class_name Hazard
extends Area3D
## Banana peel. Whoever steps on it (except its owner) slips: the player
## stumbles and takes a little damage, enemies ragdoll.

var owner_enemy: Node
var _life: float = 25.0


static func make_peel(parent: Node, pos: Vector3, p_owner: Node = null) -> Hazard:
	var h := Hazard.new()
	h.owner_enemy = p_owner
	parent.add_child(h)
	h.global_position = pos
	return h


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.MASK_PLAYER | Game.MASK_ENEMY
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.7
	cs.shape = sh
	cs.position.y = 0.2
	add_child(cs)
	var yellow := Color(1.0, 0.9, 0.15)
	for i in 3:
		Roster.mi(self, Roster.box(Vector3(0.55, 0.04, 0.22)), Vector3(0, 0.05, 0), yellow, Vector3(0, i * 120.0, 8), 0.4)
	Roster.mi(self, Roster.sphere(0.12, 0.5), Vector3(0, 0.08, 0), Color(0.9, 0.75, 0.1))
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(b: Node3D) -> void:
	if b == owner_enemy:
		return
	if b is PlayerController:
		(b as PlayerController).slip()
	elif b is EnemyAI:
		var e := b as EnemyAI
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		e.apply_hit(dir * 14.0 + Vector3.UP * 9.0, global_position, &"hazard", 12.0)
	else:
		return
	Game.popup("SLIP!", global_position + Vector3.UP * 1.5, Color(1.0, 0.95, 0.3))
	Game.sfx(&"squeak", global_position)
	queue_free.call_deferred()
