class_name Themes
extends RefCounted
## Looks for the Downhill world. A theme is a sky, a ground, a tree finish, the light, and (for the trippy ones) a full-screen pass.
## Each shader is written to keep the PLAY readable: the ground stays dark enough that gates, trees and rocks always stand out, and the neon goes on the things you must see.

const ORDER := ["alpine", "candy", "egypt", "psychedelic", "matrix", "synthwave"]

const DATA := {
	"alpine": {
		"name": "ALPINE", "blurb": "Crisp snow, dark pine, low sun.",
		"c1": Color(0.55, 0.75, 1.0), "c2": Color(0.95, 0.97, 1.0),
		"env": {},
	},
	"candy": {
		"name": "CANDYLAND", "blurb": "Fluffy cotton trees, gumdrop rocks, frosting snow with sprinkles, and a pastel sky.",
		"c1": Color(1.0, 0.45, 0.72), "c2": Color(0.5, 0.95, 0.8),
		"env": {"sky_top": Color(0.70, 0.62, 1.0), "sky_horizon": Color(1.0, 0.84, 0.84), "sky_ground": Color(0.95, 0.7, 0.85), "ambient": 1.0, "fog_density": 0.0012,
			"fog": Color(1.0, 0.83, 0.9), "sun_color": Color(1.0, 0.92, 0.85), "sun_energy": 1.0, "sun_rot": Vector3(-36.0, -30.0, 0.0), "fog_sky": 0.0, "glow": 0.3, "glow_on": false, "saturation": 1.2, "contrast": 1.05},
	},
	"egypt": {
		"name": "EGYPT", "blurb": "Pyramids on the horizon, rolling mummies, and a sandstorm that rolls in every minute.",
		"c1": Color(1.0, 0.78, 0.25), "c2": Color(0.15, 0.8, 0.75),
		"env": {"sky_top": Color(0.2, 0.45, 0.85), "sky_horizon": Color(1.0, 0.82, 0.5), "sky_ground": Color(0.9, 0.7, 0.4), "ambient": 0.95, "fog_density": 0.0012,
			"fog": Color(0.96, 0.8, 0.52), "sun_color": Color(1.0, 0.9, 0.7), "sun_energy": 1.0, "sun_rot": Vector3(-32.0, -40.0, 0.0), "fog_sky": 0.0, "glow": 0.2, "glow_on": false, "saturation": 1.15, "contrast": 1.08},
	},
	"psychedelic": {
		"name": "PSYCHEDELIC", "blurb": "Fractal ground, a breathing sky, rainbow tracers on everything that moves.",
		"c1": Color(1.0, 0.25, 0.85), "c2": Color(0.2, 0.9, 1.0),
		"env": {"sky_top": Color(0.08, 0.0, 0.2), "sky_horizon": Color(0.6, 0.1, 0.7), "sky_ground": Color(0.05, 0.0, 0.12), "ambient": 0.9, "fog_density": 0.0016,
			"fog": Color(0.35, 0.05, 0.45), "sun_color": Color(1.0, 0.7, 1.0), "sun_energy": 0.7, "sun_rot": Vector3(-35.0, -30.0, 0.0), "fog_sky": 0.0, "glow": 0.35, "glow_on": false, "saturation": 1.15, "contrast": 1.1},
	},
	"matrix": {
		"name": "DIGITAL", "blurb": "A green grid with falling code. The slope is a program.",
		"c1": Color(0.1, 1.0, 0.35), "c2": Color(0.02, 0.15, 0.06),
		"env": {"sky_top": Color(0.0, 0.02, 0.0), "sky_horizon": Color(0.0, 0.12, 0.04), "sky_ground": Color(0.0, 0.02, 0.0), "ambient": 0.5, "fog_density": 0.0022,
			"fog": Color(0.0, 0.1, 0.03), "sun_color": Color(0.4, 1.0, 0.6), "sun_energy": 0.4, "sun_rot": Vector3(-40.0, -30.0, 0.0), "fog_sky": 0.0, "glow": 0.5, "glow_on": false, "saturation": 1.0, "contrast": 1.15},
	},
	"synthwave": {
		"name": "SYNTHWAVE", "blurb": "Neon grid, a striped sun that never sets.",
		"c1": Color(1.0, 0.2, 0.7), "c2": Color(0.2, 0.8, 1.0),
		"env": {"sky_top": Color(0.05, 0.0, 0.18), "sky_horizon": Color(1.0, 0.3, 0.6), "sky_ground": Color(0.08, 0.0, 0.15), "ambient": 0.8, "fog_density": 0.0018,
			"fog": Color(0.55, 0.1, 0.5), "sun_color": Color(1.0, 0.5, 0.7), "sun_energy": 0.6, "sun_rot": Vector3(-20.0, 0.0, 0.0), "fog_sky": 0.0, "glow": 0.5, "glow_on": false, "saturation": 1.25, "contrast": 1.1},
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

const GROUND_CANDY := """
shader_type spatial;
render_mode cull_disabled, unshaded;
//HSV
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec3 candy(float h) {
	h = fract(h) * 6.0;
	if (h < 1.0) return vec3(1.0, 0.45, 0.72);
	if (h < 2.0) return vec3(0.5, 0.95, 0.8);
	if (h < 3.0) return vec3(0.72, 0.55, 1.0);
	if (h < 4.0) return vec3(1.0, 0.72, 0.45);
	if (h < 5.0) return vec3(0.5, 0.78, 1.0);
	return vec3(1.0, 0.9, 0.5);
}
void fragment() {
	// frosting: soft swirled bands of pink, cream and mint, and sprinkles scattered over it
	float rip = 0.5 + 0.5 * sin(wp.x * 0.13 + sin(wp.z * 0.035) * 3.0 + sin(wp.x * 0.04) * 2.0);
	float band = floor(rip * 3.0);
	vec3 col = band < 1.0 ? vec3(1.0, 0.62, 0.80) : (band < 2.0 ? vec3(0.98, 0.88, 0.84) : vec3(0.66, 0.92, 0.84));
	vec2 cell = floor(wp.xz * 0.8);
	float hh = h21(cell);
	vec2 l = fract(wp.xz * 0.8) - 0.5;
	float ang = hh * 6.2831;
	l = mat2(vec2(cos(ang), -sin(ang)), vec2(sin(ang), cos(ang))) * l;
	float spr = step(0.80, hh) * step(abs(l.x), 0.34) * step(abs(l.y), 0.10);
	col = mix(col, candy(hh * 7.3), spr);
	ALBEDO = col * col;
}
"""

const VEG_CANDY := """
shader_type spatial;
render_mode cull_disabled, unshaded;
//HSV
varying vec3 org;
void vertex() { org = MODEL_MATRIX[3].xyz; }
vec3 candy(float h) {
	h = fract(h) * 6.0;
	if (h < 1.0) return vec3(1.0, 0.45, 0.72);
	if (h < 2.0) return vec3(0.5, 0.95, 0.8);
	if (h < 3.0) return vec3(0.72, 0.55, 1.0);
	if (h < 4.0) return vec3(1.0, 0.72, 0.45);
	if (h < 5.0) return vec3(0.5, 0.78, 1.0);
	return vec3(1.0, 0.9, 0.5);
}
void fragment() {
	// every tree and rock is its own sweet: the colour comes from where it stands, the pale cap and the dark underside from the mesh
	float lum = dot(COLOR.rgb, vec3(0.34));
	vec3 base = candy(h21(floor(org.xz * 0.37)) * 1.7);
	vec3 top = mix(base, vec3(1.0, 0.97, 0.98), 0.72);
	float k = floor(smoothstep(0.22, 0.85, lum) * 3.0) / 2.0;
	vec3 c = mix(base * 0.82, top, clamp(k, 0.0, 1.0));
	ALBEDO = c * c;
}
"""

const SKY_CANDY := """
shader_type sky;
void sky() {
	vec3 d = EYEDIR;
	vec3 top = vec3(0.62, 0.50, 0.96);
	vec3 hor = vec3(1.0, 0.78, 0.78);
	float k = pow(clamp(1.0 - abs(d.y), 0.0, 1.0), 2.2);
	vec3 col = mix(top, hor, k);
	col *= col;
	vec3 sd = normalize(vec3(0.25, 0.30, -1.0));
	float r = acos(clamp(dot(d, sd), -1.0, 1.0));
	col = mix(col, vec3(1.0, 0.97, 0.9), smoothstep(0.14, 0.13, r));
	col += vec3(1.0, 0.6, 0.8) * smoothstep(0.6, 0.13, r) * 0.2;
	COLOR = col;
}
"""

const GROUND_EGYPT := """
shader_type spatial;
render_mode cull_disabled, unshaded;
//HSV
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// dunes in flat bands, like a cartoon: long ripples across the slope, a few darker hieroglyph-like dashes, a little grain
	float rip = 0.5 + 0.5 * sin(wp.x * 0.22 + sin(wp.z * 0.045) * 3.2 + sin(wp.x * 0.05) * 2.0);
	float band = floor(rip * 3.0) / 3.0;
	vec3 sand = mix(vec3(0.72, 0.46, 0.22), vec3(0.92, 0.70, 0.38), band);
	float dash = step(0.93, h21(floor(vec2(wp.x * 0.5, wp.z * 0.12)))) * step(0.5, fract(wp.z * 0.12 + 0.2)) * 0.5;
	sand = mix(sand, vec3(0.42, 0.22, 0.10), dash);
	sand *= 0.96 + 0.06 * h21(floor(wp.xz * 3.0));
	ALBEDO = sand * sand;
}
"""

const VEG_EGYPT := """
shader_type spatial;
render_mode cull_disabled, unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// turquoise and gold: the palm-and-obelisk palette
	float lum = dot(COLOR.rgb, vec3(0.34));
	float k = floor(smoothstep(0.30, 0.80, lum) * 3.0) / 2.0;
	vec3 c = mix(vec3(0.08, 0.62, 0.58), vec3(1.0, 0.8, 0.3), clamp(k, 0.0, 1.0));
	ALBEDO = c * c;
}
"""

const SKY_EGYPT := """
shader_type sky;
void sky() {
	vec3 d = EYEDIR;
	vec3 top = vec3(0.10, 0.30, 0.78);
	vec3 hor = vec3(0.98, 0.62, 0.32);
	float k = pow(clamp(1.0 - abs(d.y), 0.0, 1.0), 2.5);
	vec3 col = mix(top, hor, k);
	col *= col;
	vec3 sd = normalize(vec3(-0.3, 0.32, -1.0));
	float r = acos(clamp(dot(d, sd), -1.0, 1.0));
	float disc = smoothstep(0.16, 0.15, r);
	col = mix(col, vec3(1.0, 0.97, 0.8), disc);
	col += vec3(1.0, 0.7, 0.3) * smoothstep(0.5, 0.15, r) * 0.16;
	COLOR = col;
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
uniform float use_trail = 1.0;     // 0 when the tracer pass is switched off to save frame rate
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
		col += ghost * 1.15 * amount * use_trail;
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
		"candy":
			return make_shader(GROUND_CANDY)
		"egypt":
			return make_shader(GROUND_EGYPT)
		"psychedelic":
			return make_shader(GROUND_PSY)
		"matrix":
			return make_shader(GROUND_MATRIX)
		"synthwave":
			return make_shader(GROUND_SYNTH)
	return null


static func veg_material(id: String) -> ShaderMaterial:
	match id:
		"candy":
			return make_shader(VEG_CANDY)
		"egypt":
			return make_shader(VEG_EGYPT)
		"psychedelic":
			return make_shader(VEG_PSY)
		"matrix":
			return make_shader(VEG_MATRIX)
		"synthwave":
			return make_shader(VEG_SYNTH)
	return null


static func sky_material(id: String) -> ShaderMaterial:
	match id:
		"candy":
			return make_shader(SKY_CANDY)
		"egypt":
			return make_shader(SKY_EGYPT)
		"psychedelic":
			return make_shader(SKY_PSY)
		"matrix":
			return make_shader(SKY_MATRIX)
		"synthwave":
			return make_shader(SKY_SYNTH)
	return null


static func mist_color(id: String) -> Color:
	match id:
		"candy":
			return Color(1.0, 0.86, 0.92, 0.97)
		"egypt":
			return Color(0.98, 0.84, 0.58, 0.97)
		"psychedelic":
			return Color(0.14, 0.02, 0.24, 0.97)
		"matrix":
			return Color(0.0, 0.05, 0.015, 0.98)
		"synthwave":
			return Color(0.38, 0.04, 0.42, 0.97)
	return Color(0.93, 0.96, 1.0, 0.97)


## A lumpy sphere for the fluffy shapes: smooth, a little uneven, dark underneath and pale on top (the vertex colours tell the shaders which is which).
static func _puff(st: SurfaceTool, c: Vector3, r: float, squash: float, dark: Color, light: Color, seed: float) -> void:
	var rings := 4                      # light on purpose: there are hundreds of these on screen, and a phone has to draw them while the tracker uses the same chip
	var segs := 7
	var grid: Array = []
	for i in rings + 1:
		var phi := PI * float(i) / float(rings)
		var row: Array = []
		for j in segs + 1:
			var th := TAU * float(j) / float(segs)
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var lump := 1.0 + 0.09 * sin(th * 3.0 + seed) + 0.07 * sin(phi * 5.0 + seed * 1.7)
			var p := c + Vector3(n.x * r * lump, n.y * r * squash * lump, n.z * r * lump)
			var col := dark.lerp(light, smoothstep(-0.25, 0.9, n.y))
			row.append([p, col])
		grid.append(row)
	for i in rings:
		for j in segs:
			var a: Array = (grid[i] as Array)[j]
			var b: Array = (grid[i] as Array)[j + 1]
			var cc: Array = (grid[i + 1] as Array)[j]
			var d: Array = (grid[i + 1] as Array)[j + 1]
			for tri in [[a, cc, b], [b, cc, d]]:
				for v in tri:
					st.set_color(v[1])
					st.add_vertex(v[0])


## A fluffy tree: four soft puffs stacked and narrowing, a stubby trunk. Roughly the footprint of the pine it replaces, so nothing about the course changes.
static func fluffy_tree_mesh(id: String) -> ArrayMesh:
	var dark := Color(0.20, 0.62, 0.50)
	var light := Color(0.95, 0.98, 1.0)
	if id == "candy":
		dark = Color(0.30, 0.30, 0.34)
		light = Color(0.95, 0.95, 0.97)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_puff(st, Vector3(0.0, 1.6, 0.0), 1.9, 0.9, dark, light, 0.3)
	_puff(st, Vector3(0.2, 3.6, 0.1), 1.45, 0.95, dark, light, 1.1)
	_puff(st, Vector3(-0.05, 5.2, 0.0), 0.95, 1.05, dark, light, 2.0)
	st.generate_normals()
	return st.commit()


## A gumdrop for a rock: a squat, smooth dome.
static func gumdrop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_puff(st, Vector3(0.0, 0.5, 0.0), 1.35, 0.72, Color(0.42, 0.42, 0.46), Color(0.92, 0.92, 0.96), 0.7)
	st.generate_normals()
	return st.commit()


## Cotton-candy hills around the horizon, in place of mountains.
static func candy_hills_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var pal := [Color(1.0, 0.62, 0.82), Color(0.62, 0.95, 0.85), Color(0.78, 0.66, 1.0), Color(1.0, 0.8, 0.6), Color(0.62, 0.82, 1.0)]
	for i in 22:
		var ang := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / 22.0
		var far := i % 2 == 0
		var dist := rng.randf_range(780.0, 980.0) if far else rng.randf_range(540.0, 680.0)
		var r := rng.randf_range(190.0, 320.0) if far else rng.randf_range(110.0, 200.0)
		var base: Color = pal[i % pal.size()]
		_puff_big(st, Vector3(sin(ang) * dist, -r * 0.25, cos(ang) * dist), r, base.darkened(0.12), base.lightened(0.35), rng.randf() * 6.0)
	st.generate_normals()
	return st.commit()


static func _puff_big(st: SurfaceTool, c: Vector3, r: float, dark: Color, light: Color, seed: float) -> void:
	_puff(st, c, r, 0.9, dark, light, seed)


## What rolls down at you (the snowball's stand-in): the rules are the same, the monster is not.
static func hazard_skin(id: String) -> String:
	return "mummy" if id == "egypt" else ("gumball" if id == "candy" else "snow")


## Pyramids (and a few obelisks) in a ring far away, in the colours of sandstone, each face a different shade.
static func pyramid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3150
	var n := 14
	for i in n:
		var ang := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(n)
		var far := i % 2 == 0
		var dist := rng.randf_range(760.0, 980.0) if far else rng.randf_range(520.0, 660.0)
		var big := rng.randf_range(150.0, 300.0) if far else rng.randf_range(80.0, 160.0)
		var obelisk := i % 5 == 3
		var half := big * (0.12 if obelisk else 0.62)
		var h := big * (2.4 if obelisk else 1.0)
		var c := Vector3(sin(ang) * dist, 0.0, cos(ang) * dist)
		var rot := rng.randf() * TAU
		var corners: Array[Vector3] = []
		for k in 4:
			var a := rot + TAU * float(k) / 4.0 + PI / 4.0
			corners.append(c + Vector3(cos(a), 0.0, sin(a)) * half * 1.414)
		var apex := c + Vector3(0, h, 0)
		var face_cols := [Color(1.0, 0.86, 0.55), Color(0.86, 0.66, 0.38), Color(0.98, 0.78, 0.48), Color(0.7, 0.5, 0.3)]
		for k in 4:
			var k2 := (k + 1) % 4
			var fc: Color = face_cols[k]
			st.set_color(fc)
			st.add_vertex(corners[k])
			st.set_color(fc)
			st.add_vertex(corners[k2])
			st.set_color(fc.lightened(0.18))
			st.add_vertex(apex)
	st.generate_normals()
	return st.commit()


static func post_mode(id: String) -> int:
	return {"psychedelic": 1, "matrix": 2, "synthwave": 3}.get(id, 0)
