// THE REGISTRY, IN THE GAME (owner 2026-11-27): every world fields its own machines (two regulars and a boss), each with a niche, and each world teaches one
// answer: Desert RAM, Alps STOMP, Candy SIDESWIPE, Tunnel BAIT, Synthwave ROCKETS, Matrix NODE, Egypt combos, Trip everything. Everything can be beaten by
// steering alone; Rocket Racks on the driving line fire seekers that pick their own targets. Gentle stakes: machines cost you speed, a shove or your boost,
// never a stop. No HUD: every warning is in the world (a lit tail, a moving ridge, a red grid, glowing eyes).
//   createBeasts(d).step(dt, live) every frame. d: { B, scene, PH, th, trailX, inTunZ, tunnel(), world, tier, END, cam(), audio(), fx(kind, p), shake(v),
//   chain(), score(n), look(kind), emp(), sfx(k) }

export function createBeasts(d) {
  const { B, scene, PH } = d, clamp = (v, a, b) => Math.max(a, Math.min(b, v)), rnd = (a, b) => a + Math.random() * (b - a), pick = (a) => a[Math.floor(Math.random() * a.length)];
  const T = clamp(d.tier | 0, 0, 7), C3 = (a, k = 1) => new B.Color3(a[0] * k, a[1] * k, a[2] * k);
  const ground = (x, z) => { try { const g = d.th(x, z); return Number.isFinite(g) ? g : PH.y; } catch (e) { return PH.y; } };
  const speed = () => Math.hypot(PH.vx, PH.vz);

  // ---------------------------------------------------------------- materials: dark chrome bodies, each world's own glow
  const PAL = {
    desert: { a: [1, .69, .13], b: [.18, .84, .78], shell: [.11, .09, .07] }, alpine: { a: [.75, .91, 1], b: [.29, .66, 1], shell: [.1, .13, .18] },
    candy: { a: [.79, .66, 1], b: [.49, 1, .85], shell: [.16, .12, .24] }, tunnel: { a: [.22, .91, 1], b: [.62, .48, 1], shell: [.06, .09, .2] },
    synthwave: { a: [.69, .48, 1], b: [.22, .91, 1], shell: [.12, .1, .22] }, matrix: { a: [.49, 1, .54], b: [.78, 1, .82], shell: [.03, .12, .06] },
    egypt: { a: [1, .82, .23], b: [.29, .66, 1], shell: [.18, .14, .05] }, psychedelic: { a: [.49, 1, .54], b: [1, .69, .13], shell: [.1, .05, .18] } };
  const P = PAL[d.world] || PAL.desert, MATS = {};
  const shellM = (k, col) => { const key = 'sh' + k; if (MATS[key]) return MATS[key]; const m = new B.StandardMaterial('bst_' + key, scene), c = col || P.shell; m.disableLighting = true;          /* (owner 2026-11-27: the scene has no lights, so lit materials came out as black silhouettes; the shells glow from within, with a neon rim in the world's colours) */
    const f = new B.FresnelParameters(); f.leftColor = new B.Color3(Math.min(1, P.a[0] * 1.1 + .15), Math.min(1, P.a[1] * 1.1 + .15), Math.min(1, P.a[2] * 1.1 + .15)); f.rightColor = new B.Color3(c[0] * 2.4 + .1, c[1] * 2.4 + .1, c[2] * 2.4 + .14); f.power = 1.6; f.bias = .08; m.emissiveFresnelParameters = f; m.emissiveColor = new B.Color3(1, 1, 1); return MATS[key] = m; };
  const glowM = (k, col, a) => { const key = 'gl' + k; if (MATS[key]) return MATS[key]; const m = new B.StandardMaterial('bst_' + key, scene); m.emissiveColor = C3(col); m.disableLighting = true; if (a != null) m.alpha = a; return MATS[key] = m; };
  const own = (k, col) => { const m = new B.StandardMaterial('bst_own' + k, scene); m.emissiveColor = C3(col); m.disableLighting = true; return m; };          /* (a beast's own glow: it can flash and fade alone) */

  // ---------------------------------------------------------------- modelling: primitive parts under one root
  function part(root, kind, o) { let m;
    if (kind === 'box') m = B.MeshBuilder.CreateBox('bp', { width: o.s[0], height: o.s[1], depth: o.s[2] }, scene);
    else if (kind === 'sph') m = B.MeshBuilder.CreateSphere('bp', { diameterX: o.s[0], diameterY: o.s[1], diameterZ: o.s[2], segments: o.seg || 12 }, scene);
    else if (kind === 'cyl') m = B.MeshBuilder.CreateCylinder('bp', { height: o.h, diameterTop: o.dt ?? o.dd, diameterBottom: o.dd, tessellation: o.tess || 14 }, scene);
    else if (kind === 'tor') m = B.MeshBuilder.CreateTorus('bp', { diameter: o.dd, thickness: o.th, tessellation: o.tess || 32 }, scene);
    else if (kind === 'tube') m = B.MeshBuilder.CreateTube('bp', { path: o.path.map((p) => new B.Vector3(p[0], p[1], p[2])), radius: o.r, tessellation: 8 }, scene);
    m.material = o.m; m.parent = root; m.isPickable = false; if (o.p) m.position.set(o.p[0], o.p[1], o.p[2]); if (o.r3) m.rotation.set(o.r3[0], o.r3[1], o.r3[2]); return m; }
  const legs = (R, m, n, sx, len, y, z0, dz, th) => { const out = []; for (const s of [-1, 1]) for (let i = 0; i < n; i++) { const z = z0 + i * dz, L = part(R, 'tube', { path: [[s * sx, y, z], [s * (sx + len * .55), y + len * .45, z - .1 * len], [s * (sx + len), 0, z - .2 * len]], r: th, m }); out.push({ L, s, i }); } return out; };

  // the build for each model. Forward is -z (the way you drive); size in metres
  const BUILD = {
    stinger(R, v) { const sh = shellM('st' + (v || ''), v === 'scarab' ? [.3, .24, .06] : v === 'glass' ? [.25, .2, .35] : null), gl = glowM('stg', P.a), eye = glowM('eye', [1, .15, .1]);
      part(R, 'sph', { s: [.9, .45, 1.3], p: [0, .45, 0], m: sh }); part(R, 'sph', { s: [.55, .35, .5], p: [0, .45, -.75], m: sh });
      for (const s of [-1, 1]) { part(R, 'tube', { path: [[s * .25, .45, -.9], [s * .55, .5, -1.3], [s * .4, .5, -1.75]], r: .07, m: sh }); part(R, 'sph', { s: [.28, .16, .4], p: [s * .4, .5, -1.85], m: gl }); }
      part(R, 'tube', { path: [[0, .5, .6], [0, 1, 1.05], [0, 1.55, .85], [0, 1.75, .35]], r: .1, m: sh }); const tip = part(R, 'sph', { s: [.32, .32, .32], p: [0, 1.75, .3], m: own('sting' + Math.random(), P.a) });
      part(R, 'sph', { s: [.1, .1, .1], p: [-.12, .55, -.98], m: eye }); part(R, 'sph', { s: [.1, .1, .1], p: [.12, .55, -.98], m: eye });
      return { legs: legs(R, sh, 3, .35, .9, .4, -.35, .4, .045), tip, h: 1.9, r: 1.2, len: 2.6 }; },
    tailgater(R, v) { const sh = shellM('tg' + (v || ''), v === 'chrome' ? [.3, .3, .38] : null), gl = glowM('tgg', P.a), bulb = own('bulb' + Math.random(), [.3, .66, 1]);
      part(R, 'sph', { s: [3.2, 1.3, 4.6], p: [0, 1.1, 0], m: sh }); part(R, 'box', { s: [2.6, .12, 3.6], p: [0, 1.7, 0], m: gl });
      part(R, 'box', { s: [.9, .3, .2], p: [0, 1.05, -2.3], m: glowM('lamp', [1, .9, .6]) });
      for (const s of [-1, 1]) part(R, 'tube', { path: [[s * 1.2, 1.1, -1.8], [s * 2, 1.2, -2.8], [s * 1.5, 1.1, -3.6]], r: .2, m: sh });
      const tail = new B.TransformNode('tail', scene); tail.parent = R; tail.position.set(0, 1.4, 2.1); part(tail, 'tube', { path: [[0, 0, 0], [0, 1.6, 1.2], [0, 3.4, .6], [0, 4, -.8]], r: .3, m: sh });
      const tip = part(tail, 'sph', { s: [1.2, 1.2, 1.2], p: [0, 4, -1.2], m: bulb });
      return { legs: legs(R, sh, 4, 1.3, 2.2, 1, -1.5, 1, .12), tip, tail, h: 3.5, r: 2, len: 5 }; },
    scrapper(R, v) { const sh = shellM('sc' + (v || ''), [.22, .14, .08]), red = glowM('mr', [1, .2, .25]), blu = glowM('mb', [.3, .6, 1]), eye = glowM('ye', [1, .85, .2]);
      part(R, 'box', { s: [1.1, .9, 2.4], p: [0, 1.2, 0], m: sh }); part(R, 'box', { s: [.8, .7, .9], p: [0, 1.4, -1.5], m: sh });
      part(R, 'tor', { dd: .8, th: .18, p: [0, 1.2, -2.05], r3: [0, 0, Math.PI / 2], m: sh }); part(R, 'sph', { s: [.25, .25, .25], p: [-.38, 1.2, -2.15], m: red }); part(R, 'sph', { s: [.25, .25, .25], p: [.38, 1.2, -2.15], m: blu });
      part(R, 'sph', { s: [.22, .22, .22], p: [0, 1.65, -1.95], m: eye }); if (v === 'jackal') { part(R, 'box', { s: [.15, .7, .2], p: [-.3, 2, -1.4], r3: [.3, 0, -.2], m: glowM('gold', [1, .82, .23]) }); part(R, 'box', { s: [.15, .7, .2], p: [.3, 2, -1.4], r3: [.3, 0, .2], m: glowM('gold', [1, .82, .23]) }); }
      const ls = []; for (const [x, z] of [[-.5, -.8], [.5, -.8], [-.5, .9], [.5, .9]]) ls.push({ L: part(R, 'box', { s: [.2, 1, .25], p: [x, .5, z], m: sh }), s: Math.sign(x), i: z < 0 ? 0 : 1 });
      part(R, 'tube', { path: [[0, 1.4, 1.2], [0, 2.2, 1.8], [0, 2.8, 1.5]], r: .08, m: sh });
      return { legs: ls, quad: true, h: 2, r: 1, len: 3, scale: v === 'jackal' ? 1.6 : 1 }; },
    tick(R) { const sh = shellM('tk', [.2, .24, .3]), gl = glowM('tkg', P.b); part(R, 'sph', { s: [.6, .3, .6], p: [0, .12, 0], m: sh }); part(R, 'sph', { s: [.12, .12, .12], p: [0, .3, 0], m: gl }); return { h: .4, r: .4, len: .7 }; },
    burrower(R) { const sh = shellM('bw', [.12, .15, .22]), gl = glowM('bwg', P.b); for (let k = 0; k < 4; k++) part(R, 'sph', { s: [2.4 - k * .3, 2 - k * .25, 2], p: [0, 1, k * 1.8], m: sh });
      const drill = part(R, 'cyl', { h: 2.4, dd: 2.2, dt: .05, p: [0, 1.1, -2.1], r3: [-Math.PI / 2, 0, 0], m: gl, tess: 10 }); return { h: 2.2, r: 1.6, len: 8, drill }; },
    plow(R) { const sh = shellM('pl', [.08, .09, .12]), gl = glowM('plg', P.a), blade = shellM('pb', [.25, .3, .38]);
      part(R, 'box', { s: [3, 2.2, 5], p: [0, 1.6, .5], m: sh }); part(R, 'box', { s: [2.8, 1.4, 2], p: [0, 3.2, -.6], m: sh }); part(R, 'box', { s: [2.4, .9, 1.6], p: [0, 3.2, -.7], m: glowM('cab', [.4, .7, 1], .5) });
      const bl = part(R, 'box', { s: [9, 2.2, .5], p: [0, 1.2, -3.4], r3: [-.25, 0, 0], m: blade }); part(R, 'box', { s: [9, .15, .2], p: [0, 2.3, -3.6], m: gl });
      const lr = part(R, 'box', { s: [.9, .3, .4], p: [-.5, 4.05, -.4], m: glowM('lr', [1, .2, .25]) }), lb = part(R, 'box', { s: [.9, .3, .4], p: [.5, 4.05, -.4], m: glowM('lb', [.3, .6, 1]) });
      for (const x of [-1.3, 1.3]) for (const z of [-1, 2]) part(R, 'cyl', { h: .6, dd: 1.6, p: [x, .8, z], r3: [0, 0, Math.PI / 2], m: sh });
      return { h: 4.5, r: 4.5, len: 7, blade: bl, cab: [0, 3.9, -.6] }; },
    concierge(R) { const sh = shellM('cn', [.35, .32, .42]), scr = glowM('scr', P.b); part(R, 'sph', { s: [1.6, 2.6, 1.4], p: [0, 2.6, 0], m: sh }); part(R, 'box', { s: [1, .8, .1], p: [0, 2.9, -.66], m: scr });
      part(R, 'tube', { path: [[-.35, 2.2, -.68], [0, 2.05, -.7], [.35, 2.2, -.68]], r: .05, m: glowM('smile', P.a) }); const halo = part(R, 'tor', { dd: 1.7, th: .06, p: [0, 1.1, 0], m: glowM('cnh', P.a) }); return { h: 4, r: 1, len: 1.6, hover: 1, halo }; },
    gumball(R) { const sh = shellM('gb', [.2, .16, .26]), dome = glowM('dome', P.b, .45);
      part(R, 'box', { s: [3, 2, 7], p: [0, 1.4, 0], m: sh }); part(R, 'box', { s: [2.8, 1.6, 2], p: [0, 2.8, -2.4], m: sh }); part(R, 'sph', { s: [3.4, 3.4, 3.4], p: [0, 4, 1.4], m: dome });
      for (let k = 0; k < 8; k++) part(R, 'sph', { s: [.7, .7, .7], p: [rnd(-1, 1), rnd(3.2, 4.6), 1.4 + rnd(-1, 1)], m: glowM('gum' + (k % 3), [[1, .82, .23], P.a, P.b][k % 3]) });
      const arm = new B.TransformNode('arm', scene); arm.parent = R; arm.position.set(0, 3.6, -1); part(arm, 'box', { s: [.4, .4, 7], p: [0, 0, -3.5], m: sh }); const hook = part(arm, 'sph', { s: [.8, .8, .8], p: [0, -.4, -7], m: own('hook' + Math.random(), P.a) });
      for (const z of [-2.5, 2.5]) for (const x of [-1.4, 1.4]) part(R, 'cyl', { h: .5, dd: 1.4, p: [x, .7, z], r3: [0, 0, Math.PI / 2], m: sh });
      return { h: 5.5, r: 2, len: 7, arm, tip: hook }; },
    spotter(R) { const sh = shellM('sp', [.12, .12, .16]), red = own('lens' + Math.random(), [1, .2, .25]); part(R, 'box', { s: [1.2, .5, 1.2], p: [0, 0, 0], m: sh }); part(R, 'sph', { s: [.5, .5, .5], p: [0, -.3, -.5], m: red });
      const rot = []; for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { part(R, 'box', { s: [.12, .12, 1.4], p: [x * .5, 0, z * .5], r3: [0, x * z > 0 ? .78 : -.78, 0], m: sh }); rot.push(part(R, 'tor', { dd: 1, th: .05, p: [x, .12, z], m: glowM('rot', P.a) })); }
      return { h: .8, r: 1.4, len: 2.4, hover: 1, tip: red }; },
    bore(R) { const sh = shellM('bo', [.08, .08, .14]), gl = glowM('bog', P.b); part(R, 'cyl', { h: 12, dd: 15, p: [0, 7.5, 5], r3: [Math.PI / 2, 0, 0], m: sh, tess: 24 });
      const rings = [0, 1, 2].map((k) => part(R, 'tor', { dd: 13 - k * 3.8, th: .7, p: [0, 7.5, -1.2 - k * .9], r3: [Math.PI / 2, 0, 0], m: gl, tess: 24 })); const core = part(R, 'sph', { s: [2.4, 2.4, 2.4], p: [0, 7.5, -3.4], m: own('core' + Math.random(), [1, 1, 1]) });
      return { h: 15, r: 7.5, len: 12, rings, tip: core }; },
    warden(R, v) { const sh = shellM('wd' + (v || ''), v === 'chrome' ? [.28, .28, .36] : [.06, .06, .08]); part(R, 'box', { s: [2.2, .9, 4.6], p: [0, .9, 0], m: sh }); part(R, 'box', { s: [1.9, .7, 2.2], p: [0, 1.6, .3], m: sh });
      part(R, 'box', { s: [1.7, .5, 1.6], p: [0, 1.65, .25], m: glowM('ws', [.2, .5, 1], .5) }); const lr = part(R, 'box', { s: [.8, .22, .3], p: [-.42, 2.05, .3], m: own('lbr' + Math.random(), [1, .2, .25]) }), lb = part(R, 'box', { s: [.8, .22, .3], p: [.42, 2.05, .3], m: own('lbb' + Math.random(), [.3, .6, 1]) });
      part(R, 'box', { s: [1.8, .2, .1], p: [0, .9, -2.32], m: glowM('hl', [1, .95, .8]) }); part(R, 'box', { s: [2.2, .06, 4.6], p: [0, 1.36, 0], m: glowM('wde', P.a) });
      for (const x of [-1.05, 1.05]) for (const z of [-1.5, 1.5]) part(R, 'cyl', { h: .45, dd: .9, p: [x, .45, z], r3: [0, 0, Math.PI / 2], m: shellM('tyre', [.04, .04, .05]) });
      return { h: 2.2, r: 1.3, len: 4.6, lr, lb }; },
    mast(R) { const gl = glowM('mst', P.a); for (const s of [-1, 1]) part(R, 'box', { s: [.3, 22, .3], p: [s * 1.2, 11, 0], r3: [0, 0, -s * .05], m: gl });
      for (let k = 0; k < 7; k++) part(R, 'box', { s: [2.6, .15, .15], p: [0, 2 + k * 3, 0], r3: [0, 0, k % 2 ? .6 : -.6], m: gl }); part(R, 'sph', { s: [3, 1.2, 3], p: [0, 22, 0], m: shellM('dish', [.2, .2, .26]) });
      const tip = part(R, 'sph', { s: [.8, .8, .8], p: [0, 23, 0], m: own('red' + Math.random(), [1, .15, .2]) }); return { h: 23, r: 2, len: 2, tip }; },
    sysadmin(R) { const sh = shellM('sy', [.04, .1, .06]), gl = glowM('syg', P.a); part(R, 'box', { s: [12, 8, 7], p: [0, 9, 0], m: sh }); for (let k = 0; k < 6; k++) part(R, 'box', { s: [10.5, .3, .1], p: [0, 6 + k * 1.1, -3.55], m: glowM('srv' + (k % 2), k % 2 ? P.a : P.b) });
      const fan = part(R, 'cyl', { h: .4, dd: 4.5, p: [0, 9, -3.7], r3: [Math.PI / 2, 0, 0], m: glowM('fan', P.b), tess: 6 });
      const masts = [-4, 0, 4].map((x) => { const nm = new B.TransformNode('m', scene); nm.parent = R; nm.position.set(x, 13, 0); part(nm, 'box', { s: [.4, 5, .4], p: [0, 2.5, 0], m: gl }); const t = part(nm, 'sph', { s: [1.4, 1.4, 1.4], p: [0, 5.4, 0], m: own('smt' + Math.random(), [1, .2, .25]) }); return { nm, t, up: true }; });
      for (const s of [-1, 1]) for (let i = 0; i < 3; i++) part(R, 'tube', { path: [[s * 5, 6, -2 + i * 2], [s * 9, 7, -2.5 + i * 2], [s * 10, 0, -3 + i * 2]], r: .35, m: sh });
      return { h: 19, r: 6, len: 7, fan, masts }; },
    sphinx(R) { const sh = shellM('sx', [.3, .24, .08]), gl = glowM('sxg', P.b); part(R, 'box', { s: [6, 14, 6], p: [0, 7, 3], m: sh }); part(R, 'box', { s: [8, 6, 6], p: [0, 15, 2], m: sh }); part(R, 'box', { s: [10, 6, 1.5], p: [0, 16, 3.5], m: glowM('nem', [.3, .25, .08]) });
      const eyes = [-1.6, 1.6].map((x) => part(R, 'sph', { s: [1.2, .8, .5], p: [x, 15.5, -1.1], m: own('eye' + Math.random(), P.b) }));
      const wings = [-1, 1].map((s) => { const w = new B.TransformNode('w', scene); w.parent = R; w.position.set(s * 3, 2, 0); part(w, 'box', { s: [16, 4, .8], p: [s * 8, 0, 0], m: sh }); for (let k = 0; k < 5; k++) part(w, 'box', { s: [1.4, .5, .2], p: [s * (3 + k * 3), 0, -.45], r3: [0, 0, s * .7], m: gl }); return w; });
      return { h: 18, r: 4, len: 6, eyes, wings, tip: eyes[0] }; },
    murmur(R) { const sh = shellM('mu', [.55, .56, .6]); for (let k = 0; k < 3; k++) part(R, 'box', { s: [2.4 - k * .5, 3, 2], p: [0, 2 + k * 3.2, 0], m: sh });
      for (let k = 0; k < 3; k++) part(R, 'tor', { dd: 1.4 - k * .3, th: .15, p: [0, 2 + k * 3.2, -1.02], r3: [Math.PI / 2, 0, 0], m: glowM('spk', [.85, .87, .9]) });
      const rings = [0, 1, 2].map(() => part(R, 'tor', { dd: 3, th: .08, p: [0, 5, 0], m: own('mr' + Math.random(), [.8, .82, .86]) })); return { h: 10, r: 1.5, len: 2, rings }; },
    brood(R) { const sh = shellM('br', [.1, .06, .16]); part(R, 'sph', { s: [16, 7, 20], p: [0, 22, 0], m: sh });
      for (const s of [-1, 1]) for (let i = 0; i < 2; i++) part(R, 'tube', { path: [[s * 6, 22, -4 + i * 8], [s * 14, 26, -6 + i * 8], [s * 17, 0, -8 + i * 10]], r: .9, m: sh });
      part(R, 'tube', { path: [[0, 24, 10], [0, 34, 16], [0, 42, 8], [0, 40, -2]], r: 1.4, m: sh }); const node = part(R, 'sph', { s: [5, 2.4, 5], p: [0, 18.6, 0], m: own('node' + Math.random(), [.22, .91, 1]) });
      const ring = part(R, 'tor', { dd: 7, th: .4, p: [0, 18.4, 0], m: own('nr' + Math.random(), [.22, .91, 1]), tess: 40 }); return { h: 30, r: 9, len: 20, tip: node, ring }; },
    rack(R) { const sh = shellM('rk', [.18, .12, .05]), gl = glowM('rkg', [1, .69, .13]); part(R, 'box', { s: [4.4, .5, 3], p: [0, .25, 0], m: sh });
      for (const x of [-1, 0, 1]) part(R, 'cyl', { h: 1.8, dd: .7, p: [x, 1.2, 0], r3: [-.5, 0, x * .3], m: sh });
      for (const s of [-1, 1]) part(R, 'box', { s: [1.4, .1, .3], p: [s * 1.6, .55, -1], r3: [0, s * .7, 0], m: gl }); const halo = part(R, 'tor', { dd: 5.6, th: .12, p: [0, .5, 0], m: glowM('rkh', [1, .82, .3]), tess: 40 }); return { h: 2, r: 2.6, len: 3, halo }; },
  };

  // ---------------------------------------------------------------- the rosters: three per world, in campaign order, each teaching one answer
  const ROSTER = {
    desert: [{ k: 'swarm', model: 'stinger', v: 'sand', name: 'Sand Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'] }, { k: 'pack', model: 'scrapper', name: 'Dune Scrapper', hp: 1, kill: ['RAM', 'SIDESWIPE', 'ROCKETS'] }, { k: 'chaser', model: 'tailgater', name: 'Dune Tailgater', hp: 3, boss: 1, kill: ['RAM', 'ROCKETS'] }],
    alpine: [{ k: 'carpet', model: 'tick', name: 'Frost Tick', hp: 1, kill: ['STOMP', 'RAM', 'ROCKETS'] }, { k: 'ambush', model: 'burrower', name: 'Snow Burrower', hp: 2, kill: ['STOMP', 'ROCKETS'] }, { k: 'plow', model: 'plow', name: 'Plow Warden', hp: 4, boss: 1, kill: ['STOMP', 'BAIT', 'ROCKETS'] }],
    candy: [{ k: 'swarm', model: 'stinger', v: 'glass', name: 'Glass Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'], big: 1 }, { k: 'lure', model: 'concierge', name: 'Sweet Concierge', hp: 2, kill: ['SIDESWIPE', 'STOMP', 'ROCKETS'] }, { k: 'thief', model: 'gumball', name: 'Gumball Adjuster', hp: 4, boss: 1, kill: ['SIDESWIPE', 'ROCKETS'] }],
    tunnel: [{ k: 'drop', model: 'stinger', v: 'wire', name: 'Wire Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS', 'BAIT'] }, { k: 'flyer', model: 'spotter', name: 'Tunnel Spotter', hp: 2, kill: ['STOMP', 'ROCKETS', 'BAIT'] }, { k: 'bore', model: 'bore', name: 'The Bore', hp: 5, boss: 1, kill: ['BAIT', 'ROCKETS'] }],
    synthwave: [{ k: 'chaser', model: 'tailgater', v: 'chrome', name: 'Chrome Tailgater', hp: 3, kill: ['RAM', 'ROCKETS'], pair: 1 }, { k: 'flyer', model: 'spotter', name: 'Grid Drones', hp: 1, kill: ['STOMP', 'ROCKETS'], squad: 1 }, { k: 'wing', model: 'warden', v: 'chrome', name: 'Interceptor Wing', hp: 2, boss: 1, kill: ['SIDESWIPE', 'BAIT', 'ROCKETS'] }],
    matrix: [{ k: 'swarm', model: 'stinger', v: 'glyph', name: 'Glyph Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'], regen: 1 }, { k: 'mast', model: 'mast', name: 'Relay Mast', hp: 2, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'] }, { k: 'sysadmin', model: 'sysadmin', name: 'The Sysadmin', hp: 3, boss: 1, kill: ['NODE', 'RAM', 'ROCKETS'] }],
    egypt: [{ k: 'swarm', model: 'stinger', v: 'scarab', name: 'Scarab Stinger', hp: 1, kill: ['SIDESWIPE', 'STOMP', 'ROCKETS'], armour: 1 }, { k: 'pack', model: 'scrapper', v: 'jackal', name: 'Jackal Hound', hp: 3, kill: ['SIDESWIPE', 'BAIT', 'ROCKETS'], leader: 1 }, { k: 'sphinx', model: 'sphinx', name: 'Sphinx Cordon', hp: 6, boss: 1, kill: ['ROCKETS', 'RAM'] }],
    psychedelic: [{ k: 'swarm', model: 'stinger', v: 'breath', name: 'Breathing Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'], shift: 1 }, { k: 'drain', model: 'murmur', name: 'Murmur Unit', hp: 3, kill: ['RAM', 'SIDESWIPE', 'ROCKETS'] }, { k: 'brood', model: 'brood', name: 'Broodmother Prime', hp: 9, boss: 1, kill: ['NODE', 'STOMP', 'ROCKETS'] }],
  };
  const ROS = ROSTER[d.world] || ROSTER.desert, REG = ROS.filter((r) => !r.boss), BOSS = ROS.find((r) => r.boss);

  // ---------------------------------------------------------------- beasts
  const LIVE = [], RACKS = [], ROCKETS = [], CARPETS = [], WALLS = [], PILLARS = [], LOG = { kills: {}, seen: {} };
  let uid = 0;
  const BQ = [];          /* the build queue: big groups are made a few per frame */
  function make(spec, x, z, extra) { const R = new B.TransformNode('beast', scene), g = BUILD[spec.model](R, spec.v); const sc = (g.scale || 1) * (spec.boss ? 1 : 1) * (extra && extra.scale || 1); R.scaling.setAll(sc);
    const b = Object.assign({ id: ++uid, spec, R, g, x, z, y: ground(x, z), u: 0, vz: 0, vx: 0, hp: spec.hp + (spec.boss ? Math.floor(T / 3) : 0), t: 0, state: 'go', cool: rnd(1, 3), blind: 0, hitT: 0, ph: rnd(0, 6.28), sc, r: g.r * sc, h: g.h * sc, len: g.len * sc }, extra || {});
    b.max = b.hp; LIVE.push(b); LOG.seen[spec.name] = (LOG.seen[spec.name] || 0) + 1; return b; }
  /* THE BOOMS (owner 2026-11-27): every species has its own deep harmonic boom: a root note from its name, its own blend of partials, a soft thump under it;
     each one a little different (detune, partial mix, length). Bosses an octave down. Kept soft. */
  const ROOTS = [55, 61.74, 65.41, 73.42, 82.41, 87.31, 98, 110];
  let lastBoom = 0;
  function boom(b) { const ctx = d.actx && d.actx(); if (!ctx) return; if (!b.spec.boss && ctx.currentTime - lastBoom < .14) return; lastBoom = ctx.currentTime; try {          /* (a swarm popping at once makes one rolling run of booms, not a pile-up) */ const nm = b.spec.name; let h = 0; for (const ch of nm) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
      const t0 = ctx.currentTime + .01, root = ROOTS[h % ROOTS.length] * (b.spec.boss ? .5 : 1) * (1 + (Math.random() - .5) * .06), len = (b.spec.boss ? 2.6 : 1.3) * (.85 + Math.random() * .3);
      const out = ctx.createGain(); out.gain.value = b.spec.boss ? .22 : .12; const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900 + (h % 5) * 220; out.connect(lp); lp.connect(ctx.destination);
      const P = [[1, 1], [2, .45 + ((h >> 3) % 4) * .1], [3.01, .25], [4.2 + ((h >> 5) % 3) * .4, .12], [.5, b.spec.boss ? .6 : .2]];
      for (const [m, a] of P) { const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine'; o.frequency.setValueAtTime(root * m * 1.08, t0); o.frequency.exponentialRampToValueAtTime(root * m, t0 + .25);
        const amp = a * (.8 + Math.random() * .4); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(amp, t0 + .012); g.gain.exponentialRampToValueAtTime(.0008, t0 + len * (1.1 - m * .12)); o.connect(g); g.connect(out); o.start(t0); o.stop(t0 + len + .1); }
      const nb = ctx.createBuffer(1, Math.round(ctx.sampleRate * .25), ctx.sampleRate), ch = nb.getChannelData(0); for (let i = 0; i < ch.length; i++) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / ch.length, 3);
      const ns = ctx.createBufferSource(), nf = ctx.createBiquadFilter(), ng = ctx.createGain(); ns.buffer = nb; nf.type = 'lowpass'; nf.frequency.value = 220; ng.gain.value = .5; ns.connect(nf); nf.connect(ng); ng.connect(out); ns.start(t0); } catch (e) { } }
  function kill(b, how) { if (b.dead) return; b.dead = true; if (!b.spec.swarmQuiet) boom(b); const p = [b.x, b.y + b.h * .5, b.z]; try { d.fx(b.spec.boss ? 'blast' : 'orb', p); if (b.spec.boss) { d.fx('blast', [b.x - 3, b.y + b.h * .3, b.z]); d.fx('cheer', p); } } catch (e) { }
    try { d.score(b.spec.boss ? 2500 : 150 * b.max); d.chain(); d.look(b.spec.boss ? 'boss' : 'kill'); d.shake(b.spec.boss ? .6 : .2); d.sfx(b.spec.boss ? 'kaboom' : 'boom'); } catch (e) { }
    LOG.kills[b.spec.name] = (LOG.kills[b.spec.name] || 0) + 1; try { const k = 'ag_registry', o = JSON.parse(localStorage.getItem(k) || '{}'); o[b.spec.name] = (o[b.spec.name] || 0) + 1; localStorage.setItem(k, JSON.stringify(o)); } catch (e) { }
    if (b.onDie) b.onDie(how); b.fall = 0; }
  function hurt(b, how, n = 1) { if (b.dead || b.hitT > 0) return false; b.hp -= n; b.hitT = .45; try { d.fx('orb', [b.x, b.y + b.h * .6, b.z]); d.sfx('thwack'); d.shake(.18); } catch (e) { } if (b.hp <= 0) kill(b, how); return true; }

  // how the car touched it: from above, from the side, or head-on / from behind
  function method(b) { if (!PH.grounded && PH.vy < 1 && PH.y > b.y + b.h * .45) return 'STOMP'; if (Math.abs(PH.vx) > 4.5 && Math.sign(PH.vx) === Math.sign(b.x - PH.x) && Math.abs(b.x - PH.x) > b.r * .35) return 'SIDESWIPE'; return 'RAM'; }
  const touching = (b, pad = 1.1) => Math.abs(PH.x - b.x) < b.r + pad && Math.abs(PH.z - b.z) < b.len * .5 + 1.6 && PH.y < b.y + b.h + 2.2 && PH.y > b.y - 2;
  // what a machine does to you: always a stumble, never a stop
  /* DAMAGE PLAN (owner 2026-11-27): a machine never stops you; how hard it shoves or slows you grows gently with the campaign (Route Zero 0.7x .. the Open Channel 1.05x),
     bosses a touch harder, and every species keeps its own kind of hit (shove, drag, EMP, ride-along). Relaxing first: nothing ever passes about 1.1x. */
  const DMG = Math.min(1.1, .7 + .05 * T);
  const shove0 = (dir, k) => { PH.vx += dir * k * DMG; try { d.shake(.25 * DMG); } catch (e) { } }; const shove = shove0;
  const drag = (k) => { const kk = 1 - (1 - k) * DMG; PH.vx *= kk; PH.vz *= kk; };
  const bounce = (b) => { drag(.82); shove(Math.sign(PH.x - b.x) || 1, 5); try { d.sfx('bonk'); } catch (e) { } };
  const emp = () => { PH.boost_t = 0; drag(.86); try { d.emp(); d.shake(.35); d.sfx('zap'); } catch (e) { } };

  // ---------------------------------------------------------------- encounter builders (what spawns for each kind)
  const ahead = (m) => PH.z - m, lineX = (z, u) => d.trailX(z) + u;
  const ENC = {
    swarm(s) { const n = Math.round((s.big ? 14 : 9) + T * 1.6), z0 = ahead(rnd(110, 150)); for (let k = 0; k < n; k++) BQ.push(() => { const z = z0 - rnd(0, 40), b = make(s, lineX(z, rnd(-13, 13)), z); b.mode = 'swarm'; b.sp = rnd(7, 11) + T * .5; }); },          /* (built a few per frame: a whole swarm in one frame stalled it) */
    drop(s) { const z = ahead(rnd(90, 120)), gap = rnd(-6, 6), n = 6 + Math.floor(T / 2); for (let k = 0; k < n; k++) { const u = -12 + k * 24 / (n - 1); if (Math.abs(u - gap) < 3.2) continue; const b = make(s, lineX(z, u), z); b.mode = 'drop'; b.yOff = 14; b.vy = 0; } },
    pack(s) { const n = 3 + Math.min(2, Math.floor(T / 3)); for (let k = 0; k < n; k++) { const b = make(s, PH.x, PH.z + 30 + k * 4); b.mode = 'pack'; b.slot = (k % 2 ? 1 : -1) * (4 + Math.floor(k / 2) * 2.5); b.rel = -2 - k * 2; }
      if (s.leader) { const L = make(s, PH.x, PH.z + 40, { scale: 1.35 }); L.mode = 'leader'; L.hp = L.max = s.hp; L.lead = true; } },
    chaser(s) { const n = s.pair ? 2 : 1; for (let k = 0; k < n; k++) { const b = make(s, PH.x, PH.z + 60 + k * 12); b.mode = 'chase'; b.slot = n > 1 ? (k ? 3.5 : -3.5) : 0; b.cool = 3 + k * 2.5; } },
    carpet(s) { const z0 = ahead(rnd(100, 140)), len = 26 + T * 3, u = rnd(-4, 4), w = 9; const c = { z0, z1: z0 - len, u, w, bits: [] }; for (let k = 0; k < 70; k++) { const z = z0 - rnd(0, len), b = make(s, lineX(z, u + rnd(-w, w)), z); b.mode = 'carpet'; b.carpet = c; c.bits.push(b); } CARPETS.push(c); },
    ambush(s) { const z = ahead(rnd(150, 190)), side = Math.random() < .5 ? -1 : 1, b = make(s, lineX(z, side * 26), z); b.mode = 'ridge'; b.side = side; b.under = true; b.R.setEnabled(false); b.ridge = mkRidge(); },
    lure(s) { const b = make(s, PH.x, ahead(90)); b.mode = 'lure'; },
    flyer(s) { const n = s.squad ? 3 + Math.floor(T / 3) : 1; for (let k = 0; k < n; k++) { const b = make(s, PH.x, PH.z + 25, {}); b.mode = 'fly'; b.slot = (k - (n - 1) / 2) * 5; b.rel = -(30 + Math.abs(k - (n - 1) / 2) * 6); b.grid = mkGrid(); } },
    mast(s) { const z = ahead(rnd(200, 260)), side = Math.random() < .5 ? -1 : 1, b = make(s, lineX(z, side * 15), z); b.mode = 'mast'; b.links = []; },
    drain(s) { const z = ahead(rnd(180, 230)), side = Math.random() < .5 ? -1 : 1, b = make(s, lineX(z, side * 11), z); b.mode = 'drain'; },
    // bosses
    plow(s) { const b = make(s, PH.x, PH.z + 70); b.mode = 'plow'; b.phase = 'behind'; b.pt = 0; },
    thief(s) { const b = make(s, PH.x, ahead(70)); b.mode = 'thief'; b.sw = 0; },
    bore(s) { const b = make(s, d.trailX(PH.z + 50), PH.z + 50); b.mode = 'bore'; },
    wing(s) { for (let k = 0; k < 3; k++) { const b = make(s, PH.x, PH.z + 40 + k * 6); b.mode = 'wing'; b.wi = k; b.hp = b.max = s.hp; } },
    sysadmin(s) { const b = make(s, PH.x, ahead(80)); b.mode = 'sysadmin'; b.cores = false; b.masts = b.g.masts; },
    sphinx(s) { const b = make(s, PH.x, ahead(90)); b.mode = 'sphinx'; b.eyes = 0; },
    brood(s) { const b = make(s, PH.x, ahead(110)); b.mode = 'brood'; b.node = 3; },
  };
  // the swarm for the Sysadmin's glyph walls and the Broodmother's drops
  const GLYPH = { k: 'swarm', model: 'stinger', v: 'glyph', name: 'Glyph Stinger', hp: 1, kill: ['RAM', 'SIDESWIPE', 'STOMP', 'ROCKETS'] };
  const BROOD = [ROSTER.desert[0], ROSTER.candy[0], ROSTER.matrix[0], ROSTER.egypt[0]];
  function dropLine(spec, z, gapU) { for (let u = -12; u <= 12; u += 3) { if (Math.abs(u - gapU) < 3.4) continue; const b = make(spec, lineX(z, u), z); b.mode = 'drop'; b.yOff = 12; b.vy = 0; b.minion = true; } }

  // ---------------------------------------------------------------- world dressings for some machines
  function mkRidge() { const m = B.MeshBuilder.CreateSphere('ridge', { diameterX: 3, diameterY: 1.2, diameterZ: 6, segments: 10 }, scene); m.material = glowM('ridge', P.b, .55); m.isPickable = false; return m; }
  function mkGrid() { const m = B.MeshBuilder.CreateGround('grid', { width: 18, height: 26, subdivisions: 1 }, scene), mt = new B.StandardMaterial('bst_grid' + Math.random(), scene), dt = new B.DynamicTexture('gridT', { width: 128, height: 128 }, scene, true), c = dt.getContext();
    c.clearRect(0, 0, 128, 128); c.strokeStyle = '#ff3b4e'; c.lineWidth = 3; for (let k = 0; k <= 8; k++) { c.beginPath(); c.moveTo(k * 16, 0); c.lineTo(k * 16, 128); c.stroke(); c.beginPath(); c.moveTo(0, k * 16); c.lineTo(128, k * 16); c.stroke(); } dt.update(); dt.hasAlpha = true;
    mt.diffuseTexture = dt; mt.emissiveTexture = dt; mt.opacityTexture = dt; mt.disableLighting = true; mt.alpha = .75; mt.backFaceCulling = false; m.material = mt; m.isPickable = false; return m; }
  function mkWall(z, gapU, kind) { const segs = []; for (let u = -13; u <= 13; u += 3.2) { if (Math.abs(u - gapU) < 4) continue; const x = lineX(z, u), m = B.MeshBuilder.CreateBox('wall', { width: 3, height: kind === 'snow' ? 2.4 : 3.2, depth: 1.2 }, scene);
      m.material = kind === 'snow' ? glowM('snow', [.75, .88, 1], .85) : kind === 'glyph' ? glowM('gw', P.a, .7) : glowM('wing', P.b, .8); m.position.set(x, ground(x, z) + 1.2, z); m.isPickable = false; segs.push({ m, x, u }); }
    WALLS.push({ z, segs, kind, gapU }); }

  // ---------------------------------------------------------------- rocket racks and seekers
  function rackAt(z) { const R = new B.TransformNode('rack', scene), g = BUILD.rack(R), x = d.trailX(z) + rnd(-2, 2); R.position.set(x, ground(x, z) + .05, z); RACKS.push({ R, g, x, z, used: false }); }
  const salvo = () => 2 + Math.round(T * 4 / 7);
  function fire(n, boost) { const targets = LIVE.filter((b) => !b.dead && !b.under && b.z < PH.z + 5 && PH.z - b.z < 170 && (!b.spec.boss || weakOpen(b))).sort((a, c) => (PH.z - a.z) - (PH.z - c.z));
    const shots = boost ? n + 1 : n; for (let k = 0; k < shots; k++) { const tg = targets.length ? targets[k % targets.length] : null; const m = B.MeshBuilder.CreateSphere('rkt', { diameterX: .4, diameterY: .4, diameterZ: 1.4, segments: 6 }, scene); m.material = glowM('rkt', [1, .82, .3]); m.isPickable = false;
      const tr = B.MeshBuilder.CreateBox('rktT', { width: .12, height: .12, depth: 5 }, scene); tr.material = glowM('rktT', [1, .55, .15], .55); tr.parent = m; tr.position.z = 2.8; tr.isPickable = false;
      const ring = tg ? B.MeshBuilder.CreateTorus('lock', { diameter: Math.max(2.4, tg.r * 2.4), thickness: .12, tessellation: 32 }, scene) : null; if (ring) { ring.material = glowM('lock', [1, .82, .3]); ring.isPickable = false; }
      ROCKETS.push({ m, tg, ring, x: PH.x + (k - shots / 2) * .8, y: PH.y + 2, z: PH.z - 2, vx: (k - shots / 2) * 6, vy: 10 + k, vz: -Math.max(30, speed() + 15), t: 0 }); }
    try { d.sfx('launch'); d.shake(.15); } catch (e) { } }
  const weakOpen = (b) => { const m = b.mode; if (m === 'sysadmin') return true; if (m === 'sphinx') return b.eyes > .5; if (m === 'brood') return true; if (m === 'bore') return true; return true; };

  // ---------------------------------------------------------------- the director: what comes when, by distance along the level
  const LEN = Math.abs(d.END || -7400), BOSSZ = -LEN * .68, DIR = { next: -650, i: 0, bossDone: false, bossOn: null, racks: [] };
  const gapM = clamp(760 - T * 45, 420, 760);
  { for (let z = -900; z > -LEN + 600; z -= rnd(900, 1300)) DIR.racks.push(z); DIR.racks.push(BOSSZ + 350, BOSSZ + 180); DIR.racks.sort((a, b) => b - a); }
  const ALLSPEC = Object.values(ROSTER).flat(), ONLY = d.only ? ALLSPEC.find((r) => r.name.toLowerCase() === String(d.only).toLowerCase()) : null;
  if (ONLY) { DIR.next = -90; DIR.racks.length = 0; for (let z = -260; z > -LEN + 200; z -= 380) DIR.racks.push(z); }
  function director() {
    if (ONLY) { while (DIR.racks.length && PH.z - 220 < DIR.racks[0]) rackAt(DIR.racks.shift()); const alive = LIVE.some((b) => !b.dead && b.spec === ONLY && !b.minion);
      if (!alive && PH.z < DIR.next) { ENC[ONLY.k](ONLY); DIR.next = PH.z - (ONLY.boss ? 300 : 220); } return; }
    if (d.inTunZ && d.inTunZ(PH.z, 160) && d.world !== 'tunnel') return; const busy = LIVE.some((b) => !b.dead && !b.minion && !b.carpetBit && b.mode !== 'swarm' && b.mode !== 'drop' && PH.z - b.z < 260 && b.z < PH.z + 90);
    while (DIR.racks.length && PH.z - 220 < DIR.racks[0]) { const z = DIR.racks.shift(); if (!(d.inTunZ && d.inTunZ(z, 40))) rackAt(z); }
    if (!DIR.bossDone && PH.z < BOSSZ && BOSS) { if (BOSS.k === 'bore') { if (!(d.tunnel && d.tunnel())) return; } DIR.bossDone = true; DIR.bossOn = BOSS; ENC[BOSS.k](BOSS); return; }
    if (PH.z < DIR.next && !busy && REG.length) { const s = REG[DIR.i++ % REG.length]; if (s.k === 'flyer' && d.world === 'tunnel' && !(d.tunnel && d.tunnel())) { DIR.i--; } else ENC[s.k](s); DIR.next = PH.z - gapM * rnd(.8, 1.2); }
    if (d.world === 'tunnel' && d.tunnel && d.tunnel() && !DIR.tunFly && REG[1]) { DIR.tunFly = true; ENC.flyer(REG[1]); }          /* (the Tunnel Spotter lives in the tunnel) */
  }

  // ---------------------------------------------------------------- per-kind behaviour
  const stall = (b, dt, every, len) => { b.st = (b.st ?? rnd(3, 5)) - dt; if (b.st < -len) b.st = every * rnd(.85, 1.2) - T * .3; return b.st < 0; };          /* (a window where it lets you close in) */
  const hold = (b, rel, k = 1.6) => { const tgt = PH.z + rel; b.vz = PH.vz + clamp((tgt - b.z) * k, -24, 24); b.z += b.vz * DT; };
  const steerU = (b, u, k = 2) => { const cu = b.x - d.trailX(b.z); b.x += (u - cu) * Math.min(1, k * DT); };
  let DT = 0;
  function behave(b, dt) { const m = b.mode, rel = b.z - PH.z, dx = PH.x - b.x, live = b.blind <= 0;
    switch (m) {
      case 'swarm': { if (b.latched) { b.x = PH.x + b.lx; b.z = PH.z + b.lz; b.y = PH.y + .6; if (PH.boost_t > 0 || Math.random() < dt * .08) { b.latched = false; PH.latch_n = Math.max(0, (PH.latch_n || 1) - 1); kill(b, 'BOOST'); } else drag(1 - .012 * dt * 60 * .25); return; }
        const sp = live ? b.sp : b.sp * .2, tx = dx * .6 + Math.sin(b.t * 3 + b.ph) * 2.5, l = Math.hypot(tx, 1); b.x += tx / l * sp * dt; b.z += 1 / l * sp * dt;
        if (b.spec.regen && b.respawn) { } if (rel > 12) { b.gone = true; } break; }
      case 'drop': { if (b.yOff > 0) { b.vy -= 30 * dt; b.yOff = Math.max(0, b.yOff + b.vy * dt); } if (rel > 8) b.gone = true; break; }
      case 'pack': { const tgtU = d.trailX(PH.z) - d.trailX(b.z); if (live) { hold(b, b.rel, 2); b.x += (PH.x + b.slot * (b.tight ? .5 : 1) - b.x) * Math.min(1, 2.5 * dt); } else { b.z += PH.vz * .5 * dt; b.x += Math.sign(b.slot) * 6 * dt; }
        b.cool -= dt; if (live && b.cool < .6 && !b.tell) { b.tell = true; } if (b.cool < 0) { b.cool = rnd(2.5, 4.5) - T * .15; b.tell = false; if (Math.abs(dx) < 4.5 && Math.abs(rel) < 4) shove(-Math.sign(dx), 7); } if (rel > 60) b.gone = true; break; }
      case 'leader': { if (live) hold(b, 12, 1.2); b.x += (PH.x - b.x) * Math.min(1, 1.2 * dt); b.cool -= dt; if (b.cool < .7) b.tell = true; if (b.cool < 0) { b.cool = 6 - T * .3; b.tell = false; for (const o of LIVE) if (o.mode === 'pack') o.tight = 2.5; try { d.look('howl'); d.sfx('honk'); } catch (e) { } }
        for (const o of LIVE) if (o.mode === 'pack' && o.tight) o.tight = Math.max(0, o.tight - dt);
        if (b.rear && PH.vz > -6 + b.vz) { } break; }
      case 'chase': { if (b.over) { b.vz = PH.vz * .7; b.z += b.vz * dt; if (rel < -80) { b.over = false; } } else if (live) hold(b, 11 - (b.slot ? 2 : 0), 1); else b.z += PH.vz * .4 * dt;
        b.x += (PH.x + b.slot - b.x) * Math.min(1, (b.over ? .5 : 1.6) * dt); b.cool -= dt; b.tell = !b.over && live && b.cool < 1.1;
        if (b.g.tip) b.g.tip.material.emissiveColor.set(...(b.tell ? [1, 1, 1] : [.3, .66 + .2 * Math.sin(b.t * 6), 1]));
        if (b.cool < 0 && !b.over) { b.cool = rnd(4, 6) - T * .2; if (!PH.grounded || Math.abs(dx - b.slot) > 3) { b.over = true; b.z = Math.min(b.z, PH.z - 2); b.vz = PH.vz; try { d.sfx('whoosh'); } catch (e) { } } else emp(); } break; }
      case 'carpet': { break; }
      case 'ridge': { const tgtU = d.trailX(PH.z + rel) - b.x; b.z = Math.max(b.z, b.z); b.x += clamp((d.trailX(b.z) + (PH.x - d.trailX(PH.z)) - b.x), -1, 1) * 9 * dt; b.ridge.position.set(b.x, ground(b.x, b.z) + .2, b.z);
        if (rel > -35 && b.under) { b.under = false; b.R.setEnabled(true); b.ridge.setEnabled(false); b.up = 0; try { d.sfx('boom'); d.shake(.2); } catch (e) { } } if (!b.under) { b.up = Math.min(1, (b.up || 0) + dt * 2.5); } if (rel > 14) b.gone = true; break; }
      case 'lure': { hold(b, -7 + Math.sin(b.t * .8) * 5, 1); b.x += (PH.x + Math.sin(b.t * .7) * 3.5 - b.x) * Math.min(1, .9 * dt); if (b.g.halo) b.g.halo.rotation.y = b.t; if (rel > 20) b.gone = true; break; }
      case 'fly': { if (ONLY && d.world === 'tunnel') b.free = true; if (live) { hold(b, b.rel, 1.1); b.x += (PH.x + b.slot - b.x) * Math.min(1, 1.2 * dt); } else { b.vy = (b.vy || 0) - 18 * dt; b.yOff = (b.yOff ?? 10) + b.vy * dt; if (b.yOff < 0) kill(b, 'BAIT'); }
        b.yOff = live ? 4.2 + Math.sin(b.t * 2 + b.ph) * .8 : b.yOff; const gz = b.z - 18; if (b.grid) { b.grid.position.set(d.trailX(gz) + (b.x - d.trailX(b.z)), ground(b.x, gz) + .25, gz); b.grid.rotation.y = 0; }
        if (d.world === 'tunnel' && d.tunnel && !d.tunnel() && !b.free) { b.gone = true; } const pu = PH.x - d.trailX(PH.z); if (d.world === 'tunnel' && Math.abs(pu) > 8) { b.hug = (b.hug || 0) + dt; if (b.hug > 1.4) { b.hug = 0; hurt(b, 'BAIT'); } } else b.hug = 0;
        if (rel > 30) b.gone = true; break; }
      case 'mast': { const linked = LIVE.filter((o) => !o.dead && o !== b && Math.abs(o.z - b.z) < 140 && (o.mode === 'swarm' || o.mode === 'drop')); for (const o of linked) o.mesh = b; b.links = linked; if (rel > 30) b.gone = true; break; }
      case 'drain': { const inView = rel < 0 && rel > -220; if (inView) try { d.drain(dt); } catch (e) { } for (let k = 0; k < 3; k++) { const r = b.g.rings[k], s = ((b.t * .6 + k / 3) % 1); r.scaling.setAll(1 + s * 10); r.material.alpha = 1 - s; } if (rel > 30) b.gone = true; break; }
      case 'plow': { b.pt -= dt; if (b.phase === 'behind') { hold(b, 9, 1.2); b.x += (PH.x - b.x) * Math.min(1, 1.4 * dt); b.tell = b.pt < 1; if (b.pt < 0) { b.pt = rnd(5, 7) - T * .2; if (Math.abs(dx) < 4.5) { drag(.8); shove(Math.sign(dx) || 1, 3); try { d.sfx('thwack'); } catch (e) { } } if (Math.random() < .55) { b.phase = 'ahead'; } } }
          else { hold(b, -38, .9); b.x += (d.trailX(b.z) + Math.sin(b.t * .5) * 6 - b.x) * Math.min(1, dt); if (b.pt < 0) { b.pt = rnd(3, 4.5); mkWall(b.z - 25, rnd(-8, 8), 'snow'); if (Math.random() < .4) b.phase = 'behind'; } }
          const edge = Math.abs(b.x - d.trailX(b.z)); if (edge > 15) { hurt(b, 'BAIT'); b.x = d.trailX(b.z) + Math.sign(b.x - d.trailX(b.z)) * 10; } break; }
      case 'thief': { const w = stall(b, dt, 9, 4); hold(b, w ? -1 : -34, .9); b.x += ((w ? PH.x + (b.x > PH.x ? 3.6 : -3.6) : d.trailX(b.z) + Math.sin(b.t * .4) * 5) - b.x) * Math.min(1, (w ? 2 : .8) * dt); b.sw += dt; const a = Math.sin(b.sw * 1.1) * 1.2; b.g.arm.rotation.y = a; b.tell = Math.abs(Math.cos(b.sw * 1.1)) < .25;
          const tipX = b.x + Math.sin(a) * -7 * b.sc, tipZ = b.z - Math.cos(a) * 7 * b.sc; if (Math.abs(PH.x - tipX) < 2 && Math.abs(PH.z - tipZ) < 3 && (b.armCool || 0) <= 0) { b.armCool = 1.2; shove(Math.sign(PH.x - b.x) || 1, 8); } b.armCool = (b.armCool || 0) - dt; break; }
      case 'bore': { const W = d.tunnel && d.tunnel(); if (!W && !ONLY) { if (rel > 0) b.gone = true; } hold(b, 16 - Math.min(10, b.t * .5), .7); b.x += (PH.x - b.x) * Math.min(1, .5 * dt); for (const r of b.g.rings) r.rotation.z += dt * (3 + T * .2) * (r === b.g.rings[1] ? -1 : 1);
          if (Math.abs(rel) < b.len * .5 + 1 && Math.abs(dx) < 6) { drag(.85); try { d.shake(.4); d.sfx('thwack'); } catch (e) { } b.z = PH.z + 9; }
          if (!b.pil || b.pil.length < 2) { b.pil = b.pil || []; const z = PH.z - rnd(60, 90), u = pick([-6, -3, 3, 6]), x = lineX(z, u); const m = B.MeshBuilder.CreateCylinder('pillar', { height: 14, diameter: 2.2 }, scene); m.material = glowM('pil', P.b, .9); m.position.set(x, ground(x, z) + 7, z); m.isPickable = false; const pl = { m, x, z, hit: false }; b.pil.push(pl); PILLARS.push(pl); }
          for (const pl of b.pil) { if (!pl.hit && Math.abs(b.z - pl.z) < 2 && Math.abs(b.x - pl.x) < 4) { pl.hit = true; hurt(b, 'BAIT'); try { d.fx('blast', [pl.x, PH.y + 3, pl.z]); } catch (e) { } pl.m.dispose(); } if (!pl.carHit && Math.abs(PH.z - pl.z) < 1.5 && Math.abs(PH.x - pl.x) < 2) { pl.carHit = true; drag(.75); shove(Math.sign(PH.x - pl.x) || 1, 6); } }
          b.pil = b.pil.filter((pl) => !pl.hit && pl.z < b.z + 5); break; }
      case 'wing': { const off = [-3.4, 3.4, 0][b.wi]; if (b.wi < 2) { hold(b, 1.5, 1.4); b.x += (PH.x + off * (b.pinch ? .55 : 1) - b.x) * Math.min(1, 2 * dt); } else { hold(b, -9, 1.2); b.x += (PH.x - b.x) * Math.min(1, 1.5 * dt); }
          b.cool -= dt; b.tell = b.cool < .8; if (b.cool < 0) { b.cool = rnd(3, 5) - T * .2; b.pinch = 1.2; if (b.wi === 2 && Math.abs(dx) < 2.6 && rel < 0 && rel > -12) { drag(.86); try { d.sfx('honk'); } catch (e) { } } } if (b.pinch) b.pinch = Math.max(0, b.pinch - dt);
          if (b.shoveV) { b.x += b.shoveV * dt; b.shoveV *= Math.exp(-3 * dt); for (const o of LIVE) if (o !== b && !o.dead && o.mode === 'wing' && Math.abs(o.x - b.x) < 2.4 && Math.abs(o.z - b.z) < 4.5 && Math.abs(b.shoveV) > 3) { hurt(o, 'BAIT'); hurt(b, 'BAIT'); b.shoveV = 0; } } break; }
      case 'sysadmin': { const w = stall(b, dt, 10, 4.5); b.crouch = clamp((b.crouch || 0) + (w ? 1 : -1) * dt * 1.5, 0, 1); hold(b, w ? -2 : -60, .7); b.x += (d.trailX(b.z) - b.x) * Math.min(1, dt); b.g.fan.rotation.y += dt * 4; b.cool -= dt; if (b.cool < 0) { b.cool = rnd(4, 6) - T * .2; dropLine(GLYPH, b.z + 18, rnd(-8, 8)); }
          b.cores = b.masts.every((q) => !q.up); break; }
      case 'sphinx': { const w = stall(b, dt, 11, 4); b.bow = clamp((b.bow || 0) + (w ? 1 : -1) * dt * 1.3, 0, 1); hold(b, w ? -3 : -70, .6); if (!w) b.headHit = false; b.x += (d.trailX(b.z) - b.x) * Math.min(1, dt); b.cool -= dt; b.eyes = Math.max(0, b.eyes - dt * .5);
          if (b.cool < 0) { b.cool = rnd(5, 7) - T * .2; const gap = rnd(-8, 8); mkWall(b.z + 30, gap, 'wing'); b.eyes = 1.6; b.sweepU = gap; } for (const e of b.g.eyes) e.material.emissiveColor.set(...(b.eyes > .5 ? [1, 1, 1] : P.b));
          if (b.eyes > .5 && b.eyes < 1.1 && !b.swept) { b.swept = true; if (Math.abs((PH.x - d.trailX(PH.z)) - b.sweepU) < 3) emp(); } if (b.eyes <= .5) b.swept = false; break; }
      case 'brood': { const w = stall(b, dt, 10, 4.5); b.low = clamp((b.low || 0) + (w ? 1 : -1) * dt * 1.4, 0, 1); b.g.tip.position.y = 18.6 - 15 * b.low; b.g.ring.position.y = 18.4 - 15 * b.low; hold(b, w ? -2 : -75, .6); if (!w) b.nodeHit = false; b.x += (d.trailX(b.z) - b.x) * Math.min(1, dt); b.cool -= dt; if (b.cool < 0) { b.cool = rnd(4.5, 6.5) - T * .2; const sp = pick(BROOD); for (let k = 0; k < 6 + T; k++) { const m = make(sp, b.x + rnd(-8, 8), b.z + rnd(-4, 8)); m.mode = 'swarm'; m.sp = rnd(8, 12); m.minion = true; } }
          b.g.ring.rotation.y += dt * 1.5; break; }
    }
  }

  // ---------------------------------------------------------------- contact: what the car did to it, or it did to the car
  function contact(b) { if (b.dead || b.under || b.latched) return; if (PH.set || PH.rail) return; const yo = b.yOff || 0; const by = b.y + yo;
    const near = Math.abs(PH.x - b.x) < b.r + 1.1 && Math.abs(PH.z - b.z) < b.len * .5 + 1.6 && PH.y < by + b.h + 2.4 && PH.y > by - 2.2; if (!near) return;
    const how = method({ ...b, y: by }), kills = b.spec.kill, m = b.mode;
    if (m === 'swarm' || m === 'drop') { if (b.spec.armour && how === 'RAM') { bounce(b); b.z -= 6; return; } if (b.spec.shift) { const want = ['RAM', 'SIDESWIPE', 'STOMP'][Math.floor(((b.t + b.ph) % 3))]; if (how !== want && how !== 'RAM') { } }
      if (speed() > 18 || how !== 'RAM') { kill(b, how); return; } if ((PH.latch_n || 0) < 3) { b.latched = true; b.lx = rnd(-1, 1); b.lz = rnd(-1.5, 1); PH.latch_n = (PH.latch_n || 0) + 1; try { d.look('latch'); } catch (e) { } } else kill(b, how); return; }
    if (m === 'carpet') { if (how === 'STOMP' && !b.carpet.popped) { b.carpet.popped = true; for (const o of b.carpet.bits) kill(o, 'STOMP'); return; } drag(.995); kill(b, 'RAM'); return; }
    if (m === 'ridge') { if (how === 'STOMP') { hurt(b, 'STOMP'); PH.vy = Math.max(PH.vy, 6); return; } if (speed() > 34) { PH.vy = Math.max(PH.vy, 12); PH.grounded = false; try { d.sfx('boing'); } catch (e) { } } else { drag(.7); shove(Math.sign(PH.x - b.x) || 1, 9); } b.hitT = .8; return; }
    if (m === 'leader' && how === 'RAM' && PH.z > b.z) { /* it ran into your back after a brake-check */ hurt(b, 'BAIT'); return; }
    if (m === 'wing' && how === 'SIDESWIPE') { b.shoveV = Math.sign(PH.vx) * 14; hurt(b, 'SIDESWIPE'); PH.vx *= .5; return; }
    if (m === 'fly' && !PH.grounded) { hurt(b, 'STOMP'); PH.vy = Math.max(PH.vy, 5); return; }
    if (m === 'sysadmin') { if (how === 'STOMP' || (b.crouch || 0) > .7) { const q = b.masts.find((q) => q.up && Math.abs(PH.x - (b.x + q.nm.position.x * b.sc)) < 4); if (q) { q.up = false; q.nm.setEnabled(false); try { d.fx('blast', [PH.x, PH.y, PH.z]); d.sfx('boom'); } catch (e) { } PH.vy = 8; return; } } if (b.cores && how === 'RAM') { hurt(b, 'RAM'); bounce(b); return; } bounce(b); return; }
    if (m === 'brood') { if ((b.low || 0) > .7 && !b.nodeHit && Math.abs(PH.x - b.x) < 4.5 && Math.abs(PH.z - b.z) < 5) { b.nodeHit = true; nodeBreak(b); if (!PH.grounded) PH.vy = Math.max(PH.vy, 6); } return; }
    if (m === 'sphinx') { if ((b.bow || 0) > .7 && !b.headHit && Math.abs(PH.x - b.x) < 5) { b.headHit = true; hurt(b, 'RAM'); drag(.85); } return; }
    if (m === 'bore') return;
    if (kills.includes(how)) { hurt(b, how); if (how === 'RAM' || how === 'SIDESWIPE') { PH.vx *= .7; } if (m === 'chase') { b.over = false; b.z = PH.z + 14; } return; }
    bounce(b); if (m === 'lure') { b.z -= 10; } }
  function nodeBreak(b) { b.node--; hurt(b, 'NODE', 3); for (const o of LIVE) if (o.minion && !o.dead) o.blind = 4; try { d.look('node'); } catch (e) { } }

  // ---------------------------------------------------------------- frame
  function step(dt, live) { DT = dt; if (!live) return; if (BQ.length) BQ.shift()(); director();
    for (const r of RACKS) { r.g.halo.rotation.y += dt * 2; r.g.halo.scaling.setAll(1 + .08 * Math.sin(performance.now() / 160)); if (!r.used && Math.abs(PH.z - r.z) < 2.4 && Math.abs(PH.x - r.x) < r.g.r + .8 && !PH.set) { r.used = true; fire(salvo(), PH.boost_t > 0); r.R.setEnabled(false); } }
    for (let i = RACKS.length - 1; i >= 0; i--) if (RACKS[i].z > PH.z + 30) { RACKS[i].R.dispose(false, true); RACKS.splice(i, 1); }
    for (let i = ROCKETS.length - 1; i >= 0; i--) { const k = ROCKETS[i]; k.t += dt; let tx, ty, tz; if (k.tg && !k.tg.dead) { tx = k.tg.x; ty = k.tg.y + (k.tg.yOff || 0) + k.tg.h * .55; tz = k.tg.z; } else { k.tg = LIVE.find((b) => !b.dead && !b.under && PH.z - b.z < 170 && b.z < PH.z) || null; tx = k.x + k.vx * .1; ty = k.y; tz = k.z + k.vz * .1; }
      const dx = tx - k.x, dy = ty - k.y, dz = tz - k.z, dl = Math.hypot(dx, dy, dz) || 1, sp = 70 + k.t * 30, turn = Math.min(1, dt * (3 + k.t * 4)); k.vx += (dx / dl * sp - k.vx) * turn; k.vy += (dy / dl * sp - k.vy) * turn; k.vz += (dz / dl * sp - k.vz) * turn;
      k.x += k.vx * dt; k.y += k.vy * dt; k.z += k.vz * dt; k.m.position.set(k.x, k.y, k.z); k.m.lookAt(new B.Vector3(k.x - k.vx, k.y - k.vy, k.z - k.vz)); if (k.ring && k.tg) { k.ring.position.set(k.tg.x, ty, k.tg.z); k.ring.rotation.x = Math.PI / 2; k.ring.scaling.setAll(1 + .15 * Math.sin(k.t * 20)); }
      if ((k.tg && !k.tg.dead && dl < 2.5) || k.t > 4) { if (k.tg && !k.tg.dead && dl < 2.5) { const b = k.tg; if (b.mode === 'sysadmin') { const q = b.masts.find((q) => q.up); if (q) { q.up = false; q.nm.setEnabled(false); } else hurt(b, 'ROCKETS'); } else if (b.mode === 'brood') nodeBreak(b); else if (b.mode === 'sphinx') { if (b.eyes > .2) hurt(b, 'ROCKETS'); } else hurt(b, 'ROCKETS'); try { d.fx('blast', [k.x, k.y, k.z]); } catch (e) { } }
        k.m.dispose(); if (k.ring) k.ring.dispose(); ROCKETS.splice(i, 1); } }
    for (let i = LIVE.length - 1; i >= 0; i--) { const b = LIVE[i]; b.t += dt; b.hitT = Math.max(0, b.hitT - dt); b.blind = Math.max(0, b.blind - dt);
      if (b.dead) { b.fall += dt; b.R.scaling.setAll(b.sc * Math.max(0, 1 - b.fall * 2.2)); b.R.rotation.y += dt * 9; if (b.fall > .5) { b.R.dispose(false, true); if (b.ridge) b.ridge.dispose(); if (b.grid) b.grid.dispose(false, true); if (b.spec.regen && !b.minion && !b.respawned && mastNear(b)) { const n = make(b.spec, b.x, b.z - 4); n.mode = 'swarm'; n.sp = 8; n.respawned = true; } LIVE.splice(i, 1); } continue; }
      behave(b, dt); if (b.gone) { b.R.dispose(false, true); if (b.ridge) b.ridge.dispose(); if (b.grid) b.grid.dispose(false, true); LIVE.splice(i, 1); continue; }
      if (b.mode !== 'swarm' || !b.latched) b.y = ground(b.x, b.z);
      const yo = (b.mode === 'drop' || b.mode === 'fly') ? (b.yOff || 0) : b.mode === 'sysadmin' ? -10 * b.sc * (b.crouch || 0) : b.mode === 'sphinx' ? -12 * b.sc * (b.bow || 0) : (b.g.hover ? 1.2 + Math.sin(b.t * 2 + b.ph) * .4 : 0), up = b.mode === 'ridge' ? -b.h * (1 - (b.up || 0)) : 0;
      b.R.position.set(b.x, b.y + yo + up, b.z); const hd = Math.atan2(-(b.vx || 0), -1); b.R.rotation.y = b.mode === 'swarm' && !b.latched ? Math.atan2(PH.x - b.x, b.z - PH.z) + Math.PI : 0;
      if (b.spec.shift) { const c = [[1, .69, .13], [.22, .91, 1], [.49, 1, .54]][Math.floor(((b.t + b.ph) % 3))]; if (b.g.tip) b.g.tip.material.emissiveColor.set(...c); }
      if (b.g.legs) for (const L of b.g.legs) L.L.rotation.x = Math.sin(b.t * (b.g.quad ? 14 : 22) + L.i * 1.4 + (L.s > 0 ? Math.PI : 0)) * .25;
      if (b.hitT > 0) b.R.scaling.setAll(b.sc * (1 + .15 * Math.sin(b.hitT * 40)));
      if (b.tell && b.g.lr) { b.g.lr.material.emissiveColor.set(1, .2, .25); b.g.lb.material.emissiveColor.set(1, .2, .25); } else if (b.g.lr) { const f = Math.sin(b.t * 14) > 0; b.g.lr.material.emissiveColor.set(f ? 1 : .2, .2, .25); b.g.lb.material.emissiveColor.set(.3, .6, f ? .2 : 1); }
      contact(b); }
    for (let i = CARPETS.length - 1; i >= 0; i--) if (CARPETS[i].z1 > PH.z + 20) CARPETS.splice(i, 1);
    for (let i = WALLS.length - 1; i >= 0; i--) { const w = WALLS[i]; if (!w.hit && Math.abs(PH.z - w.z) < 1.6 && !PH.set) { for (const s of w.segs) if (Math.abs(PH.x - s.x) < 2) { w.hit = true; drag(.72); shove(Math.sign(PH.x - s.x) || 1, 7); try { d.sfx('thwack'); d.fx('orb', [s.x, PH.y + 1, w.z]); } catch (e) { } s.m.dispose(); break; } }
      if (w.z > PH.z + 25) { for (const s of w.segs) s.m.dispose(); WALLS.splice(i, 1); } }
  }
  const mastNear = (b) => LIVE.some((o) => o.mode === 'mast' && !o.dead && Math.abs(o.z - b.z) < 160);
  // PORTRAIT STUDIO (owner 2026-11-27, the Trip Guide): set any machine on the road in front of the camera, three-quarters on, warning lights lit, for a menacing still
  function pose(name, turn = .45, dist = null) { const spec = ALLSPEC.find((r) => r.name.toLowerCase() === String(name).toLowerCase()); if (!spec) return null; const cam = (d.cam && d.cam()) || scene.activeCamera, cp = cam.globalPosition, f = cam.getDirection(new B.Vector3(0, 0, -1));
    const R = new B.TransformNode('pose', scene), g = BUILD[spec.model](R, spec.v), sc = g.scale || 1; R.scaling.setAll(sc); const FR = { brood: 62, sphinx: 36, mast: 30, sysadmin: 30, bore: 26 }, k = dist ?? FR[spec.model] ?? (g.len * sc < 4 ? 4.4 : (g.len + g.h) * sc * .5 + 3), x = cp.x + f.x * k, z = cp.z + f.z * k;          /* (framing by size: small ones close, giants far enough to fit) */
    R.position.set(x, ground(x, z) + (spec.model === 'spotter' ? 1.3 : g.hover ? 2.2 : 0), z); R.rotation.y = Math.atan2(-(cp.x - x), -(cp.z - z)) + turn;
    if (g.tip && g.tip.material) g.tip.material.emissiveColor.set(1, 1, 1); if (g.lr) { g.lr.material.emissiveColor.set(1, .2, .25); g.lb.material.emissiveColor.set(.3, .6, 1); }
    if (g.legs) for (const L of g.legs) L.L.rotation.x = Math.sin(L.i * 1.4 + (L.s > 0 ? Math.PI : 0)) * .25; return R; }
  /* WARM-UP (owner 2026-11-27): build this world's machines and a rack once while the level loads and compile their materials, so the first one on the road
     never stalls a frame; then throw the copies away (the materials stay cached). */
  { try { for (const spec of ROS.concat([{ model: 'rack' }])) { const R = new B.TransformNode('warm', scene); BUILD[spec.model](R, spec.v); for (const m of R.getChildMeshes()) { if (m.material && m.material.forceCompilation) m.material.forceCompilation(m); } R.dispose(false, false); } } catch (e) { console.warn('beasts warm-up', e); } }
  return { pose, step, LIVE, LOG, RACKS, ROSTER, DIR, spawn: (k) => { const s = ROS.find((r) => r.k === k || r.name === k) || REG[0]; ENC[s.k](s); return s.name; }, rack: (z) => rackAt(PH.z - (z || 60)), fire: () => fire(salvo(), false) };
}
