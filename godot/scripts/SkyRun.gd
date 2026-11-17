class_name SkyRun
extends Node3D
## ABOVE THE CLOUDS. A ramp hit hard enough (a sky ramp, or a super ramp taken very fast or on a long chain) blasts the board up through the cloud deck, and the ride goes on
## as FLIGHT: a slow, floating break from the racing, with plenty to do, for thirty seconds or more, and then a dive back down through the clouds.
##
## HOW IT IS FLOWN
##   eyes      look left, middle or right and the thing there is LOCKED (a green ring on it): the board flies at it by itself, up and down as well. The faint rings are the
##             things that can be looked at. Look at the other side and the lock moves.
##   head      chin UP climbs and floats, chin DOWN dives and charges the energy bar. A nod always wins over the autopilot, so the head can take any height it wants.
##   BLAST     snap the chin up (or tap the screen, or W) with energy in the bar: a burst of speed in which walls shatter and the big piñata can be hit.
##   SLAM      snap the chin down from height (or S): a dive that crushes the cupcakes standing on the clouds.
## EVERY HIT chains: hits within three seconds of each other build a multiplier, and the sounds climb with it. Sweets floating by are power-ups (magnet, slow time, double
## points, a shield, overdrive). Later a giant piñata drifts in; it takes three blasts to burst, and it rains stars. The longer you are up, the further the trip comes on.

const DECK_Y := 1400.0                      # world height of the cloud tops
const CRUISE := 28.0
const MAX_SPEED := 90.0
const MIN_SPEED := 14.0
const GROUND := 2.0                         # the cloud deck, as far as slamming goes
const CEILING := 130.0
const SWEET := [Color(1.0, 0.25, 0.6), Color(0.1, 0.75, 1.0), Color(1.0, 0.6, 0.05), Color(0.3, 0.9, 0.3), Color(0.65, 0.35, 1.0)]
const LOCKABLE := ["ring", "balloon", "pickup", "pinata", "wind", "bumper", "sling"]

var rig: RunRig = null
var cam: Camera3D
var heading: float = 0.0
var speed: float = CRUISE
var alt: float = -70.0                      # height over the deck; negative: still coming up through the cloud
var vy: float = 95.0
var energy: float = 0.0
var groove: float = 1.0
var chain: int = 0
var chain_t: float = 0.0
var combo: int = 0
var combo_t: float = 0.0
var best_combo: int = 0
var score: int = 0
var blast_t: float = 0.0
var blast_cd: float = 0.0
var slam_active: bool = false
var slam_power: float = 0.0
var slam_cd: float = 0.0
var hurt_t: float = 0.0
var nod_p: float = 0.0
var nod_v: float = 0.0
var steer: float = 0.0
var phase: int = 0                          # 0 coming up through the cloud, 1 flying, 2 diving back down
var timer: float = 0.0
var duration: float = 36.0
var goals: Array = []
var items: Array[Dictionary] = []
var buffs := {"magnet": 0.0, "slow": 0.0, "x2": 0.0, "shield": 0.0}
var stats := {"rings": 0, "balloons": 0, "targets": 0, "walls": 0, "stars": 0, "pickups": 0, "crashes": 0, "pinata": 0, "bumpers": 0, "slings": 0}
var lock: Dictionary = {}
var cand_l: Dictionary = {}
var cand_m: Dictionary = {}
var cand_r: Dictionary = {}
var trip_lvl: float = 0.0
var _lock_want: Dictionary = {}
var _lock_dwell: float = 0.0
var _rng := RandomNumberGenerator.new()
var _next_z: float = 0.0
var _prev_pos: Vector3 = Vector3.ZERO
var _hud: Control
var _deck: MeshInstance3D
var _deck_mat: ShaderMaterial
var _puff_mesh: SphereMesh
var _puff_mat: StandardMaterial3D
var _chunks: Array = []
var _shake: float = 0.0
var _fov_punch: float = 0.0
var _flash: float = 0.0
var _age: float = 0.0
var _white: float = 1.0
var _clear_t: float = -1.0
var _feed: Array = []                       # words in the middle of the screen: [text, colour, age]
var _pops: Array = []                       # numbers that float up from what was hit: [text, world position, colour, age]
var _start_z: float = 0.0
var _start_x: float = 0.0
var _done: bool = false
var _tap: bool = false
var _pinata_spawned: bool = false
var _flick_t: float = 2.0
var _flick_back: float = 0.0
var _flick_world: String = "psychedelic"
var _trip_pulse: float = 0.0
var _base_world: String = "alpine"
var _trip_peak: float = 0.5
var _hist_nod: float = 0.0
var _brow_was: bool = false
var _zone: int = 0
var _mid_dwell: float = 0.0
var _kick: Vector3 = Vector3.ZERO
var _hot_lane: int = 0
var _hot_left: int = 0
var _wind_gap: int = 0
var _hint_big: bool = false

const DECK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 tint = vec3(1.0);
uniform float trip = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
vec3 hsv(float hh, float s, float v) {
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(hh) + k) * 6.0 - 3.0);
	return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}
void fragment() {
	vec2 p = wp.xz * 0.011;
	float v = n(p) * 0.55 + n(p * 2.1 + 7.0) * 0.3 + n(p * 4.3 + 3.0) * 0.15;
	vec3 c = mix(vec3(0.66, 0.74, 0.93), vec3(1.0), smoothstep(0.32, 0.78, v));
	// the trip: the clouds go iridescent, bands of colour that drift across them
	float bands = fract(v * 1.6 + TIME * 0.06 + wp.x * 0.0012);
	c = mix(c, hsv(bands, 0.65, 1.0), trip * 0.6 * (0.35 + 0.65 * v));
	ALBEDO = c * tint;
}
"""


func setup(r: RunRig, wave: int) -> void:
	name = "SkyRun"
	rig = r
	_rng.seed = int(Time.get_ticks_usec()) & 0xffffff
	duration = clampf(34.0 + 2.0 * float(wave), 34.0, 56.0)
	_trip_peak = clampf(0.45 + 0.07 * float(wave), 0.45, 0.95)
	_base_world = rig._jw
	_flick_world = rig._journey.world if rig._journey != null else "psychedelic"
	_start_z = rig.spos.z
	_start_x = rig.spos.x
	global_position = Vector3(_start_x, DECK_Y + alt, _start_z)
	_prev_pos = global_position
	_next_z = _start_z - 130.0
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.make_current()
	_build_deck()
	_pick_goals(wave)
	var hcf := ConfigFile.new()
	hcf.load("user://sky_hint.cfg")
	var seen := int(hcf.get_value("h", "n", 0))
	_hint_big = seen < 3
	hcf.set_value("h", "n", seen + 1)
	hcf.save("user://sky_hint.cfg")
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	while _next_z > _start_z - 560.0:
		_spawn_chunk(_next_z)
		_next_z -= _rng.randf_range(34.0, 50.0)
	Game.sfx(&"boom")
	_fov_punch = 20.0


func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		_tap = true          # a tap anywhere is a blast: there is always a way to do it, whatever the head is doing


func _build_deck() -> void:
	var sh := Shader.new()
	sh.code = DECK_SHADER
	_deck_mat = ShaderMaterial.new()
	_deck_mat.shader = sh
	var td: Dictionary = Themes.theme_data(rig._jw)
	var c: Color = td["c2"]
	_deck_mat.set_shader_parameter("tint", Vector3(lerpf(1.0, c.r, 0.35), lerpf(1.0, c.g, 0.35), lerpf(1.0, c.b, 0.35)))
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600.0, 2600.0)
	_deck = MeshInstance3D.new()
	_deck.mesh = pm
	_deck.material_override = _deck_mat
	_deck.top_level = true
	_deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_deck)
	_puff_mesh = SphereMesh.new()
	_puff_mesh.radius = 1.0
	_puff_mesh.height = 1.4
	_puff_mesh.radial_segments = 8
	_puff_mesh.rings = 4
	_puff_mat = StandardMaterial3D.new()
	_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_puff_mat.albedo_color = Color(1, 1, 1)


func _pick_goals(wave: int) -> void:
	var pool := [["rings", "RINGS", 5 + wave / 2], ["balloons", "BALLOONS", 6], ["targets", "CUPCAKES", 4], ["walls", "WALLS", 2], ["stars", "STARS", 8 + wave], ["pickups", "POWER-UPS", 3], ["combo", "COMBO", 10]]
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: Array = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	goals.clear()
	for i in 3:
		var p: Array = pool[i]
		goals.append({"k": String(p[0]), "label": String(p[1]), "need": mini(int(p[2]), 12), "have": 0, "done": false})


func _wanted(kind: String) -> float:
	for g in goals:
		if String(g["k"]) == kind and not bool(g["done"]):
			return 1.8
	return 1.0


# --------------------------------------------------------------------------
# What is up here
# --------------------------------------------------------------------------
func _node_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.top_level = true
	n.global_position = pos
	return n


func _spawn_chunk(z: float) -> void:
	var cx := _start_x + sin((z - _start_z) * 0.011) * 36.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _puff_mesh
	mm.instance_count = 34
	for i in 34:
		var s := _rng.randf_range(7.0, 26.0)
		var px := cx + _rng.randf_range(-320.0, 320.0)
		var pz := z - _rng.randf_range(0.0, 52.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * 0.6, s)), Vector3(px, DECK_Y + 1.0 + s * 0.15, pz)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _puff_mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks.append({"z": z, "n": mi})
	# THREE LANES, left, middle and right, and something in each (nearly always), so there is always a choice and the middle is never empty. One lane is the HOT lane for a
	# few chunks in a row: rings, stars and winds one after another down it, an epic run for anyone who stays on it. A boost ring is never more than a few chunks away.
	var y := DECK_Y
	if _hot_left <= 0:
		_hot_lane = [-1, 0, 1][_rng.randi() % 3]
		_hot_left = _rng.randi_range(3, 5)
	_hot_left -= 1
	_wind_gap += 1
	var wave_y := 30.0 + 12.0 * sin((z - _start_z) * 0.02)
	for lane in [-1, 0, 1]:
		var lx: float = cx + float(lane) * 17.0 + _rng.randf_range(-2.0, 2.0)
		var hot: bool = lane == _hot_lane
		if not hot and _rng.randf() > 0.82:
			continue
		var kind := ""
		if hot:
			var hr := _rng.randf()
			kind = "ring" if hr < 0.5 else ("stars" if hr < 0.85 else "wind")
		else:
			var w := {"ring": 0.24, "balloon": 0.20, "jelly": 0.10, "wind": 0.10, "pickup": 0.10 * _wanted("pickups"), "stars": 0.10 * _wanted("stars"), "cake": 0.08 * _wanted("targets"), "pillar": 0.04 if lane != 0 else 0.0, "storm": 0.02, "wall": 0.04 if lane == 0 else 0.0, "bumper": 0.12, "sling": 0.08}
			w["ring"] = float(w["ring"]) * _wanted("rings")
			w["balloon"] = float(w["balloon"]) * _wanted("balloons")
			var tot := 0.0
			for k in w:
				tot += float(w[k])
			var r := _rng.randf() * tot
			kind = "ring"
			for k in w:
				r -= float(w[k])
				if r <= 0.0:
					kind = String(k)
					break
		if lane == 0 and _wind_gap >= 3 and not hot:
			kind = "wind"
		if kind == "wind":
			_wind_gap = 0
		var ly := y + (wave_y if hot else _rng.randf_range(18.0, 52.0))
		match kind:
			"ring":
				_add_ring(Vector3(lx, ly, z), false)
			"wind":
				_add_ring(Vector3(lx, ly, z), true)
			"balloon":
				for i in 2:
					_add_balloon(Vector3(lx + _rng.randf_range(-4.0, 4.0), y + _rng.randf_range(16.0, 56.0), z - float(i) * 9.0), 0.0)
			"jelly":
				_add_balloon(Vector3(lx, ly, z), _rng.randf_range(6.0, 10.0))
			"wall":
				_add_wall(Vector3(lx, y, z))
			"pillar":
				_add_pillar(Vector3(lx, y, z))
			"cake":
				for i in 3:
					_add_cake(Vector3(lx + _rng.randf_range(-6.0, 6.0), y, z - float(i) * 10.0))
			"stars":
				for i in 6:
					_add_star(Vector3(lx + sin(float(i) * 0.9) * 6.0, ly + cos(float(i) * 0.9) * 5.0, z - float(i) * 6.0))
			"pickup":
				_add_pickup(Vector3(lx, ly, z), ["magnet", "slow", "x2", "shield", "over"][_rng.randi() % 5])
			"storm":
				_add_storm(Vector3(lx, ly, z))
			"bumper":
				_add_bumper(Vector3(lx, ly, z))
				_add_bumper(Vector3(lx - 9.0, ly + 6.0, z - 12.0))
				_add_bumper(Vector3(lx + 9.0, ly - 4.0, z - 24.0))
			"sling":
				_add_sling(Vector3(lx, ly, z))


func _add_ring(pos: Vector3, wind: bool) -> void:
	var n := _node_at(pos)
	var col: Color = Color(0.5, 1.0, 0.5) if wind else SWEET[_rng.randi() % 3]
	Roster.mi(n, Roster.torus(4.6, 7.0), Vector3.ZERO, col, Vector3(90, 0, 0), 0.5)
	if wind:
		Roster.mi(n, Roster.torus(2.6, 3.4), Vector3.ZERO, Color(0.8, 1.0, 0.7), Vector3(90, 0, 0), 0.6)
	items.append({"type": "wind" if wind else "ring", "node": n, "pos": pos, "r": 6.0, "done": false})


func _add_balloon(pos: Vector3, amp: float) -> void:
	var n := _node_at(pos)
	var col: Color = SWEET[_rng.randi() % SWEET.size()]
	var b := Roster.mi(n, Roster.sphere(3.0, 1.15), Vector3.ZERO, col, Vector3.ZERO, 0.3)
	b.scale = Vector3(1.0, 1.1, 1.0)
	Roster.mi(n, Roster.cyl(0.05, 0.05, 4.0), Vector3(0, -4.4, 0), Color(1, 1, 1))
	if amp > 0.0:
		Roster.mi(n, Roster.torus(3.2, 3.6), Vector3.ZERO, Color(1, 1, 1), Vector3(90, 0, 0), 0.4)          # a jelly one: it drifts from side to side
	items.append({"type": "balloon", "node": n, "pos": pos, "bx": pos.x, "amp": amp, "ph": _rng.randf() * TAU, "r": 5.0, "done": false})


func _add_star(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.sphere(1.5, 1.0), Vector3.ZERO, Color(1.0, 0.8, 0.1), Vector3.ZERO, 0.8)
	items.append({"type": "star", "node": n, "pos": pos, "r": 4.4, "done": false})


func _add_wall(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.box(Vector3(20, 16, 1.6)), Vector3(0, 8, 0), Color(1.0, 0.55, 0.8), Vector3.ZERO, 0.5)
	Roster.mi(n, Roster.box(Vector3(20.4, 1.2, 2.0)), Vector3(0, 16.4, 0), Color(1.0, 0.95, 0.85), Vector3.ZERO, 1.0)
	items.append({"type": "wall", "node": n, "pos": pos, "r": 10.0, "done": false})


func _add_pillar(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.cyl(1.6, 1.8, 46.0), Vector3(0, 23, 0), Color(0.62, 0.55, 0.75))
	Roster.mi(n, Roster.sphere(3.4, 1.0), Vector3(0, 47, 0), Color(1.0, 0.7, 0.85), Vector3.ZERO, 0.4)
	items.append({"type": "pillar", "node": n, "pos": pos, "r": 3.0, "done": false})


func _add_cake(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.cyl(1.4, 1.0, 1.0), Vector3(0, 0.6, 0), Color(0.75, 0.55, 0.95))
	Roster.mi(n, Roster.sphere(1.5, 1.0), Vector3(0, 1.7, 0), Color(1.0, 0.45, 0.75), Vector3.ZERO, 0.6)
	Roster.mi(n, Roster.sphere(0.45, 1.0), Vector3(0, 3.1, 0), Color(1.0, 0.1, 0.2), Vector3.ZERO, 0.8)
	items.append({"type": "cake", "node": n, "pos": pos, "r": 2.2, "done": false})


## PINBALL BUMPER: a pink gumdrop with a cherry and a ring. Fly into it and it knocks the board away, and it can be hit again and again: three of them close together make a pinball table.
func _add_bumper(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.sphere(2.6, 1.0), Vector3.ZERO, Color(1.0, 0.3, 0.7), Vector3.ZERO, 0.7)
	Roster.mi(n, Roster.torus(3.2, 3.7), Vector3.ZERO, Color(1, 1, 1), Vector3(90, 0, 0), 0.8)
	Roster.mi(n, Roster.sphere(0.8, 1.0), Vector3(0, 3.0, 0), Color(1.0, 0.1, 0.2), Vector3.ZERO, 0.9)
	items.append({"type": "bumper", "node": n, "pos": pos, "r": 5.4, "cool": 0.0, "done": false})


## GRAVITY SLINGSHOT: a glowing orb with slow turning bands. Come near and it draws the board in, faster the closer it gets, and as the board swings past it lets go with a fling and a blast.
func _add_sling(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.sphere(2.2, 1.0), Vector3.ZERO, Color(0.6, 0.95, 1.0), Vector3.ZERO, 1.5)
	var rs: Array = []
	var cols := [Color(0.5, 0.9, 1.0), Color(1.0, 0.85, 0.45), Color(0.6, 0.8, 1.0)]
	for i in 3:
		rs.append(Roster.mi(n, Roster.torus(4.0 + 2.2 * float(i), 4.4 + 2.2 * float(i)), Vector3.ZERO, cols[i], Vector3(60.0 * float(i), 0, 30.0 * float(i)), 0.9))
	items.append({"type": "sling", "node": n, "pos": pos, "rings": rs, "r": 34.0, "in": false, "used": false, "done": false})


func _add_storm(pos: Vector3) -> void:
	var n := _node_at(pos)
	for i in 4:
		Roster.mi(n, Roster.sphere(3.4, 1.0), Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-2, 2), _rng.randf_range(-3, 3)), Color(0.22, 0.12, 0.35), Vector3.ZERO, 0.0)
	Roster.mi(n, Roster.sphere(1.0, 1.0), Vector3(0, -3.5, 0), Color(1.0, 0.9, 0.3), Vector3.ZERO, 1.5)
	items.append({"type": "storm", "node": n, "pos": pos, "r": 6.5, "done": false})


## Power-ups are sweets: a magnet, a stopwatch, double points, a donut shield and a rocket. Each is a different colour and shape and glows.
func _add_pickup(pos: Vector3, kind: String) -> void:
	var n := _node_at(pos)
	match kind:
		"magnet":
			Roster.mi(n, Roster.torus(0.8, 1.7), Vector3.ZERO, Color(1.0, 0.2, 0.2), Vector3(90, 0, 0), 0.8)
			Roster.mi(n, Roster.box(Vector3(0.7, 1.2, 0.7)), Vector3(-1.25, -1.2, 0), Color(0.95, 0.95, 0.95), Vector3.ZERO, 0.4)
			Roster.mi(n, Roster.box(Vector3(0.7, 1.2, 0.7)), Vector3(1.25, -1.2, 0), Color(0.95, 0.95, 0.95), Vector3.ZERO, 0.4)
		"slow":
			Roster.mi(n, Roster.sphere(1.6, 1.0), Vector3.ZERO, Color(0.4, 0.8, 1.0), Vector3.ZERO, 0.8)
			Roster.mi(n, Roster.torus(1.8, 2.3), Vector3.ZERO, Color(1, 1, 1), Vector3(90, 0, 0), 0.8)
		"x2":
			Roster.mi(n, Roster.sphere(1.7, 1.0), Vector3.ZERO, Color(1.0, 0.8, 0.1), Vector3.ZERO, 1.2)
			Roster.mi(n, Roster.sphere(0.5, 1.0), Vector3(2.4, 0, 0), Color(1.0, 0.95, 0.5), Vector3.ZERO, 1.2)
			Roster.mi(n, Roster.sphere(0.5, 1.0), Vector3(-2.4, 0, 0), Color(1.0, 0.95, 0.5), Vector3.ZERO, 1.2)
		"shield":
			Roster.mi(n, Roster.torus(1.0, 2.1), Vector3.ZERO, Color(1.0, 0.45, 0.8), Vector3(90, 0, 0), 0.8)
			Roster.mi(n, Roster.sphere(0.5, 1.0), Vector3(1.6, 0.6, 0), Color(0.5, 1.0, 0.6), Vector3.ZERO, 0.6)
			Roster.mi(n, Roster.sphere(0.5, 1.0), Vector3(-1.4, -0.8, 0), Color(0.5, 0.8, 1.0), Vector3.ZERO, 0.6)
		_:
			Roster.mi(n, Roster.cyl(0.0, 1.5, 3.2), Vector3(0, 0.4, 0), Color(1.0, 0.5, 0.1), Vector3.ZERO, 0.9)
			Roster.mi(n, Roster.sphere(1.0, 1.0), Vector3(0, -1.4, 0), Color(1.0, 0.9, 0.3), Vector3.ZERO, 1.5)
	var col := {"magnet": Color(1.0, 0.3, 0.3), "slow": Color(0.5, 0.85, 1.0), "x2": Color(1.0, 0.85, 0.2), "shield": Color(1.0, 0.5, 0.85), "over": Color(1.0, 0.6, 0.2)}[kind] as Color
	items.append({"type": "pickup", "kind": kind, "col": col, "node": n, "pos": pos, "r": 4.6, "done": false})


## The piñata: a giant striped sweet with spikes. Three blasts through it and it bursts into stars.
func _add_pinata(pos: Vector3) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.sphere(8.0, 1.0), Vector3.ZERO, Color(1.0, 0.35, 0.7), Vector3.ZERO, 0.6)
	for ci in 3:
		Roster.mi(n, Roster.torus(7.8 - float(ci) * 1.5, 8.6 - float(ci) * 1.5), Vector3(0, float(ci - 1) * 3.2, 0), SWEET[(ci + 1) % 5], Vector3(90, 0, 0), 0.8)
	for si in 8:
		var a := float(si) / 8.0 * TAU
		Roster.mi(n, Roster.cyl(0.0, 1.8, 6.0), Vector3(cos(a) * 9.5, sin(a * 2.0) * 3.0, sin(a) * 9.5), Color.from_hsv(float(si) / 8.0, 0.8, 1.0), Vector3(0, 0, -rad_to_deg(a) + 90.0), 0.9)
	items.append({"type": "pinata", "node": n, "pos": pos, "r": 11.0, "hp": 3, "cool": 0.0, "done": false})


# --------------------------------------------------------------------------
# Flight
# --------------------------------------------------------------------------
func _say(text: String, col: Color) -> void:
	_feed.append([text, col, 0.0])
	if _feed.size() > 3:
		_feed.pop_front()


func _goal(kind: String, n: int = 1) -> void:
	for g in goals:
		if String(g["k"]) == kind and not bool(g["done"]):
			g["have"] = int(g["have"]) + n
			if int(g["have"]) >= int(g["need"]):
				g["done"] = true
				score += int(300.0 * _mult())
				_say("%s DONE" % String(g["label"]), Color(1.0, 0.9, 0.4))
				Game.sfx(&"levelup")
	var all := true
	for g in goals:
		all = all and bool(g["done"])
	if all and _clear_t < 0.0:
		_clear_t = 0.0
		score += int(1500.0 * _mult())
		_say("SKY CLEARED", Color(0.6, 1.0, 0.8))
		rig._cheer("SKY CLEARED!", Color(0.6, 1.0, 0.8), 1.6)


func _mult() -> float:
	return (1.0 + 0.25 * float(mini(maxi(combo - 1, 0), 16))) * (2.0 if float(buffs["x2"]) > 0.0 else 1.0) * groove


## Every hit: the combo goes up, the number floats up from the thing, the sound climbs, the screen kicks a little. A few counts of the combo pay out.
func _hit(it: Dictionary, base_pts: int, col: Color) -> void:
	combo = combo + 1 if combo_t > 0.0 else 1
	combo_t = 4.5 if float(buffs["slow"]) > 0.0 else 3.0
	best_combo = maxi(best_combo, combo)
	var pts := int(float(base_pts) * _mult())
	score += pts
	_pops.append(["+%d" % pts, it["pos"], col, 0.0])
	energy = minf(energy + 5.0, 100.0)
	_fov_punch = maxf(_fov_punch, 2.0 + 0.5 * float(mini(combo, 12)))
	_shake = maxf(_shake, 0.05)
	Game.sfx([&"blip", &"coin", &"zap", &"boing2"][combo % 4])
	_goal("combo", 0)
	for g in goals:
		if String(g["k"]) == "combo" and not bool(g["done"]):
			g["have"] = best_combo
			if best_combo >= int(g["need"]):
				_goal("combo", 0)
	if combo == 5 or combo == 10 or combo == 15 or combo == 25 or combo == 40:
		score += 100 * combo
		energy = 100.0
		_trip_pulse = maxf(_trip_pulse, 0.18)
		_say("COMBO x%d" % combo, Color(1.0, 0.85, 0.3))
		rig._cheer("COMBO x%d" % combo, Color(1.0, 0.85, 0.3), 0.9 + 0.05 * float(mini(combo, 20)))
		Fx.confetti(self, global_position + Vector3(0, 2, -8), 30 + combo * 2, 1.0)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	nod_p = 0.0
	nod_v = 0.0
	blast_cd = maxf(blast_cd - delta, 0.0)
	slam_cd = maxf(slam_cd - delta, 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	chain_t -= delta
	combo_t -= delta
	if combo_t <= 0.0 and combo > 0:
		combo = 0
	if chain_t <= 0.0 and chain > 0:
		chain = 0
		groove = 1.0
	for k in buffs:
		if k != "shield":
			buffs[k] = maxf(float(buffs[k]) - delta, 0.0)
	if _clear_t >= 0.0:
		_clear_t += delta
	_trip_tick(delta)
	if phase == 0:
		alt += vy * delta
		vy = maxf(vy - 30.0 * delta, 30.0)
		if alt >= 6.0:
			phase = 1
			_flash = 0.7
			_fov_punch = 14.0
			Game.sfx(&"snap")
			rig._cheer("ABOVE THE CLOUDS", Color(0.8, 0.95, 1.0), 1.5)
		_move(delta, 0.0)
		_tap = false
		return
	if phase == 1:
		timer += delta
		if not _pinata_spawned and timer >= duration * 0.55:
			_pinata_spawned = true
			_add_pinata(Vector3(global_position.x + _rng.randf_range(-10.0, 10.0), DECK_Y + 34.0, global_position.z - 230.0))
			_say("PIÑATA AHEAD: BLAST IT", Color(1.0, 0.5, 0.8))
		if timer >= duration or _clear_t > 4.0:
			phase = 2
			vy = -100.0
			slam_active = false
			_say("DIVE", Color(1.0, 0.8, 0.5))
	if phase == 2:
		alt += vy * delta
		vy = minf(vy - 40.0 * delta, -60.0)
		speed = move_toward(speed, CRUISE, 20.0 * delta)
		_move(delta, 0.0)
		_tap = false
		if alt <= -45.0:
			_finish()
		return
	# time can be slowed by a power-up: the board and the world keep the same speed but everything is taken more gently
	var ts := 0.65 if float(buffs["slow"]) > 0.0 else 1.0
	_lock_tick(delta)
	# EYES ONLY. The lock is the only steering: the board flies at what it is locked on, up and down as well. The bar fills by itself and with every hit; a look held straight
	# ahead for a moment, with a lock and enough in the bar, is the blast (or a tap).
	steer = clampf(_lock_steer(), -1.0, 1.0)
	vy = lerpf(vy, _auto_vy(), 1.0 - exp(-2.4 * delta))
	energy = minf(energy + 2.5 * delta, 100.0)
	if blast_t <= 0.0:
		speed = move_toward(speed, CRUISE, 5.0 * delta)
	if _zone == 0 and not lock.is_empty() and energy >= 50.0:
		_mid_dwell += delta
	else:
		_mid_dwell = 0.0
	if (_mid_dwell >= 0.45 or _tap) and energy > 12.0 and blast_cd <= 0.0:
		_blast()
		_mid_dwell = 0.0
	_tap = false
	if blast_t > 0.0:
		blast_t -= delta
	_move(delta, ts)
	_magnet_tick(delta)
	_items_tick(delta)
	_flicker_tick(delta)
	while _next_z > global_position.z - 560.0:
		_spawn_chunk(_next_z)
		_next_z -= _rng.randf_range(34.0, 50.0)
	_cleanup_behind()


func _move(delta: float, ts: float) -> void:
	var dt := delta * (ts if ts > 0.0 else 1.0)
	heading = clampf(heading - steer * (0.7 + speed / 100.0) * dt, -0.9, 0.9)
	if absf(steer) < 0.15 and lock.is_empty():
		heading *= exp(-0.5 * dt)
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	_prev_pos = global_position
	var np := global_position + fwd * speed * dt
	if phase == 1:
		alt += _kick.y * dt
		np += Vector3(_kick.x, 0.0, 0.0) * dt
		_kick *= exp(-3.5 * dt)
		alt = clampf(alt + vy * dt, GROUND, CEILING) if not slam_active else alt + vy * dt
		if alt >= CEILING:
			vy = minf(vy, 0.0)
		if alt <= GROUND:
			if slam_active:
				_slam_impact()
			alt = GROUND
			vy = maxf(vy, 0.0)
	np.y = DECK_Y + alt
	np.x = clampf(np.x, _start_x - 260.0, _start_x + 260.0)
	global_position = np


# --------------------------------------------------------------------------
# Targeting: the eyes choose, the board flies there
# --------------------------------------------------------------------------
func _lock_tick(delta: float) -> void:
	var pos := global_position
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	var cands: Array = []
	var near := 1.0e9
	for it in items:
		if bool(it["done"]) or not LOCKABLE.has(String(it["type"])):
			continue
		var rel: Vector3 = (it["pos"] as Vector3) - pos
		var dz := rel.dot(fwd)
		var lx := rel.dot(right)
		if dz < 10.0 or dz > 180.0 or absf(lx) > 90.0:
			continue
		it["_lx"] = lx
		it["_dz"] = dz
		cands.append(it)
		near = minf(near, dz)
	# the next few things ahead: the group the eyes choose between
	var grp: Array = []
	for it in cands:
		if float(it["_dz"]) <= near + 46.0:
			grp.append(it)
	for it in cands:
		if String(it["type"]) == "pinata" and not grp.has(it):
			grp.append(it)          # the piñata is always one of the things that can be looked at, however far off
	grp.sort_custom(func(a, b): return float(a["_lx"]) < float(b["_lx"]))
	cand_l = {}
	cand_m = {}
	cand_r = {}
	if not grp.is_empty():
		cand_l = grp[0]
		cand_r = grp[grp.size() - 1]
		var best := 1.0e9
		for it in grp:
			if absf(float(it["_lx"])) < 10.0 and absf(float(it["_lx"])) < best:
				best = absf(float(it["_lx"]))
				cand_m = it
	var ez := rig.eye_now()
	var zone := 0 if absf(ez) < 0.5 else (1 if ez > 0.0 else -1)
	_zone = zone
	var want: Dictionary = {}
	if zone < 0:
		want = cand_l
	elif zone > 0:
		want = cand_r
	elif lock.is_empty():
		want = cand_m if not cand_m.is_empty() else (grp[0] if not grp.is_empty() else {})          # looking at the middle with nothing locked: the nearest straight ahead
		for it in cands:
			if String(it["type"]) == "pinata":
				want = it
	if not lock.is_empty() and (bool(lock["done"]) or float(lock.get("_dz", 0.0)) < 4.0 or not cands.has(lock)):
		lock = {}
	if not want.is_empty() and not is_same(want, lock):
		if is_same(want, _lock_want):
			_lock_dwell += delta
		else:
			_lock_want = want
			_lock_dwell = 0.0
		if _lock_dwell >= 0.10:
			lock = want
			_lock_dwell = 0.0
			Game.sfx(&"blip")
	elif not want.is_empty():
		_lock_dwell = 0.0


func _lock_steer() -> float:
	var tgt := lock
	if tgt.is_empty():
		return 0.0
	var ip: Vector3 = tgt["pos"]
	var dz := global_position.z - ip.z
	if dz < 3.0:
		return 0.0
	var want_h := clampf(atan2(-(ip.x - global_position.x), dz), -0.9, 0.9)
	return clampf(-(want_h - heading) * 3.5 / (0.7 + speed / 100.0), -1.0, 1.0)


func _auto_vy() -> float:
	if lock.is_empty():
		# nothing locked: drift gently, and keep clear of the deck
		return 3.0 if alt < 14.0 else -1.0
	var ip: Vector3 = lock["pos"]
	return clampf((ip.y - global_position.y) * 0.55, -14.0, 17.0)


# --------------------------------------------------------------------------
# Moves
# --------------------------------------------------------------------------
func _blast() -> void:
	var gain := energy
	chain = (chain + 1) if chain_t > 0.0 else 1
	chain_t = 3.2
	groove = 1.0 + 0.5 * float(mini(chain - 1, 4))
	speed = minf(speed + gain * 0.55 * groove, MAX_SPEED)
	vy += 5.0
	blast_t = 1.0 + gain * 0.012
	blast_cd = 0.5
	energy = 0.0
	_fov_punch = 16.0
	_shake = maxf(_shake, 0.25)
	_flash = 0.5
	_trip_pulse = maxf(_trip_pulse, 0.12)
	Game.sfx(&"explosion")
	_say("BLAST x%.1f" % groove, Color(0.5, 0.95, 1.0))


func _start_slam() -> void:
	slam_active = true
	slam_power = clampf(0.5 + energy / 100.0, 0.5, 1.5)
	energy = 0.0
	slam_cd = 1.2
	vy = -70.0
	_fov_punch = 10.0
	Game.sfx(&"whoosh")


func _slam_impact() -> void:
	slam_active = false
	vy = 5.0 * slam_power
	var pos := Vector3(global_position.x, DECK_Y + 0.5, global_position.z)
	var radius := 10.0 + 6.0 * slam_power
	Fx.confetti(self, pos + Vector3.UP * 0.6, 50, 1.2)
	_shake = 0.9
	_flash = 0.6
	for it in items.duplicate():
		if String(it["type"]) == "cake" and not bool(it["done"]):
			var p: Vector3 = it["pos"]
			if Vector2(p.x - pos.x, p.z - pos.z).length() <= radius:
				_crush(it)
	speed = maxf(speed, CRUISE * 0.9)
	Game.sfx(&"kaboom")
	_say("SLAM", Color(1.0, 0.7, 0.2))


func _pop(it: Dictionary) -> void:
	it["done"] = true
	var nv: Variant = it["node"]
	if is_instance_valid(nv):
		var n := nv as Node3D
		Fx.confetti(self, n.global_position, 22, 0.8)
		n.queue_free()


func _crush(it: Dictionary) -> void:
	_hit(it, 45, Color(1.0, 0.5, 0.8))
	_pop(it)
	stats["targets"] = int(stats["targets"]) + 1
	_goal("targets")


func _crash(msg: String) -> void:
	if hurt_t > 0.0:
		return
	if int(buffs["shield"]) > 0:
		buffs["shield"] = int(buffs["shield"]) - 1
		hurt_t = 0.5
		_say("SHIELD HELD", Color(1.0, 0.5, 0.85))
		Game.sfx(&"boing2")
		return
	stats["crashes"] = int(stats["crashes"]) + 1
	hurt_t = 0.8
	speed = maxf(speed * 0.55, MIN_SPEED)
	energy *= 0.5
	chain = 0
	groove = 1.0
	combo = 0
	_shake = 0.7
	vy = 8.0
	global_position -= Vector3(-sin(heading), 0.0, -cos(heading)) * 3.0
	Game.sfx(&"splat")
	_say(msg, Color(1.0, 0.4, 0.35))


func _magnet_tick(delta: float) -> void:
	if float(buffs["magnet"]) <= 0.0:
		return
	var pos := global_position
	for it in items:
		if bool(it["done"]):
			continue
		var t := String(it["type"])
		if t != "star" and t != "balloon" and t != "pickup":
			continue
		var ip: Vector3 = it["pos"]
		if absf(ip.z - pos.z) > 60.0 or ip.distance_to(pos) > 60.0:
			continue
		var np := ip.move_toward(pos + Vector3(0, 0.5, 0), 55.0 * delta)
		it["pos"] = np
		it["bx"] = np.x
		it["amp"] = 0.0
		var nd := it["node"] as Node3D
		if is_instance_valid(nd):
			nd.global_position = np


func _items_tick(delta: float) -> void:
	var pos := global_position
	for it in items:
		if bool(it["done"]):
			continue
		var ip: Vector3 = it["pos"]
		if absf(ip.z - pos.z) > 90.0:
			continue
		if String(it["type"]) == "balloon" and float(it.get("amp", 0.0)) > 0.0:
			ip.x = float(it["bx"]) + sin(_age * 1.3 + float(it["ph"])) * float(it["amp"])
			it["pos"] = ip
			var bn := it["node"] as Node3D
			if is_instance_valid(bn):
				bn.global_position = ip
		match String(it["type"]):
			"ring", "wind":
				if _prev_pos.z > ip.z and pos.z <= ip.z:
					var t := (_prev_pos.z - ip.z) / maxf(_prev_pos.z - pos.z, 0.0001)
					var cross := _prev_pos.lerp(pos, t)
					it["done"] = true
					if Vector2(cross.x - ip.x, cross.y - ip.y).length() < float(it["r"]) + 0.8:
						if String(it["type"]) == "wind":
							speed = minf(speed + 22.0, MAX_SPEED)
							blast_t = maxf(blast_t, 1.0)          # a blast ring is a blast: walls and the piñata break
							_fov_punch = 12.0
							_say("WIND", Color(0.6, 1.0, 0.6))
							_hit(it, 40, Color(0.6, 1.0, 0.6))
						else:
							stats["rings"] = int(stats["rings"]) + 1
							_hit(it, 60, Color(0.4, 0.9, 1.0))
							_goal("rings")
						energy = minf(energy + 8.0, 100.0)
					else:
						combo = 0
			"balloon":
				if pos.distance_to(ip) < float(it["r"]):
					_hit(it, 35, Color(1, 1, 1))
					_pop(it)
					stats["balloons"] = int(stats["balloons"]) + 1
					_goal("balloons")
			"star":
				if pos.distance_to(ip) < float(it["r"]):
					_hit(it, 15, Color(1.0, 0.9, 0.3))
					_pop(it)
					stats["stars"] = int(stats["stars"]) + 1
					_goal("stars")
			"pickup":
				if pos.distance_to(ip) < float(it["r"]):
					_take_pickup(it)
			"wall":
				if _prev_pos.z > ip.z and pos.z <= ip.z:
					var t2 := (_prev_pos.z - ip.z) / maxf(_prev_pos.z - pos.z, 0.0001)
					var c2 := _prev_pos.lerp(pos, t2)
					if absf(c2.x - ip.x) < float(it["r"]) + 0.8 and c2.y - DECK_Y < 17.0:
						it["done"] = true
						if blast_t > 0.0:
							stats["walls"] = int(stats["walls"]) + 1
							_hit(it, 90, Color(1.0, 0.85, 0.3))
							var wn := it["node"] as Node3D
							if is_instance_valid(wn):
								Fx.confetti(self, wn.global_position + Vector3(0, 8, 0), 60, 1.4)
								wn.queue_free()
							_shake = 0.4
							Game.sfx(&"explosion")
							_goal("walls")
						else:
							_crash("WALL: BLAST THROUGH")
			"pillar":
				if alt < 47.0 and Vector2(pos.x - ip.x, pos.z - ip.z).length() < float(it["r"]) + 1.0:
					_crash("TOWER")
			"bumper":
				it["cool"] = maxf(float(it["cool"]) - delta, 0.0)
				var bn := it["node"] as Node3D
				if is_instance_valid(bn):
					bn.scale = bn.scale.lerp(Vector3.ONE, 1.0 - exp(-8.0 * delta))
				if float(it["cool"]) <= 0.0 and pos.distance_to(ip) < float(it["r"]):
					it["cool"] = 0.45
					var dv := pos - ip
					if dv.length() < 0.1:
						dv = Vector3(1, 0, 0)
					dv = dv.normalized()
					_kick = Vector3(dv.x * 26.0, dv.y * 14.0, 0.0)
					if is_instance_valid(bn):
						bn.scale = Vector3.ONE * 1.5
					stats["bumpers"] = int(stats["bumpers"]) + 1
					_hit(it, 140, Color(1.0, 0.4, 0.8))
					_shake = maxf(_shake, 0.25)
					Fx.confetti(self, ip, 14, 0.7)
					Game.sfx(&"boing2")
			"sling":
				for rr in it["rings"]:
					if is_instance_valid(rr):
						(rr as Node3D).rotate_y(delta * 1.4)
				if bool(it["used"]):
					continue
				var sd := ip - pos
				var sdist := sd.length()
				var dzs := pos.z - ip.z
				if sdist < float(it["r"]) and dzs > -8.0:
					if not bool(it["in"]):
						it["in"] = true
						Game.sfx(&"stretch")
					var snear := 1.0 - clampf(sdist / float(it["r"]), 0.0, 1.0)
					if sdist > 7.0:
						var pull := sd.normalized() * (10.0 + 26.0 * snear) * delta
						global_position += Vector3(pull.x, 0.0, 0.0)
						alt += pull.y
					speed = minf(speed + (8.0 + 30.0 * snear) * delta, MAX_SPEED)
					_fov_punch = maxf(_fov_punch, 3.0 + 6.0 * snear)
				elif bool(it["in"]) and dzs <= -8.0:
					it["used"] = true
					speed = minf(speed + 28.0, MAX_SPEED)
					blast_t = maxf(blast_t, 1.3)
					_fov_punch = 14.0
					_shake = maxf(_shake, 0.3)
					_flash = maxf(_flash, 0.4)
					stats["slings"] = int(stats["slings"]) + 1
					_hit(it, 220, Color(0.6, 0.95, 1.0))
					Game.sfx(&"snap")
					Game.sfx(&"whoosh")
			"storm":
				if pos.distance_to(ip) < float(it["r"]):
					it["done"] = true
					_crash("STORM")
			"cake":
				if alt < 8.0 and Vector2(pos.x - ip.x, pos.z - ip.z).length() < 3.6:
					_crush(it)          # fly low over them
			"pinata":
				it["cool"] = maxf(float(it["cool"]) - delta, 0.0)
				var pn := it["node"] as Node3D
				if is_instance_valid(pn):
					pn.rotation.y += delta * 0.8
					pn.global_position = ip + Vector3(sin(_age * 0.9) * 6.0, sin(_age * 1.3) * 3.0, 0.0)
					it["pos"] = pn.global_position
				if pos.distance_to(ip) < 80.0 and energy < 30.0 and blast_t <= 0.0:
					energy = 30.0          # the piñata always arrives with enough in the bar for one blast
					if not it.has("said"):
						it["said"] = true
						_say("BLAST NOW", Color(1.0, 0.85, 0.4))
				if pos.distance_to(ip) < float(it["r"]) and float(it["cool"]) <= 0.0:
					it["cool"] = 1.0
					if speed >= 46.0 or blast_t > 0.0:
						_pinata_hit(it)
					else:
						_say("BLAST THROUGH IT", Color(1.0, 0.6, 0.8))
						Game.sfx(&"boing2")
						speed = maxf(speed * 0.8, MIN_SPEED)
						_shake = 0.3
	# floating numbers
	for p in _pops:
		p[3] = float(p[3]) + delta
	while not _pops.is_empty() and float(_pops[0][3]) > 1.1:
		_pops.pop_front()


func _pinata_hit(it: Dictionary) -> void:
	it["hp"] = int(it["hp"]) - 1
	stats["pinata"] = int(stats["pinata"]) + 1
	_shake = 0.8
	_flash = 0.5
	_fov_punch = 14.0
	Fx.confetti(self, global_position + Vector3(0, 2, -6), 70, 1.5)
	Game.sfx(&"kaboom")
	if int(it["hp"]) > 0:
		_say("HIT  %d MORE" % int(it["hp"]), Color(1.0, 0.6, 0.8))
		_hit(it, 300, Color(1.0, 0.6, 0.8))
		return
	_say("PIÑATA!", Color(1.0, 0.85, 0.4))
	rig._cheer("PIÑATA!", Color(1.0, 0.85, 0.4), 1.8)
	_hit(it, 1500, Color(1.0, 0.85, 0.4))
	score += 1500
	energy = 100.0
	buffs["magnet"] = 7.0
	var center: Vector3 = it["pos"]
	_pop(it)
	for i in 36:
		var a := float(i) * 2.399
		var rr := 5.0 + float(i % 6) * 2.5
		_add_star(center + Vector3(cos(a) * rr, sin(a * 1.3) * rr * 0.6, sin(a) * rr))
	trip_lvl = minf(trip_lvl + 0.15, 1.0)
	_trip_pulse = 0.3


func _take_pickup(it: Dictionary) -> void:
	var kind := String(it["kind"])
	stats["pickups"] = int(stats["pickups"]) + 1
	_hit(it, 80, it["col"])
	_pop(it)
	match kind:
		"magnet":
			buffs["magnet"] = 9.0
			_say("MAGNET", Color(1.0, 0.4, 0.4))
		"slow":
			buffs["slow"] = 7.0
			_say("SLOW TIME", Color(0.5, 0.85, 1.0))
		"x2":
			buffs["x2"] = 10.0
			_say("DOUBLE POINTS", Color(1.0, 0.85, 0.2))
		"shield":
			buffs["shield"] = int(buffs["shield"]) + 1
			_say("SHIELD", Color(1.0, 0.5, 0.85))
		_:
			energy = 100.0
			speed = minf(speed + 25.0, MAX_SPEED)
			blast_t = 1.5
			_fov_punch = 14.0
			_say("OVERDRIVE", Color(1.0, 0.6, 0.2))
	_goal("pickups")
	Game.sfx(&"levelup")


func _cleanup_behind() -> void:
	for i in range(items.size() - 1, -1, -1):
		var ip: Vector3 = items[i]["pos"]
		if ip.z > global_position.z + 50.0:
			var n: Variant = items[i]["node"]
			if is_instance_valid(n):
				(n as Node3D).queue_free()
			items.remove_at(i)
	for i in range(_chunks.size() - 1, -1, -1):
		if float(_chunks[i]["z"]) > global_position.z + 120.0:
			var cn: Variant = _chunks[i]["n"]
			if is_instance_valid(cn):
				(cn as Node).queue_free()
			_chunks.remove_at(i)


func _finish() -> void:
	if _done:
		return
	_done = true
	# the trip goes back to whatever the journey is doing
	_restore_sky()
	if rig._journey == null or rig._journey.phase == DhJourney.Phase.CALM:
		rig.journey_post("alpine", 0.0, false, 0.3)
	var res := {"score": score, "dist": _start_z - global_position.z, "stats": stats, "goals": goals, "cleared": _clear_t >= 0.0, "best_combo": best_combo}
	rig.sky_end(res)
	queue_free()


# --------------------------------------------------------------------------
# The trip: it builds the longer you are up here, shows in the clouds, the sky colours and the full-screen pass, and goes back down with the dive
# --------------------------------------------------------------------------
func _trip_tick(delta: float) -> void:
	var goal := 0.0
	if phase == 1:
		# one rising arc: hints at first, then more, fuller as the combo builds and the energy fills, with a surge on the big moments
		var base := lerpf(0.12, _trip_peak, smoothstep(0.0, 0.85, timer / duration))
		var ex := 0.6 * clampf(float(combo) / 12.0, 0.0, 1.0) + 0.2 * clampf(energy / 100.0, 0.0, 1.0) + 0.2 * clampf((speed - CRUISE) / 50.0, 0.0, 1.0)
		_trip_pulse = maxf(_trip_pulse - delta * 0.08, 0.0)
		goal = minf(base * (0.7 + 0.3 * ex) + _trip_pulse, 1.0)
	elif phase == 2:
		goal = 0.1
	if rig._journey != null and rig._journey.phase != DhJourney.Phase.CALM:
		goal = maxf(goal, rig._journey.onset_k() * 0.6)
	trip_lvl = move_toward(trip_lvl, goal, delta * 0.10)
	if phase != 0:
		rig.journey_post(_flick_world, clampf(0.15 + 0.85 * trip_lvl, 0.0, 1.0), true, 0.3 + 0.8 * trip_lvl)
		rig.trip = maxf(rig.trip, trip_lvl * 0.9)
	if _deck_mat != null:
		_deck_mat.set_shader_parameter("trip", trip_lvl)


## The sky flickers into other worlds, more and more of the time as the trip comes on.
func _flicker_tick(delta: float) -> void:
	if rig._lvl == null or phase != 1:
		return
	_flick_t -= delta
	if _flick_t > 0.0:
		return
	_flick_t = 0.12
	# the sky's colours lean toward the world of the wave, a little more as the trip builds, breathing slowly: the same palette all the way, no jumping about
	ThemeFX.blend_env(rig._lvl, _flick_world, trip_lvl * 0.9 * (0.78 + 0.22 * sin(_age * 0.8)))


func _restore_sky() -> void:
	if rig._lvl != null:
		ThemeFX.apply_part(rig._lvl, rig, rig._jw, "sky", 1.0, true, true, false)
	_flick_back = 0.0


# --------------------------------------------------------------------------
# Camera + HUD
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _done:
		return
	rotation = Vector3(0.0, heading, 0.0)
	var climb := clampf(atan2(vy, maxf(speed, 1.0)) * 0.9, -0.7, 0.55)
	cam.rotation = Vector3(lerpf(cam.rotation.x, climb, 1.0 - exp(-6.0 * delta)), 0.0, lerpf(cam.rotation.z, -steer * 0.3, 1.0 - exp(-6.0 * delta)))
	_fov_punch = maxf(_fov_punch - 30.0 * delta, 0.0)
	cam.fov = 80.0 + (speed - CRUISE) * 0.18 + _fov_punch
	_shake = maxf(_shake - 1.5 * delta, 0.0)
	cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.35
	_flash = maxf(_flash - 2.0 * delta, 0.0)
	if is_instance_valid(_deck):
		_deck.global_position = Vector3(global_position.x, DECK_Y, global_position.z)
	_puff_mat.albedo_color = Color.from_hsv(fposmod(_age * 0.05, 1.0), clampf(trip_lvl * 0.5, 0.0, 0.5), 1.0)
	_white = clampf(1.0 - (alt - 2.0) / 22.0, 0.0, 1.0)
	if alt < -20.0:
		_white = 1.0
	for f in _feed:
		f[2] = float(f[2]) + delta
	while not _feed.is_empty() and float(_feed[0][2]) > 2.2:
		_feed.pop_front()
	_hud.size = get_viewport().get_visible_rect().size
	_hud.queue_redraw()


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	_hud.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, Color(0, 0, 0, 0.85))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _ring_at(world_pos: Vector3, rad: float, col: Color, width: float) -> void:
	if cam.is_position_behind(world_pos):
		return
	var sp := cam.unproject_position(world_pos)
	_hud.draw_arc(sp, rad, 0.0, TAU, 28, col, width)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := clampf(minf(s.x, s.y * 1.6) / 900.0, 0.6, 1.6)
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.25 * hurt_t))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.97, 1.0, 0.3 * _flash))
	if _white > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, _white))
	if _hint_big and _age < 9.0:
		var hl := ["FLYING WITH YOUR EYES", "look LEFT / MIDDLE / RIGHT: lock on and fly to it", "look STRAIGHT AHEAD for a moment: BLAST", "bumpers bounce you, glowing orbs sling you on"]
		var hy := s.y * 0.33
		var ha := clampf(minf(9.0 - _age, 1.0), 0.0, 1.0)
		var dark := phase == 0 or _white > 0.5
		for hi in hl.size():
			var ht: String = hl[hi]
			var hs := int((40.0 if hi == 0 else 26.0) * k)
			var hc := Color(0.1, 0.15, 0.35, ha) if dark else Color(1, 1, 1, ha)
			_hud.draw_string(font, Vector2(s.x * 0.5 - font.get_string_size(ht, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x * 0.5, hy), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, hc)
			hy += float(hs) * 1.5
	if phase != 1:
		return
	# time left, thin, across the top
	var bw := minf(s.x * 0.6, 640.0 * k)
	var bx := s.x * 0.5 - bw * 0.5
	_hud.draw_rect(Rect2(bx, 8.0 * k, bw, 6.0 * k), Color(0, 0, 0, 0.35))
	_hud.draw_rect(Rect2(bx, 8.0 * k, bw * clampf(1.0 - timer / duration, 0.0, 1.0), 6.0 * k), Color(1.0, 0.9, 0.5, 0.9))
	# the three goals
	var gy := 44.0 * k
	for g in goals:
		var gd: Dictionary = g
		var txt := "%s  %d / %d" % [String(gd["label"]), int(gd["have"]), int(gd["need"])]
		_text(font, Vector2(24.0 * k, gy), txt, int(22.0 * k), Color(0.6, 1.0, 0.7) if bool(gd["done"]) else Color(1, 1, 1, 0.92))
		gy += 28.0 * k
	_text(font, Vector2(24.0 * k, gy + 8.0 * k), "%d" % score, int(30.0 * k), Color(1.0, 0.9, 0.5))
	# the combo: a big number and a bar that runs down
	if combo >= 2:
		var ct := "x%d" % combo
		var csz := int((34.0 + minf(float(combo), 20.0)) * k)
		var cw := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
		_text(font, Vector2(s.x * 0.5 - cw * 0.5, 66.0 * k), ct, csz, Color.from_hsv(fposmod(float(combo) * 0.07, 1.0), 0.6, 1.0))
		var frac := clampf(combo_t / (4.5 if float(buffs["slow"]) > 0.0 else 3.0), 0.0, 1.0)
		_hud.draw_rect(Rect2(s.x * 0.5 - 60.0 * k, 74.0 * k, 120.0 * k * frac, 5.0 * k), Color(1.0, 0.9, 0.5, 0.9))
	# power-ups that are running
	var by := 44.0 * k
	var names := {"magnet": ["MAGNET", Color(1.0, 0.4, 0.4)], "slow": ["SLOW", Color(0.5, 0.85, 1.0)], "x2": ["x2", Color(1.0, 0.85, 0.2)]}
	for kname in names:
		if float(buffs[kname]) > 0.0:
			var nm: Array = names[kname]
			var bt := "%s %d" % [String(nm[0]), int(ceil(float(buffs[kname])))]
			_text(font, Vector2(s.x - 150.0 * k, by), bt, int(22.0 * k), nm[1])
			by += 28.0 * k
	if int(buffs["shield"]) > 0:
		_text(font, Vector2(s.x - 150.0 * k, by), "SHIELD %d" % int(buffs["shield"]), int(22.0 * k), Color(1.0, 0.5, 0.85))
	# what can be looked at, and what is locked
	for cd in [cand_l, cand_m, cand_r]:
		var c: Dictionary = cd
		if not c.is_empty() and not is_same(c, lock):
			_ring_at(c["pos"], 26.0 * k, Color(1, 1, 1, 0.35), 2.0 * k)
	if not lock.is_empty():
		var pulse := 1.0 + 0.12 * sin(_age * 9.0)
		_ring_at(lock["pos"], 34.0 * k * pulse, Color(0.5, 1.0, 0.65, 0.95), 4.0 * k)
	# floating numbers from what was hit
	for p in _pops:
		var wp: Vector3 = p[1]
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var age := float(p[3])
		var pc: Color = p[2]
		_text(font, Vector2(sp.x - 24.0 * k, sp.y - 30.0 * k * age - 10.0 * k), String(p[0]), int(24.0 * k), Color(pc.r, pc.g, pc.b, clampf(1.2 - age, 0.0, 1.0)))
	# energy (bottom middle), speed
	var w := minf(s.x * 0.4, 380.0 * k)
	var x0 := s.x * 0.5 - w * 0.5
	var y0 := s.y - 54.0 * k
	_hud.draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 20.0 * k + 6), Color(0, 0, 0, 0.6))
	var ec := Color(0.4, 0.7, 1.0).lerp(Color(1.0, 0.85, 0.3), energy / 100.0)
	_hud.draw_rect(Rect2(x0, y0, w * energy / 100.0, 20.0 * k), ec)
	if energy >= 50.0 and not lock.is_empty():
		_text(font, Vector2(s.x * 0.5 - 90.0 * k, y0 - 8.0 * k), "LOOK AHEAD: BLAST", int(22.0 * k), Color(1.0, 0.95, 0.5, 0.6 + 0.4 * sin(_age * 12.0)))
	_text(font, Vector2(s.x - 190.0 * k, s.y - 24.0 * k), "%d km/h" % int(speed * 3.6), int(22.0 * k), Color(1, 1, 1, 0.85))
	# where the eyes are read (left, middle, right) and where the head is: so it can be seen that it is working
	var ez := rig.eye_now()
	var zone := 0 if absf(ez) < 0.5 else (1 if ez > 0.0 else -1)
	for zi in 3:
		var zc := Vector2(s.x * 0.5 + float(zi - 1) * 30.0 * k, y0 - 32.0 * k)
		_hud.draw_circle(zc, 7.0 * k, Color(0.5, 1.0, 0.65, 0.95) if zone == zi - 1 else Color(1, 1, 1, 0.25))
	# the words that come and go
	var fy := s.y * 0.30
	for f in _feed:
		var a := clampf(1.0 - float(f[2]) / 2.2, 0.0, 1.0)
		var c2: Color = f[1]
		var tx: String = f[0]
		_text(font, Vector2(s.x * 0.5 - font.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30.0 * k)).x * 0.5, fy), tx, int(30.0 * k), Color(c2.r, c2.g, c2.b, a))
		fy += 36.0 * k
	if _age < 14.0:
		var t := "look left / middle / right: lock on     hold the look in the middle: blast"
		_text(font, Vector2(s.x * 0.5 - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17.0 * k)).x * 0.5, s.y - 82.0 * k), t, int(17.0 * k), Color(1, 1, 1, 0.9))
