extends Node
## Where does a game frame's script time go? Runs the real course with the autopilot and times each part per frame (headless: script cost only, no graphics).
var _acc: Dictionary = {}


func _t(name: String, c: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	c.call()
	_acc[name] = int(_acc.get(name, 0)) + Time.get_ticks_usec() - t0


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
	for i in 240:
		rig._physics_process(dt)
	var n := 600
	var t_all := Time.get_ticks_usec()
	for i in n:
		_t("physics_process (everything)", func() -> void: rig._physics_process(dt))
		_t("  update_rows", func() -> void: rig._update_rows())
		_t("  vortex_drive", func() -> void: rig._vortex_drive(dt))
		_t("  chain_tick", func() -> void: rig._chain_tick(dt))
		_t("  ball_evade", func() -> void: rig._ball_evade())
		_t("  collide", func() -> void: rig._collide())
		_t("  update_ramps", func() -> void: rig._update_ramps(dt))
		_t("  update_pads", func() -> void: rig._update_pads())
		_t("  realm_tick", func() -> void: rig._realm_tick(dt))
		_t("  chunk_pump", func() -> void: rig._chunk_pump())
		_t("  update_ribbons", func() -> void: rig._update_ribbons())
		_t("  update_aim", func() -> void: rig._update_aim(dt))
		_t("  update_buff_aim", func() -> void: rig._update_buff_aim(dt))
		_t("  update_crumbs", func() -> void: rig._update_crumbs(dt))
		_t("  animate_buffs", func() -> void: rig._animate_buffs())
		_t("  process (camera etc.)", func() -> void: rig._process(dt))
		_t("  draw_hud", func() -> void: rig._draw_hud_inner())
	var total := float(Time.get_ticks_usec() - t_all) / 1000.0
	print("CPU  %d frames, %.1f ms per frame in total for everything below (headless script cost)" % [n, total / float(n)])
	var keys := _acc.keys()
	keys.sort_custom(func(a, b): return int(_acc[a]) > int(_acc[b]))
	for k in keys:
		print("CPU    %-34s %7.2f ms per frame" % [k, float(_acc[k]) / 1000.0 / float(n)])
	get_tree().quit()
