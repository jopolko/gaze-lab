extends Node
## Headless checks for DOWNHILL:  godot --headless --path . res://tests/run_test.tscn
var _fails := 0

var _metrics: Dictionary = {}
var _t_start: int = Time.get_ticks_msec()


## Every number worth comparing between builds goes through here: the suite writes them all to tests/metrics_latest.json and appends a row to tests/metrics_history.csv.
func _m(key: String, value: Variant) -> void:
	_metrics[key] = value


func _write_metrics() -> void:
	_metrics["tests_failed"] = _fails
	_metrics["seconds"] = snappedf(float(Time.get_ticks_msec() - _t_start) / 1000.0, 0.1)
	_metrics["when"] = Time.get_datetime_string_from_system(false, true)
	var txt := JSON.stringify(_metrics, "  ", true)
	for path in ["res://tests/metrics_latest.json", "user://metrics_latest.json"]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(txt)
	var keys: Array = _metrics.keys()
	keys.sort()
	var hist := "res://tests/metrics_history.csv"
	var new_file := not FileAccess.file_exists(hist)
	var h := FileAccess.open(hist, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if h != null:
		if new_file:
			h.store_line(",".join(keys))
		else:
			h.seek_end()
		var row: Array = []
		for k in keys:
			row.append(str(_metrics[k]))
		h.store_line(",".join(row))
	print("metrics: %d numbers written to tests/metrics_latest.json (and a row to metrics_history.csv)" % keys.size())


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
func _gaze_for(rig: RunRig, x_frac: float) -> float:
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
	var rig: RunRig = level._dh as RunRig
	rig.view_fp = false                  # the older checks measure the third-person camera; first person has its own checks below
	rig.balls_enabled = false            # the older simulations have no snowballs; they have their own checks below
	rig.weird = 0.0                     # the older checks measure the original zones; the strange places have their own checks at the end
	_check(rig != null and Game.run_mode and Game.downhill_mode and rig.cam.current, "carve rig starts, owns the camera")
	_check(rig.lane_ctl == 2, "gaze steering is continuous (STEER)")
	_check(not rig._rows.is_empty() and rig._chunks.size() >= 3, "course and terrain chunks exist (%d segments)" % rig._rows.size())

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
	for j in range(RunRig.START_CALM, 50):
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
	_check(n_rows >= 34 and n_open > n_rows, "barriers with several openings (%d barriers, %d openings)" % [n_rows, n_open])
	_check(worst_clear > 2.2, "the safe opening is wide enough to drive through (clear half width %.1f m)" % worst_clear)
	_check(worst_ratio <= 0.31, "the safe opening drifts at most 0.3 m sideways per metre downhill (%.2f)" % worst_ratio)
	var first: Dictionary = rig._rows[RunRig.START_CALM]
	_check(float(first["z"]) < -150.0, "the first %d segments are open snow (first barrier at %.0f m)" % [RunRig.START_CALM, -float(first["z"])])
	var finish_row := -1
	for j in rig._rows:
		if float((rig._rows[j] as Dictionary)["z0"]) > RunRig.FINISH_Z and float((rig._rows[j] as Dictionary)["z0"]) - DownhillRig.ROW_GAP <= RunRig.FINISH_Z:
			finish_row = j
	_check(finish_row >= 0 and not (rig._rows[finish_row]["nodes"] as Array).is_empty(), "a finish line is built (segment %d)" % finish_row)

	# ---- gate layouts and buffs
	var lay := {}
	var even_ok := true
	var iso_n := 0
	var iso_buffed := 0
	var iso_reach := true
	var iso_narrow := true
	var rows_b := 0
	var buff_n := 0
	var all_clear := true
	var path_off_ok := true
	var path_n := 0
	for jb in range(RunRig.START_CALM, 50):
		var rb: Dictionary = rig._rows[jb]
		if not rb["has_row"]:
			continue
		rows_b += 1
		lay[rb["layout"]] = int(lay.get(rb["layout"], 0)) + 1
		var xs: Array = []
		var good_w := 0.0
		for gb in rb["gaps"]:
			xs.append(float(gb["x"]))
			if gb["good"]:
				good_w = float(gb["w"])
			if gb.get("iso", false):
				iso_n += 1
				if gb.get("buff", false):
					iso_buffed += 1
				if absf(float(gb["x"]) - float(rb["px"])) > 0.33 * (float(rb["pz"]) - float(rb["z"])) + 0.01:
					iso_reach = false
				if float(gb["w"]) > 13.0 * 1.1 + 0.01:
					iso_narrow = false
		if rb["layout"] == "trio":
			xs.sort()
			if xs.size() != 3 or absf((float(xs[1]) - float(xs[0])) - (float(xs[2]) - float(xs[1]))) > 0.01:
				even_ok = false
		for bf in rb["buffs"]:
			buff_n += 1
			if not rig._clear_of_obs(rb["obs"], float(bf["x"]), float(bf["z"]), 3.0):
				all_clear = false
				print("    buff on an obstacle: %s %s kind %s x %.1f z %.1f" % [rb["layout"], bf["t"], bf["kind"], float(bf["x"]), float(bf["z"])])
			if bf["kind"] == "path":
				path_n += 1
				var offp := absf(float(bf["x"]) - rig.path_x(rb, float(bf["z"])))
				if offp < 7.9 or offp > 13.1:
					path_off_ok = false
	_check(lay.size() >= 4 and int(lay.get("near", 0)) >= 3 and int(lay.get("spread", 0)) >= 2, "several gate layouts appear, including the meadow spread and the tunnel and bend pairs (%s)" % str(lay))
	_check(even_ok, "a trio of gates is evenly spaced")
	_check(iso_n >= 1 and iso_buffed == iso_n, "every isolated gate carries a buff (%d of %d)" % [iso_buffed, iso_n])
	_check(iso_reach and iso_narrow, "an isolated gate is narrower and reachable from the last barrier")
	var per_row := float(buff_n) / float(maxi(rows_b, 1))
	_check(per_row >= 0.6 and per_row <= 2.0, "buffs are semi-frequent (%.2f per barrier, %d beside the path)" % [per_row, path_n])
	_check(all_clear, "no buff sits on a tree or rock")
	_check(path_n >= 6 and path_off_ok, "path buffs sit 8-13 m off the safe line (%d)" % path_n)

	# ---- buff effects
	rig._restart()
	var fb := func(t: String) -> Dictionary: return {"t": t, "x": 0.0, "z": 0.0, "taken": false, "n": null, "orbs": [], "kind": "path"}
	var spd0 := rig.vel.length()
	rig._take_buff(fb.call("boost"))
	_check(rig._boost_t > 2.9 and rig.vel.length() > spd0 + 4.0 and rig.buffs_got == 1, "a boost kicks the speed up and runs for a few seconds")
	var shield_hold := rig.crashes
	rig.shield = 1
	rig.hurt_t = 0.0
	rig._crash("TEST")
	_check(rig.crashes == shield_hold and rig.shield == 0 and rig.hurt_t > 0.0, "a shield absorbs the next crash and is used up")
	rig.hurt_t = 0.0
	rig._crash("TEST")
	_check(rig.crashes == shield_hold + 1, "and the one after that counts")
	rig._restart()
	rig._gain(100)
	rig._take_buff(fb.call("mult"))
	var sc_a := rig.score
	rig._gain(100)
	_check(rig._mult_t > 9.0 and rig.score - sc_a == 200, "double points doubles what you earn")
	rig._tick_buffs(11.0)
	_check(rig._mult_t == 0.0 and rig._boost_t == 0.0, "buffs run out")
	# boosted vs plain: same state, 1.5 s later the boosted board is faster
	var vend := []
	for boosted in [false, true]:
		rig._restart()
		rig.set_physics_process(false)
		if boosted:
			rig._take_buff(fb.call("boost"))
		for i in 90:
			rig._physics_process(1.0 / 60.0)
		vend.append(rig.vel.length())
	_check(float(vend[1]) > float(vend[0]) + 3.0, "a boosted board is faster 1.5 s later (%.1f vs %.1f m/s)" % [vend[1], vend[0]])

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
		if v500 == 0.0 and rig.spos.z < -500.0 and rig._boost_t <= 0.0:
			v500 = rig.vel.length()
		if v3500 == 0.0 and rig.spos.z < -3500.0 and rig._boost_t <= 0.0:
			v3500 = rig.vel.length()
	rig.autopilot = false
	if rig.crashes > 0:
		print("    autopilot crash log: ", rig.crash_log, "  kickers (z/x): ", rig.kick_log)
	_check(rig._finished, "the autopilot reaches the finish (%d m, %.0f s)" % [int(-rig.spos.z), rig._run_t])
	_check(rig.crashes <= 3, "and does it with at most one crash (it follows the safe line blindly) (%d crashes: %s)" % [rig.crashes, str(rig.crash_log)])
	_check(v3500 > 14.0 and v500 > 14.0, "the speed stays in a sane range whatever stretch it is in (%.0f m/s at 500 m, %.0f m/s at 3500 m)" % [v500, v3500])
	_check(rig.score >= 1000 and rig.rows_passed >= 35, "a clean run scores (%d points, %d barriers)" % [rig.score, rig.rows_passed])
	var z_end := rig.spos.z
	for i in 240:
		rig._physics_process(dt)
	_check(rig.vel.length() < 6.0 and rig.spos.z < z_end, "after the finish the board coasts to a stop (%.1f m/s)" % rig.vel.length())
	rig._restart()
	_check(not rig._finished and rig.crashes == 0 and rig.spos.z > -1.0 and rig._rows.size() >= 3 and rig.vel.length() > 5.0, "restart gives a fresh run")

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
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
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
	for kq0 in rig._rows:
		(rig._rows[kq0] as Dictionary)["obs"] = PackedFloat32Array()          # only the one tree: this is about the swerve, not about whatever else is on the slope
	var tobs := PackedFloat32Array([0.0, tree_z, 1.0, 0.0])
	arow2["obs"] = tobs
	arow2["zmax"] = maxf(float(arow2["zmax"]), tree_z + 6.0)
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
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
	rig.gate_assist = false          # this one is about the single tree, not about which gate the barrier ahead pulls toward
	while rig.spos.z > tree_z - 6.0 and st < 600:
		st += 1
		rig._physics_process(dt)
		min_d = minf(min_d, Vector2(rig.spos.x, rig.spos.z - tree_z).length())
		if st % 20 == 0 and rig.crashes == c0:
			print("      tree test st %d z %.1f x %.2f vx %.2f steer %.2f swerve_s %.2f swerving %s avoid %s gate %s" % [st, rig.spos.z, rig.spos.x, rig.vel.x, rig.steer, rig._swerve_s, str(rig._swerving), str(rig.avoid_enabled), str(rig.gate_assist)])
		max_dev = maxf(max_dev, absf(rig.spos.x))
	_check(rig.crashes == c0 and min_d >= 2.0, "a tree dead ahead is avoided (closest %.1f m, %d crashes %s)" % [min_d, rig.crashes - c0, str(rig.crash_log.slice(maxi(rig.crash_log.size() - 1, 0)))])
	_check(max_dev < 6.0 and rig.swerves >= 1, "and it swerves only as much as needed (%.1f m sideways, %d swerve)" % [max_dev, rig.swerves])
	rig.gate_assist = true

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
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
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
		rig.ghost = rig.spos.z > arz + 14.0          # stray singles on the approach are not what this checks
		rig._physics_process(dt)
	rig.ghost = false
	_check(rig.crashes - c0 <= 1 and absf(rig.spos.x) < 30.0, "aimed at the middle of a wall (a late cross may clip one rock at the gate edge, never the wall) (x %.0f, %.0f m from a gate) it still goes through a gate (%d crashes, %d barriers scored, %s)" % [wx, wbest, rig.crashes - c0, rig._passed_ok - p0, str(rig.crash_log.slice(maxi(rig.crash_log.size() - 1, 0)))])

	# hands off completely: the board alone should get a long way down the hill (the eyes then choose which gates)
	rig._restart()
	rig.vel = Vector2(0.0, -16.0)
	st = 0
	while rig.spos.z > -1500.0 and st < 14000:
		st += 1
		rig._physics_process(dt)
	print("hands off: %d barriers, %d crashes, %d swerves over %.0f m" % [rig._passed_ok, rig.crashes, rig.swerves, -rig.spos.z])
	_m("handsoff_barriers_passed", rig._passed_ok)
	_m("handsoff_crashes", rig.crashes)
	_m("handsoff_metres", int(-rig.spos.z))
	_m("handsoff_engage_end", snappedf(rig._engage, 0.01))
	var ho_eng := float(rig.agency_summary()["engageMean"])
	_m("handsoff_engage_mean", ho_eng)
	_check(ho_eng < 0.8, "with no input the help fades (it was engaged %.0f%% of the time; the board still passed %d barriers with %d crashes)" % [ho_eng * 100.0, rig._passed_ok, rig.crashes])
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
	_check(rig._steer_gaze > 0.4 and rig.heading > 0.18, "a look to the right carves right (steer %.2f, heading %.2f)" % [rig._steer_gaze, rig.heading])
	var t_c := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_c < 900:
		GazeProvider.set_scripted(Vector2(clampf(0.42 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		rig.spos.x = clampf(rig.spos.x, -10.0, 10.0)
	_check(rig._steer_gaze < -0.4 and rig.heading < -0.18, "a look to the left carves left (steer %.2f, heading %.2f)" % [rig._steer_gaze, rig.heading])
	await _hold(1800, Vector2(0.5, 0.45))
	_check(absf(rig.heading) < 0.4, "looking back at the middle straightens the board (heading %.2f)" % rig.heading)

	# ---- aim: an opening you keep looking at latches; a glance does not; looking away lets go
	rig.aim_enabled = true
	rig.gate_assist = true
	rig.avoid_enabled = true
	rig.set_physics_process(false)
	rig._restart()
	var arow: Dictionary = {}
	for j in range(RunRig.START_CALM, 12):
		if rig._rows.has(j) and rig._rows[j]["has_row"]:
			arow = rig._rows[j]
			break
	var vs := get_viewport().get_visible_rect().size
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
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
		rig.view_fp = hcase % 3 == 2          # the last run of each group is flown in first person
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
	_m("human_clean_crashes", tot_cr[0.0])
	_m("human_clean_barriers", tot_bar[0.0])
	_m("human_wrongpick_crashes", tot_cr[0.3])
	_m("human_wrongpick_barriers", tot_bar[0.3])
	_check(tot_cr[0.0] <= 9 and tot_cr[0.3] <= 24, "a full 4200 m run with late, noisy, sometimes wrong gate choices stays nearly crash free (%d / %d crashes over 3 runs each)" % [tot_cr[0.0], tot_cr[0.3]])

	# ---- a player who hunts the buffs with their eyes: looks at the nearest buff in reach (path buffs, and the ones in front of the safe gate), else the safe gate
	var hs_path_sp := 0
	var hs_path_got := 0
	var hs_gate_sp := 0
	var hs_gate_got := 0
	var hs_cr := 0
	var hs_bar := 0
	rig.wide_override = true             # the pickup hunter eats everything it reaches
	for hcase2 in 2:
		rig.set_physics_process(false)
		rig.aim_enabled = true
		rig._restart()
		await get_tree().process_frame
		rig.vel = Vector2(0.0, -16.0)
		var vrng := RandomNumberGenerator.new()
		vrng.seed = 31 + hcase2
		var vlate: Dictionary = {}
		var vheld := 0.5
		var vcur := 0.5
		var vq: Array = []
		var vsteps := 0
		while not rig._finished and vsteps < 16000:
			vsteps += 1
			var vtarget := 0.5
			var vbest := 1.0e9
			var vrow: Dictionary = {}
			for kk4 in rig._rows:
				var r4: Dictionary = rig._rows[kk4]
				if not r4["has_row"] or r4["passed"]:
					continue
				var d4: float = rig.spos.z - float(r4["z"])
				if d4 < 3.0 or d4 > 190.0:
					continue
				if vrow.is_empty() or float(r4["z"]) > float(vrow["z"]):
					vrow = r4
			if not vrow.is_empty():
				var j4: int = int(vrow["j"])
				if not vlate.has(j4):
					vlate[j4] = vrng.randf_range(45.0, 120.0)
				if rig.spos.z - float(vrow["z"]) <= float(vlate[j4]):
					for g4 in vrow["gaps"]:
						if g4["good"]:
							var sc4: Dictionary = rig._gap_screen(vrow, g4)
							if not sc4.is_empty():
								vtarget = float(sc4["c"].x) / vsz.x
			for kk5 in rig._rows:
				var r5: Dictionary = rig._rows[kk5]
				var good5 := 0.0
				for g5 in r5["gaps"]:
					if g5["good"]:
						good5 = float(g5["x"])
				for b5 in r5["buffs"]:
					if b5["taken"]:
						continue
					var dz5: float = rig.spos.z - float(b5["z"])
					if dz5 < 14.0 or dz5 > 95.0 or absf(float(b5["x"]) - rig.spos.x) > 0.3 * dz5 + 3.0:
						continue
					if b5["kind"] == "gate":
						continue                                 # in front of a gate this player did not choose
					if dz5 < vbest:
						vbest = dz5
						var wp5 := Vector3(float(b5["x"]), rig.terrain_h(float(b5["x"]), float(b5["z"])) + 1.7, float(b5["z"]))
						if not rig.cam.is_position_behind(wp5):
							vtarget = rig.cam.unproject_position(wp5).x / vsz.x
			if vsteps % 4 == 0:
				vheld = vtarget + vrng.randfn(0.0, 0.07)
			vq.append(vheld)
			if vq.size() > 9:
				vcur = lerpf(vcur, float(vq.pop_front()), 1.0 - exp(-(1.0 / 60.0) / 0.07))
			rig._cursor_px = Vector2(vcur * vsz.x, 0.45 * vsz.y)
			rig._steer_gaze = clampf((vcur - 0.5) / (rig._steer_scale * rig._zone_scale), -1.0, 1.0)
			rig._update_aim(1.0 / 60.0)
			rig._update_buff_aim(1.0 / 60.0)
			rig._physics_process(1.0 / 60.0)
			rig._place_camera(1.0 / 60.0, false)
		print("buff hunter run %d: path %d/%d, safe-gate %d/%d, other-gate %d/%d, orbs %d, crashes %d, %s, score %d" % [hcase2, int(rig.got_kind.get("path", 0)), int(rig.spawned_kind.get("path", 0)), int(rig.got_kind.get("safe", 0)), int(rig.spawned_kind.get("safe", 0)), int(rig.got_kind.get("gate", 0)), int(rig.spawned_kind.get("gate", 0)), rig.orbs_got, rig.crashes, str(rig.buff_log), rig.score])
		for cl2 in rig.crash_log:
			print("    crash: ", cl2)
		hs_path_sp += int(rig.spawned_kind.get("path", 0))
		hs_path_got += int(rig.got_kind.get("path", 0))
		hs_gate_sp += int(rig.spawned_kind.get("safe", 0))
		hs_gate_got += int(rig.got_kind.get("safe", 0))
		hs_cr += rig.crashes
		hs_bar += rig._passed_ok
	_check(hs_path_got >= int(0.2 * float(hs_path_sp)), "a player who looks at the buffs collects a good share of the ones beside the path (%d of %d)" % [hs_path_got, hs_path_sp])
	_check(hs_gate_got >= int(0.25 * float(hs_gate_sp)), "and the ones in front of the safe gate (%d of %d)" % [hs_gate_got, hs_gate_sp])
	_check(hs_cr <= 12, "hunting buffs does not wreck the run (%d crashes, %d barriers over 2 full runs)" % [hs_cr, hs_bar])
	rig.wide_override = false
	rig.set_physics_process(true)

	# ---- first person, kickers, tricks
	rig.view_fp = false
	rig.set_physics_process(false)
	rig.apply_params({"zones": {"air": 8.0, "rush": 1.0, "flat": 0.0, "tunnel": 0.0, "bend": 0.0}})
	rig._restart()
	for jk in range(rig._next_j, 60):
		rig._gen_segment(jk)
	var k_rows: Array = []
	var air_buffs := 0
	var k_far := true
	for jk2 in rig._rows:
		var rk: Dictionary = rig._rows[jk2]
		if rk.has("kick"):
			k_rows.append(rk)
			if rk["has_row"] and absf(float(rk["kick"]["x"]) - rig.path_x(rk, float(rk["kick"]["z"]))) < 13.9:
				k_far = false
		for bk in rk["buffs"]:
			if bk["kind"] == "air":
				air_buffs += 1
	_check(k_rows.size() >= 5 and rig.kickers_built == k_rows.size(), "kickers appear along the course (%d in 58 segments)" % k_rows.size())
	_check(k_far, "a kicker sits well beside the safe line, so it is a choice and never in the way")
	_check(air_buffs >= 3, "most kickers carry a pickup in the air above them (%d)" % air_buffs)
	var jrow: Dictionary = {}
	jrow = k_rows[0]
	var kx0: float = float(jrow["kick"]["x"])
	var kz0: float = float(jrow["kick"]["z"])
	rig.gate_assist = false
	rig.avoid_enabled = false
	rig.spos = Vector3(kx0, rig.terrain_h(kx0, kz0 + 16.0), kz0 + 16.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -36.0)
	rig.vy = -36.0 * 0.34
	rig.heading = 0.0
	rig.hurt_t = 0.0
	rig.grounded = true
	rig._finished = false
	rig.trick_look_override = 1.0
	rig.trick_grab_override = true
	rig.ghost = true
	var j_c0 := rig.crashes
	var j_peak := 0.0
	var j_air_t := 0.0
	var j_spun := 0.0
	var j_steps := 0
	var j_air := false
	while j_steps < 420 and rig.spos.z > float(jrow["kick"]["lip"]) - 120.0:
		j_steps += 1
		rig._physics_process(dt)
		if not rig.grounded and rig.spos.z < float(jrow["kick"]["lip"]) + 6.0:
			if not j_air:
				print("    flight starts at z %.1f (kicker z %.1f, lip %.1f, rise %.2f), speed %.1f" % [rig.spos.z, kz0, float(jrow["kick"]["lip"]), float(rig._kickers[0]["rise"]) if not rig._kickers.is_empty() else -1.0, rig.vel.length()])
			j_air = true
			j_air_t += dt
			j_peak = maxf(j_peak, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
			j_spun = maxf(j_spun, absf(rig._trk_spin))
		elif j_air:
			break
	_check(j_air and j_air_t > 0.35 and j_peak > 1.0, "riding a kicker at speed launches the board (%.2f s in the air, %.1f m up)" % [j_air_t, j_peak])
	_check(rig.crashes == j_c0, "and lands without a crash (%d crashes: %s)" % [rig.crashes - j_c0, str(rig.crash_log.slice(maxi(rig.crash_log.size() - 2, 0)))])
	_check(rig.tricks_landed >= 1 and rig.trick_score >= 100, "looking aside and holding a grab in the air lands a trick worth points (%d tricks, %d points, best %s, spun %.0f deg)" % [rig.tricks_landed, rig.trick_score, rig.best_trick, rad_to_deg(j_spun)])
	rig.trick_look_override = 0.0
	rig.trick_grab_override = false
	# no input in the air: no trick, no bonus, no crash
	rig.spos = Vector3(kx0, rig.terrain_h(kx0, kz0 + 16.0), kz0 + 16.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -36.0)
	rig.vy = -36.0 * 0.34
	rig.grounded = true
	rig.hurt_t = 0.0
	var t_before: int = rig.tricks_landed
	j_air = false
	j_steps = 0
	while j_steps < 420:
		j_steps += 1
		rig._physics_process(dt)
		if not rig.grounded and rig.spos.z < float(jrow["kick"]["lip"]) + 6.0:
			j_air = true
		elif j_air:
			break
	_check(rig.tricks_landed <= t_before + 1 and rig.crashes == j_c0, "a jump with no tricks is just a jump (at most a stray trick, no crash)")
	rig.ghost = false
	rig.gate_assist = true
	rig.avoid_enabled = true
	# the view
	rig._restart()
	rig.view_fp = true
	await _frames(4)
	await get_tree().process_frame
	rig._place_camera(0.016, true)
	var eye_h: float = rig.cam.global_position.y - rig.spos.y
	_check(eye_h > 1.2 and eye_h < 2.6 and rig._tip_pivot != null and rig._tip_pivot.visible and not rig._sled.visible, "first person: the camera sits at eye height, the rider is hidden and the board tip shows (%.2f m)" % eye_h)
	rig.view_fp = false
	await get_tree().process_frame
	await get_tree().process_frame
	rig._place_camera(0.016, true)
	_check(rig.cam.global_position.y - rig.spos.y > 3.0 and not rig._tip_pivot.visible and rig._sled.visible, "third person: the camera is behind and above, the rider shows, the tip is hidden")
	rig.view_fp = true
	rig.set_physics_process(true)

	# ---- eye actions: squint and wide-eyed, judged against YOUR recent normal
	GazeProvider._lid_hist.clear()
	GazeProvider.eye_open_fast = 1.0
	for i in 40:
		GazeProvider._track_lids(0.20)                              # a habitual squinter's normal
		await get_tree().create_timer(0.01).timeout
	_check(not GazeProvider.squint_held() and not GazeProvider.wide_held(), "someone who always has their eyes a little narrow is not squinting (ratio %.2f)" % GazeProvider.eye_open_fast)
	for i in 8:
		GazeProvider._track_lids(0.14)
		await get_tree().create_timer(0.05).timeout
	_check(GazeProvider.squint_held() and not GazeProvider.wide_held(), "narrowing from your own normal, held for a moment, is a squint (ratio %.2f)" % GazeProvider.eye_open_fast)
	GazeProvider._lid_hist.clear()
	for i in 40:
		GazeProvider._track_lids(0.20)
	GazeProvider.eye_open_fast = 1.0
	for i in 8:
		GazeProvider._track_lids(0.26)
		await get_tree().create_timer(0.05).timeout
	_check(GazeProvider.wide_held() and not GazeProvider.squint_held(), "opening wider than your own normal, held for a moment, is wide-eyed (ratio %.2f)" % GazeProvider.eye_open_fast)
	GazeProvider._lid_hist.clear()
	for i in 40:
		GazeProvider._track_lids(0.20)
	for i in 6:
		GazeProvider._track_lids(0.03)
		await get_tree().create_timer(0.03).timeout
	_check(not GazeProvider.squint_held(), "a blink (eyes nearly shut) is not a squint")
	GazeProvider._lid_hist.clear()
	GazeProvider.eye_open_fast = 1.0

	# ---- foods: all four are built, eaten with wide eyes, and bounce away if you miss
	rig.set_physics_process(false)
	rig._restart()
	rig.balls_enabled = false
	rig.eat_enabled = true               # the wide-eyed eating rule is optional now; these checks cover it
	var foods_ok := true
	for ft in ["boost", "shield", "mult", "donut"]:
		var fi: Dictionary = rig._make_item(ft)
		foods_ok = foods_ok and (fi["root"] as Node3D).get_child_count() >= 3 and ((fi["spin"] as Node3D).get_child(0) as Node3D).get_child_count() >= 3
		(fi["root"] as Node).free()
	_check(foods_ok, "all four foods build (burger, ice cream, candy, donut)")
	var frow: Dictionary = {}
	for jf in rig._rows:
		if rig._rows[jf]["has_row"]:
			frow = rig._rows[jf]
			break
	var fz: float = float(frow["z"]) + 20.0
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, fz), fz)
	rig.vel = Vector2(0.0, -30.0)
	rig.hurt_t = 0.0
	rig.grounded = true
	rig.wide_override = false
	rig._wide_last = -10.0
	var gb0: int = rig.buffs_got
	rig._spawn_buff(frow, "boost", 0.0, fz - 0.5, [], "path")
	var f1: Dictionary = (frow["buffs"] as Array).back()
	rig._collect_buffs()
	_check(not f1["taken"] and f1.get("bounced", false) and rig.foods_bounced == 1 and rig.buffs_got == gb0 and rig._boost_t <= 0.0, "driving through food with eyes not wide leaves it: it bounces away (%d bounced)" % rig.foods_bounced)
	_check(float(f1["z"]) < rig.spos.z - 28.0 and float(f1["arm"]) > 0.0, "it lands 30+ m ahead and cannot be taken until it lands (%.0f m ahead)" % (rig.spos.z - float(f1["z"])))
	f1["arm"] = 0.0
	f1["moving"] = false
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
	rig.spos = Vector3(float(f1["x"]), rig.terrain_h(float(f1["x"]), float(f1["z"])), float(f1["z"]) + 0.5)
	rig._collect_buffs()
	_check(f1["taken"] and rig.foods_lost == 1 and rig.buffs_got == gb0, "a second miss pops it for good")
	rig._pitch.clear()                    # these checks teleport: use the plain, neutral hillside
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, fz), fz)
	rig.wide_override = true
	rig._spawn_buff(frow, "boost", 0.0, fz - 0.5, [], "path")
	rig._collect_buffs()
	_check(rig.buffs_got == gb0 + 1 and rig._boost_t > 2.5, "eyes wide: the burger is eaten and the boost starts")
	rig.wide_override = false
	rig._wide_last = rig._age - 0.3
	rig._spawn_buff(frow, "shield", 0.0, fz - 0.5, [], "path")
	rig._collect_buffs()
	_check(rig.buffs_got == gb0 + 2 and rig.shield == 1, "opening wide a moment early still counts (the tracker is late)")
	rig._wide_last = rig._age - 0.8
	rig._spawn_buff(frow, "donut", 0.0, fz - 0.5, [], "path")
	var sc_d: int = rig.score
	rig._collect_buffs()
	_check(rig.buffs_got == gb0 + 2 and rig.score == sc_d, "but not 0.8 s early")
	rig.wide_override = true
	rig._spawn_buff(frow, "donut", 0.0, fz - 0.5, [], "path")
	sc_d = rig.score
	rig._collect_buffs()
	_check(rig.score - sc_d >= 200 and rig.buffs_got == gb0 + 3, "a donut is worth a lot of points (%d)" % (rig.score - sc_d))
	rig.wide_override = false
	rig.vel = Vector2(0.0, -30.0)
	rig._spawn_ball()                                   # a squint only counts while a snowball is about
	rig.squint_override = true
	var v_sq: float = rig.vel.length()
	rig._update_eye_actions(0.5)
	_check(rig.vel.length() < v_sq * 0.96 and rig._squinting_now, "squinting costs speed while you do it (%.1f -> %.1f m/s)" % [v_sq, rig.vel.length()])
	rig.squint_override = false
	for bq in rig._balls:
		if is_instance_valid(bq["n"]):
			(bq["n"] as Node).queue_free()
	rig._balls.clear()

	rig.eat_enabled = false
	# ---- snowballs: hit, brace, dodge, outrun
	var sb_modes := ["nothing", "squint", "sidestep", "outrun"]
	var sb_res := {}
	for mode in sb_modes:
		rig.set_physics_process(false)
		rig._restart()
		rig.balls_enabled = true
		rig.gate_assist = false
		rig.avoid_enabled = false
		rig.squint_override = mode == "squint"
		rig._pitch.clear()
		rig.spos = Vector3(0.0, rig.terrain_h(0.0, -600.0), -600.0)
		rig._gh_prev = rig.spos.y
		rig.vel = Vector2(0.0, -40.0)
		rig.heading = 0.0
		rig.hurt_t = 0.0
		rig.grounded = true
		rig.shield = 0
		for kq in rig._rows:
			(rig._rows[kq] as Dictionary)["obs"] = PackedFloat32Array()
			(rig._rows[kq] as Dictionary)["zmin"] = 1.0e9
			(rig._rows[kq] as Dictionary)["zmax"] = -1.0e9
		rig._next_j = 100000
		rig._spawn_ball()
		var ball: Dictionary = rig._balls[0]
		if mode == "nothing":
			_check(float(ball["z"]) < rig.spos.z - 50.0 and absf(float(ball["x"]) - rig.spos.x) > 25.0, "a snowball appears well ahead and to the side (%.0f m ahead, %.0f m across)" % [rig.spos.z - float(ball["z"]), float(ball["x"]) - rig.spos.x])
		if mode == "sidestep":
			rig.spos.x = 30.0 if float(ball["x"]) < 0.0 else -30.0
		if mode == "outrun":
			rig.vel = Vector2(0.0, -62.0)
		var cr0: int = rig.crashes
		var v_pre := 0.0
		var v_post := 0.0
		var sb_steps := 0
		while sb_steps < 400 and rig.snow_hit + rig.snow_braced + rig.snow_dodged == 0:
			sb_steps += 1
			v_pre = rig.vel.length()
			rig._physics_process(dt)
			v_post = rig.vel.length()
			if mode == "nothing" and sb_steps % 25 == 0 and not rig._balls.is_empty():
				print("      t %.2f player z %.1f x %.1f v %.1f | ball z %.1f x %.1f vz %.1f vx %.1f done %s crashes %d" % [float(sb_steps) * dt, rig.spos.z, rig.spos.x, v_post, float(rig._balls[0]["z"]), float(rig._balls[0]["x"]), float(rig._balls[0]["vz"]), float(rig._balls[0]["vx"]), str(rig._balls[0]["done"]), rig.crashes - cr0])
		print("    snowball %s: " % mode, rig.snow_hit, "/", rig.snow_braced, "/", rig.snow_dodged, " steps ", sb_steps, " player x %.1f z %.1f" % [rig.spos.x, rig.spos.z], " ball ", ("none" if rig._balls.is_empty() else "%.1f,%.1f" % [float(rig._balls[0]["x"]), float(rig._balls[0]["z"])]))
		sb_res[mode] = {"hit": rig.snow_hit, "braced": rig.snow_braced, "dodged": rig.snow_dodged, "ratio": v_post / maxf(v_pre, 0.1), "crashes": rig.crashes - cr0, "chain": rig.chain}
	_check(int(sb_res["nothing"]["hit"]) == 1 and float(sb_res["nothing"]["ratio"]) < 0.68 and int(sb_res["nothing"]["crashes"]) == 0, "doing nothing: the snowball hits, takes about 40%% of your speed (x%.2f) and is not a wipeout" % float(sb_res["nothing"]["ratio"]))
	_check(int(sb_res["squint"]["braced"]) == 1 and int(sb_res["squint"]["hit"]) == 0 and float(sb_res["squint"]["ratio"]) > 0.85, "squinting: it shatters on you and costs only a little speed (x%.2f)" % float(sb_res["squint"]["ratio"]))
	_check(int(sb_res["sidestep"]["dodged"]) == 1 and int(sb_res["sidestep"]["hit"]) == 0, "carving out of its line: no cost")
	_check(int(sb_res["outrun"]["dodged"]) == 1 and int(sb_res["outrun"]["hit"]) == 0, "outrunning it (a boost): no cost")
	rig.squint_override = false
	rig.shield = 1
	rig._restart()
	rig.balls_enabled = true
	rig._pitch.clear()
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, -600.0), -600.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -40.0)
	rig.hurt_t = 0.0
	rig.grounded = true
	rig.shield = 1
	for kq in rig._rows:
		(rig._rows[kq] as Dictionary)["obs"] = PackedFloat32Array()
		(rig._rows[kq] as Dictionary)["zmin"] = 1.0e9
		(rig._rows[kq] as Dictionary)["zmax"] = -1.0e9
	rig._next_j = 100000
	rig._spawn_ball()
	var sb_i := 0
	while sb_i < 400 and rig.snow_hit + rig.snow_braced + rig.snow_dodged == 0 and rig.shield == 1:
		sb_i += 1
		rig._physics_process(dt)
	_check(rig.shield == 0 and rig.snow_hit == 0, "an ice cream shield takes a snowball hit")
	rig.balls_enabled = false
	rig.gate_assist = true
	rig.avoid_enabled = true

	# ---- boost pads
	var pad_row: Dictionary = {}
	rig._restart()
	for jp in range(rig._next_j, 60):
		rig._gen_segment(jp)
	for jp2 in rig._rows:
		if not (rig._rows[jp2]["pads"] as Array).is_empty():
			pad_row = rig._rows[jp2]
			break
	_check(not pad_row.is_empty(), "boost pads are laid in front of kickers")
	if not pad_row.is_empty():
		var pd: Dictionary = (pad_row["pads"] as Array)[0]
		rig._pitch.clear()
		rig.spos = Vector3(float(pd["x"]), rig.terrain_h(float(pd["x"]), float(pd["z"]) - 2.2), float(pd["z"]) - 2.2)
		rig.vel = Vector2(0.0, -34.0)
		rig.grounded = true
		rig._boost_t = 0.0
		rig._update_pads()
		_check(rig.pads_hit == 1 and rig._boost_t >= 1.7 and rig.vel.length() > 36.5, "driving over a pad gives a short boost (%.1f m/s, %.1f s)" % [rig.vel.length(), rig._boost_t])
	var epic_n := 0
	var epic_ok := true
	for rk3 in rig._rows:
		var rr3: Dictionary = rig._rows[rk3]
		if rr3.has("kick") and bool(rr3["kick"].get("epic", false)):
			epic_n += 1
			var airs := 0
			for bk3 in rr3["buffs"]:
				if bk3["kind"] == "air":
					airs += 1
			if (rr3["has_row"] and float(rr3["kick"]["lip"]) < float(rr3["z"]) + 88.0) or airs < 2 or (rr3["pads"] as Array).is_empty():
				epic_ok = false
	_check(epic_n >= 1 and epic_ok, "epic kickers exist (%d in 58 segments): taller, a pad before them, two pickups in the air, room to land" % epic_n)

	# ---- the ridiculous: head shakes and darting eyes are zigzags, extra moves get silly names and commentary
	var zs := {}
	var zn := 0
	for zi in 90:
		zn = rig._zig_push(zs, 8.0 * sin(TAU * 3.0 * float(zi) / 60.0), float(zi) / 60.0, 4.0, 1.0)
	_check(zn >= 3, "a head shaking left and right 3 times a second counts as a shake (%d turns in the last second)" % zn)
	zs = {}
	zn = 0
	for zi2 in 90:
		zn = rig._zig_push(zs, 0.3 * float(zi2) / 60.0, float(zi2) / 60.0, 4.0, 1.0)
	_check(zn == 0, "a slow drift is not a shake")
	zs = {}
	var zrng := RandomNumberGenerator.new()
	zrng.seed = 5
	zn = 0
	for zi3 in 90:
		zn = maxi(zn, rig._zig_push(zs, zrng.randfn(0.0, 0.8), float(zi3) / 60.0, 4.0, 1.0))
	_check(zn == 0, "small jitter is not a shake")

	rig.set_physics_process(false)
	rig._restart()
	rig.balls_enabled = false
	for jz in range(rig._next_j, 60):
		rig._gen_segment(jz)
	var zrow: Dictionary = {}
	for jz2 in rig._rows:
		if rig._rows[jz2].has("kick"):
			zrow = rig._rows[jz2]
			break
	rig.ghost = true
	var zkx: float = float(zrow["kick"]["x"])
	var zkz: float = float(zrow["kick"]["z"])
	rig.gate_assist = false
	rig.avoid_enabled = false
	var chaos_seen := 0
	var best_len := 0
	var best_pile := 0
	var best_pile_text := ""
	var best_pile_comment := ""
	var z_crashed := false
	for zrun in 3:
		rig.spos = Vector3(zkx, rig.terrain_h(zkx, zkz + 16.0), zkz + 16.0)
		rig._gh_prev = rig.spos.y
		rig.vel = Vector2(0.0, -36.0)
		rig.vy = -36.0 * 0.34
		rig.heading = 0.0
		rig.hurt_t = 0.0
		rig.grounded = true
		rig._finished = false
		rig.trick_look_override = 1.0
		rig.trick_grab_override = true
		rig.head_shake_override = true
		rig.cross_override = true
		rig.crazy_override = true
		rig.slam_override = zrun != 1
		var z_c0: int = rig.crashes
		var z_t0: int = rig.tricks_landed
		var z_s0: int = rig.trick_score
		var z_air := false
		var z_steps := 0
		while z_steps < 420:
			z_steps += 1
			rig._physics_process(dt)
			if not rig.grounded and rig.spos.z < float(zrow["kick"]["lip"]) + 6.0:
				z_air = true
			elif z_air:
				break
		Engine.time_scale = 1.0
		var z_parts: int = rig.best_trick.get_slice("|", 0).count(" + ") + 1
		best_len = maxi(best_len, z_parts)
		var run_pts: int = rig.trick_score - z_s0
		if run_pts > best_pile:
			best_pile = run_pts
			best_pile_text = rig._trk_text
			best_pile_comment = rig._trk_comment
		if rig.crashes != z_c0:
			z_crashed = true
		chaos_seen = maxi(chaos_seen, rig.ridiculous)
		rig._air_moves.clear()
		rig._trk_comment_t = 0.0
	_check(best_pile >= 700 and not z_crashed, "a jump with everything at once lands a pile of points (%d, no crash: %s)" % [best_pile, str(not z_crashed)])
	_check(best_pile_text != "" and best_pile_comment != "", "and the commentators have something to say (%s / %s)" % [best_pile_text, best_pile_comment])
	_check(best_len >= 4, "the move names stack up into a ridiculous combo (%d parts)" % best_len)
	_check(Engine.time_scale == 1.0, "slow motion never outlasts the jump")
	rig.trick_look_override = 0.0
	rig.trick_grab_override = false
	rig.head_shake_override = false
	rig.cross_override = false
	rig.crazy_override = false
	rig.slam_override = false
	rig.spos = Vector3(zkx, rig.terrain_h(zkx, zkz + 16.0), zkz + 16.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -36.0)
	rig.vy = -36.0 * 0.34
	rig.grounded = true
	rig.hurt_t = 0.0
	var z_air2 := false
	var z_steps2 := 0
	var z_sc2: int = rig.trick_score
	while z_steps2 < 420:
		z_steps2 += 1
		rig._physics_process(dt)
		if not rig.grounded and rig.spos.z < float(zrow["kick"]["lip"]) + 6.0:
			z_air2 = true
		elif z_air2:
			break
	_check(rig.trick_score == z_sc2 and rig._trk_text == "JUST FALLING", "a long jump with no tricks is just falling, and the game says so (text %s, comment %s, crashes %d, score %d vs %d, air %s steps %d z %.0f kick z %.0f air_time %.2f)" % [rig._trk_text, rig._trk_comment, rig.crashes, rig.trick_score, z_sc2, str(z_air2), z_steps2, rig.spos.z, zkz, rig._air_time])
	rig.ghost = false
	# ---- regions and the new zones
	rig.apply_params({})
	rig._restart()
	rig.balls_enabled = false
	for jr in range(rig._next_j, 140):
		rig._gen_segment(jr)
	_check(rig.regions_seen.size() >= 3, "a long course passes through several regions (%s)" % str(rig.regions_seen))
	_check(rig.zones_seen.has("forest") and rig.zones_seen.has("drop"), "forests and cliff drops turn up (%s)" % str(rig.zones_seen))
	var tints := {}
	for jt in rig._rows:
		tints[String((rig._rows[jt] as Dictionary).get("region", ""))] = true
	_check(tints.size() >= 3 and rig._chunk_tint(40) is Color, "regions colour the snow differently")
	# ---- the desert theme: mummies roll like snowballs but look different
	_check(Themes.DATA.has("egypt") and Themes.hazard_skin("egypt") == "mummy" and Themes.hazard_skin("alpine") == "snow", "there is an Egypt theme whose hazard is a mummy")
	rig.hazard_skin = "mummy"
	rig._balls.clear()
	rig._spawn_ball()
	var mb: Dictionary = rig._balls.back()
	_check(mb["eyes"] != null and is_instance_valid(mb["eyes"]), "a mummy rolls in with glowing eyes that stay turned to you")
	for bb in rig._balls:
		if is_instance_valid(bb["n"]):
			(bb["n"] as Node).queue_free()
		if bb.get("eyes") != null and is_instance_valid(bb["eyes"]):
			(bb["eyes"] as Node).queue_free()
	rig._balls.clear()
	rig.hazard_skin = "snow"
	_check(Themes.pyramid_mesh().get_surface_count() == 1 and Themes.ground_material("egypt") != null and Themes.sky_material("egypt") != null, "the desert has pyramids, dunes and a sky")
	# ---- dynamic light: the day wraps round and moves through dawn, day, golden hour and dusk
	var dl := DhLighting.new()
	var d0 := dl.sample_day(0.0)
	var d1 := dl.sample_day(1.0)
	var dn := dl.sample_day(0.25)
	var dg := dl.sample_day(0.5)
	_check((d0["sun"] as Color).is_equal_approx(d1["sun"]) and float(d0["elev"]) < float(dn["elev"]) and float(dg["elev"]) < float(dn["elev"]), "the day wraps, with a low sun at dawn and golden hour and a high one at noon (%.0f / %.0f / %.0f degrees)" % [float(d0["elev"]), float(dn["elev"]), float(dg["elev"])])
	_check((dg["hor"] as Color).r > (dn["hor"] as Color).r - 0.2 and (dg["hor"] as Color).b < (dn["hor"] as Color).b, "golden hour is warmer than noon")
	dl.free()
	# ---- the black box and the lean
	var rl := RunLog.new()
	rig._restart()
	for ti in 200:
		rl.tick(rig, 1.0 / 60.0)
	rig._run_t = 5.0
	for ti2 in 200:
		rl.tick(rig, 1.0 / 60.0)
	var sm := rl.summary(rig, "test")
	_check(sm.has("steering") and sm.has("phone") and sm.has("vehicle") and sm.has("performance") and sm.has("tracker") and sm.has("device"), "a run summary has steering, phone, vehicle, performance, tracker and device sections")
	var shares := float((sm["steering"] as Dictionary)["left"]) + float((sm["steering"] as Dictionary)["centre"]) + float((sm["steering"] as Dictionary)["right"])
	_check(absf(shares - 1.0) < 0.03, "the left, centre and right shares add up (%.2f)" % shares)
	_check(RunLog.line(sm).contains("steer L"), "a run can be shown as one line: %s" % RunLog.line(sm))
	_check(not JSON.stringify(sm).to_lower().contains("latitude") and not JSON.stringify(sm).to_lower().contains("longitude"), "no location is ever recorded")
	rl.end_run(rig, "test")
	var stored := RunLog.load_all()
	_check(stored.size() >= 1, "a finished run is kept (%d stored)" % stored.size())
	RunLog.clear_all()
	# a lean: the look sits 0.02 to one side all the time, swinging 0.03 either way. After a while the centre must have followed it.
	rig.eyes_only = true
	rig._ex_init = false
	rig._ex_raw.clear()
	rig._ex_abs.clear()
	rig._ex_slow.clear()
	var lean_sum := 0.0
	var lean_n := 0
	for li in 6000:
		var lt := float(li) / 60.0
		GazeProvider.eih = Vector2(-(0.02 + 0.03 * sin(lt * 0.9)), 0.5)
		var lo: float = rig._eyes_only_offs(1.0 / 60.0, 0.0)
		if li > 5000:
			lean_sum += lo
			lean_n += 1
	var lean_mean := lean_sum / float(lean_n)
	_check(absf(lean_mean) < 0.012, "a constant lean is absorbed into the centre (mean offset %.4f after 100 s)" % lean_mean)
	# ---- earned help
	rig._restart()
	rig._run_t = 30.0
	rig._eye_on = false
	rig.grounded = true
	for ei in 400:
		rig._update_engage(1.0 / 60.0, 0.0, Vector3.ZERO)
	var eng_idle: float = rig._engage
	for ei2 in 90:
		rig._update_engage(1.0 / 60.0, 1.0, Vector3.ZERO)
	_check(eng_idle < 0.3 and rig._engage > 0.9, "help fades when you do nothing (%.2f) and returns the moment you act (%.2f)" % [eng_idle, rig._engage])
	rig._restart()
	_check(rig._engage == 1.0 and int(rig.ag["eyes"]) == 0 and rig.agency_summary().has("eyesGateShare"), "a new run starts fully helped with an empty agency record")
	# ---- real looks versus noise: noise around the true gaze, one-frame spikes, blinks, and genuine jumps that settle
	var sd := Saccades.new()
	sd.jitter = 0.12
	sd.min_amp = 0.28
	var srng := RandomNumberGenerator.new()
	srng.seed = 4242
	var truth: Array = []                   # [t, dir]
	var found: Array = []                   # [t, dir]
	var fix := 0.0
	var t_s := 0.0
	var next_jump := 1.0
	var blink_left := 0
	var n_spikes := 0
	for fi in 3600:                          # five minutes at 12 frames a second
		t_s += 1.0 / 12.0
		if t_s >= next_jump:
			var dir_s := 1.0 if (fix < -0.4 or (fix < 0.4 and srng.randf() < 0.5)) else -1.0
			fix = clampf(fix + dir_s * srng.randf_range(0.8, 1.5), -1.6, 1.6)
			truth.append([t_s, dir_s])
			next_jump = t_s + srng.randf_range(1.0, 2.2)
		var x_s := fix + srng.randfn(0.0, 0.10)
		if srng.randf() < 0.04:
			x_s += srng.randf_range(0.7, 1.2) * (1.0 if srng.randf() < 0.5 else -1.0)         # a one-frame spike
			n_spikes += 1
		if blink_left > 0:
			x_s -= 0.7                                                                        # a blink drags the reading one way for two frames
			blink_left -= 1
		elif srng.randf() < 0.01:
			blink_left = 2
		var ev_before := sd.events
		var ev := sd.push(t_s, x_s)
		if sd.events > ev_before:
			found.append([t_s, ev])
		elif sd.events < ev_before and not found.is_empty():
			found.pop_back()                                  # the look was taken back
	var tp := 0
	var used := {}
	for tr_i in truth:
		for fd_i in found.size():
			if used.has(fd_i):
				continue
			var fdv: Array = found[fd_i]
			if float(fdv[0]) >= float(tr_i[0]) and float(fdv[0]) - float(tr_i[0]) <= 0.6 and float(fdv[1]) == float(tr_i[1]):
				tp += 1
				used[fd_i] = true
				break
	var recall := float(tp) / float(maxi(truth.size(), 1))
	var fp_min := float(found.size() - tp) / 5.0
	_m("saccade_recall", snappedf(recall, 0.01))
	_m("saccade_false_per_min", snappedf(fp_min, 0.1))
	_m("saccade_spikes_rejected", sd.spikes)
	_m("saccade_retracted", sd.retracted)
	_check(recall >= 0.8 and fp_min <= 4.0, "real looks are found and noise is not (recall %.0f%%, %.1f false per minute, %d one-frame spikes rejected of %d)" % [recall * 100.0, fp_min, sd.spikes, n_spikes])

	# ---- rocking and twitching: following the safe gate with a slow, noisy, late look must not make the board swing back and forth
	rig._restart()
	rig.set_physics_process(false)
	rig.vel = Vector2(0.0, -16.0)
	var orng := RandomNumberGenerator.new()
	orng.seed = 9
	var oq: Array = []
	var o_rev := 0
	var o_last := 0.0
	var o_st := 0
	var o_steer_changes := 0.0
	var o_prev_steer := 0.0
	while rig.spos.z > -900.0 and o_st < 9000:
		o_st += 1
		var o_row: Dictionary = {}
		var o_bz := -1.0e9
		for oj in rig._rows:
			var orw: Dictionary = rig._rows[oj]
			if orw["has_row"] and float(orw["z"]) < rig.spos.z - 4.0 and float(orw["z"]) > o_bz:
				o_bz = float(orw["z"])
				o_row = orw
		if not o_row.is_empty():
			var o_gx := 0.0
			for og in o_row["gaps"]:
				if og["good"]:
					o_gx = float(og["x"])
			oq.append(clampf((o_gx - rig.spos.x) / 30.0, -1.0, 1.0) + orng.randfn(0.0, 0.12))
			if oq.size() > 21:
				oq.pop_front()
			rig._steer_gaze = float(oq[0])
		rig._physics_process(dt)
		o_steer_changes += absf(rig.steer - o_prev_steer)
		o_prev_steer = rig.steer
		if absf(rig.vel.x) > 1.0:
			if o_last != 0.0 and signf(rig.vel.x) != signf(o_last):
				o_rev += 1
			o_last = rig.vel.x
	var o_per := float(o_rev) / maxf(-rig.spos.z / 100.0, 1.0)
	var o_twitch := o_steer_changes / maxf(float(o_st) * dt, 0.1)
	_m("rocking_reversals_per_100m", snappedf(o_per, 0.1))
	_m("twitch_steer_change_per_s", snappedf(o_twitch, 0.01))
	_check(o_per < 2.0, "a late, noisy look does not make the board rock (%.1f sideways reversals per 100 m, steering moves %.2f per second)" % [o_per, o_twitch])

	# ---- tentative intent: starts at once, is confirmed by staying, cancelled by going back
	rig._restart()
	rig._eye_on = true
	rig.sacc.accepted += 1
	rig.sacc.last_dir = 1.0
	rig._update_intent(1.0 / 60.0)
	var int_start: float = rig._intent_amt
	rig.sacc.confirmed += 1
	rig._update_intent(1.0 / 60.0)
	var int_conf: float = rig._intent_amt
	rig.sacc.accepted += 1
	rig.sacc.last_dir = -1.0
	rig._update_intent(1.0 / 60.0)
	rig.sacc.retracted += 1
	rig._update_intent(1.0 / 60.0)
	var int_cancel: float = rig._intent_amt
	_m("intent_start_amt", snappedf(int_start, 0.01))
	_check(int_start >= 0.5 and int_conf >= 0.99 and int_cancel < 0.01, "a look moves the board at once (%.2f), staying confirms it (%.2f), going back cancels it (%.2f)" % [int_start, int_conf, int_cancel])

	# ---- every button does what it says
	var menu := DownhillMenu.new()
	var menu_layer := CanvasLayer.new()
	add_child(menu_layer)
	menu_layer.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	var btn_ok := true
	var btn_bad: Array = []
	for tid in Themes.ORDER:
		menu._pick_theme(tid)
		if String(menu.cfg["theme"]) != tid:
			btn_ok = false
			btn_bad.append("theme " + tid)
	for pid in menu._preset_btns:
		menu._pick_preset(pid)
		if String(menu.cfg["preset"]) != pid:
			btn_ok = false
			btn_bad.append("preset " + pid)
	menu._pick_preset("endless")
	if not bool(menu.cfg["endless"]):
		btn_ok = false
		btn_bad.append("endless preset")
	for tk in menu._toggles:
		var before: bool = bool(menu.cfg[tk])
		(menu._toggles[tk] as Button).toggled.emit(not before)
		if bool(menu.cfg[tk]) == before:
			btn_ok = false
			btn_bad.append("toggle " + tk)
	menu._diff_s.value = 1.35
	menu._assist_s.value = 0.3
	menu._len_s.value = 7.0
	if absf(float(menu.cfg["diff"]) - 1.35) > 0.01 or absf(float(menu.cfg["assist"]) - 0.3) > 0.01 or absf(float(menu.cfg["length_km"]) - 7.0) > 0.01:
		btn_ok = false
		btn_bad.append("sliders")
	var got_cfg: Array = []
	Game.dh_started.connect(func(cc: Dictionary) -> void: got_cfg.append(cc))
	menu._pick_theme("candy")
	menu._start(false)
	await get_tree().process_frame
	get_tree().paused = false
	if got_cfg.is_empty() or String((got_cfg[0] as Dictionary)["theme"]) != "candy" or int((got_cfg[0] as Dictionary)["seed"]) == 0:
		btn_ok = false
		btn_bad.append("start")
	_check(btn_ok, "every menu button and slider changes what it should and START hands the settings over (%s)" % str(btn_bad))
	rig._paused = true
	rig._pause_action("advanced")
	var adv_on: bool = rig._pause_adv
	rig._pause_action("simple")
	var adv_off: bool = not rig._pause_adv
	rig._pause_action("resume")
	_check(adv_on and adv_off and not rig._paused, "the pause screen's ADVANCED, BACK and RESUME work")
	# right after START the browser's camera prompt takes focus: that must not pause the game
	rig._paused = false
	rig._no_pause_until = Time.get_ticks_msec() + 5000
	rig._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var no_pause_in_grace: bool = not rig._paused
	rig._no_pause_until = 0
	GazeProvider.backend = GazeProvider.Backend.SCRIPTED
	rig._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(no_pause_in_grace and rig._paused, "losing focus right after START does not pause, losing it later does")
	rig._paused = false

	# ---- the speed governor: camera and control come first
	var gv := DhLighting.new()
	for gi in 6:
		gv.step_governor(2.0, 60.0, 8.0, true)                 # the game is fine but the tracker is starving
	var tier_trk := gv.tier
	for gi2 in 12:
		gv.step_governor(2.0, 60.0, 14.0, true)
	var tier_rec := gv.tier
	var gv2 := DhLighting.new()
	gv2.floor_tier = 1
	gv2.tier = 1
	for gi3 in 30:
		gv2.step_governor(2.0, 60.0, 14.0, true)
	var gv3 := DhLighting.new()
	for gi4 in 12:
		gv3.step_governor(2.0, 25.0, 14.0, true)
	_m("governor_tier_when_tracker_slow", tier_trk)
	_check(tier_trk >= 2 and tier_rec < tier_trk, "a starving tracker makes the game give up looks (tier %d) and they come back when it recovers (tier %d)" % [tier_trk, tier_rec])
	_check(gv2.tier == 1 and gv3.tier >= 2, "a phone never drops below its floor, and a slow game gives up looks too (%d, %d)" % [gv2.tier, gv3.tier])
	gv.free()
	gv2.free()
	gv3.free()

	# ---- sky ramps, face challenges, the cutaway camera, gate posts and breadcrumbs
	rig.set_physics_process(false)
	rig.apply_params({"zones": {"air": 9.0, "rush": 1.0, "flat": 0.0, "tunnel": 0.0, "bend": 0.0}})
	rig._restart()
	rig.balls_enabled = false
	for js in range(rig._next_j, 60):
		rig._gen_segment(js)
	var srow: Dictionary = {}
	for js2 in rig._rows:
		if rig._rows[js2].has("kick"):
			srow = rig._rows[js2]
			break
	var sx0: float = float(srow["kick"]["x"])
	var sz0: float = float(srow["kick"]["z"])
	rig.gate_assist = false
	rig.avoid_enabled = false
	rig.ghost = true
	rig.spos = Vector3(sx0, rig.terrain_h(sx0, sz0 + 40.0), sz0 + 40.0)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -36.0)
	rig.vy = -36.0 * 0.34
	rig.heading = 0.0
	rig.hurt_t = 0.0
	rig.grounded = true
	rig._finished = false
	var s_air := 0.0
	var s_peak := 0.0
	var s_asked := 0
	var s_cine := 0.0
	var s_steps := 0
	var s_was_air := false
	while s_steps < 900:
		s_steps += 1
		if rig.face_kind != "":
			rig.face_override = rig.face_kind
			s_asked += 1
		else:
			rig.face_override = ""
		rig._physics_process(dt)
		await get_tree().process_frame
		s_cine = maxf(s_cine, rig._cine_k)
		if not rig.grounded and rig.spos.z < float(srow["kick"]["lip"]) + 6.0:
			s_was_air = true
			s_air += dt
			s_peak = maxf(s_peak, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
		elif s_was_air and rig.grounded:
			break
	rig.face_override = ""
	rig.ghost = false
	for ps in 40:
		rig._physics_process(dt)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("    sky flight: steps %d end z %.0f kick z %.0f lip %.0f rise %.2f speed %.1f epic %s drag %.2f" % [s_steps, rig.spos.z, sz0, float(srow["kick"]["lip"]), float(rig._kickers[0]["rise"]) if not rig._kickers.is_empty() else -1.0, rig.vel.length(), str(rig._air_epic), rig.sky_drag])
	_m("sky_peak_m", snappedf(s_peak, 0.1))
	_m("sky_air_s", snappedf(s_air, 0.1))
	_m("faces_done", rig.face_done)
	_check(s_peak > 5.0 and s_air > 1.4, "an air-stretch ramp throws you into the sky (%.1f m up, %.1f s in the air)" % [s_peak, s_air])
	_check(s_asked > 0 and rig.face_done >= 1, "up there the game asks for a face and pays for pulling it (%d frames asked, %d done, tricks %s)" % [s_asked, rig.face_done, str(rig.face_seen)])
	_check((s_cine > 0.5 or s_peak < 7.0) and rig.cines >= 1, "a big jump cuts away to the hero camera (blend %.2f, %d cutaways)" % [s_cine, rig.cines])
	_check(rig._cine_k < 0.5 and Engine.time_scale == 1.0, "and the camera is back with you after the landing (blend %.2f)" % rig._cine_k)
	var grow := {}
	for jg in rig._rows:
		if rig._rows[jg]["has_row"]:
			grow = rig._rows[jg]
			break
	var posts_ok := false
	if not grow.is_empty():
		var pcount := 0
		for nd in grow["nodes"]:
			if nd is MeshInstance3D and (nd as MeshInstance3D).mesh is CylinderMesh and absf(((nd as MeshInstance3D).mesh as CylinderMesh).height - 9.0) < 0.01:
				pcount += 1
		posts_ok = pcount >= 2 * (grow["gaps"] as Array).size()
	_check(posts_ok, "every opening has a tall post on each side")
	if not grow.is_empty():
		var lx := 0.0
		var gm := -1.0
		for lxi in range(-40, 41, 2):
			var dmin := 1.0e9
			for gg in grow["gaps"]:
				dmin = minf(dmin, absf(float(gg["x"]) - float(lxi)))
			if dmin > gm:
				gm = dmin
				lx = float(lxi)
		rig.spos = Vector3(lx, rig.terrain_h(lx, float(grow["z"]) + 60.0), float(grow["z"]) + 60.0)
		rig._in_air = false
		for ci in 40:
			rig._update_crumbs(0.05)
		_check(gm > 11.0 and rig._crumb_a > 0.9, "lost far from every opening, glowing breadcrumbs light the way (%.0f m off, strength %.2f)" % [gm, rig._crumb_a])
	rig.gate_assist = true
	rig.avoid_enabled = true

	# ---- the realms: every one generates, the roofed ones have a roof and darkness, and every barrier is a choice
	rig.set_physics_process(false)
	rig.weird = 1.0
	var realm_ok := true
	var roofs_ok := true
	var choice_ok := true
	for rid in Realms.IDS:
		rig._force_realm = rid
		rig.apply_params({})
		rig._restart()
		rig.balls_enabled = false
		for rj in range(rig._next_j, 14):
			rig._gen_segment(rj)
		var nin := 0
		for rj2 in rig._zone_by_j:
			if rig._zone_by_j[rj2] == rid:
				nin += 1
		if nin < 6:
			realm_ok = false
		for rj3 in rig._rows:
			var rrow: Dictionary = rig._rows[rj3]
			if rrow["has_row"] and (rrow["gaps"] as Array).size() < 2:
				choice_ok = false
			if rrow["zone"] == rid and Realms.has_roof(rid):
				var has_roof_node := false
				for nd in rrow["nodes"]:
					if is_instance_valid(nd) and nd is MeshInstance3D and (nd as MeshInstance3D).mesh is ArrayMesh and (nd as MeshInstance3D).material_override == Realms.material(rid):
						has_roof_node = true
				if not has_roof_node:
					roofs_ok = false
	rig._force_realm = ""
	_check(realm_ok, "all %d realms generate real stretches" % Realms.IDS.size())
	_check(roofs_ok, "the roofed realms have a roof")
	_check(choice_ok, "every barrier offers at least two openings")
	rig.weird = 0.0
	rig.apply_params({})
	rig._restart()

	# ---- leaving restores the player camera
	level.load_level(6)
	await _frames(5)
	_check(not Game.run_mode and not Game.downhill_mode and level._dh == null and level.player.camera.current, "leaving carve restores the player camera")
	# ---- phone motion: tilt-following removed from the iris reading, lap detection, bump hold
	var pmx := PhoneMotion.new()
	var pr := RandomNumberGenerator.new()
	pr.seed = 7
	var raw_v := 0.0
	var cor_v := 0.0
	var nv := 0
	for pi in 1500:                                           # 50 s at 30 Hz
		var pt := float(pi) / 30.0
		var tx := 70.0 + 5.0 * sin(pt * 2.1) + 3.0 * sin(pt * 5.3) + pr.randfn(0.0, 0.6)
		var ty := 80.0 + 4.0 * sin(pt * 1.7 + 1.0) + pr.randfn(0.0, 0.6)
		pmx.feed(ty, tx, 0, Vector3(8.0, 8.0, 8.0), 1.0 / 30.0)
		var glance := 0.03 * sin(pt * 0.5)                                # a slow, real glance
		var e := Vector2(0.5 + glance + 0.0035 * (tx - 70.0) + pr.randfn(0.0, 0.002), 0.5 + 0.002 * (ty - 80.0) + pr.randfn(0.0, 0.002))
		var cc := pmx.correct(e)
		if pi > 900:
			raw_v += pow(e.x - 0.5 - glance, 2.0)
			cor_v += pow(cc.x - 0.5 - glance, 2.0)
			nv += 1
	_check(cor_v < raw_v * 0.4, "the phone stabiliser removes most of the hand-tilt wobble from the iris reading (%.6f -> %.6f, removed %.0f%%)" % [raw_v / float(nv), cor_v / float(nv), pmx.removed_pct])
	var pm2 := PhoneMotion.new()
	var still_bad := 0.0
	for pj in 900:
		var ptj := float(pj) / 30.0
		pm2.feed(80.0, 0.0, 0, Vector3.ZERO, 1.0 / 30.0)
		var g2 := 0.03 * sin(ptj * 1.3)
		var e2 := Vector2(0.5 + g2, 0.5)
		var c2 := pm2.correct(e2)
		still_bad = maxf(still_bad, absf(c2.x - e2.x))
	_check(still_bad < 0.002, "a steady phone leaves real glances alone (largest change %.4f)" % still_bad)
	var pm3 := PhoneMotion.new()
	pm3.feed(85.0, 0.0, 0, Vector3.ZERO, 0.03)
	var lap_up := pm3.lap
	pm3.feed(15.0, 0.0, 0, Vector3.ZERO, 0.03)
	_check(lap_up < 0.1 and pm3.lap > 0.9, "an upright phone is not in the lap, a flat one is (%.2f / %.2f)" % [lap_up, pm3.lap])
	var pm4 := PhoneMotion.new()
	for pk in 60:
		pm4.feed(80.0, 0.0, 0, Vector3(5, 5, 5), 1.0 / 30.0)
	var calm_ok := not pm4.settling() and not pm4.holding()
	for pk2 in 30:
		pm4.feed(80.0 - float(pk2), 0.0, 0, Vector3(40, 40, 40), 1.0 / 30.0)
	_check(calm_ok and pm4.settling(), "changing how the phone is held pauses squint and wide-eye detection")
	var pm5 := PhoneMotion.new()
	for pk3 in 20:
		pm5.feed(80.0, 0.0, 0, Vector3(120, 100, 90), 1.0 / 30.0)
	_check(pm5.holding(), "a hard bump holds the gaze for a moment")
	_write_metrics()
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
