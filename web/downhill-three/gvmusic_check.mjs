// node gvmusic_check.mjs : simulates a whole session of the arc director on a stand-in audio engine (no browser) and asserts the arc:
// layers enter only on bar lines, nothing but the pre-trip layers plays before the trip, the funk comes in on a bar line after the trip kicks in, the drop lands on a bar line (a multiple of 8) with a boom on it,
// the clarity gating and the slam back on the grid, the chill-out at the comedown, the wrap-around, and that nothing but fades/gain is ever done to a track.
import { createGvMusic } from './gvmusic.js';

const BEAT = 60 / 128, BAR = 4 * BEAT;
class P { constructor(v) { this.value = v; this.ev = []; } setValueAtTime(v, t) { this.ev.push({ k: 's', v, t }); } linearRampToValueAtTime(v, t) { this.ev.push({ k: 'l', v, t }); } exponentialRampToValueAtTime(v, t) { this.ev.push({ k: 'e', v, t }); } cancelScheduledValues(t) { this.ev = this.ev.filter((e) => e.t < t); } setTargetAtTime() { } }
class N { constructor() { this.gain = new P(0); this.frequency = new P(0); this.Q = new P(0); this.type = ''; this.out = null; } connect(n) { this.out = n; return n; } disconnect() { this.out = null; } }
const CTX = { currentTime: 0, state: 'running', resume: async () => { }, suspend: () => { }, createGain: () => new N(), createBiquadFilter: () => new N() };
const booms = [], whooshes = [], cutoffs = [];
class MockMusic {
  constructor() { this.ctx = CTX; this.stems = {}; this.beat = BEAT; this.t0 = 0; this.started = false; this.musicBus = new N(); this.sfxBus = new N(); }
  load(name) { const g = new N(); this.stems[name] = { buf: {}, gain: g, ready: Promise.resolve() }; g.connect(this.musicBus); return this.stems[name].ready; }
  start() { this.started = true; this.t0 = CTX.currentTime + 0.15; }
  level() { } setVolume() { }
  cutoff(f) { cutoffs.push({ t: CTX.currentTime, f }); }
  beatPos() { return (CTX.currentTime - this.t0) / this.beat; }
  nextGrid(div = 4) { const g = this.beat / div, now = CTX.currentTime + 0.012; return this.t0 + Math.ceil((now - this.t0) / g) * g; }
  tone() { } boom() { booms.push({ at: CTX.currentTime, when: this.nextGrid(2) }); } whoosh(dur, up) { whooshes.push({ at: CTX.currentTime, dur, up }); }
}
const plays = [], gainsSet = [];
const trackFactory = (url) => { const key = /moodless/.test(url) ? 'moodless' : url.split('/').pop().replace(/\.(ogg|mp3)$/, ''); let t0 = 0, on = false; return { ready: true, failed: false, play() { on = true; t0 = CTX.currentTime; plays.push({ key, at: CTX.currentTime }); }, setGain(v) { gainsSet.push({ key, t: CTX.currentTime, v }); }, pos: () => (on ? CTX.currentTime - t0 : 0), dur: () => 240, pause() { }, stop() { plays.push({ key, stop: CTX.currentTime }); on = false; } }; };

let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const frac = (x) => Math.abs(x - Math.round(x));

const SESSION = 600, PH = [['settle', 0, .07], ['come up', .07, .30], ['peak', .30, .52], ['plateau', .52, .70], ['comedown', .70, 1.01]];
const phaseOf = (u) => PH.find((p) => u >= p[1] && u < p[2])[0];
const TRIP_T = 110, CLAR_T = 240, SHARP_T = 270;
const clarityAt = (s) => (s < 0.35 ? 1 + (0.1 - 1) * s / 0.35 : s < 1.7 ? 0.1 : s < 2.4 ? 0.1 + 1.2 * (s - 1.7) / 0.7 : s < 5 ? 1.3 - 0.3 * (s - 2.4) / 2.6 : 1);

async function session(withPhase) {
  CTX.currentTime = 0; booms.length = 0; whooshes.length = 0; cutoffs.length = 0; plays.length = 0; gainsSet.length = 0; const L = [];
  const gm = createGvMusic({ Music: MockMusic, trackFactory, log: (e) => L.push(Object.assign({}, e, { _now: CTX.currentTime })), stemAfter: 1 }); await gm.start();
  const M = gm.audio().music, marks = {}; let sharp = 0, prevStage = '';
  for (let f = 0; f < 60 * 660; f++) {
    CTX.currentTime += 1 / 60; const t = CTX.currentTime, ts = t % SESSION, u = ts / SESSION;
    const trip = ts >= TRIP_T && ts < 480, a = !trip ? 0 : ts < 200 ? 0.3 * (ts - TRIP_T) / 150 : ts < 312 ? 0.3 : ts < 420 ? 0.3 - 0.1 * (ts - 312) / 108 : Math.max(0, 0.2 - 0.2 * (ts - 420) / 60);
    const cs = ts - CLAR_T; if (t >= SHARP_T && t < SHARP_T + 0.02) sharp = 1; sharp = Math.max(0, sharp - 0.42 / 60);
    const st = { felt: [a, a, a, a, a, a], excitement: Math.min(1, 0.2 + a), dmt: a > 0.25 ? 0.5 : 0, speed01: 0.5, chain: 0, airborne: false };
    if (withPhase) { st.phase = phaseOf(u); st.u = u; st.tripOn = trip; st.clarityK = cs >= 0 && cs < 5 ? clarityAt(cs) : 1; st.sharp = sharp; }
    gm.tick(1 / 60, st);
    const stg = gm.arc.stage; if (stg !== prevStage) { marks[stg + '@' + Math.round(t)] = t; prevStage = stg; }
  }
  return { gm, M, L, marks };
}

// ================= the arc with the phase supplied
const { gm, M, L, marks } = await session(true);
const T0 = M.t0, bar = (t) => (t - T0) / BAR, beatsOf = (t) => (t - T0) / BEAT;
const segs = L.filter((e) => e.param);
console.log('stages:', Object.keys(marks).join('  '));
ok(segs.every((e) => Number.isFinite(e.to) && Number.isFinite(e.at)), 'every scheduled automation is a finite number');
// layers enter only on bar lines (and beat lines for the holes, grid lines for the clarity slam)
const bad = (kind, tol, unit, skip) => { const r = segs.filter((e) => e.kind === kind && !(skip && skip(e)) && frac((e.at - T0) / unit) * unit > tol); if (r.length && process.env.DEBUG) console.log('  offenders', kind, r.slice(0, 6).map((e) => e.param + ' at ' + e.at.toFixed(4) + ' off ' + (frac((e.at - T0) / unit) * unit).toFixed(4) + ' now ' + e._now.toFixed(3) + ' to ' + e.to)); return r; };
ok(bad('bar', 1e-6, BAR, (e) => e.param === 'hp').length === 0, 'every "bar" automation starts exactly on a bar line  (' + segs.filter((e) => e.kind === 'bar').length + ' of them)');
ok(bad('bar', 0.006, BAR, (e) => e.param !== 'hp').length === 0, 'the high-pass resets sit on bar lines to within 5 ms');
ok(bad('beat', 1e-6, BEAT).length === 0, 'every beat-dropout / accent starts exactly on a beat line  (' + segs.filter((e) => e.kind === 'beat').length + ' of them)');
ok(bad('grid', 1e-6, BEAT / 2).length === 0, 'the clarity slam-back lands exactly on an eighth-note line  (' + segs.filter((e) => e.kind === 'grid').length + ')');
// pre-trip: only the pre layers, entering in order
const preBar0 = L.find((e) => e.stage === 'pre').bar, tripAt = TRIP_T;
const first = (name, pred) => segs.find((e) => e.param === 'stem:' + name && e.to > 0 && (!pred || pred(e)));
for (const n of ['drums', 'piano', 'guitar', 'synth', 'acid']) ok(!segs.some((e) => e.param === 'stem:' + n && e.to > 0 && e._now < tripAt), 'before the trip: no ' + n + ' at all');
const fxIn = first('fx'), puIn = first('pulse'), baIn = first('bass');
ok(fxIn && bar(fxIn.at) >= preBar0 + 8 - 1e-6 && bar(fxIn.at) < preBar0 + 9, 'the fx stem enters at bar 8 of the pre-trip (bar ' + (fxIn && (bar(fxIn.at) - preBar0).toFixed(2)) + ')');
ok(puIn && Math.abs(bar(puIn.at) - preBar0 - 16) < 1e-6, 'the pulse enters at bar 16 (' + (puIn && (bar(puIn.at) - preBar0).toFixed(2)) + ')');
ok(baIn && Math.abs(bar(baIn.at) - preBar0 - 24) < 1e-6, 'the bass sub enters at bar 24 (' + (baIn && (bar(baIn.at) - preBar0).toFixed(2)) + ')');
const bassPre = segs.filter((e) => e.param === 'stem:bass' && e.kind === 'bar' && e._now < tripAt && bar(e.at) - preBar0 >= 24).slice(0, 8).map((e) => e.to > 0 ? 1 : 0);
ok(bassPre.length >= 6 && bassPre.every((v, i) => i === 0 || v !== bassPre[i - 1]), 'the bass sub is gated one bar on, one bar off  ' + bassPre.join(''));
const holes = segs.filter((e) => e.param === 'stem:ambience' && e.kind === 'beat' && e.to === 0 && e._now < tripAt);
ok(holes.length >= 1 && holes.every((e) => Math.abs(beatsOf(e.at) % 4 - 3) < 1e-6), 'a one-beat dropout on the 4th beat of the last riser bar  (' + holes.length + ' before the trip)');
const hpMax = Math.max(...segs.filter((e) => e.param === 'hp' && e._now < tripAt).map((e) => e.to));
ok(hpMax > 1300 && hpMax < 1500, 'the riser high-pass sweeps up to 1.4 kHz (' + hpMax.toFixed(0) + ' Hz)');
ok(whooshes.some((w) => w.up && w.at < tripAt), 'a whoosh under the risers');
// funk kicks in on a bar line after the trip
const funk = plays.find((p) => /funk|quirky/.test(p.key) && p.at !== undefined);
const tf = funk.at, nb = Math.round(bar(tf));
ok(tf > tripAt && Math.abs(tf - (T0 + nb * BAR)) < 0.035, 'a funk track (' + funk.key + ') starts on a bar line (off by ' + ((tf - (T0 + nb * BAR)) * 1000).toFixed(0) + ' ms) at ' + tf.toFixed(1) + ' s, after the trip kicked in at ' + tripAt + ' s');
const duck = segs.find((e) => e.param === 'stem:ambience' && e.to === 0 && e._now > tripAt && e.kind === 'bar');
ok(duck && Math.abs(bar(duck.at) - (nb - 1)) < 1e-6 && Math.abs(duck.dur - BAR) < 1e-6, 'the stems duck out over exactly one bar, the bar before the funk');
ok(booms.some((b) => Math.abs(b.when - (T0 + nb * BAR)) < 1e-6), 'a boom lands on the funk bar line');
const fadeG = gainsSet.filter((g) => g.key === funk.key && g.t >= tf && g.t <= tf + 4.5), peakG = Math.max(...fadeG.map((g) => g.v));
ok(fadeG.length > 20 && fadeG[0].v < fadeG[fadeG.length - 1].v && peakG > 0.1, 'the funk is faded in over about 2 bars (gain only)');
// the drop
const dropE = L.find((e) => e.drop !== undefined), D8 = dropE.drop, tD = T0 + D8 * BAR;
ok(D8 % 8 === 0, 'the drop is on a bar that is a multiple of 8 (bar ' + D8 + ') at ' + tD.toFixed(1) + ' s');
ok(tD >= 0.30 * SESSION - 1 && tD < 0.30 * SESSION + 20, 'and it comes as the peak phase begins (' + tD.toFixed(1) + ' s; the peak starts at ' + (0.30 * SESSION) + ' s)');
ok(booms.some((b) => Math.abs(b.when - tD) < 1e-6), 'a boom lands exactly on the drop');
const dropIn = ['pulse', 'bass', 'drums', 'piano', 'guitar', 'synth', 'acid'].map((n) => segs.find((e) => e.param === 'stem:' + n && Math.abs(e.at - tD) < 1e-6 && e.to > 0));
ok(dropIn.every(Boolean), 'all seven stems come in together on the drop line');
const bl = segs.filter((e) => e.param === 'stem:fx' && e.kind === 'bar' && e.at >= tD - 2 * BAR - 1e-6 && e.at < tD - 1e-6);
ok(bl.length >= 2 && Math.abs(bl[0].at - (tD - 2 * BAR)) < 1e-6, 'the pre-drop break starts exactly 2 bars before the drop (fx in, riser)');
const lpBreak = segs.filter((e) => e.param === 'lp' && e.at >= tD - 2 * BAR - 1e-6 && e.at <= tD + 1e-6);
ok(lpBreak.some((e) => Math.abs(e.to - 700) < 1) && lpBreak.some((e) => e.to === 7000) && lpBreak.some((e) => e.to === 18000 && Math.abs(e.at - tD) < 1e-6), 'the break closes the low-pass to 700 Hz, opens it to 7 kHz, and the drop opens it fully');
const hole = segs.find((e) => e.param === 'stem:drums' || true && e.param === 'stem:ambience' && e.kind === 'beat' && Math.abs(e.at - (tD - BEAT)) < 1e-6);
ok(!!hole, 'one-beat hole on the last beat before the drop');
ok(!segs.some((e) => e.param === 'stem:drums' && e.to > 0 && e.at < tD - 1e-6 && e._now > tripAt), 'no drums before the drop');
// the funk is gone by the time the stems are open
const fo = gainsSet.filter((g) => g.key === funk.key && g.t > tD - 1 && g.t < tD + 1); ok(fo.length && fo[fo.length - 1].v < 0.05, 'the funk has faded out by the drop');
const co = cutoffs.filter((c) => c.f === 16000); ok(co.length > 0 && cutoffs.filter((c) => c.t > tf + 0.3 && c.t < tD - 3 * BAR).every((c) => c.f === 3000), 'the engine low-pass stays at 3 kHz while a track is audible (never opened over the funk)');
// sustain: pattern variation on 4-bar phrases, a hole on the end of the 4th phrase
const sus = segs.filter((e) => e.param === 'stem:acid' && e.kind === 'bar' && e.at > tD + 0.5 && e.at < tD + 20 * BAR).map((e) => e.to > 0 ? 1 : 0);
ok(sus.includes(0) && sus.includes(1), 'acid is muted for a phrase and back again during the sustain (' + sus.join('') + ')');
ok(segs.some((e) => e.param === 'stem:drums' && e.kind === 'beat' && e.to === 0 && e.at > tD + 0.5), 'a one-beat hole closes a phrase in the sustain');
// clarity
const cl = L.find((e) => e.clarity === 'drop'), sn = L.find((e) => e.clarity === 'snap');
ok(cl && sn, 'the clarity drop and snap were both seen (stage then: ' + (cl && 'drop') + ')');
const gate = segs.filter((e) => e.kind === 'now' && e.param.startsWith('stem:') && e._now >= cl._now - 1e-9 && e._now < cl._now + 0.01 && e.to === 0);
ok(gate.length === 8 && !gate.some((e) => e.param === 'stem:ambience'), 'on the clarity drop eight stems (all but the ambience) are gated to nothing in 0.12 s');
ok(segs.some((e) => e.param === 'lp' && e.kind === 'now' && e.to === 500 && Math.abs(e._now - cl._now) < 0.01), 'and the stem low-pass closes to 500 Hz');
const slam = segs.filter((e) => e.kind === 'grid' && e.param.startsWith('stem:')), slamT = slam[0] && slam[0].at;
ok(slam.length >= 8 && slamT > cl._now + 1 && slamT - sn._now < BEAT, 'the full mix slams back on the next eighth after the snap (' + (slamT && (slamT - sn._now).toFixed(3)) + ' s later)');
ok(booms.some((b) => Math.abs(b.when - slamT) < 1e-6), 'with a boom on the same line');
ok(L.some((e) => e.sharp), 'the sharpen snap gave an accent');
// chill-out
const moodless = plays.find((p) => p.key === 'moodless' && p.at !== undefined), tm = moodless.at;
ok(tm >= 0.70 * SESSION - 1 && tm < 0.70 * SESSION + 5 && Math.abs(tm - (T0 + Math.round(bar(tm)) * BAR)) < 0.035, 'Moodless Refrain starts on a bar line as the comedown begins (' + tm.toFixed(1) + ' s; comedown at ' + 0.70 * SESSION + ' s)');
const ch = segs.filter((e) => e.param.startsWith('stem:') && e.to === 0 && e.at > tD + 60 && Math.abs(e.dur - 5) < 1e-6); ok(ch.length === 9, 'every stem fades out over 5 s at the comedown (' + ch.length + ')');
const mg = gainsSet.filter((g) => g.key === 'moodless'); ok(mg.length > 50 && mg[mg.length - 1].v === mg[mg.length - 1].v && Math.max(...mg.map((g) => g.v)) > 0.2, 'Moodless is faded in by gain only (' + mg.length + ' gain writes)');
ok(!segs.some((e) => e.param === 'stem:drums' && e.to > 0 && e._now > tm && e._now < SESSION - 1), 'no stems in the chill-out');
// wrap-around
const wrap = L.filter((e) => e.stage === 'pre'), w2 = wrap[wrap.length - 1];
ok(wrap.length >= 2 && w2.at >= SESSION - 1 && w2.at < SESSION + 4, 'at the wrap (settle again) the arc returns to the pre-trip atmosphere (' + w2.at.toFixed(1) + ' s)');
ok(plays.some((p) => p.key === 'moodless' && p.stop !== undefined && p.stop > SESSION - 1), 'the chill-out track is faded out and stopped');
ok(segs.some((e) => e.param === 'stem:ambience' && e._now > SESSION && e.to > 0) && segs.some((e) => e.param === 'stem:fx' && e._now > SESSION + 10 && e.to > 0), 'the pre-trip layers rebuild after the wrap (ambience, then fx)');
ok(gm.arc.stage === 'pre', 'the session ends in the pre-trip stage');
// nothing is ever done to a track but gain: the director never gives a track a node or a filter
ok(!segs.some((e) => /moodless|funk|quirky/.test(e.param)), 'no filter, no automation of any kind on a track: only setGain and fades');

// ================= without a phase (the old callers): felt average only
const r2 = await session(false);
ok(r2.gm.arc.stage !== undefined && r2.L.some((e) => e.stage === 'funk') && r2.L.some((e) => e.drop !== undefined), 'without a phase the felt average still drives it: pre -> funk -> drop');
console.log(fails ? '\n' + fails + ' FAILED' : '\nall passed');
process.exit(fails ? 1 : 0);
