extends Node
## Headless checks for Ocular Trance:  godot --headless --path . res://tests/trance_test.tscn
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
	Game.touch_mode = false
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(9)
	await _frames(30)
	var rig: TranceRig = level._tr
	_check(rig != null and Game.trance_mode and rig.cam.current and rig.orbs.size() == 6, "trance rig starts: camera, %d orbs, %d blocks" % [rig.orbs.size(), rig.debris.size()])
	_check(AudioServer.get_bus_index(DopamineLoop.BUS_NAME) != -1, "the audio bus with low-pass and pitch shift exists")

	# --- camera maths (pure) ---
	var saw_up := true
	var prev := -1.0
	for i in 79:
		var v := AlteredStateCamera.sawtooth(float(i) / 100.0, 0.8)
		if v < prev:
			saw_up = false
		prev = v
	var snap := AlteredStateCamera.sawtooth(0.80, 0.8) - AlteredStateCamera.sawtooth(0.95, 0.8)
	_check(saw_up and snap > 0.5 and AlteredStateCamera.sawtooth(0.0, 0.8) == 0.0, "nystagmus is a sawtooth: slow drift, then a rapid snap back")
	_check(AlteredStateCamera.bob(0.25) > 0.6 and AlteredStateCamera.bob(0.52) > AlteredStateCamera.bob(0.9) + 0.4 and absf(AlteredStateCamera.bob(0.999)) < 0.05, "head bob lifts, then drops with gravity (pow 3)")
	# gravity: the drop starts slowly and ends fast
	var d1 := AlteredStateCamera.bob(0.5) - AlteredStateCamera.bob(0.6)
	var d2 := AlteredStateCamera.bob(0.9) - AlteredStateCamera.bob(1.0 - 0.0001)
	_check(d2 > d1 * 2.0, "the drop speeds up as it falls (%.2f then %.2f)" % [d1, d2])

	# --- intensity scales the camera effects ---
	var loop: DopamineLoop = rig.loop
	TrackerBridge.force_mouse_mode = true
	TrackerBridge.debug_gaze = Vector2(0.02, 0.98)         # looking at nothing
	loop.intensity = 0.0
	await _frames(40)
	var still := rig.cam.rotation.distance_to(rig.cam._base.basis.get_euler())
	loop.intensity = 1.0
	var moved := 0.0
	for i in 120:
		await get_tree().physics_frame
		moved = maxf(moved, rig.cam.rotation.distance_to(rig.cam._base.basis.get_euler()))
	_check(still < 0.002 and moved > 0.01, "intensity 0 holds the camera still, intensity 1 sways it (%.4f vs %.4f rad)" % [still, moved])

	# --- dwell -> charge -> effects ---
	loop.intensity = 0.8
	var orb: Node3D = rig.orbs[2]
	var vs := level.get_viewport().get_visible_rect().size
	var oc := rig.cam.unproject_position(orb.global_position)
	TrackerBridge.debug_gaze = oc / vs
	await _frames(20)
	_check(loop.target == orb and not loop.charging, "looking at an orb starts a dwell but does not charge yet (%.2f s)" % loop.dwell)
	await _frames(60)
	_check(loop.charging and loop.dwell > 0.5, "after 0.5 s of dwell it is CHARGING")
	var cut0 := (AudioServer.get_bus_effect(AudioServer.get_bus_index(DopamineLoop.BUS_NAME), 0) as AudioEffectLowPassFilter).cutoff_hz
	await _frames(120)
	var lp := AudioServer.get_bus_effect(AudioServer.get_bus_index(DopamineLoop.BUS_NAME), 0) as AudioEffectLowPassFilter
	var pt := AudioServer.get_bus_effect(AudioServer.get_bus_index(DopamineLoop.BUS_NAME), 1) as AudioEffectPitchShift
	var ab: float = float(rig._post_mat.get_shader_parameter("aberration"))
	_check(loop.charge > 0.3 and lp.cutoff_hz < cut0 - 3000.0 and pt.pitch_scale < 0.95 and ab > 0.3, "charge squeezes the audio and splits the colours (cutoff %.0f Hz, pitch %.2f, aberration %.2f)" % [lp.cutoff_hz, pt.pitch_scale, ab])
	var pm := rig._post_mat
	var f_all := float(pm.get_shader_parameter("flow")) > 0.05 and float(pm.get_shader_parameter("kaleido")) > 0.05 and float(pm.get_shader_parameter("rays")) > 0.05 and float(pm.get_shader_parameter("phos")) > 0.05 and float(pm.get_shader_parameter("tunnel")) > 0.05
	_check(f_all, "charging drives the ported effects: flow, kaleidoscope, tunnel, god rays, phosphene")
	loop.fx_mode = 0
	await _frames(3)
	_check(float(pm.get_shader_parameter("flow")) == 0.0 and float(pm.get_shader_parameter("kaleido")) == 0.0 and float(pm.get_shader_parameter("rays")) == 0.0, "CLASSIC mode turns the ported effects off")
	loop.fx_mode = 4
	await _frames(3)
	_check(float(pm.get_shader_parameter("rays")) > 0.3 and float(pm.get_shader_parameter("flow")) == 0.0, "GOD RAYS mode runs only the rays")
	loop.fx_mode = 6
	_check(DopamineLoop.charge_for_dwell(0.4) == 0.0 and DopamineLoop.charge_for_dwell(3.5) == 1.0, "the charge curve is zero before 0.5 s and full after 3.5 s")

	# --- a blink releases it ---
	var before := PackedVector3Array()
	for rb in rig.debris:
		before.append(rb.global_position)
	var score0 := loop.score
	var charge_at_release := loop.charge
	TrackerBridge.debug_blink()
	await _frames(3)
	var thrown := 0
	for i in rig.debris.size():
		if (rig.debris[i].linear_velocity.length() > 1.5) or rig.debris[i].global_position.distance_to(before[i]) > 0.5:
			thrown += 1
	_check(loop.discharges == 1 and loop.score > score0 and not loop.charging, "blinking while charging releases it and scores (+%d, x%.1f)" % [loop.score - score0, loop.multiplier])
	_check(thrown >= 4, "the shockwave throws the nearby blocks (%d moved)" % thrown)
	_check(loop.multiplier > 1.0 and charge_at_release > 0.3, "the multiplier climbs after a release")

	# --- a blink with no charge does nothing ---
	TrackerBridge.debug_gaze = Vector2(0.02, 0.98)
	await _frames(60)
	var d0 := loop.discharges
	TrackerBridge.debug_blink()
	await _frames(3)
	_check(loop.discharges == d0, "a blink while not charging does nothing")

	# --- looking away cancels the charge ---
	oc = rig.cam.unproject_position(rig.orbs[0].global_position)
	TrackerBridge.debug_gaze = oc / vs
	await _frames(90)
	var was_charging := loop.charging
	TrackerBridge.debug_gaze = Vector2(0.98, 0.02)
	await _frames(240)
	_check(was_charging and not loop.charging and loop.charge < 0.05, "looking away cancels the charge")

	# --- tracker bridge: UDP packet beats the mouse ---
	TrackerBridge.force_mouse_mode = false
	TrackerBridge.debug_gaze = Vector2.INF
	var tx := PacketPeerUDP.new()
	tx.set_dest_address("127.0.0.1", 4242)
	tx.put_packet(JSON.stringify({"gaze_pos": [0.8, 0.3], "ear": 0.3, "is_blinking": false, "head_pitch_yaw": [0.1, -0.2]}).to_utf8_buffer())
	await _frames(6)
	var udp_ok := TrackerBridge.source == "udp"
	_check(udp_ok and absf(TrackerBridge.raw_gaze.x - 0.8) < 0.01 and absf(TrackerBridge.head_pitch_yaw.y + 0.2) < 0.01, "a UDP packet from the webcam script is used (source %s)" % TrackerBridge.source)
	tx.put_packet(JSON.stringify({"gaze_pos": [0.8, 0.3], "ear": 0.1, "is_blinking": true}).to_utf8_buffer())
	await _frames(4)
	tx.put_packet(JSON.stringify({"gaze_pos": [0.8, 0.3], "ear": 0.3, "is_blinking": false}).to_utf8_buffer())
	var blink_state := [false]
	TrackerBridge.blinked.connect(func() -> void: blink_state[0] = true)
	await _frames(8)
	var got_blink: bool = blink_state[0]
	_check(got_blink, "the eyes re-opening in UDP data is a blink release")
	await _frames(80)
	_check(TrackerBridge.source == "mouse", "after 1 s of silence it falls back to the mouse")

	# --- every orb is inside the visible screen, in landscape and portrait ---
	var vsz := level.get_viewport().get_visible_rect().size
	var all_in := true
	for o in rig.orbs:
		var sp := rig.cam.unproject_position(o.global_position)
		if sp.x < 0.05 * vsz.x or sp.x > 0.95 * vsz.x or sp.y < 0.1 * vsz.y or sp.y > 0.9 * vsz.y or rig.cam.is_position_behind(o.global_position):
			all_in = false
	_check(all_in, "all orbs sit inside the visible screen")
	for k2 in 12:
		var tmp := loop.target
		rig.loop._respawn(rig.orbs[k2 % 6])
	await _frames(25)
	var respawn_in := true
	for o2 in rig.orbs:
		var sp2 := rig.cam.unproject_position(o2.global_position)
		if sp2.x < 0.05 * vsz.x or sp2.x > 0.95 * vsz.x or sp2.y < 0.1 * vsz.y or sp2.y > 0.9 * vsz.y:
			respawn_in = false
	_check(respawn_in, "respawned orbs also land inside the visible screen")

	# --- leaving cleans up ---
	level.load_level(6)
	await _frames(5)
	_check(level._tr == null and AudioServer.get_bus_index(DopamineLoop.BUS_NAME) == -1 and not Game.trance_mode and level.player.camera.current, "leaving trance removes the bus and restores the player camera")
	print("RESULT: " + ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
