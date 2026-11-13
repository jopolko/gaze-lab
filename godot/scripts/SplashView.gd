class_name SplashView
extends Control
## The welcome screen: the emblem (a ring, two peaks, and the sun as an iris), the title, the promise, and eight one-word pictograms that say what the eyes do.
## Drawn in code so it matches any screen shape and stays sharp. It sits over the live 3D backdrop; any tap, click or key moves on to the settings.

signal done

const ICONS := ["STEER", "LOCK", "JUMP", "SPIN", "EAT", "SHIELD", "BRACE", "FACE"]

var _t: float = 0.0
var _go: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		_finish()
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_finish()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if _go or _t < 0.4:
		return
	_go = true
	done.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var portrait := h > w * 1.05
	var s := (minf(w, h) / 720.0) * (0.62 if portrait else 1.0)
	var fade := clampf(_t / 0.6, 0.0, 1.0)
	# a soft wash so everything reads over any backdrop
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.10, 0.45 * fade))
	var font := ThemeDB.fallback_font
	var white := Color(1, 1, 1, fade)
	# emblem
	var c := Vector2(w * 0.5, h * (0.24 if not portrait else 0.2))
	var r := 120.0 * s
	draw_arc(c + Vector2(0, 20.0 * s), r, deg_to_rad(150.0), deg_to_rad(390.0), 48, white, 12.0 * s, true)
	var peaks := PackedVector2Array([c + Vector2(-84, 66) * s, c + Vector2(-36, -14) * s, c + Vector2(-4, 34) * s, c + Vector2(30, -34) * s, c + Vector2(84, 66) * s])
	draw_colored_polygon(peaks, white)
	draw_arc(c + Vector2(50, -48) * s, 13.0 * s, 0.0, TAU, 24, white, 6.0 * s, true)
	draw_circle(c + Vector2(50, -48) * s, 4.0 * s, white)
	# title
	var tsz := int(110.0 * s)
	var title := "DOWNHILL"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	var ty := h * (0.50 if not portrait else 0.36)
	draw_string_outline(font, Vector2(w * 0.5 - tw * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, int(10.0 * s), Color(0.05, 0.08, 0.25, 0.8 * fade))
	draw_string(font, Vector2(w * 0.5 - tw * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, white)
	var sub := "S T E E R   B Y   E Y E"
	var ssz := int(26.0 * s)
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ssz).x
	draw_string(font, Vector2(w * 0.5 - sw * 0.5, ty + 42.0 * s), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ssz, Color(1, 1, 1, 0.9 * fade))
	# the pictograms
	var per_row := 8 if not portrait else 4
	var rows := ICONS.size() / per_row
	var cell := minf(w * 0.92 / float(per_row), 150.0 * s * 1.3)
	var rr := cell * 0.34
	var y0 := h * (0.72 if not portrait else 0.52)
	for i in ICONS.size():
		var col := i % per_row
		var row := i / per_row
		var cx := w * 0.5 + (float(col) - float(per_row - 1) * 0.5) * cell
		var cy := y0 + float(row) * cell * 1.12
		var a := clampf((_t - 0.5 - float(i) * 0.08) / 0.35, 0.0, 1.0)
		if a <= 0.0:
			continue
		var cc := Vector2(cx, cy)
		draw_circle(cc, rr, Color(0.04, 0.06, 0.2, 0.40 * a))
		draw_arc(cc, rr, 0.0, TAU, 40, Color(1, 1, 1, 0.8 * a), 2.5 * s, true)
		_icon(i, cc, rr / 34.0 * 0.78, Color(1, 1, 1, a))
		var label: String = ICONS[i]
		var lsz := int(20.0 * s)
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
		draw_string(font, Vector2(cx - lw * 0.5, cy + rr + 30.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, Color(1, 1, 1, a))
	# the invitation
	var hint := "TAP TO BEGIN"
	var hsz := int(30.0 * s)
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hsz).x
	var pulse := 0.55 + 0.45 * sin(_t * 3.0)
	draw_string(font, Vector2(w * 0.5 - hw * 0.5, h * 0.95), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hsz, Color(1, 1, 1, pulse * fade))


## One pictogram in a box of about +-34 units, scaled by u.
func _icon(i: int, c: Vector2, u: float, col: Color) -> void:
	var lw := 4.5 * u
	match i:
		0:   # STEER: two eyes looking aside, an arrow
			draw_arc(c + Vector2(-13, -6) * u, 11.0 * u, 0.0, TAU, 20, col, lw * 0.7, true)
			draw_arc(c + Vector2(13, -6) * u, 11.0 * u, 0.0, TAU, 20, col, lw * 0.7, true)
			draw_circle(c + Vector2(-8, -5) * u, 4.5 * u, col)
			draw_circle(c + Vector2(18, -5) * u, 4.5 * u, col)
			draw_polyline(PackedVector2Array([c + Vector2(-12, 20) * u, c + Vector2(18, 20) * u]), col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(10, 13) * u, c + Vector2(19, 20) * u, c + Vector2(10, 27) * u]), col, lw, true)
		1:   # LOCK: an eye on a gate
			draw_arc(c, 18.0 * u, 0.0, TAU, 24, col, lw, true)
			draw_circle(c, 5.0 * u, col)
			for d in [Vector2(0, -28), Vector2(0, 28), Vector2(-28, 0), Vector2(28, 0)]:
				draw_line(c + d * u * 0.72, c + d * u, col, lw, true)
		2:   # JUMP: a ramp and an arrow up
			draw_polyline(PackedVector2Array([c + Vector2(-26, 22) * u, c + Vector2(16, 22) * u, c + Vector2(16, -6) * u, c + Vector2(-26, 22) * u]), col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(20, -8) * u, c + Vector2(30, -26) * u]), col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(20, -26) * u, c + Vector2(31, -26) * u, c + Vector2(31, -14) * u]), col, lw, true)
		3:   # SPIN: a circling arrow around a board
			draw_arc(c, 22.0 * u, deg_to_rad(40.0), deg_to_rad(330.0), 28, col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(-30, -6) * u, c + Vector2(-20, 6) * u, c + Vector2(-10, -4) * u]), col, lw, true)
			draw_arc(c + Vector2(0, 6) * u, 12.0 * u, 0.0, TAU, 16, col, lw * 0.6, true)
		4:   # EAT: a burger
			draw_arc(c + Vector2(0, -4) * u, 24.0 * u, PI, TAU, 20, col, lw, true)
			draw_line(c + Vector2(-26, -4) * u, c + Vector2(26, -4) * u, col, lw, true)
			draw_line(c + Vector2(-24, 6) * u, c + Vector2(24, 6) * u, col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(-24, 14) * u, c + Vector2(24, 14) * u, c + Vector2(20, 24) * u, c + Vector2(-20, 24) * u, c + Vector2(-24, 14) * u]), col, lw, true)
		5:   # SHIELD
			draw_polyline(PackedVector2Array([c + Vector2(0, -26) * u, c + Vector2(22, -17) * u, c + Vector2(22, 3) * u, c + Vector2(0, 28) * u, c + Vector2(-22, 3) * u, c + Vector2(-22, -17) * u, c + Vector2(0, -26) * u]), col, lw, true)
			draw_circle(c + Vector2(0, -2) * u, 6.0 * u, col)
		6:   # BRACE: a ball hits, speed lines
			draw_arc(c + Vector2(8, 0) * u, 20.0 * u, 0.0, TAU, 24, col, lw, true)
			draw_polyline(PackedVector2Array([c + Vector2(-6, -6) * u, c + Vector2(4, 0) * u, c + Vector2(-6, 6) * u]), col, lw, true)
			for yy in [-14.0, 2.0, 18.0]:
				draw_line(c + Vector2(-30, yy) * u, c + Vector2(-16, yy) * u, col, lw, true)
		7:   # FACE: a goofy face, tongue out
			draw_arc(c, 26.0 * u, 0.0, TAU, 28, col, lw, true)
			draw_line(c + Vector2(-12, -8) * u, c + Vector2(-12, -1) * u, col, lw, true)
			draw_line(c + Vector2(12, -8) * u, c + Vector2(12, -1) * u, col, lw, true)
			draw_arc(c + Vector2(0, 4) * u, 14.0 * u, deg_to_rad(20.0), deg_to_rad(160.0), 12, col, lw, true)
			draw_line(c + Vector2(4, 18) * u, c + Vector2(4, 26) * u, col, lw * 1.2, true)
