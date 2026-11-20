// headless check of vortexfx.js against the GDScript formulas (RunRig.gd 7944-7946, 3999-4026, 7990-8001)
import * as THREE from '../stargaze/vendor/three/three.module.min.js';
import { nearK, ringPose, ringPoseSmall, landTime, createVortexFx } from './vortexfx.js';
let bad = 0; const eq = (name, a, b, tol = 1e-6) => { const ok = Math.abs(a - b) <= tol; if (!ok) { bad++; console.log('FAIL', name, a, b); } else console.log('ok  ', name); };
// GDScript smoothstep(90.0, 10.0, dz): t = clamp((x - from)/(to - from)), t*t*(3-2t)
const gd = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
for (const dz of [-30, 0, 10, 30, 50, 70, 90, 150, 260]) eq('near_k dz=' + dz, nearK(dz), 1 + 2.5 * gd(90, 10, dz));
// the trail ring basis: Basis(Z, spin*near*(1.2+.5gi)*sg) * Basis(X, PI/2) * from_scale(R, R, R*.7)
for (const [R, gi, spin, dz] of [[5.2, 0, 1.0, 50], [4.525, 1, 2.7, 20], [2.5, 4, 9.1, 80]]) {
  const m = ringPose(R, gi, spin, dz, THREE), ang = spin * (1 + 2.5 * gd(90, 10, dz)) * (1.2 + .5 * gi) * (gi % 2 === 0 ? 1 : -1), c = Math.cos(ang), s = Math.sin(ang);
  // Rz * Rx(90) = [[c, -s*0, s*... ]] built by hand: Rx(90) = [[1,0,0],[0,0,-1],[0,1,0]]; Rz = [[c,-s,0],[s,c,0],[0,0,1]]
  const Rz = [[c, -s, 0], [s, c, 0], [0, 0, 1]], Rx = [[1, 0, 0], [0, 0, -1], [0, 1, 0]], Sx = [R, R, R * .7];
  const mul = (A, B) => A.map((r) => [0, 1, 2].map((j) => r[0] * B[0][j] + r[1] * B[1][j] + r[2] * B[2][j])); const M = mul(mul(Rz, Rx), [[Sx[0], 0, 0], [0, Sx[1], 0], [0, 0, Sx[2]]]);
  const e = m.elements; for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) eq('ringPose R=' + R + ' gi=' + gi + ' [' + i + '][' + j + ']', e[j * 4 + i], M[i][j], 1e-5);
}
// the small swirl: spin (2.2 + .7 i)
{ const m = ringPoseSmall([1.55, 1.55, 1], 2, 3.0, THREE), ang = 3.0 * (2.2 + .7 * 2) * 1; const e = m.elements; eq('small ring scale-x length', Math.hypot(e[0], e[1], e[2]), 1.55, 1e-5); eq('small ring spin', Math.atan2(e[1], e[0]), ((ang + Math.PI) % (2 * Math.PI)) - Math.PI, 1e-4); }
// the landing time
eq('landTime', landTime(10, 5, 20), (10 + Math.sqrt(100 + 200)) / 20);
// the air chain: a stub level with one ring, a board that flies through it
{
  const meshes = [{ visible: true }]; const lvl = { nodes: [{ iid: 'n1', name: 'R1', xf: new Array(12).fill(0) }], rows: { 0: { airrings: [{ n: '<node R1>', p: [15, -40, -400] }] } }, materials: {}, vx: [] };
  const PH = { x: 15, y: -41, z: -392, vx: 0, vy: 3, vz: -60, grounded: false, air_t: 1, boost_t: 0, vxa: 0 }; let scored = 0, chain = 0, toast = '';
  const fx = createVortexFx({ THREE, scene: new THREE.Scene(), lvl, th: () => -60, PH, SPK: 1, REGN: { R1: meshes }, gain: (n) => { scored += n; }, onAirRing: (c) => { chain = c; }, toast: (t) => { toast = t; }, landingRing: false });
  for (let i = 0; i < 40; i++) { PH.z += PH.vz / 60; fx.tick(1 / 60, i / 60); }
  eq('air ring picked', chain, 1); eq('air ring points 120*1', scored, 120); eq('ring hidden', meshes[0].visible ? 1 : 0, 0); eq('vy lift (min(3+2,7))', PH.vy, 5); eq('boost 1.0', PH.boost_t, 1); eq('forward push', PH.vz < -60 ? 1 : 0, 1);
  PH.grounded = true; fx.tick(1 / 60, 1); eq('chain reset on landing', fx.state.airChain, 0); fx.reset(); eq('ring back after reset', meshes[0].visible ? 1 : 0, 1);
}
console.log(bad ? bad + ' FAILED' : 'all passed'); process.exit(bad ? 1 : 0);
