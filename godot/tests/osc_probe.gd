extends Node
## Dev probe: does the board rock side to side?  Counts reversals of the sideways velocity per 100 m with the help at different strengths.
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
	for lvl in [0.0, 0.7, 1.0]:
		for mode in ["hands off", "eyes on gates", "delayed+noisy"]:
			rig.assist_level = lvl
			rig._restart()
			rig.vel = Vector2(0.0, -16.0)
			var rev := 0
			var last := 0.0
			var amp := 0.0
			var n := 0
			var st := 0
			var q: Array = []
			var nr := RandomNumberGenerator.new()
			nr.seed = 9
			while rig.spos.z > -1200.0 and st < 9000:
				st += 1
				if mode != "hands off":
					# a person looking at the safe gate of the next barrier
					var best: Dictionary = {}
					var bz := -1.0e9
					for j in rig._rows:
						var r: Dictionary = rig._rows[j]
						if r["has_row"] and float(r["z"]) < rig.spos.z - 4.0 and float(r["z"]) > bz:
							bz = float(r["z"])
							best = r
					if not best.is_empty():
						var gx := 0.0
						for g in best["gaps"]:
							if g["good"]:
								gx = float(g["x"])
						var want_g := clampf((gx - rig.spos.x) / 30.0, -1.0, 1.0)
						if mode == "delayed+noisy":
							q.append(want_g + nr.randfn(0.0, 0.12))
							if q.size() > 21:
								q.pop_front()                              # about 0.35 s behind what the board is doing
							want_g = float(q[0])
						rig._steer_gaze = want_g
				rig._physics_process(dt)
				var vx := rig.vel.x
				if absf(vx) > 1.0 and last != 0.0 and signf(vx) != signf(last):
					rev += 1
				if absf(vx) > 1.0:
					last = vx
				amp += absf(rig.steer)
				n += 1
			print("assist %.1f  %-14s  %.0f m  sideways reversals %d (%.1f per 100 m)  mean |steer| %.2f  crashes %d" % [lvl, mode, -rig.spos.z, rev, float(rev) / maxf(-rig.spos.z / 100.0, 1.0), amp / float(maxi(n, 1)), rig.crashes])
	get_tree().quit()
