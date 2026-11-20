// SPAWN: the content of the wide level, generated in the browser and laid across the whole width of the open snow (the Godot dump gives the terrain, the forest at the edges and the few ramps; everything the player goes after is made here).
// Pickups (the four kit shapes from RunRig._kit_mesh), boost pads (the chevron bars), rails (a chain of atoms, RunRig._build_rail), the six molecules as real ball-and-stick, glowing orb trails that lead sideways to far targets, and lone trees to avoid.
// Everything is instanced / merged so a phone draws a few dozen things, and every target is a plain record pushed into the same arrays the physics already reads (BUFFS, PADS, RAILS, PILLS), so collecting, chains, beacons and the goal icon all work on it unchanged.
import * as THREE from 'three';
import { createPickupMesh } from './pickupmesh.js';
import { buildMolGeometry, moleculeMaterial, PILL } from './molmesh.js';
const PM = createPickupMesh(THREE); const _xax = new THREE.Vector3(1, 0, 0), qA = new THREE.Quaternion(), qB = new THREE.Quaternion(), qC = new THREE.Quaternion();

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
  const live = []; let ORBS = []; const matCache = {}; const ANIM = []; const _eu = new THREE.Euler();
  const kitMat = (name, emi) => matCache[name] || (matCache[name] = (() => { const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .3, metalness: .15, emissive: new THREE.Color(emi, emi, emi * 1.1) }); m.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_begin>', String.fromCharCode(10) + '{ float rim = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.5); totalEmissiveRadiance += mix(vec3(1.), diffuseColor.rgb, .35) * rim * .8; }' + String.fromCharCode(10) + '#include <lights_fragment_begin>'); }; return m; })());
  function clear() { for (const m of live) { scene.remove(m); if (m.geometry && !m.userData.shared) m.geometry.dispose(); } live.length = 0; ORBS = []; ANIM.length = 0; for (const arr of [BUFFS, PADS, RAILS, PILLS]) for (let i = arr.length - 1; i >= 0; i--) if (arr[i].mine) arr.splice(i, 1); }
  function build(seed, zEnd, halfW, lap) {
    clear(); const R = mulberry(seed * 7919 + lap * 104729), rr = (a, b) => a + (b - a) * R(), pick = (arr) => arr[Math.floor(R() * arr.length)];
    const buffsBy = { boost: [], shield: [], mult: [], donut: [] }, pads = [], mols = [], orbs = [], trees = [], rails = [];
    const X = (x) => Math.max(-halfW, Math.min(halfW, x)), gy = (x, z) => th(x, z);
    const addBuff = (x, z, t) => { x = X(x); const y = gy(x, z) + 2.4, b = { mine: true, x, z, y, t, kind: 'path', taken: false, orbs: [], ph: R() * 6.28, base: y }; buffsBy[t].push(b); BUFFS.push(b); return b; };
    const addPad = (x, z) => { x = X(x); const p = { mine: true, x, z, used: false, epic: R() < .2, ph: R() * 6.28 }; pads.push(p); PADS.push(p); return p; };
    const addOrbs = (x0, z0, x1, z1, step) => { const n = Math.max(2, Math.floor(Math.hypot(x1 - x0, z1 - z0) / step)); for (let i = 1; i < n; i++) { const t = i / n, x = X(x0 + (x1 - x0) * t), z = z0 + (z1 - z0) * t; orbs.push({ x, z, y: gy(x, z) + 1.3, taken: false, pi: i }); } };
    const weighted = () => { const r = R(); return r < .36 ? 'boost' : r < .5 ? 'shield' : r < .72 ? 'mult' : 'donut'; };
    let z = -150, molIdx = Math.floor(R() * 6), nextMol = -330, side = R() < .5 ? 1 : -1;
    while (z > zEnd) {
      { const zj = Math.floor(-z / 180), zn = (typeof window !== 'undefined' && window.__zoneOf) ? window.__zoneOf(zj) : 'off'; if (zn === 'clear' || zn === 'slalom') { z = -(zj + 1) * 180 - 3; continue; } }          // clear and slalom stretches: nothing here (the game decides which rows)
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
        const x0 = rr(-halfW + 20, halfW - 20), mt = pick(['steel', 'steel', 'glass', 'wood', 'neon', 'rust']), RM = { steel: [[.35, .95, 1], 1], glass: [[.85, .95, 1], .85], wood: [[1, .62, .25], 1.5], neon: [[1, .3, .9], 1], rust: [[1, .5, .2], 1.2] }[mt], f = { mine: true, kind: 'rail', mat: mt, col: RM[0], kx: x0, sd: 0, za: z, zb: z - rr(26, 46) * RM[1], done: false };          // materials: each rail has a colour and a way of riding (see railStep in the game) rails.push(f); RAILS.push(f); addOrbs(x0 + rr(-40, 40), z + 70, x0, z + 8, 7);
        z -= 70;
      } else {          // trees to avoid in the open middle
        const n = Math.floor(rr(6, 15)), x0 = rr(-halfW + 20, halfW - 20); for (let i = 0; i < n; i++) trees.push({ x: X(x0 + rr(-26, 26)), z: z - rr(0, 44), s: rr(.9, 1.6) });
        addBuff(X(x0 + rr(-40, 40)), z - 52, weighted()); z -= 56;
      }
      z -= rr(2, 9) + (typeof window !== 'undefined' && window.__spawnGap ? rr(30, 90) * window.__spawnGap() : 0);          // spread out: more open ground between the things you go after (&spawngap, default 1.3)
    }
    // ---- instanced meshes, from Godot's own recipes (pickupmesh.js: RunRig._make_item / _make_pad / _build_rail / _spawn_orb; molmesh.js: the molecule mesh and pill)
    const add = (mesh, shared) => { mesh.frustumCulled = false; mesh.userData.shared = shared; scene.add(mesh); live.push(mesh); return mesh; };
    const zero = new THREE.Matrix4().makeScale(0, 0, 0), killAt = (ims, idx) => { for (const m of ims) { m.setMatrixAt(idx, zero); m.instanceMatrix.needsUpdate = true; } };
    for (const t of Object.keys(buffsBy)) {          // buffs: body (kit shape x1.3, spins), halo (billboard 6.2), pool (flat 7 at -1.6); the root bobs and the halo pulses (_animate_buffs)
      const list = buffsBy[t]; if (!list.length) continue; const spec = PM.buff(t), ims = [0, 1, 2].map((k) => add(new THREE.InstancedMesh(spec.parts[k].geo, spec.parts[k].mat, list.length), true)); ims[1].renderOrder = 4; ims[2].renderOrder = 3;
      list.forEach((b, i) => { b.im = ims; b.idx = i; b.hideSelf = () => { b.hidden = true; killAt(ims, i); };
        b.upd = (age) => { const a = spec.anim(age, b.ph), yy = b.y + a.bobY; ims[0].setMatrixAt(i, _m.compose(_v.set(b.x, yy, b.z), qA.setFromAxisAngle(_up, a.spinY), _s.set(1.3, 1.3, 1.3))); const hs = 6.2 * a.haloScale; ims[1].setMatrixAt(i, _m.compose(_v.set(b.x, yy, b.z), qB.identity(), _s.set(hs, hs, 1))); ims[2].setMatrixAt(i, _m.compose(_v.set(b.x, yy - 1.6, b.z), qC.setFromAxisAngle(_xax, -Math.PI / 2), _s.set(7, 7, 1))); };
        b.upd(0); onTarget(b, t); });
      ims.forEach((m) => { m.instanceMatrix.needsUpdate = true; ANIM.push(m); });
    }
    for (const epic of [false, true]) {          // pads: emissive chevron bars and a glow pool lying on the slope, a crystal hovering over them with a halo (_make_pad)
      const list = pads.filter((p) => !!p.epic === epic); if (!list.length) continue; const spec = PM.pad(epic), ims = spec.parts.map((pt) => add(new THREE.InstancedMesh(pt.geo, pt.mat, list.length), true)); ims[1].renderOrder = 3; ims[3].renderOrder = 4;
      list.forEach((p, i) => { const zz = p.z - 2.2, y = gy(p.x, zz), pit = -Math.atan((gy(p.x, zz + .6) - gy(p.x, zz - .6)) / 1.2); p.im = ims; p.idx = i;
        ims[0].setMatrixAt(i, _m.compose(_v.set(p.x, y, zz), qA.setFromAxisAngle(_xax, pit), _s.set(1, 1, 1))); ims[1].setMatrixAt(i, _m.compose(_v.set(p.x, y + .15, zz), qB.setFromAxisAngle(_xax, -Math.PI / 2 + pit), _s.set(8, 8, 1)));
        p.upd = (age) => { const gyy = y + 1.35 + .22 * Math.sin(age * 2.6 + p.ph); ims[2].setMatrixAt(i, _m.compose(_v.set(p.x, gyy, zz), qC.setFromAxisAngle(_up, age * 1.8 + p.ph), _s.set(1.25, 1.25, 1.25))); ims[3].setMatrixAt(i, _m.compose(_v.set(p.x, gyy, zz), qB.identity(), _s.set(3.6, 3.6, 1))); };
        p.hideSelf = () => { p.hidden = true; killAt(ims, i); }; p.upd(0); onTarget(p, 'pad'); });
      ims.forEach((m) => { m.instanceMatrix.needsUpdate = true; }); ims[2].userData.anim = ims[3].userData.anim = true; ANIM.push(ims[2], ims[3]);
    }
    for (const f of rails) {          // rails: long glowing boxes, posts, glossy atoms at the joints, a spiral of gold glints (RunRig._build_rail)
      const r = PM.rail(f, () => f.kx, (zz) => railY(f, zz), gy); add(new THREE.Mesh(r.boxes.geo, r.boxes.mat), false); add(new THREE.Mesh(r.posts.geo, r.posts.mat), false); add(new THREE.Mesh(r.balls.geo, r.balls.mat), false);
      if (r.glints.length) { const gi = add(new THREE.InstancedMesh(r.glint.geo, r.glint.mat, r.glints.length), true); r.glints.forEach((g, k) => gi.setMatrixAt(k, _m.compose(_v.set(g[0], g[1], g[2]), qA.identity(), _s.set(r.glint.scale, r.glint.scale, r.glint.scale)))); gi.instanceMatrix.needsUpdate = true; }
      onTarget(f, 'rail');
    }
    for (const id of MOL_ORDER) {          // molecules: the real ball-and-stick mesh, 1.6x, tilted and spinning at 2.4 rad/s, floating 2.2 m over the snow, with its soft halo (the pill in RunRig)
      const list = mols.filter((m) => m.id === id); if (!list.length) continue; const mc = MOLS[id].c, imM = add(new THREE.InstancedMesh(buildMolGeometry(THREE, id), moleculeMaterial(THREE), list.length), true), imH = add(new THREE.InstancedMesh(PM.quadGeo, PM.fxMaterial('halo', [mc[0], mc[1], mc[2], PILL.halo_alpha]), list.length), true); imH.renderOrder = 4;
      list.forEach((m, i) => { m.im = [imM, imH]; m.idx = i; m.gy = gy(m.x, m.z); m.y = m.gy + PILL.y_above_snow; m.hideSelf = () => { m.hidden = true; killAt(m.im, i); };
        m.upd = (age) => { const sp = age * PILL.spin_rate + m.ph, bob = PILL.bob_amp * Math.sin(age * PILL.bob_rate + m.x); const q = qA.setFromEuler(_eu.set(PILL.tilt[0], PILL.tilt[1], PILL.tilt[2], PILL.tilt_order)).premultiply(qB.setFromAxisAngle(_up, sp)); imM.setMatrixAt(i, _m.compose(_v.set(m.x, m.gy + PILL.y_above_snow + bob, m.z), q, _s.set(PILL.hold_scale, PILL.hold_scale, PILL.hold_scale))); const hs = PILL.halo_size * PILL.hold_scale; imH.setMatrixAt(i, _m.compose(_v.set(m.x, m.gy + PILL.y_above_snow + bob, m.z), qC.identity(), _s.set(hs, hs, 1))); };
        m.upd(0); onTarget(m, 'mol'); });
      imM.instanceMatrix.needsUpdate = imH.instanceMatrix.needsUpdate = true; ANIM.push(imM, imH);
    }
    if (orbs.length) { const spec = PM.orb(), im = add(new THREE.InstancedMesh(spec.geo, spec.mat, orbs.length), true); ORBS = orbs; ORBS.spec = spec; orbs.forEach((b, i) => { b.idx = i; b.inst = im; b.upd = (age) => { const k = spec.scale * spec.pulse(age, b.pi); im.setMatrixAt(i, _m.compose(_v.set(b.x, b.y, b.z), qA.identity(), _s.set(k, k, k))); }; b.upd(0); }); im.instanceMatrix.needsUpdate = true; ORBS.im = im; ANIM.push(im); }
    if (trees.length && vegSrc) { const im = add(new THREE.InstancedMesh(vegSrc.g, vegSrc.mat, trees.length), true); trees.forEach((t, i) => { const y = gy(t.x, t.z); _q.setFromAxisAngle(_up, R() * 6.28); _m.compose(_v.set(t.x, y, t.z), _q, _s.set(t.s, t.s, t.s)); im.setMatrixAt(i, _m); addObs(t.x, t.z, 1.5 * t.s); }); im.instanceMatrix.needsUpdate = true; }
    return { buffs: Object.values(buffsBy).reduce((a, l) => a + l.length, 0), pads: pads.length, rails: rails.length, mols: mols.length, orbs: orbs.length, trees: trees.length };
  }
  // per frame: bob, spin and pulse the pickups, pads, molecules and orbs near the player (_animate_buffs and friends); the rest stay where they were built
  function tick(age, pz) {
    for (const o of BUFFS) if (o.mine && o.upd && !o.hidden && !o.taken && Math.abs(o.z - pz) < 320) o.upd(age);
    for (const o of PADS) if (o.mine && o.upd && !o.hidden && !o.used && Math.abs(o.z - pz) < 320) o.upd(age);
    for (const o of PILLS) if (o.mine && o.upd && !o.hidden && !o.taken && Math.abs(o.z - pz) < 420) o.upd(age);
    for (const b of ORBS) if (!b.taken && Math.abs(b.z - pz) < 200) b.upd(age);
    for (const m of ANIM) m.instanceMatrix.needsUpdate = true;
  }
  function collectOrbs(PH, above) { let n = 0; for (const b of ORBS) { if (b.taken || Math.abs(b.z - PH.z) > 3) continue; if (Math.abs(b.x - PH.x) < 3 && above < 5) { b.taken = true; _m.makeScale(0, 0, 0); ORBS.im.setMatrixAt(b.idx, _m); ORBS.im.instanceMatrix.needsUpdate = true; n++; } } return n; }
  return { build, tick, collectOrbs, clear };
}
