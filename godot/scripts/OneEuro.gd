## One Euro filter: smooth when still, responsive when moving. Ideal for jittery
## webcam gaze. Units are screen-fractions per second.
class_name OneEuro
extends RefCounted
var min_cutoff: float = 1.4
var beta: float = 4.0
var d_cutoff: float = 1.0
var _x: float = 0.0
var _dx: float = 0.0
var _primed: bool = false

func _alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)

func filter(v: float, dt: float) -> float:
	if not _primed:
		_primed = true
		_x = v
		return v
	dt = maxf(dt, 0.0001)
	_dx = lerpf(_dx, (v - _x) / dt, _alpha(d_cutoff, dt))
	_x = lerpf(_x, v, _alpha(min_cutoff + beta * absf(_dx), dt))
	return _x

func reset() -> void:
	_primed = false
