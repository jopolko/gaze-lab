extends Node
## Headless checks for the automatic head-pose coach:  godot --headless --path . res://tests/coach_test.tscn
var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := 0.0
	var c := HeadCoach.new()
	# 10 s of good posture: pitch ~3, yaw ~-2, roll ~1, eyes open 0.33 +- noise
	for i in 150:
		t += 0.067
		c.add(3.0 + rng.randf_range(-1.5, 1.5), -2.0 + rng.randf_range(-1.5, 1.5), 1.0 + rng.randf_range(-1, 1), 0.33 + rng.randf_range(-0.015, 0.015), t)
	_check(c.ref_ok and absf(c.ref.x - 3.0) < 2.0 and absf(c.ref.y + 2.0) < 2.0, "the good pose is learned from the images alone (%.1f, %.1f, %.1f)" % [c.ref.x, c.ref.y, c.ref.z])
	_check(c.issues().is_empty() and c.quality > 0.8, "a steady good pose raises no hint (quality %.2f)" % c.quality)
	# tilt the head back 16 degrees and squint
	var msg := ""
	for i in 60:
		t += 0.067
		c.add(-13.0 + rng.randf_range(-1, 1), -2.0, 1.0, 0.22 + rng.randf_range(-0.01, 0.01), t)
		var m := c.message(t)
		if m != "" and msg == "":
			msg = m
	_check(msg.find("Chin down") >= 0, "a head tilted back gets a chin-down hint: '%s'" % msg)
	_check(c.quality < 0.5, "quality drops when the head is tilted back (%.2f)" % c.quality)
	# no nagging: another bad second does not repeat the hint within the gap
	var again := ""
	for i in 30:
		t += 0.067
		c.add(-13.0, -2.0, 1.0, 0.22, t)
		var m2 := c.message(t)
		if m2 != "":
			again = m2
	_check(again == "", "the hint is not repeated straight away")
	# back to good: a one-off 'good' event
	for i in 40:
		t += 0.067
		c.add(3.0, -2.0, 1.0, 0.33, t)
	_check(c.take_good_event() and not c.take_good_event(), "returning to a good pose fires one 'good' event")
	# turned head
	var c2 := HeadCoach.new()
	for i in 120:
		t += 0.067
		c2.add(0.0, 0.0, 0.0, 0.33 + rng.randf_range(-0.01, 0.01), t)
	for i in 30:
		t += 0.067
		c2.add(0.0, 18.0, 0.0, 0.33, t)
	_check(c2.issues().size() == 1 and c2.issues()[0]["id"] == "turn_right", "a turned head is reported")
	# seeding from a saved pose works before any data
	var c3 := HeadCoach.new()
	c3.seed(-4.0, 1.0, 0.0)
	_check(c3.ref_ok and c3.ref.x == -4.0, "a saved pose seeds the reference")
	print("RESULT: ", "ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
