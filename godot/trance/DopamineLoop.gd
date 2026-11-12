class_name DopamineLoop
extends Node
## The anticipation loop.
##
##   LOOK   at an interactive orb. Once your gaze has dwelt on it for more than DWELL_START seconds it starts CHARGING.
##   BUILD  while charging, the world changes with the charge: the audio bus pitches down and loses its highs (low-pass),
##          the post shader pulls the colour channels apart, the camera effects swell.
##   BLINK  while charging, the blink (the eyes re-opening) RELEASES it: a physics shockwave throws the debris, the score
##          jumps by charge x multiplier, the multiplier climbs, the audio and picture snap back.
##
## Looking away for longer than GRACE seconds cancels the charge. A short grace keeps the charge alive across the blink
## itself, which briefly makes the gaze jump.

signal charging_started(orb: Node3D)
signal discharged(orb: Node3D, charge: float)

const DWELL_START := 0.5
const CHARGE_TIME := 3.0
const GRACE := 0.4
const MULT_RESET_AFTER := 7.0
const BUS_NAME := &"Trance"
## Screen-space effects ported from the psychedelic WebXR demos. Weights are (flow, kaleidoscope, tunnel, god rays, phosphene).
const FX_NAMES := ["CLASSIC", "FLOW", "KALEIDOSCOPE", "TUNNEL", "GOD RAYS", "PHOSPHENE", "EVERYTHING"]
const FX_WEIGHTS := [
	[0.0, 0.0, 0.0, 0.0, 0.0],
	[1.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 1.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 1.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 1.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 1.0],
	[0.7, 0.55, 0.45, 1.0, 0.6],
]

var cam: AlteredStateCamera
var orbs: Array[Node3D] = []
var post_mat: ShaderMaterial
var rig: Node3D

## 0..1. The player's comfort setting. Scales every effect (0 = effects off, the game still plays).
var intensity: float = 0.4

## Held true while the eye setup runs.
var paused: bool = false
## Which effect set the charge drives (index into FX_NAMES).
var fx_mode: int = 6
var target: Node3D = null
var dwell: float = 0.0
var charge: float = 0.0
var charging: bool = false
var score: int = 0
var multiplier: float = 1.0
var discharges: int = 0
var last_radius: float = 0.0

var _lost: float = 0.0
var _since_discharge: float = 0.0
var _lp: AudioEffectLowPassFilter
var _pitch: AudioEffectPitchShift
var _bus_idx: int = -1
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_cam: AlteredStateCamera, p_orbs: Array[Node3D], p_post: ShaderMaterial, p_rig: Node3D) -> void:
	cam = p_cam
	orbs = p_orbs
	post_mat = p_post
	rig = p_rig
	_rng.randomize()
	_make_bus()
	_apply_fx(0.0)


func _make_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx == -1:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_send(_bus_idx, &"Master")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(_bus_idx, _lp)
		_pitch = AudioEffectPitchShift.new()
		_pitch.fft_size = AudioEffectPitchShift.FFT_SIZE_1024
		_pitch.pitch_scale = 1.0
		AudioServer.add_bus_effect(_bus_idx, _pitch)
	else:
		_lp = AudioServer.get_bus_effect(_bus_idx, 0) as AudioEffectLowPassFilter
		_pitch = AudioServer.get_bus_effect(_bus_idx, 1) as AudioEffectPitchShift


func _exit_tree() -> void:
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx != -1:
		AudioServer.remove_bus(idx)
	if post_mat != null:
		post_mat.set_shader_parameter("aberration", 0.0)


## Pure: the charge (0..1) for a dwell time. Nothing until DWELL_START, then a smooth rise over CHARGE_TIME.
static func charge_for_dwell(dwell_s: float) -> float:
	if dwell_s <= DWELL_START:
		return 0.0
	var x := clampf((dwell_s - DWELL_START) / CHARGE_TIME, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## The orb under the gaze point (screen space), or null. Generous: orbs are big targets, and webcam gaze is rough.
func orb_under_gaze(gaze_px: Vector2, vs: Vector2) -> Node3D:
	var best: Node3D = null
	var best_ratio := 1.0
	for o in orbs:
		if not o.visible:
			continue
		var p := o.global_position
		if cam.is_position_behind(p):
			continue
		var c := cam.unproject_position(p)
		var r := absf(cam.unproject_position(p + cam.global_transform.basis.x * 0.9).x - c.x)
		var tol := r + maxf(0.08, 2.5 * TrackerBridge.camera_sigma) * vs.y
		var ratio := gaze_px.distance_to(c) / tol
		if ratio < best_ratio:
			best_ratio = ratio
			best = o
	return best


func _process(delta: float) -> void:
	_t += delta
	if paused:
		dwell = 0.0
		charge = 0.0
		charging = false
		target = null
		_apply_fx(0.0)
		return
	var vs := get_viewport().get_visible_rect().size
	var under := orb_under_gaze(TrackerBridge.gaze * vs, vs)
	if under != null and under == target:
		dwell += delta
		_lost = 0.0
	elif under != null:
		target = under
		dwell = delta
		_lost = 0.0
	else:
		_lost += delta
		if _lost > GRACE:
			dwell = maxf(dwell - 3.0 * delta, 0.0)
			if dwell <= 0.0:
				target = null

	var was := charging
	charging = dwell > DWELL_START and target != null
	if charging and not was:
		charging_started.emit(target)
	var goal := DopamineLoop.charge_for_dwell(dwell) if charging else 0.0
	charge = move_toward(charge, goal, (2.0 if goal > charge else 3.0) * delta)

	if charging and TrackerBridge.just_blinked:
		discharge()
	_since_discharge += delta
	if _since_discharge > MULT_RESET_AFTER:
		multiplier = 1.0
	_apply_fx(charge)
	_animate_orbs()


## Blink release: the shockwave and the payout. Also callable directly (tests, UI).
func discharge() -> void:
	if target == null:
		return
	var orb := target
	var c := maxf(charge, 0.05)
	# a blink while staring at an orb is a known fact about where the eyes are: pin the automatic offset to it
	if TrackerBridge.source == "camera" and cam != null and not cam.is_position_behind(orb.global_position):
		var vs0 := get_viewport().get_visible_rect().size
		GazeProvider.eye_anchor(cam.unproject_position(orb.global_position) / vs0, 0.12)
	var radius := 5.0 + 9.0 * c
	last_radius = radius
	var origin := orb.global_position
	var rb_count := 0
	for n in get_tree().get_nodes_in_group("trance_debris"):
		var rb := n as RigidBody3D
		if rb == null:
			continue
		var off := rb.global_position - origin
		var d := off.length()
		if d > radius:
			continue
		var fall := 1.0 - d / radius
		var dir := (off.normalized() + Vector3.UP * 0.7).normalized()
		rb.apply_central_impulse(dir * (6.0 + 30.0 * c) * fall * rb.mass)
		rb.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 2.0 * c * rb.mass)
		rb_count += 1
	var pts := int(round((20.0 + 180.0 * c) * multiplier))
	score += pts
	multiplier = minf(multiplier + 0.5, 5.0)
	discharges += 1
	_since_discharge = 0.0
	cam.punch(0.4 + 0.8 * c)
	_burst(origin, c)
	_respawn(orb)
	# snap the world back, with a brief overshoot (the "release")
	_release_until = _t + 0.7
	var tw := create_tween()
	if _pitch != null:
		tw.tween_property(_pitch, "pitch_scale", 1.3, 0.05)
		tw.tween_property(_pitch, "pitch_scale", 1.0, 0.6)
	discharged.emit(orb, c)
	dwell = 0.0
	charge = 0.0
	charging = false
	target = null
	if rig != null and rig.has_method("on_discharge"):
		rig.call("on_discharge", pts, rb_count, c)


func _burst(pos: Vector3, c: float) -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.4)
	p.material_override = m
	p.amount = int(40 + 60 * c)
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0 + 8.0 * c
	p.gravity = Vector3(0, -6, 0)
	if rig != null:
		rig.add_child(p)
	else:
		add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _respawn(orb: Node3D) -> void:
	var vs := get_viewport().get_visible_rect().size
	var p := cam.project_position(Vector2(_rng.randf_range(0.14, 0.86) * vs.x, _rng.randf_range(0.28, 0.56) * vs.y), _rng.randf_range(10.0, 13.0))
	p.y = maxf(p.y, 2.8)
	var home := p
	orb.set_meta("home", home)
	orb.position = home
	orb.scale = Vector3.ONE * 0.1
	var tw := create_tween()
	tw.tween_property(orb, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Everything the charge changes in the world, scaled by the player's comfort `intensity`.
func _apply_fx(c: float) -> void:
	var k := clampf(intensity, 0.0, 1.0)
	if _lp != null:
		_lp.cutoff_hz = lerpf(20000.0, 700.0, c * k)
	if _pitch != null and _t >= _release_until:
		_pitch.pitch_scale = lerpf(1.0, 0.78, c * k)
	if post_mat != null:
		post_mat.set_shader_parameter("aberration", c * 1.6)
		var w: Array = FX_WEIGHTS[clampi(fx_mode, 0, FX_WEIGHTS.size() - 1)]
		var amb := 0.1 if fx_mode != 0 else 0.0                 # a little of the effect is always there; the charge brings the rest
		post_mat.set_shader_parameter("flow", clampf(float(w[0]) * (amb + c), 0.0, 1.0))
		post_mat.set_shader_parameter("kaleido", clampf(float(w[1]) * c, 0.0, 1.0))
		post_mat.set_shader_parameter("tunnel", clampf(float(w[2]) * c, 0.0, 1.0))
		post_mat.set_shader_parameter("rays", clampf(float(w[3]) * (0.25 * (1.0 if target != null else 0.0) + c), 0.0, 1.0))
		post_mat.set_shader_parameter("phos", clampf(float(w[4]) * c, 0.0, 1.0))
		if target != null and cam != null and not cam.is_position_behind(target.global_position):
			var vs := get_viewport().get_visible_rect().size
			post_mat.set_shader_parameter("rays_pos", cam.unproject_position(target.global_position) / vs)
		post_mat.set_shader_parameter("intensity", k)
		post_mat.set_shader_parameter("vignette", c)
	if cam != null:
		cam.intensity = clampf(k * (1.0 + 0.8 * c), 0.0, 1.0)


var _release_until: float = 0.0


func _animate_orbs() -> void:
	for o in orbs:
		var base := 1.0
		var mi := o.get_child(0) as MeshInstance3D
		var is_t := o == target
		var glow := 0.8 + (3.0 * charge if is_t else 0.0)
		if mi != null and mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).emission_energy_multiplier = glow + 0.3 * sin(_t * 2.0 + float(o.get_instance_id() % 7))
		if is_t and charging and o.scale.x > 0.9:
			base = 1.0 + 0.18 * charge * sin(_t * 18.0)
			o.scale = Vector3.ONE * base
		if o.has_meta("home") and o.scale.x > 0.9:
			var h: Vector3 = o.get_meta("home")
			o.position.y = h.y + 0.25 * sin(_t * 0.9 + h.x)
