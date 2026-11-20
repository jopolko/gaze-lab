// node tiers_check.mjs : the governor against scripted frame-rate traces, and the tier table.
import { createTiers, tierFlags, pixelBudget } from './tiers.js';
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const run = (T, seconds, fps, trk = 60, cam = false, dtFrame = null) => { const calls = []; const dt = 1 / fps; let t = 0; const o = T; while (t < seconds) { const before = o.tier; o.state.fps = fps; o.frame(dt); t += dt; if (o.tier !== before) calls.push([+t.toFixed(1), o.tier]); } return calls; };
const mk = (extra = {}) => createTiers(Object.assign({ isTouch: true, isWeb: true, trackerOn: () => false, trackerFps: () => 60, hooks: {} }, extra));
// a web / phone build starts at its floor, tier 1, and never goes above it
{ const T = mk(); ok(T.tier === 1 && T.floorTier === 1, 'web build starts at tier 1 (the floor)'); run(T, 60, 60); ok(T.tier === 1, 'stays at tier 1 at 60 fps for a minute (never reaches 0)'); }
// below 50 fps: one step down after 3 s of pressure (checked every 2 s: so at the second check, t = 4 s), then 6 s cool-down, so the next step is at 10 s
{ const T = mk(); const c = run(T, 14, 40); ok(c.length === 2 && Math.abs(c[0][0] - 4) < .2 && c[0][1] === 2, 'tier 2 at about 4 s of 40 fps: ' + JSON.stringify(c)); ok(c[1] && Math.abs(c[1][0] - 10) < .2 && c[1][1] === 3, 'tier 3 about 6 s later (cool-down): ' + JSON.stringify(c)); run(T, 30, 40); ok(T.tier === 3, 'never past tier 3'); }
// back up: 16 s at 55+ fps per step, and never past the floor
{ const T = mk(); run(T, 14, 40); ok(T.tier === 3, 'at tier 3'); const c = run(T, 50, 60); ok(c.length === 2 && Math.abs(c[0][0] - 16) < .6 && c[0][1] === 2 && Math.abs(c[1][0] - 32) < .6 && c[1][1] === 1, 'up one step per 16 s, stops at the floor: ' + JSON.stringify(c)); }
// a short dip does not trigger and the pressure timer drains
{ const T = mk(); run(T, 2, 40); run(T, 4, 60); run(T, 2, 40); ok(T.tier === 1, 'a 2 s dip, a recovery and another 2 s dip: still tier 1'); }
// 52 fps is neither pressure nor good enough to climb: holds
{ const T = mk(); run(T, 14, 40); run(T, 40, 52); ok(T.tier === 3, 'between 50 and 55 fps it holds its tier'); }
// a starving tracker is answered in 2 s
{ let trk = 8; const T = mk({ trackerOn: () => true, trackerFps: () => trk }); const c = run(T, 3, 60); ok(c.length === 1 && c[0][0] <= 2.1, 'tracker below 10.5 fps: tier down after one 2 s check: ' + JSON.stringify(c)); }
// a desktop web build may be pinned to 0 for testing (floorTier 0)
{ const T = createTiers({ isTouch: false, isWeb: true, floorTier: 0, startTier: 0, hooks: {} }); ok(T.tier === 0, 'desktop with floorTier 0 can start at tier 0'); }
{ const T = mk({ pin: 2 }); T.frame(0.016); ok(T.tier === 2, 'pin forces a tier'); }
// the table
const f0 = tierFlags(0, true), f1 = tierFlags(1, true), f1d = tierFlags(1, false), f2 = tierFlags(2, true), f3 = tierFlags(3, true);
ok(f0.grade && !f1.grade, 'colour grade only at tier 0'); ok(f0.groundDetail && !f1.groundDetail, 'ground detail only at tier 0'); ok(f1.glow && !f2.glow, 'glow off from tier 2'); ok(!f1.trails && f1d.trails, 'trails pass: off at tier 1 on a phone, on for desktop');
ok(!f1.snow && f1d.snow, 'snow: off at tier 1 on a phone, on for desktop'); ok(f2.postLook && !f3.postLook, 'full-screen pass off at tier 3'); ok(f2.sky && !f3.sky, 'sky off at tier 3'); ok(f1.shafts && !f2.shafts, 'shafts off from tier 2');
ok(JSON.stringify([f0.scale, f1.scale, f2.scale, f3.scale]) === '[1,1,0.88,0.76]', 'phone render scale [1, 1, .88, .76]'); ok(JSON.stringify([f1.vegRange, f2.vegRange, f3.vegRange]) === '[260,210,160]', 'phone vegetation range 260 / 210 / 160');
// the pixel budget: a 390x844 phone at devicePixelRatio 3 is 2.96 Mpx, the budget .95 Mpx
{ let ratio = 0; const T = mk({ cssSize: () => [390, 844], dpr: () => 3, hooks: { setPixelRatio: (r) => { ratio = r; } } }); T.apply(); const want = 3 * Math.sqrt(pixelBudget(true, false) / (390 * 844 * 9)); ok(Math.abs(ratio - want) < 1e-6, 'phone pixel ratio ' + ratio.toFixed(3) + ' = dpr * sqrt(budget / pixels)'); }
console.log(fails ? fails + ' FAILED' : 'all passed'); process.exit(fails ? 1 : 0);
