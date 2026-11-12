class_name LevelBuilder
extends RefCounted
## Builds the five themed levels out of primitives, plus each level's lighting.
## Every level has its own environment AND its own mechanic mix:
##   0 Backyard BBQ     trampolines, slip-n-slide, goo pool, sprinkler boost strip
##   1 Supermarket      wet-floor ice, freezer goo, conveyor boosts, shelf-top climbs
##   2 Candy Kingdom    chocolate river goo, marshmallow bounce, rainbow slide, gumdrop hills
##   3 Moonbase         LOW GRAVITY, launch pads up the reactor, updraft vents, moon ice
##   4 Disco Inferno    LAVA everywhere, bridges between islands, vents, disco floor + disco ball


static func build(index: int, L: MainLevel) -> Dictionary:
	match index:
		0: return _backyard(L)
		1: return _market(L)
		2: return _candy(L)
		3: return _moon(L)
		5: return _demo(L)
		6: return _peek(L)
		7: return _flight(L)
		8: return _downhill(L)
		11:
			var cc := _downhill(L)
			cc["name"] = "Downhill"
			return cc
		9: return _trance(L)
		10: return _gaze_test(L)
		_: return _lava(L)


## 5  EYE DEMO RANGE: a small, cheap arena for the web demo (few objects so a phone
## loads it quickly; no lights, no particles, no decor).
static func _demo(L: MainLevel) -> Dictionary:
	L.box(Vector3(34, 1, 34), Vector3(0, -0.5, 0), Color(0.55, 0.8, 0.5))
	var wall := Color(0.95, 0.85, 0.6)
	L.box(Vector3(36, 6, 1), Vector3(0, 3, 17.5), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(36, 6, 1), Vector3(0, 3, -17.5), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(1, 6, 36), Vector3(17.5, 3, 0), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(1, 6, 36), Vector3(-17.5, 3, 0), wall, Vector3.ZERO, 0.0, true, false)
	for p in [Vector2(-8, -4), Vector2(8, -4), Vector2(0, -10)]:
		L.cyl(1.2, 4.0, Vector3(p.x, 2.0, p.y), _hue(int(p.x + 20.0), 40, 0.55, 0.95), 0.0, true)
	L.box(Vector3(6, 1.2, 3), Vector3(0, 0.6, 2), Color(0.9, 0.45, 0.4), Vector3.ZERO, 0.0, true, false)
	# Enemies always come from in front (the player faces -Z and never has to turn).
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		L.spawn_points.append(Vector3(x, 0.2, -13.0))
	return {
		"name": "Eye Demo Range", "half": 15.0, "spawn": Vector3(0, 0.1, 13),
		"sky_top": Color(0.3, 0.6, 0.95), "sky_horizon": Color(0.9, 0.95, 1.0), "sky_ground": Color(0.5, 0.75, 0.45),
		"fog": Color(0.8, 0.9, 1.0), "fog_density": 0.0, "ambient": 1.0,
		"sun_color": Color(1.0, 0.95, 0.85), "sun_energy": 1.5, "sun_rot": Vector3(-50, -30, 0),
		"glow": 0.0, "saturation": 1.1,
		"prop_kinds": [&"crate", &"barrel", &"ball", &"duck"] as Array[StringName],
	}


## 6  PEEK RANGE: the player rides a rail between stations. Each station has a row of cover (rocks, wall
## chunks, pillars) with baddies tucked just behind the edge of each one. You see nothing from the centre;
## lean out and they appear. Few objects, no lights: loads fast on a phone.
const PEEK_STATIONS: Array[float] = [22.0, -2.0, -26.0]
const PEEK_COVER_X: Array[float] = [-9.0, -3.0, 3.0, 9.0]
const PEEK_COVER_DIST := 9.0
const PEEK_RADIUS: Array[float] = [1.0, 1.2, 0.7]        # cover radius per station type (rock, fat rock, pillar)
const PEEK_LEAN: Array[float] = [1.0, 1.4, 0.8]          # how far you must lean to reveal a baddy, per station type


## Spawn list [kind, position] of hidden baddies for a station (more on later rounds). Each hiding spot is
## solved numerically: fully hidden from the rail centre, revealed once you lean about PEEK_LEAN metres.
static func peek_baddies(station: int, round_n: int) -> Array:
	var out: Array = []
	var pz: float = PEEK_STATIONS[station]
	var r: float = PEEK_RADIUS[station % 3]
	var kinds: Array[StringName] = [&"tomato", &"waddler", &"goose", &"banana"]
	var n := mini(4 + round_n, 6)
	for i in n:
		var row := i / 4
		var cx: float = PEEK_COVER_X[i % 4]
		var side := 1.0 if (i + station) % 2 == 0 else -1.0
		var spot := _hide_spot(Vector2(0.0, pz), Vector2(cx, pz - PEEK_COVER_DIST), r, 1.8 + float(row) * 3.0, side, PEEK_LEAN[station % 3])
		out.append([kinds[(i + station) % kinds.size()], spot])
	return out


## Where to stand behind a round cover so you are hidden from `cam` but a sideways lean of `want_lean` reveals you.
static func _hide_spot(cam: Vector2, cover: Vector2, r: float, behind: float, side: float, want_lean: float) -> Vector3:
	var to_c := cover - cam
	var dist_c := to_c.length()
	var th0 := atan2(to_c.x, -to_c.y)                    # angle from straight ahead (-z)
	var dist_b := dist_c + behind
	var h := 0.97
	var spot := Vector2.ZERO
	while h > 0.4:
		var th := th0 + asin(minf(h * r / dist_c, 0.99)) * side
		spot = Vector2(cam.x + dist_b * sin(th), cam.y - dist_b * cos(th))
		if _lean_to_reveal(cam, cover, r, spot) >= want_lean:
			break
		h -= 0.02
	return Vector3(spot.x, 0.2, spot.y)


## Smallest sideways camera shift (either way) that gives a clear sight line past a round cover. 99 = never.
static func _lean_to_reveal(cam: Vector2, cover: Vector2, r: float, spot: Vector2) -> float:
	for k in range(0, 81):
		var d := float(k) * 0.05
		for sgn in [1.0, -1.0]:
			if Geometry2D.segment_intersects_circle(Vector2(cam.x + sgn * d, cam.y), spot, cover, r) < 0.0:
				return d
	return 99.0


## 7  NOD FLIGHT: just an environment. The FlightRig builds its own endless course and ground.
static func _flight(_L: MainLevel) -> Dictionary:
	return {
		"name": "Nod Flight", "half": 40.0, "spawn": Vector3(0, 0.1, 0),
		"sky_top": Color(0.25, 0.45, 0.9), "sky_horizon": Color(1.0, 0.86, 0.72), "sky_ground": Color(0.55, 0.7, 0.5),
		"fog": Color(0.95, 0.86, 0.76), "fog_density": 0.003, "ambient": 1.0,
		"sun_color": Color(1.0, 0.92, 0.8), "sun_energy": 1.4, "sun_rot": Vector3(-35, -40, 0),
		"glow": 0.0, "saturation": 1.15,
		"prop_kinds": [&"crate"] as Array[StringName],
	}


## 8  DOWNHILL: just an environment. The DownhillRig builds its own terrain, forest walls and openings.
static func _downhill(_L: MainLevel) -> Dictionary:
	return {
		"name": "Downhill Lanes", "half": 40.0, "spawn": Vector3(0, 0.1, 0),
		"sky_top": Color(0.18, 0.42, 0.9), "sky_horizon": Color(0.98, 0.84, 0.72), "sky_ground": Color(0.8, 0.85, 0.95),
		"fog": Color(0.78, 0.82, 0.95), "fog_density": 0.0012, "fog_sky": 0.05,
		"ambient": 0.62, "ambient_color": Color(0.66, 0.75, 0.97), "exposure": 1.05,
		"sun_color": Color(1.0, 0.88, 0.72), "sun_energy": 1.9, "sun_rot": Vector3(-26, 205, 0),
		"sun_disc": 38.0, "sun_curve": 0.1, "shadows": true, "shadow_dist": 130.0, "glow_on": true, "glow": 0.3,
		"saturation": 1.1, "contrast": 1.08,
		"prop_kinds": [&"crate"] as Array[StringName],
	}


## 9  OCULAR TRANCE: just an environment (a dusk void). The TranceRig builds the arena.
static func _trance(_L: MainLevel) -> Dictionary:
	return {
		"name": "Ocular Trance", "half": 40.0, "spawn": Vector3(0, 0.1, 0),
		"sky_top": Color(0.04, 0.02, 0.14), "sky_horizon": Color(0.42, 0.16, 0.45), "sky_ground": Color(0.08, 0.04, 0.16),
		"fog": Color(0.2, 0.1, 0.32), "fog_density": 0.012, "fog_sky": 0.2,
		"ambient": 0.8, "ambient_color": Color(0.45, 0.38, 0.9), "exposure": 1.0,
		"sun_color": Color(0.85, 0.75, 1.0), "sun_energy": 0.7, "sun_rot": Vector3(-50, 30, 0),
		"glow_on": true, "glow": 0.9, "saturation": 1.2, "contrast": 1.05,
		"prop_kinds": [&"crate"] as Array[StringName],
	}


## 10  GAZE TEST: a dark void; the rig draws everything in 2D.
static func _gaze_test(_L: MainLevel) -> Dictionary:
	return {
		"name": "Gaze Test", "half": 40.0, "spawn": Vector3(0, 0.1, 0),
		"sky_top": Color(0.02, 0.03, 0.08), "sky_horizon": Color(0.04, 0.05, 0.1), "sky_ground": Color(0.03, 0.04, 0.08),
		"fog": Color(0.04, 0.05, 0.1), "fog_density": 0.0, "ambient": 0.5, "exposure": 1.0,
		"sun_color": Color(1, 1, 1), "sun_energy": 0.2, "sun_rot": Vector3(-50, 30, 0),
		"glow": 0.0, "saturation": 1.0,
		"prop_kinds": [&"crate"] as Array[StringName],
	}


static func _peek(L: MainLevel) -> Dictionary:
	var ground := Color(0.55, 0.62, 0.42)
	L.box(Vector3(46, 1, 100), Vector3(0, -0.5, -2), ground)
	var wall := Color(0.85, 0.78, 0.6)
	L.box(Vector3(1, 7, 100), Vector3(23, 3.5, -2), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(1, 7, 100), Vector3(-23, 3.5, -2), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(46, 7, 1), Vector3(0, 3.5, -52), wall, Vector3.ZERO, 0.0, true, false)
	L.box(Vector3(46, 7, 1), Vector3(0, 3.5, 48), wall, Vector3.ZERO, 0.0, true, false)
	for i in PEEK_STATIONS.size():
		var pz: float = PEEK_STATIONS[i]
		for cx in PEEK_COVER_X:
			var base := Vector3(cx, 0.0, pz - PEEK_COVER_DIST)
			match i % 3:
				0:
					L.cyl(PEEK_RADIUS[0], 2.8, base + Vector3(0, 1.4, 0), Color(0.52, 0.5, 0.46))
				1:
					L.cyl(PEEK_RADIUS[1], 3.0, base + Vector3(0, 1.5, 0), Color(0.62, 0.45, 0.3))
				_:
					L.cyl(PEEK_RADIUS[2], 3.4, base + Vector3(0, 1.7, 0), Color(0.45, 0.52, 0.45))
	return {
		"name": "Peek Range", "half": 22.0, "spawn": Vector3(0, 0.1, 22.0),
		"sky_top": Color(0.35, 0.6, 0.95), "sky_horizon": Color(0.92, 0.95, 1.0), "sky_ground": Color(0.5, 0.7, 0.45),
		"fog": Color(0.8, 0.9, 1.0), "fog_density": 0.0, "ambient": 1.0,
		"sun_color": Color(1.0, 0.95, 0.85), "sun_energy": 1.5, "sun_rot": Vector3(-50, -30, 0),
		"glow": 0.0, "saturation": 1.1,
		"prop_kinds": [&"crate"] as Array[StringName],
	}


static func _hue(i: int, n: int, s: float = 0.8, v: float = 1.0) -> Color:
	return Color.from_hsv(float(i) / float(n), s, v)


static func _ring_points(n: int, radius: float, y: float = 0.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector3(cos(a) * radius, y, sin(a) * radius))
	return out


# ==========================================================================
# 0  BACKYARD BBQ SHOWDOWN
# ==========================================================================
static func _backyard(L: MainLevel) -> Dictionary:
	var wood := Color(0.62, 0.42, 0.24)
	L.box(Vector3(70, 1, 70), Vector3(0, -0.5, 0), Color(0.45, 0.82, 0.35))
	var hedge := Color(0.16, 0.5, 0.2)
	L.box(Vector3(72, 16, 2), Vector3(0, 8, 35), hedge)
	L.box(Vector3(72, 16, 2), Vector3(0, 8, -35), hedge)
	L.box(Vector3(2, 16, 72), Vector3(35, 8, 0), hedge)
	L.box(Vector3(2, 16, 72), Vector3(-35, 8, 0), hedge)
	for i in range(-13, 14):
		var o := i * 2.5
		L.box(Vector3(1.8, 1.7, 0.15), Vector3(o, 0.85, 33.8), Color(0.97, 0.97, 0.95), Vector3.ZERO, 0.0, false, false)
		L.box(Vector3(0.15, 1.7, 1.8), Vector3(33.8, 0.85, o), Color(0.97, 0.97, 0.95), Vector3.ZERO, 0.0, false, false)
		L.box(Vector3(0.15, 1.7, 1.8), Vector3(-33.8, 0.85, o), Color(0.97, 0.97, 0.95), Vector3.ZERO, 0.0, false, false)

	# The house + deck
	L.box(Vector3(34, 12, 9), Vector3(0, 6, -30), Color(0.96, 0.9, 0.78))
	L.prism(Vector3(11, 6, 38), Vector3(0, 15, -30), Color(0.7, 0.25, 0.2), Vector3(0, 90, 0))
	for x in [-11, -5, 5, 11]:
		L.box(Vector3(3, 3, 0.2), Vector3(x, 6.5, -25.4), Color(1.0, 0.88, 0.45), Vector3.ZERO, 1.8, false, false)
	L.box(Vector3(3, 5, 0.2), Vector3(0, 2.5, -25.4), Color(0.45, 0.28, 0.15), Vector3.ZERO, 0.0, false, false)
	L.light(Vector3(0, 6, -22), Color(1.0, 0.85, 0.55), 3.0, 18.0)
	L.box(Vector3(24, 3, 9), Vector3(0, 1.5, -20.5), wood)
	L.ramp(0, -6.0, -1, 3.0, 16, 7, wood)
	for x in range(-11, 12, 2):
		L.box(Vector3(0.2, 1.0, 0.2), Vector3(x, 3.5, -16.2), wood, Vector3.ZERO, 0.0, false, false)
	L.keepout(0, -24, 36, 14)
	L.keepout(0, -11, 8, 12)

	# Slip-n-slide (yellow tarp ramp) + soap bubbles
	L.ramp(-14, 10, -1, 3.5, 14, 5, Color(1.0, 0.9, 0.2))
	L.box(Vector3(5, 3.5, 4), Vector3(-14, 1.75, -5.8), Color(1.0, 0.9, 0.2))
	L.zone(&"slip", Vector3(-14, 1.9, 3.0), Vector3(5, 4, 14.5))
	L.particles(Vector3(-14, 2.5, 3), Vector3(5, 3, 14), 40, 4.0, Vector3(0, 0.4, 0), Color(0.85, 0.95, 1.0, 0.6), 0.18)
	L.keepout(-14, 0, 6, 18)

	# Trampolines
	for t in [Vector2(16, 8), Vector2(-24, -8), Vector2(24, -18)]:
		L.cyl(2.4, 0.5, Vector3(t.x, 0.25, t.y), Color(0.1, 0.1, 0.12), 0.0, false)
		L.cyl(2.1, 0.1, Vector3(t.x, 0.55, t.y), Color(0.25, 0.3, 0.6), 0.3, false)
		L.torus(0.08, 2.4, Vector3(t.x, 0.6, t.y), Color(0.95, 0.25, 0.25), Vector3.ZERO, 0.4)
		L.zone(&"bounce", Vector3(t.x, 0.9, t.y), Vector3(4.2, 1.2, 4.2), Vector3(0, 22, 0))
		L.keepout(t.x, t.y, 5.0, 5.0)

	# Kiddie pool (water drag)
	L.cyl(5.0, 0.3, Vector3(-19, 0.15, -13), Color(0.3, 0.65, 1.0), 0.7, false)
	L.torus(0.4, 5.2, Vector3(-19, 0.35, -13), Color(0.95, 0.45, 0.2))
	L.torus(0.3, 1.0, Vector3(-17.5, 0.5, -11.5), Color(1.0, 0.9, 0.2))
	L.zone(&"sticky", Vector3(-19, 0.6, -13), Vector3(9, 1.2, 9), Vector3.ZERO, Color(0.3, 0.65, 1.0, 0.3))
	L.keepout(-19, -13, 11, 11)

	# Sprinkler boost strip
	L.zone(&"boost", Vector3(10, 0.5, -4), Vector3(3, 1, 14), Vector3(0, 0, -1))
	for z in range(-9, 3, 4):
		L.cyl(0.12, 0.5, Vector3(10, 0.25, z), Color(0.7, 0.7, 0.75), 0.0, false)
	L.light(Vector3(10, 1.5, -4), Color(0.3, 0.9, 1.0), 2.0, 9.0)
	L.keepout(10, -4, 4, 15)

	# Picnic tables, umbrellas, grills, trees, gnomes
	for t in [Vector2(8, 18), Vector2(-6, 19), Vector2(22, -6)]:
		L.box(Vector3(3.4, 1.1, 1.8), Vector3(t.x, 0.55, t.y), Color(0.9, 0.2, 0.2))
		L.box(Vector3(3.4, 0.12, 0.5), Vector3(t.x, 0.35, t.y + 1.4), wood, Vector3.ZERO, 0.0, false, false)
		L.cyl(0.06, 3.6, Vector3(t.x, 1.8, t.y), Color(0.9, 0.9, 0.9), 0.0, false)
		L.cone(2.2, 0.7, Vector3(t.x, 3.7, t.y), Color(1.0, 0.8, 0.2))
		L.keepout(t.x, t.y, 4.0, 3.0)
	var first_grill := true
	for g in [Vector2(-26, 12), Vector2(26, 16), Vector2(6, -12)]:
		L.box(Vector3(1.6, 1.2, 1.0), Vector3(g.x, 0.6, g.y), Color(0.18, 0.18, 0.2))
		L.ball(0.62, Vector3(g.x, 1.3, g.y), Color(0.12, 0.12, 0.14), 0.0, false)
		L.box(Vector3(1.3, 0.1, 0.8), Vector3(g.x, 1.25, g.y), Color(1.0, 0.4, 0.1), Vector3.ZERO, 2.5, false, false)
		L.light(Vector3(g.x, 1.8, g.y), Color(1.0, 0.5, 0.15), 2.2, 7.0, true)
		if first_grill:
			first_grill = false
			L.particles(Vector3(g.x, 2.0, g.y), Vector3(0.6, 0.2, 0.6), 24, 3.0, Vector3(0.3, 1.6, 0.2), Color(0.7, 0.7, 0.72, 0.6), 0.25)
		L.keepout(g.x, g.y, 2.4, 2.0)
	for t in [Vector2(-29, -24), Vector2(29, -26), Vector2(-29, 24), Vector2(29, 26), Vector2(21, -30), Vector2(-9, -12)]:
		L.cyl(0.6, 7.0, Vector3(t.x, 3.5, t.y), Color(0.4, 0.27, 0.15))
		L.ball(3.6, Vector3(t.x, 8.5, t.y), Color(0.2, 0.62, 0.25), 0.0, false)
		L.ball(2.6, Vector3(t.x + 2.0, 7.4, t.y + 1.0), Color(0.25, 0.7, 0.3), 0.0, false)
		L.keepout(t.x, t.y, 2.4, 2.4)
	for i in 9:
		var gp := Vector3(randf_range(-30, 30), 0, randf_range(-5, 30))
		L.cone(0.25, 0.7, gp + Vector3(0, 0.95, 0), Color(0.9, 0.15, 0.15))
		L.cyl(0.22, 0.6, gp + Vector3(0, 0.3, 0), Color(0.2, 0.4, 0.9), 0.0, false)
		L.ball(0.18, gp + Vector3(0, 0.55, -0.15), Color.WHITE, 0.0, false)
	# String lights between two poles
	for px in [-31.0, 31.0]:
		L.cyl(0.1, 7.2, Vector3(px, 3.6, -10), Color(0.35, 0.25, 0.15), 0.0, false)
	for i in 28:
		var t := float(i) / 27.0
		L.ball(0.2, Vector3(lerpf(-31.0, 31.0, t), 7.0 - 1.4 * sin(t * PI), -10), _hue(i, 28), 3.0, false)
	for x in [-20.0, 0.0, 20.0]:
		L.light(Vector3(x, 6.0, -10), Color(1.0, 0.85, 0.6), 1.4, 16.0)

	return {
		"name": "Backyard BBQ Showdown", "half": 34.0, "spawn": Vector3(0, 0.1, 28),
		"sky_top": Color(0.25, 0.55, 0.95), "sky_horizon": Color(0.9, 0.95, 1.0), "sky_ground": Color(0.5, 0.75, 0.45),
		"fog": Color(0.8, 0.9, 1.0), "fog_density": 0.004, "ambient": 0.9,
		"sun_color": Color(1.0, 0.93, 0.78), "sun_energy": 1.7, "sun_rot": Vector3(-42, -35, 0),
		"glow": 0.6, "saturation": 1.15,
		"prop_kinds": [&"crate", &"barrel", &"ball", &"duck", &"duck"] as Array[StringName],
	}


# ==========================================================================
# 1  SUPERMARKET GRAVEYARD SHIFT
# ==========================================================================
static func _market(L: MainLevel) -> Dictionary:
	L.box(Vector3(66, 1, 66), Vector3(0, -0.5, 0), Color(0.88, 0.93, 0.9))
	var wall := Color(0.3, 0.5, 0.55)
	L.box(Vector3(66, 15, 1), Vector3(0, 7.5, -32.5), wall)
	L.box(Vector3(66, 15, 1), Vector3(0, 7.5, 32.5), wall)
	L.box(Vector3(1, 15, 66), Vector3(32.5, 7.5, 0), wall)
	L.box(Vector3(1, 15, 66), Vector3(-32.5, 7.5, 0), wall)
	L.box(Vector3(66, 1, 66), Vector3(0, 15.0, 0), Color(0.22, 0.26, 0.3))
	# Fluorescent grid (a few flicker)
	var idx := 0
	for x in [-20.0, 0.0, 20.0]:
		for z in [-20.0, 0.0, 20.0]:
			L.box(Vector3(5, 0.15, 1.3), Vector3(x, 14.4, z), Color(1.0, 1.0, 0.95), Vector3.ZERO, 3.0, false, false)
			L.light(Vector3(x, 12.8, z), Color(0.85, 1.0, 0.92), 2.4, 26.0, idx % 3 == 0)
			idx += 1

	# Shelves with product grids, cart ramps to the shelf tops
	var shelf_xs := [-22.0, -11.0, 11.0, 22.0]
	for x: float in shelf_xs:
		L.box(Vector3(2.0, 4.0, 14.0), Vector3(x, 2.0, -8), Color(0.75, 0.8, 0.9))
		for tier in 3:
			for i in 7:
				for side in [-1.0, 1.0]:
					L.box(Vector3(0.5, 0.8, 1.5), Vector3(x + side * 1.15, 0.8 + tier * 1.2, -14.0 + i * 1.9),
						Color.from_hsv(randf(), 0.7, 1.0), Vector3.ZERO, 0.25, false, false)
		L.ramp(x, 11.3, -1, 4.0, 18, 2.4, Color(0.9, 0.2, 0.25))
		L.keepout(x, -8, 3.0, 15.0)
		L.keepout(x, 5, 3.2, 13.0)

	# Freezer wall: icy goo in front of it
	for x in [-21.0, -7.0, 7.0, 21.0]:
		L.box(Vector3(10, 3.2, 2.6), Vector3(x, 1.6, -30.6), Color(0.85, 0.95, 1.0))
		L.box(Vector3(9.4, 2.4, 0.15), Vector3(x, 1.7, -29.2), Color(0.5, 0.9, 1.0), Vector3.ZERO, 1.2, false, false)
		L.light(Vector3(x, 3.0, -28.0), Color(0.5, 0.85, 1.0), 1.6, 9.0)
	L.zone(&"sticky", Vector3(0, 0.6, -26.5), Vector3(56, 1.2, 4.5), Vector3.ZERO, Color(0.55, 0.85, 1.0, 0.25))
	L.keepout(0, -30, 60, 6)

	# Wet-floor slip patches + signs
	for p in [Vector3(0, 0.5, 9), Vector3(-16.5, 0.5, -6), Vector3(16.5, 0.5, -6)]:
		L.zone(&"slip", p, Vector3(6.5, 1, 11 if p.z > 0 else 13), Vector3.ZERO, Color(1.0, 0.95, 0.5, 0.3))
		L.cone(0.35, 0.9, p + Vector3(3.6, 0.0, 0), Color(1.0, 0.85, 0.1), 0.6)
		L.cone(0.35, 0.9, p + Vector3(-3.6, 0.0, 0), Color(1.0, 0.85, 0.1), 0.6)

	# Checkout lanes with conveyor boost belts
	for x in [-9.0, 9.0]:
		L.box(Vector3(1.8, 1.1, 7.0), Vector3(x, 0.55, 20), Color(0.3, 0.35, 0.45))
		L.zone(&"boost", Vector3(x, 1.75, 20), Vector3(1.2, 1, 6.5), Vector3(0, 0, -1))
		L.box(Vector3(0.8, 0.6, 0.8), Vector3(x + 1.3, 1.4, 22), Color(0.15, 0.15, 0.2), Vector3.ZERO, 0.0, false, false)
		L.box(Vector3(0.6, 0.35, 0.05), Vector3(x + 1.3, 1.9, 21.6), Color(0.2, 1.0, 0.5), Vector3.ZERO, 2.0, false, false)
		L.keepout(x, 20, 3.0, 8.0)

	# Mattress-pallet trampolines
	for z in [-18.0, -3.0]:
		for i in 4:
			L.box(Vector3(5, 0.25, 5), Vector3(0, 0.15 + i * 0.25, z), _hue(i, 4, 0.35, 1.0), Vector3(0, i * 9.0, 0), 0.0, false, false)
		L.zone(&"bounce", Vector3(0, 0.7, z), Vector3(5, 1.2, 5), Vector3(0, 22, 0))
		L.keepout(0, z, 6, 6)

	# Hanging SALE banners + neon
	for x in [-16.0, 0.0, 16.0]:
		L.box(Vector3(7, 2.0, 0.12), Vector3(x, 10.0, -8), _hue(int(x) + 20, 40, 0.9, 1.0), Vector3.ZERO, 2.0, false, false)
		L.cyl(0.03, 4.0, Vector3(x - 3.0, 12.0, -8), Color.GRAY, 0.0, false)
		L.cyl(0.03, 4.0, Vector3(x + 3.0, 12.0, -8), Color.GRAY, 0.0, false)
	L.light(Vector3(0, 9, 26), Color(1.0, 0.2, 0.6), 2.0, 14.0)
	L.light(Vector3(-26, 8, 0), Color(0.2, 0.6, 1.0), 2.0, 14.0)

	return {
		"name": "Supermarket Graveyard Shift", "half": 32.0, "spawn": Vector3(0, 0.1, 28),
		"sky_top": Color(0.04, 0.04, 0.09), "sky_horizon": Color(0.08, 0.1, 0.16), "sky_ground": Color(0.03, 0.03, 0.05),
		"fog": Color(0.12, 0.16, 0.2), "fog_density": 0.012, "ambient": 0.4,
		"sun_color": Color(0.5, 0.6, 1.0), "sun_energy": 0.15, "sun_rot": Vector3(-70, 20, 0),
		"glow": 1.0, "saturation": 1.2, "exposure": 1.1,
		"prop_kinds": [&"crate", &"barrel", &"ball", &"duck", &"crate"] as Array[StringName],
	}


# ==========================================================================
# 2  CANDY KINGDOM MELTDOWN
# ==========================================================================
static func _candy(L: MainLevel) -> Dictionary:
	L.box(Vector3(74, 1, 74), Vector3(0, -0.5, 0), Color(1.0, 0.72, 0.86))
	var cake := Color(1.0, 0.93, 0.8)
	for w in [Vector4(0, 8, 37, 0), Vector4(0, 8, -37, 0), Vector4(37, 8, 0, 1), Vector4(-37, 8, 0, 1)]:
		var sz := Vector3(76, 16, 2) if w.w == 0.0 else Vector3(2, 16, 76)
		L.box(sz, Vector3(w.x, w.y, w.z), cake)
		L.box(sz + (Vector3(0, 0.6, 0.6) if w.w == 0.0 else Vector3(0.6, 0.6, 0)), Vector3(w.x, 15.9, w.z), Color(1.0, 0.45, 0.7), Vector3.ZERO, 0.2, false, false)
	for i in 22:
		var a := TAU * float(i) / 22.0
		L.ball(0.45, Vector3(cos(a) * 35.2, 14.6, sin(a) * 35.2).clamp(Vector3(-35.3, 0, -35.3), Vector3(35.3, 20, 35.3)), Color(1.0, 0.5, 0.75), 0.2, false)

	# Chocolate river across the middle, wafer bridges
	L.box(Vector3(74, 0.1, 9), Vector3(0, 0.05, 0), Color(0.35, 0.2, 0.1), Vector3.ZERO, 0.15, false, false)
	L.zone(&"sticky", Vector3(0, 0.6, 0), Vector3(74, 1.2, 9), Vector3.ZERO, Color(0.35, 0.18, 0.08, 0.15), false)
	L.light(Vector3(0, 1.5, 0), Color(1.0, 0.6, 0.3), 1.5, 14.0)
	for x in [-16.0, 16.0]:
		L.box(Vector3(5, 0.5, 10), Vector3(x, 0.25, 0), Color(0.93, 0.78, 0.5))
		L.box(Vector3(5.2, 0.12, 0.3), Vector3(x, 0.55, -4.9), Color(0.7, 0.5, 0.25), Vector3.ZERO, 0.0, false, false)
	L.keepout(0, 0, 76, 10)

	# Rainbow slide -> candy platform
	var rainbow := [Color(1, 0.2, 0.2), Color(1, 0.55, 0.1), Color(1, 0.95, 0.2), Color(0.3, 0.9, 0.3), Color(0.2, 0.7, 1), Color(0.4, 0.3, 1), Color(0.85, 0.3, 0.95)]
	var z_top := 0.0
	for i in rainbow.size():
		z_top = L.ramp(-4.0 + i * (8.0 / 7.0) + 0.57, -10.0, -1, 6.0, 20, 8.0 / 7.0 + 0.02, rainbow[i])
	L.box(Vector3(14, 6, 8), Vector3(0, 3, z_top - 3.7), Color(0.75, 0.9, 1.0))
	L.keepout(0, -22, 16, 30)
	for i in 6:
		L.ball(0.3, Vector3(-5 + i * 2.0, 6.4, z_top - 3.7), _hue(i, 6), 1.0, false)

	# Marshmallow bounce pads
	for p in [Vector2(20, 14), Vector2(-20, 14), Vector2(20, -16), Vector2(-20, -16), Vector2(28, 26)]:
		L.cyl(2.2, 0.9, Vector3(p.x, 0.45, p.y), Color(1.0, 0.97, 0.97), 0.3, false)
		L.cyl(2.3, 0.15, Vector3(p.x, 0.9, p.y), Color(1.0, 0.6, 0.8), 0.6, false)
		L.zone(&"bounce", Vector3(p.x, 1.0, p.y), Vector3(4.2, 1.2, 4.2), Vector3(0, 24, 0))
		L.keepout(p.x, p.y, 5, 5)

	# Fruit-roll boost strips
	for x in [-28.0, 28.0]:
		L.zone(&"boost", Vector3(x, 0.5, -20), Vector3(3, 1, 22), Vector3(0, 0, -1), Color(0.3, 0.6, 1.0, 0.5))
		L.keepout(x, -20, 4, 23)

	# Gumdrop hills (spherical bumps), jawbreakers, lollipop trees, candy canes
	var hills := [Vector3(-26, 0, 20), Vector3(-10, 0, 24), Vector3(26, 0, 6), Vector3(-28, 0, -26), Vector3(12, 0, -28), Vector3(30, 0, -8), Vector3(-30, 0, 6)]
	for i in hills.size():
		var r := randf_range(3.0, 5.0)
		var h: Vector3 = hills[i]
		L.ball(r, Vector3(h.x, -r * 0.45, h.z), _hue(i * 3 + 1, 22, 0.65, 1.0), 0.25)
		L.ball(r * 0.35, Vector3(h.x - r * 0.2, r * 0.45, h.z - r * 0.2), Color(1, 1, 1, 1), 0.8, false)
		L.keepout(h.x, h.z, r * 2.0, r * 2.0)
	for p in [Vector2(8, 18), Vector2(-14, 8), Vector2(14, 8)]:
		L.ball(2.2, Vector3(p.x, 0.9, p.y), _hue(int(p.x) + 30, 40, 0.5, 1.0), 0.2)
		L.torus(0.12, 2.25, Vector3(p.x, 0.9, p.y), Color.WHITE, Vector3(90, 0, 0))
		L.torus(0.12, 2.0, Vector3(p.x, 1.4, p.y), Color(1, 0.3, 0.5), Vector3(60, 0, 0))
		L.keepout(p.x, p.y, 5.0, 5.0)
	for i in 14:
		var tp := Vector3(randf_range(-31, 31), 0, randf_range(-31, 31))
		if absf(tp.x) < 10.0 and tp.z < 8.0 and tp.z > -30.0:
			continue
		L.cyl(0.25, 5.0, tp + Vector3(0, 2.5, 0), Color(0.95, 0.95, 0.95))
		L.cyl(1.8, 0.35, tp + Vector3(0, 5.5, 0), _hue(i, 14, 0.7, 1.0), 0.9, false, Vector3(90, randf() * 180.0, 0))
		L.torus(0.1, 1.2, tp + Vector3(0, 5.5, 0), Color.WHITE, Vector3(90, 0, 0))
		L.keepout(tp.x, tp.z, 1.6, 1.6)
	for i in 10:
		var cp := Vector3(randf_range(-33, 33), 0, randf_range(-33, 33))
		if cp.z > 18.0 and absf(cp.x) < 12.0:
			continue
		for k in 4:
			L.cyl(0.55, 1.8, cp + Vector3(0, 0.9 + k * 1.8, 0), Color(1, 0.95, 0.95) if k % 2 == 0 else Color(0.95, 0.2, 0.3), 0.0, false)
	# A giant donut, gummy bears
	L.torus(1.6, 4.5, Vector3(24, 3.0, -20), Color(0.95, 0.7, 0.4), Vector3(70, 20, 0))
	L.torus(1.5, 4.6, Vector3(24, 3.3, -20), Color(1.0, 0.45, 0.75), Vector3(70, 20, 0), 0.4)
	for i in 8:
		var gp := Vector3(randf_range(-30, 30), 0, randf_range(8, 32))
		var gc := _hue(i, 8, 0.8, 1.0)
		L.cyl(0.35, 0.9, gp + Vector3(0, 0.55, 0), gc, 0.4, false)
		L.ball(0.32, gp + Vector3(0, 1.15, 0), gc, 0.4, false)
		L.ball(0.12, gp + Vector3(-0.2, 1.4, 0), gc, 0.4, false)
		L.ball(0.12, gp + Vector3(0.2, 1.4, 0), gc, 0.4, false)
	L.particles(Vector3(0, 18, 0), Vector3(70, 1, 70), 260, 9.0, Vector3(0, -1.6, 0), Color(1, 1, 1, 1), 0.07)
	for p in [Vector3(-24, 5, 24), Vector3(24, 5, 24), Vector3(-24, 5, -24), Vector3(24, 5, -24), Vector3(0, 5, 14)]:
		L.light(p, _hue(int(p.x + p.z), 17, 0.6, 1.0), 2.5, 20.0)

	return {
		"name": "Candy Kingdom Meltdown", "half": 36.0, "spawn": Vector3(0, 0.1, 30),
		"sky_top": Color(1.0, 0.55, 0.85), "sky_horizon": Color(1.0, 0.92, 0.96), "sky_ground": Color(1.0, 0.8, 0.9),
		"fog": Color(1.0, 0.78, 0.92), "fog_density": 0.007, "ambient": 0.7,
		"sun_color": Color(1.0, 0.92, 0.95), "sun_energy": 1.1, "sun_rot": Vector3(-48, 30, 0),
		"glow": 0.55, "saturation": 1.25, "contrast": 1.1, "exposure": 0.85,
		"prop_kinds": [&"ball", &"ball", &"duck", &"crate", &"barrel"] as Array[StringName],
	}


# ==========================================================================
# 3  MOONBASE LOW-G BRAWL
# ==========================================================================
static func _moon(L: MainLevel) -> Dictionary:
	var dust := Color(0.6, 0.6, 0.66)
	L.box(Vector3(78, 1, 78), Vector3(0, -0.5, 0), dust)
	var rock := Color(0.25, 0.25, 0.3)
	L.box(Vector3(80, 34, 2), Vector3(0, 17, 39), rock)
	L.box(Vector3(80, 34, 2), Vector3(0, 17, -39), rock)
	L.box(Vector3(2, 34, 80), Vector3(39, 17, 0), rock)
	L.box(Vector3(2, 34, 80), Vector3(-39, 17, 0), rock)
	# Stars + Earth
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Roster.sphere(0.5)
	mm.instance_count = 220
	for i in 220:
		var d := Vector3(randf_range(-1, 1), randf_range(0.05, 1), randf_range(-1, 1)).normalized() * 220.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.4, 1.6)), d))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stars.material_override = smat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	L.decor.add_child(stars)
	L.ball(34.0, Vector3(-110, 90, -170), Color(0.2, 0.45, 0.95), 0.5, false)
	L.ball(35.0, Vector3(-110, 90, -171), Color(1, 1, 1, 1), 0.0, false).scale = Vector3(1.0, 1.0, 0.2)

	# Reactor tower: ramp -> base disc -> bounce pad -> upper disc -> pad -> top
	L.ramp(0, 7.0, -1, 3.0, 20, 6.0, Color(0.35, 0.4, 0.5))
	L.cyl(8.0, 3.0, Vector3(0, 1.5, -12), Color(0.55, 0.6, 0.7))
	L.cyl(5.0, 3.0, Vector3(0, 4.5, -12), Color(0.45, 0.5, 0.62))
	L.cyl(2.6, 3.0, Vector3(0, 7.5, -12), Color(0.4, 0.45, 0.6))
	L.cyl(1.4, 4.0, Vector3(0, 11.0, -12), Color(0.3, 1.0, 1.0), 2.5, false)
	L.light(Vector3(0, 12, -12), Color(0.3, 1.0, 1.0), 4.0, 26.0)
	L.zone(&"bounce", Vector3(4.2, 3.4, -12), Vector3(2.5, 1.0, 2.5), Vector3(0, 14, -2), Color(0.2, 1.0, 1.0, 0.5))
	L.zone(&"bounce", Vector3(0, 6.4, -9), Vector3(2.2, 1.0, 2.2), Vector3(0, 11, -2), Color(0.2, 1.0, 1.0, 0.5))
	L.keepout(0, -12, 18, 22)
	L.keepout(0, 3, 7, 12)
	L.particles(Vector3(0, 12, -12), Vector3(1.5, 4, 1.5), 40, 2.0, Vector3(0, 1.0, 0), Color(0.4, 1.0, 1.0), 0.1)

	# Updraft vents with grates, launch pads, boost landing strips
	for p in [Vector2(-20, -8), Vector2(22, -10), Vector2(-24, 14), Vector2(24, 12)]:
		L.cyl(2.0, 0.3, Vector3(p.x, 0.15, p.y), Color(0.15, 0.15, 0.2), 0.0, false)
		L.cyl(1.7, 0.1, Vector3(p.x, 0.33, p.y), Color(0.3, 0.9, 1.0), 1.5, false)
		L.zone(&"vent", Vector3(p.x, 6.0, p.y), Vector3(3.4, 12, 3.4))
		L.particles(Vector3(p.x, 5.0, p.y), Vector3(2.5, 10, 2.5), 30, 2.5, Vector3(0, 3.0, 0), Color(0.7, 0.95, 1.0, 0.6), 0.09)
		L.light(Vector3(p.x, 1.0, p.y), Color(0.3, 0.9, 1.0), 2.0, 8.0)
		L.keepout(p.x, p.y, 4.5, 4.5)
	for a in [0.0, 120.0, 240.0]:
		var dir := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a)))
		var c := dir * 22.0 + Vector3(0, 0.5, 6)
		L.zone(&"boost", c, Vector3(3, 1, 10), dir * -1.0, Color(1.0, 0.6, 0.2, 0.5))
	for p in [Vector3(-8, 0.5, 20), Vector3(14, 0.5, 24)]:
		L.zone(&"slip", p, Vector3(10, 1, 7), Vector3.ZERO, Color(0.8, 0.95, 1.0, 0.35))
		L.keepout(p.x, p.z, 11, 8)

	# Boulders, dome base, solar farm, antennas with blinkers
	for i in 12:
		var bp := Vector3(randf_range(-34, 34), 0, randf_range(-34, 34))
		if absf(bp.x) < 12.0 and bp.z < 12.0 and bp.z > -24.0:
			continue
		var r := randf_range(1.5, 3.0)
		L.ball(r, Vector3(bp.x, r * 0.3, bp.z), dust.darkened(randf_range(0.0, 0.35)))
		L.keepout(bp.x, bp.z, r * 2.0, r * 2.0)
	L.box(Vector3(10, 4, 8), Vector3(-26, 2, -26), Color(0.8, 0.82, 0.88))
	L.ball(5.2, Vector3(-26, 3.5, -26), Color(0.6, 0.9, 1.0, 1), 0.3, false)
	L.light(Vector3(-26, 5, -26), Color(0.6, 0.9, 1.0), 3.0, 14.0)
	L.keepout(-26, -26, 12, 10)
	for i in 8:
		var sp := Vector3(14 + (i % 4) * 4.0, 0.9, -28 + (i / 4) * 5.0)
		L.box(Vector3(3.0, 0.12, 2.2), sp, Color(0.1, 0.2, 0.6), Vector3(-30, 0, 0), 0.5, false, false)
		L.cyl(0.08, 0.9, sp - Vector3(0, 0.45, 0), Color.GRAY, 0.0, false)
	L.keepout(21, -26, 18, 12)
	for p in [Vector2(-30, 8), Vector2(30, -4), Vector2(30, 28), Vector2(-14, -32)]:
		L.cyl(0.18, 10.0, Vector3(p.x, 5.0, p.y), Color(0.8, 0.8, 0.85), 0.0, false)
		L.ball(0.3, Vector3(p.x, 10.2, p.y), Color(1.0, 0.2, 0.2), 4.0, false)
		L.light(Vector3(p.x, 10.2, p.y), Color(1.0, 0.2, 0.2), 2.5, 12.0, true)
	for p in [Vector3(-34, 22, -34), Vector3(34, 22, -34), Vector3(-34, 22, 34), Vector3(34, 22, 34)]:
		L.spot(p, Vector3(0, 0, 0), Color(1.0, 0.95, 0.85), 14.0, 80.0, 28.0)
	L.particles(Vector3(0, 6, 0), Vector3(70, 10, 70), 120, 6.0, Vector3(0, 0.3, 0), Color(0.9, 0.9, 1.0, 0.6), 0.05)

	return {
		"name": "Moonbase Low-G Brawl", "half": 38.0, "spawn": Vector3(0, 0.1, 30), "gravity": 0.4,
		"sky_top": Color(0.0, 0.0, 0.02), "sky_horizon": Color(0.02, 0.02, 0.07), "sky_ground": Color(0.02, 0.02, 0.04),
		"fog": Color(0.0, 0.0, 0.0), "fog_density": 0.0, "ambient": 0.25,
		"sun_color": Color(1.0, 1.0, 1.0), "sun_energy": 2.6, "sun_rot": Vector3(-28, -60, 0),
		"glow": 0.5, "saturation": 1.0, "contrast": 1.15, "exposure": 1.15,
		"prop_kinds": [&"crate", &"barrel", &"ball", &"ball", &"duck"] as Array[StringName],
	}


# ==========================================================================
# 4  DISCO INFERNO LAVA LAIR
# ==========================================================================
static func _lava(L: MainLevel) -> Dictionary:
	var obsidian := Color(0.12, 0.08, 0.1)
	# Lava lake (visual + damage zone) and a pit floor so nothing falls forever
	L.box(Vector3(80, 0.2, 80), Vector3(0, -1.5, 0), Color(1.0, 0.35, 0.05), Vector3.ZERO, 2.2, false, false)
	L.zone(&"lava", Vector3(0, -2.4, 0), Vector3(78, 3.2, 78), Vector3.ZERO, Color(0, 0, 0, 0), false)
	L.box(Vector3(80, 1, 80), Vector3(0, -7.5, 0), obsidian)
	var cliff := Color(0.18, 0.1, 0.1)
	L.box(Vector3(84, 26, 4), Vector3(0, 9, 40), cliff)
	L.box(Vector3(84, 26, 4), Vector3(0, 9, -40), cliff)
	L.box(Vector3(4, 26, 84), Vector3(40, 9, 0), cliff)
	L.box(Vector3(4, 26, 84), Vector3(-40, 9, 0), cliff)
	for i in 14:
		var a := TAU * float(i) / 14.0
		L.cone(1.6, 7.0, Vector3(cos(a) * 30.0, 21.0, sin(a) * 30.0), obsidian, 0.0, Vector3(180, 0, 0))
		L.box(Vector3(0.3, 8.0, 0.2), Vector3(cos(a) * 37.5, 4.0, sin(a) * 37.5), Color(1.0, 0.4, 0.05), Vector3(0, -rad_to_deg(a), 0), 2.5, false, false)

	# Central disco island + satellites
	var spawns: Array[Vector3] = []
	L.cyl(11.0, 2.0, Vector3(0, -1.0, 0), obsidian)
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			if Vector2(gx, gz).length() <= 4.2:
				var tile := L.box(Vector3(2.4, 0.12, 2.4), Vector3(gx * 2.5, 0.07, gz * 2.5), Color.WHITE, Vector3.ZERO, 0.6, false, false)
				L.disco_tiles.append(tile as MeshInstance3D)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * 22.0, 0, sz * 22.0)
			L.cyl(6.5, 2.0, c + Vector3(0, -1.0, 0), obsidian)
			L.cyl(6.0, 0.1, c + Vector3(0, 0.05, 0), Color(1.0, 0.3, 0.1), 0.8, false)
			L.zone(&"vent", c + Vector3(0, 5.0, 0), Vector3(3.6, 10, 3.6))
			L.particles(c + Vector3(0, 4, 0), Vector3(3, 8, 3), 34, 2.2, Vector3(0, 3.0, 0), Color(1.0, 0.6, 0.2, 0.7), 0.11)
			L.light(c + Vector3(0, 2.0, 0), Color(1.0, 0.4, 0.1), 3.0, 14.0, true)
			for k in 3:
				var pp := c + Vector3(cos(k * 2.1) * 4.6, 3.0, sin(k * 2.1) * 4.6)
				L.cyl(0.8, 6.0, pp, obsidian)
				L.ball(0.35, pp + Vector3(0, 3.3, 0), Color(1.0, 0.45, 0.1), 3.0, false)
			spawns.append(c + Vector3(3, 0.2, 0))
			spawns.append(c + Vector3(-3, 0.2, 2))
			# bridge to center along the diagonal
			var d := Vector3(sx, 0, sz).normalized()
			L.box(Vector3(4.2, 0.5, 13.0), d * 17.0 + Vector3(0, -0.25, 0), Color(0.3, 0.2, 0.18), Vector3(0, rad_to_deg(atan2(d.x, d.z)), 0))
	# Outer ring bridges between satellites + bounce pads on the middle of each
	for s in [-1.0, 1.0]:
		L.box(Vector3(4.2, 0.5, 38.0), Vector3(s * 22.0, -0.25, 0), Color(0.3, 0.2, 0.18))
		L.box(Vector3(38.0, 0.5, 4.2), Vector3(0, -0.25, s * 22.0), Color(0.3, 0.2, 0.18))
		L.zone(&"bounce", Vector3(s * 22.0, 0.5, 0), Vector3(3.2, 1.2, 3.2), Vector3(0, 18, 0), Color(1.0, 0.8, 0.2, 0.6))
		L.zone(&"bounce", Vector3(0, 0.5, s * 22.0), Vector3(3.2, 1.2, 3.2), Vector3(0, 18, 0), Color(1.0, 0.8, 0.2, 0.6))
	for r in _ring_points(6, 7.0):
		spawns.append(r + Vector3(0, 0.3, 0))
	L.spawn_points.append_array(spawns)

	# Disco ball with four rotating coloured spotlights, lava glows, embers
	L.ball(1.4, Vector3(0, 13.0, 0), Color(0.85, 0.85, 0.95), 0.6, false)
	L.cyl(0.05, 6.0, Vector3(0, 17.0, 0), Color.GRAY, 0.0, false)
	var sp := L.spinner(Vector3.ZERO)
	for i in 4:
		var col := _hue(i, 4, 0.9, 1.0)
		var s := L.spot(Vector3(0, 13.0, 0), Vector3(cos(i * PI / 2.0) * 9.0, 0.0, sin(i * PI / 2.0) * 9.0), col, 9.0, 40.0, 22.0)
		s.reparent(sp, true)
	for p in [Vector3(0, 1, 0), Vector3(-30, 0, 0), Vector3(30, 0, 0), Vector3(0, 0, -30), Vector3(0, 0, 30)]:
		L.light(p + Vector3(0, 0.5, 0), Color(1.0, 0.35, 0.08), 4.0, 22.0)
	L.particles(Vector3(0, 2, 0), Vector3(76, 4, 76), 220, 4.0, Vector3(0, 2.5, 0), Color(1.0, 0.55, 0.15), 0.07)

	return {
		"name": "Disco Inferno Lava Lair", "half": 34.0, "spawn": Vector3(0, 0.1, 6),
		"sky_top": Color(0.12, 0.02, 0.03), "sky_horizon": Color(0.85, 0.25, 0.05), "sky_ground": Color(0.25, 0.06, 0.02),
		"fog": Color(0.6, 0.15, 0.05), "fog_density": 0.014, "ambient": 0.55,
		"sun_color": Color(1.0, 0.5, 0.25), "sun_energy": 0.9, "sun_rot": Vector3(-30, 40, 0),
		"glow": 0.9, "saturation": 1.25, "contrast": 1.1, "exposure": 0.9,
		"prop_kinds": [&"crate", &"barrel", &"ball", &"duck", &"crate"] as Array[StringName],
	}
