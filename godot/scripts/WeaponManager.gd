class_name WeaponManager
extends Node3D
## Owns every WeaponBase child, handles switching and routes fire input.
## Sits under the player's Camera3D so weapons inherit camera shake/recoil.

signal weapon_changed(weapon: WeaponBase)

var weapons: Array[WeaponBase] = []
var current: int = -1
var player: PlayerController
var camera: Camera3D

var _blocked_until_msec: int = 0
var _prev_fire: bool = false
var _prev_alt: bool = false


func _ready() -> void:
	add_to_group("weapon_manager")
	camera = get_parent() as Camera3D
	var n: Node = get_parent()
	while n != null and not (n is PlayerController):
		n = n.get_parent()
	player = n as PlayerController

	# The two UT99-style guns are built in code. The web/demo build uses only these.
	if Game.demo_mode:
		for c in get_children():
			if c is WeaponBase:
				c.queue_free()
				remove_child(c)
	add_child(ShockRifle.new())
	add_child(RocketLauncher.new())
	for c in get_children():
		if c is WeaponBase:
			var w := c as WeaponBase
			w.setup(player, camera)
			weapons.append(w)
	if Game.demo_mode:
		weapons.sort_custom(func(a: WeaponBase, b: WeaponBase) -> bool: return a is ShockRifle and not (b is ShockRifle))
	if not weapons.is_empty():
		select(0)


func current_weapon() -> WeaponBase:
	if current < 0 or current >= weapons.size():
		return null
	return weapons[current]


func block_input(seconds: float) -> void:
	_blocked_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)


func select(index: int) -> void:
	if weapons.is_empty():
		return
	index = wrapi(index, 0, weapons.size())
	if index == current:
		return
	var old := current_weapon()
	if old:
		old.unequip()
	current = index
	var w := weapons[current]
	w.equip()
	weapon_changed.emit(w)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"weapon_1"):
		select(0)
	elif event.is_action_pressed(&"weapon_2"):
		select(1)
	elif event.is_action_pressed(&"weapon_next"):
		select(current + 1)
	elif event.is_action_pressed(&"weapon_prev"):
		select(current - 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_3 or k == KEY_4:
			select(k - KEY_1)


func _process(delta: float) -> void:
	var w := current_weapon()
	if w == null or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.using_gamepad and not Game.touch_mode):
		return
	if player != null and player.dead:
		w.primary_released()
		w.alt_released()
		return
	if Time.get_ticks_msec() < _blocked_until_msec:
		return
	var down := Game.touch_fire if Game.touch_mode else Input.is_action_pressed(&"fire")
	if down and not _prev_fire:
		w.primary_pressed()
		Game.peek_shot.emit(&"click")
	if down:
		w.primary_held(delta)
	if _prev_fire and not down:
		w.primary_released()
	_prev_fire = down
	var alt := Game.touch_alt if Game.touch_mode else Input.is_action_pressed(&"alt_fire")
	if alt and not _prev_alt:
		w.alt_pressed()
	if alt:
		w.alt_held(delta)
	if _prev_alt and not alt:
		w.alt_released()
	_prev_alt = alt
