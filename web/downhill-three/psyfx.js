// PSYFX: the psychedelic trip model of the Godot game ("ALL DRESSED" and the psychedelic world), ported LITERALLY from godot/scripts so the three.js game feels the same.
// It is a pure state machine: no THREE, no DOM. Feed it time and events, read back the numbers that drive the picture pass, the bloom and the haze.
//
// WHAT IS PORTED (source line ranges in godot/scripts/RunRig.gd unless named):
//   FX_KNOBS defaults ........................ RunRig.gd 6135-6196 (the lab knobs; fx(k) returns the default unless overridden through opts.fx)
//   fx() / fx_level() ........................ 6203-6211
//   DhPacer (session curve, wear, target) ..... DhPacer.gd 1-67
//   DhJourney (waves, thresholds, onset_k, hint, trip_floor, stages) .... DhJourney.gd 1-303 (the rig-side effects of a wave, biome_apply / music_morph / journey_part / journey_sky, are reported through callbacks)
//   the dose model: _pill_eat, _mol_gift, _mol_hurt, _mol_avg, _mol_dmt, decay and wear ...... 9803-9830 (eat), 9205-9240 (gift), 9830-9860 (avg, dmt), 9870-9920 (hurt, tick)
//   _pill_tick (dose, body, wear, the picture-pass block, the flick, the pill flash, the apex swell, the journey hand-off) ....... 9890-10010
//   _buzz_tick (buzz wave, sharpening, tube, smear, rewind, lab knobs, glow, haze) ................ 9344-9400
//   _sharpen ................................ 9245-9256
//   _mflash_tick (a molecule's own flash) ....... 7013-7046
//   _pk (the six pieces) and _stage_tick (h, _lv, stage_post, sky flash) ....... 7048-7052, 7113-7160
//   _clarity_tick (a moment of clarity) ......... 6962-7000
//   _trip_tick / _trip_add (the trip meter) ...... 1495-1530
//   journey_post (what the pass is doing between and during waves) ............. 8519-8549
//   ThemeFX.set_look ........................ ThemeFX.gd 283-300
//   _exc_tick (excitement) ................... 8394-8404
//   _efc_tick / the God (face and sky timers) .... 6737-6790
//
// HOW gv.js CALLS IT (postM.uniforms in gv.js are named trip, mA, mB, dmt, buzz, sharp, k_warp, k_pulse, k_chroma, k_trace, k_punch, k_wash, amount, breathe):
//     import { createPsyFx } from './psyfx.js';
//     const PSY = createPsyFx({ seed: lvl.seed, sessionMin: 10, cfgTrip: 1 });      // journey:true = ALL DRESSED (molecules, waves, clarity); journey:false = the plain psychedelic world (the trip meter only)
//     // every frame, with the game's own numbers:
//     PSY.tick(dt, { speedY: -vzMetresPerSecond, chain: PH.chain, boosting: PH.boost_t > 0, links: 0, wave: 0.5, inAir: !PH.grounded, vy: PH.vy, alt: PH.y - groundHeight, hurtT: PH.hurt, rail: !!PH.rail, tube: toys.active() });
//     const U = PSY.uniforms();
//     postM.uniforms.trip.value = U.trip; postM.uniforms.mA.value.set(...U.mA); postM.uniforms.mB.value.set(...U.mB); postM.uniforms.dmt.value = U.dmt; postM.uniforms.buzz.value = U.buzz; postM.uniforms.sharp.value = U.sharp;
//     postM.uniforms.k_warp.value = U.k_warp; postM.uniforms.k_pulse.value = U.k_pulse; postM.uniforms.k_chroma.value = U.k_chroma; postM.uniforms.k_trace.value = U.k_trace; postM.uniforms.k_punch.value = U.k_punch; postM.uniforms.k_wash.value = U.k_wash;
//     postM.uniforms.amount.value = U.amount; postM.uniforms.breathe.value = U.breathe; (and onset, tube, smear, rewind, k_edge, k_cel, k_fold, k_rings, k_dmtr, use_trail, layerVisible when the shader has them)
//     // bloom and haze (multipliers on the base values of the scene): glowIntensity = base * U.glowIntensityMul; glowBloom = baseBloom * U.glowBloomMul + U.glowBloomAdd; fogDensity = base * U.fogDensityMul
//     // events:  PSY.pillEat('2cb') (collecting a molecule), PSY.molGift(), PSY.molHurt(i), PSY.tripAdd(a), PSY.sharpen(k), PSY.chainPayoff()
//     // callbacks (optional opts): onCheer(text), onToast(text), onApex(), onPhase(name), onStage(part, world), onBiome(world, k, difficulty), onMusic(kind, seq), onDmt()

export const MOL_ORDER = ['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'];
export const FX_DEFAULTS = { x_level: 0, x_pieces: 1, x_sharp: 0, x_clear: 1, x_wander: .6, g_sq: 1, g_shape: 1, g_col: 1, g_tri: 1, g_rad: 1, g_warp: 1, g_glow: 1, r_edge: 1, r_apron: 1, w_caves: 0, w_backdrop: 0, w_bend: 0, t_sway: 1, t_breathe: .6, t_moire: 0, m_moire: 1, m_breathe: .5, m_polar: 0, s_bands: 1, s_polar: .45, s_tunnel: .6, p_wash: 0, p_face: 0, p_face_auto: 1, p_god: 0, p_god_auto: 1, w_moguls: 0, w_echo: 0, w_carve: 0, p_rewind: 0, p_smear: 0, p_hueedge: 0, p_edge: 0, p_cel: 0, p_chroma: 1, p_trace: 1, p_punch: 1, p_glow: .35, p_bloom: .4, p_haze: .55, p_tube: 1, p_warp: 1, p_fold: 0, p_pulse: 1, p_rings: 0, p_dmtr: 0 };

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const moveToward = (a, b, d) => Math.abs(b - a) <= d ? b : a + Math.sign(b - a) * d;
const fposmod = (a, b) => ((a % b) + b) % b;
const mulberry = (seed) => { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };

// ---- DhPacer.gd
const PHASES = [
  { name: 'settle', a: 0, b: .07, from: 0, to: .12, hazard: .35 }, { name: 'come up', a: .07, b: .30, from: .12, to: .75, hazard: .75 }, { name: 'peak', a: .30, b: .52, from: .75, to: 1, hazard: 1.2 },
  { name: 'plateau', a: .52, b: .70, from: 1, to: .65, hazard: 1 }, { name: 'comedown', a: .70, b: 1, from: .65, to: 0, hazard: .45 },
];
const CALM_START_S = 20;
class Pacer {
  constructor(sessionS) { this.session_s = sessionS; this.t = 0; this.cycle = 0; }
  tick(d) { this.t += d; if (this.t >= this.session_s) { this.t = 0; this.cycle++; } }
  _phase(u) { for (const p of PHASES) if (u < p.b) return p; return PHASES[PHASES.length - 1]; }
  phaseName() { return this._phase(clamp(this.t / this.session_s, 0, 1)).name; }
  target() { const u = clamp(this.t / this.session_s, 0, 1), p = this._phase(u), k = clamp((u - p.a) / Math.max(p.b - p.a, .001), 0, 1), v = lerp(p.from, p.to, sstep(0, 1, k)); return clamp(v * (1 + .04 * Math.min(this.cycle, 5)), 0, 1); }
  spawnBias(avg) { return clamp(1 + 2.6 * (this.target() - avg), .15, 3); }
  hazardK() { if (this.t < CALM_START_S && this.cycle === 0) return 0; const u = clamp(this.t / this.session_s, 0, 1); return this._phase(u).hazard * (1 + .05 * Math.min(this.cycle, 6)); }
}

// ---- DhJourney.gd
const ARC = [
  { w: 'psychedelic', s: .36, calm: 40, on: 16, peak: 10, off: 10 }, { w: 'candy', s: .48, calm: 30, on: 18, peak: 22, off: 10 }, { w: 'tunnel', s: .60, calm: 26, on: 20, peak: 30, off: 10 }, { w: 'synthwave', s: .72, calm: 22, on: 18, peak: 38, off: 10 },
  { w: 'matrix', s: .84, calm: 18, on: 20, peak: 34, off: 12 }, { w: 'psychedelic', s: 1.0, calm: 16, on: 22, peak: 55, off: 16 }, { w: 'desert', s: .60, calm: 22, on: 18, peak: 30, off: 14 }, { w: 'egypt', s: .40, calm: 45, on: 24, peak: 40, off: 20 },
];
const LV_STR = [.5, 1, 1.3], LV_LEN = [.7, 1, 1.3], LV_CALM = [1.3, 1, .75], THR = [2.6, 3.8, 5, 6.2, 7.6, 9.6, 4.5, 1.5], LV_THR = [1.3, 1, .75];
export const BIOME = {
  alpine: { spd: 1, haz: 1, pads: 1, jumps: 1, glint: 1, bump: 1, spring: 1, padk: 1, grip: 1, mus: 'techno' }, psychedelic: { spd: 1, haz: .9, pads: 1, jumps: 1.2, glint: 1.7, bump: 1.2, spring: 1.1, padk: 1, grip: .9, mus: 'trance' },
  tunnel: { spd: 1.28, haz: .8, pads: 1.6, jumps: .9, glint: 1, bump: 1, spring: .9, padk: 1.5, grip: .8, mus: 'techno' }, desert: { spd: 1, haz: 1.5, pads: .8, jumps: 1.5, glint: .8, bump: .9, spring: 1.4, padk: 1, grip: 1.15, mus: 'jungle' },
  candy: { spd: .9, haz: .6, pads: 1, jumps: 1, glint: 1.6, bump: 1.9, spring: 1.5, padk: .9, grip: 1, mus: 'jungle' }, egypt: { spd: 1, haz: 1.3, pads: 1, jumps: 1, glint: .9, bump: .9, spring: 1, padk: 1, grip: 1.3, mus: 'ambient' },
  matrix: { spd: 1.15, haz: 1, pads: 1.3, jumps: .9, glint: 1, bump: 1, spring: 1, padk: 1.3, grip: .75, mus: 'industrial' }, synthwave: { spd: 1.1, haz: 1, pads: 1.2, jumps: 1.6, glint: 1.2, bump: 1.1, spring: 1.2, padk: 1.2, grip: 1, mus: 'trance' },
};
const STAGES = ['skymat', 'ground', 'veg', 'light'];
const WIN_ON = { sky: [0, .30], ground: [.30, .55], veg: [.55, .80], light: [.80, 1] }, WIN_OFF = { light: [0, .20], veg: [.20, .45], ground: [.45, .70], sky: [.70, 1] };
const SWAP_ON = { skymat: .55, ground: .5, veg: .78, light: .88 }, SWAP_OFF = { skymat: .30, ground: .45, veg: .58, light: .70 };
const POST_MODE = { psychedelic: 1, tunnel: 1, matrix: 2, synthwave: 3 };
export const postMode = (w) => POST_MODE[w] || 0;
const CALM = 0, ONSET = 1, PEAK = 2, OFFSET = 3, PH_NAMES = ['calm', 'onset', 'peak', 'offset'];

export function createPsyFx(opts = {}) {
  const O = Object.assign({ fx: {}, cfgTrip: 1, sessionMin: 10, seed: 7, journey: true, intensity: .8, theme: null, rand: null, dir: true }, opts);
  const rng = mulberry(O.seed * 7 + 31), rand = (lo, hi, tag) => O.rand ? O.rand(lo, hi, tag) : lo + (hi - lo) * rng();
  const FXV = Object.assign({}, FX_DEFAULTS, O.fx), fx = (k) => (FXV[k] !== undefined ? FXV[k] : 1);
  const cb = (n, ...a) => { if (typeof O[n] === 'function') O[n](...a); };
  const S = {
    // dose model
    mdose: [0, 0, 0, 0, 0, 0], mbody: [0, 0, 0, 0, 0, 0], mflash: [0, 0, 0, 0, 0, 0], mol_got: [false, false, false, false, false, false], mol_seen: false, mol_hurt_t: 0, mol_hurt_i: -1, dmt_on: false,
    dose: 0, body: 0, flick: 0, drift_t: 110, pill_k: 0, pill_n: 0, pill_gap: 0, pill_live: false, apex_t: 0, apex_amp: 0, apex_vy: 0, sky_flash: 0,
    // trip
    trip: 0, trip_tier: 0, trip_on: false, trip_force: -1, exc: 0,
    // picture-pass state (the shader's uniforms)
    post: { mode: 0, amount: 1, breathe: 1, onset: 1, light: false, layer: false, use_trail: 0 }, jpost_mode: 0, jpost_light: false, mflash_on: false,
    mA: [0, 0, 0], mB: [0, 0, 0], dmt: 0, buzz: 0, sharp: 0, tube: 0, smear: 0, rewind: 0, tube_k: 0, smear_k: 0, k: {},
    // clarity, sharpening, buzz
    clr_t: -1, clr_next: 75, clr_k: 1, buzz_t: 0, sharp_next: 30, sharp_v: 0,
    // stage
    lv: [0, 0, 0, 0, 0, 0], hall: 0, stage_post: 0, stg_acc: 0, age: 0,
    // face and God timers
    efc_t: -1, efc_next: 60, efc_k: 0, efc_lift: 0, efc_peek: false, god_t: -1, god_next: 150, god_k: 0,
    glowMul: 1, glowBloomMul: 1, glowBloomAdd: 0, fogMul: 1,
    // camera feel (RunRig/DownhillRig: _fov_punch decays 24/s, _shake 1.6/s, _flash 2/s)
    cam: { fov_punch: 0, shake: 0, flash: 0 },
    // flow (the multiplier you keep alive) and the four-step chain, score
    flow: { chain: 0, groove: 1, flow_t: 0, flow_window: 5, flow_bump: 0, drops: 0, best: 1, chain_lvl: 0, chain_step: 0, chain_t: 0, chain_flash: 0, mult_t: 0, score: 0, jumps: 0, rails: 0, pads: 0, picks: 0, glints: 0, orbs: 0, pops: 0, crashes: 0 },
    // the moire knobs and the wander (what the ground, trees and mountains do)
    mo: { ang: 0, asp: .045, cell: 6, ratio: 1.037, depth: .12, sat: 0, hue: 0, tri: 0, rad: 0, warp: 0, drift: [0, 0] }, wd_t: 0, wd_drift: [0, 0],
  };
  const pacer = O.journey ? new Pacer(clamp(O.sessionMin, 5, 600) * 60) : null;
  const molAvg = () => (S.mbody[0] + S.mbody[1] + S.mbody[2] + S.mbody[3] + S.mbody[4] + S.mbody[5]) / 36;
  const molDmt = () => { let mn = 6; for (let i = 0; i < 6; i++) mn = Math.min(mn, S.mbody[i]); return sstep(.52, .75, mn / 6); };
  const molCount = () => S.mol_got.filter(Boolean).length;
  const fxLevel = () => fx('x_level');

  // ---- ThemeFX.set_look(m, intensity)
  const setLook = (m, intensity) => { const P = S.post; P.mode0 = m; P.amount0 = clamp(intensity, 0, 1.5); P.mode = m; P.amount = P.amount0; P.breathe = P.amount0; P.layer = m > 0; P.use_trail = (m === 1 && !P.light) ? 1 : 0; };          // (mode0 / amount0 are ThemeFX's remembered look, pm.mode / pm.amount; mode / amount / breathe are what is on the shader right now)
  // ---- _pk(i): how far molecule i's piece of the world has come
  const pk = (i) => { if (fx('x_pieces') < .5) return sstep(.03, .30, S.hall); return clamp((sstep(.04, .45, S.lv[i]) + S.mflash[i] * .7) * S.clr_k, 0, 1.3); };

  // ---- the journey (DhJourney.gd), without the rig-side effects: they are callbacks
  const J = { on: O.journey, wave: 0, phase: CALM, t: 0, world: 'psychedelic', strength: .3, time_scale: 1, calm_len: 75, prewarm_t: 5, onset_len: 9, peak_len: 4, off_len: 6, shown: {}, sky_k: -1, env_next: 0, clock: 0, mods_t: 0, echo: false, flash: 0 };
  const lvl = () => clamp(O.cfgTrip, 0, 2);
  const lenK = () => (pacer ? clamp(pacer.session_s / 1200, .5, 1.5) : 1);
  const thr = (w) => THR[w % THR.length] * LV_THR[lvl()] * (1 + .08 * Math.floor(w / THR.length));
  const jcalm = (w) => ARC[w % ARC.length].calm * LV_CALM[lvl()] * rand(.9, 1.15, 'calm') * lenK();
  function planWave(w = -1) { if (w < 0) w = J.wave; const a = ARC[w % ARC.length], lv = lvl(), rk = 1 + .08 * Math.floor(J.wave / ARC.length); J.strength = clamp(a.s * LV_STR[lv] * rk, .15, lv < 2 ? LV_STR[lv] * 1 : 1.3); J.onset_len = a.on; J.peak_len = a.peak * LV_LEN[lv] * lenK(); J.off_len = a.off; }
  const hint = () => (J.phase !== CALM ? 0 : clamp(S.body / Math.max(thr(J.wave), .1), 0, 1) * .15);
  const onsetK = () => {
    if (J.phase === ONSET) { const p = clamp(J.t / J.onset_len, 0, 1); return clamp(Math.max(p + (1 - p) * .18 * Math.sin(p * 5 * Math.PI), .15), 0, 1); }
    if (J.phase === PEAK) return 1;
    if (J.phase === OFFSET) { const q = clamp(J.t / J.off_len, 0, 1); return clamp((1 - q) + q * (1 - q) * .15 * Math.sin(q * 3 * Math.PI), 0, 1); }
    return hint();
  };
  const wantsTrip = () => J.strength >= .45 || postMode(J.world) === 1;
  const tripFloor = () => (J.phase === CALM || !wantsTrip() ? 0 : Math.pow(onsetK(), 1.5) * (.2 + .45 * clamp((J.strength - .3) / .9, 0, 1)) * (.7 + .3 * S.exc));
  const jfrac = (stage) => {
    if (J.phase === ONSET) { const w = WIN_ON[stage], fo = clamp((J.t / J.onset_len - w[0]) / (w[1] - w[0]), 0, 1); return stage === 'sky' ? Math.max(fo, hint()) : fo; }
    if (J.phase === PEAK) return 1;
    if (J.phase === OFFSET) { const w2 = WIN_OFF[stage]; return 1 - clamp((J.t / J.off_len - w2[0]) / (w2[1] - w2[0]), 0, 1); }
    return 0;
  };
  function setPhase(p) {
    J.phase = p; J.t = 0; cb('onPhase', PH_NAMES[p], J.world);
    if (p === ONSET) cb('onMusic', BIOME[J.world].mus, J.wave * 3 + 1);
    else if (p === OFFSET) cb('onMusic', BIOME.alpine.mus, J.wave * 3 + 2);
    else if (p === CALM) {
      if (!J.echo) { J.wave++; if (J.wave % ARC.length < 5 && S.body >= thr(J.wave + 1) * 1.15) J.wave++; }
      J.echo = false; J.world = ARC[J.wave % ARC.length].w; J.calm_len = jcalm(J.wave); J.prewarm_t = 6; planWave(); journeyReset(); J.sky_k = -1; for (const s of STAGES) J.shown[s] = false;
    }
  }
  function journeyReset() { for (const part of ['sky', 'skymat', 'ground', 'veg', 'light']) cb('onStage', part, 'alpine'); journeyPost('alpine', 0, false, .3); cb('onBiome', 'alpine', 1, 1); }
  function jstages() {
    const e = onsetK(); let ke = clamp(e * 1.45, 0, 1); if (ke > .001 && ke < .999) ke *= .8 + .2 * Math.sin(J.clock * 1.7);
    if (Math.abs(ke - J.sky_k) > .004 && J.clock >= J.env_next) { J.env_next = J.clock + .12; J.sky_k = ke; cb('onSky', J.world, ke); }
    for (const s of STAGES) { let on = !!J.shown[s]; if (!on && e >= SWAP_ON[s]) on = true; else if (on && e < SWAP_OFF[s]) on = false; if (on !== !!J.shown[s]) { J.shown[s] = on; cb('onStage', s, on ? J.world : 'alpine'); J.flash = 1; } }
  }
  const difficulty = () => 1 + .05 * Math.min(J.wave, 20) + .01 * Math.max(J.wave - 20, 0);
  function jtick(delta) {
    const d = delta * J.time_scale; J.t += d; J.clock += d;
    if (J.phase === CALM && J.prewarm_t > 0) { J.prewarm_t -= delta; if (J.prewarm_t <= 0) cb('onPrewarm', J.world); }
    J.flash = Math.max(J.flash - delta * .9, 0);
    if (J.phase === CALM) {
      if (J.t >= J.calm_len && S.body >= thr(J.wave)) setPhase(ONSET);
      else if (J.wave > 0 && J.t >= J.calm_len * 2 + 25 && S.body >= thr(J.wave - 1) * .6) { J.echo = true; J.world = ARC[(J.wave - 1) % ARC.length].w; planWave(J.wave - 1); J.strength *= .85; setPhase(ONSET); }
    } else if (J.phase === ONSET) { if (J.t >= J.onset_len) setPhase(PEAK); }
    else if (J.phase === PEAK) { if (J.t >= J.peak_len && (S.body < thr(J.wave) * 1.3 || J.t >= J.peak_len * 1.6)) setPhase(OFFSET); }
    else if (J.phase === OFFSET) { if (J.t >= J.off_len) setPhase(CALM); }
    jstages();
    if (J.phase !== CALM || hint() > .001) journeyPost(J.world, onsetK(), wantsTrip(), J.strength * .85);
    J.mods_t -= d; if (J.mods_t <= 0) { J.mods_t = .4; const k = onsetK() * clamp(J.strength / .6, .45, 1); cb('onBiome', J.world, k, difficulty()); }
  }

  // ---- journey_post(world, onset, want_trip, strength)  (RunRig.gd 8519)
  function journeyPost(world, onset, wantTrip, strength) {
    const mav = molAvg();
    if (mav > .01) { onset = Math.max(onset, clamp(mav * 1.3, 0, 1) * S.stage_post); wantTrip = true; strength = Math.max(strength, .5 + .7 * mav); }
    const light = onset < .3;
    if (S.pill_k > .001) { onset = Math.max(onset, S.pill_k); wantTrip = true; strength = Math.max(strength, .9); }
    let m = 0;
    if (onset > .001) { if (wantTrip && (onset < .999 || postMode(world) < 2)) m = 1; else if (onset >= .999) m = postMode(world); }
    if (m !== S.jpost_mode || (m === 1 && light !== S.jpost_light)) { S.jpost_mode = m; S.jpost_light = light; S.post.light = light; setLook(m, clamp(strength, .3, 1.2)); }
    S.trip_on = S.jpost_mode === 1;
    if (S.jpost_mode === 0) { S.trip = 0; S.trip_tier = 0; }
    S.post.onset = S.jpost_mode === 1 ? clamp(onset, 0, 1) : 1;
  }

  // ---- camera feel: every trigger and its amount (RunRig.gd line numbers in brackets)
  const C = S.cam, F = S.flow;
  const mx = (k, v) => { C[k] = Math.max(C[k], v); };
  function kick(name, a = 1) {
    switch (name) {
      case 'cheer': mx('flash', .25 * a); mx('fov_punch', 6 * a); break;                                   // _cheer (3959): size a
      case 'buff': C.flash = .25; break;                                                                   // _take_buff (4754)
      case 'buff_boost': C.fov_punch = 9; mx('shake', .45); break;                                         // _buff_pop (4570)
      case 'buff_shield': mx('shake', .25); break;                                                         // (4578)
      case 'buff_donut': case 'buff_mult': mx('shake', .2); break;                                         // (4584, 4590)
      case 'blast': C.fov_punch = 12; C.shake = 1.4; mx('flash', .35); break;                              // _update_ramps (8044)
      case 'pop_charged': C.fov_punch = 4 + 5 * a; break;                                                  // (8073): a = charge 0..1
      case 'pad': C.fov_punch = 7; mx('shake', .25); break;                                                // _update_pads (8178)
      case 'pop': mx('fov_punch', 2.5); break;                                                             // _pop_tick (4351)
      case 'rail_off': mx('fov_punch', 3); break;                                                          // _rail_off (1889)
      case 'sling': mx('fov_punch', 4 + 6 * a); break;                                                     // (1876): a = sling 0..1
      case 'molecule': mx('shake', .12); break;                                                            // _pill_eat (9819)
      case 'apex': mx('fov_punch', 5); break;                                                              // _pill_tick apex (9961)
      case 'tree_hit': mx('shake', .5); break;                                                             // _hit_fx (5638)
      case 'rock_hit': mx('shake', .6); break;                                                             // (5649)
      case 'shield_break': C.flash = .35; C.shake = .5; break;                                             // _crash shield (5689)
      case 'crash': C.shake = .9; break;                                                                   // _crash (5720)
      case 'finish': C.flash = .6; break;                                                                  // _finish (5941)
      case 'ball_braced': case 'ball_shield': mx('shake', .5); C.flash = .3; break;                        // _ball_hit (7813, 7818)
      case 'ball_hit': C.shake = .9; C.flash = .5; break;                                                  // (7827)
      case 'sb_close': mx('shake', .35 * a * a); break;                                                    // _sb_tick (1425): a = closeness
      case 'tube_open': mx('fov_punch', 8); break;                                                         // _lk_open (9013)
      case 'tube_start': mx('fov_punch', 11); mx('shake', .35); break;                                     // _lk_start (9120)
      case 'tube_step': mx('fov_punch', 7); break;                                                         // _lk_step (9140)
      case 'payoff': mx('flash', .35); break;                                                              // _lk_payoff (9413)
      default: break;
    }
  }
  // fov of the chase camera (RunRig.gd 10442): the speed in m/s; first person adds 0.6 of the punch
  const cameraFov = (sp, firstPerson) => (firstPerson ? clamp(62 + (sp - 18) * .3, 60, 74) + C.fov_punch * .6 : clamp(80 + (sp - 18) * .6, 78, 108) + C.fov_punch);
  // the view shake (RunRig.gd 10439-10440): the camera's h and v offset, in the camera's own units
  const shakeOffset = (r1, r2) => [(r1 * 2 - 1) * C.shake * .3, (r2 * 2 - 1) * C.shake * .3];
  function cheer(text, col, size = 1) { kick('cheer', size); tripAdd(.04 * size); cb('onCheer', text, col, size); }

  // ---- flow (4257-4300) and the four-step chain (4189-4215, 4360-4372), the score (4442)
  const FLOW_WINDOW = 5, FLOW_WINDOW_MIN = 2.6, FLOW_DRAIN_STEP = .7, FLOW_MAX = 8, CHAIN_ORDER = ['mult', 'boost', 'ramp', 'air'], CHAIN_WINDOW = 9, BOOST_S = 3, MULT_S = 10;
  const chainK = () => 1 + .25 * F.chain_lvl;
  const gain = (pts) => { const g = Math.trunc(pts * (F.mult_t > 0 ? 2 : 1) * chainK() * (1 + .8 * S.mbody[1] / 6) * (1 + 2 * molDmt())); F.score += g; return g; };          // DOM: more for everything; all six: much more
  function flowTouch() { F.flow_window = lerp(FLOW_WINDOW, FLOW_WINDOW_MIN, clamp(F.chain / FLOW_MAX, 0, 1)); F.flow_t = F.flow_window; }
  function flowUp(levels = 1) {
    const was = F.chain; F.chain = Math.min(F.chain + levels, 24);
    if (Math.floor(F.chain / 3) > Math.floor(was / 3) && F.chain >= 3) cheer('COMBO x' + F.chain + '!', 'gold', 1 + .1 * Math.min(Math.floor(F.chain / 3), 5));
    F.groove = 1 + .25 * Math.min(F.chain, FLOW_MAX); F.best = Math.max(F.best, F.groove); F.flow_bump = 1; flowTouch();
  }
  function flowTick(delta) {
    F.flow_bump = Math.max(F.flow_bump - 3 * delta, 0); if (F.chain <= 0) return;
    F.flow_t -= delta; if (F.flow_t <= 0) { F.chain = Math.max(Math.min(F.chain, FLOW_MAX) - 1, 0); F.groove = 1 + .25 * F.chain; F.drops++; F.flow_t = FLOW_DRAIN_STEP; F.flow_window = Math.max(F.flow_window, FLOW_DRAIN_STEP); }
  }
  const chainExpect = () => CHAIN_ORDER[F.chain_step];
  function chainHit(kind) {
    if (kind === chainExpect()) { F.chain_lvl = Math.min(F.chain_lvl + 1, 4); F.chain_step = (F.chain_step + 1) % CHAIN_ORDER.length; F.chain_t = CHAIN_WINDOW; F.chain_flash = 1; }
    else if ((kind === 'shield' || kind === 'donut') && F.chain_lvl > 0) F.chain_t = Math.min(F.chain_t + 3, CHAIN_WINDOW + 3);
  }
  function chainTick(delta) { flowTick(delta); F.chain_flash = Math.max(F.chain_flash - 2 * delta, 0); if (F.chain_lvl > 0) { F.chain_t -= delta; if (F.chain_t <= 0) { F.chain_lvl = 0; F.chain_step = 0; } } }
  // what flow does for pace: in a race, flow IS speed (RunRig.gd 5522: cap += 0.5 * min(chain, FLOW_MAX)); in score mode it multiplies points (groove)
  const flowSpeedBonus = (race) => (race ? .5 * Math.min(F.chain, FLOW_MAX) : 0);

  // ---- THE PERKS (biome_apply, 8430-8436, and _gain): what each molecule's felt level does, as multipliers the physics can read
  const felt = (i) => S.mbody[i] / 6;
  const perks = () => ({ glintK: 1 + .6 * felt(0), pointsK: (1 + .8 * felt(1)) * (1 + 2 * molDmt()), padK: 1 + .5 * felt(2), jumpChanceK: 1 + .35 * felt(3), springK: 1 + .6 * felt(4), speedK: 1 + .12 * felt(5), felt: [0, 1, 2, 3, 4, 5].map(felt), names: ['GLINTS', 'POINTS', 'BOOST', 'RAMPS', 'SLING', 'SPEED'] });
  // the whole biome_apply (8423-8447): what a world does to the ride, with the perks on top. base = the run's starting values
  function biomeApply(m, k, diff, ctx = {}, base = {}) {
    const b = Object.assign({ haz: .6, jump: .72, pad: .12, glint: 1, grip: 1 }, base), P = perks(); const o = {};
    o.spd_k = clamp(lerp(1, m.spd, k) * (1 + .4 * (diff - 1)), .8, 1.7); o.hazard_share = clamp(b.haz * lerp(1, m.haz, k) * (1 + .6 * (diff - 1)), 0, 1);
    o.jump_chance = clamp(b.jump * lerp(1, m.jumps, k), 0, 1); o.pad_chance = clamp(b.pad * lerp(1, m.pads, k), 0, 1); o.glint_k = clamp(b.glint * lerp(1, m.glint, k), .5, 4); o.grip_lag = b.grip * lerp(1, m.grip, k);
    o.bm_bump = lerp(1, m.bump, k); o.bm_spring = lerp(1, m.spring, k); o.bm_pad = lerp(1, m.padk, k);
    o.glint_k = clamp(o.glint_k * P.glintK, .5, 5); o.bm_pad *= P.padK; o.jump_chance = clamp(o.jump_chance * P.jumpChanceK, 0, 1); o.bm_spring *= P.springK; o.spd_k = clamp(o.spd_k * P.speedK, .8, 1.9);
    if (pacer) o.hazard_share = clamp(o.hazard_share * pacer.hazardK(), 0, 1);
    if (O.dir) { const pace = .7 + .6 * (ctx.waveAhead !== undefined ? ctx.waveAhead : .5); o.hazard_share = clamp(o.hazard_share * pace, 0, 1); o.jump_chance = clamp(o.jump_chance * (1.6 - .6 * pace), 0, 1); o.pad_chance = clamp(o.pad_chance * (1.6 - .6 * pace), 0, 1); }
    return o;
  }

  // ---- THE MOIRE KNOBS (_moire_tick 7068) and THE WANDER (_wander_tick 6504): the ground's, the trees' and the mountains' numbers
  function moireTick(delta, h, ctx) {
    const M = S.mo, spd = clamp((ctx.speed || 0) / 50, 0, 1), alt = clamp((ctx.alt || 0) / 30, 0, 1), tube = ctx.tube ? 1 : 0, k = 1 - Math.exp(-3 * delta), sh = S.sharp_v;
    M.asp = lerp(M.asp, .045 + .20 * spd + .5 * sh + .25 * tube, k); M.cell = lerp(M.cell, 6 * (1 + 1.2 * alt) * (1 - .4 * tube) * (1 - .3 * sh), k);
    M.ratio = lerp(M.ratio, 1.037 + .02 * Math.sin(S.buzz_t * .4) * pk(0) + .03 * pk(0), k); M.depth = lerp(M.depth, (.12 + .30 * pk(0) + .25 * sh) * fx('g_shape'), k);
    M.sat = lerp(M.sat, clamp((pk(2) * .9 + .5 * sh * pk(2) + .4 * tube * pk(2)) * fx('g_col'), 0, 1), k); M.tri = lerp(M.tri, (pk(4) * .9 + .5 * sh * pk(4)) * fx('g_tri'), k);
    M.rad = lerp(M.rad, clamp((.9 * sh + .7 * tube + (ctx.rail ? .5 : 0)) * fx('g_rad'), 0, 1), k); M.warp = lerp(M.warp, (.5 + .5 * Math.sin(S.buzz_t * .55)) * pk(4) * fx('g_warp'), k);
    M.ang += M.asp * delta * .3; M.drift[0] += Math.cos(M.ang) * (.10 + .9 * M.asp) * delta; M.drift[1] += Math.sin(M.ang) * (.10 + .9 * M.asp) * delta; M.hue = fposmod(M.hue + delta * (.03 + .1 * spd), 1);
  }
  const wdW = (period, phase, gate, h) => sstep(.35, .75, .5 + .5 * Math.sin(S.wd_t * Math.PI * 2 / period + phase)) * sstep(gate, gate + .12, h) * clamp(fx('x_wander'), 0, 2) * .5;
  function wanderTick(delta, h) { S.wd_t += delta; S.wd_drift[0] += Math.cos(S.wd_t * .05) * .6 * delta; S.wd_drift[1] += Math.sin(S.wd_t * .037) * .6 * delta; }
  // what each molecule brings into the world, 0..1 per piece (feed these to the shaders)
  function world(ctx = {}) {
    const h = S.hall, g3 = pk(3), M = S.mo, breath = .85 + .15 * Math.sin(S.age * .9);
    return {
      pieces: [0, 1, 2, 3, 4, 5].map(pk), names: ['ground', 'sky', 'colour', 'mountains', 'ripples', 'pulse'],
      groundGlow: pk(0) * fx('g_glow'), groundGrid: sstep(.08, .34, h), moire: { cell: M.cell, ang: M.ang, ratio: M.ratio, depth: M.depth, sat: M.sat, hue: M.hue, tri: M.tri, drift: M.drift.slice(), rad: M.rad, warp: M.warp },
      skyK: clamp(Math.max(S.sky_flash * S.sky_flash * .9, .30 * pk(1) * breath), 0, 1), skyPolar: fx('s_polar') * pk(1), skyTunnel: fx('s_tunnel') * pk(5),
      vegWob: pk(5) * (1 + .5 * pk(5)) * fx('t_sway'), vegBreathe: pk(5) * fx('t_breathe'),
      treeMoire: clamp(Math.max(fx('t_moire'), wdW(70, 0, .2, h) * 2) * pk(2), 0, 2), wanderDrift: S.wd_drift.slice(),
      mtnMoire: clamp(Math.max(fx('m_moire') * g3, wdW(110, 2.1, .35, h) * 2 * g3), 0, 2), mtnBreathe: clamp(Math.max(fx('m_breathe') * g3, wdW(90, 4, .3, h) * 3 * g3), 0, 3), mtnPolar: clamp(Math.max(fx('m_polar'), wdW(130, 1, .4, h) * 2 * g3), 0, 2),
      faceK: S.efc_k, godK: S.god_k, faceLift: S.efc_lift, stagePost: S.stage_post, hall: h, apex: S.apex_t > 0 ? Math.sin(Math.PI * (1 - S.apex_t / 1.9)) : 0,
    };
  }

  // ---- THE EVENTS INTERFACE: what the game reports, each doing what the Godot code does at that moment. Each returns what the physics should do about it (the numbers are the source's, in m/s of the Godot game: scale them with your speed factor).
  const ev = {
    onMolecule(id, name) { const r = pillEat(id, name); kick('molecule'); gain(120 * S.pill_n * (r && r.first ? 3 : 1)); tripAdd(0); flowUp(1); return r; },   // _pill_eat (9803): the score, the flow level, the shake; the dose model is in pillEat
    onChain(dp = 1) { sharpen(1); const gift = molGift(); gain(Math.trunc(500 * F.groove * dp)); F.mult_t = Math.max(F.mult_t, 8 + 3 * dp); tripAdd(.08 + .03 * dp); kick('payoff'); cheer('CHAIN' + (dp === 1 ? '!' : ' x' + dp + '!') + gift, 'magenta', 2 + .4 * dp); return { gift, boostT: 3 + .5 * dp, vxActiveT: 2.4 }; },   // _lk_payoff (9400)
    onPad(epic) { F.pads++; kick('pad'); return { boostT: 1.8, kickMps: 7 * perks().padK, vxActiveT: 1.4, capOver: 6 }; },          // _update_pads (8147): vel += fwd * 7 * _bm_pad; boost 1.8 s; the cap may be passed by 6 m/s
    onBlast({ crossedMid = true, superRamp = false, charge = 0 } = {}) {          // _update_ramps (8015): the lip of a ramp
      if (crossedMid) { F.jumps++; flowUp(); }
      kick('blast'); cheer('BLAST!', 'magenta', 1.6); if (superRamp) cheer('SUPER AIR!', 'yellow', 2.2);
      const extraVy = 2 + (superRamp ? 5 : 0) + 1.5 * F.chain_lvl + (charge > .15 ? 3 * charge : 0); chainHit('ramp'); if (charge > .15) kick('pop_charged', charge);
      return { vyAdd: extraVy, boostT: superRamp ? 2.4 : 1.2, vxBlast: 1 };
    },
    onRail(m, how = 'end', glRun = 0, isChain = false, depth = 1) {          // _rail_off (1849)
      if (m < 6) return { sling: 0 }; F.rails++; gain(Math.trunc(m * 7 * F.groove) + (how === 'pop' ? 80 : 0)); flowUp(m > 18 ? 2 : 1);
      const sling = clamp(m / 36 + .04 * glRun, 0, 1); let boostT = 0, vyAdd = 0;
      if (sling > .2 && how !== 'drop') { vyAdd = 3 + 13 * sling; boostT = .7 + 1.8 * sling; kick('sling', sling); tripAdd(.05 * sling); if (sling > .5) cheer('SLINGSHOT!', 'cyan', .8 + sling); }
      if (glRun >= 6) { boostT = Math.max(boostT, 1.2 + .08 * glRun); cheer('GLINT RUSH! x' + glRun, 'gold', 1.4); }
      if (isChain && how === 'end') ev.onChain(depth); kick('rail_off'); return { sling, boostT, vyAdd, vxActiveT: sling > .2 ? .7 : 0 };
    },
    onBuff(t) {          // _take_buff (4735)
      F.picks++; flowUp(); gain(60); kick('buff'); tripAdd({ donut: .30, mult: .22, boost: .08, shield: .08 }[t] !== undefined ? { donut: .30, mult: .22, boost: .08, shield: .08 }[t] : .05); const r = {};
      if (t === 'boost') { r.boostT = BOOST_S + .8 * F.chain_lvl; r.kickMps = 6 + 1.5 * F.chain_lvl; kick('buff_boost'); }
      else if (t === 'shield') { r.shield = 1; kick('buff_shield'); } else if (t === 'mult') { F.mult_t = MULT_S + 2 * F.chain_lvl; r.multT = F.mult_t; kick('buff_mult'); } else { gain(160); kick('buff_donut'); }
      chainHit(t); return r;
    },
    onCrash(kind = 'tree', { shield = false, mol = -1 } = {}) {          // _crash (5682) and _hit_fx
      if (shield) { kick('shield_break'); return { absorbed: true }; }
      molHurt(mol); F.crashes++; F.chain = 0; F.groove = 1; kick(kind === 'rock' ? 'rock_hit' : 'tree_hit'); kick('crash'); return { absorbed: false, speedK: .3 };
    },
    onPop() { gain(15); flowTouch(); kick('pop'); F.pops++; },          // _pop_tick (4340)
    onGlint() { tripAdd(.012); F.glints++; flowTouch(); },          // _glint_got (3973)
    onOrb(big, streak) { gain(Math.trunc((big ? 130 : 60) * F.groove * Math.min(streak, 8))); tripAdd(.015); F.orbs++; },          // (11036)
    onFinish() { kick('finish'); },
    onCheer(text, size = 1) { cheer(text, 'white', size); },
    onSnowball(kind, closeness) { if (kind === 'close') kick('sb_close', closeness); else if (kind === 'braced') { kick('ball_braced'); gain(80); } else if (kind === 'shield') kick('ball_shield'); else if (kind === 'hit') { kick('ball_hit'); F.chain = 0; F.groove = 1; } else if (kind === 'escaped') { gain(Math.trunc(500 * F.groove)); flowUp(); tripAdd(.1); cheer('ESCAPED THE SNOWBALL!', 'ice', 1.5); } },
  };

  // ---- events (the dose model)
  function sharpen(k = 1) { S.sharp_v = Math.max(S.sharp_v, k); S.sharp_next = Math.max(S.sharp_next, 14); }
  function tripAdd(a) { if (!S.trip_on) return; S.trip = clamp(S.trip + a, 0, 1); }
  function pillEat(id, name) {
    const mi = typeof id === 'number' ? id : MOL_ORDER.indexOf(id); if (mi < 0) return; S.pill_n = S.pill_gap > 0 ? S.pill_n + 1 : 1; S.pill_gap = 6;
    const first = !S.mol_got[mi], old = S.mdose[mi];
    if (first) { S.mol_got[mi] = true; S.mdose[mi] = 6; } else S.mdose[mi] = Math.min(S.mdose[mi] + 2, 6);
    S.mflash[mi] = 1; sharpen(.7); S.dose += .30 * (S.mdose[mi] - old); S.mol_seen = true; S.flick = 1; tripAdd(.25);
    if (first) { const nf = molCount(); cheer((name || MOL_ORDER[mi]).toUpperCase() + ' FOUND  ' + nf + ' OF 6', mi, nf < 5 ? 1.6 : 2); if (nf === 5) cb('onToast', 'ONE MORE!'); } else cb('onToast', (name || MOL_ORDER[mi]) + '  topped up');
    if (S.pill_n === 3) cheer('TRIPPING', -1, 1.2);
    return { first, mi };
  }
  function molGift() {
    let pick = -1; for (let q = 0; q < 6; q++) if (!S.mol_got[q]) { pick = q; break; }
    if (pick >= 0) { S.mol_got[pick] = true; S.mdose[pick] = 6; S.dose += .30 * 6; S.flick = 1; S.mol_seen = true; return '  FOUND ' + MOL_ORDER[pick].toUpperCase(); }
    let lo = 0; for (let m2 = 0; m2 < 6; m2++) if (S.mdose[m2] < S.mdose[lo]) lo = m2;
    if (S.mdose[lo] < 6) { S.mdose[lo] = Math.min(S.mdose[lo] + 2, 6); S.dose += .30 * 2; S.flick = 1; return '  +' + MOL_ORDER[lo].toUpperCase(); }
    return '';
  }
  function molHurt(mol) {
    let i = mol; if (i < 0) { const held = []; for (let k = 0; k < 6; k++) if (S.mdose[k] >= .5) held.push(k); if (!held.length) return; i = held[Math.floor(rand(0, held.length, 'hurt'))]; }
    if (S.mbody[i] < .5) return; S.mbody[i] = Math.max(S.mbody[i] - 2, 0); S.mol_hurt_t = 1; S.mol_hurt_i = i; cb('onToast', MOL_ORDER[i] + '  dimmed');
  }

  // ---- _clarity_tick(delta)  (6969)
  function clarityTick(delta) {
    const deep = Math.max(molAvg(), fxLevel()), f = fx('x_clear');
    if (S.clr_t < 0) { S.clr_k = 1; if (deep > .45 && f > .01) { S.clr_next -= delta * f; if (S.clr_next <= 0) { S.clr_t = 0; S.clr_next = rand(50, 110, 'clr'); } } return; }
    const before = S.clr_t; S.clr_t += delta; const t = S.clr_t;
    if (t < .35) S.clr_k = lerp(1, .10, t / .35);
    else if (t < 1.7) S.clr_k = .10;
    else if (t < 2.4) { S.clr_k = lerp(.10, 1.30, (t - 1.7) / .7); if (before < 1.7) sharpen(1); }
    else S.clr_k = lerp(1.30, 1, sstep(2.4, 5, t));
    if (t > 5) { S.clr_t = -1; S.clr_k = 1; }
  }
  // ---- _stage_tick(delta)  (7113)  (journey only: without a journey it returns at once and stage_post stays 0)
  function stageTick(delta) {
    if (!J.on) return;
    const h = Math.max(molAvg(), fxLevel()); S.hall = h; for (let li = 0; li < 6; li++) S.lv[li] = Math.max(S.mbody[li] / 6, fxLevel());
    S.sky_flash = Math.max(S.sky_flash - delta / 1.3, 0);
    S.stg_acc += delta; { const sd = S.stg_acc; S.stg_acc = 0; moireTick(sd, h, S._ctx || {}); clarityTick(sd); wanderTick(sd, h); }          // (in the game this block runs every frame, or every other one on a slow phone with the time it missed added in)
    S.stage_post = sstep(.22, .5, h);
  }
  // ---- _mflash_tick(delta)  (7016)
  function mflashTick(delta) {
    let mx = 0; for (let i = 0; i < 6; i++) { S.mflash[i] = Math.max(S.mflash[i] - delta * .9, 0); mx = Math.max(mx, S.mflash[i]); }
    const P = S.post;
    if (mx > .02) { S.mflash_on = true; P.layer = true; P.mode = 1; P.onset = 1; const a = Math.max(P.amount0, 1); P.amount = a; P.breathe = a; }
    else if (S.mflash_on) { S.mflash_on = false; P.mode = P.mode0; P.amount = P.amount0; P.breathe = P.amount0; P.layer = P.mode0 > 0; }
  }
  // ---- _buzz_tick(delta)  (9344)
  function buzzTick(delta, ctx) {
    S.buzz_t += delta; const deep = clamp(Math.max(molAvg(), fxLevel()) / 3, 0, 1);
    const wave = .5 + .5 * Math.sin(S.buzz_t * .55) * (.6 + .4 * Math.sin(S.buzz_t * .17 + 1)), buzz = wave * (.35 + .65 * deep);
    S.sharp_next -= delta * (.7 + .8 * deep); if (S.sharp_next <= 0) { sharpen(1); S.sharp_next = rand(26, 48, 'sharp'); }
    S.sharp_v = Math.max(S.sharp_v - delta * .42, 0); S.sharp = S.sharp_v; S.buzz = buzz;
    const tubeTo = ctx.tube ? 1 : (ctx.rail && ctx.railChain ? .5 : 0); S.tube_k = lerp(S.tube_k, tubeTo, 1 - Math.exp(-(tubeTo > S.tube_k ? 7 : 2) * delta)); S.tube = S.tube_k * fx('p_tube');
    S.k.chroma = fx('p_chroma');
    S.smear_k = lerp(S.smear_k, ctx.boosting ? 1 : 0, 1 - Math.exp(-(ctx.boosting ? 9 : 3) * delta)); S.smear = S.smear_k * fx('p_smear') * .6;
    S.rewind = O.journey ? clamp((ctx.hurtT || 0) / 1.1, 0, 1) * fx('p_rewind') : 0;
    const hueOn = O.journey && fx('p_hueedge') > .01; S.k.edge = Math.max(fx('p_edge'), hueOn ? .45 * fx('p_hueedge') : 0); S.k.edge_hue = hueOn ? 1 : 0; S.k.cel = fx('p_cel'); S.k.wash = fx('p_wash');
    mflashTick(delta); efcTick(delta);
    S.k.trace = fx('p_trace'); S.k.punch = fx('p_punch'); S.k.warp = fx('p_warp'); S.k.fold = fx('p_fold'); S.k.pulse = fx('p_pulse'); S.k.rings = fx('p_rings'); S.k.dmtr = fx('p_dmtr');
    // the environment: glow and haze, as multipliers on whatever base the scene has
    S.glowMul = fx('p_glow') * (1 + (.3 * buzz + 1 * S.sharp_v) * fx('p_bloom')); S.glowBloomMul = fx('p_glow'); S.glowBloomAdd = (.12 * buzz + .3 * S.sharp_v) * fx('p_bloom'); S.fogMul = fx('p_haze');
  }
  // ---- _efc_tick(delta)  (6737): the face in the picture and the God in the sky, their timers and envelopes
  function efcTick(delta) {
    const deep = Math.max(molAvg(), fxLevel()), auto = fx('p_face_auto');
    if (S.efc_t < 0) { if (deep > .25 && auto > .01) { S.efc_next -= delta * auto; if (S.efc_next <= 0) { S.efc_t = 0; S.efc_next = rand(70, 150, 'efc'); S.efc_peek = rand(0, 1, 'efcpeek') < .45; } } }
    else { S.efc_t += delta; if (S.efc_t > 14) S.efc_t = -1; }
    let envK = 0; if (S.efc_t >= 0) envK = sstep(0, 5, S.efc_t) * (1 - sstep(9, 14, S.efc_t));
    const manual = fx('p_face'); S.efc_k = clamp(Math.max(manual, envK * .6), 0, 1);
    const gauto = fx('p_god_auto');
    if (S.god_t < 0) { if (deep > .35 && gauto > .01) { S.god_next -= delta * gauto; if (S.god_next <= 0) { S.god_t = 0; S.god_next = rand(200, 360, 'god'); } } } else { S.god_t += delta; if (S.god_t > 26) S.god_t = -1; }
    let genv = 0; if (S.god_t >= 0) genv = sstep(0, 6, S.god_t) * (1 - sstep(18, 26, S.god_t));
    S.god_k = clamp(Math.max(fx('p_god'), genv * .85), 0, 1);
    if (manual > .001 && S.efc_t < 0) S.efc_lift = 0; else if (S.efc_peek) S.efc_lift = S.efc_t < 9 ? lerp(.70, .28, sstep(0, 6, S.efc_t)) : lerp(.28, .70, sstep(9, 14, S.efc_t)); else S.efc_lift = -.10;
  }
  // ---- _pill_tick(delta)  (9890): the physics-rate half of the model
  function tickPhysics(delta, ctx) {
    S._ctx = ctx; F.mult_t = Math.max(F.mult_t - delta, 0);
    if (pacer) pacer.tick(delta);
    S.mol_hurt_t = Math.max(S.mol_hurt_t - delta * 1.5, 0);
    let wear = 1; if (pacer) wear = 1 + 12 * Math.max(molAvg() - pacer.target() - .05, 0);
    for (let i = 0; i < 6; i++) { S.mdose[i] = Math.max(S.mdose[i] - (i === 1 ? .004 : .008) * wear * delta, 0); const rate = S.mdose[i] > S.mbody[i] ? 25 : 8; S.mbody[i] += (S.mdose[i] - S.mbody[i]) * (1 - Math.exp(-delta / rate)); }
    const dm = molDmt(); if (dm > .5 && !S.dmt_on) { S.dmt_on = true; cheer('ALL SIX', -1, 2.2); cb('onDmt'); } else if (dm < .3) S.dmt_on = false;
    {          // the picture-pass block
      let wk = 1; if (O.dir) wk = .7 + .6 * (ctx.wave !== undefined ? ctx.wave : .5);          // the effects breathe with the music's wave (0.5 when the stems are not playing)
      let ma = [S.mbody[0] / 6, S.mbody[1] / 6, S.mbody[2] / 6], mb = [S.mbody[3] / 6, S.mbody[4] / 6, S.mbody[5] / 6];
      wk *= S.stage_post;
      ma = ma.map((v) => Math.pow(v, 1.15) * wk); mb = mb.map((v) => Math.pow(v, 1.15) * wk);
      const fl = fxLevel() * wk; ma = ma.map((v) => Math.max(v, fl)); mb = mb.map((v) => Math.max(v, fl));
      ma = ma.map((v, i) => v + S.mflash[i] * .9); mb = mb.map((v, i) => v + S.mflash[3 + i] * .9);
      ma = ma.map((v) => v * S.clr_k); mb = mb.map((v) => v * S.clr_k); S.mA = ma; S.mB = mb; S.dmt = dm * S.clr_k;
      buzzTick(delta, ctx);
    }
    stageTick(delta);
    S.pill_gap = Math.max(S.pill_gap - delta, 0); S.flick = Math.max(S.flick - delta * 2, 0);
    S.dose = Math.max(S.dose - .006 * wear * delta, 0);
    if (O.journey) S.dose = Math.min(S.dose, (S.mdose[0] + S.mdose[1] + S.mdose[2] + S.mdose[3] + S.mdose[4] + S.mdose[5]) * .42 + 1.2);          // _mol_rows
    S.body += (S.dose - S.body) * (1 - Math.exp(-delta / 25));
    if (J.on) { S.drift_t -= delta; if (S.drift_t <= 0) { S.drift_t = 100; S.dose += .7; } }
    S.pill_k = S.flick > 0 ? .5 * Math.pow(Math.max(Math.sin((1 - S.flick) * Math.PI * 2 * 1.5), 0), 1.4) : 0;
    if (S.flick > .9) S.sky_flash = 1;
    S.pill_k *= .12 + .88 * S.stage_post;
    const altNow = ctx.alt || 0;
    if (ctx.inAir && S.apex_vy > 0 && (ctx.vy || 0) <= 0 && altNow > 7 && !ctx.faceOk && !ctx.faceKind && S.apex_t <= 0) { S.apex_t = 1.9; S.apex_amp = .28 + .3 * clamp(molAvg() * 1.5, 0, 1); kick('apex'); cb('onApex'); }
    S.apex_vy = ctx.vy || 0;
    if (S.apex_t > 0) { S.apex_t = Math.max(S.apex_t - delta, 0); S.pill_k = Math.max(S.pill_k, S.apex_amp * (.3 + .7 * S.stage_post) * Math.sin(Math.PI * (1 - S.apex_t / 1.9))); S.sky_flash = Math.max(S.sky_flash, Math.sin(Math.PI * (1 - S.apex_t / 1.9))); }
    chainTick(delta);
    if (!J.on) return;
    if (S.pill_k > .001 || molAvg() > .01) { S.pill_live = true; if (J.phase === CALM && hint() < .001) journeyPost('psychedelic', 0, false, .9); }
    else if (S.pill_live) { S.pill_live = false; if (J.phase === CALM && hint() < .001) journeyPost('psychedelic', 0, false, .3); }
  }
  // ---- _trip_tick(delta)  (1504) and _exc_tick  (8398): the process-rate half
  function tripTick(delta) {
    if (!S.trip_on) return;
    if (S.trip_force >= 0) S.trip = S.trip_force;
    else {
      S.trip = Math.max(S.trip - (.018 + .02 * S.trip) * delta, 0);
      if (J.on) S.trip = Math.max(S.trip, tripFloor());
      S.trip = Math.max(S.trip, Math.pow(molAvg(), 1.8) * .8 * S.stage_post);
    }
    const tier = S.trip < .25 ? 0 : (S.trip < .55 ? 1 : (S.trip < .85 ? 2 : 3));
    if (tier > S.trip_tier && S.trip_force < 0) { cheer(['', 'things get colourful...', 'WHOA', 'FULL TRIP!!'][tier], -1, .8 + .4 * tier); gain(Math.trunc(100 * tier * F.groove)); }
    S.trip_tier = tier; S.post.breathe = S.post.amount0 * (1 + S.trip * 6);
  }
  function excTick(delta, ctx) {
    const sp = clamp(((ctx.speedY || 0) - 20) / 30, 0, 1), fl = clamp((ctx.chain || 0) / 12, 0, 1), bo = ctx.boosting ? 1 : 0, ln = clamp((ctx.links || 0) / 8, 0, 1);
    const goal = clamp(.45 * sp + .25 * fl + .15 * bo + .15 * ln, 0, 1); S.exc += (goal - S.exc) * (1 - Math.exp(-delta / 1.5));
  }
  function tickProcess(delta, ctx) {          // RunRig._process order: the camera and flash decay (super._process), then _trip_tick, _exc_tick, and last the journey's tick
    C.shake = Math.max(C.shake - 1.6 * delta, 0); C.fov_punch = Math.max(C.fov_punch - 24 * delta, 0); C.flash = Math.max(C.flash - 2 * delta, 0);
    tripTick(delta); excTick(delta, ctx); if (J.on) jtick(delta);
  }
  function tick(dt, ctx = {}) { S.age += dt; tickPhysics(dt, ctx); tickProcess(dt, ctx); }

  // ---- setup, as RunRig.apply_menu does it (RunRig.gd 10731-10790)
  if (O.journey) { J.world = ARC[0].w; J.calm_len = jcalm(0); J.prewarm_t = 5; planWave(); for (const s of STAGES) J.shown[s] = false; setLook(0, O.intensity); }          // (the alpine run starts with the pass parked: mode 0, at the menu's intensity)
  else { S.trip_on = true; setLook(1, O.intensity); S.post.light = false; S.post.use_trail = 1; }          // the plain psychedelic world: post mode 1 from the start, the trip meter on
  function uniforms() {
    const P = S.post;
    return {
      mode: P.mode, amount: P.amount, breathe: P.breathe, onset: P.onset, use_trail: P.use_trail, layerVisible: P.layer, trip: S.trip,
      mA: S.mA.slice(), mB: S.mB.slice(), dmt: S.dmt, buzz: S.buzz, sharp: S.sharp, tube: S.tube, smear: S.smear, rewind: S.rewind,
      k_chroma: S.k.chroma, k_trace: S.k.trace, k_punch: S.k.punch, k_warp: S.k.warp, k_fold: S.k.fold, k_pulse: S.k.pulse, k_rings: S.k.rings, k_dmtr: S.k.dmtr, k_wash: S.k.wash, k_edge: S.k.edge, k_cel: S.k.cel, edge_hue: S.k.edge_hue,
      glowIntensityMul: S.glowMul, glowBloomMul: S.glowBloomMul, glowBloomAdd: S.glowBloomAdd, fogDensityMul: S.fogMul, skyFlash: S.sky_flash,
    };
  }
  return {
    state: S, journey: J, pacer, fx, uniforms, tick, tickPhysics, tickProcess, pillEat, molGift, molHurt, tripAdd, sharpen, chainPayoff: () => sharpen(1), events: ev, perks, world, biomeApply, kick, cameraFov, shakeOffset, camera: C, flow: F, gain, flowUp, flowTouch, chainHit, chainK, flowSpeedBonus, cheer, pk, molAvg, molDmt, molCount, clarityK: () => S.clr_k,
    forceBody(arr) { for (let i = 0; i < 6; i++) { S.mdose[i] = arr[i]; S.mbody[i] = arr[i]; } S.mol_seen = true; },
    onsetK, hint, tripFloor, wantsTrip, phaseName: () => PH_NAMES[J.phase], stageFractions: () => Object.fromEntries(['sky', 'ground', 'veg', 'light'].map((s) => [s, jfrac(s)])), difficulty,
    pieces: () => [0, 1, 2, 3, 4, 5].map(pk),
  };
}
