class_name SkillTreeUI
extends Control
## Pause-menu skill tree + equipped gear. Tab (or Back on a pad) toggles it.
## Mouse click or gamepad focus + A buys a rank. Built entirely in code.

var _buttons: Dictionary = {}
var _points: Label
var _desc: Label
var _gear: RichTextLabel
var _first: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 600)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.14, 0.97)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1.0, 0.85, 0.3)
	sb.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "SKILL TREE"
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 20)
	root.add_child(_points)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	for bi in Prog.BRANCHES.size():
		var b: Dictionary = Prog.BRANCHES[bi]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		var head := Label.new()
		head.text = b["name"]
		head.add_theme_font_size_override("font_size", 26)
		head.add_theme_color_override("font_color", b["color"])
		col.add_child(head)
		var tag := Label.new()
		tag.text = b["tag"]
		tag.add_theme_font_size_override("font_size", 13)
		tag.modulate = Color(1, 1, 1, 0.65)
		col.add_child(tag)
		for s: Dictionary in Prog.SKILLS:
			if int(s["branch"]) != bi:
				continue
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 44)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var id: String = s["id"]
			btn.pressed.connect(func() -> void: _on_buy(id))
			btn.focus_entered.connect(func() -> void: _describe(id))
			btn.mouse_entered.connect(func() -> void: _describe(id))
			col.add_child(btn)
			_buttons[id] = btn
			if _first == null:
				_first = btn

	_desc = Label.new()
	_desc.custom_minimum_size = Vector2(0, 50)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 18)
	root.add_child(_desc)

	_gear = RichTextLabel.new()
	_gear.bbcode_enabled = true
	_gear.fit_content = true
	_gear.custom_minimum_size = Vector2(0, 70)
	root.add_child(_gear)

	var row := HBoxContainer.new()
	root.add_child(row)
	var respec := Button.new()
	respec.text = "Respec (free)"
	respec.pressed.connect(func() -> void: Prog.respec())
	row.add_child(respec)
	var close := Button.new()
	close.text = "Close  [Tab]"
	close.pressed.connect(close_menu)
	row.add_child(close)

	Prog.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"skill_tree"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	if _first != null:
		_first.grab_focus()


func close_menu() -> void:
	visible = false
	get_tree().paused = false
	if not Game.using_gamepad and not GazeProvider.active and not Game.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var wm := get_tree().get_first_node_in_group("weapon_manager") as WeaponManager
	if wm != null:
		wm.block_input(0.25)


func _on_buy(id: String) -> void:
	if Prog.buy(id):
		Game.sfx(&"powerup")
	else:
		_desc.text = Prog.can_buy(id)
		Game.sfx(&"hurt")


func _describe(id: String) -> void:
	var s := Prog.skill_def(id)
	var why := Prog.can_buy(id)
	_desc.text = "%s  (rank %d/%d)\n%s%s" % [s["name"], int(Prog.ranks.get(id, 0)), int(s["max"]), s["desc"],
		("   [%s]" % why) if why != "" else "   [Click / A to buy]"]


func _refresh() -> void:
	if _points == null:
		return
	_points.text = "Level %d    Skill points: %d    Coins: %d    Best wave: %d" % [Prog.level, Prog.skill_points, Prog.coins, Prog.best_wave]
	for id: String in _buttons:
		var s := Prog.skill_def(id)
		var rank := int(Prog.ranks.get(id, 0))
		var btn: Button = _buttons[id]
		btn.text = "%s   %d/%d" % [s["name"], rank, int(s["max"])]
		var locked := Prog.can_buy(id) != "" and rank == 0
		btn.modulate = Color(1, 1, 1, 0.5) if locked else (Color(0.6, 1.0, 0.6) if rank >= int(s["max"]) else Color.WHITE)
	var t := "[b]GEAR[/b]   "
	for slot in ["Hat", "Boots", "Gloves"]:
		if Prog.gear.has(slot):
			var item: Dictionary = Prog.gear[slot]
			var c: Color = Loot.rarity_color(int(item["rarity"]))
			t += "[color=#%s]%s[/color]  (%s)   " % [c.to_html(false), item["name"], Loot.describe(item).replace("\n", ", ")]
		else:
			t += "[color=#777777]%s: empty[/color]   " % slot
		t += "\n       "
	_gear.text = t
