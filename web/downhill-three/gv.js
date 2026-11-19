// GODOT LEVEL VIEWER. Renders a level DUMPED from the real Godot game (godot/tests/dump_level.gd: the real generator, run headless with a fixed seed) so that every mesh, every instance and every transform
// is the game's own, not an approximation. Godot and three.js are both right-handed, Y up, -Z forward, so transforms carry over as they are. What this file does: build geometry from the dumped vertex arrays,
// map Godot's materials (StandardMaterial3D -> MeshStandardMaterial, each shader -> a GLSL port), set the sun, the sky-lit ambient, the exponential fog and the filmic tonemap from the dumped Environment, and fly a camera down the course.
import * as THREE from 'three';
const Q = new URLSearchParams(location.search);
const LVL = Q.get('lvl') || 'level_psy_s7';
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
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0, side: THREE.DoubleSide });
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
      ? 'uniform float uTime, dose; varying vec2 vUv; void main(){ float e = smoothstep(0., .4, vUv.x) * smoothstep(1., .6, vUv.x); float v = smoothstep(1., .7, vUv.y) * smoothstep(0., .55, vUv.y); float sh = .75 + .25 * sin(vUv.x * 23. + uTime * .7) * sin(vUv.x * 7. - uTime * .4); vec3 rb = .5 + .5 * cos(6.2831 * (vUv.y * 1.5 + uTime * .15 + vec3(0., .33, .67))); gl_FragColor = vec4(mix(vec3(.6, .5, 1.), rb, clamp(dose * 1.4, 0., .85)), e * v * sh * (1. + dose * 1.6) * .6); }'
      : 'uniform vec4 tint; varying vec2 vUv; void main(){ gl_FragColor = vec4(tint.rgb, tint.a * smoothstep(.22, .62, vUv.y)); }' });
}

// ---------------------------------------------------------------- load
const [lvl] = await Promise.all([fetch('./data/' + LVL + '.json').then((r) => r.json())]);
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
    if (d.unshaded) m = new THREE.MeshBasicMaterial({ color: rgb(d.albedo), vertexColors: !!d.vertex_color_albedo });
    else {
      m = new THREE.MeshStandardMaterial({ color: rgb(d.albedo), roughness: d.roughness, metalness: d.metallic, vertexColors: !!d.vertex_color_albedo });
      if (d.emission_on) { m.emissive = rgb(d.emission); m.emissiveIntensity = d.emission_energy; }
    }
    if (d.transparency > 0 || d.albedo[3] < 0.99) { m.transparent = true; m.opacity = d.albedo[3]; }
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
const vis = {}; const ground = []; let nMesh = 0, nInst = 0;
const NODE = new THREE.Group(); scene.add(NODE); let ring = null;          // the mountain ring (the 1620-vertex vertex-coloured mesh): Godot moves it with the board so it never moves against the road
for (const n of lvl.nodes) {
  vis[n.path] = n.vis !== false; const parts = n.path.split('/'); let ok = true; for (let k = 2; k < parts.length; k++) if (vis['/' + parts.slice(1, k + 1).join('/')] === false) { ok = false; break; }
  if (!ok || !n.path.startsWith('/MainLevel/RunRig') || n.path.includes('@Camera3D') || n.path.includes('SubViewport')) continue;
  if (n.class === 'MeshInstance3D' && n.mesh) {
    const gs = geoOf(n.mesh); const M4 = mat4(n.xf);
    for (const [g, sm] of gs) { const mat = matOf(n.mat_override || sm); if (!mat) continue; const m = new THREE.Mesh(g, mat); m.matrixAutoUpdate = false; m.matrix.copy(M4); m.frustumCulled = false; NODE.add(m); nMesh++; if (lvl.materials[n.mat_override || sm]?.shader_code?.includes('MOIRE')) ground.push(m); if (g.attributes.position.count === 1620 && !ring) ring = m; }
  } else if (n.class === 'MultiMeshInstance3D' && n.mesh && n.count) {
    const gs = geoOf(n.mesh); const NM = mat4(n.xf);
    for (const [g, sm] of gs) {
      const mat = matOf(n.mat_override || sm); if (!mat) continue; const im = new THREE.InstancedMesh(g, mat, n.count); const t = new THREE.Matrix4();
      for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); im.setMatrixAt(i, t); if (n.cols) im.setColorAt(i, new THREE.Color().setRGB(n.cols[i][0], n.cols[i][1], n.cols[i][2], THREE.LinearSRGBColorSpace)); }
      im.frustumCulled = false; NODE.add(im); nMesh++; nInst += n.count;
    }
  }
}
// lights and environment from the dump
let sunNode = lvl.nodes.find((n) => n.light && n.name === 'Sun'), envNode = lvl.nodes.find((n) => n.env);
if (sunNode) {
  const L = sunNode.light, sun = new THREE.DirectionalLight(rgb(L.color), L.energy * Math.PI), b = sunNode.xf, dir = new THREE.Vector3(-b[6], -b[7], -b[8]);          // Godot lights shine along the node's -Z
  sun.position.copy(dir.clone().multiplyScalar(-200)); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target);
}
if (envNode) {
  const e = envNode.env; scene.fog = new THREE.FogExp2(rgb(e.fog_light_color), e.fog_density); U.fogColor.value.copy(rgb(e.fog_light_color)); U.fogDensity.value = e.fog_density;
  scene.add(new THREE.HemisphereLight(new THREE.Color(0.10, 0.01, 0.16), new THREE.Color(0.05, 0.0, 0.12), e.ambient_light_energy * Math.PI));          // (ambient comes from the sky: dark violet here)
  renderer.toneMappingExposure = e.tonemap_exposure || 1.05;
}
const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), skyMat()); sky.frustumCulled = false; sky.renderOrder = -10; scene.add(sky);
// ---------------------------------------------------------------- fly
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0);
function groundY(x, z) { ray.set(new THREE.Vector3(x, 3000, z), down); const h = ray.intersectObjects(ground, false); return h.length ? h[0].point.y : null; }
const st = { z: lvl.start ? lvl.start[2] - 2 : -2, x: 0, speed: parseFloat(Q.get('speed') || '40'), paused: false, y: 0 };
addEventListener('keydown', (e) => { if (e.key === ' ') st.paused = !st.paused; if (e.key === 'ArrowUp') st.speed += 10; if (e.key === 'ArrowDown') st.speed = Math.max(0, st.speed - 10); if (e.key === 'ArrowLeft') st.x -= 4; if (e.key === 'ArrowRight') st.x += 4; });
function resize() { const w = innerWidth, h = innerHeight; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); }
addEventListener('resize', resize); resize();
let last = performance.now(), fps = 0, acc = 0, frames = 0;
const SHOT = Q.has('shot') ? lvl.shots[parseInt(Q.get('shot'), 10) || 0] : null;
if (SHOT) { st.paused = true; const img = document.createElement('img'); img.src = './shots/godot_' + String(SHOT.i).padStart(2, '0') + '.png'; img.id = 'ref'; img.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;object-fit:fill;opacity:' + (Q.get('ref') || '0') + ';pointer-events:none;z-index:4'; document.body.appendChild(img); addEventListener('keydown', (e) => { if (e.key === 'g') img.style.opacity = img.style.opacity === '1' ? '0' : (img.style.opacity === '0.5' ? '1' : '0.5'); }); camera.fov = SHOT.fov; }
function frame(now) {
  requestAnimationFrame(frame); const dt = Math.min(0.05, (now - last) / 1000); last = now; clock.t += dt; U.uTime.value = clock.t;
  if (!st.paused) st.z -= st.speed * dt;
  if (SHOT) { const M4 = mat4(SHOT.xf), p = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3(); M4.decompose(p, q, sc); camera.position.copy(p); camera.quaternion.copy(q); if (ring) { const e = ring.matrix.elements; e[12] = p.x; e[13] = p.y - 1.7 - 159.696; e[14] = p.z; } U.uBoard.value.set(p.x, p.z); sky.position.copy(camera.position); renderer.render(scene, camera); return; }
  const gy = groundY(st.x, st.z); if (gy !== null) st.y += ((gy + 3.2) - st.y) * Math.min(1, dt * 8); else st.y -= 0;
  const ahead = groundY(st.x, st.z - 30); const pitch = (gy !== null && ahead !== null) ? Math.atan2(ahead - gy, 30) : 0;
  if (ring) { const e = ring.matrix.elements; e[12] = st.x; e[13] = st.y - 1.7 - 159.696; e[14] = st.z; }
  camera.position.set(st.x, st.y, st.z); camera.rotation.set(-0.06 + pitch * 0.8, 0, 0, 'YXZ'); U.uBoard.value.set(st.x, st.z); sky.position.copy(camera.position);
  renderer.render(scene, camera);
  frames++; acc += dt; if (acc > 0.5) { fps = frames / acc; frames = 0; acc = 0; hud.textContent = LVL + '  seed ' + lvl.seed + '  ' + lvl.theme + '\n' + nMesh + ' meshes, ' + nInst + ' instances, ' + Object.keys(lvl.meshes).length + ' unique meshes\nz ' + st.z.toFixed(0) + '  speed ' + st.speed.toFixed(0) + '  ' + fps.toFixed(0) + ' fps'; }
}
requestAnimationFrame(frame);
window.__gv = { frame, scene, camera, st, lvl, renderer };
