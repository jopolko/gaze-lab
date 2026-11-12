class_name ThemeFX
extends Node
## Puts a Themes look onto a running level (sky, light, ground, trees, the full-screen pass), or onto the menu backdrop.
## ThemePost is the full-screen pass; with the psychedelic theme it also keeps a fading stack of recent frames (a SubViewport that is never cleared, onto which each
## finished frame is drawn at a low alpha) so that whatever moved leaves a rainbow echo.

var post: ThemePost
var _theme: String = "alpine"


## Apply a theme to the Downhill level. Safe to call again with another theme (alpine puts everything back).
static func apply_to_level(level: MainLevel, rig: DownhillRig, id: String, intensity: float = 1.0) -> void:
	var env: Environment = level.world_env.environment
	var sky := env.sky
	if not sky.has_meta("orig_sky"):
		sky.set_meta("orig_sky", sky.sky_material)
		sky.set_meta("alpine_cfg", _snapshot(level))
		rig.set_meta("orig_ground", (rig._m_ground as ShaderMaterial).shader)
	var data := Themes.theme_data(id)
	sky.sky_material = sky.get_meta("orig_sky")
	var cfg: Dictionary = (sky.get_meta("alpine_cfg") as Dictionary).duplicate()
	var te: Dictionary = data["env"]
	for k in te:
		cfg[k] = te[k]
	level._apply_environment(cfg)
	var sm := Themes.sky_material(id)
	if sm != null:
		sky.sky_material = sm
	# ground: swap the shader inside the very material every chunk already uses
	var gm := Themes.ground_material(id)
	(rig._m_ground as ShaderMaterial).shader = gm.shader if gm != null else (rig.get_meta("orig_ground") as Shader)
	rig._veg_theme = Themes.veg_material(id)
	rig.mist_color = Themes.mist_color(id)
	if rig._mist != null:
		(rig._mist.material_override as ShaderMaterial).set_shader_parameter("tint", rig.mist_color)
	var host: Node = level.get_node_or_null("ThemeFX")
	var fx: ThemeFX = host as ThemeFX
	if fx == null:
		fx = ThemeFX.new()
		fx.name = "ThemeFX"
		fx.process_mode = Node.PROCESS_MODE_ALWAYS
		level.add_child(fx)
	fx.show_theme(id, intensity)


static func _snapshot(level: MainLevel) -> Dictionary:
	var env: Environment = level.world_env.environment
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	var sun: DirectionalLight3D = level.sun
	return {"sky_top": sm.sky_top_color, "sky_horizon": sm.sky_horizon_color, "sky_ground": sm.ground_bottom_color, "ambient": env.ambient_light_energy,
		"fog_density": env.fog_density if env.fog_enabled else 0.0, "fog": env.fog_light_color, "exposure": env.tonemap_exposure, "glow": env.glow_intensity,
		"saturation": env.adjustment_saturation, "contrast": env.adjustment_contrast, "sun_color": sun.light_color, "sun_energy": sun.light_energy,
		"sun_rot": sun.rotation_degrees, "sun_disc": sm.sun_angle_max, "sun_curve": sm.sun_curve, "fog_sky": env.fog_sky_affect, "glow_on": env.glow_enabled}


func show_theme(id: String, intensity: float = 1.0) -> void:
	_theme = id
	if post == null:
		post = ThemePost.new()
		post.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(post)
		post.setup_screen()
	post.set_look(Themes.post_mode(id), intensity)


func current() -> String:
	return _theme


## The full-screen pass. Mode 0 is off.
class ThemePost extends Node:
	var mat: ShaderMaterial
	var layer: CanvasLayer
	var rect: CanvasItem
	var trail_vp: SubViewport
	var src: Viewport
	var cur_vp: SubViewport                  # in the game: a second, small render of the same world (no HUD, no overlay), the picture the tracers are made from
	var cur_cam: Camera3D
	var src_tex: Texture2D
	var mode: int = 0
	var amount: float = 1.0
	var _own_tex: bool = false

	## Over the whole game picture (above the HUD, below the menus).
	func setup_screen() -> void:
		src = get_tree().root
		layer = CanvasLayer.new()
		layer.layer = 5
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		var r := ColorRect.new()
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(r)
		rect = r
		mat = Themes.make_shader(Themes.POST)
		r.material = mat
		layer.visible = false

	## Over the menu backdrop: reads a SubViewport instead of the screen.
	func setup_backdrop(vp: SubViewport, target: TextureRect) -> void:
		src = vp
		_own_tex = true
		rect = target
		target.texture = vp.get_texture()
		src_tex = vp.get_texture()
		mat = Themes.make_shader(Themes.POST.replace("uniform sampler2D screen_tex : hint_screen_texture, filter_linear;", "uniform sampler2D screen_tex : filter_linear;"))
		mat.set_shader_parameter("screen_tex", vp.get_texture())
		target.material = mat

	func set_look(m: int, intensity: float) -> void:
		if OS.has_feature("web") and not _own_tex and str(JavaScriptBridge.eval("window.location.search")).contains("nopost"):
			m = 0                                                  # ?nopost: the world's look without the full-screen pass (to tell the two apart)
		mode = m
		amount = clampf(intensity, 0.0, 1.5)
		if mat == null:
			return
		mat.set_shader_parameter("mode", float(m))
		mat.set_shader_parameter("amount", amount)
		mat.set_shader_parameter("breathe", amount)
		if layer != null:
			layer.visible = m > 0
		if m == 1:
			_make_trail()
		elif trail_vp != null:
			trail_vp.queue_free()
			trail_vp = null
			if cur_vp != null:
				cur_vp.queue_free()
				cur_vp = null
			mat.set_shader_parameter("trail", null)

	func _make_trail() -> void:
		if trail_vp != null:
			return
		if not _own_tex:
			# the overlay's own output ends up in the screen picture, so the screen cannot be fed back into itself: render the world once more, small, without any overlay
			cur_vp = SubViewport.new()
			cur_vp.world_3d = get_tree().root.world_3d
			cur_vp.msaa_3d = Viewport.MSAA_DISABLED
			cur_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			cur_vp.size = _trail_size()
			add_child(cur_vp)
			cur_cam = Camera3D.new()
			cur_vp.add_child(cur_cam)
			cur_cam.current = true
			src_tex = cur_vp.get_texture()
		trail_vp = SubViewport.new()
		trail_vp.disable_3d = true
		trail_vp.transparent_bg = false
		trail_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		trail_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		trail_vp.size = _trail_size()
		add_child(trail_vp)
		var tr := TextureRect.new()
		tr.texture = src_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.modulate = Color(1, 1, 1, 0.07)                        # each frame is laid over the pile at 7 %: an echo that lasts about a third of a second
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trail_vp.add_child(tr)
		mat.set_shader_parameter("trail", trail_vp.get_texture())
		mat.set_shader_parameter("cur", src_tex)

	func _trail_size() -> Vector2i:
		var s: Vector2 = src.get_visible_rect().size if src != get_tree().root else Vector2(get_tree().root.size)
		return Vector2i(maxi(int(s.x * 0.5), 64), maxi(int(s.y * 0.5), 64))

	func _process(_delta: float) -> void:
		if trail_vp != null:
			var ts := _trail_size()
			if ts != trail_vp.size:
				trail_vp.size = ts
				if cur_vp != null:
					cur_vp.size = ts
			if cur_cam != null:
				var c := get_viewport().get_camera_3d()
				if c != null and c != cur_cam:
					cur_cam.global_transform = c.global_transform
					cur_cam.fov = c.fov
					cur_cam.keep_aspect = c.keep_aspect
					cur_cam.near = c.near
					cur_cam.far = c.far
					cur_cam.h_offset = c.h_offset
					cur_cam.v_offset = c.v_offset
