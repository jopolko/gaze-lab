class_name ThemeBackdrop
extends Control
## A small live 3D world behind the menu: a snowy (or neon, or digital) slope with trees, rocks and a few gates, seen from a camera that slowly drifts around it.
## It lives in its own SubViewport with its own World3D, so it never touches the game, and it is thrown away when the run starts.

var vp: SubViewport
var shown: TextureRect
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var terrain: MeshInstance3D
var trees: MultiMeshInstance3D
var rocks: MultiMeshInstance3D
var gates: Node3D
var pyramids: MeshInstance3D
var post: ThemeFX.ThemePost
var theme_id: String = "alpine"
var intensity: float = 1.0
var _t: float = 0.0
var _rs: float = 0.75                         # render scale: the backdrop does not need to be sharp, and phones will thank us
var _tree_mesh: ArrayMesh
var _rock_mesh: ArrayMesh
var _sky: Sky

const HALF_X := 130.0
const Z0 := 60.0
const Z1 := -240.0


static func hill(x: float, z: float) -> float:
	return z * 0.30 + 5.0 * sin(x * 0.045 + z * 0.021) + 2.6 * sin(x * 0.11 - z * 0.063) + 1.2 * sin(x * 0.23 + z * 0.17)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = _want_size()
	add_child(vp)
	_build_world()
	shown = TextureRect.new()
	shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shown)
	post = ThemeFX.ThemePost.new()
	post.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(post)
	post.setup_backdrop(vp, shown)
	choose_theme(theme_id)


func _want_size() -> Vector2i:
	var s := get_viewport_rect().size
	return Vector2i(maxi(int(s.x * _rs * 0.5), 160), maxi(int(s.y * _rs * 0.5), 160))   # the canvas is in 1280-wide units; half of that is plenty for a soft backdrop


func choose_theme(id: String) -> void:
	theme_id = id
	var d := Themes.theme_data(id)
	var e: Dictionary = d["env"]
	# environment
	var sky_top: Color = e.get("sky_top", Color(0.33, 0.58, 0.95))
	var sky_hor: Color = e.get("sky_horizon", Color(0.9, 0.95, 1.0))
	var sky_gnd: Color = e.get("sky_ground", Color(0.55, 0.7, 0.8))
	var sm := Themes.sky_material(id)
	if sm != null:
		_sky.sky_material = sm
	else:
		var ps := ProceduralSkyMaterial.new()
		ps.sky_top_color = sky_top
		ps.sky_horizon_color = sky_hor
		ps.ground_horizon_color = sky_hor
		ps.ground_bottom_color = sky_gnd
		_sky.sky_material = ps
	env.ambient_light_energy = float(e.get("ambient", 0.55))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = e.get("fog", Color(0.82, 0.9, 1.0))
	env.fog_density = float(e.get("fog_density", 0.0022))
	env.fog_sky_affect = float(e.get("fog_sky", 0.35))
	env.tonemap_exposure = 0.85 if id == "alpine" else 1.0
	env.glow_enabled = true
	env.glow_intensity = minf(float(e.get("glow", 0.5)), 0.6)
	env.glow_hdr_threshold = 1.3
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = float(e.get("saturation", 1.1))
	env.adjustment_contrast = float(e.get("contrast", 1.05))
	sun.light_color = e.get("sun_color", Color(1.0, 0.95, 0.85))
	sun.light_energy = float(e.get("sun_energy", 0.9))
	sun.rotation_degrees = e.get("sun_rot", Vector3(-38.0, -35.0, 0.0))
	# materials
	var gm := Themes.ground_material(id)
	if gm == null:
		var sm3 := StandardMaterial3D.new()
		sm3.vertex_color_use_as_albedo = true
		sm3.roughness = 1.0
		sm3.metallic_specular = 0.0
		gm = null
		terrain.material_override = sm3
	else:
		terrain.material_override = gm
	var vm := Themes.veg_material(id)
	if vm == null:
		var vm3 := StandardMaterial3D.new()
		vm3.vertex_color_use_as_albedo = true
		vm3.roughness = 1.0
		vm3.cull_mode = BaseMaterial3D.CULL_DISABLED
		vm3.metallic_specular = 0.0
		trees.material_override = vm3
		rocks.material_override = vm3
	else:
		trees.material_override = vm
		rocks.material_override = vm
	pyramids.visible = id == "egypt"
	var sweet := id == "candy"
	trees.multimesh.mesh = Themes.fluffy_tree_mesh(id) if sweet else _tree_mesh
	rocks.multimesh.mesh = Themes.gumdrop_mesh() if sweet else _rock_mesh
	_recolor_gates(d["c1"], d["c2"])
	post.set_look(Themes.post_mode(id), intensity)


func set_intensity(v: float) -> void:
	intensity = v
	post.set_look(Themes.post_mode(theme_id), v)


func _process(delta: float) -> void:
	_t += delta
	var ws := _want_size()
	if ws != vp.size:
		vp.size = ws
	# a slow drift: a long arc across the slope, looking down the hill, with a gentle bob
	var a := _t * 0.045
	var cx := sin(a) * 70.0
	var cz := -70.0 + cos(a * 0.7) * 40.0
	var cy := hill(cx, cz) + 20.0 + sin(_t * 0.31) * 2.5
	cam.position = Vector3(cx, cy, cz)
	var tgt := Vector3(cx * 0.35 + sin(a * 1.3) * 18.0, hill(cx * 0.3, cz - 90.0) + 4.0, cz - 90.0)
	cam.look_at(tgt, Vector3.UP)
	cam.fov = 68.0 + (4.0 * sin(_t * 0.4) if theme_id == "psychedelic" else 0.0)


# ------------------------------------------------------------------ the world
func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	_sky = Sky.new()
	_sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = _sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.far = 900.0
	cam.current = true
	vp.add_child(cam)
	terrain = MeshInstance3D.new()
	terrain.mesh = _terrain_mesh()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(terrain)
	_tree_mesh = _make_tree()
	_rock_mesh = _make_rock()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	trees = _scatter(_tree_mesh, 220, rng, 0.8, 1.7)
	rocks = _scatter(_rock_mesh, 46, rng, 0.9, 2.4)
	vp.add_child(trees)
	vp.add_child(rocks)
	pyramids = MeshInstance3D.new()
	pyramids.mesh = Themes.pyramid_mesh()
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.roughness = 1.0
	pyramids.material_override = pm
	pyramids.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pyramids.position = Vector3(0, hill(0.0, -60.0) - 6.0, -60.0)
	vp.add_child(pyramids)
	gates = Node3D.new()
	vp.add_child(gates)
	for i in 7:
		var gz := -20.0 - float(i) * 34.0
		var gx := sin(float(i) * 1.3) * 26.0
		for sx in [-1.0, 1.0]:
			var post_mesh := CylinderMesh.new()
			post_mesh.top_radius = 0.35
			post_mesh.bottom_radius = 0.45
			post_mesh.height = 11.0
			post_mesh.radial_segments = 6
			var mi := MeshInstance3D.new()
			mi.mesh = post_mesh
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var px: float = gx + float(sx) * 8.0
			mi.position = Vector3(px, hill(px, gz) + 5.5, gz)
			gates.add_child(mi)
		var beam := CylinderMesh.new()
		beam.top_radius = 0.4
		beam.bottom_radius = 0.9
		beam.height = 60.0
		var bm := MeshInstance3D.new()
		bm.mesh = beam
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.material_override = bmat
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.position = Vector3(gx, hill(gx, gz) + 30.0, gz)
		gates.add_child(bm)


func _recolor_gates(c1: Color, c2: Color) -> void:
	var i := 0
	for n in gates.get_children():
		var mi := n as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		var c := c1 if (i / 3) % 2 == 0 else c2
		if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).height > 30.0:
			m.albedo_color = Color(c.r, c.g, c.b, 0.22)
		else:
			m.albedo_color = c
		i += 1


func _terrain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 56
	var nz := 90
	var verts: Array = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := lerpf(-HALF_X, HALF_X, float(ix) / float(nx))
			var z := lerpf(Z0, Z1, float(iz) / float(nz))
			verts.append(Vector3(x, hill(x, z), z))
	var snow := Color(0.78, 0.85, 0.95)
	for iz in nz:
		for ix in nx:
			var a: Vector3 = verts[iz * (nx + 1) + ix]
			var b: Vector3 = verts[iz * (nx + 1) + ix + 1]
			var c: Vector3 = verts[(iz + 1) * (nx + 1) + ix]
			var d: Vector3 = verts[(iz + 1) * (nx + 1) + ix + 1]
			for tri in [[a, c, b], [b, c, d]]:
				for v in tri:
					st.set_color(snow)
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _make_tree() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.10, 0.30, 0.22)
	var snow := Color(0.88, 0.93, 0.97)
	var white := Color(0.98, 0.99, 1.0)
	for tier in [[1.95, 1.1, 2.8], [1.55, 2.6, 2.5], [1.1, 4.0, 2.3]]:
		var r: float = tier[0]
		var y0: float = tier[1]
		var h: float = tier[2]
		var apex := Vector3(0.0, y0 + h, 0.0)
		var n := 7
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			var b0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
			var b1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
			var m0 := Vector3(cos(a0) * r * 0.5, y0 + h * 0.5, sin(a0) * r * 0.5)
			var m1 := Vector3(cos(a1) * r * 0.5, y0 + h * 0.5, sin(a1) * r * 0.5)
			for tri in [[b0, green, b1, green, m1, snow], [b0, green, m1, snow, m0, snow], [m0, snow, m1, snow, apex, white]]:
				for k in 3:
					st.set_color(tri[k * 2 + 1])
					st.add_vertex(tri[k * 2])
	st.generate_normals()
	return st.commit()


func _make_rock() -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 1.5
	sph.radial_segments = 7
	sph.rings = 4
	var arr := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + 0.18 * sin(v.x * 5.0 + v.z * 3.0))
		cols.append(Color(0.55, 0.58, 0.64))
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _scatter(mesh: Mesh, count: int, rng: RandomNumberGenerator, smin: float, smax: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var x := rng.randf_range(-HALF_X + 6.0, HALF_X - 6.0)
		var z := rng.randf_range(Z1 + 10.0, Z0 - 10.0)
		var path_x := sin((-z - 20.0) / 34.0 * 1.3) * 26.0          # leave the gate line clear
		if absf(x - path_x) < 14.0 and z < -10.0:
			x += signf(x - path_x + 0.01) * 16.0
		var s := rng.randf_range(smin, smax)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, hill(x, z) - 0.15, z)))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
