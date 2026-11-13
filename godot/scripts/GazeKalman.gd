class_name GazeKalman
extends RefCounted
## One axis of the gaze point as a Kalman filter: position and velocity, in screen fractions.
##
## Why not the One Euro filter alone: the camera delivers 12-15 readings a second but the game draws 60. One Euro holds the
## last value between readings (a staircase) and has to pick between "calm when still" and "quick when moving" with two knobs.
## This one keeps a velocity, so between readings it keeps gliding the way your gaze was going (the velocity fades quickly, so
## it never runs away), and each new reading is blended in by how much we trust it against how sure we already were.
##
## Eyes do not drift, they jump (saccades): a jump of the gaze looks like a wildly wrong reading to a plain Kalman filter, which
## then lags behind it for half a second. So a reading far outside what the filter expected is held at arm's length once (it could
## be a glitch), and if the NEXT reading agrees (same side, also far), the filter snaps to the new place at once.

var r: float = 0.0025         # variance of one reading (screen fraction squared): about 5% of the screen of noise per reading
var qa: float = 1.2           # how hard the gaze can accelerate between readings (screen fractions per second squared)
var fade: float = 0.30        # seconds for the velocity to fade away when no reading confirms it
var gate: float = 2.8         # a reading this many standard deviations from the prediction is a possible jump
var min_jump: float = 0.07    # ...and at least this far in screen terms (below it, always plain filtering)

var x: float = 0.5
var v: float = 0.0
var _p00: float = 1.0
var _p01: float = 0.0
var _p11: float = 1.0
var _primed: bool = false
var _pend: float = 0.0        # a far reading waiting for confirmation
var _pend_n: int = 0
var jumps: int = 0            # how many snaps so far (tests / the report)


func reset() -> void:
	_primed = false
	_pend_n = 0
	v = 0.0


## Advance by dt seconds; `z` is the newest reading when `fresh`, otherwise only the prediction moves. Returns the estimate.
func step(z: float, dt: float, fresh: bool) -> float:
	if not _primed:
		if not fresh:
			return x
		_primed = true
		x = z
		v = 0.0
		_p00 = r
		_p01 = 0.0
		_p11 = 1.0
		return x
	dt = clampf(dt, 0.0001, 0.25)
	# predict
	var d := exp(-dt / fade)
	x += v * dt
	v *= d
	var q := qa * qa
	var q00 := q * dt * dt * dt * dt * 0.25
	var q01 := q * dt * dt * dt * 0.5
	var q11 := q * dt * dt
	var p00 := _p00 + 2.0 * dt * _p01 + dt * dt * _p11 + q00
	var p01 := d * (_p01 + dt * _p11) + q01
	var p11 := d * d * _p11 + q11
	_p00 = p00
	_p01 = p01
	_p11 = p11
	if not fresh:
		return x
	# update
	var y := z - x
	var s := _p00 + r
	var far := absf(y) > min_jump and absf(y) > gate * sqrt(s)
	var rr := r
	if far:
		if _pend_n > 0 and signf(z - x) == signf(_pend - x) and absf(z - _pend) < 0.6 * absf(y):
			# two far readings that agree: it was a real jump of the gaze
			var to := (z + _pend) * 0.5 * 0.5 + z * 0.5
			x = to
			v = 0.0
			_p00 = r
			_p01 = 0.0
			_p11 = 0.5
			_pend_n = 0
			jumps += 1
			return x
		_pend = z
		_pend_n = 1
		rr = r * 9.0                     # the first far reading only nudges
	else:
		_pend_n = 0
	s = _p00 + rr
	var k0 := _p00 / s
	var k1 := _p01 / s
	x += k0 * y
	v += k1 * y
	var n00 := _p00 - k0 * _p00
	var n01 := _p01 - k0 * _p01
	var n11 := _p11 - k1 * _p01
	_p00 = n00
	_p01 = n01
	_p11 = maxf(n11, 0.0001)
	return x
