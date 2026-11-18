extends Node
## Ramps and boost pads, measured. For the first few ramps on the trail the board is set down 80 m before the foot, OFF metres to the side of the ramp's line (default 0, then 8, then 16),
## and left alone (eyes straight ahead): does the swirl take it, does it stay on, does it leave the lip, how high and how long does it fly. Then the same for a boost pad: speed before
## and after. BEND=1 for the winding trail.


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
	rig.apply_menu({"journey": true, "seed": 7, "theme": "alpine", "mus": "off", "session": 10, "trip": 1}, level)
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	# ride until a few ramps exist
	var tested := 0
	var done_z := {}
	var offs := [0.0, 8.0, -8.0, 16.0, 0.0, 12.0]
	var guard := 0
	while tested < offs.size() and guard < 60 * 240:
		guard += 1
		rig._physics_process(dt)
		rig._process(dt)
		var target: Dictionary = {}
		for k in rig._kickers:
			if k.get("trail", false) and not done_z.has(float(k["z"])) and float(k["z"]) < rig.spos.z - 90.0 and float(k["z"]) > rig.spos.z - 400.0:
				target = k
				break
		if target.is_empty():
			continue
		done_z[float(target["z"])] = true
		var kx := float(target["x"])
		var kz := float(target["z"])
		var klen := float(target["len"])
		var off: float = offs[tested]
		tested += 1
		var sx := kx + off
		var mode := "eyes ahead"
		GazeProvider.set_scripted(Vector2(0.5, 0.45))
		if tested > 3:
			sx = rig.trail_x(kz + 80.0)          # from the middle of the trail, looking over at the ramp's side (or, for the last one, away from it)
			var sgn := signf(kx - rig.trail_x(kz)) * (-1.0 if tested == 6 else 1.0)
			GazeProvider.set_scripted(Vector2(0.5 + 0.3 * sgn, 0.45))
			mode = "from the middle, looking " + ("AWAY from it" if tested == 6 else "at its side")
			off = sx - kx
		rig.spos = Vector3(sx, rig.terrain_h(sx, kz + 80.0), kz + 80.0)
		rig.vel = Vector2(0.0, -26.0)
		rig.grounded = true
		rig._gh_prev = rig.spos.y
		var pulled := false
		var on_ramp := 0.0
		var left_lip := false
		var air := 0.0
		var hmax := 0.0
		var min_dx := 999.0
		var dx_at_foot := 999.0
		var dx_at_lip := 999.0
		var v_lip := 0.0
		var fell_side := false
		for i in 60 * 9:
			rig._physics_process(dt)
			rig._process(dt)
			var dx := absf(rig.spos.x - kx)
			if rig._vx_pull > 0.05:
				pulled = true
			if rig.spos.z < kz and rig.spos.z > kz - klen:
				if dx_at_foot > 900.0:
					dx_at_foot = dx
				min_dx = minf(min_dx, dx)
				if rig.grounded and dx < float(target["w"]) * 0.5:
					on_ramp += dt
				if dx > float(target["w"]) * 0.5 + 1.0:
					fell_side = true
			if rig.spos.z < kz - klen and dx_at_lip > 900.0:
				dx_at_lip = dx
				v_lip = -rig.vel.y
			if OS.get_environment("FLY") != "" and rig.spos.z < kz - klen + 6.0 and i % 15 == 0 and (not rig.grounded or rig.spos.z > kz - klen - 4.0):
				print("   fly t=%.2f  vy %.1f  alt %.1f  y %.1f  fwd %.0f m/s  grounded %s  gravity %.1f  boost %.1f" % [float(i) * dt, rig.vy, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z), rig.spos.y, -rig.vel.y, str(rig.grounded), rig.G, rig._boost_t])
			if rig.spos.z < kz - klen + 2.0 and not rig.grounded:
				left_lip = true
				air += dt
				hmax = maxf(hmax, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
			if rig.spos.z < kz - klen - 160.0:
				break
		print("RAMP (" + mode + ") start %+5.1f m to the side: swirl took hold %s | off line at the foot %.1f m, at the lip %.1f m (ramp half-width %.1f) | on the ramp %.2f s | went off the side %s | flew %s, %.2f s, %.1f m high, %.0f km/h at the lip" % [
			off, str(pulled), dx_at_foot, dx_at_lip, float(target["w"]) * 0.5, on_ramp, str(fell_side), str(left_lip and air > 0.4), air, hmax, v_lip * 3.6])
	# ---- boost pads
	var pt := 0
	guard = 0
	var seen := {}
	while pt < 4 and guard < 60 * 240:
		guard += 1
		rig._physics_process(dt)
		rig._process(dt)
		for rk in rig._rows:
			for p in (rig._rows[rk] as Dictionary).get("pads", []):
				var pz := float(p["z"])
				if pt >= 4 or seen.has(pz) or bool(p["used"]) or pz > rig.spos.z - 60.0 or pz < rig.spos.z - 300.0:
					continue
				seen[pz] = true
				pt += 1
				var px := float(p["x"])
				var v0: float = [18.0, 28.0, 36.0, 42.0][pt - 1]
				rig.spos = Vector3(px, rig.terrain_h(px, pz + 25.0), pz + 25.0)
				rig.vel = Vector2(0.0, -v0)
				rig.grounded = true
				rig._gh_prev = rig.spos.y
				var hit0 := rig.pads_hit
				print("PAD   is %.0f m from its stretch's own z (the pad code skips stretches more than 130 m away)" % absf(float((rig._rows[rk] as Dictionary)["z"]) - pz))
				GazeProvider.set_scripted(Vector2(0.5 + clampf((px - rig.trail_x(pz)) / 7.0, -1.0, 1.0) * 0.3, 0.45))          # looking at the pad's lane
				var v_before := 0.0
				var v_after := 0.0
				var v_peak := 0.0
				var miss_x := 0.0
				for i in 150:
					rig._physics_process(dt)
					rig._process(dt)
					if absf(rig.spos.z - (pz - 2.2)) < 1.0 and OS.get_environment("PADDBG") != "":
						print("PAD     at the pad: grounded %s, x off %.1f, height over snow %.2f" % [str(rig.grounded), rig.spos.x - px, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z)])
					if rig.spos.z > pz + 2.0:
						v_before = rig.vel.length()
						miss_x = rig.spos.x - px
					if rig.pads_hit > hit0:
						v_peak = maxf(v_peak, rig.vel.length())
				v_after = rig.vel.length()
				print("PAD arriving at %.0f km/h, %.1f m off its middle: taken %s | just before %.0f km/h, peak after %.0f km/h, 2 s later %.0f km/h (cap %.0f km/h)" % [v0 * 3.6, miss_x, str(rig.pads_hit > hit0), v_before * 3.6, v_peak * 3.6, v_after * 3.6, rig.SPEED_CAP * 3.6])
	get_tree().quit()
