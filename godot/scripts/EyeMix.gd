class_name EyeMix
extends RefCounted
## One steady "eyes left / right" number for phones, made from the three sideways eye readings the tracker gives every frame:
##   bx   the face model's own "eye look" outputs
##   x    the model's iris point between the eye corners
##   lx   our iris-edge fit inside the eye opening (the precise one on a laptop; on a phone the eye is only a few pixels wide and it jitters)
##
## Each reading is centred on its own median and divided by the size of this player's own glances, so the three are in the same units, then they are
## averaged with weights = (glance size / jitter while the eyes rest) squared. Whichever reading is steadiest FOR THIS PLAYER counts most: without
## glasses that is usually bx, with glasses the three end up closer. Nothing is fitted to a target, so it needs no calibration step.
##
## Measured on two phone recordings of the sweep test (jumping dot): jitter while looking steadily 2.2% / 3.4% of the screen (no glasses / glasses)
## against 7.4% / 11.6% for lx alone, following the dot 0.90 / 0.65 against 0.77 / 0.61. Pure logic, no engine calls.

const N := 3
const SIGN := [1.0, 1.0, -1.0]               # which way each reading grows when you look to the right of the screen
const KEEP := 900                            # readings kept per signal (about 45 s)
const MIN_STATS := 40
const OUT_UNIT := 0.03                       # one normal glance, written in the units of the iris-in-eye reading the rest of the game expects

var med: Array = [0.1, 0.5, 0.48]            # start values: typical for a phone, replaced by the player's own within a few seconds
var spread: Array = [0.4, 0.15, 0.045]
var noise: Array = [0.05, 0.02, 0.016]
var w: Array = [1.0, 0.7, 0.1]
var ready: bool = false                      # true once the numbers above are this player's own
var value: float = 0.0                       # the mix, in glances (about -1 .. +1), + = looking right
var out: float = 0.5                         # the same thing in iris-in-eye units (0.5 = centre, falls when you look right, like lx)
var _buf: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _since: int = 0
var _learned: int = 0


func reset() -> void:
	for i in N:
		(_buf[i] as PackedFloat32Array).clear()
	ready = false
	_since = 0
	_learned = 0


## One tracker frame. Pass NAN for a reading that is missing this frame (the iris-edge fit drops out when the eye is nearly shut).
func add(bx: float, x: float, lx: float) -> float:
	var v := [bx, x, lx]
	var num := 0.0
	var den := 0.0
	for i in N:
		var s := float(v[i])
		if not is_finite(s):
			continue
		var b: PackedFloat32Array = _buf[i]
		b.append(s)
		if b.size() > KEEP:
			b = b.slice(b.size() - KEEP)
		_buf[i] = b
		var wi := float(w[i])
		num += wi * float(SIGN[i]) * (s - float(med[i])) / maxf(float(spread[i]), 1.0e-4)
		den += wi
	if den > 0.0:
		value = clampf(num / den, -3.0, 3.0)
		out = 0.5 - value * OUT_UNIT
	_since += 1
	if _since >= 10:
		_since = 0
		_learn()
	return out


func _learn() -> void:
	var any := false
	for i in N:
		var b: PackedFloat32Array = _buf[i]
		if b.size() < MIN_STATS:
			continue
		any = true
		var srt := b.duplicate()
		srt.sort()
		var m := srt[srt.size() / 2]
		var dev := PackedFloat32Array()
		for s in b:
			dev.append(absf(s - m))
		dev.sort()
		var sp := maxf(dev[int(float(dev.size() - 1) * 0.9)], 1.0e-4)
		# jitter: the typical spread inside a third of a second, when the eyes are mostly at rest
		var stds := PackedFloat32Array()
		var q := 0
		while q + 6 <= b.size():
			var mu := 0.0
			for z in 6:
				mu += b[q + z]
			mu /= 6.0
			var var_ := 0.0
			for z in 6:
				var_ += (b[q + z] - mu) * (b[q + z] - mu)
			stds.append(sqrt(var_ / 6.0))
			q += 6
		stds.sort()
		var nz := maxf(stds[stds.size() / 2], 1.0e-5)
		var a := 1.0 if _learned == 0 else 0.06                    # the first estimate replaces the start values, later ones nudge (a jump here would be a jump in the steering)
		med[i] = lerpf(float(med[i]), m, a)
		spread[i] = lerpf(float(spread[i]), sp, a)
		noise[i] = lerpf(float(noise[i]), nz, a)
		var snr := clampf(float(spread[i]) / float(noise[i]), 1.0, 20.0)
		w[i] = snr * snr
	if any:
		_learned += 1
		ready = true
