extends Node
## Windowed screenshot of the head monitor with a fake head pose: godot --path . res://tests/shots_cube.tscn -- <out dir>
func _ready() -> void:
	var out := "."
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.director.abort_wave()
	GazeProvider.set_process(false)
	GazeProvider.backend = GazeProvider.Backend.CAMERA
	GazeProvider.active = true
	GazeProvider.head_rpy_ok = true
	GazeProvider.confidence = 1.0
	var poses := [Vector3(0, 0, 0), Vector3(-0.45, 0.25, 0.15)]    # camera conventions: yaw<0 = you turn to YOUR right
	for i in poses.size():
		GazeProvider.head_rpy = poses[i]
		GazeProvider.gaze_ang = Vector2(poses[i].x * 1.3, poses[i].y * 1.3)
		for k in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/cube_%d.png" % [out, i])
	get_tree().quit()
