extends Node
## Hands off from a standstill: does the board or the view lean to one side in the first seconds of a run?


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
	for run in 6:
		rig._restart()
		var line := "LEAN run %d:" % run
		for i in 300:
			await get_tree().physics_frame
			if i % 50 == 49:
				line += "  z%4d off %+5.1f head %+5.1f steer %+.2f bend60 %+5.1f |" % [int(-rig.spos.z), rig.spos.x - rig.trail_x(rig.spos.z), rad_to_deg(rig.heading), rig.steer, rig.trail_x(rig.spos.z - 60.0) - rig.trail_x(rig.spos.z)]
		print(line)
	get_tree().quit()
