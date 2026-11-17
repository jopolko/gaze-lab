class_name Mats
## The few kinds of plain material the game is allowed to make.
##
## Why: every different combination of material switches (lit or not, see-through or not, two-sided or not, glow or not, vertex colours or not) is a
## separate shader program, and the browser builds each one, in several versions, while the page is frozen at start-up. Two materials that differ only
## in a colour or a number share a program; two that differ in a switch do not. So every plain material starts from one of these, with the switches
## already set the same way, and only changes colours and numbers afterwards. A switch that is on but not needed costs nothing visible: glow set to
## black adds nothing, vertex colours on a mesh that has none read as white.

## Lit, solid. Vertex colours on, two-sided, glow on (black until you set it).
static func lit() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color.BLACK
	return m


## Unlit, solid: the colour you give it is the colour you see.
static func flat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m


## Unlit, see-through. `two_sided` for flat sheets and walls you can be on either side of; leave it off for closed shapes (a see-through ball would show its back too).
static func glass(two_sided: bool = false) -> StandardMaterial3D:
	var m := flat()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Unlit, see-through, adds its colour to what is behind it (glows, rings, beams).
static func glow() -> StandardMaterial3D:
	var m := glass()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static var _keep: Array = []


## Holds one material of every kind for the whole session. The engine throws a shader away when the last material using it is freed and builds it again
## the next time one is made, so an effect that makes a material, shows it for a second and frees it (a ring at every gate, a burst at every pickup)
## froze the picture every single time. With these kept, each kind is built once.
static func keep_alive(extra: Array = []) -> void:
	if _keep.is_empty():
		_keep = [lit(), flat(), glass(), glass(true), glow()]
	for m in extra:
		if m != null and not _keep.has(m):
			_keep.append(m)
	for m in _keep:
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).get_shader_rid()          # claim the shader now: a material that was never drawn holds nothing


static var _shaders: Dictionary = {}


## One Shader object per piece of shader code, however many materials use it (two Shader objects with the same code are built twice).
static func shader(code: String) -> Shader:
	var sh: Shader = _shaders.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shaders[code] = sh
	return sh
