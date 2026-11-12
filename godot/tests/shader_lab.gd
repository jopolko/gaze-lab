extends Node
## Dev probe: the ground and the sky of one theme, straight on.  THEME=psychedelic OUT=dir godot --path . res://tests/shader_lab.tscn
func _ready() -> void:
	var id := OS.get_environment("THEME")
	var ui := CanvasLayer.new()
	add_child(ui)
	var bd := ThemeBackdrop.new()
	ui.add_child(bd)
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	bd.set_process(false)
	bd.choose_theme(id)
	var shots := {"ground": [Vector3(0, 60, -60), Vector3(0, 0, -100)], "horizon": [Vector3(0, 8, -60), Vector3(0, 12, -200)], "sky": [Vector3(0, 8, -60), Vector3(0, 90, -200)]}
	for k in shots:
		bd.cam.position = shots[k][0]
		bd.cam.look_at(shots[k][1], Vector3.UP)
		for i in 120:
			await get_tree().process_frame
		bd.vp.get_texture().get_image().save_png(OS.get_environment("OUT") + "/lab_%s_%s.png" % [id, k])
	get_tree().quit()
