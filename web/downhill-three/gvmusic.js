// GV MUSIC: the Godot game's music director (godot/scripts/DhDirector.gd, update() and the mix, ported line for line) for the wide level, on the existing sample-accurate stem engine (music.js).
// Real recordings only, nothing synthesised for the music: the Alien Warfare stems and the three funk tracks (used exactly as they are, only their playback volume is set). A missing file is silence.
//
//   before the first molecule   the stems' ambience alone (every other part sits at nothing until its molecule is held)
//   from the first molecule     (avg felt >= 0.03) a funk track chosen by how hard the run is going (sunny < 0.3 <= lift < 0.6 <= rush), crossfaded over 5 s
//   deeper (avg >= 0.2)         the stems take over: ambience always, and each molecule brings its own part: mescaline pulse, DOM piano, 2C-B synth, 2C-E acid, 2C-T-2 guitar,
//                               2C-T-7 bass and drums (also bass and drums at 1.3 x the average), the fx layer comes with dmt. Parts come in and go out only on every second bar (3.75 s)
//   after the peak, wearing off the comedown track (funk) until the next molecule
//   back below avg 0.11         the funk returns
// Every sound effect ducks the music by 28 % for a moment (duck()), so it sits on top without being louder. Sound effects here are notes in key on the next sixteenth (music.js tone()).
//
// CREDITS (show them somewhere, the licences ask for it; everything here is NON-COMMERCIAL):
//   Alien Warfare Stems, Kamihamiha, CC BY-NC 3.0, ccmixter.org/files/Kamihamiha/60882
//   Funk it!, SunnyScy, CC BY-NC-SA 4.0, freemusicarchive.org/music/sunnyscy/single/funk-it-1/
//   Quirky Funk, butterflystudio, CC BY-NC-ND 4.0, freemusicarchive.org/music/butterflystudio/quirky-funk/quirky-funk/
//   Funk Express, butterflystudio, CC BY-NC-ND 4.0, freemusicarchive.org/music/butterflystudio/funky-grooves/funk-express/
//
// HOW gv.js USES IT (a few lines):
//   import { createGvMusic, CREDITS } from './gvmusic.js';
//   const GM = createGvMusic({ base: '../music/' });                       // nothing is loaded or played yet
//   // on the first user gesture (the tap that starts the game): GM.start();   (it creates the AudioContext, so it MUST come from a tap or key)
//   // every frame while playing:  GM.tick(dt, { felt: [6 numbers 0..1], excitement: 0..1, chain, airborne, speed01 });
//   // events: GM.onMolecule(id) on a molecule, GM.onChain(level) on a chain link, GM.onCue(+1 or -1) good or bad moment, GM.onBump(.45) a big moment (ramp blast, rail end), GM.duck() on every sound effect
//   // pause: GM.setPaused(true/false).  mute / volume: GM.setVolume(0..1).  for effects that breathe with the music: GM.wave(aheadSeconds), GM.beatPos()
//   // To share the audio graph (recommended): gv.js's SFX should use GM.audio() -> { ctx, sfxBus } instead of its own AudioContext, so effects sit in the same compressor and low-pass as the music.

const STEMS = ['ambience', 'pulse', 'bass', 'drums', 'piano', 'guitar', 'synth', 'acid', 'fx'];
const MOL_ORDER = ['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'];
const TRACKS = {
  funk_it: { file: 'funk_it.ogg', gain: -1.8 }, quirky_funk: { file: 'quirky_funk.ogg', gain: -7.2 }, funk_express: { file: 'funk_express.ogg', gain: -8.9 },
};
const BANDS = { sunny: ['funk_it', 'quirky_funk'], lift: ['funk_express', 'quirky_funk'], rush: ['funk_express'], down: ['funk_it', 'quirky_funk'] };
const BPM = 128, FADE_S = 5, BAR_S = 4 * 60 / BPM;
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
];

// the default way to play a long funk track: the file is downloaded first (chosen once, then waited for while it downloads, as in Godot's _fetch) and played from an <audio> element through the music bus,
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

export function createGvMusic(opts = {}) {
  const base = opts.base || '../music/', stemAfter = opts.stemAfter !== undefined ? opts.stemAfter : 2;
  let M = null, starting = null, started = false, paused = false, failed = false, vol = opts.volume !== undefined ? opts.volume : 0.8;
  const trackFactory = opts.trackFactory || null;
  // ---- the director's state, one to one with DhDirector.gd
  const D = { mode: 'none', cur: '', age: 0, dwell: 0, peak: 0, down: false, deep: false, band: '', pick: -1, wantKey: '', mixT: 0, duck: 0, bump: 0,
    curP: null, oldP: null, curG: 0, oldG: 0, stemG: 0, stemWant: 0, sv: new Array(9).fill(0), lq: new Array(9).fill(0), lastBar: -1, firstQ: true, stemsAsked: false, trackAsk: {}, lastSt: {} };
  let factory = null;

  async function start() {
    if (starting) return starting;
    starting = (async () => {
      try {
        const Music = opts.Music || (await import('./music.js')).Music; M = new Music(base); await M.ctx.resume(); M.setVolume(vol);
        factory = trackFactory || browserTrackFactory(M);
        await M.load('ambience'); M.start(); started = true;          // the ambience is always there: it starts the one clock the other stems join, in step
      } catch (e) { failed = true; started = false; }
    })();
    return starting;
  }
  function unlock() { if (M && M.ctx && M.ctx.state === 'suspended' && !paused) M.ctx.resume(); }
  function stop() { if (D.curP) D.curP.stop(); if (D.oldP) D.oldP.stop(); D.curP = D.oldP = null; if (M) { for (const n of STEMS) M.level(n, 0, 0.1); try { M.ctx.suspend(); } catch (e) { /* */ } } started = false; }
  function setPaused(b) { paused = !!b; if (!M) return; try { if (paused) M.ctx.suspend(); else M.ctx.resume(); } catch (e) { /* */ } for (const p of [D.curP, D.oldP]) if (p) p.pause(paused); }
  function setVolume(v) { vol = v; if (M) M.setVolume(v); }
  const barPos = () => (M && M.started && D.mode === 'stems' && D.stemG > 0.001 ? fposmod(M.beatPos() / 4, 16) : -1);          // bars into the 16-bar loop, as heard (the engine's own beat clock less the output delay)
  const beatPos = () => (M && M.started ? M.beatPos() : 0);
  function wave(ahead) { let b = barPos(); if (b < 0) return 0.5; b = fposmod(b + ahead / BAR_S, 8); return b < 6 ? sstep(0, 1, b / 6) : 1 - (b - 6) / 2; }          // swells over six bars and lets go over two (DhDirector.wave_at)
  const stemsLoaded = () => (M ? STEMS.every((n) => M.stems[n] && M.stems[n].buf) : false);
  const bandFor = (exc) => (exc < 0.3 ? 'sunny' : exc < 0.6 ? 'lift' : 'rush');
  function nextIn(band) { const l = BANDS[band]; D.pick++; let k = l[D.pick % l.length]; if (k === D.cur && l.length > 1) k = l[(D.pick + 1) % l.length]; return k; }
  function askTrack(key) { if (!D.trackAsk[key]) D.trackAsk[key] = factory(base + TRACKS[key].file); return D.trackAsk[key]; }
  function playTrack(key) {
    if (D.oldP) D.oldP.stop(); D.oldP = D.curP; D.oldG = D.curG; D.oldKey = D.cur; D.curP = D.trackAsk[key]; D.curP.play(); D.curG = 0; D.cur = key; D.mode = 'track'; D.dwell = 0;
  }

  // st: { felt: [6 x 0..1] (the six molecules as felt, Godot's _mbody / 6), avg (optional, else the mean), dmt 0..1, excitement 0..1, chain, airborne, speed01 }
  function tick(dt, st) {
    if (!started || !M || failed) return; D.age += dt; D.dwell += dt; D.bump = Math.max(D.bump - dt * 0.8, 0);
    const holds = st.felt || [0, 0, 0, 0, 0, 0], avg = st.avg !== undefined ? st.avg : holds.reduce((a, b) => a + b, 0) / 6, exc = clamp(st.excitement || 0, 0, 1), dmt = st.dmt || 0;
    if (paused) return;
    D.peak = Math.max(D.peak - 0.003 * dt, avg); const trip = avg >= 0.03;
    if (avg >= 0.2) D.deep = true; else if (avg < 0.11) D.deep = false;
    if (trip) D.down = false; else if (D.peak > 0.2 && avg < D.peak * 0.4) D.down = true;
    if (D.age > stemAfter && !D.stemsAsked) { D.stemsAsked = true; for (const n of STEMS) M.load(n); }          // the stems come down in the background once the run is going
    // ---- what should be playing
    let wantMode = D.deep ? 'stems' : (trip || D.down ? 'track' : 'none'); if (wantMode === 'none') wantMode = 'stems';          // before the first molecule: the ambience alone
    let wantBand = D.down ? 'down' : bandFor(exc);
    const ready = stemsLoaded();
    if (wantMode === 'stems' && !ready && !(!trip && !D.down && M.stems.ambience && M.stems.ambience.buf)) { wantMode = (trip || D.down) ? 'track' : 'none'; wantBand = 'sunny'; }          // (the ambience alone may start before the rest has arrived: nothing else is wanted yet)
    if (wantMode === 'stems') { if (D.mode !== 'stems') { D.mode = 'stems'; D.cur = 'stems'; } D.stemWant = 1; }
    else {
      D.stemWant = 0; if (D.mode === 'stems' && D.stemG < 0.02) D.mode = 'none';
      let needNew = D.mode !== 'track' && wantMode === 'track';
      if (D.mode === 'track' && wantMode === 'track') { const l = BANDS[D.band] || []; const ended = D.curP && D.curP.pos() > D.curP.dur() - FADE_S - 1; if (ended || (wantBand !== D.band && D.dwell > 40 && !l.includes(D.cur))) needNew = true; }
      if (needNew) { if (!D.wantKey) D.wantKey = nextIn(wantBand); const p = askTrack(D.wantKey); if (p.ready) { D.band = wantBand; const k = D.wantKey; D.wantKey = ''; playTrack(k); } }
    }
    // ---- the mix, ten times a second
    D.mixT += dt;
    if (D.mixT >= 0.1) {
      const d = D.mixT; D.mixT = 0; D.duck = Math.max(D.duck - d * 4, 0); const step = d / FADE_S, dk = 1 - 0.28 * D.duck;
      if (D.mode === 'track' && D.curP) D.curG = wantMode === 'track' ? Math.min(D.curG + step, 1) : Math.max(D.curG - step * 1.4, 0);
      if (D.oldP) { D.oldG = Math.max(D.oldG - step, 0); D.oldP.setGain(D.oldG * 0.9 * dk * dbLin(TRACKS[D.oldKey] ? TRACKS[D.oldKey].gain : 0)); if (D.oldG <= 0) { D.oldP.stop(); D.oldP = null; } }
      if (D.curP) { D.curP.setGain(D.curG * 0.9 * dk * dbLin(TRACKS[D.cur] ? TRACKS[D.cur].gain : 0)); if (wantMode === 'stems' && D.mode === 'stems') { D.curG = Math.max(D.curG - step * 1.4, 0); if (D.curG <= 0.001) { D.curP.stop(); D.curP = null; } } }          // (once the funk has faded out under the stems it is stopped: Godot leaves it playing silently, a phone would rather not)
      D.stemG = moveToward(D.stemG, D.stemWant, step * 1.2);
      const lv = [1.0, holds[0], Math.max(holds[5], avg * 1.3), Math.max(holds[5], avg * 1.3), holds[1], holds[4], holds[2], holds[3], dmt];          // ambience, pulse (mescaline), bass and drums (2C-T-7), piano (DOM), guitar (2C-T-2), synth (2C-B), acid (2C-E), fx (dmt)
      const bp = barPos();
      if (bp >= 0) { const bi = Math.floor(bp); if (D.firstQ || (bi !== D.lastBar && bi % 2 === 0)) { D.lq = lv.slice(); D.firstQ = false; } D.lastBar = bi; }          // parts come in and go out on bar lines, every second bar
      else { D.firstQ = true; D.lq = lv.slice(); }
      const grp = D.stemG * 0.85 * dk * (1 + 0.6 * D.bump);
      for (let i = 0; i < 9; i++) {
        D.sv[i] = lerp(D.sv[i], clamp(D.lq[i], 0, 1), clamp(d * 1.6, 0, 1));
        const sdb = D.sv[i] < 0.02 ? -80 : lerp(-24, 0, Math.pow(D.sv[i], 0.7));
        M.level(STEMS[i], sdb <= -79 ? 0 : clamp(dbLin(sdb) * grp, 0, 1.2), 0.12);
      }
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
    audio: () => (M ? { ctx: M.ctx, sfxBus: M.sfxBus, music: M } : null), get started() { return started; }, get failed() { return failed; }, get state() { return D; }, STEMS, MOL_ORDER, CREDITS,
  };
}
