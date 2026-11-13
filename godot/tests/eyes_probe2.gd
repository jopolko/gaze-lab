extends Node
## Dev probe: a model of a person whose eyes are in the loop, driving the REAL eyes-only path. For each barrier they look at the gate farthest from straight ahead.
## Which gate does the board actually take?
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
	Game.touch_mode = true
	level.load_level(11)
	await _frames(5)
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.balls_enabled = false
	var dt := 1.0 / 60.0
	var vs := Vector2(1280.0, 720.0)
	for variant in ["help 0.7", "help 0.0", "help 1.0"]:
		rig._restart()
		rig.vel = Vector2(0.0, -16.0)
		rig.eyes_only = true
		GazeProvider.eih_ok = true
		GazeProvider.direct_ok = true
		GazeProvider.direct = Vector2(0.5, 0.5)
		GazeProvider.backend = GazeProvider.Backend.CAMERA
		GazeProvider.active = true
		rig.assist_level = float(variant.split(" ")[1])
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var look := 0.0
		var t := 0.0
		var targeted := 0
		var took_target := 0
		var took_straight := 0
		var seen_rows := {}
		var tgt_of := {}
		for i in 5400:
			t += dt
			var row: Dictionary = {}
			var bz := -1.0e9
			for j in rig._rows:
				var r: Dictionary = rig._rows[j]
				if r["has_row"] and float(r["z"]) < rig.spos.z - 12.0 and float(r["z"]) > bz:
					bz = float(r["z"])
					row = r
			if not row.is_empty() and t > 12.0:
				var rj := int(row["j"])
				if not tgt_of.has(rj):
					var far_g: Dictionary = {}
					var far_d := -1.0
					for g in row["gaps"]:
						var dd := absf(float(g["x"]) - rig.spos.x)
						if dd > far_d:
							far_d = dd
							far_g = g
					tgt_of[rj] = far_g
				var tg: Dictionary = tgt_of[rj]
				var sp := rig.cam.unproject_position(Vector3(float(tg["x"]), rig.terrain_h(float(tg["x"]), bz) + 2.0, bz))
				var err := sp.x / vs.x - rig._gx
				look = clampf(look + err * 0.12, -0.06, 0.06)
			elif t <= 12.0:
				look = 0.03 * sin(t * 1.1)                       # learn the glance size first
			else:
				look *= 0.95
			GazeProvider._last_packet_msec = Time.get_ticks_msec()
			GazeProvider.confidence = 1.0
			GazeProvider.eih = Vector2(-look + rng.randfn(0.0, 0.004), 0.5)
			rig._update_focus(dt)
			rig._physics_process(dt)
			rig.crashes = 0
			# bookkeeping when a barrier is passed
			for j2 in rig._rows:
				var r2: Dictionary = rig._rows[j2]
				if r2["passed"] and not seen_rows.has(int(r2["j"])) and tgt_of.has(int(r2["j"])):
					seen_rows[int(r2["j"])] = true
					targeted += 1
					var tg2: Dictionary = tgt_of[int(r2["j"])]
					if absf(rig.spos.x - float(tg2["x"])) <= float(tg2["w"]) * 0.5 + 6.0:
						took_target += 1
		print("%-10s  looked at the far gate of %d barriers, the board took it %d times (%.0f%%)   gates by eyes %d, by board %d, wrong %d   engage mean %.2f" % [variant, targeted, took_target, 100.0 * float(took_target) / float(maxi(targeted, 1)), rig.ag["eyes"], rig.ag["auto"], rig.ag["wrong"], rig.agency_summary()["engageMean"]])
	get_tree().quit()
