class_name SweepTest
extends Control
## SWEEP TEST (?level=gaze&sweep): a dot moves across the screen on a known path while every raw tracker reading is logged at full rate.
## With the truth known, each stage of the gaze (iris inside the eye, the geometry reading, the final cursor, the head angles) can be scored for how well it
## follows the eyes and how noisy it is. It measures only: nothing here calibrates or changes the tracker.
##
## Phases: side-to-side glide, side-to-side jumps, up-and-down glide, then "turn your head, keep looking at the middle" (how much a head turn leaks into the gaze).

const PHASES := [
	{"id": "wait", "dur": 0.0, "text": "Waiting for the camera..."},
	{"id": "ready", "dur": 3.0, "text": "Follow the dot with your EYES. Keep your head still."},
	{"id": "hx", "dur": 16.0, "text": ""},
	{"id": "jump", "dur": 10.0, "text": ""},
	{"id": "vy", "dur": 10.0, "text": ""},
	{"id": "head", "dur": 10.0, "text": "Keep looking at the dot. Slowly turn your HEAD left and right."},
	{"id": "done", "dur": 0.0, "text": "Done. Thank you."},
]
const JUMPS := [0.5, 0.1, 0.9, 0.5, 0.25, 0.75, 0.1, 0.9, 0.5, 0.5]

var ph: int = 0
var t: float = 0.0
var tgt: Vector2 = Vector2(0.5, 0.5)
var rows_sent: int = 0
var _seen: int = -1
var _batch: Array = []
var _live_t: float = 0.0
var _wait_t: float = 0.0
var _retry_t: float = 0.0
var _status: String = ""
var _mouse_ok: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_mouse_ok = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('mouse')"))


func phase_id() -> String:
	return String(PHASES[ph]["id"])


static func target_at(id: String, tt: float) -> Vector2:
	match id:
		"hx":
			return Vector2(0.5 + 0.42 * sin(TAU * tt / 4.0), 0.5)
		"jump":
			return Vector2(float(JUMPS[clampi(int(tt), 0, JUMPS.size() - 1)]), 0.5)
		"vy":
			return Vector2(0.5, 0.5 + 0.36 * sin(TAU * tt / 5.0))
	return Vector2(0.5, 0.5)


static func _num(v: Variant) -> Variant:
	if v is float or v is int:
		return snappedf(float(v), 0.0001)
	if v is bool:
		return 1 if v else 0
	if v is Array and (v as Array).size() <= 8:
		var out: Array = []
		for e: Variant in v:
			if not (e is float or e is int):
				return null
			out.append(snappedf(float(e), 0.0001))
		return out
	return null


## One log row from a tracker packet: every number the tracker sent, plus where the dot was and what each later stage made of it.
static func make_row(id: String, tt: float, target: Vector2, d: Dictionary, P: Object) -> Dictionary:
	var p: Dictionary = {}
	for k: Variant in d:
		var n: Variant = _num(d[k])
		if n != null:
			p[String(k)] = n
	return {"ph": id, "tt": snappedf(tt, 0.001), "tx": snappedf(target.x, 0.001), "ty": snappedf(target.y, 0.001), "p": p,
		"eih": [snappedf(P.eih.x, 0.0001), snappedf(P.eih.y, 0.0001)], "mix": [snappedf(P.mix_x, 0.0001), snappedf(P.mix.value, 0.001)], "geo": [snappedf(P._geo_raw.x, 0.001), snappedf(P._geo_raw.y, 0.001)],
		"cur": [snappedf(P.gaze.x, 0.001), snappedf(P.gaze.y, 0.001)], "head": [snappedf(P.head_rpy.x, 0.001), snappedf(P.head_rpy.y, 0.001), snappedf(P.head_rpy.z, 0.001)]}


func _flush() -> void:
	if _batch.is_empty():
		return
	rows_sent += _batch.size()
	if Telemetry.inst != null:
		Telemetry.inst._post({"kind": "sweep", "rows": _batch})
	_batch = []


func _process(delta: float) -> void:
	var P := GazeProvider
	size = get_viewport().get_visible_rect().size
	var id := phase_id()
	if id == "wait":
		var cam_live: bool = P.backend == P.Backend.CAMERA and P.confidence > 0.3 and P.pkt_count > 0
		_live_t = _live_t + delta if (cam_live or (_mouse_ok and P.backend == P.Backend.MOUSE)) else 0.0          # ?mouse runs it without a camera (nothing is recorded): a way to see the test
		_wait_t += delta
		if not _mouse_ok and P.backend != P.Backend.CAMERA and _wait_t > 2.0 and _retry_t <= 0.0:
			_retry_t = 6.0                              # the camera is not running (never started, or it failed and the game fell back to touch): start it, and say so in the log
			P._cam_failed = false
			P.start_camera()
			if Telemetry.inst != null:
				Telemetry.inst._post({"kind": "sweep_wait", "why": "camera not running, starting it", "status": P.camera_status, "touch": Game.touch_mode})
		_retry_t -= delta
		_status = ("camera: " + P.camera_status) if P.camera_status != "" else "starting the camera..."
		if P.backend == P.Backend.CAMERA and P.pkt_count > 0 and P.confidence <= 0.3:
			_status = "camera on, looking for your face..."
		if _live_t > 1.0:
			ph += 1
			t = 0.0
	elif id != "done":
		t += delta
		tgt = SweepTest.target_at(id, t)
		if P.pkt_count != _seen and id != "ready":
			_seen = P.pkt_count
			_batch.append(SweepTest.make_row(id, t, tgt, P.last_pkt, P))
			if _batch.size() >= 10:
				_flush()
		if t >= float(PHASES[ph]["dur"]):
			ph += 1
			t = 0.0
			if phase_id() == "done":
				_flush()
				if Telemetry.inst != null:
					Telemetry.inst._post({"kind": "sweep_done", "n": rows_sent})
	queue_redraw()


func _draw() -> void:
	var sz := size
	if sz.y < 40.0:
		return
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.04, 0.08, 1.0))
	var k := sz.y / 720.0
	var font := ThemeDB.fallback_font
	var id := phase_id()
	var text := String(PHASES[ph]["text"])
	if text != "":
		var fs := int(30.0 * k)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((sz.x - w) * 0.5, sz.y * 0.22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
	if id == "wait" or id == "done":
		if id == "wait" and _status != "":
			var fs3 := int(20.0 * k)
			draw_string(font, Vector2((sz.x - font.get_string_size(_status, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x) * 0.5, sz.y * 0.32), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Color(0.7, 0.9, 1.0, 0.9))
		if id == "done":
			var s2 := "%d readings recorded" % rows_sent
			var fs2 := int(22.0 * k)
			draw_string(font, Vector2((sz.x - font.get_string_size(s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x) * 0.5, sz.y * 0.32), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.7, 0.9, 1.0, 0.9))
		return
	var p := Vector2(tgt.x * sz.x, tgt.y * sz.y)
	Draw2D.circle(self, p, 20.0 * k, Color(1.0, 0.62, 0.15, 0.35))
	Draw2D.circle(self, p, 11.0 * k, Color(1.0, 0.62, 0.15, 1.0))
	Draw2D.circle(self, p, 3.5 * k, Color(0.05, 0.05, 0.1, 1.0))
	# progress along the bottom
	var total := 0.0
	var gone := 0.0
	for i in PHASES.size():
		var dd := float(PHASES[i]["dur"])
		total += dd
		if i < ph:
			gone += dd
	gone += t
	draw_rect(Rect2(0, sz.y - 6.0 * k, sz.x * clampf(gone / maxf(total, 1.0), 0.0, 1.0), 6.0 * k), Color(1.0, 0.62, 0.15, 0.8))
