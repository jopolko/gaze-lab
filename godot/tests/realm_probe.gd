extends Node
## Dev probe: force each realm, generate a stretch of it and drive it with the autopilot.  godot --headless --path . res://tests/realm_probe.tscn
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = true
	level.load_level(11)
	await _frames(5)
	var rig: RunRig = level._dh as RunRig
	rig.view_fp = false
	rig.set_physics_process(false)
	var dt := 1.0 / 60.0
	for id in Realms.IDS:
		var zw := {}
		for k in RunRig.ZONES:
			zw[k] = 0.0
		zw[id] = 1.0
		rig.apply_params({"zones": zw, "lazy": true})
		rig._restart()
		rig.balls_enabled = false
		rig.autopilot = true
		rig._boost_t = 0.0
		var peak_h := 0.0
		var steps := 0
		while steps < 3600 and rig.spos.z > -900.0:
			rig._physics_process(dt)
			steps += 1
		var rc := 0
		var tc := 0
		for j in rig._chunks:
			tc += 1
			if (rig._chunks[j] as MeshInstance3D).material_override == Realms.ground_material():
				rc += 1
		print("  chunks %d, with realm ground %d" % [tc, rc])
		var inz := 0
		for j in rig._zone_by_j:
			if rig._zone_by_j[j] == id:
				inz += 1
		print("REALM %-10s: segments in realm %d, reached z %.0f in %d steps, crashes %d, nodes %d" % [id, inz, rig.spos.z, steps, rig.crashes, rig.get_child_count()])
	get_tree().quit()
