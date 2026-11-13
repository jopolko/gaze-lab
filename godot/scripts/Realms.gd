class_name Realms
extends RefCounted
## REALMS: the strange places behind the mystery gates. Each one has its own ground, its own props, its own rule, and none of them is announced:
## a gate shows a glyph, never a name, and the name appears when you arrive. Everything is generated from primitives and a small shader.
##
##   highway   DESERT HIGHWAY  a neon desert grid, cacti, road-sign poles, swarms of bats. The surface is slick: you drift.      (hard)
##   interzone INTERZONE       a paper-and-newsprint bazaar of arches and pillars. At the far barrier the world is CUT UP: you are spliced sideways.
##   hive      THE HIVE        a ribbed bone-and-pipe corridor that breathes. The beat speeds you up and drags you back, hoops to thread.  (hard)
##   eyes      ORCHARD OF EYES giant eyes on stalks follow you. Look toward one and hold it: it blinks shut and lets you pass.
##   melt      THE MELT        liquid, swirling ground that rolls under you, blobs and mushrooms that sway, a slippery slope.             (hard)
##   mandala   MANDALA DROP    a steep fall through radial petals and rings, the ground a spinning colour wheel.

##   glowcave  GLOW GROTTO     a roofed cavern: dark mouth, a black tunnel, then the lights come on, mammoth glowing mushrooms, ferns and vines.
##   crystal   CRYSTAL VAULT   a roofed vault of glowing crystal clusters and stalagmites in cold colours.
##   lava      LAVA TUBE       a roofed basalt tube with glowing cracks in the floor, columns capped with fire and falls of lava. Fast and crowded. (hard)
##   abyss     JELLY ABYSS     a deep, roofed dark with drifting glowing jellyfish and coral. Heavy going.
## The roofed realms dim the whole picture while you are inside (exposure) and the glowing things are boosted to make up for it, so they are the light.

const IDS := ["highway", "interzone", "hive", "eyes", "melt", "mandala", "glowcave", "crystal", "lava", "abyss"]
const NAMES := {"highway": "DESERT HIGHWAY", "interzone": "INTERZONE", "hive": "THE HIVE", "eyes": "ORCHARD OF EYES", "melt": "THE MELT", "mandala": "MANDALA DROP",
	"glowcave": "GLOW GROTTO", "crystal": "CRYSTAL VAULT", "lava": "LAVA TUBE", "abyss": "JELLY ABYSS"}
const ROOF := {
	"glowcave": {"col": Color(0.12, 0.08, 0.22), "expo": 0.4, "reveal": "THE GROTTO WAKES"},
	"crystal": {"col": Color(0.08, 0.12, 0.24), "expo": 0.5, "reveal": "THE VAULT LIGHTS"},
	"lava": {"col": Color(0.16, 0.06, 0.05), "expo": 0.55, "reveal": "THE TUBE GLOWS"},
	"abyss": {"col": Color(0.03, 0.08, 0.2), "expo": 0.35, "reveal": "SOMETHING IS WATCHING"},
}
static var cave_k: float = 0.0              # how dark the picture is (0 outside, 1 deep inside), written by the rig, read by Lighting
static var cave_expo: float = 1.0
static var flash: float = 0.0               # the lights coming on


static func has_roof(zone: String) -> bool:
	return ROOF.has(zone)


## All the glowing materials get brighter as the world dims, and surge when the lights come on.
static func apply_cave() -> void:
	var b := lerpf(1.0, 0.9 / maxf(cave_expo, 0.2), cave_k)
	for key in _mats:
		var m: ShaderMaterial = _mats[key]
		m.set_shader_parameter("boost", b)
		m.set_shader_parameter("flash", flash)
const SIGN_COL := Color(0.95, 0.55, 1.0)          # every realm gate glows the same shimmering violet: you learn the glyphs, not the colours

## id -> what is built there. "solid" props are obstacles, "scene" props are scenery.
const KITS := {
	"highway": {"solid": ["cactus", "pole"], "scene": ["cactus", "pole", "bats"], "glow": 0.5},
	"interzone": {"solid": ["pillar", "arch_leg"], "scene": ["arch", "pillar", "awning"], "glow": 0.15},
	"hive": {"solid": ["rib", "pipe"], "scene": ["rib", "pipe", "pipe"], "glow": 0.2, "beat": 1.0},
	"eyes": {"solid": ["eyeball", "eyeball", "stalk"], "scene": ["stalk", "stalk", "eyeball"], "glow": 0.2},
	"melt": {"solid": ["blob", "mush"], "scene": ["blob", "mush", "mush"], "glow": 0.55, "wob": 1.0},
	"mandala": {"solid": ["petal", "petal"], "scene": ["ring", "petal", "petal"], "glow": 0.6},
	"glowcave": {"solid": ["glowshroom", "glowshroom", "stalag"], "scene": ["glowshroom", "frond", "frond", "vine", "vine"], "glow": 1.0},
	"crystal": {"solid": ["crystal", "crystal", "stalag"], "scene": ["crystal", "crystal", "vine"], "glow": 1.1},
	"lava": {"solid": ["lavarock", "lavarock", "stalag"], "scene": ["lavafall", "lavarock", "stalag"], "glow": 0.9},
	"abyss": {"solid": ["coral", "stalag", "coral"], "scene": ["jelly", "jelly", "coral"], "glow": 1.0},
}
const RADIUS := {"cactus": 1.0, "pole": 0.6, "pillar": 1.0, "arch_leg": 1.0, "rib": 1.3, "pipe": 1.1, "eyeball": 1.6, "stalk": 0.9, "blob": 1.8, "mush": 1.6, "petal": 1.7,
	"glowshroom": 1.2, "crystal": 1.5, "stalag": 1.5, "lavarock": 1.5, "coral": 1.4}
const HANGING := ["vine", "stalactite"]          # these hang from the roof
const FLOATING := ["jelly"]                      # these drift in the air
const FACING := ["arch", "rib", "awning", "ring", "petal", "pole"]          # these do not turn at random: they face the rider
const ORIGIN_Y := {"bats": 0.0, "ring": 0.0}

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}
static var found: Dictionary = {}
static var _loaded: bool = false


static func is_realm(zone: String) -> bool:
	return KITS.has(zone)


static func pick(zone: String, scene: bool, rng: RandomNumberGenerator) -> String:
	var l: Array = (KITS[zone] as Dictionary)["scene" if scene else "solid"]
	return String(l[rng.randi() % l.size()])


static func radius(id: String) -> float:
	return float(RADIUS.get(id, 1.0))


## A tint that varies the look from one prop to the next.
static func tint(zone: String, rng: RandomNumberGenerator) -> Color:
	match zone:
		"melt":
			return Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.9), 1.0)
		"mandala":
			return Color.from_hsv(fposmod(0.82 + rng.randf_range(-0.25, 0.25), 1.0), rng.randf_range(0.5, 0.85), 1.0)
		"highway":
			return Color.from_hsv(rng.randf_range(0.45, 0.95), rng.randf_range(0.35, 0.7), 1.0)
		"eyes":
			return Color.from_hsv(rng.randf_range(0.0, 0.08), rng.randf_range(0.1, 0.35), rng.randf_range(0.85, 1.0))
		"interzone":
			return Color.from_hsv(rng.randf_range(0.08, 0.14) if rng.randf() < 0.7 else rng.randf(), rng.randf_range(0.1, 0.5), rng.randf_range(0.8, 1.0))
		"glowcave":
			return Color.from_hsv(rng.randf_range(0.42, 0.95), rng.randf_range(0.65, 0.9), 1.0)
		"crystal":
			return Color.from_hsv([0.5, 0.58, 0.85, 0.95, 0.12][rng.randi() % 5], rng.randf_range(0.55, 0.85), 1.0)
		"lava":
			return Color.from_hsv(rng.randf_range(0.0, 0.1), rng.randf_range(0.8, 1.0), 1.0)
		"abyss":
			return Color.from_hsv(rng.randf_range(0.45, 0.62), rng.randf_range(0.6, 0.9), 1.0)
	return Color.from_hsv(rng.randf_range(0.28, 0.4), rng.randf_range(0.08, 0.25), rng.randf_range(0.7, 0.95))          # hive: bone and green-grey


## The colour of the ground at a point.
static func ground(zone: String, x: float, z: float, zc: float, base: Color) -> Color:
	match zone:
		"highway":
			var gx := absf(fposmod(x, 14.0) - 7.0)
			var gz := absf(fposmod(z, 14.0) - 7.0)
			var line := 1.0 - smoothstep(0.0, 0.5, minf(gx, gz) - 6.5)          # thin neon grid lines
			var sand := Color(0.34, 0.12, 0.34).lerp(Color(0.9, 0.38, 0.3), 0.5 + 0.5 * sin(z * 0.02 + x * 0.01))
			return sand.lerp(Color(0.2, 1.0, 0.9), clampf(line, 0.0, 1.0) * 0.9)
		"interzone":
			var cx := floori(x / 9.0)
			var cz := floori(z / 9.0)
			var hsh := fposmod(float(cx * 73 + cz * 151 + cx * cz * 7), 11.0)
			var paper := Color(0.93, 0.89, 0.76)
			var ink := Color(0.16, 0.18, 0.22)
			var c := paper if (cx + cz) % 2 == 0 else ink
			if hsh < 1.2:
				c = Color(0.95, 0.2, 0.55)
			elif hsh < 2.2:
				c = Color(0.98, 0.84, 0.2)
			var txt := 0.5 + 0.5 * sin(z * 3.1)          # lines of type
			return c.lerp(c.darkened(0.25), 0.25 * txt)
		"hive":
			var rib := 0.5 + 0.5 * sin(z * 1.35)
			var sheen := 0.5 + 0.5 * sin(x * 0.08 + z * 0.03)
			var c2 := Color(0.22, 0.3, 0.26).lerp(Color(0.5, 0.58, 0.5), rib * rib)
			return c2.lerp(Color(0.45, 0.2, 0.55), 0.25 * sheen)
		"eyes":
			var v := sin(x * 0.31 + sin(z * 0.17) * 2.0) * sin(z * 0.23 - sin(x * 0.12) * 2.0)
			var vein := smoothstep(0.78, 0.97, absf(v))
			return Color(0.98, 0.82, 0.8).lerp(Color(0.75, 0.1, 0.18), vein * 0.8)
		"melt":
			var h := fposmod(0.15 * sin(x * 0.045 + z * 0.03) + z * 0.006 + 0.1 * sin(x * 0.11 - z * 0.05), 1.0)
			return Color.from_hsv(h, 0.78, 1.0)
		"mandala":
			var dx := x
			var dz := z - zc
			var r := sqrt(dx * dx + dz * dz)
			var ang := atan2(dz, dx)
			var petals := 0.5 + 0.5 * sin(ang * 8.0 + r * 0.05)
			var rings := 0.5 + 0.5 * sin(r * 0.55)
			return Color.from_hsv(fposmod(r * 0.012 + petals * 0.18, 1.0), 0.8 - 0.35 * rings, 0.55 + 0.45 * rings)
		"glowcave":
			var pool := smoothstep(0.35, 0.75, sin(x * 0.085 + sin(z * 0.06) * 2.0) * sin(z * 0.07 - x * 0.03))
			return Color(0.2, 0.14, 0.34).lerp(Color(0.2, 1.0, 0.8), pool)
		"crystal":
			var fx := floori(x / 7.0)
			var fz := floori(z / 7.0)
			var h2 := fposmod(float(fx * 31 + fz * 57 + fx * fz * 3), 7.0) / 7.0
			var edge := 1.0 - smoothstep(0.0, 0.7, minf(absf(fposmod(x, 7.0) - 3.5), absf(fposmod(z, 7.0) - 3.5)) - 2.8)
			return Color.from_hsv(0.5 + 0.35 * h2, 0.6, 0.12 + 0.18 * h2).lerp(Color(0.6, 0.9, 1.0), edge * 0.8)
		"lava":
			var cr := absf(sin(x * 0.19 + sin(z * 0.11) * 3.0)) * absf(sin(z * 0.15 + sin(x * 0.07) * 2.5))
			var glow := 1.0 - smoothstep(0.0, 0.16, cr)
			return Color(0.2, 0.1, 0.09).lerp(Color(1.0, 0.45, 0.08), glow)
		"abyss":
			var caustic := 0.5 + 0.5 * sin(x * 0.2 + sin(z * 0.13 + x * 0.05) * 3.0) * sin(z * 0.18 - x * 0.04)
			return Color(0.05, 0.13, 0.28).lerp(Color(0.1, 0.7, 0.9), smoothstep(0.82, 1.0, caustic) * 0.8)
	return base


## How much the ground rolls in a melt stretch.
static func melt_h(x: float, z: float, edge: float) -> float:
	return edge * (2.4 * sin(z * 0.07 + x * 0.05) + 1.6 * sin(x * 0.11 - z * 0.055))


## The ground colour comes through almost as designed (the snow lighting is tuned for white and would wash it out): mostly emission, a little light for the slopes.
static func ground_material() -> ShaderMaterial:
	if _mats.has("_ground"):
		return _mats["_ground"]
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode cull_disabled;
uniform float boost = 1.0;
uniform float flash = 0.0;
void fragment() {
	vec3 c = COLOR.rgb;
	c = c * c;
	ALBEDO = c * 0.4;
	EMISSION = c * 0.7 * boost * (1.0 + flash * 0.8);
	ROUGHNESS = 0.95;
}
"
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats["_ground"] = m
	return m


static func material(zone: String) -> ShaderMaterial:
	if _mats.has(zone):
		return _mats[zone]
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode cull_disabled;
uniform float glow = 0.3;
uniform float beat = 0.0;
uniform float wob = 0.0;
uniform float boost = 1.0;
uniform float flash = 0.0;
void vertex() {
	float w = 1.0 - COLOR.a;
	VERTEX.y += sin(TIME * 9.0 + VERTEX.x * 2.0 + float(INSTANCE_ID)) * 0.4 * w;
	VERTEX.x += cos(TIME * 7.0 + float(INSTANCE_ID) * 1.7) * 0.3 * w;
	VERTEX *= 1.0 + beat * 0.07 * sin(TIME * 5.5);
	VERTEX.xz += wob * 0.22 * sin(TIME * 1.8 + VERTEX.y * 1.4 + float(INSTANCE_ID)) * max(VERTEX.y, 0.0) * 0.3;
}
void fragment() {
	vec3 c = COLOR.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = c;
	ROUGHNESS = 0.7;
	EMISSION = (c * glow + c * rim * 0.5) * boost * (1.0 + flash * 1.5);
}
"
	var m := ShaderMaterial.new()
	m.shader = sh
	var k: Dictionary = KITS[zone]
	m.set_shader_parameter("glow", float(k.get("glow", 0.3)))
	m.set_shader_parameter("beat", float(k.get("beat", 0.0)))
	m.set_shader_parameter("wob", float(k.get("wob", 0.0)))
	_mats[zone] = m
	return m


# --------------------------------------------------------------------------
# Meshes: a handful of primitives with vertex colours, merged into one mesh each.
# --------------------------------------------------------------------------
class B:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func add(m: Mesh, xf: Transform3D, col: Color) -> void:
		var a := m.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ix: Variant = a[Mesh.ARRAY_INDEX]
		var base := v.size()
		for k in vs.size():
			v.append(xf * vs[k])
			n.append((xf.basis * ns[k]).normalized())
			c.append(col)
		if ix == null:
			for k in vs.size():
				i.append(base + k)
		else:
			for k in (ix as PackedInt32Array):
				i.append(base + k)

	func cyl(pos: Vector3, r0: float, r1: float, h: float, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
		var m := CylinderMesh.new()
		m.top_radius = r1
		m.bottom_radius = r0
		m.height = h
		m.radial_segments = 7
		m.rings = 1
		add(m, Transform3D(Basis.from_euler(rot), pos), col)

	func ball(pos: Vector3, r: float, col: Color, sc: Vector3 = Vector3.ONE) -> void:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 8
		m.rings = 4
		add(m, Transform3D(Basis.from_scale(sc), pos), col)

	func box(pos: Vector3, size: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(m, Transform3D(Basis.from_euler(rot), pos), col)

	func ring(pos: Vector3, inner: float, outer: float, col: Color, rot: Vector3 = Vector3(PI * 0.5, 0, 0)) -> void:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 14
		m.ring_segments = 6
		add(m, Transform3D(Basis.from_euler(rot), pos), col)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var b := B.new()
	var wh := Color(1, 1, 1)
	match id:
		"cactus":
			b.cyl(Vector3(0, 2.6, 0), 0.5, 0.42, 5.2, Color(0.35, 0.95, 0.6))
			b.cyl(Vector3(1.1, 3.0, 0), 0.3, 0.3, 1.8, Color(0.3, 0.85, 0.55), Vector3(0, 0, PI * 0.5))
			b.cyl(Vector3(1.9, 3.9, 0), 0.3, 0.26, 1.9, Color(0.35, 0.95, 0.6))
			b.cyl(Vector3(-1.0, 2.2, 0), 0.3, 0.3, 1.6, Color(0.3, 0.85, 0.55), Vector3(0, 0, PI * 0.5))
			b.cyl(Vector3(-1.7, 3.0, 0), 0.3, 0.26, 1.7, Color(0.35, 0.95, 0.6))
			b.ball(Vector3(0, 5.35, 0), 0.5, Color(1.0, 0.4, 0.8))
		"pole":
			b.cyl(Vector3(0, 4.5, 0), 0.2, 0.15, 9.0, Color(0.55, 0.55, 0.65))
			b.box(Vector3(0, 8.4, 0), Vector3(3.0, 1.3, 0.2), Color(1.0, 0.25, 0.7))
			b.box(Vector3(0, 6.9, 0), Vector3(2.2, 0.7, 0.2), Color(0.2, 0.95, 1.0))
		"bats":
			for k in 6:
				var a := float(k) * 1.05
				var o := Vector3(cos(a) * 3.6, 7.0 + float(k % 3) * 1.3, sin(a * 1.7) * 2.5)
				b.ball(o, 0.28, Color(0.25, 0.1, 0.3))
				b.box(o + Vector3(-0.5, 0.1, 0), Vector3(0.9, 0.06, 0.45), Color(0.3, 0.12, 0.35, 0.4), Vector3(0, 0, 0.45))
				b.box(o + Vector3(0.5, 0.1, 0), Vector3(0.9, 0.06, 0.45), Color(0.3, 0.12, 0.35, 0.4), Vector3(0, 0, -0.45))
		"pillar":
			b.cyl(Vector3(0, 4.0, 0), 0.8, 0.7, 8.0, Color(0.95, 0.92, 0.85))
			b.box(Vector3(0, 8.2, 0), Vector3(2.2, 0.6, 2.2), Color(0.3, 0.3, 0.35))
			b.box(Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), Color(0.3, 0.3, 0.35))
			b.box(Vector3(0, 6.0, 0.8), Vector3(1.6, 0.7, 0.1), Color(0.95, 0.25, 0.5))
		"arch_leg":
			b.cyl(Vector3(0, 3.0, 0), 0.7, 0.7, 6.0, Color(0.9, 0.75, 0.3))
			b.ball(Vector3(0, 6.3, 0), 0.9, Color(0.9, 0.3, 0.55))
		"arch":
			b.cyl(Vector3(-4.2, 4.0, 0), 0.8, 0.8, 8.0, Color(0.95, 0.9, 0.8))
			b.cyl(Vector3(4.2, 4.0, 0), 0.8, 0.8, 8.0, Color(0.95, 0.9, 0.8))
			b.box(Vector3(0, 8.4, 0), Vector3(10.4, 1.2, 1.4), Color(0.2, 0.22, 0.28))
			b.box(Vector3(0, 8.4, 0.75), Vector3(9.0, 0.5, 0.1), Color(0.98, 0.84, 0.2))
		"awning":
			b.box(Vector3(0, 7.0, 0), Vector3(8.0, 0.2, 4.0), Color(0.95, 0.2, 0.5), Vector3(0.35, 0, 0))
			b.box(Vector3(-3.0, 7.0, 0), Vector3(1.4, 0.22, 4.0), wh, Vector3(0.35, 0, 0))
			b.box(Vector3(0.2, 7.0, 0), Vector3(1.4, 0.22, 4.0), wh, Vector3(0.35, 0, 0))
			b.box(Vector3(3.2, 7.0, 0), Vector3(1.4, 0.22, 4.0), wh, Vector3(0.35, 0, 0))
			b.cyl(Vector3(-3.8, 3.3, 1.2), 0.15, 0.15, 6.6, Color(0.3, 0.3, 0.35))
			b.cyl(Vector3(3.8, 3.3, 1.2), 0.15, 0.15, 6.6, Color(0.3, 0.3, 0.35))
		"rib":
			b.ring(Vector3(0, 1.0, 0), 2.7, 3.7, Color(0.82, 0.88, 0.8))
			b.ball(Vector3(-3.2, 0.3, 0), 0.9, Color(0.6, 0.66, 0.6))
			b.ball(Vector3(3.2, 0.3, 0), 0.9, Color(0.6, 0.66, 0.6))
			b.ball(Vector3(0, 4.7, 0), 0.8, Color(0.6, 0.66, 0.6))
		"pipe":
			b.cyl(Vector3(0, 3.0, 0), 0.5, 0.5, 6.0, Color(0.5, 0.58, 0.52))
			for k in 3:
				b.ring(Vector3(0, 1.2 + 1.9 * float(k), 0), 0.45, 0.8, Color(0.75, 0.8, 0.7), Vector3.ZERO)
			b.ball(Vector3(0, 6.2, 0), 0.8, Color(0.85, 0.9, 0.82))
		"stalk":
			b.cyl(Vector3(0, 3.5, 0), 0.5, 0.3, 7.0, Color(0.95, 0.75, 0.72))
			b.ball(Vector3(0, 7.3, 0), 1.2, Color(0.95, 0.72, 0.7))
			b.ball(Vector3(0, 7.6, 0.2), 1.25, Color(0.8, 0.45, 0.45), Vector3(1.0, 0.4, 1.0))
		"eyeball":
			b.cyl(Vector3(0, 3.0, 0), 0.5, 0.35, 6.0, Color(0.95, 0.75, 0.72))
			b.ball(Vector3(0, 7.0, 0), 1.9, Color(1.0, 0.98, 0.95))
		"iris":
			b.ball(Vector3.ZERO, 0.9, Color(0.2, 0.75, 0.6), Vector3(1.0, 1.0, 0.35))
			b.ball(Vector3(0, 0, 0.12), 0.45, Color(0.02, 0.02, 0.04), Vector3(1.0, 1.0, 0.3))
		"blob":
			b.ball(Vector3(0, 1.4, 0), 1.7, wh, Vector3(1.0, 1.3, 1.0))
			b.ball(Vector3(0.2, 3.7, 0), 1.2, Color(1.0, 0.92, 0.95))
			b.ball(Vector3(-0.1, 5.2, 0), 0.75, wh)
			b.cyl(Vector3(1.6, 1.6, 0.4), 0.3, 0.1, 3.2, Color(1.0, 0.85, 0.9))
		"mush":
			b.cyl(Vector3(0, 1.6, 0), 0.7, 0.55, 3.2, Color(1.0, 0.97, 0.9))
			b.ball(Vector3(0, 3.3, 0), 2.4, wh, Vector3(1.0, 0.5, 1.0))
			b.ball(Vector3(0.9, 4.2, 0.6), 0.4, Color(1, 1, 0.9))
			b.ball(Vector3(-1.0, 4.0, -0.4), 0.35, Color(1, 1, 0.9))
		"petal":
			b.cyl(Vector3(0, 1.6, 0), 0.25, 0.25, 3.2, Color(0.5, 0.95, 0.7))
			for k in 8:
				var a2 := float(k) * TAU / 8.0
				b.ball(Vector3(cos(a2) * 1.5, 3.4 + sin(a2) * 1.5, 0), 0.9, wh if k % 2 == 0 else Color(1.0, 0.8, 1.0), Vector3(1.0, 0.5, 0.3))
			b.ball(Vector3(0, 3.4, 0.05), 0.8, Color(1.0, 0.95, 0.4), Vector3(1, 1, 0.5))
		"ring":
			b.ring(Vector3(0, 12.0, 0), 5.3, 6.0, wh)
			b.ring(Vector3(0, 12.0, 0), 3.0, 3.4, Color(1.0, 0.85, 1.0))
		"glowshroom":
			b.cyl(Vector3(0, 4.0, 0), 0.9, 0.6, 8.0, Color(0.85, 0.9, 1.0))
			b.ball(Vector3(0, 8.6, 0), 4.5, wh, Vector3(1.0, 0.45, 1.0))
			b.ring(Vector3(0, 8.1, 0), 3.2, 3.9, Color(1.0, 1.0, 0.7), Vector3.ZERO)
			for k in 5:
				var sa := float(k) * 1.26
				b.ball(Vector3(cos(sa) * 2.3, 10.3 - 0.4 * float(k % 2), sin(sa) * 2.3), 0.5, Color(1.0, 1.0, 0.85))
		"frond":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.7, 7.0, 0.12)
			for k in 7:
				var fa := float(k) * TAU / 7.0
				var fx := Transform3D(Basis(Vector3.UP, fa) * Basis(Vector3.RIGHT, 0.6), Vector3(cos(fa) * 0.5, 3.0, sin(fa) * 0.5))
				b.add(bm, fx, Color(0.6, 1.0, 0.8) if k % 2 == 0 else Color(1.0, 0.9, 1.0))
			b.ball(Vector3(0, 0.6, 0), 0.9, Color(1.0, 0.95, 0.6))
		"vine":
			b.cyl(Vector3(0, -6.0, 0), 0.15, 0.15, 12.0, Color(0.5, 0.8, 0.9))
			for k in 3:
				b.ball(Vector3(0.0, -3.5 - 3.5 * float(k), 0.0), 0.5 + 0.2 * float(k), Color(1.0, 1.0, 0.8, 0.5))
		"stalactite":
			b.cyl(Vector3(0, -3.5, 0), 0.0, 1.5, 7.0, Color(0.16, 0.12, 0.2))
		"stalag":
			b.cyl(Vector3(0, 3.0, 0), 1.5, 0.0, 6.0, Color(0.16, 0.12, 0.2))
			b.cyl(Vector3(0, 0.4, 0), 1.8, 1.6, 0.8, Color(0.12, 0.09, 0.15))
		"crystal":
			for k in 3:
				var cr := Vector3(1.4 * float(k - 1), 0.0, 0.5 * float(k % 2))
				var tl := 0.3 * float(k - 1)
				var hgt := 4.5 + 2.2 * float((k + 1) % 3)
				b.cyl(cr + Vector3(-sin(tl) * hgt * 0.5, hgt * 0.5, 0.0), 0.9, 0.9, hgt, wh, Vector3(0, 0, tl))
				b.cyl(cr + Vector3(-sin(tl) * (hgt + 0.9), hgt + 0.9, 0.0), 0.9, 0.0, 1.8, Color(1.0, 1.0, 1.0), Vector3(0, 0, tl))
		"lavarock":
			b.cyl(Vector3(0, 2.5, 0), 1.4, 1.3, 5.0, Color(0.12, 0.08, 0.08))
			b.ring(Vector3(0, 5.0, 0), 0.5, 1.3, Color(1.0, 0.5, 0.1), Vector3.ZERO)
			b.ball(Vector3(0, 5.2, 0), 0.7, Color(1.0, 0.8, 0.3), Vector3(1.0, 0.5, 1.0))
		"lavafall":
			b.box(Vector3(0, 15.0, 0), Vector3(1.8, 30.0, 1.2), Color(1.0, 0.4, 0.08))
			b.box(Vector3(0, 15.0, 0.3), Vector3(0.7, 30.0, 0.8), Color(1.0, 0.9, 0.45))
			b.ball(Vector3(0, 0.5, 0), 2.4, Color(1.0, 0.5, 0.1), Vector3(1.0, 0.3, 1.0))
		"jelly":
			b.ball(Vector3(0, 9.0, 0), 2.4, wh, Vector3(1.0, 0.7, 1.0))
			b.ball(Vector3(0, 9.2, 0), 1.4, Color(1.0, 1.0, 1.0), Vector3(1.0, 0.7, 1.0))
			for k in 6:
				var ja := float(k) * TAU / 6.0
				b.cyl(Vector3(cos(ja) * 1.2, 5.8, sin(ja) * 1.2), 0.12, 0.12, 5.0, Color(1.0, 1.0, 1.0, 0.35))
		"coral":
			b.cyl(Vector3(0, 2.0, 0), 0.7, 0.5, 4.0, Color(0.9, 0.9, 1.0))
			for k in 4:
				var ca := float(k) * TAU / 4.0
				b.cyl(Vector3(cos(ca) * 1.0, 4.6, sin(ca) * 1.0), 0.4, 0.25, 3.2, wh, Vector3(sin(ca) * 0.5, 0, -cos(ca) * 0.5))
				b.ball(Vector3(cos(ca) * 1.7, 6.2, sin(ca) * 1.7), 0.55, Color(1.0, 1.0, 0.9))
	var m := b.build()
	_meshes[id] = m
	return m


# --------------------------------------------------------------------------
# What you have discovered, kept between runs.
# --------------------------------------------------------------------------
static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load("user://downhill_realms.cfg") == OK:
		for id in IDS:
			if bool(cf.get_value("found", id, false)):
				found[id] = true


## Returns how many realms you have found so far if this one is new to you, else 0.
static func discover(id: String) -> int:
	_load()
	if found.has(id):
		return 0
	found[id] = true
	var cf := ConfigFile.new()
	for k in found:
		cf.set_value("found", k, true)
	cf.save("user://downhill_realms.cfg")
	return found.size()
