// node tools/build_bank.mjs : splits the four 63-row dumps into one small file per row (data/bank/long_s11_07.json ...) plus data/bank/shared.json.
import fs from 'node:fs'; import { bankRecord } from '../downhill-three/trip_compose.mjs';
const D = new URL('../downhill-three/data/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'); fs.mkdirSync(D + 'bank', { recursive: true });
const rd = (p) => JSON.parse(fs.readFileSync(D + p)); const materials = {}, meshes = {}; let shared = null, total = 0;
for (const d of ['long_s7b', 'long_s11', 'long_s23', 'long_s42']) {
  const m = rd(d + '/meta.json'), ph = rd(d + '/physics.json'); Object.assign(materials, m.materials); Object.assign(meshes, m.meshes);
  if (!shared) { shared = Object.assign({}, m); for (const k of ['materials', 'meshes', 'pitch', 'trailx', 'nrows', 'segs']) delete shared[k]; }
  for (let j = 0; j < m.nrows; j++) { const rec = bankRecord(m, ph, rd(d + '/row_' + String(j).padStart(2, '0') + '.json'), j), nm = D + 'bank/' + d + '_' + String(j).padStart(2, '0'), t = JSON.stringify(rec.heavy); total += t.length; fs.writeFileSync(nm + '.json', t); fs.writeFileSync(nm + '.p.json', JSON.stringify(rec.light)); }
}
fs.writeFileSync(D + 'bank/shared.json', JSON.stringify({ meta: shared, materials, meshes }));
console.log('bank: 252 rows, ' + (total / 1e6).toFixed(0) + ' MB; shared ' + (fs.statSync(D + 'bank/shared.json').size / 1e6).toFixed(1) + ' MB');
