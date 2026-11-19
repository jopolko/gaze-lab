// THE MUSIC ENGINE (loaded on demand, the first time the game starts). Real recorded stems (Alien Warfare Stems by Kamihamiha, CC BY-NC 3.0, ccmixter.org/files/Kamihamiha/60882: nine 16-bar loops at 128 BPM in A minor)
// played on ONE Web Audio clock, so everything is sample-accurate and in step:
//   - every stem is exactly 30.000 s (16 bars), started on the same clock with the loop end set to 30.000 s, so they can never drift apart; a stem that arrives late is started mid-loop at exactly the right offset;
//   - the drum stem's kick is on every beat from time 0 (measured), so the beat clock IS the audio clock: beatPos() is what the game flashes its visuals on (less the output latency of the device);
//   - sound effects are tiny synthesised notes snapped to A minor pentatonic and started on the next sixteenth note of the same clock, so they are always in key and always on the beat.
// Stems are fetched and decoded one at a time (about 400 KB each), the ones that are needed first first.
export const STEMS = ['ambience', 'pulse', 'bass', 'drums', 'piano', 'guitar', 'synth', 'acid', 'fx'];
const PCS = [9, 0, 2, 4, 7];          // A C D E G
export class Music {
  constructor(base) {
    this.base = base; const AC = window.AudioContext || window.webkitAudioContext; this.ctx = new AC({ latencyHint: 'interactive' }); const c = this.ctx;
    this.stems = {}; this.beat = 60 / 128; this.len = 30; this.t0 = 0; this.started = false; this.vol = 0.8;
    this.master = c.createGain(); this.master.gain.value = this.vol;
    this.lp = c.createBiquadFilter(); this.lp.type = 'lowpass'; this.lp.frequency.value = 3000; this.lp.Q.value = 0.6;
    this.comp = c.createDynamicsCompressor(); this.comp.threshold.value = -16; this.comp.knee.value = 12; this.comp.ratio.value = 3; this.comp.attack.value = 0.01; this.comp.release.value = 0.2;
    this.musicBus = c.createGain(); this.sfxBus = c.createGain(); this.sfxBus.gain.value = 0.9;
    this.musicBus.connect(this.lp); this.lp.connect(this.comp); this.sfxBus.connect(this.comp); this.comp.connect(this.master); this.master.connect(c.destination);
  }
  load(name) {
    if (this.stems[name]) return this.stems[name].ready;
    const c = this.ctx, s = this.stems[name] = { buf: null, gain: c.createGain(), src: null, level: 0 }; s.gain.gain.value = 0; s.gain.connect(this.musicBus);
    s.ready = (async () => { const ab = await (await fetch(this.base + 'stem_' + name + '.ogg')).arrayBuffer(); s.buf = await c.decodeAudioData(ab); if (this.started) this._attach(name); })().catch(() => { /* a missing stem is silence */ });
    return s.ready;
  }
  start() { if (this.started) return; this.started = true; this.t0 = this.ctx.currentTime + 0.15; for (const n in this.stems) if (this.stems[n].buf) this._attach(n); }
  _attach(name) {
    const s = this.stems[name]; if (s.src || !s.buf) return; const c = this.ctx, src = c.createBufferSource(); src.buffer = s.buf; src.loop = true; src.loopStart = 0; src.loopEnd = this.len; src.connect(s.gain);
    const when = Math.max(c.currentTime + 0.05, this.t0), off = (((when - this.t0) % this.len) + this.len) % this.len; src.start(when, off); s.src = src;          // a late stem joins mid-loop, in step
  }
  level(name, v, tc = 0.35) { const s = this.stems[name]; if (!s) return; s.level = v; s.gain.gain.setTargetAtTime(v, this.ctx.currentTime, tc); }
  cutoff(f, tc = 0.25) { this.lp.frequency.setTargetAtTime(f, this.ctx.currentTime, tc); }
  setVolume(v) { this.vol = v; this.master.gain.setTargetAtTime(v, this.ctx.currentTime, 0.05); }
  latency() { return (this.ctx.outputLatency || 0) + (this.ctx.baseLatency || 0); }
  beatPos() { return this.started ? (this.ctx.currentTime - this.latency() - this.t0) / this.beat : 0; }          // beats since the start, as heard NOW (the clock less the device's output delay)
  nextGrid(div = 4) { const g = this.beat / div, now = this.ctx.currentTime + 0.012; return this.t0 + Math.ceil((now - this.t0) / g) * g; }          // the next sixteenth (div 4)
  snap(f) { const m = 69 + 12 * Math.log2(f / 440); let best = m, bd = 99; for (let k = Math.floor(m) - 7; k <= Math.ceil(m) + 7; k++) { if (PCS.includes(((k % 12) + 12) % 12)) { const d = Math.abs(k - m); if (d < bd) { bd = d; best = k; } } } return 440 * Math.pow(2, (best - 69) / 12); }
  tone(f, dur, gain, quantize = true) {          // a soft note in key, on the next sixteenth (or at once for a hit that must be felt now)
    const c = this.ctx, when = quantize && this.started ? this.nextGrid(4) : c.currentTime + 0.005, fr = this.snap(f), g = Math.min(0.16, (gain || 0.1) * 0.9), d = Math.max(0.12, dur || 0.3);
    const o1 = c.createOscillator(), o2 = c.createOscillator(), v = c.createGain(), lp = c.createBiquadFilter(); o1.type = 'triangle'; o2.type = 'sine'; o1.frequency.value = fr; o2.frequency.value = fr * 2.003; lp.type = 'lowpass'; lp.frequency.value = 2600;
    v.gain.setValueAtTime(0.0001, when); v.gain.linearRampToValueAtTime(g, when + 0.006); v.gain.exponentialRampToValueAtTime(0.0008, when + d); const m2 = c.createGain(); m2.gain.value = 0.3; o1.connect(v); o2.connect(m2); m2.connect(v); v.connect(lp); lp.connect(this.sfxBus);
    o1.start(when); o2.start(when); o1.stop(when + d + 0.05); o2.stop(when + d + 0.05);
  }
  whoosh(dur = 1.4, up = true) {          // a noise sweep for the tunnel dive
    const c = this.ctx, when = c.currentTime + 0.01, n = Math.floor(c.sampleRate * dur), b = c.createBuffer(1, n, c.sampleRate), x = b.getChannelData(0); for (let i = 0; i < n; i++) x[i] = Math.random() * 2 - 1;
    const src = c.createBufferSource(), bp = c.createBiquadFilter(), v = c.createGain(); src.buffer = b; bp.type = 'bandpass'; bp.Q.value = 1.2; bp.frequency.setValueAtTime(up ? 200 : 6000, when); bp.frequency.exponentialRampToValueAtTime(up ? 6000 : 200, when + dur);
    v.gain.setValueAtTime(0.0001, when); v.gain.linearRampToValueAtTime(0.22, when + dur * 0.7); v.gain.linearRampToValueAtTime(0.0001, when + dur); src.connect(bp); bp.connect(v); v.connect(this.sfxBus); src.start(when);
  }
}
