class_name AimStats
extends RefCounted
## Accuracy numbers for the Peek level, kept separately for the two ways of aiming (HEAD: the view turns with your head and the crosshair is the middle of the screen;
## EYES: the shot goes where your gaze is). Everything is a percentage of the screen width so a phone and a desktop can be compared.
##
##   shots / hits       a shot counts as a hit if the baddy nearest the aim point is hurt or dies within 0.8 s
##   aim error (fire)   at the moment of a shot: distance from where you were aiming to the nearest exposed baddy
##   fixation error     (eyes only) while you are locked onto a baddy: distance from the gaze reading to the baddy, sampled every frame. A person looking at a target looks
##                      at it, so this is the tracker's own error: its median is the accuracy, its 90th percentile is how far off it gets
##   unaimed            shots with no baddy anywhere near the aim point
## Kept on this device only (user://peek_aim.cfg, and localStorage on the web). Nothing is sent anywhere.

const MODES := ["head", "eyes"]
const MAX_SAMPLES := 4000

static var data: Dictionary = {
	"head": {"shots": 0, "hits": 0, "unaimed": 0, "fire_err": [], "fix_err": []},
	"eyes": {"shots": 0, "hits": 0, "unaimed": 0, "fire_err": [], "fix_err": []},
}


static func reset() -> void:
	for m in MODES:
		data[m] = {"shots": 0, "hits": 0, "unaimed": 0, "fire_err": [], "fix_err": []}


static func _push(arr: Array, v: float) -> void:
	arr.append(v)
	if arr.size() > MAX_SAMPLES:
		arr.remove_at(0)


static func shot(mode: String, err_pct: float) -> void:
	var d: Dictionary = data[mode]
	d["shots"] = int(d["shots"]) + 1
	if err_pct < 0.0:
		d["unaimed"] = int(d["unaimed"]) + 1
	else:
		_push(d["fire_err"], err_pct)


static func hit(mode: String) -> void:
	var d: Dictionary = data[mode]
	d["hits"] = int(d["hits"]) + 1


static func fixation(mode: String, err_pct: float) -> void:
	_push((data[mode] as Dictionary)["fix_err"], err_pct)


static func pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	return float(s[clampi(int(round(q * float(s.size() - 1))), 0, s.size() - 1)])


static func summary(mode: String) -> Dictionary:
	var d: Dictionary = data[mode]
	var shots := int(d["shots"])
	return {
		"mode": mode, "shots": shots, "hits": int(d["hits"]), "hit_rate": float(d["hits"]) / float(maxi(shots, 1)), "unaimed": int(d["unaimed"]),
		"fire_err_median": pct(d["fire_err"], 0.5), "fire_err_p90": pct(d["fire_err"], 0.9),
		"fix_err_median": pct(d["fix_err"], 0.5), "fix_err_p90": pct(d["fix_err"], 0.9), "fix_samples": (d["fix_err"] as Array).size(),
	}


static func _f(v: float) -> String:
	return "--" if v < 0.0 else "%.1f%%" % v


## One line for the screen.
static func line(mode: String) -> String:
	var s := summary(mode)
	var t := "%s: %d shots, %d hit" % [mode.to_upper(), s["shots"], s["hits"]]
	if int(s["shots"]) > 0:
		t += " (%d%%)" % int(round(float(s["hit_rate"]) * 100.0))
	t += "   aim error %s (90%%: %s)" % [_f(s["fire_err_median"]), _f(s["fire_err_p90"])]
	if mode == "eyes":
		t += "   gaze error %s (90%%: %s)" % [_f(s["fix_err_median"]), _f(s["fix_err_p90"])]
	return t


static func report() -> String:
	return JSON.stringify({"when": Time.get_datetime_string_from_system(), "touch": Game.touch_mode, "head": summary("head"), "eyes": summary("eyes")}, "  ")


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("peek", "report", report())
	cf.save("user://peek_aim.cfg")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('gazelab_peek_aim'," + JSON.stringify(report()) + ")}catch(e){}")
