class_name EyeDemoIntro
extends Control
## Start screen for the face-control demos. Kept short on purpose: pick a mode, read three lines, press the big
## button. The button is a user gesture, so it can open the camera, go fullscreen and ask for landscape in one tap.
## Sizes scale with orientation / touch so it stays readable on a phone and nothing falls off the bottom
## (the whole panel scrolls if a very short window cannot fit it). The game is paused behind it.

const MODES := {
	6: {"tab": "PEEK", "title": "PEEK & BLAST", "desc": "Lean to peek around cover. Blink to fire.",
		"lines": ["LEAN   peek around the rocks", "LOOK   at a baddy to lock it", "BLINK  fire      WINK  swap gun"],
		"nokeys": "No camera: arrows peek, mouse aims, click fires"},
	7: {"tab": "FLIGHT", "title": "NOD FLIGHT", "desc": "Nod to charge, blast and slam.",
		"lines": ["CHIN DOWN  charge      SNAP UP  blast", "CHIN UP  float      SNAP DOWN  slam", "LEAN   steer"],
		"nokeys": "No camera: W / S chin, arrows lean"},
	8: {"tab": "LANES", "title": "DOWNHILL LANES", "desc": "Your eyes set the line. Read the gates, beat the timing.",
		"lines": ["LOOK  at a gate to set your line", "LEAN  carve      CHIN  tuck, pop, brake", "Some gates open late or slam shut"],
		"nokeys": "No camera: A / D lean, W / S chin, mouse = your eyes"},
	11: {"tab": "DOWNHILL", "title": "DOWNHILL", "desc": "Look where you want to go. Hit jumps for tricks, grab the pickups, reach the finish.",
		"lines": ["LOOK  aside to steer that way", "HOLD your look on a gate to lock it", "In the air: look aside to spin, chin down to grab"],
		"nokeys": "No camera: A / D carve, mouse = your eyes"},
	9: {"tab": "TRANCE", "title": "OCULAR TRANCE", "desc": "Stare to charge. Blink to release.",
		"lines": ["LOOK  at a glowing orb and hold it", "BLINK  to release the shockwave", "Strong motion effects: lower INTENSITY any time"],
		"nokeys": "No camera: mouse = your eyes, SPACE = blink.  - / = intensity, C = calm"},
	10: {"tab": "GAZE TEST", "title": "GAZE TEST", "desc": "See how precisely your eyes land on the screen.",
		"lines": ["LOOK  at each lit dot", "Lines show how far off the tracker was", "R = restart, C = centre"],
		"nokeys": "No camera: the mouse stands in (it should score near zero)"},
	5: {"tab": "EYES", "title": "EYE CONTROL", "desc": "Your face is the controller.",
		"lines": ["EYES   aim", "BLINK  fire      WINK  swap gun", "LEAN   move"],
		"nokeys": "No camera: the mouse or your finger is your eyes"},
}

var _status: Label
var _cam_btn: Button
var _alt_btn: Button
var _title: Label
var _desc: Label
var _lines: Array[Label] = []
var _note: Label
var _mode_btns: Dictionary = {}
var _box: VBoxContainer
var _scroll: ScrollContainer
var _items: Array = []          # [Control, base font size, base min height]
var _u: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = true
	size = get_viewport_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.12, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_box = VBoxContainer.new()
	center.add_child(_box)

	# mode tabs (wrap onto a second row on a narrow screen)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_box.add_child(row)
	for idx: int in [6, 7, 8, 11, 9, 10, 5]:
		var b := Button.new()
		b.text = String(MODES[idx]["tab"])
		b.pressed.connect(_pick.bind(idx))
		row.add_child(b)
		_reg(b, 24, 52.0)
		_mode_btns[idx] = b

	_title = _label(46, Color(1.0, 0.85, 0.3))
	_desc = _label(24, Color(1, 1, 1, 0.92))
	for i in 3:
		var l := _label(22, Color(0.7, 0.95, 1.0))
		_lines.append(l)

	_cam_btn = _button(Color(0.9, 0.3, 0.25), 32, 88.0)
	_cam_btn.pressed.connect(_start.bind(true))
	_alt_btn = _button(Color(0.25, 0.45, 0.8), 22, 60.0)
	_alt_btn.pressed.connect(_start.bind(false))
	_note = _label(17, Color(1, 1, 1, 0.6))
	_status = _label(20, Color(1.0, 0.85, 0.3))
	_refresh()
	_apply_unit()


func _reg(c: Control, font: int, min_h: float = 0.0) -> void:
	_items.append([c, font, min_h])


func _label(font: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	_reg(l, font)
	return l


func _button(color: Color, font: int, min_h: float) -> Button:
	var b := Button.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.15) if state == "hover" else color
		sb.set_corner_radius_all(18)
		sb.border_color = Color.WHITE
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override(state, sb)
	_box.add_child(b)
	_reg(b, font, min_h)
	return b


## Fonts and spacing scale with how the screen is held: big in portrait (the viewport is very wide there, so
## everything shrinks on a phone), a bit bigger on a touch device in landscape.
func _apply_unit() -> void:
	var portrait := size.y > size.x * 1.05
	var u := 2.1 if portrait else (1.3 if Game.touch_mode else 1.0)
	_u = u
	for it in _items:
		var c: Control = it[0]
		if int(it[1]) > 0:
			c.add_theme_font_size_override("font_size", int(float(it[1]) * u))
		if float(it[2]) > 0.0:
			c.custom_minimum_size.y = float(it[2]) * u
	_box.add_theme_constant_override("separation", int(12.0 * u))
	_box.custom_minimum_size.x = minf(size.x * 0.92, 640.0 * u)


func _current_mode() -> int:
	if Game.gaze_test_mode:
		return 10
	if Game.trance_mode:
		return 9
	if Game.run_mode:
		return 11
	if Game.downhill_mode:
		return 8
	if Game.flight_mode:
		return 7
	if Game.peek_mode:
		return 6
	return 5


func _refresh() -> void:
	var m: int = _current_mode()
	var d: Dictionary = MODES[m]
	_title.text = d["title"]
	_desc.text = d["desc"]
	var ls: Array = d["lines"]
	for i in _lines.size():
		_lines[i].text = String(ls[i]) if i < ls.size() else ""
		_lines[i].visible = i < ls.size()
	_cam_btn.text = "START WITH CAMERA"
	_alt_btn.text = "PLAY WITHOUT CAMERA"
	_note.text = String(d["nokeys"]) + "\nThe camera never leaves your device."
	for idx: int in _mode_btns:
		(_mode_btns[idx] as Button).modulate = Color(1, 0.9, 0.4) if idx == m else Color(1, 1, 1, 0.6)


func _pick(idx: int) -> void:
	if idx != _current_mode():
		Game.level_requested.emit(idx)      # MainLevel loads it synchronously (and sets the mode flags)
	_refresh()


func _process(_delta: float) -> void:
	# Child of a CanvasLayer: size ourselves to the viewport so the anchors work.
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
		_apply_unit()
	if _status != null and visible and GazeProvider.camera_status != "":
		_status.text = GazeProvider.camera_status


func _start(with_camera: bool) -> void:
	if with_camera and not OS.has_feature("web"):
		_status.text = "Camera tracking runs in the web build. Using mouse as your eyes."
		with_camera = false
	visible = false
	get_tree().paused = false
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		JavaScriptBridge.eval("(function(){try{if(screen.orientation&&screen.orientation.lock){screen.orientation.lock('landscape').catch(function(){});}}catch(e){}})()")
	if with_camera:
		GazeProvider.start_camera()
	else:
		GazeProvider.set_backend(GazeProvider.Backend.TOUCH if Game.touch_mode else GazeProvider.Backend.MOUSE)
	if Game.peek_mode:
		if not Game.touch_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # mouse aims in the peek level
	elif not Game.flight_mode and not Game.trance_mode and not Game.gaze_test_mode:
		GazeProvider.set_active(true)
	queue_free()
