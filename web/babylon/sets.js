/* STORY SETS (owner 2026-11-27): the places the stories happen, built from primitives like the machines, self-lit (the game has no lights).
   AGSETS.build(B, scene, name) -> a TransformNode, origin at ground level on the set's front edge, the set facing -z (toward a camera on the road).
   Used now for the Brochure's hero shots; built to drop into levels later. */
(function () {
  function kit(B, scene, R) { const MAT = {};
    const mat = (col, k, a) => { const key = col.join(',') + (k || '') + (a || ''); if (MAT[key]) return MAT[key]; const m = new B.StandardMaterial('set_' + key, scene), c = new B.Color3(col[0], col[1], col[2]); m.disableLighting = true;
      if (k === 'glow') m.emissiveColor = c; else { m.emissiveColor = c.scale(.75); const f = new B.FresnelParameters(); f.leftColor = c.scale(1.6).add(new B.Color3(.08, .08, .1)); f.rightColor = c.scale(.55); f.power = 1.8; m.emissiveFresnelParameters = f; }
      if (a != null) m.alpha = a; return MAT[key] = m; };
    const add = (m, p, mt, r) => { m.parent = R; m.position.set(p[0], p[1], p[2]); if (r) m.rotation.set(r[0], r[1], r[2]); m.material = mt; m.isPickable = false; return m; };
    const box = (w, h, d, p, col, k, r, a) => add(B.MeshBuilder.CreateBox('sb', { width: w, height: h, depth: d }, scene), p, mat(col, k, a), r);
    const cyl = (h, dd, p, col, k, r, dt) => add(B.MeshBuilder.CreateCylinder('sc', { height: h, diameterTop: dt ?? dd, diameterBottom: dd, tessellation: 20 }, scene), p, mat(col, k), r);
    const sign = (w, h, p, draw, r) => { const dt = new B.DynamicTexture('sgn', { width: Math.round(w * 64), height: Math.round(h * 64) }, scene, true); const g = dt.getContext(); draw(g, dt.getSize().width, dt.getSize().height); dt.update(); dt.hasAlpha = true;
      const m = new B.StandardMaterial('sgnm', scene); m.disableLighting = true; m.emissiveTexture = dt; m.opacityTexture = dt; m.backFaceCulling = false; const pl = add(B.MeshBuilder.CreatePlane('sp', { width: w, height: h }, scene), p, m, r); pl.scaling.x = -1; return pl; };
    const neon = (g, txt, x, y, px, col, font) => { g.font = (font || '900 ') + px + 'px Arial Black, Impact, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.shadowColor = col; for (const b of [px * .6, px * .3, 0]) { g.shadowBlur = b; g.fillStyle = b ? col : '#fff'; g.fillText(txt, x, y); } g.shadowBlur = 0; };
    return { mat, box, cyl, sign, neon }; }
  const SETS = {
    /* ROUTE ZERO: the diner at Mile Zero. The last pumps for 200 km, a neon roof sign, a lit window with the jukebox inside, and tonight's getaway car. */
    diner(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R);
      const WALL = [.1, .32, .4], TRIM = [1, .2, .55], WARM = [1, .78, .42], CHROME = [.55, .6, .68];
      box(16, 4.6, 9, [-6, 2.3, 4.5], WALL); box(16.4, .5, 9.4, [-6, 4.85, 4.5], [.05, .08, .1]);
      box(16.6, .16, .16, [-6, 5.12, -.2], TRIM, 'glow'); box(16.6, .16, .16, [-6, .3, -.15], TRIM, 'glow');
      box(12.5, 1.9, .1, [-6.5, 2.4, -.06], WARM, 'glow'); for (let i = 0; i < 7; i++) box(.12, 1.9, .14, [-12.5 + i * 2.05, 2.4, -.1], [.04, .08, .1]);
      box(1.1, 1.5, .5, [-3.4, 2.2, .3], [1, .35, .7], 'glow'); box(.7, .5, .52, [-3.4, 2.95, .3], [.3, .9, 1], 'glow');          /* the jukebox, seen through the glass */
      box(1.6, 3, .12, [3.3, 1.5, -.07], [.9, .95, 1], 'glow');          /* the door, light spilling out */
      cyl(7, .35, [-14.5, 3.5, 1], CHROME); sign(9, 3.4, [-10.5, 7.9, .8], (g, w, h) => { g.fillStyle = 'rgba(10,6,20,.85)'; g.fillRect(8, 8, w - 16, h - 16); g.strokeStyle = '#ff3d8b'; g.lineWidth = 10; g.strokeRect(14, 14, w - 28, h - 28);
        neon(g, 'MILE ZERO', w / 2, h * .38, 74, '#ff3d8b'); neon(g, 'DINER · FUEL', w / 2, h * .72, 40, '#5ff0ff'); });
      /* the canopy and the last pumps */
      box(13, .55, 7.5, [10, 5.3, -2.2], [.08, .1, .14]); for (const z of [-4.5, -2.2, 0]) box(11, .08, .5, [10, 5.0, z], [.9, .85, .7], 'glow'); for (const [x, z] of [[4.5, -5.3], [15.5, -5.3], [4.5, .8], [15.5, .8]]) cyl(5, .3, [x, 2.5, z], CHROME);
      box(13.2, .5, .1, [10, 5.3, -6], [1, .55, .1], 'glow');
      for (const x of [7, 10, 13]) { box(1, 2.2, .7, [x, 1.1, -2.2], [.75, .1, .12]); box(.7, .5, .05, [x, 1.75, -2.56], [1, .25, .2], 'glow'); cyl(.2, 1.1, [x, .1, -2.2], [.2, .2, .22]); }
      cyl(4, .18, [17.5, 2, -7], [.55, .6, .68]); sign(3.6, 1.6, [17.5, 4.6, -7.05], (g, w, h) => { g.fillStyle = 'rgba(0,0,0,.8)'; g.fillRect(0, 0, w, h); neon(g, 'LAST FUEL', w / 2, h * .36, 30, '#ffb020'); neon(g, '200 KM', w / 2, h * .74, 30, '#ffb020'); });
      /* tonight's getaway car, parked badly, door open, engine running */
      const C = new B.TransformNode('car', scene); C.parent = R; C.position.set(1, 0, -6.5); C.rotation.y = .5; const ck = kit(B, scene, C);
      ck.box(4.4, 1, 2, [0, .8, 0], [.85, .72, .12]); ck.box(2.4, .8, 1.8, [-.3, 1.65, 0], [.1, .12, .16]); for (const [x, z] of [[1.4, .95], [-1.4, .95], [1.4, -.95], [-1.4, -.95]]) ck.cyl(.35, .8, [x, .4, z], [.05, .05, .06], null, [Math.PI / 2, 0, 0]);
      ck.box(.1, .3, .5, [2.22, .9, .55], [1, 1, .85], 'glow'); ck.box(.1, .3, .5, [2.22, .9, -.55], [1, 1, .85], 'glow'); ck.box(.1, .25, .4, [-2.22, .9, .6], [1, .1, .1], 'glow'); ck.box(.1, .25, .4, [-2.22, .9, -.6], [1, .1, .1], 'glow');
      ck.box(1.2, .9, .08, [.2, 1.1, -1.55], [.85, .72, .12], null, [0, .9, 0]);
      return { h: 9, w: 34 }; },
  };
  window.AGSETS = { build: (B, scene, name) => { const R = new B.TransformNode('set_' + name, scene); if (!SETS[name]) return null; R.info = SETS[name](B, scene, R); return R; }, list: Object.keys(SETS) };
})();
