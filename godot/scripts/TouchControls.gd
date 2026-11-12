class_name TouchControls
extends Control
## On-screen controls for phones/tablets (also testable on desktop with F7).
##   left side  : floating thumb-stick (move; pushing to the edge sprints)
##   right side : drag to look (or, in hands-free mode, your finger IS your gaze)
##   buttons    : FIRE, JUMP, KICK, SLIDE, weapon swap, EYES (hands-free), skills
## Everything is drawn in code. Shows itself only on touch devices (or after F7).

const STICK_R := 95.0
const DEAD := 0.15
const LOOK_SENS := 0.0042

# id, label, x frac, y frac, radius
const BUTTONS := [
	["fire", "FIRE", 0.91, 0.66, 66.0],
	["jump", "JUMP", 0.80, 0.84, 48.0],
	["kick", "KICK", 0.78, 0.58, 44.0],
	["slide", "SLIDE", 0.66, 0.84, 40.0],
	["weapon", "SWAP", 0.66, 0.60, 32.0],
	["alt", "ALT", 0.93, 0.47, 38.0],
	["eyes", "EYES", 0.93, 0.30, 36.0],
	["cam", "CAM", 0.93, 0.13, 32.0],
	["menu", "SKILLS", 0.07, 0.10, 34.0],
]

# Demo layout: just what the eye-control demo needs, big and colourful.
const DEMO_BUTTONS := [
	["fire", "BLINK", 0.87, 0.68, 100.0],
	["weapon", "WINK", 0.66, 0.82, 74.0],
	["center", "CENTER", 0.93, 0.17, 48.0],
	["cam", "CAM", 0.30, 0.88, 46.0],
]

# Peek level: hold to lean (a fallback when the camera is slow or unavailable)
const PEEK_EXTRA := [
	["peekl", "< LEAN", 0.10, 0.80, 58.0],
	["peekr", "LEAN >", 0.27, 0.80, 58.0],
]
const PEEK_EXTRA_PORTRAIT := [
	["peekl", "< LEAN", 0.16, 0.74, 56.0],
	["peekr", "LEAN >", 0.40, 0.74, 56.0],
]
# Flight: GATHER (hold = chin down; releasing it is the snap-up blast), FLOAT (hold = chin up), SLAM (tap)
const FLIGHT_BUTTONS := [
	["gather", "GATHER", 0.16, 0.76, 84.0],
	["float", "FLOAT", 0.84, 0.76, 84.0],
	["slam", "SLAM", 0.50, 0.84, 62.0],
	["center", "CENTER", 0.93, 0.17, 48.0],
	["cam", "CAM", 0.30, 0.90, 46.0],
]
const TRANCE_BUTTONS := [
	["fire", "BLINK", 0.84, 0.76, 84.0],
	["center", "CENTER", 0.93, 0.17, 48.0],
	["cam", "CAM", 0.30, 0.90, 46.0],
]
const TRANCE_PORTRAIT := [
	["fire", "BLINK", 0.78, 0.84, 78.0],
	["center", "CENTER", 0.90, 0.07, 46.0],
	["cam", "CAM", 0.20, 0.94, 44.0],
]
const FLIGHT_PORTRAIT := [
	["gather", "GATHER", 0.22, 0.84, 78.0],
	["float", "FLOAT", 0.78, 0.84, 78.0],
	["slam", "SLAM", 0.50, 0.70, 58.0],
	["center", "CENTER", 0.90, 0.07, 46.0],
	["cam", "CAM", 0.20, 0.94, 44.0],
]

const DEMO_PORTRAIT := [
	["fire", "BLINK", 0.80, 0.88, 100.0],
	["weapon", "WINK", 0.50, 0.92, 70.0],
	["center", "CENTER", 0.90, 0.07, 46.0],
	["cam", "CAM", 0.20, 0.90, 46.0],
]

var _auto_cam: float = 0.0
var _auto_eyes: float = 0.0        # ?eyes in the URL starts hands-free after a moment
var _forced: bool = false          # F7 on desktop: mouse acts as a finger
var _stick_id: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _look_id: int = -1
var _look_start: Vector2 = Vector2.ZERO
var _btn_touch: Dictionary = {}    # finger index -> button id
var _held: Dictionary = {}         # button id -> true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if OS.has_feature("web"):
		var coarse: Variant = JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches")
		var q := str(JavaScriptBridge.eval("window.location.search"))
		if bool(coarse) or q.contains("touch"):
			Game.touch_mode = true
		if q.contains("eyes"):
			_auto_eyes = 1.5
		if q.contains("cam"):
			_auto_cam = 1.5
	visible = Game.touch_mode


func _exit_tree() -> void:
	_release_all()


func _player() -> PlayerController:
	return get_tree().get_first_node_in_group("player") as PlayerController


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F7:
		_forced = not _forced
		Game.touch_mode = _forced
		if not _forced:
			_release_all()
		return
	if get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if not Game.touch_mode:
			Game.touch_mode = true
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_move(d.index, d.position, d.relative)
	elif _forced and event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := event as InputEventMouseButton
		if m.pressed:
			_press(99, m.position)
		else:
			_release(99)
	elif _forced and event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		var mm := event as InputEventMouseMotion
		_move(99, mm.position, mm.relative)


func _layout() -> Array:
	var portrait := size.y > size.x * 1.05
	if Game.demo_mode:
		if (Game.trance_mode or Game.gaze_test_mode):
			return TRANCE_PORTRAIT if portrait else TRANCE_BUTTONS
		if Game.flight_mode:
			return FLIGHT_PORTRAIT if portrait else FLIGHT_BUTTONS
		var base: Array = DEMO_PORTRAIT if portrait else DEMO_BUTTONS
		if Game.peek_mode:
			return base + (PEEK_EXTRA_PORTRAIT if portrait else PEEK_EXTRA)
		return base
	return BUTTONS


func _button_pos(b: Array) -> Vector2:
	return Vector2(size.x * float(b[2]), size.y * float(b[3]))


func _press(index: int, pos: Vector2) -> void:
	for b: Array in _layout():
		if _button_hidden(b[0]):
			continue
		if pos.distance_to(_button_pos(b)) <= float(b[4]) * 1.25:
			_btn_touch[index] = b[0]
			_btn_down(b[0])
			return
	if pos.x < size.x * 0.45 and not (Game.peek_mode or Game.flight_mode or (Game.trance_mode or Game.gaze_test_mode)):
		if _stick_id == -1:
			_stick_id = index
			_stick_origin = pos
			_stick_pos = pos
	elif _look_id == -1:
		_look_id = index
		_look_start = pos
		if GazeProvider.active:
			GazeProvider.touch_gaze = (pos / size).clamp(Vector2.ZERO, Vector2.ONE)


func _move(index: int, pos: Vector2, rel: Vector2) -> void:
	if index == _stick_id:
		_stick_pos = pos
		_apply_stick()
	elif index == _look_id:
		if Game.flight_mode:
			GazeProvider.touch_steer = clampf((pos.x - _look_start.x) / 140.0, -1.0, 1.0)
		elif GazeProvider.active:
			GazeProvider.touch_gaze = (pos / size).clamp(Vector2.ZERO, Vector2.ONE)
		else:
			var p := _player()
			if p != null and not p.dead:
				p.rotate_y(-rel.x * LOOK_SENS)
				p.head.rotation.x = clampf(p.head.rotation.x - rel.y * LOOK_SENS, -1.5, 1.5)


func _release(index: int) -> void:
	if _btn_touch.has(index):
		_btn_up(_btn_touch[index])
		_btn_touch.erase(index)
	if index == _stick_id:
		_stick_id = -1
		_set_move(Vector2.ZERO)
	if index == _look_id:
		_look_id = -1
		GazeProvider.touch_steer = 0.0


func _release_all() -> void:
	for id: String in _held.keys():
		_btn_up(id)
	_btn_touch.clear()
	_stick_id = -1
	_look_id = -1
	_set_move(Vector2.ZERO)


func _apply_stick() -> void:
	var v := (_stick_pos - _stick_origin) / STICK_R
	if v.length() > 1.0:
		_stick_origin += (v - v.normalized()) * STICK_R   # drag the base along (floating stick)
		v = v.normalized()
	if v.length() < DEAD:
		v = Vector2.ZERO
	_set_move(v)


func _set_move(v: Vector2) -> void:
	_axis(&"move_forward", maxf(-v.y, 0.0))
	_axis(&"move_back", maxf(v.y, 0.0))
	_axis(&"move_left", maxf(-v.x, 0.0))
	_axis(&"move_right", maxf(v.x, 0.0))
	_axis(&"sprint", 1.0 if v.length() > 0.92 else 0.0)


func _axis(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _button_hidden(id: String) -> bool:
	if Game.flight_mode and (id == "fire" or id == "weapon"):
		return true
	# In hands-free mode keep only what's useful: fire(blink), jump, kick, eyes.
	if id == "cam":
		if not OS.has_feature("web"):
			return true
		if Game.demo_mode:
			return GazeProvider.head_rpy_ok and GazeProvider._camera_fresh()   # only shown while the camera is not tracking
	return GazeProvider.active and (id == "slide" or id == "menu" or id == "alt")


func _btn_down(id: String) -> void:
	_held[id] = true
	match id:
		"fire":
			if GazeProvider.active:
				GazeProvider.blinked.emit()
			else:
				Game.touch_fire = true
		"jump":
			Input.action_press(&"jump")
		"kick":
			Input.action_press(&"kick")
		"slide":
			Input.action_press(&"crouch")
		"weapon":
			if GazeProvider.active:
				GazeProvider.winked.emit(true)   # hands-free: the SWAP button stands in for a wink
			else:
				_tap(&"weapon_next")
		"alt":
			Game.touch_alt = true
		"cam":
			toggle_camera()
		"peekl":
			GazeProvider.touch_lean = -1.0
		"peekr":
			GazeProvider.touch_lean = 1.0
		"gather":
			GazeProvider.touch_nod_goal = -1.0
		"float":
			GazeProvider.touch_nod_goal = 1.0
		"slam":
			GazeProvider.touch_nod_goal = -1.0           # a fast chin drop
			get_tree().create_timer(0.22).timeout.connect(func() -> void: GazeProvider.touch_nod_goal = 0.0)
		"center":
			GazeProvider.recentre()
			Game.banner("Centered", Color(0.5, 1.0, 0.6), 1.0)
		"menu":
			_tap(&"skill_tree")
		"eyes":
			toggle_hands_free()


func _btn_up(id: String) -> void:
	_held.erase(id)
	match id:
		"fire":
			Game.touch_fire = false
		"jump":
			Input.action_release(&"jump")
		"kick":
			Input.action_release(&"kick")
		"slide":
			Input.action_release(&"crouch")
		"alt":
			Game.touch_alt = false
		"peekl", "peekr":
			GazeProvider.touch_lean = 0.0
		"gather", "float":
			GazeProvider.touch_nod_goal = 0.0


func toggle_camera() -> void:
	if Game.peek_mode:
		GazeProvider.start_camera()                # (re)start head tracking; no hands-free mode in the peek level
		return
	if GazeProvider.active and GazeProvider.backend == GazeProvider.Backend.CAMERA:
		GazeProvider.set_active(false)
	else:
		GazeProvider.start_camera()
		GazeProvider.set_active(true)


func toggle_hands_free() -> void:
	if GazeProvider.active:
		GazeProvider.set_active(false)
	else:
		GazeProvider.set_backend(GazeProvider.Backend.TOUCH)
		GazeProvider.set_active(true)


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _auto_cam > 0.0:
		_auto_cam -= delta
		if _auto_cam <= 0.0:
			toggle_camera()
	if _auto_eyes > 0.0:
		_auto_eyes -= delta
		if _auto_eyes <= 0.0 and not GazeProvider.active:
			toggle_hands_free()
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	if visible != Game.touch_mode:
		visible = Game.touch_mode
	if visible:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var hf := GazeProvider.active
	# stick
	var portrait := size.y > size.x * 1.05
	var base := _stick_origin if _stick_id != -1 else (Vector2(size.x * 0.22, size.y * 0.86) if portrait else Vector2(size.x * 0.15, size.y * 0.72))
	var knob := _stick_pos if _stick_id != -1 else base
	knob = base + (knob - base).limit_length(STICK_R)
	if not (Game.peek_mode or Game.flight_mode or (Game.trance_mode or Game.gaze_test_mode)):
		draw_circle(base, STICK_R, Color(0.1, 0.1, 0.2, 0.35))
		draw_arc(base, STICK_R, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 4.0)
		draw_circle(knob, 42.0, Color(1, 1, 1, 0.45 if _stick_id == -1 else 0.75))
		if _stick_id == -1:
			_text(font, base + Vector2(-34, -STICK_R - 14), "MOVE", 24)
	# touch-as-eyes hint (only when no camera is driving the aim)
	if hf and _look_id == -1 and GazeProvider.backend == GazeProvider.Backend.TOUCH:
		_text(font, Vector2(size.x * 0.34, size.y * 0.93), "touch the right side = where you LOOK", 22)
	elif Game.peek_mode and _look_id == -1:
		_text(font, Vector2(size.x * 0.30, size.y * 0.80), "drag anywhere to AIM  |  lean / turn your head to PEEK", 20)
	elif not hf and _look_id == -1 and not Game.demo_mode:
		_text(font, Vector2(size.x * 0.46, size.y * 0.9), "drag here to LOOK", 20)
	# buttons: big, solid, colour-coded
	for b: Array in _layout():
		var id: String = b[0]
		if _button_hidden(id):
			continue
		var c := _button_pos(b)
		var r := float(b[4])
		var down := _held.has(id)
		var col := Color(1, 1, 1)
		match id:
			"fire":
				col = Color(0.95, 0.25, 0.22)
			"weapon":
				col = Color(0.25, 0.5, 0.95)
			"center":
				col = Color(0.2, 0.7, 0.4)
			"alt", "slam":
				col = Color(0.9, 0.6, 0.15)
			"gather":
				col = Color(0.3, 0.5, 1.0)
			"float":
				col = Color(0.25, 0.8, 0.45)
			"peekl", "peekr":
				col = Color(0.95, 0.75, 0.2)
			"eyes", "cam":
				col = Color(0.2, 0.75, 0.85)
		draw_circle(c, r, Color(col, 0.85 if down else 0.55))
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.95), 5.0)
		var label: String = String(b[1])
		if Game.peek_mode and Game.demo_mode:
			label = {"fire": "FIRE", "weapon": "SWAP", "center": "CENTER"}.get(id, label)
		if not Game.demo_mode:
			if id == "fire" and hf:
				label = "BLINK"
			elif id == "weapon" and hf:
				label = "WINK"
			elif id == "eyes" and hf:
				label = "EXIT"
			elif id == "cam" and hf and GazeProvider.backend == GazeProvider.Backend.CAMERA:
				label = "CAM ON"
		var fs := 34 if r > 80.0 else (26 if r > 50.0 else 18)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_text(font, c + Vector2(-w * 0.5, fs * 0.35), label, fs)

func _text(font: Font, pos: Vector2, text: String, fs: int) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
