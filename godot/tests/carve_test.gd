extends Node
## Headless checks for CARVE:  godot --headless --path . res://tests/carve_test.tscn
var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _hold(ms: int, gaze: Vector2) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		GazeProvider.set_scripted(gaze)
		await get_tree().physics_frame
		await get_tree().process_frame


## The gaze that puts the reticle at screen fraction x (the reticle is your gaze relative to your own centre, times the reach).
func _gaze_for(rig: CarveRig, x_frac: float) -> float:
	return clampf(rig._ref_x + (x_frac - 0.5) / rig.reach, 0.0, 1.0)


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
	var rig: CarveRig = level._dh as CarveRig
	_check(rig != null and Game.carve_mode and Game.downhill_mode and rig.cam.current, "carve rig starts, owns the camera")
	_check(rig.lane_ctl == 2, "gaze steering is continuous (STEER)")
	_check(not rig._rows.is_empty() and rig._chunks.size() >= 5, "course and terrain chunks exist (%d segments)" % rig._rows.size())

	# ---- the course: every barrier has a clear safe opening, and it never moves further than a carve can follow
	rig.set_physics_process(false)
	rig._restart()
	for j in range(rig._next_j, 52):
		rig._gen_segment(j)
	var worst_clear := 99.0
	var worst_jump := 0.0
	var prev_good := 0.0
	var n_rows := 0
	var n_open := 0
	var prev_z := 0.0
	var worst_ratio := 0.0
	for j in range(CarveRig.START_CALM, 50):
		var r: Dictionary = rig._rows[j]
		if not r["has_row"]:
			continue
		n_rows += 1
		var good: Dictionary = {}
		for g in r["gaps"]:
			n_open += 1
			if g["good"]:
				good = g
		var obs: PackedFloat32Array = r["obs"]
		var i := 0
		while i < obs.size():
			if absf(obs[i + 1] - float(r["z"])) < 4.0:
				worst_clear = minf(worst_clear, absf(obs[i] - float(good["x"])) - obs[i + 2] - DownhillRig.SLED_R - float(good["w"]) * 0.0)
			i += 4
		if n_rows > 1:
			worst_jump = maxf(worst_jump, absf(float(good["x"]) - prev_good))
			worst_ratio = maxf(worst_ratio, absf(float(good["x"]) - prev_good) / maxf(prev_z - float(r["z"]), 1.0))
		prev_good = float(good["x"])
		prev_z = float(r["z"])
	_check(n_rows >= 40 and n_open > n_rows, "barriers with several openings (%d barriers, %d openings)" % [n_rows, n_open])
	_check(worst_clear > 2.2, "the safe opening is wide enough to drive through (clear half width %.1f m)" % worst_clear)
	_check(worst_ratio <= 0.31, "the safe opening drifts at most 0.3 m sideways per metre downhill (%.2f)" % worst_ratio)
	var first: Dictionary = rig._rows[CarveRig.START_CALM]
	_check(float(first["z"]) < -150.0, "the first %d segments are open snow (first barrier at %.0f m)" % [CarveRig.START_CALM, -float(first["z"])])
	var finish_row := -1
	for j in rig._rows:
		if float((rig._rows[j] as Dictionary)["z0"]) > CarveRig.FINISH_Z and float((rig._rows[j] as Dictionary)["z0"]) - DownhillRig.ROW_GAP <= CarveRig.FINISH_Z:
			finish_row = j
	_check(finish_row >= 0 and not (rig._rows[finish_row]["nodes"] as Array).is_empty(), "a finish line is built (segment %d)" % finish_row)

	# ---- a full run with the autopilot: no crash, it speeds up, the finish line ends it
	rig._restart()
	rig.autopilot = true
	var dt := 1.0 / 60.0
	var v500 := 0.0
	var v3500 := 0.0
	var steps := 0
	while not rig._finished and steps < 20000:
		rig._physics_process(dt)
		steps += 1
		if v500 == 0.0 and rig.spos.z < -500.0:
			v500 = rig.vel.length()
		if v3500 == 0.0 and rig.spos.z < -3500.0:
			v3500 = rig.vel.length()
	rig.autopilot = false
	_check(rig._finished, "the autopilot reaches the finish (%d m, %.0f s)" % [int(-rig.spos.z), rig._run_t])
	_check(rig.crashes == 0, "and does it without a crash (%d crashes: %s)" % [rig.crashes, str(rig.crash_log)])
	_check(v3500 > v500 + 8.0, "the hill pulls faster the further you go (%.0f m/s at 500 m, %.0f m/s at 3500 m)" % [v500, v3500])
	_check(rig.score >= 1000 and rig.rows_passed >= 35, "a clean run scores (%d points, %d barriers)" % [rig.score, rig.rows_passed])
	var z_end := rig.spos.z
	for i in 240:
		rig._physics_process(dt)
	_check(rig.vel.length() < 6.0 and rig.spos.z < z_end, "after the finish the board coasts to a stop (%.1f m/s)" % rig.vel.length())
	rig._restart()
	_check(not rig._finished and rig.crashes == 0 and rig.spos.z > -1.0 and rig._rows.size() >= 5 and rig.vel.length() > 5.0, "restart gives a fresh run")

	# ---- obstacles are solid: driving into a tree wipes you out and costs speed
	var obs_row: Dictionary = {}
	for j in rig._rows:
		if rig._rows[j]["has_row"]:
			obs_row = rig._rows[j]
			break
	var ox := 0.0
	var oz := 0.0
	var oi := 0
	var ob: PackedFloat32Array = obs_row["obs"]
	while oi < ob.size():
		if ob[oi + 3] < 0.5 and absf(ob[oi + 1] - float(obs_row["z"])) < 4.0:
			ox = ob[oi]
			oz = ob[oi + 1]
			break
		oi += 4
	rig.spos = Vector3(ox, rig.terrain_h(ox, oz + 6.0), oz + 6.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -25.0)
	rig.heading = 0.0
	rig.hurt_t = 0.0
	rig.grounded = true
	rig.avoid_enabled = false            # the wipeout itself is tested here; the board's own care for trees is tested below
	rig.gate_assist = false
	for i in 40:
		rig._physics_process(dt)
	_check(rig.crashes >= 1 and rig.vel.length() < 14.0, "hitting a tree is a wipeout (%d crashes, %.1f m/s left)" % [rig.crashes, rig.vel.length()])
	rig.avoid_enabled = true
	rig.gate_assist = true
	rig._restart()

	# ---- the board looks after itself: a lone tree dead ahead is swerved around just enough; a wall is crossed through a gate
	var arz := 0.0
	var arow2: Dictionary = {}
	for j in rig._rows:
		if rig._rows[j]["has_row"]:
			arow2 = rig._rows[j]
			arz = float(arow2["z"])
			break
	var tree_z := arz + 45.0
	var tobs: PackedFloat32Array = arow2["obs"]
	tobs.append_array(PackedFloat32Array([0.0, tree_z, 1.0, 0.0]))
	arow2["obs"] = tobs
	arow2["zmax"] = maxf(float(arow2["zmax"]), tree_z + 6.0)
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, arz + 90.0), arz + 90.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -25.0)
	rig.heading = 0.0
	rig.hurt_t = 0.0
	rig.grounded = true
	var c0 := rig.crashes
	var min_d := 99.0
	var max_dev := 0.0
	var st := 0
	while rig.spos.z > tree_z - 6.0 and st < 600:
		st += 1
		rig._physics_process(dt)
		min_d = minf(min_d, Vector2(rig.spos.x, rig.spos.z - tree_z).length())
		max_dev = maxf(max_dev, absf(rig.spos.x))
	_check(rig.crashes == c0 and min_d >= 2.0, "a tree dead ahead is avoided (closest %.1f m, %d crashes)" % [min_d, rig.crashes - c0])
	_check(max_dev < 6.0 and rig.swerves >= 1, "and it swerves only as much as needed (%.1f m sideways, %d swerve)" % [max_dev, rig.swerves])

	# a wall: aim the board at the thickest part of the barrier; it must go through a gate, not into the trees
	var wx := 0.0
	var wbest := -1.0
	for xi in range(-40, 41, 2):
		var dm := 99.0
		for g in arow2["gaps"]:
			dm = minf(dm, absf(float(xi) - float(g["x"])) - float(g["w"]) * 0.5)
		if dm > wbest:
			wbest = dm
			wx = float(xi)
	rig._restart()
	arow2 = {}
	for j in rig._rows:
		if rig._rows[j]["has_row"]:
			arow2 = rig._rows[j]
			arz = float(arow2["z"])
			break
	rig.spos = Vector3(wx, rig.terrain_h(wx, arz + 100.0), arz + 100.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -26.0)
	rig.heading = 0.0
	rig.hurt_t = 0.0
	rig.grounded = true
	c0 = rig.crashes
	var p0 := rig._passed_ok
	st = 0
	while rig.spos.z > arz - 9.0 and st < 900:
		st += 1
		rig._physics_process(dt)
	_check(rig.crashes == c0 and rig._passed_ok == p0 + 1, "aimed at the middle of a wall (x %.0f, %.0f m from a gate) it still goes through a gate (%d crashes, %d barriers scored)" % [wx, wbest, rig.crashes - c0, rig._passed_ok - p0])

	# hands off completely: the board alone should get a long way down the hill (the eyes then choose which gates)
	rig._restart()
	rig.vel = Vector2(0.0, -16.0)
	st = 0
	while rig.spos.z > -1500.0 and st < 14000:
		st += 1
		rig._physics_process(dt)
	print("hands off: %d barriers, %d crashes, %d swerves over %.0f m" % [rig._passed_ok, rig.crashes, rig.swerves, -rig.spos.z])
	_check(rig.crashes <= 4, "with no input at all it makes it down 1500 m with few crashes (%d)" % rig.crashes)
	rig._restart()

	# ---- steering from the eyes: a steady gaze goes straight, a look aside carves that way, then straightens
	rig.set_physics_process(true)
	rig.aim_enabled = false              # this block checks the raw look-trim on its own; the opening choice is tested below
	rig.gate_assist = false
	rig.avoid_enabled = false
	rig.vel = Vector2(0.0, -20.0)
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 5
	var t_a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_a < 3500:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		rig.spos.x = 0.0        # nothing to hit while the steering settles
	_check(absf(rig._steer_gaze) < 0.35 and absf(rig.heading) < 0.4, "a steady look at the middle goes straight (steer %.2f, heading %.2f)" % [rig._steer_gaze, rig.heading])
	var t_b := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_b < 900:
		GazeProvider.set_scripted(Vector2(clampf(0.58 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		rig.spos.x = clampf(rig.spos.x, -10.0, 10.0)
	_check(rig._steer_gaze > 0.4 and rig.heading > 0.25, "a look to the right carves right (steer %.2f, heading %.2f)" % [rig._steer_gaze, rig.heading])
	var t_c := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_c < 900:
		GazeProvider.set_scripted(Vector2(clampf(0.42 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		rig.spos.x = clampf(rig.spos.x, -10.0, 10.0)
	_check(rig._steer_gaze < -0.4 and rig.heading < -0.25, "a look to the left carves left (steer %.2f, heading %.2f)" % [rig._steer_gaze, rig.heading])
	await _hold(1800, Vector2(0.5, 0.45))
	_check(absf(rig.heading) < 0.4, "looking back at the middle straightens the board (heading %.2f)" % rig.heading)

	# ---- aim: an opening you keep looking at latches; a glance does not; looking away lets go
	rig.aim_enabled = true
	rig.gate_assist = true
	rig.avoid_enabled = true
	rig.set_physics_process(false)
	rig._restart()
	var arow: Dictionary = {}
	for j in range(CarveRig.START_CALM, 12):
		if rig._rows.has(j) and rig._rows[j]["has_row"]:
			arow = rig._rows[j]
			break
	var vs := get_viewport().get_visible_rect().size
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, float(arow["z"]) + 90.0), float(arow["z"]) + 90.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -20.0)
	rig._place_camera(1.0, true)
	await get_tree().process_frame
	var gaps: Array = arow["gaps"]
	var good: Dictionary = {}
	for g in gaps:
		if g["good"]:
			good = g
	var sc: Dictionary = rig._gap_screen(arow, good)
	var cx: float = float(sc["c"].x) / vs.x
	_check(not sc.is_empty() and cx > 0.02 and cx < 0.98, "the safe opening is on screen (%.0f%% across)" % (cx * 100.0))
	await _hold(800, Vector2(_gaze_for(rig, 0.97 if cx < 0.5 else 0.03), 0.45))      # start from a look well away from the opening
	rig._update_aim(0.016)
	_check(not is_same(rig._aim, good), "the opening is not latched before you look at it")
	# a glance of 0.08 s does not latch
	await _hold(80, Vector2(_gaze_for(rig, cx), 0.45))
	var glance_latched: bool = is_same(rig._aim, good)
	await _hold(700, Vector2(rig._ref_x, 0.45))
	_check(not glance_latched, "a split-second glance does not latch an opening")
	await _hold(700, Vector2(_gaze_for(rig, cx), 0.45))
	_check(is_same(rig._aim, good) and rig._aim_w > 0.1, "looking at an opening for a moment latches it (pull %.2f)" % rig._aim_w)
	await _hold(500, Vector2(_gaze_for(rig, cx), 0.45))
	var want_sign := signf(float(good["x"]) - rig.spos.x)
	_check(rig._aim_w > 0.9 and (absf(rig._aim_want) < 0.01 or signf(rig._aim_want) == want_sign), "the latched opening pulls the board toward it (pull %.2f, want %+.2f)" % [rig._aim_w, rig._aim_want])
	await _hold(900, Vector2(_gaze_for(rig, 0.97 if cx < 0.5 else 0.03), 0.45))
	_check(not is_same(rig._aim, good), "looking elsewhere lets go of it")
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# ---- closed loop with noisy eyes: aim at the safe opening with a webcam's jitter, delay and 15 Hz readings; the board must still get through
	var vsz := get_viewport().get_visible_rect().size
	for sigma in [0.0, 0.05, 0.09, 0.14]:
		rig.set_physics_process(false)
		rig.aim_enabled = true
		rig._restart()
		await get_tree().process_frame
		rig.vel = Vector2(0.0, -16.0)
		var srng := RandomNumberGenerator.new()
		srng.seed = 11
		var held := 0.5
		var cur := 0.5
		var queue: Array = []
		var dt2 := 1.0 / 60.0
		var steps2 := 0
		var start_pass: int = rig._passed_ok
		var start_cr: int = rig.crashes
		while rig.spos.z > -1500.0 and steps2 < 9000:
			steps2 += 1
			# where the safe opening of the next barrier is on screen
			var target := 0.5
			for kk2 in rig._rows:
				var r2: Dictionary = rig._rows[kk2]
				if not r2["has_row"] or r2["passed"]:
					continue
				var d2: float = rig.spos.z - float(r2["z"])
				if d2 < 14.0 or d2 > 190.0:
					continue
				for g2 in r2["gaps"]:
					if g2["good"]:
						var sc2: Dictionary = rig._gap_screen(r2, g2)
						if not sc2.is_empty():
							target = float(sc2["c"].x) / vsz.x
				break
			if steps2 % 4 == 0:
				held = target + srng.randfn(0.0, sigma)        # a new, noisy reading 15 times a second
			queue.append(held)
			if queue.size() > 9:
				cur = lerpf(cur, float(queue.pop_front()), 1.0 - exp(-dt2 / 0.07))      # 150 ms late, then the 70 ms look smoothing
			rig._cursor_px = Vector2(cur * vsz.x, 0.45 * vsz.y)
			rig._steer_gaze = clampf((cur - 0.5) / (rig._steer_scale * rig._zone_scale), -1.0, 1.0)
			rig._update_aim(dt2)
			rig._physics_process(dt2)
			rig._place_camera(dt2, false)
		print("noisy eyes sigma %.2f: %d barriers, %d crashes, %d m" % [sigma, rig._passed_ok - start_pass, rig.crashes - start_cr, int(-rig.spos.z)])
		if sigma == 0.09:
			_check(rig.crashes - start_cr <= 4, "with 9%% screen jitter on the eyes the board still gets through most barriers (%d crashes over %d m, %d barriers)" % [rig.crashes - start_cr, int(-rig.spos.z), rig._passed_ok - start_pass])
		if sigma == 0.0:
			_check(rig.crashes - start_cr <= 1, "with clean eyes aimed at the safe opening it runs (%d crashes over %d m)" % [rig.crashes - start_cr, int(-rig.spos.z)])
	# ---- a human at full speed: the whole 4200 m, eyes decide late (45-120 m out), noisy, and sometimes pick a wrong gate
	var tot_cr := {0.0: 0, 0.3: 0}
	var tot_bar := {0.0: 0, 0.3: 0}
	for hcase in 6:
		var p_wrong: float = 0.0 if hcase < 3 else 0.3
		rig.set_physics_process(false)
		rig.aim_enabled = true
		rig._restart()
		await get_tree().process_frame
		rig.vel = Vector2(0.0, -16.0)
		var hrng := RandomNumberGenerator.new()
		hrng.seed = 21 + hcase % 3
		var picks: Dictionary = {}
		var late: Dictionary = {}
		var hheld := 0.5
		var hcur := 0.5
		var hq: Array = []
		var hsteps := 0
		var h_pass: int = rig._passed_ok
		var h_cr: int = rig.crashes
		var h_wrong := 0
		while not rig._finished and hsteps < 16000:
			hsteps += 1
			var htarget := 0.5
			for kk3 in rig._rows:
				var r3: Dictionary = rig._rows[kk3]
				if not r3["has_row"] or r3["passed"]:
					continue
				var d3: float = rig.spos.z - float(r3["z"])
				if d3 < 3.0 or d3 > 190.0:
					continue
				var j3: int = int(r3["j"])
				if not picks.has(j3):
					var chosen3: Dictionary = {}
					var others: Array = []
					for g3 in r3["gaps"]:
						if g3["good"]:
							chosen3 = g3
						else:
							others.append(g3)
					if not others.is_empty() and hrng.randf() < p_wrong:
						chosen3 = others[hrng.randi() % others.size()]
						h_wrong += 1
					picks[j3] = chosen3
					late[j3] = hrng.randf_range(45.0, 120.0)
				if d3 <= float(late[j3]):
					var sc3: Dictionary = rig._gap_screen(r3, picks[j3])
					if not sc3.is_empty():
						htarget = float(sc3["c"].x) / vsz.x
				break
			if hsteps % 4 == 0:
				hheld = htarget + hrng.randfn(0.0, 0.09)
			hq.append(hheld)
			if hq.size() > 9:
				hcur = lerpf(hcur, float(hq.pop_front()), 1.0 - exp(-(1.0 / 60.0) / 0.07))
			rig._cursor_px = Vector2(hcur * vsz.x, 0.45 * vsz.y)
			rig._steer_gaze = clampf((hcur - 0.5) / (rig._steer_scale * rig._zone_scale), -1.0, 1.0)
			rig._update_aim(1.0 / 60.0)
			rig._physics_process(1.0 / 60.0)
			rig._place_camera(1.0 / 60.0, false)
		print("human p_wrong %.1f: %d barriers scored, %d crashes, %d wrong picks, %d m, %.0f s, score %d" % [p_wrong, rig._passed_ok - h_pass, rig.crashes - h_cr, h_wrong, int(-rig.spos.z), rig._run_t, rig.score])
		tot_cr[p_wrong] += rig.crashes - h_cr
		tot_bar[p_wrong] += rig._passed_ok - h_pass
		for cl in rig.crash_log:
			print("    crash: ", cl)
	print("human totals over 3 runs each: clean eyes %d crashes, %d barriers   |   30%% wrong picks %d crashes, %d barriers" % [tot_cr[0.0], tot_bar[0.0], tot_cr[0.3], tot_bar[0.3]])
	_check(tot_cr[0.0] <= 3 and tot_cr[0.3] <= 8, "a full 4200 m run with late, noisy, sometimes wrong gate choices stays nearly crash free (%d / %d crashes over 3 runs each)" % [tot_cr[0.0], tot_cr[0.3]])
	rig.set_physics_process(true)

	# ---- leaving restores the player camera
	level.load_level(6)
	await _frames(5)
	_check(not Game.carve_mode and not Game.downhill_mode and level._dh == null and level.player.camera.current, "leaving carve restores the player camera")
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
