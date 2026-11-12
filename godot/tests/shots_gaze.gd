extends Node
## Windowed hands-free screenshot: godot --path . res://tests/shots_gaze.tscn -- <output dir>
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
	level.load_level(1)
	for k in 8:
		await get_tree().physics_frame
	level.player.revive(Vector3(0, 0.1, 28))
	level.player.rotation = Vector3.ZERO
	level.player.head.rotation.x = -0.05
	var foes: Array[EnemyAI] = []
	for kind: StringName in [&"waddler", &"goose", &"tank"]:
		foes.append(level.director.spawn_enemy(kind, Vector3(randf_range(-5, 5), 0.2, 14.0 + randf_range(0, 4))))
	level.gaze.pan_enabled = false
	GazeProvider.set_scripted(Vector2(0.5, 0.5))
	GazeProvider.set_active(true)
	for k in 20:
		await get_tree().physics_frame
	var vp := get_viewport().get_visible_rect().size
	# lock the first two, half-fill the third
	for i in 2:
		for k in 30:
			GazeProvider.set_scripted(level.player.camera.unproject_position(foes[i].global_position + Vector3.UP) / vp)
			await get_tree().physics_frame
	for k in 14:
		GazeProvider.set_scripted(level.player.camera.unproject_position(foes[2].global_position + Vector3.UP) / vp)
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/gaze_lock.png" % out)
	print("saved; tags=", level.gaze.tags.size(), " bullet=", level.gaze.bullet_time)
	Engine.time_scale = 1.0
	get_tree().quit()
