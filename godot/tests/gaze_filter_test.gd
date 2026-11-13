extends Node
## Headless checks for the Kalman gaze filter and the one-pass sweep calibration:
##   godot --headless --path . res://tests/gaze_filter_test.tscn
var _fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1


## Simulated gaze: fixations with jumps between them, read 14 times a second with noise (and the odd wild reading), drawn at 60 Hz.
func _sim(use_kalman: bool, sigma: float, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var kf := GazeKalman.new()
	var oe := OneEuro.new()
	var truth := 0.5
	var fix_left := 0.0
	var since := 0.0
	var held := 0.5
	var t := 0.0
	var next_read := 0.0
	var se := 0.0
	var n := 0
	var settle := 0.0
	var settles := 0
	var got := false
	var dt := 1.0 / 60.0
	for i in 60 * 90:
		t += dt
		fix_left -= dt
		since += dt
		if fix_left <= 0.0:
			var tgt := rng.randf_range(0.08, 0.92)
			if absf(tgt - truth) < 0.15:
				tgt = clampf(truth + 0.3 * (1.0 if rng.randf() < 0.5 else -1.0), 0.08, 0.92)
			truth = tgt
			fix_left = rng.randf_range(0.5, 1.4)
			since = 0.0
			got = false
		var fresh := false
		if t >= next_read:
			next_read = t + 1.0 / 14.0
			var nz := rng.randfn(0.0, sigma)
			if rng.randf() < 0.04:
				nz += 0.3 * (1.0 if rng.randf() < 0.5 else -1.0)
			held = truth + nz
			fresh = true
		var e: float = kf.step(held, dt, fresh) if use_kalman else oe.filter(held, dt)
		if not got and absf(e - truth) < 0.08:
			got = true
			settle += since
			settles += 1
		if since > 0.5:
			se += (e - truth) * (e - truth)
			n += 1
	return {"rms": sqrt(se / n), "settle": settle / maxf(settles, 1), "jumps": kf.jumps}


func _ready() -> void:
	# ---- Kalman filter
	var ks := _sim(true, 0.05, 3)
	var os := _sim(false, 0.05, 3)
	_check(float(ks["rms"]) < 0.6 * float(os["rms"]), "Kalman holds a fixation steadier than One Euro (error %.3f vs %.3f of the screen)" % [ks["rms"], os["rms"]])
	_check(float(ks["settle"]) < 0.3, "...and still follows a jump of the gaze within %.2f s (One Euro %.2f s)" % [ks["settle"], os["settle"]])
	var kf := GazeKalman.new()
	for i in 30:
		kf.step(0.2, 1.0 / 60.0, i % 4 == 0)
	var pre := kf.x
	kf.step(0.8, 1.0 / 60.0, true)                       # one far reading: held at arm's length
	var after_one := kf.x
	for i in 4:
		kf.step(0.8, 1.0 / 60.0, false)
	kf.step(0.8, 1.0 / 60.0, true)                       # the next agrees: snap
	_check(absf(after_one - pre) < 0.12 and absf(kf.x - 0.8) < 0.1 and kf.jumps == 1, "one wild reading barely moves it, a second one agreeing snaps to the new place (%.2f -> %.2f -> %.2f)" % [pre, after_one, kf.x])
	var kg := GazeKalman.new()
	for i in 20:
		kg.step(0.1 + 0.02 * i, 1.0 / 14.0, true)       # moving steadily right
	var edge := kg.x
	for i in 90:
		kg.step(0.0, 1.0 / 60.0, false)                 # then the camera stalls for 1.5 s
	_check(absf(kg.x - edge) < 0.08, "with no new reading it glides a little and stops, it does not run away (%.2f -> %.2f)" % [edge, kg.x])

	# ---- the sweep path
	_check(EyeSweep.duration() > 3.0 and EyeSweep.duration() < 5.0, "the sweep lasts %.1f s" % EyeSweep.duration())
	var lo := Vector2(1.0, 1.0)
	var hi := Vector2.ZERO
	var t := 0.0
	while t < EyeSweep.duration():
		var p := EyeSweep.dot(t)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		t += 0.05
	_check(lo.x <= 0.11 and hi.x >= 0.89 and lo.y <= 0.11 and hi.y >= 0.89, "the dot reaches both edges and both top and bottom (%.2f..%.2f, %.2f..%.2f)" % [lo.x, hi.x, lo.y, hi.y])

	# ---- fitting: eyes read u = (x - ax) / sx, delayed 0.2 s behind the dot, with noise, blinks and wrong readings
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sx_true := 1.7
	var sy_true := 2.4
	var ox := 0.58
	var oy := 0.31
	var samples: Array = []
	t = 0.0
	while t < EyeSweep.duration() + 0.3:
		var d := EyeSweep.dot(t - 0.2)
		var u := (d.x - 0.5) / sx_true + ox + rng.randfn(0.0, 0.02)
		var v := (d.y - 0.5) / sy_true + oy + rng.randfn(0.0, 0.02)
		if rng.randf() < 0.1:
			u += rng.randf_range(-0.3, 0.3)
			v += rng.randf_range(-0.3, 0.3)
		samples.append([t, u, v])
		t += 1.0 / 14.0
	var f := EyeSweep.fit(samples)
	var ex := 1.0 / sx_true
	_check(bool(f["ok"]) and absf(float(f["sx"]) - sx_true) < 0.2 * sx_true and absf(float(f["sy"]) - sy_true) < 0.2 * sy_true, "the sweep recovers the screen scale from noisy readings (x %.2f vs %.2f, y %.2f vs %.2f, %d readings)" % [f["sx"], sx_true, f["sy"], sy_true, samples.size()])
	_check(absf(float(f["lag"]) - 0.2) <= 0.06, "...and finds how far behind the dot your eyes are (%.2f s vs 0.20)" % f["lag"])
	var b := EyeBias.new()
	b.set_linear(f["ax"], f["sx"], f["ay"], f["sy"])
	var worst := 0.0
	for k in 40:
		var p := EyeSweep.dot(EyeSweep.duration() * k / 40.0)
		var u2 := (p.x - 0.5) / sx_true + ox
		var v2 := (p.y - 0.5) / sy_true + oy
		worst = maxf(worst, (b.apply(u2, v2, 0.0, 0.2) - p).length())
	_check(worst < 0.06, "after the sweep the corrected gaze lands on the dot all the way round (worst miss %.3f of the screen)" % worst)
	var b2 := EyeBias.new()
	b2.exp_span = Vector2(0.6, 0.0)
	b2.set_linear(f["ax"], f["sx"], f["ay"], f["sy"])
	var before := b2.scale_lo
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 8
	for i in 600:
		b2.add(0.5 + rng2.randf_range(-0.01, 0.01), 0.3, 0.0, 0.2)       # then you stare at one spot for a while
	_check(b2.scale_lo.is_equal_approx(before), "a measured scale is not re-stretched from how much you happen to look around (x%.2f stays x%.2f)" % [b2.scale_lo.x, before.x])

	# ---- bad sweeps are refused
	var still: Array = []
	t = 0.0
	while t < EyeSweep.duration():
		still.append([t, 0.5 + rng.randfn(0.0, 0.01), 0.4 + rng.randfn(0.0, 0.01)])
		t += 1.0 / 14.0
	_check(not bool(EyeSweep.fit(still)["ok"]), "eyes that never moved do not make a calibration (%s)" % EyeSweep.fit(still)["why"])
	var junk: Array = []
	t = 0.0
	while t < EyeSweep.duration():
		junk.append([t, rng.randf(), rng.randf()])
		t += 1.0 / 14.0
	_check(not bool(EyeSweep.fit(junk)["ok"]), "random readings do not make a calibration (%s)" % EyeSweep.fit(junk)["why"])
	_check(not bool(EyeSweep.fit(samples.slice(0, 10))["ok"]), "too few readings do not make a calibration")

	# ---- the tuning session: the verdict per barrier, the lit gate, the cycle of settings
	_check(GazeTune.classify(true, 0.6, 0.6, 5.0) == "followed", "through the lit gate with the gaze on it = followed")
	_check(GazeTune.classify(true, 0.02, 0.02, 5.0) == "assist", "through the lit gate with the gaze never on it = the game's help, not the eyes")
	_check(GazeTune.classify(false, 0.7, 0.8, 5.0) == "looked-not-followed", "gaze and cursor on the gate, but the board went elsewhere = the game failed to follow")
	_check(GazeTune.classify(false, 0.05, 0.7, 5.0) == "cursor-lost-it", "tracker on the gate, the game's cursor not = the correction lost it")
	_check(GazeTune.classify(false, 0.0, 0.05, 5.0) == "never-reached" and GazeTune.classify(false, 0.9, 0.9, 0.4) == "n/a", "neither on the gate = never reached; too short an approach is not scored")
	var tn := GazeTune.new()
	tn.start()
	var gaps3: Array = [{"x": 5.0}, {"x": -20.0}, {"x": 30.0}]
	var picked: Array = []
	for i in 3:
		picked.append(tn.pick_target(gaps3))
		tn.trial_i += 1
	tn.trial_i = 0
	_check(picked == [1, 2, 0], "the lit gate goes left-most, right-most, middle in turn (%s)" % str(picked))
	_check(tn.pick_target(gaps3, [0, 1]) in [0, 1] and tn.pick_target(gaps3, [2]) == -1 and tn.pick_target(gaps3, []) >= 0, "a gate that is off screen is never lit, and a barrier with fewer than two gates in view is not lit at all")
	_check(GazeProvider.kal_on and not GazeProvider.hold_on, "session starts on the default setting")
	for i in GazeTune.PER:
		tn.record({"verdict": "followed", "look_cur": 0.5, "aim_t": 1.0})
	_check(tn.config_name() == "no Kalman" and not GazeProvider.kal_on, "after %d barriers the next setting is applied (%s)" % [GazeTune.PER, tn.config_name()])
	while tn.active:
		tn.record({"verdict": "never-reached" if tn.config_index() == 2 else "followed", "look_cur": 0.4, "aim_t": 1.0})
	_check(tn.done and tn.summary.size() == GazeTune.CONFIGS.size() and int(tn.summary[0]["followed"]) == GazeTune.PER and int(tn.summary[2]["never_reached"]) == GazeTune.PER, "the summary counts each kind per setting")
	_check(tn.best != "" and tn.best != "fixation hold", "the best setting is not the one that never reached (%s)" % tn.best)
	GazeProvider.opts_default()

	# ---- AUTO: explore every setting, keep the best, challenge it now and then
	var tl := GazeTune.new()
	tl.loop = true
	tl.start()
	while tl.phase == "explore":
		tl.record({"verdict": "followed" if tl.config_index() == 3 else "never-reached", "look_cur": 0.5, "aim_t": 1.0})
	_check(tl.phase == "exploit" and tl.best == "gaze zones pick" and tl.active and not tl.done and tl.note != "", "AUTO tries every setting, then settles on the best and keeps going (%s)" % tl.best)
	_check(GazeProvider.opt_pick == 1, "...and that setting is the one switched on")
	_check(tl.should_light(0) and not tl.should_light(1), "while using the best, every second barrier is lit")
	for i in GazeTune.EXPLOIT_N:
		tl.record({"verdict": "followed", "look_cur": 0.5, "aim_t": 1.0})
	_check(tl.phase == "challenge" and tl.config_name() != "gaze zones pick" and tl.should_light(1), "after a while a challenger is tried (%s)" % tl.config_name())
	for i in GazeTune.PER * 2:
		tl.record({"verdict": "never-reached", "look_cur": 0.0, "aim_t": -1.0})
	_check(tl.phase == "exploit" and tl.best == "gaze zones pick" and GazeProvider.opt_pick == 1 and tl.note.contains("did not beat"), "a challenger that does worse is dropped and the best setting comes back")
	for i in GazeTune.EXPLOIT_N:
		tl.record({"verdict": "never-reached", "look_cur": 0.0, "aim_t": -1.0})
	var chal_name := tl.config_name()
	for i in GazeTune.PER * 2:
		tl.record({"verdict": "followed", "look_cur": 0.5, "aim_t": 1.0})
	_check(tl.phase == "exploit" and tl.best == chal_name and tl.note.contains("beat"), "when the best setting stops working and a challenger does, the challenger takes over (%s)" % tl.best)
	GazeProvider.opts_default()
	# the health sample and the rules
	GazeProvider._h_ft = PackedFloat32Array([16.0, 16.0, 40.0, 16.0])
	GazeProvider.backend = GazeProvider.Backend.MOUSE
	GazeProvider._health_sample()
	_check(int(GazeProvider.health["gameFps"]) >= 0 and float(GazeProvider.health["frameP95ms"]) >= 16.0 and GazeProvider.health.has("trackerFps"), "the health sample reports frame rate, p95 frame time and tracker rate")
	GazeProvider.auto_on = true
	GazeProvider.health = {"trackerFps": 6.0, "jitterOut": 0.03, "spanX": 0.5, "gameFps": 60, "frameP95ms": 17.0}
	GazeProvider._auto_rules()
	_check(GazeProvider.geo_win == 3 and GazeProvider.hold_on, "AUTO rules: a slow tracker shortens the median, a jittery gaze point turns the fixation hold on")
	GazeProvider.health = {"trackerFps": 14.0, "jitterOut": 0.004, "spanX": 0.5, "gameFps": 60, "frameP95ms": 17.0}
	GazeProvider._auto_rules()
	_check(GazeProvider.geo_win == 5 and not GazeProvider.hold_on, "...and both go back when the tracker recovers and the gaze settles")
	GazeProvider.auto_on = false
	GazeProvider.opts_default()
	GazeProvider.backend = GazeProvider.Backend.MOUSE

	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
