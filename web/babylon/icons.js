// READABLE POWERUP MODELS (Babylon port of downhill-three/icons.js, 2026-11-28): a shield looks like a shield, a magnet like a horseshoe magnet, wings like wings,
// a saw like a toothed blade, a boost like a lightning bolt. Same recipes, same sizes and segment counts as the three.js original, built with Babylon:
//   three ExtrudeGeometry (outline + bevel)  -> extrude() below: the outline sampled the way three samples it (lines 1, curves 10, arcs 20 points), caps by ear clipping
//                                               (holes bridged in), and three's bevel: the caps at -bevel / depth+bevel on the outline, the walls on the outline grown by bevel
//   three TubeGeometry / Cylinder / Sphere / Torus / Octahedron -> geo3.js, three's own generators written out for Babylon (same vertices, normals and triangle order)
// A colour per part is stored as vertex colours so one material draws the whole thing. About 1 unit across, facing the camera along +z. Returns B.VertexData.
import { createGeo3 } from './geo3.js';
export function iconGeo(B, type) {
  const parts = [], G3 = createGeo3(B);          // { vd, c }
  const xform = (vd, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) => { vd = G3.toNonIndexed(vd); if (rx) G3.transform(vd, B.Matrix.RotationX(rx)); if (ry) G3.transform(vd, B.Matrix.RotationY(ry)); if (rz) G3.transform(vd, B.Matrix.RotationZ(rz)); G3.transform(vd, B.Matrix.Translation(x, y, z)); return vd; };          // three: toNonIndexed, rotateX, rotateY, rotateZ, then translate (Babylon's rotation matrices have three's memory layout)
  const add = (vd, c, x, y, z, rx, ry, rz) => parts.push({ vd: xform(vd, x, y, z, rx, ry, rz), c });

  // ---- outlines (three Shape / Path): moveTo, lineTo, bezierCurveTo, absarc, closePath, holes
  function Shape() { const s = { segs: [], cur: null, holes: [],
    moveTo(x, y) { s.cur = [x, y]; s.segs.push({ k: 'm', p: [x, y] }); return s; }, lineTo(x, y) { s.segs.push({ k: 'l', a: s.cur, p: [x, y] }); s.cur = [x, y]; return s; },
    bezierCurveTo(x1, y1, x2, y2, x, y) { s.segs.push({ k: 'b', a: s.cur, c1: [x1, y1], c2: [x2, y2], p: [x, y] }); s.cur = [x, y]; return s; },
    absarc(cx, cy, r, a0, a1, cw) { s.segs.push({ k: 'a', cx, cy, r, a0, a1, cw }); s.cur = [cx + Math.cos(a1) * r, cy + Math.sin(a1) * r]; return s; },
    closePath() { return s; },
    points(div) { const P = []; const push = (q) => { const l = P[P.length - 1]; if (!l || l[0] !== q[0] || l[1] !== q[1]) P.push(q); };
      for (const g of s.segs) {
        if (g.k === 'm' || g.k === 'l') push(g.p);
        else if (g.k === 'b') for (let i = 1; i <= div; i++) { const t = i / div, u = 1 - t; push([u * u * u * g.a[0] + 3 * u * u * t * g.c1[0] + 3 * u * t * t * g.c2[0] + t * t * t * g.p[0], u * u * u * g.a[1] + 3 * u * u * t * g.c1[1] + 3 * u * t * t * g.c2[1] + t * t * t * g.p[1]]); }
        else if (g.k === 'a') { let d = g.a1 - g.a0; while (d < 0) d += Math.PI * 2; while (d > Math.PI * 2) d -= Math.PI * 2; if (d < 1e-6) d = Math.PI * 2; if (g.cw) d = d === Math.PI * 2 ? -d : d - Math.PI * 2; const n = div * 2; for (let i = 0; i <= n; i++) { const a = g.a0 + d * i / n; push([g.cx + Math.cos(a) * g.r, g.cy + Math.sin(a) * g.r]); } }          /* (three: an EllipseCurve is sampled with twice the divisions) */
      }
      const f = P[0], l = P[P.length - 1]; if (P.length > 2 && f[0] === l[0] && f[1] === l[1]) P.pop(); return P; } }; return s; }
  const area = (P) => { let a = 0; for (let p = P.length - 1, q = 0; q < P.length; p = q++) a += P[p][0] * P[q][1] - P[q][0] * P[p][1]; return a * .5; };          // three ShapeUtils.area: > 0 counter-clockwise
  // ear clipping, holes bridged to the outline (the saw's hub hole): Eberly's method, the bridge is always visible: a ray from the hole's rightmost point to the
  // nearest outline edge, that edge's right end, or the reflex corner inside the triangle it makes that is closest in angle. Gives a simple polygon; then ears.
  function triangulate(outer, holes) {
    let poly = outer.slice(); if (area(poly) < 0) poly.reverse();
    const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
    const inTri = (p, a, b, c) => { const d1 = cross(a, b, p), d2 = cross(b, c, p), d3 = cross(c, a, p); return d1 >= 0 && d2 >= 0 && d3 >= 0; };
    const hs = holes.map((h0) => { const h = h0.slice(); if (area(h) > 0) h.reverse(); let hi = 0; for (let i = 1; i < h.length; i++) if (h[i][0] > h[hi][0]) hi = i; return { h, hi }; }).sort((a, b) => b.h[b.hi][0] - a.h[a.hi][0]);
    for (const { h, hi } of hs) { const M = h[hi]; let best = -1, bx = Infinity;
      for (let i = 0; i < poly.length; i++) { const a = poly[i], b = poly[(i + 1) % poly.length]; if ((a[1] - M[1]) * (b[1] - M[1]) > 0) continue; if (a[1] === b[1]) continue; const t = (M[1] - a[1]) / (b[1] - a[1]), x = a[0] + (b[0] - a[0]) * t; if (x >= M[0] && x < bx) { bx = x; best = a[0] > b[0] ? i : (i + 1) % poly.length; } }
      const I = [bx, M[1]], P = poly[best]; let pick = best, bestAng = Infinity, bestD = Infinity;
      for (let k = 0; k < poly.length; k++) { if (k === best) continue; const v = poly[k], prev = poly[(k + poly.length - 1) % poly.length], next = poly[(k + 1) % poly.length]; if (cross(prev, v, next) >= 0) continue;          // only reflex corners can block
        const tri = cross(M, I, P) >= 0 ? inTri(v, M, I, P) : inTri(v, M, P, I); if (!tri) continue; const ang = Math.abs(Math.atan2(v[1] - M[1], v[0] - M[0])), d = Math.hypot(v[0] - M[0], v[1] - M[1]); if (ang < bestAng || (ang === bestAng && d < bestD)) { bestAng = ang; bestD = d; pick = k; } }
      const ring = []; for (let k = 0; k <= h.length; k++) ring.push(h[(hi + k) % h.length]); poly = poly.slice(0, pick + 1).concat(ring, [poly[pick]], poly.slice(pick + 1)); }
    const tris = [], idx = poly.map((_, i) => i);
    const isEar = (ia, ib, ic) => { const a = poly[ia], b = poly[ib], c = poly[ic]; if (cross(a, b, c) <= 0) return false; for (const j of idx) { if (j === ia || j === ib || j === ic) continue; const p = poly[j]; if ((p[0] === a[0] && p[1] === a[1]) || (p[0] === b[0] && p[1] === b[1]) || (p[0] === c[0] && p[1] === c[1])) continue; if (inTri(p, a, b, c)) return false; } return true; };
    let guard = 0; while (idx.length > 3 && guard++ < 20000) { let cut = false;
      for (let i = 0; i < idx.length; i++) { const ia = idx[(i + idx.length - 1) % idx.length], ib = idx[i], ic = idx[(i + 1) % idx.length]; if (isEar(ia, ib, ic)) { tris.push([poly[ia], poly[ib], poly[ic]]); idx.splice(i, 1); cut = true; break; } }
      if (!cut) { let k = 0; for (let i = 0; i < idx.length; i++) { const a = poly[idx[(i + idx.length - 1) % idx.length]], b = poly[idx[i]], c = poly[idx[(i + 1) % idx.length]]; if (Math.abs(cross(a, b, c)) < 1e-12) { k = i; break; } } idx.splice(k, 1); } }          // (a flat corner on the bridge: drop it, no triangle)
    if (idx.length === 3 && cross(poly[idx[0]], poly[idx[1]], poly[idx[2]]) > 0) tris.push([poly[idx[0]], poly[idx[1]], poly[idx[2]]]); return tris; }
  function bevelVec(pt, prev, next) {
    let tx, ty, shrink; const px = pt[0] - prev[0], py = pt[1] - prev[1], nx = next[0] - pt[0], ny = next[1] - pt[1], plsq = px * px + py * py, col = px * ny - py * nx;
    if (Math.abs(col) > Number.EPSILON) { const pl = Math.sqrt(plsq), nl = Math.sqrt(nx * nx + ny * ny), psx = prev[0] - py / pl, psy = prev[1] + px / pl, nsx = next[0] - ny / nl, nsy = next[1] + nx / nl, sf = ((nsx - psx) * ny - (nsy - psy) * nx) / (px * ny - py * nx);
      tx = psx + px * sf - pt[0]; ty = psy + py * sf - pt[1]; const tl = tx * tx + ty * ty; if (tl <= 2) return [tx, ty]; shrink = Math.sqrt(tl / 2); }
    else { let eq = false; if (px > Number.EPSILON) { if (nx > Number.EPSILON) eq = true; } else if (px < -Number.EPSILON) { if (nx < -Number.EPSILON) eq = true; } else if (Math.sign(py) === Math.sign(ny)) eq = true;
      if (eq) { tx = -py; ty = px; shrink = Math.sqrt(plsq); } else { tx = px; ty = py; shrink = Math.sqrt(plsq / 2); } }
    return [tx / shrink, ty / shrink]; }
  const bevelOut = (P, d) => P.map((p, i) => { const v = bevelVec(p, P[(i + P.length - 1) % P.length], P[(i + 1) % P.length]); return [p[0] + v[0] * d, p[1] + v[1] * d]; });
  // (the old grow, kept unused)
  const grow = (P, d, ccw) => P.map((p, i) => { const a = P[(i + P.length - 1) % P.length], b = P[(i + 1) % P.length]; let nx = (b[1] - a[1]), ny = -(b[0] - a[0]); const l = Math.hypot(nx, ny) || 1; nx /= l; ny /= l; if (!ccw) { nx = -nx; ny = -ny; } return [p[0] + nx * d, p[1] + ny * d]; });
  // three ExtrudeGeometry({ depth, bevelEnabled, bevelThickness: b, bevelSize: b, bevelSegments: 1, curveSegments: 10 }): flat-shaded, non-indexed
  function extrude(shape, depth, b) {
    let outer = shape.points(10); const holes = shape.holes.map((h) => h.points(10)), pos = [];
    if (!(area(outer) < 0)) { outer = outer.slice().reverse(); for (let h = 0; h < holes.length; h++) if (area(holes[h]) < 0) holes[h] = holes[h].slice().reverse(); }          /* (three: the outline clockwise, its holes then counter-clockwise) */
    const tri = (a, c, d) => pos.push(a[0], a[1], a[2], c[0], c[1], c[2], d[0], d[1], d[2]);
    const caps = triangulate(outer, holes);
    for (const [a, c, d] of caps) { tri([a[0], a[1], -b], [d[0], d[1], -b], [c[0], c[1], -b]); tri([a[0], a[1], depth + b], [c[0], c[1], depth + b], [d[0], d[1], depth + b]); }          // back cap faces -z, front cap +z
    const wall = (P, isHole) => { const ccw = area(P) > 0, G = bevelOut(P, b), L = [[P, -b], [G, 0], [G, depth], [P, depth + b]];
      for (let k = 0; k < 3; k++) { const [A, za] = L[k], [C, zc] = L[k + 1]; for (let i = 0; i < P.length; i++) { const j = (i + 1) % P.length, p0 = [A[i][0], A[i][1], za], p1 = [A[j][0], A[j][1], za], q0 = [C[i][0], C[i][1], zc], q1 = [C[j][0], C[j][1], zc];
        if (ccw !== isHole) { tri(p0, p1, q1); tri(p0, q1, q0); } else { tri(p0, q1, p1); tri(p0, q0, q1); } } } };
    wall(outer, false); for (const h of holes) wall(h, true);
    const vd = new B.VertexData(); vd.positions = pos; vd.indices = pos.map((_, i) => i).slice(0, pos.length / 3);
    // flat shading (three computes normals on the non-indexed extrude: one normal per face)
    const fn = []; for (let i = 0; i < pos.length; i += 9) { const ax = pos[i + 3] - pos[i], ay = pos[i + 4] - pos[i + 1], az = pos[i + 5] - pos[i + 2], bx = pos[i + 6] - pos[i], by = pos[i + 7] - pos[i + 1], bz = pos[i + 8] - pos[i + 2]; let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx; const l = Math.hypot(nx, ny, nz) || 1; nx /= l; ny /= l; nz /= l; fn.push(nx, ny, nz, nx, ny, nz, nx, ny, nz); } vd.normals = fn;
    return vd; }
  const plate = (shape, depth, bevel, c, z = 0) => { const vd = extrude(shape, depth, bevel); G3.transform(vd, B.Matrix.Translation(0, 0, -depth / 2 + z)); return { vd, c }; };
  const poly = (pts) => { const s = Shape(); pts.forEach(([x, y], i) => (i ? s.lineTo(x, y) : s.moveTo(x, y))); s.closePath(); return s; };
  const crTube = (ctrl, segs, r, n) => G3.tube(ctrl, segs, r, n);          // THREE.TubeGeometry(new CatmullRomCurve3(ctrl), segs, r, n, false)
  const cyl = (rt, rb, h, n) => G3.cylinder(rt, rb, h, n);
  const sphere = (r, ws, hs) => G3.sphere(r, ws, hs);
  const torus = (R, t, rs, ts) => G3.torus(R, t, rs, ts);          // in XY, as three's
  const octa = (r) => G3.octahedron(r, 0);

  if (type === 'shield') {
    const outline = (k) => { const s = Shape(); s.moveTo(-.78 * k, .92 * k); s.lineTo(.78 * k, .92 * k); s.lineTo(.78 * k, .12 * k); s.bezierCurveTo(.78 * k, -.5 * k, .36 * k, -.86 * k, 0, -1.12 * k); s.bezierCurveTo(-.36 * k, -.86 * k, -.78 * k, -.5 * k, -.78 * k, .12 * k); s.closePath(); return s; };
    parts.push(plate(outline(1), .26, .09, [.25, .8, 1]));
    parts.push(plate(outline(.74), .2, .04, [.07, .3, .55], .13));
    parts.push(plate(poly([[-.14, .62], [.14, .62], [.14, .22], [.46, .22], [.46, -.06], [.14, -.06], [.14, -.5], [-.14, -.5], [-.14, -.06], [-.46, -.06], [-.46, .22], [-.14, .22]]), .12, .03, [1, 1, 1], .26));
  } else if (type === 'mult') {          // the magnet
    const pts = []; for (let i = 0; i <= 16; i++) { const a = Math.PI * (i / 16); pts.push([-Math.cos(a) * .62, Math.sin(a) * .62 + .1, 0]); }
    add(crTube([[-.62, -.5, 0], ...pts, [.62, -.5, 0]], 40, .26, 10), [.85, .2, .9]);
    add(cyl(.27, .27, .42, 10), [.95, .95, 1], -.62, -.62, 0);
    add(cyl(.27, .27, .42, 10), [1, .85, .85], .62, -.62, 0);
    add(cyl(.285, .285, .1, 10), [1, .25, .25], -.62, -.4, 0);
    add(cyl(.285, .285, .1, 10), [.3, .45, 1], .62, -.4, 0);
  } else if (type === 'donut') {          // wings
    const wing = (m) => poly([[0, -.18], [.3 * m, .22], [.82 * m, .5], [1.45 * m, .62], [1.22 * m, .38], [1.42 * m, .2], [1.1 * m, .06], [1.2 * m, -.14], [.82 * m, -.12], [.55 * m, -.34]]);
    for (const m of [1, -1]) parts.push(plate(wing(m), .1, .03, [1, .6, .8]));
    add(sphere(.24, 10, 8), [1, 1, 1], 0, .02, 0);
    for (const m of [1, -1]) parts.push(plate(poly([[.2 * m, -.05], [.74 * m, .24], [1.0 * m, .3], [.8 * m, .12], [.5 * m, -.06]]), .12, .02, [1, .92, .96], .06));
  } else if (type === 'boost') {          // a lightning bolt
    parts.push(plate(poly([[.14, 1.15], [-.56, -.05], [-.06, -.05], [-.22, -1.15], [.58, .22], [.06, .22]]), .3, .08, [1, .6, .12]));
  } else if (type === 'saw') {          // a toothed blade with a hub
    const s = Shape(), N = 14; for (let i = 0; i < N * 2; i++) { const a = (i / (N * 2)) * Math.PI * 2, r = i % 2 ? .62 : .98, a2 = a + (i % 2 ? 0 : .1); (i ? s.lineTo : s.moveTo).call(s, Math.cos(a2) * r, Math.sin(a2) * r); } s.closePath();
    const h = Shape(); h.absarc(0, 0, .2, 0, Math.PI * 2, true); s.holes.push(h);
    parts.push(plate(s, .12, .04, [.82, .88, 1]));
    add(torus(.34, .07, 6, 16), [1, .55, .15], 0, 0, .1);
    add(torus(.62, .035, 5, 24), [.5, .6, .75], 0, 0, .09);
  } else {
    add(octa(.9), [1, 1, 1]);
  }
  // merge with colour
  const P = [], N2 = [], C = [], I = []; for (const { vd, c } of parts) { const base = P.length / 3, n = vd.positions.length / 3; P.push(...vd.positions); N2.push(...vd.normals); for (let i = 0; i < n; i++) C.push(c[0], c[1], c[2], 1); for (const i of vd.indices) I.push(i + base); }
  const out = new B.VertexData(); out.positions = P; out.normals = N2; out.colors = C; out.indices = I; return out;
}
