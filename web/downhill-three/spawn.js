// SPAWN: the content of the wide level, generated in the browser and laid across the whole width of the open snow (the Godot dump gives the terrain, the forest at the edges and the few ramps; everything the player goes after is made here).
// Pickups (the four kit shapes from RunRig._kit_mesh), boost pads (the chevron bars), rails (a chain of atoms, RunRig._build_rail), the six molecules as real ball-and-stick, glowing orb trails that lead sideways to far targets, and lone trees to avoid.
// Everything is instanced / merged so a phone draws a few dozen things, and every target is a plain record pushed into the same arrays the physics already reads (BUFFS, PADS, RAILS, PILLS), so collecting, chains, beacons and the goal icon all work on it unchanged.
import * as THREE from 'three';

const mulberry = (seed) => { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
const sphereG = new THREE.SphereGeometry(1, 9, 6), cylG = new THREE.CylinderGeometry(1, 1, 1, 6, 1), boxG = new THREE.BoxGeometry(1, 1, 1);
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _v = new THREE.Vector3(), _s = new THREE.Vector3(), _up = new THREE.Vector3(0, 1, 0);
const lerp3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

function merge(parts) {
  const P = [], N = [], C = [], I = []; let nv = 0;
  for (const p of parts) {
    const g = p.g.clone(); g.applyMatrix4(p.m); const pos = g.attributes.position, nor = g.attributes.normal, idx = g.index;
    for (let i = 0; i < pos.count; i++) { P.push(pos.getX(i), pos.getY(i), pos.getZ(i)); N.push(nor.getX(i), nor.getY(i), nor.getZ(i)); C.push(p.c[0], p.c[1], p.c[2]); }
    if (idx) for (let i = 0; i < idx.count; i++) I.push(idx.getX(i) + nv); else for (let i = 0; i < pos.count; i++) I.push(i + nv);
    nv += pos.count;
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); g.setIndex(I); return g;
}
const ball = (p, r, c) => ({ g: sphereG, m: new THREE.Matrix4().compose(new THREE.Vector3(...p), new THREE.Quaternion(), new THREE.Vector3(r, r, r)), c });
function stick(a, b, rad, c) { const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b), d = B.clone().sub(A), len = d.length(); if (len < 1e-4) return null; const q = new THREE.Quaternion().setFromUnitVectors(_up, d.clone().normalize()); return { g: cylG, m: new THREE.Matrix4().compose(A.clone().add(B).multiplyScalar(.5), q, new THREE.Vector3(rad, len, rad)), c }; }

// the kit shapes (RunRig._kit_mesh)
function kitGeo(kind, col) {
  const pale = lerp3(col, [1, 1, 1], .72), pts = [], bonds = []; let stk = .07;
  if (kind === 'crystal') { pts.push([[0, 0, 0], .36, col]); for (const v of [[0, 1.15, 0], [0, -1.15, 0], [.8, 0, 0], [-.8, 0, 0], [0, 0, .8], [0, 0, -.8]]) pts.push([v, .17, pale]); for (let i = 3; i < 7; i++) { bonds.push([1, i]); bonds.push([2, i]); } for (const pr of [[3, 5], [5, 4], [4, 6], [6, 3]]) bonds.push(pr); }
  else if (kind === 'cage') { pts.push([[0, 0, 0], .42, col]); const ph = (1 + Math.sqrt(5)) / 2; for (const a of [-1, 1]) for (const b of [-ph, ph]) for (const v of [[0, a, b], [a, b, 0], [b, 0, a]]) { const l = Math.hypot(...v); pts.push([v.map((x) => x / l * 1.15), .14, pale]); } for (let i = 1; i < 13; i++) for (let j = i + 1; j < 13; j++) if (Math.hypot(pts[i][0][0] - pts[j][0][0], pts[i][0][1] - pts[j][0][1], pts[i][0][2] - pts[j][0][2]) < 1.3) bonds.push([i, j]); stk = .055; }
  else if (kind === 'rings') { for (let r = 0; r < 2; r++) { for (let i = 0; i < 6; i++) { const a = i * Math.PI * 2 / 6; let v = [Math.cos(a) * .85, Math.sin(a) * .85, 0]; if (r === 1) v = [v[0] + .85, 0, v[1]]; pts.push([[v[0] - .42, v[1], v[2]], .19, r === 0 ? col : pale]); } for (let i = 0; i < 6; i++) bonds.push([r * 6 + i, r * 6 + (i + 1) % 6]); } }
  else { pts.push([[0, 0, 0], .24, pale]); for (const v of [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]]) { const l = Math.hypot(...v); pts.push([v.map((x) => x / l * .85), .4, col]); } for (let i = 1; i < 5; i++) bonds.push([0, i]); stk = .1; }
  const parts = pts.map((p) => ball(p[0], p[1], p[2])); for (const b of bonds) { const s = stick(pts[b[0]][0], pts[b[1]][0], stk, [.92, .92, .96]); if (s) parts.push(s); } return merge(parts);
}
const EL = { H: [[1, 1, 1], .5], C: null, N: [[.45, .6, 1], .8], O: [[1, .3, .3], .8], S: [[1, .9, .3], 1.05], Br: [[.8, .4, .2], 1.15] };
function molGeo(mol) {
  const A = mol.atoms, parts = []; let cx = 0, cy = 0, cz = 0; for (const a of A) { cx += a[1]; cy += a[2]; cz += a[3]; } cx /= A.length; cy /= A.length; cz /= A.length;
  const P = A.map((a) => [a[1] - cx, a[2] - cy, a[3] - cz]);
  A.forEach((a, i) => { const e = EL[a[0]]; parts.push(ball(P[i], (a[0] === 'H' ? .45 : a[0] === 'C' ? .75 : (e ? e[1] : .8)) * .55, a[0] === 'C' ? mol.c : (e ? e[0] : [1, 1, 1]))); });
  for (const b of mol.bonds) { const s = stick(P[b[0]], P[b[1]], b[2] === 2 ? .13 : .09, [.95, .95, 1]); if (s) parts.push(s); } return merge(parts);
}
const BUFF_COLS = { boost: [1, .55, .1], shield: [.3, .85, 1], mult: [.95, .4, 1], donut: [1, .45, .7] }, BUFF_KIT = { boost: 'crystal', shield: 'cage', mult: 'rings', donut: 'tetra' };

export function createSpawn(o) {
  const { scene, MOLS, MOL_ORDER, th, railY, BUFFS, PADS, RAILS, PILLS, addObs, vegSrc, onTarget, trailX } = o;
  const live = []; let ORBS = []; const matCache = {};
  const kitMat = (name, emi) => matCache[name] || (matCache[name] = (() => { const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .3, metalness: .15, emissive: new THREE.Color(emi, emi, emi * 1.1) }); m.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_begin>', '{ float rim = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.5); totalEmissiveRadiance += mix(vec3(1.), diffuseColor.rgb, .35) * rim * .8; }' + String.fromCharCode(10) + '#include <lights_fragment_begin>'); }; return m; })());
  function clear() { for (const m of live) { scene.remove(m); if (m.geometry && !m.userData.shared) m.geometry.dispose(); } live.length = 0; ORBS = []; for (const arr of [BUFFS, PADS, RAILS, PILLS]) for (let i = arr.length - 1; i >= 0; i--) if (arr[i].mine) arr.splice(i, 1); }
  function build(seed, zEnd, halfW, lap) {
    clear(); const R = mulberry(seed * 7919 + lap * 104729), rr = (a, b) => a + (b - a) * R(), pick = (arr) => arr[Math.floor(R() * arr.length)];
    const buffsBy = { boost: [], shield: [], mult: [], donut: [] }, pads = [], mols = [], orbs = [], trees = [], rails = [];
    const X = (x) => Math.max(-halfW, Math.min(halfW, x)), gy = (x, z) => th(x, z);
    const addBuff = (x, z, t) => { x = X(x); const y = gy(x, z) + 1.9, b = { mine: true, x, z, y, t, kind: 'path', taken: false, orbs: [], ph: R() * 6.28, base: y }; buffsBy[t].push(b); BUFFS.push(b); return b; };
    const addPad = (x, z) => { x = X(x); const p = { mine: true, x, z, used: false, epic: R() < .2, ph: R() * 6.28 }; pads.push(p); PADS.push(p); return p; };
    const addOrbs = (x0, z0, x1, z1, step) => { const n = Math.max(2, Math.floor(Math.hypot(x1 - x0, z1 - z0) / step)); for (let i = 1; i < n; i++) { const t = i / n, x = X(x0 + (x1 - x0) * t), z = z0 + (z1 - z0) * t; orbs.push({ x, z, y: gy(x, z) + 1.5, taken: false, ph: i * .9 }); } };
    const weighted = () => { const r = R(); return r < .36 ? 'boost' : r < .5 ? 'shield' : r < .72 ? 'mult' : 'donut'; };
    let z = -150, molIdx = Math.floor(R() * 6), nextMol = -330, side = R() < .5 ? 1 : -1;
    while (z > zEnd) {
      const cx = trailX(z), kind = R();
      if (z < nextMol) {          // a molecule, far to one side, with a trail of orbs that leads there from the middle of the course
        const id = MOL_ORDER[molIdx++ % 6], mx = side * rr(55, halfW - 12), mz = z - 20; side = -side; nextMol -= rr(170, 230);
        const m = { mine: true, x: X(mx), z: mz, id, name: MOLS[id].name, t: 0, taken: false, ph: R() * 6.28 }; mols.push(m); PILLS.push(m); addOrbs(cx, mz + 120, m.x, mz + 4, 6.5); addPad(m.x * .6, mz + 40);
        for (let i = 0; i < 3; i++) addBuff(m.x + rr(-9, 9), mz + 14 + i * 7, weighted());
        z -= 70;
      } else if (kind < .3) {          // a sweep: a diagonal line of pickups that carries you a long way sideways
        const x0 = rr(-halfW + 15, halfW - 15), dir = R() < .5 ? -1 : 1, len = rr(55, 95), n = Math.floor(rr(5, 9)), x1 = X(x0 + dir * rr(50, 110));
        for (let i = 0; i < n; i++) { const t = i / (n - 1); addBuff(x0 + (x1 - x0) * t, z - t * len, weighted()); }
        z -= len + 15;
      } else if (kind < .5) {          // a cluster: a handful of pickups together, one of each kind if you can take them all
        const x0 = rr(-halfW + 12, halfW - 12), n = Math.floor(rr(3, 6)); for (let i = 0; i < n; i++) addBuff(x0 + rr(-7, 7), z - rr(0, 16), i < 4 ? Object.keys(buffsBy)[i] : weighted());
        if (R() < .6) addOrbs(x0 - 20, z + 25, x0, z, 5);
        z -= 36;
      } else if (kind < .64) {          // boost pads, then something to catch with the speed
        const x0 = rr(-halfW + 10, halfW - 10); addPad(x0, z); if (R() < .6) addPad(x0 + rr(-10, 10), z - 28); addBuff(x0 + rr(-14, 14), z - 55, 'boost'); addBuff(X(x0 + rr(-60, 60)), z - 90, weighted());
        z -= 62;
      } else if (kind < .82) {          // a rail, with a line of orbs to lead you to it
        const x0 = rr(-halfW + 20, halfW - 20), f = { mine: true, kind: 'rail', kx: x0, sd: 0, za: z, zb: z - rr(26, 46), done: false }; rails.push(f); RAILS.push(f); addOrbs(x0 + rr(-40, 40), z + 70, x0, z + 8, 7);
        z -= 70;
      } else {          // trees to avoid in the open middle
        const n = Math.floor(rr(6, 15)), x0 = rr(-halfW + 20, halfW - 20); for (let i = 0; i < n; i++) trees.push({ x: X(x0 + rr(-26, 26)), z: z - rr(0, 44), s: rr(.9, 1.6) });
        addBuff(X(x0 + rr(-40, 40)), z - 52, weighted()); z -= 56;
      }
      z -= rr(2, 9);
    }
    // ---- instanced meshes
    const add = (mesh, shared) => { mesh.frustumCulled = false; mesh.userData.shared = shared; scene.add(mesh); live.push(mesh); return mesh; };
    for (const t of Object.keys(buffsBy)) { const list = buffsBy[t]; if (!list.length) continue; const im = add(new THREE.InstancedMesh(kitGeo(BUFF_KIT[t], BUFF_COLS[t]), kitMat('kit', .22), list.length)); list.forEach((b, i) => { b.inst = im; b.idx = i; b.sc = 1.35; b.spin = t === 'boost' ? 2.8 : 1.7; b.hideSelf = () => { b.hidden = true; _m.makeScale(0, 0, 0); im.setMatrixAt(b.idx, _m); im.instanceMatrix.needsUpdate = true; }; onTarget(b, t); }); }
    if (pads.length) { const parts = []; for (let i = 0; i < 3; i++) for (const sx of [-1, 1]) parts.push({ g: boxG, m: new THREE.Matrix4().compose(new THREE.Vector3(sx * 1.4, .22, -i * 2.4), new THREE.Quaternion().setFromAxisAngle(_up, -sx * .55), new THREE.Vector3(3.4, .16, .7)), c: [1, .6, .15] }); const im = add(new THREE.InstancedMesh(merge(parts), new THREE.MeshBasicMaterial({ vertexColors: true }), pads.length)); pads.forEach((p, i) => { p.inst = im; p.idx = i; const y = gy(p.x, p.z - 2.2), pit = Math.atan2(gy(p.x, p.z - 4) - gy(p.x, p.z), 4); _q.setFromAxisAngle(new THREE.Vector3(1, 0, 0), pit); _m.compose(_v.set(p.x, y, p.z - 2.2), _q, _s.set(1, 1, 1)); im.setMatrixAt(i, _m); p.hideSelf = () => { _m.makeScale(0, 0, 0); im.setMatrixAt(i, _m); im.instanceMatrix.needsUpdate = true; }; onTarget(p, 'pad'); }); im.instanceMatrix.needsUpdate = true; }
    for (const f of rails) {          // a rail: a chain of atoms with a bar between them, following the snow (RunRig._build_rail)
      const parts = [], pts = []; for (let zz = f.za; zz >= f.zb - .01; zz -= 2.2) pts.push([f.kx, railY(f, zz), zz]); pts.forEach((p, i) => { parts.push(ball(p, i === 0 || i === pts.length - 1 ? .5 : .3, [.4, 1, .95])); if (i) { const s = stick(pts[i - 1], p, .09, [.9, 1, 1]); if (s) parts.push(s); } });
      add(new THREE.Mesh(merge(parts), kitMat('kit', .3))); onTarget(f, 'rail');
    }
    if (mols.length) { for (const id of MOL_ORDER) { const list = mols.filter((m) => m.id === id); if (!list.length) continue; const im = add(new THREE.InstancedMesh(molGeo(MOLS[id]), kitMat('mol', .28), list.length)); list.forEach((m, i) => { m.inst = im; m.idx = i; m.y = gy(m.x, m.z) + 4.2; m.sc = 1.9; m.spin = .9; m.hideSelf = () => { m.hidden = true; _m.makeScale(0, 0, 0); im.setMatrixAt(i, _m); im.instanceMatrix.needsUpdate = true; }; onTarget(m, 'mol'); }); } }
    if (orbs.length) { const im = add(new THREE.InstancedMesh(sphereG, new THREE.MeshBasicMaterial({ color: new THREE.Color(1, .9, .45) }), orbs.length)); ORBS = orbs; orbs.forEach((b, i) => { b.idx = i; b.inst = im; _m.compose(_v.set(b.x, b.y, b.z), _q.identity(), _s.set(.55, .55, .55)); im.setMatrixAt(i, _m); }); im.instanceMatrix.needsUpdate = true; ORBS.im = im; }
    if (trees.length && vegSrc) { const im = add(new THREE.InstancedMesh(vegSrc.g, vegSrc.mat, trees.length), true); trees.forEach((t, i) => { const y = gy(t.x, t.z); _q.setFromAxisAngle(_up, R() * 6.28); _m.compose(_v.set(t.x, y, t.z), _q, _s.set(t.s, t.s, t.s)); im.setMatrixAt(i, _m); addObs(t.x, t.z, 1.5 * t.s); }); im.instanceMatrix.needsUpdate = true; }
    return { buffs: Object.values(buffsBy).reduce((a, l) => a + l.length, 0), pads: pads.length, rails: rails.length, mols: mols.length, orbs: orbs.length, trees: trees.length };
  }
  // per frame: spin and bob the pickups and molecules near the player (the rest stay where they were built), and pulse the orbs
  function tick(age, pz) {
    for (const mesh of live) { if (!mesh.isInstancedMesh || !mesh.userData.anim) continue; }
    const upd = (arr) => { const im = arr.length ? arr[0].inst : null; if (!im) return; for (const b of arr) { if (b.hidden || b.taken) continue; if (Math.abs(b.z - pz) > 320) continue; _q.setFromAxisAngle(_up, age * (b.spin || 1.7) + b.ph); _m.compose(_v.set(b.x, (b.y !== undefined ? b.y : 0) + Math.sin(age * 2.4 + b.ph) * .35, b.z), _q, _s.set(b.sc, b.sc, b.sc)); b.inst.setMatrixAt(b.idx, _m); } for (const m of new Set(arr.map((b) => b.inst))) m.instanceMatrix.needsUpdate = true; };
    upd(BUFFS.filter((b) => b.mine)); upd(PILLS.filter((b) => b.mine));
  }
  function collectOrbs(PH, above) { let n = 0; for (const b of ORBS) { if (b.taken || Math.abs(b.z - PH.z) > 3) continue; if (Math.abs(b.x - PH.x) < 3 && above < 5) { b.taken = true; _m.makeScale(0, 0, 0); ORBS.im.setMatrixAt(b.idx, _m); ORBS.im.instanceMatrix.needsUpdate = true; n++; } } return n; }
  return { build, tick, collectOrbs, clear };
}
