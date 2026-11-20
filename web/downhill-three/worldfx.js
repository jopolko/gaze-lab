// WORLDFX: the Godot "All dressed" world, ported from the code (not from pictures), as plug-in materials, patches and a per-frame driver for gv.js.
//
// WHAT THE GODOT JOURNEY REALLY DOES (the reason this module exists): in journey mode the world is plain ALPINE (snow, dark pine, a blue sky) and the psychedelic world comes ON in pieces, in this order
// during an onset (psyfx.js journeyStage windows): the sky and light first, then the ground, then the trees, then the rest. The pieces are ThemeFX.apply_part (ThemeFX.gd 113-175):
//   "sky" / "skymat": the environment blends alpine -> the theme's env (ThemeFX.blend_env, 178-205), the sky material is swapped, the mountains and mist recoloured
//   "ground": ONE ground for every world, DownhillRig.GROUND_SHADER (DownhillRig.gd 1853-1990) stays; only its palette changes (w_a, w_b, w_line, w_mix from Themes.ground_pal)
//   "veg": the trees take the world's shader (Themes.VEG_PSY) instead of the alpine tree
//   "light": the rider's lights, snow and sandstorm clock
// and, driven every frame by the dose (RunRig._stage_tick 7113-7160, _moire_tick 7068-7110, _wander_tick 6504-6545, _sky_dome_tick 6420-6455): the ground's moire knobs, the tree sway / breathing / moire, the sky bands, the
// sky dome (polar and tunnel fields, DOM and 2C-T-7), the mountain moire / breathing / polar skin (2C-E). psyfx.js already computes all of those numbers (PSY.world()); this module turns them into pixels.
//
// SOURCE MAP (godot/scripts):
//   ground shader ............. DownhillRig.gd 1853-1990 (GROUND_SHADER), palette Themes.gd 693-709
//   horizon bend (all shaders) ... DownhillRig.gd 1839-1845 / 1858-1896, RunRig.gd 6085, driver RunRig._bend_tick (6996-7010): bend_k = 0.00012 * w_bend * (0.4 + 0.6 * speed01), starts 140 m out
//   live trees (alpine, sway) ..... RunRig.gd 6019-6103 (VEG_LIVE_SHADER), driver RunRig 7122-7123
//   themed trees .................. Themes.gd 270-285 (VEG_PSY)
//   alpine / theme environment ..... LevelBuilder.gd 123-136 (_downhill), Themes.gd 11-60, MainLevel.gd 218-250 (_apply_environment)
//   sky bands quad ................ RunRig.gd 6005-6016 (SKY_SHADER), placement 7164-7178
//   sky dome ...................... RunRig.gd 6385-6414 (SKYDOME_SHADER), driver 6420-6455
//   mountain skin ................. RunRig.gd 6450-6490 (MTNFX_SHADER), driver 6504-6545
//   tree mesh ..................... DownhillRig.gd 1993-2040 (_make_tree_mesh): three 6-sided tiers, radii 1.95/1.55/1.1, heights 2.8/2.5/2.3, green skirts, snow caps; the dump already holds this mesh (same function), so no new builder is needed
//
// HOW gv.js USES IT (full list at the bottom of this file):
//   const WFX = createWorldFx({ THREE, scene, camera, U, light: sunLight, hemi: ambient });
//   ground.material  = WFX.ground();               // instead of the GROUND_PSY port (needs vertexColors geometry, which the dump has)
//   treeMesh.material = WFX.vegLive();             // alpine trees (sway, breathing, moire); WFX.setStage('veg', true) swaps instanced trees to the themed material you already have
//   WFX.tick(dt, clock.t, PSY.world(), { speed01, alt01, tube, rail, sharp, travZ, camera });   // every frame, after PSY.tick
//   WFX.onStage(part, on)  <- PSY's onStage callback;  WFX.onSky(k) <- PSY's onSky callback (the env blend)

import { createWorldFx2, S2L_GLSL, FACE_UNIFORMS, FACE_FUNCS, FACE_TREE, GODOT_FOG_LIT, srgbToLinear } from './worldfx2.js';
export { srgbToLinear, S2L_GLSL };

export const ALPINE = {          // LevelBuilder._downhill (the plain world the journey starts in)
  sky_top: [0.18, 0.42, 0.9], sky_horizon: [0.98, 0.84, 0.72], sky_ground: [0.8, 0.85, 0.95], fog: [0.78, 0.82, 0.95], fog_density: 0.0012, fog_sky: 0.05,
  ambient: 0.62, ambient_color: [0.66, 0.75, 0.97], exposure: 1.05, sun_color: [1.0, 0.88, 0.72], sun_energy: 1.9, sun_rot: [-26, 205, 0], sun_disc: 38, sun_curve: 0.1, glow: 0.3, saturation: 1.1, contrast: 1.08,
};
export const PSYCHEDELIC = {          // Themes.DATA["psychedelic"].env laid over the alpine values (a key the theme does not set stays alpine)
  sky_top: [0.08, 0.0, 0.2], sky_horizon: [0.6, 0.1, 0.7], sky_ground: [0.05, 0.0, 0.12], ambient: 0.9, fog_density: 0.0016, fog: [0.35, 0.05, 0.45], sun_color: [1.0, 0.7, 1.0], sun_energy: 0.7, sun_rot: [-35, -30, 0], fog_sky: 0.0, glow: 0.35, saturation: 1.15, contrast: 1.1,
};
export const GROUND_PAL = { psychedelic: { a: [0.30, 0.08, 0.55], b: [0.95, 0.50, 1.0], line: [1.0, 0.9, 0.3], mix: 0.85 } };          // Themes.ground_pal

const HSV_GLSL = 'vec3 hsv2rgb(vec3 c) { vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0); return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y); }';
const NL = String.fromCharCode(10);

export function createWorldFx(o) {
  const { THREE, scene, camera, U } = o;
  const V2 = THREE.Vector2, V3 = THREE.Vector3;
  const shared = { uTime: U && U.uTime ? U.uTime : { value: 0 }, bendK: { value: 0 }, fogColor: U && U.fogColor, fogDensity: U && U.fogDensity };          // one uniform each shader reads: gv.js's own clock, and the horizon bend
  const G = {};          // (filled below; worldfx2 needs the objects to exist)
  const MT = {};
  const F2 = createWorldFx2({ THREE, scene, camera, shared, G, MT });
  // ---------------------------------------------------------------- the ground (DownhillRig.GROUND_SHADER)
  Object.assign(G, {
    grid: { value: 0 }, gglow: { value: 0 }, gcen: { value: new V2() }, m_tri: { value: 0 }, m_rad: { value: 0 }, m_warp: { value: 0 }, m_drift: { value: new V2() }, m_rc: { value: new V2() },
    w_a: { value: new V3(1, 1, 1) }, w_b: { value: new V3(1, 1, 1) }, w_line: { value: new V3(1, 1, 1) }, w_mix: { value: 0 }, k_sq: { value: 1 }, k_edge: { value: 1 }, k_apron: { value: 1 },
    m_cell: { value: 6 }, m_ang: { value: 0 }, m_ratio: { value: 1.037 }, m_depth: { value: 0.12 }, m_sat: { value: 0 }, m_hue: { value: 0 }, detail: { value: 1 },
    path_on: { value: 0 }, path_half: { value: 13 }, vc_lin: { value: 0 },
  });
  const GROUND_UNIFORMS = 'uniform float grid, gglow, m_tri, m_rad, m_warp, w_mix, k_sq, k_edge, k_apron, m_cell, m_ang, m_ratio, m_depth, m_sat, m_hue, detail, path_on, path_half, vc_lin; uniform vec2 gcen, m_drift, m_rc; uniform vec3 w_a, w_b, w_line;';
  const GROUND_FRAG = `
    float dist = length(vViewPosition);
    float near = 1.0 - smoothstep(30.0, 120.0, dist);
    float big = vn(wpg.xz * 0.11);
    float drift = vn(vec2(wpg.x * 0.5, wpg.z * 0.09));
    float fine = 0.5;
    if (near > 0.01 && detail > 0.5) fine = vn(wpg.xz * 3.5) * near + vn(wpg.xz * 15.0) * 0.5 * near;
    vec3 base = vc_lin > 0.5 ? l2s(vColor.rgb) : vColor.rgb;
    vec3 shade = base * vec3(0.84, 0.89, 0.99);
    float patchk = smoothstep(0.12, 0.45, big * 0.65 + drift * 0.45);
    vec3 gc = mix(shade, base, patchk);
    gc *= 0.93 + 0.10 * fine;
    float tw = h21(floor(wpg.xz * 26.0));
    float sp = step(0.9985, tw) * near * (0.55 + 0.45 * sin(uTime * 3.0 + tw * 60.0));
    vec3 gEmi = vec3(sp) * 0.8;
    float al = abs((0.5 - 0.5) * 60.0);
    float onp = path_on * (1.0 - smoothstep(path_half - 0.3, path_half + 0.3, al));
    float edge = path_on * (1.0 - smoothstep(0.35, 1.1, abs(al - path_half))) * (1.0 - smoothstep(160.0, 340.0, dist));
    float apron = path_on * smoothstep(path_half, path_half + 0.3, al) * (1.0 - smoothstep(path_half + 0.3, path_half + 9.0, al));
    vec2 g1 = wpg.xz / 6.0;
    float gr1 = sin(g1.x * 6.283) * sin(g1.y * 6.283);
    float sw = fwidth(gr1) * 1.1 + 0.002;
    float sq0 = smoothstep(-sw, sw, gr1);
    vec2 g24 = wpg.xz / 24.0;
    float gr24 = sin(g24.x * 6.283) * sin(g24.y * 6.283);
    float sw24 = fwidth(gr24) * 1.1 + 0.002;
    vec2 g96 = wpg.xz / 96.0;
    float gr96 = sin(g96.x * 6.283) * sin(g96.y * 6.283);
    float sw96 = fwidth(gr96) * 1.1 + 0.002;
    float fw1 = smoothstep(80.0, 200.0, dist);
    float fw2 = smoothstep(300.0, 700.0, dist);
    float sq = mix(mix(sq0, smoothstep(-sw24, sw24, gr24), fw1), smoothstep(-sw96, sw96, gr96), fw2);
    vec2 wq = wpg.xz + m_warp * 5.0 * vec2(sin(wpg.z * 0.06 + uTime * 0.7), cos(wpg.x * 0.05 - uTime * 0.5));
    vec2 g2 = (vec2(wq.x * 0.99939 - wq.y * 0.03499, wq.x * 0.03499 + wq.y * 0.99939) * m_ratio + m_drift) / m_cell;
    float gr2 = sin(g2.x * 6.283) * sin(g2.y * 6.283);
    vec2 g3 = (vec2(wq.x * 0.99820 + wq.y * 0.05996, -wq.x * 0.05996 + wq.y * 0.99820) * (m_ratio * 1.021) + m_drift * vec2(-0.7, 0.9)) / m_cell;
    float gr3 = sin(g3.x * 6.283) * sin(g3.y * 6.283);
    float grr = sin(length(wpg.xz - m_rc) / m_cell * 6.283 - uTime * 2.0);
    if (grid > 0.001) {
      float ga = grid * (1.0 - smoothstep(90.0, 260.0, dist));
      float mmx = gr1 * mix(gr2, grr, m_rad) * mix(1.0, gr3, m_tri);
      float mm = smoothstep(-0.5, 0.5, mmx);
      float sqk = grid * (1.0 - smoothstep(1800.0, 3200.0, dist));
      gc *= mix(1.0, mix(1.0 - (0.26 - 0.10 * fw2) * k_sq, 1.0, sq), sqk * (0.55 + 0.45 * onp));
      gc *= mix(1.0, (1.0 - m_depth * 0.6) + m_depth * 0.6 * mm, ga * (1.0 - onp));
      if (m_sat > 0.01) {
        vec3 hc = clamp(abs(fract(vec3(mm * 0.5 + m_hue) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        vec3 mc = mix(vec3(1.0), hc, m_sat) * (0.35 + 0.65 * pow(mm, 0.65));
        float ck = ga * m_sat * (0.55 - 0.45 * onp);
        gc = mix(gc, mc, ck);
        gEmi += mc * ck * 0.22;
      }
    }
    if (w_mix > 0.001) {
      vec2 fl = abs(fract(g1) - 0.5);
      float lw = 0.035 + 0.0014 * dist;
      float ln = max(smoothstep(0.5 - lw, 0.5, fl.x), smoothstep(0.5 - lw, 0.5, fl.y));
      vec3 wc = mix(w_b, w_a, sq);
      wc = mix(wc, w_line, ln * 0.9 * (1.0 - smoothstep(60.0, 300.0, dist)));
      gc = mix(gc, wc * wc, w_mix);
      gEmi += w_line * ln * 0.25 * w_mix;
    }
    gc = mix(gc, gc * 0.4, clamp(apron * 0.9 * k_apron, 0.0, 1.0));
    gc = mix(gc, vec3(0.92, 1.0, 1.0), clamp(edge * k_edge, 0.0, 1.0));
    gEmi += vec3(0.15, 0.95, 1.0) * edge * 1.6 * k_edge;
    diffuseColor.rgb = s2l(gc);`;          // (mixed in authored space, converted once: Godot's ALBEDO rule, see worldfx2.js)
  const GLSL_NOISE = 'float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }' + NL + 'float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y); }';
  // the vertex half every world shader shares: the world position (varying) and the HORIZON BEND (past 140 m the world curls up with the square of the distance)
  const PROJECT_BEND = (v) => `
    vec4 wv_ = vec4(transformed, 1.0);
    #ifdef USE_INSTANCING
    wv_ = instanceMatrix * wv_;
    #endif
    wv_ = modelMatrix * wv_;
    ${v} = wv_.xyz;
    float bd_ = max(length(wv_.xz - cameraPosition.xz) - 140.0, 0.0);
    wv_.y += bendK * bd_ * bd_;
    vec4 mvPosition = viewMatrix * wv_;
    gl_Position = projectionMatrix * mvPosition;`;
  function ground() {
    const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0, side: THREE.DoubleSide, fog: false });
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, G, { uTime: shared.uTime, bendK: shared.bendK }, F2.fogU());
      sh.vertexShader = 'varying vec3 wpg; uniform float bendK;' + NL + sh.vertexShader.replace('#include <project_vertex>', PROJECT_BEND('wpg'));
      sh.fragmentShader = 'varying vec3 wpg; uniform float uTime; uniform vec3 gFogColor; uniform float gFogDensity;' + NL + GROUND_UNIFORMS + NL + S2L_GLSL + NL + GLSL_NOISE + NL + sh.fragmentShader
        .replace('#include <color_fragment>', GROUND_FRAG)
        .replace('#include <fog_fragment>', GODOT_FOG_LIT)
        .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>' + NL + 'totalEmissiveRadiance += gEmi;');
    };
    m.customProgramCacheKey = () => 'worldfx-ground';
    return m;
  }
  // ---------------------------------------------------------------- the live trees (RunRig.VEG_LIVE_SHADER): alpine pines that sway, breathe and (2C-B) take a moire skin
  G.vc_lin = F2.VC.vc_lin;          // one flag for every material of the module: set WFX.uniforms.vcLin.value = 1 if the geometry's colours were converted to linear on load
  const T = { wob: { value: 0 }, breathe: { value: 0 }, mo_k: { value: 0 }, mo_t: { value: new V2() } };
  // RunRig.VEG_LIVE_SHADER (6019-6112): lit (roughness 1, specular 0) vertex-coloured trees / rocks, with breathing + sway in the vertex stage, the 2C-B moire skin and the portrait ink in the fragment stage.
  // Everything is mixed in authored space and converted once (s2l). Works on InstancedMesh (instanceMatrix) and plain meshes.
  function vegLive() {
    const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0, side: THREE.DoubleSide, fog: false });
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, T, F2.F, F2.VC, { uTime: shared.uTime, bendK: shared.bendK }, F2.fogU());
      sh.vertexShader = 'varying vec3 wpv; uniform float uTime, bendK, wob, breathe;' + NL + sh.vertexShader
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          { mat4 M_ = modelMatrix;
          #ifdef USE_INSTANCING
          M_ = modelMatrix * instanceMatrix;
          #endif
          vec3 ob = (M_ * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
          if (breathe > 0.001) { float bw = sin(uTime * 1.1 + ob.x * 0.045 + ob.z * 0.035) + 0.5 * sin(uTime * 1.9 - ob.z * 0.08); transformed.y *= 1.0 + bw * breathe * 0.22; transformed.xz *= 1.0 + bw * breathe * 0.10; }
          if (wob > 0.001) { float ph = ob.x * 0.21 + ob.z * 0.17; float hgt = max(transformed.y, 0.0);
            transformed.x += sin(uTime * 1.7 + ph) * wob * 0.2 * hgt; transformed.z += cos(uTime * 1.3 + ph * 1.3) * wob * 0.14 * hgt; transformed.y *= 1.0 + sin(uTime * 2.1 + ph) * wob * 0.07; } }`)
        .replace('#include <project_vertex>', PROJECT_BEND('wpv'));
      sh.fragmentShader = 'varying vec3 wpv; uniform float mo_k, face_k, face_az, vc_lin, gFogDensity; uniform vec2 mo_t; uniform vec3 face_o, gFogColor;' + NL + FACE_UNIFORMS + NL + S2L_GLSL + NL + FACE_FUNCS + NL + FACE_TREE + NL + sh.fragmentShader
        .replace('#include <color_fragment>', `
          vec3 au_ = vc_lin > 0.5 ? l2s(vColor.rgb) : vColor.rgb;
          vec3 gEmiL = vec3(0.0);
          if (mo_k > 0.001) { vec2 q = (wpv.xz + wpv.y * 1.3) * 2.2; float s1 = sin(q.x) * sin(q.y); float s2 = sin(q.x * 1.037 + mo_t.x) * sin(q.y * 1.037 + mo_t.y); float mm = smoothstep(-0.5, 0.5, s1 * s2);
            vec3 hc = clamp(abs(fract(vec3(mm * 0.5 + mo_t.x * 0.05) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
            au_ = mix(au_, hc * (0.4 + 0.6 * mm), clamp(mo_k, 0.0, 1.0) * 0.65); gEmiL = hc * mm * mo_k * 0.55; }
          if (face_k > 0.001) { vec4 fi_ = face_on_tree(wpv, face_o, face_az); au_ = mix(au_, fi_.rgb, fi_.a * face_k); gEmiL += fi_.rgb * fi_.a * face_k * 0.25; }
          diffuseColor.rgb = s2l(au_);`)
        .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>' + NL + 'totalEmissiveRadiance += gEmiL;')
        .replace('#include <fog_fragment>', GODOT_FOG_LIT);
    };
    m.customProgramCacheKey = () => 'worldfx-veg2';
    return m;
  }
  // ---------------------------------------------------------------- the alpine sky (a procedural gradient + sun), for the journey's start; the psychedelic sky is gv.js's SKY_PSY port
  const SKYU = { sTop: { value: new V3() }, sHor: { value: new V3() }, sGnd: { value: new V3() }, sunDir: { value: new V3(0, 1, 0) }, sunCol: { value: new V3(1, 1, 1) }, sunDisc: { value: 38 }, sunCurve: { value: 0.1 } };
  function skyAlpine() {          // Godot's ProceduralSkyMaterial: sky = mix(horizon, top, 1 - pow(1 - c, 1/curve)) above the horizon (c = 1 - angle/(pi/2)), the ground the same below, plus the sun disc (written from the engine's sky.glsl, not from the project sources)
    return new THREE.ShaderMaterial({ uniforms: SKYU, side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: 'varying vec3 vD; void main(){ vD = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p.xyww; }',
      fragmentShader: `uniform vec3 sTop, sHor, sGnd, sunDir, sunCol; uniform float sunDisc, sunCurve; varying vec3 vD; void main(){ vec3 d = normalize(vD); float c = 1.0 - acos(clamp(d.y, -1.0, 1.0)) / 1.5708;
        vec3 sky = mix(sHor, sTop, clamp(1.0 - pow(1.0 - max(c, 0.0), 1.0 / 0.15), 0.0, 1.0)); vec3 gr = mix(sHor, sGnd, clamp(1.0 - pow(1.0 + min(c, 0.0), 1.0 / 0.02), 0.0, 1.0)); vec3 col = c >= 0.0 ? sky : gr;
        float ang = acos(clamp(dot(d, normalize(sunDir)), -1.0, 1.0)) * 57.2958; float disc = clamp(1.0 - ang / max(sunDisc, 1.0), 0.0, 1.0); col += sunCol * pow(disc, 1.0 / max(sunCurve, 0.02)) * 1.2; gl_FragColor = vec4(col, 1.0); }` });
  }
  // ---------------------------------------------------------------- the sky bands quad (RunRig.SKY_SHADER), the dome (SKYDOME_SHADER) and the mountain skin (MTNFX_SHADER)
  const SF = { k: { value: 0 } }, SD = { polar: { value: 0 }, tun: { value: 0 }, spd: { value: 0 } }; Object.assign(MT, { mo_k: { value: 0 }, br_k: { value: 0 }, pol_k: { value: 0 }, mo_t: { value: new V2() }, trav: { value: 0 }, cam_pos: { value: new V3() } });
  const skyFxMat = new THREE.ShaderMaterial({ uniforms: Object.assign({ uTime: shared.uTime }, SF), transparent: true, depthWrite: false, depthTest: true, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: `varying vec2 vUv; uniform float uTime, k; ${S2L_GLSL}
 void main(){ vec2 u = vUv; float edge = smoothstep(0.0, 0.18, u.x) * smoothstep(1.0, 0.82, u.x) * smoothstep(0.0, 0.25, u.y) * smoothstep(1.0, 0.45, u.y);
      float band = sin(u.x * 9.0 + sin(u.y * 5.0 + uTime * 0.6) * 1.5 + uTime * 0.4); float cur = smoothstep(0.15, 1.0, band); vec3 c = 0.5 + 0.5 * cos(6.2831 * (u.x * 0.8 + u.y * 0.4 + uTime * 0.07 + vec3(0.0, 0.33, 0.67)));
      gl_FragColor = vec4(s2l(c) * cur * 0.5 * edge * k, 1.0); }` });
  const skyDomeMat = new THREE.ShaderMaterial({ uniforms: Object.assign({ uTime: shared.uTime }, SD), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.BackSide, fog: false,
    vertexShader: 'varying vec3 dir; void main(){ dir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p; }',
    fragmentShader: `varying vec3 dir; uniform float uTime, polar, tun, spd; ${S2L_GLSL}
 void main(){ vec3 d = normalize(dir); float up = d.y; float r = acos(clamp(up, -1.0, 1.0)); float a = atan(d.x, d.z); float over = smoothstep(0.08, 0.55, up);
      float rad = sin(r * 18.0 - uTime * 1.2); float ang = sin(a * 14.0 + uTime * 0.5); float dia = sin((r * 12.6 + a * 7.0) * 1.2 + uTime * 0.7); float f = (rad + ang + dia) / 3.0;
      vec3 pc = 0.5 + 0.5 * cos(6.2831 * (vec3(f * 0.45 + uTime * 0.04) + vec3(0.0, 0.33, 0.67))); float pa = polar * over * (0.25 + 0.75 * smoothstep(-0.1, 0.9, f));
      float depth = 0.4 / max(r, 0.04); float ph = fract(depth - uTime * (0.18 + 0.4 * spd)); float band = smoothstep(0.0, 0.15, ph) * smoothstep(0.7, 0.45, ph); float sec = 0.5 + 0.5 * sin(a * 11.0);
      vec3 tc = 0.5 + 0.5 * cos(6.2831 * (vec3(depth * 0.12 + uTime * 0.06 + sec * 0.2) + vec3(0.0, 0.33, 0.67))); float ta = tun * over * band * (0.35 + 0.65 * sec) * smoothstep(0.0, 0.25, r);
      gl_FragColor = vec4(s2l(pc * pa + tc * ta) * 0.6, 1.0); }` });
  const mtnFxMat = new THREE.ShaderMaterial({ uniforms: Object.assign({ uTime: shared.uTime }, MT), transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false,
    vertexShader: 'varying vec3 lp; varying vec3 wpm; void main(){ lp = position; vec4 w = modelMatrix * vec4(position, 1.0); wpm = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: `varying vec3 lp; varying vec3 wpm; uniform float uTime, mo_k, br_k, pol_k, trav; uniform vec2 mo_t; uniform vec3 cam_pos; ${S2L_GLSL}
 void main(){
      float dist = length(wpm - cam_pos); vec2 q = (lp.xz + lp.y * 1.2) * 0.157; q += vec2(0.0, trav * 0.012); float fine = 1.0 + 0.9 * smoothstep(300.0, 1500.0, dist);
      float s1 = sin(q.x * fine) * sin(q.y * fine); float s2 = sin(q.x * fine * 1.037 + mo_t.x * 0.3) * sin(q.y * fine * 1.037 + mo_t.y * 0.3); float mm = smoothstep(-0.5, 0.5, s1 * s2);
      vec3 hc = clamp(abs(fract(vec3(mm * 0.5 + uTime * 0.04 + lp.y * 0.0008) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
      float band = 0.5 + 0.5 * sin(lp.y * 0.085 - uTime * 1.1 + trav * 0.015); band = smoothstep(0.55, 0.95, band);
      vec3 bc = clamp(abs(fract(vec3(lp.y * 0.0015 + uTime * 0.06) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
      float pf = 0.5 + 0.5 * sin(length(lp.xz) * 0.02 - uTime * 1.1) * sin(atan(lp.z, lp.x) * 9.0 + uTime * 0.3);
      vec3 pc = 0.5 + 0.5 * cos(6.2831 * (vec3(pf * 0.5 + uTime * 0.05) + vec3(0.0, 0.33, 0.67)));
      vec3 alb = mix(mix(hc, bc, band * 0.5), pc, clamp(pol_k * pf, 0.0, 1.0)); float al = clamp(mo_k * (0.58 + 0.30 * mm + 0.20 * band) + pol_k * pf * 0.6, 0.0, 0.94); gl_FragColor = vec4(s2l(alb), al); }` });
  const skyFxMesh = new THREE.Mesh(new THREE.PlaneGeometry(1500, 520), skyFxMat); skyFxMesh.frustumCulled = false; skyFxMesh.visible = false; skyFxMesh.renderOrder = -5; scene.add(skyFxMesh);
  const skyDomeMesh = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), skyDomeMat); skyDomeMesh.frustumCulled = false; skyDomeMesh.visible = false; skyDomeMesh.renderOrder = -6; scene.add(skyDomeMesh);
  let mtnMesh = null;
  function attachMountainSkin(ringMesh) {          // gv.js passes its mountain ring (the 1620-vertex mesh); a second mesh with the skin material shares its geometry and follows it
    mtnMesh = new THREE.Mesh(ringMesh.geometry, mtnFxMat); mtnMesh.matrixAutoUpdate = false; mtnMesh.frustumCulled = false; mtnMesh.visible = false; mtnMesh.renderOrder = 4; mtnMesh.userData.src = ringMesh; scene.add(mtnMesh); F2.attachMountainFace(ringMesh); return mtnMesh;
  }
  // ---------------------------------------------------------------- the stage flags and the environment blend
  const stage = { sky: false, skymat: false, ground: false, veg: false, light: false }, E = { k: 0 };
  const lerpA = (a, b, k) => a.map((x, i) => x + (b[i] - x) * k);
  function envAt(k) {          // ThemeFX.blend_env: every value of the alpine environment slides toward the psychedelic one
    const P = Object.assign({}, ALPINE, PSYCHEDELIC), r = {}; delete P.ambient_color;
    for (const key of Object.keys(ALPINE)) { const a = ALPINE[key], b = P[key] !== undefined ? P[key] : a; r[key] = Array.isArray(a) ? lerpA(a, b, k) : a + (b - a) * k; }
    r.ambient_color = k > 0.001 ? null : ALPINE.ambient_color;          // ThemeFX._snapshot has no ambient_color, so as soon as any blend runs the ambient comes from the SKY (MainLevel._apply_environment 234-238)
    return r;
  }
  function onStage(part, on) { stage[part] = !!on; F2.setStage(part, on); if (part === 'ground') { const p = GROUND_PAL.psychedelic; G.w_a.value.set(...p.a); G.w_b.value.set(...p.b); G.w_line.value.set(...p.line); G.w_mix.value = on ? p.mix : 0; } }
  function onSky(k) { E.k = k; }
  // ---------------------------------------------------------------- per frame
  function tick(dt, time, W, ctx = {}) {
    // ground (RunRig._stage_tick + _moire_tick, numbers computed by psyfx world())
    const M = W.moire; G.grid.value = W.groundGrid; G.gglow.value = W.groundGlow; G.m_cell.value = M.cell; G.m_ang.value = M.ang; G.m_ratio.value = M.ratio; G.m_depth.value = M.depth; G.m_sat.value = M.sat; G.m_hue.value = M.hue; G.m_tri.value = M.tri; G.m_rad.value = M.rad; G.m_warp.value = M.warp; G.m_drift.value.set(M.drift[0], M.drift[1]);
    if (ctx.board) G.gcen.value.set(ctx.board.x, ctx.board.z);
    if (M.rad > 0.05 && !tick.radOn && ctx.board) { G.m_rc.value.set(ctx.board.x, ctx.board.z); } tick.radOn = M.rad > 0.05;          // the bullseye is centred where you were when it started
    // trees (7122-7123, 6507-6513)
    T.wob.value = W.vegWob; T.breathe.value = W.vegBreathe; T.mo_k.value = W.treeMoire; T.mo_t.value.set(W.wanderDrift[0], W.wanderDrift[1]);
    // horizon bend (RunRig._bend_tick): 0 unless the lab's w_bend is on; kept as a knob
    shared.bendK.value = 0.00012 * (ctx.bendKnob || 0) * (0.4 + 0.6 * (ctx.speed01 || 0));
    // sky bands, dome and mountain skin (7164-7178, 6420-6455, 6504-6545)
    const cam = ctx.camera || camera;
    SF.k.value = W.skyK; skyFxMesh.visible = W.skyK > 0.004;
    if (skyFxMesh.visible) { const f = new V3(); cam.getWorldDirection(f); f.y = 0; if (f.length() > 0.01) f.normalize(); else f.set(0, 0, -1); skyFxMesh.position.copy(cam.position).addScaledVector(f, 620).add(new V3(0, 250, 0)); skyFxMesh.lookAt(cam.position.x, skyFxMesh.position.y, cam.position.z); }
    SD.polar.value = W.skyPolar; SD.tun.value = W.skyTunnel; SD.spd.value = Math.min(1, Math.max(0, ctx.speed01 || 0)); const domeOn = W.skyPolar + W.skyTunnel > 0.01; skyDomeMesh.visible = domeOn; if (domeOn) skyDomeMesh.position.copy(cam.position);
    MT.mo_k.value = W.mtnMoire; MT.br_k.value = W.mtnBreathe; MT.pol_k.value = W.mtnPolar; MT.mo_t.value.set(W.wanderDrift[0], W.wanderDrift[1]); MT.trav.value = ctx.travZ || 0; MT.cam_pos.value.copy(cam.position);
    if (mtnMesh) { const on = W.mtnMoire + W.mtnBreathe + W.mtnPolar > 0.02; mtnMesh.visible = on; if (on) mtnMesh.matrix.copy(mtnMesh.userData.src.matrix); }
    if (shared.uTime === (U && U.uTime)) { /* gv.js owns the clock */ } else shared.uTime.value = time;
    F2.tick(dt, time, W, Object.assign({ camera: cam }, ctx));
  }
  return {
    ground, vegLive, skyAlpine, attachMountainSkin, onStage, onSky, tick, envAt, stage, E,
    groundPsy: F2.groundPsy, vegPsy: F2.vegPsy, skyPsy: F2.skyPsy, registerTrees: F2.registerTrees, unregisterTrees: F2.unregisterTrees, registerSky: F2.registerSky, ringBell: F2.ringBell, face: F2, srgbToLinear,
    uniforms: { vcLin: F2.VC.vc_lin, fogColor: shared.fogColor, fogDensity: shared.fogDensity, groundPsy: F2.GP, face: F2.F, ground: G, veg: T, shared, skyFx: SF, skyDome: SD, mountain: MT, sky: SKYU }, meshes: { skyFx: skyFxMesh, skyDome: skyDomeMesh },
    // alpine <-> theme sky colours for the procedural sky: call after envAt(k) each frame the blend changes
    setSkyEnv(c, sunRotDeg) { SKYU.sTop.value.set(...c.sky_top); SKYU.sHor.value.set(...c.sky_horizon); SKYU.sGnd.value.set(...c.sky_ground); SKYU.sunCol.value.set(...c.sun_color).multiplyScalar(Math.min(1, c.sun_energy / 1.9)); SKYU.sunDisc.value = c.sun_disc; SKYU.sunCurve.value = c.sun_curve;
      const r = sunRotDeg || c.sun_rot, rx = r[0] * Math.PI / 180, ry = r[1] * Math.PI / 180; SKYU.sunDir.value.set(Math.sin(ry) * Math.cos(rx), -Math.sin(rx), Math.cos(ry) * Math.cos(rx)).multiplyScalar(-1); },          // (Godot's sun shines along its -Z; the sky disc sits the other way)
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// DIFFERENCES FOUND between gv.js today and the Godot journey world (file:line in the Godot project; gv.js line numbers as of this writing):
//  1. gv.js renders the PSYCHEDELIC world from the first frame (the dump was taken with journey:false). Godot's journey starts ALPINE and the psychedelic pieces arrive per stage (ThemeFX.gd 113-175; psyfx onStage/onSky). Missing: the alpine start (snow ground, dark pine, blue sky, alpine fog/sun/ambient: LevelBuilder.gd 123-136) and the blend.
//  2. Ground: gv.js uses a standalone port of Themes.GROUND_PSY (gv.js:41-52). In the journey the ground is DownhillRig.GROUND_SHADER (DownhillRig.gd 1853-1990) in EVERY world, with a palette (w_a/w_b/w_line/w_mix) and the moire knobs driven by the dose: m_cell, m_ang, m_ratio, m_depth, m_sat, m_hue, m_tri, m_rad, m_warp, m_drift, m_rc, gglow, grid (RunRig.gd 7068-7110, 7120-7127). Missing in gv.js: the whole snow base (big/drift noise patches, fine grain, sparkle), the 6 m hard squares + their 24 m / 96 m far fades, the third grid, the bullseye rings, the warp, the dose-driven colour, the speed-driven turning.
//  3. Trees: gv.js:54-66 (vegMat) is the themed VEG_PSY hue-drift material, always on. Missing: the alpine tree (VEG_LIVE_SHADER, RunRig.gd 6019-6103: lit vertex colours, roughness 1, specular 0), sway (wob), breathing, 2C-B moire skin (mo_k, mo_t), horizon bend. The swap to VEG_PSY should only happen at the "veg" stage and only for new stretches of hill in Godot (RunRig comment on 'veg').
//  4. Sky: gv.js:67-80 (skyMat) is SKY_PSY only. Missing: the alpine ProceduralSkyMaterial start, the bands quad (SKY_SHADER, 0.30 * pk(1) breathing, first hint of the trip), the sky dome (DOM polar field and 2C-T-7 tunnel, SKYDOME_SHADER).
//  5. Mountains/backdrop: gv.js maps the dump's backdrop material (HORIZON BEND) and ring. Missing: the 2C-E skin (MTNFX_SHADER: moire creeping with travel, rolling contour bands, polar field), driven by m_moire / m_breathe / m_polar and the wander clocks (RunRig.gd 6504-6545).
//  6. Environment: gv.js sets fog/sun/ambient once from the dump (psychedelic values). Godot blends alpine -> theme env by the onset k (ThemeFX.blend_env 178-205): fog colour/density, sun colour/energy/rotation, ambient (sky or colour 0.66,0.75,0.97), exposure stays 1.05 (the theme sets none), saturation 1.1 -> 1.15, contrast 1.08 -> 1.1, glow 0.3 -> 0.35.
//  7. Horizon bend (bend_k): in gv.js only the backdrop has it; Godot applies it to ground, trees, skirt and backdrop (default OFF: the lab knob w_bend = 0; speed-scaled when on).
//  8. Tree geometry: the dumped tree mesh IS DownhillRig._make_tree_mesh (3 tiers, 6 sides, radius jitter 0.14*sin(i*2.3)), so no replacement is needed. In the candy world Godot swaps in fluffy puffs (Themes.fluffy_tree_mesh) and gumdrop rocks: not needed for psychedelic.
//  9. Rocks: same material path as trees (the live shader), and the 'ring bell' struck-rock wobble (RunRig._ring_bell, 5653-5680) is a short scale/alpha animation of a glowing copy: the game's collision code can re-create it with a pooled additive mesh.
// 10. Vertex colours: the dump stores Godot's colours; three's colour pipeline is linear, so keep the geometry's colour attribute as it is (the ground shader here multiplies it in linear space exactly like Godot's ALBEDO).
//
// INTEGRATION LINES for gv.js (in order):
//   import { createWorldFx } from './worldfx.js';
//   const WFX = createWorldFx({ THREE, scene, camera, U });                     // after U, scene, camera exist
//   (ground meshes: replace their material with WFX.ground(); trees: keep two materials per instanced tree mesh: LIVE = WFX.vegLive() and THEME = your existing vegMat(); start on LIVE)
//   const mtnSkin = WFX.attachMountainSkin(ring);                                // `ring` is the mountain ring mesh gv.js already tracks; each frame copy ring.matrix into mtnSkin.matrix (done inside tick when attached)
//   PSY options:  createPsyFx({ ..., onStage: (part, world) => { WFX.onStage(part, world !== 'alpine'); if (part === 'veg') for (const t of treeMeshes) t.material = world !== 'alpine' ? THEME : LIVE; }, onSky: (world, k) => WFX.onSky(k) })
//   in playStep after PSY.tick:  WFX.tick(dt, clock.t, PSY.world(), { board: { x: PH.x, z: PH.z }, camera, speed01: Math.min(1, spd / 50 / SPK), travZ: -PH.z });
//   the environment each frame:  const c = WFX.envAt(WFX.E.k); fog: U.fogColor.value.setRGB(...c.fog); U.fogDensity.value = c.fog_density; scene.fog.color/density the same; sun.color.setRGB(...c.sun_color); sun.intensity = c.sun_energy; hemi.intensity = c.ambient;
//   the alpine sky (until the 'skymat' stage): sky.material = WFX.skyAlpine(); WFX.setSkyEnv(c) each frame while E.k < 1; at the 'skymat' stage swap sky.material to your SKY_PSY material.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// ROUND 2 (worldfx2.js): the COLOUR RULE and the rest of the world. Findings and integration for gv.js
//  A. COLOUR: Godot opengl3 converts every authored colour sRGB->linear before the Filmic tonemap (measured: godot/tests/tonecard.gd, web/data/tonecard_*.json); unshaded EMISSION renders nothing. All materials here mix in authored space and
//     call s2l() once. GROUND_PSY's "ALBEDO = col*col" is therefore s2l(col*col) ~ col^4.4: a port that treats col*col as linear (gv.js groundMat, line 51-62) is ~2x too saturated and too bright; that is also why exposure 0.6 looked right.
//  B. gv.js integration (exact lines):
//     const GP = WFX.groundPsy({ labA: U.uLabA });  ground meshes: m.material = GP  (replaces gv.js groundMat; speed/gcen are driven by WFX.tick: ctx.speed01, ctx.board)       // exact Themes GROUND_PSY + s2l + Godot fog
//     veg: const live = WFX.vegLive(); WFX.registerTrees(treeMeshesAndRocks, live); stage 'veg' (PSY onStage -> WFX.onStage) swaps to WFX.vegPsy() (VEG_PSY) automatically; call WFX.registerTrees(newRowMeshes) when a row streams in
//     sky: WFX.registerSky(skyMesh, WFX.skyAlpine()); stage 'skymat' swaps to WFX.skyPsy(); (gv.js skyMat() is the same SKY_PSY but without s2l)
//     mountains: WFX.attachMountainSkin(ring) now also creates the face print for the mountains (WFX.face.godMesh is the sky god); each frame: WFX.tick(dt, clock.t, PSY.world(), { camera, board:{x:PH.x,z:PH.z}, speed01, travZ:-PH.z, heading, bendKnob })
//     geometry colours: either leave them raw (dump values, default) or convert to linear in geoOf and set WFX.uniforms.vcLin.value = 1 (the shaders convert back to authored space, same result). Do NOT convert AND leave vcLin 0.
//     fog: the module reads U.fogColor / U.fogDensity (Godot formula 1-exp(-d*density), not three's FogExp2); set scene.fog = null for these materials (fog:false is already set on them).
//     rocks struck: WFX.ringBell(x, groundY, z, radius, rockGeometry)  (pooled, 8 max, 0.9 s)
//  C. KNOWN GAPS: the ground's own face layer is dead code in Godot (face_k forced to 0, RunRig 6713-6720), so it is not ported; lit EMISSION colour space is untested (left linear); the sky bands quad / dome / god use Godot's blend_add as additive.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
