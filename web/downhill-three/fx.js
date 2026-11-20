// FX: the effect layer of the Godot game (sparkle bursts, sparklers and trails, expanding light rings, shockwave bubbles, confetti, the snow spray), ported from the CODE so the three.js game looks the way Godot did.
// Sources (godot/scripts): Fx.gd (confetti 11-40, shockwave 45-48 + _ring 84-101), RunRig.gd _burst 4478-4521, _ring 4525-4553, _sparkler 3684-3715, _fx_mat 3620-3644 (the 'spark' and 'halo' materials: unshaded, additive, glow texture), _buff_pop 4556-4590,
// the trails _ensure_fx 4603-4614, _hit_fx 5628-5650, and every call site listed in the EVENTS section below; DownhillRig.gd 796-815 and 1432 (the snow spray); Mats.gd 21-41 (flat / glass / glow).
//
// HOW IT IS BUILT FOR A PHONE: nothing is a node per particle. All sparkles are ONE additive InstancedMesh (CPU-simulated in typed arrays, matrices written straight into the instance buffer), rings are ONE additive instanced torus, confetti is ONE instanced box mesh,
// the spray is ONE instanced mesh, the shockwave bubbles are a pool of six spheres. So the whole layer costs about five draw calls however much is going on.
//
// WHAT IS EXACT (Godot's CPUParticles3D rules, as _burst sets them): one-shot, everything emitted at once (explosiveness 1); `amount` particles; `lifetime`; direction + `spread` (a cone half-angle in degrees, 180 = a full ball); speed random between 0.35 x speed and speed;
// gravity (0, grav, 0); damping 1..3 (a constant slowing of the speed in m/s per second, Godot's own damping rule); size random between 0.5 x and 1.6 x of `size` on a sphere of radius 0.1; colour = the burst colour, alpha from the ramp 1 -> 0.8 (at 60% of the life) -> 0, drawn ADDITIVE and unshaded, no fog.
// Godot's web build halves every burst's count and allows only 12 live bursts at a time (RunRig.gd 4482-4486): `webParity: true` (the default) does the same, so the look matches what was seen on a phone; pass webParity:false for the desktop counts (cap 40).
//
//   import { createFx } from './fx.js';
//   const FX = createFx({ THREE, scene, camera });            // THREE is the module namespace; `camera` is only used to hide nothing for now (kept for facing effects)
//   FX.burst(pos, col, n, speed, life, size, dir, spread, grav)   same arguments, same meaning as RunRig._burst (pos and dir are [x,y,z] arrays or {x,y,z}; col is [r,g,b] 0..1, {r,g,b} or a THREE.Color)
//   FX.ring(pos, col, rEnd, dur, standing, delay)                  RunRig._ring (standing = faces the camera down -Z, false = flat on the snow); delay in seconds (Godot used timers for the three rock rings)
//   FX.shockwave(pos, radius, col)                                 Fx.shockwave's visible part: a translucent bubble 0.2 -> radius*2 in 0.3 s
//   FX.confetti(pos, amount, size)                                 Fx.confetti
//   FX.sparkler({ pos, color, radius, n, ... })                    RunRig._sparkler: a continuous emitter; returns a handle { set(x,y,z), emitting, setDir(x,y,z), dispose() }
//   FX.trailBoost() / FX.trailMult()                               the two trails behind the board (RunRig 4603-4632): handles with update(x,y,z, fx, fz, emitting)
//   FX.spray()                                                     the snow spray (DownhillRig 796-815): handle with update(dt-free) update(x,y,z, fx, fz, emitting)
//   FX.E.*                                                         one function per Godot call site (see the list): E.pickup('boost'|'shield'|'donut'|'mult', pos, heading), E.pad(spos), E.blast(spos), E.railSpark(spos), E.land(...), E.treeHit(...) and so on
//   FX.tick(dt)                                                    once per frame
//   FX.stats()                                                     live particle counts, for the HUD or tests

const COL = { boost: [1.0, 0.55, 0.1], shield: [0.3, 0.85, 1.0], mult: [0.95, 0.4, 1.0], donut: [1.0, 0.45, 0.7], orb: [1.0, 0.9, 0.45] };          // BUFF_COL (RunRig 3560)
const rgb = (c) => (Array.isArray(c) ? c : (c && c.isColor ? [c.r, c.g, c.b] : [c.r, c.g, c.b]));
const v3 = (p) => (Array.isArray(p) ? p : [p.x, p.y, p.z]);
const rnd = (a, b) => a + (b - a) * Math.random();
const hsv = (h, s, v) => { h = ((h % 1) + 1) % 1; const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]; };          // Color.from_hsv

export function createFx(opts) {
  const { THREE, scene } = opts;
  const WEB = opts.webParity !== false, CNT = opts.scale !== undefined ? opts.scale : (WEB ? 0.5 : 1), MAXB = opts.maxBursts !== undefined ? opts.maxBursts : (WEB ? 12 : 40);
  const CAP = opts.capParticles || 1400, CAPC = opts.capConfetti || 320, CAPR = opts.capRings || 24, CAPS = opts.capSpray || 90;
  let now = 0;

  // ---------------------------------------------------------------- the sparkles (bursts, sparklers, trails): one additive instanced mesh
  const sparkGeo = new THREE.SphereGeometry(0.1, 7, 5);
  const sparkMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
  const sparks = new THREE.InstancedMesh(sparkGeo, sparkMat, CAP); sparks.frustumCulled = false; sparks.count = 0; sparks.setColorAt(0, new THREE.Color(1, 1, 1)); sparks.renderOrder = 6; scene.add(sparks);
  const P = { x: new Float32Array(CAP), y: new Float32Array(CAP), z: new Float32Array(CAP), vx: new Float32Array(CAP), vy: new Float32Array(CAP), vz: new Float32Array(CAP), gx: new Float32Array(CAP), gy: new Float32Array(CAP), gz: new Float32Array(CAP), age: new Float32Array(CAP), life: new Float32Array(CAP), size: new Float32Array(CAP), r: new Float32Array(CAP), g: new Float32Array(CAP), b: new Float32Array(CAP), damp: new Float32Array(CAP), ramp: new Uint8Array(CAP) };
  const alive = new Uint16Array(CAP); let nAlive = 0; const freeList = new Uint16Array(CAP); let nFree = CAP; for (let i = 0; i < CAP; i++) freeList[i] = CAP - 1 - i;
  function emit(x, y, z, vx, vy, vz, life, size, c, damp, gx, gy, gz, ramp) {
    if (nFree === 0) return; const i = freeList[--nFree]; alive[nAlive++] = i;
    P.x[i] = x; P.y[i] = y; P.z[i] = z; P.vx[i] = vx; P.vy[i] = vy; P.vz[i] = vz; P.gx[i] = gx; P.gy[i] = gy; P.gz[i] = gz; P.age[i] = 0; P.life[i] = life; P.size[i] = size; P.r[i] = c[0]; P.g[i] = c[1]; P.b[i] = c[2]; P.damp[i] = damp; P.ramp[i] = ramp;
  }
  // a random unit vector inside the cone of half-angle `spreadDeg` around `dir` (180 = the whole ball)
  function cone(dir, spreadDeg) {
    let dx = dir[0], dy = dir[1], dz = dir[2]; const dl = Math.hypot(dx, dy, dz) || 1; dx /= dl; dy /= dl; dz /= dl;
    const cMin = Math.cos(Math.min(Math.max(spreadDeg, 0), 180) * Math.PI / 180), cz = rnd(cMin, 1), sz = Math.sqrt(Math.max(0, 1 - cz * cz)), ph = rnd(0, 6.2831853);
    // a frame around dir
    let ux, uy, uz; if (Math.abs(dy) < 0.99) { ux = dz; uy = 0; uz = -dx; } else { ux = 1; uy = 0; uz = 0; } const ul = Math.hypot(ux, uy, uz) || 1; ux /= ul; uy /= ul; uz /= ul;
    const wx = dy * uz - dz * uy, wy = dz * ux - dx * uz, wz = dx * uy - dy * ux, a = sz * Math.cos(ph), b = sz * Math.sin(ph);
    return [dx * cz + ux * a + wx * b, dy * cz + uy * a + wy * b, dz * cz + uz * a + wz * b];
  }
  const bursts = [];          // end times of the bursts still live (Godot's _burst_live)
  function burst(pos, col, nIn, speed, life, size, dir, spread, grav) {
    dir = dir || [0, 1, 0]; spread = spread === undefined ? 180 : spread; grav = grav === undefined ? -6 : grav;
    for (let i = bursts.length - 1; i >= 0; i--) if (bursts[i] <= now) bursts.splice(i, 1);
    if (bursts.length >= MAXB) return;          // RunRig 4482: only so many at once
    const n = Math.max(1, Math.floor(nIn * CNT)); bursts.push(now + life + 0.4);
    const p = v3(pos), c = rgb(col), d = v3(dir);
    for (let k = 0; k < n; k++) { const u = cone(d, spread), sp = rnd(speed * 0.35, speed); emit(p[0], p[1], p[2], u[0] * sp, u[1] * sp, u[2] * sp, life, rnd(size * 0.5, size * 1.6), c, rnd(1, 3), 0, grav, 0, 0); }
  }
  // a continuous emitter (CPUParticles3D with amount n and a lifetime: n / lifetime particles a second)
  const sparklers = [];
  function sparkler(o) {
    const s = Object.assign({ pos: [0, 0, 0], color: [1, 1, 1], radius: 1.6, n: 10, life: 1.3, dir: [0, 1, 0], spread: 60, vmin: 0.2, vmax: 0.9, grav: [0, 0.6, 0], smin: 0.5, smax: 1.5, emitting: false, acc: 0 }, o);          // _sparkler defaults (RunRig 3684-3715)
    s.pos = v3(s.pos).slice(); s.color = rgb(s.color); s.dir = v3(s.dir).slice(); s.grav = v3(s.grav).slice(); sparklers.push(s);
    s.set = (x, y, z) => { s.pos[0] = x; s.pos[1] = y; s.pos[2] = z; }; s.setDir = (x, y, z) => { s.dir[0] = x; s.dir[1] = y; s.dir[2] = z; };
    s.dispose = () => { const i = sparklers.indexOf(s); if (i >= 0) sparklers.splice(i, 1); };
    return s;
  }
  // the two trails behind the board (RunRig _ensure_fx 4603-4614, switched on while boosting / sugar-rushing at 4631-4632). `local` offsets are in the board's frame: +z is behind it.
  function trail(o) {
    const s = sparkler(o); const off = o.off || [0, 0, 0], back = o.back || [0, 0, 0];
    s.update = (x, y, z, fx, fz, emitting) => { const bx = -fx, bz = -fz; s.set(x + bx * off[2] + (-fz) * off[0], y + off[1], z + bz * off[2] + fx * off[0]); if (back[2]) s.setDir(bx * back[2], back[1], bz * back[2]); s.emitting = !!emitting; };
    return s;
  }
  const trailBoost = () => trail({ color: [1.0, 0.65, 0.2], radius: 0.35, n: 26, off: [0, 0.5, 1.0], dir: [0, 0.2, 1], back: [0, 0.2, 1], spread: 18, vmin: 4, vmax: 9, life: 0.5, grav: [0, 0, 0] });
  const trailMult = () => trail({ color: [1.0, 0.85, 0.35], radius: 0.9, n: 16, off: [0, 1.0, 0] });
  // a pickup's own sparkler (_make_item 3864): pale version of its colour, radius 1.6, 10 sparkles
  const buffSparkler = (col, pos) => sparkler({ pos, color: [col[0] * 0.5 + 0.5, col[1] * 0.5 + 0.5, col[2] * 0.5 + 0.5], radius: 1.6, n: 10 });

  // ---------------------------------------------------------------- rings: one additive instanced torus (Godot: TorusMesh inner 0.9 outer 1.0, Mats.glow, scale 0.3 -> rEnd with TRANS_QUART / EASE_OUT, alpha 0.95 -> 0 over `dur`)
  const ringGeo = new THREE.RingGeometry(0.45, 1.0, 72, 1);
  const ringMat = new THREE.ShaderMaterial({ transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, side: THREE.DoubleSide,          // a soft shockwave: a glowing band that is bright and crisp on its outer edge and fades inward
    vertexShader: 'varying vec3 vC; varying float vR; void main(){ vC = instanceColor; vR = length(position.xy); gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.); }',
    fragmentShader: 'varying vec3 vC; varying float vR; void main(){ float a = smoothstep(.6, .95, vR) * (1. - smoothstep(.95, 1., vR)); gl_FragColor = vec4(vC * a * 1.7, 1.); }' });
  const rings = new THREE.InstancedMesh(ringGeo, ringMat, CAPR); rings.frustumCulled = false; rings.count = 0; rings.setColorAt(0, new THREE.Color(1, 1, 1)); rings.renderOrder = 6; scene.add(rings);
  const RG = []; // { x,y,z, r,g,b, rEnd, dur, t, delay, flat }
  function ring(pos, col, rEnd, dur, standing, delay) {
    if (RG.length >= CAPR) RG.shift(); const p = v3(pos), c = rgb(col); RG.push({ x: p[0], y: p[1], z: p[2], r: c[0], g: c[1], b: c[2], rEnd, dur, t: 0, delay: delay || 0, flat: standing === false });
  }
  // ---------------------------------------------------------------- shockwave bubbles (Fx.gd 84-101: a SphereMesh r 0.5, glass (alpha) unshaded, scale 0.2 -> radius*2 in 0.3 s TRANS_QUAD EASE_OUT, alpha -> 0)
  const bubbleGeo = new THREE.SphereGeometry(0.5, 16, 10), bubbles = [];
  for (let i = 0; i < 6; i++) { const m = new THREE.Mesh(bubbleGeo, new THREE.ShaderMaterial({ uniforms: { uC: { value: new THREE.Color(1, 1, 1) }, uA: { value: 0 } }, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, side: THREE.DoubleSide,          // a glassy bubble: bright rim, nearly clear middle
      vertexShader: 'varying vec3 vN; varying vec3 vV; void main(){ vec4 mv = modelViewMatrix * vec4(position, 1.); vN = normalize(normalMatrix * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }',
      fragmentShader: 'uniform vec3 uC; uniform float uA; varying vec3 vN; varying vec3 vV; void main(){ float f = pow(1. - abs(dot(normalize(vN), normalize(vV))), 2.2); gl_FragColor = vec4(uC * (f * 1.8 + .06) * uA * 2., 1.); }' })); m.visible = false; m.frustumCulled = false; scene.add(m); bubbles.push({ m, t: 99, rad: 1, a0: 0.45 }); }
  let bi = 0;
  function shockwave(pos, radius, col) {
    const c = col ? (col.length === 4 ? col : rgb(col).concat([0.45])) : [1.0, 0.9, 0.5, 0.45], b = bubbles[bi++ % bubbles.length], p = v3(pos);
    b.t = 0; b.rad = radius; b.a0 = c[3]; b.m.material.uniforms.uC.value.setRGB(c[0], c[1], c[2]); b.m.position.set(p[0], p[1], p[2]); b.m.visible = true; b.m.scale.setScalar(0.2);
  }
  // ---------------------------------------------------------------- confetti (Fx.gd 11-40): lifetime 1.4, a ball of radius 0.3*size, speed 4*size..9*size, gravity -9.8, spin +-400 deg/s, a 5-colour gradient picked at random; a flat unshaded box 0.09 x 0.09 x 0.02 (x size)
  const confMat = new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, fog: false });
  const conf = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), confMat, CAPC); conf.frustumCulled = false; conf.count = 0; conf.setColorAt(0, new THREE.Color(1, 1, 1)); scene.add(conf);
  const CF = []; const GRAD = [[1, 0, 0], [1, 1, 0], [0.3, 1, 0.4], [0.3, 0.7, 1], [1, 0.4, 0.9]];
  function confetti(pos, amount, size) {
    amount = amount === undefined ? 60 : amount; size = size === undefined ? 1 : size; const p = v3(pos);
    for (let k = 0; k < amount; k++) {
      if (CF.length >= CAPC) CF.shift(); const u = cone([0, 1, 0], 180), sp = rnd(4 * size, 9 * size), rr = Math.cbrt(Math.random()) * 0.3 * size, gt = Math.random() * 4, gi = Math.min(3, Math.floor(gt)), c = [0, 1, 2].map((q) => GRAD[gi][q] + (GRAD[gi + 1][q] - GRAD[gi][q]) * (gt - gi));
      const a = cone([0, 1, 0], 180); CF.push({ x: p[0] + a[0] * rr, y: p[1] + a[1] * rr, z: p[2] + a[2] * rr, vx: u[0] * sp, vy: u[1] * sp, vz: u[2] * sp, t: 0, size, c, ax: a[2], ay: a[0], az: a[1], w: rnd(-400, 400) * Math.PI / 180, ph: rnd(0, 6.28) });
    }
  }
  // ---------------------------------------------------------------- the snow spray (DownhillRig 796-815, on while grounded and moving over 8 m/s at 1432): white opaque spheres r 0.13 x (0.3..0.6), 36 over 0.5 s, up and BACK (0,1,0.6), spread 30, speed 1..3, gravity -6
  const sprayMat = new THREE.ShaderMaterial({ transparent: true, depthWrite: false, fog: false,          // powder puffs: soft, see-through at the edge, never a flat white ball
    vertexShader: 'varying vec3 vN; varying vec3 vV; void main(){ vec4 mv = modelViewMatrix * instanceMatrix * vec4(position, 1.); vN = normalize(normalMatrix * mat3(instanceMatrix) * normal); vV = normalize(-mv.xyz); gl_Position = projectionMatrix * mv; }',
    fragmentShader: 'varying vec3 vN; varying vec3 vV; void main(){ float a = pow(abs(dot(normalize(vN), normalize(vV))), 1.6); gl_FragColor = vec4(vec3(.92, .96, 1.), a * .6); }' });
  const sprayM = new THREE.InstancedMesh(new THREE.SphereGeometry(0.13, 12, 8), sprayMat, CAPS); sprayM.frustumCulled = false; sprayM.count = 0; scene.add(sprayM);
  const SP = [];
  function spray() {
    const s = { emitting: false, acc: 0, x: 0, y: 0, z: 0, fx: 0, fz: -1 };
    s.update = (x, y, z, fx, fz, emitting) => { s.x = x; s.y = y; s.z = z; s.fx = fx; s.fz = fz; s.emitting = !!emitting; }; sprays.push(s); s.dispose = () => { const i = sprays.indexOf(s); if (i >= 0) sprays.splice(i, 1); }; return s;
  }
  const sprays = [];

  // ---------------------------------------------------------------- the frame
  const _m = new Float32Array(16);
  function tick(dt) {
    now += dt;
    // emitters
    for (const s of sparklers) {
      if (!s.emitting) { s.acc = 0; continue; } s.acc += dt * s.n / s.life;
      while (s.acc >= 1) { s.acc -= 1; const r = Math.cbrt(Math.random()) * s.radius, a = cone([0, 1, 0], 180), u = cone(s.dir, s.spread), sp = rnd(s.vmin, s.vmax); emit(s.pos[0] + a[0] * r, s.pos[1] + a[1] * r, s.pos[2] + a[2] * r, u[0] * sp, u[1] * sp, u[2] * sp, s.life, rnd(s.smin, s.smax) * 0.7, s.color, 0, s.grav[0], s.grav[1], s.grav[2], 1); }
    }
    for (const s of sprays) { if (!s.emitting) { s.acc = 0; continue; } s.acc += dt * 72; while (s.acc >= 1) { s.acc -= 1; if (SP.length >= CAPS) SP.shift(); const u = cone([-s.fx * 0.6, 1, -s.fz * 0.6], 30), sp = rnd(1, 3); SP.push({ x: s.x - s.fx * 0.9, y: s.y + 0.2, z: s.z - s.fz * 0.9, vx: u[0] * sp, vy: u[1] * sp, vz: u[2] * sp, t: 0, sc: rnd(0.3, 0.6) }); } }
    // sparkles
    const ma = sparks.instanceMatrix.array, ca = sparks.instanceColor.array; let k = 0;
    for (let q = 0; q < nAlive; q++) {
      const i = alive[q]; P.age[i] += dt; if (P.age[i] >= P.life[i]) { freeList[nFree++] = i; alive[q] = alive[--nAlive]; q--; continue; }
      P.vy[i] += P.gy[i] * dt; P.vx[i] += P.gx[i] * dt; P.vz[i] += P.gz[i] * dt;
      if (P.damp[i] > 0) { const sp = Math.hypot(P.vx[i], P.vy[i], P.vz[i]); const ns = sp - P.damp[i] * dt; if (ns <= 0) { P.vx[i] = P.vy[i] = P.vz[i] = 0; } else { const f = ns / sp; P.vx[i] *= f; P.vy[i] *= f; P.vz[i] *= f; } }
      P.x[i] += P.vx[i] * dt; P.y[i] += P.vy[i] * dt; P.z[i] += P.vz[i] * dt;
      const u = P.age[i] / P.life[i]; let a;
      if (P.ramp[i] === 0) a = u < 0.6 ? 1 + (0.8 - 1) * (u / 0.6) : 0.8 * (1 - (u - 0.6) / 0.4); else a = u < 0.2 ? u / 0.2 : 1 - (u - 0.2) / 0.8;          // burst ramp: 1, 0.8 at 60%, 0 (RunRig 4510-4513); sparkler ramp: 0, 1 at 20%, 0 (RunRig 3708-3711)
      const s = P.size[i], o = k * 16; ma[o] = s; ma[o + 1] = 0; ma[o + 2] = 0; ma[o + 3] = 0; ma[o + 4] = 0; ma[o + 5] = s; ma[o + 6] = 0; ma[o + 7] = 0; ma[o + 8] = 0; ma[o + 9] = 0; ma[o + 10] = s; ma[o + 11] = 0; ma[o + 12] = P.x[i]; ma[o + 13] = P.y[i]; ma[o + 14] = P.z[i]; ma[o + 15] = 1;
      ca[k * 3] = P.r[i] * a; ca[k * 3 + 1] = P.g[i] * a; ca[k * 3 + 2] = P.b[i] * a; k++;
    }
    sparks.count = k; sparks.instanceMatrix.needsUpdate = true; sparks.instanceColor.needsUpdate = true;
    // rings
    { const ra = rings.instanceMatrix.array, rc = rings.instanceColor.array; let n = 0;
      for (let i = RG.length - 1; i >= 0; i--) {
        const g = RG[i]; if (g.delay > 0) { g.delay -= dt; if (g.delay > 0) continue; } g.t += dt; if (g.t >= g.dur) { RG.splice(i, 1); }
      }
      for (const g of RG) {
        if (g.delay > 0) continue; const x = Math.min(1, g.t / g.dur), e = 1 - Math.pow(1 - x, 4), s = 0.3 + (g.rEnd - 0.3) * e, al = 0.95 * (1 - x), o = n * 16;
        if (g.flat) { ra[o] = s; ra[o + 1] = 0; ra[o + 2] = 0; ra[o + 3] = 0; ra[o + 4] = 0; ra[o + 5] = 0; ra[o + 6] = -s; ra[o + 7] = 0; ra[o + 8] = 0; ra[o + 9] = s; ra[o + 10] = 0; ra[o + 11] = 0; }
        else { ra[o] = s; ra[o + 1] = 0; ra[o + 2] = 0; ra[o + 3] = 0; ra[o + 4] = 0; ra[o + 5] = s; ra[o + 6] = 0; ra[o + 7] = 0; ra[o + 8] = 0; ra[o + 9] = 0; ra[o + 10] = s; ra[o + 11] = 0; }
        ra[o + 12] = g.x; ra[o + 13] = g.y; ra[o + 14] = g.z; ra[o + 15] = 1; rc[n * 3] = g.r * al; rc[n * 3 + 1] = g.g * al; rc[n * 3 + 2] = g.b * al; n++;
      }
      rings.count = n; rings.instanceMatrix.needsUpdate = true; rings.instanceColor.needsUpdate = true; }
    // bubbles
    for (const b of bubbles) { if (!b.m.visible) continue; b.t += dt; const x = b.t / 0.3; if (x >= 1) { b.m.visible = false; continue; } const e = 1 - (1 - x) * (1 - x); b.m.scale.setScalar(0.2 + (b.rad * 2 - 0.2) * e); b.m.material.uniforms.uA.value = b.a0 * (1 - x); }
    // confetti
    { const ca2 = conf.instanceMatrix.array, cc = conf.instanceColor.array; let n = 0;
      for (let i = CF.length - 1; i >= 0; i--) { const f = CF[i]; f.t += dt; if (f.t >= 1.4) { CF.splice(i, 1); continue; } }
      for (const f of CF) {
        f.vy -= 9.8 * dt; f.x += f.vx * dt; f.y += f.vy * dt; f.z += f.vz * dt;
        const ang = f.ph + f.w * f.t, c = Math.cos(ang), s = Math.sin(ang), t = 1 - c, al = Math.hypot(f.ax, f.ay, f.az) || 1, ux = f.ax / al, uy = f.ay / al, uz = f.az / al, o = n * 16, sx = 0.09 * f.size, sy = 0.09 * f.size, sz = 0.02 * f.size;
        ca2[o] = (t * ux * ux + c) * sx; ca2[o + 1] = (t * ux * uy + s * uz) * sx; ca2[o + 2] = (t * ux * uz - s * uy) * sx; ca2[o + 3] = 0;
        ca2[o + 4] = (t * ux * uy - s * uz) * sy; ca2[o + 5] = (t * uy * uy + c) * sy; ca2[o + 6] = (t * uy * uz + s * ux) * sy; ca2[o + 7] = 0;
        ca2[o + 8] = (t * ux * uz + s * uy) * sz; ca2[o + 9] = (t * uy * uz - s * ux) * sz; ca2[o + 10] = (t * uz * uz + c) * sz; ca2[o + 11] = 0;
        ca2[o + 12] = f.x; ca2[o + 13] = f.y; ca2[o + 14] = f.z; ca2[o + 15] = 1; cc[n * 3] = f.c[0]; cc[n * 3 + 1] = f.c[1]; cc[n * 3 + 2] = f.c[2]; n++;
      }
      conf.count = n; conf.instanceMatrix.needsUpdate = true; conf.instanceColor.needsUpdate = true; }
    // spray
    { const sa = sprayM.instanceMatrix.array; let n = 0;
      for (let i = SP.length - 1; i >= 0; i--) if ((SP[i].t += dt) >= 0.5) SP.splice(i, 1);
      for (const p of SP) { p.vy -= 6 * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt; const o = n * 16, s = p.sc; sa[o] = s; sa[o + 1] = 0; sa[o + 2] = 0; sa[o + 3] = 0; sa[o + 4] = 0; sa[o + 5] = s; sa[o + 6] = 0; sa[o + 7] = 0; sa[o + 8] = 0; sa[o + 9] = 0; sa[o + 10] = s; sa[o + 11] = 0; sa[o + 12] = p.x; sa[o + 13] = p.y; sa[o + 14] = p.z; sa[o + 15] = 1; n++; }
      sprayM.count = n; sprayM.instanceMatrix.needsUpdate = true; }
  }

  // ================================================================ EVENTS: each Godot call site, with its exact arguments. Positions are [x,y,z]; `spos` is the board's position.
  // Where a call site also does something that is not a visual here (a sound, a toast, the field-of-view punch, the shake), the comment says so and gv.js / psyfx.js do that part.
  const up = (p, dy) => [p[0], p[1] + dy, p[2]];
  const E = {
    // _buff_pop (RunRig 4556-4590): what a pickup feels like. Also a hop of the rider, fov punch / shake (psyfx.events.onBuff does the camera part).
    pickup(type, pos, heading) {
      const p = v3(pos), col = COL[type] || COL.orb, fwd3 = [Math.sin(heading || 0), 0.25, -Math.cos(heading || 0)];
      if (type === 'boost') { burst(p, [1.0, 0.6, 0.15], 70, 14, 0.9, 1.0); burst(p, [1.0, 0.95, 0.6], 36, 24, 0.6, 0.8, fwd3, 20, -2); ring(p, col, 7, 0.45, true); }
      else if (type === 'shield') { burst(p, col, 56, 9, 1.0, 1.0, [0, 1, 0], 180, -3); burst(p, [1, 1, 1], 26, 5, 1.2, 0.7, [0, 1, 0], 180, 1.5); ring(p, col, 9, 0.6, true); ring(up(p, -1.6), col, 13, 0.75, false); }
      else if (type === 'donut') { burst(p, [1.0, 0.45, 0.7], 56, 10, 1.2, 1.2, [0, 1, 0], 180, -8); burst(p, [1.0, 0.95, 0.4], 30, 9, 1.2, 0.9, [0, 1, 0], 180, -8); ring(p, col, 8, 0.5, true); }
      else { burst(p, [1.0, 0.85, 0.3], 56, 11, 1.3, 1.3, [0, 1, 0], 180, -9); burst(p, [0.95, 0.35, 1.0], 56, 11, 1.3, 1.3, [0, 1, 0], 180, -9); ring(p, [1.0, 0.85, 0.3], 8, 0.5, true); }          // 'mult' and anything else
    },
    orb(p) { burst(p, COL.orb, 6, 5, 0.45, 0.6); },                                                                                   // _collect_buffs 4805 (an orb taken)
    orbPulse(p, col) { burst(p, col, 14, 8, 0.5, 0.7); },                                                                              // _orb_tick 8813
    glint(p) { burst(p, [1.0, 0.85, 0.3], 3, 4, 0.35, 0.5); },                                                                         // _glint_got 3981
    pad(spos) { burst(up(v3(spos), 0.6), [1.0, 0.6, 0.2], 40, 12, 0.6, 0.9, [0, 0.3, 1.0], 40, -3); },                                 // _update_pads 8180 (boost pad)
    blast(spos) { const p = up(v3(spos), 0.6); burst(p, [1.0, 0.55, 1.0], 90, 16, 0.9, 1.1, [0, 1, 0.5], 70, -5); burst(p, [1.0, 0.95, 0.6], 50, 24, 0.6, 0.8, [0, 0.6, 1], 35, -3); },   // _update_ramps 8047-8048 (the lip of a ramp)
    pop(spos, charge) { burst(up(v3(spos), 0.5), [1.0, 0.85, 0.4], 30 + Math.floor(40 * charge), 10, 0.7, 1.0, [0, 1, 0.4], 50, -4); },   // _update_ramps 8071 (a charged pop at the lip)
    railSpark(spos) { burst([v3(spos)[0], v3(spos)[1] + 0.05, v3(spos)[2] + 0.6], [1.0, 0.9, 0.5], 5, 6, 0.3, 0.45, [0, 1, 1], 50, -9); },   // _feat_tick 1946: every 0.14 s while grinding a rail
    railEnd(spos) { burst(up(v3(spos), 0.3), [0.6, 0.95, 1.0], 26, 9, 0.6, 0.8, [0, 1, 0.4], 60, -5); },                               // _rail_off 1888
    rockSmash(hx, gy, za) { burst([hx, gy + 1.0, za + 4.0], [0.8, 0.82, 0.9], 70, 12, 0.8, 1.2, [0, 1, 0], 80, -9); },                  // _feat_tick 1977 (a hazard patch smashed by a steady look)
    pole(x, y, z) { burst([x, y + 1.0, z], [1, 1, 1], 16, 7, 0.5, 0.7); },                                                              // _slalom_tick 2094 (a pole shaved)
    cheer(spos, col, size) { const s = v3(spos), cp = [s[0], s[1] + 2.0, s[2] - 4.0]; confetti(cp, Math.floor(50 * size), 1 + 0.4 * size); ring([s[0], s[1] + 0.8, s[2]], col, 7 + 5 * size, 0.5, true); burst(cp, col, Math.floor(30 * size), 10, 0.8, 1.0, [0, 1, 0], 120, -6); },   // _cheer 3967-3969
    landSmooth(spos) { burst(up(v3(spos), 0.5), [0.95, 0.98, 1.0], 18, 6, 0.5, 0.8, [0, 1, 0.3], 60, -6); },                          // _pop_tick 4352
    shieldBreak(spos) { const bp = up(v3(spos), 1.2); burst(bp, COL.shield, 44, 12, 0.8, 1.0); ring(bp, COL.shield, 8, 0.4, true); },    // _crash 5693-5694 (the shield takes the hit)
    foodBounce(p) { burst(p, COL.boost, 18, 6, 0.5, 0.7); }, foodLost(p, col) { burst(p, col, 34, 7, 0.7, 0.9); },                       // _bounce_food 7685 / 7671
    // _hit_fx (RunRig 5628-5650): a tree throws needles, bark and shaken-off snow; a rock RINGS with three rings 0.18 s apart (the glowing bell copy of the rock is a mesh effect for gv.js)
    treeHit(ox, gy, oz, speed) { const p = [ox, gy + 2.2, oz], k = Math.min(1.4, Math.max(0.5, speed / 40)); burst(p, [0.1, 0.48, 0.2], Math.floor(46 * k), 8, 1.0, 0.8, [0, 1, 0], 150, -4); burst(p, [0.42, 0.28, 0.14], Math.floor(20 * k), 6, 0.8, 0.7, [0, 1, 0], 120, -6); burst(up(p, 1.4), [1, 1, 1], Math.floor(40 * k), 5, 1.3, 1.5, [0, 1, 0], 100, -2.5); },
    rockHit(ox, gy, oz, orad) { const p2 = [ox, gy + orad, oz], c = [0.8, 0.92, 1.0]; burst(p2, [0.8, 0.9, 1.0], 26, 9, 0.6, 0.6, [0, 1, 0], 180, -7); ring(p2, c, 7, 0.8, true); ring(p2, c, 9, 0.9, true, 0.18); ring(p2, c, 11, 1.0, true, 0.36); },
    snowballEnd(p) { burst(p, [0.9, 0.95, 1.0], 60, 14, 1.0, 1.4, [0, 1, 0], 120, -8); },                                              // _sb_end 1360
    ballHit(p) { burst(p, [0.95, 0.98, 1.0], 90, 15, 1.0, 2.2, [0, 1, 0], 180, -9); ring(p, [0.85, 0.95, 1.0], 10, 0.5, true); },         // _ball_hit 7830-7831 (a side-rolling snowball hits)
    // linked set pieces / toys
    lkCatch(cp, col) { burst(cp, col, 60, 16, 0.9, 1.2); },                                                                            // _lk_catch 9057
    lkStart(spos) { burst(up(v3(spos), 0.6), [1.0, 0.4, 0.9], 50, 14, 0.7, 1.0, [0, 1, 0], 60, -3); },                                 // _lk_start 9119
    lkStep(spos, rc) { burst(up(v3(spos), 0.4), rc, 8, 7, 0.4, 0.5); },                                                                // _lk_step 9138 (along the tube)
    lkEnd(spos) { burst(up(v3(spos), 0.5), [0.3, 0.95, 1.0], 30, 10, 0.5, 0.8); },                                                      // _lk_end 9187
    pillEat(p, col) { burst(p, col, 22, 8, 0.6, 1.0); },                                                                               // _pill_eat 9814 (a molecule eaten)
    slingDraw(spos) { burst(up(v3(spos), 0.5), [0.6, 0.9, 1.0], 2, 3, 0.4, 0.5); },                                                    // _sling_tick 10062
    slingRelease(spos) { const p = up(v3(spos), 0.6); burst(p, [0.75, 0.95, 1.0], 40, 12, 0.6, 0.9, [0, 0.3, 1.0], 40, -3); ring(up(v3(spos), 0.8), [0.6, 0.9, 1.0], 9, 0.5, true); },   // _sling_tick 10072-10073
    gateResult(spos, col) { burst(up(v3(spos), 1.5), col, 14, 7, 0.5, 0.8); },                                                          // _gate_result 10176
    bump(x, y, tz) { burst([x, y + 1.0, tz], [1.0, 0.4, 0.8], 18, 8, 0.5, 0.9); },                                                      // _toys_tick 10264 (a bumper kicks)
    // landings
    landOnSpot(x, gh, z) { burst([x, gh + 0.3, z], [0.5, 1.0, 0.8], 40, 9, 0.6, 0.9, [0, 1, 0], 60, -6); },                            // _land 10571 ('landed where you looked')
    landBounce(x, gh, z) { burst([x, gh + 0.3, z], [1.0, 0.9, 0.4], 16, 6, 0.5, 0.7, [0, 1, 0], 80, -4); },                            // _land 10578 (a bouncy landing)
    slam(spos, fell) { const s = v3(spos), gp = [s[0], s[1] + 1.0, s[2]]; burst(gp, [1.0, 0.9, 0.5], 40, 10, 0.9, 1.0); ring([s[0], s[1] + 0.3, s[2]], [1.0, 0.85, 0.4], 9, 0.5, false); if (fell) { ring([s[0], s[1] + 0.3, s[2]], [1.0, 0.5, 0.3], 16, 0.7, false); burst(gp, [0.95, 0.98, 1.0], 80, 14, 1.0, 2.0, [0, 1, 0], 180, -9); } },   // _land_tricks 11441-11445
    stomp(pos) { shockwave(pos, 9, [1.0, 0.9, 0.6, 0.5]); confetti(up(v3(pos), 0.4), 40, 1.0); },                                       // DownhillRig._land 979-980: Fx.shockwave(...9.0...) + Fx.confetti(...40...)
    // the trip
    apex(spos, age) { const s = v3(spos); for (let ri = 0; ri < 4; ri++) ring([s[0] + rnd(-5, 5), s[1] + 1.0 + 1.5 * ri, s[2] - 8.0 - 7.0 * ri], hsv(age * 0.13 + 0.23 * ri, 0.75, 1.0), 12 + 6 * ri, 0.9 + 0.2 * ri, true); burst([s[0], s[1] + 2.0, s[2] - 6.0], hsv(age * 0.13, 0.6, 1.0), 60, 14, 1.3, 1.0, [0, 1, 0], 180, -1.5); },   // _pill_tick 9959-9960 (the top of a jump)
    face(fp, fc) { burst(fp, fc, 60, 16, 1.1, 1.2, [0, 1, 0], 180, -4); ring(fp, [1.0, 0.9, 0.3], 16, 0.7, true); ring(fp, [1.0, 0.4, 0.85], 10, 0.5, false); },   // _face_tick 11031-11033
    faceGold(spos) { const s = v3(spos); burst([s[0], s[1] + 1.6, s[2]], [1.0, 0.85, 0.3], 50, 9, 1.0, 1.0); },                         // _face_tick 11043
    chaos(pos, fp, fc) { burst(pos, [1.0, 0.95, 0.7], 60, 12, 1.0, 1.4); if (fp) burst(fp, fc, 50, 11, 1.2, 1.2, [0, 1, 0], 180, -3); burst(pos, [1.0, 0.8, 0.3], 70, 10, 1.4, 1.3, [0, 1, 0], 180, -9); burst(pos, [0.4, 0.9, 1.0], 70, 10, 1.4, 1.3, [0, 1, 0], 180, -9); },   // _chaos_event 11211-11235
  };

  return { burst, ring, shockwave, confetti, sparkler, trailBoost, trailMult, buffSparkler, spray, tick, E, COL, stats: () => ({ sparks: nAlive, rings: RG.length, confetti: CF.length, spray: SP.length, bursts: bursts.length, emitters: sparklers.length }), objects: { sparks, rings, conf, sprayM, bubbles } };
}
