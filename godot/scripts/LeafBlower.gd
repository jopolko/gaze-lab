class_name LeafBlower
extends WeaponBase
## Hold fire: a cone-shaped Area3D pushes everything in front of you with a
## constant per-frame impulse. Aim at the ground to rocket-jump / hover.

@export var cone_length: float = 9.0
@export var cone_radius: float = 3.5
@export var wind_accel: float = 60.0          # m/s^2 given to props (mass-independent)
@export var lift_bias: float = 0.2            # a little upward lift so props float
@export var spin_chaos: float = 2.0
@export var rocket_reach: float = 6.0
@export var rocket_thrust: float = 70.0       # m/s^2 at point-blank
@export var rocket_max_speed: float = 28.0

@onready var cone: Area3D = $WindCone
@onready var cone_shape: CollisionShape3D = $WindCone/ConeShape
@onready var muzzle: Marker3D = $Muzzle

var firing: bool = false
var _particles: CPUParticles3D
var _last_popup_msec: int = 0


func _ready() -> void:
	display_name = "Leaf Blower"
	_build_cone()
	_build_particles()
	cone.monitoring = false
	Prog.changed.connect(_on_stats)


func _on_stats() -> void:
	_build_cone()


func _build_cone() -> void:
	# Tip at the nozzle, opening along -Z.
	var pts := PackedVector3Array()
	pts.append(Vector3.ZERO)
	var steps := 12
	var length := cone_length * Prog.mult("blower_range")
	var radius := cone_radius * (0.8 + 0.2 * Prog.mult("blower_range"))
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(Vector3(cos(a) * radius, sin(a) * radius, -length))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cone_shape.shape = shape
	cone.position = muzzle.position


func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 48
	_particles.lifetime = 0.55
	_particles.local_coords = false
	_particles.direction = Vector3(0, 0, -1)
	_particles.spread = 14.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 14.0
	_particles.initial_velocity_max = 20.0
	_particles.scale_amount_min = 0.5
	_particles.scale_amount_max = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.95, 0.35, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_particles.mesh = mesh
	muzzle.add_child(_particles)


func _on_unequip() -> void:
	_set_firing(false)


func primary_pressed() -> void:
	_set_firing(true)
	var now := Time.get_ticks_msec()
	if now - _last_popup_msec > 1500:
		_last_popup_msec = now
		Game.popup("FWOOSH!", aim_origin() + aim_direction() * 3.0, Color(0.7, 1.0, 0.4))


func primary_released() -> void:
	_set_firing(false)


func _set_firing(on: bool) -> void:
	if firing == on:
		return
	firing = on
	cone.monitoring = on
	_particles.emitting = on
	Game.sfx(&"blower_on" if on else &"blower_off")


func _physics_process(delta: float) -> void:
	if not firing:
		return
	var dir := aim_direction()
	var power := Prog.mult("blower_power")
	var length := cone_length * Prog.mult("blower_range")
	var push_dir := (dir + Vector3.UP * lift_bias).normalized()

	for body in cone.get_overlapping_bodies():
		var rel: Vector3 = body.global_position - cone.global_position
		var along := clampf(rel.dot(dir) / length, 0.0, 1.0)
		var strength := lerpf(1.0, 0.25, along)
		if body is RigidBody3D:
			var rb := body as RigidBody3D
			rb.apply_central_impulse(push_dir * wind_accel * power * strength * rb.mass * delta)
			var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			rb.apply_torque_impulse(spin * spin_chaos * rb.mass * delta * 0.3)
		elif body is EnemyAI:
			(body as EnemyAI).apply_wind(dir * wind_accel * power * strength, delta, 9.0 * power * strength)

	# Rocket-jump / hover: the nozzle shoves *you* away from nearby ground/walls.
	var hit := raycast(rocket_reach, Game.MASK_WORLD)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		var dist := aim_origin().distance_to(p)
		var k := pow(clampf(1.0 - dist / rocket_reach, 0.0, 1.0), 0.8)
		player.apply_push(-dir * rocket_thrust * Prog.mult("thrust") * k * delta, rocket_max_speed)

	player.add_trauma(0.9 * delta, 0.22)
