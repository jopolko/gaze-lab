class_name Draw2D
## Circles, arcs, polylines and filled polygons for HUD drawing that cost the graphics chip nothing extra.
##
## Why this exists: in the browser renderer, CanvasItem.draw_circle / draw_arc / draw_polyline / draw_colored_polygon each make a brand-new
## vertex buffer (and a vertex array) on the graphics chip every time they are drawn, and throw it away at the next redraw. A HUD that
## redraws every frame with a hundred of them makes and destroys a hundred buffers a frame, which on a laptop's built-in graphics takes
## longer than drawing the whole 3D scene. These helpers draw the same shapes from quads and one shared disc texture, which the renderer
## batches without allocating anything.

static var _discs: Array = []          # [size px, ImageTexture], small to large
static var _one := PackedColorArray([Color.WHITE])
static var _q := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _t := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _no_uv := PackedVector2Array()


static func _disc_for(r: float) -> Texture2D:
	if _discs.is_empty():
		for size: int in [24, 64, 192]:
			var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
			var h := float(size) * 0.5
			for y in size:
				for x in size:
					var d := Vector2(float(x) + 0.5 - h, float(y) + 0.5 - h).length()
					img.set_pixel(x, y, Color(1, 1, 1, clampf(h - 0.5 - d, 0.0, 1.0)))
			_discs.append([size, ImageTexture.create_from_image(img)])
	for e: Array in _discs:
		if float(e[0]) >= r * 1.5:
			return e[1]
	return _discs[_discs.size() - 1][1]


## A filled circle.
static func circle(ci: CanvasItem, pos: Vector2, r: float, col: Color) -> void:
	if r <= 0.0 or col.a <= 0.0:
		return
	var rr := r + 0.5
	ci.draw_texture_rect(_disc_for(r), Rect2(pos - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, col)


static func _quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_q[0] = a
	_q[1] = b
	_q[2] = c
	_q[3] = d
	_one[0] = col
	ci.draw_primitive(_q, _one, _no_uv)


## A ring section, same arguments as CanvasItem.draw_arc.
static func arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float = -1.0, aa: bool = false) -> void:
	if col.a <= 0.0 or r <= 0.0 or is_equal_approx(a0, a1):
		return
	var hw := maxf(w, 1.0) * 0.5
	var r0 := maxf(r - hw, 0.0)
	var r1 := r + hw
	var span := a1 - a0
	var segs := clampi(mini(n, int(ceil(absf(span) * maxf(r1, 6.0) / 5.0))), 3, 48)       # no more pieces than the size can show
	var st := span / float(segs)
	var dir := Vector2(cos(a0), sin(a0))
	var cs := cos(st)
	var sn := sin(st)
	var pi0 := c + dir * r0
	var po0 := c + dir * r1
	var clear := Color(col.r, col.g, col.b, 0.0)
	var pf0 := c + dir * (r1 + 1.0)
	var pg0 := c + dir * maxf(r0 - 1.0, 0.0)
	for i in segs:
		dir = Vector2(dir.x * cs - dir.y * sn, dir.x * sn + dir.y * cs)
		var pi1 := c + dir * r0
		var po1 := c + dir * r1
		_quad(ci, pi0, po0, po1, pi1, col)
		if aa:
			var pf1 := c + dir * (r1 + 1.0)
			var pg1 := c + dir * maxf(r0 - 1.0, 0.0)
			_feather(ci, po0, po1, pf1, pf0, col, clear)
			_feather(ci, pi0, pi1, pg1, pg0, col, clear)
			pf0 = pf1
			pg0 = pg1
		pi0 = pi1
		po0 = po1


static var _c4 := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])


static func _feather(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, clear: Color) -> void:
	_q[0] = a
	_q[1] = b
	_q[2] = c
	_q[3] = d
	_c4[0] = col
	_c4[1] = col
	_c4[2] = clear
	_c4[3] = clear
	ci.draw_primitive(_q, _c4, _no_uv)


## Connected line segments, same arguments as CanvasItem.draw_polyline. Thick lines get a round dot at each corner.
static func pline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float = -1.0, aa: bool = false) -> void:
	var m := pts.size()
	if m < 2 or col.a <= 0.0:
		return
	var ww := maxf(w, 1.0)
	for i in m - 1:
		ci.draw_line(pts[i], pts[i + 1], col, ww, aa)
	if ww >= 3.0 and col.a >= 0.99:                      # round the corners (only when opaque: an overlapping dot would show through a see-through line)
		for i in range(1, m - 1):
			circle(ci, pts[i], ww * 0.5, col)


## A filled polygon, same arguments as CanvasItem.draw_colored_polygon.
static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var m := pts.size()
	if m < 3 or col.a <= 0.0:
		return
	_one[0] = col
	if m == 3:
		ci.draw_primitive(pts, _one, _no_uv)
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		_t[0] = pts[idx[i]]
		_t[1] = pts[idx[i + 1]]
		_t[2] = pts[idx[i + 2]]
		ci.draw_primitive(_t, _one, _no_uv)
