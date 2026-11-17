extends Node
## Renders each music style without waiting for frames and reports how long it took and how loud each layer is (peak and RMS), to catch silence and clipping.

func _ready() -> void:
	for st in DhMusic.STYLES:
		var m := DhMusic.new()
		add_child(m)
		var t0 := Time.get_ticks_msec()
		m.compose(st, 1234)
		var nj := m._jobs.size()
		while not m._jobs.is_empty():
			m._run(m._jobs.pop_front())
		var ms := Time.get_ticks_msec() - t0
		var line := "MUSIC %s: %d events, rendered %.1f s of audio in %d ms  |" % [st, nj, float(m._n) / float(DhMusic.RATE), ms]
		for l in DhMusic.LAYERS:
			var pl: AudioStreamPlayer = m._players.get(l)
			if pl == null:
				line += " %s: none" % l
				continue
			var d: PackedByteArray = (pl.stream as AudioStreamWAV).data
			var pk := 0
			var sum := 0.0
			var cnt := d.size() / 2
			for i in cnt:
				var v := absi(d.decode_s16(i * 2))
				pk = maxi(pk, v)
				sum += float(v) * float(v)
			line += " %s peak %.2f rms %.3f" % [l, float(pk) / 32767.0, sqrt(sum / float(cnt)) / 32767.0]
		print(line)
		m.queue_free()
	var t1 := Time.get_ticks_msec()
	var a := AudioHooks.new()
	add_child(a)
	var out := "SFX built in %d ms:" % (Time.get_ticks_msec() - t1)
	for k in ["explosion", "kaboom", "sproing", "boing2", "stretch", "snap", "splat", "zap", "rumble", "blip"]:
		var w: AudioStreamWAV = a._streams[StringName(k)]
		var pk := 0
		for i in w.data.size() / 2:
			pk = maxi(pk, absi(w.data.decode_s16(i * 2)))
		out += " %s %.2fs pk %.2f," % [k, float(w.data.size() / 2) / float(AudioHooks.RATE), float(pk) / 32767.0]
	print(out)
	get_tree().quit()
