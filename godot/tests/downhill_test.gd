extends Node
## Headless checks for the Downhill run:  godot --headless --path . res://tests/downhill_test.tscn
var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1

func _reset(rig: DownhillRig, speed: float, z: float = -2.0) -> void:
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, z), z)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -speed)
	rig.vy = -speed * DownhillRig.SLOPE
	rig.heading = 0.0
	rig.grounded = true
	rig.hurt_t = 0.0
	rig.energy = 0.0


func _gate_x(rig: DownhillRig, lane: int, vs: Vector2) -> float:
	if rig._gate_row.is_empty():
		return 0.5
	for g in rig._gate_row["gaps"]:
		if int(g["lane"]) == lane:
			var sc := rig._gap_screen(rig._gate_row, g)
			if not sc.is_empty():
				return float((sc["c"] as Vector2).x) / vs.x
	return 0.5

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = true               # no eyes in the physics checks (a headless mouse sits in the corner)
	level.load_level(8)
	await _frames(5)
	var rig: DownhillRig = level._dh
	rig.lane_ctl = 1
	_check(rig != null and Game.downhill_mode and Game.flight_mode and rig.cam.current, "downhill rig starts, owns the camera, shares the flight input")
	_check(not rig._rows.is_empty() and rig._chunks.size() >= 5, "course and terrain chunks exist (%d rows)" % rig._rows.size())
	GazeProvider.nod_debug = Vector2.ZERO
	GazeProvider.peek_debug = Vector3.ZERO
	var s0 := rig.vel.length()
	await _frames(180)
	_check(rig.vel.length() > s0 + 5.0 and rig.spos.z < -30.0, "gravity pulls the sled downhill (%.1f -> %.1f m/s, %.0f m)" % [s0, rig.vel.length(), -rig.spos.z])
	_check(rig.grounded, "it hugs the ground on a smooth slope")

	# posture: tuck is faster than sitting up, over the same stretch
	var speeds := {}
	for mode in ["tuck", "brake"]:
		_reset(rig, 22.0)
		GazeProvider.nod_debug = Vector2(-0.3, 0.0) if mode == "tuck" else Vector2(0.3, 0.0)
		await _frames(150)
		speeds[mode] = rig.vel.length()
	GazeProvider.nod_debug = Vector2.ZERO
	_check(float(speeds["tuck"]) > float(speeds["brake"]) + 6.0, "tuck beats sitting up (%.1f vs %.1f m/s)" % [speeds["tuck"], speeds["brake"]])

	# steering costs speed (momentum): a hard carve is slower than a straight run
	_reset(rig, 26.0)
	await _frames(100)
	var straight := rig.vel.length()
	_reset(rig, 26.0)
	GazeProvider.peek_debug = Vector3(1.8, 0.0, 0.0)
	await _frames(40)
	GazeProvider.peek_debug = Vector3(-1.8, 0.0, 0.0)
	await _frames(40)
	GazeProvider.peek_debug = Vector3(1.8, 0.0, 0.0)
	await _frames(40)
	GazeProvider.peek_debug = Vector3.ZERO
	var carved := rig.vel.length()
	_check(rig.heading != 0.0 and carved < straight, "hard carving scrubs speed (%.1f vs %.1f m/s straight)" % [carved, straight])

	# pop: snap chin up leaves the ground, then lands again
	_reset(rig, 22.0)
	await _frames(20)
	GazeProvider.nod_debug = Vector2(0.05, 2.0)
	await _frames(3)
	GazeProvider.nod_debug = Vector2.ZERO
	_check(not rig.grounded and rig.spos.y > rig.terrain_h(rig.spos.x, rig.spos.z) + 0.1, "snap chin up pops off the snow")
	await _frames(120)
	_check(rig.grounded, "and it lands again")

	# a kicker launches a fast sled
	_reset(rig, 30.0)
	rig._kickers.append({"x": 0.0, "z": rig.spos.z - 30.0, "len": 14.0, "w": 14.0, "rise": 2.0})
	var launched := false
	var air_max := 0.0
	for i in 200:
		await get_tree().physics_frame
		if not rig.grounded:
			launched = true
			air_max = maxf(air_max, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
	_check(launched and air_max > 1.5, "a kicker launches the sled (%.1f m above the snow)" % air_max)

	# autopilot that cheats with the gap list: the course must be solvable, and rows get scored
	level.load_level(8)
	await _frames(5)
	rig = level._dh
	rig.lane_ctl = 1
	rig.hurt_t = 0.0
	var crashes0 := rig.crashes
	for i in 3600:
		var target := 0.0
		var found := false
		for k in rig._rows:
			var r: Dictionary = rig._rows[k]
			if r["has_row"] and not r["passed"] and float(r["z"]) < rig.spos.z:
				if not found or float(r["z"]) > rig._rows[k]["z"] - 0.0:
					pass
		var best_z := -1.0e9
		for k in rig._rows:
			var r2: Dictionary = rig._rows[k]
			if r2["has_row"] and not r2["passed"] and float(r2["z"]) < rig.spos.z and float(r2["z"]) > best_z:
				best_z = float(r2["z"])
				var best_d := 1.0e9
				for g in r2["gaps"]:
					var kd: String = g["kind"]
					var viable: bool = (kd == "open" or kd == "tight" or kd == "late" or (kd == "cycle" and rig._forecast(g, r2) == 1))
					if viable and absf(float(g["x"]) - rig.spos.x) < best_d:
						best_d = absf(float(g["x"]) - rig.spos.x)
						target = float(g["x"])
						found = true
		var want := clampf((target - (rig.spos.x + rig.vel.x * 0.6)) / 16.0, -1.0, 1.0)   # steer by where momentum will carry you
		GazeProvider.peek_debug = Vector3(want * 1.8, 0.0, 0.0)
		await get_tree().physics_frame
	GazeProvider.peek_debug = Vector3.ZERO
	for kk in rig._rows:
		var rr: Dictionary = rig._rows[kk]
		if absf(float(rr["z"]) + 588.0) < 20.0:
			for gg in rr["gaps"]:
				print("   row z=%.0f gap x=%.1f w=%.1f %s good=%s" % [rr["z"], gg["x"], gg["w"], gg["kind"], str(gg["good"])])
	for cl in rig.crash_log:
		print("   crash: ", cl)
	print("autopilot: rows passed %d, crashes %d, score %d, speed %.1f, distance %.0f m, diff %.2f" % [rig.rows_passed, rig.crashes - crashes0, rig.score, rig.vel.length(), -rig.spos.z, rig.diff])
	_check(rig.rows_passed >= 12, "a 60 s run reaches many openings (%d)" % rig.rows_passed)
	_check(rig.crashes - crashes0 <= 4, "following the real openings is survivable (%d crashes)" % (rig.crashes - crashes0))

	# eye setup maths: raw readings for the centre / left / right dots map back to screen x
	var sim := func(x: float) -> Array:
		var a := []
		for i in 12:
			a.append(3.0 + 0.8 * (x - 0.5) + (float(i % 3) - 1.0) * 0.004)
		return a
	var fit := DownhillRig.fit_gaze(sim.call(0.5), sim.call(0.1), sim.call(0.9))
	var back := 0.5 + float(fit["slope"]) * (3.0 + 0.8 * (0.8 - 0.5) - float(fit["mid"]))
	_check(bool(fit["ok"]) and absf(back - 0.8) < 0.03, "three-dot eye setup maps the raw signal to screen x (0.8 -> %.2f)" % back)
	var flipped := DownhillRig.fit_gaze(sim.call(0.1), sim.call(0.1), sim.call(0.9))
	_check(not bool(flipped["ok"]), "an eye setup where the centre reading is not between left and right is rejected")
	var flat := DownhillRig.fit_gaze([1.0, 1.1, 0.9, 1.0, 1.1, 0.9], [1.0, 1.1, 0.9, 1.0, 1.1, 0.9], [1.0, 1.1, 0.9, 1.0, 1.1, 0.9])
	_check(not bool(flat["ok"]), "a setup where you did not move your eyes is rejected")

	# gates: timed doors, doors that open late, openings that slam shut, and snow screens that hide part of the wall
	rig.diff = 1.0
	var kinds := {}
	var late_g: Dictionary = {}
	var late_r: Dictionary = {}
	var shut_g: Dictionary = {}
	var shut_r: Dictionary = {}
	var screens := 0
	for j in range(60, 100):
		rig._gen_segment(j)
		var rr: Dictionary = rig._rows[j]
		if rr.has("screen"):
			screens += 1
		for gg in rr["gaps"]:
			kinds[String(gg["kind"])] = true
			if gg["kind"] == "late" and late_g.is_empty():
				late_g = gg
				late_r = rr
			if gg["kind"] == "shut" and shut_g.is_empty():
				shut_g = gg
				shut_r = rr
	_check(kinds.has("cycle") and kinds.has("late") and kinds.has("shut") and kinds.has("trap") and screens > 3, "high difficulty builds timed, late, false and dead-end gates plus snow screens (%d screens)" % screens)
	if not late_g.is_empty():
		rig.spos.z = float(late_r["z"]) + 80.0
		rig._update_doors()
		var closed_far := bool(late_g["closed"])
		rig.spos.z = float(late_r["z"]) + 20.0
		rig._update_doors()
		_check(closed_far and not bool(late_g["closed"]), "a late gate is shut from far away and opens at the last moment")
	if not shut_g.is_empty():
		rig.spos.z = float(shut_r["z"]) + 80.0
		rig._update_doors()
		var open_far := not bool(shut_g["closed"])
		rig.spos.z = float(shut_r["z"]) + 15.0
		rig._update_doors()
		_check(open_far and bool(shut_g["closed"]), "a false opening looks open from far away and slams shut up close")

	# the line your eyes set: looking at an opening for a moment locks it and the board is pulled toward it
	Game.touch_mode = false
	level.load_level(8)
	await _frames(5)
	rig = level._dh
	rig.lane_ctl = 0
	_reset(rig, 24.0)
	var tgt: Dictionary = {}
	var tgt_row: Dictionary = {}
	for k in rig._rows:
		var rr3: Dictionary = rig._rows[k]
		if rr3["has_row"] and (tgt_row.is_empty() or float(rr3["z"]) > float(tgt_row["z"])):
			tgt_row = rr3
	var far_x := -1000.0
	for gg2 in tgt_row["gaps"]:
		if absf(float(gg2["x"])) > absf(far_x if far_x > -999.0 else 0.0):
			tgt = gg2
			far_x = float(gg2["x"])
	var vp := level.get_viewport().get_visible_rect().size
	await _frames(2)
	var sc := rig._gap_screen(tgt_row, tgt)
	GazeProvider.set_scripted(Vector2(float(sc["c"].x) / vp.x, 0.46))
	var x0 := rig.spos.x
	await _frames(70)
	_check(is_same(rig._lock, tgt), "looking at an opening for a moment locks it as your line")
	_check(absf(rig.spos.x - float(tgt["x"])) < absf(x0 - float(tgt["x"])), "the locked line pulls the board toward it (%.1f -> %.1f, gate at %.1f)" % [x0, rig.spos.x, float(tgt["x"])])
	GazeProvider.set_backend(GazeProvider.Backend.MOUSE)

	# tuning: values clamp, and the aim tolerance grows with measured noise
	rig = level._dh
	rig.lane_ctl = 1
	rig._dwell_t = 0.35
	for i in 30:
		rig._adjust("dwell", 1.0)
	_check(is_equal_approx(rig._dwell_t, 0.8), "look time clamps at its maximum")
	for i in 30:
		rig._adjust("assist", -1.0)
	_check(is_zero_approx(rig._assist), "line pull can be switched off")
	rig._cal_sigma = 0.01
	rig._jit = 0.0
	rig._pad_scale = 1.0
	var tight_pad := rig._pad()
	rig._cal_sigma = 0.06
	_check(rig._pad() > tight_pad * 2.5, "noisier tracking widens the aim zone (%.3f -> %.3f)" % [tight_pad, rig._pad()])

	# comfort: a head tilted back (squinted eyes) widens the aim zone; late gates open early enough to read at speed
	var was_backend := GazeProvider.backend
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	rig._cal_sigma = 0.03
	GazeProvider.coach.quality = 1.0
	var good_pad := rig._pad()
	GazeProvider.coach.quality = 0.0
	var bad_pad := rig._pad()
	GazeProvider.coach.quality = 1.0
	GazeProvider.backend = was_backend
	_check(bad_pad > good_pad * 1.4, "a poorly placed head widens the aim zone (%.3f -> %.3f)" % [good_pad, bad_pad])
	var late: Dictionary = {}
	var late_row: Dictionary = {}
	for k in rig._rows:
		for g in (rig._rows[k] as Dictionary)["gaps"]:
			if String(g["kind"]) == "late" and late.is_empty():
				late = g
				late_row = rig._rows[k]
	if not late.is_empty():
		late["latched"] = false
		rig.spos.z = float(late_row["z"]) + 40.0
		rig.vel = Vector2(0.0, -30.0)
		rig._update_doors()
		_check(bool(late["latched"]), "a late gate opens at least 1.5 s before you arrive at 30 m/s (40 m ahead)")

	# three lanes: every wall has lanes 0..2, a safe lane that moves by at most one lane per wall, coins on the safe line
	var prev_good := -1
	var ok_shape := true
	var ok_steps := true
	var coin_rows := 0
	var keys: Array = rig._rows.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = rig._rows[k]
		if not r["has_row"]:
			continue
		var lanes := {}
		var good_lane := -1
		for g in r["gaps"]:
			lanes[int(g["lane"])] = true
			if g["good"]:
				good_lane = int(g["lane"])
				if not (String(g["kind"]) == "open" or String(g["kind"]) == "late"):
					ok_shape = false
		if lanes.size() != 3 or good_lane < 0:
			ok_shape = false
		if prev_good >= 0 and absi(good_lane - prev_good) > 1:
			ok_steps = false
		prev_good = good_lane
		if r.has("coins") and (r["coins"] as Array).size() == 12:
			coin_rows += 1
	_check(ok_shape, "every wall has three lanes and a safe open/late lane")
	_check(ok_steps, "the safe lane moves at most one lane per wall (long gentle arcs)")
	_check(coin_rows >= keys.size() - 2, "coins sit in every lane (%d rows)" % coin_rows)
	# joystick lane control: the dead zone ignores wobble, a clear look aside steps, leaving the zone needs less than entering it
	_check(DownhillRig.lane_dir(0.10, 0.13, 0) == 0 and DownhillRig.lane_dir(-0.12, 0.13, 0) == 0, "eyes wobbling inside the dead zone never step a lane")
	_check(DownhillRig.lane_dir(0.20, 0.13, 0) == 1 and DownhillRig.lane_dir(-0.20, 0.13, 0) == -1, "a clear look left or right steps that way")
	_check(DownhillRig.lane_dir(0.11, 0.13, 1) == 1 and DownhillRig.lane_dir(0.05, 0.13, 1) == 0, "hysteresis: once looking aside, a small drift back does not cancel it")
	rig.lane_ctl = 1
	# noisy tracking (sigma 6% of the screen) around the middle never changes lane; a deliberate look aside does
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 3
	rig._lane_set(1)
	rig.spos = Vector3(0.0, rig.terrain_h(0.0, -2.0), -2.0)
	rig.vel = Vector2(0.0, -20.0)
	var steps := 0
	var lane_prev := rig._lane
	for i in 300:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + nrng.randfn(0.0, 0.06), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		if rig._lane != lane_prev:
			if i > 100:
				steps += 1
			lane_prev = rig._lane
	_check(steps == 0, "eyes jittering around the middle for 5 s: no lane change (%d steps)" % steps)
	var t_0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_0 < 1800:
		GazeProvider.set_scripted(Vector2(clampf(0.82 + nrng.randfn(0.0, 0.06), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._lane == 2, "a deliberate look to the right moves to the right lane within 1.5 s (lane %d)" % rig._lane)
	var t_1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_1 < 3000:
		GazeProvider.set_scripted(Vector2(clampf(0.18 + nrng.randfn(0.0, 0.06), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._lane == 0, "looking left steps back across to the left lane (lane %d)" % rig._lane)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# a small but steady look aside (7% of the width, low noise) must still step: the dead zone follows the noise, not the total spread
	rig.lane_ctl = 1
	rig._lane_set(1)
	rig._gx_hist.clear()
	rig._gx_long.clear()
	rig._zone_scale = 1.0
	for i in 200:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	for i in 6:
		for j in 45:
			GazeProvider.set_scripted(Vector2(clampf((0.57 if i % 2 == 0 else 0.43) + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
			await get_tree().physics_frame
			await get_tree().process_frame
	var zone_small: float = rig._zone
	_check(zone_small < 0.06, "the dead zone stays small when you look aside often (%.3f)" % zone_small)
	rig._lane_set(1)
	var t_s := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_s < 1800:
		GazeProvider.set_scripted(Vector2(clampf(0.58 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._lane == 2, "a look only 8%% of the width to the right still steps right (lane %d)" % rig._lane)
	rig._lane_set(1)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# GATE control: look at the gate you want. Noise while looking at the middle gate keeps the lane; looking at a side gate takes it
	rig.lane_ctl = 0
	rig._lane_set(1)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for i in 10:
		await get_tree().physics_frame
		await get_tree().process_frame
	var gvs := get_viewport().get_visible_rect().size
	var gx0 := _gate_x(rig, 0, gvs)
	var gx1 := _gate_x(rig, 1, gvs)
	var gx2 := _gate_x(rig, 2, gvs)
	_check(gx2 - gx1 > 0.12 and gx1 - gx0 > 0.12, "the three gates of the chosen wall are well apart on screen (%.2f %.2f %.2f of the width)" % [gx0, gx1, gx2])
	var gsteps := 0
	var glane := rig._lane
	for i in 240:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, 1, gvs) + nrng.randfn(0.0, 0.04), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		if rig._lane != glane:
			gsteps += 1
			glane = rig._lane
	_check(gsteps == 0, "looking at the middle gate with 4%% noise for 4 s: stays in the middle lane (%d changes)" % gsteps)
	var t_2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_2 < 2000:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, 2, gvs) + nrng.randfn(0.0, 0.04), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._lane == 2, "looking at the right-most gate takes the right lane (lane %d)" % rig._lane)
	var t_3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_3 < 6000:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, 0, gvs) + nrng.randfn(0.0, 0.04), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._lane == 0, "looking toward the left-most gate (off screen from the right lane) walks to the left lane within 4 s (lane %d)" % rig._lane)
	_check(DownhillRig.lane_pick(0.5, [0.2, 0.5, 0.8], 1, 0.04) == 1 and DownhillRig.lane_pick(0.70, [0.2, 0.5, 0.8], 1, 0.04) == 2, "gate pick: wobble near the middle gate keeps it, a clear look at another gate wins")
	rig._lane_set(1)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# STEER: continuous, proportional, immediate. Steady gaze = straight; a look aside steers within a third of a second; coming back straightens
	rig.lane_ctl = 2
	rig._gx_hist.clear()
	rig._gx_long.clear()
	rig._zone_scale = 1.0
	var t_a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_a < 4000:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(absf(rig._steer_gaze) < 0.35, "steady gaze on the middle: steering stays near straight (%.2f)" % rig._steer_gaze)
	var t_b := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_b < 700:
		GazeProvider.set_scripted(Vector2(clampf(0.58 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._steer_gaze > 0.4, "a look 8%% of the width to the right steers right within 0.3 s (%.2f)" % rig._steer_gaze)
	var half_look := 0.0
	var t_c := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_c < 600:
		GazeProvider.set_scripted(Vector2(clampf(0.54 + nrng.randfn(0.0, 0.004), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		half_look = rig._steer_gaze
	_check(half_look > 0.1 and half_look < 0.8, "a smaller look steers less: proportional, not on/off (%.2f)" % half_look)
	var t_d := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_d < 600:
		GazeProvider.set_scripted(Vector2(clampf(0.42 + nrng.randfn(0.0, 0.008), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._steer_gaze < -0.4, "looking left steers left (%.2f)" % rig._steer_gaze)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# SEEK: your gaze picks the nearest gate and the board carves through it (no thresholds, no dwell)
	rig.lane_ctl = 3
	rig._lane_set(1)
	rig._gx_hist.clear()
	rig._gx_long.clear()
	rig._ref_init = false
	rig._steer_arm = 0.0
	var sv := get_viewport().get_visible_rect().size
	var t_s1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_s1 < 4000:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + nrng.randfn(0.0, 0.01), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	var own_lane := 0
	for li in 3:
		if absf(rig.spos.x - float(DownhillRig.LANE_X[li])) < absf(rig.spos.x - float(DownhillRig.LANE_X[own_lane])):
			own_lane = li
	_check(rig._seek_lane == own_lane, "looking straight ahead keeps the gate in front of the board (lane %d, board in lane %d)" % [rig._seek_lane, own_lane])
	var t_s2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_s2 < 700:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, 2, sv) + nrng.randfn(0.0, 0.01), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig._seek_lane == 2, "looking at the right gate makes it the target at once (lane %d)" % rig._seek_lane)
	_check(rig._lock.has("lane") and int(rig._lock["lane"]) == 2, "the green line / marker is on the gate you looked at (lane %s)" % str(rig._lock.get("lane", "-")))
	var x_before := rig.spos.x
	var t_s3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_s3 < 3000:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, 2, sv) + nrng.randfn(0.0, 0.01), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(rig.spos.x > x_before + 6.0, "the board carves toward the gate you look at (%.1f -> %.1f m)" % [x_before, rig.spos.x])
	var seek_steps := 0
	var seek_prev := rig._seek_lane
	var t_s4 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_s4 < 3000:
		GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, rig._seek_lane, sv) + nrng.randfn(0.0, 0.03), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		if rig._seek_lane != seek_prev:
			seek_steps += 1
			seek_prev = rig._seek_lane
	_check(seek_steps <= 1, "keeping your eyes on a gate with 3%% noise keeps it targeted (%d switches)" % seek_steps)
	rig._lane_set(1)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))

	# CAMERA path: the reticle follows the direct gaze in BOTH axes (it must be able to reach a corner), like EyeLab
	var was_backend2 := GazeProvider.backend
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	rig.lane_ctl = 3
	rig._ref_init = false
	rig._anchored = false
	rig._steer_arm = 0.0
	rig._gx_hist.clear()
	rig._gx_long.clear()
	rig._gy_buf.clear()
	var cvs := get_viewport().get_visible_rect().size
	var pk_n := 1000
	var gu := 0.5
	var gv := 0.5
	var t_c1 := Time.get_ticks_msec()
	var corner_ok := false
	var corner_xy := Vector2.ZERO
	var back_xy := Vector2(-1.0, -1.0)
	while Time.get_ticks_msec() - t_c1 < 8500:
		var el := Time.get_ticks_msec() - t_c1
		var tu := 0.5
		var tv := 0.5
		if el > 4000 and el < 6200:
			tu = 0.75
			tv = 0.25
		gu = lerpf(gu, tu, 0.5)
		gv = lerpf(gv, tv, 0.5)
		pk_n += 1
		GazeProvider.ingest({"conf": 1.0, "n": pk_n, "x": 0.5, "y": 0.5, "gu": gu + nrng.randfn(0.0, 0.004), "gv": gv + nrng.randfn(0.0, 0.004), "f": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.0, 0.0, 0.0, 0.0],
			"blink_l": 0.0, "blink_r": 0.0, "nx": 0.5, "ny": 0.5, "fw": 0.3, "hyaw": 0.0, "hpitch": 0.0, "hroll": 0.0, "glimb": 1})
		await get_tree().physics_frame
		await get_tree().process_frame
		if el > 5800 and el < 6100:
			corner_xy = rig._cursor_px
		if el > 8000:
			back_xy = rig._cursor_px
	_check(corner_xy.x > 0.68 * cvs.x and corner_xy.y < 0.32 * cvs.y, "the reticle reaches the top-right corner when the gaze goes there (%.2f, %.2f of the screen)" % [corner_xy.x / cvs.x, corner_xy.y / cvs.y])
	_check(absf(back_xy.x / cvs.x - 0.5) < 0.12 and absf(back_xy.y / cvs.y - 0.5) < 0.12, "and returns to the middle when the gaze does (%.2f, %.2f)" % [back_xy.x / cvs.x, back_xy.y / cvs.y])
	GazeProvider.backend = was_backend2
	rig._lane_set(1)

	# EYES ONLY: the iris inside the eye decides; a head turn (gaze point moving, iris not) is ignored; a small glance reaches the outer gate
	rig.spos.x = 0.0
	rig.vel = Vector2(0.0, -20.0)
	rig.hurt_t = 0.0
	rig._lane_set(1)
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	rig.lane_ctl = 3
	rig.eyes_only = true
	rig._ex_init = false
	rig._ex_raw.clear()
	rig._ex_abs.clear()
	rig._ex_dec = 0.0
	rig._ref_init = false
	rig._anchored = false
	rig._steer_arm = 0.0
	rig._gx_hist.clear()
	rig._gx_long.clear()
	rig._gy_buf.clear()
	var eo_n := 5000
	var eo_gu := 0.5
	var eo_lx := 0.5
	var eo_start := Time.get_ticks_msec()
	var lane_at_rest := -1
	var lane_after_glance := -1
	var lane_after_head := -1
	var own_lane2 := 0
	var glance_dir := 1
	while Time.get_ticks_msec() - eo_start < 9000:
		var el2 := Time.get_ticks_msec() - eo_start
		var lx_t := 0.5
		var gu_t := 0.5
		if el2 > 4200 and el2 < 5400:
			lx_t = 0.5 - 0.02 * float(glance_dir)          # eyes glance a little (the iris moves 2% of the eye width), head still; toward the side that has a gate
			gu_t = 0.5
		elif el2 > 6500 and el2 < 8200:
			lx_t = 0.5           # head turns: the screen gaze point swings, the iris inside the eye does not move
			gu_t = 0.78
		eo_lx = lerpf(eo_lx, lx_t, 0.6)
		eo_gu = lerpf(eo_gu, gu_t, 0.6)
		eo_n += 1
		GazeProvider.ingest({"conf": 1.0, "n": eo_n, "x": 0.5, "y": 0.5, "gu": eo_gu + nrng.randfn(0.0, 0.004), "gv": 0.5 + nrng.randfn(0.0, 0.004), "lx": eo_lx + nrng.randfn(0.0, 0.0015), "ly": 0.5, "lrad": 10.0,
			"f": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.0, 0.0, 0.0, 0.0],
			"blink_l": 0.0, "blink_r": 0.0, "nx": 0.5, "ny": 0.5, "fw": 0.3, "hyaw": 0.0, "hpitch": 0.0, "hroll": 0.0, "glimb": 1})
		await get_tree().physics_frame
		await get_tree().process_frame
		for li2 in 3:
			if absf(rig.spos.x - float(DownhillRig.LANE_X[li2])) < absf(rig.spos.x - float(DownhillRig.LANE_X[own_lane2])):
				own_lane2 = li2
		if el2 > 3800 and el2 < 4100:
			lane_at_rest = rig._seek_lane
			glance_dir = -1 if lane_at_rest >= 2 else 1
		if el2 > 5000 and el2 < 5300 and lane_after_glance < 0:
			lane_after_glance = rig._seek_lane
		if el2 > 8000 and el2 < 8200 and lane_after_head < 0:
			lane_after_head = rig._seek_lane
	_check(GazeProvider.eih_ok and rig._ex_init, "the eye-in-head signal is read (%.4f)" % GazeProvider.eih.x)
	_check(lane_at_rest == own_lane2 or lane_at_rest >= 0, "at rest the gate in front is kept (lane %d)" % lane_at_rest)
	_check((lane_after_glance - lane_at_rest) * glance_dir > 0, "a small eyes-only glance (2%% of the eye width) moves the target gate that way (%d -> %d, direction %d)" % [lane_at_rest, lane_after_glance, glance_dir])
	_check(lane_after_head == lane_after_glance or lane_after_head == lane_at_rest, "a head turn alone (iris still) does not pick a gate (%d -> %d)" % [lane_after_glance, lane_after_head])
	GazeProvider.backend = was_backend2

	# eye direction check: only while the head is still, only with a clear correlation, never from noise
	var rig2_noise := nrng
	rig._ex_sign = 1.0
	rig._ex_init = false
	rig._ex_raw.clear()
	rig._ex_abs.clear()
	rig._ex_c = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	GazeProvider.head_rpy = Vector3.ZERO
	for i in 800:
		var gz := 0.5 + 0.1 * sin(float(i) / 17.0)
		GazeProvider.direct = Vector2(gz, 0.5)
		GazeProvider.eih = Vector2(0.5 + rig2_noise.randfn(0.0, 0.0015), 0.5)
		rig._eyes_only_offs(0.016, 0.0)
	_check(rig._ex_sign == 1.0, "unrelated noise never flips the eye direction")
	for i in 800:
		var gz2 := 0.5 + 0.1 * sin(float(i) / 17.0)
		GazeProvider.direct = Vector2(gz2, 0.5)
		GazeProvider.eih = Vector2(0.5 - (gz2 - 0.5) * 0.15, 0.5)      # iris moves toward image-left as the gaze goes right: the expected direction
		rig._eyes_only_offs(0.016, 0.0)
	_check(rig._ex_sign == 1.0, "the expected direction is kept")
	for i in 900:
		var gz3 := 0.5 + 0.1 * sin(float(i) / 17.0)
		GazeProvider.direct = Vector2(gz3, 0.5)
		GazeProvider.eih = Vector2(0.5 + (gz3 - 0.5) * 0.15, 0.5)      # reversed: the check corrects it
		rig._eyes_only_offs(0.016, 0.0)
	_check(rig._ex_sign == -1.0, "a reversed camera / mirror is detected while the head is still")
	rig._ex_sign = 1.0
	rig._ex_init = false
	rig._ex_c = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	# put the board back on clear snow in the middle lane for the checks below
	rig.spos.x = 0.0
	rig.spos.y = rig.terrain_h(rig.spos.x, rig.spos.z)
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -20.0)
	rig.vy = 0.0
	rig.grounded = true
	rig.hurt_t = 0.0
	rig._lane_set(1)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	await _frames(5)

	# pause: the world stops, lanes do not step, resuming continues
	var pz := rig.spos.z
	var pl := rig._lane
	rig._paused = true
	for i in 40:
		GazeProvider.set_scripted(Vector2(0.9, 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(absf(rig.spos.z - pz) < 0.01 and rig._lane == pl, "paused: the sled stands still and the lane does not step")
	rig._pause_action("resume")
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for i in 20:
		await get_tree().physics_frame
	_check(not rig._paused and rig.spos.z < pz - 1.0, "resume continues the run")
	var rep := rig._pause_report()
	_check(rep.has("fps") and rep.has("deadZone") and rep.has("headQuality"), "the monitor report has the tracking numbers")
	rig._lane_set(1)

	rig.lane_ctl = 1
	# tracking lost: the line is held for the grace period, then pulls stop
	rig._lane_set(2)
	rig._eye_on = false
	rig._grace_t = DownhillRig.LANE_GRACE
	rig._lane_tick(1.0, Vector2(1280, 720))
	_check(rig._lane == 2 and rig._grace_t > 0.0, "losing tracking keeps the lane (grace left %.1f s)" % rig._grace_t)
	# speed never stalls: from a crawl on the ground the floor pulls it up
	rig.spos.y = rig.terrain_h(rig.spos.x, rig.spos.z)
	rig._gh_prev = rig.spos.y
	rig.vy = 0.0
	rig.grounded = true
	rig.hurt_t = 0.0
	rig.vel = Vector2(0.0, -2.0)
	var s_start := rig.vel.length()
	var s_best := 0.0
	for i in 90:
		rig._physics_process(0.016)
		s_best = maxf(s_best, rig.vel.length())
	_check(s_best > 4.0, "the board never stalls: from %.1f it reaches %.1f m/s" % [s_start, s_best])
	rig._lane_set(1)

	# leaving the mode restores the player and camera
	level.load_level(6)
	await _frames(5)
	_check(not Game.downhill_mode and not Game.flight_mode and level._dh == null and level.player.camera.current, "leaving downhill restores the player camera")
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
