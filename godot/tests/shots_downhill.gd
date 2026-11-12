extends Node
## Windowed screenshots of Downhill: godot --path . res://tests/shots_downhill.tscn -- <out dir>
func _ready() -> void:
	var out := "."
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(8)
	var rig: DownhillRig = level._dh
	GazeProvider.nod_debug = Vector2.ZERO
	rig._tune_open = true
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for k in 150:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/dh_cruise.png" % out)
	# look at the nearest unresolved opening ahead
	var best: Dictionary = {}
	var best_z := -1.0e9
	for k in rig._rows:
		var r: Dictionary = rig._rows[k]
		if r["has_row"] and float(r["z"]) < rig.spos.z - 60.0 and float(r["z"]) > best_z:
			best_z = float(r["z"])
			best = r
	var vs := get_viewport().get_visible_rect().size
	for g in best["gaps"]:
		var s := rig._gap_screen(best, g)
		if not s.is_empty():
			GazeProvider.set_scripted(s["c"] / vs)
			for k in 30:
				await get_tree().physics_frame
				await get_tree().process_frame
			break
	get_viewport().get_texture().get_image().save_png("%s/dh_look.png" % out)
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	rig._kickers.append({"x": rig.spos.x, "z": rig.spos.z - 30.0, "len": 14.0, "w": 14.0, "rise": 2.0})
	for k in 70:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/dh_jump.png" % out)
	print("sun shadow=%s rot=%s energy=%.2f maxdist=%.0f tonemap=%d exposure=%.2f ambient=%.2f" % [str(level.sun.shadow_enabled), str(level.sun.rotation_degrees), level.sun.light_energy, level.sun.directional_shadow_max_distance, level.world_env.environment.tonemap_mode, level.world_env.environment.tonemap_exposure, level.world_env.environment.ambient_light_energy])
	print("downhill shots: speed=%.1f rows=%d crashes=%d air=%s" % [rig.vel.length(), rig.rows_passed, rig.crashes, str(not rig.grounded)])
	get_tree().quit()
