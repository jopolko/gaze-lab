extends Node
## Windowed screenshots of the Peek Range: godot --path . res://tests/shots_peek.tscn -- <out dir>
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
	level.load_level(6)
	for k in 240:
		await get_tree().physics_frame      # let the station banner fade
	for lean in [0.0, 1.3, -1.3]:
		GazeProvider.peek_debug = Vector3(lean, 0.0, 0.0)
		for k in 70:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("%s/peek_%s.png" % [out, str(lean).replace(".", "_").replace("-", "m")])
	get_tree().quit()
