extends Node
## The linked set piece, measured: ride until a spring-tube-rail chain stands ahead, put the board down 40 m before the spring in its lane, eyes ahead, and watch it:
## does the spring take it, does the tube deliver it onto the rail, does the rail run to its end, what is the payoff and how fast does it come out. BEND=1 for the winding trail.


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = false
	level.load_level(11)
	for i in 5:
		await get_tree().physics_frame
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.set_process(false)
	rig.trail = true
	rig.bend = OS.get_environment("BEND") != ""
	rig.apply_menu({"journey": true, "seed": int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7, "theme": "alpine", "mus": "off", "session": 10, "trip": 1}, level)
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	var tested := 0
	var seen := {}
	var guard := 0
	while tested < 3 and guard < 60 * 900:
		guard += 1
		rig._physics_process(dt)
		rig._process(dt)
		var target: Dictionary = {}
		for rk in rig._rows:
			for p in (rig._rows[rk] as Dictionary).get("pads", []):
				if p.has("lk") and (p["lk"] as Dictionary).get("open", false) and not seen.has(float(p["z"])) and float(p["z"]) < rig.spos.z - 80.0 and float(p["z"]) > rig.spos.z - 380.0:
					target = p
					break
			if not target.is_empty():
				break
		if target.is_empty():
			continue
		seen[float(target["z"])] = true
		tested += 1
		var px := float(target["x"])
		var pz := float(target["z"])
		var score0 := rig.score
		var gl0 := rig.glints
		rig.spos = Vector3(px, rig.terrain_h(px, pz + 40.0), pz + 40.0)
		rig.vel = Vector2(0.0, -34.0)
		rig.grounded = true
		rig._gh_prev = rig.spos.y
		rig._line_pick = {}
		rig.pick_override = signf(px - rig.trail_x(pz))
		var started := false
		var opened := false
		var caught := false
		var maxy := 0.0
		for i in 60 * 10:
			rig._physics_process(dt)
			rig._process(dt)
			if not started and not rig._lk.is_empty():
				started = true
				rig.pick_override = [-0.8, 0.0, 0.8][tested - 1]          # the look in the air: left, middle, right
			if started and not rig._lkp.is_empty():
				opened = true
			if opened and rig._lkp.is_empty():
				caught = true
			maxy = maxf(maxy, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
			if caught and i > 0:
				break
		rig.pick_override = 0.0
		print("LAUNCH #%d: spring taken %s | open %s | caught %s | max height %.1f m | score +%d | glints +%d | hurt %s" % [tested, str(started), str(opened), str(caught), maxy, rig.score - score0, rig.glints - gl0, str(rig.hurt_t > 0.0)])
	print("launches tested %d in %d frames" % [tested, guard])
	get_tree().quit()
