class_name WeaponBase
extends Node3D
## Extensible weapon base class. Subclass it, override the virtual hooks, drop
## the scene under the Camera's WeaponManager and it shows up as a new slot.

@export var display_name: String = "Weapon"
@export var equip_time: float = 0.25

var player: PlayerController
var camera: Camera3D
var active: bool = false

var _rest_position: Vector3
var _equip_tween: Tween


## Called once by WeaponManager.
func setup(p_player: PlayerController, p_camera: Camera3D) -> void:
	player = p_player
	camera = p_camera
	_rest_position = position
	visible = false
	set_physics_process(false)


func equip() -> void:
	active = true
	visible = true
	set_physics_process(true)
	position = _rest_position + Vector3(0.0, -0.45, 0.1)
	if _equip_tween:
		_equip_tween.kill()
	_equip_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_equip_tween.tween_property(self, "position", _rest_position, equip_time)
	_on_equip()


func unequip() -> void:
	active = false
	visible = false
	set_physics_process(false)
	if _equip_tween:
		_equip_tween.kill()
	position = _rest_position
	_on_unequip()


# ---- Virtual hooks -------------------------------------------------------
func _on_equip() -> void: pass
func _on_unequip() -> void: pass
func primary_pressed() -> void: pass
func primary_held(_delta: float) -> void: pass
func primary_released() -> void: pass
func alt_pressed() -> void: pass
func alt_held(_delta: float) -> void: pass
func alt_released() -> void: pass
## Hands-free / lock-on firing: shoot at a world point (and optional target node).
## Returns true if a shot was fired. Weapons that can't do this return false.
func fire_at(_point: Vector3, _node: Node3D, _force: bool = false) -> bool: return false
func is_ready() -> bool: return true
## Seconds to keep bullet time running after the last shot of a volley.
var volley_tail: float = 0.4


# ---- Helpers ---------------------------------------------------------------
func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_basis.z


## Ray from the crosshair. Returns {} on a miss.
func raycast(max_dist: float, mask: int) -> Dictionary:
	var from := aim_origin()
	var query := PhysicsRayQueryParameters3D.create(from, from + aim_direction() * max_dist, mask)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)
