extends Node
## The forest trail: with the eyes resting on the middle, does the board ride the trail, pass the poles on the right side and stay out of the trees?


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
	for run in 3:
		rig.trail = true
		rig.bend = OS.get_environment("BEND") != ""
		rig._restart()
		var dt := 1.0 / 60.0
		var off_max := 0.0
		var off_sum := 0.0
		var n := 0
		var air := 0.0
		var high := 0.0
		var vmax := 0.0
		for i in 60 * 90:
			GazeProvider.set_scripted(Vector2(0.5, 0.45))
			rig._physics_process(dt)
			rig._process(dt)
			if -rig.spos.z > 200.0 and not rig._finished:
				var off := absf(rig.spos.x - rig.trail_x(rig.spos.z))
				off_max = maxf(off_max, off)
				off_sum += off
				n += 1
				if not rig.grounded:
					air += dt
					high = maxf(high, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
				vmax = maxf(vmax, rig.vel.length())
		print("TRAIL run %d: %d m in 90 s, crashes %d, poles %d (clean %d, shaved %d, wrong side %d), off the middle %.1f m on average and %.1f m at worst, %.1f s in the air (highest %.1f m), top speed %d km/h, best flow x%.1f, score %d" % [run, int(-rig.spos.z), rig.crashes, rig.poles_clean + rig.poles_wrong, rig.poles_clean, rig.poles_shaved, rig.poles_wrong, off_sum / maxf(float(n), 1.0), off_max, air, high, int(vmax * 3.6), rig.best_flow, rig.score])
		if rig.crashes > 0:
			print("TRAIL   crash log: ", rig.crash_log)
	get_tree().quit()
