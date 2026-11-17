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
	if OS.get_environment("DOSE") != "":
		rig._dose = float(OS.get_environment("DOSE"))          # pills taken: a dose to start with
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 150
	var last := ""
	var dt := 1.0 / 60.0
	var vmax_by := {}
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
		var shown := 0
		for nd in rig.find_children("*", "MeshInstance3D", true, false):
			var mi := nd as MeshInstance3D
			if mi.mesh == rig._pad_mesh and shown < 3:
				shown += 1
				print("PAD mesh at ", mi.global_position, " aabb ", mi.mesh.get_aabb(), " vis ", mi.is_visible_in_tree(), " range_end ", mi.visibility_range_end, " tris ", (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " mat ", mi.material_override)
		var nb := 0
		for rk in rig._rows:
			for bf in (rig._rows[rk] as Dictionary).get("buffs", []):
				if nb < 4 and is_instance_valid(bf["n"]):
					nb += 1
					var bnode: Node3D = bf["n"]
					var kids := bnode.find_children("*", "MeshInstance3D", true, false)
					var info := ""
					for kd in kids:
						var km := kd as MeshInstance3D
						info += "[%s vis %s scale %s y %.1f]" % [km.mesh.get_class() if km.mesh != null else "none", str(km.is_visible_in_tree()), str(km.global_transform.basis.get_scale()), km.global_position.y]
					var jj := int(-bnode.global_position.z / 180.0)
					if rig._chunks.has(jj):
						var cmi := rig._chunks[jj] as MeshInstance3D
						var vv: PackedVector3Array = cmi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
						var best := 1.0e9
						var by := 0.0
						for v in vv:
							var dd := absf(v.x - bnode.global_position.x) + absf(v.z - bnode.global_position.z)
							if dd < best:
								best = dd
								by = v.y
						print("  GROUND MESH vs terrain at buff: mesh y ", snappedf(by, 0.1), " analytic ", snappedf(rig.terrain_h(bnode.global_position.x, bnode.global_position.z), 0.1), " nearest vertex off by ", snappedf(best, 0.1), " m, chunk pos ", cmi.global_position)
					print("BUFF ", bf["t"], " at y ", snappedf(bnode.global_position.y, 0.1), " ground ", snappedf(rig.terrain_h(bnode.global_position.x, bnode.global_position.z), 0.1), " base_y ", snappedf(float(bf["y"]), 0.1), " kids ", kids.size(), " ", info.substr(0, 400))
		print("ROWS ", rig._rows.size(), " chunks ", rig._chunks.size())
	var lane_c := {}
	for rk in rig._rows:
		for ff in (rig._rows[rk] as Dictionary).get("feats", []):
			if ff.has("hz"):
				continue
			var kk := "%s sd%+d" % [String(ff["kind"]), int(float(ff["sd"]))]
			lane_c[kk] = int(lane_c.get(kk, 0)) + 1
	print("LANES ", lane_c)
	print("JOURNEY top speed by world (km/h): ", vmax_by)
	print("JOURNEY waves done: ", j.wave, "  score ", rig.score, "  crashes ", rig.crashes if "crashes" in rig else -1)
	get_tree().quit()
