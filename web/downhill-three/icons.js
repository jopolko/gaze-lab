// READABLE POWERUP MODELS: a shield looks like a shield, a magnet like a horseshoe magnet, wings like wings, a saw like a toothed blade, a boost like a lightning bolt.
// Each is a few hundred triangles, built once from three.js's own shape tools (ExtrudeGeometry for outlines, TubeGeometry for the horseshoe, Cylinder / Torus for small parts), with a colour per part
// stored as vertex colours so one material draws the whole thing. They are about 1 unit across (the game scales the body by 1.3) and face the camera along +z.
export function iconGeo(THREE, type) {
  const parts = [];          // { g, c }
  const add = (g, c, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) => { g = g.index ? g.toNonIndexed() : g; g.rotateX(rx); g.rotateY(ry); g.rotateZ(rz); g.translate(x, y, z); parts.push({ g, c }); };
  const plate = (shape, depth, bevel, c, z = 0) => { const g = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 1, curveSegments: 10 }); g.translate(0, 0, -depth / 2 + z); return { g, c }; };
  const poly = (pts) => { const s = new THREE.Shape(); pts.forEach(([x, y], i) => (i ? s.lineTo(x, y) : s.moveTo(x, y))); s.closePath(); return s; };
  if (type === 'shield') {
    const outline = (k) => { const s = new THREE.Shape(); s.moveTo(-.78 * k, .92 * k); s.lineTo(.78 * k, .92 * k); s.lineTo(.78 * k, .12 * k); s.bezierCurveTo(.78 * k, -.5 * k, .36 * k, -.86 * k, 0, -1.12 * k); s.bezierCurveTo(-.36 * k, -.86 * k, -.78 * k, -.5 * k, -.78 * k, .12 * k); s.closePath(); return s; };
    let p = plate(outline(1), .26, .09, [.25, .8, 1]); parts.push(p);
    p = plate(outline(.74), .2, .04, [.07, .3, .55], .13); parts.push(p);
    p = plate(poly([[-.14, .62], [.14, .62], [.14, .22], [.46, .22], [.46, -.06], [.14, -.06], [.14, -.5], [-.14, -.5], [-.14, -.06], [-.46, -.06], [-.46, .22], [-.14, .22]]), .12, .03, [1, 1, 1], .26); parts.push(p);
  } else if (type === 'mult') {          // the magnet
    const pts = []; for (let i = 0; i <= 16; i++) { const a = Math.PI * (i / 16); pts.push(new THREE.Vector3(-Math.cos(a) * .62, Math.sin(a) * .62 + .1, 0)); }
    const arc = new THREE.CatmullRomCurve3([new THREE.Vector3(-.62, -.5, 0), ...pts, new THREE.Vector3(.62, -.5, 0)]);
    add(new THREE.TubeGeometry(arc, 40, .26, 10, false), [.85, .2, .9]);
    add(new THREE.CylinderGeometry(.27, .27, .42, 10), [.95, .95, 1], -.62, -.62, 0);
    add(new THREE.CylinderGeometry(.27, .27, .42, 10), [1, .85, .85], .62, -.62, 0);
    add(new THREE.CylinderGeometry(.285, .285, .1, 10), [1, .25, .25], -.62, -.4, 0);
    add(new THREE.CylinderGeometry(.285, .285, .1, 10), [.3, .45, 1], .62, -.4, 0);
  } else if (type === 'donut') {          // wings
    const wing = (m) => poly([[0, -.18], [.3 * m, .22], [.82 * m, .5], [1.45 * m, .62], [1.22 * m, .38], [1.42 * m, .2], [1.1 * m, .06], [1.2 * m, -.14], [.82 * m, -.12], [.55 * m, -.34]].map(([x, y]) => [x, y]));
    for (const m of [1, -1]) { const p = plate(wing(m), .1, .03, [1, .6, .8]); if (m < 0) { p.g.scale(1, 1, 1); p.g.deleteAttribute && 0; } parts.push(p); }
    add(new THREE.SphereGeometry(.24, 10, 8), [1, 1, 1], 0, .02, 0);
    for (const m of [1, -1]) parts.push(plate(poly([[.2 * m, -.05], [.74 * m, .24], [1.0 * m, .3], [.8 * m, .12], [.5 * m, -.06]]), .12, .02, [1, .92, .96], .06));
  } else if (type === 'boost') {          // a lightning bolt
    parts.push(plate(poly([[.14, 1.15], [-.56, -.05], [-.06, -.05], [-.22, -1.15], [.58, .22], [.06, .22]]), .3, .08, [1, .6, .12]));
  } else if (type === 'saw') {          // a toothed blade with a hub
    const s = new THREE.Shape(), N = 14; for (let i = 0; i < N * 2; i++) { const a = (i / (N * 2)) * Math.PI * 2, r = i % 2 ? .62 : .98, a2 = a + (i % 2 ? 0 : .1); (i ? s.lineTo : s.moveTo).call(s, Math.cos(a2) * r, Math.sin(a2) * r); } s.closePath();
    const h = new THREE.Path(); h.absarc(0, 0, .2, 0, Math.PI * 2, true); s.holes.push(h);
    parts.push(plate(s, .12, .04, [.82, .88, 1]));
    add(new THREE.TorusGeometry(.34, .07, 6, 16), [1, .55, .15], 0, 0, .1);
    add(new THREE.TorusGeometry(.62, .035, 5, 24), [.5, .6, .75], 0, 0, .09);
  } else {
    add(new THREE.OctahedronGeometry(.9, 0), [1, 1, 1]);
  }
  // merge with colour
  const P = [], N2 = [], C = []; for (const { g, c } of parts) { g.computeVertexNormals && !g.attributes.normal && g.computeVertexNormals(); const pos = g.attributes.position, nor = g.attributes.normal; for (let i = 0; i < pos.count; i++) { P.push(pos.getX(i), pos.getY(i), pos.getZ(i)); N2.push(nor.getX(i), nor.getY(i), nor.getZ(i)); C.push(c[0], c[1], c[2]); } }
  const out = new THREE.BufferGeometry(); out.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); out.setAttribute('normal', new THREE.Float32BufferAttribute(N2, 3)); out.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); return out;
}
