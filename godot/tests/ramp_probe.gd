extends Node
## Trail ramp: ride the first jump from 80 m up the slope, centred, and report the flight. Sweeps rise / length / power / blast.
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
	rig._restart()
	var dt := 1.0 / 60.0
	var k: Dictionary = {}
	for i in 60 * 120:
		GazeProvider.set_scripted(Vector2(0.5, 0.45))
		rig._physics_process(dt)
		for kk in rig._kickers:
			if kk.get("trail", false) and float(kk["z"]) < rig.spos.z - 120.0:
				k = kk
				break
		if not k.is_empty():
			break
	print("kicker z %.0f x %.1f len %.0f rise %.1f pow %.1f" % [k["z"], k["x"], k["len"], k["rise"], k["pw"]])
	var configs := [[34.0, 8.5, 2.0, 3.0], [34.0, 11.0, 2.0, 3.0], [34.0, 14.0, 2.0, 3.0], [40.0, 14.0, 2.0, 3.0], [40.0, 16.0, 2.2, 4.0], [36.0, 12.0, 1.7, 4.0]]
	if OS.get_environment("CFG") != "":
		var p := OS.get_environment("CFG").split(",")
		configs = [[float(p[0]), float(p[1]), float(p[2]), float(p[3])]]
	for cfg in configs:
		k["len"] = cfg[0]
		k["rise"] = cfg[1]
		k["pw"] = cfg[2]
		rig.jump_blast = cfg[3]
		var kx: float = k["x"]
		var kz: float = k["z"]
		var lipz: float = kz - float(k["len"])
		rig.spos = Vector3(kx, rig.terrain_h(kx, kz + 80.0), kz + 80.0)
		rig._gh_prev = rig.spos.y
		rig.vel = Vector2(0.0, -24.0)
		rig.vy = -24.0 * 0.3
		rig.heading = 0.0
		rig.hurt_t = 0.0
		rig.grounded = true
		rig._finished = false
		rig._line_pick = {}
		var c0 := rig.crashes
		var air_t := 0.0
		var peak := 0.0
		var vmax := 0.0
		var vlip := 0.0
		var was_air := false
		var d0 := 0.0
		var d1 := 0.0
		var pks := {}
		for i in 60 * 14:
			GazeProvider.set_scripted(Vector2(0.5, 0.45))
			if rig.spos.z > lipz:
				rig.spos.x = kx
				rig.vel.x = 0.0
			rig._physics_process(dt)
			vmax = maxf(vmax, rig.vel.length())
			if not was_air and not rig.grounded and rig.spos.z < lipz + 8.0:
				was_air = true
				d0 = rig.spos.z
				vlip = rig.vel.length()
			if was_air:
				if not rig.grounded:
					air_t += dt
					peak = maxf(peak, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
				else:
					d1 = rig.spos.z
					break
		print("len %.0f rise %.0f pow %.1f blast %.0f: speed at lip %.0f m/s (max %.0f), air %.2f s, peak %.1f m, flew %.0f m, off-centre %.1f m, crashes %d" % [cfg[0], cfg[1], cfg[2], cfg[3], vlip, vmax, air_t, peak, d0 - d1, rig.spos.x - kx, rig.crashes - c0])
		rig.hurt_t = 0.0
	get_tree().quit()
