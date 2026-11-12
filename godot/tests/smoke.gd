extends Node
## Headless smoke test:
##   Godot_console.exe --headless --path . res://tests/smoke.tscn
## Exercises: all 5 levels, all 15 characters, damage/death/loot, XP + skills,
## gear, power-ups, zones, weapons.

var _failed := false

func _check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		_failed = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Point the scripted gaze at a world position for `frames` physics frames.
func _stare_at(player: PlayerController, world_pos: Vector3, frames: int) -> void:
	for i in frames:
		var vp := get_viewport().get_visible_rect().size
		GazeProvider.set_scripted(player.camera.unproject_position(world_pos) / vp)
		await get_tree().physics_frame


func _gaze_tests(level: MainLevel, player: PlayerController, dir: WaveDirector) -> void:
	for c in level.enemies_root.get_children():
		c.queue_free()
	level.load_level(0)
	await _frames(5)
	var gaze: GazeTargeting = level.gaze
	gaze.pan_enabled = false
	player.revive(Vector3(0, 0.05, 20))
	player.rotation = Vector3.ZERO
	player.head.rotation.x = 0.0
	GazeProvider.set_scripted(Vector2(0.5, 0.5))
	GazeProvider.set_active(true)
	await _frames(3)

	# stare-lock -> bullet time -> blink volley
	var foe := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 8))
	await _frames(2)
	var hp0 := foe.health
	await _stare_at(player, foe.global_position + Vector3.UP, 45)
	_check(gaze.tags.has(foe), "stare-lock tagged the enemy (dwell)")
	_check(Engine.time_scale < 0.5, "bullet time engaged (%.2f)" % Engine.time_scale)
	GazeProvider.blinked.emit()
	GazeProvider.set_scripted(Vector2(0.95, 0.05))
	await get_tree().create_timer(0.7, true, false, true).timeout
	_check(foe.health < hp0 or foe.dying, "blink volley damaged the target (%d -> %d)" % [int(hp0), int(foe.health)])
	_check(is_equal_approx(Engine.time_scale, 1.0) and gaze.tags.is_empty(), "bullet time ended after volley (ts=%.2f tags=%d bt=%s vol=%s)" % [Engine.time_scale, gaze.tags.size(), gaze.bullet_time, gaze._volleying])
	if is_instance_valid(foe):
		foe.queue_free()
	await _frames(3)

	# a quick glance must not lock
	gaze.reset()
	await get_tree().create_timer(1.0, true, false, true).timeout
	var foe2 := dir.spawn_enemy(&"bouncer", Vector3(0, 0.1, 8))
	await _frames(2)
	gaze.reset()
	for i in 15:
		GazeProvider.set_scripted(player.camera.unproject_position(foe2.global_position + Vector3.UP) / get_viewport().get_visible_rect().size)
		await get_tree().physics_frame
	_check(gaze.tags.is_empty(), "a quick glance does not lock (tags=%d dwell=%.2f tgt=%s)" % [gaze.tags.size(), gaze.dwell, gaze.target])
	gaze.reset()
	if is_instance_valid(foe2):
		foe2.queue_free()
	await _frames(3)

	# floor stare -> auto-walk (clear props so nothing steals the stare)
	gaze.reset()
	for pr in level.props_root.get_children():
		pr.queue_free()
	for en in level.enemies_root.get_children():
		en.queue_free()
	await _frames(3)
	var p0 := player.global_position
	player.revive(Vector3(0, 0.05, 28))
	p0 = player.global_position
	await _frames(3)
	GazeProvider.set_scripted(Vector2(0.5, 0.78))
	await _frames(80)
	_check(gaze.waypoint != Vector3.INF or player.global_position.distance_to(p0) > 0.5, "floor stare set a waypoint")
	await _frames(60)
	_check(player.global_position.distance_to(p0) > 1.0, "player auto-walked toward the waypoint (%.1fm)" % player.global_position.distance_to(p0))
	gaze.reset()

	# edge gaze pans the camera
	gaze.pan_enabled = true
	var yaw0 := player.rotation.y
	GazeProvider.set_scripted(Vector2(0.97, 0.5))
	await _frames(30)
	_check(absf(player.rotation.y - yaw0) > 0.2, "edge gaze pans the camera (%.2f rad)" % absf(player.rotation.y - yaw0))

	# tracker packets: a deliberate blink fires, a normal flicker does not
	GazeProvider.set_active(false)
	GazeProvider.set_backend(GazeProvider.Backend.UDP)
	var blinks: Array[int] = [0]
	var cb := func() -> void: blinks[0] += 1
	GazeProvider.blinked.connect(cb)
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 1.0, "blink_r": 1.0})
	await get_tree().create_timer(0.08, true, false, true).timeout
	GazeProvider.ingest({"blink_l": 0.0, "blink_r": 0.0})
	_check(blinks[0] == 0, "natural short blink ignored")
	GazeProvider.ingest({"blink_l": 1.0, "blink_r": 1.0})
	await get_tree().create_timer(0.3, true, false, true).timeout
	GazeProvider.ingest({"blink_l": 0.0, "blink_r": 0.0})
	_check(blinks[0] == 1, "deliberate hard blink detected")
	GazeProvider.blinked.disconnect(cb)
	GazeProvider.set_backend(GazeProvider.Backend.MOUSE)
	Engine.time_scale = 1.0

	# ---- touch controls: stick moves, look finger turns, buttons press actions
	var tc: TouchControls = null
	for c in level.get_node("UI").get_children():
		if c is TouchControls:
			tc = c
	_check(tc != null, "TouchControls present")
	Game.touch_mode = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var sz := tc.size
	tc._press(1, Vector2(sz.x * 0.15, sz.y * 0.7))
	tc._move(1, Vector2(sz.x * 0.15, sz.y * 0.7 - 80.0), Vector2.ZERO)
	_check(Input.is_action_pressed(&"move_forward"), "touch stick presses move_forward")
	tc._release(1)
	_check(not Input.is_action_pressed(&"move_forward"), "stick release clears movement")
	var yaw1 := player.rotation.y
	tc._press(2, Vector2(sz.x * 0.7, sz.y * 0.3))
	tc._move(2, Vector2(sz.x * 0.7 + 100.0, sz.y * 0.3), Vector2(100.0, 0.0))
	tc._release(2)
	_check(absf(player.rotation.y - yaw1) > 0.2, "touch look drag turns the player")
	tc._btn_down("fire")
	_check(Game.touch_fire, "FIRE button sets touch_fire")
	tc._btn_up("fire")
	tc._btn_down("jump")
	_check(Input.is_action_pressed(&"jump"), "JUMP button presses jump")
	tc._btn_up("jump")
	# touch hands-free: finger = gaze, FIRE = blink, guide ticks off
	tc.toggle_hands_free()
	_check(GazeProvider.active and GazeProvider.backend == GazeProvider.Backend.TOUCH, "EYES button starts touch hands-free")
	var g2: GazeTargeting = level.gaze
	g2.pan_enabled = false
	player.revive(Vector3(0, 0.05, 20))
	player.rotation = Vector3.ZERO
	player.head.rotation.x = 0.0
	var foe3 := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 8))
	await _frames(2)
	for i in 45:
		var p3 := player.camera.unproject_position(foe3.global_position + Vector3.UP) / get_viewport().get_visible_rect().size
		tc._press(3, p3 * sz) if i == 0 else tc._move(3, p3 * sz, Vector2.ZERO)
		await get_tree().physics_frame
	tc._release(3)
	_check(g2.tags.has(foe3) and g2.guide["lock"], "touch gaze locked an enemy and ticked the guide")
	tc._btn_down("fire")
	tc._btn_up("fire")
	await get_tree().create_timer(0.9, true, false, true).timeout
	_check(g2.guide["fire"], "BLINK button fired the volley (guide ticked)")
	GazeProvider.set_active(false)
	g2.reset()
	Game.touch_mode = false
	Engine.time_scale = 1.0


func _weapon_tests(level: MainLevel, player: PlayerController, dir: WaveDirector) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	level.load_level(0)
	await _frames(5)
	level.gaze.pan_enabled = false
	player.revive(Vector3(0, 0.05, 20))
	player.rotation = Vector3.ZERO
	player.head.rotation.x = 0.0
	var wm: WeaponManager = player.weapons
	var shock: ShockRifle = null
	var rocket: RocketLauncher = null
	for w in wm.weapons:
		if w is ShockRifle:
			shock = w
		elif w is RocketLauncher:
			rocket = w
	_check(shock != null and rocket != null, "Shock Rifle and Rocket Launcher present (%d guns)" % wm.weapons.size())
	wm.select(wm.weapons.find(shock))
	await _frames(15)

	# shock beam (hitscan) damages
	var foe := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 8))
	await _frames(3)
	var hp0 := foe.health
	for attempt in 3:
		shock._cd = 0.0
		shock.primary_pressed()
		await _frames(4)
		if foe.health < hp0:
			break
	_check(foe.health < hp0, "shock beam damaged the target (%d -> %d)" % [int(hp0), int(foe.health)])

	# aim assist scales with input device: mouse is exact, touch/gaze get a cone
	var cam := player.camera
	var to_foe := (foe.global_position + Vector3.UP - cam.global_position).normalized()
	var off_dir := to_foe.rotated(Vector3.UP, deg_to_rad(3.5))
	Game.touch_mode = false
	var a_mouse := AimAssist.assist(get_tree(), cam, cam.global_position, off_dir)
	Game.touch_mode = true
	var a_touch := AimAssist.assist(get_tree(), cam, cam.global_position, off_dir)
	Game.touch_mode = false
	_check(rad_to_deg(a_mouse.angle_to(to_foe)) > 3.0, "mouse aim is NOT bent (%.1f deg off)" % rad_to_deg(a_mouse.angle_to(to_foe)))
	_check(rad_to_deg(a_touch.angle_to(to_foe)) < 0.5, "touch aim snaps to the enemy 3.5 deg away")

	# shock core + beam = combo
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(3)
	var far := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 6))
	await _frames(3)
	shock._cd = 0.0
	shock.alt_pressed()
	await _frames(14)
	_check(get_tree().get_nodes_in_group("shock_cores").size() == 1, "shock core in flight")
	var fhp := far.health
	shock._cd = 0.0
	shock.primary_pressed()
	await _frames(4)
	_check(get_tree().get_nodes_in_group("shock_cores").is_empty() and (far.health < fhp or far.dying), "beam through core = SHOCK COMBO (%d -> %d)" % [int(fhp), int(far.health)])

	# rocket launcher: one rocket, then a loaded fan
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(3)
	wm.select(wm.weapons.find(rocket))
	await _frames(15)
	var rfoe := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 8))
	await _frames(3)
	var rhp := rfoe.health
	rocket.primary_pressed()
	await _frames(70)
	_check(rfoe.health < rhp or rfoe.dying, "rocket exploded on the target (%d -> %d)" % [int(rhp), int(rfoe.health)])
	rocket._cd = 0.0
	rocket.alt_pressed()
	rocket.alt_held(0.6)
	rocket.alt_held(0.6)
	_check(rocket._loaded == 3, "alt-fire loads rockets (%d)" % rocket._loaded)
	rocket.alt_released()
	_check(rocket._loaded == 0 and rocket._cd > 0.5, "released: fan fired")
	await _frames(90)

	# hands-free: wink swaps guns, blink fires at the gaze point, head lean moves you
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(3)
	GazeProvider.set_scripted(Vector2(0.5, 0.5))
	GazeProvider.set_active(true)
	var g: GazeTargeting = level.gaze
	await _frames(3)
	var cur := wm.current
	GazeProvider.winked.emit(false)
	_check(wm.current != cur and g.guide["swap"], "wink swapped guns (%d -> %d)" % [cur, wm.current])
	wm.select(wm.weapons.find(shock))
	await _frames(15)
	var gfoe := dir.spawn_enemy(&"tank", Vector3(0, 0.1, 8))
	await _frames(3)
	var ghp := gfoe.health
	var vp := get_viewport().get_visible_rect().size
	GazeProvider.set_scripted(cam.unproject_position(gfoe.global_position + Vector3.UP) / vp)
	await get_tree().process_frame
	await get_tree().process_frame
	shock._cd = 0.0
	GazeProvider.blinked.emit()
	await _frames(3)
	_check(gfoe.health < ghp, "blink fired the shock rifle at the gaze point (%d -> %d)" % [int(ghp), int(gfoe.health)])
	g.reset()
	GazeProvider.set_scripted(Vector2(0.5, 0.95))
	var z0 := player.global_position
	GazeProvider.head_move = Vector2(0, -1)
	await _frames(40)
	GazeProvider.head_move = Vector2.ZERO
	_check(player.global_position.distance_to(z0) > 1.0 and g.guide["move"], "leaning in walks you forward (%.1fm)" % player.global_position.distance_to(z0))
	# tracker packets: lean right = strafe right
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.5, "fw": 0.3})
	for i in 6:
		GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.68, "fw": 0.3})
	_check(GazeProvider.head_move.x > 0.3, "tracker nose offset -> strafe (%.2f)" % GazeProvider.head_move.x)
	GazeProvider.set_active(false)
	GazeProvider.head_move = Vector2.ZERO
	Engine.time_scale = 1.0

	# ---- gesture detection is relative to each eye's own baseline
	GazeProvider.reset_gestures()
	var winks: Array[int] = [0, 0]
	var blinks2: Array[int] = [0]
	var cw := func(left: bool) -> void: winks[0 if left else 1] += 1
	var cb := func() -> void: blinks2[0] += 1
	GazeProvider.winked.connect(cw)
	GazeProvider.blinked.connect(cb)
	for i in 30:
		GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.22, "blink_r": 0.12})   # asymmetric "open" eyes
	_check(winks[0] + winks[1] == 0 and blinks2[0] == 0, "open eyes with different baselines trigger nothing")
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.62, "blink_r": 0.13})
	await get_tree().create_timer(0.2, true, false, true).timeout
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.62, "blink_r": 0.13})
	_check(winks[0] == 1, "left wink detected with a modest 0.62 closure")
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.22, "blink_r": 0.12})
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.12, "blink_r": 0.55})
	await get_tree().create_timer(0.2, true, false, true).timeout
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.22, "blink_r": 0.55})
	_check(winks[1] == 1, "right wink detected")
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.22, "blink_r": 0.12})
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.6, "blink_r": 0.5})
	await get_tree().create_timer(0.25, true, false, true).timeout
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.6, "blink_r": 0.5})
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "blink_l": 0.22, "blink_r": 0.12})
	_check(blinks2[0] == 1, "two-eye blink fires exactly one blink (no wink)")
	GazeProvider.winked.disconnect(cw)
	GazeProvider.blinked.disconnect(cb)

	# ---- 5-point calibration maths: noisy, biased, inverted-y raw signals still map to the screen
	GazeProvider.set_backend(GazeProvider.Backend.MOUSE)
	GazeProvider.start_calibration()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for pi in GazeProvider.CAL_POINTS.size():
		var sp: Vector2 = GazeProvider.CAL_POINTS[pi]
		for k in 30:
			# raw iris = biased, 3x compressed, y inverted; blendshape signal = pure noise
			var iris := Vector2(0.3 + sp.x * 0.12 + rng.randf_range(-0.004, 0.004), 0.7 - sp.y * 0.10 + rng.randf_range(-0.004, 0.004))
			var bs := Vector2(rng.randf_range(0.4, 0.6), rng.randf_range(0.4, 0.6))
			(GazeProvider._cal_samples[pi] as Array).append([iris, bs])
	GazeProvider.cal_index = -1
	GazeProvider._finish_calibration()
	var probe := func(sp: Vector2) -> Vector2:
		var iris := Vector2(0.3 + sp.x * 0.12, 0.7 - sp.y * 0.10)
		GazeProvider._raw_iris = iris
		GazeProvider._raw_bs = Vector2(0.5, 0.5)
		return Vector2((GazeProvider._feat_vec(GazeProvider._feat.x).x - GazeProvider._mid.x) * GazeProvider._gain.x + 0.5,
			(GazeProvider._feat_vec(GazeProvider._feat.y).y - GazeProvider._mid.y) * GazeProvider._gain.y + 0.5)
	var pl: Vector2 = probe.call(Vector2(0.15, 0.5))
	var pr: Vector2 = probe.call(Vector2(0.85, 0.5))
	var pt: Vector2 = probe.call(Vector2(0.5, 0.15))
	var pb: Vector2 = probe.call(Vector2(0.5, 0.85))
	_check(GazeProvider._feat == Vector2i(0, 0), "calibration picks the steady iris signal over the noisy one")
	_check(absf(pl.x - 0.15) < 0.05 and absf(pr.x - 0.85) < 0.05, "calibration maps left/right to the screen (%.2f, %.2f)" % [pl.x, pr.x])
	_check(absf(pt.y - 0.15) < 0.05 and absf(pb.y - 0.85) < 0.05, "calibration fixes inverted y (%.2f, %.2f)" % [pt.y, pb.y])
	GazeProvider._calibrated = false

	# ---- calibration-free: a biased, mis-scaled geometry signal is centred and rescaled by itself
	GazeProvider._geo_buf.clear()
	GazeProvider._geo_n = 0
	GazeProvider._geo_mu = Vector2(0.5, 0.5)
	GazeProvider._geo_var = Vector2(0.04, 0.02)
	GazeProvider._open_mu = 0.0
	GazeProvider._open_var = 0.0004
	GazeProvider._zv_var = 1.0
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 3
	for i in 300:
		# true gaze wanders +-0.2 / +-0.12 about the centre; the signal is offset by (+0.4, -0.25) and shrunk to 40%
		var tx := rng3.randfn(0.0, 0.2)
		var ty := rng3.randfn(0.0, 0.12)
		GazeProvider._geo_push(Vector2(0.5 + 0.4 + tx * 0.4, 0.5 - 0.25 + ty * 0.4) + Vector2(rng3.randfn(0, 0.01), rng3.randfn(0, 0.01)))
	var probe_t := Vector2(0.5 + 0.4 + 0.2 * 0.4, 0.5 - 0.25 + 0.0)
	for i in 8:
		GazeProvider._geo_push(probe_t)
	_check(absf(GazeProvider._geo_out.x - 0.7) < 0.12 and absf(GazeProvider._geo_out.y - 0.5) < 0.08, "geometry auto-fit removes offset and rescales (%.2f, %.2f vs 0.70, 0.50)" % [GazeProvider._geo_out.x, GazeProvider._geo_out.y])
	# vertical: the eyes barely move (spread 0.02) but the eyelid signal moves a lot; both must give full range
	GazeProvider._geo_buf.clear()
	GazeProvider._geo_n = 0
	GazeProvider._geo_mu = Vector2(0.5, 0.5)
	GazeProvider._geo_var = Vector2(0.04, 0.02)
	GazeProvider._open_mu = 0.0
	GazeProvider._open_var = 0.0004
	GazeProvider._zv_var = 1.0
	for i in 400:
		var ly := rng3.randfn(0.0, 1.0)         # true vertical gaze, in standard deviations
		GazeProvider._geo_push(Vector2(0.5, 0.5 + ly * 0.02 + rng3.randfn(0, 0.004)), 0.30 - ly * 0.03 + rng3.randfn(0, 0.004))
	for i in 8:
		GazeProvider._geo_push(Vector2(0.5, 0.5 + 1.5 * 0.02), 0.30 - 1.5 * 0.03)        # look down 1.5 sd
	var vd := GazeProvider._geo_out.y
	for i in 8:
		GazeProvider._geo_push(Vector2(0.5, 0.5 - 1.5 * 0.02), 0.30 + 1.5 * 0.03)        # look up 1.5 sd
	var vu := GazeProvider._geo_out.y
	_check(vd > 0.68 and vu < 0.32, "weak vertical eye movement still spans the screen (down %.2f, up %.2f)" % [vd, vu])
	GazeProvider._geo_ok = false

	# head pose: a head that rests tilted back is the new centre, small nods span the screen, and a weaker
	# 'down' direction (eyelids hide the pupil) is boosted to match 'up'
	GazeProvider._geo_buf.clear()
	GazeProvider._hbuf.clear()
	GazeProvider._geo_n = 0
	GazeProvider._geo_mu = Vector2(0.5, 0.5)
	GazeProvider._geo_var = Vector2(0.04, 0.02)
	GazeProvider._open_mu = 0.0
	GazeProvider._open_var = 0.0004
	GazeProvider._zv_var = 1.0
	GazeProvider._zx_var = 1.0
	GazeProvider._zp = 1.0
	GazeProvider._zn = 1.0
	GazeProvider._hd_mu = Vector2.ZERO
	GazeProvider._hd_var = Vector2(0.001, 0.0005)
	GazeProvider._head_sign = Vector2(1, 1)
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 9
	var hw_saved := GazeProvider.head_weight
	GazeProvider.head_weight = 0.65     # this block tests the head path; the shipped default lets the eyes lead
	var tilt := 0.35     # head rests tilted back 0.35 rad
	for i in 600:
		var ny := rng4.randfn(0.0, 1.0)                        # nod: +down. Down movement is only half as large as up
		var pitch := tilt + (ny * 0.02 * (0.5 if ny > 0.0 else 1.0))
		var yaw := rng4.randfn(0.0, 1.0) * 0.04
		GazeProvider._geo_push(Vector2(0.5, 0.5) + Vector2(rng4.randfn(0, 0.02), rng4.randfn(0, 0.004)), 0.30, Vector2(yaw, pitch))
	for i in 8:
		GazeProvider._geo_push(Vector2(0.5, 0.5), 0.30, Vector2(0.0, tilt + 0.01))        # small nod down (0.5 sd of 'up' scale)
	var hd_down := GazeProvider._geo_out.y
	for i in 8:
		GazeProvider._geo_push(Vector2(0.5, 0.5), 0.30, Vector2(0.0, tilt - 0.02))        # nod up 1 sd
	var hd_up := GazeProvider._geo_out.y
	for i in 8:
		GazeProvider._geo_push(Vector2(0.5, 0.5), 0.30, Vector2(0.0, tilt))               # back to the resting tilt
	var hd_rest := GazeProvider._geo_out.y
	_check(absf(hd_rest - 0.5) < 0.08, "a head resting tilted back is treated as the centre (%.2f)" % hd_rest)
	_check(hd_down > 0.62 and hd_up < 0.4, "head nods drive vertical aim, down boosted to match up (down %.2f, up %.2f)" % [hd_down, hd_up])
	GazeProvider.head_weight = hw_saved
	GazeProvider._geo_ok = false

	# ---- peek lean is in real centimetres: the same lean gives the same peek on a desk and on a phone
	var lean_at := func(fw: float, dnx: float) -> float:
		GazeProvider.reset_gestures()
		GazeProvider._head_ok = false
		GazeProvider._pk_buf.clear()
		GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.5, "ny": 0.5, "fw": fw, "hyaw": 0.0, "hpitch": 0.0, "hroll": 0.0})
		for i in 6:
			GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.5 + dnx, "ny": 0.5, "fw": fw, "hyaw": 0.0, "hpitch": 0.0, "hroll": 0.0})
		return GazeProvider._pk_target.x
	Game.touch_mode = false
	var desk: float = lean_at.call(0.15, 0.07)         # face small in the frame: a 7%-of-frame shift ~ 6.5 cm
	var phone: float = lean_at.call(0.5, 0.07 * 0.5 / 0.15)   # the same physical lean seen from arm's length
	_check(desk > 0.3 and absf(phone - desk) < 0.12, "same physical lean gives the same peek at any distance (desk %.2f m, phone %.2f m)" % [desk, phone])
	# on a held phone, turning your head drives the peek more than translation
	Game.touch_mode = true
	GazeProvider.reset_gestures()
	GazeProvider._head_ok = false
	GazeProvider._pk_buf.clear()
	GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.5, "ny": 0.5, "fw": 0.5, "hyaw": 0.0, "hpitch": 0.0, "hroll": 0.0})
	for i in 6:
		GazeProvider.ingest({"x": 0.5, "y": 0.5, "nx": 0.5, "ny": 0.5, "fw": 0.5, "hyaw": -0.2, "hpitch": 0.0, "hroll": 0.0})   # turn right ~11 deg
	_check(GazeProvider._pk_target.x > 0.5, "on a phone, turning your head right peeks right (%.2f m)" % GazeProvider._pk_target.x)
	Game.touch_mode = false
	GazeProvider._head_ok = false
	GazeProvider._pk_buf.clear()
	GazeProvider._pk_target = Vector3.ZERO

	# ---- slow trackers (phones): readings every ~0.9 s still count as a live camera
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	GazeProvider._last_packet_msec = Time.get_ticks_msec() - 900
	GazeProvider.confidence = 1.0
	_check(GazeProvider._camera_fresh(), "a camera reading 0.9 s ago is still fresh")
	GazeProvider._last_packet_msec = Time.get_ticks_msec() - 2500
	_check(not GazeProvider._camera_fresh(), "a camera silent for 2.5 s is stale")
	GazeProvider.backend = GazeProvider.Backend.MOUSE
	# touch fallbacks feed the same signals as the head
	GazeProvider.touch_lean = 1.0
	var tl := GazeProvider.peek_offset(0.5)
	GazeProvider.touch_lean = 0.0
	GazeProvider._kb_cur = Vector3.ZERO
	_check(tl.x > 0.5, "touch LEAN button peeks right (%.2f m)" % tl.x)
	GazeProvider.touch_nod_goal = -1.0
	var tn := GazeProvider.nod_state(0.3)
	GazeProvider.touch_nod_goal = 0.0
	GazeProvider._kb_nod = 0.0
	_check(tn.x < -0.1, "touch GATHER button is a chin-down (%.2f rad)" % tn.x)

	# ---- ridge regression: many coupled, noisy signals -> screen position, with honest held-out error
	GazeProvider.start_calibration()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	for pi in GazeProvider.CAL_POINTS.size():
		var sp2: Vector2 = GazeProvider.CAL_POINTS[pi]
		for k in 24:
			var fv := PackedFloat32Array()
			# 6 coupled signals: x and y each leak into several channels, plus noise and a dead channel
			fv.append(0.4 + sp2.x * 0.10 + sp2.y * 0.03 + rng2.randf_range(-0.01, 0.01))
			fv.append(0.5 + sp2.x * 0.08 + rng2.randf_range(-0.01, 0.01))
			fv.append(0.3 - sp2.y * 0.06 + sp2.x * 0.02 + rng2.randf_range(-0.01, 0.01))
			fv.append(0.3 - sp2.y * 0.05 + rng2.randf_range(-0.01, 0.01))
			fv.append(0.1 + rng2.randf_range(-0.05, 0.05))
			fv.append(sp2.x * 0.5 - sp2.y * 0.2 + rng2.randf_range(-0.02, 0.02))
			(GazeProvider._cal_samples[pi] as Array).append([Vector2.ZERO, Vector2.ZERO, fv])
	GazeProvider.cal_index = -1
	GazeProvider._finish_calibration()
	_check(GazeProvider._ridge_ok and GazeProvider.cal_error >= 0.0 and GazeProvider.cal_error < 0.08, "ridge calibration fits coupled signals (held-out error %.3f)" % GazeProvider.cal_error)
	var fvt := PackedFloat32Array([0.4 + 0.7 * 0.10 + 0.3 * 0.03, 0.5 + 0.7 * 0.08, 0.3 - 0.3 * 0.06 + 0.7 * 0.02, 0.3 - 0.3 * 0.05, 0.1, 0.7 * 0.5 - 0.3 * 0.2])
	var pred := GazeProvider._predict(fvt)
	_check(absf(pred.x - 0.7) < 0.06 and absf(pred.y - 0.3) < 0.06, "ridge predicts an unseen point (%.2f, %.2f vs 0.70, 0.30)" % [pred.x, pred.y])
	GazeProvider._ridge_ok = false


func _peek_tests(level: MainLevel, player: PlayerController, dir: WaveDirector) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	level.load_level(6)
	await _frames(8)
	_check(level.level_name == "Peek Range" and Game.peek_mode and player.rail_lock, "peek level loads in rail mode")

	# --- level design: every baddy is hidden from the rail centre, and a lean of <= 1.8 m reveals it
	var space := level.get_world_3d().direct_space_state
	var vis := func(from: Vector3, p: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, p, Game.MASK_WORLD)
		return space.intersect_ray(q).is_empty()
	var total := 0
	var hidden_ok := 0
	var reveal_ok := 0
	var worst_lean := 0.0
	var first_dx := 0.0
	var first_spec: Array = []
	for st in LevelBuilder.PEEK_STATIONS.size():
		for spec: Array in LevelBuilder.peek_baddies(st, 2):
			var pos: Vector3 = spec[1]
			total += 1
			var eye := Vector3(0.0, 1.7, LevelBuilder.PEEK_STATIONS[st])
			var seen0: bool = vis.call(eye, pos + Vector3.UP * 0.7) or vis.call(eye, pos + Vector3.UP * 1.4)
			if not seen0:
				hidden_ok += 1
			var found := 0.0
			for k in range(1, 19):
				for sgn in [-1.0, 1.0]:
					var e2 := eye + Vector3(sgn * float(k) * 0.1, 0.0, 0.0)
					if found == 0.0 and (vis.call(e2, pos + Vector3.UP * 0.7) or vis.call(e2, pos + Vector3.UP * 1.4)):
						found = sgn * float(k) * 0.1
				if found != 0.0:
					break
			if found != 0.0:
				reveal_ok += 1
				worst_lean = maxf(worst_lean, absf(found))
			if first_spec.is_empty():
				first_spec = spec
				first_dx = found
	_check(hidden_ok == total, "all %d baddies are hidden from the rail centre (%d)" % [total, hidden_ok])
	_check(reveal_ok == total, "all baddies can be revealed by a lean (%d/%d, worst lean %.1f m)" % [reveal_ok, total, worst_lean])

	# --- leaning moves the body (and cover / walls stop it)
	var x0 := player.global_position.x
	GazeProvider.peek_debug = Vector3(1.4, 0.0, 0.0)
	await _frames(50)
	_check(absf(player.global_position.x - x0 - 1.4) < 0.3, "lean moves the body out from cover (%.2f m)" % (player.global_position.x - x0))
	GazeProvider.peek_debug = Vector3(80.0, 0.0, 0.0)
	await _frames(120)
	_check(player.global_position.x < 22.6, "a huge lean is stopped by the wall (x = %.1f)" % player.global_position.x)
	GazeProvider.peek_debug = Vector3.ZERO
	await _frames(90)
	_check(absf(player.global_position.x) < 0.4, "relaxing returns you to the rail (x = %.2f)" % player.global_position.x)

	# --- a hiding baddy only reacts once you can see it
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(3)
	var cb := dir.spawn_enemy(first_spec[0], first_spec[1])
	cb.cover = true
	await _frames(15)
	_check(not cb._exposed_to_player() and cb._exposed_t <= 0.0, "cover baddy stays quiet while hidden")
	GazeProvider.peek_debug = Vector3(first_dx, 0.0, 0.0)
	await _frames(70)
	_check(cb._exposed_to_player() and cb._exposed_t > 0.2, "leaning out exposes it and it reacts (exposed %.2f s)" % cb._exposed_t)
	GazeProvider.peek_debug = Vector3.ZERO
	await _frames(50)

	# --- clear the station: the rail carries you to the next one
	var z0 := player.global_position.z
	for n in get_tree().get_nodes_in_group("enemies"):
		(n as EnemyAI).apply_hit(Vector3.ZERO, n.global_position, &"test", 9999.0)
	await get_tree().create_timer(8.0, true, false, true).timeout
	_check(level.peek_station == 1 and player.global_position.z < z0 - 15.0, "clearing a station rides the rail to the next (station %d, z %.1f)" % [level.peek_station + 1, player.global_position.z])
	GazeProvider.peek_debug = Vector3.ZERO
	level.load_level(0)
	await _frames(5)
	_check(not Game.peek_mode and not player.rail_lock, "leaving the peek level restores normal movement")


func _peek_eye_tests(level: MainLevel, player: PlayerController, dir: WaveDirector) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	GazeProvider.peek_debug = Vector3.ZERO
	level.load_level(6)
	await _frames(8)
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(3)
	GazeProvider.set_process(false)                    # we drive the gaze by hand; no browser here
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	GazeProvider.confidence = 1.0
	GazeProvider._last_packet_msec = Time.get_ticks_msec() + 3600000
	var targeting: GazeTargeting = level.gaze
	var wm: WeaponManager = player.weapons
	var shock: ShockRifle = null
	for w in wm.weapons:
		if w is ShockRifle:
			shock = w
	wm.select(wm.weapons.find(shock))
	await _frames(15)
	var decoy := dir.spawn_enemy(&"banana", (LevelBuilder.peek_baddies(0, 0)[3] as Array)[1])
	decoy.cover = true         # a spare hidden baddy keeps the station alive (clearing it would ride the rail on)

	# a baddy you can see
	var spec: Array = LevelBuilder.peek_baddies(0, 0)[0]
	var space := level.get_world_3d().direct_space_state
	var lean := 0.0
	for k in range(1, 19):
		for sgn in [-1.0, 1.0]:
			var eye := Vector3(sgn * float(k) * 0.1, 1.7, LevelBuilder.PEEK_STATIONS[0])
			var q := PhysicsRayQueryParameters3D.create(eye, (spec[1] as Vector3) + Vector3.UP * 0.7, Game.MASK_WORLD)
			if lean == 0.0 and space.intersect_ray(q).is_empty():
				lean = sgn * float(k) * 0.1
	var e := dir.spawn_enemy(spec[0], spec[1])
	e.cover = true
	GazeProvider.peek_debug = Vector3(lean * 1.4, 0.0, 0.0)
	await _frames(70)
	var vp := get_viewport().get_visible_rect().size
	var cam := player.camera

	# looking at it locks it
	for i in 40:
		GazeProvider.gaze = cam.unproject_position(e.global_position + Vector3.UP * e.s) / vp
		await get_tree().physics_frame
	_check(targeting.peek_lock == e and AimAssist.locked == e, "staring at an exposed baddy locks it")

	# the lock pulls mouse shots toward it
	var to_e := (e.global_position + Vector3.UP * e.s - cam.global_position).normalized()
	var off := to_e.rotated(Vector3.UP, deg_to_rad(4.0))
	Game.touch_mode = false
	var pulled := AimAssist.assist(get_tree(), cam, cam.global_position, off)
	AimAssist.locked = null
	var plain := AimAssist.assist(get_tree(), cam, cam.global_position, off)
	AimAssist.locked = e
	_check(rad_to_deg(pulled.angle_to(to_e)) < 0.5 and rad_to_deg(plain.angle_to(to_e)) > 3.0, "the gaze lock pulls a shot 4 deg off, mouse alone does not (%.1f vs %.1f deg)" % [rad_to_deg(pulled.angle_to(to_e)), rad_to_deg(plain.angle_to(to_e))])

	# blink fires at the lock
	var hp0 := e.health
	shock._cd = 0.0
	GazeProvider.blinked.emit()
	await _frames(4)
	_check(e.health < hp0 or e.dying, "blinking fires at the locked baddy (%d -> %d)" % [int(hp0), int(e.health)])

	# wink swaps guns
	var g0 := wm.current
	targeting._wink_cd = 0.0
	GazeProvider.winked.emit(true)
	_check(wm.current != g0, "winking swaps guns in the peek level")
	wm.select(wm.weapons.find(shock))

	# ducking back behind cover drops the lock
	GazeProvider.peek_debug = Vector3.ZERO
	await _frames(90)
	_check(targeting.peek_lock == null or not is_instance_valid(targeting.peek_lock) or e.dying, "the lock lapses when the baddy is hidden again")

	# snuffle: rest your gaze on a rock with someone behind it
	for n in get_tree().get_nodes_in_group("enemies"):
		if n != decoy:
			n.queue_free()
	await _frames(3)
	var spec2: Array = LevelBuilder.peek_baddies(0, 0)[1]
	var h := dir.spawn_enemy(spec2[0], spec2[1])
	h.cover = true
	await _frames(20)
	var cover_pt := Vector3(LevelBuilder.PEEK_COVER_X[1], 1.4, LevelBuilder.PEEK_STATIONS[0] - LevelBuilder.PEEK_COVER_DIST)
	var sn0 := targeting.sniffs
	for i in 80:
		GazeProvider.gaze = cam.unproject_position(cover_pt) / vp
		await get_tree().physics_frame
	_check(targeting.sniffs > sn0, "resting your gaze on a rock sniffs behind it (%d sniffs)" % (targeting.sniffs - sn0))

	GazeProvider.backend = GazeProvider.Backend.MOUSE
	GazeProvider.set_process(true)
	GazeProvider._last_packet_msec = -100000
	AimAssist.locked = null
	targeting.reset()
	level.load_level(0)
	await _frames(5)


func _flight_tests(level: MainLevel, player: PlayerController) -> void:
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	GazeProvider.peek_debug = Vector3.ZERO
	GazeProvider.nod_debug = Vector2.ZERO
	level.load_level(7)
	await _frames(10)
	var rig: FlightRig = level._rig
	_check(rig != null and Game.flight_mode and rig.cam.current, "flight rig starts and owns the camera")
	var z0 := rig.global_position.z
	await _frames(60)
	_check(rig.global_position.z < z0 - 10.0, "it flies forward (%.0f m)" % (z0 - rig.global_position.z))

	# chin down: gather energy, shed speed
	GazeProvider.nod_debug = Vector2(-0.30, 0.0)
	var s0 := rig.speed
	await _frames(130)
	_check(rig.energy > 20.0 and rig.speed < s0 - 3.0, "chin down gathers energy and slows (energy %.0f, speed %.1f -> %.1f)" % [rig.energy, s0, rig.speed])

	# chin snaps up: blast
	var s1 := rig.speed
	GazeProvider.nod_debug = Vector2(0.05, 2.0)
	await _frames(3)
	GazeProvider.nod_debug = Vector2(0.05, 0.0)
	await _frames(8)
	_check(rig.speed > s1 + 10.0 and rig.energy < 1.0 and rig.blast_t > 0.0, "snapping the chin up blasts (speed %.1f -> %.1f, groove x%.1f)" % [s1, rig.speed, rig.groove])

	# chin up held: float up
	GazeProvider.nod_debug = Vector2(0.30, 0.0)
	var a0 := rig.alt
	await _frames(100)
	_check(rig.alt > a0 + 5.0, "chin up floats you upward (%.0f -> %.0f m)" % [a0, rig.alt])

	# a wall: smash it while blasting, crash without
	rig.heading = 0.0
	GazeProvider.nod_debug = Vector2(0.0, 0.0)
	await _frames(20)
	var fwd := Vector3(-sin(rig.heading), 0.0, -cos(rig.heading))
	var broken0 := rig.walls_broken
	rig.alt = 6.0
	rig.blast_t = 3.0
	rig.add_wall(rig.global_position + fwd * 30.0)
	await _frames(120)
	_check(rig.walls_broken == broken0 + 1, "a blast smashes through a wall")
	var crashes0 := rig.crashes
	rig.blast_t = 0.0
	rig.speed = FlightRig.CRUISE
	rig.alt = 6.0
	rig.add_wall(rig.global_position + fwd * 30.0)
	await _frames(140)
	_check(rig.crashes == crashes0 + 1, "without a blast the wall is a crash")

	# a ring straight ahead
	rig.alt = 20.0
	rig.vy = 0.0
	rig.speed = FlightRig.CRUISE
	rig.hurt_t = 0.0
	var rings0 := rig.rings_passed
	var ring_pos := Vector3(rig.global_position.x, rig.alt - 2.0, rig.global_position.z) + fwd * 30.0
	rig.add_ring(ring_pos, 6.0)
	await _frames(150)
	_check(rig.rings_passed >= rings0 + 1, "flying through a ring scores (rings %d -> %d)" % [rings0, rig.rings_passed])

	# steering by leaning
	rig.heading = 0.0
	GazeProvider.peek_debug = Vector3(1.5, 0.0, 0.0)
	await _frames(90)
	_check(rig.heading < -0.1, "leaning right turns right (heading %.2f rad)" % rig.heading)
	GazeProvider.peek_debug = Vector3.ZERO
	rig.heading = 0.0

	# slam: snap the chin down from high up, crush a target below
	rig.alt = 40.0
	rig.slam_cd = 0.0
	rig.speed = 30.0
	fwd = Vector3(-sin(rig.heading), 0.0, -cos(rig.heading))
	var crushed0 := rig.targets_crushed
	var slams0 := rig.slams
	rig.add_target(rig.global_position + fwd * 16.0)
	GazeProvider.nod_debug = Vector2(-0.05, -3.0)
	await _frames(3)
	GazeProvider.nod_debug = Vector2.ZERO
	await _frames(100)
	_check(rig.slams == slams0 + 1 and rig.targets_crushed > crushed0, "a fast chin drop slams and crushes the target below (slams %d, crushed %d)" % [rig.slams, rig.targets_crushed])

	# leaving restores the normal game
	GazeProvider.nod_debug = Vector2.INF
	level.load_level(0)
	await _frames(6)
	_check(not Game.flight_mode and player.process_mode != Node.PROCESS_MODE_DISABLED and player.camera.current and level.hud.visible, "leaving flight restores the player, camera and HUD")


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	level.start_level = 0
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	_run(level)


func _run(level: MainLevel) -> void:
	await _frames(5)
	level.director.autostart = false
	level.director.abort_wave()
	var player: PlayerController = level.player
	var dir: WaveDirector = level.director

	# ---- every level builds + bakes
	for i in 5:
		level.load_level(i)
		await _frames(4)
		_check(level.geometry.get_child_count() > 8, "level %d '%s' built (%d solids, %d decor)" % [i, level.level_name, level.geometry.get_child_count(), level.decor.get_child_count()])
		_check(level.props_root.get_child_count() > 20, "level %d props spawned" % i)
		var e := dir.spawn_enemy(&"waddler")
		await _frames(60)
		_check(is_instance_valid(e) and e.global_position.y > -3.0, "level %d enemy stands on navmesh/ground (y=%.1f)" % [i, e.global_position.y])
		e.queue_free()
	level.load_level(3)
	_check(is_equal_approx(Game.gravity_scale, 0.4), "moon gravity is 0.4")
	level.load_level(0)
	await _frames(4)

	# ---- all characters spawn, think for a while without errors
	var kinds: Array = Roster.DEFS.keys()
	_check(kinds.size() >= 15, "roster has %d characters" % kinds.size())
	var spawned: Array[EnemyAI] = []
	player.global_position = Vector3(0, 0.1, 28)
	for k: StringName in kinds:
		spawned.append(dir.spawn_enemy(k, Vector3(randf_range(-10, 10), 0.3, randf_range(2, 12))))
	await _frames(240)
	var alive := 0
	for e in spawned:
		if is_instance_valid(e):
			alive += 1
	_check(alive >= 12, "characters survived 4s of AI (%d/%d alive; player hp %d)" % [alive, spawned.size(), int(player.health)])

	# ---- damage -> death -> XP + loot
	var xp0 := Prog.level * 10000 + Prog.xp
	var coins0 := Prog.coins
	for e in spawned:
		if is_instance_valid(e) and not e.dying:
			e.apply_hit(Vector3(0, 6, -10), e.global_position, &"kick", 9999.0)
	await _frames(120)
	_check(Prog.level * 10000 + Prog.xp > xp0, "kills awarded XP (lv %d, xp %d)" % [Prog.level, Prog.xp])
	var pickups := 0
	for c in level.enemies_root.get_children():
		if c is Pickup:
			pickups += 1
	_check(pickups > 0, "loot dropped (%d pickups)" % pickups)
	player.revive(Vector3(0, 0.05, 28))
	await _frames(180)
	_check(Prog.coins > coins0, "coins collected via magnet (%d -> %d)" % [coins0, Prog.coins])
	for c in level.enemies_root.get_children():
		c.queue_free()

	# ---- ragdoll swap on the humanoid and the blob rigs
	for k: StringName in [&"waddler", &"tank", &"bouncer", &"boss"]:
		var e := dir.spawn_enemy(k, Vector3(0, 0.3, 14))
		await _frames(10)
		e.apply_hit(Vector3(0, 4, -minf(float(Roster.get_def(k)["stagger"]) + 6.0, 80.0)), e.global_position, &"kick", 1.0)
		await _frames(3)
		var want_ragdoll := k != &"boss"
		if not is_instance_valid(e):
			_check(false, "%s vanished before ragdoll check" % k)
			continue
		_check((e.state == EnemyAI.State.RAGDOLL) == want_ragdoll, "%s ragdoll=%s" % [k, want_ragdoll])
		if want_ragdoll and is_instance_valid(e):
			await _frames(60 * 9)
			_check(is_instance_valid(e) and e.state == EnemyAI.State.CHASE and e.visual.get_parent() == e, "%s recovered (visual restored)" % k)
		if is_instance_valid(e):
			e.queue_free()
	await _frames(5)

	# ---- skills, levelling, gear, power-ups (clear stragglers so late kills can't grant XP mid-test)
	for n in get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await _frames(4)
	Prog.reset()
	Prog.skill_points = 3
	_check(Prog.buy("boots"), "bought Steel-Toed Boots")
	var kd := Prog.mult("kick_damage")
	_check(kd > 1.15, "kick damage multiplier applied (%.2f)" % kd)
	_check(Prog.can_buy("shockboots") != "", "capstone locked behind prerequisites")
	Prog.respec()
	_check(Prog.skill_points == 3 and Prog.mult("kick_damage") == 1.0, "respec refunds points")
	var lv_before := Prog.level
	Prog.add_xp(100000)
	_check(Prog.level > lv_before and Prog.skill_points > 3, "level-ups grant skill points (lv %d)" % Prog.level)
	var item := Loot.generate(4)
	_check(Prog.try_loot(item) and Prog.gear.has(item["slot"]), "gear equipped: " + String(item["name"]))
	Prog.grant_powerup("socks")
	_check(Prog.mult("gravity") < 0.5, "Anti-gravity socks active")
	Prog.powerups.clear()
	Prog.reset()

	# ---- player damage, death, shield, revive
	Prog.grant_powerup("shield")
	var hp0 := player.health
	player.take_damage(50.0, player.global_position)
	_check(player.health == hp0, "shield blocks damage")
	Prog.powerups.clear()
	player._invuln = 0.0
	player.take_damage(30.0, player.global_position)
	_check(player.health < hp0, "player takes damage (%d)" % int(player.health))
	player._invuln = 0.0
	player.take_damage(9999.0, player.global_position)
	_check(player.dead, "player dies")
	player.revive(level.spawn.global_position)
	_check(not player.dead and player.health > 0.0, "player revives")

	# ---- weapons (kick, blower rocket-jump, plunger)
	level.load_level(0)
	await _frames(5)
	player.revive(Vector3(0, 0.05, 28))
	var wm: WeaponManager = player.get_node("Head/Camera/WeaponManager")
	var blower: LeafBlower = wm.weapons[0]
	player.head.rotation.x = -1.5
	await _frames(5)
	blower.primary_pressed()
	var y0 := player.global_position.y
	await _frames(60)
	_check(player.global_position.y > y0 + 1.0, "leaf blower rocket-jump (%.2f -> %.2f)" % [y0, player.global_position.y])
	blower.primary_released()
	player.head.rotation.x = 0.0

	wm.select(1)
	var plunger: PlungerGrapple = wm.weapons[1]
	player.revive(Vector3(0, 0.05, 20))
	player.rotation = Vector3.ZERO
	player.head.rotation.x = -0.15
	await _frames(30)
	plunger.primary_pressed()
	await _frames(30)
	_check(plunger.mode == PlungerGrapple.Mode.HOOKED_BODY or plunger.mode == PlungerGrapple.Mode.HOOKED_WORLD, "plunger hooked (mode %d)" % plunger.mode)
	plunger.primary_pressed()
	await _frames(5)

	player.revive(Vector3(0, 0.05, 20))
	var foe := dir.spawn_enemy(&"waddler", player.global_position + Vector3(0, 0.1, -1.6))
	await _frames(3)
	var foe_hp := foe.health
	player._do_kick()
	await _frames(5)
	_check(foe.health < foe_hp or foe.dying, "kick damaged an enemy (%d -> %d)" % [int(foe_hp), int(foe.health)])

	await _gaze_tests(level, player, dir)
	await _weapon_tests(level, player, dir)
	await _peek_tests(level, player, dir)
	await _peek_eye_tests(level, player, dir)
	await _flight_tests(level, player)

	print("RESULT: " + ("FAILED" if _failed else "ALL PASSED"))
	get_tree().quit(1 if _failed else 0)
