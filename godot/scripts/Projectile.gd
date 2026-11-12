class_name Projectile
extends Node3D
## Rockets and shock cores. Swept-ray movement (no tunnelling), optional soft
## homing, explosion via Fx.shockwave. A shock core hit by a shock-rifle beam
## detonates as a huge SHOCK COMBO.

var kind: StringName = &"rocket"
var velocity: Vector3 = Vector3.ZERO
var target: Node3D = null
var homing: float = 0.0          # radians/sec toward `target`
var life: float = 5.0
var damage: float = 75.0
var radius: float = 5.5
var force: float = 26.0
var _done: bool = false


static func fire(ctx: Node, p_kind: StringName, from: Vector3, dir: Vector3, speed: float, p_target: Node3D = null, p_homing: float = 0.0) -> Projectile:
	var p := Projectile.new()
	p.kind = p_kind
	p.velocity = dir.normalized() * speed
	p.target = p_target
	p.homing = p_homing
	var dm := Prog.mult("weapon_damage")
	if p_kind == &"core":
		p.damage = 50.0 * dm
		p.radius = 3.4
		p.force = 20.0
		p.life = 6.0
	else:
		p.damage = 75.0 * dm
		p.radius = 5.5
		p.force = 26.0
	Fx._world(ctx).add_child(p)
	p.global_position = from
	return p


func _ready() -> void:
	if kind == &"core":
		add_to_group("shock_cores")
		var m := Roster.mat(Color(0.7, 0.35, 1.0, 0.85), 3.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		Roster.mi(self, Roster.sphere(0.3), Vector3.ZERO, Color.WHITE, Vector3.ZERO, 3.0, m)
		Roster.mi(self, Roster.sphere(0.13), Vector3.ZERO, Color(0.9, 0.95, 1.0), Vector3.ZERO, 4.0)
	else:
		Roster.mi(self, Roster.cyl(0.07, 0.07, 0.5), Vector3.ZERO, Color(0.55, 0.58, 0.5), Vector3(90, 0, 0))
		Roster.mi(self, Roster.cyl(0.0, 0.07, 0.18), Vector3(0, 0, -0.33), Color(0.9, 0.2, 0.15), Vector3(-90, 0, 0))
		Roster.mi(self, Roster.sphere(0.09), Vector3(0, 0, 0.3), Color(1.0, 0.7, 0.2), Vector3.ZERO, 4.0)
		var t := CPUParticles3D.new()
		t.amount = 14
		t.lifetime = 0.5
		t.local_coords = false
		t.direction = Vector3(0, 0, 1)
		t.spread = 12.0
		t.gravity = Vector3.ZERO
		t.initial_velocity_min = 1.0
		t.initial_velocity_max = 3.0
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color(0.85, 0.85, 0.85, 0.7)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = smat
		t.mesh = sm
		add_child(t)
		t.position = Vector3(0, 0, 0.3)
		t.emitting = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	life -= delta
	if homing > 0.0 and is_instance_valid(target) and not (target is EnemyAI and (target as EnemyAI).dying):
		var aim := target.global_position + (Vector3.UP if target is EnemyAI else Vector3.ZERO)
		var want := (aim - global_position).normalized()
		var spd := velocity.length()
		var cur := velocity / maxf(spd, 0.001)
		var ang := cur.angle_to(want)
		if ang > 0.0005:
			velocity = cur.slerp(want, minf(1.0, homing * delta / ang)) * spd
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.MASK_WORLD | Game.MASK_ENEMY | Game.MASK_PROPS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_explode(hit.get("collider") as Node)
		return
	global_position = to
	if velocity.length() > 0.1 and not velocity.normalized().is_equal_approx(Vector3.UP):
		look_at(global_position + velocity, Vector3.UP)
	if life <= 0.0:
		_explode(null)


## Shock combo: a beam through a core makes everything near it bad news.
func combo() -> void:
	if _done:
		return
	_done = true
	var p := global_position
	Game.banner("SHOCK COMBO!", Color(0.75, 0.45, 1.0), 1.4)
	Game.add_chaos(5)
	Fx.shockwave(self, p, 10.0, 40.0, 170.0 * Prog.mult("weapon_damage"), false, true, &"combo", null, Color(0.7, 0.4, 1.0, 0.55))
	Fx.confetti(self, p, 70, 1.4)
	var pl := get_tree().get_first_node_in_group("player") as PlayerController
	if pl != null:
		pl.add_trauma(0.6, 0.9)
	queue_free()


func _explode(collider: Node) -> void:
	if _done:
		return
	_done = true
	var p := global_position
	if kind == &"core":
		if collider is EnemyAI:
			(collider as EnemyAI).apply_hit(velocity.normalized() * 12.0, p, &"shock", 30.0 * Prog.mult("weapon_damage"))
		Fx.shockwave(self, p, radius, force, damage, false, true, &"shock", null, Color(0.7, 0.4, 1.0, 0.5))
	else:
		Fx.shockwave(self, p, radius, force, damage, false, true, &"rocket")
		Fx.confetti(self, p, 36, 0.9)
		Game.popup("BOOM!", p + Vector3.UP * 0.8, Color(1.0, 0.6, 0.2), 1.1)
		# Mild rocket-jump: blasts near your feet shove you around (no damage).
		var pl := get_tree().get_first_node_in_group("player") as PlayerController
		if pl != null:
			var off := (pl.global_position + Vector3.UP) - p
			if off.length() < radius * 0.8:
				pl.apply_push(off.normalized() * (1.0 - off.length() / (radius * 0.8)) * 16.0, 30.0)
	var pl2 := get_tree().get_first_node_in_group("player") as PlayerController
	if pl2 != null:
		pl2.add_trauma(0.35, 0.7)
	queue_free()
