class_name FlightRig
extends Node3D
## Nod-energy flight prototype ("lift and rise, float, arise, slam down").
##
##   chin DOWN (held)        gather energy, shed speed        (the dip before the surge)
##   chin snaps UP           BLAST: stored energy becomes speed + a few seconds of smashing through walls
##   chin UP (held)          float: climb, trade a little speed for height
##   chin snaps DOWN, high   SLAM: dive and crush everything on the ground around the impact
##   lean / head turn        steer
##   bob at a steady beat    GROOVE multiplier (blasts chained within ~3 s)
##
## Input comes from GazeProvider.nod_state() (head pitch + how fast it is changing) and peek_offset() (steer);
## W/S or the arrow keys stand in for the chin when there is no camera.

const CRUISE := 22.0
const MAX_SPEED := 90.0
const MIN_SPEED := 9.0
const GROUND := 1.5
const CEILING := 90.0

var player: PlayerController
var cam: Camera3D
var heading: float = 0.0
var speed: float = CRUISE
var alt: float = 38.0
var vy: float = 0.0
var energy: float = 0.0
var groove: float = 1.0
var chain: int = 0
var chain_t: float = 0.0
var score: int = 0
var rings_passed: int = 0
var walls_broken: int = 0
var targets_crushed: int = 0
var crashes: int = 0
var slams: int = 0
var blasts: int = 0
var blast_t: float = 0.0
var blast_cd: float = 0.0
var slam_active: bool = false
var slam_power: float = 0.0
var slam_cd: float = 0.0
var hurt_t: float = 0.0
var nod_p: float = 0.0
var nod_v: float = 0.0
var steer: float = 0.0
var items: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _next_z: float = -90.0
var _decor_z: float = 30.0
var _prev_pos: Vector3 = Vector3.ZERO
var _hud: Control
var _ground: MeshInstance3D
var _shake: float = 0.0
var _fov_punch: float = 0.0
var _age: float = 0.0
var _flash: float = 0.0


func setup(p_player: PlayerController) -> void:
	name = "FlightRig"
	player = p_player
	_rng.seed = 12345
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.1
	cam.far = 700.0
	add_child(cam)
	cam.make_current()
	global_position = Vector3(0.0, alt, 0.0)
	_prev_pos = global_position
	_build_ground()
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	while _next_z > -520.0:
		_spawn_chunk(_next_z)
		_next_z -= _rng.randf_range(48.0, 72.0)


func _build_ground() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 1, 1))
	img.set_pixel(1, 1, Color(1, 1, 1))
	img.set_pixel(1, 0, Color(0.82, 0.82, 0.82))
	img.set_pixel(0, 1, Color(0.82, 0.82, 0.82))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.05
	m.albedo_color = Color(0.45, 0.72, 0.5)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
	_ground = MeshInstance3D.new()
	_ground.mesh = pm
	_ground.material_override = m
	_ground.top_level = true
	add_child(_ground)


# --------------------------------------------------------------------------
# Course
# --------------------------------------------------------------------------
func _node_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	get_parent().add_child(n)
	n.global_position = pos
	return n


func add_ring(pos: Vector3, r: float = 6.0) -> void:
	var n := _node_at(pos)
	Roster.mi(n, Roster.torus(r - 1.0, r + 0.4), Vector3.ZERO, Color(0.3, 0.9, 1.0), Vector3(90, 0, 0), 1.6)
	items.append({"type": "ring", "node": n, "pos": pos, "r": r, "done": false})


func add_wall(pos: Vector3) -> void:
	var p := Vector3(pos.x, 0.0, pos.z)
	var n := _node_at(p)
	Roster.mi(n, Roster.box(Vector3(18, 14, 1.4)), Vector3(0, 7, 0), Color(0.95, 0.4, 0.3), Vector3.ZERO, 0.5)
	Roster.mi(n, Roster.box(Vector3(18.4, 1.0, 1.8)), Vector3(0, 14.2, 0), Color(1.0, 0.85, 0.2), Vector3.ZERO, 1.2)
	items.append({"type": "wall", "node": n, "pos": p, "r": 9.0, "done": false})


func add_pillar(pos: Vector3) -> void:
	var p := Vector3(pos.x, 0.0, pos.z)
	var n := _node_at(p)
	Roster.mi(n, Roster.cyl(1.4, 1.6, 40.0), Vector3(0, 20, 0), Color(0.55, 0.5, 0.6))
	items.append({"type": "pillar", "node": n, "pos": p, "r": 2.6, "done": false})


func add_target(pos: Vector3) -> void:
	var p := Vector3(pos.x, 0.0, pos.z)
	var n := _node_at(p)
	Roster.mi(n, Roster.box(Vector3(2.4, 2.4, 2.4)), Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.2), Vector3.ZERO, 0.8)
	Roster.mi(n, Roster.torus(1.4, 1.7), Vector3(0, 0.1, 0), Color(1.0, 0.4, 0.2), Vector3.ZERO, 1.2)
	items.append({"type": "target", "node": n, "pos": p, "r": 2.0, "done": false})


func _spawn_chunk(z: float) -> void:
	var cx := sin(z * 0.012) * 45.0
	var roll := _rng.randf()
	if roll < 0.42:
		add_ring(Vector3(cx + _rng.randf_range(-12.0, 12.0), _rng.randf_range(10.0, 48.0), z))
	elif roll < 0.60:
		add_wall(Vector3(cx, 0.0, z))
	elif roll < 0.78:
		for i in 3:
			add_pillar(Vector3(cx + _rng.randf_range(-26.0, 26.0), 0.0, z - float(i) * 10.0))
	else:
		for i in 3:
			add_target(Vector3(cx + _rng.randf_range(-16.0, 16.0), 0.0, z - float(i) * 9.0))


func _spawn_decor(z: float) -> void:
	var cx := sin(z * 0.012) * 45.0
	for side in [-1.0, 1.0]:
		var n := _node_at(Vector3(cx + side * _rng.randf_range(48.0, 85.0), 0.0, z))
		var h := _rng.randf_range(6.0, 24.0)
		Roster.mi(n, Roster.cyl(0.8, 1.0, h), Vector3(0, h * 0.5, 0), Color.from_hsv(_rng.randf(), 0.35, 0.9))
		Roster.mi(n, Roster.sphere(2.2), Vector3(0, h + 1.0, 0), Color.from_hsv(_rng.randf(), 0.5, 1.0), Vector3.ZERO, 0.4)
		items.append({"type": "decor", "node": n, "pos": n.global_position, "r": 0.0, "done": true})


# --------------------------------------------------------------------------
# Flight
# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_age += delta
	var ns := GazeProvider.nod_state(delta)
	nod_p = ns.x
	nod_v = ns.y
	var pk := GazeProvider.peek_offset(delta)
	steer = clampf(pk.x / 1.8, -1.0, 1.0)
	blast_cd = maxf(blast_cd - delta, 0.0)
	slam_cd = maxf(slam_cd - delta, 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	chain_t -= delta
	if chain_t <= 0.0 and chain > 0:
		chain = 0
		groove = 1.0

	var gathering := false
	if slam_active:
		vy = -75.0
		speed = move_toward(speed, 30.0, 25.0 * delta)
	else:
		if nod_p < -0.10:
			var rate := clampf((-nod_p - 0.10) / 0.22, 0.0, 1.0)
			energy = minf(energy + 30.0 * rate * delta, 100.0)
			speed = maxf(speed - 9.0 * rate * delta, MIN_SPEED)
			vy = lerpf(vy, -1.0, 1.0 - exp(-2.0 * delta))
			gathering = true
		elif nod_p > 0.10:
			var lift := clampf((nod_p - 0.10) / 0.22, 0.0, 1.0)
			vy = lerpf(vy, 11.0 * lift, 1.0 - exp(-3.0 * delta))
			speed = maxf(speed - 2.5 * lift * delta, MIN_SPEED)
		else:
			vy = lerpf(vy, -2.5, 1.0 - exp(-1.5 * delta))
		if not gathering and blast_t <= 0.0:
			speed = move_toward(speed, CRUISE, 4.0 * delta)
		if nod_v > 1.1 and energy > 12.0 and blast_cd <= 0.0:
			_blast()
		elif nod_v < -1.6 and alt > 6.0 and slam_cd <= 0.0:
			_start_slam()
	if blast_t > 0.0:
		blast_t -= delta

	heading -= steer * (0.55 + speed / 70.0) * delta
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	_prev_pos = global_position
	var np := global_position + fwd * speed * delta
	alt = clampf(alt + vy * delta, 0.0, CEILING)
	if alt >= CEILING:
		vy = minf(vy, 0.0)
	if alt <= GROUND:
		if slam_active:
			_slam_impact()
		alt = GROUND
		vy = maxf(vy, 0.0)
	np.y = alt
	np.x = clampf(np.x, -260.0, 260.0)
	global_position = np

	_process_items()
	while _next_z > global_position.z - 520.0:
		_spawn_chunk(_next_z)
		_next_z -= _rng.randf_range(48.0, 72.0)
	while _decor_z > global_position.z - 520.0:
		_spawn_decor(_decor_z)
		_decor_z -= 32.0
	_cleanup_behind()


func _blast() -> void:
	var gain := energy
	chain = (chain + 1) if chain_t > 0.0 else 1
	chain_t = 3.2
	groove = 1.0 + 0.5 * float(mini(chain - 1, 4))
	speed = minf(speed + gain * 0.55 * groove, MAX_SPEED)
	vy += 5.0
	blast_t = 0.9 + gain * 0.012
	blast_cd = 0.5
	energy = 0.0
	blasts += 1
	_fov_punch = 14.0
	_shake = maxf(_shake, 0.25)
	_flash = 0.5
	Game.sfx(&"boom")
	Game.popup("BLAST x%.1f" % groove, global_position + _fwd() * 8.0, Color(0.5, 0.95, 1.0), 1.3)


func _start_slam() -> void:
	slam_active = true
	slam_power = clampf(0.5 + energy / 100.0, 0.5, 1.5)
	energy = 0.0
	slam_cd = 1.2
	vy = -75.0
	_fov_punch = 10.0
	Game.sfx(&"whoosh")


func _slam_impact() -> void:
	slam_active = false
	slams += 1
	vy = 4.0 * slam_power
	var pos := Vector3(global_position.x, 0.2, global_position.z)
	var radius := 8.0 + 6.0 * slam_power
	Fx.shockwave(self, pos, radius, 28.0 * slam_power, 40.0 * slam_power, false, true, &"slam", null, Color(1.0, 0.6, 0.2, 0.5))
	Fx.confetti(self, pos + Vector3.UP * 0.6, 50, 1.2)
	_shake = 0.9
	_flash = 0.6
	for it in items.duplicate():
		if it["type"] == "target" and not it["done"]:
			var p: Vector3 = it["pos"]
			if Vector2(p.x - pos.x, p.z - pos.z).length() <= radius:
				_crush(it)
	speed = maxf(speed, CRUISE * 0.9)
	Game.popup("SLAM!", pos + Vector3.UP * 3.0, Color(1.0, 0.7, 0.2), 1.6)


func _crush(it: Dictionary) -> void:
	it["done"] = true
	targets_crushed += 1
	score += int(25.0 * groove)
	var nv: Variant = it["node"]
	if is_instance_valid(nv):
		var n := nv as Node3D
		Fx.confetti(n, n.global_position + Vector3.UP, 24, 0.9)
		n.queue_free()
	energy = minf(energy + 8.0, 100.0)


func _crash(msg: String) -> void:
	if hurt_t > 0.0:
		return
	crashes += 1
	hurt_t = 0.8
	speed = maxf(speed * 0.45, MIN_SPEED)
	energy *= 0.5
	chain = 0
	groove = 1.0
	_shake = 0.7
	vy = 6.0
	global_position -= _fwd() * 3.0
	Game.sfx(&"hurt")
	Game.popup(msg, global_position + _fwd() * 6.0, Color(1.0, 0.4, 0.35), 1.2)


func _fwd() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _process_items() -> void:
	var pos := global_position
	for it in items:
		if it["done"]:
			continue
		var ip: Vector3 = it["pos"]
		match String(it["type"]):
			"ring":
				if _prev_pos.z > ip.z and pos.z <= ip.z:
					var t := (_prev_pos.z - ip.z) / maxf(_prev_pos.z - pos.z, 0.0001)
					var cross := _prev_pos.lerp(pos, t)
					it["done"] = true
					if Vector2(cross.x - ip.x, cross.y - ip.y).length() < float(it["r"]) - 0.6:
						rings_passed += 1
						score += int(10.0 * groove)
						energy = minf(energy + 10.0, 100.0)
						Game.sfx(&"coin")
						Game.popup("+%d" % int(10.0 * groove), ip, Color(0.5, 0.95, 1.0), 0.9)
					else:
						chain = 0
						groove = 1.0
			"wall":
				if _prev_pos.z > ip.z and pos.z <= ip.z:
					var t2 := (_prev_pos.z - ip.z) / maxf(_prev_pos.z - pos.z, 0.0001)
					var c2 := _prev_pos.lerp(pos, t2)
					if absf(c2.x - ip.x) < float(it["r"]) + 0.8 and c2.y < 14.5:
						it["done"] = true
						if blast_t > 0.0:
							walls_broken += 1
							score += int(50.0 * groove)
							var wv: Variant = it["node"]
							if is_instance_valid(wv):
								var wn := wv as Node3D
								Fx.confetti(wn, wn.global_position + Vector3(0, 7, 0), 60, 1.4)
								wn.queue_free()
							_shake = 0.4
							Game.sfx(&"boom")
							Game.popup("SMASH!", ip + Vector3.UP * 8.0, Color(1.0, 0.85, 0.3), 1.4)
						else:
							_crash("WALL! need a BLAST")
			"pillar":
				if alt < 40.0 and Vector2(pos.x - ip.x, pos.z - ip.z).length() < float(it["r"]):
					_crash("PILLAR!")
			"target":
				if blast_t > 0.0 and alt < 5.0 and Vector2(pos.x - ip.x, pos.z - ip.z).length() < 3.0:
					_crush(it)


func _free_node(it: Dictionary) -> void:
	var n: Variant = it["node"]
	if is_instance_valid(n):
		(n as Node3D).queue_free()


func _cleanup_behind() -> void:
	for i in range(items.size() - 1, -1, -1):
		var ip: Vector3 = items[i]["pos"]
		if ip.z > global_position.z + 40.0:
			_free_node(items[i])
			items.remove_at(i)


func cleanup() -> void:
	for it in items:
		_free_node(it)
	items.clear()


# --------------------------------------------------------------------------
# Camera + HUD
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	rotation = Vector3(0.0, heading, 0.0)
	var climb := clampf(atan2(vy, maxf(speed, 1.0)) * 0.9, -0.6, 0.5)
	cam.rotation = Vector3(lerpf(cam.rotation.x, climb, 1.0 - exp(-6.0 * delta)), 0.0, lerpf(cam.rotation.z, -steer * 0.35, 1.0 - exp(-6.0 * delta)))
	_fov_punch = maxf(_fov_punch - 30.0 * delta, 0.0)
	cam.fov = 78.0 + (speed - CRUISE) * 0.22 + _fov_punch
	_shake = maxf(_shake - 1.5 * delta, 0.0)
	cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.35
	_flash = maxf(_flash - 2.0 * delta, 0.0)
	_ground.global_position = Vector3(global_position.x, 0.0, global_position.z)
	_hud.size = get_viewport().get_visible_rect().size
	_hud.queue_redraw()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.25 * hurt_t))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.95, 1.0, 0.25 * _flash))
	# energy bar
	var w := minf(s.x * 0.5, 420.0)
	var x0 := s.x * 0.5 - w * 0.5
	var y0 := s.y - 70.0
	_hud.draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 26), Color(0, 0, 0, 0.7))
	var ec := Color(0.4, 0.7, 1.0).lerp(Color(1.0, 0.85, 0.3), energy / 100.0)
	_hud.draw_rect(Rect2(x0, y0, w * energy / 100.0, 20), ec)
	_text(font, Vector2(x0, y0 - 10), "ENERGY %d" % int(energy), 20, ec)
	if energy > 12.0:
		_text(font, Vector2(x0 + w * 0.5 - 130, y0 + 44), "SNAP CHIN UP = BLAST", 22, Color(0.7, 1.0, 1.0))
	# groove + speed
	_text(font, Vector2(24, s.y - 66), "SPEED %d" % int(speed), 30, Color(1, 1, 1))
	_text(font, Vector2(24, s.y - 30), "GROOVE x%.1f" % groove, 24, Color(1.0, 0.85, 0.3) if chain > 0 else Color(1, 1, 1, 0.6))
	_text(font, Vector2(s.x - 190, s.y - 30), "ALT %d m" % int(alt), 24, Color(1, 1, 1, 0.85))
	# score line
	_text(font, Vector2(24, 40), "SCORE %d    rings %d   walls %d   crushed %d" % [score, rings_passed, walls_broken, targets_crushed], 24, Color(1, 1, 1))
	if blast_t > 0.0:
		_text(font, Vector2(s.x * 0.5 - 150, 110), "BLASTING: walls will shatter", 26, Color(0.6, 1.0, 1.0))
	# chin gauge (left, vertical): zones for gather / float, marker for where your chin is, arrow for how fast it moves
	var gx := 34.0
	var gy := s.y * 0.5 - 110.0
	var gh := 220.0
	_hud.draw_rect(Rect2(gx, gy, 22, gh), Color(0, 0, 0, 0.55))
	var mid := gy + gh * 0.5
	var zone := gh * (0.10 / 0.40) * 0.5
	_hud.draw_rect(Rect2(gx, mid + zone, 22, gh * 0.5 - zone), Color(0.3, 0.55, 1.0, 0.35))   # chin down: gather
	_hud.draw_rect(Rect2(gx, gy, 22, gh * 0.5 - zone), Color(0.3, 1.0, 0.5, 0.30))              # chin up: float
	var my := mid - clampf(nod_p / 0.40, -1.0, 1.0) * gh * 0.5
	_hud.draw_circle(Vector2(gx + 11, my), 11.0, Color(1.0, 0.85, 0.3))
	var vy_arrow := clampf(nod_v / 3.0, -1.0, 1.0) * 40.0
	_hud.draw_line(Vector2(gx + 38, my), Vector2(gx + 38, my - vy_arrow), Color(1, 1, 1, 0.8), 4.0)
	_text(font, Vector2(gx - 6, gy - 10), "CHIN", 18, Color(1, 1, 1, 0.9))
	_text(font, Vector2(gx + 28, gy + 16), "float", 16, Color(0.5, 1.0, 0.6))
	_text(font, Vector2(gx + 28, gy + gh - 6), "gather", 16, Color(0.5, 0.7, 1.0))
	var cmsg := GazeProvider.camera_message()
	if String(cmsg["text"]) != "":
		var ct: String = cmsg["text"]
		_text(font, Vector2(s.x * 0.5 - font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x * 0.5, 112), ct, 22, cmsg["color"])
	_hud.draw_string_outline(font, Vector2(12.0, s.y - 8.0), GazeProvider.debug_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, Vector2(12.0, s.y - 8.0), GazeProvider.debug_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
	if _age < 25.0:
		var t := "chin DOWN: gather   |   snap chin UP: blast   |   chin UP: float   |   snap DOWN from high: SLAM   |   lean: steer   (W/S or arrows = chin)"
		_text(font, Vector2(s.x * 0.5 - font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, 74), t, 18, Color(1, 1, 1, 0.9))


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	_hud.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
