class_name Pickup
extends Node3D
## Loot on the floor: coins, rubber-chicken health, power-ups and gear (with a
## rarity-coloured loot beam). Pops out of the dead enemy, then magnetises to you.

var kind: StringName = &"coin"
var payload: Variant = 1

var _t: float = randf() * 6.0
var _life: float = 45.0
var _landed: bool = false
var _vel: Vector3 = Vector3.ZERO
var _model: Node3D
var _done: bool = false
var _forced: bool = false


## Hands-free: staring at loot pulls it to the player regardless of distance.
func attract() -> void:
	_forced = true


static func spawn(ctx: Node3D, p_kind: StringName, pos: Vector3, p_payload: Variant) -> void:
	var pk := Pickup.new()
	pk.kind = p_kind
	pk.payload = p_payload
	ctx.get_parent().add_child(pk)
	var ang := randf() * TAU
	var tgt := pos + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(1.0, 3.2)
	var q := PhysicsRayQueryParameters3D.create(tgt + Vector3.UP * 4.0, tgt + Vector3.DOWN * 12.0, Game.MASK_WORLD)
	var hit := ctx.get_world_3d().direct_space_state.intersect_ray(q)
	var gy := pos.y - 0.5
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		gy = hp.y
	tgt.y = gy + 0.7
	pk.global_position = pos
	var start := pos
	var tw := pk.create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(pk) and pk.is_inside_tree():
			pk.global_position = start.lerp(tgt, t) + Vector3.UP * sin(t * PI) * 1.6, 0.0, 1.0, 0.55)
	tw.tween_callback(func() -> void: pk._landed = true)


func _ready() -> void:
	add_to_group("pickups")
	_model = Node3D.new()
	add_child(_model)
	match kind:
		&"coin":
			_life = 30.0
			Roster.mi(_model, Roster.cyl(0.2, 0.2, 0.05), Vector3.ZERO, Color(1.0, 0.8, 0.1), Vector3(90, 0, 0), 1.2)
		&"health":
			Roster.mi(_model, Roster.capsule(0.16, 0.45), Vector3.ZERO, Color(1.0, 0.9, 0.2), Vector3(0, 0, 90), 0.6)
			Roster.mi(_model, Roster.cyl(0.0, 0.07, 0.16), Vector3(-0.28, 0.0, 0), Color(1.0, 0.5, 0.1), Vector3(0, 0, 90))
			Roster.mi(_model, Roster.box(Vector3(0.1, 0.1, 0.04)), Vector3(0.1, 0.17, 0), Color(1.0, 0.1, 0.1))
			Roster.mi(_model, Roster.sphere(0.03), Vector3(-0.12, 0.08, -0.14), Color.BLACK)
		&"powerup":
			_build_powerup(String(payload))
		&"gear":
			_life = 70.0
			_build_gear(payload as Dictionary)


func _build_powerup(id: String) -> void:
	var c: Color = Prog.POWERUPS[id]["color"]
	match id:
		"megaboots":
			Roster.mi(_model, Roster.box(Vector3(0.2, 0.24, 0.38)), Vector3(-0.15, 0, 0), c, Vector3.ZERO, 1.0)
			Roster.mi(_model, Roster.box(Vector3(0.2, 0.24, 0.38)), Vector3(0.15, 0, 0), c, Vector3.ZERO, 1.0)
		"burrito":
			Roster.mi(_model, Roster.capsule(0.14, 0.5), Vector3.ZERO, Color(0.9, 0.75, 0.45), Vector3(0, 0, 90), 0.5)
			Roster.mi(_model, Roster.sphere(0.08), Vector3(0.0, 0.14, 0), c, Vector3.ZERO, 2.0)
		"socks":
			Roster.mi(_model, Roster.cyl(0.11, 0.11, 0.4), Vector3(0, 0.1, 0), Color.WHITE, Vector3.ZERO, 0.8)
			Roster.mi(_model, Roster.box(Vector3(0.22, 0.14, 0.36)), Vector3(0, -0.12, -0.08), Color.WHITE, Vector3.ZERO, 0.8)
			Roster.mi(_model, Roster.cyl(0.115, 0.115, 0.06), Vector3(0, 0.22, 0), c, Vector3.ZERO, 2.0)
		"yeetjuice":
			Roster.mi(_model, Roster.cyl(0.14, 0.14, 0.32), Vector3.ZERO, c, Vector3.ZERO, 2.0)
			Roster.mi(_model, Roster.cyl(0.05, 0.05, 0.14), Vector3(0, 0.23, 0), c, Vector3.ZERO, 2.0)
			Roster.mi(_model, Roster.sphere(0.06), Vector3(0, 0.33, 0), Color(0.6, 0.4, 0.2))
		"magnet":
			Roster.mi(_model, Roster.torus(0.07, 0.24), Vector3.ZERO, c, Vector3.ZERO, 1.5)
			Roster.mi(_model, Roster.box(Vector3(0.2, 0.06, 0.12)), Vector3(0, -0.26, 0), Color(0.8, 0.8, 0.85))
		_:
			var shield := Roster.sphere(0.32)
			var m := Roster.mat(Color(0.3, 0.6, 1.0, 0.4), 1.2)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			Roster.mi(_model, shield, Vector3.ZERO, c, Vector3.ZERO, 0.0, m)
			Roster.mi(_model, Roster.sphere(0.12), Vector3.ZERO, Color(1, 0.9, 0.2))
	Roster.mi(self, Roster.torus(0.02, 0.5), Vector3.ZERO, c, Vector3(90, 0, 0), 2.0)


func _build_gear(item: Dictionary) -> void:
	var rarity := int(item["rarity"])
	var c := Loot.rarity_color(rarity)
	match String(item["slot"]):
		"Hat":
			Roster.mi(_model, Roster.cyl(0.0, 0.26, 0.4), Vector3.ZERO, c, Vector3.ZERO, 1.2)
		"Boots":
			Roster.mi(_model, Roster.box(Vector3(0.18, 0.22, 0.36)), Vector3(-0.14, 0, 0), c, Vector3.ZERO, 1.2)
			Roster.mi(_model, Roster.box(Vector3(0.18, 0.22, 0.36)), Vector3(0.14, 0, 0), c, Vector3.ZERO, 1.2)
		_:
			Roster.mi(_model, Roster.sphere(0.2), Vector3.ZERO, c, Vector3.ZERO, 1.2)
			Roster.mi(_model, Roster.cyl(0.1, 0.1, 0.25), Vector3(0, -0.22, 0), c, Vector3.ZERO, 1.2)
	if rarity >= 2:
		var beam := Roster.mat(Color(c.r, c.g, c.b, 0.25), 2.0)
		beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var bm := Roster.mi(self, Roster.cyl(0.07, 0.07, 7.0), Vector3(0, 3.4, 0), c, Vector3.ZERO, 0.0, beam)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rarity >= 3:
		var l := OmniLight3D.new()
		l.light_color = c
		l.omni_range = 5.0
		l.light_energy = 1.5
		add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_life -= delta
	_model.rotation.y += delta * 2.5
	if _landed:
		_model.position.y = sin(_t * 3.0) * 0.12
	if _life < 5.0:
		visible = int(_t * 8.0) % 2 == 0
	if _life <= 0.0:
		queue_free()


func _physics_process(delta: float) -> void:
	if not _landed or _done:
		return
	var p := get_tree().get_first_node_in_group("player") as PlayerController
	if p == null or p.dead:
		return
	var off := (p.global_position + Vector3.UP) - global_position
	var dist := off.length()
	var radius := 3.2 + Prog.bonus("pickup_radius")
	if dist < radius or _forced:
		_vel = _vel.move_toward(off.normalized() * 20.0, 45.0 * delta)
		global_position += _vel * delta
	if dist < 1.2:
		_collect(p)


func _collect(p: PlayerController) -> void:
	_done = true
	var pos := global_position + Vector3.UP * 0.5
	match kind:
		&"coin":
			var n := Prog.add_coins(int(payload))
			Game.popup("+%d" % n, pos, Color(1.0, 0.85, 0.2), 0.5)
			Game.sfx(&"coin")
		&"health":
			p.heal(float(payload))
			Game.popup("+%d HP" % int(payload), pos, Color(0.4, 1.0, 0.4), 0.7)
			Game.sfx(&"powerup")
		&"powerup":
			var id := String(payload)
			Prog.grant_powerup(id)
			var info: Dictionary = Prog.POWERUPS[id]
			Game.banner(String(info["name"]) + "!", info["color"], 1.6)
			Game.sfx(&"powerup")
		&"gear":
			var item: Dictionary = payload
			var color := Loot.rarity_color(int(item["rarity"]))
			var rname := Loot.rarity_name(int(item["rarity"]))
			if Prog.try_loot(item):
				Game.banner("%s: %s" % [rname.to_upper(), item["name"]], color, 2.4)
				Game.popup("EQUIPPED!", pos, color, 0.8)
				Game.sfx(&"loot")
			else:
				Game.popup("%s (sold +%d)" % [item["name"], Loot.sell_value(item)], pos, color.darkened(0.2), 0.6)
				Game.sfx(&"coin")
	queue_free()
