// Full-screen post effect for Ocular Trance: chromatic aberration and the camera's nystagmus pixel shift, plus screen-space
// ports of the psychedelic WebXR demos (flow-based UV distortion, fractal-kaleidoscope fold, infinite tunnel, volumetric god
// rays, ring-and-spoke phosphene overlay). Put it on a ColorRect that covers the screen, in a CanvasLayer above the 3D view and
// below the HUD. Every effect is driven by a 0..1 weight from script (DopamineLoop) and scaled by the player's comfort
// `intensity`. A weight of 0 skips that effect's code entirely, so only the active ones cost anything.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float aberration : hint_range(0.0, 2.0) = 0.0;
uniform vec2 nystagmus = vec2(0.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.4;       // the player's comfort setting
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;
uniform float aspect = 1.78;
// effect weights, 0..1
uniform float flow : hint_range(0.0, 1.0) = 0.0;
uniform float kaleido : hint_range(0.0, 1.0) = 0.0;
uniform float tunnel : hint_range(0.0, 1.0) = 0.0;
uniform float rays : hint_range(0.0, 1.0) = 0.0;
uniform float phos : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rays_pos = vec2(0.5);                           // screen UV of the orb being stared at


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 scene(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV + nystagmus;
	float k = intensity;

	// 1. Flow-based UV distortion: three octaves of drifting noise push the picture around like liquid.
	if (flow > 0.001) {
		float t = time_s * 0.35;
		vec2 n1 = vec2(vnoise(uv * 2.0 + t * 0.7), vnoise(uv * 2.0 + t * 0.7 + 5.2)) * 2.0 - 1.0;
		vec2 n2 = vec2(vnoise(uv * 5.0 - t * 0.45 + 3.7), vnoise(uv * 5.0 - t * 0.45 + 9.1)) * 2.0 - 1.0;
		vec2 n3 = vec2(vnoise(uv * 11.0 + t * 0.22 + 7.3), vnoise(uv * 11.0 + t * 0.22 + 1.5)) * 2.0 - 1.0;
		uv += (n1 + n2 * 0.5 + n3 * 0.25) * 0.045 * flow * k;
	}

	// 2. Kaleidoscope: fold the picture into mirrored sectors that slowly turn.
	if (kaleido > 0.001) {
		vec2 p = (uv - 0.5) * 2.0;
		p.x *= aspect;
		float sectors = 6.0;
		float a = atan(p.y, p.x) + time_s * 0.12;
		float r = length(p);
		a = mod(a, 2.0 * PI / sectors);
		a = abs(a - PI / sectors);
		vec2 q = vec2(cos(a), sin(a)) * r;
		q.x /= aspect;
		uv = mix(uv, q * 0.5 + 0.5, kaleido * k);
	}

	// 3. Infinite tunnel: the picture wrapped onto the walls of a tunnel that you fall down.
	if (tunnel > 0.001) {
		vec2 p = uv - 0.5;
		p.x *= aspect;
		float r = max(length(p), 0.03);
		float a = atan(p.y, p.x);
		vec2 tuv = vec2(a / (2.0 * PI) + 0.5, fract(0.22 / r - time_s * 0.3));
		uv = mix(uv, tuv, clamp(tunnel * k, 0.0, 1.0) * 0.85);
	}

	// Chromatic aberration, pulled apart harder toward the edges and breathing slowly (the "fracture" mode).
	vec2 dir = uv - vec2(0.5);
	float edge = 0.35 + length(dir) * 2.2;
	float a_ab = aberration * k * 0.014 * edge * (0.8 + 0.45 * sin(time_s * 0.55));
	vec3 col = vec3(scene(uv + dir * a_ab).r, scene(uv).g, scene(uv - dir * a_ab).b);

	// 4. God rays: bright things (the orb) smear radially outward, like light scattering through fog.
	if (rays > 0.001) {
		vec2 d = (uv - rays_pos) / 20.0;
		vec2 s = uv;
		float acc = 0.0;
		float decay = 1.0;
		for (int i = 0; i < 20; i++) {
			s -= d;
			float l = max(dot(scene(s), vec3(0.299, 0.587, 0.114)) - 0.5, 0.0);
			acc += l * decay;
			decay *= 0.93;
		}
		col += vec3(1.0, 0.82, 0.55) * acc * 0.16 * rays * k;
	}

	// 5. Phosphene overlay: concentric rings crossed with spokes, breathing, strongest in the middle of the view.
	if (phos > 0.001) {
		vec2 q = SCREEN_UV - 0.5;
		q.x *= aspect;
		float r = length(q);
		float a = atan(q.y, q.x);
		float rings = sin(r * 38.0 - time_s * 9.0) * 0.5 + 0.5;          // slow enough to stay well under 3 per second
		float spokes = sin(a * 8.0 + time_s * 1.6) * 0.5 + 0.5;
		float breathe = fbm(SCREEN_UV * 3.5 + time_s * 0.25) * 0.7 + 0.35;
		float pattern = rings * spokes * breathe;
		pattern *= 1.0 - smoothstep(0.25, 0.85, r);
		col += vec3(0.75, 0.25, 1.0) * pow(pattern, 3.0) * 1.4 * phos * k;
	}

	float v = smoothstep(0.35, 0.95, length(SCREEN_UV - vec2(0.5)) * 1.4) * vignette * k;
	COLOR = vec4(col * (1.0 - 0.55 * v), 1.0);
}
