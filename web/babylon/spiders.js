// SKITTERS (owner 2026-11-27): little robot spiders swarm the road, climb onto your windscreen from the edges inward and pile up across your view.
// The cure is a storm cloud on the driving line: just before you reach it a huge lightning bolt (a new shape every time) cracks down with a thunder boom,
// then rain sheets the glass and washes them off. Gentle stakes: they only cost you view, never speed.
//   createSpiders(d).step(dt, now) every frame. d: { B, scene, PH, th, trailX, inTunZ, tier (0..7), pal: { rim, rim2, bolts: [[r,g,b]...] }, audio(), onStrike(), onWash(n), live() }
// One draw call per swarm: the legs walk in the vertex shader (alternating tetrapod gait), each spider with its own phase.

export function createSpiders(d) {
  const { B, scene, PH } = d, clamp = (v, a, b) => Math.max(a, Math.min(b, v)), rnd = (a, b) => a + Math.random() * (b - a), pick = (a) => a[Math.floor(Math.random() * a.length)];
  const tier = clamp(d.tier | 0, 0, 7), V3 = (a) => new B.Vector3(a[0], a[1], a[2]);

  // ---------------------------------------------------------------- the spider mesh (legs tagged for the shader)
  function geo() {
    const P = [], N = [], L = [], I = [];
    const quad = (a, b, c, e, n, tg) => { const o = P.length / 3; for (const [q, t] of [a, b, c, e]) { P.push(q[0], q[1], q[2]); N.push(n[0], n[1], n[2]); L.push(tg[0], tg[1], t, tg[3]); } I.push(o, o + 1, o + 2, o, o + 2, o + 3); };
    const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]], add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
    const cr = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]], nr = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
    const tube = (a, b, th, tg) => { const dd = nr(sub(b, a)); let u = cr(dd, [0, 1, 0]); u = Math.hypot(...u) < .01 ? [1, 0, 0] : nr(u); const v = nr(cr(u, dd)), U = mul(u, th), Vv = mul(v, th);
      const c = (p, su, sv) => add(add(p, mul(U, su)), mul(Vv, sv)), sx = [-1, 1, 1, -1], sy = [-1, -1, 1, 1], A = [0, 1, 2, 3].map((k) => c(a, sx[k], sy[k])), Bq = [0, 1, 2, 3].map((k) => c(b, sx[k], sy[k]));
      for (let k = 0; k < 4; k++) { const k2 = (k + 1) % 4, n = nr(add(mul(u, sx[k] + sx[k2]), mul(v, sy[k] + sy[k2]))); quad([A[k], 0], [A[k2], 0], [Bq[k2], 1], [Bq[k], 1], n, tg); } };
    const blob = (c, r, tag, seg = 10) => { const o = P.length / 3; for (let i = 0; i <= seg; i++) { const t = Math.PI * i / seg; for (let j = 0; j <= seg; j++) { const p = 2 * Math.PI * j / seg, n = [Math.sin(t) * Math.cos(p), Math.cos(t), Math.sin(t) * Math.sin(p)]; P.push(c[0] + n[0] * r[0], c[1] + n[1] * r[1], c[2] + n[2] * r[2]); N.push(...n); L.push(-1, 0, 0, tag); } }
      for (let i = 0; i < seg; i++) for (let j = 0; j < seg; j++) { const a = o + i * (seg + 1) + j, b = a + seg + 1; I.push(a, b, a + 1, b, b + 1, a + 1); } };
    blob([0, .16, .26], [.21, .15, .3], 0); blob([0, .15, -.06], [.15, .1, .16], 0); blob([0, .29, .2], [.05, .07, .05], 3, 6);
    for (const ex of [-.075, .075]) { blob([ex, .29, -.17], [.08, .08, .07], 2, 10); blob([ex + ex * .1, .36, -.2], [.04, .014, .04], 4, 8); }          /* (googly eyes: big white, pupils that wobble) */
    for (const s of [-1, 1]) for (let i = 0; i < 4; i++) { const li = (s < 0 ? 0 : 4) + i, hip = [s * .1, .15, -.14 + i * .085], knee = [s * .36, .36, -.24 + i * .16], foot = [s * .62, 0, -.42 + i * .28]; tube(hip, knee, .018, [li, 0, 0, 1]); tube(knee, foot, .013, [li, 1, 0, 1]); }
    const vd = new B.VertexData(); vd.positions = P; vd.normals = N; vd.indices = I; return { vd, L };
  }
  if (!B.Effect.ShadersStore.skitVertexShader) {
    B.Effect.ShadersStore.skitVertexShader = `precision highp float;
attribute vec3 position; attribute vec3 normal; attribute vec4 leg; attribute float phase; attribute vec2 lean;
#include<instancesDeclaration>
uniform mat4 viewProjection; uniform float uAmp;
varying vec3 vN; varying vec3 vW; varying vec4 vLeg;
void main(){
  #include<instancesVertex>
  vec3 p = position; float ph = phase;
  if (leg.w > .5 && leg.w < 1.5) { float s = leg.x < 3.5 ? 0. : 1., i = mod(leg.x, 4.), g = mod(i + s, 2.), q = ph + g * 3.14159 + i * .35;
    float k = leg.y < .5 ? leg.z * .4 : .4 + leg.z * .6; p.z += sin(q) * .15 * k * uAmp; p.y += max(0., cos(q)) * .13 * k * uAmp; p.x += (s * 2. - 1.) * max(0., cos(q)) * .03 * k * uAmp;
    float hold = leg.y < .5 ? 1. - .55 * leg.z : .45 - .45 * leg.z; p.xz += lean * hold; p.y += length(lean) * .25 * hold; }          /* (legs hold tight: the hip goes with the body, the foot stays put) */
  else { p.xz += lean; p.y += length(lean) * .25; p.y += .014 * sin(ph * 2.) * uAmp; p.x += .01 * sin(ph) * uAmp; if (leg.w > 3.5) { p.x += sin(ph * .73) * .022; p.y += cos(ph * 1.11) * .018; } }
  vec4 w = finalWorld * vec4(p, 1.); vW = w.xyz; vN = normalize(mat3(finalWorld) * normal); vLeg = leg; gl_Position = viewProjection * w; }`;
    B.Effect.ShadersStore.skitFragmentShader = `precision highp float;
varying vec3 vN; varying vec3 vW; varying vec4 vLeg; uniform vec3 uCam, uRim, uRim2; uniform float uT, uWet;
void main(){ vec3 n = normalize(vN), v = normalize(uCam - vW); float fr = pow(1. - abs(dot(n, v)), 2.2), l = max(dot(n, normalize(vec3(.3, 1., .4))), 0.);
  vec3 c = vec3(.03, .035, .05) + vec3(.13, .14, .18) * l + mix(uRim, uRim2, .5 + .5 * sin(vW.x * 2. + vW.z * 1.3 + uT)) * fr * 1.5;
  c += pow(max(dot(reflect(-v, n), normalize(vec3(.3, 1., .4))), 0.), 24.) * (.6 + 1.4 * uWet);
  if (vLeg.w > 3.5) c = vec3(.02, .02, .03);
  else if (vLeg.w > 2.5) c = uRim2 * (1.4 + .8 * sin(uT * 6. + vW.z));
  else if (vLeg.w > 1.5) c = vec3(1.05, 1.05, 1.) * (.85 + .25 * l) + uRim * fr * .3;
  else if (vLeg.w > .5) { c += uRim * .9 * smoothstep(.82, 1., vLeg.z) * step(.5, vLeg.y); c += uRim * .5 * (1. - smoothstep(0., .12, abs(vLeg.z - (1. - step(.5, vLeg.y))))); }
  gl_FragColor = vec4(c, 1.); }`;
    B.Effect.ShadersStore.skitBoltVertexShader = `precision highp float; attribute vec3 position; attribute vec3 normal; uniform mat4 world, viewProjection; varying vec3 vN, vW; void main(){ vec4 w = world * vec4(position, 1.); vW = w.xyz; vN = normalize(mat3(world) * normal); gl_Position = viewProjection * w; }`;
    B.Effect.ShadersStore.skitBoltFragmentShader = `precision highp float; varying vec3 vN, vW; uniform vec3 uCam, uCol; uniform float uA, uCore;
void main(){ float f = abs(dot(normalize(vN), normalize(uCam - vW))), k = pow(f, uCore > .5 ? 1.2 : 2.6); vec3 c = mix(uCol, vec3(1.), uCore > .5 ? pow(f, 3.) : 0.) * (uCore > .5 ? 1. : .9); gl_FragColor = vec4(clamp(c, 0., 1.), clamp(k * uA, 0., 1.)); }          /* (never past white: the picture pass turns overflow black) */`;
    B.Effect.ShadersStore.skitGlassVertexShader = `precision highp float; attribute vec3 position; attribute vec2 uv; uniform mat4 worldViewProjection; varying vec2 vUV; void main(){ vUV = uv; gl_Position = worldViewProjection * vec4(position, 1.); }`;
    B.Effect.ShadersStore.skitGlassFragmentShader = `precision highp float; varying vec2 vUV; uniform float uT, uRain, uFlash, uAsp; uniform vec3 uRainC, uFlashC;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void main(){ vec2 p = vec2((vUV.x - .5) * uAsp, vUV.y - .5); float a = 0.; vec3 c = vec3(0.);
  if (uRain > .01) { float col = floor(p.x * 95.), sp = 1.8 + 2.4 * h(vec2(col, 3.)), y = fract(vUV.y * 1.5 + uT * sp + h(vec2(col, 7.))), on = step(.5, h(vec2(col, 1.)));
    float streak = smoothstep(.0, .015, y) * (1. - smoothstep(.015, .34, y)) * on, bead = smoothstep(.012, .0, length(vec2(fract(p.x * 95.) - .5, (y - .012) * 20.)) - .2) * on;
    vec2 g = p * 14. + vec2(0., floor(uT * 3.)); float drop = smoothstep(.12, .05, length(fract(g) - .5 - (vec2(h(floor(g)), h(floor(g) + 5.)) - .5) * .6)) * step(.7, h(floor(g) + 9.));
    float ra = (streak * .55 + bead * .6 + drop * .45) * uRain; c = uRainC; a = ra; }
  if (uFlash > .01) { float edge = smoothstep(.2, .9, length(p) / max(uAsp * .5, .5)); c = mix(c, uFlashC, uFlash / max(a + uFlash, .001)); a = max(a, uFlash * (.28 + .22 * edge)); }
  gl_FragColor = vec4(c, a); }`;
  }
  const mkMat = (nm) => { const m = new B.ShaderMaterial(nm, scene, 'skit', { attributes: ['position', 'normal', 'leg', 'phase', 'lean'], uniforms: ['world', 'viewProjection', 'uAmp', 'uCam', 'uRim', 'uRim2', 'uT', 'uWet'] });
    m.setVector3('uRim', V3(d.pal.rim)); m.setVector3('uRim2', V3(d.pal.rim2)); m.setFloat('uAmp', 1); m.setFloat('uWet', 0); m.backFaceCulling = false; return m; };
  function swarm(nm, max) { const { vd, L } = geo(), m = new B.Mesh(nm, scene); vd.applyToMesh(m, true); m.setVerticesData('leg', L, false, 4); m.material = mkMat(nm + 'M'); m.alwaysSelectAsActiveMesh = true; m.isPickable = false; m.doNotSyncBoundingInfo = true;
    const mat = new Float32Array(16 * max), ph = new Float32Array(max), ln = new Float32Array(2 * max); m.thinInstanceSetBuffer('matrix', mat, 16, false); m.thinInstanceSetBuffer('phase', ph, 1, false); m.thinInstanceSetBuffer('lean', ln, 2, false); m.thinInstanceCount = 0; return { m, mat, ph, ln, max }; }

  const ROAD = swarm('skitRoad', 360), GL = swarm('skitGlass', 240); GL.m.material.setFloat('uAmp', .8);
  const glassNode = new B.TransformNode('skitGlassNode', scene); GL.m.parent = glassNode; GL.m.renderingGroupId = 1;
  const GZ = .6;
  const plane = B.MeshBuilder.CreatePlane('skitGlassPl', { size: 1 }, scene), gm = new B.ShaderMaterial('skitGlassM', scene, 'skitGlass', { attributes: ['position', 'uv'], uniforms: ['worldViewProjection', 'uT', 'uRain', 'uFlash', 'uAsp', 'uRainC', 'uFlashC'], needAlphaBlending: true });
  gm.backFaceCulling = false; plane.material = gm; plane.parent = glassNode; plane.position.z = -(GZ - .02); plane.renderingGroupId = 1; plane.isPickable = false; gm.setFloat('uRain', 0); gm.setFloat('uFlash', 0);
  gm.setVector3('uRainC', new B.Vector3(.7, .85, 1)); gm.setVector3('uFlashC', new B.Vector3(.9, .95, 1));
  const half = (cam) => { const hh = GZ * Math.tan((cam.fov || .9) / 2), eng = scene.getEngine(); return [hh * eng.getRenderWidth() / Math.max(1, eng.getRenderHeight()), hh]; };

  // ---------------------------------------------------------------- state
  const RS = [], GS = [], CL = [], BOLTS = [], RINGS = [], ZAP = [], SLO = { x: 0, y: 0, vx: 0, vy: 0, h: null, sp: 0 }, S = { nextZap: 8, nextWave: 6, nextStorm: 18, rain: 0, rainC: [.7, .85, 1], flash: 0, flashC: [.9, .95, 1], wet: 0, t: 0, washes: 0, attached: 0 };
  const waveN = 10 + tier * 3, waveGap = [9, 8, 7.5, 7, 6.5, 6, 5.5, 5][tier];
  const M = new B.Matrix(), Q = new B.Quaternion(), SC = new B.Vector3(), TR = new B.Vector3();
  const ground = (x, z) => { try { const g = d.th(x, z); return Number.isFinite(g) ? g : PH.y; } catch (e) { return PH.y; } };

  function spawnWave() { const grp = { zaps: 0 }, ahead = Math.random() < .6; for (let k = 0; k < waveN && RS.length < ROAD.max; k++) { const side = Math.random() < .5 ? -1 : 1, rz = ahead ? -rnd(30, 70) : rnd(25, 50);
      RS.push({ x: PH.x + side * rnd(4, 9), z: PH.z + rz, rz, side, wide: rnd(1.5, 4.5), catch: rnd(6, 10) + tier * .6, ph: rnd(0, 6.28), s: rnd(1.2, 1.8), h: 0, wob: rnd(0, 6.28), grp, tumble: 0, back: 0 }); } }          /* (they run with you and gain a little each second) */
  function attach(cam) { if (GS.length >= GL.max) return; const [hw, hh] = half(cam), fill = GS.length / GL.max, near = GS.length && Math.random() < .7 ? GS[Math.floor(Math.random() * GS.length)] : null;
    const a = near ? Math.atan2(near.ty / hh, near.tx / hw) + rnd(-.25, .25) : rnd(0, 6.28), r = clamp(1.05 - .42 * Math.pow(fill, 1.3) + rnd(-.04, .06), .62, 1.08);          /* (owner 2026-11-28: they gather round the very edge of the view and crowd in slowly; the middle stays clear) */
    const tx = Math.cos(a) * r, ty = Math.sin(a) * r; GS.push({ x: Math.cos(a) * 1.25, y: Math.sin(a) * 1.25, tx, ty, ph: rnd(0, 6.28), s: rnd(.13, .2), h: 0, st: 'in', vx: 0, vy: 0, spin: 0, idle: rnd(1, 4), life: rnd(30, 55) }); S.attached++; }          /* (each one dies off after half a minute or so and falls away; what they do later is still to be designed) */

  // ---------------------------------------------------------------- the storm cloud
  const cloudMat = (tint) => { const m = new B.StandardMaterial('skitCloudM', scene); m.diffuseColor = new B.Color3(.2, .22, .3); m.emissiveColor = new B.Color3(.12 + tint[0] * .18, .13 + tint[1] * .18, .2 + tint[2] * .2); m.specularColor = B.Color3.Black();
    const f = new B.FresnelParameters(); f.leftColor = new B.Color3(tint[0] * .9 + .1, tint[1] * .9 + .1, tint[2] * .9 + .2); f.rightColor = new B.Color3(.16, .17, .26); f.power = 1.4; m.emissiveFresnelParameters = f; return m; };
  function spawnStorm(zAhead) { const z = PH.z - zAhead, x = d.trailX(z), tint = pick(d.pal.bolts), g = new B.TransformNode('skitStorm', scene), m = cloudMat(tint), puffs = [];
    for (let k = 0; k < 14; k++) { const s = B.MeshBuilder.CreateSphere('skitPuff', { diameter: rnd(5, 10), segments: 10 }, scene); s.material = m; s.parent = g; s.isPickable = false; s.position.set(rnd(-9, 9), rnd(-1.5, 2.5), rnd(-5, 5)); puffs.push(s); }
    const rain = B.MeshBuilder.CreateBox('skitRain', { width: .05, height: 2.2, depth: .05 }, scene), rm = new B.StandardMaterial('skitRainM', scene); rm.emissiveColor = new B.Color3(tint[0] * .7, tint[1] * .8, tint[2]); rm.disableLighting = true; rm.alpha = .5; rain.material = rm; rain.parent = g; rain.isPickable = false; rain.alwaysSelectAsActiveMesh = true;
    const drops = []; for (let k = 0; k < 140; k++) drops.push({ x: rnd(-10, 10), y: rnd(-12, 0), z: rnd(-6, 6) }); const rb = new Float32Array(16 * drops.length); rain.thinInstanceSetBuffer('matrix', rb, 16, false);
    const gy = ground(x, z); g.position.set(x, gy + 12, z); CL.push({ g, m, puffs, rain, rb, drops, x, z, gy, tint, struck: false, done: false, flick: 0, wob: rnd(0, 6) }); }

  // ---------------------------------------------------------------- the bolt: a new shape every strike (midpoint displacement + branches)
  function jag(a, b, rough, depth, out) { if (depth <= 0) { out.push(b); return; } const m = a.add(b).scale(.5), len = B.Vector3.Distance(a, b); m.x += rnd(-1, 1) * len * rough; m.z += rnd(-1, 1) * len * rough * .6; m.y += rnd(-.2, .2) * len * rough;
    jag(a, m, rough, depth - 1, out); jag(m, b, rough, depth - 1, out); }
  function strike(cl) {
    const col = cl.tint, hz = cl.z + rnd(4, 14), hx = cl.x + rnd(-7, 7), top = new B.Vector3(cl.x + rnd(-22, 22), cl.gy + rnd(75, 100), cl.z - rnd(0, 20)), hit = new B.Vector3(hx, ground(hx, hz) + .3, hz);          /* (sky to road just in front of the cloud while you are 70 m out: the whole bolt fills the screen) */
    const path = [top]; jag(top, hit, rnd(.22, .34), 6, path);
    const bm = (core) => { const m = new B.ShaderMaterial('skitBoltM', scene, 'skitBolt', { attributes: ['position', 'normal'], uniforms: ['world', 'viewProjection', 'uCam', 'uCol', 'uA', 'uCore'] }); m.setVector3('uCol', V3(col)); m.setFloat('uA', 1); m.setFloat('uCore', core ? 1 : 0);
      m.alphaMode = B.Engine.ALPHA_COMBINE; m.needAlphaBlending = () => true; m.disableDepthWrite = true; m.backFaceCulling = false; return m; };          /* (additive light: a white-hot core fading into the strike colour, a soft halo with no edge) */
    const mat = bm(true), glow = bm(false);
    const parts = [B.MeshBuilder.CreateTube('skitBolt', { path, radius: rnd(1.4, 2.2), tessellation: 6 }, scene), B.MeshBuilder.CreateTube('skitBoltH', { path, radius: rnd(4.5, 6), tessellation: 10 }, scene)];
    parts[0].material = mat; parts[1].material = glow;
    const nb = 2 + Math.floor(Math.random() * 4); for (let k = 0; k < nb; k++) { const i0 = 5 + Math.floor(Math.random() * (path.length - 20)), a = path[i0], len = rnd(25, 70), dir = new B.Vector3(rnd(-1, 1), -rnd(.6, 1.2), rnd(-.6, .6)).normalize(), bp = [a]; jag(a, a.add(dir.scale(len)), .3, 4, bp);
      const br = B.MeshBuilder.CreateTube('skitBoltB', { path: bp, radius: rnd(.35, .65), tessellation: 5 }, scene); br.material = mat; parts.push(br); }
    for (const p of parts) { p.isPickable = false; p.alwaysSelectAsActiveMesh = true; }
    BOLTS.push({ parts, mats: [mat, glow], t: 0, life: rnd(.7, .95), flick: [rnd(.1, .14), rnd(.18, .22), rnd(.3, .36)] });
    S.flash = 1; S.flashC = [Math.min(1, col[0] * .5 + .55), Math.min(1, col[1] * .5 + .55), Math.min(1, col[2] * .5 + .55)]; thunder(); try { d.onStrike && d.onStrike(col, [hit.x, hit.y, hit.z]); } catch (e) { } }

  // ---------------------------------------------------------------- ZAPPERS: hit one and the chasing spiders get blasted back (miss them and they catch you)
  const zapM = new B.StandardMaterial('skitZapM', scene); zapM.emissiveColor = new B.Color3(.45, .9, 1); zapM.disableLighting = true;
  const zapC = new B.StandardMaterial('skitZapC', scene); zapC.emissiveColor = new B.Color3(1, .95, .55); zapC.disableLighting = true;
  function spawnZap() { const z = PH.z - rnd(130, 160), x = d.trailX(z) + rnd(-5, 5), g = new B.TransformNode('skitZap', scene), gy = ground(x, z);
    const orb = B.MeshBuilder.CreateSphere('zorb', { diameter: 1.8, segments: 14 }, scene); orb.material = zapM; orb.parent = g; orb.position.y = 2.4;
    const cage = []; for (let k = 0; k < 3; k++) { const r = B.MeshBuilder.CreateTorus('zcage', { diameter: 2.8 + k * .5, thickness: .09, tessellation: 40 }, scene); r.material = zapC; r.parent = g; r.position.y = 2.4; cage.push(r); }
    const post = B.MeshBuilder.CreateCylinder('zpost', { height: 1.6, diameter: .25 }, scene); post.material = zapC; post.parent = g; post.position.y = .8;
    for (const m of [orb, post, ...cage]) m.isPickable = false; g.position.set(x, gy, z); ZAP.push({ g, orb, cage, x, z, used: false }); }
  function zap(zp) { zp.used = true; zp.g.setEnabled(false); S.flash = .7; S.flashC = [.5, .95, 1]; buzz(); let n = 0;
    for (const s of RS) { const rel = s.z - PH.z; if (Math.abs(rel) < 55 && s.tumble <= 0) { s.tumble = rnd(.8, 1.4); s.back = rnd(30, 55); s.pop = Math.random() < .35; s.grp.zaps++; n++; } }
    const ring = B.MeshBuilder.CreateTorus('zring', { diameter: 3, thickness: .3, tessellation: 48 }, scene); ring.material = zapM; ring.position.set(PH.x, PH.y + .6, PH.z); ring.isPickable = false; RINGS.push({ ring, t: 0 });
    try { d.onZap && d.onZap(n, [zp.x, PH.y + 2, zp.z]); } catch (e) { } }
  function buzz() { try { const ac = d.audio && d.audio(); if (!ac) return; const t0 = ac.currentTime + .01, o = ac.createOscillator(), o2 = ac.createOscillator(), g = ac.createGain(), f = ac.createBiquadFilter();
      o.type = 'sawtooth'; o.frequency.setValueAtTime(rnd(110, 140), t0); o.frequency.exponentialRampToValueAtTime(40, t0 + .45); o2.type = 'square'; o2.frequency.setValueAtTime(rnd(1800, 2600), t0); o2.frequency.exponentialRampToValueAtTime(300, t0 + .3);
      f.type = 'bandpass'; f.frequency.value = 900; f.Q.value = .8; g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(.35, t0 + .01); g.gain.exponentialRampToValueAtTime(.001, t0 + .5);
      o.connect(f); o2.connect(f); f.connect(g); g.connect(ac.destination); o.start(t0); o2.start(t0); o.stop(t0 + .55); o2.stop(t0 + .55); } catch (e) { } }

  // ---------------------------------------------------------------- the boom (made here, different every time: a crack, a rolling boom and a sub)
  function thunder() { try { const ac = d.audio && d.audio(); if (!ac) return; const t0 = ac.currentTime + .02, out = ac.createGain(); out.gain.value = .55; out.connect(ac.destination);
      const noise = (dur) => { const n = Math.floor(ac.sampleRate * dur), buf = ac.createBuffer(1, n, ac.sampleRate), ch = buf.getChannelData(0); let b = 0; for (let i = 0; i < n; i++) { b = .97 * b + .03 * (Math.random() * 2 - 1); ch[i] = (Math.random() * 2 - 1) * .5 + b * 3; } const s = ac.createBufferSource(); s.buffer = buf; return s; };
      { const s = noise(.35), hp = ac.createBiquadFilter(), g = ac.createGain(); hp.type = 'highpass'; hp.frequency.value = rnd(900, 2200); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(.9, t0 + .004); g.gain.exponentialRampToValueAtTime(.001, t0 + rnd(.18, .3)); s.connect(hp); hp.connect(g); g.connect(out); s.start(t0); }
      { const dur = rnd(2.6, 4.2), s = noise(dur), lp = ac.createBiquadFilter(), g = ac.createGain(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(rnd(900, 1400), t0); lp.frequency.exponentialRampToValueAtTime(rnd(70, 120), t0 + dur * .8); lp.Q.value = .7;
        g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(1, t0 + .05); const rolls = 3 + Math.floor(Math.random() * 4); for (let k = 1; k <= rolls; k++) { const tk = t0 + .05 + dur * .75 * k / rolls; g.gain.linearRampToValueAtTime(rnd(.35, .8) * (1 - k / (rolls + 1.5)), tk); }
        g.gain.exponentialRampToValueAtTime(.001, t0 + dur); s.connect(lp); lp.connect(g); g.connect(out); s.start(t0 + rnd(0, .08)); }
      { const o = ac.createOscillator(), g = ac.createGain(); o.type = 'sine'; o.frequency.setValueAtTime(rnd(48, 62), t0); o.frequency.exponentialRampToValueAtTime(28, t0 + 1.4); g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(.8, t0 + .03); g.gain.exponentialRampToValueAtTime(.001, t0 + 1.6); o.connect(g); g.connect(out); o.start(t0); o.stop(t0 + 1.7); }
    } catch (e) { } }
  function rainSound(dur) { try { const ac = d.audio && d.audio(); if (!ac) return; const t0 = ac.currentTime + .02, n = Math.floor(ac.sampleRate * dur), buf = ac.createBuffer(1, n, ac.sampleRate), ch = buf.getChannelData(0); for (let i = 0; i < n; i++) ch[i] = Math.random() * 2 - 1;
      const s = ac.createBufferSource(), bp = ac.createBiquadFilter(), g = ac.createGain(); s.buffer = buf; bp.type = 'bandpass'; bp.frequency.value = 3200; bp.Q.value = .5; g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(.16, t0 + .3); g.gain.setValueAtTime(.16, t0 + dur - .8); g.gain.linearRampToValueAtTime(0, t0 + dur); s.connect(bp); bp.connect(g); g.connect(ac.destination); s.start(t0); } catch (e) { } }

  function wash(cl) { S.rain = 3.4; S.rainC = [Math.min(1, cl.tint[0] * .4 + .55), Math.min(1, cl.tint[1] * .4 + .6), Math.min(1, cl.tint[2] * .4 + .65)]; S.wet = 1; rainSound(3.4);
    const n = GS.filter((g) => g.st !== 'out').length; for (const g of GS) if (g.st !== 'out') { g.st = 'wait'; g.delay = rnd(0, .9); }
    S.washes++; try { d.onWash && d.onWash(n, cl.tint); } catch (e) { } }

  /* RAMP BLAST (owner 2026-11-28): leaving any ramp blows half of the spiders on the glass away, a few at a time over 3 seconds, the ones nearest the middle first.
     The half that hangs on is scattered back out to the edge of the windscreen. Every ramp halves them again. */
  function blowHalf() { const on = GS.filter((g) => g.st === 'in'); const n = Math.floor(on.length / 2); if (!n) return 0;
    on.sort((a, b) => Math.hypot(a.tx, a.ty) - Math.hypot(b.tx, b.ty));
    for (let k = 0; k < on.length; k++) { const g = on[k];
      if (k < n) { g.st = 'wait'; g.blow = true; g.delay = (k + Math.random()) / n * 3; }
      else { const a = Math.atan2(g.ty, g.tx) + rnd(-.3, .3), r = rnd(1, 1.08); g.tx = Math.cos(a) * r; g.ty = Math.sin(a) * r; g.idle = rnd(2, 5); } }
    return n; }

  // ---------------------------------------------------------------- per frame
  function step(dt, live) {
    const cam = (d.cam && d.cam()) || scene.activeCamera; if (!cam) return; S.t += dt; const t = S.t;
    if (glassNode.parent !== cam) glassNode.parent = cam;
    const cp = cam.globalPosition; for (const sw of [ROAD, GL]) { sw.m.material.setVector3('uCam', cp); sw.m.material.setFloat('uT', t); } GL.m.material.setFloat('uWet', S.wet);
    const go = live && !(d.inTunZ && d.inTunZ(PH.z, 60));
    if (go && t > S.nextWave) { spawnWave(); S.nextWave = t + waveGap * rnd(.8, 1.25); }
    const due = GS.length > 30 ? 14 : 34; if (go && t > S.nextStorm && !CL.some((c) => !c.done) && !(d.inTunZ && d.inTunZ(PH.z - 260, 80))) { spawnStorm(rnd(240, 300)); S.nextStorm = t + due * rnd(.9, 1.3); }
    if (GS.length > 30 && S.nextStorm - t > 12) S.nextStorm = t + rnd(4, 10);          /* (a full windscreen brings the storm sooner) */

    // road spiders run at your line and climb on as you pass
    let n = 0; const spd = Math.max(8, Math.hypot(PH.vx, PH.vz));
    for (let i = RS.length - 1; i >= 0; i--) { const s = RS[i], rel = s.z - PH.z, dx = PH.x - s.x;
      if (s.tumble > 0) { s.tumble -= dt; s.rz += s.back * dt; s.z = PH.z + s.rz; s.back *= Math.exp(-2 * dt); s.x += s.side * 4 * dt; s.h += dt * 14; s.ph += dt * 40; if (s.pop && s.tumble < .3) { RS.splice(i, 1); continue; } continue; }
      const giveUp = s.grp.zaps >= 2, vz = giveUp ? -spd * .55 : -(spd + s.catch * (rel > 0 ? 1 : -.9)), off = giveUp ? s.side * 18 : s.side * s.wide * clamp(Math.abs(rel) / 10, .15, 1);
      const tx = (PH.x + off + Math.sin(t * 3 + s.wob) * .8) - s.x, vx = clamp(tx * 2.2, -9, 9); s.x += vx * dt; s.rz += (giveUp ? spd * .45 : (rel > 0 ? -s.catch : s.catch * .9)) * dt; s.z = PH.z + s.rz; s.h = Math.atan2(vx, vz);          /* (moved relative to the car: they close in at the same rate at any frame rate) */ s.ph += (20 + s.catch) * dt;          /* (a readable scurry, not a blur, whatever the speed) */
      if (live && !giveUp && Math.abs(rel) < 1.8 && Math.abs(dx) < 2.4 && Math.abs(ground(s.x, s.z) - PH.y) < 3.5) {          /* (owner 2026-11-28: one in front of the car is smashed out of the way; from the side or behind it climbs on) */
        if (rel <= .4 && Math.abs(dx) < 1.5) { s.tumble = .7; s.pop = true; s.back = -(spd * .9 + 10); s.side = (Math.sign(s.x - PH.x) || 1) * 3.5; S.smashed = (S.smashed || 0) + 1; try { d.onSmash && d.onSmash([s.x, ground(s.x, s.z) + .4, s.z]); } catch (e) { } continue; }
        RS.splice(i, 1); attach(cam); continue; }
      if (rel > 120 || rel < -220 || (giveUp && Math.abs(s.x - PH.x) > 16)) { RS.splice(i, 1); continue; } }
    for (const s of RS) { SC.set(s.s, s.s, s.s); B.Quaternion.RotationYawPitchRollToRef(s.h, s.tumble > 0 ? s.h * 1.7 : 0, s.tumble > 0 ? s.h : 0, Q); TR.set(s.x, ground(s.x, s.z), s.z); B.Matrix.ComposeToRef(SC, Q, TR, M); M.copyToArray(ROAD.mat, n * 16); ROAD.ph[n] = s.ph; n++; }
    ROAD.m.thinInstanceCount = n; ROAD.m.thinInstanceBufferUpdated('matrix'); ROAD.m.thinInstanceBufferUpdated('phase');
    if (go && t > S.nextZap && RS.some((s) => s.tumble <= 0 && s.grp.zaps < 2)) { spawnZap(); S.nextZap = t + rnd(3.5, 6); }
    for (let i = ZAP.length - 1; i >= 0; i--) { const zp = ZAP[i]; zp.orb.scaling.setAll(1 + .12 * Math.sin(t * 13)); zp.cage.forEach((r, k) => { r.rotation.x = t * (1.3 + k * .4); r.rotation.z = t * (.9 + k * .5); });
      if (!zp.used && Math.abs(PH.z - zp.z) < 2.5 && Math.abs(PH.x - zp.x) < 2.9) zap(zp); if (zp.z > PH.z + 20) { zp.g.dispose(false, true); ZAP.splice(i, 1); } }
    zapM.emissiveColor.set(Math.random() < .2 ? .9 : .45, .9, 1);

    // storms: the bolt cracks down as you arrive (only on a line that will reach it), then you drive into the rain
    for (let i = CL.length - 1; i >= 0; i--) { const c = CL[i], dz = PH.z - c.z, dx = Math.abs(PH.x - c.x);
      c.g.position.y = c.gy + 12 + Math.sin(t * .8 + c.wob) * .6; for (const p of c.puffs) p.scaling.setAll(1 + .05 * Math.sin(t * 1.5 + p.position.x)); c.flick = Math.max(0, c.flick - dt * 3); if (Math.random() < dt * .8) c.flick = rnd(.5, 1);
      c.m.emissiveColor.set(.12 + c.tint[0] * (.18 + .7 * c.flick), .13 + c.tint[1] * (.18 + .7 * c.flick), .2 + c.tint[2] * (.2 + .8 * c.flick));
      c.drops.forEach((q, k) => { q.y -= dt * 24; if (q.y < -12) q.y = rnd(-1, 0); B.Matrix.TranslationToRef(q.x, q.y, q.z, M); M.copyToArray(c.rb, k * 16); }); c.rain.thinInstanceBufferUpdated('matrix');
      if (!c.struck && dz > 0 && dz < Math.max(72, spd * 1.7) && dx < 16) { c.struck = true; strike(c); }
      if (!c.done && dz < 4 && dz > -8 && dx < 12) { c.done = true; wash(c); }
      if (dz < -40) { c.g.dispose(false, true); c.m.dispose(); CL.splice(i, 1); } }
    for (let i = BOLTS.length - 1; i >= 0; i--) { const b = BOLTS[i]; b.t += dt; const on = b.t < b.flick[0] || (b.t > b.flick[1] && b.t < b.flick[2]) || (b.t > b.flick[2] + .05 && b.t < b.life * .8);
      for (const p of b.parts) p.isVisible = on; const cp2 = ((d.cam && d.cam()) || scene.activeCamera).globalPosition; for (const mm of b.mats) mm.setVector3('uCam', cp2); b.mats[1].setFloat('uA', 1 - b.t / b.life); if (b.t > b.life) { for (const p of b.parts) p.dispose(); for (const m of b.mats) m.dispose(); BOLTS.splice(i, 1); } }
    for (let i = RINGS.length - 1; i >= 0; i--) { const r = RINGS[i]; r.t += dt; r.ring.position.set(PH.x, ground(PH.x, PH.z) + .15, PH.z); r.ring.scaling.set(1 + r.t * 40, 1, 1 + r.t * 40); r.ring.visibility = Math.max(0, 1 - r.t / .6); if (r.t > .6) { r.ring.dispose(); RINGS.splice(i, 1); } }

    // the windscreen
    const [hw, hh] = half(cam); plane.scaling.set(hw * 2.4, hh * 2.4, 1); gm.setFloat('uAsp', hw / hh); gm.setFloat('uT', t);
    S.rain = Math.max(0, S.rain - dt); S.flash = Math.max(0, S.flash - dt * 2.6); S.wet = Math.max(0, S.wet - dt * .25);
    gm.setFloat('uRain', clamp(S.rain / .6, 0, 1)); gm.setVector3('uRainC', V3(S.rainC)); gm.setFloat('uFlash', S.flash * (.6 + .4 * Math.sin(t * 60) ** 2)); gm.setVector3('uFlashC', V3(S.flashC));
    { const h = PH.heading || 0, sp2 = spd; if (SLO.h == null) { SLO.h = h; SLO.sp = sp2; } let yr = (h - SLO.h) / Math.max(dt, 1e-3); yr = clamp(yr, -3, 3); const acc = (sp2 - SLO.sp) / Math.max(dt, 1e-3); SLO.h = h; SLO.sp = sp2;
      const tx = clamp(-yr * sp2 * .018, -.7, .7), ty = clamp(-acc * .012, -.35, .35) + (PH.grounded ? 0 : .12); SLO.vx += ((tx - SLO.x) * 38 - SLO.vx * 5.5) * dt; SLO.vy += ((ty - SLO.y) * 38 - SLO.vy * 5.5) * dt; SLO.x += SLO.vx * dt; SLO.y += SLO.vy * dt; }          /* (a spring on the car's turn and braking: they get flung and swing back) */
    let m = 0;
    for (let i = GS.length - 1; i >= 0; i--) { const g = GS[i];
      if (g.st === 'wait') { g.delay -= dt; g.ph += dt * 30; if (g.delay <= 0) { g.st = 'out'; if (g.blow) { const a = Math.atan2(g.y, g.x) + rnd(-.4, .4), v = rnd(1.6, 2.6); g.vx = Math.cos(a) * v; g.vy = Math.sin(a) * v + .4; g.spin = rnd(-14, 14); } else { g.vx = rnd(-.08, .08); g.vy = -rnd(.1, .4); g.spin = rnd(-5, 5); } } continue; }          /* (blown: flung off the glass outward, tumbling) */
      if (g.st === 'out') { g.vy -= 3.2 * dt; g.x += g.vx * dt; g.y += g.vy * dt; g.h += g.spin * dt; g.ph += dt * 24; if (Math.abs(g.y) > 1.5 || Math.abs(g.x) > 1.5) GS.splice(i, 1); continue; }
      g.life = (g.life || 40) - dt; if (g.life <= 0) { g.st = 'out'; g.vx = rnd(-.08, .08); g.vy = -rnd(.05, .2); g.spin = rnd(-6, 6); continue; }
      const dx = g.tx - g.x, dy = g.ty - g.y, dd = Math.hypot(dx, dy);
      if (dd > .006) { const v = Math.min(dd, 1.9 * dt); g.x += dx / dd * v; g.y += dy / dd * v; g.h = Math.atan2(dx * hw, -dy * hh); g.ph += dt * 26; }
      else { g.idle -= dt; g.ph += dt * 3; if (g.idle < 0) { g.idle = rnd(1.5, 5); g.tx = clamp(g.tx + rnd(-.05, .05), -1.1, 1.1); g.ty = clamp(g.ty + rnd(-.05, .05), -1.1, 1.1); const rr = Math.hypot(g.tx, g.ty), rmin = 1.05 - .42 * Math.pow(GS.length / GL.max, 1.3); if (rr < rmin && rr > 1e-3) { g.tx *= rmin / rr; g.ty *= rmin / rr; } } } }          /* (a wandering spider stays in the edge band) */
        for (const g of GS) { if (g.grip == null) g.grip = rnd(.6, 1.3); const s = g.s * hh, out = g.st === 'out';
      const wx = out ? 0 : SLO.x * hw * g.grip, wy = out ? 0 : SLO.y * hh * g.grip, ch = Math.cos(g.h), sh = Math.sin(g.h);          /* (the pull on this spider, in glass units) */
      let lx = (wx * ch + wy * sh) / s, lz = (wx * sh - wy * ch) / s; const ll = Math.hypot(lx, lz), cap = .42, k = ll > cap ? cap / ll : 1; lx *= k; lz *= k;          /* (its body leans up to a body-length; past that the feet let go) */
      const slip = Math.max(0, 1 - k), sx = SLO.x * g.grip * slip, sy = SLO.y * g.grip * slip;
      if (slip > .05) g.ph += dt * 45; else if (ll > .1) g.ph += dt * 4;          /* (legs scrabble when they slip) */
      GL.ln[m * 2] = lx; GL.ln[m * 2 + 1] = lz;
      B.Matrix.ScalingToRef(s, s, s, M); M.multiplyToRef(B.Matrix.RotationY(g.h), M); M.multiplyToRef(B.Matrix.RotationX(Math.PI / 2), M); M.multiplyToRef(B.Matrix.Translation(clamp(g.x + sx, -1.3, 1.3) * hw, clamp(g.y + sy, -1.3, 1.3) * hh, -GZ), M); M.copyToArray(GL.mat, m * 16); GL.ph[m] = g.ph; m++; }
    GL.m.thinInstanceCount = m; GL.m.thinInstanceBufferUpdated('matrix'); GL.m.thinInstanceBufferUpdated('phase'); GL.m.thinInstanceBufferUpdated('lean');
  }
  const api = { step, S, SLO, blowHalf, zapTest: () => spawnZap(), chaseTest: () => spawnWave(), get glass() { return GS.length; }, get road() { return RS.length; }, attach: (k) => { for (let i = 0; i < k; i++) attach((d.cam && d.cam()) || scene.activeCamera); }, settle: () => { for (const g of GS) { g.x = g.tx; g.y = g.ty; } },
    storm: (z) => spawnStorm(z || 120), strikeTest: () => { const c = CL[CL.length - 1]; if (c) strike(c); }, washTest: () => wash({ tint: pick(d.pal.bolts) }) };
  return api;
}
