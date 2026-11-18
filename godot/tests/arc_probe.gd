extends Node
## All dressed, as a player meets it: a simulated rider who takes most of the molecule rows they pass (EAT, default 0.7) and now and then hits something (HIT per minute, default 1).
## Prints when each wave comes on, and a line a minute: session phase, levels held, what is felt. SESSION = minutes (10, 60, ...), MINS = how long to run, TRIP = 0..2.


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
	rig.prof_rows = OS.get_environment("PROF") != ""
	var sess := int(OS.get_environment("SESSION")) if OS.get_environment("SESSION") != "" else 10
	var trip := int(OS.get_environment("TRIP")) if OS.get_environment("TRIP") != "" else 1
	rig.apply_menu({"journey": true, "seed": 7, "theme": "alpine", "mus": "off", "session": sess, "trip": trip, "endless": OS.get_environment("FINITE") == ""}, level)
	await get_tree().process_frame
	var j: DhJourney = rig._journey
	if j == null:
		print("ARC no journey")
		get_tree().quit()
		return
	var eat := float(OS.get_environment("EAT")) if OS.get_environment("EAT") != "" else 0.7
	var hit := float(OS.get_environment("HIT")) if OS.get_environment("HIT") != "" else 1.0
	var mins := int(OS.get_environment("MINS")) if OS.get_environment("MINS") != "" else 10
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var dt := 1.0 / 30.0
	var last := ""
	var seen := {}
	var rows_met := 0
	var eaten := 0
	var first_wave := -1.0
	var in_wave := 0.0
	var strong := 0.0
	var ring_n := 0
	var pad_seen := {}
	var pad_n := 0
	var pad_bad := 0
	var step_ms: Array = []
	var feat_seen := {}
	var feat_n := {}
	var feat_seq: Array = []
	var ring_worst := 0.0
	var ring_bend := 0.0
	print("ARC session %d min, trip level %d, takes %.0f%% of rows, %.1f hits a minute" % [sess, trip, eat * 100.0, hit])
	for i in int(mins * 60.0 / dt):
		var tm := float(i) * dt
		GazeProvider.set_scripted(Vector2(0.5, 0.45))
		var t0 := Time.get_ticks_usec()
		var rows0: int = rig._rows.size()
		var rk0: Array = rig._rows.keys()
		rig._physics_process(dt)
		rig._process(dt)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		step_ms.append(ms)
		if ms > 6.0 and OS.get_environment("PROF") != "":
			var newrow := false
			for rkk in rig._rows.keys():
				if not rk0.has(rkk):
					newrow = true
			print("ARC  slow step %.1f ms at %.1f s  (a new stretch was built: %s)" % [ms, tm, str(newrow)])
		for rk in rig._rows:
			var cand: Array = []
			for t in (rig._rows[rk] as Dictionary).get("toys", []):
				if String(t["kind"]) == "pill" and absf(float(t["z"]) - rig.spos.z) < 6.0 and not seen.has(int(round(float(t["z"]) / 20.0))):
					cand.append(t)
			if cand.is_empty():
				continue
			for t in cand:
				seen[int(round(float(t["z"]) / 20.0))] = true
				seen[int(round(float(t["z"]) / 20.0)) - 1] = true
				seen[int(round(float(t["z"]) / 20.0)) + 1] = true
			rows_met += 1
			if rng.randf() < eat:
				# a player who looks: the one of the three they hold least of
				var bt: Dictionary = cand[0]
				for t in cand:
					if rig._mdose[MolData.ORDER.find(String(t["id"]))] < rig._mdose[MolData.ORDER.find(String(bt["id"]))]:
						bt = t
				rig._pill_eat(bt)
				eaten += 1
		if rng.randf() < hit * dt / 60.0:
			rig._mol_hurt(-1)
		if j.phase != 0:
			in_wave += dt
			if first_wave < 0.0:
				first_wave = tm
			if j.strength >= 0.7:
				strong += dt
		var k := "%s w%d %s" % [j.world, j.wave, ["calm", "onset", "PEAK", "offset"][j.phase]]
		if k != last and j.phase == 1:
			print("ARC  %5.1f min  wave %d comes on: %-12s strength %.2f   felt %.2f (needs %.2f)" % [tm / 60.0, j.wave, j.world, j.strength, rig._body, j._thr(j.wave)])
		last = k
		if i % int(60.0 / dt) == 0 and i > 0:
			var lv := ""
			for m in 6:
				lv += "%d" % int(rig._mdose[m])
			print("ARC  %5.1f min  %-9s target %.2f  levels %s  avg %.2f  felt %.2f  rows met %d taken %d  bias x%.2f  all-six %.2f" % [tm / 60.0, rig._pacer.phase_name() if rig._pacer != null else "-", rig._pacer.target() if rig._pacer != null else 0.0, lv, rig._mol_avg(), rig._body, rows_met, eaten, rig._pacer.spawn_bias(rig._mol_avg()) if rig._pacer != null else 1.0, rig._mol_dmt()])
		if i % int(60.0 / dt) == 0 and OS.get_environment("TOYS") != "":
			var kc := {}
			for rk2 in rig._rows:
				for t2 in (rig._rows[rk2] as Dictionary).get("toys", []):
					kc[String(t2["kind"])] = int(kc.get(String(t2["kind"]), 0)) + 1
			print("ARC  toys live now: ", kc, "  rows ", rig._rows.size(), "  speed %.0f m/s  z %.0f" % [-rig.vel.y, rig.spos.z])
		if OS.get_environment("RINGS") != "" and i % 300 == 0:
			for kk in rig._kickers:
				for rn in (kk.get("vx", []) as Array):
					if is_instance_valid(rn) and (rn as Node3D).has_meta("Z"):
						var zz := float((rn as Node3D).get_meta("Z"))
						var axis := ((rn as Node3D).global_transform.basis.y).normalized()          # a torus's hole runs along its own Y
						var want := TrailCurve.dir(Vector3(0, 0, -1), zz)
						var off := rad_to_deg(acos(clampf(absf(axis.dot(want)), 0.0, 1.0)))
						ring_n += 1
						ring_worst = maxf(ring_worst, off)
						ring_bend = maxf(ring_bend, absf(rad_to_deg(TrailCurve.heading(zz))))
		if i % 60 == 0:
			for rk3 in rig._rows:
				for ff in (rig._rows[rk3] as Dictionary).get("feats", []):
					if ff.has("hz"):
						continue
					var fk := "%s@%d" % [String(ff["kind"]), int(float(ff.get("zl", ff.get("za", 0.0))))]
					if not feat_seen.has(fk):
						feat_seen[fk] = true
						var lane: String = ["L", "C", "R"][int(signf(float(ff["sd"]))) + 1]
						var nm := String(ff["kind"]) + " " + lane
						feat_n[nm] = int(feat_n.get(nm, 0)) + 1
						feat_seq.append([float(ff.get("zl", ff.get("za", 0.0))), String(ff["kind"]).substr(0, 2) + lane])
		if i % 30 == 0:
			for rk4 in rig._rows:
				for pd in (rig._rows[rk4] as Dictionary).get("pads", []):
					if pad_seen.has(float(pd["z"])) or not is_instance_valid(pd["gem"]) or float(pd["z"]) > rig.spos.z - 40.0:
						continue
					pad_seen[float(pd["z"])] = true
					var want_y := rig.terrain_h(float(pd["x"]), float(pd["z"]) - 2.2) + 1.35
					var got_y := (pd["gem"] as Node3D).global_position.y
					pad_n += 1
					if absf(got_y - want_y) > 0.6:
						pad_bad += 1
						var neark := ""
						for kq in rig._kickers:
							if absf(float(kq["z"]) - float(pd["z"])) < 120.0:
								neark = " (a ramp at %.0f m along, %.0f m across from it)" % [float(kq["z"]) - float(pd["z"]), float(kq["x"]) - float(pd["x"])]
						if pad_bad <= 6:
							print("ARC PAD OFF THE GROUND by %+.1f m at z %.0f%s" % [got_y - want_y, float(pd["z"]), neark])
		if rig._finished:
			print("ARC finished early at %.1f min" % (tm / 60.0))
			break
	print("ARC SUMMARY first wave at %.1f min, %.0f%% of the time inside a wave, %.0f%% in a strong one, waves done %d, rows met %d, taken %d" % [first_wave / 60.0, in_wave / (mins * 60.0) * 100.0, strong / (mins * 60.0) * 100.0, j.wave, rows_met, eaten])
	step_ms.sort()
	print("ARC STEP TIME (this machine, native): median %.2f ms, 99th %.2f ms, worst %.1f ms, steps over 6 ms: %d of %d" % [step_ms[step_ms.size() / 2], step_ms[int(step_ms.size() * 0.99)], step_ms[-1], step_ms.filter(func(x): return x > 6.0).size(), step_ms.size()])
	print("ARC PADS checked %d, off the ground: %d" % [pad_n, pad_bad])
	var ks := feat_n.keys()
	ks.sort()
	var line := ""
	for kq in ks:
		line += "%s %d   " % [kq, feat_n[kq]]
	print("ARC TARGETS over %.1f km: %s" % [-rig.spos.z / 1000.0, line])
	feat_seq.sort_custom(func(x, y): return x[0] > y[0])
	var sq := ""
	for e in feat_seq.slice(0, 70):
		sq += String(e[1]) + " "
	print("ARC TARGET ORDER (first 70): ", sq)
	if ring_n > 0:
		print("ARC RINGS checked %d: worst angle between a ring's opening and the trail there %.1f deg (trail bends up to %.0f deg from straight)" % [ring_n, ring_worst, ring_bend])
	get_tree().quit()
