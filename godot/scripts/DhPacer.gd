class_name DhPacer
extends RefCounted
## THE PACER. A session has a shape, stretched to whatever length the player chooses (10 minutes to 8 hours, then it goes round again, a little higher each time):
##
##   settle      the first few minutes: calm, nothing hostile, the first molecules offered
##   come up     a slow, wave-like climb: each wave a bit higher than the last
##   peak        everything near the top at once: the window
##   plateau     held, then easing
##   comedown    a long, soft way down to calm
##
## The pacer holds a TARGET level (0..1: how much of the six the session should be carrying right now). It does not hand anything out: it nudges how often molecules turn up (more when the
## player is behind the curve, fewer when ahead of it), so a careful player and a clumsy one both ride roughly the same arc, and losing levels to hazards is something to win back, not the end.
## It also sets how hostile the course is in each phase. It models no real substance and says nothing about any: the length is the player's choice.

const PHASES := [
	{"name": "settle", "a": 0.00, "b": 0.07, "from": 0.00, "to": 0.12, "hazard": 0.35},
	{"name": "come up", "a": 0.07, "b": 0.30, "from": 0.12, "to": 0.75, "hazard": 0.75},
	{"name": "peak", "a": 0.30, "b": 0.52, "from": 0.75, "to": 1.00, "hazard": 1.20},
	{"name": "plateau", "a": 0.52, "b": 0.70, "from": 1.00, "to": 0.65, "hazard": 1.00},
	{"name": "comedown", "a": 0.70, "b": 1.00, "from": 0.65, "to": 0.00, "hazard": 0.45},
]
const CALM_START_S := 20.0          # nothing hostile at all for the first twenty seconds

var session_s: float = 600.0
var t: float = 0.0
var cycle: int = 0


func tick(delta: float) -> void:
	t += delta
	if t >= session_s:
		t = 0.0
		cycle += 1          # round again: a little higher each time (see target())


func _phase(u: float) -> Dictionary:
	for p: Dictionary in PHASES:
		if u < float(p["b"]):
			return p
	return PHASES[PHASES.size() - 1]


func phase_name() -> String:
	return String(_phase(clampf(t / session_s, 0.0, 1.0))["name"])


## How much of the six the session should be carrying now, 0..1. Each cycle after the first reaches a little further and rises a little sooner.
func target() -> float:
	var u := clampf(t / session_s, 0.0, 1.0)
	var p := _phase(u)
	var k := clampf((u - float(p["a"])) / maxf(float(p["b"]) - float(p["a"]), 0.001), 0.0, 1.0)
	var v := lerpf(float(p["from"]), float(p["to"]), smoothstep(0.0, 1.0, k))
	return clampf(v * (1.0 + 0.04 * float(mini(cycle, 5))), 0.0, 1.0)


## How often molecules turn up, as a multiple of normal: more when the player is behind the curve, fewer when ahead of it.
func spawn_bias(avg: float) -> float:
	return clampf(1.0 + 2.6 * (target() - avg), 0.15, 3.0)


## How hostile the course is now, as a multiple of normal: none at all for the first twenty seconds.
func hazard_k() -> float:
	if t < CALM_START_S and cycle == 0:
		return 0.0
	var u := clampf(t / session_s, 0.0, 1.0)
	var k := float(_phase(u)["hazard"])
	return k * (1.0 + 0.05 * float(mini(cycle, 6)))
