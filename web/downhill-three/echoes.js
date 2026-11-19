// ASTRAL ECHOES, a literal port of the echo half of Godot's _trail_fx_tick (RunRig.gd, ECHO_N = 4).
// Godot: "four faint coloured copies of where the board was a moment ago hang behind it, each a little smaller and a little further round the rainbow". The rules, copied:
//   * the board's position is recorded every 0.12 s into a history of at most 16 entries (newest first);
//   * echo i (0..3) sits at history index (i + 1) * 3, i.e. 0.36, 0.72, 1.08, 1.44 s ago, lifted 0.9 m, as a sphere of radius 0.55 squashed to (0.8, 1.5, 0.8) and shrunk by (1 - 0.14 i);
//   * its alpha is 0.30 * _tf_on * (1 - i / 4), hidden below 0.01 or when the history is not that long yet; its colour is HSV( fract(age * 0.15 + 0.13 i), 0.85, 1.0 ); additive;
//   * _tf_on is the same switch as the carve trail: a molecule dose over 0.08, or a boost running, eased with 1 - exp(-2.5 dt).
// FIRST PERSON: in Godot the camera follows the board from behind, so the echoes hang in view just behind it. gv.js is first person (the camera IS the board), so an echo 0.36 to 1.44 s back
// is 20 to 140 m BEHIND the camera and cannot be seen. So this port keeps Godot's rule exactly and adds one thing: `lift` and `lateral` options place each echo's ghost beside the path instead of on it
// (default: `fan: true` spreads the four echoes sideways to the left and right of the lane at their own past z, alternately, so they are visible in the periphery when you look back or turn); the picture
// pass's tracer ghosts already give the "where you were a moment ago" feel on screen in first person. With a chase camera (or a rear view) use { fan: false } for Godot's exact placement.
//
// USE (gv.js):   import { createEchoes } from './echoes.js';
//                const ECHO = createEchoes({ THREE, scene, th, fan: true });
//                in playStep, after the physics:   ECHO.tick(dt, PH, clock.t, { dose: PH.trip });
export function createEchoes({ THREE, scene, th, fan = true, N = 4, sample = 0.12, maxHist = 16, step = 3, spread = 9 }) {
  const geo = new THREE.SphereGeometry(0.55, 10, 8), items = [], hist = []; let on = 0, t = 0;
  const hsv = (h, s, v) => { h = ((h % 1) + 1) % 1; const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), tt = v * (1 - (1 - f) * s); return [[v, q, p, p, tt, v][i % 6], [tt, v, v, q, p, p][i % 6], [p, p, tt, v, v, q][i % 6]]; };
  for (let i = 0; i < N; i++) { const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false })); m.visible = false; m.frustumCulled = false; m.renderOrder = 4; scene.add(m); items.push(m); }
  function tick(dt, PH, time, o = {}) {
    const dose = o.dose !== undefined ? o.dose : (PH.trip || 0), want = (dose > 0.08 || PH.boost_t > 0) ? 1 : 0;
    on += (want - on) * (1 - Math.exp(-2.5 * dt));
    t += dt; if (t >= sample) { t = 0; hist.unshift([PH.x, PH.y, PH.z]); if (hist.length > maxHist) hist.pop(); }
    for (let i = 0; i < N; i++) {
      const m = items[i], hi = (i + 1) * step, a = 0.30 * on * (1 - i / N);
      if (hi >= hist.length || a < 0.01) { m.visible = false; continue; }
      m.visible = true; const q = hist[hi], side = fan ? (i % 2 ? 1 : -1) * (spread + 3 * i) : 0;
      m.position.set(q[0] + side, (fan ? th(q[0] + side, q[2]) + 1.6 : q[1] + 0.9), q[2]);
      const s = (1 - 0.14 * i); m.scale.set(0.8 * s, 1.5 * s, 0.8 * s);
      const c = hsv(time * 0.15 + 0.13 * i, 0.85, 1); m.material.color.setRGB(c[0] * a, c[1] * a, c[2] * a);          // additive: the alpha scales the colour
    }
  }
  return { tick, meshes: items, get on() { return on; } };
}
