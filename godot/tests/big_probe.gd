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
	var out: Array = []
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var sz := mi.mesh.get_aabb().size * mi.scale
			if maxf(sz.x, sz.z) > 250.0:
				out.append("%s | %s | size %.0f x %.0f x %.0f | at %.0f %.0f %.0f | mat %s | vis %s" % [mi.name, mi.mesh.get_class(), sz.x, sz.y, sz.z, mi.global_position.x, mi.global_position.y, mi.global_position.z, mi.material_override.get_class() if mi.material_override != null else "-", str(mi.visible)])
	for l in out:
		print("BIG: ", l)
	print("player at ", rig.spos)
	get_tree().quit()
