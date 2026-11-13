class_name DhLighting
extends Node
## Everything that makes the light move in Downhill:
##  - a day that passes as you ride (dawn pink, bright blue morning, golden hour, blue dusk with moonlight), driven by distance, alpine look only;
##  - falling snow around the camera (alpine);
##  - a light on the rider that warms to orange on a boost, cools to cyan under a shield and flares on a hit or a landing;
##  - a few lights pooled on the next barrier's openings, coloured by what lies behind each one, so the gates glow on the snow before you reach them.
## Cheap by design (a handful of omni lights, no real-time shadows, a few hundred particles): it has to run on a phone.

var level: MainLevel
var rig: RunRig
var theme_id: String = "alpine"
var dynamic: bool = true
var snowfall: bool = true
var day_len: float = 3200.0               # metres for a whole day
var phase: float = 0.0

var _snow: CPUParticles3D
var _rider: OmniLight3D
var _gate_lights: Array[OmniLight3D] = []
var _flare: float = 0.0
# ---- the speed governor. The camera and the controls come first: if either the tracker or the game falls behind, the pretty things are switched off in this order
#   tier 0 everything   1 snow, gate lights and the trails pass off   2 glow off and the 3D picture rendered smaller   3 smaller still and no full-screen pass at all
var tier: int = 0
var floor_tier: int = 0                 # phones start at 1: a cartoon on a small screen is forgiving, losing control is not
var tier_changes: int = 0
var _chk: float = 0.0
var _applied: bool = false
var _bad: float = 0.0
var _good: float = 0.0
var _cool: float = 0.0
const GAME_FPS_MIN := 40.0
const TRACKER_FPS_MIN := 10.5
var _hurt_prev: float = 0.0
var _grounded_prev: bool = true

# dawn, morning, golden hour, blue dusk, and back to dawn. elev = how high the sun (or moon) stands, in degrees
const KEYS := [
	{"top": Color(0.33, 0.40, 0.80), "hor": Color(1.00, 0.70, 0.82), "fog": Color(0.86, 0.66, 0.84), "sun": Color(1.00, 0.72, 0.62), "elev": 9.0, "amb": 0.75, "glow": 0.9},
	{"top": Color(0.28, 0.52, 0.95), "hor": Color(0.86, 0.93, 1.00), "fog": Color(0.80, 0.88, 1.00), "sun": Color(1.00, 0.96, 0.88), "elev": 38.0, "amb": 1.0, "glow": 0.5},
	{"top": Color(0.30, 0.34, 0.74), "hor": Color(1.00, 0.62, 0.36), "fog": Color(0.96, 0.72, 0.58), "sun": Color(1.00, 0.64, 0.34), "elev": 12.0, "amb": 0.85, "glow": 1.0},
	{"top": Color(0.05, 0.07, 0.26), "hor": Color(0.30, 0.32, 0.68), "fog": Color(0.20, 0.22, 0.48), "sun": Color(0.50, 0.60, 1.00), "elev": 26.0, "amb": 0.55, "glow": 1.1},
]


func setup(p_level: MainLevel, p_rig: RunRig, id: String, dyn: bool, snow: bool) -> void:
	level = p_level
	rig = p_rig
	theme_id = id
	dynamic = dyn
	snowfall = snow
	if _rider == null:
		_rider = OmniLight3D.new()
		_rider.omni_range = 16.0
		_rider.light_energy = 0.0
		_rider.shadow_enabled = false
		rig.add_child(_rider)
		for i in 3:
			var l := OmniLight3D.new()
			l.omni_range = 26.0
			l.light_energy = 0.0
			l.shadow_enabled = false
			rig.add_child(l)
			_gate_lights.append(l)
	floor_tier = 1 if Game.touch_mode else 0
	tier = clampi(maxi(floor_tier, 1 if OS.has_feature("web") else 0), 0, 3)          # a web build starts one step down and climbs only if it can hold the frame rate
	_applied = false
	if _snow != null:
		_snow.queue_free()
		_snow = null
	if snowfall and (id == "alpine"):
		_snow = CPUParticles3D.new()
		_snow.amount = 600
		_snow.lifetime = 5.0
		_snow.preprocess = 5.0
		_snow.local_coords = false
		_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_snow.emission_box_extents = Vector3(38.0, 15.0, 38.0)
		_snow.direction = Vector3(0.2, -1.0, 0.1)
		_snow.spread = 14.0
		_snow.gravity = Vector3(0.0, -2.2, 0.0)
		_snow.initial_velocity_min = 0.8
		_snow.initial_velocity_max = 2.6
		_snow.scale_amount_min = 0.6
		_snow.scale_amount_max = 1.5
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.14)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.85)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		q.material = m
		_snow.mesh = q
		_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(_snow)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## The sky, fog and sun for a point in the day (0..1, wrapping).
func sample_day(ph: float) -> Dictionary:
	var n := KEYS.size()
	var x := fposmod(ph, 1.0) * float(n)
	var i := int(floor(x)) % n
	var j := (i + 1) % n
	var t := _ease(x - floor(x))
	var a: Dictionary = KEYS[i]
	var b: Dictionary = KEYS[j]
	return {
		"top": (a["top"] as Color).lerp(b["top"], t), "hor": (a["hor"] as Color).lerp(b["hor"], t), "fog": (a["fog"] as Color).lerp(b["fog"], t),
		"sun": (a["sun"] as Color).lerp(b["sun"], t), "elev": lerpf(float(a["elev"]), float(b["elev"]), t), "amb": lerpf(float(a["amb"]), float(b["amb"]), t),
		"glow": lerpf(float(a["glow"]), float(b["glow"]), t),
	}


func _process(delta: float) -> void:
	if level == null or rig == null or not is_instance_valid(rig) or get_tree().paused:
		return
	if not _applied:
		_applied = true
		_apply_tier()                                   # a phone starts at its floor tier: apply it, do not wait for the first change
	_governor(delta)
	var lit := theme_id == "alpine"                 # the other looks are unshaded: lights would cost frame rate and change nothing
	_rider.visible = lit and tier < 3
	for gl in _gate_lights:
		gl.visible = lit and tier < 1
	if dynamic and theme_id == "alpine":
		_apply_day()
	if _snow != null:
		_snow.global_position = rig.cam.global_position + Vector3(0.0, 4.0, -12.0)
	_update_rider(delta)
	_update_gate_lights(delta)


## Decide the tier from the two frame rates (the tracker's matters more: a slow game is a worse picture, a slow tracker is lost control).
func step_governor(dt: float, game_fps: float, trk_fps: float, cam_on: bool) -> void:
	_cool = maxf(_cool - dt, 0.0)
	var pressure := game_fps < GAME_FPS_MIN or (cam_on and trk_fps < TRACKER_FPS_MIN)
	if pressure:
		_good = 0.0
		_bad += dt
		var need := 2.0 if (cam_on and trk_fps < TRACKER_FPS_MIN) else 4.0          # a starving tracker is answered twice as fast
		if _bad >= need and tier < 3 and _cool <= 0.0:
			tier += 1
			tier_changes += 1
			_bad = 0.0
			_cool = 6.0
	else:
		_bad = maxf(_bad - dt, 0.0)
		_good += dt
		if _good >= 16.0 and tier > floor_tier and game_fps >= 55.0 and (not cam_on or trk_fps >= 13.0):
			tier -= 1
			tier_changes += 1
			_good = 0.0
			_cool = 6.0


func _governor(delta: float) -> void:
	if rig.perf_pin >= 0:
		if tier != rig.perf_pin:
			tier = rig.perf_pin
			_apply_tier()
		return
	_chk += delta
	if _chk < 2.0:
		return
	var dt := _chk
	_chk = 0.0
	var before := tier
	var cam_on := GazeProvider.backend == GazeProvider.Backend.CAMERA
	step_governor(dt, float(Engine.get_frames_per_second()), float(GazeProvider._pkt_times.size()) / 2.0, cam_on)
	if tier != before:
		_apply_tier()


func _apply_tier() -> void:
	if _snow != null:
		_snow.emitting = tier == 0
		_snow.visible = tier == 0
	var fx: ThemeFX = level.get_node_or_null("ThemeFX") as ThemeFX
	if fx != null and fx.post != null:
		fx.post.trails_ok = tier < 1
		fx.post.set_look(Themes.post_mode(theme_id) if tier < 3 else 0, fx.post.amount)
	var env: Environment = level.world_env.environment
	if tier >= 2:
		env.glow_enabled = false
	env.adjustment_enabled = tier < 1                 # colour grading is a whole extra pass over the picture: the first thing a phone gives up
	var vp := rig.get_viewport()
	if vp != null:
		# a big desktop window has several times the pixels of a phone: draw the 3D picture at about a million pixels at most (the HUD stays sharp)
		var px := maxf(float(vp.get_visible_rect().size.x * vp.get_visible_rect().size.y), 1.0)
		var cap := clampf(sqrt(1.15e6 / px), 0.5, 1.0) if OS.has_feature("web") else 1.0
		vp.scaling_3d_scale = minf([1.0, 1.0, 0.8, 0.65][tier], cap)
	# draw distance for trees and rocks: the cheapest big saving there is
	rig.veg_range = [0.0, 280.0, 190.0, 130.0][tier]
	for n in rig.get_children():
		if n is MultiMeshInstance3D:
			(n as MultiMeshInstance3D).visibility_range_end = rig.veg_range


func _apply_day() -> void:
	phase = fposmod(-rig.spos.z / day_len, 1.0)
	var d := sample_day(phase)
	var env: Environment = level.world_env.environment
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	if sm == null:
		return
	sm.sky_top_color = d["top"]
	sm.sky_horizon_color = d["hor"]
	sm.ground_horizon_color = d["hor"]
	sm.ground_bottom_color = (d["fog"] as Color).darkened(0.35)
	env.fog_light_color = d["fog"]
	env.ambient_light_energy = float(d["amb"])
	env.glow_intensity = float(d["glow"])
	level.sun.light_color = d["sun"]
	level.sun.rotation_degrees = Vector3(-float(d["elev"]), -35.0, 0.0)


func _update_rider(delta: float) -> void:
	var hurt := rig.hurt_t
	if hurt > _hurt_prev + 0.01:
		_flare = 1.0
	if rig.grounded and not _grounded_prev:
		_flare = maxf(_flare, 0.6)
	_hurt_prev = hurt
	_grounded_prev = rig.grounded
	_flare = maxf(_flare - 2.2 * delta, 0.0)
	var col := Color(1.0, 0.92, 0.8)
	var e := 0.35
	if rig._boost_t > 0.0:
		col = Color(1.0, 0.55, 0.15)
		e = 2.0
	elif rig.shield > 0:
		col = Color(0.4, 0.85, 1.0)
		e = 1.3
	if _flare > 0.0:
		col = col.lerp(Color(1.0, 0.3, 0.25) if hurt > 0.0 else Color(1, 1, 1), 0.7)
		e += 2.5 * _flare
	_rider.light_color = col
	_rider.light_energy = lerpf(_rider.light_energy, e, 1.0 - exp(-10.0 * delta))
	pass
	_rider.global_position = rig.spos + Vector3(0.0, 2.6, -2.5)


func _update_gate_lights(delta: float) -> void:
	var row: Dictionary = {}
	var bz := -1.0e9
	for j in rig._rows:
		var r: Dictionary = rig._rows[j]
		if r["has_row"] and float(r["z"]) < rig.spos.z - 6.0 and float(r["z"]) > bz and float(r["z"]) > rig.spos.z - 260.0:
			bz = float(r["z"])
			row = r
	var gaps: Array = [] if row.is_empty() else (row["gaps"] as Array)
	for i in _gate_lights.size():
		var l := _gate_lights[i]
		if i < gaps.size() and tier < 1:
			var g: Dictionary = gaps[i]
			var zc: Color = RunRig.ZONES[String(g.get("leads", "rush"))]["col"]
			var gx := float(g["x"])
			l.light_color = zc
			var near := clampf(1.0 - (rig.spos.z - bz) / 240.0, 0.0, 1.0)
			l.light_energy = lerpf(l.light_energy, 0.4 + 2.2 * near, 1.0 - exp(-6.0 * delta))
			l.global_position = Vector3(gx, rig.terrain_h(gx, bz) + 4.0, bz + 4.0)
		else:
			l.light_energy = lerpf(l.light_energy, 0.0, 1.0 - exp(-6.0 * delta))
