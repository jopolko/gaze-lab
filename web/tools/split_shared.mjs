// node tools/split_shared.mjs : after build_bank2.mjs, splits data/bank/shared.json so a level only downloads what its road uses.
//   bank/shared.json           meta + materials + the meshes more than one course uses (or that the meta / physics nodes name)
//   bank/shared_<dump>.json    { meshes } used by that course's sections only
// The game fetches shared.json plus shared_<dump>.json for each course in its road plan, and merges the meshes.
import fs from 'node:fs';
const D = new URL('../downhill-three/data/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1') + 'bank/';
const sh = JSON.parse(fs.readFileSync(D + 'shared.json')); if (sh.split) { for (const f of fs.readdirSync(D)) if (/^shared_long_.*\.json$/.test(f)) { Object.assign(sh.meshes, JSON.parse(fs.readFileSync(D + f)).meshes); fs.unlinkSync(D + f); } delete sh.split; }          /* (re-splitting: put the pieces back together first) */
const users = {}, keep = new Set();
for (const n of sh.meta.nodes || []) if (n.mesh) keep.add(n.mesh);
for (const f of fs.readdirSync(D)) { if (!/^long_.*_\d+\.(p\.)?json$/.test(f)) continue; const d = f.replace(/_\d+\.(p\.)?json$/, ''), h = JSON.parse(fs.readFileSync(D + f)), list = f.includes('.p.') ? (h.pnodes || []) : h.nodes;
  for (const n of list) if (n.mesh && sh.meshes[n.mesh] && !(h.meshes || {})[n.mesh]) { (users[n.mesh] = users[n.mesh] || new Set()).add(d); } }
const core = {}, per = {}; let dropped = 0;
for (const [id, m] of Object.entries(sh.meshes)) { const u = users[id]; if (keep.has(id) || (u && u.size > 1)) core[id] = m; else if (u && u.size === 1) { const d = [...u][0]; (per[d] = per[d] || {})[id] = m; } else dropped++; }
for (const [d, ms] of Object.entries(per)) fs.writeFileSync(D + 'shared_' + d + '.json', JSON.stringify({ meshes: ms }));
fs.writeFileSync(D + 'shared.json', JSON.stringify({ meta: sh.meta, materials: sh.materials, meshes: core, split: true }));
const mb = (f) => (fs.statSync(D + f).size / 1e6).toFixed(1);
console.log('core shared.json', mb('shared.json'), 'MB;', Object.keys(per).length, 'course files', Object.keys(per).map((d) => d.replace('long_', '') + ' ' + mb('shared_' + d + '.json')).join(', '), '; unused meshes dropped', dropped);
