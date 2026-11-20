extends Node
## Dumps a generated level to JSON for the three.js port: every node's transform, every mesh's vertex data, every multimesh instance, the lights and the environment, and the rig's own row data (gates, buffs, pads...).
## Run headless:  OUT=C:/path/level.json SEED=7 THEME=psychedelic SEGS=14 Godot --headless --path godot res://tests/dump_level.tscn

var meshes: Dictionary = {}          # mesh id -> data
var mats: Dictionary = {}            # material id -> data
var nodes: Array = []
var seen: Dictionary = {}
var out_rows: Dictionary = {}
var out_anims: Array = []
var out_vx: Dictionary = {}
var out_kick: Dictionary = {}
var rig_ref: RunRig = null
var shots: Array = []
var level_ref: Node = null


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
		d["blend"] = int(s.blend_mode)
		d["billboard"] = int(s.billboard_mode)
		d["tex"] = s.albedo_texture != null
		d["nofog"] = s.disable_fog
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
	if n is CanvasItem:
		var ci: CanvasItem = n
		if ci.material != null:
			rec["cmat"] = dump_mat(ci.material)
		if n is Control:
			var ct: Control = n
			rec["rect"] = [r3(ct.position.x), r3(ct.position.y), r3(ct.size.x), r3(ct.size.y)]
	nodes.append(rec)
	for ch in n.get_children():
		walk(ch, path + "/" + str(ch.name), depth + 1)


# ---------------------------------------------------------------- PARITY SIDECAR: everything needed to reproduce one captured frame in three.js
func sh_params(sm: Variant) -> Dictionary:
	var d := {}
	if not (sm is ShaderMaterial):
		return d
	var m: ShaderMaterial = sm
	if m.shader == null:
		return d
	for u in m.shader.get_shader_uniform_list():
		var nm := String(u["name"])
		var v = m.get_shader_parameter(nm)
		if v == null:
			v = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), nm)
		d[nm] = js(v)
	return d


func sidecar(cam: Camera3D, rig: RunRig, idx: int) -> Dictionary:
	var side := {"i": idx}
	side["time"] = float(Time.get_ticks_usec()) / 1.0e6          # (the shader TIME is the engine's elapsed render time: close to this)
	side["ticks_msec"] = Time.get_ticks_msec()
	side["frames_drawn"] = Engine.get_frames_drawn()
	side["version"] = Engine.get_version_info()["string"]
	side["renderer"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	side["cam"] = {"xf": xf(cam.global_transform), "fov": r3(cam.fov), "near": cam.near, "far": cam.far, "h_offset": cam.h_offset, "v_offset": cam.v_offset, "keep_aspect": int(cam.keep_aspect)}
	var vp := get_viewport()
	side["viewport"] = {"w": vp.get_visible_rect().size.x, "h": vp.get_visible_rect().size.y, "msaa_3d": int(vp.msaa_3d), "scaling_3d": vp.scaling_3d_scale}
	side["rig"] = {"spos": v3a(rig.spos), "vel": js(rig.vel), "heading": rig.heading, "gspeed": rig._gspeed if "_gspeed" in rig else 0.0}
	var posts: Array = []
	for cn in get_tree().root.find_children("*", "ColorRect", true, false):
		if (cn as ColorRect).material is ShaderMaterial:
			posts.append({"path": str(cn.get_path()), "visible": (cn as ColorRect).visible, "params": sh_params((cn as ColorRect).material)})
	side["post"] = posts
	side["ground"] = sh_params(rig._m_ground) if "_m_ground" in rig else {}
	if "_veg_live" in rig and rig._veg_live != null:
		side["veg_live"] = sh_params(rig._veg_live)
	var env: Environment = level_ref.world_env.environment if level_ref != null else null
	if env != null:
		var e := {}
		for nm in ["background_mode", "background_color", "background_energy_multiplier", "ambient_light_source", "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution", "reflected_light_source", "tonemap_mode", "tonemap_exposure", "tonemap_white", "fog_enabled", "fog_mode", "fog_light_color", "fog_light_energy", "fog_sun_scatter", "fog_density", "fog_aerial_perspective", "fog_sky_affect", "fog_height", "fog_height_density", "fog_depth_begin", "fog_depth_end", "fog_depth_curve", "glow_enabled", "glow_intensity", "glow_strength", "glow_bloom", "glow_blend_mode", "glow_hdr_threshold", "glow_hdr_scale", "glow_hdr_luminance_cap", "glow_mix", "adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation", "ssao_enabled", "sdfgi_enabled"]:
			e[nm] = js(env.get(nm))
		for li in range(1, 8):
			e["glow_levels/%d" % li] = env.get("glow_levels/%d" % li)
		side["env"] = e
		if env.sky != null and env.sky.sky_material != null:
			var smat = env.sky.sky_material
			side["sky"] = {"class": smat.get_class(), "params": sh_params(smat) if smat is ShaderMaterial else {}}
	var lights: Array = []
	for ln in get_tree().root.find_children("*", "Light3D", true, false):
		var l := ln as Light3D
		var ld := {"class": l.get_class(), "path": str(l.get_path()), "xf": xf(l.global_transform), "color": col(l.light_color), "energy": l.light_energy, "shadow": l.shadow_enabled, "visible": l.is_visible_in_tree(), "indirect": l.light_indirect_energy}
		if l is DirectionalLight3D:
			ld["max_distance"] = (l as DirectionalLight3D).directional_shadow_max_distance
		lights.append(ld)
	side["lights"] = lights
	return side


func capture(level: Node) -> void:
	walk(level, "/MainLevel", 0)
	for kk in rig_ref._kickers:
		var kkey := str(snappedf(float(kk["z"]), 0.01))
		if out_vx.has(kkey):
			continue
		out_kick[kkey] = js(kk)
		var rings = kk.get("vx", null)
		if rings == null:
			continue
		var gi := 0
		var lst := []
		for rn in rings:
			if is_instance_valid(rn):
				var e := {"gi": gi, "iid": str((rn as Node).get_instance_id()), "Z": float((rn as Node3D).get_meta("Z", kk["z"]))}
				if (rn as Node3D).has_meta("R"):
					e["R"] = float((rn as Node3D).get_meta("R"))
				else:
					var sv: Vector3 = (rn as Node3D).get_meta("S", Vector3.ONE)
					e["S"] = [sv.x, sv.y, sv.z]
				lst.append(e)
			gi += 1
		out_vx[kkey] = {"x": kk["x"], "z": kk["z"], "len": kk["len"], "w": kk["w"], "trail": kk.get("trail", false), "super": kk.get("super", false), "rings": lst}
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
		for b in row.get("buffs", []):
			var an := {"t": str(b.get("t", "")), "ph": float(b.get("ph", 0.0)), "y": float(b.get("y", 0.0)), "moving": bool(b.get("moving", false))}
			for key in ["n", "spin", "halo"]:
				var o: Variant = b.get(key)
				if o is Node:
					an[key] = str((o as Node).get_instance_id())
			var exs := []
			for e in b.get("extra", []):
				if e is Node:
					exs.append(str((e as Node).get_instance_id()))
			an["extra"] = exs
			out_anims.append(an)


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
	rig.apply_menu({"journey": OS.get_environment("JOURNEY") != "", "seed": seed_v, "theme": theme, "mus": "off", "session": 10, "trip": 0 if OS.get_environment("JOURNEY") == "" else 1}, level)
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	rig_ref = rig
	level_ref = level
	var start := rig.spos
	capture(level)
	var guard := 0
	var stage := 0
	var shot_stage := 0
	while rig._next_j < segs and guard < 6000:
		guard += 1
		rig.spos.z -= 12.0
		rig.spos.y = rig.terrain_h(rig.spos.x, rig.spos.z)
		rig.grounded = true
		rig._gh_prev = rig.spos.y
		rig.vel = Vector2(0.0, -20.0)
		rig._physics_process(dt)
		rig._process(dt)
		if int(-rig.spos.z / 270.0) > stage:
			stage = int(-rig.spos.z / 270.0)
			await get_tree().process_frame
			capture(level)
		if OS.get_environment("SHOTS") != "" and int(-rig.spos.z / 450.0) > shot_stage and -rig.spos.z > 100.0:
			shot_stage = int(-rig.spos.z / 450.0)
			rig._process(dt)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var cam := get_viewport().get_camera_3d()
			var img := get_viewport().get_texture().get_image()
			var idx := shots.size()
			img.save_png(OS.get_environment("SHOTS") + "/godot_%02d.png" % idx)
			# the same frame again with the full-screen picture pass hidden: what the scene looks like before the pass (lighting, fog, tonemap, glow, colour grade only)
			var cr: Array = []
			for cn in get_tree().root.find_children("*", "ColorRect", true, false):
				if (cn as ColorRect).material is ShaderMaterial and (cn as ColorRect).visible:
					cr.append(cn)
					(cn as ColorRect).visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTS") + "/godot_%02d_nopost.png" % idx)
			for cn in cr:
				(cn as ColorRect).visible = true
			shots.append({"i": idx, "z": r3(rig.spos.z), "xf": xf(cam.global_transform), "fov": r3(cam.fov), "w": img.get_width(), "h": img.get_height()})
			var side := sidecar(cam, rig, idx)
			shots[idx]["side"] = side
			var sf := FileAccess.open(OS.get_environment("SHOTS") + "/godot_%02d.json" % idx, FileAccess.WRITE)
			sf.store_string(JSON.stringify(side))
			sf.close()
	await get_tree().process_frame
	capture(level)
	var out := {"seed": seed_v, "theme": theme, "segs": rig._next_j, "ROW_GAP": rig.ROW_GAP, "W_HALF": rig.W_HALF, "SLOPE": rig.SLOPE, "start": v3a(start)}
	out["nodes"] = nodes
	out["meshes"] = meshes
	out["materials"] = mats
	out["shots"] = shots
	out["rows"] = out_rows
	out["anims"] = out_anims
	var tx := []
	var zz := 0.0
	while zz > -2700.0:
		tx.append(snappedf(rig.trail_x(zz), 0.001))
		zz -= 6.0
	out["trailx"] = tx
	out["vx"] = out_vx.values()
	out["kickers"] = out_kick.values()
	out["feat_off"] = rig.FEAT_OFF
	var rows := out_rows
	out["pitch"] = js(rig._pitch)
	var f := FileAccess.open(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://level.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("DUMPED nodes=", nodes.size(), " meshes=", meshes.size(), " mats=", mats.size(), " rows=", rows.size(), " next_j=", rig._next_j)
	get_tree().quit()
