class_name GazeOptions
extends CanvasLayer
## The in-game test panel for the eye-tracking layers (Peek and Downhill): every filter and helper between your eyes and the
## game can be switched on or off while you play, with the live numbers beside them. EYE OPTIONS button (bottom right) or O.
## Settings are kept between visits; "bare" turns all the helping layers off at once, "defaults" puts them back.

var _btn: Button
var _panel: PanelContainer
var _rows: Dictionary = {}
var _info: Label
var _note: Label
var _cam_btn: Button
var _cap_btn: Button
var _share_btn: Button
var _who_box: LineEdit
var _note_box: LineEdit
var _sweep_ui: Control
var _consent: PanelContainer
var _was_paused: bool = false
var _t: float = 0.0
var _built: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _mk_button(text: String, parent: Node, fs: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", fs)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.16, 0.26, 0.95)))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.26, 0.4, 0.95)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.4, 0.6, 0.95)))
	parent.add_child(b)
	return b


func _build() -> void:
	GazeProvider.sweep_changed.connect(_on_sweep_any)
	_consent = PanelContainer.new()
	_consent.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.94)))
	_consent.anchor_left = 0.5
	_consent.anchor_right = 0.5
	_consent.anchor_top = 1.0
	_consent.anchor_bottom = 1.0
	_consent.offset_left = -330.0
	_consent.offset_right = 330.0
	_consent.offset_top = -150.0
	_consent.offset_bottom = -14.0
	_consent.visible = false
	add_child(_consent)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 8)
	_consent.add_child(cvb)
	var cl := Label.new()
	cl.text = "Help improve eye tracking? Share anonymous performance numbers (speed, tracking quality, which gate you picked). No camera images, no video, no name."
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.add_theme_font_size_override("font_size", 17)
	cvb.add_child(cl)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	cvb.add_child(crow)
	var yes := _mk_button("Share numbers", crow, 17)
	yes.alignment = HORIZONTAL_ALIGNMENT_CENTER
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		GazeProvider.set_share(true)
		_consent.visible = false)
	var no := _mk_button("No thanks", crow, 17)
	no.alignment = HORIZONTAL_ALIGNMENT_CENTER
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		GazeProvider.set_share(false)
		_consent.visible = false)
	_sweep_ui = Control.new()
	_sweep_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sweep_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep_ui.visible = false
	_sweep_ui.draw.connect(_draw_sweep_ui)
	add_child(_sweep_ui)
	_btn = Button.new()
	_btn.text = "EYE OPTIONS"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 16)
	_btn.add_theme_stylebox_override("normal", _style(Color(0.1, 0.2, 0.4, 0.8)))
	_btn.add_theme_stylebox_override("hover", _style(Color(0.2, 0.3, 0.55, 0.9)))
	_btn.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.45, 0.7, 0.9)))
	_btn.anchor_left = 1.0
	_btn.anchor_right = 1.0
	_btn.anchor_top = 1.0
	_btn.anchor_bottom = 1.0
	_btn.offset_left = -160.0
	_btn.offset_right = -10.0
	_btn.offset_top = -50.0
	_btn.offset_bottom = -10.0
	_btn.pressed.connect(toggle)
	add_child(_btn)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.93)))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -400.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = -56.0
	_panel.visible = false
	add_child(_panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(370, 0)
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	var head := Label.new()
	head.text = "EYE OPTIONS  (O)"
	head.add_theme_font_size_override("font_size", 22)
	vb.add_child(head)
	for d: Array in GazeProvider.opt_defs():
		var key: String = d[0]
		var b := _mk_button("", vb)
		b.pressed.connect(_on_opt.bind(key))
		_rows[key] = b
	_who_box = LineEdit.new()
	_who_box.placeholder_text = "tester name (kept between visits)"
	_who_box.custom_minimum_size = Vector2(0, 38)
	_who_box.add_theme_font_size_override("font_size", 16)
	_who_box.text = GazeProvider.tester_name() if GazeProvider.tester_name() != "unnamed" else ""
	_who_box.text_submitted.connect(func(t: String) -> void:
		GazeProvider.set_tester(t)
		_note.text = "logging as '%s'" % GazeProvider.tester_name()
		_who_box.release_focus())
	_who_box.focus_exited.connect(func() -> void:
		if _who_box.text.strip_edges() != "":
			GazeProvider.set_tester(_who_box.text))
	vb.add_child(_who_box)
	_note_box = LineEdit.new()
	_note_box.placeholder_text = "note: what do you notice? (Enter saves it)"
	_note_box.custom_minimum_size = Vector2(0, 38)
	_note_box.add_theme_font_size_override("font_size", 16)
	_note_box.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() == "":
			return
		var rep := GazeProvider.options_report()
		GazeProvider.post_stream("note", {"text": t.substr(0, 400), "mode": "downhill" if Game.downhill_mode else ("peek" if Game.peek_mode else "other"), "gaze": [snappedf(GazeProvider.gaze.x, 0.01), snappedf(GazeProvider.gaze.y, 0.01)],
			"opts": {"kalman": GazeProvider.kal_on, "hold": GazeProvider.hold_on, "median": GazeProvider.geo_win, "pick": GazeProvider.opt_pick, "stretch": GazeProvider.bias.stretch_on, "learn": GazeProvider.bias.learn_on, "auto": GazeProvider.auto_on}, "health": rep.get("health", {})})
		_note.text = "note saved: " + t.substr(0, 60)
		_note_box.text = ""
		_note_box.release_focus())
	vb.add_child(_note_box)
	_share_btn = _mk_button("", vb, 15)
	_share_btn.pressed.connect(func() -> void:
		GazeProvider.set_share(GazeProvider.share_state != "1")
		_refresh())
	_cap_btn = _mk_button("", vb, 15)
	_cap_btn.pressed.connect(_on_cap)
	_cam_btn = _mk_button("Camera: ?", vb, 15)
	_cam_btn.pressed.connect(_on_cam)
	var tb := _mk_button("TUNE: auto-cycle the options with a lit gate", vb, 16)
	tb.pressed.connect(_on_action.bind("tune"))
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	vb.add_child(act)
	for a: Array in [["BARE", "bare"], ["DEFAULTS", "defaults"], ["SWEEP", "sweep"], ["COPY LOG", "log"]]:
		var b2 := _mk_button(a[0], act, 15)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b2.pressed.connect(_on_action.bind(a[1]))
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 14)
	_note.modulate = Color(0.6, 1.0, 0.7)
	vb.add_child(_note)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.modulate = Color(1, 1, 1, 0.75)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	_built = true
	_refresh()


## The sweep calibration: a dot waits, then glides round the screen edge and back to the middle. Follow it with your eyes only.
func _draw_sweep_ui() -> void:
	var sz := _sweep_ui.size
	var t := GazeProvider.sweep_t
	var p := EyeSweep.dot(t) * sz
	var font := ThemeDB.fallback_font
	_sweep_ui.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.08, 0.65))
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 140.0)
	var moving := t >= 0.0
	var col := Color(0.4, 1.0, 0.5) if moving else Color(1.0, 0.85, 0.3)
	_sweep_ui.draw_circle(p, 34.0 * pulse, Color(col, 0.25))
	_sweep_ui.draw_circle(p, 13.0, col)
	var msg := "FOLLOW THE DOT WITH YOUR EYES" if moving else "READY? find the dot"
	var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_sweep_ui.draw_string_outline(font, Vector2(sz.x * 0.5 - mw * 0.5, sz.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, Color(0, 0, 0, 0.9))
	_sweep_ui.draw_string(font, Vector2(sz.x * 0.5 - mw * 0.5, sz.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	var sub := "keep your head still, only your eyes move   (tap or press a key to skip)"
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_sweep_ui.draw_string(font, Vector2(sz.x * 0.5 - sw * 0.5, sz.y * 0.5 + 32.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85))


## Any app holds still while the calibration dot goes round (and is back as it was afterwards).
func _on_sweep_any(active: bool) -> void:
	if active:
		_was_paused = get_tree().paused
		get_tree().paused = true
	else:
		get_tree().paused = _was_paused


func toggle() -> void:
	_panel.visible = not _panel.visible
	_refresh()


func _on_opt(key: String) -> void:
	GazeProvider.opt_next(key)
	GazeProvider.post_stream("opt", {"key": key, "value": str(GazeProvider.opt_value(key)), "by": "hand"})
	_refresh()


func _on_cap() -> void:
	GazeProvider.capture_on = not GazeProvider.capture_on
	_note.text = "saving a face crop and the tracker's numbers every ~1 s to tools/frames on the dev laptop ONLY (max %d); switch off to stop" % GazeProvider.CAPTURE_MAX if GazeProvider.capture_on else "frame saving off"
	_refresh()


func _on_cam() -> void:
	if GazeProvider.cam_next():
		_note.text = "switching camera: a few seconds, allow it if asked"
	else:
		_note.text = "only one camera found (names show once the camera is on)"


func _on_action(which: String) -> void:
	match which:
		"bare":
			GazeProvider.opts_bare()
			_note.text = "bare: every helping layer off, gate pick by gaze zones"
		"defaults":
			GazeProvider.opts_default()
			_note.text = "defaults restored"
		"sweep":
			_panel.visible = false
			if not GazeProvider.start_sweep():
				_panel.visible = true
				_note.text = "sweep: " + GazeProvider.sweep_note
		"tune":
			if Game.downhill_mode:
				GazeProvider.tune_request = true
				_panel.visible = false
				_note.text = ""
			else:
				_note.text = "the tuning session runs in Downhill"
		"log":
			DisplayServer.clipboard_set(JSON.stringify(GazeProvider.options_report(), "  "))
			_note.text = "log copied (%d barriers)" % GazeProvider.gate_log.size()
	_refresh()


func _refresh() -> void:
	if not _built:
		return
	for d: Array in GazeProvider.opt_defs():
		var key: String = d[0]
		(_rows[key] as Button).text = "%s:  %s" % [d[1], GazeProvider.opt_label(key)]
	_btn.text = "EYE OPTIONS" + (" *" if GazeProvider.opts_changed() else "")
	_share_btn.text = "Share anonymous numbers with the developer: " + ("ON" if GazeProvider.share_state == "1" else "off")
	_cap_btn.text = ("REC  saving camera frames to the dev laptop: ON (%d)" % GazeProvider.capture_n) if GazeProvider.capture_on else "Save camera frames (local only): off"
	_cap_btn.modulate = Color(1.0, 0.5, 0.5) if GazeProvider.capture_on else Color.WHITE
	var cl := GazeProvider.cam_label()
	_cam_btn.text = "Camera: %s   (%d found, tap to switch)" % [cl.substr(0, 34), GazeProvider.cam_list().size()]
	var g := GazeProvider
	var lines: Array[String] = []
	if not g.doctor.log.is_empty():
		var dl: Dictionary = g.doctor.log[g.doctor.log.size() - 1]
		lines.append("doctor: %s -> %s: %s" % [dl.get("issue"), dl.get("action"), dl.get("verdict")])
	if not g.doctor.pending.is_empty():
		lines.append("doctor is checking: %s (%d / %d barriers)" % [str((g.doctor.pending["action"] as Dictionary)["label"]), int(g.doctor.pending["seen"]), GazeDoctor.WIN])
	lines.append("gaze x %.2f  y %.2f   head turn %+.0f deg" % [g.gaze.x, g.gaze.y, -rad_to_deg(g.head_rpy.x)])
	lines.append("offset %+.0f%% %+.0f%%   scale x%.2f..%.2f   %s" % [g.bias.bias.x * 100.0, g.bias.bias.y * 100.0, g.bias.scale_lo.x, g.bias.scale_hi.x, "LOCKED by sweep" if g.bias.cal_locked else "self-learned"])
	if g.sweep_note != "":
		lines.append("sweep: " + g.sweep_note)
	if g.gate_log.size() > 0:
		var e: Dictionary = g.gate_log[g.gate_log.size() - 1]
		lines.append("last barrier: gates at %s, you looked at %.2f (range %.2f..%.2f), went through gate %s of %s" % [str(e.get("gates", [])), float(e.get("cur_med", 0.0)), float(e.get("cur_min", 0.0)), float(e.get("cur_max", 0.0)), str(e.get("went", "?")), str(e.get("n", "?"))])
	_info.text = "\n".join(lines)


func _input(event: InputEvent) -> void:
	if GazeProvider.sweep_active:
		var skip := (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if skip:
			GazeProvider.cancel_sweep()
			get_viewport().set_input_as_handled()
		return
	if not _btn.visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_O:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_consent.visible = GazeProvider.consent_needed() and not GazeProvider.sweep_active
	_sweep_ui.visible = GazeProvider.sweep_active
	if _sweep_ui.visible:
		_sweep_ui.queue_redraw()
	var on := (Game.peek_mode or Game.downhill_mode) and GazeProvider.dev_mode          # the panel is for testers (?dev or ?who=); the doctor works without it
	_btn.visible = on
	if not on:
		_panel.visible = false
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		if _panel.visible:
			_refresh()
