extends Node
## Godot's own mapping from a flat colour to the pixel on screen, through the environment the psychedelic level uses (Filmic tonemap, exposure 1.05, contrast 1.1, saturation 1.15).
## MODE=albedo (unshaded ShaderMaterial ALBEDO=c) | emission (EMISSION=c) | srccolor (c : source_color) | std (StandardMaterial3D unshaded albedo_color) | lit (ShaderMaterial lit, no lights, ambient colour)
## Writes OUT (json): [{albedo:[r,g,b], px:[r,g,b]}...].  Run: Godot --rendering-driver opengl3 --resolution 640x360 --path godot res://tests/tonecard.tscn
## Env: GRADE=0 turns the colour adjustment off; EXPO=<x> exposure; TONEMAP=<n> (0 linear, 1 reinhard, 2 filmic, 3 aces)

var mat: ShaderMaterial
var std: StandardMaterial3D
var cases: Array = []
var results: Array = []
var i := 0
var wait := 0
var qn: MeshInstance3D
var vc := false
var emis := false


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = int(OS.get_environment("TONEMAP")) if OS.get_environment("TONEMAP") != "" else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(OS.get_environment("EXPO")) if OS.get_environment("EXPO") != "" else 1.05
	env.tonemap_white = 1.0
	env.adjustment_enabled = OS.get_environment("GRADE") != "0"
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.15
	env.glow_enabled = false
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "albedo"
	var code := ""
	if mode == "albedo":
		code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform vec3 c = vec3(0.5);\nvoid fragment() { ALBEDO = c; }\n"
	elif mode == "emission":
		code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform vec3 c = vec3(0.5);\nvoid fragment() { ALBEDO = vec3(0.0); EMISSION = c; }\n"
	elif mode == "srccolor":
		code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform vec3 c : source_color = vec3(0.5);\nvoid fragment() { ALBEDO = c; }\n"
	elif mode == "lit":
		code = "shader_type spatial;\nrender_mode cull_disabled;\nuniform vec3 c = vec3(0.5);\nvoid fragment() { ALBEDO = c; ROUGHNESS = 1.0; SPECULAR = 0.0; }\n"
	var q := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(20, 20)
	q.mesh = pm
	qn = q
	if mode == "sky":
		var skm := ShaderMaterial.new()
		var ssh := Shader.new()
		ssh.code = "shader_type sky;
uniform vec3 c = vec3(0.5);
void sky() { COLOR = c; }
"
		skm.shader = ssh
		var sk := Sky.new()
		sk.sky_material = skm
		sk.process_mode = Sky.PROCESS_MODE_REALTIME
		env.background_mode = Environment.BG_SKY
		env.sky = sk
		mat = skm
		q.visible = false
	elif mode == "vcol_std" or mode == "vcol_shader":
		vc = true
		if mode == "vcol_std":
			std = StandardMaterial3D.new()
			std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.vertex_color_use_as_albedo = true
			q.material_override = std
			std = null
		else:
			var vsh := Shader.new()
			vsh.code = "shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() { ALBEDO = COLOR.rgb; }
"
			mat = ShaderMaterial.new()
			mat.shader = vsh
			q.material_override = mat
	elif mode == "stdemis":
		std = StandardMaterial3D.new()
		std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std.cull_mode = BaseMaterial3D.CULL_DISABLED
		std.albedo_color = Color(0, 0, 0)
		std.emission_enabled = true
		std.emission_energy_multiplier = 1.0
		q.material_override = std
		emis = true
	elif mode == "std":
		std = StandardMaterial3D.new()
		std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material_override = std
	else:
		var sh := Shader.new()
		sh.code = code
		mat = ShaderMaterial.new()
		mat.shader = sh
		q.material_override = mat
	q.position = Vector3(0, 0, -3)
	add_child(q)
	for l in [0.0, 0.005, 0.01, 0.02, 0.04, 0.07, 0.1, 0.14, 0.18, 0.25, 0.35, 0.5, 0.7, 1.0, 1.5, 2.5]:
		cases.append([l, l, l])
	for c in [[0.8, 0.05, 0.05], [0.05, 0.8, 0.05], [0.05, 0.05, 0.8], [0.3, 0.1, 0.5], [0.0, 0.6, 0.2], [0.04, 0.5, 0.04], [0.5, 0.2, 0.0], [0.9, 0.9, 0.1], [0.1, 0.9, 0.9], [0.9, 0.1, 0.9]]:
		cases.append(c)
	_apply_c(cases[0])


func _apply_c(c: Array) -> void:
	if vc:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(10, 10, 0), Vector3(-10, -10, 0), Vector3(10, 10, 0), Vector3(-10, 10, 0)])
		var col := Color(c[0], c[1], c[2])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([col, col, col, col, col, col])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		qn.mesh = am
	elif emis:
		std.emission = Color(c[0], c[1], c[2])
	elif std != null:
		std.albedo_color = Color(c[0], c[1], c[2])
	else:
		mat.set_shader_parameter("c", Vector3(c[0], c[1], c[2]))


func _process(_d: float) -> void:
	wait += 1
	if wait < (12 if OS.get_environment("MODE") == "sky" else 4):
		return
	wait = 0
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var px := img.get_pixel(w / 2, h / 2)
	results.append({"albedo": cases[i], "px": [int(round(px.r * 255.0)), int(round(px.g * 255.0)), int(round(px.b * 255.0))]})
	i += 1
	if i >= cases.size():
		var f := FileAccess.open(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://tonecard.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(results))
		f.close()
		print("TONECARD DONE ", results.size())
		get_tree().quit()
		return
	_apply_c(cases[i])
