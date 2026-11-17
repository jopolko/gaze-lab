class_name DhMusic
extends Node
## Procedural music for Downhill: techno, trance or industrial, composed from a seed and rendered at the start of a run as a handful of looping layers (kick, bass, hats,
## percussion, pad, lead) that all have the same length. The layers fade in and out with how hard the run is going, so the music builds with you: the kick and a soft pad
## on the gentle stretches, the bass, hats, percussion and lead as the speed, the steepness and the trip go up.
## Rendering is spread over many frames (a few milliseconds each) so nothing stalls; the music starts when it is ready.

const RATE := 16000
var BARS: int = 2 if OS.has_feature("web") else 4          # a phone renders half as much
const LAYERS := ["kick", "bass", "pad", "hat", "perc", "arp"]
# at what intensity (0..1) each layer starts to come in and is fully in, and its level in dB
const FADE := {
	"kick": [0.0, 0.05, -1.0], "bass": [0.02, 0.18, -4.0], "pad": [0.0, 0.25, -12.0],
	"hat": [0.08, 0.25, -11.0], "perc": [0.15, 0.35, -8.0], "arp": [0.30, 0.55, -9.0],
}
const FADE_JUNGLE := {
	"kick": [0.0, 0.05, -3.0], "bass": [0.05, 0.2, -3.0], "pad": [0.2, 0.5, -13.0],
	"hat": [0.1, 0.3, -13.0], "perc": [0.0, 0.08, -6.0], "arp": [0.6, 0.85, -10.0],
}
const FADE_AMBIENT := {
	"kick": [2.0, 3.0, -40.0], "bass": [0.1, 0.4, -9.0], "pad": [0.0, 0.15, -8.0],
	"hat": [2.0, 3.0, -40.0], "perc": [2.0, 3.0, -40.0], "arp": [0.05, 0.4, -9.0],
}
const STYLES := ["techno", "trance", "industrial", "ambient", "jungle"]


func _fade(l: String) -> Array:
	if style == "jungle":
		return FADE_JUNGLE[l]
	if style == "ambient":
		return FADE_AMBIENT[l]
	return FADE[l]

var style: String = "techno"
var intensity: float = 0.0
var volume: float = 0.7                       # 0..1
var ready_to_play: bool = false
var master: float = 1.0                       # 0..1: the whole mix, so one tune can fade out as the next fades in

var _rng := RandomNumberGenerator.new()
var _bpm: float = 128.0
var _spb: int = 7500                          # samples per beat
var _n: int = 0                               # samples in the whole loop
var _buf: Dictionary = {}                     # layer -> PackedFloat32Array (while rendering)
var _jobs: Array = []
var _players: Dictionary = {}
var _gain: Dictionary = {}                    # current linear gain per layer
var _bump: float = 0.0


static var vol_music: float = 0.7
static var vol_sfx: float = 0.9
static var dbg: String = ""


## No extra buses: everything plays on Master and the two volumes are applied to the players themselves. (Buses added while the game runs were the one thing the web
## audio could not be trusted with.)
static func ensure_buses() -> void:
	pass


static func set_bus_volume(nm: String, lin: float) -> void:
	if nm == "Music":
		vol_music = lin
	else:
		vol_sfx = lin


static func vol_db(lin: float) -> float:
	return -80.0 if lin <= 0.001 else linear_to_db(lin)


## Composes and starts rendering. `seed_v` makes the same course sound the same.
func compose(style_id: String, seed_v: int) -> void:
	ensure_buses()
	style = style_id if STYLES.has(style_id) else "techno"
	_rng.seed = seed_v * 7919 + 13
	_bpm = {"techno": 150.0, "trance": 144.0, "industrial": 124.0, "ambient": 84.0, "jungle": 168.0}[style]
	dbg = "rendering"
	_spb = int(round(60.0 / _bpm * float(RATE)))
	_n = _spb * 4 * BARS
	for l in LAYERS:
		var a := PackedFloat32Array()
		a.resize(_n)
		_buf[l] = a
		_gain[l] = 0.0
	_plan()
	set_process(true)


## JUNGLE: the amen break (a four-bar drum pattern of kicks, snares and ghost snares over steady hats) with a deep sub bass and dark pads. AMBIENT: no drums, slow chords
## and bell notes.
func _plan_special() -> void:
	var root: int = int({"jungle": 38, "ambient": 45}[style]) + (_rng.randi() % 5)
	var prog := [0, 8, 3, 10]
	var amen_k := [[0, 2, 10], [0, 2, 10], [0, 2, 10, 11], [0, 2, 10]]
	var amen_s := [[4, 12], [4, 12], [4, 12], [4, 7, 12, 14, 15]]
	var amen_g := [[7, 15], [7, 9, 15], [7, 15], [9]]
	for bar in BARS:
		var cr: int = root + int(prog[bar % 4])
		var b0 := bar * 4 * _spb
		if style == "jungle":
			for st in amen_k[bar]:
				_jobs.append(["kick", b0 + int(st) * _spb / 4])
			for st in amen_s[bar]:
				_jobs.append(["snare", b0 + int(st) * _spb / 4, 0])
			for st in amen_g[bar]:
				_jobs.append(["snare", b0 + int(st) * _spb / 4, 1])
			for st in range(0, 16, 2):
				_jobs.append(["hat", b0 + st * _spb / 4, 1 if st == 6 or st == 14 else 0])
			_jobs.append(["bass", b0, cr - 12, 2.0])
			_jobs.append(["bass", b0 + 10 * _spb / 4, cr - 12 + (7 if bar % 2 == 1 else 0), 1.2])
			for ci in [0, 1]:
				_jobs.append(["pad", b0, cr + 12 + [0, 7][ci], 4.0 * float(_spb) / float(RATE) + 0.3])
			for st in [0, 6, 10]:
				if (st + bar) % 2 == 0 or bar == 3:
					_jobs.append(["arp", b0 + st * _spb / 4, cr + 24 + [0, 3, 7, 10][(st + bar) % 4]])
		else:
			for ci in [0, 1, 2, 3]:
				_jobs.append(["pad", b0, cr + 12 + [0, 7, 10, 14][ci] - (12 if ci == 0 else 0), 4.0 * float(_spb) / float(RATE) + 1.2])
			_jobs.append(["bass", b0, cr - 12, 4.0])
			var penta := [0, 3, 5, 7, 10, 12, 15]
			for st in [0, 5, 8, 13]:
				if _rng.randf() < 0.75:
					_jobs.append(["bell", b0 + st * _spb / 4, cr + 24 + int(penta[_rng.randi() % penta.size()])])
	_jobs.append(["finish"])


func _plan() -> void:
	if style == "jungle" or style == "ambient":
		_plan_special()
		return
	var root: int = int({"techno": 43, "trance": 45, "industrial": 38}[style]) + (_rng.randi() % 5)
	var prog := [0, 8, 3, 10]                                         # i, VI, III, VII of a minor key
	var minor := [0, 3, 7, 10, 12, 15, 19, 22]                        # chord tones, a minor seventh up through the octaves
	var swing := _rng.randi() % 2
	for bar in BARS:
		var cr: int = root + int(prog[bar % 4])
		var b0 := bar * 4 * _spb
		# kick: four on the floor, a beat each
		for beat in 4:
			_jobs.append(["kick", b0 + beat * _spb])
		# percussion: a clap on 2 and 4; industrial adds metal on the off-beats
		for beat in [1, 3]:
			_jobs.append(["clap", b0 + beat * _spb])
		if style == "industrial":
			for st in [3, 6, 11, 14]:
				if (st + bar) % 3 != 0:
					_jobs.append(["clang", b0 + st * _spb / 4, cr + 12 * (1 + _rng.randi() % 2)])
		# hats: closed on the 16ths between the kicks, open on the off-beat 8ths
		for st in 16:
			if st % 4 == 2:
				_jobs.append(["hat", b0 + st * _spb / 4, 1])
			elif st % 2 == 1:
				_jobs.append(["hat", b0 + st * _spb / 4, 0])
		# bass
		var steps: Array = []
		match style:
			"techno":
				steps = [2, 3, 6, 7, 10, 11, 14, 15] if swing == 0 else [0, 2, 3, 6, 7, 10, 11, 14]          # a rolling bass on the off-beats, pumping against the kick
			"trance":
				steps = [1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15]
			_:
				steps = [0, 3, 6, 10, 13] if swing == 0 else [0, 2, 6, 8, 11, 14]
		for st in steps:
			var m := cr - 12 if (st + bar) % 5 != 0 else cr
			_jobs.append(["bass", b0 + st * _spb / 4, m, 0.9 if style == "trance" else 1.6])
		# pad: a chord held for the bar
		for ci in [0, 1, 2]:
			_jobs.append(["pad", b0, cr + 12 + int(minor[ci]) - (12 if ci == 0 else 0), 4.0 * float(_spb) / float(RATE) + 0.3])
		# the lead: an arpeggio over the chord
		var arp_steps: Array = []
		match style:
			"trance":
				arp_steps = range(16)
			"techno":
				arp_steps = [0, 2, 3, 5, 6, 8, 10, 11, 13, 15]
			_:
				arp_steps = [0, 2, 4, 6, 8, 10, 12, 14]
		var k := 0
		for st in arp_steps:
			var tone: int = int(minor[(k * 3 + (bar % 3)) % minor.size()])
			if style == "industrial" and k % 4 == 3:
				tone = 6                                            # the tritone: harsh
			_jobs.append(["arp", b0 + st * _spb / 4, cr + 24 + tone])
			k += 1
	_jobs.append(["finish"])


func _process(_delta: float) -> void:
	if not _jobs.is_empty():
		var t0 := Time.get_ticks_usec()
		while not _jobs.is_empty() and Time.get_ticks_usec() - t0 < 3000:
			_run(_jobs.pop_front())
		return
	if ready_to_play:
		_mix_levels(_delta)


func _run(j: Array) -> void:
	match String(j[0]):
		"kick":
			_kick(int(j[1]))
		"clap":
			_clap(int(j[1]))
		"clang":
			_clang(int(j[1]), int(j[2]))
		"hat":
			_hat(int(j[1]), int(j[2]) == 1)
		"bass":
			_bass(int(j[1]), int(j[2]), float(j[3]))
		"pad":
			_pad(int(j[1]), int(j[2]), float(j[3]))
		"arp":
			_arp(int(j[1]), int(j[2]))
		"snare":
			_snare(int(j[1]), int(j[2]) == 1)
		"bell":
			_bell(int(j[1]), int(j[2]))
		"finish":
			_finish()


func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func _add(layer: String, start: int, i: int, v: float) -> void:
	var p := start + i
	if p >= _n:
		p -= _n                                                        # a tail past the end wraps round to the start of the loop
	(_buf[layer] as PackedFloat32Array)[p] += v


func _kick(start: int) -> void:
	var len := int(RATE * (0.38 if style == "industrial" else 0.28))
	var phase := 0.0
	var buf: PackedFloat32Array = _buf["kick"]
	var ind := style == "industrial"
	var e := 1.0
	var em := exp(-(5.0 if ind else 8.0) / float(RATE))
	var fe := 120.0
	var fm := exp(-30.0 / float(RATE))
	var ce := 0.3
	var cm := exp(-350.0 / float(RATE))
	var inc := TAU / float(RATE)
	for i in len:
		phase += (42.0 + fe) * inc
		var s := sin(phase) * e + (randf() * 2.0 - 1.0) * ce
		if ind:
			s = tanh(s * 3.2) * 0.8
		e *= em
		fe *= fm
		ce *= cm
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s


func _clap(start: int) -> void:
	var len := int(RATE * 0.22)
	var lp := 0.0
	var buf: PackedFloat32Array = _buf["perc"]
	var tail := 0.5
	var tm := exp(-16.0 / float(RATE))
	var ind := style == "industrial"
	for i in len:
		var t := float(i) / float(RATE)
		var n := randf() * 2.0 - 1.0
		lp += (n - lp) * 0.55
		var bursts := tail
		if t < 0.036:
			bursts += exp(-fmod(t, 0.012) * 300.0)
		tail *= tm
		var s := (n - lp * 0.4) * bursts * 0.5
		if ind:
			s = tanh(s * 2.5) * 0.7
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s


func _clang(start: int, midi: int) -> void:
	var len := int(RATE * 0.45)
	var f := _hz(float(midi))
	var buf: PackedFloat32Array = _buf["perc"]
	var e := 0.5
	var em := exp(-9.0 / float(RATE))
	var ne := 0.25
	var nm := exp(-40.0 / float(RATE))
	var w1 := TAU * f / float(RATE)
	var w2 := TAU * f * 1.414 / float(RATE)
	for i in len:
		var fi := float(i)
		var s := sin(w1 * fi + 5.0 * sin(w2 * fi)) * e + (randf() * 2.0 - 1.0) * ne
		e *= em
		ne *= nm
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += tanh(s * 2.0) * 0.6


func _hat(start: int, open: bool) -> void:
	var len := int(RATE * (0.22 if open else 0.05))
	var prev := 0.0
	var buf: PackedFloat32Array = _buf["hat"]
	var e := 0.5 if open else 0.6
	var em := exp(-(14.0 if open else 70.0) / float(RATE))
	for i in len:
		var n := randf() * 2.0 - 1.0
		var s := (n - prev) * e
		prev = n
		e *= em
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s


func _snare(start: int, ghost: bool) -> void:
	var len := int(RATE * (0.12 if ghost else 0.2))
	var buf: PackedFloat32Array = _buf["perc"]
	var amp := 0.28 if ghost else 0.8
	var e := 1.0
	var em := exp(-(30.0 if ghost else 20.0) / float(RATE))
	var ph := 0.0
	var lp := 0.0
	for i in len:
		ph += 190.0 / float(RATE)
		var n := randf() * 2.0 - 1.0
		lp += (n - lp) * 0.7
		var s := (sin(ph * TAU) * 0.45 + (n - lp * 0.3) * 0.7) * e * amp
		e *= em
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += tanh(s * 1.6) * 0.7


func _bell(start: int, midi: int) -> void:
	var f := _hz(float(midi))
	var len := int(RATE * 1.4)
	var buf: PackedFloat32Array = _buf["arp"]
	var e := 0.5
	var em := exp(-3.2 / float(RATE))
	var w1 := TAU * f / float(RATE)
	var w2 := TAU * f * 2.76 / float(RATE)
	for i in len:
		var fi := float(i)
		var s := (sin(w1 * fi) + 0.3 * sin(w2 * fi) * e) * e * minf(fi / 40.0, 1.0)
		e *= em
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s * 0.7


func _bass(start: int, midi: int, dur_beats: float) -> void:
	var f := _hz(float(midi))
	var sub := style == "jungle" or style == "ambient"
	var len := int(float(_spb) * (minf(dur_beats, 4.0) * 0.9 if sub else minf(dur_beats, 1.0) * 0.55))
	var ph := 0.0
	var lp := 0.0
	var buf: PackedFloat32Array = _buf["bass"]
	var ind := style == "industrial"
	var df := f / float(RATE)
	var fe := 0.30
	var fm := exp(-14.0 / float(RATE))
	var e := 1.0
	var em := exp(-5.0 / float(RATE))
	for i in len:
		ph += df
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		lp += (saw - lp) * (0.06 + fe)
		var s := lp * e * minf(float(i) / 64.0, 1.0)
		if sub:
			s = sin(ph * TAU) * minf(float(i) / 200.0, 1.0) * minf(float(len - i) / 800.0, 1.0) * 0.9
		if ind:
			s = tanh(s * 3.0) * 0.7
		fe *= fm
		e *= em
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s


func _pad(start: int, midi: int, dur_s: float) -> void:
	var f := _hz(float(midi))
	var len := int(dur_s * float(RATE))
	var p1 := 0.0
	var p2 := 0.0
	var lp := 0.0
	var buf: PackedFloat32Array = _buf["pad"]
	var d1 := f * 0.994 / float(RATE)
	var d2 := f * 1.006 / float(RATE)
	var k := 0.05 if style != "industrial" else 0.12
	var atk := 0.5 * float(RATE)
	var rel := 0.6 * float(RATE)
	for i in len:
		p1 += d1
		p2 += d2
		lp += ((fmod(p1, 1.0) + fmod(p2, 1.0)) - 1.0 - lp) * k
		var env := minf(float(i) / atk, 1.0) * minf(float(len - i) / rel, 1.0)
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += lp * env * 0.5


func _arp(start: int, midi: int) -> void:
	var f := _hz(float(midi))
	var len := int(RATE * 0.16)
	var ph := 0.0
	var lp := 0.0
	var buf: PackedFloat32Array = _buf["arp"]
	var ind := style == "industrial"
	var df := f / float(RATE)
	var fe := 0.35
	var fm := exp(-25.0 / float(RATE))
	var e := 0.7
	var em := exp(-14.0 / float(RATE))
	for i in len:
		ph += df
		var q := fmod(ph, 1.0)
		var w := (1.0 if q < 0.5 else -1.0) if ind else (q * 2.0 - 1.0)
		lp += (w - lp) * (0.12 + fe)
		fe *= fm
		var s := lp * e * minf(float(i) / 32.0, 1.0)
		e *= em
		var p := start + i
		if p >= _n:
			p -= _n
		buf[p] += s


## All the events are drawn: duck the sustained layers under the kick, soft-limit, and turn each layer into a looping stream.
func _finish() -> void:
	var duck := {"bass": 0.92, "pad": 0.7, "arp": 0.55}          # the strong pump: everything ducks hard under every kick
	var curve := PackedFloat32Array()
	curve.resize(_spb)
	for i in _spb:
		curve[i] = exp(-float(i) / float(RATE) * 9.0)
	for l in LAYERS:
		var b: PackedFloat32Array = _buf[l]
		var d: float = float(duck.get(l, 0.0))
		var data := PackedByteArray()
		data.resize(_n * 2)
		var bi := 0
		for i in _n:
			var s := b[i]
			if d > 0.0:
				s *= 1.0 - d * curve[bi]
			bi += 1
			if bi >= _spb:
				bi = 0
			data.encode_s16(i * 2, int(clampf(tanh(s * 0.9), -1.0, 1.0) * 30000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = RATE
		w.stereo = false
		w.data = data
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = _n
		var pl := AudioStreamPlayer.new()
		pl.stream = w
		pl.bus = &"Master"
		pl.volume_db = -60.0
		add_child(pl)
		_players[l] = pl
		_buf[l] = PackedFloat32Array()
	for l in LAYERS:
		(_players[l] as AudioStreamPlayer).play()
	ready_to_play = true
	dbg = "music playing"


func set_intensity(x: float) -> void:
	intensity = clampf(x, 0.0, 1.0)


## A moment that deserves a hit: the whole mix swells for a second.
func bump(a: float = 0.35) -> void:
	_bump = maxf(_bump, a)


func _mix_levels(delta: float) -> void:
	_bump = maxf(_bump - delta * 0.8, 0.0)
	var x := clampf(intensity + _bump, 0.0, 1.0)
	for l in LAYERS:
		var f: Array = _fade(l)
		var g := smoothstep(float(f[0]), float(f[1]), x)
		_gain[l] = lerpf(float(_gain[l]), g, clampf(delta * 2.5, 0.0, 1.0))
		var db := -60.0 if float(_gain[l]) < 0.003 else linear_to_db(float(_gain[l])) + float(f[2]) + vol_db(vol_music) + vol_db(master)
		(_players[l] as AudioStreamPlayer).volume_db = maxf(db, -80.0)


func stop() -> void:
	for l in _players:
		(_players[l] as AudioStreamPlayer).stop()
	queue_free()
