class_name RunRig
extends DownhillRig
## DOWNHILL: free carving down an open slope. No lanes, no gates, no markers: the course is natural (tree lines, boulder bands, scattered
## trees and rocks) with openings you read and aim for. Reach the finish line without wiping out.
##
##   steering   continuous, from where you look (the iris inside the eye, see DownhillRig._eyes_only_offs): a look aside carves that way,
##              a look back to the middle straightens. Keys A / D, a lean (no camera) and the mouse stand in.
##   aim assist look at an opening and keep looking for a moment (AIM_LINGER): it latches, and the board is gently pulled through it.
##              Look somewhere else and it lets go. After you pass it, the next opening is yours to choose.
##   speed      the hill pulls harder the further you go (steeper slope, less drag), so the run keeps getting faster.
##              Carving costs speed, a tuck (chin down) saves it.
##
## It reuses the DownhillRig terrain, trees, rocks, camera, pause monitor and gaze pipeline; only the course, the physics, the HUD and
## the scoring are different. lane_ctl stays at 2 (STEER) so the base gaze tick produces _steer_gaze and the reticle position.

const FINISH_Z := -4200.0
const PULL_RAMP := 3500.0            # metres until the hill is at full pull
const AIM_LINGER := 0.14             # seconds your eyes must stay on an opening before it latches
const AIM_MIN_DIST := 14.0
const AIM_MAX_DIST := 125.0          # kept at the distance the tracking was tested with (the realms commit had raised it to 190)
const START_CALM := 2                # the first segments are open snow
const MIN_SPEED := 14.0

var show_reticle: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("reticle")
var carve_assist: float = 1.0        # how hard a latched opening pulls the board: it is the main control, the raw look only trims
var aim_enabled: bool = true         # tests: switch the opening choice off to check the raw look-trim alone
var _aim_cx: float = -1.0           # your look, smoothed over ~0.2 s, for choosing an opening (the raw cursor jitters by several percent of the screen)
var autopilot: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("autopilot")          # tests (and ?autopilot): steer toward the safe opening of the next barrier
var _aim: Dictionary = {}
var _aim_row: Dictionary = {}
var _cand: Dictionary = {}
var _cand_t: float = 0.0
var _aim_w: float = 0.0
var _aim_want: float = 0.0
var _finished: bool = false
var _end_t: float = 0.0
var _run_t: float = 0.0
var _run_seed: int = 424242
var _best_time: float = 0.0
var _passed_ok: int = 0
var _tight_n: int = 0
var _clean: bool = true
var _last_rz: float = 0.0


func setup(p_player: PlayerController) -> void:
	lane_ctl = 2
	lane_mode = true
	super.setup(p_player)
	Telemetry.set_rig(self)
	if OS.has_feature("web"):
		var bq := str(JavaScriptBridge.eval("window.location.search"))
		if bq.contains("nobeacons"):
			beacons = false
		elif bq.contains("beacons"):
			beacons = true
	name = "RunRig"
	_load_view_pref()
	_read_params()
	if OS.has_feature("web"):
		var pv := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('pmview') || ''"))
		if pv != "":
			pm_view = clampf(float(pv), -1.0, 1.0)
	_zone_scale = 1.8                    # the trim from the raw look is looser: full lock at about +-19% of the screen, not +-10%
	if OS.has_feature("web"):
		_tr_auto = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('trace')"))
		var rsq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('rs') || ''"))
		if rsq == "auto":
			_rs_off = false
		elif rsq != "":
			_rs_pin = clampf(float(rsq), 0.3, 1.0)
			_rs = _rs_pin
			RScale.set_scale(get_viewport(), _rs)
		elif not Game.touch_mode:
			_rs = 1.0                                      # a laptop or desktop in the browser: full sharpness (measured 55-60 fps on built-in Intel graphics once the scaled depth copy was gone, see RScale)
			RScale.set_scale(get_viewport(), _rs)


# --------------------------------------------------------------------------
# Terrain: the base slope, getting steeper with distance
# --------------------------------------------------------------------------
## One stretch of forest trail: the tree lines down both sides (solid: leave the trail and you hit them), forest behind them, and the slalom poles.
## Nothing is drawn further away than this: the haze has hidden it by then.
func _vis_range(n: Node, r: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = r
	for ch in n.get_children():
		_vis_range(ch, r)


func _gen_trail(row: Dictionary, z0: float, cones: Array[Transform3D], cone_cols: PackedColorArray, trunks: Array[Transform3D], trunk_cols: PackedColorArray,
		rocks: Array[Transform3D], rock_cols: PackedColorArray, obs: PackedFloat32Array) -> void:
	var z := z0
	var z_end := maxf(z0 - ROW_GAP, finish_z + 6.0)
	while z > z_end:
		var s := -z
		if s > 26.0:
			var cx := trail_x(z)
			var half := TRAIL_HALF + 2.5 * sin(s / 47.0 + _tr_p2)                       # the trail breathes: a little wider, a little narrower
			for sd in [-1.0, 1.0]:
				var ex: float = cx + float(sd) * (half + _rng.randf_range(0.0, 2.2))
				if absf(ex) < W_HALF - 1.5:
					if _rng.randf() < 0.1:
						_add_rock(rocks, rock_cols, obs, ex + float(sd) * 1.5, z + _rng.randf_range(-1.0, 1.0), _rng.randf_range(1.2, 2.0), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.4))
					else:
						_add_tree(cones, cone_cols, trunks, trunk_cols, obs, ex, z + _rng.randf_range(-1.0, 1.0), _rng.randf_range(0.95, 1.5), true)
				for deep in 3:                                                         # the forest behind the front row: seen, never hit
					var fx: float = cx + float(sd) * (half + 4.0 + _rng.randf_range(0.0, 34.0))
					_add_tree(cones, cone_cols, trunks, trunk_cols, PackedFloat32Array(), fx, z + _rng.randf_range(-1.6, 1.6), _rng.randf_range(1.0, 1.9), false)
		z -= 3.3
	# slalom poles: one on the inside of every turn, at its tightest point
	var poles: Array = []
	var n0 := int(floor((-z0 / TRAIL_TURN_LEN + _tr_p1 - PI * 0.5) / PI))
	for n in range(n0, n0 + 12):
		var sp := (PI * 0.5 + float(n) * PI - _tr_p1) * TRAIL_TURN_LEN
		var pz := -sp
		if not winding or pz > z0 or pz <= z0 - ROW_GAP or sp < 150.0 or pz < finish_z + 30.0:
			continue
		var e := signf(sin(sp / TRAIL_TURN_LEN + _tr_p1))                               # +1: the trail is at its right-most here, so the turn is to the left and the pole stands on the left
		var px := trail_x(pz) - e * 6.5
		var pole := {"x": px, "z": pz, "e": e, "done": false, "n": _make_pole(row, px, pz, e, poles_total % 2 == 0)}
		poles_total += 1
		poles.append(pole)
	row["poles"] = poles
	_gen_feats(row, z0)
	_clear_for_kickers(z0, cones, cone_cols, trunks, trunk_cols, rocks, rock_cols, obs)
	_gen_guide(row, z0)
	# rails, poles, rocks, swirls: a few hundred separate things, each its own draw call on a phone. Nothing further than 300 m ahead needs drawing (the fog has hidden it by then) (a choice is only offered from 130 m)
	for nd in (row["nodes"] as Array):
		if is_instance_valid(nd):
			_vis_range(nd, 260.0)


# --------------------------------------------------------------------------
# FOLLOW THE DOT: on a phone the run starts with a dot that sweeps left and right for about seven seconds. Following it with your eyes is what teaches the game how YOUR
# look reads on THIS phone, held the way you are holding it now (see KitEye). Without it the sideways reading on the phone that was tested barely moved.
# Once per page load; ?nocal skips it, ?calib asks for it on a laptop too.
# --------------------------------------------------------------------------
const CAL_XS := [0.0, -0.75, 0.75, 0.0, 0.75, -0.75, 0.0]          # learning: the dot JUMPS between the middle, the left and the right (it does not glide)
const CAL_STEP := 1.1
const CAL_LEAD := 1.3
var cal_res: Dictionary = {}
# The dots are off by default now (the three places are learned while playing); ?calib or ?eyecheck brings them back.
var _dot_off: bool = not (OS.has_feature("web") and (str(JavaScriptBridge.eval("window.location.search")).contains("calib") or str(JavaScriptBridge.eval("window.location.search")).contains("eyecheck")))
var _dot_force: bool = OS.has_feature("web") and (str(JavaScriptBridge.eval("window.location.search")).contains("calib") or str(JavaScriptBridge.eval("window.location.search")).contains("eyecheck"))
var _dot_t: float = -1.0
var _dot_done: bool = false
var _dot_tries: int = 0
var _dot_targets: Array = []


# --------------------------------------------------------------------------
# EYE CHECK: is the camera reading your eyes? It runs straight after the dot sweep (and again from Pause > EYE CHECK, or with ?eyecheck on a laptop):
#   1  the sweep: the fit itself says how well the readings followed the dot, and whether it was your eyes or your head that followed it
#   2  the look test: the dot JUMPS left, right and to the middle six times; each time the game checks that it read the side you were asked to look at
#   3  the result, in plain words, on screen until you tap, and written to the log (kind "eyecheck")
# ?eyecheck=sim runs it with made-up eyes that follow the dot, to check the check itself.
# --------------------------------------------------------------------------
const CHK_XS := [-0.75, 0.75, 0.0, 0.75, 0.0, -0.75, 0.75, -0.75]
const CHK_STEP := 1.2
var chk_res: Dictionary = {}
var dot_sim: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("eyecheck=sim")
var _dot_phase: int = 0              # 0 the sweep, 1 the look test, 2 the result
var _chk_sum: Array = []            # per prompt: readings that showed the place asked for
var _chk_n: Array = []
var _chk_rt: Array = []             # per prompt: seconds until the game first read that place (-1 = never)
var _chk_tr: Array = []             # the look test as it was read, 20 a second: [t, asked, iris, how far to the side, place read]
var _chk_acc: float = 0.0
var _dot_marks: Array = []          # [time, x] each time the dot jumped
var _chk_lines: Array = []           # [text, 0 good / 1 so-so / 2 bad]
var _chk_head: String = ""
var _chk_grade: int = 0
var _sim_hist: Array = []
var _sim_rng := RandomNumberGenerator.new()
var _sim_dead: bool = false          # tests: the made-up eyes do not move at all


func _dot_x() -> float:
	if _dot_phase == 1:
		return float(CHK_XS[clampi(int(_dot_t / CHK_STEP), 0, CHK_XS.size() - 1)])
	if _dot_phase == 2:
		return 0.0
	var tt := _dot_t - CAL_LEAD
	if tt <= 0.0:
		return 0.0
	return float(CAL_XS[clampi(int(tt / CAL_STEP), 0, CAL_XS.size() - 1)])


## Run the whole check again (from the pause menu).
func eye_check_start() -> void:
	_dot_done = false
	_dot_t = -1.0
	_dot_tries = 0
	_dot_phase = 0
	_dot_force = true
	_dot_off = false
	chk_res = {}
	if not _dot_ready():
		_dot_done = true
		_toast("The eye check needs the camera", Color(1.0, 0.7, 0.3))


func _dot_ready() -> bool:
	if dot_sim:
		return true
	return GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider._camera_fresh() and GazeProvider.kit.has_feat


## Made-up eyes for ?eyecheck=sim and the tests: they follow the dot 0.15 s late, mostly with the head, a little with the iris, with some noise.
func _dot_sim_feed() -> void:
	var now := GazeProvider._now()
	_sim_hist.append(Vector2(now, _dot_x() if _dot_t >= 0.0 else 0.0))
	while _sim_hist.size() > 2 and (_sim_hist[1] as Vector2).x < now - 0.15:
		_sim_hist.pop_front()
	var xl := 0.0 if _sim_dead else (_sim_hist[0] as Vector2).y
	var kit := GazeProvider.kit
	kit.set_feat(-0.03 * xl + _sim_rng.randfn(0.0, 0.004), 0.0, 0.1, 0.04 * xl + _sim_rng.randfn(0.0, 0.008), -0.5, 0.01 * xl, 0.1)
	kit.add(kit.feat[0], 0.3, 0.3, now)


## True while the dot or the result is on screen: the board waits where it is.
func _calib_tick(delta: float) -> bool:
	GazeProvider.kit.auto_zones = _dot_off and GazeProvider.backend == GazeProvider.Backend.CAMERA          # no dots: learn the three places while playing
	if _dot_done or _dot_off or not (Game.touch_mode or _dot_force or dot_sim or GazeProvider.backend == GazeProvider.Backend.CAMERA) or _finished:
		return false
	if dot_sim:
		_dot_sim_feed()
	var kit := GazeProvider.kit
	if _dot_phase == 2:
		_dot_t += delta
		return true                                           # the result stays until a tap
	if not _dot_ready():
		if _dot_t >= 0.0:
			_dot_t = -1.0                                     # the face went away half way through: start again when it is back
			_dot_phase = 0
			kit.recording = false
		return false
	if _dot_t < 0.0:
		_dot_t = 0.0
		_dot_phase = 0
		_dot_marks.clear()
	_dot_t += delta
	var now := GazeProvider._now()
	if _dot_phase == 0:
		var tt := _dot_t - CAL_LEAD
		if tt > -0.4 and not kit.recording:
			kit.begin_zones()
		if tt >= 0.0 and (_dot_marks.is_empty() or float(_dot_marks[_dot_marks.size() - 1][1]) != _dot_x()):
			_dot_marks.append([now, _dot_x()])
		if tt >= float(CAL_XS.size()) * CAL_STEP:
			var stops: Array = []
			for i in _dot_marks.size():
				stops.append([_dot_marks[i][0], _dot_marks[i + 1][0] if i + 1 < _dot_marks.size() else now, _dot_marks[i][1]])
			cal_res = kit.finish_zones(stops)
			_dot_tries += 1
			var rec := cal_res.duplicate()
			rec["try"] = _dot_tries
			Telemetry.event("calib", rec)
			if not dot_sim:
				Telemetry.event("calib_raw", {"try": _dot_tries, "s": kit.fit_raw.get("s", []), "d": kit.fit_raw.get("d", [])})
			if bool(cal_res.get("ok", false)) or _dot_tries >= 2:
				_dot_phase = 1
				_dot_t = 0.0
				_chk_sum.clear()
				_chk_n.clear()
				_chk_rt.clear()
				_chk_tr.clear()
				_chk_acc = 0.0
				for i in CHK_XS.size():
					_chk_sum.append(0)
					_chk_n.append(0)
					_chk_rt.append(-1.0)
			else:
				_dot_t = 0.0                                  # one more go
				_dot_marks.clear()
	else:
		var ci := int(_dot_t / CHK_STEP)
		if ci >= CHK_XS.size():
			_check_finish()
		else:
			var want := int(signf(float(CHK_XS[ci])))
			var in_step := fmod(_dot_t, CHK_STEP)
			var z := kit.zone if not kit.zones.is_empty() else 0
			if z == want and float(_chk_rt[ci]) < 0.0 and in_step > 0.08 and not kit.zones.is_empty():
				_chk_rt[ci] = in_step
			if in_step > 0.55:
				_chk_n[ci] = int(_chk_n[ci]) + 1
				if z == want and not kit.zones.is_empty():
					_chk_sum[ci] = int(_chk_sum[ci]) + 1
			_chk_acc += delta
			if _chk_acc >= 0.05:
				_chk_acc = 0.0
				_chk_tr.append([snappedf(_dot_t, 0.01), want, snappedf(kit.feat[0], 0.0001), snappedf(kit.zn, 0.01), z])
	return true


func _check_finish() -> void:
	var kit := GazeProvider.kit
	var hits := 0
	var per: Array = []
	var rts: Array = []
	for i in CHK_XS.size():
		var share := float(_chk_sum[i]) / maxf(float(_chk_n[i]), 1.0)
		var hit := share >= 0.6
		per.append([int(signf(float(CHK_XS[i]))), snappedf(share, 0.01), snappedf(float(_chk_rt[i]), 0.01)])
		if hit:
			hits += 1
			if i > 0 and float(_chk_rt[i]) >= 0.0:
				rts.append(float(_chk_rt[i]))
	var react := KitEye._median(rts)
	var fitted := not kit.zones.is_empty()
	var fps := 60.0 if dot_sim else float(GazeProvider._pkt_times.size()) / 2.0
	var lat := 0 if dot_sim else int(GazeProvider.trk_lat_ms)
	var st := _guide_status()
	var sep := float(cal_res.get("sep", 0.0))
	var nq := CHK_XS.size()
	_chk_grade = 0 if (hits >= nq - 1 and fitted) else (1 if (hits >= nq - 2 and fitted) else 2)
	_chk_head = ["LEFT, MIDDLE AND RIGHT ARE BEING READ", "ROUGH: SOME LOOKS ARE MISREAD", "NOT READING YOUR EYES"][_chk_grade]
	_chk_lines.clear()
	_chk_lines.append(["Camera: %d readings a second, %d ms behind" % [int(fps), lat], 0 if fps >= 15.0 else (1 if fps >= 9.0 else 2)])
	var face_bad: Array = []
	if float(st["face"]) > 0.0:
		face_bad.append("your face keeps dropping out of the picture")
	if float(st["light"]) > 0.0:
		face_bad.append("poor light on your face: turn toward a window or a lamp")
	if float(st["dist"]) > 0.0:
		face_bad.append("too close or too far")
	if face_bad.is_empty():
		_chk_lines.append(["Face: in view, well placed and lit", 0])
	else:
		for fb in face_bad:
			_chk_lines.append(["Face: " + String(fb), 1])
	if fitted:
		_chk_lines.append(["Learning: a look to a side moves your iris %.1f times the noise" % sep, 0 if sep >= 4.0 else 1])
	else:
		_chk_lines.append(["Learning: left, middle and right could not be told apart (%.1f times the noise)" % sep, 2])
	_chk_lines.append(["Look test: %d of %d read right" % [hits, nq], 0 if hits >= nq - 1 else (1 if hits >= nq - 2 else 2)])
	if not rts.is_empty():
		_chk_lines.append(["Speed: %d ms from the dot jumping to the game reading it" % int(1000.0 * react), 0 if react <= 0.45 else 1])
	chk_res = {"grade": ["good", "rough", "none"][_chk_grade], "hits": hits, "of": nq, "per": per, "react": snappedf(react, 0.01), "fitted": fitted,
		"sep": sep, "noise": cal_res.get("noise", 0.0), "dl": cal_res.get("dl", 0.0), "dr": cal_res.get("dr", 0.0), "agree": cal_res.get("agree", 0), "cal_react": cal_res.get("react", 0.0),
		"fps": snappedf(fps, 0.1), "lat": lat, "face": face_bad, "tries": _dot_tries, "sim": dot_sim}
	Telemetry.event("eyecheck", chk_res.duplicate())
	if not dot_sim:
		Telemetry.event("lmr_trace", {"tr": _chk_tr.duplicate()})
	_dot_phase = 2
	_dot_t = 0.0
	Game.sfx(&"coin" if _chk_grade == 0 else &"hurt")


func _check_dismiss() -> void:
	_dot_done = true
	_dot_phase = 0
	_dot_t = -1.0
	_toast(["EYES LOCKED", "ROUGH LOCK", "NO LOCK: the board will not follow your eyes"][_chk_grade], [Color(0.5, 1.0, 0.6), Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.4)][_chk_grade])


func _draw_calib(font: Font, s: Vector2, k: float) -> void:
	_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.5 if _dot_phase < 2 else 0.86))
	if _dot_phase == 2:
		var hc: Color = [Color(0.5, 1.0, 0.6), Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.4)][_chk_grade]
		_ctext(font, s.y * 0.14, "EYE CHECK", 20, Color(1, 1, 1, 0.7))
		_ctext(font, s.y * 0.14 + 40.0 * k, _chk_head, 32, hc)
		var y := s.y * 0.14 + 84.0 * k
		var x0 := s.x * 0.5 - minf(s.x * 0.42, 400.0 * k)
		for ln in _chk_lines:
			var lc: Color = [Color(0.5, 1.0, 0.6), Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.4)][int(ln[1])]
			_hud.draw_rect(Rect2(x0, y - 13.0 * k, 12.0 * k, 12.0 * k), lc)
			_text(font, Vector2(x0 + 22.0 * k, y), String(ln[0]), 18, Color(1, 1, 1, 0.92))
			y += 30.0 * k
		if _dot_t > 1.0:
			_ctext(font, y + 26.0 * k, "tap to ride", 24, Color(1, 1, 1, 0.6 + 0.3 * sin(_dot_t * 4.0)))
		_ctext(font, y + 54.0 * k, "Pause > EYE CHECK runs this again", 14, Color(1, 1, 1, 0.5))
		return
	if _dot_phase == 0:
		_ctext(font, s.y * 0.2, "LOOK AT THE DOT EACH TIME IT JUMPS", 30, Color(1, 1, 1, 0.95))
		_ctext(font, s.y * 0.2 + 34.0 * k, "eyes only, keep your head and the phone still" if _dot_tries == 0 else "once more: eyes only, a little closer to the light", 16, Color(1, 1, 1, 0.7))
	else:
		_ctext(font, s.y * 0.2, "AGAIN: THE BAR SHOWS WHAT THE GAME READS", 30, Color(1, 1, 1, 0.95))
		_ctext(font, s.y * 0.2 + 34.0 * k, "it should jump to the dot as fast as your eyes do", 16, Color(1, 1, 1, 0.7))
		var zk := GazeProvider.kit
		var zz := zk.zone if not zk.zones.is_empty() else 0
		_hud.draw_rect(Rect2(s.x * (0.02 + 0.32 * float(zz + 1)), s.y * 0.62, s.x * 0.32, 14.0 * k), Color(0.4, 1.0, 0.55, 0.9))
	var c := Vector2((0.5 + 0.5 * _dot_x()) * s.x, s.y * 0.5)
	Draw2D.circle(_hud, c, 26.0 * k, Color(1.0, 0.85, 0.3, 0.25))
	Draw2D.circle(_hud, c, 13.0 * k, Color(1.0, 0.9, 0.4, 1.0))
	Draw2D.circle(_hud, c, 4.0 * k, Color(1, 1, 1, 1))
	var total := (CAL_LEAD + float(CAL_XS.size()) * CAL_STEP) if _dot_phase == 0 else float(CHK_XS.size()) * CHK_STEP
	var bw := minf(s.x * 0.4, 460.0 * k)
	_hud.draw_rect(Rect2(s.x * 0.5 - bw * 0.5, s.y * 0.78, bw, 8.0 * k), Color(0.05, 0.12, 0.25, 0.6))
	_hud.draw_rect(Rect2(s.x * 0.5 - bw * 0.5, s.y * 0.78, bw * clampf(_dot_t / total, 0.0, 1.0), 8.0 * k), Color(1.0, 0.85, 0.35, 0.95))


# --------------------------------------------------------------------------
# EYES vs GAME: the four links between your eyes and what the board does, compared at every choice and drawn live.
#   EYES   what the tracker reads (the fitted look on a phone)                     -1 left .. +1 right
#   READ   what the game makes of it after its own smoothing: left, ahead or right
#   PICK   the target the game chose from that
#   GOT    what the board actually took
# At each left/right choice the four are compared and the first link that broke is named:
#   match     eyes, read, pick and board all agree
#   misread   the game read a different side than your eyes showed (tracker -> game)
#   mispick   the game read your side but chose something else, or nothing (game -> pick)
#   missed    the game chose your side but the board did not get there (pick -> board)
#   stray     you were not looking to a side and the game picked one anyway
#   no look   no look to either side, nothing picked
# Each one is a small line on screen, a record in the log (kind "choice"), and a count on the finish screen. The live chart (Pause > EYE CHART, ?nodiag hides it)
# scrolls the last 8 seconds: yellow = eyes, white = the game's reading, blue = the steering the board was given, green bar = the side picked.
# --------------------------------------------------------------------------
var diag_on: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("diag")          # the eye graph is off in play: ?diag shows it. The readings are still kept in the background
var choice_log: Array = []
var choice_n: Dictionary = {}
var _cho: Dictionary = {}
var _dg_hist: Array = []             # Vector4(eyes, read, steer, pick side), 30 a second
var _dg_acc: float = 0.0
const SIDE_NAME := {-1: "LEFT", 0: "AHEAD", 1: "RIGHT"}


## What the tracker says right now, before the game does anything with it.
func eye_now() -> float:
	if pick_override != 0.0:
		return pick_override
	if zone_test != 99 or zn_test != 99.0:
		return float(_eye_zone())
	var kit := GazeProvider.kit
	if GazeProvider.backend == GazeProvider.Backend.CAMERA and kit.ready and GazeProvider.kit_used():
		if kit.lost:
			return 0.0
		if not kit.zones.is_empty():
			return float(kit.zone)                       # left, middle or right: nothing in between
		return clampf(kit.gaze_x if not kit.model.is_empty() else kit.x, -1.0, 1.0)
	return clampf(_steer_gaze, -1.0, 1.0)


var _dec_key: String = ""


## The decision trace: every step between the eye reading and the board, as short records per choice: [time, what, ...]. what = tgt (what the reading points at and why),
## refused (a look that was long enough to count but the lock rules said no), LOCK (the board is now going for it), drop (it can no longer be reached).
func _dec(g: int, ev: Array) -> void:
	if g < 0:
		return
	var c := _cho_get(g)
	if not c.has("ev"):
		c["ev"] = []
	if (c["ev"] as Array).size() < 40:
		(c["ev"] as Array).append(ev)


func _cho_get(g: int) -> Dictionary:
	if not _cho.has(g):
		_cho[g] = {"t": 0.0, "eL": 0.0, "eR": 0.0, "rL": 0.0, "rR": 0.0, "es": 0.0, "pick": 0, "got": 0, "closed": 0, "kinds": {}, "z": 0.0, "tr": [], "ta": 0.0}
	return _cho[g]


## One thing of a choice is behind the board (or was ridden). When both are, the choice is judged.
func _choice_feat_done(f: Dictionary, got: bool) -> void:
	if f.get("cd", false) or not f.has("g"):
		return
	f["cd"] = true
	var g := int(f["g"])
	var c := _cho_get(g)
	(c["kinds"] as Dictionary)[int(float(f["sd"]))] = String(f["kind"])
	if got:
		c["got"] = int(float(f["sd"]))
	elif int(c.get("pick", 0)) == int(float(f["sd"])):
		# the thing the eyes chose was not taken: where the board was when it went by, for the log
		c["md"] = [String(f["kind"]), snappedf(spos.x - _feat_x(f, spos.z), 0.1), grounded, snappedf(hurt_t, 0.1), int(-vel.y), snappedf(_lock_age, 0.1), _rail.is_empty(), snappedf(spos.y - terrain_h(spos.x, spos.z), 0.1)]
	c["closed"] = int(c["closed"]) + 1
	if int(c["closed"]) < 2:
		return
	_cho.erase(g)
	var tt := maxf(float(c["t"]), 0.01)
	var eyes := 0
	if float(c["eL"]) >= 0.3 and float(c["eL"]) > float(c["eR"]) * 1.3:
		eyes = -1
	elif float(c["eR"]) >= 0.3 and float(c["eR"]) > float(c["eL"]) * 1.3:
		eyes = 1
	var read := 0
	if float(c["rL"]) >= 0.2 and float(c["rL"]) > float(c["rR"]) * 1.3:
		read = -1
	elif float(c["rR"]) >= 0.2 and float(c["rR"]) > float(c["rL"]) * 1.3:
		read = 1
	var pick := int(c["pick"])
	var gotv := int(c["got"])
	var v := "match"
	if eyes == 0:
		v = "no look" if pick == 0 else "stray"
	elif read != eyes:
		v = "misread"
	elif pick != eyes:
		v = "mispick"
	elif gotv != pick:
		v = "missed"
	choice_n[v] = int(choice_n.get(v, 0)) + 1
	var kinds: Dictionary = c["kinds"]
	var got_txt := String(kinds.get(gotv, "nothing")).to_upper() if gotv != 0 else "NOTHING"
	var rec := {"z": int(-spos.z), "v": v, "eyes": eyes, "read": read, "pick": pick, "got": gotv, "got_kind": got_txt.to_lower(), "left": kinds.get(-1, ""), "right": kinds.get(1, ""),
		"eye_mean": snappedf(float(c["es"]) / tt, 0.01), "eye_left_s": snappedf(float(c["eL"]), 0.01), "eye_right_s": snappedf(float(c["eR"]), 0.01), "secs": snappedf(tt, 0.01), "tr": c["tr"], "pz": c.get("pz", 0), "pzn": c.get("pzn", 0.0), "zm": c.get("zm", []), "pnx": c.get("pnx", 0.0), "md": c.get("md", []), "sw": c.get("sw", 0), "dec": c.get("ev", [])}
	choice_log.append(rec)
	if choice_log.size() > 200:
		choice_log.pop_front()
	Telemetry.event("choice", rec.duplicate())
	if diag_on and v != "no look":
		var ok := v == "match"
		_toast("eyes %s > read %s > picked %s > got %s   %s" % [SIDE_NAME[eyes], SIDE_NAME[read], SIDE_NAME[pick] if pick != 0 else "NONE", got_txt, "OK" if ok else v.to_upper()], Color(0.5, 1.0, 0.6) if ok else Color(1.0, 0.6, 0.35), "ach")


func _feat_got(f: Dictionary) -> bool:
	match String(f["kind"]):
		"jump":
			return absf(spos.x - _feat_x(f, float(f["zb"]))) < float(f.get("jw", JUMP_W)) * 0.5 - 1.5
		"loot":
			return f.has("b") and bool((f["b"] as Dictionary)["taken"])
	return false


func _diag_tick(delta: float) -> void:
	_dg_acc += delta
	if _dg_acc < 1.0 / 30.0:
		return
	_dg_acc = 0.0
	_dg_hist.append(Quaternion(eye_now(), clampf(_s_in_now, -1.0, 1.0), steer, 0.0 if _line_pick.is_empty() else float(_line_pick["sd"])))
	if _dg_hist.size() > 240:
		_dg_hist.pop_front()


func choice_summary() -> String:
	var n := 0
	for kk in choice_n:
		n += int(choice_n[kk])
	if n == 0:
		return ""
	var looked := n - int(choice_n.get("no look", 0))
	return "eyes vs board: %d of %d looks taken   misread %d   mispick %d   missed %d   stray %d" % [int(choice_n.get("match", 0)), looked - int(choice_n.get("stray", 0)), int(choice_n.get("misread", 0)), int(choice_n.get("mispick", 0)), int(choice_n.get("missed", 0)), int(choice_n.get("stray", 0))]


## LOOK TARGETS. The things on the trail sit close to the middle of the screen until the last moment, so looking at them barely moves the eyes sideways: on a phone that
## is too small for the camera to tell apart. So each choice also shows as a big round target out at the side of the screen, where the follow-the-dot check proved the
## eyes can be read. Look at one: its ring fills, it turns green, and the board goes for that side.
var _show_cards: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("cards")


func _draw_cards(font: Font, s: Vector2, k: float) -> void:
	if not _show_cards:
		return          # the things carry their own rings now; ?cards brings the round look targets at the sides of the screen back
	for cd in [_card_l, _card_r, _card_m]:
		var fd: Dictionary = cd
		if fd.is_empty() or bool(fd["done"]) or spos.z < float(fd["zb"]) + 6.0:
			continue
		var sd := float(fd.get("cs", fd["sd"]))
		var c := Vector2((0.5 + 0.5 * sd * 0.72) * s.x, s.y * (0.30 if sd == 0.0 else 0.42))
		var on := is_same(_line_pick, fd)
		var fill := 1.0 if on else clampf(float(fd["want"]) / 0.18, 0.0, 1.0)
		var r := (38.0 if on else 32.0) * k
		var col := Color(0.5, 1.0, 0.6) if on else Color(1.0, 0.9, 0.45)
		Draw2D.circle(_hud, c, r, Color(0.03, 0.07, 0.15, 0.55))
		Draw2D.arc(_hud, c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.3), 2.0 * k)
		if fill > 0.0:
			Draw2D.arc(_hud, c, r, -PI * 0.5, -PI * 0.5 + TAU * fill, 32, col, 6.0 * k)
		Draw2D.circle(_hud, c, 5.0 * k, Color(col.r, col.g, col.b, 0.95))
		var nm := String(fd["kind"]).to_upper()
		var fs := int(18.0 * k)
		_text(font, c + Vector2(-_tw(font, nm, fs) * 0.5, r + 22.0 * k), nm, 18, Color(col.r, col.g, col.b, 0.95))


func _draw_diag(font: Font, s: Vector2, k: float) -> void:
	if GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider.kit_used() and GazeProvider.kit.lost_s > 1.0:
		_ctext(font, s.y * 0.2, "CAN'T SEE YOUR FACE", 26, Color(1.0, 0.55, 0.4, 0.75 + 0.2 * sin(GazeProvider.kit.lost_s * 6.0)))
	var w := minf(s.x * 0.36, 400.0 * k)
	var h := 64.0 * k
	var o := Vector2(s.x * 0.5 - w * 0.5, s.y * 0.72)
	_hud.draw_rect(Rect2(o, Vector2(w, h)), Color(0.03, 0.07, 0.15, 0.5))
	_hud.draw_line(o + Vector2(0.0, h * 0.5), o + Vector2(w, h * 0.5), Color(1, 1, 1, 0.25), 1.0)
	var thr := LOOK_PICK / 0.6 * h * 0.5                              # the reading has to pass these lines to count as a look to that side
	_hud.draw_line(o + Vector2(0.0, h * 0.5 - thr), o + Vector2(w, h * 0.5 - thr), Color(0.5, 1.0, 0.7, 0.22), 1.0)
	_hud.draw_line(o + Vector2(0.0, h * 0.5 + thr), o + Vector2(w, h * 0.5 + thr), Color(0.5, 1.0, 0.7, 0.22), 1.0)
	var n := _dg_hist.size()
	if n >= 2:
		var pe := PackedVector2Array()
		var pr := PackedVector2Array()
		var ps := PackedVector2Array()
		for i in n:
			var q: Quaternion = _dg_hist[i]
			var x := o.x + w * (1.0 - float(n - 1 - i) / 239.0)
			pe.append(Vector2(x, o.y + h * 0.5 + clampf(q.x, -1.0, 1.0) * h * 0.5))            # down the chart = RIGHT, up = LEFT
			pr.append(Vector2(x, o.y + h * 0.5 + clampf(q.y / 0.6, -1.0, 1.0) * h * 0.5))
			ps.append(Vector2(x, o.y + h * 0.5 + clampf(q.z, -1.0, 1.0) * h * 0.5))
			if q.w != 0.0 and i > 0:
				var xp := o.x + w * (1.0 - float(n - i) / 239.0)
				_hud.draw_rect(Rect2(xp, o.y + (h - 5.0 * k if q.w > 0.0 else 0.0), x - xp + 1.0, 5.0 * k), Color(0.4, 1.0, 0.6, 0.85))
		_hud.draw_polyline(ps, Color(0.4, 0.75, 1.0, 0.9), 2.0 * k)
		_hud.draw_polyline(pr, Color(1, 1, 1, 0.9), 2.0 * k)
		_hud.draw_polyline(pe, Color(1.0, 0.85, 0.3, 1.0), 2.5 * k)
	_text(font, o + Vector2(-16.0 * k, 12.0 * k), "L", 13, Color(1, 1, 1, 0.9 if look_side < 0.0 else 0.45))
	_text(font, o + Vector2(-16.0 * k, h), "R", 13, Color(1, 1, 1, 0.9 if look_side > 0.0 else 0.45))
	var ly := o.y + h + 15.0 * k
	_text(font, Vector2(o.x, ly), "eyes", 12, Color(1.0, 0.85, 0.3, 0.95))
	_text(font, Vector2(o.x + 44.0 * k, ly), "game's reading", 12, Color(1, 1, 1, 0.9))
	_text(font, Vector2(o.x + 150.0 * k, ly), "steering", 12, Color(0.4, 0.75, 1.0, 0.95))
	_text(font, Vector2(o.x + 214.0 * k, ly), "picked", 12, Color(0.4, 1.0, 0.6, 0.95))
	var cs := choice_summary()
	if cs != "":
		_text(font, Vector2(o.x + w - font.get_string_size(cs.substr(0, 33), HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * k)).x, o.y - 6.0 * k), cs.substr(0, 33), 12, Color(1, 1, 1, 0.75))


# --------------------------------------------------------------------------
# GOALS: three things to do this run, picked at the start and shown on screen. Nothing on the trail is collected by riding down the middle any more: every pole, ramp,
# rail and treat is a little to one side, and it is a look to that side that takes it. The goals say what to go for; each one pays, and all three pay a lot.
# --------------------------------------------------------------------------
const GOAL_POOL := [["shave", "Shave %d poles", 5], ["rail", "Grind %d rails", 3], ["jump", "Hit %d jumps", 4], ["treat", "Eat %d treats", 6], ["orb", "Collect %d orbs", 24], ["flow", "Reach FLOW x%.1f", 6]]
var goals: Array = []
var goals_done: int = 0
var flow_peak: int = 0


func _goals_new() -> void:
	goals.clear()
	goals_done = 0
	flow_peak = 0
	var grng := RandomNumberGenerator.new()
	grng.randomize()
	var pool: Array = GOAL_POOL.duplicate()
	if not winding:
		pool.pop_front()                                    # no poles on the open slope
	var sc := clampf(absf(finish_z) / 4200.0, 0.35, 1.6)
	for i in 3:
		var g: Array = pool.pop_at(grng.randi() % pool.size())
		var need := int(g[2]) if g[0] == "flow" else maxi(int(round(float(g[2]) * sc)), 1)
		var txt := String(g[1]) % (1.0 + 0.25 * float(need)) if g[0] == "flow" else String(g[1]) % need
		goals.append({"id": g[0], "text": txt, "need": need, "done": false})


func _goal_have(id: String) -> int:
	match id:
		"shave":
			return poles_shaved
		"rail":
			return rails_done
		"jump":
			return jumps_done
		"treat":
			return buffs_got
		"orb":
			return orbs_got
		"flow":
			return flow_peak
	return 0


func _goals_tick() -> void:
	flow_peak = maxi(flow_peak, mini(chain, FLOW_MAX))
	if _finished:
		return
	for g in goals:
		if g["done"] or _goal_have(String(g["id"])) < int(g["need"]):
			continue
		g["done"] = true
		goals_done += 1
		var all := goals_done >= goals.size()
		if mode == "race":
			time_pen -= 5.0 if all else 2.0
		else:
			_gain(1500 if all else 500)
		_toast(("ALL GOALS!  %s" if all else "GOAL: " + String(g["text"]) + "  %s") % (("-5 s" if all else "-2 s") if mode == "race" else ("+1500" if all else "+500")), Color(0.5, 1.0, 0.6))
		_flash = maxf(_flash, 0.3)
		Game.sfx(&"loot")


func _draw_goals(font: Font, s: Vector2, k: float, m: float) -> void:
	if goals.is_empty():
		return
	var intro := clampf(4.5 - _run_t, 0.0, 1.0)                       # big in the middle for the first seconds, then small in the corner
	var y := lerpf(m + 128.0 * k, s.y * 0.2, intro)
	var x := lerpf(m, s.x * 0.5 - 150.0 * k, intro)
	var sz := int(lerpf(14.0, 24.0, intro))
	if intro > 0.0:
		_text(font, Vector2(x, y - 12.0 * k), "GOALS", int(lerpf(12.0, 18.0, intro)), Color(1.0, 0.85, 0.3, 0.9))
		y += 16.0 * k * intro + 4.0 * k
	for g in goals:
		var done: bool = g["done"]
		var col := Color(0.5, 1.0, 0.6, 0.9) if done else Color(1, 1, 1, 0.85)
		var bs := float(sz) * 0.7 * k
		if done:
			_hud.draw_rect(Rect2(x, y - bs, bs, bs), col)
		else:
			_hud.draw_rect(Rect2(x, y - bs, bs, bs), col, false, 2.0 * k)
		var have := mini(_goal_have(String(g["id"])), int(g["need"]))
		var txt := String(g["text"]) if (done or g["id"] == "flow") else "%s   %d/%d" % [g["text"], have, int(g["need"])]
		_text(font, Vector2(x + bs + 8.0 * k, y), txt, sz, col)
		y += float(sz) * 1.35 * k


# --------------------------------------------------------------------------
# WHAT IS ON THE TRAIL. Between every two poles the trail runs nearly straight for a moment, and that is where things stand:
#   a JUMP   across the middle: ride on and you fly (eyebrows up on the ramp for a bigger launch), with something to grab in the air
#   a RAIL   down one side: look that way and the board lines itself up, hops on and grinds it. Pop off early for style, or ride it to the end.
#   a LOOT LINE  a string of orbs curving out to one side with a treat at the end
# The side things are a CHOICE: you make it with a look to that side, and the board carves over by itself (the same rule as everywhere: eyes pick, the board steers).
#
# TWO MODES, same trail:
#   "score"  FREESTYLE: the biggest score wins. Flow multiplies everything; rails, tricks and treats are where the points are.
#   "race"   RACE: the fastest time wins. Flow is SPEED: every clean pole, rail and jump raises your pace, a pole on the wrong side costs two seconds, treats are boosts.
# --------------------------------------------------------------------------
## THE OPEN SLOPE (the default; ?winding brings the forest trail back). The trail used to wind, and the board followed its bends by itself: hands off, it turned 10 to 15
## degrees with the first bend, so nobody could tell their eyes from the game. Now the slope runs straight and wide, nothing turns the board but your look, the board sits
## where your eyes are across the slope, and the two things at each choice stand far apart (15 m either side) so going to one is plainly your doing.
static func _winding() -> bool:
	return OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("winding")
var winding: bool = _winding()
var FEAT_OFF: float = 6.5 if _winding() else 15.0                # metres from the middle of the trail to a rail or a loot line
const RAIL_H := 0.9
const BEST_FILE := "user://downhill_best.cfg"
var mode: String = "race" if (OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("mode=race")) else "score"
var time_pen: float = 0.0
var feats_total: int = 0
var jumps_built: int = 0
var jumps_done: int = 0
var rails_built: int = 0
var rails_done: int = 0
var rail_m: float = 0.0
var loot_built: int = 0
var picks: int = 0
var picks_side: Dictionary = {}
var choices_built: int = 0
var look_side: float = 0.0           # what the game reads your look as right now: -1 left, 0 ahead, +1 right
const LOOK_PICK := 0.14
var pick_override: float = 0.0       # tests: a look held to one side (-1 / +1)
var best_val: float = 0.0            # the record for this mode and length before this run
var new_best: bool = false
var _rail: Dictionary = {}           # the rail being ridden
var _rail_z0: float = 0.0
var _rail_dx: float = 0.0
var _rail_pops0: int = 0
var _rail_spark: float = 0.0
var _rail_py: float = 0.0
var _rail_py_ok: bool = false
var _rail_out_t: float = 0.0
var _card_l: Dictionary = {}              # the two things coming up, for the look targets at the sides of the screen
var _card_r: Dictionary = {}
var _card_m: Dictionary = {}              # the thing in the middle of the screen, when there is one
var _line_pick: Dictionary = {}           # the side line your eyes chose
var _s_in_now: float = 0.0
var _rail_meshes: Dictionary = {}
var _rail_post: CylinderMesh


func _feat_x(f: Dictionary, z: float) -> float:
	if f.has("kx"):
		return float(f["kx"])          # a ramp stands where it was built; it does not follow the weave of the trail
	return trail_x(z) + float(f["sd"]) * FEAT_OFF


func _rail_y(f: Dictionary, z: float) -> float:
	return terrain_h(_feat_x(f, z), z) + lerpf(0.15, RAIL_H, smoothstep(0.0, 4.0, float(f["za"]) - z))          # it rises out of the snow over its first metres, so you slide up onto it


## A box laid from a to b (strip points).
func _seg_box(row: Dictionary, a: Vector3, b: Vector3, thick: Vector2, mat: Material) -> void:
	var ln := snappedf(a.distance_to(b) + 0.06, 0.1)
	var key := "%.2f_%.2f_%.1f" % [thick.x, thick.y, ln]
	if not _rail_meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3(thick.x, thick.y, ln)
		_rail_meshes[key] = bm
	var n := MeshInstance3D.new()
	n.mesh = _rail_meshes[key]
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	n.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), Vector3.ZERO)
	_place(n, (a + b) * 0.5)
	(row["nodes"] as Array).append(n)


func _build_rail(row: Dictionary, f: Dictionary) -> void:
	var col := Color(0.35, 0.95, 1.0)
	var mat := _fx_mat("solid", col, 1.8)
	var pmat := _fx_mat("solid", Color(0.3, 0.36, 0.5), 0.5)
	if _rail_post == null:
		_rail_post = CylinderMesh.new()
		_rail_post.top_radius = 0.09
		_rail_post.bottom_radius = 0.12
		_rail_post.height = RAIL_H
		_rail_post.radial_segments = 5
	var za: float = f["za"]
	var zb: float = f["zb"]
	var n := int(ceil((za - zb) / 8.0))
	var prev := Vector3.ZERO
	for i in n + 1:
		var z := lerpf(za, zb, float(i) / float(n))
		var pt := Vector3(_feat_x(f, z), _rail_y(f, z), z)
		if i > 0:
			_seg_box(row, prev, pt, Vector2(0.36, 0.2), mat)
			if i % 2 == 0 or i == n:
				(row["nodes"] as Array).append(_mi(self, _rail_post, pmat, Vector3(pt.x, pt.y - RAIL_H * 0.5, z)))
		prev = pt
	# a spiral of glints round the rail: ride it and you scoop the lot
	var gpts: Array = []
	var gz := za - 3.0
	while gz > zb + 2.0:
		var gt := (za - gz) * 0.8
		gpts.append(Vector3(_feat_x(f, gz) + sin(gt) * 1.1, _rail_y(f, gz) + 1.0 + cos(gt) * 0.7, gz))
		gz -= 2.2 / glint_k
	_glint_line(row, gpts, 2.3)
	# a tall thin light at the way on, so it can be picked out from a long way up the trail
	_buff_assets("orb")
	var ex := _feat_x(f, za)
	(row["nodes"] as Array).append(_mi(self, _buff_mesh["beacon"], _fx_mat("add", Color(col.r, col.g, col.b, 0.3)), Vector3(ex, terrain_h(ex, za) + 4.6, za + 0.5)))


## Nothing may stand where a ramp, its swirl or the ground you are pulled across to reach it is: every tree, rock, trunk, shadow and collision circle inside that
## band is taken out of the stretch before it is built. (A swirl that pulls you sideways into a tree is the worst thing the game can do.)
func _clear_for_kickers(z0: float, cones: Array[Transform3D], cone_cols: PackedColorArray, trunks: Array[Transform3D], trunk_cols: PackedColorArray,
		rocks: Array[Transform3D], rock_cols: PackedColorArray, obs: PackedFloat32Array) -> void:
	var rects: Array[Rect2] = []
	for k in _kickers:
		var kz: float = k["z"]
		var lipz := kz - float(k["len"])
		if kz < z0 - ROW_GAP - 60.0 or lipz > z0 + 60.0:
			continue
		var hw := float(k["w"]) * 0.5 + 24.0
		rects.append(Rect2(float(k["x"]) - hw, lipz - 10.0, hw * 2.0, (kz + VX_REACH + 16.0) - (lipz - 10.0)))
	if rects.is_empty():
		return
	var c2: Array[Transform3D] = []
	var cc2 := PackedColorArray()
	var t2: Array[Transform3D] = []
	var tc2 := PackedColorArray()
	for i in cones.size():
		if not _in_rects(cones[i].origin.x, cones[i].origin.z, rects, 0.0):
			c2.append(cones[i])
			cc2.append(cone_cols[i])
			t2.append(trunks[i])
			tc2.append(trunk_cols[i])
	cones.clear()
	cones.append_array(c2)
	cone_cols.clear()
	cone_cols.append_array(cc2)
	trunks.clear()
	trunks.append_array(t2)
	trunk_cols.clear()
	trunk_cols.append_array(tc2)
	var r2: Array[Transform3D] = []
	var rc2 := PackedColorArray()
	for i in rocks.size():
		if not _in_rects(rocks[i].origin.x, rocks[i].origin.z, rects, 0.0):
			r2.append(rocks[i])
			rc2.append(rock_cols[i])
	rocks.clear()
	rocks.append_array(r2)
	rock_cols.clear()
	rock_cols.append_array(rc2)
	var o2 := PackedFloat32Array()
	var oi := 0
	while oi + 3 < obs.size():
		if not _in_rects(obs[oi], obs[oi + 1], rects, 0.0):
			o2.append(obs[oi])
			o2.append(obs[oi + 1])
			o2.append(obs[oi + 2])
			o2.append(obs[oi + 3])
		oi += 4
	obs.clear()
	obs.append_array(o2)
	var s2: Array[Transform3D] = []
	var sc2 := PackedColorArray()
	for i in _sh_xf.size():
		if not _in_rects(_sh_xf[i].origin.x, _sh_xf[i].origin.z, rects, 9.0):
			s2.append(_sh_xf[i])
			sc2.append(_sh_col[i])
	_sh_xf.clear()
	_sh_xf.append_array(s2)
	_sh_col = sc2


## How much a ramp raises the ground at a point (the ground with it, minus the ground without it).
func _kick_dh(kk: Dictionary, x: float, z: float) -> float:
	if z > float(kk["z"]) + 1.0 or z < float(kk["z"]) - float(kk["len"]) - 1.0 or absf(x - float(kk["x"])) > float(kk["w"]) * 0.5 + 8.0:
		return 0.0
	var last: Dictionary = _kickers.pop_back()
	var h0 := terrain_h(x, z)
	_kickers.append(last)
	return terrain_h(x, z) - h0


## A new ramp raises the ground under things that were put down before it existed (a buff, a pad, a pill, a cupcake in its path): they were set on the old ground and would sit
## buried. Everything built so far in reach of the ramp is lifted by exactly how much the ground came up under it.
func _kick_lift(kk: Dictionary, cur: Dictionary) -> void:
	var rws: Array = _rows.values()
	if not _rows.has(cur["j"]):
		rws.append(cur)
	var zhi := float(kk["z"]) + 20.0
	var zlo := float(kk["z"]) - float(kk["len"]) - 20.0
	for r: Dictionary in rws:
		for n in r["nodes"]:
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var nd := n as Node3D
			if nd.global_position.length() < 0.05 and nd.get_child_count() > 0:
				for c in nd.get_children():
					if c is Node3D:
						_lift_node(c as Node3D, kk, zlo, zhi)
			else:
				_lift_node(nd, kk, zlo, zhi)
		for b in r["buffs"]:
			b["y"] = float(b["y"]) + _kick_dh(kk, float(b["x"]), float(b["z"]))
		for pp in r["pads"]:
			if pp.has("gy"):
				pp["gy"] = float(pp["gy"]) + _kick_dh(kk, float(pp["x"]), float(pp["z"]))
		if r.has("toys"):
			for t in r["toys"]:
				if t.has("y") and t.has("x"):
					t["y"] = float(t["y"]) + _kick_dh(kk, float(t["x"]), float(t["z"]))


func _lift_node(nd: Node3D, kk: Dictionary, zlo: float, zhi: float) -> void:
	var gp := nd.global_position
	var sp := TrailCurve.strip_near(gp, zlo, zhi) if TrailCurve.on else gp
	if sp.z > zhi or sp.z < zlo:
		return
	var dh := _kick_dh(kk, sp.x, sp.z)
	if dh > 0.005:
		nd.global_position = Vector3(gp.x, gp.y + dh, gp.z)


func _in_rects(x: float, z: float, rects: Array[Rect2], grow: float) -> bool:
	for r in rects:
		if r.grow(grow).has_point(Vector2(x, z)):
			return true
	return false


func _make_feat(row: Dictionary, feats: Array, kind: String, zi: float, sd: float, grp: int) -> void:
	feats_total += 1
	if kind == "jump":
		var klen := jump_len
		var kz := zi + klen - 3.0
		var lipz := kz - klen
		var jw := JUMP_W if not _winding() else 10.0          # on the winding trail the lanes are close: a narrower ramp, set out far enough that its inner edge is clear of the middle
		var is_super := sd == 0.0 and _rng.randf() < 0.6
		var kx := trail_x(kz - klen * 0.5) + sd * (jw * 0.5 + 13.0)          # well clear of the trail wherever it weaves along the ramp, so nothing is ever crossed by accident
		_jump_gap_z = -kz
		_kickers.append({"x": kx, "z": kz, "len": klen, "w": jw, "rise": jump_rise * (1.3 if is_super else 1.0), "epic": false, "trail": true, "pw": jump_pow, "curl": jump_curl, "super": is_super})
		_kick_lift(_kickers.back(), row)          # everything already standing where this ramp now rises goes up with the ground
		var lc := Color(1.0, 0.6, 0.15) if not is_super else Color(1.0, 0.95, 0.2)
		var lipm := BoxMesh.new()
		lipm.size = Vector3(jw - 3.0, 0.12, 0.5)
		(row["nodes"] as Array).append(_mi(self, lipm, _fx_mat("solid", lc, 1.6), Vector3(kx, terrain_h(kx, lipz + 0.8) + 0.12, lipz + 0.8)))
		for sx in [-1.0, 1.0]:
			var pole := CylinderMesh.new()
			pole.top_radius = 0.07
			pole.bottom_radius = 0.09
			pole.height = 3.4
			pole.radial_segments = 5
			var px: float = kx + float(sx) * (jw * 0.5 - 0.8)
			var pn := _mi(self, pole, _fx_mat("solid", lc, 1.4), Vector3(px, terrain_h(px, lipz + 1.0) + 1.7, lipz + 1.0))
			(row["nodes"] as Array).append(pn)
			_mi(pn, _quad(1.5), _fx_mat("halo", Color(lc.r, lc.g, lc.b, 0.9)), Vector3(0.0, 1.5, 0.0))
		var lead: Array = [Vector2(trail_x(kz + 12.0) + sd * FEAT_OFF * 0.8, kz + 12.0), Vector2(kx, kz - 2.0)]
		_spawn_buff(row, "boost" if mode == "race" else _pick_buff(true), trail_x(lipz - 11.0) + sd * FEAT_OFF, lipz - 11.0, lead, "air", 2.2)
		var apts: Array = []
		var lip_y := terrain_h(kx, lipz)
		for ai in range(1, int(9.0 * glint_k) + 1):
			var at := float(ai) * 0.45 / glint_k
			var az := lipz - 33.0 * at
			var ay := maxf(lip_y + jump_launch * at - 4.9 * at * at, terrain_h(kx, az) + 1.8)
			apts.append(Vector3(kx, ay, az))
		_glint_line(row, apts, 4.0)          # an arc of glints through the air off the lip: the blast carries you through them
		# AIR CHAIN: big rings hung along the flight. Fly through one and it lifts you and keeps the speed up, so the air goes on; each one in a row pays more.
		var rings: Array = []
		for rt in ([0.9, 1.6, 2.3, 3.0, 3.7] if is_super else [0.9, 1.6, 2.3]):
			var rp := Vector3(kx, lip_y + (jump_launch + jump_blast) * rt - 4.9 * rt * rt + (0.0 if rt < 3.0 else 1.5), lipz - 40.0 * rt)
			var rn := _mi(self, _air_ring_mesh(), _fx_mat("add", Color(1.0, 0.85, 0.3, 0.9) if is_super else Color(0.4, 1.0, 0.9, 0.9)), rp)
			rn.rotation.x = PI * 0.5
			(row["nodes"] as Array).append(rn)
			rings.append({"n": rn, "p": rp, "got": false})
		if not row.has("airrings"):
			row["airrings"] = []
		(row["airrings"] as Array).append_array(rings)
		jumps_built += 1
		_make_vortex(row, _kickers[_kickers.size() - 1], kx, kz, false, true)          # the same swirl the free-ride ramps have, big, so a jump can be seen from far up the slope
		_buff_assets("orb")
		(row["nodes"] as Array).append(_mi(self, _buff_mesh["beacon"], _fx_mat("add", Color(1.0, 0.35, 1.0, 0.3)), Vector3(kx, terrain_h(kx, kz + 8.0) + 4.6, kz + 8.5)))
		# the two edges of the ramp, lit, so its length and where it ends can be seen
		for ex in [-1.0, 1.0]:
			var ex_x: float = kx + float(ex) * (jw * 0.5 - 0.4)
			var ep := Vector3(ex_x, terrain_h(ex_x, kz) + 0.18, kz)
			var en_ := 2
			for ei in range(1, en_ + 1):
				var ez := kz - klen * float(ei) / float(en_)
				var epn := Vector3(ex_x, terrain_h(ex_x, ez) + 0.18, ez)
				_seg_box(row, ep, epn, Vector2(0.3, 0.14), _fx_mat("solid", lc, 1.6))
				ep = epn
		feats.append({"kind": "jump", "za": kz + 44.0, "zl": kz, "zb": lipz, "sd": sd, "done": false, "want": 0.0, "away": 0.0, "g": grp, "kx": kx, "jw": jw})
	elif kind == "boost":
		_boost_row(row, trail_x(zi) + sd * FEAT_OFF, zi - 2.0, sd, grp)
	elif kind == "rail":
		var rl := _rng.randf_range(26.0, 36.0)
		var f := {"kind": "rail", "za": zi + rl * 0.5, "zb": zi - rl * 0.5, "sd": sd, "done": false, "want": 0.0, "away": 0.0, "g": grp}
		_build_rail(row, f)
		rails_built += 1
		feats.append(f)
	else:
		var bz := zi - 8.0
		var lead2: Array = []
		for i in 3:
			var u := float(i + 2) / 5.0
			var oz := bz + 30.0 * (1.0 - u)
			lead2.append(Vector2(trail_x(oz) + sd * FEAT_OFF * u * u * (3.0 - 2.0 * u), oz))          # the orbs curve out toward the treat (they start clear of the middle: riding straight on collects nothing)
		var t := ("boost" if _rng.randf() < 0.7 else "shield") if mode == "race" else ("mult" if loot_built == 0 else _pick_buff(false))
		_spawn_buff(row, t, trail_x(bz) + sd * FEAT_OFF, bz, lead2, "path")
		loot_built += 1
		feats.append({"kind": "loot", "za": bz + 30.0, "zl": bz, "zb": bz - 2.0, "sd": sd, "done": false, "want": 0.0, "away": 0.0, "g": grp, "b": (row["buffs"] as Array).back()})


## A dashed light down the middle of the trail: the way on, easy to find at a glance. One shared draw for the whole stretch.
var _show_guide: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("guide")          # the dashed centre line is off: it drew the eyes


func _gen_guide(row: Dictionary, z0: float) -> void:
	if not _show_guide:
		return
	var xf: Array[Transform3D] = []
	var cols := PackedColorArray()
	var z := z0 - 6.0
	var z_end := maxf(z0 - ROW_GAP, finish_z + 6.0)
	while z > z_end:
		if -z > 26.0:
			var yaw := atan2(trail_x(z - 2.0) - trail_x(z + 2.0), 4.0)
			xf.append(Transform3D(Basis(Vector3.UP, -yaw), Vector3(trail_x(z), terrain_h(trail_x(z), z) + 0.1, z)))
			cols.append(Color(1, 1, 1, 1))
		z -= 11.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.06, 4.2)
	_add_mm(row, bm, xf, cols, _fx_mat("add", Color(0.75, 0.95, 1.0, 0.45)))


## The things that stand between the poles of this stretch of trail. Every one is a CHOICE of two: something on the left and something different on the right, side by
## side, with nothing in the middle. You cannot have both, the board takes neither by itself, and the one you get is the one you looked at: that is how you can tell the
## game is reading your eyes and not steering for you.
func _gen_feats(row: Dictionary, z0: float) -> void:
	var feats: Array = []
	row["feats"] = feats
	var taken: Array = []
	if _cur_m < 0.7:
		# a mild stretch is where speed is made: boost pads laid along the middle of the trail, a few to a stretch, to be hit on purpose
		for pdz0: float in [22.0, 78.0, 134.0]:
			if _rng.randf() < minf(1.0, pad_chance * 6.0):
				var pdz := z0 - pdz0
				var plane := _lane_turn()
				var pdx := trail_x(pdz) + plane * 7.0 + _rng.randf_range(-1.5, 1.5)
				_make_pad(row, pdx, pdz, false)
				_toy_feat(row, pdx, pdz, plane, _toy_g)          # a pad can be looked at and chosen like anything else
				_toy_g += 1
	var rz0: float = row["z"]
	var n0 := int(floor((-z0 / TRAIL_TURN_LEN + _tr_p1) / PI))
	for n in range(n0, n0 + 12):
		var si := (float(n) * PI - _tr_p1) * TRAIL_TURN_LEN          # where the trail swings from one turn into the next: its straightest stretch
		var zi := -si
		if zi > z0 or zi <= z0 - ROW_GAP or si < 230.0 or zi < finish_z + 110.0:
			continue
		var can_jump := _rng.randf() < (1.0 if (-zi - _jump_gap_z > 450.0 and jump_chance > 0.05) else jump_chance) and zi < z0 - (jump_len + 72.0) and zi > z0 - ROW_GAP + 6.0 and absf(zi - 14.0 - rz0) < 140.0          # a ramp is part of this stretch of ground, and what hangs over it must be in reach of this stretch's bookkeeping
		var can_loot := absf(zi + 22.0 - rz0) < 140.0 and absf(zi - 10.0 - rz0) < 140.0
		var kinds: Array = []
		if _rng.randf() < 0.28:          # a rail is one choice among several now, not the default
			kinds.append("rail")
		if can_jump:
			kinds.append("jump")
		if can_loot:
			kinds.append("loot")
		if _rng.randf() < 0.85:
			kinds.append("boost")          # a row of boost pads: in any lane, and one more link for a chain
		for i in range(kinds.size() - 1, 0, -1):
			var jx := _rng.randi() % (i + 1)
			var tmp: String = kinds[i]
			kinds[i] = kinds[jx]
			kinds[jx] = tmp
		_sd_flip = -_sd_flip
		var sd := _sd_flip if _rng.randf() < 0.8 else -_sd_flip          # mostly taking turns: the better thing is not on the same side time after time
		choices_built += 1
		taken.append(zi)
		# LAYOUTS. Every choice point is dressed differently, so no two feel alike:
		#   pair    something on each side (the classic), the middle lane open or with a slalom of rocks to thread
		#   centre  ONE good thing straight ahead in the middle, with rocks on both sides: stay on it, or leave and run the rocks
		#   triple  three different things across the track, left, middle and right
		#   flank   a pair with a small rock cluster between the middle and each side: crossing over takes timing
		var roll := _rng.randf()
		var layout := "pair"
		if roll < 0.22:
			layout = "centre"
		elif roll < 0.58:
			layout = "triple"
			while kinds.size() < 3:
				kinds.append("boost" if not kinds.has("boost") else ("loot" if can_loot else ("rail" if not kinds.has("rail") else "boost")))
		elif roll < 0.78:
			layout = "flank"
		var harder := 0.45 if _cur_m < 0.7 else (1.4 if _cur_m > 1.2 else 1.0)
		var can_rock := absf(zi + 36.0 - rz0) < 140.0
		match layout:
			"centre":
				var ck: String = "jump" if (can_jump and _rng.randf() < 0.35) else ("boost" if _rng.randf() < 0.5 else ("rail" if _rng.randf() < 0.22 or not can_loot else "loot"))
				_make_feat(row, feats, ck, zi, 0.0, choices_built)
				if can_rock and ck != "jump":
					_make_hazard(row, feats, "rock", zi, -9.0, 2, 1.2)
					_make_hazard(row, feats, "rock", zi, 9.0, 2, 1.2)
			"triple":
				_make_feat(row, feats, String(kinds[0]), zi, -1.0, choices_built)
				_make_feat(row, feats, String(kinds[1]), zi, 0.0, choices_built)
				_make_feat(row, feats, String(kinds[2]), zi, 1.0, choices_built)
			_:
				while kinds.size() < 2:
					kinds.append("loot" if can_loot and _rng.randf() < 0.75 else "rail")          # a second treat (a different buff) far more often than a second rail
				_make_feat(row, feats, String(kinds[0]), zi, sd, choices_built)
				_make_feat(row, feats, String(kinds[1]), zi, -sd, choices_built)
				var mid_rocks := false
				if can_rock and not (kinds[0] == "jump" or kinds[1] == "jump") and _rng.randf() < hazard_share * harder:
					if layout == "flank":
						_make_hazard(row, feats, "rock", zi, -7.5, 2, 1.2)
						_make_hazard(row, feats, "rock", zi, 7.5, 2, 1.2)
					else:
						_make_hazard(row, feats, "rock", zi, 0.0, 4, 3.0)          # a slalom of rocks in the middle lane
						mid_rocks = true
				if not mid_rocks and not (kinds[0] == "jump" or kinds[1] == "jump") and _rng.randf() < 0.3:
					_boost_row(row, trail_x(zi), zi - 4.0, 0.0, choices_built)          # the middle lane is never empty: a row of boosts down the middle
	_gen_toys(row, z0, taken)


var _sd_flip: float = 1.0
var hazard_share: float = 0.6            # the sandbox: how often something nasty sits in the middle lane
var _jump_gap_z: float = 0.0          # how far down the hill (m) the last ramp was built: a long stretch without one makes the next choice point have one
var jump_chance: float = 0.72            # the sandbox: how often a choice pair has a ramp in it
var pad_chance: float = 0.12             # the sandbox: boost pads on the slope
var grip_lag: float = 1.0                # the sandbox: > 1 is ice, the board takes longer to swing across
var big_head: bool = false
var bouncy: bool = false                 # the sandbox: landings spring you back up
var trike: bool = false                  # the sandbox: a tricycle, which wobbles from side to side by itself
var glint_k: float = 1.0                 # the sandbox: glint rain
var face_k: float = 1.0                  # the sandbox: face challenges come more often and pay more
var hat_id: int = 0
var _super_face: bool = false

# --------------------------------------------------------------------------
# THE TRIP: a meter that sugar and combos fill and time drains. In the Psychedelic look it drives how far gone the picture is: a tease at first (a little breathing and
# tracer fuzz), then swirling and colours thrown apart, then full blown hallucination. Donuts and candy are the big hits.
# --------------------------------------------------------------------------
var trip: float = 0.0
var _xp_paid: int = 0

# --------------------------------------------------------------------------
# SOUND: the music (procedural techno, trance or industrial) follows how hard the run is going: speed, the steepness of the stretch, the trip, a snowball behind you.
# --------------------------------------------------------------------------
var _music: DhMusic = null
var _vx_snd: bool = false


func _audio_setup(c: Dictionary) -> void:
	DhMusic.ensure_buses()
	DhMusic.set_bus_volume("SFX", float(c.get("svol", 0.9)))
	DhMusic.set_bus_volume("Music", float(c.get("mvol", 0.7)))
	var ah := get_parent().get_node_or_null("AudioHooks") as AudioHooks if get_parent() != null else null
	if ah != null:
		ah.toon = bool(c.get("toon", true))
	var st := String(c.get("mus", "auto"))
	if bool(c.get("journey", true)) and st == "auto":
		st = "techno"          # all dressed starts fast and pumping: the music follows the world from there
	if st == "auto":
		st = String({"alpine": "techno", "psychedelic": "trance", "tunnel": "techno", "desert": "jungle", "matrix": "industrial", "candy": "jungle", "egypt": "ambient"}.get(String(c.get("theme", "alpine")), "techno"))
	if _music != null and is_instance_valid(_music):
		_music.stop()
	_music = null
	_music_next = null
	_music_style = ""
	DhMusic.dbg = "off"
	_audio_cfg = c
	if _dir != null and is_instance_valid(_dir):
		_dir.stop()
		_dir.queue_free()
	_dir = null
	if String(c.get("mus", "auto")) == "auto" and OS.has_feature("web"):
		# AUTO is the real tracks and stems. If they cannot be fetched (or ?nomusic) there is silence, not the synthesised music: that is only for the styles picked by hand in SOUND.
		if not _dir_failed and not str(JavaScriptBridge.eval("window.location.search")).contains("nomusic"):
			_dir = DhDirector.new()
			add_child(_dir)
			_dir.start()
		return
	if st != "off" and OS.has_feature("web"):
		_music = DhMusic.new()
		add_child(_music)
		var mm := _music
		var mseed := int(c.get("seed", 1))
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(mm):
				mm.compose(st, mseed))          # the tune is made after the run has started, not while it loads
		_music_style = st


var _dir: DhDirector = null
var _dir_failed: bool = false
var _audio_cfg: Dictionary = {}


func _music_tick() -> void:
	if _dir != null and is_instance_valid(_dir):
		var hl: Array = []
		for hi in 6:
			hl.append(_mbody[hi] / 6.0)
		_dir.update(get_physics_process_delta_time(), {"avg": _mol_avg(), "holds": hl, "dmt": _mol_dmt(), "exc": _exc, "paused": _paused, "spd": clampf(vel.length() / 45.0, 0.0, 1.0), "air": not grounded and air_t > 0.2})
		DhMusic.dbg = _dir.dbg
		if _dir.failed:
			_dir.queue_free()
			_dir = null
			_dir_failed = true
			_audio_setup(_audio_cfg)          # the synthesised music instead
		return
	if _music == null or not is_instance_valid(_music) or not _music.ready_to_play:
		return
	var sp := clampf(-vel.y / 45.0, 0.0, 1.0)
	var grade := clampf((_cur_m - 0.4) / 1.6, 0.0, 1.0)
	var x := 0.3 + 0.42 * sp + 0.2 * grade + 0.25 * trip + 0.2 * _exc + (0.2 if _sb_on else 0.0) + (0.12 if _boost_t > 0.0 else 0.0)
	if _journey != null:
		x += 0.15 * _journey.trip_floor()
	_music.set_intensity(0.0 if _paused else x)
	if _music_next != null:
		if not is_instance_valid(_music_next):
			_music_next = null
		elif _music_next.ready_to_play:
			_music_fade = minf(_music_fade + get_physics_process_delta_time() / 3.0, 1.0)          # three seconds from one tune to the next
			_music_next.master = _music_fade
			_music.master = 1.0 - _music_fade
			_music_next.set_intensity(0.0 if _paused else x)
			if _music_fade >= 1.0:
				_music.stop()
				_music = _music_next
				_music_next = null
				_music_fade = 0.0
				_music_style = _music_style_to


## The next world's music is composed in the background (a few seconds on a phone) and takes over from the current one with a crossfade.
var _music_style: String = ""
var _music_style_to: String = ""
var _music_next: DhMusic = null
var _music_fade: float = 0.0


func music_morph(st: String, salt: int) -> void:
	if _music == null or not is_instance_valid(_music) or _music_next != null or st == _music_style or not OS.has_feature("web"):
		return
	_music_style_to = st
	_music_next = DhMusic.new()
	_music_next.master = 0.0
	add_child(_music_next)
	_music_next.compose(st, int(params.get("seed", 1)) + salt * 101)

# --------------------------------------------------------------------------
# THE SNOWBALL: now and then, as a steep stretch begins, a giant snowball starts rolling down the slope behind you. It follows where you go but turns slowly, so a quick move
# to the side lets it by; it gains on you wherever you slow down (the gentle stretches), so boost pads, rails, ramps and clean lines are how you stay ahead.
# Get far enough ahead and you have escaped it; stay in its path when it arrives and it flattens you.
# --------------------------------------------------------------------------
var _sb: Node3D = null
var _sb_mesh: Node3D = null
var _sb_z: float = 0.0
var _sb_x: float = 0.0
var _sb_next: float = 700.0
var _sb_on: bool = false
var _sb_close: float = 0.0


func _sb_clear() -> void:
	if _sb != null and is_instance_valid(_sb):
		_sb.queue_free()
	_sb = null
	_sb_mesh = null
	_sb_on = false
	_sb_next = 700.0
	_sb_close = 0.0


func _sb_end(escaped: bool) -> void:
	var dist := -spos.z
	if _sb != null and is_instance_valid(_sb):
		_burst(_sb.global_position, Color(0.9, 0.95, 1.0), 60, 14.0, 1.0, 1.4, Vector3(0, 1, 0), 120.0, -8.0)
		_sb.queue_free()
	_sb = null
	_sb_mesh = null
	_sb_on = false
	_sb_close = 0.0
	_sb_next = dist + _rng.randf_range(650.0, 1100.0)
	if escaped:
		_gain(int(500.0 * groove))
		_flow_up()
		_trip_add(0.1)
		_cue(1)
		_cheer("ESCAPED THE SNOWBALL!", Color(0.8, 0.95, 1.0), 1.5)


func _sb_tick(delta: float) -> void:
	if not trail or _finished or _warming or _paused:
		return
	var dist := -spos.z
	if not _sb_on:
		if dist >= _sb_next and grounded and _grade_of(int(floor(dist / ROW_GAP))) > 1.1 and dist < absf(finish_z) - 450.0:
			_sb_on = true
			_sb_z = spos.z + 75.0
			_sb_x = spos.x
			_sb = Node3D.new()
			add_child(_sb)
			_sb_mesh = Node3D.new()
			_sb.add_child(_sb_mesh)
			var sm := SphereMesh.new()
			sm.radius = 3.0
			sm.height = 6.0
			sm.radial_segments = 16
			sm.rings = 8
			var body := MeshInstance3D.new()
			body.mesh = sm
			_sb_mol = _pick_held_molecule()
			var sbc: Color = MolData.MOLS[MolData.ORDER[_sb_mol]]["c"]
			body.material_override = _fx_mat("solid", Color(0.92, 0.96, 1.0).lerp(sbc, 0.5), 0.9)
			body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_sb_mesh.add_child(body)
			for bi in 7:
				var bump := MeshInstance3D.new()
				var bm := SphereMesh.new()
				bm.radius = 0.7
				bm.height = 1.4
				bm.radial_segments = 6
				bm.rings = 3
				bump.mesh = bm
				bump.material_override = _fx_mat("solid", Color(0.45, 0.5, 0.7), 0.4)
				bump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_sb_mesh.add_child(bump)
				bump.position = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() * 2.9
			_cheer("SNOWBALL!  RUN!", Color(0.8, 0.95, 1.0), 1.4)
			Game.sfx(&"rumble")
			_cue(-1)
		return
	var prog := clampf(dist / 4200.0, 0.0, 1.0)
	var v := 31.0 + 7.0 * prog
	_sb_z -= v * delta
	_sb_x += (spos.x - _sb_x) * clampf(delta * 1.1, 0.0, 1.0)          # it turns slowly: a quick move to the side gets out of its way
	var gap := _sb_z - spos.z
	if _sb != null and is_instance_valid(_sb):
		_place(_sb, Vector3(_sb_x, terrain_h(_sb_x, _sb_z) + 3.0, _sb_z))
		_sb_mesh.rotate_x(v * delta / 3.0)
	_sb_close = clampf(1.0 - (gap - 14.0) / 80.0, 0.0, 1.0)
	_shake = maxf(_shake, 0.35 * _sb_close * _sb_close)
	if gap < 3.8 and absf(spos.x - _sb_x) < 3.9 and spos.y - terrain_h(spos.x, spos.z) < 3.5 and hurt_t <= 0.0:
		_sb_end(false)
		_crash("snowball", "", _sb_mol)
	elif gap > 150.0:
		_sb_end(true)

# --------------------------------------------------------------------------
# SUBLIMINAL CUES: very quiet tones and a faint tint at the edge of the picture that go with doing things well (an early choice, a clean landing, a long rail, a run of glints)
# or badly (a crash, a choice left too late). They are below what you notice, so you do not learn "do this" so much as feel when you are doing well.
# --------------------------------------------------------------------------
var _cue_pl: AudioStreamPlayer = null
var _cue_wav: AudioStreamWAV = null
var _cue_tint: float = 0.0
var _cue_col: Color = Color(1.0, 0.9, 0.5)


func _cue_init() -> void:
	if _cue_pl != null:
		return
	var n := 3086                                                      # 0.14 s at 22050 Hz
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var t := float(i) / 22050.0
		var env := minf(t / 0.012, 1.0) * exp(-t * 22.0)
		pcm.encode_s16(i * 2, int(sin(TAU * 523.0 * t) * env * 16000.0))
	_cue_wav = AudioStreamWAV.new()
	_cue_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_cue_wav.mix_rate = 22050
	_cue_wav.stereo = false
	_cue_wav.data = pcm
	_cue_pl = AudioStreamPlayer.new()
	_cue_pl.stream = _cue_wav
	add_child(_cue_pl)


## kind 1: a good moment (two rising notes and a warm tint); kind -1: a bad one (one low note and a cool tint); kind 2: a rung of the glint ladder, `step` higher each time.
func _cue(kind: int, step: int = 0) -> void:
	if kind == 1:
		Game.sfx(&"cue_good")          # the same soft sounds as everything else (the old separate player was at -25 dB: it could not be heard over the music)
		_cue_tint = 1.0
		_cue_col = Color(1.0, 0.9, 0.5)
	elif kind == -1:
		Game.sfx(&"cue_bad")
		_cue_tint = 1.0
		_cue_col = Color(0.3, 0.4, 0.95)
	else:
		Game.sfx(StringName("lad%d" % mini(step, 9)))          # a rung of the glint ladder: one note higher each time, up the pentatonic scale
var _xp_t: float = 0.0


## Points become XP every couple of seconds (and the last bit when the run ends); a new level opens things in the menu and says so.
func _xp_tick(delta: float, force: bool = false) -> void:
	_xp_t += delta
	if _xp_t < 2.0 and not force:
		return
	_xp_t = 0.0
	var d := score - _xp_paid
	if d <= 0:
		return
	_xp_paid = score
	var opened := DhProgress.add(float(d) * 0.1)
	if not opened.is_empty():
		_cheer("LEVEL UP!  Lv %d" % DhProgress.level(), Color(1.0, 0.85, 0.3), 1.8)
		_toast("Unlocked: " + ", ".join(opened), Color(0.7, 0.9, 1.0))
var _gspeed: float = 0.0
var _lvl: MainLevel = null
var _trip_on: bool = false
var _trip_tier: int = 0
var _trip_force: float = -1.0


func _trip_add(a: float) -> void:
	if not _trip_on:
		return
	trip = clampf(trip + a, 0.0, 1.0)


func _trip_tick(delta: float) -> void:
	if not _trip_on:
		return
	if _trip_force >= 0.0:
		trip = _trip_force
	else:
		trip = maxf(trip - (0.018 + 0.02 * trip) * delta, 0.0)          # it fades slowly, a little faster the further gone you are
		if _journey != null:
			trip = maxf(trip, _journey.trip_floor())          # a wave holds the picture at least this far gone
		trip = maxf(trip, pow(_mol_avg(), 1.8) * 0.9)          # and so do the molecules: slowly at first, hard only near the top
	var tier := 0 if trip < 0.25 else (1 if trip < 0.55 else (2 if trip < 0.85 else 3))
	if tier > _trip_tier and _trip_force < 0.0:
		_cheer(["", "things get colourful...", "WHOA", "FULL TRIP!!"][tier], Color.from_hsv(0.8 - 0.2 * float(tier), 0.8, 1.0), 0.8 + 0.4 * float(tier))
		_gain(int(100.0 * float(tier) * groove))
	_trip_tier = tier
	var fx := _lvl.get_node_or_null("ThemeFX") as ThemeFX if _lvl != null else null
	if fx != null and fx.post != null and fx.post.mat != null:
		fx.post.mat.set_shader_parameter("trip", trip)
		fx.post.mat.set_shader_parameter("breathe", fx.post.amount * (1.0 + trip * 6.0))

## A hazard in the middle lane. "rock": a patch of rocks, a crash (the shield takes it if you have one). "slush": wet heavy snow that drags the board's speed down while in it.
func _make_hazard(row: Dictionary, feats: Array, kind: String, zi: float, cx_off: float = 0.0, nrock: int = 5, spread: float = 3.0) -> void:
	var za := zi + (30.0 if kind == "rock" else 36.0)
	var zb := zi + (22.0 if kind == "rock" else 14.0)
	var zm := (za + zb) * 0.5
	var nodes := row["nodes"] as Array
	var hn: Array = []
	var mi := _rng.randi() % 6          # every hazard belongs to one molecule: it takes a level of that one and no other, and it is that molecule's colour
	var mcol: Color = MolData.MOLS[MolData.ORDER[mi]]["c"]
	if kind == "rock":
		var rm := _fx_mat("solid", Color(0.5, 0.52, 0.6).lerp(mcol, 0.65), 0.8)
		var sm := SphereMesh.new()                                   # one mesh for every rock of the patch, each its own size
		sm.radius = 1.0
		sm.height = 1.5
		sm.radial_segments = 8
		sm.rings = 4
		for i in nrock:
			var rx := trail_x(zm) + cx_off + _rng.randf_range(-spread, spread)
			var rz := zm + _rng.randf_range(-3.5, 3.5)
			var r := _rng.randf_range(1.0, 1.7)
			var rn := _mi(self, sm, rm, Vector3(rx, terrain_h(rx, rz) + r * 0.45, rz))
			rn.scale = Vector3(r, r, r)
			nodes.append(rn)
			hn.append(rn)
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(9.0, 0.08, za - zb)
		var cx := trail_x(zm)
		var sln := _mi(self, bm, _fx_mat("solid", Color(0.5, 0.42, 0.34).lerp(mcol, 0.6), 0.6), Vector3(cx, terrain_h(cx, zm) + 0.1, zm))
		sln.rotation.x = -atan2(terrain_h(cx, za) - terrain_h(cx, zb), za - zb)          # laid along the slope, not flat: a flat slab on a hill stands up out of it like a wall
		nodes.append(sln)
		hn.append(sln)
	_buff_assets("orb")
	var bx := trail_x(za) + cx_off
	nodes.append(_mi(self, _buff_mesh["beacon"], _fx_mat("add", Color(mcol.r, mcol.g, mcol.b, 0.35)), Vector3(bx, terrain_h(bx, za) + 4.6, za + 0.5)))
	nodes.append(_mi(self, _quad(7.0), _fx_mat("halo", Color(mcol.r, mcol.g, mcol.b, 0.45)), Vector3(trail_x(zm) + cx_off, terrain_h(trail_x(zm) + cx_off, zm) + 1.8, zm)))
	hazards_built += 1
	feats.append({"kind": kind, "hz": true, "mol": mi, "hn": hn, "za": za, "zl": zb, "zb": zb, "sd": 0.0, "done": false, "want": 0.0, "away": 0.0, "cx": cx_off, "hw": spread + 0.8})


## Which side thing the eyes have chosen, or {}. At a choice there is one on the left and one on the right: a look held to a side for a moment chooses that one, and a
## look to the other side changes your mind. With no look to either side nothing is chosen and the board rides between them.
var _slide_v: float = 0.0
var hazards_hit: int = 0
var _lock_age: float = 0.0          # seconds since the current lock
var _switch_slow: float = 0.0       # after changing a lock the board turns slowly for a moment: changing your mind costs distance
const COMMIT_S := 0.5
var hazards_built: int = 0
var zone_test: int = 99            # tests: 99 = off, otherwise the place the eyes are read at (-1, 0, +1)


var zn_test: float = 99.0          # tests: 99 = off, otherwise the unrounded reading (-1 = on the left look target, +1 = on the right one)
var fine_test: float = 0.15


func _eye_zone() -> int:
	if zn_test != 99.0:
		return 1 if zn_test > 0.5 else (-1 if zn_test < -0.5 else 0)
	return zone_test if zone_test != 99 else GazeProvider.kit.zone


## The same reading unrounded: 0 = the middle of the screen, -1 / +1 = the look targets at the sides (0.75 of the way to the edge).
func _eye_zn() -> float:
	if zn_test != 99.0:
		return zn_test
	return float(zone_test) if zone_test != 99 else GazeProvider.kit.zn


## The smallest look to a side the reading can be trusted for, in the same units. A steady reading (a laptop) can tell a small look from none, so a look at the thing
## itself counts; a noisy one (a phone) only tells the three places apart, so there this is 0.5 and only the look targets at the sides count.
func _eye_fine() -> float:
	if zn_test != 99.0 or zone_test != 99:
		return fine_test
	var z: Dictionary = GazeProvider.kit.zones
	if z.is_empty():
		return 0.5
	var sep := minf(absf(float(z["dl"])), absf(float(z["dr"]))) / maxf(float(z["noise"]), 1.0e-5)
	return clampf(3.0 / sep, 0.15, 0.5)


## Where a rail, a jump or a loot line is across the screen right now: -1 = the left edge, +1 = the right edge, 99 = not in view. Taken a little ahead of the board.
func _feat_nx(f: Dictionary) -> float:
	var z := clampf(spos.z - 12.0, float(f["zb"]), float(f["za"]))
	var x := _feat_x(f, z)
	var w := Vector3(x, terrain_h(x, z) + 1.0, z)
	if cam == null or _behind(w):
		return 99.0
	var sx := get_viewport().get_visible_rect().size.x
	return clampf(_unp(w).x / maxf(sx, 1.0) * 2.0 - 1.0, -1.5, 1.5)


## Which third of the screen a rail, a jump or a loot line is in, seen from the board: -1 left, 0 straight ahead, +1 right. It is judged where the thing begins, so
## once the board has carved over to it, it is "straight ahead" and the other one is the one to the side.
const SECTOR_M := 2.0
func _sector(f: Dictionary) -> int:
	var dx := _feat_x(f, clampf(spos.z, float(f["zb"]), float(f["za"]))) - spos.x
	return 0 if absf(dx) < SECTOR_M else int(signf(dx))


## True when the eyes are being read as left / middle / right (the learning step passed and the face is in view).
func _zoned() -> bool:
	if zone_test != 99 or zn_test != 99.0:
		return true
	var kit := GazeProvider.kit
	return GazeProvider.backend == GazeProvider.Backend.CAMERA and not kit.zones.is_empty() and kit.ready and not kit.lost


func _trail_pick(delta: float, s_in: float) -> Dictionary:
	var v := pick_override if pick_override != 0.0 else s_in
	_lock_age += delta
	_switch_slow = maxf(_switch_slow - delta, 0.0)
	if not _line_pick.is_empty() and (spos.z < float(_line_pick["zb"]) + 4.0 or bool(_line_pick["done"])):
		_line_pick = {}
	var fl: Dictionary = {}
	var fr: Dictionary = {}
	var fm: Dictionary = {}
	var cands: Array = []
	for kk in _rows:
		for f in (_rows[kk] as Dictionary).get("feats", []):
			var ez0 := float(f["zl"]) if f.has("zl") else float(f["za"])          # where the thing is taken: the ramp's foot, the treat, the top of a rail
			if f.has("hz") or f["done"] or spos.z - ez0 > 130.0 or spos.z < float(f["zb"]) + 6.0:
				continue
			# only what the board can still reach is offered: crossing over takes time, and a thing that will be gone by then is not a choice
			if not is_same(f, _line_pick) and not is_same(f, _rail):
				var reach_t := absf(_feat_x(f, clampf(spos.z, float(f["zb"]), float(f["za"]))) - spos.x) / (SLIDE_MAX * 0.85) + 0.3 + (0.25 if not _line_pick.is_empty() else 0.0)
				var end_z := float(f["zl"]) if f.has("zl") else float(f["zb"]) + 8.0          # a jump or a treat is taken at one spot; a rail anywhere along it
				if (spos.z - end_z) / maxf(-vel.y, MIN_SPEED) < reach_t:
					if not f.has("dr"):
						f["dr"] = true
						_dec(int(f.get("g", -1)), [snappedf(_age, 0.01), "drop", String(f["kind"]), int(float(f["sd"])), "time left %.2f s, needs %.2f s (dx %.1f m)" % [(spos.z - end_z) / maxf(-vel.y, MIN_SPEED), reach_t, _feat_x(f, clampf(spos.z, float(f["zb"]), float(f["za"]))) - spos.x]])
					continue
			cands.append(f)
			if float(f["sd"]) < 0.0:
				if fl.is_empty() or float(f["za"]) > float(fl["za"]):
					fl = f
			elif fr.is_empty() or float(f["za"]) > float(fr["za"]):
				fr = f
	look_side = 0.0 if absf(v) < LOOK_PICK else signf(v)
	var en := eye_now()
	var zoned := pick_override == 0.0 and _zoned()
	var tgt: Dictionary = {}
	if zoned:
		# CHOOSING WITH THE EYES. Everything coming up that can still be reached is a choice, wherever it is and whatever it is. Each is placed where it shows on the
		# screen right now. The nearest ones (one choice) also get a look target out at the side of the screen: the leftmost of them the left target, the rightmost the right.
		#   a look at a side target        chooses the thing it stands for (this is all a noisy reading can tell, and it always works)
		#   a look at the thing itself     chooses it too, when the reading is steady enough to tell that small a look from none: the eyes have to go most of the way to
		#                                  where it is on the screen. Of several that way, the one nearest to where the eyes are.
		#   a look at the middle           chooses nothing and changes nothing: what was chosen stays chosen, and nothing is taken just for being in the way
		var near_g := -1
		var near_za := -1.0e9
		for f in cands:
			f["nx"] = _feat_nx(f)
			if float(f["za"]) > near_za:
				near_za = float(f["za"])
				near_g = int(f.get("g", -1))
		var grp: Array = []
		for f in cands:
			if int(f.get("g", -2)) == near_g and float(f["nx"]) != 99.0:
				grp.append(f)
		grp.sort_custom(func(a, b): return float(a["nx"]) < float(b["nx"]))
		fl = {}
		fr = {}
		fm = {}
		# LOOKING LEFT OR RIGHT MOVES ONE THING ALONG, from where the board is. The reference is what the board is going for, or else the thing nearest the middle of the screen (the one in
		# the board's own lane): a look to the left takes the thing just to the left of it, a look to the right the thing just to the right, and a look held on will keep stepping.
		# (It used to be the leftmost and rightmost of all of them, so the one in between could not be chosen by looking to a side.)
		var ri := -1
		if not _line_pick.is_empty():
			for gi in grp.size():
				if is_same(grp[gi], _line_pick):
					ri = gi
		if ri < 0:
			var bn := 9.0
			for gi in grp.size():
				var an := absf(float((grp[gi] as Dictionary)["nx"]))
				if an < bn:
					bn = an
					ri = gi
		if grp.size() == 1:
			var one: Dictionary = grp[0]
			fm = one
			fm["cs"] = 0
			var cs0 := int(one.get("cs", 0))
			if cs0 == 0:
				cs0 = int(signf(float(one["nx"]))) if absf(float(one["nx"])) > 0.05 else int(float(one["sd"]))
			if cs0 < 0:
				fl = one
			else:
				fr = one
		elif ri >= 0:
			fm = grp[ri]
			fm["cs"] = 0
			if ri > 0:
				fl = grp[ri - 1]
			if ri < grp.size() - 1:
				fr = grp[ri + 1]
		if not fl.is_empty():
			fl["cs"] = -1
		if not fr.is_empty():
			fr["cs"] = 1
		var zone := _eye_zone()
		var g := _eye_zn()
		var fine := _eye_fine()
		look_side = float(zone)
		var why := "none"
		if zone < 0 and not fl.is_empty():
			tgt = fl
			why = "side-L"
		elif zone > 0 and not fr.is_empty():
			tgt = fr
			why = "side-R"
		elif zone == 0 and not fm.is_empty() and absf(g) < 0.3:
			tgt = fm
			why = "middle"
		elif zone != 0 and (fl if zone < 0 else fr).is_empty():
			why = "side-empty"
		elif fine < 0.5:
			var best := 9.0
			for f in cands:
				var cn := float(f["nx"]) / 0.75
				# only a thing well out from the middle of the screen can be chosen by looking at it (a look near the middle is a look at nothing in particular), and the
				# eyes have to be close to where it is
				if absf(cn) < 0.22 or cn > 2.0 or cn * g <= 0.0 or absf(g) < maxf(maxf(0.22, 0.6 * absf(cn)), fine) or absf(cn - g) > 0.4:
					continue
				if absf(cn - g) < best:
					best = absf(cn - g)
					tgt = f
			if not tgt.is_empty():
				look_side = signf(g)
				why = "fine"
		var dkey := "%s|%s|%d" % [why, String(tgt.get("kind", "")), int(float(tgt.get("za", 0.0)))]
		if dkey != _dec_key:
			_dec_key = dkey
			_dec(near_g, [snappedf(_age, 0.01), "tgt", why, String(tgt.get("kind", "-")), int(float(tgt.get("sd", 0.0))), snappedf(g, 0.01), zone, snappedf(fine, 0.01)])
	_card_l = fl
	_card_r = fr
	_card_m = fm
	var seen_g := -1
	for f0 in [fl, fr, fm]:
		var fd0: Dictionary = f0
		if fd0.is_empty() or int(fd0["g"]) == seen_g:
			continue
		seen_g = int(fd0["g"])
		var cc := _cho_get(seen_g)
		cc["t"] = float(cc["t"]) + delta
		cc["es"] = float(cc["es"]) + en * delta
		cc["ta"] = float(cc["ta"]) + delta
		if float(cc["ta"]) >= 0.1 and (cc["tr"] as Array).size() < 100:
			cc["ta"] = 0.0
			(cc["tr"] as Array).append(snappedf(en, 0.01))          # the eye reading ten times a second through the approach, for the log
		if en < -0.2:
			cc["eL"] = float(cc["eL"]) + delta
		elif en > 0.2:
			cc["eR"] = float(cc["eR"]) + delta
		if look_side < 0.0:
			cc["rL"] = float(cc["rL"]) + delta
		elif look_side > 0.0:
			cc["rR"] = float(cc["rR"]) + delta
	for f in (cands if zoned else [fl, fr]):
		var fd: Dictionary = f
		if fd.is_empty():
			continue
		if is_same(fd, tgt) if zoned else (look_side == float(fd["sd"])):
			# a look at the side is a decision; a look at the middle is also where resting eyes go, so taking the middle thing needs a longer, steadier look
			fd["want"] = minf(float(fd["want"]) + delta * (0.35 if (zoned and is_same(fd, fm)) else 1.0), 0.5)
		else:
			fd["want"] = maxf(float(fd["want"]) - delta * (3.0 if look_side != 0.0 else 0.6), 0.0)
		# LOCK ON. The first look settles on a thing after a fifth of a second. Once something is locked it holds, however the eyes wander: another thing takes the lock only
		# after a steady look at it (0.35 s), and not in the last half second before the board reaches the one it is going for.
		var need_w := 0.11          # a look settles on a thing after a ninth of a second
		if not _line_pick.is_empty() and zoned:
			need_w = 0.14 if _lock_age >= COMMIT_S else 0.35          # just locked: committed for half a second, a change of mind in that window needs a longer, steadier look
			var lez := float(_line_pick["zl"]) if _line_pick.has("zl") else float(_line_pick["za"])
			if (spos.z - lez) / maxf(-vel.y, MIN_SPEED) < 0.25 and spos.z > float(_line_pick["zb"]):
				need_w = 9.0
		if float(fd["want"]) > 0.18 and float(fd["want"]) <= need_w and not is_same(_line_pick, fd) and not fd.has("rf"):
			fd["rf"] = true
			_dec(int(fd.get("g", -1)), [snappedf(_age, 0.01), "refused", String(fd["kind"]), int(float(fd["sd"])), snappedf(float(fd["want"]), 0.01), need_w, snappedf(_lock_age, 0.1), "blocked: too close to the locked thing" if need_w >= 9.0 else "holding the lock"])
		elif float(fd["want"]) < 0.05:
			fd.erase("rf")
		if float(fd["want"]) > need_w and not is_same(_line_pick, fd):
			_dec(int(fd.get("g", -1)), [snappedf(_age, 0.01), "LOCK", String(fd["kind"]), int(float(fd["sd"])), snappedf(float(fd["want"]), 0.01), need_w, "switch" if not _line_pick.is_empty() else "first", snappedf(_eye_zn(), 0.01)])
			if not _line_pick.is_empty():
				_switch_slow = 0.8                                  # a change of mind: the turn to the new one is slow at first
			_lock_age = 0.0
			_line_pick = fd
			var ez_l := float(fd["zl"]) if fd.has("zl") else float(fd["zb"]) + 8.0
			var margin := (spos.z - ez_l) / maxf(-vel.y, MIN_SPEED)          # seconds left to get there
			if margin > 2.2:
				_cue(1)
			elif margin < 0.7:
				_cue(-1)
			var pc := _cho_get(int(fd["g"]))
			pc["pick"] = int(float(fd["sd"]))
			pc["sw"] = int(pc.get("sw", 0)) + 1
			pc["pz"] = _eye_zone()
			pc["pzn"] = snappedf(_eye_zn(), 0.01)
			pc["zm"] = [snappedf(float(GazeProvider.kit.zones.get("m", 0.0)), 0.0001), snappedf(float(GazeProvider.kit.zones.get("dl", 0.0)), 0.0001), snappedf(float(GazeProvider.kit.zones.get("dr", 0.0)), 0.0001)]
			pc["pnx"] = snappedf(float(fd.get("nx", 0.0)), 0.01)
			picks += 1
			picks_side[int(float(fd["sd"]))] = int(picks_side.get(int(float(fd["sd"])), 0)) + 1
	return _line_pick


func _rail_off(how: String) -> void:
	var f := _rail
	_rail = {}
	f["done"] = true
	var m := _rail_z0 - spos.z
	_choice_feat_done(f, m >= 6.0)
	rail_m += m
	if how != "drop":
		grounded = false
		air_t = 0.0
		if how == "end":
			vy += 3.2                                             # it throws you off the end: a small hop on top of the way the hill is already carrying you down
	if m < 6.0:
		return
	rails_done += 1
	var pts := int(m * 7.0 * groove) + (80 if how == "pop" else 0)
	_gain(pts)
	_flow_up(2 if m > 18.0 else 1)
	if mode == "race":
		_boost_t = maxf(_boost_t, 1.0 + m / 22.0)                 # in a race a rail is a slingshot
	# THE SLINGSHOT: the longer the grind (and the more glints scooped on it), the more the rail has been stretched like a rubber band: at the end it lets go and fires you out
	var sling := clampf(m / 36.0 + 0.04 * float(_gl_run), 0.0, 1.0)
	if sling > 0.2 and how != "drop":
		vel.y -= 3.0 + 13.0 * sling
		_boost_t = maxf(_boost_t, 0.7 + 1.8 * sling)
		Game.sfx(&"snap")
		_vx_active_t = 0.7                                         # lets the speed run past its cap for a moment: it settles back like a stretched band
		_fov_punch = maxf(_fov_punch, 4.0 + 6.0 * sling)
		_trip_add(0.05 * sling)
		if sling > 0.5:
			_cheer("SLINGSHOT!", Color(0.5, 0.95, 1.0), 0.8 + sling)
	if m >= 20.0:
		_cue(1)
	if _gl_run >= 6:
		_boost_t = maxf(_boost_t, 1.2 + 0.08 * float(_gl_run))      # a rail full of glints scooped: it fires you off the end
		_cheer("GLINT RUSH! x%d" % _gl_run, Color(1.0, 0.85, 0.3), 1.4)
	_toast(("POPPED OFF  %d m" if how == "pop" else "RAIL  %d m") % int(m), Color(0.5, 0.95, 1.0))
	_burst(spos + Vector3(0, 0.3, 0), Color(0.6, 0.95, 1.0), 26, 9.0, 0.6, 0.8, Vector3(0, 1, 0.4), 60.0, -5.0)
	_fov_punch = maxf(_fov_punch, 3.0)
	Game.sfx(&"coin")


## Per physics frame, after the board has moved: getting on a rail, riding it, coming off it.
func _feat_tick(delta: float) -> void:
	if not trail or _finished:
		return
	if not _rail.is_empty():
		var f := _rail
		if hurt_t > 0.0:
			_rail = {}
			f["done"] = true
			_choice_feat_done(f, true)
			return
		if pops_flat != _rail_pops0:
			_rail_off("pop")                                       # eyebrows up: off the rail and into the air, early
			return
		if spos.z <= float(f["zb"]):
			_rail_off("end")
			return
		_rail_out_t = _rail_out_t + delta if (_s_in_now * float(f["sd"]) < -0.8 or (not _zoned() and absf(_s_in_now) > 0.8)) else 0.0          # read as left / middle / right, only a look to the OTHER side lets go
		if _zoned() and not _line_pick.is_empty() and not is_same(_line_pick, f):
			_rail_off("drop")                                      # the eyes chose something else: off this rail and over to it
			return
		if _rail_out_t > 0.3:
			_rail_off("drop")                                      # a hard look away lets go of it
			return
		# held on the rail: the board follows it, whatever the snow underneath is doing
		var slope := (_feat_x(f, spos.z - 1.0) - _feat_x(f, spos.z + 1.0)) * 0.5
		_rail_dx += _slide_v * delta                                    # the sideways speed the board arrived with carries on, then dies away: no stop dead on the rail
		_slide_v *= exp(-delta / 0.1)
		_rail_dx *= exp(-delta / 0.15)                                 # the first metre onto the rail is eased, not a jump
		spos.x = _feat_x(f, spos.z) + _rail_dx
		var ry := _rail_y(f, spos.z)
		vy = clampf((ry - _rail_py) / maxf(delta, 0.0001), -40.0, 10.0) if _rail_py_ok else vy          # falling with the hill, like the snow under it (a pop or the hop off the end is added to this)
		_rail_py = ry
		_rail_py_ok = true
		spos.y = ry
		vel.x = slope * -vel.y
		heading = atan(slope)
		_steer_s = clampf(heading / THETA_MAX, -1.0, 1.0)
		_steer_vel = 0.0
		grounded = true
		_flow_touch()
		_rail_spark -= delta
		if _rail_spark <= 0.0:
			_rail_spark = 0.14
			_burst(spos + Vector3(0, 0.05, 0.6), Color(1.0, 0.9, 0.5), 5, 6.0, 0.3, 0.45, Vector3(0, 1, 1), 50.0, -9.0)
		return
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		for f in r.get("feats", []):
			if f["done"]:
				continue
			if spos.z < float(f["zb"]) + (5.0 if f["kind"] == "rail" else 0.0):
				f["done"] = true
				_choice_feat_done(f, _feat_got(f))
				continue
			if f["kind"] == "rail" and grounded and spos.z < float(f["za"]) + 6.0 and (_line_pick.is_empty() or is_same(_line_pick, f)):
				# a rail has a pull round it, like a small gravity well: the nearer, the harder, so a near miss falls onto it
				var wdx := _feat_x(f, clampf(spos.z, float(f["zb"]), float(f["za"]))) - spos.x
				if absf(wdx) < 7.0 and absf(wdx) > 0.3:
					spos.x += signf(wdx) * minf(absf(wdx), (2.5 + 9.0 * (1.0 - absf(wdx) / 7.0)) * delta)
			if f.has("hz"):
				if f.has("cleared"):
					continue
				var hd: float = spos.z - float(f["za"])
				if hd > 0.0 and hd < 38.0 and _zoned() and not f.has("rolled") and absf(spos.x - (trail_x(spos.z) + float(f.get("cx", 0.0)))) < 6.0:
					# a steady look at it: hold the eyes still on the way in for 0.7 s and there is a chance it breaks. Not a sure thing, a shot worth taking when it cannot be avoided
					f["dwell"] = float(f.get("dwell", 0.0)) + delta if absf(_eye_zn()) < 0.3 else maxf(float(f.get("dwell", 0.0)) - 2.0 * delta, 0.0)
					if float(f["dwell"]) >= 0.7:
						f["rolled"] = true
						if _rng.randf() < 0.55:
							f["cleared"] = true
							for hn in f.get("hn", []):
								if is_instance_valid(hn):
									(hn as Node3D).visible = false
							var hx := trail_x(float(f["za"]))
							_burst(Vector3(hx, terrain_h(hx, float(f["za"])) + 1.0, float(f["za"]) + 4.0), Color(0.8, 0.82, 0.9), 70, 12.0, 0.8, 1.2, Vector3(0, 1, 0), 80.0, -9.0)
							Game.sfx(&"boom")
							_flow_up()
							_cheer("SMASHED!", Color(1.0, 0.9, 0.5), 1.0)
							continue
						_toast("TOUGH ONE", Color(0.8, 0.8, 0.9))
				if spos.z <= float(f["za"]) and spos.y - terrain_h(spos.x, spos.z) < 2.0 and absf(spos.x - (trail_x(spos.z) + float(f.get("cx", 0.0)))) < (float(f.get("hw", 3.6)) if f["kind"] == "rock" else 4.3):
					if f["kind"] == "rock":
						if not f.has("hit"):
							f["hit"] = true
							hazards_hit += 1
							_crash("rock patch", "", int(f.get("mol", -1)))
					else:
						if not f.has("hit"):
							f["hit"] = true
							hazards_hit += 1
							pass
						vel *= exp(-0.9 * delta)
				continue
			if f["kind"] != "rail" or hurt_t > 0.0 or spos.z > float(f["za"]) + 0.5:
				continue
			var near_top := spos.z > float(f["za"]) - 10.0
			if absf(spos.x - _feat_x(f, spos.z)) < (2.6 if near_top else 1.3) and spos.y - _rail_y(f, spos.z) < 2.0:
				_rail = f
				Game.sfx(&"rail_on")
				_rail_dx = spos.x - _feat_x(f, spos.z)
				_rail_z0 = spos.z
				_rail_pops0 = pops_flat
				_gl_run = 0
				_rail_py_ok = false
				_rail_out_t = 0.0
				_rail_spark = 0.0
				_mix_add("rail")
				_shake = maxf(_shake, 0.15)
				Game.sfx(&"coin")
				return


func _best_key() -> String:
	return "%s_%d" % [mode, int(absf(finish_z) / 100.0)]


func _best_load() -> void:
	best_val = 0.0
	new_best = false
	if not Prog.save_enabled:
		return
	var cf := ConfigFile.new()
	if cf.load(BEST_FILE) == OK:
		best_val = float(cf.get_value("best", _best_key(), 0.0))


## The run is over: is it the record for this mode on a course of this length? (A race is judged on time with penalties, a freestyle run on score.)
func _best_store() -> void:
	var val := (_run_t + time_pen) if mode == "race" else float(score)
	new_best = best_val <= 0.0 or (val < best_val if mode == "race" else val > best_val)
	if not new_best or not Prog.save_enabled:
		return
	var cf := ConfigFile.new()
	cf.load(BEST_FILE)
	cf.set_value("best", _best_key(), val)
	cf.save(BEST_FILE)


static func clock_text(t: float) -> String:
	return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]


func _make_pole(row: Dictionary, x: float, z: float, e: float, red: bool) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	_place(root, Vector3(x, terrain_h(x, z), z))
	(row["nodes"] as Array).append(root)
	var col := Color(1.0, 0.22, 0.2) if red else Color(0.2, 0.5, 1.0)
	var mat := _fx_mat("solid", col, 1.6)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.16
	shaft.bottom_radius = 0.2
	shaft.height = 5.2
	shaft.radial_segments = 6
	_mi(root, shaft, mat, Vector3(0.0, 2.6, 0.0))
	var flag := BoxMesh.new()                                         # the banner flies toward the side you pass on
	flag.size = Vector3(2.6, 1.4, 0.12)
	_mi(root, flag, mat, Vector3(e * 1.4, 4.3, 0.0))
	var chev := PrismMesh.new()                                       # and a marker on the snow points the same way
	chev.size = Vector3(2.4, 2.0, 0.3)
	var cn := _mi(root, chev, _fx_mat("add", Color(col.r, col.g, col.b, 0.7)), Vector3(e * 3.4, 0.25, 0.0))
	cn.rotation = Vector3(-PI * 0.5, 0.0, -e * PI * 0.5)
	return root


## Which side did the board pass each pole on, and how close?
func _slalom_tick() -> void:
	if not trail or _finished:
		return
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r.has("poles"):
			continue
		for pl in r["poles"]:
			if pl["done"] or spos.z > float(pl["z"]):
				continue
			pl["done"] = true
			var d := (spos.x - float(pl["x"])) * float(pl["e"])         # + = the right side of it
			if d <= 0.0:
				poles_wrong += 1
				chain = maxi(chain - 2, 0)
				groove = 1.0 + 0.25 * minf(float(chain), float(FLOW_MAX))
				if mode == "race":
					time_pen += 2.0
				_toast("WRONG SIDE  +2 s" if mode == "race" else "WRONG SIDE", Color(1.0, 0.6, 0.3))
			elif d < 2.8:
				poles_shaved += 1
				poles_clean += 1
				_gain(int(60.0 * groove))
				_flow_up(2)
				_toast("SHAVED IT", Color(0.4, 1.0, 0.7))
				_burst(Vector3(float(pl["x"]), spos.y + 1.0, float(pl["z"])), Color(1, 1, 1), 16, 7.0, 0.5, 0.7)
				Game.sfx(&"coin")
			elif d < 4.2:
				poles_clean += 1
				_gain(int(30.0 * groove))
				_flow_up()
				_toast("CLOSE", Color(0.8, 0.95, 1.0))
				Game.sfx(&"coin")


## The next pole ahead, or {}.
func _next_pole() -> Dictionary:
	var best: Dictionary = {}
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r.has("poles"):
			continue
		for pl in r["poles"]:
			if not pl["done"] and (best.is_empty() or float(pl["z"]) > float(best["z"])):
				best = pl
	return best


# --------------------------------------------------------------------------
# FOREST TRAIL: a slalom run. No walls of trees across the hill and no doors in them: one trail, about 26 m wide, winding through forest that stands along both sides,
# over rollers and crests, with a single slalom pole on the inside of every turn. The board follows the trail by itself; your eyes trim the line to shave the poles.
# (?gates brings the old course back.)
# --------------------------------------------------------------------------
var trail: bool = OS.has_feature("web") and not str(JavaScriptBridge.eval("window.location.search")).contains("gates")
const TRAIL_TURN_LEN := 30.0         # metres: the trail swings one way and back every 2 * PI * this (a turn about every 95 m)
var TRAIL_TURN_AMP: float = 13.0 if _winding() else 4.0         # metres either side of its slow line
const TRAIL_DRIFT_LEN := 170.0
var TRAIL_DRIFT_AMP: float = 9.0 if _winding() else 8.0
const TRAIL_SPEED := 23.5           # m/s
var TRAIL_HALF: float = 13.0 if _winding() else 25.0             # half the width of the open snow between the tree lines
var _tr_p1: float = 0.0
var _tr_p2: float = 0.0
var _tr_p3: float = 0.0
var _tr_p4: float = 0.0
var poles_clean: int = 0
var poles_shaved: int = 0
var poles_wrong: int = 0
var poles_total: int = 0


func _trail_k(s: float) -> float:
	return smoothstep(50.0, 170.0, s)          # the first metres run straight, then the turns grow in


## Where the middle of the trail is (strip x) at strip z.
func trail_x(z: float) -> float:
	var s := maxf(-z, 0.0)
	return _trail_k(s) * (TRAIL_TURN_AMP * sin(s / TRAIL_TURN_LEN + _tr_p1) + TRAIL_DRIFT_AMP * sin(s / TRAIL_DRIFT_LEN + _tr_p2))


## How hard the trail is turning there, -1 .. +1 (+ = curving toward +x).
func _trail_turn(z: float) -> float:
	if not winding:
		return 0.0
	var s := maxf(-z, 0.0)
	return -_trail_k(s) * sin(s / TRAIL_TURN_LEN + _tr_p1)


## What the trail adds to the height of the ground: rollers and whoops along it, a bank on the outside of every turn, and the sides rising where the forest stands.
func _trail_h(x: float, z: float) -> float:
	var s := maxf(-z, 0.0)
	var k := _trail_k(s)
	var off := x - trail_x(z)
	var h := k * 1.7 * sin(s / 26.0 + _tr_p3)                                         # long gentle rollers only: the short bumps threw the board into the air every few seconds, and that read as constant bouncing
	h -= 0.11 * _trail_turn(z) * clampf(off, -22.0, 22.0)                             # banked turns: the outside of the bend is higher
	var side := absf(off) - (TRAIL_HALF - 3.0)
	if side > 0.0:
		h += minf(0.02 * side * side, 5.0)                                             # the forest floor climbs away from the trail
	return h


func terrain_h(x: float, z: float) -> float:
	var u := maxf(-z, 0.0)
	var h := _base_h(z) - 0.00002 * u * u
	h += 0.9 * sin(z * 0.031 + 1.3) * cos(x * 0.045) + 0.5 * sin(z * 0.011 - x * 0.02)          # swells, much gentler than the lane game's: a bump must never launch you by accident
	h += 0.6 * sin(z * 0.045 + x * 0.025 + 0.7) * sin(x * 0.03 - z * 0.02)
	var ax := absf(x) - W_HALF
	if ax > 0.0:
		h += 0.0085 * ax * ax
	if trail:
		h += _trail_h(x, z)
	if _zone_by_j.get(int(floor(-z / ROW_GAP)), "") == "melt":
		var fz := fposmod(-z, ROW_GAP)
		h += Realms.melt_h(x, z, smoothstep(0.0, 12.0, fz) * smoothstep(0.0, 12.0, ROW_GAP - fz))          # the ground rolls like liquid, easing in and out at the edges of the stretch
	for k in _kickers:
		var kz: float = k["z"]
		if z > kz + 1.0 or z < kz - float(k["len"]) - 1.0:
			continue
		var uu := (kz - z) / float(k["len"])
		if uu < 0.0 or uu >= 1.0:
			continue
		var half: float = float(k["w"]) * 0.5
		var lat := 1.0 - smoothstep(half - (3.5 if k.get("trail", false) else 2.0), half, absf(x - float(k["x"])))
		var kf := uu
		if k.has("curl"):
			kf = (1.0 - float(k["curl"])) * uu * uu + float(k["curl"]) * pow(uu, 7.0)          # a swoop that is nearly a wall at the lip
		elif k.has("pw"):
			kf = pow(uu, float(k["pw"]))
		h += float(k["rise"]) * kf * lat
	return h


func _course_diff(z0: float) -> float:
	var ref := minf(absf(finish_z), 4200.0)
	return clampf((0.12 + (-z0) / ref * 0.88) * diff_scale, 0.0, 1.0)


func progress() -> float:
	if absf(finish_z) > 1.0e6:
		return fposmod(-spos.z, 1000.0) / 1000.0          # endless: the bar fills every kilometre
	return clampf(-spos.z / absf(finish_z), 0.0, 1.0)


# --------------------------------------------------------------------------
# Course: every segment has a barrier (a line of trees / boulders with openings) at a random depth, and scattered singles in between.
# The safe opening drifts by at most about 36 m from one barrier to the next, so it is always reachable with a carve.
# --------------------------------------------------------------------------
func _gen_segment(j: int) -> void:
	var z0 := -ROW_GAP * float(j)
	var d := _course_diff(z0)
	var post_air := _force_far_next
	# where in its stretch the barrier stands is random over a wide range, so the gap to the next one varies from about 80 m to about 280 m. However short, it is always
	# makeable: the safe opening moves sideways by at most a third of the distance (see `shift` below).
	var rz := z0 - _rng.randf_range(0.56, 0.74) * ROW_GAP if _force_far_next else z0 - _rng.randf_range(0.22, 0.78) * ROW_GAP
	_force_far_next = false
	# now and then a segment has no barrier at all: an air segment, with an epic kicker at the top and room to land
	_region_step(j)
	var zone := _pending_zone if _pending_zone != "" else _pick_zone(j)
	_pending_zone = ""
	if j < 3 or not ZONES.has(zone) or (zone == "air" and (_last_air or rz < finish_z + 300.0)):
		zone = "rush"
	if trail:
		zone = "flat" if _grade_of(j) < 0.7 else ("rush" if _grade_of(j) > 1.1 else "forest")          # plain snow: the stage of the course sets the pitch (see _grade_of)
	var zp: Dictionary = ZONES[zone]
	_cur_zone = zone
	_zone_by_j[j] = zone
	_gen_z0 = z0
	_gen_lip = not Realms.has_roof(String(_zone_by_j.get(j - 1, "")))          # a cave has a low mouth, unless the stretch before it was one too
	_rp.clear()
	_zone_w = float(zp["w"])
	_cur_m = _grade_of(j) if trail else float(zp["m"])
	_push_pitch(z0, _cur_m)
	zones_seen[zone] = int(zones_seen.get(zone, 0)) + 1
	var air_seg := zone == "air"
	_last_air = air_seg
	var has_row := j >= START_CALM and rz > finish_z + 40.0 and not air_seg and not trail          # a forest trail has no barriers across it
	var row: Dictionary = {"j": j, "z": rz, "z0": z0, "gaps": [], "obs": PackedFloat32Array(), "banks": [], "nodes": [],
		"passed": false, "crash": false, "has_row": has_row, "buffs": [], "pads": [], "layout": "none", "zone": zone, "region": _region}
	var cones: Array[Transform3D] = []
	var cone_cols := PackedColorArray()
	var trunks: Array[Transform3D] = []
	var trunk_cols := PackedColorArray()
	var rocks: Array[Transform3D] = []
	var rock_cols := PackedColorArray()
	var obs: PackedFloat32Array = row["obs"]
	var prev_x := _good_x
	var prev_rz := _last_rz
	if has_row:
		var shift := clampf((_last_rz - rz) * 0.30, 8.0, 14.0 if post_air else 44.0)          # after a jump you land close to where you left the line: the next gate is not far off it          # the safe opening moves at most a third of the distance since the last barrier: always reachable
		_last_rz = rz
		if zone == "bend":
			var bside := _pending_bend if _pending_bend != 0.0 else (1.0 if _good_x < 0.0 else -1.0)
			_good_x = clampf(_good_x + bside * shift * 0.75, -42.0, 42.0)          # an abrupt turn: three quarters of what a carve can follow
		else:
			_good_x = clampf(_good_x + _rng.randf_range(-1.0, 1.0) * shift * (0.6 + 0.4 * d), -42.0, 42.0)
		_pending_bend = 0.0
		var gaps: Array = row["gaps"]
		var g0 := _mk_gap(_good_x, lerpf(17.0, 10.0, d) * _rng.randf_range(0.92, 1.1) * _zone_w, "open", true)
		g0["lane"] = -1
		gaps.append(g0)
		g0["iso"] = false
		_layout_gaps(row, gaps, d, prev_x, prev_rz, rz)
		_assign_leads(row, gaps, rz)
		# the barrier: a line of trees, a boulder band or a mix, two staggered rows, skipping the openings
		var style := _rng.randi() % 3
		var p_rock: float = [0.12, 0.8, 0.4][style]
		for line in 2:
			var lz := rz - 2.9 * float(line)
			var k := 0
			while true:
				var x := -W_HALF + (float(k) + 0.5 * float(line)) * 3.7 + _rng.randf_range(-0.4, 0.4)
				k += 1
				if x > W_HALF:
					break
				var inside := false
				for g in gaps:
					if absf(x - float(g["x"])) < float(g["w"]) * 0.5 + 1.6:
						inside = true
				if inside:
					continue
				if _rng.randf() < p_rock:
					_add_rock(rocks, rock_cols, obs, x, lz + _rng.randf_range(-0.6, 0.6), _rng.randf_range(1.1, 1.7), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.4))
				else:
					_add_tree(cones, cone_cols, trunks, trunk_cols, obs, x, lz + _rng.randf_range(-0.6, 0.6), _rng.randf_range(0.8, 1.25), true)
	row["px"] = prev_x
	row["pz"] = prev_rz
	if has_row and j > START_CALM:
		var m_span := prev_rz - rz
		if m_span > 70.0:
			var m_amp := minf(0.10 * m_span, 17.0) * _rng.randf_range(0.55, 1.0) * (0.6 if float(zp["walls"]) > 0.0 else 1.0)
			row["mz"] = Vector3(m_amp * (1.0 if _rng.randf() < 0.5 else -1.0), float(clampi(int(m_span / 70.0), 1, 3)), _rng.randf_range(0.0, PI * 0.5))
	if zone == "interzone" and has_row and bool(params.get("lazy", true)):
		var csgn := -signf(_good_x) if absf(_good_x) > 8.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
		row["cut"] = csgn * _rng.randf_range(9.0, 15.0)          # the world is spliced here: you come out sideways
	var halfw: float = float(zp["walls"])
	if has_row and halfw > 0.0:
		_build_corridor(row, zone, halfw, prev_rz, rz, cones, cone_cols, trunks, trunk_cols, obs)
	# scattered singles between this barrier and the one before it; the straight line from the last safe opening to this one stays clear
	if has_row:
		var n_single := int(minf(prev_rz - rz, ROW_GAP * 1.3) / ROW_GAP * (2.5 + 4.0 * d) * float(zp["singles"])) + (1 if float(zp["singles"]) > 0.0 else 0)          # after an air segment the span is long: no more singles than a normal one has
		for i in n_single:
			var sz := _rng.randf_range(rz + 9.0, minf(prev_rz - 9.0, -30.0))
			var sx := _rng.randf_range(-W_HALF + 3.0, W_HALF - 3.0)
			if absf(sx - path_x(row, sz)) < 9.0 or absf(sx - chord_x(row, sz)) < 6.5:
				continue                                          # the winding trail is clear, and so is the straight cut across its bends (a board that ignores the trail must not meet a tree planted on the direct line)
			var in_air_zone := false
			for az in _air_zones:
				if sz < float(az["z0"]) and sz > float(az["z1"]) and absf(sx - float(az["x"])) < 16.0:
					in_air_zone = true
			if in_air_zone:
				continue
			if _rng.randf() < 0.35:
				_add_rock(rocks, rock_cols, obs, sx, sz, _rng.randf_range(1.0, 1.6), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.3))
			else:
				_add_tree(cones, cone_cols, trunks, trunk_cols, obs, sx, sz, _rng.randf_range(0.8, 1.3), true)
	if trail:
		_gen_trail(row, z0, cones, cone_cols, trunks, trunk_cols, rocks, rock_cols, obs)
	else:
		_place_kicker(row, obs, prev_rz, rz, z0, has_row, j, air_seg)
	# boost pads live out on the slope now, not on ramps (the vortex does the ramps): now and then one lies on the safe line a little after a barrier
	if has_row and not air_seg and _rng.randf() < pad_chance:
		var pdz := rz - _rng.randf_range(24.0, 40.0)
		_make_pad(row, path_x(row, pdz) + _rng.randf_range(-3.0, 3.0), pdz, false)
	if has_row:
		_place_buffs(row, d, prev_rz, rz)
		_make_signs(row, rz)
	# forest and boulders on both sides (visual only)
	for side in [-1.0, 1.0]:
		for i in 22:
			var fx: float = float(side) * (W_HALF + 2.5 + _rng.randf_range(0.0, 70.0))
			_add_tree(cones, cone_cols, trunks, trunk_cols, PackedFloat32Array(), fx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(0.9, 1.6), false)
	for side2 in [-1.0, 1.0]:
		for ci in 2:
			var cxx: float = float(side2) * (W_HALF + _rng.randf_range(8.0, 36.0))
			_add_rock(rocks, rock_cols, PackedFloat32Array(), cxx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(7.0, 14.0), Color.WHITE, _rng.randf_range(0.9, 1.5), false)
	var zlo := 1.0e9
	var zhi := -1.0e9
	var oi := 0
	while oi < obs.size():
		zlo = minf(zlo, obs[oi + 1])
		zhi = maxf(zhi, obs[oi + 1])
		oi += 4
	row["zmin"] = zlo - 4.0
	row["zmax"] = zhi + 4.0
	_add_mm(row, _m_shadow, _sh_xf, _sh_col, _m_shadow_mat)
	_sh_xf.clear()
	_sh_col = PackedColorArray()
	_add_mm(row, _m_cone, cones, cone_cols)
	_add_mm(row, _m_trunk, trunks, trunk_cols)
	_add_mm(row, _m_rock, rocks, rock_cols)
	_flush_realm(row, zone, j, z0)
	if z0 > finish_z and z0 - ROW_GAP <= finish_z:
		_make_finish(row)
	_rows[j] = row
	if _gen_sliced:
		_chunk_jobs.append(_chunk_job_new(j))                  # the ground mesh is built over the next few frames, a few milliseconds each
	else:
		_chunks[j] = _build_chunk(j)
	_update_mist(z0 - ROW_GAP)
	if has_row and bool(params.get("lazy", true)):
		_gate_open = false                                    # the next stretch is built when you go through this barrier


## The finish: two tall posts and a chequered bar across the whole run.
func _make_finish(row: Dictionary) -> void:
	var red := _flat_mat(Color(0.92, 0.18, 0.15))
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * 24.0
		var post := MeshInstance3D.new()
		post.mesh = _m_post
		post.material_override = red
		post.scale = Vector3(2.4, 2.4, 2.4)
		add_child(post)
		_place(post, Vector3(px, terrain_h(px, finish_z) + 6.0, finish_z))
		(row["nodes"] as Array).append(post)
	for i in 12:
		var bx := -22.0 + 4.0 * float(i)
		var seg := MeshInstance3D.new()
		seg.mesh = _m_bar
		seg.scale = Vector3(4.0, 1.8, 0.8)
		seg.material_override = _flat_mat(Color(0.97, 0.97, 1.0) if i % 2 == 0 else Color(0.12, 0.12, 0.16))
		add_child(seg)
		_place(seg, Vector3(bx, terrain_h(bx, finish_z) + 12.4, finish_z))
		(row["nodes"] as Array).append(seg)


# --------------------------------------------------------------------------
# ZONES: what lies beyond a gate. Every gate in a barrier leads somewhere different, and the next stretch of the course is only built once you have gone
# through one (a bank of mist hides what is beyond until then). The signs above the gates tell you what each one leads to, so you can learn them:
#   RUSH    steep and fast, a clear run, few trees.                  Good place to be hammered by a boost: a long straight to spend it on.
#   MEADOW  gentle and slow, wide spread-out gates, many pickups.    A boost lifts you out of the slow stretch; candy and donuts to farm.
#   TUNNEL  a lined corridor with narrow hoops to thread, no lone trees.   A shield is the sensible thing to carry in; a boost leaves no time to think.
#   BEND    a sharp turn, lined with trees.                           A boost in front of the gate will pin you in the corner. Brake into it (tuck).
#   AIR     a big ramp, room to fly, pads and pickups above the lip.  Boost into it for an epic jump.
# --------------------------------------------------------------------------
const ZONES := {
	"rush": {"m": 1.45, "w": 1.0, "singles": 0.5, "walls": 0.0, "path_buff": 0.30, "col": Color(1.0, 0.3, 0.25), "name": "RUSH"},
	"flat": {"m": 0.55, "w": 1.45, "singles": 1.1, "walls": 0.0, "path_buff": 0.85, "col": Color(0.4, 0.9, 0.5), "name": "MEADOW"},
	"tunnel": {"m": 1.25, "w": 0.95, "singles": 0.0, "walls": 26.0, "path_buff": 0.12, "col": Color(0.7, 0.45, 1.0), "name": "TUNNEL"},
	"bend": {"m": 1.0, "w": 1.0, "singles": 0.5, "walls": 30.0, "path_buff": 0.35, "col": Color(1.0, 0.85, 0.3), "name": "BEND"},
	"air": {"m": 1.0, "w": 1.0, "singles": 0.0, "walls": 0.0, "path_buff": 0.0, "col": Color(1.0, 0.4, 0.7), "name": "AIR"},
	"forest": {"m": 1.15, "w": 1.0, "singles": 3.2, "walls": 0.0, "path_buff": 0.4, "col": Color(0.2, 0.75, 0.35), "name": "FOREST"},
	"drop": {"m": 2.2, "w": 1.15, "singles": 0.25, "walls": 0.0, "path_buff": 0.2, "col": Color(1.0, 0.6, 0.15), "name": "DROP"},
	# the realms (see Realms.gd): no name on the gate, a violet glyph; the name shows when you arrive
	"highway": {"m": 1.35, "w": 1.1, "singles": 0.9, "walls": 0.0, "path_buff": 0.25, "col": Color(1.0, 0.35, 0.75), "scol": Realms.SIGN_COL, "name": "DESERT HIGHWAY"},
	"interzone": {"m": 1.0, "w": 1.0, "singles": 1.1, "walls": 0.0, "path_buff": 0.3, "col": Color(0.98, 0.84, 0.2), "scol": Realms.SIGN_COL, "name": "INTERZONE"},
	"hive": {"m": 1.2, "w": 0.85, "singles": 0.0, "walls": 22.0, "path_buff": 0.1, "col": Color(0.5, 0.9, 0.6), "scol": Realms.SIGN_COL, "name": "THE HIVE"},
	"eyes": {"m": 0.95, "w": 1.05, "singles": 2.2, "walls": 0.0, "path_buff": 0.45, "col": Color(1.0, 0.5, 0.5), "scol": Realms.SIGN_COL, "name": "ORCHARD OF EYES"},
	"melt": {"m": 1.1, "w": 1.0, "singles": 0.8, "walls": 0.0, "path_buff": 0.35, "col": Color(0.4, 1.0, 0.8), "scol": Realms.SIGN_COL, "name": "THE MELT"},
	"mandala": {"m": 2.0, "w": 1.15, "singles": 0.9, "walls": 0.0, "path_buff": 0.2, "col": Color(1.0, 0.7, 1.0), "scol": Realms.SIGN_COL, "name": "MANDALA DROP"},
	# the roofed ones: caves and chambers, dark inside, lit by what grows or burns there
	"canyon": {"m": 1.3, "w": 1.1, "singles": 1.4, "walls": 22.0, "path_buff": 0.35, "col": Color(1.0, 0.55, 0.25), "scol": Realms.SIGN_COL, "name": "RED CANYON"},
	"mammoth": {"m": 0.9, "w": 1.2, "singles": 1.5, "walls": 0.0, "path_buff": 0.45, "col": Color(0.55, 1.0, 0.35), "scol": Realms.SIGN_COL, "name": "MAMMOTH GARDEN"},
	"glowcave": {"m": 1.0, "w": 1.1, "singles": 1.6, "walls": 0.0, "path_buff": 0.4, "col": Color(0.3, 1.0, 0.8), "scol": Realms.SIGN_COL, "name": "GLOW GROTTO"},
	"crystal": {"m": 1.15, "w": 1.0, "singles": 1.4, "walls": 0.0, "path_buff": 0.3, "col": Color(0.6, 0.9, 1.0), "scol": Realms.SIGN_COL, "name": "CRYSTAL VAULT"},
	"lava": {"m": 1.5, "w": 0.9, "singles": 2.2, "walls": 0.0, "path_buff": 0.15, "col": Color(1.0, 0.45, 0.1), "scol": Realms.SIGN_COL, "name": "LAVA TUBE"},
	"abyss": {"m": 0.85, "w": 1.1, "singles": 1.2, "walls": 0.0, "path_buff": 0.5, "col": Color(0.2, 0.7, 1.0), "scol": Realms.SIGN_COL, "name": "JELLY ABYSS"},
}
## What a gate offers in front of it depends on what lies behind it, so the offer teaches you something: a burger is as likely in front of a BEND (a trap)
## as in front of a RUSH (a reward).
const FOOD_BY_ZONE := {
	"rush": {"boost": 0.4, "shield": 0.15, "mult": 0.25, "donut": 0.2},
	"flat": {"boost": 0.3, "shield": 0.1, "mult": 0.35, "donut": 0.25},
	"tunnel": {"boost": 0.25, "shield": 0.4, "mult": 0.2, "donut": 0.15},
	"bend": {"boost": 0.4, "shield": 0.3, "mult": 0.15, "donut": 0.15},
	"air": {"boost": 0.2, "shield": 0.1, "mult": 0.45, "donut": 0.25},
	"forest": {"boost": 0.15, "shield": 0.4, "mult": 0.2, "donut": 0.25},          # trees everywhere: a boost here is a gamble, a shield is not
	"drop": {"boost": 0.1, "shield": 0.3, "mult": 0.3, "donut": 0.3},              # already fast enough: the sensible gifts are the ones that do not add speed
}
const DEFAULT_ZONE_WEIGHTS := {"rush": 1.0, "flat": 0.9, "tunnel": 0.8, "bend": 1.4, "air": 0.9, "forest": 0.8, "drop": 0.5,
	"highway": 0.8, "interzone": 0.8, "hive": 0.7, "eyes": 0.8, "melt": 0.7, "mandala": 0.7, "glowcave": 1.0, "crystal": 0.9, "lava": 0.8, "abyss": 0.8, "canyon": 1.0, "mammoth": 1.0}

## Regions: the world comes in stretches of four to seven zones with a character of their own (which zones are likely, and the colour of the snow). A banner says when you cross into one.
const REGIONS := {
	"pines": {"name": "PINE VALLEY", "tint": Color(1.0, 1.0, 1.0), "w": {"forest": 1.8, "flat": 1.1, "mammoth": 1.2, "canyon": 0.6}},
	"glacier": {"name": "THE GLACIER", "tint": Color(0.78, 0.9, 1.0), "w": {"tunnel": 1.8, "drop": 1.3, "flat": 0.5}},
	"ember": {"name": "EMBER RIDGE", "tint": Color(1.0, 0.86, 0.78), "w": {"rush": 1.5, "drop": 1.8, "bend": 1.3, "flat": 0.5}},
	"blossom": {"name": "BLOSSOM FIELDS", "tint": Color(1.0, 0.9, 0.96), "w": {"flat": 1.9, "forest": 1.1, "air": 1.4, "tunnel": 0.4, "mammoth": 3.0}},
	"dusk": {"name": "DUSK CANYON", "tint": Color(0.86, 0.84, 1.0), "w": {"bend": 1.8, "tunnel": 1.3, "rush": 1.1, "air": 0.5, "canyon": 3.2}},
	"fever": {"name": "THE FEVER", "tint": Color(1.0, 0.9, 1.0), "w": {"highway": 2.4, "interzone": 2.4, "hive": 2.2, "eyes": 2.4, "melt": 2.2, "mandala": 2.2, "flat": 0.4, "forest": 0.3}},
	"under": {"name": "THE UNDERWORLD", "tint": Color(0.9, 0.9, 1.0), "w": {"glowcave": 3.0, "crystal": 2.6, "lava": 2.2, "abyss": 2.4, "flat": 0.3, "forest": 0.3, "rush": 0.5}},
}
const REGION_ORDER := ["pines", "glacier", "ember", "blossom", "dusk", "fever", "under"]

var _pitch: Array = []                  # the slope of the hill, stretch by stretch: [{z, h, s}]
var _cur_zone: String = "rush"
var _region: String = "pines"
var _region_left: int = 5
var _player_region: String = "pines"
var regions_seen: Dictionary = {}
var _pending_zone: String = ""          # set by the gate you go through
var _pending_bend: float = 0.0
var _gate_open: bool = true             # false: the next stretch waits for you to go through the barrier ahead
var _mist: MeshInstance3D
var _zone_w: float = 1.0
var zones_seen: Dictionary = {}
var realms_seen: Dictionary = {}
var finish_z: float = FINISH_Z
var diff_scale: float = 1.0
var params: Dictionary = {"seed": 424242, "length": 4200, "diff": 1.0, "zones": {}, "lazy": true}


func _base_h(z: float) -> float:
	var n := _pitch.size()
	if n == 0:
		return z * SLOPE
	var i := n - 1
	while i > 0 and float(_pitch[i]["z"]) < z:
		i -= 1
	var e: Dictionary = _pitch[i]
	return float(e["h"]) + (z - float(e["z"])) * float(e["s"])


var _cur_m: float = 1.0                 # the pitch of the stretch being built, as a multiple of the base slope

## THE STAGES. The course builds from slow to as fast as you can handle, in stages that repeat and each time get steeper: long mild slopes where speed has to be made
## (boost pads, burgers, rail slingshots and ramps matter most), a short build-up, then steep drops where the speed is free and the thing that matters is choosing
## and hitting the right line. Each steep one is steeper than the last.
const STAGE_CYCLE := [0.0, 0.0, 0.0, 0.5, 1.0, 1.0]          # in rows (about 180 m each): 0 mild, 0.5 build, 1 steep
func _grade_of(j: int) -> float:
	var prog := clampf(float(j) * ROW_GAP / maxf(minf(absf(finish_z), 4200.0), 600.0), 0.0, 1.0)
	if j < 2:
		return 0.4                                                            # a slow start: time to settle in
	var k: float = STAGE_CYCLE[(j - 2) % STAGE_CYCLE.size()]
	var mild := 0.42 + 0.16 * prog
	var steep := 1.3 + 0.85 * prog
	return lerpf(mild, steep, k) + 0.04 * sin(float(j) * 2.7)


func _push_pitch(z: float, m: float) -> void:
	_pitch.append({"z": z, "h": _base_h(z), "s": SLOPE * m})


func _zone_weights() -> Dictionary:
	var w: Dictionary = DEFAULT_ZONE_WEIGHTS.duplicate()
	var pz: Dictionary = params.get("zones", {})
	for k in pz:
		w[k] = float(pz[k])
	var rw: Dictionary = (REGIONS[_region] as Dictionary)["w"]
	for k in rw:
		w[k] = float(w.get(k, 1.0)) * float(rw[k])
	for k in Realms.IDS:
		w[k] = float(w.get(k, 1.0)) * weird                      # 0 = none of the strange places, 1 = the usual share, 2 = mostly strange
	if _force_realm != "":
		for k in ZONES:
			w[k] = 1.0 if (Realms.is_realm(k) and (_force_realm == "all" or _force_realm == k)) else 0.0
	return w


## Called once per segment: a region lasts four to seven of them, then another (never the same twice in a row) takes over.
func _region_step(j: int) -> void:
	if j < 4:
		_region = "pines"
		_region_left = 5
		return
	_region_left -= 1
	if _region_left <= 0:
		var opts: Array = REGION_ORDER.duplicate()
		opts.erase(_region)
		_region = String(opts[_rng.randi() % opts.size()])
		_region_left = _rng.randi_range(4, 7)
	regions_seen[_region] = int(regions_seen.get(_region, 0)) + 1


var _gen_sliced: bool = false           # true only for the stretch built when you pass a gate while playing


func _chunk_tint(j: int) -> Color:
	if _rows.has(j):
		return (REGIONS[String((_rows[j] as Dictionary).get("region", "pines"))] as Dictionary)["tint"]
	return Color.WHITE


func _pick_zone_w(excl: Array, d: float) -> String:
	var w := _zone_weights()
	var total := 0.0
	var wl: Dictionary = {}
	for k in ZONES:
		if excl.has(k):
			continue
		var x: float = float(w.get(k, 1.0))
		if k == "bend" or k == "tunnel":
			x *= 0.6 + 0.8 * d
		elif k == "flat":
			x *= 1.3 - 0.7 * d
		wl[k] = maxf(x, 0.0)
		total += wl[k]
	if total <= 0.0:
		return "rush"
	var r := _rng.randf() * total
	for k in wl:
		r -= float(wl[k])
		if r <= 0.0:
			return String(k)
	return "rush"


func _pick_zone(j: int) -> String:
	if j < 3:
		return "rush"
	var excl: Array = ["air"] if _last_air else []
	return _pick_zone_w(excl, _course_diff(-ROW_GAP * float(j)))


## Each gate of a barrier leads to a different kind of stretch (as far as there are kinds to go round).
func _assign_leads(row: Dictionary, gaps: Array, rz: float) -> void:
	var used: Array = []
	var d := _course_diff(rz)
	var allow_air := rz - 2.0 * ROW_GAP > finish_z + 300.0 and int(row["j"]) >= START_CALM
	for g in gaps:
		var excl: Array = used.duplicate()
		if not allow_air:
			excl.append("air")
		var zn := _pick_zone_w(excl, d)
		g["leads"] = zn
		used.append(zn)
		if zn == "bend":
			g["bend"] = 1.0 if float(g["x"]) < 0.0 else -1.0          # the bend turns toward the middle of the slope


func _pick_for_gate(zone: String) -> String:
	var tbl: Dictionary = FOOD_BY_ZONE.get(zone, FOOD_BY_ZONE["rush"])
	var r := _rng.randf()
	for k in tbl:
		r -= float(tbl[k])
		if r <= 0.0:
			return String(k)
	return "boost"


## The sign above a gate: a coloured beacon you can see from afar and a symbol for the kind of stretch it leads to.
## A stone archway as one mesh: a half ring of rectangular section (inner radius r_in, outer radius r_out, depth along the direction of travel), cached by size.
var _arch_cache: Dictionary = {}


func _arch_mesh(r_in: float, r_out: float, depth: float) -> ArrayMesh:
	var key := "%.1f_%.1f_%.1f" % [r_in, r_out, depth]
	if _arch_cache.has(key):
		return _arch_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var hz := depth * 0.5
	for i in n:
		var a0 := PI * float(i) / float(n)
		var a1 := PI * float(i + 1) / float(n)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var o0f := Vector3(c0.x * r_out, c0.y * r_out, hz)
		var o1f := Vector3(c1.x * r_out, c1.y * r_out, hz)
		var i0f := Vector3(c0.x * r_in, c0.y * r_in, hz)
		var i1f := Vector3(c1.x * r_in, c1.y * r_in, hz)
		var o0b := Vector3(o0f.x, o0f.y, -hz)
		var o1b := Vector3(o1f.x, o1f.y, -hz)
		var i0b := Vector3(i0f.x, i0f.y, -hz)
		var i1b := Vector3(i1f.x, i1f.y, -hz)
		for q in [[i0f, i1f, o1f, o0f], [o0b, o1b, i1b, i0b], [o0f, o1f, o1b, o0b], [i0b, i1b, i1f, i0f]]:
			var qa: Vector3 = q[0]
			var qb: Vector3 = q[1]
			var qc: Vector3 = q[2]
			var qd: Vector3 = q[3]
			st.add_vertex(qa)
			st.add_vertex(qb)
			st.add_vertex(qc)
			st.add_vertex(qa)
			st.add_vertex(qc)
			st.add_vertex(qd)
	st.generate_normals()
	var m := st.commit()
	_arch_cache[key] = m
	return m


var _gate_mats: Dictionary = {}


## The three materials a gate is built from. Lit, so the sun and the caves shade them, with a little glow of their own so they still read as marble, gold and oak in the dark.
func _gate_mat(kind: String) -> StandardMaterial3D:
	if _gate_mats.has(kind):
		return _gate_mats[kind]
	var m := Mats.lit()
	match kind:
		"marble":
			m.albedo_color = Color(0.93, 0.91, 0.86)
			m.roughness = 0.28
			m.metallic_specular = 0.7
			m.emission = Color(0.93, 0.9, 0.84)
			m.emission_energy_multiplier = 0.22
		"gold":
			m.albedo_color = Color(1.0, 0.76, 0.22)
			m.metallic = 0.85
			m.roughness = 0.25
			m.emission = Color(1.0, 0.7, 0.15)
			m.emission_energy_multiplier = 0.55
		"oak":
			m.albedo_color = Color(0.42, 0.25, 0.11)
			m.roughness = 0.75
			m.metallic_specular = 0.25
			m.emission = Color(0.42, 0.24, 0.1)
			m.emission_energy_multiplier = 0.25
		_:
			m.albedo_color = Color(0.5, 0.3, 0.13)
			m.roughness = 0.6
			m.emission = Color(0.75, 0.48, 0.2)
			m.emission_energy_multiplier = 0.6
	_gate_mats[kind] = m
	return m


func _make_signs(row: Dictionary, rz: float) -> void:
	for g in row["gaps"]:
		var zn: String = g.get("leads", "rush")
		var zp: Dictionary = ZONES[zn]
		var col: Color = zp.get("scol", zp["col"])
		var gx: float = g["x"]
		var root := Node3D.new()
		add_child(root)
		_place(root, Vector3(gx, terrain_h(gx, rz) + 9.5, rz + 0.5))
		(row["nodes"] as Array).append(root)
		var mat := _fx_mat("solid", col, 2.4)
		var vk := 1.3 if Game.touch_mode else 1.0                       # a phone screen is small: everything about a gate is drawn bigger
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7 * vk
		cm.bottom_radius = 1.5 * vk
		cm.height = 120.0
		cm.radial_segments = 8
		_mi(root, cm, _fx_mat("add", Color(0.55, 0.95, 1.0, 0.32)), Vector3(0, 50.0, 0))
		# A REGAL GATE: two fluted marble columns on stepped gold plinths with gold capitals, an oak beam with a gold band laid across them, and above it an oak arch with a
		# gold keystone. Tall enough to stand clear of the trees, so an opening reads as a gateway from the far end of the stretch.
		var gw: float = float(g.get("w", 10.0))
		var half_open: float = gw * 0.5 + 1.0
		var spring: float = 20.0 * (1.1 if Game.touch_mode else 1.0)          # column height: well above the trees (about 7 m), so a gate is a landmark
		var marble := _gate_mat("marble")
		var gold := _gate_mat("gold")
		var oak := _gate_mat("oak")
		var gy_mid: float = terrain_h(gx, rz)
		var top_y: float = gy_mid + spring
		for psx in [-1.0, 1.0]:
			var ppx: float = gx + float(psx) * (half_open + 2.0)
			var gy: float = terrain_h(ppx, rz) - 0.6
			for step in 3:                                                   # stepped plinth, widest at the ground
				var pl := BoxMesh.new()
				var pw := 6.6 - 1.0 * float(step)
				pl.size = Vector3(pw, 0.7, pw)
				(row["nodes"] as Array).append(_mi(self, pl, gold if step == 2 else marble, Vector3(ppx, gy + 0.35 + 0.7 * float(step), rz)))
			var shaft_h: float = top_y - (gy + 2.1)
			var shaft := CylinderMesh.new()
			shaft.top_radius = 1.2 * 1.5
			shaft.bottom_radius = 2.15
			shaft.height = shaft_h
			shaft.radial_segments = 12
			(row["nodes"] as Array).append(_mi(self, shaft, marble, Vector3(ppx, gy + 2.1 + shaft_h * 0.5, rz)))
			for band in [0.08, 0.92]:                                        # gold rings near the foot and the head of the shaft
				var ring := CylinderMesh.new()
				ring.top_radius = 2.35
				ring.bottom_radius = 2.35
				ring.height = 0.7
				ring.radial_segments = 12
				(row["nodes"] as Array).append(_mi(self, ring, gold, Vector3(ppx, gy + 2.1 + shaft_h * float(band), rz)))
			var cap := BoxMesh.new()
			cap.size = Vector3(6.0, 1.3, 6.0)
			(row["nodes"] as Array).append(_mi(self, cap, gold, Vector3(ppx, top_y + 0.65, rz)))
		var beam := BoxMesh.new()                                         # the oak beam across the two columns
		beam.size = Vector3(2.0 * (half_open + 2.0) + 7.6, 2.6, 4.2)
		(row["nodes"] as Array).append(_mi(self, beam, oak, Vector3(gx, top_y + 2.6, rz)))
		var trim := BoxMesh.new()
		trim.size = Vector3(beam.size.x + 0.8, 0.55, 4.7)
		(row["nodes"] as Array).append(_mi(self, trim, gold, Vector3(gx, top_y + 4.15, rz)))
		var key := PrismMesh.new()                                        # the keystone
		key.size = Vector3(3.6, 4.0, 4.6)
		var kn := _mi(self, key, gold, Vector3(gx, top_y + 2.4, rz))
		kn.rotation.z = PI
		(row["nodes"] as Array).append(kn)
		var arch_y: float = top_y + 4.4
		var arch_mat := (_gate_mat("oak_glow") as StandardMaterial3D).duplicate() as StandardMaterial3D          # its own material: the arch turns gold when it holds the next step of the chain
		var arch := _mi(self, _arch_mesh(half_open + 0.2, half_open + 3.2 * vk, 3.6 * vk), arch_mat, Vector3(gx, arch_y, rz))
		(row["nodes"] as Array).append(arch)
		g["arch_mat"] = arch_mat
		g["arch_col"] = arch_mat.albedo_color
		var offer := ""
		for bb in row["buffs"]:
			var bkind := String(bb.get("kind", ""))
			if (bkind == "safe" or bkind == "gate") and absf(float(bb["x"]) - gx) < 3.0 and float(bb["z"]) >= rz - 1.0 and float(bb["z"]) < rz + 90.0:
				offer = String(bb["t"])
				break
		g["offer"] = offer
		if offer != "" and BUFF_COL.has(offer):
			var gem := PrismMesh.new()
			gem.size = Vector3(2.4 * vk, 3.2 * vk, 2.4 * vk)
			var gc: Color = BUFF_COL[offer]
			var gm := _fx_mat("solid", gc, 3.4)
			(row["nodes"] as Array).append(_mi(self, gem, gm, Vector3(gx, arch_y + half_open + 2.4, rz)))
		var sm := BoxMesh.new()
		sm.size = Vector3(gw, 0.2, 1.4)
		(row["nodes"] as Array).append(_mi(self, sm, _fx_mat("add", Color(col.r, col.g, col.b, 0.75)), Vector3(gx, terrain_h(gx, rz) + 0.2, rz)))
		match zn:
			"rush":
				for vi in 2:
					for sx in [-1.0, 1.0]:
						var bm := BoxMesh.new()
						bm.size = Vector3(1.7, 0.38, 0.3)
						var b := _mi(root, bm, mat, Vector3(float(sx) * 0.72, 0.5 - float(vi) * 1.15, 0.0))
						b.rotation.z = -float(sx) * 0.55
			"flat":
				var tm := TorusMesh.new()
				tm.inner_radius = 0.85
				tm.outer_radius = 1.3
				var t := _mi(root, tm, mat)
				t.rotation.x = PI * 0.5
				t.scale = Vector3(1.6, 1.0, 0.8)
			"tunnel":
				for ri in 2:
					var tm2 := TorusMesh.new()
					tm2.inner_radius = 0.9 - 0.45 * float(ri)
					tm2.outer_radius = 1.35 - 0.6 * float(ri)
					var t2 := _mi(root, tm2, mat)
					t2.rotation.x = PI * 0.5
			"bend":
				var side: float = float(g.get("bend", 1.0))
				var vb := BoxMesh.new()
				vb.size = Vector3(0.38, 1.9, 0.3)
				_mi(root, vb, mat, Vector3(0, -0.5, 0))
				var hb := BoxMesh.new()
				hb.size = Vector3(1.6, 0.38, 0.3)
				_mi(root, hb, mat, Vector3(side * 0.8, 0.45, 0))
				var ab := BoxMesh.new()
				ab.size = Vector3(0.8, 0.38, 0.3)
				var a := _mi(root, ab, mat, Vector3(side * 1.55, 0.25, 0))
				a.rotation.z = -side * 0.8
			"forest":
				for fi in 2:
					var fp := PrismMesh.new()
					fp.size = Vector3(2.0 - 0.5 * float(fi), 1.1, 0.35)
					_mi(root, fp, mat, Vector3(0, 0.55 - 0.9 * float(fi) * -1.0 - 0.9, 0))
			"drop":
				for di in 3:
					var db := BoxMesh.new()
					db.size = Vector3(1.5, 0.34, 0.3)
					for dsx in [-1.0, 1.0]:
						var dn := _mi(root, db, mat, Vector3(float(dsx) * 0.62, 0.9 - float(di) * 0.8, 0.0))
						dn.rotation.z = float(dsx) * 0.55
			"highway":
				var hd := PrismMesh.new()
				hd.size = Vector3(1.8, 1.8, 0.3)
				var hn := _mi(root, hd, mat)
				hn.rotation.z = PI
				_mi(root, hd, mat, Vector3(0, 1.2, 0))
			"interzone":
				for ik in 2:
					var ib := BoxMesh.new()
					ib.size = Vector3(1.0, 1.0, 0.3)
					_mi(root, ib, mat, Vector3(-0.55 + 1.1 * float(ik), 0.5 - 1.0 * float(ik), 0.0))
			"hive":
				for hk in 3:
					var hb := BoxMesh.new()
					hb.size = Vector3(2.4 - 0.7 * float(hk), 0.28, 0.3)
					_mi(root, hb, mat, Vector3(0, 0.9 - 0.7 * float(hk), 0.0))
			"eyes":
				var et := TorusMesh.new()
				et.inner_radius = 0.7
				et.outer_radius = 1.2
				var en := _mi(root, et, mat)
				en.rotation.x = PI * 0.5
				var es := SphereMesh.new()
				es.radius = 0.4
				es.height = 0.8
				_mi(root, es, mat)
			"melt":
				for mk in 3:
					var ms := SphereMesh.new()
					ms.radius = 0.75 - 0.2 * float(mk)
					ms.height = ms.radius * 2.0
					_mi(root, ms, mat, Vector3(0.12 * float(mk), 0.9 - 0.9 * float(mk), 0.0))
			"glowcave":
				for gk in 2:
					var gs := SphereMesh.new()
					gs.radius = 0.7 - 0.25 * float(gk)
					gs.height = gs.radius * 2.0
					_mi(root, gs, mat, Vector3(0.0, 0.5 - 0.9 * float(gk), 0.0))
				var gr := TorusMesh.new()
				gr.inner_radius = 0.9
				gr.outer_radius = 1.2
				var gn := _mi(root, gr, mat)
				gn.rotation.x = PI * 0.5
			"crystal":
				var cp := PrismMesh.new()
				cp.size = Vector3(1.0, 2.2, 0.3)
				_mi(root, cp, mat, Vector3(0, 0.3, 0))
				var cp2 := PrismMesh.new()
				cp2.size = Vector3(1.0, 2.2, 0.3)
				var cn2 := _mi(root, cp2, mat, Vector3(0, -0.8, 0))
				cn2.rotation.z = PI
			"lava":
				var lb := BoxMesh.new()
				lb.size = Vector3(0.3, 2.0, 0.3)
				_mi(root, lb, mat, Vector3(-0.45, 0.0, 0))
				_mi(root, lb, mat, Vector3(0.45, 0.0, 0))
				var lt := BoxMesh.new()
				lt.size = Vector3(1.4, 0.3, 0.3)
				_mi(root, lt, mat, Vector3(0, 0.95, 0))
			"abyss":
				var aj := SphereMesh.new()
				aj.radius = 0.8
				aj.height = 0.9
				_mi(root, aj, mat, Vector3(0, 0.6, 0))
				for ab in 3:
					var at := BoxMesh.new()
					at.size = Vector3(0.12, 1.2, 0.12)
					_mi(root, at, mat, Vector3(-0.4 + 0.4 * float(ab), -0.5, 0))
			"mandala":
				for ak in 6:
					var ab2 := BoxMesh.new()
					ab2.size = Vector3(0.3, 1.5, 0.3)
					var an := _mi(root, ab2, mat)
					an.rotation.z = float(ak) * PI / 6.0
			_:
				var pm := PrismMesh.new()
				pm.size = Vector3(2.4, 1.5, 0.4)
				_mi(root, pm, mat)
		var halo := _mi(root, _quad(5.0), _fx_mat("halo", Color(col.r, col.g, col.b, 0.7)))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A line of trees down both sides of the stretch (a corridor that follows the safe line), and in a tunnel two hoops to thread.
func _build_corridor(row: Dictionary, zone: String, halfw: float, prev_rz: float, rz: float, cones: Array[Transform3D], cone_cols: PackedColorArray, trunks: Array[Transform3D], trunk_cols: PackedColorArray, obs: PackedFloat32Array) -> void:
	var z := prev_rz - 8.0
	while z > rz + 6.0:
		var cx := path_x(row, z)
		for sd in [-1.0, 1.0]:
			var x: float = cx + float(sd) * halfw + _rng.randf_range(-0.5, 0.5)
			if z < rz + 48.0 and _near_gap(row, x, 5.0):
				continue                                          # the walls open up in front of every gate, so a way out is never hidden behind a tree
			if absf(x) < W_HALF - 1.0:
				_add_tree(cones, cone_cols, trunks, trunk_cols, obs, x, z + _rng.randf_range(-0.6, 0.6), _rng.randf_range(0.9, 1.3), true)
		z -= 3.7
	if zone == "tunnel" or zone == "hive":
		for hk in [1, 2]:
			var hz := rz + 26.0 * float(hk)
			if hz > prev_rz - 24.0:
				continue
			var hc := path_x(row, hz) + _rng.randf_range(-3.0, 3.0)
			var hx := path_x(row, hz) - halfw
			while hx < path_x(row, hz) + halfw:
				if absf(hx - hc) > 9.0 + 1.6 and absf(hx) < W_HALF - 1.0:
					_add_tree(cones, cone_cols, trunks, trunk_cols, obs, hx, hz + _rng.randf_range(-0.5, 0.5), _rng.randf_range(0.9, 1.2), true)
				hx += 3.7


# --------------------------------------------------------------------------
# Realms (Realms.gd): what is built there and what the rule is. Props go into buckets while a stretch is generated, then one multimesh per kind.
# --------------------------------------------------------------------------
var _zone_by_j: Dictionary = {}
var _rp: Dictionary = {}
var _row_eyes: Array = []
var _eye_count: int = 0
var _grip_mul: float = 1.0
var _drag_mul: float = 1.0
var weird: float = 1.0                  # how many of the strange places (Realms.gd) the gates lead to
var _gen_z0: float = 0.0
var _gen_lip: bool = true
var _reveal_j: int = -1
var _force_realm: String = ""
var _realm_now: String = ""
var _cut_z: float = 0.0
var _cut_dx: float = 0.0


func _zone_at(z: float) -> String:
	return String(_zone_by_j.get(int(floor(-z / ROW_GAP)), ""))


func _chunk_post(j: int, mi: MeshInstance3D) -> void:
	if Realms.is_realm(String(_zone_by_j.get(j, ""))):
		mi.material_override = Realms.ground_material()          # a realm has its own ground, whatever theme is on


func _ground_color(j: int, x: float, z: float, c: Color) -> Color:
	if trail:
		for kk in _kickers:
			var kzz: float = kk["z"]
			if z > kzz + 3.0 or z < kzz - float(kk["len"]) - 3.0:
				continue
			var hw: float = float(kk["w"]) * 0.5
			var ax := absf(x - float(kk["x"]))
			if ax > hw + 2.5:
				continue
			var ku := clampf((kzz - z) / float(kk["len"]), 0.0, 1.0)
			var ramp_col := Color(1.0, 0.92, 0.45).lerp(Color(1.0, 0.45, 0.12), ku).lerp(Color(0.95, 0.2, 0.75), smoothstep(hw - 2.0, hw + 1.0, ax) * 0.8)
			c = c.lerp(ramp_col, 0.9 * (1.0 - smoothstep(hw, hw + 2.5, ax)))
	var zn := String(_zone_by_j.get(j, ""))
	if Realms.is_realm(zn):
		return Realms.ground(zn, x, z, -ROW_GAP * (float(j) + 0.5), c)
	return c


func _add_tree(cones: Array[Transform3D], cone_cols: PackedColorArray, trunks: Array[Transform3D], trunk_cols: PackedColorArray,
		obs: PackedFloat32Array, x: float, z: float, s: float, solid: bool) -> void:
	if Realms.is_realm(_cur_zone):
		_realm_prop(x, z, s, solid, obs)
		return
	super._add_tree(cones, cone_cols, trunks, trunk_cols, obs, x, z, s, solid)


func _add_rock(rocks: Array[Transform3D], cols: PackedColorArray, obs: PackedFloat32Array, x: float, z: float, s: float, c: Color, tall: float, solid: bool = true) -> void:
	if Realms.is_realm(_cur_zone):
		_realm_prop(x, z, s, solid, obs)
		return
	super._add_rock(rocks, cols, obs, x, z, s, c, tall, solid)


func _rp_add(id: String, x: float, z: float, sc: float, yaw: float, vy: float, y_abs: float = NAN) -> void:
	if not _rp.has(id):
		_rp[id] = {"xf": [], "col": []}
	var d: Dictionary = _rp[id]
	var y := terrain_h(x, z) if is_nan(y_abs) else y_abs
	(d["xf"] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * vy, sc)), Vector3(x, y, z)))
	(d["col"] as Array).append(Realms.tint(_cur_zone, _rng))


## Height of the roof above the ground at a point in a roofed realm: a low mouth at the start, then a tall cavern that closes in at the sides of the valley.
func _roof_y(x: float, z: float, z0: float, lip: bool) -> float:
	var e := sqrt(maxf(1.0 - (x / 145.0) * (x / 145.0), 0.0))
	var n := 0.5 + 0.5 * sin(x * 0.09 + z * 0.05) * sin(z * 0.043 - x * 0.03)
	var k := (0.18 + 0.82 * smoothstep(0.0, 40.0, z0 - z)) if lip else 1.0
	return terrain_h(x, z) + (4.0 + (24.0 + 8.0 * n) * e) * k


func _realm_prop(x: float, z: float, s: float, solid: bool, obs: PackedFloat32Array) -> void:
	var id := Realms.pick(_cur_zone, not solid, _rng)
	var sc := s if solid else clampf(s * 0.2, 1.0, 2.6)
	if _cur_zone == "mammoth":
		sc *= 2.2 if not solid else 1.5                          # strange mammoth plants
	if Realms.has_roof(_cur_zone):
		var into := _gen_z0 - z                                   # metres into this stretch
		if not solid and into < 42.0 and id != "stalag":
			return                                                # the first stretch of a cave is dark and bare: the lights come on later
		if not solid and (id == "glowshroom" or id == "coral" or id == "crystal"):
			sc *= 1.6                                             # mammoth
		if Realms.HANGING.has(id):
			_rp_add(id, x, z, sc, _rng.randf() * TAU, 1.0, _roof_y(x, z, _gen_z0, _gen_lip))
			return
		if Realms.FLOATING.has(id):
			_rp_add(id, x, z, sc, _rng.randf() * TAU, 1.0, terrain_h(x, z) + _rng.randf_range(-1.0, 8.0))
			return
	if id == "eyeball" and solid:
		if _eye_count < 7:
			_make_watcher(x, z, sc, obs)
			return
		id = "stalk"
	var yaw := 0.0 if Realms.FACING.has(id) else _rng.randf() * TAU
	_rp_add(id, x, z, sc, yaw, _rng.randf_range(0.9, 1.3))
	if solid:
		obs.append(x)
		obs.append(z)
		obs.append(Realms.radius(id) * sc)
		obs.append(1.0 if (id == "blob" or id == "mush") else 0.0)
	_push_shadow(x, z, 6.0 * sc, 2.4 * sc)


## A giant eye on a stalk: a real node, because its iris follows you. Look toward it and hold and it blinks shut, and lets you through.
func _make_watcher(x: float, z: float, sc: float, obs: PackedFloat32Array) -> void:
	var root := Node3D.new()
	add_child(root)
	_place(root, Vector3(x, terrain_h(x, z), z))
	root.scale = Vector3.ONE * sc
	var mat := Realms.material("eyes")
	var body := MeshInstance3D.new()
	body.mesh = Realms.mesh("eyeball")
	body.material_override = mat
	root.add_child(body)
	var iris := MeshInstance3D.new()
	iris.mesh = Realms.mesh("iris")
	iris.material_override = mat
	root.add_child(iris)
	iris.position = Vector3(0, 7.0, 1.8)
	var oi := obs.size()
	obs.append(x)
	obs.append(z)
	obs.append(Realms.radius("eyeball") * sc)
	obs.append(0.0)
	_push_shadow(x, z, 6.0 * sc, 2.4 * sc)
	_row_eyes.append({"root": root, "iris": iris, "x": x, "z": z, "sc": sc, "oi": oi, "t": 0.0, "seen": false, "c": 0.0})
	_eye_count += 1


## The roof of a cave: one cheap lumpy sheet over the whole stretch, closing down to the valley walls at the sides.
func _build_roof(row: Dictionary, zone: String, z0: float) -> void:
	const NXR := 26
	const NZR := 12
	var base: Color = (Realms.ROOF[zone] as Dictionary)["col"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for iz in NZR + 1:
		var z := z0 - ROW_GAP * float(iz) / float(NZR)
		for ix in NXR + 1:
			var x := -145.0 + 290.0 * float(ix) / float(NXR)
			verts.append(W(Vector3(x, _roof_y(x, z, z0, _gen_lip), z)))
			norms.append(Vector3(0.0, -1.0, 0.0))
			var n := 0.5 + 0.5 * sin(x * 0.21 + z * 0.17) * sin(z * 0.13 - x * 0.11)
			cols.append(base.lerp(base * 1.8, n))
	for iz in NZR:
		for ix in NXR:
			var a := iz * (NXR + 1) + ix
			idx.append_array(PackedInt32Array([a, a + 1, a + NXR + 1, a + 1, a + NXR + 2, a + NXR + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Realms.material(zone)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 60.0
	add_child(mi)
	(row["nodes"] as Array).append(mi)


func _flush_realm(row: Dictionary, zone: String, j: int, z0: float) -> void:
	if not Realms.is_realm(zone):
		_row_eyes = []
		_eye_count = 0
		return
	if zone == "mandala":
		for k in 3:
			_rp_add("ring", 20.0 * sin(float(j) * 1.9 + float(k) * 2.1), z0 - 14.0 - 26.0 * float(k), 1.5, 0.0, 1.0)
	if Realms.has_roof(zone):
		for k in 16:
			var hx := _rng.randf_range(-70.0, 70.0)
			var hz := z0 - _rng.randf_range(44.0, ROW_GAP)
			_rp_add("stalactite", hx, hz, _rng.randf_range(0.8, 2.2), _rng.randf() * TAU, 1.0, _roof_y(hx, hz, z0, _gen_lip))
		_build_roof(row, zone, z0)
	if not _row_eyes.is_empty():
		row["eyes"] = _row_eyes
		for e in _row_eyes:
			(row["nodes"] as Array).append(e["root"])
	_row_eyes = []
	_eye_count = 0
	for id in _rp:
		var d: Dictionary = _rp[id]
		var xs: Array[Transform3D] = []
		for t in (d["xf"] as Array):
			xs.append(t)
		var cs := PackedColorArray()
		for c in (d["col"] as Array):
			cs.append(c)
		_add_mm(row, Realms.mesh(String(id)), xs, cs, Realms.material(zone))
	_rp.clear()


## Per physics tick: the rule of the realm you are in, the name when you arrive, and the eyes watching you.
func _realm_tick(delta: float) -> void:
	if _cut_dx != 0.0 and spos.z <= _cut_z:
		spos.x = clampf(spos.x + _cut_dx, -(W_HALF - 4.0), W_HALF - 4.0)
		_cut_dx = 0.0
		_toast("CUT-UP", Color(0.98, 0.84, 0.2))
	var zn := _zone_at(spos.z)
	if zn != _realm_now:
		_realm_now = zn
		if Realms.is_realm(zn):
			var nf := Realms.discover(zn)
			realms_seen[zn] = true
			if nf > 0:
				_toast("NEW REALM %d/%d: %s" % [nf, Realms.IDS.size(), Realms.NAMES[zn]], Color(1.0, 0.7, 1.0))
			else:
				_toast(String(Realms.NAMES[zn]), Color(0.95, 0.8, 1.0))
	# darkness inside a roofed realm, and the lights coming on 42 m in
	var roofed := Realms.has_roof(zn)
	if roofed:
		Realms.cave_expo = float((Realms.ROOF[zn] as Dictionary)["expo"])
		var sj := int(floor(-spos.z / ROW_GAP))
		if spos.z <= -ROW_GAP * float(sj) - 42.0 and _reveal_j != sj:
			_reveal_j = sj
			Realms.flash = 1.0
			_toast(String((Realms.ROOF[zn] as Dictionary)["reveal"]), Color(0.9, 1.0, 0.9))
	Realms.cave_k = move_toward(Realms.cave_k, 1.0 if roofed else 0.0, delta * (1.1 if roofed else 0.8))
	Realms.flash = move_toward(Realms.flash, 0.0, delta * 0.7)
	Realms.apply_cave()
	_grip_mul = 1.0
	_drag_mul = 1.0
	match zn:
		"glowcave":
			_drag_mul = 0.92
		"lava":
			_drag_mul = 0.8                                       # hot and fast
		"abyss":
			_drag_mul = 1.25                                      # heavy going
		"highway":
			_grip_mul = 0.5                                       # slick: the board drifts
			_drag_mul = 0.85
		"hive":
			_drag_mul = 1.0 + 0.4 * sin(_age * 5.5)               # the heartbeat: surge, then drag
		"melt":
			_grip_mul = 0.75
	var look := _steer_gaze if _eye_on else steer
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r.has("eyes"):
			continue
		for e in (r["eyes"] as Array):
			var root: Node3D = e["root"]
			if not is_instance_valid(root):
				continue
			var d: float = spos.z - float(e["z"])
			if d < -10.0 or d > 110.0:
				continue
			var sc: float = e["sc"]
			var iris: Node3D = e["iris"]
			var dir := Vector3(spos.x - float(e["x"]), 0.3, maxf(d, 0.0) + 2.0).normalized()
			iris.position = Vector3(0.0, 7.0, 0.0) + dir * 1.8
			iris.basis = Basis.looking_at(-dir, Vector3.UP)
			if bool(e["seen"]):
				e["c"] = minf(float(e["c"]) + delta * 3.0, 1.0)
				root.scale = Vector3(sc, sc * (1.0 - 0.75 * float(e["c"])), sc)
				iris.visible = float(e["c"]) < 0.5
				continue
			var lat := float(e["x"]) - spos.x
			var toward := absf(look) > 0.25 and (signf(lat) == signf(look) or absf(lat) < 5.0)
			e["t"] = clampf(float(e["t"]) + (delta if (d > 4.0 and d < 55.0 and toward) else -delta * 1.5), 0.0, 1.0)
			if float(e["t"]) >= 0.5:
				e["seen"] = true
				var ob: PackedFloat32Array = r["obs"]
				ob[int(e["oi"]) + 2] = 0.0
				_gain(30)
				_toast("SEEN", Color(0.6, 1.0, 0.9))


func _near_gap(row: Dictionary, x: float, pad: float) -> bool:
	for g in row["gaps"]:
		if absf(x - float(g["x"])) < float(g["w"]) * 0.5 + pad:
			return true
	return false


## Lost in a corridor? Glowing breadcrumbs lead from the board to the nearest opening of the next barrier.
var _rib: MeshInstance3D
var _rib_im: ImmediateMesh


## Glowing ribbons on the snow from the board to every opening of the next barrier, in the colour of its sign. The one your eyes have chosen is bright and wide,
## the rest stay faint but visible, so the fork is always there to read: nothing else is drawn on the ground.
func _update_ribbons() -> void:
	if _rib == null:
		_rib_im = ImmediateMesh.new()
		_rib = MeshInstance3D.new()
		_rib.mesh = _rib_im
		var rm := Mats.glass(true)                       # normal blending, not additive: additive washes out to white on bright snow
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.vertex_color_use_as_albedo = true
		rm.no_depth_test = false
		_rib.material_override = rm
		_rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rib.extra_cull_margin = 600.0
		add_child(_rib)
	_rib_im.clear_surfaces()
	if _finished or _in_air or _paused:
		return
	var row: Dictionary = {}
	var bz := -1.0e9
	for j in _rows:
		var r: Dictionary = _rows[j]
		if r["has_row"] and not r["passed"] and float(r["z"]) < spos.z - 10.0 and float(r["z"]) > spos.z - 200.0 and float(r["z"]) > bz:
			bz = float(r["z"])
			row = r
	if row.is_empty():
		return
	var sx := spos.x + vel.x * 0.3
	var sz := spos.z - 8.0
	for g in row["gaps"]:
		var col := Color(0.7, 1.0, 1.0)
		if String(g.get("offer", "")) == _chain_expect_kind():
			col = Color(1.0, 0.82, 0.25)
		var chosen := is_same(g, _aim)
		var a := 0.95 if chosen else (0.7 if _aim.is_empty() else 0.4)
		var w := 1.7 if chosen else 1.1
		var gx: float = g["x"]
		_rib_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var n := 18
		for i in n + 1:
			var u := float(i) / float(n)
			var x := lerpf(sx, gx, u * u * (3.0 - 2.0 * u))
			var z := lerpf(sz, bz, u)
			var al := a * smoothstep(0.0, 0.2, u) * (0.65 + 0.35 * sin(_age * 6.0 - u * 16.0)) * (1.0 + 0.8 * smoothstep(0.85, 1.0, u))
			var ww := w * (0.6 + 0.8 * u)
			var c := Color(col.r, col.g, col.b, clampf(al, 0.0, 1.0))
			_rib_im.surface_set_color(c)
			_rib_im.surface_add_vertex(W(Vector3(x - ww, terrain_h(x - ww, z) + 0.25, z)))
			_rib_im.surface_set_color(c)
			_rib_im.surface_add_vertex(W(Vector3(x + ww, terrain_h(x + ww, z) + 0.25, z)))
		_rib_im.surface_end()


func _update_crumbs(delta: float) -> void:
	var row: Dictionary = {}
	var bz := -1.0e9
	for j in _rows:
		var r: Dictionary = _rows[j]
		if r["has_row"] and float(r["z"]) < spos.z - 12.0 and float(r["z"]) > bz and float(r["z"]) > spos.z - 160.0:
			bz = float(r["z"])
			row = r
	var gap := {}
	var gd := 1.0e9
	if not row.is_empty() and not _in_air:
		for g in row["gaps"]:
			if absf(float(g["x"]) - spos.x) < gd:
				gd = absf(float(g["x"]) - spos.x)
				gap = g
	var lost := not gap.is_empty() and gd > 11.0
	_crumb_a = move_toward(_crumb_a, 1.0 if lost else 0.0, delta * 2.5)
	if _crumbs.is_empty():
		var dm := CylinderMesh.new()
		dm.top_radius = 0.9
		dm.bottom_radius = 0.9
		dm.height = 0.08
		var cmat := _fx_mat("add", Color(1.0, 1.0, 1.0, 0.8))
		for ci in 14:
			var cn := _mi(self, dm, cmat)
			cn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cn.visible = false
			_crumbs.append(cn)
	for ci2 in _crumbs.size():
		var cn2: MeshInstance3D = _crumbs[ci2]
		if _crumb_a <= 0.02 or gap.is_empty():
			cn2.visible = false
			continue
		var u := float(ci2 + 1) / float(_crumbs.size())
		var cz := lerpf(spos.z - 6.0, bz, u)
		var cx := lerpf(spos.x, float(gap["x"]), u * u * (3.0 - 2.0 * u))
		cn2.visible = true
		_place(cn2, Vector3(cx, terrain_h(cx, cz) + 0.3, cz))
		var wave := 0.5 + 0.5 * sin(_age * 7.0 - float(ci2) * 0.9)
		cn2.scale = Vector3.ONE * (0.5 + 0.9 * wave) * _crumb_a


func _update_mist(z_end: float) -> void:
	if _mist == null:
		_mist = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(560.0, 160.0)
		_mist.mesh = q
		var m := ShaderMaterial.new()
		m.shader = Mats.shader("shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(0.93, 0.96, 1.0, 0.97);
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a * smoothstep(0.22, 0.62, UV.y); }
")
		_mist.material_override = m
		_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mist)
	(_mist.material_override as ShaderMaterial).set_shader_parameter("tint", mist_color)
	_wset(_mist, Vector3(0.0, terrain_h(0.0, z_end) + 50.0, z_end))
	_mist.global_transform.basis = TrailCurve.basis_at(z_end)


## Spread layout for a meadow: several wide gates across the whole slope.
func _layout_spread(gaps: Array, gx: float, d: float, want: int) -> void:
	var slots: Array = [-36.0, -12.0, 12.0, 36.0]
	slots.shuffle()
	var added := 0
	for sx in slots:
		if added >= want:
			break
		var ok := absf(float(sx) - gx) >= 18.0
		for g in gaps:
			if absf(float(sx) - float(g["x"])) < 18.0:
				ok = false
		if ok:
			_add_gate(gaps, float(sx) + _rng.randf_range(-3.0, 3.0), _gate_w(d), false)
			added += 1


## A tunnel or a bend: the second gate sits close by, so the choice is quick.
func _layout_near(gaps: Array, gx: float, d: float, lo: float, hi: float) -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var ex := gx + side * _rng.randf_range(lo, hi)
	if absf(ex) > 44.0:
		ex = gx - side * _rng.randf_range(lo, hi)
	if absf(ex) <= 44.0:
		_add_gate(gaps, ex, _gate_w(d), false)


# --------------------------------------------------------------------------
# Parameters and presets. Every course is generated from these, so any setting makes a different run, and length 0 never ends.
#   ?preset=alpine|meadow|canyon|chaos|endless   ?seed=123   ?len=0 (metres, 0 = endless)   ?diff=1.3   ?zones=rush:2,flat:0.5,tunnel:1,bend:1,air:0.5
# N cycles the presets in the game.
# --------------------------------------------------------------------------
const PRESETS := {
	"classic": {},
	"alpine": {"zones": {"rush": 2.0, "flat": 0.4, "tunnel": 0.6, "bend": 0.6, "air": 0.8}, "diff": 1.1},
	"meadow": {"zones": {"rush": 0.5, "flat": 2.0, "tunnel": 0.2, "bend": 0.3, "air": 0.6}, "diff": 0.7},
	"canyon": {"zones": {"rush": 0.6, "flat": 0.3, "tunnel": 2.0, "bend": 1.8, "air": 0.3}, "diff": 1.2},
	"chaos": {"zones": {"rush": 1.0, "flat": 0.6, "tunnel": 0.8, "bend": 0.8, "air": 2.0}, "diff": 1.3},
	"endless": {"length": 0},
}
const PRESET_ORDER := ["classic", "alpine", "meadow", "canyon", "chaos", "endless"]


func apply_params(d: Dictionary) -> void:
	params = {"seed": int(params.get("seed", 424242)), "length": 4200, "diff": 1.0, "zones": {}, "lazy": true}
	for k in d:
		params[k] = d[k]
	var ln := float(params.get("length", 4200))
	finish_z = -ln if ln > 0.0 else -1.0e7
	diff_scale = float(params.get("diff", 1.0))


func apply_preset(name: String) -> void:
	apply_params(PRESETS.get(name, {}))
	_preset_i = maxi(PRESET_ORDER.find(name), 0)


func cycle_preset() -> void:
	_preset_i = (_preset_i + 1) % PRESET_ORDER.size()
	var nm: String = PRESET_ORDER[_preset_i]
	apply_preset(nm)
	_restart()
	_toast("COURSE: " + nm.to_upper(), Color(1.0, 0.9, 0.5))


func _read_params() -> void:
	if not OS.has_feature("web"):
		return
	var q := func(key: String) -> String:
		return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % key))
	var d: Dictionary = {}
	var pr: String = q.call("preset")
	if PRESETS.has(pr):
		d = (PRESETS[pr] as Dictionary).duplicate(true)
		_preset_i = maxi(PRESET_ORDER.find(pr), 0)
	var sd: String = q.call("seed")
	if sd != "":
		params["seed"] = int(sd)
	var ln: String = q.call("len")
	if ln != "":
		d["length"] = float(ln)
	var df: String = q.call("diff")
	if df != "":
		d["diff"] = clampf(float(df), 0.3, 2.0)
	var rlm: String = q.call("realm")
	if Realms.is_realm(rlm) or rlm == "all":
		_force_realm = rlm                                       # ?realm=hive : nothing but that realm (for looking at one); ?realm=all : realms only
	var zs: String = q.call("zones")
	if zs != "":
		var zd: Dictionary = {}
		for part in zs.split(","):
			var kv := part.split(":")
			if kv.size() == 2 and ZONES.has(kv[0]):
				zd[kv[0]] = float(kv[1])
		d["zones"] = zd
	apply_params(d)


# --------------------------------------------------------------------------
# Gate layouts: a barrier is one of several shapes, so reading the slope pays off.
#   scatter  the safe gate plus 0-2 gates at random places (the original)
#   pair     two gates a carve apart
#   trio     three gates evenly spaced across the slope
#   decoy    the safe gate plus one isolated, narrower gate far to the side that carries a better buff
# The safe gate never moves faster than a carve can follow; an isolated gate is only placed where it can be reached from the last barrier.
# --------------------------------------------------------------------------
func _gate_w(d: float) -> float:
	return lerpf(15.0, 9.0, d) * _rng.randf_range(0.92, 1.1) * _zone_w


func _add_gate(gaps: Array, x: float, w: float, iso: bool) -> void:
	var ge := _mk_gap(x, w, "open", false)
	ge["lane"] = -1
	ge["iso"] = iso
	gaps.append(ge)


func _layout_gaps(row: Dictionary, gaps: Array, d: float, prev_x: float, prev_rz: float, rz: float) -> void:
	var gx := _good_x
	if _cur_zone == "flat":
		_layout_spread(gaps, gx, d, 2 + (1 if _rng.randf() < 0.5 else 0))
		row["layout"] = "spread"
		return
	if _cur_zone == "tunnel" or _cur_zone == "bend" or _cur_zone == "hive":
		_layout_near(gaps, gx, d, 9.0 if _cur_zone != "bend" else 12.0, 14.0 if _cur_zone != "bend" else 18.0)
		row["layout"] = "near"
		return
	var roll := _rng.randf()
	var layout := "scatter"
	if roll >= 0.26:
		layout = "pair" if roll < 0.48 else ("trio" if roll < 0.74 else "decoy")
	if layout == "trio":
		var sp := _rng.randf_range(27.0, 32.0)
		# evenly spaced, with the safe gate at either end or in the middle, whichever keeps all three on the slope
		var steps: Array = [-1.0, 1.0]
		if gx + sp > 46.0:
			steps = [-1.0, -2.0]
		elif gx - sp < -46.0:
			steps = [1.0, 2.0]
		for sg in steps:
			var ex: float = gx + float(sg) * sp
			if absf(ex) <= 46.0:
				_add_gate(gaps, ex, _gate_w(d), false)
		if gaps.size() < 3:
			layout = "pair"
	if layout == "pair" and gaps.size() < 2:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var ex2 := gx + side * _rng.randf_range(24.0, 30.0)
		if absf(ex2) > 46.0:
			ex2 = gx - side * _rng.randf_range(24.0, 30.0)
		if absf(ex2) <= 46.0:
			_add_gate(gaps, ex2, _gate_w(d), false)
		else:
			layout = "scatter"
	if layout == "decoy":
		var pref := 1.0 if prev_x >= gx else -1.0              # off toward where you came from: far from the safe gate, still within a carve's reach
		if absf(prev_x - gx) < 6.0 and _rng.randf() < 0.5:
			pref = -pref
		var placed := false
		for sd in [pref, -pref]:
			var ex3 := clampf(gx + float(sd) * _rng.randf_range(26.0, 34.0), -46.0, 46.0)
			if absf(ex3 - gx) >= 24.0 and absf(ex3 - prev_x) <= 0.33 * (prev_rz - rz):
				_add_gate(gaps, ex3, lerpf(13.0, 8.0, d) * _rng.randf_range(0.92, 1.1), true)
				placed = true
				break
		if not placed:
			layout = "scatter"
	if layout == "scatter":
		var extra := (1 if _rng.randf() < 0.55 + 0.3 * d else 0) + (1 if d > 0.5 and _rng.randf() < 0.5 else 0)
		for e in extra:
			for attempt in 10:
				var ex4 := _rng.randf_range(-46.0, 46.0)
				var ew := _gate_w(d)
				var ok := true
				for g in gaps:
					if absf(ex4 - float(g["x"])) < (float(g["w"]) + ew) * 0.5 + 9.0:
						ok = false
				if ok:
					_add_gate(gaps, ex4, ew, false)
					break
	if gaps.size() < 2:
		# a barrier is always a choice: never a single door
		var sd2 := -signf(gx) if absf(gx) > 12.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
		var ex5 := clampf(gx + sd2 * _rng.randf_range(22.0, 30.0), -46.0, 46.0)
		if absf(ex5 - gx) < 18.0:
			ex5 = clampf(gx - sd2 * _rng.randf_range(22.0, 30.0), -46.0, 46.0)
		_add_gate(gaps, ex5, _gate_w(d), false)
		layout = "pair"
	row["layout"] = layout


# --------------------------------------------------------------------------
# Buffs: the things worth looking at.
#   boost   a burst of speed and less drag for a few seconds (faster is harder to steer)
#   shield  absorbs the next crash
#   mult    double points for 10 s
# They sit in two kinds of place: in front of an opening (always the isolated one, sometimes the others), on a short lead-in trail of
# small orbs; and out beside the safe line between two barriers, on a curved trail, so you have to want it and look there.
# Look at one for a moment and the board leans toward it (like an opening); the avoidance still keeps you off the trees.
# --------------------------------------------------------------------------
const BOOST_S := 3.0
const MULT_S := 10.0
const SLIDE_MAX := 30.0                 # m/s sideways at the most when the board crosses over to what the eyes chose
const TRAIL_VMAX := 30.0                 # m/s on the forest trail (108 km/h) before boosts
const SPEED_CAP := 57.0              # a boost never pushes you past this (the hill alone reaches about 51 m/s)
const BUFF_COL := {"boost": Color(1.0, 0.55, 0.1), "shield": Color(0.3, 0.85, 1.0), "mult": Color(0.95, 0.4, 1.0), "donut": Color(1.0, 0.45, 0.7), "orb": Color(1.0, 0.9, 0.45)}

var shield: int = 0
var _boost_t: float = 0.0
var _mult_t: float = 0.0
var buffs_spawned: int = 0
var buffs_got: int = 0
var buff_log: Dictionary = {}
var spawned_kind: Dictionary = {}
var got_kind: Dictionary = {}
var orbs_got: int = 0
var _buff_tgt: Dictionary = {}
var _buff_cand: Dictionary = {}
var _buff_cand_t: float = 0.0
var _buff_w: float = 0.0
var _buff_want: float = 0.0
var _buff_assist: bool = true
var _buff_mesh: Dictionary = {}
var _buff_mat: Dictionary = {}


func _pick_buff(iso: bool) -> String:
	var r := _rng.randf()
	if iso:
		return "mult" if r < 0.3 else ("shield" if r < 0.65 else ("boost" if r < 0.85 else "donut"))
	return "boost" if r < 0.3 else ("shield" if r < 0.52 else ("mult" if r < 0.8 else "donut"))


func _clear_of_obs(obs: PackedFloat32Array, x: float, z: float, m: float) -> bool:
	var i := 0
	while i < obs.size():
		var dx := obs[i] - x
		var dz := obs[i + 1] - z
		var rr := obs[i + 2] + m
		if dx * dx + dz * dz < rr * rr:
			return false
		i += 4
	return true


var _glow_tex: GradientTexture2D
var _fxm: Dictionary = {}


func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex


## Shared materials: "solid" glowing colour, "add" additive translucent, "halo" soft billboard glow, "spark" particle colour from vertex colours.
func _fx_mat(kind: String, col: Color, energy: float = 1.8) -> StandardMaterial3D:
	var key := "%s_%s_%.1f" % [kind, col.to_html(true), energy]
	if _fxm.has(key):
		return _fxm[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.albedo_color = col
	if kind == "solid":
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if kind == "halo":
			m.albedo_texture = _glow_texture()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		elif kind == "ground":
			m.albedo_texture = _glow_texture()
		elif kind == "spark":
			m.vertex_color_use_as_albedo = true
	_fxm[key] = m
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, world: bool = false) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)
	if parent == self or world:          # `world`: the parent is a holder sitting at the origin, so pos is still a strip point and has to be laid onto the winding trail
		_place(n, pos)
	else:
		n.position = pos
	return n


func _cone(r: float, h: float, down: bool = false) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	var n := MeshInstance3D.new()
	n.mesh = c
	if down:
		n.rotation.x = PI
	return n


func _torus(inner: float, outer: float) -> TorusMesh:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 20
	tm.ring_segments = 8
	return tm


## A small cloud of sparkles that stays around an item (turned on only when it is close, so far ones cost nothing).
func _sparkler(parent: Node3D, col: Color, radius: float, n: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 5
	sm.rings = 2
	p.mesh = sm
	p.material_override = _fx_mat("spark", Color(1, 1, 1, 1))
	p.amount = n
	p.lifetime = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.color = col
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = cr
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## One pickup, built from simple shapes but lit like a treat: a spinning gem, a soft halo, a pool of light on the snow and a few sparkles.
##   boost   orange double-cone crystal with a white-hot core and orbiting sparks
##   shield  two crossed cyan rings round a glass bubble
##   mult    a magenta-gold gem with a floating x2
func _food_mat(col: Color, glow: float = 0.35) -> StandardMaterial3D:
	var key := "food_%s_%.2f" % [col.to_html(false), glow]
	if _fxm.has(key):
		return _fxm[key]
	var m := Mats.lit()
	m.albedo_color = col
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	_fxm[key] = m
	return m


func _fm(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var n := _mi(parent, mesh, _food_mat(col), pos)
	n.scale = sc
	return n


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return c


## One pickup, built from simple shapes and lit like a treat. Everything edible is eaten by opening your eyes wide.
##   boost   BURGER      a stack of bun, patty, cheese, lettuce, tomato, sesame bun
##   shield  ICE CREAM   a waffle cone with two scoops and a cherry
##   mult    CANDY       a wrapped sweet with twisted ends
##   donut   DONUT       pink frosting and sprinkles
## More looks for the same four jobs: a speed item may be a burger, a pizza slice, a hot dog or a taco; ice cream a cone or a popsicle; candy a wrapped sweet, a lollipop or gumdrops;
## a donut a donut or a cupcake. The colour still says what it does (orange speed, cyan ice, purple candy, pink donut), the shape is only for fun. True when a variant was built.
func _food_variant(body: Node3D, t: String, vr: int) -> bool:
	match t:
		"boost":
			if vr == 1:        # pizza slice
				var sl := _fm(body, PrismMesh.new(), Color(1.0, 0.78, 0.25), Vector3(0, 0.0, 0), Vector3(1.0, 1.0, 1.0))
				(sl.mesh as PrismMesh).size = Vector3(1.9, 2.2, 0.28)
				sl.rotation.z = PI
				for pi in 4:
					_fm(body, _sphere_mesh(0.2), Color(0.8, 0.12, 0.1), Vector3(-0.35 + 0.28 * float(pi % 2) * 1.2, 0.55 - 0.4 * float(pi), 0.16), Vector3(1.0, 1.0, 0.4))
				_fm(body, _cyl(1.0, 0.16), Color(0.85, 0.55, 0.2), Vector3(0, 0.95, 0), Vector3(1.0, 1.0, 0.5))
				return true
			if vr == 2:        # hot dog
				_fm(body, _cyl(0.5, 2.1), Color(0.95, 0.7, 0.35), Vector3(0, -0.15, 0), Vector3(1.0, 1.0, 1.0)).rotation.z = PI * 0.5
				_fm(body, _cyl(0.32, 2.4), Color(0.8, 0.28, 0.18), Vector3(0, 0.1, 0), Vector3(1.0, 1.0, 1.0)).rotation.z = PI * 0.5
				_fm(body, _cyl(0.1, 2.2), Color(1.0, 0.85, 0.1), Vector3(0, 0.4, 0.0), Vector3(1.0, 1.0, 1.0)).rotation.z = PI * 0.5
				return true
			if vr == 3:        # taco
				var shell := _fm(body, _torus(0.45, 1.0), Color(1.0, 0.8, 0.3), Vector3(0, 0, 0), Vector3(1.0, 0.7, 1.0))
				shell.rotation.x = PI * 0.5
				for ti in 5:
					_fm(body, _sphere_mesh(0.22), [Color(0.4, 0.85, 0.2), Color(0.9, 0.2, 0.15), Color(1.0, 0.9, 0.3)][ti % 3], Vector3(-0.6 + 0.3 * float(ti), 0.5, 0.0), Vector3(1.0, 0.8, 1.0))
				return true
		"shield":
			if vr == 1:        # popsicle
				_fm(body, _cyl(0.12, 0.8), Color(0.9, 0.75, 0.5), Vector3(0, -1.0, 0), Vector3(1.0, 1.0, 1.0))
				var pop := _fm(body, BoxMesh.new(), Color(0.5, 0.9, 1.0), Vector3(0, 0.1, 0), Vector3(1.0, 1.0, 1.0))
				(pop.mesh as BoxMesh).size = Vector3(1.0, 1.7, 0.5)
				_fm(body, _sphere_mesh(0.5), Color(0.5, 0.9, 1.0), Vector3(0, 0.95, 0), Vector3(1.0, 0.7, 0.5))
				return true
		"mult":
			if vr == 1:        # lollipop
				_fm(body, _cyl(0.08, 1.7), Color(1, 1, 1), Vector3(0, -0.7, 0), Vector3(1.0, 1.0, 1.0))
				_fm(body, _sphere_mesh(0.85), Color(0.95, 0.25, 0.75), Vector3(0, 0.55, 0), Vector3(1.0, 1.0, 0.45))
				var sw := _fm(body, _torus(0.45, 0.62), Color(1.0, 0.95, 0.4), Vector3(0, 0.55, 0.1), Vector3(1.0, 1.0, 1.0))
				sw.rotation.x = PI * 0.5
				return true
			if vr == 2:        # gumdrops
				var gc: Array = [Color(0.95, 0.25, 0.75), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.25)]
				for gi in 3:
					_fm(body, _sphere_mesh(0.48), gc[gi], Vector3(-0.7 + 0.7 * float(gi), -0.15 + 0.35 * float(gi % 2), 0), Vector3(1.0, 0.8, 1.0))
				return true
		"donut":
			if vr == 1:        # cupcake
				_fm(body, _cyl(0.7, 0.8), Color(0.75, 0.45, 0.25), Vector3(0, -0.45, 0), Vector3(1.0, 1.0, 1.0))
				_fm(body, _sphere_mesh(0.8), Color(0.98, 0.45, 0.72), Vector3(0, 0.25, 0), Vector3(1.0, 0.85, 1.0))
				_fm(body, _sphere_mesh(0.22), Color(0.9, 0.1, 0.15), Vector3(0, 0.95, 0), Vector3(1.0, 1.0, 1.0))
				return true
	return false


func _make_item(t: String) -> Dictionary:
	var col: Color = BUFF_COL[t]
	var root := Node3D.new()
	var spin := Node3D.new()
	root.add_child(spin)
	var halo := _mi(root, _quad(6.2), _fx_mat("halo", Color(col.r, col.g, col.b, 0.8)))
	var pool := _mi(root, _quad(7.0), _fx_mat("ground", Color(col.r, col.g, col.b, 0.55)), Vector3(0, -1.6, 0))
	pool.rotation.x = -PI * 0.5
	var body := Node3D.new()
	spin.add_child(body)
	body.scale = Vector3(1.3, 1.3, 1.3)
	var built := true
	_mi(body, _kit_mesh(String({"boost": "crystal", "shield": "cage", "mult": "rings", "donut": "tetra"}.get(t, "tetra")), col), _mol_material())
	match ("skip" if built else t):
		"skip":
			pass
		"boost":
			_fm(body, _sphere_mesh(1.0), Color(0.93, 0.62, 0.28), Vector3(0, -0.62, 0), Vector3(1.0, 0.42, 1.0))
			_fm(body, _cyl(1.02, 0.3), Color(0.36, 0.18, 0.09), Vector3(0, -0.22, 0))
			var ch := _fm(body, BoxMesh.new(), Color(1.0, 0.82, 0.15), Vector3(0, -0.02, 0))
			(ch.mesh as BoxMesh).size = Vector3(1.95, 0.07, 1.95)
			ch.rotation.y = 0.785
			_fm(body, _cyl(1.08, 0.1), Color(0.35, 0.8, 0.25), Vector3(0, 0.1, 0))
			_fm(body, _cyl(0.95, 0.15), Color(0.9, 0.2, 0.15), Vector3(0, 0.23, 0))
			_fm(body, _sphere_mesh(1.05), Color(0.95, 0.6, 0.22), Vector3(0, 0.42, 0), Vector3(1.0, 0.62, 1.0))
			for i in 7:
				var a := float(i) * TAU / 7.0
				_fm(body, _sphere_mesh(0.07), Color(1.0, 0.97, 0.85), Vector3(cos(a) * 0.5, 0.82 - 0.05 * float(i % 2), sin(a) * 0.5), Vector3(1.0, 0.6, 1.0))
		"shield":
			var cone := _cone(0.62, 1.6, true)
			cone.material_override = _food_mat(Color(0.86, 0.6, 0.3))
			cone.position = Vector3(0, -0.7, 0)
			body.add_child(cone)
			_fm(body, _sphere_mesh(0.7), Color(1.0, 0.55, 0.75), Vector3(0, 0.3, 0))
			_fm(body, _sphere_mesh(0.62), Color(0.8, 0.95, 1.0), Vector3(0, 0.95, 0))
			_fm(body, _sphere_mesh(0.18), Color(0.9, 0.1, 0.15), Vector3(0.05, 1.5, 0.0))
			_fm(body, _sphere_mesh(0.2), Color(1.0, 0.55, 0.75), Vector3(0.6, 0.0, 0.1), Vector3(0.8, 1.3, 0.8))
		"mult":
			_fm(body, _sphere_mesh(0.7), Color(0.95, 0.25, 0.75), Vector3.ZERO, Vector3(1.3, 0.85, 0.85))
			for sx in [-1.0, 1.0]:
				var tw := _cone(0.5, 0.9)
				tw.material_override = _food_mat(Color(1.0, 0.85, 0.25))
				tw.position = Vector3(float(sx) * 1.25, 0.0, 0.0)
				tw.rotation.z = -float(sx) * PI * 0.5
				body.add_child(tw)
			var ring := _mi(body, _torus(0.62, 0.74), _food_mat(Color(1, 1, 1), 0.5))
			ring.rotation.z = PI * 0.5
			ring.scale = Vector3(1.0, 1.0, 1.0)
		_:
			body.rotation.x = 1.0
			_fm(body, _torus(0.4, 1.0), Color(0.9, 0.65, 0.35), Vector3.ZERO)
			_fm(body, _torus(0.42, 0.96), Color(0.98, 0.4, 0.66), Vector3(0, 0.12, 0), Vector3(1.0, 0.6, 1.0))
			var sc: Array = [Color(1, 1, 0.3), Color(0.3, 0.9, 1.0), Color(1, 1, 1), Color(0.5, 1.0, 0.4)]
			for i in 12:
				var a2 := float(i) * TAU / 12.0
				var sp2 := _fm(body, BoxMesh.new(), sc[i % 4], Vector3(cos(a2) * 0.7, 0.3, sin(a2) * 0.7))
				(sp2.mesh as BoxMesh).size = Vector3(0.22, 0.06, 0.07)
				sp2.rotation.y = -a2 + float(i) * 0.9
	var sp := _sparkler(root, Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5, 1.0), 1.6, 10)
	return {"root": root, "spin": spin, "halo": halo, "sp": sp, "extra": []}


var _quad_meshes: Dictionary = {}
var _sph_meshes: Dictionary = {}


func _quad(sz: float) -> QuadMesh:
	if not _quad_meshes.has(sz):
		var q := QuadMesh.new()
		q.size = Vector2(sz, sz)
		_quad_meshes[sz] = q
	return _quad_meshes[sz]


func _sphere_mesh(r: float) -> SphereMesh:
	if not _sph_meshes.has(r):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		_sph_meshes[r] = s
	return _sph_meshes[r]


func _buff_assets(t: String) -> void:
	if _buff_mesh.has(t):
		return
	var os := SphereMesh.new()
	os.radius = 0.5
	os.height = 1.0
	os.radial_segments = 8
	os.rings = 4
	_buff_mesh[t] = os
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.16
	cm.height = 9.0
	cm.radial_segments = 6
	_buff_mesh["beacon"] = cm
	for key in BUFF_COL:
		if not _buff_mat.has(key):
			var c: Color = BUFF_COL[key]
			_buff_mat[key] = _fx_mat("solid", c, 2.0)
			_buff_mat["beacon_" + str(key)] = _fx_mat("add", Color(c.r, c.g, c.b, 0.3))


# --------------------------------------------------------------------------
# GLINTS: small gold sparks. A rail carries a spiral of them (ride it and you scoop the lot), a ramp leaves an arc of them in the air, and a crash spills some of yours
# onto the snow ahead, where they can be caught again. Rushing along a rail with a good handful gives a boost off the end.
# --------------------------------------------------------------------------
var glints: int = 0
var _gl_run: int = 0                     # glints scooped since the board got onto the current rail
var _gl_mesh: SphereMesh = null
var _gl_mat: Material = null
var _gl_spill: Array = []


func _gl_assets() -> void:
	if _gl_mesh == null:
		_gl_mesh = SphereMesh.new()
		_gl_mesh.radius = 0.3
		_gl_mesh.height = 0.6
		_gl_mesh.radial_segments = 6
		_gl_mesh.rings = 3
		_gl_mat = _fx_mat("add", Color(1.0, 0.82, 0.25, 0.95))


func _glint_line(row: Dictionary, pts: Array, rad: float) -> void:
	if pts.is_empty():
		return
	_gl_assets()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _gl_mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, TrailCurve.xf(Transform3D(Basis(), pts[i])))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _gl_mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 30.0
	add_child(inst)
	(row["nodes"] as Array).append(inst)
	var got := PackedByteArray()
	got.resize(pts.size())
	if not row.has("gl"):
		row["gl"] = []
	(row["gl"] as Array).append({"mm": mm, "pts": pts, "got": got, "rad": rad})


## A big moment: words, a colour flash, confetti and a ring, so it is felt and not read.
func _cheer(text: String, col: Color, size: float = 1.0) -> void:
	_toast(text, col)
	_flash = maxf(_flash, 0.25 * size)
	_fov_punch = maxf(_fov_punch, 6.0 * size)
	_psy_pulse(2 if size >= 1.5 else 5, col)
	_trip_add(0.04 * size)
	var cp := spos + Vector3(0.0, 2.0, -4.0)
	if not _nofx.contains("c"):
		Fx.confetti(self, cp, int(50.0 * size), 1.0 + 0.4 * size)
	_ring(spos + Vector3(0.0, 0.8, 0.0), col, 7.0 + 5.0 * size, 0.5, true)
	_burst(cp, col, int(30.0 * size), 10.0, 0.8, 1.0, Vector3(0, 1, 0), 120.0, -6.0)
	Game.sfx(&"coin")


func _glint_got(p: Vector3) -> void:
	glints += 1
	_trip_add(0.012)
	_cue(2, mini(_gl_run, 14))
	_psy_pulse(1, Color(1.0, 0.85, 0.3))
	_gl_run += 1
	_flow_touch()
	_gain(int(5.0 * groove))
	_burst(p, Color(1.0, 0.85, 0.3), 3, 4.0, 0.35, 0.5)
	if glints % 3 == 0:
		Game.sfx(&"coin")


var _air_ring_m: TorusMesh = null
var _air_chain: int = 0


func _air_ring_mesh() -> TorusMesh:
	if _air_ring_m == null:
		_air_ring_m = TorusMesh.new()
		_air_ring_m.inner_radius = 3.2
		_air_ring_m.outer_radius = 3.9
		_air_ring_m.rings = 24
		_air_ring_m.ring_segments = 6
	return _air_ring_m


## Flying through a ring: a lift, a push and a cheer that grows with every ring in a row.
func _air_rings_tick() -> void:
	if grounded:
		return
	var bp := spos + Vector3(0.0, 0.9, 0.0)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r.has("airrings"):
			continue
		for e in r["airrings"]:
			if e["got"] or absf(float((e["p"] as Vector3).z) - spos.z) > 5.0:
				continue
			if (e["p"] as Vector3).distance_to(bp) < 4.6:
				e["got"] = true
				_air_chain += 1
				if is_instance_valid(e["n"]):
					(e["n"] as Node3D).visible = false
				vy = minf(vy + 4.0 + 0.6 * float(_air_chain), 26.0)
				vel.y -= 2.0
				_boost_t = maxf(_boost_t, 1.0)
				_vx_active_t = 0.5
				_gain(int(120.0 * float(_air_chain) * groove))
				_trip_add(0.03)
				Game.sfx(&"zap")
				_mix_add("ring")
				_cheer("AIR CHAIN x%d" % _air_chain, Color(0.4, 1.0, 0.9) if _air_chain < 3 else Color(1.0, 0.85, 0.3), 0.7 + 0.25 * float(_air_chain))


func _glint_tick(delta: float) -> void:
	if not trail or _finished:
		return
	_air_rings_tick()
	var bp := spos + Vector3(0.0, 0.9, 0.0)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r.has("gl"):
			continue
		for e in r["gl"]:
			var pts: Array = e["pts"]
			var got: PackedByteArray = e["got"]
			for i in pts.size():
				if got[i] == 1:
					continue
				var pv: Vector3 = pts[i]
				if absf(pv.z - spos.z) > 4.0:
					continue
				if pv.distance_to(bp) < float(e["rad"]):
					got[i] = 1
					(e["mm"] as MultiMesh).set_instance_transform(i, TrailCurve.xf(Transform3D(Basis().scaled(Vector3.ZERO), pv)))
					_glint_got(pv)
	# the ones a crash spilled: they tumble down the slope and can be caught again after a moment
	var i2 := _gl_spill.size() - 1
	while i2 >= 0:
		var g: Dictionary = _gl_spill[i2]
		g["t"] = float(g["t"]) + delta
		var gp: Vector3 = g["p"]
		var gv: Vector3 = g["v"]
		gv.y -= 18.0 * delta
		gp += gv * delta
		var gh := terrain_h(gp.x, gp.z) + 0.4
		if gp.y < gh:
			gp.y = gh
			gv.y = absf(gv.y) * 0.5
			gv.x *= 0.7
			gv.z *= 0.8
		g["p"] = gp
		g["v"] = gv
		var gn: Node3D = g["n"]
		if is_instance_valid(gn):
			_place(gn, gp)
		var take: bool = float(g["t"]) > 0.6 and gp.distance_to(bp) < 2.8
		if take or float(g["t"]) > 5.0:
			if is_instance_valid(gn):
				gn.queue_free()
			_gl_spill.remove_at(i2)
			if take:
				_glint_got(gp)
		i2 -= 1


## A crash knocks some glints out of the board's pocket: they scatter forward and down the slope, a handful to chase.
func _glint_spill() -> void:
	var n := mini(glints, 20)
	if n < 3:
		return
	glints -= n
	_gl_assets()
	for i in n:
		var node := _mi(self, _gl_mesh, _gl_mat, spos)
		_gl_spill.append({"n": node, "p": spos + Vector3(0.0, 1.0, 0.0), "v": Vector3(_rng.randf_range(-7.0, 7.0), _rng.randf_range(7.0, 14.0), -_rng.randf_range(5.0, 16.0)), "t": 0.0})
	_toast("-%d glints!" % n, Color(1.0, 0.8, 0.3))


func _spawn_orb(row: Dictionary, x: float, z: float, t: String) -> Node3D:
	_buff_assets("orb")
	var n := MeshInstance3D.new()
	n.mesh = _buff_mesh["orb"]
	n.material_override = _buff_mat["orb"]
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	_place(n, Vector3(x, terrain_h(x, z) + 1.3, z))
	(row["nodes"] as Array).append(n)
	return n


## A buff with a lead-in trail of small orbs (x, z pairs, ordered from far to near).
func _spawn_buff(row: Dictionary, t: String, x: float, z: float, trail: Array, kind: String, lift: float = 0.0) -> void:
	_buff_assets("orb")
	var it := _make_item(t)
	var bn: Node3D = it["root"]
	add_child(bn)
	_place(bn, Vector3(x, terrain_h(x, z) + 2.4 + lift, z))
	(row["nodes"] as Array).append(bn)
	var bc := MeshInstance3D.new()
	bc.mesh = _buff_mesh["beacon"]
	bc.material_override = _buff_mat["beacon_" + t]
	bc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bn.add_child(bc)
	bc.position = Vector3(0.0, 5.4, 0.0)
	var orbs: Array = []
	for p in trail:
		var pv: Vector2 = p
		orbs.append({"n": _spawn_orb(row, pv.x, pv.y, "orb"), "x": pv.x, "z": pv.y, "taken": false})
	(row["buffs"] as Array).append({"t": t, "x": x, "z": z, "taken": false, "n": bn, "y": bn.position.y, "ph": _rng.randf() * TAU, "orbs": orbs, "kind": kind, "lift": lift,
		"spin": it["spin"], "halo": it["halo"], "sp": it["sp"], "extra": it["extra"]})
	buffs_spawned += 1
	spawned_kind[kind] = int(spawned_kind.get(kind, 0)) + 1


func _place_buffs(row: Dictionary, d: float, prev_rz: float, rz: float) -> void:
	var gaps: Array = row["gaps"]
	var obs: PackedFloat32Array = row["obs"]
	# in front of an opening
	for g in gaps:
		var iso: bool = g.get("iso", false)
		var p := 1.0 if iso else (0.45 if g["good"] else 0.35)          # stretches are longer now, so more of the gates carry an offer
		if _rng.randf() >= p:
			continue
		var gx: float = g["x"]
		var bz := 0.0
		var bxx := gx
		var found := false
		for dzv in [12.0, 17.0, 9.0, 22.0]:
			for dxv in [0.0, 3.0, -3.0]:
				if not found and _clear_of_obs(obs, gx + dxv, rz + dzv, 4.0):
					bz = rz + dzv
					bxx = gx + dxv
					found = true
		if not found:
			continue
		var trail: Array = []
		for i in 3:
			trail.append(Vector2(gx, rz + 29.0 - 6.0 * float(i)))
		g["buff"] = true
		_spawn_buff(row, _pick_for_gate(String(g.get("leads", "rush"))), bxx, bz, trail, "safe" if g["good"] else "gate")
	# beside the safe line, between two barriers: you have to look there and want it
	var span := prev_rz - rz
	if span >= 80.0 and (int(row["j"]) == START_CALM or _rng.randf() < float(ZONES[String(row.get("zone", "rush"))]["path_buff"])):
		for attempt in 6:
			var zb := prev_rz - span * _rng.randf_range(0.42, 0.58)          # mid-way: time to pick it out after the last barrier and to get back before the next
			var bx0 := path_x(row, zb)
			var off := _rng.randf_range(8.0, 13.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			if absf(bx0 + off) > 42.0:
				off = -off
			var bx := bx0 + off
			if absf(bx) > 42.0 or not _clear_of_obs(obs, bx, zb, 4.5):
				continue
			var tz := zb + 26.0
			var sx := path_x(row, tz)
			var trail2: Array = []
			for i in 4:
				var u := float(i + 1) / 5.0
				var s := u * u * (3.0 - 2.0 * u)
				var px := lerpf(sx, bx, s)
				var pz := zb + 26.0 * (1.0 - u)
				if _clear_of_obs(obs, px, pz, 2.5):
					trail2.append(Vector2(px, pz))
			_spawn_buff(row, "boost" if int(row["j"]) == START_CALM else _pick_for_gate(String(row.get("zone", "rush"))), bx, zb, trail2, "path")
			break


# --------------------------------------------------------------------------
# The chain. The game is about picking the right thing to go for, in the right order: CANDY (x2) first, because it multiplies what follows, then a BURGER (speed),
# then a RAMP (the launch), then a FACE or a trick in the air. Each step taken in order within a few seconds raises the chain level (1 to 4), and every level makes the
# next pickups, the launch and the points bigger. A different pickup still does its own job: it just does not raise the level and costs you nothing. ICE CREAM and DONUT
# are the recovery items: they never break the chain and they buy a few seconds. The next step is marked on the item itself, so the choice is never a puzzle.
# --------------------------------------------------------------------------
const CHAIN_ORDER := ["mult", "boost", "ramp", "air"]
const CHAIN_WINDOW := 9.0
var chain_step: int = 0                   # index in CHAIN_ORDER of the thing to take next
var chain_lvl: int = 0                    # 0 .. 4
var _chain_t: float = 0.0                 # seconds left to take the next step before the chain drops
var _chain_flash: float = 0.0


func _chain_expect_kind() -> String:
	return String(CHAIN_ORDER[chain_step])


func _chain_k() -> float:
	return 1.0 + 0.25 * float(chain_lvl)


func _chain_hit(kind: String) -> void:
	if kind == _chain_expect_kind():
		chain_lvl = mini(chain_lvl + 1, 4)
		chain_step = (chain_step + 1) % CHAIN_ORDER.size()
		_chain_t = CHAIN_WINDOW
		_chain_flash = 1.0
	elif (kind == "shield" or kind == "donut") and chain_lvl > 0:
		_chain_t = minf(_chain_t + 3.0, CHAIN_WINDOW + 3.0)


## The arches say what the gate offers. The colour of the arch is where the gate leads (its realm), the gem on top is the item waiting in front of it (the item's own colour:
## purple candy, orange burger, cyan ice cream, pink donut), and the arch that has the NEXT step of the chain turns gold and pulses.
var _arch_hl_t: float = 0.0


func _arch_highlight(delta: float) -> void:
	_arch_hl_t -= delta
	if _arch_hl_t > 0.0:
		return
	_arch_hl_t = 0.12
	var want := _chain_expect_kind()
	var pulse := 0.5 + 0.5 * sin(_age * 6.0)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"] or r["passed"]:
			continue
		if spos.z - float(r["z"]) > 260.0:
			continue
		for g in r["gaps"]:
			var am: Variant = g.get("arch_mat", null)
			if am == null or not is_instance_valid(am):
				continue
			var mat := am as StandardMaterial3D
			if String(g.get("offer", "")) == want:
				mat.albedo_color = Color(1.0, 0.82, 0.25)
				mat.emission = Color(1.0, 0.78, 0.2)
				mat.emission_energy_multiplier = 2.6 + 2.4 * pulse
			else:
				var bc: Color = g.get("arch_col", Color.WHITE)
				mat.albedo_color = bc
				mat.emission = bc
				mat.emission_energy_multiplier = 2.4


# --------------------------------------------------------------------------
# FLOW: the multiplier you keep alive. Clean gates, landed tricks, pickups, dodges and faces push it up a level; everything you do, even a small pop off the snow, refills
# its clock. Leave it alone for a few seconds and it starts dropping, a level at a time. The higher it is, the shorter the clock: at the top you have to keep moving.
# (It used to climb with every gate and never fall until you crashed.)
# --------------------------------------------------------------------------
const FLOW_WINDOW := 5.0             # seconds of grace at the bottom level
const FLOW_WINDOW_MIN := 2.6         # and at the top
const FLOW_DRAIN_STEP := 0.7         # seconds per level once the clock has run out
const FLOW_MAX := 8
var _flow_t: float = 0.0
var _flow_window: float = FLOW_WINDOW
var _flow_bump: float = 0.0           # HUD: a flash when it goes up
var flow_drops: int = 0


## Something small happened: the clock is refilled, the level stays.
func _flow_touch() -> void:
	_flow_window = lerpf(FLOW_WINDOW, FLOW_WINDOW_MIN, clampf(float(chain) / float(FLOW_MAX), 0.0, 1.0))
	_flow_t = _flow_window


## Something worth a level happened.
func _flow_up(levels: int = 1) -> void:
	var chain_was := chain
	chain = mini(chain + levels, 24)
	if chain / 3 > chain_was / 3 and chain >= 3:
		_cheer("COMBO x%d!" % chain, Color(1.0, 0.8, 0.3), 1.0 + 0.1 * float(mini(chain / 3, 5)))
	groove = 1.0 + 0.25 * minf(float(chain), float(FLOW_MAX))
	best_flow = maxf(best_flow, groove)
	_flow_bump = 1.0
	_flow_touch()


func _flow_tick(delta: float) -> void:
	_flow_bump = maxf(_flow_bump - 3.0 * delta, 0.0)
	if chain <= 0 or _finished or _paused:
		return
	_flow_t -= delta
	if _flow_t <= 0.0:
		chain = maxi(mini(chain, FLOW_MAX) - 1, 0)          # anything banked above the top level goes first
		groove = 1.0 + 0.25 * float(chain)
		flow_drops += 1
		_flow_t = FLOW_DRAIN_STEP
		_flow_window = maxf(_flow_window, FLOW_DRAIN_STEP)


# --------------------------------------------------------------------------
# POP: raise your eyebrows to hop off the snow (W or the up arrow without a camera). On a ramp, holding them up charges the launch instead, and the
# pop happens at the lip. A pop is small, but it refills the flow clock: it is the thing you do between the big things.
# --------------------------------------------------------------------------
const POP_RISE := 0.3                # how far above your own resting level the eyebrows must go
const POP_VY := 6.2                  # m/s off the snow: about 1.2 s in the air and 1.9 m up
const POP_COOLDOWN := 1.0
var brow_override: bool = false      # tests
var pops_flat: int = 0
var _brow_base: float = 0.0
var _brow_ready: bool = false
var _brow_was: bool = false
var _brow_hold: float = 0.0
var _pop_cd: float = 0.0
var _brow_hint_t: float = 0.0
var _brow_hinted: bool = false


## Are the eyebrows up, judged against where this face's eyebrows normally sit?
func _brows_up(delta: float) -> bool:
	if brow_override or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		return true
	if GazeProvider.backend != GazeProvider.Backend.CAMERA or not GazeProvider._camera_fresh():
		return false
	var b := float(GazeProvider.face.get("brows", 0.0))
	if not _brow_ready:
		_brow_base = b
		_brow_ready = true
	var raised := b - _brow_base > POP_RISE
	_brow_hold = _brow_hold + delta if raised else 0.0
	var up := _brow_hold > 0.12                                        # held for a moment: one noisy frame from the camera is not a pop
	if not raised:
		_brow_base += (b - _brow_base) * minf(delta / 4.0, 1.0)          # the resting level follows slowly, and only while they are down
	return up


func _pop_tick(delta: float) -> void:
	_pop_cd = maxf(_pop_cd - delta, 0.0)
	_brow_hint_t = maxf(_brow_hint_t - delta, 0.0)
	var up := _brows_up(delta)
	var edge := up and not _brow_was
	_brow_was = up
	_brow_held = up
	if not _brow_hinted and _age > 7.0 and _eye_on and not _finished:
		_brow_hinted = true
		_brow_hint_t = 4.0
	if not edge or _finished or not grounded or hurt_t > 0.0 or _pop_cd > 0.0 or _on_ramp_now:
		return
	_pop_cd = POP_COOLDOWN
	grounded = false
	vy += POP_VY
	air_t = 0.0
	pops_flat += 1
	_gain(15)
	_flow_touch()
	_brow_hint_t = 0.0
	_fov_punch = maxf(_fov_punch, 2.5)
	_burst(spos + Vector3(0, 0.3, 0), Color(0.95, 0.98, 1.0), 18, 6.0, 0.5, 0.8, Vector3(0, 1, 0.3), 60.0, -6.0)
	Game.sfx(&"boing")


var _brow_held: bool = false
var _on_ramp_now: bool = false


func _chain_tick(delta: float) -> void:
	_flow_tick(delta)
	_pop_tick(delta)
	_chain_flash = maxf(_chain_flash - 2.0 * delta, 0.0)
	_arch_highlight(delta)
	if chain_lvl > 0:
		_chain_t -= delta
		if _chain_t <= 0.0:
			chain_lvl = 0
			chain_step = 0


func _chain_color(i: int) -> Color:
	match i:
		0:
			return BUFF_COL["mult"]
		1:
			return BUFF_COL["boost"]
		2:
			return Color(0.9, 0.95, 1.0)
	return Color(1.0, 0.88, 0.3)


## Where the next step of the chain is in the world (INF when it is not something you can see: the air step).
func _chain_target_pos(kind: String) -> Vector3:
	var best := Vector3.INF
	var best_dz := 1.0e9
	if kind == "mult" or kind == "boost":
		for k in _rows:
			for b in (_rows[k] as Dictionary)["buffs"]:
				if b["taken"] or String(b["t"]) != kind or float(b.get("arm", 0.0)) > 0.0:
					continue
				var dz := spos.z - float(b["z"])
				if dz < 6.0 or dz > 230.0 or dz >= best_dz:
					continue
				best_dz = dz
				best = Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 4.2 + float(b.get("lift", 0.0)), float(b["z"]))
	elif kind == "ramp":
		for kk in _kickers:
			var lipz: float = float(kk["z"]) - float(kk["len"])
			var dz2 := spos.z - lipz
			if dz2 < 6.0 or dz2 > 260.0 or dz2 >= best_dz:
				continue
			best_dz = dz2
			best = Vector3(float(kk["x"]), terrain_h(float(kk["x"]), lipz) + 5.0, lipz)
	return best


## The chain on screen: four dots in order (the next one big and pulsing), a pip for each level, and a thin bar for the time left. No words. The next step is also ringed in the world.
func _draw_chain(s: Vector2, k: float, m: float) -> void:
	var cx0 := s.x * 0.5 - 60.0 * k
	var cy0 := m + 34.0 * k
	for i in 4:
		var c := _chain_color(i)
		var pos := Vector2(cx0 + float(i) * 40.0 * k, cy0)
		if i == chain_step:
			var rr := (11.0 + 2.5 * sin(_age * 8.0) + 5.0 * _chain_flash) * k
			Draw2D.circle(_hud, pos, rr + 3.0 * k, Color(0, 0, 0, 0.6))
			Draw2D.circle(_hud, pos, rr, Color(c.r, c.g, c.b, 1.0))
		elif chain_lvl > 0 and i < chain_step:
			Draw2D.circle(_hud, pos, 7.0 * k, Color(c.r, c.g, c.b, 0.9))
		else:
			Draw2D.circle(_hud, pos, 7.0 * k, Color(c.r, c.g, c.b, 0.3))
	for li in 4:
		var on := li < chain_lvl
		_hud.draw_rect(Rect2(cx0 + (float(li) * 14.0 - 8.0) * k + 0.0, cy0 + 20.0 * k, 11.0 * k, 5.0 * k), Color(1.0, 0.85, 0.3, 0.95) if on else Color(1, 1, 1, 0.2))
	if chain_lvl > 0:
		var fw := 120.0 * k
		_hud.draw_rect(Rect2(cx0 - 10.0 * k, cy0 + 29.0 * k, fw, 3.0 * k), Color(1, 1, 1, 0.15))
		_hud.draw_rect(Rect2(cx0 - 10.0 * k, cy0 + 29.0 * k, fw * clampf(_chain_t / CHAIN_WINDOW, 0.0, 1.0), 3.0 * k), Color(1.0, 0.85, 0.3, 0.9))
	var tp := _chain_target_pos(_chain_expect_kind())
	if tp.is_finite() and not _behind(tp):
		var sc := _unp(tp)
		if sc.x > 0.0 and sc.x < s.x and sc.y > 0.0 and sc.y < s.y:
			var c2 := _chain_color(chain_step)
			var pr := (24.0 + 4.0 * sin(_age * 8.0)) * k
			Draw2D.arc(_hud, sc, pr, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 7.0 * k)
			Draw2D.arc(_hud, sc, pr, 0.0, TAU, 32, Color(c2.r, c2.g, c2.b, 0.95), 4.0 * k)
			var tri := PackedVector2Array([sc + Vector2(0, -pr - 18.0 * k), sc + Vector2(-9.0 * k, -pr - 30.0 * k), sc + Vector2(9.0 * k, -pr - 30.0 * k)])
			Draw2D.poly(_hud, tri, Color(c2.r, c2.g, c2.b, 0.95))


func _gain(pts: int) -> void:
	score += int(float(pts) * (2.0 if _mult_t > 0.0 else 1.0) * _chain_k() * (1.0 + 0.8 * _mbody[1] / 6.0) * (1.0 + 2.0 * _mol_dmt()))          # DOM: more for everything; all six: much more


func _tick_buffs(delta: float) -> void:
	_boost_t = maxf(_boost_t - delta, 0.0)
	_mult_t = maxf(_mult_t - delta, 0.0)


var _hop_t: float = 1.0
var _hop_dur: float = 0.6
var _hop_h: float = 1.0
var _hop_spin: float = 0.0
var _hop_pitch: float = 0.0
var _hop_return: bool = false
var _pop_col: Color = Color.WHITE
var _pop_a: float = 0.0
var _hud_pops: Array = []
var _bubble: MeshInstance3D
var _trail_boost: CPUParticles3D
var _trail_mult: CPUParticles3D


func _start_hop(h: float, dur: float, spin: float, pitch: float, ret: bool) -> void:
	_hop_t = 0.0
	_hop_h = h
	_hop_dur = dur
	_hop_spin = spin
	_hop_pitch = pitch
	_hop_return = ret


## An explosion of sparkles at pos. dir / spread shape it (180 = a ball), grav pulls the sparks down (negative) or floats them up.
var _burst_live: int = 0


func _burst(pos: Vector3, col: Color, n_in: int, speed: float, life: float, size: float, dir: Vector3 = Vector3.UP, spread: float = 180.0, grav: float = -6.0) -> void:
	if _nofx.contains("b"):
		return
	var cap := 12 if OS.has_feature("web") else 40          # every burst is a node whose particles the CPU moves each frame: only so many at once, and on a phone smaller ones
	if _burst_live >= cap:
		return
	var n := maxi(1, int(float(n_in) * (0.5 if OS.has_feature("web") else 1.0)))
	_burst_live += 1
	var p := CPUParticles3D.new()
	p.mesh = _sphere_mesh(0.1)
	p.material_override = _fx_mat("spark", Color(1, 1, 1, 1))
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.6
	p.color = col
	var cr := Gradient.new()
	cr.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	cr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = cr
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_wset(p, pos)
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(func() -> void:
		_burst_live = maxi(_burst_live - 1, 0)
		if is_instance_valid(p):
			p.queue_free())


## A ring of light that expands and fades: standing (facing the camera) or flat on the snow.
var _nofx: String = str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('nofx') || ''")) if OS.has_feature("web") else ""          # ?nofx=rbc: no rings / bursts / confetti (to find what an effect costs)


var _ring_pool: Array = []
var _ring_i: int = 0


func _ring(pos: Vector3, col: Color, r_end: float, dur: float, standing: bool) -> void:
	if _nofx.contains("r"):
		return
	var m := MeshInstance3D.new()
	m.mesh = _torus(0.9, 1.0)
	# the ring's material comes from a small pool that is never freed: a new one per ring had its shader thrown away and built again each time (a tenth of a second of
	# stopped picture at every pickup)
	if _ring_pool.is_empty():
		for i in 10:
			_ring_pool.append(Mats.glow())
	_ring_i = (_ring_i + 1) % _ring_pool.size()
	var mat: StandardMaterial3D = _ring_pool[_ring_i]
	mat.albedo_color = Color(col.r, col.g, col.b, 0.95)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	_wset(m, pos)
	if standing:
		m.rotation.x = PI * 0.5
	m.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * r_end, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(m.queue_free)


## What a pickup feels like, one flavour each. Everything here is visual (sparkles, light, a hop of the rider); it never changes where the board goes.
##   boost   orange fireworks + a forward streak, a nose-up pop, the field of view kicks wide
##   shield  cool blue sparkle and two shock rings, a full graceful spin in the air
##   mult    gold and magenta confetti, a half turn to face the camera and back
func _buff_pop(b: Dictionary, shown: String) -> void:
	var t: String = b["t"]
	var col: Color = BUFF_COL[t]
	var pos := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.9, float(b["z"]))
	var fwd3 := Vector3(sin(heading), 0.25, -cos(heading))
	_pop_col = col
	_pop_a = 1.0
	_hud_pops.append({"p": pos, "col": col, "t": 0.0, "text": shown})
	match t:
		"boost":
			_burst(pos, Color(1.0, 0.6, 0.15), 70, 14.0, 0.9, 1.0)
			_burst(pos, Color(1.0, 0.95, 0.6), 36, 24.0, 0.6, 0.8, fwd3, 20.0, -2.0)
			_ring(pos, col, 7.0, 0.45, true)
			_start_hop(1.0, 0.55, 0.0, 0.5, false)
			_fov_punch = 9.0
			_shake = maxf(_shake, 0.45)
		"shield":
			_burst(pos, col, 56, 9.0, 1.0, 1.0, Vector3.UP, 180.0, -3.0)
			_burst(pos, Color(1, 1, 1), 26, 5.0, 1.2, 0.7, Vector3.UP, 180.0, 1.5)
			_ring(pos, col, 9.0, 0.6, true)
			_ring(pos + Vector3(0, -1.6, 0), col, 13.0, 0.75, false)
			_start_hop(1.35, 0.8, TAU, 0.0, false)
			_shake = maxf(_shake, 0.25)
		"donut":
			_burst(pos, Color(1.0, 0.45, 0.7), 56, 10.0, 1.2, 1.2, Vector3.UP, 180.0, -8.0)
			_burst(pos, Color(1.0, 0.95, 0.4), 30, 9.0, 1.2, 0.9, Vector3.UP, 180.0, -8.0)
			_ring(pos, col, 8.0, 0.5, true)
			_start_hop(1.0, 0.6, TAU, 0.0, false)
			_shake = maxf(_shake, 0.2)
		_:
			_burst(pos, Color(1.0, 0.85, 0.3), 56, 11.0, 1.3, 1.3, Vector3.UP, 180.0, -9.0)
			_burst(pos, Color(0.95, 0.35, 1.0), 56, 11.0, 1.3, 1.3, Vector3.UP, 180.0, -9.0)
			_ring(pos, Color(1.0, 0.85, 0.3), 8.0, 0.5, true)
			_start_hop(1.15, 0.7, PI, 0.0, true)
			_shake = maxf(_shake, 0.2)


func _ensure_fx() -> void:
	if _bubble != null or _sled == null:
		return
	_bubble = MeshInstance3D.new()
	_bubble.mesh = _sphere_mesh(1.55)
	_bubble.material_override = _fx_mat("add", Color(0.3, 0.85, 1.0, 0.2))
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = false
	_sled.add_child(_bubble)
	_bubble.position = Vector3(0, 1.0, 0)
	_trail_boost = _sparkler(_sled, Color(1.0, 0.65, 0.2, 1.0), 0.35, 26)
	_trail_boost.position = Vector3(0, 0.5, 1.0)
	_trail_boost.direction = Vector3(0, 0.2, 1)
	_trail_boost.spread = 18.0
	_trail_boost.initial_velocity_min = 4.0
	_trail_boost.initial_velocity_max = 9.0
	_trail_boost.lifetime = 0.5
	_trail_boost.gravity = Vector3.ZERO
	_trail_boost.local_coords = false
	_trail_mult = _sparkler(_sled, Color(1.0, 0.85, 0.35, 1.0), 0.9, 16)
	_trail_mult.position = Vector3(0, 1.0, 0)
	_trail_mult.local_coords = false
	if _tip_pivot == null and cam != null:
		_build_tip()


func _juice(delta: float) -> void:
	_ensure_fx()
	_pop_a = maxf(_pop_a - 2.4 * delta, 0.0)
	for pp in _hud_pops:
		pp["t"] = float(pp["t"]) + delta
	while not _hud_pops.is_empty() and float(_hud_pops[0]["t"]) > 0.85:
		_hud_pops.remove_at(0)
	if _bubble != null:
		_bubble.visible = shield > 0
		if shield > 0:
			var s := 1.0 + 0.05 * sin(_age * 6.0)
			_bubble.scale = Vector3(s, s, s)
		_trail_boost.emitting = _boost_t > 0.0 and not _finished
		_trail_mult.emitting = _mult_t > 0.0 and not _finished
	if _hop_t < 1.0:
		_hop_t = minf(_hop_t + delta / _hop_dur, 1.0)
		var u := _hop_t
		var y := _hop_h * 4.0 * u * (1.0 - u)
		var spin := _hop_spin * (sin(PI * u) if _hop_return else smoothstep(0.0, 1.0, u))
		_sled.global_position.y += y
		_sled.rotate_object_local(Vector3.RIGHT, _hop_pitch * sin(PI * u))
		_sled.rotate_object_local(Vector3.UP, spin)
		var sq := 0.0
		if u > 0.82:
			sq = sin((u - 0.82) / 0.18 * PI) * 0.14
		_sled.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
		_hop_vis_spin = spin
		_hop_vis_pitch = _hop_pitch * sin(PI * u)
	else:
		_hop_vis_spin = 0.0
		_hop_vis_pitch = 0.0
	_view_juice()


var _hop_vis_spin: float = 0.0
var _hop_vis_pitch: float = 0.0


func _view_juice() -> void:
	_hop_cam = (_hop_h * 4.0 * _hop_t * (1.0 - _hop_t) * 0.5) if _hop_t < 1.0 else 0.0
	var ts := _trk_spin if _in_air else _trk_vis_spin
	var tf := _trk_flip if _in_air else _trk_vis_flip
	var grabbing := _in_air and (nod_p < -0.10 or trick_grab_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	if not _fp_now():
		if _in_air or absf(ts) > 0.01 or absf(tf) > 0.01:
			_sled.rotate_object_local(Vector3.RIGHT, tf + (0.3 if grabbing else 0.0))
			_sled.rotate_object_local(Vector3.UP, ts)
	_sled.visible = _sled.visible and not _fp_now()
	if _tip_pivot != null:
		_tip_pivot.visible = _fp_now() and (hurt_t <= 0.0 or int(_age * 14.0) % 2 == 0)
		if _fp_now():
			# Everything eases toward where it should be, so the board seems to glide and slide on the snow instead of snapping: it lags a turn, skids a little sideways
			# when you carve hard, and hums softly with speed.
			var dt := get_process_delta_time()
			var d := wrapf(heading - atan2(_cam_look.x, -_cam_look.y), -PI, PI)
			var right := Vector2(cos(heading), sin(heading))
			var slip := vel.dot(right)
			var sp := clampf(vel.length() / 45.0, 0.0, 1.0)
			_tip_yaw = lerpf(_tip_yaw, -d, 1.0 - exp(-6.0 * dt))
			_tip_roll = lerpf(_tip_roll, -steer * 0.26, 1.0 - exp(-5.0 * dt))
			_tip_x = lerpf(_tip_x, clampf(-slip * 0.012, -0.14, 0.14), 1.0 - exp(-4.0 * dt))
			var hum := (0.008 * sin(_age * 17.0) + 0.005 * sin(_age * 29.0)) * sp if grounded else 0.0
			_tip_pivot.position = Vector3(_tip_x, -1.15 + hum - (0.1 if grabbing else 0.0), 0.0)
			_tip_pivot.rotation = Vector3(tf + _hop_vis_pitch + (0.2 if grabbing else 0.0) + 0.02 * sp, _tip_yaw + ts + _hop_vis_spin, _tip_roll)


## THE WINDING TRAIL (see TrailCurve). On in the browser unless the address has ?straight; tests switch it on to check it.
var bend: bool = OS.has_feature("web") and not str(JavaScriptBridge.eval("window.location.search")).contains("straight")
var bend_strength: float = 1.0
var _cam_strip: Transform3D
var _cam_strip_ok: bool = false


func _process(delta: float) -> void:
	# the camera and the board are worked out on the straight strip exactly as before, then laid onto the trail's curve as the very last thing each frame
	if TrailCurve.on and _cam_strip_ok:
		cam.global_transform = _cam_strip
	super._process(delta)
	if _hi_dbg:
		cam.global_position += Vector3(0.0, 110.0, 0.0)          # ?high: the camera up where a big jump would take it, to look at the edges of the world
		cam.rotation.x -= 0.12
	_juice(delta)
	_psy_tick(delta)
	_trip_tick(delta)
	_exc_tick(delta)
	_dbg_t -= delta
	if _dbg_t <= 0.0 and OS.has_feature("web"):
		_dbg_t = 1.0
		JavaScriptBridge.eval("window.__dbg={draws:%d,objs:%d,prims:%d,fps:%d}" % [int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)), int(Engine.get_frames_per_second())])          # for looking at what a frame costs (read window.__dbg)
	if _journey != null and not _finished:
		_journey.tick(delta)
	_cue_tint = maxf(_cue_tint - delta / 1.2, 0.0)
	_music_tick()
	_sb_tick(delta)
	if not _finished:
		_xp_tick(delta)
	_gspeed = lerpf(_gspeed, clampf(-vel.y / 45.0, 0.0, 1.0), clampf(delta * 2.0, 0.0, 1.0))
	if _m_ground is ShaderMaterial:
		(_m_ground as ShaderMaterial).set_shader_parameter("speed", _gspeed)
	if TrailCurve.on:
		_cam_strip = cam.global_transform
		_cam_strip_ok = true
		cam.global_transform = TrailCurve.xf(_cam_strip)
		_sled.global_transform = TrailCurve.xf(_sled.global_transform)


func _take_buff(b: Dictionary) -> void:
	b["taken"] = true
	_flow_up()
	var n: Variant = b["n"]
	if is_instance_valid(n):
		(n as Node3D).visible = false
	buffs_got += 1
	var t: String = b["t"]
	buff_log[t] = int(buff_log.get(t, 0)) + 1
	var kd: String = b.get("kind", "path")
	got_kind[kd] = int(got_kind.get(kd, 0)) + 1
	var shown := "+%d" % (60 * (2 if _mult_t > 0.0 else 1))
	_gain(60)
	_flash = 0.25
	_trip_add({"donut": 0.30, "mult": 0.22, "boost": 0.08, "shield": 0.08}.get(t, 0.05))
	match t:
		"boost":
			_boost_t = BOOST_S + 0.8 * float(chain_lvl)
			var fwd := Vector2(sin(heading), -cos(heading))
			var sp0 := vel.length()
			vel += fwd * (6.0 + 1.5 * float(chain_lvl))
			if vel.length() > maxf(SPEED_CAP, sp0):
				vel = vel.normalized() * maxf(SPEED_CAP, sp0)
			_toast("BURGER BOOST!", BUFF_COL["boost"])
			Game.sfx(&"buff_boost")
		"shield":
			shield = 1
			_toast("ICE SHIELD!", BUFF_COL["shield"])
			Game.sfx(&"buff_shield")
		"mult":
			_mult_t = MULT_S + 2.0 * float(chain_lvl)
			shown = "x2"
			_toast("SUGAR RUSH x2!", BUFF_COL["mult"])
			Game.sfx(&"buff_mult")
		"donut":
			shown = "+%d" % (220 * (2 if _mult_t > 0.0 else 1))
			_gain(160)
			_toast("DONUT!", BUFF_COL["donut"])
			Game.sfx(&"loot")
	_chain_hit(t)
	_buff_pop(b, shown)
	if is_same(_buff_tgt, b):
		_buff_tgt = {}


func _collect_buffs() -> void:
	if _finished:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 150.0:
			continue
		for b in r["buffs"]:
			for o in b["orbs"]:
				if not o["taken"] and absf(float(o["z"]) - spos.z) < 2.4 and absf(float(o["x"]) - spos.x) < 2.6 and above < 5.0:
					o["taken"] = true
					var on: Variant = o["n"]
					if is_instance_valid(on):
						(on as Node3D).visible = false
					orbs_got += 1
					_flow_touch()
					_gain(int(10.0 * groove))
					if is_instance_valid(on):
						_burst(Vector3(float(o["x"]), (on as Node3D).global_position.y, float(o["z"])), BUFF_COL["orb"], 6, 5.0, 0.45, 0.6)
			if b["taken"]:
				continue
			if b.get("kind", "") == "air":
				if absf(float(b["z"]) - spos.z) < 3.8 and absf(float(b["x"]) - spos.x) < 4.2 and above > 0.8 and absf(float(b["y"]) - spos.y) < 3.6:
					_eat_or_bounce(b)
			elif absf(float(b["z"]) - spos.z) < 3.2 and absf(float(b["x"]) - spos.x) < 3.6 and above < 6.0:
				_eat_or_bounce(b)


func _animate_buffs() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 210.0:
			continue
		for b in r["buffs"]:
			var n: Variant = b["n"]
			if b["taken"] or not is_instance_valid(n):
				continue
			if b.get("moving", false):
				continue
			var nn := n as Node3D
			var ph := float(b["ph"])
			nn.position.y = float(b["y"]) + sin(_age * 2.4 + ph) * 0.35
			var sp: Variant = b.get("spin")
			if sp is Node3D and is_instance_valid(sp):
				(sp as Node3D).rotation.y = _age * (2.8 if b["t"] == "boost" else 1.7) + ph
			var hl: Variant = b.get("halo")
			if hl is Node3D and is_instance_valid(hl):
				var hs := 1.0 + 0.12 * sin(_age * 3.4 + ph)
				(hl as Node3D).scale = Vector3(hs, hs, hs)
			var ex: Array = b.get("extra", [])
			for ei in ex.size():
				if is_instance_valid(ex[ei]):
					var en := ex[ei] as Node3D
					if ei == 0:
						en.rotation.x = _age * 1.4 + ph
					elif ei == 1:
						en.rotation.y = _age * 1.9 + ph
					else:
						en.rotation.z = _age * 2.3 + ph
			var spk: Variant = b.get("sp")
			if spk is CPUParticles3D and is_instance_valid(spk):
				(spk as CPUParticles3D).emitting = absf(float(b["z"]) - spos.z) < 150.0
			var orbs: Array = b["orbs"]
			for oi in orbs.size():
				var o: Dictionary = orbs[oi]
				var on: Variant = o["n"]
				if not o["taken"] and is_instance_valid(on):
					var sc := 0.85 + 0.35 * maxf(sin(_age * 7.0 - float(oi) * 0.9), 0.0)         # a pulse runs along the trail toward the pickup
					(on as Node3D).scale = Vector3(sc, sc, sc)


## Looking at a buff for a moment leans the board toward it: the same dwell as an opening, with a wide look tolerance.
func _update_buff_aim(delta: float) -> void:
	var live := _eye_on and not _finished and aim_enabled and _buff_assist and not _paused and not (trace_on and _tr_phase != 3)
	if not live:
		_buff_tgt = {}
		_buff_cand = {}
		_buff_cand_t = 0.0
		_buff_w = move_toward(_buff_w, 0.0, 6.0 * delta)
		return
	var vs := get_viewport().get_visible_rect().size
	var cx := _aim_cx if _aim_cx >= 0.0 else _cursor_px.x
	var best: Dictionary = {}
	var best_d := 1.0e9
	for k in _rows:
		var r: Dictionary = _rows[k]
		for b in r["buffs"]:
			if b["taken"] or float(b.get("arm", 0.0)) > 0.0:
				continue
			var dz := spos.z - float(b["z"])
			var is_next := String(b["t"]) == _chain_expect_kind()
			if dz < 8.0 or dz > (150.0 if is_next else 95.0) or absf(float(b["x"]) - spos.x) > (0.46 * dz + 6.0 if is_next else 0.34 * dz + 4.0):
				continue
			var wp := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.7 + float(b.get("lift", 0.0)), float(b["z"]))
			if _behind(wp):
				continue
			var dd := absf(_unp(wp).x - cx) / (0.1 * vs.x * (1.6 if is_next else 1.0))
			if is_same(b, _buff_tgt):
				dd *= 0.7
			if dd < best_d:
				best_d = dd
				best = b
	if not best.is_empty() and best_d < 1.0:
		if is_same(best, _buff_tgt):
			_buff_cand = {}
			_buff_cand_t = 0.0
		elif is_same(best, _buff_cand):
			_buff_cand_t += delta
			if _buff_cand_t >= AIM_LINGER * (0.5 if String(best["t"]) == _chain_expect_kind() else 1.0):
				_buff_tgt = best
				_buff_cand = {}
				_buff_cand_t = 0.0
		else:
			_buff_cand = best
			_buff_cand_t = 0.0
	else:
		_buff_cand = {}
		_buff_cand_t = 0.0
		if best_d > 1.6:
			_buff_tgt = {}
	if not _buff_tgt.is_empty() and spos.z - float(_buff_tgt["z"]) < 2.0:
		_buff_tgt = {}                                   # passed it (taken or missed)
	if _buff_tgt.is_empty():
		_buff_w = move_toward(_buff_w, 0.0, 6.0 * delta)
	else:
		_buff_w = move_toward(_buff_w, 1.0, 4.0 * delta)
		_buff_want = clampf((float(_buff_tgt["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)


# --------------------------------------------------------------------------
# Physics: the hill pulls, carving costs speed, the board turns on a short spring, momentum follows through grip
# --------------------------------------------------------------------------
## The safe line toward a barrier: straight from the safe opening of the barrier before it to the safe opening of this one.
## The straight line from the last opening to the safe one (the trail, path_x, wanders either side of it).
func chord_x(row: Dictionary, z: float) -> float:
	var gx := 0.0
	for g in row["gaps"]:
		if g["good"]:
			gx = float(g["x"])
	var span := float(row["pz"]) - float(row["z"])
	if span < 1.0:
		return gx
	return lerpf(float(row["px"]), gx, clampf((float(row["pz"]) - z) / span, 0.0, 1.0))


func path_x(row: Dictionary, z: float) -> float:
	var gx := 0.0
	for g in row["gaps"]:
		if g["good"]:
			gx = float(g["x"])
	var span := float(row["pz"]) - float(row["z"])
	if span < 1.0:
		return gx
	var t := clampf((float(row["pz"]) - z) / span, 0.0, 1.0)
	var x := lerpf(float(row["px"]), gx, t)
	# the trail meanders: one to three bends between the two openings, fading to nothing at both ends so it still leaves and arrives dead on
	var mz: Variant = row.get("mz")
	if mz is Vector3:
		var m: Vector3 = mz
		x += m.x * sin(PI * t) * sin(PI * m.y * t + m.z)
	return clampf(x, -(W_HALF - 8.0), W_HALF - 8.0)


func _auto_steer() -> float:
	var best: Dictionary = {}
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		if best.is_empty() or float(r["z"]) > float(best["z"]):
			best = r
	if best.is_empty():
		return 0.0
	var zl := spos.z + vel.y * 0.5
	return clampf((path_x(best, zl) - (spos.x + vel.x * 0.3)) / 14.0, -0.7, 0.7)


# --------------------------------------------------------------------------
# The board looks after itself: it swerves just enough around a lone tree or rock, and it always commits to a gate in a barrier.
# The skill is choosing the right gate, in time, with your eyes. A wrong choice carries you through that gate (no crash) and you recover for the next one.
# --------------------------------------------------------------------------
const WALL_FAR := 80.0               # the barrier ahead starts pulling you into a gate this far away ...
const WALL_NEAR := 34.0              # ... and pulls with full strength from here
var avoid_enabled: bool = true
var gate_assist: bool = true
var _eye_lp: float = 0.0
## TENTATIVE INTENT. The instant a real look to one side is recognised, the board starts to move that way (provisional); if the eyes stay there it is confirmed, if they go
## back it is cancelled. So the response is immediate but never committed on a flicker.
var _intent_dir: float = 0.0
var _intent_amt: float = 0.0
var _sacc_seen: int = 0
var _sacc_conf_seen: int = 0
var _sacc_ret_seen: int = 0
var assist_level: float = 0.7             # AUTO-HELP, 0..1: how much the board does for you. The eyes say WHICH way (a side, a gate, a moment of attention); the board does the carving, early and smoothly.
var _glide_x: float = 0.0
var _steer_vel: float = 0.0
var _ball_s: float = 0.0
var _dbg_parts: Vector3 = Vector3.ZERO          # tests: what the path guard added this tick (gate pull, obstacle swerve, snowball dodge)
var _glide_row: int = -999
## EARNED HELP. The board only helps while there is evidence you are steering it: a look to one side, a gate or pickup you are looking at, a key or a lean. Look at nothing
## for a moment and the help fades away (it comes back the instant you act), so a hands-off board does not play itself down the hill.
var _engage: float = 1.0
var _idle_t: float = 0.0
var _brake_toast_t: float = 0.0
var ag := {"eyes": 0, "auto": 0, "wrong": 0, "in": 0.0, "as": 0.0, "eng": 0.0, "idle": 0.0}      # who did the driving: gates chosen by you vs the board, steering that came from you vs from help


func _configure_sacc() -> void:
	sacc.jitter = 0.12                  # the look is measured in units of YOUR glance (1 = a full look aside), so these are fractions of one
	sacc.min_amp = 0.28
	sacc.k = 3.0


func _update_intent(delta: float) -> void:
	if not _eye_on:
		_intent_amt = move_toward(_intent_amt, 0.0, delta * 4.0)
		return
	if sacc.accepted != _sacc_seen:
		_sacc_seen = sacc.accepted
		_intent_dir = sacc.last_dir
		_intent_amt = maxf(_intent_amt, 0.55)                     # provisional: start now
	if sacc.retracted != _sacc_ret_seen:
		_sacc_ret_seen = sacc.retracted
		_intent_amt = 0.0                                         # it went back: cancelled
	if sacc.confirmed != _sacc_conf_seen:
		_sacc_conf_seen = sacc.confirmed
		_intent_amt = 1.0                                         # it stayed: confirmed
	else:
		_intent_amt = move_toward(_intent_amt, 0.0, delta * (0.35 if sacc.pending() else 0.7))


## Which way the player means to go, from the most certain evidence down: the gate their eyes hold, a look just made, a look held to one side.
func _intent_pref() -> float:
	if not _aim.is_empty():
		return signf(float(_aim["x"]) - spos.x)
	if _intent_amt > 0.2:
		return _intent_dir
	if absf(_steer_gaze) > 0.25:
		return signf(_steer_gaze)
	return 0.0


func _a() -> float:
	return assist_level * _engage


## How much of the run was you: the share of gates chosen with your eyes, the share of the steering that came from you (not from help), how engaged the help thought you were.
func agency_summary() -> Dictionary:
	var gates := maxi(int(ag["eyes"]) + int(ag["auto"]) + int(ag["wrong"]), 1)
	var steer_tot := maxf(float(ag["in"]) + float(ag["as"]), 0.0001)
	return {"gatesChosen": int(ag["eyes"]), "gatesByBoard": int(ag["auto"]), "gatesWrong": int(ag["wrong"]), "eyesGateShare": snappedf(float(ag["eyes"]) / float(gates), 0.01),
		"steerFromYouShare": snappedf(float(ag["in"]) / steer_tot, 0.01), "engageMean": snappedf(float(ag["eng"]) / maxf(_run_t, 0.1), 0.01), "idleSeconds": snappedf(float(ag["idle"]), 0.1), "assistSetting": assist_level}


func _update_engage(delta: float, key: float, pk: Vector3) -> void:
	var active := absf(key) > 0.05
	if _eye_on:
		active = active or sacc.recent(2.5, _age) or absf(_steer_gaze) > 0.12 or not _aim.is_empty() or _buff_w > 0.2 or not _buff_tgt.is_empty()
	else:
		active = active or absf(pk.x) > 0.1 or absf(GazeProvider.touch_lean) > 0.05 or absf(GazeProvider.touch_steer) > 0.05
	if autopilot or _finished or _run_t < 6.0 or not grounded:
		active = true                                           # the start, the air and the finish line are not a test
	_idle_t = 0.0 if active else _idle_t + delta
	var want := clampf(1.0 - (_idle_t - 2.5) / 3.0, 0.2, 1.0)          # a quiet stretch costs nothing; a long one leaves a fifth of the help
	_engage = move_toward(_engage, want, delta * (4.0 if want > _engage else 0.6))

var _wall_gap: Dictionary = {}
var _wall_row_j: int = -999
var _wall_w: float = 0.0             # how hard the nearest barrier pulls (0..1), for the HUD and the report
var _swerve_s: float = 0.0           # the sideways shift the board is making right now (m)
var swerves: int = 0
var _swerving: bool = false
var _swerve_idle: float = 0.0
var wrong_gates: int = 0             # barriers passed through a gate other than the one the eyes had latched


## Smallest sideways shift (m) that clears every lone tree/rock closer than max_t seconds ahead, and the time to the nearest of them.
func _free_shift(max_t: float, sp: float, above: float, skip_wall: bool = false) -> Vector2:
	var cs := PackedFloat32Array()
	var rs := PackedFloat32Array()
	var tmin := 9.0
	var look := sp * max_t
	for jj in _rows:
		var rj: Dictionary = _rows[jj]
		if spos.z - look > float(rj["zmax"]) or spos.z + 3.0 < float(rj["zmin"]):
			continue
		var rzz := float(rj["z"]) if rj["has_row"] else 1.0e9
		var obs: PackedFloat32Array = rj["obs"]
		var i := 0
		while i < obs.size():
			var ox := obs[i]
			var oz := obs[i + 1]
			var orad := obs[i + 2]
			var okind := obs[i + 3]
			i += 4
			if skip_wall and rj["has_row"] and absf(oz - rzz) < 7.0:
				continue                                         # the long look-ahead is for lone trees and rocks; a barrier is for the gate you chose
			var dz := spos.z - oz
			if dz < -1.5 or dz > look:
				continue
			if above > (7.0 if okind < 0.5 else 3.0) + 0.5:
				continue                                         # in the air above it
			var t := maxf(dz, 0.0) / sp
			var rr := orad + SLED_R + 1.0
			var c := spos.x + vel.x * t - ox
			if absf(c) >= rr + 5.0:
				continue
			cs.append(c)
			rs.append(rr)
			if absf(c) < rr:
				tmin = minf(tmin, t)
	if tmin > 8.0:
		return Vector2(0.0, 9.0)
	var best := 1.0e9
	var best_cost := 1.0e9
	var pref := _intent_pref()
	var cand := PackedFloat32Array([0.0])
	for k in cs.size():
		cand.append(-cs[k] - rs[k] - 0.05)
		cand.append(-cs[k] + rs[k] + 0.05)
	for s in cand:
		if absf(spos.x + s) > W_HALF - 3.0:
			continue
		var ok := true
		for k in cs.size():
			if absf(cs[k] + s) < rs[k] - 0.001:
				ok = false
				break
		var cost := absf(s) + (2.5 if (pref != 0.0 and absf(s) > 0.05 and signf(s) != pref) else 0.0)          # a swerve goes the way you mean to go when it can
		if ok and cost < best_cost:
			best = s
			best_cost = cost
	return Vector2(0.0 if best > 1.0e8 else best, tmin)


## Returns the steering added by the avoidance and gate commitment, and nudges the board sideways at the last moment if a swerve is still owed.
func _guard_path(delta: float, s_in: float) -> float:
	_swerve_s = 0.0
	_wall_w = 0.0
	if _finished or hurt_t > 0.0:
		_slide_v = 0.0                                              # a crash stops the sideways slide for good: it must not carry on at full speed when the board gets up
		return 0.0
	var add := 0.0
	if trail:
		# the board rides the trail by itself: it steers for the middle of the trail a little way ahead, leaning to the passing side of the next pole. Your look is added on
		# top, so you choose how close to shave each pole, and a look held hard to one side will still take you off the trail.
		var spd_t := maxf(-vel.y, MIN_SPEED)
		# two parts: point the board the way the trail is heading a moment ahead (so it turns WITH the bend instead of chasing it), and correct for being off the line
		var zf := spos.z - spd_t * 0.4
		var ff := atan((trail_x(zf - 2.0) - trail_x(zf + 2.0)) / 4.0) / THETA_MAX
		var tx := trail_x(spos.z - spd_t * 0.5)
		var np := _next_pole()
		if not np.is_empty() and spos.z - float(np["z"]) < 55.0:
			# the pole stands 5 m to the inside of the turn. Left alone the board passes it wide, which earns nothing; a look toward the pole cuts in to shave it.
			var pv := pick_override if pick_override != 0.0 else s_in
			if absf(pv) > 0.14 and signf(pv) == -float(np["e"]):
				np["want"] = float(np.get("want", 0.0)) + delta
			if float(np.get("want", 0.0)) > 0.15:
				tx = float(np["x"]) + float(np["e"]) * 1.5
		var pkf := _trail_pick(delta, s_in)
		var slide_steer := 0.0
		var sliding := false
		if not winding:
			tx += (0.0 if _zoned() else clampf(eye_now(), -1.0, 1.0) * FEAT_OFF * 1.15)          # the board sits where you look across the slope: far left of the screen is the far left line
		if not pkf.is_empty():
			tx = _feat_x(pkf, clampf(spos.z - spd_t * 0.5, float(pkf["zb"]), float(pkf["za"]) + 40.0))          # the rail or loot line you looked at: the board carves over to it
			# a look that picked it always gets there: whatever the carve cannot cover in the time left, the board slides across
			if _rail.is_empty():
				var gx := _feat_x(pkf, clampf(spos.z, float(pkf["zb"]), float(pkf["za"])))
				var t_left := maxf((spos.z - float(pkf["za"])) / spd_t - 0.25, 0.04)
				var need := gx - spos.x
				var rate := clampf(absf(need) / t_left, 0.0, SLIDE_MAX)
				# eased in and out: the sideways speed builds up and dies away over a fraction of a second instead of starting and stopping at once
				var v_want := signf(need) * rate if (rate > 3.0 or spos.z <= float(pkf["za"])) else 0.0
				_slide_v += (v_want * (0.55 if _switch_slow > 0.0 else 1.0) - _slide_v) * (1.0 - exp(-delta / (((0.35 if _switch_slow > 0.0 else 0.2) if t_left > 0.5 else 0.12) * grip_lag)))
				if _slide_v * need > 0.0:
					_slide_v = signf(_slide_v) * minf(absf(_slide_v), absf(need) / 0.14)          # and settles onto the line instead of stopping dead on it
					spos.x += signf(need) * minf(absf(need), absf(_slide_v) * delta)
				else:
					spos.x += _slide_v * delta                         # the choice changed: the old sideways speed dies away over a few frames, it does not stop dead
				if absf(_slide_v) > 0.5:
					sliding = true
					slide_steer = clampf(atan2(_slide_v, spd_t) / THETA_MAX, -0.5, 0.5)          # the board points the way it is actually going: no second controller pulling against the slide
		if pkf.is_empty():
			_slide_v = 0.0
		if not np.is_empty() and spos.z - float(np["z"]) < 32.0 and absf(s_in) < 0.6:
			var pe := float(np["e"])                                   # close to a pole the line never drifts to its wrong side by itself: only a hard look takes you there
			if (tx - float(np["x"])) * pe < 1.4:
				tx = float(np["x"]) + pe * 1.4
		var t_want := clampf(ff + (tx - (spos.x + vel.x * 0.5)) / 11.0, -1.0, 1.0)
		if trike:
			t_want = clampf(t_want + 0.3 * sin(_age * 2.7) * (0.5 + 0.5 * sin(_age * 0.9 + 1.0)), -1.0, 1.0)          # a trike weaves: the eyes have to keep correcting it
		if sliding:
			t_want = clampf(ff + slide_steer, -0.6, 0.6)
		# the edge of the trail: the nearer the trees, the harder the board leans back in. Only a look held hard at the forest gets past it.
		var e_off := (spos.x + vel.x * 0.45) - trail_x(spos.z - spd_t * 0.45)
		var e_over := absf(e_off) - maxf(8.0, FEAT_OFF + 4.0)
		if e_over > 0.0 and absf(s_in) < 0.8:
			t_want = clampf(t_want - signf(e_off) * clampf(e_over / 3.0, 0.0, 1.0) * 1.3, -1.0, 1.0)
		add += t_want * lerpf(0.75, 1.0, _a()) * (1.0 - 0.4 * absf(s_in))
	# 1) the barrier ahead: commit to a gate
	var row: Dictionary = {}
	var bd := 1.0e9
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r["has_row"]:
			continue
		var d := spos.z - float(r["z"])
		if d < -6.0 or d >= bd:
			continue
		bd = d
		row = r
	var gate_done := false
	var spd_w := maxf(-vel.y, MIN_SPEED)
	var wall_far := clampf(spd_w * 2.4 * (1.0 + 0.5 * _a()), WALL_FAR, 230.0)       # the hill speeds up, so the pull starts earlier in metres, not in seconds
	var wall_near := clampf(spd_w * 1.0, WALL_NEAR, 70.0)
	if gate_assist and not row.is_empty() and bd <= wall_far:
		if int(row["j"]) != _wall_row_j:
			_wall_row_j = int(row["j"])
			_wall_gap = {}
		var tgt: Dictionary = {}
		var eyes_chose := not _aim.is_empty() and is_same(_aim_row, row)
		if eyes_chose:
			tgt = _aim
			row["eyes_gap"] = _aim                            # remembered for scoring: this is the gate YOU chose
		elif row.has("eyes_gap") and not (row["eyes_gap"] as Dictionary).is_empty():
			tgt = row["eyes_gap"]                             # your eyes let go inside the last 14 m (the tracker cannot resolve it): keep the gate you chose
		else:
			var px := spos.x + vel.x * 0.7 + s_in * 4.0
			var bd2 := 1.0e9
			for g in row["gaps"]:
				var dd := absf(float(g["x"]) - px) * (0.85 if is_same(g, _wall_gap) else 1.0)
				if _eye_on and absf(_steer_gaze) > 0.12 and signf(float(g["x"]) - spos.x) == signf(_steer_gaze):
					dd *= lerpf(1.0, 0.3, _a())                  # a look to one side is a strong vote for the gates on that side, however far they are
				if _intent_amt > 0.2 and signf(float(g["x"]) - spos.x) == _intent_dir:
					dd *= lerpf(1.0, 0.35, _intent_amt)          # a look to one side is a vote for the gates on that side, even when it is too rough to pick one
				if dd < bd2:
					bd2 = dd
					tgt = g
			_wall_gap = tgt
		# a gate too far sideways to reach in the distance that is left cannot be flown to (the course itself never asks for more than ~0.3 m sideways per metre):
		# carry on through the reachable gate nearest to it instead
		var reach_m := 0.38 * maxf(bd - 6.0, 2.0) + 4.0
		var from_x := spos.x + vel.x * 0.3
		if absf(float(tgt["x"]) - from_x) - float(tgt["w"]) * 0.3 > reach_m:
			var alt: Dictionary = {}
			var alt_d := 1.0e9
			for g in row["gaps"]:
				if absf(float(g["x"]) - from_x) - float(g["w"]) * 0.3 > reach_m:
					continue
				var ad := absf(float(g["x"]) - float(tgt["x"]))
				if ad < alt_d:
					alt_d = ad
					alt = g
			if alt.is_empty():
				alt_d = 1.0e9
				for g in row["gaps"]:
					var ad2 := absf(float(g["x"]) - from_x)
					if ad2 < alt_d:
						alt_d = ad2
						alt = g
			tgt = alt
		var u := clampf((wall_far - bd) / (wall_far - wall_near), 0.0, 1.0)
		var w := maxf(u * _engage, 0.35 * _a() * clampf((wall_far - bd) / 30.0, 0.0, 1.0))          # with help on, the board begins to commit early and gently; with no sign of you, it does not choose a gate for you
		if eyes_chose:
			w = maxf(carve_assist * _assist_conf() * _aim_w, w)
		# close to the barrier the board commits: fully to a gate that is yours, and as far as the help level allows to one it picked for itself
		var mine := eyes_chose or (row.has("eyes_gap") and is_same(row["eyes_gap"], tgt))
		var urgency := clampf((2.5 - bd / maxf(spd_w, 1.0)) / 1.7, 0.0, 1.0)
		w = maxf(w, urgency * (1.0 if mine else maxf(_engage, _a())))
		_wall_w = w
		# the aim point glides to the chosen gate instead of jumping when the choice changes: no jerk when the eyes flick between two gates
		if _glide_row != int(row["j"]):
			_glide_row = int(row["j"])
			_glide_x = spos.x + vel.x * 0.45
		# the aim point glides to the chosen gate (no jerk when the choice flips), but never slower than it takes to ARRIVE: a gate chosen late and far off must still be reached
		var aim_x := float(tgt["x"])
		if bool(tgt.get("good", false)) and bd > 34.0 and row.get("mz") is Vector3:
			aim_x = path_x(row, spos.z - clampf(spd_w * 1.3, 20.0, 48.0))          # heading for the opening the trail leads to: follow the trail's bends, a little ahead of the board
		var glide_need := absf(aim_x - _glide_x) / maxf(bd / spd_w - 0.7, 0.25)
		_glide_x = move_toward(_glide_x, aim_x, maxf(lerpf(40.0, 14.0, _a()), glide_need * 1.5) * delta)
		var t_gate := bd / maxf(spd_w, 1.0)
		var want := clampf((_glide_x - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)
		# too far off to make the gap with a normal carve: give up speed instead of the line (a friendly brake, never a crash)
		var miss := absf(float(tgt["x"]) - spos.x) - float(tgt["w"]) * 0.35
		if _a() > 0.05 and miss > 0.0 and bd < 95.0:
			var need := miss / (maxf(bd - 4.0, 1.0) / spd_w)
			if need > 11.0:
				vel *= 1.0 - _a() * clampf((need - 11.0) / 14.0, 0.0, 1.0) * 0.8 * delta
				if _brake_toast_t <= 0.0 and need > 16.0:
					_brake_toast_t = 4.0
					_toast("EASING OFF TO MAKE IT", Color(0.8, 0.9, 1.0))          # the help says so when it does more than a carve
		var yield_to_buff := _buff_w * clampf((bd - (wall_near + 8.0)) / 10.0, 0.0, 1.0)       # a buff you are looking at wins until the barrier is close
		add += w * want * (1.0 - (0.3 if mine else 0.6) * absf(s_in)) * (1.0 - 0.85 * yield_to_buff)
		# The last half second is not left to chance: if the board is still set to clip the edge of the opening it is heading for, the snow carries it the final metre or two
		# sideways (fully for a gate chosen with your eyes, even if your look has since moved on; as far as the help level allows for one the board picked). No steering kick.
		var slide := 1.0 if mine else maxf(_engage, _a()) * w
		if slide > 0.05 and bd > 0.5 and t_gate < 0.7:
			var xp := spos.x + vel.x * t_gate
			var over := absf(xp - float(tgt["x"])) - maxf(float(tgt["w"]) * 0.5 - 2.0, 0.8)
			if over > 0.0 and over < 5.0:
				spos.x += signf(float(tgt["x"]) - xp) * minf(over, 4.5 * slide * delta)
		gate_done = true
	if not gate_done:
		add += carve_assist * _assist_conf() * _aim_w * _aim_want * (1.0 - 0.6 * absf(s_in))
	if _buff_w > 0.0 and not _buff_tgt.is_empty() and not trail:          # on a winding trail a straight line to a treat cuts through the forest: there the side-line pick does this job
		add += _buff_w * _buff_want * (1.0 - 0.6 * absf(s_in))
	# 2) a lone tree or rock on the way: swerve by just what is needed
	var av := 0.0
	if avoid_enabled and not trail:                      # on a forest trail the tree lines ARE the course: following the trail is the avoidance
		var sp := maxf(-vel.y, 6.0)
		var above := spos.y - terrain_h(spos.x, spos.z)
		var far := _free_shift(clampf(95.0 / sp, 1.6, 2.4), sp, above, true)
		if absf(far.x) > 0.001:
			# the same for a tree or rock ahead: the angle that carries the board the needed distance sideways in the time left, with a margin, instead of a fixed share of full lock
			var av_v := absf(far.x) / maxf(far.y - 0.2, 0.3)
			av = signf(far.x) * clampf(asin(clampf(av_v / maxf(vel.length(), 1.0), 0.0, 0.85)) / THETA_MAX * 1.35, minf(absf(far.x) / 12.0, 0.3), 0.9)
			_swerve_idle = 0.0
			if not _swerving:
				_swerving = true
				swerves += 1
			var near := _free_shift(0.55, sp, above)
			if absf(near.x) > 0.001:
				var nudge := near.x * clampf(delta / maxf(near.y, 0.1), 0.0, 1.0)
				var nmax := lerpf(5.0, 12.0, _engage)
				nudge = clampf(nudge, -nmax * delta, nmax * delta)
				spos.x += nudge
				_swerve_s = nudge / maxf(delta, 0.0001)
		else:
			_swerve_idle += delta
			if _swerve_idle > 0.6:
				_swerving = false
	# a snowball dodge eases in and out (it used to switch on and off within one tick, which threw the nose sideways and back)
	_ball_s += (_ball_evade() - _ball_s) * (1.0 - exp(-delta / 0.18))
	_dbg_parts = Vector3(add, av, _ball_s)
	if not grounded:
		add *= 0.3                                         # nothing to carve against in the air: do not wind the steering up for the landing
	return add + av + _ball_s * (1.0 - 0.5 * absf(s_in))


var _rs: float = 1.0                 # 3D render scale: the game and the face model share one GPU, so the game gives up pixels before the tracker starves
var _rs_t: float = 0.0
var _rs_pin: float = -1.0            # &rs=0.7 pins it
var _rs_off: bool = true             # the automatic governor is opt-in (&rs=auto): resizing the 3D buffer can itself hitch, and on the one laptop tested it bought nothing
var _rs_drop_fps: float = 0.0
# where a game frame goes (milliseconds, smoothed): so a slow game can be told apart from a slow tracker
var _pf_phys: float = 0.0
var _pf_hud: float = 0.0
var _pf_focus: float = 0.0


func _pf(cur: float, t0: int) -> float:
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	return ms if cur <= 0.0 else lerpf(cur, ms, 0.05)


func _render_governor(delta: float) -> void:
	if _rs_pin > 0.0 or DisplayServer.get_name() == "headless":
		return
	_rs_t += delta
	if _rs_t < 1.5:
		return
	_rs_t = 0.0
	var f := float(Engine.get_frames_per_second())
	if _rs_off:
		return
	if f < 46.0:
		if _rs_drop_fps > 0.0 and f < _rs_drop_fps * 1.12:
			# the last drop in resolution bought less than 12% more frames: the game is not pixel-bound, so stop trading looks for nothing
			_rs = 1.0
			_rs_off = true
			RScale.set_scale(get_viewport(), 1.0)
			_log_ev("render scale did not raise the frame rate (%d fps): back to full" % int(f))
			return
		_rs_drop_fps = f
		_rs = maxf(_rs - 0.1, 0.5)
	elif f > 57.0:
		_rs = minf(_rs + 0.05, 1.0)
		_rs_drop_fps = 0.0
	RScale.set_scale(get_viewport(), _rs)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	var vp := get_viewport()
	if vp != null:
		RScale.set_scale(vp, 1.0)


## A phone held upright: the game waits and asks for it sideways. Nothing is learned meanwhile (the eye zones are cleared every frame), so the middle, left and right the
## tracker learns are the ones for the way the phone is really held. Turning it back makes the learning start fresh.
var _portrait_hold: bool = false
var _coarse: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches")) == "true"


func _portrait_check() -> bool:
	var vs := get_viewport().get_visible_rect().size
	_portrait_hold = _coarse and vs.y > vs.x * 1.05
	if _portrait_hold:
		GazeProvider.kit.zones = {}
		GazeProvider.kit._zauto.clear()
		GazeProvider.kit._zh.clear()
	return _portrait_hold


func _physics_process(delta: float) -> void:
	if not _warmed:
		_warm_shaders()
	if _paused or _warming or _portrait_check():
		return
	if _calib_tick(delta):
		return
	var pf0 := Time.get_ticks_usec()
	_render_governor(delta)
	_age += delta
	var ns := GazeProvider.nod_state(delta)
	nod_p = ns.x
	nod_v = ns.y
	var pk := GazeProvider.peek_offset(delta)
	var key := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	_tick_buffs(delta)
	_eye_on = _eye_mode()
	_update_engage(delta, key, pk)
	_update_intent(delta)
	_clock += delta
	if _finished:
		_end_t += delta
	else:
		_run_t += delta
	var dist := maxf(-spos.z, 0.0)
	var prog := clampf(dist / PULL_RAMP, 0.0, 1.0)
	# steering: your gaze when the eyes are on (a head lean must not steer), else a lean, plus keys; a latched opening adds a gentle pull
	var eye_raw := _guard_gaze(_steer_gaze, delta) if _eye_on else 0.0
	# The board must not twitch with the eyes. A small dead zone (a resting eye is never exactly still), then a low-pass: it follows where you MEAN to go, not every flicker.
	# The stronger the help, the longer it averages (0.1 s with none, about 0.4 s at full strength).
	var eye_dz := signf(eye_raw) * maxf(absf(eye_raw) - 0.06, 0.0) / 0.94
	var lp_tau := lerpf(0.08, 0.30, assist_level)
	lp_tau *= lerpf(1.0, 0.4, smoothstep(0.35, 0.7, absf(eye_dz)))          # a small wobble is averaged away; a big, deliberate look gets through quickly
	_eye_lp += (eye_dz - _eye_lp) * (1.0 - exp(-delta / lp_tau))
	var eye_s := _eye_lp
	# A webcam gaze is a slow, noisy signal (a few percent of the screen of jitter), so the eyes CHOOSE the opening and the board carves to it; free steering from the
	# raw look only trims (0.6 with nothing chosen, 0.15 once an opening is locked).
	var eye_gain := lerpf(0.7, 0.35, _aim_w) * lerpf(1.0, 0.6, _a() * _aim_w)
	# Read as left / middle / right, the eyes CHOOSE and do not steer: the board holds its line down the trail however the eyes move, and turns only for what was chosen.
	var eyes_pick_only := trail and pick_override == 0.0 and _zoned()
	var s_in := key + (0.0 if eyes_pick_only else (eye_s * eye_gain if _eye_on else clampf(pk.x / 1.8, -1.0, 1.0)))
	if _eye_on and not eyes_pick_only:
		s_in += _intent_dir * _intent_amt * 0.38                     # the board starts toward a look at once; the settled gaze and the chosen gate take over
	if false:
		# the moment a real look to one side is recognised the board starts turning that way, then the settled gaze takes over: response without waiting for the smoothed signal
		pass
	if autopilot:
		s_in = _auto_steer()
	s_in = clampf(s_in, -1.0, 1.0)
	_s_in_now = s_in
	steer = clampf(s_in + _guard_path(delta, s_in), -1.0, 1.0)
	if grounded and absf(s_in) < 0.3 and _aim.is_empty():
		steer = clampf(steer - 0.12 * clampf(vel.x / 12.0, -1.0, 1.0), -1.0, 1.0)          # coming back to the middle: damp the sideways speed so it does not ring
	_brake_toast_t = maxf(_brake_toast_t - delta, 0.0)
	if not _finished and grounded:
		ag["in"] = float(ag["in"]) + absf(s_in) * delta
		ag["as"] = float(ag["as"]) + absf(steer - s_in) * delta
		ag["eng"] = float(ag["eng"]) + _engage * delta
		if _idle_t > 2.5:
			ag["idle"] = float(ag["idle"]) + delta
	if _finished:
		steer = 0.0
	# The steering eases in and eases out (a critically damped spring), so the board leans into a turn instead of snapping to it: a simple follow-with-a-speed-limit started and
	# stopped abruptly, which is what read as waggle. About 0.35 s to get most of the way to a new line with help on, 0.25 s without.
	var st_w := lerpf(13.0, 9.0, _a()) * (steer_rate / 9.0)
	var st_acc := st_w * st_w * (steer - _steer_s) - 2.0 * st_w * _steer_vel
	_steer_vel += st_acc * delta
	_steer_s = clampf(_steer_s + _steer_vel * delta, -1.0, 1.0)
	steer = _steer_s
	var tuck := nod_p < -0.10 and not _finished
	tucking = tuck and grounded
	braking = false
	gliding = false
	var theta_t := steer * THETA_MAX * (1.0 if grounded else 0.4)          # in the air the board stays close to the way it is flying, so it lands along its path and does not whip
	heading += (theta_t - heading) * (1.0 - exp(-delta / (0.22 if grounded else 0.4)))
	var fwd := Vector2(sin(heading), -cos(heading))
	var right := Vector2(cos(heading), sin(heading))
	var prev := spos
	var g := _grad(spos.x, spos.z)
	if grounded:
		var spd := vel.length()
		if spd < MIN_SPEED and not _finished:
			vel += fwd * (MIN_SPEED - spd) * 1.2 * delta        # never stalls: always pushes the way the board points, never along a sideways or backward slide
		vel += -G * g / (1.0 + g.length_squared()) * delta
		var sp := vel.length()
		var drag := DRAG * _drag_mul * (0.55 if tucking else 1.0) * lerpf(1.0, 0.5, prog) * (0.3 if _boost_t > 0.0 else 1.0)          # less drag the further you go: the hill keeps pulling harder
		if _boost_t > 0.0 and spd < SPEED_CAP:
			vel += fwd * 7.0 * delta                                  # a boost pushes along where the board points
		var fr := 0.22 + (3.0 if _finished else 0.0)
		if _finished:
			vel *= exp(-1.3 * delta)
		if sp > 0.01:
			var dec := minf((fr + drag * sp * sp) * delta, sp)
			vel -= vel / sp * dec
		if trail and not _finished:
			var vcap := TRAIL_VMAX * _spd_k + (8.0 if _boost_t > 0.0 else 0.0) + (9.0 if _vx_active_t > 0.0 else 0.0)          # a relaxing speed: the hill alone does not run away with it, a boost or a swirl adds a bit
			if sp > vcap:
				vel -= vel / sp * (sp - vcap) * 1.5 * delta
		var old_sp := vel.length()
		var along := vel.dot(fwd)
		var lat := vel.dot(right)
		var lat_new := lat * exp(-GRIP * _grip_mul * (0.75 if tucking else 1.0) * delta)
		along += absf(lat - lat_new) * 0.6 * signf(along if absf(along) > 0.01 else 1.0)          # a carve costs some speed
		vel = fwd * along + right * lat_new
		if vel.length() > old_sp:
			vel = vel.normalized() * old_sp
	else:
		var sp2 := vel.length()
		if sp2 > 0.01:
			vel -= vel / sp2 * minf(DRAG * 0.4 * sp2 * sp2 * delta, sp2)
		vel += right * steer * 3.0 * delta
		if trail and not _finished:
			var a_high := spos.y - terrain_h(spos.x, spos.z) - 34.0
			if a_high > 0.0 and vy > -12.0:
				vy -= minf(a_high * 6.0, 30.0) * delta                    # a trail ramp is a hop of a few metres: anything that starts to go higher is pulled back down
			var a_tz := spos.z + vel.y * 0.7                                 # a jump lands you on the trail: in the air the board drifts toward where the trail will be
			var lo_t := (eye_now() * FEAT_OFF * 0.8) if (_zoned() and air_t > 0.2) else 0.0          # in the air the eyes choose where you come down: left lane, the middle or the right lane
			_land_off += (lo_t - _land_off) * (1.0 - exp(-6.0 * delta))
			vel.x += clampf((trail_x(a_tz) + _land_off - (spos.x + vel.x * 0.7)) * 2.2, -16.0, 16.0) * delta
		air_t += delta
	if trail and not _finished:
		# slalom pace: the forest trail turns every 95 m, so the hill is held to about 85-105 km/h (it climbs a little as the run goes on)
		var cap := TRAIL_SPEED * _spd_k + 6.0 * prog + (4.0 if _boost_t > 0.0 else 0.0) + (9.0 if _vx_active_t > 0.0 else 0.0)
		if mode == "race":
			cap += 0.5 * minf(float(chain), float(FLOW_MAX))          # in a race, flow IS pace: every clean pole lets the hill run a little faster
		var spn := vel.length()
		if spn > cap:
			vel *= 1.0 - minf(1.4 * delta * (spn - cap) / cap * 3.0, 0.5)
	if not _finished:
		vel.y = minf(vel.y, -3.0)          # the hill always carries you down it: a slide off a tree can never turn into a run uphill
	spos.x += vel.x * delta
	spos.z = minf(spos.z + vel.y * delta, 0.0)
	if absf(spos.x) >= W_HALF - 2.5:
		spos.x = clampf(spos.x, -(W_HALF - 2.5), W_HALF - 2.5)
		vel.x = -vel.x * 0.2
	var gh := terrain_h(spos.x, spos.z)
	var gvy := (gh - _gh_prev) / maxf(delta, 0.0001)
	if grounded:
		var vg := (gh - prev.y) / maxf(delta, 0.0001)
		if vg < vy - G * delta - 0.4:
			grounded = false
			air_t = 0.0
			vy = vy - G * delta
			spos.y = prev.y + vy * delta
		else:
			spos.y = gh
			vy = minf(vg, jump_launch) if trail else vg
	else:
		vy -= G * delta
		spos.y += vy * delta
		if spos.y <= gh:
			_land(maxf(gvy - vy, 0.0), gh, gvy)
	_gh_prev = gh
	_feat_tick(delta)
	_realm_tick(delta)
	_collide()
	_collect_buffs()
	_update_eye_actions(delta)
	_update_pads()
	_toys_tick(delta)
	_pill_tick(delta)
	_update_ramps(delta)
	_vortex_drive(delta)
	_glint_tick(delta)
	_chain_tick(delta)
	_update_balls(delta)
	_update_tricks(delta, key, pk)
	_animate_buffs()
	_update_rows()
	_slalom_tick()
	_goals_tick()
	_diag_tick(delta)
	_called_tick(delta)
	if not _finished and spos.z <= finish_z:
		_finish()
	if _gate_open and int(float(_next_j) * ROW_GAP) < int(-spos.z + AHEAD):
		_gen_sliced = true
		_gen_segment(_next_j)
		_gen_sliced = false
		_next_j += 1
	_chunk_pump()
	_cleanup()
	_pf_phys = _pf(_pf_phys, pf0)


var pm_view: float = 0.0                                   # ?pmview=0.3 : phone tilt gently turns the view (experimental, sign may need flipping with a negative value)
var ghost := false                                       # tests only: ride through obstacles


func _collide() -> void:
	if hurt_t > 0.0 or _finished or ghost:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for jj in _rows:
		var rj: Dictionary = _rows[jj]
		if spos.z < float(rj["zmin"]) or spos.z > float(rj["zmax"]):
			continue
		var obs: PackedFloat32Array = rj["obs"]
		var i := 0
		while i < obs.size():
			var ox := obs[i]
			var oz := obs[i + 1]
			var orad := obs[i + 2]
			var okind := obs[i + 3]
			i += 4
			var dx := spos.x - ox
			var dz := spos.z - oz
			if dx * dx + dz * dz < (orad + SLED_R) * (orad + SLED_R):
				var limit := 7.0 if okind < 0.5 else 3.0
				if above < limit:
					var v_pre := vel
					var n := Vector2(dx, dz).normalized()
					spos.x = ox + n.x * (orad + SLED_R + 0.1)
					spos.z = oz + n.y * (orad + SLED_R + 0.1)
					if grounded:
						spos.y = terrain_h(spos.x, spos.z)
						_gh_prev = spos.y
					vel = vel.slide(n) * 0.4
					var wallhit: bool = rj["has_row"] and (absf(oz - float(rj["z"])) < 7.0 or float(ZONES[String(rj.get("zone", "rush"))]["walls"]) > 0.0)          # a barrier, or the lined corridor of a tunnel or bend
					_crash("TREE!" if okind < 0.5 else "ROCK!", "%s swerving %s wallPull %.2f latched %s speed %.0f sideways %.1f" % [("WALL:" if wallhit else "SINGLE:") + String(rj.get("zone", "?")), str(_swerving), _wall_w, str(not _aim.is_empty()), v_pre.length(), v_pre.x])
					_hit_fx(okind, ox, oz, orad, v_pre.length())
					if wallhit:
						hurt_t = 2.2          # still inside the barrier band: enough grace to be carried out of it instead of into the next tree
					return


## What a collision looks and sounds like. A tree throws a puff of needles, bark and shaken-off snow. A rock RINGS: a gong, ripples in the air, and the rock itself
## shivers like a struck bell.
func _hit_fx(kind: float, ox: float, oz: float, orad: float, speed: float) -> void:
	var gy := terrain_h(ox, oz)
	if kind < 0.5:
		var p := Vector3(ox, gy + 2.2, oz)
		var k := clampf(speed / 40.0, 0.5, 1.4)
		_burst(p, Color(0.1, 0.48, 0.2), int(46.0 * k), 8.0, 1.0, 0.8, Vector3.UP, 150.0, -4.0)
		_burst(p, Color(0.42, 0.28, 0.14), int(20.0 * k), 6.0, 0.8, 0.7, Vector3.UP, 120.0, -6.0)
		_burst(p + Vector3(0, 1.4, 0), Color(1, 1, 1), int(40.0 * k), 5.0, 1.3, 1.5, Vector3.UP, 100.0, -2.5)
		Game.sfx(&"thwack")
		GazeProvider.pm.buzz([35])
		_shake = maxf(_shake, 0.5)
	else:
		var p2 := Vector3(ox, gy + orad, oz)
		Game.sfx(&"gong")
		GazeProvider.pm.buzz([40, 50, 25, 50, 15, 50, 8])              # rings out and fades, like the bell
		_burst(p2, Color(0.8, 0.9, 1.0), 26, 9.0, 0.6, 0.6, Vector3.UP, 180.0, -7.0)
		_ring(p2, Color(0.8, 0.92, 1.0), 7.0, 0.8, true)
		get_tree().create_timer(0.18).timeout.connect(func() -> void: _ring(p2, Color(0.8, 0.92, 1.0), 9.0, 0.9, true))
		get_tree().create_timer(0.36).timeout.connect(func() -> void: _ring(p2, Color(0.8, 0.92, 1.0), 11.0, 1.0, true))
		_ring_bell(ox, oz, orad)
		_toast("DONNNG!", Color(0.85, 0.93, 1.0))
		_shake = maxf(_shake, 0.6)


## A glowing copy of the rock that wobbles and fades: the struck bell.
func _ring_bell(ox: float, oz: float, orad: float) -> void:
	if _m_rock == null:
		return
	var n := MeshInstance3D.new()
	n.mesh = _m_rock
	var mat := Mats.lit()
	mat.albedo_color = Color(0.75, 0.82, 0.95)
	mat.metallic = 0.9
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.65, 1.0)
	mat.emission_energy_multiplier = 1.2
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	var sc := orad / 1.3
	var base := Vector3(sc, sc * 1.1, sc)
	_place(n, Vector3(ox, terrain_h(ox, oz) + 0.7 * sc * 1.1, oz))
	n.scale = base * 1.04
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		if is_instance_valid(n):
			var amp := (1.0 - u) * 0.09
			var w := sin(u * 38.0)
			n.scale = base * Vector3(1.04 + amp * w, 1.04 - amp * w * 0.7, 1.04 + amp * w)
			mat.emission_energy_multiplier = 1.2 * (1.0 - u), 0.0, 1.0, 0.9)
	tw.tween_callback(n.queue_free)


func _crash(msg: String, ctx: String = "", mol: int = -1) -> void:
	if hurt_t > 0.0 or _finished:
		return
	GazeProvider.pm.buzz([90, 40, 60])
	if shield > 0:
		shield = 0
		hurt_t = 0.8
		_flash = 0.35
		_shake = 0.5
		_toast("SHIELD BROKE", BUFF_COL["shield"])
		var bp := spos + Vector3(0, 1.2, 0)
		_burst(bp, BUFF_COL["shield"], 44, 12.0, 0.8, 1.0)
		_ring(bp, BUFF_COL["shield"], 8.0, 0.4, true)
		Game.sfx(&"hurt")
		return
	crashes += 1
	_mol_hurt(mol)
	_cue(-1)
	Game.sfx(&"splat")
	_psy_pulse(4, Color(1.0, 0.2, 0.2))
	_glint_spill()
	_clean = false
	crash_log.append("%s at z=%.0f x=%.1f v=%.1f %s" % [msg, spos.z, spos.x, vel.length(), ctx])
	hurt_t = 1.1
	vel *= 0.3
	if trail:
		# back onto the trail: a tree at the edge must not leave the board pinned among the trees, hitting the next one and the next
		spos.x = lerpf(spos.x, trail_x(spos.z), 0.85)
		spos.y = terrain_h(spos.x, spos.z)                  # the snow is at another height there: without this the next frame reads the difference as a launch
		_gh_prev = spos.y
		vy = 0.0
		grounded = true
		vel.x = 0.0
		heading = 0.0
		_steer_s = 0.0
		_steer_vel = 0.0
	chain = 0
	groove = 1.0
	_shake = 0.9
	_toast(msg, Color(1.0, 0.4, 0.35))
	Game.sfx(&"hurt")
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) < 30.0:
			r["crash"] = true


## Scores a barrier the moment you cross it: the opening you went through, how close to its middle, and the flow chain.
# --------------------------------------------------------------------------
# CALLED GATE test (?called): the game marks one opening of every barrier, you look at it, and it records what your eyes said and which opening it understood.
# Nothing about the steering or the course changes: it only draws the marker and writes a log (tools/called_report.py scores it).
# --------------------------------------------------------------------------
var called_mode: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("called")
var called_res: Array = []           # one record per barrier
var _call_rng := RandomNumberGenerator.new()
var _call_rows: Array = []           # samples waiting to be posted
var _call_acc: float = 0.0
var _call_row: Dictionary = {}       # the barrier being called now


func _call_index(row: Dictionary, g: Dictionary) -> int:
	if g.is_empty():
		return -1
	var n := 0
	for o in row["gaps"]:
		if float(o["x"]) < float(g["x"]):
			n += 1
	return n


func _called_tick(delta: float) -> void:
	if not called_mode or _finished:
		return
	# the barrier ahead
	var row: Dictionary = {}
	var keys: Array = _rows.keys()
	keys.sort()
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if r["has_row"] and not r["passed"] and spos.z - float(r["z"]) > 0.0:
			row = r
			break
	if called_res.is_empty() and _call_row.is_empty() and not row.is_empty():
		_call_rng.randomize()
		_toast("TEST: look at the marked opening", Color(1.0, 0.9, 0.2))
	if not row.is_empty() and not row.has("call"):
		var gs: Array = row["gaps"]
		row["call"] = gs[_call_rng.randi() % gs.size()]
		row["call_t0"] = _age
		row["call_lock_t"] = -1.0
		row["call_first"] = -2
	_call_row = row
	# a barrier just passed: the result
	for kk2 in keys:
		var r2: Dictionary = _rows[kk2]
		if not r2.has("call") or not r2["passed"] or r2.has("call_done"):
			continue
		r2["call_done"] = true
		var through: Dictionary = {}
		for g in r2["gaps"]:
			if absf(spos.x - float(g["x"])) <= float(g["w"]) * 0.5 + 1.2:
				through = g
		var xs: Array = []
		var srt: Array = (r2["gaps"] as Array).duplicate()
		srt.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
		for g2 in srt:
			xs.append(snappedf(float(g2["x"]), 0.1))
		var eg: Dictionary = r2.get("eyes_gap", {})
		var rec := {"kind": "called_gate", "row": int(r2["j"]), "n": xs.size(), "call": _call_index(r2, r2["call"]), "eyes": _call_index(r2, eg), "first": int(r2["call_first"]), "through": _call_index(r2, through),
			"lock_s": snappedf(float(r2["call_lock_t"]), 0.01), "seen_s": snappedf(_age - float(r2["call_t0"]), 0.01), "crash": bool(r2["crash"]), "xs": xs, "px": snappedf(spos.x, 0.1), "zone": String(r2.get("zone", ""))}
		called_res.append(rec)
		if Telemetry.inst != null:
			Telemetry.inst._post(rec)
	if row.is_empty():
		return
	# which opening the game holds right now, and the first time it holds the called one
	var held: Dictionary = _aim if (not _aim.is_empty() and is_same(_aim_row, row)) else {}
	if not held.is_empty():
		if int(row["call_first"]) == -2:
			row["call_first"] = _call_index(row, held)
		if is_same(held, row["call"]) and float(row["call_lock_t"]) < 0.0:
			row["call_lock_t"] = _age - float(row["call_t0"])
	_call_acc += delta
	if _call_acc < 0.1:
		return
	_call_acc = 0.0
	var vs := get_viewport().get_visible_rect().size
	var sxs: Array = []
	var srt2: Array = (row["gaps"] as Array).duplicate()
	srt2.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	for g3 in srt2:
		var sc := _gap_screen(row, g3)
		var gi3 := (row["gaps"] as Array).find(g3)
		if beacons and is_same(_bc_row, row) and gi3 >= 0 and gi3 < _bc_xs.size():
			sxs.append(snappedf(float(_bc_xs[gi3]) / maxf(vs.x, 1.0), 0.001))
		else:
			sxs.append(snappedf((sc["c"] as Vector2).x / maxf(vs.x, 1.0), 0.001) if not sc.is_empty() else -1.0)
	var P := GazeProvider
	_call_rows.append([snappedf(_age, 0.01), int(row["j"]), snappedf(spos.z - float(row["z"]), 0.1), _call_index(row, row["call"]), _call_index(row, held), _call_index(row, _cand) if not _cand.is_empty() else -1,
		snappedf(_cursor_px.x / maxf(vs.x, 1.0), 0.001), snappedf(_aim_cx / maxf(vs.x, 1.0), 0.001), snappedf(_steer_gaze, 0.01), snappedf(P.mix.value, 0.01), snappedf(P.eih.x, 0.0001),
		snappedf(P.head_rpy.x, 0.001), 1 if P.mix_used() else 0, snappedf(spos.x, 0.1), sxs])
	if _call_rows.size() >= 20:
		_call_flush()


func _call_flush() -> void:
	if _call_rows.is_empty():
		return
	if Telemetry.inst != null:
		Telemetry.inst._post({"kind": "called", "cols": "t,row,dist,call,held,cand,cursor,aimx,steer,mix,eih,yaw,mixed,x,gates", "rows": _call_rows})
	_call_rows = []


## The marker over the called opening: a bouncing arrow above it and a ring around it.
func _draw_called(k: float) -> void:
	if not called_mode or _call_row.is_empty() or not _call_row.has("call") or _call_row["passed"]:
		return
	var sc := _gap_screen(_call_row, _call_row["call"])
	if sc.is_empty():
		return
	var c: Vector2 = sc["c"]
	var hw := maxf(float(sc["hw"]), 10.0 * k)
	if beacons and is_same(_bc_row, _call_row):
		var ci := (_call_row["gaps"] as Array).find(_call_row["call"])
		if ci >= 0 and ci < _bc_xs.size():
			var sy := get_viewport().get_visible_rect().size.y
			c = Vector2(float(_bc_xs[ci]), maxf(minf(sy * 0.30, c.y - 70.0 * k), 60.0 * k))            # the arrow points at the marker you look toward, not at the far-off opening
			hw = 26.0 * k
	var bob := sin(_age * 7.0) * 5.0 * k
	var col := Color(1.0, 0.9, 0.2, 0.95)
	var tip := c + Vector2(0.0, -hw * 0.9 - 26.0 * k + bob)
	var sz := 22.0 * k
	Draw2D.poly(_hud, PackedVector2Array([tip + Vector2(-sz, -sz * 1.5), tip + Vector2(sz, -sz * 1.5), tip]), col)
	_hud.draw_rect(Rect2(tip + Vector2(-sz * 0.35, -sz * 2.6), Vector2(sz * 0.7, sz * 1.2)), col)
	Draw2D.arc(_hud, c, hw * 1.05, 0.0, TAU, 32, Color(1.0, 0.9, 0.2, 0.8), 3.5 * k, true)


func _update_rows() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"] or r["passed"]:
			continue
		if spos.z <= float(r["z"]):
			r["passed"] = true
			rows_passed += 1
			var chosen: Dictionary = {}
			for g in r["gaps"]:
				if absf(spos.x - float(g["x"])) <= float(g["w"]) * 0.5 + 1.2:
					chosen = g
			var via: Dictionary = chosen
			if via.is_empty():
				var bdx := 1.0e9
				for g2 in r["gaps"]:
					if absf(spos.x - float(g2["x"])) < bdx:
						bdx = absf(spos.x - float(g2["x"]))
						via = g2
			Telemetry.barrier({"row": int(r["j"]), "gaps": (r["gaps"] as Array).size(), "hit": not chosen.is_empty() and not bool(r["crash"]), "eyes": _eye_on, "locked": r.has("eyes_gap") and not (r["eyes_gap"] as Dictionary).is_empty(),
				"mine": is_same(r.get("eyes_gap", {}), chosen), "dx": snappedf(spos.x - float(via["x"]) if not via.is_empty() else 0.0, 0.1), "spd": int(vel.length()), "zone": String(r.get("zone", "")),
				"cur": snappedf(_cursor_px.x / maxf(get_viewport().get_visible_rect().size.x, 1.0), 0.01), "look": snappedf(_off_now, 0.01), "sg": snappedf(_steer_gaze, 0.01), "chain": chain_lvl})
			if not via.is_empty():
				_pending_zone = String(via.get("leads", ""))
				_pending_bend = float(via.get("bend", 0.0))
				if bool(params.get("lazy", true)):
					_good_x = float(via["x"])                         # the next stretch is built around where you came through, not around where the safe line was
				_gate_open = true
				var cut_dx := float(r.get("cut", 0.0))
				if cut_dx != 0.0:
					_cut_z = float(r["z"]) - 7.0                          # spliced once you are clear of both lines of the barrier
					_cut_dx = cut_dx
					_good_x = clampf(_good_x + cut_dx, -42.0, 42.0)       # the next stretch is built around where you will come out
				if _pending_zone != "" and ZONES.has(_pending_zone) and not Realms.is_realm(_pending_zone):
					var zi: Dictionary = ZONES[_pending_zone]
					_toast(String(zi["name"]), zi["col"])
			var rg := String(r.get("region", "pines"))
			if rg != _player_region:
				_player_region = rg
				_toast("ENTERING: " + String((REGIONS[rg] as Dictionary)["name"]), Color(1.0, 0.95, 0.7))
			if chosen.is_empty() or r["crash"]:
				continue
			_passed_ok += 1
			# with the eyes on, the points are for the gate you chose with them; the board's own pick (or a wrong one) carries you through but is worth little
			var eg: Dictionary = r.get("eyes_gap", {})
			if _eye_on and gate_assist and not autopilot and is_same(eg, chosen):
				ag["eyes"] = int(ag["eyes"]) + 1                                      # a gate you chose with your eyes and then went through
			if _eye_on and gate_assist and not autopilot and not is_same(eg, chosen):
				_gain(10)
				chain = 0
				groove = 1.0
				if eg.is_empty():
					ag["auto"] = int(ag["auto"]) + 1
					_toast("AUTO GATE", Color(0.8, 0.8, 0.85))
				else:
					ag["wrong"] = int(ag["wrong"]) + 1
					wrong_gates += 1
					_toast("WRONG GATE: RECOVER", Color(1.0, 0.75, 0.3))
				continue
			var margin := clampf(1.0 - absf(spos.x - float(chosen["x"])) / (float(chosen["w"]) * 0.5), 0.0, 1.0)
			var pts := 40 + int(30.0 * margin)
			if float(chosen["w"]) < 11.5:
				pts += 30
				_tight_n += 1
				_toast("TIGHT", Color(0.4, 1.0, 0.7))
			_flow_up()
			_gain(int(float(pts) * groove))
			Game.sfx(&"coin")


func _finish() -> void:
	_finished = true
	_xp_tick(0.0, true)
	_best_store()
	_call_flush()
	_runlog.end_run(self, "finish")
	_end_t = 0.0
	if _best_time <= 0.0 or (_clean and _run_t < _best_time):
		_best_time = _run_t
	if _clean:
		score += 1000
	Game.sfx(&"boom")
	_flash = 0.6
	_toast("FINISH!", Color(1.0, 0.9, 0.4))


## Builds every shader the run can need NOW, at the start, instead of the moment each thing first appears (a browser freezes the picture for 70 to 800 ms every time it
## builds one: the first loot effect, the first realm, the first glow...). One tiny copy of each kind of material is drawn just in front of the camera for a few frames, once
## as a single mesh and once as a batch (the two are different programs), next to a small light, then removed.
var _warmed: bool = false
var _warming: bool = false           # the board waits at the top while this runs
var _warm_k: float = 0.0             # 0..1, for the bar


# ONE OF EVERY KIND, KEPT: the engine throws a shader away when the last material using it is freed and builds it again the next time one like it is made (a tenth of a second
# of stopped picture, every time). So every plain material that turns up on anything added to the scene is looked at once, and the first of each kind (each combination of
# switches) is copied and kept for the session. An effect that makes a material, shows it and frees it then costs its build once, not every time.
var _held_kinds: Dictionary = {}


func _hold_node(n: Node) -> void:
	if n is GeometryInstance3D:
		_hold_check.call_deferred(n)


func _hold_check(n: Node) -> void:
	if not is_instance_valid(n):
		return
	_hold_mat((n as GeometryInstance3D).material_override)
	var me: Mesh = null
	if n is MeshInstance3D:
		me = (n as MeshInstance3D).mesh
	elif n is CPUParticles3D:
		me = (n as CPUParticles3D).mesh
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		me = (n as MultiMeshInstance3D).multimesh.mesh
	if me != null:
		for si in me.get_surface_count():
			_hold_mat(me.surface_get_material(si))


func _hold_mat(m: Material) -> void:
	var b := m as BaseMaterial3D
	if b == null:
		return
	var key := "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d" % [b.shading_mode, b.transparency, b.blend_mode, b.cull_mode, b.depth_draw_mode, int(b.no_depth_test),
		int(b.vertex_color_use_as_albedo), b.billboard_mode, int(b.emission_enabled), int(b.disable_fog), int(b.albedo_texture != null), b.texture_filter, b.distance_fade_mode,
		int(b.disable_receive_shadows), b.specular_mode, b.diffuse_mode, int(b.use_particle_trails) * 2 + int(b.vertex_color_is_srgb)]
	if not _held_kinds.has(key):
		var kept := b.duplicate() as BaseMaterial3D
		kept.get_shader_rid()          # a material that has never been drawn has not claimed its shader yet: asking for it makes it claim one, and that is what keeps the shader alive
		_held_kinds[key] = kept


func _warm_shaders() -> void:
	if _warmed or cam == null:
		return
	_warmed = true
	if not OS.has_feature("web"):
		return                                             # only a browser builds shaders this slowly; tests and the desktop build go straight in
	if not get_tree().node_added.is_connected(_hold_node):
		get_tree().node_added.connect(_hold_node)
	_warming = true
	_warm_k = 0.0
	Mats.keep_alive([_fx_mat("solid", Color.WHITE), _fx_mat("add", Color.WHITE), _fx_mat("halo", Color.WHITE), _fx_mat("ground", Color.WHITE), _fx_mat("spark", Color.WHITE)])
	var lt := get_parent().get_node_or_null("Lighting") as DhLighting if get_parent() != null else null
	if lt != null:
		lt._cool = 20.0                                    # the pauses below are not the game being slow: the governor must not drop a tier over them
		lt._bad = 0.0
	var holder := Node3D.new()
	cam.add_child(holder)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.02
	lamp.omni_range = 4.0
	lamp.shadow_enabled = false
	holder.add_child(lamp)
	lamp.position = Vector3(0.0, -0.4, -3.0)
	var mats: Array = [Mats.lit(), Mats.flat(), Mats.glass(), Mats.glass(true), Mats.glow(), _fx_mat("solid", Color.WHITE), _fx_mat("add", Color.WHITE), _fx_mat("halo", Color.WHITE),
		_fx_mat("ground", Color.WHITE), _fx_mat("spark", Color.WHITE), Realms.ground_material(), _m_shadow_mat, _m_ground, _coin_mat]
	for zn in Realms.KITS:
		mats.append(Realms.material(String(zn)))
		break
	mats.append(_food_mat(Color.WHITE))                     # the pickups are lit and glow: a different program from the plain lit one, and the first one in view used to stall the frame before it was eaten
	mats.append(_food_mat(Color(1.0, 0.5, 0.2), 1.2))
	mats.append(_mol_material())                             # the molecules and everything built like them (pads, pickups, bumpers, gates)
	mats.append(_shaft_material())                           # the light shafts
	if _veg_theme != null:
		mats.append(_veg_theme)                           # the theme's trees and rocks: built here, not the first time one comes into a lamp's reach
	var box := BoxMesh.new()
	var plain_box := BoxMesh.new()
	var col_box := ArrayMesh.new()                    # a box with vertex colours, which the batches use
	var arr := box.get_mesh_arrays()
	var cols := PackedColorArray()
	cols.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	cols.fill(Color.WHITE)
	arr[Mesh.ARRAY_COLOR] = cols
	col_box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Each is drawn beside a small lamp and out of its reach ("lit by a lamp" and
	# "not lit by a lamp" are different programs), as a single mesh and as a batch (different again).
	var steps := 3.0
	for f in 3:
		await get_tree().process_frame                     # GET READY is on the screen before the picture stops
	for i in mats.size():
		var m: Material = mats[i]
		if m != null:
			for near in [true, false]:
				_warm_one(holder, col_box, m, i, near)
				_warm_one(holder, plain_box, m, i, near)          # a mesh without vertex colours (rings, glints, poles, beacons) is a different program from one with them
	_warm_k = 0.5
	var puff := CPUParticles3D.new()
	puff.mesh = _sphere_mesh(0.1)
	puff.material_override = _fx_mat("spark", Color(1, 1, 1, 1))
	puff.amount = 2
	puff.emitting = true
	holder.add_child(puff)
	puff.position = Vector3(0.0, -0.4, -3.0)
	for f in 12:
		await get_tree().process_frame
	# and each of those comes in two flavours: one for when colour grading or glow is on (the picture is finished in a pass afterwards) and one for when both
	# are off (each material finishes its own colour). The quality governor switches between them when it changes tier, so build the other one too, then put it back.
	var env: Environment = lt.level.world_env.environment if lt != null and lt.level != null and lt.level.world_env != null else null
	if env != null:
		var g0 := env.glow_enabled
		var a0 := env.adjustment_enabled
		if g0 or a0:
			env.glow_enabled = false
			env.adjustment_enabled = false
		else:
			env.adjustment_enabled = true
		_warm_k = 0.8
		for f in 12:
			await get_tree().process_frame
		env.glow_enabled = g0
		env.adjustment_enabled = a0
		lt._apply_tier()
	if _journey != null and _lvl != null:
		# every world's sky, ground, trees and full-screen looks are built here, behind the GET READY screen, so none of them stalls the game when it comes on
		for wi in 2:
			var wid := _journey.peek_world(wi)
			_pw_done[wid] = true
			_warm_k = 0.9 + 0.08 * float(wi) / 2.0
			for part in ["sky", "skymat", "ground", "veg", "light"]:
				ThemeFX.apply_part(_lvl, self, wid, part, 1.0, _cfg_dyn, _cfg_snow, _cfg_fluffy)
			var vm := Themes.veg_material(wid)
			if vm != null:
				_warm_one(holder, col_box, vm, 40 + wi, true)
				_warm_one(holder, col_box, vm, 40 + wi, false)
			for f in 3:
				await get_tree().process_frame
		var wfx := _lvl.get_node_or_null("ThemeFX") as ThemeFX
		if wfx != null and wfx.post != null:
			if wfx.post.rect != null:
				wfx.post.rect.modulate = Color(1, 1, 1, 0.01)          # built, but invisible: nothing may flash before the run
			for md in [1]:
				wfx.post.set_look(md, 0.8)
				if wfx.post.mat != null:
					wfx.post.mat.set_shader_parameter("onset", 0.0)          # at no strength: the pass is built and compiled, and shows nothing
					wfx.post.mat.set_shader_parameter("mode", 1.0 if md == 1 else 0.0)          # (the other two looks tint the whole picture: only the shader program matters here, not the look)
				for f in 3:
					await get_tree().process_frame
			wfx.post.set_look(0, 0.8)
			if wfx.post.rect != null:
				wfx.post.rect.modulate = Color(1, 1, 1, 1)
		_jpost_mode = 0
		journey_reset()
		for f in 2:
			await get_tree().process_frame
	if lt != null:
		lt._cool = 6.0
		lt._bad = 0.0
	_warm_k = 1.0
	await get_tree().process_frame
	holder.queue_free()
	_warming = false


func _warm_one(holder: Node3D, mesh: Mesh, m: Material, i: int, near: bool) -> void:
	var root := Node3D.new()
	holder.add_child(root)
	root.position = (Vector3(0.0, -0.4, -3.0) if near else Vector3(0.0, -2.0, -40.0)) + Vector3(float(i) * (0.008 if near else 0.06), 0.0, 0.0)
	root.scale = Vector3.ONE * (0.004 if near else 0.03)
	for shadow in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.position = Vector3(0.0, 2.0 if shadow else 0.0, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = mesh is ArrayMesh
	mm.mesh = mesh
	mm.instance_count = 2
	for q in 2:
		mm.set_instance_transform(q, Transform3D(Basis.IDENTITY, Vector3(0.0, -2.0 - float(q), 0.0)))
		if mm.use_colors:
			mm.set_instance_color(q, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	root.add_child(mmi)


func _restart() -> void:
	if GazeProvider.kit.refit_due and not _dot_off:
		GazeProvider.kit.refit_due = false            # the face was gone for a while: this may be someone else, so the dot runs again
		_dot_done = false
		_dot_t = -1.0
		_dot_tries = 0
		_dot_phase = 0
	var trng := RandomNumberGenerator.new()
	trng.randomize()
	_tr_p1 = trng.randf_range(0.0, TAU)
	_tr_p2 = trng.randf_range(0.0, TAU)
	_tr_p3 = trng.randf_range(0.0, TAU)
	_tr_p4 = trng.randf_range(0.0, TAU)
	poles_clean = 0
	poles_shaved = 0
	poles_wrong = 0
	poles_total = 0
	time_pen = 0.0
	_goals_new()
	feats_total = 0
	jumps_built = 0
	_jump_gap_z = 0.0
	jumps_done = 0
	rails_built = 0
	rails_done = 0
	rail_m = 0.0
	loot_built = 0
	picks = 0
	picks_side = {}
	choices_built = 0
	choice_log.clear()
	choice_n = {}
	_cho.clear()
	_dg_hist.clear()
	_rail = {}
	_line_pick = {}
	TrailCurve.on = bend
	_cam_strip_ok = false
	if bend:
		TrailCurve.setup(randi(), bend_strength)
	_guide_done = false
	ag = {"eyes": 0, "auto": 0, "wrong": 0, "in": 0.0, "as": 0.0, "eng": 0.0, "idle": 0.0}
	_engage = 1.0
	_idle_t = 0.0
	sacc.reset()
	_configure_sacc()
	_intent_dir = 0.0
	_intent_amt = 0.0
	_sacc_seen = 0
	_sacc_conf_seen = 0
	_sacc_ret_seen = 0
	_runlog.end_run(self, "restart")
	if _journey != null:
		if _jw != "alpine" or _jpost_mode != 0 or _journey.phase != DhJourney.Phase.CALM:
			journey_reset()
		_journey.start(self, int(params.get("seed", 1)))
	cleanup()
	if _run_t > 2.0 or _finished:
		_run_no += 1                                          # a fresh page always gets the same first course, on any device; each ride after that is a new one
	_run_seed = int(params["seed"]) + _run_no
	_rng.seed = _run_seed
	_next_j = 0
	_good_x = 0.0
	_last_rz = 0.0
	score = 0
	chain = 0
	groove = 1.0
	crashes = 0
	best_flow = 1.0
	rows_passed = 0
	_passed_ok = 0
	_tight_n = 0
	_clean = true
	_finished = false
	_end_t = 0.0
	_run_t = 0.0
	hurt_t = 0.0
	crash_log.clear()
	spos = Vector3(0.0, terrain_h(0.0, 0.0), 0.0)
	vel = Vector2(0.0, -10.0)
	vy = vel.y * SLOPE
	heading = 0.0
	grounded = true
	steer = 0.0
	_steer_s = 0.0
	_steer_vel = 0.0
	_gh_prev = spos.y
	_aim = {}
	_aim_row = {}
	_cand = {}
	_cand_t = 0.0
	_aim_w = 0.0
	swerves = 0
	wrong_gates = 0
	shield = 0
	_boost_t = 0.0
	_mult_t = 0.0
	chain_lvl = 0
	chain_step = 0
	_chain_t = 0.0
	buffs_spawned = 0
	buffs_got = 0
	buff_log = {}
	spawned_kind = {}
	got_kind = {}
	orbs_got = 0
	glints = 0
	_xp_paid = 0
	_sb_clear()
	_gl_run = 0
	for gsp in _gl_spill:
		if is_instance_valid(gsp["n"]):
			(gsp["n"] as Node).queue_free()
	_gl_spill.clear()
	_buff_tgt = {}
	_buff_cand = {}
	_buff_cand_t = 0.0
	_buff_w = 0.0
	_pitch.clear()
	face_kind = ""
	_cine_k = 0.0
	_cine_on = false
	_region = "pines"
	_region_left = 5
	_player_region = "pines"
	regions_seen = {}
	_pending_zone = ""
	_pending_bend = 0.0
	_gate_open = true
	zones_seen = {}
	_zone_by_j.clear()
	_rp.clear()
	_row_eyes = []
	_eye_count = 0
	_realm_now = ""
	_cut_dx = 0.0
	_reveal_j = -1
	Realms.cave_k = 0.0
	Realms.flash = 0.0
	realms_seen = {}
	Engine.time_scale = 1.0
	_slowmo_t = 0.0
	_air_moves.clear()
	_trk_comment_t = 0.0
	ridiculous = 0
	_kickers.clear()
	_ramp_charge = 0.0
	_ramp_prev_z = 0.0
	pops_done = 0
	_air_zones.clear()
	_force_far_next = false
	_last_air = false
	air_segments = 0
	for bb in _balls:
		if is_instance_valid(bb["n"]):
			(bb["n"] as Node).queue_free()
	_balls.clear()
	_next_ball_z = -420.0
	snow_spawned = 0
	snow_braced = 0
	snow_hit = 0
	snow_dodged = 0
	foods_bounced = 0
	foods_lost = 0
	pads_hit = 0
	epics_built = 0
	_wide_last = -10.0
	_squint_last = -10.0
	_fx_rng.seed = _run_seed + 99
	kickers_built = 0
	tricks_landed = 0
	trick_score = 0
	best_trick = ""
	_in_air = false
	_trk_spin = 0.0
	_trk_flip = 0.0
	_trk_flip_goal = 0.0
	_trk_vis_spin = 0.0
	_trk_vis_flip = 0.0
	_trk_text_t = 0.0
	_hop_t = 1.0
	_pop_a = 0.0
	_hud_pops.clear()
	_swerving = false
	_wall_gap = {}
	_wall_row_j = -999
	while _gate_open and float(_next_j) * ROW_GAP < AHEAD:
		_gen_segment(_next_j)
		_next_j += 1
	_place_camera(1.0, true)


# --------------------------------------------------------------------------
# Eyes as buttons. LOOK steers and chooses. OPEN WIDE (or hold SPACE) eats a food as you reach it. SQUINT (or hold SHIFT) braces against a snowball.
# A food you drive past without eating it bounces away like rubber, once, and waits for a second try; miss that and it pops.
# Opening wide a moment early counts (0.5 s), because the tracker is a little late.
# --------------------------------------------------------------------------
const FOOD_NAME := {"boost": "BURGER", "shield": "ICE CREAM", "mult": "CANDY", "donut": "DONUT"}
var wide_override: bool = false
var squint_override: bool = false
var eat_enabled: bool = false              # false (the default): every pickup is taken by touching it. true: you must open your eyes wide to eat (experimental, needs a reliable tracker)
var foods_bounced: int = 0
var foods_lost: int = 0
var _wide_last: float = -10.0
var _squint_last: float = -10.0
var _squinting_now: bool = false
var _squint_vis: float = 0.0
var _eat_hint: bool = false
var _fx_rng := RandomNumberGenerator.new()
var _run_no: int = 0
var _preset_i: int = 0


func _wide_now() -> bool:
	return wide_override or Input.is_key_pressed(KEY_SPACE) or (_eye_on and GazeProvider.wide_held())


func _squint_now() -> bool:
	return squint_override or Input.is_key_pressed(KEY_SHIFT) or (_eye_on and GazeProvider.squint_held())


func _can_eat() -> bool:
	return trail or (not eat_enabled) or wide_override or _age - _wide_last < 0.5


## Snowballs are things to get away from, not things to look at. Two things do that for you: the board slips out of the way of a ball that is about to hit (a smooth sideways push, stronger the
## closer it gets, like it does for trees), and ducking your chin still braces. You can also outrun it (a burger) or carve away yourself. Returns the sideways steering to add.
func _ball_evade() -> float:
	var best := 0.0
	var best_w := 0.0
	for b in _balls:
		if b["done"]:
			continue
		var dz0 := spos.z - float(b["z"])
		if dz0 < -6.0 or dz0 > 70.0:
			continue
		var dmin := 1.0e9
		var tmin := 0.0
		var side := 0.0
		var tau := 0.15
		while tau <= 2.6:
			var px := spos.x + vel.x * tau
			var pz := spos.z + vel.y * tau
			var qx := float(b["x"]) + float(b["vx"]) * tau
			var qz := float(b["z"]) + float(b["vz"]) * tau
			var d := Vector2(px - qx, pz - qz).length()
			if d < dmin:
				dmin = d
				tmin = tau
				side = px - qx
			tau += 0.15
		var reach := BALL_R + 1.1 + 3.2
		if dmin >= reach:
			continue
		if absf(side) < 0.6:
			side = -signf(float(b["vx"])) if float(b["vx"]) != 0.0 else (1.0 if spos.x < 0.0 else -1.0)           # dead on: go the way the ball came from, there is room behind it
		var urgency := clampf(1.9 / maxf(tmin, 0.4), 0.35, 1.0)
		var w := (1.0 - dmin / reach) * urgency
		if w > best_w:
			best_w = w
			# steer by just what it takes to be clear when the ball arrives: a ball seen early is a slight lean, only a late one is a hard swerve (it used to be at least a
			# quarter of full lock the moment a ball came into range, whatever the distance)
			var need_v := (reach - dmin + 0.6) / maxf(tmin - 0.15, 0.3)
			best = signf(side) * clampf(asin(clampf(need_v / maxf(vel.length(), 1.0), 0.0, 0.85)) / THETA_MAX * 1.25, 0.06, 0.95)
	return best if (avoid_enabled and not _braced()) else 0.0


func _braced() -> bool:
	return squint_override or _age - _squint_last < 0.45


func _update_eye_actions(delta: float) -> void:
	if _wide_now():
		_wide_last = _age
	var sq := squint_override                                            # blinking and squinting with your eyes no longer brace (it did not feel right); a chin duck does. Only the test switch counts here.
	var tk := nod_p < -0.10                                              # ducking your chin braces too: it is the one signal that is always reliable
	_squinting_now = (sq or tk) and not _balls.is_empty()               # only means something while a snowball is about: a stray one costs nothing
	if _squinting_now:
		_squint_last = _age
		if sq and grounded and not _finished:
			vel *= 1.0 - 0.12 * delta                 # squinting costs speed: you are hunched up and half blind


func _eat_or_bounce(b: Dictionary) -> void:
	if float(b.get("arm", 0.0)) > 0.0:
		return
	if _can_eat():
		_take_buff(b)
	else:
		_bounce_food(b)


func _food_pos(b: Dictionary) -> Vector3:
	var n: Variant = b["n"]
	if is_instance_valid(n) and not TrailCurve.on:
		return (n as Node3D).global_position
	if is_instance_valid(n):
		return Vector3(float(b["x"]), (n as Node3D).global_position.y, float(b["z"]))          # the game thinks on the straight strip: height from the node, the rest from the record
	return Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + 1.9, float(b["z"]))


func _bounce_food(b: Dictionary) -> void:
	var n: Variant = b["n"]
	var col: Color = BUFF_COL[b["t"]]
	var p0 := _food_pos(b)
	if b.get("bounced", false):
		b["taken"] = true
		foods_lost += 1
		if is_instance_valid(n):
			(n as Node3D).visible = false
		_burst(p0, col, 34, 7.0, 0.7, 0.9)
		Game.sfx(&"squeak")
		return
	b["bounced"] = true
	foods_bounced += 1
	var nx := clampf(spos.x + vel.x * 0.25 + _fx_rng.randf_range(-7.0, 7.0), -40.0, 40.0)
	var nz := spos.z - 32.0 - _fx_rng.randf_range(0.0, 12.0)
	var ny := terrain_h(nx, nz) + 1.9
	b["x"] = nx
	b["z"] = nz
	b["arm"] = 0.8
	b["moving"] = true
	b["lift"] = 0.0
	b["kind"] = "bounced"
	_burst(p0, col, 18, 6.0, 0.5, 0.7)
	Game.sfx(&"boing")
	if is_instance_valid(n):
		var nn := n as Node3D
		var s0 := Vector3(p0.x, nn.global_position.y, p0.z)
		var tw := create_tween()
		tw.tween_method(func(u: float) -> void:
			if is_instance_valid(nn):
				_wset(nn, Vector3(lerpf(s0.x, nx, u), lerpf(s0.y, ny, u) + sin(PI * u) * 9.0, lerpf(s0.z, nz, u))), 0.0, 1.0, 0.8)
		tw.tween_callback(func() -> void:
			b["arm"] = 0.0
			b["moving"] = false
			b["y"] = ny)
	else:
		b["arm"] = 0.0
		b["moving"] = false


# --------------------------------------------------------------------------
# Snowballs: one rolls in from the side now and then, aimed at where you will be in about 2.6 s. Three ways through:
#   carve away   steer out of its line (or behind it)       no cost
#   outrun it    be across its line first (a burger helps)  no cost
#   squint       brace: it shatters on you                  a little speed, no shove, the chain keeps; and you are blind and slow while you squint
# Do nothing and it hits: 40% of your speed gone, a shove the way it was rolling, your flow chain reset. An ice cream shield absorbs it too.
# --------------------------------------------------------------------------
const BALL_R := 3.0
var balls_enabled: bool = true
var _balls: Array = []
var _next_ball_z: float = -420.0
var snow_spawned: int = 0
var snow_braced: int = 0
var snow_hit: int = 0
var snow_dodged: int = 0
var _ball_hint: bool = false


func _spawn_ball() -> void:
	var d := _course_diff(spos.z)
	var T := 2.6
	var sp := maxf(-vel.y, 24.0)
	var px := clampf(spos.x + vel.x * T, -38.0, 38.0)
	var pz := spos.z - sp * T
	var vb := 12.0 + 6.0 * d
	var side := 1.0 if px < 0.0 else -1.0
	var sx := clampf(px + side * 44.0, -(W_HALF - 4.0), W_HALF - 4.0)
	var sz := pz + vb * T
	var vx := (px - sx) / T
	var n := Node3D.new()
	var mummy := hazard_skin == "mummy"
	var gum := hazard_skin == "gumball"
	var body_c := Color(0.93, 0.87, 0.68) if mummy else (Color(1.0, 0.45, 0.72) if gum else Color(0.95, 0.97, 1.0))
	var lump_c := Color(0.8, 0.72, 0.5) if mummy else (Color(0.5, 0.95, 0.8) if gum else Color(0.88, 0.93, 1.0))
	_mi(n, _sphere_mesh(BALL_R), _fx_mat("solid", body_c, 0.9))
	for i in 5:
		var a := float(i) * 1.7
		_mi(n, _sphere_mesh(1.1), _fx_mat("solid", lump_c, 0.8), Vector3(cos(a), sin(a * 1.3), sin(a)) * 2.4)
	add_child(n)
	var eyes: Node3D = null
	if mummy:
		eyes = Node3D.new()                                       # two glowing green eyes that stay turned toward you while the bandaged ball rolls
		for ex in [-0.9, 0.9]:
			_mi(eyes, _sphere_mesh(0.5), _fx_mat("solid", Color(0.3, 1.0, 0.45), 3.0), Vector3(float(ex), 0.0, 0.0))
		add_child(eyes)
	_place(n, Vector3(sx, terrain_h(sx, sz) + BALL_R, sz))
	_balls.append({"n": n, "x": sx, "z": sz, "vx": vx, "vz": -vb, "t": 0.0, "done": false, "eyes": eyes})
	snow_spawned += 1
	_next_ball_z = spos.z - _fx_rng.randf_range(150.0, 230.0) * lerpf(1.0, 0.7, d)
	_toast("MUMMY!" if mummy else ("GUMBALL!" if gum else "SNOWBALL!"), Color(0.95, 0.85, 0.5) if mummy else (Color(1.0, 0.7, 0.85) if gum else Color(0.85, 0.95, 1.0)))
	Game.sfx(&"whoosh")
	if not _ball_hint:
		_ball_hint = true
		_toast("Carve away, outrun it, or duck your chin / squint to brace", Color(0.85, 0.95, 1.0))


func _update_balls(delta: float) -> void:
	if balls_enabled and not trail and not _finished and _balls.is_empty() and spos.z < _next_ball_z and spos.z > finish_z + 260.0:
		_spawn_ball()
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		b["t"] = float(b["t"]) + delta
		b["x"] = float(b["x"]) + float(b["vx"]) * delta
		b["z"] = float(b["z"]) + float(b["vz"]) * delta
		var n: Variant = b["n"]
		var bx := float(b["x"])
		var bz := float(b["z"])
		if float(b["t"]) < 0.9 and float(b["vx"]) != 0.0:
			# the first moments: keep the roll timed to where you will be (the hill speeds you up more than a guess can say). After that it is fixed, so a late boost or a sidestep still beats it.
			var tl := absf((spos.x + vel.x * 1.5 - bx) / float(b["vx"]))
			tl = clampf(tl, 0.6, 4.0)
			var want_vz := (spos.z + vel.y * tl - bz) / tl
			b["vz"] = lerpf(float(b["vz"]), clampf(want_vz, -34.0, -8.0), 0.15)
		if is_instance_valid(n):
			var nn := n as Node3D
			_wset(nn, Vector3(bx, terrain_h(bx, bz) + BALL_R, bz))
			nn.rotate_x(float(b["vz"]) * delta / BALL_R)
			nn.rotate_z(-float(b["vx"]) * delta / BALL_R)
			var ey: Variant = b.get("eyes")
			if ey != null and is_instance_valid(ey):
				_wset((ey as Node3D), Vector3(bx, terrain_h(bx, bz) + BALL_R * 1.25, bz + BALL_R * 0.78))
		if not b["done"]:
			var dx := spos.x - bx
			var dz := spos.z - bz
			var above := spos.y - terrain_h(spos.x, spos.z)
			if dx * dx + dz * dz < (BALL_R + 1.1) * (BALL_R + 1.1) and above < BALL_R + 1.0:
				_ball_hit(b)
			elif bz > spos.z + 6.0:
				b["done"] = true
				snow_dodged += 1
				_gain(60)
				_toast("DODGED", Color(0.7, 1.0, 0.8))
				_flow_up()
		if bz > spos.z + 70.0 or float(b["t"]) > 14.0 or b.get("gone", false):
			if is_instance_valid(n):
				(n as Node).queue_free()
			var ey2: Variant = b.get("eyes")
			if ey2 != null and is_instance_valid(ey2):
				(ey2 as Node).queue_free()
			_balls.remove_at(i)


func _ball_hit(b: Dictionary) -> void:
	b["done"] = true
	var pos := Vector3(float(b["x"]), terrain_h(float(b["x"]), float(b["z"])) + BALL_R, float(b["z"]))
	if _braced():
		snow_braced += 1
		vel *= 0.9
		_gain(80)
		_toast("BRACED!", Color(0.6, 0.9, 1.0))
		_shake = maxf(_shake, 0.5)
		_flash = 0.3
	elif shield > 0:
		shield = 0
		_toast("ICE SHIELD TOOK IT", BUFF_COL["shield"])
		_shake = maxf(_shake, 0.5)
		_flash = 0.3
	else:
		snow_hit += 1
		vel *= 0.6
		vel.x += signf(float(b["vx"])) * 9.0
		hurt_t = maxf(hurt_t, 0.5)
		chain = 0
		groove = 1.0
		_shake = 0.9
		_flash = 0.5
		_toast("SNOWBALL HIT", Color(1.0, 0.5, 0.4))
	_burst(pos, Color(0.95, 0.98, 1.0), 90, 15.0, 1.0, 2.2, Vector3.UP, 180.0, -9.0)
	_ring(pos, Color(0.85, 0.95, 1.0), 10.0, 0.5, true)
	Game.sfx(&"boom")
	var n: Variant = b["n"]
	if is_instance_valid(n):
		(n as Node3D).visible = false
	b["gone"] = true


# --------------------------------------------------------------------------
# Boost pads (chevrons on the snow, usually just before a kicker) and epic kickers: a taller ramp with a pad and two pickups in the air.
# --------------------------------------------------------------------------
var pads_hit: int = 0
var _ramp_charge: float = 0.0
var _ramp_prev_z: float = 0.0
var pops_done: int = 0
var trick_charge_override: bool = false


## On a ramp, tuck (chin down, or S) to charge; the pop at the lip is bigger the longer you held it. Or just ride the pads and let the ramp do the work.
# --------------------------------------------------------------------------
# The jump vortex: a swirl hanging over the base of every ramp. Come near it and an invisible suction lines you up with the ramp and speeds you up to launch speed by itself, so
# the ramp is something you pick (look at the swirl: it reaches much further to the side) and not something you have to steer onto. No boost pad is needed.
# --------------------------------------------------------------------------
const VX_LAUNCH := 46.0                   # m/s the vortex brings you to by the lip
const VX_ACCEL := 34.0
const VX_TRAIL := 37.0                   # m/s the trail swirl builds up to by the lip
const VX_REACH := 90.0                   # m before the foot of the ramp where the swirl starts to take hold
var _vx_pull: float = 0.0                # 0..1: how far into the swirl you are (the camera widens with it)
var _vx_blast: float = 0.0               # 1 at the lip, running down to 0
var _land_off: float = 0.0               # m across the trail the eyes have chosen to land at
var _land_ring: MeshInstance3D = null
var _vx_spin: float = 0.0
var _vx_active_t: float = 0.0


func _make_vortex(row: Dictionary, k: Dictionary, kx: float, kz: float, epic: bool, big: bool = false) -> void:
	var col := Color(0.95, 0.35, 1.0) if not epic else Color(0.3, 0.9, 1.0)
	var rings: Array = []
	if big:
		# a funnel: big rings over the foot of the ramp, smaller and brighter toward the lip, so you can see the way in from far up the slope and then ride through the swirl
		var nr := 5
		for ri in nr:
			var f := float(ri) / float(nr - 1)
			var rz: float = kz - float(k["len"]) * lerpf(-0.22, 0.86, f)
			var rr := lerpf(5.2, 2.5, f)
			var tm := TorusMesh.new()
			tm.inner_radius = 0.88
			tm.outer_radius = 1.12
			tm.rings = 28
			tm.ring_segments = 8
			var cc := col.lerp(Color(1.0, 0.95, 0.6), f * 0.7)
			var node := _mi(self, tm, _fx_mat("solid", Color(cc.r, cc.g, cc.b), 2.6), Vector3(kx, terrain_h(kx, rz) + 1.2 + 0.3 * rr, rz))
			node.set_meta("R", rr)
			node.set_meta("Z", rz)
			node.basis = TrailCurve.basis_at(rz) * Basis(Vector3(1, 0, 0), PI * 0.5) * Basis.from_scale(Vector3(rr, rr, rr * 0.7))          # the opening faces up the TRAIL as it runs there (it was turned to the straight strip, so on a bend the board met the ring edge on); facing down the slope from the start (they lay flat until the board was within 260 m)
			(row["nodes"] as Array).append(node)
			rings.append(node)
		k["vx"] = rings
		k["vx_col"] = col
		return
	for ri in 4:
		var tm := TorusMesh.new()
		tm.inner_radius = 2.2 - 0.45 * float(ri)
		tm.outer_radius = 2.7 - 0.45 * float(ri)
		if big and ri % 2 == 1:
			continue                                                     # two rings are enough on the trail
		var node := _mi(self, tm, _fx_mat("add", Color(col.r, col.g, col.b, 0.8 - 0.12 * float(ri))), Vector3(kx, terrain_h(kx, kz + 8.0) + (6.5 if big else 5.0), kz + 8.0))
		node.set_meta("Z", kz + 8.0)
		node.basis = TrailCurve.basis_at(kz + 8.0) * Basis(Vector3(1, 0, 0), PI * 0.5)
		var bs := 1.5 if big else 1.0
		node.scale = Vector3((1.0 + 0.55 * float(ri)) * bs, (1.0 + 0.55 * float(ri)) * bs, bs)
		node.set_meta("S", node.scale)
		(row["nodes"] as Array).append(node)
		rings.append(node)
	k["vx"] = rings
	k["vx_col"] = col


## Per physics frame: spin the swirls and, when you are in reach of one, pull you onto the ramp and up to launch speed.
var _jumpdemo: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("jumpdemo")          # test: starts the board 75 m before the first ramp
var _jd_done: bool = false


func _vortex_drive(delta: float) -> void:
	if _jumpdemo and not _jd_done and trail:
		for kk0 in _kickers:
			if kk0.get("trail", false):
				_jd_done = true
				spos = Vector3(float(kk0["x"]), terrain_h(float(kk0["x"]), float(kk0["z"]) + 75.0), float(kk0["z"]) + 75.0)
				_gh_prev = spos.y
				vel = Vector2(0.0, -24.0)
				break
	_vx_spin += delta
	var vs := get_viewport().get_visible_rect().size
	var cx := _aim_cx if _aim_cx >= 0.0 else _cursor_px.x
	var active := false
	for k in _kickers:
		var rings: Variant = k.get("vx", null)
		var kx: float = float(k["x"])
		var kz: float = float(k["z"])
		var lipz: float = kz - float(k["len"])
		var dz := spos.z - kz
		if rings != null and dz < 260.0 and dz > -40.0:
			var gi := 0
			var near_k := 1.0 + 2.5 * smoothstep(90.0, 10.0, dz)
			for rn in (rings as Array):
				if is_instance_valid(rn):
					if (rn as Node3D).has_meta("R"):
						var rr: float = (rn as Node3D).get_meta("R")
						(rn as Node3D).basis = TrailCurve.basis_at(float((rn as Node3D).get_meta("Z", kz))) * Basis(Vector3(0, 0, 1), _vx_spin * near_k * (1.2 + 0.5 * float(gi)) * (1.0 if gi % 2 == 0 else -1.0)) * Basis(Vector3(1, 0, 0), PI * 0.5) * Basis.from_scale(Vector3(rr, rr, rr * 0.7))
					else:
						(rn as Node3D).basis = TrailCurve.basis_at(float((rn as Node3D).get_meta("Z", kz))) * Basis(Vector3(0, 0, 1), _vx_spin * (2.2 + 0.7 * float(gi)) * (1.0 if gi % 2 == 0 else -1.0)) * Basis(Vector3(1, 0, 0), PI * 0.5) * Basis.from_scale((rn as Node3D).get_meta("S", Vector3.ONE))          # spin about the ring's own axis, which points down the slope: the opening always faces the board
				gi += 1
		if k.get("trail", false):
			# on the trail: the swirl catches you when you are lined up with the ramp (or the eyes picked it): it eases you onto the middle of the ramp and the speed builds
			# from the first rings to the lip, where the BLAST in _update_ramps throws you off it
			var half: float = float(k["w"]) * 0.5
			var dxk := kx - spos.x
			var picked: bool = not _line_pick.is_empty() and String(_line_pick["kind"]) == "jump" and absf(float(_line_pick.get("kx", 1.0e9)) - kx) < 0.5
			if grounded and spos.z < kz + VX_REACH + 14.0 and spos.z > lipz + 4.0 and (absf(dxk) < half + 36.0 or (picked and absf(dxk) < half + 50.0)):          # the mouth, and the whole side of the ramp: a board that comes at it from the side is taken in too
				active = true
				if not _vx_snd:
					_vx_snd = true
					Game.sfx(&"stretch")                          # the swirl takes hold: a rubbery stretch, let go at the lip
				var t := clampf((kz + VX_REACH - spos.z) / (VX_REACH + float(k["len"])), 0.0, 1.0)
				_vx_pull = maxf(_vx_pull, smoothstep(0.0, 0.8, t))
				spos.x += clampf(dxk * 7.0, -34.0, 34.0) * delta * smoothstep(0.0, 0.12, t)
				var fsp := -vel.y
				if fsp < VX_TRAIL:
					vel.y -= minf(VX_ACCEL * (0.9 if spos.z < kz else 0.6) * delta, VX_TRAIL - fsp)
			continue
		if dz > 70.0 or spos.z < lipz or not grounded:
			continue
		# reach: a little way either side of the ramp, much more when you are looking at the swirl
		var wp := Vector3(kx, terrain_h(kx, kz + 8.0) + 5.0, kz + 8.0)
		var looking := false
		if not _behind(wp):
			looking = _eye_on and absf(_unp(wp).x - cx) < 0.13 * vs.x
		var reach := float(k["w"]) * 0.5 + (16.0 if looking else 8.0)
		var dx := kx - spos.x
		if absf(dx) > reach:
			continue
		active = true
		vel.x += clampf(dx * 1.8, -10.0, 10.0) * delta * (1.0 - clampf(absf(dx) / reach, 0.0, 0.8))
		var fwd_sp := -vel.y
		if fwd_sp < VX_LAUNCH:
			vel.y -= minf(VX_ACCEL * delta, VX_LAUNCH - fwd_sp)
	if trail and not grounded and air_t > 0.25 and absf(_land_off) > 1.5:
		if _land_ring == null or not is_instance_valid(_land_ring):
			var rm := TorusMesh.new()
			rm.inner_radius = 2.0
			rm.outer_radius = 2.5
			rm.rings = 24
			rm.ring_segments = 6
			_land_ring = _mi(self, rm, _fx_mat("add", Color(0.5, 1.0, 0.8, 0.9)), Vector3.ZERO)
		var hh := maxf(spos.y - terrain_h(spos.x, spos.z), 0.0)
		var tl := (vy + sqrt(maxf(vy * vy + 2.0 * G * hh, 0.0))) / G
		var lz := spos.z + vel.y * tl
		var lx := trail_x(lz) + _land_off
		_land_ring.position = Vector3(lx, terrain_h(lx, lz) + 0.25, lz)
		_land_ring.visible = true
	elif _land_ring != null and is_instance_valid(_land_ring):
		_land_ring.visible = false
	if active:
		_vx_active_t = 0.45
	else:
		_vx_active_t = maxf(_vx_active_t - delta, 0.0)
		_vx_pull = maxf(_vx_pull - 2.0 * delta, 0.0)
	_vx_blast = maxf(_vx_blast - 2.2 * delta, 0.0)
	if not active and _vx_snd and _vx_active_t <= 0.0:
		_vx_snd = false


func _update_ramps(delta: float) -> void:
	var on_ramp := false
	var crossed := false
	var crossed_mid := false
	var crossed_k: Dictionary = {}
	for k in _kickers:
		var kz: float = k["z"]
		var lipz: float = kz - float(k["len"])
		if absf(spos.x - float(k["x"])) < float(k["w"]) * 0.5:
			if spos.z < kz + 4.0 and spos.z > lipz - 1.0:
				on_ramp = true
			if _ramp_prev_z > lipz and spos.z <= lipz:
				crossed = true
				crossed_k = k
				crossed_mid = absf(spos.x - float(k["x"])) < float(k["w"]) * 0.5 - 1.5
	_ramp_prev_z = spos.z
	var tucking_in := nod_p < -0.10 or trick_charge_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or _brow_held          # chin down or eyebrows up: either one winds the launch up
	_on_ramp_now = on_ramp
	if on_ramp and grounded and tucking_in:
		_ramp_charge = minf(_ramp_charge + delta / 0.9, 1.0)
	elif not crossed:
		_ramp_charge = move_toward(_ramp_charge, 0.0, delta * (0.6 if on_ramp else 2.5))
	if crossed and trail and crossed_mid:
		jumps_done += 1
		_flow_up()
	if crossed and trail:
		vy += jump_blast                                  # the swirl lets go: a hard blast off the lip
		_vx_blast = 1.0
		_boost_t = maxf(_boost_t, 1.2)
		_fov_punch = 12.0
		_shake = 1.4
		_flash = maxf(_flash, 0.35)
		_burst(spos + Vector3(0, 0.6, 0), Color(1.0, 0.55, 1.0), 90, 16.0, 0.9, 1.1, Vector3(0, 1, 0.5), 70.0, -5.0)
		_burst(spos + Vector3(0, 0.6, 0), Color(1.0, 0.95, 0.6), 50, 24.0, 0.6, 0.8, Vector3(0, 0.6, 1), 35.0, -3.0)
		Game.sfx(&"boom")
		GazeProvider.pm.buzz([60, 40])
		_cheer("BLAST!", Color(1.0, 0.6, 1.0), 1.6)
		Game.sfx(&"snap")
		if _music != null:
			_music.bump(0.45)
		if crossed_k.get("super", false):
			vy += 9.0                                            # the super ramp: a lot more height, and a face to pull straight away, worth double
			_boost_t = maxf(_boost_t, 2.4)
			_face_next = 0.0
			_super_face = true
			_cheer("SUPER AIR!", Color(1.0, 0.9, 0.2), 2.2)
	if crossed:
		vy += 1.5 * float(chain_lvl)                      # a longer chain launches harder
		_chain_hit("ramp")
		_mix_add("ramp")
		if _ramp_charge > 0.15:
			vy += 3.0 * _ramp_charge
			pops_done += 1
			_toast("CHARGED POP!" if _ramp_charge > 0.7 else "POP!", Color(1.0, 0.85, 0.4))
			_burst(spos + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.4), 30 + int(40.0 * _ramp_charge), 10.0, 0.7, 1.0, Vector3(0, 1, 0.4), 50.0, -4.0)
			Game.sfx(&"boing")
			_fov_punch = 4.0 + 5.0 * _ramp_charge
		_ramp_charge = 0.0


var _pad_mesh: ArrayMesh = null


## The six chevron bars of a pad, joined into one mesh, built once and shared by every pad.
func _pad_mesh_get() -> ArrayMesh:
	if _pad_mesh != null:
		return _pad_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 0.16, 0.7)
	for i in 3:
		for sx in [-1.0, 1.0]:
			st.append_from(bm, 0, Transform3D(Basis(Vector3.UP, -float(sx) * 0.55), Vector3(float(sx) * 1.4, 0.22, -float(i) * 2.4)))          # the outer ends trail behind and the point leads: a chevron down the slope
	_pad_mesh = st.commit()
	return _pad_mesh


var _gem_mesh: ArrayMesh = null


## The boost crystal: a faceted diamond (two cones base to base) with a thin ring round its middle, in one mesh, built once and shared.
func _gem_mesh_get() -> ArrayMesh:
	if _gem_mesh != null:
		return _gem_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := CylinderMesh.new()
	up.top_radius = 0.0
	up.bottom_radius = 0.7
	up.height = 1.1
	up.radial_segments = 6
	up.rings = 1
	var dn := CylinderMesh.new()
	dn.top_radius = 0.7
	dn.bottom_radius = 0.0
	dn.height = 1.1
	dn.radial_segments = 6
	dn.rings = 1
	st.append_from(up, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0)))
	st.append_from(dn, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.55, 0.0)))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.05
	tm.rings = 18
	tm.ring_segments = 4
	st.append_from(tm, 0, Transform3D.IDENTITY)
	_gem_mesh = st.commit()
	return _gem_mesh


func _make_pad(row: Dictionary, x: float, z: float, epic: bool, with_pool: bool = true) -> void:
	var col := Color(1.0, 0.55, 0.1) if not epic else Color(1.0, 0.25, 0.55)
	var mat := _fx_mat("solid", col, 2.6)
	var holder := Node3D.new()
	add_child(holder)
	var bars := _mi(holder, _pad_mesh_get(), mat, Vector3(x, terrain_h(x, z - 2.2), z), true)
	bars.rotation.x = -atan(_grad(x, z - 2.2).y)
	if with_pool:
		var pool := _mi(holder, _quad(8.0), _fx_mat("ground", Color(col.r, col.g, col.b, 0.5)), Vector3(x, terrain_h(x, z - 2.2) + 0.15, z - 2.2), true)
		pool.rotation.x = -PI * 0.5 - atan(_grad(x, z - 2.2).y)
	# and a crystal hanging just over it, turning slowly: the flat bars cannot be seen from far off at the height of the board, this can
	var gy := terrain_h(x, z - 2.2) + 1.35
	var gem := _mi(holder, _kit_mesh("crystal", Color(1.0, 0.62, 0.15) if not epic else Color(1.0, 0.3, 0.6)), _mol_material(), Vector3(x, gy, z - 2.2), true)
	gem.scale = Vector3.ONE * 1.25
	_mi(gem, _quad(3.6), _fx_mat("halo", Color(col.r, col.g, col.b, 0.55)), Vector3.ZERO)
	(row["nodes"] as Array).append(holder)
	(row["pads"] as Array).append({"x": x, "z": z, "used": false, "epic": epic, "gem": gem, "gy": gy, "ph": _rng.randf() * TAU})


func _update_pads() -> void:
	if _finished or not grounded:
		return
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) > 130.0:
			continue
		for p in r["pads"]:
			if p["used"]:
				continue
			if absf(float(p["z"]) - 2.2 - spos.z) < 3.4 and absf(float(p["x"]) - spos.x) < 3.2:
				p["used"] = true
				if p.has("gem") and is_instance_valid(p["gem"]):
					(p["gem"] as Node3D).visible = false
				pads_hit += 1
				Game.sfx(&"pad_boost")          # the push of a speed pad is heard
				_boost_t = maxf(_boost_t, 1.8)
				var fwd := Vector2(sin(heading), -cos(heading))
				var sp0 := vel.length()
				vel += fwd * 5.0 * _bm_pad
				if vel.length() > maxf(SPEED_CAP, sp0):
					vel = vel.normalized() * maxf(SPEED_CAP, sp0)
				_fov_punch = 7.0
				_shake = maxf(_shake, 0.25)
				_burst(spos + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2), 40, 12.0, 0.6, 0.9, Vector3(0, 0.3, 1.0), 40.0, -3.0)
				Game.sfx(&"buff_boost")
				_toast("LAUNCH PAD" if p["epic"] else "BOOST PAD", Color(1.0, 0.7, 0.3))
				_mix_add("pad")


# --------------------------------------------------------------------------
# TOYS: things to bounce off and ride through, set between the choice points. Every one feeds the combo, and four DIFFERENT kinds inside a few seconds (these, boost pads,
# air rings) pay a SURPRISE.
#   bumper   a triangle of glowing posts, like pinball pop bumpers: ride into one and it kicks you sideways and pays
#   spring   a springboard that throws you up for a free hop
#   gates    rows of lit arches in three colours, one of each colour per row: take the same colour row after row for a COLOUR CHAIN
# --------------------------------------------------------------------------
const GATE_COLS := [Color(0.2, 0.95, 1.0), Color(1.0, 0.3, 0.9), Color(1.0, 0.85, 0.2)]
var _toy_mats: Dictionary = {}
var _gate_streak: int = 0
var _gate_col: int = -1
var _mix: Dictionary = {}
var _mix_t: float = 0.0


func _toy_mat(key: String, col: Color, e: float) -> StandardMaterial3D:
	if not _toy_mats.has(key):
		_toy_mats[key] = _fx_mat("solid", col, e)
	return _toy_mats[key]


var _lane_n := [0, 0, 0]


## Left, middle or right for the next thing: whichever has had least so far (a tie is broken by chance), so the three lanes fill evenly and it is never side after side the same.
func _lane_turn() -> float:
	var lo: int = mini(_lane_n[0], mini(_lane_n[1], _lane_n[2]))
	var pick: Array = []
	for i in 3:
		if _lane_n[i] == lo:
			pick.append(i)
	var li: int = pick[_rng.randi() % pick.size()]
	_lane_n[li] += 1
	return float(li - 1)


# LIGHT SHAFTS: tall soft beams of sun slanting down between the trees beside the trail, two or three to a stretch. Plain and warm on the plain run; as the molecules come on they
# take on moving bands of colour and brighten, so the light itself goes strange. One shared material and one draw per stretch; nothing is lit by them.
var _shaft_mat: ShaderMaterial = null
var _shaft_mesh: QuadMesh = null
const SHAFT_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float dose = 0.0;
void fragment() {
	float e = smoothstep(0.0, 0.4, UV.x) * smoothstep(1.0, 0.6, UV.x);
	float v = smoothstep(1.0, 0.7, UV.y) * smoothstep(0.0, 0.55, UV.y);
	float sh = 0.75 + 0.25 * sin(UV.x * 23.0 + TIME * 0.7) * sin(UV.x * 7.0 - TIME * 0.4);
	vec3 rb = 0.5 + 0.5 * cos(6.2831 * (UV.y * 1.5 + TIME * 0.15 + vec3(0.0, 0.33, 0.67)));
	ALBEDO = mix(COLOR.rgb, rb, clamp(dose * 1.4, 0.0, 0.85));
	ALPHA = e * v * sh * COLOR.a * (1.0 + dose * 1.6);
}
"""


func _shaft_material() -> ShaderMaterial:
	if _shaft_mat == null:
		var sh := Shader.new()
		sh.code = SHAFT_SHADER
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = sh
		_shaft_mesh = QuadMesh.new()
		_shaft_mesh.size = Vector2(13.0, 64.0)
	return _shaft_mat


func _gen_shafts(row: Dictionary, z0: float) -> void:
	if not trail or not _cfg_dyn:
		return
	_shaft_material()
	var xf: Array[Transform3D] = []
	var cols := PackedColorArray()
	for off: float in [30.0, 95.0, 150.0]:
		if _rng.randf() > 0.7:
			continue
		var sz := z0 - off - _rng.randf_range(0.0, 20.0)
		var sd := -1.0 if _rng.randf() < 0.5 else 1.0
		var sx := trail_x(sz) + sd * _rng.randf_range(15.0, 30.0)
		var bs := Basis(Vector3.UP, sd * 0.35) * Basis(Vector3(0, 0, 1), -sd * 0.42)          # leaning in over the trail, turned a little toward the rider
		xf.append(Transform3D(bs.scaled(Vector3(_rng.randf_range(0.7, 1.5), 1.0, 1.0)), Vector3(sx, terrain_h(sx, sz) + 24.0, sz)))
		cols.append(Color(1.0, 0.9, 0.72, _rng.randf_range(0.09, 0.15)))
	_add_mm(row, _shaft_mesh, xf, cols, _shaft_mat)


func _gen_toys(row: Dictionary, z0: float, taken: Array) -> void:
	var toys: Array = []
	row["toys"] = toys
	_gen_shafts(row, z0)
	# MOLECULES come at their own pace, not as one of the toys: a row every so many metres, closer together when the player is behind the session's curve (the pacer) and
	# further apart when ahead of it. About one row every seven seconds at an even pace; a row is moved on a little if something already stands there.
	if _mol_rows and not _mol_dbg:
		var tries := 0
		while _mol_next_z > z0 - 180.0 and _mol_next_z > finish_z + 130.0 and tries < 8:
			tries += 1
			var mz := minf(_mol_next_z, z0 - 6.0)
			var blocked := false
			for zt: float in taken:
				if absf(zt - mz) < 34.0:
					blocked = true
			if blocked:
				_mol_next_z = mz - 22.0
				continue
			_make_pills(row, toys, mz, 0.0)
			taken.append(mz)
			var bias := _pacer.spawn_bias(_mol_avg()) if _pacer != null else 1.0
			_mol_next_z = mz - clampf(MOL_GAP_M / bias, 105.0, 900.0) * _rng.randf_range(0.85, 1.15)
	for off: float in [48.0, 102.0, 156.0]:
		var tz := z0 - off + _rng.randf_range(-8.0, 8.0)
		if tz < finish_z + 130.0 or _rng.randf() > 0.8:
			continue
		var near := false
		for zt: float in taken:
			if absf(zt - tz) < 30.0:
				near = true
		if near:
			continue
		var side: float = _lane_turn()
		var roll := _rng.randf()
		var pill_odds := (0.06 if -tz < 500.0 else 0.2) * (_pacer.spawn_bias(_mol_avg()) if _pacer != null else 1.0)          # the pacer: more when the player is behind the session's curve
		if _mol_dbg and _journey != null:
			_make_pills(row, toys, tz, [-1.0, 1.0, 0.0][_rng.randi() % 3])          # ?mol: every slot is a row of molecules
		elif _journey != null and not _mol_rows and ((not _pill_seen and -tz > 160.0) or _rng.randf() < pill_odds):
			_pill_seen = true
			_make_pills(row, toys, tz, side)
		elif roll < 0.20:
			_make_bumpers(row, toys, tz, side)
		elif roll < 0.42:
			_make_spring(row, toys, tz, side)
		elif roll < 0.60:
			_make_gates(row, toys, tz)
		else:
			var bs: float = _lane_turn()
			_boost_row(row, trail_x(tz) + bs * 7.0, tz, bs, _toy_g)
			_toy_g += 1


# --------------------------------------------------------------------------
# ALL DRESSED (see DhJourney): the world changes in waves, and each world changes the ride.
# --------------------------------------------------------------------------
var _journey: DhJourney = null
var _exc: float = 0.0
var _dbg_t: float = 1.0
var _back_dbg: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("back")
var _hi_dbg: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("high")          # ?high: the camera up where a big jump would take it, to look at the edges of the world


## How hard the run is going, 0 to 1: speed, a flow going, boosts, a chain of things hit. The trip is made to come on with it.
func excitement() -> float:
	return _exc


func _exc_tick(delta: float) -> void:
	var sp := clampf((-vel.y - 20.0) / 30.0, 0.0, 1.0)
	var fl := clampf(float(chain) / 12.0, 0.0, 1.0)
	var bo := 1.0 if _boost_t > 0.0 else 0.0
	var ln := clampf(float(_links) / 8.0, 0.0, 1.0)
	var goal := clampf(0.45 * sp + 0.25 * fl + 0.15 * bo + 0.15 * ln, 0.0, 1.0)
	_exc += (goal - _exc) * (1.0 - exp(-delta / 1.5))
var _jw: String = "alpine"
var _spd_k: float = 1.0
var _bm_bump: float = 1.0
var _bm_spring: float = 1.0
var _bm_pad: float = 1.0
var _base_haz: float = 0.6
var _base_jump: float = 0.72
var _base_pad: float = 0.12
var _base_glint: float = 1.0
var _base_grip: float = 1.0
var _cfg_intensity: float = 0.75
var _cfg_trip: int = 1          # the trip level for All dressed: 0 gentle, 1 normal, 2 wild
var _cfg_dyn: bool = true
var _cfg_snow: bool = true
var _cfg_fluffy: bool = false


func biome_apply(m: Dictionary, k: float, diff: float) -> void:
	_spd_k = clampf(lerpf(1.0, float(m["spd"]), k) * (1.0 + 0.4 * (diff - 1.0)), 0.8, 1.7)
	hazard_share = clampf(_base_haz * lerpf(1.0, float(m["haz"]), k) * (1.0 + 0.6 * (diff - 1.0)), 0.0, 1.0)
	jump_chance = clampf(_base_jump * lerpf(1.0, float(m["jumps"]), k), 0.0, 1.0)
	pad_chance = clampf(_base_pad * lerpf(1.0, float(m["pads"]), k), 0.0, 1.0)
	glint_k = clampf(_base_glint * lerpf(1.0, float(m["glint"]), k), 0.5, 4.0)
	grip_lag = _base_grip * lerpf(1.0, float(m["grip"]), k)
	_bm_bump = lerpf(1.0, float(m["bump"]), k)
	_bm_spring = lerpf(1.0, float(m["spring"]), k)
	_bm_pad = lerpf(1.0, float(m["padk"]), k)
	glint_k = clampf(glint_k * (1.0 + 0.6 * _mbody[0] / 6.0), 0.5, 5.0)          # mescaline: more glints
	_bm_pad *= 1.0 + 0.5 * _mbody[2] / 6.0          # 2C-B: stronger boosts
	jump_chance = clampf(jump_chance * (1.0 + 0.35 * _mbody[3] / 6.0), 0.0, 1.0)          # 2C-E: more ramps
	_bm_spring *= 1.0 + 0.6 * _mbody[4] / 6.0          # 2C-T-2: stronger slingshots
	_spd_k = clampf(_spd_k * (1.0 + 0.12 * _mbody[5] / 6.0), 0.8, 1.9)          # 2C-T-7: faster
	if _pacer != null:
		hazard_share = clampf(hazard_share * _pacer.hazard_k(), 0.0, 1.0)          # what the phase of the session asks for (nothing hostile for the first twenty seconds)
	if _dir != null and is_instance_valid(_dir):
		var pace := 0.7 + 0.6 * _dir.wave_at(8.0)          # the course is built about eight seconds ahead of the board: where the wave will be when you get there
		hazard_share = clampf(hazard_share * pace, 0.0, 1.0)          # more on the crest of a wave, fewer in the lull
		jump_chance = clampf(jump_chance * (1.6 - 0.6 * pace), 0.0, 1.0)          # and big easy ramps in the lull
		pad_chance = clampf(pad_chance * (1.6 - 0.6 * pace), 0.0, 1.0)


## One piece of a world at a time (see ThemeFX.apply_part): the journey lets a world come on layer by layer, flickering, and go the same way.
func journey_sky(world: String, k: float) -> void:
	_jw = world if k > 0.05 else "alpine"
	if _lvl != null:
		ThemeFX.blend_env(_lvl, world, k)


func journey_part(world: String, part: String) -> void:
	if part == "sky" or part == "skymat":
		_jw = world
	if _lvl != null:
		ThemeFX.apply_part(_lvl, self, world, part, 1.0, _cfg_dyn, _cfg_snow, _cfg_fluffy)


var _jpost_mode: int = 0
var _jpost_light: bool = false
var _pw_done: Dictionary = {}


## A world is built a little ahead of its wave, off to the side: a 16 pixel world of its own, never on the screen, gets the sky, then the ground, then the trees of that world one
## after another, so the phone does its building in three small pieces during a calm stretch and not all at once when the wave arrives.
func journey_prewarm(world: String) -> void:
	if _pw_done.has(world) or _lvl == null or not OS.has_feature("web"):
		return
	_pw_done[world] = true
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var main_env: Environment = _lvl.world_env.environment
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = main_env.fog_enabled
	env.fog_density = main_env.fog_density
	env.glow_enabled = main_env.glow_enabled
	env.tonemap_mode = main_env.tonemap_mode
	env.adjustment_enabled = main_env.adjustment_enabled
	var sk := Sky.new()
	sk.sky_material = ProceduralSkyMaterial.new()
	env.sky = sk
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cm := Camera3D.new()
	vp.add_child(cm)
	cm.current = true
	await get_tree().create_timer(0.5).timeout
	var sm := Themes.sky_material(world)
	if sm != null:
		sk.sky_material = sm
	await get_tree().create_timer(0.8).timeout
	var gm := Themes.ground_material(world)
	if gm != null:
		var gmi := MeshInstance3D.new()
		gmi.mesh = PlaneMesh.new()
		gmi.material_override = gm
		vp.add_child(gmi)
		gmi.position = Vector3(0.0, -1.0, -3.0)
	await get_tree().create_timer(0.8).timeout
	var vm := Themes.veg_material(world)
	if vm != null:
		var vmi := MeshInstance3D.new()
		vmi.mesh = SphereMesh.new()
		vmi.material_override = vm
		vp.add_child(vmi)
		vmi.position = Vector3(0.0, 0.0, -3.0)
	await get_tree().create_timer(0.8).timeout
	vp.queue_free()


## The full-screen pass for the journey: while a world is coming on, the psychedelic pass with its onset (first only round the horizon, then everywhere); at full strength a
## world with a look of its own gets that look. onset 0 is off.
func journey_post(world: String, onset: float, want_trip: bool, strength: float) -> void:
	var fx := _lvl.get_node_or_null("ThemeFX") as ThemeFX if _lvl != null else null
	if fx == null or fx.post == null:
		return
	var mav := _mol_avg()
	if mav > 0.01:          # what is felt of the six holds the pass on, deeper the more of them and the higher
		onset = maxf(onset, clampf(mav * 1.3, 0.0, 1.0))
		want_trip = true
		strength = maxf(strength, 0.5 + 0.7 * mav)
	var light := onset < 0.3          # a hint or a flicker needs no tracers: no second render of the world, nothing to build, so it can come and go instantly
	if _pill_k > 0.001:          # a pill's flicker rides on top of whatever the journey is doing
		onset = maxf(onset, _pill_k)
		want_trip = true
		strength = maxf(strength, 0.9)
	var m := 0
	if onset > 0.001:
		if want_trip and (onset < 0.999 or Themes.post_mode(world) < 2):
			m = 1
		elif onset >= 0.999:
			m = Themes.post_mode(world)
	if m != _jpost_mode or (m == 1 and light != _jpost_light):
		_jpost_mode = m
		_jpost_light = light
		fx.post.light = light
		fx.post.set_look(m, clampf(strength, 0.3, 1.2))
	_trip_on = _jpost_mode == 1
	if _jpost_mode == 0:
		trip = 0.0          # between waves the meter is empty (it only runs down while the pass is on)
		_trip_tier = 0
	if fx.post.mat != null:
		fx.post.mat.set_shader_parameter("onset", clampf(onset, 0.0, 1.0) if _jpost_mode == 1 else 1.0)


## Everything back to the plain alpine run (a new run, or the end of a wave).
func journey_reset() -> void:
	for part in ["sky", "skymat", "ground", "veg", "light"]:
		journey_part("alpine", part)
	journey_post("alpine", 0.0, false, 0.3)
	biome_apply(DhJourney.BIOME["alpine"], 1.0, 1.0)


var _toy_g: int = 100000


## A row of three boost pads down one lane, one after another: a thing to look at and carve over to, and a chain in itself (every pad is a link).
func _beacon(row: Dictionary, x: float, z: float, col: Color) -> void:
	_buff_assets("orb")
	(row["nodes"] as Array).append(_mi(self, _buff_mesh["beacon"], _fx_mat("add", Color(col.r, col.g, col.b, 0.32)), Vector3(x, terrain_h(x, z) + 4.6, z)))          # a tall thin light, so a thing can be picked out from far up the slope


func _boost_row(row: Dictionary, x: float, z: float, sd: float, g: int) -> void:
	for i in 3:
		_make_pad(row, x, z - float(i) * 13.0, false, false)
	var pool := _mi(self, _quad(22.0), _fx_mat("ground", Color(1.0, 0.55, 0.1, 0.45)), Vector3(x, terrain_h(x, z - 15.0) + 0.15, z - 15.0))          # one wide pool of orange light for the whole row
	pool.rotation.x = -PI * 0.5 - atan(_grad(x, z - 15.0).y)
	(row["nodes"] as Array).append(pool)
	_beacon(row, x, z - 2.0, Color(1.0, 0.6, 0.15))
	(row["feats"] as Array).append({"kind": "toy", "kx": x, "za": z + 24.0, "zl": z, "zb": z - 30.0, "sd": sd, "done": false, "want": 0.0, "away": 0.0, "g": g, "cd": true})
# --------------------------------------------------------------------------
# THE KIT: everything you can pick up or bounce off is built the way the molecules are (balls joined by sticks, colours in the vertices, the same material and the same light),
# so the whole course reads as one set. Each shape is one mesh, built once per colour and shared.
#   crystal  an octahedron cell round a bright core            (boost pads and the boost pickup)
#   cage     an icosahedron cage round a core                  (the shield)
#   rings    two six-rings locked through each other           (the multiplier)
#   tetra    four big atoms round a small one                  (the treat)
#   atom     a big atom with eight small ones standing off it  (the bumpers)
#   hex      one six-ring, upright, with a core                (the colour gates)
# --------------------------------------------------------------------------
var _kit_cache: Dictionary = {}


func _kit_mesh(kind: String, col: Color) -> ArrayMesh:
	var key := kind + col.to_html(false)
	if _kit_cache.has(key):
		return _kit_cache[key]
	var pts: Array = []          # [position, radius, colour]
	var bonds: Array = []        # [i, j]
	var pale := col.lerp(Color(1, 1, 1), 0.72)
	var deep := col.darkened(0.25)
	var stick := 0.07
	match kind:
		"crystal":
			pts.append([Vector3.ZERO, 0.36, col])
			for v: Vector3 in [Vector3(0, 1.15, 0), Vector3(0, -1.15, 0), Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8)]:
				pts.append([v, 0.17, pale])
			for i in range(3, 7):
				bonds.append([1, i])
				bonds.append([2, i])
			for pr in [[3, 5], [5, 4], [4, 6], [6, 3]]:
				bonds.append(pr)
		"cage":
			pts.append([Vector3.ZERO, 0.42, col])
			var ph := (1.0 + sqrt(5.0)) * 0.5
			for a: float in [-1.0, 1.0]:
				for b: float in [-ph, ph]:
					pts.append([Vector3(0, a, b).normalized() * 1.15, 0.14, pale])
					pts.append([Vector3(a, b, 0).normalized() * 1.15, 0.14, pale])
					pts.append([Vector3(b, 0, a).normalized() * 1.15, 0.14, pale])
			for i in range(1, 13):
				for j in range(i + 1, 13):
					if ((pts[i][0] as Vector3) - (pts[j][0] as Vector3)).length() < 1.3:
						bonds.append([i, j])
			stick = 0.055
		"rings":
			for r in 2:
				for i in 6:
					var a2 := float(i) * TAU / 6.0
					var v2 := Vector3(cos(a2), sin(a2), 0.0) * 0.85
					if r == 1:
						v2 = Vector3(v2.x + 0.85, 0.0, v2.y)
					else:
						v2.x -= 0.0
					pts.append([v2 - Vector3(0.42, 0, 0), 0.19, col if r == 0 else pale])
				for i in 6:
					bonds.append([r * 6 + i, r * 6 + (i + 1) % 6])
		"tetra":
			pts.append([Vector3.ZERO, 0.24, pale])
			for v3: Vector3 in [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]:
				pts.append([v3.normalized() * 0.85, 0.4, col])
			for i in range(1, 5):
				bonds.append([0, i])
			stick = 0.1
		"atom":
			pts.append([Vector3.ZERO, 0.72, col])
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						pts.append([Vector3(sx, sy, sz).normalized() * 1.2, 0.2, pale])
						bonds.append([0, pts.size() - 1])
			stick = 0.08
		_:
			pts.append([Vector3.ZERO, 0.3, pale])
			for i in 6:
				var a3 := float(i) * TAU / 6.0
				pts.append([Vector3(cos(a3), sin(a3), 0.0) * 1.2, 0.22, col if i % 2 == 0 else deep])
			for i in 6:
				bonds.append([1 + i, 1 + (i + 1) % 6])
			stick = 0.09
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 10
	ball.rings = 5
	var ba := ball.get_mesh_arrays()
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
	for pt in pts:
		for k in bi:
			st.set_color(pt[2])
			st.set_normal(bn[k])
			st.add_vertex((pt[0] as Vector3) + bv[k] * float(pt[1]))
	var rod := CylinderMesh.new()
	rod.top_radius = 1.0
	rod.bottom_radius = 1.0
	rod.height = 1.0
	rod.radial_segments = 6
	rod.rings = 1
	rod.cap_top = false
	rod.cap_bottom = false
	var ra := rod.get_mesh_arrays()
	var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
	var rn: PackedVector3Array = ra[Mesh.ARRAY_NORMAL]
	var ri: PackedInt32Array = ra[Mesh.ARRAY_INDEX]
	var bcol := Color(0.86, 0.88, 0.95)
	for bd in bonds:
		var a: Vector3 = pts[int(bd[0])][0]
		var b: Vector3 = pts[int(bd[1])][0]
		var d := b - a
		var ln := d.length()
		if ln < 0.001:
			continue
		var y := d / ln
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		var rb := Basis(x, y, z)
		var sb := Basis(x * stick, y * ln, z * stick)
		var mid := (a + b) * 0.5
		for k in ri:
			st.set_color(bcol)
			st.set_normal(rb * rn[k])
			st.add_vertex(mid + sb * rv[k])
	var m := st.commit()
	_kit_cache[key] = m
	return m


var _toy_meshes: Dictionary = {}


## Sweets are built from a few round shapes, shared between all of one kind.
func _tm(key: String) -> Mesh:
	if _toy_meshes.has(key):
		return _toy_meshes[key]
	var m: Mesh
	match key:
		"cup":
			var c := CylinderMesh.new()
			c.top_radius = 1.25
			c.bottom_radius = 0.85
			c.height = 0.95
			c.radial_segments = 12
			m = c
		"frost":
			var sp := SphereMesh.new()
			sp.radius = 1.3
			sp.height = 2.0
			sp.radial_segments = 12
			sp.rings = 6
			m = sp
		"cherry":
			var sp2 := SphereMesh.new()
			sp2.radius = 0.4
			sp2.height = 0.8
			sp2.radial_segments = 8
			sp2.rings = 4
			m = sp2
		"coil":
			var t := TorusMesh.new()
			t.inner_radius = 0.55
			t.outer_radius = 0.95
			t.rings = 16
			t.ring_segments = 8
			m = t
		"disc":
			var d := CylinderMesh.new()
			d.top_radius = 1.7
			d.bottom_radius = 1.7
			d.height = 0.3
			d.radial_segments = 16
			m = d
		"lolly":
			var l := CylinderMesh.new()
			l.top_radius = 1.2
			l.bottom_radius = 1.2
			l.height = 0.3
			l.radial_segments = 16
			m = l
		"pill":
			var pc := CapsuleMesh.new()
			pc.radius = 0.6
			pc.height = 2.4
			pc.radial_segments = 12
			pc.rings = 3
			m = pc
		"lring":
			var lr := TorusMesh.new()
			lr.inner_radius = 0.5
			lr.outer_radius = 0.72
			lr.rings = 16
			lr.ring_segments = 6
			m = lr
		_:
			var st := CylinderMesh.new()
			st.top_radius = 0.09
			st.bottom_radius = 0.09
			st.height = 2.3
			st.radial_segments = 5
			m = st
	_toy_meshes[key] = m
	return m


func _toy_feat(row: Dictionary, x: float, z: float, sd: float, g: int) -> void:
	# the toy can be looked at and chosen like a rail or a jump: a ring on it, a look at it (or the side it is on) and the board carves over
	(row["feats"] as Array).append({"kind": "toy", "kx": x, "za": z + 24.0, "zl": z, "zb": z - 6.0, "sd": sd, "done": false, "want": 0.0, "away": 0.0, "g": g, "cd": true})


var _pacer: DhPacer = null
const MOL_GAP_M := 250.0          # metres between molecule rows at an even pace (about seven seconds of riding)
var _mol_rows: bool = false
var _mol_next_z: float = -150.0
var _pill_seen: bool = false
var _mol_dbg: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("mol")          # ?mol: a row of molecules right at the start, to look at
var _pill_k: float = 0.0          # how far the pill flash has come on, 0 to 1
var _pill_t: float = 0.0          # how long it is still held
var _pill_n: int = 0          # pills in this chain
var _pill_gap: float = 0.0
var _pill_live: bool = false


## PILLS: a short row of capsules floating over the snow, turning. Eat one and the world flashes trippy for a few seconds; one after another and it holds and deepens.
func _make_pills(row: Dictionary, toys: Array, z: float, side: float) -> void:
	var g := _toy_g
	_toy_g += 1
	var picked: Array = []
	for r in 3:
		# three different molecules side by side, one in each lane: which one to look at is the choice
		var sd: float = [-1.0, 0.0, 1.0][r]
		var pz := z - 2.0 * absf(sd)
		var px := trail_x(pz) + sd * 8.0
		var mid := _pick_molecule(picked)
		picked.append(mid)
		var ca: Color = MolData.MOLS[mid]["c"]
		var hold := Node3D.new()
		add_child(hold)
		_place(hold, Vector3(px, terrain_h(px, pz) + 2.2, pz))
		var spin := Node3D.new()
		hold.add_child(spin)
		_mi(spin, _mol_mesh(mid), _mol_material(), Vector3.ZERO)
		spin.rotation = Vector3(0.5, 0.0, 0.3)
		_mi(hold, _quad(5.0), _fx_mat("halo", Color(ca.r, ca.g, ca.b, 0.6)), Vector3.ZERO)
		hold.scale = Vector3.ONE * 1.6
		(row["nodes"] as Array).append(hold)
		toys.append({"kind": "pill", "x": px, "z": pz, "n": hold, "spin": spin, "t": 0, "col": ca, "y": hold.position.y, "name": String(MolData.MOLS[mid]["name"]), "id": mid})
		_beacon(row, px, pz, ca)
		_toy_feat(row, px, pz, sd, g)


## Which molecule the next pickup is: any of the six, the ones not yet near the top more often (a run is built of the climb, so what is missing keeps turning up).
func _pick_molecule(exclude: Array = []) -> String:
	var wsum := 0.0
	var ws: Array = []
	for i in 6:
		var w := 0.3 if _mdose[i] >= 5.5 else 1.0 + 0.5 * (6.0 - _mdose[i])
		if exclude.has(String(MolData.ORDER[i])):
			w = 0.0
		ws.append(w)
		wsum += w
	var r := _rng.randf() * wsum
	for i in 6:
		r -= float(ws[i])
		if r <= 0.0:
			return String(MolData.ORDER[i])
	return String(MolData.ORDER[5])


var _mol_cache: Dictionary = {}
var _mol_mat: StandardMaterial3D = null
const MOL_EL_COL := {"H": Color(0.95, 0.95, 1.0), "O": Color(1.0, 0.22, 0.2), "N": Color(0.25, 0.42, 1.0), "S": Color(1.0, 0.9, 0.2), "Br": Color(0.70, 0.25, 0.15)}
const MOL_EL_R := {"H": 0.36, "C": 0.62, "O": 0.60, "N": 0.62, "S": 0.82, "Br": 0.92}


func _mol_material() -> StandardMaterial3D:
	if _mol_mat == null:
		_mol_mat = StandardMaterial3D.new()
		_mol_mat.vertex_color_use_as_albedo = true
		_mol_mat.roughness = 0.45
		_mol_mat.emission_enabled = true
		_mol_mat.emission = Color(0.22, 0.22, 0.26)
	return _mol_mat


## One real molecule (MolData, from tools/mol_gen.py) as a single ball-and-stick mesh with its colours in the vertices: carbon in the molecule's own colour, hydrogen white, oxygen red,
## nitrogen blue, sulphur yellow, bromine brown. The ring's double bonds are drawn as two sticks. Built once per molecule.
func _mol_mesh(id: String) -> ArrayMesh:
	if _mol_cache.has(id):
		return _mol_cache[id]
	var md: Dictionary = MolData.MOLS[id]
	var sc := 0.3
	var accent: Color = md["c"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 8
	ball.rings = 4
	var ba := ball.get_mesh_arrays()
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
	var pts: Array = []
	for a in md["atoms"]:
		var el := String(a[0])
		var c := Vector3(float(a[1]), float(a[2]), float(a[3])) * sc
		pts.append(c)
		var col: Color = accent if el == "C" else MOL_EL_COL[el]
		var r: float = float(MOL_EL_R[el]) * sc
		for k in bi:
			st.set_color(col)
			st.set_normal(bn[k])
			st.add_vertex(c + bv[k] * r)
	var rod := CylinderMesh.new()
	rod.top_radius = 1.0
	rod.bottom_radius = 1.0
	rod.height = 1.0
	rod.radial_segments = 6
	rod.rings = 1
	rod.cap_top = false
	rod.cap_bottom = false
	var ra := rod.get_mesh_arrays()
	var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
	var rn: PackedVector3Array = ra[Mesh.ARRAY_NORMAL]
	var ri: PackedInt32Array = ra[Mesh.ARRAY_INDEX]
	var bcol := Color(0.86, 0.88, 0.95)
	for bd in md["bonds"]:
		var p0: Vector3 = pts[int(bd[0])]
		var p1: Vector3 = pts[int(bd[1])]
		var d := p1 - p0
		var blen := d.length()
		var up := d / blen
		var ref := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP
		var xa := up.cross(ref).normalized()
		var bs := Basis(xa, up, xa.cross(up))
		var offs: Array = [Vector3.ZERO]
		var br := 0.17 * sc
		if int(bd[2]) == 2:
			var off := up.cross(Vector3(0.0, 0.0, 1.0)).normalized() * 0.15 * sc
			offs = [off, -off]
			br = 0.10 * sc
		for off2: Vector3 in offs:
			for k in ri:
				st.set_color(bcol)
				st.set_normal((bs * rn[k]).normalized())
				var lv := rv[k]
				st.add_vertex((p0 + p1) * 0.5 + off2 + bs * Vector3(lv.x * br, lv.y * blen, lv.z * br))
	var mesh := st.commit()
	_mol_cache[id] = mesh
	return mesh


func _pill_eat(t: Dictionary) -> void:
	t["t"] = 1 << 60
	(t["n"] as Node3D).visible = false
	_pill_n = _pill_n + 1 if _pill_gap > 0.0 else 1
	_pill_gap = 6.0
	_dose += 0.42          # (all six together open the waves)
	var mi: int = MolData.ORDER.find(String(t["id"]))
	_mdose[mi] = minf(_mdose[mi] + 1.0, 6.0)
	_mol_seen = true
	_flick = 1.0          # but there is an instant glimmer
	_burst(Vector3(float(t["x"]), float(t["y"]), float(t["z"])), t["col"], 22, 8.0, 0.6, 1.0)
	_gain(int(120.0 * groove * float(_pill_n)))
	_trip_add(0.25)
	_flow_up(1)
	_mix_add("pill")
	_shake = maxf(_shake, 0.12)
	Game.sfx(StringName("mol%d" % mi))          # each molecule has its own note
	_toast("%s  %d/6" % [String(t["name"]), int(_mdose[mi])], t["col"])          # what it was
	if _pill_n == 3:
		_cheer("TRIPPING", Color(1.0, 0.3, 0.9), 1.2)


var _mdose := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])          # per molecule (MolData.ORDER): what has been taken and not worn off, 0 to 6
var _mbody := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])          # per molecule: what is felt, following the dose slowly
var _mol_seen: bool = false
var _mol_hurt_t: float = 0.0
var _dmt_on: bool = false
var _dose: float = 0.0          # what has been taken and not yet worn off (all of them together: it opens the waves)
var _body: float = 0.0          # what is felt: it follows the dose slowly, so the waves come some while after the pills
var _flick: float = 0.0          # the instant glimmer that goes with each pill
var _drift_t: float = 110.0          # time itself adds a little, so a run with no pills still comes on, late


func _mol_avg() -> float:
	return (_mbody[0] + _mbody[1] + _mbody[2] + _mbody[3] + _mbody[4] + _mbody[5]) / 36.0


## 0 until all six are felt at nearly the top, then 1: the peak.
func _mol_dmt() -> float:
	var mn := 6.0
	for i in 6:
		mn = minf(mn, _mbody[i])
	return smoothstep(0.52, 0.75, mn / 6.0)          # on from about four of each, full at four and a half


var _sb_mol: int = 0
var _mol_hurt_i: int = -1


## A snowball's molecule: one you are holding, more likely the more of it you hold (it is the one with something to lose).
func _pick_held_molecule() -> int:
	var tot := 0.0
	for i in 6:
		tot += _mdose[i] + 0.3
	var r := randf() * tot
	for i in 6:
		r -= _mdose[i] + 0.3
		if r <= 0.0:
			return i
	return 5


## A hazard costs a level of its own molecule and no other (`mol`, from its colour); one with no molecule of its own (a tree) takes a level from one you hold, any of them. A hazard
## of a molecule you do not hold costs nothing: the bar shows what is at stake, and which fights are worth having. A shield takes the crash instead (see _crash).
func _mol_hurt(mol: int) -> void:
	var i := mol
	if i < 0:
		var held: Array = []
		for k in 6:
			if _mdose[k] >= 0.5:
				held.append(k)
		if held.is_empty():
			return
		i = int(held[randi() % held.size()])
	if _mdose[i] < 0.5 and _mbody[i] < 0.5:
		return
	_mdose[i] = maxf(_mdose[i] - 1.0, 0.0)
	_mbody[i] = maxf(_mbody[i] - 1.0, 0.0)
	_mol_hurt_t = 1.0
	_mol_hurt_i = i
	_dose = maxf(_dose - 0.42, 0.0)
	_toast("%s  %d/6" % [String(MolData.MOLS[MolData.ORDER[i]]["name"]), int(_mdose[i])], Color(1.0, 0.35, 0.3))


func _pill_tick(delta: float) -> void:
	if _pacer != null and not _paused:
		_pacer.tick(delta)
	_mol_hurt_t = maxf(_mol_hurt_t - delta * 1.5, 0.0)
	# THE WAY DOWN: what is held above the session's curve wears off faster, so the plateau eases and the comedown really comes down (and a long session climbs slowly)
	var wear := 1.0
	if _pacer != null:
		wear = 1.0 + 12.0 * maxf(_mol_avg() - _pacer.target() - 0.05, 0.0)
	for i in 6:
		_mdose[i] = maxf(_mdose[i] - (0.004 if i == 1 else 0.008) * wear * delta, 0.0)          # each wears off slowly (DOM, the long one, half as fast)
		var rate := 25.0 if _mdose[i] > _mbody[i] else 8.0
		_mbody[i] += (_mdose[i] - _mbody[i]) * (1.0 - exp(-delta / rate))
	var dm := _mol_dmt()
	if dm > 0.5 and not _dmt_on:
		_dmt_on = true
		_cheer("ALL SIX", Color(1.0, 0.85, 0.3), 2.2)
		Game.sfx(&"kaboom")
	elif dm < 0.3:
		_dmt_on = false
	var fxm := _lvl.get_node_or_null("ThemeFX") as ThemeFX if _lvl != null else null
	if fxm != null and fxm.post != null and fxm.post.mat != null:
		var wk := 1.0
		if _dir != null and is_instance_valid(_dir):
			wk = 0.7 + 0.6 * _dir.wave_at(0.0)          # the effects breathe with the music's wave
		var ma := Vector3(_mbody[0], _mbody[1], _mbody[2]) / 6.0
		var mb := Vector3(_mbody[3], _mbody[4], _mbody[5]) / 6.0
		ma = Vector3(pow(ma.x, 1.5), pow(ma.y, 1.5), pow(ma.z, 1.5)) * wk          # each look comes in gently and only at a high level does it take over
		mb = Vector3(pow(mb.x, 1.5), pow(mb.y, 1.5), pow(mb.z, 1.5)) * wk
		fxm.post.mat.set_shader_parameter("mA", ma)
		fxm.post.mat.set_shader_parameter("mB", mb)
		fxm.post.mat.set_shader_parameter("dmt", dm)
	if _shaft_mat != null:
		_shaft_mat.set_shader_parameter("dose", _mol_avg())
	_pill_gap = maxf(_pill_gap - delta, 0.0)
	_flick = maxf(_flick - delta * 2.0, 0.0)          # half a second
	_dose = maxf(_dose - 0.006 * wear * delta, 0.0)
	if _mol_rows:
		_dose = minf(_dose, (_mdose[0] + _mdose[1] + _mdose[2] + _mdose[3] + _mdose[4] + _mdose[5]) * 0.42 + 1.2)          # the waves follow what is held now, not everything ever taken
	_body += (_dose - _body) * (1.0 - exp(-delta / 25.0))
	if _journey != null:
		_drift_t -= delta
		if _drift_t <= 0.0:
			_drift_t = 100.0
			_dose += 0.7
	# the glimmer: two sharp pulses in half a second. Subtle in size, strong in colour: a hint of what is coming
	_pill_k = 0.5 * pow(maxf(sin((1.0 - _flick) * TAU * 1.5), 0.0), 1.4) if _flick > 0.0 else 0.0
	if _journey == null:
		return
	if _pill_k > 0.001 or _mol_avg() > 0.01:
		_pill_live = true
		if _journey.phase == DhJourney.Phase.CALM and _journey.hint() < 0.001:
			journey_post("psychedelic", 0.0, false, 0.9)
	elif _pill_live:
		_pill_live = false
		if _journey.phase == DhJourney.Phase.CALM and _journey.hint() < 0.001:
			journey_post("psychedelic", 0.0, false, 0.3)


## BUMPERS: three cupcakes, pink frosting and a cherry. Ride into one and it bounces you off.
func _make_bumpers(row: Dictionary, toys: Array, z: float, side: float) -> void:
	var cx := trail_x(z) + side * 7.0
	var g := _toy_g
	_toy_g += 1
	var first := true
	for p: Vector2 in [Vector2(0.0, 0.0), Vector2(-3.4, -5.0), Vector2(3.4, -5.0)]:
		var px := cx + p.x
		var pz := z + p.y
		var hold := Node3D.new()
		add_child(hold)
		_place(hold, Vector3(px, terrain_h(px, pz), pz))
		var fr := _mi(hold, _kit_mesh("atom", Color(1.0, 0.4, 0.75)), _mol_material(), Vector3(0.0, 1.7, 0.0))
		fr.scale = Vector3.ONE * 1.25
		fr.rotation = Vector3(0.4, p.x, 0.2)
		_mi(hold, _quad(4.5), _fx_mat("halo", Color(1.0, 0.45, 0.75, 0.55)), Vector3(0.0, 1.4, 0.0))
		(row["nodes"] as Array).append(hold)
		toys.append({"kind": "bump", "x": px, "z": pz, "n": hold, "t": 0})
		if first:
			_beacon(row, px, pz, Color(1.0, 0.4, 0.8))
			_toy_feat(row, px, pz, side, g)          # the front cupcake is the one to look at
			first = false


## GRAVITY SLINGSHOT: a small glowing orb hanging just over the snow, ringed by slow turning bands of light, with a faint pool of light on the ground showing how far its pull
## reaches. Pass close and it takes hold of the board and draws it in, speeding it up as it nears; as the board swings past it lets go and flings it on, faster.
func _make_spring(row: Dictionary, toys: Array, z: float, side: float) -> void:
	var x := trail_x(z) + side * 7.0
	var holder := Node3D.new()
	add_child(holder)
	_place(holder, Vector3(x, terrain_h(x, z), z))
	var core := SphereMesh.new()
	core.radius = 1.0
	core.height = 2.0
	core.radial_segments = 14
	core.rings = 7
	_mi(holder, core, _fx_mat("add", Color(0.75, 0.95, 1.0, 0.95)), Vector3(0.0, 3.0, 0.0))
	_mi(holder, _quad(7.0), _fx_mat("halo", Color(0.45, 0.85, 1.0, 0.5)), Vector3(0.0, 3.0, 0.0))
	var rings: Array = []
	var specs := [[2.0, 2.3, Color(0.55, 0.9, 1.0, 0.8), 0.5, 0.9], [3.1, 3.35, Color(1.0, 0.85, 0.45, 0.75), 1.2, -0.7], [4.3, 4.5, Color(0.6, 0.8, 1.0, 0.6), 2.1, 0.5]]
	for sp in specs:
		var tm := TorusMesh.new()
		tm.inner_radius = float(sp[0])
		tm.outer_radius = float(sp[1])
		tm.rings = 36
		tm.ring_segments = 6
		var rn := _mi(holder, tm, _fx_mat("add", sp[2]), Vector3(0.0, 3.0, 0.0))
		rn.rotation = Vector3(float(sp[3]), 0.0, float(sp[3]) * 0.6)
		rings.append([rn, float(sp[4])])
	var pool := _mi(holder, _quad(26.0), _fx_mat("ground", Color(0.45, 0.85, 1.0, 0.22)), Vector3(0.0, 0.15, 0.0))
	pool.rotation.x = -PI * 0.5 - atan(_grad(x, z).y)
	(row["nodes"] as Array).append(holder)
	_beacon(row, x, z, Color(0.5, 0.9, 1.0))
	toys.append({"kind": "sling", "x": x, "z": z, "n": holder, "rings": rings, "in": false, "used": false, "t": 0})
	_toy_feat(row, x, z, side, _toy_g)
	_toy_g += 1


## While the board is inside the pull of a slingshot: drawn toward it from the side and sped up the nearer it gets; past it, it is let go with a fling.
func _sling_tick(t: Dictionary, delta: float) -> void:
	var tz: float = t["z"]
	var dz := spos.z - tz
	if absf(dz) < 100.0:
		for rr in t["rings"]:
			(rr[0] as Node3D).rotate_y(float(rr[1]) * delta)
	if bool(t["used"]):
		return
	var dx := float(t["x"]) - spos.x
	var low := spos.y - terrain_h(spos.x, spos.z) < 6.0
	var inside := dz < 24.0 and dz > -4.0 and absf(dx) < 17.0 and low
	if inside:
		if not bool(t["in"]):
			t["in"] = true
			Game.sfx(&"stretch")
		var near := 1.0 - clampf(absf(dz) / 24.0, 0.0, 1.0)
		vel.x += clampf(dx * 2.4, -15.0, 15.0) * delta * (0.4 + near)
		vel.y -= (9.0 + 38.0 * near) * delta * _bm_spring
		_vx_active_t = maxf(_vx_active_t, 0.5)          # lets the speed run past its usual cap while it is being drawn in
		_fov_punch = maxf(_fov_punch, 2.0 + 5.0 * near)
		if randf() < 0.08:
			_burst(spos + Vector3(0.0, 0.5, 0.0), Color(0.6, 0.9, 1.0), 2, 3.0, 0.4, 0.5)
	elif bool(t["in"]) and dz <= -4.0:
		t["used"] = true
		vel.y -= 7.0 * _bm_spring
		_vx_active_t = 1.2
		_boost_t = maxf(_boost_t, 1.6)
		_fov_punch = 11.0
		_shake = maxf(_shake, 0.25)
		_gain(int(150.0 * groove))
		_flow_up(1)
		_burst(spos + Vector3(0.0, 0.6, 0.0), Color(0.75, 0.95, 1.0), 40, 12.0, 0.6, 0.9, Vector3(0, 0.3, 1.0), 40.0, -3.0)
		_ring(spos + Vector3(0.0, 0.8, 0.0), Color(0.6, 0.9, 1.0), 9.0, 0.5, true)
		_mix_add("sling")
		Game.sfx(&"snap")
		Game.sfx(&"whoosh")


## COLOUR LOLLIPOPS: four pairs, two colours, far apart. One colour zigzags left and right and the other does the opposite, so once you have taken a colour the next one is
## across the trail from the last: a slalom with a prize. Each pair is a choice like any other.
func _make_gates(row: Dictionary, toys: Array, z: float) -> void:
	var ca := _rng.randi() % 3
	var cb := (ca + 1 + _rng.randi() % 2) % 3
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	for r in 4:
		var gz := z - float(r) * 30.0
		var lanes: Array = []
		var g := _toy_g
		_toy_g += 1
		for pair in 2:
			var ci := ca if pair == 0 else cb
			var sgn := side if pair == 0 else -side
			if r % 2 == 1:
				sgn = -sgn
			var gx := trail_x(gz) + sgn * 5.5
			var col: Color = GATE_COLS[ci]
			var y0 := terrain_h(gx, gz)
			var hold := Node3D.new()
			add_child(hold)
			_place(hold, Vector3(gx, y0, gz))
			_mi(hold, _tm("stick"), _toy_mat("stick", Color(0.95, 0.95, 0.95), 0.8), Vector3(0.0, 1.15, 0.0))
			_mi(hold, _kit_mesh("hex", col), _mol_material(), Vector3(0.0, 2.9, 0.0))
			_mi(hold, _quad(5.5), _fx_mat("halo", Color(col.r, col.g, col.b, 0.7)), Vector3(0.0, 2.9, 0.0))
			(row["nodes"] as Array).append(hold)
			lanes.append({"x": gx, "c": ci, "n": hold, "y0": y0})
			_toy_feat(row, gx, gz, signf(sgn), g)
		toys.append({"kind": "gates", "z": gz, "r": r, "lanes": lanes, "done": false})
		if r == 0:
			_beacon(row, trail_x(gz), gz, Color(1.0, 0.9, 0.5))


var _links: int = 0
var _link_t: float = 0.0


## Everything that can be linked (a ramp, a ring, a pad, a spring, a cupcake, a lollipop, a rail) counts in one chain while the gaps between them stay under 7 seconds. The long
## chains are MEGA: a burst of points, XP toward the next unlock, and a chance of a surprise on top.
func _mix_add(kind: String) -> void:
	_links += 1
	_link_t = 7.0
	if _links == 6 or _links == 10 or _links == 15 or (_links > 15 and _links % 8 == 0):
		_gain(int(400.0 * float(_links) * groove))
		var opened := DhProgress.add(40.0 * float(_links))
		_cheer("MEGA CHAIN x%d" % _links, Color(1.0, 0.85, 0.3), 1.6 + 0.1 * float(mini(_links, 15)))
		if not opened.is_empty():
			_toast("Unlocked: " + ", ".join(opened), Color(0.7, 0.9, 1.0))
		if _links >= 10:
			_surprise()
	_mix[kind] = true
	_mix_t = 14.0
	if _mix.size() >= 4:
		_mix.clear()
		_surprise()


## Four kinds of thing in a row: a prize nobody can see coming. (The global random generator, not the course one: the course must not change with how you play.)
func _surprise() -> void:
	var gold := Color(1.0, 0.85, 0.3)
	match randi() % 4:
		0:
			_gain(int(1500.0 * groove))
			_cheer("JACKPOT!", gold, 1.8)
		1:
			_boost_t = maxf(_boost_t, 4.0)
			var sp0 := vel.length()
			vel += Vector2(sin(heading), -cos(heading)) * 7.0
			if vel.length() > maxf(SPEED_CAP, sp0):
				vel = vel.normalized() * maxf(SPEED_CAP, sp0)
			_cheer("TURBO SURPRISE!", Color(1.0, 0.5, 0.2), 1.6)
		2:
			_trip_add(0.4)
			_cheer("TRIP SURGE!", Color(1.0, 0.3, 0.9), 1.6)
		_:
			for i in 24:
				_glint_got(spos + Vector3(randf_range(-4.0, 4.0), randf_range(1.0, 4.0), randf_range(-14.0, -2.0)))
			_cheer("GLINT SHOWER!", gold, 1.5)
	Game.sfx(&"kaboom")
	_flow_up(2)


func _gate_result(hit: int, first: bool) -> void:
	if first:
		_gate_streak = 0
		_gate_col = -1
	if hit < 0:
		_gate_streak = 0
		_gate_col = -1
		return
	if hit == _gate_col:
		_gate_streak += 1
	else:
		_gate_col = hit
		_gate_streak = 1
	var col: Color = GATE_COLS[hit]
	_gain(int(60.0 * groove * float(_gate_streak)))
	_burst(spos + Vector3(0.0, 1.5, 0.0), col, 14, 7.0, 0.5, 0.8)
	_mix_add("gate")
	Game.sfx(&"blip")
	if _gate_streak == 2:
		_toast("MATCH", col)
	elif _gate_streak == 3:
		_flow_up(1)
		_boost_t = maxf(_boost_t, 1.5)
		_cheer("COLOUR CHAIN x3", col, 1.1)
	elif _gate_streak >= 4:
		_gain(int(600.0 * groove))
		_cheer("COLOUR CHAIN x%d !!" % _gate_streak, col, 1.7)
		_surprise()


func _toys_tick(delta: float) -> void:
	for kk in _rows:
		for pp in (_rows[kk] as Dictionary)["pads"]:
			var pg: Variant = pp.get("gem", null)
			if pg != null and is_instance_valid(pg) and absf(float(pp["z"]) - spos.z) < 150.0:
				(pg as Node3D).rotate_y(1.8 * delta)
				(pg as Node3D).position.y = float(pp["gy"]) + 0.22 * sin(_age * 2.6 + float(pp["ph"]))          # turning and bobbing a little
	_link_t -= delta
	if _link_t <= 0.0:
		_links = 0
	_mix_t -= delta
	if _mix_t <= 0.0 and not _mix.is_empty():
		_mix.clear()
	if _finished or not trail:
		return
	var now := Time.get_ticks_msec()
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r.has("toys"):
			continue
		for t in r["toys"]:
			var tz: float = t["z"]
			var kind: String = t["kind"]
			if kind == "gates":
				if absf(tz - spos.z) < 90.0:
					for ln in t["lanes"]:
						var gn := ln["n"] as Node3D
						if gn.visible:
							gn.rotation.z = 0.16 * sin(_vx_spin * 2.4 + float(ln["x"]))          # the lollipop sways on its stick
				if t["done"] or spos.z > tz:
					continue
				t["done"] = true
				if tz - spos.z > 8.0:
					continue
				var hit := -1
				for ln in t["lanes"]:
					if absf(float(ln["x"]) - spos.x) < 3.2:
						hit = int(ln["c"])
						(ln["n"] as Node3D).visible = false
				_gate_result(hit, int(t["r"]) == 0)
				continue
			if kind == "sling":
				_sling_tick(t, delta)
				continue
			if absf(tz - spos.z) > 40.0:
				continue
			var n := t["n"] as Node3D
			if kind == "pill":
				if n.visible:
					(t["spin"] as Node3D).rotate_y(2.4 * delta)
					n.position.y = float(t["y"]) + 0.25 * sin(_age * 2.8 + float(t["x"]))
					var pdx := spos.x - float(t["x"])
					var pdz := spos.z - tz
					if pdx * pdx + pdz * pdz < 9.0 and absf(spos.y - n.position.y) < 4.5:
						_pill_eat(t)
				continue
			if kind == "bump":
				n.scale = n.scale.lerp(Vector3.ONE, 1.0 - exp(-8.0 * delta))
			if absf(tz - spos.z) > 3.5 or now < int(t["t"]):
				continue
			var dx := spos.x - float(t["x"])
			var dz := spos.z - tz
			if dx * dx + dz * dz > (5.5 if kind == "bump" else 6.5) or spos.y - terrain_h(spos.x, spos.z) > 2.6:
				continue
			if kind == "bump":
				t["t"] = now + 400
				var d := Vector2(dx, dz).normalized() if dx * dx + dz * dz > 0.01 else Vector2(1.0, 0.0)
				vel.x += d.x * 15.0 * _bm_bump
				vel.y -= 2.5
				n.scale = Vector3(1.6, 1.6, 1.6)
				_shake = maxf(_shake, 0.2)
				_gain(int(80.0 * groove))
				_flow_up(1)
				_burst(Vector3(float(t["x"]), n.position.y + 1.0, tz), Color(1.0, 0.4, 0.8), 18, 8.0, 0.5, 0.9)
				_mix_add("bump")
				Game.sfx(&"boing2")


# --------------------------------------------------------------------------
# View: first person (default, like a snowboarding game: only the tip of the board shows, which is also the best view for eye tracking, because the
# gates are where you look) or third person (shows the rider, so tricks and pickup hops can be seen). V or the VIEW label toggles it.
# --------------------------------------------------------------------------
var view_fp: bool = true
var _tip_pivot: Node3D
var _tip_yaw: float = 0.0
var _tip_roll: float = 0.0
var _tip_x: float = 0.0
var _cam_look: Vector2 = Vector2(0.0, -1.0)
var _hop_cam: float = 0.0
var _view_msec: int = 0
const VIEW_CFG := "user://carve_view.cfg"


func _load_view_pref() -> void:
	var cf := ConfigFile.new()
	if cf.load(VIEW_CFG) == OK:
		view_fp = bool(cf.get_value("carve", "fp", true))
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('view') || ''"))
		if q == "3p" or q == "3":
			view_fp = false
		elif q == "1p" or q == "1":
			view_fp = true


func _toggle_view() -> void:
	view_fp = not view_fp
	var cf := ConfigFile.new()
	cf.set_value("carve", "fp", view_fp)
	cf.save(VIEW_CFG)
	_place_camera(0.016, true)
	_toast("FIRST PERSON" if view_fp else "THIRD PERSON", Color(0.9, 0.95, 1.0))


var _menu_arm_t: float = 0.0


## A MENU button under the view toggle. Two taps (the first says SURE?), so a stray touch cannot throw a run away.
func _menu_rect() -> Rect2:
	return Rect2(-9000.0, -9000.0, 1.0, 1.0)          # no on-screen buttons in the game: the screen is the game (Esc or P pauses)
	var r := _view_rect()
	return Rect2(r.position.x - 14.0 * _hud_scale(), r.position.y + r.size.y + 10.0 * _hud_scale(), r.size.x + 14.0 * _hud_scale(), r.size.y)


func _view_rect() -> Rect2:
	return Rect2(-9000.0, -9000.0, 1.0, 1.0)          # no on-screen buttons in the game: the screen is the game (Esc or P pauses)
	var s := get_viewport().get_visible_rect().size
	var k := _hud_scale()
	return Rect2(s.x - 24.0 * k - 56.0 * k, 24.0 * k + 30.0 * k + 46.0 * k, 56.0 * k, 30.0 * k)


## A phone held upright is a tall, narrow window: keep the HORIZONTAL field of view (so the gates are still in sight) instead of the vertical one.
func _fit_fov() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x * 1.05:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = clampf(62.0 + (vel.length() - 18.0) * 0.3, 60.0, 74.0) + _fov_punch * 0.6          # held upright the picture is tall: a wide sideways view makes it far taller still (122 deg from top to bottom at 78) and the phone draws all of it
	elif Game.touch_mode and vs.x > vs.y * 1.9:
		cam.keep_aspect = Camera3D.KEEP_WIDTH                    # a long thin phone screen: a 100 deg view from top to bottom is 140 deg across. Fix the width instead and the sky and snow nobody looks at are not drawn
		cam.fov = clampf(98.0 + (vel.length() - 18.0) * 0.4, 96.0, 110.0) + _fov_punch * 0.6
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT


## The tip of the board sits low in the picture, at a fixed angle below the middle. On a long thin phone screen the view is fixed across the width, so the picture is much
## shorter than it is wide and that angle fell off the bottom of the screen: the board is raised to stay inside whatever the picture shows.
func _fit_tip() -> void:
	if _tip_pivot == null or cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var half_v := deg_to_rad(cam.fov) * 0.5
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		half_v = atan(tan(half_v) * vs.y / maxf(vs.x, 1.0))
	_tip_pivot.position.y = clampf(-tan(half_v * 0.82), -1.15, -0.3)


func _place_camera(delta: float, snap: bool = false) -> void:
	if not view_fp:
		cam_back = 9.5 if trail else 8.0                          # on the trail the camera sits higher and looks further down the slope: the next two things are in view sooner
		cam_h = 6.2 if trail else 4.6
		cam_ahead = 30.0 if trail else 16.0
		cam_road = 0.8 if trail else 0.0
		if trail:
			cam_hint = Vector2(trail_x(spos.z - 50.0) - spos.x, -50.0).normalized()
		if trail:
			var vxk := maxf(_vx_pull * 0.6, _vx_blast)
			_fov_punch = minf(_fov_punch, 3.0 + 9.0 * vxk)       # calmer: no big zoom flashes, except the swirl pulling you in and the blast off the lip
			_shake = minf(_shake, 0.5 + 1.0 * _vx_blast)
		super._place_camera(delta, snap)
		_fit_fov()
		_fit_tip()
		_cine_apply(delta)
		return
	var sp := vel.length()
	var vdir := vel / sp if sp > 1.0 else Vector2(0.0, -1.0)
	var hd := Vector2(sin(heading), -cos(heading))
	var want := (vdir * 0.5 + hd * 0.5).normalized()
	_cam_look = want if snap else _cam_look.lerp(want, 1.0 - exp(-7.0 * delta)).normalized()
	_cdir = _cam_look
	var eye := Vector3(spos.x, spos.y + 1.72 + _hop_cam, spos.z) - Vector3(_cam_look.x, 0.0, _cam_look.y) * 0.25
	eye.y = maxf(eye.y, terrain_h(eye.x, eye.z) + 1.2)
	cam.global_position = eye
	var ahead := spos + Vector3(_cam_look.x, 0.0, _cam_look.y) * 18.0
	ahead.y = terrain_h(ahead.x, ahead.z) + 1.4 + _hop_cam * 0.5
	if (ahead - eye).length() > 0.5:
		cam.look_at(ahead, Vector3.UP)
		if _back_dbg:
			cam.rotate_object_local(Vector3.UP, PI)          # ?back: look behind (to check the ground back there)
	cam.basis = cam.basis * Basis(Vector3(0, 0, 1), -steer * 0.10 - _trk_cam_roll) * Basis(Vector3(1, 0, 0), _trk_cam_pitch)
	if pm_view > 0.0 and GazeProvider.pm.active:
		var pmt := GazeProvider.pm
		cam.basis = cam.basis * Basis(Vector3(0, 1, 0), deg_to_rad(clampf(-pmt.tilt_x * pm_view, -5.0, 5.0))) * Basis(Vector3(1, 0, 0), deg_to_rad(clampf(-(pmt.tilt_y - 70.0) * pm_view * 0.5, -4.0, 4.0)))
	_shake = maxf(_shake - 1.6 * delta, 0.0)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	_fov_punch = maxf(_fov_punch - 24.0 * delta, 0.0)
	cam.fov = clampf(80.0 + (sp - 18.0) * 0.6, 78.0, 108.0) + _fov_punch
	_fit_fov()
	_fit_tip()
	_cine_apply(delta)


## The view model: just the tip of the board at the bottom of the screen. It swings with the board's heading (so you can see where it points relative to
## where you are going), leans into a turn, bobs on the snow and carries the tricks.
func _build_tip() -> void:
	_tip_pivot = Node3D.new()
	cam.add_child(_tip_pivot)
	_tip_pivot.position = Vector3(0.0, -1.15, 0.0)
	var blue := _flat_mat(Color(0.15, 0.3, 0.75))
	# a rounded board: a flat body with a half-round nose (a flattened cylinder), the nose turned up a little
	var body := BoxMesh.new()
	body.size = Vector3(0.8, 0.09, 0.5)
	var b := _mi(_tip_pivot, body, blue, Vector3(0.0, 0.0, -0.9))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.4
	cap.bottom_radius = 0.4
	cap.height = 0.09
	cap.radial_segments = 28
	cap.rings = 1
	var c := _mi(_tip_pivot, cap, blue, Vector3(0.0, 0.0, -1.15))
	c.rotation.x = 0.12
	var rim := TorusMesh.new()
	rim.inner_radius = 0.36
	rim.outer_radius = 0.42
	rim.rings = 28
	rim.ring_segments = 6
	var r := _mi(_tip_pivot, rim, _flat_mat(Color(0.97, 0.97, 1.0)), Vector3(0.0, 0.05, -1.15))
	r.rotation.x = 0.12
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.07, 0.1, 0.55)
	_mi(_tip_pivot, stripe, _flat_mat(Color(1.0, 0.55, 0.15)), Vector3(0.0, 0.03, -1.0))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------------------
# Jumps and tricks. A kicker (a ramp of snow) sits beside the safe line now and then, usually with a pickup floating above its lip: look at it, ride it,
# and in the air:
#   spin   look hard left or right (or A / D): each half turn counts (180, 360, 540 ...)
#   grab   chin down (or S): hold it for bonus points
#   flip   snap your chin up (or W): a backflip
# You always land: the landing straightens the board to the nearest half turn, so a trick never costs you a crash. Doing more than one at once multiplies the points.
# --------------------------------------------------------------------------
var perf_pin: int = -1                 # -1 automatic; 0..3 pins the quality tier (the menu's SPEED FIRST pins 2)
var _nohud: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("nohud")
const HUD_MIN := true                    # on screen in play: points, speed, frame rates. Nothing else standing on the picture.
var show_perf: bool = true  # was: OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("perf")               # ?perf (or F3) shows the frame-rate line
var _runlog := RunLog.new()
var hazard_skin: String = "snow"                          # what rolls at you: a snowball, or (desert) a mummy
var mist_color: Color = Color(0.93, 0.96, 1.0, 0.97)       # what hides the stretch that is not built yet: the theme sets it
var _crumbs: Array = []
var _crumb_a: float = 0.0
var sky_rise: float = 2.2
var sky_drag: float = 0.28                                   # how much steeper than a plain kicker the air-stretch ramps are
const KICK_LEN := 26.0
const KICK_W := 18.0
var jump_len: float = 42.0              # the ramps on the forest trail: a curved kicker, flat at its foot and steepest at the lip, with a swirl that pulls you in and blasts you off
const JUMP_W := 14.0
var jump_rise: float = 24.0
var jump_curl: float = 0.45             # how much of the ramp is the steep curl at the end
var jump_launch: float = 21.0           # m/s straight up at the lip, however steep the wall: the flight is long and roomy, never a rocket
var jump_pow: float = 2.0               # the profile: height = rise * (distance up the ramp)^pow
var jump_blast: float = 2.0             # m/s of extra lift the swirl gives at the lip
var kickers_built: int = 0
var kick_log: Array = []
var epics_built: int = 0
var _force_far_next: bool = false
var _last_air: bool = false
var air_segments: int = 0
var _air_zones: Array = []
var _air_epic: bool = false
var tricks_landed: int = 0
var trick_score: int = 0
var best_trick: String = ""
var trick_look_override: float = 0.0           # tests: stand-in for the look
var trick_grab_override: bool = false
var trick_flip_override: bool = false
var _in_air: bool = false
var _trk_spin: float = 0.0
var _trk_spin_v: float = 0.0
var _trk_flip: float = 0.0
var _trk_flip_goal: float = 0.0
var _trk_grab_t: float = 0.0
var _trk_vis_spin: float = 0.0
var _trk_vis_flip: float = 0.0
var _trk_cam_roll: float = 0.0
var _trk_cam_pitch: float = 0.0
var _trk_text: String = ""
var _trk_text_t: float = 0.0
var _trk_hint: bool = false
var _flip_key_prev: bool = false
var _air_peak: float = 0.0


## A hard landing costs speed but never wipes you out: the hill is steep and a landing is rarely your fault (a bump, a ramp you chose).
func _land(impact: float, gh: float, gvy: float) -> void:
	if impact > 4.0:
		Game.sfx(&"land")          # every real landing is felt: a soft low thump
	var t_air := air_t
	var lo := _land_off
	_psy_pulse(3, Color(0.5, 1.0, 0.9))
	if impact > 2.0:
		Game.sfx(&"boing2")
	if impact < 6.0 and t_air > 0.8:
		_cue(1)
	var on_spot: bool = trail and t_air > 0.8 and absf(lo) > 1.5 and absf(spos.x - (trail_x(spos.z) + lo)) < 3.5 and impact < 7.0
	_land_off = 0.0
	if _air_chain >= 3:
		_flow_up()
	_air_chain = 0
	if on_spot:
		_boost_t = maxf(_boost_t, 1.6)
		_flow_up()
		score += int(150.0 * groove)
		_cheer("LANDED WHERE YOU LOOKED!", Color(0.5, 1.0, 0.8), 1.2)
		_burst(Vector3(spos.x, gh + 0.3, spos.z), Color(0.5, 1.0, 0.8), 40, 9.0, 0.6, 0.9, Vector3(0, 1, 0), 60.0, -6.0)
	GazeProvider.pm.buzz([clampi(int(impact * 4.0), 15, 70)])
	super._land(minf(impact, 15.0), gh, gvy)
	if bouncy and impact > 2.0 and not _finished:
		vy = clampf(impact * 0.75, 6.0, 15.0)          # boing
		grounded = false
		spos.y = gh + 0.15
		_burst(Vector3(spos.x, gh + 0.3, spos.z), Color(1.0, 0.9, 0.4), 16, 6.0, 0.5, 0.7, Vector3(0, 1, 0), 80.0, -4.0)


func _place_kicker(row: Dictionary, obs: PackedFloat32Array, prev_rz: float, rz: float, z0: float, has_row: bool, j: int, air: bool = false) -> void:
	var span := (prev_rz - rz) if has_row else ROW_GAP
	if has_row and span < 78.0:
		return
	if not air:
		return                                              # ramps are big and sit in air segments only: no small lumps to hit by accident
	if has_row and _rng.randf() > 0.7:
		return
	var d := _course_diff(z0)
	var first := has_row and prev_rz > -1.0
	var epic := air or (has_row and first and _rng.randf() < 0.6)
	var prev_obs := PackedFloat32Array()
	if _rows.has(j - 1):
		prev_obs = (_rows[j - 1] as Dictionary)["obs"]
	for attempt in 8:
		if attempt == 4:
			epic = false                                    # no room for an epic one here: a plain kicker will do
		var kz: float
		if air:
			kz = z0 - 6.0
		elif first:
			kz = rz + (_rng.randf_range(125.0, 150.0) if epic else _rng.randf_range(90.0, 120.0))          # the first barrier: the ramp comes well after the start
		elif has_row:
			kz = prev_rz - span * _rng.randf_range(0.10, 0.19)
		else:
			kz = z0 - _rng.randf_range(18.0, 34.0)
		var lipz := kz - KICK_LEN
		if has_row and lipz < rz + (88.0 if epic else 50.0 + 12.0 * d):
			continue
		var cxl: float = path_x(row, kz) if has_row else (_good_x if air else 0.0)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var koff := _rng.randf_range(4.0, 8.0) if air else _rng.randf_range(14.0, 19.0)
		var kx := cxl + side * koff
		if absf(kx) > 40.0:
			kx = cxl - side * koff
		if absf(kx) > 40.0:
			continue
		var ok := true
		for zz in [kz, lipz, lipz - 12.0, lipz - 26.0, lipz - 40.0 if epic else lipz - 26.0]:
			for xx in [kx - 8.0, kx, kx + 8.0]:
				if not _clear_of_obs(obs, xx, zz, 4.0) or not _clear_of_obs(prev_obs, xx, zz, 4.0):
					ok = false
		if not ok:
			continue
		var rise := _rng.randf_range(0.95, 1.05) * 3.3 * (36.0 / (34.0 + 17.0 * d))          # a ramp rising this fast over its length throws you about 1.3 s into the air and 50-70 m down the slope at any speed (tests/jump_probe); a charged pop adds up to 3 m/s
		if air:
			rise *= sky_rise                                   # air stretches throw you at the sky
		_kickers.append({"x": kx, "z": kz, "len": KICK_LEN, "w": KICK_W, "rise": rise, "epic": epic})
		_make_vortex(row, _kickers[_kickers.size() - 1], kx, kz, epic)
		kick_log.append("%.0f/%.0f%s" % [kz, kx, "E" if epic else ""])
		row["kick"] = {"x": kx, "z": kz, "lip": lipz, "epic": epic}
		kickers_built += 1
		if epic:
			epics_built += 1
		if air:
			air_segments += 1
			_force_far_next = true                          # the barrier after an air segment starts well below the landing
			_air_zones.append({"z0": kz + 4.0, "z1": lipz - 105.0, "x": kx})
		var lc := Color(1.0, 0.6, 0.15) if not epic else Color(1.0, 0.3, 0.6)
		var lipm := BoxMesh.new()
		lipm.size = Vector3(KICK_W - 2.0, 0.12, 0.5)
		var lp := _mi(self, lipm, _fx_mat("solid", lc, 1.6), Vector3(kx, terrain_h(kx, lipz + 0.8) + 0.12, lipz + 0.8))
		(row["nodes"] as Array).append(lp)
		for sx in [-1.0, 1.0]:
			var pole := CylinderMesh.new()
			pole.top_radius = 0.07
			pole.bottom_radius = 0.09
			pole.height = 3.2 if not epic else 4.6
			pole.radial_segments = 5
			var px: float = kx + float(sx) * (KICK_W * 0.5 - 0.6)
			var pn := _mi(self, pole, _fx_mat("solid", lc, 1.4), Vector3(px, terrain_h(px, lipz + 1.0) + pole.height * 0.5, lipz + 1.0))
			(row["nodes"] as Array).append(pn)
			var flag := _mi(pn, _quad(1.4 if not epic else 2.2), _fx_mat("halo", Color(lc.r, lc.g, lc.b, 0.9)), Vector3(0.0, pole.height * 0.42, 0.0))
			flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# no boost pads on a ramp any more: the vortex does that job, and boosts live in the pickups
		if epic or _rng.randf() < 0.8:
			var trail: Array = [Vector2(kx, kz + 18.0), Vector2(kx, kz + 10.0), Vector2(kx, kz + 2.0)]
			_spawn_buff(row, _pick_buff(true), kx, lipz - 9.0, trail, "air", 2.4)
			if epic:
				_spawn_buff(row, _pick_buff(true), kx, lipz - 26.0, [], "air", 3.4)
		return


# --------------------------------------------------------------------------
# Up in the sky: face challenges and the cinematic cutaway
# --------------------------------------------------------------------------
## Every face the game can ask for: the prompt, what the move is called, and what it pays.
const FACES := {
	"tongue": {"say": "STICK OUT YOUR TONGUE!", "name": "THE BLEH", "pts": 260},
	"smile": {"say": "MANIACAL SMILE!!", "name": "THE JOKER", "pts": 260},
	"shock": {"say": "LOOK SHOCKED!", "name": "THE HOME ALONE", "pts": 280},
	"pain": {"say": "LOOK IN PAIN!", "name": "THE OUCHIE", "pts": 280},
	"wide": {"say": "EYES WIDE OPEN!", "name": "THE OWL", "pts": 240},
	"cross": {"say": "CROSS YOUR EYES!", "name": "THE CROSS-EYED CRUSADER", "pts": 280},
	"squint": {"say": "SQUINT LIKE A PIRATE!", "name": "THE PIRATE", "pts": 220},
	"puff": {"say": "PUFF YOUR CHEEKS!", "name": "THE HAMSTER", "pts": 260},
	"kiss": {"say": "BLOW A KISS!", "name": "THE SMOOCH", "pts": 240},
	"sneer": {"say": "SNEER AT THE MOUNTAIN!", "name": "THE VILLAIN", "pts": 240},
	"crazy": {"say": "CRAZY EYES!!", "name": "THE LOOSE MARBLES", "pts": 280},
	"shake": {"say": "SHAKE YOUR HEAD!", "name": "THE WET DOG", "pts": 240},
}
const FACE_OPENERS := ["MAKE A FACE!", "QUICK, A FACE!", "THE CROWD WANTS A FACE!", "SURPRISE FACE TIME!", "FACE! NOW!", "THE CAMERAS ARE ON YOU!"]
const FACE_WINDOW := 2.6

var face_enabled: bool = true
var face_kind: String = ""             # the face being asked for ("" = none)
var face_t: float = 0.0                # seconds left to pull it
var face_hold: float = 0.0
var face_open: String = ""
var face_done: int = 0
var face_seen: Dictionary = {}
var face_override: String = ""         # tests: pretend the player is pulling this face
var _face_next: float = 0.7            # air time at which the next prompt appears
var _face_last: String = ""
var _cine_k: float = 0.0
var _cine_on: bool = false
var _cine_t: float = 0.0
var _cine_side: float = 1.0
var cine_enabled: bool = true
var cines: int = 0


## The menu's choices, applied just before the run starts (and the course rebuilt from them).
func apply_menu(c: Dictionary, level: MainLevel) -> void:
	_lvl = level
	var zones: Dictionary = (c.get("zones", {}) as Dictionary).duplicate()
	var km := float(c.get("length_km", 4.2))
	params["seed"] = int(c.get("seed", 424242))
	_mol_rows = bool(c.get("journey", true)) and String(c.get("theme", "alpine")) == "alpine"          # All dressed: molecules come at their own steady pace (see _gen_toys)
	_mol_next_z = -150.0
	_pacer = null
	apply_params({"length": 0.0 if (bool(c.get("endless", false)) or _mol_rows) else km * 1000.0, "diff": float(c.get("diff", 1.0)), "zones": zones})
	face_enabled = bool(c.get("faces", true))
	mode = String(c.get("mode", mode))
	cine_enabled = bool(c.get("cine", true))
	GazeProvider.pm_on = bool(c.get("phone", true))
	GazeProvider.pm.haptics_on = bool(c.get("haptics", true))
	vehicle_forced = bool(c.get("vehicle", false))
	_no_pause_until = Time.get_ticks_msec() + 12000
	_paused = false
	perf_pin = 2 if bool(c.get("speed_first", false)) else -1
	assist_level = clampf(float(c.get("assist", 0.7)), 0.0, 1.0)
	if bool(c.get("gps", false)):
		RunLog.start_gps()
	_trip_on = Themes.post_mode(String(c.get("theme", "alpine"))) == 1 and not bool(c.get("journey", true))
	_audio_setup(c)
	trip = 0.0
	_trip_tier = 0
	if OS.has_feature("web"):
		var tq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('trip') || ''"))
		_trip_force = float(tq) if tq.is_valid_float() else -1.0
	_psy_start(false, 0.0)                                         # the psychedelic overlay is parked until it is better
	G = 9.8 * clampf(float(c.get("m_grav", 1.0)), 0.2, 3.0)
	hazard_share = clampf(0.6 * float(c.get("m_rocks", 1.0)), 0.0, 1.0)
	jump_chance = clampf(0.72 * float(c.get("m_ramps", 1.0)), 0.0, 1.0)
	pad_chance = clampf(0.12 * float(c.get("m_pads", 1.0)), 0.0, 1.0)
	grip_lag = 2.6 if bool(c.get("m_ice", false)) else 1.0
	big_head = bool(c.get("m_head", false))
	bouncy = bool(c.get("m_bounce", false))
	trike = bool(c.get("m_trike", false))
	glint_k = clampf(float(c.get("m_glints", 1.0)), 0.5, 4.0)
	face_k = clampf(float(c.get("m_faces", 1.0)), 0.5, 3.0)
	hat_id = int(c.get("m_hat", 0))
	_base_haz = hazard_share
	_base_jump = jump_chance
	_base_pad = pad_chance
	_base_glint = glint_k
	_base_grip = grip_lag
	_cfg_intensity = float(c.get("intensity", 0.8))
	_cfg_trip = int(c.get("trip", 1))
	_cfg_dyn = bool(c.get("dynlight", true))
	_cfg_snow = bool(c.get("snow", true))
	_cfg_fluffy = bool(c.get("fluffy", false))
	_journey = DhJourney.new() if bool(c.get("journey", true)) and String(c.get("theme", "alpine")) == "alpine" else null          # a world picked by hand is the world, all of it: the journey starts from alpine
	_pacer = null
	if _journey != null:
		_pacer = DhPacer.new()
		_pacer.session_s = clampf(float(c.get("session", 10)), 5.0, 600.0) * 60.0
	_pill_seen = false
	_pill_k = 0.0
	_pill_t = 0.0
	_pill_n = 0
	_dose = 0.0
	_body = 0.0
	_flick = 0.0
	_mdose.fill(0.0)
	_mbody.fill(0.0)
	_mol_seen = false
	_dmt_on = false
	if OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("dose"):
		_mdose.fill(3.0)          # ?dose: begin with half of every molecule taken (to look at the trip and the stems from the start)
		_mbody.fill(3.0)
		_mol_seen = true
	_drift_t = 110.0
	_dress_rider()
	if _rider != null:
		for hi in [1, 2]:
			var hn := _rider.get_child(hi) as Node3D
			if hn != null:
				hn.scale = Vector3.ONE * (3.0 if big_head else 1.0)
				hn.position.y = (1.5 if hi == 1 else 1.62) + (0.6 if big_head else 0.0)
	ThemeFX.apply_to_level(level, self, "alpine" if _journey != null else String(c.get("theme", "alpine")), float(c.get("intensity", 0.8)), bool(c.get("dynlight", true)), bool(c.get("snow", true)), bool(c.get("fluffy", false)))
	_run_no = 0
	_restart()


# --------------------------------------------------------------------------
# PSYCHEDELIC MODE: one full-screen shader over the world, nothing else. Rings and spokes fall away from where you are looking, in colours that cycle;
# the faster you go (and the harder a boost or a flash hits) the harder it throbs. A clear patch is kept round the board and the trail so play stays readable.
# It samples no screen texture and does a handful of sines per pixel, so it costs a phone almost nothing.
# --------------------------------------------------------------------------
const PSY_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;
uniform float rush = 0.0;
uniform float amount = 0.4;
uniform float grind = 0.0;     // on a rail: the rings tighten into fine fast lines
uniform float air = 0.0;       // in the air: slow, huge, floaty waves and a drifting colour
uniform float speed = 0.0;     // how fast the ground streams
uniform vec2 gaze = vec2(0.0, 0.0);
uniform vec2 aspect = vec2(1.0, 1.0);
uniform vec4 pa = vec4(9.0);   // age of the four latest events, in seconds (9 = none)
uniform vec4 pk = vec4(0.0);   // their kind: 1 glint, 2 blast, 3 landing, 4 crash, 5 cheer
uniform vec3 c0 = vec3(1.0);
uniform vec3 c1 = vec3(1.0);

vec3 pal(float x) {
	return 0.5 + 0.5 * cos(6.2831 * (vec3(x) + vec3(0.0, 0.33, 0.67)));
}

// a ripple that leaves the board: its width, speed and look depend on what happened
vec4 ev(float age, float kind, vec2 uv, vec3 col) {
	if (age > 1.6 || kind < 0.5) { return vec4(0.0); }
	float sp = kind > 1.5 ? 1.1 : 0.7;               // a blast or a landing spreads wide and fast
	float w = kind > 3.5 ? 0.09 : (kind > 1.5 ? 0.06 : 0.025);
	float rad = age * sp;
	float d = length((uv - vec2(0.5, 0.68)) * aspect);
	float band = exp(-pow((d - rad) / w, 2.0));
	float fade = 1.0 - age / 1.6;
	float tex = 1.0;
	if (kind > 3.5) { tex = 0.55 + 0.45 * sin(d * 90.0); }                       // a crash: a coarse, buzzing band
	else if (kind > 2.5) { tex = 0.7 + 0.3 * sin(d * 40.0 - age * 30.0); }       // a landing: a thump with ridges
	else if (kind > 1.5) { tex = 0.6 + 0.4 * sin(atan(uv.y - 0.68, uv.x - 0.5) * 12.0); }   // a blast: a starburst
	return vec4(col, band * fade * tex);
}

void fragment() {
	vec2 uv = (UV - 0.5 - gaze * 0.2) * aspect;
	float r = length(uv) + 1.0e-4;
	float a = atan(uv.y, uv.x);
	float depth = 1.0 / (r + 0.15);
	float tt = t * (1.0 + 0.6 * rush);
	float wob = mix(0.6 * sin(a * 3.0 + t * 0.4), 1.6 * sin(a * 2.0 + t * 0.7), air);
	float rings = sin(depth * mix(5.0, 14.0, grind) - tt * mix(1.5, 4.5, grind) * (1.0 + 2.0 * rush) + wob);
	float spokes = sin(a * mix(6.0, 26.0, grind) + depth * 1.5 - t * 0.7);
	float f = rings * mix(0.65, 0.5, grind) + spokes * mix(0.35, 0.5, grind);
	f = mix(f, sin(depth * 2.0 + t * 0.8 + 2.0 * sin(a * 2.0 - t * 0.3)), air * 0.6);
	vec3 col = pal(f * 0.25 + depth * 0.08 + t * (0.05 + 0.1 * air));
	col = mix(col, vec3(1.0), smoothstep(0.85, 1.0, f) * 0.5);
	// the pattern lives at the edges and in the sky and fades out over the lower middle, so the board and the trail stay readable
	vec2 d = (UV - vec2(0.5, 0.66)) * vec2(1.0, 1.35);
	float keep = smoothstep(0.28, 0.7, length(d));
	float al = amount * (0.12 + 0.88 * keep) * (0.7 + 0.3 * rush);

	// THE GROUND: a grid laid on the snow in perspective that streams at you, with a second one running the other way, so the eyes cannot settle:
	// stripes across the slope, lines along it that bend with the colour, and a checker flicker that quickens with speed
	float hz = 0.40;
	float gy = UV.y - hz;
	vec4 ground = vec4(0.0);
	if (gy > 0.01) {
		float gd = 1.0 / gy;                                       // distance along the ground
		float gx = (UV.x - 0.5) * gd;                              // across it
		float flow = t * (4.0 + 22.0 * speed);
		float s1 = sin((gd - flow) * 1.6);
		float s2 = sin((gd + flow * 0.5) * 3.1 + gx * 1.2);
		float l1 = sin(gx * 2.2);
		float chk = sign(s1) * sign(l1);
		float lines = smoothstep(0.55, 1.0, abs(s1)) * 0.6 + smoothstep(0.8, 1.0, abs(l1)) * 0.6;
		vec3 gc = pal(gd * 0.05 - flow * 0.02 + 0.3 * s2 + float(chk > 0.0) * 0.2);
		float fade_far = smoothstep(0.0, 0.18, gy);                // melts into the horizon
		float gal = (0.12 + 0.3 * lines + 0.12 * abs(chk)) * fade_far * (0.4 + 0.6 * speed) * amount * 2.0;
		// the board's own patch stays calm
		gal *= 0.35 + 0.65 * smoothstep(0.1, 0.4, length((UV - vec2(0.5, 0.78)) * vec2(1.4, 1.0)));
		ground = vec4(gc, clamp(gal, 0.0, 0.6));
	}

	vec3 outc = mix(col, ground.rgb, ground.a / max(al + ground.a, 0.001));
	float outa = clamp(al + ground.a * (1.0 - al), 0.0, 0.85);
	vec4 e0 = ev(pa.x, pk.x, UV, c0);
	vec4 e1 = ev(pa.y, pk.y, UV, c1);
	float ea = clamp(e0.a + e1.a, 0.0, 1.0);
	vec3 ec = (e0.rgb * e0.a + e1.rgb * e1.a) / max(e0.a + e1.a, 0.001);
	COLOR = vec4(mix(outc, ec, ea * 0.9), clamp(outa + ea * 0.75, 0.0, 0.92));
}
"""
var psy_on: bool = false
var _psy_rect: ColorRect = null
var _psy_mat: ShaderMaterial = null
var _psy_rush: float = 0.0
var _psy_grind: float = 0.0
var _psy_air: float = 0.0
var _psy_speed: float = 0.0
var _psy_ev: Array = [[9.0, 0.0, Color(1, 1, 1)], [9.0, 0.0, Color(1, 1, 1)]]          # the two latest events: [age, kind, colour]


## Something happened: send a ripple out from the board. kind: 1 glint, 2 blast, 3 landing, 4 crash, 5 cheer.
func _psy_pulse(kind: int, col: Color) -> void:
	if not psy_on:
		return
	_psy_ev[1] = _psy_ev[0]
	_psy_ev[0] = [0.0, float(kind), col]


func _psy_start(on: bool, amount: float) -> void:
	psy_on = on
	if _psy_rect != null:
		_psy_rect.visible = on
	if not on:
		return
	if _psy_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = -1                                                 # over the 3D world, under everything drawn on screen
		add_child(layer)
		_psy_rect = ColorRect.new()
		_psy_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_psy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = PSY_SHADER
		_psy_mat = ShaderMaterial.new()
		_psy_mat.shader = sh
		_psy_rect.material = _psy_mat
		layer.add_child(_psy_rect)
	_psy_mat.set_shader_parameter("amount", clampf(0.12 + 0.3 * amount, 0.12, 0.5))


func _psy_tick(delta: float) -> void:
	if not psy_on or _psy_mat == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var sp := clampf(-vel.y / 45.0, 0.0, 1.5)
	var target := sp * 0.6 + (0.6 if _boost_t > 0.0 else 0.0) + clampf(_flash * 2.0, 0.0, 0.5)
	_psy_rush = lerpf(_psy_rush, clampf(target, 0.0, 1.0), clampf(delta * 3.0, 0.0, 1.0))
	_psy_grind = lerpf(_psy_grind, 1.0 if not _rail.is_empty() else 0.0, clampf(delta * 5.0, 0.0, 1.0))
	_psy_air = lerpf(_psy_air, 1.0 if (not grounded and _rail.is_empty()) else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	_psy_speed = lerpf(_psy_speed, clampf(-vel.y / 45.0, 0.0, 1.0), clampf(delta * 2.0, 0.0, 1.0))
	for e in _psy_ev:
		(e as Array)[0] = float((e as Array)[0]) + delta
	var e0: Array = _psy_ev[0]
	var e1: Array = _psy_ev[1]
	_psy_mat.set_shader_parameter("pa", Vector4(float(e0[0]), float(e1[0]), 9.0, 9.0))
	_psy_mat.set_shader_parameter("pk", Vector4(float(e0[1]), float(e1[1]), 0.0, 0.0))
	var ca: Color = e0[2]
	var cb: Color = e1[2]
	_psy_mat.set_shader_parameter("c0", Vector3(ca.r, ca.g, ca.b))
	_psy_mat.set_shader_parameter("c1", Vector3(cb.r, cb.g, cb.b))
	_psy_mat.set_shader_parameter("grind", _psy_grind)
	_psy_mat.set_shader_parameter("air", _psy_air)
	_psy_mat.set_shader_parameter("speed", _psy_speed)
	_psy_mat.set_shader_parameter("t", float(Time.get_ticks_msec()) * 0.001)
	_psy_mat.set_shader_parameter("rush", _psy_rush)
	_psy_mat.set_shader_parameter("gaze", Vector2(clampf(_eye_zn(), -1.0, 1.0), 0.0))
	_psy_mat.set_shader_parameter("aspect", Vector2(vs.x / maxf(vs.y, 1.0), 1.0))


func _pause_rect() -> Rect2:
	if not Game.touch_mode:
		return Rect2(-9000.0, -9000.0, 1.0, 1.0)          # on a computer there is no button: the screen is the game (Esc or P pauses)
	var vs := get_viewport().get_visible_rect().size
	var k := _hud_scale()
	return Rect2(vs.x - 66.0 * k, 10.0 * k, 54.0 * k, 44.0 * k)          # on a phone a small pause button sits in the top corner (touch only)


## The sandbox looks: a hat, and a tricycle under the rider.
func _dress_rider() -> void:
	if _rider == null:
		return
	var old := _rider.get_node_or_null("Dress")
	if old != null:
		old.queue_free()
	var dr := Node3D.new()
	dr.name = "Dress"
	_rider.add_child(dr)
	var top := 1.62 + (0.6 if big_head else 0.0)
	var hs := 3.0 if big_head else 1.0
	match hat_id:
		1:          # a top hat
			Roster.mi(dr, Roster.cyl(0.26 * hs, 0.26 * hs, 0.5 * hs), Vector3(0, top + 0.45 * hs, 0), Color(0.1, 0.1, 0.12))
			Roster.mi(dr, Roster.cyl(0.46 * hs, 0.46 * hs, 0.06), Vector3(0, top + 0.2 * hs, 0), Color(0.1, 0.1, 0.12))
		2:          # a party cone
			Roster.mi(dr, Roster.cyl(0.02, 0.3 * hs, 0.7 * hs), Vector3(0, top + 0.4 * hs, 0), Color(1.0, 0.35, 0.8))
		3:          # a propeller beanie
			Roster.mi(dr, Roster.sphere(0.3 * hs, 0.5), Vector3(0, top + 0.1 * hs, 0), Color(0.3, 0.6, 1.0))
			Roster.mi(dr, Roster.box(Vector3(0.9 * hs, 0.04, 0.12)), Vector3(0, top + 0.42 * hs, 0), Color(1.0, 0.85, 0.2))
	if trike:
		for wx in [-0.45, 0.45]:
			Roster.mi(dr, Roster.cyl(0.32, 0.32, 0.12), Vector3(wx, -0.05, 0.7), Color(0.08, 0.08, 0.1)).rotation.z = PI * 0.5
		Roster.mi(dr, Roster.cyl(0.24, 0.24, 0.1), Vector3(0, -0.1, -0.8), Color(0.08, 0.08, 0.1)).rotation.z = PI * 0.5


func _fp_now() -> bool:
	return view_fp and _cine_k < 0.5


func _face_now(kind: String) -> bool:
	if face_override == kind or Input.is_key_pressed(KEY_G):
		return true
	match kind:
		"crazy":
			return crazy_override or Input.is_key_pressed(KEY_Z) or _crazy_eyes_now()
		"shake":
			return head_shake_override or Input.is_key_pressed(KEY_H) or _head_shake_now()
	return GazeProvider.face_is(kind)


func _face_pick() -> String:
	var ids: Array = FACES.keys()
	ids.erase(_face_last)
	return String(ids[_fx_rng.randi() % ids.size()])


## In the air: now and then the game demands a face. Pull it for a moment for a big bonus; ignore it and nothing is lost.
func _face_tick(delta: float, alt: float) -> void:
	var rd := delta / maxf(Engine.time_scale, 0.05)
	if face_kind == "":
		if _air_time >= _face_next and alt > 3.0 and not _air_moves.has("slam"):
			face_kind = _face_pick()
			_face_last = face_kind
			face_t = FACE_WINDOW
			face_hold = 0.0
			face_open = FACE_OPENERS[_fx_rng.randi() % FACE_OPENERS.size()]
			_trk_burst_t = 0.4
			Game.sfx(&"bell")
			_fov_punch = maxf(_fov_punch, 4.0)
		return
	face_t -= rd
	var ok := _face_now(face_kind)
	face_hold = face_hold + rd if ok else maxf(face_hold - rd * 2.0, 0.0)
	if face_hold >= 0.3:
		var id := "face_" + face_kind
		face_done += 1
		_flow_up()
		face_seen[face_kind] = int(face_seen.get(face_kind, 0)) + 1
		_add_move(id)
		face_kind = ""
		_face_next = _air_time + 1.6 / face_k
		if _super_face:
			_super_face = false
			_gain(int(600.0 * groove))
			_cheer("SUPER FACE!", Color(1.0, 0.9, 0.2), 1.8)
		_trip_add(0.08)
		if face_k > 1.2:
			_gain(int(250.0 * groove * face_k))
		_burst(Vector3(spos.x, spos.y + 1.6, spos.z), Color(1.0, 0.85, 0.3), 50, 9.0, 1.0, 1.0)
	elif face_t <= 0.0:
		face_kind = ""
		_face_next = _air_time + 1.8 / face_k
		_trk_text = "...nothing?"
		_trk_text_t = 0.8


## A hero shot: when you are far up, the camera swings out to a low angle on the rider (slow motion helps) and comes back before the ground does.
func _cine_apply(delta: float) -> void:
	var rd := delta / maxf(Engine.time_scale, 0.05)
	var alt := spos.y - terrain_h(spos.x, spos.z)
	var want := cine_enabled and _in_air and hurt_t <= 0.0 and not _finished and (_air_peak >= 7.0 and alt > 5.0 and (_air_time > 0.5)) and not (vy < 0.0 and alt < 7.0)
	if want and not _cine_on:
		cines += 1
		_cine_side = 1.0 if _fx_rng.randf() < 0.5 else -1.0
		_cine_t = 0.0
	_cine_on = want
	if _cine_on:
		_cine_t += rd
	_cine_k = move_toward(_cine_k, 1.0 if want else 0.0, rd * 3.0)
	if _cine_k <= 0.001:
		return
	var a := _cine_side * (0.9 + _cine_t * 0.45)
	var pos := Vector3(spos.x + sin(a) * 10.5, spos.y + 0.6 + sin(_cine_t * 0.8) * 0.8, spos.z + cos(a) * 10.5 * 0.8 - 2.0)
	pos.y = maxf(pos.y, terrain_h(pos.x, pos.z) + 1.5)
	var tgt := Vector3(spos.x, spos.y + 0.9, spos.z)
	var ease_k := _cine_k * _cine_k * (3.0 - 2.0 * _cine_k)
	var p0 := cam.global_position
	var b0 := cam.global_transform.basis.get_rotation_quaternion()
	cam.global_position = p0.lerp(pos, ease_k)
	var look_b := Basis.looking_at((tgt - pos).normalized(), Vector3.UP)
	cam.global_transform.basis = Basis(b0.slerp(look_b.get_rotation_quaternion(), ease_k))
	cam.fov = lerpf(cam.fov, 62.0, ease_k)
	if _cine_on and Engine.time_scale >= 0.99 and _slowmo_t <= 0.0:
		Engine.time_scale = 0.6                       # the director holds the moment
	elif not _cine_on and Engine.time_scale < 0.99 and _slowmo_t <= 0.0:
		Engine.time_scale = 1.0


func _tricks_look(key: float, pk: Vector3) -> float:
	var look := key + (_steer_gaze if _eye_on else clampf(pk.x / 1.8, -1.0, 1.0))
	return clampf(look + trick_look_override, -1.5, 1.5)


const SPIN_NAMES := ["", "THE LAZY SUSAN", "THE FULL LAZY SUSAN", "THE WASHING MACHINE", "HELICOPTER DAD", "THE EXORCIST", "WEATHER REPORT", "ABSOLUTE TORNADO"]
const FLIP_NAMES := ["THE BACKFLIP", "THE PANCAKE", "OOPS ALL FLIPS", "THE SPICY FLIP", "SOMERSAULT SALAD"]
const GRAB_NAMES := ["THE BAGEL GRAB", "GRANDMA'S GRAB", "THE BURGER GRAB", "THE NOPE ROPE", "MELON GRAB (LIGHT)"]
const SHAKE_NAMES := ["THE BOBBLEHEAD", "NOPE NOPE NOPE", "THE WET DOG", "MAXIMUM NOPE"]
const CROSS_NAMES := ["BIG BRAIN TIME", "THE CROSS-EYED CRUSADER", "SPOOKY EYES", "ONE EYE ON EACH THING"]
const CRAZY_NAMES := ["THE GOOSE EYES", "WIGGLE WIGGLE", "THE LOOSE MARBLES", "CHAOS PUPILS"]
const SLAM_NAMES := ["THE ELBOW DROP OF DESTINY", "THE PEOPLE'S ELBOW", "FLYING SPLASH OFF THE CLIFF", "THE PILEDRIVER (INTO SNOW)", "THE SUPLEX (OF SADNESS)"]
const COMMENTARY := ["AND THE CROWD GOES WILD!", "SOMEONE CALL HIS MOTHER!", "I'VE NEVER SEEN ANYTHING LIKE IT!", "THE JUDGES ARE WEEPING!", "IS HE EVEN HUMAN?!", "NO FEAR! NO KNEES!", "SCIENTISTS ARE BAFFLED!", "PUT THAT ON A T-SHIRT!", "THE SNOW WILL REMEMBER THIS!", "ABSOLUTE UNIT!", "BRING BACK THE REPLAY!", "WHAT A TIME TO BE ALIVE!", "MOM! GET THE CAMERA!", "THE PHYSICS TEAM IS SWEATING!"]
const SLAM_LINES := ["TABLES! WE NEED TABLES!", "OH THE HUMANITY!", "DING DING DING!", "HE'S GOING FOR THE PIN!", "THE ROPES ARE BURNING!"]
const FALL_LINES := ["...that was just falling.", "Ten out of ten for gravity.", "A bold choice to do nothing.", "Please do something next time.", "The snow was not impressed."]
const MOVE_PTS := {"shake": 120, "cross": 150, "crazy": 150, "slam": 300}

var head_shake_override: bool = false
var cross_override: bool = false
var crazy_override: bool = false
var slam_override: bool = false
var ridiculous: int = 0
var _air_moves: Array = []
var _move_name: Dictionary = {}
var _chaos_pts: int = 0
var _chaos_last: String = ""
var _trk_comment: String = ""
var _trk_comment_t: float = 0.0
var _trk_burst_t: float = 0.0
var _slowmo_t: float = 0.0
var _air_time: float = 0.0
var _slam_fell: bool = false
var _hs_state: Dictionary = {}
var _cz_state: Dictionary = {}


## A zigzag detector: how many times has a value turned round, by at least `amp`, in the last `window` seconds? (Head shakes and darting eyes.)
func _zig_push(st: Dictionary, v: float, t: float, amp: float, window: float) -> int:
	if not st.has("ext"):
		st["ext"] = v
		st["dir"] = 0.0
		st["revs"] = []
		return 0
	var dir: float = st["dir"]
	var ext: float = st["ext"]
	if dir == 0.0:
		if absf(v - ext) > amp:
			st["dir"] = signf(v - ext)
			st["ext"] = v
	elif (v - ext) * dir > 0.0:
		st["ext"] = v
	elif absf(v - ext) > amp:
		(st["revs"] as Array).append(t)
		st["dir"] = -dir
		st["ext"] = v
	var revs: Array = st["revs"]
	while not revs.is_empty() and t - float(revs[0]) > window:
		revs.remove_at(0)
	return revs.size()


func _head_shake_now() -> bool:
	if not GazeProvider.head_rpy_ok or not _eye_on:
		return false
	return _zig_push(_hs_state, -rad_to_deg(GazeProvider.head_rpy.x), _age, 4.0, 1.0) >= 3


func _crazy_eyes_now() -> bool:
	if not _eye_on:
		return false
	var amp := maxf(0.35 * _ex_full, 0.006)
	return _zig_push(_cz_state, GazeProvider.eih.x, _age, amp, 0.9) >= 4


func _pick(arr: Array) -> String:
	return String(arr[_fx_rng.randi() % arr.size()])


## One extra move in the air: a name, a bit of noise and a line from the commentators.
func _add_move(id: String) -> void:
	if _air_moves.has(id):
		return
	_air_moves.append(id)
	_chain_hit("air")
	var nm := ""
	if id.begins_with("face_") and FACES.has(id.substr(5)):
		nm = String(FACES[id.substr(5)]["name"])
		Game.sfx(&"honk" if _fx_rng.randf() < 0.5 else &"boing")
		_toast("+%d  %s" % [int(FACES[id.substr(5)]["pts"]), nm], Color(1.0, 0.85, 0.3), "face")
	match id:
		"shake":
			nm = _pick(SHAKE_NAMES)
			Game.sfx(&"squeak")
		"cross":
			nm = _pick(CROSS_NAMES)
			Game.sfx(&"boing")
		"crazy":
			nm = _pick(CRAZY_NAMES)
			Game.sfx(&"honk")
		"slam":
			nm = _pick(SLAM_NAMES)
			Game.sfx(&"bell")
			vy -= 7.0                                          # a slam: you drop out of the sky
			_slam_fell = true
			_shake = maxf(_shake, 0.4)
	_move_name[id] = nm
	_trk_text = nm + "!"
	_trk_text_t = 1.0
	_trk_comment = _pick(SLAM_LINES if id == "slam" else COMMENTARY)
	_trk_comment_t = 1.6
	_trk_burst_t = 0.5
	_gain(20)
	var big := _air_peak > 2.5 or _air_epic
	if _fx_rng.randf() < (0.45 if big else 0.2):
		_chaos_event()


## The ridiculous part: now and then, a move sets off something nobody asked for.
func _chaos_event() -> void:
	var opts := ["goose", "snowman", "slowmo", "fireworks", "crowd"]
	opts.erase(_chaos_last)
	var pick: String = opts[_fx_rng.randi() % opts.size()]
	_chaos_last = pick
	ridiculous += 1
	var pos := Vector3(spos.x, spos.y + 2.0, spos.z)
	match pick:
		"goose":
			_burst(pos, Color(1.0, 0.95, 0.7), 60, 12.0, 1.0, 1.4)
			_toast("HONK!!!  A GOOSE HAS ENTERED THE CHAT", Color(1.0, 0.95, 0.6))
			Game.sfx(&"honk")
			_chaos_pts += 150
		"snowman":
			_spawn_snowman()
			_toast("A SNOWMAN APPEARS TO WATCH", Color(0.9, 0.97, 1.0))
			Game.sfx(&"pop")
			_chaos_pts += 100
		"slowmo":
			_slowmo_t = 0.45
			Engine.time_scale = 0.45
			_toast("HANG TIME!", Color(0.8, 0.9, 1.0))
			_chaos_pts += 120
		"fireworks":
			for fi in 4:
				var fp := pos + Vector3(_fx_rng.randf_range(-9.0, 9.0), _fx_rng.randf_range(2.0, 9.0), -_fx_rng.randf_range(0.0, 14.0))
				var fc := Color.from_hsv(_fx_rng.randf(), 0.8, 1.0)
				_burst(fp, fc, 50, 11.0, 1.2, 1.2, Vector3.UP, 180.0, -3.0)
			_toast("FIREWORKS (NOBODY ASKED)", Color(1.0, 0.85, 0.5))
			Game.sfx(&"boom")
			_chaos_pts += 200
		_:
			_burst(pos, Color(1.0, 0.8, 0.3), 70, 10.0, 1.4, 1.3, Vector3.UP, 180.0, -9.0)
			_burst(pos, Color(0.4, 0.9, 1.0), 70, 10.0, 1.4, 1.3, Vector3.UP, 180.0, -9.0)
			_toast("THE CROWD GOES WILD (WHAT CROWD?)", Color(1.0, 0.9, 0.5))
			Game.sfx(&"crowd")
			_chaos_pts += 150


func _spawn_snowman() -> void:
	var sx := clampf(spos.x + (9.0 if _fx_rng.randf() < 0.5 else -9.0), -42.0, 42.0)
	var sz := spos.z - 26.0
	var n := Node3D.new()
	_mi(n, _sphere_mesh(1.0), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 1.0, 0))
	_mi(n, _sphere_mesh(0.75), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 2.3, 0))
	_mi(n, _sphere_mesh(0.55), _food_mat(Color(0.97, 0.98, 1.0), 0.3), Vector3(0, 3.35, 0))
	var nose := _cone(0.12, 0.7)
	nose.material_override = _food_mat(Color(1.0, 0.5, 0.1))
	n.add_child(nose)
	nose.position = Vector3(0, 3.35, 0.7)
	nose.rotation.x = PI * 0.5
	for ex in [-0.2, 0.2]:
		_mi(n, _sphere_mesh(0.07), _food_mat(Color(0.05, 0.05, 0.08), 0.0), Vector3(float(ex), 3.5, 0.5))
	add_child(n)
	_place(n, Vector3(sx, terrain_h(sx, sz) - 0.2, sz))
	n.scale = Vector3.ONE * 0.1
	n.rotation.y = PI
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(5.0)
	tw.tween_callback(n.queue_free)


func _update_tricks(delta: float, key: float, pk: Vector3) -> void:
	_trk_text_t = maxf(_trk_text_t - delta, 0.0)
	_trk_comment_t = maxf(_trk_comment_t - delta, 0.0)
	_trk_burst_t = maxf(_trk_burst_t - delta, 0.0)
	if _slowmo_t > 0.0:
		_slowmo_t -= delta
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	var alt := spos.y - terrain_h(spos.x, spos.z)
	var air := (not grounded) and alt > 0.6 and air_t > 0.1 and not _finished and hurt_t <= 0.0
	if air:
		if not _in_air:
			_in_air = true
			Game.sfx(&"launch")
			_trk_spin = 0.0
			_trk_spin_v = 0.0
			_trk_flip = 0.0
			_trk_flip_goal = 0.0
			_trk_grab_t = 0.0
			_air_peak = 0.0
			_air_time = 0.0
			_air_moves.clear()
			_move_name.clear()
			face_kind = ""
			_face_next = 0.8
			_chaos_pts = 0
			_slam_fell = false
			_air_epic = false
			for ke in _kickers:
				if bool(ke.get("epic", false)) and spos.z <= float(ke["z"]) and float(ke["z"]) - spos.z < 40.0 and absf(spos.x - float(ke["x"])) < 12.0:
					_air_epic = true
			if _air_epic:
				_toast("EPIC JUMP!", Color(1.0, 0.45, 0.7))
				_fov_punch = 6.0
			if not _trk_hint and alt > 0.8:
				_trk_hint = true
				_toast("In the air: look aside to spin, chin down to grab, shake your head, cross your eyes...", Color(0.9, 0.95, 1.0))
		_air_peak = maxf(_air_peak, alt)
		_air_time += delta
		if _air_epic and alt > 4.0 and not _finished:
			vel *= exp(-sky_drag * delta)                       # high up the air is thick: you hang there and drift, and the landing stays inside the cleared run-out
		var look := _tricks_look(key, pk)
		var landing := alt < 2.0 and vy < 0.0
		var target := 0.0
		if absf(look) > 0.45 and not landing:
			target = signf(look) * TAU * 0.85
		_trk_spin_v = lerpf(_trk_spin_v, target, 1.0 - exp(-8.0 * delta))
		_trk_spin += _trk_spin_v * delta
		if landing:
			_trk_spin = lerpf(_trk_spin, roundf(_trk_spin / PI) * PI, 1.0 - exp(-12.0 * delta))
		var grab := nod_p < -0.10 or trick_grab_override or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		if grab:
			_trk_grab_t += delta
		var fk := nod_v > 1.1 or trick_flip_override or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		if fk and not _flip_key_prev and alt > 1.2 and _trk_flip >= _trk_flip_goal - 0.2 and _trk_flip_goal < TAU * 2.0:
			_trk_flip_goal += TAU
		_flip_key_prev = fk
		_trk_flip = move_toward(_trk_flip, _trk_flip_goal, TAU * (3.0 if landing else 1.7) * delta)
		if alt > 1.0:
			if head_shake_override or Input.is_key_pressed(KEY_H) or _head_shake_now():
				_add_move("shake")
			if cross_override or Input.is_key_pressed(KEY_X) or GazeProvider.cross_eyed():
				_add_move("cross")
			if crazy_override or Input.is_key_pressed(KEY_Z) or _crazy_eyes_now():
				_add_move("crazy")
			if alt > 2.0 and (slam_override or Input.is_key_pressed(KEY_F) or nod_v < -1.6):
				_add_move("slam")
		if face_enabled and alt > 1.0:
			_face_tick(delta, alt)
		var parts := _trick_parts(false)
		if not parts.is_empty() and _trk_text_t < 0.3:
			_trk_text = " + ".join(parts)
			_trk_text_t = 0.25
	elif _in_air:
		_in_air = false
		face_kind = ""
		_cine_on = false
		if Engine.time_scale < 0.99 and _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
		if _slowmo_t > 0.0:
			_slowmo_t = 0.0
			Engine.time_scale = 1.0
		if hurt_t > 0.0:
			_trk_text = "BAILED"
			_trk_comment = "(he's fine, he's fine)"
			_trk_text_t = 1.2
			_trk_comment_t = 1.4
		else:
			_land_tricks()
		_trk_vis_spin = _trk_spin - roundf(_trk_spin / TAU) * TAU
		_trk_vis_flip = _trk_flip - roundf(_trk_flip / TAU) * TAU
		_trk_spin = 0.0
		_trk_flip = 0.0
		_trk_flip_goal = 0.0
		_trk_spin_v = 0.0
	if not _in_air:
		_trk_vis_spin = move_toward(_trk_vis_spin, 0.0, 14.0 * delta)
		_trk_vis_flip = move_toward(_trk_vis_flip, 0.0, 14.0 * delta)
	var ts := (_trk_spin if _in_air else _trk_vis_spin)
	var tf := (_trk_flip if _in_air else _trk_vis_flip)
	var wob := 0.0
	if _in_air and (_air_moves.has("shake") or _air_moves.has("crazy")):
		wob = sin(_age * 40.0) * 0.07
	_trk_cam_roll = lerpf(_trk_cam_roll, sin(ts) * 0.16 + wob, 1.0 - exp(-14.0 * delta))
	_trk_cam_pitch = lerpf(_trk_cam_pitch, sin(tf) * 0.3, 1.0 - exp(-14.0 * delta))


## The plain list while you are in the air (degrees and the moves so far), or the silly names once you land.
func _trick_parts(funny: bool) -> Array:
	var parts: Array = []
	var n := int(roundf(absf(_trk_spin) / PI))
	if n >= 1:
		parts.append(SPIN_NAMES[mini(n, SPIN_NAMES.size() - 1)] if funny else str(n * 180))
	var fl := int(floorf(_trk_flip / TAU + 0.25))
	if fl >= 1:
		parts.append((FLIP_NAMES[_fx_rng.randi() % FLIP_NAMES.size()] if fl == 1 else "DOUBLE " + FLIP_NAMES[_fx_rng.randi() % FLIP_NAMES.size()]) if funny else ("FLIP" if fl == 1 else "DOUBLE FLIP"))
	if _trk_grab_t >= 0.35:
		parts.append(_pick(GRAB_NAMES) if funny else "GRAB")
	for mv in _air_moves:
		parts.append(String(_move_name.get(mv, mv)))
	return parts


func _land_tricks() -> void:
	var n := int(roundf(absf(_trk_spin) / PI))
	var fl := int(floorf(_trk_flip / TAU + 0.25))
	var gr := mini(int(_trk_grab_t / 0.35), 5)
	var pts := 0
	var kinds := 0
	if n >= 1:
		pts += [0, 100, 250, 450, 700, 1000][mini(n, 5)]
		kinds += 1
	if fl >= 1:
		pts += 220 * fl
		kinds += 1
	if gr >= 1:
		pts += 40 * gr
		kinds += 1
	for mv in _air_moves:
		pts += int(FACES[String(mv).substr(5)]["pts"]) if (String(mv).begins_with("face_") and FACES.has(String(mv).substr(5))) else int(MOVE_PTS.get(mv, 100))
		kinds += 1
	if _air_peak > 2.5:
		pts += 30
	if pts <= 30:
		if _air_time > 0.8:
			_trk_text = "JUST FALLING"
			_trk_comment = _pick(FALL_LINES)
			_trk_text_t = 1.6
			_trk_comment_t = 1.8
		return
	var mult := minf(1.0 + 0.5 * float(maxi(kinds - 1, 0)), 4.0)
	pts = int(float(pts) * mult) + _chaos_pts
	if _air_epic:
		pts = int(float(pts) * 1.6)
	var name := " + ".join(_trick_parts(true))
	if _air_epic:
		name = "EPIC " + name
	tricks_landed += 1
	trick_score += pts
	if best_trick == "" or pts > int(best_trick.get_slice("|", 1)):
		best_trick = "%s|%d" % [name, pts]
	_gain(pts)
	_flow_up(2 if pts >= 400 else 1)
	var shown := name
	if shown.length() > 64:
		shown = shown.substr(0, 61) + "..."
	_trk_text = "%s  +%d" % [shown, pts] if name != "" else "AIR  +%d" % pts
	_trk_text_t = 2.2
	_trk_comment = _pick(SLAM_LINES if _air_moves.has("slam") else COMMENTARY)
	_trk_comment_t = 2.4
	_trk_burst_t = 0.7
	_flash = 0.3
	_shake = maxf(_shake, 0.3)
	_pop_col = Color(1.0, 0.85, 0.3)
	_pop_a = 0.8
	var gp := Vector3(spos.x, spos.y + 1.0, spos.z)
	_burst(gp, Color(1.0, 0.9, 0.5), 40, 10.0, 0.9, 1.0)
	_ring(Vector3(spos.x, spos.y + 0.3, spos.z), Color(1.0, 0.85, 0.4), 9.0, 0.5, false)
	if _slam_fell:
		_ring(Vector3(spos.x, spos.y + 0.3, spos.z), Color(1.0, 0.5, 0.3), 16.0, 0.7, false)
		_burst(gp, Color(0.95, 0.98, 1.0), 80, 14.0, 1.0, 2.0, Vector3.UP, 180.0, -9.0)
		_shake = maxf(_shake, 0.9)
		Game.sfx(&"boom")
		Game.sfx(&"crowd")
	if _air_epic or kinds >= 3:
		Game.sfx(&"levelup")
	else:
		Game.sfx(&"buff_mult")


func _draw_eyes_hud(font: Font, s: Vector2, k: float) -> void:
	# squinting: the top and bottom of the view close in, like narrowed eyes
	_squint_vis = lerpf(_squint_vis, 1.0 if _squinting_now else 0.0, 0.25)
	if _squint_vis > 0.02:
		var bh := s.y * 0.14 * _squint_vis
		_hud.draw_rect(Rect2(0.0, 0.0, s.x, bh), Color(0.02, 0.03, 0.08, 0.88))
		_hud.draw_rect(Rect2(0.0, s.y - bh, s.x, bh), Color(0.02, 0.03, 0.08, 0.88))
	# the nearest food you can still reach: what to do with your eyes
	if eat_enabled and not _finished:
		var best: Dictionary = {}
		var bd := 1.0e9
		for kk in _rows:
			var r: Dictionary = _rows[kk]
			if absf(float(r["z"]) - spos.z) > 130.0:
				continue
			for b in r["buffs"]:
				if b["taken"] or float(b.get("arm", 0.0)) > 0.0:
					continue
				var dz := spos.z - float(b["z"])
				if dz < 3.0 or dz > 36.0 or absf(float(b["x"]) - spos.x) > 0.3 * dz + 4.0:
					continue
				if dz < bd:
					bd = dz
					best = b
		if not best.is_empty():
			var bp := _food_pos(best) + Vector3(0, 2.8, 0)
			if not _behind(bp):
				var sc := _unp(bp)
				var can := _can_eat()
				var txt := "CHOMP!" if can else "OPEN WIDE"
				var col := Color(0.5, 1.0, 0.6) if can else Color(1.0, 0.9, 0.4)
				var pulse := 1.0 + 0.12 * sin(_age * 10.0)
				var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k * pulse)).x
				_text(font, sc + Vector2(-w * 0.5, 0.0), txt, int(24.0 * pulse), col)
	# snowballs: where they are and what to do
	for b2 in _balls:
		if b2["done"]:
			continue
		var wp := Vector3(float(b2["x"]), terrain_h(float(b2["x"]), float(b2["z"])) + BALL_R + 3.0, float(b2["z"]))
		if _behind(wp):
			continue
		var sp2 := _unp(wp)
		var dist := maxf(spos.z - float(b2["z"]), 0.0)
		var near := dist < 45.0
		var c2 := Color(1.0, 0.45, 0.3) if near and not _braced() else Color(0.8, 0.95, 1.0)
		var tri := PackedVector2Array([sp2 + Vector2(0, -22.0 * k), sp2 + Vector2(-18.0 * k, 10.0 * k), sp2 + Vector2(18.0 * k, 10.0 * k)])
		Draw2D.poly(_hud, tri, Color(c2.r, c2.g, c2.b, 0.9))
		_hud.draw_rect(Rect2(sp2 + Vector2(-2.5 * k, -10.0 * k), Vector2(5.0 * k, 11.0 * k)), Color(0.1, 0.05, 0.05, 0.95))
		if near and not _braced():
			var away := signf(spos.x - float(b2["x"]))
			if away == 0.0:
				away = 1.0
			for ci in 2:
				var ax := sp2.x + away * (30.0 + 16.0 * float(ci)) * k
				var ay := sp2.y - 4.0 * k
				_hud.draw_line(Vector2(ax, ay) + Vector2(-away * 8.0 * k, -10.0 * k), Vector2(ax, ay), Color(1, 1, 1, 0.9 - 0.3 * float(ci)), 4.0 * k)
				_hud.draw_line(Vector2(ax, ay) + Vector2(-away * 8.0 * k, 10.0 * k), Vector2(ax, ay), Color(1, 1, 1, 0.9 - 0.3 * float(ci)), 4.0 * k)


## A simple picture of each face the game asks for, so the prompt can be read at a glance: a round face with the one feature that matters drawn big.
## The big cartoon version of a face challenge: fat white eyes with glints, thick brows, a clear mouth. It is meant to be copied at a glance, with no reading.
func _eye_big(c: Vector2, R: float, pup: Vector2, pr: float, ink: Color) -> void:
	Draw2D.circle(_hud, c, R + R * 0.1, ink)
	Draw2D.circle(_hud, c, R, Color(1, 1, 1))
	Draw2D.circle(_hud, c + pup * R, pr, ink)
	Draw2D.circle(_hud, c + pup * R + Vector2(-pr * 0.32, -pr * 0.34), pr * 0.3, Color(1, 1, 1))


func _brow_big(a: Vector2, b: Vector2, w: float, ink: Color) -> void:
	_hud.draw_line(a, b, ink, w, true)
	Draw2D.circle(_hud, a, w * 0.5, ink)
	Draw2D.circle(_hud, b, w * 0.5, ink)


func _face_big(c: Vector2, r: float, kind: String) -> void:
	var ink := Color(0.1, 0.07, 0.06)
	var skin := Color(1.0, 0.86, 0.3)
	var red := Color(1.0, 0.3, 0.4)
	var pink := Color(1.0, 0.45, 0.6)
	var white := Color(1, 1, 1)
	var bw := r * 0.11
	Draw2D.circle(_hud, c, r + r * 0.06, Color(0, 0, 0, 0.8))
	Draw2D.circle(_hud, c, r, skin)
	var ex := r * 0.42
	var ey := -r * 0.18
	var R := r * 0.3
	var L := c + Vector2(-ex, ey)
	var Rr := c + Vector2(ex, ey)
	match kind:
		"crazy":
			_eye_big(L, R * 1.1, Vector2(0.35, 0.4), R * 0.45, ink)
			_eye_big(Rr, R * 1.1, Vector2(-0.3, -0.38), R * 0.45, ink)
			_brow_big(L + Vector2(-R * 1.1, -R * 1.5), L + Vector2(R * 0.9, -R * 1.2), bw, ink)
			_brow_big(Rr + Vector2(-R * 0.9, -R * 1.75), Rr + Vector2(R * 1.2, -R * 1.45), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.28), r * 0.38, 0.12 * PI, 0.88 * PI, 18, ink, bw * 0.9, true)
		"tongue":
			_eye_big(L, R, Vector2(0.0, -0.25), R * 0.42, ink)
			_eye_big(Rr, R, Vector2(0.0, -0.25), R * 0.42, ink)
			_brow_big(L + Vector2(-R, -R * 1.4), L + Vector2(R, -R * 1.55), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 1.55), Rr + Vector2(R, -R * 1.4), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.12), r * 0.46, 0.1 * PI, 0.9 * PI, 18, ink, bw, true)
			Draw2D.poly(_hud, PackedVector2Array([c + Vector2(-r * 0.2, r * 0.52), c + Vector2(r * 0.2, r * 0.52), c + Vector2(r * 0.2, r * 0.8), c + Vector2(0, r * 0.95), c + Vector2(-r * 0.2, r * 0.8)]), pink)
			_hud.draw_line(c + Vector2(0, r * 0.56), c + Vector2(0, r * 0.76), Color(0.8, 0.2, 0.4), bw * 0.5, true)
		"smile":
			for ec in [L, Rr]:
				Draw2D.arc(_hud, ec + Vector2(0, R * 0.3), R * 0.9, PI * 1.08, PI * 1.92, 14, ink, bw, true)
			Draw2D.poly(_hud, PackedVector2Array([c + Vector2(-r * 0.62, r * 0.12), c + Vector2(r * 0.62, r * 0.12), c + Vector2(r * 0.42, r * 0.62), c + Vector2(0, r * 0.78), c + Vector2(-r * 0.42, r * 0.62)]), ink)
			Draw2D.poly(_hud, PackedVector2Array([c + Vector2(-r * 0.5, r * 0.14), c + Vector2(r * 0.5, r * 0.14), c + Vector2(r * 0.42, r * 0.3), c + Vector2(-r * 0.42, r * 0.3)]), white)
		"shock":
			_eye_big(L, R * 1.2, Vector2(0, 0), R * 0.22, ink)
			_eye_big(Rr, R * 1.2, Vector2(0, 0), R * 0.22, ink)
			_brow_big(L + Vector2(-R, -R * 1.9), L + Vector2(R, -R * 2.1), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 2.1), Rr + Vector2(R, -R * 1.9), bw, ink)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.5), r * 0.2, ink)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.52), r * 0.12, Color(0.8, 0.2, 0.3))
		"pain":
			for ec in [L, Rr]:
				_hud.draw_line(ec + Vector2(-R * 0.8, -R * 0.8), ec + Vector2(R * 0.8, R * 0.8), ink, bw * 1.1, true)
				_hud.draw_line(ec + Vector2(-R * 0.8, R * 0.8), ec + Vector2(R * 0.8, -R * 0.8), ink, bw * 1.1, true)
			_brow_big(L + Vector2(-R, -R * 1.2), L + Vector2(R, -R * 1.9), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 1.9), Rr + Vector2(R, -R * 1.2), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.8), r * 0.4, 1.15 * PI, 1.85 * PI, 16, ink, bw, true)
			Draw2D.circle(_hud, c + Vector2(r * 0.8, -r * 0.1), r * 0.07, Color(0.4, 0.7, 1.0))
		"wide":
			_eye_big(L, R * 1.3, Vector2(0, 0), R * 0.3, ink)
			_eye_big(Rr, R * 1.3, Vector2(0, 0), R * 0.3, ink)
			_brow_big(L + Vector2(-R, -R * 2.1), L + Vector2(R, -R * 2.2), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 2.2), Rr + Vector2(R, -R * 2.1), bw, ink)
			_hud.draw_line(c + Vector2(-r * 0.22, r * 0.55), c + Vector2(r * 0.22, r * 0.55), ink, bw, true)
		"cross":
			_eye_big(L, R * 1.1, Vector2(0.45, 0.05), R * 0.45, ink)
			_eye_big(Rr, R * 1.1, Vector2(-0.45, 0.05), R * 0.45, ink)
			_brow_big(L + Vector2(-R, -R * 1.5), L + Vector2(R, -R * 1.3), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 1.3), Rr + Vector2(R, -R * 1.5), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.35), r * 0.3, 0.15 * PI, 0.85 * PI, 14, ink, bw, true)
		"squint":
			_hud.draw_line(L + Vector2(-R, 0), L + Vector2(R, 0), ink, bw * 1.2, true)
			_eye_big(Rr, R * 0.7, Vector2(0, 0.1), R * 0.3, ink)
			_brow_big(L + Vector2(-R, -R * 1.0), L + Vector2(R, -R * 0.5), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 0.5), Rr + Vector2(R, -R * 1.0), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.42), r * 0.3, 0.1 * PI, 0.9 * PI, 14, ink, bw, true)
		"puff":
			_eye_big(L, R * 0.8, Vector2(0, 0), R * 0.35, ink)
			_eye_big(Rr, R * 0.8, Vector2(0, 0), R * 0.35, ink)
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * r * 0.62, r * 0.32), r * 0.34, skin.lightened(0.2))
				Draw2D.arc(_hud, c + Vector2(float(sx) * r * 0.62, r * 0.32), r * 0.34, 0.0, TAU, 20, ink, bw * 0.6, true)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.42), r * 0.1, ink)
		"kiss":
			for ec in [L, Rr]:
				Draw2D.arc(_hud, ec + Vector2(0, R * 0.2), R * 0.9, PI * 1.08, PI * 1.92, 14, ink, bw, true)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.45), r * 0.2, red)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.45), r * 0.07, Color(0.5, 0.05, 0.15))
			for hp in [Vector2(0.75, -0.55), Vector2(1.0, -0.8)]:
				Draw2D.circle(_hud, c + hp * r, r * 0.12, red)
		"sneer":
			_eye_big(L, R * 0.85, Vector2(0.25, 0.1), R * 0.35, ink)
			_eye_big(Rr, R * 0.85, Vector2(0.25, 0.1), R * 0.35, ink)
			_brow_big(L + Vector2(-R, -R * 1.9), L + Vector2(R, -R * 1.0), bw, ink)
			_brow_big(Rr + Vector2(-R, -R * 1.0), Rr + Vector2(R, -R * 1.9), bw, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.5), r * 0.34, 1.12 * PI, 1.88 * PI, 14, ink, bw, true)
			Draw2D.poly(_hud, PackedVector2Array([c + Vector2(r * 0.18, r * 0.4), c + Vector2(r * 0.34, r * 0.4), c + Vector2(r * 0.26, r * 0.58)]), white)
		"shake":
			for off in [-0.28, 0.28]:
				var oc := c + Vector2(off * r, 0)
				Draw2D.circle(_hud, oc, r * 0.7, Color(1.0, 0.86, 0.3, 0.45))
			_eye_big(L, R * 0.8, Vector2(0, 0), R * 0.35, ink)
			_eye_big(Rr, R * 0.8, Vector2(0, 0), R * 0.35, ink)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.35), r * 0.3, 0.15 * PI, 0.85 * PI, 14, ink, bw, true)
			for sx in [-1.0, 1.0]:
				var ax := c + Vector2(float(sx) * r * 1.25, 0)
				_hud.draw_line(ax - Vector2(float(sx) * r * 0.25, 0), ax + Vector2(float(sx) * r * 0.25, 0), Color(1, 1, 1), bw, true)
				Draw2D.poly(_hud, PackedVector2Array([ax + Vector2(float(sx) * r * 0.4, 0), ax + Vector2(float(sx) * r * 0.15, -r * 0.18), ax + Vector2(float(sx) * r * 0.15, r * 0.18)]), Color(1, 1, 1))


func _face_icon(c: Vector2, r: float, kind: String) -> void:
	var skin := Color(1.0, 0.88, 0.3)
	var ink := Color(0.12, 0.08, 0.05)
	var white := Color(1, 1, 1)
	var red := Color(0.95, 0.25, 0.3)
	Draw2D.circle(_hud, c, r + 3.0, Color(0, 0, 0, 0.75))
	Draw2D.circle(_hud, c, r, skin)
	var ex := r * 0.36
	var ey := -r * 0.22
	var ew := r * 0.9
	match kind:
		"tongue":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.1, ink)
			_hud.draw_rect(Rect2(c + Vector2(-r * 0.42, r * 0.22), Vector2(r * 0.84, r * 0.14)), ink)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.52), r * 0.22, red)
			_hud.draw_rect(Rect2(c + Vector2(-r * 0.22, r * 0.26), Vector2(r * 0.44, r * 0.26)), red)
		"smile":
			for sx in [-1.0, 1.0]:
				Draw2D.arc(_hud, c + Vector2(float(sx) * ex, ey + r * 0.08), r * 0.14, PI, TAU, 10, ink, r * 0.07)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.02), r * 0.62, 0.12 * PI, 0.88 * PI, 20, ink, r * 0.09)
		"shock":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.2, white)
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.08, ink)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.45), r * 0.2, ink)
		"pain":
			for sx in [-1.0, 1.0]:
				var p0 := c + Vector2(float(sx) * ex, ey)
				_hud.draw_line(p0 + Vector2(-r * 0.14, -r * 0.14), p0 + Vector2(r * 0.14, r * 0.14), ink, r * 0.08)
				_hud.draw_line(p0 + Vector2(-r * 0.14, r * 0.14), p0 + Vector2(r * 0.14, -r * 0.14), ink, r * 0.08)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.75), r * 0.42, 1.18 * PI, 1.82 * PI, 16, ink, r * 0.09)
		"wide":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.27, white)
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.1, ink)
			_hud.draw_line(c + Vector2(-r * 0.3, r * 0.5), c + Vector2(r * 0.3, r * 0.5), ink, r * 0.07)
		"cross":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.24, white)
				Draw2D.circle(_hud, c + Vector2(float(sx) * (ex - r * 0.14), ey), r * 0.09, ink)
			_hud.draw_line(c + Vector2(-r * 0.3, r * 0.5), c + Vector2(r * 0.3, r * 0.5), ink, r * 0.07)
		"squint":
			_hud.draw_line(c + Vector2(ex - r * 0.16, ey), c + Vector2(ex + r * 0.16, ey), ink, r * 0.09)
			Draw2D.circle(_hud, c + Vector2(-ex, ey), r * 0.24, ink)
			_hud.draw_line(c + Vector2(-r * 0.95, -r * 0.5), c + Vector2(r * 0.7, -r * 0.05), ink, r * 0.06)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.4), r * 0.3, 0.1 * PI, 0.9 * PI, 12, ink, r * 0.07)
		"puff":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.1, ink)
				Draw2D.circle(_hud, c + Vector2(float(sx) * r * 0.62, r * 0.28), r * 0.3, skin.lightened(0.15))
				Draw2D.arc(_hud, c + Vector2(float(sx) * r * 0.62, r * 0.28), r * 0.3, 0.0, TAU, 14, ink, r * 0.05)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.4), r * 0.1, ink)
		"kiss":
			for sx in [-1.0, 1.0]:
				Draw2D.arc(_hud, c + Vector2(float(sx) * ex, ey + r * 0.06), r * 0.14, PI, TAU, 10, ink, r * 0.07)
			Draw2D.circle(_hud, c + Vector2(0, r * 0.42), r * 0.17, red)
			Draw2D.circle(_hud, c + Vector2(r * 0.62, -r * 0.5), r * 0.14, red)
			Draw2D.circle(_hud, c + Vector2(r * 0.84, -r * 0.5), r * 0.14, red)
		"sneer":
			Draw2D.circle(_hud, c + Vector2(-ex, ey), r * 0.1, ink)
			Draw2D.circle(_hud, c + Vector2(ex, ey), r * 0.1, ink)
			_hud.draw_line(c + Vector2(-ex - r * 0.2, ey - r * 0.2), c + Vector2(-ex + r * 0.2, ey - r * 0.08), ink, r * 0.08)
			_hud.draw_line(c + Vector2(ex - r * 0.2, ey - r * 0.08), c + Vector2(ex + r * 0.2, ey - r * 0.22), ink, r * 0.08)
			_hud.draw_line(c + Vector2(-r * 0.4, r * 0.5), c + Vector2(r * 0.1, r * 0.48), ink, r * 0.08)
			_hud.draw_line(c + Vector2(r * 0.1, r * 0.48), c + Vector2(r * 0.42, r * 0.3), ink, r * 0.08)
		"crazy":
			for sx in [-1.0, 1.0]:
				var p1 := c + Vector2(float(sx) * ex, ey)
				Draw2D.circle(_hud, p1, r * 0.25, white)
				Draw2D.arc(_hud, p1, r * 0.17, 0.0, 1.5 * TAU, 16, ink, r * 0.05)
				Draw2D.arc(_hud, p1, r * 0.08, 0.0, 1.5 * TAU, 10, ink, r * 0.05)
			Draw2D.arc(_hud, c + Vector2(0, r * 0.35), r * 0.4, 0.1 * PI, 0.9 * PI, 16, ink, r * 0.08)
		"shake":
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.1, ink)
			_hud.draw_line(c + Vector2(-r * 0.3, r * 0.45), c + Vector2(r * 0.3, r * 0.45), ink, r * 0.07)
			for sx2 in [-1.0, 1.0]:
				var tip := c + Vector2(float(sx2) * r * 1.5, 0.0)
				_hud.draw_line(c + Vector2(float(sx2) * r * 1.1, 0.0), tip, white, r * 0.1)
				_hud.draw_line(tip, tip + Vector2(-float(sx2) * r * 0.22, -r * 0.2), white, r * 0.1)
				_hud.draw_line(tip, tip + Vector2(-float(sx2) * r * 0.22, r * 0.2), white, r * 0.1)
		_:
			for sx in [-1.0, 1.0]:
				Draw2D.circle(_hud, c + Vector2(float(sx) * ex, ey), r * 0.1, ink)
			_hud.draw_line(c + Vector2(-r * 0.3, r * 0.45), c + Vector2(r * 0.3, r * 0.45), ink, r * 0.07)
	if ew < 0.0:
		return


func _draw_tricks(font: Font, s: Vector2, k: float) -> void:
	if _ramp_charge > 0.02:
		var bw := 180.0 * k
		var bx := s.x * 0.5 - bw * 0.5
		var by := s.y * 0.8
		_hud.draw_rect(Rect2(bx, by, bw, 14.0 * k), Color(0.05, 0.1, 0.2, 0.6))
		_hud.draw_rect(Rect2(bx, by, bw * _ramp_charge, 14.0 * k), Color(1.0, 0.7 + 0.25 * _ramp_charge, 0.2, 0.95))
		_ctext(font, by - 8.0 * k, "pop at the lip" if _ramp_charge < 0.95 else "FULL CHARGE", 16, Color(1, 1, 1, 0.8))
	if face_kind != "":
		var fk2 := _hud_scale()
		var pulse := 1.0 + 0.06 * sin(_age * 14.0)
		var py := s.y * 0.12
		_hud.draw_rect(Rect2(0.0, py - 34.0 * fk2, s.x, 156.0 * fk2), Color(0.6, 0.1, 0.45, 0.4))
		_ctext(font, py, face_open, int(24.0 * pulse), Color(1.0, 1.0, 1.0, 0.95))
		var say := String(FACES[face_kind]["say"])
		var sw := font.get_string_size(say, HORIZONTAL_ALIGNMENT_LEFT, -1, int(58.0 * pulse * fk2)).x
		_ctext(font, py + 58.0 * fk2, say, int(58.0 * pulse), Color(1.0, 0.92, 0.3, 1.0))
		_face_big(Vector2(s.x * 0.5, py + 100.0 * fk2 + minf(s.y * 0.17, 120.0 * fk2)), minf(s.y * 0.17, 120.0 * fk2), face_kind)          # the face to copy: big, so it reads at a glance
		var fw := 260.0 * fk2
		var fx := s.x * 0.5 - fw * 0.5
		_hud.draw_rect(Rect2(fx, py + 66.0 * fk2, fw, 10.0 * fk2), Color(0.05, 0.05, 0.1, 0.6))
		_hud.draw_rect(Rect2(fx, py + 66.0 * fk2, fw * clampf(face_t / FACE_WINDOW, 0.0, 1.0), 10.0 * fk2), Color(1.0, 0.8, 0.2, 0.95))
		_hud.draw_rect(Rect2(fx, py + 66.0 * fk2, fw * clampf(face_hold / 0.3, 0.0, 1.0), 10.0 * fk2), Color(0.3, 1.0, 0.5, 0.95))
	if _trk_text_t > 0.0 and _trk_text != "":
		var a := clampf(_trk_text_t / 0.5, 0.0, 1.0)
		var big := _trk_text_t > 0.3 and not _in_air
		var ty := s.y * (0.52 if big else 0.58)
		if _trk_burst_t > 0.0:
			var u := 1.0 - _trk_burst_t / 0.7
			var rad := (150.0 + 90.0 * u) * k
			var c0 := Vector2(s.x * 0.5, ty + 12.0 * k)
			var pts := PackedVector2Array()
			for si in 24:
				var ang := float(si) * TAU / 24.0 + _age * 0.8
				var rr := rad * (1.0 if si % 2 == 0 else 0.62)
				pts.append(c0 + Vector2(cos(ang), sin(ang)) * rr)
			Draw2D.poly(_hud, pts, Color(1.0, 0.45, 0.1, 0.55 * clampf(_trk_burst_t / 0.4, 0.0, 1.0)))
		_ctext(font, ty, _trk_text, 28 if big else 22, Color(1.0, 0.88, 0.35, a * 0.9))
	var mrect2 := _menu_rect()
	_hud.draw_rect(mrect2, Color(0.8, 0.3, 0.3, 0.7) if _menu_arm_t > 0.0 else Color(0.05, 0.12, 0.25, 0.5))
	_text(font, mrect2.position + Vector2(6.0 * k, 21.0 * k), "SURE?" if _menu_arm_t > 0.0 else "MENU", 18, Color(1, 1, 1, 0.9))
	var vr := _view_rect()
	_hud.draw_rect(vr, Color(0.05, 0.12, 0.25, 0.5))
	_text(font, vr.position + Vector2(6.0 * k, 21.0 * k), "1ST" if view_fp else "3RD", 18, Color(1, 1, 1, 0.9))


# --------------------------------------------------------------------------
# Aim: the opening you look at, and keep looking at for a moment, pulls the board through it
# --------------------------------------------------------------------------
func _update_focus(delta: float) -> void:
	var pf0 := Time.get_ticks_usec()
	super._update_focus(delta)
	_menu_arm_t = maxf(_menu_arm_t - delta, 0.0)
	_runlog.tick(self, delta)
	_update_crumbs(delta)
	_update_ribbons()
	_update_aim(delta)
	_update_buff_aim(delta)
	_trace_tick(delta)
	_pf_focus = _pf(_pf_focus, pf0)


## TARGET MARKERS (phones by default, ?beacons on a laptop, ?nobeacons off): see _update_aim.
var beacons: bool = Game.touch_mode
const BEACON_MAX_DIST := 190.0       # markers appear as soon as the barrier does
const BEACON_LEFT := 0.17            # where the outermost markers sit across the screen
const BEACON_RIGHT := 0.83
const GLANCE_WINDOW := 0.35          # seconds
const GLANCE_MOVE := 0.07            # the look must cross this share of the screen within the window to count as a glance
const GLANCE_HOLD := 0.7             # seconds a glance stays "fresh" for changing the choice
var _bc_row: Dictionary = {}
var _bc_xs: Array = []               # marker x in pixels, one per opening, in the order of row["gaps"]
var _cx_hist: Array = []
var _glance_t: float = 0.0


## Where each opening's marker sits across the screen (pixels). Spread evenly while the openings are far and close together; as the barrier nears and the openings themselves
## spread out, each marker slides onto its own opening.
func _beacon_xs(row: Dictionary, vs: Vector2) -> Array:
	var gs: Array = row["gaps"]
	var n := gs.size()
	var real: Array = []
	var lo := 1.0e9
	var hi := -1.0e9
	var seen := 0
	for g in gs:
		var sc := _gap_screen(row, g)
		var rx := (sc["c"] as Vector2).x / maxf(vs.x, 1.0) if not sc.is_empty() else -1.0
		real.append(rx)
		if rx >= 0.0:
			lo = minf(lo, rx)
			hi = maxf(hi, rx)
			seen += 1
	var slot_span := (BEACON_RIGHT - BEACON_LEFT) if n > 1 else 0.0
	var k := 0.0
	if seen == n and n > 1 and slot_span > 0.0:
		k = clampf(((hi - lo) - 0.6 * slot_span) / (0.4 * slot_span), 0.0, 1.0)
	var out: Array = []
	for i in n:
		var rank := 0
		for o in gs:
			if float(o["x"]) < float(gs[i]["x"]):
				rank += 1
		var slot := lerpf(BEACON_LEFT, BEACON_RIGHT, float(rank) / float(n - 1)) if n > 1 else 0.5
		var x := lerpf(slot, float(real[i]), k) if float(real[i]) >= 0.0 else slot
		out.append(x * vs.x)
	return out


## The markers: a ring per opening with a line down to it. The chosen one is filled; the one you are looking toward shows a dwell arc.
func _draw_beacons(s: Vector2, k: float) -> void:
	if not beacons or _bc_row.is_empty() or bool(_bc_row["passed"]) or _paused:
		return
	var gs: Array = _bc_row["gaps"]
	if gs.size() != _bc_xs.size():
		return
	var r := 24.0 * k
	for i in gs.size():
		var g: Dictionary = gs[i]
		var sc := _gap_screen(_bc_row, g)
		var by := s.y * 0.30
		if not sc.is_empty():
			by = minf(by, (sc["c"] as Vector2).y - 70.0 * k)
		var bp := Vector2(float(_bc_xs[i]), maxf(by, 60.0 * k))
		var chosen := is_same(g, _aim)
		var cand := is_same(g, _cand)
		var col := Color(0.45, 1.0, 0.65, 0.95) if chosen else Color(1, 1, 1, 0.75)
		if not sc.is_empty():
			_hud.draw_line(bp + Vector2(0.0, r), sc["c"], Color(col.r, col.g, col.b, 0.55 if chosen else 0.28), (4.0 if chosen else 2.0) * k, true)
		Draw2D.circle(_hud, bp, r + 3.0 * k, Color(0, 0, 0, 0.45))
		if chosen:
			Draw2D.circle(_hud, bp, r * (0.72 + 0.06 * sin(_age * 8.0)), Color(0.45, 1.0, 0.65, 0.9))
		Draw2D.arc(_hud, bp, r, 0.0, TAU, 28, col, (4.5 if chosen else 3.0) * k, true)
		if cand:
			Draw2D.arc(_hud, bp, r * 0.6, -PI * 0.5, -PI * 0.5 + TAU * clampf(_cand_t / AIM_LINGER, 0.0, 1.0), 20, Color(1, 1, 1, 0.9), 4.0 * k)


func _update_aim(delta: float) -> void:
	if _paused:
		return
	var row: Dictionary = {}
	var keys: Array = _rows.keys()
	keys.sort()
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		var dist := spos.z - float(r["z"])
		if dist < AIM_MIN_DIST or dist > (BEACON_MAX_DIST if beacons else AIM_MAX_DIST):
			continue
		row = r
		break
	_bc_row = {}
	if row.is_empty() or not _eye_on or _finished or not aim_enabled or (trace_on and _tr_phase != 3):
		_aim = {}
		_aim_row = {}
		_cand = {}
		_cand_t = 0.0
		_aim_w = move_toward(_aim_w, 0.0, 6.0 * delta)
		return
	if not is_same(_aim_row, row):
		_aim = {}
		_aim_row = {}
	var vs := get_viewport().get_visible_rect().size
	if _aim_cx < 0.0:
		_aim_cx = _cursor_px.x
	_aim_cx = lerpf(_aim_cx, _cursor_px.x, 1.0 - exp(-delta / 0.10))
	var cx := _aim_cx
	var best: Dictionary = {}
	var best_d := 1.0e9
	# has the look just MOVED (a glance), or is it only sitting / drifting? Remembered for a moment, so a choice changes on a glance and never on a slow fade back to the middle.
	_cx_hist.append(Vector2(_age, cx / maxf(vs.x, 1.0)))
	while _cx_hist.size() > 2 and _age - (_cx_hist[1] as Vector2).x > GLANCE_WINDOW:
		_cx_hist.remove_at(0)
	if absf((_cx_hist[_cx_hist.size() - 1] as Vector2).y - (_cx_hist[0] as Vector2).y) > GLANCE_MOVE:
		_glance_t = GLANCE_HOLD
	_glance_t = maxf(_glance_t - delta, 0.0)
	if beacons:
		# TARGET MARKERS: every opening gets a marker, and the markers are spread wide across the screen however close together the openings look in the distance (two openings
		# 30 m apart are under a tenth of the screen apart at 100 m: less than a phone can resolve). You pick by looking toward a marker; the nearest marker to your look wins.
		_bc_row = row
		_bc_xs = _beacon_xs(row, vs)
		var gs: Array = row["gaps"]
		for bi in gs.size():
			var bdd := absf(float(_bc_xs[bi]) - cx)
			if is_same(gs[bi], _aim):
				bdd *= 0.8
			if bdd < best_d:
				best_d = bdd
				best = gs[bi]
		# with nothing chosen yet, a look that sits between two markers chooses neither (the board then takes its own line, as before): it takes a look toward one
		var spacing := (BEACON_RIGHT - BEACON_LEFT) * vs.x / float(maxi(gs.size() - 1, 1))
		best_d = 0.5 if (not _aim.is_empty() or best_d < 0.36 * spacing) else 1.2
		# a choice you have made stays until you glance somewhere else: the look drifting back to the middle on its own does not undo it
		if not _aim.is_empty() and is_same(_aim_row, row) and not is_same(best, _aim) and _glance_t <= 0.0:
			best = _aim
	else:
		for g in row["gaps"]:
			var sc := _gap_screen(row, g)
			if sc.is_empty():
				continue
			var c: Vector2 = sc["c"]
			var tol := maxf(float(sc["hw"]) * 1.15, 0.12 * vs.x * clampf(68.0 / maxf(cam.fov, 40.0), 0.55, 1.0))          # a wider view packs the gates closer together on screen: look more precisely
			var dd := absf(c.x - cx) / tol
			if is_same(g, _aim):
				dd *= 0.85                                           # a little stickiness against jitter, not enough to hold you on the near one
			if dd < best_d:
				best_d = dd
				best = g
		if best_d >= 1.0:
			# no gate under the gaze point: the gate nearest to where you are looking, whichever it is. The far ones stay reachable this way, however small they are on screen, and a gaze that is
			# a bit off or noisy no longer sends you to the outermost gate on one side.
			var zg: Dictionary = {}
			var zgd := 1.0e9
			for g2 in row["gaps"]:
				var zsc := _gap_screen(row, g2)
				if zsc.is_empty():
					continue
				var zdx := absf((zsc["c"] as Vector2).x - cx)
				if zdx < zgd:
					zgd = zdx
					zg = g2
			if not zg.is_empty():
				best = zg
				best_d = 0.9
	if best_d < 1.0:
		if is_same(best, _aim):
			_cand = {}
			_cand_t = 0.0
		elif is_same(best, _cand):
			_cand_t += delta
			if _cand_t >= AIM_LINGER:
				_aim = best
				_aim_row = row
				_cand = {}
				_cand_t = 0.0
		else:
			_cand = best
			_cand_t = 0.0
	else:
		_cand = {}
		_cand_t = 0.0
		if best_d > 1.6:
			_aim = {}
			_aim_row = {}
	if _aim.is_empty():
		_aim_w = move_toward(_aim_w, 0.0, 6.0 * delta)
	else:
		_aim_w = move_toward(_aim_w, 1.0, 4.0 * delta)
		_aim_want = clampf((float(_aim["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)


# --------------------------------------------------------------------------
# Input, pause, report
# --------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _dot_phase == 2 and not _dot_done and _dot_t > 1.0:
		if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventKey and (event as InputEventKey).pressed):
			_check_dismiss()
			get_viewport().set_input_as_handled()
			return
	if _pause_input(event):
		get_viewport().set_input_as_handled()
		return
	if not _paused:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F3:
			show_perf = not show_perf
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_N:
			cycle_preset()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_V:
			_toggle_view()
			get_viewport().set_input_as_handled()
			return
		var vpos := Vector2.INF
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			vpos = (event as InputEventMouseButton).position
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			vpos = (event as InputEventScreenTouch).position
		if vpos.is_finite() and _menu_rect().has_point(vpos):
			if Time.get_ticks_msec() - _view_msec > 300:
				_view_msec = Time.get_ticks_msec()
				if _menu_arm_t > 0.0:
					_return_to_menu()
				else:
					_menu_arm_t = 2.5
			get_viewport().set_input_as_handled()
			return
		if vpos.is_finite() and _view_rect().has_point(vpos):
			if Time.get_ticks_msec() - _view_msec > 300:
				_view_msec = Time.get_ticks_msec()
				_toggle_view()
			get_viewport().set_input_as_handled()
			return
	if not _paused and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var tk := (event as InputEventKey).keycode
		if tk == KEY_T:
			if trace_on:
				_trace_end()
			else:
				_trace_start()
			get_viewport().set_input_as_handled()
			return
		if trace_on and _tr_phase == 4 and tk == KEY_R:
			_trace_start()
			get_viewport().set_input_as_handled()
			return
		if trace_on and _tr_phase == 4 and tk == KEY_C:
			_trace_copy()
			get_viewport().set_input_as_handled()
			return
	if trace_on and _tr_phase == 4 and not _paused and ((event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)):
		_trace_copy()
		get_viewport().set_input_as_handled()
		return
	if _finished and _end_t > 1.2 and not _paused and not trace_on:
		var again := false
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var kc := (event as InputEventKey).keycode
			again = kc == KEY_R or kc == KEY_SPACE or kc == KEY_ENTER
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			again = true
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			again = true
		if again:
			_restart()
			get_viewport().set_input_as_handled()


func _pause_action(id: String) -> void:
	if id == "ctl":
		_copy_note = "carve steers continuously from where you look"
		return
	if id == "trace":
		_paused = false
		_trace_start()
		return
	if id == "diag":
		diag_on = not diag_on
		return
	if id == "eyecheck":
		_paused = false
		_pause_adv = false
		eye_check_start()
		return
	if id == "trace_off":
		_trace_end()
		_copy_note = "trace ended"
		return
	super._pause_action(id)


func _pause_report() -> Dictionary:
	var r := super._pause_report()
	r["carve"] = {"distance": int(-spos.z), "finishAt": int(-finish_z), "speedKmh": int(vel.length() * 3.6), "crashes": crashes, "barriersPassed": _passed_ok,
		"tight": _tight_n, "crashLog": crash_log.slice(maxi(crash_log.size() - 12, 0)), "swerves": swerves, "wrongGates": wrong_gates, "buffs": {"got": buffs_got, "spawned": buffs_spawned, "byType": buff_log, "gotByKind": got_kind, "spawnedByKind": spawned_kind, "orbs": orbs_got, "latched": not _buff_tgt.is_empty(), "pull": snappedf(_buff_w, 0.01)}, "foods": {"bounced": foods_bounced, "lost": foods_lost, "eyeOpenFast": snappedf(GazeProvider.eye_open_fast, 0.01), "squinting": _squinting_now}, "snowballs": {"spawned": snow_spawned, "braced": snow_braced, "hit": snow_hit, "dodged": snow_dodged}, "faces": {"asked": face_done, "seen": face_seen, "cines": cines}, "agency": agency_summary(), "phone": {"active": GazeProvider.pm.active, "shake": snappedf(GazeProvider.pm.shake, 0.01), "lap": snappedf(GazeProvider.pm.lap, 0.01), "removedPct": snappedf(GazeProvider.pm.removed_pct, 0.1), "learned": snappedf(GazeProvider.pm.learned, 0.01), "tiltX": snappedf(GazeProvider.pm.tilt_x, 0.1), "tiltY": snappedf(GazeProvider.pm.tilt_y, 0.1)}, "seed": _run_seed, "preset": PRESET_ORDER[_preset_i], "zone": _cur_zone, "zonesSeen": zones_seen, "region": _region, "regionsSeen": regions_seen, "pads": pads_hit, "pops": pops_done, "epicKickers": epics_built, "tricks": {"ridiculous": ridiculous, "landed": tricks_landed, "score": trick_score, "best": best_trick, "kickers": kickers_built, "view": "1p" if view_fp else "3p"}, "gatePull": snappedf(_wall_w, 0.01), "aimLatched": not _aim.is_empty(), "aimPull": snappedf(_aim_w, 0.01), "runTime": snappedf(_run_t, 0.1), "finished": _finished, "events": _ev}
	if not _tr_res.is_empty():
		r["trace"] = _tr_res
	return r


# --------------------------------------------------------------------------
# HUD: speed, distance, flow, the gaze ring. Nothing else on the snow.
# --------------------------------------------------------------------------
func _draw_hud() -> void:
	var pf0 := Time.get_ticks_usec()
	_draw_hud_inner()
	_pf_hud = _pf(_pf_hud, pf0)


func _draw_pops(font: Font, s: Vector2, k: float) -> void:
	if _pop_a > 0.0:
		var c := _pop_col
		for i in 7:
			_hud.draw_rect(Rect2(Vector2.ZERO, s).grow(-float(i) * 10.0 * k), Color(c.r, c.g, c.b, _pop_a * (0.2 - 0.026 * float(i))), false, 12.0 * k)
	for pp in _hud_pops:
		var p3: Vector3 = pp["p"]
		if _behind(p3):
			continue
		var sc := _unp(p3)
		var u := clampf(float(pp["t"]) / 0.8, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var c2: Color = pp["col"]
		Draw2D.arc(_hud, sc, (14.0 + 120.0 * e) * k, 0.0, TAU, 32, Color(c2.r, c2.g, c2.b, 1.0 - u), 5.0 * k * (1.0 - u) + 1.0)
		for ri in 10:
			var ang := float(ri) * TAU / 10.0 + 0.3
			var d := Vector2(cos(ang), sin(ang))
			_hud.draw_line(sc + d * (20.0 + 90.0 * e) * k, sc + d * (30.0 + 150.0 * e) * k, Color(1.0, 1.0, 0.9, 1.0 - u), 3.0 * k * (1.0 - u) + 1.0)
		_text(font, sc + Vector2(-18.0 * k, (-24.0 - 40.0 * e) * k), String(pp["text"]), 18, Color(c2.r * 0.4 + 0.6, c2.g * 0.4 + 0.6, c2.b * 0.4 + 0.6, 1.0 - u * u))


# --------------------------------------------------------------------------
# The set-up guide: pictures, no sentences. For the first seconds of a run on a phone, five round icons show what the tracker needs: your face at a good size, good light, the phone
# upright, the phone steady, a face it can find. Green is fine; amber pulses and shows which way to move (arrows) so the fix is obvious. If a problem lasts during play, only that
# one icon comes back, small, in the corner. It reads the same flags the diagnostics write down.
# --------------------------------------------------------------------------
const GUIDE_SHOW_S := 14.0
var _guide_ok_t: float = 0.0
var _guide_done: bool = false


func _guide_status() -> Dictionary:
	var st := {"dist": 0.0, "light": 0.0, "angle": 0.0, "steady": 0.0, "face": 0.0}
	if Telemetry.inst == null:
		return st
	var fl: Dictionary = Telemetry.inst.flags
	for code in fl:
		var secs := float(fl[code])
		match String(code):
			"too_far", "too_close":
				st["dist"] = maxf(float(st["dist"]), secs)
			"dark_face", "overexposed_face", "backlit_face", "flat_picture", "side_light", "eye_glare":
				st["light"] = maxf(float(st["light"]), secs)
			"bad_angle", "phone_flat", "squint":
				st["angle"] = maxf(float(st["angle"]), secs)
			"phone_shaking":
				st["steady"] = maxf(float(st["steady"]), secs)
			"no_face", "cam_stalled":
				st["face"] = maxf(float(st["face"]), secs)
	return st


func _guide_icon(id: String, c: Vector2, r: float, bad: bool, k: float) -> void:
	var col := Color(1.0, 0.72, 0.2) if bad else Color(0.4, 0.95, 0.5)
	var pulse := 1.0 + (0.08 * sin(_age * 9.0) if bad else 0.0)
	var rr := r * pulse
	Draw2D.circle(_hud, c, rr + 3.0 * k, Color(0, 0, 0, 0.65))
	Draw2D.circle(_hud, c, rr, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.9))
	Draw2D.arc(_hud, c, rr, 0.0, TAU, 28, col, 3.0 * k)
	var u := rr * 0.5
	match id:
		"dist":
			Draw2D.circle(_hud, c, u * 0.8, col)                                       # a face
			var too_far := GazeProvider.face_size < 0.2
			for sx in [-1.0, 1.0]:
				var tip := c + Vector2(float(sx) * u * (0.9 if too_far else 1.6), 0.0)
				var tail := c + Vector2(float(sx) * u * (1.6 if too_far else 0.9), 0.0)
				if bad:
					_hud.draw_line(tail, tip, Color(1, 1, 1), 2.5 * k)
					_hud.draw_line(tip, tip + Vector2(float(sx) * u * (0.35 if not too_far else -0.35), -u * 0.3), Color(1, 1, 1), 2.5 * k)
					_hud.draw_line(tip, tip + Vector2(float(sx) * u * (0.35 if not too_far else -0.35), u * 0.3), Color(1, 1, 1), 2.5 * k)
		"light":
			Draw2D.circle(_hud, c, u * 0.6, col)                                        # a bulb with rays
			for ri in 8:
				var a := float(ri) * TAU / 8.0
				_hud.draw_line(c + Vector2(cos(a), sin(a)) * u * 0.9, c + Vector2(cos(a), sin(a)) * u * 1.3, col, 2.5 * k)
			if bad:
				_hud.draw_line(c + Vector2(-u * 0.3, 0), c + Vector2(u * 0.3, 0), Color(0.1, 0.1, 0.1), 3.0 * k)
		"angle":
			var tw := u * 1.0
			var th := u * 1.7
			var tl := (0.5 * sin(_age * 3.0) if bad else 0.0)                         # a phone: upright when fine, rocking when it is not
			var pts := PackedVector2Array()
			for cr in [Vector2(-tw, -th), Vector2(tw, -th), Vector2(tw, th), Vector2(-tw, th)]:
				pts.append(c + (cr as Vector2).rotated(tl) * 0.7)
			pts.append(pts[0])
			Draw2D.pline(_hud, pts, col, 3.0 * k)
			Draw2D.circle(_hud, c + Vector2(0, -th * 0.55).rotated(tl) * 0.7, u * 0.12, col)
		"steady":
			var tw2 := u * 0.7
			var th2 := u * 1.3
			var off := Vector2(sin(_age * 22.0) * u * 0.25, 0.0) if bad else Vector2.ZERO
			_hud.draw_rect(Rect2(c - Vector2(tw2, th2) * 0.8 + off, Vector2(tw2, th2) * 1.6), col, false, 3.0 * k)
			if bad:
				for wi in 2:
					Draw2D.arc(_hud, c + Vector2(u * 1.15, 0.0), u * (0.35 + 0.3 * float(wi)), -0.9, 0.9, 8, col, 2.0 * k)
					Draw2D.arc(_hud, c - Vector2(u * 1.15, 0.0), u * (0.35 + 0.3 * float(wi)), PI - 0.9, PI + 0.9, 8, col, 2.0 * k)
		"face":
			Draw2D.arc(_hud, c, u * 1.1, 0.0, TAU, 20, col, 3.0 * k)
			Draw2D.circle(_hud, c + Vector2(-u * 0.4, -u * 0.25), u * 0.14, col)
			Draw2D.circle(_hud, c + Vector2(u * 0.4, -u * 0.25), u * 0.14, col)
			Draw2D.arc(_hud, c + Vector2(0, u * 0.1), u * 0.6, 0.2 * PI, 0.8 * PI, 10, col, 2.5 * k)


## The set-up ring: one picture that says where your face should be and what the light is doing, with no words.
##   the fixed ring      where the face belongs
##   the coloured ring   your face: smaller than the fixed ring = too far, bigger = too close; they match when the distance is right
##   the dot and line    which way your head is turned or tipped: bring the dot to the middle
##   the sun             where troublesome light is: above = behind you, left / right = from that side, on the eyes = glare on glasses, hollow = too dark
## Everything turns green when it is good. `c` centre, `r` radius of the fixed ring. Returns true when nothing needs fixing.
func _draw_positioner(c: Vector2, r: float, k: float, alpha: float) -> bool:
	var P := GazeProvider
	var good := Color(0.4, 0.95, 0.5, alpha)
	var warn := Color(1.0, 0.72, 0.2, alpha)
	var seen := P._camera_fresh() and P.confidence >= 0.3 and P.face_size > 0.05
	Draw2D.circle(_hud, c, r * 1.75, Color(0.03, 0.07, 0.15, 0.6 * alpha))
	Draw2D.arc(_hud, c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.55 * alpha), 2.0 * k, true)
	Draw2D.arc(_hud, c, r * 0.3, 0.0, TAU, 20, Color(1, 1, 1, 0.35 * alpha), 1.5 * k, true)
	if not seen:
		# no face in the picture: a face outline that pulses
		var pu := 0.85 + 0.12 * sin(_age * 6.0)
		Draw2D.arc(_hud, c, r * 0.7 * pu, 0.0, TAU, 28, warn, 3.0 * k, true)
		Draw2D.circle(_hud, c + Vector2(-r * 0.25, -r * 0.15) * pu, r * 0.08, warn)
		Draw2D.circle(_hud, c + Vector2(r * 0.25, -r * 0.15) * pu, r * 0.08, warn)
		Draw2D.arc(_hud, c + Vector2(0, r * 0.05) * pu, r * 0.36 * pu, 0.2 * PI, 0.8 * PI, 10, warn, 2.5 * k)
		return false
	var fs := P.face_size
	var dist_ok := fs >= POS_FACE_MIN and fs <= POS_FACE_MAX
	var fr := r * clampf(fs / POS_FACE_IDEAL, 0.35, 1.7)
	Draw2D.arc(_hud, c, fr, 0.0, TAU, 40, good if dist_ok else warn, 4.0 * k, true)
	var ang_ok := true
	if P.head_rpy_ok:
		var hv := Vector2(-rad_to_deg(P.head_rpy.x), rad_to_deg(P.head_rpy.y)) / POS_ANGLE_DEG
		ang_ok = hv.length() <= 1.0
		var dp := c + hv.limit_length(1.5) * r
		var dcol := good if ang_ok else warn
		_hud.draw_line(c, dp, Color(dcol.r, dcol.g, dcol.b, 0.7 * alpha), 2.5 * k, true)
		Draw2D.circle(_hud, dp, 8.0 * k, Color(0, 0, 0, 0.6 * alpha))
		Draw2D.circle(_hud, dp, 6.0 * k, dcol)
	var li := Telemetry.light_issue(Telemetry.inst._light) if Telemetry.inst != null else ""
	if li != "":
		var sp := c + Vector2(0.0, -r * 1.25)                         # behind you / too bright / too dark / flat: above the ring
		match li:
			"side_l":
				sp = c + Vector2(r * 1.25, 0.0)                          # the left half of the camera picture is your right, and the ring is a mirror
			"side_r":
				sp = c + Vector2(-r * 1.25, 0.0)
			"glare":
				sp = c + Vector2(0.0, -r * 0.3)
		var su := r * (0.2 + 0.02 * sin(_age * 7.0))
		if li == "dark" or li == "flat":
			Draw2D.arc(_hud, sp, su, 0.0, TAU, 16, warn, 2.5 * k, true)
			_hud.draw_line(sp + Vector2(-su, su) * 1.2, sp + Vector2(su, -su) * 1.2, warn, 2.5 * k, true)
		else:
			Draw2D.circle(_hud, sp, su, warn)
			var rays := 1.9 if li == "bright" or li == "glare" else 1.55
			for ri in 8:
				var a := float(ri) * TAU / 8.0 + _age * 0.6
				_hud.draw_line(sp + Vector2(cos(a), sin(a)) * su * 1.25, sp + Vector2(cos(a), sin(a)) * su * rays, warn, 2.5 * k, true)
	return dist_ok and ang_ok and li == ""


const POS_FACE_IDEAL := 0.30         # face width as a share of the camera picture when the distance is right
const POS_FACE_MIN := 0.17
const POS_FACE_MAX := 0.50
const POS_ANGLE_DEG := 20.0          # a head turned or tipped this far puts the dot on the ring
const GUIDE_RAISE_S := 8.0           # seconds a set-up problem must last during play before the ring comes back
var _pos_fade: float = 0.0


func _draw_setup_guide(s: Vector2, k: float, delta_hint: float) -> void:
	if Telemetry.inst != null:
		Telemetry.inst.light_fast = false
	if GazeProvider.backend != GazeProvider.Backend.CAMERA or _paused or _finished:
		return
	if not _guide_done and _age < GUIDE_SHOW_S:
		# the start of a run: the set-up ring, low on the screen (the course stays visible above). It leaves as soon as everything has been fine for two seconds.
		if Telemetry.inst != null:
			Telemetry.inst.light_fast = true
		_pos_fade = minf(_pos_fade + delta_hint * 4.0, 1.0)
		var r0 := 46.0 * k
		var fine := _draw_positioner(Vector2(s.x * 0.5, s.y * 0.76), r0, k, _pos_fade * clampf((GUIDE_SHOW_S - _age) / 0.6, 0.0, 1.0))
		var st0 := _guide_status()
		if float(st0["steady"]) > 0.0:
			_guide_icon("steady", Vector2(s.x * 0.5 + r0 * 2.6, s.y * 0.76), 22.0 * k, true, k)
			fine = false
		_guide_ok_t = _guide_ok_t + delta_hint if fine else 0.0
		if _guide_ok_t > 2.0:
			_guide_done = true
		return
	# during play: nothing, unless the same problem has lasted a good while. Then the ring comes back small in the corner until it is fixed.
	var st := _guide_status()
	var worst := ""
	var worst_t := GUIDE_RAISE_S
	for key2 in st:
		if float(st[key2]) >= worst_t:
			worst_t = float(st[key2])
			worst = String(key2)
	if worst == "steady":
		_guide_icon(worst, Vector2(s.x - 44.0 * k, 78.0 * k), 22.0 * k, true, k)
	elif worst != "":
		if Telemetry.inst != null:
			Telemetry.inst.light_fast = true
		_draw_positioner(Vector2(s.x - 56.0 * k, 96.0 * k), 24.0 * k, k * 0.6, 0.9)


## The six, along the top: a ring for each in its colour. The dim arc is how much has been taken, the bright arc is how much is felt, the number is the level (out of 6). A crash flashes them red.
func _draw_mol_bar(font: Font, k: float, s: Vector2, m: float) -> void:
	if not _mol_seen:
		return
	var gap := 56.0 * k
	var x0 := s.x * 0.5 - gap * 2.5
	var y := m + 70.0 * k
	for i in 6:
		var id: String = MolData.ORDER[i]
		var col: Color = MolData.MOLS[id]["c"]
		var c := Vector2(x0 + gap * float(i), y)
		var lv := _mdose[i] / 6.0
		var felt := _mbody[i] / 6.0
		_hud.draw_circle(c, 18.0 * k, Color(0.0, 0.0, 0.0, 0.5))
		if lv > 0.001:
			Draw2D.arc(_hud, c, 17.0 * k, -PI * 0.5, -PI * 0.5 + TAU * lv, 32, Color(col.r, col.g, col.b, 0.35), 5.0 * k)
		if felt > 0.001:
			Draw2D.arc(_hud, c, 17.0 * k, -PI * 0.5, -PI * 0.5 + TAU * felt, 32, col, 5.0 * k)
		if _mol_hurt_t > 0.0 and i == _mol_hurt_i:
			_hud.draw_circle(c, 19.0 * k, Color(1.0, 0.2, 0.2, 0.6 * _mol_hurt_t))
		var cnt := "%d" % int(floor(_mdose[i] + 0.001))
		_text(font, c + Vector2(-_tw(font, cnt, int(16.0 * k)) * 0.5, 6.0 * k), cnt, 16, Color(1, 1, 1, 0.95 if lv > 0.001 else 0.35))
		var nm := String(MolData.MOLS[id]["name"]).to_upper()
		if nm == "MESCALINE":
			nm = "MESC"
		_text(font, c + Vector2(-_tw(font, nm, int(10.0 * k)) * 0.5, 33.0 * k), nm, 10, Color(col.r, col.g, col.b, 0.85))
	if _dmt_on:
		_text(font, Vector2(s.x * 0.5 - _tw(font, "ALL SIX", int(14.0 * k)) * 0.5, y + 50.0 * k), "ALL SIX", 14, Color(1.0, 0.85, 0.3, 0.7 + 0.3 * sin(_age * 6.0)))


var _diag: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("diag")          # ?diag: the tracking made visible (targets, the gaze point, the readings)


## DIAGNOSTICS (?diag): every thing that can be chosen is ringed where it is on the screen (grey; the one the board is committed to is green and thick), the raw gaze point is a
## cyan cross, and the readings the choice is made from are listed down the left side, so a miss can be told apart: the camera lost you, the gaze was off, or the choice was wrong.
func _draw_track_dbg(font: Font, k: float, s: Vector2, m: float) -> void:
	var gp := Vector2(GazeProvider.gaze.x * s.x, GazeProvider.gaze.y * s.y)
	_hud.draw_line(gp - Vector2(16.0 * k, 0.0), gp + Vector2(16.0 * k, 0.0), Color(0.3, 1.0, 1.0, 0.9), 2.0 * k)
	_hud.draw_line(gp - Vector2(0.0, 16.0 * k), gp + Vector2(0.0, 16.0 * k), Color(0.3, 1.0, 1.0, 0.9), 2.0 * k)
	var n := 0
	var best_d := 1.0e9
	var best_f := ""
	for kk in _rows:
		for f in (_rows[kk] as Dictionary).get("feats", []):
			if f.has("hz") or f["done"]:
				continue
			var fz := float(f["zl"]) if f.has("zl") else float(f["za"])
			if spos.z - fz > 130.0 or spos.z < fz - 260.0:
				continue
			var fx := _feat_x(f, clampf(spos.z, float(f["zb"]), float(f["za"])))
			var wp := Vector3(fx, terrain_h(fx, fz) + 1.5, fz)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			n += 1
			var locked := is_same(f, _line_pick)
			var col := Color(0.4, 1.0, 0.5, 1.0) if locked else Color(1, 1, 1, 0.55)
			_hud.draw_arc(sp, (26.0 if locked else 17.0) * k, 0.0, TAU, 28, col, (4.0 if locked else 2.0) * k)
			_text(font, sp + Vector2(20.0 * k, -8.0 * k), "%s %dm" % [String(f["kind"]), int(spos.z - fz)], 13, col)
			var dg := gp.distance_to(sp)
			if dg < best_d:
				best_d = dg
				best_f = "%s %dm" % [String(f["kind"]), int(spos.z - fz)]
	var lines: Array = [
		"gaze %.2f %.2f   conf %.2f   face %.2f" % [GazeProvider.gaze.x, GazeProvider.gaze.y, GazeProvider.confidence, GazeProvider.face_size],
		"look %s   eyes %s   choices ringed %d" % [["LEFT", "AHEAD", "RIGHT"][int(look_side) + 1], "on" if _eye_on else "off", n],
		"nearest to your gaze: %s (%d px)" % [best_f if best_f != "" else "-", int(best_d) if best_f != "" else 0],
		"locked: %s" % (String(_line_pick["kind"]) if not _line_pick.is_empty() else "-"),
		"cam %.0f fps  %d ms   game %d fps" % [float(GazeProvider._pkt_times.size()) / 2.0, int(GazeProvider.trk_lat_ms), int(Engine.get_frames_per_second())],
	]
	for i in lines.size():
		_text(font, Vector2(m, m + (90.0 + 20.0 * float(i)) * k), String(lines[i]), 15, Color(0.75, 1.0, 1.0, 0.95))


func _draw_hud_inner() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	if _journey != null and _journey.flash > 0.0:
		var jf := _journey.flash
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(_journey.flash_col.r, _journey.flash_col.g, _journey.flash_col.b, jf * 0.30))          # the wash that hides a swap of worlds
	if _portrait_hold:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.09, 0.2, 1.0))
		for pl in [["TURN YOUR PHONE SIDEWAYS", 34, -0.04], ["the camera and your eyes are set up for landscape", 20, 0.04]]:
			var ptxt := String(pl[0])
			var psz := int(float(pl[1]) * k)
			_text(font, Vector2(s.x * 0.5 - font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, psz).x * 0.5, s.y * (0.5 + float(pl[2]))), ptxt, int(pl[1]), Color(1, 1, 1, 0.95))
		return
	if _warming:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.09, 0.2, 1.0))          # a solid screen: the shader warm-up draws test boxes in front of the camera, nobody should see them
		# the short wait at the very start of the first run: a bar, so it reads as getting ready and not as a hang
		var bw0 := minf(s.x * 0.4, 460.0 * k)
		var bp := Vector2(s.x * 0.5 - bw0 * 0.5, s.y * 0.62)
		_text(font, Vector2(s.x * 0.5 - font.get_string_size("GET READY", HORIZONTAL_ALIGNMENT_LEFT, -1, int(34.0 * k)).x * 0.5, bp.y - 26.0 * k), "GET READY", 34, Color(1, 1, 1, 0.95))
		_hud.draw_rect(Rect2(bp, Vector2(bw0, 12.0 * k)), Color(0.05, 0.12, 0.25, 0.6))
		_hud.draw_rect(Rect2(bp, Vector2(bw0 * _warm_k, 12.0 * k)), Color(1.0, 0.85, 0.35, 0.95))
		return
	if _dot_t >= 0.0 and not _dot_done:
		_draw_calib(font, s, k)
		return
	if _nohud:
		return          # ?nohud: nothing on the picture (for screenshots)
	if _sb_on and _sb_close > 0.02:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.15, 0.1, 0.16 * _sb_close * (0.7 + 0.3 * sin(_age * 14.0))))
		var sw := "SNOWBALL BEHIND YOU"
		_text(ThemeDB.fallback_font, Vector2(s.x * 0.5 - 150.0 * _hud_scale(), s.y - 40.0 * _hud_scale()), sw, 22, Color(1.0, 0.85, 0.8, 0.9 * _sb_close))
	if _cue_tint > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(_cue_col.r, _cue_col.g, _cue_col.b, 0.07 * _cue_tint))
	var m := 24.0 * k
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.22 * clampf(hurt_t, 0.0, 1.0)))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, 0.3 * _flash))
	_draw_pops(font, s, k)
	_draw_tricks(font, s, k)
	_draw_eyes_hud(font, s, k)
	# speed lines at the edge of the screen: the faster you go, the more of them
	var sp_f := clampf((vel.length() - 26.0) / 40.0, 0.0, 1.0)
	if sp_f > 0.02:
		var c0 := s * 0.5 + Vector2(0.0, s.y * 0.04)
		var rmax := s.length() * 0.5
		for i in 30:
			var a := float(i) * 2.399963 + floorf(_age * 3.0 + float(i) * 0.37) * 1.3
			var f := fposmod(_age * (1.3 + 0.07 * float(i % 5)) + float(i) * 0.173, 1.0)
			var r0 := lerpf(0.42, 0.95, f) * rmax
			var r1 := r0 + (0.03 + 0.12 * f) * rmax * (0.5 + sp_f)
			var dir := Vector2(cos(a), sin(a))
			_hud.draw_line(c0 + dir * r0, c0 + dir * r1, Color(1.0, 1.0, 1.0, 0.22 * sp_f * f), 2.0 * k)
	if trail:
		var np := _next_pole()
		if not np.is_empty() and spos.z - float(np["z"]) < 140.0:
			var pw := Vector3(float(np["x"]), terrain_h(float(np["x"]), float(np["z"])) + 6.6, float(np["z"]))
			if not _behind(pw):
				var pc := _unp(pw)
				var pe := float(np["e"])
				var bob := sin(_age * 8.0) * 4.0 * k
				var a0 := pc + Vector2(pe * (14.0 * k + bob), 0.0)
				Draw2D.poly(_hud, PackedVector2Array([a0 + Vector2(0.0, -12.0 * k), a0 + Vector2(0.0, 12.0 * k), a0 + Vector2(pe * 20.0 * k, 0.0)]), Color(1.0, 0.9, 0.2, 0.95))          # pass on this side
		# what is coming up on the trail: both things at a choice are named. The one your look has chosen gets a ring and an arrow, the other fades.
		for fk in _rows:
			for ff in (_rows[fk] as Dictionary).get("feats", []):
				var fzl := float(ff.get("zl", ff["za"]))
				var fdz := spos.z - fzl
				if ff["done"] or fdz > 130.0 or fdz < 4.0:
					continue
				var fx0 := _feat_x(ff, fzl)
				var fw := Vector3(fx0, terrain_h(fx0, fzl) + 6.0, fzl)
				if _behind(fw):
					continue
				var fs := _unp(fw)
				var chosen := is_same(ff, _line_pick)
				var other := not _line_pick.is_empty() and not chosen and int(ff.get("g", -1)) == int(_line_pick.get("g", -2))
				var fa := clampf((130.0 - fdz) / 30.0, 0.0, 1.0) * (0.3 if other else 0.95)
				var fcl := Color(0.5, 0.95, 1.0, fa) if ff["kind"] == "rail" else (Color(1.0, 0.7, 0.25, fa) if ff["kind"] == "jump" else (Color(1.0, 0.35, 0.3, fa) if ff.has("hz") else Color(1.0, 0.55, 0.9, fa)))
				if not ff.has("hz"):
					# the ring sits on the thing itself: it grows as the board closes in, fills while a look is settling on it, and turns green when it is locked
					var rr := clampf(2300.0 / maxf(fdz, 28.0), 16.0, 80.0) * k
					var rc := fs + Vector2(0.0, rr * 0.9)
					var rfill := 1.0 if chosen else clampf(float(ff["want"]) / 0.18, 0.0, 1.0)
					var rcol := Color(0.5, 1.0, 0.65, 0.95) if chosen else Color(fcl.r, fcl.g, fcl.b, fa * 0.75)
					Draw2D.arc(_hud, rc, rr, 0.0, TAU, 32, Color(1, 1, 1, 0.22 * fa), 2.0 * k)
					if rfill > 0.0:
						Draw2D.arc(_hud, rc, rr, -PI * 0.5, -PI * 0.5 + TAU * rfill, 32, rcol, (6.0 if chosen else 4.0) * k)
				if chosen:
					var bob2 := sin(_age * 8.0) * 3.0 * k
					Draw2D.poly(_hud, PackedVector2Array([fs + Vector2(-11.0 * k, 10.0 * k + bob2), fs + Vector2(11.0 * k, 10.0 * k + bob2), fs + Vector2(0.0, 26.0 * k + bob2)]), Color(0.5, 1.0, 0.7, 0.95))
					pass
				else:
					pass
		# HOW THE GAME READS YOUR LOOK, live: a dot on a short bar. When it is far enough to a side to choose something, that half lights up. If the dot does not follow
		# your eyes, the tracking is not working; if it does and the board goes to what you chose, it is.
		if not _finished:
			_draw_cards(font, s, k)
		if diag_on and not _finished:
			_draw_diag(font, s, k)
		elif not _finished and false:
			var lv := pick_override if pick_override != 0.0 else _s_in_now
			var lw := 170.0 * k
			var lc0 := Vector2(s.x * 0.5, s.y * 0.8)
			_hud.draw_rect(Rect2(lc0.x - lw, lc0.y - 3.0 * k, lw * 2.0, 6.0 * k), Color(0.05, 0.1, 0.2, 0.45))
			if look_side != 0.0:
				_hud.draw_rect(Rect2(lc0.x if look_side > 0.0 else lc0.x - lw, lc0.y - 3.0 * k, lw, 6.0 * k), Color(0.5, 1.0, 0.7, 0.75))
			_hud.draw_rect(Rect2(lc0.x - 1.5 * k, lc0.y - 9.0 * k, 3.0 * k, 18.0 * k), Color(1, 1, 1, 0.6))
			Draw2D.circle(_hud, lc0 + Vector2(clampf(lv / 0.5, -1.0, 1.0) * lw, 0.0), 9.0 * k, Color(1.0, 0.9, 0.4, 0.95) if _eye_on or pick_override != 0.0 else Color(1, 1, 1, 0.5))
			_text(font, Vector2(lc0.x - lw - 20.0 * k, lc0.y + 6.0 * k), "L", 15, Color(1, 1, 1, 0.9 if look_side < 0.0 else 0.4))
			_text(font, Vector2(lc0.x + lw + 10.0 * k, lc0.y + 6.0 * k), "R", 15, Color(1, 1, 1, 0.9 if look_side > 0.0 else 0.4))
	_draw_beacons(s, k)
	_draw_called(k)
	# the opening you have latched: two soft posts at its edges
	if not _aim.is_empty() and not _aim_row.is_empty():
		var asc := _gap_screen(_aim_row, _aim)
		if not asc.is_empty():
			var ac: Vector2 = asc["c"]
			var ahw: float = asc["hw"]
			var aa := 0.35 + 0.5 * _aim_w
			for sx in [-1.0, 1.0]:
				_hud.draw_line(ac + Vector2(float(sx) * ahw, -64.0 * k), ac + Vector2(float(sx) * ahw, 14.0 * k), Color(0.45, 1.0, 0.65, aa), 4.0 * k)
	if not _cand.is_empty():
		for kk in _rows:
			var rr: Dictionary = _rows[kk]
			if not rr["has_row"] or rr["passed"]:
				continue
			for gg in rr["gaps"]:
				if is_same(gg, _cand):
					var csc := _gap_screen(rr, gg)
					if not csc.is_empty():
						var cc: Vector2 = csc["c"]
						Draw2D.arc(_hud, cc, 16.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_cand_t / AIM_LINGER, 0.0, 1.0), 24, Color(1.0, 1.0, 1.0, 0.85), 3.5 * k)
	# the buff you are looking at: a dwell arc while it is being picked, a ring once it has you
	for bb in [_buff_cand, _buff_tgt]:
		var bd2: Dictionary = bb
		if bd2.is_empty() or bd2["taken"]:
			continue
		var bp := Vector3(float(bd2["x"]), terrain_h(float(bd2["x"]), float(bd2["z"])) + 2.4, float(bd2["z"]))
		if _behind(bp):
			continue
		var bs := _unp(bp)
		var bcol: Color = BUFF_COL[bd2["t"]]
		if is_same(bd2, _buff_tgt):
			Draw2D.arc(_hud, bs, 22.0 * k, 0.0, TAU, 28, Color(bcol.r, bcol.g, bcol.b, 0.35 + 0.5 * _buff_w), 4.0 * k)
		else:
			Draw2D.arc(_hud, bs, 22.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_buff_cand_t / AIM_LINGER, 0.0, 1.0), 24, Color(1.0, 1.0, 1.0, 0.85), 3.5 * k)
	# gaze reticle: hidden in play (it jitters and draws the eye away from the course; the latched opening already shows what the game understood). ?reticle shows it.
	if _eye_on and not _paused and show_reticle:
		var cur_px := _cursor_px if _cursor_px != Vector2.ZERO else _gaze_px
		for ti in _gaze_trail.size():
			var ta := float(ti + 1) / float(_gaze_trail.size() + 1)
			Draw2D.circle(_hud, _gaze_trail[ti], 5.0 * k * ta, Color(1.0, 0.6, 0.1, 0.35 * ta))
		Draw2D.circle(_hud, cur_px, 15.0 * k, Color(1.0, 0.6, 0.1, 0.18))
		Draw2D.arc(_hud, cur_px, 15.0 * k, 0.0, TAU, 24, Color(1.0, 0.6, 0.1, 0.95), 3.5 * k)
		Draw2D.circle(_hud, cur_px, 4.5 * k, Color(1.0, 0.6, 0.1, 0.95))
	# progress bar (top centre), score (top left), eyes status (top right)
	var bw := minf(s.x * 0.34, 420.0 * k)
	var bx := s.x * 0.5 - bw * 0.5
	_hud.draw_rect(Rect2(bx, 6.0 * k, bw, 4.0 * k), Color(0.05, 0.12, 0.25, 0.35))
	_hud.draw_rect(Rect2(bx, 6.0 * k, bw * progress(), 4.0 * k), Color(1.0, 0.85, 0.3, 0.8))
	if trail and mode == "race":
		_text(font, Vector2(m, m + 22.0 * k), clock_text(_run_t), 26, Color(1, 1, 1, 0.95))
		if time_pen != 0.0:
			_text(font, Vector2(m + 96.0 * k, m + 22.0 * k), "%+d s" % int(time_pen), 18, Color(1.0, 0.5, 0.4, 0.95) if time_pen > 0.0 else Color(0.5, 1.0, 0.6, 0.95))
	else:
		_text(font, Vector2(m, m + 22.0 * k), "%d" % score, 26, Color(1, 1, 1, 0.95))
	if not HUD_MIN:
		_draw_chain(s, k, m)
	if glints > 0 and not HUD_MIN:
		var gdc := Vector2(m + 9.0 * k, m + 47.0 * k)
		Draw2D.poly(_hud, PackedVector2Array([gdc + Vector2(0, -9.0 * k), gdc + Vector2(8.0 * k, 0), gdc + Vector2(0, 9.0 * k), gdc + Vector2(-8.0 * k, 0)]), Color(1.0, 0.82, 0.25, 0.95))
		_text(font, Vector2(m + 24.0 * k, m + 54.0 * k), "%d" % glints, 22, Color(1.0, 0.9, 0.5, 0.95))
	if trail and not _finished:
		pass          # the goals list is off the screen (they are still counted)
	_draw_setup_guide(s, k, get_process_delta_time())
	var by := m + 84.0 * k
	if _boost_t > 0.0 and not HUD_MIN:
		_text(font, Vector2(m, by), "BOOST %.1f" % _boost_t, 15, BUFF_COL["boost"])
		by += 20.0 * k
	if _mult_t > 0.0 and not HUD_MIN:
		_text(font, Vector2(m, by), "x2 POINTS %.1f" % _mult_t, 15, BUFF_COL["mult"])
		by += 20.0 * k
	if shield > 0:
		_text(font, Vector2(m, by), "SHIELD", 15, BUFF_COL["shield"])
	var eye_txt := "EYES OFF"
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		eye_txt = "EYES"
	elif GazeProvider.backend == GazeProvider.Backend.MOUSE and not Game.touch_mode:
		eye_txt = "MOUSE EYES"
	var ecol := Color(0.5, 1.0, 0.6) if _eye_on else Color(1, 1, 1, 0.55)
	var ew := font.get_string_size(eye_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14.0 * k)).x
	if show_perf:
		var lt: Node = get_parent().get_node_or_null("Lighting") if get_parent() != null else null
		var qt := (lt as DhLighting).tier if lt != null else 0
		var gf := int(Engine.get_frames_per_second())
		var tf := float(GazeProvider._pkt_times.size()) / 2.0
		var pt := "%d km/h     GAME %d fps" % [int(-vel.y * 3.6), gf]
		if GazeProvider.backend == GazeProvider.Backend.CAMERA:
			pt += "   CAM %.0f fps  %d ms" % [tf, int(GazeProvider.trk_lat_ms)]
		pt += "   Q%d" % qt
		pt += "   SND %d %s" % [AudioHooks.played, DhMusic.dbg if DhMusic.dbg != "" else "-"]
		var pcol := Color(0.6, 1.0, 0.6) if gf >= 50 and (GazeProvider.backend != GazeProvider.Backend.CAMERA or tf >= 12.0) else (Color(1.0, 0.85, 0.3) if gf >= 35 else Color(1.0, 0.4, 0.35))
		var pw := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * k)).x
		_text(font, Vector2(s.x * 0.5 - pw * 0.5, m + 66.0 * k), pt, 18, pcol)
	_draw_mol_bar(font, k, s, m)
	if _diag:
		_draw_track_dbg(font, k, s, m)
	if chain > 0 and not HUD_MIN:
		# FLOW: the multiplier, big, with its clock underneath. The bar is what you watch: it empties in a few seconds and anything you do refills it.
		var fsz := 26 + int(8.0 * _flow_bump)
		var fcol := Color(1.0, 0.85, 0.3, 0.95).lerp(Color(1, 1, 1, 1), _flow_bump)
		var fy := s.y - m - 84.0 * k
		_text(font, Vector2(m, fy), "FLOW x%.1f" % groove, fsz, fcol)
		var fw := 150.0 * k
		var left := clampf(_flow_t / maxf(_flow_window, 0.1), 0.0, 1.0)
		var low := left < 0.3
		_hud.draw_rect(Rect2(m, fy + 8.0 * k, fw, 9.0 * k), Color(0.05, 0.1, 0.2, 0.6))
		_hud.draw_rect(Rect2(m, fy + 8.0 * k, fw * left, 9.0 * k), Color(1.0, 0.35, 0.25, 0.95) if (low and int(_age * 8.0) % 2 == 0) else Color(1.0, 0.85, 0.3, 0.95))
	if _brow_hint_t > 0.0:
		# the one hint for the pop: an eyebrow icon and an up arrow, low in the middle
		var hc := Vector2(s.x * 0.5, s.y * 0.7)
		var ha := clampf(_brow_hint_t, 0.0, 1.0)
		var hcol := Color(1, 1, 1, 0.9 * ha)
		var lift := (sin(_age * 6.0) * 0.5 + 0.5) * 7.0 * k
		for hs in [-1.0, 1.0]:
			Draw2D.arc(_hud, hc + Vector2(float(hs) * 20.0 * k, 6.0 * k), 9.0 * k, 0.0, TAU, 16, hcol, 2.5 * k, true)                                   # eyes
			Draw2D.arc(_hud, hc + Vector2(float(hs) * 20.0 * k, -2.0 * k - lift), 15.0 * k, PI * 1.2, PI * 1.8, 10, Color(1.0, 0.85, 0.3, ha), 4.0 * k, true)   # eyebrows, going up
		var at := hc + Vector2(58.0 * k, -8.0 * k - lift)
		Draw2D.poly(_hud, PackedVector2Array([at + Vector2(-9.0 * k, 8.0 * k), at + Vector2(9.0 * k, 8.0 * k), at + Vector2(0.0, -8.0 * k)]), Color(1.0, 0.85, 0.3, ha))
		_text(font, Vector2(hc.x - font.get_string_size("POP", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * k)).x * 0.5, hc.y + 44.0 * k), "POP", 18, hcol)
	var dtxt := "%d m" % int(maxf(-spos.z, 0.0))
	var dw := font.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * k)).x
	var ty := s.y * 0.40
	var ay := s.y - m - 54.0 * k
	for t in _toasts:
		var a2 := clampf(float(t["t"]) / 0.5, 0.0, 1.0)
		var col2: Color = t["color"]
		col2.a = a2
		var tk := String(t.get("kind", "info"))
		if tk == "face":
			_ctext(font, s.y * 0.32, String(t["text"]), 44, col2)             # a face you pulled: the one thing that is loud
		elif tk == "ach":
			_text(font, Vector2(m, ay), String(t["text"]), 15, Color(col2.r, col2.g, col2.b, a2 * 0.8))
			ay -= 20.0 * k
		elif a2 > 0.0 and face_kind == "":
			_ctext(font, ty, String(t["text"]), 20, Color(col2.r, col2.g, col2.b, a2 * 0.85))
			ty += 26.0 * k
	if _finished:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.55))
		_ctext(font, s.y * 0.34, "FINISH", 64, Color(1.0, 0.9, 0.4))
		if trail:
			var race := mode == "race"
			var mine := clock_text(_run_t + time_pen) if race else "%d" % score
			_ctext(font, s.y * 0.34 + 56.0 * k, ("RACE   %s" if race else "FREESTYLE   %s points") % mine, 34, Color(1, 1, 1))
			var sub := ""
			if new_best:
				sub = "NEW BEST!"
			elif best_val > 0.0:
				sub = "best %s" % (clock_text(best_val) if race else "%d" % int(best_val))
			if race and time_pen != 0.0:
				sub += "   (%+d s from poles and goals)" % int(time_pen)
			if sub != "":
				_ctext(font, s.y * 0.34 + 96.0 * k, sub, 24, Color(0.5, 1.0, 0.6) if new_best else Color(1, 1, 1, 0.8))
			_ctext(font, s.y * 0.34 + 126.0 * k, "goals %d/%d   poles %d (shaved %d)   rails %d   jumps %d   best flow x%.1f   crashes %d" % [goals_done, goals.size(), poles_clean, poles_shaved, rails_done, jumps_done, best_flow, crashes], 18, Color(1, 1, 1, 0.75))
			if not race:
				_ctext(font, s.y * 0.34 + 150.0 * k, "time %s" % clock_text(_run_t), 16, Color(1, 1, 1, 0.55))
			if choice_summary() != "":
				_ctext(font, s.y * 0.34 + 214.0 * k, choice_summary(), 16, Color(0.6, 0.95, 1.0, 0.9))
		else:
			_ctext(font, s.y * 0.34 + 56.0 * k, "time %.1f s   crashes %d   score %d" % [_run_t, crashes, score], 30, Color(1, 1, 1))
			if crashes == 0:
				_ctext(font, s.y * 0.34 + 98.0 * k, "CLEAN RUN +1000", 28, Color(0.5, 1.0, 0.6))
		if _end_t > 1.2:
			_ctext(font, s.y * 0.34 + 184.0 * k, "press R, SPACE or tap to ride again", 22, Color(1, 1, 1, 0.85))
	if not _paused:
		var pr := _pause_rect()
		_hud.draw_rect(pr, Color(0.05, 0.12, 0.25, 0.5))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.32, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.56, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
	else:
		_draw_pause(font, s, k)
	if _coach_t > 0.0 and _coach_text != "":
		var ca := clampf(_coach_t / 0.6, 0.0, 1.0)
		var ccol := Color(0.5, 1.0, 0.6, ca) if _coach_good else Color(1.0, 0.85, 0.4, ca)
		ccol.a *= 0.75
		_ctext(font, s.y - m - 8.0 * k, _coach_text, 15, ccol)
	var cmsg := GazeProvider.camera_message()
	if String(cmsg["text"]) != "" and _coach_t <= 0.0 and (_age < 12.0 or not GazeProvider._camera_fresh()):
		var cc3: Color = cmsg["color"]
		cc3.a *= 0.75
		_ctext(font, s.y - m - 8.0 * k, String(cmsg["text"]), 15, cc3)
	if trace_on and not _paused:
		_draw_trace(font, s, k)


# --------------------------------------------------------------------------
# TRACE test: follow a highlighted dot with your eyes while the game measures how well the tracking keeps up.
# Start it from Pause -> TRACE TEST, with the T key, or by opening the page with &trace=1.
#   1 FOLLOW: the dot sweeps back and forth, faster and faster (smooth following: scale, lag, wobble)
#   2 JUMP:   the dot jumps to a new spot every 2 s (glance reaction, where you land, how steady you hold)
#   3 DOWNHILL:  the real game, steering with your eyes along a highlighted line (how far off the line, the steering lag)
# The board drives itself in 1 and 2, so all you have to do is look.
# --------------------------------------------------------------------------
const TR_INTRO := 3.0
const TR_PURSUIT := 24.0
const TR_JUMPS := 22.0
const TR_JUMP_HOLD := 2.0
const TR_CARVE := 40.0
const TR_HZ := 30.0

var trace_on: bool = false
var _tr_phase: int = -1                 # 0 intro, 1 follow, 2 jump, 3 carve, 4 results
var _tr_t: float = 0.0
var _tr_acc: float = 0.0
var _tr_bead: Vector2 = Vector2(0.5, 0.46)   # the dot, as fractions of the screen
var _tr_samp: Array = [[], [], [], []]       # by phase; each: PackedFloat32Array(t, dot x, dot y, gaze x, gaze y, metres off the line, steer, steer needed)
var _tr_jx: Array = []
var _tr_jy: Array = []
var _tr_res: Dictionary = {}
var _tr_lines: Array = []
var _tr_rng := RandomNumberGenerator.new()
var _tr_crash0: int = 0
var _tr_pass0: int = 0
var _tr_total: int = 0
var _tr_miss: int = 0
var _tr_auto: bool = false
var _tr_note: String = ""


func _trace_start() -> void:
	trace_on = true
	_restart()
	_tr_samp = [[], [], [], []]
	_tr_res = {}
	_tr_lines = []
	_tr_total = 0
	_tr_miss = 0
	_tr_note = ""
	_tr_rng.seed = 7777
	_paused = false
	_trace_phase(0)


func _trace_end() -> void:
	if not trace_on:
		return
	trace_on = false
	_tr_phase = -1
	autopilot = false
	_restart()


func _trace_phase(p: int) -> void:
	_tr_phase = p
	_tr_t = 0.0
	_tr_acc = 0.0
	autopilot = p != 3
	if p == 2:
		_tr_jx.clear()
		_tr_jy.clear()
		var prev := 0.5
		for i in int(TR_JUMPS / TR_JUMP_HOLD):
			var nx := prev
			var tries := 0
			while absf(nx - prev) < 0.28 and tries < 40:
				nx = _tr_rng.randf_range(0.12, 0.88)
				tries += 1
			_tr_jx.append(nx)
			_tr_jy.append(_tr_rng.randf_range(0.30, 0.58))
			prev = nx
	elif p == 3:
		_tr_crash0 = crashes
		_tr_pass0 = _passed_ok
	elif p == 4:
		_trace_finish()


## Where the dot is during FOLLOW: a sweep that speeds up from 0.08 to 0.4 swings a second.
func _tr_pursuit_pos(t: float) -> Vector2:
	var ph := TAU * (0.08 * t + (0.40 - 0.08) * t * t / (2.0 * TR_PURSUIT))
	return Vector2(0.5 + 0.30 * sin(ph), 0.46 + 0.04 * sin(t * 0.9))


## The safe line at a height z: toward the nearest barrier at or beyond z.
func _safe_x_at(z: float) -> float:
	var keys: Array = _rows.keys()
	keys.sort()
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"] or r["passed"]:
			continue
		if float(r["z"]) <= z + 0.001:
			return path_x(r, z)
	return 0.0


func _tr_world_px(x: float, z: float, up: float) -> Vector2:
	var wp := Vector3(x, terrain_h(x, z) + up, z)
	if _behind(wp):
		return Vector2(-9999.0, -9999.0)
	return _unp(wp)


func _trace_tick(delta: float) -> void:
	if _tr_auto and _age > 1.5 and not _paused:
		_tr_auto = false
		_trace_start()
		return
	if not trace_on or _paused or _tr_phase < 0 or _tr_phase >= 4:
		return
	_tr_t += delta
	var vs := get_viewport().get_visible_rect().size
	match _tr_phase:
		0:
			_tr_bead = Vector2(0.5, 0.46)
			if _tr_t >= TR_INTRO:
				_trace_phase(1)
		1:
			_tr_bead = _tr_pursuit_pos(_tr_t)
			if _tr_t >= TR_PURSUIT:
				_trace_phase(2)
		2:
			var i := mini(int(_tr_t / TR_JUMP_HOLD), _tr_jx.size() - 1)
			_tr_bead = Vector2(float(_tr_jx[i]), float(_tr_jy[i]))
			if _tr_t >= TR_JUMPS:
				_trace_phase(3)
		3:
			var zt := spos.z - 38.0
			var sp := _tr_world_px(_safe_x_at(zt), zt, 0.5)
			if sp.x > -9000.0:
				_tr_bead = Vector2(clampf(sp.x / vs.x, 0.02, 0.98), clampf(sp.y / vs.y, 0.05, 0.95))
			if _tr_t >= TR_CARVE or _finished:
				_trace_phase(4)
	if _tr_phase < 1 or _tr_phase > 3:
		return
	_tr_acc += delta
	while _tr_acc >= 1.0 / TR_HZ:
		_tr_acc -= 1.0 / TR_HZ
		_tr_record(vs)


func _tr_record(vs: Vector2) -> void:
	_tr_total += 1
	if not _eye_on or _cursor_px == Vector2.ZERO or GazeProvider.confidence < 0.5:
		_tr_miss += 1
		return
	var off := 0.0
	var need := 0.0
	if _tr_phase == 3:
		off = spos.x - _safe_x_at(spos.z)
		need = _auto_steer()
	var raw := -1.0
	if not GazeProvider._limb_buf.is_empty():
		raw = (GazeProvider._limb_buf.back() as Vector2).x       # the iris-in-eye reading as it came from the camera, before any smoothing
	# 9 head yaw (rad), 10 screen-gaze x from the face geometry, 11 smoothed iris-in-eye x: candidate signals, all fitted against the dot afterwards
	(_tr_samp[_tr_phase] as Array).append(PackedFloat32Array([_tr_t, _tr_bead.x, _tr_bead.y, _cursor_px.x / vs.x, _cursor_px.y / vs.y, off, steer, need, raw, GazeProvider.head_rpy.x, GazeProvider.direct.x, GazeProvider.eih.x]))


## Least squares of column ycol on the columns xcols (shifted `lag` samples later). Columns are standardised first. Returns the fit error as a
## spread in the units of ycol (screen fraction) and the correlation of the fit with the dot.
func _tr_ols(s: Array, ycol: int, xcols: Array, lag: int) -> Dictionary:
	var k := xcols.size()
	var rows: Array = []
	for i in s.size():
		var j := i + lag
		if j < 0 or j >= s.size():
			continue
		var r: Array = [(s[i] as PackedFloat32Array)[ycol]]
		for c in xcols:
			r.append((s[j] as PackedFloat32Array)[int(c)])
		rows.append(r)
	var n := rows.size()
	if n < 40:
		return {"r": -2.0, "err": 1.0}
	var mu: Array = []
	var sd: Array = []
	for c in k + 1:
		var m := 0.0
		for r in rows:
			m += float(r[c])
		m /= float(n)
		var v := 0.0
		for r in rows:
			v += (float(r[c]) - m) * (float(r[c]) - m)
		mu.append(m)
		sd.append(maxf(sqrt(v / float(n)), 1.0e-9))
	var A: Array = []
	var b: Array = []
	for a in k:
		A.append([])
		for c in k:
			(A[a] as Array).append(0.0)
		b.append(0.0)
	for r in rows:
		for a in k:
			var xa := (float(r[a + 1]) - float(mu[a + 1])) / float(sd[a + 1])
			b[a] += xa * (float(r[0]) - float(mu[0]))
			for c in k:
				A[a][c] += xa * (float(r[c + 1]) - float(mu[c + 1])) / float(sd[c + 1])
	for a in k:
		A[a][a] += 1.0e-6 * float(n)
	for c in k:
		var p := c
		for r2 in range(c + 1, k):
			if absf(A[r2][c]) > absf(A[p][c]):
				p = r2
		var tmp = A[c]
		A[c] = A[p]
		A[p] = tmp
		var tb = b[c]
		b[c] = b[p]
		b[p] = tb
		for r2 in range(c + 1, k):
			var f: float = A[r2][c] / A[c][c]
			for cc in range(c, k):
				A[r2][cc] -= f * A[c][cc]
			b[r2] -= f * b[c]
	var w: Array = []
	w.resize(k)
	for c in range(k - 1, -1, -1):
		var acc: float = b[c]
		for cc in range(c + 1, k):
			acc -= float(A[c][cc]) * float(w[cc])
		w[c] = acc / A[c][c]
	var sse := 0.0
	for r in rows:
		var pred := 0.0
		for a in k:
			pred += float(w[a]) * (float(r[a + 1]) - float(mu[a + 1])) / float(sd[a + 1])
		var e := float(r[0]) - float(mu[0]) - pred
		sse += e * e
	var vy := float(sd[0]) * float(sd[0])
	var ev := sse / float(n)
	return {"r": sqrt(maxf(1.0 - ev / vy, 0.0)), "err": sqrt(ev)}


## Every candidate signal (and the useful combinations) fitted against the dot over the follow and jump phases, each at its own best delay.
func _tr_signals() -> Dictionary:
	var s: Array = (_tr_samp[1] as Array) + (_tr_samp[2] as Array)
	var cands := {"iris": [8], "irisSmooth": [11], "screenGaze": [10], "head": [9], "iris+head": [8, 9], "screen+head": [10, 9], "all": [8, 9, 10]}
	var out := {}
	for nm in cands:
		var best: Dictionary = {"r": -2.0, "err": 1.0}
		var bl := 0
		for lag in range(-3, 31, 2):
			var f := _tr_ols(s, 1, cands[nm], lag)
			if float(f["r"]) > float(best["r"]):
				best = f
				bl = lag
		out[nm] = {"r": snappedf(float(best["r"]), 0.01), "errPct": snappedf(float(best["err"]) * 100.0, 0.1), "lagMs": int(roundf(float(bl) * 1000.0 / TR_HZ))}
	var hy := PackedFloat32Array()
	for e in s:
		hy.append(rad_to_deg((e as PackedFloat32Array)[9]))
	out["headYawStdDeg"] = snappedf(_tr_std(hy), 0.1) if hy.size() > 3 else -1.0
	return out


# ---- analysis
## Fit of series ci against series bi with ci shifted `lag` samples later: Pearson r, slope, intercept, residual spread.
func _tr_lagfit(s: Array, i0: int, i1: int, bi: int, ci: int, lag: int) -> Dictionary:
	var n := 0
	var sb := 0.0
	var sc := 0.0
	var sbb := 0.0
	var scc := 0.0
	var sbc := 0.0
	for i in range(i0, mini(i1, s.size())):
		var j := i + lag
		if j < 0 or j >= s.size():
			continue
		var b: float = (s[i] as PackedFloat32Array)[bi]
		var c: float = (s[j] as PackedFloat32Array)[ci]
		n += 1
		sb += b
		sc += c
		sbb += b * b
		scc += c * c
		sbc += b * c
	if n < 20:
		return {"n": n, "r": -2.0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var fn := float(n)
	var mb := sb / fn
	var mc := sc / fn
	var vb := sbb / fn - mb * mb
	var vc := scc / fn - mc * mc
	var cv := sbc / fn - mb * mc
	if vb < 1.0e-9 or vc < 1.0e-12:
		return {"n": n, "r": -2.0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var slope := cv / vb
	return {"n": n, "r": cv / sqrt(vb * vc), "slope": slope, "icpt": mc - slope * mb, "resid": sqrt(maxf(vc - slope * slope * vb, 0.0))}


func _tr_best(s: Array, i0: int, i1: int, bi: int, ci: int) -> Dictionary:
	var best: Dictionary = {"r": -2.0, "n": 0, "slope": 1.0, "icpt": 0.0, "resid": 0.0}
	var bl := 0
	for lag in range(-3, 31):
		var f := _tr_lagfit(s, i0, i1, bi, ci, lag)
		if float(f["r"]) > float(best["r"]):
			best = f
			bl = lag
	best["lagMs"] = int(roundf(float(bl) * 1000.0 / TR_HZ))
	return best


func _tr_win(s: Array, ta: float, tb: float, ci: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in s:
		var t: float = (e as PackedFloat32Array)[0]
		if t >= ta and t < tb:
			out.append((e as PackedFloat32Array)[ci])
	return out


func _tr_mean(a: PackedFloat32Array) -> float:
	if a.size() < 3:
		return NAN
	var m := 0.0
	for v in a:
		m += v
	return m / float(a.size())


func _tr_std(a: PackedFloat32Array) -> float:
	var m := _tr_mean(a)
	if is_nan(m):
		return NAN
	var q := 0.0
	for v in a:
		q += (v - m) * (v - m)
	return sqrt(q / float(a.size()))


func _tr_median(a: Array) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _tr_jump_stats() -> Dictionary:
	var s: Array = _tr_samp[2]
	var t50s: Array = []
	var errs: Array = []
	var overs: Array = []
	var jit: Array = []
	var missed := 0
	var prev_x := 0.5
	for k in _tr_jx.size():
		var t0 := float(k) * TR_JUMP_HOLD
		var tx := float(_tr_jx[k])
		var st := _tr_mean(_tr_win(s, t0 + 1.2, t0 + TR_JUMP_HOLD, 3))
		if is_nan(st):
			missed += 1
			prev_x = tx
			continue
		errs.append(absf(st - tx))
		jit.append(_tr_std(_tr_win(s, t0 + 1.2, t0 + TR_JUMP_HOLD, 3)))
		var p0 := _tr_mean(_tr_win(s, t0 - 0.2, t0, 3))
		if k > 0 and not is_nan(p0):
			var travel := st - p0
			if absf(travel) < 0.05:
				missed += 1
			else:
				var dir := signf(travel)
				var ov := 0.0
				var got := -1.0
				for e in s:
					var ee := e as PackedFloat32Array
					if ee[0] < t0 or ee[0] > t0 + 1.2:
						continue
					if got < 0.0 and (ee[3] - p0) * dir >= 0.5 * absf(travel):
						got = (ee[0] - t0) * 1000.0
					ov = maxf(ov, (ee[3] - st) * dir)
				if got >= 0.0:
					t50s.append(got)
				overs.append(ov)
		prev_x = tx
	var worst := 0.0
	for v in t50s:
		worst = maxf(worst, float(v))
	return {"reactMs": int(_tr_median(t50s)) if not t50s.is_empty() else -1, "worstMs": int(worst), "landErr": _tr_median(errs), "overshoot": _tr_median(overs), "stillJitter": _tr_median(jit), "missed": missed, "jumps": _tr_jx.size() - 1}


func _trace_finish() -> void:
	autopilot = true
	var res: Dictionary = {}
	# 1 FOLLOW
	var s1: Array = _tr_samp[1]
	var h := s1.size() / 2
	var f_all := _tr_best(s1, 0, s1.size(), 1, 3)
	var f_slow := _tr_best(s1, 0, h, 1, 3)
	var f_fast := _tr_best(s1, h, s1.size(), 1, 3)
	res["follow"] = {"samples": s1.size(), "r": snappedf(float(f_all["r"]), 0.01), "lagMs": f_all["lagMs"], "lagSlowMs": f_slow["lagMs"], "lagFastMs": f_fast["lagMs"], "gain": snappedf(float(f_all["slope"]), 0.01), "offset": snappedf(float(f_all["icpt"]), 0.001), "wobble": snappedf(float(f_all["resid"]), 0.001)}
	# 2 JUMP
	var js := _tr_jump_stats()
	res["jump"] = {"reactMs": js["reactMs"], "worstMs": js["worstMs"], "landErr": snappedf(float(js["landErr"]), 0.001) if not is_nan(float(js["landErr"])) else -1.0, "overshoot": snappedf(float(js["overshoot"]), 0.001) if not is_nan(float(js["overshoot"])) else -1.0, "stillJitter": snappedf(float(js["stillJitter"]), 0.001) if not is_nan(float(js["stillJitter"])) else -1.0, "missed": js["missed"], "jumps": js["jumps"]}
	# 3 DOWNHILL
	var s3: Array = _tr_samp[3]
	var sum_off := 0.0
	var within := 0
	var sum_gz := 0.0
	for e in s3:
		var ee := e as PackedFloat32Array
		sum_off += absf(ee[5])
		if absf(ee[5]) < 2.5:
			within += 1
		sum_gz += absf(ee[3] - ee[1])
	var n3 := maxi(s3.size(), 1)
	var f_st := _tr_best(s3, 0, s3.size(), 7, 6)
	res["carve"] = {"samples": s3.size(), "offLineM": snappedf(sum_off / float(n3), 0.1), "withinPct": int(100.0 * float(within) / float(n3)), "gazeOnLineErr": snappedf(sum_gz / float(n3), 0.001), "steerLagMs": f_st["lagMs"], "steerR": snappedf(float(f_st["r"]), 0.01), "crashes": crashes - _tr_crash0, "barriers": _passed_ok - _tr_pass0}
	# tracker health and the settings in force
	res["tracker"] = {"fps": snappedf(float(GazeProvider._pkt_times.size()) / 2.0, 0.1), "latencyMs": int(GazeProvider.trk_lat_ms), "modelMs": int(GazeProvider.trk_inf_ms), "detectMs": int(GazeProvider.trk_det_ms), "delegate": GazeProvider.trk_delegate, "video": GazeProvider.trk_video, "renderScale": snappedf(_rs, 0.01), "frameMs": {"physics": snappedf(_pf_phys, 0.01), "hud": snappedf(_pf_hud, 0.01), "focus": snappedf(_pf_focus, 0.01), "poll": snappedf(GazeProvider.poll_ms, 0.01)}, "faceCropPx": GazeProvider.trk_roi, "eyePatches": GazeProvider.trk_patches, "cropMoves": GazeProvider.trk_roi_moves, "cropLost": GazeProvider.trk_roi_lost, "camFrames": GazeProvider.trk_cam_frames, "dropped": GazeProvider.trk_dropped, "gameFps": int(Engine.get_frames_per_second()), "signalLostPct": int(100.0 * float(_tr_miss) / float(maxi(_tr_total, 1))), "eyeWeights": [snappedf(GazeProvider.eye_w.x, 0.01), snappedf(GazeProvider.eye_w.y, 0.01)], "eyesOnly": eyes_only and GazeProvider.eih_ok}
	res["signals"] = _tr_signals()
	var suggest := reach
	var gain := float(f_all["slope"])
	if float(f_all["r"]) >= 0.6 and gain > 0.4 and gain < 2.5:
		suggest = clampf(reach / gain, 0.6, 4.0)
	res["tune"] = {"reach": snappedf(reach, 0.01), "suggestReach": snappedf(suggest, 0.01), "smoothMs": int(look_smooth * 1000.0), "steerRate": steer_rate, "zoneScale": snappedf(_zone_scale, 0.01), "curve": snappedf(steer_curve, 0.01), "assist": carve_assist}
	# the raw series (15 per second: time, dot x, raw iris-in-eye x, cursor x) for fitting the smoothing offline
	var csv := PackedStringArray(["phase,t,dotx,raw,cursorx,headDeg,screenGaze,irisSmooth"])
	for ph in [1, 2]:
		var sa: Array = _tr_samp[ph]
		var si := 0
		while si < sa.size():
			var e := sa[si] as PackedFloat32Array
			csv.append("%d,%.2f,%.3f,%.4f,%.3f,%.1f,%.3f,%.4f" % [ph, e[0], e[1], e[8], e[3], rad_to_deg(e[9]), e[10], e[11]])
			si += 2
	res["seriesCsv"] = "\n".join(csv)
	_tr_res = res
	_tr_build_lines()
	_trace_copy()
	var brief := res.duplicate()
	brief.erase("seriesCsv")
	print("TRACE ", JSON.stringify(brief))


func _tr_grade(v: float, good: float, ok: float) -> Color:
	if v <= good:
		return Color(0.5, 1.0, 0.6)
	if v <= ok:
		return Color(1.0, 0.85, 0.4)
	return Color(1.0, 0.5, 0.45)


func _tr_build_lines() -> void:
	var fo: Dictionary = _tr_res["follow"]
	var jp: Dictionary = _tr_res["jump"]
	var cv: Dictionary = _tr_res["carve"]
	var tk: Dictionary = _tr_res["tracker"]
	var tn: Dictionary = _tr_res["tune"]
	var L: Array = []
	L.append(["GAZE TRACE RESULTS", Color(1, 1, 1), 26])
	L.append(["FOLLOW  gaze tracks the dot: r %.2f   scale x%.2f   wobble %.1f%% of screen" % [float(fo["r"]), float(fo["gain"]), float(fo["wobble"]) * 100.0], _tr_grade(1.0 - float(fo["r"]), 0.1, 0.25), 16])
	L.append(["        lag %d ms   (slow sweep %d ms, fast sweep %d ms)" % [int(fo["lagMs"]), int(fo["lagSlowMs"]), int(fo["lagFastMs"])], _tr_grade(float(fo["lagMs"]), 150.0, 280.0), 16])
	L.append(["JUMP    reaction %d ms (worst %d)   lands %.1f%% off   overshoot %.1f%%" % [int(jp["reactMs"]), int(jp["worstMs"]), float(jp["landErr"]) * 100.0, float(jp["overshoot"]) * 100.0], _tr_grade(float(jp["reactMs"]), 330.0, 520.0), 16])
	L.append(["        held still: jitter %.1f%%   missed %d of %d jumps" % [float(jp["stillJitter"]) * 100.0, int(jp["missed"]), int(jp["jumps"])], _tr_grade(float(jp["stillJitter"]), 0.02, 0.04), 16])
	L.append(["DOWNHILL   %.1f m off the line, %d%% within 2.5 m   crashes %d   barriers %d" % [float(cv["offLineM"]), int(cv["withinPct"]), int(cv["crashes"]), int(cv["barriers"])], _tr_grade(float(cv["offLineM"]), 3.0, 6.0), 16])
	L.append(["        eyes on the line within %.1f%%   steering lag %d ms" % [float(cv["gazeOnLineErr"]) * 100.0, int(cv["steerLagMs"])], _tr_grade(float(cv["steerLagMs"]), 250.0, 450.0), 16])
	L.append(["TRACKER %d frames/s (%d dropped)   latency %d ms   model %d ms   game %d/s   lost %d%%" % [int(float(tk["fps"])), int(tk["dropped"]), int(tk["latencyMs"]), int(tk["modelMs"]), int(tk["gameFps"]), int(tk["signalLostPct"])], _tr_grade(30.0 - float(tk["fps"]), 4.0, 10.0), 16])
	var sg: Dictionary = _tr_res["signals"]
	L.append(["SIGNALS error vs dot, %% of screen (head moved %.1f deg):  iris %.1f  screen %.1f  head %.1f  iris+head %.1f  all %.1f" % [float(sg["headYawStdDeg"]), float(sg["iris"]["errPct"]), float(sg["screenGaze"]["errPct"]), float(sg["head"]["errPct"]), float(sg["iris+head"]["errPct"]), float(sg["all"]["errPct"])], Color(0.8, 0.9, 1.0), 16])
	L.append(["", Color(1, 1, 1), 12])
	var adv: Array = []
	var gain: float = float(fo["gain"])
	if float(fo["r"]) < 0.6:
		adv.append("Barely followed the dot: check light, face in view, glasses glare.")
	elif absf(gain - 1.0) > 0.15:
		adv.append("Your gaze moved x%.2f as far as the dot: set REACH about x%.2f (now x%.2f)." % [gain, float(tn["suggestReach"]), float(tn["reach"])])
	if int(fo["lagMs"]) > 250:
		adv.append("Late by %d ms: the tracker adds %d ms, smoothing %d ms: try SNAPPIER." % [int(fo["lagMs"]), int(maxf(float(tk["latencyMs"]), 0.0)), int(tn["smoothMs"])])
	if float(fo["wobble"]) > 0.045 or float(jp["stillJitter"]) > 0.035:
		adv.append("Jittery: try STEADIER, or more light on your face.")
	if int(tk["signalLostPct"]) > 10:
		adv.append("Lost your eyes %d%% of the time." % int(tk["signalLostPct"]))
	if float(tk["fps"]) < 20.0:
		adv.append("Camera only %d frames/s: more light, or ?fast." % int(float(tk["fps"])))
	if adv.is_empty():
		adv.append("Tracking looks healthy. Copy the report and send it for tuning.")
	for a in adv:
		L.append([String(a), Color(0.85, 0.92, 1.0), 15])
	L.append(["", Color(1, 1, 1), 12])
	L.append(["tap or press C to copy the report   R run again   T end", Color(1, 1, 1, 0.75), 15])
	if _tr_note != "":
		L.append([_tr_note, Color(0.6, 1.0, 0.7), 15])
	_tr_lines = L


# ---- steering safety: a gaze signal that flails or disappears must never throw the board around
var _fl_clock: float = 0.0
var _fl_side: int = 0
var _fl_flips: Array = []
var _flail_t: float = 0.0
var _lost_t: float = 0.0
var _ev: Array = []
var _ev_ex_sign: float = 1.0
var _ev_conf_low: bool = false
var _ev_head_far: bool = false


func _note(msg: String) -> void:
	_log_ev(msg)


func _log_ev(msg: String) -> void:
	_ev.append("%.0fs %dm %s" % [_clock, int(maxf(-spos.z, 0.0)), msg])
	if _ev.size() > 40:
		_ev.remove_at(0)


## The eye steering, checked: if the look keeps flipping hard from one side to the other, or the tracker has stopped, the board is eased back toward straight.
func _guard_gaze(s: float, delta: float) -> float:
	_fl_clock += delta
	var side := 0
	if s > 0.5:
		side = 1
	elif s < -0.5:
		side = -1
	if side != 0 and side != _fl_side:
		if _fl_side != 0:
			_fl_flips.append(_fl_clock)
		_fl_side = side
	while not _fl_flips.is_empty() and _fl_clock - float(_fl_flips[0]) > 1.2:
		_fl_flips.remove_at(0)
	if _fl_flips.size() >= 3 and _flail_t <= 0.0:
		_log_ev("steering flipped side %d times in 1.2 s: softened (conf %.2f, spread %.3f)" % [_fl_flips.size(), GazeProvider.confidence, _stat_std])
		_toast("Tracking jittery: steering softened", Color(1.0, 0.8, 0.4))
		_flail_t = 2.0
		_fl_flips.clear()
	_flail_t = maxf(_flail_t - delta, 0.0)
	# events for the report: what the tracker was doing when things went wrong
	if _ex_sign != _ev_ex_sign:
		_ev_ex_sign = _ex_sign
		_log_ev("eye direction flipped to %s" % ("normal" if _ex_sign > 0.0 else "reversed"))
	var low := GazeProvider.confidence < 0.5
	if low != _ev_conf_low:
		_ev_conf_low = low
		_log_ev("tracker confidence %s (%.2f)" % ["low" if low else "back", GazeProvider.confidence])
	var turn := absf(rad_to_deg(GazeProvider.head_rpy.x))
	var far := turn > 25.0
	if far != _ev_head_far:
		_ev_head_far = far
		_log_ev("head turned %s (%.0f deg)" % ["far" if far else "back", turn])
	var live := GazeProvider.backend != GazeProvider.Backend.CAMERA or GazeProvider._camera_fresh()
	if not live:
		if _lost_t <= 0.0:
			_log_ev("tracker stopped sending frames")
			_toast("Lost your eyes", Color(1.0, 0.5, 0.45))
		_lost_t = 1.0
		return 0.0
	_lost_t = maxf(_lost_t - delta, 0.0)
	return s * (0.3 if _flail_t > 0.0 else 1.0)


func _trace_copy() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_pause_report(), "  "))
	_tr_note = "report copied"
	_tr_build_lines()


func _draw_trace(font: Font, s: Vector2, k: float) -> void:
	if _tr_phase < 0:
		return
	var m := 24.0 * k
	if _tr_phase == 4:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.86))
		var y := m
		for ln in _tr_lines:
			var sz: int = int(ln[2])
			y += float(sz) * 1.5 * k
			_text(font, Vector2(m, y), String(ln[0]), sz, ln[1])
		return
	var cy := Color(1.0, 0.15, 0.7)
	if _tr_phase == 1:
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(_tr_pursuit_pos(minf(_tr_t + float(i) * 0.1, TR_PURSUIT)) * s)
		Draw2D.pline(_hud, pts, Color(cy.r, cy.g, cy.b, 0.35), 4.0 * k)
	elif _tr_phase == 3:
		var rp := PackedVector2Array()
		var d := 6.0
		while d < 150.0:
			var zt := spos.z - d
			var p := _tr_world_px(_safe_x_at(zt), zt, 0.4)
			if p.x > -9000.0:
				rp.append(p)
			d += 7.0
		if rp.size() > 1:
			Draw2D.pline(_hud, rp, Color(cy.r, cy.g, cy.b, 0.6), 5.0 * k)
	var bp := _tr_bead * s
	Draw2D.circle(_hud, bp, 26.0 * k, Color(cy.r, cy.g, cy.b, 0.35))
	Draw2D.arc(_hud, bp, 26.0 * k, 0.0, TAU, 28, Color(0, 0, 0, 0.8), 6.0 * k)
	Draw2D.arc(_hud, bp, 26.0 * k, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 3.0 * k)
	Draw2D.circle(_hud, bp, 9.0 * k, Color(0, 0, 0, 0.8))
	Draw2D.circle(_hud, bp, 7.0 * k, Color(1, 1, 1, 1.0))
	var title := ""
	var left := 0.0
	match _tr_phase:
		0:
			title = "GAZE TRACE: follow the glowing dot with your eyes"
			left = TR_INTRO - _tr_t
		1:
			title = "1 of 3  FOLLOW the dot"
			left = TR_PURSUIT - _tr_t
		2:
			title = "2 of 3  look at the dot each time it jumps"
			left = TR_JUMPS - _tr_t
		3:
			title = "3 of 3  DOWNHILL: steer with your eyes along the line"
			left = TR_CARVE - _tr_t
	_ctext(font, m + 64.0 * k, "%s   %d s" % [title, int(ceilf(maxf(left, 0.0)))], 22, Color(0.8, 0.95, 1.0))
