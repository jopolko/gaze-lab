extends Node
## Dumps a generated level to JSON for the three.js port: every node's transform, every mesh's vertex data, every multimesh instance, the lights and the environment, and the rig's own row data (gates, buffs, pads...).
## Run headless:  OUT=C:/path/level.json SEED=7 THEME=psychedelic SEGS=14 Godot --headless --path godot res://tests/dump_level.tscn

var meshes: Dictionary = {}          # mesh id -> data
var mats: Dictionary = {}            # material id -> data
var nodes: Array = []
var seen: Dictionary = {}
var out_rows: Dictionary = {}
var rig_ref: RunRig = null


func r3(x: float) -> float:
	return snappedf(x, 0.001)


func v3a(v: Vector3) -> Array:
	return [r3(v.x), r3(v.y), r3(v.z)]


func xf(t: Transform3D) -> Array:
	var b := t.basis
	return [r3(b.x.x), r3(b.x.y), r3(b.x.z), r3(b.y.x), r3(b.y.y), r3(b.y.z), r3(b.z.x), r3(b.z.y), r3(b.z.z), r3(t.origin.x), r3(t.origin.y), r3(t.origin.z)]


func col(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]


## Any variant to something JSON can hold.
func js(v, depth: int = 0):
	if depth > 6:
		return null
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return v if typeof(v) != TYPE_STRING_NAME else String(v)
		TYPE_FLOAT:
			return r3(v) if is_finite(v) else 0.0
		TYPE_VECTOR2:
			return [r3(v.x), r3(v.y)]
		TYPE_VECTOR3:
			return v3a(v)
		TYPE_COLOR:
			return col(v)
		TYPE_TRANSFORM3D:
			return xf(v)
		TYPE_ARRAY:
			var a := []
			for e in v:
				a.append(js(e, depth + 1))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = js(v[k], depth + 1)
			return d
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var a2 := []
			for e2 in v:
				a2.append(r3(e2))
			return a2
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			var a3 := []
			for e3 in v:
				a3.append(int(e3))
			return a3
		TYPE_PACKED_VECTOR3_ARRAY:
			var a4 := []
			for e4 in v:
				a4.append(v3a(e4))
			return a4
		TYPE_PACKED_COLOR_ARRAY:
			var a5 := []
			for e5 in v:
				a5.append(col(e5))
			return a5
		TYPE_OBJECT:
			if v == null:
				return null
			if v is Node:
				return "<node " + str(v.name) + ">"
			return "<" + v.get_class() + ">"
		_:
			return str(v)


func dump_mat(m: Material) -> String:
	if m == null:
		return ""
	var id := str(m.get_instance_id())
	if mats.has(id):
		return id
	var d := {"class": m.get_class()}
	if m is ShaderMaterial:
		var sm: ShaderMaterial = m
		d["shader_hash"] = str(sm.shader.code.hash()) if sm.shader != null else ""
		d["shader_code"] = sm.shader.code if sm.shader != null else ""
		var params := {}
		if sm.shader != null:
			for u in sm.shader.get_shader_uniform_list():
				var nm := String(u["name"])
				params[nm] = js(sm.get_shader_parameter(nm))
		d["params"] = params
	elif m is StandardMaterial3D:
		var s: StandardMaterial3D = m
		d["albedo"] = col(s.albedo_color)
		d["metallic"] = r3(s.metallic)
		d["roughness"] = r3(s.roughness)
		d["emission_on"] = s.emission_enabled
		d["emission"] = col(s.emission)
		d["emission_energy"] = r3(s.emission_energy_multiplier)
		d["vertex_color_albedo"] = s.vertex_color_use_as_albedo
		d["shading_mode"] = int(s.shading_mode)
		d["transparency"] = int(s.transparency)
		d["cull_mode"] = int(s.cull_mode)
		d["unshaded"] = s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
	mats[id] = d
	return id


func dump_mesh(m: Mesh) -> String:
	if m == null:
		return ""
	var id := str(m.get_instance_id())
	if meshes.has(id):
		return id
	var d := {"class": m.get_class(), "surfaces": []}
	for s in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var sd := {"mat": dump_mat(m.surface_get_material(s)), "prim": int(m.surface_get_primitive_type(s)) if m.has_method("surface_get_primitive_type") else 3}
		var verts = arr[Mesh.ARRAY_VERTEX]
		sd["v"] = js(verts) if verts != null else []
		if arr[Mesh.ARRAY_NORMAL] != null:
			sd["n"] = js(arr[Mesh.ARRAY_NORMAL])
		if arr[Mesh.ARRAY_COLOR] != null:
			sd["c"] = js(arr[Mesh.ARRAY_COLOR])
		if arr[Mesh.ARRAY_TEX_UV] != null:
			var uvs := []
			for uv in arr[Mesh.ARRAY_TEX_UV]:
				uvs.append([r3(uv.x), r3(uv.y)])
			sd["uv"] = uvs
		if arr[Mesh.ARRAY_INDEX] != null:
			sd["i"] = js(arr[Mesh.ARRAY_INDEX])
		d["surfaces"].append(sd)
	if m is PrimitiveMesh:
		d["params"] = {}
		for p in m.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_EDITOR and typeof(m.get(p["name"])) in [TYPE_FLOAT, TYPE_INT, TYPE_VECTOR3, TYPE_BOOL]:
				d["params"][p["name"]] = js(m.get(p["name"]))
	meshes[id] = d
	return id


func walk(n: Node, path: String, depth: int) -> void:
	var iid := n.get_instance_id()
	if seen.has(iid):
		for ch0 in n.get_children():
			walk(ch0, path + "/" + str(ch0.name), depth + 1)
		return
	seen[iid] = true
	var rec := {"name": str(n.name), "class": n.get_class(), "path": path, "depth": depth, "iid": str(iid)}
	if n is Node3D:
		var n3: Node3D = n
		rec["xf"] = xf(n3.global_transform)
		rec["vis"] = n3.visible
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		rec["mesh"] = dump_mesh(mi.mesh)
		rec["mat_override"] = dump_mat(mi.material_override)
		rec["cast_shadow"] = int(mi.cast_shadow)
	elif n is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = n
		var mm: MultiMesh = mmi.multimesh
		if mm != null:
			rec["mesh"] = dump_mesh(mm.mesh)
			rec["mat_override"] = dump_mat(mmi.material_override)
			rec["count"] = mm.instance_count
			rec["use_colors"] = mm.use_colors
			var xs := []
			var cs := []
			for i in mm.instance_count:
				xs.append(xf(mm.get_instance_transform(i)))
				if mm.use_colors:
					cs.append(col(mm.get_instance_color(i)))
			rec["xfs"] = xs
			if mm.use_colors:
				rec["cols"] = cs
	elif n is DirectionalLight3D or n is OmniLight3D or n is SpotLight3D:
		var l: Light3D = n
		rec["light"] = {"color": col(l.light_color), "energy": r3(l.light_energy), "shadow": l.shadow_enabled, "indirect": r3(l.light_indirect_energy)}
		if n is DirectionalLight3D:
			var dl: DirectionalLight3D = n
			rec["light"]["max_distance"] = r3(dl.directional_shadow_max_distance)
		else:
			rec["light"]["range"] = r3(n.get("omni_range") if n is OmniLight3D else n.get("spot_range"))
	elif n is WorldEnvironment:
		var we: WorldEnvironment = n
		var e: Environment = we.environment
		if e != null:
			var ed := {}
			for p in e.get_property_list():
				if int(p["usage"]) & PROPERTY_USAGE_EDITOR:
					var val = e.get(p["name"])
					if typeof(val) != TYPE_OBJECT:
						ed[p["name"]] = js(val)
			rec["env"] = ed
			if e.sky != null and e.sky.sky_material != null:
				var sky_m: Material = e.sky.sky_material
				rec["sky_mat"] = dump_mat(sky_m)
	elif n is Camera3D:
		var c: Camera3D = n
		rec["cam"] = {"fov": r3(c.fov), "near": r3(c.near), "far": r3(c.far), "current": c.current}
	nodes.append(rec)
	for ch in n.get_children():
		walk(ch, path + "/" + str(ch.name), depth + 1)


func capture(level: Node) -> void:
	walk(level, "/MainLevel", 0)
	for k in rig_ref._rows:
		if out_rows.has(str(k)):
			continue
		var row: Dictionary = rig_ref._rows[k]
		var rd := {}
		for kk in row:
			var v = row[kk]
			if typeof(v) == TYPE_OBJECT:
				continue
			rd[str(kk)] = js(v)
		out_rows[str(k)] = rd


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
	var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	var theme := OS.get_environment("THEME") if OS.get_environment("THEME") != "" else "psychedelic"
	var segs := int(OS.get_environment("SEGS")) if OS.get_environment("SEGS") != "" else 12
	rig.apply_menu({"journey": true, "seed": seed_v, "theme": theme, "mus": "off", "session": 10, "trip": 1}, level)
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	rig_ref = rig
	var start := rig.spos
	capture(level)
	var guard := 0
	var stage := 0
	while rig._next_j < segs and guard < 6000:
		guard += 1
		rig.spos.z -= 12.0
		rig._physics_process(dt)
		rig._process(dt)
		if int(-rig.spos.z / 270.0) > stage:
			stage = int(-rig.spos.z / 270.0)
			await get_tree().process_frame
			capture(level)
	await get_tree().process_frame
	capture(level)
	var out := {"seed": seed_v, "theme": theme, "segs": rig._next_j, "ROW_GAP": rig.ROW_GAP, "W_HALF": rig.W_HALF, "SLOPE": rig.SLOPE, "start": v3a(start)}
	out["nodes"] = nodes
	out["meshes"] = meshes
	out["materials"] = mats
	out["rows"] = out_rows
	var rows := out_rows
	out["kickers"] = js(rig._kickers)
	out["pitch"] = js(rig._pitch)
	var f := FileAccess.open(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://level.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("DUMPED nodes=", nodes.size(), " meshes=", meshes.size(), " mats=", mats.size(), " rows=", rows.size(), " next_j=", rig._next_j)
	get_tree().quit()
