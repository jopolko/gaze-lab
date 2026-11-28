// GEO3 (2026-11-28): three.js's own geometry generators, written out for Babylon, so the ported modules (icons, pickupmesh, snowball) keep the exact vertices,
// normals, uvs and triangle order they had under three.js. Each returns a B.VertexData. Coordinates are the game's raw coordinates, as they were under three.
//   sphere   = THREE.SphereGeometry(radius, widthSegments, heightSegments)
//   cylinder = THREE.CylinderGeometry(radiusTop, radiusBottom, height, radialSegments, heightSegments = 1, openEnded)
//   box      = THREE.BoxGeometry(w, h, d)              plane = THREE.PlaneGeometry(w, h)
//   torus    = THREE.TorusGeometry(radius, tube, radialSegments, tubularSegments)   (lies in XY, as three's)
//   icosahedron(radius, detail) = THREE.IcosahedronGeometry (non-indexed, flat normals as three computes them)
//   octahedron(radius) = THREE.OctahedronGeometry(radius, 0)
//   tube(points, tubularSegments, radius, radialSegments) = THREE.TubeGeometry(new CatmullRomCurve3(points), ...) (centripetal, Frenet frames, open)
// Helpers: transform(vd, M) with a three-style column-major matrix array (same memory layout as Babylon's), toNonIndexed(vd), flatNormals(vd).
export function createGeo3(B) {
  const VD = (pos, nor, idx, uv) => { const v = new B.VertexData(); v.positions = pos; v.normals = nor; v.indices = idx; if (uv) v.uvs = uv; return v; };
  function sphere(radius = 1, ws = 32, hs = 16, phiStart = 0, phiLength = Math.PI * 2, thetaStart = 0, thetaLength = Math.PI) {
    ws = Math.max(3, Math.floor(ws)); hs = Math.max(2, Math.floor(hs)); const thetaEnd = Math.min(thetaStart + thetaLength, Math.PI), grid = [], pos = [], nor = [], uv = [], idx = []; let index = 0;
    for (let iy = 0; iy <= hs; iy++) { const row = [], v = iy / hs; let uOff = 0; if (iy === 0 && thetaStart === 0) uOff = .5 / ws; else if (iy === hs && thetaEnd === Math.PI) uOff = -.5 / ws;
      for (let ix = 0; ix <= ws; ix++) { const u = ix / ws, x = -radius * Math.cos(phiStart + u * phiLength) * Math.sin(thetaStart + v * thetaLength), y = radius * Math.cos(thetaStart + v * thetaLength), z = radius * Math.sin(phiStart + u * phiLength) * Math.sin(thetaStart + v * thetaLength);
        pos.push(x, y, z); const l = Math.hypot(x, y, z) || 1; nor.push(x / l, y / l, z / l); uv.push(u + uOff, 1 - v); row.push(index++); } grid.push(row); }
    for (let iy = 0; iy < hs; iy++) for (let ix = 0; ix < ws; ix++) { const a = grid[iy][ix + 1], b = grid[iy][ix], c = grid[iy + 1][ix], d = grid[iy + 1][ix + 1]; if (iy !== 0 || thetaStart > 0) idx.push(a, b, d); if (iy !== hs - 1 || thetaEnd < Math.PI) idx.push(b, c, d); }
    return VD(pos, nor, idx, uv); }
  function cylinder(rt = 1, rb = 1, h = 1, rs = 32, hs = 1, open = false, thetaStart = 0, thetaLength = Math.PI * 2) {
    rs = Math.floor(rs); hs = Math.floor(hs); const pos = [], nor = [], uv = [], idx = [], grid = [], half = h / 2; let index = 0; const slope = (rb - rt) / h;
    for (let y = 0; y <= hs; y++) { const row = [], v = y / hs, r = v * (rb - rt) + rt; for (let x = 0; x <= rs; x++) { const u = x / rs, th = u * thetaLength + thetaStart, s = Math.sin(th), c = Math.cos(th); pos.push(r * s, -v * h + half, r * c); const l = Math.hypot(s, slope, c); nor.push(s / l, slope / l, c / l); uv.push(u, 1 - v); row.push(index++); } grid.push(row); }
    for (let x = 0; x < rs; x++) for (let y = 0; y < hs; y++) { const a = grid[y][x], b = grid[y + 1][x], c = grid[y + 1][x + 1], d = grid[y][x + 1]; idx.push(a, b, d); idx.push(b, c, d); }
    const cap = (top) => { const r = top ? rt : rb, sign = top ? 1 : -1; if (r <= 0 && false) return; const c0 = index; for (let x = 1; x <= rs; x++) { pos.push(0, half * sign, 0); nor.push(0, sign, 0); uv.push(.5, .5); index++; } const e0 = index;
      for (let x = 0; x <= rs; x++) { const u = x / rs, th = u * thetaLength + thetaStart, c = Math.cos(th), s = Math.sin(th); pos.push(r * s, half * sign, r * c); nor.push(0, sign, 0); uv.push(c * .5 + .5, s * .5 * sign + .5); index++; }
      for (let x = 0; x < rs; x++) { const c = c0 + x, i = e0 + x; if (top) idx.push(i, i + 1, c); else idx.push(i + 1, i, c); } };
    if (!open) { if (rt > 0) cap(true); if (rb > 0) cap(false); }
    return VD(pos, nor, idx, uv); }
  function box(w = 1, hh = 1, d = 1) {
    const pos = [], nor = [], uv = [], idx = []; let n = 0;
    const plane = (u, v, wdir, udir, vdir, width, height, depth) => { const sx = width, sy = height, hw = sx / 2, hgt = sy / 2, dh = depth / 2; const base = n;
      for (let iy = 0; iy <= 1; iy++) { const y = iy * sy - hgt; for (let ix = 0; ix <= 1; ix++) { const x = ix * sx - hw, p = [0, 0, 0], q = [0, 0, 0]; p[u] = x * udir; p[v] = y * vdir; p[wdir] = dh; q[wdir] = depth > 0 ? 1 : -1; pos.push(...p); nor.push(...q); uv.push(ix, 1 - iy); n++; } }
      const a = base, b = base + 2, c = base + 3, e = base + 1; idx.push(a, b, e, b, c, e); };
    plane(2, 1, 0, -1, -1, d, hh, w); plane(2, 1, 0, 1, -1, d, hh, -w); plane(0, 2, 1, 1, 1, w, d, hh); plane(0, 2, 1, 1, -1, w, d, -hh); plane(0, 1, 2, 1, -1, w, hh, d); plane(0, 1, 2, -1, -1, w, hh, -d);
    return VD(pos, nor, idx, uv); }
  function plane(w = 1, h = 1) { return VD([-w / 2, h / 2, 0, w / 2, h / 2, 0, -w / 2, -h / 2, 0, w / 2, -h / 2, 0], [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], [0, 2, 1, 2, 3, 1], [0, 1, 1, 1, 0, 0, 1, 0]); }
  function torus(R = 1, t = .4, rs = 12, ts = 48, arc = Math.PI * 2) {
    const pos = [], nor = [], uv = [], idx = [];
    for (let j = 0; j <= rs; j++) for (let i = 0; i <= ts; i++) { const u = i / ts * arc, v = j / rs * Math.PI * 2, x = (R + t * Math.cos(v)) * Math.cos(u), y = (R + t * Math.cos(v)) * Math.sin(u), z = t * Math.sin(v); pos.push(x, y, z); const cx = R * Math.cos(u), cy = R * Math.sin(u), nx = x - cx, ny = y - cy, nz = z, l = Math.hypot(nx, ny, nz) || 1; nor.push(nx / l, ny / l, nz / l); uv.push(i / ts, j / rs); }
    for (let j = 1; j <= rs; j++) for (let i = 1; i <= ts; i++) { const a = (ts + 1) * j + i - 1, b = (ts + 1) * (j - 1) + i - 1, c = (ts + 1) * (j - 1) + i, d = (ts + 1) * j + i; idx.push(a, b, d, b, c, d); }
    return VD(pos, nor, idx, uv); }
  function flatNormals(vd) { const p = vd.positions, nor = new Array(p.length); for (let i = 0; i < p.length; i += 9) { const ax = p[i + 3] - p[i], ay = p[i + 4] - p[i + 1], az = p[i + 5] - p[i + 2], bx = p[i + 6] - p[i], by = p[i + 7] - p[i + 1], bz = p[i + 8] - p[i + 2]; let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx; const l = Math.hypot(nx, ny, nz) || 1; for (let k = 0; k < 3; k++) { nor[i + k * 3] = nx / l; nor[i + k * 3 + 1] = ny / l; nor[i + k * 3 + 2] = nz / l; } } vd.normals = nor; return vd; }
  function polyhedron(V, F, radius, detail) {          // three PolyhedronGeometry: subdivide each face, push onto the sphere, non-indexed, flat normals (detail 0) as three computes them
    const out = [], lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
    for (let f = 0; f < F.length; f += 3) { const a = V[F[f]], b = V[F[f + 1]], c = V[F[f + 2]], cols = detail + 1, v = [];
      for (let i = 0; i <= cols; i++) { v[i] = []; const aj = lerp(a, c, i / cols), bj = lerp(b, c, i / cols), rows = cols - i; for (let j = 0; j <= rows; j++) v[i][j] = (j === 0 && i === cols) ? aj : lerp(aj, bj, j / rows); }
      for (let i = 0; i < cols; i++) for (let j = 0; j < 2 * (cols - i) - 1; j++) { const k = Math.floor(j / 2); if (j % 2 === 0) out.push(v[i][k + 1], v[i + 1][k], v[i][k]); else out.push(v[i][k + 1], v[i + 1][k + 1], v[i + 1][k]); } }
    const pos = []; for (const q of out) { const l = Math.hypot(q[0], q[1], q[2]) || 1; pos.push(q[0] / l * radius, q[1] / l * radius, q[2] / l * radius); }
    const vd = VD(pos, null, pos.map((_, i) => i).slice(0, pos.length / 3)); if (detail === 0) flatNormals(vd); else { const nor = []; for (let i = 0; i < pos.length; i += 3) { const l = Math.hypot(pos[i], pos[i + 1], pos[i + 2]) || 1; nor.push(pos[i] / l, pos[i + 1] / l, pos[i + 2] / l); } vd.normals = nor; } return vd; }
  function icosahedron(radius = 1, detail = 0) { const t = (1 + Math.sqrt(5)) / 2, v = [-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1], V = []; for (let i = 0; i < v.length; i += 3) V.push([v[i], v[i + 1], v[i + 2]]);
    return polyhedron(V, [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1], radius, detail); }
  function octahedron(radius = 1, detail = 0) { return polyhedron([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2], radius, detail); }
  // THREE.CatmullRomCurve3 (centripetal, tension .5): getPoint(t) with three's end extension, getPointAt(u) by arc length (200 divisions, as three's getLengths)
  function catmull(P) {
    const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    const point = (t) => { const l = P.length, p = (l - 1) * t; let ip = Math.floor(p), w = p - ip; if (w === 0 && ip === l - 1) { ip = l - 2; w = 1; }
      const p0 = ip > 0 ? P[ip - 1] : add(sub(P[0], P[1]), P[0]), p1 = P[ip % l], p2 = P[(ip + 1) % l], p3 = ip + 2 < l ? P[ip + 2] : add(sub(P[l - 1], P[l - 2]), P[l - 1]);
      const ds = (a, b) => Math.pow((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2, .25); let dt0 = ds(p0, p1), dt1 = ds(p1, p2), dt2 = ds(p2, p3); if (dt1 < 1e-4) dt1 = 1; if (dt0 < 1e-4) dt0 = dt1; if (dt2 < 1e-4) dt2 = dt1;
      return [0, 1, 2].map((k) => { let t1 = (p1[k] - p0[k]) / dt0 - (p2[k] - p0[k]) / (dt0 + dt1) + (p2[k] - p1[k]) / dt1, t2 = (p2[k] - p1[k]) / dt1 - (p3[k] - p1[k]) / (dt1 + dt2) + (p3[k] - p2[k]) / dt2; t1 *= dt1; t2 *= dt1; const c0 = p1[k], c1 = t1, c2 = -3 * p1[k] + 3 * p2[k] - 2 * t1 - t2, c3 = 2 * p1[k] - 2 * p2[k] + t1 + t2; return c0 + c1 * w + c2 * w * w + c3 * w * w * w; }); };
    const D = 200, L = [0]; let prev = point(0); for (let i = 1; i <= D; i++) { const q = point(i / D); L.push(L[i - 1] + Math.hypot(q[0] - prev[0], q[1] - prev[1], q[2] - prev[2])); prev = q; }
    const uToT = (u) => { const target = u * L[D]; let lo = 0, hi = D; while (lo <= hi) { const m = Math.floor(lo + (hi - lo) / 2); if (L[m] < target) lo = m + 1; else if (L[m] > target) hi = m - 1; else { hi = m; break; } } const i = hi; if (L[i] === target) return i / D; const a = L[i], b = L[i + 1]; return (i + (target - a) / (b - a)) / D; };
    const at = (u) => point(uToT(u)), tangentAt = (u) => { const t = uToT(u), d = 1e-4; let t1 = t - d, t2 = t + d; if (t1 < 0) t1 = 0; if (t2 > 1) t2 = 1; const a = point(t1), b = point(t2), v = sub(b, a), l = Math.hypot(...v) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
    return { at, tangentAt }; }
  function tube(points, ts = 64, radius = 1, rs = 8) {
    const C = catmull(points), cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]], norm = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }, dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    const T = [], N = [], Bn = []; for (let i = 0; i <= ts; i++) T.push(C.tangentAt(i / ts));
    { let min = Infinity; const tx = Math.abs(T[0][0]), ty = Math.abs(T[0][1]), tz = Math.abs(T[0][2]); let nrm = [0, 0, 0]; if (tx <= min) { min = tx; nrm = [1, 0, 0]; } if (ty <= min) { min = ty; nrm = [0, 1, 0]; } if (tz <= min) nrm = [0, 0, 1]; const vec = norm(cross(T[0], nrm)); N[0] = cross(T[0], vec); Bn[0] = cross(T[0], N[0]); }
    for (let i = 1; i <= ts; i++) { N[i] = N[i - 1].slice(); Bn[i] = Bn[i - 1].slice(); let vec = cross(T[i - 1], T[i]); if (Math.hypot(...vec) > Number.EPSILON) { vec = norm(vec); const th = Math.acos(Math.max(-1, Math.min(1, dot(T[i - 1], T[i])))), c = Math.cos(th), s = Math.sin(th), n = N[i];          // rotate N[i] about vec by th (Rodrigues)
        const k = vec, kd = dot(k, n), kx = cross(k, n); N[i] = [n[0] * c + kx[0] * s + k[0] * kd * (1 - c), n[1] * c + kx[1] * s + k[1] * kd * (1 - c), n[2] * c + kx[2] * s + k[2] * kd * (1 - c)]; } Bn[i] = cross(T[i], N[i]); }
    const pos = [], nor = [], uv = [], idx = [];
    for (let i = 0; i <= ts; i++) { const P = C.at(i / ts); for (let j = 0; j <= rs; j++) { const v = j / rs * Math.PI * 2, sin = Math.sin(v), cos = -Math.cos(v), n = norm([cos * N[i][0] + sin * Bn[i][0], cos * N[i][1] + sin * Bn[i][1], cos * N[i][2] + sin * Bn[i][2]]); nor.push(...n); pos.push(P[0] + radius * n[0], P[1] + radius * n[1], P[2] + radius * n[2]); uv.push(i / ts, j / rs); } }
    for (let j = 1; j <= ts; j++) for (let i = 1; i <= rs; i++) { const a = (rs + 1) * (j - 1) + (i - 1), b = (rs + 1) * j + (i - 1), c = (rs + 1) * j + i, d = (rs + 1) * (j - 1) + i; idx.push(a, b, d, b, c, d); }
    return VD(pos, nor, idx, uv); }
  function toNonIndexed(vd) { const p = [], n = [], u = [], c = []; for (const i of vd.indices) { p.push(vd.positions[i * 3], vd.positions[i * 3 + 1], vd.positions[i * 3 + 2]); if (vd.normals) n.push(vd.normals[i * 3], vd.normals[i * 3 + 1], vd.normals[i * 3 + 2]); if (vd.uvs) u.push(vd.uvs[i * 2], vd.uvs[i * 2 + 1]); if (vd.colors) c.push(vd.colors[i * 4], vd.colors[i * 4 + 1], vd.colors[i * 4 + 2], vd.colors[i * 4 + 3]); } const o = VD(p, vd.normals ? n : null, p.map((_, i) => i).slice(0, p.length / 3), vd.uvs ? u : null); if (vd.colors) o.colors = c; return o; }
  // a three-style matrix (column-major elements, the same memory layout as a Babylon Matrix) applied to positions and normals: p' = M p
  function transform(vd, M) { const m = M.m || M, p = vd.positions, n = vd.normals; for (let i = 0; i < p.length; i += 3) { const x = p[i], y = p[i + 1], z = p[i + 2]; p[i] = m[0] * x + m[4] * y + m[8] * z + m[12]; p[i + 1] = m[1] * x + m[5] * y + m[9] * z + m[13]; p[i + 2] = m[2] * x + m[6] * y + m[10] * z + m[14]; }
    if (n) { const inv = B.Matrix.FromArray(Array.from(m)).invert().transpose().m; for (let i = 0; i < n.length; i += 3) { const x = n[i], y = n[i + 1], z = n[i + 2]; let a = inv[0] * x + inv[4] * y + inv[8] * z, b = inv[1] * x + inv[5] * y + inv[9] * z, c = inv[2] * x + inv[6] * y + inv[10] * z; const l = Math.hypot(a, b, c) || 1; n[i] = a / l; n[i + 1] = b / l; n[i + 2] = c / l; } } return vd; }
  const clone = (vd) => { const o = VD(vd.positions.slice(), vd.normals ? vd.normals.slice() : null, vd.indices.slice(), vd.uvs ? vd.uvs.slice() : null); if (vd.colors) o.colors = vd.colors.slice(); return o; };
  return { sphere, cylinder, box, plane, torus, icosahedron, octahedron, tube, catmull, toNonIndexed, flatNormals, transform, clone };
}
