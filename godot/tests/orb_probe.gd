extends Node
## The linked set piece, measured: ride until a spring-tube-rail chain stands ahead, put the board down 40 m before the spring in its lane, eyes ahead, and watch it:
## does the spring take it, does the tube deliver it onto the rail, does the rail run to its end, what is the payoff and how fast does it come out. BEND=1 for the winding trail.


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
	var sides := [0.0, -0.8, 0.0, 0.8]
	for step in 60 * 150:
		if step % 90 == 0:
			rig.pick_override = sides[(step / 90) % 4]          # a look that moves: middle, left, middle, right
		rig._physics_process(dt)
		rig._process(dt)
	print("ORBS built %d, collected %d (%.0f%%) | chains %d | score %d" % [rig.gz_seen, rig.gz_got, 100.0 * float(rig.gz_got) / maxf(float(rig.gz_seen), 1.0), rig.lk_done, rig.score])
	get_tree().quit()
