class_name Roster
extends RefCounted
## The cast. Every character is data (DEFS) plus a primitive-shape builder.
## collider = [type, a, b]: capsule [r, h], sphere [r, 0], box [width, height].

const DEFS := {
	&"waddler": {"name": "Dave the Waddler", "hp": 40.0, "speed": 4.5, "scale": 1.0, "humanoid": true,
		"collider": ["capsule", 0.4, 1.8], "contact": 10.0, "push": 12.0, "behavior": "chase", "xp": 10,
		"coins": [1, 3], "stagger": 6.0, "color": Color(0.95, 0.55, 0.7), "min_wave": 1, "weight": 10.0, "cost": 1.0,
		"blurb": "Shoves you. That's the whole personality."},
	&"goose": {"name": "Honk the Goose", "hp": 30.0, "speed": 5.5, "scale": 0.9, "humanoid": true,
		"collider": ["capsule", 0.4, 1.8], "contact": 12.0, "push": 14.0, "behavior": "rush", "xp": 18,
		"coins": [1, 4], "stagger": 6.0, "color": Color(0.97, 0.97, 0.97), "min_wave": 2, "weight": 6.0, "cost": 1.5,
		"windup": 0.7, "rush_speed": 20.0, "rush_time": 0.8, "recover": 1.2, "trigger": 13.0, "homing": false, "cooldown": 2.5,
		"blurb": "Telegraphs a HONK, then charges like a feathered missile."},
	&"bouncer": {"name": "Sir Bounce-a-Lot", "hp": 45.0, "speed": 7.0, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.6, 0.0], "contact": 8.0, "push": 10.0, "behavior": "hop", "xp": 20,
		"coins": [2, 4], "stagger": 8.0, "color": Color(0.65, 0.4, 0.95), "min_wave": 3, "weight": 5.0, "cost": 2.0,
		"blurb": "Pogo-hops. Every landing is a tiny earthquake."},
	&"tank": {"name": "Big Brenda", "hp": 240.0, "speed": 3.0, "scale": 1.6, "humanoid": true,
		"collider": ["capsule", 0.4, 1.8], "contact": 22.0, "push": 20.0, "behavior": "tank", "xp": 60,
		"coins": [8, 14], "stagger": 38.0, "color": Color(1.0, 0.65, 0.3), "min_wave": 4, "weight": 2.5, "cost": 5.0,
		"cooldown": 5.0, "blurb": "Immovable. Ground-pounds. Needs a REAL yeet to topple."},
	&"bomber": {"name": "Kaboom Kevin", "hp": 22.0, "speed": 7.5, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.45, 0.0], "contact": 0.0, "push": 0.0, "behavior": "bomber", "xp": 15,
		"coins": [1, 2], "stagger": 6.0, "color": Color(0.9, 0.2, 0.2), "min_wave": 3, "weight": 5.0, "cost": 1.5,
		"blurb": "Sprints at you and goes boom. Kill him near his friends."},
	&"banana": {"name": "Gerald the Banana", "hp": 35.0, "speed": 5.0, "scale": 1.0, "humanoid": false,
		"collider": ["capsule", 0.35, 1.4], "contact": 6.0, "push": 8.0, "behavior": "peel", "xp": 22,
		"coins": [2, 5], "stagger": 7.0, "color": Color(1.0, 0.9, 0.2), "min_wave": 4, "weight": 4.0, "cost": 2.0,
		"blurb": "Kites you and leaves banana peels. Everyone slips. EVERYONE."},
	&"tomato": {"name": "Tomato Tony", "hp": 28.0, "speed": 4.5, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.55, 0.0], "contact": 6.0, "push": 8.0, "behavior": "thrower", "xp": 20,
		"coins": [2, 4], "stagger": 7.0, "color": Color(0.9, 0.12, 0.1), "min_wave": 2, "weight": 6.0, "cost": 1.5,
		"blurb": "Lobs tomatoes. Kick them back for a refund."},
	&"spinner": {"name": "Dizzy Dan", "hp": 60.0, "speed": 4.5, "scale": 1.0, "humanoid": true,
		"collider": ["capsule", 0.4, 1.8], "contact": 14.0, "push": 16.0, "behavior": "rush", "xp": 28,
		"coins": [3, 6], "stagger": 8.0, "color": Color(0.2, 0.8, 0.8), "min_wave": 5, "weight": 4.0, "cost": 3.0,
		"windup": 0.5, "rush_speed": 9.0, "rush_time": 2.2, "recover": 1.8, "trigger": 7.0, "homing": true, "cooldown": 2.0,
		"blurb": "Becomes a human tornado, then gets hilariously dizzy."},
	&"balloon": {"name": "Barry the Balloon", "hp": 8.0, "speed": 3.5, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.6, 0.0], "contact": 8.0, "push": 10.0, "behavior": "flyer", "xp": 14,
		"coins": [1, 3], "stagger": 999.0, "knock": 0.8, "color": Color(1.0, 0.45, 0.6), "min_wave": 3, "weight": 4.0, "cost": 1.5,
		"blurb": "Floats, then dive-bombs. One poke and he pops."},
	&"mime": {"name": "Mime Marcel", "hp": 70.0, "speed": 9.0, "scale": 1.0, "humanoid": true,
		"collider": ["capsule", 0.4, 1.8], "contact": 15.0, "push": 14.0, "behavior": "mime", "xp": 30,
		"coins": [3, 6], "stagger": 8.0, "color": Color(0.96, 0.96, 0.96), "min_wave": 6, "weight": 3.0, "cost": 3.0,
		"blurb": "Freezes when you look at him. Blink and he's behind you."},
	&"mama": {"name": "Mama Quack", "hp": 90.0, "speed": 3.5, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.8, 0.0], "contact": 10.0, "push": 12.0, "behavior": "summoner", "xp": 40,
		"coins": [4, 8], "stagger": 14.0, "color": Color(1.0, 0.85, 0.15), "min_wave": 6, "weight": 2.5, "cost": 4.0,
		"cooldown": 7.0, "blurb": "Summons angry ducklings in threes."},
	&"duckling": {"name": "Duckling", "hp": 8.0, "speed": 8.0, "scale": 1.0, "humanoid": false,
		"collider": ["sphere", 0.22, 0.0], "contact": 4.0, "push": 4.0, "behavior": "chase", "xp": 3,
		"coins": [0, 1], "stagger": 3.0, "color": Color(1.0, 0.9, 0.3), "min_wave": 999, "weight": 0.0, "cost": 0.5,
		"blurb": "Tiny. Fast. Furious."},
	&"vacuum": {"name": "Vacuum Vic", "hp": 90.0, "speed": 3.5, "scale": 1.0, "humanoid": false,
		"collider": ["capsule", 0.5, 1.6], "contact": 6.0, "push": 8.0, "behavior": "vacuum", "xp": 38,
		"coins": [4, 8], "stagger": 12.0, "color": Color(0.85, 0.15, 0.2), "min_wave": 7, "weight": 2.5, "cost": 4.0,
		"cooldown": 3.0, "blurb": "Sucks in you AND your props, then burps everything out."},
	&"magician": {"name": "Poof the Magician", "hp": 38.0, "speed": 5.0, "scale": 1.0, "humanoid": false,
		"collider": ["capsule", 0.4, 1.8], "contact": 10.0, "push": 12.0, "behavior": "blink", "xp": 24,
		"coins": [2, 5], "stagger": 7.0, "color": Color(0.5, 0.22, 0.75), "min_wave": 5, "weight": 3.0, "cost": 2.5,
		"cooldown": 4.5, "blurb": "Vanishes in a puff of confetti and reappears right behind you."},
	&"boss": {"name": "THE BIG CHEESE", "hp": 700.0, "speed": 3.8, "scale": 2.4, "humanoid": false,
		"collider": ["box", 1.5, 1.5], "contact": 25.0, "push": 24.0, "behavior": "boss", "xp": 400,
		"coins": [40, 60], "stagger": 999.0, "knock": 0.05, "color": Color(1.0, 0.82, 0.2), "min_wave": 999, "weight": 0.0, "cost": 0.0,
		"windup": 0.9, "rush_speed": 14.0, "rush_time": 1.2, "recover": 2.0, "trigger": 20.0, "homing": false, "cooldown": 3.5,
		"blurb": "A dairy-based disaster. Stomps, rolls, summons."},
}


static func get_def(kind: StringName) -> Dictionary:
	return DEFS[kind] if DEFS.has(kind) else DEFS[&"waddler"]


static func pick(wave: int) -> StringName:
	var total := 0.0
	for k: StringName in DEFS:
		var d: Dictionary = DEFS[k]
		if int(d["min_wave"]) <= wave:
			total += float(d["weight"])
	var roll := randf() * total
	for k: StringName in DEFS:
		var d: Dictionary = DEFS[k]
		if int(d["min_wave"]) <= wave:
			roll -= float(d["weight"])
			if roll <= 0.0:
				return k
	return &"waddler"


# --------------------------------------------------------------------------
# Primitive helpers
# --------------------------------------------------------------------------
static func mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func mi(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO, glow: float = 0.0, material: Material = null) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material if material != null else mat(color, glow)
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


static func sphere(r: float, squash: float = 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 * squash
	return s


static func cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


static func torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


static func add_face(parent: Node3D, y: float = 0.06, z: float = -0.2, spread: float = 0.1, r: float = 0.09, angry: bool = false) -> void:
	for x in [-spread, spread]:
		mi(parent, sphere(r), Vector3(x, y, z), Color.WHITE)
		mi(parent, sphere(r * 0.5), Vector3(x * 0.8, y, z - r * 0.75), Color.BLACK)
		if angry:
			mi(parent, box(Vector3(r * 2.2, r * 0.35, r * 0.4)), Vector3(x, y + r * 1.3, z - r * 0.2), Color.BLACK,
				Vector3(0, 0, -20.0 * signf(x)))


# --------------------------------------------------------------------------
# Humanoid dressing (heads/torsos of the 5 humanoids)
# --------------------------------------------------------------------------
static func accessorize_head(kind: StringName, head: Node3D) -> void:
	add_face(head, 0.06, -0.2, 0.1, 0.09, kind == &"tank" or kind == &"goose")
	match kind:
		&"goose":
			mi(head, cyl(0.0, 0.1, 0.28), Vector3(0, -0.02, -0.38), Color(1.0, 0.55, 0.1), Vector3(-90, 0, 0))
			mi(head, box(Vector3(0.1, 0.35, 0.1)), Vector3(0, 0.3, 0.05), Color.WHITE)
		&"tank":
			mi(head, sphere(0.16), Vector3(0, 0.34, 0.05), Color(0.35, 0.15, 0.05))
			mi(head, torus(0.1, 0.2), Vector3(0, 0.22, 0.05), Color(1, 0.3, 0.6), Vector3(90, 0, 0))
		&"spinner":
			mi(head, sphere(0.2, 0.5), Vector3(0, 0.27, 0), Color(1, 0.3, 0.3))
			mi(head, cyl(0.02, 0.02, 0.12), Vector3(0, 0.38, 0), Color.BLACK)
			var prop := Node3D.new()
			prop.name = "Propeller"
			prop.position = Vector3(0, 0.45, 0)
			head.add_child(prop)
			mi(prop, box(Vector3(0.7, 0.02, 0.1)), Vector3.ZERO, Color(1, 0.9, 0.2))
			mi(prop, box(Vector3(0.1, 0.02, 0.7)), Vector3.ZERO, Color(0.3, 0.6, 1))
		&"mime":
			mi(head, cyl(0.3, 0.3, 0.06), Vector3(0.08, 0.27, 0), Color.BLACK, Vector3(0, 0, 8))
			mi(head, sphere(0.04), Vector3(0.08, 0.34, 0), Color.BLACK)
			mi(head, sphere(0.05), Vector3(0, -0.03, -0.27), Color(1, 0.2, 0.2))
		_:
			pass


static func dress_torso(kind: StringName, torso: Node3D) -> void:
	match kind:
		&"mime":
			for i in 4:
				mi(torso, box(Vector3(0.74, 0.07, 0.74)), Vector3(0, -0.4 + i * 0.28, 0), Color.BLACK)
		&"tank":
			mi(torso, sphere(0.25), Vector3(-0.42, 0.4, 0), Color(0.5, 0.2, 0.1))
			mi(torso, sphere(0.25), Vector3(0.42, 0.4, 0), Color(0.5, 0.2, 0.1))
			mi(torso, box(Vector3(0.74, 0.12, 0.74)), Vector3(0, 0.0, 0), Color(0.2, 0.2, 0.25))
		&"goose":
			mi(torso, box(Vector3(0.08, 0.5, 0.6)), Vector3(-0.38, 0.0, 0.1), Color(0.9, 0.9, 0.9), Vector3(0, 0, 12))
			mi(torso, box(Vector3(0.08, 0.5, 0.6)), Vector3(0.38, 0.0, 0.1), Color(0.9, 0.9, 0.9), Vector3(0, 0, -12))
		&"spinner":
			mi(torso, torus(0.25, 0.4), Vector3(0, 0.0, 0), Color(1, 0.9, 0.2), Vector3(90, 0, 0))
		_:
			pass


## Builds the standing visual. Humanoids reuse the scene's Body/Head/Arm meshes;
## everything else is constructed from scratch. Returns the head node (or null).
static func build_visual(kind: StringName, def: Dictionary, visual: Node3D, body_mat: StandardMaterial3D) -> Node3D:
	if def["humanoid"]:
		for c in visual.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = body_mat
		var head := visual.get_node("Head") as Node3D
		accessorize_head(kind, head)
		dress_torso(kind, visual.get_node("Body") as Node3D)
		return head

	for c in visual.get_children():
		c.queue_free()
	var col: Color = def["color"]
	match kind:
		&"bouncer":
			mi(visual, sphere(0.6), Vector3(0, 0.6, 0), col, Vector3.ZERO, 0.0, body_mat)
			var face := Node3D.new()
			face.position = Vector3(0, 0.7, 0)
			visual.add_child(face)
			add_face(face, 0.08, -0.5, 0.2, 0.13)
			mi(visual, cyl(0.28, 0.28, 0.4), Vector3(0, 1.3, 0), Color(0.1, 0.1, 0.15))
			mi(visual, cyl(0.4, 0.4, 0.05), Vector3(0, 1.1, 0), Color(0.1, 0.1, 0.15))
			mi(visual, torus(0.03, 0.12), Vector3(0.22, 0.78, -0.55), Color(1, 0.85, 0.2), Vector3(90, 0, 0))
		&"bomber":
			mi(visual, sphere(0.45), Vector3(0, 0.45, 0), col, Vector3.ZERO, 0.0, body_mat)
			var face := Node3D.new()
			face.position = Vector3(0, 0.55, 0)
			visual.add_child(face)
			add_face(face, 0.08, -0.32, 0.14, 0.1, true)
			mi(visual, sphere(0.1), Vector3(0, 0.45, -0.45), Color(1, 0.9, 0.2))
			mi(visual, cyl(0.03, 0.03, 0.25), Vector3(0, 1.0, 0), Color(0.15, 0.1, 0.05))
			mi(visual, sphere(0.07), Vector3(0, 1.17, 0), Color(1, 0.7, 0.1), Vector3.ZERO, 3.0)
			for i in 7:
				var a := TAU * i / 7.0
				mi(visual, sphere(0.13), Vector3(cos(a) * 0.35, 0.8, sin(a) * 0.35), Color(0.3, 0.9, 0.3))
		&"banana":
			var tilt := Node3D.new()
			tilt.position = Vector3(0, 0.75, 0)
			tilt.rotation_degrees = Vector3(0, 0, 14)
			visual.add_child(tilt)
			mi(tilt, capsule(0.33, 1.5), Vector3.ZERO, col, Vector3.ZERO, 0.0, body_mat)
			mi(tilt, cyl(0.05, 0.08, 0.2), Vector3(0, 0.82, 0), Color(0.4, 0.3, 0.1))
			mi(tilt, sphere(0.08), Vector3(0, -0.8, 0), Color(0.25, 0.15, 0.05))
			var face := Node3D.new()
			face.position = Vector3(0, 0.3, 0)
			tilt.add_child(face)
			add_face(face, 0.0, -0.24, 0.12, 0.09)
			mi(face, box(Vector3(0.4, 0.07, 0.05)), Vector3(0, 0.02, -0.3), Color.BLACK)
		&"tomato":
			mi(visual, sphere(0.55, 0.9), Vector3(0, 0.55, 0), col, Vector3.ZERO, 0.0, body_mat)
			var face := Node3D.new()
			face.position = Vector3(0, 0.65, 0)
			visual.add_child(face)
			add_face(face, 0.06, -0.42, 0.18, 0.12, true)
			mi(visual, box(Vector3(0.5, 0.08, 0.1)), Vector3(0, 0.48, -0.53), Color.BLACK)
			for i in 5:
				mi(visual, cyl(0.0, 0.14, 0.28), Vector3(cos(TAU * i / 5.0) * 0.18, 1.08, sin(TAU * i / 5.0) * 0.18), Color(0.2, 0.7, 0.2),
					Vector3(sin(TAU * i / 5.0) * 60.0, 0, -cos(TAU * i / 5.0) * 60.0))
		&"balloon":
			mi(visual, sphere(0.6, 1.25), Vector3(0, 0.6, 0), col, Vector3.ZERO, 0.0, body_mat)
			mi(visual, cyl(0.0, 0.1, 0.16), Vector3(0, -0.2, 0), col, Vector3(180, 0, 0))
			mi(visual, cyl(0.01, 0.01, 1.2), Vector3(0, -0.8, 0), Color(0.9, 0.9, 0.9))
			var face := Node3D.new()
			face.position = Vector3(0, 0.7, 0)
			visual.add_child(face)
			add_face(face, 0.05, -0.5, 0.17, 0.11)
			mi(visual, sphere(0.2, 0.5), Vector3(0.25, 0.9, -0.4), Color(1, 1, 1, 1), Vector3.ZERO, 1.0)
		&"mama":
			mi(visual, sphere(0.8, 0.9), Vector3(0, 0.75, 0), col, Vector3.ZERO, 0.0, body_mat)
			mi(visual, sphere(0.45), Vector3(0, 1.55, -0.3), col, Vector3.ZERO, 0.0, body_mat)
			var face := Node3D.new()
			face.position = Vector3(0, 1.62, -0.3)
			visual.add_child(face)
			add_face(face, 0.04, -0.34, 0.16, 0.1)
			mi(visual, box(Vector3(0.4, 0.12, 0.35)), Vector3(0, 1.5, -0.8), Color(1.0, 0.45, 0.05))
			mi(visual, cyl(0.3, 0.3, 0.05), Vector3(0, 1.98, -0.3), Color(1.0, 0.4, 0.7))
			mi(visual, sphere(0.14), Vector3(0, 2.05, -0.3), Color(1.0, 0.4, 0.7))
			mi(visual, box(Vector3(0.1, 0.5, 0.7)), Vector3(-0.85, 0.8, 0.1), Color(0.95, 0.75, 0.1), Vector3(0, 0, 25))
			mi(visual, box(Vector3(0.1, 0.5, 0.7)), Vector3(0.85, 0.8, 0.1), Color(0.95, 0.75, 0.1), Vector3(0, 0, -25))
		&"duckling":
			mi(visual, sphere(0.22), Vector3(0, 0.22, 0), col, Vector3.ZERO, 0.0, body_mat)
			var face := Node3D.new()
			face.position = Vector3(0, 0.3, 0)
			visual.add_child(face)
			add_face(face, 0.03, -0.14, 0.07, 0.05, true)
			mi(visual, box(Vector3(0.12, 0.04, 0.12)), Vector3(0, 0.25, -0.26), Color(1, 0.45, 0.05))
		&"vacuum":
			mi(visual, cyl(0.5, 0.55, 1.2), Vector3(0, 0.8, 0), col, Vector3.ZERO, 0.0, body_mat)
			mi(visual, cyl(0.2, 0.55, 0.9), Vector3(0, 0.95, -0.7), Color(0.4, 0.4, 0.45), Vector3(-90, 0, 0))
			mi(visual, torus(0.05, 0.25), Vector3(0.4, 1.4, 0.2), Color(0.15, 0.15, 0.18), Vector3(70, 0, 30))
			mi(visual, cyl(0.12, 0.12, 0.1), Vector3(0, 0.15, 0.0), Color(0.1, 0.1, 0.1))
			var face := Node3D.new()
			face.position = Vector3(0, 1.3, 0)
			visual.add_child(face)
			add_face(face, 0.0, -0.5, 0.2, 0.12, true)
			mi(visual, sphere(0.12), Vector3(-0.35, 0.9, -0.48), Color(0.2, 1, 0.3), Vector3.ZERO, 2.0)
		&"magician":
			mi(visual, capsule(0.38, 1.6), Vector3(0, 0.8, 0), col, Vector3.ZERO, 0.0, body_mat)
			mi(visual, cyl(0.2, 0.55, 1.2), Vector3(0, 0.75, 0.3), Color(0.75, 0.1, 0.2), Vector3(-12, 0, 0))
			mi(visual, sphere(0.26), Vector3(0, 1.78, 0), Color(1.0, 0.85, 0.7))
			var face := Node3D.new()
			face.position = Vector3(0, 1.8, 0)
			visual.add_child(face)
			add_face(face, 0.04, -0.2, 0.1, 0.07)
			mi(visual, cyl(0.2, 0.2, 0.5), Vector3(0, 2.2, 0), Color(0.08, 0.08, 0.1))
			mi(visual, cyl(0.2, 0.2, 0.1), Vector3(0, 2.0, 0), Color(0.9, 0.1, 0.2))
			mi(visual, cyl(0.38, 0.38, 0.04), Vector3(0, 1.97, 0), Color(0.08, 0.08, 0.1))
			mi(visual, cyl(0.025, 0.025, 0.7), Vector3(0.5, 1.0, -0.4), Color(0.1, 0.1, 0.1), Vector3(60, 0, 0))
			mi(visual, sphere(0.09), Vector3(0.5, 1.3, -0.72), Color(1.0, 0.95, 0.3), Vector3.ZERO, 3.0)
			mi(visual, box(Vector3(0.28, 0.1, 0.06)), Vector3(0, 1.45, -0.3), Color(0.9, 0.1, 0.2))
		&"boss":
			var prism := PrismMesh.new()
			prism.size = Vector3(1.6, 1.4, 1.5)
			mi(visual, prism, Vector3(0, 0.7, 0), col, Vector3.ZERO, 0.0, body_mat)
			var holes := [Vector3(-0.4, 0.5, -0.76), Vector3(0.3, 0.8, -0.76), Vector3(0.45, 0.35, -0.76), Vector3(-0.1, 0.25, -0.76)]
			for h: Vector3 in holes:
				mi(visual, cyl(0.14, 0.14, 0.08), h, Color(0.75, 0.55, 0.05), Vector3(90, 0, 0))
			var face := Node3D.new()
			face.position = Vector3(0, 0.75, 0)
			visual.add_child(face)
			add_face(face, 0.1, -0.78, 0.3, 0.15, true)
			mi(visual, box(Vector3(0.6, 0.1, 0.05)), Vector3(0, 0.45, -0.78), Color.BLACK)
			for i in 5:
				mi(visual, cyl(0.0, 0.1, 0.3), Vector3(-0.4 + i * 0.2, 1.5, 0), Color(1, 0.85, 0.1), Vector3.ZERO, 1.5)
		_:
			mi(visual, sphere(0.4), Vector3(0, 0.4, 0), col, Vector3.ZERO, 0.0, body_mat)
	return null
