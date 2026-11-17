class_name DownhillMenu
extends Control
## The pre-run screen for Downhill: a live 3D backdrop that drifts slowly behind glass cards, one column on a phone held upright, two on a wide screen,
## with the start buttons always on screen at the bottom. The game is paused behind it. Everything chosen here is remembered, and the course can be shared as a link.
## Sizes are in the game's canvas units (1280 wide in landscape, 1280 across the SHORT side in portrait), so `_u` scales them up for a phone held upright.

const SAVE := "user://downhill_menu.cfg"
const PRESET_NAMES := {"classic": "CLASSIC", "alpine": "ALPINE RUSH", "meadow": "MEADOWS", "canyon": "CANYON", "chaos": "CHAOS", "endless": "ENDLESS"}
const ZONE_LABELS := {"rush": "RUSH", "flat": "MEADOW", "tunnel": "TUNNEL", "bend": "BEND", "air": "SKY", "forest": "FOREST", "drop": "CLIFF"}

var cfg: Dictionary = {
	"v": 4, "theme": "alpine", "preset": "classic", "diff": 1.0, "length_km": 4.2, "endless": false, "seed": 0,
	"zones": {"rush": 1.0, "flat": 1.0, "tunnel": 1.0, "bend": 1.0, "air": 1.0, "forest": 1.0, "drop": 1.0},
	"psy": false, "journey": true, "trip": 1, "mus": "auto", "mvol": 0.7, "svol": 0.9, "toon": true, "m_grav": 1.0, "m_rocks": 1.0, "m_ramps": 1.0, "m_pads": 1.0, "m_ice": false, "m_head": false, "m_bounce": false, "m_trike": false, "m_glints": 1.0, "m_faces": 1.0, "m_hat": 0, "faces": true, "cine": true, "phone": true, "haptics": true, "dynlight": true, "snow": true, "fluffy": false, "vehicle": false, "gps": false, "speed_first": false, "assist": 0.7, "intensity": 0.75, "mode": "score",
}

var _defaults: Dictionary = cfg.duplicate(true)
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
var _mode_btns: Dictionary = {}
var _u: float = 1.0
var _cols: int = -1
var _last_vs: Vector2 = Vector2.ZERO
var _accent: Color = Color(0.04, 0.52, 1.0)
var _building: bool = true
var _tab: int = 0
var _note: Label
var _force_tabs: bool = false          # the panels do not fit side by side at a readable size: one at a time, with tabs
var _fit: float = 1.0                  # shrinks everything in step until the whole page fits the screen
var _fit_n: int = 0
var _fit_w: int = 0
var _fit_h: int = 0
var _tab_btns: Array[Button] = []
var _tabrow: HBoxContainer
var _rep_card: PanelContainer
var _rep_on: bool = false
var _mix_grid: GridContainer = GridContainer.new()          # (the zone mix is set by the course presets now; this stays only so old code has a place to point)
var _tints: Array = [Color(0.45, 0.8, 1.0), Color(1.0, 0.7, 0.3), Color(0.8, 0.55, 1.0), Color(1.0, 0.45, 0.55), Color(0.6, 0.9, 0.6)]
var _mh_s: Dictionary = {}
var _hat_b: Button
var _lvl_l: Label
var _mus_btns: Dictionary = {}
var _reset_arm: float = 0.0
var _reset_b: Button
var _trip_btns: Dictionary = {}
var _mvol_s: HSlider
var _svol_s: HSlider
var _mvol_l: Label
var _svol_l: Label
var _lvl_bar: ProgressBar
var _sw_on: ImageTexture
var _sw_off: ImageTexture
var _mh_l: Dictionary = {}
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
	_build_tabs()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED          # no scrolling anywhere: every page is made to fit the screen
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_build_theme_card()
	_build_course_card()
	_build_sound_card()
	_build_experience_card()
	_build_mayhem_card()
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


func _card(title: String, sub: String = "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _style(Color(0.10, 0.10, 0.12, 0.93), Color(1, 1, 1, 0.07), 26, 1))
	_grid.add_child(pc)
	_cards.append(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	_label(title, 30, Color(1, 1, 1, 1), vb)
	if sub != "":
		_label(sub, 16, Color(1, 1, 1, 0.5), vb)
	return vb


## An iOS-style switch row: the name on the left, the switch on the right, a hairline under it.
func _switch_tex(on: bool) -> ImageTexture:
	var w := 60
	var h := 36
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color(0.20, 0.78, 0.35) if on else Color(0.34, 0.34, 0.37)
	var kx := float(w) - 18.0 if on else 18.0
	for y in h:
		for x in w:
			var px := Vector2(float(x) + 0.5, float(y) + 0.5)
			# the track: a pill
			var cx := clampf(px.x, 18.0, float(w) - 18.0)
			var dt := (px - Vector2(cx, float(h) * 0.5)).length() - 18.0
			var ta := clampf(0.5 - dt, 0.0, 1.0)
			var dk := (px - Vector2(kx, float(h) * 0.5)).length() - 14.0
			var ka := clampf(0.5 - dk, 0.0, 1.0)
			var c := Color(track.r, track.g, track.b, ta)
			c = c.lerp(Color(1, 1, 1, 1), ka * ta)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _switch_row(parent: Node, text: String, hairline: bool = true) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _sw_on == null:
		_sw_on = _switch_tex(true)
		_sw_off = _switch_tex(false)
	for ic in ["checked", "checked_mirrored", "unchecked_mirrored"]:
		b.add_theme_icon_override(ic, _sw_on if ic == "checked" or ic == "checked_mirrored" else _sw_off)
	b.add_theme_icon_override("unchecked", _sw_off)
	for ic in ["checked_disabled", "checked_disabled_mirrored"]:
		b.add_theme_icon_override(ic, _sw_on)
	for ic in ["unchecked_disabled", "unchecked_disabled_mirrored"]:
		b.add_theme_icon_override(ic, _sw_off)
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0.0)
	clear.content_margin_left = 4
	clear.content_margin_right = 4
	clear.content_margin_top = 6
	clear.content_margin_bottom = 6
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, clear)
	for cn in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(cn, Color(1, 1, 1, 0.95))
	b.add_theme_constant_override("h_separation", 12)
	parent.add_child(b)
	_texts.append([b, 18])
	_boxes.append([b, 0.0, 46.0])
	if hairline:
		var sep := ColorRect.new()
		sep.color = Color(1, 1, 1, 0.08)
		sep.custom_minimum_size = Vector2(0, 1)
		parent.add_child(sep)
	return b


## Two columns of switches (or dials), so a page of them is half as tall.
func _pair_grid(parent: Node) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 18)
	parent.add_child(g)
	return g


func _build_tabs() -> void:
	_tabrow = HBoxContainer.new()
	_root.add_child(_tabrow)
	var grp := ButtonGroup.new()
	for i in 5:
		var b := _button(["WORLD", "COURSE", "SOUND", "YOU", "MAYHEM"][i], 22, _tabrow, true)
		b.button_group = grp
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 14, 0))
		b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 14, 0))
		b.add_theme_stylebox_override("pressed", _style(_accent, Color(0, 0, 0, 0), 14, 0))
		b.add_theme_stylebox_override("hover_pressed", _style(_accent, Color(0, 0, 0, 0), 14, 0))
		b.pressed.connect(func() -> void:
			_tab = i
			_show_cards())
		_tab_btns.append(b)
		_boxes.append([b, 0.0, 64.0])
	_tab_btns[0].set_pressed_no_signal(true)


func _show_cards() -> void:
	var portrait := _cols == 1
	for i in _cards.size():
		var pc := _cards[i]
		if i == _cards.size() - 1:
			pc.visible = _rep_on
		elif _rep_on:
			pc.visible = false
		else:
			pc.visible = (i == _tab) if portrait else true
	for i in _tab_btns.size():
		_tab_btns[i].set_pressed_no_signal(i == _tab and not _rep_on)


func _button(text: String, font: int, parent: Node, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), 14, 0))
	b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 14, 0))
	b.add_theme_stylebox_override("pressed", _style(_accent, Color(0, 0, 0, 0), 14, 0))
	b.add_theme_stylebox_override("hover_pressed", _style(_accent, Color(0, 0, 0, 0), 14, 0))
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


func _slider(parent: Node, lo: float, hi: float, step: float, label_text: String, fs: int = 20, sh: float = 46.0) -> Array:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var l := _label(label_text, fs, Color(1, 1, 1, 0.9), row)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.scrollable = false          # the wheel never moves a slider (it used to change values by accident while scrolling the page)
	if _grabber == null:
		_grabber = _grabber_tex(24, Color(1, 1, 1, 1.0))
	s.add_theme_icon_override("grabber", _grabber)
	s.add_theme_icon_override("grabber_highlight", _grabber)
	s.add_theme_icon_override("grabber_disabled", _grabber)
	var track := _style(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 6)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := _style(_accent, Color(0, 0, 0, 0), 6)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	row.add_child(s)
	_boxes.append([s, 0.0, sh])
	return [s, l]


func _build_header() -> void:
	var h := HBoxContainer.new()
	_root.add_child(h)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tb)
	_title = _label("DOWNHILL", 40, Color(1.0, 0.9, 0.4), tb)
	_sub = _label("Build your own ride, then go. The riding is always the same fun: rails, ramps, flow.", 17, Color(1, 1, 1, 0.8), tb)
	_lvl_l = _label("", 17, Color(1.0, 0.85, 0.3), tb)
	_lvl_bar = ProgressBar.new()
	_lvl_bar.show_percentage = false
	_lvl_bar.custom_minimum_size = Vector2(0, 6)
	_lvl_bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 4, 0))
	_lvl_bar.add_theme_stylebox_override("fill", _style(Color(1.0, 0.85, 0.3), Color(0, 0, 0, 0), 4, 0))
	tb.add_child(_lvl_bar)
	var xb := _button("RESET", 16, h)
	xb.pressed.connect(func() -> void:
		if _reset_arm <= 0.0:
			_reset_arm = 3.0
			xb.text = "SURE?"
			return
		_reset_arm = 0.0
		xb.text = "RESET"
		cfg = _defaults.duplicate(true)
		_bg.choose_theme(String(cfg["theme"]))
		_sync_widgets()
		_save()
		_status.text = "Everything is back to how it came.")
	_reset_b = xb
	var rb := _button("MORE", 16, h)
	rb.pressed.connect(func() -> void:
		_rep_on = not _rep_on
		_show_cards())
	_more = _button("OTHER GAMES", 16, h)
	_more.pressed.connect(_other_games)


func _build_theme_card() -> void:
	var c := _card("WORLD", "what you ride through")
	var jb := _switch_row(c, "All dressed: every world, in waves")
	jb.toggled.connect(func(on: bool) -> void:
		if _building:
			return
		cfg["journey"] = on
		if on and String(cfg["theme"]) != "alpine":
			cfg["theme"] = "alpine"          # All dressed starts from alpine: switching it on takes you back there
			_bg.choose_theme("alpine")
		_sync_widgets())
	_toggles["journey"] = jb
	_label("A night out in waves: a first taste, warmth, the rush, the peak, the comedown. Glowing molecules bring it on early. Picking a world yourself gives that world in full.", 15, Color(1, 1, 1, 0.55), c)
	var tf := _flow(c)
	var tg := ButtonGroup.new()
	for tv in [[0, "GENTLE"], [1, "NORMAL"], [2, "WILD"]]:
		var tb := _button(String(tv[1]), 17, tf, true)
		tb.button_group = tg
		tb.pressed.connect(func() -> void:
			cfg["trip"] = int(tv[0])
			_save())
		_trip_btns[tv[0]] = tb
		_boxes.append([tb, 120.0, 44.0])
	var f := _flow(c)
	var grp := ButtonGroup.new()
	var all_looks := OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('looks')"))          # one look at a time: Alpine is the demo, ?looks brings the others back
	for id in Themes.ORDER:
		if not ["alpine", "psychedelic", "tunnel", "desert"].has(id) and not all_looks:
			continue
		var d := Themes.theme_data(id)
		var b := _button(String(d["name"]), 22, f, true)
		b.button_group = grp
		b.pressed.connect(_pick_theme.bind(id))
		_theme_btns[id] = b
		_boxes.append([b, 190.0, 64.0])
	_blurb = _label("", 20, Color(1, 1, 1, 0.8), c)
	var r := _slider(c, 0.0, 1.5, 0.05, "TRIPPY INTENSITY", 17, 34.0)
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
	var c := _card("COURSE", "how the run is built")
	var f := _flow(c)
	var grp := ButtonGroup.new()
	grp.allow_unpress = true
	for id in Game_presets():
		var b := _button(String(PRESET_NAMES[id]), 17, f, true)
		b.button_group = grp
		b.pressed.connect(_pick_preset.bind(id))
		_preset_btns[id] = b
		_boxes.append([b, 118.0, 46.0])
	var d := _slider(c, 0.5, 1.6, 0.05, "", 17, 36.0)
	_diff_s = d[0]
	_diff_l = d[1]
	_diff_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["diff"] = v
		_custom()
		_sync_labels())
	var ln := _slider(c, 1.0, 12.0, 0.2, "", 17, 36.0)
	_len_s = ln[0]
	_len_l = ln[1]
	_len_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["length_km"] = v
		cfg["endless"] = false
		_custom()
		_sync_labels())
	_end_b = _button("ENDLESS", 17, c, true)
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


func _build_sound_card() -> void:
	var c := _card("SOUND", "music and effects")
	_label("MUSIC", 16, Color(1, 1, 1, 0.5), c)
	var mf := _flow(c)
	var mg := ButtonGroup.new()
	for md in [["off", "OFF"], ["auto", "AUTO"], ["ambient", "AMBIENT"], ["techno", "TECHNO"], ["trance", "TRANCE"], ["jungle", "JUNGLE"], ["industrial", "INDUSTRIAL"]]:
		var mb := _button(String(md[1]), 17, mf, true)
		mb.button_group = mg
		mb.pressed.connect(func() -> void:
			cfg["mus"] = String(md[0])
			_save())
		_mus_btns[md[0]] = mb
		_boxes.append([mb, 120.0, 44.0])
	var g := _pair_grid(c)
	var mv := _slider(g, 0.0, 1.0, 0.05, "", 17, 34.0)
	_mvol_s = mv[0]
	_mvol_l = mv[1]
	_mvol_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["mvol"] = v
		_sync_labels())
	var sv := _slider(g, 0.0, 1.0, 0.05, "", 17, 34.0)
	_svol_s = sv[0]
	_svol_l = sv[1]
	_svol_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["svol"] = v
		_sync_labels())
	var tb := _switch_row(c, "Cartoon sounds")
	tb.toggled.connect(func(on: bool) -> void:
		if _building:
			return
		cfg["toon"] = on
		_sync_labels())
	_toggles["toon"] = tb


func _build_experience_card() -> void:
	var c := _card("YOU", "how you play")
	var ar := _slider(c, 0.0, 1.0, 0.05, "")
	_assist_s = ar[0]
	_assist_l = ar[1]
	_assist_s.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg["assist"] = v
		_sync_labels())
	var g := _pair_grid(c)
	for t in [["faces", "Face challenges"], ["cine", "Cinematic jumps"], ["dynlight", "Dynamic light"], ["snow", "Snowfall"], ["fluffy", "Fluffy shapes"], ["phone", "Phone stabiliser"], ["haptics", "Haptics"], ["speed_first", "Speed first"]]:
		var b := _switch_row(g, String(t[1]), false)
		b.toggled.connect(func(on: bool) -> void:
			if _building:
				return
			cfg[t[0]] = on
			_sync_labels())
		_toggles[t[0]] = b
	_label("Faces pop up in the air: pull them for points. The stabiliser steadies tracking with your phone's motion sensors.", 14, Color(1, 1, 1, 0.55), c).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## One dial can drive more than one setting (`also`: key, scale), so the page has four dials instead of six.
func _mh_slider(c: Node, key: String, lo: float, hi: float, name: String, words: Array, also: Array = []) -> void:
	var r := _slider(c, lo, hi, 0.05, "", 17, 34.0)
	var sl: HSlider = r[0]
	_mh_s[key] = sl
	_mh_l[key] = [r[1], name, words]
	sl.value_changed.connect(func(v: float) -> void:
		if _building:
			return
		cfg[key] = v
		for al in also:
			cfg[String(al[0])] = v * float(al[1])
		_sync_labels())


func _build_mayhem_card() -> void:
	var c := _card("MAYHEM", "bend the rules")
	var g := _pair_grid(c)
	_mh_slider(g, "m_grav", 0.3, 2.0, "GRAVITY", ["MOON", "FLOATY", "NORMAL", "HEAVY", "ANVIL"])
	_mh_slider(g, "m_ramps", 0.0, 2.5, "RAMPS & BOOSTS", ["NONE", "RARE", "NORMAL", "LOTS", "ALL OVER"], [["m_pads", 1.6]])
	_mh_slider(g, "m_rocks", 0.0, 2.5, "ROCKS & SLUSH", ["NONE", "FEW", "NORMAL", "LOTS", "MINEFIELD"])
	_mh_slider(g, "m_glints", 0.5, 4.0, "GLINTS & FACES", ["DRIZZLE", "LIGHT", "NORMAL", "HEAVY", "MONSOON"], [["m_faces", 0.75]])
	var tg := _pair_grid(c)
	for t in [["m_ice", "Ice rink"], ["m_head", "Big head"], ["m_bounce", "Bouncy snow"], ["m_trike", "Tricycle"]]:
		var b := _switch_row(tg, String(t[1]), false)
		b.toggled.connect(func(on: bool) -> void:
			if _building:
				return
			cfg[t[0]] = on
			_sync_labels())
		_toggles[t[0]] = b
	var f := _flow(c)
	var hb := _button("HAT  NONE", 17, f)
	hb.pressed.connect(func() -> void:
		cfg["m_hat"] = (int(cfg["m_hat"]) + 1) % 4
		_sync_labels())
	_boxes.append([hb, 118.0, 46.0])
	_hat_b = hb
	var rs := _button("RESET", 17, f)
	rs.pressed.connect(func() -> void:
		for k in ["m_grav", "m_rocks", "m_ramps", "m_pads", "m_glints", "m_faces"]:
			cfg[k] = 1.0
		for k in ["m_ice", "m_head", "m_bounce", "m_trike"]:
			cfg[k] = false
		cfg["m_hat"] = 0
		_sync_widgets())
	_boxes.append([rs, 118.0, 46.0])


func _build_reports_card() -> void:
	var c := _card("MORE", "reports, travel, reset")
	_rep_card = _cards[_cards.size() - 1]
	var vg := _pair_grid(c)
	for t in [["vehicle", "On a vehicle"], ["gps", "GPS speed"]]:
		var vb := _switch_row(vg, String(t[1]), false)
		vb.toggled.connect(func(on: bool) -> void:
			if _building:
				return
			cfg[t[0]] = on
			_sync_labels())
		_toggles[t[0]] = vb
	_reports_l = _label("", 17, Color(1, 1, 1, 0.8), c)
	var f := _flow(c)
	var cp := _button("COPY ALL", 20, f)
	cp.pressed.connect(func() -> void:
		RunLog.copy_text(JSON.stringify(RunLog.load_all(), "  "))
		_status.text = "Reports copied: paste them wherever you want help with them.")
	var dl := _button("DOWNLOAD", 20, f)
	dl.pressed.connect(func() -> void:
		RunLog.download(JSON.stringify(RunLog.load_all(), "  ")))
	var ua := _button("UNLOCK ALL", 20, f)
	ua.pressed.connect(func() -> void:
		DhProgress.unlock_all()
		_sync_widgets())
	var rst := _button("RESET ALL SETTINGS", 20, f)
	var rwarn := _label("This will reset all parameters and settings (your level and unlocks stay). Reset: yes or no?", 17, Color(1.0, 0.8, 0.4), c)
	rwarn.visible = false
	var rf := _flow(c)
	var ryes := _button("YES, RESET", 20, rf)
	var rno := _button("NO", 20, rf)
	rf.visible = false
	rst.pressed.connect(func() -> void:
		rwarn.visible = true
		rf.visible = true)
	rno.pressed.connect(func() -> void:
		rwarn.visible = false
		rf.visible = false)
	ryes.pressed.connect(func() -> void:
		rwarn.visible = false
		rf.visible = false
		cfg = _defaults.duplicate(true)
		_sync_widgets()
		_save()
		_status.text = "Everything is back to how it came.")
	var cl := _button("CLEAR", 20, f)
	cl.pressed.connect(func() -> void:
		RunLog.clear_all()
		_refresh_reports())
	_label("VEHICLE: tells the game you are on a bus or train, so it re-centres your look faster. GPS SPEED: lets the browser report only your speed (never your position) so it can notice a moving vehicle by itself.", 16, Color(1, 1, 1, 0.55), c)
	_label("The molecules you collect are six phenethylamines from Alexander Shulgin's PiHKAL: mescaline, DOM, 2C-B, 2C-E, 2C-T-2 and 2C-T-7. Their shapes are built from their structural formulas. With respect to Sasha Shulgin, whose work on how molecules shape what we perceive made them known.", 14, Color(1, 1, 1, 0.55), c).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(DhDirector.credits_text(), 13, Color(1, 1, 1, 0.5), c).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# the two ways to ride the same trail: one choice, remembered
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	_footer.add_child(mrow)
	var mgrp := ButtonGroup.new()
	for md in [["score", "FREESTYLE  ·  biggest score"], ["race", "RACE  ·  fastest line"]]:
		var mb := _button(String(md[1]), 20, mrow, true)
		mb.button_group = mgrp
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.pressed.connect(func() -> void:
			cfg["mode"] = String(md[0])
			_save())
		_mode_btns[md[0]] = mb
	_cam_btn = Button.new()
	_cam_btn.text = "START"
	_cam_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT          # the browser's own "exit full screen" notice sits over the middle of the bottom edge for a few seconds: the word goes where it is not covered
	_cam_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _style(_accent if st != "hover" else Color(0.25, 0.62, 1.0), Color(0, 0, 0, 0), 20, 0)
		sb.content_margin_right = 90
		_cam_btn.add_theme_stylebox_override(st, sb)
	_cam_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_btn.pressed.connect(_start.bind(not (OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("nocam"))))          # ?nocam: start with the mouse as your eyes (tests)
	_footer.add_child(_cam_btn)
	_texts.append([_cam_btn, 30])
	_boxes.append([_cam_btn, 0.0, 84.0])
	_note = _label("The camera never leaves your device.  No camera? The mouse or your thumb steers instead.", 16, Color(1, 1, 1, 0.55), _root, true)
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("/iPhone|iPod/.test(navigator.userAgent) && !navigator.standalone")):
		_note.text += "  On an iPhone the browser cannot go full screen: tap Share, then Add to Home Screen, and open the game from its icon."


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
	for id in _mode_btns:
		(_mode_btns[id] as Button).set_pressed_no_signal(id == String(cfg["mode"]))
	for id in _preset_btns:
		(_preset_btns[id] as Button).set_pressed_no_signal(false)


func _pick_theme(id: String) -> void:
	cfg["theme"] = id
	if id != "alpine":
		cfg["journey"] = false          # a world picked by hand is that world, all of it: All dressed switches itself off
	_bg.choose_theme(id)
	_sync_widgets()


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
	for k in _mh_s:
		(_mh_s[k] as HSlider).value = float(cfg[k])
	for id in _mus_btns:
		(_mus_btns[id] as Button).set_pressed_no_signal(id == String(cfg["mus"]))
	for tid in _trip_btns:
		(_trip_btns[tid] as Button).set_pressed_no_signal(int(tid) == int(cfg["trip"]))
	_mvol_s.value = float(cfg["mvol"])
	_svol_s.value = float(cfg["svol"])
	for id in _mode_btns:
		(_mode_btns[id] as Button).set_pressed_no_signal(id == String(cfg["mode"]))
	_int_s.value = float(cfg["intensity"])
	_assist_s.value = float(cfg["assist"])
	_building = was
	_sync_labels()
	_apply_locks()


## A setting that is not open yet at this level: greyed out, with the level that opens it.
func _locked(key: String) -> bool:
	return not DhProgress.unlocked(key)


func _apply_locks() -> void:
	var p := DhProgress.progress()
	_lvl_l.text = "LEVEL %d     %d / %d XP" % [DhProgress.level(), int(p.x), int(p.y)] if DhProgress.level() < DhProgress.LEVEL_XP.size() else "LEVEL %d  (MAX)" % DhProgress.level()
	_lvl_bar.max_value = maxf(p.y, 1.0)
	_lvl_bar.value = p.x
	for id in _theme_btns:
		var b: Button = _theme_btns[id]
		var key := "theme:" + String(id)
		var nm := String(Themes.theme_data(String(id))["name"])
		b.disabled = _locked(key)
		b.text = nm if not _locked(key) else "%s  ·  LV %d" % [nm, DhProgress.need(key)]
	for k in _mh_s:
		(_mh_s[k] as HSlider).editable = not _locked(String(k))
	for k in _toggles:
		if DhProgress.UNLOCK.has(String(k)):
			(_toggles[k] as Button).disabled = _locked(String(k))
	if _hat_b != null:
		_hat_b.disabled = _locked("m_hat")


func _sync_labels() -> void:
	var id := String(cfg["theme"])
	var d := Themes.theme_data(id)
	_blurb.text = String(d["blurb"])
	_int_row.visible = Themes.post_mode(id) > 0
	_diff_l.text = "DIFFICULTY  %s" % _diff_word(float(cfg["diff"]))
	_assist_l.text = "AUTO-HELP  %s" % ("OFF" if float(cfg["assist"]) < 0.05 else ("LIGHT" if float(cfg["assist"]) < 0.4 else ("BALANCED" if float(cfg["assist"]) < 0.75 else "STRONG")))
	_len_l.text = "LENGTH  %s" % ("ENDLESS" if bool(cfg["endless"]) else "%.1f km" % float(cfg["length_km"]))
	_mvol_l.text = "MUSIC VOLUME  %d%%" % int(float(cfg["mvol"]) * 100.0)
	_svol_l.text = "EFFECTS VOLUME  %d%%" % int(float(cfg["svol"]) * 100.0)
	_int_l.text = "TRIPPY  %d%%" % int(float(cfg["intensity"]) / 1.5 * 100.0) if _int_l != null else ""
	for z in _zone_l:
		(_zone_l[z] as Label).text = "%s · %s" % [ZONE_LABELS[z], _mix_word(float((cfg["zones"] as Dictionary).get(z, 1.0)))]
	if _hat_b != null:
		_hat_b.text = ("HAT  %s" % ["NONE", "TOP HAT", "PARTY", "PROP"][int(cfg["m_hat"])]) if not _locked("m_hat") else "HAT  ·  LV %d" % DhProgress.need("m_hat")
	for k in _mh_l:
		var ml: Array = _mh_l[k]
		var v := float(cfg[k])
		var th: Array = [0.45, 0.8, 1.25, 1.6] if k == "m_grav" else ([0.05, 0.7, 1.6, 2.8] if k == "m_pads" else [0.05, 0.7, 1.4, 2.2])
		var wd: Array = ml[2]
		var idx := 4
		for ti in 4:
			if v < float(th[ti]):
				idx = ti
				break
		(ml[0] as Label).text = ("%s · %s" % [ml[1], wd[idx]]) if not _locked(String(k)) else "%s  ·  LV %d" % [ml[1], DhProgress.need(String(k))]
	for k in _toggles:
		var b: Button = _toggles[k]
		if b is CheckButton:
			if DhProgress.UNLOCK.has(String(k)):
				var base := String(b.get_meta("base", b.text))
				b.set_meta("base", base)
				b.text = base if not _locked(String(k)) else "%s  ·  LV %d" % [base, DhProgress.need(String(k))]
			continue
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
		return "SOME"
	if v < 2.2:
		return "LOTS"
	return "MAX"


# ---------------------------------------------------------------- saving and links
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	var old_cfg := not cf.has_section_key("m", "v") or int(cf.get_value("m", "v")) != 4          # saved before Psychedelic became the default: take the new look and the new 50% once
	for k in cfg.keys():
		if old_cfg and (k == "theme" or k == "intensity" or k == "journey"):
			continue
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
	if str(JavaScriptBridge.eval("window.location.search")).contains("nodyn"):
		cfg["dynlight"] = false          # a test switch: no moving lights (they make the shaders switch programs as lights come in range)
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
	var mo: String = q.call("mode")
	if mo == "race" or mo == "score":
		cfg["mode"] = mo
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
	if _reset_arm > 0.0:
		_reset_arm -= _delta
		if _reset_arm <= 0.0 and _reset_b != null:
			_reset_b.text = "RESET"
	var vs := get_viewport_rect().size
	if vs != _last_vs:
		_last_vs = vs
		position = Vector2.ZERO
		size = vs
		_fit = 1.0
		_fit_n = 0
		_fit_w = 0
		_fit_h = 0
		_force_tabs = false
		_apply_unit(false)
	if _root != null and _margin.visible and _fit_w < 10:
		# nothing may be wider than the screen: if the widest row (the tabs, the buttons along the top, the footer) does not fit across, everything is scaled down until it does
		var mw := _margin.get_combined_minimum_size().x
		if mw > vs.x + 1.0 and _fit > 0.4:
			_fit_w += 1
			_fit = maxf(0.4, _fit * (vs.x / mw) * 0.97)
			_apply_unit(true)
	if _fit_h < 10 and _root != null and _margin.visible and _cols == 1:
		# the settings card must keep a usable share of the screen: if the title, tabs and buttons around it take more than 60 % of the height (a phone on its side), scale them down
		var fixed := float(_margin.get_theme_constant("margin_top") + _margin.get_theme_constant("margin_bottom"))
		for ch in _root.get_children():
			if ch != _scroll and (ch as Control).visible:
				fixed += (ch as Control).get_combined_minimum_size().y + float(_root.get_theme_constant("separation"))
		if fixed > vs.y * 0.6 and _fit > 0.4:
			_fit_h += 1
			_fit = maxf(0.4, _fit * (vs.y * 0.55 / fixed))
			_apply_unit(true)
	if _fit_n < 9 and _root != null and _margin.visible:
		# everything must be on the page without scrolling: if it is taller than the screen, shrink it all a little and look again
		var need := _grid.get_combined_minimum_size().y
		for ch in _root.get_children():
			if ch != _scroll and (ch as Control).visible:
				need += (ch as Control).get_combined_minimum_size().y + float(_root.get_theme_constant("separation"))
		need += float(_margin.get_theme_constant("margin_top") + _margin.get_theme_constant("margin_bottom")) + float(_root.get_theme_constant("separation"))
		if need > vs.y + 2.0:
			if _cols != 1:
				_force_tabs = true                           # side by side does not fit at a readable size: tabs instead
				_fit = 1.0
				_fit_n += 1
				_apply_unit(true)
			elif _fit > 0.45:
				_fit_n += 1                                   # no scrolling: the whole page, the footer included, is scaled until it fits the height
				_fit = maxf(0.45, _fit * vs.y / need * 0.97)
				_apply_unit(true)
	if visible and GazeProvider.camera_status != "" and _status != null:
		_status.text = GazeProvider.camera_status


## How many CSS pixels one canvas unit is on this screen right now (1.0 is a laptop window at its natural size, about 0.3 to 0.5 on a phone).
func _css_per_unit() -> float:
	var vp := get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return 1.0
	if OS.has_feature("web"):
		# the page's own width in CSS pixels over the canvas width in units: no guessing about the device pixel ratio or what the engine reports as the window size
		var iw := float(JavaScriptBridge.eval("window.innerWidth || 0"))
		if iw > 50.0:
			return clampf(iw / vp.x, 0.15, 2.0)
	return clampf(minf(float(DisplayServer.window_get_size().x) / vp.x, float(DisplayServer.window_get_size().y) / vp.y), 0.15, 2.0)


func _apply_unit(force: bool) -> void:
	var portrait := size.y > size.x * 1.05
	# text is sized from how big it really is on this screen (CSS pixels), not from the game's own 1280-unit canvas: the smallest text must be readable and every button a thumb
	var u_read := clampf(17.0 / (15.0 * _css_per_unit()), 1.0, 3.4)
	var tabs := true          # one page at a time, always: each page is short enough to fit without scrolling
	var u := u_read * _fit
	var compact := size.y * _css_per_unit() < 480.0          # a short landscape phone: every pixel of height goes to the panel
	var hk := 0.58 if compact else 1.0
	_sub.visible = not compact
	_note.visible = not compact
	_lvl_l.visible = not compact
	_lvl_bar.visible = not compact
	var cols := 1 if tabs else 4
	if not force and absf(u - _u) < 0.001 and cols == _cols:
		return
	_u = u
	_cols = cols
	_grid.columns = cols
	_mix_grid.columns = 2
	_tabrow.visible = cols == 1
	_sub.visible = cols != 1 or true
	var gap := int(14.0 * u)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	for it in _texts:
		(it[0] as Control).add_theme_font_size_override("font_size", int(float(it[1]) * u))
	for it in _boxes:
		var c: Control = it[0]
		c.custom_minimum_size = Vector2(float(it[1]) * u, float(it[2]) * u * hk)
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
	_show_cards()


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
	for key in DhProgress.UNLOCK:
		if key.begins_with("theme:") or not _locked(String(key)):
			continue
		out[key] = (1.0 if typeof(cfg[key]) == TYPE_FLOAT else (0 if typeof(cfg[key]) == TYPE_INT else false))
	if _locked("theme:" + String(out["theme"])):
		out["theme"] = "alpine"
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


var _cam_warm: bool = false


## The camera and the tracker take a few seconds to wake up: the first touch of the menu starts them, so that by the time START is pressed they are nearly ready (the camera stays off for anyone who only landed here).
func _input(event: InputEvent) -> void:
	if _cam_warm or not OS.has_feature("web") or str(JavaScriptBridge.eval("window.location.search")).contains("nocam"):
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_cam_warm = true
		GazeProvider.start_camera()
