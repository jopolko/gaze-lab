// node tools/trip_compose_test.mjs : composing a dump's own rows in order (no renaming) must give back the dump unchanged.
import fs from 'node:fs'; import { composeBank } from '../downhill-three/trip_compose.mjs';
const D = new URL('../downhill-three/data/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'), rd = (p) => JSON.parse(fs.readFileSync(D + p));
const EDGES = rd('trip_edges.json'); export const edgeOf = (d, j) => EDGES[d][j], bankRow = async (d, j) => { const n = 'bank/' + d + '_' + String(j).padStart(2, '0'); return { heavy: rd(n + '.json'), light: rd(n + '.p.json') }; }, bankShared = () => rd('bank/shared.json');
if (process.argv[1].endsWith('trip_compose_test.mjs')) {
  const d = 'long_s11', m = rd(d + '/meta.json'), ph = rd(d + '/physics.json'), plan = []; for (let j = 0; j < m.nrows; j++) plan.push({ d, j });
  const out = await composeBank(plan, bankRow, await bankShared(), edgeOf, { noRemap: true }); let bad = 0;
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b), chk = (name, ok) => { if (!ok) bad++; console.log(ok ? 'ok  ' : 'FAIL', name); };
  chk('pitch', same(out.meta.pitch.map((p) => p.z), m.pitch.map((p) => p.z)) && out.meta.pitch.every((p, i) => Math.abs(p.h - m.pitch[i].h) < .01));
  chk('trailx (first 1890)', out.meta.trailx.slice(0, 1890).every((v, i) => Math.abs(v - m.trailx[i]) < .002));
  chk('physics rows', Object.keys(ph.rows).every((k) => same(out.phys.rows[k], ph.rows[k]))); chk('vx', same(out.phys.vx, ph.vx)); chk('kickers', same(out.phys.kickers, ph.kickers)); chk('anims', same(out.phys.anims, ph.anims));
  let nodesOk = true; for (const v of [0, 10, 40, 62]) if (!same(out.rows[v].nodes, rd(d + '/row_' + String(v).padStart(2, '0') + '.json').nodes)) nodesOk = false; chk('row nodes', nodesOk);
  chk('slim nodes', out.phys.nodes.length === ph.nodes.length); console.log('slim nodes', out.phys.nodes.length, 'of', ph.nodes.length);
  process.exit(bad ? 1 : 0);
}
