class_name PlungerGrapple
extends WeaponBase
## LMB: fire a suction cup (hit-scan with a visible flight). On a prop/enemy it
## hooks on and reels the target to a hold point above and in front of you;
## LMB again FLINGS it, RMB just drops it. On world geometry it grapples YOU
## toward the hook point (jump or click to let go).

enum Mode { IDLE, FLYING, HOOKED_BODY, HOOKED_WORLD }

@export var max_range: float = 45.0
@export var projectile_speed: float = 140.0
@export var hold_forward: float = 3.2
@export var hold_up: float = 1.3
@export var pull_gain: float = 6.0
@export var pull_max_speed: float = 30.0
@export var pull_response: float = 12.0
@export var fling_speed: float = 40.0
@export var fling_lift: float = 6.0
@export var grapple_accel: float = 55.0
@export var grapple_max_speed: float = 32.0
@export var fire_cooldown: float = 0.3
@export var max_tether_length: float = 70.0

@onready var muzzle: Marker3D = $Muzzle

var mode: Mode = Mode.IDLE

var _target: RigidBody3D
var _anchor_local: Vector3 = Vector3.ZERO
var _anchor_world: Vector3 = Vector3.ZERO
var _fly_from: Vector3
var _fly_to: Vector3
var _fly_t: float = 0.0
var _fly_dur: float = 0.1
var _fly_hit: Dictionary = {}
var _cd: float = 0.0
var _tether: MeshInstance3D
var _cup: MeshInstance3D


func _ready() -> void:
	display_name = "Plunger Grapple"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.2, 0.2)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.material = mat
	_tether = MeshInstance3D.new()
	_tether.mesh = cyl
	_tether.top_level = true
	_tether.visible = false
	add_child(_tether)

	var cup := CylinderMesh.new()
	cup.top_radius = 0.12
	cup.bottom_radius = 0.12
	cup.height = 0.07
	cup.radial_segments = 16
	cup.material = mat
	_cup = MeshInstance3D.new()
	_cup.mesh = cup
	_cup.top_level = true
	_cup.visible = false
	add_child(_cup)


func _on_unequip() -> void:
	_release(false)
	mode = Mode.IDLE
	_hide_tether()


func primary_pressed() -> void:
	match mode:
		Mode.IDLE:
			if _cd <= 0.0:
				_fire()
		Mode.HOOKED_BODY:
			_release(true)
		Mode.HOOKED_WORLD:
			_release(false)


func alt_pressed() -> void:
	if mode == Mode.HOOKED_BODY or mode == Mode.HOOKED_WORLD:
		_release(false)


func _fire() -> void:
	_cd = fire_cooldown
	var hit := raycast(max_range * Prog.mult("plunger_power"), Game.MASK_WORLD | Game.MASK_ENEMY | Game.MASK_PROPS)
	_fly_hit = hit
	_fly_from = muzzle.global_position
	if hit.is_empty():
		_fly_to = aim_origin() + aim_direction() * max_range
	else:
		_fly_to = hit["position"]
	_fly_dur = maxf(_fly_from.distance_to(_fly_to) / projectile_speed, 0.03)
	_fly_t = 0.0
	mode = Mode.FLYING
	Game.sfx(&"pop", _fly_from)
	player.add_recoil(2.0, 0.04)
	player.add_trauma(0.3, 0.5)


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	match mode:
		Mode.FLYING:
			_fly_t += delta / _fly_dur
			var tip := _fly_from.lerp(_fly_to, minf(_fly_t, 1.0))
			_draw_tether(muzzle.global_position, tip)
			if _fly_t >= 1.0:
				_on_impact()
		Mode.HOOKED_BODY:
			_step_body(delta)
		Mode.HOOKED_WORLD:
			_step_world(delta)


func _on_impact() -> void:
	if _fly_hit.is_empty():
		mode = Mode.IDLE
		_hide_tether()
		return
	var collider: Object = _fly_hit["collider"]
	if not is_instance_valid(collider):
		mode = Mode.IDLE
		_hide_tether()
		return
	var point: Vector3 = _fly_hit["position"]
	Game.popup("THWUP!", point, Color(1.0, 0.45, 0.45))
	Game.sfx(&"thwup", point)

	if collider is EnemyAI:
		var enemy := collider as EnemyAI
		var to_player := (muzzle.global_position - point).normalized()
		enemy.apply_hit(to_player * 8.0 + Vector3.UP * 5.0, point, &"plunger")
		var body := enemy.get_ragdoll_body()
		if body != null:
			_hook_body(body, point)
		else:
			mode = Mode.IDLE
			_hide_tether()
	elif collider is RigidBody3D:
		_hook_body(collider as RigidBody3D, point)
	else:
		mode = Mode.HOOKED_WORLD
		_anchor_world = point


func _hook_body(body: RigidBody3D, point: Vector3) -> void:
	_target = body
	_target.set_meta(&"held", true)  # EnemyAI waits while its ragdoll is held
	_anchor_local = body.to_local(point)
	mode = Mode.HOOKED_BODY


func _step_body(delta: float) -> void:
	if not is_instance_valid(_target):
		_release(false)
		return
	var anchor := _target.to_global(_anchor_local)
	var origin := muzzle.global_position
	if origin.distance_to(anchor) > max_tether_length:
		_release(false)
		return

	# Velocity-matching reel toward a hold point above/in front of the player.
	var hold := camera.global_position + aim_direction() * hold_forward + Vector3.UP * hold_up
	var pm := Prog.mult("plunger_power")
	var desired := ((hold - anchor) * pull_gain * pm).limit_length(pull_max_speed * pm)
	var dv := (desired - _target.linear_velocity) * minf(1.0, pull_response * delta)
	_target.apply_central_impulse(dv * _target.mass)
	_target.angular_velocity *= maxf(0.0, 1.0 - 3.0 * delta)
	_draw_tether(origin, anchor)


func _step_world(delta: float) -> void:
	var chest := player.global_position + Vector3.UP * 1.0
	var to := _anchor_world - chest
	var dist := to.length()
	if dist < 2.0 or Input.is_action_just_pressed(&"jump"):
		_release(false)
		return
	player.apply_push(to / dist * grapple_accel * delta, grapple_max_speed)
	_draw_tether(muzzle.global_position, _anchor_world)


func _release(fling: bool) -> void:
	if mode == Mode.HOOKED_BODY and is_instance_valid(_target):
		_target.set_meta(&"held", false)
		if fling:
			_target.linear_velocity = aim_direction() * fling_speed * Prog.mult("plunger_power") + Vector3.UP * fling_lift
			if Prog.flag("yeetcannon"):
				_target.set_meta(&"yeet", true)
			_target.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
			Game.popup("YEET!", _target.global_position + Vector3.UP * 0.8, Color(1.0, 0.9, 0.2))
			Game.sfx(&"yeet", _target.global_position)
			Game.add_chaos(1)
			player.add_trauma(0.5, 0.9)
			player.add_recoil(3.0, 0.08)
	_target = null
	if mode != Mode.IDLE:
		_cd = 0.25
	mode = Mode.IDLE
	_hide_tether()


func _hide_tether() -> void:
	_tether.visible = false
	_cup.visible = false


func _draw_tether(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var dist := d.length()
	if dist < 0.01:
		return
	var dir := d / dist
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# CylinderMesh runs along Y; rotate so Y points down the tether.
	var bs := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI / 2.0)
	_tether.global_transform = Transform3D(bs.scaled_local(Vector3(1.0, dist, 1.0)), (a + b) * 0.5)
	_cup.global_transform = Transform3D(bs, b)
	_tether.visible = true
	_cup.visible = true
