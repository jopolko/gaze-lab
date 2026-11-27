// TRIP COMPOSER: builds one long course out of rows of the existing Godot dumps ("your elements, my layout").
// A plan is a list of source rows [{d:'long_s11', j:7}, ...]. Row v of the new course is source row (d, j) moved so that
//   - the ground meets the previous row at the trail (same height, same trail x), and
//   - every position in its physics data (pickups, rails, kickers, rings, trees, obstacles, node transforms) moves with it, and
//   - every node name / id gets a per-row suffix so a row can be used twice in one course.
// Works in Node (build a static dump to data/trip_*) and, later, in the browser (same functions, fetch instead of fs).
export const ROW = 180, SAMP = 30;           // metres per row; trailx samples per row (every 6 m)
const NAME = /@([A-Za-z0-9_]+)@(\d+)/g;
export function remapStr(s, slot) {
  if (slot === 0) return s;
  if (typeof s !== 'string') return s;
  if (/^\d{9,}$/.test(s)) return s + String(slot).padStart(3, '0');
  return s.indexOf('@') < 0 ? s : s.replace(NAME, (m, c, n) => '@' + c + '@' + (+n + slot * 100000));
}
const X_KEYS = new Set(['x', 'kx', 'cx']), Y_KEYS = new Set(['y', 'gy', 'y0']), Z_KEYS = new Set(['z', 'Z', 'za', 'zb', 'zl', 'z0', 'zmax', 'zmin']);
const P3_KEYS = new Set(['p', 'p0', 'p1']);
// deep copy of a physics object with every position moved by D = [dx, dy, dz] and every name / id suffixed by slot
export function moveObj(o, D, slot, key) {
  if (Array.isArray(o)) {
    if (key === 'trees') return o.map((t) => [t[0] + D[0], t[1] + D[2]]);
    if (key === 'obs') { const r = o.slice(); for (let i = 0; i + 3 < r.length; i += 4) { r[i] += D[0]; r[i + 1] += D[2]; } return r; }
    if (o.length === 3 && typeof o[0] === 'number' && P3_KEYS.has(key)) return [o[0] + D[0], o[1] + D[1], o[2] + D[2]];
    if (key === 'pts' && o.length && Array.isArray(o[0]) && o[0].length === 3) return o.map((p) => [p[0] + D[0], p[1] + D[1], p[2] + D[2]]);
    return o.map((v) => moveObj(v, D, slot, undefined));
  }
  if (o && typeof o === 'object') { const r = {}; for (const k of Object.keys(o)) { const v = o[k]; if (typeof v === 'number') r[k] = X_KEYS.has(k) ? v + D[0] : Y_KEYS.has(k) ? v + D[1] : Z_KEYS.has(k) ? v + D[2] : v; else if (typeof v === 'string') r[k] = remapStr(v, slot); else r[k] = moveObj(v, D, slot, k); } return r; }
  return typeof o === 'string' ? remapStr(o, slot) : o;
}
export function moveNode(n, D, slot) { const r = Object.assign({}, n); for (const k of ['name', 'path', 'iid']) if (typeof r[k] === 'string') r[k] = remapStr(r[k], slot); if (r.xf) { r.xf = r.xf.slice(); r.xf[9] += D[0]; r.xf[10] += D[1]; r.xf[11] += D[2]; } for (const k of ['halo', 'n', 'spin', 'sp']) if (typeof r[k] === 'string') r[k] = remapStr(r[k], slot); return r; }
const interp = (H, x) => { const u = (x + 150) / 5, i = Math.floor(u); if (i < 0 || i >= 60) return null; const f = u - i; return H[i] * (1 - f) + H[i + 1] * f; };
// how well does B (starting) follow A (ending), both on the trail: the largest height difference within +-w m of the trail after matching heights on the trail. Same-course neighbours give 0.
export function joinCost(A, B, w = 30) {
  const dx = A.t1 - B.t0, c = A.t1, yA = interp(A.b, c), yB = interp(B.a, c - dx); if (yA == null || yB == null) return 99; const dy = yA - yB; let mx = 0;
  for (let k = -w; k <= w; k += 2.5) { const a = interp(A.b, c + k), b = interp(B.a, c + k - dx); if (a == null || b == null) continue; mx = Math.max(mx, Math.abs(a - b - dy)); } return mx;
}
// THE BANK: every source row as two small files, so the browser only fetches the rows a course uses.
//   light (needed for the whole course up front): { row (physics), vx, kickers, anims, pnodes (slim nodes), tx (30 trail x samples), pitch [h0, s0, h1, s1] }
//   heavy (fetched as the board nears the row):   { nodes, meshes }
// shared: { meta (seed, ROW_GAP, W_HALF, SLOPE, start, feat_off, nodes), materials, meshes } for the whole bank; edges: data/trip_edges.json { dump: { j: {t0, t1, a, b} } }.
export function bankRecord(m, ph, r, j) {
  const lo = -ROW * (j + 1), hi = -ROW * j, inRow = (z) => z <= hi && z > lo, ids = new Set(r.nodes.map((n) => n.iid));
  return { heavy: { nodes: r.nodes, meshes: r.meshes || {} }, light: { row: ph.rows[j] || {}, vx: (ph.vx || []).filter((k) => inRow(k.z)), kickers: (ph.kickers || []).filter((k) => inRow(k.z)), anims: (ph.anims || []).filter((a) => ids.has(a.n)), pnodes: ph.nodes.filter((n) => ids.has(n.iid)),
    tx: m.trailx.slice(SAMP * j, SAMP * j + SAMP), pitch: [m.pitch[j].h, m.pitch[j].s, m.pitch[j + 1].h, m.pitch[j + 1].s] } };
}
// where each row goes: [dx, dy, dz] per row, from the edges alone (no row data needed)
export function rowOffsets(plan, edgeOf) {
  const out = []; let prevEdge = null, prevD = [0, 0, 0];
  plan.forEach(({ d, j }, v) => { const e = edgeOf(d, j); let dx = 0, dy = 0; if (prevEdge) { dx = prevEdge.t1 + prevD[0] - e.t0; dy = interp(prevEdge.b, prevEdge.t1) + prevD[1] - interp(e.a, e.t0); } const D = [dx, dy, -ROW * (v - j)]; out.push(D); prevD = D; prevEdge = e; });
  return out;
}
export const slotOf = (v, opts) => (opts && opts.noRemap ? 0 : v + 1);
export function moveHeavy(h, D, v, opts) { const slot = slotOf(v, opts); return { j: v, z0: -ROW * v, z1: -ROW * (v + 1), nodes: h.nodes.map((n) => moveNode(n, D, slot)), meshes: h.meshes, row: {}, vx: [], kickers: [], anims: [] }; }
// the whole course's physics from the light records (lights[v] for plan[v]) -> { meta, phys }
export function assemble(plan, lights, offsets, shared, opts = {}) {
  const N = plan.length, P = { rows: {}, vx: [], kickers: [], anims: [], nodes: [] }, trailx = [], pitch = [];
  for (let v = 0; v < N; v++) {
    const b = lights[v], D = offsets[v], slot = slotOf(v, opts), prow = moveObj(b.row, D, slot); if (prow.j !== undefined) prow.j = v; P.rows[v] = prow;
    for (const k of b.vx) P.vx.push(moveObj(k, D, slot)); for (const k of b.kickers) P.kickers.push(moveObj(k, D, slot)); for (const a of b.anims) P.anims.push(moveObj(a, D, slot)); for (const n of b.pnodes) P.nodes.push(moveNode(n, D, slot));
    for (let k = 0; k < SAMP; k++) trailx.push(+(b.tx[k] + D[0]).toFixed(3));
    pitch.push({ h: +(b.pitch[0] + D[1]).toFixed(3), s: b.pitch[1], z: -ROW * v }); if (v === N - 1) pitch.push({ h: +(b.pitch[2] + D[1]).toFixed(3), s: b.pitch[3], z: -ROW * N });
  }
  const last = trailx[trailx.length - 1]; for (let k = 0; k < SAMP * 6; k++) trailx.push(last);
  return { meta: Object.assign({}, shared.meta, { nrows: N, segs: N + 1, pitch, trailx, materials: shared.materials, meshes: shared.meshes }), phys: P };
}
// everything at once (Node): rowData(d, j) -> { heavy, light }
export async function composeBank(plan, rowData, shared, edgeOf, opts = {}) {
  const recs = []; for (const p of plan) recs.push(await rowData(p.d, p.j)); const offsets = rowOffsets(plan, edgeOf), { meta, phys } = assemble(plan, recs.map((r) => r.light), offsets, shared, opts);
  return { meta, phys, rows: recs.map((r, v) => { const o = moveHeavy(r.heavy, offsets[v], v, opts); o.row = phys.rows[v]; return o; }) };
}
