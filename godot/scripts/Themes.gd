class_name Themes
extends RefCounted
## Looks for the Downhill world. A theme is a sky, a ground, a tree finish, the light, and (for the trippy ones) a full-screen pass.
## Each shader is written to keep the PLAY readable: the ground stays dark enough that gates, trees and rocks always stand out, and the neon goes on the things you must see.

const ORDER := ["alpine", "psychedelic", "matrix", "synthwave"]

const DATA := {
	"alpine": {
		"name": "ALPINE", "blurb": "Crisp snow, dark pine, low sun.",
		"c1": Color(0.55, 0.75, 1.0), "c2": Color(0.95, 0.97, 1.0),
		"env": {},
	},
	"psychedelic": {
		"name": "PSYCHEDELIC", "blurb": "Fractal ground, a breathing sky, rainbow tracers on everything that moves.",
		"c1": Color(1.0, 0.25, 0.85), "c2": Color(0.2, 0.9, 1.0),
		"env": {"sky_top": Color(0.08, 0.0, 0.2), "sky_horizon": Color(0.6, 0.1, 0.7), "sky_ground": Color(0.05, 0.0, 0.12), "ambient": 0.9, "fog_density": 0.0016,
			"fog": Color(0.35, 0.05, 0.45), "sun_color": Color(1.0, 0.7, 1.0), "sun_energy": 0.7, "sun_rot": Vector3(-35.0, -30.0, 0.0), "fog_sky": 0.0, "glow": 0.35, "glow_on": true, "saturation": 1.15, "contrast": 1.1},
	},
	"matrix": {
		"name": "DIGITAL", "blurb": "A green grid with falling code. The slope is a program.",
		"c1": Color(0.1, 1.0, 0.35), "c2": Color(0.02, 0.15, 0.06),
		"env": {"sky_top": Color(0.0, 0.02, 0.0), "sky_horizon": Color(0.0, 0.12, 0.04), "sky_ground": Color(0.0, 0.02, 0.0), "ambient": 0.5, "fog_density": 0.0022,
			"fog": Color(0.0, 0.1, 0.03), "sun_color": Color(0.4, 1.0, 0.6), "sun_energy": 0.4, "sun_rot": Vector3(-40.0, -30.0, 0.0), "fog_sky": 0.0, "glow": 0.5, "glow_on": true, "saturation": 1.0, "contrast": 1.15},
	},
	"synthwave": {
		"name": "SYNTHWAVE", "blurb": "Neon grid, a striped sun that never sets.",
		"c1": Color(1.0, 0.2, 0.7), "c2": Color(0.2, 0.8, 1.0),
		"env": {"sky_top": Color(0.05, 0.0, 0.18), "sky_horizon": Color(1.0, 0.3, 0.6), "sky_ground": Color(0.08, 0.0, 0.15), "ambient": 0.8, "fog_density": 0.0018,
			"fog": Color(0.55, 0.1, 0.5), "sun_color": Color(1.0, 0.5, 0.7), "sun_energy": 0.6, "sun_rot": Vector3(-20.0, 0.0, 0.0), "fog_sky": 0.0, "glow": 0.5, "glow_on": true, "saturation": 1.25, "contrast": 1.1},
	},
}

const HSV := """
vec3 hsv(float h, float s, float v) {
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
"""

# ---------------------------------------------------------------- ground
const GROUND_PSY := """
shader_type spatial;
render_mode cull_disabled, unshaded;
//HSV
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// liquid marble: a coordinate field folded and warped by itself, so the bands flow, split and rejoin as you ride downhill
	vec2 p = wp.xz * 0.045 + vec2(0.0, TIME * 0.05);
	float a = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		p += 0.9 * vec2(sin(p.y * 1.6 + TIME * 0.31 + fi * 1.3), cos(p.x * 1.4 - TIME * 0.27 + fi * 2.1));
		a += sin(p.x * 1.2 + p.y * 0.9 + fi * 1.7);
	}
	float hue = fract(a * 0.15 + TIME * 0.035);
	float band = 1.0 - smoothstep(0.0, 0.16, abs(sin(a * 2.2)));           // thin glowing contour lines
	float soft = 0.5 + 0.5 * sin(a * 1.1 + TIME * 0.4);
	vec3 col = hsv(hue, 1.0, 0.14 + 0.30 * soft) + hsv(fract(hue + 0.5), 0.9, 0.6) * band;
	ALBEDO = col * col;                                          // authored in screen colours: square it into the linear space the renderer wants
}
"""

const GROUND_MATRIX := """
shader_type spatial;
render_mode cull_disabled, unshaded;
//HSV
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float cell = 3.2;
	vec2 g = wp.xz / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float speed = 0.35 + h21(vec2(id.x, 3.0)) * 0.8;
	float t = fract(h21(vec2(id.x, 9.0)) + id.y * 0.071 + TIME * speed * 0.35);     // a drop runs down each column
	float trail = pow(1.0 - t, 3.0);
	float head = smoothstep(0.06, 0.0, t);
	vec2 px = floor(f * vec2(3.0, 5.0));
	float glyph = step(0.45, h21(px + id * 3.1 + floor(TIME * 1.5 + h21(id) * 7.0)));
	float inside = step(0.12, f.x) * step(f.x, 0.88) * step(0.1, f.y) * step(f.y, 0.9);
	float lines = max(smoothstep(0.03, 0.0, f.x), smoothstep(0.03, 0.0, f.y));
	vec3 col = vec3(0.0, 0.015, 0.005);
	col += vec3(0.0, 0.07, 0.03) * lines;
	col += vec3(0.1, 1.0, 0.3) * glyph * inside * trail * 0.55;
	col += vec3(0.7, 1.0, 0.8) * glyph * inside * head * 0.9;
	ALBEDO = col * col;
}
"""

const GROUND_SYNTH := """
shader_type spatial;
render_mode cull_disabled, unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = wp.xz / 5.0;
	vec2 f = abs(fract(g) - 0.5);
	float w = 0.035 + 0.0025 * length(VERTEX);                          // lines stay visible far away
	float line = max(smoothstep(0.5 - w, 0.5, f.x * 1.0 + 0.0), smoothstep(0.5 - w, 0.5, f.y));
	float pulse = 0.65 + 0.35 * sin(wp.z * 0.05 - TIME * 2.0);
	vec3 neon = mix(vec3(1.0, 0.1, 0.65), vec3(0.15, 0.85, 1.0), 0.5 + 0.5 * sin(wp.x * 0.02 + TIME * 0.3));
	vec3 col = vec3(0.03, 0.0, 0.07) + neon * line * pulse * 0.9;
	ALBEDO = col * col;
}
"""

# ---------------------------------------------------------------- trees and rocks (vertex colours tell us 'dark skirt' from 'bright top')
const VEG_PSY := """
shader_type spatial;
render_mode cull_disabled;
//HSV
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.34));
	float hue = fract(wp.z * 0.012 + wp.x * 0.007 + TIME * 0.07 + lum * 0.2);
	vec3 neon = hsv(hue, 0.85, 1.0);
	ALBEDO = mix(vec3(0.03, 0.0, 0.06), neon * 0.75, smoothstep(0.1, 0.9, lum));
	EMISSION = neon * smoothstep(0.35, 1.0, lum) * 0.75;
	ROUGHNESS = 0.5;
}
"""

const VEG_MATRIX := """
shader_type spatial;
render_mode cull_disabled, unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.34));
	float scan = 0.65 + 0.35 * sin(wp.y * 6.0 - TIME * 3.0);
	ALBEDO = mix(vec3(0.0, 0.03, 0.01), vec3(0.15, 1.0, 0.4) * scan, smoothstep(0.1, 0.95, lum));
}
"""

const VEG_SYNTH := """
shader_type spatial;
render_mode cull_disabled, unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.34));
	vec3 hot = mix(vec3(1.0, 0.15, 0.6), vec3(0.2, 0.85, 1.0), clamp(wp.y * 0.12, 0.0, 1.0));
	ALBEDO = mix(vec3(0.06, 0.0, 0.12), hot, smoothstep(0.1, 0.95, lum));
}
"""

# ---------------------------------------------------------------- sky
const SKY_PSY := """
shader_type sky;
vec3 pal(float t) { return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67))); }
void sky() {
	vec3 d = EYEDIR;
	float t = TIME * 0.04;
	// a stereographic map of the whole sky, folded again and again: a slowly turning mandala of glowing filaments on a deep field
	vec2 p = d.xz / (1.0 + abs(d.y) * 1.3 + 0.001) * 1.5;
	float c = cos(t), s = sin(t);
	p = mat2(vec2(c, s), vec2(-s, c)) * p;
	float acc = 0.0;
	float m = 1.0e3;
	for (int i = 0; i < 9; i++) {
		p = abs(p) / (dot(p, p) + 0.002) - vec2(0.90 + 0.05 * sin(TIME * 0.11), 0.58 + 0.04 * cos(TIME * 0.09));
		acc += length(p);
		m = min(m, abs(p.x) + abs(p.y) * 0.7);
	}
	float glow = exp(-m * 4.0);
	vec3 col = pal(acc * 0.025 + TIME * 0.025 + d.y * 0.3) * (0.04 + 0.62 * glow * glow);
	col += vec3(0.02, 0.0, 0.06);
	float horizon = smoothstep(-0.1, 0.3, d.y);
	COLOR = mix(vec3(0.10, 0.01, 0.16), col, horizon);
}
"""

const SKY_MATRIX := """
shader_type sky;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void sky() {
	vec3 d = EYEDIR;
	float az = atan(d.x, -d.z);
	float col = floor(az * 26.0);
	float speed = 0.2 + h21(vec2(col, 1.0)) * 0.5;
	float y = d.y * 14.0;
	float t = fract(h21(vec2(col, 5.0)) - TIME * speed * 0.25 + floor(y) * 0.11);
	float streak = pow(1.0 - t, 4.0) * step(0.0, d.y);
	float cellf = smoothstep(0.0, 0.2, fract(az * 26.0)) * smoothstep(1.0, 0.8, fract(az * 26.0));
	vec3 base = mix(vec3(0.0, 0.05, 0.02), vec3(0.0, 0.0, 0.0), clamp(d.y * 2.0, 0.0, 1.0));
	COLOR = base + vec3(0.1, 1.0, 0.3) * streak * cellf * 0.5;
}
"""

const SKY_SYNTH := """
shader_type sky;
void sky() {
	vec3 d = EYEDIR;
	vec3 top = vec3(0.04, 0.0, 0.16);
	vec3 hor = vec3(1.0, 0.25, 0.55);
	float k = pow(clamp(1.0 - abs(d.y), 0.0, 1.0), 3.0);
	vec3 col = mix(top, hor, k);
	// the sun, low, sliced into stripes that widen toward the bottom
	vec3 sd = normalize(vec3(0.0, 0.14, -1.0));
	float r = acos(clamp(dot(d, sd), -1.0, 1.0));
	float disc = smoothstep(0.34, 0.325, r);
	float band = step(0.5, fract((d.y - 0.14) * 22.0 + 0.5));
	float cut = d.y < 0.14 ? mix(1.0, band, clamp((0.14 - d.y) * 9.0, 0.0, 1.0)) : 1.0;
	vec3 sun = mix(vec3(1.0, 0.85, 0.2), vec3(1.0, 0.1, 0.55), clamp((0.34 - r) * -3.0 + (0.14 - d.y) * 4.0 + 0.2, 0.0, 1.0));
	col = mix(col, sun, disc * cut);
	col += vec3(1.0, 0.3, 0.6) * smoothstep(0.7, 0.325, r) * 0.18;
	COLOR = col;
}
"""

# ---------------------------------------------------------------- the full-screen pass
## The overlay sees the finished picture (screen_texture). In the psychedelic theme `trail` is a slowly fading stack of recent frames; where the picture has moved
## since then (and ONLY there, so the HUD and still things are untouched) it adds a hue-rotating echo: tracers.
const POST := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D trail : filter_linear, repeat_disable;
uniform sampler2D cur : filter_linear, repeat_disable;     // the same picture as the trail is made of, this frame
uniform float mode = 0.0;        // 1 psychedelic, 2 digital, 3 synthwave
uniform float amount = 1.0;
uniform float breathe = 0.0;     // 0..1 how hard the picture breathes
""" + HSV + """
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);
	vec3 col;
	if (mode < 0.5) {
		col = texture(screen_tex, uv).rgb;
	} else if (mode < 1.5) {
		// psychedelic: a gentle breathing warp, chromatic split that grows toward the edges, tracers
		float w = sin(TIME * 0.7 + r * 9.0) * 0.0035 * amount * breathe;
		vec2 wuv = uv + c * w * 2.0 + vec2(sin(uv.y * 14.0 + TIME) * 0.0008, 0.0) * amount * breathe;
		float ca = (0.003 + r * 0.012) * amount;
		col = vec3(texture(screen_tex, wuv + c * ca).r, texture(screen_tex, wuv).g, texture(screen_tex, wuv - c * ca).b);
		vec3 old = texture(trail, uv).rgb;
		vec3 diff = max(old - texture(cur, uv).rgb * 0.92 - 0.02, vec3(0.0));
		float m = clamp(dot(diff, vec3(0.34)) * 3.2, 0.0, 1.0);
		vec3 ghost = hsv(fract(TIME * 0.12 + r * 0.9 + m * 0.5), 0.95, 1.0) * m;
		col += ghost * 1.15 * amount;
		col = mix(col, col * hsv(fract(TIME * 0.05), 0.25, 1.1), 0.12 * amount);
		col *= 1.0 - 0.45 * smoothstep(0.45, 0.95, r);
	} else if (mode < 2.5) {
		// digital: green tint, scanlines, a little flicker, vignette
		col = texture(screen_tex, uv).rgb;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(0.1, 1.0, 0.35) * l * 1.2, 0.55 * amount);
		col *= 0.9 + 0.1 * sin(uv.y * 900.0 + TIME * 6.0);
		col *= 1.0 - 0.5 * smoothstep(0.4, 0.95, r);
	} else {
		// synthwave: chromatic fringe, soft scanlines, hot glow in the highlights
		float ca = (0.0015 + r * 0.006) * amount;
		col = vec3(texture(screen_tex, uv + c * ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv - c * ca).b);
		col *= 0.94 + 0.06 * sin(uv.y * 700.0);
		col += max(col - 0.75, 0.0) * vec3(0.8, 0.2, 0.6) * 0.8;
		col *= 1.0 - 0.4 * smoothstep(0.45, 0.95, r);
	}
	COLOR = vec4(col, 1.0);
}
"""

# the feedback quad: draws the finished frame onto the trail texture at a low alpha, so old frames fade out slowly
const TRAIL_QUAD := """
shader_type canvas_item;
void fragment() { vec4 t = texture(TEXTURE, UV); COLOR = vec4(t.rgb, COLOR.a); }
"""


static func theme_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["alpine"])


static func make_shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code.replace("//HSV", HSV)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func ground_material(id: String) -> ShaderMaterial:
	match id:
		"psychedelic":
			return make_shader(GROUND_PSY)
		"matrix":
			return make_shader(GROUND_MATRIX)
		"synthwave":
			return make_shader(GROUND_SYNTH)
	return null


static func veg_material(id: String) -> ShaderMaterial:
	match id:
		"psychedelic":
			return make_shader(VEG_PSY)
		"matrix":
			return make_shader(VEG_MATRIX)
		"synthwave":
			return make_shader(VEG_SYNTH)
	return null


static func sky_material(id: String) -> ShaderMaterial:
	match id:
		"psychedelic":
			return make_shader(SKY_PSY)
		"matrix":
			return make_shader(SKY_MATRIX)
		"synthwave":
			return make_shader(SKY_SYNTH)
	return null


static func mist_color(id: String) -> Color:
	match id:
		"psychedelic":
			return Color(0.14, 0.02, 0.24, 0.97)
		"matrix":
			return Color(0.0, 0.05, 0.015, 0.98)
		"synthwave":
			return Color(0.38, 0.04, 0.42, 0.97)
	return Color(0.93, 0.96, 1.0, 0.97)


static func post_mode(id: String) -> int:
	return {"psychedelic": 1, "matrix": 2, "synthwave": 3}.get(id, 0)
