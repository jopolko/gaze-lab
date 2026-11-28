// SNOWBALL (Babylon port of downhill-three/snowball.js, 2026-11-28), ported from Godot's RunRig for the wide level. Two kinds, as in the source:
//
//   BEHIND  (RunRig._sb_tick, lines ~1335-1431, the open-slope / trail mode): a ball spawns 75 m behind you on a steep stretch and rolls after you at 31 m/s (+7 by 4200 m).
//           It TURNS SLOWLY (x chases yours at 1.1/s), so a quick move sideways gets out of its way. It gains whenever you slow down; get 150 m ahead and you have ESCAPED
//           (+500, flow, trip +0.1, "ESCAPED THE SNOWBALL!"); stay in its path when it arrives (gap < 3.8 and |dx| < 3.9 and low) and it flattens you. The next one comes 650-1100 m later (first at 700 m).
//           The screen gets a red wash and "SNOWBALL BEHIND YOU" as it closes (close = 1 - (gap - 14) / 80), and the camera shakes (0.35 * close^2).
//   SIDE    (RunRig._spawn_ball / _update_balls / _ball_hit, lines ~7710-7836, the course mode): a ball rolls across the slope from far to one side, timed to cross where you will be in 2.6 s
//           (retimed for the first 0.9 s so the hill's speed-up cannot spoil it), radius 3, hit radius 3 + 1.1. Dodge it (+60, flow), outrun it, or take the hit
//           (speed x0.6, a sideways shove of 9, 0.5 s hurt, chain reset). An ice shield takes the hit instead. The next one is 150-230 m later (x0.7 at full difficulty).
//
// SCALING: every SPEED and the gap/escape distances are multiplied by SPK so the time to catch you is the same as in Godot; the spacing between balls is a fraction of the course length;
// sideways distances stay Godot's; where Godot clamps to the corridor (+-38 of 58) it is scaled by halfW / 58 here.
//
// THE PORT: the three.js version kept its balls in a hidden three.js scene that the game copied into Babylon every frame. Here they are Babylon nodes in the game's own scene
// (TransformNode = THREE.Group, a Mesh per shape with instances = THREE.Mesh), the same geometry from geo3.js (three's generators), the same rock shader in Babylon's GLSL,
// and three's MeshBasicMaterial colours as unlit Babylon materials. Rotations use rotation.x / .z as in the original (three's Euler order XYZ; the tumble looks the same).
import { createGeo3 } from './geo3.js';
const mulberry = (seed) => { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;

export function createSnowball(o) {
  const GLW = o.glow || ((m) => m);          // the glow helper: the flat balls get a rim and a beat lift
  const { B, scene, th, PH, SFX = {}, onHit, onDodge, onEscape, onWarn, onShake } = o; const toast = (m, c) => o.toast(o.boulders ? String(m).replace(/SNOWBALL/g, 'BOULDER') : m, c);
  const G3 = createGeo3(B);
  const SPK = o.SPK || 2.2, halfW = o.halfW || 120, WS = halfW / 58;
  const BALL_R = 3.0, rng = o.rng || mulberry(o.seed || 12345);
  const molColors = o.molColors || null;
  const behind = o.behind !== false, side = o.side !== false;
  const worldEnd = o.worldEnd !== undefined ? o.worldEnd : -4200, L = o.courseLen || -worldEnd;
  const slopeAt = o.gradeAt || ((x, z) => (th(x, z + 30) - th(x, z - 30)) / 60);
  const braced = o.braced || (() => false);
  const rumble = (lv) => { if (SFX.rumble) SFX.rumble(lv); else if (SFX.land && lv > .9) SFX.land(); };

  const root = new B.TransformNode('snowballs', scene);
  // three MeshBasicMaterial({ color }): unlit, the colour as given ("solid": albedo plus emission, so a little over 1)
  const basic = (r, g, b, k) => { const m = new B.StandardMaterial('sbBasic', scene); m.disableLighting = true; m.emissiveColor = new B.Color3(r * k, g * k, b * k); m.diffuseColor = new B.Color3(0, 0, 0); m.specularColor = new B.Color3(0, 0, 0); return m; };
  const mats = { bump: GLW(basic(.45, .5, .7, 1.4)), side: GLW(basic(.95, .97, 1, 1.9)), lump: GLW(basic(.88, .93, 1, 1.8)) };
  const srcOf = (name, vd, mat) => { const m = new B.Mesh(name, scene); vd.applyToMesh(m); m.material = mat; m.isVisible = false; m.isPickable = false; m.parent = null; return m; };
  const G_BODY = G3.sphere(3, 16, 8), G_BUMP = G3.sphere(.7, 6, 3), G_LUMP = G3.sphere(1.1, 6, 3);
  const SRC = { bump: srcOf('sbBump', G_BUMP, mats.bump), side: srcOf('sbSide', G3.clone(G_BODY), mats.side), lump: srcOf('sbLump', G_LUMP, mats.lump) };
  const inst = (src, parent) => { const i = src.createInstance(src.name + 'I'); i.parent = parent; i.isPickable = false; i.alwaysSelectAsActiveMesh = true; return i; };
  // ---- BOULDERS (o.boulders): the rolling balls are rocks, not snowballs. One low-poly lumpy icosphere (flat facets) shared by all, and four cheap procedural rock looks (granite, sandstone, mossy, basalt):
  // a base and a lighter colour mixed by layered noise, dark hairline cracks, a sun-lit side and a faint rim. One small shader, no texture files.
  const BOULD = !!o.boulders; const toastO = toast;
  const rockGeo = BOULD ? (() => { const g = G3.icosahedron(3, 3), p = g.positions, hh = (x, y, z) => { const s = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453; return s - Math.floor(s); };
    for (let i = 0; i < p.length; i += 3) { const x = p[i], y = p[i + 1], z = p[i + 2], k = .8 + .38 * hh(Math.round(x * 20) / 20, Math.round(y * 20) / 20, Math.round(z * 20) / 20); p[i] = x * k; p[i + 1] = y * k * .92; p[i + 2] = z * k; } return G3.flatNormals(g); })() : null;          // (three: toNonIndexed, displaced, computeVertexNormals = flat on a non-indexed mesh)
  const ROCKS = [[[.38, .39, .42], [.66, .66, .7]], [[.55, .4, .25], [.88, .7, .46]], [[.28, .34, .22], [.62, .64, .5]], [[.13, .13, .16], [.36, .35, .41]]];
  if (BOULD) {
    B.Effect.ShadersStore.sbRockVertexShader = 'precision highp float; attribute vec3 position; attribute vec3 normal; uniform mat4 viewProjection; varying vec3 vN; varying vec3 vW; varying vec3 vL;\n#include<instancesDeclaration>\nvoid main(void) {\n#include<instancesVertex>\nvL = position; vec4 w = finalWorld * vec4(position, 1.0); vW = w.xyz; vN = normalize(mat3(finalWorld) * normal); gl_Position = viewProjection * w; }';
    B.Effect.ShadersStore.sbRockFragmentShader = 'precision highp float; uniform vec3 uBase; uniform vec3 uAlt; uniform vec3 uSun; uniform vec3 uCam; varying vec3 vN; varying vec3 vW; varying vec3 vL; float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); } float n(vec3 p) { vec3 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y), mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z); } void main(void) { vec3 N = normalize(vN); float g = n(vL * 1.6) * 0.6 + n(vL * 5.0) * 0.3 + n(vL * 14.0) * 0.1; float crack = smoothstep(0.0, 0.07, abs(n(vL * 3.2) - 0.5)); vec3 c = mix(uBase, uAlt, g) * (0.7 + 0.3 * crack); float dl = max(dot(N, normalize(uSun)), 0.0), rim = pow(1.0 - max(dot(N, normalize(uCam - vW)), 0.0), 3.0); c *= 0.5 + 0.7 * dl; c += rim * 0.12; gl_FragColor = vec4(c, 1.0); }';
  }
  const rockMats = BOULD ? ROCKS.map(([a, b], k) => { const m = new B.ShaderMaterial('sbRock' + k, scene, { vertex: 'sbRock', fragment: 'sbRock' }, { attributes: ['position', 'normal'], uniforms: ['world', 'viewProjection', 'uBase', 'uAlt', 'uSun', 'uCam'] }); m.setColor3('uBase', new B.Color3(a[0], a[1], a[2])); m.setColor3('uAlt', new B.Color3(b[0], b[1], b[2])); m.setVector3('uSun', new B.Vector3(.4, .8, .3)); m.onBindObservable.add(() => { const c = scene.activeCamera; if (c) m.getEffect().setVector3('uCam', c.globalPosition); }); return m; }) : null;
  const ROCKSRC = BOULD ? rockMats.map((m, k) => srcOf('sbRock' + k, G3.clone(rockGeo), m)) : null;
  const rockMesh = (rv, parent) => inst(ROCKSRC[rv % ROCKSRC.length], parent);
  const bodySrc = {}; const bodyOf = (c) => { const k = c.map((x) => x.toFixed(3)).join(','); return bodySrc[k] || (bodySrc[k] = srcOf('sbBody', G3.clone(G_BODY), GLW(basic(c[0], c[1], c[2], 1.9)))); };
  const toastB = (m, c) => toastO(BOULD ? String(m).replace(/SNOWBALL/g, 'BOULDER') : m, c);

  // ---- state
  const S = { on: false, z: 0, x: 0, next: .167 * L, close: 0, mol: 0, mesh: null, group: null, rumbleT: 0, spawned: 0, escaped: 0, hit: 0, dodged: 0, shield: 0, age: 0, shake: 0 };
  let balls = [], nextBallZ = -420 * SPK;

  function pickMol() { return o.pickMol ? o.pickMol() : Math.floor(rng() * 6); }
  function makeBehind() {
    const g = new B.TransformNode('sbBehind', scene), m = new B.TransformNode('sbSpin', scene); g.parent = root; m.parent = g;
    const mc = molColors && molColors[S.mol] ? molColors[S.mol] : [.8, .85, 1];
    const base = [.92, .96, 1], c = [lerp(base[0], mc[0], .5), lerp(base[1], mc[1], .5), lerp(base[2], mc[2], .5)];
    if (BOULD) rockMesh(Math.floor(rng() * 4), m); else inst(bodyOf(c), m);
    for (let i = 0; i < (BOULD ? 0 : 7); i++) { const b = inst(SRC.bump, m); const v = [rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1], l = Math.hypot(v[0], v[1], v[2]) || 1; b.position.set(v[0] / l * 2.9, v[1] / l * 2.9, v[2] / l * 2.9); }
    S.group = g; S.mesh = m;
  }
  function removeBehind() { if (S.group) { S.group.dispose(false, false); S.group = null; S.mesh = null; } }

  function endBehind(escaped) {
    const dist = -PH.z; removeBehind(); S.on = false; S.close = 0; S.next = dist + (.155 + rng() * .107) * L;
    if (onWarn) onWarn(0);
    if (escaped) { S.escaped++; PH.score += 500; toast('ESCAPED THE SNOWBALL!', '#cdf'); if (onEscape) onEscape(); }
  }

  // what a hit does (RunRig._crash for the behind ball, _ball_hit for the side ball), softened: you keep going.
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
    if (gap < 3.8 + 1.2 * (SPK - 1) && Math.abs(PH.x - S.x) < 3.9 && PH.y - th(PH.x, PH.z) < 3.5 && PH.hurt <= 0) { const dir = Math.sign(PH.x - S.x) || 1; throwBoulder(S.group, -dir, v); endBehind(false); hurtPlayer('behind', dir); }
    else if (gap > 150 * SPK) endBehind(true);
  }

  // ---- side-rolling balls
  function spawnSide() {
    const d = clamp(-PH.z / 3500, 0, 1), T = 2.6, sp = Math.max(-PH.vz, 24 * SPK);
    const lim = 38 * WS, px = clamp(PH.x + PH.vx * T, -lim, lim), pz = PH.z - sp * T, vb = (12 + 6 * d) * SPK, sd = px < 0 ? 1 : -1;
    const sx = clamp(px + sd * 44 * Math.sqrt(WS), -(halfW - 4), halfW - 4), sz = pz + vb * T, vx = (px - sx) / T;
    const n = new B.TransformNode('sbSide', scene); n.parent = root; if (BOULD) rockMesh(Math.floor(rng() * 4), n); else inst(SRC.side, n); for (let i = 0; i < (BOULD ? 0 : 5); i++) { const a = i * 1.7, l = inst(SRC.lump, n); l.position.set(Math.cos(a) * 2.4, Math.sin(a * 1.3) * 2.4, Math.sin(a) * 2.4); }
    n.position.set(sx, th(sx, sz) + BALL_R, sz); balls.push({ n, x: sx, z: sz, vx, vz: -vb, t: 0, done: false });
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
        if (dx * dx + dz * dz < R * R && above < BALL_R + 1) { b.done = true; hurtPlayer('side', b.vx); throwBoulder(b.n, Math.sign(b.vx) || 1, Math.abs(b.vz)); b.gone = true; b.n.setEnabled(false); }
        else if (b.z > PH.z + 6 * SPK) { b.done = true; S.dodged++; PH.score += 60; toast('DODGED', '#aef'); if (onDodge) onDodge(); }
      }
      if (b.z > PH.z + 70 * SPK || b.t > 14 || b.gone) { b.n.dispose(false, false); balls.splice(i, 1); }
    }
  }

  // A BOULDER THAT HITS YOU IS KNOCKED AWAY: it leaps ahead of you and to the side, tumbling and bouncing on the hill, so you see it go, then it is gone.
  const debris = [];
  function throwBoulder(src, side, speed) {
    if (!src) return; const n = src.clone('sbDebris', root); n.position.copyFrom(src.position); n.setEnabled(true); for (const c of n.getChildMeshes()) c.setEnabled(true);
    debris.push({ n, vx: side * (9 + rng() * 7), vy: 11 + rng() * 5, vz: -(Math.max(speed, 20 * SPK) * 1.05 + 8 + rng() * 8), rx: (rng() - .5) * 9, rz: (rng() - .5) * 9, age: 0 });
  }
  function stepDebris(dt) {
    for (let i = debris.length - 1; i >= 0; i--) {
      const d = debris[i]; d.age += dt; d.vy -= 26 * dt; const p = d.n.position; p.x += d.vx * dt; p.y += d.vy * dt; p.z += d.vz * dt; d.n.rotation.x += d.rx * dt; d.n.rotation.z += d.rz * dt;
      const g = th(p.x, p.z) + 3; if (p.y < g) { p.y = g; d.vy = Math.abs(d.vy) * .55; d.vx *= .8; d.vz *= .85; }
      if (d.age > 4.5) { d.n.dispose(false, false); debris.splice(i, 1); }
    }
  }
  function tick(dt) {
    S.age += dt; stepDebris(dt); S.shake = Math.max(S.shake - dt * 1.6, 0);
    if (behind) tickBehind(dt);
    if (side) tickSide(dt);
  }
  function reset() { removeBehind(); for (const d of debris) d.n.dispose(false, false); debris.length = 0; for (const b of balls) b.n.dispose(false, false); balls = []; S.on = false; S.close = 0; S.next = .167 * L; nextBallZ = -420 * SPK; S.shake = 0; if (onWarn) onWarn(0); }
  const info = () => ({ on: S.on, gap: S.on ? S.z - PH.z : null, close: S.close, shake: S.shake, balls: balls.length, spawned: S.spawned, escaped: S.escaped, hit: S.hit, dodged: S.dodged, next: S.next, x: S.x, z: S.z });
  return { tick, reset, mesh: root, info, state: S };
}
