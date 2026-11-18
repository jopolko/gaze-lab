extends Node
## Is the path ever hidden? Ride the course on a simulated rider, and every few frames look from the rider's eye to points down the middle of the trail 40 to 220 m ahead; walk each line
## across the ground (in the world, so a bend is judged as it is seen) and count it blocked if the ground stands above the line anywhere along it. Prints how often, and the worst place.
## BEND=1 for the winding trail, SEED=n for the course.


var THR := float(OS.get_environment("THR")) if OS.get_environment("THR") != "" else 0.25


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
	var mins := float(OS.get_environment("MINS")) if OS.get_environment("MINS") != "" else 4.0
	var steps := int(mins * 60.0 * 60.0)
	var checked := 0
	var blocked := 0
	var frames_with_block := 0
	var frames := 0
	var lift_sum := 0.0
	var lift_hi := 0
	var worst := 0.0
	var worst_at := ""
	var by_dist := {}
	for step in steps:
		rig._physics_process(dt)
		rig._process(dt)
		if step % 12 != 0 or step < 120:
			continue
		frames += 1
		lift_sum += rig._crest_lift
		lift_hi += 1 if rig._crest_lift > 2.0 else 0
		var eye_s := Vector3(rig.spos.x, rig.spos.y + 1.7 + rig._crest_lift, rig.spos.z + 0.5)
		var eye_w := TrailCurve.w(eye_s)
		var any := false
		for d in [40.0, 80.0, 120.0, 160.0, 200.0, 240.0]:
			var tz: float = rig.spos.z - d
			var tx: float = rig.trail_x(tz)
			var tp := Vector3(tx, rig.terrain_h(tx, tz) + 0.3, tz)
			var tw := TrailCurve.w(tp)
			var over := 0.0
			var n := int(d / 3.0)
			for si in range(1, n):
				var u := float(si) / float(n)
				var pw := eye_w.lerp(tw, u)
				var ps := TrailCurve.strip_near(pw, rig.spos.z - d - 30.0, rig.spos.z + 10.0)
				var gh := rig.terrain_h(ps.x, ps.z)
				over = maxf(over, gh - pw.y)
			checked += 1
			by_dist[d] = int(by_dist.get(d, 0)) + (1 if over > THR else 0)
			if over > THR:
				blocked += 1
				any = true
				if over > worst:
					worst = over
					worst_at = "z %d, %d m ahead, ground %.1f m above the line, board %.0f km/h, %.1f m up" % [int(rig.spos.z), int(d), over, -rig.vel.y * 3.6, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z)]
		if any:
			frames_with_block += 1
	print("SIGHT %s: %d looks, path hidden in %.1f%% of them; in %.1f%% of the frames something along the path was hidden" % ["winding" if rig.bend else "straight", checked, 100.0 * float(blocked) / maxf(float(checked), 1.0), 100.0 * float(frames_with_block) / maxf(float(frames), 1.0)])
	print("SIGHT by distance (hidden counts out of %d frames): %s" % [frames, str(by_dist)])
	print("LIFT mean %.2f m, over 2 m in %.0f%% of frames" % [lift_sum / maxf(float(frames), 1.0), 100.0 * float(lift_hi) / maxf(float(frames), 1.0)])
	print("SIGHT worst: %s" % worst_at)
	get_tree().quit()
