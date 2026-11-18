extends Node
## The linked set piece, measured: ride until a spring-tube-rail chain stands ahead, put the board down 40 m before the spring in its lane, eyes ahead, and watch it:
## does the spring take it, does the tube deliver it onto the rail, does the rail run to its end, what is the payoff and how fast does it come out. BEND=1 for the winding trail.


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
	rig.set_physics_process(false)
	rig.set_process(false)
	rig.trail = true
	rig.bend = OS.get_environment("BEND") != ""
	rig.apply_menu({"journey": true, "seed": int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7, "theme": "alpine", "mus": "off", "session": 10, "trip": 1}, level)
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for i in 600:
		rig._physics_process(dt)
		rig._process(dt)
	var groups := {}
	var stack: Array = [rig]
	var tot_nodes := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var tris := 0
		var inst := 1
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				mesh = mm.mesh
				inst = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(si)
			if a.size() > Mesh.ARRAY_INDEX and a[Mesh.ARRAY_INDEX] != null and (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
				tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif a[Mesh.ARRAY_VERTEX] != null:
				tris += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var gi := n as GeometryInstance3D
		var key := "%s %s tri/inst %d vr_end %d dz %d" % [n.get_class(), String(n.get_parent().name).left(18), tris, int(gi.visibility_range_end), int(absf((n as Node3D).global_position.z - rig.spos.z)) / 100 * 100]
		var g: Array = groups.get(key, [0, 0, 0])
		g[0] += 1
		g[1] += tris * inst
		g[2] += inst
		groups[key] = g
	var arr: Array = []
	for k in groups:
		arr.append([groups[k][1], k, groups[k][0], groups[k][2]])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for e in arr.slice(0, 40):
		print("DRAW tris %d | %s | nodes %d | instances %d" % [e[0], e[1], e[2], e[3]])
	print("draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	get_tree().quit()
