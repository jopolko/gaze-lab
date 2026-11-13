class_name EyeBias
extends RefCounted
## Automatic, invisible correction of the gaze point. No dots, no stare-at-this.
##
## The geometry model (head pose + depth from iris size + the screen's real size) already maps the eyes to the screen
## with the right scale. What it cannot know is each person's constant offset (the eye's optical axis is about 5 degrees
## off the line of sight, the camera may sit off-centre, the head may be habitually tilted). That offset is steady, so it
## is learned while you play, from the one thing every game here has in common: the action is where you look.
##
##   * every ~1.5 s the median of your recent gaze is nudged toward `target` (screen centre, a little above the middle)
##   * vertical offset also learns a slow link to HEAD PITCH and eyelid APERTURE (a head tilted back squints the eyes and
##     shifts the vertical reading), by a small ridge regression over recent windows
##   * a confirmed event (a blink on a target, the CENTER button) pins it right away via anchor()
##   * only trusted while the face is roughly frontal; the correction is in screen terms and persists as the head moves,
##     and a better (more frontal) view keeps refining it
## apply() never returns anything outside the screen.

const WINDOW_FRAMES := 45
const MAX_BIAS := 0.45
const RATE := 0.18

var target: Vector2 = Vector2(0.5, 0.46)
var bias: Vector2 = Vector2.ZERO
var k_pitch: float = 0.0
var k_aper: float = 0.0
var windows_used: int = 0
## How much of the screen the player's gaze normally covers in this mode (a span from the 5th to the 95th percentile, as a
## screen fraction). (0, 0) = do not rescale. The physical model's scale is only a guess (screen size, viewing distance, eye
## size all vary), so the observed spread of the signal is used to correct it, slowly and within safe limits.
var exp_span: Vector2 = Vector2.ZERO
var scale: Vector2 = Vector2.ONE            # average of the two sides (for display)
## Each side of the centre is stretched on its own: eyes rotate more easily one way than the other, the iris edge is
## hidden differently near the nose and the temple, and a camera that is off to one side sees the two directions unequally.
var scale_lo: Vector2 = Vector2.ONE         # toward the left / top of the screen
var scale_hi: Vector2 = Vector2.ONE         # toward the right / bottom
var obs_span: Vector2 = Vector2.ZERO
var saturated: bool = false          # the offset hit its limit: the signal is too far off to trust
## After a sweep calibration the scale and offset come from measured pairs (eyes here, dot there): the spread-based stretching is
## switched off (it would fight the measurement) and the silent offset learning slows to a quarter, so a settled posture drifts
## gently instead of being pulled toward the middle.
var cal_locked: bool = false
var stretch_on: bool = true         # test switch: the spread-based stretching of each side of the screen
var learn_on: bool = true           # test switch: the silent offset learning toward the screen centre

var _u_buf: Array = []
var _v_buf: Array = []
const SPAN_FRAMES := 540
const SCALE_MIN := 0.6
const SCALE_MAX := 3.0
var anchors: int = 0

var _win: Array = []          # [u, v, pitch, aperture] per frame
var _hist: Array = []         # [need_y, pitch_med, ap_med] per window
var _pitch_ref: float = 0.0
var _ap_ref: float = 0.2
var _frontal_max: float = 0.5


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func add(u: float, v: float, pitch: float, aperture: float, active: bool = true) -> void:
	if not active or absf(pitch) > _frontal_max:
		return
	_win.append([u, v, pitch, aperture])
	_u_buf.append(u)
	_v_buf.append(v)
	if _u_buf.size() > SPAN_FRAMES:
		_u_buf.remove_at(0)
		_v_buf.remove_at(0)
	if _win.size() >= WINDOW_FRAMES:
		_window_done()


func _window_done() -> void:
	var us: Array = []
	var vs: Array = []
	var ps: Array = []
	var aps: Array = []
	for f in _win:
		us.append(f[0])
		vs.append(f[1])
		ps.append(f[2])
		aps.append(f[3])
	_win.clear()
	var mu: float = EyeBias._median(us)
	var mv: float = EyeBias._median(vs)
	var mp: float = EyeBias._median(ps)
	var ma: float = EyeBias._median(aps)
	windows_used += 1
	if not learn_on:
		_update_scale()
		return
	# horizontal: nudge the whole-window median toward the target
	bias.x = clampf(bias.x + RATE * (0.25 if cal_locked else 1.0) * (target.x - (mu + bias.x)), -MAX_BIAS, MAX_BIAS)
	# vertical: collect what offset this window needed, then fit it against head pitch and aperture
	_hist.append([target.y - mv, mp, ma])
	if _hist.size() > 30:
		_hist.remove_at(0)
	_fit_vertical()
	_update_scale()
	saturated = absf(bias.x) >= MAX_BIAS - 0.01 or absf(bias.y) >= MAX_BIAS - 0.01


func _pct(a: Array, q: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(float(b.size()) * q), 0, b.size() - 1)])


func _update_scale() -> void:
	if not stretch_on and not cal_locked:
		scale_lo = Vector2.ONE
		scale_hi = Vector2.ONE
		scale = Vector2.ONE
		return
	if cal_locked or _u_buf.size() < 150:
		return
	var u5 := _pct(_u_buf, 0.05)
	var u50 := _pct(_u_buf, 0.5)
	var u95 := _pct(_u_buf, 0.95)
	var v5 := _pct(_v_buf, 0.05)
	var v50 := _pct(_v_buf, 0.5)
	var v95 := _pct(_v_buf, 0.95)
	obs_span = Vector2(u95 - u5, v95 - v5)
	var tl := Vector2.ONE
	var th := Vector2.ONE
	if exp_span.x > 0.0:
		tl.x = clampf(exp_span.x * 0.5 / maxf(u50 - u5, 0.02), SCALE_MIN, SCALE_MAX)
		th.x = clampf(exp_span.x * 0.5 / maxf(u95 - u50, 0.02), SCALE_MIN, SCALE_MAX)
	if exp_span.y > 0.0:
		tl.y = clampf(exp_span.y * 0.5 / maxf(v50 - v5, 0.02), SCALE_MIN, SCALE_MAX)
		th.y = clampf(exp_span.y * 0.5 / maxf(v95 - v50, 0.02), SCALE_MIN, SCALE_MAX)
	scale_lo = Vector2(lerpf(scale_lo.x, tl.x, 0.25), lerpf(scale_lo.y, tl.y, 0.25))
	scale_hi = Vector2(lerpf(scale_hi.x, th.x, 0.25), lerpf(scale_hi.y, th.y, 0.25))
	scale = (scale_lo + scale_hi) * 0.5


func _fit_vertical() -> void:
	var n := _hist.size()
	if n < 3:
		var cur: float = float(_hist[n - 1][0])
		bias.y = clampf(bias.y + RATE * (0.25 if cal_locked else 1.0) * (cur - bias.y), -MAX_BIAS, MAX_BIAS)
		return
	var mean_y := 0.0
	var mean_p := 0.0
	var mean_a := 0.0
	for h in _hist:
		mean_y += float(h[0])
		mean_p += float(h[1])
		mean_a += float(h[2])
	mean_y /= float(n)
	mean_p /= float(n)
	mean_a /= float(n)
	_pitch_ref = mean_p
	_ap_ref = mean_a
	var spp := 0.0
	var saa := 0.0
	var spa := 0.0
	var spy := 0.0
	var say := 0.0
	for h in _hist:
		var dp := float(h[1]) - mean_p
		var da := float(h[2]) - mean_a
		var dy := float(h[0]) - mean_y
		spp += dp * dp
		saa += da * da
		spa += dp * da
		spy += dp * dy
		say += da * dy
	var kp := 0.0
	var ka := 0.0
	var lam := 1.0e-3 * float(n)
	var p_spread := sqrt(spp / float(n))
	var a_spread := sqrt(saa / float(n))
	if n >= 8 and (p_spread > 0.02 or a_spread > 0.01):
		var det := (spp + lam) * (saa + lam) - spa * spa
		if absf(det) > 1.0e-12:
			kp = ((spy) * (saa + lam) - say * spa) / det
			ka = ((spp + lam) * say - spa * spy) / det
		if p_spread <= 0.02:
			kp = 0.0
		if a_spread <= 0.01:
			ka = 0.0
	k_pitch = clampf(lerpf(k_pitch, kp, 0.3), -1.5, 1.5)
	k_aper = clampf(lerpf(k_aper, ka, 0.3), -3.0, 3.0)
	bias.y = clampf(lerpf(bias.y, mean_y, 0.35 * (0.25 if cal_locked else 1.0)), -MAX_BIAS, MAX_BIAS)


## The corrected gaze point, always inside the screen.
func apply(u: float, v: float, pitch: float, aperture: float) -> Vector2:
	var y := v + bias.y + k_pitch * (pitch - _pitch_ref) + k_aper * (aperture - _ap_ref)
	var x := u + bias.x
	# rescale about the target: the median is already there, so this only stretches or shrinks the spread around it
	x = target.x + (x - target.x) * (scale_lo.x if x < target.x else scale_hi.x)
	y = target.y + (y - target.y) * (scale_lo.y if y < target.y else scale_hi.y)
	return Vector2(clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0))


## A known fact: right now the player is looking at `screen_pos` (a blink on a target, the CENTER button).
## `raw` is the uncorrected gaze at that moment. weight 1 = trust fully.
func anchor(raw: Vector2, pitch: float, aperture: float, screen_pos: Vector2, weight: float = 0.5) -> void:
	var cur := apply(raw.x, raw.y, pitch, aperture)
	bias.x = clampf(bias.x + weight * (screen_pos.x - cur.x), -MAX_BIAS, MAX_BIAS)
	bias.y = clampf(bias.y + weight * (screen_pos.y - cur.y), -MAX_BIAS, MAX_BIAS)
	anchors += 1
	_win.clear()


## Take a measured map (screen = a + s * reading, per axis) from a sweep calibration.
func set_linear(ax: float, sx: float, ay: float, sy: float) -> void:
	scale_lo = Vector2(sx, sy)
	scale_hi = Vector2(sx, sy)
	scale = Vector2(sx, sy)
	bias = Vector2(target.x + (ax - target.x) / sx, target.y + (ay - target.y) / sy)
	cal_locked = true
	saturated = false
	_win.clear()


func reset() -> void:
	cal_locked = false
	bias = Vector2.ZERO
	scale = Vector2.ONE
	scale_lo = Vector2.ONE
	scale_hi = Vector2.ONE
	obs_span = Vector2.ZERO
	saturated = false
	_u_buf.clear()
	_v_buf.clear()
	k_pitch = 0.0
	k_aper = 0.0
	windows_used = 0
	_win.clear()
	_hist.clear()
