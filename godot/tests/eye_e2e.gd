extends Node
## End to end: the real Peek level, a simulated camera feed with the gaze held to one side, and a check that the VIEW turns.
##   godot --headless --path . res://tests/eye_e2e.tscn
var _fails := 0


func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1


func _feed(g: Vector2, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		GazeProvider._udp_gaze = g
		GazeProvider._calib = Vector2.ZERO
		GazeProvider._last_packet_msec = Time.get_ticks_msec()
		GazeProvider.confidence = 1.0
		GazeProvider._kal_pending = true
		await get_tree().process_frame


func _ready() -> void:
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	level.load_level(6)
	for i in 10:
		await get_tree().process_frame
	GazeProvider.set_backend(GazeProvider.Backend.CAMERA)
	GazeProvider.active = true
	GazeProvider._geo_ok = false
	GazeProvider._calibrated = false
	GazeProvider._ridge_ok = false
	GazeProvider._cal_done = true
	var cam: Camera3D = level.player.camera
	await _feed(Vector2(0.5, 0.5), 0.6)
	var gt := get_tree().get_first_node_in_group("gaze") as GazeTargeting
	print("setup: peek_mode %s rail_lock %s backend %s live %s gaze %s" % [Game.peek_mode, level.player.rail_lock, GazeProvider.backend_name(), gt._peek_eyes_live(), GazeProvider.gaze])
	Game.peek_eye_aim = true
	var yaw0 := cam.rotation.y
	await _feed(Vector2(0.12, 0.5), 2.0)
	var yaw1 := cam.rotation.y
	print("looking far left for 2 s: gaze %s  eye_look %s  camera yaw %.3f -> %.3f" % [GazeProvider.gaze, Game.peek_eye_look, yaw0, yaw1])
	_check(GazeProvider.gaze.x < 0.2, "the simulated gaze reaches the left side (%.2f)" % GazeProvider.gaze.x)
	_check(absf(Game.peek_eye_look.x) > 0.2, "the game asks the view to turn (%.2f rad)" % Game.peek_eye_look.x)
	_check(absf(yaw1 - yaw0) > 0.15, "and the camera really turns (%.3f rad)" % (yaw1 - yaw0))
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
