// WORLDFX2: the second half of the Godot world port (worldfx.js is the first): the colour rule, the exact GROUND_PSY / VEG_PSY / SKY_PSY materials, THE FACE (portrait in the mountains, on the trees and the god in the
// sky), the struck-rock "ring bell" pool, and the tree / sky stage swaps. createWorldFx() in worldfx.js builds this and merges its API, so gv.js only imports worldfx.js.
//
// THE COLOUR RULE (measured, godot/tests/tonecard.gd -> web/data/tonecard_*.json): Godot's opengl3 renderer treats EVERY authored colour as sRGB and converts it to linear before the Filmic tonemap:
//   shader ALBEDO, vertex COLOR, sky COLOR, StandardMaterial albedo_color, source_color uniforms all give the same pixel for the same number (0.5 -> 165 of 255 = srgb_encode(filmic(s2l(.5)*1.05)/filmic(1)));
//   unshaded + EMISSION renders nothing (0 for every value). So GROUND_PSY's "ALBEDO = col * col" is s2l(col^2), about col^4.4: that is why a port that used col^2 as linear is ~2x too saturated and too bright.
// Every material here therefore does its mixing in AUTHORED (screen) space and converts ONCE at the end with s2l(). Pass { vertexLinear: true } to a material when the geometry's colour attribute was already
// converted to linear on load (then the shader converts it back to authored space first, so the result is identical either way).

export const srgbToLinear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
export const S2L_GLSL = 'vec3 s2l(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }\nvec3 l2s(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }';
export const HSV_GLSL = 'vec3 hsv(float h, float s, float v) { vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0); vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0); return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s); }';
const NL = String.fromCharCode(10);
// Godot's fog (MainLevel env: fog_density 0.002 in the psychedelic world): amount = 1 - exp(-density * distance), toward the fog colour, before the tonemap. NOT three's FogExp2 (which squares the product).
export const GODOT_FOG_UNIFORMS = 'uniform vec3 gFogColor; uniform float gFogDensity;';
export const GODOT_FOG_LIT = 'gl_FragColor.rgb = mix(gl_FragColor.rgb, gFogColor, 1.0 - exp(-gFogDensity * length(vViewPosition)));';
const TAIL = NL + '#include <tonemapping_fragment>' + NL + '#include <colorspace_fragment>' + NL;

// ---- THE FACE shader pieces (RunRig.gd FACEFX_SHADER 6546-6652, veg block 6054-6112): one set of functions shared by the trees, the mountains and the sky
export const FACE_UNIFORMS = 'uniform sampler2D face_tex; uniform float face_lift, fm_ratio, fm_ang, fm_sat, fm_cyc; uniform vec2 fm_drift; uniform float uTime;';
export const FACE_FUNCS = `
vec3 face_sample(float az, float el) {
  vec2 p = vec2(az, el - 0.02 + face_lift) / 0.55;
  vec2 uv = vec2(0.5 + p.x * 0.5 / 0.667, 0.5 - p.y * 0.5);
  float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  float vig = smoothstep(0.0, 0.10, uv.x) * smoothstep(1.0, 0.90, uv.x) * smoothstep(0.0, 0.08, uv.y) * smoothstep(1.0, 0.92, uv.y);
  vec2 cu = clamp(uv, vec2(0.0), vec2(1.0));
  float l = (texture2D(face_tex, cu).r + texture2D(face_tex, clamp(uv + vec2(0.04, 0.0), vec2(0.0), vec2(1.0))).r + texture2D(face_tex, clamp(uv - vec2(0.04, 0.0), vec2(0.0), vec2(1.0))).r + texture2D(face_tex, clamp(uv + vec2(0.0, 0.03), vec2(0.0), vec2(1.0))).r + texture2D(face_tex, clamp(uv - vec2(0.0, 0.03), vec2(0.0), vec2(1.0))).r) * 0.2;
  l = mix(0.62, l, 0.6);
  return vec3(l * inside, inside, vig * inside);
}
vec3 face_moire_fill(vec2 f, float tone) {
  vec2 a = f * 6.2831 * fm_cyc;
  float s1 = sin(a.x) * sin(a.y);
  float ca = cos(fm_ang); float sa = sin(fm_ang);
  vec2 b = vec2(f.x * ca - f.y * sa, f.x * sa + f.y * ca) * 6.2831 * fm_cyc * fm_ratio + fm_drift + vec2(tone * 3.14159);
  float s2 = sin(b.x) * sin(b.y);
  float m = smoothstep(-0.5, 0.5, s1 * s2);
  vec3 hc = clamp(abs(fract(vec3(m * 0.5 + tone * 0.3 + uTime * 0.04) + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
  return mix(vec3(m), hc, fm_sat) * (0.35 + 0.65 * m);
}
float face_ink(vec2 f, vec3 ls, float radk) {
  float rad = radk * sqrt(clamp(1.0 - ls.x, 0.0, 1.0)) * ls.y;
  float d = length(f);
  float aa = fwidth(d) + 0.02;
  return smoothstep(rad + aa, rad - aa, d) * ls.z;
}`;
// the portrait printed on foliage (veg block): dv = direction from where the face began; returns ink in rgb, dot weight in a
export const FACE_TREE = `
vec4 face_on_tree(vec3 wpos, vec3 fo, float faz) {
  vec3 dv = normalize(wpos - fo);
  float azv = atan(dv.x, -dv.z) - faz;
  azv = atan(sin(azv), cos(azv));
  float csv = 0.010;
  vec2 qv = vec2(azv, dv.y);
  vec2 cidv = floor(qv / csv);
  vec3 ls = face_sample((cidv.x + 0.5) * csv, (cidv.y + 0.5) * csv);
  float dt = face_ink(fract(qv / csv) - 0.5, ls, 0.36);
  vec3 ink = mix(vec3(0.10, 0.03, 0.26), face_moire_fill(fract(qv / csv) - 0.5, ls.x), fm_sat);
  return vec4(ink, dt);
}`;
const FACE_SHADER_FRAG = `
uniform float face_k, face_az, mode; uniform vec3 cam_pos; varying vec3 dirv;
` + FACE_UNIFORMS + FACE_FUNCS + S2L_GLSL + `
vec4 face_god(vec3 d, float az0, float k) {
  float az = atan(d.x, -d.z) - az0;
  float th = acos(clamp(d.y, -1.0, 1.0));
  float r = tan(th * 0.5);
  vec2 p = r * vec2(sin(az), -cos(az));
  float cs = 0.014;
  vec2 cid = floor(p / cs);
  vec2 f = fract(p / cs) - 0.5;
  vec2 cc = (cid + 0.5) * cs;
  vec2 uv = vec2(0.5 + cc.x * 0.5 / (0.85 * 0.667), 0.5 - cc.y * 0.5 / 0.85);
  float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  float vig = smoothstep(0.0, 0.10, uv.x) * smoothstep(1.0, 0.90, uv.x) * smoothstep(0.0, 0.08, uv.y) * smoothstep(1.0, 0.92, uv.y) * inside;
  float lum = texture2D(face_tex, clamp(uv, vec2(0.0), vec2(1.0))).r;
  float rad = 0.07 + 0.42 * sqrt(lum);
  float dd = length(f);
  float aa = fwidth(dd) + 0.02;
  float dt = smoothstep(rad + aa, rad - aa, dd) * vig;
  vec3 col = face_moire_fill(f, lum);
  return vec4(col, dt * k * smoothstep(0.02, 0.18, d.y));
}
vec4 face_terrain(vec3 d, float az0, float k) {
  float az = atan(d.x, -d.z) - az0;
  az = atan(sin(az), cos(az));
  float cs = 0.010;
  vec2 q = vec2(az, d.y * 0.0022 - 0.40);
  vec2 cid = floor(q / cs);
  vec3 ls = face_sample((cid.x + 0.5) * cs, (cid.y + 0.5) * cs);
  float dt = face_ink(fract(q / cs) - 0.5, ls, 0.47);
  vec3 ink = mix(vec3(0.10, 0.03, 0.26), face_moire_fill(fract(q / cs) - 0.5, ls.x), fm_sat);
  return vec4(ink, dt * k);
}
void main() {
  vec4 fm = mode < 0.5 ? face_god(normalize(dirv), face_az, face_k) : face_terrain(dirv, face_az, face_k);
  gl_FragColor = vec4(s2l(fm.rgb), fm.a);
` + TAIL + '}';

export function createWorldFx2(o) {
  const { THREE, scene, camera, shared, G, MT } = o;
  const V2 = THREE.Vector2, V3 = THREE.Vector3;
  // ---------------------------------------------------------------- the face texture (godot/scripts/FaceTone.gd: 120 x 180, light = bright; extracted to face_tone.png)
  const faceTex = new THREE.TextureLoader().load(new URL('./face_tone.png', import.meta.url).href);
  faceTex.colorSpace = THREE.NoColorSpace; faceTex.minFilter = faceTex.magFilter = THREE.LinearFilter; faceTex.wrapS = faceTex.wrapT = THREE.ClampToEdgeWrapping; faceTex.generateMipmaps = false;
  const F = { face_tex: { value: faceTex }, face_lift: { value: 0 }, fm_ratio: { value: 1.2 }, fm_ang: { value: 0 }, fm_drift: { value: new V2() }, fm_sat: { value: 0.7 }, fm_cyc: { value: 3 },
    face_k: { value: 0 }, face_az: { value: 0 }, face_o: { value: new V3() } };          // (trees' face uniforms; the sky / mountain materials carry their own face_k / face_az)
  shared.fogColor = shared.fogColor || { value: new THREE.Color(0.35, 0.05, 0.45) }; shared.fogDensity = shared.fogDensity || { value: 0.002 };
  const fogU = () => ({ gFogColor: shared.fogColor, gFogDensity: shared.fogDensity });
  const VC = { vc_lin: { value: 0 } };          // 1 when gv.js has already converted the geometry's colours to linear (the shaders then convert back to authored space)
  const vcOf = (name) => `(vc_lin > 0.5 ? l2s(${name}) : ${name})`;

  // ---------------------------------------------------------------- GROUND_PSY exactly (Themes.gd 68-98): unshaded, two grids, ALBEDO = col*col -> s2l(col*col)
  // uniforms: speed (0..1, the board's speed: the colour breathes with it), gcen (where the board is: the second grid turns about it)
  const GP = { speed: { value: 0 }, gcen: { value: new V2() } };
  function groundPsy(opt = {}) {
    const lab = opt.labA || { value: new THREE.Vector4(1, 1.037, 1, 1) };          // (x grid scale, y second-grid ratio, z turning, w saturation): all 1 / 1.037 = Godot as is
    const m = new THREE.ShaderMaterial({ uniforms: Object.assign({ uTime: shared.uTime, uLabA: lab }, GP, fogU()), side: THREE.DoubleSide, fog: false,
      vertexShader: 'varying vec3 wp; void main() { wp = (modelMatrix * vec4(position, 1.0)).xyz; gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0); }',
      fragmentShader: 'uniform float uTime, speed, gFogDensity; uniform vec4 uLabA; uniform vec3 gFogColor; uniform vec2 gcen; varying vec3 wp;' + NL + HSV_GLSL + NL + S2L_GLSL + `
      void main() {
        float dist = distance(wp, cameraPosition);
        float sc = uLabA.x / 6.0;
        vec2 g1 = wp.xz * sc;
        float grid1 = sin(g1.x * 6.283) * sin(g1.y * 6.283);
        float t = uTime * 0.15 * 0.3 * uLabA.z; float ca = cos(t), sa = sin(t);
        vec2 rp = wp.xz - gcen;
        vec2 g2 = vec2(rp.x * ca - rp.y * sa, rp.x * sa + rp.y * ca) * sc * uLabA.y;
        float grid2 = sin(g2.x * 6.283) * sin(g2.y * 6.283);
        float far = 1.0 - smoothstep(130.0, 340.0, dist);
        float amp = mix(0.5, grid1 * grid2 * 0.5 + 0.5, far);
        float sq = mix(0.5, smoothstep(-0.06, 0.06, grid1), far);
        vec3 col = hsv(fract(amp * 0.5 + uTime * 0.03), clamp(0.9 * uLabA.w, 0.0, 1.0), 0.25 + 0.75 * pow(amp, 0.65)) * (0.62 + 0.38 * sq);
        col *= 0.75 + 0.25 * speed;
        vec3 lin = s2l(col * col);          // ALBEDO = col * col, then Godot's own sRGB -> linear
        lin = mix(lin, gFogColor, 1.0 - exp(-gFogDensity * dist));
        gl_FragColor = vec4(lin, 1.0);` + TAIL + '}' });
    return m;
  }

  // ---------------------------------------------------------------- VEG_PSY (Themes.gd 270-285): themed trees and rocks, lit (roughness 0.5), neon hue drifting with where it stands and with time. Instancing friendly.
  function vegPsy(opt = {}) {
    const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0, side: THREE.DoubleSide, fog: false });
    m.userData.veg = true;
    const lab = opt.labB || { value: new THREE.Vector4(1, 1, 1, 1) };          // (x hue drift speed, y emission): 1, 1 = Godot as is
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, { uTime: shared.uTime, uLabB: lab }, VC, fogU());
      sh.vertexShader = 'varying vec3 vWp;' + NL + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
        vec4 wpp_ = vec4(transformed, 1.0);
        #ifdef USE_INSTANCING
        wpp_ = instanceMatrix * wpp_;
        #endif
        vWp = (modelMatrix * wpp_).xyz;`);
      sh.fragmentShader = 'varying vec3 vWp; uniform float uTime, vc_lin, gFogDensity; uniform vec3 gFogColor; uniform vec4 uLabB;' + NL + HSV_GLSL + NL + S2L_GLSL + NL + sh.fragmentShader
        .replace('#include <color_fragment>', `
          vec3 vcr_ = ${vcOf('vColor.rgb')};
          float lum = dot(vcr_, vec3(0.34));
          lum = mix(lum, 0.55, smoothstep(70.0, 240.0, distance(vWp, cameraPosition)));          // the fine tiers of the foliage flatten with distance, so they cannot alias into stripes
          float hue = fract(vWp.z * 0.012 + vWp.x * 0.007 + uTime * 0.07 * uLabB.x + lum * 0.2);
          vec3 neon = hsv(hue, 0.85, 1.0);
          diffuseColor.rgb = s2l(mix(vec3(0.03, 0.0, 0.06), neon * 0.75, smoothstep(0.1, 0.9, lum)));
          vec3 gEmiV = neon * smoothstep(0.35, 1.0, lum) * 0.75 * uLabB.y;`)
        .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>' + NL + 'totalEmissiveRadiance += gEmiV;')
        .replace('#include <fog_fragment>', GODOT_FOG_LIT);
    };
    m.customProgramCacheKey = () => 'worldfx2-vegpsy';
    return m;
  }

  // ---------------------------------------------------------------- SKY_PSY (Themes.gd 424+): the psychedelic sky; sky COLOR is also sRGB -> linear in Godot
  function skyPsy() {
    return new THREE.ShaderMaterial({ uniforms: { uTime: shared.uTime }, side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: 'varying vec3 vD; void main() { vD = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0); gl_Position = p.xyww; }',
      fragmentShader: 'uniform float uTime; varying vec3 vD;' + NL + S2L_GLSL + `
        vec3 pal(float t) { return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67))); }
        void main() { vec3 d = normalize(vD); float az = atan(d.x, -d.z);
          float band = 0.5 + 0.5 * sin(az * 2.0 + d.y * 5.0 + sin(d.y * 3.0 + uTime * 0.15) * 1.2 + uTime * 0.05);
          vec3 col = pal(d.y * 0.5 + az * 0.08 + uTime * 0.02) * (0.05 + 0.20 * band * smoothstep(0.0, 0.6, d.y)); col += vec3(0.02, 0.0, 0.06);
          float horizon = smoothstep(-0.1, 0.3, d.y);
          gl_FragColor = vec4(s2l(mix(vec3(0.10, 0.01, 0.16), col, horizon)), 1.0);` + TAIL + '}' });
  }

  // ---------------------------------------------------------------- THE FACE on the sky (the god) and on the mountains (the terrain print): the same shader, two meshes (RunRig._face_fx_tick 6654-6720)
  const sharedFace = { uTime: shared.uTime, face_tex: F.face_tex, face_lift: F.face_lift, fm_ratio: F.fm_ratio, fm_ang: F.fm_ang, fm_drift: F.fm_drift, fm_sat: F.fm_sat, fm_cyc: F.fm_cyc };
  function faceMat(mode) {
    return new THREE.ShaderMaterial({ uniforms: Object.assign({ mode: { value: mode }, face_k: { value: 0 }, face_az: { value: 0 }, cam_pos: { value: new V3() } }, sharedFace), transparent: true, depthWrite: false, side: THREE.DoubleSide, fog: false,
      vertexShader: 'varying vec3 dirv; void main() { dirv = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }', fragmentShader: FACE_SHADER_FRAG });
  }
  const godMat = faceMat(0), mtnFaceMat = faceMat(1);
  const godMesh = new THREE.Mesh(new THREE.SphereGeometry(880, 48, 24), godMat); godMesh.frustumCulled = false; godMesh.visible = false; godMesh.renderOrder = -4; scene.add(godMesh);
  let mtnFace = null;
  function attachMountainFace(ringMesh) {          // same geometry as the mountain ring, drawn with the face shader (local coordinates: the picture is carved into the rock)
    mtnFace = new THREE.Mesh(ringMesh.geometry, mtnFaceMat); mtnFace.matrixAutoUpdate = false; mtnFace.frustumCulled = false; mtnFace.visible = false; mtnFace.renderOrder = 6; mtnFace.userData.src = ringMesh; scene.add(mtnFace); return mtnFace;
  }
  const FS = { efcOn: false, godOn: false, efcAz: 0, godAz: 0 };          // az / origin are captured when each face starts (RunRig 6737-6790: _efc_az = heading, _efc_o = camera position)
  const heading = (cam) => { const f = new V3(); cam.getWorldDirection(f); return Math.atan2(f.x, -f.z); };

  // ---------------------------------------------------------------- the struck-rock "ring bell" (RunRig._ring_bell 5653-5680): a glowing metal copy of the rock rings for 0.9 s (amp (1-u)*0.09, wave sin(u*38)), emission 1.2*(1-u)
  const bells = [];
  function ringBell(ox, oy, oz, orad, geometry) {          // oy = terrain height at the rock; geometry = the rock's own BufferGeometry (the dump's rock mesh)
    let b = bells.find((q) => !q.on) || null;
    if (!b) {
      if (bells.length >= 8) b = bells.reduce((a, q) => (q.u > a.u ? q : a));
      else { const mat = new THREE.MeshStandardMaterial({ roughness: 0.25, metalness: 0.9 }); mat.color.setRGB(0.75, 0.82, 0.95, THREE.SRGBColorSpace); mat.emissive.setRGB(0.5, 0.65, 1.0, THREE.SRGBColorSpace);
        const mesh = new THREE.Mesh(geometry, mat); mesh.frustumCulled = false; scene.add(mesh); b = { mesh, mat, on: false, u: 0, sc: 1 }; bells.push(b); }
    }
    b.mesh.geometry = geometry; const sc = orad / 1.3; b.sc = sc; b.u = 0; b.on = true; b.mesh.visible = true; b.mesh.position.set(ox, oy + 0.7 * sc * 1.1, oz); b.mesh.scale.set(sc * 1.04, sc * 1.1 * 1.04, sc * 1.04); b.mat.emissiveIntensity = 1.2; return b;
  }
  function bellTick(dt) {
    for (const b of bells) if (b.on) {
      b.u += dt / 0.9; if (b.u >= 1) { b.on = false; b.mesh.visible = false; continue; }
      const amp = (1 - b.u) * 0.09, w = Math.sin(b.u * 38), sc = b.sc;
      b.mesh.scale.set(sc * (1.04 + amp * w), sc * 1.1 * (1.04 - amp * w * 0.7), sc * (1.04 + amp * w)); b.mat.emissiveIntensity = 1.2 * (1 - b.u);
    }
  }

  // ---------------------------------------------------------------- the stage swaps: trees (alpine live <-> themed) and the sky material
  const treeMeshes = new Set(); let treeLive = null, treePsy = null, treeStage = false; let skyMesh = null, skyAlpineMat = null, skyPsyMat = null, skyStage = false;
  const applyTrees = () => { for (const t of treeMeshes) t.material = treeStage ? treePsy : treeLive; };
  function registerTrees(meshes, live) { if (live) treeLive = live; if (!treePsy) treePsy = vegPsy(); for (const m of [].concat(meshes)) treeMeshes.add(m); applyTrees(); }
  const unregisterTrees = (meshes) => { for (const m of [].concat(meshes)) treeMeshes.delete(m); };
  function registerSky(mesh, alpineMat) { skyMesh = mesh; skyAlpineMat = alpineMat; skyPsyMat = skyPsyMat || skyPsy(); skyMesh.material = skyStage ? skyPsyMat : skyAlpineMat; }
  function setStage(part, on) {
    if (part === 'veg') { treeStage = !!on; applyTrees(); }
    if (part === 'skymat' || part === 'sky') { if (part === 'skymat') { skyStage = !!on; if (skyMesh) skyMesh.material = skyStage ? skyPsyMat : skyAlpineMat; } }
  }
  function newRegisterCheck() { return { trees: treeMeshes.size, treeStage, skyStage }; }

  // ---------------------------------------------------------------- per frame: the face timers' outputs (psyfx world(): faceK, godK, faceLift) and the mosaic's moire knobs (_face_moire_params 6722-6728)
  function tick(dt, time, W, ctx = {}) {
    const cam = ctx.camera || camera, M = W.moire || {}, buzz = ctx.buzzT !== undefined ? ctx.buzzT : time;
    F.fm_ratio.value = 1 + ((M.ratio || 1.037) - 1) * 6 + 0.04 * Math.sin(buzz * 0.3); F.fm_ang.value = (M.ang || 0) * 0.6; F.fm_drift.value.set((M.drift ? M.drift[0] : 0) * 2, (M.drift ? M.drift[1] : 0) * 2);
    F.fm_sat.value = Math.min(1, Math.max(0, 0.55 + (M.sat || 0) * 0.45)); F.fm_cyc.value = 2 + 2 * Math.min(1.5, Math.max(0, (M.cell || 6) / 6 - 0.5)); F.face_lift.value = W.faceLift || 0;
    const fk = W.faceK || 0, gk = W.godK || 0;
    if ((fk > 0.001 && !FS.efcOn) || (fk > 0.001 && ctx.faceHold)) { FS.efcAz = ctx.heading !== undefined ? ctx.heading : heading(cam); F.face_o.value.copy(cam.position); } FS.efcOn = fk > 0.001;
    if ((gk > 0.001 && !FS.godOn) || (gk > 0.001 && ctx.godHold)) FS.godAz = ctx.heading !== undefined ? ctx.heading : heading(cam); FS.godOn = gk > 0.001;
    F.face_k.value = fk > 0.01 ? fk : 0; F.face_az.value = FS.efcAz;          // trees (veg_live reads these)
    godMat.uniforms.face_k.value = gk; godMat.uniforms.face_az.value = FS.godAz; godMesh.visible = gk > 0.01; if (godMesh.visible) godMesh.position.copy(cam.position);
    mtnFaceMat.uniforms.face_k.value = fk; mtnFaceMat.uniforms.face_az.value = FS.efcAz; mtnFaceMat.uniforms.cam_pos.value.copy(cam.position);
    if (mtnFace) { mtnFace.visible = fk > 0.01 && !ctx.backdropMode; if (mtnFace.visible) mtnFace.matrix.copy(mtnFace.userData.src.matrix); }
    GP.speed.value = Math.min(1, Math.max(0, ctx.speed01 || 0)); if (ctx.board) GP.gcen.value.set(ctx.board.x, ctx.board.z);
    bellTick(dt);
  }
  return { F, VC, GP, fogU, vcOf, groundPsy, vegPsy, skyPsy, godMesh, godMat, mtnFaceMat, attachMountainFace, ringBell, registerTrees, unregisterTrees, registerSky, setStage, tick, check: newRegisterCheck, faceTex, FS };
}
