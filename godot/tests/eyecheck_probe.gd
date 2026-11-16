extends Node
## The eye check, run for real time with made-up eyes: once with eyes that follow the dot (it must say they are being read) and once with eyes that do not move
## (it must say they are not).


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
	rig.trail = true
	rig._restart()
	for pass_n in 2:
		GazeProvider.kit.reset()
		rig.dot_sim = true
		rig._sim_dead = pass_n == 1
		rig.eye_check_start()
		var z0 := rig.spos.z
		var t0 := Time.get_ticks_msec()
		while rig._dot_phase != 2 and Time.get_ticks_msec() - t0 < 45000:
			await get_tree().physics_frame
		print("EYECHECK %s: %s  moved %.1f m while it ran  took %.1f s" % ["still eyes" if pass_n == 1 else "eyes following the dot", rig._chk_head, absf(rig.spos.z - z0), float(Time.get_ticks_msec() - t0) / 1000.0])
		for ln in rig._chk_lines:
			print("EYECHECK    [%s] %s" % [["ok", "so-so", "BAD"][int(ln[1])], ln[0]])
		print("EYECHECK    log: ", rig.chk_res)
		rig._check_dismiss()
	get_tree().quit()
