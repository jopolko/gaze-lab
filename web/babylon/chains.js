/* SET PIECES ("chains"): the 3D Sonic part of the game. A set piece is a run of pieces that hand you on to each other: a boost pad onto a rail, the
   rail's end into a ramp, the ramp into a ring arc, the arc onto a corkscrew, and so on. Once you line up with the first piece the set carries you
   (positions are scripted, so pieces always connect); you steer in the air to grab side crystals and, on the harder ones, to line up a catch.

   Some pieces are GATED: a branch you can see but only reach with something else (Air Rights, a magnet, your gear, RUSH, a lens, or speed).
   Without it you take the plain branch, the gated target stays where it is, and it becomes a LOOSE END. Loose ends come back: a later set in this
   level (or the next) repeats that piece with the thing it needs placed on the road before it (SECOND CHANCE). Clearing it pays the debt.
   Loose ends are kept in localStorage (dl_loose), so they follow you from level to level.

   createSets(d) takes the game's own pieces (see index.html, where it is created). Everything here is plain Babylon meshes, built a section ahead
   and thrown away behind you. */
export function createSets(d) {
  const { B, scene, PH } = d, TAU = Math.PI * 2;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v)), lerp = (a, b, t) => a + (b - a) * t;
  const gnd = (x, z) => { const g = d.th(x, z); return Number.isFinite(g) ? g : PH.y; };
  const SETS = [], ST = { A: null, loose: [], done: 0, full: 0, paid: 0, n: 0, err: 0, echoes: 0, boosts: [], charges: [] };
  try { ST.loose = (JSON.parse(localStorage.getItem('dl_loose') || '[]') || []).slice(0, 6); } catch (e) { ST.loose = []; }
  const saveLoose = () => { try { localStorage.setItem('dl_loose', JSON.stringify(ST.loose.slice(0, 6))); } catch (e) { } };

  // ---------------------------------------------------------------- materials (no pink anywhere)
  const MT = {};
  const mat = (k, dif, em, alpha) => { if (MT[k]) return MT[k]; const m = new B.StandardMaterial('set_' + k, scene); m.diffuseColor = new B.Color3(dif[0], dif[1], dif[2]); m.emissiveColor = new B.Color3(em[0], em[1], em[2]); m.specularColor = new B.Color3(.7, .7, .7); m.backFaceCulling = false; if (alpha != null) m.alpha = alpha; return MT[k] = m; };
  const M = {
    chrome: () => mat('chrome', [.78, .82, .9], [.22, .25, .3]), gold: () => mat('gold', [1, .78, .3], [.55, .38, .08]), orange: () => mat('orange', [1, .45, .15], [.5, .18, .04]),
    post: () => mat('post', [.62, .66, .74], [.16, .18, .22]), cyan: () => mat('cyan', [.3, .9, 1], [.2, .75, .9]), pad: () => mat('pad', [1, .55, .1], [1, .45, .05]),
    spring: () => mat('spring', [.35, 1, .55], [.15, .7, .3]), ghost: () => mat('ghost', [.4, 1, .6], [.25, .9, .5], .16), wall: () => mat('wall', [1, .45, .2], [.7, .22, .05], .55),
    box: () => mat('box', [.85, .7, .25], [.35, .25, .05]), barrier: () => mat('barrier', [.3, .8, 1], [.3, .8, 1], .35),
    /* ART PASS phase 1 (2026-11-26): one look for all track furniture: a lit edge along every rail, lamps on lips and posts */
    lit: () => { const m = mat('lit', [0, 0, 0], [1.9, 1.95, 2.1]); m.disableLighting = true; return m; }, litGold: () => { const m = mat('litGold', [0, 0, 0], [2.4, 1.7, .5]); m.disableLighting = true; return m; }, litGreen: () => { const m = mat('litGreen', [0, 0, 0], [.5, 2.2, .9]); m.disableLighting = true; return m; },
  };

  // ---------------------------------------------------------------- what a gate needs (the words match the game's own names)
  const NEED = {
    WINGS: { txt: 'AIR RIGHTS', col: '#9fe8ff', has: () => PH.wings > 0 || d.BANK().wings > 0, spend: () => { if (PH.wings <= 0 && d.BANK().wings > 0) { d.bankSpend('wings'); PH.wings = 8; } } },
    MAGNET: { txt: 'MAGNET', col: '#c9a8ff', has: () => d.GEAR().id === 'pole' || d.BANK().magnet > 0 || PH.mult > 0, spend: () => { if (d.GEAR().id !== 'pole' && PH.mult <= 0 && d.BANK().magnet > 0) { d.bankSpend('magnet'); PH.mult = 8; } } },
    SHIELD: { txt: 'SHIELD', col: '#38e8ff', has: () => (d.GEAR().id === 'shield' && d.GEAR().sh > 0) || d.BANK().shield > 0, spend: () => { if (!(d.GEAR().id === 'shield' && d.GEAR().sh > 0)) d.bankSpend('shield'); } },
    BULL: { txt: 'BULL BAR or RUSH', col: '#ff9a3a', has: () => d.GEAR().id === 'bull' || d.DOP().on },
    ROCKETS: { txt: 'ROCKETS or RUSH', col: '#ffd23a', has: () => d.GEAR().id === 'rocket' || d.DOP().on },
    RUSH: { txt: 'RUSH', col: '#ffd23a', has: () => d.DOP().on },
    LENS: { txt: 'ANY LENS', col: '#7dff8a', has: () => d.LENS().t > 0 },
    SPEED: { txt: 'FULL SPEED', col: '#ff7a3a', has: (A) => !!A && A.v0 >= d.speedNeed() },
    AIM: { txt: 'AIM', col: '#ffffff', has: () => true },
  };

  // ---------------------------------------------------------------- world helpers: a set is laid out in road space (d metres along, u metres across, h metres up)
  const P = (S, dd, u, h) => { const z = S.z0 - dd, x = d.trailX(z) + u; return [x, gnd(x, z) + h, z]; };
  const V = (p) => new B.Vector3(p[0], p[1], p[2]);
  const own = (S, m) => { m.isPickable = false; S.meshes.push(m); return m; };
  function sign(S, txt, col, p, w) {
    const dt = new B.DynamicTexture('setSignT', { width: 512, height: 128 }, scene, true), c = dt.getContext();
    const draw = (have) => { c.clearRect(0, 0, 512, 128); c.fillStyle = 'rgba(8,12,20,.88)'; c.fillRect(0, 0, 512, 128); c.strokeStyle = have ? '#7dff8a' : col; c.lineWidth = 9; c.strokeRect(6, 6, 500, 116); c.fillStyle = have ? '#7dff8a' : col; let f = 60; c.font = 'bold ' + f + 'px Arial'; while (c.measureText(txt).width > 470 && f > 24) { f -= 4; c.font = 'bold ' + f + 'px Arial'; } c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText((have ? '✓ ' : '') + txt, 256, 66); dt.update(); };
    draw(false);
    const m = new B.StandardMaterial('setSignM', scene); m.diffuseTexture = dt; m.emissiveTexture = dt; m.disableLighting = true; m.backFaceCulling = false; m.fogEnabled = false;
    const pl = B.MeshBuilder.CreatePlane('setSign', { width: w || 11, height: (w || 11) / 4 }, scene); pl.material = m; pl.billboardMode = B.Mesh.BILLBOARDMODE_ALL; pl.position.set(p[0], p[1], p[2]); own(S, pl);
    S.extra.push(m, dt); return { pl, draw, have: null };
  }
  function tube(S, pts, r, mt) { if (pts.length < 2) return null; const m = B.MeshBuilder.CreateTube('setTube', { path: pts.map(V), radius: r, tessellation: 10, cap: B.Mesh.CAP_ALL }, scene); m.material = mt; return own(S, m); }
  function posts(S, pts, every) { const list = [], lamps = []; for (let i = 0; i < pts.length; i += every) { const p = pts[i], g = gnd(p[0], p[2]), hh = p[1] - g; if (hh < 1.4) continue; const c = B.MeshBuilder.CreateCylinder('setPost', { height: hh, diameter: .26, tessellation: 6 }, scene); c.position.set(p[0], g + hh / 2, p[2]); list.push(c); const lp = B.MeshBuilder.CreateSphere('setPostLamp', { diameter: .4, segments: 6 }, scene); lp.position.set(p[0], g + hh + .05, p[2]); lamps.push(lp); }
    if (!list.length) return; const mm = list.length > 1 ? B.Mesh.MergeMeshes(list, true) : list[0]; mm.material = M.post(); own(S, mm); const ml = lamps.length > 1 ? B.Mesh.MergeMeshes(lamps, true) : lamps[0]; ml.material = M.lit(); own(S, ml); }
  function ribbon(S, d0, d1, u, w, hf, mt) { const N = 18, pos = [], idx = [], uv = []; for (let i = 0; i <= N; i++) { const t = i / N, dd = lerp(d0, d1, t), h = hf(t); for (const s of [-w / 2, w / 2]) { const p = P(S, dd, u + s, h + .06); pos.push(p[0], p[1], p[2]); uv.push(s > 0 ? 1 : 0, t); } }
    for (let i = 0; i < N; i++) { const a = i * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); } const m = new B.Mesh('setDeck', scene), vd = new B.VertexData(), nr = []; vd.positions = pos; vd.indices = idx; vd.uvs = uv; B.VertexData.ComputeNormals(pos, idx, nr); vd.normals = nr; vd.applyToMesh(m); m.material = mt; return own(S, m); }
  function torus(S, p, dia, th, mt, facing) { const m = B.MeshBuilder.CreateTorus('setRing', { diameter: dia, thickness: th, tessellation: 28 }, scene); m.material = mt; m.position.set(p[0], p[1], p[2]); if (facing) m.rotation.x = Math.PI / 2; return own(S, m); }

  // ---------------------------------------------------------------- the pieces: each adds a segment (and its meshes) to a list, moving the cursor c = { d, u, h }
  function builder(S, L, c) {
    const b = {
      c, L,
      pad(u, len = 12) { c.u = u; const s = { t: 'ride', k: 'pad', d0: c.d, d1: c.d + len, u0: u, u1: u, h0: 0, h1: 0, boost: 1.1, w: 6 }; L.push(s);
        const a = P(S, c.d, u, .12), e = P(S, c.d + len, u, .12), m = B.MeshBuilder.CreateBox('setPad', { width: 5, height: .2, depth: len }, scene); m.position.set((a[0] + e[0]) / 2, (a[1] + e[1]) / 2, (a[2] + e[2]) / 2); m.lookAt(V(e)); m.material = M.pad(); own(S, m);
        for (let i = 0; i < 3; i++) { const q = P(S, c.d + len * (i + .5) / 3, u, .3), ch = B.MeshBuilder.CreateDisc('setChev', { radius: 1.5, tessellation: 3 }, scene); ch.rotation.x = Math.PI / 2; ch.rotation.y = Math.PI; ch.position.set(q[0], q[1], q[2]); ch.material = M.gold(); own(S, ch); }
        c.d += len; c.h = 0; return b; },
      kick(u, H = 5, len = 24) { c.u = u; const hf = (t) => H * t * t, s = { t: 'ride', k: 'kick', d0: c.d, d1: c.d + len, u0: u, u1: u, hf, w: 7 }; L.push(s);
        ribbon(S, c.d, c.d + len, u, 7, hf, M.gold());
        for (const sd of [-3.6, 3.6]) { const pts = []; for (let i = 0; i <= 12; i++) { const t = i / 12; pts.push(P(S, c.d + len * t, u + sd, hf(t) + .55)); } tube(S, pts, .16, M.orange()); }
        { const l = P(S, c.d + len, u, H + .3), bar = B.MeshBuilder.CreateBox('setLip', { width: 8, height: .4, depth: .5 }, scene); bar.position.set(l[0], l[1], l[2]); bar.material = M.orange(); own(S, bar); for (const sd of [-4.2, 4.2]) { const q = P(S, c.d + len, u + sd, H + .55), lp = B.MeshBuilder.CreateSphere('setLipLamp', { diameter: .7, segments: 8 }, scene); lp.position.set(q[0], q[1], q[2]); lp.material = M.litGold(); own(S, lp); } }
        c.d += len; c.h = H; return b; },
      spring(u) { c.u = u; const s = { t: 'ride', k: 'spring', d0: c.d, d1: c.d + 5, u0: u, u1: u, h0: 0, h1: 0, w: 6 }; L.push(s);
        const p = P(S, c.d + 2.5, u, 0), base = B.MeshBuilder.CreateCylinder('setSpring', { height: .5, diameter: 5.4, tessellation: 24 }, scene); base.position.set(p[0], p[1] + .25, p[2]); base.material = M.spring(); own(S, base);
        for (let i = 0; i < 3; i++) torus(S, [p[0], p[1] + .7 + i * .45, p[2]], 4.2 - i * .5, .22, M.chrome()); { const cap = B.MeshBuilder.CreateCylinder('setSpringCap', { height: .12, diameter: 2.6, tessellation: 24 }, scene); cap.position.set(p[0], p[1] + 1.75, p[2]); cap.material = M.litGreen(); own(S, cap); }
        c.d += 5; c.h = 0; c.nextH = 22; return b; },
      rail(len, u1, h0, h1, o = {}) { const s = { t: 'ride', k: 'rail', d0: c.d, d1: c.d + len, u0: c.u, u1: u1 ?? c.u, h0: h0 ?? c.h, h1: h1 ?? (h0 ?? c.h), boost: o.boost, pull: o.pull, ghost: o.ghost }; L.push(s);
        if (o.mesh !== false) { const pts = []; for (let i = 0; i <= Math.ceil(len / 3); i++) { const t = i / Math.ceil(len / 3); pts.push(P(S, c.d + len * t, lerp(s.u0, s.u1, t), lerp(s.h0, s.h1, t) - .55)); } const m = tube(S, pts, .32, o.ghost ? M.ghost() : (o.boost ? M.gold() : M.chrome())); if (o.ghost) S.ghosts.push(m); if (!o.ghost) { posts(S, pts, 7); tube(S, pts.map((q) => [q[0], q[1] + .3, q[2]]), .07, o.boost ? M.litGold() : M.lit()); } s.mesh = m; }
        c.d += len; c.u = s.u1; c.h = s.h1; return b; },
      helix(len, turns = 1.5, R = 5) { const s = { t: 'ride', k: 'helix', d0: c.d, d1: c.d + len, u0: c.u, u1: c.u, R, turns, hc: c.h + R }; L.push(s);
        const pts = [], N = Math.ceil(len / 1.4); for (let i = 0; i <= N; i++) { const t = i / N, a = turns * TAU * t; pts.push(P(S, c.d + len * t, c.u + R * Math.sin(a), s.hc - R * Math.cos(a) - .55)); } tube(S, pts, .3, M.cyan()); posts(S, pts.filter((q, i) => Math.cos(turns * TAU * i / N) > .9), 1);
        c.d += len; return b; },
      air(len, u1, h1, H = 6, o = {}) { const s = { t: 'air', d0: c.d, d1: c.d + len, u0: c.u, u1, h0: c.h, h1, H: Math.max(H, c.nextH || 0), tol: o.tol ?? null, free: h1 <= .01 || o.tol != null, rings: [] }; c.nextH = 0; L.push(s);
        if (o.gems) gems(S, s, o.gems, o.gemKind); if (o.rings) for (let i = 1; i <= o.rings; i++) { const t = i / (o.rings + 1), dd = lerp(s.d0, s.d1, t), q = P(S, dd, lerp(s.u0, s.u1, t), lerp(s.h0, s.h1, t) + 4 * s.H * t * (1 - t) + .6); s.rings.push({ d: dd, m: torus(S, q, 7, .5, M.gold(), true), got: false }); }
        if (o.tol != null) { const q = P(S, s.d1, u1, h1 + .2); s.catchM = torus(S, q, o.tol * 2 + 1, .25, M.cyan(), false); }
        c.d += len; c.u = u1; c.h = h1; return b; },
      land(len = 60, u, o = {}) { b.air(len, u ?? c.u, 0, o.H ?? 7, { gems: o.gems ?? 'line' }); L[L.length - 1].end = true; return b; },
      gate(need, yes, no, at) { const s = { t: 'gate', d0: c.d, d1: c.d, need, yes: [], no: [] }; L.push(s);
        const cy = { ...c }, cn = { ...c }, by = builder(S, s.yes, cy), bn = builder(S, s.no, cn); yes(by); no(bn);
        if (need !== 'FORK') { const tgt = s.yes.find((q) => q.t === 'ride') || s.yes[0], dd = tgt ? (tgt.d0 + tgt.d1) / 2 : c.d + 30, uu = tgt ? lerp(tgt.u0, tgt.u1 ?? tgt.u0, .5) : c.u, hh = tgt ? (tgt.t === 'air' ? lerp(tgt.h0, tgt.h1, .5) + tgt.H : (tgt.h0 ?? tgt.hc ?? 0)) : 6; s.sign = sign(S, NEED[need].txt, NEED[need].col, P(S, at ?? dd, uu, hh + 6)); }
        S.gated = true; c.d = Math.max(cy.d, cn.d); return b; },
    };
    return b;
  }
  /* crystals along a flight: on the line ('line'), a bonus bend off to one side you have to steer for ('side'), or a weave ('zig') */
  function gems(S, s, mode, kind) { const n = Math.max(4, Math.floor((s.d1 - s.d0) / 9)), side = S.side; s.gems = [];
    for (let i = 1; i < n; i++) { const t = i / n; let du = 0; if (mode === 'side') du = t > .3 && t < .75 ? 5.5 * side : 0; else if (mode === 'zig') du = (i % 2 ? 3.2 : -3.2); else if (mode === 'far') du = 12 * side;
      const dd = lerp(s.d0, s.d1, t), u = lerp(s.u0, s.u1, t) + du, h = lerp(s.h0, s.h1, t) + 4 * s.H * t * (1 - t), z = S.z0 - dd, x = d.trailX(z) + u;
      try { const o = d.solPut(kind || (du && mode !== 'zig' ? 'octa' : 'tetra'), x, z, h + .2); if (o) s.gems.push(o); } catch (e) { } } }

  // ---------------------------------------------------------------- the set pieces. Each is f(b, R, u): R is the set's dice, u its lane. "tier" is the first level index where it may appear.
  const LANE = [-6, 0, 6], pickU = (R) => LANE[Math.floor(R() * 3)], other = (R, u) => { const o = LANE.filter((q) => q !== u); return o[Math.floor(R() * o.length)]; };
  const CAT = {
    hop: { tier: 0, f(b, R, u) { b.kick(u, 5).air(80, u, 0, 10, { gems: 'line' }); b.L[b.L.length - 1].end = true; } },
    grind: { tier: 0, f(b, R, u) { b.pad(u).rail(48, u, .5, 1.6).land(60, u, { gems: R() < .5 ? 'zig' : 'line' }); } },
    spring: { tier: 0, f(b, R, u) { b.spring(u).air(84, u, 0, 22, { gems: 'line', gemKind: 'octa' }); b.L[b.L.length - 1].end = true; } },
    skygrind: { tier: 0, f(b, R, u) { const u2 = other(R, u); b.kick(u, 5).air(42, u2, 8, 6, { gems: 'line' }).rail(64, u2, 8, 6).land(64, u2, { gems: 'side' }); } },
    railhop: { tier: 1, f(b, R, u) { const u2 = other(R, u), u3 = other(R, u2); b.pad(u).rail(30, u, .5, 1.6).air(28, u2, 1.6, 5).rail(30, u2, 1.6).air(28, u3, 1.6, 5).rail(30, u3, 1.6).land(56, u3); } },
    corkscrew: { tier: 1, f(b, R, u) { b.kick(u, 6).air(36, u, 6, 6, { gems: 'line' }).helix(96, 1.5, 5.5).land(64, u, { gems: 'zig' }); } },
    pinball: { tier: 1, f(b, R, u) { b.spring(-6).air(40, 6, 0, 12, { gems: 'line' }).spring(6).air(40, 0, 0, 14, { gems: 'line' }).spring(0).air(80, 0, 0, 20, { gems: 'side', gemKind: 'octa' }); b.L[b.L.length - 1].end = true; } },
    ladder: { tier: 2, f(b, R, u) { b.kick(u, 4, 20).air(42, u, 0, 8, { tol: 3 }).kick(u, 6, 22).air(52, u, 0, 11, { tol: 3 }).kick(u, 8, 24).air(90, u, 0, 15, { gems: 'line', gemKind: 'octa' }); b.L[b.L.length - 1].end = true; } },
    rings: { tier: 0, f(b, R, u) { b.pad(u).kick(u, 6).air(130, u, 0, 15, { rings: 3, gems: 'line' }); b.L[b.L.length - 1].end = true; } },
    catcher: { tier: 2, f(b, R, u) { const u2 = other(R, u); b.kick(u, 6).air(48, u2, 7, 7, { tol: 2.6 }).rail(60, u2, 7, 5).land(60, u2, { gems: 'line' }); } },
    fork: { tier: 1, f(b, R, u) { b.pad(0).kick(0, 5).gate('FORK', (y) => y.air(40, -6, 6, 6).rail(60, -6, 6, 4).land(56, -6, { gems: 'line' }), (n) => n.air(110, 6, 0, 13, { gems: 'zig', rings: 2 })); } },
    // ---- gated: you can see the prize; it needs something
    speedtrap: { tier: 1, need: 'SPEED', f(b, R, u) { b.pad(u).pad(u).kick(u, 6).gate('SPEED', (y) => y.air(60, u, 15, 10).rail(70, u, 15, 10, { boost: 1.08 }).land(72, u, { gems: 'line' }), (n) => n.air(76, u, 0, 9, { gems: 'line' })); } },
    wingspan: { tier: 1, need: 'WINGS', f(b, R, u) { b.kick(u, 6).air(46, u, 11, 9).gate('WINGS', (y) => y.air(96, u, 20, 9, { gems: 'line', gemKind: 'octa' }).land(90, u, { H: 4 }), (n) => n.air(48, u, 0, 2)); } },
    magnetline: { tier: 2, need: 'MAGNET', f(b, R, u) { b.pad(u).gate('MAGNET', (y) => y.rail(76, u, .5, 1.6, { pull: true }).land(56, u), (n) => n.rail(76, u, .5, 1.6, { mesh: false }).land(56, u)); const g = b.L[b.L.length - 1]; const rs = g.yes[0]; const fake = { d0: rs.d0, d1: rs.d1, u0: u, u1: u, h0: .5, h1: 1.6, H: 0 }; gems(b.S, fake, 'far', 'octa'); g.magGems = fake.gems; } },
    bullwall: { tier: 3, need: 'BULL', f(b, R, u) { b.pad(u).gate('BULL', (y) => y.rail(80, u, .5, 4, { boost: 1.15 }).land(70, u, { gems: 'line' }), (n) => { n.L.push({ t: 'ride', k: 'stop', d0: n.c.d, d1: n.c.d + 4, u0: u, u1: u, h0: 0, h1: 0, stop: true }); }, b.c.d + 2); const g = b.L[b.L.length - 1]; const p = P(b.S, b.c.d - 0, u, 0); const w = B.MeshBuilder.CreateBox('setWall', { width: 7, height: 6, depth: 1 }, scene); const q = P(b.S, g.d0 + 2, u, 3); w.position.set(q[0], q[1], q[2]); w.material = M.wall(); own(b.S, w); g.wall = w; } },
    lockbox: { tier: 3, need: 'ROCKETS', f(b, R, u) { b.kick(u, 6).air(44, u, 10, 8).gate('ROCKETS', (y) => y.air(110, u, 0, 13, { rings: 2, gems: 'line', gemKind: 'octa' }), (n) => n.air(46, u, 0, 3)); const g = b.L[b.L.length - 1]; const q = P(b.S, g.d0 + 26, u, 15); const bx = B.MeshBuilder.CreateBox('setBox', { size: 3.4 }, scene); bx.position.set(q[0], q[1], q[2]); bx.material = M.box(); own(b.S, bx); g.box = bx; torus(b.S, q, 6, .3, M.gold(), true); } },
    ghostrail: { tier: 2, need: 'LENS', f(b, R, u) { b.kick(u, 5).air(40, u, 7, 7).gate('LENS', (y) => y.rail(72, u, 7, 7, { ghost: true }).land(62, u, { gems: 'side' }), (n) => n.air(44, u, 0, 2)); } },
    rushgate: { tier: 4, need: 'RUSH', f(b, R, u) { b.pad(u).gate('RUSH', (y) => y.kick(u, 7).air(150, u, 0, 20, { rings: 3, gems: 'line', gemKind: 'octa' }), (n) => n.kick(u, 4).air(60, u, 0, 6, { gems: 'line' })); const g = b.L[b.L.length - 1]; torus(b.S, P(b.S, g.d0 + 4, u, 5), 11, .7, M.gold(), true); } },
    shieldrun: { tier: 4, need: 'SHIELD', f(b, R, u) { b.kick(u, 5).air(40, u, 7, 7).gate('SHIELD', (y) => y.rail(64, u, 7, 4).land(56, u, { gems: 'zig' }), (n) => n.air(30, u, 0, 1)); const g = b.L[b.L.length - 1]; const bar = torus(b.S, P(b.S, g.d0 + 1, u, 7), 8, .45, M.barrier(), true); g.barrier = bar; } },
  };
  /* REMIX: a fresh chain from the same parts, so no two sets need be alike: an opener, two to four links, a landing */
  function remix(b, R, u) { const op = R(); if (op < .4) b.kick(u, 5); else if (op < .7) b.pad(u).rail(36, u, .5, 1.6); else b.spring(u);
    const n = 2 + Math.floor(R() * 3); for (let i = 0; i < n; i++) { const r = R(), u2 = other(R, b.c.u);
      if (r < .3) b.air(40, u2, 6, 6, { gems: 'line' }).rail(40 + Math.floor(R() * 30), u2, 6, 4 + R() * 3);
      else if (r < .5) b.air(36, b.c.u, 5, 6).helix(80, 1 + Math.floor(R() * 2) * .5 + .5, 5);
      else if (r < .75) b.air(44, u2, 0, 8, { gems: 'zig' }).kick(u2, 6);
      else b.air(44, u2, 0, 9, { gems: 'line' }).spring(u2); }
    b.land(70, b.c.u, { gems: R() < .5 ? 'side' : 'line' }); }

  // ---------------------------------------------------------------- building a set
  function build(id, z0, R, echo) {
    const S = { id, z0, segs: [], meshes: [], extra: [], ghosts: [], state: 'ready', side: R() < .5 ? -1 : 1, echo: echo || null, gated: false }; S.S = S;
    const u = pickU(R), b = builder(S, S.segs, { d: 0, u, h: 0 }); b.S = S;
    if (id === 'remix') remix(b, R, u); else CAT[id].f(b, R, u);
    const s0 = S.segs[0]; S.w = s0.w || 6; S.len = b.c.d;
    // the way in: three gold chevrons on the road in its lane
    for (let i = 1; i <= 3; i++) { const q = P(S, -i * 14, s0.u0, .25), ch = B.MeshBuilder.CreateDisc('setChev', { radius: 1.8, tessellation: 3 }, scene); ch.rotation.x = Math.PI / 2; ch.rotation.y = Math.PI; ch.position.set(q[0], q[1], q[2]); ch.material = M.gold(); own(S, ch); }
    if (echo) sign(S, 'SECOND CHANCE', '#ffd23a', P(S, -10, s0.u0, 7), 12);
    SETS.push(S); ST.n++; return S;
  }
  /* SECTION: called by the level script. Chooses a set (a loose end first, if there is one), builds it, and returns how much road it uses. */
  function section(z, T, lvIdx, R, forceId) {
    R = R || Math.random;
    if (forceId) { if (d.inTunZ(z, 200) || d.inTunZ(z - 500, 200)) return 120; const S = build(forceId === 'remix' || CAT[forceId] ? forceId : 'hop', z - 40, R, null); return S.len + 120; }
    if (d.inTunZ(z, 200) || d.inTunZ(z - 500, 200)) return 120;
    let echo = null; if (ST.loose.length && ST.echoes < 2 && R() < .85) { echo = ST.loose[0]; ST.echoes++; }
    let id;
    if (echo) id = echo.id;
    else { const pool = Object.keys(CAT).filter((k) => CAT[k].tier <= lvIdx); const gated = pool.filter((k) => CAT[k].need), plain = pool.filter((k) => !CAT[k].need);
      const slot = ST.n % 3; id = slot === 1 && gated.length ? gated[Math.floor(R() * gated.length)] : (slot === 2 && lvIdx >= 2 && R() < .6 ? 'remix' : plain[Math.floor(R() * plain.length)]); }
    if (id !== 'remix' && !CAT[id]) id = 'hop';
    let pre = 0; const z0 = z - 40;
    // the thing a loose end needed, on the road before its second chance (or, now and then, before a gated set the first time)
    const need = echo ? echo.need : (CAT[id] && CAT[id].need);
    if (need && (echo || R() < .45)) pre = provide(need, z0 + 160, R);
    const S = build(id, z0, R, echo); return S.len + 120 + pre * 0;
  }
  function provide(need, z, R, side) { side = side || ((R || Math.random)() < .5 ? -1 : 1); const x = d.trailX(z) + side * 9;
    try {
      if (need === 'WINGS') d.makeBuff('donut', x, z); else if (need === 'MAGNET') d.makeBuff('mult', x, z); else if (need === 'SHIELD') d.makeBuff('shield', x, z);
      else if (need === 'LENS') { const o = d.lensPut(d.lensKind(), z); if (o && o.m) { o.x += side * 9; o.m.position.x += side * 9; } }
      else if (need === 'SPEED') { const S = { z0: z, meshes: [], extra: [], segs: [], ghosts: [], state: 'prop', len: 40 }; SETS.push(S); for (let i = 0; i < 3; i++) { const zz = z + 70 - i * 35, xx = d.trailX(zz) + side * 9, q = [xx, gnd(xx, zz) + .12, zz], m = B.MeshBuilder.CreateBox('setPad', { width: 6, height: .2, depth: 12 }, scene); m.position.set(q[0], q[1], q[2]); m.material = M.pad(); own(S, m); ST.boosts.push({ z: zz, x: side * 9 }); } }
      else if (need === 'BULL' || need === 'ROCKETS' || need === 'RUSH') { const n = 12; for (let i = 0; i < n; i++) d.solPut('octa', d.trailX(z + 40 - i * 9) + side * 9 + Math.sin(i * .7) * 2, z + 40 - i * 9, 1.7); ST.charges.push({ z: z - 70, x: side * 9 }); }
    } catch (e) { console.error('sets provide', need, e); } return 0; }

  // ---------------------------------------------------------------- running a set
  function at(S, sg, dd, off) { const s = clamp((dd - sg.d0) / Math.max(.01, sg.d1 - sg.d0), 0, 1); let u, h;
    if (sg.t === 'air') { const env = sg.free ? 1 : (s < .8 ? 1 : (1 - s) / .2); u = lerp(sg.u0, sg.u1, s) + off * env; h = lerp(sg.h0, sg.h1, s) + 4 * sg.H * s * (1 - s); }
    else if (sg.k === 'helix') { const a = sg.turns * TAU * s; u = sg.u0 + sg.R * Math.sin(a) + off * .2; h = sg.hc - sg.R * Math.cos(a); }
    else { u = lerp(sg.u0, sg.u1, s) + off; h = sg.hf ? sg.hf(s) : lerp(sg.h0, sg.h1, s); }
    return P(S, dd, u, h); }
  function tryStart() {
    for (const S of SETS) { if (S.state !== 'ready') continue; const s0 = S.segs[0], ze = S.z0 - s0.d0;
      if (PH.z < ze - 22) { S.state = 'skipped'; continue; }
      if (PH.z <= ze + 1 && PH.z >= ze - 22) { const ex = d.trailX(PH.z) + s0.u0, g = gnd(PH.x, PH.z);
        if (Math.abs(PH.x - ex) < S.w / 2 + .6 && PH.y < g + 7 && !PH.rail && !PH.ram && !d.busy()) start(S); } } }
  function start(S) { const v = clamp(Math.hypot(PH.vx, PH.vz), 24 * d.SPK(), 50 * d.SPK()), s0 = S.segs[0];
    ST.A = { S, i: 0, d: Math.max(s0.d0, S.z0 - PH.z), v, v0: v, off: clamp(PH.x - (d.trailX(PH.z) + s0.u0), -3, 3), prev: null, combo: 0, full: true, sAvg: 0 }; S.state = 'live'; PH.set = ST.A;
    d.sfx('blip'); d.fx('orb', [PH.x, PH.y + 1, PH.z]); }
  function piece(A, sg) { A.combo++; d.chainHit(); if (A.combo % 3 === 0) d.fx('cheer', [PH.x, PH.y + 2, PH.z]); else d.fx('orb', [PH.x, PH.y + 1, PH.z]); d.sfx(A.combo % 2 ? 'blip' : 'orb'); d.dopAdd('pad', .03); }
  function release(A, landed) { const S = A.S; PH.set = null; ST.A = null; S.state = 'done';
    if (landed) { PH.y = gnd(PH.x, PH.z); PH.vy = 0; PH.grounded = true; PH.crest = false; } else { PH.grounded = false; PH.crest = true; PH.air_t = 0; PH.vy = Math.min(PH.vy, 2); }
    PH.gh_prev = gnd(PH.x, PH.z); }
  function finish(A) { const S = A.S; ST.done++; if (S.gated && A.full) ST.full++;
    PH.score += 300 * A.combo; d.dopAdd('mol', .05); d.fx('cheer', [PH.x, PH.y + 2, PH.z]); d.shake(.25);
    const last = S.segs[S.segs.length - 1], landed = last && (last.end || (last.t === 'ride' && !last.stop));
    release(A, !!(last && last.end));
    if (!landed || last.end) { try { d.raidRam(); } catch (e) { } } }          /* a set that ends with a raider in front of you sends you into it */
  function miss(A, need, gateSeg) { const S = A.S; A.full = false;
    if (need !== 'FORK') { const key = S.id + ':' + need; if (!ST.loose.some((q) => q.id === S.id && q.need === need)) { ST.loose.push({ id: S.id, need, w: d.world() }); if (ST.loose.length > 6) ST.loose.shift(); saveLoose(); } }
    if (gateSeg && gateSeg.sign) { gateSeg.sign.draw(false); } }
  function paid(S, need) { const i = ST.loose.findIndex((q) => q.id === S.id && q.need === need); if (i < 0) return; ST.loose.splice(i, 1); saveLoose(); ST.paid++; PH.score += 2500; d.dopAdd('mol', .2); d.fx('cheer', [PH.x, PH.y + 2, PH.z]); d.fx('cheer', [PH.x + 3, PH.y + 3, PH.z - 3]); d.sfx('levelup'); d.shake(.4); }
  function gateNow(A, g) { const S = A.S; let ok;
    if (g.need === 'FORK') ok = A.sAvg < 0;
    else { const N = NEED[g.need]; ok = !!N.has(A); if (ok && N.spend) N.spend(); }
    const br = ok ? g.yes : g.no; S.segs.splice(A.i, 1, ...br);
    if (g.need === 'FORK') return;
    if (ok) { d.sfx('powerup'); d.fx('blast', [PH.x, PH.y + 1, PH.z]); if (S.echo || ST.loose.some((q) => q.id === S.id && q.need === g.need)) paid(S, g.need);
      if (g.wall) { d.fx('blast', [g.wall.position.x, g.wall.position.y, g.wall.position.z]); g.wall.setEnabled(false); d.shake(.5); }
      if (g.box) { const p = g.box.position; d.fx('blast', [p.x, p.y, p.z]); d.fx('cheer', [p.x, p.y, p.z]); g.box.setEnabled(false); d.rocketFx && d.rocketFx(p); }
      if (g.barrier) g.barrier.setEnabled(false);
      if (g.magGems) A.pull = g.magGems; }
    else { miss(A, g.need, g); if (g.barrier || g.wall) d.shake(.35); } }
  function endSeg(A, sg) { const S = A.S;
    if (sg.t === 'air' && sg.tol != null) { if (Math.abs(A.off) > sg.tol) { miss(A, 'AIM'); release(A, false); return true; } if (sg.catchM) sg.catchM.setEnabled(false); piece(A, sg); }
    else if (sg.t === 'ride') piece(A, sg);
    if (sg.boost) A.v = Math.min(A.v * sg.boost, 66 * d.SPK());
    if (sg.stop) { PH.vx *= .55; PH.vz *= .55; release(A, true); d.shake(.3); return true; }
    A.i++;
    while (S.segs[A.i] && S.segs[A.i].t === 'gate') gateNow(A, S.segs[A.i]);
    if (!S.segs[A.i]) { finish(A); return true; }
    return false; }
  function step(dt, sIn) {
    try {
      tidy();
      const A = ST.A; if (!A) { tryStart(); return; }
      if (dt <= 0) return; const S = A.S; let sg = S.segs[A.i]; if (!sg) { finish(A); return; }
      A.d += A.v * dt; A.sAvg += (sIn - A.sAvg) * Math.min(1, dt * 4);
      if (sg.t === 'air') A.off = clamp(A.off + sIn * 12 * dt, -8, 8); else A.off *= Math.exp(-4 * dt);
      for (const r of (sg.rings || [])) if (!r.got && A.d >= r.d) { r.got = true; A.v = Math.min(A.v * 1.06, 66 * d.SPK()); r.m.setEnabled(false); d.fx('cheer', [PH.x, PH.y + 1, PH.z]); d.sfx('powerup'); PH.score += 200; }
      while (sg && A.d >= sg.d1) { if (endSeg(A, sg)) return; sg = S.segs[A.i]; }
      if (!sg) return;
      const p = at(S, sg, A.d, A.off);
      if (A.prev && dt > 1e-4) { PH.vx = (p[0] - A.prev[0]) / dt; PH.vy = (p[1] - A.prev[1]) / dt; PH.vz = (p[2] - A.prev[2]) / dt; } else { PH.vx = 0; PH.vz = -A.v; PH.vy = 0; }
      const sp = Math.hypot(PH.vx, PH.vz); if (sp > A.v * 2.5) { PH.vx *= A.v / sp; PH.vz *= A.v / sp; }
      PH.x = p[0]; PH.y = p[1]; PH.z = p[2]; PH.heading = Math.atan2(PH.vx, -PH.vz) || 0; PH.grounded = true; PH.air_t = 0; PH.crest = false; PH.rail = null; PH.gh_prev = gnd(p[0], p[2]); PH.boost_t = Math.max(PH.boost_t || 0, .3);
      A.prev = p;
      if (A.pull) for (const o of A.pull) { if (o.got || !o.m) continue; o.x += (PH.x - o.x) * Math.min(1, dt * 4); o.y += (PH.y - o.y) * Math.min(1, dt * 4); o.z += (PH.z - 4 - o.z) * Math.min(1, dt * 4); o.m.position.set(o.x, o.y, o.z); }
    } catch (e) { if (!ST.err) { ST.err = 1; console.error('sets', e); } abort(); } }
  function abort() { const A = ST.A; if (!A) return; release(A, false); }
  /* signs show a tick when you have what they need; ghost rails firm up under a lens; everything well behind you is thrown away */
  let tT = 0;
  function tidy() { tT++; const lensOn = d.LENS().t > 0;
    for (const S of SETS) { if (S.state === 'gone') continue;
      if (S.ghosts.length) for (const m of S.ghosts) m.material.alpha = lensOn ? .85 : .16;
      if (tT % 20 === 0 && S.state === 'ready' && PH.z - S.z0 < 450) for (const sg of S.segs) if (sg.t === 'gate' && sg.sign && sg.need !== 'FORK') { const h = !!NEED[sg.need].has(sg.need === 'SPEED' ? { v0: Math.hypot(PH.vx, PH.vz) } : null); if (h !== sg.sign.have) { sg.sign.have = h; sg.sign.draw(h); } }
      if (S.state !== 'live' && PH.z < S.z0 - (S.len || 0) - 120) { for (const m of S.meshes) try { m.dispose(); } catch (e) { } for (const x of S.extra) try { x.dispose(); } catch (e) { } S.meshes.length = 0; S.state = 'gone'; } }
    for (let i = ST.boosts.length - 1; i >= 0; i--) if (PH.z < ST.boosts[i].z) { const bo = ST.boosts.splice(i, 1)[0]; if (Math.abs(PH.x - d.trailX(bo.z) - bo.x) < 4.5 && !ST.A) { PH.vx *= 1.18; PH.vz *= 1.18; PH.boost_t = Math.max(PH.boost_t || 0, 2.4); d.sfx('powerup'); d.fx('orb', [PH.x, PH.y + 1, PH.z]); } }
    for (let i = ST.charges.length - 1; i >= 0; i--) if (PH.z < ST.charges[i].z) { const ch = ST.charges.splice(i, 1)[0]; if (Math.abs(PH.x - d.trailX(ch.z) - ch.x) < 8) { const D = d.DOP(); if (!D.on) { D.v = Math.max(D.v, .97); d.dopAdd('mol'); } } } }          /* (a RUSH charge counts only if you took its line of crystals) */
  /* THE FORK (the director's lock-and-key): two keys, one each side of the road, each under a sign naming it. You can only take one. */
  function fork(z, a, b) { const S = { z0: z, meshes: [], extra: [], segs: [], ghosts: [], state: 'prop', len: 60, fork: [a, b] }; SETS.push(S);
    for (const [need, side] of [[a, -1], [b, 1]]) { provide(need, z, null, side); const x = d.trailX(z) + side * 9; sign(S, (side < 0 ? '◀ ' : '') + NEED[need].txt + (side > 0 ? ' ▶' : ''), NEED[need].col, [x, gnd(x, z) + 7.5, z + 8], 10); }
    return 140; }
  function key(z, need, side) { const S = { z0: z, meshes: [], extra: [], segs: [], ghosts: [], state: 'prop', len: 60, keyNeed: need }; SETS.push(S); provide(need, z, null, side); const x = d.trailX(z) + side * 9; sign(S, NEED[need].txt, NEED[need].col, [x, gnd(x, z) + 7.5, z + 8], 9); return 120; }
  const summary = () => ({ done: ST.done, full: ST.full, paid: ST.paid, loose: ST.loose.map((q) => NEED[q.need] ? NEED[q.need].txt : q.need) });
  return { section, fork, key, step, abort, summary, build, CAT, ST, SETS, NEED, active: () => !!ST.A };
}
