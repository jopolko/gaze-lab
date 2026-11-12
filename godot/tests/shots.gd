extends Node
## Windowed screenshot tour: godot --path . res://tests/shots.tscn -- <output dir>
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
	var views := [
		[Vector3(0, 0.1, 28), 0.0, -0.05],
		[Vector3(0, 0.1, 28), 0.0, -0.05],
		[Vector3(0, 0.1, 30), 0.0, -0.05],
		[Vector3(0, 0.1, 30), 0.0, 0.0],
		[Vector3(0, 0.1, 6), 0.0, -0.15],
	]
	for i in 5:
		level.load_level(i)
		for k in 8:
			await get_tree().physics_frame
		for kind: StringName in [&"waddler", &"goose", &"bomber", &"banana", &"tomato", &"mama", &"balloon", &"boss"]:
			level.director.spawn_enemy(kind, level.random_spawn_point(8.0))
		level.player.revive(views[i][0])
		level.player.rotation.y = views[i][1]
		level.player.head.rotation.x = views[i][2]
		for k in 120:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("%s/level_%d.png" % [out, i])
		print("saved level ", i)
	Prog.skill_points = 4
	Prog.buy("boots")
	Prog.buy("hustle")
	Prog.try_loot(Loot.generate(3))
	Prog.try_loot(Loot.generate(4))
	level.get_node("UI/SkillTreeUI").open_menu()
	for k in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/skills.png" % out)
	get_tree().quit()
