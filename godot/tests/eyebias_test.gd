extends Node
## Headless checks for the automatic gaze offset:  godot --headless --path . res://tests/eyebias_test.tscn
var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var true_c := Vector2(0.5, 0.46)

	# a constant offset (optical-axis angle, camera position) is learned from play alone
	var b := EyeBias.new()
	var off := Vector2(0.12, -0.08)
	var final_err := 0.0
	for i in 900:
		var fix := true_c + Vector2(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.12, 0.12))
		var raw := fix + off + Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))
		b.add(raw.x, raw.y, 0.0, 0.2)
		if i > 700:
			final_err += (b.apply(raw.x, raw.y, 0.0, 0.2) - fix).length()
	final_err /= 199.0
	_check(final_err < 0.045, "a constant gaze offset is learned from play alone (error %.3f, was %.3f)" % [final_err, off.length()])

	# head tilted back changes the vertical reading: it is learned against head pitch
	var b2 := EyeBias.new()
	var b3 := EyeBias.new()
	var err_with := 0.0
	var err_without := 0.0
	var n := 0
	for i in 2400:
		var pitch := 0.22 * sin(float(i) / 170.0)
		var fix := true_c + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1))
		var raw := fix + Vector2(0.05, 0.04 + 0.45 * pitch) + Vector2(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.015, 0.015))
		b2.add(raw.x, raw.y, pitch, 0.2)
		b3.add(raw.x, raw.y, pitch, 0.2)
		b3.k_pitch = 0.0              # the same learner with the pitch link switched off
		if i > 1800:
			err_with += absf(b2.apply(raw.x, raw.y, pitch, 0.2).y - fix.y)
			err_without += absf(b3.apply(raw.x, raw.y, pitch, 0.2).y - fix.y)
			n += 1
	err_with /= float(n)
	err_without /= float(n)
	_check(err_with < err_without * 0.7 and absf(b2.k_pitch + 0.45) < 0.2, "tilting the head back is learned: pitch correction %.2f (true -0.45), vertical error %.3f vs %.3f without it" % [b2.k_pitch, err_with, err_without])

	# squint (eyelid aperture) also moves the vertical reading
	var b4 := EyeBias.new()
	var err4 := 0.0
	var n4 := 0
	for i in 2400:
		var ap := 0.22 + 0.08 * sin(float(i) / 140.0)
		var fix := true_c + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1))
		var raw := fix + Vector2(0.0, -0.9 * (ap - 0.22)) + Vector2(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.015, 0.015))
		b4.add(raw.x, raw.y, 0.0, ap)
		if i > 1800:
			err4 += absf(b4.apply(raw.x, raw.y, 0.0, ap).y - fix.y)
			n4 += 1
	err4 /= float(n4)
	_check(err4 < 0.045 and b4.k_aper > 0.4, "squint is learned: aperture correction %.2f, vertical error %.3f" % [b4.k_aper, err4])

	# the signal moves far less than the screen does (a physical scale that is too optimistic): the range is learned
	var b8 := EyeBias.new()
	b8.exp_span = Vector2(0.54, 0.0)
	var b9 := EyeBias.new()                 # same data, scaling off
	var err_s := 0.0
	var err_n := 0.0
	var ns := 0
	for i in 1800:
		var fix := true_c + Vector2(rng.randf_range(-0.3, 0.3), 0.0)
		var raw := true_c + Vector2(0.45 * (fix.x - true_c.x) + 0.1, 0.0) + Vector2(rng.randf_range(-0.01, 0.01), 0.0)
		raw.y = 0.46
		b8.add(raw.x, raw.y, 0.0, 0.2)
		b9.add(raw.x, raw.y, 0.0, 0.2)
		if i > 1400:
			err_s += absf(b8.apply(raw.x, raw.y, 0.0, 0.2).x - fix.x)
			err_n += absf(b9.apply(raw.x, raw.y, 0.0, 0.2).x - fix.x)
			ns += 1
	err_s /= float(ns)
	err_n /= float(ns)
	_check(b8.scale.x > 1.6 and err_s < 0.05 and err_n > 0.08, "a signal that moves too little is stretched to the screen: scale x%.2f, error %.3f (%.3f without)" % [b8.scale.x, err_s, err_n])
	var b10 := EyeBias.new()
	b10.exp_span = Vector2(0.6, 0.0)
	for i in 900:
		b10.add(0.5 + rng.randf_range(-0.01, 0.01), 0.46, 0.0, 0.2)
	_check(b10.scale.x <= EyeBias.SCALE_MAX + 0.001, "staring at one spot cannot amplify noise past the limit (x%.2f)" % b10.scale.x)

	# eyes reach one side more easily than the other: each side is stretched on its own
	var b11 := EyeBias.new()
	b11.exp_span = Vector2(0.54, 0.0)
	var err_l := 0.0
	var err_r := 0.0
	var err_r_sym := 0.0
	var nl := 0
	var nr := 0
	for i in 2400:
		var d := rng.randf_range(-0.3, 0.3)
		var raw := true_c + Vector2(d * (0.9 if d < 0.0 else 0.4), 0.0) + Vector2(rng.randf_range(-0.008, 0.008), 0.0)
		raw.y = 0.46
		b11.add(raw.x, raw.y, 0.0, 0.2)
		if i > 1800:
			var got := b11.apply(raw.x, raw.y, 0.0, 0.2).x
			var sym := true_c.x + (raw.x + b11.bias.x - true_c.x) * b11.scale_lo.x      # one shared scale (the left side's)
			if d < 0.0:
				err_l += absf(got - (true_c.x + d))
				nl += 1
			else:
				err_r += absf(got - (true_c.x + d))
				err_r_sym += absf(sym - (true_c.x + d))
				nr += 1
	err_l /= float(nl)
	err_r /= float(nr)
	err_r_sym /= float(nr)
	_check(err_l < 0.05 and err_r < 0.05 and err_r_sym > err_r * 1.6, "a side that reaches less is stretched more: right error %.3f vs %.3f with one shared scale, left %.3f" % [err_r, err_r_sym, err_l])

	# an anchor (a blink on an orb, the CENTER button) corrects it immediately
	var b5 := EyeBias.new()
	b5.anchor(Vector2(0.62, 0.38), 0.0, 0.2, Vector2(0.5, 0.46), 1.0)
	var pinned := b5.apply(0.62, 0.38, 0.0, 0.2)
	_check(pinned.distance_to(Vector2(0.5, 0.46)) < 0.01, "an anchor pins the gaze to the known point at once")

	# never outside the screen
	var wild := b.apply(5.0, -3.0, 0.0, 0.2)
	var wild2 := b.apply(-5.0, 9.0, 0.0, 0.2)
	_check(wild.x == 1.0 and wild.y == 0.0 and wild2.x == 0.0 and wild2.y == 1.0, "the gaze point can never leave the screen")

	# a head turned far away (not frontal) does not train it
	var b6 := EyeBias.new()
	for i in 300:
		b6.add(0.9, 0.9, 1.2, 0.2)
	_check(b6.windows_used == 0 and b6.bias == Vector2.ZERO, "a badly turned face does not teach the offset")

	# no learning when the mode is not active
	var b7 := EyeBias.new()
	for i in 300:
		b7.add(0.9, 0.9, 0.0, 0.2, false)
	_check(b7.windows_used == 0, "nothing is learned outside a game mode")
	# staring at one spot must not amplify noise: without exp_span the scale stays 1; with it, a tight spread is stretched up to 3x (the old lane-mode bug)
	var b_flat := EyeBias.new()
	var b_stretch := EyeBias.new()
	b_stretch.exp_span = Vector2(0.6, 0.0)
	for i in 400:
		var u := 0.5 + rng.randf_range(-0.015, 0.015)
		b_flat.add(u, 0.46, 0.0, 0.2)
		b_stretch.add(u, 0.46, 0.0, 0.2)
	_check(b_flat.scale_lo.x == 1.0 and b_flat.scale_hi.x == 1.0, "without exp_span a steady stare keeps scale 1.0 (lane mode)")
	_check(b_stretch.scale_hi.x > 2.0, "with exp_span the same stare would be stretched %.1fx (why lane mode turns it off)" % b_stretch.scale_hi.x)
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
