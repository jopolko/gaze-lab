class_name Prop
extends RigidBody3D
## Physics prop: crate, barrel, beach ball or rubber duck. Builds its own
## collider + mesh from `kind`. Use kind = &"custom" and add your own children
## (the enemy ragdoll parts do this). Hard impacts spawn "BONK!" pop-ups, and
## fast props knock enemies into ragdoll.

@export var kind: StringName = &"crate"
@export var size_scale: float = 1.0
@export var bonk_speed: float = 9.0

var _home: Vector3 = Vector3.ZERO
var _last_bonk_msec: int = 0
var _exploded: bool = false
var _bonk_words: Array[String] = ["BONK!", "THUD!", "CLONK!", "WHAM!"]


static func make(p_kind: StringName, p_size_scale: float = 1.0) -> Prop:
	var p := Prop.new()
	p.kind = p_kind
	p.size_scale = p_size_scale
	return p


func _ready() -> void:
	collision_layer = Game.MASK_PROPS
	collision_mask = Game.MASK_WORLD | Game.MASK_PLAYER | Game.MASK_ENEMY | Game.MASK_PROPS
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("props")
	gravity_scale = Game.gravity_scale
	_home = global_position

	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.15
	physics_material_override = pm
	if kind != &"custom":
		_build(pm)
	body_entered.connect(_on_body_entered)


func _build(pm: PhysicsMaterial) -> void:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	var shape: Shape3D
	var mesh: Mesh
	var s := size_scale

	match kind:
		&"barrel":
			mat.albedo_color = Color(0.85, 0.2, 0.15)
			var cs := CylinderShape3D.new()
			cs.radius = 0.35 * s
			cs.height = 0.9 * s
			shape = cs
			var cm := CylinderMesh.new()
			cm.top_radius = cs.radius
			cm.bottom_radius = cs.radius
			cm.height = cs.height
			mesh = cm
			mass = 12.0 * s
		&"tnt":
			mat.albedo_color = Color(0.85, 0.1, 0.1)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.2, 0.1)
			mat.emission_energy_multiplier = 0.4
			var ns := BoxShape3D.new()
			ns.size = Vector3(0.8, 0.8, 0.8)
			shape = ns
			var nm := BoxMesh.new()
			nm.size = ns.size
			mesh = nm
			mass = 5.0
			bonk_speed = 999.0
		&"tomato":
			mat.albedo_color = Color(0.9, 0.12, 0.1)
			var ts := SphereShape3D.new()
			ts.radius = 0.22
			shape = ts
			var tm := SphereMesh.new()
			tm.radius = 0.22
			tm.height = 0.44
			mesh = tm
			mass = 0.6
			bonk_speed = 999.0
			get_tree().create_timer(8.0).timeout.connect(func() -> void:
				if is_instance_valid(self):
					queue_free())
		&"ball":
			mat.albedo_color = Color.from_hsv(randf(), 0.8, 1.0)
			var ss := SphereShape3D.new()
			ss.radius = 0.5 * s
			shape = ss
			var sm := SphereMesh.new()
			sm.radius = ss.radius
			sm.height = ss.radius * 2.0
			mesh = sm
			mass = 1.5 * s
			pm.bounce = 0.85
			pm.friction = 0.3
		&"duck":
			mat.albedo_color = Color(1.0, 0.85, 0.1)
			var ds := SphereShape3D.new()
			ds.radius = 0.38 * s
			shape = ds
			var dm := SphereMesh.new()
			dm.radius = ds.radius
			dm.height = ds.radius * 2.0
			mesh = dm
			mass = 1.0 * s
			pm.bounce = 0.4
			_bonk_words = ["SQUAWK!", "QUACK!", "HONK!"]
			_add_beak(ds.radius)
		_:  # crate
			var side := 0.9 * s * randf_range(0.8, 1.25)
			mat.albedo_color = Color(0.72, 0.5, 0.28)
			var bs := BoxShape3D.new()
			bs.size = Vector3.ONE * side
			shape = bs
			var bm := BoxMesh.new()
			bm.size = bs.size
			mesh = bm
			mass = 7.0 * pow(side, 3.0)

	var cshape := CollisionShape3D.new()
	cshape.shape = shape
	add_child(cshape)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _add_beak(r: float) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(0.22, 0.1, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.05)
	var beak := MeshInstance3D.new()
	beak.mesh = m
	beak.material_override = mat
	beak.position = Vector3(0, -0.02, -r - 0.05)
	add_child(beak)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Kill plane: anything launched out of the arena respawns where it began.
	if kind != &"custom" and state.transform.origin.y < -30.0:
		state.transform = Transform3D(Basis.IDENTITY, _home)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO


func _on_body_entered(body: Node) -> void:
	var speed := linear_velocity.length()
	if kind == &"tomato":
		_tomato_hit(body, speed)
		return
	if kind == &"tnt":
		if speed > 8.0 and not _exploded:
			_exploded = true
			Game.popup("KABOOM!", global_position + Vector3.UP, Color(1.0, 0.4, 0.1), 1.3)
			Fx.shockwave(self, global_position, 7.0, 24.0, 40.0, true, true, &"shockwave")
			Fx.confetti(self, global_position, 40, 1.2)
			queue_free.call_deferred()
		return
	if speed > 9.0 and bool(get_meta(&"yeet", false)):
		set_meta(&"yeet", false)
		Game.popup("KABLAMMO!", global_position + Vector3.UP, Color(1.0, 0.6, 0.1), 1.3)
		Fx.shockwave(self, global_position, 6.5, 22.0, 45.0, false, true, &"shockwave")
		return
	if speed < bonk_speed:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bonk_msec < 350:
		return
	_last_bonk_msec = now

	if body is EnemyAI:
		if body == _meta(&"enemy"):
			return
		(body as EnemyAI).apply_hit(linear_velocity * 0.7 + Vector3.UP * 4.0, global_position, &"prop")
		return
	if kind == &"custom":
		# Ragdoll limbs hurt their owner when slammed into the world.
		var owner_enemy: Object = _meta(&"enemy")
		if is_instance_valid(owner_enemy) and (body is StaticBody3D or body is Prop):
			(owner_enemy as EnemyAI).take_damage(clampf(speed * 0.9, 6.0, 40.0), global_position, &"splat")
			Game.popup("SPLAT!", global_position + Vector3.UP * 0.8, Color(1.0, 0.5, 0.5), 0.8)
			Game.sfx(&"bonk", global_position)
		return
	Game.popup(_bonk_words.pick_random(), global_position + Vector3.UP * 0.6, Color(1.0, 0.8, 0.3))
	Game.sfx(&"squawk" if kind == &"duck" else &"bonk", global_position)


func _meta(key: StringName) -> Variant:
	return get_meta(key) if has_meta(key) else null


func _tomato_hit(body: Node, speed: float) -> void:
	if body == _meta(&"thrower") or speed < 3.0:
		return
	var dmg := float(get_meta(&"dmg", 8.0))
	if body is PlayerController:
		(body as PlayerController).take_damage(dmg, global_position, linear_velocity.normalized() * 4.0)
	elif body is EnemyAI:
		(body as EnemyAI).apply_hit(linear_velocity * 0.5, global_position, &"prop", 12.0)
	Game.popup("SPLAT!", global_position + Vector3.UP * 0.3, Color(1.0, 0.3, 0.3), 0.8)
	Game.sfx(&"pop", global_position)
	Fx.confetti(self, global_position, 12, 0.4)
	queue_free.call_deferred()
