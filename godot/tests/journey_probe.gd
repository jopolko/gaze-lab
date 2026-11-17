extends Node
## All dressed: runs the forest trail for a while with the journey clock sped up and reports every change of world, the speeds, and anything that breaks.


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
	rig.apply_menu({"journey": true, "seed": 7, "theme": "alpine", "mus": "off"}, level)
	await get_tree().process_frame
	var j: DhJourney = rig._journey
	print("JOURNEY object: ", j != null)
	if j == null:
		get_tree().quit()
		return
	j.time_scale = float(OS.get_environment("JT")) if OS.get_environment("JT") != "" else 10.0
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 150
	var last := ""
	var dt := 1.0 / 60.0
	var vmax_by := {}
	var sky_seen := 0
	var last_sky: SkyRun = null
	var sling_t := -1.0
	for i in 60 * secs:
		GazeProvider.set_scripted(Vector2(0.5, 0.45))
		rig._physics_process(dt)
		rig._process(dt)
		if OS.get_environment("SLING") != "" and sling_t < 0.0 and i % 60 == 0 and i >= 180:
			var found := false
			for rk in rig._rows:
				for tt in (rig._rows[rk] as Dictionary).get("toys", []):
					if String(tt["kind"]) == "sling" and not found:
						found = true
						rig.spos = Vector3(float(tt["x"]) + 4.0, rig.terrain_h(float(tt["x"]) + 4.0, float(tt["z"]) + 24.0), float(tt["z"]) + 24.0)
						rig.vel = Vector2(0.0, -28.0)
						rig.grounded = true
						sling_t = float(i)
						print("SLING test: placed 24 m before the orb, 4 m to the side")
		if sling_t > 0.0 and float(i) - sling_t < 240.0 and (i - int(sling_t)) % 20 == 0:
			print("SLING t+%.2f dz-to-orb: speed %.1f m/s  vx %.1f  boost %.1f" % [(float(i) - sling_t) * dt, -rig.vel.y, rig.vel.x, rig._boost_t])
		if OS.get_environment("SKY") != "" and i == 60 * 10:
			rig.sky_start()
			print("SKY started at z=", rig.spos.z)
		if rig._sky != null and is_instance_valid(rig._sky):
			var sk: SkyRun = rig._sky
			last_sky = sk
			rig.zone_test = [0, -1, 1, 0, 1, -1][int(sk._age / 2.5) % 6]          # the eyes look left, middle and right in turn
			rig.zn_test = 99.0
			GazeProvider.nod_debug = Vector2(0.0, 0.0)
			if sk.energy > 40.0 and int(sk._age * 10.0) % 40 == 0:
				sk._tap = true
			for it2 in sk.items:
				if String(it2["type"]) == "pinata" and sk.global_position.distance_to(it2["pos"]) < 140.0 and sk.energy >= 25.0 and sk.blast_cd <= 0.0:
					sk._tap = true
			if OS.get_environment("PINTEST") != "":
				for it4 in sk.items:
					if String(it4["type"]) == "pinata" and int(it4["hp"]) > 0 and float(it4["cool"]) <= 0.0:
						sk.global_position = (it4["pos"] as Vector3) + Vector3(0, 0, 6)
						sk.alt = (it4["pos"] as Vector3).y - SkyRun.DECK_Y
						sk.speed = 60.0
						sk.blast_t = 1.0
			if int(sk._age * 60.0) % 60 == 0 and sk.timer > 17.0:
				for it3 in sk.items:
					if String(it3["type"]) == "pinata":
						print("PIN dist %.0f z-rel %.0f lock %s energy %.0f speed %.0f blast %.1f hp %d" % [sk.global_position.distance_to(it3["pos"]), sk.global_position.z - it3["pos"].z, str(sk.lock.get("type", "-")), sk.energy, sk.speed, sk.blast_t, it3["hp"]])
			sk._physics_process(dt)
			sk._process(dt)
			if i % 120 == 0:
				print("SKY steer %.2f head %.2f eye %.2f x %.0f  phase %d alt %.0f timer %.1f/%.0f speed %.0f items %d score %d goals %s" % [sk.steer, sk.heading, rig.eye_now(), sk.global_position.x - sk._start_x, sk.phase, sk.alt, sk.timer, sk.duration, sk.speed, sk.items.size(), sk.score, str(sk.goals.map(func(g): return "%s %d/%d" % [g["k"], g["have"], g["need"]]))])
		elif sky_seen == 0 and rig.sky_visits > 0:
			sky_seen = 1
			print("SKY ended: back on the slope at z=%.0f y=%.0f grounded=%s hold=%s score=%d" % [rig.spos.z, rig.spos.y, str(rig.grounded), str(rig.sky_hold), rig.score])
		var key := "%s w%d %s" % [j.world, j.wave, ["calm", "onset", "PEAK", "offset"][j.phase]]
		if key != last:
			last = key
			print("JOURNEY t=%5.1fs  %-34s spd_k %.2f haz %.2f jumps %.2f pads %.2f grip %.2f  strength %.2f  diff %.2f  trip %.2f  post %d shown %s" % [float(i) * dt, key, rig._spd_k, rig.hazard_share, rig.jump_chance, rig.pad_chance, rig.grip_lag, j.strength, j.difficulty(), rig.trip, rig._jpost_mode, str(j._shown.values().map(func(b): return 1 if b else 0))])
		if i % 60 == 0 and j.phase != 0 and OS.get_environment("ONS") != "":
			print("ONSET t=%4.1f phase %d e %.2f post %d trip %.2f shown %s" % [float(i) * dt, j.phase, j.onset_k(), rig._jpost_mode, rig.trip, str(j._shown.values().map(func(b): return 1 if b else 0))])
		var v := -rig.vel.y * 3.6
		vmax_by[j.world if j.phase != 0 else "alpine"] = maxf(float(vmax_by.get(j.world if j.phase != 0 else "alpine", 0.0)), v)
		if rig._finished:
			print("finished early at ", float(i) * dt)
			break
	if OS.get_environment("NODES") != "":
		var cnt := {}
		var stack: Array = [level]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			for ch in nd.get_children():
				stack.append(ch)
			if nd is MeshInstance3D or nd is MultiMeshInstance3D or nd is GPUParticles3D or nd is CPUParticles3D or nd is Sprite3D:
				var vis := (nd as Node3D).is_visible_in_tree()
				var key := "%s%s" % [nd.get_class(), "" if vis else " (hidden)"]
				cnt[key] = int(cnt.get(key, 0)) + 1
				if nd is MeshInstance3D and vis:
					var m := (nd as MeshInstance3D).mesh
					var k2 := "  mesh %s" % (m.get_class() if m != null else "none")
					cnt[k2] = int(cnt.get(k2, 0)) + 1
		print("NODES ", cnt)
		print("ROWS ", rig._rows.size(), " chunks ", rig._chunks.size())
	var lane_c := {}
	for rk in rig._rows:
		for ff in (rig._rows[rk] as Dictionary).get("feats", []):
			if ff.has("hz"):
				continue
			var kk := "%s sd%+d" % [String(ff["kind"]), int(float(ff["sd"]))]
			lane_c[kk] = int(lane_c.get(kk, 0)) + 1
	print("LANES ", lane_c)
	if last_sky != null:
		print("SKYSTATS ", last_sky.stats, " best combo ", last_sky.best_combo, " score ", last_sky.score, " trip ", snappedf(last_sky.trip_lvl, 0.01), " goals ", last_sky.goals.map(func(g): return "%s %d/%d" % [g["k"], g["have"], g["need"]]))
	print("JOURNEY top speed by world (km/h): ", vmax_by)
	print("JOURNEY waves done: ", j.wave, "  score ", rig.score, "  crashes ", rig.crashes if "crashes" in rig else -1)
	get_tree().quit()
