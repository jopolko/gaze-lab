extends Node
## Start-screen screenshots: godot --path . --resolution 540x1170 res://tests/shots_intro.tscn -- <out dir> <name> --demo
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "."
	var nm := args[1] if args.size() > 1 else "intro"
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	for i in 6:
		await get_tree().process_frame
	Game.level_requested.emit(8)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, nm])
	get_tree().quit()
