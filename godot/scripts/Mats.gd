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


static var _shaders: Dictionary = {}


## One Shader object per piece of shader code, however many materials use it (two Shader objects with the same code are built twice).
static func shader(code: String) -> Shader:
	var sh: Shader = _shaders.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shaders[code] = sh
	return sh
