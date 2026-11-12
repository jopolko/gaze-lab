class_name TranceRig
extends Node3D
## OCULAR TRANCE: builds the arena (glowing orbs over piles of physics blocks), the altered-state camera, the post
## shader, a drone for the audio bus to bend, and the HUD. DopamineLoop runs the gameplay.
##
## Comfort: intensity starts moderate. - / = change it, C (or tapping the bar) sets it. 0 = calm: the game plays
## the same with no camera sway, no colour split and no pitch bend.

const ORB_COUNT := 6
const PILE := 10

var player: PlayerController
var cam: AlteredStateCamera
var loop: DopamineLoop
var orbs: Array[Node3D] = []
var debris: Array[RigidBody3D] = []

var _hud: Control
var _post_mat: ShaderMaterial
var _age: float = 0.0
var _drone: AudioStreamPlayer
var _drone_playback: AudioStreamGeneratorPlayback
var _drone_t: float = 0.0
var _toast: String = ""
var _toast_t: float = 0.0
var _bar: Rect2 = Rect2()
var _fx_rect: Rect2 = Rect2()
var _layers: Array[Node] = []


func setup(p_player: PlayerController) -> void:
	name = "TranceRig"
	player = p_player
	cam = AlteredStateCamera.new()
	cam.fov = 72.0
	cam.near = 0.1
	cam.far = 200.0
	cam.position = Vector3(0.0, 1.9, 8.5)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	add_child(cam)
	cam.make_current()
	_frame_camera()
	cam.set_base(cam.transform)
	_build_arena()

	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	_layers.append(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://trance/NystagmusPostProcess.gdshader")
	rect.material = _post_mat
	post_layer.add_child(rect)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 6
	add_child(hud_layer)
	_layers.append(hud_layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(_hud)
	_hud.draw.connect(_draw_hud)

	loop = DopamineLoop.new()
	add_child(loop)
	loop.setup(cam, orbs, _post_mat, self)
	GazeProvider.bias.reset()
	GazeProvider.bias.exp_span = Vector2(0.62, 0.28)    # orbs span the width, a narrower band of the height
	_start_drone()


const ORB_SY := [0.34, 0.50, 0.30, 0.46, 0.38, 0.52]


## A point in the world that lands inside the visible screen: orbs are placed by projecting screen positions, so no
## orb is ever off-screen (you cannot look off-screen and still play). Kept in the middle 72% across, 25-58% down.
func screen_home(i: int, rng: RandomNumberGenerator) -> Vector3:
	var vs := get_viewport().get_visible_rect().size
	var sx := lerpf(0.14, 0.86, float(i) / float(ORB_COUNT - 1))
	var sy: float = ORB_SY[i % ORB_SY.size()] + rng.randf_range(-0.03, 0.03)
	var p := cam.project_position(Vector2(sx * vs.x, sy * vs.y), rng.randf_range(10.0, 13.0))
	p.y = maxf(p.y, 2.8)
	return p


func _frame_camera() -> void:
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x * 1.05
	cam.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	cam.fov = 100.0 if portrait else 72.0          # portrait: keep the whole spread of orbs in view


func _build_arena() -> void:
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(80.0, 1.0, 80.0)
	fcs.shape = fbox
	fcs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(80.0, 1.0, 80.0)
	fm.mesh = fmesh
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.1, 0.07, 0.16)
	fmat.roughness = 0.35
	fmat.metallic_specular = 0.6
	fm.material_override = fmat
	fm.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(fm)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(0.8, 0.8, 0.8)
	for i in ORB_COUNT:
		var home := screen_home(i, rng)
		var orb := Node3D.new()
		add_child(orb)
		orb.position = home
		orb.set_meta("home", home)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		sm.radial_segments = 20
		sm.rings = 10
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		var hue := fmod(0.55 + float(i) * 0.13, 1.0)
		m.albedo_color = Color.from_hsv(hue, 0.5, 0.9)
		m.emission_enabled = true
		m.emission = Color.from_hsv(hue, 0.8, 1.0)
		m.emission_energy_multiplier = 1.0
		mi.material_override = m
		orb.add_child(mi)
		orbs.append(orb)
		# a pile of blocks under each orb, for the shockwave to throw
		var gx := home.x
		var gz := home.z
		var n := 0
		for layer in 3:
			for bx in (3 - layer):
				if n >= PILE:
					break
				var rb := RigidBody3D.new()
				rb.mass = 1.0
				rb.add_to_group("trance_debris")
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.8, 0.8, 0.8)
				cs.shape = bs
				rb.add_child(cs)
				var cm := MeshInstance3D.new()
				cm.mesh = cube_mesh
				var cmat := StandardMaterial3D.new()
				cmat.albedo_color = Color.from_hsv(fmod(hue + rng.randf_range(-0.06, 0.06), 1.0), 0.55, 0.55)
				cmat.emission_enabled = true
				cmat.emission = Color.from_hsv(hue, 0.7, 0.4)
				cm.material_override = cmat
				rb.add_child(cm)
				add_child(rb)
				rb.position = Vector3(gx + (float(bx) - float(2 - layer) * 0.5) * 0.9, 0.42 + 0.85 * float(layer), gz)
				debris.append(rb)
				n += 1


# --------------------------------------------------------------------------
# A drone for the audio bus to bend (generated, nothing to download)
# --------------------------------------------------------------------------
func _start_drone() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_drone = AudioStreamPlayer.new()
	_drone.stream = gen
	_drone.bus = DopamineLoop.BUS_NAME
	_drone.volume_db = -14.0
	add_child(_drone)
	_drone.play()
	_drone_playback = _drone.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_drone() -> void:
	if _drone_playback == null:
		return
	var frames := _drone_playback.get_frames_available()
	var dt := 1.0 / 22050.0
	for i in frames:
		_drone_t += dt
		var wob := 1.0 + 0.004 * sin(_drone_t * 0.7)
		var s := 0.5 * sin(TAU * 98.0 * wob * _drone_t) + 0.3 * sin(TAU * 147.0 * _drone_t + sin(_drone_t * 0.4) * 2.0) + 0.15 * sin(TAU * 196.5 * _drone_t)
		_drone_playback.push_frame(Vector2(s, s) * 0.6)


# --------------------------------------------------------------------------
# Frame loop, comfort controls, HUD
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	_age += delta
	_toast_t = maxf(_toast_t - delta, 0.0)
	_fill_drone()
	_post_mat.set_shader_parameter("nystagmus", cam.nystagmus_uv)
	_post_mat.set_shader_parameter("time_s", _age)
	var vs0 := get_viewport().get_visible_rect().size
	_post_mat.set_shader_parameter("aspect", vs0.x / maxf(vs0.y, 1.0))
	_frame_camera()
	_hud.size = get_viewport().get_visible_rect().size
	_hud.queue_redraw()


func set_intensity(v: float) -> void:
	loop.intensity = clampf(snappedf(v, 0.05), 0.0, 1.0)


func on_discharge(pts: int, thrown: int, c: float) -> void:
	_toast = "+%d   x%.1f   (%d thrown)" % [pts, loop.multiplier, thrown]
	_toast_t = 1.6


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_intensity(loop.intensity - 0.1)
			KEY_EQUAL, KEY_KP_ADD:
				set_intensity(loop.intensity + 0.1)
			KEY_C, KEY_ESCAPE:
				set_intensity(0.0)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				loop.fx_mode = int((event as InputEventKey).keycode) - int(KEY_1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		if _fx_rect.has_point(p):
			loop.fx_mode = (loop.fx_mode + 1) % DopamineLoop.FX_NAMES.size()
			get_viewport().set_input_as_handled()
		elif _bar.grow(14.0).has_point(p):
			set_intensity((p.x - _bar.position.x) / _bar.size.x)
			get_viewport().set_input_as_handled()


func _hud_scale() -> float:
	return 2.0 if _hud.size.y > _hud.size.x * 1.05 else (1.25 if Game.touch_mode else 1.0)


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	var fs := int(float(size) * _hud_scale())
	_hud.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var s := _hud.size
	var k := _hud_scale()
	var m := 24.0 * k
	# score + multiplier
	_text(font, Vector2(m, m + 24.0 * k), "%d" % loop.score, 36, Color.WHITE)
	_text(font, Vector2(m, m + 56.0 * k), "x%.1f" % loop.multiplier, 24, Color(1.0, 0.85, 0.3))
	# which trippy effect the charge drives (keys 1-7, or tap)
	var fxl := "EFFECT: %s   (1-7 / tap)" % String(DopamineLoop.FX_NAMES[loop.fx_mode])
	var fxw := font.get_string_size(fxl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * k)).x
	_fx_rect = Rect2(m - 8.0 * k, m + 70.0 * k, fxw + 16.0 * k, 34.0 * k)
	_text(font, Vector2(m, m + 92.0 * k), fxl, 18, Color(0.85, 0.7, 1.0))
	# tracker source (top right)
	var src := TrackerBridge.source_label()
	var sw := font.get_string_size(src, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_text(font, Vector2(s.x - m - sw, m + 8.0 * k + 74.0 * k), src, 20, Color(0.6, 1.0, 0.8))
	# comfort slider (top centre): the one control that is always there
	var bw := minf(s.x * 0.32, 300.0 * k)
	_bar = Rect2(s.x * 0.5 - bw * 0.5, m + 8.0 * k, bw, 14.0 * k)
	_hud.draw_rect(_bar.grow(3.0), Color(0, 0, 0, 0.6))
	_hud.draw_rect(Rect2(_bar.position, Vector2(_bar.size.x * loop.intensity, _bar.size.y)), Color(0.6, 0.5, 1.0))
	var lab := "INTENSITY %d%%   (- / = , C = calm)" % int(round(loop.intensity * 100.0))
	var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k)).x
	_text(font, Vector2(s.x * 0.5 - lw * 0.5, _bar.position.y + 40.0 * k), lab, 16, Color(1, 1, 1, 0.85))
	# gaze cursor
	var gp := TrackerBridge.gaze * s
	_hud.draw_arc(gp, 12.0 * k, 0.0, TAU, 20, Color(1.0, 0.9, 0.5, 0.9), 2.5 * k)
	_hud.draw_circle(gp, 3.0 * k, Color(1.0, 0.9, 0.5, 0.9))
	# charge ring around the orb being stared at
	if loop.target != null and not cam.is_position_behind(loop.target.global_position):
		var oc := cam.unproject_position(loop.target.global_position)
		var prog := clampf(loop.dwell / DopamineLoop.DWELL_START, 0.0, 1.0)
		if not loop.charging:
			_hud.draw_arc(oc, 40.0 * k, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color(1, 1, 1, 0.8), 4.0 * k)
		else:
			_hud.draw_arc(oc, 40.0 * k, -PI * 0.5, -PI * 0.5 + TAU * maxf(loop.charge, 0.03), 40, Color(1.0, 0.6, 0.2), 8.0 * k)
			var msg := "BLINK!" if loop.charge > 0.3 else "keep looking"
			var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k)).x
			_text(font, oc + Vector2(-mw * 0.5, -56.0 * k), msg, 24, Color(1.0, 0.85, 0.4))
	if _toast_t > 0.0:
		var tw := font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30.0 * k)).x
		_text(font, Vector2(s.x * 0.5 - tw * 0.5, s.y * 0.78), _toast, 30, Color(1.0, 0.9, 0.5, clampf(_toast_t, 0.0, 1.0)))
	if _age < 18.0:
		var hint := "LOOK at an orb and hold it.  Then BLINK."
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26.0 * k)).x
		_text(font, Vector2(s.x * 0.5 - hw * 0.5, s.y - m - 10.0 * k), hint, 26, Color(1, 1, 1, 0.9))


func cleanup() -> void:
	if loop != null and is_instance_valid(loop):
		loop.queue_free()
	for n in get_tree().get_nodes_in_group("trance_debris"):
		n.queue_free()
