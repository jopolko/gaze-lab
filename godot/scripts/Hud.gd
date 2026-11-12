class_name Hud
extends Control
## Crosshair, health/XP bars, wave + boss info, power-up timers, combo style,
## coins, big banners and a red damage flash. Everything drawn/built in code.

var _weapon_label: Label
var _chaos_label: Label
var _level_label: Label
var _wave_label: Label
var _style_label: Label
var _powerup_label: Label
var _hp_label: Label
var _banner: Label
var _boss_label: Label
var _hint: Label
var _flash: ColorRect
var _banner_tween: Tween
var _player: PlayerController
var _director: WaveDirector
var _boss_hp: float = 0.0
var _boss_max: float = 1.0
var _level_name: String = ""
var _hf_shown: bool = false
var _touch_shown: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_level_label = _make_label("", 24)
	_level_label.position = Vector2(20, 12)
	_chaos_label = _make_label("", 22)
	_chaos_label.position = Vector2(20, 44)

	_wave_label = _make_label("", 28)
	_wave_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_boss_label = _make_label("", 22)
	_boss_label.position = Vector2(0, 52)
	_boss_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 52)
	_boss_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_style_label = _make_label("", 34)
	_style_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_style_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_style_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_powerup_label = _make_label("", 22)
	_powerup_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_powerup_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_hp_label = _make_label("", 20)
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 54)
	_hp_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hp_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_weapon_label = _make_label("", 28)
	_weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_weapon_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_hint = _make_label("", 14)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_set_hint(Game.using_gamepad)
	Game.pad_changed.connect(_set_hint)

	_banner = _make_label("", 64)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_banner.position.y -= 140.0

	Game.banner_requested.connect(_show_banner)
	Game.player_hurt.connect(_on_hurt)
	Game.boss_changed.connect(func(n: String, hp: float, mx: float) -> void:
		_boss_hp = hp
		_boss_max = mx
		_boss_label.text = n if hp > 0.0 else "")
	_bind.call_deferred()


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_director = get_tree().get_first_node_in_group("director") as WaveDirector
	var wm := get_tree().get_first_node_in_group("weapon_manager") as WeaponManager
	if wm != null:
		wm.weapon_changed.connect(func(w: WeaponBase) -> void: _weapon_label.text = w.display_name if w else "")
		_weapon_label.text = wm.current_weapon().display_name if wm.current_weapon() else ""


func set_level_name(n: String) -> void:
	_level_name = n


func _set_hint(pad: bool) -> void:
	if Game.demo_mode:
		_hint.text = ""
		return
	if Game.touch_mode:
		_hint.text = "Left thumb: move  |  right thumb: look  |  EYES button: hands-free mode"
		return
	_hint.text = ("L-stick move | R-stick look | A jump | B slide | X kick | RT fire | LT drop | LB/RB weapons | Back: skills" if pad
		else "WASD move | Shift sprint | Space jump | Ctrl slide | F kick | LMB fire | RMB alt-fire | 1-4 guns | Q swap | Tab skills | F9 HANDS-FREE mode")


func _show_banner(text: String, color: Color, seconds: float) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.pivot_offset = _banner.size * 0.5
	if _banner_tween:
		_banner_tween.kill()
	_banner.scale = Vector2(0.5, 0.5)
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(maxf(seconds - 0.7, 0.2))
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.45)


func _on_hurt(_amount: float) -> void:
	_flash.color.a = 0.38
	create_tween().tween_property(_flash, "color:a", 0.0, 0.45)


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if Game.touch_mode != _touch_shown:
		_touch_shown = Game.touch_mode
		if not GazeProvider.active:
			_set_hint(Game.using_gamepad)
	if GazeProvider.active != _hf_shown:
		_hf_shown = GazeProvider.active
		if _hf_shown and not Game.demo_mode:
			_hint.text = "HANDS-FREE: eyes aim | stare = LOCK x3 | blink (B) = FIRE | wink (Z) = SWAP GUN | lean / floor look = move | F9 exit"
		else:
			_set_hint(Game.using_gamepad)
	_level_label.text = "LV %d   %d/%d XP   %d coins%s" % [Prog.level, Prog.xp, Prog.xp_needed(), Prog.coins,
		("   [Tab] +%d SKILL PT" % Prog.skill_points) if Prog.skill_points > 0 else ""]
	_chaos_label.text = "%s   CHAOS %d" % [_level_name, Game.chaos]
	if _director != null:
		_wave_label.text = "WAVE %d   -   %d left" % [_director.wave, _director.remaining()] if _director.active \
			else "WAVE %d  -  next wave soon" % _director.wave
	if _player != null:
		_hp_label.text = "%d / %d" % [int(ceil(_player.health)), int(_player.max_hp())]
	if Prog.combo >= 2:
		_style_label.text = "x%d  %s\n+%d%% XP" % [Prog.combo, Prog.style_name(), int((Prog.combo_mult() - 1.0) * 100.0)]
		_style_label.modulate = Color(1, 1, 1, clampf(Prog.combo_time / 1.0, 0.4, 1.0))
	else:
		_style_label.text = ""
	var lines: PackedStringArray = []
	for id: String in Prog.powerups:
		lines.append("%s  %ds" % [Prog.POWERUPS[id]["name"], int(ceil(float(Prog.powerups[id])))])
	_powerup_label.text = "\n".join(lines)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 3.5, Color.BLACK)
	draw_circle(c, 2.0, Color.WHITE)
	draw_arc(c, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)

	# Health bar (bottom center) + XP bar under it.
	if _player != null:
		var w := 380.0
		var x := size.x * 0.5 - w * 0.5
		var y := size.y - 44.0
		var ratio := clampf(_player.health / _player.max_hp(), 0.0, 1.0)
		draw_rect(Rect2(x - 3, y - 3, w + 6, 24), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(x, y, w * ratio, 18), Color(1.0 - ratio, 0.25 + 0.75 * ratio, 0.2))
		var xr := clampf(float(Prog.xp) / float(Prog.xp_needed()), 0.0, 1.0)
		draw_rect(Rect2(x, y + 24, w, 6), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(x, y + 24, w * xr, 6), Color(1.0, 0.85, 0.2))
	var gt := get_tree().get_first_node_in_group("gaze") as GazeTargeting
	if gt != null:
		gt.draw_overlay(self)
	# Boss bar (top center).
	if _boss_hp > 0.0:
		var bw := 560.0
		var bx := size.x * 0.5 - bw * 0.5
		draw_rect(Rect2(bx - 3, 88, bw + 6, 24), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(bx, 91, bw * clampf(_boss_hp / _boss_max, 0.0, 1.0), 18), Color(1.0, 0.8, 0.15))
