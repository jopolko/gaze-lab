// THE CHROMATIC CARVE TRAIL, a literal port of Godot's _trail_fx_tick (RunRig.gd, "ASTRAL ECHOES and CHROMATIC CARVE TRAILS", consts CARVE_N = 28, ECHO_N = 4).
// When the board carves hard on the snow it leaves a trail of colour dots on the ground that cycles hue and fades. Godot's rules, copied:
//   * a pool of CARVE_N = 28 small additive spheres (radius 0.2), hidden when unused; the next free slot is taken round-robin;
//   * a dot is dropped every 0.05 s while the board is grounded, its sideways speed |vel.x| is over 7 m/s, the effect is on (_tf_on > 0.2) and the carve knob is up;
//   * the dot is placed at (x, ground + 0.2, z + 0.6), 0.6 m behind the board;
//   * each dot lives 1.4 s; its colour is HSV( fract(age_of_run * 0.3 + slot * 0.045), 0.9, 1.0 ) with alpha 0.8 * (1 - dot_age / 1.4) * _tf_on;
//   * _tf_on follows "a molecule dose is on, or a boost is running" (want = 1 when max(_mol_avg, fx_level) > 0.08 or _boost_t > 0), eased with 1 - exp(-2.5 dt).
// Additive blending means alpha is applied by scaling the dot's colour. One InstancedMesh, one draw call.
//
// USE (gv.js):   import { createCarveTrail } from './carvetrail.js';
//                const CARVE = createCarveTrail({ THREE, scene, th, vxMin: 7 * SPK, size: 2 });      // vxMin: Godot's 7 m/s scaled with our speeds; size: a multiplier on the 0.2 m dots (the camera is higher up here)
//                in playStep, after the physics:   CARVE.tick(dt, PH, clock.t, { dose: PH.trip });   // dose = the molecule felt level 0..3 (Godot's max(_mol_avg, fx_level)); PH.boost_t also turns it on
//                CARVE.mesh is the InstancedMesh (already added to the scene).
export function createCarveTrail({ THREE, scene, th, vxMin = 7, size = 1, N = 28, life = 1.4, drop = 0.05, wCarve = 1 }) {
  const geo = new THREE.SphereGeometry(0.2 * size, 8, 6);
  const mat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false });
  const mesh = new THREE.InstancedMesh(geo, mat, N); mesh.frustumCulled = false; mesh.renderOrder = 4;
  mesh.setColorAt(0, new THREE.Color(0, 0, 0)); scene.add(mesh);
  const age = new Float32Array(N).fill(99), px = new Float32Array(N), py = new Float32Array(N), pz = new Float32Array(N), m4 = new THREE.Matrix4(), col = new THREE.Color(), zero = new THREE.Matrix4().makeScale(0, 0, 0);
  let on = 0, dropT = 0, idx = 0;
  const hsv = (h, s, v) => { h = ((h % 1) + 1) % 1; const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); const r = [v, q, p, p, t, v][i % 6], g = [t, v, v, q, p, p][i % 6], b = [p, p, t, v, v, q][i % 6]; return [r, g, b]; };
  for (let i = 0; i < N; i++) mesh.setMatrixAt(i, zero);
  function tick(dt, PH, time, o = {}) {
    const dose = o.dose !== undefined ? o.dose : (PH.trip || 0), want = (dose > 0.08 || PH.boost_t > 0) ? 1 : 0, k = (o.wCarve !== undefined ? o.wCarve : wCarve);
    on += (want - on) * (1 - Math.exp(-2.5 * dt));
    dropT -= dt;
    if (dropT <= 0 && PH.grounded && Math.abs(PH.vx) > vxMin && on > 0.2 && k > 0.01) { dropT = drop; const di = idx; idx = (idx + 1) % N; age[di] = 0; px[di] = PH.x; pz[di] = PH.z + 0.6; py[di] = th(PH.x, PH.z) + 0.2; }
    for (let di = 0; di < N; di++) {
      age[di] += dt; const ag = age[di];
      if (ag > life) { mesh.setMatrixAt(di, zero); continue; }
      m4.makeTranslation(px[di], py[di], pz[di]); mesh.setMatrixAt(di, m4);
      const rgb = hsv(time * 0.3 + di * 0.045, 0.9, 1), a = 0.8 * (1 - ag / life) * on; col.setRGB(rgb[0] * a, rgb[1] * a, rgb[2] * a); mesh.setColorAt(di, col);
    }
    mesh.instanceMatrix.needsUpdate = true; if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  }
  return { tick, mesh, get on() { return on; } };
}
