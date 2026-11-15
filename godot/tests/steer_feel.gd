extends Node
## How steady is the board under a realistic eye signal? Feeds the run a jittery gaze (new reading 18 times a second, like the tracker) and counts how much the board's direction
## waggles: reversals of the turn (swings of at least 2.5 degrees) per second, how fast the nose swings on average, and the widest angle reached.
##   resting   eyes on the middle, only jitter: the board should hold its line
##   glances   a look left / middle / right every 2.5 s plus jitter: the board should carve over once per look, not whip


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
	for sc in [["resting", 0.03], ["resting", 0.07], ["glances", 0.03], ["glances", 0.07]]:
		_run(rig, String(sc[0]), float(sc[1]))
	get_tree().quit()


func _run(rig: RunRig, kind: String, jitter: float) -> void:
	rig._restart()
	rig._warmed = true
	rig._warming = false
	rig.ghost = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dt := 1.0 / 60.0
	var g := 0.5
	var hs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	var xs := PackedFloat32Array()
	for i in 60 * 45:
		var t := float(i) * dt
		if i % 3 == 0:                                  # ~20 readings a second, held in between
			var tgt := 0.5
			if kind == "glances":
				tgt = [0.5, 0.28, 0.5, 0.72][int(t / 2.5) % 4]
			g = clampf(tgt + rng.randfn(0.0, jitter), 0.0, 1.0)
		GazeProvider.set_scripted(Vector2(g, 0.45))
		rig._physics_process(dt)
		rig._process(dt)
		if t > 5.0:
			hs.append(rig.heading)
			vs.append(rig._vis_heading)
			xs.append(rig.spos.x)
	print("FEEL  %-8s jitter %2d%%   physics: %s   seen: %s" % [kind, int(jitter * 100.0), _wag(hs, dt), _wag(vs, dt)])


func _wag(h: PackedFloat32Array, dt: float) -> String:
	var rev := 0
	var last_ext := h[0]
	var dir := 0
	var rate := 0.0
	var peak := 0.0
	for i in range(1, h.size()):
		var d := h[i] - h[i - 1]
		rate += absf(d) / dt
		peak = maxf(peak, absf(h[i]))
		var nd := 1 if d > 0.0 else (-1 if d < 0.0 else dir)
		if nd != dir:
			if absf(h[i - 1] - last_ext) >= deg_to_rad(2.5):
				rev += 1
			last_ext = h[i - 1]
			dir = nd
	var rates := PackedFloat32Array()
	var acc := 0.0
	for i in range(2, h.size()):
		rates.append(absf(h[i] - h[i - 1]) / dt)
		var a := (h[i] - 2.0 * h[i - 1] + h[i - 2]) / (dt * dt)
		acc += a * a
	rates.sort()
	var secs := float(h.size()) * dt
	return "%.2f rev/s, fastest swing %3.0f deg/s, snap %4.0f deg/s2, widest %2.0f deg" % [float(rev) / secs, rad_to_deg(rates[int(float(rates.size() - 1) * 0.99)]), rad_to_deg(sqrt(acc / float(h.size()))), rad_to_deg(peak)]
