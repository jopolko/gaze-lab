
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D trail : filter_linear, repeat_disable;
uniform sampler2D cur : filter_linear, repeat_disable;     // the same picture as the trail is made of, this frame
uniform float mode = 0.0;        // 1 psychedelic, 2 digital, 3 synthwave
uniform float amount = 1.0;
uniform float use_trail = 1.0;     // 0 when the tracer pass is switched off to save frame rate
uniform float breathe = 0.0;     // 0..1 how hard the picture breathes
uniform float trip = 0.0;        // 0..1 the TRIP: built up by sugar and combos, it swirls the picture, throws the colours apart and fills the air with tracers
uniform float onset = 1.0;       // 0..1 how far the effect has come on: at first only a band around the horizon (the mountains) shimmers, then it spreads over the whole picture
uniform float horizon = 0.42;    // where the horizon is on the screen (0 top, 1 bottom)
uniform vec3 mA = vec3(0.0);     // how far each of six molecules is felt, 0..1: mescaline, DOM, 2C-B
uniform vec3 mB = vec3(0.0);     // 2C-E, 2C-T-2, 2C-T-7
uniform float dmt = 0.0;         // all six at the top at once
uniform float buzz = 0.0;        // 0..1 slow waves: bloom and colour swell and ease
uniform float k_warp = 1.0;     // 1 = the gentle warps of now; 5 = the original strength
uniform float k_fold = 0.0;     // the mirrored-segment fold (the mandala): 0 off
uniform float k_pulse = 1.0;    // 1 = the soft 2C-T-7 pulse of now; 4 = the original
uniform float k_rings = 0.0;    // rings of trip radiating from the middle: 0 off
uniform float k_dmtr = 0.0;     // the rings when all six are held: 0 off
uniform float face = 0.0;       // 0..1 a FACE emerges in the picture (rarely, for a few seconds): not drawn on it, but found in its light and shade
uniform float k_wash = 0.0;     // a colour wash over the WHOLE picture that turns with the trip (the tie-dye): 0 off. It covered everything in a soft rainbow, so it is off
uniform float k_edge = 0.0;      // CEL OUTLINES: ink lines where the picture changes (0 off)
uniform float rewind = 0.0;      // 0..1 a crash: the picture tears sideways and splits its colours while the board is put back, like tape run backwards
uniform float smear = 0.0;       // 0..1 BOOST SMEAR: the picture streaks outward from the middle while you are boosting (the middle stays clear to steer by)
uniform float edge_hue = 0.0;    // 0..1 the outline ink cycles through the rainbow instead of staying dark
uniform float k_cel = 0.0;       // CEL BANDS: light and shade in a few flat steps (0 off)
uniform float k_chroma = 1.0;   // the lab: how much each part of the picture pass counts (1 = as designed)
uniform float k_trace = 1.0;
uniform float k_punch = 1.0;
uniform float tube = 0.0;       // 0..1 inside a tube: colour rays and rings run out from the middle of the picture along its edges
uniform float sharp = 0.0;       // 0..1 rare: everything bright snaps crisp and hard, then softens

vec3 hsv(float h, float s, float v) {
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

float ell(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return 1.0 - smoothstep(0.88, 1.0, length(q));
}
// A WOMAN'S FACE, as light and shade only: the head a little lighter, the hair a lot darker, the eyes, brows and the shadow of the nose dark, the lips warm. Returns x = shade, y = lips.
vec2 woman(vec2 p) {
	float head = ell(p, vec2(0.0, 0.0), vec2(0.50, 0.70));
	float hair_o = ell(p, vec2(0.0, 0.08), vec2(0.74, 0.92));
	float hair_fall = (1.0 - smoothstep(0.60, 0.70, abs(p.x))) * step(abs(p.x), 0.74) * step(-1.5, p.y) * step(p.y, 0.1);
	float hair = clamp(max(hair_o, hair_fall * smoothstep(0.42, 0.52, abs(p.x))) - head, 0.0, 1.0);
	float eyes = max(ell(p, vec2(-0.21, 0.14), vec2(0.115, 0.045)), ell(p, vec2(0.21, 0.14), vec2(0.115, 0.045)));
	float brows = max(ell(p, vec2(-0.21, 0.27), vec2(0.15, 0.02)), ell(p, vec2(0.21, 0.27), vec2(0.15, 0.02)));
	float nose = ell(p, vec2(0.035, -0.06), vec2(0.03, 0.15)) * 0.7 + ell(p, vec2(0.0, -0.2), vec2(0.07, 0.03)) * 0.6;
	float lips = ell(p, vec2(0.0, -0.40), vec2(0.15, 0.055));
	float cheeks = max(ell(p, vec2(-0.27, -0.12), vec2(0.13, 0.09)), ell(p, vec2(0.27, -0.12), vec2(0.13, 0.09)));
	float shade = 0.14 * head - 0.34 * hair - 0.55 * eyes - 0.32 * brows - 0.28 * nose + 0.10 * cheeks - 0.10 * lips;
	return vec2(shade, lips);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);
	vec3 col;
	if (mode < 0.5) {
		col = texture(screen_tex, uv).rgb;
	} else if (mode < 1.5) {
		// psychedelic: a gentle breathing warp, chromatic split that grows toward the edges, tracers
		float w = sin(TIME * 0.7 + r * 9.0) * 0.0012 * k_warp * amount * breathe;
		float tw = trip * trip;
		float ang = 0.0;          // no swirl: the heavy swirling was too much
		vec2 cw = vec2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
		vec2 wuv = vec2(0.5) + cw + c * w * 2.0 + vec2(sin(uv.y * 14.0 + TIME) * 0.0008, 0.0) * amount * breathe;
		// the six, each in its own way. Everything is eased down in the middle of the picture and round the board, so it stays playable.
		float keep = mix(0.35, 1.0, smoothstep(0.05, 0.38, length(c * vec2(1.0, 1.25))));
		float pl = pow(max(sin(TIME * 6.0), 0.0), 3.0);
		wuv += c * (mA.x * 0.002 * k_warp * keep * sin(TIME * 0.5 + r * 6.0));          // mescaline: slow warm waves
		wuv += c * (mB.y * 0.0015 * k_warp * keep * sin(r * 34.0 - TIME * 3.0));          // 2C-T-2: ripples running out from the middle
		if (k_fold > 0.001 && mB.x + dmt > 0.01) {          // 2C-E: the picture folds into mirrored segments
			// (only out toward the edges, and never most of the picture: folded all the way in, the ground stopped reading as ground and the feeling of speed went)
			float kf = clamp(mB.x * 0.22 + dmt * 0.4, 0.0, 0.55) * smoothstep(0.24, 0.5, r) * k_fold;
			float seg = 6.2831853 / (6.0 + 2.0 * dmt);
			float an = atan(c.y, c.x);
			float af = abs(mod(an, seg) - seg * 0.5);
			wuv = mix(wuv, vec2(0.5) + vec2(cos(af), sin(af)) * r, kf);
		}
		wuv = vec2(0.5) + (wuv - vec2(0.5)) * (1.0 - 0.006 * k_pulse * mB.z * pl * keep + 0.006 * k_pulse * dmt * sin(TIME * 0.8) * keep);          // 2C-T-7: a pulse that pushes in
		float ca = (0.003 + r * 0.012) * amount * k_chroma * (1.0 + trip * 0.5 + mA.z * 0.5 + dmt * 0.6);          // 2C-B: the colours split apart
		col = vec3(texture(screen_tex, wuv + c * ca).r, texture(screen_tex, wuv).g, texture(screen_tex, wuv - c * ca).b);
		vec3 old = texture(trail, uv).rgb;
		vec3 diff = max(old - texture(cur, uv).rgb * 0.92 - 0.02, vec3(0.0));
		float m = clamp(dot(diff, vec3(0.34)) * 3.2 * (1.0 + trip * 1.0) * (0.4 + 0.6 * smoothstep(0.1, 0.45, r)) + trip * 0.06 * k_rings * (0.5 + 0.5 * sin(r * 22.0 - TIME * 2.5)), 0.0, 1.0);
		vec3 ghost = hsv(fract(TIME * 0.12 + r * 0.9 + m * 0.5), 0.95, 1.0) * m;
		col += ghost * 0.45 * amount * use_trail * k_trace;          // (added light washes a picture out: less of it, and the colour is pushed instead, below)
		col = mix(col, col * hsv(fract(TIME * 0.05), 0.25, 1.1), 0.12 * amount);
		col = mix(col, col * hsv(fract(TIME * 0.14 + r * 1.2), 0.7, 1.3), tw * 0.55 * k_wash);
		col *= 1.0 + trip * 0.08;
		col *= 1.0 - 0.45 * smoothstep(0.45, 0.95, r);
		col = mix(col, col * vec3(1.15, 0.95, 0.78), mA.x * 0.5);          // mescaline: warm
		col *= 1.0 + mA.y * 0.12 * sin(TIME * 0.35);          // DOM: a slow deep swell of light
		col *= 1.0 + mB.z * 0.30 * pl * keep;          // 2C-T-7: the pulse is bright too
		// punch: richer colour and deeper darks, so the effect is vivid and not pale
		float lm = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(lm), col, 1.0 + (0.45 + 0.6 * trip + 0.8 * mA.z + 0.5 * dmt) * k_punch);          // 2C-B: vivid (a bit more: the colour is the point)
		col += max(col - 0.55, vec3(0.0)) * (0.30 + 0.25 * buzz + 1.0 * sharp) * amount;
		col = max((col - 0.5) * (1.0 + 0.3 * sharp) + 0.5, vec3(0.0));          // sharpening is crisp contrast too
		col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 1.0 + 0.4 * sharp);          // the bright things (glows, moire, trees) bloom a little harder
		col = max((col - 0.5) * (1.14 + 0.2 * trip + 0.2 * mA.y) + 0.5 - 0.05, vec3(0.0));          // DOM: deeper
		if (dmt > 0.001) {          // all six: the colours cycle through everything and rings run outward
			col = mix(col, col * hsv(fract(TIME * 0.2 + r * 2.0), 0.8, 1.4), dmt * 0.6 * keep * k_wash);
			col += hsv(fract(r * 8.0 - TIME * 0.6), 0.9, 1.0) * 0.18 * k_dmtr * dmt * (0.5 + 0.5 * sin(r * 40.0 - TIME * 4.0)) * keep;
		}
		if (tube > 0.001) {          // an enclosed tube: rays and rings streaming past at the edges (the middle stays clear, so the path is never hidden)
			float ta = atan(c.y, c.x);
			float rays = 0.5 + 0.5 * sin(ta * 18.0 + sin(TIME * 1.7) * 3.0 + r * 8.0 - TIME * 12.0);
			float rng = 0.5 + 0.5 * sin(r * 34.0 - TIME * 20.0);
			vec3 rc2 = hsv(fract(TIME * 0.35 + r * 1.4 + ta * 0.16), 0.9, 1.0);
			float edge = smoothstep(0.16, 0.62, r);
			col = mix(col, col * (1.0 + 0.5 * rng * edge) + rc2 * rays * 0.55 * edge, tube * 0.9);
		}
		// soft shoulder: light added by the effects is folded back instead of clipping to white, so bright areas keep their colour (this is what made it pale and washed out)
		float mxc = max(max(col.r, col.g), col.b);
		if (mxc > 0.75) {
			float tm = 0.75 + 0.25 * (1.0 - exp(-(mxc - 0.75) * 2.5));
			col *= tm / mxc;
		}
		col *= 0.92;
		if (onset < 0.999) {
			vec3 plain = texture(screen_tex, uv).rgb;
			float dh = abs(uv.y - horizon);
			float wm = clamp(onset * 2.6 - dh * 2.6, 0.0, 1.0);
			float fl = 0.6 + 0.4 * sin(TIME * 11.0 + uv.x * 7.0 + sin(TIME * 3.0) * 2.0);          // it flickers while it is only partly there
			wm *= mix(fl, 1.0, onset);
			float amt = onset * onset * (3.0 - 2.0 * onset);          // and how strong it is where it reaches grows too: a hint is only a hint
			col = mix(plain, col, wm * amt);
		}
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
	if (face > 0.001) {          // THE FACE: found in the picture's own light and shade. It sits high, over the mountains and sky, and leaves the road alone.
		float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 fp = (uv - vec2(0.5, 0.30)) * vec2(asp, 1.0) / 0.36;
		fp.y = -fp.y;
		vec2 fs = woman(fp);
		float lumf = dot(col, vec3(0.299, 0.587, 0.114));
		float fk = face * (0.6 + 0.4 * smoothstep(0.1, 0.6, lumf)) * (1.0 - smoothstep(0.55, 0.75, uv.y));
		col *= 1.0 + fs.x * fk * 1.6;
		col = mix(col, vec3(1.0, 0.35, 0.5) * (0.4 + lumf), fs.y * fk * 0.5);
	}
	if (rewind > 0.01) {
		float rt = sin(uv.y * 70.0 + TIME * 45.0) * 0.012 * rewind;
		vec2 ru = uv + vec2(rt, 0.0);
		float rs2 = rewind * 0.03;
		col = vec3(texture(screen_tex, ru + c * rs2).r, texture(screen_tex, ru).g, texture(screen_tex, ru - c * rs2).b);
		col = mix(col, vec3(dot(col, vec3(0.333))), rewind * 0.35);
	}
	if (smear > 0.002) {
		vec3 acc = col;
		for (int si = 1; si < 6; si++) {
			acc += texture(screen_tex, uv - c * smear * 0.09 * (float(si) / 6.0)).rgb;
		}
		col = mix(col, acc / 6.0, clamp(smear * 0.9, 0.0, 0.85) * smoothstep(0.08, 0.4, r));
	}
	if (k_edge > 0.001) {          // outlines: a Sobel over the UNtouched picture (so the lines are as sharp as the geometry, not smeared by the other effects), drawn as dark ink
		vec2 px = SCREEN_PIXEL_SIZE * 1.4;
		vec3 t00 = texture(screen_tex, uv + px * vec2(-1.0, -1.0)).rgb;
		vec3 t10 = texture(screen_tex, uv + px * vec2(0.0, -1.0)).rgb;
		vec3 t20 = texture(screen_tex, uv + px * vec2(1.0, -1.0)).rgb;
		vec3 t01 = texture(screen_tex, uv + px * vec2(-1.0, 0.0)).rgb;
		vec3 t21 = texture(screen_tex, uv + px * vec2(1.0, 0.0)).rgb;
		vec3 t02 = texture(screen_tex, uv + px * vec2(-1.0, 1.0)).rgb;
		vec3 t12 = texture(screen_tex, uv + px * vec2(0.0, 1.0)).rgb;
		vec3 t22 = texture(screen_tex, uv + px * vec2(1.0, 1.0)).rgb;
		vec3 gxv = (t20 + 2.0 * t21 + t22) - (t00 + 2.0 * t01 + t02);
		vec3 gyv = (t02 + 2.0 * t12 + t22) - (t00 + 2.0 * t10 + t20);
		float eg = length(vec3(length(vec2(gxv.r, gyv.r)), length(vec2(gxv.g, gyv.g)), length(vec2(gxv.b, gyv.b))));
		float line = smoothstep(0.30, 0.85, eg);
		vec3 ink = mix(vec3(0.02, 0.0, 0.09), hsv(fract(TIME * 0.12 + uv.x * 0.35 + uv.y * 0.2), 0.9, 1.0), edge_hue);
		col = mix(col, ink, clamp(line * k_edge, 0.0, 0.92));
	}
	if (k_cel > 0.001) {          // bands: the light is stepped, so surfaces read as flat shapes with crisp edges between them
		float lc = dot(col, vec3(0.299, 0.587, 0.114));
		float bands = 5.0;
		float lq = (floor(lc * bands) + smoothstep(0.35, 0.65, fract(lc * bands))) / bands;
		col *= mix(1.0, lq / max(lc, 0.02), clamp(k_cel, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
