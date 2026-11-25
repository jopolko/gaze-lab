// SYNTHTRACK: simple generated techno loops (WebAudio, no files). Each part of the game gets its own preset (tempo, key, mood).
// A track is a plan of sections: 'soft' (pad and a quiet arpeggio, no kick), 'build' (the kick creeps in, hats speed up), 'heavy' (four on the floor, off-beat bass, claps), 'half' (a lighter kick on 1 and 3).
// The beat grid is known, so no listening is needed: the returned map has the same shape as beatsync.js (bpm, beatLen, t0, down, bars, drops, peaks, kick(j), beatStr(j), dur).
//   startSynth(name, vol) -> Promise<{ map, ctx, pos(), beatsBetween(a,b), level(), pause(), play(), stop() }>
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
export const PRESETS = {
  route0: { bpm: 122, root: 45, scale: [0, 3, 5, 7, 10], prog: [0, 2, 1, 3], wave: 'sawtooth', cut: 900, hat: 8, plan: [['soft', 8], ['build', 4], ['heavy', 12], ['soft', 4], ['build', 4], ['heavy', 8], ['soft', 4]] },
  sugar: { bpm: 108, root: 48, scale: [0, 2, 4, 7, 9], prog: [0, 3, 1, 2], wave: 'triangle', cut: 1500, hat: 8, plan: [['soft', 8], ['build', 4], ['half', 12], ['soft', 4], ['build', 4], ['half', 8], ['soft', 4]] },
  neon: { bpm: 128, root: 43, scale: [0, 2, 3, 5, 7, 8, 10], prog: [0, 5, 3, 4], wave: 'sawtooth', cut: 1200, hat: 16, plan: [['soft', 4], ['build', 4], ['heavy', 12], ['soft', 4], ['build', 4], ['heavy', 16], ['soft', 4]] },
  rack: { bpm: 118, root: 40, scale: [0, 1, 3, 5, 7, 8, 10], prog: [0, 0, 1, 0], wave: 'square', cut: 600, hat: 8, plan: [['soft', 12], ['build', 4], ['heavy', 8], ['soft', 8], ['build', 4], ['heavy', 8], ['soft', 4]] },
  coast: { bpm: 140, root: 41, scale: [0, 3, 5, 7, 10], prog: [0, 3, 2, 4], wave: 'sawtooth', cut: 1400, hat: 16, plan: [['soft', 4], ['build', 4], ['heavy', 16], ['soft', 4], ['build', 4], ['heavy', 12], ['soft', 4]] },
  peaks: { bpm: 100, root: 47, scale: [0, 2, 3, 5, 7, 9, 10], prog: [0, 4, 3, 4], wave: 'triangle', cut: 1100, hat: 8, plan: [['soft', 8], ['build', 4], ['half', 12], ['soft', 8], ['build', 4], ['half', 8]] },
  orchard: { bpm: 88, root: 52, scale: [0, 2, 4, 5, 7, 9, 11], prog: [0, 3, 4, 3], wave: 'sine', cut: 2000, hat: 8, plan: [['soft', 12], ['half', 8], ['soft', 8], ['half', 8]] },
};
export async function startSynth(name, vol = .7) {
  const P = PRESETS[name] || PRESETS.route0, Ctx = window.AudioContext || window.webkitAudioContext, ctx = new Ctx(); try { await ctx.resume(); } catch (e) { }
  const beatLen = 60 / P.bpm, stepDur = beatLen / 4, bars = []; for (const [kind, n] of P.plan) for (let i = 0; i < n; i++) bars.push(kind);
  const nBars = bars.length, nSteps = nBars * 16, nBeats = nBars * 4, dur = nBars * 4 * beatLen, ns = P.scale.length;
  const master = ctx.createGain(); master.gain.value = vol; const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 4; const an = ctx.createAnalyser(); an.fftSize = 1024; master.connect(comp); comp.connect(an); an.connect(ctx.destination);
  const duck = ctx.createGain(); duck.connect(master);          // pad, bass and arpeggio sit on this and dip with each kick
  const echo = ctx.createDelay(1); echo.delayTime.value = stepDur * 3; const fb = ctx.createGain(); fb.gain.value = .35; const ef = ctx.createBiquadFilter(); ef.type = 'lowpass'; ef.frequency.value = 2500; echo.connect(ef); ef.connect(fb); fb.connect(echo); ef.connect(duck);
  const nb = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate), nd = nb.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
  const env = (g, t, a, d, v) => { g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(v, t + a); g.gain.exponentialRampToValueAtTime(.0008, t + a + d); };
  const kick = (t, v) => { const o = ctx.createOscillator(), g = ctx.createGain(); o.frequency.setValueAtTime(150, t); o.frequency.exponentialRampToValueAtTime(46, t + .13); env(g, t, .002, .38, v); o.connect(g); g.connect(master); o.start(t); o.stop(t + .45); const c = ctx.createBufferSource(), cg = ctx.createGain(), cf = ctx.createBiquadFilter(); c.buffer = nb; cf.type = 'highpass'; cf.frequency.value = 3000; env(cg, t, .001, .02, v * .25); c.connect(cf); cf.connect(cg); cg.connect(master); c.start(t); c.stop(t + .05); };
  const duckAt = (t) => { duck.gain.cancelScheduledValues(t); duck.gain.setValueAtTime(.3, t); duck.gain.linearRampToValueAtTime(1, t + stepDur * 3); };
  const noise = (t, len, ftype, f, v, dest) => { const s = ctx.createBufferSource(), g = ctx.createGain(), fl = ctx.createBiquadFilter(); s.buffer = nb; fl.type = ftype; fl.frequency.value = f; env(g, t, .001, len, v); s.connect(fl); fl.connect(g); g.connect(dest || master); s.start(t, Math.random() * .5); s.stop(t + len + .05); };
  const hat = (t, open, v) => noise(t, open ? .16 : .04, 'highpass', 7500, v);
  const clap = (t, v) => { noise(t, .1, 'bandpass', 1500, v); noise(t + .012, .12, 'bandpass', 1800, v * .7); };
  const tone = (t, midi, len, v, type, cut, dest) => { const o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain(); o.type = type; o.frequency.value = mtof(midi); f.type = 'lowpass'; f.frequency.setValueAtTime(cut * 1.8, t); f.frequency.exponentialRampToValueAtTime(cut * .6, t + len); g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(v, t + .01); g.gain.exponentialRampToValueAtTime(.0008, t + len); o.connect(f); f.connect(g); g.connect(dest || duck); o.start(t); o.stop(t + len + .05); };
  const note = (idx, oct) => P.root + 12 * oct + P.scale[((idx % ns) + ns) % ns] + 12 * Math.floor(idx / ns);
  const pad = (t, deg, len, v) => { for (const k of [0, 2, 4]) { for (const det of [-6, 6]) { const o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain(); o.type = 'sawtooth'; o.frequency.value = mtof(note(deg + k, 2)); o.detune.value = det; f.type = 'lowpass'; f.frequency.value = P.cut * .8; g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(v, t + len * .35); g.gain.linearRampToValueAtTime(0, t + len); o.connect(f); f.connect(g); g.connect(duck); o.start(t); o.stop(t + len + .05); } } };
  function sched(sa, t) {
    const s = sa % nSteps, bar = (s / 16) | 0, st = s % 16, kind = bars[bar], deg = P.prog[bar % P.prog.length], heavy = kind === 'heavy', half = kind === 'half', build = kind === 'build', soft = kind === 'soft';
    if (st === 0) pad(t, deg, stepDur * 16, soft ? .035 : .022);
    if (heavy && st % 4 === 0) { kick(t, 1); duckAt(t); }
    if (half && (st === 0 || st === 8)) { kick(t, .8); duckAt(t); }
    if (build && st % 4 === 0) { kick(t, .45 + .35 * (bar - bars.indexOf('build')) / 4); duckAt(t); }
    if ((heavy || half) && st % 4 === 2) tone(t, note(deg, 0), stepDur * 1.6, .22, P.wave === 'sine' ? 'sine' : 'sawtooth', P.cut * .6);
    if (heavy && (st === 4 || st === 12)) clap(t, .35);
    if (heavy || half) { if (st % 4 === 2) hat(t, true, .16); else if (P.hat === 16 && st % 2 === 1) hat(t, false, .08); else if (st % 4 === 0 && P.hat === 16) hat(t, false, .05); }
    if (build) { const ramp = (bar - bars.indexOf('build')) / 4; if (st % 2 === 0) hat(t, false, .07 + .1 * ramp); if (bar === bars.lastIndexOf('build') && st >= 8) hat(t, false, .12); }
    if (soft) { if (st % 8 === 4) hat(t, false, .05); if (st % 2 === 0) { const a = [0, 2, 4, 2][(st / 2 | 0) % 4]; tone(t, note(deg + a, 3), stepDur * 3, .05, P.wave === 'sawtooth' ? 'triangle' : P.wave, P.cut * 1.6, echo); } }
    if (build && st % 4 === 2) tone(t, note(deg + [0, 2, 4, 2][(st / 4 | 0) % 4], 3), stepDur * 2, .05, 'triangle', P.cut * 1.6, echo);
  }
  let nextT = ctx.currentTime + .2, sa = 0; const tStart = nextT, iv = setInterval(() => { while (nextT < ctx.currentTime + .5) { sched(sa, nextT); sa++; nextT += stepDur; } }, 50);
  // the beat map, the same shape the game reads from a track it has listened to
  const kindOfBeat = (j) => bars[((((j % nBeats) + nBeats) % nBeats) / 4) | 0], eOf = { soft: .25, build: .6, half: .8, heavy: 1 }, drops = [], peaks = [], barsOut = bars.map((k, i) => ({ t: i * 4 * beatLen, e: eOf[k] }));
  for (let i = 0; i < nBars; i++) if ((bars[i] === 'heavy' || bars[i] === 'half') && bars[(i + nBars - 1) % nBars] !== bars[i]) { drops.push(i * 4 * beatLen); let j = i; while (j + 1 < nBars && bars[j + 1] === bars[i]) j++; peaks.push(((i + j) / 2 | 0) * 4 * beatLen); }
  const map = { dur, bpm: P.bpm, beatLen, t0: 0, down: 0, bars: barsOut, drops, peaks, name, kick: (j) => { const k = kindOfBeat(j), jb = ((j % 4) + 4) % 4; return k === 'heavy' ? 1 : k === 'half' ? (jb % 2 === 0 ? .8 : 0) : k === 'build' ? .55 : 0; }, beatStr: (j) => (kindOfBeat(j) === 'soft' ? .2 : 1), score: 1 };
  const lat = () => (ctx.outputLatency || ctx.baseLatency || 0), pos = () => Math.max(0, ctx.currentTime - tStart - lat());
  const beatsBetween = (a, b) => { const out = [], L0 = Math.floor(a / dur), L1 = Math.floor(b / dur); for (let L = L0; L <= L1; L++) { const base = L * dur, j0 = Math.max(0, Math.floor((a - base) / beatLen)), j1 = Math.floor((b - base) / beatLen); for (let j = j0; j <= j1; j++) { const t = base + j * beatLen; if (t >= a && t < b && t - base < dur) out.push({ t, id: L * 100000 + j, bar: j % 4 === 0, str: map.beatStr(j) }); } } return out; };
  const buf = new Float32Array(an.fftSize), level = () => { an.getFloatTimeDomainData(buf); let s = 0; for (let i = 0; i < buf.length; i++) s += buf[i] * buf[i]; return Math.sqrt(s / buf.length); };
  return { map, ctx, pos, beatsBetween, level, pause() { return ctx.suspend(); }, play() { return ctx.resume(); }, stop() { clearInterval(iv); try { ctx.close(); } catch (e) { } } };
}
