extends Node
## Checks the called-gate test end to end without a camera: a scripted look that goes to the marked opening (with jitter) must be scored as mostly right.


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
	for jit in [0.03, 0.09]:
		for mode in [false, true]:
			await _ride(rig, mode, jit)
	get_tree().quit()


func _ride(rig: RunRig, with_markers: bool, jitter: float) -> void:
	rig._restart()
	rig.called_mode = true
	rig.called_res = []
	rig._call_row = {}
	rig.beacons = with_markers
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dt := 1.0 / 60.0
	var g := 0.5
	var vs := get_viewport().get_visible_rect().size
	var all_rows: Array = []
	for i in 60 * 90:
		if i % 3 == 0:
			var tgt := 0.5
			if not rig._call_row.is_empty() and rig._call_row.has("call"):
				var sc := rig._gap_screen(rig._call_row, rig._call_row["call"])
				if not sc.is_empty():
					tgt = (sc["c"] as Vector2).x / vs.x
				var ci := (rig._call_row["gaps"] as Array).find(rig._call_row["call"])
				if with_markers and is_same(rig._bc_row, rig._call_row) and ci >= 0 and ci < rig._bc_xs.size():
					tgt = float(rig._bc_xs[ci]) / vs.x
			g = clampf(tgt + rng.randfn(0.0, jitter), 0.0, 1.0)
		GazeProvider.set_scripted(Vector2(g, 0.45))
		rig._physics_process(dt)
		rig._process(dt)
		if rig._call_rows.size() >= 19:
			all_rows.append_array(rig._call_rows)
			rig._call_rows = []
	all_rows.append_array(rig._call_rows)
	var okn := 0
	var thr := 0
	for r in rig.called_res:
		if int(r["eyes"]) == int(r["call"]):
			okn += 1
		if int(r["through"]) == int(r["call"]):
			thr += 1
	print("CALLED  jitter %d%% markers %s: %d barriers, held the marked one at the barrier: %d, went through it: %d, crashes %d" % [int(jitter * 100.0), "ON " if with_markers else "off", rig.called_res.size(), okn, thr, rig.crashes])
	var f := FileAccess.open("res://tests/called_probe_%s_%d.jsonl" % ["on" if with_markers else "off", int(jitter * 100.0)], FileAccess.WRITE)
	for r in rig.called_res:
		f.store_line(JSON.stringify(r))
	f.store_line(JSON.stringify({"kind": "called", "rows": all_rows}))
	f.close()
