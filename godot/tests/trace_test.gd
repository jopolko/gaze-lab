extends Node
## Headless checks for the TRACE test:  godot --headless --path . res://tests/trace_test.tscn
## A fake pair of eyes follows the dot with a known delay and a known gain; the analysis must read those back.
var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Runs a whole trace in simulated time. The cursor follows the dot `delay_s` late, scaled by `gain` about the middle, with a little noise.
func _run(rig: RunRig, delay_s: float, gain: float, noise: float) -> void:
	var dt := 1.0 / 60.0
	var vs := get_viewport().get_visible_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hist: Array = []
	rig._trace_start()
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	var guard := 0
	while rig._tr_phase != 4 and guard < 20000:
		guard += 1
		var b := rig._tr_bead
		hist.append(b)
		var di := maxi(hist.size() - 1 - int(round(delay_s / dt)), 0)
		var bb: Vector2 = hist[di]
		rig._cursor_px = Vector2((0.5 + (bb.x - 0.5) * gain + rng.randfn(0.0, noise)) * vs.x, (bb.y + rng.randfn(0.0, noise)) * vs.y)
		rig._physics_process(dt)
		rig._trace_tick(dt)
		if hist.size() > 400:
			hist.pop_front()


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = true
	level.load_level(11)
	await _frames(5)
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)

	await _run(rig, 0.10, 1.0, 0.004)
	var res: Dictionary = rig._tr_res
	_check(not res.is_empty() and rig._tr_phase == 4, "a full trace runs through all phases to the results")
	var fo: Dictionary = res["follow"]
	var jp: Dictionary = res["jump"]
	_check(fo["samples"] > 600, "FOLLOW collected samples (%d)" % int(fo["samples"]))
	_check(float(fo["r"]) > 0.95, "FOLLOW: an eye that tracks the dot correlates (r %.2f)" % float(fo["r"]))
	_check(absi(int(fo["lagMs"]) - 100) <= 40, "FOLLOW: a 100 ms delay reads back as about 100 ms (%d ms)" % int(fo["lagMs"]))
	_check(absf(float(fo["gain"]) - 1.0) < 0.08, "FOLLOW: gain 1.0 reads back as 1.0 (%.2f)" % float(fo["gain"]))
	_check(int(jp["reactMs"]) >= 60 and int(jp["reactMs"]) <= 260, "JUMP: reaction time reads back near the delay (%d ms)" % int(jp["reactMs"]))
	_check(float(jp["landErr"]) < 0.03 and int(jp["missed"]) <= 1, "JUMP: lands on the dot (%.1f%% off, %d missed)" % [float(jp["landErr"]) * 100.0, int(jp["missed"])])
	_check(res.has("carve") and res.has("tracker") and res.has("tune") and not rig._tr_lines.is_empty(), "the report has carve, tracker and tune sections and result lines")

	await _run(rig, 0.30, 0.7, 0.004)
	res = rig._tr_res
	fo = res["follow"]
	_check(absi(int(fo["lagMs"]) - 300) <= 50, "a 300 ms delay reads back as about 300 ms (%d ms)" % int(fo["lagMs"]))
	_check(absf(float(fo["gain"]) - 0.7) < 0.08, "a gaze that moves only 0.7 as far reads back as 0.7 (%.2f)" % float(fo["gain"]))
	var tn: Dictionary = res["tune"]
	_check(absf(float(tn["suggestReach"]) / float(tn["reach"]) - 1.0 / 0.7) < 0.15, "and the suggested reach is about 1/0.7 of the current one (%.2f -> %.2f)" % [float(tn["reach"]), float(tn["suggestReach"])])

	# the signal fit: dot = 0.5 + 6*iris (iris noisy), head carries the dot too (clean): the combination must beat either alone
	var syn: Array = []
	var rs := RandomNumberGenerator.new()
	rs.seed = 9
	for i in 600:
		var dx := 0.5 + 0.3 * sin(float(i) * 0.05)
		var iris := (dx - 0.5) / 6.0 + rs.randfn(0.0, 0.02)
		var head := (dx - 0.5) * 0.4 + rs.randfn(0.0, 0.03)
		syn.append(PackedFloat32Array([0.0, dx, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, iris, head, 0.5, 0.0]))
	var f_i: Dictionary = rig._tr_ols(syn, 1, [8], 0)
	var f_h: Dictionary = rig._tr_ols(syn, 1, [9], 0)
	var f_b: Dictionary = rig._tr_ols(syn, 1, [8, 9], 0)
	_check(float(f_b["err"]) < float(f_i["err"]) and float(f_b["err"]) < float(f_h["err"]), "signal fit: iris+head errs less than either alone (%.3f vs %.3f / %.3f)" % [float(f_b["err"]), float(f_i["err"]), float(f_h["err"])])
	var f_l: Dictionary = rig._tr_ols(syn, 1, [8], 7)
	_check(float(f_l["r"]) < float(f_i["r"]), "signal fit: a wrong delay fits worse (r %.2f vs %.2f)" % [float(f_l["r"]), float(f_i["r"])])

	# a stale centre: the whole iris reading shifts (head moved, light changed). The eyes-only offset must recover, not stay pinned.
	rig._restart()
	rig._ex_init = false
	rig._ex_raw.clear()
	rig._ex_full = 0.02
	GazeProvider.eih_ok = true
	var ers := RandomNumberGenerator.new()
	ers.seed = 4
	var last := 0.0
	for i in 120:
		GazeProvider.eih = Vector2(-0.50 + ers.randfn(0.0, 0.002), 0.0)
		last = rig._eyes_only_offs(1.0 / 60.0, 0.0)
	var bad := 0.0
	for i in 60 * 8:
		GazeProvider.eih = Vector2(-0.50 - 0.20 + ers.randfn(0.0, 0.002), 0.0)       # shifted by 0.2, far beyond any glance
		last = rig._eyes_only_offs(1.0 / 60.0, 0.0)
		if i == 60:
			bad = last
	_check(absf(last) < 0.15 and absf(rig._ex_ref - 0.70) < 0.02,"a shifted iris reading re-centres (after 1 s %.2f, after 8 s %.2f)" % [bad, last])
	GazeProvider.eih_ok = false

	rig._trace_end()
	_check(not rig.trace_on and not rig.autopilot, "ending the trace gives the board back")

	# ---- safety: a slide uphill or backward is turned back downhill, and the start line is a wall
	var dt := 1.0 / 60.0
	rig.vel = Vector2(4.0, 12.0)
	rig.grounded = true
	for i in 120:
		rig._physics_process(dt)
	_check(rig.vel.y < 0.0 and rig.spos.z <= 0.0, "a backward slide cannot run uphill (vel.y %.1f, z %.1f)" % [rig.vel.y, rig.spos.z])
	rig._restart()
	rig.vel = Vector2(-9.0, 0.0)          # pure sideways slide after a hit
	for i in 180:
		rig._physics_process(dt)
	_check(rig.vel.y < -3.0 or rig.spos.z < -5.0, "a sideways slide is carried downhill, not along the slope's side (z %.1f)" % rig.spos.z)

	# ---- safety: a flailing look is softened
	rig._restart()
	var out := 0.0
	for i in 60:
		var s := 1.0 if (i / 5) % 2 == 0 else -1.0
		out = rig._guard_gaze(s, 0.05)
	_check(rig._flail_t > 0.0 and absf(out) <= 0.31, "a look that keeps flipping side to side is softened (steer %.2f)" % out)
	_check(not rig._ev.is_empty(), "and the event is in the report (%s)" % str(rig._ev.back()))
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
