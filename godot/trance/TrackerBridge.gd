extends Node
## TrackerBridge (autoload): one place that answers "where is the player looking, and did they just blink?"
##
## Source priority, re-evaluated every frame:
##   1. UDP   - JSON packets from tools/trance/webcam_server.py on 127.0.0.1:4242 (desktop builds only).
##              A packet newer than UDP_TIMEOUT seconds wins.
##   2. CAMERA - the in-browser MediaPipe tracker (GazeProvider) when its camera is running (web builds).
##   3. MOUSE / TOUCH - the pointer is the gaze, SPACE / right click / the BLINK button is the blink.
## `force_mouse_mode` skips 1 and 2.
##
## UDP packet (any extra keys are ignored):
##   {"gaze_pos": [x, y], "ear": 0.27, "is_blinking": false, "head_pitch_yaw": [pitch, yaw]}
##   gaze_pos is 0..1 across the screen; head_pitch_yaw is in radians.

signal blinked

const UDP_PORT := 4242
const UDP_TIMEOUT := 1.0

## Skip the trackers and use the mouse / touch only.
var force_mouse_mode: bool = false
## Smoothed gaze, 0..1 across the screen (use this one).
var gaze: Vector2 = Vector2(0.5, 0.5)
## Unsmoothed gaze from whichever source is active.
var raw_gaze: Vector2 = Vector2(0.5, 0.5)
var ear: float = 0.3
var is_blinking: bool = false
## True for exactly one frame, the frame a blink ends (the eyes re-open). This is the "release" action.
var just_blinked: bool = false
var head_pitch_yaw: Vector2 = Vector2.ZERO
var source: String = "mouse"
## Tests / tools: pin the gaze (Vector2.INF = off) and fire blinks by hand.
var debug_gaze: Vector2 = Vector2.INF

## Typical jitter of the calibrated gaze (screen fraction): sizes the aim zone.
var camera_sigma: float = 0.03

var _udp: PacketPeerUDP
var _last_udp: float = -1000.0
var _udp_blink_prev: bool = false
var _touch_gaze: Vector2 = Vector2(0.5, 0.5)
var _touch_seen: bool = false
var _pending_blink: bool = false
var _fire_prev: bool = false
var _smooth_rate: float = 14.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		_udp = PacketPeerUDP.new()
		var err := _udp.bind(UDP_PORT, "127.0.0.1")
		if err != OK:
			push_warning("TrackerBridge: could not listen on UDP %d (%s). Mouse / camera only." % [UDP_PORT, error_string(err)])
			_udp = null
	GazeProvider.blinked.connect(_on_camera_blink)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _on_camera_blink() -> void:
	if source == "camera":
		_pending_blink = true


## Fire a blink from code (tests, UI buttons).
func debug_blink() -> void:
	_pending_blink = true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_SPACE:
			_pending_blink = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_pending_blink = true
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		var p := (event as InputEventScreenTouch).position if event is InputEventScreenTouch else (event as InputEventScreenDrag).position
		var vs := get_viewport().get_visible_rect().size
		_touch_gaze = (p / vs).clamp(Vector2.ZERO, Vector2.ONE)
		_touch_seen = true


func _process(delta: float) -> void:
	just_blinked = false
	_poll_udp()
	var now := _now()
	var target := raw_gaze
	var blink_edge := false

	if not force_mouse_mode and _udp != null and now - _last_udp < UDP_TIMEOUT:
		source = "udp"
		target = raw_gaze                       # filled by _poll_udp
		blink_edge = _pending_blink
	elif not force_mouse_mode and GazeProvider.backend == GazeProvider.Backend.CAMERA and GazeProvider._camera_fresh():
		source = "camera"
		target = GazeProvider.gaze
		is_blinking = false
		blink_edge = _pending_blink
	else:
		source = "touch" if (Game.touch_mode and _touch_seen) else "mouse"
		var vs := get_viewport().get_visible_rect().size
		target = _touch_gaze if source == "touch" else (get_viewport().get_mouse_position() / vs).clamp(Vector2.ZERO, Vector2.ONE)
		var fire := Game.touch_fire
		if fire and not _fire_prev:
			_pending_blink = true
		_fire_prev = fire
		blink_edge = _pending_blink
	if debug_gaze.is_finite():
		target = debug_gaze
	raw_gaze = target
	gaze = gaze.lerp(target, 1.0 - exp(-_smooth_rate * delta))       # frame-rate independent smoothing: no jitter
	if blink_edge:
		just_blinked = true
		blinked.emit()
	_pending_blink = false


func _poll_udp() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var txt := _udp.get_packet().get_string_from_utf8()
		var d: Variant = JSON.parse_string(txt)
		if not (d is Dictionary):
			continue
		var dd: Dictionary = d
		_last_udp = _now()
		if dd.has("gaze_pos") and dd["gaze_pos"] is Array and (dd["gaze_pos"] as Array).size() >= 2:
			var a: Array = dd["gaze_pos"]
			raw_gaze = Vector2(clampf(float(a[0]), 0.0, 1.0), clampf(float(a[1]), 0.0, 1.0))
		ear = float(dd.get("ear", ear))
		var blinking_now := bool(dd.get("is_blinking", false))
		if _udp_blink_prev and not blinking_now:
			_pending_blink = true                  # the eyes just re-opened
		_udp_blink_prev = blinking_now
		is_blinking = blinking_now
		if dd.has("head_pitch_yaw") and dd["head_pitch_yaw"] is Array and (dd["head_pitch_yaw"] as Array).size() >= 2:
			var h: Array = dd["head_pitch_yaw"]
			head_pitch_yaw = Vector2(float(h[0]), float(h[1]))


func source_label() -> String:
	match source:
		"udp":
			return "WEBCAM (UDP)"
		"camera":
			return "EYES (camera)"
		"touch":
			return "TOUCH: tap = blink"
	return "MOUSE: space = blink"
