class_name HitNotifierUI
extends Control
## Full-screen overlay that spawns animated comic-book words ("YEET!", "BONK!",
## "SLIP!") at the screen position of a world-space hit. Subscribes to
## Game.popup_requested, so any gameplay code can fire one with Game.popup().

@export var font_size: int = 54
@export var lifetime: float = 0.9
@export var rise_pixels: float = 110.0
@export var max_labels: int = 28

var _active: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.popup_requested.connect(spawn_popup)


func spawn_popup(text: String, world_pos: Vector3, color: Color = Color.WHITE, size_scale: float = 1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos) or _active >= max_labels:
		return
	var screen := cam.unproject_position(world_pos)

	var settings := LabelSettings.new()
	settings.font_size = int(font_size * size_scale)
	settings.font_color = color
	settings.outline_size = 12
	settings.outline_color = Color.BLACK
	settings.shadow_size = 4
	settings.shadow_color = Color(0, 0, 0, 0.5)

	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.size = label.get_minimum_size()
	label.pivot_offset = label.size * 0.5
	label.position = screen - label.size * 0.5 + Vector2(randf_range(-30.0, 30.0), randf_range(-10.0, 10.0))
	label.rotation = deg_to_rad(randf_range(-12.0, 12.0))
	label.scale = Vector2.ZERO
	_active += 1

	var start_y := label.position.y
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "scale", Vector2(1.35, 1.35), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.1).set_delay(0.12)
	tw.tween_property(label, "position:y", start_y - rise_pixels, lifetime) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, lifetime * 0.4).set_delay(lifetime * 0.6)
	tw.finished.connect(func() -> void:
		_active -= 1
		label.queue_free())
