// SNOWBALL, ported from Godot's RunRig for the wide level in gv.js. Two kinds, as in the source:
//
//   BEHIND  (RunRig._sb_tick, lines ~1335-1431, the open-slope / trail mode): a ball spawns 75 m behind you on a steep stretch and rolls after you at 31 m/s (+7 by 4200 m).
//           It TURNS SLOWLY (x chases yours at 1.1/s), so a quick move sideways gets out of its way. It gains whenever you slow down; get 150 m ahead and you have ESCAPED
//           (+500, flow, trip +0.1, "ESCAPED THE SNOWBALL!"); stay in its path when it arrives (gap < 3.8 and |dx| < 3.9 and low) and it flattens you. The next one comes 650-1100 m later (first at 700 m).
//           The screen gets a red wash and "SNOWBALL BEHIND YOU" as it closes (close = 1 - (gap - 14) / 80), and the camera shakes (0.35 * close^2).
//   SIDE    (RunRig._spawn_ball / _update_balls / _ball_hit, lines ~7710-7836, the course mode): a ball rolls across the slope from far to one side, timed to cross where you will be in 2.6 s
//           (retimed for the first 0.9 s so the hill's speed-up cannot spoil it), radius 3, hit radius 3 + 1.1. Dodge it (+60, flow), outrun it, or take the hit
//           (speed x0.6, a sideways shove of 9, 0.5 s hurt, chain reset). An ice shield takes the hit instead. The next one is 150-230 m later (x0.7 at full difficulty).
//
// SCALING for gv.js (speeds there are SPK times Godot's, the corridor is about 4x as wide): every SPEED and the gap/escape distances are multiplied by SPK so the time to catch you is the same as in Godot;
// the spacing between balls is kept as a fraction of the course length (a 2.4 km lap cannot hold 700 m x SPK); sideways distances stay Godot's (the ball's turn rate and the 3.9 m half-width are the dodge window, and a player that moves 20 m sideways at these speeds
// is long gone, so the window stays fair on the wide course); where Godot clamps to the corridor (+-38 of 58) it is scaled by halfW / 58 here.
//
// WHAT THE CALLER MUST DO (see the end of this file for the exact lines): call sb.tick(dt) once per physics step after the player has moved; give it PH, th, toast and SFX; draw the warning in onWarn(level 0..1)
// (a red wash of alpha 0.16 * level * (0.7 + 0.3 * sin(age * 14)) and the text "SNOWBALL BEHIND YOU"); shake the camera with info().shake. The module never takes the player's momentum away completely.

const mulberry = (seed) => { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;

export function createSnowball(o) {
  const GLW = o.glow || ((m) => m);          // the glow helper from gv.js: the flat balls get a rim and a beat lift
  const { THREE, scene, th, PH, SFX = {}, onHit, onDodge, onEscape, onWarn, onShake } = o; const toast = (m, c) => o.toast(o.boulders ? String(m).replace(/SNOWBALL/g, 'BOULDER') : m, c);
  const SPK = o.SPK || 2.2, halfW = o.halfW || 120, WS = halfW / 58;
  const BALL_R = 3.0, rng = o.rng || mulberry(o.seed || 12345);
  const molColors = o.molColors || null;
  const behind = o.behind !== false, side = o.side !== false;
  const worldEnd = o.worldEnd !== undefined ? o.worldEnd : -4200, L = o.courseLen || -worldEnd;          // z of the end of the course (negative) and its length: Godot's distances (first ball 700 m, then 650-1100 m, none in the last 450 m, of a 4200 m run) are kept as FRACTIONS of the course
  const slopeAt = o.gradeAt || ((x, z) => (th(x, z + 30) - th(x, z - 30)) / 60);          // downhill steepness, Godot's steep stages are slope >= 0.34 * 1.1
  const braced = o.braced || (() => false);
  const rumble = (lv) => { if (SFX.rumble) SFX.rumble(lv); else if (SFX.land && lv > .9) SFX.land(); };

  const root = new THREE.Group(); root.name = 'snowballs'; scene.add(root);
  const col = (r, g, b, k) => { const c = new THREE.Color(); c.setRGB(r * k, g * k, b * k); return c; };          // "solid": albedo plus emission, so a little over 1
  const mats = { body: null, bump: GLW(new THREE.MeshBasicMaterial({ color: col(.45, .5, .7, 1.4) })), side: GLW(new THREE.MeshBasicMaterial({ color: col(.95, .97, 1, 1.9) })), lump: GLW(new THREE.MeshBasicMaterial({ color: col(.88, .93, 1, 1.8) })) };
  const sph = (r, ws, hs) => new THREE.SphereGeometry(r, ws, hs);
  const G_BODY = sph(3, 16, 8), G_BUMP = sph(.7, 6, 3), G_LUMP = sph(1.1, 6, 3);
  // ---- BOULDERS (o.boulders): the rolling balls are rocks, not snowballs. One low-poly lumpy icosphere (flat facets) shared by all, and four cheap procedural rock looks (granite, sandstone, mossy, basalt):
  // a base and a lighter colour mixed by layered noise, dark hairline cracks, a sun-lit side and a faint rim. One small shader, no texture files; a boulder costs about as much as the old ball.
  const BOULD = !!o.boulders; const toastO = toast;
  const rockGeo = BOULD ? (() => { const g = new THREE.IcosahedronGeometry(3, 3).toNonIndexed(), p = g.attributes.position, hh = (x, y, z) => { const s = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453; return s - Math.floor(s); }; for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i), z = p.getZ(i), k = .8 + .38 * hh(Math.round(x * 20) / 20, Math.round(y * 20) / 20, Math.round(z * 20) / 20); p.setXYZ(i, x * k, y * k * .92, z * k); } g.computeVertexNormals(); return g; })() : null;
  const ROCKS = [[[.38, .39, .42], [.66, .66, .7]], [[.55, .4, .25], [.88, .7, .46]], [[.28, .34, .22], [.62, .64, .5]], [[.13, .13, .16], [.36, .35, .41]]];
  const rockMats = BOULD ? ROCKS.map(([a, b]) => new THREE.ShaderMaterial({ uniforms: { uBase: { value: new THREE.Color().setRGB(a[0], a[1], a[2]) }, uAlt: { value: new THREE.Color().setRGB(b[0], b[1], b[2]) }, uSun: { value: new THREE.Vector3(.4, .8, .3) } },
    vertexShader: 'varying vec3 vN, vW, vL; void main() { vL = position; vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal); gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: 'uniform vec3 uBase, uAlt, uSun; varying vec3 vN, vW, vL; float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); } float n(vec3 p) { vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y), mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z); } void main() { vec3 N = normalize(vN); float g = n(vL * 1.6) * 0.6 + n(vL * 5.0) * 0.3 + n(vL * 14.0) * 0.1; float crack = smoothstep(0.0, 0.07, abs(n(vL * 3.2) - 0.5)); vec3 c = mix(uBase, uAlt, g) * (0.7 + 0.3 * crack); float dl = max(dot(N, normalize(uSun)), 0.0), rim = pow(1.0 - max(dot(N, normalize(cameraPosition - vW)), 0.0), 3.0); c *= 0.5 + 0.7 * dl; c += rim * 0.12; gl_FragColor = vec4(c, 1.0); }' })) : null;
  const rockMesh = (rv) => new THREE.Mesh(rockGeo, rockMats[rv % rockMats.length]);
  const toastB = (m, c) => toastO(BOULD ? String(m).replace(/SNOWBALL/g, 'BOULDER') : m, c);

  // ---- state
  const S = { on: false, z: 0, x: 0, next: .167 * L, close: 0, mol: 0, mesh: null, group: null, rumbleT: 0, spawned: 0, escaped: 0, hit: 0, dodged: 0, shield: 0, age: 0, shake: 0 };
  let balls = [], nextBallZ = -420 * SPK;

  function pickMol() { return o.pickMol ? o.pickMol() : Math.floor(rng() * 6); }
  function makeBehind() {
    const g = new THREE.Group(), m = new THREE.Group(); g.add(m);
    const mc = molColors && molColors[S.mol] ? molColors[S.mol] : [.8, .85, 1];
    const base = [.92, .96, 1], c = [lerp(base[0], mc[0], .5), lerp(base[1], mc[1], .5), lerp(base[2], mc[2], .5)];
    const body = BOULD ? rockMesh(Math.floor(rng() * 4)) : new THREE.Mesh(G_BODY, GLW(new THREE.MeshBasicMaterial({ color: col(c[0], c[1], c[2], 1.9) }))); m.add(body);
    for (let i = 0; i < (BOULD ? 0 : 7); i++) { const b = new THREE.Mesh(G_BUMP, mats.bump); const v = [rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1], l = Math.hypot(v[0], v[1], v[2]) || 1; b.position.set(v[0] / l * 2.9, v[1] / l * 2.9, v[2] / l * 2.9); m.add(b); }
    root.add(g); S.group = g; S.mesh = m;
  }
  function removeBehind() { if (S.group) { root.remove(S.group); S.group = null; S.mesh = null; } }

  function endBehind(escaped) {
    const dist = -PH.z; removeBehind(); S.on = false; S.close = 0; S.next = dist + (.155 + rng() * .107) * L;
    if (onWarn) onWarn(0);
    if (escaped) { S.escaped++; PH.score += 500; toast('ESCAPED THE SNOWBALL!', '#cdf'); if (onEscape) onEscape(); }
  }

  // what a hit does (RunRig._crash for the behind ball, _ball_hit for the side ball), softened as everywhere in gv.js: you keep going.
  function hurtPlayer(kind, vxDir) {
    if (PH.hurt > 0) return false;
    if (braced()) { PH.vx *= .9; PH.vz *= .9; PH.score += 80; toast('BRACED!', '#9ef'); S.shake = Math.max(S.shake, .5); return true; }
    if (PH.shield > 0) { PH.shield = 0; PH.hurt = .8; toast('ICE SHIELD TOOK IT', '#5df'); S.shake = Math.max(S.shake, .5); if (SFX.shield) SFX.shield(); return true; }
    S.hit++; PH.vx *= .75; PH.vz *= .75; PH.vx += Math.sign(vxDir || (Math.random() - .5)) * 9 * SPK * .5; PH.hurt = Math.max(PH.hurt, .5); PH.score = Math.max(0, PH.score - 100);
    toast(kind === 'behind' ? 'FLATTENED BY THE SNOWBALL' : 'SNOWBALL HIT', '#f96'); S.shake = .9; if (SFX.hurt) SFX.hurt(); if (SFX.boom) SFX.boom(); else if (SFX.thwack) SFX.thwack();
    if (onHit) onHit(kind); return true;
  }

  function tickBehind(dt) {
    const dist = -PH.z;
    if (!S.on) {
      if (dist >= S.next && PH.grounded && slopeAt(PH.x, PH.z) > .34 * 1.1 && PH.z > worldEnd + .107 * L) {
        S.on = true; S.z = PH.z + 75 * SPK; S.x = PH.x; S.mol = pickMol(); S.spawned++; S.rumbleT = 0; makeBehind();
        toast('SNOWBALL!  RUN!', '#cdf'); rumble(1);
      }
      return;
    }
    const prog = clamp(dist / 4200, 0, 1), v = (31 + 7 * prog) * SPK;
    S.z -= v * dt; S.x += (PH.x - S.x) * clamp(dt * 1.1, 0, 1);          // it turns slowly: a quick move to the side gets out of its way
    const gap = S.z - PH.z;
    if (S.group) { S.group.position.set(S.x, th(S.x, S.z) + 3, S.z); S.mesh.rotation.x += v * dt / 3; }
    S.close = clamp(1 - (gap - 14 * SPK) / (80 * SPK), 0, 1);
    S.shake = Math.max(S.shake, .35 * S.close * S.close); if (onShake) onShake(S.shake);
    S.rumbleT -= dt; if (S.rumbleT <= 0 && S.close > .05) { S.rumbleT = 1.8 - 1.2 * S.close; rumble(S.close); }
    if (onWarn) onWarn(S.close);
    if (gap < 3.8 + 1.2 * (SPK - 1) && Math.abs(PH.x - S.x) < 3.9 && PH.y - th(PH.x, PH.z) < 3.5 && PH.hurt <= 0) { const dir = Math.sign(PH.x - S.x); endBehind(false); hurtPlayer('behind', dir); }
    else if (gap > 150 * SPK) endBehind(true);
  }

  // ---- side-rolling balls
  function spawnSide() {
    const d = clamp(-PH.z / 3500, 0, 1), T = 2.6, sp = Math.max(-PH.vz, 24 * SPK);
    const lim = 38 * WS, px = clamp(PH.x + PH.vx * T, -lim, lim), pz = PH.z - sp * T, vb = (12 + 6 * d) * SPK, sd = px < 0 ? 1 : -1;
    const sx = clamp(px + sd * 44 * Math.sqrt(WS), -(halfW - 4), halfW - 4), sz = pz + vb * T, vx = (px - sx) / T;
    const n = new THREE.Group(); n.add(BOULD ? rockMesh(Math.floor(rng() * 4)) : new THREE.Mesh(G_BODY, mats.side)); for (let i = 0; i < (BOULD ? 0 : 5); i++) { const a = i * 1.7, l = new THREE.Mesh(G_LUMP, mats.lump); l.position.set(Math.cos(a) * 2.4, Math.sin(a * 1.3) * 2.4, Math.sin(a) * 2.4); n.add(l); }
    n.position.set(sx, th(sx, sz) + BALL_R, sz); root.add(n); balls.push({ n, x: sx, z: sz, vx, vz: -vb, t: 0, done: false });
    S.spawned++; nextBallZ = PH.z - (150 + rng() * 80) * lerp(1, .7, d) * SPK; toast('SNOWBALL!', '#cdf'); if (SFX.whoosh) SFX.whoosh(); else rumble(.6);
  }
  function tickSide(dt) {
    if (!S.on && !balls.length && PH.z < nextBallZ && PH.z > worldEnd + 260 * SPK) spawnSide();
    for (let i = balls.length - 1; i >= 0; i--) {
      const b = balls[i]; b.t += dt; b.x += b.vx * dt; b.z += b.vz * dt;
      if (b.t < .9 && b.vx !== 0) { let tl = Math.abs((PH.x + PH.vx * 1.5 - b.x) / b.vx); tl = clamp(tl, .6, 4); const want = (PH.z + PH.vz * tl - b.z) / tl; b.vz = lerp(b.vz, clamp(want, -34 * SPK, -8 * SPK), .15); }          // the first moments: keep the roll timed to where you will be
      b.n.position.set(b.x, th(b.x, b.z) + BALL_R, b.z); b.n.rotation.x += b.vz * dt / BALL_R; b.n.rotation.z += -b.vx * dt / BALL_R;
      if (!b.done) {
        const dx = PH.x - b.x, dz = PH.z - b.z, above = PH.y - th(PH.x, PH.z), R = BALL_R + 1.1 + 1.2 * (SPK - 1);
        if (dx * dx + dz * dz < R * R && above < BALL_R + 1) { b.done = true; hurtPlayer('side', b.vx); b.gone = true; b.n.visible = false; }
        else if (b.z > PH.z + 6 * SPK) { b.done = true; S.dodged++; PH.score += 60; toast('DODGED', '#aef'); if (onDodge) onDodge(); }
      }
      if (b.z > PH.z + 70 * SPK || b.t > 14 || b.gone) { root.remove(b.n); balls.splice(i, 1); }
    }
  }

  function tick(dt) {
    S.age += dt; S.shake = Math.max(S.shake - dt * 1.6, 0);
    if (behind) tickBehind(dt);
    if (side) tickSide(dt);
  }
  function reset() { removeBehind(); for (const b of balls) root.remove(b.n); balls = []; S.on = false; S.close = 0; S.next = .167 * L; nextBallZ = -420 * SPK; S.shake = 0; if (onWarn) onWarn(0); }
  const info = () => ({ on: S.on, gap: S.on ? S.z - PH.z : null, close: S.close, shake: S.shake, balls: balls.length, spawned: S.spawned, escaped: S.escaped, hit: S.hit, dodged: S.dodged, next: S.next, x: S.x, z: S.z });
  return { tick, reset, mesh: root, info, state: S };
}

/* INTEGRATION in gv.js (the parent applies these):
   1. import { createSnowball } from './snowball.js';                                          (next to the other imports)
   2. after SFX and toast exist and PH, th, MOLS exist (e.g. right after `toys = createToys(...)`):
        const SB = createSnowball({ THREE, scene, th, PH, toast, SFX, SPK, halfW: C.W_HALF, worldEnd: WORLD_END, molColors: MOL_ORDER.map((id) => MOLS[id].c),
          onHit: () => { PH.chain = 0; }, onDodge: () => chainHit(), onEscape: () => { chainHit(); chainHit(); }, onWarn: (lv) => { PH.sbWarn = lv; }, onShake: (v) => { PH.shake = Math.max(PH.shake || 0, v); } });
      (WORLD_END is defined in the world-building block; if SB is created earlier, pass worldEnd later with `SB.state` untouched or create SB after buildWorld.)
   3. in playStep, after the board has moved and the collision/collect steps:   SB.tick(dt);
   4. when a lap ends or the run restarts (where buildWorld() is called):          SB.reset();
   5. add to the SFX object a rumble (the ball approaching):
        rumble: (lv) => { tone(55, 38, .9, .35 * (lv || 1), 'sawtooth'); noise(.8, .22 * (lv || 1), 120, .7); },
      and a boom if missing:  boom: () => { tone(90, 30, .5, .55); noise(.35, .4, 400, .8); },
   6. HUD warning: add one div (a red full-screen wash + text) and each frame set
        warn.style.opacity = (PH.sbWarn || 0) > .02 ? 0.16 * PH.sbWarn * (0.7 + 0.3 * Math.sin(now * .014)) : 0;  and show the text "SNOWBALL BEHIND YOU" with opacity .9 * PH.sbWarn.
   7. camera shake (optional): add (Math.random() - .5) * 0.6 * (PH.shake || 0) to camera.position.x/y after it is set, and decay PH.shake by 1.6/s.
*/
