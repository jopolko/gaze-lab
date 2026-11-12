extends Node
func _ready() -> void:
	Prog.save_enabled = false
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in [0, 5]:
		var t0 := Time.get_ticks_usec()
		for n: Node in [level.geometry, level.decor, level.props_root, level.enemies_root]:
			for c in n.get_children():
				n.remove_child(c)
				c.queue_free()
		var cfg := LevelBuilder.build(i, level)
		var t1 := Time.get_ticks_usec()
		level._bake_navigation()
		var t2 := Time.get_ticks_usec()
		level.player.revive(level.spawn.global_position)
		level._spawn_props()
		var t3 := Time.get_ticks_usec()
		print("LEVEL %d build=%dms bake=%dms props=%dms (props=%d decor=%d geom=%d)" % [i, (t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000, level.props_root.get_child_count(), level.decor.get_child_count(), level.geometry.get_child_count()])
		await get_tree().physics_frame
	get_tree().quit()
