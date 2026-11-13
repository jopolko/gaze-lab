class_name DownhillMenu
extends Control
## The pre-run screen for Downhill: a live 3D backdrop that drifts slowly behind glass cards, one column on a phone held upright, two on a wide screen,
## with the start buttons always on screen at the bottom. The game is paused behind it. Everything chosen here is remembered, and the course can be shared as a link.
## Sizes are in the game's canvas units (1280 wide in landscape, 1280 across the SHORT side in portrait), so `_u` scales them up for a phone held upright.

const SAVE := "user://downhill_menu.cfg"
const PRESET_NAMES := {"classic": "CLASSIC", "alpine": "ALPINE RUSH", "meadow": "MEADOWS", "canyon": "CANYON", "chaos": "CHAOS", "endless": "ENDLESS"}
const ZONE_LABELS := {"rush": "STEEP RUSH", "flat": "MEADOW", "tunnel": "TUNNEL", "bend": "BEND", "air": "SKY RAMP", "forest": "DENSE FOREST", "drop": "CLIFF DROP"}

var cfg: Dictionary = {
	"theme": "alpine", "preset": "classic", "diff": 1.0, "length_km": 4.2, "endless": false, "seed": 0,
	"zones": {"rush": 1.0, "flat": 1.0, "tunnel": 1.0, "bend": 1.0, "air": 1.0, "forest": 1.0, "drop": 1.0},
	"faces": true, "cine": true, "phone": true, "haptics": true, "dynlight": true, "snow": true, "fluffy": false, "vehicle": false, "gps": false, "speed_first": false, "assist": 0.7, "intensity": 0.8,
}

var _bg: ThemeBackdrop
var _grid: GridContainer
var _scroll: ScrollContainer
var _footer: BoxContainer
var _root: VBoxContainer
var _margin: MarginContainer
var _title: Label
var _sub: Label
var _more: Button
var _cards: Array[PanelContainer] = []
var _texts: Array = []                 # [Control, base font size]
var _boxes: Array = []                 # [Control, base min size]
var _theme_btns: Dictionary = {}
var _preset_btns: Dictionary = {}
var _blurb: Label
var _diff_s: HSlider
var _diff_l: Label
var _len_s: HSlider
var _len_l: Label
var _end_b: Button
var _seed_e: LineEdit
var _zone_s: Dictionary = {}
var _zone_l: Dictionary = {}
var _toggles: Dictionary = {}
var _int_s: HSlider
var _assist_s: HSlider
var _assist_l: Label
var _int_l: Label
var _int_row: Control
var _status: Label
var _reports_l: Label
var _cam_btn: Button
var _alt_btn: Button
var _u: float = 1.0
var _cols: int = -1
var _last_vs: Vector2 = Vector2.ZERO
var _accent: Color = Color(1.0, 0.85, 0.3)
var _building: bool = true
var _grabber: ImageTexture
var _grabber_hi: ImageTexture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = true
	size = get_viewport_rect().size
	_load()
	_url_overrides()
	_bg = ThemeBackdrop.new()
	_bg.theme_id = String(cfg["theme"])
	_bg.intensity = float(cfg["intensity"])
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# a soft dark wash so text always reads, strongest at the bottom where the buttons are
	var gs := Gradient.new()
	gs.set_color(0, Color(0.02, 0.03, 0.08, 0.35))
	gs.set_color(1, Color(0.02, 0.03, 0.08, 0.80))
	var gt := GradientTexture2D.new()
	gt.gradient = gs
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_root = VBoxContainer.new()
	_margin.add_child(_root)
	_build_header()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_build_theme_card()
	_build_course_card()
	_build_mix_card()
	_build_experience_card()
	_build_reports_card()
	_build_footer()
	_building = false
	_sync_widgets()
	_last_vs = get_viewport_rect().size
	_apply_unit(true)
	# the welcome screen: shown over the settings until a tap (add nosplash to the address to skip it)
	var skip := OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("nosplash")
	if not skip:
		var sp := SplashView.new()
		add_child(sp)
		_margin.visible = false
		sp.done.connect(func() -> void:
			sp.queue_free()
			_margin.visible = true)


# ---------------------------------------------------------------- pieces
func _label(text: String, font: int, color: Color, parent: Node, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	_texts.append([l, font])
	return l


func _style(bg: Color, border: Color, radius: int, bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _card(title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var csb := _style(Color(0.04, 0.05, 0.12, 0.66), Color(_accent.r, _accent.g, _accent.b, 0.28), 16, 1)
	csb.shadow_color = Color(0, 0, 0, 0.35)
	csb.shadow_size = 10
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	csb.content_margin_top = 14
	csb.content_margin_bottom = 14
	pc.add_theme_stylebox_override("panel", csb)
	_grid.add_child(pc)
	_cards.append(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	_label(title, 17, Color(_accent.r, _accent.g, _accent.b, 0.95), vb)
	var hr := HSeparator.new()
	var hs := _style(Color(_accent.r, _accent.g, _accent.b, 0.35), Color(0, 0, 0, 0), 0)
	hs.content_margin_left = 0
	hs.content_margin_right = 0
	hs.content_margin_top = 0
	hs.content_margin_bottom = 0
	hr.add_theme_stylebox_override("separator", hs)
	hr.add_theme_constant_override("separation", 2)
	vb.add_child(hr)
	return vb


func _button(text: String, font: int, parent: Node, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.20), 12, 1))
	b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.38), 12, 1))
	b.add_theme_stylebox_override("pressed", _style(Color(_accent.r, _accent.g, _accent.b, 0.26), _accent, 12, 2))
	b.add_theme_stylebox_override("hover_pressed", _style(Color(_accent.r, _accent.g, _accent.b, 0.34), _accent, 12, 2))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1, 1))
	parent.add_child(b)
	_texts.append([b, font])
	_boxes.append([b, 0.0, 52.0])
	return b


func _flow(parent: Node) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.alignment = FlowContainer.ALIGNMENT_BEGIN
	parent.add_child(f)
	_boxes.append([f, 0.0, 0.0])
	return f


func _grabber_tex(r: int, c: Color) -> ImageTexture:
	var s := r * 2 + 4
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(float(x) - float(s) * 0.5 + 0.5, float(y) - float(s) * 0.5 + 0.5).length()
			var a := clampf(float(r) - d + 0.5, 0.0, 1.0)
			var ring := clampf(float(r) - d - 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a).lerp(Color(1, 1, 1, a), 1.0 - ring))
	return ImageTexture.create_from_image(img)


func _slider(parent: Node, lo: float, hi: float, step: float, label_text: String) -> Array:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var l := _label(label_text, 20, Color(1, 1, 1, 0.9), row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	if _grabber == null:
		_grabber = _grabber_tex(22, Color(_accent.r, _accent.g, _accent.b, 1.0))
	s.add_theme_icon_override("grabber", _grabber)
	s.add_theme_icon_override("grabber_highlight", _grabber)
	s.add_theme_icon_override("grabber_disabled", _grabber)
	var track := _style(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 12)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	s.add_theme_stylebox_override("slider", track)
	var fill := _style(Color(_accent.r, _accent.g, _accent.b, 0.7), Color(0, 0, 0, 0), 12)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	row.add_child(s)
	_boxes.append([s, 0.0, 46.0])
	return [s, l]


func _build_header() -> void:
	var h := HBoxContainer.new()
	_root.add_child(h)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tb)
	_title = _label("DOWNHILL", 52, Color(1.0, 0.9, 0.4), tb)
	_sub = _label("Steer with your eyes. Pick effects and a course, then go.", 20, Color(1, 1, 1, 0.7), tb)
	_more = _button("DEMOS", 18, h)
	_more.pressed.connect(_other_games)


func _build_theme_card() -> void:
	var c := _card("EFFECTS  (colours, sky, scenery and screen effects)")
	var f := _flow(c)
	var grp := ButtonGroup.new()
	for id in Themes.ORDER:
		var d := Themes.theme_data(id)
		var b := _button(String(d["name"]), 22, f, true)
		b.button_group = grp
		var c1: Color = d["c1"]
		var c2: Color = d["c2"]
		b.add_theme_stylebox_override("normal", _style(Color(c1.r, c1.g, c1.b, 0.18), Color(c1.r, c1.g, c1.b, 0.5), 12, 1))
		b.add_theme_stylebox_override("hover", _style(Color(c1.r, c1.g, c1.b, 0.30), c1, 12, 1))
		b.add_theme_stylebox_override("pressed", _style(Color(c1.r, c1.g, c1.b, 0.50), c2, 12, 3))
		b.add_theme_stylebox_override("hover_pressed", _style(Color(c1.r, c1.g, c1.b, 0.56), c2, 12, 3))
		b.pressed.connect(_pick_theme.bind(id))
		_theme_btns[id] = b
		_boxes.append([b, 190.0, 64.0])
	_blurb = _label("", 20, Color(1, 1, 1, 0.8), c)
	var r := _slider(c, 0.0, 1.5, 0.05, "EFFECT INTENSITY")
	_int_s = r[0]
	_int_l = r[1]
	_int_row = _int_s.get_parent()
	_int_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["intensity"] = v
		_bg.set_intensity(v)
		_sync_labels())


func _build_course_card() -> void:
	var c := _card("COURSE")
	var f := _flow(c)
	var grp := ButtonGroup.new()
	grp.allow_unpress = true
	for id in Game_presets():
		var b := _button(String(PRESET_NAMES[id]), 20, f, true)
		b.button_group = grp
		b.pressed.connect(_pick_preset.bind(id))
		_preset_btns[id] = b
		_boxes.append([b, 190.0, 56.0])
	var d := _slider(c, 0.5, 1.6, 0.05, "")
	_diff_s = d[0]
	_diff_l = d[1]
	_diff_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["diff"] = v
		_custom()
		_sync_labels())
	var ln := _slider(c, 1.0, 12.0, 0.2, "")
	_len_s = ln[0]
	_len_l = ln[1]
	_len_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["length_km"] = v
		cfg["endless"] = false
		_custom()
		_sync_labels())
	_end_b = _button("ENDLESS", 20, c, true)
	_end_b.toggled.connect(func(on: bool) -> void:
		if _building:
			return
		cfg["endless"] = on
		_custom()
		_sync_labels())
	var sr := HBoxContainer.new()
	c.add_child(sr)
	var seed_l := _label("SEED  ", 20, Color(1, 1, 1, 0.9), sr)
	seed_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_seed_e = LineEdit.new()
	_seed_e.placeholder_text = "random"
	_seed_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_e.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.25), 14, 2))
	_seed_e.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0.5), _accent, 14, 3))
	_seed_e.text_changed.connect(func(t: String) -> void:
		cfg["seed"] = int(t) if t.is_valid_int() else 0)
	sr.add_child(_seed_e)
	_texts.append([_seed_e, 22])
	_boxes.append([_seed_e, 0.0, 56.0])
	var roll := _button("ROLL", 20, sr)
	roll.pressed.connect(func() -> void:
		cfg["seed"] = randi_range(1000, 999999)
		_seed_e.text = str(cfg["seed"]))
	var share := _button("COPY LINK", 20, sr)
	share.pressed.connect(_copy_link)


func _build_mix_card() -> void:
	var c := _card("WORLD MIX  (what the gates lead to)")
	for z in ["rush", "flat", "tunnel", "bend", "air", "forest", "drop"]:
		var r := _slider(c, 0.0, 3.0, 0.1, "")
		_zone_s[z] = r[0]
		_zone_l[z] = r[1]
		(r[0] as HSlider).value_changed.connect(func(v: float) -> void:
			if _building:
				return
			(cfg["zones"] as Dictionary)[z] = v
			_custom()
			_sync_labels())


func _build_experience_card() -> void:
	var c := _card("EXPERIENCE")
	var ar := _slider(c, 0.0, 1.0, 0.05, "")
	_assist_s = ar[0]
	_assist_l = ar[1]
	_assist_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["assist"] = v
		_sync_labels())
	var f := _flow(c)
	for t in [["faces", "FACE CHALLENGES"], ["cine", "CINEMATIC JUMPS"], ["dynlight", "DYNAMIC LIGHT"], ["snow", "SNOWFALL"], ["fluffy", "FLUFFY SHAPES"], ["phone", "PHONE STABILISER"], ["haptics", "HAPTICS"], ["speed_first", "SPEED FIRST"], ["vehicle", "ON A VEHICLE"], ["gps", "GPS SPEED"]]:
		var b := _button(String(t[1]), 20, f, true)
		b.toggled.connect(func(on: bool) -> void:
			if _building:
				return
			cfg[t[0]] = on
			_sync_labels())
		_toggles[t[0]] = b
		_boxes.append([b, 240.0, 56.0])
	_label("Face challenges pop up in the air: pull the face for bonus points. The stabiliser uses your phone's motion sensors to steady the eye tracking.", 18, Color(1, 1, 1, 0.65), c)


func _build_reports_card() -> void:
	var c := _card("RUN REPORTS  (kept on this device only)")
	_reports_l = _label("", 17, Color(1, 1, 1, 0.8), c)
	var f := _flow(c)
	var cp := _button("COPY ALL", 20, f)
	cp.pressed.connect(func() -> void:
		RunLog.copy_text(JSON.stringify(RunLog.load_all(), "  "))
		_status.text = "Reports copied: paste them wherever you want help with them.")
	var dl := _button("DOWNLOAD", 20, f)
	dl.pressed.connect(func() -> void:
		RunLog.download(JSON.stringify(RunLog.load_all(), "  ")))
	var cl := _button("CLEAR", 20, f)
	cl.pressed.connect(func() -> void:
		RunLog.clear_all()
		_refresh_reports())
	_label("VEHICLE: tells the game you are on a bus or train, so it re-centres your look faster. GPS SPEED: lets the browser report only your speed (never your position) so it can notice a moving vehicle by itself.", 16, Color(1, 1, 1, 0.55), c)
	_refresh_reports()


func _refresh_reports() -> void:
	var runs := RunLog.load_all()
	if runs.is_empty():
		_reports_l.text = "No runs yet. Every run is recorded here: how the tracking, the steering and the frame rate behaved."
		return
	var lines: Array = []
	for i in range(runs.size() - 1, maxi(runs.size() - 6, -1), -1):
		lines.append(RunLog.line(runs[i]))
	_reports_l.text = "\n".join(lines)


func _build_footer() -> void:
	_status = _label("", 20, Color(1.0, 0.85, 0.3), _root, true)
	_footer = BoxContainer.new()
	_footer.vertical = true
	_root.add_child(_footer)
	_cam_btn = Button.new()
	_cam_btn.text = "START WITH CAMERA"
	_cam_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _style(Color(0.92, 0.28, 0.24) if st != "hover" else Color(1.0, 0.4, 0.34), Color(1, 1, 1, 0.55), 40, 2)
		sb.shadow_color = Color(0.92, 0.28, 0.24, 0.55)
		sb.shadow_size = 16
		_cam_btn.add_theme_stylebox_override(st, sb)
	_cam_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_btn.pressed.connect(_start.bind(true))
	_footer.add_child(_cam_btn)
	_texts.append([_cam_btn, 30])
	_boxes.append([_cam_btn, 0.0, 84.0])
	_alt_btn = Button.new()
	_alt_btn.text = "PLAY WITHOUT CAMERA"
	_alt_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		_alt_btn.add_theme_stylebox_override(st, _style(Color(1, 1, 1, 0.07) if st != "hover" else Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.35), 40, 1))
	_alt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alt_btn.pressed.connect(_start.bind(false))
	_footer.add_child(_alt_btn)
	_footer.move_child(_cam_btn, _footer.get_child_count() - 1)          # START WITH CAMERA goes last: on the right of a wide screen, at the bottom of a phone held upright, under the thumb
	_texts.append([_alt_btn, 22])
	_boxes.append([_alt_btn, 0.0, 84.0])
	_label("The camera never leaves your device.  No camera: A / D carve, mouse = your eyes.", 16, Color(1, 1, 1, 0.55), _root, true)
	_label("While we tune this, anonymous performance numbers (speed, tracking quality, gate choices; never images, video or names) go to the developer. EYE OPTIONS has a switch to stop it.", 14, Color(1, 1, 1, 0.42), _root, true)


static func Game_presets() -> Array:
	return ["classic", "alpine", "meadow", "canyon", "chaos", "endless"]


# ---------------------------------------------------------------- state
func _preset_defs(id: String) -> Dictionary:
	match id:
		"alpine":
			return {"diff": 1.1, "zones": {"rush": 2.0, "flat": 0.4, "tunnel": 0.6, "bend": 0.6, "air": 0.8}}
		"meadow":
			return {"diff": 0.7, "zones": {"rush": 0.5, "flat": 2.0, "tunnel": 0.2, "bend": 0.3, "air": 0.6}}
		"canyon":
			return {"diff": 1.2, "zones": {"rush": 0.6, "flat": 0.3, "tunnel": 2.0, "bend": 1.8, "air": 0.3}}
		"chaos":
			return {"diff": 1.3, "zones": {"rush": 1.0, "flat": 0.6, "tunnel": 0.8, "bend": 0.8, "air": 2.0}}
		"endless":
			return {"endless": true}
	return {"diff": 1.0, "zones": {"rush": 1.0, "flat": 1.0, "tunnel": 1.0, "bend": 1.0, "air": 1.0}}


func _pick_preset(id: String) -> void:
	if _building:
		return
	var d := _preset_defs(id)
	cfg["preset"] = id
	cfg["endless"] = bool(d.get("endless", false))
	if d.has("diff"):
		cfg["diff"] = d["diff"]
	if d.has("zones"):
		cfg["zones"] = (d["zones"] as Dictionary).duplicate()
	_sync_widgets()


func _custom() -> void:
	cfg["preset"] = ""
	for id in _preset_btns:
		(_preset_btns[id] as Button).set_pressed_no_signal(false)


func _pick_theme(id: String) -> void:
	cfg["theme"] = id
	_bg.choose_theme(id)
	_sync_labels()


func _sync_widgets() -> void:
	var was := _building
	_building = true
	for id in _theme_btns:
		(_theme_btns[id] as Button).set_pressed_no_signal(id == String(cfg["theme"]))
	for id in _preset_btns:
		(_preset_btns[id] as Button).set_pressed_no_signal(id == String(cfg["preset"]))
	_diff_s.value = float(cfg["diff"])
	_len_s.value = float(cfg["length_km"])
	_end_b.set_pressed_no_signal(bool(cfg["endless"]))
	_seed_e.text = str(int(cfg["seed"])) if int(cfg["seed"]) != 0 else ""
	for z in _zone_s:
		(_zone_s[z] as HSlider).value = float((cfg["zones"] as Dictionary).get(z, 1.0))
	for k in _toggles:
		(_toggles[k] as Button).set_pressed_no_signal(bool(cfg[k]))
	_int_s.value = float(cfg["intensity"])
	_assist_s.value = float(cfg["assist"])
	_building = was
	_sync_labels()


func _sync_labels() -> void:
	var id := String(cfg["theme"])
	var d := Themes.theme_data(id)
	_blurb.text = String(d["blurb"])
	_int_row.visible = Themes.post_mode(id) > 0
	_diff_l.text = "DIFFICULTY  %s   (more gates, narrower and trickier ones, more trees; speed and controls stay the same)" % _diff_word(float(cfg["diff"]))
	_assist_l.text = "AUTO-HELP  %s" % ("OFF" if float(cfg["assist"]) < 0.05 else ("LIGHT" if float(cfg["assist"]) < 0.4 else ("BALANCED" if float(cfg["assist"]) < 0.75 else "STRONG")))
	_len_l.text = "LENGTH  %s" % ("ENDLESS" if bool(cfg["endless"]) else "%.1f km" % float(cfg["length_km"]))
	_int_l.text = "EFFECT INTENSITY  %d%%" % int(float(cfg["intensity"]) / 1.5 * 100.0) if _int_l != null else ""
	for z in _zone_l:
		(_zone_l[z] as Label).text = "%s   %s" % [ZONE_LABELS[z], _mix_word(float((cfg["zones"] as Dictionary).get(z, 1.0)))]
	for k in _toggles:
		var b: Button = _toggles[k]
		b.text = "%s  %s" % [String(b.text).get_slice("  ", 0), "ON" if bool(cfg[k]) else "OFF"]
	_accent = (d["c1"] as Color).lerp(Color(1, 1, 1), 0.35)
	_title.add_theme_color_override("font_color", (d["c1"] as Color).lerp(Color(1, 1, 1), 0.55))
	_save()


func _diff_word(v: float) -> String:
	if v < 0.8:
		return "RELAXED"
	if v < 1.1:
		return "NORMAL"
	if v < 1.35:
		return "HARD"
	return "BRUTAL"


func _mix_word(v: float) -> String:
	if v <= 0.05:
		return "NEVER"
	if v < 0.7:
		return "RARE"
	if v < 1.4:
		return "NORMAL"
	if v < 2.2:
		return "OFTEN"
	return "EVERYWHERE"


# ---------------------------------------------------------------- saving and links
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	for k in cfg.keys():
		if cf.has_section_key("m", k):
			var v: Variant = cf.get_value("m", k)
			if typeof(v) == typeof(cfg[k]):
				cfg[k] = v
	if not Themes.DATA.has(String(cfg["theme"])):
		cfg["theme"] = "alpine"


func _save() -> void:
	if _building:
		return
	var cf := ConfigFile.new()
	for k in cfg:
		cf.set_value("m", k, cfg[k])
	cf.save(SAVE)


func _url_overrides() -> void:
	if not OS.has_feature("web"):
		return
	var q := func(key: String) -> String:
		return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % key))
	var th: String = q.call("theme")
	if Themes.DATA.has(th):
		cfg["theme"] = th
	var pr: String = q.call("preset")
	if PRESET_NAMES.has(pr):
		var d := _preset_defs(pr)
		cfg["preset"] = pr
		cfg["endless"] = bool(d.get("endless", false))
		if d.has("diff"):
			cfg["diff"] = d["diff"]
		if d.has("zones"):
			cfg["zones"] = (d["zones"] as Dictionary).duplicate()
	var sd: String = q.call("seed")
	if sd.is_valid_int():
		cfg["seed"] = int(sd)
	var ln: String = q.call("len")
	if ln.is_valid_float():
		var m := float(ln)
		cfg["endless"] = m <= 0.0
		if m > 0.0:
			cfg["length_km"] = clampf(m / 1000.0, 1.0, 12.0)
	var df: String = q.call("diff")
	if df.is_valid_float():
		cfg["diff"] = clampf(float(df), 0.5, 1.6)
	var zs: String = q.call("zones")
	if zs != "":
		for part in zs.split(","):
			var kv := part.split(":")
			if kv.size() == 2 and ZONE_LABELS.has(kv[0]):
				(cfg["zones"] as Dictionary)[kv[0]] = float(kv[1])
		cfg["preset"] = ""


func link() -> String:
	var z: Array = []
	for k in ["rush", "flat", "tunnel", "bend", "air", "forest", "drop"]:
		z.append("%s:%.1f" % [k, float((cfg["zones"] as Dictionary).get(k, 1.0))])
	var sd := int(cfg["seed"]) if int(cfg["seed"]) != 0 else randi_range(1000, 999999)
	cfg["seed"] = sd
	_seed_e.text = str(sd)
	return "?level=downhill&theme=%s&seed=%d&len=%d&diff=%.2f&zones=%s" % [cfg["theme"], sd, 0 if bool(cfg["endless"]) else int(float(cfg["length_km"]) * 1000.0), float(cfg["diff"]), ",".join(z)]


func _copy_link() -> void:
	var q := link()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){var u=location.origin+location.pathname+'%s';try{navigator.clipboard.writeText(u)}catch(e){}})()" % q)
		_status.text = "Link copied: the same course, the same look."
	else:
		DisplayServer.clipboard_set(q)
		_status.text = "Link copied."


# ---------------------------------------------------------------- layout
func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	if vs != _last_vs:
		_last_vs = vs
		position = Vector2.ZERO
		size = vs
		_apply_unit(false)
	if visible and GazeProvider.camera_status != "" and _status != null:
		_status.text = GazeProvider.camera_status


func _apply_unit(force: bool) -> void:
	var portrait := size.y > size.x * 1.05
	var u := 2.1 if portrait else (1.25 if Game.touch_mode else 1.0)
	var cols := 1 if (portrait or size.x < 900.0) else 2
	if not force and absf(u - _u) < 0.001 and cols == _cols:
		return
	_u = u
	_cols = cols
	_grid.columns = cols
	var gap := int(14.0 * u)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for it in _texts:
		(it[0] as Control).add_theme_font_size_override("font_size", int(float(it[1]) * u))
	for it in _boxes:
		var c: Control = it[0]
		c.custom_minimum_size = Vector2(float(it[1]) * u, float(it[2]) * u)
	var m := int(24.0 * u)
	_margin.add_theme_constant_override("margin_left", m)
	_margin.add_theme_constant_override("margin_right", m)
	_margin.add_theme_constant_override("margin_top", int(16.0 * u))
	_margin.add_theme_constant_override("margin_bottom", int(16.0 * u))
	_root.add_theme_constant_override("separation", int(10.0 * u))
	_footer.vertical = portrait or size.x < 760.0
	_footer.add_theme_constant_override("separation", int(10.0 * u))
	for pc in _cards:
		var sb := pc.get_theme_stylebox("panel") as StyleBoxFlat
		sb.content_margin_left = 20.0 * u
		sb.content_margin_right = 20.0 * u
		sb.content_margin_top = 14.0 * u
		sb.content_margin_bottom = 16.0 * u
		(pc.get_child(0) as VBoxContainer).add_theme_constant_override("separation", int(10.0 * u))
	_more.visible = true


# ---------------------------------------------------------------- leaving
func _other_games() -> void:
	var intro := EyeDemoIntro.new()
	get_parent().add_child(intro)
	queue_free()


func _start(with_camera: bool) -> void:
	if with_camera and not OS.has_feature("web"):
		_status.text = "Camera tracking runs in the web build. Using mouse as your eyes."
		with_camera = false
	_save()
	var out := cfg.duplicate(true)
	if int(out["seed"]) == 0:
		out["seed"] = randi_range(1000, 999999)                       # "random" stays random next time: only this run gets a number
	visible = false
	get_tree().paused = false
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		JavaScriptBridge.eval("(function(){try{if(screen.orientation&&screen.orientation.lock){screen.orientation.lock('landscape').catch(function(){});}}catch(e){}})()")
	Game.dh_started.emit(out)
	if with_camera:
		GazeProvider.start_camera()
	else:
		GazeProvider.set_backend(GazeProvider.Backend.TOUCH if Game.touch_mode else GazeProvider.Backend.MOUSE)
	GazeProvider.set_active(true)
	queue_free()
