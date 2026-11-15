extends Node
## The flow meter and the eyebrow pop on an autopilot ride: pops every 2.5 s for the first half, then nothing, so the meter must rise, hold, and drain.


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
	rig._restart()
	rig.autopilot = true
	var dt := 1.0 / 60.0
	var peak := 0
	var air_pop := 0.0
	var high_pop := 0.0
	var line := ""
	for i in 60 * 60:
		var t := float(i) * dt
		rig.brow_override = t < 30.0 and fmod(t, 2.5) < 0.15
		var before := rig.pops_flat
		rig._physics_process(dt)
		if rig.pops_flat != before:
			air_pop = 0.0
		if not rig.grounded:
			air_pop += dt
			high_pop = maxf(high_pop, rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z))
		peak = maxi(peak, rig.chain)
		if i % 300 == 0:
			line += "%ds:x%.1f " % [int(t), rig.groove]
	print("FLOW  pops %d, highest level %d, levels lost to the clock %d, crashes %d, barriers %d, score %d, highest off the snow %.1f m" % [rig.pops_flat, peak, rig.flow_drops, rig.crashes, rig.rows_passed, rig.score, high_pop])
	print("FLOW  multiplier over time: ", line)
	get_tree().quit()
