# MAKE ENGINE: builds musicengine.js (the game's music) from musiclab.html, so the lab stays the one place the music is made and tuned.
#   python tools/make_engine.py      (run from web/babylon after any change to the lab)
# It takes the lab's engine code (everything before "/* ---------- controls */"), unhooks it from the lab's page, and adds window.ME, the game's handle.
import re, os
here = os.path.dirname(os.path.abspath(__file__)); B = os.path.dirname(here) + '/'
s = open(B + 'musiclab.html', encoding='utf8').read()
js = re.findall(r'<script>(.*?)</script>', s, re.S)[0]
core = js.split('/* ---------- controls */')[0]
def r(a, b):
    global core
    assert core.count(a) == 1, (core.count(a), a[:80])
    core = core.replace(a, b)
r("try { Tone.setContext(new Tone.Context({ latencyHint: 'playback', lookAhead: .2 })); } catch (e) { }", '')
core = re.sub(r"let SEED = \(\(\) => \{.*?\}\)\(\);[^\n]*", 'let SEED = 1;', core, count=1)
r("document.getElementById('seed').textContent = SEED; drawSecs(); info(); }", '}')
core = re.sub(r"function info\(extra\) \{.*?\n", 'function info() { }\n', core, count=1, flags=re.S)
core = re.sub(r"function drawSecs\(\) \{.*?\n", 'function drawSecs() { }\n', core, count=1, flags=re.S)
r("const TR = () => +document.getElementById('tr').value / 100, EN = () => +document.getElementById('en').value / 100;", "let ME_TR = .5, ME_EN = .8; const TR = () => ME_TR, EN = () => ME_EN;")
API = r'''
/* ---------- THE GAME'S HANDLE (window.ME). The level's preset picks the style, tempo and blend; your saved tracks for that level (and the curated ones below)
   are played first, so a level opens on a track someone chose; otherwise a fresh seed. The game moves the mood: a dose (riser, hook), RUSH and fights (harder),
   the afterglow (softer, floatier). */
const CURATED = { };          /* level -> seeds picked by ear in the lab (filled in as tracks are chosen) */
let loopId = null;
window.ME = {
  on: false, base: null,
  /* PRELOAD: called while the level loads (before any tap), so the instruments are built, the samples decoded and the reverb made before the first frame:
     the tap then only starts the clock, and the music starts with the level */
  preload(o) { if (this.pre) return this.pre; o = o || {}; this.opts = o;
    try { if (!S && Tone.getContext().latencyHint !== 'playback') Tone.setContext(new Tone.Context({ latencyHint: 'playback', lookAhead: o.lookAhead || .2 })); else if (o.lookAhead) Tone.getContext().lookAhead = o.lookAhead; } catch (e) { }          /* the game asks for more look-ahead: its frames can stall while it builds shaders, and the notes must already be planned */
    if (!S) build();
    LV = o.level && LVLP[o.level] ? o.level : null; STYLE = o.style || (LV ? LVLP[LV][1] : 'techno'); if (LV) { ME_TR = LVLP[LV][3] / 100; ME_EN = LVLP[LV][4] / 100; } if (o.tr !== undefined) ME_TR = o.tr; if (o.en !== undefined) ME_EN = o.en; if (o.trAdd) ME_TR = Math.max(0, Math.min(1, ME_TR + o.trAdd)); if (o.enMul) ME_EN = Math.max(.15, Math.min(1, ME_EN * o.enMul));          /* the Frequency's faders override the level's blend */
    const mine = rdT0().filter((t) => t.level === LV && t.style === STYLE).map((t) => t.seed), pool = (CURATED[LV] || []).concat(mine);
    SEED = o.seed || (pool.length ? pool[Math.floor(Math.random() * pool.length)] : Math.floor(Math.random() * 1e9)); step = 0; lastSec = -1; makeTrack(); need(T.kind);
    if (o.strong && T.kind !== 'acid') { const g = T.secs.find((x) => x.n === 'GROOVE' || x.n === 'DROP'); if (g) step = g.b0 * 16; }          /* a strong start: straight into the full groove */
    this.pre = (async () => { await Tone.loaded(); await S.ready(); })(); return this.pre; },
  async start(o) { if (this.on || this.starting) return; this.starting = true;
    try { await Tone.start(); } catch (e) { }          /* first, inside the tap: unlock the audio */
    await this.preload(o);
    Tone.Transport.bpm.value = T.bpm; Tone.Transport.swing = swingOf(); Tone.Transport.swingSubdivision = '16n';
    if (loopId === null) loopId = Tone.Transport.scheduleRepeat(tick, '16n'); this.on = true; this.starting = false; this.base = { tr: ME_TR, en: ME_EN };
    if (this.paused) { try { Tone.getContext().rawContext.suspend(); } catch (e) { } } else Tone.Transport.start('+0.05');          /* paused while it was loading: it waits for the resume */
    if (!this.wd) this.wd = setInterval(() => { const c = Tone.getContext(); if (ME.on && !ME.paused && c.state !== 'running') c.resume(); }, 1000); },
  /* pause: the clock stops and the whole audio context is suspended, so held pads, tails and loops stop at once (and resume where they were) */
  pause(b) { this.paused = !!b; if (!this.on) return; try { if (b) { Tone.Transport.pause(); Tone.getContext().rawContext.suspend(); } else { Tone.getContext().resume(); Tone.Transport.start(); } } catch (e) { } },
  dose() { if (this.on) doseBar = Math.floor(step / 16) + 1; },
  set(tr, en) { if (tr !== undefined) ME_TR = tr; if (en !== undefined) ME_EN = en; this.base = { tr: ME_TR, en: ME_EN }; },
  restyle(style, level) { if (!this.on) return; STYLE = style || STYLE; LV = level === undefined ? LV : level; SEED = Math.floor(Math.random() * 1e9); step = 0; lastSec = -1; makeTrack(); Tone.Transport.bpm.rampTo(T.bpm, .5); Tone.Transport.swing = swingOf(); try { if (S.atm) S.atm.stop(); } catch (e) { } need(T.kind); },
  stop() { try { Tone.Transport.stop(); S.pad.releaseAll(); if (S.drone) S.drone.releaseAll(); if (S.atm) S.atm.stop(); if (S.brk) S.brk.forEach((p) => p.stop()); if (S.rnOn) { S.rn.stop(); S.rnOn = false; } } catch (e) { } this.on = false; },
  chords() { return T ? chordNames() : ''; },
  next() { if (!this.on) return; SEED = Math.floor(Math.random() * 1e9); step = 0; lastSec = -1; makeTrack(); Tone.Transport.bpm.rampTo(T.bpm, .5); Tone.Transport.swing = swingOf(); try { if (S.atm) S.atm.stop(); } catch (e) { } need(T.kind); },
  mood(m) { const b = this.base || { tr: ME_TR, en: ME_EN }; if (m === 'glow') { ME_TR = Math.min(1, b.tr + .35); ME_EN = b.en * .45; } else if (m === 'rush' || m === 'fight') { ME_TR = b.tr * .7; ME_EN = 1; } else { ME_TR = b.tr; ME_EN = b.en; } },
  beatPos() { return this.on ? Tone.Transport.ticks / Tone.Transport.PPQ : 0; },
  volume(db) { try { Tone.getDestination().volume.value = db; } catch (e) { } },          /* (getDestination: Tone.Destination is the first context's, stale after setContext) */
  render: (o) => renderOffline(o),
  get track() { return T; }, get seed() { return SEED; },
};
'''
out = '/* MUSIC ENGINE for the game: GENERATED from musiclab.html by tools/make_engine.py (edit the lab, then rebuild). Needs Tone.js 14.8.49 loaded first. */\n(() => {\n' + core + API + '\n})();\n'
open(B + 'musicengine.js', 'w', encoding='utf8').write(out)
print('musicengine.js', len(out), 'bytes')
