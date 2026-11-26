// node tools/build_bank2.mjs [--check] [dump ...]
// THE ROAD BANK, rebuilt from every wide course dump (data/long_s*, 60+ rows; default: all of them):
//   data/bank/<dump>_<jj>.json / .p.json   one 180 m section each (heavy: nodes + meshes; light: physics, see trip_compose.mjs bankRecord)
//   data/bank/shared.json                  materials + meshes shared across sections (merged; a mesh id used by two dumps with different data is renamed)
//   data/row_catalog.json                  per section: drop, slope, counts of pickups / toys / kickers / rings / trees (what the director chooses by)
//   data/trip_edges.json                   per section: trail x at both ends and the ground's height across the road (x -150..150, every 5 m) at both ends,
//                                          so two sections can be checked for a clean join without loading them (trip_compose.mjs joinCost)
// --check rebuilds the edges of the old four dumps and compares them with the existing file (the method must agree before it is trusted).
import fs from 'node:fs';
import { bankRecord, ROW, SAMP } from '../downhill-three/trip_compose.mjs';
const D = new URL('../downhill-three/data/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const args = process.argv.slice(2), CHECK = args.includes('--check');
let dumps = args.filter((a) => !a.startsWith('--'));
if (!dumps.length) dumps = fs.readdirSync(D).filter((n) => /^long_s\d+b?$/.test(n) && fs.existsSync(D + n + '/meta.json')).filter((n) => JSON.parse(fs.readFileSync(D + n + '/meta.json')).nrows >= 60);
const rd = (p) => JSON.parse(fs.readFileSync(D + p));

// ground height at (x, z) from a row's ground chunk (the mesh with a world-baked grid: identity transform)
function groundOf(row, meta) {
  const tris = [];
  for (const n of row.nodes) { const def = n.mesh && ((row.meshes || {})[n.mesh] || meta.meshes[n.mesh]); if (!def || !def.surfaces) continue; const s = def.surfaces[0]; if (!s || !s.v || s.v.length < 1500 || !s.i) continue;
    const xf = n.xf || [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]; if (Math.abs(xf[0] - 1) > 1e-3 || Math.abs(xf[4] - 1) > 1e-3) continue;
    const V = s.v.map((p) => [p[0] + xf[9], p[1] + xf[10], p[2] + xf[11]]); for (let i = 0; i + 2 < s.i.length; i += 3) tris.push([V[s.i[i]], V[s.i[i + 1]], V[s.i[i + 2]]]); }
  return (x, z) => { for (const [a, b, c] of tris) { const d = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2]); if (Math.abs(d) < 1e-9) continue; const l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / d, l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / d, l3 = 1 - l1 - l2;
    if (l1 >= -1e-4 && l2 >= -1e-4 && l3 >= -1e-4) return +(l1 * a[1] + l2 * b[1] + l3 * c[1]).toFixed(3); } return null; };
}
const prof = (G, z) => { const o = []; for (let k = 0; k <= 60; k++) { const x = -150 + k * 5; let y = G(x, z); if (y == null) y = G(x, z + (z % ROW === 0 ? -.5 : .5)); o.push(y); } return o; };

const OLDE = fs.existsSync(D + 'trip_edges.json') ? rd('trip_edges.json') : {}, EDGES = CHECK ? {} : Object.assign({}, OLDE);
const OLDC = fs.existsSync(D + 'row_catalog.json') ? rd('row_catalog.json') : [];
const shared = fs.existsSync(D + 'bank/shared.json') && !CHECK ? rd('bank/shared.json') : null, materials = shared ? shared.materials : {}, meshes = shared ? shared.meshes : {}; let sharedMeta = shared ? shared.meta : null;
const catalog = OLDC.filter((c) => !dumps.includes('long_' + c.d)); let renamed = 0, total = 0;
fs.mkdirSync(D + 'bank', { recursive: true });
for (const d of dumps) {
  const m = rd(d + '/meta.json'), ph = rd(d + '/physics.json'), tag = d.replace(/^long_/, '');
  // merge materials and meshes; an id clash with different data gets this dump's suffix (and every reference in this dump follows)
  const ren = {}; for (const [id, def] of Object.entries(m.meshes)) { const js = JSON.stringify(def); if (meshes[id] && JSON.stringify(meshes[id]) !== js) { ren[id] = id + '~' + tag; meshes[ren[id]] = def; renamed++; } else meshes[id] = def; }
  Object.assign(materials, m.materials);
  if (!sharedMeta) { sharedMeta = Object.assign({}, m); for (const k of ['materials', 'meshes', 'pitch', 'trailx', 'nrows', 'segs']) delete sharedMeta[k]; }
  EDGES[d] = {};
  for (let j = 0; j < m.nrows; j++) {
    const row = rd(d + '/row_' + String(j).padStart(2, '0') + '.json'); if (Object.keys(ren).length) for (const n of row.nodes) if (n.mesh && ren[n.mesh] && !(row.meshes || {})[n.mesh]) n.mesh = ren[n.mesh];
    if (!CHECK) { const rec = bankRecord(m, ph, row, j), nm = D + 'bank/' + d + '_' + String(j).padStart(2, '0'), t = JSON.stringify(rec.heavy); total += t.length; fs.writeFileSync(nm + '.json', t); fs.writeFileSync(nm + '.p.json', JSON.stringify(rec.light)); }
    const G = groundOf(row, m); EDGES[d][j] = { t0: m.trailx[SAMP * j], t1: m.trailx[SAMP * (j + 1)], a: prof(G, -ROW * j), b: prof(G, -ROW * (j + 1)) };
    const pr = ph.rows[String(j)] || {}, inRow = (z) => z <= -ROW * j && z > -ROW * (j + 1);
    if (!CHECK) catalog.push({ d: tag, j, drop: +(m.pitch[j + 1].h - m.pitch[j].h).toFixed(1), slope: m.pitch[j].s, buffs: (pr.buffs || []).length, pads: (pr.pads || []).length, toys: (pr.toys || []).length, rings: (pr.airrings || []).length,
      orbs: (pr.buffs || []).reduce((a, b) => a + ((b.orbs || []).length), 0), feats: (pr.feats || []).length, obs: Math.floor((pr.obs || []).length / 4), trees: (pr.trees || []).length, kick: (ph.kickers || []).filter((k) => inRow(k.z)).length, vx: (ph.vx || []).filter((k) => inRow(k.z)).length, tx: m.trailx[SAMP * j] });
  }
  console.log(d, m.nrows, 'rows');
}
if (CHECK) { let worst = 0, n = 0, miss = 0; for (const d of dumps) for (const j of Object.keys(EDGES[d])) { const A = EDGES[d][j], B = OLDE[d] && OLDE[d][j]; if (!B) { miss++; continue; } for (const k of ['a', 'b']) for (let i = 0; i < 61; i++) { if (A[k][i] == null || B[k][i] == null) continue; worst = Math.max(worst, Math.abs(A[k][i] - B[k][i])); n++; } worst = Math.max(worst, Math.abs(A.t0 - B.t0), Math.abs(A.t1 - B.t1)); }
  console.log('CHECK: compared', n, 'heights, worst difference', worst.toFixed(3), 'm; sections missing in the old file', miss); process.exit(0); }
fs.writeFileSync(D + 'bank/shared.json', JSON.stringify({ meta: sharedMeta, materials, meshes }));
fs.writeFileSync(D + 'trip_edges.json', JSON.stringify(EDGES)); fs.writeFileSync(D + 'row_catalog.json', JSON.stringify(catalog));
console.log('bank:', catalog.length, 'sections in all;', (total / 1e6).toFixed(0), 'MB written; mesh ids renamed', renamed, '; shared', (fs.statSync(D + 'bank/shared.json').size / 1e6).toFixed(1), 'MB');
