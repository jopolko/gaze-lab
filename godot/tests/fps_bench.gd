extends Node
## Dev bench: frames per second of a real window, per theme. THEME=candy godot --path . res://tests/fps_bench.tscn  (needs a GPU; headless gives nothing)
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
		await get_tree().process_frame
	var rig: RunRig = level._dh as RunRig
	for id in ["alpine", "candy", "psychedelic"]:
		ThemeFX.apply_to_level(level, rig, id, 0.8, true, true, false)
		rig.apply_params({})
		rig._restart()
		rig.autopilot = true
		for i in 120:
			await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		var n := 0
		while Time.get_ticks_msec() - t0 < 6000:
			await get_tree().process_frame
			n += 1
		print("%-12s %.1f fps (frames %d in 6 s)" % [id, float(n) / 6.0, n])
	get_tree().quit()
