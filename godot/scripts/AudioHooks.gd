class_name AudioHooks
extends Node
## Listens to Game.sfx_requested and plays procedurally synthesised sounds
## (no audio files needed). To use real audio, replace entries in `_streams`
## with `load("res://audio/squawk.ogg")` etc. -- the signal names stay the same.

const RATE := 22050
const MAX_VOICES := 28

var _streams: Dictionary = {}
var _loop_player: AudioStreamPlayer
var toon: bool = true                          # cartoon sounds: springs, stretches, snaps, rubber and big layered explosions
## With cartoon sounds off the new names fall back to the plain old ones; with them on, a few old names are swapped for the bigger new ones.
const _FALLBACK := {&"explosion": &"boom", &"kaboom": &"boom", &"stretch": &"powerup", &"snap": &"pop", &"boing2": &"boing", &"splat": &"bonk", &"zap": &"squeak", &"rumble": &"boom", &"blip": &"coin", &"sproing": &"boing"}
const _TOON_MAP := {&"boom": &"explosion", &"coin": &"blip", &"boing": &"sproing"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DhMusic.ensure_buses()
	# SOFT SOUNDS. Sine tones with a few gentle harmonics and a slow-ish attack, no square or saw, no hard clicks; every pitch is in A minor pentatonic (A C D E G), the key of
	# the music, so an effect that lands on a note sounds like part of it. Notes: A3 220, C4 261.6, D4 293.7, E4 329.6, G4 392, A4 440, C5 523.3, D5 587.3, E5 659.3, G5 784, A5 880, C6 1047.
	_streams[&"squawk"] = _wav(_tone(392.0, 329.6, 0.22, 0.4, 0.015, 2.5, 0.25))
	_streams[&"pop"] = _wav(_mixp([_tone(329.6, 130.0, 0.12, 0.5, 0.004, 3.0), _tone(659.3, 659.3, 0.07, 0.12, 0.006, 3.0)]))
	_streams[&"squeak"] = _wav(_tone(659.3, 784.0, 0.16, 0.25, 0.012, 2.0, 0.15))
	_streams[&"bonk"] = _wav(_mixp([_tone(196.0, 82.0, 0.22, 0.6, 0.004, 3.0), _air(0.12, 0.05, 0.02, 0.25, 0.004, 3.0)]))
	_streams[&"whoosh"] = _wav(_air(0.4, 0.02, 0.2, 0.55, 0.07, 1.6))
	_streams[&"yeet"] = _wav(_tone(220.0, 440.0, 0.35, 0.32, 0.03, 1.8, 0.15))
	_streams[&"thwup"] = _wav(_tone(220.0, 110.0, 0.12, 0.55, 0.005, 3.0))
	_streams[&"boing"] = _wav(_tone(196.0, 392.0, 0.38, 0.4, 0.015, 1.8, 0.2))
	_streams[&"honk"] = _wav(_tone(220.0, 220.0, 0.28, 0.32, 0.02, 1.6, 0.3, 0.12))
	_streams[&"hurt"] = _wav(_mixp([_tone(220.0, 165.0, 0.32, 0.4, 0.01, 2.2, 0.15), _tone(110.0, 82.0, 0.3, 0.4, 0.01, 2.5)]))
	_streams[&"boom"] = _wav(_mixp([_tone(90.0, 45.0, 0.55, 0.75, 0.006, 2.2), _air(0.5, 0.03, 0.01, 0.4, 0.006, 2.0)]))
	_streams[&"coin"] = _wav(_cat([_tone(659.3, 659.3, 0.07, 0.34, 0.006, 2.0, 0.3, 0.1), _tone(880.0, 880.0, 0.22, 0.34, 0.006, 3.0, 0.3, 0.1)]))
	_streams[&"gong"] = _wav(_tone(110.0, 108.0, 1.2, 0.55, 0.02, 1.4, 0.3, 0.0, [Vector2(2.76, 0.3), Vector2(5.4, 0.15)]))
	_streams[&"thwack"] = _wav(_mixp([_tone(250.0, 100.0, 0.15, 0.5, 0.004, 3.0), _air(0.08, 0.1, 0.03, 0.3, 0.003, 3.0)]))
	_streams[&"bell"] = _wav(_tone(880.0, 880.0, 0.7, 0.4, 0.008, 2.2, 0.0, 0.0, [Vector2(2.76, 0.25), Vector2(5.4, 0.1)]))
	_streams[&"crowd"] = _wav(_air(0.9, 0.03, 0.08, 0.35, 0.2, 1.2))
	_streams[&"buff_boost"] = _wav(_mixp([_air(0.35, 0.02, 0.22, 0.4, 0.05, 1.4), _tone(440.0, 880.0, 0.3, 0.3, 0.03, 1.6, 0.2)]))
	_streams[&"buff_shield"] = _wav(_cat([_tone(440.0, 440.0, 0.08, 0.32, 0.008, 1.0, 0.25), _tone(523.3, 523.3, 0.08, 0.32, 0.008, 1.0, 0.25), _tone(659.3, 659.3, 0.3, 0.32, 0.008, 2.0, 0.25)]))
	_streams[&"buff_mult"] = _wav(_cat([_tone(523.3, 523.3, 0.07, 0.3, 0.008, 1.0, 0.2), _tone(587.3, 587.3, 0.07, 0.3, 0.008, 1.0, 0.2), _tone(659.3, 659.3, 0.07, 0.3, 0.008, 1.0, 0.2), _tone(784.0, 784.0, 0.3, 0.3, 0.008, 2.0, 0.2)]))
	_streams[&"powerup"] = _wav(_mixp([_tone(440.0, 880.0, 0.3, 0.3, 0.03, 1.4, 0.2), _tone(660.0, 1320.0, 0.3, 0.12, 0.05, 1.8)]))
	_streams[&"levelup"] = _wav(_cat([_tone(440.0, 440.0, 0.1, 0.3, 0.008, 1.0, 0.25), _tone(523.3, 523.3, 0.1, 0.3, 0.008, 1.0, 0.25), _tone(659.3, 659.3, 0.1, 0.3, 0.008, 1.0, 0.25), _tone(880.0, 880.0, 0.4, 0.3, 0.008, 2.0, 0.25)]))
	_streams[&"loot"] = _wav(_cat([_tone(659.3, 659.3, 0.08, 0.32, 0.006, 1.0, 0.3), _tone(880.0, 880.0, 0.08, 0.32, 0.006, 1.0, 0.3), _tone(1047.0, 1047.0, 0.28, 0.32, 0.006, 2.5, 0.3)]))

	_build_new_voices.call_deferred()          # the big new sounds take a moment to build: one a frame, after the game is up

	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = &"Master"
	_loop_player.stream = _noise_loop()
	_loop_player.volume_db = -12.0
	add_child(_loop_player)

	Game.sfx_requested.connect(_on_sfx)


func _on_sfx(sfx_name: StringName, world_pos: Vector3) -> void:
	match sfx_name:
		&"blower_on":
			_loop_player.play()
			return
		&"blower_off":
			_loop_player.stop()
			return
	if toon:
		sfx_name = _TOON_MAP.get(sfx_name, sfx_name)
	elif _FALLBACK.has(sfx_name):
		sfx_name = _FALLBACK[sfx_name]
	if not _streams.has(sfx_name) or _voices >= MAX_VOICES:
		return
	var stream: AudioStream = _streams[sfx_name]
	played += 1
	_voices += 1
	if world_pos.is_finite():
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		if _low_latency:
			p3.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		p3.unit_size = 12.0
		p3.max_distance = 90.0
		p3.pitch_scale = randf_range(0.9, 1.15)
		p3.bus = &"Master"
		p3.volume_db = DhMusic.vol_db(DhMusic.vol_sfx) + SFX_GAIN_DB
		add_child(p3)
		p3.global_position = world_pos
		p3.play()
		_free_later(p3, stream, p3.pitch_scale)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		if _low_latency:
			p.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
		p.pitch_scale = randf_range(0.95, 1.05)
		p.bus = &"Master"
		p.volume_db = DhMusic.vol_db(DhMusic.vol_sfx) + SFX_GAIN_DB
		add_child(p)
		p.play()
		_free_later(p, stream, p.pitch_scale)


var _voices: int = 0
static var played: int = 0
const SFX_GAIN_DB := 3.0          # the soft sounds are quieter than the old harsh ones: this brings them back up so they are still heard over the music
## ?samples: the browser plays the effects itself (its own low-latency sample playback) instead of the game mixing them: less delay, and less work for the game. Off unless asked for, to be tried on a phone.
var _low_latency: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("samples")


## A voice is freed by a timer of its own length, not by its "finished" signal, and counted by hand: if a signal ever fails to come, the sounds do not run out.
func _free_later(pl: Node, stream: AudioStream, pitch: float) -> void:
	var life := stream.get_length() / maxf(pitch, 0.1) + 0.25
	get_tree().create_timer(life).timeout.connect(func() -> void:
		_voices = maxi(_voices - 1, 0)
		if is_instance_valid(pl):
			pl.queue_free())


func _synth(f0: float, f1: float, dur: float, wave: int, vol: float, vibrato: float, noise_mix: float, decay: float) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / float(n)
		var f := lerpf(f0, f1, u) * (1.0 + vibrato * sin(TAU * 18.0 * t))
		phase += TAU * f / RATE
		var s := 0.0
		match wave:
			0: s = sin(phase)
			1: s = 1.0 if fmod(phase, TAU) < PI else -1.0
			2: s = fmod(phase, TAU) / PI - 1.0
			_: s = 0.0
		s = lerpf(s, randf() * 2.0 - 1.0, noise_mix)
		var env := pow(1.0 - u, decay) * minf(1.0, t * 100.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return data


func _build_new_voices() -> void:
	_streams[&"explosion"] = _wav(_mixp([_tone(100.0, 35.0, 0.9, 0.8, 0.006, 1.8), _air(0.8, 0.04, 0.01, 0.55, 0.006, 1.8), _tone(55.0, 40.0, 0.9, 0.5, 0.01, 1.4)]))
	await get_tree().process_frame
	_streams[&"kaboom"] = _wav(_mixp([_tone(70.0, 30.0, 1.5, 0.85, 0.008, 1.5), _air(1.4, 0.03, 0.01, 0.6, 0.008, 1.4), _tone(45.0, 32.0, 1.5, 0.5, 0.01, 1.2)]))
	await get_tree().process_frame
	_streams[&"sproing"] = _wav(_tone(196.0, 587.3, 0.5, 0.42, 0.015, 1.6, 0.2))
	await get_tree().process_frame
	_streams[&"boing2"] = _wav(_tone(587.3, 165.0, 0.5, 0.42, 0.012, 1.6, 0.2))
	await get_tree().process_frame
	_streams[&"stretch"] = _wav(_mixp([_tone(130.0, 523.3, 0.5, 0.3, 0.05, 1.2, 0.15), _air(0.5, 0.02, 0.12, 0.15, 0.08, 1.2)]))
	await get_tree().process_frame
	_streams[&"snap"] = _wav(_mixp([_air(0.06, 0.25, 0.08, 0.4, 0.002, 3.5), _tone(784.0, 587.3, 0.06, 0.25, 0.003, 3.0)]))
	await get_tree().process_frame
	_streams[&"splat"] = _wav(_mixp([_tone(150.0, 60.0, 0.35, 0.55, 0.006, 2.4), _air(0.3, 0.08, 0.02, 0.35, 0.006, 2.4)]))
	await get_tree().process_frame
	_streams[&"zap"] = _wav(_tone(784.0, 330.0, 0.22, 0.28, 0.01, 2.0, 0.25))
	await get_tree().process_frame
	_streams[&"rumble"] = _wav(_mixp([_tone(55.0, 46.0, 1.3, 0.6, 0.06, 1.0), _air(1.3, 0.015, 0.01, 0.4, 0.08, 1.0)]))
	await get_tree().process_frame
	# the target tick: two soft notes, E5 then A5 (a rising fourth), short: heard on every look and every choice
	_streams[&"blip"] = _wav(_cat([_tone(659.3, 659.3, 0.05, 0.26, 0.008, 1.2, 0.25), _tone(880.0, 880.0, 0.12, 0.26, 0.008, 3.0, 0.25)]))
	await get_tree().process_frame
	# a speed pad: a soft air riser, a tone climbing A3 to A4 under it, and a low push at the start
	_streams[&"pad_boost"] = _wav(_mixp([_air(0.75, 0.02, 0.3, 0.55, 0.08, 1.3), _tone(220.0, 440.0, 0.75, 0.32, 0.06, 1.2, 0.2), _tone(82.0, 55.0, 0.4, 0.55, 0.01, 2.0)]))
	await get_tree().process_frame
	# the cues: a good moment (two rising notes, E5 then A5, warm), a bad one (a low falling pair), and the glint ladder (one rung higher each time up A C D E G)
	_streams[&"cue_good"] = _wav(_cat([_tone(659.3, 659.3, 0.08, 0.34, 0.01, 1.2, 0.25), _tone(880.0, 880.0, 0.22, 0.34, 0.01, 2.5, 0.25)]))
	_streams[&"cue_bad"] = _wav(_mixp([_tone(220.0, 165.0, 0.3, 0.4, 0.01, 2.0, 0.2), _tone(110.0, 82.0, 0.3, 0.35, 0.01, 2.2)]))
	await get_tree().process_frame
	var ladder := [440.0, 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5, 1568.0]
	for li in 10:
		_streams[StringName("lad%d" % li)] = _wav(_tone(ladder[li], ladder[li], 0.16, 0.3, 0.006, 2.5, 0.2))
	await get_tree().process_frame
	# leaving a ramp: a soft air lift with a tone rising under it; grabbing a rail: a short bright tick with air; a landing: a soft low thump
	_streams[&"launch"] = _wav(_mixp([_air(0.45, 0.02, 0.2, 0.45, 0.04, 1.4), _tone(220.0, 440.0, 0.4, 0.22, 0.04, 1.6, 0.15)]))
	_streams[&"rail_on"] = _wav(_mixp([_tone(880.0, 784.0, 0.12, 0.28, 0.006, 2.5, 0.3), _air(0.1, 0.12, 0.05, 0.3, 0.004, 2.5)]))
	_streams[&"land"] = _wav(_mixp([_tone(110.0, 55.0, 0.3, 0.7, 0.006, 2.2), _air(0.18, 0.05, 0.02, 0.35, 0.004, 2.5)]))
	await get_tree().process_frame
	# a chime for each molecule, on the pentatonic scale rising from the first to the last: C5 D5 E5 G5 A5 C6
	var notes := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
	for i in 6:
		var f: float = notes[i]
		_streams[StringName("mol%d" % i)] = _wav(_mixp([_tone(f, f, 0.7, 0.4, 0.008, 1.6, 0.3, 0.1), _tone(f * 2.0, f * 2.0, 0.5, 0.12, 0.008, 2.2)]))
		await get_tree().process_frame


## A soft tone: a sine gliding f0 to f1 (exponentially) with a second and third harmonic mixed in (h2, h3) and any extra partials (a list of Vector2(multiple of the pitch, strength)),
## an attack of `att` seconds (never abrupt: that is what clicks) and an exponential decay. Ends in a short fade so nothing is cut off.
func _tone(f0: float, f1: float, dur: float, vol: float, att: float = 0.012, dec: float = 2.5, h2: float = 0.0, h3: float = 0.0, extra: Array = []) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var norm := 1.0 / (1.0 + h2 + h3 + _sum_x(extra))
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / float(n)
		phase += TAU * f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), u) / RATE
		var sm := sin(phase) + h2 * sin(2.0 * phase) + h3 * sin(3.0 * phase)
		for e: Vector2 in extra:
			sm += e.y * sin(phase * e.x)
		var env := exp(-dec * u * 5.0) * minf(1.0, t / maxf(att, 0.002)) * minf(1.0, (dur - t) / 0.01)
		data.encode_s16(i * 2, int(clampf(sm * norm * env * vol, -1.0, 1.0) * 32767.0))
	return data


func _sum_x(extra: Array) -> float:
	var t := 0.0
	for e: Vector2 in extra:
		t += e.y
	return t


## Soft air: noise smoothed by two low-pass stages (the coefficient moves lp0 to lp1: small is dark, larger is brighter), a slow attack and a decay. Whooshes, thumps' bodies, rumbles.
func _air(dur: float, lp0: float, lp1: float, vol: float, att: float = 0.05, dec: float = 1.5) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / float(n)
		var c := lerpf(lp0, lp1, u)
		a += ((randf() * 2.0 - 1.0) - a) * c
		b += (a - b) * c
		var gain := 1.0 / maxf(sqrt(c / (2.0 - c)) * 0.58, 0.02)          # brings the smoothed noise back up to about the same loudness at any coefficient
		var env := exp(-dec * u * 5.0) * minf(1.0, t / maxf(att, 0.002)) * minf(1.0, (dur - t) / 0.01)
		data.encode_s16(i * 2, int(clampf(b * gain * 0.35 * env * vol, -1.0, 1.0) * 32767.0))
	return data


## A general voice: the pitch glides f0 to f1 along a curve, sine/saw/square mixed (`wave`), noise with a low-pass that sweeps lp0 to lp1 (0..1 coefficients), an FM wobble
## (fm_hz, fm_depth in radians), tanh drive, an exponential decay and a short attack. This is what makes springs, stretches, snaps, splats and the layered explosions.
func _voice(dur: float, f0: float, f1: float, curve: float, wave: Vector3, noise: float, lp0: float, lp1: float, fm_hz: float, fm_depth: float, drive: float, decay: float, vol: float) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var lp := 0.0
	var norm := 1.0 / tanh(maxf(drive, 0.1))
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / float(n)
		var f := f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), pow(u, curve))
		phase += TAU * f / RATE
		var ph := phase + fm_depth * sin(TAU * fm_hz * t)
		var q := fmod(ph, TAU) / TAU
		var s := wave.x * sin(ph) + wave.y * (q * 2.0 - 1.0) + wave.z * (1.0 if q < 0.5 else -1.0)
		if noise > 0.0:
			lp += ((randf() * 2.0 - 1.0) - lp) * lerpf(lp0, lp1, u)
			s += noise * lp * 2.0
		s = tanh(s * drive) * norm
		var env := exp(-decay * u * 5.0) * minf(1.0, t * 100.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return data


## Mixes several sounds that start together (the longest sets the length).
func _mixp(parts: Array) -> PackedByteArray:
	var n := 0
	for p: PackedByteArray in parts:
		n = maxi(n, p.size() / 2)
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var v := 0.0
		for p: PackedByteArray in parts:
			if i * 2 + 1 < p.size():
				v += float(p.decode_s16(i * 2)) / 32767.0
		out.encode_s16(i * 2, int(clampf(tanh(v * 0.9), -1.0, 1.0) * 32767.0))
	return out


func _cat(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p: PackedByteArray in parts:
		out.append_array(p)
	return out


func _noise_loop() -> AudioStreamWAV:
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.25)
		data.encode_s16(i * 2, int(lp * 0.6 * 32767.0))
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
