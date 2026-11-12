class_name EnemyAI
extends CharacterBody3D
## One script, many characters: Roster.DEFS picks stats/looks, `behavior` picks
## the brain. Hits deal damage; big hits ragdoll (a jointed RigidBody swap that
## inherits the impact vector); at 0 HP the character pops into confetti and drops loot.

enum State { CHASE, RAGDOLL }

@export var kind: StringName = &"waddler"
@export var gravity: float = 24.0
@export var recover_time: float = 4.0
@export var hp_scale: float = 1.0
@export var dmg_scale: float = 1.0
@export var body_color: Color = Color(0, 0, 0, 0)  # alpha 0 = use the roster colour

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var visual: Node3D = $Visual

var def: Dictionary
var behavior: String = "chase"
var state: State = State.CHASE
var target: Node3D
var health: float = 1.0
var max_health: float = 1.0
var dying: bool = false
var s: float = 1.0

var _material: StandardMaterial3D
var _head: Node3D
var _ragdoll_root: Node3D
var _torso: Prop
var _ragdoll_time: float = 0.0
var _wind: float = 0.0
var _dot: float = 0.0
var _dot_t: float = 0.0
var _repath: float = 0.0
var _spawn: Vector3
var _t: float = randf() * 10.0
var _cd: float = 2.0
var _contact_cd: float = 1.0
var _act: StringName = &"none"
var _act_t: float = 0.0
var _act_dir: Vector3 = Vector3.ZERO
var _want_dir: Vector3 = Vector3.ZERO
var _want_speed: float = 4.0
var _face_dir: Vector3 = Vector3.ZERO
var _contact_mult: float = 1.0
var _hop_t: float = 0.4
var _airborne: bool = false
var _pending_launch: Vector3 = Vector3.ZERO
var _peel_t: float = 0.0
var slow_until: int = 0
## Cover mode (peek level): stays put behind its rock, rustles while hidden, pops out and lobs
## tomatoes once you can see it.
var cover: bool = false
var _exposed_t: float = 0.0
var _rustle_t: float = 0.5
var _center_y: float = 0.9
var _bar_root: Node3D
var _bar_fg: MeshInstance3D
var _bar_w: float = 1.2


func _ready() -> void:
	def = Roster.get_def(kind)
	behavior = def["behavior"]
	s = float(def["scale"])
	max_health = float(def["hp"]) * hp_scale
	health = max_health
	add_to_group("enemies")
	_spawn = global_position

	var col: Color = def["color"]
	if body_color.a > 0.0:
		col = body_color
	_material = Roster.mat(col)
	visual.scale = Vector3.ONE * s
	_setup_collider()
	_head = Roster.build_visual(kind, def, visual, _material)
	_build_bar()
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	nav.radius = 0.5 * s
	if behavior == "flyer":
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_cd = randf_range(1.0, 3.0)
	if kind == &"boss":
		add_to_group("boss")
		_cd = 4.0
		Game.boss_changed.emit(def["name"], health, max_health)


func _exit_tree() -> void:
	_restore_visual()
	if is_instance_valid(_ragdoll_root):
		_ragdoll_root.queue_free()


func _setup_collider() -> void:
	var c: Array = def["collider"]
	var shape: Shape3D
	match String(c[0]):
		"sphere":
			var ss := SphereShape3D.new()
			ss.radius = float(c[1]) * s
			shape = ss
			_center_y = ss.radius
		"box":
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(c[1]), float(c[2]), float(c[1])) * s
			shape = bs
			_center_y = bs.size.y * 0.5
		_:
			var cs := CapsuleShape3D.new()
			cs.radius = float(c[1]) * s
			cs.height = float(c[2]) * s
			shape = cs
			_center_y = cs.height * 0.5
	collision.shape = shape
	collision.position.y = _center_y


func _build_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0, _center_y * 2.0 + 0.5, 0)
	_bar_root.visible = false
	add_child(_bar_root)
	_bar_w = 1.2 * maxf(s, 0.8)
	var bg := MeshInstance3D.new()
	var q1 := QuadMesh.new()
	q1.size = Vector2(_bar_w + 0.06, 0.18)
	bg.mesh = q1
	bg.material_override = _bar_mat(Color(0, 0, 0, 0.8), 0)
	_bar_root.add_child(bg)
	_bar_fg = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(_bar_w, 0.12)
	_bar_fg.mesh = q2
	_bar_fg.material_override = _bar_mat(Color(0.3, 1.0, 0.3), 1)
	_bar_fg.position.z = 0.01
	_bar_root.add_child(_bar_fg)


func _bar_mat(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.render_priority = prio
	m.no_depth_test = true
	return m


func _update_bar() -> void:
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_bar_root.visible = ratio < 0.999 and not dying
	_bar_fg.scale.x = maxf(ratio, 0.001)
	_bar_fg.position.x = -(1.0 - ratio) * _bar_w * 0.5
	(_bar_fg.material_override as StandardMaterial3D).albedo_color = Color(1.0 - ratio, ratio, 0.2).lightened(0.2)
	if kind == &"boss":
		Game.boss_changed.emit(def["name"], health, max_health)


# --------------------------------------------------------------------------
# Damage API
# --------------------------------------------------------------------------
func _default_damage(source: StringName, speed: float) -> float:
	match source:
		&"kick": return 28.0
		&"slide": return 22.0
		&"plunger": return 4.0
		&"prop": return clampf(speed * 1.1, 6.0, 45.0)
		&"splat": return clampf(speed * 0.9, 6.0, 40.0)
		&"shockwave": return 15.0
		&"leaf": return 0.0
		&"death": return 0.0
	return 10.0


## `launch_velocity` is the velocity change a ragdoll should receive.
func apply_hit(launch_velocity: Vector3, point: Vector3, source: StringName = &"generic", damage: float = -1.0) -> void:
	_pending_launch = launch_velocity
	var dmg := damage if damage >= 0.0 else _default_damage(source, launch_velocity.length())
	if state == State.RAGDOLL:
		if is_instance_valid(_torso):
			_torso.linear_velocity += launch_velocity
		take_damage(dmg, point, source)
		return
	if dying:
		return
	take_damage(dmg, point, source)
	if dying:
		return
	if launch_velocity.length() >= float(def["stagger"]):
		ragdoll(launch_velocity, point, source)
	else:
		velocity += launch_velocity * float(def.get("knock", 0.15))


func take_damage(amount: float, point: Vector3, source: StringName) -> void:
	if dying or amount <= 0.0:
		return
	var crit := false
	if source != &"hazard":
		amount *= Prog.mult("damage")
		if randf() < Prog.crit_chance():
			amount *= 2.0
			crit = true
	health -= amount
	_update_bar()
	var pos := global_position + Vector3.UP * (_center_y * 2.0 + 0.3)
	Game.popup(("CRIT! %d" % int(round(amount))) if crit else str(int(round(amount))), pos,
		Color(1.0, 0.35, 0.2) if crit else Color(1.0, 1.0, 1.0), 1.0 if crit else 0.6)
	if health <= 0.0:
		_die(source)


## Continuous wind from the leaf blower: damage-over-time + ragdoll after exposure.
func apply_wind(accel: Vector3, delta: float, dps: float = 0.0) -> void:
	if dying:
		return
	_dot += dps * delta
	_dot_t += delta
	if _dot_t >= 0.4:
		take_damage(_dot, global_position, &"leaf")
		_dot = 0.0
		_dot_t = 0.0
	if behavior == "flyer":
		velocity += accel * delta * 1.2
		return
	if state != State.CHASE:
		return
	_wind += delta * 2.0
	velocity += accel * delta * 0.35
	var resist := clampf(float(def["stagger"]) / 8.0, 1.0, 20.0)
	if _wind >= 0.6 * resist:
		ragdoll(accel.normalized() * 20.0 + Vector3.UP * 5.0, global_position + Vector3.UP, &"leaf")


func get_ragdoll_body() -> RigidBody3D:
	return _torso if is_instance_valid(_torso) else null


# --------------------------------------------------------------------------
# Death + loot
# --------------------------------------------------------------------------
func _die(_source: StringName) -> void:
	if dying:
		return
	dying = true
	remove_from_group("enemies")
	add_to_group("dying_enemies")
	_bar_root.visible = false
	if kind == &"boss":
		Game.boss_changed.emit(def["name"], 0.0, max_health)
		Game.banner("THE BIG CHEESE IS GRATED!", Color(1.0, 0.85, 0.2), 3.0)
	Game.add_chaos(1)
	Prog.register_kill()
	var gained := Prog.add_xp(int(def["xp"]))
	Game.popup("+%d XP" % gained, global_position + Vector3.UP * (_center_y * 2.0 + 0.8), Color(0.6, 1.0, 0.6), 0.55)
	_drop_loot()
	if kind == &"bomber":
		Fx.shockwave(self, global_position + Vector3.UP * 0.5, 6.0, 25.0, 25.0, true, true, &"hazard", self)
	if behavior == "flyer":
		_pop()
		return
	if state != State.RAGDOLL:
		ragdoll(_pending_launch, global_position, &"death")
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			_pop())


func _pop() -> void:
	Fx.confetti(self, global_position + Vector3.UP, 70, maxf(s, 1.0))
	Game.sfx(&"pop", global_position)
	queue_free()


func _drop_loot() -> void:
	var luck := Prog.mult("drop_rate")
	var p := target as PlayerController
	var coin_range: Array = def["coins"]
	var total := randi_range(int(coin_range[0]), int(coin_range[1]))
	var origin := global_position + Vector3.UP * 0.5
	if total > 0:
		var n := mini(6, total)
		for i in n:
			Pickup.spawn(self, &"coin", origin, maxi(1, total / n))
	var low_hp := p != null and p.health < p.max_hp() * 0.6
	if randf() < (0.2 if low_hp else 0.1) * luck:
		Pickup.spawn(self, &"health", origin, 25)
	if randf() < 0.06 * luck:
		var ids: Array = Prog.POWERUPS.keys()
		Pickup.spawn(self, &"powerup", origin, ids.pick_random())
	if randf() < 0.07 * luck:
		Pickup.spawn(self, &"gear", origin, Loot.generate(0, luck))
	if kind == &"boss":
		for i in 3:
			Pickup.spawn(self, &"gear", origin, Loot.generate(3, 2.0))
		for i in 2:
			Pickup.spawn(self, &"health", origin, 50)
		Pickup.spawn(self, &"powerup", origin, Prog.POWERUPS.keys().pick_random())


# --------------------------------------------------------------------------
# Ragdoll swap
# --------------------------------------------------------------------------
func ragdoll(launch_velocity: Vector3, _point: Vector3, source: StringName = &"generic") -> void:
	if state == State.RAGDOLL or behavior == "flyer":
		return
	state = State.RAGDOLL
	_ragdoll_time = 0.0
	_act = &"none"
	collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	_material.emission_enabled = false
	if def["humanoid"]:
		visual.visible = false
		_build_humanoid_ragdoll(launch_velocity)
	else:
		_build_blob_ragdoll(launch_velocity)
	if source != &"death":
		_announce(launch_velocity, source)


func _new_root() -> void:
	_ragdoll_root = Node3D.new()
	_ragdoll_root.name = "Ragdoll"
	get_parent().add_child(_ragdoll_root)
	_ragdoll_root.global_transform = Transform3D(Basis(Vector3.UP, rotation.y), global_position)


func _build_blob_ragdoll(lv: Vector3) -> void:
	_new_root()
	var c: Array = def["collider"]
	var shape: Shape3D
	match String(c[0]):
		"sphere":
			var ss := SphereShape3D.new()
			ss.radius = float(c[1]) * s
			shape = ss
		"box":
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(c[1]), float(c[2]), float(c[1])) * s
			shape = bs
		_:
			var cs := CapsuleShape3D.new()
			cs.radius = float(c[1]) * s
			cs.height = float(c[2]) * s
			shape = cs
	var p := Prop.new()
	p.kind = &"custom"
	p.name = "Torso"
	p.mass = 6.0 * s * s
	p.bonk_speed = 14.0
	p.linear_damp = 0.1
	p.angular_damp = 0.6
	p.position = Vector3(0, _center_y, 0)
	p.set_meta(&"enemy", self)
	var cs2 := CollisionShape3D.new()
	cs2.shape = shape
	p.add_child(cs2)
	_ragdoll_root.add_child(p)
	_torso = p
	# The whole standing model rides on the rigid body.
	visual.reparent(p, false)
	visual.position = Vector3(0, -_center_y, 0)
	visual.rotation = Vector3.ZERO
	p.linear_velocity = lv
	p.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0


func _build_humanoid_ragdoll(lv: Vector3) -> void:
	_new_root()
	var torso_shape := CapsuleShape3D.new()
	torso_shape.radius = 0.35 * s
	torso_shape.height = 1.2 * s
	_torso = _make_part("Torso", torso_shape, Roster.capsule(0.35, 1.2), Vector3(0, 0.85, 0) * s, 8.0 * s)
	Roster.dress_torso(kind, _torso.get_node("Mesh") as Node3D)

	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.28 * s
	var head := _make_part("Head", head_shape, Roster.sphere(0.28), Vector3(0, 1.5, 0) * s, 3.0 * s)
	Roster.accessorize_head(kind, head.get_node("Mesh") as Node3D)
	_pin(_torso, head, Vector3(0, 1.42, 0) * s)

	var parts: Array[Prop] = [_torso, head]
	for side in [-1.0, 1.0]:
		var arm_shape := CapsuleShape3D.new()
		arm_shape.radius = 0.09 * s
		arm_shape.height = 0.6 * s
		var arm := _make_part("Arm%d" % int(side), arm_shape, Roster.capsule(0.09, 0.6), Vector3(0.48 * side, 1.0, 0) * s, 1.0 * s)
		_pin(_torso, arm, Vector3(0.42 * side, 1.25, 0) * s)
		parts.append(arm)
	for p in parts:
		p.linear_velocity = lv
	_torso.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0


func _make_part(part_name: String, shape: Shape3D, mesh: Mesh, local_pos: Vector3, mass_kg: float) -> Prop:
	var p := Prop.new()
	p.kind = &"custom"
	p.name = part_name
	p.mass = mass_kg
	p.bonk_speed = 14.0
	p.linear_damp = 0.1
	p.angular_damp = 0.8
	p.position = local_pos
	p.set_meta(&"enemy", self)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	p.add_child(cs)
	var m := MeshInstance3D.new()
	m.name = "Mesh"
	m.mesh = mesh
	m.material_override = _material
	m.scale = Vector3.ONE * s
	p.add_child(m)
	_ragdoll_root.add_child(p)
	return p


func _pin(a: Node3D, b: Node3D, local_pos: Vector3) -> void:
	var j := PinJoint3D.new()
	j.position = local_pos
	_ragdoll_root.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


func _announce(lv: Vector3, source: StringName) -> void:
	var text := "BONK!"
	var color := Color(1.0, 0.8, 0.2)
	match source:
		&"plunger":
			text = "THWUP!"
			color = Color(1.0, 0.45, 0.45)
		&"leaf":
			text = "FWOOSH!"
			color = Color(0.7, 1.0, 0.4)
		&"slide":
			text = "BOWLED!"
			color = Color(0.5, 0.9, 1.0)
		&"prop":
			text = "CLONK!"
		&"hazard":
			text = "WHOOPS!"
		&"shockwave":
			text = "KABLAM!"
			color = Color(1.0, 0.6, 0.2)
	var pos := global_position + Vector3.UP * (_center_y * 2.0 + 0.6)
	Game.popup(text, pos, color)
	Game.sfx(&"squawk", global_position)
	Game.sfx(&"pop", global_position)
	if lv.length() > 22.0:
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				Game.popup("YEET!", pos + Vector3.UP * 0.8, Color(1.0, 0.95, 0.3)))


func _restore_visual() -> void:
	if is_instance_valid(visual) and visual.get_parent() != self and is_inside_tree():
		visual.reparent(self, false)
		visual.position = Vector3.ZERO
		visual.rotation = Vector3.ZERO


func _recover() -> void:
	var pos := _spawn
	if is_instance_valid(_torso):
		pos = _torso.global_position
		pos.y -= _center_y if not def["humanoid"] else 0.0
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.8, pos + Vector3.DOWN * 6.0, Game.MASK_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit["position"]
			pos = p
	_restore_visual()
	if is_instance_valid(_ragdoll_root):
		_ragdoll_root.queue_free()
	_ragdoll_root = null
	_torso = null
	global_position = pos + Vector3.UP * 0.1
	rotation = Vector3(0, rotation.y, 0)
	velocity = Vector3.ZERO
	collision.disabled = false
	visual.visible = true
	_wind = 0.0
	_contact_cd = 1.0
	_cd = 1.5
	state = State.CHASE
	Game.popup("RUDE!", global_position + Vector3.UP * (_center_y * 2.0 + 0.4), Color(1.0, 0.6, 0.9))


# --------------------------------------------------------------------------
# Brains
# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if dying and state != State.RAGDOLL:
		return
	match state:
		State.CHASE:
			if cover:
				_cover(delta)
			else:
				_chase(delta)
		State.RAGDOLL:
			_ragdoll_tick(delta)


func _path_dir(flat: Vector3) -> Vector3:
	var next := nav.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05 or nav.is_navigation_finished():
		dir = flat
	return dir.normalized()


func _keep_distance(flat: Vector3, dist: float, near: float, far: float) -> Vector3:
	if dist < near:
		return -flat.normalized()
	if dist > far:
		return _path_dir(flat)
	return Vector3.ZERO


func _begin(act: StringName, t: float) -> void:
	_act = act
	_act_t = t


func _chase(delta: float) -> void:
	_t += delta
	_cd -= delta
	_contact_cd -= delta
	_peel_t -= delta
	_wind = maxf(_wind - delta * 0.6, 0.0)

	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	var p := target as PlayerController
	_want_dir = Vector3.ZERO
	_want_speed = float(def["speed"])
	_contact_mult = 1.0

	if target == null or (p != null and p.dead):
		_apply_move(delta)
		return

	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.25
		nav.target_position = target.global_position
	var flat := target.global_position - global_position
	flat.y = 0.0
	var dist := flat.length()

	if behavior == "flyer":
		_fly(delta, flat)
		return

	_face_dir = Vector3.ZERO
	if _act != &"none":
		_run_action(delta, flat, dist)
	else:
		_run_behavior(delta, flat, dist)
	if _face_dir == Vector3.ZERO:
		_face_dir = _want_dir
	if Time.get_ticks_msec() < slow_until:
		_want_speed *= 0.45
	_apply_move(delta)
	_animate(delta)

	var reach := float(def.get("range", 1.7)) * s
	if float(def["contact"]) > 0.0 and _contact_cd <= 0.0 and dist < reach * (1.4 if _contact_mult > 1.0 else 1.0) \
			and absf(target.global_position.y - global_position.y) < 2.5 * s:
		_hit_player(p, flat)


func _run_behavior(_delta: float, flat: Vector3, dist: float) -> void:
	match behavior:
		"chase":
			_want_dir = _path_dir(flat)
		"tank":
			_want_dir = _path_dir(flat)
			if _cd <= 0.0 and dist < 7.0 * s:
				_begin(&"stomp_wind", 0.9)
		"rush":
			_want_dir = _path_dir(flat)
			if _cd <= 0.0 and dist < float(def["trigger"]):
				_act_dir = flat.normalized()
				_begin(&"rush_wind", float(def["windup"]))
				if kind == &"goose":
					Game.popup("HONK!", global_position + Vector3.UP * 2.2, Color(1, 0.9, 0.3))
					Game.sfx(&"honk", global_position)
		"hop":
			_want_dir = _path_dir(flat)
		"bomber":
			_want_dir = _path_dir(flat)
			if dist < 2.6:
				_begin(&"fuse", 0.9)
				Game.popup("TSSSS!", global_position + Vector3.UP * 1.6, Color(1, 0.5, 0.2))
		"peel":
			_want_dir = _keep_distance(flat, dist, 7.0, 13.0)
			_face_dir = flat
			if _peel_t <= 0.0:
				_peel_t = 1.8
				Hazard.make_peel(get_parent(), global_position + Vector3.UP * 0.05, self)
		"thrower":
			_want_dir = _keep_distance(flat, dist, 9.0, 15.0)
			_face_dir = flat
			if _cd <= 0.0 and dist < 24.0 and dist > 4.0:
				_cd = 2.2
				_throw(flat)
		"mime":
			var seen := _seen_by_player()
			if seen:
				_want_speed = 0.0
				_face_dir = flat
			else:
				_want_dir = _path_dir(flat)
		"blink":
			_want_dir = _path_dir(flat)
			if _cd <= 0.0 and dist > 5.0 and dist < 28.0 and target is Node3D:
				_cd = float(def["cooldown"])
				Fx.confetti(self, global_position + Vector3.UP, 30, 0.8)
				var behind := (target as Node3D).global_basis.z
				behind.y = 0.0
				global_position = target.global_position + behind.normalized() * 3.0 + Vector3.UP * 0.2
				velocity = Vector3.ZERO
				Game.popup("TA-DA!", global_position + Vector3.UP * 2.4, Color(1.0, 0.6, 1.0))
				Game.sfx(&"pop", global_position)
				Fx.confetti(self, global_position + Vector3.UP, 30, 0.8)
		"summoner":
			_want_dir = _keep_distance(flat, dist, 8.0, 12.0)
			_face_dir = flat
			if _cd <= 0.0:
				_cd = float(def["cooldown"])
				_summon(&"duckling", 3)
		"vacuum":
			_want_dir = _keep_distance(flat, dist, 6.0, 9.0)
			_face_dir = flat
			if _cd <= 0.0 and dist < 14.0:
				_begin(&"suck", 5.0)
		"boss":
			_want_dir = _path_dir(flat)
			if _cd <= 0.0:
				var roll := randi() % 3
				if roll == 0 and dist < 10.0 * s:
					_begin(&"stomp_wind", 1.0)
				elif roll == 1:
					_act_dir = flat.normalized()
					_begin(&"rush_wind", float(def["windup"]))
				else:
					_summon(&"waddler", 3)
					_cd = float(def["cooldown"])
		_:
			_want_dir = _path_dir(flat)


func _run_action(delta: float, flat: Vector3, dist: float) -> void:
	_act_t -= delta
	var homing: bool = bool(def.get("homing", false))
	match _act:
		&"rush_wind":
			_want_speed = 0.0
			_face_dir = flat
			_flash(Color(1, 0.9, 0.2))
			if homing:
				_act_dir = flat.normalized()
			if _act_t <= 0.0:
				_begin(&"rush", float(def["rush_time"]))
				Game.sfx(&"whoosh", global_position)
		&"rush":
			_want_dir = flat.normalized() if homing else _act_dir
			_want_speed = float(def["rush_speed"])
			_contact_mult = 2.0
			if _act_t <= 0.0:
				_begin(&"recover", float(def["recover"]))
		&"recover":
			_want_speed = 0.0
			_material.emission_enabled = false
			if _act_t <= 0.0:
				_act = &"none"
				_cd = float(def.get("cooldown", 3.0))
		&"stomp_wind":
			_want_speed = 0.0
			_flash(Color(1, 0.3, 0.2))
			if _act_t <= 0.0:
				Fx.shockwave(self, global_position, 6.0 * minf(s, 1.8), 22.0, 18.0, true, false, &"hazard", self)
				Game.popup("STOMP!", global_position + Vector3.UP * 2.0 * s, Color(1, 0.5, 0.2))
				_begin(&"recover", 0.8)
				_cd = float(def.get("cooldown", 4.0))
		&"fuse":
			_want_speed = 0.0
			_flash(Color(1, 0.2, 0.1), 14.0)
			if _act_t <= 0.0:
				_act = &"none"
				_material.emission_enabled = false
				_die(&"self")
		&"suck":
			_want_dir = _keep_distance(flat, dist, 6.0, 9.0)
			_face_dir = flat
			_suck(delta)
			if _act_t <= 0.0:
				_begin(&"burp_wind", 0.7)
				Game.popup("...", global_position + Vector3.UP * 2.0, Color.WHITE)
		&"burp_wind":
			_want_speed = 0.0
			if _act_t <= 0.0:
				Fx.shockwave(self, global_position + Vector3.UP, 10.0, 28.0, 12.0, true, false, &"hazard", self)
				Game.popup("BUUURP!", global_position + Vector3.UP * 2.2, Color(0.6, 1.0, 0.4))
				_begin(&"recover", 1.5)
				_cd = float(def.get("cooldown", 3.0))
		_:
			_act = &"none"


func _suck(delta: float) -> void:
	var center := global_position + Vector3.UP
	var p := target as PlayerController
	if p != null:
		var off := center - (p.global_position + Vector3.UP)
		var d := off.length()
		if d < 11.0 and d > 0.5:
			p.apply_push(off.normalized() * 16.0 * (1.0 - d / 11.0) * delta)
	for n in get_tree().get_nodes_in_group("props"):
		var rb := n as RigidBody3D
		if rb == null:
			continue
		var off := center - rb.global_position
		var d := off.length()
		if d < 11.0 and d > 0.5:
			rb.apply_central_impulse(off.normalized() * 25.0 * rb.mass * (1.0 - d / 11.0) * delta)


func _fly(delta: float, flat: Vector3) -> void:
	_t += delta
	var p := target as PlayerController
	var to_p := (target.global_position + Vector3.UP) - global_position
	if _act == &"dive":
		_act_t -= delta
		velocity = _act_dir * 14.0
		_contact_mult = 2.0
		if _act_t <= 0.0:
			_act = &"none"
			_cd = 3.0
	else:
		var ty := target.global_position.y + 3.2 + sin(_t * 2.0) * 0.4
		var hdir := Vector3.ZERO
		if flat.length() > 5.0:
			hdir = flat.normalized()
		var want := hdir * float(def["speed"])
		velocity.x = move_toward(velocity.x, want.x, 12.0 * delta)
		velocity.z = move_toward(velocity.z, want.z, 12.0 * delta)
		velocity.y = (ty - global_position.y) * 3.0
		if _cd <= 0.0 and flat.length() < 10.0:
			_act_dir = to_p.normalized()
			_begin(&"dive", 1.0)
			Game.sfx(&"whoosh", global_position)
	move_and_slide()
	visual.rotation.z = sin(_t * 3.0) * 0.15
	if flat.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, 6.0 * delta))
	if _contact_cd <= 0.0 and to_p.length() < 1.6:
		_hit_player(p, flat if flat != Vector3.ZERO else Vector3.FORWARD)


func _seen_by_player() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var head_pos := global_position + Vector3.UP * 1.5
	var to_me := head_pos - cam.global_position
	# Hands-free: "seen" means your EYES are on it (within ~14 degrees of the gaze ray).
	var look_dir := -cam.global_basis.z
	var min_dot := 0.55
	if GazeProvider.active:
		look_dir = cam.project_ray_normal(GazeProvider.gaze * get_viewport().get_visible_rect().size)
		min_dot = 0.97
	if to_me.length() > 70.0 or to_me.normalized().dot(look_dir) < min_dot:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, head_pos, Game.MASK_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _cover(delta: float) -> void:
	_t += delta
	_cd -= delta
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	var p := target as PlayerController
	if target == null or (p != null and p.dead):
		return
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, 6.0 * delta))
	if _exposed_to_player():
		if _exposed_t <= 0.0:
			Game.popup("!", global_position + Vector3.UP * (_center_y * 2.0 + 0.8), Color(1.0, 0.85, 0.2), 1.1)
		_exposed_t += delta
		visual.position.x = 0.0
		if _exposed_t > 0.35 and _cd <= 0.0:
			_cd = randf_range(1.5, 2.3)
			_throw(flat)
	else:
		_exposed_t = maxf(_exposed_t - delta * 2.0, 0.0)
		# Hidden: wiggle and squeak so you know where to snuffle next.
		visual.position.x = sin(_t * 14.0) * 0.05 * s
		_rustle_t -= delta
		if _rustle_t <= 0.0:
			_rustle_t = randf_range(1.2, 2.4)
			rustle()


## A hidden baddy gives itself away: a squeak and a puff of dust.
func rustle() -> void:
	Game.sfx(&"squeak", global_position)
	Fx.confetti(self, global_position + Vector3.UP * 0.5, 5, 0.35)


## True when the player's camera has a clear line to this character's head or chest.
func _exposed_to_player() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var space := get_world_3d().direct_space_state
	for h in [1.45, 0.7]:
		var pt := global_position + Vector3.UP * float(h) * s
		var to := pt - cam.global_position
		if to.length() > 70.0 or to.normalized().dot(-cam.global_basis.z) < 0.15:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, pt, Game.MASK_WORLD)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _throw(flat: Vector3) -> void:
	var t := Prop.make(&"tomato")
	t.set_meta(&"thrower", self)
	t.set_meta(&"dmg", 8.0 * dmg_scale)
	get_parent().add_child(t)
	var from := global_position + Vector3.UP * 1.3 + flat.normalized() * 1.0
	t.global_position = from
	var to := target.global_position + Vector3.UP * 1.0
	if target is CharacterBody3D:
		to += (target as CharacterBody3D).velocity * 0.35
	var tt := clampf(from.distance_to(to) / 18.0, 0.45, 1.4)
	t.linear_velocity = (to - from) / tt + Vector3(0, 0.5 * 9.8 * tt, 0)
	Game.sfx(&"pop", global_position)


func _summon(minion: StringName, count: int) -> void:
	var dir := get_tree().get_first_node_in_group("director") as WaveDirector
	if dir == null:
		return
	Game.popup("QUACK!" if kind == &"mama" else "REINFORCEMENTS!", global_position + Vector3.UP * (_center_y * 2.0 + 1.0), Color(1.0, 0.9, 0.3))
	for i in count:
		var a := TAU * float(i) / float(count) + randf()
		dir.spawn_enemy(minion, global_position + Vector3(cos(a), 0.2, sin(a)) * 2.0 * s)


func _hit_player(p: PlayerController, flat: Vector3) -> void:
	if p == null:
		return
	_contact_cd = 1.2
	var dir := flat.normalized() if flat != Vector3.ZERO else -global_basis.z
	var dmg := float(def["contact"]) * dmg_scale * _contact_mult
	p.take_damage(dmg, global_position, dir * float(def["push"]) * _contact_mult + Vector3.UP * 4.0)
	Game.popup("OOF!", p.global_position + Vector3.UP * 1.6, Color(1.0, 0.6, 0.2))
	Game.sfx(&"squawk", global_position)


func _flash(color: Color, rate: float = 10.0) -> void:
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 0.5 + 0.5 * sin(_t * rate) + 0.5


func _apply_move(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if behavior == "hop":
		if is_on_floor():
			if _airborne:
				_airborne = false
				Fx.shockwave(self, global_position, 3.5, 10.0, 8.0, true, false, &"hazard", self)
				_hop_t = 0.45
			_hop_t -= delta
			h = h.move_toward(Vector3.ZERO, 40.0 * delta)
			if _hop_t <= 0.0 and _want_dir != Vector3.ZERO and _act == &"none":
				velocity.y = 9.5
				h = _want_dir * _want_speed
				_airborne = true
				Game.sfx(&"pop", global_position)
		else:
			_airborne = true
	else:
		var accel := 80.0 if _act == &"rush" else 20.0
		h = h.move_toward(_want_dir * _want_speed, accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= gravity * Game.gravity_scale * delta
	move_and_slide()
	if _face_dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-_face_dir.x, -_face_dir.z), minf(1.0, 8.0 * delta))


func _animate(delta: float) -> void:
	var run := Vector3(velocity.x, 0.0, velocity.z).length() / maxf(float(def["speed"]), 0.1)
	var base := Vector3.ONE * s
	var vs := base
	if behavior == "hop":
		var stretch := clampf(velocity.y * 0.03, -0.25, 0.3)
		vs = base * Vector3(1.0 - stretch * 0.5, 1.0 + stretch, 1.0 - stretch * 0.5)
	else:
		visual.rotation.z = sin(_t * 9.0) * 0.12 * run
		visual.position.y = absf(sin(_t * 9.0)) * 0.08 * run * s
	match _act:
		&"fuse":
			vs = base * (1.0 + 0.2 * sin(_t * 30.0))
		&"stomp_wind":
			vs = base * Vector3(1.15, 0.8, 1.15)
		&"burp_wind":
			vs = base * (1.0 + 0.4 * (1.0 - _act_t / 0.7))
		&"rush_wind":
			vs = base * Vector3(1.1, 0.85, 1.1)
		&"recover":
			visual.rotation.z = sin(_t * 12.0) * 0.25
			visual.rotation.y = 0.0
	if kind == &"spinner":
		if _act == &"rush":
			visual.rotation.y += delta * 22.0
		else:
			visual.rotation.y = lerp_angle(visual.rotation.y, 0.0, 6.0 * delta)
		if _head != null and _head.has_node("Propeller"):
			_head.get_node("Propeller").rotation.y += delta * (30.0 if _act == &"rush" else 8.0)
	visual.scale = vs


func _ragdoll_tick(delta: float) -> void:
	_ragdoll_time += delta
	if not is_instance_valid(_torso):
		if not dying:
			_recover()
		return
	global_position = _torso.global_position - (Vector3.UP * _center_y if not def["humanoid"] else Vector3.ZERO)
	if _torso.global_position.y < -25.0 and not dying:
		_torso.global_position = _spawn + Vector3.UP * 2.0
		_recover()
		return
	if dying or bool(_torso.get_meta(&"held", false)):
		return
	var settled := _torso.linear_velocity.length() < 2.0
	if (_ragdoll_time > recover_time and settled) or _ragdoll_time > recover_time * 3.0:
		_recover()
