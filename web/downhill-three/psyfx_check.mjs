// Regression check: replay the scripted run captured from the real Godot game (web/data/psy_states.json, made by godot/tests/dump_states.gd) through psyfx.js and compare every number.
//   node psyfx_check.mjs [path/to/psy_states.json]
import fs from 'fs';
import { createPsyFx, BIOME } from './psyfx.js';
const B = { res: null };

const J = JSON.parse(fs.readFileSync(process.argv[2] || new URL('../data/psy_states.json', import.meta.url), 'utf8'));
const Q = { clr: [...J.draws.clr], sharp: [...J.draws.sharp], efc: [...J.draws.efc], efcpeek: [...J.draws.efcpeek], god: [...J.draws.god], calm: J.draws.calm.map((x) => x[1]) };
const rand = (lo, hi, tag) => {
  const q = Q[tag]; if (!q || !q.length) { console.log('  (no recorded draw left for', tag, ')'); return lo; }
  const v = q.shift(); if (tag === 'calm') return v; if (tag === 'efcpeek') return v ? .2 : .8; return v;
};
const P = createPsyFx({ seed: 7, sessionMin: 10, cfgTrip: 1, journey: true, intensity: .8, fx: { x_clear: 2 }, rand, onBiome: (w, k, d) => { B.res = P.biomeApply(BIOME[w], k, d, { waveAhead: .5 }, { haz: .6, jump: .72, pad: .12, glint: 1, grip: 1 }); } });
const dt = 1 / 60, plan = { 3: 0, 12: 1, 22: 2, 32: 3, 42: 4, 52: 5, 70: 0 };
const NAMES = ['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'];
const DEF = { onset: 1, trip: 0, amount: 1, breathe: 0, mode: 0, use_trail: 0, k_chroma: 1, k_trace: 1, k_punch: 1, k_warp: 1, k_pulse: 1, k_wash: 0, k_edge: 0, k_cel: 0, tube: 0, smear: 0, rewind: 0, dmt: 0, buzz: 0, sharp: 0 };
const err = {}; const note = (k, a, b, t) => { if (b === null || b === undefined) b = DEF[k.replace('u.', '')] !== undefined ? DEF[k.replace('u.', '')] : 0; const e = Math.abs(a - b); if (!err[k]) err[k] = { max: 0, n: 0 }; const R = err[k]; R.n++; if (e > .002 && R.first === undefined) { R.first = t; R.fjs = a; R.fgd = b; } if (e > R.max) { R.max = e; R.t = t; R.js = a; R.gd = b; } };
const arr = (k, a, b, t) => a.forEach((x, i) => note(k + '[' + i + ']', x, b[i], t));

for (let f = 0; f < J.ctx.length; f++) {
  const t = f * dt, c = J.ctx[f];
  for (const et of Object.keys(plan)) if (Math.abs(t - +et) < dt * .5) P.events.onMolecule(plan[et], NAMES[plan[et]]);
  if (Math.abs(t - 4) < dt * .5) P.flowUp(1); if (Math.abs(t - 6) < dt * .5) P.flowUp(2);
  if (Math.abs(t - 8) < dt * .5) P.chainHit('mult'); if (Math.abs(t - 9) < dt * .5) P.chainHit('boost');
  if (Math.abs(t - 15) < dt * .5) P.cheer('TEST', 'white', 1.5);
  if (Math.abs(t - 20) < dt * .5) P.camera.shake = .9;
  if (Math.abs(t - 75) < dt * .5) P.sharpen(1);
  { const C2 = J.ctx2 ? J.ctx2[f] : c, mk = (r) => ({ speed: r[0], speedY: r[1], chain: r[2], boosting: !!r[3], links: r[4], alt: r[5], vy: r[6], inAir: !!r[7], hurtT: r[8], rail: !!r[9], tube: !!r[10], wave: r[11] }); P.state.age += dt; P.tickPhysics(dt, mk(c)); P.tickProcess(dt, mk(C2)); }
  if (f % 6 === 0) {
    const g = J.frames[f / 6], u = P.uniforms(), S = P.state;
    if (!g || f < 12) continue; const T = g.t;          // (the first frames of the Godot run are the game warming up)
    arr('mA', u.mA, g.mA, T); arr('mB', u.mB, g.mB, T);
    for (const k of ['dmt', 'buzz', 'sharp', 'tube', 'smear', 'rewind', 'trip', 'amount', 'breathe', 'onset', 'mode', 'k_chroma', 'k_trace', 'k_punch', 'k_warp', 'k_pulse', 'k_wash', 'k_edge', 'k_cel', 'use_trail']) note('u.' + k, +u[k], g[k], T);
    note('glow', g.glow_base * u.glowIntensityMul, g.glow, T); note('bloom', g.bloom_base * u.glowBloomMul + u.glowBloomAdd, g.bloom, T); note('fog(x1000)', g.fog_base * u.fogDensityMul, g.fog, T);
    arr('mdose', S.mdose, g.mdose, T); arr('mbody', S.mbody, g.mbody, T); arr('mflash', S.mflash, g.mflash, T);
    note('dose', S.dose, g.dose, T); note('body', S.body, g.body, T); note('clr_k', S.clr_k, g.clr_k, T); note('clr_t', S.clr_t, g.clr_t, T); note('sharp_v', S.sharp_v, g.sharp_v, T); note('stage_post', S.stage_post, g.stage_post, T); note('hall', S.hall, g.hall, T); note('pill_k', S.pill_k, g.pill_k, T);
    note('chain', S.flow.chain, g.chain, T); note('groove', S.flow.groove, g.groove, T); note('chain_lvl', S.flow.chain_lvl, g.chain_lvl, T); note('chain_step', S.flow.chain_step, g.chain_step, T); note('chain_t', S.flow.chain_t, g.chain_t, T); note('flow_t', S.flow.flow_t, g.flow_t, T); note('mult_t', S.flow.mult_t, g.mult_t, T);
    note('score', S.flow.score, g.score, T); note('shake', S.cam.shake, g.shake, T); note('fov_punch', S.cam.fov_punch, g.fov_punch, T); note('flash', S.cam.flash, g.flash, T);
    arr('mo', [S.mo.asp, S.mo.cell, S.mo.ratio, S.mo.depth, S.mo.sat, S.mo.tri, S.mo.rad, S.mo.warp], g.mo, T); note('efc_k', S.efc_k, g.efc_k, T); note('god_k', S.god_k, g.god_k, T); note('sky_flash', S.sky_flash, g.sky_flash, T); note('exc', S.exc, g.exc, T);
    if (B.res) { note('perk.bm_pad', B.res.bm_pad, g.perk[0], T); note('perk.spd_k', B.res.spd_k, g.perk[1], T); note('perk.glint_k', B.res.glint_k, g.perk[2], T); note('perk.jump_chance', B.res.jump_chance, g.perk[3], T); }
    if (g.j) { note('j.phase', P.journey.phase, g.j.phase, T); note('j.wave', P.journey.wave, g.j.wave, T); note('j.onset_k', P.onsetK(), g.j.onset_k, T); note('j.t', P.journey.t, g.j.t, T); note('j.strength', P.journey.strength, g.j.strength, T); }
  }
}
const rows = Object.entries(err).map(([k, v]) => ({ k, max: v.max, t: v.t, js: v.js, gd: v.gd, first: v.first, fjs: v.fjs, fgd: v.fgd }));
rows.sort((a, b) => b.max - a.max);
console.log('compared', J.frames.length, 'samples over', (J.ctx.length / 60).toFixed(0), 's');
console.log('worst 18 (max abs error, at time, js value, godot value):');
for (const r of rows.slice(0, 18)) console.log(' ', r.k.padEnd(14), r.max.toExponential(2), 't=' + r.t, 'js=' + (+r.js).toFixed(4), 'gd=' + (+r.gd).toFixed(4));
const bad = rows.filter((r) => r.max > 0.002); bad.sort((a, b) => a.first - b.first); console.log('earliest divergences (first time over 0.002):'); for (const r of bad.slice(0, 12)) console.log(' ', r.k.padEnd(14), 'first t=' + r.first, 'js=' + (+r.fjs).toFixed(4), 'gd=' + (+r.fgd).toFixed(4)); console.log(bad.length ? 'KEYS OVER 0.002: ' + bad.map((r) => r.k).join(' ') : 'ALL KEYS WITHIN 0.002 (rounding)');

// the glow, bloom and haze are written back to the environment by the game, and the journey's own environment blend (journey_sky, about every 0.12 s) overwrites them in the same frame: count how often the sample is the model's value
{
  const P2 = createPsyFx({ seed: 7, sessionMin: 10, cfgTrip: 1, journey: true, intensity: .8, fx: { x_clear: 2 }, rand: (() => { const q2 = { clr: [...J.draws.clr], sharp: [...J.draws.sharp], efc: [...J.draws.efc], efcpeek: [...J.draws.efcpeek], god: [...J.draws.god], calm: J.draws.calm.map((x) => x[1]) }; return (lo, hi, tag) => { const q = q2[tag]; if (!q || !q.length) return lo; const v = q.shift(); return tag === 'efcpeek' ? (v ? .2 : .8) : v; }; })() });
  let n = 0, okG = 0, okF = 0, okB = 0;
  for (let f = 0; f < J.ctx.length; f++) {
    const t = f * dt, c = J.ctx[f];
    for (const et of Object.keys(plan)) if (Math.abs(t - +et) < dt * .5) P2.events.onMolecule(plan[et], NAMES[plan[et]]);
    if (Math.abs(t - 4) < dt * .5) P2.flowUp(1); if (Math.abs(t - 6) < dt * .5) P2.flowUp(2); if (Math.abs(t - 8) < dt * .5) P2.chainHit('mult'); if (Math.abs(t - 9) < dt * .5) P2.chainHit('boost');
    if (Math.abs(t - 15) < dt * .5) P2.cheer('TEST', 'white', 1.5); if (Math.abs(t - 20) < dt * .5) P2.camera.shake = .9; if (Math.abs(t - 75) < dt * .5) P2.sharpen(1);
    { const C2 = J.ctx2 ? J.ctx2[f] : c, mk = (r) => ({ speed: r[0], speedY: r[1], chain: r[2], boosting: !!r[3], links: r[4], alt: r[5], vy: r[6], inAir: !!r[7], hurtT: r[8], rail: !!r[9], tube: !!r[10], wave: r[11] }); P2.tickPhysics(dt, mk(c)); P2.tickProcess(dt, mk(C2)); }
    if (f % 6 === 0 && f >= 12) { const g = J.frames[f / 6], u = P2.uniforms(); if (!g) continue; n++; if (Math.abs(g.glow_base * u.glowIntensityMul - g.glow) < .003) okG++; if (Math.abs(g.fog_base * u.fogDensityMul - g.fog) < .003) okF++; if (Math.abs(g.bloom_base * u.glowBloomMul + u.glowBloomAdd - g.bloom) < .003) okB++; }
  }
  console.log('environment write-back: model matches the sampled value in glow ' + (100 * okG / n).toFixed(1) + '%, fog ' + (100 * okF / n).toFixed(1) + '%, bloom ' + (100 * okB / n).toFixed(1) + '% of samples (the rest are frames where the journey environment blend wrote the base back)');
}

// ---- part 2: the forced depths. The Godot run goes on from the timeline: for each of five felt levels it forces all six molecules to that level, waits 90 steps, then takes four states (normal, clarity drop, snap back + sharpening, sharp peak).
{
  const q2 = { clr: [...J.draws.clr], sharp: [...J.draws.sharp], efc: [...J.draws.efc], efcpeek: [...J.draws.efcpeek], god: [...J.draws.god], calm: J.draws.calm.map((x) => x[1]) };
  const P3 = createPsyFx({ seed: 7, sessionMin: 10, cfgTrip: 1, journey: true, intensity: .8, fx: { x_clear: 2 }, rand: (lo, hi, tag) => { const q = q2[tag]; if (!q || !q.length) return lo; const v = q.shift(); return tag === 'efcpeek' ? (v ? .2 : .8) : v; } });
  let f = 0; const ctxAt = (i, post) => { const c = (post && J.ctx2) ? J.ctx2[i] : J.ctx[i]; return { speed: c[0], speedY: c[1], chain: c[2], boosting: !!c[3], links: c[4], alt: c[5], vy: c[6], inAir: !!c[7], hurtT: c[8], rail: !!c[9], tube: !!c[10], wave: c[11] }; };
  for (; f < 18000; f++) {          // the timeline again (same events)
    const t = f * dt;
    for (const et of Object.keys(plan)) if (Math.abs(t - +et) < dt * .5) P3.events.onMolecule(plan[et], NAMES[plan[et]]);
    if (Math.abs(t - 4) < dt * .5) P3.flowUp(1); if (Math.abs(t - 6) < dt * .5) P3.flowUp(2); if (Math.abs(t - 8) < dt * .5) P3.chainHit('mult'); if (Math.abs(t - 9) < dt * .5) P3.chainHit('boost');
    if (Math.abs(t - 15) < dt * .5) P3.cheer('TEST', 'white', 1.5); if (Math.abs(t - 20) < dt * .5) P3.camera.shake = .9; if (Math.abs(t - 75) < dt * .5) P3.sharpen(1);
    P3.tickPhysics(dt, ctxAt(f)); P3.tickProcess(dt, ctxAt(f, true));
  }
  const step = (n) => { for (let i = 0; i < n; i++, f++) { P3.tickPhysics(dt, ctxAt(f)); P3.tickProcess(dt, ctxAt(f, true)); } };
  const cmp = (tag, g, u, S) => {
    const row = {}; const d = (k, a, b) => { row[k] = Math.abs(a - b); };
    u.mA.forEach((x, i) => d('mA' + i, x, g.mA[i])); u.mB.forEach((x, i) => d('mB' + i, x, g.mB[i])); d('dmt', u.dmt, g.dmt); d('buzz', u.buzz, g.buzz); d('sharp', u.sharp, g.sharp); d('trip', u.trip, g.trip || 0); d('clr_k', S.clr_k, g.clr_k); d('stage', S.stage_post, g.stage_post);
    const w = Math.max(...Object.values(row)); return { tag, w, worst: Object.entries(row).sort((a, b) => b[1] - a[1])[0] };
  };
  const out = [];
  J.shots.forEach((g) => {
    const S = P3.state;
    if (g.state === 'normal') { P3.forceBody(Array(6).fill(J.levels[g.lvl].lvl * 6)); S.clr_t = -1; S.clr_k = 1; S.sharp_v = 0; S.clr_next = 9999; S.sharp_next = 9999; step(90); }
    else if (g.state === 'drop') { S.clr_t = 1.0; step(4); }
    else if (g.state === 'snap') { S.clr_t = 2.4; P3.sharpen(1); step(2); }
    else { S.clr_t = -1; S.clr_k = 1; P3.sharpen(1); step(2); }
    out.push(cmp('L' + g.lvl + ' ' + g.state, g, P3.uniforms(), S));
  });
  console.log('forced depths (max abs error across mA, mB, dmt, buzz, sharp, trip, clr_k, stage_post; the environment glow is excluded, see above):');
  for (const r of out) console.log(' ', r.tag.padEnd(12), r.w.toExponential(2), r.worst[0]);
  console.log(out.every((r) => r.w < .003) ? 'FORCED DEPTHS: ALL WITHIN 0.003' : 'FORCED DEPTHS: SOME OVER 0.003');
}
