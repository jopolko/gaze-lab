extends Node
## Windowed screenshots of three-lane Downhill: godot --path . res://tests/shots_lanes.tscn -- <out dir>
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
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	for k in 240:
		await get_tree().physics_frame
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/lanes_centre.png" % out)
	var vs := get_viewport().get_visible_rect().size
	for kk in rig._rows:
		var rr: Dictionary = rig._rows[kk]
		print("ROW ", kk, " z=", rr["z"], " has=", rr["has_row"], " fl=", rr.get("fl", "none"))
	GazeProvider.set_scripted(Vector2(0.85, 0.45))
	for k in 140:
		await get_tree().physics_frame
		await get_tree().process_frame
		if k % 10 == 0:
			print("t=%d z=%.0f x=%.1f vx=%.1f v=%.1f steer=%.2f head=%.2f lane=%d eye=%s grace=%.1f lockx=%s" % [k, rig.spos.z, rig.spos.x, rig.vel.x, rig.vel.length(), rig.steer, rig.heading, rig._lane, str(rig._eye_on), rig._grace_t, str(rig._lock.get("x", "-"))])
	get_viewport().get_texture().get_image().save_png("%s/lanes_right.png" % out)
	rig._paused = true
	for k in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/lanes_pause.png" % out)
	for cl in rig.crash_log:
		print("CRASH ", cl)
	print("lane=%d coins=%d rows=%d crashes=%d speed=%.1f x=%.1f size=%s" % [rig._lane, rig.coins_got, rig.rows_passed, rig.crashes, rig.vel.length(), rig.spos.x, str(vs)])
	get_tree().quit()
