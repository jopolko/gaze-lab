class_name Zone
extends Area3D
## Interactive floor/volume mechanics used by the levels.
##   bounce  trampoline: launches anything that touches it (`launch` vector)
##   boost   speed strip: shoves the player along `launch` direction
##   slip    ice / wet floor: player loses traction, enemies trip
##   sticky  goo / water: slows player and enemies
##   lava    burns player + enemies, bounces them out, floats props
##   vent    updraft column: lifts player and props

const TINTS := {
	&"bounce": Color(1.0, 0.35, 0.8, 0.55),
	&"boost": Color(0.2, 0.9, 1.0, 0.5),
	&"slip": Color(0.75, 0.9, 1.0, 0.35),
	&"sticky": Color(0.45, 0.28, 0.12, 0.6),
	&"lava": Color(1.0, 0.4, 0.05, 0.0),
	&"vent": Color(0.9, 0.9, 1.0, 0.18),
}

var type: StringName = &"bounce"
var launch: Vector3 = Vector3.ZERO
var size: Vector3 = Vector3(4, 1, 4)
var tint: Color = Color(0, 0, 0, 0)
var show_mesh: bool = true


static func make(parent: Node, p_type: StringName, pos: Vector3, p_size: Vector3,
		p_launch: Vector3 = Vector3.ZERO, p_tint: Color = Color(0, 0, 0, 0), p_show: bool = true) -> Zone:
	var z := Zone.new()
	z.type = p_type
	z.size = p_size
	z.launch = p_launch
	z.tint = p_tint
	z.show_mesh = p_show
	z.position = pos
	parent.add_child(z)
	return z


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.MASK_PLAYER | Game.MASK_ENEMY | Game.MASK_PROPS
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	var c: Color = tint if tint.a > 0.0 else TINTS[type]
	if show_mesh and c.a > 0.0:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = 0.8
		var mesh := BoxMesh.new()
		# Flat glowing pad at the bottom of the volume (vents/slip show a taller haze).
		var flat := type == &"bounce" or type == &"boost" or type == &"slip" or type == &"sticky"
		mesh.size = Vector3(size.x, 0.12 if flat else size.y, size.z)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.position.y = -size.y * 0.5 + 0.08 if flat else 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	body_entered.connect(_on_enter)


func _on_enter(b: Node3D) -> void:
	if type != &"bounce":
		return
	var now := Time.get_ticks_msec()
	if now - int(b.get_meta(&"bounce_t", 0)) < 450:
		return
	b.set_meta(&"bounce_t", now)
	var l := launch if launch != Vector3.ZERO else Vector3(0, 22, 0)
	if b is PlayerController:
		var p := b as PlayerController
		p.velocity = Vector3(p.velocity.x * 0.6 + l.x, l.y, p.velocity.z * 0.6 + l.z)
		Game.popup("BOING!", p.global_position + Vector3.UP * 2.0, Color(1.0, 0.5, 0.9))
		Game.sfx(&"boing", global_position)
		p.add_trauma(0.3, 0.5)
	elif b is RigidBody3D:
		(b as RigidBody3D).linear_velocity = l
		Game.sfx(&"boing", global_position)
	elif b is EnemyAI:
		var e := b as EnemyAI
		e.apply_hit(l, e.global_position, &"hazard", 0.0)
		e.velocity = l
		Game.popup("WHEEE!", e.global_position + Vector3.UP * 2.0, Color(1.0, 0.7, 1.0))
		Game.sfx(&"boing", global_position)


func _physics_process(delta: float) -> void:
	if type == &"bounce":
		return
	var now := Time.get_ticks_msec()
	for b in get_overlapping_bodies():
		match type:
			&"boost":
				var dir := launch.normalized()
				if b is PlayerController:
					(b as PlayerController).apply_push(dir * 55.0 * delta, 32.0)
				elif b is RigidBody3D:
					(b as RigidBody3D).apply_central_impulse(dir * 30.0 * (b as RigidBody3D).mass * delta)
			&"slip":
				if b is PlayerController:
					(b as PlayerController).slippery_until = now + 140
				elif b is EnemyAI and randf() < 0.5 * delta:
					var e := b as EnemyAI
					var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
					e.apply_hit(d * 10.0 + Vector3.UP * 6.0, e.global_position, &"hazard", 0.0)
					Game.popup("WHOOPS!", e.global_position + Vector3.UP * 2.0, Color(0.7, 0.9, 1.0), 0.8)
			&"sticky":
				if b is PlayerController:
					(b as PlayerController).sticky_until = now + 140
				elif b is EnemyAI:
					(b as EnemyAI).slow_until = now + 140
			&"lava":
				_lava(b, delta, now)
			&"vent":
				if b is PlayerController:
					var p := b as PlayerController
					if p.velocity.y < 14.0:
						p.velocity.y += 48.0 * delta
				elif b is RigidBody3D:
					var rb := b as RigidBody3D
					if rb.linear_velocity.y < 10.0:
						rb.apply_central_impulse(Vector3.UP * 35.0 * rb.mass * delta)


func _lava(b: Node3D, delta: float, now: int) -> void:
	if b is PlayerController:
		var p := b as PlayerController
		if now - int(p.get_meta(&"lava_t", 0)) > 600:
			p.set_meta(&"lava_t", now)
			p.take_damage(10.0, global_position, Vector3.UP * 4.0)
			Game.popup("HOT HOT HOT!", p.global_position + Vector3.UP * 2.0, Color(1.0, 0.5, 0.1))
		p.velocity.y = maxf(p.velocity.y, 13.0)
	elif b is EnemyAI:
		var e := b as EnemyAI
		if now - int(e.get_meta(&"lava_t", 0)) > 800:
			e.set_meta(&"lava_t", now)
			e.apply_hit(Vector3.UP * 14.0, e.global_position, &"hazard", 12.0)
			e.velocity.y = 12.0
	elif b is RigidBody3D:
		var rb := b as RigidBody3D
		rb.apply_central_impulse(Vector3.UP * rb.mass * 22.0 * delta)
