class_name ShockRifle
extends WeaponBase
## UT99-style Shock Rifle.
##   primary : instant shock beam (hitscan), aim-assisted
##   alt     : slow shock CORE. Shoot the core with the beam for a SHOCK COMBO.
## Built entirely from primitives; no art assets.

const RANGE := 140.0
const BEAM_DAMAGE := 36.0
const MASK := Game.MASK_WORLD | Game.MASK_ENEMY | Game.MASK_PROPS

var _cd: float = 0.0
var _muzzle: Node3D


func _ready() -> void:
	display_name = "Shock Rifle"
	volley_tail = 0.35
	position = Vector3(0.22, -0.22, -0.45)
	var body := Color(0.2, 0.22, 0.28)
	Roster.mi(self, Roster.box(Vector3(0.12, 0.15, 0.5)), Vector3(0, -0.04, 0.2), body)
	Roster.mi(self, Roster.cyl(0.05, 0.05, 0.75), Vector3(0, 0.02, -0.25), Color(0.55, 0.25, 1.0), Vector3(90, 0, 0), 2.5)
	for i in 3:
		Roster.mi(self, Roster.torus(0.055, 0.085), Vector3(0, 0.02, -0.05 - 0.2 * i), Color(0.3, 0.9, 1.0), Vector3(90, 0, 0), 2.0)
	Roster.mi(self, Roster.sphere(0.07), Vector3(0, 0.02, -0.64), Color(0.85, 0.7, 1.0), Vector3.ZERO, 3.0)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -0.66)
	add_child(_muzzle)


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)


func is_ready() -> bool:
	return _cd <= 0.0


func primary_pressed() -> void:
	if _cd <= 0.0:
		_beam(Vector3.INF, null)


func primary_held(_delta: float) -> void:
	if _cd <= 0.0:
		_beam(Vector3.INF, null)


func alt_pressed() -> void:
	if _cd <= 0.0:
		_core()


func fire_at(point: Vector3, node: Node3D, force: bool = false) -> bool:
	if _cd > 0.0 and not force:
		return false
	_beam(point, node)
	return true


func _dir_to(point: Vector3) -> Vector3:
	var origin := aim_origin()
	if point != Vector3.INF:
		return (point - origin).normalized()
	return AimAssist.assist(get_tree(), camera, origin, aim_direction())


func _beam(point: Vector3, _node: Node3D) -> void:
	_cd = 0.55
	var origin := aim_origin()
	var dir := _dir_to(point)
	var end := origin + dir * RANGE
	var q := PhysicsRayQueryParameters3D.create(origin, end, MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var hit_pos: Vector3 = hit["position"] if not hit.is_empty() else end
	player.add_recoil(1.8, 0.04)
	Game.sfx(&"whoosh", origin)

	# Shock combo: the beam passes through a live core before reaching its target.
	var reach := origin.distance_to(hit_pos)
	for c in get_tree().get_nodes_in_group("shock_cores"):
		var core := c as Projectile
		if core == null:
			continue
		var t := clampf((core.global_position - origin).dot(dir), 0.0, reach)
		if (origin + dir * t).distance_to(core.global_position) < 1.1:
			_draw_beam(core.global_position)
			core.combo()
			return

	_draw_beam(hit_pos)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	var dmg := BEAM_DAMAGE * Prog.mult("weapon_damage")
	if col is EnemyAI:
		(col as EnemyAI).apply_hit(dir * 16.0 + Vector3.UP * 3.0, hit_pos, &"shock", dmg)
		Game.popup("ZAP!", hit_pos + Vector3.UP * 0.6, Color(0.75, 0.45, 1.0), 0.9)
	elif col is RigidBody3D:
		var rb := col as RigidBody3D
		rb.apply_central_impulse(dir * 14.0 * rb.mass)
		Game.popup("ZAP!", hit_pos + Vector3.UP * 0.4, Color(0.75, 0.45, 1.0), 0.7)
	Fx.confetti(self, hit_pos, 10, 0.4)
	player.add_trauma(0.12, 0.4)


func _core() -> void:
	_cd = 0.8
	var origin := aim_origin()
	var dir := _dir_to(Vector3.INF)
	Projectile.fire(self, &"core", _muzzle.global_position, dir, 24.0)
	player.add_recoil(2.4, 0.06)
	Game.sfx(&"whoosh", origin)


func _draw_beam(to: Vector3) -> void:
	var from := _muzzle.global_position
	var dist := from.distance_to(to)
	if dist < 0.1:
		return
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT
	for layer in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := 0.09 if layer == 0 else 0.035
		bm.size = Vector3(w, w, dist)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.65, 0.35, 1.0, 0.7) if layer == 0 else Color(0.95, 0.95, 1.0, 0.95)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Fx._world(self).add_child(mi)
		mi.global_position = from.lerp(to, 0.5)
		mi.look_at(to, up)
		var tw := mi.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
		tw.tween_callback(mi.queue_free)
