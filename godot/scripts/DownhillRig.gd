class_name DownhillRig
extends Node3D
## DOWNHILL: a procedural snow run where gravity, momentum and posture do the work.
##
##   body            real slope physics: the hill pulls you, carving sheds speed, a tuck cuts drag, sitting up brakes
##   LEAN head       steer. The board turns, your momentum follows the grip, so a hard turn costs speed
##   chin DOWN hold  TUCK: less drag (faster) and it charges a spring
##   chin snaps UP   POP: a hop off the snow (bigger when charged). Hold chin UP in the air to GLIDE
##   chin UP hold    on snow: sit up = air brake
##   chin snaps DOWN in the air: SLAM, a stomp landing that kicks you forward
##   EYES            the course is a row of openings in a forest wall. Far away every opening looks alike. Look at one
##                   for a moment and it resolves (open / hop / dead end). Peripheral vision handles what is near.
##
## Input: GazeProvider.peek_offset (lean), nod_state (chin), gaze (screen position). Arrow keys, A / D, W / S stand in.

const G := 9.8
const SLOPE := 0.34
const ROW_GAP := 85.0
const W_HALF := 58.0
const GROUND_HALF := 150.0
const FLAG_COLS := [Color(1.0, 0.5, 0.15), Color(0.2, 0.8, 0.9), Color(0.16, 0.16, 0.2)]
const AHEAD := 520.0
const SLED_R := 1.0
const THETA_MAX := 1.05
const DRAG := 0.0024
const GRIP := 2.6
const FOCUS_TIME := 0.35
const EYE_REVEAL := 46.0
const PLAIN_REVEAL := 110.0
const CAL_DOT_T := 2.2
const CAL_SETTLE := 0.8
const GAZE_Y := 0.46
const ASSIST := 0.75        # how hard the line your eyes set pulls the board (your lean still wins)
const LATE_DIST := 34.0     # a late gate opens at least this close ...
const SHUT_DIST := 26.0     # a false opening slams shut at least this close
const LATE_WARN := 1.5      # ... and never later than this many seconds before you arrive (eyes need about 0.7 s to read and commit)
const SHUT_WARN := 1.1
# THREE-LANE mode: every wall has exactly three lanes (left / centre / right). Your eyes choose a lane, the board carves to it.
const LANE_X := [-24.0, 0.0, 24.0]
const LANE_W := 14.0
const CALM_ROWS := 5               # the first rows are all open: settle in
const LANE_ZONE := 0.13            # dead zone: look further than this (screen fraction) left or right of the middle to step a lane
const LANE_MARGIN := 0.04          # gate mode: your eyes must be this much (screen fraction) nearer another gate before it can win
const LANE_DWELL := 0.25           # seconds of looking aside before the first step
const LANE_REPEAT := 0.60          # seconds between further steps while you keep looking aside
const LANE_HEAD_GAIN := 0.012      # screen fraction per degree of head turn: turning toward where you want to go helps the eyes
const STEER_SCALE_MIN := 0.10       # STEER control: a look this far (screen fraction) from your own centre is full steering at most; never more sensitive than this
const STEER_SCALE_MAX := 0.30
const ZONE_FLOOR := 0.02
const LANE_ZONE_MAX := 0.20
const LANE_COMMIT_MIN := 55.0
const LANE_COMMIT_T := 2.2         # seconds before a wall that its lane is locked
const LANE_GRACE := 1.5            # seconds the line is held after tracking is lost
const LANE_MIN_SPEED := 12.0
const LANE_MAX_SPEED := 36.0
const CAL_PTS := [0.5, 0.1, 0.9]

var player: PlayerController
var cam: Camera3D

# sled state
var spos: Vector3 = Vector3.ZERO
var vel: Vector2 = Vector2(0.0, -10.0)       # horizontal velocity (x, z); downhill is -z
var vy: float = 0.0
var heading: float = 0.0
var grounded: bool = true
var air_t: float = 0.0
var steer: float = 0.0
var nod_p: float = 0.0
var nod_v: float = 0.0
var energy: float = 0.0
var tucking: bool = false
var braking: bool = false
var gliding: bool = false
var slamming: bool = false
var slam_from: float = 0.0
var pop_cd: float = 0.0
var hurt_t: float = 0.0
var crash_log: Array[String] = []

# scoring
var score: int = 0
var groove: float = 1.0
var chain: int = 0
var rows_passed: int = 0
var crashes: int = 0
var jumps: int = 0
var best_air: float = 0.0
var diff: float = 0.15
var kick_interest: float = 0.0
var reveals_by_eye: int = 0

var _rng := RandomNumberGenerator.new()
var _rows: Dictionary = {}
var _chunks: Dictionary = {}
var _kickers: Array[Dictionary] = []
var _next_j: int = 0
var _good_x: float = 0.0
var _hud: Control
var _toasts: Array[Dictionary] = []
var _age: float = 0.0
var _shake: float = 0.0
var _fov_punch: float = 0.0
var _flash: float = 0.0
var _cdir: Vector2 = Vector2(0.0, -1.0)
var _gh_prev: float = 0.0
var _sled: Node3D
var _rider: Node3D
var _spray: CPUParticles3D
var _gaze_px: Vector2 = Vector2.ZERO
var _focus_gap: Dictionary = {}
var _eye_on: bool = false
# three-dot eye setup (centre, left, right): maps the raw eye signal to screen x
var _cal: int = 0                # 0 not started, 1 running, 2 done
var _cal_i: int = 0
var _cal_t: float = 0.0
var _cal_samples: Array = [[], [], []]
var _cal_ok: bool = false
var _cal_slope: float = 0.0
var _cal_mid: float = 0.0
var _gx: float = 0.5
var _clock: float = 0.0
var _lock: Dictionary = {}
var _coach_text: String = ""
var _coach_t: float = 0.0
var _coach_good: bool = false
var _lock_row: Dictionary = {}
# eye tuning (saved on the device; ?dwell= ?assist= ?pad= in the address override)
var _dwell_t: float = FOCUS_TIME
var _assist: float = ASSIST
var _pad_scale: float = 1.0
var _cal_sigma: float = 0.03          # screen-fraction noise measured during the three-dot setup
var _jit: float = 0.0                 # live jitter of the gaze point, screen fraction
var _tune_open: bool = false
var _tune_btns: Array = []
var lane_mode: bool = true
var _lane: int = 1                 # committed lane (0 left, 1 centre, 2 right)
var _lane_cand: int = 1
var _lane_cand_t: float = 0.0
var lane_ctl: int = 3                  # 3 = SEEK: your gaze picks the nearest gate and the board carves through it (default); 2 = STEER: continuous gaze offset; 1 = SIDE; 0 = GATE
var _gate_row: Dictionary = {}
const GATE_ROW_MIN := 22.0             # choose among the gates of the first wall at least this far ahead (near gates are wide apart on screen)
var _look_lane: int = 1            # lane your eyes are pointing at (committed lane + the way you look)
var _look_dir: int = 0             # -1 looking left of the dead zone, +1 right, 0 middle
var _step_t: float = 0.0
var _steer_gaze: float = 0.0              # -1..1 continuous steering from the gaze (STEER control)
var _steer_scale: float = 0.2
var steer_curve: float = 1.0              # <1: small looks steer more (fine control near the middle is not wasted); 1 = linear
var steer_rate: float = 9.0               # how fast the steering follows the gaze (per second)
var steer_scale_min: float = STEER_SCALE_MIN
var steer_scale_const: float = 0.08        # a look this far from your centre is full steering (screen fraction). Fixed, NOT learned from your range: learning it cancelled your own steering
var _ref_x: float = 0.5                   # your centre: follows slow drift only while you look near it, so a look held to one side does not become the new centre
var _ref_init: bool = false
var _ref_y: float = 0.5
var reach: float = 1.3                      # how far a look moves the reticle / the control (1.3: your eyes cover the whole screen without straining)
var look_smooth: float = 0.07             # seconds: smooths the 12-30 readings a second into fluid motion at 60 fps
var _offs_s: float = 0.0
var eyes_only: bool = true                 # control from where the IRIS sits in the eye opening (a head turn does not move it), scaled to YOUR glance size
var _ex_sign: float = 1.0
var _ex_yaw: float = 0.0
var _ex_ref: float = 0.0
var sacc := Saccades.new()               # real looks (a jump that settles) as opposed to jitter and one-frame spikes
var _sacc_last_raw: float = 1.0e9
var _ex_slow: Array = []                 # a long, slow record of where the look sits (every 0.25 s, about 40 s): its median is the true centre of a long ride
var _ex_slow_t: float = 0.0
var vehicle_forced: bool = false         # the player said "I am on a bus / train": the centre re-learns faster
var _ex_init: bool = false
var _ex_dec: float = 0.0                   # lingered (smoothed) eye-in-head offset
var _ex_full: float = 0.02                 # the eye-in-head offset of your biggest normal glances: that maps to a full look at the outer gate
var _ex_noise: float = 0.002
var _ex_pin_t: float = 0.0                 # how long the look has sat beyond any normal glance: the centre is then wrong, not your eyes
var _ry_away: float = 0.0
var _ex_rec: bool = false


func _note(_msg: String) -> void:
	pass
var _ex_raw := PackedFloat32Array()
var _ex_abs := PackedFloat32Array()
var _ex_stat_t: float = 0.0
var _ex_c := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # running means / covariance of (eye-in-head, geometry gaze): checks the sign
var _offy_s: float = 0.0
var _gy_buf := PackedFloat32Array()
var _anchored: bool = false
var _fuse_seen: bool = false
var _steer_arm: float = 0.0              # 0..1: steering fades in after the first look at the middle, and after any change of the signal
var _seek_lane: int = 1                  # the lane of the gate nearest to your gaze (SEEK)
var _cursor_px: Vector2 = Vector2.ZERO    # where the reticle is drawn: your gaze relative to your own centre, exactly what the game uses
var _away_t: float = 0.0
var _gx_hist := PackedFloat32Array()
var _gx_long := PackedFloat32Array()      # 30 s of gaze: its median is the slow reference (a look held for seconds must not re-centre itself)
var _zone: float = LANE_ZONE            # dead-zone half width, learned from your own signal
var _gx_med: float = 0.5
var _off_now: float = 0.0
var _head_off: float = 0.0
var _yaw_ref: float = 0.0
var _yaw_ref_ok: bool = false
var _stat_t: float = 0.0
var head_assist: bool = true
var _gaze_trail: Array[Vector2] = []
var _trk_play_fps: float = 0.0
var _trk_t: float = 0.0
var _zone_scale: float = 1.0           # sensitivity: smaller = steps with a smaller look aside (set in the pause monitor)
var _was_fullscreen: bool = false
var _paused: bool = false
var _pause_btns: Array = []
var _pause_adv: bool = false              # the tracking monitor (tuning tools) sits behind ADVANCED; the plain pause screen is for players
var _stat_std: float = 0.0
var _noise_fix: float = 0.03
var _stat_p5: float = 0.5
var _stat_p95: float = 0.5
var _copy_note: String = ""
var _ui_msec: int = 0
var _step_first: bool = true
var _target_row: Dictionary = {}
var _lane_good: int = 1            # lane of the safe route in the newest row
var _grace_t: float = 0.0
var _steer_s: float = 0.0
var _pick_best: Dictionary = {}
var _pick_row: Dictionary = {}
var coins_got: int = 0
var best_flow: float = 1.0
var _minutes: int = 0
var _calm_said: bool = false
var _coin_mesh: SphereMesh
var _coin_mat: StandardMaterial3D

var _m_cone: Mesh
var _m_trunk: CylinderMesh
var _m_rock: Mesh
var _m_rock_snow: Mesh
var _m_flag: Mesh
var _m_shadow: Mesh
var _m_shadow_mat: StandardMaterial3D
var _sh_xf: Array[Transform3D] = []
var _sh_col := PackedColorArray()
var _mtn: MeshInstance3D
var _m_bank: BoxMesh
var _m_post: CylinderMesh
var _m_bar: BoxMesh
var veg_range: float = 0.0               # 0 = trees and rocks are drawn as far as you can see; the speed governor shortens it
var _veg_theme: Material                  # a theme's finish for trees and rocks (null = the plain vertex-colour one)
var _m_veg: StandardMaterial3D
var _m_ground: Material
var _kind_mat: Dictionary = {}


func setup(p_player: PlayerController) -> void:
	name = "DownhillRig"
	player = p_player
	_rng.seed = 424242
	_load_tune()
	GazeProvider.bias.reset()
	GazeProvider.coach.reset()
	GazeProvider.bias.exp_span = Vector2.ZERO if lane_mode else Vector2(0.6, 0.0)      # lane mode: NO spread-based stretching (it multiplies noise by up to 3x when you hold your gaze on the middle)
	_make_assets()
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.2
	cam.far = 1600.0
	add_child(cam)
	cam.make_current()
	spos = Vector3(0.0, terrain_h(0.0, 0.0), 0.0)
	_gh_prev = spos.y
	vy = vel.y * SLOPE
	_build_sled()
	_build_mountains()
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)
	GazeProvider.recentred.connect(_on_recentre)
	while float(_next_j) * ROW_GAP < AHEAD:
		_gen_segment(_next_j)
		_next_j += 1
	_place_camera(1.0, true)


# --------------------------------------------------------------------------
# Terrain: one function the physics, the meshes and the trees all agree on
# --------------------------------------------------------------------------
func terrain_h(x: float, z: float) -> float:
	var h := z * SLOPE
	h += 2.2 * sin(z * 0.031 + 1.3) * cos(x * 0.045) + 1.2 * sin(z * 0.011 - x * 0.02)
	h += 1.5 * sin(z * 0.045 + x * 0.025 + 0.7) * sin(x * 0.03 - z * 0.02)
	var ax := absf(x) - W_HALF
	if ax > 0.0:
		h += 0.0085 * ax * ax              # the corridor sits in a valley: the sides climb into hills
	for k in _kickers:
		var kz: float = k["z"]
		if z > kz + 1.0 or z < kz - float(k["len"]) - 1.0:
			continue
		var u := (kz - z) / float(k["len"])
		if u < 0.0 or u >= 1.0:
			continue
		var half: float = float(k["w"]) * 0.5
		var lat := 1.0 - smoothstep(half - 3.0, half, absf(x - float(k["x"])))
		h += float(k["rise"]) * u * u * lat
	return h


func _grad(x: float, z: float) -> Vector2:
	var e := 0.6
	return Vector2((terrain_h(x + e, z) - terrain_h(x - e, z)) / (2.0 * e), (terrain_h(x, z + e) - terrain_h(x, z - e)) / (2.0 * e))


func _make_assets() -> void:
	_m_cone = _make_tree_mesh()
	_m_trunk = CylinderMesh.new()
	_m_trunk.top_radius = 0.28
	_m_trunk.bottom_radius = 0.34
	_m_trunk.height = 1.4
	_m_trunk.radial_segments = 5
	_m_trunk.rings = 1
	_m_rock = _make_rock_mesh()
	var rs := SphereMesh.new()
	rs.radius = 1.5
	rs.height = 2.4
	rs.radial_segments = 8
	rs.rings = 4
	_m_rock_snow = rs
	_m_flag = _make_flag_mesh()
	var sc := CylinderMesh.new()
	sc.top_radius = 1.0
	sc.bottom_radius = 1.0
	sc.height = 0.02
	sc.radial_segments = 10
	sc.rings = 1
	_m_shadow = sc
	_m_shadow_mat = StandardMaterial3D.new()
	_m_shadow_mat.vertex_color_use_as_albedo = true
	_m_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_m_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_shadow_mat.albedo_color = Color.WHITE
	_m_bank = BoxMesh.new()
	_m_post = CylinderMesh.new()
	_m_post.top_radius = 0.28
	_m_post.bottom_radius = 0.28
	_m_post.height = 5.0
	_m_post.radial_segments = 6
	_m_post.rings = 1
	_m_bar = BoxMesh.new()
	_m_veg = StandardMaterial3D.new()
	_m_veg.vertex_color_use_as_albedo = true
	_m_veg.roughness = 1.0
	_m_veg.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m_veg.metallic_specular = 0.0
	var gsh := Shader.new()
	gsh.code = GROUND_SHADER
	var gm := ShaderMaterial.new()
	gm.shader = gsh
	_m_ground = gm
	for kind in ["open", "tight", "hop", "trap", "cycle", "late", "shut"]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _kind_color(kind)
		_kind_mat[kind] = m
	var wall := StandardMaterial3D.new()
	wall.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall.albedo_color = Color(1.0, 0.25, 0.2, 0.28)
	wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	_kind_mat["trapwall"] = wall


func _kind_color(kind: String) -> Color:
	match kind:
		"hop":
			return Color(1.0, 0.85, 0.2)
		"trap":
			return Color(1.0, 0.3, 0.25)
		"tight":
			return Color(0.4, 1.0, 0.7)
		"cycle":
			return Color(0.75, 0.55, 1.0)
		"shut":
			return Color(1.0, 0.3, 0.25)
	return Color(0.3, 0.9, 1.0)


func _kind_label(kind: String) -> String:
	match kind:
		"hop":
			return "HOP"
		"trap":
			return "DEAD END"
		"tight":
			return "TIGHT"
	return "OPEN"


# --------------------------------------------------------------------------
# Course generation: a forest wall every ROW_GAP metres with several openings, only some of them real
# --------------------------------------------------------------------------
func _gen_segment(j: int) -> void:
	var z0 := -ROW_GAP * float(j)
	var row: Dictionary = {"j": j, "z": z0 - 78.0, "gaps": [], "obs": PackedFloat32Array(), "banks": [], "nodes": [],
		"passed": false, "crash": false, "has_row": j >= 1}
	var cones: Array[Transform3D] = []
	var cone_cols := PackedColorArray()
	var trunks: Array[Transform3D] = []
	var trunk_cols := PackedColorArray()
	var rocks: Array[Transform3D] = []
	var rock_cols := PackedColorArray()
	var srocks: Array[Transform3D] = []
	var srock_cols := PackedColorArray()
	var flags: Array[Transform3D] = []
	var flag_cols := PackedColorArray()
	if row["has_row"]:
		var rz: float = row["z"]
		var prev_x := _good_x
		_good_x = clampf(_good_x + _rng.randf_range(-1.0, 1.0) * (16.0 + 12.0 * diff), -44.0, 44.0)
		var gaps: Array = row["gaps"]
		# the way through is always one of: plain opening, tight opening, or a gate that opens late
		var rr := _rng.randf()
		var gk := "open"
		if rr < 0.05 + 0.25 * diff:
			gk = "tight"
		elif rr < 0.30 + 0.25 * diff:
			gk = "late"
		var gw0 := 6.5 if gk == "tight" else _rng.randf_range(11.0, 14.0)
		gaps.append(_mk_gap(_good_x, gw0, gk, true))
		var extra := 1 + (1 if diff > 0.35 and _rng.randf() < 0.7 else 0) + (1 if diff > 0.7 and _rng.randf() < 0.6 else 0)
		for e in extra:
			for attempt in 12:
				var ex := _rng.randf_range(-48.0, 48.0)
				var ok := true
				for g in gaps:
					if absf(ex - float(g["x"])) < 24.0:
						ok = false
				if ok:
					gaps.append(_mk_gap(ex, _rng.randf_range(10.0, 14.0), _extra_kind(), false))
					break
		if lane_mode:
			_lane_gaps(row, gaps, j)
		# the wall: two staggered lines of trees and boulders, skipping the openings
		var obs: PackedFloat32Array = row["obs"]
		for line in (0 if lane_mode else 2):
			var lz := rz - 2.9 * float(line)
			var k := 0
			while true:
				var x := -W_HALF + (float(k) + 0.5 * float(line)) * 3.7 + _rng.randf_range(-0.3, 0.3)
				k += 1
				if x > W_HALF:
					break
				var inside := false
				for g in gaps:
					if absf(x - float(g["x"])) < float(g["w"]) * 0.5 + (2.6 if lane_mode else 1.2):
						inside = true
				if inside:
					continue
				if _rng.randf() < 0.22:
					_add_rock(rocks, rock_cols, obs, x, lz + _rng.randf_range(-0.5, 0.5), _rng.randf_range(1.0, 1.5), Color(0.55, 0.58, 0.64), 1.0)
				else:
					_add_tree(cones, cone_cols, trunks, trunk_cols, obs, x, lz + _rng.randf_range(-0.5, 0.5), _rng.randf_range(0.8, 1.25), true)
		# dead-end pockets (camouflaged in snow colours) and hop banks
		for g in gaps:
			var gx: float = g["x"]
			var gw: float = g["w"]
			if g["kind"] == "trap":
				var side := gw * 0.5 + 1.7
				var zz := rz - 3.0
				while zz > rz - 28.0:
					_add_rock(srocks, srock_cols, obs, gx - side, zz, 1.5, Color(0.9, 0.94, 1.0), 1.0)
					_add_rock(srocks, srock_cols, obs, gx + side, zz, 1.5, Color(0.9, 0.94, 1.0), 1.0)
					zz -= 3.0
				var cx := gx - side
				while cx <= gx + side + 0.1:
					_add_rock(srocks, srock_cols, obs, cx, rz - 28.0, 1.6, Color(0.92, 0.95, 1.0), 1.3)
					cx += 3.0
			elif g["kind"] == "hop":
				(row["banks"] as Array).append({"x": gx, "w": gw, "z": rz - 0.6})
				var bank := MeshInstance3D.new()
				bank.mesh = _m_bank
				bank.scale = Vector3(gw, 1.1, 2.4)
				bank.material_override = _flat_mat(Color(0.88, 0.93, 1.0))
				add_child(bank)
				bank.global_position = Vector3(gx, terrain_h(gx, rz - 0.6) + 0.45, rz - 0.6)
				(row["nodes"] as Array).append(bank)
			g["marker"] = _make_marker(g, rz)
			for fs in [-1.0, 1.0]:
				var fx: float = gx + float(fs) * (gw * 0.5 + 1.0)
				flags.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25)), Vector3(fx, terrain_h(fx, rz), rz)))
				flag_cols.append(FLAG_COLS[_rng.randi() % 3])
			if g["kind"] == "cycle" or g["kind"] == "late" or g["kind"] == "shut":
				g["door"] = _make_door(g, rz, row)
		# a drifting snow screen hides part of the wall until you are nearly there
		if lane_mode:
			_lane_extras(row, gaps, prev_x, rz, j)
		elif _rng.randf() < 0.3 + 0.35 * diff:
			_make_screen(row, float((gaps[_rng.randi() % gaps.size()] as Dictionary)["x"]) + _rng.randf_range(-6.0, 6.0), rz)
		# a kicker on the line between the last opening and this one, more often if the player stares at jumps
		var kx := clampf(lerpf(prev_x, _good_x, 0.6), -46.0, 46.0)
		var clear := true
		if _rows.has(j - 1):
			for pg in (_rows[j - 1] as Dictionary)["gaps"]:
				if pg["kind"] == "trap" and absf(kx - float(pg["x"])) < 24.0:
					clear = false
		if clear and _rng.randf() < 0.35 + 0.45 * clampf(kick_interest / 8.0, 0.0, 1.0):
			_kickers.append({"x": kx, "z": z0 - 12.0, "len": 14.0, "w": 14.0, "rise": _rng.randf_range(1.5, 2.1)})
	# forest on both sides (visual only)
	for side in [-1.0, 1.0]:
		for i in 22:
			var sx: float = float(side) * (W_HALF + 2.5 + _rng.randf_range(0.0, 70.0))
			_add_tree(cones, cone_cols, trunks, trunk_cols, PackedFloat32Array(), sx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(0.9, 1.6), false)
	for side2 in [-1.0, 1.0]:
		for ci in 2:
			var cxx: float = float(side2) * (W_HALF + _rng.randf_range(8.0, 36.0))
			_add_rock(rocks, rock_cols, PackedFloat32Array(), cxx, z0 - _rng.randf_range(0.0, ROW_GAP), _rng.randf_range(7.0, 14.0), Color.WHITE, _rng.randf_range(0.9, 1.5), false)
	_add_mm(row, _m_shadow, _sh_xf, _sh_col, _m_shadow_mat)
	_sh_xf.clear()
	_sh_col = PackedColorArray()
	_add_mm(row, _m_cone, cones, cone_cols)
	_add_mm(row, _m_trunk, trunks, trunk_cols)
	_add_mm(row, _m_rock, rocks, rock_cols)
	_add_mm(row, _m_rock_snow, srocks, srock_cols)
	_add_mm(row, _m_flag, flags, flag_cols)
	_rows[j] = row
	_chunks[j] = _build_chunk(j)


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _add_tree(cones: Array[Transform3D], cone_cols: PackedColorArray, trunks: Array[Transform3D], trunk_cols: PackedColorArray,
		obs: PackedFloat32Array, x: float, z: float, s: float, solid: bool) -> void:
	var h := terrain_h(x, z)
	var sy := s * _rng.randf_range(0.9, 1.35)
	cones.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, sy, s)), Vector3(x, h, z)))
	cone_cols.append(Color.WHITE.darkened(_rng.randf_range(0.0, 0.16)))
	trunks.append(Transform3D(Basis.IDENTITY, Vector3(x, h + 0.7, z)))
	_push_shadow(x, z, 9.0 * sy, 3.4 * s)
	trunk_cols.append(Color(0.34, 0.24, 0.18))
	if solid:
		obs.append(x)
		obs.append(z)
		obs.append(1.35 * s)
		obs.append(0.0)


func _add_rock(rocks: Array[Transform3D], cols: PackedColorArray, obs: PackedFloat32Array, x: float, z: float, s: float, c: Color, tall: float, solid: bool = true) -> void:
	var h := terrain_h(x, z)
	rocks.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * tall, s)), Vector3(x, h + 0.7 * s * tall, z)))
	cols.append(c if c.get_luminance() > 0.85 else Color.WHITE.darkened(_rng.randf_range(0.0, 0.14)))
	_push_shadow(x, z, minf(5.0 * s * tall, 38.0), 2.6 * s)
	if solid:
		obs.append(x)
		obs.append(z)
		obs.append(1.3 * s)
		obs.append(1.0)


func _add_mm(row: Dictionary, mesh: Mesh, xf: Array[Transform3D], cols: PackedColorArray, mat: Material = null) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat if mat != null else (_veg_theme if _veg_theme != null else _m_veg)
	inst.extra_cull_margin = 40.0
	if veg_range > 0.0:
		inst.visibility_range_end = veg_range
	add_child(inst)
	(row["nodes"] as Array).append(inst)


## Posts + a bar over the opening. Hidden until the opening is resolved by looking at it (or by getting close).
func _make_marker(g: Dictionary, rz: float) -> Node3D:
	var gx: float = g["x"]
	var gw: float = g["w"]
	var kind: String = g["kind"]
	var m := Node3D.new()
	add_child(m)
	m.global_position = Vector3(gx, 0.0, rz)
	m.visible = false
	var mat: Material = _kind_mat[kind]
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * (gw * 0.5 + 0.3)
		var post := MeshInstance3D.new()
		post.mesh = _m_post
		post.material_override = mat
		m.add_child(post)
		post.global_position = Vector3(gx + px, terrain_h(gx + px, rz) + 2.5, rz)
	var bar := MeshInstance3D.new()
	bar.mesh = _m_bar
	bar.scale = Vector3(gw + 0.6, 0.4, 0.4)
	bar.material_override = mat
	m.add_child(bar)
	bar.global_position = Vector3(gx, terrain_h(gx, rz) + 5.2, rz)
	if kind == "trap":
		var wall := MeshInstance3D.new()
		wall.mesh = _m_bar
		wall.scale = Vector3(gw, 4.6, 0.15)
		wall.material_override = _kind_mat["trapwall"]
		m.add_child(wall)
		wall.global_position = Vector3(gx, terrain_h(gx, rz) + 2.4, rz)
	return m


func _chunk_tint(_j: int) -> Color:
	return Color.WHITE


func _ground_color(_j: int, _x: float, _z: float, c: Color) -> Color:
	return c


func _build_chunk(j: int) -> MeshInstance3D:
	const NX := 60
	const NZ := 34
	var z0 := -ROW_GAP * float(j)
	var dz := ROW_GAP / float(NZ)
	var dx := (GROUND_HALF * 2.0) / float(NX)
	var heights := PackedFloat32Array()
	for iz in range(-1, NZ + 2):
		var z := z0 - dz * float(iz)
		for ix in NX + 1:
			heights.append(terrain_h(-GROUND_HALF + dx * float(ix), z))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var stride := NX + 1
	for iz in NZ + 1:
		var z := z0 - dz * float(iz)
		for ix in NX + 1:
			var x := -GROUND_HALF + dx * float(ix)
			var row_i := (iz + 1) * stride
			var h: float = heights[row_i + ix]
			var xl: int = maxi(ix - 1, 0)
			var xr: int = mini(ix + 1, NX)
			var gx: float = (heights[row_i + xr] - heights[row_i + xl]) / (dx * float(xr - xl))
			var gz: float = (heights[row_i - stride + ix] - heights[row_i + stride + ix]) / (2.0 * dz)
			verts.append(Vector3(x, h, z))
			norms.append(Vector3(-gx, 1.0, -gz).normalized())
			var t := 0.5 + 0.5 * sin(x * 0.07 + z * 0.05) * sin(z * 0.021)
			var stripe := 0.5 + 0.5 * sin(z * 0.9 + sin(x * 0.2) * 2.0)
			var c := Color(0.97, 0.98, 1.0).lerp(Color(0.8, 0.86, 0.97), clampf(0.35 * t + 0.1 * stripe, 0.0, 1.0))
			if absf(x) > W_HALF:
				c = c.lerp(Color(0.8, 0.84, 0.88), 0.3)
			c = _ground_color(j, x, z, c)
			cols.append(c * _chunk_tint(j))
	for iz in NZ:
		for ix in NX:
			var a := iz * stride + ix
			idx.append_array(PackedInt32Array([a, a + 1, a + stride, a + 1, a + stride + 1, a + stride]))
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
	mi.material_override = _m_ground
	mi.extra_cull_margin = 30.0
	add_child(mi)
	return mi


func _build_sled() -> void:
	_sled = Node3D.new()
	add_child(_sled)
	var board := Roster.mi(_sled, Roster.box(Vector3(0.7, 0.12, 1.9)), Vector3(0, 0.06, 0), Color(0.15, 0.3, 0.75))
	board.name = "Board"
	_rider = Node3D.new()
	_sled.add_child(_rider)
	_rider.position = Vector3(0, 0.12, 0)
	Roster.mi(_rider, Roster.cyl(0.26, 0.3, 1.1), Vector3(0, 0.75, 0), Color(0.95, 0.45, 0.15))
	Roster.mi(_rider, Roster.sphere(0.27), Vector3(0, 1.5, 0), Color(0.98, 0.8, 0.65))
	Roster.mi(_rider, Roster.sphere(0.3, 0.7), Vector3(0, 1.62, 0), Color(0.15, 0.15, 0.2))
	_spray = CPUParticles3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.13
	pm.height = 0.26
	pm.radial_segments = 6
	pm.rings = 3
	_spray.mesh = pm
	_spray.material_override = _flat_mat(Color(1, 1, 1))
	_spray.amount = 36
	_spray.lifetime = 0.5
	_spray.direction = Vector3(0, 1, 0.6)
	_spray.spread = 30.0
	_spray.initial_velocity_min = 1.0
	_spray.initial_velocity_max = 3.0
	_spray.scale_amount_min = 0.3
	_spray.scale_amount_max = 0.6
	_spray.gravity = Vector3(0, -6.0, 0)
	_spray.emitting = false
	_sled.add_child(_spray)
	_spray.position = Vector3(0, 0.2, 0.9)


# --------------------------------------------------------------------------
# Physics: slope, momentum, grip, drag, jumps
# --------------------------------------------------------------------------
func _eye_mode() -> bool:
	match GazeProvider.backend:
		GazeProvider.Backend.MOUSE:
			return not Game.touch_mode
		GazeProvider.Backend.CAMERA:
			return GazeProvider._camera_fresh() and GazeProvider.confidence > 0.3
		GazeProvider.Backend.SCRIPTED:
			return true                      # tests pin the gaze point
	return false


func _physics_process(delta: float) -> void:
	if _paused:
		return
	_age += delta
	if _cal == 1:
		return                      # the run waits while you set up your eyes
	var ns := GazeProvider.nod_state(delta)
	nod_p = ns.x
	nod_v = ns.y
	var pk := GazeProvider.peek_offset(delta)
	var key := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	steer = clampf(pk.x / 1.8 + key + (_steer_gaze if lane_ctl == 2 else (_seek_term() if lane_ctl == 3 else 0.0)), -1.0, 1.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	pop_cd = maxf(pop_cd - delta, 0.0)
	_eye_on = _eye_mode()
	_clock += delta
	if not _lock.is_empty() and (_lock_row.is_empty() or _lock_row["passed"]):
		_lock = {}
		_lock_row = {}
	if (_eye_on or (lane_mode and _grace_t > 0.0)) and not _lock.is_empty() and lane_ctl < 2:
		# the path your eyes set pulls the board toward it; leaning harder takes over
		var want := clampf((float(_lock["x"]) - (spos.x + vel.x * (0.45 if lane_mode else 0.6))) / (20.0 if lane_mode else 16.0), -0.7 if lane_mode else -1.0, 0.7 if lane_mode else 1.0)      # lane mode: long gentle arcs, never full lock
		steer = clampf(steer + (1.0 if lane_mode else _assist) * _assist_conf() * want * (1.0 - 0.6 * absf(steer)), -1.0, 1.0)

	if lane_mode:
		_steer_s = lerpf(_steer_s, steer, 1.0 - exp(-(steer_rate if lane_ctl >= 2 else 4.5) * delta))      # long, smooth carves: no jerks (faster for continuous gaze steering)
		steer = _steer_s
	var tuck := nod_p < -0.10
	var sit_up := nod_p > 0.12
	tucking = tuck and grounded
	braking = sit_up and grounded
	gliding = sit_up and not grounded
	if tucking:
		energy = minf(energy + 40.0 * clampf((-nod_p - 0.10) / 0.2, 0.0, 1.0) * delta, 100.0)

	# heading follows the lean with a short spring (the board edge), the velocity follows the board through grip
	var theta_t := steer * THETA_MAX
	heading += (theta_t - heading) * (1.0 - exp(-delta / (0.2 if grounded else 0.35)))
	var fwd := Vector2(sin(heading), -cos(heading))
	var right := Vector2(cos(heading), sin(heading))

	if lane_mode and grounded:
		var spd := vel.length()
		if spd < LANE_MIN_SPEED:
			vel += (vel / spd if spd > 0.05 else fwd) * (LANE_MIN_SPEED - spd) * 1.2 * delta     # never stalls
		elif spd > LANE_MAX_SPEED:
			vel -= vel / spd * (spd - LANE_MAX_SPEED) * 0.8 * delta                           # never gets frantic
	var prev := spos
	var g := _grad(spos.x, spos.z)
	if grounded:
		vel += -G * g / (1.0 + g.length_squared()) * delta
		var sp := vel.length()
		var drag := DRAG * (0.55 if tucking else 1.0) + (0.0035 if braking else 0.0)
		var fr := 0.22 + (1.4 if braking else 0.0)
		if sp > 0.01:
			var dec := minf((fr + drag * sp * sp) * delta, sp)
			vel -= vel / sp * dec
		var old_sp := vel.length()
		var along := vel.dot(fwd)
		var lat := vel.dot(right)
		var lat_new := lat * exp(-GRIP * (0.75 if tucking else 1.0) * delta)
		# redirecting momentum costs some speed, but a clean carve keeps most of it (the rest is lost to the edge)
		along += absf(lat - lat_new) * 0.6 * signf(along if absf(along) > 0.01 else 1.0)
		vel = fwd * along + right * lat_new
		if vel.length() > old_sp:
			vel = vel.normalized() * old_sp          # redirecting momentum can never create speed
		if nod_v > 1.1 and pop_cd <= 0.0:
			_pop()
	else:
		var sp2 := vel.length()
		if sp2 > 0.01:
			vel -= vel / sp2 * minf(DRAG * 0.4 * sp2 * sp2 * delta, sp2)
		vel += right * steer * 3.0 * delta
		air_t += delta
		if nod_v < -1.6 and not slamming and spos.y - terrain_h(spos.x, spos.z) > 2.0:
			slamming = true
			slam_from = spos.y - terrain_h(spos.x, spos.z)
			vy = minf(vy, -30.0)
			vel *= 0.85
			_fov_punch = 10.0
			Game.sfx(&"whoosh")

	spos.x += vel.x * delta
	spos.z += vel.y * delta
	spos.x = clampf(spos.x, -(W_HALF - 2.5), W_HALF - 2.5) if absf(spos.x) > W_HALF - 2.5 else spos.x
	if absf(spos.x) >= W_HALF - 2.5:
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
			jumps += 1
		else:
			spos.y = gh
			vy = vg
	else:
		var ge := G * (0.5 if gliding else 1.0)
		vy -= ge * delta
		spos.y += vy * delta
		if spos.y <= gh:
			_land(maxf(gvy - vy, 0.0), gh, gvy)
	_gh_prev = gh

	_update_doors()
	_collide()
	_collide_doors()
	_collect_coins()
	_update_rows()
	if int(float(_next_j) * ROW_GAP) < int(-spos.z + AHEAD):
		_gen_segment(_next_j)
		_next_j += 1
	_cleanup()


func _pop() -> void:
	var gh := terrain_h(spos.x, spos.z)
	pop_cd = 0.4
	var v := 4.6 + 0.05 * energy
	grounded = false
	air_t = 0.0
	vy = vy + v
	spos.y = gh + 0.05
	energy = 0.0
	jumps += 1
	_fov_punch = 6.0
	Game.sfx(&"whoosh")


func _land(impact: float, gh: float, gvy: float) -> void:
	grounded = true
	spos.y = gh
	vy = gvy
	var t := air_t
	air_t = 0.0
	if slamming:
		slamming = false
		var kick := 3.0 + slam_from * 0.25
		vel += vel.normalized() * kick if vel.length() > 0.1 else Vector2.ZERO
		_shake = 0.8
		_flash = 0.5
		score += int((20.0 + slam_from * 4.0) * groove)
		Fx.shockwave(self, Vector3(spos.x, gh + 0.2, spos.z), 9.0, 0.0, 0.0, false, true, &"slam", null, Color(1.0, 0.9, 0.6, 0.5))
		Fx.confetti(self, Vector3(spos.x, gh + 0.6, spos.z), 40, 1.0)
		Game.sfx(&"boom")
		_toast("STOMP +%d m/s" % int(kick), Color(1.0, 0.8, 0.3))
		return
	if impact > 16.0:
		_crash("WIPEOUT!")
		return
	if t > 0.7:
		best_air = maxf(best_air, t)
		var pts := int(t * 60.0 * groove)
		if impact < 7.0:
			pts = int(pts * 1.5)
			_toast("AIR %.1fs  SMOOTH +%d" % [t, pts], Color(0.5, 1.0, 0.7))
			Game.sfx(&"coin")
		else:
			vel *= 0.92
			_toast("AIR %.1fs  rough +%d" % [t, pts], Color(1.0, 0.9, 0.5))
		score += pts
	elif impact > 9.0:
		vel *= 0.9


func _crash(msg: String) -> void:
	if hurt_t > 0.0:
		return
	crashes += 1
	var near := ""
	for kk in _rows:
		var rr: Dictionary = _rows[kk]
		if absf(float(rr["z"]) - spos.z) < 36.0 and rr["has_row"]:
			for gg in rr["gaps"]:
				near += " [%s x=%.0f w=%.0f%s]" % [gg["kind"], gg["x"], gg["w"], "*" if gg["good"] else ""]
	crash_log.append("%s at z=%.0f x=%.1f v=%.1f%s" % [msg, spos.z, spos.x, vel.length(), near])
	hurt_t = 0.5 if lane_mode else 1.0
	vel *= (0.6 if lane_mode else 0.35)
	chain = 0
	groove = 1.0
	energy *= 0.4
	_shake = 0.8
	_toast(msg, Color(1.0, 0.4, 0.35))
	Game.sfx(&"hurt")
	diff = clampf(diff - 0.10, 0.0, 1.0)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if absf(float(r["z"]) - spos.z) < 30.0:
			r["crash"] = true


func _collide() -> void:
	if hurt_t > 0.0:
		return
	var gh := terrain_h(spos.x, spos.z)
	var above := spos.y - gh
	for k in _rows:
		var r: Dictionary = _rows[k]
		var rz: float = r["z"]
		if not r["has_row"] or spos.z > rz + 6.0 or spos.z < rz - 34.0:
			continue
		var obs: PackedFloat32Array = r["obs"]
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
					var n := Vector2(dx, dz).normalized()
					spos.x = ox + n.x * (orad + SLED_R + 0.1)
					spos.z = oz + n.y * (orad + SLED_R + 0.1)
					if grounded:
						spos.y = terrain_h(spos.x, spos.z)
						_gh_prev = spos.y
					vel = vel.slide(n) * 0.4
					_crash("TREE!" if okind < 0.5 else "ROCK!")
					return
		for b in r["banks"]:
			if absf(spos.z - float(b["z"])) < 1.3 and absf(spos.x - float(b["x"])) < float(b["w"]) * 0.5 and above < 1.25:
				vel *= 0.3
				spos.z = float(b["z"]) + 1.4
				if grounded:
					spos.y = terrain_h(spos.x, spos.z)
					_gh_prev = spos.y
				_crash("SNOW BANK! pop over it")
				return


# --------------------------------------------------------------------------
# Openings: reveal by looking (or by closeness), score when you pass
# --------------------------------------------------------------------------
func _gap_screen(row: Dictionary, g: Dictionary) -> Dictionary:
	var gx: float = g["x"]
	var gw: float = g["w"]
	var rz: float = row["z"]
	var wp := Vector3(gx, terrain_h(gx, rz) + 1.8, rz)
	if cam.is_position_behind(wp):
		return {}
	var c := cam.unproject_position(wp)
	var e := cam.unproject_position(wp + Vector3(gw * 0.5, 0.0, 0.0))
	return {"c": c, "hw": absf(e.x - c.x)}


func _resolve(g: Dictionary, by_eye: bool, dist: float) -> void:
	if g["resolved"]:
		return
	g["resolved"] = true
	g["eye"] = by_eye
	g["eye_dist"] = dist
	if by_eye:
		reveals_by_eye += 1
	var m: Node3D = g["marker"]
	if m != null and is_instance_valid(m):
		m.visible = true


func _update_rows() -> void:
	var reveal := 170.0 if lane_mode else (EYE_REVEAL if _eye_on else PLAIN_REVEAL)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"]:
			continue
		var rz: float = r["z"]
		var dist := spos.z - rz
		if dist > 0.0 and dist < reveal:
			for g in r["gaps"]:
				if not _occluded(r, g):
					_resolve(g, false, dist)
		if not r["passed"] and spos.z <= rz:
			_pass_row(r)


func _pass_row(row: Dictionary) -> void:
	row["passed"] = true
	rows_passed += 1
	var chosen: Dictionary = {}
	for g in row["gaps"]:
		if absf(spos.x - float(g["x"])) <= float(g["w"]) * 0.5 + 1.2:
			chosen = g
	if chosen.is_empty():
		return
	if chosen["kind"] == "trap":
		_toast("DEAD END ahead!", Color(1.0, 0.45, 0.3))
		return
	if row["crash"]:
		return
	var margin := clampf(1.0 - absf(spos.x - float(chosen["x"])) / (float(chosen["w"]) * 0.5), 0.0, 1.0)
	var pts := 40 + int(30.0 * margin)
	if chosen["kind"] == "tight":
		pts += 40
		_toast("TIGHT LINE", Color(0.4, 1.0, 0.7))
	elif chosen["kind"] == "hop":
		pts += 30
	var eye_n := 0
	for g in row["gaps"]:
		if g["eye"]:
			eye_n += 1
	if eye_n >= 2 and chosen["eye"]:
		var sb := 20 * mini(eye_n - 1, 3)
		pts += sb
		_toast("SCOUTED +%d" % sb, Color(0.6, 0.9, 1.0))
	if chosen["eye"] and float(chosen["eye_dist"]) > 70.0:
		var lb := int(clampf((float(chosen["eye_dist"]) - 70.0) / 5.0, 0.0, 40.0))
		pts += lb
		_toast("LOOK-AHEAD +%d" % lb, Color(0.9, 0.8, 1.0))
	if chosen["kind"] == "late":
		pts += 50
		_toast("TRUSTED THE GATE", Color(0.4, 0.9, 1.0))
	elif chosen["kind"] == "cycle":
		pts += 40
		_toast("TIMED IT", Color(0.8, 0.6, 1.0))
	if is_same(chosen, _lock):
		pts += 25
		if not lane_mode:
			_toast("ON YOUR LINE", Color(0.6, 1.0, 0.6))
	chain += 1
	groove = 1.0 + 0.25 * minf(float(chain), 8.0)
	best_flow = maxf(best_flow, groove)
	score += int(float(pts) * groove)
	diff = clampf(diff + (0.025 if lane_mode else 0.06), 0.0, 0.7 if lane_mode else 1.0)
	Game.sfx(&"coin")


func _update_focus(delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	_gx = _eye_x()
	_gaze_px = Vector2(_gx * vs.x, GAZE_Y * vs.y)
	_gaze_trail.append(_cursor_px if (lane_ctl >= 2 and _cursor_px != Vector2.ZERO) else _gaze_px)
	if _gaze_trail.size() > 10:
		_gaze_trail.remove_at(0)
	if lane_mode:
		_lane_tick(delta, vs)
	var best: Dictionary = {}
	var best_row: Dictionary = {}
	if _eye_on:
		# Only the horizontal gaze is trusted (vertical eye tracking is weak and every opening sits near the
		# horizon anyway). Take the nearest wall that has an opening under your gaze, then the closest opening in it.
		var keys: Array = _rows.keys()
		keys.sort()                                  # row indices grow downhill, so the nearest row comes first
		for kk in keys:
			var r: Dictionary = _rows[kk]
			if not r["has_row"]:
				continue
			var dist := spos.z - float(r["z"])
			if dist < 8.0 or dist > 320.0:
				continue
			var row_best: Dictionary = {}
			var row_ratio := 1.0
			for g in r["gaps"]:
				if _occluded(r, g):
					continue
				var s2 := _gap_screen(r, g)
				if s2.is_empty():
					continue
				var c: Vector2 = s2["c"]
				var tol: float = float(s2["hw"]) + _pad() * vs.x
				var ratio := absf(_gaze_px.x - c.x) / tol
				if is_same(g, _focus_gap):
					ratio *= 0.75                       # stick with what you are already looking at
				if ratio < row_ratio:
					row_ratio = ratio
					row_best = g
			if not row_best.is_empty():
				best = row_best
				best_row = r
				break
		if lane_mode:
			best = _pick_best
			best_row = _pick_row
		# kickers: what the player likes to look at decides how many we build
		for kk2 in _kickers:
			var kz: float = kk2["z"]
			var kd := spos.z - kz
			if kd < 10.0 or kd > 240.0:
				continue
			var kp := Vector3(float(kk2["x"]), terrain_h(float(kk2["x"]), kz - 7.0) + 1.0, kz - 7.0)
			if not cam.is_position_behind(kp) and absf(_gaze_px.x - cam.unproject_position(kp).x) < 0.06 * vs.x:
				kick_interest = minf(kick_interest + delta, 20.0)
	for k in _rows:
		var r2: Dictionary = _rows[k]
		for g2 in r2["gaps"]:
			if is_same(g2, best):
				g2["dwell"] = minf(float(g2["dwell"]) + delta, _dwell_t)
				if float(g2["dwell"]) >= _dwell_t:
					if not g2["resolved"]:
						_resolve(g2, true, spos.z - float(best_row["z"]))
					if not lane_mode and not is_same(_lock, g2):
						_lock = g2                   # looking at a gate for a moment sets your line through it
						_lock_row = best_row
						Game.sfx(&"coin")
			else:
				g2["dwell"] = maxf(float(g2["dwell"]) - 0.5 * delta, 0.0)
	_focus_gap = best


# --------------------------------------------------------------------------
# Eye setup: look at three dots, map the raw eye signal to screen x
# --------------------------------------------------------------------------
func _maybe_start_cal() -> void:
	pass          # nothing to do: the eye mapping is automatic (see EyeBias), no dots


func _on_recentre() -> void:
	pass          # GazeProvider.recentre() already pins the automatic offset to the screen centre


## Pure: fit screen x (0.5 / 0.1 / 0.9) against the raw signal medians for the centre, left and right dots.
static func fit_gaze(cs: Array, ls: Array, rs: Array) -> Dictionary:
	if cs.size() < 6 or ls.size() < 6 or rs.size() < 6:
		return {"ok": false}
	var med := func(a: Array) -> float:
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2])
	var spread := func(a: Array, m: float) -> float:
		var t := 0.0
		for v in a:
			t += (float(v) - m) * (float(v) - m)
		return sqrt(t / float(a.size()))
	var c: float = med.call(cs)
	var l: float = med.call(ls)
	var r: float = med.call(rs)
	var mx := (c + l + r) / 3.0
	var sxx := (c - mx) * (c - mx) + (l - mx) * (l - mx) + (r - mx) * (r - mx)
	var sxy := (c - mx) * (CAL_PTS[0] - 0.5) + (l - mx) * (CAL_PTS[1] - 0.5) + (r - mx) * (CAL_PTS[2] - 0.5)
	var noise: float = (float(spread.call(cs, c)) + float(spread.call(ls, l)) + float(spread.call(rs, r))) / 3.0
	var span := absf(r - l)
	var monotone := (c - l) * (r - c) > 0.0          # centre must lie between the two edge readings
	if sxx < 1.0e-9 or span < 2.5 * noise or not monotone:
		return {"ok": false, "span": span, "noise": noise}
	return {"ok": true, "slope": sxy / sxx, "mid": mx, "span": span, "noise": noise}


func _eye_x() -> float:
	var x := GazeProvider.gaze.x
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		_jit = lerpf(_jit, clampf(absf(GazeProvider._geo_raw.x + GazeProvider.bias.bias.x - x), 0.0, 0.12), 0.03)
	_gx = clampf(x, 0.0, 1.0)
	return _gx


func _input(event: InputEvent) -> void:
	if true:
		if _pause_input(event):
			get_viewport().set_input_as_handled()
			return
		if lane_mode:
			if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
				var kc := (event as InputEventKey).keycode
				if kc == KEY_LEFT or kc == KEY_A:
					_lane_set(_lane - 1, true)
				elif kc == KEY_RIGHT or kc == KEY_D:
					_lane_set(_lane + 1, true)
			elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and not _eye_on:
				var tx := (event as InputEventScreenTouch).position.x / maxf(get_viewport().get_visible_rect().size.x, 1.0)
				_lane_set(0 if tx < 0.34 else (2 if tx > 0.66 else 1), true)
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_T:
			_tune_open = not _tune_open
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _tune_click((event as InputEventMouseButton).position):
				get_viewport().set_input_as_handled()
		return


func _toast(text: String, color: Color) -> void:
	_toasts.append({"text": text, "color": color, "t": 2.2})
	if _toasts.size() > 4:
		_toasts.remove_at(0)


func _cleanup() -> void:
	for k in _rows.keys():
		var r: Dictionary = _rows[k]
		if float(r["z"]) > spos.z + 90.0:
			for n in r["nodes"]:
				if is_instance_valid(n):
					(n as Node).queue_free()
			for g in r["gaps"]:
				var m: Variant = g["marker"]
				if is_instance_valid(m):
					(m as Node).queue_free()
			_rows.erase(k)
			if _chunks.has(k):
				var c: Variant = _chunks[k]
				if is_instance_valid(c):
					(c as Node).queue_free()
				_chunks.erase(k)
	for i in range(_kickers.size() - 1, -1, -1):
		if float(_kickers[i]["z"]) > spos.z + 140.0:
			_kickers.remove_at(i)


func cleanup() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		for n in r["nodes"]:
			if is_instance_valid(n):
				(n as Node).queue_free()
		for g in r["gaps"]:
			var m: Variant = g["marker"]
			if is_instance_valid(m):
				(m as Node).queue_free()
	_rows.clear()
	for k in _chunks:
		var c: Variant = _chunks[k]
		if is_instance_valid(c):
			(c as Node).queue_free()
	_chunks.clear()


# --------------------------------------------------------------------------
# Camera + visuals + HUD
# --------------------------------------------------------------------------
func _place_camera(delta: float, snap: bool = false) -> void:
	var sp := vel.length()
	var vdir := vel / sp if sp > 1.0 else Vector2(0.0, -1.0)
	_cdir = (_cdir.lerp(vdir, 1.0 - exp(-3.0 * delta))).normalized()
	var back := Vector3(_cdir.x, 0.0, _cdir.y) * -8.0
	var target := spos + back + Vector3(0.0, 4.6 + (0.5 if not grounded else 0.0), 0.0)
	target.y = maxf(target.y, terrain_h(target.x, target.z) + 2.2)
	if snap:
		cam.global_position = target
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	var ahead := spos + Vector3(_cdir.x, 0.0, _cdir.y) * 16.0
	ahead.y = terrain_h(ahead.x, ahead.z) + 1.0
	if (ahead - cam.global_position).length() > 0.5:
		cam.look_at(ahead, Vector3.UP)
	cam.basis = cam.basis * Basis(Vector3(0, 0, 1), -steer * 0.14)
	_shake = maxf(_shake - 1.6 * delta, 0.0)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
	_fov_punch = maxf(_fov_punch - 24.0 * delta, 0.0)
	cam.fov = clampf(68.0 + (sp - 18.0) * 0.7, 66.0, 100.0) + _fov_punch


func _process(delta: float) -> void:
	_watch_fullscreen()
	_watch_trk(delta)
	if _paused:
		_eye_on = _eye_mode()
	_place_camera(delta)
	_animate_doors(delta)
	if _mtn != null:
		_mtn.global_position = Vector3(spos.x, spos.y - 160.0, spos.z)
	_maybe_start_cal()
	_update_focus(delta)
	# sled orientation: follow the ground normal, lean into the turn, tuck low
	var g := _grad(spos.x, spos.z)
	var n := Vector3(-g.x, 1.0, -g.y).normalized() if grounded else Vector3.UP.lerp(Vector3(-g.x, 1.0, -g.y).normalized(), 0.35).normalized()
	var f := Vector3(sin(heading), 0.0, -cos(heading))
	f = (f - n * f.dot(n)).normalized()
	_sled.global_transform = Transform3D(Basis(f.cross(n).normalized(), n, -f), spos)
	_rider.rotation.z = lerpf(_rider.rotation.z, -steer * 0.45, 1.0 - exp(-10.0 * delta))
	_rider.scale.y = lerpf(_rider.scale.y, 0.62 if tucking else (1.12 if braking else 1.0), 1.0 - exp(-8.0 * delta))
	_sled.visible = hurt_t <= 0.0 or int(_age * 14.0) % 2 == 0
	_spray.emitting = grounded and vel.length() > 8.0
	for t in _toasts:
		t["t"] = float(t["t"]) - delta
	while not _toasts.is_empty() and float(_toasts[0]["t"]) <= 0.0:
		_toasts.remove_at(0)
	_flash = maxf(_flash - 2.0 * delta, 0.0)
	if lane_mode:
		if not _calm_said and _age > 1.5:
			_calm_said = true
			_toast("Settle in. Look where you want to go.", Color(0.9, 0.95, 1.0))
		if int(_age / 60.0) > _minutes:
			_minutes = int(_age / 60.0)
			_toast("%d min   %d coins   best flow x%.1f" % [_minutes, coins_got, best_flow], Color(1.0, 0.9, 0.5))
	if _eye_on and GazeProvider.backend == GazeProvider.Backend.CAMERA and _age > 6.0:
		var cm := GazeProvider.coach.message(GazeProvider._now())
		if cm != "":
			_coach_text = cm
			_coach_t = 4.5
		if GazeProvider.coach.take_good_event() and _coach_t > 0.0:
			_coach_text = "Good position"
			_coach_good = true
			_coach_t = 1.6
		elif _coach_t > 0.0 and not _coach_good:
			pass
	_coach_t = maxf(_coach_t - delta, 0.0)
	if _coach_t <= 0.0:
		_coach_good = false
	_hud.size = get_viewport().get_visible_rect().size
	_hud.queue_redraw()


func _hud_scale() -> float:
	var portrait := _hud.size.y > _hud.size.x * 1.05
	return 2.0 if portrait else (1.25 if Game.touch_mode else 1.0)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	var fs := int(float(size) * _hud_scale())
	_hud.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _ctext(font: Font, y: float, text: String, size: int, color: Color) -> void:
	var fs := int(float(size) * _hud_scale())
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_hud.draw_string_outline(font, Vector2(_hud.size.x * 0.5 - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, Vector2(_hud.size.x * 0.5 - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	var m := 24.0 * k
	if hurt_t > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.1, 0.1, 0.22 * hurt_t * (0.25 if lane_mode else 1.0)))
	if _flash > 0.0:
		_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, 0.3 * _flash))
	# gates you have read get a label; a ring fills while you look at one. Unread gates get nothing: you have to see them.
	for kk in _rows:
		var r: Dictionary = _rows[kk]
		if not r["has_row"]:
			continue
		var dist := spos.z - float(r["z"])
		if dist < 10.0 or dist > 330.0:
			continue
		if lane_mode and not (is_same(r, _pick_row) or is_same(r, _target_row)):
			continue
		for g in r["gaps"]:
			if _occluded(r, g):
				continue
			var sc := _gap_screen(r, g)
			if sc.is_empty():
				continue
			var c: Vector2 = sc["c"]
			var rad := 13.0 * k
			if g["resolved"]:
				var ok := _forecast(g, r) == 1
				var col := _kind_color(String(g["kind"])) if ok else Color(1.0, 0.35, 0.3)
				if g["kind"] == "hop":
					col = Color(1.0, 0.85, 0.2)
				_hud.draw_arc(c, rad, 0.0, TAU, 24, col, 3.0 * k)
				var lab := _gap_text(g, r)
				var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
				_text(font, c + Vector2(-lw * 0.5, -rad - 8.0 * k), lab, 20, col)
			elif float(g["dwell"]) > 0.0:
				var dw := float(g["dwell"]) / _dwell_t
				_hud.draw_arc(c, rad, 0.0, TAU, 24, Color(0.1, 0.2, 0.4, 0.55), 2.5 * k)
				_hud.draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * clampf(dw, 0.0, 1.0), 24, Color(1.0, 0.8, 0.2), 4.5 * k)
	if lane_mode:
		var lr: Dictionary = _pick_row
		if not lr.is_empty():
			for lg in lr["gaps"]:
				var lsc := _gap_screen(lr, lg)
				if lsc.is_empty():
					continue
				var lc: Vector2 = lsc["c"]
				var lhw: float = lsc["hw"]
				var lni := int(lg["lane"])
				if lni == _lane or (_look_dir != 0 and lni == _look_lane):
					var by := lc.y + s.y * 0.11
					var bw := maxf(lhw * 1.5, 26.0 * k)
					if lni == _lane:
						_hud.draw_line(Vector2(lc.x - bw, by), Vector2(lc.x + bw, by), Color(1.0, 0.62, 0.15, 0.9), 7.0 * k)
					else:
						_hud.draw_line(Vector2(lc.x - bw * 0.7, by), Vector2(lc.x + bw * 0.7, by), Color(1.0, 1.0, 1.0, 0.65), 4.0 * k)
				if String(lg["kind"]) == "late" and not lg["latched"] and spos.z - float(lr["z"]) < LATE_DIST + vel.length() * LATE_WARN + 25.0:
					var pulse := 0.5 + 0.5 * sin(_age * 6.0)
					_hud.draw_arc(lc, (16.0 + 8.0 * pulse) * k, 0.0, TAU, 28, Color(0.5, 0.9, 1.0, 0.35 + 0.3 * pulse), 3.0 * k)
		# gaze bar: the dead zone (light) and where your gaze (plus head turn) is right now, so you can see the tracker work
		if _eye_on:
			var bx0 := s.x * 0.5
			var bw0 := 90.0 * k
			var by0 := m + 50.0 * k
			_hud.draw_rect(Rect2(bx0 - bw0, by0 - 5.0 * k, bw0 * 2.0, 10.0 * k), Color(0.05, 0.12, 0.25, 0.45))
			_hud.draw_rect(Rect2(bx0 - _zone * 2.0 * bw0 / 0.5 * 0.5, by0 - 5.0 * k, _zone * 2.0 * bw0 / 0.5 * 0.5 * 2.0, 10.0 * k), Color(1.0, 1.0, 1.0, 0.35))
			_hud.draw_circle(Vector2(bx0 + (_steer_gaze if lane_ctl == 2 else clampf(_off_now / 0.5, -1.0, 1.0)) * bw0, by0), 6.0 * k, Color(1.0, 0.62, 0.15, 0.95))
		# lane indicator, top centre: three pills, the committed lane filled; a ring fills while you look aside
		var px0 := s.x * 0.5 - 38.0 * k
		_hud.draw_rect(Rect2(px0 - 26.0 * k, m - 4.0 * k, 38.0 * k * 2.0 + 52.0 * k, 40.0 * k), Color(0.05, 0.12, 0.25, 0.45))
		for li in 3:
			var pc := Vector2(px0 + 38.0 * k * float(li), m + 16.0 * k)
			var lane_now := int(_target_row["fl"]) if (not _target_row.is_empty() and _target_row.has("fl")) else _lane
			_hud.draw_circle(pc, 10.0 * k, Color(1.0, 1.0, 1.0, 0.7))
			if li == lane_now:
				_hud.draw_arc(pc, 13.0 * k, 0.0, TAU, 20, Color(1.0, 0.62, 0.15, 0.7), 2.5 * k)
			if li == _lane:
				_hud.draw_circle(pc, 7.5 * k, Color(1.0, 0.62, 0.15, 0.95))
			if _look_dir != 0 and li == _look_lane and li != _lane:
				var need := LANE_DWELL if _step_first else LANE_REPEAT
				_hud.draw_arc(pc, 13.0 * k, -PI * 0.5, -PI * 0.5 + TAU * clampf(_step_t / need, 0.0, 1.0), 20, Color(1.0, 1.0, 1.0, 0.9), 3.5 * k)
	# gaze cursor: a ring at the horizon where your eyes are (only the left / right part is used)
	if _eye_on:
		var cur_px := _cursor_px if (lane_ctl >= 2 and _cursor_px != Vector2.ZERO) else _gaze_px
		for ti in _gaze_trail.size():
			var ta := float(ti + 1) / float(_gaze_trail.size() + 1)
			_hud.draw_circle(_gaze_trail[ti], 5.0 * k * ta, Color(1.0, 0.6, 0.1, 0.35 * ta))
		_hud.draw_circle(cur_px, 15.0 * k, Color(1.0, 0.6, 0.1, 0.18))
		_hud.draw_arc(cur_px, 15.0 * k, 0.0, TAU, 24, Color(1.0, 0.6, 0.1, 0.95), 3.5 * k)
		_hud.draw_circle(cur_px, 4.5 * k, Color(1.0, 0.6, 0.1, 0.95))
	# the line your eyes set: from the board to the gate you locked
	if not _lock.is_empty() and not _lock_row.is_empty():
		var ls := _gap_screen(_lock_row, _lock)
		if not ls.is_empty():
			var from := cam.unproject_position(spos + Vector3(0.0, 1.4, 0.0))
			var lok := _forecast(_lock, _lock_row) == 1
			var lcol := Color(0.3, 0.85, 0.45, 0.95) if lok else Color(1.0, 0.35, 0.3, 0.95)
			_hud.draw_dashed_line(from, ls["c"], lcol, 4.0 * k, 14.0 * k)
			_hud.draw_arc(ls["c"], 18.0 * k, 0.0, TAU, 28, lcol, 4.0 * k)
	# score (top left) and eyes status (top right): that is all
	_text(font, Vector2(m, m + 22.0 * k), "%d" % score, 34, Color(1, 1, 1))
	if lane_mode:
		_text(font, Vector2(m, m + 52.0 * k), "%d coins" % coins_got, 20, Color(1.0, 0.9, 0.5))
	var eye_txt := "EYES OFF"
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		eye_txt = "EYES"
	elif GazeProvider.backend == GazeProvider.Backend.MOUSE and not Game.touch_mode:
		eye_txt = "MOUSE EYES"
	var ecol := Color(0.5, 1.0, 0.6) if _eye_on else Color(1, 1, 1, 0.55)
	var ew := font.get_string_size(eye_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_text(font, Vector2(s.x - m - ew, m + 18.0 * k), eye_txt, 20, ecol)
	# speed + flow (bottom left), posture (bottom right)
	_text(font, Vector2(m, s.y - m - 30.0 * k), "%d km/h" % int(vel.length() * 3.6), 30, Color(1, 1, 1))
	if chain > 0:
		_text(font, Vector2(m, s.y - m), "FLOW x%.1f" % groove, 22, Color(1.0, 0.85, 0.3))
	var posture := ""
	if not grounded:
		posture = "SLAM" if slamming else ("GLIDE" if gliding else "AIR")
	elif tucking:
		posture = "TUCK"
	elif braking:
		posture = "BRAKE"
	var pw := font.get_string_size(posture, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28.0 * k)).x
	_text(font, Vector2(s.x - m - pw, s.y - m), posture, 28, Color(0.1, 0.35, 0.7))
	# spring bar (only while it holds something)
	if energy > 3.0:
		var bw := minf(s.x * 0.3, 300.0 * k)
		var bx := s.x * 0.5 - bw * 0.5
		var by := s.y - m - 14.0 * k
		_hud.draw_rect(Rect2(bx - 3.0, by - 3.0, bw + 6.0, 14.0 * k + 6.0), Color(0, 0, 0, 0.6))
		_hud.draw_rect(Rect2(bx, by, bw * energy / 100.0, 14.0 * k), Color(0.4, 0.7, 1.0).lerp(Color(1.0, 0.85, 0.3), energy / 100.0))
	# toasts
	var ty := s.y * 0.2
	for t in _toasts:
		var a2 := clampf(float(t["t"]) / 0.5, 0.0, 1.0)
		var col2: Color = t["color"]
		col2.a = a2
		_ctext(font, ty, String(t["text"]), 30, col2)
		ty += 38.0 * k
	# chin gauge (left edge): where your chin is, no words
	var gx := m
	var gh := 150.0 * k
	var gy := s.y * 0.5 - gh * 0.5
	_hud.draw_rect(Rect2(gx, gy, 18.0 * k, gh), Color(0, 0, 0, 0.5))
	var mid := gy + gh * 0.5
	_hud.draw_rect(Rect2(gx, mid + 5.0 * k, 18.0 * k, gh * 0.5 - 5.0 * k), Color(0.3, 0.55, 1.0, 0.4))
	_hud.draw_rect(Rect2(gx, gy, 18.0 * k, gh * 0.5 - 5.0 * k), Color(0.3, 1.0, 0.5, 0.35))
	_hud.draw_circle(Vector2(gx + 9.0 * k, mid - clampf(nod_p / 0.40, -1.0, 1.0) * gh * 0.5), 9.0 * k, Color(1.0, 0.85, 0.3))
	if not _paused:
		var pr := _pause_rect()
		_hud.draw_rect(pr, Color(0.05, 0.12, 0.25, 0.5))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.32, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
		_hud.draw_rect(Rect2(pr.position.x + pr.size.x * 0.56, pr.position.y + pr.size.y * 0.25, pr.size.x * 0.12, pr.size.y * 0.5), Color(1, 1, 1, 0.9))
	else:
		_draw_pause(font, s, k)
	if _tune_open:
		_draw_tune(font, s, k)
	# head coach: one soft line, rarely (see HeadCoach); never over the bottom of the screen, where the eyes read worst
	if _coach_t > 0.0 and _coach_text != "":
		var ca := clampf(_coach_t / 0.6, 0.0, 1.0)
		var ccol := Color(0.5, 1.0, 0.6, ca) if _coach_good else Color(1.0, 0.85, 0.4, ca)
		_ctext(font, s.y * 0.30, _coach_text, 24, ccol)
	# camera trouble only
	var cmsg := GazeProvider.camera_message()
	if String(cmsg["text"]) != "" and (_age < 12.0 or not GazeProvider._camera_fresh()):
		_ctext(font, s.y * 0.12, String(cmsg["text"]), 20, cmsg["color"])


# --------------------------------------------------------------------------
# Gates: some open and close on a timer (your speed decides when you arrive), some stay shut until the last
# moment, some look open and slam shut. Snow screens hide part of the wall until you are nearly there.
# --------------------------------------------------------------------------
func _mk_gap(x: float, w: float, kind: String, good: bool) -> Dictionary:
	var t := _rng.randf_range(3.6, 5.2)
	return {"x": x, "w": w, "kind": kind, "good": good, "dwell": 0.0, "resolved": false, "eye": false, "eye_dist": 0.0,
		"marker": null, "door": null, "closed": kind == "late", "latched": false, "T": t, "frac": 0.55, "phase": _rng.randf_range(0.0, t)}


func _extra_kind() -> String:
	var r := _rng.randf()
	if r < 0.30 + 0.20 * diff:
		return "trap"
	if r < 0.50:
		return "hop"
	if r < 0.68:
		return "cycle"
	if r < 0.84:
		return "late"
	return "shut" if diff > 0.25 else "hop"


func _make_door(g: Dictionary, rz: float, row: Dictionary) -> MeshInstance3D:
	var d := MeshInstance3D.new()
	d.mesh = _m_bank
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match String(g["kind"]):
		"cycle":
			m.albedo_color = Color(0.7, 0.55, 1.0)
		"late":
			m.albedo_color = Color(0.12, 0.28, 0.55)
		_:
			m.albedo_color = Color(1.0, 0.4, 0.3)
	d.material_override = m
	add_child(d)
	var gx: float = g["x"]
	g["gy"] = terrain_h(gx, rz)
	var sy := 4.6 if g["closed"] else 0.05
	d.scale = Vector3(float(g["w"]), sy, 1.6)
	d.global_position = Vector3(gx, float(g["gy"]) + sy * 0.5, rz)
	(row["nodes"] as Array).append(d)
	return d


func _make_screen(row: Dictionary, cx: float, rz: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _m_bank
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.93, 0.95, 1.0, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.material_override = m
	n.scale = Vector3(36.0, 11.0, 5.0)
	add_child(n)
	var sz := rz + 40.0
	n.global_position = Vector3(cx, terrain_h(cx, sz) + 5.5, sz)
	(row["nodes"] as Array).append(n)
	row["screen"] = {"node": n, "mat": m, "cx": cx, "hw": 18.0, "z": sz, "alpha": 1.0}


func _occluded(row: Dictionary, g: Dictionary) -> bool:
	if not row.has("screen"):
		return false
	var sc: Dictionary = row["screen"]
	return float(sc["alpha"]) > 0.3 and absf(float(g["x"]) - float(sc["cx"])) < float(sc["hw"]) + float(g["w"]) * 0.5


## Will this gate let you through if you keep your speed? 1 yes, 0 no.
func _forecast(g: Dictionary, row: Dictionary) -> int:
	match String(g["kind"]):
		"trap", "shut":
			return 0
		"cycle":
			var eta := (spos.z - float(row["z"])) / maxf(-vel.y, 6.0)
			var t := fmod(_clock + eta + float(g["phase"]), float(g["T"]))
			return 1 if (t > 0.25 and t < float(g["T"]) * float(g["frac"]) - 0.25) else 0
	return 1


func _gap_text(g: Dictionary, row: Dictionary) -> String:
	match String(g["kind"]):
		"hop":
			return "HOP"
		"trap":
			return "DEAD END"
		"tight":
			return "TIGHT"
		"late":
			return "OPENS LATE"
		"shut":
			return "SLAMS SHUT"
		"cycle":
			return "TIMED: OPEN" if _forecast(g, row) == 1 else "TIMED: SHUT"
	return "OPEN"


func _update_doors() -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"]:
			continue
		var dist := spos.z - float(r["z"])
		for g in r["gaps"]:
			match String(g["kind"]):
				"cycle":
					g["closed"] = fmod(_clock + float(g["phase"]), float(g["T"])) > float(g["T"]) * float(g["frac"])
				"late":
					if not g["latched"] and dist < maxf(LATE_DIST, vel.length() * LATE_WARN):
						g["latched"] = true
						Game.sfx(&"whoosh")
					g["closed"] = not g["latched"]
				"shut":
					if not g["latched"] and dist < maxf(SHUT_DIST, vel.length() * SHUT_WARN) and dist > 2.0:
						g["latched"] = true
						Game.sfx(&"boom")
					g["closed"] = g["latched"]


func _collide_doors() -> void:
	if hurt_t > 0.0:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r["has_row"]:
			continue
		var rz: float = r["z"]
		if absf(spos.z - rz) > 2.5:
			continue
		for g in r["gaps"]:
			if g["door"] != null and g["closed"] and absf(spos.x - float(g["x"])) < float(g["w"]) * 0.5 + 0.9 and absf(spos.z - rz) < 1.6 and above < 5.0:
				spos.z = rz + 1.7
				if grounded:
					spos.y = terrain_h(spos.x, spos.z)
					_gh_prev = spos.y
				vel *= 0.25
				_crash("SHUT!")
				return


func _animate_doors(delta: float) -> void:
	for k in _rows:
		var r: Dictionary = _rows[k]
		for g in r["gaps"]:
			var d: Variant = g["door"]
			if d != null and is_instance_valid(d):
				var node := d as Node3D
				var sy := lerpf(node.scale.y, 4.6 if g["closed"] else 0.05, 1.0 - exp(-12.0 * delta))
				node.scale.y = sy
				node.position.y = float(g["gy"]) + sy * 0.5
		if r.has("screen"):
			var sc: Dictionary = r["screen"]
			var a := clampf((spos.z - float(sc["z"]) - 12.0) / 28.0, 0.0, 1.0)
			sc["alpha"] = a
			var mat: StandardMaterial3D = sc["mat"]
			mat.albedo_color.a = a * 0.92
			var nd: Variant = sc["node"]
			if is_instance_valid(nd):
				(nd as Node3D).visible = a > 0.03


# --------------------------------------------------------------------------
# Art: all built from code (no downloads), kept low-poly so a phone can draw it
# --------------------------------------------------------------------------
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float near = 1.0 - smoothstep(30.0, 120.0, length(VERTEX));
	float big = vn(wp.xz * 0.11);
	float drift = vn(vec2(wp.x * 0.5, wp.z * 0.09));
	float fine = vn(wp.xz * 3.5) * near + vn(wp.xz * 15.0) * 0.5 * near;
	vec3 base = COLOR.rgb;
	vec3 shade = base * vec3(0.84, 0.89, 0.99);
	float patch = smoothstep(0.12, 0.45, big * 0.65 + drift * 0.45);
	vec3 c = mix(shade, base, patch);
	c *= 0.93 + 0.10 * fine;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;                  // grazing-angle sky reflection was washing the whole slope white
	float tw = h21(floor(wp.xz * 26.0));
	float sp = step(0.9985, tw) * near * (0.55 + 0.45 * sin(TIME * 3.0 + tw * 60.0));
	EMISSION = vec3(sp) * 0.8;
}
"""


func _tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## Three stacked tiers, green skirts under snow-laden tops.
func _make_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var green := Color(0.10, 0.30, 0.22)
	var snow := Color(0.88, 0.93, 0.97)
	var white := Color(0.98, 0.99, 1.0)
	for tier in [[1.95, 1.1, 2.8], [1.55, 2.6, 2.5], [1.1, 4.0, 2.3]]:
		var r: float = tier[0]
		var y0: float = tier[1]
		var h: float = tier[2]
		var apex := Vector3(0.0, y0 + h, 0.0)
		var n := 8
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			var r0 := r * (1.0 + 0.14 * sin(float(i) * 2.3))
			var r1 := r * (1.0 + 0.14 * sin(float(i + 1) * 2.3))
			var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var b1 := Vector3(cos(a1) * r1, y0, sin(a1) * r1)
			var m0 := Vector3(cos(a0) * r0 * 0.5, y0 + h * 0.5, sin(a0) * r0 * 0.5)
			var m1 := Vector3(cos(a1) * r1 * 0.5, y0 + h * 0.5, sin(a1) * r1 * 0.5)
			_tri(st, b0, green, b1, green, m1, snow)
			_tri(st, b0, green, m1, snow, m0, snow)
			_tri(st, m0, snow, m1, snow, apex, white)
	st.generate_normals()
	return st.commit()


## A lumpy boulder: rocky sides, a snow cap on every upward-facing vertex.
func _make_rock_mesh() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.5
	sm.height = 2.4
	sm.radial_segments = 8
	sm.rings = 5
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols := PackedColorArray()
	for i in verts.size():
		var v := verts[i]
		var hsh := fmod(absf(sin(roundf(v.x * 7.0) * 12.9898 + roundf(v.y * 7.0) * 78.233 + roundf(v.z * 7.0) * 37.719)) * 43758.5453, 1.0)
		verts[i] = v * (0.8 + 0.4 * hsh)
		var t := smoothstep(0.45, 0.85, norms[i].y)
		cols.append(Color(0.40, 0.35, 0.36).lerp(Color(0.97, 0.98, 1.0), t))
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## A pole with a tall feather flag (tinted per instance).
func _make_flag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var dark := Color(0.2, 0.2, 0.22)
	var pr := 0.07
	for i in 3:
		var a0 := TAU * float(i) / 3.0
		var a1 := TAU * float(i + 1) / 3.0
		var p0 := Vector3(cos(a0) * pr, 0.0, sin(a0) * pr)
		var p1 := Vector3(cos(a1) * pr, 0.0, sin(a1) * pr)
		_tri(st, p0, dark, p1, dark, p1 + Vector3(0, 7.0, 0), dark)
		_tri(st, p0, dark, p1 + Vector3(0, 7.0, 0), dark, p0 + Vector3(0, 7.0, 0), dark)
	var pts := [Vector3(0.07, 2.4, 0.0), Vector3(0.07, 6.8, 0.0), Vector3(0.95, 6.3, 0.1), Vector3(1.15, 4.8, 0.2), Vector3(0.9, 3.2, 0.1)]
	var white := Color.WHITE
	_tri(st, pts[0], white, pts[1], white, pts[2], white)
	_tri(st, pts[0], white, pts[2], white, pts[3], white)
	_tri(st, pts[0], white, pts[3], white, pts[4], white)
	st.generate_normals()
	return st.commit()


## A ring of faceted peaks around the whole valley, drawn as one mesh. Far ones are tall, near ones are foothills.
func _build_mountains() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var rock := Color(0.50, 0.55, 0.90)               # blue-violet, so the far ranges melt into the haze
	var snow := Color(0.80, 0.86, 0.98)
	var white := Color(0.95, 0.97, 1.0)
	var n := 30
	for i in n:
		var ang := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var far := i % 3 != 0
		var dist := rng.randf_range(820.0, 1000.0) if far else rng.randf_range(560.0, 700.0)
		var h := rng.randf_range(260.0, 480.0) if far else rng.randf_range(90.0, 190.0)
		var w := rng.randf_range(240.0, 380.0) if far else rng.randf_range(160.0, 260.0)
		var c := Vector3(sin(ang) * dist, 0.0, cos(ang) * dist)
		var apex := c + Vector3(rng.randf_range(-30.0, 30.0), h, rng.randf_range(-30.0, 30.0))
		var base: Array[Vector3] = []
		var mid: Array[Vector3] = []
		var k := 6
		for j in k:
			var aj := TAU * float(j) / float(k) + rng.randf_range(-0.2, 0.2)
			var rj := w * 0.5 * rng.randf_range(0.75, 1.15)
			base.append(c + Vector3(cos(aj) * rj, 0.0, sin(aj) * rj))
			mid.append(c + Vector3(cos(aj) * rj * 0.5, h * rng.randf_range(0.45, 0.65), sin(aj) * rj * 0.5))
		for j in k:
			var j2 := (j + 1) % k
			_tri(st, base[j], rock, base[j2], rock, mid[j2], snow)
			_tri(st, base[j], rock, mid[j2], snow, mid[j], snow)
			_tri(st, mid[j], snow, mid[j2], snow, apex, white)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mtn = MeshInstance3D.new()
	_mtn.mesh = st.commit()
	_mtn.material_override = mat
	_mtn.extra_cull_margin = 2000.0
	add_child(_mtn)


## A soft blue shadow shape on the snow, cast away from the low sun (works the same on every renderer, so a phone gets it too).
func _push_shadow(x: float, z: float, length: float, width: float) -> void:
	var d := Vector2(0.4226, 0.9063)
	var cx := x + d.x * length * 0.5
	var cz := z + d.y * length * 0.5
	var g := _grad(cx, cz)
	var n := Vector3(-g.x, 1.0, -g.y).normalized()
	var d3 := Vector3(d.x, 0.0, d.y)
	var p3 := Vector3(d.y, 0.0, -d.x)
	var bz := (d3 - n * d3.dot(n)).normalized() * length * 0.5
	var bx := (p3 - n * p3.dot(n)).normalized() * width * 0.5
	_sh_xf.append(Transform3D(Basis(bx, n, bz), Vector3(cx, terrain_h(cx, cz) + 0.12, cz)))
	_sh_col.append(Color(0.22, 0.32, 0.68, 0.30))


# --------------------------------------------------------------------------
# Eye tuning: how long you must look, how hard the line pulls, how forgiving the aim is.
# Open with T or by tapping the EYES label (top right). Saved on this device.
# --------------------------------------------------------------------------
func _assist_conf() -> float:
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		return clampf(GazeProvider.confidence, 0.3, 1.0)
	return 1.0


## Extra width (screen fraction) around a gate that still counts as looking at it: grows with how noisy your tracking is.
func _pad() -> float:
	var posture := 1.0 + 0.6 * (1.0 - GazeProvider.coach.quality) if GazeProvider.backend == GazeProvider.Backend.CAMERA else 1.0      # head tilted back = squinted eyes = a rougher signal: forgive more
	return clampf(maxf(0.04, 2.5 * maxf(_cal_sigma, _jit)) * posture, 0.04, 0.18) * _pad_scale


func _adjust(which: String, dir: float) -> void:
	match which:
		"dwell":
			_dwell_t = clampf(snappedf(_dwell_t + 0.05 * dir, 0.05), 0.15, 0.8)
		"assist":
			_assist = clampf(snappedf(_assist + 0.1 * dir, 0.1), 0.0, 1.0)
		"pad":
			_pad_scale = clampf(snappedf(_pad_scale + 0.1 * dir, 0.1), 0.5, 2.0)
	_save_tune()


func _tune_click(pos: Vector2) -> bool:
	var s := _hud.size
	var k := _hud_scale()
	if Rect2(s.x - 260.0 * k, 0.0, 260.0 * k, 70.0 * k).has_point(pos):
		_tune_open = not _tune_open
		return true
	if _tune_open:
		for b in _tune_btns:
			if (b["rect"] as Rect2).has_point(pos):
				_adjust(String(b["which"]), float(b["dir"]))
				return true
	return false


func _draw_tune(font: Font, s: Vector2, k: float) -> void:
	_tune_btns.clear()
	var w := 330.0 * k
	var x0 := s.x - w - 12.0 * k
	var y0 := 84.0 * k
	_hud.draw_rect(Rect2(x0, y0, w, 330.0 * k), Color(0.04, 0.08, 0.2, 0.78))
	var rows := [["dwell", "LOOK TIME", "%.2f s" % _dwell_t], ["assist", "LINE PULL", "%d%%" % int(round(_assist * 100.0))], ["pad", "AIM FORGIVING", "x%.1f" % _pad_scale]]
	var y := y0 + 40.0 * k
	for r in rows:
		_text(font, Vector2(x0 + 14.0 * k, y), String(r[1]), 18, Color(0.8, 0.92, 1.0))
		_text(font, Vector2(x0 + 14.0 * k, y + 28.0 * k), String(r[2]), 24, Color.WHITE)
		for d in [-1.0, 1.0]:
			var rc := Rect2(x0 + w - (130.0 if d < 0.0 else 66.0) * k, y - 22.0 * k, 54.0 * k, 54.0 * k)
			_hud.draw_rect(rc, Color(0.2, 0.4, 0.8, 0.9))
			_text(font, rc.position + Vector2(15.0 * k, 38.0 * k), "-" if d < 0.0 else "+", 30, Color.WHITE)
			_tune_btns.append({"rect": rc, "which": String(r[0]), "dir": d})
		y += 78.0 * k
	var q := "good" if _cal_sigma < 0.03 else ("ok" if _cal_sigma < 0.06 else "weak")
	_text(font, Vector2(x0 + 14.0 * k, y + 2.0 * k), "tracking %s  (setup %d%%, live %d%%)" % [q, int(round(_cal_sigma * 100.0)), int(round(_jit * 100.0))], 15, Color(1, 1, 1, 0.85))
	_text(font, Vector2(x0 + 14.0 * k, y + 26.0 * k), "aim zone +-%d%% of the screen" % int(round(_pad() * 100.0)), 15, Color(1, 1, 1, 0.85))
	_text(font, Vector2(x0 + 14.0 * k, y + 50.0 * k), "T or tap EYES to close", 14, Color(1, 1, 1, 0.55))


func _load_tune() -> void:
	if not OS.has_feature("web"):
		return
	var stored := str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('dh_tune')||''}catch(e){return ''}})()"))
	if stored != "":
		var d: Variant = JSON.parse_string(stored)
		if d is Dictionary:
			_dwell_t = clampf(float((d as Dictionary).get("dwell", _dwell_t)), 0.15, 0.8)
			_assist = clampf(float((d as Dictionary).get("assist", _assist)), 0.0, 1.0)
			_pad_scale = clampf(float((d as Dictionary).get("pad", _pad_scale)), 0.5, 2.0)
			_zone_scale = clampf(float((d as Dictionary).get("zs", _zone_scale)), 0.25, 2.0)
			steer_curve = clampf(float((d as Dictionary).get("curve", steer_curve)), 0.4, 1.6)
			steer_rate = clampf(float((d as Dictionary).get("rate", steer_rate)), 3.0, 24.0)
			reach = clampf(float((d as Dictionary).get("reach", reach)), 0.6, 4.0)
			look_smooth = clampf(float((d as Dictionary).get("smooth", look_smooth)), 0.02, 0.4)
	var q := str(JavaScriptBridge.eval("location.search"))
	for part in q.trim_prefix("?").split("&"):
		var kv := part.split("=")
		if kv.size() == 2 and kv[1].is_valid_float():
			match kv[0]:
				"dwell":
					_dwell_t = clampf(float(kv[1]), 0.15, 0.8)
				"assist":
					_assist = clampf(float(kv[1]), 0.0, 1.0)
				"pad":
					_pad_scale = clampf(float(kv[1]), 0.5, 2.0)
				"curve":
					steer_curve = clampf(float(kv[1]), 0.4, 1.6)
				"rate":
					steer_rate = clampf(float(kv[1]), 3.0, 24.0)
				"steer":
					steer_scale_const = clampf(float(kv[1]), 0.04, 0.3)


func _save_tune() -> void:
	if not OS.has_feature("web"):
		return
	var js := JSON.stringify({"dwell": _dwell_t, "assist": _assist, "pad": _pad_scale, "zs": _zone_scale, "curve": steer_curve, "rate": steer_rate, "reach": reach, "smooth": look_smooth})
	JavaScriptBridge.eval("(function(){try{localStorage.setItem('dh_tune','%s')}catch(e){}})()" % js)



# --------------------------------------------------------------------------
# THREE-LANE mode
# --------------------------------------------------------------------------
## Which lane do the eyes pick among the three gates of a wall? The gate nearest to the gaze wins only if it is clearly nearer than the committed one.
static func lane_pick(gx: float, sx: Array, cur: int, margin: float) -> int:
	var cand := 0
	for q in 3:
		if absf(gx - float(sx[q])) < absf(gx - float(sx[cand])):
			cand = q
	if cand != cur and absf(gx - float(sx[cand])) + margin < absf(gx - float(sx[cur])):
		return cand
	return cur


## SEEK: the carve toward the lane of the gate your gaze picked (same lead / gain the lane tests were tuned with), faded in after a reset.
func _seek_term() -> float:
	var xt := float(LANE_X[_seek_lane])
	return clampf((xt - (spos.x + vel.x * 0.45)) / 20.0, -0.7, 0.7) * _steer_arm


## EYES ONLY: the iris position inside the eye opening is a pure eye signal (a head turn moves the whole eye, not the iris inside it). Its range is tiny
## (a few percent of the eye width), so it is scaled to the size of YOUR normal glances (95th percentile of the last ~20 s, never below 6 x the fixation noise):
## a small glance then reaches the outer gates. It lingers (short smoothing) so a split-second look is noise-free, and returns screen-fraction units like the geometry offset.
func _eyes_only_offs(delta: float, geo_offs: float) -> float:
	var raw := -GazeProvider.eih.x * _ex_sign
	if _ex_full > 0.004 and not is_equal_approx(raw, _sacc_last_raw):
		_sacc_last_raw = raw                               # a new tracker frame (the game runs faster than the camera)
		sacc.push(_age, (raw - _ex_ref) / _ex_full)
	_ex_raw.append(raw)
	if _ex_raw.size() > 90:
		_ex_raw.remove_at(0)
	if not _ex_init:
		if _ex_raw.size() >= 45:
			var srt := _ex_raw.duplicate()
			srt.sort()
			_ex_ref = srt[srt.size() / 2]
			_ex_init = true
		return 0.0
	# direction check (mirror conventions are easy to get wrong): while the HEAD IS STILL, the iris-in-eye signal must agree with the geometry gaze.
	# (During a head turn the eyes counter-rotate, so that moment would give the wrong answer: it is never used.)
	var gx := GazeProvider.direct.x
	var ex_now := -GazeProvider.eih.x
	var yaw_now := GazeProvider.head_rpy.x
	_ex_yaw += (yaw_now - _ex_yaw) * 0.05
	if absf(yaw_now - _ex_yaw) < 0.015:
		_ex_c[5] += 1.0
		var aa := 1.0 / minf(float(_ex_c[5]), 600.0)
		if _ex_c[5] <= 1.0:
			_ex_c[0] = ex_now
			_ex_c[1] = gx
		else:
			_ex_c[0] += (ex_now - _ex_c[0]) * aa
			_ex_c[1] += (gx - _ex_c[1]) * aa
			_ex_c[2] += ((ex_now - _ex_c[0]) * (gx - _ex_c[1]) - _ex_c[2]) * aa
			_ex_c[3] += ((ex_now - _ex_c[0]) * (ex_now - _ex_c[0]) - _ex_c[3]) * aa
			_ex_c[4] += ((gx - _ex_c[1]) * (gx - _ex_c[1]) - _ex_c[4]) * aa
		if _ex_c[5] > 300.0 and _ex_c[3] > 4.0e-8 and _ex_c[4] > 4.0e-6:
			var corr := float(_ex_c[2]) / sqrt(float(_ex_c[3]) * float(_ex_c[4]))
			if absf(corr) > 0.5:
				var want := 1.0 if corr > 0.0 else -1.0
				if want != _ex_sign:
					_ex_sign = want
					_ex_init = false
					_ex_raw.clear()
					_ex_abs.clear()
					_ex_dec = 0.0
					return 0.0
	var d := raw - _ex_ref
	if absf(d) < 0.6 * _ex_full:
		_ex_ref += d * minf(delta / (7.0 if RunLog.on_vehicle(vehicle_forced) else 20.0), 1.0)         # slow drift only while you look near the middle
	# a lean (a streetcar, a tilted phone, a slumped shoulder) moves the whole reading by less than a glance, so the rules above never see it. Over a long ride you look left and
	# right about equally, so the median of the last ~40 s IS the centre: follow it, gently.
	_ex_slow_t -= delta
	if _ex_slow_t <= 0.0:
		_ex_slow_t = 0.25
		_ex_slow.append(raw)
		if _ex_slow.size() > 160:
			_ex_slow.remove_at(0)
	if _ex_slow.size() >= 40 and _ex_full > 0.0:
		var ss := _ex_slow.duplicate()
		ss.sort()
		var dm: float = float(ss[ss.size() / 2]) - _ex_ref
		if absf(dm) > 0.12 * _ex_full:
			_ex_ref += dm * minf(delta / (4.0 if RunLog.on_vehicle(vehicle_forced) else 14.0), 1.0)
	# a head shift or a lighting change moves the whole iris reading: if the look sits beyond any normal glance for 2 s the centre is stale, so re-centre on the recent median
	if not _ex_rec:
		if absf(d) > _ex_full:
			_ex_pin_t += delta
			if _ex_pin_t > 2.5:
				_ex_rec = true
				_note("eye centre was stale (%.3f off, normal glance %.3f): re-centring" % [d, _ex_full])
		else:
			_ex_pin_t = maxf(_ex_pin_t - delta * 2.0, 0.0)
	if _ex_rec:
		var rs := _ex_raw.duplicate()
		rs.sort()
		var med := float(rs[rs.size() / 2])
		_ex_ref += (med - _ex_ref) * minf(delta / 0.6, 1.0)
		if absf(med - _ex_ref) < 0.006:
			_ex_rec = false
			_ex_pin_t = 0.0
			_ex_abs.clear()                         # the glance size learned while the centre was wrong is wrong too
	var linger := maxf(look_smooth * 1.7, 0.03)
	_ex_dec += (raw - _ex_ref - _ex_dec) * (1.0 - exp(-delta / linger))
	_ex_abs.append(absf(_ex_dec))
	if _ex_abs.size() > 900:
		_ex_abs.remove_at(0)
	_ex_stat_t -= delta
	if _ex_stat_t <= 0.0 and _ex_abs.size() >= 90:
		_ex_stat_t = 0.5
		var ab := _ex_abs.duplicate()
		ab.sort()
		var p95 := ab[int(float(ab.size() - 1) * 0.95)]
		var stds: Array = []
		var q := 0
		while q + 6 <= _ex_raw.size():
			var mu := 0.0
			for z in 6:
				mu += _ex_raw[q + z]
			mu /= 6.0
			var v := 0.0
			for z in 6:
				v += (_ex_raw[q + z] - mu) * (_ex_raw[q + z] - mu)
			stds.append(sqrt(v / 6.0))
			q += 6
		stds.sort()
		_ex_noise = clampf(float(stds[stds.size() / 2]), 0.0004, 0.02) if not stds.is_empty() else 0.002
		_ex_full = clampf(p95, maxf(0.008, 6.0 * _ex_noise), 0.08)
	return clampf(_ex_dec / maxf(_ex_full, 0.004), -1.5, 1.5) * 0.25


func _head_offset(delta: float) -> float:
	if not (head_assist and GazeProvider.head_rpy_ok and GazeProvider.backend == GazeProvider.Backend.CAMERA):
		return 0.0
	var yaw := -rad_to_deg(GazeProvider.head_rpy.x)
	if not _yaw_ref_ok:
		_yaw_ref = yaw
		_yaw_ref_ok = true
	_yaw_ref += (yaw - _yaw_ref) * minf(delta / 6.0, 1.0)
	return clampf((yaw - _yaw_ref) * LANE_HEAD_GAIN, -0.2, 0.2)


## GATE control: look at the gate you want to go through. Only the nearest wall that is still far enough to carve to is used, because its
## three gates are 250 px or more apart on screen (far walls are about 90 px apart, less than the tracker's error).
func _lane_gate(delta: float, vs: Vector2) -> void:
	_gate_row = {}
	var keys: Array = _rows.keys()
	keys.sort()
	var row: Dictionary = {}
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"]:
			continue
		var dist := spos.z - float(r["z"])
		if dist < GATE_ROW_MIN or dist > 320.0:
			continue
		row = r
		break
	if row.is_empty():
		return
	var sx: Array = [0.0, 0.0, 0.0]
	var seen := 0
	for g in row["gaps"]:
		var sc := _gap_screen(row, g)
		if sc.is_empty():
			continue
		sx[int(g["lane"])] = float((sc["c"] as Vector2).x)
		seen += 1
	if seen < 3:
		return
	_gate_row = row
	_head_off = _head_offset(delta)
	var poor := (1.0 - GazeProvider.coach.quality) if GazeProvider.backend == GazeProvider.Backend.CAMERA else 0.0
	var gxp := _gaze_px.x + _head_off * vs.x
	_off_now = gxp / maxf(vs.x, 1.0) - 0.5
	var margin := LANE_MARGIN * vs.x * _zone_scale * (1.0 + 0.5 * poor)
	var cand := lane_pick(gxp, sx, _lane, margin)
	_look_lane = cand
	if cand != _lane:
		if cand != _lane_cand:
			_lane_cand = cand
			_step_t = 0.0
		_step_t += delta
		_step_first = true
		_look_dir = 1 if cand > _lane else -1
		if _step_t >= LANE_DWELL and not _paused:
			_lane_set(cand)
			_look_dir = 0
	else:
		_lane_cand = _lane
		_step_t = 0.0
		_look_dir = 0
## Learns the dead zone from your own signal: wide enough to ignore your noise, narrow enough that your real range crosses it.
func _update_lane_stats() -> void:
	var a := _gx_hist.duplicate()
	a.sort()
	var n := a.size()
	var al := _gx_long.duplicate()
	al.sort()
	_gx_med = al[al.size() / 2] if al.size() >= 90 else a[n / 2]
	var p16: float = a[int(float(n - 1) * 0.16)]
	var p84: float = a[int(float(n - 1) * 0.84)]
	_stat_std = (p84 - p16) * 0.5
	_stat_p5 = a[int(float(n - 1) * 0.05)]
	_stat_p95 = a[int(float(n - 1) * 0.95)]
	# Noise while you hold your gaze still: the spread inside short blocks (a glance aside does not count as noise). The dead zone follows THIS
	# (3 sigma) and a share of your real range, never the total spread: the more you look around, the more sensitive it must get, not less.
	var stds: Array = []
	var m0 := maxi(0, _gx_hist.size() - 72)
	var q := m0
	while q + 6 <= _gx_hist.size():
		var mu := 0.0
		for z in 6:
			mu += _gx_hist[q + z]
		mu /= 6.0
		var v := 0.0
		for z in 6:
			v += (_gx_hist[q + z] - mu) * (_gx_hist[q + z] - mu)
		stds.append(sqrt(v / 6.0))
		q += 6
	stds.sort()
	_noise_fix = clampf(float(stds[stds.size() / 2]), 0.002, 0.06) if not stds.is_empty() else 0.03
	var half := maxf(_stat_p95 - _gx_med, _gx_med - _stat_p5)
	_zone = clampf(maxf(0.30 * half, 3.0 * _noise_fix), ZONE_FLOOR, LANE_ZONE_MAX)
## Joystick-style lane control: look clearly left or right of the middle and the lane steps that way. Accuracy needed: a few
## percent of the screen, not the gap between two far-away gates. Leaving the zone needs a smaller offset than entering it (hysteresis).
static func lane_dir(off: float, zone: float, prev: int) -> int:
	var th := zone if prev == 0 else zone * 0.75
	if absf(off) <= th:
		return 0
	return 1 if off > 0.0 else -1


func _lane_set(l: int, manual: bool = false) -> void:
	_seek_lane = clampi(l, 0, 2)
	if clampi(l, 0, 2) != _lane:
		Game.sfx(&"whoosh")
	_lane = clampi(l, 0, 2)
	_step_t = 0.0
	if manual:
		_grace_t = 1.0e9


func _lane_tick(delta: float, vs: Vector2) -> void:
	_cursor_px = _gaze_px
	_pick_best = {}
	_pick_row = {}
	var commit := maxf(LANE_COMMIT_MIN, vel.length() * LANE_COMMIT_T)
	var keys: Array = _rows.keys()
	keys.sort()
	var target: Dictionary = {}
	var scout: Dictionary = {}
	for kk in keys:
		var r: Dictionary = _rows[kk]
		if not r["has_row"]:
			continue
		var dist := spos.z - float(r["z"])
		if dist < 8.0 or dist > 320.0:
			continue
		if target.is_empty():
			target = r
		if dist >= commit:
			scout = r
			break
	if target.is_empty():
		return
	if scout.is_empty():
		scout = target
	# the wall you are about to pass locks its lane (a carve needs room); your choice now applies to the wall after it
	if lane_mode:
		target["fl"] = _lane
	if _eye_on and lane_ctl >= 2:
		_grace_t = LANE_GRACE
		var cam_direct := GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider.direct_ok
		var gxs := (GazeProvider.direct.x if cam_direct else _gaze_px.x / maxf(vs.x, 1.0))
		var gys := (GazeProvider.direct.y if cam_direct else 0.5)
		_gy_buf.append(gys)
		if _gy_buf.size() > 90:
			_gy_buf.remove_at(0)
		var fuse_ready := GazeProvider.eye_w.x >= 0.0
		if fuse_ready != _fuse_seen:
			_fuse_seen = fuse_ready
			if fuse_ready:
				GazeProvider.bias.reset()          # the fused signal is already centred on your median look: do not correct it twice
				GazeProvider.bias.exp_span = Vector2.ZERO
			_ref_init = false
			_steer_arm = 0.0
			_gx_hist.clear()
			_gx_long.clear()
		if not _anchored and GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider._geo_n >= 10:
			GazeProvider.eye_anchor(Vector2(0.5, 0.46), 1.0)      # you look at the middle when it starts: pin the centre there at once
			_anchored = true
			_ref_init = false
			_steer_arm = 0.0
			_gx_hist.clear()
			_gx_long.clear()
		_gx_hist.append(gxs)
		if _gx_hist.size() > 600:
			_gx_hist.remove_at(0)
		_gx_long.append(gxs)
		if _gx_long.size() > 1800:
			_gx_long.remove_at(0)
		_stat_t -= delta
		if _stat_t <= 0.0 and _gx_hist.size() >= 90:
			_stat_t = 0.5
			_update_lane_stats()
			_steer_scale = clampf(maxf(steer_scale_const, 4.0 * _noise_fix), steer_scale_min, STEER_SCALE_MAX)      # only a noisier signal asks for a bigger look
		_head_off = _head_offset(delta)
		if not _ref_init and _gx_hist.size() >= 90:
			_ref_x = _gx_med
			_ref_init = true
		var scn := _steer_scale * _zone_scale
		if absf(gxs - _ref_x) < 1.2 * scn:
			_ref_x += (gxs - _ref_x) * minf(delta / 20.0, 1.0)
			_away_t = 0.0
		else:
			_away_t += delta
			if _away_t > 25.0:
				_ref_x += (gxs - _ref_x) * minf(delta / 10.0, 1.0)      # away for a long time: the centre really moved
		var offs := gxs - (_ref_x if _ref_init else _gx_med) + _head_off
		if eyes_only and cam_direct and GazeProvider.eih_ok:
			offs = _eyes_only_offs(delta, offs)
		offs *= reach
		_offs_s += (offs - _offs_s) * (1.0 - exp(-delta / maxf(look_smooth, 0.01)))
		offs = _offs_s
		# vertical: only for the reticle (the game steers sideways), but it must be able to go anywhere on the screen
		if not _ref_init and _gy_buf.size() >= 30:
			var gsorted := _gy_buf.duplicate()
			gsorted.sort()
			_ref_y = gsorted[gsorted.size() / 2]
		elif absf(gys - _ref_y) < 1.5 * scn:
			_ref_y += (gys - _ref_y) * minf(delta / 20.0, 1.0)
			_ry_away = 0.0
		else:
			_ry_away += delta
			if _ry_away > 3.0 and _gy_buf.size() >= 30:       # the vertical centre moved (head pitch, posture): follow the recent median
				var gs2 := _gy_buf.duplicate()
				gs2.sort()
				_ref_y += (float(gs2[gs2.size() / 2]) - _ref_y) * minf(delta / 1.0, 1.0)
				if _ry_away - delta <= 3.0:
					_note("vertical centre was stale (looking %.2f, centre %.2f): re-centred" % [gys, _ref_y])
		_offy_s += ((gys - _ref_y) * reach - _offy_s) * (1.0 - exp(-delta / maxf(look_smooth, 0.01)))
		var offy := _offy_s
		_cursor_px = Vector2(clampf(0.5 + offs, 0.0, 1.0) * vs.x, clampf(0.5 + offy, 0.0, 1.0) * vs.y)
		_off_now = offs
		var scs := _steer_scale * _zone_scale
		var dzs := minf(_noise_fix, 0.03)
		var lin := clampf(maxf(absf(offs) - dzs, 0.0) / maxf(scs - dzs, 0.05), 0.0, 1.0)
		_steer_arm = minf(_steer_arm + (delta / 1.5 if _ref_init else 0.0), 1.0)
		_steer_gaze = signf(offs) * pow(lin, steer_curve) * _steer_arm
		if lane_ctl == 3:
			var gaze_eff := (offs + 0.5) * vs.x
			_cursor_px = Vector2(clampf(gaze_eff, 0.0, vs.x), _cursor_px.y)
			var srow: Dictionary = {}
			var skeys: Array = _rows.keys()
			skeys.sort()
			for sk in skeys:
				var sr: Dictionary = _rows[sk]
				if not sr["has_row"]:
					continue
				var sd := spos.z - float(sr["z"])
				if sd < GATE_ROW_MIN or sd > 320.0:
					continue
				srow = sr
				break
			if not srow.is_empty():
				var ssx: Array = [0.0, 0.0, 0.0]
				var sseen := 0
				for sg in srow["gaps"]:
					var ssc := _gap_screen(srow, sg)
					if ssc.is_empty():
						continue
					ssx[int(sg["lane"])] = float((ssc["c"] as Vector2).x)
					sseen += 1
				if sseen == 3:
					_gate_row = srow
					if not _paused:
						_seek_lane = lane_pick(gaze_eff, ssx, _seek_lane, LANE_MARGIN * vs.x * _zone_scale)
	elif _eye_on and lane_ctl == 0:
		_grace_t = LANE_GRACE
		_lane_gate(delta, vs)
	elif _eye_on:

		_grace_t = LANE_GRACE
		var poor := (1.0 - GazeProvider.coach.quality) if GazeProvider.backend == GazeProvider.Backend.CAMERA else 0.0
		var gxn := _gaze_px.x / maxf(vs.x, 1.0)
		_gx_hist.append(gxn)
		if _gx_hist.size() > 600:
			_gx_hist.remove_at(0)
		_gx_long.append(gxn)
		if _gx_long.size() > 1800:
			_gx_long.remove_at(0)
		_stat_t -= delta
		if _stat_t <= 0.0 and _gx_hist.size() >= 90:
			_stat_t = 0.5
			_update_lane_stats()
		var head_off := 0.0
		if head_assist and GazeProvider.head_rpy_ok and GazeProvider.backend == GazeProvider.Backend.CAMERA:
			var yaw := -rad_to_deg(GazeProvider.head_rpy.x)
			if not _yaw_ref_ok:
				_yaw_ref = yaw
				_yaw_ref_ok = true
			_yaw_ref += (yaw - _yaw_ref) * minf(delta / 6.0, 1.0)
			head_off = clampf((yaw - _yaw_ref) * LANE_HEAD_GAIN, -0.2, 0.2)
		_head_off = head_off
		var off := gxn - _gx_med + head_off
		_off_now = off
		_look_dir = lane_dir(off, maxf(_zone * _zone_scale, 0.02) * (1.0 + 0.5 * poor), _look_dir)
		if _look_dir == 0 or _paused:
			_step_t = 0.0
			_step_first = true
		else:
			_step_t += delta
			if _step_t >= (LANE_DWELL if _step_first else LANE_REPEAT):
				_step_t = 0.0
				_step_first = false
				_lane_set(_lane + _look_dir)
	else:
		_grace_t = maxf(_grace_t - delta, 0.0)
		_look_dir = 0
		_steer_gaze = lerpf(_steer_gaze, 0.0, 1.0 - exp(-4.0 * delta))
	if lane_ctl != 0:
		_look_lane = clampi(_lane + _look_dir, 0, 2)
	if lane_ctl == 2:
		var best_l := 1
		for li2 in 3:
			if absf(spos.x - float(LANE_X[li2])) < absf(spos.x - float(LANE_X[best_l])):
				best_l = li2
		_lane = best_l
		_look_lane = best_l
		_look_dir = 0
	elif lane_ctl == 3:
		_lane = _seek_lane
		_look_lane = _seek_lane
		_look_dir = 0
	var lane_t: int = int(target["fl"]) if target.has("fl") else _lane
	for g2 in target["gaps"]:
		if int(g2["lane"]) == lane_t:
			_lock = g2
			_lock_row = target
	_pick_row = _gate_row if ((lane_ctl == 0 or lane_ctl == 3) and not _gate_row.is_empty()) else scout
	_target_row = target


## Three gaps per wall at fixed lanes. The safe route moves by at most one lane per wall, so lines are long gentle arcs.
func _lane_gaps(row: Dictionary, gaps: Array, j: int) -> void:
	gaps.clear()
	var calm := j <= CALM_ROWS
	var d := diff * (GazeProvider.coach.quality if GazeProvider.backend == GazeProvider.Backend.CAMERA else 1.0)    # a poorly placed head eases the course
	var step := 0
	if not calm:
		var r := _rng.randf()
		step = -1 if r < 0.25 else (1 if r < 0.5 else 0)
	var good := clampi(_lane_good + step, 0, 2)
	_lane_good = good
	_good_x = float(LANE_X[good])
	for i in 3:
		var kind := "open"
		var is_good := i == good
		if not calm:
			var q := _rng.randf()
			if is_good:
				if q < 0.12 + 0.2 * d:
					kind = "late"
			else:
				if q < 0.2 + 0.4 * d:
					kind = "trap"
				elif q < 0.32 + 0.4 * d:
					kind = "shut"
				elif q < 0.40 + 0.4 * d:
					kind = "cycle"
		var g := _mk_gap(float(LANE_X[i]), LANE_W, kind, is_good)
		g["lane"] = i
		gaps.append(g)


func _lane_extras(row: Dictionary, gaps: Array, prev_x: float, rz: float, j: int) -> void:
	if j > CALM_ROWS and _rng.randf() < 0.1 + 0.2 * diff:
		var oth: Array = []
		for g in gaps:
			if not g["good"]:
				oth.append(g)
		if not oth.is_empty():
			_make_screen(row, float((oth[_rng.randi() % oth.size()] as Dictionary)["x"]) + _rng.randf_range(-3.0, 3.0), rz)
	_make_coins(row, gaps, rz)


## Coins sit in every lane, so the lane you choose is what you collect: nothing points at the safe lane.
func _make_coins(row: Dictionary, gaps: Array, rz: float) -> void:
	if _coin_mesh == null:
		_coin_mesh = SphereMesh.new()
		_coin_mesh.radius = 0.55
		_coin_mesh.height = 1.1
		_coin_mesh.radial_segments = 10
		_coin_mesh.rings = 5
		_coin_mat = StandardMaterial3D.new()
		_coin_mat.albedo_color = Color(1.0, 0.85, 0.35)
		_coin_mat.emission_enabled = true
		_coin_mat.emission = Color(1.0, 0.8, 0.3)
		_coin_mat.emission_energy_multiplier = 1.6
		_coin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var coins: Array = []
	for g in gaps:
		var cx: float = g["x"]
		for i in 4:
			var cz := rz + 44.0 - float(i) * 9.0
			var n := MeshInstance3D.new()
			n.mesh = _coin_mesh
			n.material_override = _coin_mat
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			n.global_position = Vector3(cx, terrain_h(cx, cz) + 1.4, cz)
			(row["nodes"] as Array).append(n)
			coins.append({"n": n, "x": cx, "z": cz, "taken": false})
	row["coins"] = coins


func _collect_coins() -> void:
	if not lane_mode:
		return
	var above := spos.y - terrain_h(spos.x, spos.z)
	for k in _rows:
		var r: Dictionary = _rows[k]
		if not r.has("coins") or absf(float(r["z"]) - spos.z) > 64.0:
			continue
		for c in r["coins"]:
			if c["taken"]:
				continue
			if absf(float(c["z"]) - spos.z) < 3.0 and absf(float(c["x"]) - spos.x) < 3.2 and above < 5.0:
				c["taken"] = true
				var n: Variant = c["n"]
				if is_instance_valid(n):
					(n as Node3D).visible = false
				coins_got += 1
				score += int(5.0 * groove)
				Game.sfx(&"coin")



# --------------------------------------------------------------------------
# Pause + live tracking monitor (P / Esc, or the button under EYES). Same idea as EyeLab, kept simple.
# --------------------------------------------------------------------------
var _no_pause_until: int = 0              # msec: right after START the browser asks for the camera, may leave fullscreen and steals focus; none of that is a reason to pause


func _pause_grace() -> bool:
	if Time.get_ticks_msec() < _no_pause_until:
		return true
	return GazeProvider.backend == GazeProvider.Backend.CAMERA and not GazeProvider._camera_fresh() and _age < 30.0          # still waiting for the first camera frames


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if lane_mode and cam != null and not _pause_grace():
			_paused = true


func _watch_trk(delta: float) -> void:
	if _paused:
		return
	_trk_t -= delta
	if _trk_t <= 0.0:
		_trk_t = 0.5
		var f := float(GazeProvider._pkt_times.size()) / 2.0
		_trk_play_fps = f if _trk_play_fps <= 0.0 else lerpf(_trk_play_fps, f, 0.3)


func _watch_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if _was_fullscreen and not fs and not _pause_grace():
		_paused = true                 # Esc in a fullscreen browser only leaves fullscreen: treat it as pause
	_was_fullscreen = fs


func _pause_rect() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	var k := _hud_scale()
	return Rect2(s.x - 24.0 * k - 56.0 * k, 24.0 * k + 30.0 * k, 56.0 * k, 40.0 * k)


func _pause_input(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_P or kc == KEY_ESCAPE:
			_paused = not _paused
			return true
		if _paused and (kc == KEY_SPACE or kc == KEY_ENTER):
			_paused = false
			return true
	var pos := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	if not pos.is_finite():
		return false
	var now := Time.get_ticks_msec()
	if now - _ui_msec < 250:
		return _paused or _pause_rect().has_point(pos)      # a touch also arrives as an emulated mouse click: act once
	if not _paused:
		if _pause_rect().has_point(pos):
			_paused = true
			_ui_msec = now
			return true
		return false
	_ui_msec = now
	for b in _pause_btns:
		if (b["r"] as Rect2).has_point(pos):
			_pause_action(String(b["id"]))
			_save_tune()
			break
	return true


func _pause_report() -> Dictionary:
	var fps := float(GazeProvider._pkt_times.size()) / 2.0
	var cs := GazeProvider.coach
	return {"backend": GazeProvider.backend_name(), "trackerMode": (str(JavaScriptBridge.eval("window.__gazeMode || '?'")) if OS.has_feature("web") else "n/a"), "camera": GazeProvider.camera_status, "fps": snappedf(fps, 0.1), "gameFps": int(Engine.get_frames_per_second()), "latencyMs": int(GazeProvider.trk_lat_ms), "modelMs": int(GazeProvider.trk_inf_ms), "detectMs": int(GazeProvider.trk_det_ms), "delegate": GazeProvider.trk_delegate, "video": GazeProvider.trk_video, "faceCropPx": GazeProvider.trk_roi, "camFrames": GazeProvider.trk_cam_frames, "droppedFrames": GazeProvider.trk_dropped, "trackerFpsWhilePlaying": snappedf(_trk_play_fps, 0.1), "gazeStretch": [snappedf(GazeProvider.bias.scale_lo.x, 0.01), snappedf(GazeProvider.bias.scale_hi.x, 0.01)], "irisPx": snappedf(GazeProvider.limb_rad * 2.0, 0.1),
		"confidence": snappedf(GazeProvider.confidence, 0.01), "gazeNoiseStd": snappedf(_stat_std, 0.001), "gazeRange": [snappedf(_stat_p5 - _gx_med, 0.001), snappedf(_stat_p95 - _gx_med, 0.001)],
		"deadZone": snappedf(_zone, 0.001), "fixationNoise": snappedf(_noise_fix, 0.001), "zoneScale": snappedf(_zone_scale, 0.01), "offNow": snappedf(_off_now, 0.001), "headOff": snappedf(_head_off, 0.001), "headDeg": [snappedf(-rad_to_deg(GazeProvider.head_rpy.x), 0.1), snappedf(rad_to_deg(GazeProvider.head_rpy.y), 0.1), snappedf(-rad_to_deg(GazeProvider.head_rpy.z), 0.1)],
		"eyesOpenRatio": snappedf(cs.open_ratio, 0.01), "headQuality": snappedf(cs.quality, 0.01), "lane": _lane, "control": ["gate", "side", "steer", "seek"][lane_ctl], "steer": snappedf(_steer_gaze, 0.01), "steerScale": snappedf(_steer_scale, 0.001), "reach": snappedf(reach, 0.01), "eyesOnly": eyes_only, "exFull": snappedf(_ex_full, 0.0001), "exNoise": snappedf(_ex_noise, 0.0001), "exSign": _ex_sign, "eihX": snappedf(GazeProvider.eih.x, 0.0001), "lookSmoothMs": int(look_smooth * 1000.0), "steerCurve": steer_curve, "steerRate": steer_rate, "steerRef": snappedf(_ref_x, 0.001), "directGaze": [snappedf(GazeProvider.direct.x, 0.001), snappedf(GazeProvider.direct.y, 0.001)], "refY": snappedf(_ref_y, 0.001), "steerArm": snappedf(_steer_arm, 0.01), "anchored": _anchored, "headAssist": head_assist, "coins": coins_got, "crashes": crashes, "rows": rows_passed}


func _pause_action(id: String) -> void:
	match id:
		"resume":
			_paused = false
			_pause_adv = false
		"restart":
			_paused = false
			_pause_adv = false
			call("_restart")
		"menu":
			_return_to_menu()
		"advanced":
			_pause_adv = true
		"simple":
			_pause_adv = false
		"copy":
			DisplayServer.clipboard_set(JSON.stringify(_pause_report(), "  "))
			_copy_note = "report copied"
		"reset":
			GazeProvider.bias.reset()
			GazeProvider.bias.exp_span = Vector2.ZERO if lane_mode else Vector2(0.6, 0.0)
			GazeProvider.coach.reset()
			_gx_hist.clear()
			_gx_long.clear()
			_ref_init = false
			_yaw_ref_ok = false
			_zone = LANE_ZONE
			_copy_note = "learning reset"
		"ctl":
			lane_ctl = (lane_ctl + 1) % 4
			_lane_cand = _lane
			_step_t = 0.0
			_copy_note = "control: " + ["look at the gate you want", "look left / right of the middle to step a lane", "STEER: the board turns as far as you look from your centre, continuously", "SEEK: your gaze picks the nearest gate and the board carves through it"][lane_ctl]
		"head":
			head_assist = not head_assist
		"sens_up":
			_zone_scale = clampf(_zone_scale * 0.8, 0.25, 2.0)
			_copy_note = "sensitivity x%.1f (dead zone +-%.0f%%)" % [1.0 / _zone_scale, _zone * _zone_scale * 100.0]
		"curve_up":
			steer_curve = clampf(steer_curve + 0.1, 0.4, 1.6)
			_copy_note = "curve %.1f: a larger number is gentler near the middle" % steer_curve
		"curve_dn":
			steer_curve = clampf(steer_curve - 0.1, 0.4, 1.6)
			_copy_note = "curve %.1f: small looks steer more" % steer_curve
		"eyes":
			eyes_only = not eyes_only
			_ex_init = false
			_copy_note = "eyes only: " + ("the iris inside the eye, a head turn does not count" if eyes_only else "screen gaze (head turns count)")
		"flip":
			_ex_sign = -_ex_sign
			_ex_init = false
			_ex_raw.clear()
			_ex_abs.clear()
			_ex_dec = 0.0
			_copy_note = "eye direction reversed (now %s)" % ("normal" if _ex_sign > 0.0 else "reversed")
		"reach_up":
			reach = clampf(reach * 1.15, 0.6, 4.0)
			_copy_note = "reach x%.2f: a look moves the reticle further" % reach
		"reach_dn":
			reach = clampf(reach / 1.15, 0.6, 4.0)
			_copy_note = "reach x%.2f" % reach
		"smooth_up":
			look_smooth = clampf(look_smooth * 1.3, 0.02, 0.4)
			_copy_note = "steadier: %.0f ms of smoothing" % (look_smooth * 1000.0)
		"smooth_dn":
			look_smooth = clampf(look_smooth / 1.3, 0.02, 0.4)
			_copy_note = "snappier: %.0f ms of smoothing" % (look_smooth * 1000.0)
		"rate_up":
			steer_rate = clampf(steer_rate * 1.25, 3.0, 24.0)
			_copy_note = "response %.0f per second (faster, less smoothing)" % steer_rate
		"rate_dn":
			steer_rate = clampf(steer_rate / 1.25, 3.0, 24.0)
			_copy_note = "response %.0f per second (smoother, slower)" % steer_rate
		"sens_dn":
			_zone_scale = clampf(_zone_scale * 1.25, 0.25, 2.0)
			_copy_note = "sensitivity x%.1f (dead zone +-%.0f%%)" % [1.0 / _zone_scale, _zone * _zone_scale * 100.0]


func _return_to_menu() -> void:
	_paused = false
	_pause_adv = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()                 # the start menu comes back (the camera keeps running)


## The pause screen a player sees: big buttons, nothing to tune.
func _draw_pause_simple(font: Font, s: Vector2, k: float) -> void:
	_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.9))
	_ctext(font, s.y * 0.14, "PAUSED", 46, Color(1, 1, 1))
	var pt := "GAME %d fps" % int(Engine.get_frames_per_second())
	if GazeProvider.backend == GazeProvider.Backend.CAMERA:
		pt += "    CAM %.0f fps  %d ms" % [float(GazeProvider._pkt_times.size()) / 2.0, int(GazeProvider.trk_lat_ms)]
	_ctext(font, s.y * 0.14 + 40.0 * k, pt, 18, Color(1, 1, 1, 0.7))
	var labels := [["resume", "RESUME"], ["restart", "RESTART RUN"], ["menu", "RETURN TO MENU"], ["advanced", "ADVANCED: TRACKING MONITOR"]]
	var bw := minf(s.x * 0.8, 560.0 * k)
	var bh := 62.0 * k
	var y := s.y * 0.30
	for b in labels:
		var br := Rect2((s.x - bw) * 0.5, y, bw, bh)
		var primary: bool = b[0] == "resume"
		_hud.draw_rect(br, Color(0.2, 0.5, 0.9, 0.95) if primary else Color(1, 1, 1, 0.14))
		var tw := font.get_string_size(String(b[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k)).x
		_text(font, Vector2(br.position.x + (bw - tw) * 0.5, br.position.y + bh * 0.66), String(b[1]), 24, Color(1, 1, 1))
		_pause_btns.append({"id": b[0], "r": br})
		y += bh + 14.0 * k


func _draw_pause(font: Font, s: Vector2, k: float) -> void:
	_pause_btns.clear()
	if not _pause_adv:
		_draw_pause_simple(font, s, k)
		return
	_hud.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.07, 0.15, 0.88))
	var m := 22.0 * k
	var y := m
	_text(font, Vector2(m, y + 26.0 * k), "PAUSED: tracking monitor", 30, Color(1, 1, 1))
	y += 44.0 * k
	var cam_on := GazeProvider.backend == GazeProvider.Backend.CAMERA
	var fps := float(GazeProvider._pkt_times.size()) / 2.0
	var iris := GazeProvider.limb_rad * 2.0
	var conf := GazeProvider.confidence
	var cs := GazeProvider.coach
	var issues: Array[String] = []
	if not cam_on:
		issues.append("no camera: using mouse / touch")
	else:
		if not GazeProvider._camera_fresh():
			issues.append("no camera frames arriving")
		if fps < 20.0:
			issues.append("camera slow (%d frames/s): more light" % int(fps))
		if iris < 14.0 and iris > 0.0:
			issues.append("iris small (%.0f px): sit closer" % iris)
		if conf < 0.5:
			issues.append("face not clear")
		if _stat_std > 0.09:
			issues.append("gaze very noisy")
		elif _stat_p95 - _stat_p5 < 0.06 and _gx_hist.size() > 200:
			issues.append("gaze barely moves: look further aside")
		if cs.quality < 0.5:
			issues.append("head position poor")
	var good := issues.is_empty()
	var lines: Array[String] = [
		"camera %s   %d frames/s   iris %.0f px   confidence %d%%" % [GazeProvider.camera_status if GazeProvider.camera_status != "" else "-", int(fps), iris, int(conf * 100.0)],
		"head  turn %+.0f   nod %+.0f   tilt %+.0f deg   eyes open %d%%   position %d%%" % [-rad_to_deg(GazeProvider.head_rpy.x), rad_to_deg(GazeProvider.head_rpy.y), -rad_to_deg(GazeProvider.head_rpy.z), int(cs.open_ratio * 100.0), int(cs.quality * 100.0)],
		"gaze  now %+.0f%%   dead zone +-%.0f%%   range %+.0f%% .. %+.0f%%   spread %.1f%%   head help %.0f%%" % [_off_now * 100.0, _zone * _zone_scale * 100.0, (_stat_p5 - _gx_med) * 100.0, (_stat_p95 - _gx_med) * 100.0, _stat_std * 100.0, _head_off * 100.0]]
	var fs := 19
	for ln in lines:
		_text(font, Vector2(m, y + 18.0 * k), ln, fs, Color(0.85, 0.92, 1.0))
		y += 26.0 * k
	lines.append("frames  game %d/s   tracker now %d/s   tracker while playing %d/s   gaze stretch L x%.1f R x%.1f" % [int(Engine.get_frames_per_second()), int(fps), int(_trk_play_fps), GazeProvider.bias.scale_lo.x, GazeProvider.bias.scale_hi.x])
	if OS.has_feature("web"):
		lines.append("speed  capture to game %s ms   model %s ms per frame   camera frames %d   dropped %d" % [str(int(GazeProvider.trk_lat_ms)) if GazeProvider.trk_lat_ms >= 0.0 else "?", str(int(GazeProvider.trk_inf_ms)) if GazeProvider.trk_inf_ms >= 0.0 else "?", GazeProvider.trk_cam_frames, GazeProvider.trk_dropped])
	if lane_ctl == 2:
		lines.append("steer  %+d%%   full steering at a look of +-%.0f%% from your centre   (MORE SENSITIVE = smaller)" % [int(_steer_gaze * 100.0), _steer_scale * _zone_scale * 100.0])
	if OS.has_feature("web"):
		lines.append("tracker  %s" % str(JavaScriptBridge.eval("(window.__gazeMode || '?') + '   packets ' + ((window.__gazeStats && window.__gazeStats.pk) || 0) + '   ' + (window.__gazeWorkerError ? 'worker error: ' + window.__gazeWorkerError : '')")))
	lines.append("iris   %s   iris-in-eye %.4f   your glance size %.4f   noise %.4f   (full look = your glance size)" % ["EYES ONLY" if (eyes_only and GazeProvider.eih_ok) else "screen gaze", GazeProvider.eih.x, _ex_full, _ex_noise])
	lines.append("eyes   auto weights: right %s   left %s   (glasses / lens distortion are learned from how you look around)" % [("%d%%" % int(GazeProvider.eye_w.x * 100.0)) if GazeProvider.eye_w.x >= 0.0 else "learning", ("%d%%" % int(GazeProvider.eye_w.y * 100.0)) if GazeProvider.eye_w.y >= 0.0 else "learning"])
	var verdict := "TRACKING GOOD" if good else "CHECK: " + "; ".join(issues)
	_text(font, Vector2(m, y + 20.0 * k), verdict, 22, Color(0.5, 1.0, 0.6) if good else Color(1.0, 0.8, 0.4))
	y += 40.0 * k
	# trace of the last ~10 s of left / right gaze, with the dead zone: this is what the lane control sees
	var gw := minf(s.x - 2.0 * m, 560.0 * k)
	var gh := 104.0 * k
	var gr := Rect2(m, y, gw, gh)
	_hud.draw_rect(gr, Color(0.0, 0.0, 0.0, 0.4))
	var midy := gr.position.y + gh * 0.5
	var zpx := _zone * _zone_scale / 0.3 * gh * 0.5
	_hud.draw_rect(Rect2(gr.position.x, midy - zpx, gw, zpx * 2.0), Color(1.0, 1.0, 1.0, 0.16))
	_hud.draw_line(Vector2(gr.position.x, midy), Vector2(gr.end.x, midy), Color(1, 1, 1, 0.35), 1.0)
	var n := _gx_hist.size()
	if n > 2:
		var pts := PackedVector2Array()
		var step := maxi(1, n / int(maxf(gw / 3.0, 1.0)))
		for q in range(0, n, step):
			var off := clampf((_gx_hist[q] - _gx_med) / 0.3, -1.0, 1.0)
			pts.append(Vector2(gr.position.x + gw * float(q) / float(n - 1), midy - off * gh * 0.5))
		if pts.size() > 1:
			_hud.draw_polyline(pts, Color(1.0, 0.62, 0.15, 0.95), 2.0 * k)
	_text(font, Vector2(gr.position.x + 6.0 * k, gr.position.y + 16.0 * k), "right", 14, Color(1, 1, 1, 0.6))
	_text(font, Vector2(gr.position.x + 6.0 * k, gr.end.y - 6.0 * k), "left", 14, Color(1, 1, 1, 0.6))
	# little screen map: where the gaze is on your screen right now, and the three lanes
	var mw := 190.0 * k
	var mh := mw * s.y / maxf(s.x, 1.0)
	var mx := gr.end.x + 18.0 * k
	var landscape := mx + mw < s.x - m
	var mrect := Rect2(mx, y, mw, mh) if landscape else Rect2(m, y + gh + 14.0 * k, mw, mh)
	_hud.draw_rect(mrect, Color(0.0, 0.0, 0.0, 0.4))
	for li in 3:
		_hud.draw_rect(Rect2(mrect.position.x + mrect.size.x * float(li) / 3.0, mrect.position.y, mrect.size.x / 3.0 - 1.0, mrect.size.y), Color(1.0, 0.62, 0.15, 0.22 if li == _lane else 0.07))
	var gmap := _cursor_px if (lane_ctl >= 2 and _cursor_px != Vector2.ZERO) else _gaze_px
	var gp := Vector2(mrect.position.x + clampf(gmap.x / maxf(s.x, 1.0), 0.0, 1.0) * mrect.size.x, mrect.position.y + clampf(gmap.y / maxf(s.y, 1.0), 0.0, 1.0) * mrect.size.y)
	_hud.draw_circle(gp, 5.0 * k, Color(1.0, 0.62, 0.15, 1.0))
	_hud.draw_rect(mrect, Color(1, 1, 1, 0.35), false, 1.0)
	y = (mrect.end.y if not landscape else maxf(gr.end.y, mrect.end.y)) + 20.0 * k
	_text(font, Vector2(m, y + 14.0 * k), "Look left / right and watch the orange line leave the grey band: that is what steers. Vertical gaze is not used (looking down is the least accurate); nodding your chin handles speed.", 14, Color(1, 1, 1, 0.6))
	y += 34.0 * k
	# buttons
	var labels := [["simple", "BACK"], ["resume", "RESUME"], ["ctl", "CONTROL: " + ["GATE", "SIDE", "STEER", "SEEK"][lane_ctl]], ["copy", "COPY REPORT"], ["reset", "RESET LEARNING"], ["head", "HEAD HELP: " + ("ON" if head_assist else "OFF")], ["sens_up", "MORE SENSITIVE"], ["sens_dn", "LESS SENSITIVE"], ["curve_up", "FINER CENTRE"], ["curve_dn", "FLATTER"], ["rate_up", "FASTER"], ["rate_dn", "SMOOTHER"], ["reach_up", "REACH +"], ["reach_dn", "REACH -"], ["smooth_up", "STEADIER"], ["smooth_dn", "SNAPPIER"], ["eyes", "EYES ONLY: " + ("ON" if eyes_only else "OFF")], ["flip", "REVERSE EYES"]]
	if Game.run_mode:
		labels.append(["trace", "TRACE TEST"])
		labels.append(["trace_off", "END TRACE"])
	var bx := m
	var bh := 46.0 * k
	for b in labels:
		var tw := font.get_string_size(String(b[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * k)).x
		var br := Rect2(bx, y, tw + 30.0 * k, bh)
		if br.end.x > s.x - m:
			bx = m
			y += bh + 10.0 * k
			br = Rect2(bx, y, tw + 30.0 * k, bh)
		_hud.draw_rect(br, Color(0.2, 0.5, 0.9, 0.9) if b[0] == "resume" else Color(1, 1, 1, 0.16))
		_text(font, Vector2(br.position.x + 15.0 * k, br.position.y + bh * 0.66), String(b[1]), 18, Color(1, 1, 1))
		_pause_btns.append({"id": b[0], "r": br})
		bx = br.end.x + 12.0 * k
	if _copy_note != "":
		_text(font, Vector2(m, y + bh + 28.0 * k), _copy_note, 16, Color(0.6, 1.0, 0.7))
