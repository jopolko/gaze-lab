class_name WaveDirector
extends Node
## Endless escalating waves. Every 5th wave is a boss wave. Clearing a boss wave
## advances to the next themed level (see MainLevel.advance_level).

signal wave_started(n: int)
signal wave_cleared(n: int)

@export var autostart: bool = true
@export var first_delay: float = 3.0
@export var intermission: float = 8.0
@export var max_alive: int = 24

var wave: int = 0
var active: bool = false
var level: Node3D

var _queue: Array[StringName] = []
var _spawn_t: float = 0.0
var _timer: float = 3.0


func _ready() -> void:
	add_to_group("director")
	level = get_parent() as Node3D
	_timer = first_delay


func abort_wave() -> void:
	_queue.clear()
	active = false
	_timer = first_delay


func alive() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func remaining() -> int:
	return alive() + _queue.size()


func _process(delta: float) -> void:
	if active:
		_spawn_t -= delta
		if _spawn_t <= 0.0 and not _queue.is_empty() and alive() < max_alive:
			_spawn_t = 0.6
			spawn_enemy(_queue.pop_front())
		if _queue.is_empty() and alive() == 0:
			_clear_wave()
	elif autostart:
		_timer -= delta
		if _timer <= 0.0:
			start_wave()


func start_wave() -> void:
	wave += 1
	active = true
	_queue.clear()
	var boss_wave := wave % 5 == 0
	var budget := 4.0 + wave * 2.5
	if boss_wave:
		budget *= 0.5
		_queue.append(&"boss")
	while budget > 0.0:
		var k := Roster.pick(wave)
		_queue.append(k)
		budget -= float(Roster.get_def(k)["cost"])
	_spawn_t = 0.5
	Game.banner(("WAVE %d  -  BOSS!" % wave) if boss_wave else ("WAVE %d" % wave), Color(1.0, 0.85, 0.3) if not boss_wave else Color(1.0, 0.4, 0.3), 2.2)
	Game.sfx(&"levelup")
	wave_started.emit(wave)


func _clear_wave() -> void:
	active = false
	_timer = intermission
	Prog.best_wave = maxi(Prog.best_wave, wave)
	var coins := Prog.add_coins(10 * wave)
	Prog.add_xp(20 * wave)
	Game.banner("WAVE %d CLEARED!  +%d coins" % [wave, coins], Color(0.5, 1.0, 0.6), 2.4)
	var p := get_tree().get_first_node_in_group("player") as PlayerController
	if p != null:
		p.heal(p.max_hp() * 0.3)
		p.reset_wave_state()
	Prog.save_game()
	wave_cleared.emit(wave)
	if wave % 5 == 0 and level != null and level.has_method("advance_level"):
		_timer = intermission + 2.0
		level.call_deferred("advance_level")


func spawn_enemy(kind: StringName, pos: Vector3 = Vector3.INF) -> EnemyAI:
	var scene: PackedScene = load("res://scenes/Enemy.tscn")
	var e := scene.instantiate() as EnemyAI
	e.kind = kind
	e.hp_scale = 1.0 + 0.1 * (wave - 1)
	e.dmg_scale = 1.0 + 0.05 * (wave - 1)
	if kind == &"waddler":
		e.body_color = Color.from_hsv(randf(), 0.5, 0.95)
	var root: Node = level.get("enemies_root") if level != null and level.get("enemies_root") != null else self
	if pos.is_finite():
		e.position = pos
	elif level != null and level.has_method("random_spawn_point"):
		e.position = level.call("random_spawn_point", 14.0)
	root.add_child(e)
	Fx.confetti(e, e.global_position + Vector3.UP, 20, 0.6)
	return e
