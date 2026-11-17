class_name SplashView
extends Control
## The welcome screen: the emblem (a ring, two peaks, and the sun as an iris), the title, the promise, and eight one-word pictograms that say what the eyes do.
## Drawn in code so it matches any screen shape and stays sharp. It sits over the live 3D backdrop; any tap, click or key moves on to the settings.

signal done

const ICONS := ["LOOK TO STEER", "RAMP = BLAST!", "STARE AT ROCKS", "MAKE FACES"]
const BADGE := [Color(0.20, 0.45, 0.95), Color(0.62, 0.22, 0.85), Color(0.90, 0.38, 0.18), Color(0.12, 0.65, 0.55)]

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
	if OS.has_feature("web"):                                 # the first tap is the one moment a browser lets a page go full screen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		JavaScriptBridge.eval("(function(){try{if(screen.orientation&&screen.orientation.lock){screen.orientation.lock('landscape').catch(function(){});}}catch(e){}})()")
	done.emit()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var portrait := h > w * 1.05
	var s := (minf(w, h) / 720.0) * (0.62 if portrait else 1.0)
	var fade := clampf(_t / 0.6, 0.0, 1.0)
	# a soft wash so everything reads over any backdrop
	# a colour wash instead of a dark one: violet at the top to peach at the bottom, so the backdrop reads bright and the badges sit in it
	var sky := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var skc := PackedColorArray([Color(0.35, 0.30, 0.85, 0.55 * fade), Color(0.35, 0.30, 0.85, 0.55 * fade), Color(1.0, 0.60, 0.45, 0.45 * fade), Color(1.0, 0.60, 0.45, 0.45 * fade)])
	draw_polygon(sky, skc)
	var font := ThemeDB.fallback_font
	var white := Color(1, 1, 1, fade)
	# emblem
	var c := Vector2(w * 0.5, h * (0.24 if not portrait else 0.2))
	var r := 120.0 * s
	Draw2D.arc(self, c + Vector2(0, 20.0 * s), r, deg_to_rad(150.0), deg_to_rad(390.0), 48, white, 12.0 * s, true)
	var peaks := PackedVector2Array([c + Vector2(-84, 66) * s, c + Vector2(-36, -14) * s, c + Vector2(-4, 34) * s, c + Vector2(30, -34) * s, c + Vector2(84, 66) * s])
	Draw2D.poly(self, peaks, white)
	Draw2D.arc(self, c + Vector2(50, -48) * s, 13.0 * s, 0.0, TAU, 24, white, 6.0 * s, true)
	Draw2D.circle(self, c + Vector2(50, -48) * s, 4.0 * s, white)
	# title
	var tsz := int(110.0 * s)
	var title := "DOWNHILL"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	var ty := h * (0.50 if not portrait else 0.36)
	draw_string_outline(font, Vector2(w * 0.5 - tw * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, int(10.0 * s), Color(0.05, 0.08, 0.25, 0.8 * fade))
	draw_string(font, Vector2(w * 0.5 - tw * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, white)
	var sub := "STEER WITH YOUR EYES!  MAKE FACES!"
	var ssz := int(26.0 * s)
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ssz).x
	draw_string(font, Vector2(w * 0.5 - sw * 0.5, ty + 42.0 * s), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ssz, Color(1, 1, 1, 0.9 * fade))
	# the pictograms
	var per_row := 4 if not portrait else 2
	var rows := ICONS.size() / per_row
	var cell := minf(w * 0.92 / float(per_row), 230.0 * s * 1.3)
	var rr := cell * 0.30
	var y0 := h * (0.74 if not portrait else 0.54)
	for i in ICONS.size():
		var col := i % per_row
		var row := i / per_row
		var cx := w * 0.5 + (float(col) - float(per_row - 1) * 0.5) * cell
		var cy := y0 + float(row) * cell * 1.2
		var a := clampf((_t - 0.5 - float(i) * 0.08) / 0.35, 0.0, 1.0)
		if a <= 0.0:
			continue
		var cc := Vector2(cx, cy)
		cc.y += sin(_t * 2.4 + float(i) * 1.3) * rr * 0.05
		var bc: Color = BADGE[i]
		Draw2D.circle(self, cc, rr, Color(bc.r, bc.g, bc.b, a))
		Draw2D.arc(self, cc, rr, 0.0, TAU, 40, Color(1, 1, 1, a), 5.0 * s, true)
		_icon(i, cc, rr / 34.0 * 0.9, a)
		var label: String = ICONS[i]
		var lsz := int(26.0 * s)
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
		draw_string(font, Vector2(cx - lw * 0.5, cy + rr + 34.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz, Color(1, 1, 1, a))
	# the invitation
	var hint := "TAP TO BEGIN"
	var hsz := int(30.0 * s)
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hsz).x
	var pulse := 0.55 + 0.45 * sin(_t * 3.0)
	draw_string(font, Vector2(w * 0.5 - hw * 0.5, h * 0.95), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hsz, Color(1, 1, 1, pulse * fade))


## One cartoon badge picture in a box of about +-34 units, scaled by u: fat shapes, bright fills, dark outlines, a face or a burst in each so it reads at a glance.
func _disc(c: Vector2, r: float, fill: Color, ink: Color, ow: float) -> void:
	Draw2D.circle(self, c, r, fill)
	Draw2D.arc(self, c, r, 0.0, TAU, 28, ink, ow, true)


func _star(c: Vector2, r1: float, r2: float, n: int, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in n * 2:
		var rr := r1 if k % 2 == 0 else r2
		var an := rot + PI * float(k) / float(n)
		pts.append(c + Vector2(cos(an), sin(an)) * rr)
	Draw2D.poly(self, pts, col)


func _icon(i: int, c: Vector2, u: float, a: float) -> void:
	var ink := Color(0.05, 0.06, 0.18, a)
	var white := Color(1, 1, 1, a)
	var ow := 3.2 * u
	match i:
		0:   # LOOK: two big googly eyes, pupils swung to one side, a little arrow past them
			for ex in [-15.0, 15.0]:
				_disc(c + Vector2(ex, -4) * u, 14.0 * u, white, ink, ow)
				_disc(c + Vector2(ex + 5.0, -2) * u, 6.5 * u, ink, ink, 1.0)
				Draw2D.circle(self, c + Vector2(ex + 7.0, -5) * u, 2.2 * u, white)
			Draw2D.pline(self, PackedVector2Array([c + Vector2(-20, 22) * u, c + Vector2(20, 22) * u]), Color(1.0, 0.9, 0.3, a), 5.0 * u, true)
			Draw2D.poly(self, PackedVector2Array([c + Vector2(16, 12) * u, c + Vector2(32, 22) * u, c + Vector2(16, 32) * u]), Color(1.0, 0.9, 0.3, a))
		1:   # RAMP: an orange kicker, a purple swirl over it, a yellow blast star
			_star(c + Vector2(14, -16) * u, 20.0 * u, 9.0 * u, 7, 0.3, Color(1.0, 0.9, 0.3, a))
			Draw2D.arc(self, c + Vector2(14, -16) * u, 11.0 * u, 0.0, TAU, 20, Color(1.0, 0.45, 0.9, a), 4.0 * u, true)
			var wedge := PackedVector2Array([c + Vector2(-30, 26) * u, c + Vector2(26, 26) * u, c + Vector2(26, 2) * u])
			Draw2D.poly(self, wedge, Color(1.0, 0.62, 0.15, a))
			Draw2D.pline(self, PackedVector2Array([wedge[0], wedge[1], wedge[2], wedge[0]]), ink, ow, true)
		2:   # STARE AT ROCKS: a grumpy rock that is cracking, bits flying
			var rock := PackedVector2Array([c + Vector2(-24, 20) * u, c + Vector2(-28, 0) * u, c + Vector2(-12, -20) * u, c + Vector2(12, -22) * u, c + Vector2(28, -2) * u, c + Vector2(24, 20) * u])
			Draw2D.poly(self, rock, Color(0.62, 0.64, 0.72, a))
			Draw2D.pline(self, PackedVector2Array([rock[0], rock[1], rock[2], rock[3], rock[4], rock[5], rock[0]]), ink, ow, true)
			Draw2D.pline(self, PackedVector2Array([c + Vector2(0, -22) * u, c + Vector2(-4, -6) * u, c + Vector2(6, 4) * u, c + Vector2(0, 20) * u]), ink, ow, true)
			Draw2D.circle(self, c + Vector2(-13, -4) * u, 3.4 * u, ink)
			Draw2D.circle(self, c + Vector2(13, -4) * u, 3.4 * u, ink)
			_star(c + Vector2(26, -24) * u, 9.0 * u, 4.0 * u, 5, 0.0, Color(1.0, 0.9, 0.3, a))
			_star(c + Vector2(-28, -22) * u, 7.0 * u, 3.0 * u, 5, 0.5, Color(1.0, 0.9, 0.3, a))
		3:   # MAKE FACES: a big yellow face with its tongue out
			_disc(c, 27.0 * u, Color(1.0, 0.85, 0.25, a), ink, ow)
			Draw2D.circle(self, c + Vector2(-10, -8) * u, 4.6 * u, ink)
			Draw2D.circle(self, c + Vector2(10, -8) * u, 4.6 * u, ink)
			Draw2D.poly(self, PackedVector2Array([c + Vector2(-4, 10) * u, c + Vector2(10, 10) * u, c + Vector2(10, 26) * u, c + Vector2(3, 31) * u, c + Vector2(-4, 26) * u]), Color(1.0, 0.45, 0.6, a))
			Draw2D.arc(self, c + Vector2(0, 2) * u, 16.0 * u, deg_to_rad(25.0), deg_to_rad(155.0), 14, ink, ow, true)
