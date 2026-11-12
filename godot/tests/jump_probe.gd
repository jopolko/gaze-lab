extends Node
## Dev probe: how long is a flight off a kicker of a given rise, at a given speed?  godot --headless --path . res://tests/jump_probe.tscn
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
	rig.view_fp = false
	rig.set_physics_process(false)
	rig._restart()
	for j in range(rig._next_j, 30):
		rig._gen_segment(j)
	var kk: Dictionary = {}
	var kdict: Dictionary = {}
	for jj in rig._rows:
		if rig._rows[jj].has("kick"):
			kk = rig._rows[jj]["kick"]
			break
	for k in rig._kickers:
		if absf(float(k["z"]) - float(kk["z"])) < 0.01:
			kdict = k
	rig.gate_assist = false
	rig.avoid_enabled = false
	var dt := 1.0 / 60.0
	for spd in [36.0, 50.0]:
		for rise in [0.4, 0.7, 1.0, 1.4, 1.8, 2.4]:
			kdict["rise"] = rise
			var kx: float = kk["x"]
			var kz: float = kk["z"]
			rig.spos = Vector3(kx, rig.terrain_h(kx, kz + 30.0), kz + 30.0)
			rig._gh_prev = rig.spos.y
			rig.vel = Vector2(0.0, -spd)
			rig.heading = 0.0
			rig.hurt_t = 0.0
			rig.grounded = true
			rig._finished = false
			var c0 := rig.crashes
			var air_t := 0.0
			var peak := 0.0
			var d0 := 0.0
			var d1 := 0.0
			var was_air := false
			for i in 400:
				rig._physics_process(dt)
				if not rig.grounded and rig.spos.z < float(kk["lip"]) + 6.0:
					if not was_air:
						d0 = rig.spos.z
					was_air = true
					air_t += dt
					peak = maxf(peak, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
				elif was_air and rig.grounded:
					d1 = rig.spos.z
					break
			print("speed %.0f rise %.1f: air %.2f s, peak %.1f m, flew %.0f m, crashes %d %s" % [spd, rise, air_t, peak, d0 - d1, rig.crashes - c0, str(rig.crash_log.slice(maxi(rig.crash_log.size() - 1, 0)))])
			rig.hurt_t = 0.0
	get_tree().quit()
