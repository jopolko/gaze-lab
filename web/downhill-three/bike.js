// A DIRTBIKE FRONT END, seen from behind and above, to replace the board tip. About 1,500 triangles in four meshes (wheel, fork + fender, handlebars + rider's hands, lamp).
//   const B = createBike(THREE, { accent: [1, .45, .1] });  scene.add(B.group);   B.update(dt, { speed, steer, comp, lean });
//   speed  forward speed in m/s (spins the wheel, tread knobs make the spin visible)       steer  -1..1 (turns the bars and fork about the steering axis)
//   comp   0..1 fork compression (landings and bumps push the lower legs up the fork; 0 = fully extended in the air)
// The group's origin is the ground under the front axle's line; forward is -z, up is +y (the same frame as the board tip). Everything is vertex-coloured so one standard material draws each mesh.
export function createBike(THREE, opts = {}) {
  const acc = opts.accent || [1, .45, .1], R = .34, RAKE = .45, D = new THREE.Vector3(0, -Math.cos(RAKE), -Math.sin(RAKE)), UPAX = new THREE.Vector3(0, Math.cos(RAKE), Math.sin(RAKE));
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .5, metalness: .2, side: THREE.DoubleSide });
  const mk = (parts) => {
    const P = [], N = [], C = [];
    for (const { g, c, m } of parts) { let gg = g.index ? g.toNonIndexed() : g.clone(); gg.applyMatrix4(m || new THREE.Matrix4()); if (!gg.attributes.normal) gg.computeVertexNormals(); const p = gg.attributes.position, n = gg.attributes.normal; for (let i = 0; i < p.count; i++) { P.push(p.getX(i), p.getY(i), p.getZ(i)); N.push(n.getX(i), n.getY(i), n.getZ(i)); C.push(c[0], c[1], c[2]); } }
    const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); geo.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3)); geo.setAttribute('color', new THREE.Float32BufferAttribute(C, 3));
    const mesh = new THREE.Mesh(geo, mat); mesh.frustumCulled = false; return mesh;
  };
  const T = (x, y, z, rx = 0, ry = 0, rz = 0, s = 1) => new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz, 'YXZ')), new THREE.Vector3(s, s, s));
  const along = (a, b) => { const d = b.clone().sub(a), len = d.length(), q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.clone().normalize()); return { len, m: new THREE.Matrix4().compose(a.clone().add(b).multiplyScalar(.5), q, new THREE.Vector3(1, 1, 1)) }; };
  const rod = (a, b, r, c, seg = 8) => { const o = along(new THREE.Vector3(...a), new THREE.Vector3(...b)); return { g: new THREE.CylinderGeometry(r, r, o.len, seg), c, m: o.m }; };

  // ---- the wheel (axle along x, centre at the origin): tyre with knobs, rim, spokes, hub, brake disc
  const wp = [];
  wp.push({ g: new THREE.TorusGeometry(R - .02, .072, 10, 30), c: [.05, .05, .06], m: T(0, 0, 0, 0, Math.PI / 2, 0) });
  for (let i = 0; i < 26; i++) { const a = (i / 26) * Math.PI * 2, side = i % 2 ? .035 : -.035; wp.push({ g: new THREE.BoxGeometry(.11, .035, .045), c: [.13, .13, .14], m: T(side, Math.sin(a) * (R + .02), Math.cos(a) * (R + .02), a, 0, 0) }); }
  wp.push({ g: new THREE.TorusGeometry(.215, .02, 6, 26), c: [.88, .88, .92], m: T(0, 0, 0, 0, Math.PI / 2, 0) });
  for (let i = 0; i < 10; i++) { const a = (i / 10) * Math.PI * 2; wp.push(rod([0, 0, 0], [0, Math.sin(a) * .21, Math.cos(a) * .21], .006, [.75, .75, .8], 4)); }
  wp.push({ g: new THREE.CylinderGeometry(.05, .05, .17, 10), c: [.5, .5, .56], m: T(0, 0, 0, 0, 0, Math.PI / 2) });
  wp.push({ g: new THREE.CylinderGeometry(.13, .13, .012, 22), c: [.62, .62, .68], m: T(.075, 0, 0, 0, 0, Math.PI / 2) });
  wp.push({ g: new THREE.TorusGeometry(.07, .008, 5, 14), c: acc, m: T(.082, 0, 0, 0, Math.PI / 2, 0) });
  const wheel = mk(wp);

  // ---- the lower fork legs and the fender (they move with the wheel when the suspension works)
  const lp = [];
  for (const sx of [-.1, .1]) { lp.push(rod([sx, 0, 0], [sx, 0, 0].map((v, i) => v + [0, D.y, D.z][i] * .36), .036, [.16, .17, .2])); lp.push({ g: new THREE.CylinderGeometry(.05, .05, .09, 10), c: acc, m: T(sx, D.y * .3, D.z * .3, 0, 0, 0).multiply(new THREE.Matrix4().makeRotationX(RAKE)) }); }
  lp.push({ g: new THREE.CylinderGeometry(.04, .04, .24, 8), c: [.2, .2, .24], m: T(0, D.y * .36, D.z * .36, 0, 0, Math.PI / 2) });
  const fendG = new THREE.CylinderGeometry(R + .075, R + .075, .15, 18, 1, true, Math.PI * .5 - .95, 1.9); fendG.rotateZ(Math.PI / 2); fendG.rotateY(Math.PI);
  lp.push({ g: fendG, c: acc, m: T(0, D.y * .6, D.z * .6) });
  const lower = mk(lp);

  // ---- the steering head: upper fork tubes (gold), clamps, handlebars, grips, levers, gloved hands and arms, the lamp and the number plate
  const sp = [], gold = [.95, .72, .2], blk = [.07, .07, .08], steel = [.78, .78, .84];
  for (const sx of [-.1, .1]) sp.push(rod([sx, 0, 0], [sx, D.y * .36, D.z * .36], .03, gold));
  sp.push({ g: new THREE.BoxGeometry(.28, .045, .07), c: [.18, .18, .22], m: T(0, .03, .0) });
  sp.push({ g: new THREE.BoxGeometry(.05, .09, .06), c: [.12, .12, .15], m: T(0, .09, .0) });
  const barPts = [[-.4, .03, .1], [-.32, .1, .02], [-.14, .14, -.01], [.14, .14, -.01], [.32, .1, .02], [.4, .03, .1]].map((p) => new THREE.Vector3(...p));
  sp.push({ g: new THREE.TubeGeometry(new THREE.CatmullRomCurve3(barPts), 24, .016, 7), c: [.1, .1, .12] });
  sp.push(rod([-.2, .125, -.01], [.2, .125, -.01], .011, steel, 6));
  sp.push({ g: new THREE.BoxGeometry(.14, .05, .025), c: acc, m: T(0, .165, -.012) });
  for (const sx of [-1, 1]) {
    sp.push(rod([sx * .34, .08, .04], [sx * .45, .02, .12], .026, [.08, .08, .09], 8));          // the grip
    sp.push({ g: new THREE.CapsuleGeometry(.04, .09, 4, 8), c: [.1, .1, .12], m: T(sx * .4, .045, .08, 0, 0, Math.PI / 2 - sx * .25) });          // the glove
    sp.push({ g: new THREE.BoxGeometry(.012, .012, .12), c: steel, m: T(sx * .3, .105, -.04, 0, sx * .12, 0) });          // the brake / clutch lever
    sp.push(rod([sx * .42, .06, .15], [sx * .46, .16, .36], .042, [.14, .14, .17], 8));          // the forearm, cut short so it stays out of the camera's face
  }
  sp.push({ g: new THREE.SphereGeometry(.1, 12, 10), c: [.14, .14, .17], m: T(0, -.07, -.1, 0, 0, 0).multiply(new THREE.Matrix4().makeScale(1, .85, .8)) });          // the lamp shell (its face looks forward)
  sp.push({ g: new THREE.BoxGeometry(.3, .24, .02), c: acc, m: T(0, -.04, -.17, -.12, 0, 0) });          // the number plate
  sp.push({ g: new THREE.BoxGeometry(.24, .17, .022), c: [1, 1, 1], m: T(0, -.045, -.172, -.12, 0, 0) });
  const head = mk(sp);

  // ---- assemble: root > steerG (pivot at the steering head, turned about the fork axis) > head + lower (slides along the fork) > wheel (spins)
  const group = new THREE.Group(), steerG = new THREE.Group(), lowerG = new THREE.Group(), wheelG = new THREE.Group();
  const headPos = new THREE.Vector3(0, R + (.36 + .24) * Math.cos(RAKE) + .06 - .02, -1.7);          // so the tyre just touches y = 0 when the fork is extended a little
  steerG.position.copy(headPos); group.add(steerG); steerG.add(head); steerG.add(lowerG); lowerG.add(lower); lowerG.add(wheelG); wheelG.add(wheel);
  const axle = D.clone().multiplyScalar(.6); wheelG.position.copy(axle); lower.position.set(0, 0, 0);
  const S = { rot: 0, comp: 0.3, compV: 0 };
  function update(dt, s = {}) {
    dt = Math.min(dt || .016, .05); const speed = s.speed || 0;
    S.rot -= speed * dt / R; wheel.rotation.x = S.rot;
    steerG.quaternion.setFromAxisAngle(UPAX, -(s.steer || 0) * .5);
    // the fork is a damped spring toward the compression the game asks for
    const target = Math.max(0, Math.min(1, s.comp === undefined ? .3 : s.comp)); S.compV += ((target - S.comp) * 220 - S.compV * 18) * dt; S.comp = Math.max(-.2, Math.min(1.2, S.comp + S.compV * dt));
    lowerG.position.copy(D).multiplyScalar(-(S.comp - .3) * .14);
    group.rotation.z = s.lean || 0;
  }
  return { group, update, parts: { wheel, lower, head }, tris: () => [wheel, lower, head].reduce((a, m) => a + m.geometry.attributes.position.count / 3, 0) };
}
