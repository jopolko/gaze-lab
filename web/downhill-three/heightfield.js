// HEIGHTFIELD: the ground height under (x, z) without a raycast.
// The game asks "how high is the snow here" about ten times a frame (the hill's pull, the board's height, the camera, pickups, obstacles, the ramps). It used to answer each with a THREE.Raycaster against the ground meshes,
// which tests every triangle of the chunk under the ray (4080 of them for each 180 m chunk). Godot's ground chunks are a REGULAR GRID: 61 columns 5 m apart, 35 rows 5.29 m apart, every quad split on the same diagonal
// ((0,0)-(1,1)). So the height is two array lookups and one triangle interpolation, with the exact same answer as the raycast (the test compares them).
//
//   const HF = createHeightfield();
//   HF.addMesh(id, positions /*Float32Array xyz*/, index /*Uint16Array|Uint32Array|null*/, [dx, dy, dz]?)   // when a row's ground mesh is built
//   HF.remove(id)                                                                                      // when the row is unloaded
//   HF.height(x, z)  -> y, or null where no chunk covers the point
//   HF.heightOr(x, z, fallback)
//   HF.slope(x, z, e) -> [dh/dx, dh/dz]   the gradient the hill's pull uses (RunRig._grad: central differences over +-e = 0.6 m)
// Meshes that are not regular grids are reported by addMesh() returning false: keep those in the raycast list.

export function createHeightfield() {
  const chunks = new Map(); let list = []; let last = null;
  const EPS = 1e-3, r3 = (v) => Math.round(v / EPS);
  function uniqSorted(vals) { const m = new Map(); for (const v of vals) m.set(r3(v), v); return [...m.entries()].sort((a, b) => a[0] - b[0]).map((e) => e[1]); }
  function addMesh(id, pos, index, off) {
    const ox = off ? off[0] : 0, oy = off ? off[1] : 0, oz = off ? off[2] : 0, n = pos.length / 3;
    const X = new Array(n), Z = new Array(n); for (let i = 0; i < n; i++) { X[i] = pos[i * 3] + ox; Z[i] = pos[i * 3 + 2] + oz; }
    const xs = uniqSorted(X), zs = uniqSorted(Z), NX = xs.length, NZ = zs.length; if (NX < 2 || NZ < 2 || NX * NZ !== n) return false;          // a regular grid has exactly one vertex per (column, row)
    const ix = new Map(), iz = new Map(); xs.forEach((v, k) => ix.set(r3(v), k)); zs.forEach((v, k) => iz.set(r3(v), k));
    const H = new Float32Array(NX * NZ).fill(NaN), cell = new Int32Array(n * 2);
    for (let i = 0; i < n; i++) { const a = ix.get(r3(X[i])), b = iz.get(r3(Z[i])); if (a === undefined || b === undefined) return false; cell[i * 2] = a; cell[i * 2 + 1] = b; H[b * NX + a] = pos[i * 3 + 1] + oy; }
    for (let i = 0; i < H.length; i++) if (Number.isNaN(H[i])) return false;
    // which diagonal splits the quads: find the two triangles of the first quad (columns 0-1, rows 0-1) and see which vertices they share
    let diag = 0;          // 0: the diagonal runs (0,0)-(1,1);  1: it runs (1,0)-(0,1)
    const tri = (t) => (index ? [index[t * 3], index[t * 3 + 1], index[t * 3 + 2]] : [t * 3, t * 3 + 1, t * 3 + 2]), nt = index ? index.length / 3 : n / 3;
    const seen = []; for (let t = 0; t < nt && seen.length < 2; t++) { const v = tri(t), cs = v.map((k) => [cell[k * 2], cell[k * 2 + 1]]); if (cs.every((c) => c[0] <= 1 && c[1] <= 1)) seen.push(cs.map((c) => c[0] + ',' + c[1])); }
    if (seen.length === 2) { const shared = seen[0].filter((c) => seen[1].includes(c)); diag = (shared.includes('0,0') && shared.includes('1,1')) ? 0 : 1; }
    const dx = (xs[NX - 1] - xs[0]) / (NX - 1), dz = (zs[NZ - 1] - zs[0]) / (NZ - 1); let ux = true, uz = true;
    for (let k = 1; k < NX; k++) if (Math.abs(xs[k] - xs[k - 1] - dx) > 2e-3) ux = false; for (let k = 1; k < NZ; k++) if (Math.abs(zs[k] - zs[k - 1] - dz) > 2e-3) uz = false;
    const c = { id, xs: Float64Array.from(xs), zs: Float64Array.from(zs), NX, NZ, H, diag, x0: xs[0], x1: xs[NX - 1], z0: zs[0], z1: zs[NZ - 1], dx, dz, ux, uz };
    chunks.set(id, c); list = [...chunks.values()]; last = null; return true;
  }
  function remove(id) { chunks.delete(id); list = [...chunks.values()]; last = null; }
  function clear() { chunks.clear(); list = []; last = null; }
  const find = (a, v, n, u, d, v0) => { if (u) { const k = Math.floor((v - v0) / d); return k < 0 ? 0 : k > n - 2 ? n - 2 : k; } let lo = 0, hi = n - 2; while (lo < hi) { const m = (lo + hi + 1) >> 1; if (a[m] <= v) lo = m; else hi = m - 1; } return lo; };
  function sample(c, x, z) {
    const i = find(c.xs, x, c.NX, c.ux, c.dx, c.x0), j = find(c.zs, z, c.NZ, c.uz, c.dz, c.z0), NX = c.NX, H = c.H;
    const fx = (x - c.xs[i]) / (c.xs[i + 1] - c.xs[i]), fz = (z - c.zs[j]) / (c.zs[j + 1] - c.zs[j]);
    const y00 = H[j * NX + i], y10 = H[j * NX + i + 1], y01 = H[(j + 1) * NX + i], y11 = H[(j + 1) * NX + i + 1];
    if (c.diag === 0) return fx >= fz ? y00 + fx * (y10 - y00) + fz * (y11 - y10) : y00 + fx * (y11 - y01) + fz * (y01 - y00);          // triangles (00,10,11) and (00,11,01)
    return fx + fz <= 1 ? y00 + fx * (y10 - y00) + fz * (y01 - y00) : y11 + (1 - fx) * (y01 - y11) + (1 - fz) * (y10 - y11);          // triangles (00,10,01) and (10,11,01)
  }
  function height(x, z) {
    const L = last; if (L && x >= L.x0 && x <= L.x1 && z >= L.z0 && z <= L.z1) { let y = sample(L, x, z); for (const c of list) if (c !== L && x >= c.x0 && x <= c.x1 && z >= c.z0 && z <= c.z1) { const y2 = sample(c, x, z); if (y2 > y) y = y2; } return y; }          // (a point on the seam between two chunks is covered by both: the higher one wins, as a ray from above would)
    let best = null; for (const c of list) if (x >= c.x0 && x <= c.x1 && z >= c.z0 && z <= c.z1) { const y = sample(c, x, z); if (best === null || y > best) { best = y; last = c; } } return best;
  }
  const heightOr = (x, z, f) => { const y = height(x, z); return y === null ? f : y; };
  function slope(x, z, e = 0.6) { const a = height(x + e, z), b = height(x - e, z), c = height(x, z + e), d = height(x, z - e); if (a === null || b === null || c === null || d === null) return null; return [(a - b) / (2 * e), (c - d) / (2 * e)]; }
  return { addMesh, remove, clear, height, heightOr, slope, stats: () => ({ chunks: chunks.size }) };
}
