class_name Telemetry
extends Node
## Passive diagnostics, so that when a tester says "it sucked" we can see why. It never changes how anything works: once a second it writes down how the game, the phone / computer
## and the tracker were doing, names what looks wrong (too dark, backlit, bad angle, squinting, too far, phone shaking or lying flat, frame rate, GPU or CPU maxed, tracker slow
## or late, main thread stalls, camera problems), notes every gate, and sends it to the server in small batches. No pictures, no video, no names. The camera never leaves the device.
## Off with ?noshare, or the DIAGNOSTICS button on the pause screen.
##
## Records (kind): env (once), tick (every second), incident (a problem that lasted 2 s or more, when it started and again when it ended), gate (every barrier), sum (running totals),
## sensor (camera track ended / muted), feltbad (the player pressed THAT FELT BAD: the last 40 seconds ride along).

const TICK := 1.0
const LIGHT_EVERY := 8.0
const MIN_FLAG_S := 2.0

static var inst: Telemetry = null

var rig: Object = null
var flags: Dictionary = {}               # code -> seconds it has been true right now
var _ctx: Dictionary = {}                # code -> the numbers when it started
var _time_in: Dictionary = {}            # code -> total seconds
var _acc: float = 0.0
var _ft: PackedFloat32Array = PackedFloat32Array()
var _ring: Array = []
var _total: float = 0.0
var _light: Dictionary = {}
var light_fast: bool = false             # the set-up ring is on screen: look at the light every second instead of every 8
var _light_t: float = 0.0
var _sum_t: float = 0.0
var _fps_sum: float = 0.0
var _fps_n: int = 0
var _gates: int = 0
var _hits: int = 0
var _live: bool = false
var _tel_ms: float = 0.0
var _tick_mul: float = 1.0
var _tr: Array = []
var _tr_acc: float = 0.0

const SETUP_JS := "(function(){if(window.__tl)return;var q=[],tm=null,who='',sid='';try{who=localStorage.getItem('gazelab_id')||'';if(!who){who='anon-'+Math.random().toString(16).slice(2,8);localStorage.setItem('gazelab_id',who);}}catch(e){who='anon-'+Math.random().toString(16).slice(2,8);}sid=Math.random().toString(16).slice(2,8);var dev=(location.hostname==='localhost'||location.port==='8443'||location.port==='8060');function on(){try{if(/[?&]noshare/.test(location.search))return false;return localStorage.getItem('gazelab_share')!=='0';}catch(e){return true;}}function send(items,beacon){var o={kind:'batch',who:who,sid:sid,device:(matchMedia('(pointer: coarse)').matches?'mobile':'desktop'),app:'downhill',items:items};var body=JSON.stringify(o);var u=dev?'/tune':'/gaze-lab/log.php';try{if(beacon&&navigator.sendBeacon)navigator.sendBeacon(u,body);else fetch(u,{method:'POST',body:body,keepalive:true});}catch(e){}}function flush(beacon){tm=null;if(!q.length)return;var items=q;q=[];if(!on())return;while(items.length){var take=[],len=0;while(items.length&&len<20000){var it=items.shift();take.push(it);len+=it.__n;}take.forEach(function(x){delete x.__n;});send(take,beacon);}}var st={lt:0,ltmax:0,err:0,vis:0};try{new PerformanceObserver(function(l){l.getEntries().forEach(function(e){st.lt++;if(e.duration>st.ltmax)st.ltmax=Math.round(e.duration);});}).observe({type:'longtask'});}catch(e){}window.addEventListener('error',function(){st.err++;});window.addEventListener('unhandledrejection',function(){st.err++;});document.addEventListener('visibilitychange',function(){st.vis++;if(document.hidden)flush(true);});window.addEventListener('pagehide',function(){flush(true);});var env={};try{var c=document.createElement('canvas');var gl=c.getContext('webgl');var d=gl&&gl.getExtension('WEBGL_debug_renderer_info');env.gpu=d?gl.getParameter(d.UNMASKED_RENDERER_WEBGL):'';}catch(e){}env.cores=navigator.hardwareConcurrency||0;env.mem=navigator.deviceMemory||0;env.ua=(navigator.userAgent||'').slice(0,160);env.scr=[screen.width,screen.height,window.devicePixelRatio||1];env.coarse=matchMedia('(pointer: coarse)').matches;env.net=(navigator.connection&&navigator.connection.effectiveType)||'';var bat=-1,chg=false;try{navigator.getBattery&&navigator.getBattery().then(function(b){bat=Math.round(b.level*100);chg=b.charging;b.addEventListener('levelchange',function(){bat=Math.round(b.level*100);});});}catch(e){}var lc=null;window.__tl={who:who,sid:sid,env:env,push:function(o){var s=JSON.stringify(o);o.__n=s.length;q.push(o);if(!tm)tm=setTimeout(function(){flush(false);},3000);},flush:flush,take:function(){var o={lt:st.lt,ltmax:st.ltmax,err:st.err,vis:st.vis,bat:bat,chg:chg,heap:(performance.memory?Math.round(performance.memory.usedJSHeapSize/1048576):-1),hid:document.hidden};st.lt=0;st.ltmax=0;st.err=0;return JSON.stringify(o);},light:function(){try{var v=window.__gazeVideo;if(!v||v.readyState<2)return '';var W=32,H=24;if(!lc){lc=document.createElement('canvas');lc.width=W;lc.height=H;}var x=lc.getContext('2d',{willReadFrequently:true});x.drawImage(v,0,0,W,H);var d=x.getImageData(0,0,W,H).data;var g=window.__gaze||{};var fx=g.nx!==undefined?(1-g.nx)*W:W/2,fy=g.ny!==undefined?g.ny*H:H/2,fr=Math.max(3,(g.fw||0.3)*W*0.5);var sf=0,sf2=0,nf=0,sb=0,nb=0,ns=0,nd=0,sl=0,nl=0,sr=0,nr=0,ne=0,nge=0;for(var j=0;j<H;j++){for(var i=0;i<W;i++){var k=(j*W+i)*4,l=0.299*d[k]+0.587*d[k+1]+0.114*d[k+2];if(Math.abs(i-fx)<fr&&Math.abs(j-fy)<fr*1.2){sf+=l;sf2+=l*l;nf++;if(l>240)ns++;if(l<30)nd++;if(i<fx){sl+=l;nl++;}else{sr+=l;nr++;}if(j<fy-fr*0.1&&j>fy-fr*0.75){ne++;if(l>235)nge++;}}else{sb+=l;nb++;}}}if(nf<6)return '';var mf=sf/nf,sd=Math.sqrt(Math.max(sf2/nf-mf*mf,0)),mb=nb?sb/nb:mf;return JSON.stringify({face:Math.round(mf),contrast:Math.round(sd),bg:Math.round(mb),sat:Math.round(100*ns/nf),dk:Math.round(100*nd/nf),l:Math.round(nl?sl/nl:mf),r:Math.round(nr?sr/nr:mf),eye:Math.round(ne?100*nge/ne:0)});}catch(e){return '';}}};window.__tlTrack=function(tr){try{tr.addEventListener('ended',function(){window.__tl.push({kind:'sensor',what:'camera track ended'});});tr.addEventListener('mute',function(){window.__tl.push({kind:'sensor',what:'camera muted'});});tr.addEventListener('unmute',function(){window.__tl.push({kind:'sensor',what:'camera unmuted'});});}catch(e){}};window.__tl.push({kind:'env',env:env});})()"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	inst = self
	if not OS.has_feature("web"):
		set_process(false)
		return
	JavaScriptBridge.eval(SETUP_JS)
	_live = true


static var _rig_wait: Object = null


static func set_rig(r: Object) -> void:
	_rig_wait = r                                      # the run can be set up before this node exists: it is picked up at the next tick
	if inst != null:
		inst.rig = r


static func sharing() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("(function(){try{if(/[?&]noshare/.test(location.search))return false;return localStorage.getItem('gazelab_share')!=='0'}catch(e){return true}})()"))


static func set_sharing(on: bool) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('gazelab_share','%s')}catch(e){}" % ("1" if on else "0"))


func _post(rec: Dictionary) -> void:
	if not _live:
		return
	rec["t"] = snappedf(float(Time.get_ticks_msec()) / 1000.0, 0.1)
	_buf.append(JSON.stringify(rec))          # kept in memory: nothing is handed to the page while the game is being played
	if String(rec.get("kind", "")) == "sum" or _buf.size() >= 400:
		flush_now()


var _buf: PackedStringArray = PackedStringArray()
var _was_paused: bool = false
var _last_flush_ms: int = 0


## Hand what has been kept to the page's own sender (one call, not one per record). At a pause, the end of a level, losing focus, or a big buffer (400 records).
func flush_now() -> void:
	if _buf.is_empty():
		return
	JavaScriptBridge.eval("(function(a){var q=window.__tl;if(!q)return;for(var i=0;i<a.length;i++)q.push(a[i]);})([" + ",".join(_buf) + "])")
	_buf = PackedStringArray()
	_last_flush_ms = Time.get_ticks_msec()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_now()


func _process(delta: float) -> void:
	if not _live:
		return
	var pz := get_tree().paused or (rig != null and is_instance_valid(rig) and bool(rig.get("_paused")))
	if pz and not _was_paused:
		flush_now()          # the game has just been paused: a good moment, nothing is moving
	_was_paused = pz
	_ft.append(delta * 1000.0 / maxf(Engine.time_scale, 0.05))
	_acc += delta
	_tr_acc += delta
	if _tr_acc >= 0.2:                               # five times a second: each stage of the gaze, so a bad cursor can be traced to the stage that broke
		_tr_acc = 0.0
		var P := GazeProvider
		if P.backend == P.Backend.CAMERA and _tr.size() < 8:
			# iris inside the eye (x, y), geometry gaze before offsets (x, y), after the median (x, y), final cursor (x, y), head yaw, head pitch, learned offset (x, y), iris radius px, eyes-only ok
			_tr.append([snappedf(P.eih.x, 0.01), snappedf(P.eih.y, 0.01), snappedf(P._geo_raw.x, 0.01), snappedf(P._geo_raw.y, 0.01), snappedf(P._last_g.x, 0.01), snappedf(P._last_g.y, 0.01), snappedf(P.gaze.x, 0.01), snappedf(P.gaze.y, 0.01), snappedf(P.head_rpy.x, 0.01), snappedf(P.head_rpy.y, 0.01), snappedf(P.bias.bias.x, 0.01), snappedf(P.bias.bias.y, 0.01), snappedf(P.limb_rad, 0.1), 1 if P.eih_ok else 0, 1 if P.bias.saturated else 0])
	if _acc >= TICK * _tick_mul:
		var t0 := Time.get_ticks_usec()
		_tick(_acc)
		_tel_ms = float(Time.get_ticks_usec() - t0) / 1000.0          # what the diagnostics themselves cost, so it can be checked in the data
		_tick_mul = 4.0 if _tel_ms > 15.0 else 1.0          # on a slow phone one tick cost about 30 ms, a hitch every second: report a quarter as often (the data inside is the same, just summed over longer)
		_acc = 0.0
		_ft = PackedFloat32Array()


func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(int(float(b.size() - 1) * q), b.size() - 1)]


var _gaze_gap: int = 0          # the least time (ms) between frames sent to the face model

## ADAPTIVE TRACKER: when the game itself is slow the tracker is asked for fewer frames (the camera and model share the phone with the picture), and it is let go again when
## the game has room. The steering is slower with a long gap, so it is only used when the picture would otherwise stutter. Hysteresis: it tightens fast and loosens slowly.
func _adapt_tracker(fps: float) -> void:
	if not OS.has_feature("web"):
		return
	var want := _gaze_gap
	if fps < 20.0:
		want = 140
	elif fps < 26.0:
		want = maxi(want, 100)
	elif fps < 32.0:
		want = maxi(want, 60) if want == 0 else want
	elif fps > 42.0:
		want = maxi(want - 30, 0)
	if want != _gaze_gap:
		_gaze_gap = want
		JavaScriptBridge.eval("window.__gazeGap=%d" % want)


func _tick(dt: float) -> void:
	var P := GazeProvider
	if (rig == null or not is_instance_valid(rig)) and _rig_wait != null and is_instance_valid(_rig_wait):
		rig = _rig_wait
	var r := {"kind": "tick"}
	var fps := float(_ft.size()) / maxf(dt, 0.001)
	var f95 := _pct(_ft, 0.95)
	var fmax := _pct(_ft, 1.0)
	var cpu_ms := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	r["tel"] = snappedf(_tel_ms, 0.01)
	r["fps"] = snappedf(fps, 0.1)
	r["ft50"] = snappedf(_pct(_ft, 0.5), 0.1)
	r["ft95"] = snappedf(f95, 0.1)
	r["ftmax"] = snappedf(fmax, 0.1)
	r["cpu"] = snappedf(cpu_ms, 0.1)
	r["gp"] = snappedf(P.proc_ms, 0.01)          # the gaze provider's own time on the game thread, ms
	r["gap"] = _gaze_gap
	_adapt_tracker(fps)
	r["draws"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	r["prims"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	r["mem"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	r["rs"] = snappedf(RScale.cur if OS.has_feature("web") else get_viewport().scaling_3d_scale, 0.01)
	var js: Variant = JSON.parse_string(str(JavaScriptBridge.eval("window.__tl?window.__tl.take():''")))
	if js is Dictionary:
		r["js"] = js
	if light_fast:
		_light_t = minf(_light_t, 1.0)
	_light_t -= dt
	if _light_t <= 0.0 and P.backend == P.Backend.CAMERA:
		_light_t = 1.0 if light_fast else LIGHT_EVERY
		var lt: Variant = JSON.parse_string(str(JavaScriptBridge.eval("window.__tl?window.__tl.light():''")))
		_light = lt as Dictionary if lt is Dictionary else {}
		if not _light.is_empty():
			_light["backlit"] = int(_light["bg"]) - int(_light["face"])
	if not _light.is_empty():
		r["light"] = _light
	var cam := P.backend == P.Backend.CAMERA
	r["cam"] = cam
	var ws := DisplayServer.window_get_size()
	r["port"] = ws.y > ws.x          # portrait or landscape: to compare how the tracking does in each
	r["win"] = [ws.x, ws.y]
	var fresh := false
	if cam:
		fresh = P._camera_fresh()
		r["fresh"] = fresh
		r["conf"] = snappedf(P.confidence, 0.01)
		r["face"] = snappedf(P.face_size, 0.01)
		r["trk"] = snappedf(float(P._pkt_times.size()) / 2.0, 0.1)
		r["lat"] = int(P.trk_lat_ms)
		r["model"] = int(P.trk_inf_ms)
		r["dlg"] = P.trk_delegate
		r["video"] = P.trk_video
		r["drop"] = P.trk_dropped
		r["roilost"] = P.trk_roi_lost
		r["head"] = [snappedf(P.head_rpy.x, 0.01), snappedf(P.head_rpy.y, 0.01), snappedf(P.head_rpy.z, 0.01)]
		r["open"] = snappedf(P._last_open, 0.01)
		r["gaze"] = [snappedf(P.gaze.x, 0.01), snappedf(P.gaze.y, 0.01)]
		r["rawg"] = [snappedf(P._last_g.x, 0.01), snappedf(P._last_g.y, 0.01)]
		r["state"] = P.camera_status
		r["tr"] = _tr
		r["kit"] = [1 if P.kit_used() else 0, snappedf(P.kit.x, 0.01), snappedf(P.kit.centre, 0.001), 1 if P.kit.held else 0, 1 if P.kit.fitted() else 0, snappedf(P.kit.gaze_x, 0.01), P.kit.zone]          # the STARGAZE sideways reading: in use, the look (-1 .. +1), its centre, held for a blink
		r["mix"] = [1 if P.mix_used() else 0, snappedf(P.mix.value, 0.01), snappedf(float(P.mix.w[0]), 0.1), snappedf(float(P.mix.w[1]), 0.1), snappedf(float(P.mix.w[2]), 0.1)]          # phone eye blend: in use, value in glances, the three weights
		if rig != null and is_instance_valid(rig):
			r["ex"] = [float(rig.get("_ex_sign")), snappedf(float(rig.get("_ex_full")), 0.0001), snappedf(float(rig.get("_ex_ref")), 0.0001), snappedf(float(rig.get("_off_now")), 0.01)]          # steering: direction, glance size, centre, the look as the game reads it
		_tr = []
	if rig != null and is_instance_valid(rig):
		r["pf"] = [snappedf(float(rig.get("_pf_phys")), 0.1), snappedf(float(rig.get("_pf_hud")), 0.1), snappedf(float(rig.get("_pf_focus")), 0.1)]          # where a game frame goes, ms: physics, HUD drawing, aim / focus
	if rig != null and is_instance_valid(rig):
		r["z"] = int(-float((rig.get("spos") as Vector3).z))          # where on the course
		r["reg"] = str(rig.get("_player_region"))
		r["warm"] = int(rig.get("warm_ms"))          # how long GET READY took on this device, ms
	r["shake"] = snappedf(P.pm.shake, 0.01)
	r["tilt"] = [snappedf(P.pm.tilt_x, 0.1), snappedf(P.pm.tilt_y, 0.1)]
	r["lap"] = snappedf(P.pm.lap, 0.01)
	if rig != null and is_instance_valid(rig):
		r["z"] = int(-float(rig.get("spos").z))
		r["spd"] = int((rig.get("vel") as Vector2).length())
		r["crash"] = int(rig.get("crashes"))
		r["paused"] = bool(rig.get("_paused"))
	var fl := _classify(r, fps, f95, fmax, cpu_ms, cam, fresh)
	r["flags"] = fl
	_post(r)
	_ring.append(r)
	if _ring.size() > 40:
		_ring.pop_front()
	_total += dt
	_fps_sum += fps
	_fps_n += 1
	_sum_t += dt
	if _sum_t >= 10.0:
		_sum_t = 0.0
		_post({"kind": "sum", "play": snappedf(_total, 0.1), "in": _time_in.duplicate(), "fps_avg": snappedf(_fps_sum / maxf(float(_fps_n), 1.0), 0.1), "gates": _gates, "hits": _hits})


## What is wrong with the light on the face, from one camera sample: "" (fine), "flat", "dark", "bright", "back" (the light is behind you), "side_l" / "side_r" (one half of
## the face is much brighter; l / r are the halves of the camera picture) or "glare" (blown-out patches over the eyes: glasses catching a lamp or the screen).
static func light_issue(lt: Dictionary) -> String:
	if lt.is_empty():
		return ""
	var face := float(lt.get("face", 128))
	if int(lt.get("contrast", 99)) < 12:
		return "flat"
	if face < 55.0:
		return "dark"
	if int(lt.get("sat", 0)) >= 12 or face > 200.0:
		return "bright"
	if float(lt.get("backlit", 0)) > 45.0 and face < 120.0:
		return "back"
	var l := float(lt.get("l", face))
	var r := float(lt.get("r", face))
	if absf(l - r) > maxf(38.0, 0.4 * maxf(l, r)):
		return "side_l" if l > r else "side_r"
	if int(lt.get("eye", 0)) >= 10:
		return "glare"
	return ""


## What looks wrong right now, in a few words each. Every threshold is written next to the raw numbers in the tick, so it can be changed later without losing the history.
func _classify(r: Dictionary, fps: float, f95: float, fmax: float, cpu_ms: float, cam: bool, fresh: bool) -> Array:
	var now: Dictionary = {}
	var lt: Dictionary = r.get("light", {})
	if bool(r.get("paused", false)):
		return []
	if cam and not fresh:
		now["cam_stalled"] = true
	elif cam:
		var face := float(r.get("face", 0.0))
		var conf := float(r.get("conf", 0.0))
		if conf < 0.3 or face < 0.05:
			now["no_face"] = true
		else:
			if face < 0.14:
				now["too_far"] = true
			if face > 0.55:
				now["too_close"] = true
			var head: Array = r.get("head", [0.0, 0.0, 0.0])
			if absf(float(head[0])) > 0.6 or absf(float(head[1])) > 0.6 or absf(float(head[2])) > 0.6:
				now["bad_angle"] = true
			if float(r.get("open", 1.0)) < 0.2 and float(r.get("open", 1.0)) > 0.0:
				now["squint"] = true
			if float(r.get("trk", 99.0)) < 10.0:
				now["tracker_slow"] = true
			if int(r.get("lat", 0)) > 250:
				now["tracker_late"] = true
			if int(r.get("model", 0)) > 90:
				now["model_slow"] = true
		var li := light_issue(lt)
		if li != "":
			now[{"flat": "flat_picture", "dark": "dark_face", "bright": "overexposed_face", "back": "backlit_face", "side_l": "side_light", "side_r": "side_light", "glare": "eye_glare"}[li]] = true
	if float(r.get("shake", 0.0)) > 0.5:
		now["phone_shaking"] = true
	if float(r.get("lap", 0.0)) > 0.65:
		now["phone_flat"] = true
	if fps < 30.0:
		now["low_fps"] = true
		if cpu_ms > 0.7 * f95 and f95 > 25.0:
			now["cpu_bound"] = true
		elif f95 > 25.0 and cpu_ms < 0.45 * f95:
			now["gpu_bound"] = true
	if fmax > 150.0:
		now["freeze"] = true
	var jsd: Dictionary = r.get("js", {})
	if int(jsd.get("ltmax", 0)) > 120:
		now["main_thread_busy"] = true
	if int(jsd.get("err", 0)) > 0:
		now["js_errors"] = true
	if bool(jsd.get("hid", false)):
		now["page_hidden"] = true
	var out: Array = []
	for code in now:
		out.append(code)
		_time_in[code] = float(_time_in.get(code, 0.0)) + TICK
		flags[code] = float(flags.get(code, 0.0)) + TICK
		if not _ctx.has(code):
			_ctx[code] = {"t0": r.get("t", 0), "fps": r["fps"], "face": r.get("face"), "light": lt, "head": r.get("head"), "open": r.get("open"), "trk": r.get("trk"), "lat": r.get("lat"), "model": r.get("model"), "cpu": r["cpu"], "ft95": r["ft95"]}
		if float(flags[code]) >= MIN_FLAG_S and not bool((_ctx[code] as Dictionary).get("sent", false)):
			(_ctx[code] as Dictionary)["sent"] = true
			_post({"kind": "incident", "what": code, "state": "start", "ctx": (_ctx[code] as Dictionary).duplicate()})
	for code2 in flags.keys():
		if not now.has(code2):
			if bool((_ctx.get(code2, {}) as Dictionary).get("sent", false)):
				_post({"kind": "incident", "what": code2, "state": "end", "dur": flags[code2]})
			flags.erase(code2)
			_ctx.erase(code2)
	return out


## One barrier: which gate you went through, how far from its middle, whether your eyes had chosen one, how fast, and what was wrong at the time.
static func barrier(d: Dictionary) -> void:
	if inst == null or not inst._live:
		return
	inst._gates += 1
	if bool(d.get("hit", false)):
		inst._hits += 1
	d["kind"] = "gate"
	d["flags"] = inst.flags.keys()
	inst._post(d)


## A one-off record (the result of the follow-the-dot fit, ...).
static func event(kind: String, d: Dictionary) -> void:
	if inst == null:
		return
	d["kind"] = kind
	inst._post(d)


## THAT FELT BAD: keep the last 40 seconds with the note.
static func felt_bad(why: String) -> void:
	if inst == null or not inst._live:
		return
	inst._post({"kind": "feltbad", "why": why, "flags": inst.flags.keys(), "in": inst._time_in.duplicate(), "window": inst._ring.duplicate()})
	JavaScriptBridge.eval("window.__tl&&window.__tl.flush(false)")
