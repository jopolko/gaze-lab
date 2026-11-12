extends Node
## Closed-loop tuning of the continuous gaze steering: godot --headless --path . res://tests/steer_sweep.tscn
## A scripted driver looks at the gate of the lane it wants (gaze noise included) and we measure how well the board follows.
var _lv: MainLevel

func _gate_x(rig: DownhillRig, lane: int, vs: Vector2) -> float:
	var row: Dictionary = rig._gate_row if not rig._gate_row.is_empty() else rig._target_row
	if row.is_empty():
		return 0.5
	for g in row["gaps"]:
		if int(g["lane"]) == lane:
			var sc := rig._gap_screen(row, g)
			if not sc.is_empty():
				return float((sc["c"] as Vector2).x) / vs.x
	return 0.5

func _run(curve: float, rate: float, smin: float, noise: float, rng: RandomNumberGenerator) -> Dictionary:
	_lv.load_level(8)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rig: DownhillRig = _lv._dh
	rig.lane_ctl = 2
	rig.steer_curve = curve
	rig.steer_rate = rate
	rig.steer_scale_const = smin
	rig.steer_scale_min = 0.05
	var vs := get_viewport().get_visible_rect().size
	# 1) hold the gaze on the middle: how much does the noise move the steering? (jitter)
	var t0 := rig._age
	var s_sum := 0.0
	var s_n := 0
	while rig._age - t0 < 6.0:
		GazeProvider.set_scripted(Vector2(clampf(0.5 + rng.randfn(0.0, noise), 0.0, 1.0), 0.45))
		await get_tree().physics_frame
		await get_tree().process_frame
		if rig._age - t0 > 3.0:
			s_sum += rig._steer_gaze * rig._steer_gaze
			s_n += 1
	var jitter := sqrt(s_sum / maxf(float(s_n), 1.0))
	# 2) look at the gate of the right lane, then the left lane: time to cross 80%, overshoot, final error
	var res := {"jitter": jitter}
	for leg in 2:
		var lane := 2 if leg == 0 else 0
		var x_goal := float(DownhillRig.LANE_X[lane])
		var x0 := rig.spos.x
		var t1 := rig._age
		var rise := -1.0
		var over := 0.0
		while rig._age - t1 < 7.0:
			GazeProvider.set_scripted(Vector2(clampf(_gate_x(rig, lane, vs) + rng.randfn(0.0, noise), 0.0, 1.0), 0.45))
			await get_tree().physics_frame
			await get_tree().process_frame
			var frac := (rig.spos.x - x0) / (x_goal - x0)
			if rise < 0.0 and frac >= 0.8:
				rise = rig._age - t1
			over = maxf(over, (rig.spos.x - x_goal) * signf(x_goal - x0) * -1.0 * -1.0)
		res["rise%d" % leg] = rise
		res["end%d" % leg] = absf(rig.spos.x - x_goal)
		res["crash"] = rig.crashes
	return res

func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	_lv = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_lv)
	await get_tree().process_frame
	await get_tree().process_frame
	_lv.director.autostart = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for noise in [0.015, 0.03]:
		for curve in [1.0]:
			for rate in [9.0]:
				for smin in [0.08]:
					var r: Dictionary = await _run(curve, rate, smin, noise, rng)
					print("noise=%.3f curve=%.1f rate=%4.1f smin=%.2f | jitter=%.3f rise->right=%.2fs rise->left=%.2fs endErr=%.1f/%.1f m crashes=%d" % [noise, curve, rate, smin, r["jitter"], r["rise0"], r["rise1"], r["end0"], r["end1"], r["crash"]])
	get_tree().quit()
