extends Node
## Dev probe: renders the Downhill menu in each theme and saves screenshots to the user dir.  godot --path . res://tests/menu_probe.tscn
func _ready() -> void:
	Game.touch_mode = false
	var ui := CanvasLayer.new()
	add_child(ui)
	var m := DownhillMenu.new()
	ui.add_child(m)
	get_window().size = Vector2i(OS.get_environment("PW").to_int() if OS.get_environment("PW") != "" else 1280, OS.get_environment("PH").to_int() if OS.get_environment("PH") != "" else 720)
	for id in Themes.ORDER:
		m._pick_theme(id)
		for i in 150:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := OS.get_environment("OUT") + "/menu_%s.png" % id
		img.save_png(path)
		m._bg.vp.get_texture().get_image().save_png(OS.get_environment("OUT") + "/vp_%s.png" % id)
		print("saved ", path, " ", img.get_size(), " shown size ", m._bg.shown.size, " vis ", m._bg.shown.is_visible_in_tree(), " bg size ", m._bg.size, " mode ", m._bg.post.mode, " tex ", m._bg.shown.texture)
	get_tree().quit()
