class_name Saccades
extends RefCounted
## Real looks versus noise, in a slow, noisy, lopsided signal (a webcam iris reading at 10 to 15 frames a second).
## Noise spread evenly around the true gaze averages out. A look is different: a jump one way that SETTLES somewhere new. So a jump is accepted only if it carries on
## the same way for two frames in a row and clears a threshold that grows with how jittery YOUR signal is. A one-frame spike that comes back (a blink, a glance down, a
## glitch) is counted and thrown away. Each accepted jump is an event with a direction and a size, usable as intent: "he looked right, now".

var base: float = 0.0                 # where the look has been resting: the median of the recent calm frames
var jitter: float = 0.006             # how far a calm reading wanders from `base`, smoothed (the noise floor of this device and light)
var min_amp: float = 0.012            # the smallest jump ever believed
var k: float = 3.0                    # jumps must clear k * jitter
var refractory: float = 0.22          # seconds after a jump during which no new one is accepted (the eye is still arriving)
var last_dir: float = 0.0             # -1 left, +1 right
var last_t: float = -10.0
var last_amp: float = 0.0             # size in units of the threshold (1 = barely, 3 = a decisive look)
var events: int = 0
var spikes: int = 0                   # one-frame excursions that came back: noise, not looks
var frames: int = 0
var accepted: int = 0                # every look ever accepted (never goes down, even when one is later taken back)
var confirmed: int = 0               # looks that stayed long enough to be certain
var retracted: int = 0                # looks that were accepted and then taken back: the reading went home within a moment (a blink, a glitch)

var _hist: Array = []                 # [t, x] recent readings
var _pend_dir: float = 0.0
var _pend_t: float = -10.0
var _seeded: bool = false
var _prev_base: float = 0.0
var _acc_t: float = -10.0
var _confirmed: bool = true


func threshold() -> float:
	return maxf(k * jitter, min_amp)


## Feed one fresh reading. Returns +1 / -1 on the frame a look is accepted, else 0.
func push(t: float, x: float) -> float:
	frames += 1
	if not _seeded:
		base = x
		_seeded = true
	_hist.append([t, x])
	if _hist.size() > 8:
		_hist.remove_at(0)
	var thr := threshold()
	var d := x - base
	var out := 0.0
	if not _confirmed:
		if t - _acc_t > 0.45:
			_confirmed = true                                    # it stayed: a real look
			confirmed += 1
		elif absf(x - _prev_base) < 0.6 * thr:
			events -= 1                                          # it went straight back where it came from: not a look after all
			retracted += 1
			base = _prev_base
			last_t = -10.0
			_confirmed = true
			return 0.0
	if absf(d) > thr and t - last_t > refractory:
		var dir := signf(d)
		if _pend_dir == dir and t - _pend_t < 0.45:
			# the second frame in a row beyond the threshold on the same side: that is a look
			out = dir
			last_dir = dir
			last_t = t
			last_amp = absf(d) / thr
			events += 1
			accepted += 1
			_prev_base = base
			_acc_t = t
			_confirmed = false
			base = x
			_pend_dir = 0.0
		else:
			_pend_dir = dir
			_pend_t = t
	else:
		if _pend_dir != 0.0 and absf(d) <= thr:
			spikes += 1                                          # it went out for a frame and came straight back
			_pend_dir = 0.0
		# calm frame: the resting point follows slowly, and the noise floor is re-learned from how far readings wander
		base += (x - base) * 0.08
		jitter = clampf(lerpf(jitter, absf(d), 0.04), 0.002, 0.03)
	return out


## True from the moment a look is accepted until it has stayed long enough to be certain (or has been taken back).
func pending() -> bool:
	return not _confirmed


func recent(window: float, now: float) -> bool:
	return now - last_t < window


func reset() -> void:
	base = 0.0
	jitter = 0.006
	last_dir = 0.0
	last_t = -10.0
	last_amp = 0.0
	events = 0
	spikes = 0
	frames = 0
	retracted = 0
	accepted = 0
	confirmed = 0
	_prev_base = 0.0
	_acc_t = -10.0
	_confirmed = true
	_hist.clear()
	_pend_dir = 0.0
	_seeded = false
