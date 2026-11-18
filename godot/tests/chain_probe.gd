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
	var chains_seen := 0
	while tested < 4 and guard < 60 * 400:
		guard += 1
		rig._physics_process(dt)
		rig._process(dt)
		var target: Dictionary = {}
		for rk in rig._rows:
			for p in (rig._rows[rk] as Dictionary).get("pads", []):
				if p.has("lk") and not seen.has(float(p["z"])) and float(p["z"]) < rig.spos.z - 80.0 and float(p["z"]) > rig.spos.z - 380.0:
					target = p
					break
			if not target.is_empty():
				break
		if target.is_empty():
			continue
		seen[float(target["z"])] = true
		chains_seen += 1
		tested += 1
		var d: Dictionary = target["lk"]
		var px := float(target["x"])
		var pz := float(target["z"])
		var rail: Dictionary = d["rail"]
		var v0: float = [20.0, 30.0, 40.0, 46.0][tested - 1]
		rig.spos = Vector3(px, rig.terrain_h(px, pz + 40.0), pz + 40.0)
		rig.vel = Vector2(0.0, -v0)
		rig.grounded = true
		rig._gh_prev = rig.spos.y
		rig._line_pick = {}
		rig.pick_override = signf(px - rig.trail_x(pz))          # a look at the spring's side
		var started := false
		var t_start := 0.0
		var on_rail := false
		var t_rail := 0.0
		var ended := false
		var v_end := 0.0
		var min_alt := 999.0
		var max_alt := 0.0
		var x_err := 999.0
		var lk0 := rig.lk_done
		var score0 := rig.score
		var hurt := false
		var nxt: Dictionary = {}
		var nxt_dx := 999.0
		var nxt_alt := 0.0
		var relay := false
		var relay_depth := 0
		var relay_t := 0.0
		var pad_dbg := "never reached the pad"
		for i in 60 * 9:
			rig._physics_process(dt)
			rig._process(dt)
			var tt := float(i) * dt
			if not started and not rig._lk.is_empty():
				started = true
				t_start = tt
			if started and rig._lk.is_empty() and not on_rail and not rig._rail.is_empty():
				on_rail = true
				t_rail = tt
				x_err = absf(rig.spos.x - float(rail["kx"]))
			if not rig._lk.is_empty():
				var alt := rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z)
				min_alt = minf(min_alt, alt)
				max_alt = maxf(max_alt, alt)
			if rig.hurt_t > 0.0:
				hurt = true
			if absf(rig.spos.z - (pz - 2.2)) < 0.4 and not started:
				pad_dbg = "at the pad: %.1f m off its middle, %.1f m up, grounded %s, vortex lock %.1f, used %s, pick %s, line_pick %s" % [rig.spos.x - px, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z), str(rig.grounded), rig._vx_lock_t, str(target["used"]), str(rig.pick_override), String(rig._line_pick.get("kind", "-"))]
			if on_rail and rig._rail.is_empty() and not ended:
				ended = true
				v_end = -rig.vel.y
				var bz := 1.0e9
				for rk2 in rig._rows:
					for p2 in (rig._rows[rk2] as Dictionary).get("pads", []):
						if p2.has("lk") and float(p2["z"]) < float(rail["zb"]) - 30.0 and float(rail["zb"]) - float(p2["z"]) < bz:
							bz = float(rail["zb"]) - float(p2["z"])
							nxt = p2
			if not nxt.is_empty() and nxt_dx > 900.0 and rig.spos.z < float(nxt["z"]) - 2.2:
				nxt_dx = rig.spos.x - float(nxt["x"])
				nxt_alt = rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z)
			if started and rig._lk.is_empty():
				rig.pick_override = 0.0          # the look was only needed to get to the spring
			if ended and not rig._lk.is_empty() and not relay:
				relay = true
				relay_depth = rig._lk_depth
				relay_t = tt
			if ended and tt > t_rail + 6.0:
				break
		rig.pick_override = 0.0
		if not started:
			print("   MISS: ", pad_dbg)
		print("CHAIN #%d  arriving %.0f km/h | spring taken %s (at %.2f s) | tube alt %.1f..%.1f m | on the rail %s (%.2f s, %.1f m off its line) | rail ran to the end %s | payoff %s | score +%d | out at %.0f km/h | hurt %s | NEXT: %s (%s) taken as link %d | next spring: board %.1f m off it, %.1f m up as it passes" % [
			tested, v0 * 3.6, str(started), t_start, min_alt, max_alt, str(on_rail), t_rail, x_err, str(ended), str(rig.lk_done > lk0), rig.score - score0, v_end * 3.6, str(hurt), String(rig._lk_follow.get("kind", "built")), "relay yes" if relay else "relay no", relay_depth, nxt_dx, nxt_alt])
	print("chains seen %d in %d frames" % [chains_seen, guard])
	get_tree().quit()
