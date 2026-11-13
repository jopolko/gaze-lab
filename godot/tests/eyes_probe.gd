extends Node
## Dev probe: the real eyes-only path (iris-in-eye), not the screen-gaze stand-in the other tests use. Does a look aside steer?
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
	Game.touch_mode = true
	level.load_level(11)
	await _frames(5)
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.balls_enabled = false
	rig.avoid_enabled = false
	var dt := 1.0 / 60.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for variant in ["current", "no help", "no help, no recentre"]:
		rig._restart()
		rig.vel = Vector2(0.0, -16.0)
		rig.eyes_only = true
		GazeProvider.eih_ok = true
		GazeProvider.direct_ok = true
		GazeProvider.direct = Vector2(0.5, 0.5)
		GazeProvider.backend = GazeProvider.Backend.CAMERA
		GazeProvider.active = true
		rig.assist_level = 0.7 if variant == "current" else 0.0
		var t := 0.0
		var look := 0.0
		var phase := 0
		var x_at_look := 0.0
		var max_steer := 0.0
		for i in 1800:
			t += dt
			# 0-12 s: glance left and right now and then (this is what teaches it your glance size), 12-16 s: hold a look to one side
			if t < 12.0:
				look = 0.03 * sin(t * 1.1)
			elif t < 16.0:
				if phase == 0:
					phase = 1
					x_at_look = rig.spos.x
				look = 0.03
			else:
				look = 0.0
			if variant == "no help, no recentre":
				rig._ex_slow.clear()
			GazeProvider._last_packet_msec = Time.get_ticks_msec()
			GazeProvider.confidence = 1.0
			GazeProvider.eih = Vector2(-look + rng.randfn(0.0, 0.004), 0.5)
			rig._update_focus(dt)
			rig._physics_process(dt)
			rig.spos.x = clampf(rig.spos.x, -30.0, 30.0)
			if t > 12.0 and t < 16.0:
				max_steer = maxf(max_steer, absf(rig._steer_gaze))
		print("%-22s  glance %.4f  ref %.4f  engage %.2f  steer_gaze max %.2f  moved %.1f m in the 4 s look" % [variant, rig._ex_full, rig._ex_ref, rig._engage, max_steer, rig.spos.x - x_at_look])
	get_tree().quit()
