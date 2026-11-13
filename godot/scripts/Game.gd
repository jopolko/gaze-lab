extends Node
## Autoload "Game": global event bus, collision-mask constants, and runtime
## InputMap registration (so the project works with zero editor setup).
##
## Audio / UI hook-ups: anything can call Game.popup() or Game.sfx(); the
## HitNotifierUI and AudioHooks nodes subscribe to the signals below.

signal popup_requested(text: String, world_pos: Vector3, color: Color, size_scale: float)
signal banner_requested(text: String, color: Color, seconds: float)
signal player_hurt(amount: float)
signal boss_changed(boss_name: String, hp: float, max_hp: float)
signal level_requested(index: int)
signal dh_started(cfg: Dictionary)          # the Downhill menu: go, with these settings
signal sfx_requested(sfx: StringName, world_pos: Vector3)
signal chaos_changed(score: int)
signal pad_changed(using_gamepad: bool)
signal peek_shot(source: StringName)          # a shot fired in the Peek level (for the accuracy numbers)

# Collision *masks* (bit values) for the four physics layers.
const MASK_WORLD := 1    # layer 1
const MASK_PLAYER := 2   # layer 2
const MASK_ENEMY := 4    # layer 3
const MASK_PROPS := 8    # layer 4
const MASK_ALL_ACTORS := MASK_PLAYER | MASK_ENEMY | MASK_PROPS

var chaos: int = 0
## Per-level gravity multiplier (Moonbase = 0.4). Applied to player, enemies and props.
var gravity_scale: float = 1.0
## True once a gamepad was the last device used (switches HUD hints, enables rumble).
var using_gamepad: bool = false
## Touch UI active (phones/tablets, or F7 on desktop). Fire comes from the on-screen button.
var touch_mode: bool = false
var touch_fire: bool = false
var touch_alt: bool = false
## Peek-and-blast level: head lean moves the player out from cover, mouse/keyboard shoot.
var peek_mode: bool = false
## Peek level: aim with the eyes instead of the head. Off by default, so the head-tracked Peek is exactly as it was. In eye mode the gaze is a hint: the game turns the view
## toward it and focuses in on the baddy it points at (peek_eye_look is that turn, yaw / pitch in radians, used in place of the head turn), and the crosshair stays in the middle.
var peek_eye_aim: bool = false
var peek_eye_look: Vector2 = Vector2.ZERO
## Nod-energy flight prototype (level 7): chin down gathers, snap up blasts, snap down slams.
var flight_mode: bool = false
## Downhill run (level 8). Also sets flight_mode so it shares the chin / lean input and touch layout.
var downhill_mode: bool = false
## Downhill (level 11): the free-run version, with trees, gates, pickups, jumps and tricks (the three-lane version is level 8, "Downhill Lanes"). Also sets downhill_mode and flight_mode.
var run_mode: bool = false
## Ocular Trance (level 9): stare to charge, blink to release.
var trance_mode: bool = false
## Gaze test (level 10): measures how precisely the eyes map to the screen.
var gaze_test_mode: bool = false
## Web / --demo builds: one level, no level switching.
var demo_mode: bool = OS.has_feature("web") or OS.get_cmdline_user_args().has("--demo")


func _ready() -> void:
	_register_inputs()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_pad(false)


func _set_pad(on: bool) -> void:
	if on != using_gamepad:
		using_gamepad = on
		pad_changed.emit(on)


## Controller rumble (no-op without a gamepad).
func rumble(weak: float, strong: float, duration: float = 0.15) -> void:
	if using_gamepad and not Input.get_connected_joypads().is_empty():
		Input.start_joy_vibration(Input.get_connected_joypads()[0], clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Spawn a comedic pop-up word at a world position.
func popup(text: String, world_pos: Vector3, color: Color = Color.WHITE, size_scale: float = 1.0) -> void:
	popup_requested.emit(text, world_pos, color, size_scale)


## Big centered announcement ("WAVE 3", "LEVEL UP!").
func banner(text: String, color: Color = Color.WHITE, seconds: float = 2.0) -> void:
	banner_requested.emit(text, color, seconds)


## Request a sound effect. Pass Vector3.INF for a non-positional sound.
func sfx(sfx_name: StringName, world_pos: Vector3 = Vector3.INF) -> void:
	sfx_requested.emit(sfx_name, world_pos)


func add_chaos(amount: int = 1) -> void:
	chaos += amount
	chaos_changed.emit(chaos)


# --------------------------------------------------------------------------
# InputMap (only registers actions that don't already exist in Project Settings)
# --------------------------------------------------------------------------
func _register_inputs() -> void:
	var map: Dictionary = {
		&"move_forward": [_k(KEY_W), _a(JOY_AXIS_LEFT_Y, -1.0)],
		&"move_back": [_k(KEY_S), _a(JOY_AXIS_LEFT_Y, 1.0)],
		&"move_left": [_k(KEY_A), _a(JOY_AXIS_LEFT_X, -1.0)],
		&"move_right": [_k(KEY_D), _a(JOY_AXIS_LEFT_X, 1.0)],
		&"jump": [_k(KEY_SPACE), _b(JOY_BUTTON_A)],
		&"sprint": [_k(KEY_SHIFT), _b(JOY_BUTTON_LEFT_STICK)],
		&"crouch": [_k(KEY_CTRL), _k(KEY_C), _b(JOY_BUTTON_B)],
		&"kick": [_k(KEY_F), _b(JOY_BUTTON_X)],
		&"weapon_1": [_k(KEY_1), _b(JOY_BUTTON_DPAD_LEFT)],
		&"weapon_2": [_k(KEY_2), _b(JOY_BUTTON_DPAD_RIGHT)],
		&"fire": [_m(MOUSE_BUTTON_LEFT), _a(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		&"alt_fire": [_m(MOUSE_BUTTON_RIGHT), _a(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		&"skill_tree": [_k(KEY_TAB), _b(JOY_BUTTON_BACK)],
		&"level_next": [_k(KEY_PAGEDOWN)],
		&"level_prev": [_k(KEY_PAGEUP)],
		&"weapon_next": [_m(MOUSE_BUTTON_WHEEL_DOWN), _k(KEY_Q), _b(JOY_BUTTON_RIGHT_SHOULDER)],
		&"weapon_prev": [_m(MOUSE_BUTTON_WHEEL_UP), _b(JOY_BUTTON_LEFT_SHOULDER)],
		&"look_left": [_a(JOY_AXIS_RIGHT_X, -1.0)],
		&"look_right": [_a(JOY_AXIS_RIGHT_X, 1.0)],
		&"look_up": [_a(JOY_AXIS_RIGHT_Y, -1.0)],
		&"look_down": [_a(JOY_AXIS_RIGHT_Y, 1.0)],
	}
	for action: StringName in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.25)
		for ev: InputEvent in map[action]:
			InputMap.action_add_event(action, ev)


func _k(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func _m(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev


func _a(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _b(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev
