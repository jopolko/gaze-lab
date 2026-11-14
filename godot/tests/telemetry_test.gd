extends Node
## The diagnostics name the right problem for the right numbers.
var _fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1


func _ready() -> void:
	var t := Telemetry.new()
	var base := {"fps": 60.0, "cpu": 6.0, "ft95": 17.0, "face": 0.28, "conf": 1.0, "head": [0.0, 0.0, 0.0], "open": 0.4, "trk": 20.0, "lat": 90, "model": 40, "shake": 0.0, "lap": 0.0, "t": 1.0}
	var f: Array = t._classify(base.duplicate(true), 60.0, 17.0, 20.0, 6.0, true, true)
	_check(f.is_empty(), "a healthy second names nothing wrong")
	var d := base.duplicate(true)
	d["light"] = {"face": 40, "contrast": 30, "bg": 150, "sat": 0, "dk": 20, "backlit": 110}
	f = t._classify(d, 60.0, 17.0, 20.0, 6.0, true, true)
	_check(f.has("dark_face"), "a dark face is called dark")
	d["light"] = {"face": 90, "contrast": 30, "bg": 190, "sat": 0, "dk": 0, "backlit": 100}
	f = t._classify(d, 60.0, 17.0, 20.0, 6.0, true, true)
	_check(f.has("backlit_face") and not f.has("dark_face"), "a face much darker than the room is called backlit")
	d = base.duplicate(true)
	d["head"] = [0.0, 0.8, 0.0]
	d["open"] = 0.1
	d["face"] = 0.1
	f = t._classify(d, 60.0, 17.0, 20.0, 6.0, true, true)
	_check(f.has("bad_angle") and f.has("squint") and f.has("too_far"), "a turned head, narrow eyes and a small face are called bad angle, squint and too far")
	f = t._classify(base.duplicate(true), 20.0, 40.0, 60.0, 8.0, true, true)
	_check(f.has("low_fps") and f.has("gpu_bound") and f.has("freeze") == false, "a slow frame with little script time is called GPU bound")
	f = t._classify(base.duplicate(true), 20.0, 40.0, 200.0, 36.0, true, true)
	_check(f.has("cpu_bound") and f.has("freeze"), "a slow frame that is all script time is CPU bound, and a 200 ms frame is a freeze")
	d = base.duplicate(true)
	d["lap"] = 0.9
	d["shake"] = 0.8
	f = t._classify(d, 60.0, 17.0, 20.0, 6.0, true, true)
	_check(f.has("phone_flat") and f.has("phone_shaking"), "a phone lying flat and shaking is named")
	f = t._classify(base.duplicate(true), 60.0, 17.0, 20.0, 6.0, true, false)
	_check(f.has("cam_stalled"), "no fresh camera frames is a stalled camera")
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
