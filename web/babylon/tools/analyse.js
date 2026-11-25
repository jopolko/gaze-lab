/* ANALYSE: measures an offline render from the music lab, so the mix can be judged without ears. Load it into musiclab.html (dev only):
     const s = document.createElement('script'); s.src = 'tools/analyse.js'; document.head.appendChild(s);   then   await __an('techno', 4242, 8)
   peak / clip: anything over 0.99 is a clipped sample.  sub/mid/hi: band loudness (dBFS).  kickLow / kickLaptop: how much louder the low band
   (under 120 Hz) and the laptop band (150-900 Hz, what small speakers can play) are on the beat than between beats: 10 dB+ is a kick you can hear. */
window.__an = async (style, seed, secs, from) => {
  const r = await window.__lab.renderOffline({ style, seed, secs: secs || 10, from });
  const b = r.buf.get(), sr = b.sampleRate, ch = b.getChannelData(0), N = ch.length;
  let peak = 0, clip = 0, ss = 0; for (let i = 0; i < N; i++) { const a = Math.abs(ch[i]); if (a > peak) peak = a; if (a > .99) clip++; ss += ch[i] * ch[i]; }
  const band = async (type) => { const oc = new OfflineAudioContext(1, N, sr), src = oc.createBufferSource(), bb = oc.createBuffer(1, N, sr); bb.copyToChannel(ch, 0); src.buffer = bb; let node = src; for (const [t, fr] of type) { const q = oc.createBiquadFilter(); q.type = t; q.frequency.value = fr; node.connect(q); node = q; } node.connect(oc.destination); src.start(); return (await oc.startRendering()).getChannelData(0); };
  const rms = (x, a, z) => { let s = 0; for (let i = a; i < z; i++) s += x[i] * x[i]; return Math.sqrt(s / Math.max(1, z - a)); }, db = (v) => +(20 * Math.log10(v + 1e-9)).toFixed(1);
  const lo = await band([['lowpass', 120]]), lap = await band([['highpass', 150], ['lowpass', 900]]), hi = await band([['highpass', 5000]]), mid = await band([['highpass', 300], ['lowpass', 3000]]);
  const beat = 60 / r.bpm, W = Math.floor(.05 * sr); let on = 0, off = 0, lon = 0, loff = 0, n = 0;
  for (let t = 1; t + beat < N / sr - .2; t += beat) { const a = Math.floor(t * sr), h = Math.floor((t + beat / 2) * sr); on += rms(lo, a, a + W); off += rms(lo, h, h + W); lon += rms(lap, a, a + W); loff += rms(lap, h, h + W); n++; }
  window.__lastBuf = r.buf;
  return { style, seed, bpm: r.bpm, chords: r.chords, peak: +peak.toFixed(3), clip, rmsDb: db(Math.sqrt(ss / N)), subDb: db(rms(lo, 0, N)), midDb: db(rms(mid, 0, N)), hiDb: db(rms(hi, 0, N)), kickLowDb: +(db(on / n) - db(off / n)).toFixed(1), kickLaptopDb: +(db(lon / n) - db(loff / n)).toFixed(1) };
};
window.__batch = (list, secs) => { window.__res = []; (async () => { for (const [s, sd] of list) { try { window.__res.push(JSON.stringify(await window.__an(s, sd, secs || 8))); } catch (e) { window.__res.push(s + ' ERR ' + String(e).slice(0, 200)); } } window.__res.push('DONE'); })(); return 'started'; };
