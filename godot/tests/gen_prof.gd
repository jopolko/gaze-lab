extends Node
## Which single frames are slow, and why? Rides the real course on autopilot and lists the slowest frames with the part that took the time
## (headless: script cost only; the browser runs the same script two to three times slower).


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
	rig._restart()
	rig.autopilot = true
	var dt := 1.0 / 60.0
	var slow: Array = []
	var all := PackedFloat32Array()
	for i in 3600:
		var nj := rig._next_j
		var rp := rig.rows_passed
		var got := rig.orbs_got + int(rig.get("buffs_got")) if rig.get("buffs_got") != null else rig.orbs_got
		var jobs := rig._chunk_jobs.size()
		var t0 := Time.get_ticks_usec()
		rig._physics_process(dt)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		all.append(ms)
		var got2 := rig.orbs_got + int(rig.get("buffs_got")) if rig.get("buffs_got") != null else rig.orbs_got
		if ms > 4.0:
			slow.append([ms, i, "built a stretch" if rig._next_j != nj else "", "passed a gate" if rig.rows_passed != rp else "", "picked up" if got2 != got else "", "ground jobs %d" % jobs])
	all.sort()
	print("GEN  frames 3600   median %.2f ms   99th %.2f ms   worst %.2f ms" % [all[1800], all[3564], all[3599]])
	slow.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for s in slow.slice(0, 25):
		print("GEN  %6.1f ms  frame %4d  %s %s %s %s" % s)
	get_tree().quit()
