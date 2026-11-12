extends Node
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(8)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for k in 90:
		await get_tree().physics_frame
	level.world_env.environment.ambient_light_energy = 0.15
	level.sun.light_energy = 2.0
	level.world_env.environment.fog_enabled = false
	var pillar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 14.0, 3.0)
	pillar.mesh = bm
	level._dh.add_child(pillar)
	pillar.global_position = level._dh.spos + Vector3(0.0, 5.0, -18.0)
	print("sun cull=%d layers=%d shadow_caster_mask? ground cast=%d" % [level.sun.light_cull_mask, pillar.layers, (level._dh._chunks.values()[0] as MeshInstance3D).cast_shadow])
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	plane.mesh = pm
	level._dh.add_child(plane)
	plane.global_position = level._dh.spos + Vector3(14.0, 6.5, -12.0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.9, 0.9)
	plane.material_override = pmat
	var pill2 := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(3.0, 8.0, 3.0)
	pill2.mesh = b2
	level._dh.add_child(pill2)
	pill2.global_position = level._dh.spos + Vector3(14.0, 11.0, -22.0)
	var variants := {
		"a_base": {},
		"b_near": {"cam_far": 300.0},
		"c_ortho": {"mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "bias": 0.02},
	}
	for nm in variants:
		var v: Dictionary = variants[nm]
		if v.has("cam_far"):
			level._dh.cam.far = float(v["cam_far"])
		if v.has("mode"):
			level.sun.directional_shadow_mode = int(v["mode"])
		if v.has("bias"):
			level.sun.shadow_bias = float(v["bias"])
		for k in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/shadow_%s.png" % [out, nm])
	get_tree().quit()
