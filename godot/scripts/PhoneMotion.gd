class_name PhoneMotion
extends RefCounted
## The phone's motion sensors, used to help the eye tracker.
## A hand-held phone tilts and shakes; the camera sees the face move and the iris-in-eye reading picks up part of that as a fake glance.
## 1. correct(): learns, while you play, how much of the iris reading follows the phone's tilt (a two-variable regression on the short-term tilt, per axis) and subtracts it.
##    A steady phone has ~0 short-term tilt, so real glances pass through untouched.
## 2. shake: how hard the phone is moving right now (0..1). A grab or bump freezes the gaze for a moment instead of throwing the board at a gate.
## 3. tilt_x / tilt_y: the phone's tilt in screen terms (degrees), for an optional world-lock camera.
## 4. buzz(): haptics where the browser allows it (Android).
## Everything is a no-op where there is no sensor (desktop), so callers never need to check.

var active: bool = false           # sensor data is arriving
var shake: float = 0.0             # 0 steady .. 1 violent
var tilt_x: float = 0.0            # degrees, screen space: + the right edge goes toward you
var tilt_y: float = 0.0            # degrees, screen space: + the top edge goes away from you
var rate: float = 0.0              # deg/s rotation magnitude, smoothed
var gain: Vector4 = Vector4.ZERO   # learned: eih.x per tilt (x, y), eih.y per tilt (x, y)
var learned: float = 0.0           # 0..1 how much it trusts the fit
var removed_pct: float = 0.0       # share of the iris reading's short-term variance the fit explains (diagnostic)
var buzz_ok: bool = false
var haptics_on: bool = true         # the player can turn the buzzing off
var lap: float = 0.0               # 0 held up at the face .. 1 lying flat (in the lap): the camera looks up at you, the lids sit lower
var _hist: Array = []              # [time, tilt_x, tilt_y] for the last few seconds
var _clock: float = 0.0

var _t_poll: float = 0.0
var _inited: bool = false
var _m_t := Vector2.ZERO           # slow mean of the tilt
var _m_e := Vector2.ZERO           # slow mean of the iris reading
var _have_mean: bool = false
var _cxx: float = 0.0              # covariance of short-term tilt: (xx, xy, yy)
var _cxy: float = 0.0
var _cyy: float = 0.0
var _ce := Vector4.ZERO            # cov(tilt_x, e.x), cov(tilt_y, e.x), cov(tilt_x, e.y), cov(tilt_y, e.y)
var _vex: float = 0.0
var _vey: float = 0.0
var _n: int = 0
var _shake_hold: float = 0.0
const GAIN_CAP := 0.02             # iris-reading units per degree, at most
const WARM_UP := 90                # samples before the fit is used
const FORGET := 0.004              # per sample (the poll runs at ~30 Hz: ~8 s memory)


func start() -> void:
	if _inited or not OS.has_feature("web"):
		return
	_inited = true
	JavaScriptBridge.eval("""
(function(){
  if (window.__pm) return;
  var pm = window.__pm = {b:0,g:0,rx:0,ry:0,rz:0,ang:0,ok:0,t:0};
  function ang(){ try { return (screen.orientation && screen.orientation.angle) || window.orientation || 0; } catch(e){ return 0; } }
  window.addEventListener('deviceorientation', function(e){ if (e.beta==null) return; pm.b=e.beta; pm.g=e.gamma; pm.ang=ang(); pm.ok=1; pm.t=Date.now(); }, true);
  window.addEventListener('devicemotion', function(e){ var r=e.rotationRate; if (r){ pm.rx=r.beta||0; pm.ry=r.gamma||0; pm.rz=r.alpha||0; } }, true);
  function ask(){
    try {
      if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') DeviceOrientationEvent.requestPermission().catch(function(){});
      if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') DeviceMotionEvent.requestPermission().catch(function(){});
    } catch(e){}
  }
  window.addEventListener('touchend', ask, {once:true});
  window.addEventListener('click', ask, {once:true});
})();
""")
	buzz_ok = bool(JavaScriptBridge.eval("(typeof navigator.vibrate === 'function') ? 1 : 0"))


## Call every frame; it samples at ~30 Hz.
func poll(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	if not _inited:
		start()
	_t_poll += delta
	if _t_poll < 0.033:
		return
	var dt := _t_poll
	_t_poll = 0.0
	var raw = JavaScriptBridge.eval("window.__pm ? JSON.stringify(window.__pm) : ''")
	if str(raw) == "":
		return
	var d: Variant = JSON.parse_string(str(raw))
	if not (d is Dictionary) or int(d.get("ok", 0)) != 1 or Time.get_unix_time_from_system() * 1000.0 - float(d.get("t", 0)) > 2000.0:
		active = false
		return
	feed(float(d["b"]), float(d["g"]), int(d.get("ang", 0)), Vector3(float(d.get("rx", 0)), float(d.get("ry", 0)), float(d.get("rz", 0))), dt)


## One sensor sample: beta / gamma in degrees, the screen orientation angle, and the gyro rates in deg/s.
func feed(beta: float, gamma: float, ang: int, gyro: Vector3, dt: float) -> void:
	active = true
	var a := posmod(ang, 360)
	match a:
		90:
			tilt_x = beta
			tilt_y = -gamma
		270:
			tilt_x = -beta
			tilt_y = gamma
		180:
			tilt_x = -gamma
			tilt_y = -beta
		_:
			tilt_x = gamma
			tilt_y = beta
	_clock += dt
	_hist.append([_clock, tilt_x, tilt_y])
	while _hist.size() > 1 and _clock - float(_hist[0][0]) > 3.0:
		_hist.remove_at(0)
	# how upright is the screen? an upright phone reads ~90 deg of pitch along its long axis (portrait beta / landscape gamma), flat reads ~0
	var up := absf(tilt_y) if (a == 0 or a == 180) else absf(tilt_x)
	lap = clampf((70.0 - up) / 45.0, 0.0, 1.0)
	rate += (gyro.length() - rate) * minf(dt * 8.0, 1.0)
	var s := clampf((rate - 25.0) / 90.0, 0.0, 1.0)
	if s > shake:
		shake = s
		_shake_hold = 0.25
	else:
		_shake_hold = maxf(_shake_hold - dt, 0.0)
		if _shake_hold <= 0.0:
			shake = maxf(shake - dt * 2.5, s)


## True while the way the phone is held is changing (shifting in a seat, lifting it, settling into the lap): the eyelid baseline lags behind that, so squint / wide-eye
## detection waits instead of firing on it.
func settling() -> bool:
	if not active or _hist.size() < 2:
		return false
	var o: Array = _hist[0]
	return absf(tilt_x - float(o[1])) + absf(tilt_y - float(o[2])) > 14.0


## True while the phone is being moved hard enough that the gaze reading should be held, not trusted.
func holding() -> bool:
	return active and shake > 0.7


## The iris-in-eye reading with the part that follows the phone's tilt taken out.
func correct(e: Vector2) -> Vector2:
	if not active:
		return e
	var t := Vector2(tilt_x, tilt_y)
	if not _have_mean:
		_m_t = t
		_m_e = e
		_have_mean = true
		return e
	# the slow means follow with a ~3 s time constant: the short-term part is what the hand does
	_m_t += (t - _m_t) * 0.01
	_m_e += (e - _m_e) * 0.01
	var dt_ := t - _m_t
	var de := e - _m_e
	var f := FORGET
	_cxx += (dt_.x * dt_.x - _cxx) * f
	_cxy += (dt_.x * dt_.y - _cxy) * f
	_cyy += (dt_.y * dt_.y - _cyy) * f
	_ce.x += (dt_.x * de.x - _ce.x) * f
	_ce.y += (dt_.y * de.x - _ce.y) * f
	_ce.z += (dt_.x * de.y - _ce.z) * f
	_ce.w += (dt_.y * de.y - _ce.w) * f
	_vex += (de.x * de.x - _vex) * f
	_vey += (de.y * de.y - _vey) * f
	_n += 1
	if _n < WARM_UP:
		return e
	var ridge := 0.05 + 0.05 * (_cxx + _cyy)          # in deg^2: keeps a still phone from inventing a fit
	var a := _cxx + ridge
	var b := _cxy
	var c := _cyy + ridge
	var det := a * c - b * b
	if det < 1.0e-6:
		return e
	var gx_x := clampf((c * _ce.x - b * _ce.y) / det, -GAIN_CAP, GAIN_CAP)
	var gx_y := clampf((-b * _ce.x + a * _ce.y) / det, -GAIN_CAP, GAIN_CAP)
	var gy_x := clampf((c * _ce.z - b * _ce.w) / det, -GAIN_CAP, GAIN_CAP)
	var gy_y := clampf((-b * _ce.z + a * _ce.w) / det, -GAIN_CAP, GAIN_CAP)
	gain = Vector4(gx_x, gx_y, gy_x, gy_y)
	var expl_x := (gx_x * _ce.x + gx_y * _ce.y) / maxf(_vex, 1.0e-12)
	var expl_y := (gy_x * _ce.z + gy_y * _ce.w) / maxf(_vey, 1.0e-12)
	removed_pct = clampf((expl_x + expl_y) * 50.0, 0.0, 100.0)
	learned = clampf(float(_n - WARM_UP) / 120.0, 0.0, 1.0) * clampf(removed_pct / 8.0, 0.0, 1.0)
	return e - Vector2(gx_x * dt_.x + gx_y * dt_.y, gy_x * dt_.x + gy_y * dt_.y) * learned


## A buzz in the hand. pattern: milliseconds on / off / on ...
func buzz(pattern: Array) -> void:
	if not buzz_ok or not haptics_on or not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("try{navigator.vibrate(%s)}catch(e){}" % JSON.stringify(pattern))
