extends Node
## godot --path . res://tests/shots_trance.tscn -- <out dir>
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	level.load_level(9)
	var rig: TranceRig = level._tr
	TrackerBridge.force_mouse_mode = true
	rig.loop.intensity = 0.8
	var vs := get_viewport().get_visible_rect().size
	TrackerBridge.debug_gaze = rig.cam.unproject_position(rig.orbs[3].global_position) / vs
	for k in 240:
		await get_tree().physics_frame
	for mode in range(7):
		rig.loop.fx_mode = mode
		for k in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/trfx_%d_%s.png" % [out, mode, String(DopamineLoop.FX_NAMES[mode]).to_lower().replace(" ", "_")])
	print("trance fx shots: charge=%.2f" % rig.loop.charge)
	get_tree().quit()
