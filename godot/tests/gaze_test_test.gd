extends Node
## godot --headless --path . res://tests/gaze_test_test.tscn
var _fails := 0
func _check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		_fails += 1
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(10)
	await _frames(5)
	var rig: GazeTestRig = level._gt
	_check(rig != null and Game.gaze_test_mode and rig.cam.current, "gaze test starts and owns the camera")
	TrackerBridge.force_mouse_mode = true
	var guard := 0
	while not rig.done and guard < 2600:
		TrackerBridge.debug_gaze = rig.target() + Vector2(0.03, 0.02)
		await get_tree().physics_frame
		guard += 1
	_check(rig.done and rig.results.size() == GazeTestRig.N_TARGETS, "it walks through %d targets and finishes (%d frames)" % [GazeTestRig.N_TARGETS, guard])
	var off := rig.mean_offset()
	_check(absf(off.x - 0.03) < 0.012 and absf(off.y - 0.02) < 0.012, "it measures the tracker offset (%.3f, %.3f vs 0.030, 0.020)" % [off.x, off.y])
	var me := rig.mean_error(1.78)
	_check(me > 0.02 and me < 0.05, "and the average error (%.3f of the screen width)" % me)
	TrackerBridge.debug_gaze = Vector2.INF
	rig.restart()
	_check(not rig.done and rig.results.is_empty(), "restart clears the results")
	# the game polls ~33x/s but the camera gives ~15 frames/s: the same frame must not enter the smoothing buffers twice
	GazeProvider._geo_buf.clear()
	GazeProvider._limb_buf.clear()
	GazeProvider._last_frame_n = -1
	var pkt := {"conf": 1.0, "x": 0.5, "y": 0.5, "bx": 0.5, "by": 0.5, "gu": 0.4, "gv": 0.3, "lx": 0.5, "ly": 0.5, "n": 7, "hyaw": 0.0, "hpitch": 0.0}
	for i in 3:
		GazeProvider.ingest(pkt)
	var after_dupes: int = GazeProvider._geo_buf.size()
	pkt["n"] = 8
	pkt["gu"] = 0.45
	GazeProvider.ingest(pkt)
	GazeProvider.ingest(pkt)
	_check(GazeProvider._pkt_times.size() <= 2, "the frame-rate counter counts distinct camera frames, not polls (%d)" % GazeProvider._pkt_times.size())
	_check(after_dupes == 1 and GazeProvider._geo_buf.size() == 2 and GazeProvider._limb_buf.size() == 2, "a repeated camera frame enters the gaze buffers once (%d, then %d)" % [after_dupes, GazeProvider._geo_buf.size()])
	GazeProvider._geo_buf.clear()
	GazeProvider._limb_buf.clear()

	level.load_level(6)
	await _frames(5)
	_check(level._gt == null and not Game.gaze_test_mode and level.player.camera.current, "leaving restores the player camera")
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
