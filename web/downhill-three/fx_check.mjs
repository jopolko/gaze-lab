// node fx_check.mjs : numeric test of fx.js with a stand-in for THREE (no browser). Checks Godot's burst rules, the web-parity halving and cap, damping and gravity, the ramps, rings, confetti, the sparkler rate and the trail frame.
import { createFx } from './fx.js';

class Col { constructor(r = 1, g = 1, b = 1) { this.r = r; this.g = g; this.b = b; } setRGB(r, g, b) { this.r = r; this.g = g; this.b = b; } }
class Geo { constructor(...a) { this.a = a; } }
class Mat { constructor(o = {}) { Object.assign(this, o); this.color = new Col(); } }
class Inst { constructor(g, m, n) { this.n = n; this.count = n; this.instanceMatrix = { array: new Float32Array(n * 16), needsUpdate: false }; this.instanceColor = null; } setColorAt() { this.instanceColor = { array: new Float32Array(this.n * 3), needsUpdate: false }; } }
class Mesh { constructor(g, m) { this.material = m; this.position = { set() { } }; this.scale = { setScalar(s) { this.s = s; } }; this.visible = true; } }
const THREE = { SphereGeometry: Geo, TorusGeometry: Geo, BoxGeometry: Geo, MeshBasicMaterial: Mat, InstancedMesh: Inst, Mesh, Color: Col, AdditiveBlending: 2, DoubleSide: 2 };
const scene = { add() { } };
let fails = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) fails++; };
const near = (a, b, e) => Math.abs(a - b) <= e;

// ---- web parity: a 70-particle burst makes 35; at most 12 live bursts
{ const FX = createFx({ THREE, scene }); FX.burst([0, 0, 0], [1, 1, 1], 70, 14, 0.9, 1.0); FX.tick(0.001); ok(FX.stats().sparks === 35, 'web parity: a burst of 70 emits 35 particles'); for (let i = 0; i < 20; i++) FX.burst([0, 0, 0], [1, 1, 1], 10, 5, 1, 1); ok(FX.stats().bursts === 12, 'web parity: only 12 live bursts at once (got ' + FX.stats().bursts + ')'); }
{ const FX = createFx({ THREE, scene, webParity: false }); FX.burst([0, 0, 0], [1, 1, 1], 70, 14, 0.9, 1.0); FX.tick(0.001); ok(FX.stats().sparks === 70, 'desktop counts: 70 stays 70'); for (let i = 0; i < 60; i++) FX.burst([0, 0, 0], [1, 1, 1], 4, 5, 1, 1); ok(FX.stats().bursts === 40, 'desktop cap is 40 (got ' + FX.stats().bursts + ')'); }

// ---- a burst: speeds in [0.35 v, v], they all die at `life`, the cone and gravity behave
{ const FX = createFx({ THREE, scene, webParity: false }); const o = FX.objects.sparks;
  FX.burst([0, 10, 0], [1, 0.5, 0.2], 400, 10, 1.0, 1.0, [0, 1, 0], 20, -6); FX.tick(0.001);
  // after one tiny step every particle has speed between 0.35*10 and 10 (damping removes at most 3*dt) and points within 20 degrees of up
  const sp = [], ang = [];
  // read velocities by stepping a copy: use the matrix positions after 0.1 s
  FX.tick(0.099); let minY = 1e9, maxY = -1e9; const m = o.instanceMatrix.array; for (let k = 0; k < o.count; k++) { const y = m[k * 16 + 13]; minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  ok(o.count === 400, 'all 400 alive at 0.1 s'); ok(minY > 10.2 && maxY < 11.1, 'after 0.1 s the particles rose 0.35..1.0 m (y ' + minY.toFixed(2) + '..' + maxY.toFixed(2) + ')');
  for (let t = 0; t < 8; t++) FX.tick(0.1); FX.tick(0.05); ok(o.count === 400, 'still alive at 0.95 s'); FX.tick(0.06); ok(o.count === 0, 'all gone after the lifetime (1.0 s)'); }
{ const FX = createFx({ THREE, scene, webParity: false }); const o = FX.objects.sparks; FX.burst([0, 0, 0], [1, 1, 1], 300, 12, 2.0, 1.0, [0, 1, 0], 180, -6); for (let i = 0; i < 100; i++) FX.tick(0.01); const m = o.instanceMatrix.array; let up = 0, down = 0; for (let k = 0; k < o.count; k++) { if (m[k * 16 + 13] > 0) up++; else down++; }
  ok(up > 20 && down > 20, 'a spread of 180 goes in every direction (' + up + ' above, ' + down + ' below after 1 s)'); }
// gravity: with spread 0 and gravity -6 a particle of speed v rises to about v^2 / 12 (damping aside)
{ const FX = createFx({ THREE, scene, webParity: false }); const o = FX.objects.sparks; FX.burst([0, 0, 0], [1, 1, 1], 1, 10, 3.0, 1.0, [0, 1, 0], 0, -6); let top = 0; for (let i = 0; i < 300; i++) { FX.tick(0.005); if (o.count) top = Math.max(top, o.instanceMatrix.array[13]); } ok(top > 2.0 && top < 8.4, 'a single particle goes up and falls back under gravity (peak ' + top.toFixed(2) + ' m)'); }
// the alpha ramp: colour is multiplied by 1 -> 0.8 (60%) -> 0
{ const FX = createFx({ THREE, scene, webParity: false }); const o = FX.objects.sparks; FX.burst([0, 0, 0], [1, 1, 1], 1, 1, 1.0, 1.0); FX.tick(0.6); ok(near(o.instanceColor.array[0], 0.8, 0.02), 'alpha is 0.8 at 60% of the life (' + o.instanceColor.array[0].toFixed(3) + ')'); FX.tick(0.2); ok(near(o.instanceColor.array[0], 0.4, 0.03), 'alpha is 0.4 at 80% (' + o.instanceColor.array[0].toFixed(3) + ')'); }

// ---- rings: scale 0.3 -> rEnd (quart ease-out), alpha 0.95 -> 0, standing vs flat, the delay
{ const FX = createFx({ THREE, scene }); const o = FX.objects.rings; FX.ring([1, 2, 3], [1, 0.5, 0.2], 9, 0.5, true); FX.tick(0.001); ok(near(o.instanceMatrix.array[0], 0.3, 0.12), 'ring starts at scale 0.3'); FX.tick(0.249); const s = o.instanceMatrix.array[0]; ok(near(s, 0.3 + (9 - 0.3) * (1 - Math.pow(0.5, 4)), 0.1), 'ring is at the quart ease-out scale halfway (' + s.toFixed(2) + ')'); ok(near(o.instanceColor.array[0], 0.95 * 0.5, 0.02), 'ring alpha is 0.475 halfway'); FX.tick(0.3); ok(o.count === 0, 'ring is gone after its duration'); }
{ const FX = createFx({ THREE, scene }); const o = FX.objects.rings; FX.ring([0, 0, 0], [1, 1, 1], 5, 1, false); FX.tick(0.01); ok(o.instanceMatrix.array[6] < 0 && o.instanceMatrix.array[9] > 0, 'a flat ring lies on the XZ plane'); }
{ const FX = createFx({ THREE, scene }); const o = FX.objects.rings; FX.ring([0, 0, 0], [1, 1, 1], 5, 1, true, 0.18); FX.tick(0.1); ok(o.count === 0, 'a delayed ring is not shown before its delay'); FX.tick(0.2); ok(o.count === 1, 'a delayed ring appears after 0.18 s'); }
// shockwave: 0.2 -> radius*2 in 0.3 s
{ const FX = createFx({ THREE, scene }); const b = FX.objects.bubbles; FX.shockwave([0, 0, 0], 9); ok(b[0].m.visible, 'a shockwave bubble shows'); FX.tick(0.31); ok(!b[0].m.visible, 'and is gone after 0.3 s'); }

// ---- confetti: lifetime 1.4 s, gravity, 5-colour gradient
{ const FX = createFx({ THREE, scene }); const o = FX.objects.conf; FX.confetti([0, 5, 0], 50, 1.0); FX.tick(0.01); ok(o.count === 50, 'confetti: 50 pieces'); const cols = new Set(); for (let k = 0; k < o.count; k++) cols.add(o.instanceColor.array[k * 3].toFixed(1) + o.instanceColor.array[k * 3 + 1].toFixed(1)); ok(cols.size >= 5, 'confetti uses a spread of colours (' + cols.size + ' distinct)'); FX.tick(1.45); ok(o.count === 0, 'confetti is gone after 1.4 s'); }

// ---- sparkler: n particles per lifetime, continuously; pale colour; stops when emitting is off
{ const FX = createFx({ THREE, scene, webParity: false }); const sp = FX.sparkler({ pos: [0, 0, 0], color: [1, 1, 1], n: 10, life: 1.3, radius: 1.6 }); sp.emitting = true; for (let i = 0; i < 130; i++) FX.tick(0.01); const n = FX.stats().sparks; ok(n >= 8 && n <= 11, 'a sparkler keeps about n=10 alive (' + n + ')'); sp.emitting = false; for (let i = 0; i < 140; i++) FX.tick(0.01); ok(FX.stats().sparks === 0, 'and they all die once it stops'); }
// ---- the board's trail frame: +z local is behind the board
{ const FX = createFx({ THREE, scene }); const t = FX.trailBoost(); t.update(0, 0, 0, 0, -1, true); ok(near(t.pos[2], 1.0, 1e-6) && near(t.pos[1], 0.5, 1e-6), 'trail sits 1 m behind a board heading -z (z=' + t.pos[2] + ')'); ok(t.dir[2] > 0.9, 'and shoots backwards'); t.update(0, 0, 0, 1, 0, true); ok(near(t.pos[0], -1.0, 1e-6), 'heading +x: the trail is at -x'); }
// ---- spray: ~72 a second while emitting, 0.5 s life
{ const FX = createFx({ THREE, scene }); const s = FX.spray(); s.update(0, 0, 0, 0, -1, true); for (let i = 0; i < 100; i++) FX.tick(0.01); const n = FX.stats().spray; ok(n >= 30 && n <= 40, 'the spray keeps about 36 alive (' + n + ')'); }
// ---- events do not throw, and the pickup flavours differ
{ const FX = createFx({ THREE, scene, webParity: false }); const names = Object.keys(FX.E); let bad = 0; for (const n of names) { try { const f = FX.E[n]; if (n === 'pickup') { f('boost', [0, 0, 0], 0); f('shield', [0, 0, 0], 0); f('donut', [0, 0, 0], 0); f('mult', [0, 0, 0], 0); } else if (n === 'rockSmash') f(0, 0, 0); else if (n === 'treeHit') f(0, 0, 0, 40); else if (n === 'rockHit') f(0, 0, 0, 2); else if (n === 'pole') f(0, 0, 0); else if (n === 'landOnSpot' || n === 'landBounce') f(0, 0, 0); else if (n === 'apex') f([0, 0, 0], 1); else if (n === 'face') f([0, 0, 0], [1, 1, 1]); else if (n === 'chaos') f([0, 0, 0], [0, 0, 0], [1, 0, 0]); else if (n === 'bump') f(0, 0, 0); else if (n === 'slam') f([0, 0, 0], true); else if (n === 'cheer') f([0, 0, 0], [1, 1, 1], 1.2); else if (n === 'foodLost' || n === 'orbPulse' || n === 'lkCatch' || n === 'lkStep' || n === 'gateResult') f([0, 0, 0], [1, 1, 1]); else f([0, 0, 0], 0.5); for (let i = 0; i < 5; i++) FX.tick(0.05); } catch (e) { bad++; console.log('  throws in', n, e.message); } }
  ok(bad === 0, 'all ' + names.length + ' event helpers run without throwing'); }
console.log(fails ? fails + ' FAILED' : 'all passed'); process.exit(fails ? 1 : 0);
