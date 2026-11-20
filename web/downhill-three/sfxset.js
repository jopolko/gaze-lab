// THE SOUND SET: every effect the Godot game fires (Game.sfx(...)), rebuilt as the same soft procedural sounds. A literal port of godot/scripts/AudioHooks.gd: its _tone (a sine gliding f0 to f1 with a second and third harmonic, a gentle attack, an exponential decay),
// _air (noise through two low-pass stages), _mixp (sum, tanh-limited), _cat (one after another), at its 22050 Hz, with every recipe (frequencies, durations, volumes, attacks, decays, harmonics) copied from the source. All pitches are A minor pentatonic, the key of the music.
// Short effects only; no music. Soft by design: sine-based, slow attacks, and the whole bus is low-passed at 3200 Hz.
//
// USE (gv.js):   import { createSfx } from './sfxset.js';
//                const SFX = createSfx(() => ac(), SFXG);          // ac() returns the AudioContext (as in gv.js), SFXG is the gain node every effect goes into
//                SFX.preload();                                     // optional: builds the buffers one a tick after the game is up (otherwise each is built the first time it plays)
// Method names are Godot's: pop squawk squeak bonk whoosh yeet thwup boing honk hurt boom coin gong thwack bell crowd buff_boost buff_shield buff_mult powerup levelup loot explosion kaboom sproing boing2 stretch snap splat zap rumble blip pad_boost
//                cue_good cue_bad launch rail_on land, lad(0..9) the glint ladder, mol(0..5) the molecule chimes, glint() (a ladder rung that climbs on each call and resets after a pause), blower_on / blower_off (a noise loop).
// With `toon` on (Godot's default) three names are swapped for the bigger ones, exactly as AudioHooks does: boom -> explosion, coin -> blip, boing -> sproing.
// ALIASES so the existing gv.js calls keep working: thwack gong hurt stretch snap boing land (same name), pick = loot, orb = glint, pad = pad_boost, blast = boom + snap (what Godot fires at a ramp lip), shield = buff_shield, grindOn / grindOff / grindSpeed(v) (the rail grind loop).
// play(name, { pan, gain, pitch }) plays any name; names lists them all. Voice limit 28 as in Godot; the pitch is varied by +-5% on every play as Godot does.

const RATE = 22050, MAX_VOICES = 28, SFX_GAIN = Math.pow(10, 3 / 20);          // Godot's SFX_GAIN_DB = +3 dB (the soft sounds are quieter than the old harsh ones, this brings them back over the music)
const TOON_MAP = { boom: 'explosion', coin: 'blip', boing: 'sproing' }, FALLBACK = { explosion: 'boom', kaboom: 'boom', stretch: 'powerup', snap: 'pop', boing2: 'boing', splat: 'bonk', zap: 'squeak', rumble: 'boom', blip: 'coin', sproing: 'boing' };
const TAU = Math.PI * 2;

// ---- the synthesis primitives, as in AudioHooks.gd (Float32 in -1..1 instead of int16)
function tone(f0, f1, dur, vol, att = .012, dec = 2.5, h2 = 0, h3 = 0, extra = []) {
  const n = Math.floor(RATE * dur), out = new Float32Array(n); let phase = 0, sx = 0; for (const e of extra) sx += e[1]; const norm = 1 / (1 + h2 + h3 + sx);
  for (let i = 0; i < n; i++) {
    const t = i / RATE, u = i / n; phase += TAU * f0 * Math.pow(Math.max(f1, 1) / Math.max(f0, 1), u) / RATE;
    let sm = Math.sin(phase) + h2 * Math.sin(2 * phase) + h3 * Math.sin(3 * phase); for (const e of extra) sm += e[1] * Math.sin(phase * e[0]);
    const env = Math.exp(-dec * u * 5) * Math.min(1, t / Math.max(att, .002)) * Math.min(1, (dur - t) / .01);
    out[i] = Math.max(-1, Math.min(1, sm * norm * env * vol));
  }
  return out;
}
function air(dur, lp0, lp1, vol, att = .05, dec = 1.5) {
  const n = Math.floor(RATE * dur), out = new Float32Array(n); let a = 0, b = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE, u = i / n, c = lp0 + (lp1 - lp0) * u; a += ((Math.random() * 2 - 1) - a) * c; b += (a - b) * c;
    const gain = 1 / Math.max(Math.sqrt(c / (2 - c)) * .58, .02), env = Math.exp(-dec * u * 5) * Math.min(1, t / Math.max(att, .002)) * Math.min(1, (dur - t) / .01);
    out[i] = Math.max(-1, Math.min(1, b * gain * .35 * env * vol));
  }
  return out;
}
function mixp(parts) { let n = 0; for (const p of parts) n = Math.max(n, p.length); const out = new Float32Array(n); for (let i = 0; i < n; i++) { let v = 0; for (const p of parts) if (i < p.length) v += p[i]; out[i] = Math.max(-1, Math.min(1, Math.tanh(v * .9))); } return out; }
function cat(parts) { let n = 0; for (const p of parts) n += p.length; const out = new Float32Array(n); let o = 0; for (const p of parts) { out.set(p, o); o += p.length; } return out; }

// ---- every recipe, copied from AudioHooks._ready and _build_new_voices
const R = {
  squawk: () => tone(392, 329.6, .22, .4, .015, 2.5, .25),
  pop: () => mixp([tone(329.6, 130, .12, .5, .004, 3), tone(659.3, 659.3, .07, .12, .006, 3)]),
  squeak: () => tone(659.3, 784, .16, .25, .012, 2, .15),
  bonk: () => mixp([tone(196, 82, .22, .6, .004, 3), air(.12, .05, .02, .25, .004, 3)]),
  whoosh: () => air(.4, .02, .2, .55, .07, 1.6),
  yeet: () => tone(220, 440, .35, .32, .03, 1.8, .15),
  thwup: () => tone(220, 110, .12, .55, .005, 3),
  boing: () => tone(196, 392, .38, .4, .015, 1.8, .2),
  honk: () => tone(220, 220, .28, .32, .02, 1.6, .3, .12),
  hurt: () => mixp([tone(220, 165, .32, .4, .01, 2.2, .15), tone(110, 82, .3, .4, .01, 2.5)]),
  boom: () => mixp([tone(90, 45, .55, .75, .006, 2.2), air(.5, .03, .01, .4, .006, 2)]),
  coin: () => cat([tone(659.3, 659.3, .07, .34, .006, 2, .3, .1), tone(880, 880, .22, .34, .006, 3, .3, .1)]),
  gong: () => tone(110, 108, 1.2, .55, .02, 1.4, .3, 0, [[2.76, .3], [5.4, .15]]),
  thwack: () => mixp([tone(250, 100, .15, .5, .004, 3), air(.08, .1, .03, .3, .003, 3)]),
  bell: () => tone(880, 880, .7, .4, .008, 2.2, 0, 0, [[2.76, .25], [5.4, .1]]),
  crowd: () => air(.9, .03, .08, .35, .2, 1.2),
  buff_boost: () => mixp([air(.35, .02, .22, .4, .05, 1.4), tone(440, 880, .3, .3, .03, 1.6, .2)]),
  buff_shield: () => cat([tone(440, 440, .08, .32, .008, 1, .25), tone(523.3, 523.3, .08, .32, .008, 1, .25), tone(659.3, 659.3, .3, .32, .008, 2, .25)]),
  buff_mult: () => cat([tone(523.3, 523.3, .07, .3, .008, 1, .2), tone(587.3, 587.3, .07, .3, .008, 1, .2), tone(659.3, 659.3, .07, .3, .008, 1, .2), tone(784, 784, .3, .3, .008, 2, .2)]),
  powerup: () => mixp([tone(440, 880, .3, .3, .03, 1.4, .2), tone(660, 1320, .3, .12, .05, 1.8)]),
  levelup: () => cat([tone(440, 440, .1, .3, .008, 1, .25), tone(523.3, 523.3, .1, .3, .008, 1, .25), tone(659.3, 659.3, .1, .3, .008, 1, .25), tone(880, 880, .4, .3, .008, 2, .25)]),
  loot: () => cat([tone(659.3, 659.3, .08, .32, .006, 1, .3), tone(880, 880, .08, .32, .006, 1, .3), tone(1047, 1047, .28, .32, .006, 2.5, .3)]),
  explosion: () => mixp([tone(100, 35, .9, .8, .006, 1.8), air(.8, .04, .01, .55, .006, 1.8), tone(55, 40, .9, .5, .01, 1.4)]),
  kaboom: () => mixp([tone(70, 30, 1.5, .85, .008, 1.5), air(1.4, .03, .01, .6, .008, 1.4), tone(45, 32, 1.5, .5, .01, 1.2)]),
  sproing: () => tone(196, 587.3, .5, .42, .015, 1.6, .2),
  boing2: () => tone(587.3, 165, .5, .42, .012, 1.6, .2),
  stretch: () => mixp([tone(130, 523.3, .5, .3, .05, 1.2, .15), air(.5, .02, .12, .15, .08, 1.2)]),
  snap: () => mixp([air(.06, .25, .08, .4, .002, 3.5), tone(784, 587.3, .06, .25, .003, 3)]),
  splat: () => mixp([tone(150, 60, .35, .55, .006, 2.4), air(.3, .08, .02, .35, .006, 2.4)]),
  zap: () => tone(784, 330, .22, .28, .01, 2, .25),
  rumble: () => mixp([tone(55, 46, 1.3, .6, .06, 1), air(1.3, .015, .01, .4, .08, 1)]),
  blip: () => cat([tone(659.3, 659.3, .05, .26, .008, 1.2, .25), tone(880, 880, .12, .26, .008, 3, .25)]),          // the target tick: E5 then A5
  pad_boost: () => mixp([air(.75, .02, .3, .55, .08, 1.3), tone(220, 440, .75, .32, .06, 1.2, .2), tone(82, 55, .4, .55, .01, 2)]),
  cue_good: () => cat([tone(659.3, 659.3, .08, .34, .01, 1.2, .25), tone(880, 880, .22, .34, .01, 2.5, .25)]),
  cue_bad: () => mixp([tone(220, 165, .3, .4, .01, 2, .2), tone(110, 82, .3, .35, .01, 2.2)]),
  launch: () => mixp([air(.45, .02, .2, .45, .04, 1.4), tone(220, 440, .4, .22, .04, 1.6, .15)]),
  rail_on: () => mixp([tone(880, 784, .12, .28, .006, 2.5, .3), air(.1, .12, .05, .3, .004, 2.5)]),
  land: () => mixp([tone(110, 55, .3, .7, .006, 2.2), air(.18, .05, .02, .35, .004, 2.5)]),
};
const LADDER = [440, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.5, 1568];          // the glint ladder: one rung higher each time up A C D E G
LADDER.forEach((f, i) => { R['lad' + i] = () => tone(f, f, .16, .3, .006, 2.5, .2); });
const MOLN = [523.25, 587.33, 659.25, 783.99, 880, 1046.5];          // a chime for each molecule, C5 D5 E5 G5 A5 C6
MOLN.forEach((f, i) => { R['mol' + i] = () => mixp([tone(f, f, .7, .4, .008, 1.6, .3, .1), tone(f * 2, f * 2, .5, .12, .008, 2.2)]); });

export function createSfx(audioCtxProvider, destination, opts = {}) {
  const O = Object.assign({ toon: true, lowpass: 3200, gain: 1 }, opts);
  const LIS = { set: false, x: 0, y: 0, z: 0, yaw: 0 }; const cache = {}; let voices = 0, bus = null, busCtx = null, ladStep = 0, ladT = 0, loopSrc = null, grind = null;
  const ctx = () => { const a = audioCtxProvider && audioCtxProvider(); if (a && a !== busCtx) { busCtx = a; bus = a.createGain(); bus.gain.value = O.gain * SFX_GAIN; let last = bus; if (O.lowpass) { const lp = a.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = O.lowpass; bus.connect(lp); last = lp; } last.connect(destination || a.destination); } return a; };
  function buffer(name, a) { if (cache[name]) return cache[name]; const make = R[name]; if (!make) return null; const data = make(), b = a.createBuffer(1, data.length, RATE); b.copyToChannel(data, 0); return (cache[name] = b); }
  function resolve(name) { if (O.toon) name = TOON_MAP[name] || name; else name = FALLBACK[name] || name; return R[name] ? name : null; }
  function play(name, o = {}) {
    const a = ctx(); if (!a) return; const nm = resolve(name); if (!nm || voices >= MAX_VOICES) return; const b = buffer(nm, a); if (!b) return;
    let pitchR = .95 + Math.random() * .1; o = Object.assign({}, o);          // 2D: the pitch varies by +-5%
    if (o.at && LIS.set) {          // AudioHooks._on_sfx with a world position: AudioStreamPlayer3D, unit_size 12, max_distance 90, pitch_scale 0.9..1.15; here a 1/(1+d/12) falloff, nothing past 90 m, and a pan from where it is
      const dx = o.at[0] - LIS.x, dy = (o.at[1] || 0) - LIS.y, dz = o.at[2] - LIS.z, d = Math.hypot(dx, dy, dz); if (d > 90) return;
      o.gain = (o.gain === undefined ? 1 : o.gain) / (1 + d / 12); pitchR = .9 + Math.random() * .25; if (o.pan === undefined) o.pan = Math.max(-1, Math.min(1, (dx * Math.cos(LIS.yaw) + dz * Math.sin(LIS.yaw)) / Math.max(d, 1)));
    }
    const s = a.createBufferSource(); s.buffer = b; s.playbackRate.value = (o.pitch || 1) * pitchR; let node = s;
    if (o.gain !== undefined && o.gain !== 1) { const g = a.createGain(); g.gain.value = o.gain; node.connect(g); node = g; }
    if (o.pan && a.createStereoPanner) { const p = a.createStereoPanner(); p.pan.value = Math.max(-1, Math.min(1, o.pan)); node.connect(p); node = p; }
    node.connect(bus); voices++; s.onended = () => { voices = Math.max(0, voices - 1); }; s.start();
  }
  const api = { play, names: Object.keys(R).concat(['blower_on', 'blower_off']), toon: O.toon, set toonMode(v) { O.toon = !!v; } };
  for (const name of Object.keys(R)) api[name] = (o) => play(name, o);
  api.lad = (i, o) => play('lad' + Math.max(0, Math.min(9, i | 0)), o); api.mol = (i, o) => play('mol' + Math.max(0, Math.min(5, i | 0)), o);
  api.glint = (o) => { const now = performance.now(); if (now - ladT > 1400) ladStep = 0; ladT = now; api.lad(ladStep, o); ladStep = Math.min(ladStep + 1, 9); };          // a ladder rung that climbs each time and starts over after a pause
  api.blower_on = () => { const a = ctx(); if (!a || loopSrc) return; const n = RATE, d = new Float32Array(n); let lp = 0; for (let i = 0; i < n; i++) { lp = lp + ((Math.random() * 2 - 1) - lp) * .25; d[i] = lp * .6; } const b = a.createBuffer(1, n, RATE); b.copyToChannel(d, 0); const s = a.createBufferSource(); s.buffer = b; s.loop = true; const g = a.createGain(); g.gain.value = Math.pow(10, -12 / 20); s.connect(g); g.connect(bus); s.start(); loopSrc = { s, g }; };
  api.blower_off = () => { if (loopSrc) { try { loopSrc.s.stop(); } catch (e) { } loopSrc = null; } };
  // aliases for the calls gv.js already makes
  api.pick = (o) => play('loot', o); api.orb = (o) => api.glint(o); api.pad = (o) => play('pad_boost', o); api.shield = (o) => play('buff_shield', o);
  api.blast = (o) => { play('boom', o); play('snap', o); };          // what Godot fires at the lip of a ramp
  api.grindOn = () => { const a = ctx(); if (!a || grind) return; const n = a.sampleRate, b = a.createBuffer(1, n, a.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; const s = a.createBufferSource(); s.buffer = b; s.loop = true; const fl = a.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.value = 2200; fl.Q.value = 3; const g = a.createGain(); g.gain.value = .22; s.connect(fl); fl.connect(g); g.connect(bus); s.start(); grind = { s, g, fl }; };
  api.grindSpeed = (v) => { if (grind) grind.fl.frequency.value = 1800 + v * 14; };
  api.grindOff = () => { if (grind) { try { grind.g.gain.setTargetAtTime(0, busCtx.currentTime, .05); grind.s.stop(busCtx.currentTime + .3); } catch (e) { } grind = null; } };
  api.listener = (x, y, z, heading) => { LIS.set = true; LIS.x = x; LIS.y = y; LIS.z = z; LIS.yaw = heading || 0; };          // where the player is, so a sound given { at: [x, y, z] } is placed
  // THE WIND (DhDirector._wind_make / _wind_mix; Godot has it off unless ?wind): a 4 s loop of noise through two gentle low-passes with the rumble taken out and a breathing swell (3 cycles), loudness rising with speed and opening up in the air
  let wind = null, windG = 0; const windRng = (() => { let a = 4242 >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; })();
  api.windStart = () => { const a = ctx(); if (!a || wind) return; const sr = 22050, N = sr * 4, arr = new Float32Array(N); let lp1 = 0, lp2 = 0, hp = 0; for (let i = 0; i < N; i++) { const w = windRng() * 2 - 1; lp1 += (w - lp1) * .2; lp2 += (lp1 - lp2) * .2; hp += (lp2 - hp) * .03; arr[i] = (lp2 - hp) * (.75 + .25 * Math.sin(TAU * i / N * 3)); }
    const c = sr / 2; for (let i = 0; i < c; i++) { const k = i / c; arr[i] = arr[i] * k + arr[N - c + i] * (1 - k); } const n = N - c; let pk = .001; for (let i = 0; i < n; i++) pk = Math.max(pk, Math.abs(arr[i]));
    const buf = a.createBuffer(1, n, sr), d = buf.getChannelData(0); for (let i = 0; i < n; i++) d[i] = arr[i] / pk; const src = a.createBufferSource(); src.buffer = buf; src.loop = true; const g = a.createGain(); g.gain.value = 0; src.connect(g); g.connect(bus); src.start(); wind = { src, g }; };
  api.windUpdate = (spd01, air, paused, dt) => { if (!wind) return; const want = paused ? 0 : Math.max(0, Math.min(.8, (spd01 - .15) * 1.1)) * (air ? 1.5 : 1), rate = (air ? 1.6 : .6) * dt; windG = windG < want ? Math.min(want, windG + rate) : Math.max(want, windG - rate); wind.g.gain.value = windG < .01 ? 0 : windG * Math.pow(10, -23 / 20); };
  api.windStop = () => { if (wind) { try { wind.src.stop(); } catch (e) { } wind = null; windG = 0; } };
  api.preload = () => { const a = ctx(); if (!a) return; const list = Object.keys(R); let i = 0; const step = () => { if (i < list.length) { buffer(list[i++], a); setTimeout(step, 0); } }; step(); };          // one buffer a tick, so nothing hitches
  return api;
}
