class_name AudioHooks
extends Node
## Listens to Game.sfx_requested and plays procedurally synthesised sounds
## (no audio files needed). To use real audio, replace entries in `_streams`
## with `load("res://audio/squawk.ogg")` etc. -- the signal names stay the same.

const RATE := 22050
const MAX_VOICES := 28

var _streams: Dictionary = {}
var _loop_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# wave: 0 sine, 1 square, 2 saw, 3 noise
	_streams[&"squawk"] = _wav(_synth(700.0, 320.0, 0.28, 2, 0.35, 0.12, 0.05, 1.5))
	_streams[&"pop"] = _wav(_synth(420.0, 70.0, 0.14, 0, 0.7, 0.0, 0.0, 2.5))
	_streams[&"squeak"] = _wav(_synth(1300.0, 2400.0, 0.2, 0, 0.35, 0.05, 0.0, 1.2))
	_streams[&"bonk"] = _wav(_synth(170.0, 55.0, 0.22, 0, 0.8, 0.0, 0.25, 3.0))
	_streams[&"whoosh"] = _wav(_synth(900.0, 200.0, 0.22, 3, 0.35, 0.0, 1.0, 1.0))
	_streams[&"yeet"] = _wav(_synth(300.0, 1000.0, 0.4, 1, 0.25, 0.08, 0.0, 1.5))
	_streams[&"thwup"] = _wav(_synth(260.0, 90.0, 0.12, 0, 0.8, 0.0, 0.2, 2.0))
	_streams[&"boing"] = _wav(_synth(180.0, 620.0, 0.4, 0, 0.45, 0.15, 0.0, 1.2))
	_streams[&"honk"] = _wav(_synth(420.0, 360.0, 0.3, 1, 0.22, 0.03, 0.05, 1.2))
	_streams[&"hurt"] = _wav(_synth(320.0, 70.0, 0.25, 2, 0.4, 0.0, 0.2, 2.0))
	_streams[&"boom"] = _wav(_synth(130.0, 35.0, 0.55, 0, 0.9, 0.0, 0.55, 2.2))
	_streams[&"coin"] = _wav(_cat([_synth(1250.0, 1250.0, 0.05, 0, 0.35, 0.0, 0.0, 0.5), _synth(1850.0, 1850.0, 0.12, 0, 0.35, 0.0, 0.0, 1.5)]))
	_streams[&"powerup"] = _wav(_synth(300.0, 1200.0, 0.3, 1, 0.22, 0.0, 0.0, 1.0))
	_streams[&"levelup"] = _wav(_cat([
		_synth(523.0, 523.0, 0.1, 1, 0.22, 0.0, 0.0, 0.8), _synth(659.0, 659.0, 0.1, 1, 0.22, 0.0, 0.0, 0.8),
		_synth(784.0, 784.0, 0.1, 1, 0.22, 0.0, 0.0, 0.8), _synth(1047.0, 1047.0, 0.3, 1, 0.22, 0.0, 0.0, 1.5)]))
	_streams[&"loot"] = _wav(_cat([
		_synth(880.0, 880.0, 0.08, 0, 0.35, 0.0, 0.0, 0.6), _synth(1175.0, 1175.0, 0.08, 0, 0.35, 0.0, 0.0, 0.6),
		_synth(1568.0, 1568.0, 0.25, 0, 0.35, 0.0, 0.0, 1.5)]))

	_loop_player = AudioStreamPlayer.new()
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
	if not _streams.has(sfx_name) or get_child_count() > MAX_VOICES:
		return
	var stream: AudioStream = _streams[sfx_name]
	if world_pos.is_finite():
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.unit_size = 12.0
		p3.max_distance = 90.0
		p3.pitch_scale = randf_range(0.9, 1.15)
		add_child(p3)
		p3.global_position = world_pos
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.pitch_scale = randf_range(0.95, 1.05)
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


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
		var env := pow(1.0 - u, decay) * minf(1.0, t * 200.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return data


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
