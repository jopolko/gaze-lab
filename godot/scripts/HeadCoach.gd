class_name HeadCoach
extends RefCounted
## Works out, from the camera image alone (no dots), where your head should sit so the eyes stay readable, and how far
## off that you are right now.
##
## Why it matters: tilting the head back (for example to look through the lower part of progressive lenses) narrows the
## eye opening and shrinks the visible iris, so gaze is least precise exactly when you look down. The ideal pose is
## learned while you play: it is the head pose you hold when your eyes are open widest. Pure logic, unit tested.

const KEEP := 600                       # samples kept (about 40 s at 15 frames/s)
const MIN_REF := 45                     # samples before a reference pose exists
const TOL_PITCH := 8.0                  # degrees
const TOL_YAW := 9.0
const TOL_ROLL := 7.0
const TOL_OPEN := 0.80                  # eye opening below this share of your usual = squinting
const NAG_AFTER := 1.5                  # seconds out of range before a hint appears
const NAG_GAP := 14.0                   # seconds between hints

var pose: Array = []                    # recent [pitch, yaw, roll, open, t]
var ref: Vector3 = Vector3.ZERO         # learned (or seeded) good pose: pitch, yaw, roll in degrees
var ref_ok: bool = false
var seeded: bool = false
var open_base: float = 0.0              # your usual (wide-open) eye opening
var quality: float = 1.0                # 1 = head well placed, 0 = far off
var cur: Vector3 = Vector3.ZERO
var open_ratio: float = 1.0
var _bad_since: float = -1.0
var _last_msg_t: float = -100.0
var _was_bad: bool = false
var good_event: bool = false            # set for one read after returning to a good position


func reset() -> void:
	pose.clear()
	ref_ok = seeded
	quality = 1.0
	_bad_since = -1.0
	_last_msg_t = -100.0
	_was_bad = false


## Start from a pose measured earlier (EyeLab saves one); it is refined as you play.
func seed(pitch: float, yaw: float, roll: float) -> void:
	ref = Vector3(pitch, yaw, roll)
	ref_ok = true
	seeded = true


func add(pitch: float, yaw: float, roll: float, open: float, t: float) -> void:
	if not is_finite(open) or open <= 0.0:
		return
	pose.append([pitch, yaw, roll, open, t])
	if pose.size() > KEEP:
		pose.remove_at(0)
	if pose.size() < 8:
		return
	# usual opening: the 85th percentile of everything seen
	var os := PackedFloat32Array()
	for p in pose:
		os.append(float(p[3]))
	os.sort()
	open_base = os[int(float(os.size() - 1) * 0.85)]
	var open_med := _med_recent(3, t, 1.2)
	open_ratio = open_med / maxf(open_base, 0.001)
	cur = Vector3(_med_recent(0, t, 1.2), _med_recent(1, t, 1.2), _med_recent(2, t, 1.2))
	# the good pose = median pose while the eyes are well open (above the median opening)
	if pose.size() >= MIN_REF:
		var thr := os[int(float(os.size() - 1) * 0.6)]
		var a: Array = []
		var b: Array = []
		var c: Array = []
		for p in pose:
			if float(p[3]) >= thr:
				a.append(float(p[0]))
				b.append(float(p[1]))
				c.append(float(p[2]))
		if a.size() >= 12:
			var learned := Vector3(_median(a), _median(b), _median(c))
			ref = learned if not seeded else ref.lerp(learned, 0.02)
			ref_ok = true
	var d := deviation()
	quality = clampf(1.0 - maxf(maxf(absf(d.x) / (2.0 * TOL_PITCH), absf(d.y) / (2.0 * TOL_YAW)), maxf(absf(d.z) / (2.0 * TOL_ROLL), maxf(0.0, (0.9 - open_ratio) / 0.4))), 0.0, 1.0)
	var bad := not issues().is_empty()
	if bad:
		if _bad_since < 0.0:
			_bad_since = t
	else:
		_bad_since = -1.0
		if _was_bad:
			good_event = true
	_was_bad = bad


func deviation() -> Vector3:
	return cur - ref if ref_ok else Vector3.ZERO


## Problems right now, most important first: [{"id", "text"}].
func issues() -> Array:
	var out: Array = []
	if not ref_ok:
		return out
	var d := deviation()
	if d.x < -TOL_PITCH:
		out.append({"id": "tilt_back", "text": "Chin down a little: tilted back narrows your eyes"})
	elif d.x > TOL_PITCH:
		out.append({"id": "chin_low", "text": "Lift your chin a little: face the screen"})
	if d.y > TOL_YAW:
		out.append({"id": "turn_right", "text": "Turn back a little toward the middle"})
	elif d.y < -TOL_YAW:
		out.append({"id": "turn_left", "text": "Turn back a little toward the middle"})
	if absf(d.z) > TOL_ROLL:
		out.append({"id": "lean", "text": "Level your head gently"})
	if open_ratio < TOL_OPEN:
		out.append({"id": "squint", "text": "Relax your forehead: open your eyes a little more"})
	return out


## A hint to show now ("" most of the time): only after you have been off for a while, and not more than once per NAG_GAP.
func message(t: float) -> String:
	var list := issues()
	if list.is_empty() or _bad_since < 0.0:
		return ""
	if t - _bad_since < NAG_AFTER or t - _last_msg_t < NAG_GAP:
		return ""
	_last_msg_t = t
	return String(list[0]["text"])


func take_good_event() -> bool:
	var g := good_event
	good_event = false
	return g


func _med_recent(idx: int, t: float, window: float) -> float:
	var v: Array = []
	for i in range(pose.size() - 1, -1, -1):
		var p: Array = pose[i]
		if t - float(p[4]) > window:
			break
		v.append(float(p[idx]))
	return _median(v) if not v.is_empty() else 0.0


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])
