// GV MUSIC, THE ARC DIRECTOR. The Godot game's music director (godot/scripts/DhDirector.gd) grown into the director of the whole flagship trip, on the sample-accurate stem engine (music.js).
// Real recordings only, nothing synthesised for the music: the Alien Warfare stems (CC BY-NC 3.0, filters, gating and level changes on them are allowed: they are derivatives), the three funk tracks and Moodless Refrain
// (used exactly as they are: ONLY fades, gain and ducking, because two of the funk tracks are NoDerivatives; no filter, no time-stretch and no effect is ever put on them). A missing file is silence.
//
// THE ARC (driven by psyfx's session pacer: settle .00-.07, come up .07-.30, peak .30-.52, plateau .52-.70, comedown .70-1.00 of the session):
//   PRE-TRIP      atmosphere and tension from the stems alone, everything entering on a bar line (the engine's own beat clock, 128 BPM, one bar = 1.875 s):
//                   bar  0   the ambience, behind a low-pass that is nearly shut (700 Hz) and opens slowly (to 5.2 kHz over 32 bars)
//                   bar  8   the fx stem swells, 4 bars up and cut back, over and over
//                   bar 16   the pulse enters, filtered (it is behind the low-pass)
//                   bar 24   the bass sub, gated by the bar (one bar on, one bar off), and from here a RISER every 8 bars: the whole stem group's high-pass sweeps 20 Hz -> 1.4 kHz over 8 bars,
//                            the fx stem climbs, a long whoosh underneath, and on the 4th beat of the last bar a one-beat dropout (everything out) before the next entry. No drums yet, ever, before the trip.
//   TRIP KICKS IN (the first molecule felt, or the journey's onset): on the next bar line the stems duck out over one bar (a whoosh up), and on the bar line after that a FUNK track crossfades in over 2 bars with a boom.
//                 It plays through the come-up and the waves. (Which funk track: by how hard the run is going, sunny < .3 <= lift < .6 <= rush, as in Godot.)
//   CLIMAX        when the peak phase begins: on the next 8-bar boundary minus 2 bars the funk fades out and the PRE-DROP BREAK starts: bar 1 everything is sucked into the ambience and fx behind a closing low-pass
//                 (700 Hz) and a whoosh down; bar 2 the riser: low-pass opening, high-pass sweeping up, fx climbing; on the last beat before the drop a one-beat HOLE (everything out). Then THE DROP, on a bar
//                 line that is a multiple of 8: every stem at once, drums and bass heavy, the filters fully open, a boom. It is sustained through the peak and the plateau with variation on 4-bar phrases
//                 (acid and guitar out for a phrase, piano and synth out for a phrase, a full phrase that ends in a one-beat hole), the molecules you hold colouring which parts are loudest.
//   SYNC          the moment of clarity (psyfx _clr_k): when the picture drops to a tenth the stems but the ambience are gated out in 0.12 s and the stem low-pass closes (500 Hz); when it snaps back (to 1.3) the
//                 full mix slams back on the next eighth note, with a boom. The sharpen snap is a short accent: a boom and an fx hit on the next beat.
//   CHILL-OUT     the comedown phase: on the next bar line the stems and the funk fade out over 5 s while Moodless Refrain (Apoxode) fades in over the same 5 s. When the session wraps (settle again) the chill-out fades out and
//                 the pre-trip atmosphere starts again from bar 0.
//
// TICK CONTRACT:  tick(dt, st), st fields (all optional, the old ones still work):
//   felt: [6 numbers 0..1]  the six molecules as felt (mescaline, DOM, 2C-B, 2C-E, 2C-T-2, 2C-T-7), Godot's _mbody / 6      avg: number (default: their mean)      dmt: 0..1      excitement: 0..1 (funk band, as in Godot)
//   phase: 'settle' | 'come up' | 'peak' | 'plateau' | 'comedown'   (psyfx pacer.phaseName(); without it the phase is inferred from the felt average, as in Godot)     u: 0..1 session progress (only used to start fetching Moodless early)
//   tripOn: bool  the trip has kicked in (first molecule felt / journey onset; default avg >= 0.03)
//   clarityK: 0.1 .. 1.3  psyfx's _clr_k (the moment of clarity; edges are detected here)     sharp: 0..1  psyfx's _sharp (a snap to 1 that eases off; the rising edge is detected here)
//   chill: bool  force the chill-out (same as phase 'comedown')     chain, airborne, speed01: kept for the callers, not used by the arc
// EVENTS: onMolecule(id), onChain(level), onCue(+1|-1), onBump(k), onClarityDrop(), onClaritySnap(), onSharp(), duck() (every sound effect ducks the stems and funk by 28 % for a moment).
// opts: base ('../music/'), Music (the engine class, for tests), trackFactory (for tests), stemAfter (s, default 2), log (fn: every automation the director schedules, for tests), volume.
//
// CREDITS (show them somewhere, the licences ask for it; everything here is NON-COMMERCIAL):
//   Alien Warfare Stems, Kamihamiha, CC BY-NC 3.0, ccmixter.org/files/Kamihamiha/60882
//   Funk it!, SunnyScy, CC BY-NC-SA 4.0, freemusicarchive.org/music/sunnyscy/single/funk-it-1/
//   Quirky Funk, butterflystudio, CC BY-NC-ND 4.0, freemusicarchive.org/music/butterflystudio/quirky-funk/quirky-funk/
//   Funk Express, butterflystudio, CC BY-NC-ND 4.0, freemusicarchive.org/music/butterflystudio/funky-grooves/funk-express/
//   Moodless Refrain (ft. Quiana Nadine), Apoxode, CC BY-NC 4.0 (per the project's licence notes)

const STEMS = ['ambience', 'pulse', 'bass', 'drums', 'piano', 'guitar', 'synth', 'acid', 'fx'];
const MOL_ORDER = ['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'];
const TRACKS = {
  funk_it: { file: 'funk_it.ogg', gain: -1.8 }, quirky_funk: { file: 'quirky_funk.ogg', gain: -7.2 }, funk_express: { file: 'funk_express.ogg', gain: -8.9 }, moodless: { file: 'moodless_refrain.mp3', gain: -4 },
};
const BANDS = { sunny: ['funk_it', 'quirky_funk'], lift: ['funk_express', 'quirky_funk'], rush: ['funk_express'], down: ['funk_it', 'quirky_funk'], chill: ['moodless'] };
const BPM = 128, FADE_S = 5, BAR_S = 4 * 60 / BPM, BEAT_S = 60 / BPM;
const FUNK_IN_BARS = 2, LOOK = 0.2;          // the funk crossfades in over 2 bars; every bar line is prepared 0.2 bar (0.375 s) ahead, so the automation is scheduled exactly on the line
const BASE_CUT = 3000, OPEN_CUT = 16000;          // the engine's own output low-pass: 3 kHz while a track (funk / Moodless) is audible, exactly as it always was; opened while only the stems play
const LP_OPEN = 18000, LP_SHUT = 700, HP_REST = 20;          // the stem group's own filters (they never touch a track)
const LADDER = [440.0, 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5, 1568.0];          // the glint ladder: one rung higher each time, up A C D E G
const dbLin = (db) => Math.pow(10, db / 20);
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;
const moveToward = (a, b, d) => (Math.abs(b - a) <= d ? b : a + Math.sign(b - a) * d);
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const fposmod = (x, m) => ((x % m) + m) % m;
export const CREDITS = [
  'Alien Warfare Stems, Kamihamiha (CC BY-NC 3.0) ccmixter.org/files/Kamihamiha/60882',
  'Funk it!, SunnyScy (CC BY-NC-SA 4.0) freemusicarchive.org/music/sunnyscy/single/funk-it-1/',
  'Quirky Funk, butterflystudio (CC BY-NC-ND 4.0) freemusicarchive.org/music/butterflystudio/quirky-funk/quirky-funk/',
  'Funk Express, butterflystudio (CC BY-NC-ND 4.0) freemusicarchive.org/music/butterflystudio/funky-grooves/funk-express/',
  'Moodless Refrain (ft. Quiana Nadine), Apoxode (CC BY-NC 4.0)',
];

// the default way to play a long track: the file is downloaded first (chosen once, then waited for while it downloads, as in Godot's _fetch) and played from an <audio> element through the music bus,
// so a phone never has to hold minutes of decoded audio. Replaceable (opts.trackFactory) so the director can be tested without a browser.
function browserTrackFactory(M) {
  return (url) => {
    let el = null, node = null, g = null, ready = false, failed = false, obj = null;
    const done = fetch(url).then((r) => { if (!r.ok) throw new Error('x'); return r.blob(); }).then((b) => { if (b.size < 1000) throw new Error('x'); obj = URL.createObjectURL(b); ready = true; }).catch(() => { failed = true; });
    return {
      get ready() { return ready; }, get failed() { return failed; }, done,
      play() { el = new Audio(); el.src = obj; el.loop = false; el.preload = 'auto'; node = M.ctx.createMediaElementSource(el); g = M.ctx.createGain(); g.gain.value = 0; node.connect(g); g.connect(M.musicBus); el.play().catch(() => { }); },
      setGain(v) { if (g) g.gain.setTargetAtTime(v, M.ctx.currentTime, 0.08); },
      pos() { return el ? el.currentTime : 0; }, dur() { return el && isFinite(el.duration) ? el.duration : 1e9; },
      pause(b) { if (el) { if (b) el.pause(); else el.play().catch(() => { }); } },
      stop() { try { if (el) { el.pause(); el.removeAttribute('src'); el.load(); } if (node) node.disconnect(); if (g) g.disconnect(); } catch (e) { /* */ } el = null; node = null; g = null; },
    };
  };
}

// One automated AudioParam. plan(list of segments) cancels what is still scheduled, holds the value it has reached, and lays the new segments down in one go (so several steps of one plan never cancel each other).
// A segment: { to, at (audio-clock seconds), dur, kind }  it holds the previous value until `at`, then ramps (linear, or exponential for frequencies) to `to` over `dur` (0 = a step). The model of what the param is doing
// is kept here, so the value "now" is always known (cancelScheduledValues alone would jump back).
class Auto {
  constructor(param, v0, exp, name, log) { this.p = param; this.exp = !!exp; this.name = name; this.log = log; this.base = v0; this.sg = []; }
  value(t) { let v = this.base; for (const s of this.sg) { if (t < s.t0) break; v = t >= s.t1 ? s.v1 : (this.exp ? s.v0 * Math.pow(s.v1 / s.v0, (t - s.t0) / (s.t1 - s.t0)) : s.v0 + (s.v1 - s.v0) * (t - s.t0) / (s.t1 - s.t0)); } return v; }
  plan(now, segs, kind) {
    const cur = this.value(now), p = this.p; this.base = cur; this.sg = []; let v = cur;
    try { p.cancelScheduledValues(now); p.setValueAtTime(cur, now); } catch (e) { /* */ }
    for (const g of segs) {
      const t0 = Math.max(g.at, now), t1 = Math.max(t0 + Math.max(g.dur || 0, 0), t0), to = this.exp ? Math.max(g.to, 1e-3) : g.to;
      try { if (t0 > now) p.setValueAtTime(v, t0); if (t1 > t0 + 1e-4) { if (this.exp) p.exponentialRampToValueAtTime(to, t1); else p.linearRampToValueAtTime(to, t1); } else p.setValueAtTime(to, t0); } catch (e) { /* */ }
      this.sg.push({ t0, t1: t1 > t0 + 1e-4 ? t1 : t0, v0: v, v1: to }); v = to;
      if (this.log) this.log({ param: this.name, to: +to.toFixed(4), at: t0, dur: t1 - t0, kind: g.kind || kind || '' });
    }
  }
}

export function createGvMusic(opts = {}) {
  const base = opts.base || '../music/', stemAfter = opts.stemAfter !== undefined ? opts.stemAfter : 2, log = opts.log || null;
  let M = null, starting = null, started = false, paused = false, failed = false, vol = opts.volume !== undefined ? opts.volume : 0.8;
  const trackFactory = opts.trackFactory || null;
  // ---- the director's state (the Godot one, kept: mode, band, tracks, peak, deep, duck, bump) plus the arc
  const D = { mode: 'none', cur: '', age: 0, dwell: 0, peak: 0, down: false, deep: false, band: '', pick: -1, wantKey: '', mixT: 0, duck: 0, bump: 0, curP: null, oldP: null, curG: 0, oldG: 0, curEnv: null, oldEnv: null, oldKey: '',
    stemG: 0, stemWant: 0, trackAsk: {}, funkDuck: 1 };
  const A = { stage: 'pre', preBar0: null, lastCommit: -1, noCommitUntil: -1, busyUntil: -1, q: [], pend: null, clr: false, clrT: 0, lastSnap: -9, prevClarity: 1, prevSharp: 0, dropBar: -1, offT: 0, applied: new Array(9).fill(-1) };
  let factory = null, AU = null, hp = null, lp = null, sm = null; const wired = {};

  // ---- the clock: everything is scheduled on the engine's own audio clock (t0 + bars * 4 beats)
  const tBar = (b) => M.t0 + b * 4 * M.beat;
  const barsNow = () => (M.ctx.currentTime - M.t0) / (4 * M.beat);
  const barS = () => 4 * M.beat;
  const now = () => M.ctx.currentTime;
  const nextBar = () => Math.ceil(barsNow() + LOOK);          // the first bar line far enough ahead to be scheduled exactly
  const gv = (v) => (v < 0.02 ? 0 : dbLin(lerp(-24, 0, Math.pow(v, 0.7))) * 0.85);          // a layer 0..1 -> a stem gain (Godot's mapping)

  function ensure(name) {          // load a stem (once) and route it through the stem group's own filters
    if (!M || wired[name]) return; wired[name] = true; M.load(name); const s = M.stems[name]; if (!s) return;
    if (hp && s.gain && s.gain.disconnect) { try { s.gain.disconnect(); s.gain.connect(hp); } catch (e) { /* */ } }
    AU.stems[name] = new Auto(s.gain.gain, 0, false, 'stem:' + name, log);
  }
  async function start() {
    if (starting) return starting;
    starting = (async () => {
      try {
        const Music = opts.Music || (await import('./music.js')).Music; M = new Music(base); await M.ctx.resume(); M.setVolume(vol);
        factory = trackFactory || browserTrackFactory(M);
        AU = { stems: {} };
        if (M.ctx.createBiquadFilter) {          // the stem group's own high-pass and low-pass, and a master that carries the sound-effect ducking and the bumps: stems -> hp -> lp -> sm -> the music bus (the funk never passes them)
          hp = M.ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = HP_REST; hp.Q.value = 0.7; lp = M.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = LP_OPEN; lp.Q.value = 0.7; sm = M.ctx.createGain(); sm.gain.value = 1;
          hp.connect(lp); lp.connect(sm); sm.connect(M.musicBus);
          AU.hp = new Auto(hp.frequency, HP_REST, true, 'hp', log); AU.lp = new Auto(lp.frequency, LP_OPEN, true, 'lp', log); AU.lpStart = true;
        }
        ensure('ambience'); await M.stems.ambience.ready; M.start(); started = true;          // the ambience is always there: it starts the one clock the other stems join, in step
        M.cutoff(OPEN_CUT, 0.05);
      } catch (e) { failed = true; started = false; }
    })();
    return starting;
  }
  function unlock() { if (M && M.ctx && M.ctx.state === 'suspended' && !paused) M.ctx.resume(); }
  function stop() { if (D.curP) D.curP.stop(); if (D.oldP) D.oldP.stop(); D.curP = D.oldP = null; if (M) { for (const n of STEMS) if (M.stems[n]) M.level(n, 0, 0.1); try { M.ctx.suspend(); } catch (e) { /* */ } } started = false; }
  function setPaused(b) { paused = !!b; if (!M) return; try { if (paused) M.ctx.suspend(); else M.ctx.resume(); } catch (e) { /* */ } for (const p of [D.curP, D.oldP]) if (p) p.pause(paused); }
  function setVolume(v) { vol = v; if (M) M.setVolume(v); }
  const barPos = () => (M && M.started && D.mode === 'stems' && D.stemG > 0.001 ? fposmod(M.beatPos() / 4, 16) : -1);          // bars into the 16-bar loop, as heard (the engine's own beat clock less the output delay)
  const beatPos = () => (M && M.started ? M.beatPos() : 0);
  function wave(ahead) { let b = barPos(); if (b < 0) return 0.5; b = fposmod(b + ahead / BAR_S, 8); return b < 6 ? sstep(0, 1, b / 6) : 1 - (b - 6) / 2; }          // swells over six bars and lets go over two (DhDirector.wave_at)
  const stemsLoaded = () => (M ? STEMS.every((n) => M.stems[n] && M.stems[n].buf) : false);
  const bandFor = (exc) => (exc < 0.3 ? 'sunny' : exc < 0.6 ? 'lift' : 'rush');
  function nextIn(band) { const l = BANDS[band]; D.pick++; let k = l[D.pick % l.length]; if (k === D.cur && l.length > 1) k = l[(D.pick + 1) % l.length]; return k; }
  function askTrack(key) { if (!D.trackAsk[key]) D.trackAsk[key] = factory(base + TRACKS[key].file); return D.trackAsk[key]; }
  const mkEnv = (a, b, t0, dur) => ({ a, b, t0, t1: t0 + Math.max(dur, 1e-3) });
  const envVal = (e, t) => (e ? lerp(e.a, e.b, clamp((t - e.t0) / (e.t1 - e.t0), 0, 1)) : null);
  function playTrack(key, fadeS) {          // a track starts (from silence) and fades in over fadeS; the one that was playing fades out over the same time. Nothing else is ever done to a track.
    const t = now(); if (D.oldP) D.oldP.stop(); D.oldP = D.curP; D.oldG = D.curG; D.oldKey = D.cur; D.oldEnv = D.oldP ? mkEnv(D.curG, 0, t, fadeS) : null;
    D.curP = D.trackAsk[key]; D.curP.play(); D.curG = 0; D.curEnv = mkEnv(0, 1, t, fadeS); D.cur = key; D.mode = 'track'; D.dwell = 0; if (log) log({ track: key, at: t, fade: fadeS });
  }
  function fadeTracksOut(t0, dur) { if (D.curP) D.curEnv = mkEnv(envVal(D.curEnv, t0) !== null ? envVal(D.curEnv, t0) : D.curG, 0, t0, dur); if (D.oldP) D.oldEnv = mkEnv(envVal(D.oldEnv, t0) !== null ? envVal(D.oldEnv, t0) : D.oldG, 0, t0, dur); }
  const sched = (bar, lead, fn, tag) => { A.q.push({ bar, lead, fn, tag }); };          // run fn when the audio clock is `lead` seconds before the start of `bar`
  const trackAudible = () => D.curG > 0.02 || D.oldG > 0.02 || (D.curEnv && envVal(D.curEnv, now()) > 0.02);

  // ---- the layers of the stems, as 0..1 (the Godot meaning: the molecule layers) -> a plan for every stem
  const W = [0.5, 0.8, 1.0, 1.0, 0.6, 0.65, 0.75, 0.75, 0.55];          // the drop: ambience, pulse, bass, drums, piano, guitar, synth, acid, fx (drums and bass heavy)
  function stemsPlan(values, at, dur, kind, extra) {          // values: 9 layer numbers; extra(i) -> more segments appended for stem i (a hole, a restore)
    for (let i = 0; i < 9; i++) { const a = AU.stems[STEMS[i]]; if (!a) continue; const segs = [{ to: gv(values[i]), at, dur, kind }]; if (extra) { const e = extra(i); if (e) segs.push(...e); } a.plan(now(), segs, kind); A.applied[i] = values[i]; }
  }
  const holdsOf = (st) => st.felt || [0, 0, 0, 0, 0, 0];
  const colour = (h, floor) => floor + (1 - floor) * clamp(h * 1.6, 0, 1);
  function dropLayers(bsd, st, E) {          // bars since the drop -> the layers of that bar: patterns on 4-bar phrases, the held molecules colouring which parts are loudest
    const h = holdsOf(st), avg = st.avg !== undefined ? st.avg : h.reduce((a, b) => a + b, 0) / 6, dmt = st.dmt || 0, p = Math.floor(bsd / 4) % 4;
    const col = [1, colour(h[0], 0.6), colour(Math.max(h[5], avg * 1.3), 0.7), colour(Math.max(h[5], avg * 1.3), 0.7), colour(h[1], 0.6), colour(h[4], 0.6), colour(h[2], 0.6), colour(h[3], 0.6), 0.5 + 0.5 * dmt];
    const pat = [1, 1, 1, 1, 1, 1, 1, 1, 1];
    if (p === 1) { pat[7] = 0; pat[5] = 0; pat[8] = 0.7; } else if (p === 2) { pat[4] = 0; pat[6] = 0; pat[8] = 0.8; pat[2] = 1; pat[3] = 1; } else if (p === 3) { pat[8] = 1; }
    return W.map((w, i) => clamp(w * pat[i] * col[i] * E, 0, 1));
  }
  function stage(s) { A.stage = s; if (log) log({ stage: s, at: now(), bar: barsNow() }); }

  // ---- PRE-TRIP
  function preValues(pb) {
    const v = [0.8, 0, 0, 0, 0, 0, 0, 0, 0];
    if (pb >= 8) v[8] = 0.22 + 0.35 * (((pb - 8) % 4) + 1) / 4;          // the fx swell
    if (pb >= 16) v[1] = 0.3 + 0.2 * sstep(16, 48, pb);          // the pulse, filtered by the low-pass that is still nearly shut
    if (pb >= 24) { v[2] = pb % 2 === 0 ? 0.5 : 0; const r = pb % 8, cyc = Math.floor((pb - 24) / 8), rk = clamp(0.45 + 0.18 * cyc, 0.45, 1); v[8] = Math.max(v[8], rk * (0.4 + 0.5 * r / 7)); }          // the bass sub, one bar on one bar off; the riser lifts the fx
    return v;
  }
  const lpPre = (pb) => lerp(LP_SHUT, 5200, sstep(0, 32, pb)) * (pb >= 24 && pb % 8 >= 4 ? 1.6 : 1);
    function commitPre(B) {
    const pb = B - A.preBar0; if (pb < 0) return; const tB = tBar(B), v = preValues(pb), r = pb % 8, riser = pb >= 24;
    const hole = riser && r === 7;          // the last bar of a riser: a one-beat dropout on its 4th beat, before the next entry
    stemsPlan(v, tB, 0.06, 'bar', hole ? () => [{ to: 0, at: tB + 3 * M.beat, dur: 0.03, kind: 'beat' }] : null);
    if (AU.lp) {
      AU.lp.plan(now(), [{ to: lpPre(pb + 1), at: tB, dur: barS(), kind: 'bar' }], 'bar');
      const hpEnd = HP_REST * Math.pow(1400 / HP_REST, ((pb % 8) + 1) / 8);          // the riser: the high-pass reaches 1.4 kHz at the end of the 8th bar
      AU.hp.plan(now(), riser ? (r === 0 ? [{ to: HP_REST, at: tB, dur: 0.005, kind: 'bar' }, { to: hpEnd, at: tB + 0.005, dur: barS() - 0.005, kind: 'bar' }] : [{ to: hpEnd, at: tB, dur: barS(), kind: 'bar' }]) : [{ to: HP_REST, at: tB, dur: 0.05, kind: 'bar' }], 'bar');
    }
    if (riser && r === 0) { const cyc = Math.floor((pb - 24) / 8); sched(B, 0.02, () => { try { M.whoosh(4 * barS(), true); } catch (e) { /* */ } }, 'whoosh'); if (cyc >= 1) sched(B, 0.1, () => { try { M.boom(); } catch (e) { /* */ } }, 'boom'); }          // a long whoosh under every riser, and a boom as each later riser starts
  }

  // ---- TRIP KICKS IN: the stems duck out over a bar, the funk crossfades in on the bar line after
  function startFunk(band, B) {
    const key = D.wantKey || nextIn(band); D.wantKey = key; const tB = tBar(B);
    stage('funk'); A.busyUntil = B + 1 + FUNK_IN_BARS; A.noCommitUntil = B + 1; D.band = band; D.stemWant = 0;
    sched(B, 0.45, () => {
      stemsPlan([0, 0, 0, 0, 0, 0, 0, 0, 0], tBar(B), barS(), 'bar');
      if (AU.lp) { AU.lp.plan(now(), [{ to: LP_OPEN, at: tBar(B + 1), dur: 0.05, kind: 'bar' }], 'bar'); AU.hp.plan(now(), [{ to: HP_REST, at: tBar(B + 1), dur: 0.05, kind: 'bar' }], 'bar'); }
      sched(B, 0.02, () => { try { M.whoosh(barS(), true); } catch (e) { /* */ } }, 'whoosh');
    }, 'funk-duck');
    A.pend = { key, bar: B + 1, fadeS: FUNK_IN_BARS * barS(), boom: true };
  }
  function runPend() {
    const P = A.pend; if (!P) return; const t = tBar(P.bar);
    if (now() >= t - 0.03) {
      const p = askTrack(P.key); if (!p.ready) { if (!p.failed) { P.bar = Math.max(P.bar, nextBar()); } else { A.pend = null; } return; }
      A.pend = null; playTrack(P.key, P.fadeS); D.mode = 'track'; D.stemG = 0; if (P.boom) { try { M.boom(); } catch (e) { /* */ } }
    }
  }

  // ---- CLIMAX: the break, then the drop
  function startBreak(E, st) {
    const D8 = Math.ceil((barsNow() + 3 + LOOK) / 8) * 8, B = D8 - 2, tB = tBar(B), tD = tBar(D8); A.dropBar = D8;
    stage('break'); A.busyUntil = D8; A.noCommitUntil = D8; D.stemWant = 1; D.mode = 'stems'; D.stemG = 1;
    sched(B, 0.45, () => {
      fadeTracksOut(tB, 2 * barS() - 0.1);          // the funk fades out over the break (a fade is all that is ever done to it)
      const fxEnd = gv(1);
      const segFor = (i) => {
        if (i === 0) return [{ to: gv(0.9), at: tB, dur: barS(), kind: 'bar' }, { to: gv(0.9), at: tD - M.beat, dur: 0, kind: 'beat' }, { to: 0, at: tD - M.beat, dur: 0.03, kind: 'beat' }, { to: gv(W[0]), at: tD, dur: 0.02, kind: 'bar' }];
        if (i === 8) return [{ to: gv(0.6), at: tB, dur: barS(), kind: 'bar' }, { to: fxEnd, at: tB + barS(), dur: barS() - M.beat, kind: 'bar' }, { to: 0, at: tD - M.beat, dur: 0.03, kind: 'beat' }, { to: gv(clamp(W[8] * (0.5 + 0.5 * (st.dmt || 0)), 0, 1)), at: tD, dur: 0.02, kind: 'bar' }];
        return [{ to: 0, at: tB, dur: 0, kind: 'bar' }, { to: gv(dropLayers(0, st, E)[i]), at: tD, dur: 0.02, kind: 'bar' }];          // the rest wait in silence and ALL come in together on the drop
      };
      for (let i = 0; i < 9; i++) { const a = AU.stems[STEMS[i]]; if (a) a.plan(now(), segFor(i), 'bar'); A.applied[i] = -1; }
      if (AU.lp) {
        AU.lp.plan(now(), [{ to: LP_SHUT, at: tB, dur: barS(), kind: 'bar' }, { to: 7000, at: tB + barS(), dur: barS() - M.beat, kind: 'bar' }, { to: LP_OPEN, at: tD, dur: 0.01, kind: 'bar' }], 'bar');
        AU.hp.plan(now(), [{ to: HP_REST, at: tB, dur: 0, kind: 'bar' }, { to: HP_REST, at: tB + barS(), dur: 0, kind: 'bar' }, { to: 1500, at: tB + barS(), dur: barS() - M.beat, kind: 'bar' }, { to: HP_REST, at: tD, dur: 0.01, kind: 'bar' }], 'bar');
      }
      sched(B, 0.02, () => { try { M.whoosh(barS(), false); } catch (e) { /* */ } }, 'whoosh-down');
      sched(B + 1, 0.02, () => { try { M.whoosh(barS(), true); } catch (e) { /* */ } }, 'whoosh-up');
      sched(D8, 0.1, () => { try { M.boom(); } catch (e) { /* */ } stage('drop'); A.noCommitUntil = D8; A.dropBar = D8; if (log) log({ drop: D8, at: tD }); }, 'drop');
    }, 'break');
  }

  // ---- CHILL-OUT and WRAP
  function startChill(B) {
    const tB = tBar(B); A.q.length = 0; A.pend = null; stage('chill'); A.busyUntil = B + 3; A.noCommitUntil = B + 3; D.stemWant = 0; D.band = 'chill'; D.wantKey = 'moodless';
    sched(B, 0.45, () => {
      stemsPlan([0, 0, 0, 0, 0, 0, 0, 0, 0], tB, FADE_S, 'bar');
      if (AU.lp) { AU.lp.plan(now(), [{ to: LP_OPEN, at: tB + FADE_S, dur: 0.05, kind: 'tail' }], 'tail'); AU.hp.plan(now(), [{ to: HP_REST, at: tB + FADE_S, dur: 0.05, kind: 'tail' }], 'tail'); }          // (the filters go back once the stems are silent)
      fadeTracksOut(tB, FADE_S);
    }, 'chill-out');
    A.pend = { key: 'moodless', bar: B, fadeS: FADE_S, boom: false };
  }
  function startPre(B) {
    const tB = tBar(B); A.q.length = 0; A.pend = null; stage('pre'); A.preBar0 = B; A.busyUntil = B + 1; A.noCommitUntil = B - 1; A.lastCommit = B - 1; D.mode = 'stems'; D.stemG = 1; D.stemWant = 1; D.wantKey = ''; D.peak = 0; D.down = false; D.deep = false;
    sched(B, 0.45, () => { fadeTracksOut(tB, FADE_S); if (AU.lp) { AU.lp.plan(now(), [{ to: LP_SHUT, at: tB, dur: 0.3, kind: 'bar' }], 'bar'); AU.hp.plan(now(), [{ to: HP_REST, at: tB, dur: 0.05, kind: 'bar' }], 'bar'); } }, 'pre-start');
  }

  // ---- what stage the arc wants (the phase does the arc; the felt average is the fallback when there is no phase, as in Godot)
  function wantStage(st, avg) {
    const phaseGiven = typeof st.phase === 'string', trip = st.tripOn !== undefined ? !!st.tripOn : avg >= 0.03;
    if (avg >= 0.2) D.deep = true; else if (avg < 0.11) D.deep = false;
    D.peak = Math.max(D.peak - 0.003 * (st._dt || 0), avg); if (trip) D.down = false; else if (!phaseGiven && D.peak > 0.2 && avg < D.peak * 0.4) D.down = true;
    const phase = phaseGiven ? st.phase : (st.chill ? 'comedown' : D.deep ? 'peak' : trip ? 'come up' : 'settle');
    if (st.chill || phase === 'comedown') return { stage: 'chill', trip, phase };
    const peakish = phase === 'peak' || phase === 'plateau';
    if (phaseGiven) return { stage: trip ? (peakish ? 'drop' : 'funk') : 'pre', trip, phase };
    return { stage: D.deep ? 'drop' : (trip || D.down ? 'funk' : 'pre'), trip, phase };
  }
  function arcStep(st, avg) {
    const w = wantStage(st, avg), exc = clamp(st.excitement || 0, 0, 1), E = w.phase === 'plateau' ? 0.88 : 1;
    if (w.stage === 'chill') { if (A.stage !== 'chill') startChill(nextBar()); return w; }
    if (A.stage === 'chill') { if (barsNow() >= A.busyUntil - 3 + 0 && !A.pend) { if (w.stage === 'pre') startPre(nextBar()); else if (askTrack(D.wantKey && D.wantKey !== 'moodless' ? D.wantKey : (D.wantKey = nextIn(w.trip ? bandFor(exc) : 'sunny'))).ready) startFunk(bandFor(exc), nextBar()); } return w; }
    if (barsNow() < A.busyUntil - LOOK) return w;          // a transition is under way
    if (A.stage === 'pre') { if (w.stage !== 'pre') { const key = D.wantKey || (D.wantKey = nextIn(bandFor(exc))); if (askTrack(key).ready) startFunk(bandFor(exc), nextBar()); } return w; }
    if (A.stage === 'funk') {
      if (w.stage === 'drop') { if (stemsLoaded() && D.curP) startBreak(E, st); }
      else if (w.stage === 'pre') { A.offT += st._dt || 0; if (A.offT > 8) { A.offT = 0; startPre(nextBar()); } } else A.offT = 0;
      return w;
    }
    if (A.stage === 'drop') { if (w.stage !== 'drop') { const key = D.wantKey && D.wantKey !== 'moodless' ? D.wantKey : nextIn(w.stage === 'funk' ? (D.down ? 'down' : bandFor(exc)) : 'sunny'); D.wantKey = key; if (askTrack(key).ready) startFunk(D.down ? 'down' : bandFor(exc), nextBar()); } }
    return w;
  }

  function commitDrop(B, st, E) {
    const bsd = B - A.dropBar; if (bsd < 0) return; const tB = tBar(B), v = dropLayers(bsd, st, E), p = Math.floor(bsd / 4) % 4, last = bsd % 4 === 3;
    stemsPlan(v, tB, 0.06, 'bar', p === 3 && last ? () => [{ to: 0, at: tB + 3 * M.beat, dur: 0.03, kind: 'beat' }] : null);
    if (AU.lp) AU.lp.plan(now(), [{ to: p === 2 ? 6000 : LP_OPEN, at: tB, dur: barS() * 0.5, kind: 'bar' }], 'bar');
    if (bsd >= 8 && bsd % 8 === 0) sched(B, 0.1, () => { try { M.boom(); } catch (e) { /* */ } }, 'phrase-boom');
  }

  // ---- the picture's moments: clarity (the mix is gated out and slams back) and the sharpen snap (an accent)
  function clarityDrop() {
    if (A.clr || !AU) return; if (A.stage === 'drop') { A.clr = true; A.clrT = 0; const t = now(); for (let i = 1; i < 9; i++) { const a = AU.stems[STEMS[i]]; if (a) a.plan(t, [{ to: 0, at: t, dur: 0.12, kind: 'now' }], 'now'); } if (AU.lp) AU.lp.plan(t, [{ to: 500, at: t, dur: 0.3, kind: 'now' }], 'now'); }
    else if (A.stage === 'funk') { A.clr = true; A.clrT = 0; D.funkDuck = 0.25; }
    if (log) log({ clarity: 'drop', at: now() });
  }
  function claritySnap(st, E) {
    if (!A.clr) return; A.clr = false; A.lastSnap = now(); const tS = M.nextGrid ? M.nextGrid(2) : now() + 0.1;
    if (A.stage === 'drop') { const bsd = Math.max(0, Math.floor(barsNow()) - A.dropBar), v = dropLayers(bsd, st, E); stemsPlan(v, tS, 0.02, 'grid'); if (AU.lp) AU.lp.plan(now(), [{ to: LP_OPEN, at: tS, dur: 0.1, kind: 'grid' }], 'grid'); }
    D.funkDuck = 1; try { M.boom(); } catch (e) { /* */ }
    if (log) log({ clarity: 'snap', at: tS });
  }
  function sharpAccent() {
    if (!AU || now() - A.lastSnap < 1.2 || A.stage === 'chill') return; const tS = M.nextGrid ? M.nextGrid(1) : now() + 0.1;
    try { M.boom(); } catch (e) { /* */ }
    if (A.stage === 'drop' || A.stage === 'pre') { const a = AU.stems.fx; if (a) { const base = A.stage === 'drop' ? gv(A.applied[8] > 0 ? A.applied[8] : 0.5) : gv(0.3); a.plan(now(), [{ to: gv(1), at: tS, dur: 0.02, kind: 'beat' }, { to: base, at: tS + M.beat * 0.5, dur: 0.25, kind: 'grid' }], 'beat'); } }
    if (log) log({ sharp: true, at: tS });
  }

  // st: see the contract at the top
  function tick(dt, st) {
    if (!started || !M || failed) return; D.age += dt; D.dwell += dt; D.bump = Math.max(D.bump - dt * 0.8, 0); if (paused) return;
    st = Object.assign({}, st, { _dt: dt }); const holds = holdsOf(st), avg = st.avg !== undefined ? st.avg : holds.reduce((a, b) => a + b, 0) / 6, exc = clamp(st.excitement || 0, 0, 1);
    if (A.preBar0 === null) { A.preBar0 = Math.ceil(barsNow() + LOOK); A.lastCommit = A.preBar0 - 1; D.mode = 'stems'; D.stemG = 1; D.stemWant = 1; if (log) log({ stage: 'pre', at: now(), bar: A.preBar0 });
      if (AU.lp) AU.lp.plan(now(), [{ to: LP_SHUT, at: now(), dur: 0.01, kind: 'now' }], 'now'); stemsPlan(preValues(0), now(), 1.5, 'now'); }
    if (D.age > stemAfter) { ensure('fx'); ensure('pulse'); ensure('bass'); }
    if (D.age > 15 || st.tripOn || avg >= 0.03) for (const n of ['drums', 'synth', 'acid', 'piano', 'guitar']) ensure(n);          // the rest of the stems come down in the background
    if (D.age > 3 && !D.wantKey && A.stage !== 'chill') { D.wantKey = nextIn(bandFor(exc)); askTrack(D.wantKey); }          // the funk is fetched long before it is needed
    if ((typeof st.u === 'number' && st.u > 0.45) || st.phase === 'plateau' || st.phase === 'peak' || st.chill) askTrack('moodless');          // and so is the chill-out
    // the picture's edges
    if (typeof st.clarityK === 'number') { if (st.clarityK < 0.5 && A.prevClarity >= 0.5) clarityDrop(); else if (st.clarityK >= 0.5 && A.prevClarity < 0.5) claritySnap(st, st.phase === 'plateau' ? 0.88 : 1); A.prevClarity = st.clarityK; }
    if (typeof st.sharp === 'number') { if (st.sharp >= 0.9 && A.prevSharp < 0.5) sharpAccent(); A.prevSharp = st.sharp; }
    if (A.clr) { A.clrT += dt; if (A.clrT > 6) claritySnap(st, 1); }          // (a clarity that never ends is let go after 6 s)
    const w = arcStep(st, avg), E = w.phase === 'plateau' ? 0.88 : 1;
    // the scheduled things (each fires a little before its bar line, so the automation lands exactly on it)
    const t = now(); for (let i = A.q.length - 1; i >= 0; i--) { const e = A.q[i]; if (t >= tBar(e.bar) - e.lead) { A.q.splice(i, 1); e.fn(); } }
    runPend();
    // the per-bar commits
    const b = Math.floor(barsNow() + LOOK);
    if (b > barsNow() + 0.001 && b > A.lastCommit && b > A.noCommitUntil && !A.clr && !A.q.length) { A.lastCommit = b; if (A.stage === 'pre') commitPre(b); else if (A.stage === 'drop') commitDrop(b, st, E); }
    // ---- the mix, ten times a second: the tracks' fades (gain only), the stems' master (the sound-effect duck and the bumps), the output low-pass
    D.mixT += dt;
    if (D.mixT >= 0.1) {
      const d = D.mixT; D.mixT = 0; D.duck = Math.max(D.duck - d * 4, 0); const dk = 1 - 0.28 * D.duck, tt = now(); D.funkDuck = A.clr && A.stage === 'funk' ? D.funkDuck : lerp(D.funkDuck, 1, clamp(d * 3, 0, 1));
      if (D.curP) { const e = envVal(D.curEnv, tt); if (e !== null) D.curG = e; D.curP.setGain(D.curG * D.funkDuck * 0.9 * dk * dbLin(TRACKS[D.cur] ? TRACKS[D.cur].gain : 0)); if (D.curEnv && tt >= D.curEnv.t1 && D.curEnv.b === 0 && D.curG <= 0.001) { D.curP.stop(); D.curP = null; D.curEnv = null; D.curG = 0; } }
      if (D.oldP) { const e = envVal(D.oldEnv, tt); if (e !== null) D.oldG = e; D.oldP.setGain(D.oldG * 0.9 * dk * dbLin(TRACKS[D.oldKey] ? TRACKS[D.oldKey].gain : 0)); if (D.oldG <= 0.001 || (D.oldEnv && tt >= D.oldEnv.t1)) { D.oldP.stop(); D.oldP = null; D.oldEnv = null; D.oldG = 0; } }
      if (sm) sm.gain.setTargetAtTime(dk * (1 + 0.6 * D.bump), tt, 0.08);
      M.cutoff(trackAudible() ? BASE_CUT : OPEN_CUT, trackAudible() ? 0.05 : 0.4);          // the engine's own 3 kHz stage while a track is audible (as it always was), opened for the stems alone
      if (A.stage === 'funk' || A.stage === 'chill') { if (!A.pend && D.mode === 'track' && D.curP) { const l = BANDS[D.band] || []; const ended = D.curP.pos() > D.curP.dur() - FADE_S - 1; const wantBand = A.stage === 'chill' ? 'chill' : (D.down ? 'down' : bandFor(exc)); if (ended || (A.stage === 'funk' && wantBand !== D.band && D.dwell > 40 && !l.includes(D.cur))) { const key = nextIn(A.stage === 'chill' ? 'chill' : wantBand); if (askTrack(key).ready) { D.band = wantBand; A.pend = { key, bar: nextBar(), fadeS: FADE_S, boom: false }; } } } }
    }
  }
  // ---- events (soft notes in key, on the next sixteenth: music.js tone() snaps to A minor pentatonic and caps the gain)
  const safe = (f) => { try { if (M && M.started && !paused) f(); } catch (e) { /* */ } };
  function duck() { D.duck = 1; }
  function onCue(dir) { safe(() => { if (dir > 0) { M.tone(659.3, 0.1, 0.34); setTimeout(() => safe(() => M.tone(880.0, 0.22, 0.34)), 90); } else { M.tone(220.0, 0.3, 0.3, false); M.tone(110.0, 0.3, 0.25, false); } }); }
  function onChain(level) { safe(() => M.tone(LADDER[clamp(Math.floor(level) - 1, 0, 9)], 0.16, 0.3)); }
  function onBump(k) { D.bump = Math.max(D.bump, k === undefined ? 0.35 : k); }          // a moment that deserves a hit: the whole mix swells for a second (DhMusic.bump)
  function onMolecule(id) { onCue(1); onBump(0.45); safe(() => { const i = Math.max(0, MOL_ORDER.indexOf(id)); setTimeout(() => safe(() => M.tone(LADDER[2 + i], 0.3, 0.3)), 220); }); }
  return {
    start, unlock, stop, setPaused, setVolume, tick, duck, onCue, onChain, onBump, onMolecule, wave, barPos, beatPos,
    onClarityDrop: () => safe(clarityDrop), onClaritySnap: () => safe(() => claritySnap({}, 1)), onSharp: () => safe(sharpAccent),
    audio: () => (M ? { ctx: M.ctx, sfxBus: M.sfxBus, music: M } : null), get started() { return started; }, get failed() { return failed; }, get state() { return D; }, get arc() { return A; }, STEMS, MOL_ORDER, CREDITS,
  };
}
