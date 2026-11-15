class_name TrailCurve
## The trail winds. Everything the game DECIDES still happens on a straight strip (x across, z down the hill): the course, the steering, the collisions and every test are
## unchanged. This class is only about what you SEE: it lays that strip along a curving line across the mountain, so the ground, the trees, the gates, the board and the
## camera all swing left and right through long bends, and the peaks and the sun wheel around you as the trail turns.
##
##   strip point (x, y, z)  ->  world point = centre(s) + x * right(s),  height unchanged,  with s = -z the distance down the trail
##
## The line turns by at most about one degree every 5.5 m (a radius over 300 m), which keeps the inside of a bend from folding over itself: the ground is drawn 150 m
## either side of the middle. The first 120 m are straight, so a run starts the way it always did.

const STEP := 4.0                    # metres between stored points of the line
const LENGTH := 12000.0              # metres of trail laid out (a run is about 4 km; ENDLESS wraps the heading smoothly well before this)
const STRAIGHT_START := 120.0
const EASE_IN := 260.0               # metres over which the bends grow to full size after the straight start

static var on: bool = false
static var _phi := PackedFloat32Array()          # heading of the line at each stored point (radians, + = turning right)
static var _cx := PackedFloat32Array()           # centre of the line in the world
static var _cz := PackedFloat32Array()


## Lay out a new line. `strength` 1 is the normal amount of winding, 0 is dead straight.
static func setup(seed_n: int, strength: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var l1 := rng.randf_range(230.0, 290.0)
	var l2 := rng.randf_range(520.0, 640.0)
	var a1 := 0.62 * strength                        # a quicker swing of about 35 degrees either way ...
	var a2 := 0.55 * strength                        # ... on top of a slow one of about 30
	var n := int(LENGTH / STEP) + 2
	_phi.resize(n)
	_cx.resize(n)
	_cz.resize(n)
	var x := 0.0
	var z := 0.0
	# the heading starts at zero with zero turn, whatever the phases
	var base := a1 * sin(p1) + a2 * sin(p2)
	for i in n:
		var s := float(i) * STEP
		var k := smoothstep(STRAIGHT_START, STRAIGHT_START + EASE_IN, s)
		var ph := k * (a1 * sin(s / l1 + p1) + a2 * sin(s / l2 + p2) - base)
		_phi[i] = ph
		_cx[i] = x
		_cz[i] = z
		x += sin(ph) * STEP
		z -= cos(ph) * STEP


static func _at(z: float) -> Vector3:
	# x = centre x, y = heading, z = centre z, at distance s = -z down the trail
	if _phi.is_empty():
		return Vector3(0.0, 0.0, z)
	var s := -z
	if s <= 0.0:
		return Vector3(0.0, 0.0, z)                   # behind the start: straight on
	var f := s / STEP
	var i := mini(int(f), _phi.size() - 2)
	var t := clampf(f - float(i), 0.0, 1.0)
	return Vector3(lerpf(_cx[i], _cx[i + 1], t), lerpf(_phi[i], _phi[i + 1], t), lerpf(_cz[i], _cz[i + 1], t))


## Heading of the trail at strip z (radians).
static func heading(z: float) -> float:
	return _at(z).y if on else 0.0


## A strip point as a world point.
static func w(p: Vector3) -> Vector3:
	if not on:
		return p
	var c := _at(p.z)
	return Vector3(c.x + p.x * cos(c.y), p.y, c.z + p.x * sin(c.y))


## How things standing at strip z are turned: the strip's "down the hill" (-z) becomes the trail's direction there.
static func basis_at(z: float) -> Basis:
	if not on:
		return Basis.IDENTITY
	return Basis(Vector3.UP, -_at(z).y)


## A strip transform (where something stands and how it is turned) as a world transform.
static func xf(t: Transform3D) -> Transform3D:
	if not on:
		return t
	return Transform3D(basis_at(t.origin.z) * t.basis, w(t.origin))


## A strip direction at strip z as a world direction.
static func dir(v: Vector3, z: float) -> Vector3:
	if not on:
		return v
	return basis_at(z) * v
