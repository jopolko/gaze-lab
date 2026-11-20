extends Node
## Captures the psychedelic TRIP MODEL from the real game so web/downhill-three/psyfx.js can be checked against it (and the picture at several depths).
## Boots ALL DRESSED (the journey, the six molecules, the clarity moments), plays a fixed scripted run at 60 Hz (the same events at the same times), and records, every frame, the inputs the model reads
## (speed, boost, hurt, ...) and, every 6th frame, everything it produces (the picture-pass uniforms, the bloom and haze, the dose and flow state, the camera kicks).
## Then forces five trip depths and takes screenshots of: normal, mid clarity drop (_clr_k 0.10), the snap back (_clr_k 1.3 with _sharp 1) and a sharp peak.
##   OUT=C:/.../psy_states.json SHOTS=C:/.../psy_states SEED=7 SECS=240 Godot --rendering-driver opengl3 --resolution 960x540 --path godot res://tests/dump_states.tscn
## The scripted events (time in seconds): molecules 0..5 eaten at 3, 12, 22, 32, 42, 52 and the first again at 70, flow and chain events at 4..9, a cheer at 15, a crash-like shake at 20, a sharpen at 75. The lab knob x_clear is 2 (clarity comes twice as soon).

var out := {"frames": [], "ctx": [], "ctx2": [], "events": [], "draws": {"clr": [], "sharp": [], "efc": [], "efcpeek": [], "god": [], "calm": []}, "shots": [], "levels": []}
var rig_ref: RunRig
var fxm_ref: ThemeFX
var env_ref: Environment


func r3(x: float) -> float:
	return snappedf(x, 0.0001)


func v3(v: Vector3) -> Array:
	return [r3(v.x), r3(v.y), r3(v.z)]


func prm(n: String) -> Variant:
	var v: Variant = fxm_ref.post.mat.get_shader_parameter(n)
	if v is Vector3:
		return v3(v)
	if v is float or v is int:
		return r3(float(v))
	return v


func sample(t: float) -> Dictionary:
	var rig := rig_ref
	var d := {"t": r3(t)}
	for n in ["mode", "amount", "breathe", "onset", "trip", "dmt", "buzz", "sharp", "tube", "smear", "rewind", "k_chroma", "k_trace", "k_punch", "k_warp", "k_fold", "k_pulse", "k_rings", "k_dmtr", "k_wash", "k_edge", "k_cel", "edge_hue", "use_trail", "mA", "mB"]:
		d[n] = prm(n)
	d["layer"] = fxm_ref.post.layer.visible if fxm_ref.post.layer != null else false
	d["pm_mode"] = int(fxm_ref.post.mode)
	d["pm_amount"] = r3(float(fxm_ref.post.amount))
	if env_ref != null:
		d["glow"] = r3(env_ref.glow_intensity)
		d["bloom"] = r3(env_ref.glow_bloom)
		d["fog"] = r3(env_ref.fog_density * 1000.0)
	d["glow_base"] = r3(rig._glow_base)
	d["bloom_base"] = r3(rig._bloom_base)
	d["fog_base"] = r3(rig._fog_base * 1000.0)
	d["mdose"] = Array(rig._mdose).map(func(x): return r3(x))
	d["mbody"] = Array(rig._mbody).map(func(x): return r3(x))
	d["mflash"] = Array(rig._mflash).map(func(x): return r3(x))
	d["dose"] = r3(rig._dose)
	d["body"] = r3(rig._body)
	d["clr_k"] = r3(rig._clr_k)
	d["clr_t"] = r3(rig._clr_t)
	d["sharp_v"] = r3(rig._sharp)
	d["stage_post"] = r3(rig.stage_post)
	d["hall"] = r3(rig._hall)
	d["pill_k"] = r3(rig._pill_k)
	d["trip_v"] = r3(rig.trip)
	d["chain"] = rig.chain
	d["groove"] = r3(rig.groove)
	d["chain_lvl"] = rig.chain_lvl
	d["chain_step"] = rig.chain_step
	d["chain_t"] = r3(rig._chain_t)
	d["flow_t"] = r3(rig._flow_t)
	d["mult_t"] = r3(rig._mult_t)
	d["score"] = rig.score
	d["shake"] = r3(rig._shake)
	d["fov_punch"] = r3(rig._fov_punch)
	d["flash"] = r3(rig._flash)
	d["mo"] = [r3(rig._mo_asp), r3(rig._mo_cell), r3(rig._mo_ratio), r3(rig._mo_depth), r3(rig._mo_sat), r3(rig._mo_tri), r3(rig._mo_rad), r3(rig._mo_warp)]
	d["efc_k"] = r3(rig._efc_k)
	d["god_k"] = r3(rig._god_k)
	d["sky_flash"] = r3(rig._sky_flash)
	if rig._journey != null:
		d["j"] = {"phase": rig._journey.phase, "t": r3(rig._journey.t), "wave": rig._journey.wave, "world": rig._journey.world, "strength": r3(rig._journey.strength), "calm_len": r3(rig._journey._calm_len), "onset_k": r3(rig._journey.onset_k())}
	d["perk"] = [r3(rig._bm_pad), r3(rig._spd_k), r3(rig.glint_k), r3(rig.jump_chance)]
	d["pacer_t"] = r3(rig._pacer.t) if rig._pacer != null else 0.0
	d["exc"] = r3(rig._exc)
	d["x_clear"] = r3(rig.fx("x_clear"))
	return d


func ctx_row() -> Array:
	var rig := rig_ref
	var wave := 0.5
	if rig._dir != null and is_instance_valid(rig._dir):
		wave = rig._dir.wave_at(0.0)
	return [r3(rig.vel.length()), r3(-rig.vel.y), rig.chain, 1 if rig._boost_t > 0.0 else 0, rig._links, r3(rig.spos.y - rig.terrain_h(rig.spos.x, rig.spos.z)), r3(rig.vy), 1 if rig._in_air else 0, r3(rig.hurt_t), 1 if not rig._rail.is_empty() else 0, 1 if (not rig._lk.is_empty() or not rig._lkp.is_empty()) else 0, r3(wave)]


var _prev := {"clr": 0.0, "sharp": 0.0, "efc": 0.0, "god": 0.0, "calm": 0.0, "efc_t": -1.0}


func track_draws() -> void:
	var rig := rig_ref
	var n := rig._clr_next
	if n >= 50.0 and _prev["clr"] <= 1.0:
		out["draws"]["clr"].append(r3(n))
	_prev["clr"] = n
	var s := rig._sharp_next
	if s >= 26.0 and s <= 48.0 and s > float(_prev["sharp"]) + 1.0:
		out["draws"]["sharp"].append(r3(s))
	_prev["sharp"] = s
	var e := rig._efc_next
	if e >= 70.0 and e <= 150.0 and float(_prev["efc"]) <= 1.0:
		out["draws"]["efc"].append(r3(e))
		out["draws"]["efcpeek"].append(1.0 if rig._efc_peek else 0.0)
	_prev["efc"] = e
	var g := rig._god_next
	if g >= 200.0 and g <= 360.0 and float(_prev["god"]) <= 1.0:
		out["draws"]["god"].append(r3(g))
	_prev["god"] = g
	if rig._journey != null:
		var cl := rig._journey._calm_len
		if absf(cl - float(_prev["calm"])) > 0.001:
			_prev["calm"] = cl
			var w: int = rig._journey.wave
			var a: Dictionary = DhJourney.ARC[w % DhJourney.ARC.size()]
			var lv := clampi(rig._cfg_trip, 0, 2)
			var lk := clampf(rig._pacer.session_s / 1200.0, 0.5, 1.5) if rig._pacer != null else 1.0
			out["draws"]["calm"].append([r3(w), r3(cl / (float(a["calm"]) * float(DhJourney.LV_CALM[lv]) * lk))])


func eat(mi: int) -> void:
	var n := Node3D.new()
	var d := {"t": 0, "n": n, "id": String(MolData.ORDER[mi]), "name": String(MolData.MOLS[MolData.ORDER[mi]]["name"]), "col": MolData.MOLS[MolData.ORDER[mi]]["c"], "x": rig_ref.spos.x, "y": rig_ref.spos.y, "z": rig_ref.spos.z}
	rig_ref._pill_eat(d)
	out["events"].append({"t": r3(rig_ref._age), "e": "eat", "mi": mi})


func step(dt: float) -> void:
	var rig := rig_ref
	rig.spos = Vector3(0.0, 0.0, -200.0)
	rig.spos.y = rig.terrain_h(rig.spos.x, rig.spos.z)
	rig.grounded = true
	rig._gh_prev = rig.spos.y
	rig.vel = Vector2(0.0, -24.0)
	rig.hurt_t = 0.0
	out["ctx"].append(ctx_row())
	rig._physics_process(dt)
	out["ctx2"].append(ctx_row())          # what _process (the trip tick, the excitement) sees: after the physics step
	rig._process(dt)
	track_draws()


## The slow world effects (clarity among them) only run on even engine frames when the frame rate is under 45; stepping by hand does not advance that counter, so wait for an even one.
func even_frame() -> void:
	var guard := 0
	while (Engine.get_process_frames() & 1) != 0 and Engine.get_frames_per_second() < 45.0 and guard < 4:
		guard += 1
		await get_tree().process_frame


func shot(name: String, lvl: int, state: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("SHOTS") + "/s_L%d_%s.png" % [lvl, state]
	img.save_png(path)
	var d := sample(0.0)
	d["lvl"] = lvl
	d["state"] = state
	d["png"] = "s_L%d_%s.png" % [lvl, state]
	out["shots"].append(d)


func _ready() -> void:
	Prog.save_enabled = false
	Prog.reset()
	var level: MainLevel = load("res://scenes/MainLevel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	await get_tree().process_frame
	await get_tree().process_frame
	level.director.autostart = false
	Game.touch_mode = false
	level.load_level(11)
	for i in 5:
		await get_tree().physics_frame
	var rig: RunRig = level._dh as RunRig
	rig.set_physics_process(false)
	rig.set_process(false)
	rig.trail = true
	var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	rig.apply_menu({"journey": true, "seed": seed_v, "theme": "alpine", "mus": "off", "session": 10, "trip": 1, "intensity": 0.8}, level)
	await get_tree().process_frame
	rig_ref = rig
	rig.ghost = true
	fxm_ref = level.get_node_or_null("ThemeFX") as ThemeFX
	env_ref = level.world_env.environment if level.world_env != null else null
	GazeProvider.set_scripted(Vector2(0.5, 0.45))
	_prev["clr"] = rig._clr_next
	_prev["sharp"] = rig._sharp_next
	_prev["efc"] = rig._efc_next
	_prev["god"] = rig._god_next
	var dt := 1.0 / 60.0
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 240.0
	var frames := int(secs * 60.0)
	var plan := {3.0: 0, 12.0: 1, 22.0: 2, 32.0: 3, 42.0: 4, 52.0: 5, 70.0: 0}
	var t := 0.0
	for f in frames:
		t = float(f) * dt
		for et in plan:
			if absf(t - float(et)) < dt * 0.5:
				eat(int(plan[et]))
		if absf(t - 4.0) < dt * 0.5:
			rig._flow_up(1)
			out["events"].append({"t": r3(rig._age), "e": "flow_up", "n": 1})
		if absf(t - 6.0) < dt * 0.5:
			rig._flow_up(2)
			out["events"].append({"t": r3(rig._age), "e": "flow_up", "n": 2})
		if absf(t - 8.0) < dt * 0.5:
			rig._chain_hit("mult")
			out["events"].append({"t": r3(rig._age), "e": "chain_hit", "k": "mult"})
		if absf(t - 9.0) < dt * 0.5:
			rig._chain_hit("boost")
			out["events"].append({"t": r3(rig._age), "e": "chain_hit", "k": "boost"})
		if absf(t - 15.0) < dt * 0.5:
			rig._cheer("TEST", Color.WHITE, 1.5)
			out["events"].append({"t": r3(rig._age), "e": "cheer", "size": 1.5})
		if absf(t - 20.0) < dt * 0.5:
			rig._shake = 0.9
			out["events"].append({"t": r3(rig._age), "e": "shake", "v": 0.9})
		if absf(t - 75.0) < dt * 0.5:
			rig._sharpen(1.0)
			out["events"].append({"t": r3(rig._age), "e": "sharpen", "k": 1.0})
		step(dt)
		if f == 20:
			rig._fx_val["x_clear"] = 2.0          # (set once the lab has started: its own start resets the knobs to their defaults)
			rig._fx_apply()
			print("x_clear is now ", rig.fx("x_clear"))
		if f % 6 == 0:
			out["frames"].append(sample(t))
	# ---- the picture at five depths (felt level of all six molecules), in four states each
	var levels := [0.0, 0.15, 0.35, 0.6, 1.0]
	for li in levels.size():
		var lv: float = levels[li]
		for i in 6:
			rig._mdose[i] = lv * 6.0
			rig._mbody[i] = lv * 6.0
		rig._clr_t = -1.0
		rig._clr_k = 1.0
		rig._sharp = 0.0
		rig._clr_next = 9999.0
		rig._sharp_next = 9999.0
		await even_frame()
		for k in 90:
			step(dt)
		await shot("normal", li, "normal")
		await even_frame()
		rig._clr_t = 1.0                    # the hold of a moment of clarity: everything down to 10%
		for k in 4:
			step(dt)
		await shot("drop", li, "drop")
		await even_frame()
		rig._clr_t = 2.4                    # the snap back: 130% and a sharpening
		rig._sharpen(1.0)
		for k in 2:
			step(dt)
		await shot("snap", li, "snap")
		await even_frame()
		rig._clr_t = -1.0
		rig._clr_k = 1.0
		rig._sharpen(1.0)                   # a sharp peak with no clarity moment
		for k in 2:
			step(dt)
		await shot("sharp", li, "sharp")
		out["levels"].append({"lvl": lv})
	var f2 := FileAccess.open(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://psy_states.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(out))
	f2.close()
	print("STATES frames=", out["frames"].size(), " shots=", out["shots"].size(), " draws=", JSON.stringify(out["draws"]))
	get_tree().quit()
