class_name DhDirector
extends Node
## THE MUSIC DIRECTOR. It chooses what plays from what is happening, and moves between pieces with crossfades. The music files (ogg, made by tools/music_build.py) are not part of the
## game's download: each is fetched when it is first wanted (the page's own cache keeps it after that).
##
##   before the first molecule   one of the pre-trip tracks, by how fast the run is going: sunny and chill when it is easy, a lifting dream when it speeds up, hard when it is frantic
##   from the first molecule     the Alien Warfare stems (Kamihamiha), playing together, locked, looping: the ambience is always there and each molecule brings in its own part, so
##                               the music is built from what you are holding. A level lost takes its part away. All six at the top bring in the FX layer: the full piece.
##   after the peak, as it wears off   the comedown track, until the next molecule
##
## When the files cannot be fetched (offline, a desktop run) it says so (`failed`) and the game's own synthesised music takes over.

const DIR := "music/"
const TRACKS := {
	# the three funk tracks are used exactly as they are (no editing at all: two are NoDerivatives, one ShareAlike): only the playback volume is set, from their measured loudness
	"funk_it": {"file": "funk_it.ogg", "loop": false, "gain": -1.8, "title": "Funk it!", "artist": "SunnyScy", "lic": "CC BY-NC-SA 4.0", "url": "freemusicarchive.org/music/sunnyscy/single/funk-it-1/"},
	"quirky_funk": {"file": "quirky_funk.ogg", "loop": false, "gain": -7.2, "title": "Quirky Funk", "artist": "butterflystudio", "lic": "CC BY-NC-ND 4.0", "url": "freemusicarchive.org/music/butterflystudio/quirky-funk/quirky-funk/"},
	"funk_express": {"file": "funk_express.ogg", "loop": false, "gain": -8.9, "title": "Funk Express", "artist": "butterflystudio", "lic": "CC BY-NC-ND 4.0", "url": "freemusicarchive.org/music/butterflystudio/funky-grooves/funk-express/"},
}
const BANDS := {"sunny": ["funk_it", "quirky_funk"], "lift": ["funk_express", "quirky_funk"], "rush": ["funk_express"], "down": ["funk_it", "quirky_funk"]}
const STEMS := ["ambience", "pulse", "bass", "drums", "piano", "guitar", "synth", "acid", "fx"]
const STEM_CREDIT := {"title": "Alien Warfare Stems", "artist": "Kamihamiha", "lic": "CC BY-NC 3.0", "url": "ccmixter.org/files/Kamihamiha/60882"}
const BPM := 128.0          # the stems
const FADE_S := 5.0
const BAR_S := 4.0 * 60.0 / BPM          # one bar of the stems, in seconds

var failed: bool = false
var dbg: String = ""
var mode: String = "none"          # none, track, stems
var cur: String = ""
var _cache: Dictionary = {}
var _asked: Dictionary = {}
var _fails: int = 0
var _cur_p: AudioStreamPlayer = null
var _old_p: AudioStreamPlayer = null
var _cur_g: float = 0.0
var _old_g: float = 0.0
var _stem_p: AudioStreamPlayer = null
var _stem_g: float = 0.0
var _stem_want: float = 0.0
var _sv: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _sync: AudioStreamSynchronized = null
var _age: float = 0.0
var _dwell: float = 0.0
var _peak: float = 0.0
var _down: bool = false
var _band: String = ""
var _deep: bool = false
const OPENING: Array = []          # keys of TRACKS for the opening of a run (fresh, awake): none chosen yet, so the run opens on the wind alone
var _pick: int = -1
var _paused: bool = false
var _paused_sent: bool = false
var _mix_t: float = 0.0
var _sent_db: Dictionary = {}          # what was last sent to each player or stem: every change costs the audio server, so a value goes out only when it has moved


## Sends a volume only when it has moved enough to matter (changing a player's volume every frame was what dropped the game to 8 fps on the web).
func _vol(p: AudioStreamPlayer, db: float) -> void:
	var k := p.get_instance_id()
	if absf(db - float(_sent_db.get(k, 999.0))) > 0.5 or (db <= -79.0 and float(_sent_db.get(k, 0.0)) > -79.0):
		_sent_db[k] = db
		p.volume_db = db


static func credits_text() -> String:
	var lines: Array = []
	for k in TRACKS:
		var t: Dictionary = TRACKS[k]
		lines.append("%s, %s (%s) %s" % [t["title"], t["artist"], t["lic"], t["url"]])
	lines.append("%s, %s (%s) %s" % [STEM_CREDIT["title"], STEM_CREDIT["artist"], STEM_CREDIT["lic"], STEM_CREDIT["url"]])
	return "Music: " + "; ".join(lines)


var _base: String = ""
var _nostem: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("nostem")          # ?nostem: tracks only (to measure what the stems cost)
var _want_key: String = ""
var _still: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("still")          # ?still: play, but leave the players alone after starting them (to measure)
var _noplay: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("noplay")          # ?noplay: fetch but never play (to measure)


var _stem_after: float = 12.0


func start() -> void:
	if OS.has_feature("web"):
		# the stems are about 3.6 MB: on a slow or metered connection they wait longer (the tracks play meanwhile)
		var slow := bool(JavaScriptBridge.eval("(navigator.connection && (navigator.connection.saveData || /(^|-)(2g|3g)/.test(navigator.connection.effectiveType || ''))) ? true : false"))
		_stem_after = 60.0 if slow else 20.0
	_base = str(JavaScriptBridge.eval("new URL('music/', document.baseURI).href")) if OS.has_feature("web") else ""
	_age = 0.0
	dbg = "music: starting"
	Game.sfx_requested.connect(_on_sfx)


func stop() -> void:
	for p in [_cur_p, _old_p, _stem_p]:
		if p != null and is_instance_valid(p):
			p.stop()


## The seconds until the next beat of the stems (div 1 = a beat, 4 = a bar, 0.5 = an eighth note; the stems are in 4/4), or -1 when they are not playing: a sound that waits for it lands on the beat.
func secs_to_beat(div: float = 1.0) -> float:
	if _stem_p == null or not _stem_p.playing or mode != "stems":
		return -1.0
	var pos := _stem_p.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var beat := 60.0 / BPM * maxf(div, 0.01)
	return beat - fposmod(pos, beat)


var _lq: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]          # the stem levels as last settled on a bar line
var _last_bar: int = -1
var _first_q: bool = true


## Where the stems are in their 16-bar loop, in bars (0 to 16), or -1 when they are not playing.
func bar_pos() -> float:
	if _stem_p == null or not _stem_p.playing or mode != "stems":
		return -1.0
	var pos := _stem_p.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return fposmod(pos, 16.0 * BAR_S) / BAR_S


## The wave, 0 to 1, `ahead` seconds from now: it swells over six bars and falls away over two, over and over (so each wave comes on slowly and lets go quickly). 0.5 when the stems
## are not playing. The effects breathe with it and the course is paced by it.
func wave_at(ahead: float) -> float:
	var b := bar_pos()
	if b < 0.0:
		return 0.5
	b = fposmod(b + ahead / BAR_S, 8.0)
	return smoothstep(0.0, 1.0, b / 6.0) if b < 6.0 else 1.0 - (b - 6.0) / 2.0


func _fetch(key: String, file: String, loop: bool) -> void:
	if _cache.has(key) or _asked.has(key):
		return
	_asked[key] = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 1000:
			_fails += 1
			_asked.erase(key)
			return
		var s := AudioStreamOggVorbis.load_from_buffer(body)
		if s == null:
			_fails += 1
			return
		s.loop = loop
		_cache[key] = s)
	var err := req.request(_base + file)
	if err != OK:
		req.queue_free()
		_fails += 1
		_asked.erase(key)


func _mk_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Master"
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM          # music is streamed: as a browser "sample" a long track could not be paused or looped (the browser refused to copy it, and it fell silent)
	p.volume_db = -80.0
	add_child(p)
	return p


var _duck: float = 0.0


func _on_sfx(_n: StringName, _p: Vector3) -> void:
	_duck = 1.0          # every effect takes a little of the music's level for a moment, so it sits on top of it without being louder


func _db(g: float) -> float:
	return -80.0 if g < 0.003 else maxf(linear_to_db(g * (1.0 - 0.28 * _duck)) + DhMusic.vol_db(DhMusic.vol_music), -80.0)


func _play_track(key: String) -> void:
	if _noplay:
		return
	if _old_p != null and is_instance_valid(_old_p):
		_old_p.stop()
		_old_p.queue_free()
	_old_p = _cur_p
	_old_g = _cur_g
	_cur_p = _mk_player()
	_cur_p.stream = _cache[key]
	_cur_p.play(0.0)
	if _still:
		_cur_p.volume_db = -8.0
	_cur_g = 0.0
	cur = key
	mode = "track"
	_dwell = 0.0


## THE WIND: a soft rush of air that rises with speed and opens up in the air off a ramp. Not music: it is the sound of going downhill, and it is all there is under the
## opening until a track is chosen for it. One short loop of smoothed noise, made once.
var _wind_p: AudioStreamPlayer = null
var _wind_g: float = 0.0
var _wind_on: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.search")).contains("wind")          # ?wind: off unless asked for (made noise, unheard by its author: not to be trusted on by default)


func _wind_make() -> void:
	var sr := 22050
	var n := sr * 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var a := PackedFloat32Array()
	a.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var hp := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += (w - lp1) * 0.2          # two gentle low-passes: a soft rush with no hiss
		lp2 += (lp1 - lp2) * 0.2
		hp += (lp2 - hp) * 0.03          # and the rumble taken out from underneath
		var slow := 0.75 + 0.25 * sin(TAU * float(i) / float(n) * 3.0)          # it breathes, three times a loop (whole cycles, so the loop joins)
		a[i] = (lp2 - hp) * slow
	var c := sr / 2          # half a second of the end blended into the start
	var pk := 0.001
	for i in c:
		var k := float(i) / float(c)
		a[i] = a[i] * k + a[n - c + i] * (1.0 - k)
	n -= c
	for i in n:
		pk = maxf(pk, absf(a[i]))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(a[i] / pk, -1.0, 1.0) * 30000.0))
	var wv := AudioStreamWAV.new()
	wv.format = AudioStreamWAV.FORMAT_16_BITS
	wv.mix_rate = sr
	wv.stereo = false
	wv.data = bytes
	wv.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wv.loop_begin = 0
	wv.loop_end = n
	_wind_p = _mk_player()
	_wind_p.stream = wv
	_wind_p.play()


func _wind_mix(spd: float, air: bool, d: float) -> void:
	if not _wind_on:
		return
	if _wind_p == null:
		_wind_make()
	var want := clampf((spd - 0.15) * 1.1, 0.0, 0.8) * (1.5 if air else 1.0)
	if _paused:
		want = 0.0
	_wind_g = move_toward(_wind_g, want, d * (1.6 if air else 0.6))
	_vol(_wind_p, -80.0 if _wind_g < 0.01 else linear_to_db(_wind_g) - 23.0 + DhMusic.vol_db(DhMusic.vol_sfx))


func _band_for(exc: float) -> String:
	return "sunny" if exc < 0.3 else ("lift" if exc < 0.6 else "rush")


func _next_in(band: String) -> String:
	var l: Array = OPENING if band == "opening" else BANDS[band]
	_pick += 1
	var k := String(l[_pick % l.size()])
	if k == cur and l.size() > 1:
		k = String(l[(_pick + 1) % l.size()])
	return k


## state: avg (0..1 of all six molecules felt), holds (six values 0..1), dmt (0..1), exc (0..1, how hard the run is going), paused.
func update(delta: float, st: Dictionary) -> void:
	_age += delta
	_dwell += delta
	_paused = bool(st.get("paused", false))
	if _still and mode == "track":
		return
	if _paused != _paused_sent:
		_paused_sent = _paused
		for p in [_cur_p, _old_p, _stem_p]:
			if p != null and is_instance_valid(p):
				p.stream_paused = _paused
	if _fails >= 3 and _cache.is_empty():
		failed = true
		dbg = "music: files not found"
		return
	var avg := float(st.get("avg", 0.0))
	var exc := float(st.get("exc", 0.0))
	var holds: Array = st.get("holds", [0, 0, 0, 0, 0, 0])
	_peak = maxf(_peak - 0.003 * delta, avg)
	var trip := avg >= 0.03
	# THE ORDER OF THE NIGHT: the plain run opens without the funk (OPENING holds the opening music once it is chosen; until then there is the wind and the board), the funk comes
	# in when the first molecules are felt, and the stems take over once it runs deeper. Going back down, the funk returns.
	if avg >= 0.2:
		_deep = true
	elif avg < 0.11:
		_deep = false
	if trip:
		_down = false
	elif _peak > 0.2 and avg < _peak * 0.4:
		_down = true
	if _age > minf(_stem_after, 2.0 if _stem_after < 30.0 else _stem_after):
		for n in STEMS:
			_fetch("stem_" + n, "stem_" + n + ".ogg", true)          # the stems come down in the background once the run is going
	# ------------------------------------------------ what should be playing
	var want_mode := "stems" if (_deep and not _nostem) else ("track" if (trip or _down or not OPENING.is_empty()) else "none")
	if want_mode == "none" and not _nostem:
		want_mode = "stems"          # before the first molecule: the stems' ambience alone (every other part is at nothing until its molecule is held)
	var want_band := "down" if _down else _band_for(exc)
	if not trip and not _down and not OPENING.is_empty():
		want_band = "opening"
	var stems_ready := true
	for n in STEMS:
		if not _cache.has("stem_" + n):
			stems_ready = false
	if want_mode == "stems" and not stems_ready:
		want_mode = "track" if (trip or _down) else "none"          # the stems are still on their way: the funk if the run has already begun to turn, otherwise quiet
		want_band = "sunny"
	if want_mode == "stems":
		if mode != "stems":
			_start_stems()
	else:
		_stem_want = 0.0
		if mode == "stems" and _stem_g < 0.02:
			mode = "none"
		var need_new := mode != "track" and want_mode == "track"
		if mode == "track" and want_mode == "track":
			var l: Array = BANDS.get(_band, [])
			var ended: bool = _cur_p != null and not TRACKS[cur]["loop"] and _cur_p.stream != null and _cur_p.get_playback_position() > (_cur_p.stream as AudioStream).get_length() - FADE_S - 1.0
			if ended or (want_band != _band and _dwell > 40.0 and not l.has(cur)):
				need_new = true
		if need_new:
			if _want_key == "":
				_want_key = _next_in(want_band)          # chosen once, then waited for while it downloads
			var key := _want_key
			_fetch(key, String(TRACKS[key]["file"]), bool(TRACKS[key]["loop"]))
			if _cache.has(key):
				_band = want_band
				_want_key = ""
				_play_track(key)
		elif mode == "none" and _age < 1.0:
			var k0 := String(BANDS["sunny"][0])
			_fetch(k0, String(TRACKS[k0]["file"]), bool(TRACKS[k0]["loop"]))
	# ------------------------------------------------ the mix (ten times a second, not every frame)
	_mix_t += delta
	if _mix_t >= 0.1:
		var d := _mix_t
		_mix_t = 0.0
		_duck = maxf(_duck - d * 4.0, 0.0)
		_wind_mix(float(st.get("spd", 0.0)), bool(st.get("air", false)), d)
		var step := d / FADE_S
		if mode == "track" and _cur_p != null:
			_cur_g = minf(_cur_g + step, 1.0) if want_mode == "track" else maxf(_cur_g - step * 1.4, 0.0)
		if _old_p != null and is_instance_valid(_old_p):
			_old_g = maxf(_old_g - step, 0.0)
			_vol(_old_p, _db(_old_g))
			if _old_g <= 0.0:
				_old_p.stop()
				_old_p.queue_free()
				_old_p = null
		if _cur_p != null and is_instance_valid(_cur_p):
			_vol(_cur_p, _db(_cur_g * 0.9) + (float(TRACKS[cur].get("gain", 0.0)) if mode == "track" and TRACKS.has(cur) else 0.0))
			if want_mode == "stems" and mode == "stems":
				_cur_g = maxf(_cur_g - step * 1.4, 0.0)
		if _stem_p != null and is_instance_valid(_stem_p):
			_stem_g = move_toward(_stem_g, _stem_want, step * 1.2)
			_vol(_stem_p, _db(_stem_g * 0.85))
			var lv := [1.0, float(holds[0]), maxf(float(holds[5]), avg * 1.3), maxf(float(holds[5]), avg * 1.3), float(holds[1]), float(holds[4]), float(holds[2]), float(holds[3]), float(st.get("dmt", 0.0))]
			# parts come in and go out on bar lines (every second bar), not whenever the number happens to change
			var bp := bar_pos()
			if bp >= 0.0:
				var bi := int(floor(bp))
				if _first_q or (bi != _last_bar and bi % 2 == 0):
					_lq = lv.duplicate()
					_first_q = false
				_last_bar = bi
			else:
				_first_q = true
				_lq = lv.duplicate()
			for i in STEMS.size():
				_sv[i] = lerpf(_sv[i], clampf(float(_lq[i]), 0.0, 1.0), clampf(d * 1.6, 0.0, 1.0))
				var sdb := -80.0 if _sv[i] < 0.02 else lerpf(-24.0, 0.0, pow(_sv[i], 0.7))
				if absf(sdb - float(_sent_db.get(1000 + i, 999.0))) > 0.5:
					_sent_db[1000 + i] = sdb
					_sync.set_sync_stream_volume(i, sdb)
			if mode != "stems" and _stem_g <= 0.0 and _stem_p.playing:
				_stem_p.stop()
	dbg = "music: %s %s" % [mode, cur if mode == "track" else "%d/9 stems" % _loaded_stems()]


func _loaded_stems() -> int:
	var n := 0
	for s in STEMS:
		if _cache.has("stem_" + s):
			n += 1
	return n


func _start_stems() -> void:
	if _noplay:
		return
	if _sync == null:
		_sync = AudioStreamSynchronized.new()
		_sync.stream_count = STEMS.size()
		for i in STEMS.size():
			_sync.set_sync_stream(i, _cache["stem_" + String(STEMS[i])])
			_sync.set_sync_stream_volume(i, -80.0)
	if _stem_p == null or not is_instance_valid(_stem_p):
		_stem_p = _mk_player()
		_stem_p.stream = _sync
	if not _stem_p.playing:
		_stem_p.play(0.0)
	_stem_want = 1.0
	mode = "stems"
	cur = "stems"
