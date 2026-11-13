extends Node
## Autoload "GazeProvider": the one place gameplay reads eye / face input from.
##
## Backends (swap at runtime, gameplay never knows which one is live):
##   MOUSE    mouse position is the gaze point; keys simulate face gestures. For
##            development and for playing without a camera.
##   UDP      JSON packets from an external tracker (tools/gaze_helper.py uses
##            MediaPipe Face Landmarker on a webcam; a phone app / ARKit bridge
##            can send the same packets). Low confidence falls back to the mouse.
##   SCRIPTED tests / replays set the gaze directly.
##
## Packet (any subset of keys, UDP port 5005):
##   {"x":0..1, "y":0..1, "conf":0..1, "blink_l":0..1, "blink_r":0..1,
##    "mouth":0..1, "brows":0..1, "yaw":-1..1, "pitch":-1..1}
##
## Keys: F9 hands-free on/off, F10 mouse <-> UDP backend, F8 recentre (UDP).
## Mouse-sim gestures: B blink (tap twice = double), Z/X wink L/R, M mouth, V brows.

signal blinked
signal recentred
signal double_blinked
signal winked(left: bool)
signal mouth_opened
signal brows_raised
signal mode_changed(active: bool)
signal sweep_changed(active: bool)          # a sweep calibration started / ended: a running game holds still while the dot goes round

enum Backend { MOUSE, UDP, SCRIPTED, TOUCH, CAMERA }

const GESTURE_ON := 0.6
const WINK_HOLD := 0.15

var backend: Backend = Backend.MOUSE
var active: bool = false
## Calibrated + filtered gaze in 0..1 screen space (0,0 = top-left).
var gaze: Vector2 = Vector2(0.5, 0.5)
## Finger position (0..1) fed by TouchControls for the TOUCH backend.
var touch_gaze: Vector2 = Vector2(0.5, 0.5)
var confidence: float = 1.0
var head_yaw: float = 0.0
## Head lean as movement: x = strafe (-1 left .. 1 right), y = -1 forward (lean in) .. +1 back.
var head_move: Vector2 = Vector2.ZERO
## Browser camera status text ("loading", "ready", "error: ...").
var camera_status: String = ""
var head_pitch: float = 0.0
var udp_port: int = 5005
## A blink only counts as "deliberate" when the eyes stay shut this long (s).
var blink_min_closed: float = 0.12

var _udp: PacketPeerUDP
var _nx: float = 0.5
var _fw: float = 0.0
var _nx0: float = 0.5
var _fw0: float = 0.0
var _head_ok: bool = false
var _cam_poll: float = 0.0
var _stats_poll: float = 0.0
## Tracker health (web camera): capture-to-page latency and model time per frame in ms (-1 = unknown), camera frames seen, frames dropped because the model was busy.
var trk_lat_ms: float = -1.0
var trk_inf_ms: float = -1.0
var trk_cam_frames: int = 0
var trk_dropped: int = 0
var trk_det_ms: float = -1.0           # of trk_inf_ms, the face-model part (the rest is our own gaze maths and iris fit)
var trk_delegate: String = "?"         # GPU or CPU
var trk_patches: bool = false          # true while the iris fit runs on small full-resolution eye patches (the default), false on the old big-crop path
var trk_roi_moves: int = 0           # how many times the face crop moved / was dropped (to the whole frame) this session
var trk_roi_lost: int = 0
var trk_roi: int = 0                 # side in pixels of the face crop the model is fed (0 = whole frame)
var trk_video: String = "?"          # camera size and frame rate the browser gave us
var _cal_done: bool = false
## 5-dot calibration: centre, left, right, top, bottom. Per axis it picks the steadier of
## two eye signals (iris position / blendshapes) and fits offset + gain to the screen.
const CAL_POINTS: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.15, 0.5), Vector2(0.85, 0.5), Vector2(0.5, 0.15), Vector2(0.5, 0.85),
		Vector2(0.15, 0.15), Vector2(0.85, 0.15), Vector2(0.15, 0.85), Vector2(0.85, 0.85)]
const CAL_SETTLE := 0.7
const CAL_HOLD := 1.4
const BLINK_ON := 0.28
const BLINK_OFF := 0.15
var cal_index: int = -1
var cal_progress: float = 0.0
var cal_settling: bool = true
var cal_note: String = ""
## Live eye-closure above each eye's own open baseline (for the on-screen meters).
var dbg_l: float = 0.0
## Ridge-regression gaze model trained during calibration (many signals -> screen x,y).
var cal_error: float = -1.0            # typical error as a fraction of the screen, from held-out samples
var face_size: float = 0.0             # face width as a fraction of the camera frame
var _ridge_ok: bool = false
var _full: PackedFloat32Array = PackedFloat32Array()
var _r_mean: PackedFloat32Array = PackedFloat32Array()
var _r_std: PackedFloat32Array = PackedFloat32Array()
var _wx: PackedFloat32Array = PackedFloat32Array()
var _wy: PackedFloat32Array = PackedFloat32Array()
var dbg_r: float = 0.0
var last_event: String = ""
var last_event_t: float = -10.0
var _base_l: float = 1.0
var _base_r: float = 1.0
## Calibration-free gaze (3D geometry from the camera tracker): a running mean / spread learns
## where you look, so the offset (off-centre cameras, portrait, side cameras) and scale fix
## themselves while you play. Optional dot calibration (C) overrides it.
## Head pose (turn / nod) is the main aim; the eyes refine it. Head pose comes from the whole face, so it is
## precise and works when the eyelids hide the pupil (head tilted back, looking down).
var head_weight: float = 0.12
var _head_sign: Vector2 = Vector2(1.0, 1.0)      # J / K (or ?flipyaw / ?flippitch) flip these if a direction is reversed
const HEAD_MIN_SIGMA := Vector2(0.03, 0.02)       # radians: ~1.7 deg turn / ~1.1 deg nod = one 'unit' of movement
var _hd_mu: Vector2 = Vector2.ZERO
var _hd_var: Vector2 = Vector2(0.001, 0.0005)
var _hbuf: Array[Vector2] = []
var _zx_var: float = 1.0
## Raw tracker pose for the on-screen 3D monitor (camera conventions: yaw +image-right, pitch +down, roll +counter-clockwise).
var head_rpy: Vector3 = Vector3.ZERO
var gaze_ang: Vector2 = Vector2.ZERO
var head_rpy_ok: bool = false
## Peek (lean out of cover): head position + turn, magnified. Metres of body movement per unit of
## normalised head movement (the head moves ~0.1 of the frame for a 10 cm lean).
var peek_gain: Vector3 = Vector3(16.0, 12.0, 8.0)      # z (lean toward the screen) only; x / y use physical units below
const PEEK_MAX := Vector3(1.8, 1.2, 1.2)
const PEEK_DEAD := Vector3(0.012, 0.012, 0.03)
## Lean is measured in real centimetres (a face is ~14 cm wide, so frame fractions / face size = cm) so the
## same lean feels the same at a desk (face small in frame) and on a phone (face fills the frame).
const PEEK_M_PER_CM := Vector2(0.17, 0.13)
const PEEK_M_PER_RAD := 8.6                           # head turn: 10 degrees ~ 1.5 m of lean
const PEEK_YAW_MIX_PHONE := 0.6                       # held phones jiggle the face in the frame, so lean on head TURN more
var cam_ok_msec: int = 0
## Touch fallbacks (phones): on-screen buttons / drags feed the same signals as the head.
var touch_lean: float = 0.0          # -1 .. +1 sideways lean (peek level)
var touch_steer: float = 0.0         # -1 .. +1 steering (flight)
var touch_nod_goal: float = 0.0      # -1 chin down (hold), +1 chin up (hold)
var _pkt_times: Array[int] = []
## Nod (chin up / down) for the flight game: head pitch relative to your resting head (chin up = positive,
## radians) and how fast it is changing (rad/s). W / S or the up / down arrows stand in without a camera.
var nod_debug: Vector2 = Vector2.INF       # tests: (pitch, velocity) override
var nod_sens: float = 1.0
var _nod_p: float = 0.0
var _nod_v: float = 0.0
var _nod_t: float = 0.0
var _kb_nod: float = 0.0
const PEEK_LOOK := Vector2(2.5, 2.0)
var peek_debug: Vector3 = Vector3.ZERO           # tests / tools
var _ny: float = 0.5
var _ny0: float = 0.5
var _hr0: Vector3 = Vector3.ZERO
var _pk_buf: Array[Vector3] = []
var _pk_target: Vector3 = Vector3.ZERO
var _pk_out: Vector3 = Vector3.ZERO
var _kb_cur: Vector3 = Vector3.ZERO
var _look_out: Vector2 = Vector2.ZERO
var _last_g: Vector2 = Vector2(0.5, 0.5)
var _last_hd: Vector2 = Vector2.ZERO
var _last_open: float = 0.0
var _zp: float = 1.0                              # one-sided spreads of vertical movement (down / up)
var _zn: float = 1.0
const GEO_TARGET := Vector2(0.2, 0.2)    # one standard deviation of your gaze maps to this fraction of the screen
var _open_mu: float = 0.0
var _open_var: float = 0.0004
var _zv_var: float = 1.0
var _geo_buf: Array[Vector3] = []
var _limb_buf: Array[Vector2] = []
var _last_frame_n: int = -1          # camera frame number of the last packet: the poll runs ~33x/s but the camera delivers 12-15 frames/s
var _frame_fresh: bool = true
var _geo_limb: bool = false          # the geometry gaze is built from the precise limbus centres
var bias := EyeBias.new()
var face: Dictionary = {"jaw": 0.0, "brows": 0.0, "smile": 0.0, "tongue": -1.0, "puff": 0.0, "frown": 0.0, "bdown": 0.0, "ewide": 0.0, "esq": 0.0, "pucker": 0.0, "sneer": 0.0}   # blendshapes, lightly smoothed (tongue -1 = this tracker cannot see it)
var face_override: Dictionary = {}        # tests: kind -> true
var pm := PhoneMotion.new()               # phone sensors: removes tilt-following from the iris reading, holds the gaze through a bump, buzzes the hand
var pm_on: bool = true                    # ?nopm turns the stabiliser off to compare
var _eih_frozen_t: float = 0.0
var eye_w := Vector2(-1.0, -1.0)         # automatic per-eye weights (right, left); (-1, -1) until learned
var direct: Vector2 = Vector2(0.5, 0.5)     # the geometry gaze straight from the tracker, only lightly smoothed: the same signal EyeLab shows (no median, no offset learning)
var direct_ok: bool = false
var eih: Vector2 = Vector2(0.5, 0.5)        # where the iris sits INSIDE the eye opening (0..1 across / down): your eyes only, a head turn does not move it
var eih_ok: bool = false
var _efx := OneEuro.new()
var _efy := OneEuro.new()
var _eih_t: float = 0.0
var _direct_t: float = 0.0
var _dfx := OneEuro.new()
var _dfy := OneEuro.new()
var coach := HeadCoach.new()          # head-pose coach: learns your good pose from the camera image, no dots
## Eyes narrowed / opened wide, against your own usual opening (HeadCoach.open_base), smoothed over about a tenth of a second.
const SQUINT_BELOW := 0.78
const WIDE_ABOVE := 1.12
const LID_HOLD := 0.18                # seconds a squint / wide look must last (a blink is shorter)
var eye_open_fast: float = 1.0
## Cross-eyed: both irises turn toward the nose, against each eye's own slow baseline.
const CROSS_ABOVE := 0.06
var _xc_r: float = -1.0
var _xc_l: float = -1.0
var _conv: float = 0.0
var _cross_since: float = -1.0
var _sq_since: float = -1.0
var _wide_since: float = -1.0
var _lid_seen: float = -10.0
var _geo_raw: Vector2 = Vector2(0.5, 0.5)
var _limb_msec: int = -100000
var limb_rad: float = 0.0            # iris radius in camera pixels (how many pixels the eye gets: more is better)
var _geo_n: int = 0
var _geo_mu: Vector2 = Vector2(0.5, 0.5)
var _geo_var: Vector2 = Vector2(0.04, 0.02)
var _geo_out: Vector2 = Vector2(0.5, 0.5)
var _geo_ok: bool = false
var _hist_l: PackedFloat32Array = PackedFloat32Array()
var _hist_r: PackedFloat32Array = PackedFloat32Array()
var _cal_clock: float = 0.0
var _cal_samples: Array = []
var _calibrated: bool = false
var _raw_iris: Vector2 = Vector2(0.5, 0.5)
var _raw_bs: Vector2 = Vector2(0.5, 0.5)
var _feat: Vector2i = Vector2i(0, 0)
var _mid: Vector2 = Vector2(0.5, 0.5)
var _gain: Vector2 = Vector2.ONE
var _cam_failed: bool = false
var _udp_gaze: Vector2 = Vector2(0.5, 0.5)
var _calib: Vector2 = Vector2.ZERO
var _last_packet_msec: int = -100000
var _fx := OneEuro.new()
var _fy := OneEuro.new()
## The gaze point is filtered by a Kalman filter per axis (position + velocity, jumps recognised): steadier than One Euro when you
## look at something, and it keeps gliding between the camera's 14 readings a second. ?nokalman goes back to One Euro to compare.
var kal_on: bool = true
var _kx := GazeKalman.new()
var _ky := GazeKalman.new()
var _kal_pending: bool = false
## One-pass sweep calibration (EyeSweep): a dot glides round the screen, you follow it with your eyes.
var sweep_active: bool = false
var sweep_t: float = 0.0
var sweep_done: bool = false           # a sweep has been fitted this session
var sweep_note: String = ""
var sweep_fit: Dictionary = {}
var _sweep_samples: Array = []
var _closed: bool = false
var _close_t: float = 0.0
var _last_blink_t: float = -10.0
var _wink_state: int = 0
var _wink_since: float = 0.0
var _wink_fired: bool = false
var _mouth_on: bool = false
var _brows_on: bool = false


# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------
## True during the short 'look at the centre of the screen' auto-calibration.
var calibrating: bool:
	get:
		return cal_index >= 0 or sweep_active


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep tracking while a menu pauses the game
	_load_opts()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{fetch('/gaze-lab/profiles.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null}).then(function(j){window.__gazeFleet=j}).catch(function(){})}catch(e){}")
	add_child.call_deferred(GazeOptions.new())      # the in-game EYE OPTIONS panel (shows itself only in Peek and Downhill)
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search"))
		if q.contains("flipyaw"):
			_head_sign.x = -1.0
		if q.contains("flippitch"):
			_head_sign.y = -1.0
		if q.contains("nopm"):
			pm_on = false
		if q.contains("nokalman"):
			kal_on = false
		var dv_flag := str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('gazelab_dev')||''}catch(e){return ''}})()"))
		dev_mode = dv_flag != "0"                     # while this is in development the tester panel is there for everybody; ?nodev hides it (and remembers), ?dev brings it back
		if q.contains("nodev"):
			dev_mode = false
			JavaScriptBridge.eval("try{localStorage.setItem('gazelab_dev','0')}catch(e){}")
		elif q.contains("dev"):
			dev_mode = true
			JavaScriptBridge.eval("try{localStorage.removeItem('gazelab_dev')}catch(e){}")
		if q.contains("noauto"):
			auto_on = false
		if q.contains("share=1"):
			set_share(true)                                  # a link from the person running the test: sharing the numbers is already agreed, no question asked
		elif q.contains("share=0"):
			set_share(false)
		if q.contains("bare"):
			opts_bare()
		if q.contains("tune"):
			tune_request = true
		if q.contains("headw="):
			head_weight = clampf(float(q.split("headw=")[1].split("&")[0]), 0.0, 1.0)
	_dfx.min_cutoff = 2.0
	_dfy.min_cutoff = 2.0
	_dfx.beta = 3.0
	_efx.min_cutoff = 3.0
	_efy.min_cutoff = 3.0
	_efx.beta = 6.0
	_efy.beta = 6.0
	_dfy.beta = 3.0
	_fx.min_cutoff = 0.6
	_fy.min_cutoff = 0.6
	_fx.beta = 1.0
	_fy.beta = 1.0


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not on:
		head_move = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (on or Game.touch_mode) else Input.MOUSE_MODE_CAPTURED
	mode_changed.emit(on)


func set_backend(b: Backend) -> void:
	backend = b
	_fx.reset()
	_fy.reset()
	if b == Backend.UDP:
		if _udp == null:
			_udp = PacketPeerUDP.new()
			var err := _udp.bind(udp_port)
			if err != OK:
				push_warning("GazeProvider: cannot bind UDP %d (err %d), using mouse" % [udp_port, err])
				_udp = null
				backend = Backend.MOUSE
	elif _udp != null:
		_udp.close()
		_udp = null


## Tests / replays: pin the gaze point directly.
func set_scripted(pos: Vector2, conf: float = 1.0) -> void:
	if backend != Backend.SCRIPTED:
		set_backend(Backend.SCRIPTED)
	gaze = pos
	confidence = conf


## Apply one tracker packet (also callable directly by other transports).
func ingest(d: Dictionary) -> void:
	_frame_fresh = true
	if d.has("n") and d["n"] != null:
		_frame_fresh = int(d["n"]) != _last_frame_n
		_last_frame_n = int(d["n"])
	confidence = clampf(float(d.get("conf", 1.0)), 0.0, 1.0)
	if d.has("ew") and d["ew"] != null:
		var ew: Array = d["ew"]
		eye_w = Vector2(float(ew[0]), float(ew[1]))
	if d.has("hyaw"):
		head_rpy = Vector3(float(d["hyaw"]), float(d["hpitch"]), float(d.get("hroll", 0.0)))
		head_rpy_ok = true
	if d.has("gyaw"):
		gaze_ang = Vector2(float(d["gyaw"]), float(d["gpitch"]))
	head_yaw = float(d.get("yaw", 0.0))
	head_pitch = float(d.get("pitch", 0.0))
	var both := float(d.get("blink", 0.0))
	var bl := float(d.get("blink_l", both))
	var br := float(d.get("blink_r", both))
	_gestures(bl, br, float(d.get("mouth", 0.0)), float(d.get("brows", 0.0)), _now())
	face["jaw"] = lerpf(float(face["jaw"]), float(d.get("mouth", 0.0)), 0.5)
	face["brows"] = lerpf(float(face["brows"]), float(d.get("brows", 0.0)), 0.5)
	for fk in ["smile", "puff", "frown", "bdown", "ewide", "esq", "pucker", "sneer"]:
		if d.has(fk):
			face[fk] = lerpf(float(face[fk]), float(d[fk]), 0.5)
	if d.has("tongue"):
		face["tongue"] = lerpf(float(face["tongue"]), float(d["tongue"]), 0.5) if float(d["tongue"]) >= 0.0 else -1.0
	# Eyelids closing makes the iris reading garbage: hold the last gaze through a blink.
	# Judged against each eye's own open level (it varies a lot: glasses, camera angle).
	if maxf(dbg_l, dbg_r) < 0.22 and d.has("x"):
		_raw_iris = Vector2(float(d.get("x", 0.5)), float(d.get("y", 0.5)))
		_raw_bs = Vector2(float(d["bx"]), float(d["by"])) if d.has("bx") else _raw_iris
		_udp_gaze = _raw_iris
		if d.has("f"):
			_full = PackedFloat32Array(d["f"])
		if d.has("gu") and d.has("gv"):
			var lid_open := 0.0
			if _full.size() >= 18:
				lid_open = (_full[16] + _full[17]) * 0.5   # eyelid opening / eye width
			var hd := Vector2.INF
			if _full.size() >= 14:
				hd = Vector2(_full[12], _full[13]) * 0.5   # head yaw / pitch, radians
			if _frame_fresh:
				_geo_push(Vector2(float(d["gu"]), float(d["gv"])), lid_open, hd)
				if head_rpy_ok and lid_open > 0.0:
					if d.has("pp") and d["pp"] != null and not coach.seeded:
						var pp: Array = d["pp"]
						coach.seed(float(pp[0]), float(pp[1]), float(pp[2]))
					coach.add(rad_to_deg(head_rpy.y), -rad_to_deg(head_rpy.x), -rad_to_deg(head_rpy.z), lid_open, _now())
					_track_lids(lid_open)
					if _full.size() >= 2:
						_track_conv(float(_full[0]), float(_full[1]))
		_geo_limb = d.has("glimb") and int(d["glimb"]) == 1
		if _frame_fresh and d.has("lx") and d.has("ly") and d["lx"] != null and d["ly"] != null:
			_limb_buf.append(Vector2(float(d["lx"]), float(d["ly"])))
			var tn2 := _now()
			var edt := clampf(tn2 - _eih_t, 0.005, 0.5)
			_eih_t = tn2
			var ev := Vector2(float(d["lx"]), float(d["ly"]))
			if pm_on and pm.active:
				ev = pm.correct(ev)
			if pm_on and pm.holding() and eih_ok and _eih_frozen_t < 0.4:
				_eih_frozen_t += edt                   # a bump or a re-grip: keep the last reading for a moment (never longer than 0.4 s)
			else:
				_eih_frozen_t = 0.0
				eih = Vector2(_efx.filter(ev.x, edt), _efy.filter(ev.y, edt))
			eih_ok = true
			if _limb_buf.size() > 5:
				_limb_buf.remove_at(0)
			_limb_msec = Time.get_ticks_msec()
		if d.has("lrad") and d["lrad"] != null:
			limb_rad = float(d["lrad"])
		if cal_index >= 0 and _cal_clock >= CAL_SETTLE:
			(_cal_samples[cal_index] as Array).append([_raw_iris, _raw_bs, _full])
	if d.has("nx") and d.has("fw"):
		_nx = float(d["nx"])
		_fw = float(d["fw"])
		face_size = _fw
		if d.has("ny"):
			_ny = float(d["ny"])
		if not _head_ok and _fw > 0.01:
			_head_ok = true
			_nx0 = _nx
			_fw0 = _fw
			_ny0 = _ny
			_hr0 = head_rpy
			cam_ok_msec = Time.get_ticks_msec()
		_update_head_move()
		_update_peek()
		_update_nod()
	_last_packet_msec = Time.get_ticks_msec()
	if _frame_fresh:
		_kal_pending = true
		_pkt_times.append(_last_packet_msec)
	while not _pkt_times.is_empty() and _last_packet_msec - _pkt_times[0] > 2000:
		_pkt_times.remove_at(0)
	if backend == Backend.CAMERA and not _cal_done and cal_index < 0 and confidence > 0.5 and d.has("x"):
		_cal_done = true
		if d.has("gu"):
			Game.banner("Camera ready: it calibrates itself, no dots to stare at", Color(0.5, 1.0, 0.6), 3.0)
		else:
			Game.banner("Camera ready", Color(0.5, 1.0, 0.6), 2.0)          # never the nine-dot calibration by itself: the one-pass sweep and the doctor do the work


## True when a tracker is feeding us (or we're simulating with the mouse).
func tracking_ok() -> bool:
	return backend != Backend.UDP or (Time.get_ticks_msec() - _last_packet_msec < 500 and confidence >= 0.2)


func backend_name() -> String:
	return ["mouse-sim", "webcam/UDP", "scripted", "touch", "camera"][backend]


## A known fact for the automatic offset: right now the player is looking at `screen_pos`.
func eye_anchor(screen_pos: Vector2, weight: float = 0.5) -> void:
	if _geo_limb:
		bias.anchor(_geo_raw, head_rpy.y if head_rpy_ok else 0.0, _last_open, screen_pos, weight)


func recentre() -> void:
	recentred.emit()
	if _geo_limb and (Game.peek_mode or Game.flight_mode or (Game.trance_mode or Game.gaze_test_mode)):
		eye_anchor(bias.target, 1.0)
	if backend == Backend.CAMERA:
		_nx0 = _nx
		_ny0 = _ny
		if _fw > 0.01:
			_fw0 = _fw
		_hr0 = head_rpy
		_pk_buf.clear()
		if Game.peek_mode or Game.downhill_mode:
			Game.banner("Centred", Color(0.5, 1.0, 0.6), 1.0)
			return
		if _geo_ok:
			# No dots: just call "where I am right now" the centre. Scale (how far you move) is kept.
			_geo_mu = _last_g
			_hd_mu = _last_hd
			_open_mu = _last_open
			_geo_buf.clear()
			_hbuf.clear()
			Game.banner("Centred on where you are now", Color(0.5, 1.0, 0.6), 1.2)
			return
		start_calibration()
		return
	_calib = Vector2(0.5, 0.5) - _udp_gaze
	if _head_ok:
		_nx0 = _nx
		_fw0 = _fw


# --------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------
## The usual opening is YOUR median over the last ~8 s of play, not a high percentile: someone who always squints a little (glasses, a low camera) must not be
## read as squinting all the time. A squint is 22% narrower than your recent normal, wide is 12% wider. A squint that never lets up for 3 s is the new normal.
var _lid_hist: Array = []


func lid_baseline() -> float:
	if _lid_hist.size() < 12:
		return 0.0
	var v: Array = []
	for p in _lid_hist:
		v.append(float(p[1]))
	v.sort()
	return float(v[v.size() / 2])


func _track_lids(lid_open: float) -> void:
	if not is_finite(lid_open) or lid_open <= 0.0:
		return
	var t := _now()
	_lid_seen = t
	_lid_hist.append([t, lid_open])
	while not _lid_hist.is_empty() and t - float(_lid_hist[0][0]) > 8.0:
		_lid_hist.remove_at(0)
	var base := lid_baseline()
	if base <= 0.001:
		return
	if pm_on and pm.settling():
		_sq_since = -1.0                                   # the grip is changing; the lid baseline has not caught up yet
		_wide_since = -1.0
		return
	eye_open_fast = lerpf(eye_open_fast, lid_open / base, 0.5)
	if eye_open_fast < SQUINT_BELOW and eye_open_fast > 0.3 and (_sq_since < 0.0 or t - _sq_since < 3.0):
		if _sq_since < 0.0:
			_sq_since = t
	else:
		_sq_since = -1.0
	if eye_open_fast > WIDE_ABOVE and (_wide_since < 0.0 or t - _wide_since < 3.0):
		if _wide_since < 0.0:
			_wide_since = t
	else:
		_wide_since = -1.0


func _track_conv(xr: float, xl: float) -> void:
	if _xc_r < 0.0:
		_xc_r = xr
		_xc_l = xl
	_conv = lerpf(_conv, (xr - _xc_r) - (xl - _xc_l), 0.4)
	var t := _now()
	if _conv > CROSS_ABOVE:
		if _cross_since < 0.0:
			_cross_since = t
	else:
		_cross_since = -1.0
		_xc_r = lerpf(_xc_r, xr, 0.02)                  # the baseline follows slowly, so a held look-at-the-nose does not become normal
		_xc_l = lerpf(_xc_l, xl, 0.02)


func cross_eyed() -> bool:
	return _cross_since >= 0.0 and _now() - _cross_since >= LID_HOLD and _now() - _lid_seen < 0.6


## Is the player pulling this face right now? (Thresholds are for the raw blendshape scores, which run a little low for most people.)
func face_is(kind: String) -> bool:
	if face_override.get(kind, false):
		return true
	var f := face
	match kind:
		"tongue":
			if float(f["tongue"]) >= 0.0:
				return float(f["tongue"]) > 0.3
			return float(f["jaw"]) > 0.5 and float(f["smile"]) < 0.25          # no tongue sensor: a wide open mouth stands in for it
		"smile":
			return float(f["smile"]) > 0.5
		"shock":
			return float(f["jaw"]) > 0.35 and float(f["brows"]) > 0.4 and float(f["ewide"]) > 0.25
		"pain":
			return float(f["bdown"]) > 0.4 and float(f["esq"]) > 0.3
		"wide":
			return wide_held() or float(f["ewide"]) > 0.65
		"cross":
			return cross_eyed()
		"squint":
			return squint_held()
		"puff":
			return float(f["puff"]) > 0.4
		"kiss":
			return float(f["pucker"]) > 0.5
		"sneer":
			return float(f["sneer"]) > 0.45
	return false


func squint_held() -> bool:
	return _sq_since >= 0.0 and _now() - _sq_since >= LID_HOLD and _now() - _lid_seen < 0.6


func wide_held() -> bool:
	return _wide_since >= 0.0 and _now() - _wide_since >= LID_HOLD and _now() - _lid_seen < 0.6


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	match k.physical_keycode:
		KEY_F9:
			set_active(not active)
		KEY_F10:
			if backend == Backend.MOUSE or backend == Backend.TOUCH:
				if OS.has_feature("web"):
					start_camera()
				else:
					set_backend(Backend.UDP)
			else:
				head_move = Vector2.ZERO
				set_backend(Backend.MOUSE)
		KEY_J:
			_head_sign.x = -_head_sign.x
			Game.banner("Head left/right flipped", Color(0.7, 0.9, 1.0), 1.2)
		KEY_K:
			if not Game.peek_mode:
				_head_sign.y = -_head_sign.y
				Game.banner("Head up/down flipped", Color(0.7, 0.9, 1.0), 1.2)
		KEY_F8, KEY_C:
			if active or Game.peek_mode or Game.downhill_mode or Game.gaze_test_mode:
				recentre()
		_:
			if active and backend == Backend.MOUSE:
				match k.physical_keycode:
					KEY_B:
						_emit_blink(_now())
					KEY_Z:
						winked.emit(true)
					KEY_X:
						winked.emit(false)
					KEY_M:
						mouth_opened.emit()
					KEY_V:
						brows_raised.emit()


func _process(delta: float) -> void:
	if not active and not Game.peek_mode and not Game.flight_mode and not (Game.trance_mode or Game.gaze_test_mode):
		return
	var rd := delta / maxf(Engine.time_scale, 0.05)
	_health_tick(rd)
	match backend:
		Backend.MOUSE:
			var vp := get_viewport().get_visible_rect().size
			gaze = (get_viewport().get_mouse_position() / vp).clamp(Vector2.ZERO, Vector2.ONE)
			confidence = 1.0
		Backend.TOUCH:
			gaze = touch_gaze
			confidence = 1.0
		Backend.UDP, Backend.CAMERA:
			if backend == Backend.CAMERA:
				pm.poll(rd)
				_poll_camera(rd)
				if cal_index >= 0:
					_calibrate_tick(rd)
				if sweep_active:
					sweep_t += rd
					if sweep_t >= EyeSweep.duration() + 0.3:
						_finish_sweep()
			else:
				_poll_udp()
			if Time.get_ticks_msec() - _last_packet_msec > 1500:
				confidence = move_toward(confidence, 0.0, rd * 2.0)
			var vp2 := get_viewport().get_visible_rect().size
			if confidence < 0.2:
				gaze = (get_viewport().get_mouse_position() / vp2).clamp(Vector2.ZERO, Vector2.ONE)
			else:
				var c := _udp_gaze + _calib
				if _calibrated:
					c = Vector2((_feat_vec(_feat.x).x - _mid.x) * _gain.x + 0.5, (_feat_vec(_feat.y).y - _mid.y) * _gain.y + 0.5)
				if _ridge_ok and _full.size() == _r_mean.size():
					c = _predict(_full)
				elif _geo_ok and not _calibrated:
					c = _geo_out
				if kal_on:
					var fresh_k := _kal_pending
					_kal_pending = false
					gaze = Vector2(_kx.step(c.x, rd, fresh_k), _ky.step(c.y, rd, fresh_k)).clamp(Vector2.ZERO, Vector2.ONE)
				else:
					gaze = Vector2(_fx.filter(c.x, rd), _fy.filter(c.y, rd)).clamp(Vector2.ZERO, Vector2.ONE)
				if hold_on:
					# fixation hold: small movements inside a dead zone are ignored, a bigger one drags the zone along, a jump moves it at once
					var hd := gaze - _hold_pt
					var hl := hd.length()
					if hl > 0.16:
						_hold_pt = gaze
					elif hl > HOLD_R:
						_hold_pt = gaze - hd / hl * HOLD_R
					gaze = _hold_pt


func _poll_udp() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			ingest(parsed as Dictionary)


func _gestures(blink_l: float, blink_r: float, mouth: float, brows: float, now: float) -> void:
	# Each eye has its own "open" level (often 0.1-0.3). Track it slowly while the eye is
	# open, and judge closure relative to it. That is what makes winks detectable.
	# The "eyes open" level is the 25th percentile of the last ~3 s, so it self-heals if early
	# frames were odd, and a blink or a held wink never drags it up.
	_hist_l.append(blink_l)
	_hist_r.append(blink_r)
	if _hist_l.size() > 90:
		_hist_l.remove_at(0)
		_hist_r.remove_at(0)
	_base_l = _pct(_hist_l, 0.25)
	_base_r = _pct(_hist_r, 0.25)
	var l := maxf(blink_l - _base_l, 0.0)
	var r := maxf(blink_r - _base_r, 0.0)
	dbg_l = l
	dbg_r = r
	# Deliberate blink: both eyes shut for a moment, then open (hysteresis on/off).
	var both := minf(l, r)
	if both > BLINK_ON:
		if not _closed:
			_closed = true
			_close_t = now
	elif _closed and both < BLINK_OFF:
		_closed = false
		var dur := now - _close_t
		if dur >= blink_min_closed and dur < 1.5:
			_emit_blink(now)
			last_event = "BLINK"
			last_event_t = now
	# Wink: one eye clearly shut while the other stays open, held briefly.
	var state := 0
	if l > BLINK_ON and r < 0.12:
		state = 1
	elif r > BLINK_ON and l < 0.12:
		state = 2
	if state != _wink_state:
		_wink_state = state
		_wink_since = now
		_wink_fired = false
	elif state != 0 and not _wink_fired and now - _wink_since >= 0.1:
		_wink_fired = true
		winked.emit(state == 1)
		last_event = "WINK " + ("LEFT" if state == 1 else "RIGHT")
		last_event_t = now
	if mouth > GESTURE_ON and not _mouth_on:
		mouth_opened.emit()
	_mouth_on = mouth > GESTURE_ON
	if brows > GESTURE_ON and not _brows_on:
		brows_raised.emit()
	_brows_on = brows > GESTURE_ON


func _emit_blink(now: float) -> void:
	blinked.emit()
	if now - _last_blink_t < 0.7:
		double_blinked.emit()
	_last_blink_t = now


## Lean sideways = strafe, lean toward the screen = walk forward, lean back = back up.
func _update_head_move() -> void:
	var lean := _nx - _nx0
	var x := signf(lean) * maxf(absf(lean) - 0.04, 0.0) / 0.10
	var z := _fw / maxf(_fw0, 0.01) - 1.0     # > 0: closer to the camera
	var y := -signf(z) * maxf(absf(z) - 0.07, 0.0) / 0.20
	head_move = head_move.lerp(Vector2(clampf(x, -1.0, 1.0), clampf(y, -1.0, 1.0)), 0.4)


## Browser camera tracking (MediaPipe Face Landmarker, runs on-device, nothing is
## uploaded). Web builds only; needs the camera permission.
func start_camera() -> void:
	if not OS.has_feature("web"):
		camera_status = "camera tracking needs the web build"
		return
	if backend != Backend.CAMERA:
		set_backend(Backend.CAMERA)
		JavaScriptBridge.eval(GazeCamJS.source())
		JavaScriptBridge.eval("window.__gazeStart()")
		camera_status = "starting"
		reset_gestures()
		_geo_buf.clear()
		_geo_n = 0
		_geo_mu = Vector2(0.5, 0.5)
		_geo_var = Vector2(0.04, 0.02)
		_open_mu = 0.0
		_open_var = 0.0004
		_zv_var = 1.0
		_zx_var = 1.0
		_zp = 1.0
		_zn = 1.0
		_hd_mu = Vector2.ZERO
		_hd_var = Vector2(0.001, 0.0005)
		_hbuf.clear()
		_geo_ok = false
		cal_index = -1
		_cal_done = false
		_calibrated = false
		_ridge_ok = false
		_cam_failed = false


func _poll_camera(rd: float) -> void:
	_cam_poll -= rd
	if _cam_poll > 0.0:
		return
	var pt0 := Time.get_ticks_usec()
	_poll_camera_inner(rd)
	var pms := float(Time.get_ticks_usec() - pt0) / 1000.0
	poll_ms = pms if poll_ms <= 0.0 else lerpf(poll_ms, pms, 0.05)


var poll_ms: float = 0.0               # what reading the tracker costs the game, per frame (ms)


func _poll_camera_inner(rd: float) -> void:
	_cam_poll = 0.008      # about every game frame: a 30 fps camera must not lose up to 30 ms to our own polling
	_stats_poll -= rd
	if _stats_poll <= 0.0:
		_stats_poll = 0.5
		var sj: Variant = JavaScriptBridge.eval("(function(){var s=window.__gazeStats||{};return JSON.stringify([s.lat===undefined?-1:s.lat,s.inf===undefined?-1:s.inf,s.cf||0,s.drop||0,s.pk||0,s.det===undefined?-1:s.det,s.dlg||'?',s.vw||0,s.vh||0,s.cfps||0,s.roi||0,s.rmv||0,s.rlost||0,s.pa||0])})()")
		var sp: Variant = JSON.parse_string(str(sj))
		if sp is Array and (sp as Array).size() == 14:
			trk_patches = int(sp[13]) == 1
			trk_roi = int(sp[10])
			trk_roi_moves = int(sp[11])
			trk_roi_lost = int(sp[12])
			trk_lat_ms = float(sp[0])
			trk_inf_ms = float(sp[1])
			trk_cam_frames = int(sp[2])
			trk_dropped = int(sp[3])
			trk_det_ms = float(sp[5])
			trk_delegate = str(sp[6])
			trk_video = "%dx%d @%d" % [int(sp[7]), int(sp[8]), int(float(sp[9]))]
	var st: Variant = JavaScriptBridge.eval("window.__gazeStatus || ''")
	camera_status = str(st)
	if camera_status.begins_with("error") and not _cam_failed:
		_cam_failed = true
		Game.banner("Camera unavailable: using touch / mouse as your eyes", Color(1.0, 0.7, 0.3), 3.5)
		set_backend(Backend.TOUCH if Game.touch_mode else Backend.MOUSE)
		return
	var js: Variant = JavaScriptBridge.eval("window.__gaze ? JSON.stringify(window.__gaze) : ''")
	var txt := str(js)
	if txt != "":
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			ingest(parsed as Dictionary)


# --------------------------------------------------------------------------
# Calibration
# --------------------------------------------------------------------------
func _feat_vec(i: int) -> Vector2:
	return _raw_iris if i == 0 else _raw_bs


func start_calibration() -> void:
	cal_index = 0
	_cal_clock = 0.0
	cal_note = ""
	_ridge_ok = false
	_cal_samples = []
	for i in CAL_POINTS.size():
		_cal_samples.append([])


# --------------------------------------------------------------------------
# Test switches (the in-game EYE OPTIONS panel): every layer between the eyes and the game can be turned off
# --------------------------------------------------------------------------
const OPT_FILE := "user://gaze_opts.cfg"
const HOLD_R := 0.035
var hold_on: bool = false
var geo_win: int = 5                   # readings in the median that comes before everything else (1 = none)
var opt_pick: int = 0                  # Downhill gate choice: 0 = the gate nearest your gaze within a tolerance (as before), 1 = gaze zones with hysteresis
var gate_log: Array = []               # one entry per barrier passed in Downhill: where the gates were, where you looked, where you went
var _hold_pt: Vector2 = Vector2(0.5, 0.5)
var _sweep_lin: Array = []
var tune_request: bool = false         # the panel (or ?tune) asks the Downhill rig to start a tuning session
var tune_summary: Array = []
var tune_trials: Array = []
var auto_on: bool = true               # the silent doctor (GazeDoctor) and the health rules: on for everybody, nobody has to know about it
var dev_mode: bool = false             # ?dev, ?who= or a remembered dev flag: the EYE OPTIONS panel and the on-screen AUTO messages are only for testers
var doctor := GazeDoctor.new()
## What the doctor may adjust besides the switches (read by the game every frame): how long a look must stay on a gate before it latches (x), how many metres of sideways
## room per metre forward the pull toward a chosen gate asks for (smaller = earlier), how hard the pull is (x), and how far a look moves the cursor (x).
var p_linger: float = 1.0
var p_pull: float = 0.22
var p_carve: float = 1.0
var p_reach: float = 1.0
var auto_log: Array = []
## Frame capture for the camera-vs-decision analysis: OFF every time the page loads, switched on by the player in EYE OPTIONS. Each captured frame (a face crop, a small whole
## frame and the tracker's numbers) goes to the local test server only, with what the game decided at that moment.
var capture_on: bool = false
var capture_n: int = 0
const CAPTURE_MAX := 300
var tune_phase: String = ""            # set by the rig: while a setting is being tested (explore / challenge) the AUTO rules keep their hands off
var health: Dictionary = {}            # the latest health sample (every 5 s): frame rate, tracker rate, latency, jitter, how much of the screen the gaze covers
var _h_ft := PackedFloat32Array()
var _h_gx := PackedFloat32Array()
var _h_gy := PackedFloat32Array()
var _h_dr := PackedFloat32Array()
var _h_do := PackedFloat32Array()
var _h_prev_raw: Vector2 = Vector2.INF
var _h_prev_out: Vector2 = Vector2.INF
var _h_clock: float = 0.0
var _h_samp: float = 0.0
var _h_narrow: int = 0
var _h_slow: int = 0
var _h_note_t: float = -100.0


## Frame rate, tracker rate, jitter and screen coverage, sampled continuously; a summary every 5 s goes into the report and, on the local test
## server, into tools/tune_results.jsonl as it happens (so it can be watched while you play).
## Consent to share anonymous numbers (no images, no video, no names) with the people running this site. Asked once, after the camera has started, never on a dev host.
var share_state: String = "1"          # "1" sharing (the default while in development), "0" the player turned it off
var _share_loaded: bool = false
var _app_last: String = ""
var _cam_good_t: float = 0.0
var _sweep_tried: bool = false


func _on_dev_host() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("(location.hostname==='localhost'||location.port==='8443')"))


const SHARE_BY_DEFAULT := true         # development: anonymous numbers are shared unless the player turns it off (a clear opt-in button replaces this before it is public)


func consent_needed() -> bool:
	if SHARE_BY_DEFAULT:
		return false
	if not OS.has_feature("web") or backend != Backend.CAMERA or not _camera_fresh():
		return false
	if not _share_loaded:
		_share_loaded = true
		share_state = str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('gazelab_share')||''}catch(e){return ''}})()"))
		if _on_dev_host():
			share_state = "1"
	return share_state == ""


func set_share(yes: bool) -> void:
	share_state = "1" if yes else "0"
	JavaScriptBridge.eval("try{localStorage.setItem('gazelab_share','" + share_state + "')}catch(e){}")


## One calibration sweep per visit, in every app, once the camera is delivering a good face (or when the doctor asks for one).
func _auto_sweep_check(rd: float) -> void:
	if backend != Backend.CAMERA or not auto_on:
		return
	if _camera_fresh() and confidence > 0.5 and face_size > 0.12:
		_cam_good_t += rd
	else:
		_cam_good_t = 0.0
	if sweep_active:
		return
	# never at the start: only when the stats show a tracking problem (the doctor asks), only once the player has been playing a while, and only once per visit by itself
	if doctor.sweep_wanted and _cam_good_t > 20.0 and not _sweep_tried:
		doctor.sweep_wanted = false
		_sweep_tried = true
		start_sweep()


## Peek: how far the eyes read from the baddy being looked at (screen widths, %), sampled while locked. A poor reading asks for a calibration sweep and steadies the gaze point.
var _pf_win: Array = []
var _pf_bad: int = 0


func peek_fix_sample(err_pct: float) -> void:
	if not auto_on or not Game.peek_eye_aim:
		return
	_pf_win.append(err_pct)
	if _pf_win.size() < 14:
		return
	var s := _pf_win.duplicate()
	s.sort()
	var med: float = float(s[s.size() / 2])
	_pf_win.clear()
	if med <= 10.0:
		_pf_bad = 0
		return
	_pf_bad += 1
	var what := ""
	if not sweep_done and not sweep_active:
		doctor.sweep_wanted = true
		what = "calibrate the eyes with one sweep"
	elif not hold_on:
		opt_set("hold", true)
		what = "steady the gaze point (fixation hold)"
	if what != "":
		doctor_event({"event": "action", "issue": "PEEK_GAZE_OFF", "evidence": {"median_error_pct": snappedf(med, 0.1), "windows": _pf_bad}, "action": what})


# --------------------------------------------------------------------------
# The load-time tuner (GazeTuner): camera exposure (only in a dim room), camera resolution and tracker rate, a few seconds per option, once per device
# --------------------------------------------------------------------------
const PROFILE_FILE := "user://gaze_profile.cfg"
var tuner := GazeTuner.new()
var tuner_state: String = "wait"          # wait -> running -> done
var applied: Dictionary = {"cap": 0, "res": 0, "expo": "auto"}
var tuning_flash: String = ""
var tuning_flash_t: float = 0.0
var _tn_baseline: float = -1.0
var _tn_guard_t: float = 0.0
var _tn_guard_bad: int = 0
var _tn_cool: float = 0.0
var _tn_ema: Dictionary = {"game": 0.0, "trk": 0.0, "lat": 0.0}
var _sweep_bias0: Vector2 = Vector2.ZERO
var _drift_n: int = 0
var _drift_last: float = -1000.0
var _h_shake: int = 0
var _shake_hold: bool = false
var _shake_prev_hold: bool = false


func tuner_apply(key: String, v: Variant) -> void:
	applied[key] = v
	if not OS.has_feature("web"):
		return
	match key:
		"cap":
			JavaScriptBridge.eval("window.__gazeCap=%d" % int(v))
		"res":
			if int(v) > 0:
				JavaScriptBridge.eval("window.__gazeSetRes&&window.__gazeSetRes(%d)" % int(v))
		"expo":
			JavaScriptBridge.eval("window.__gazeExposure&&window.__gazeExposure(%s)" % ("true" if str(v) == "fast" else "false"))


## Which device this is (hardware + screen + camera): the saved tuning is per device and camera.
func profile_key() -> String:
	var h := hw_info()
	return ("%s|%s|%s|%s|%s" % [h.get("platform", "?"), h.get("cores", "?"), str(h.get("gpu", "?")).substr(0, 40), str(h.get("screen", "?")), cam_label()]).md5_text().substr(0, 10)


## A coarse class of hardware (for the fleet table built from everybody's logs).
func hw_class() -> String:
	var h := hw_info()
	return "%s|%s|%s" % [h.get("platform", "?"), "touch" if int(h.get("touch", 0)) > 0 else "pointer", str(h.get("gpu", "?")).substr(0, 24)]


func _tuner_metrics() -> Dictionary:
	return {"game": float(Engine.get_frames_per_second()), "trk": float(_pkt_times.size()) / 2.0, "lat": maxf(trk_lat_ms, 0.0)}


func _tuner_knobs() -> Array:
	var ks: Array = []
	var phone := device_tag() == "mobile"
	if OS.has_feature("web"):
		var br := float(JavaScriptBridge.eval("window.__gazeBright ? window.__gazeBright() : -1"))
		if br >= 0.0 and br < 70.0:
			ks.append({"id": "expo", "label": "camera exposure (dim room)", "options": [{"v": "auto", "label": "automatic"}, {"v": "fast", "label": "short fixed exposure"}]})
	var ro: Array = [{"v": 0, "label": "as chosen"}, {"v": 480, "label": "480p"}] if phone else [{"v": 0, "label": "as chosen"}, {"v": 720, "label": "720p"}, {"v": 480, "label": "480p"}]
	ks.append({"id": "res", "label": "camera resolution", "options": ro})
	ks.append({"id": "cap", "label": "tracker rate", "options": [{"v": 0, "label": "as fast as it goes"}, {"v": 24, "label": "at most 24 a second"}, {"v": 18, "label": "at most 18 a second"}]})
	return ks


func _tuner_begin() -> void:
	var cf := ConfigFile.new()
	var key := profile_key()
	if cf.load(PROFILE_FILE) == OK and cf.has_section(key):
		for id in ["cap", "res", "expo"]:
			if cf.has_section_key(key, id):
				tuner_apply(id, cf.get_value(key, id))
		_tn_baseline = float(cf.get_value(key, "score", -1.0))
		tuner_state = "done"
		_tn_guard_t = 0.0
		tuning_flash = "settings for this device restored"
		tuning_flash_t = 4.0
		post_stream("tuner", {"event": "restored", "key": key, "class": hw_class(), "applied": applied})
		return
	var fleet: Variant = null
	if OS.has_feature("web"):
		fleet = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify((window.__gazeFleet && window.__gazeFleet[" + JSON.stringify(hw_class()) + "]) || null)")))
	if fleet is Dictionary:
		for id in ["cap", "res", "expo"]:
			if (fleet as Dictionary).has(id):
				tuner_apply(id, (fleet as Dictionary)[id])
		_tn_baseline = -1.0
		tuner_state = "done"
		_tn_guard_t = 0.0
		tuning_flash = "starting from what worked on similar devices"
		tuning_flash_t = 4.0
		post_stream("tuner", {"event": "fleet", "key": key, "class": hw_class(), "applied": applied})
		return
	tuner.start(_tuner_knobs())
	tuner_state = "running" if tuner.active else "done"
	post_stream("tuner", {"event": "start", "key": key, "class": hw_class(), "hw": hw_short()})


func _tuner_finish() -> void:
	tuner_state = "done"
	_tn_baseline = tuner.final_score
	_tn_guard_t = 0.0
	var cf := ConfigFile.new()
	cf.load(PROFILE_FILE)
	var key := profile_key()
	for id in tuner.chosen:
		cf.set_value(key, str(id), tuner.chosen[id])
	cf.set_value(key, "score", tuner.final_score)
	if DisplayServer.get_name() != "headless":
		cf.save(PROFILE_FILE)
	var parts: Array = []
	for id in tuner.chosen:
		parts.append("%s=%s" % [id, str(tuner.chosen[id])])
	tuning_flash = "tuned for this device: " + ", ".join(parts)
	tuning_flash_t = 5.0
	post_stream("tuner", {"event": "done", "key": key, "class": hw_class(), "hw": hw_short(), "chosen": tuner.chosen, "score": snappedf(tuner.final_score, 0.001), "log": tuner.log})


func _tuner_tick(rd: float) -> void:
	tuning_flash_t = maxf(tuning_flash_t - rd, 0.0)
	if not auto_on or backend != Backend.CAMERA:
		return
	_tn_cool = maxf(_tn_cool - rd, 0.0)
	var m := _tuner_metrics()
	for key in _tn_ema:
		_tn_ema[key] = lerpf(float(_tn_ema[key]), float(m[key]), clampf(rd / 8.0, 0.0, 1.0))
	if tuner_state == "wait":
		if _cam_good_t > 6.0 and not sweep_active:
			_tuner_begin()
	elif tuner_state == "running":
		if sweep_active:
			return
		var ev := tuner.tick(rd, m)
		if not ev.is_empty():
			if ev["event"] == "knob" or ev["event"] == "done":
				post_stream("tuner", {"event": "knob", "knob": ev["knob"], "kept": ev["kept"], "score": snappedf(float(ev["score"]), 0.001), "default_score": snappedf(float(ev["default"]), 0.001)})
				tuning_flash = "%s: kept '%s'" % [ev["knob"], ev["kept"]]
				tuning_flash_t = 3.0
			if ev["event"] == "done":
				_tuner_finish()
	elif tuner_state == "done":
		# the heat / battery guard: if the machine is clearly slower than when it was tuned, tune again (at most every five minutes)
		_tn_guard_t += rd
		if _tn_guard_t >= 30.0:
			_tn_guard_t = 0.0
			var cur := GazeTuner.score(_tn_ema)
			if _tn_baseline < 0.0:
				_tn_baseline = cur
			elif cur < _tn_baseline * 0.75:
				_tn_guard_bad += 1
			else:
				_tn_guard_bad = 0
			if _tn_guard_bad >= 2 and _tn_cool <= 0.0:
				_tn_guard_bad = 0
				_tn_cool = 300.0
				tuner_state = "wait"
				_cam_good_t = 7.0
				tuning_flash = "the machine slowed down: tuning again"
				tuning_flash_t = 4.0
				post_stream("tuner", {"event": "retune", "score_now": snappedf(cur, 0.001), "baseline": snappedf(_tn_baseline, 0.001)})
				var cf := ConfigFile.new()
				if cf.load(PROFILE_FILE) == OK:
					cf.erase_section(profile_key())
					if DisplayServer.get_name() != "headless":
						cf.save(PROFILE_FILE)


## What the corner indicator says right now (empty: nothing is being tried).
func tuning_text() -> Dictionary:
	if tuner.active and tuner_state == "running":
		var st := tuner.status()
		if not st.is_empty():
			return {"text": "TUNING  %s: %s" % [st["element"], st["option"]], "frac": 1.0 - float(st["left"]) / maxf(float(st["total"]), 0.01), "step": "%d / %d" % [int(st["step"]), int(st["steps"])]}
	if not doctor.pending.is_empty():
		var act: Dictionary = doctor.pending["action"]
		return {"text": "CHECKING  %s" % str(act["label"]), "frac": float(doctor.pending["seen"]) / float(GazeDoctor.WIN), "step": "%d / %d barriers" % [int(doctor.pending["seen"]), GazeDoctor.WIN]}
	if tuning_flash_t > 0.0:
		return {"text": tuning_flash, "frac": -1.0, "step": ""}
	return {}


func _health_tick(rd: float) -> void:
	_tuner_tick(rd)
	_auto_sweep_check(rd)
	var app_now := app_id()
	if app_now != _app_last:
		_app_last = app_now
		post_stream("app", {"app": app_now})
	_h_ft.append(rd * 1000.0)
	if _h_ft.size() > 300:
		_h_ft.remove_at(0)
	if backend == Backend.CAMERA:
		_h_samp -= rd
		if _h_samp <= 0.0:
			_h_samp = 0.1
			_h_gx.append(gaze.x)
			_h_gy.append(gaze.y)
			if _h_gx.size() > 200:
				_h_gx.remove_at(0)
				_h_gy.remove_at(0)
			if _h_prev_raw.is_finite():
				_h_dr.append(_last_g.distance_to(_h_prev_raw))
				_h_do.append(gaze.distance_to(_h_prev_out))
				if _h_dr.size() > 50:
					_h_dr.remove_at(0)
					_h_do.remove_at(0)
			_h_prev_raw = _last_g
			_h_prev_out = gaze
	_h_clock += rd
	if _h_clock >= 5.0:
		_h_clock = 0.0
		_health_sample()


func _quiet_mean(a: PackedFloat32Array) -> float:
	if a.size() < 8:
		return -1.0
	var b := a.duplicate()
	b.sort()
	var t := 0.0
	var n := int(float(b.size()) * 0.7)
	for i in n:
		t += b[i]
	return t / maxf(n, 1.0)


func _pctl(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(float(b.size()) * q), 0, b.size() - 1)]


func _health_sample() -> void:
	var span := Vector2(_pctl(_h_gx, 0.95) - _pctl(_h_gx, 0.05), _pctl(_h_gy, 0.95) - _pctl(_h_gy, 0.05))
	health = {"gameFps": int(Engine.get_frames_per_second()), "frameP95ms": snappedf(_pctl(_h_ft, 0.95), 0.1), "trackerFps": snappedf(float(_pkt_times.size()) / 2.0, 0.1),
		"latencyMs": int(trk_lat_ms), "modelMs": int(trk_inf_ms), "confidence": snappedf(confidence, 0.01), "face": snappedf(face_size, 0.01),
		"jitterRaw": snappedf(_quiet_mean(_h_dr), 0.001), "jitterOut": snappedf(_quiet_mean(_h_do), 0.001), "spanX": snappedf(span.x, 0.01), "spanY": snappedf(span.y, 0.01),
		"device": device_tag(), "view": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)], "camera": cam_label(), "mode": app_id(), "app": app_id(), "eyeAim": Game.peek_eye_aim, "gaze": [snappedf(gaze.x, 0.01), snappedf(gaze.y, 0.01)], "eyeLook": [snappedf(Game.peek_eye_look.x, 0.01), snappedf(Game.peek_eye_look.y, 0.01)], "offset": [snappedf(bias.bias.x, 0.01), snappedf(bias.bias.y, 0.01)], "scale": [snappedf(bias.scale_lo.x, 0.01), snappedf(bias.scale_hi.x, 0.01)], "locked": bias.cal_locked, "kalman": kal_on, "hold": hold_on, "median": geo_win, "pick": opt_pick, "auto": auto_on}
	if backend == Backend.CAMERA:
		post_stream("health", health)
		if auto_on:
			_auto_rules()


## Who is testing, which visit, and on what: every logged line carries all three, so sessions from different people and devices never mix.
## The tester name comes from ?who=name (remembered in the browser afterwards) or the box in EYE OPTIONS. The session id is new on every page load.
var tester: String = ""
var session_id: String = ""
var hw: Dictionary = {}
var device: String = ""


## Which Godot app is running (the same logging and the same doctor apply to every one of them).
func app_id() -> String:
	if Game.run_mode:
		return "downhill"
	if Game.downhill_mode:
		return "lanes"
	if Game.peek_mode:
		return "peek"
	if Game.flight_mode:
		return "flight"
	if Game.trance_mode:
		return "trance"
	if Game.gaze_test_mode:
		return "gazetest"
	return "arena"


func tester_name() -> String:
	if tester != "":
		return tester
	var n := ""
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('who') || ''"))
		if q != "":
			n = q
			JavaScriptBridge.eval("try{localStorage.setItem('gazelab_who'," + JSON.stringify(q) + ")}catch(e){}")
		else:
			n = str(JavaScriptBridge.eval("(function(){try{return localStorage.getItem('gazelab_who')||''}catch(e){return ''}})()"))
	if n == "" and OS.has_feature("web"):
		# nobody has to give a name: each browser gets a random anonymous id once, so one person's sessions stay together and nobody's are mixed with anyone else's
		n = str(JavaScriptBridge.eval("(function(){try{var a=localStorage.getItem('gazelab_anon');if(!a){a='anon-'+Math.random().toString(16).slice(2,8);localStorage.setItem('gazelab_anon',a)}return a}catch(e){return 'anon-x'}})()"))
	tester = _clean_name(n) if n != "" else "unnamed"
	return tester


func _clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
			out += ch
	return out.substr(0, 24) if out != "" else "unnamed"


func set_tester(n: String) -> void:
	tester = _clean_name(n)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('gazelab_who'," + JSON.stringify(tester) + ")}catch(e){}")


func session() -> String:
	if session_id == "":
		session_id = "%06x" % (randi() % 0xFFFFFF)
	return session_id


## The hardware, once per page load: browser and OS, screen, cores, memory, the graphics chip, touch.
func hw_info() -> Dictionary:
	if not hw.is_empty():
		return hw
	hw = {"web": false}
	if OS.has_feature("web"):
		var j := str(JavaScriptBridge.eval("(function(){var o={};try{o.ua=navigator.userAgent.slice(0,200);o.platform=(navigator.userAgentData&&navigator.userAgentData.platform)||navigator.platform||'';o.mobile=!!(navigator.userAgentData&&navigator.userAgentData.mobile);o.brands=((navigator.userAgentData&&navigator.userAgentData.brands)||[]).map(function(b){return b.brand+' '+b.version}).join(', ');o.cores=navigator.hardwareConcurrency||0;o.mem=navigator.deviceMemory||0;o.dpr=window.devicePixelRatio||1;o.screen=[screen.width,screen.height];o.touch=navigator.maxTouchPoints||0;var c=document.createElement('canvas'),g=c.getContext('webgl'),e=g&&g.getExtension('WEBGL_debug_renderer_info');o.gpu=e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'';}catch(x){}return JSON.stringify(o)})()"))
		var p: Variant = JSON.parse_string(j)
		if p is Dictionary:
			hw = p
			hw["web"] = true
	return hw


func hw_short() -> String:
	var h := hw_info()
	return "%s | %s cores | %s GB | %s" % [str(h.get("platform", "?")), str(h.get("cores", "?")), str(h.get("mem", "?")), str(h.get("gpu", "?")).substr(0, 60)]


func device_tag() -> String:
	if device != "":
		return device
	var touch := Game.touch_mode
	if OS.has_feature("web"):
		touch = touch or bool(JavaScriptBridge.eval("(navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches)"))
	device = "mobile" if touch else "desktop"
	return device


## The cameras the browser knows ([{id, label}], names only once a camera is allowed), the one in use, and a switch to the next one.
func cam_list() -> Array:
	if not OS.has_feature("web"):
		return []
	var p: Variant = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.__gazeCams || [])")))
	return p if p is Array else []


func cam_label() -> String:
	if not OS.has_feature("web"):
		return "(web build only)"
	var l := str(JavaScriptBridge.eval("window.__gazeCamLabel || ''"))
	return l if l != "" else "(not started)"


func cam_next() -> bool:
	var cams := cam_list()
	if cams.size() < 2:
		return false
	var cur := cam_label()
	var idx := 0
	for i in cams.size():
		if String((cams[i] as Dictionary).get("label", "")) == cur:
			idx = i
	var nxt: Dictionary = cams[(idx + 1) % cams.size()]
	camera_status = "switching camera"
	JavaScriptBridge.eval("window.__gazeUseCam(" + JSON.stringify(String(nxt.get("id", ""))) + ")")
	return true


func capture_frame(tag: String, meta: Dictionary) -> void:
	if not capture_on or capture_n >= CAPTURE_MAX or not OS.has_feature("web"):
		return
	capture_n += 1
	var m := meta.duplicate()
	m["tag"] = tag
	m["app"] = app_id()
	m["device"] = device_tag()
	m["who"] = tester_name()
	m["sid"] = session()
	m["gaze"] = [snappedf(gaze.x, 0.001), snappedf(gaze.y, 0.001)]
	m["opts"] = {"kalman": kal_on, "hold": hold_on, "median": geo_win, "stretch": bias.stretch_on, "learn": bias.learn_on, "pick": opt_pick, "locked": bias.cal_locked}
	m["offset"] = [snappedf(bias.bias.x, 0.001), snappedf(bias.bias.y, 0.001)]
	m["scale"] = [snappedf(bias.scale_lo.x, 0.01), snappedf(bias.scale_hi.x, 0.01)]
	m["t"] = snappedf(float(Time.get_ticks_msec()) / 1000.0, 0.1)
	var vsz := get_viewport().get_visible_rect().size
	m["view"] = [int(vsz.x), int(vsz.y)]
	JavaScriptBridge.eval("(function(){if(!(location.hostname==='localhost'||location.port==='8443'))return;var s=window.__gazeSnap&&window.__gazeSnap();if(!s)return;fetch('/frame',{method:'POST',body:JSON.stringify({meta:JSON.parse(" + JSON.stringify(JSON.stringify(m)) + "),snap:s})}).catch(function(){});})()")


func post_stream(kind: String, d: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var o := d.duplicate()
	o["device"] = device_tag()
	o["who"] = tester_name()
	o["sid"] = session()
	o["app"] = app_id()
	if kind == "health":
		o["hw"] = hw_info()
	o["kind"] = kind
	o["t"] = snappedf(float(Time.get_ticks_msec()) / 1000.0, 0.1)
	JavaScriptBridge.eval("(function(){var dev=(location.hostname==='localhost'||location.port==='8443');var ok=dev;var off=false;try{off=localStorage.getItem('gazelab_share')==='0'}catch(e){}ok=ok||!off;if(!ok)return;fetch(dev?'/tune':'/gaze-lab/log.php',{method:'POST',body:" + JSON.stringify(JSON.stringify(o)) + "}).catch(function(){})})()")


func _auto_say(msg: String, banner: bool = true) -> void:
	auto_log.append(msg)
	while auto_log.size() > 30:
		auto_log.remove_at(0)
	post_stream("auto", {"msg": msg})
	if banner and dev_mode:
		Game.banner("AUTO: " + msg, Color(0.6, 0.9, 1.0), 3.0)          # testers see what the system did; everybody else sees nothing


## The doctor decided something (an action, or the verdict on an earlier one): log it for whoever validates it afterwards.
func doctor_event(e: Dictionary) -> void:
	if e.is_empty():
		return
	post_stream("fix", e)
	if str(e.get("event", "")) == "action":
		_auto_say("%s: %s" % [e.get("issue"), e.get("action")])
	else:
		_auto_say("%s: '%s' %s (score %.2f -> %.2f)" % [e.get("issue"), e.get("action"), e.get("verdict"), float((e["before"] as Dictionary).get("score", 0.0)), float((e["after"] as Dictionary).get("score", 0.0))])
	_save_opts()


## The rules AUTO applies on top of the lit-gate testing, each one small and reversible (every change is announced and logged).
func _auto_rules() -> void:
	if tune_phase == "explore" or tune_phase == "challenge":
		return
	var h := health
	var tf := float(h["trackerFps"])
	if tf > 0.0 and tf < 9.0 and geo_win > 3:
		opt_set("median", 3)
		_auto_say("tracker only %.0f readings a second: median window cut to 3 to cut the delay" % tf)
	elif tf >= 13.0 and geo_win == 3 and int(h["gameFps"]) > 40:
		opt_set("median", 5)
		_auto_say("tracker back to %.0f readings a second: median window back to 5" % tf, false)
	# a shaking phone (bus, walking): steady the gaze point while it lasts, put it back after
	if pm_on and pm.active and pm.shake > 0.35:
		_h_shake += 1
	else:
		_h_shake = maxi(_h_shake - 1, 0)
	if _h_shake >= 3 and not _shake_hold:
		_shake_hold = true
		_shake_prev_hold = hold_on
		opt_set("hold", true)
		_auto_say("the phone is shaking: gaze point steadied while it lasts")
	elif _h_shake == 0 and _shake_hold:
		_shake_hold = false
		opt_set("hold", _shake_prev_hold)
		_auto_say("steady again: back to normal", false)
	# the player has shifted in their seat since the sweep: the learned offset has moved a long way, so measure again (at most every five minutes)
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if sweep_done and (bias.bias - _sweep_bias0).length() > 0.18:
		_drift_n += 1
	else:
		_drift_n = 0
	if _drift_n >= 3 and now_s - _drift_last > 300.0:
		_drift_last = now_s
		_drift_n = 0
		_sweep_tried = false
		doctor.sweep_wanted = true
		_auto_say("seating has shifted since the calibration: one new sweep")
	var jo := float(h["jitterOut"])
	if jo > 0.022 and not hold_on:
		opt_set("hold", true)
		_auto_say("gaze point jitters (%.1f%% of the screen between samples): fixation hold on" % (jo * 100.0))
	elif jo >= 0.0 and jo < 0.007 and hold_on:
		opt_set("hold", false)
		_auto_say("gaze point is steady (%.1f%%): fixation hold off, it only adds lag" % (jo * 100.0), false)
	if float(h["spanX"]) < 0.22 and (Game.downhill_mode or Game.peek_mode or Game.flight_mode or Game.gaze_test_mode):
		_h_narrow += 1
	else:
		_h_narrow = 0
	if _h_narrow >= 3 and float(Time.get_ticks_msec()) / 1000.0 - _h_note_t > 90.0:
		_h_note_t = float(Time.get_ticks_msec()) / 1000.0
		if not _sweep_tried and not sweep_done:
			doctor.sweep_wanted = true
			_auto_say("the gaze covers only %d%% of the screen width: one calibration sweep" % int(float(h["spanX"]) * 100.0))
		else:
			_auto_say("the gaze covers only %d%% of the screen width (SWEEP in EYE OPTIONS re-calibrates)" % int(float(h["spanX"]) * 100.0), false)
	if int(h["gameFps"]) < 22:
		_h_slow += 1
	else:
		_h_slow = 0
	if _h_slow == 3:
		_auto_say("game at %d fps (frame p95 %.0f ms): the quality tier controller should step down" % [int(h["gameFps"]), float(h["frameP95ms"])], false)


func opt_defs() -> Array:
	return [["auto", "AUTO-FIX (silent doctor + rules)"], ["kalman", "Kalman filter"], ["stab", "Phone-motion stabiliser"], ["stretch", "Spread stretching"], ["learn", "Auto offset learning"],
		["hold", "Fixation hold (dead zone)"], ["median", "Median window"], ["headw", "Head weight"], ["pick", "Gate pick (Downhill)"]]


func opt_value(key: String) -> Variant:
	match key:
		"auto":
			return auto_on
		"kalman":
			return kal_on
		"stab":
			return pm_on
		"stretch":
			return bias.stretch_on
		"learn":
			return bias.learn_on
		"hold":
			return hold_on
		"median":
			return geo_win
		"headw":
			return head_weight
		"pick":
			return opt_pick
	return null


func opt_label(key: String) -> String:
	var v: Variant = opt_value(key)
	if v is bool:
		return "ON" if v else "off"
	if key == "median":
		return "none" if int(v) <= 1 else "%d readings" % int(v)
	if key == "headw":
		return "%d%%" % int(round(float(v) * 100.0))
	if key == "pick":
		return "gaze zones" if int(v) == 1 else "nearest in tolerance"
	return str(v)


func opt_set(key: String, v: Variant) -> void:
	match key:
		"auto":
			auto_on = bool(v)
		"kalman":
			kal_on = bool(v)
			_kx.reset()
			_ky.reset()
			_fx.reset()
			_fy.reset()
		"stab":
			pm_on = bool(v)
		"stretch":
			bias.stretch_on = bool(v)
		"learn":
			bias.learn_on = bool(v)
		"hold":
			hold_on = bool(v)
			_hold_pt = gaze
		"median":
			geo_win = clampi(int(v), 1, 9)
			while _geo_buf.size() > geo_win:
				_geo_buf.remove_at(0)
		"headw":
			head_weight = clampf(float(v), 0.0, 1.0)
		"pick":
			opt_pick = int(v)
	_save_opts()


func opt_next(key: String) -> void:
	var v: Variant = opt_value(key)
	if v is bool:
		opt_set(key, not v)
	elif key == "median":
		var cyc := [1, 3, 5]
		opt_set(key, cyc[(cyc.find(int(v)) + 1) % cyc.size()])
	elif key == "headw":
		var cw := [0.0, 0.12, 0.3, 0.5]
		var bi := 0
		for i in cw.size():
			if absf(float(cw[i]) - float(v)) < absf(float(cw[bi]) - float(v)):
				bi = i
		opt_set(key, cw[(bi + 1) % cw.size()])
	elif key == "pick":
		opt_set(key, 1 - int(v))


func opts_default() -> void:
	opt_set("kalman", true)
	opt_set("stab", true)
	opt_set("stretch", true)
	opt_set("learn", true)
	opt_set("hold", false)
	opt_set("median", 5)
	opt_set("headw", 0.12)
	opt_set("pick", 0)


## Everything that helps is off: raw geometry gaze, no stretching, no learning, no filter, and the gate nearest where you look.
func opts_bare() -> void:
	opt_set("kalman", false)
	opt_set("stab", false)
	opt_set("stretch", false)
	opt_set("learn", false)
	opt_set("hold", false)
	opt_set("median", 1)
	opt_set("pick", 1)


func opts_changed() -> bool:
	return not (kal_on and pm_on and bias.stretch_on and bias.learn_on and not hold_on and geo_win == 5 and absf(head_weight - 0.12) < 0.001 and opt_pick == 0)


func _save_opts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cf := ConfigFile.new()
	for d: Array in opt_defs():
		cf.set_value("opts", d[0], opt_value(d[0]))
	cf.set_value("params", "p_linger", p_linger)
	cf.set_value("params", "p_pull", p_pull)
	cf.set_value("params", "p_carve", p_carve)
	cf.set_value("params", "p_reach", p_reach)
	cf.save(OPT_FILE)


func _load_opts() -> void:
	var cf := ConfigFile.new()
	if cf.load(OPT_FILE) != OK:
		return
	p_linger = clampf(float(cf.get_value("params", "p_linger", 1.0)), 0.3, 2.0)
	p_pull = clampf(float(cf.get_value("params", "p_pull", 0.22)), 0.1, 0.3)
	p_carve = clampf(float(cf.get_value("params", "p_carve", 1.0)), 0.8, 1.6)
	p_reach = clampf(float(cf.get_value("params", "p_reach", 1.0)), 0.8, 2.0)
	for d: Array in opt_defs():
		if cf.has_section_key("opts", d[0]):
			var key: String = d[0]
			var v: Variant = cf.get_value("opts", key)
			match key:
				"auto":
					auto_on = bool(v)
				"kalman":
					kal_on = bool(v)
				"stab":
					pm_on = bool(v)
				"stretch":
					bias.stretch_on = bool(v)
				"learn":
					bias.learn_on = bool(v)
				"hold":
					hold_on = bool(v)
				"median":
					geo_win = clampi(int(v), 1, 9)
				"headw":
					head_weight = clampf(float(v), 0.0, 1.0)
				"pick":
					opt_pick = int(v)


## After a Downhill run resets the gaze correction: put the sweep's measured map back.
func reapply_sweep() -> void:
	if sweep_done and _sweep_lin.size() == 4:
		bias.set_linear(float(_sweep_lin[0]), float(_sweep_lin[1]), float(_sweep_lin[2]), float(_sweep_lin[3]))


## For the run report / the COPY LOG button: which layers were on, what the correction looked like, and the last barriers.
func options_report() -> Dictionary:
	var sw: Dictionary = {}
	if not sweep_fit.is_empty():
		sw = {"ok": sweep_fit.get("ok", false), "scaleX": snappedf(float(sweep_fit.get("sx", 0.0)), 0.01), "scaleY": snappedf(float(sweep_fit.get("sy", 0.0)), 0.01), "lag": sweep_fit.get("lag", 0.0), "n": sweep_fit.get("n", 0), "note": sweep_note}
		if sweep_fit.has("rms"):
			sw["miss"] = [snappedf((sweep_fit["rms"] as Vector2).x, 0.001), snappedf((sweep_fit["rms"] as Vector2).y, 0.001)]
	return {"kalman": kal_on, "stabiliser": pm_on, "stretch": bias.stretch_on, "learn": bias.learn_on, "hold": hold_on, "median": geo_win, "headWeight": head_weight, "pick": ["nearest", "zones"][opt_pick],
		"offset": [snappedf(bias.bias.x, 0.001), snappedf(bias.bias.y, 0.001)], "scale": [snappedf(bias.scale_lo.x, 0.01), snappedf(bias.scale_hi.x, 0.01), snappedf(bias.scale_lo.y, 0.01), snappedf(bias.scale_hi.y, 0.01)],
		"who": tester_name(), "sid": session(), "device": device_tag(), "hw": hw_info(), "calLocked": bias.cal_locked, "sweep": sw, "kalmanJumps": _kx.jumps, "gateLog": gate_log.slice(maxi(gate_log.size() - 40, 0)), "tuner": {"state": tuner_state, "applied": applied, "chosen": tuner.chosen, "log": tuner.log, "baseline": snappedf(_tn_baseline, 0.001)}, "tune": tune_summary, "tuneTrials": tune_trials, "auto": auto_on, "doctor": doctor.log, "doctorPending": str((doctor.pending.get("action", {}) as Dictionary).get("label", "")) if not doctor.pending.is_empty() else "", "params": {"linger": snappedf(p_linger, 0.01), "pull": snappedf(p_pull, 0.01), "carve": snappedf(p_carve, 0.01), "reach": snappedf(p_reach, 0.01)}, "autoLog": auto_log, "health": health}


## Start the one-pass sweep: a dot glides round the screen for about four seconds. Needs the geometry gaze (the camera path).
func start_sweep() -> bool:
	if backend != Backend.CAMERA or not _geo_limb:
		sweep_note = "needs the camera tracker"
		return false
	sweep_active = true
	sweep_t = -EyeSweep.LEAD
	_sweep_samples = []
	sweep_note = ""
	sweep_changed.emit(true)
	return true


func cancel_sweep() -> void:
	if sweep_active:
		sweep_active = false
		sweep_note = "skipped"
		sweep_changed.emit(false)


func _finish_sweep() -> void:
	sweep_active = false
	sweep_changed.emit(false)
	sweep_fit = EyeSweep.fit(_sweep_samples)
	if bool(sweep_fit["ok"]):
		bias.set_linear(float(sweep_fit["ax"]), float(sweep_fit["sx"]), float(sweep_fit["ay"]), float(sweep_fit["sy"]))
		_sweep_lin = [float(sweep_fit["ax"]), float(sweep_fit["sx"]), float(sweep_fit["ay"]), float(sweep_fit["sy"])]
		_sweep_bias0 = bias.bias
		sweep_done = true
		_kx.reset()
		_ky.reset()
		var rms: Vector2 = sweep_fit["rms"]
		sweep_note = "calibrated, typical miss %d%% of the screen" % int(round(maxf(rms.x, rms.y) * 100.0))
		Game.banner(sweep_note, Color(0.5, 1.0, 0.6), 2.5)
	else:
		sweep_note = String(sweep_fit.get("why", "failed"))
		Game.banner("Sweep did not take: " + sweep_note, Color(1.0, 0.7, 0.3), 3.5)


func _calibrate_tick(rd: float) -> void:
	_cal_clock += rd
	cal_settling = _cal_clock < CAL_SETTLE
	cal_progress = clampf((_cal_clock - CAL_SETTLE) / CAL_HOLD, 0.0, 1.0)
	if _cal_clock >= CAL_SETTLE + CAL_HOLD:
		cal_index += 1
		_cal_clock = 0.0
		if cal_index >= CAL_POINTS.size():
			cal_index = -1
			_finish_calibration()


func _series(pt: int, feat: int, axis: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for smp: Array in _cal_samples[pt]:
		var v: Vector2 = smp[feat]
		out.append(v.x if axis == 0 else v.y)
	return out


func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func _std(a: PackedFloat32Array, m: float) -> float:
	if a.size() < 2:
		return 1.0
	var t := 0.0
	for v in a:
		t += (v - m) * (v - m)
	return sqrt(t / a.size())


func _finish_calibration_axes() -> void:
	var weak := false
	var mids := Vector2.ZERO
	var gains := Vector2.ONE
	var feats := Vector2i.ZERO
	for axis in 2:
		var lo := 1 if axis == 0 else 3
		var hi := 2 if axis == 0 else 4
		var best_snr := -1.0
		for feat in 2:
			var a := _series(lo, feat, axis)
			var b := _series(hi, feat, axis)
			var c := _series(0, feat, axis)
			if a.size() < 5 or b.size() < 5:
				continue
			var ma := _mean(a)
			var mb := _mean(b)
			var sep := mb - ma
			var sigma := (_std(a, ma) + _std(b, mb)) * 0.5 + 0.0001
			var snr := absf(sep) / sigma
			if snr > best_snr and absf(sep) > 0.0001:
				best_snr = snr
				var mc := _mean(c) if c.size() >= 5 else (ma + mb) * 0.5
				var mid := ((ma + mb) * 0.5 + mc) * 0.5
				var t_lo: float = CAL_POINTS[lo].x if axis == 0 else CAL_POINTS[lo].y
				var t_hi: float = CAL_POINTS[hi].x if axis == 0 else CAL_POINTS[hi].y
				var g := clampf(absf((t_hi - t_lo) / sep), 0.3, 40.0) * signf(sep)
				if axis == 0:
					mids.x = mid
					gains.x = g
					feats.x = feat
				else:
					mids.y = mid
					gains.y = g
					feats.y = feat
		if best_snr < 2.0:
			weak = true
	_mid = mids
	_gain = gains
	_feat = feats
	_calibrated = true
	_fx.reset()
	_fy.reset()
	if weak:
		cal_note = "weak"
		Game.banner("Calibration weak: more light on your face, sit still, press C to retry", Color(1.0, 0.7, 0.3), 4.0)
	else:
		cal_note = "ok"
		Game.banner("Calibrated! Look around, blink to fire", Color(0.5, 1.0, 0.6), 2.5)


func _finish_calibration() -> void:
	if _fit_ridge():
		return
	_finish_calibration_axes()


## Ridge regression: standardised signals (iris ratios, eye-look blendshapes, head pose)
## -> screen x,y. Trained on the calibration dots; every 4th sample is held out to
## measure honest accuracy. Falls back to the per-axis fit when no signal vector exists.
func _fit_ridge() -> bool:
	var rows: Array = []
	for pi in CAL_POINTS.size():
		for smp: Array in _cal_samples[pi]:
			if smp.size() > 2 and (smp[2] as PackedFloat32Array).size() > 3:
				rows.append([smp[2], CAL_POINTS[pi]])
	if rows.size() < 60:
		return false
	var m: int = (rows[0][0] as PackedFloat32Array).size()
	var mean := PackedFloat32Array()
	var sd := PackedFloat32Array()
	mean.resize(m)
	sd.resize(m)
	for i in m:
		var t := 0.0
		for r: Array in rows:
			t += (r[0] as PackedFloat32Array)[i]
		mean[i] = t / rows.size()
		var v := 0.0
		for r: Array in rows:
			var dlt: float = (r[0] as PackedFloat32Array)[i] - mean[i]
			v += dlt * dlt
		sd[i] = maxf(sqrt(v / rows.size()), 0.0005)
	var train: Array = []
	var val: Array = []
	for k in rows.size():
		var z := PackedFloat32Array()
		z.resize(m + 1)
		for i in m:
			z[i] = ((rows[k][0] as PackedFloat32Array)[i] - mean[i]) / sd[i]
		z[m] = 1.0
		(val if k % 4 == 0 else train).append([z, rows[k][1]])
	var lam := 4.0
	var wxv := _ridge_solve(train, 0, m + 1, lam)
	var wyv := _ridge_solve(train, 1, m + 1, lam)
	var err2 := 0.0
	for e: Array in val:
		var z: PackedFloat32Array = e[0]
		var tgt: Vector2 = e[1]
		var px := 0.0
		var py := 0.0
		for i in m + 1:
			px += wxv[i] * z[i]
			py += wyv[i] * z[i]
		err2 += (px - tgt.x) * (px - tgt.x) + (py - tgt.y) * (py - tgt.y)
	cal_error = sqrt(err2 / maxf(val.size(), 1.0) * 0.5)
	# refit on everything
	var all: Array = train + val
	_wx = _ridge_solve(all, 0, m + 1, lam)
	_wy = _ridge_solve(all, 1, m + 1, lam)
	_r_mean = mean
	_r_std = sd
	_ridge_ok = true
	_calibrated = false
	_fx.reset()
	_fy.reset()
	var pct := int(round(cal_error * 100.0))
	if cal_error > 0.2:
		cal_note = "weak"
		Game.banner("Calibration error ~%d%% of the screen: sit closer, more light, head still. Press C to retry" % pct, Color(1.0, 0.7, 0.3), 5.0)
	else:
		cal_note = "ok"
		Game.banner("Calibrated (error ~%d%% of screen). Blink to fire, wink to swap" % pct, Color(0.5, 1.0, 0.6), 3.0)
	return true


func _ridge_solve(rows: Array, axis: int, n: int, lam: float) -> PackedFloat32Array:
	var a: Array = []
	for i in n:
		var row := PackedFloat32Array()
		row.resize(n)
		a.append(row)
	var b := PackedFloat32Array()
	b.resize(n)
	for e: Array in rows:
		var z: PackedFloat32Array = e[0]
		var y: float = (e[1] as Vector2)[axis]
		for i in n:
			b[i] += z[i] * y
			var ai: PackedFloat32Array = a[i]
			for j in n:
				ai[j] += z[i] * z[j]
	for i in n - 1:
		(a[i] as PackedFloat32Array)[i] += lam
	# Gauss-Jordan with partial pivoting
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf((a[r] as PackedFloat32Array)[col]) > absf((a[piv] as PackedFloat32Array)[col]):
				piv = r
		var tmp: PackedFloat32Array = a[col]
		a[col] = a[piv]
		a[piv] = tmp
		var tb := b[col]
		b[col] = b[piv]
		b[piv] = tb
		var pv: float = (a[col] as PackedFloat32Array)[col]
		if absf(pv) < 0.000001:
			continue
		for r in n:
			if r == col:
				continue
			var f: float = (a[r] as PackedFloat32Array)[col] / pv
			if f == 0.0:
				continue
			var ar: PackedFloat32Array = a[r]
			var ac: PackedFloat32Array = a[col]
			for c in n:
				ar[c] -= f * ac[c]
			b[r] -= f * b[col]
	var w := PackedFloat32Array()
	w.resize(n)
	for i in n:
		var d: float = (a[i] as PackedFloat32Array)[i]
		w[i] = b[i] / d if absf(d) > 0.000001 else 0.0
	return w


func _predict(full: PackedFloat32Array) -> Vector2:
	var m := _r_mean.size()
	var x := _wx[m]
	var y := _wy[m]
	for i in m:
		var z := (full[i] - _r_mean[i]) / _r_std[i]
		x += _wx[i] * z
		y += _wy[i] * z
	return Vector2(x, y)


func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[int(floor((b.size() - 1) * q))]


func reset_gestures() -> void:
	_hist_l.clear()
	_hist_r.clear()
	_base_l = 1.0
	_base_r = 1.0
	_closed = false
	_wink_state = 0
	_wink_fired = false
	dbg_l = 0.0
	dbg_r = 0.0


## One new tracker sample (15 Hz). Every signal becomes a z-score against its own running mean / spread, so a
## weak signal (eyes barely move up and down) gets the same on-screen range as a strong one, and a head
## that rests tilted back is simply the new "centre". Blend: head pose (precise) + eyes (refinement).
## Vertical eye signal = geometry + eyelid opening (upper lid follows the eye). A one-sided correction
## evens out down vs up when one direction is physically weaker.
func _geo_z(g: Vector2, openness: float, hd: Vector2, has_head: bool) -> Vector2:
	var zx := (g.x - _geo_mu.x) / maxf(sqrt(_geo_var.x), 0.01)
	var zg := (g.y - _geo_mu.y) / maxf(sqrt(_geo_var.y), 0.01)
	var zl := zg
	if openness > 0.0:
		zl = -(openness - _open_mu) / maxf(sqrt(_open_var), 0.01)
	var zey := 0.6 * zg + 0.4 * zl
	if not has_head:
		return Vector2(zx, zey)
	var zhx := -_head_sign.x * (hd.x - _hd_mu.x) / maxf(sqrt(_hd_var.x), HEAD_MIN_SIGMA.x)
	var zhy := _head_sign.y * (hd.y - _hd_mu.y) / maxf(sqrt(_hd_var.y), HEAD_MIN_SIGMA.y)
	var hw := head_weight * (0.4 if (Game.peek_mode or Game.downhill_mode or (Game.trance_mode or Game.gaze_test_mode)) else 1.0)      # peek: the head is busy leaning, so lean on the eyes
	return Vector2((1.0 - hw) * zx + hw * zhx, (1.0 - hw) * zey + hw * zhy)


func _geo_push(g: Vector2, openness: float = 0.0, head: Vector2 = Vector2.INF) -> void:
	var tn := _now()
	var ddt := clampf(tn - _direct_t, 0.005, 0.5)
	_direct_t = tn
	direct = Vector2(_dfx.filter(g.x, ddt), _dfy.filter(g.y, ddt))
	direct_ok = true
	var has_head := head.is_finite()
	_last_g = g
	_last_open = openness
	if has_head:
		_last_hd = head
	_geo_buf.append(Vector3(g.x, g.y, openness))
	if sweep_active and sweep_t >= 0.0 and maxf(dbg_l, dbg_r) < 0.22:
		_sweep_samples.append([sweep_t, g.x, g.y])
	if has_head:
		_hbuf.append(head)
	while _geo_buf.size() > geo_win:
		_geo_buf.remove_at(0)
	if _hbuf.size() > 7:
		_hbuf.remove_at(0)
	_geo_n += 1
	var al := maxf(1.0 / float(_geo_n), 1.0 / 900.0)
	var dv := g - _geo_mu
	_geo_var.x += al * (dv.x * dv.x - _geo_var.x)
	_geo_var.y += al * (dv.y * dv.y - _geo_var.y)
	_geo_mu += dv * al
	if openness > 0.0:
		var dop := openness - _open_mu
		_open_var += al * (dop * dop - _open_var)
		_open_mu += dop * al
	if has_head:
		var dh := head - _hd_mu
		_hd_var.x += al * (dh.x * dh.x - _hd_var.x)
		_hd_var.y += al * (dh.y * dh.y - _hd_var.y)
		_hd_mu += dh * al
	# Spreads of the blended signal, measured on RAW samples (the median below would shrink them).
	if _geo_n > 20:
		var zr := _geo_z(g, openness, head, has_head)
		_zx_var += al * (zr.x * zr.x - _zx_var)
		_zv_var += al * (zr.y * zr.y - _zv_var)
		if zr.y > 0.0:
			_zp += al * 2.0 * (zr.y * zr.y - _zp)
		else:
			_zn += al * 2.0 * (zr.y * zr.y - _zn)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var os := PackedFloat32Array()
	for v in _geo_buf:
		xs.append(v.x)
		ys.append(v.y)
		os.append(v.z)
	xs.sort()
	ys.sort()
	os.sort()
	var m := _geo_buf.size() / 2
	var med := Vector3(xs[m], ys[m], os[m])
	var medh := Vector2.ZERO
	if has_head and not _hbuf.is_empty():
		var hx := PackedFloat32Array()
		var hy := PackedFloat32Array()
		for h in _hbuf:
			hx.append(h.x)
			hy.append(h.y)
		hx.sort()
		hy.sort()
		medh = Vector2(hx[hx.size() / 2], hy[hy.size() / 2])
	_geo_ok = true
	if _geo_limb:
		# Physical mapping: the geometry already knows the screen size, the viewing distance and the head pose, so no
		# stretching to fit your recent spread (that amplified noise). Only a constant offset is learned, silently.
		_geo_raw = Vector2(med.x, med.y)
		var pitch_now := head_rpy.y if head_rpy_ok else 0.0
		var active_mode := Game.peek_mode or Game.flight_mode or (Game.trance_mode or Game.gaze_test_mode)
		bias.add(med.x, med.y, pitch_now, med.z, active_mode and _camera_fresh())
		_geo_out = bias.apply(med.x, med.y, pitch_now, med.z)
		return
	if _geo_n < 45:
		_geo_out = Vector2(0.5, 0.5)
		return
	var z := _geo_z(Vector2(med.x, med.y), med.z, medh, has_head)
	var zx := clampf(z.x / maxf(sqrt(_zx_var), 0.3), -2.5, 2.5)
	var zv := z.y / maxf(sqrt(_zv_var), 0.3)
	if zv > 0.0:
		zv *= clampf(sqrt(_zn / maxf(_zp, 0.05)), 1.0, 2.5)   # looking down is often the weaker direction
	zv = clampf(zv, -2.5, 2.5)
	_geo_out = Vector2(0.5 + zx * GEO_TARGET.x, 0.5 + zv * GEO_TARGET.y)


# --------------------------------------------------------------------------
# Peek (lean out of cover)
# --------------------------------------------------------------------------
func _dz(v: float, dz: float) -> float:
	return signf(v) * maxf(absf(v) - dz, 0.0)


## Median of the last few raw geometry-gaze samples (screen-plane units from the tracker), or Vector2.INF.
## Used by Downhill, which calibrates this signal itself instead of the self-normalising gaze point.
func geo_median() -> Vector2:
	if _geo_buf.is_empty():
		return Vector2.INF
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for v in _geo_buf:
		xs.append(v.x)
		ys.append(v.y)
	xs.sort()
	ys.sort()
	return Vector2(xs[xs.size() / 2], ys[ys.size() / 2])


## True while the limbus-fit eye signal (the precise one, same as EyeLab) is arriving.
func limb_ready() -> bool:
	return backend == Backend.CAMERA and Time.get_ticks_msec() - _limb_msec < 700 and not _limb_buf.is_empty()


## [lx, ly, head yaw, head pitch]: where the iris sits inside the eye box (median of the last few frames) and the
## head angles in radians. Empty when there is no fresh reading. Kept for tools and tests.
func limb_sample() -> Array:
	if not limb_ready():
		return []
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for v in _limb_buf:
		xs.append(v.x)
		ys.append(v.y)
	xs.sort()
	ys.sort()
	return [xs[xs.size() / 2], ys[ys.size() / 2], head_rpy.x, head_rpy.y]


func _camera_fresh() -> bool:
	return backend == Backend.CAMERA and Time.get_ticks_msec() - _last_packet_msec < 1500 and confidence > 0.3


func _update_peek() -> void:
	if not _head_ok:
		return
	var cm := 14.0 / maxf(_fw0, 0.05)                     # frame fraction -> centimetres
	var lx := (_nx - _nx0) * cm
	var ly := (_ny0 - _ny) * cm                           # up is positive
	var lz := _fw / maxf(_fw0, 0.01) - 1.0                # closer to the screen is positive
	var yaw := -(head_rpy.x - _hr0.x)                     # + = you turned to your right
	# Slowly adopt a new resting posture (only while you are near it), so sagging in the chair does not pull the view.
	if absf(lx) < 2.0 and absf(ly) < 2.0:
		_nx0 = lerpf(_nx0, _nx, 0.004)
		_ny0 = lerpf(_ny0, _ny, 0.004)
	var mix := PEEK_YAW_MIX_PHONE if Game.touch_mode else 0.0
	var x := lerpf(_dz(lx, 1.0) * PEEK_M_PER_CM.x, _dz(yaw, 0.04) * PEEK_M_PER_RAD, mix)
	var y := _dz(ly, 1.0) * PEEK_M_PER_CM.y
	var z := _dz(lz, PEEK_DEAD.z) * peek_gain.z
	var t := Vector3(x, y, z).clamp(-PEEK_MAX, PEEK_MAX)
	_pk_buf.append(t)
	if _pk_buf.size() > 5:
		_pk_buf.remove_at(0)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for v in _pk_buf:
		xs.append(v.x)
		ys.append(v.y)
		zs.append(v.z)
	xs.sort()
	ys.sort()
	zs.sort()
	var m := _pk_buf.size() / 2
	_pk_target = Vector3(xs[m], ys[m], zs[m])


## Where the player should lean to (x right, y up, z forward; metres), smoothed. Arrow keys work without a camera.
func peek_offset(delta: float) -> Vector3:
	var goal := _pk_target if _camera_fresh() else Vector3.ZERO
	_pk_out = _pk_out.lerp(goal, 1.0 - exp(-delta / 0.1))
	var kb := Vector3.ZERO
	kb.x = (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) + touch_lean + touch_steer
	kb.x = clampf(kb.x, -1.0, 1.0)
	kb.y = (0.3 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)
	_kb_cur = _kb_cur.lerp(kb * Vector3(1.5, 0.9, 1.0), 1.0 - exp(-delta / 0.1))
	return peek_offset_current()


func peek_offset_current() -> Vector3:
	return _pk_out + _kb_cur + peek_debug


## Extra camera yaw / pitch (radians) from turning / nodding the head, magnified.
func peek_look(delta: float) -> Vector2:
	var goal := Vector2.ZERO
	if _camera_fresh():
		var dy := _dz(head_rpy.x - _hr0.x, 0.03)          # camera yaw: + = image-right = your left, same as the game camera
		var dp := _dz(head_rpy.y - _hr0.y, 0.03)          # + = nod down
		var lk := 0.4 if Game.touch_mode else 1.0
		goal = Vector2(clampf(dy * PEEK_LOOK.x * lk, -0.7, 0.7), clampf(-dp * PEEK_LOOK.y * lk, -0.5, 0.5))
	_look_out = _look_out.lerp(goal, 1.0 - exp(-delta / 0.12))
	return _look_out


# --------------------------------------------------------------------------
# Nod (flight)
# --------------------------------------------------------------------------
func _update_nod() -> void:
	if not _head_ok:
		return
	var p := -(head_rpy.y - _hr0.y)                  # chin up is positive
	if absf(p) < 0.05:
		_hr0.y = lerpf(_hr0.y, head_rpy.y, 0.004)    # slowly adopt a new resting head angle
	var t := float(Time.get_ticks_msec()) / 1000.0
	var dt := t - _nod_t
	if _nod_t > 0.0 and dt > 0.02 and dt < 0.5:
		_nod_v = lerpf(_nod_v, (p - _nod_p) / dt, 0.55)
	elif dt >= 0.5:
		_nod_v = 0.0
	_nod_p = p
	_nod_t = t


## (chin pitch, chin velocity) for the flight game, camera and keyboard combined.
func nod_state(delta: float) -> Vector2:
	if nod_debug.is_finite():
		return nod_debug
	var up := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var goal := 0.32 * clampf((1.0 if up else 0.0) - (1.0 if down else 0.0) + touch_nod_goal, -1.0, 1.0)
	var prev := _kb_nod
	_kb_nod = lerpf(_kb_nod, goal, 1.0 - exp(-delta / 0.07))
	var p := _kb_nod
	var v := (_kb_nod - prev) / maxf(delta, 0.001)
	if _camera_fresh():
		var age := float(Time.get_ticks_msec()) / 1000.0 - _nod_t
		p += _nod_p
		v += _nod_v * clampf(1.0 - age / 0.4, 0.0, 1.0)
	return Vector2(p, v * nod_sens)


## One-line live diagnostic for the on-screen HUD (so a phone that "does nothing" can tell us why).
func debug_line() -> String:
	if backend != Backend.CAMERA:
		return "camera: not started   (touch buttons / arrow keys active)"
	var age := Time.get_ticks_msec() - _last_packet_msec
	var rate := float(_pkt_times.size()) / 2.0
	var cm := 14.0 / maxf(_fw0, 0.05)
	return "cam %s | %.1f readings/s | last %d ms ago | lean %+.1f cm | turn %+d | nod %+.2f" % [
		"OK" if _camera_fresh() else "NO DATA", rate, age if _last_packet_msec > 0 else -1,
		(_nx - _nx0) * cm, int(round(rad_to_deg(-(head_rpy.x - _hr0.x)))), _nod_p]


## What the HUD should say about the camera: {"text": String, "color": Color}; text "" = nothing to say.
func camera_message() -> Dictionary:
	var st := camera_status
	if backend != Backend.CAMERA and st == "":
		return {"text": "", "color": Color.WHITE}
	if st.begins_with("error"):
		return {"text": "CAMERA PROBLEM: %s   (tap CAM to retry)" % st.substr(7), "color": Color(1.0, 0.5, 0.4)}
	if head_rpy_ok and _camera_fresh():
		if Time.get_ticks_msec() - cam_ok_msec < 5000:
			return {"text": "Camera tracking ON", "color": Color(0.5, 1.0, 0.6)}
		return {"text": "", "color": Color.WHITE}
	if head_rpy_ok:
		return {"text": "Camera: lost your face (face the screen, add light)", "color": Color(1.0, 0.8, 0.3)}
	return {"text": "Camera: %s ..." % (st if st != "" else "starting"), "color": Color(1.0, 0.85, 0.3)}
