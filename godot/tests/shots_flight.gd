extends Node
## Windowed screenshots of Nod Flight: godot --path . res://tests/shots_flight.tscn -- <out dir>
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
	level.load_level(7)
	var rig: FlightRig = level._rig
	GazeProvider.nod_debug = Vector2.ZERO
	for k in 120:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/flight_cruise.png" % out)
	GazeProvider.nod_debug = Vector2(-0.3, 0.0)         # chin down: gather
	for k in 140:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/flight_gather.png" % out)
	GazeProvider.nod_debug = Vector2(0.05, 2.2)         # snap up: blast
	for k in 4:
		await get_tree().physics_frame
	GazeProvider.nod_debug = Vector2(0.05, 0.0)
	for k in 18:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png("%s/flight_blast.png" % out)
	print("flight shots: speed=%.1f alt=%.1f energy=%.1f groove=%.1f" % [rig.speed, rig.alt, rig.energy, rig.groove])
	get_tree().quit()
