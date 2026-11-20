// KIT: custom ramps, rails and ring arcs in five cheap materials (steel, glass, wood, neon, rust). Every object is a few merged triangles; every material is ONE small shader that picks its look from a per-vertex
// material id, so the whole kit is two draw calls (one opaque, one see-through for glass) however many objects stand on the course. The looks are fakes, on purpose:
//   steel  a gradient "reflection" of the sky with a sharp highlight and a rim brightening        glass  a pale tint that is mostly clear in the middle and bright at the edges (fresnel), blended
//   wood   warm grain bands from the surface coordinates                                           neon   a pulsing emissive colour           rust  two layers of noise between brown and orange
// No environment map, no refraction, no extra render pass: that is what makes real glass and mirrors expensive, and the reason they are not used.
//
// The physics reads plain records: rails go into the game's RAILS list (so the existing grind code rides them, curved ones through f.cv(z)); ramps and rings are stepped by kit.step().
import * as THREE from 'three';

const MATS = ['steel', 'glass', 'wood', 'neon', 'rust'], MCOL = { steel: [.62, .7, .8], glass: [.7, .9, 1], wood: [.7, .45, .22], neon: [1, .3, .9], rust: [.8, .4, .15] };
const mulberry = (seed) => { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };

const VERT = `attribute float mat; attribute vec3 color; varying vec3 vN, vW, vC; varying float vM; varying vec2 vUv;
void main() { vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal); vC = color; vM = mat; vUv = uv; gl_Position = projectionMatrix * viewMatrix * w; }`;
const FRAG = `uniform float uTime; uniform float uGlass; uniform vec3 uSun; uniform vec3 uTop; uniform vec3 uHor; varying vec3 vN, vW, vC; varying float vM; varying vec2 vUv;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
void main() {
  float m = vM; if (uGlass > 0.5 && m > 1.5) discard; if (uGlass < 0.5 && m > 0.5 && m < 1.5) discard;
  vec3 N = normalize(vN); vec3 V = normalize(cameraPosition - vW); float ndv = clamp(dot(N, V), 0.0, 1.0), fr = pow(1.0 - ndv, 3.0), dl = max(dot(N, normalize(uSun)), 0.0); vec3 R = reflect(-V, N); float sky = clamp(R.y * 0.5 + 0.5, 0.0, 1.0); vec3 env = mix(uHor, uTop, sky); vec3 col; float a = 1.0;
  if (m < 0.5) { float spec = pow(max(dot(R, normalize(uSun)), 0.0), 28.0); col = vC * 0.3 + env * (0.42 + 0.5 * fr) * vec3(0.9, 0.95, 1.0) + vec3(1.0) * spec * 0.9; }
  else if (m < 1.5) { col = mix(vec3(0.55, 0.8, 0.95), env, 0.5) + fr * 0.9; a = 0.2 + 0.65 * fr; }
  else if (m < 2.5) { float g = n(vec2(vUv.x * 3.0, vUv.y * 38.0)); float rings = 0.5 + 0.5 * sin(vUv.y * 55.0 + g * 5.0); col = mix(vec3(0.5, 0.29, 0.12), vec3(0.85, 0.57, 0.3), rings * 0.6 + g * 0.4) * (0.55 + 0.6 * dl); }
  else if (m < 3.5) { float p = 0.78 + 0.22 * sin(uTime * 6.0 + vW.z * 0.15); col = vC * (1.5 * p) + fr * vC; }
  else { float g = n(vW.xz * 1.7 + vW.y), g2 = n(vW.xz * 6.0 + vW.y * 2.0); col = mix(vec3(0.42, 0.18, 0.07), vec3(0.88, 0.47, 0.16), g * 0.7 + g2 * 0.3) * (0.5 + 0.6 * dl); }
  gl_FragColor = vec4(col, a);
}`;

function GeoBuf() {
  const P = [], N = [], U = [], C = [], M = [], I = []; let nv = 0;
  const vert = (p, n, u, v, c, m) => { P.push(p[0], p[1], p[2]); N.push(n[0], n[1], n[2]); U.push(u, v); C.push(c[0], c[1], c[2]); M.push(m); return nv++; };
  const quad = (a, b, c, d) => { I.push(a, b, c, a, c, d); };
  const geo = () => { const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(U, 2)); g.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); g.setAttribute('mat', new THREE.Float32BufferAttribute(M, 1)); g.setIndex(I); return g; };
  return { vert, quad, geo, get count() { return nv; } };
}
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

// a tube along a polyline (round pipe)
function addTube(B, pts, rad, sides, col, mat) {
  const rings = []; for (let i = 0; i < pts.length; i++) {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)], t = norm(sub(b, a)), up = Math.abs(t[1]) > .95 ? [1, 0, 0] : [0, 1, 0], s = norm(cross(t, up)), u = cross(s, t), ring = [];
    for (let k = 0; k <= sides; k++) { const an = k / sides * Math.PI * 2, nx = Math.cos(an), ny = Math.sin(an), nn = [s[0] * nx + u[0] * ny, s[1] * nx + u[1] * ny, s[2] * nx + u[2] * ny]; ring.push(B.vert([pts[i][0] + nn[0] * rad, pts[i][1] + nn[1] * rad, pts[i][2] + nn[2] * rad], nn, k / sides, i * 0.5, col, mat)); }
    rings.push(ring);
  }
  for (let i = 0; i < rings.length - 1; i++) for (let k = 0; k < sides; k++) B.quad(rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]);
}
// a box beam along a polyline (flat-topped rail)
function addBeam(B, pts, w, hgt, col, mat) {
  const rings = []; for (let i = 0; i < pts.length; i++) {
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)], t = norm(sub(b, a)), s = norm(cross(t, [0, 1, 0])), u = cross(s, t), cs = [[-w, hgt], [w, hgt], [w, -hgt], [-w, -hgt]], ring = [];
    const nn = [[0, 1], [1, 0], [0, -1], [-1, 0]]; for (let k = 0; k < 4; k++) { const [x0, y0] = cs[k], [x1, y1] = cs[(k + 1) % 4], nx = nn[k][0], ny = nn[k][1], n3 = [s[0] * nx + u[0] * ny, s[1] * nx + u[1] * ny, s[2] * nx + u[2] * ny]; const mk = (x, y, uu) => B.vert([pts[i][0] + s[0] * x + u[0] * y, pts[i][1] + s[1] * x + u[1] * y, pts[i][2] + s[2] * x + u[2] * y], n3, uu, i * 0.5, col, mat); ring.push([mk(x0, y0, 0), mk(x1, y1, 1)]); }
    rings.push(ring);
  }
  for (let i = 0; i < rings.length - 1; i++) for (let k = 0; k < 4; k++) B.quad(rings[i][k][0], rings[i][k][1], rings[i + 1][k][1], rings[i + 1][k][0]);
}
function addPost(B, x, y0, y1, z, col, mat) { addTube(B, [[x, y0, z], [x, y1, z]], .1, 5, col, mat); }

// ramp profiles: height 0..1 along the run t 0..1
const PROF = {
  kicker: (t) => Math.pow(t, 1.8), roller: (t) => 0.5 - 0.5 * Math.cos(Math.PI * Math.min(1, t * 1.15)), double: (t) => Math.max(0.5 * Math.sin(Math.PI * Math.min(1, t * 2)), Math.pow(t, 2.2)),
  quarter: (t) => 1 - Math.cos(Math.PI / 2 * t), bridge: (t) => Math.min(1, t * 6), step: (t) => { const k = Math.min(2, Math.floor(t * 3)), f = t * 3 - k; return (k + Math.min(1, f * 4)) / 3; }, bump: (t) => Math.sin(Math.PI * Math.min(1, t * .5 + .5 * t * t)) * .55 + Math.pow(t, 3) * .45, hop: (t) => Math.pow(t, 1.3), spine: (t) => Math.pow(t, 2.2),
};
const RAMPS = [
  { id: 'kicker', name: 'KICKER', len: 16, h: 4.2, w: 11, mats: ['steel', 'neon', 'steel', 'rust'], hm: 1.0 },
  { id: 'roller', name: 'ROLLER', len: 40, h: 3.0, w: 16, mats: ['wood', 'wood', 'glass'], hm: .8 },
  { id: 'double', name: 'DOUBLE HUMP', len: 34, h: 4.5, w: 12, mats: ['rust', 'wood', 'steel'], hm: 1.0 },
  { id: 'quarter', name: 'QUARTER PIPE', len: 22, h: 7.0, w: 12, mats: ['glass', 'steel', 'neon'], hm: 1.25 },
  { id: 'hop', name: 'WIDE HOP', len: 14, h: 2.2, w: 24, mats: ['wood', 'rust', 'glass'], hm: .7 },
  { id: 'spine', name: 'SPINE', len: 20, h: 6.0, w: 5, mats: ['neon', 'steel', 'rust'], hm: 1.15 },
  { id: 'bridge', name: 'BRIDGE DROP', len: 34, h: 4.5, w: 9, mats: ['rust', 'steel', 'wood'], hm: .9 },
  { id: 'step', name: 'STAIRS', len: 30, h: 5.5, w: 12, mats: ['wood', 'neon', 'rust'], hm: 1.05 },
  { id: 'bump', name: 'WHOOP', len: 26, h: 3.4, w: 14, mats: ['glass', 'wood', 'neon'], hm: .85 },
];
const RAILD = [
  { id: 'pipe', name: 'PIPE', len: 40, kind: 'tube', rad: .22, mats: ['steel', 'rust', 'steel'], cv: null },
  { id: 'beam', name: 'BEAM', len: 46, kind: 'beam', mats: ['wood', 'rust', 'wood'], cv: null },
  { id: 'twin', name: 'TWIN RAIL', len: 38, kind: 'twin', rad: .13, mats: ['neon', 'steel', 'glass'], cv: null },
  { id: 'wave', name: 'WAVE RAIL', len: 64, kind: 'tube', rad: .2, mats: ['glass', 'neon'], cv: { amp: 5.5, wl: 36 } },
  { id: 'long', name: 'LONG PIPE', len: 80, kind: 'tube', rad: .26, mats: ['steel', 'wood', 'rust'], cv: null },
  { id: 'arc', name: 'ARC RAIL', len: 52, kind: 'beam', mats: ['neon', 'glass', 'steel'], cv: { amp: 9, wl: 104 } },
  { id: 'zig', name: 'ZIGZAG', len: 56, kind: 'beam', mats: ['rust', 'neon', 'steel'], cv: { amp: 6, wl: 28, tri: true } },
  { id: 'coil', name: 'COIL', len: 48, kind: 'tube', rad: .18, mats: ['glass', 'steel', 'neon'], cv: { amp: 2.6, wl: 13 } },
  { id: 'tw2', name: 'DOUBLE PIPE', len: 44, kind: 'twin', rad: .2, mats: ['steel', 'rust', 'wood'], cv: { amp: 3.5, wl: 60 } },
];
const ARCS = ['parabola', 'spiral', 'ladder', 'sweep', 'low'];

export function createKit(o) {
  const { scene, th, groundY, trailX, PH, C, SPK, RAILS, toast, hooks = {} } = o;
  const U = { uTime: { value: 0 }, uGlass: { value: 0 }, uSun: { value: new THREE.Vector3(.4, .8, .3) }, uTop: { value: new THREE.Vector3(.35, .45, .95) }, uHor: { value: new THREE.Vector3(.9, .7, .85) } };
  const matO = new THREE.ShaderMaterial({ uniforms: { ...U, uGlass: { value: 0 } }, vertexShader: VERT, fragmentShader: FRAG }), matG = new THREE.ShaderMaterial({ uniforms: { ...U, uGlass: { value: 1 } }, vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide });
  const mid = (m) => MATS.indexOf(m), col = (m) => MCOL[m];
  const ramps = [], rings = [], used = new Set(), recent = []; let t0 = 0;

  function pickDesign(list, R) { for (let tries = 0; tries < 6; tries++) { const d = list[Math.floor(R() * list.length)]; if (!recent.includes(d.id)) { recent.push(d.id); if (recent.length > 4) recent.shift(); return d; } } const d = list[Math.floor(R() * list.length)]; recent.push(d.id); if (recent.length > 4) recent.shift(); return d; }

  function buildRamp(d, mat, x, z0, B) {
    const W = d.w / 2, L = d.len, NU = Math.max(8, Math.round(L / 2)), prof = PROF[d.id], c = col(mat), m = mid(mat), rows = [];
    for (let i = 0; i <= NU; i++) { const t = i / NU, z = z0 - t * L, hh = d.h * prof(t), rowv = []; for (let k = 0; k <= 2; k++) { const xx = x + (k - 1) * W, g = groundY(xx, z), gy = g === null ? th(xx, z) : g; rowv.push([xx, gy + hh, z, gy]); } rows.push(rowv); }
    for (let i = 0; i < rows.length - 1; i++) for (let k = 0; k < 2; k++) {
      const a = rows[i][k], b = rows[i][k + 1], cc = rows[i + 1][k + 1], dd = rows[i + 1][k], nn = norm(cross(sub(dd, a), sub(b, a))); const nrm = nn[1] < 0 ? [-nn[0], -nn[1], -nn[2]] : nn;
      B.quad(B.vert(a, nrm, k * .5, i / NU * 6, c, m), B.vert(b, nrm, (k + 1) * .5, i / NU * 6, c, m), B.vert(cc, nrm, (k + 1) * .5, (i + 1) / NU * 6, c, m), B.vert(dd, nrm, k * .5, (i + 1) / NU * 6, c, m));
    }
    for (const side of [0, 2]) for (let i = 0; i < rows.length - 1; i++) { const a = rows[i][side], b = rows[i + 1][side], nrm = [side === 0 ? -1 : 1, 0, 0]; B.quad(B.vert([a[0], a[3], a[2]], nrm, 0, 0, c, m), B.vert([b[0], b[3], b[2]], nrm, 0, 1, c, m), B.vert([b[0], b[1], b[2]], nrm, 1, 1, c, m), B.vert([a[0], a[1], a[2]], nrm, 1, 0, c, m)); }
    const e = rows[NU]; B.quad(B.vert([e[0][0], e[0][3], e[0][2]], [0, 0, -1], 0, 0, c, m), B.vert([e[2][0], e[2][3], e[2][2]], [0, 0, -1], 1, 0, c, m), B.vert([e[2][0], e[2][1], e[2][2]], [0, 0, -1], 1, 1, c, m), B.vert([e[0][0], e[0][1], e[0][2]], [0, 0, -1], 0, 1, c, m));
  }

  function buildRail(d, mat, x, z0, B) {
    const L = d.len, n = Math.max(6, Math.round(L / 3)), f = { mine: true, kind: 'rail', kit: true, mat, col: col(mat), name: d.name, kx: x, sd: 0, za: z0, zb: z0 - L, done: false };
    if (d.cv) f.cv = d.cv.tri ? (z) => d.cv.amp * (2 / Math.PI) * Math.asin(Math.sin((z0 - z) / d.cv.wl * Math.PI * 2)) : (z) => d.cv.amp * Math.sin((z0 - z) / d.cv.wl * Math.PI * 2);
    const path = [], RH = (C && C.RAIL_H) || .9; for (let i = 0; i <= n; i++) { const z = z0 - L * i / n, xx = x + (f.cv ? f.cv(z) : 0), g = groundY(xx, z), gy = g === null ? th(xx, z) : g; const tt = Math.max(0, Math.min(1, (z0 - z) / 4)); path.push([xx, gy + .15 + (RH - .15) * tt * tt * (3 - 2 * tt), z]); }
    const c = col(mat), m = mid(mat);
    if (d.kind === 'tube') addTube(B, path, d.rad, 7, c, m); else if (d.kind === 'beam') addBeam(B, path, .42, .16, c, m); else if (d.kind === 'twin') { for (const off of [-.5, .5]) addTube(B, path.map((p) => [p[0] + off, p[1], p[2]]), d.rad, 6, c, m); }
    for (let i = 0; i <= n; i += 2) { const p = path[i], g = groundY(p[0], p[2]); addPost(B, p[0], g === null ? p[1] - RH : g, p[1], p[2], [.6, .62, .7], 0); }
    RAILS.push(f); return f;
  }

  function buildRings(r, x0, zLip, mat, design) {          // hoops in the air after the lip, in five arrangements: parabola, spiral, ladder, sweep, low
    const NR = design === 'spiral' ? 8 : design === 'low' ? 6 : 5; for (let i = 0; i < NR; i++) { const z = zLip - 20 - i * (design === 'low' ? 11 : 14); let x = x0, hh = 3.6 + 5.2 * Math.sin(Math.PI * (i + .5) / NR); if (design === 'spiral') { const a = i * 1.1; x = x0 + Math.sin(a) * 3.4; hh = 5.5 + Math.cos(a) * 2.6; } else if (design === 'ladder') hh = 2.6 + i * 1.6; else if (design === 'sweep') { x = x0 + Math.sin(i * .9) * 9; hh = 4.5 + Math.sin(i * .5) * 1.5; } else if (design === 'low') hh = 1.9; const g = groundY(x, z), gy = g === null ? th(x, z) : g, y = gy + hh;
      const geo = new THREE.TorusGeometry(2.7, .3, 6, 14), mesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: new THREE.Color(1.6, 1.2, .35), fog: false })); mesh.position.set(x, y, z); mesh.frustumCulled = false; scene.add(mesh); rings.push({ x, y, z, r: 3.1, mesh, taken: false }); }
  }

  // build the objects of one row (the game calls it when the row's ground exists); `spans` are z ranges to stay out of
  function buildRow(j, rr, z0, spans) {
    if (used.has(j)) return; used.add(j);
    const R = mulberry(j * 7919 + 4242), B = GeoBuf(), BG = GeoBuf(); const slots = [-20 - R() * 14, -62 - R() * 14, -108 - R() * 14, -150 - R() * 12]; let made = 0;
    for (let k = 0; k < 4; k++) {
      const z = z0 + slots[k]; if (spans.some((q) => z > q[0] - 30 && z < q[1] + 10)) continue;
      const ramp = R() < .55, lane = (R() < .5 ? -1 : 1) * (6 + R() * 14), x = trailX(z) + lane;
      const d = pickDesign(ramp ? RAMPS : RAILD, R), mat = d.mats[Math.floor(R() * d.mats.length)], buf = mat === 'glass' ? BG : B;
      if (ramp) { buildRamp(d, mat, x, z, buf); const r = { x, z0: z, len: d.len, w: d.w, h: d.h, prof: PROF[d.id], name: d.name, mat, hm: d.hm, on: false }; ramps.push(r); const arcD = ARCS[Math.floor(R() * ARCS.length)]; if (R() < .75) buildRings(r, x, z - d.len, mat, arcD); if (R() < .45 && k < 3) { const d2 = pickDesign(RAILD, R), mat2 = d2.mats[Math.floor(R() * d2.mats.length)]; buildRail(d2, mat2, x + (R() < .5 ? -1 : 1) * R() * 3, z - d.len - 34 - R() * 12, mat2 === 'glass' ? BG : B); k++; } }          // a ramp, its hoops, and sometimes a rail to land on
      else buildRail(d, mat, x, z, buf);
      made++;
    }
    if (!made) return;
    for (const [buf, mt] of [[B, matO], [BG, matG]]) { if (!buf.count) continue; const mesh = new THREE.Mesh(buf.geo(), mt); mesh.frustumCulled = false; if (mt === matG) mesh.renderOrder = 6; scene.add(mesh); }
  }

  // physics: the ramps lift a grounded board along their profile and throw it at the lip; the hoops are collected on the way through
  function step(dt) {
    U.uTime.value = matO.uniforms.uTime.value = matG.uniforms.uTime.value = (t0 += dt);
    for (const r of ramps) {
      if (Math.abs(r.z0 - PH.z) > 130) continue; const t = (r.z0 - PH.z) / r.len, inX = Math.abs(PH.x - r.x) < r.w / 2 + .5;
      if (PH.grounded && !PH.rail && t >= 0 && t <= 1 && inX) { r.on = true; const g = groundY(PH.x, PH.z); PH.y = (g === null ? th(PH.x, PH.z) : g) + r.h * r.prof(t); PH.gh_prev = PH.y; PH.vy = Math.max(0, PH.vy); }
      else if (r.on) {
        r.on = false; if (t > 1 && inX && !PH.hurt) {
          const sp = Math.abs(PH.vz), slope = (r.h * (1 - r.prof(.92))) / (r.len * .08), kind = r.mat;
          PH.grounded = false; PH.air_t = 0; PH.vy = Math.min(26, slope * sp * .55 + (C.JUMP_BLAST || 2) * 2.2 * r.hm * (kind === 'wood' ? 1.15 : 1)); PH.vz -= (kind === 'glass' ? 7 : kind === 'rust' ? -2 : 2) * SPK; PH.boost_t = Math.max(PH.boost_t, 1.2); PH.score += kind === 'neon' ? 300 : 150; PH.jumps++;
          toast(kind.toUpperCase() + ' ' + r.name, '#' + col(kind).map((c2) => Math.round(Math.min(1, c2) * 15).toString(16)).join('')); try { hooks.onLaunch && hooks.onLaunch(r); } catch (e) { }
        }
      }
    }
    for (const g of rings) { if (g.taken || Math.abs(g.z - PH.z) > 3) continue; if (Math.hypot(PH.x - g.x, (PH.y + 1) - g.y) < g.r) { g.taken = true; g.mesh.visible = false; PH.score += 80; PH.boost_t = Math.max(PH.boost_t, .8); toast('RING', '#fc6'); try { hooks.onRing && hooks.onRing(g); } catch (e) { } } }
  }
  return { buildRow, step, ramps, rings, designs: { RAMPS, RAILD }, MATS };
}
