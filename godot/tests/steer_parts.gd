extends Node
## Which part of the steering makes the board swing while the eyes rest on the middle?


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = false
	level.load_level(11)
	for i in 5:
		await get_tree().physics_frame
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.set_process(false)
	rig._restart()
	rig._warmed = true
	rig._warming = false
	rig.ghost = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dt := 1.0 / 60.0
	var g := 0.5
	var out: Array = []
	for i in 60 * 45:
		if i % 3 == 0:
			g = clampf(0.5 + rng.randfn(0.0, 0.03), 0.0, 1.0)
		GazeProvider.set_scripted(Vector2(g, 0.45))
		rig._physics_process(dt)
		if i > 300 and i % 4 == 0 and absf(rig.heading) > 0.3:
			out.append("%5.1f st %+.2f eye %+.2f sg %+.2f swv %+.2f wallw %.2f aimw %.2f int %+.2f hd %+3.0f x %+5.1f vx %+5.1f aim %s parts %s gnd %s z %d" % [float(i) * dt, rig.steer, rig._eye_lp, rig._steer_gaze, rig._swerve_s, rig._wall_w, rig._aim_w, rig._intent_dir * rig._intent_amt, rad_to_deg(rig.heading), rig.spos.x, rig.vel.x, "y" if not rig._aim.is_empty() else "-", str(rig._dbg_parts.snapped(Vector3.ONE * 0.01)), str(rig.grounded), int(rig.spos.z)])
	for l in out.slice(0, 70):
		print("PART ", l)
	get_tree().quit()
