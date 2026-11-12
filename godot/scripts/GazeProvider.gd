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
		return cal_index >= 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep tracking while a menu pauses the game
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search"))
		if q.contains("flipyaw"):
			_head_sign.x = -1.0
		if q.contains("flippitch"):
			_head_sign.y = -1.0
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
		_geo_limb = d.has("glimb") and int(d["glimb"]) == 1
		if _frame_fresh and d.has("lx") and d.has("ly") and d["lx"] != null and d["ly"] != null:
			_limb_buf.append(Vector2(float(d["lx"]), float(d["ly"])))
			var tn2 := _now()
			var edt := clampf(tn2 - _eih_t, 0.005, 0.5)
			_eih_t = tn2
			eih = Vector2(_efx.filter(float(d["lx"]), edt), _efy.filter(float(d["ly"]), edt))
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
		_pkt_times.append(_last_packet_msec)
	while not _pkt_times.is_empty() and _last_packet_msec - _pkt_times[0] > 2000:
		_pkt_times.remove_at(0)
	if backend == Backend.CAMERA and not _cal_done and cal_index < 0 and confidence > 0.5 and d.has("x"):
		_cal_done = true
		if d.has("gu"):
			Game.banner("Camera ready. No calibration needed: look around and it learns your centre. (C = optional dot calibration)", Color(0.5, 1.0, 0.6), 4.0)
		else:
			start_calibration()


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
				_poll_camera(rd)
				if cal_index >= 0:
					_calibrate_tick(rd)
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
				gaze = Vector2(_fx.filter(c.x, rd), _fy.filter(c.y, rd)).clamp(Vector2.ZERO, Vector2.ONE)


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
	if has_head:
		_hbuf.append(head)
	if _geo_buf.size() > 5:
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
