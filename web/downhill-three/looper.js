// A SEAMLESS LOOP FOR SHORT TRACKS: the track is decoded once and played on the Web Audio clock, and each pass overlaps the next by a short crossfade (1.4 s by default), so the end melts into the start instead of a gap
// or a click. The first pass starts at a random point so the intro is never the same twice. It returns an object with pause() and play() so it can stand in for an audio element.
//   startLoop(url, volume, { xfade }) -> Promise<{ pause, play, ctx }>
// preloadLoop(url): fetch and decode the track in the background at page load (a suspended context may decode), so the music is ready the moment it is wanted
export function preloadLoop(url) { const Ctx = window.AudioContext || window.webkitAudioContext; const ctx = new Ctx(); const p = fetch(url).then((r) => r.arrayBuffer()).then((b) => ctx.decodeAudioData(b)); p.catch(() => { }); return { ctx, p }; }
export async function startLoop(url, vol = .8, o = {}) {
  const Ctx = window.AudioContext || window.webkitAudioContext; const ctx = o.pre ? o.pre.ctx : new Ctx(); try { await ctx.resume(); } catch (e) { }
  const buf = o.pre ? await o.pre.p : await ctx.decodeAudioData(await (await fetch(url)).arrayBuffer());
  const master = ctx.createGain(); master.gain.setValueAtTime(0, ctx.currentTime); master.gain.linearRampToValueAtTime(vol, ctx.currentTime + .8); master.connect(ctx.destination);
  const D = buf.duration - (o.trim || 0), X = Math.min(o.xfade || 1.4, D / 4); const lg = (m) => { try { (window.__dm || (() => { }))('MUSIC ' + m); } catch (e) { } }; lg('loop ready: ctx ' + ctx.state + ', length ' + D.toFixed(1) + ' s, activation ' + (navigator.userActivation ? navigator.userActivation.hasBeenActive : 'n/a')); setTimeout(() => lg('after 1.5 s: ctx ' + ctx.state), 1500); setTimeout(() => lg('after 4 s: ctx ' + ctx.state), 4000);
  let first = true, nextStart = ctx.currentTime + .05; const passes = [];          /* (each pass: when it starts and where in the song; pos() reads the song position as heard, for beat sync) */
  const schedule = () => {
    const off = first ? Math.random() * Math.max(0, D - X * 3) * .7 : 0, len = D - off, src = ctx.createBufferSource(), g = ctx.createGain(); src.buffer = buf; src.connect(g); g.connect(master);
    const t0 = nextStart, t1 = t0 + len;
    if (first) g.gain.setValueAtTime(1, t0); else { g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(1, t0 + X); }
    g.gain.setValueAtTime(1, Math.max(t0 + X, t1 - X)); g.gain.linearRampToValueAtTime(0, t1);
    src.start(t0, off); src.stop(t1 + .05); passes.push({ t0, off }); if (passes.length > 4) passes.shift(); nextStart = t1 - X; first = false;
  };
  schedule(); const iv = setInterval(() => { while (nextStart < ctx.currentTime + 6) schedule(); }, 1000);
  const pos = () => { const now = ctx.currentTime - (ctx.outputLatency || ctx.baseLatency || 0); let p = passes[0]; for (const q of passes) if (q.t0 <= now) p = q; return p ? Math.max(0, p.off + now - p.t0) : 0; };
  return { ctx, buf, pos, pause() { return ctx.suspend(); }, play() { return ctx.resume(); }, stop() { clearInterval(iv); try { ctx.close(); } catch (e) { } } };
}
