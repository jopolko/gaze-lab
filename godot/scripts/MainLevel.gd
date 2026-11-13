class_name MainLevel
extends Node3D
## Level framework: owns the director, builds one of five themed levels
## (LevelBuilder), applies its lighting/environment, bakes navigation, scatters
## props, and exposes the primitive helpers the builders use.

const LEVEL_COUNT := 12

@export var start_level: int = 0
@export var prop_count: int = 40

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var geometry: Node3D = $NavigationRegion3D/Geometry
@onready var decor: Node3D = $Decor
@onready var props_root: Node3D = $Props
@onready var enemies_root: Node3D = $Enemies
@onready var player: PlayerController = $Player
@onready var spawn: Marker3D = $PlayerSpawn
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: Hud = $UI/Hud

var level_index: int = 0
var level_name: String = ""
var arena_half: float = 34.0
var director: WaveDirector
var _rig: FlightRig
var _dh: DownhillRig
var _tr: TranceRig
var _gt: GazeTestRig
var peek_station: int = 0
var _peek_round: int = 0
var _peek_moving: bool = false
var _peek_clear_t: float = 0.0
var _was_peek: bool = false
var _autostart_saved: bool = true
var gaze: GazeTargeting
var keepouts: Array[Rect2] = []
var spawn_points: Array[Vector3] = []
var prop_kinds: Array[StringName] = [&"crate", &"barrel", &"ball", &"duck"]

var disco_tiles: Array[MeshInstance3D] = []
var _flicker: Array[Array] = []   # [light, base_energy, phase]
var _spinners: Array[Node3D] = []
var _checker_mat: StandardMaterial3D
var _disco_t: float = 0.0
var _loading: bool = false


func _ready() -> void:
	randomize()
	if Game.demo_mode:
		start_level = 11       # the bare address opens Downhill, whose menu reaches every other level; ?level=peek|eyes|flight|lanes|trance|gaze still deep-link
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=eyes"):
			start_level = 5
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=peek"):
			start_level = 6
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=flight"):
			start_level = 7
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=lanes"):
			start_level = 8
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=downhill"):
			start_level = 11
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=trance"):
			start_level = 9
		if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("level=gaze"):
			start_level = 10
		prop_count = 8
		Game.peek_mode = start_level == 6
		Game.flight_mode = start_level == 7 or start_level == 8 or start_level == 11
		Game.downhill_mode = start_level == 8 or start_level == 11
		Game.run_mode = start_level == 11
		Game.trance_mode = start_level == 9
		Game.gaze_test_mode = start_level == 10
		Game.level_requested.connect(load_level)      # the intro's mode picker
	_make_checker_material()
	director = WaveDirector.new()
	director.name = "WaveDirector"
	add_child(director)
	if Game.demo_mode:
		director.max_alive = 5
		director.first_delay = 6.0
	gaze = GazeTargeting.new()
	gaze.name = "GazeTargeting"
	add_child(gaze)
	$UI.add_child(TouchControls.new())
	if Game.demo_mode:
		if start_level == 11:
			$UI.add_child(DownhillMenu.new())
		else:
			$UI.add_child(EyeDemoIntro.new())
		Game.dh_started.connect(func(c: Dictionary) -> void:
			if _dh is RunRig:
				(_dh as RunRig).apply_menu(c, self))
	player.died.connect(_on_player_died)
	load_level(start_level)


func _unhandled_input(event: InputEvent) -> void:
	if Game.demo_mode:
		return
	if event.is_action_pressed(&"level_next"):
		load_level(level_index + 1)
	elif event.is_action_pressed(&"level_prev"):
		load_level(level_index - 1)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in _flicker:
		var l: OmniLight3D = f[0]
		if is_instance_valid(l):
			l.light_energy = float(f[1]) * (0.65 + 0.35 * sin(t * 17.0 + float(f[2])) * sin(t * 5.3 + float(f[2])))
	for s in _spinners:
		if is_instance_valid(s):
			s.rotate_y(delta * 0.9)
	_disco_t -= delta
	if _disco_t <= 0.0 and not disco_tiles.is_empty():
		_disco_t = 0.4
		for i in disco_tiles.size():
			var m := disco_tiles[i].material_override as StandardMaterial3D
			var c := Color.from_hsv(fmod(float(i) * 0.07 + t * 0.35, 1.0), 0.85, 1.0)
			m.albedo_color = c
			m.emission = c
			m.emission_energy_multiplier = 0.7


func _physics_process(delta: float) -> void:
	if Game.peek_mode and not _peek_moving and not _loading:
		var alive := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e.get_parent() == enemies_root:
				alive += 1
		_peek_clear_t = _peek_clear_t + delta if alive == 0 else 0.0
		if _peek_clear_t > 1.2:
			_peek_advance()
	if player.global_position.y < -40.0 or (level_index == 4 and player.global_position.y < -7.5):
		player.global_position = spawn.global_position
		player.velocity = Vector3.ZERO


# --------------------------------------------------------------------------
# Level lifecycle
# --------------------------------------------------------------------------
func load_level(idx: int) -> void:
	_loading = true
	level_index = wrapi(idx, 0, LEVEL_COUNT)
	_stop_flight()
	for n: Node in [geometry, decor, props_root, enemies_root]:
		for c in n.get_children():
			n.remove_child(c)
			c.queue_free()
	_flicker.clear()
	_spinners.clear()
	disco_tiles.clear()
	keepouts.clear()
	spawn_points.clear()
	director.abort_wave()
	Game.boss_changed.emit("", 0.0, 1.0)

	var cfg := LevelBuilder.build(level_index, self)
	level_name = String(cfg["name"])
	arena_half = float(cfg["half"])
	spawn.position = cfg["spawn"]
	Game.gravity_scale = float(cfg.get("gravity", 1.0))
	if cfg.has("prop_kinds"):
		prop_kinds = cfg["prop_kinds"]
	_apply_environment(cfg)
	if level_index != 7 and level_index != 8 and level_index != 9 and level_index != 10 and level_index != 11:
		_bake_navigation()
	player.revive(spawn.global_position)
	_spawn_props()
	hud.set_level_name(level_name)
	Game.banner(level_name.to_upper(), Color(1.0, 0.9, 0.5), 2.6)
	Game.peek_mode = level_index == 6
	Game.flight_mode = level_index == 7 or level_index == 8 or level_index == 11
	Game.downhill_mode = level_index == 8 or level_index == 11
	Game.run_mode = level_index == 11
	Game.trance_mode = level_index == 9
	Game.gaze_test_mode = level_index == 10
	player.rail_lock = Game.peek_mode
	var quiet := Game.peek_mode or Game.flight_mode or Game.trance_mode or Game.gaze_test_mode
	if quiet:
		if not _was_peek:
			_autostart_saved = director.autostart
		director.autostart = false                 # no wandering chasers: the baddies are hiding / you are flying
	elif _was_peek:
		director.autostart = _autostart_saved
	_was_peek = quiet
	if Game.peek_mode:
		_peek_round = 0
		_peek_begin_station(0)
	if Game.flight_mode:
		_start_flight()
	if Game.trance_mode:
		_start_trance()
	if Game.gaze_test_mode:
		_start_gaze_test()
	_loading = false


func advance_level() -> void:
	Game.banner("NEXT STOP...", Color(0.7, 0.9, 1.0), 2.0)
	await get_tree().create_timer(2.5).timeout
	load_level(level_index + 1)


func _on_player_died() -> void:
	Game.banner("EMBARRASSED!", Color(1.0, 0.35, 0.35), 2.6)
	Prog.coins = int(Prog.coins * 0.75)
	await get_tree().create_timer(2.6).timeout
	player.revive(spawn.global_position)
	if Game.peek_mode:
		player.global_position = Vector3(player.rail_anchor.x, 0.1, player.rail_anchor.z)


func _apply_environment(cfg: Dictionary) -> void:
	var env := world_env.environment
	if env.sky.has_meta("orig_sky"):
		env.sky.sky_material = env.sky.get_meta("orig_sky")            # a theme may have put its own sky in: back to the plain one before the level sets its colours
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = cfg["sky_top"]
	sky.sky_horizon_color = cfg["sky_horizon"]
	sky.ground_horizon_color = cfg["sky_horizon"]
	sky.ground_bottom_color = cfg["sky_ground"]
	env.ambient_light_energy = float(cfg["ambient"])
	env.fog_enabled = float(cfg["fog_density"]) > 0.0
	env.fog_light_color = cfg["fog"]
	env.fog_density = float(cfg["fog_density"])
	env.tonemap_exposure = float(cfg.get("exposure", 1.0))
	env.glow_enabled = not Game.demo_mode or bool(cfg.get("glow_on", false))
	env.glow_intensity = float(cfg.get("glow", 0.8))
	if cfg.has("ambient_color"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = cfg["ambient_color"]
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_sky_affect = float(cfg.get("fog_sky", 1.0))
	sky.sun_angle_max = float(cfg.get("sun_disc", 30.0))
	sky.sun_curve = float(cfg.get("sun_curve", 0.15))
	env.glow_bloom = 0.1
	env.adjustment_enabled = true
	env.adjustment_saturation = float(cfg.get("saturation", 1.1))
	env.adjustment_contrast = float(cfg.get("contrast", 1.05))
	sun.shadow_enabled = not Game.demo_mode or bool(cfg.get("shadows", false))
	sun.directional_shadow_max_distance = float(cfg.get("shadow_dist", 80.0))
	sun.light_color = cfg["sun_color"]
	sun.light_energy = float(cfg["sun_energy"])
	sun.rotation_degrees = cfg["sun_rot"]


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.MASK_WORLD
	nm.cell_size = 0.5
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# --------------------------------------------------------------------------
# Population
# --------------------------------------------------------------------------
func _blocked(p: Vector3) -> bool:
	for r in keepouts:
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return Vector2(p.x, p.z).distance_to(Vector2(spawn.position.x, spawn.position.z)) < 5.0


func random_spawn_point(min_dist: float = 14.0) -> Vector3:
	var pp := player.global_position
	if not spawn_points.is_empty():
		var far: Array[Vector3] = []
		for sp in spawn_points:
			if Vector2(sp.x, sp.z).distance_to(Vector2(pp.x, pp.z)) >= min_dist:
				far.append(sp)
		var base: Vector3 = far.pick_random() if not far.is_empty() else spawn_points.pick_random()
		return base + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2))
	for i in 60:
		var p := Vector3(randf_range(-arena_half + 4.0, arena_half - 4.0), 0.2, randf_range(-arena_half + 4.0, arena_half - 4.0))
		if not _blocked(p) and Vector2(p.x, p.z).distance_to(Vector2(pp.x, pp.z)) >= min_dist:
			return p
	return Vector3(arena_half - 6.0, 0.2, -arena_half + 6.0)


func _spawn_props() -> void:
	if level_index >= 8:
		return
	if level_index == 6 or level_index == 7:
		return
	var kinds: Array[StringName] = prop_kinds.duplicate()
	kinds.append(&"tnt")
	kinds.append(&"tnt")
	for i in prop_count:
		var p := Prop.make(kinds.pick_random())
		var pos := random_spawn_point(0.0)
		pos.y += randf_range(1.0, 3.0)
		p.position = pos
		props_root.add_child(p)
	# A crate pyramid near spawn: instant bowling alley.
	var base := spawn.position + Vector3(9.0, 0.0, -2.0)
	if level_index != 4 and level_index != 5:
		for layer in 4:
			for i in 4 - layer:
				var c := Prop.make(&"crate", 1.0)
				c.position = base + Vector3((i - (3 - layer) * 0.5) * 1.1, 0.5 + layer * 1.0, 0)
				props_root.add_child(c)


# --------------------------------------------------------------------------
# Primitive helpers used by LevelBuilder
# --------------------------------------------------------------------------
func _make_checker_material() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 1, 1))
	img.set_pixel(1, 1, Color(1, 1, 1))
	img.set_pixel(1, 0, Color(0.8, 0.8, 0.8))
	img.set_pixel(0, 1, Color(0.8, 0.8, 0.8))
	_checker_mat = StandardMaterial3D.new()
	_checker_mat.albedo_texture = ImageTexture.create_from_image(img)
	_checker_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_checker_mat.uv1_triplanar = true
	_checker_mat.uv1_world_triplanar = true
	_checker_mat.uv1_scale = Vector3.ONE * 0.25
	_checker_mat.roughness = 0.8


func _material(color: Color, glow: float, checker: bool) -> StandardMaterial3D:
	var m: StandardMaterial3D
	if checker:
		m = _checker_mat.duplicate() as StandardMaterial3D
		m.albedo_color = color
	else:
		m = Roster.mat(color, glow)
	if glow > 0.0 and checker:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _place(shape: Shape3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, color: Color, glow: float, collide: bool, checker: bool) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, glow, checker)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = Game.MASK_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.add_child(mi)
		body.position = pos
		body.rotation_degrees = rot_deg
		geometry.add_child(body)
		return body
	mi.position = pos
	mi.rotation_degrees = rot_deg
	decor.add_child(mi)
	return mi


func box(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, glow: float = 0.0,
		collide: bool = true, checker: bool = true) -> Node3D:
	var bs := BoxShape3D.new()
	bs.size = size
	return _place(bs, Roster.box(size), pos, rot_deg, color, glow, collide, checker and collide)


func cyl(r: float, h: float, pos: Vector3, color: Color, glow: float = 0.0, collide: bool = true,
		rot_deg: Vector3 = Vector3.ZERO, checker: bool = false) -> Node3D:
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = h
	return _place(cs, Roster.cyl(r, r, h), pos, rot_deg, color, glow, collide, checker)


func cone(r: float, h: float, pos: Vector3, color: Color, glow: float = 0.0, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	return _place(null, Roster.cyl(0.0, r, h), pos, rot_deg, color, glow, false, false)


func ball(r: float, pos: Vector3, color: Color, glow: float = 0.0, collide: bool = true, checker: bool = false) -> Node3D:
	var ss := SphereShape3D.new()
	ss.radius = r
	return _place(ss, Roster.sphere(r), pos, Vector3.ZERO, color, glow, collide, checker)


func prism(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, glow: float = 0.0) -> Node3D:
	var pm := PrismMesh.new()
	pm.size = size
	return _place(null, pm, pos, rot_deg, color, glow, false, false)


func torus(inner: float, outer: float, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, glow: float = 0.0) -> Node3D:
	return _place(null, Roster.torus(inner, outer), pos, rot_deg, color, glow, false, false)


## Ramp rising from ground at z_low toward dir (+/-1 along Z). Returns the high-end z.
func ramp(x: float, z_low: float, dir: float, height: float, deg: float, width: float, color: Color, yaw_deg: float = 0.0) -> float:
	var th := deg_to_rad(deg)
	var length := height / sin(th)
	var run := length * cos(th)
	var thick := 0.6
	var cy := height * 0.5 - thick * 0.5 * cos(th)
	var cz := dir * (run * 0.5 + thick * 0.5 * sin(th))
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0, z_low)
	pivot.rotation_degrees.y = yaw_deg
	geometry.add_child(pivot)
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, thick, length)
	var body := StaticBody3D.new()
	body.collision_layer = Game.MASK_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = Roster.box(bs.size)
	mi.material_override = _material(color, 0.0, true)
	body.add_child(mi)
	body.position = Vector3(0, cy, cz)
	body.rotation_degrees = Vector3(-dir * deg, 0, 0)
	pivot.add_child(body)
	return z_low + dir * run


func light(pos: Vector3, color: Color, energy: float = 2.0, rng: float = 10.0, flicker: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	decor.add_child(l)
	if flicker:
		_flicker.append([l, energy, randf() * 10.0])
	return l


func spot(pos: Vector3, look_at_pos: Vector3, color: Color, energy: float = 4.0, rng: float = 30.0, angle: float = 30.0, spin_parent: bool = false) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = color
	s.light_energy = energy
	s.spot_range = rng
	s.spot_angle = angle
	decor.add_child(s)
	s.position = pos
	s.look_at(look_at_pos, Vector3.UP if absf((look_at_pos - pos).normalized().y) < 0.99 else Vector3.RIGHT)
	return s


func spinner(center: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = center
	decor.add_child(n)
	_spinners.append(n)
	return n


func zone(type: StringName, pos: Vector3, size: Vector3, launch: Vector3 = Vector3.ZERO, tint: Color = Color(0, 0, 0, 0), show: bool = true) -> Zone:
	return Zone.make(decor, type, pos, size, launch, tint, show)


func keepout(x: float, z: float, w: float, d: float) -> void:
	keepouts.append(Rect2(x - w * 0.5, z - d * 0.5, w, d))


func particles(pos: Vector3, box_size: Vector3, amount: int, life: float, gravity: Vector3, color: Color, size: float, glow: bool = true, vel: float = 0.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box_size * 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = gravity
	p.local_coords = false
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material = mat
	p.mesh = m
	p.position = pos
	p.emitting = false
	decor.add_child(p)
	p.emitting = true
	return p


# --------------------------------------------------------------------------
# Peek level: rail stations
# --------------------------------------------------------------------------
func _peek_begin_station(i: int) -> void:
	peek_station = i
	_peek_moving = false
	_peek_clear_t = 0.0
	var pz: float = LevelBuilder.PEEK_STATIONS[i]
	player.rail_anchor = Vector3(0.0, 0.1, pz)
	for spec: Array in LevelBuilder.peek_baddies(i, _peek_round):
		var e := director.spawn_enemy(spec[0], spec[1])
		e.cover = true
	Game.banner("STATION %d: sniff them out" % (i + 1), Color(1.0, 0.9, 0.5), 2.2)


func _peek_advance() -> void:
	_peek_moving = true
	var next := peek_station + 1
	if next >= LevelBuilder.PEEK_STATIONS.size():
		_peek_round += 1
		next = 0
		Game.banner("AREA CLEARED!  Round %d" % (_peek_round + 1), Color(0.6, 1.0, 0.6), 2.6)
		Prog.add_xp(40)
	else:
		Game.banner("ON THE MOVE...", Color(0.8, 0.9, 1.0), 1.6)
	var dest: float = LevelBuilder.PEEK_STATIONS[next]
	var secs := 2.0 + absf(dest - player.rail_anchor.z) / 25.0
	var tw := create_tween()
	tw.tween_property(player, "rail_anchor:z", dest, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_peek_begin_station.bind(next))


# --------------------------------------------------------------------------
# Nod Flight (level 7): the player body sleeps, the FlightRig owns the camera
# --------------------------------------------------------------------------
func _start_flight() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	hud.visible = false
	if Game.downhill_mode:
		_dh = RunRig.new() if Game.run_mode else DownhillRig.new()
		add_child(_dh)
		_dh.setup(player)
		return
	_rig = FlightRig.new()
	add_child(_rig)
	_rig.setup(player)


func _start_trance() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	hud.visible = false
	_tr = TranceRig.new()
	add_child(_tr)
	_tr.setup(player)


func _start_gaze_test() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	hud.visible = false
	_gt = GazeTestRig.new()
	add_child(_gt)
	_gt.setup(player)


func _stop_flight() -> void:
	if _gt != null and is_instance_valid(_gt):
		_gt.cleanup()
		_gt.queue_free()
	_gt = null
	if _tr != null and is_instance_valid(_tr):
		_tr.cleanup()
		_tr.queue_free()
	_tr = null
	if _dh != null and is_instance_valid(_dh):
		_dh.cleanup()
		_dh.queue_free()
	_dh = null
	if _rig != null and is_instance_valid(_rig):
		_rig.cleanup()
		_rig.queue_free()
	_rig = null
	if player.process_mode == Node.PROCESS_MODE_DISABLED:
		player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	hud.visible = true
	if player.camera != null:
		player.camera.make_current()
