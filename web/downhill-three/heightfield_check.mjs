// node heightfield_check.mjs : compares heightfield.js with the THREE.Raycaster the game used (same ground meshes, same ray), and times both.
import * as THREE from '../stargaze/vendor/three/three.module.min.js';
import { createHeightfield } from './heightfield.js';
import fs from 'fs';

const dir = new URL('./data/long_s7/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const meta = JSON.parse(fs.readFileSync(dir + 'meta.json', 'utf8'));
const FIRST = parseInt(process.argv[2] || '3', 10), COUNT = parseInt(process.argv[3] || '8', 10);
const ground = [], HF = createHeightfield(); let bad = 0;
for (let j = FIRST; j < FIRST + COUNT; j++) {
  const r = JSON.parse(fs.readFileSync(dir + 'row_' + String(j).padStart(2, '0') + '.json', 'utf8')), meshes = Object.assign({}, meta.meshes, r.meshes);
  for (const n of r.nodes) {
    if (n.class !== 'MeshInstance3D' || !n.mesh) continue;
    for (const s of meshes[n.mesh].surfaces) {
      const mid = n.mat_override || s.mat, code = (meta.materials[String(mid)] || {}).shader_code || ''; if (!code.includes('MOIRE') || !s.v) continue;
      const pos = new Float32Array(s.v.length * 3); s.v.forEach((p, i) => { pos[i * 3] = p[0]; pos[i * 3 + 1] = p[1]; pos[i * 3 + 2] = p[2]; });
      const idx = Uint32Array.from(s.i); const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setIndex(new THREE.BufferAttribute(idx, 1));
      const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ side: THREE.DoubleSide })); m.matrixAutoUpdate = false; m.matrixWorld.identity(); ground.push(m);
      if (!HF.addMesh('row' + j, pos, idx)) { bad++; console.log('row', j, 'is not a regular grid'); }
    }
  }
}
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0), origin = new THREE.Vector3();
const rayY = (x, z) => { origin.set(x, 3000, z); ray.set(origin, down); const h = ray.intersectObjects(ground, false); return h.length ? h[0].point.y : null; };
const z0 = -180 * (FIRST + COUNT) + 1, z1 = -180 * FIRST - 1; let seed = 12345; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const N = 4000; const pts = []; for (let i = 0; i < N; i++) pts.push([-148 + rnd() * 296, z0 + rnd() * (z1 - z0)]);
// the places most likely to disagree: the seams between chunks and the grid lines
for (let j = FIRST + 1; j < FIRST + COUNT; j++) for (const x of [-100, -5, 0, 7.5, 33]) pts.push([x, -180 * j], [x, -180 * j + 0.01], [x, -180 * j - 0.01]);
let maxD = 0, sumD = 0, nullMis = 0; const worst = [];
for (const [x, z] of pts) { const a = rayY(x, z), b = HF.height(x, z); if ((a === null) !== (b === null)) { nullMis++; continue; } if (a === null) continue; const d = Math.abs(a - b); sumD += d; if (d > maxD) { maxD = d; worst.push([x, z, a, b]); } }
let t0 = process.hrtime.bigint(); let sink = 0; for (let k = 0; k < 3; k++) for (const [x, z] of pts) sink += rayY(x, z) || 0; const tRay = Number(process.hrtime.bigint() - t0) / 1e6 / (3 * pts.length);
t0 = process.hrtime.bigint(); for (let k = 0; k < 30; k++) for (const [x, z] of pts) sink += HF.height(x, z) || 0; const tHF = Number(process.hrtime.bigint() - t0) / 1e6 / (30 * pts.length);
console.log('rows', FIRST + '..' + (FIRST + COUNT - 1), 'ground meshes', ground.length, 'not-grid', bad, 'points', pts.length);
console.log('max |raycast - heightfield| =', maxD.toExponential(2), 'm   mean =', (sumD / pts.length).toExponential(2), 'm   null mismatches', nullMis);
console.log('raycast   :', (tRay * 1000).toFixed(1), 'us per call  ->', (tRay * 10).toFixed(2), 'ms per frame at 10 calls');
console.log('heightfield:', (tHF * 1000).toFixed(2), 'us per call  ->', (tHF * 10).toFixed(4), 'ms per frame at 10 calls   (speed-up x' + (tRay / tHF).toFixed(0) + ')');
if (maxD > 0.01 || nullMis) { console.log('FAIL, worst:', worst.slice(-3)); process.exit(1); } else console.log('OK');
