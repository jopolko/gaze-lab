// MONSTER SOUNDS (owner 2026-11-28: "give all monsters action sounds"). Everything is synthesised here, nothing loaded.
//   createMonSfx(acx, cam) -> { vox(kind, x, y, z, k), wind(level), chew(dt, n, pan), skitter(dt, list), launch(x,y,z), impact(x,y,z) }
// Loops (wind, swarm drone) fade out by themselves unless they are refreshed every frame, so a paused game goes quiet.
export function createMonSfx(acx, cam) {
  const rnd = (a, b) => a + Math.random() * (b - a), clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  let AC = null, BUS = null, NB = null; const ERR = [];
  function ctx() { const ac = acx && acx(); if (!ac) return null; if (ac !== AC) { AC = ac; BUS = ac.createGain(); BUS.gain.value = 1; const cmp = ac.createDynamicsCompressor(); cmp.threshold.value = -14; cmp.ratio.value = 4; BUS.connect(cmp); cmp.connect(ac.destination);
      const n = ac.sampleRate * 2; NB = ac.createBuffer(1, n, ac.sampleRate); const ch = NB.getChannelData(0); for (let i = 0; i < n; i++) ch[i] = Math.random() * 2 - 1; LOOP.wind = null; LOOP.drone = null; } return ac; }
  const noise = (ac) => { const s = ac.createBufferSource(); s.buffer = NB; s.loop = true; return s; };
  // where a sound sits: pan from the camera's right, level from distance
  function where(x, y, z) { try { const c = cam(); if (!c || x == null) return { pan: 0, g: 1 }; const p = c.globalPosition, m = c.getWorldMatrix().m, rx = m[0], rz = m[2], dx = x - p.x, dy = y - p.y, dz = z - p.z, d = Math.hypot(dx, dy, dz), side = (dx * rx + dz * rz) / Math.max(1, Math.hypot(rx, rz));
      return { pan: clamp(side / Math.max(8, d * .7), -.9, .9), g: clamp(1 / (1 + d / 30), .08, 1) }; } catch (e) { return { pan: 0, g: 1 }; } }
  function out(ac, pan, g) { const gn = ac.createGain(); gn.gain.value = g; if (ac.createStereoPanner) { const p = ac.createStereoPanner(); p.pan.value = pan; gn.connect(p); p.connect(BUS); } else gn.connect(BUS); return gn; }
  const env = (gp, t0, a, peak, dec) => { gp.setValueAtTime(0, t0); gp.linearRampToValueAtTime(peak, t0 + a); gp.exponentialRampToValueAtTime(.0005, t0 + a + dec); };
  function osc(ac, type, f0, f1, t0, dur, peak, dest, a = .005) { const o = ac.createOscillator(), g = ac.createGain(); o.type = type; o.frequency.setValueAtTime(f0, t0); if (f1 && f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t0 + dur); env(g.gain, t0, a, peak, dur); o.connect(g); g.connect(dest); o.start(t0); o.stop(t0 + a + dur + .05); return o; }
  function nz(ac, type, f0, f1, q, t0, dur, peak, dest, a = .003) { const s = noise(ac), f = ac.createBiquadFilter(), g = ac.createGain(); f.type = type; f.frequency.setValueAtTime(f0, t0); if (f1 && f1 !== f0) f.frequency.exponentialRampToValueAtTime(f1, t0 + dur); f.Q.value = q; env(g.gain, t0, a, peak, dur); s.connect(f); f.connect(g); g.connect(dest); s.start(t0, Math.random() * 1.5); s.stop(t0 + a + dur + .05); }
  const metal = (ac, f, t0, dur, peak, dest, few) => { for (const [m, k] of (few ? [[1, 1], [2.41, .6]] : [[1, 1], [2.41, .6], [3.93, .4], [5.37, .25]])) osc(ac, 'sine', f * m, f * m * .995, t0, dur * (1.1 - k * .3), peak * k, dest, .001); };

  // ---------------------------------------------------------------- one-shots, each placed in the world
  const KINDS = {
    appear(ac, t, o, k) { osc(ac, 'sawtooth', 140 * k, 520 * k, t, .38, .16, o, .02); nz(ac, 'bandpass', 900, 2600, 3, t, .35, .12, o, .02); for (let i = 0; i < 3; i++) osc(ac, 'square', rnd(1300, 2100) * k, 0, t + .38 + i * .07, .05, .06, o); },          /* a machine booting: servo spin-up, then three chirps */
    tell(ac, t, o, k) { osc(ac, 'square', 660 * k, 0, t, .09, .1, o); osc(ac, 'square', 990 * k, 0, t + .12, .1, .1, o); osc(ac, 'sine', 380 * k, 1500 * k, t, .55, .12, o, .05); },          /* a warning: two beeps and a charging whine */
    clank(ac, t, o, k) { metal(ac, rnd(280, 420) * k, t, .35, .2, o); nz(ac, 'highpass', 2500, 0, .7, t, .04, .25, o); },
    clang(ac, t, o, k) { metal(ac, rnd(620, 760) * k, t, .6, .2, o); nz(ac, 'highpass', 3000, 0, .7, t, .03, .2, o); },
    thud(ac, t, o) { osc(ac, 'sine', 75, 32, t, .32, .5, o); nz(ac, 'lowpass', 420, 120, .7, t, .22, .35, o); },
    hatch(ac, t, o) { for (let i = 0; i < 9; i++) { const ti = t + rnd(0, .5); nz(ac, 'bandpass', rnd(2500, 4500), 0, 6, ti, .025, .2, o); if (Math.random() < .4) metal(ac, rnd(2200, 3400), ti, .05, .04, o); } osc(ac, 'sawtooth', 90, 60, t, .6, .08, o, .05); },
    beep(ac, t, o, k) { osc(ac, 'square', 1700 * k, 0, t, .06, .08, o); osc(ac, 'square', 2260 * k, 0, t + .09, .06, .08, o); osc(ac, 'square', 1700 * k, 0, t + .18, .06, .07, o); },
    growl(ac, t, o, k) { const f = ac.createBiquadFilter(); f.type = 'lowpass'; f.frequency.setValueAtTime(260, t); f.frequency.linearRampToValueAtTime(700, t + .4); f.frequency.linearRampToValueAtTime(220, t + 1); f.connect(o); osc(ac, 'sawtooth', 62 * k, 52 * k, t, 1, .4, f, .08); osc(ac, 'sawtooth', 65 * k, 50 * k, t, 1, .35, f, .08); },
    clack(ac, t, o) { nz(ac, 'bandpass', 2200, 0, 4, t, .03, .3, o); metal(ac, rnd(1800, 2600), t + .01, .06, .06, o); },
    grind(ac, t, o) { nz(ac, 'bandpass', 520, 380, 2, t, .5, .3, o, .04); osc(ac, 'sawtooth', 48, 44, t, .5, .12, o, .04); },
    buzz(ac, t, o, k) { const g = ac.createGain(); g.connect(o); osc(ac, 'sawtooth', 150 * k, 170 * k, t, .7, .1, g, .08); osc(ac, 'sawtooth', 153 * k, 168 * k, t, .7, .08, g, .08); },
    hum(ac, t, o) { osc(ac, 'sine', 55, 52, t, 1.1, .3, o, .25); osc(ac, 'sine', 110, 104, t, 1.1, .12, o, .25); },
    chime(ac, t, o) { osc(ac, 'sine', 1320, 0, t, .9, .1, o); osc(ac, 'sine', 1760, 0, t + .15, .9, .08, o); osc(ac, 'sine', 2640, 0, t + .3, .7, .05, o); },
    swoosh(ac, t, o) { nz(ac, 'bandpass', 500, 2400, 1.5, t, .4, .3, o, .1); },
    zapp(ac, t, o) { osc(ac, 'sawtooth', 120, 40, t, .4, .25, o); nz(ac, 'bandpass', 3000, 900, 2, t, .3, .2, o); },
    swarm(ac, t, o) { for (let i = 0; i < 26; i++) { const ti = t + rnd(0, 1.1); nz(ac, 'bandpass', rnd(1600, 3800), 0, 5, ti, .02, .12, o); } osc(ac, 'sawtooth', 70, 95, t, 1.2, .1, o, .3); osc(ac, 'sawtooth', 71.5, 93, t, 1.2, .09, o, .3); },          /* a wave of spiders arriving: a rush of legs over a rising drone */
    launch(ac, t, o) { osc(ac, 'sine', 95, 38, t, .2, .55, o); nz(ac, 'bandpass', 700, 2800, 1.2, t + .02, .7, .4, o, .02); nz(ac, 'highpass', 4000, 0, .7, t, .05, .3, o); },          /* a missile leaving: ignition thump and a tearing hiss */
    defeat(ac, t, o) { osc(ac, 'sawtooth', 330, 300, t, .35, .16, o, .01); osc(ac, 'sawtooth', 262, 196, t + .32, .9, .18, o, .01); osc(ac, 'sine', 98, 55, t + .3, 1.2, .3, o, .02); nz(ac, 'lowpass', 600, 120, .7, t + .3, .9, .2, o, .05); },          /* a falling 'you lost that one' */
    sting(ac, t, o) { osc(ac, 'sine', 140, 70, t, .22, .22, o); nz(ac, 'bandpass', 2600, 1400, 3, t, .08, .1, o); },          /* soft damage knock */
    impact(ac, t, o) { nz(ac, 'lowpass', 900, 110, .7, t, 1.1, .7, o); osc(ac, 'sine', 60, 28, t, .7, .6, o); },
  };
  let last = {};
  function vox(kind, x, y, z, k = 1, gain = 1) { try { const ac = ctx(); if (!ac || ac.state !== 'running' || !KINDS[kind]) return; const now = ac.currentTime, key = kind + (x == null ? '' : Math.round(x / 6) + ',' + Math.round(z / 6)); if (now - (last[key] || 0) < .12) return; last[key] = now;
      const w = where(x, y, z); KINDS[kind](ac, now + .01, out(ac, w.pan, w.g * gain), k); } catch (e) { if (ERR.length < 20) ERR.push(String(e)); } }

  // ---------------------------------------------------------------- loops (dead man: they fade unless refreshed)
  const LOOP = { wind: null, drone: null };
  const hold = (p, v, now, tc = .06) => { p.cancelScheduledValues(now); p.setTargetAtTime(v, now, tc); p.setTargetAtTime(0, now + .25, .1); };
  let wt = 0;
  function wind(level, dt) { try { const ac = ctx(); if (!ac) return; if (!LOOP.wind) { if (level <= 0) return; const s = noise(ac), f = ac.createBiquadFilter(), f2 = ac.createBiquadFilter(), g = ac.createGain(); f.type = 'bandpass'; f.Q.value = 2; f2.type = 'lowpass'; f2.frequency.value = 3000; g.gain.value = 0; s.connect(f); f.connect(f2); f2.connect(g); g.connect(BUS); s.start(); LOOP.wind = { f, g }; }
      wt += dt || .016; const now = ac.currentTime, L = LOOP.wind, lv = clamp(level, 0, 1);
      L.f.frequency.setTargetAtTime((380 + 520 * lv) * (1 + .35 * Math.sin(wt * .9) + .2 * Math.sin(wt * 2.3 + 1.3) + .1 * Math.sin(wt * 5.1)), now, .08);          /* (higher and brighter the higher you fly, the pitch always wandering) */
      L.f.Q.setTargetAtTime(1.6 + .9 * Math.sin(wt * 1.7), now, .1);
      hold(L.g.gain, lv > 0 ? (.12 + .5 * lv) * (1 + .15 * Math.sin(wt * 3.1)) : 0, now); } catch (e) { if (ERR.length < 20) ERR.push(String(e)); } }
  // the glass being chewed: one little chip per bite, each spider biting a few times a second, so the sound thins out as they go
  function chew(dt, n, panOf) { try { const ac = ctx(); if (!ac || ac.state !== 'running' || n <= 0) return; const exp = Math.min(40, n * 3.2) * dt; let k = Math.floor(exp) + (Math.random() < exp % 1 ? 1 : 0); const now = ac.currentTime;
      while (k-- > 0) { const t = now + .02 + Math.random() * dt, o = out(ac, panOf ? panOf() : rnd(-.8, .8), rnd(.6, 1)), glass = Math.random() < .65;
        if (glass) { nz(ac, 'bandpass', rnd(3200, 7500), 0, rnd(5, 10), t, rnd(.008, .022), rnd(.12, .22), o, .001); if (Math.random() < .3) osc(ac, 'sine', rnd(4200, 7800), 0, t, .03, .05, o, .001); }
        else { nz(ac, 'bandpass', rnd(1400, 2600), 0, 6, t, rnd(.012, .03), .18, o, .001); metal(ac, rnd(900, 1600), t, .05, .04, o, 1); } } } catch (e) { if (ERR.length < 20) ERR.push(String(e)); } }          /* (glass: a high crack; metal: a lower chip with a ring) */
  // the swarm on the road: racing mechanical legs, a tick per footfall, in surges, over an ominous low drone
  let st = 0, surge = 1;
  function skitter(dt, list) { try { const ac = ctx(); if (!ac) return; const now = ac.currentTime; st += dt;
      let w = 0; for (const s of list) w += s.g; if (!LOOP.drone && w > 0) { const f = ac.createBiquadFilter(), g = ac.createGain(), lfo = ac.createOscillator(), lg = ac.createGain(); f.type = 'lowpass'; f.frequency.value = 240; f.Q.value = 3; g.gain.value = 0;
        for (const hz of [43.65, 46.2, 87.3]) { const o = ac.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz; o.connect(f); o.start(); } lfo.frequency.value = 5.5; lg.gain.value = 90; lfo.connect(lg); lg.connect(f.frequency); lfo.start(); f.connect(g); g.connect(BUS); LOOP.drone = { g, f }; }
      if (LOOP.drone) hold(LOOP.drone.g.gain, clamp(w / 6, 0, 1) * .16, now, .3);
      if (ac.state !== 'running' || w <= 0) return; if (Math.random() < dt * .7) surge = rnd(.35, 1.6);          /* (they race in bursts, at random) */
      const exp = Math.min(70, w * 14 * surge) * dt; let k = Math.floor(exp) + (Math.random() < exp % 1 ? 1 : 0);
      while (k-- > 0) { let r = Math.random() * w, s = list[0]; for (const q of list) { r -= q.g; if (r <= 0) { s = q; break; } } const t = now + .02 + Math.random() * dt, o = out(ac, s.pan, s.g * rnd(.6, 1));
        nz(ac, 'bandpass', rnd(1500, 4200), 0, rnd(4, 9), t, rnd(.006, .016), .16, o, .001); if (Math.random() < .25) metal(ac, rnd(2400, 4200), t, .03, .03, o, 1); } } catch (e) { if (ERR.length < 20) ERR.push(String(e)); } }
  return { vox, wind, chew, skitter, launch: (x, y, z) => vox('launch', x, y, z), impact: (x, y, z) => vox('impact', x, y, z), get ctx() { return AC; }, ERR, KINDS: Object.keys(KINDS) };
}
