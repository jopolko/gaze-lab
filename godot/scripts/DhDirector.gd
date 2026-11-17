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
	"mechanichal": {"file": "mechanichal.ogg", "loop": false, "title": "Mechanichal Meaning of a Peanut", "artist": "Calyman", "lic": "CC BY 3.0", "url": "ccmixter.org/files/Lemoneight/61928"},
	"space_echo": {"file": "space_echo.ogg", "loop": true, "title": "Space Echo", "artist": "Centurion_of_war", "lic": "CC0", "url": "opengameart.org/content/space-echo"},
	"dnb": {"file": "dnb.ogg", "loop": true, "title": "1 Minute DnB", "artist": "Of Far Different Nature", "lic": "CC-BY 4.0", "url": "opengameart.org/content/1-minute-dnb"},
	"exodus": {"file": "exodus.ogg", "loop": false, "title": "Electric Exodus", "artist": "FoxSynergy", "lic": "CC-BY 3.0", "url": "opengameart.org/content/electric-exodus"},
	"bouncer": {"file": "bouncer.ogg", "loop": true, "title": "Bouncer", "artist": "Of Far Different Nature", "lic": "CC0", "url": "opengameart.org/node/107501"},
	# the three funk tracks are used exactly as they are (no editing at all: two are NoDerivatives, one ShareAlike): only the playback volume is set, from their measured loudness
	"funk_it": {"file": "funk_it.ogg", "loop": false, "gain": -1.8, "title": "Funk it!", "artist": "SunnyScy", "lic": "CC BY-NC-SA 4.0", "url": "freemusicarchive.org/music/sunnyscy/single/funk-it-1/"},
	"quirky_funk": {"file": "quirky_funk.ogg", "loop": false, "gain": -7.2, "title": "Quirky Funk", "artist": "butterflystudio", "lic": "CC BY-NC-ND 4.0", "url": "freemusicarchive.org/music/butterflystudio/quirky-funk/quirky-funk/"},
	"funk_express": {"file": "funk_express.ogg", "loop": false, "gain": -8.9, "title": "Funk Express", "artist": "butterflystudio", "lic": "CC BY-NC-ND 4.0", "url": "freemusicarchive.org/music/butterflystudio/funky-grooves/funk-express/"},
	"moodless": {"file": "moodless.ogg", "loop": false, "title": "Moodless Refrain (ft. Quiana Nadine)", "artist": "Apoxode", "lic": "CC BY-NC 4.0", "url": "ccmixter.org/files/Apoxode/67475"},
}
const BANDS := {"sunny": ["mechanichal", "funk_it", "quirky_funk", "space_echo"], "lift": ["funk_express", "dnb"], "rush": ["exodus", "bouncer"], "down": ["moodless", "space_echo"]}
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


func start() -> void:
	_base = str(JavaScriptBridge.eval("new URL('music/', document.baseURI).href")) if OS.has_feature("web") else ""
	_age = 0.0
	dbg = "music: starting"


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
	p.volume_db = -80.0
	add_child(p)
	return p


func _db(g: float) -> float:
	return -80.0 if g < 0.003 else maxf(linear_to_db(g) + DhMusic.vol_db(DhMusic.vol_music), -80.0)


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


func _band_for(exc: float) -> String:
	return "sunny" if exc < 0.3 else ("lift" if exc < 0.6 else "rush")


func _next_in(band: String) -> String:
	var l: Array = BANDS[band]
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
	if trip:
		_down = false
	elif _peak > 0.2 and avg < _peak * 0.4:
		_down = true
	if _age > 12.0:
		for n in STEMS:
			_fetch("stem_" + n, "stem_" + n + ".ogg", true)          # the stems come down in the background once the run is going
	# ------------------------------------------------ what should be playing
	var want_mode := "stems" if (trip and not _nostem) else "track"
	var want_band := "down" if _down else _band_for(exc)
	var stems_ready := true
	for n in STEMS:
		if not _cache.has("stem_" + n):
			stems_ready = false
	if want_mode == "stems" and not stems_ready:
		want_mode = "track"
		want_band = "sunny"          # the stems are still on their way: keep what is playing
	if want_mode == "stems":
		if mode != "stems":
			_start_stems()
	else:
		_stem_want = 0.0
		if mode == "stems" and _stem_g < 0.02:
			mode = "none"
		var need_new := mode != "track"
		if mode == "track":
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
