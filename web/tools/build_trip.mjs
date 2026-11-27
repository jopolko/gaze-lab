// node tools/build_trip.mjs <biome> <minutes per biome> <seed>  ->  data/trip_<biome>_<seed>/  (a static dump the unmodified game can load: ?lvl=trip_<biome>_<seed>&theme=<biome>)
import fs from 'node:fs'; import { prepare, planTrip, BIOMES, SPEED, ROW_M } from '../downhill-three/trip_plan.js'; import { composeBank, joinCost } from '../downhill-three/trip_compose.mjs'; import { bankRow, bankShared, edgeOf } from './trip_compose_test.mjs';
const [biome = 'alpine', minutes = '5', seed = '1'] = process.argv.slice(2);
const D = new URL('../downhill-three/data/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'), EDGES = JSON.parse(fs.readFileSync(D + 'trip_edges.json')), cat = JSON.parse(fs.readFileSync(D + 'row_catalog.json'));
const rows = prepare(cat), E = (r) => EDGES['long_' + r.d][r.j], cache = new Map();
const joinOk = (a, b) => { const key = a.k * 1000 + b.k; let v = cache.get(key); if (v === undefined) { v = joinCost(E(a), E(b)) < .35; cache.set(key, v); } return v; };
const trip = planTrip(rows, +minutes * BIOMES.length, +seed, joinOk), b = trip.plan.find((p) => p.biome === biome); if (!b) throw new Error('unknown biome');
const plan = b.rows.map((r) => ({ d: 'long_' + r.d, j: r.j }));
const out = await composeBank(plan, bankRow, await bankShared(), edgeOf), dir = D + 'trip_' + biome + '_' + seed + '/'; fs.mkdirSync(dir, { recursive: true });
out.meta.theme = biome; fs.writeFileSync(dir + 'meta.json', JSON.stringify(out.meta));
fs.writeFileSync(dir + 'physics.json', JSON.stringify({ rows: out.phys.rows, vx: out.phys.vx, kickers: out.phys.kickers, anims: out.phys.anims, nodes: out.phys.nodes }));
out.rows.forEach((r, v) => fs.writeFileSync(dir + 'row_' + String(v).padStart(2, '0') + '.json', JSON.stringify(r)));
let worst = 0; for (let v = 1; v < plan.length; v++) worst = Math.max(worst, joinCost(EDGES[plan[v - 1].d][plan[v - 1].j], EDGES[plan[v].d][plan[v].j]));
console.log('built', dir, plan.length, 'rows', (plan.length * ROW_M / 1000).toFixed(1), 'km | dumps used', [...new Set(plan.map((p) => p.d))].join(','), '| worst seam', worst.toFixed(2), 'm | roles', [...new Set(b.rows.map((r) => r.role))].join(','));
