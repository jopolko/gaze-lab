// KIT: custom ramps, rails and ring arcs in five cheap materials (steel, glass, wood, neon, rust). Every object is a few merged triangles; every material is ONE small shader that picks its look from a per-vertex
// material id, so the whole kit is two draw calls (one opaque, one see-through for glass) however many objects stand on the course. The looks are fakes, on purpose:
//   steel  a gradient "reflection" of the sky with a sharp highlight and a rim brightening        glass  a pale tint that is mostly clear in the middle and bright at the edges (fresnel), blended
//   wood   warm grain bands from the surface coordinates                                           neon   a pulsing emissive colour           rust  two layers of noise between brown and orange
// No environment map, no refraction, no extra render pass: that is what makes real glass and mirrors expensive, and the reason they are not used.
//
// The physics reads plain records: rails go into the game's RAILS list (so the existing grind code rides them, curved ones through f.cv(z)); ramps and rings are stepped by kit.step().
import * as THREE from 'three';
import { createPickupMesh } from './pickupmesh.js';

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
  if (m < 0.5) { float spec = pow(max(dot(R, normalize(uSun)), 0.0), 60.0); float band = smoothstep(-0.15, 0.25, R.y) - 0.35 * smoothstep(0.25, 0.9, R.y); col = (mix(uHor * 0.35, uTop * 1.15, clamp(band + 0.35, 0.0, 1.0)) + 0.25) * (0.7 + 0.6 * fr) + vec3(1.0) * spec * 1.6; }
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
const RAILD_OLD = [
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
const RAILD = [
  { id: 'pipe', name: 'PIPE', kind: 'tube', rad: .22, mats: ['steel'] },
  { id: 'bar', name: 'BAR', kind: 'beam', mats: ['steel'] },
  { id: 'twin', name: 'TWIN RAIL', kind: 'twin', rad: .13, mats: ['steel'] },
];
const ARCS = ['parabola', 'spiral', 'ladder', 'sweep', 'low'];

export function createKit(o) {
  const { scene, th, groundY, trailX, PH, C, SPK, RAILS, toast, hooks = {}, PADS, BUFFS, onTarget, nrows = 43, zoneOf = () => 'content', seed = 7 } = o;
  const PM = createPickupMesh(THREE), _m = new THREE.Matrix4(), _v = new THREE.Vector3(), _s = new THREE.Vector3(), qA = new THREE.Quaternion(), qB = new THREE.Quaternion(), qC = new THREE.Quaternion(), _up = new THREE.Vector3(0, 1, 0), _xax = new THREE.Vector3(1, 0, 0), ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
  const U = { uTime: { value: 0 }, uGlass: { value: 0 }, uSun: { value: new THREE.Vector3(.4, .8, .3) }, uTop: { value: new THREE.Vector3(.35, .45, .95) }, uHor: { value: new THREE.Vector3(.9, .7, .85) } };
  const matO = new THREE.ShaderMaterial({ uniforms: { ...U, uGlass: { value: 0 } }, vertexShader: VERT, fragmentShader: FRAG }), matG = new THREE.ShaderMaterial({ uniforms: { ...U, uGlass: { value: 1 } }, vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false, side: THREE.DoubleSide });
  const mid = (m) => MATS.indexOf(m), col = (m) => MCOL[m];
  const ramps = [], rings = [], used = new Set(), recent = []; let t0 = 0, lastRailX = -99;

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

  function buildRail(d, mat, x, z0, B, len) {
    const L = len || d.len || 48, n = Math.max(6, Math.round(L / 3)), f = { mine: true, kind: 'rail', kit: true, mat, col: col(mat), name: d.name, kx: x, sd: 0, za: z0, zb: z0 - L, done: false };
    if (d.cv) f.cv = d.cv.tri ? (z) => d.cv.amp * (2 / Math.PI) * Math.asin(Math.sin((z0 - z) / d.cv.wl * Math.PI * 2)) : (z) => d.cv.amp * Math.sin((z0 - z) / d.cv.wl * Math.PI * 2);
    const path = [], RH = (C && C.RAIL_H) || .9; for (let i = 0; i <= n; i++) { const z = z0 - L * i / n, xx = x + (f.cv ? f.cv(z) : 0), g = groundY(xx, z), gy = g === null ? th(xx, z) : g; const tt = Math.max(0, Math.min(1, (z0 - z) / 4)); path.push([xx, gy + .15 + (RH - .15) * tt * tt * (3 - 2 * tt), z]); }
    const c = col(mat), m = mid(mat);
    if (d.kind === 'tube') addTube(B, path, d.rad, 7, c, m); else if (d.kind === 'beam') addBeam(B, path, .42, .16, c, m); else if (d.kind === 'twin') { for (const off of [-.5, .5]) addTube(B, path.map((p) => [p[0] + off, p[1], p[2]]), d.rad, 6, c, m); }
    for (let i = 0; i <= n; i += 2) { const p = path[i], g = groundY(p[0], p[2]); addPost(B, p[0], g === null ? p[1] - RH : g, p[1], p[2], [.6, .62, .7], 0); }
    RAILS.push(f); return f;
  }

  function buildRings(r, x0, zLip, mat, design) {          // hoops in the air after the lip, in five arrangements: parabola, spiral, ladder, sweep, low
    const NR = design === 'stream' ? 13 : design === 'spiral' ? 8 : design === 'low' ? 6 : 5; for (let i = 0; i < NR; i++) { const z = zLip - 20 - i * (design === 'low' ? 11 : design === 'stream' ? 7 : 14); let x = x0, hh = 3.6 + 5.2 * Math.sin(Math.PI * (i + .5) / NR); if (design === 'stream') { x = x0 + Math.sin(i * .5) * 3.2; hh = 1.9 + .5 * Math.sin(i * .7); } else if (design === 'spiral') { const a = i * 1.1; x = x0 + Math.sin(a) * 3.4; hh = 5.5 + Math.cos(a) * 2.6; } else if (design === 'ladder') hh = 2.6 + i * 1.6; else if (design === 'sweep') { x = x0 + Math.sin(i * .9) * 9; hh = 4.5 + Math.sin(i * .5) * 1.5; } else if (design === 'low') hh = 1.9; const g = groundY(x, z), gy = g === null ? th(x, z) : g, y = gy + hh;
      const geo = new THREE.TorusGeometry(2.7, .3, 6, 14), mesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: new THREE.Color(1.6, 1.2, .35), fog: false })); mesh.position.set(x, y, z); mesh.frustumCulled = false; scene.add(mesh); rings.push({ x, y, z, r: 3.1, mesh, taken: false }); }
  }

  // ---------------------------------------------------------------- the PHRASE DECK: which phrase each row of the course holds, decided once for the whole course from the seed
  // A phrase is a short chain where each piece leads to the next. The deck is shuffled like cards: a phrase may not repeat within 5 rows, a lane (left .. right) may not repeat within 2 rows, and
  // chapters (7 rows each) add phrases one at a time. 'launch' rows hold a natural ramp (fixed by the course), 'slalom' rows come from the course zones.
  const LANES = [-17, -9, 0, 9, 17]; let plan = null, vxRows = new Set();
  function planCourse() {
    plan = {}; const R = mulberry(((seed * 2654435761) >>> 0) ^ 0x9e3779b9), recent = [], lanes = [];
    for (let j = 1; j < nrows; j++) {
      const zn = zoneOf(j); if (zn === 'slalom') { plan[j] = { phrase: 'slalom' }; recent.push('slalom'); continue; }
      if (vxRows.has(j)) { plan[j] = { phrase: 'launch' }; recent.push('launch'); continue; }
      const ch = Math.floor(j / 7), allowed = [['open', ch === 0 ? 3 : 2], ['boostrun', 3]]; if (ch >= 1) allowed.push(['boostgrind', 3]); if (ch >= 2) allowed.push(['warm', 2]);
      let pool = allowed.filter(([id]) => !recent.slice(-5).includes(id)); if (!pool.length) pool = allowed.filter(([id]) => id !== recent[recent.length - 1]); if (!pool.length) pool = allowed;
      const tot = pool.reduce((a, [, w]) => a + w, 0); let r = R() * tot, pick = pool[0][0]; for (const [id, w] of pool) { if ((r -= w) <= 0) { pick = id; break; } }
      const free = LANES.filter((l) => !lanes.slice(-2).includes(l)), lane = free[Math.floor(R() * free.length)];
      plan[j] = { phrase: pick, lane }; recent.push(pick); if (pick !== 'open') lanes.push(lane);
    }
  }
  function setVxRows(rows) { vxRows = new Set(rows); plan = null; }
  const phraseOf = (j) => { if (!plan) planCourse(); return (plan[j] && plan[j].phrase) || 'open'; };

  function makePad(x, z, R) {          // the Godot pad (chevron bars, glow pool, hovering crystal), one at a time: the same meshes the course's own pads had
    const spec = PM.pad(false), ims = spec.parts.map((pt) => { const im = new THREE.InstancedMesh(pt.geo, pt.mat, 1); im.frustumCulled = false; scene.add(im); return im; }); ims[1].renderOrder = 3; ims[3].renderOrder = 4;
    const gyf = (xx, zz) => { const g = groundY(xx, zz); return g === null ? th(xx, zz) : g; }, zz = z - 2.2, y = gyf(x, zz), pit = -Math.atan((gyf(x, zz + .6) - gyf(x, zz - .6)) / 1.2), p = { mine: true, x, z, used: false, epic: false, ph: R() * 6.28 };
    ims[0].setMatrixAt(0, _m.compose(_v.set(x, y, zz), qA.setFromAxisAngle(_xax, pit), _s.set(1, 1, 1))); ims[1].setMatrixAt(0, _m.compose(_v.set(x, y + .15, zz), qB.setFromAxisAngle(_xax, -Math.PI / 2 + pit), _s.set(8, 8, 1)));
    p.upd = (age) => { const gyy = y + 1.35 + .22 * Math.sin(age * 2.6 + p.ph); ims[2].setMatrixAt(0, _m.compose(_v.set(x, gyy, zz), qC.setFromAxisAngle(_up, age * 1.8 + p.ph), _s.set(1.25, 1.25, 1.25))); ims[3].setMatrixAt(0, _m.compose(_v.set(x, gyy, zz), qB.identity(), _s.set(3.6, 3.6, 1))); for (const im of ims) im.instanceMatrix.needsUpdate = true; };
    p.hideSelf = () => { p.hidden = true; for (const im of ims) { im.setMatrixAt(0, ZERO); im.instanceMatrix.needsUpdate = true; } };
    p.upd(0); for (const im of ims) im.instanceMatrix.needsUpdate = true; PADS.push(p); try { onTarget && onTarget(p, 'pad'); } catch (e) { } return p;
  }
  function makeBuff(t, x, z, R) {          // a powerup (the Godot kit shape, halo and pool), one at a time
    const spec = PM.buff(t), ims = [0, 1, 2].map((k) => { const im = new THREE.InstancedMesh(spec.parts[k].geo, spec.parts[k].mat, 1); im.frustumCulled = false; scene.add(im); return im; }); ims[1].renderOrder = 4; ims[2].renderOrder = 3;
    const g = groundY(x, z), y = (g === null ? th(x, z) : g) + 2.4, b = { mine: true, x, z, y, t, kind: 'path', taken: false, orbs: [], ph: R() * 6.28, base: y };
    b.upd = (age) => { const a = spec.anim(age, b.ph), yy = b.y + a.bobY; ims[0].setMatrixAt(0, _m.compose(_v.set(b.x, yy, b.z), qA.setFromAxisAngle(_up, a.spinY), _s.set(1.3, 1.3, 1.3))); const hs = 6.2 * a.haloScale; ims[1].setMatrixAt(0, _m.compose(_v.set(b.x, yy, b.z), qB.identity(), _s.set(hs, hs, 1))); ims[2].setMatrixAt(0, _m.compose(_v.set(b.x, yy - 1.6, b.z), qC.setFromAxisAngle(_xax, -Math.PI / 2), _s.set(7, 7, 1))); for (const im of ims) im.instanceMatrix.needsUpdate = true; };
    b.hideSelf = () => { b.hidden = true; for (const im of ims) { im.setMatrixAt(0, ZERO); im.instanceMatrix.needsUpdate = true; } };
    b.upd(0); BUFFS.push(b); try { onTarget && onTarget(b, t); } catch (e) { } return b;
  }
  const weighted = (R) => { const r = R(); return r < .4 ? 'boost' : r < .55 ? 'shield' : r < .78 ? 'mult' : 'donut'; };

  // build the objects of one row (the game calls it when the row's ground exists); `spans` are z ranges to stay out of
  function buildRow(j, rr, z0, spans) {
    if (used.has(j)) return; used.add(j);
    const R = mulberry(j * 7919 + 4242), B = GeoBuf(), BG = GeoBuf(); let made = 0;
    const ph = phraseOf(j), pl = plan[j] || {}, lane = pl.lane === undefined ? 0 : pl.lane, t0 = 28 + Math.floor(R() * 40), clear = (za, zb) => !spans.some((s2) => zb < s2[1] + 8 && za > s2[0] - 25);
    if (ph === 'boostrun') { const za = z0 - t0, zb = za - 44 - 60; if (clear(za, zb)) { for (let i = 0; i < 3; i++) makePad(trailX(za - i * 22) + lane + (R() - .5) * 3, za - i * 22, R); makeBuff(weighted(R), trailX(zb) + lane + (R() < .5 ? -1 : 1) * (5 + R() * 5), zb, R); made++; } }
    else if (ph === 'boostgrind') { const len = 28 + Math.floor(R() * 5) * 11, za = z0 - t0, zr = za - 16, zb = zr - len - 40; if (clear(za, zb)) { const x = trailX(za) + lane; makePad(x, za, R); buildRings({ x, z0: zr, len }, x, zr + 20, 'steel', 'stream'); made++; makeBuff(weighted(R), trailX(zb) + lane + Math.sin(12.5) * 3.2, zr - 20 - 13 * 7 - 12, R); } }          // pad -> a winding stream of rings -> a powerup at its end (no rail: nothing locks the board)
    for (let k = 0; k < 0; k++) {          // (the old scattered ramps and rails are off)
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

  // after a natural ramp: hoops along the flight and a chrome rail to land on, in line with the ramp
  function buildAfterRamp(v, spans) {
    const R = mulberry((Math.abs(Math.floor(v.z)) * 31 + 7) >>> 0), B = GeoBuf(), zLip = v.z - v.len, x = v.x; let made = false;
    made = true;          // (the hoops, the landing target and the stream are made at the moment of the jump, from the real flight: launch())
    const z = zLip - 34 - R() * 10;
    if (made) { const mesh = new THREE.Mesh(B.geo(), matO); mesh.frustumCulled = false; scene.add(mesh); if (R() < .6) makeBuff(weighted(R), x + (R() - .5) * 8, z - 70 - R() * 20, R); }
  }

  // ---------------------------------------------------------------- LANDING TARGETS: after a natural ramp a bullseye lies on the slope where the jump comes down. While you are in the air a ring on the ground shows where you will
  // land (it turns gold when that is on the target), and landing on it pays by ring (outer 50, middle 150, centre 500), gives a boost, and throws confetti.
  const targets = [], bursts = []; let airT = 0;
  const reticle = new THREE.Mesh(new THREE.RingGeometry(1.1, 1.7, 36), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.2, 1.2, 1.2), transparent: true, opacity: .9, depthTest: false, toneMapped: false, fog: false, side: THREE.DoubleSide })); reticle.rotation.x = -Math.PI / 2; reticle.visible = false; reticle.renderOrder = 9; reticle.frustumCulled = false; scene.add(reticle);
  function buildTarget(x, zc) {
    const gyf = (xx, zz) => { const g = groundY(xx, zz); return g === null ? th(xx, zz) : g; }, y = gyf(x, zc), dh = (gyf(x, zc + 4) - gyf(x, zc - 4)) / 8, n = new THREE.Vector3(0, 1, -dh).normalize(), grp = new THREE.Group(), flat = new THREE.Group();
    const discs = [[9, [1.5, 1.5, 1.6]], [5.2, [1.9, .3, .3]], [2.4, [2, 1.5, .3]]]; discs.forEach(([r, c], i) => { const m = new THREE.Mesh(new THREE.CircleGeometry(r, 44), new THREE.MeshBasicMaterial({ color: new THREE.Color(c[0], c[1], c[2]), toneMapped: false, fog: false, polygonOffset: true, polygonOffsetFactor: -2 - i, polygonOffsetUnits: -2 - i })); m.rotation.x = -Math.PI / 2; m.position.y = .08 + i * .05; flat.add(m); });
    grp.add(flat); grp.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), n); grp.position.set(x, y, zc); scene.add(grp);
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(.35, .35, 34, 8, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(2, 1.5, .4), transparent: true, opacity: .32, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, fog: false })); beam.position.set(x, y + 17, zc); beam.frustumCulled = false; scene.add(beam);
    targets.push({ x, z: zc, y, r: 9, rings: [9, 5.2, 2.4], grp, beam, done: false, t: 0 });
  }
  function predictLanding() {          // where the board will touch down if nothing changes (the game's own air gravity)
    let x = PH.x, y = PH.y, z = PH.z, vx = PH.vx, vy = PH.vy, vz = PH.vz; const g = (C.GV || 9.8) * (C.AIR_G_K || 2.1);
    for (let i = 0; i < 90; i++) { const dt = .05; vy -= g * dt; x += vx * dt; y += vy * dt; z += vz * dt; const gg = groundY(x, z), gy = gg === null ? th(x, z) : gg; if (y <= gy + .3) return { x, z, y: gy }; }
    return null;
  }
  function confetti(x, y, z, count) {
    const N = count || 150, pos = new Float32Array(N * 3), col = new Float32Array(N * 3), vel = []; for (let i = 0; i < N; i++) { pos[i * 3] = x; pos[i * 3 + 1] = y + 1; pos[i * 3 + 2] = z; const a = Math.random() * 6.283, up = 8 + Math.random() * 14, sp2 = 2 + Math.random() * 9; vel.push([Math.cos(a) * sp2, up, Math.sin(a) * sp2]); const h = Math.random(); const c = new THREE.Color().setHSL(h, 1, .6); col[i * 3] = c.r * 1.6; col[i * 3 + 1] = c.g * 1.6; col[i * 3 + 2] = c.b * 1.6; }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('color', new THREE.BufferAttribute(col, 3)); const pts = new THREE.Points(g, new THREE.PointsMaterial({ size: 1.3, vertexColors: true, transparent: true, depthWrite: false, toneMapped: false, fog: false })); pts.frustumCulled = false; scene.add(pts); bursts.push({ pts, vel, age: 0, N });
  }
  function hitTarget(t, d) {
    const ring = d < t.rings[2] ? 2 : d < t.rings[1] ? 1 : 0, pts = [50, 150, 500][ring], name = ['NICE LANDING', 'GREAT LANDING', 'BULLSEYE!'][ring], colr = ['#fff', '#f66', '#fc3'][ring]; t.done = true; t.t = 0;
    PH.score += pts; PH.boost_t = Math.max(PH.boost_t, 1.2 + ring * .8); toast(name + '  +' + pts, colr); confetti(t.x, t.y, t.z); if (ring === 2) { confetti(t.x + 3, t.y, t.z - 3); confetti(t.x - 3, t.y, t.z + 3); }
    try { hooks.cheer && hooks.cheer([PH.x, PH.y + 1, PH.z], [1, .6 + .2 * ring, .3], 1 + ring * .5); hooks.sfx && hooks.sfx(); hooks.chain && hooks.chain(); } catch (e) { }
  }
  function targetsStep(dt) {
    const air = !PH.grounded && !PH.rail; if (air) airT += dt; else { const was = airT; airT = 0; if (was > .5) { for (const t of targets) { if (t.done || Math.abs(t.z - PH.z) > 14) continue; const d = Math.hypot(PH.x - t.x, PH.z - t.z); if (d < t.r) hitTarget(t, d); } } }
    let near = null; for (const t of targets) { if (t.done || t.z > PH.z + 6 || PH.z - t.z > 170) continue; if (!near || t.z > near.z) near = t; }
    if (air && near) { const L = predictLanding(); if (L) { const d = Math.hypot(L.x - near.x, L.z - near.z), on = d < near.r, pulse = 1 + .12 * Math.sin(t0 * 9); reticle.visible = true; reticle.position.set(L.x, L.y + .2, L.z); reticle.scale.setScalar(pulse); reticle.material.color.setRGB(on ? 2 : 1.2, on ? 1.5 : 1.2, on ? .3 : 1.2); } else reticle.visible = false; } else reticle.visible = false;
    for (const t of targets) { if (!t.done) { t.grp.scale.setScalar(1 + .03 * Math.sin(t0 * 4 + t.z)); t.beam.visible = Math.abs(t.z - PH.z) < 260; } else { t.t += dt; const k = Math.max(0, 1 - t.t / 2.5); t.grp.scale.setScalar(1 + (1 - k) * .6); t.beam.material.opacity = .32 * k + .25 * Math.max(0, 1 - t.t * 2); if (t.t > 2.5) { t.grp.visible = false; t.beam.visible = false; } } }
    for (let b = bursts.length - 1; b >= 0; b--) { const B = bursts[b]; B.age += dt; const p = B.pts.geometry.attributes.position; for (let i = 0; i < B.N; i++) { const v = B.vel[i]; v[1] -= 16 * dt; v[0] *= Math.exp(-.6 * dt); v[2] *= Math.exp(-.6 * dt); p.array[i * 3] += v[0] * dt; p.array[i * 3 + 1] += v[1] * dt; p.array[i * 3 + 2] += v[2] * dt; } p.needsUpdate = true; B.pts.material.opacity = Math.max(0, 1 - B.age / 2.8); if (B.age > 2.8) { scene.remove(B.pts); B.pts.geometry.dispose(); B.pts.material.dispose(); bursts.splice(b, 1); } }
  }

  // ---------------------------------------------------------------- THE FLIGHT IS MEASURED, NOT GUESSED: at the moment a board leaves a natural ramp the game calls launch(). It simulates the flight from the board's real
  // position and speed (the same air gravity), then puts the hoops ON that path (a few of them, wandering a little), a landing target a few metres off where the board would come down (so a little air steering is
  // needed to hit it), and a stream of rings carrying on from the landing. Everything is made at that moment, for that jump.
  const RGEO = new THREE.TorusGeometry(2.7, .3, 10, 28), RMAT = new THREE.MeshBasicMaterial({ color: new THREE.Color(1.6, 1.2, .35), fog: false });
  function addRing(x, y, z, r) { const mesh = new THREE.Mesh(RGEO, RMAT); mesh.position.set(x, y, z); mesh.frustumCulled = false; scene.add(mesh); rings.push({ x, y, z, r: r || 3.1, mesh, taken: false }); }
  function flightPath() { let x = PH.x, y = PH.y, z = PH.z, vx = PH.vx, vy = PH.vy, vz = PH.vz; const g = (C.GV || 9.8) * (C.AIR_G_K || 2.1), pts = []; for (let i = 0; i < 90; i++) { const dt = .05; vy -= g * dt; x += vx * dt; y += vy * dt; z += vz * dt; const gg = groundY(x, z), gy = gg === null ? th(x, z) : gg; pts.push({ x, y, z, gy }); if (y <= gy + .3) break; } return pts; }
  function launch() {
    const pts = flightPath(); if (pts.length < 4) return; const R = mulberry((Math.floor(Math.abs(PH.z) * 13) + 91) >>> 0), L = pts[pts.length - 1], design = ARCS[Math.floor(R() * 4)], n = Math.min(5, Math.max(3, Math.floor(pts.length / 3)));
    for (let i = 0; i < n; i++) { const p = pts[Math.min(pts.length - 2, Math.floor((i + 1) / (n + 1) * pts.length))]; let dx = 0; if (design === 'spiral') dx = Math.sin(i * 1.3) * 3; else if (design === 'sweep') dx = Math.sin(i * .9) * 5; addRing(p.x + dx, p.y + 1.1, p.z); }
    const off = (R() < .5 ? -1 : 1) * (4 + R() * 5), tx = L.x + off, tz = L.z - 6 - R() * 10; buildTarget(tx, tz); buildRings({ x: tx, z0: tz, len: 90 }, tx - off * .5, tz + 22, 'steel', 'stream');
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
    targetsStep(dt);
    for (const g of rings) { if (g.taken || Math.abs(g.z - PH.z) > 3) continue; if (Math.hypot(PH.x - g.x, (PH.y + 1) - g.y) < g.r) { g.taken = true; g.mesh.visible = false; PH.score += 80; PH.boost_t = Math.max(PH.boost_t, .8); toast('RING', '#fc6'); confetti(g.x, g.y, g.z, 40); try { hooks.onRing && hooks.onRing(g); } catch (e) { } } }
  }
  { const warm = new THREE.Group(); const dummy = (geo, mat) => { const m = new THREE.Mesh(geo, mat); m.position.set(0, -4000, 0); m.scale.setScalar(.01); m.frustumCulled = false; warm.add(m); };
    dummy(RGEO, RMAT); dummy(new THREE.CircleGeometry(1, 8), new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false, fog: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 })); dummy(new THREE.CylinderGeometry(.3, .3, 1, 6, 1, true), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: .3, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, fog: false })); dummy(new THREE.RingGeometry(1, 1.5, 8), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, depthTest: false, toneMapped: false, fog: false, side: THREE.DoubleSide }));
    { const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0], 3)); g.setAttribute('color', new THREE.Float32BufferAttribute([1, 1, 1], 3)); const pt = new THREE.Points(g, new THREE.PointsMaterial({ size: 1.3, vertexColors: true, transparent: true, depthWrite: false, toneMapped: false, fog: false })); pt.position.set(0, -4000, 0); pt.frustumCulled = false; warm.add(pt); } scene.add(warm); }          // (warm-up copies, see above)
  return { buildRow, buildAfterRamp, launch, phraseOf, setVxRows, step, ramps, rings, designs: { RAMPS, RAILD }, MATS };
}
