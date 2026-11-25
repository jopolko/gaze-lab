// BEATSYNC: reads a track, finds its tempo, beat grid, bars, loud and quiet sections and drops, and plays it on a clock the game can read.
//   analyse(AudioBuffer) -> map { dur, bpm, beatLen, t0, down, bars:[{t,e}], drops:[sec], peaks:[sec], beatStr(j) }
//   startBeat(url, vol) -> Promise<{ map, ctx, pos(), pause(), play(), stop(), beatsBetween(a, b) }>
// Nothing here changes the audio (no stretching): it only listens. Tuned for steady-tempo tracks (dance, funk, dnb).
export function analyse(buf) {
  const sr = buf.sampleRate, n = buf.length, nc = buf.numberOfChannels, hop = Math.round(sr * .01), frames = Math.floor(n / hop), HS = hop / sr;
  const chs = []; for (let c = 0; c < nc; c++) chs.push(buf.getChannelData(c));
  const low = new Float32Array(frames), full = new Float32Array(frames), a = 1 - Math.exp(-2 * Math.PI * 160 / sr);
  let y1 = 0, y2 = 0;
  for (let f = 0; f < frames; f++) {
    let sl = 0, sf = 0;
    for (let i = f * hop, e = i + hop; i < e; i++) { let x = 0; for (let c = 0; c < nc; c++) x += chs[c][i]; x /= nc; y1 += a * (x - y1); y2 += a * (y1 - y2); sl += y2 * y2; sf += x * x; }
    low[f] = Math.sqrt(sl / hop); full[f] = Math.sqrt(sf / hop);
  }
  // onset strength: how fast the bass and the whole sound jump up, with the local average taken off so loud passages do not swamp quiet ones
  const raw = new Float32Array(frames); for (let f = 1; f < frames; f++) raw[f] = Math.max(0, low[f] - low[f - 1]) + .5 * Math.max(0, full[f] - full[f - 1]);
  const o = new Float32Array(frames + 2), W = 100; let acc = 0;
  for (let f = 0; f < frames; f++) { acc += raw[f]; if (f >= W) acc -= raw[f - W]; const mean = acc / Math.min(W, f + 1); o[f] = Math.max(0, raw[f] - mean * .8) / (mean + 1e-4); }
  for (let f = 1; f < frames - 1; f++) raw[f] = (o[f - 1] + 2 * o[f] + o[f + 1]) / 4; o.set(raw.subarray(0, frames));
  // tempo and phase: lay a beat grid over the whole track and keep the one that lands on the most onsets
  let best = { s: -1, bpm: 120, ph: 0 };
  for (let bpm = 70; bpm <= 175; bpm += .1) {
    const P = 60 / bpm / HS, nb = Math.floor((frames - 2) / P) - 1; if (nb < 8) continue; const prior = Math.exp(-.5 * Math.pow(Math.log2(bpm / 118) / .5, 2));
    for (let ph = 0; ph < P; ph += 1) { let s = 0; for (let k = 0; k < nb; k++) { const x = ph + k * P, i = x | 0, fr = x - i; s += o[i] * (1 - fr) + o[i + 1] * fr; } s = s / nb * prior; if (s > best.s) best = { s, bpm, ph }; }
  }
  const P = 60 / best.bpm / HS, beatLen = 60 / best.bpm, nBeats = Math.floor((frames - best.ph - 2) / P);
  // the bar line: of the four beats in a bar, the one with the heaviest bass
  const sums = [0, 0, 0, 0]; for (let k = 0; k < nBeats; k++) { const i = Math.round(best.ph + k * P); sums[k % 4] += low[Math.min(frames - 1, i + 2)] - low[Math.max(0, i - 3)]; }
  const down = sums.indexOf(Math.max(...sums)), t0 = best.ph * HS;
  // loudness bar by bar
  const barF = 4 * P, nBars = Math.floor((frames - best.ph) / barF), bars = [], eRaw = []; for (let b = 0; b < nBars; b++) { const f0 = Math.floor(best.ph + (b * 4 + (down % 4)) * P), f1 = Math.min(frames, Math.floor(f0 + barF)); let s = 0; for (let f = f0; f < f1; f++) s += full[f]; eRaw.push(s / Math.max(1, f1 - f0)); }
  const sorted = [...eRaw].sort((p, q) => p - q), ref = sorted[Math.floor(sorted.length * .95)] || 1; for (let b = 0; b < nBars; b++) bars.push({ t: t0 + (b * 4 + down) * beatLen, e: Math.min(1.2, eRaw[b] / ref) });
  // drops: a bar much louder than the bars just before it; peaks: the loudest bars of a stretch
  const drops = [], peaks = [];
  for (let b = 4; b < bars.length; b++) { const prev = (bars[b - 1].e + bars[b - 2].e + bars[b - 3].e + bars[b - 4].e) / 4; if (bars[b].e - prev > .22 && prev < bars[b].e * .8 && (!drops.length || bars[b].t - drops[drops.length - 1] > 8 * 4 * beatLen * .5)) drops.push(bars[b].t); }
  for (let b = 4; b < bars.length - 4; b++) { let mx = true; for (let d = -4; d <= 4; d++) if (bars[b + d].e > bars[b].e) mx = false; if (mx && bars[b].e > .85 && (!peaks.length || bars[b].t - peaks[peaks.length - 1] > 16 * beatLen)) peaks.push(bars[b].t); }
  const beatStr = (j) => { const i = Math.round((best.ph + j * P)); return i >= 0 && i < frames ? Math.min(1, o[i] / 3) : 0; };
  // kick(j): how hard the bass hits on beat j, 0 (none: the instrumental parts) to 1 (a full kick), against the track's own heavy beats
  const kv = []; for (let k = 0; k < nBeats; k++) { const i = Math.round(best.ph + k * P); kv.push(Math.max(0, low[Math.min(frames - 1, i + 3)] - low[Math.max(0, i - 2)])); }
  const ks = kv.slice().sort((p, q) => p - q), kref = ks[Math.floor(ks.length * .85)] || 1e-6;
  const kick = (j) => { const v = kv[((j % kv.length) + kv.length) % kv.length] / kref; const x = Math.max(0, Math.min(1, (v - .3) / .5)); return x * x * (3 - 2 * x); };
  return { dur: buf.duration, bpm: best.bpm, beatLen, t0, down, bars, drops, peaks, beatStr, kick, score: best.s };
}
export async function startBeat(url, vol = .8, opts = {}) {
  const Ctx = window.AudioContext || window.webkitAudioContext, ctx = new Ctx(); try { await ctx.resume(); } catch (e) { }
  const buf = await ctx.decodeAudioData(await (await fetch(url)).arrayBuffer()), map = analyse(buf);
  const g = ctx.createGain(); g.gain.value = vol; g.connect(ctx.destination); const src = ctx.createBufferSource(); src.buffer = buf; src.loop = true; src.connect(g);
  const tStart = ctx.currentTime + .15; src.start(tStart);
  const lat = () => (ctx.outputLatency || ctx.baseLatency || 0);
  const pos = () => Math.max(0, ctx.currentTime - tStart - lat());          // seconds into the music as it is heard, counting every pass of the loop
  // beats (absolute time, counting loops) between a and b: { t, j, bar:boolean, str }
  const beatsBetween = (a, b) => {
    const out = [], L0 = Math.floor(a / map.dur), L1 = Math.floor(b / map.dur);
    for (let L = L0; L <= L1; L++) { const base = L * map.dur; let j0 = Math.max(0, Math.floor((a - base - map.t0) / map.beatLen)), j1 = Math.floor((b - base - map.t0) / map.beatLen); for (let j = j0; j <= j1; j++) { const t = base + map.t0 + j * map.beatLen; if (t >= a && t < b && t - base < map.dur) out.push({ t, id: L * 100000 + j, bar: ((j - map.down) % 4 + 4) % 4 === 0, str: map.beatStr(j) }); } }
    return out;
  };
  return { map, ctx, pos, beatsBetween, pause() { return ctx.suspend(); }, play() { return ctx.resume(); }, stop() { try { src.stop(); ctx.close(); } catch (e) { } } };
}
