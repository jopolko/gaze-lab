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
    const cyl = (h, dd, p, col, k, r, dt, tess) => add(B.MeshBuilder.CreateCylinder('sc', { height: h, diameterTop: dt ?? dd, diameterBottom: dd, tessellation: tess || 20 }, scene), p, mat(col, k), r);
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
    /* THE SAFE PEAKS: the Hunt. ACCORD Live's gunship over the pass, its searchlight on the road, a camera crane and the broadcast truck on the shoulder. */
    hunt(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R); const SNOW = [.86, .9, .98], ROCK = [.3, .32, .4], RED = [1, .15, .2];
      for (const [x, z, h, w] of [[-60, 60, 46, 60], [-20, 90, 70, 80], [40, 80, 56, 70], [80, 50, 40, 50], [-90, 30, 30, 40]]) { cyl(h, w, [x, h / 2, z], ROCK, null, null, 0); cyl(h * .35, w * .36, [x, h * .83, z], SNOW, null, null, 0); }
      for (let i = 0; i < 8; i++) cyl(.9, .16, [-8, .45, -10 + i * 4], [.6, .62, .7]); box(.12, .25, 32, [-8, .9, 4], [1, .8, .2], 'glow');
      const G = new B.TransformNode('ship', scene); G.parent = R; G.position.set(6, 16, 18); G.rotation.set(.12, -.6, .06); const gk = kit(B, scene, G);
      gk.box(7, 2.2, 2.6, [0, 0, 0], [.12, .14, .18]); gk.box(3, 1.6, 2.2, [3.8, -.2, 0], [.1, .12, .16]); gk.box(6, .35, .5, [-6, .4, 0], [.12, .14, .18]); gk.box(.35, 2, .5, [-8.6, 1.2, 0], [.12, .14, .18]);
      gk.cyl(.12, 12, [0, 1.4, 0], [.25, .27, .3]); gk.box(1.6, .5, .1, [4.4, .1, 1.12], [.3, .9, 1], 'glow'); gk.box(.5, .5, .5, [-1, -1.3, 0], RED, 'glow');
      const beam = gk.cyl(18, 9, [1.5, -10, 0], [1, .97, .85], 'glow', null, .6); beam.material.alpha = .16;
      cyl(.08, 9, [7, .05, 8], [1, .97, .85], 'glow').material.alpha = .25;
      box(1.2, 9, 1.2, [-14, 4.5, 2], [.2, .22, .28]); box(12, .6, .6, [-9, 9, 2], [.2, .22, .28], null, [0, 0, -.25]); box(1.4, 1, 1.6, [-3.5, 7.4, 2], [.1, .1, .12]); box(.4, .4, .4, [-3.5, 8.1, 2.9], RED, 'glow');
      box(7, 3.2, 2.6, [-16, 1.6, -6], [.85, .86, .9]); box(2.2, 2.6, 2.6, [-11.4, 1.3, -6], [.7, .72, .78]); cyl(.2, 2.4, [-16, 4.6, -6], [.6, .62, .7], null, [Math.PI / 2, 0, 0], 2.4);
      sign(6.6, 1.4, [-16, 2, -7.35], (g, w, h) => { g.fillStyle = '#c4102a'; g.fillRect(0, 0, w, h); neon(g, 'ACCORD LIVE', w / 2, h / 2, 46, '#ffffff'); });
      sign(3, 1, [-3.5, 9.3, 2], (g, w, h) => { g.fillStyle = '#000'; g.fillRect(0, 0, w, h); neon(g, '● ON AIR', w / 2, h / 2, 34, '#ff3040'); }); return { h: 20, w: 40 }; },
    /* SUGARFALL: the Comfort Belt. A row of rented pastel houses at 4 pm, a picket fence, the laugh-track tower and a billboard that never changes. */
    comfort(B, scene, R) { const { mat, box, cyl, sign, neon } = kit(B, scene, R); const P = [[1, .72, .82], [.72, .9, 1], [.8, 1, .8], [1, .92, .66], [.88, .78, 1]];
      for (let i = 0; i < 5; i++) { const x = -22 + i * 9, c = P[i]; box(7, 4.5, 6, [x, 2.25, 6], c); cyl(7.4, 6.4, [x, 5.6, 6], [c[0] * .7, c[1] * .55, c[2] * .65], null, [0, 0, Math.PI / 2], 0, 3);
        box(1.2, 2, .1, [x, 1, 2.95], [.45, .3, .25]); box(1.6, 1.2, .1, [x - 2.2, 2.6, 2.95], [1, .95, .7], 'glow'); box(1.6, 1.2, .1, [x + 2.2, 2.6, 2.95], [1, .95, .7], 'glow'); }
      for (let i = 0; i < 46; i++) box(.18, 1, .08, [-26 + i, .5, 1.6], [1, 1, 1]); box(46, .12, .08, [-3.5, .8, 1.6], [1, 1, 1]);
      for (const x of [-27, 20]) { cyl(4, .3, [x, 2, -1], [1, 1, 1]); const pop = B.MeshBuilder.CreateSphere('pop', { diameter: 2.6, segments: 16 }, scene); pop.parent = R; pop.position.set(x, 4.8, -1); pop.material = mat([1, .4, .7], 'glow'); }
      box(1, 14, 1, [26, 7, 4], [.85, .86, .9]); for (const y of [10, 12]) box(3, 2, 2, [26, y, 3.4], [.2, .2, .24]); sign(5, 1.6, [26, 14.6, 3.3], (g, w, h) => { g.fillStyle = '#300'; g.fillRect(0, 0, w, h); neon(g, 'APPLAUSE', w / 2, h / 2, 50, '#ff3a3a'); });
      box(16, 7, .4, [-6, 12, 9], [.2, .2, .26]); for (const x of [-12, 0]) box(.6, 9, .6, [x, 4.5, 9.4], [.5, .5, .55]);
      sign(15.4, 6.4, [-6, 12, 8.75], (g, w, h) => { const gr = g.createLinearGradient(0, 0, w, h); gr.addColorStop(0, '#ff9ed2'); gr.addColorStop(1, '#9ee8ff'); g.fillStyle = gr; g.fillRect(0, 0, w, h); g.fillStyle = '#4a1050'; g.textAlign = 'center'; g.font = '900 120px Arial Black, sans-serif'; g.fillText('TODAY', w / 2, h * .48); g.font = '700 54px Arial, sans-serif'; g.fillText('AGAIN. AND IT’S LOVELY.', w / 2, h * .8); });
      return { h: 16, w: 50 }; },
    /* THE UNDERTOW: Warden Pell's checkpoint at the tunnel mouth. Toll booths, striped barriers, a scanner gate, a tariff board priced per metre. */
    checkpoint(B, scene, R) { const { box, sign, neon } = kit(B, scene, R); const CON = [.22, .24, .3], RED = [1, .12, .15], AMB = [1, .7, .1];
      box(44, 20, 3, [0, 10, 26], CON); box(20, 14, 3.4, [0, 7, 25.8], [.02, .02, .04]); box(20.6, .4, .4, [0, 14.2, 24], AMB, 'glow');
      for (let i = 0; i < 9; i++) box(.3, 14, .2, [-10 + i * 2.5, 7, 24.1], [.08, .08, .1]);
      for (const x of [-6, 0, 6]) { box(2.2, 3.2, 3, [x, 1.6, 8], [.3, .32, .4]); box(2, 1, .1, [x, 2.4, 6.45], [.6, .9, 1], 'glow'); box(.4, .4, .4, [x, 3.5, 8], RED, 'glow');
        for (let k = 0; k < 6; k++) box(.7, .35, .35, [x + 1.6 + k * .7, 1.1, 6.2], k % 2 ? [1, 1, 1] : RED); }
      box(22, .6, .6, [0, 8, 6], [.3, .32, .4]); for (const x of [-11, 11]) box(.6, 8, .6, [x, 4, 6], [.3, .32, .4]); box(21, .12, .12, [0, 7.6, 5.7], RED, 'glow');
      sign(14, 3, [0, 10.4, 5.6], (g, w, h) => { g.fillStyle = '#0a0000'; g.fillRect(0, 0, w, h); neon(g, 'CHECKPOINT 7', w / 2, h * .36, 62, '#ff2a2a'); neon(g, 'TOLL: 0.4 CR PER METRE · NO RETURNS', w / 2, h * .76, 30, '#ffb020'); });
      box(3, 12, 3, [-16, 6, 12], CON); box(4.4, 2.4, 4.4, [-16, 13, 12], [.1, .1, .14]); box(4, 1, .1, [-16, 13.2, 9.75], [1, .3, .2], 'glow'); return { h: 20, w: 44 }; },
    /* NEON ACCORD: Vance's studio. A stage arch of light bars, two giant screens, bleachers on both sides like an arena, follow-spots on the road. */
    studio(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R); const PINK = [1, .2, .7], CYAN = [.2, .95, 1], SEAT = [.12, .08, .2];
      for (let i = 0; i < 7; i++) { const r = 16 + i * 1.2, a = new B.TransformNode('arch', scene); a.parent = R; a.position.set(0, 0, 18 + i * 2.5); const k2 = kit(B, scene, a), c = i % 2 ? PINK : CYAN; k2.box(.5, r, .5, [-r / 2 - 2, r / 2, 0], c, 'glow'); k2.box(.5, r, .5, [r / 2 + 2, r / 2, 0], c, 'glow'); k2.box(r + 4.5, .5, .5, [0, r, 0], c, 'glow'); }
      for (const s of [-1, 1]) { for (let k = 0; k < 7; k++) box(6, 1.4, 40, [s * (14 + k * 2.2), .7 + k * 1.4, 10], SEAT);
        for (let k = 0; k < 7; k++) for (let j = 0; j < 14; j++) box(.5, .7, .5, [s * (14 + k * 2.2) + ((j * 7 + k * 3) % 5 - 2) * .6, 1.9 + k * 1.4, -8 + j * 2.8], [.2 + ((j + k) % 3) * .15, .2, .55], 'glow');
        box(12, 7, .4, [s * 18, 22, 24], [.02, .02, .05]);
        sign(11.6, 6.6, [s * 18, 22, 23.75], (g, w, h) => { const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#2a0040'); gr.addColorStop(1, '#ff2a9d'); g.fillStyle = gr; g.fillRect(0, 0, w, h); neon(g, s < 0 ? 'ACCORD LIVE' : 'WILL HE CRASH?', w / 2, h * .42, 70, '#ffffff'); neon(g, s < 0 ? 'THE HUNT · LIVE' : 'VOTE NOW · 92% YES', w / 2, h * .76, 40, '#5ff0ff'); }); }
      for (const x of [-5, 5]) cyl(.08, 7, [x, .06, 2], [1, 1, .9], 'glow').material.alpha = .3;
      sign(10, 2.4, [0, 26, 17.6], (g, w, h) => { g.fillStyle = '#000'; g.fillRect(0, 0, w, h); neon(g, '● ON AIR', w / 2, h / 2, 80, '#ff3040'); }); return { h: 30, w: 60 }; },
    /* COLD RACK: Free Signal. Mast Hill's relay masts in rows, and WREN's pirate van on the ridge throwing an unfiltered beam into the sky. */
    signal(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R); const MAST = [.3, .5, .4], G = [.2, 1, .45];
      cyl(18, 90, [0, -6, 40], [.04, .12, .06], null, null, 60); for (let i = 0; i < 9; i++) { const x = -32 + i * 8, z = 26 + (i % 3) * 8, h = 14 + (i % 4) * 3, y = 2.5 + (i % 3) * 1.2; cyl(h, .5, [x, y + h / 2, z], MAST); for (let k = 1; k < 4; k++) cyl(.12, 2.2 - k * .4, [x, y + h * k / 4, z], G, 'glow'); box(.5, .5, .5, [x, y + h + .3, z], [1, .2, .2], 'glow'); }
      const V = new B.TransformNode('van', scene); V.parent = R; V.position.set(9, 0, 6); V.rotation.y = -.5; const vk = kit(B, scene, V); vk.box(5, 2.4, 2.4, [0, 1.6, 0], [.42, .46, .5]); vk.box(1.6, 1.8, 2.3, [3.1, 1.3, 0], [.36, .4, .44]); vk.box(5.02, .3, 2.42, [0, 1.2, 0], [.2, 1, .6], 'glow'); for (const [x, z] of [[1.6, 1.15], [-1.6, 1.15], [1.6, -1.15], [-1.6, -1.15]]) vk.cyl(.3, .8, [x, .4, z], [.05, .05, .06], null, [Math.PI / 2, 0, 0]);
      vk.cyl(3, .15, [-1, 4.3, 0], [.6, .6, .65]); vk.cyl(.1, 2.2, [-1, 5.8, 0], [.2, 1, .8], 'glow', [.6, 0, 0]); const bm = vk.cyl(60, 1.2, [-1, 35, 0], [.3, 1, .85], 'glow', null, null, 8); bm.material.alpha = .35;
      vk.box(1.6, .6, .05, [3.92, 1.6, 0], [.3, 1, .8], 'glow', [0, Math.PI / 2, 0]);
      sign(7, 1.6, [9, 7.6, 6], (g, w, h) => { g.fillStyle = 'rgba(0,10,6,.8)'; g.fillRect(0, 0, w, h); neon(g, 'FREE SIGNAL · 30 S', w / 2, h / 2, 52, '#3affb5'); }, [0, -.5, 0]); return { h: 40, w: 70 }; },
    /* THE TOMB: Ghost Road. Obelisks lining a road that only shows under a lens, and a convoy of deprecated models driving it as ghosts. */
    ghost(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R); const STONE = [.75, .58, .3], LAPIS = [.2, .4, 1], GH = [.4, 1, 1];
      for (let i = 0; i < 6; i++) for (const s of [-1, 1]) { const z = -6 + i * 9, x = s * 9; box(1.6, 9, 1.6, [x, 4.5, z], STONE); cyl(1.6, 2.2, [x, 9.8, z], STONE, null, [0, Math.PI / 4, 0], 0, 4); box(1.7, .3, 1.7, [x, 3, z], LAPIS, 'glow'); }
      box(7, .04, 60, [0, .05, 18], GH, 'glow', null, .25); for (const s of [-1, 1]) box(.15, .06, 60, [s * 3.5, .08, 18], GH, 'glow');
      for (let i = 0; i < 4; i++) { const C = new B.TransformNode('gc', scene); C.parent = R; C.position.set((i % 2 ? 1.6 : -1.6), 0, 4 + i * 8); const ck = kit(B, scene, C); ck.box(2, 1, 4.2, [0, .8, 0], GH, 'glow', null, .28); ck.box(1.8, .8, 2.2, [0, 1.6, -.3], GH, 'glow', null, .2); ck.box(1.9, .12, .12, [0, .8, -2.12], [1, 1, 1], 'glow'); }
      cyl(30, 40, [0, 15, 70], STONE, null, [0, Math.PI / 4, 0], 0, 4); box(9, 9, 1, [0, 4.5, 56], [.05, .03, .02]); sign(10, 2, [0, 10.5, 55.4], (g, w, h) => { g.fillStyle = 'rgba(20,10,0,.6)'; g.fillRect(0, 0, w, h); neon(g, 'DEPRECATED · DO NOT RESTORE', w / 2, h / 2, 40, '#ffd27a'); }); return { h: 30, w: 40 }; },
    /* THE OPEN CHANNEL: the Brood Cathedral. Spires, a rose window in every colour, and the roadside shrine where the colours settle. */
    cathedral(B, scene, R) { const { box, cyl, sign, neon } = kit(B, scene, R); const ST = [.18, .08, .28];
      box(40, 26, 4, [0, 13, 34], ST); for (const x of [-18, -9, 9, 18]) { box(4, 40, 4, [x, 20, 33], ST); cyl(14, 5, [x, 47, 33], ST, null, null, 0, 4); box(.6, 16, .2, [x, 22, 30.9], [1, .3, .9], 'glow'); }
      sign(18, 18, [0, 18, 31.8], (g, w, h) => { const cx = w / 2, cy = h / 2, R0 = w * .48; for (let i = 0; i < 24; i++) { g.beginPath(); g.moveTo(cx, cy); g.arc(cx, cy, R0, i / 24 * 6.283, (i + 1) / 24 * 6.283); g.closePath(); g.fillStyle = `hsl(${i * 15},100%,${55 + (i % 2) * 10}%)`; g.fill(); }
        g.lineWidth = 8; g.strokeStyle = '#140820'; for (let i = 0; i < 24; i++) { g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx + Math.cos(i / 24 * 6.283) * R0, cy + Math.sin(i / 24 * 6.283) * R0); g.stroke(); } for (const r of [.25, .55, .8]) { g.beginPath(); g.arc(cx, cy, R0 * r, 0, 7); g.stroke(); } });
      box(10, 14, 1, [0, 7, 31.7], [.02, .01, .03]); box(10.4, .4, .4, [0, 14.2, 31.4], [1, .85, .3], 'glow');
      box(3, 1.4, 3, [-11, .7, 2], [.9, .88, .8]); cyl(.6, .8, [-11, 1.7, 2], [1, .9, .5], 'glow'); for (let i = 0; i < 8; i++) cyl(.6, .25, [-11 + Math.cos(i) * 2.2, .3, 2 + Math.sin(i) * 2.2], [1, .8, .4], 'glow');
      sign(5, 1.2, [-11, 3.4, 2], (g, w, h) => { g.fillStyle = 'rgba(0,0,0,.6)'; g.fillRect(0, 0, w, h); neon(g, 'THE COLOURS SETTLE HERE', w / 2, h / 2, 26, '#ffe8a0'); }); return { h: 50, w: 50 }; },
  };
  window.AGSETS = { build: (B, scene, name) => { const R = new B.TransformNode('set_' + name, scene); if (!SETS[name]) return null; R.info = SETS[name](B, scene, R); return R; }, list: Object.keys(SETS) };
})();
