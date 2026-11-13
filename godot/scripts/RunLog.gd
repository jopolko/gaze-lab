class_name RunLog
extends RefCounted
## A black box for every run: how the tracking, the steering, the phone and the frame rate behaved, on whatever device and in whatever conditions (desk, bus, streetcar).
## It is stored ON THE DEVICE ONLY (browser localStorage, or a file outside the web build) and nothing is ever sent anywhere: you read it back from the menu
## (copy it, or download it) and send it yourself if you want help. Location is never recorded: with the optional GPS toggle on, only the browser's reported
## SPEED and its accuracy are read, to notice a moving vehicle; the coordinates are never touched.

const KEY := "gazelab_runs"
const MAX_RUNS := 40
const FILE := "user://runs.json"

static var device_cache: Dictionary = {}
static var gps_on: bool = false
static var gps_speed: float = -1.0            # m/s, -1 = unknown
static var gps_acc: float = -1.0

var run_id: int = 0
var _active: bool = false
var _t: float = 0.0
var _n: int = 0
var _sum_steer: float = 0.0
var _l: int = 0
var _r: int = 0
var _c: int = 0
var _sum_eih: float = 0.0
var _eih_min: float = 1.0e9
var _eih_max: float = -1.0e9
var _ref_min: float = 1.0e9
var _ref_max: float = -1.0e9
var _tilt_n: int = 0
var _tx_mean: float = 0.0
var _tx_m2: float = 0.0
var _ty_mean: float = 0.0
var _shake_n: int = 0
var _lap_sum: float = 0.0
var _fps_sum: float = 0.0
var _fps_n: int = 0
var _fps_min: float = 1.0e9
var _lat_sum: float = 0.0
var _lat_n: int = 0
var _gps_n: int = 0
var _gps_sum: float = 0.0
var _gps_max: float = 0.0
var _veh_n: int = 0
var _rev: int = 0
var _last_vx: float = 0.0
var _steer_sq: float = 0.0
var _z0: float = 0.0
var _save_t: float = 10.0
var _fps_t: float = 0.0
var _gps_t: float = 0.0


# ------------------------------------------------------------------ device
static func device() -> Dictionary:
	if not device_cache.is_empty():
		return device_cache
	var d := {"platform": OS.get_name(), "model": OS.get_model_name(), "touch": Game.touch_mode, "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))}
	if OS.has_feature("web"):
		var js := str(JavaScriptBridge.eval("JSON.stringify({ua:navigator.userAgent,lang:navigator.language,screen:[screen.width,screen.height],inner:[innerWidth,innerHeight],dpr:devicePixelRatio,cores:navigator.hardwareConcurrency||0,mem:navigator.deviceMemory||0,net:(navigator.connection&&navigator.connection.effectiveType)||'',orient:(screen.orientation&&screen.orientation.type)||'',sensors:!!(window.DeviceMotionEvent)})"))
		var p: Variant = JSON.parse_string(js)
		if p is Dictionary:
			d.merge(p, true)
	device_cache = d
	return d


## Optional: read the browser's reported speed (never the position) so the game can tell it is on a moving vehicle.
static func start_gps() -> void:
	if gps_on or not OS.has_feature("web"):
		return
	gps_on = true
	JavaScriptBridge.eval("(function(){try{if(!navigator.geolocation)return;window.__gps={s:-1,a:-1,t:0};navigator.geolocation.watchPosition(function(p){window.__gps={s:(p.coords.speed==null?-1:p.coords.speed),a:p.coords.accuracy,t:Date.now()}},function(){},{enableHighAccuracy:false,maximumAge:4000,timeout:15000})}catch(e){}})()")


static func poll_gps() -> void:
	if not gps_on or not OS.has_feature("web"):
		return
	var js := str(JavaScriptBridge.eval("window.__gps?JSON.stringify(window.__gps):''"))
	if js == "":
		return
	var p: Variant = JSON.parse_string(js)
	if p is Dictionary and Time.get_unix_time_from_system() * 1000.0 - float(p.get("t", 0)) < 12000.0:
		gps_speed = float(p.get("s", -1.0))
		gps_acc = float(p.get("a", -1.0))
	else:
		gps_speed = -1.0


## True while the device is on a moving vehicle (the player says so, or the speed reading says so).
static func on_vehicle(forced: bool) -> bool:
	return forced or (gps_speed > 3.0)


# ------------------------------------------------------------------ recording
func tick(rig: RunRig, delta: float) -> void:
	if rig._finished or rig._run_t < 0.5:
		return
	if not _active:
		_active = true
		run_id = int(Time.get_unix_time_from_system() * 1000.0)
	_t += delta
	_n += 1
	var st := float(rig._steer_gaze)
	if _n == 1:
		_z0 = rig.spos.z
	var vx := rig.vel.x
	if absf(vx) > 1.0:
		if _last_vx != 0.0 and signf(vx) != signf(_last_vx):
			_rev += 1                                              # the board changed its sideways direction: counted, so rocking shows up in the numbers
		_last_vx = vx
	_steer_sq += rig.steer * rig.steer
	_sum_steer += st
	if st < -0.25:
		_l += 1
	elif st > 0.25:
		_r += 1
	else:
		_c += 1
	var ex := float(GazeProvider.eih.x)
	_sum_eih += ex
	_eih_min = minf(_eih_min, ex)
	_eih_max = maxf(_eih_max, ex)
	_ref_min = minf(_ref_min, rig._ex_ref)
	_ref_max = maxf(_ref_max, rig._ex_ref)
	var pm := GazeProvider.pm
	if pm.active:
		_tilt_n += 1
		var dx := pm.tilt_x - _tx_mean
		_tx_mean += dx / float(_tilt_n)
		_tx_m2 += dx * (pm.tilt_x - _tx_mean)
		_ty_mean += (pm.tilt_y - _ty_mean) / float(_tilt_n)
		_lap_sum += pm.lap
		if pm.shake > 0.5:
			_shake_n += 1
	if GazeProvider.trk_lat_ms >= 0.0:
		_lat_sum += GazeProvider.trk_lat_ms
		_lat_n += 1
	if RunLog.on_vehicle(rig.vehicle_forced):
		_veh_n += 1
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		var f := float(Engine.get_frames_per_second())
		if f > 1.0:
			_fps_sum += f
			_fps_n += 1
			_fps_min = minf(_fps_min, f)
	_gps_t -= delta
	if _gps_t <= 0.0:
		_gps_t = 1.0
		RunLog.poll_gps()
		if RunLog.gps_speed >= 0.0:
			_gps_n += 1
			_gps_sum += RunLog.gps_speed
			_gps_max = maxf(_gps_max, RunLog.gps_speed)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 10.0
		save_run(summary(rig, "running"))


func summary(rig: RunRig, why: String) -> Dictionary:
	var n := float(maxi(_n, 1))
	var tn := float(maxi(_tilt_n, 1))
	var th := ""
	var lvl: Node = rig.get_parent()
	if lvl != null and lvl.get_node_or_null("ThemeFX") != null:
		th = (lvl.get_node("ThemeFX") as ThemeFX).current()
	return {
		"id": run_id, "when": Time.get_datetime_string_from_system(false, true), "why": why, "seconds": snappedf(_t, 0.1),
		"device": RunLog.device(),
		"course": {"seed": rig._run_seed, "preset": RunRig.PRESET_ORDER[rig._preset_i], "theme": th, "length": rig.params.get("length", 0), "diff": rig.params.get("diff", 1.0), "zones": rig.params.get("zones", {}), "region": rig._region, "regions": rig.regions_seen},
		"result": {"metres": int(-rig.spos.z), "score": rig.score, "crashes": rig.crashes, "finished": rig._finished, "tricks": rig.tricks_landed, "faces": rig.face_done, "wrongGates": rig.wrong_gates, "gatesPassed": rig._passed_ok},
		"rocking": {"reversalsPer100m": snappedf(float(_rev) / maxf((_z0 - rig.spos.z) / 100.0, 1.0), 0.1), "steerRms": snappedf(sqrt(_steer_sq / n), 0.01)},
		"steering": {"meanSteer": snappedf(_sum_steer / n, 0.001), "left": snappedf(float(_l) / n, 0.01), "centre": snappedf(float(_c) / n, 0.01), "right": snappedf(float(_r) / n, 0.01),
			"eihMean": snappedf(_sum_eih / n, 0.0001), "eihMin": snappedf(_eih_min, 0.0001), "eihMax": snappedf(_eih_max, 0.0001), "refMin": snappedf(_ref_min, 0.0001), "refMax": snappedf(_ref_max, 0.0001), "glance": snappedf(rig._ex_full, 0.0001)},
		"agency": rig.agency_summary(),
		"saccades": {"events": rig.sacc.events, "spikesRejected": rig.sacc.spikes, "jitter": snappedf(rig.sacc.jitter, 0.001), "threshold": snappedf(rig.sacc.threshold(), 0.001)},
		"phone": {"sensors": _tilt_n > 0, "tiltXMean": snappedf(_tx_mean, 0.1), "tiltXSd": snappedf(sqrt(_tx_m2 / tn), 0.1), "tiltYMean": snappedf(_ty_mean, 0.1), "lapMean": snappedf(_lap_sum / tn, 0.01), "shakeShare": snappedf(float(_shake_n) / tn, 0.01), "removedPct": snappedf(GazeProvider.pm.removed_pct, 0.1)},
		"vehicle": {"forced": rig.vehicle_forced, "share": snappedf(float(_veh_n) / n, 0.01), "gpsOn": RunLog.gps_on, "speedMean": snappedf(_gps_sum / float(maxi(_gps_n, 1)), 0.1) if _gps_n > 0 else -1.0, "speedMax": snappedf(_gps_max, 0.1) if _gps_n > 0 else -1.0, "accuracyM": snappedf(RunLog.gps_acc, 1.0)},
		"quality": {"tier": _tier_now(rig), "tierChanges": _tier_changes(rig), "pinned": rig.perf_pin},
		"performance": {"vegRange": rig.veg_range, "fpsMean": snappedf(_fps_sum / float(maxi(_fps_n, 1)), 0.1), "fpsMin": snappedf(_fps_min if _fps_n > 0 else 0.0, 0.1)},
		"tracker": {"fps": snappedf(float(GazeProvider._pkt_times.size()) / 2.0, 0.1), "latencyMs": int(_lat_sum / float(maxi(_lat_n, 1))) if _lat_n > 0 else -1, "lostPct": int(100.0 * float(rig._tr_miss) / float(maxi(rig._tr_total, 1))), "video": GazeProvider.trk_video, "eyesOnly": rig.eyes_only},
		"crashLog": rig.crash_log.slice(maxi(rig.crash_log.size() - 6, 0)),
	}


func _tier_now(rig: RunRig) -> int:
	var lt := rig.get_parent().get_node_or_null("Lighting") if rig.get_parent() != null else null
	return (lt as DhLighting).tier if lt != null else -1


func _tier_changes(rig: RunRig) -> int:
	var lt := rig.get_parent().get_node_or_null("Lighting") if rig.get_parent() != null else null
	return (lt as DhLighting).tier_changes if lt != null else 0


## Called when a run ends (finish, restart, or a new course): writes the final entry.
func end_run(rig: RunRig, why: String) -> void:
	if _active and _n >= 120:
		var s := summary(rig, why)
		s["detail"] = rig._pause_report()                       # the full tracker report, once, at the end
		save_run(s)
	reset()


func reset() -> void:
	run_id = 0
	_active = false
	_t = 0.0
	_n = 0
	_sum_steer = 0.0
	_l = 0
	_r = 0
	_c = 0
	_sum_eih = 0.0
	_eih_min = 1.0e9
	_eih_max = -1.0e9
	_ref_min = 1.0e9
	_ref_max = -1.0e9
	_tilt_n = 0
	_tx_mean = 0.0
	_tx_m2 = 0.0
	_ty_mean = 0.0
	_shake_n = 0
	_lap_sum = 0.0
	_fps_sum = 0.0
	_fps_n = 0
	_fps_min = 1.0e9
	_lat_sum = 0.0
	_lat_n = 0
	_gps_n = 0
	_gps_sum = 0.0
	_gps_max = 0.0
	_veh_n = 0
	_rev = 0
	_last_vx = 0.0
	_steer_sq = 0.0
	_z0 = 0.0
	_save_t = 10.0


# ------------------------------------------------------------------ storage
static func load_all() -> Array:
	var txt := ""
	if OS.has_feature("web"):
		txt = str(JavaScriptBridge.eval("localStorage.getItem('%s')||'[]'" % KEY))
	elif FileAccess.file_exists(FILE):
		txt = FileAccess.get_file_as_string(FILE)
	var p: Variant = JSON.parse_string(txt) if txt != "" else []
	return p if p is Array else []


static func store(runs: Array) -> void:
	var txt := JSON.stringify(runs)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(s){try{localStorage.setItem('%s',s);window.gazeLabRuns=function(){return JSON.parse(localStorage.getItem('%s')||'[]')}}catch(e){}})(%s)" % [KEY, KEY, JSON.stringify(txt)])
	else:
		var f := FileAccess.open(FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(txt)


func save_run(entry: Dictionary) -> void:
	var runs := RunLog.load_all()
	var found := false
	for i in runs.size():
		if int((runs[i] as Dictionary).get("id", -1)) == int(entry["id"]):
			runs[i] = entry
			found = true
	if not found:
		runs.append(entry)
	while runs.size() > MAX_RUNS:
		runs.remove_at(0)
	RunLog.store(runs)


static func clear_all() -> void:
	RunLog.store([])


static func line(r: Dictionary) -> String:
	var agy: Dictionary = r.get("agency", {})
	var st: Dictionary = r.get("steering", {})
	var res: Dictionary = r.get("result", {})
	var pf: Dictionary = r.get("performance", {})
	var tk: Dictionary = r.get("tracker", {})
	var cs: Dictionary = r.get("course", {})
	var veh: Dictionary = r.get("vehicle", {})
	return "%s  %s  %dm  %d crashes  steer L%d C%d R%d  you %d%%  fps %d  track %s fps %d ms%s" % [String(r.get("when", "")).substr(5, 11), String(cs.get("theme", "")).to_upper(), int(res.get("metres", 0)), int(res.get("crashes", 0)),
		int(float(st.get("left", 0)) * 100.0), int(float(st.get("centre", 0)) * 100.0), int(float(st.get("right", 0)) * 100.0), int(float(agy.get("eyesGateShare", 0)) * 100.0), int(float(pf.get("fpsMean", 0))), str(tk.get("fps", "?")), int(tk.get("latencyMs", -1)),
		"  VEHICLE" if float(veh.get("share", 0)) > 0.5 else ""]


static func copy_text(txt: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(s){try{navigator.clipboard.writeText(s)}catch(e){}})(%s)" % JSON.stringify(txt))
	else:
		DisplayServer.clipboard_set(txt)


static func download(txt: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(s){var b=new Blob([s],{type:'application/json'});var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='gazelab-runs.json';document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove()},500)})(%s)" % JSON.stringify(txt))
