// SKY DROPS: a small happy storm now and then. A cluster of fat, smiling bombs falls slowly into the distance around where the board is heading; each one shows a growing ring on the ground first,
// so a little steering is all it takes. A bonk is a stumble (speed knocked back, a shake, the chain breaks), never a crash. Every biome has its own form (jelly, snow puffs, gumdrops, bulbs, pinatas, data cubes, disco balls).
// ONE instanced mesh for the bombs and ONE for the rings (two draws in all, nothing when no storm is on).
export const DROP_FORMS = {
  psychedelic: { name: 'jelly', geo: 'sphere', cols: [[1.0, .25, .9], [.25, 1.0, .9], [1.0, .9, .2], [.6, .3, 1.0]], pop: 'SPLAT', ring: [1, .4, 1], hue: true },
  alpine: { name: 'snow puff', geo: 'sphere', cols: [[1.0, 1.0, 1.05], [.8, .92, 1.1], [1.0, .85, .9]], pop: 'FLUMP', ring: [.7, .9, 1.2], squash: 1.5 },
  candy: { name: 'gumdrop', geo: 'gum', cols: [[1.4, .35, .6], [.4, 1.3, .5], [1.4, 1.1, .2], [.5, .6, 1.5], [1.4, .55, .15]], pop: 'POP', ring: [1.3, .5, .9] },
  tunnel: { name: 'light bulb', geo: 'sphere', cols: [[1.6, 1.3, .5], [.6, 1.4, 1.6], [1.6, .6, 1.2]], pop: 'DING', ring: [1.4, 1.2, .5] },
  desert: { name: 'pinata', geo: 'sphere', cols: [[1.5, .45, .25], [1.4, 1.2, .2], [.3, 1.2, .8], [1.5, .3, .9]], pop: 'PINATA', ring: [1.5, .9, .3], confetti: true },
  matrix: { name: 'data cube', geo: 'box', cols: [[.3, 1.6, .5], [.5, 1.8, .9], [.2, 1.2, .3]], pop: 'BIT', ring: [.3, 1.5, .5] },
  synthwave: { name: 'disco ball', geo: 'sphere', cols: [[1.6, .35, 1.2], [.3, 1.4, 1.7], [1.7, .8, .3]], pop: 'TSS', ring: [1.5, .4, 1.3] },
};
export function createSkyDrops({ THREE, scene, th, PH, SPK, camera, toast, shudder, FX, theme, rnd, sp, Q, trailX, busy }) {
  if (Q.has('nostorm') || sp('storm', 1) <= 0) return { step() { }, force() { }, state: () => ({}) };
  const F = DROP_FORMS[theme] || DROP_FORMS.psychedelic, N = 10, R_HIT = 3.4, BIG = 2.7, FALL = sp('stormfall', 2.5);
  // the face: two eyes and a smile, tinted by the instance colour
  const cv = document.createElement('canvas'); cv.width = cv.height = 128; const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, 128, 128); g.fillStyle = '#241238';
  g.beginPath(); g.ellipse(44, 52, 7, 11, 0, 0, 7); g.fill(); g.beginPath(); g.ellipse(84, 52, 7, 11, 0, 0, 7); g.fill(); g.lineWidth = 7; g.lineCap = 'round'; g.strokeStyle = '#241238'; g.beginPath(); g.arc(64, 66, 26, .25 * Math.PI, .75 * Math.PI); g.stroke();
  g.fillStyle = '#ff8fa8aa'; g.beginPath(); g.ellipse(26, 72, 9, 6, 0, 0, 7); g.fill(); g.beginPath(); g.ellipse(102, 72, 9, 6, 0, 0, 7); g.fill();
  const tex = new THREE.CanvasTexture(cv); tex.colorSpace = THREE.SRGBColorSpace;
  const geo = F.geo === 'box' ? new THREE.BoxGeometry(1.7, 1.7, 1.7) : new THREE.SphereGeometry(1, 20, 14); if (F.geo === 'gum') geo.scale(1, .82, 1);
  // sphere uv: the face is on the -z side after rotating; the bombs are turned about Y to face the camera
  const mat = new THREE.MeshBasicMaterial({ map: tex, fog: true }); const bombs = new THREE.InstancedMesh(geo, mat, N); bombs.frustumCulled = false; bombs.userData.nocull = true; bombs.count = 0; bombs.renderOrder = 6; bombs.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(N * 3), 3); scene.add(bombs);
  const rmat = new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false }); const rg = new THREE.RingGeometry(.82, 1, 40); rg.rotateX(-Math.PI / 2);
  const rings = new THREE.InstancedMesh(rg, rmat, N); rings.frustumCulled = false; rings.userData.nocull = true; rings.count = 0; rings.renderOrder = 5; rings.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(N * 3), 3); scene.add(rings);
  const D = [], M = new THREE.Matrix4(), Q4 = new THREE.Quaternion(), V = new THREE.Vector3(), S = new THREE.Vector3(), E = new THREE.Euler(), C = new THREE.Color();
  let t = 0, nextAt = sp('stormfirst', 55), storm = null, last = 0;
  function startStorm() {
    const n = 5 + Math.floor(rnd() * 3), v = Math.hypot(PH.vx, PH.vz) || 30; storm = { n, i: 0, t: 0, gap: .42 };
    toast(F.name.toUpperCase() + ' STORM', '#fd6');
  }
  function spawn() {
    const v = Math.hypot(PH.vx, PH.vz) || 30, T = FALL, k = D.length; if (k >= N) return;
    // where the board will be when this one lands (straight on), then a scatter around that: some close to the line, some wide
    const ax = PH.x + PH.vx * T * .9, az = PH.z + PH.vz * T * .9, wide = (storm.i % 2 ? 1 : .45) * 16, x = ax + (rnd() - .5) * 2 * wide, z = az + (rnd() - .5) * 2 * 28 - 20;
    let gy = th(x, z); if (gy === null || gy === undefined) gy = PH.y;
    const col = F.cols[Math.floor(rnd() * F.cols.length)];
    D.push({ x, z, gy, y: gy + 62, t: 0, T, col, ph: rnd() * 6, hit: false, dead: 0, spin: rnd() * 2 });
  }
  function land(d) {
    d.dead = .35; d.y = d.gy + 1; const dx = PH.x - d.x, dz = PH.z - d.z; const near = Math.hypot(dx, dz) < R_HIT + BIG * .3 && PH.grounded && PH.y - d.gy < 3.2;
    try { FX.E.cheer([d.x, d.gy, d.z], F.ring, .5); } catch (e) { }
    if (near && !(PH.hurt > 0)) { if (PH.shield > 0 || (window.__SUPER && window.__SUPER.on)) { toast('SAFE!', '#5df'); } else { PH.vx *= .78; PH.vz *= .78; PH.chain = 0; shudder(.4); PH.hurt = Math.max(PH.hurt, .25); toast('BONK  ' + F.pop, '#fd6'); try { window.__spillOrbs && window.__spillOrbs(3); } catch (e) { } } }
  }
  function draw(dt) {
    let nb = 0, nr = 0; const cam = camera.position;
    for (const d of D) {
      const f = Math.min(1, d.t / d.T), rs = d.dead > 0 ? R_HIT * (1 + (.35 - d.dead) * 7) : R_HIT * (.35 + .65 * f), a = d.dead > 0 ? Math.max(0, d.dead / .35) : .35 + .65 * f;
      V.set(d.x, d.gy + .35, d.z); S.set(rs, 1, rs); M.compose(V, Q4.identity(), S); rings.setMatrixAt(nr, M); C.setRGB(F.ring[0] * a, F.ring[1] * a, F.ring[2] * a); rings.setColorAt(nr, C); nr++;
      if (d.dead <= 0 || d.dead > .2) {
        const sq = d.dead > 0 ? 1 + (F.squash || 1.2) * .5 * (1 - (.35 - d.dead) * 2) : 1, wob = 1 + .06 * Math.sin(d.t * 9 + d.ph); const sx = BIG * (d.dead > 0 ? sq : wob), sy = BIG * (d.dead > 0 ? 1 / sq * .6 : 2 - wob);
        const yaw = Math.atan2(cam.x - d.x, cam.z - d.z); E.set(0, yaw + Math.PI, F.hue ? 0 : Math.sin(d.t * 3 + d.ph) * .1); Q4.setFromEuler(E);
        V.set(d.x, d.y + sy * .9, d.z); S.set(sx, sy, sx); M.compose(V, Q4, S); bombs.setMatrixAt(nb, M); if (F.hue) C.setHSL((t * .35 + d.ph) % 1, 1, .6).multiplyScalar(1.6); else C.setRGB(d.col[0], d.col[1], d.col[2]); bombs.setColorAt(nb, C); nb++;
      }
    }
    bombs.count = nb; rings.count = nr; bombs.instanceMatrix.needsUpdate = rings.instanceMatrix.needsUpdate = true; if (bombs.instanceColor) bombs.instanceColor.needsUpdate = true; if (rings.instanceColor) rings.instanceColor.needsUpdate = true;
  }
  function step(dt) {
    t += dt; if (!PH.ready) return;
    if (!storm && !D.length) { const quiet = !(window.__SUPER && (window.__SUPER.on || window.__SUPER.warn > 0)) && PH.grounded && -PH.z > 120; if (quiet && t > nextAt) { startStorm(); } }
    if (storm) { storm.t += dt; if (storm.t > storm.i * storm.gap && storm.i < storm.n) { spawn(); storm.i++; } if (storm.i >= storm.n && D.length === 0) { storm = null; nextAt = t + sp('stormgap', 60) * (.8 + rnd() * .5); } if (storm && storm.i >= storm.n) storm.t = 1e9; }
    for (let i = D.length - 1; i >= 0; i--) { const d = D[i]; if (d.dead > 0) { d.dead -= dt; if (d.dead <= 0) D.splice(i, 1); continue; } d.t += dt; const f = Math.min(1, d.t / d.T); d.y = d.gy + 62 * (1 - f * f * .35 - f * .65); if (d.t >= d.T) land(d); if (d.z > PH.z + 60) d.dead = 1e-3; }
    draw(dt);
  }
  return { step, force: () => { nextAt = 0; }, state: () => ({ storm, n: D.length, t, nextAt, form: F.name, bc: bombs.count, rc: rings.count, d: D.map((d) => [Math.round(d.x), Math.round(d.y), Math.round(d.z), +d.t.toFixed(1), Math.round(d.gy)]) }) };
}
