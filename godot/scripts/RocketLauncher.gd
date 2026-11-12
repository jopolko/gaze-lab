class_name RocketLauncher
extends WeaponBase
## UT99-style Rocket Launcher.
##   primary : one rocket. Soft homing on the assisted target for touch / gaze.
##   alt     : HOLD to load up to 6 rockets, release to fire them in a fan.
## Built entirely from primitives; no art assets.

const SPEED := 30.0
const MAX_LOAD := 6
const LOAD_TIME := 0.5

var _cd: float = 0.0
var _loading: bool = false
var _loaded: int = 0
var _load_t: float = 0.0
var _muzzle: Node3D


func _ready() -> void:
	display_name = "Rocket Launcher"
	volley_tail = 1.2
	position = Vector3(0.24, -0.24, -0.4)
	Roster.mi(self, Roster.cyl(0.1, 0.1, 0.8), Vector3(0, 0, -0.1), Color(0.35, 0.4, 0.3), Vector3(90, 0, 0))
	Roster.mi(self, Roster.cyl(0.13, 0.1, 0.12), Vector3(0, 0, -0.52), Color(0.25, 0.28, 0.22), Vector3(90, 0, 0))
	Roster.mi(self, Roster.box(Vector3(0.1, 0.16, 0.14)), Vector3(0, -0.14, 0.05), Color(0.2, 0.2, 0.22))
	Roster.mi(self, Roster.cyl(0.0, 0.06, 0.12), Vector3(0, 0, -0.62), Color(0.95, 0.25, 0.15), Vector3(-90, 0, 0), 1.0)
	Roster.mi(self, Roster.torus(0.09, 0.13), Vector3(0, 0, 0.2), Color(1.0, 0.8, 0.2), Vector3(90, 0, 0), 1.0)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -0.66)
	add_child(_muzzle)


func _on_unequip() -> void:
	_loading = false
	_loaded = 0


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)


func is_ready() -> bool:
	return _cd <= 0.0


func primary_pressed() -> void:
	if _cd <= 0.0 and not _loading:
		_launch(_assisted_dir(), _assist_target())
		_cd = 0.8


func primary_held(_delta: float) -> void:
	primary_pressed()


func alt_pressed() -> void:
	if _cd > 0.0:
		return
	_loading = true
	_loaded = 1
	_load_t = 0.0
	Game.popup("x1", _muzzle.global_position, Color(1.0, 0.7, 0.2), 0.5)


func alt_held(delta: float) -> void:
	if not _loading or _loaded >= MAX_LOAD:
		return
	_load_t += delta
	if _load_t >= LOAD_TIME:
		_load_t = 0.0
		_loaded += 1
		Game.sfx(&"pop", _muzzle.global_position)
		Game.popup("x%d" % _loaded, _muzzle.global_position + Vector3.UP * 0.2, Color(1.0, 0.7, 0.2), 0.5 + 0.1 * _loaded)


func alt_released() -> void:
	if not _loading:
		return
	_loading = false
	var n := _loaded
	_loaded = 0
	var base := _assisted_dir()
	var tgt := _assist_target()
	var right := base.cross(Vector3.UP).normalized()
	var spread := deg_to_rad(2.5 + 1.2 * n)
	for i in n:
		var f := 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5) * 2.0
		var d := (base + right * f * spread).normalized()
		if i == 0:
			_launch(d, tgt)
		else:
			get_tree().create_timer(0.07 * i).timeout.connect(_launch.bind(d, tgt))
	_cd = 1.0


func fire_at(point: Vector3, node: Node3D, force: bool = false) -> bool:
	if _cd > 0.0 and not force:
		return false
	var dir := (point - aim_origin()).normalized()
	_launch(dir, node)
	_cd = 0.8
	return true


func _assisted_dir() -> Vector3:
	return AimAssist.assist(get_tree(), camera, aim_origin(), aim_direction())


func _assist_target() -> Node3D:
	var r := AimAssist.find(get_tree(), camera, aim_origin(), aim_direction())
	return r.get("node") as Node3D


func _launch(dir: Vector3, target: Node3D) -> void:
	if player == null or not is_instance_valid(self) or not is_inside_tree():
		return
	# Imprecise inputs (touch / gaze) get soft homing; mouse players aim for real.
	var homing := 0.0 if AimAssist.cone_deg() <= AimAssist.CONE_MOUSE + 0.01 else 1.6
	Projectile.fire(self, &"rocket", _muzzle.global_position, dir, SPEED, target, homing)
	player.add_recoil(3.0, 0.08)
	player.add_trauma(0.2, 0.5)
	Game.sfx(&"whoosh", aim_origin())
