class_name DhJourney
extends RefCounted
## ALL DRESSED: one endless run that leads the player through every world. It looks and plays like the plain alpine run, and now and then a different world comes on, the way a
## trip does: first a shimmer behind and around the mountains (the sky flickers into the new colours and out again), then the ground, then the trees, with the full-screen
## effect spreading from the horizon over the whole picture, the ride changing with it and the music morphing. It holds for a while, then recedes the same way, back to
## plain. The first waves are brief and faint, later ones come on slower, last longer and go all the way to the full trip. Between waves there are long calm stretches, so it
## stays a surprise. Everything comes from the seed and the clock, so a 30 second run and a six hour one are both complete.

const ORDER := ["psychedelic", "tunnel", "desert", "candy", "egypt", "matrix", "synthwave"]

## How each world changes the ride. spd top speed, haz rocks, pads boost pads, jumps ramps, glint glint rain, bump how hard the cupcakes bounce you, spring how high a spring
## throws you, padk how big a boost pad's kick is, grip how slowly the board swings across (above 1 is heavy, below 1 is sharp), mus the music.
const BIOME := {
	"alpine": {"spd": 1.0, "haz": 1.0, "pads": 1.0, "jumps": 1.0, "glint": 1.0, "bump": 1.0, "spring": 1.0, "padk": 1.0, "grip": 1.0, "mus": "ambient"},
	"psychedelic": {"spd": 1.0, "haz": 0.9, "pads": 1.0, "jumps": 1.2, "glint": 1.7, "bump": 1.2, "spring": 1.1, "padk": 1.0, "grip": 0.9, "mus": "trance"},
	"tunnel": {"spd": 1.28, "haz": 0.8, "pads": 1.6, "jumps": 0.9, "glint": 1.0, "bump": 1.0, "spring": 0.9, "padk": 1.5, "grip": 0.8, "mus": "techno"},
	"desert": {"spd": 1.0, "haz": 1.5, "pads": 0.8, "jumps": 1.5, "glint": 0.8, "bump": 0.9, "spring": 1.4, "padk": 1.0, "grip": 1.15, "mus": "jungle"},
	"candy": {"spd": 0.9, "haz": 0.6, "pads": 1.0, "jumps": 1.0, "glint": 1.6, "bump": 1.9, "spring": 1.5, "padk": 0.9, "grip": 1.0, "mus": "jungle"},
	"egypt": {"spd": 1.0, "haz": 1.3, "pads": 1.0, "jumps": 1.0, "glint": 0.9, "bump": 0.9, "spring": 1.0, "padk": 1.0, "grip": 1.3, "mus": "ambient"},
	"matrix": {"spd": 1.15, "haz": 1.0, "pads": 1.3, "jumps": 0.9, "glint": 1.0, "bump": 1.0, "spring": 1.0, "padk": 1.3, "grip": 0.75, "mus": "industrial"},
	"synthwave": {"spd": 1.1, "haz": 1.0, "pads": 1.2, "jumps": 1.6, "glint": 1.2, "bump": 1.1, "spring": 1.2, "padk": 1.2, "grip": 1.0, "mus": "trance"},
}

## The pieces of a world and the stretch of the coming-on (0..1) in which each one flickers in; going out is the same in the other order.
const STAGES := ["skymat", "ground", "veg", "light"]
const WIN_ON := {"sky": [0.0, 0.30], "ground": [0.30, 0.55], "veg": [0.55, 0.80], "light": [0.80, 1.0]}
const WIN_OFF := {"light": [0.0, 0.20], "veg": [0.20, 0.45], "ground": [0.45, 0.70], "sky": [0.70, 1.0]}

enum Phase { CALM, ONSET, PEAK, OFFSET }

var rig: RunRig = null
var wave: int = 0                       # waves finished so far: the difficulty and the trippiness grow with it
var phase: int = Phase.CALM
var t: float = 0.0
var world: String = "psychedelic"       # the world of the wave that is coming, here or going
var strength: float = 0.3
var flash: float = 0.0                  # kept for the screen wash; the journey no longer needs one
var flash_col: Color = Color.WHITE
var time_scale: float = 1.0             # tests run it faster
var _calm_len: float = 75.0
var _prewarm_t: float = 5.0
var _onset_len: float = 9.0
var _peak_len: float = 4.0
var _off_len: float = 6.0
var _shown := {}
var _sky_k: float = -1.0
var _env_next: float = 0.0
var _clock: float = 0.0
var _mods_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _order: Array = []


func start(r: RunRig, seed_v: int) -> void:
	rig = r
	_rng.seed = seed_v * 7 + 31
	wave = 0
	phase = Phase.CALM
	t = 0.0
	_clock = 0.0
	_shown = {}
	_sky_k = -1.0
	for s in STAGES:
		_shown[s] = false
	_order = ORDER.duplicate()
	_shuffle()
	world = String(_order[0])
	_calm_len = 75.0          # the first minute and a quarter is the plain run: nothing is shown before the player has found their feet
	_prewarm_t = 5.0
	_plan_wave()
	rig.biome_apply(BIOME["alpine"], 1.0, 1.0)
	if OS.has_feature("web"):
		var tq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('jt') || ''"))
		if tq.is_valid_float():
			time_scale = float(tq)          # ?jt=10: the journey clock runs ten times faster (to see the waves)
		var wq := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('jw') || ''"))
		if wq.is_valid_int():
			wave = int(wq)          # ?jw=6: begin at the sixth wave
			world = String(_order[wave % ORDER.size()])
			_plan_wave()


func _shuffle() -> void:
	for i in range(_order.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp: Variant = _order[i]
		_order[i] = _order[j]
		_order[j] = tmp


## How long each part of the coming wave lasts, from how many have gone before.
func _plan_wave() -> void:
	strength = clampf(0.30 + 0.10 * float(wave), 0.30, 1.2)
	_onset_len = clampf(14.0 + 3.0 * float(wave), 14.0, 45.0)
	_peak_len = clampf(4.0 + 4.0 * float(wave), 4.0, 60.0)
	_off_len = clampf(8.0 + 0.6 * float(wave), 8.0, 16.0)


func _calm_after(w: int) -> float:
	var base := _rng.randf_range(32.0, 60.0) * clampf(1.0 - 0.015 * float(w), 0.6, 1.0)
	if w % 4 == 3:
		base *= 1.6          # a long rest every fourth wave
	return maxf(base, 24.0)


## The world `k` waves ahead of the one coming now (the first one or two are built while the run loads).
func peek_world(k: int) -> String:
	return String(_order[(wave + k) % ORDER.size()])


## 1.0 at the start, a little more each wave, and it never stops growing slowly: faster, more rocks, more going on.
func difficulty() -> float:
	return 1.0 + 0.05 * float(mini(wave, 20)) + 0.01 * float(maxi(wave - 20, 0))


## The first signs, in the last ten seconds of the calm: faint, round the horizon, and they stay there (and never grow) until the run builds up enough to carry the wave in.
func hint() -> float:
	if phase != Phase.CALM:
		return 0.0
	return clampf((t - (_calm_len - 10.0)) / 10.0, 0.0, 1.0) * 0.15


## How far the world has come on: a hint in the calm, rising through the onset, 1 at the peak, falling away through the offset.
func onset_k() -> float:
	match phase:
		Phase.ONSET:
			# it comes on in swells: up, a little back, further up, a little back, and the last one carries through to the top
			var p := clampf(t / _onset_len, 0.0, 1.0)
			return clampf(maxf(p + (1.0 - p) * 0.18 * sin(p * 5.0 * PI), 0.15), 0.0, 1.0)
		Phase.PEAK:
			return 1.0
		Phase.OFFSET:
			var q := clampf(t / _off_len, 0.0, 1.0)
			return clampf((1.0 - q) + q * (1.0 - q) * 0.15 * sin(q * 3.0 * PI), 0.0, 1.0)
	return hint()


## The full effect (swirl, tracers, colours thrown apart) is for the strong waves and for the worlds that are made of it.
func wants_trip() -> bool:
	return strength >= 0.45 or Themes.post_mode(world) == 1


## How far gone the picture should be: nothing between waves, building during the onset, and from the third wave on, right up to a full trip.
func trip_floor() -> float:
	if phase == Phase.CALM or not wants_trip():
		return 0.0
	return pow(onset_k(), 1.5) * (0.25 + 0.6 * clampf((strength - 0.3) / 0.9, 0.0, 1.0)) * (0.7 + 0.3 * rig.excitement())          # a wave runs deeper while the run is going hard


func _frac(stage: String) -> float:
	match phase:
		Phase.ONSET:
			var w: Array = WIN_ON[stage]
			var fo := clampf((t / _onset_len - float(w[0])) / (float(w[1]) - float(w[0])), 0.0, 1.0)
			return maxf(fo, hint()) if stage == "sky" else fo
		Phase.PEAK:
			return 1.0
		Phase.OFFSET:
			var w2: Array = WIN_OFF[stage]
			return 1.0 - clampf((t / _off_len - float(w2[0])) / (float(w2[1]) - float(w2[0])), 0.0, 1.0)
	return 0.0


func tick(delta: float) -> void:
	if rig == null:
		return
	var d := delta * time_scale
	t += d
	_clock += d
	if phase == Phase.CALM and _prewarm_t > 0.0:
		_prewarm_t -= delta
		if _prewarm_t <= 0.0:
			rig.journey_prewarm(world)
	flash = maxf(flash - delta * 0.9, 0.0)          # the soft pulse that goes with every change of a layer
	match phase:
		Phase.CALM:
			# the wave comes in when the run is building (fast, a flow going, boosts): or, if it never does, after a while anyway
			if t >= _calm_len and (rig.excitement() > 0.55 or t >= _calm_len + 25.0):
				_set_phase(Phase.ONSET)
		Phase.ONSET:
			if t >= _onset_len:
				_set_phase(Phase.PEAK)
		Phase.PEAK:
			if t >= _peak_len:
				_set_phase(Phase.OFFSET)
		Phase.OFFSET:
			if t >= _off_len:
				_set_phase(Phase.CALM)
	_stages()
	if phase != Phase.CALM or hint() > 0.001:
		rig.journey_post(world, onset_k(), wants_trip(), strength)
	_mods_t -= d
	if _mods_t <= 0.0:
		_mods_t = 0.4
		var k := onset_k() * clampf(strength / 0.6, 0.45, 1.0)
		rig.biome_apply(BIOME[world], k, difficulty())


func _set_phase(p: int) -> void:
	phase = p
	t = 0.0
	match p:
		Phase.ONSET:
			rig.music_morph(String(BIOME[world]["mus"]), wave * 3 + 1)          # the next tune starts to be made now and arrives as the world does
		Phase.OFFSET:
			rig.music_morph(String(BIOME["alpine"]["mus"]), wave * 3 + 2)
		Phase.CALM:
			wave += 1
			if wave % ORDER.size() == 0:
				_shuffle()
			world = String(_order[wave % ORDER.size()])
			_calm_len = _calm_after(wave - 1)
			_prewarm_t = 6.0
			_plan_wave()
			rig.journey_reset()
			_sky_k = -1.0
			for s in STAGES:
				_shown[s] = false


## The sky's colours blend in over the first part of the coming-on and breathe as they do. The rest goes over one layer at a time, when the screen is already well washed by the
## effect, so each change is hidden inside it: the sky itself and the mountains, then the ground, then the trees, then the lights; each with a soft pulse of the world's colour.
## It goes out the same way, with a margin so a swell cannot flip a layer back and forth.
const SWAP_ON := {"skymat": 0.55, "ground": 0.66, "veg": 0.78, "light": 0.88}
const SWAP_OFF := {"skymat": 0.30, "ground": 0.45, "veg": 0.58, "light": 0.70}


func _stages() -> void:
	var e := onset_k()
	var ke := clampf(e * 1.45, 0.0, 1.0)
	if ke > 0.001 and ke < 0.999:
		ke *= 0.8 + 0.2 * sin(_clock * 1.7)
	if absf(ke - _sky_k) > 0.004 and _clock >= _env_next:
		_env_next = _clock + 0.12
		_sky_k = ke
		rig.journey_sky(world, ke)
	for s in STAGES:
		var on: bool = bool(_shown[s])
		if not on and e >= float(SWAP_ON[s]):
			on = true
		elif on and e < float(SWAP_OFF[s]):
			on = false
		if on != bool(_shown[s]):
			_shown[s] = on
			rig.journey_part(world if on else "alpine", s)
			_pulse()


func _pulse() -> void:
	flash = 1.0
	flash_col = Themes.theme_data(world)["c1"]
