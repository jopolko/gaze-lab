class_name CarveRig
extends DownhillRig
## CARVE: free carving down an open slope. No lanes, no gates, no markers: the course is natural (tree lines, boulder bands, scattered
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
const AIM_LINGER := 0.22             # seconds your eyes must stay on an opening before it latches
const AIM_MIN_DIST := 14.0
const AIM_MAX_DIST := 190.0
const START_CALM := 2                # the first segments are open snow
const MIN_SPEED := 14.0

var carve_assist: float = 1.0        # how hard a latched opening pulls the board: it is the main control, the raw look only trims
var aim_enabled: bool = true         # tests: switch the opening choice off to check the raw look-trim alone
var _aim_cx: float = -1.0           # your look, smoothed over ~0.2 s, for choosing an opening (the raw cursor jitters by several percent of the screen)
var autopilot: bool = false          # tests: steer toward the safe opening of the next barrier
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
	name = "CarveRig"
	_zone_scale = 1.8                    # the trim from the raw look is looser: full lock at about +-19% of the screen, not +-10%
	_toast("Look where you want to carve", Color(0.9, 0.95, 1.0))
	if OS.has_feature("web"):
		_tr_auto = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('trace')"))
		var rsq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('rs') || ''"))
		if rsq == "auto":
			_rs_off = false
		elif rsq != "":
			_rs_pin = clampf(float(rsq), 0.3, 1.0)
			_rs = _rs_pin
			get_viewport().scaling_3d_scale = _rs


# --------------------------------------------------------------------------
# Terrain: the base slope, getting steeper with distance
# --------------------------------------------------------------------------
func terrain_h(x: float, z: float) -> float:
	var u := maxf(-z, 0.0)
	return super.terrain_h(x, z) - 0.00002 * u * u


func _course_diff(z0: float) -> float:
	return clampf(0.12 + (-z0) / absf(FINISH_Z) * 0.88, 0.0, 1.0)


func progress() -> float:
	return clampf(-spos.z / absf(FINISH_Z), 0.0, 1.0)


# --------------------------------------------------------------------------
# Course: every segment has a barrier (a line of trees / boulders with openings) at a random depth, and scattered singles in between.
# The safe opening drifts by at most about 36 m from one barrier to the next, so it is always reachable with a carve.
# --------------------------------------------------------------------------
func _gen_segment(j: int) -> void:
	var z0 := -ROW_GAP * float(j)
	var d := _course_diff(z0)
	var rz := z0 - _rng.randf_range(26.0, 60.0)
	var has_row := j >= START_CALM and rz > FINISH_Z + 40.0
	var row: Dictionary = {"j": j, "z": rz, "z0": z0, "gaps": [], "obs": PackedFloat32Array(), "banks": [], "nodes": [],
		"passed": false, "crash": false, "has_row": has_row}
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
		var shift := clampf((_last_rz - rz) * 0.30, 8.0, 36.0)          # the safe opening moves at most a third of the distance since the last barrier: always reachable
		_last_rz = rz
		_good_x = clampf(_good_x + _rng.randf_range(-1.0, 1.0) * shift * (0.6 + 0.4 * d), -42.0, 42.0)
		var gaps: Array = row["gaps"]
		var g0 := _mk_gap(_good_x, lerpf(17.0, 10.0, d) * _rng.randf_range(0.92, 1.1), "open", true)
		g0["lane"] = -1
		gaps.append(g0)
		var extra := (1 if _rng.randf() < 0.55 + 0.3 * d else 0) + (1 if d > 0.5 and _rng.randf() < 0.5 else 0)
		for e in extra:
			for attempt in 10:
				var ex := _rng.randf_range(-46.0, 46.0)
				var ew := lerpf(15.0, 9.0, d) * _rng.randf_range(0.9, 1.1)
				var ok := true
				for g in gaps:
					if absf(ex - float(g["x"])) < (float(g["w"]) + ew) * 0.5 + 9.0:
						ok = false
				if ok:
					var ge := _mk_gap(ex, ew, "open", false)
					ge["lane"] = -1
					gaps.append(ge)
					break
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
	# scattered singles between this barrier and the one before it; the straight line from the last safe opening to this one stays clear
	if has_row:
		var n_single := int(float(prev_rz - rz) / ROW_GAP * (4.0 + 6.0 * d)) + 1
		for i in n_single:
			var sz := _rng.randf_range(rz + 9.0, minf(prev_rz - 9.0, -30.0))
			var sx := _rng.randf_range(-W_HALF + 3.0, W_HALF - 3.0)
			if absf(sx - path_x(row, sz)) < 9.0:
				continue
			if _rng.randf() < 0.35:
				_add_rock(rocks, rock_cols, obs, sx, sz, _rng.randf_range(1.0, 1.6), Color(0.55, 0.58, 0.64), _rng.randf_range(0.9, 1.3))
			else:
				_add_tree(cones, cone_cols, trunks, trunk_cols, obs, sx, sz, _rng.randf_range(0.8, 1.3), true)
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
	if z0 > FINISH_Z and z0 - ROW_GAP <= FINISH_Z:
		_make_finish(row)
	_rows[j] = row
	_chunks[j] = _build_chunk(j)


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
		post.global_position = Vector3(px, terrain_h(px, FINISH_Z) + 6.0, FINISH_Z)
		(row["nodes"] as Array).append(post)
	for i in 12:
		var bx := -22.0 + 4.0 * float(i)
		var seg := MeshInstance3D.new()
		seg.mesh = _m_bar
		seg.scale = Vector3(4.0, 1.8, 0.8)
		seg.material_override = _flat_mat(Color(0.97, 0.97, 1.0) if i % 2 == 0 else Color(0.12, 0.12, 0.16))
		add_child(seg)
		seg.global_position = Vector3(bx, terrain_h(bx, FINISH_Z) + 12.4, FINISH_Z)
		(row["nodes"] as Array).append(seg)


# --------------------------------------------------------------------------
# Physics: the hill pulls, carving costs speed, the board turns on a short spring, momentum follows through grip
# --------------------------------------------------------------------------
## The safe line toward a barrier: straight from the safe opening of the barrier before it to the safe opening of this one.
func path_x(row: Dictionary, z: float) -> float:
	var gx := 0.0
	for g in row["gaps"]:
		if g["good"]:
			gx = float(g["x"])
	var span := float(row["pz"]) - float(row["z"])
	if span < 1.0:
		return gx
	return lerpf(float(row["px"]), gx, clampf((float(row["pz"]) - z) / span, 0.0, 1.0))


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
var _wall_gap: Dictionary = {}
var _wall_row_j: int = -999
var _wall_w: float = 0.0             # how hard the nearest barrier pulls (0..1), for the HUD and the report
var _swerve_s: float = 0.0           # the sideways shift the board is making right now (m)
var swerves: int = 0
var _swerving: bool = false
var _swerve_idle: float = 0.0
var wrong_gates: int = 0             # barriers passed through a gate other than the one the eyes had latched


## Smallest sideways shift (m) that clears every lone tree/rock closer than max_t seconds ahead, and the time to the nearest of them.
func _free_shift(max_t: float, sp: float, above: float) -> Vector2:
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
		if ok and absf(s) < absf(best):
			best = s
	return Vector2(0.0 if best > 1.0e8 else best, tmin)


## Returns the steering added by the avoidance and gate commitment, and nudges the board sideways at the last moment if a swerve is still owed.
func _guard_path(delta: float, s_in: float) -> float:
	_swerve_s = 0.0
	_wall_w = 0.0
	if _finished or hurt_t > 0.0:
		return 0.0
	var add := 0.0
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
	var wall_far := clampf(spd_w * 2.4, WALL_FAR, 180.0)       # the hill speeds up, so the pull starts earlier in metres, not in seconds
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
				var dd := absf(float(g["x"]) - px) * (0.6 if is_same(g, _wall_gap) else 1.0)
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
		var w := u
		if eyes_chose:
			w = maxf(carve_assist * _assist_conf() * _aim_w, u)
		_wall_w = w
		var want := clampf((float(tgt["x"]) - (spos.x + vel.x * 0.45)) / 12.0, -0.9, 0.9)
		add += w * want * (1.0 - 0.6 * absf(s_in))
		gate_done = true
	if not gate_done:
		add += carve_assist * _assist_conf() * _aim_w * _aim_want * (1.0 - 0.6 * absf(s_in))
	# 2) a lone tree or rock on the way: swerve by just what is needed
	var av := 0.0
	if avoid_enabled:
		var sp := maxf(-vel.y, 6.0)
		var above := spos.y - terrain_h(spos.x, spos.z)
		var far := _free_shift(clampf(55.0 / sp, 1.0, 1.6), sp, above)
		if absf(far.x) > 0.001:
			av = clampf(far.x / 6.0, -0.9, 0.9)
			_swerve_idle = 0.0
			if not _swerving:
				_swerving = true
				swerves += 1
			var near := _free_shift(0.55, sp, above)
			if absf(near.x) > 0.001:
				var nudge := near.x * clampf(delta / maxf(near.y, 0.1), 0.0, 1.0)
				nudge = clampf(nudge, -12.0 * delta, 12.0 * delta)
				spos.x += nudge
				_swerve_s = nudge / maxf(delta, 0.0001)
		else:
			_swerve_idle += delta
			if _swerve_idle > 0.6:
				_swerving = false
	return add + av


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
			get_viewport().scaling_3d_scale = 1.0
			_log_ev("render scale did not raise the frame rate (%d fps): back to full" % int(f))
			return
		_rs_drop_fps = f
		_rs = maxf(_rs - 0.1, 0.5)
	elif f > 57.0:
		_rs = minf(_rs + 0.05, 1.0)
		_rs_drop_fps = 0.0
	get_viewport().scaling_3d_scale = _rs


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = 1.0


func _physics_process(delta: float) -> void:
	if _paused:
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
	_eye_on = _eye_mode()
	_clock += delta
	if _finished:
		_end_t += delta
	else:
		_run_t += delta
	var dist := maxf(-spos.z, 0.0)
	var prog := clampf(dist / PULL_RAMP, 0.0, 1.0)
	# steering: your gaze when the eyes are on (a head lean must not steer), else a lean, plus keys; a latched opening adds a gentle pull
	var eye_s := _guard_gaze(_steer_gaze, delta) if _eye_on else 0.0
	# A webcam gaze is a slow, noisy signal (a few percent of the screen of jitter), so the eyes CHOOSE the opening and the board carves to it; free steering from the
	# raw look only trims (0.6 with nothing chosen, 0.15 once an opening is locked).
	var eye_gain := lerpf(0.6, 0.15, _aim_w)
	var s_in := key + (eye_s * eye_gain if _eye_on else clampf(pk.x / 1.8, -1.0, 1.0))
	if autopilot:
		s_in = _auto_steer()
	s_in = clampf(s_in, -1.0, 1.0)
	steer = clampf(s_in + _guard_path(delta, s_in), -1.0, 1.0)
	if _finished:
		steer = 0.0
	_steer_s = lerpf(_steer_s, steer, 1.0 - exp(-steer_rate * delta))
	steer = _steer_s
	var tuck := nod_p < -0.10 and not _finished
	tucking = tuck and grounded
	braking = false
	gliding = false
	var theta_t := steer * THETA_MAX
	heading += (theta_t - heading) * (1.0 - exp(-delta / (0.18 if grounded else 0.35)))
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
		var drag := DRAG * (0.55 if tucking else 1.0) * lerpf(1.0, 0.5, prog)          # less drag the further you go: the hill keeps pulling harder
		var fr := 0.22 + (3.0 if _finished else 0.0)
		if _finished:
			vel *= exp(-1.3 * delta)
		if sp > 0.01:
			var dec := minf((fr + drag * sp * sp) * delta, sp)
			vel -= vel / sp * dec
		var old_sp := vel.length()
		var along := vel.dot(fwd)
		var lat := vel.dot(right)
		var lat_new := lat * exp(-GRIP * (0.75 if tucking else 1.0) * delta)
		along += absf(lat - lat_new) * 0.6 * signf(along if absf(along) > 0.01 else 1.0)          # a carve costs some speed
		vel = fwd * along + right * lat_new
		if vel.length() > old_sp:
			vel = vel.normalized() * old_sp
	else:
		var sp2 := vel.length()
		if sp2 > 0.01:
			vel -= vel / sp2 * minf(DRAG * 0.4 * sp2 * sp2 * delta, sp2)
		vel += right * steer * 3.0 * delta
		air_t += delta
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
			vy = vg
	else:
		vy -= G * delta
		spos.y += vy * delta
		if spos.y <= gh:
			_land(maxf(gvy - vy, 0.0), gh, gvy)
	_gh_prev = gh
	_collide()
	_update_rows()
	if not _finished and spos.z <= FINISH_Z:
		_finish()
	if int(float(_next_j) * ROW_GAP) < int(-spos.z + AHEAD):
		_gen_segment(_next_j)
		_next_j += 1
	_cleanup()
	_pf_phys = _pf(_pf_phys, pf0)


func _collide() -> void:
	if hurt_t > 0.0 or _finished:
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
					var wallhit: bool = rj["has_row"] and absf(oz - float(rj["z"])) < 7.0
					_crash("TREE!" if okind < 0.5 else "ROCK!", "%s swerving %s wallPull %.2f latched %s speed %.0f sideways %.1f" % ["WALL" if wallhit else "SINGLE", str(_swerving), _wall_w, str(not _aim.is_empty()), v_pre.length(), v_pre.x])
					if wallhit:
						hurt_t = 2.2          # still inside the barrier band: enough grace to be carried out of it instead of into the next tree
					return


func _crash(msg: String, ctx: String = "") -> void:
	if hurt_t > 0.0 or _finished:
		return
	crashes += 1
	_clean = false
	crash_log.append("%s at z=%.0f x=%.1f v=%.1f %s" % [msg, spos.z, spos.x, vel.length(), ctx])
	hurt_t = 1.1
	vel *= 0.3
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
			if chosen.is_empty() or r["crash"]:
				continue
			_passed_ok += 1
			# with the eyes on, the points are for the gate you chose with them; the board's own pick (or a wrong one) carries you through but is worth little
			var eg: Dictionary = r.get("eyes_gap", {})
			if _eye_on and gate_assist and not autopilot and not is_same(eg, chosen):
				score += 10
				chain = 0
				groove = 1.0
				if eg.is_empty():
					_toast("AUTO GATE", Color(0.8, 0.8, 0.85))
				else:
					wrong_gates += 1
					_toast("WRONG GATE: RECOVER", Color(1.0, 0.75, 0.3))
				continue
			var margin := clampf(1.0 - absf(spos.x - float(chosen["x"])) / (float(chosen["w"]) * 0.5), 0.0, 1.0)
			var pts := 40 + int(30.0 * margin)
			if float(chosen["w"]) < 11.5:
				pts += 30
				_tight_n += 1
				_toast("TIGHT", Color(0.4, 1.0, 0.7))
			chain += 1
			groove = 1.0 + 0.25 * minf(float(chain), 8.0)
			best_flow = maxf(best_flow, groove)
			score += int(float(pts) * groove)
			Game.sfx(&"coin")


func _finish() -> void:
	_finished = true
	_end_t = 0.0
	if _best_time <= 0.0 or (_clean and _run_t < _best_time):
		_best_time = _run_t
	if _clean:
		score += 1000
	Game.sfx(&"boom")
	_flash = 0.6
	_toast("FINISH!", Color(1.0, 0.9, 0.4))


func _restart() -> void:
	cleanup()
	_run_seed += 1
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
	_gh_prev = spos.y
	_aim = {}
	_aim_row = {}
	_cand = {}
	_cand_t = 0.0
	_aim_w = 0.0
	swerves = 0
	wrong_gates = 0
	_swerving = false
	_wall_gap = {}
	_wall_row_j = -999
	while float(_next_j) * ROW_GAP < AHEAD:
		_gen_segment(_next_j)
		_next_j += 1
	_place_camera(1.0, true)
	_toast("Look where you want to carve", Color(0.9, 0.95, 1.0))


# --------------------------------------------------------------------------
# Aim: the opening you look at, and keep looking at for a moment, pulls the board through it
# --------------------------------------------------------------------------
func _update_focus(delta: float) -> void:
	var pf0 := Time.get_ticks_usec()
	super._update_focus(delta)
	_update_aim(delta)
	_trace_tick(delta)
	_pf_focus = _pf(_pf_focus, pf0)


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
		if dist < AIM_MIN_DIST or dist > AIM_MAX_DIST:
			continue
		row = r
		break
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
	_aim_cx = lerpf(_aim_cx, _cursor_px.x, 1.0 - exp(-delta / 0.18))
	var cx := _aim_cx
	var best: Dictionary = {}
	var best_d := 1.0e9
	for g in row["gaps"]:
		var sc := _gap_screen(row, g)
		if sc.is_empty():
			continue
		var c: Vector2 = sc["c"]
		var tol := maxf(float(sc["hw"]) * 1.15, 0.12 * vs.x)
		var dd := absf(c.x - cx) / tol
		if is_same(g, _aim):
			dd *= 0.7
		if dd < best_d:
			best_d = dd
			best = g
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
	if _pause_input(event):
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
	if id == "trace_off":
		_trace_end()
		_copy_note = "trace ended"
		return
	super._pause_action(id)


func _pause_report() -> Dictionary:
	var r := super._pause_report()
	r["carve"] = {"distance": int(-spos.z), "finishAt": int(-FINISH_Z), "speedKmh": int(vel.length() * 3.6), "crashes": crashes, "barriersPassed": _passed_ok,
		"tight": _tight_n, "crashLog": crash_log.slice(maxi(crash_log.size() - 12, 0)), "swerves": swerves, "wrongGates": wrong_gates, "gatePull": snappedf(_wall_w, 0.01), "aimLatched": not _aim.is_empty(), "aimPull": snappedf(_aim_w, 0.01), "runTime": snappedf(_run_t, 0.1), "finished": _finished, "events": _ev}
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


func _draw_hud_inner() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	var m := 24.0 * k
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.22 * clampf(hurt_t, 0.0, 1.0)))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, 0.3 * _flash))
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
						_hud.draw_arc(cc, 16.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_cand_t / AIM_LINGER, 0.0, 1.0), 24, Color(1.0, 1.0, 1.0, 0.85), 3.5 * k)
	# gaze reticle
	if _eye_on and not _paused:
		var cur_px := _cursor_px if _cursor_px != Vector2.ZERO else _gaze_px
		for ti in _gaze_trail.size():
			var ta := float(ti + 1) / float(_gaze_trail.size() + 1)
			_hud.draw_circle(_gaze_trail[ti], 5.0 * k * ta, Color(1.0, 0.6, 0.1, 0.35 * ta))
		_hud.draw_circle(cur_px, 15.0 * k, Color(1.0, 0.6, 0.1, 0.18))
		_hud.draw_arc(cur_px, 15.0 * k, 0.0, TAU, 24, Color(1.0, 0.6, 0.1, 0.95), 3.5 * k)
		_hud.draw_circle(cur_px, 4.5 * k, Color(1.0, 0.6, 0.1, 0.95))
	# progress bar (top centre), score (top left), eyes status (top right)
	var bw := minf(s.x * 0.34, 420.0 * k)
	var bx := s.x * 0.5 - bw * 0.5
	_hud.draw_rect(Rect2(bx, m, bw, 10.0 * k), Color(0.05, 0.12, 0.25, 0.5))
	_hud.draw_rect(Rect2(bx, m, bw * progress(), 10.0 * k), Color(1.0, 0.85, 0.35, 0.95))
	_hud.draw_rect(Rect2(bx + bw - 3.0 * k, m - 4.0 * k, 3.0 * k, 18.0 * k), Color(1, 1, 1, 0.9))
	_text(font, Vector2(m, m + 22.0 * k), "%d" % score, 34, Color(1, 1, 1))
	var eye_txt := "EYES OFF"
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		eye_txt = "EYES"
	elif GazeProvider.backend == GazeProvider.Backend.MOUSE and not Game.touch_mode:
		eye_txt = "MOUSE EYES"
	var ecol := Color(0.5, 1.0, 0.6) if _eye_on else Color(1, 1, 1, 0.55)
	var ew := font.get_string_size(eye_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_text(font, Vector2(s.x - m - ew, m + 18.0 * k), eye_txt, 20, ecol)
	_text(font, Vector2(m, s.y - m - 30.0 * k), "%d km/h" % int(vel.length() * 3.6), 30, Color(1, 1, 1))
	if chain > 0:
		_text(font, Vector2(m, s.y - m), "FLOW x%.1f" % groove, 22, Color(1.0, 0.85, 0.3))
	var dtxt := "%d m" % int(maxf(-spos.z, 0.0))
	var dw := font.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26.0 * k)).x
	_text(font, Vector2(s.x - m - dw, s.y - m), dtxt, 26, Color(1, 1, 1, 0.85))
	var ty := s.y * 0.2
	for t in _toasts:
		var a2 := clampf(float(t["t"]) / 0.5, 0.0, 1.0)
		var col2: Color = t["color"]
		col2.a = a2
		_ctext(font, ty, String(t["text"]), 30, col2)
		ty += 38.0 * k
	if _finished:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.55))
		_ctext(font, s.y * 0.34, "FINISH", 64, Color(1.0, 0.9, 0.4))
		_ctext(font, s.y * 0.34 + 56.0 * k, "time %.1f s   crashes %d   score %d" % [_run_t, crashes, score], 30, Color(1, 1, 1))
		if crashes == 0:
			_ctext(font, s.y * 0.34 + 98.0 * k, "CLEAN RUN +1000", 28, Color(0.5, 1.0, 0.6))
		if _end_t > 1.2:
			_ctext(font, s.y * 0.34 + 148.0 * k, "press R, SPACE or tap to ride again", 22, Color(1, 1, 1, 0.85))
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
		_ctext(font, s.y * 0.30, _coach_text, 24, ccol)
	var cmsg := GazeProvider.camera_message()
	if String(cmsg["text"]) != "" and (_age < 12.0 or not GazeProvider._camera_fresh()):
		_ctext(font, s.y * 0.12, String(cmsg["text"]), 20, cmsg["color"])
	if trace_on and not _paused:
		_draw_trace(font, s, k)


# --------------------------------------------------------------------------
# TRACE test: follow a highlighted dot with your eyes while the game measures how well the tracking keeps up.
# Start it from Pause -> TRACE TEST, with the T key, or by opening the page with &trace=1.
#   1 FOLLOW: the dot sweeps back and forth, faster and faster (smooth following: scale, lag, wobble)
#   2 JUMP:   the dot jumps to a new spot every 2 s (glance reaction, where you land, how steady you hold)
#   3 CARVE:  the real game, steering with your eyes along a highlighted line (how far off the line, the steering lag)
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
	if cam.is_position_behind(wp):
		return Vector2(-9999.0, -9999.0)
	return cam.unproject_position(wp)


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
	# 3 CARVE
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
	L.append(["CARVE   %.1f m off the line, %d%% within 2.5 m   crashes %d   barriers %d" % [float(cv["offLineM"]), int(cv["withinPct"]), int(cv["crashes"]), int(cv["barriers"])], _tr_grade(float(cv["offLineM"]), 3.0, 6.0), 16])
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
		_hud.draw_polyline(pts, Color(cy.r, cy.g, cy.b, 0.35), 4.0 * k)
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
			_hud.draw_polyline(rp, Color(cy.r, cy.g, cy.b, 0.6), 5.0 * k)
	var bp := _tr_bead * s
	_hud.draw_circle(bp, 26.0 * k, Color(cy.r, cy.g, cy.b, 0.35))
	_hud.draw_arc(bp, 26.0 * k, 0.0, TAU, 28, Color(0, 0, 0, 0.8), 6.0 * k)
	_hud.draw_arc(bp, 26.0 * k, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 3.0 * k)
	_hud.draw_circle(bp, 9.0 * k, Color(0, 0, 0, 0.8))
	_hud.draw_circle(bp, 7.0 * k, Color(1, 1, 1, 1.0))
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
			title = "3 of 3  CARVE: steer with your eyes along the line"
			left = TR_CARVE - _tr_t
	_ctext(font, m + 64.0 * k, "%s   %d s" % [title, int(ceilf(maxf(left, 0.0)))], 22, Color(0.8, 0.95, 1.0))
