class_name GazeTestRig
extends Node3D
## GAZE TEST: shows how precisely your eyes map to the screen. A dot lights up, you look at it for a moment, and the
## test records where the tracker thought you were looking. Lines run from each dot to the measured point, so the error is
## visible. It only MEASURES: nothing here is a calibration (the correction is learned silently while you play anything).
##
##   R restart   C centre (pins the automatic offset to the middle of the screen)
## Works with the camera (web), the UDP tracker, or the mouse (which should score near zero: a useful sanity check).

const COLS := 5
const ROWS := 3
const HOLD := 1.3
const SETTLE := 0.55
const N_TARGETS := 24
const SCORED_TAIL := 12            # the score uses the last 12: the first ones are the tracker learning your range

var player: PlayerController
var cam: Camera3D
var results: Array[Dictionary] = []
var done: bool = false

var _hud: Control
var _cells: Array[Vector2] = []
var _order: Array[int] = []
var _i: int = 0
var _t: float = 0.0
var _samples: Array[Vector2] = []
var _hist: Array[Vector2] = []
var _age: float = 0.0
var _restart_rect: Rect2 = Rect2()
var _rng := RandomNumberGenerator.new()


func setup(p_player: PlayerController) -> void:
	name = "GazeTestRig"
	player = p_player
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	for r in ROWS:
		for c in COLS:
			_cells.append(Vector2(lerpf(0.08, 0.92, float(c) / float(COLS - 1)), lerpf(0.16, 0.84, float(r) / float(ROWS - 1))))
	_rng.randomize()
	GazeProvider.bias.reset()
	GazeProvider.bias.exp_span = Vector2(0.76, 0.62)
	restart()


func restart() -> void:
	results.clear()
	_order.clear()
	var all: Array[int] = []
	for i in _cells.size():
		all.append(i)
	# a shuffled walk through the grid, repeating cells if more targets than cells
	while _order.size() < N_TARGETS:
		all.shuffle()
		for i in all:
			if _order.size() < N_TARGETS:
				_order.append(i)
	_i = 0
	_t = 0.0
	_samples.clear()
	done = false


func target() -> Vector2:
	return _cells[_order[mini(_i, _order.size() - 1)]]


func _process(delta: float) -> void:
	_age += delta
	var g := TrackerBridge.gaze
	_hist.append(g)
	if _hist.size() > 30:
		_hist.remove_at(0)
	if not done:
		_t += delta
		if _t > SETTLE:
			_samples.append(g)
		if _t >= HOLD:
			var med := GazeTestRig._median_point(_samples)
			var tgt := target()
			results.append({"target": tgt, "gaze": med, "err": med - tgt})
			_i += 1
			_t = 0.0
			_samples.clear()
			if _i >= _order.size():
				done = true
	_hud.size = get_viewport().get_visible_rect().size
	_hud.queue_redraw()


static func _median_point(a: Array[Vector2]) -> Vector2:
	if a.is_empty():
		return Vector2(0.5, 0.5)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for v in a:
		xs.append(v.x)
		ys.append(v.y)
	xs.sort()
	ys.sort()
	return Vector2(xs[xs.size() / 2], ys[ys.size() / 2])


## Mean distance of the measured point from the dot, as a fraction of the screen WIDTH (aspect-corrected).
func _tail() -> Array:
	var n := mini(SCORED_TAIL, results.size())
	return results.slice(results.size() - n)


func mean_error(aspect: float, tail_only: bool = true) -> float:
	var rs: Array = _tail() if tail_only else results
	if rs.is_empty():
		return 0.0
	var t := 0.0
	for r in rs:
		var e: Vector2 = r["err"]
		t += Vector2(e.x, e.y / maxf(aspect, 0.1)).length()
	return t / float(rs.size())


func mean_offset() -> Vector2:
	var rs: Array = _tail()
	var t := Vector2.ZERO
	for r in rs:
		t += r["err"] as Vector2
	return t / float(maxi(rs.size(), 1))


## How far each direction actually reached: the measured gaze for targets in the left / right columns and top / bottom rows,
## next to where those targets are. A direction that falls short is being compressed.
func reach() -> Dictionary:
	var sums := {"left": [0.0, 0], "right": [0.0, 0], "up": [0.0, 0], "down": [0.0, 0]}
	for r in _tail():
		var tp: Vector2 = r["target"]
		var gp: Vector2 = r["gaze"]
		if tp.x < 0.2:
			sums["left"][0] += gp.x
			sums["left"][1] += 1
		elif tp.x > 0.8:
			sums["right"][0] += gp.x
			sums["right"][1] += 1
		if tp.y < 0.3:
			sums["up"][0] += gp.y
			sums["up"][1] += 1
		elif tp.y > 0.7:
			sums["down"][0] += gp.y
			sums["down"][1] += 1
	var out := {}
	for kk in sums:
		out[kk] = float(sums[kk][0]) / float(sums[kk][1]) if int(sums[kk][1]) > 0 else -1.0
	return out


func jitter() -> float:
	if _hist.size() < 5:
		return 0.0
	var m := Vector2.ZERO
	for v in _hist:
		m += v
	m /= float(_hist.size())
	var s := 0.0
	for v in _hist:
		s += (v - m).length()
	return s / float(_hist.size())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_R:
				restart()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if _restart_rect.has_point((event as InputEventMouseButton).position):
			restart()
			get_viewport().set_input_as_handled()


func _hud_scale() -> float:
	return 2.0 if _hud.size.y > _hud.size.x * 1.05 else (1.25 if Game.touch_mode else 1.0)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	var fs := int(float(size) * _hud_scale())
	_hud.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	var aspect := s.x / maxf(s.y, 1.0)
	_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.05, 0.1, 1.0))
	# the grid
	for c in _cells:
		_hud.draw_circle(c * s, 5.0 * k, Color(1, 1, 1, 0.18))
	# measured results: dot, line, and where the gaze was
	for r in results:
		var tp: Vector2 = (r["target"] as Vector2) * s
		var gp: Vector2 = (r["gaze"] as Vector2) * s
		var e: Vector2 = r["err"]
		var bad := clampf(Vector2(e.x, e.y / aspect).length() / 0.15, 0.0, 1.0)
		var col := Color(0.4, 1.0, 0.5).lerp(Color(1.0, 0.3, 0.25), bad)
		_hud.draw_line(tp, gp, col, 3.0 * k)
		_hud.draw_circle(gp, 6.0 * k, col)
		_hud.draw_circle(tp, 8.0 * k, Color(1, 1, 1, 0.5))
	# the current dot
	if not done:
		var p := target() * s
		var prog := clampf(_t / HOLD, 0.0, 1.0)
		_hud.draw_circle(p, 24.0 * k * (1.0 + 0.12 * sin(_age * 8.0)), Color(1.0, 0.7, 0.15))
		_hud.draw_circle(p, 6.0 * k, Color.WHITE)
		_hud.draw_arc(p, 34.0 * k, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color.WHITE, 5.0 * k)
	# live gaze cursor
	var gp2 := TrackerBridge.gaze * s
	_hud.draw_arc(gp2, 13.0 * k, 0.0, TAU, 20, Color(0.5, 0.9, 1.0, 0.95), 2.5 * k)
	_hud.draw_circle(gp2, 3.0 * k, Color(0.5, 0.9, 1.0, 0.95))
	# panel (centre): status, then the result
	var x0 := s.x * 0.5 - 200.0 * k
	var y0 := s.y * 0.40
	_hud.draw_rect(Rect2(x0 - 12.0 * k, y0 - 30.0 * k, 424.0 * k, 280.0 * k), Color(0.04, 0.06, 0.14, 0.82))
	var src := TrackerBridge.source_label()
	var precise := GazeProvider._geo_limb and TrackerBridge.source == "camera"
	var mode := "PRECISE (iris edge fit)" if precise else ("landmark only" if TrackerBridge.source == "camera" else "no camera")
	_text(font, Vector2(x0, y0), "GAZE TEST   %s" % src, 20, Color(0.6, 1.0, 0.8))
	_text(font, Vector2(x0, y0 + 26.0 * k), "tracking: %s" % mode, 16, Color(1, 1, 1, 0.85))
	_text(font, Vector2(x0, y0 + 48.0 * k), "live jitter %.1f%% of the screen" % (jitter() * 100.0), 16, Color(1, 1, 1, 0.85))
	var b := GazeProvider.bias
	var lim := GazeProvider.limb_sample()
	var rate := float(GazeProvider._pkt_times.size()) / 2.0
	_text(font, Vector2(x0, y0 + 70.0 * k), "offset %+.0f%% %+.0f%%   scale x%.2f x%.2f   range %.0f%% %.0f%%%s" % [b.bias.x * 100.0, b.bias.y * 100.0, b.scale.x, b.scale.y, b.obs_span.x * 100.0, b.obs_span.y * 100.0, "   (LIMIT)" if b.saturated else ""], 14, Color(1, 1, 1, 0.7))
	var raw := "iris %.1f px  |  %.0f readings/s  |  raw gaze %.2f, %.2f  |  eye-in-box %s  |  head %+.2f %+.2f" % [GazeProvider.limb_rad, rate, GazeProvider._geo_raw.x, GazeProvider._geo_raw.y, ("%.2f, %.2f" % [lim[0], lim[1]]) if not lim.is_empty() else "none", GazeProvider.head_rpy.x, GazeProvider.head_rpy.y]
	_text(font, Vector2(x0 - 100.0 * k, y0 + 150.0 * k), raw, 13, Color(0.7, 0.85, 1.0, 0.85))
	if TrackerBridge.source == "camera" and rate > 0.0 and rate < 20.0:
		_text(font, Vector2(x0, y0 + 196.0 * k), "camera gives only %.0f frames/s (dim light slows it): open the page with ?fast and good light for ~30" % rate, 14, Color(1.0, 0.75, 0.4))
	if GazeProvider.limb_rad > 0.0 and GazeProvider.limb_rad < 9.0 and TrackerBridge.source == "camera":
		_text(font, Vector2(x0, y0 + 170.0 * k), "the iris is only %.0f px wide: sit closer, add light, or open the page with ?res=1080" % (GazeProvider.limb_rad * 2.0), 14, Color(1.0, 0.75, 0.4))
	if done:
		var me := mean_error(aspect)
		var off := mean_offset()
		var verdict := "EXCELLENT" if me < 0.04 else ("GOOD" if me < 0.08 else ("OK" if me < 0.14 else "LOOSE"))
		var early := mean_error(aspect, false)
		_text(font, Vector2(x0, y0 + 102.0 * k), "AVERAGE ERROR  %.1f%% of the screen width   %s" % [me * 100.0, verdict], 20, Color(1.0, 0.9, 0.5))
		_text(font, Vector2(x0, y0 + 124.0 * k), "(over all %d dots: %.1f%%; the last %d use what it learned)" % [results.size(), early * 100.0, SCORED_TAIL], 13, Color(1, 1, 1, 0.7))
		var rc := reach()
		_text(font, Vector2(x0 - 100.0 * k, y0 + 190.0 * k), "reach (read / target):  left %s / 0.08   right %s / 0.92   up %s / 0.16   down %s / 0.84" % [_fmt(rc["left"]), _fmt(rc["right"]), _fmt(rc["up"]), _fmt(rc["down"])], 14, Color(1.0, 0.85, 0.5))
		_text(font, Vector2(x0, y0 + 142.0 * k), "tends to read %+.1f%% x, %+.1f%% y off   (press C to re-centre, R to retry)" % [off.x * 100.0, off.y * 100.0], 14, Color(1, 1, 1, 0.8))
	else:
		_text(font, Vector2(x0, y0 + 102.0 * k), "look at the lit dot   %d / %d" % [mini(_i + 1, _order.size()), _order.size()], 20, Color(1.0, 0.9, 0.5))
		_text(font, Vector2(x0, y0 + 128.0 * k), "this only measures: it does not calibrate anything", 14, Color(1, 1, 1, 0.6))
	var rl := "[ RESTART ]"
	var rw := font.get_string_size(rl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_restart_rect = Rect2(s.x - rw - 40.0 * k, s.y - 56.0 * k, rw + 24.0 * k, 40.0 * k)
	_text(font, Vector2(_restart_rect.position.x + 12.0 * k, _restart_rect.position.y + 28.0 * k), rl, 20, Color(0.8, 0.9, 1.0))


func _fmt(v: float) -> String:
	return "%.2f" % v if v >= 0.0 else "-"


func cleanup() -> void:
	pass
