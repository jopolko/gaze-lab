// GODOT LEVEL VIEWER. Renders a level DUMPED from the real Godot game (godot/tests/dump_level.gd: the real generator, run headless with a fixed seed) so that every mesh, every instance and every transform
// is the game's own, not an approximation. Godot and three.js are both right-handed, Y up, -Z forward, so transforms carry over as they are. What this file does: build geometry from the dumped vertex arrays,
// map Godot's materials (StandardMaterial3D -> MeshStandardMaterial, each shader -> a GLSL port), set the sun, the sky-lit ambient, the exponential fog and the filmic tonemap from the dumped Environment, and fly a camera down the course.
import * as THREE from 'three';
const Q = new URLSearchParams(location.search);
const LVL = Q.get('lvl') || (Q.has('classic') ? 'level_psy_s7' : 'level_wide2_s7');
const hud = document.getElementById('hud');
THREE.ColorManagement.enabled = true;
// Godot's exponential fog (1 - exp(-density * distance)); three's own is squared
THREE.ShaderChunk.fog_fragment = `#ifdef USE_FOG
  float fogFactor = 1.0 - exp( - fogDensity * vFogDepth );
  gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );
#endif`;
const canvas = document.getElementById('gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5)); renderer.toneMapping = THREE.CineonToneMapping; renderer.toneMappingExposure = 1.05;
const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(78, 1, 0.2, 1600);
const clock = { t: 0 };
import { MOLS, MOL_ORDER } from './molecules.js';
import { createSpawn } from './spawn.js';
import { createToys } from './toys.js';
const U = { uTime: { value: 0 }, uBoard: { value: new THREE.Vector2() }, fogColor: { value: new THREE.Color(0.35, 0.05, 0.45) }, fogDensity: { value: 0.001 } };          // (Godot's exponential fog, shared with the custom shaders: 1 - exp(-density * distance) toward the fog colour, in linear light, before the tonemap)
const FOGF = 'float fd = distance(wp, cameraPosition); col = mix(col, fogColor, 1. - exp(-fogDensity * fd));';
const rgb = (a, srgb = true) => new THREE.Color().setRGB(a[0], a[1], a[2], srgb ? THREE.SRGBColorSpace : THREE.LinearSRGBColorSpace);
const mat4 = (x) => new THREE.Matrix4().set(x[0], x[3], x[6], x[9], x[1], x[4], x[7], x[10], x[2], x[5], x[8], x[11], 0, 0, 0, 1);          // dump: basis columns x,y,z then origin

// ---------------------------------------------------------------- the Godot shaders, ported (shader hash -> material)
const GLSL_HSV = `vec3 hsv(float h, float s, float v){ vec3 k = vec3(1., 2./3., 1./3.); vec3 p = abs(fract(vec3(h) + k) * 6. - 3.); return v * mix(vec3(1.), clamp(p - 1., 0., 1.), s); }
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }`;
const TAIL = `
#include <tonemapping_fragment>
#include <colorspace_fragment>
`;
function groundMat(params) {          // GROUND_PSY (Themes.gd): two grids of squares, the second 3.7% finer and turning about the board, coloured by how far in step they are
  return new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime, gcen: U.uBoard, fogColor: U.fogColor, fogDensity: U.fogDensity, speed: { value: params.speed || 0 } }, side: THREE.DoubleSide,
    vertexShader: 'varying vec3 wp; varying vec3 vC; attribute vec3 color; void main(){ wp = (modelMatrix * vec4(position,1.)).xyz; vC = color; gl_Position = projectionMatrix * viewMatrix * vec4(wp,1.); }',
    fragmentShader: `uniform float uTime, speed, fogDensity; uniform vec3 fogColor; uniform vec2 gcen; varying vec3 wp; ${GLSL_HSV}
      void main(){ float dist = distance(wp, cameraPosition); float sc = 1. / 6.; vec2 g1 = wp.xz * sc; float grid1 = sin(g1.x * 6.283) * sin(g1.y * 6.283);
        float t = uTime * .15 * .3, ca = cos(t), sa = sin(t); vec2 rp = wp.xz - gcen; vec2 g2 = vec2(rp.x * ca - rp.y * sa, rp.x * sa + rp.y * ca) * sc * 1.037; float grid2 = sin(g2.x * 6.283) * sin(g2.y * 6.283);
        float far = 1. - smoothstep(130., 340., dist); float amp = mix(.5, grid1 * grid2 * .5 + .5, far); float sq = mix(.5, smoothstep(-.06, .06, grid1), far);
        vec3 col = hsv(fract(amp * .5 + uTime * .03), .9, .25 + .75 * pow(amp, .65)) * (.62 + .38 * sq); col *= .75 + .25 * speed;
        col = col * col; ${FOGF} gl_FragColor = vec4(col, 1.); ${TAIL} }`,
  });
}
function vegMat() {          // VEG_PSY: dark purple, neon where bright, the neon hue drifting with where it stands and with time; lit (roughness .5), so it is a standard material with the albedo and emission replaced
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0, side: THREE.DoubleSide }); m.userData.veg = true;
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = U.uTime;
    sh.vertexShader = 'varying vec3 vWp;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n vec4 wpp = vec4(transformed, 1.);\n#ifdef USE_INSTANCING\n wpp = instanceMatrix * wpp;\n#endif\n vWp = (modelMatrix * wpp).xyz;');
    sh.fragmentShader = 'varying vec3 vWp; uniform float uTime;\n' + GLSL_HSV + '\n' + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        float lum = dot(vColor.rgb, vec3(.34)); float hue = fract(vWp.z * .012 + vWp.x * .007 + uTime * .07 + lum * .2); vec3 neon = hsv(hue, .85, 1.);
        diffuseColor.rgb = mix(vec3(.03, 0., .06), neon * .75, smoothstep(.1, .9, lum));`)
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance += neon * smoothstep(.35, 1., lum) * .75;');
  };
  return m;
}
function skyMat() {          // SKY_PSY
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime }, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: 'varying vec3 vD; void main(){ vD = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p.xyww; }',
    fragmentShader: `uniform float uTime; varying vec3 vD; vec3 pal(float t){ return .5 + .5 * cos(6.28318 * (t + vec3(0., .33, .67))); }
      void main(){ vec3 d = normalize(vD); float az = atan(d.x, -d.z); float band = .5 + .5 * sin(az * 2. + d.y * 5. + sin(d.y * 3. + uTime * .15) * 1.2 + uTime * .05);
        vec3 col = pal(d.y * .5 + az * .08 + uTime * .02) * (.05 + .20 * band * smoothstep(0., .6, d.y)); col += vec3(.02, 0., .06); float horizon = smoothstep(-.1, .3, d.y);
        gl_FragColor = vec4(mix(vec3(.10, .01, .16), col, horizon), 1.); ${TAIL} }` });
}
function backdropMat(params) {          // the distant backdrop with the HORIZON BEND (past 140 m the world curls up with the square of the distance)
  return new THREE.ShaderMaterial({ uniforms: { fogColor: U.fogColor, fogDensity: U.fogDensity, albedo: { value: rgb(params.albedo_color || [1, 1, 1], true) }, bend_k: { value: params.bend_k || 0 } }, side: THREE.DoubleSide,
    vertexShader: 'attribute vec3 color; varying vec3 vC; varying vec3 wp; uniform float bend_k; void main(){ vC = color; vec4 w = modelMatrix * vec4(position, 1.); wp = w.xyz; float bd = max(length(w.xz - cameraPosition.xz) - 140., 0.); w.y += bend_k * bd * bd; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: `uniform vec3 albedo, fogColor; uniform float fogDensity; varying vec3 wp; varying vec3 vC; void main(){ vec3 col = vC * albedo; ${FOGF} gl_FragColor = vec4(col, 1.); ${TAIL} }` });
}
function quadMat(code, params) {          // the soft additive glow quads and the tint gradient
  const add = code.includes('blend_add');
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime, dose: { value: params.dose || 0 }, tint: { value: new THREE.Vector4(...(params.tint || [.93, .96, 1, .97])) } }, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: add ? THREE.AdditiveBlending : THREE.NormalBlending,
    vertexShader: ['varying vec2 vUv;', 'void main(){ vUv = uv;', '#ifdef USE_INSTANCING', ' vec4 p = instanceMatrix * vec4(position, 1.);', '#else', ' vec4 p = vec4(position, 1.);', '#endif', ' gl_Position = projectionMatrix * viewMatrix * modelMatrix * p; }'].join(String.fromCharCode(10)),
    fragmentShader: add
      ? 'uniform float uTime, dose; varying vec2 vUv; void main(){ float e = smoothstep(0., .4, vUv.x) * (1. - smoothstep(.6, 1., vUv.x)); float v = (1. - smoothstep(.7, 1., vUv.y)) * smoothstep(0., .55, vUv.y); float sh = .75 + .25 * sin(vUv.x * 23. + uTime * .7) * sin(vUv.x * 7. - uTime * .4); vec3 rb = .5 + .5 * cos(6.2831 * (vUv.y * 1.5 + uTime * .15 + vec3(0., .33, .67))); gl_FragColor = vec4(mix(vec3(.6, .5, 1.), rb, clamp(dose * 1.4, 0., .85)), e * v * sh * (1. + dose * 1.6) * .6); }'
      : 'uniform vec4 tint; varying vec2 vUv; void main(){ gl_FragColor = vec4(tint.rgb, tint.a * smoothstep(.22, .62, vUv.y)); }' });
}

function glowMat(d) {
  const a = d.albedo, tex = !!d.tex, bb = d.billboard === 1;
  return new THREE.ShaderMaterial({ uniforms: { col: { value: new THREE.Vector4(a[0], a[1], a[2], a[3] * (tex ? 1 : .28)) } }, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; ${bb ? 'vec3 o = modelMatrix[3].xyz; vec2 sc = vec2(length(modelMatrix[0].xyz), length(modelMatrix[1].xyz)); vec4 mv = viewMatrix * vec4(o, 1.) + vec4(position.xy * sc, 0., 0.); gl_Position = projectionMatrix * mv;' : 'gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.);'} }`,
    fragmentShader: `uniform vec4 col; varying vec2 vUv; void main(){ float k = 1.; ${tex ? 'float r = clamp(length(vUv - .5) * 2., 0., 1.); k = r < .3 ? mix(1., .4, r / .3) : mix(.4, 0., (r - .3) / .7);' : 'k = 1. - smoothstep(.35, .5, length(vUv - .5) * 1.0);'} gl_FragColor = vec4(col.rgb, col.a * k); }` });
}
// ---------------------------------------------------------------- load
const LD = document.createElement('div'); LD.style.cssText = 'position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:#10041a;z-index:30;color:#fff;font:700 20px ui-monospace,Consolas,monospace'; LD.innerHTML = '<div id="ldt">loading the level...</div><div style="width:min(70vw,360px);height:10px;margin-top:14px;border:1px solid #fff8;border-radius:6px;overflow:hidden"><div id="ldb" style="height:100%;width:0;background:linear-gradient(90deg,#f0f,#0ff)"></div></div>'; document.body.appendChild(LD);
const showErr = (m) => { const l = document.getElementById('ldt'); if (l) { l.style.color = '#f88'; l.style.fontSize = '14px'; l.style.maxWidth = '90vw'; l.style.wordBreak = 'break-word'; l.textContent = 'could not start: ' + m; } };
addEventListener('error', (e) => showErr((e.message || 'error') + ' ' + (e.filename ? e.filename.split('/').pop() + ':' + e.lineno : ''))); addEventListener('unhandledrejection', (e) => showErr(String((e.reason && (e.reason.stack || e.reason.message)) || e.reason).slice(0, 300)));
const setLoad = (f, t) => { const b = document.getElementById('ldb'), l = document.getElementById('ldt'); if (b) b.style.width = Math.round(Math.max(0, Math.min(1, f)) * 100) + '%'; if (l && t) l.textContent = t; };
const lvl = await (async () => {          // the level file, streamed so the bar can move (about 10 MB)
  const r = await fetch('./data/' + LVL + '.json', { cache: 'no-cache' }); const tot = +r.headers.get('content-length') || 10.5e6; const rd = r.body.getReader(); const parts = []; let got = 0;
  for (;;) { const { done, value } = await rd.read(); if (done) break; parts.push(value); got += value.length; setLoad(Math.min(.45, got / tot * .45), 'downloading the level  ' + (got / 1e6).toFixed(1) + ' MB'); }
  const all = new Uint8Array(got); let o = 0; for (const c of parts) { all.set(c, o); o += c.length; } setLoad(.47, 'reading the level (' + (got / 1e6).toFixed(0) + ' MB, a few seconds on a phone)...'); await new Promise((r2) => setTimeout(r2, 60)); return JSON.parse(new TextDecoder().decode(all));
})();
hud.textContent = 'building ' + lvl.nodes.length + ' nodes, ' + Object.keys(lvl.meshes).length + ' meshes...';
await new Promise((r) => setTimeout(r, 30));
const MAT = {}, GEO = {};
const matOf = (id) => {
  if (!id) return null; if (MAT[id]) return MAT[id]; const d = lvl.materials[id]; let m;
  if (d.class === 'ShaderMaterial') {
    const code = d.shader_code || '', p = d.params || {};
    if (code.includes('GROUND') || code.includes('MOIRE INTERFERENCE')) m = groundMat(p);
    else if (code.includes('HORIZON BEND')) m = backdropMat(p);
    else if (code.includes('shader_type sky')) m = skyMat();
    else if (code.includes('float hue = fract(wp.z * 0.012')) m = vegMat();
    else if (code.includes('blend_add') || code.includes('smoothstep(0.22, 0.62, UV.y)')) m = quadMat(code, p);
    else m = new THREE.MeshBasicMaterial({ color: 0xff00ff });
  } else if (d.class === 'StandardMaterial3D') {
    if (d.unshaded && d.transparency > 0 && d.blend === 1) m = glowMat(d);          // Godot's "halo" / "ground" / "add" materials: additive, and the halo and pool carry a radial fade texture (a soft ball of light, not a square); the halo always faces the camera
    else if (d.unshaded) m = new THREE.MeshBasicMaterial({ color: rgb(d.albedo), vertexColors: !!d.vertex_color_albedo });
    else {
      m = new THREE.MeshStandardMaterial({ color: rgb(d.albedo), roughness: d.roughness, metalness: d.metallic, vertexColors: !!d.vertex_color_albedo });
      if (d.emission_on) { m.emissive = rgb(d.emission); m.emissiveIntensity = d.emission_energy; }
      if (d.vertex_color_albedo && d.emission_on && Math.abs(d.roughness - .45) < .01) {          // the molecule material: rim_enabled .55, rim_tint .35 and a glossy specular, so the atoms read round
        m.metalness = .15; m.roughness = .32; m.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_begin>', '{ float rim = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.5); totalEmissiveRadiance += mix(vec3(1.), diffuseColor.rgb, .35) * rim * .75; }' + String.fromCharCode(10) + '#include <lights_fragment_begin>'); };
      }
    }
    if (!m.isShaderMaterial && (d.transparency > 0 || d.albedo[3] < 0.99)) { m.transparent = true; m.opacity = d.albedo[3]; }
    if (d.cull_mode === 2) m.side = THREE.DoubleSide; else if (d.cull_mode === 1) m.side = THREE.BackSide;
  } else m = new THREE.MeshBasicMaterial({ color: 0xff00ff });
  return (MAT[id] = m);
};
function geoOf(id) {
  if (GEO[id]) return GEO[id]; const md = lvl.meshes[id]; const out = [];
  for (const s of md.surfaces) {
    const v = s.v; if (!v || !v.length || s.prim !== 3) continue;
    const g = new THREE.BufferGeometry(), pos = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { pos[i * 3] = v[i][0]; pos[i * 3 + 1] = v[i][1]; pos[i * 3 + 2] = v[i][2]; }
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    if (s.n) { const n = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { n[i * 3] = s.n[i][0]; n[i * 3 + 1] = s.n[i][1]; n[i * 3 + 2] = s.n[i][2]; } g.setAttribute('normal', new THREE.BufferAttribute(n, 3)); } else g.computeVertexNormals();
    { const c = new Float32Array(v.length * 3); if (s.c) for (let i = 0; i < v.length; i++) { c[i * 3] = s.c[i][0]; c[i * 3 + 1] = s.c[i][1]; c[i * 3 + 2] = s.c[i][2]; } else c.fill(1); g.setAttribute('color', new THREE.BufferAttribute(c, 3)); }
    if (s.uv) { const u = new Float32Array(v.length * 2); for (let i = 0; i < v.length; i++) { u[i * 2] = s.uv[i][0]; u[i * 2 + 1] = s.uv[i][1]; } g.setAttribute('uv', new THREE.BufferAttribute(u, 2)); }
    if (s.i && s.i.length) g.setIndex(s.i);
    out.push([g, s.mat]);
  }
  return (GEO[id] = out);
}
// ancestors must be visible; only the level's own world (the rig's meshes), not the UI or the player body
let VEGSRC = null; const REGN = {}; const TREES = new Map(); const vis = {}; const ground = []; let nMesh = 0, nInst = 0;
const NODE = new THREE.Group(); scene.add(NODE);
const AN = {}; const GRP = {}; const ANIM = []; const pathOf = {}; for (const n of lvl.nodes) pathOf[n.iid] = n.path;
for (const a of (lvl.anims || [])) {          // the pickups: the root bobs, "spin" turns about its own up axis, "extra" parts tumble (RunRig._animate_buffs)
  if (a.moving) continue; for (const k of ['n', 'spin']) if (a[k] && pathOf[a[k]]) AN[pathOf[a[k]]] = { a, k };
  (a.extra || []).forEach((e, i) => { if (pathOf[e]) AN[pathOf[e]] = { a, k: 'x' + i }; });
}
const nodeByPath = {}; for (const n of lvl.nodes) nodeByPath[n.path] = n;
function groupFor(path) {          // the nearest animated ancestor (or the node itself) as a THREE.Group, created on demand with its parent chain
  if (GRP[path]) return GRP[path]; const an = AN[path]; if (!an) return null;
  const g = new THREE.Group(); g.matrixAutoUpdate = false; g.userData = { an, base: mat4(nodeByPath[path].xf) }; g.matrix.copy(g.userData.base); GRP[path] = g;
  let par = null, pp = path; while (!par && pp.lastIndexOf('/') > 0) { pp = pp.slice(0, pp.lastIndexOf('/')); par = GRP[pp] || (AN[pp] ? groupFor(pp) : null); }
  if (par) { g.matrix.copy(par.userData.base.clone().invert().multiply(g.userData.base)); g.userData.pbase = par.userData.base; par.add(g); } else NODE.add(g); ANIM.push(g); return g;
}
function animParent(path) { let pp = path; while (pp.lastIndexOf('/') > 0) { pp = pp.slice(0, pp.lastIndexOf('/')); if (AN[pp]) return groupFor(pp); } return null; }
function animTick(age) {
  for (const g of ANIM) { const { an, base } = g.userData, a = an.a, ph = a.ph, par = g.parent && g.parent.userData && g.parent.userData.base ? g.parent.userData.base : null;
    const L = par ? par.clone().invert().multiply(base) : base.clone(); const p = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3(); L.decompose(p, q, sc);
    if (an.k === 'n') p.y += par ? 0 : 0, p.y = (par ? p.y : a.y) + Math.sin(age * 2.4 + ph) * .35 - (par ? 0 : 0);
    else if (an.k === 'spin') q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), age * (a.t === 'boost' ? 2.8 : 1.7) + ph);
    else if (an.k === 'x0') q.setFromAxisAngle(new THREE.Vector3(1, 0, 0), age * 1.4 + ph); else if (an.k === 'x1') q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), age * 1.9 + ph); else if (an.k === 'x2') q.setFromAxisAngle(new THREE.Vector3(0, 0, 1), age * 2.3 + ph);
    g.matrix.compose(p, q, sc); g.matrixWorldNeedsUpdate = true; }
} let ring = null;          // the mountain ring (the 1620-vertex vertex-coloured mesh): Godot moves it with the board so it never moves against the road
let bi = 0; for (const n of lvl.nodes) {
  if ((++bi & 31) === 0) { setLoad(.5 + .5 * bi / lvl.nodes.length, 'building the world  ' + Math.round(100 * bi / lvl.nodes.length) + '%'); await new Promise((r2) => setTimeout(r2, 0)); }
  vis[n.path] = n.vis !== false; const parts = n.path.split('/'); let ok = true; for (let k = 2; k < parts.length; k++) if (vis['/' + parts.slice(1, k + 1).join('/')] === false) { ok = false; break; }
  if (!ok || !n.path.startsWith('/MainLevel/RunRig') || n.path.includes('@Camera3D') || n.path.includes('SubViewport')) continue;
  if (n.class === 'MeshInstance3D' && n.mesh) {
    const gs = geoOf(n.mesh); const M4 = mat4(n.xf);
    for (const [g, sm] of gs) { const mat = matOf(n.mat_override || sm); if (!mat) continue; const m = new THREE.Mesh(g, mat); m.matrixAutoUpdate = false; m.matrix.copy(M4); m.frustumCulled = false; const ap = animParent(n.path); if (ap) { m.matrix.copy(ap.userData.base.clone().invert().multiply(M4)); ap.add(m); } else NODE.add(m); (REGN[n.name] || (REGN[n.name] = [])).push(m); nMesh++; if (lvl.materials[n.mat_override || sm]?.shader_code?.includes('MOIRE')) ground.push(m); if (g.attributes.position.count === 1620 && !ring) ring = m; }
  } else if (n.class === 'MultiMeshInstance3D' && n.mesh && n.count) {
    const gs = geoOf(n.mesh); const NM = mat4(n.xf);
    for (const [g, sm] of gs) {
      const mat = matOf(n.mat_override || sm); if (!mat) continue; const im = new THREE.InstancedMesh(g, mat, n.count); const t = new THREE.Matrix4();
      for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); im.setMatrixAt(i, t); if (n.cols) im.setColorAt(i, new THREE.Color().setRGB(n.cols[i][0], n.cols[i][1], n.cols[i][2], THREE.LinearSRGBColorSpace)); }
      im.frustumCulled = false; NODE.add(im); nMesh++; nInst += n.count; if (mat.userData && mat.userData.veg) { g.computeBoundingSphere(); const br = g.boundingSphere.radius; if (br > 2 && br < 9 && (!VEGSRC || n.count > VEGSRC.n)) VEGSRC = { g, mat, n: n.count }; } if (mat.userData && mat.userData.veg) for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); const k = Math.round(t.elements[12]) + ',' + Math.round(t.elements[14]); if (!TREES.has(k)) TREES.set(k, [t.elements[12], t.elements[14]]); }
    }
  }
}
// lights and environment from the dump
let ENV = null; let sunNode = lvl.nodes.find((n) => n.light && n.name === 'Sun'), envNode = lvl.nodes.find((n) => n.env);
if (sunNode) {
  const L = sunNode.light, sun = new THREE.DirectionalLight(rgb(L.color), L.energy * Math.PI), b = sunNode.xf, dir = new THREE.Vector3(-b[6], -b[7], -b[8]);          // Godot lights shine along the node's -Z
  sun.position.copy(dir.clone().multiplyScalar(-200)); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target);
}
if (envNode) {
  const e = envNode.env; scene.fog = new THREE.FogExp2(rgb(e.fog_light_color), e.fog_density); U.fogColor.value.copy(rgb(e.fog_light_color)); U.fogDensity.value = e.fog_density;
  scene.add(new THREE.HemisphereLight(new THREE.Color(0.0903, 0.0704, 0.1298), new THREE.Color(0.10, 0.01, 0.16), e.ambient_light_energy * Math.PI));          // Godot's sky ambient (Themes.gd sky(): cosine-weighted average of the sky over the upper and the lower hemisphere)
  renderer.toneMappingExposure = e.tonemap_exposure || 1.05; ENV = e;
}
const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), skyMat()); sky.frustumCulled = false; sky.renderOrder = -10; scene.add(sky);
// ---------------------------------------------------------------- fly
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0);
function groundY(x, z) { ray.set(new THREE.Vector3(x, 3000, z), down); const h = ray.intersectObjects(ground, false); return h.length ? h[0].point.y : null; }
const st = { z: lvl.start ? lvl.start[2] - 2 : -2, x: 0, speed: parseFloat(Q.get('speed') || '40'), paused: false, y: 0 };
addEventListener('keydown', (e) => { if (e.key === ' ' && !PLAY) st.paused = !st.paused; if (e.key === 'ArrowUp') st.speed += 10; if (e.key === 'ArrowDown') st.speed = Math.max(0, st.speed - 10); if (e.key === 'ArrowLeft') st.x -= 4; if (e.key === 'ArrowRight') st.x += 4; });

// ---------------------------------------------------------------- THE PICTURE PASS (the real shader from the game: the psychedelic branch of ThemeFX's pass, with the values the game had when the level was dumped)
// The scene is drawn into a float target, tonemapped like the game's filmic tonemap into display colours, and the game's own post math runs on those (warp, chromatic split, tracer ghosts, wash, punch, vignette).
const POST_ON = !Q.has('nopost');
const GLOWQ = { on: !Q.has('noglow'), samples: 0 }; const _gl = renderer.getContext(); const MSAA_OK = renderer.capabilities.isWebGL2 && !!(_gl.getExtension('EXT_color_buffer_float') || _gl.getExtension('EXT_color_buffer_half_float')) && !Q.has('nomsaa');
GLOWQ.samples = MSAA_OK ? parseInt(Q.get('msaa') || '4', 10) : 0;
const rtScene = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: true, samples: GLOWQ.samples }), rtG4 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtG8 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtG16 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtA = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtB = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false });
const qGeo = new THREE.BufferGeometry(); qGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3)); qGeo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
const QV = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }';
const feedM = new THREE.ShaderMaterial({ uniforms: { uScene: { value: null }, uPrev: { value: null } }, vertexShader: QV, depthTest: false, depthWrite: false, fragmentShader: `varying vec2 vUv; uniform sampler2D uScene, uPrev; void main(){ vec3 c = texture2D(uScene, vUv).rgb, p = texture2D(uPrev, vUv + (vUv - .5) * .004).rgb; if (any(equal(floatBitsToUint(c) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) c = vec3(0.); if (any(equal(floatBitsToUint(p) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) p = vec3(0.); gl_FragColor = vec4(max(c * .55, p * .86), 1.); }` });
const brightM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, thr: { value: 1 }, scl: { value: 2 }, bloom: { value: .1 }, expo: { value: 1.05 }, cap: { value: 12 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel; uniform float thr, scl, bloom, expo, cap; vec3 tap(vec2 o){ vec3 c0 = texture2D(uSrc, vUv + o * uTexel).rgb; if (any(equal(floatBitsToUint(c0) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) c0 = vec3(0.); vec3 c = min(max(c0, vec3(0.)) * expo, vec3(cap)); float m = max(c.r, max(c.g, c.b)); return c * max(smoothstep(thr, thr + scl, m), bloom); }
  void main(){ gl_FragColor = vec4((tap(vec2(-1., -1.)) + tap(vec2(1., -1.)) + tap(vec2(-1., 1.)) + tap(vec2(1., 1.))) * .25, 1.); }` });
const downM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel; void main(){ vec3 c = texture2D(uSrc, vUv + uTexel * vec2(-1., -1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(1., -1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(-1., 1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(1., 1.)).rgb; gl_FragColor = vec4(c * .25, 1.); }` });
const P = { amount: 0.8, breathe: 0.8, trip: 0, mA: new THREE.Vector3(), mB: new THREE.Vector3(), dmt: 0, buzz: 0, sharp: 0, k_warp: 1, k_pulse: 1, k_chroma: 1, k_trace: 1, k_punch: 1, k_wash: 0 };
const postM = new THREE.ShaderMaterial({ uniforms: { gA: { value: null }, gB: { value: null }, gC: { value: null }, glowI: { value: 0 }, lv4: { value: .8 }, lv8: { value: .4 }, lv16: { value: .1 }, tmWhite: { value: 1 }, bcs: { value: new THREE.Vector3(1, 1.1, 1.15) }, screen_tex: { value: null }, trail: { value: null }, TIME: U.uTime, exposure: { value: 1.05 }, amount: { value: P.amount }, breathe: { value: P.breathe }, trip: { value: 0 }, mA: { value: P.mA }, mB: { value: P.mB }, dmt: { value: 0 }, buzz: { value: 0 }, sharp: { value: 0 }, k_warp: { value: 1 }, k_pulse: { value: 1 }, k_chroma: { value: 1 }, k_trace: { value: 1 }, k_punch: { value: 1 }, k_wash: { value: 0 }, use_trail: { value: 1 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D screen_tex, trail; uniform float TIME, exposure, amount, breathe, trip, dmt, buzz, sharp, k_warp, k_pulse, k_chroma, k_trace, k_punch, k_wash, use_trail; uniform vec3 mA, mB; uniform sampler2D gA, gB, gC; uniform float glowI, lv4, lv8, lv16, tmWhite; uniform vec3 bcs; ${GLSL_HSV}
  float hable(float x){ const float A = .88, B = .6, C = .1, D = .2, E = .01, F = .3; return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F; }          // Godot 4 tonemap_filmic: Hable with exposure bias 2, divided by the curve at white
  vec3 filmic(vec3 c){ c = max(c, vec3(0.)); float w = hable(tmWhite); return vec3(hable(c.r), hable(c.g), hable(c.b)) / w; }
  vec3 srgb(vec3 c){ c = clamp(c, 0., 1.); return mix(c * 12.92, 1.055 * pow(c, vec3(1. / 2.4)) - .055, step(.0031308, c)); }
  vec3 bcsAdj(vec3 c){ c = mix(vec3(0.), c, bcs.x); c = mix(vec3(.5), c, bcs.y); return mix(vec3(dot(vec3(1.), c) * (1. / 3.)), c, bcs.z); }          // Godot's adjustment: brightness, contrast, saturation (saturation about the channel average)
  vec3 toDisp(vec3 hdr){ return bcsAdj(srgb(filmic(hdr))); }
  bool badf(float x){ return (floatBitsToUint(x) & 0x7F800000u) == 0x7F800000u; }          // NaN or Inf, tested on the bits (isnan() can be optimised away by a driver)
  bool bad(vec3 c){ return badf(c.x) || badf(c.y) || badf(c.z); }
  vec3 hdrAt(sampler2D t, vec2 u){ vec3 c = texture2D(t, u).rgb; if (bad(c)) { ivec2 sz = textureSize(t, 0); ivec2 ip = ivec2(u * vec2(sz)); vec3 a = vec3(0.); float n = 0.; for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) { vec3 sm = texelFetch(t, clamp(ip + ivec2(i, j), ivec2(0), sz - 1), 0).rgb; if (!bad(sm)) { a += sm; n += 1.; } } c = n > 0. ? a / n : vec3(0.); } return min(max(c, vec3(0.)), vec3(60.)); }          // (bilinear filtering smears a NaN texel over its neighbours, so the repair reads whole texels)
  vec3 disp(vec2 u){ vec3 h = hdrAt(screen_tex, u) * exposure; if (glowI > 0.) { vec3 g = (texture2D(gA, u).rgb * lv4 + texture2D(gB, u).rgb * lv8 + texture2D(gC, u).rgb * lv16) * glowI; h = max(h + g - h * g, vec3(0.)); } return toDisp(h); }
  void main(){ vec2 uv = vUv, c = uv - .5; float r = length(c), w = sin(TIME * .7 + r * 9.) * .0012 * k_warp * amount * breathe, tw = trip * trip;
    vec2 wuv = vec2(.5) + c + c * w * 2. + vec2(sin(uv.y * 14. + TIME) * .0008, 0.) * amount * breathe;
    float keep = mix(.35, 1., smoothstep(.05, .38, length(c * vec2(1., 1.25)))), pl = pow(max(sin(TIME * 6.), 0.), 3.);
    wuv += c * (mA.x * .002 * k_warp * keep * sin(TIME * .5 + r * 6.)); wuv += c * (mB.y * .0015 * k_warp * keep * sin(r * 34. - TIME * 3.));
    wuv = vec2(.5) + (wuv - vec2(.5)) * (1. - .006 * k_pulse * mB.z * pl * keep + .006 * k_pulse * dmt * sin(TIME * .8) * keep);
    float ca = (.003 + r * .012) * amount * k_chroma * (1. + trip * .5 + mA.z * .5 + dmt * .6);
    vec3 col = vec3(disp(wuv + c * ca).r, disp(wuv).g, disp(wuv - c * ca).b);
    vec3 old = toDisp(hdrAt(trail, uv) * exposure), cur = disp(uv), diff = max(old - cur * .92 - .02, vec3(0.));
    float m = clamp(dot(diff, vec3(.34)) * 3.2 * (1. + trip) * (.4 + .6 * smoothstep(.1, .45, r)), 0., 1.); vec3 ghost = hsv(fract(TIME * .12 + r * .9 + m * .5), .95, 1.) * m;
    col += ghost * .45 * amount * use_trail * k_trace;
    col = mix(col, col * hsv(fract(TIME * .05), .25, 1.1), .12 * amount); col = mix(col, col * hsv(fract(TIME * .14 + r * 1.2), .7, 1.3), tw * .55 * k_wash);
    col *= 1. + trip * .08; col *= 1. - .45 * smoothstep(.45, .95, r); col = mix(col, col * vec3(1.15, .95, .78), mA.x * .5); col *= 1. + mA.y * .12 * sin(TIME * .35); col *= 1. + mB.z * .30 * pl * keep;
    float lm = dot(col, vec3(.299, .587, .114)); col = mix(vec3(lm), col, 1. + (.45 + .6 * trip + .8 * mA.z + .5 * dmt) * k_punch);
    col += max(col - .55, vec3(0.)) * (.30 + .25 * buzz + 1. * sharp) * amount; col = max((col - .5) * (1. + .3 * sharp) + .5, vec3(0.)); col = mix(vec3(dot(col, vec3(.299, .587, .114))), col, 1. + .4 * sharp);
    col = max((col - .5) * (1.14 + .2 * trip + .2 * mA.y) + .5 - .05, vec3(0.));
    float mxc = max(max(col.r, col.g), col.b); if (mxc > .75) col *= (.75 + .25 * (1. - exp(-(mxc - .75) * 2.5))) / mxc; col *= .92;
    gl_FragColor = vec4(col, 1.); }` });
const qScene = new THREE.Scene(), qCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1), qMesh = new THREE.Mesh(qGeo, feedM); qMesh.frustumCulled = false; qScene.add(qMesh);
const TRIPV = parseFloat(Q.get('trip') || '0.8'); postM.uniforms.trip.value = TRIPV; postM.uniforms.buzz.value = TRIPV * .5; postM.uniforms.mA.value.set(0, .3 * TRIPV, .5 * TRIPV); postM.uniforms.dmt.value = .3 * TRIPV; postM.uniforms.k_wash.value = 1;
const GL = { intensity: 0, bloom: .1, thr: 1, scale: 2, cap: 12 };
if (ENV) { GL.intensity = ENV.glow_enabled === false ? 0 : (ENV.glow_intensity !== undefined ? ENV.glow_intensity : .35); GL.bloom = ENV.glow_bloom !== undefined ? ENV.glow_bloom : .1; GL.thr = ENV.glow_hdr_threshold !== undefined ? ENV.glow_hdr_threshold : 1; GL.scale = ENV.glow_hdr_scale !== undefined ? ENV.glow_hdr_scale : 2; GL.cap = ENV.glow_hdr_luminance_cap || 12;
  const pu = postM.uniforms; pu.lv4.value = ENV['glow_levels/2'] !== undefined ? ENV['glow_levels/2'] : .8; pu.lv8.value = ENV['glow_levels/3'] !== undefined ? ENV['glow_levels/3'] : .4; pu.lv16.value = ENV['glow_levels/4'] !== undefined ? ENV['glow_levels/4'] : .1;
  pu.bcs.value.set(ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_brightness || 1), ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_contrast || 1), ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_saturation || 1)); pu.tmWhite.value = ENV.tonemap_white || 1; brightM.uniforms.cap.value = GL.cap; }
let ping = 0; let MSAA_CHECK = 3;
function sizePost(w, h) { rtScene.setSize(w, h); rtA.setSize(w >> 1, h >> 1); rtB.setSize(w >> 1, h >> 1); rtG4.setSize(Math.max(2, w >> 2), Math.max(2, h >> 2)); rtG8.setSize(Math.max(2, w >> 3), Math.max(2, h >> 3)); rtG16.setSize(Math.max(2, w >> 4), Math.max(2, h >> 4)); PW = w; PHt = h; }
let PW = 4, PHt = 4;
function renderPost() {
  if (!POST_ON) { renderer.render(scene, camera); return; }
  renderer.setRenderTarget(rtScene); renderer.render(scene, camera);
  if (MSAA_CHECK > 0) { MSAA_CHECK--; if (rtScene.samples > 0 && _gl.checkFramebufferStatus(_gl.FRAMEBUFFER) !== _gl.FRAMEBUFFER_COMPLETE) { setSamples(0); GOV.log.push('msaa target incomplete: off'); } }          // (a phone whose GPU cannot multisample a half-float target falls back to none instead of a black screen)
  const src = ping ? rtB : rtA, dst = ping ? rtA : rtB; ping ^= 1; qMesh.material = feedM; feedM.uniforms.uScene.value = rtScene.texture; feedM.uniforms.uPrev.value = src.texture; renderer.setRenderTarget(dst); renderer.render(qScene, qCam);
  const useGlow = GLOWQ.on && ENV && ENV.glow_enabled !== false && GL.intensity > 0;
  if (useGlow) {          // Godot's glow: bright pass into 1/4 resolution (4x4 box), then 1/8 and 1/16 (each a 4x4 box of the one before)
    qMesh.material = brightM; brightM.uniforms.uSrc.value = rtScene.texture; brightM.uniforms.uTexel.value.set(1 / PW, 1 / PHt); brightM.uniforms.thr.value = GL.thr; brightM.uniforms.scl.value = GL.scale; brightM.uniforms.bloom.value = GL.bloom; brightM.uniforms.expo.value = renderer.toneMappingExposure; renderer.setRenderTarget(rtG4); renderer.render(qScene, qCam);
    qMesh.material = downM; downM.uniforms.uSrc.value = rtG4.texture; downM.uniforms.uTexel.value.set(1 / Math.max(2, PW >> 2), 1 / Math.max(2, PHt >> 2)); renderer.setRenderTarget(rtG8); renderer.render(qScene, qCam);
    downM.uniforms.uSrc.value = rtG8.texture; downM.uniforms.uTexel.value.set(1 / Math.max(2, PW >> 3), 1 / Math.max(2, PHt >> 3)); renderer.setRenderTarget(rtG16); renderer.render(qScene, qCam);
    postM.uniforms.gA.value = rtG4.texture; postM.uniforms.gB.value = rtG8.texture; postM.uniforms.gC.value = rtG16.texture;
  }
  postM.uniforms.glowI.value = useGlow ? GL.intensity : 0; postM.uniforms.exposure.value = renderer.toneMappingExposure;
  qMesh.material = postM; postM.uniforms.screen_tex.value = rtScene.texture; postM.uniforms.trail.value = dst.texture; renderer.setRenderTarget(null); renderer.render(qScene, qCam);
}
// QUALITY GOVERNOR: the picture steps down by itself, one notch at a time, whenever the frame time stays over ~21 ms (below 48 fps): glow off, then fewer MSAA samples, then a lower render resolution. (Godot's own tiers do the same, Lighting.gd: glow off at tier 2, the colour adjustment at tier 1.) ?nogov turns it off.
const GOV = { on: !Q.has('nogov') && !Q.has('shot'), ema: 16.7, lastNow: 0, since: performance.now() + 2500, step: 0, log: [] };
function setSamples(n) { if (!MSAA_OK) return; rtScene.samples = n; GLOWQ.samples = n; rtScene.dispose(); }
function setDpr(r) { renderer.setPixelRatio(r); resize(); }
const GOV_STEPS = [['glow off', () => { GLOWQ.on = false; }], ['msaa 2', () => setSamples(2)], ['dpr 1.25', () => setDpr(1.25)], ['msaa off', () => setSamples(0)], ['dpr 1.0', () => setDpr(1.0)], ['dpr 0.85', () => setDpr(.85)]];
function govTick(now) {
  if (!GOV.on || document.hidden) { GOV.lastNow = now; return; } const d = GOV.lastNow ? now - GOV.lastNow : 16.7; GOV.lastNow = now; if (d > 200) return;
  GOV.ema += (Math.min(d, 60) - GOV.ema) * .04; if (now < GOV.since || GOV.step >= GOV_STEPS.length) return;
  if (GOV.ema > 21) { const st2 = GOV_STEPS[GOV.step++]; st2[1](); GOV.log.push(st2[0] + ' @' + Math.round(GOV.ema) + 'ms'); GOV.since = now + 3000; GOV.ema = 16.7; }
}
function resize() { const w = innerWidth, h = innerHeight; renderer.setSize(w, h, false); sizePost(Math.floor(w * renderer.getPixelRatio()), Math.floor(h * renderer.getPixelRatio())); camera.aspect = w / h; camera.updateProjectionMatrix(); }
addEventListener('resize', resize); resize();
let last = performance.now(), fps = 0, acc = 0, frames = 0;
const SHOT = Q.has('shot') ? lvl.shots[parseInt(Q.get('shot'), 10) || 0] : null;
if (SHOT) { st.paused = true; const img = document.createElement('img'); img.src = './shots/godot_' + String(SHOT.i).padStart(2, '0') + '.png'; img.id = 'ref'; img.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;object-fit:fill;opacity:' + (Q.get('ref') || '0') + ';pointer-events:none;z-index:4'; document.body.appendChild(img); addEventListener('keydown', (e) => { if (e.key === 'g') img.style.opacity = img.style.opacity === '1' ? '0' : (img.style.opacity === '0.5' ? '1' : '0.5'); }); camera.fov = SHOT.fov; }

// ---------------------------------------------------------------- HEAD STEERING (?head): the tracker's yaw / roll / sideways face position, self-calibrated exactly as in main.js (online PCA axis, median = straight ahead, 90th percentile = a full turn, one-euro filter)
const HD = { on: Q.has('head'), cur: null, fb: [], ax: [.577, -.577, .577], ax0: [.577, -.577, .577], neu: 0, k: .9, lastFit: 0, vs: 0, vel: 0, s: 0, fc: 2.2, beta: .8, lead: .04, flip: 1, dead: .03, gain: 1.8, lost: true, t: 0 };
const HN3 = [8, 5, 3.5], hproj = (v) => (v[0] * HD.ax[0] + v[1] * HD.ax[1] + v[2] * HD.ax[2]) / (Math.abs(HD.ax[0]) + Math.abs(HD.ax[1]) + Math.abs(HD.ax[2]));
function hfit() {
  const fb = HD.fb, n = fb.length; if (n < 20) return; const mean = [0, 0, 0]; for (const v of fb) for (let i = 0; i < 3; i++) mean[i] += v[i] / n; let ax = HD.ax0.slice();
  if (n >= 150) { const Cv = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]; for (const v of fb) for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) Cv[i][j] += (v[i] - mean[i]) * (v[j] - mean[j]) / n;
    let a = [1, 1, 1]; for (let it = 0; it < 14; it++) { const b = [0, 1, 2].map((i) => Cv[i][0] * a[0] + Cv[i][1] * a[1] + Cv[i][2] * a[2]); const m = Math.hypot(...b) || 1; a = b.map((x) => x / m); }
    let d = a[0] * HD.ax0[0] + a[1] * HD.ax0[1] + a[2] * HD.ax0[2]; if (d < 0) { a = a.map((x) => -x); d = -d; } if (d > .5) ax = a; }
  HD.ax = HD.ax.map((x, i) => x * .7 + ax[i] * .3); const m = Math.hypot(...HD.ax); HD.ax = HD.ax.map((x) => x / m);
  const pr = fb.map(hproj).sort((x, y) => x - y), med = pr[Math.floor(pr.length / 2)], dev = pr.map((x) => Math.abs(x - med)).sort((x, y) => x - y), q90 = dev[Math.floor(dev.length * .9)];
  HD.neu = n < 40 ? med : HD.neu + (med - HD.neu) * .25; HD.k = HD.k + (.9 / Math.max(.3, Math.min(2.5, q90)) - HD.k) * (n < 40 ? 1 : .25);
}
function headStep(dt, now) {
  if (!HD.on || !HD.cur || HD.fb.length < 12) { window.__steer = 0; return; }
  if (now - HD.lastFit > 500) { HD.lastFit = now; hfit(); }
  const nv = [HD.cur[0] / HN3[0], HD.cur[1] / HN3[1], HD.cur[2] / HN3[2]]; let sv = HD.lost ? 0 : -HD.flip * (hproj(nv) - HD.neu) * HD.k; sv = Math.max(-1.3, Math.min(1.3, sv)); if (Math.abs(sv) < HD.dead) sv = 0;
  const dv = (sv - HD.vs) / Math.max(dt, .001); HD.vel += (dv - HD.vel) * .3; HD.vs = sv; const fc = HD.fc + HD.beta * Math.abs(HD.vel), a = 1 / (1 + 1 / (2 * Math.PI * fc * Math.max(dt, .001))); HD.s += (sv - HD.s) * a;
  window.__steer = Math.max(-1, Math.min(1, (HD.s + HD.vel * HD.lead) * HD.gain));
}
if (HD.on) {
  const ov = document.createElement('div'); ov.style.cssText = 'position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:#000a;z-index:20;color:#fff;font:700 28px ui-monospace,Consolas,monospace;cursor:pointer;text-align:center'; ov.innerHTML = 'TURN YOUR HEAD TO STEER<br><span style="font-size:16px">tap to start the camera</span>'; document.body.appendChild(ov);
  const bar = document.createElement('div'); bar.style.cssText = 'position:fixed;left:50%;bottom:30px;width:200px;height:8px;margin-left:-100px;border:1px solid #fff8;z-index:6'; const mk = document.createElement('div'); mk.style.cssText = 'position:absolute;top:-3px;width:6px;height:14px;background:#0ff;left:97px'; bar.appendChild(mk); document.body.appendChild(bar); window.__mk = mk;
  ov.onclick = async () => { ov.textContent = 'loading the tracker...'; try {
    const video = document.createElement('video'); video.playsInline = true; video.muted = true; video.autoplay = true; video.style.cssText = 'position:fixed;right:0;bottom:0;width:2px;height:2px;opacity:.01;pointer-events:none'; document.body.appendChild(video);
    const { Tracker } = await import('../stargaze/tracker.js'); const tr = new Tracker(video); tr.camW = 1280; tr.camH = 720; tr.fullRes = true; tr.useWorker = true;
    tr.onSteady = () => { const f = [tr.head ? tr.head.yaw * 57.2958 : 0, tr.head ? tr.head.roll * 57.2958 : 0, (tr.feat ? tr.feat[5] : 0) * 100]; HD.lost = false; HD.t = performance.now(); HD.cur = HD.cur ? HD.cur.map((c, i) => c + (f[i] - c) * .35) : f; HD.fb.push([f[0] / HN3[0], f[1] / HN3[1], f[2] / HN3[2]]); if (HD.fb.length > 900) HD.fb.shift(); };
    await tr.start((m) => { window.__gazeStatus = m; }, Q.get('fakecam')); ov.remove(); st.paused = false; } catch (e) { ov.textContent = 'no camera: ' + String((e && e.message) || e).slice(0, 80) + ' (keys A/D still work)'; setTimeout(() => ov.remove(), 3000); } };
}
// ---------------------------------------------------------------- PLAY: the board's physics from RunRig._physics_process, literally (hill pull, drag, grip with a carve cost, the steering and heading springs, the caps), plus what the level does to the board:
// trees and rocks (_collide, _crash), pickups (_collect_buffs, _take_buff), boost pads (_update_pads), rails (_feat_tick), and the ramps with their vortex (_update_ramps, _vortex_drive). Speeds are scaled up (?spd=) and the grip tightened (?turn=), everything else is Godot's.
const PLAY = Q.has('play'); const K = { l: 0, r: 0 };
const SPK = parseFloat(Q.get('spd') || '2.2'), STK = parseFloat(Q.get('turn') || '3');
const C = { G: 9.8 * SPK, GV: 9.8 * SPK, DRAG: .0024 / SPK, GRIP: 2.6 * STK, THETA_MAX: parseFloat(Q.get('theta') || '0.62'), MIN_SPEED: 14 * SPK, TRAIL_VMAX: 30 * SPK, TRAIL_SPEED: 23.5 * SPK, SPEED_CAP: 57 * SPK, SLED_R: 1, W_HALF: Math.min((lvl.W_HALF || 58), 138), PULL_RAMP: 3500, AIR_G_K: 2.1, JUMP_LAUNCH: 11 * SPK, VX_REACH: 130, VX_TRAIL: 37 * SPK, VX_ACCEL: 34 * SPK, JUMP_BLAST: 2, RAIL_H: .9, BOOST_S: 3 };
const PH = { vx: 0, vz: -20, heading: 0, steer: 0, sv: 0, hurt: 0, hits: 0, grounded: true, vy: 0, y: 0, ready: false, x: 0, z: 0, air_t: 0, gh_prev: 0, boost_t: 0, vxa: 0, shield: 0, score: 0, rail: null, rail_dx: 0, rail_z0: 0, rail_py: 0, rail_ok: false, rail_out: 0, rail_sp: 0, prevZ: 0, vx_spin: 0, picks: 0, rails: 0, jumps: 0, pads: 0, vlock: null, slide: 0, chain: 0, chainT: 0, chainBest: 0, landT: 0, mom: 0, grade: 0, lastGh: null, trip: 0, flow: 0, mixAdd: 0, cands: [], latch: null, latchDist: 1e9, mult: 0, vsnd: false };
addEventListener('keydown', (e) => { if (e.key === 'a' || e.key === 'ArrowLeft') K.l = 1; if (e.key === 'd' || e.key === 'ArrowRight') K.r = 1; });
addEventListener('keyup', (e) => { if (e.key === 'a' || e.key === 'ArrowLeft') K.l = 0; if (e.key === 'd' || e.key === 'ArrowRight') K.r = 0; });
function th(x, z) { const g = groundY(x, z); if (g === null) return PH.lastGh === null ? PH.y : PH.lastGh; PH.lastGh = g; return g; }          // (where there is no ground reading, the last one is used: a board must never land on thin air)
const sstep = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
// ---- the level's data (from the Godot dump)
const nameOf = (s) => String(s).replace(/^<node |>$/g, '');
const NBN = {}; for (const n of lvl.nodes) NBN[n.name] = n;
function hideTarget(o) { if (o.hideSelf) o.hideSelf(); else hideNode(o.n || o.gem); }
function hideNode(name) { const nd = NBN[nameOf(name)]; if (!nd) return; const g = GRP[nd.path]; if (g) g.visible = false; for (const m of (REGN[nd.name] || [])) m.visible = false; }
const ROWS = Object.values(lvl.rows), OGRID = new Map();
for (const r of ROWS) { const o = r.obs || []; for (let i = 0; i + 3 < o.length; i += 4) { const ob = { x: o[i], z: o[i + 1], r: o[i + 2], k: o[i + 3] }; const key = Math.floor(ob.x / 8) + ',' + Math.floor(ob.z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); } }
for (const t of TREES.values()) { const ob = { x: t[0], z: t[1], r: 1.5, k: 0 }; const key = Math.floor(ob.x / 8) + ',' + Math.floor(ob.z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); }
const BUFFS = ROWS.flatMap((r) => r.buffs || []), PADS = ROWS.flatMap((r) => r.pads || []), FEATS = ROWS.flatMap((r) => r.feats || []), RAILS = FEATS.filter((f) => f.kind === 'rail'), VXS = lvl.vx || [];
const TX = lvl.trailx || [], FEAT_OFF = lvl.feat_off || 15;
const trailX = (z) => { const i = Math.max(0, -z) / 6, a = Math.min(TX.length - 1, Math.floor(i)), b = Math.min(TX.length - 1, a + 1); return TX.length ? TX[a] + (TX[b] - TX[a]) * (i - a) : 0; };
const featX = (f, z) => f.kx !== undefined ? f.kx : trailX(z) + f.sd * FEAT_OFF;
const railY = (f, z) => th(featX(f, z), z) + (.15 + (C.RAIL_H - .15) * sstep(0, 4, f.za - z));
// ---- the vortex rings (RunRig._vortex_drive): spin about the ring's own axis, faster the nearer the ramp
const RINGS = []; { const byIid = {}; for (const n of lvl.nodes) byIid[n.iid] = n; for (const v of VXS) for (const r of v.rings) { const nd = byIid[r.iid]; if (!nd) continue; const ms = REGN[nd.name] || []; const e = nd.xf; for (const m of ms) RINGS.push({ m, v, r, p: [e[9], e[10], e[11]] }); } }
let toys = null;
const _mA = new THREE.Matrix4(), _mB = new THREE.Matrix4(), _mS = new THREE.Matrix4();
function ringsTick() {
  for (const q of RINGS) {
    const dz = PH.z - q.v.z; if (dz > 260 || dz < -40) continue; const gi = q.r.gi, near = 1 + 2.5 * sstep(90, 10, dz), sg = gi % 2 === 0 ? 1 : -1;
    let ang, sc; if (q.r.R !== undefined) { ang = PH.vx_spin * near * (1.2 + .5 * gi) * sg; sc = [q.r.R, q.r.R, q.r.R * .7]; } else { ang = PH.vx_spin * (2.2 + .7 * gi) * sg; sc = q.r.S || [1, 1, 1]; }
    _mA.makeRotationZ(ang); _mB.makeRotationX(Math.PI * .5); _mS.makeScale(sc[0], sc[1], sc[2]); q.m.matrix.copy(_mA).multiply(_mB).multiply(_mS); q.m.matrix.elements[12] = q.p[0]; q.m.matrix.elements[13] = q.p[1]; q.m.matrix.elements[14] = q.p[2];
  }
}
// ---- the HUD text and sound
const toastEl = document.createElement('div'); toastEl.style.cssText = 'position:fixed;left:0;right:0;top:22%;text-align:center;color:#fff;font:700 34px ui-monospace,Consolas,monospace;text-shadow:0 0 12px #f0f,0 0 4px #000;pointer-events:none;z-index:7;opacity:0;transition:opacity .25s'; document.body.appendChild(toastEl);
let toastT = 0; function toast(t, col) { toastEl.textContent = t; toastEl.style.color = col || '#fff'; toastEl.style.opacity = 1; toastT = 1.1; }
let AC = null, SFXG = null, grindN = null;
function ac() { if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); SFXG = AC.createGain(); SFXG.gain.value = .5; const lp = AC.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3200; SFXG.connect(lp); lp.connect(AC.destination); } catch (e) { } } if (AC && AC.state === 'suspended') AC.resume(); return AC; }
addEventListener('pointerdown', ac); addEventListener('keydown', ac);
function tone(f0, f1, dur, vol, type) { const a = ac(); if (!a) return; const o = a.createOscillator(), g = a.createGain(); o.type = type || 'sine'; o.frequency.setValueAtTime(f0, a.currentTime); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), a.currentTime + dur); g.gain.setValueAtTime(0, a.currentTime); g.gain.linearRampToValueAtTime(vol, a.currentTime + .015); g.gain.exponentialRampToValueAtTime(.0001, a.currentTime + dur); o.connect(g); g.connect(SFXG); o.start(); o.stop(a.currentTime + dur + .05); }
function noise(dur, vol, f, q) { const a = ac(); if (!a) return null; const n = Math.floor(a.sampleRate * dur), b = a.createBuffer(1, n, a.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; const s = a.createBufferSource(); s.buffer = b; const fl = a.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.value = f; fl.Q.value = q || 1; const g = a.createGain(); g.gain.setValueAtTime(vol, a.currentTime); g.gain.exponentialRampToValueAtTime(.0001, a.currentTime + dur); s.connect(fl); fl.connect(g); g.connect(SFXG); s.start(); return s; }
const SFX = {
  thwack: () => { noise(.25, .9, 500, .8); tone(140, 60, .2, .5); }, gong: () => { tone(220, 215, 1.4, .45); tone(331, 328, 1.1, .2); tone(553, 550, .8, .1); },
  pick: () => { tone(660, 990, .18, .3); setTimeout(() => tone(990, 1320, .2, .25), 70); }, orb: () => tone(880, 1180, .1, .15), pad: () => { tone(200, 900, .35, .35, 'triangle'); noise(.3, .3, 1800, 1.5); },
  land: () => { tone(110, 45, .25, .55); noise(.12, .25, 300, 1); }, blast: () => { tone(120, 700, .5, .45, 'sawtooth'); noise(.5, .5, 1200, .7); tone(60, 40, .6, .5); }, stretch: () => tone(150, 420, 1.1, .22, 'triangle'),
  snap: () => { tone(900, 300, .15, .35, 'square'); noise(.1, .3, 3000, 2); }, hurt: () => { tone(180, 60, .35, .5, 'sawtooth'); }, shield: () => { tone(500, 200, .4, .35); noise(.25, .3, 2500, 2); }, boing: () => tone(250, 520, .25, .3),
  grindOn: () => { const a = ac(); if (!a || grindN) return; const n = a.sampleRate * 1, b = a.createBuffer(1, n, a.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; const s = a.createBufferSource(); s.buffer = b; s.loop = true; const fl = a.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.value = 2200; fl.Q.value = 3; const g = a.createGain(); g.gain.value = .22; s.connect(fl); fl.connect(g); g.connect(SFXG); s.start(); grindN = { s, g, fl }; },
  grindOff: () => { if (grindN) { try { grindN.g.gain.setTargetAtTime(0, AC.currentTime, .05); grindN.s.stop(AC.currentTime + .3); } catch (e) { } grindN = null; } },
};
toys = createToys({ lvl, PH, th, SPK, hideNode, toast, SFX, REGN });
// ---- what hurts, and what helps
const CH = document.createElement('div'); CH.style.cssText = 'position:fixed;left:50%;top:150px;transform:translateX(-50%);text-align:center;color:#fff;font:700 22px ui-monospace,Consolas,monospace;text-shadow:0 0 10px #f0f,0 0 3px #000;pointer-events:none;z-index:7;opacity:0'; CH.innerHTML = '<div id="chn"></div><div style="width:120px;height:6px;margin:4px auto 0;border:1px solid #fff8;border-radius:3px;overflow:hidden"><div id="chb" style="height:100%;width:100%;background:linear-gradient(90deg,#f0f,#0ff)"></div></div>'; document.body.appendChild(CH);
function chainHit() {
  PH.chain++; const c = PH.chain; PH.chainT = 3.2 + .25 * Math.min(c, 12); PH.chainMax = Math.max(PH.chainMax || 0, c); PH.score += 25 * c;
  PH.boost_t = Math.max(PH.boost_t, Math.min(2.6, .5 + .14 * c)); PH.mom = Math.max(PH.mom, 1.5);
  const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), kick = Math.min(5, .8 + .35 * c) * SPK; PH.vx += fx * kick; PH.vz += fz * kick;
  tone(520 * Math.pow(1.0595, Math.min(c, 14) * 2), 520 * Math.pow(1.0595, Math.min(c, 14) * 2) * 1.5, .16, .22);
  if (c === 3 || c === 6 || c === 10 || c === 15 || c === 21 || c === 28) { toast('CHAIN x' + c + '!', '#f9f'); SFX.snap(); PH.vxa = Math.max(PH.vxa, .8); PH.score += 100 * c; }
}
function chainTick(dt) {
  if (PH.chain > 0) { PH.chainT -= dt; if (PH.chainT <= 0) { if (PH.chain >= 3) toast('CHAIN ENDED  x' + PH.chain, '#c9f'); PH.chain = 0; } }
  const on = PH.chain > 1 ? 1 : 0; CH.style.opacity = on; if (on) { document.getElementById('chn').textContent = 'CHAIN x' + PH.chain; document.getElementById('chb').style.width = Math.max(0, Math.min(100, PH.chainT / (3.2 + .25 * Math.min(PH.chain, 12)) * 100)) + '%'; }
}
// the gravity well: while a chain is alive the nearest target ahead pulls the board toward it (steering and a little forward drag), harder with a longer chain, and not at all against a hard nudge the other way
function wellSteer(sIn, dt) {
  if (PH.chain < 1 || PH.rail || !PH.grounded) return 0; let best = null, bd = 1e9;
  for (const c of PH.cands) { if (c.kind === 'ramp') continue; if (c.dz < 14 || c.dz > 150 || Math.abs(c.dx) > 42) continue; const sc = Math.abs(c.dx) + .12 * c.dz; if (sc < bd) { bd = sc; best = c; } }
  if (!best) return 0; const w = Math.min(.9, .16 * PH.chain), want = Math.max(-.9, Math.min(.9, (best.x - (PH.x + PH.vx * .45)) / 14)); if (Math.abs(sIn) > .5 && Math.sign(sIn) !== Math.sign(want)) return 0;
  if (best.dz < 70) { const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), tug = 9 * SPK * dt * w * (1 - best.dz / 70); PH.vx += fx * tug; PH.vz += fz * tug; }
  return w * want * (1 - .6 * Math.abs(sIn));
}
function crash(msg, kind) {
  if (PH.hurt > 0 || toys.active()) return;
  if (PH.shield > 0) { PH.shield = 0; PH.hurt = .8; toast('SHIELD BROKE', '#5df'); SFX.shield(); return; }
  PH.hits++; PH.hurt = .45; SFX[kind === 'rock' ? 'gong' : 'thwack'](); toast(msg, '#f66'); PH.score = Math.max(0, PH.score - 50); PH.rail = null; SFX.grindOff();          // (the bounce itself is done where the hit happens: obstacleStep keeps your speed and turns it back to open ground)
}
function takeBuff(b) {
  b.taken = true; hideTarget(b); PH.picks++; PH.score += 60; chainHit(); const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), sp0 = Math.hypot(PH.vx, PH.vz);
  if (b.t === 'boost') { PH.boost_t = C.BOOST_S; PH.vx += fx * 6 * SPK; PH.vz += fz * 6 * SPK; const v = Math.hypot(PH.vx, PH.vz), lim = Math.max(C.SPEED_CAP, sp0); if (v > lim) { PH.vx *= lim / v; PH.vz *= lim / v; } toast('CRYSTAL BOOST!', '#fa3'); }
  else if (b.t === 'shield') { PH.shield = 1; toast('ICE SHIELD!', '#5df'); } else if (b.t === 'mult') { PH.mult = 10; toast('SUGAR RUSH x2!', '#f6f'); } else { PH.score += 160; toast('CLUSTER!', '#f8c'); }
  if (b.t !== 'boost') { PH.vx += fx * 3 * SPK; PH.vz += fz * 3 * SPK; PH.boost_t = Math.max(PH.boost_t, .8); } SFX.pick(); SFX.snap(); PH.latch = null;
}
function collectStep() {
  const above = PH.y - th(PH.x, PH.z);
  for (const b of BUFFS) {
    if (Math.abs(b.z - PH.z) > 150) continue;
    for (const o of (b.orbs || [])) if (!o.taken && Math.abs(o.z - PH.z) < 2.4 && Math.abs(o.x - PH.x) < 2.6 && above < 5) { o.taken = true; hideNode(o.n); PH.score += 10; SFX.orb(); }
    if (b.taken) continue;
    if (b.kind === 'air') { if (Math.abs(b.z - PH.z) < 3.8 && Math.abs(b.x - PH.x) < 4.2 && above > .8 && Math.abs(b.y - PH.y) < 3.6) takeBuff(b); }
    else if (Math.abs(b.z - PH.z) < 3.2 && Math.abs(b.x - PH.x) < 3.6 && above < 6) takeBuff(b);
  }
  { const no = SPW.collectOrbs(PH, above); if (no) { PH.score += 10 * no; SFX.orb(); } }
  for (const m of PILLS) if (m.mine && !m.taken && Math.abs(m.z - PH.z) < 4 && Math.abs(m.x - PH.x) < 4.2 && above < 8) { m.taken = true; m.hideSelf(); PH.mols = (PH.mols || 0) + 1; PH.molSet = PH.molSet || {}; const first = !PH.molSet[m.id]; PH.molSet[m.id] = 1; PH.score += first ? 1500 : 500; PH.boost_t = Math.max(PH.boost_t, 2); chainHit(); chainHit(); toast((m.name || m.id).toUpperCase() + (first ? '  NEW  ' + Object.keys(PH.molSet).length + ' OF 6' : '  FOUND'), '#8ff'); SFX.pick(); setTimeout(() => SFX.pick(), 130); setTimeout(() => SFX.pick(), 260); }
  const low = PH.grounded || above <= 2.5;
  if (low || above <= 16) for (const p of PADS) {
    if (p.used || p.lk || !low || Math.abs(p.z - PH.z) > 230) continue;
    if (Math.abs(p.z - 2.2 - PH.z) < 3.6 && Math.abs(p.x - PH.x) < 4.6) {
      p.used = true; hideTarget(p); PH.pads++; PH.boost_t = Math.max(PH.boost_t, 1.8); const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), sp0 = Math.hypot(PH.vx, PH.vz);
      PH.vx += fx * 7 * SPK; PH.vz += fz * 7 * SPK; PH.vxa = Math.max(PH.vxa, 1.4); const v = Math.hypot(PH.vx, PH.vz), lim = Math.max(C.SPEED_CAP, sp0) + 6 * SPK; if (v > lim) { PH.vx *= lim / v; PH.vz *= lim / v; }
      SFX.pad(); toast(p.epic ? 'LAUNCH PAD' : 'BOOST PAD', '#fb4'); PH.score += 40; chainHit();
    }
  }
}
function obstacleStep(px, pz) {
  if (PH.hurt > 0) return; const above = PH.y - th(PH.x, PH.z), cx = Math.floor(PH.x / 8), cz = Math.floor(PH.z / 8), sx = PH.x - px, sz = PH.z - pz, sl = sx * sx + sz * sz;
  for (let i = -2; i <= 2; i++) for (let j = -2; j <= 2; j++) {
    const a = OGRID.get((cx + i) + ',' + (cz + j)); if (!a) continue;
    for (const o of a) {
      let t = sl > 1e-6 ? ((o.x - px) * sx + (o.z - pz) * sz) / sl : 1; t = Math.max(0, Math.min(1, t)); const qx = px + sx * t, qz = pz + sz * t, R = o.r + C.SLED_R, ex = qx - o.x, ez = qz - o.z;
      if (ex * ex + ez * ez < R * R && above < (o.k < .5 ? 7 : 3)) {
        const dx = ex || .01, dz = ez || .01;
        const d = Math.hypot(dx, dz) || 1, nx = dx / d, nz = dz / d; PH.x = o.x + nx * (R + .1); PH.z = o.z + nz * (R + .1); if (PH.grounded) { PH.y = th(PH.x, PH.z); PH.gh_prev = PH.y; }
        const sp0 = Math.hypot(PH.vx, PH.vz), dp = PH.vx * nx + PH.vz * nz; let bx = PH.vx - (1 + .35) * Math.min(dp, 0) * nx, bz = PH.vz - (1 + .35) * Math.min(dp, 0) * nz;          // reflect: slide along the trunk and be pushed away from it
        bx += Math.sign(trailX(PH.z) - PH.x) * .18 * sp0; bz = Math.min(bz, -.55 * sp0);          // and a nudge back toward the path, and always still going down the hill
        const nn = Math.hypot(bx, bz) || 1, keep = .9 * sp0; PH.vx = bx / nn * keep; PH.vz = bz / nn * keep; PH.heading *= .5; PH.steer *= .5; PH.sv = 0; PH.mom = Math.max(PH.mom, 1.5);
        crash(o.k < .5 ? 'TREE!' : 'ROCK!', o.k < .5 ? 'tree' : 'rock'); return;
      }
    }
  }
}
function railStep(dt, sIn) {
  if (PH.rail) {
    const f = PH.rail; if (PH.hurt > 0) { PH.rail = null; f.done = true; SFX.grindOff(); return; }
    const off = (how) => {
      const m = PH.rail_z0 - PH.z; PH.rail = null; f.done = true; SFX.grindOff(); if (how !== 'drop') { PH.grounded = false; PH.air_t = 0; if (how === 'end') PH.vy += 3.2; }
      if (m < 6) return; PH.rails++; PH.score += Math.floor(m * 7); chainHit(); const sl = Math.max(0, Math.min(1, m / 36)); toast('RAIL  ' + Math.floor(m) + ' m', '#7ef'); SFX.pick();
      if (sl > .2 && how !== 'drop') { PH.vz -= (3 + 13 * sl) * SPK * .6; PH.boost_t = Math.max(PH.boost_t, .7 + 1.8 * sl); PH.vxa = .7; SFX.snap(); if (sl > .5) toast('SLINGSHOT!', '#7ef'); }
    };
    if (PH.z <= f.zb) { if (f.chain) toys.payoff(); off('end'); return; }
    PH.rail_out = (sIn * f.sd < -.8) ? PH.rail_out + dt : 0; if (PH.rail_out > .3) { off('drop'); return; }
    const slope = (featX(f, PH.z - 1) - featX(f, PH.z + 1)) * .5; PH.rail_dx += PH.slide * dt; PH.slide *= Math.exp(-dt / .1); PH.rail_dx *= Math.exp(-dt / .15);
    PH.x = featX(f, PH.z) + PH.rail_dx; const ry = railY(f, PH.z); PH.vy = PH.rail_ok ? Math.max(-40, Math.min(10, (ry - PH.rail_py) / Math.max(dt, 1e-4))) : PH.vy; PH.rail_py = ry; PH.rail_ok = true; PH.y = ry;
    PH.vx = slope * -PH.vz; PH.heading = Math.atan(slope); PH.steer = Math.max(-1, Math.min(1, PH.heading / C.THETA_MAX)); PH.sv = 0; PH.grounded = true;
    if (grindN) grindN.fl.frequency.value = 1800 + Math.hypot(PH.vx, PH.vz) * 14; return;
  }
  for (const f of RAILS) {
    if (f.done) continue; if (PH.z < f.zb + 5) { f.done = true; continue; }
    if (PH.grounded && PH.z < f.za + 6) { const wdx = featX(f, Math.max(f.zb, Math.min(f.za, PH.z))) - PH.x; if (Math.abs(wdx) < 7 && Math.abs(wdx) > .3) PH.x += Math.sign(wdx) * Math.min(Math.abs(wdx), (2.5 + 9 * (1 - Math.abs(wdx) / 7)) * dt * 2); }
    if (PH.hurt > 0 || PH.z > f.za + .5) continue; const nt = PH.z > f.za - 10;
    if (Math.abs(PH.x - featX(f, PH.z)) < (nt ? 2.6 : 1.3) && PH.y - railY(f, PH.z) < 2) { PH.rail = f; PH.rail_z0 = PH.z; PH.rail_dx = PH.x - featX(f, PH.z); PH.slide = PH.vx; PH.rail_ok = false; PH.rail_out = 0; SFX.grindOn(); toast('GRIND', '#7ef'); break; }
  }
}
function vortexStep(dt, steerIn) {
  PH.vx_spin += dt; let active = false, lockX = null;
  for (const k of VXS) {
    if (!k.trail) continue; const kz = k.z, kx = k.x, lipz = kz - k.len, half = k.w * .5, dxk = kx - PH.x, onIt = PH.z < kz + 4 && Math.abs(dxk) < half + 1.5;
    const wantSide = Math.sign(steerIn) === Math.sign(dxk) && Math.abs(steerIn) > .15;
    if (PH.grounded && !PH.rail && PH.z < kz + C.VX_REACH + 14 && PH.z > lipz + 1 && (onIt || Math.abs(dxk) < half + 16 || (wantSide && Math.abs(dxk) < half + 80))) {
      lockX = kx; active = true; if (!PH.vsnd) { PH.vsnd = true; SFX.stretch(); }
      const t = Math.max(0, Math.min(1, (kz + C.VX_REACH - PH.z) / (C.VX_REACH + k.len))); PH.x += Math.max(-34, Math.min(34, dxk * 7)) * dt * sstep(0, .12, t);
      const fsp = -PH.vz; if (fsp < C.VX_TRAIL) PH.vz -= Math.min(C.VX_ACCEL * (PH.z < kz ? .9 : .6) * dt, C.VX_TRAIL - fsp);
    }
    if (PH.prevZ > lipz && PH.z <= lipz && Math.abs(PH.x - kx) < half) {          // the lip: the swirl lets go (RunRig._update_ramps, crossed): a hard blast off it
      PH.vy += C.JUMP_BLAST; PH.boost_t = Math.max(PH.boost_t, 1.2); PH.jumps++; PH.score += 150; chainHit(); toast(k.super ? 'SUPER AIR!' : 'BLAST!', '#f8f'); SFX.blast(); if (k.super) { PH.vy += 5; PH.boost_t = 2.4; } PH.vxa = Math.max(PH.vxa, .45);
    }
  }
  PH.vlock = lockX; if (active) PH.vxa = Math.max(PH.vxa, .45); else { if (PH.grounded) PH.vxa = Math.max(PH.vxa - dt, 0); PH.vsnd = false; }
}
const ramp = () => .5 + .5 * sstep(0, 1500, -PH.z) + .12 * Math.min(PH.lap || 0, 4);
const MS = { buf: [], t0: performance.now(), q: [], last: 0, flips: 0, lastSign: 0, lagMs: 0, sw: 0, ll: 0 };
const scope = document.createElement('canvas'); scope.width = 360; scope.height = 120; scope.style.cssText = 'position:fixed;left:8px;bottom:36px;width:300px;height:100px;background:#0008;border:1px solid #fff4;z-index:8;pointer-events:none'; if (!Q.has('noscope')) document.body.appendChild(scope);
const sgx = scope.getContext('2d'); const txt = document.createElement('div'); txt.style.cssText = 'position:fixed;left:8px;bottom:140px;color:#cfe;font:11px/1.35 ui-monospace,Consolas,monospace;z-index:8;pointer-events:none;white-space:pre;text-shadow:0 0 3px #000'; document.body.appendChild(txt);
function measure(dt, sIn, steer) {
  const now = performance.now(); const lv = PH.vx * Math.cos(PH.heading) + PH.vz * Math.sin(PH.heading);          // sideways speed across the board's heading
  MS.buf.push([now, window.__steer || 0, sIn, steer, PH.heading, PH.x, PH.vx, Math.hypot(PH.vx, PH.vz), PH.z, PH.hurt > 0 ? 1 : 0]); if (MS.buf.length > 600) MS.buf.shift();
  const sg = Math.abs(window.__steer || 0) > .15 ? Math.sign(window.__steer) : 0; if (sg && sg !== MS.lastSign) { if (MS.lastSign) MS.flips++; MS.lastSign = sg; }
  if (now - MS.last > 250) {
    MS.last = now; const b = MS.buf, n = b.length; let best = 0, bl = 0;
    if (n > 120) { for (let lag = 0; lag <= 24; lag += 2) { let c = 0, m = 0; for (let i = lag; i < n; i++) { c += b[i - lag][2] * b[i][6]; m++; } c /= m; if (c > best) { best = c; bl = lag; } } MS.lagMs = bl * (n > 1 ? (b[n - 1][0] - b[0][0]) / (n - 1) : 16); }
    const secs = (now - MS.t0) / 1000; MS.sw = MS.flips / Math.max(secs, 1);
    txt.textContent = 'head ' + (window.__steer || 0).toFixed(2) + '  steer ' + steer.toFixed(2) + '  heading ' + (PH.heading * 57.3).toFixed(0) + 'deg\nside-to-side flips ' + MS.flips + '  (' + MS.sw.toFixed(2) + '/s)  response lag ~' + MS.lagMs.toFixed(0) + ' ms\nspeed ' + (Math.hypot(PH.vx, PH.vz) * 3.6).toFixed(0) + ' km/h  lateral ' + lv.toFixed(1) + ' m/s';
    sgx.clearRect(0, 0, 360, 120); sgx.strokeStyle = '#fff3'; sgx.beginPath(); sgx.moveTo(0, 60); sgx.lineTo(360, 60); sgx.stroke();
    const draw = (col, k, sc) => { sgx.strokeStyle = col; sgx.beginPath(); const t1 = b[n - 1] ? b[n - 1][0] : now; for (let i = 0; i < n; i++) { const x = 360 - (t1 - b[i][0]) / 8000 * 360, y = 60 - b[i][k] * sc; if (i === 0) sgx.moveTo(x, y); else sgx.lineTo(x, y); } sgx.stroke(); };
    draw('#0ff', 1, 50); draw('#ff0', 3, 50); draw('#f6f', 4, 50);
  }
  if (now - (MS.sent || 0) > 5000 && !Q.has('noshare') && MS.buf.length > 20) {          // numbers only, to the same anonymous log as the other games (every 5 s)
    MS.sent = now; const rows = MS.buf.filter((_, i) => i % 3 === 0).map((r) => r.map((v, i) => +(i === 0 ? (v - MS.t0) / 1000 : v).toFixed(3)));
    try { fetch('./log.php', { method: 'POST', body: JSON.stringify({ app: 'gv', kind: 'steer', cols: 't head sIn steer heading x vx speed z hurt', flips: MS.flips, lag: Math.round(MS.lagMs), rows: rows.slice(-90) }), keepalive: true }).catch(() => { }); } catch (e) { }
  }
}
// ---------------------------------------------------------------- THE GOAL MOLECULE: the next molecule on the course is shown at the top of the screen as a spinning ball-and-stick icon, with a downward triangle that tracks, live, where it is coming from (at the screen edge with an arrow when it is off to the side)
const PILLS = ROWS.flatMap((r) => (r.toys || []).filter((t) => t.kind === 'pill')).sort((a, b) => b.z - a.z);
const GOAL = document.createElement('div'); GOAL.style.cssText = 'position:fixed;top:6px;left:50%;width:92px;transform:translateX(-50%);text-align:center;pointer-events:none;z-index:8;display:none;font:700 12px ui-monospace,Consolas,monospace;color:#fff;text-shadow:0 0 6px #000';
const GC = document.createElement('canvas'); GC.width = 160; GC.height = 160; GC.style.cssText = 'width:96px;height:96px;display:block;margin:0 auto;filter:drop-shadow(0 0 8px #fff8)'; const GT = document.createElement('div'); GT.style.cssText = 'margin-top:-6px'; const GA = document.createElement('div'); GA.style.cssText = 'width:0;height:0;margin:2px auto 0;border-left:12px solid transparent;border-right:12px solid transparent;border-top:18px solid #fff;filter:drop-shadow(0 0 6px #fff)';
GOAL.appendChild(GC); GOAL.appendChild(GT); GOAL.appendChild(GA); document.body.appendChild(GOAL); const GX = GC.getContext('2d');
const ELC = { H: [1, 1, 1, .5], C: null, N: [.4, .6, 1, .8], O: [1, .3, .3, .8], S: [1, .9, .3, 1.05], Br: [.8, .4, .2, 1.15] };
function drawMol(mol, t) {
  GX.clearRect(0, 0, 160, 160); const A = mol.atoms, ca = Math.cos(t * .9), sa = Math.sin(t * .9), tl = .35, ct = Math.cos(tl), st = Math.sin(tl); let cx = 0, cy = 0, cz = 0; for (const a of A) { cx += a[1]; cy += a[2]; cz += a[3]; } cx /= A.length; cy /= A.length; cz /= A.length;
  const P = A.map((a) => { const x = a[1] - cx, y = a[2] - cy, z = a[3] - cz; const x1 = x * ca + z * sa, z1 = -x * sa + z * ca; const y1 = y * ct - z1 * st, z2 = y * st + z1 * ct; return [x1, y1, z2]; });
  const sc = 17, pc = (q) => [80 + q[0] * sc, 80 - q[1] * sc]; GX.lineCap = 'round';
  const items = []; for (const b of mol.bonds) items.push({ z: (P[b[0]][2] + P[b[1]][2]) / 2, b }); A.forEach((a, i) => items.push({ z: P[i][2], i })); items.sort((u, v) => u.z - v.z);
  for (const it of items) {
    if (it.b) { const a = pc(P[it.b[0]]), c = pc(P[it.b[1]]); GX.strokeStyle = '#ffffffdd'; GX.lineWidth = it.b[2] === 2 ? 7 : 4.5; GX.beginPath(); GX.moveTo(a[0], a[1]); GX.lineTo(c[0], c[1]); GX.stroke(); }
    else { const a = A[it.i], e = ELC[a[0]] || [1, 1, 1, .8], col = e[0] === undefined || e === null ? mol.c : e, c = pc(P[it.i]), r = (a[0] === 'H' ? .5 : a[0] === 'C' ? .75 : e[3]) * 10 * (1 + P[it.i][2] * .03);
      const rgb = a[0] === 'C' ? mol.c : [e[0], e[1], e[2]]; const g = GX.createRadialGradient(c[0] - r * .3, c[1] - r * .3, r * .1, c[0], c[1], r); g.addColorStop(0, 'rgba(255,255,255,.95)'); g.addColorStop(.35, 'rgb(' + rgb.map((v) => Math.round(v * 255)).join(',') + ')'); g.addColorStop(1, 'rgb(' + rgb.map((v) => Math.round(v * 150)).join(',') + ')'); GX.fillStyle = g; GX.beginPath(); GX.arc(c[0], c[1], r, 0, 6.2832); GX.fill(); }
  }
}
let goalIdx = -1;
function goalTick(time) {
  let tgt = null; for (const p of PILLS) if (!(p.taken || p.t > 1e14) && p.z < PH.z - 4) { tgt = p; break; }          // the nearest one still ahead
  if (!PLAY || st.paused || !tgt || PH.z - tgt.z > 900) { GOAL.style.display = 'none'; return; }
  const mol = MOLS[tgt.id]; if (!mol) { GOAL.style.display = 'none'; return; }
  _rv.set(tgt.x, th(tgt.x, tgt.z) + 3, tgt.z).project(camera); const W = innerWidth; let px = (_rv.x * .5 + .5) * W, off = 0; if (_rv.z > 1) { px = _rv.x > 0 ? 0 : W; off = _rv.x > 0 ? -1 : 1; } if (px < 50) { px = 50; off = off || -1; } if (px > W - 50) { px = W - 50; off = off || 1; }
  GOAL.style.display = 'block'; GOAL.style.left = px + 'px'; const col = 'rgb(' + mol.c.map((v) => Math.round(v * 255)).join(',') + ')'; GA.style.borderTopColor = col; GA.style.filter = 'drop-shadow(0 0 6px ' + col + ')';
  const dz = PH.z - tgt.z; GT.textContent = (off < 0 ? '< ' : '') + mol.name + '  ' + Math.round(dz) + ' m' + (off > 0 ? ' >' : ''); drawMol(mol, time * .001);
}

// ---------------------------------------------------------------- BEACONS: every target is a tall coloured column of light, drawn through the fog, so it can be picked out from far up the slope against the scenery and the road. Colour says what it is (orange boost, cyan shield and rails, magenta sugar and ramps, pink donut, gold pads); the molecule is the tallest, widest, and pulses.
const BCOL = { boost: [1, .55, .1], shield: [.3, .9, 1], mult: [1, .35, 1], donut: [1, .45, .75], pad: [1, .8, .2], rail: [.3, 1, .95], ramp: [1, .3, 1], mol: [1, 1, 1] };
const bGeo = new THREE.PlaneGeometry(1, 1); bGeo.translate(0, .5, 0);
const BEAC = []; const BMAT = {};
function mkBeacon(o, x, z, y, kind, w, h, col) {
  const c = col || BCOL[kind] || [1, 1, 1];
  const bkey = kind + c.join(',') + w + h; const m = new THREE.Mesh(bGeo, BMAT[bkey] || (BMAT[bkey] = new THREE.ShaderMaterial({ uniforms: { col: { value: new THREE.Vector3(c[0], c[1], c[2]) }, uW: { value: w }, uH: { value: h }, uP: { value: 0 }, uTime: U.uTime }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    vertexShader: `varying vec2 vUv; uniform float uW, uH; void main(){ vUv = uv; vec3 o = modelMatrix[3].xyz; vec3 toC = cameraPosition - o; toC.y = 0.; vec3 r = normalize(cross(vec3(0., 1., 0.), toC + vec3(1e-4))); vec3 wp = o + r * position.x * uW + vec3(0., position.y * uH, 0.); gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.); }`,
    fragmentShader: `varying vec2 vUv; uniform vec3 col; uniform float uP, uTime; void main(){ float ex = 1. - abs(vUv.x - .5) * 2.; float core = pow(ex, 2.2); float fall = pow(1. - vUv.y, 1.3) * smoothstep(0., .04, vUv.y); float pulse = .8 + .2 * sin(uTime * 4. + vUv.y * 9. - uP * 6.); gl_FragColor = vec4(col * (.55 + .9 * core), (core * .85 + ex * .15) * fall * pulse); }` })));
  m.position.set(x, y, z); m.frustumCulled = false; m.renderOrder = 5; scene.add(m); BEAC.push({ m, o, kind, z });
}
const _bAt = (x, z) => { const g = groundY(x, z); return g === null ? 0 : g; };
for (const b of BUFFS) mkBeacon(b, b.x, b.z, (b.y !== undefined ? b.y - 1.9 : _bAt(b.x, b.z)), b.t === 'boost' ? 'boost' : b.t === 'shield' ? 'shield' : b.t === 'mult' ? 'mult' : 'donut', 3.2, 48);
for (const pd of PADS) mkBeacon(pd, pd.x, pd.z, _bAt(pd.x, pd.z), 'pad', 3, 38);
for (const f of RAILS) mkBeacon(f, featX(f, f.za), f.za, _bAt(featX(f, f.za), f.za), 'rail', 3, 44);
for (const k of VXS) if (k.trail) mkBeacon(k, k.x, k.z, _bAt(k.x, k.z), 'ramp', 5, 64);
for (const mm of PILLS) { const mo = MOLS[mm.id]; mkBeacon(mm, mm.x, mm.z, _bAt(mm.x, mm.z), 'mol', 7, 160, mo ? mo.c : null); }
let molPing = 0;
function beaconTick(time) {
  for (const B of BEAC) { const o = B.o; const gone = o.taken || o.used || o.done || o.hidden || o.t > 1e14; B.m.visible = !gone && PLAY && Math.abs(B.z - PH.z) < 340;  }
  // the molecule ahead pings, faster the closer it gets (a quiet two-note tick), so it is heard before it is seen
  const tg = PILLS.find((p) => !(p.taken || p.t > 1e14) && p.z < PH.z - 4);
  if (PLAY && !st.paused && tg) { const d = PH.z - tg.z; if (d < 900) { const period = Math.max(.35, d / 700); if (time / 1000 - molPing > period) { molPing = time / 1000; tone(740 + 500 * (1 - d / 900), 740 + 500 * (1 - d / 900), .09, .12); } } }
}
const addObsG = (x, z, r) => { const ob = { x, z, r, k: 0 }; const key = Math.floor(x / 8) + ',' + Math.floor(z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); };
const SPW = createSpawn({ scene, MOLS, MOL_ORDER, th, railY, BUFFS, PADS, RAILS, PILLS, addObs: addObsG, vegSrc: VEGSRC, trailX,
  onTarget: (o, kind) => { if (kind === 'pad') mkBeacon(o, o.x, o.z, th(o.x, o.z), 'pad', 3, 38); else if (kind === 'rail') mkBeacon(o, o.kx, o.za, th(o.kx, o.za), 'rail', 3, 44); else if (kind === 'mol') { const mo = MOLS[o.id]; mkBeacon(o, o.x, o.z, th(o.x, o.z), 'mol', 7, 160, mo ? mo.c : null); } else mkBeacon(o, o.x, o.z, o.y - 1.9, kind, 3.2, 48); } });
PH.lap = 0; const WORLD_END = -(TX.length * 6) + 150;
function buildWorld() { const r = SPW.build(lvl.seed || 7, WORLD_END, Math.min(C.W_HALF - 8, 120), PH.lap); PILLS.sort((a, b) => b.z - a.z); window.__world = r; return r; }
if (PLAY) buildWorld();
const RET = document.createElement('div'); RET.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:6;overflow:hidden'; document.body.appendChild(RET);
const retEls = []; const _rv = new THREE.Vector3();
function retEl(i) { if (!retEls[i]) { const e = document.createElement('div'); e.style.cssText = 'position:absolute;border-radius:50%;transform:translate(-50%,-50%);box-sizing:border-box'; RET.appendChild(e); retEls[i] = e; } return retEls[i]; }
function reticleTick(time) {
  let n = 0; const W = innerWidth, H = innerHeight;
  const place = (c, locked) => {
    const y = (c.y !== null && c.y !== undefined ? c.y : th(c.x, c.z)) + 1.6; _rv.set(c.x, y, c.z).project(camera); if (_rv.z > 1 || _rv.z < -1) return; const px = (_rv.x * .5 + .5) * W, py = (-_rv.y * .5 + .5) * H; if (px < -40 || px > W + 40 || py < -40 || py > H + 40) return;
    const e = retEl(n++); e.style.display = 'block'; e.style.left = px + 'px'; e.style.top = py + 'px';
    if (locked) { const pr = 1 + .12 * Math.sin(time * .008), sz = Math.max(46, Math.min(110, 5200 / Math.max(c.dz, 30))) * pr; e.style.width = sz + 'px'; e.style.height = sz + 'px'; e.style.border = '3px solid #3f6'; e.style.boxShadow = '0 0 14px #3f6, inset 0 0 12px #3f68'; e.style.background = 'transparent'; e.style.opacity = '1'; e.style.borderRadius = '50%'; }
    else { const sz = Math.max(10, Math.min(30, 2200 / Math.max(c.dz, 30))); e.style.width = sz + 'px'; e.style.height = sz + 'px'; e.style.border = '2px solid #3f6a'; e.style.boxShadow = 'none'; e.style.background = 'transparent'; e.style.opacity = '.7'; e.style.borderRadius = '30%'; }
  };
  if (PLAY && !st.paused) { for (const c of PH.cands) if (!PH.latch || c.o !== PH.latch.o) place(c, false); if (PH.latch) place({ x: PH.latch.x, y: PH.latch.y, z: PH.latch.z, dz: PH.latchDist }, true); }
  for (let i = n; i < retEls.length; i++) retEls[i].style.display = 'none';
}
function playStep(dt) {
  headStep(dt, performance.now()); if (HD.on && performance.now() - HD.t > 600) HD.lost = true; if (window.__mk) window.__mk.style.left = (97 + (window.__steer || 0) * 97) + 'px';
  if (!PH.ready) { PH.x = 0; PH.z = st.z; PH.y = th(0, PH.z); PH.gh_prev = PH.y; PH.prevZ = PH.z; PH.ready = true; }
  const prog = Math.min(Math.max(-PH.z, 0) / C.PULL_RAMP, 1); PH.hurt = Math.max(PH.hurt - dt, 0); PH.boost_t = Math.max(PH.boost_t - dt, 0); PH.slide *= Math.exp(-dt / .3);
  let hs = window.__steer || 0; hs = Math.sign(hs) * Math.pow(Math.abs(hs), .8);          // a small turn of the head is a small nudge; only a decided one is a big move
  let sIn = Math.max(-1, Math.min(1, K.r - K.l + hs));
  // LOCK-ON (RunRig._update_buff_aim + _guard_path): every pickup, pad, rail and ramp up to 260 m ahead is a candidate; nudge toward one (or line one up dead ahead) and the green reticle locks on. While locked the board is pulled toward it by Godot's rule
  // (want = (target x - (x + 0.45 vx)) / 12, weight building at 4 per second, strength fading a little with distance), and the last stretch tugs you forward so you are slung into it. Nudge hard the other way to let go.
  { const lt = PH.latch; if (lt && (PH.z - lt.z < 2 || lt.o.taken || lt.o.used || lt.o.done || lt.o.t > 1e14 || (Math.abs(sIn) > .5 && Math.sign(sIn) !== Math.sign(lt.x - PH.x)) || Math.abs(lt.x - PH.x) > 60 || PH.z - lt.z > 270)) PH.latch = null;
    PH.cands.length = 0; const addC = (o, z, x, y, kind) => { const dzz = PH.z - z; if (dzz > 8 && dzz < 260 && Math.abs(x - PH.x) < 48) PH.cands.push({ o, z, x, y, kind, dz: dzz, dx: x - PH.x }); };
    if (!PH.rail) { for (const b of BUFFS) if (!b.taken && Math.abs(b.z - PH.z) < 270) addC(b, b.z, b.x, b.y, 'buff'); for (const pd of PADS) if (!pd.used && Math.abs(pd.z - PH.z) < 270) addC(pd, pd.z, pd.x, null, 'pad'); for (const f of RAILS) if (!f.done && Math.abs(f.za - PH.z) < 270) addC(f, f.za, featX(f, f.za), null, 'rail'); for (const k of VXS) if (k.trail && !k.done && Math.abs(k.z - PH.z) < 270) addC(k, k.z, k.x, null, 'ramp'); for (const m of PILLS) if (!(m.taken || m.t > 1e14) && Math.abs(m.z - PH.z) < 270) addC(m, m.z, m.x, null, 'mol'); }
    if (!PH.latch && !PH.rail) { let bd = 1e9, best = null; for (const c of PH.cands) { const side = Math.sign(c.dx) === Math.sign(sIn) && Math.abs(sIn) > .08, ahead = Math.abs(c.dx) < 3 && c.dz < 70; if (!side && !ahead) continue; const sc = Math.abs(c.dx) + .06 * c.dz; if (sc < bd) { bd = sc; best = c; } } if (best) PH.latch = { z: best.z, x: best.x, y: best.y, o: best.o, kind: best.kind, w: 0 }; }
    if (PH.latch) { const L = PH.latch; L.w = Math.min(1, L.w + 4 * dt); const dzl = PH.z - L.z, kd = Math.max(.35, Math.min(1, 1.25 - dzl / 260)); const want = Math.max(-.9, Math.min(.9, (L.x - (PH.x + PH.vx * .45)) / 12)); sIn = Math.max(-1, Math.min(1, sIn + L.w * kd * want * (1 - .5 * Math.abs(sIn)))); PH.latchDist = dzl; }
    else PH.latchDist = 1e9; }
  sIn = Math.max(-1, Math.min(1, sIn + wellSteer(sIn, dt)));
  if (!PH.rail && PH.grounded) {          // LANE HOLD (RunRig._free_shift): the smallest shift that clears every tree and rock coming up in the next second, applied early, and any nudge toward a tree is cancelled: you are held in the lane beside it
    const spd = Math.max(Math.hypot(PH.vx, PH.vz), 20), look = Math.min(90, spd * 1.15), cx2 = Math.floor(PH.x / 8), cz2 = Math.floor(PH.z / 8), reach = Math.ceil(look / 8) + 1; let push = 0, block = 0;
    for (let ci = -2; ci <= 2; ci++) for (let cj = -reach; cj <= 1; cj++) { const a = OGRID.get((cx2 + ci) + ',' + (cz2 + cj)); if (!a) continue;
      for (const o of a) { const dzz = PH.z - o.z; if (dzz < -1 || dzz > look) continue; const tt = Math.max(dzz, 0) / spd, xp = PH.x + PH.vx * tt * .8, clr = o.r + C.SLED_R + 2.2, d = xp - o.x; if (Math.abs(d) >= clr) continue;
        const side = Math.sign(d) || Math.sign(PH.x - o.x) || (o.x > 0 ? -1 : 1), urg = Math.max(.25, 1 - dzz / look), need = Math.min(1, (clr - Math.abs(d)) / 3); push += side * need * urg * 1.4; if (Math.sign(sIn) === -side && Math.abs(sIn) > .05) block = Math.max(block, urg); } }
    if (push) sIn = Math.max(-1, Math.min(1, sIn * (1 - .85 * block) + Math.max(-1.1, Math.min(1.1, push)))); }
  if (!PH.rail) { const ex = Math.abs(PH.x), edge = sstep(C.W_HALF - 16, C.W_HALF - 4, ex); sIn = Math.max(-1, Math.min(1, sIn - Math.sign(PH.x) * edge * .9)); }          // the banked walls turn you back: no sliding up the side
  if (PH.vlock !== null && PH.grounded) sIn = Math.max(-1, Math.min(1, sIn + Math.max(-1, Math.min(1, (PH.vlock - PH.x) / 12)) * .6));          // the swirl has the board's own steering aim at the ramp too
  let steer = sIn; if (Math.abs(sIn) < .3) steer = Math.max(-1, Math.min(1, steer - .12 * Math.max(-1, Math.min(1, PH.vx / (12 * SPK)))));
  const w = 13 * STK, acc = w * w * (steer - PH.steer) - 2 * w * PH.sv; PH.sv += acc * dt; PH.steer = Math.max(-1, Math.min(1, PH.steer + PH.sv * dt)); steer = PH.steer;
  PH.heading += (steer * C.THETA_MAX * (PH.grounded ? 1 : .4) - PH.heading) * (1 - Math.exp(-dt / (PH.grounded ? .07 : .4)));
  const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), rx = Math.cos(PH.heading), rz = Math.sin(PH.heading), prevY = PH.y, ox0 = PH.x, oz0 = PH.z;
  if (PH.grounded) {
    const e = .6, gx = (th(PH.x + e, PH.z) - th(PH.x - e, PH.z)) / (2 * e), gz = (th(PH.x, PH.z + e) - th(PH.x, PH.z - e)) / (2 * e), g2 = gx * gx + gz * gz;
    const spd = Math.hypot(PH.vx, PH.vz); if (spd < C.MIN_SPEED) { PH.vx += fx * (C.MIN_SPEED - spd) * 1.2 * dt; PH.vz += fz * (C.MIN_SPEED - spd) * 1.2 * dt; }
    PH.vx += -C.G * gx / (1 + g2) * dt; PH.vz += -C.G * gz / (1 + g2) * dt;
    let sp = Math.hypot(PH.vx, PH.vz); const drag = C.DRAG * (1 - .5 * prog) * (PH.boost_t > 0 ? .3 : 1);
    if (PH.boost_t > 0 && spd < C.SPEED_CAP) { PH.vx += fx * 7 * SPK * dt; PH.vz += fz * 7 * SPK * dt; }
    if (sp > .01) { const dec = Math.min((.22 + drag * sp * sp) * dt, sp); PH.vx -= PH.vx / sp * dec; PH.vz -= PH.vz / sp * dec; }
    PH.grade = Math.max(0, Math.min(1.5, -(gx * fx + gz * fz)));          // how steeply the way you are heading runs downhill
    sp = Math.hypot(PH.vx, PH.vz); const vcap = (C.TRAIL_VMAX * ramp() + (PH.boost_t > 0 ? 8 * SPK : 0) + (PH.vxa > 0 ? 9 * SPK : 0)) * (1 + .28 * PH.grade); if (sp > vcap) { const k = (sp - vcap) * (PH.mom > 0 ? .12 : .7) * dt; PH.vx -= PH.vx / sp * k; PH.vz -= PH.vz / sp * k; }
    const old = Math.hypot(PH.vx, PH.vz); let along = PH.vx * fx + PH.vz * fz; const lat = PH.vx * rx + PH.vz * rz, latN = lat * Math.exp(-C.GRIP * (Math.abs(PH.steer) < .15 ? 2.2 : 1) * dt);          // (with the head straight the board straightens along its lane: the sideways slide is killed twice as hard)
    along += Math.abs(lat - latN) * .6 * Math.sign(Math.abs(along) > .01 ? along : 1); PH.vx = fx * along + rx * latN; PH.vz = fz * along + rz * latN; const v = Math.hypot(PH.vx, PH.vz); if (v > old) { PH.vx *= old / v; PH.vz *= old / v; }
  } else {
    const sp2 = Math.hypot(PH.vx, PH.vz); if (sp2 > .01) { const dd = Math.min(C.DRAG * .4 * sp2 * sp2 * dt, sp2); PH.vx -= PH.vx / sp2 * dd; PH.vz -= PH.vz / sp2 * dd; }
    PH.vx += rx * steer * 3 * SPK * dt; PH.vz += rz * steer * 3 * SPK * dt;
    const aHigh = PH.y - th(PH.x, PH.z) - 34 * SPK; if (aHigh > 0 && PH.vy > -12) PH.vy -= Math.min(aHigh * 6, 30) * dt;
    PH.air_t += dt;
  }
  { const cap = (C.TRAIL_SPEED * ramp() + 6 * SPK * prog + (PH.boost_t > 0 ? 4 * SPK : 0) + (PH.vxa > 0 ? 9 * SPK : 0)) * (1 + .28 * PH.grade), spn = Math.hypot(PH.vx, PH.vz); if (spn > cap) { const k = 1 - Math.exp(-(PH.mom > 0 ? .1 : .5) * dt); PH.vx -= PH.vx * k * (1 - cap / spn); PH.vz -= PH.vz * k * (1 - cap / spn); } { const hard = Math.min(cap * (PH.mom > 0 ? 1.5 : 1.25), C.SPEED_CAP), sp3 = Math.hypot(PH.vx, PH.vz); if (sp3 > hard) { const k3 = 1 - Math.exp(-3 * dt); PH.vx -= PH.vx * k3 * (1 - hard / sp3); PH.vz -= PH.vz * k3 * (1 - hard / sp3); } }          // (momentum may carry you well past the cap, but never without limit)
  PH.mom = Math.max(PH.mom - dt, 0); }
  if (PH.latch && PH.grounded && PH.latchDist < 28 && PH.latchDist > 0) { const tug = 10 * SPK * dt * PH.latch.w * (1 - PH.latchDist / 28); PH.vx += fx * tug; PH.vz += fz * tug; PH.vxa = Math.max(PH.vxa, .25); }
  if (PH.vxa > 0 || PH.boost_t > 0) PH.mom = Math.max(PH.mom, 1.2);
  PH.vz = Math.min(PH.vz, -3); PH.x += PH.vx * dt; PH.z = Math.min(PH.z + PH.vz * dt, 0);
  if (Math.abs(PH.x) >= C.W_HALF - 2.5) { PH.x = Math.max(-(C.W_HALF - 2.5), Math.min(C.W_HALF - 2.5, PH.x)); PH.vx *= -.2; }
  const gh = th(PH.x, PH.z), gvy = Math.max(-60, Math.min(60, (gh - PH.gh_prev) / Math.max(dt, 1e-4)));
  if (PH.grounded) { const vg = (gh - prevY) / Math.max(dt, 1e-4); if (vg < PH.vy - C.GV * dt - .4 - .03 * Math.hypot(PH.vx, PH.vz)) {          // (the board stays glued over small crests: the faster it goes, the bigger the drop has to be to leave the snow)
 PH.grounded = false; PH.air_t = 0; PH.vy = PH.vy - C.GV * dt; PH.y = prevY + PH.vy * dt; } else { PH.y = gh; PH.vy = Math.min(vg, C.JUMP_LAUNCH); } }
  else {
    PH.vy -= C.GV * dt * C.AIR_G_K; if (PH.air_t > 2.4) PH.vy -= 26 * SPK * (PH.air_t - 2.4) * dt; PH.vy = Math.max(PH.vy, -90 * SPK); PH.y += PH.vy * dt;          // (a flight longer than about two seconds is pulled down harder and harder)
    if (PH.y <= gh + .05 || PH.y < gh) { const impact = Math.max(gvy - PH.vy, 0); PH.landT = PH.air_t; PH.grounded = true; PH.y = gh; PH.vy = gvy; PH.air_t = 0; if (impact > 4 * SPK) SFX.land(); PH.mom = 2.6; if (impact > 18 * SPK) crash('WIPEOUT!', 'tree'); else if (impact > 12 * SPK) { PH.vx *= .97; PH.vz *= .97; } else if (PH.landT > .5) { const fx2 = Math.sin(PH.heading), fz2 = -Math.cos(PH.heading), kick = (4 + 3 * Math.min(PH.landT, 3)) * SPK; PH.vx += fx2 * kick; PH.vz += fz2 * kick; PH.boost_t = Math.max(PH.boost_t, 1.1); PH.vxa = Math.max(PH.vxa, .8); toast(impact < 5 * SPK ? 'SMOOTH LANDING!' : 'LANDED', '#7fa'); SFX.snap(); chainHit(); } }          // (a landing after a real flight is a boost, and a link in the chain)
  }
  PH.gh_prev = gh;
  if (PH.z < WORLD_END + 30) { PH.lap++; toast('LAP ' + PH.lap + ' DONE  score ' + Math.floor(PH.score), '#ff6'); buildWorld(); for (const r of ROWS) { for (const b of (r.buffs || [])) b.taken = false; for (const pd of (r.pads || [])) pd.used = false; } PH.z = -2; PH.x = 0; PH.vx = 0; PH.vz = -20; PH.y = th(0, -2); PH.gh_prev = PH.y; PH.vy = 0; PH.grounded = true; PH.prevZ = -2; PH.rail = null; SFX.grindOff(); }
  railStep(dt, sIn); vortexStep(dt, sIn); toys.tick(dt, sIn); collectStep(); if (!toys.active()) obstacleStep(ox0, oz0); PH.prevZ = PH.z; ringsTick();
  if (PH.mult > 0) PH.mult -= dt; PH.score += dt * Math.hypot(PH.vx, PH.vz) * .02 * (PH.mult > 0 ? 2 : 1);
  chainTick(dt); SPW.tick(clock.t, PH.z); measure(dt, sIn, PH.steer);
  if (toastT > 0) { toastT -= dt; if (toastT <= 0) toastEl.style.opacity = 0; }
  st.x = PH.x; st.z = PH.z;
}
function frame(now) {
  requestAnimationFrame(frame); const dt = Math.min(0.05, (now - last) / 1000); last = now; clock.t += dt; U.uTime.value = clock.t;
  animTick(clock.t);
  if (PLAY && !st.paused && !SHOT) playStep(dt); else if (!PLAY && !st.paused) st.z -= st.speed * dt;
  if (SHOT) { const M4 = mat4(SHOT.xf), p = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3(); M4.decompose(p, q, sc); camera.position.copy(p); camera.quaternion.copy(q); if (ring) { const e = ring.matrix.elements; e[12] = p.x; e[13] = p.y - 1.7 - 159.696; e[14] = p.z; } U.uBoard.value.set(p.x, p.z); sky.position.copy(camera.position); renderPost(); return; }
  const gy = PLAY ? PH.y : groundY(st.x, st.z); if (gy !== null) { const tgY = gy + 3.2; if (Math.abs(tgY - st.y) > 6) st.y = tgY; else st.y += (tgY - st.y) * Math.min(1, dt * (PLAY ? 14 : 8)); }
  const ahead = groundY(st.x, st.z - 30); const pitch = (gy !== null && ahead !== null) ? Math.atan2(ahead - gy, 30) : 0;
  if (ring) { const e = ring.matrix.elements; e[12] = st.x; e[13] = st.y - 1.7 - 159.696; e[14] = st.z; }
  camera.position.set(st.x, st.y, st.z); camera.rotation.set(-0.06 + pitch * 0.8, 0, 0, 'YXZ'); U.uBoard.value.set(st.x, st.z); sky.position.copy(camera.position);
  renderPost(); goalTick(now); beaconTick(now); govTick(now);
  frames++; acc += dt; if (acc > 0.5) { fps = frames / acc; frames = 0; acc = 0; hud.textContent = LVL + '  seed ' + lvl.seed + '  ' + lvl.theme + '\n' + nMesh + ' meshes, ' + nInst + ' instances, ' + Object.keys(lvl.meshes).length + ' unique meshes\nz ' + st.z.toFixed(0) + '  speed ' + (PLAY ? (Math.hypot(PH.vx, PH.vz) * 3.6).toFixed(0) + 'km/h  hits ' + PH.hits + '  score ' + Math.floor(PH.score) + (PH.shield ? '  SHIELD' : '') + (PH.boost_t > 0 ? '  BOOST' : '') : st.speed.toFixed(0)) + '  ' + fps.toFixed(0) + ' fps'; }
}
const PB = document.createElement('div'); PB.textContent = 'II'; PB.style.cssText = 'position:fixed;right:10px;top:8px;width:44px;height:44px;line-height:44px;text-align:center;border:2px solid #fff9;border-radius:22px;color:#fff;font:700 18px ui-monospace,Consolas,monospace;background:#0006;z-index:9;cursor:pointer;user-select:none'; document.body.appendChild(PB);
const PV = document.createElement('div'); PV.style.cssText = 'position:fixed;inset:0;display:none;align-items:center;justify-content:center;flex-direction:column;background:#000b;z-index:25;color:#fff;font:700 40px ui-monospace,Consolas,monospace;cursor:pointer;text-align:center'; PV.innerHTML = 'PAUSED<br><span style="font-size:16px;opacity:.8">tap or press P to resume</span>'; document.body.appendChild(PV);
function setPause(v) { st.paused = v; PV.style.display = v ? 'flex' : 'none'; PB.textContent = v ? '>' : 'II'; if (v) SFX.grindOff(); else last = performance.now(); }
PB.addEventListener('click', (e) => { e.stopPropagation(); setPause(!st.paused); }); PV.addEventListener('click', () => setPause(false));
addEventListener('keydown', (e) => { if (e.key === 'p' || e.key === 'P' || e.key === 'Escape') setPause(!st.paused); });
document.addEventListener('visibilitychange', () => { if (document.hidden && PLAY) setPause(true); });
LD.remove();
requestAnimationFrame(frame);
window.__gv = { frame, scene, camera, st, lvl, renderer, PH, setPause, BUFFS, PADS, RAILS, featX, K, post: { rt: rtScene, u: postM.uniforms, glow: GL, gov: GOV, glowQ: GLOWQ, bright: brightM.uniforms, setSamples, setDpr }, fog: U };
