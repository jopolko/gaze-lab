class_name Fx
extends RefCounted
## Static helpers for juicy effects: confetti bursts and radial shockwaves.


static func _world(ctx: Node) -> Node:
	var tree := ctx.get_tree()
	return tree.current_scene if tree.current_scene != null else tree.root


static func confetti(ctx: Node, pos: Vector3, amount: int = 60, size: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3 * size
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0 * size
	p.initial_velocity_max = 9.0 * size
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color.RED, Color.YELLOW, Color(0.3, 1, 0.4), Color(0.3, 0.7, 1), Color(1, 0.4, 0.9)])
	p.color_initial_ramp = g
	var m := BoxMesh.new()
	m.size = Vector3(0.09, 0.09, 0.02) * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	_world(ctx).add_child(p)
	p.global_position = pos
	p.emitting = true
	ctx.get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Radial blast. Launches props, damages/launches enemies, optionally hurts the player.
## `source` &"hazard" damage is not boosted by player damage skills.
static func shockwave(ctx: Node, pos: Vector3, radius: float, force: float, damage: float,
		hurt_player: bool, hurt_enemies: bool, source: StringName = &"shockwave", exclude: Node = null,
		ring_color: Color = Color(1.0, 0.9, 0.5, 0.45)) -> void:
	_ring(ctx, pos, radius, ring_color)
	Game.sfx(&"boom", pos)
	for n in ctx.get_tree().get_nodes_in_group("props"):
		var rb := n as RigidBody3D
		if rb == null:
			continue
		var off := rb.global_position - pos
		var d := off.length()
		if d > radius:
			continue
		var fall := 1.0 - d / radius
		var dir := (off.normalized() + Vector3.UP * 0.5).normalized()
		rb.apply_central_impulse(dir * force * fall * rb.mass)
	if hurt_enemies:
		for n in ctx.get_tree().get_nodes_in_group("enemies"):
			var e := n as EnemyAI
			if e == null or e == exclude:
				continue
			var off := (e.global_position + Vector3.UP) - pos
			var d := off.length()
			if d > radius:
				continue
			var fall := 1.0 - d / radius
			var dir := (off.normalized() + Vector3.UP * 0.4).normalized()
			e.apply_hit(dir * force * fall, e.global_position, source, damage * fall)
	if hurt_player:
		var p := ctx.get_tree().get_first_node_in_group("player") as PlayerController
		if p != null:
			var off := (p.global_position + Vector3.UP) - pos
			var d := off.length()
			if d <= radius:
				var fall := 1.0 - d / radius
				var dir := (off.normalized() + Vector3.UP * 0.5).normalized()
				p.take_damage(damage * fall, pos, dir * force * 0.5 * fall)


static func _ring(ctx: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.9, 0.5, 0.45)) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	s.material = mat
	mi.mesh = s
	_world(ctx).add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)
