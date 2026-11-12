extends Node
func _ready() -> void:
	Prog.save_enabled = false
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(6)
	for i in 8:
		await get_tree().physics_frame
	var space := level.get_world_3d().direct_space_state
	for st in LevelBuilder.PEEK_STATIONS.size():
		for spec: Array in LevelBuilder.peek_baddies(st, 2):
			var pos: Vector3 = spec[1]
			var eye := Vector3(0.0, 1.7, LevelBuilder.PEEK_STATIONS[st])
			var best := 99.0
			for k in range(0, 61):
				for sgn in [-1.0, 1.0]:
					var e2 := eye + Vector3(sgn * float(k) * 0.1, 0.0, 0.0)
					var ok := false
					for h in [0.7, 1.4]:
						var q := PhysicsRayQueryParameters3D.create(e2, pos + Vector3.UP * h, Game.MASK_WORLD)
						if space.intersect_ray(q).is_empty():
							ok = true
					if ok and absf(sgn * k * 0.1) < best:
						best = absf(sgn * k * 0.1)
			print("DBG st=%d kind=%s pos=(%.1f,%.1f) minlean=%.1f" % [st, spec[0], pos.x, pos.z, best])
	get_tree().quit()
