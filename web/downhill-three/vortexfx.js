// VORTEXFX: the jump vortex rings, the ramp kit and the flight visuals, ported from Godot's code (RunRig.gd) so they look and move the way they did there.
//
// WHAT GODOT DOES (source in godot/scripts/RunRig.gd):
//  * _make_vortex (7869-7908): each ramp gets a funnel of 5 TorusMesh rings (inner .88, outer 1.12, 28 x 8), radius 5.2 -> 2.5, from over the foot of the ramp to near the lip; colour lerps from the swirl colour toward (1,.95,.6) by f*.7;
//    the material is _fx_mat("solid", colour, 2.6) (3619-3644): UNSHADED, EMISSION on at energy 2.6, disable_fog = true, opaque. That is the "cartoon neon" look: the pixel is albedo + emission*2.6 (about 3.6x, well over 1.0, so the glow pass blooms it) and the fog never touches it,
//    so the rings can be seen from far up the slope ("so you can see the way in from far up the slope").
//  * _vortex_drive (7917-7950): every frame the rings are re-posed: basis = basis_at(Z) * Rz(_vx_spin * near_k * (1.2 + .5 * i) * (+1 / -1 alternating)) * Rx(PI/2) * scale(R, R, R * .7).
//    The scale is applied in the torus' own frame, so the .7 squashes the ring into an OVAL, and the Rz turns that oval about the line of sight: that is the wobble. near_k = 1 + 2.5 * smoothstep(90, 10, dz) (dz = board z - ramp z) so the rings spin up as you close in.
//    The non-trail ramps have 4 additive rings (2.2/2.7 shrinking by .45, alpha .8 - .12 i), spin (2.2 + .7 i) with the baked scale S. Animated only while -40 < dz < 260.
//  * Ramp kit (_make_feat, 997-1068): lip bar, two poles with a halo flag and a ball, edge strips, a beacon column, the arc of glints, and the AIR CHAIN: 3 (5 on a super ramp) additive torus rings (inner 3.2, outer 3.9) hung along the flight; flying through one is worth 120 * chain * groove,
//    lifts you a little (vy + 2, capped 7), speeds you (vel.y -= 2), boost 1.0 s, vx_active .5 (_air_rings_tick 3999-4026). All of these are meshes in the dump, so gv.js already draws them; what was missing is the MATERIAL (below) and the air-chain rule.
//  * _land_ring (7990-8004): a torus (inner 2, outer 2.5, 24 x 6) with _fx_mat("add", (.5,1,.8,.9)) laid on the snow where the flight will come down (tl = (vy + sqrt(vy^2 + 2 G K h)) / (G K), K = AIR_G_K 2.1), shown while airborne.
//  * Camera on the trail (10385-10397): cam_back 9.5, cam_h 6.2, cam_ahead 30, cam_road .8 (the plain chase camera is 8 / 4.6 / 16); fov punch capped at 3 + 9 * max(pull * .6, blast) and shake at .5 + 1.0 * blast, where pull is how far into the swirl you are and blast is 1 at the lip, falling 2.2/s.
//
// WHAT gv.js DID INSTEAD (the differences this module fixes):
//  1. the rings (and every other "solid" unshaded emissive piece: lip bar, poles, pad bars, rails, edge strips) became MeshBasicMaterial with the albedo only: no emission, so about 3.6x too dim, nothing over the bloom threshold; and the scene fog applied to them, so they faded into the purple haze from far away.
//  2. the air-ring chain was a plain prop: flying through it did nothing.
//  3. no landing ring.
//  4. the trail camera numbers (9.5 / 6.2 / 30) and the swirl's fov/shake caps were not used.
// The ring wobble itself (the Rz * Rx * scale matrix and near_k) was already right in gv.js ringsTick; it is repeated here so gv.js can drop its copy.
//
// USE (gv.js):  import { createVortexFx } from './vortexfx.js';
//   const VFX = createVortexFx({ THREE, scene, lvl, th, PH, SPK, REGN, MAT, rgb, toast, SFX, gain: (n) => { PH.score += n; }, onAirRing: (chain) => { chainHit(); }, onAirChainEnd: (chain) => { } });
//   VFX.fixMaterials();                         // once, after all the dump meshes are built (the unshaded emissive solids get Godot's brightness and lose the fog)
//   per frame in playStep (replace ringsTick()):  VFX.tick(dt, clock.t);
//   in the landing code: VFX.onLand();           in vortexStep: VFX.setPull(t) while locked on a swirl (t from the pull curve) and VFX.blast() at the lip.
//   camera: VFX.camera() gives { back, h, ahead, road, fovPunchCap, shakeCap }.

const sstepG = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };          // Godot's smoothstep, which accepts a > b (GLSL's does not)

// the pure formulas, exported so they can be tested against the GDScript
export const nearK = (dz) => 1 + 2.5 * sstepG(90, 10, dz);
export function ringPose(R, gi, spin, dz, THREE, out) {
  const near = nearK(dz), sg = gi % 2 === 0 ? 1 : -1, ang = spin * near * (1.2 + .5 * gi) * sg;
  const a = new THREE.Matrix4().makeRotationZ(ang), b = new THREE.Matrix4().makeRotationX(Math.PI * .5), s = new THREE.Matrix4().makeScale(R, R, R * .7);
  return (out || new THREE.Matrix4()).copy(a).multiply(b).multiply(s);
}
export function ringPoseSmall(S, gi, spin, THREE, out) {          // the 4-ring non-trail swirl: spin (2.2 + .7 i), the baked scale S
  const sg = gi % 2 === 0 ? 1 : -1, ang = spin * (2.2 + .7 * gi) * sg;
  const a = new THREE.Matrix4().makeRotationZ(ang), b = new THREE.Matrix4().makeRotationX(Math.PI * .5), s = new THREE.Matrix4().makeScale(S[0], S[1], S[2]);
  return (out || new THREE.Matrix4()).copy(a).multiply(b).multiply(s);
}
// where a flight comes down: tl = (vy + sqrt(vy^2 + 2 g h)) / g with g = G * AIR_G_K (in the viewer's own scaled units)
export const landTime = (vy, h, g) => (vy + Math.sqrt(Math.max(vy * vy + 2 * g * h, 0))) / g;

export function createVortexFx(o) {
  const { THREE, scene, lvl, th, PH, SPK, REGN } = o, nameOf = (s) => String(s).replace(/^<node |>$/g, '');
  const GV = 9.8 * SPK * 2.1;          // gravity in the air: AIR_G_K = 2.1 (10515), scaled with the speed factor like the physics in gv.js
  const byIid = {}; for (const n of lvl.nodes) byIid[n.iid] = n; const byName = {}; for (const n of lvl.nodes) byName[n.name] = n;
  const S = { spin: 0, pull: 0, blast: 0, airChain: 0, prev: null };

  // ---- 1. the materials: unshaded + emission = albedo + emission * energy, no fog (StandardMaterial3D unshaded: ALBEDO plus EMISSION)
  function fixMaterials() {
    const MAT = o.MAT, rgb = o.rgb; if (!MAT || !rgb) return 0; let n = 0;
    for (const id of Object.keys(MAT)) {
      const d = lvl.materials[id], m = MAT[id]; if (!d || !m || d.class !== 'StandardMaterial3D' || !d.unshaded || !m.isMeshBasicMaterial || m.userData.vfxFixed) continue; m.userData.vfxFixed = true;
      if (d.emission_on && !(d.transparency > 0)) { const e = rgb(d.emission), k = d.emission_energy || 1; m.color.r += e.r * k; m.color.g += e.g * k; m.color.b += e.b * k; n++; }
      if (d.nofog) m.fog = false; m.needsUpdate = true;
    }
    return n;
  }

  // ---- 2. the rings
  const RINGS = [], SMALL = [];
  function buildRings() { RINGS.length = 0; SMALL.length = 0; for (const v of (lvl.vx || [])) {
    const small = !v.trail;
    for (const r of v.rings) {
      const nd = byIid[r.iid]; if (!nd) continue; const ms = REGN[nd.name] || []; const e = nd.xf;
      for (const m of ms) { const rec = { m, v, r, p: [e[9], e[10], e[11]], gi: r.gi }; if (r.R !== undefined) RINGS.push(rec); else if (r.S) SMALL.push(rec); }
    }
  } }
  buildRings();
  const _m = new THREE.Matrix4();
  function tickRings(dt) {
    S.spin += dt;
    for (const q of RINGS) { const dz = PH.z - q.v.z; if (dz > 260 || dz < -40) continue; ringPose(q.r.R, q.gi, S.spin, dz, THREE, _m); q.m.matrix.copy(_m); const el = q.m.matrix.elements; el[12] = q.p[0]; el[13] = q.p[1]; el[14] = q.p[2]; }
    for (const q of SMALL) { const dz = PH.z - q.v.z; if (dz > 260 || dz < -40) continue; ringPoseSmall(q.r.S, q.gi, S.spin, THREE, _m); q.m.matrix.copy(_m); const el = q.m.matrix.elements; el[12] = q.p[0]; el[13] = q.p[1]; el[14] = q.p[2]; }
  }

  // ---- 3. the air chain
  const AIR = []; for (const r of Object.values(lvl.rows)) for (const e of (r.airrings || [])) { const nd = byName[nameOf(e.n)]; AIR.push({ p: e.p, got: false, meshes: nd ? (REGN[nd.name] || []) : [] }); }
  function tickAir(dt) {
    const cur = [PH.x, PH.y + .9, PH.z]; const prev = S.prev || cur; S.prev = cur;
    if (PH.grounded) { if (S.airChain > 0) { const c = S.airChain; S.airChain = 0; o.onAirChainEnd && o.onAirChainEnd(c); } return; }
    for (const e of AIR) {
      if (e.got || Math.abs(e.p[2] - PH.z) > 5 + Math.abs(PH.vz) * dt) continue;
      // closest approach of the board's path this frame to the ring centre (the speeds here are higher than Godot's, so the path is swept)
      const dx = cur[0] - prev[0], dy = cur[1] - prev[1], dz = cur[2] - prev[2], L2 = dx * dx + dy * dy + dz * dz; let t = L2 > 1e-6 ? ((e.p[0] - prev[0]) * dx + (e.p[1] - prev[1]) * dy + (e.p[2] - prev[2]) * dz) / L2 : 1; t = Math.max(0, Math.min(1, t));
      const qx = prev[0] + dx * t - e.p[0], qy = prev[1] + dy * t - e.p[1], qz = prev[2] + dz * t - e.p[2];
      if (Math.hypot(qx, qy, qz) < 4.6) {
        e.got = true; S.airChain++; for (const m of e.meshes) m.visible = false;
        PH.vy = Math.min(PH.vy + 2 * SPK, 7 * SPK); PH.vz -= 2 * SPK; PH.boost_t = Math.max(PH.boost_t || 0, 1); PH.vxa = Math.max(PH.vxa || 0, .5);          // a lift, a push, a boost (4012-4020)
        o.gain && o.gain(Math.round(120 * S.airChain * (o.groove ? o.groove() : 1)));
        if (o.SFX && o.SFX.zap) o.SFX.zap();
        o.toast && o.toast('AIR CHAIN x' + S.airChain, S.airChain < 3 ? '#6fe' : '#fd4');
        o.onAirRing && o.onAirRing(S.airChain);
      }
    }
  }

  // ---- 4. the landing ring (an additive torus on the snow where the flight comes down)
  const landMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(.5, 1, .8), transparent: true, opacity: .9, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, depthWrite: false, fog: false });
  const landGeo = new THREE.TorusGeometry(2.25, .25, 6, 24); landGeo.rotateX(Math.PI / 2);
  const land = new THREE.Mesh(landGeo, landMat); land.visible = false; land.frustumCulled = false; scene.add(land);
  function tickLand(time) {
    if (PH.grounded || PH.air_t < .25) { land.visible = false; return; }
    const h = Math.max(PH.y - th(PH.x, PH.z), 0), tl = landTime(PH.vy, h, GV), lz = PH.z + PH.vz * tl, lx = PH.x + PH.vx * tl;
    land.position.set(lx, th(lx, lz) + .25, lz); const pul = 1 + .08 * Math.sin(time * 9); land.scale.set(pul, 1, pul); land.visible = true;
  }

  function tick(dt, time) { tickRings(dt); tickAir(dt); if (o.landingRing !== false) tickLand(time || 0); S.pull = Math.max(S.pull - 2 * dt, 0); S.blast = Math.max(S.blast - 2.2 * dt, 0); }
  // swirl state for the camera (7967, 8009-8010)
  const setPull = (t) => { S.pull = Math.max(S.pull, sstepG(0, .8, t)); };
  const blast = () => { S.blast = 1; };
  const camera = () => { const vxk = Math.max(S.pull * .6, S.blast); return { back: 9.5, h: 6.2, ahead: 30, road: .8, fovPunchCap: 3 + 9 * vxk, shakeCap: .5 + 1.0 * S.blast, vxk }; };
  const onLand = () => { if (S.airChain > 0) { const c = S.airChain; S.airChain = 0; o.onAirChainEnd && o.onAirChainEnd(c); } for (const e of AIR) if (e.got && Math.abs(e.p[2] - PH.z) > 60) { /* kept hidden */ } };
  const reset = () => { for (const e of AIR) { e.got = false; for (const m of e.meshes) m.visible = true; } S.airChain = 0; S.prev = null; S.pull = 0; S.blast = 0; };          // a new lap: the air rings come back
  return { refresh: () => { buildRings(); fixMaterials(); }, tick, fixMaterials, setPull, blast, camera, onLand, reset, state: S, rings: RINGS, small: SMALL, air: AIR };
}
