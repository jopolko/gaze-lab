// BIOME PROPS: set dressing that belongs to one biome, scattered beside the road as the rows come into view (decoration only, nothing to hit). Each kind is one small vertex-coloured mesh drawn as an instanced
// mesh, so a whole biome's props cost a handful of draw calls. Positions come from a per-row dice roll (the run's seed), so a run is repeatable with &seed= and every run is different.
//   alpine     cairns, wooden signposts, red-tipped snow poles
//   candy      lollipops, candy canes, gumdrops
//   desert     saguaro cacti, dead trees, bleached boulders
//   matrix     data columns, glowing glyph slabs, floating cubes
//   synthwave  palm trees, neon posts
//   tunnel     big ribs standing across the road, like the frame of a tube
// &props=0 turns them off, &propsk=2 doubles how many.
export function createBiomeProps(o) {
  const { THREE, scene, groundY, trailX, PH, theme, seed = 7 } = o;
  const T = (x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = sx, sz = sx) => new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz, 'YXZ')), new THREE.Vector3(sx, sy, sz));
  const mk = (parts) => { const P = [], N = [], C = []; for (const { g, c, m } of parts) { const gg = g.index ? g.toNonIndexed() : g.clone(); gg.applyMatrix4(m || new THREE.Matrix4()); if (!gg.attributes.normal) gg.computeVertexNormals(); const p = gg.attributes.position, n = gg.attributes.normal; for (let i = 0; i < p.count; i++) { P.push(p.getX(i), p.getY(i), p.getZ(i)); N.push(n.getX(i), n.getY(i), n.getZ(i)); const sh = .72 + .28 * n.getY(i); C.push(c[0] * sh, c[1] * sh, c[2] * sh); } }
    const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); geo.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); return geo; };
  const cyl = (r0, r1, h, c, x, y, z, seg = 8, rx = 0, rz = 0) => ({ g: new THREE.CylinderGeometry(r1, r0, h, seg), c, m: T(x, y + h / 2, z, rx, 0, rz) });
  const ball = (r, c, x, y, z, sx = 1, sy = 1, sz = 1, det = 1) => ({ g: new THREE.IcosahedronGeometry(r, det), c, m: T(x, y, z, 0, 0, 0, sx, sy, sz) });
  const box = (w, h, d, c, x, y, z, ry = 0, rz = 0) => ({ g: new THREE.BoxGeometry(w, h, d), c, m: T(x, y, z, 0, ry, rz) });
  const caps = (r, len, c, x, y, z, rx = 0, rz = 0) => ({ g: new THREE.CapsuleGeometry(r, len, 3, 8), c, m: T(x, y, z, rx, 0, rz) });
  const K = {};
  if (theme === 'alpine') {
    K.cairn = { n: 3, geo: mk([ball(1.1, [.62, .62, .66], 0, .6, 0, 1.2, .55, 1.1), ball(.8, [.55, .55, .6], .1, 1.45, 0, 1.2, .55, 1.1), ball(.55, [.7, .7, .74], 0, 2.1, .05, 1.1, .6, 1.1)]), sc: [.9, 1.5] };
    K.sign = { n: 2, geo: mk([cyl(.1, .1, 2.8, [.42, .27, .14], 0, 0, 0, 6), box(1.6, .5, .1, [.62, .42, .22], .35, 2.3, 0), box(1.3, .4, .1, [.55, .36, .18], -.25, 1.7, 0, 0, .08)]), sc: [.9, 1.2] };
    K.pole = { n: 6, geo: mk([cyl(.07, .07, 3.6, [.9, .9, .95], 0, 0, 0, 5), cyl(.09, .09, .7, [.95, .15, .1], 0, 2.9, 0, 5)]), sc: [.9, 1.1] };
  } else if (theme === 'candy') {
    K.lolly = { n: 3, geo: mk([cyl(.12, .12, 5, [1, 1, 1], 0, 0, 0, 6), { g: new THREE.TorusGeometry(1.4, .5, 8, 18), c: [1, .55, .75], m: T(0, 6.3, 0) }, { g: new THREE.TorusGeometry(.65, .38, 6, 14), c: [1, .95, .5], m: T(0, 6.3, .05) }]), sc: [.9, 1.5], tint: true };
    K.cane = { n: 3, geo: (() => { const pts = []; for (let i = 0; i <= 12; i++) pts.push(new THREE.Vector3(0, i * .4, 0)); for (let i = 1; i <= 10; i++) { const a = (i / 10) * Math.PI; pts.push(new THREE.Vector3(Math.sin(a) * .9, 4.8 + (1 - Math.cos(a)) * .45, 0)); } const g = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 40, .28, 7), n = g.attributes.position.count, c = []; for (let i = 0; i < n; i++) { const st = Math.floor(i / 8) % 2; c.push(st ? 1 : .95, st ? 1 : .15, st ? 1 : .25); } g.setAttribute('color', new THREE.Float32BufferAttribute(c, 3)); return g.toNonIndexed(); })(), sc: [.9, 1.4], raw: true };
    K.drop = { n: 5, geo: mk([{ g: new THREE.SphereGeometry(1, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), c: [1, .8, .9], m: T(0, 0, 0, 0, 0, 0, 1.2, 1, 1.2) }]), sc: [.9, 2.2], tint: true };
  } else if (theme === 'desert') {
    K.cactus = { n: 4, geo: mk([caps(.55, 4.8, [.2, .55, .25], 0, 2.9, 0), caps(.35, 1.4, [.22, .6, .28], -1.1, 3.2, 0, 0, 1.2), cyl(.3, .3, 1.5, [.22, .6, .28], -1.65, 2.9, 0, 7), caps(.33, 1.2, [.22, .6, .28], 1.0, 3.9, 0, 0, -1.2), cyl(.28, .28, 1.2, [.22, .6, .28], 1.5, 3.7, 0, 7)]), sc: [.8, 1.5] };
    K.deadtree = { n: 2, geo: mk([cyl(.35, .12, 4.5, [.35, .28, .22], 0, 0, 0, 6), cyl(.15, .05, 2.2, [.35, .28, .22], 0, 2.6, 0, 5, 0, .9), cyl(.12, .05, 1.8, [.35, .28, .22], 0, 3.3, 0, 5, 0, -1.0)]), sc: [.9, 1.3] };
    K.boulder = { n: 3, geo: mk([ball(1.6, [.8, .62, .48], 0, .8, 0, 1.3, .8, 1, 1), ball(1, [.72, .55, .42], 1.3, .5, .4, 1, .7, 1, 1)]), sc: [.8, 1.8] };
  } else if (theme === 'matrix') {
    K.column = { n: 4, geo: mk([box(1.4, 22, 1.4, [.03, .12, .05], 0, 11, 0), box(1.5, .5, 1.5, [.2, 1, .45], 0, 22.2, 0), box(.18, 20, 1.42, [.1, .7, .3], .5, 11, 0)]), sc: [.6, 1.8] };
    K.slab = { n: 3, geo: mk([box(3.2, 8, .25, [.05, .35, .15], 0, 4, 0), box(2.7, 7.2, .3, [.15, .9, .4], 0, 4, 0)]), sc: [.8, 1.4] };
    K.cube = { n: 3, geo: mk([box(1.6, 1.6, 1.6, [.1, .8, .35], 0, 7, 0, .6), box(1.1, 1.1, 1.1, [.5, 1, .6], 0, 7, 0, .3)]), sc: [.7, 1.4] };
  } else if (theme === 'synthwave') {
    K.palm = { n: 4, geo: (() => { const parts = [cyl(.35, .22, 6.5, [.18, .08, .22], 0, 0, 0, 6, 0, .08)]; for (let i = 0; i < 8; i++) { const a = i / 8 * Math.PI * 2; parts.push({ g: new THREE.ConeGeometry(.55, 3.8, 4), c: i % 2 ? [.95, .2, .65] : [.55, .1, .6], m: T(Math.cos(a) * 1.5, 6.7 - .2, Math.sin(a) * 1.5, Math.sin(a) * 1.1, 0, -Math.cos(a) * 1.1 - 0) }); } return mk(parts); })(), sc: [.9, 1.5] };
    K.neon = { n: 4, geo: mk([box(.35, 9, .35, [.1, .05, .15], 0, 4.5, 0), box(.5, 1.6, .5, [1, .2, .7], 0, 9.5, 0), box(.7, .15, .7, [.2, .9, 1], 0, 8.5, 0)]), sc: [.8, 1.6] };
  } else if (theme === 'tunnel') {
    K.rib = { n: 1, geo: mk([{ g: new THREE.TorusGeometry(34, 1.3, 6, 36), c: [.2, .9, 1], m: T(0, 0, 0) }, { g: new THREE.TorusGeometry(34, .5, 5, 36), c: [1, .25, .8], m: T(0, 0, 1.3) }]), sc: [1, 1], rib: true };
  }
  const kinds = Object.keys(K); if (!kinds.length) return { step() { }, count: () => 0 };
  const CAP = 90, mat = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.DoubleSide });
  const ZERO = new THREE.Matrix4().makeScale(0, 0, 0), meshes = {}, free = {}, rows = new Map();
  for (const k of kinds) { const im = new THREE.InstancedMesh(K[k].geo, mat, CAP); im.frustumCulled = false; im.count = CAP; for (let i = 0; i < CAP; i++) im.setMatrixAt(i, ZERO); if (K[k].tint) for (let i = 0; i < CAP; i++) im.setColorAt(i, new THREE.Color(1, 1, 1)); im.instanceMatrix.needsUpdate = true; scene.add(im); meshes[k] = im; free[k] = Array.from({ length: CAP }, (_, i) => CAP - 1 - i); }
  const mulberry = (a) => () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const PAL = [[1, .45, .75], [.55, .85, 1], [1, .85, .3], [.7, .5, 1], [.5, 1, .7], [1, .55, .35]];
  const K2 = Math.max(.2, Math.min(4, parseFloat(new URLSearchParams(location.search).get('propsk') || '1')));
  function spawnRow(j) {
    const placed = [], R = mulberry(j * 1319 + (seed % 100000) * 17 + 5); let pending = false;
    for (const k of kinds) { const d = K[k]; const cnt = d.rib ? 3 : Math.max(0, Math.round(d.n * K2 * (.6 + .8 * R()))); for (let q = 0; q < cnt; q++) {
      const z = d.rib ? -180 * j - (q * 60 + 20) : -180 * j - R() * 180, side = R() < .5 ? -1 : 1, off = d.rib ? 0 : 17 + R() * 34, x = trailX(z) + side * off, g = groundY(x, z); if (g === null || g === undefined) { pending = true; continue; }
      const slot = free[k].pop(); if (slot === undefined) continue; const s = d.sc[0] + R() * (d.sc[1] - d.sc[0]), yaw = R() * 6.28;
      meshes[k].setMatrixAt(slot, d.rib ? T(x, g - 4, z, 0, 0, 0, 1) : T(x, g - .1, z, 0, yaw, 0, s)); if (d.tint) meshes[k].setColorAt(slot, new THREE.Color(...PAL[Math.floor(R() * PAL.length)]));
      placed.push([k, slot]); } }
    for (const k of kinds) { meshes[k].instanceMatrix.needsUpdate = true; if (meshes[k].instanceColor) meshes[k].instanceColor.needsUpdate = true; }
    return { placed, pending };
  }
  function freeRow(r) { for (const [k, slot] of r.placed) { meshes[k].setMatrixAt(slot, ZERO); free[k].push(slot); } for (const k of kinds) meshes[k].instanceMatrix.needsUpdate = true; }
  function step() {
    const j0 = Math.max(0, Math.floor(-PH.z / 180));
    for (let j = j0; j <= j0 + 5; j++) { const r = rows.get(j); if (!r) rows.set(j, spawnRow(j)); else if (r.pending && (j - j0) <= 4 && (performance.now() - (r.t || 0) > 600)) { r.t = performance.now(); freeRow(r); rows.set(j, spawnRow(j)); } }
    for (const [j, r] of rows) if (j < j0 - 2 || j > j0 + 8) { freeRow(r); rows.delete(j); }
  }
  return { step, count: () => [...rows.values()].reduce((a, r) => a + r.placed.length, 0) };
}
