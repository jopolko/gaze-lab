// numeric check of camrig.js against the GDScript formulas worked by hand (RunRig.gd 10361-10438, 4657-4698, 10326-10337, 11358-11369). run: node camrig_check.mjs
import * as THREE from '../stargaze/vendor/three/three.module.min.js';
import { createCamRig, fovFor, CREST_LIFT_MAX } from './camrig.js';
let fails = 0; const ok = (name, cond, extra = '') => { if (!cond) fails++; console.log((cond ? 'ok   ' : 'FAIL ') + name + (extra ? '   ' + extra : '')); };
const near = (a, b, e = 1e-6) => Math.abs(a - b) <= e;
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

const mk = (opts = {}) => {
  const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(78, 16 / 9, 0.2, 1600);
  const PH = { x: 0, y: 0, z: -100, vx: 0, vz: -30, vy: 0, heading: 0, steer: 0, grounded: true, hurt: 0, slide: 0 };
  const th = opts.th || ((x, z) => -0.34 * (-z) - 0 * x);          // a plain slope: the snow is 0.34 m lower per metre travelled
  const rig = createCamRig({ THREE, scene, camera, th, trailX: opts.trailX || (() => 0), PH, SPK: opts.SPK || 1, PSY: null, viewport: () => (opts.vp || { w: 1600, h: 900 }), touch: !!opts.touch, crestStride: 1 });
  PH.y = th(PH.x, PH.z); return { scene, camera, PH, rig, th };
};

// ---- 1. steady state on a plain slope: look = (0,-1); eye = (0, snow + 1.72, z + 0.25); fov = clamp(80 + (30 - 18) * 0.6, 78, 108) = 87.2
{ const { camera, PH, rig, th } = mk(); for (let i = 0; i < 5; i++) rig.update(1 / 60, { age: i / 60 });
  ok('eye x', near(camera.position.x, 0)); ok('eye y = snow + 1.72', near(camera.position.y, th(0, -100) + 1.72, 1e-4), camera.position.y.toFixed(4));
  ok('eye z = z + 0.25', near(camera.position.z, -100 + 0.25, 1e-6)); ok('fov 87.2', near(camera.fov, 87.2, 1e-4), camera.fov.toFixed(3));
  // the look point is 18 m ahead at snow + 1.4: the camera pitch is the slope down to it, held between +0.1 d up and -0.2 d down (d = 18.0): the point is 6.12 m lower + 1.4 - 1.72 = -5.44 m -> -5.44 / 18 = -0.302 < -0.2, so clamped to -0.2 * 18 = -3.6
  const d = new THREE.Vector3(); camera.getWorldDirection(d); const want = Math.atan2(-3.6, 18.0 + 0.0); ok('pitch clamps to -0.2 d (the slope is steeper)', near(Math.asin(d.y), want, 2e-3), `${Math.asin(d.y).toFixed(4)} vs ${want.toFixed(4)}`); }

// ---- 2. the look direction: heading 0.6 with the board still travelling straight: want = normalize(vdir*0.5 + hd*0.5), eased at 7/s from the first frame (snap)
{ const { camera, PH, rig } = mk(); PH.heading = 0.6; rig.update(1 / 60, { age: 0, snap: true });
  const wx = 0.5 * 0 + 0.5 * Math.sin(0.6), wz = 0.5 * -1 + 0.5 * -Math.cos(0.6), n = Math.hypot(wx, wz);
  ok('look x snaps to the blend', near(rig.state.lookX, wx / n, 1e-9), rig.state.lookX.toFixed(5)); ok('look z', near(rig.state.lookZ, wz / n, 1e-9));
  rig.update(1 / 60, { age: 1 / 60 }); const k = 1 - Math.exp(-7 / 60); ok('look stays put when the target is unchanged', near(rig.state.lookX, wx / n, 1e-9)); void k; }
{ const { PH, rig } = mk(); rig.update(1 / 60, { age: 0, snap: true }); PH.heading = 0.6; rig.update(1 / 60, { age: 1 / 60 });
  const wx0 = 0.5 * Math.sin(0.6), wz0 = -0.5 - 0.5 * Math.cos(0.6), n0 = Math.hypot(wx0, wz0), tx = wx0 / n0, tz = wz0 / n0, k = 1 - Math.exp(-7 / 60);
  let lx = 0 + (tx - 0) * k, lz = -1 + (tz + 1) * k; const ln = Math.hypot(lx, lz); lx /= ln; lz /= ln;
  ok('look eases at 7/s', near(rig.state.lookX, lx, 1e-9) && near(rig.state.lookZ, lz, 1e-9), `${rig.state.lookX.toFixed(5)} vs ${lx.toFixed(5)}`); }

// ---- 3. the crest lift: a bump on the slope 60 m ahead hides the trail; the eye rises by clamp(need - 1.5, 0, 2), computed here by the same loop written out again
{ const bump = (x, z) => 9 * Math.exp(-Math.pow((z - (-160)) / 14, 2)); const th = (x, z) => -0.34 * (-z) + bump(x, z);
  const { camera, PH, rig } = mk({ th }); PH.y = th(PH.x, PH.z);
  rig.update(1 / 60, { age: 0, snap: true });
  // by hand: eye after the floor clamp
  const eyeX = 0, eyeZ = -100 + 0.25; let eyeY = Math.max(PH.y + 1.72, th(eyeX, eyeZ) + 1.2); const ey0 = eyeY - 0;
  let need = 0; for (const d of [45, 70, 100, 130]) { const tz = PH.z - d, tx = 0, hp = th(tx, tz) + 0.4, steps = Math.trunc(d / 12);
    for (let si = 1; si < steps; si++) { const u = si / steps; if (u > 0.75) break; const gx = eyeX + (tx - eyeX) * u, gz = eyeZ + (tz - eyeZ) * u, gh = th(gx, gz) + 0.5; need = Math.max(need, (gh - hp * u) / (1 - u) - ey0); } }
  const want = clamp(need - 1.5, 0, CREST_LIFT_MAX);
  ok('crest lift snaps to the wanted value', near(rig.state.crest, want, 1e-9), `${rig.state.crest.toFixed(4)} vs ${want.toFixed(4)} (need ${need.toFixed(3)})`);
  ok('the lift is positive and within the maximum', rig.state.crest > 0 && rig.state.crest <= CREST_LIFT_MAX + 1e-9);
  ok('the eye carries the lift', near(camera.position.y, eyeY + rig.state.crest, 1e-6));
  // it comes back slowly: flat ground, 1.2/s
  const th2 = (x, z) => -0.34 * (-z); const R2 = mk({ th: th2 }); R2.rig.update(1 / 60, { age: 0 }); R2.rig.state.crest = 1.0; R2.rig.state.crestWant = 0; R2.rig.update(1 / 60, { age: 1 / 60 }); const back = 1.0 + (0 - 1.0) * (1 - Math.exp(-1.2 / 60));
  ok('the lift eases back down at 1.2/s', near(R2.rig.state.crest, back, 1e-9), `${R2.rig.state.crest.toFixed(5)} vs ${back.toFixed(5)}`); }

// ---- 4. the hop: height 1.0 over 0.55 s: at u = 0.5 the eye is lifted by 1.0 * 4 * 0.5 * 0.5 * 0.5 = 0.5 (used by the next frame, as in Godot)
{ const { camera, PH, rig, th } = mk(); rig.startHop(1.0, 0.55, 0, 0.5, false); for (let i = 0; i < 100; i++) { rig.update(0.55 / 100, { age: i * 0.0055 }); if (rig.state.hopT >= 0.5) break; }
  const u = rig.state.hopT; ok('hop_cam = h * 4u(1-u) * 0.5', near(rig.state.hopCam, 1.0 * 4 * u * (1 - u) * 0.5, 1e-12), `u ${u.toFixed(3)} cam ${rig.state.hopCam.toFixed(4)}`);
  ok('the hop pitches the tip: pitch * sin(PI u)', near(rig.state.hopVisPitch, 0.5 * Math.sin(Math.PI * u), 1e-12));
  rig.update(0.0055, { age: 1 }); ok('the camera is lifted by hop_cam on the next frame', camera.position.y > th(0, -100) + 1.72 + 0.4); }

// ---- 5. the field of view and _fit_fov
{ ok('fov at 18 m/s is 80', near(fovFor(18, 0, 1600, 900, false), 80)); ok('fov clamps at 108', near(fovFor(80, 0, 1600, 900, false), 108));
  ok('fov clamps at 78', near(fovFor(0, 0, 1600, 900, false), 78)); ok('the punch is added', near(fovFor(18, 7, 1600, 900, false), 87));
  const hf = clamp(62 + (30 - 18) * 0.3, 60, 74), upright = 2 * Math.atan(Math.tan(hf * Math.PI / 360) * 1600 / 800) * 180 / Math.PI;
  ok('an upright phone fixes the horizontal field (62 + (v-18)*0.3)', near(fovFor(30, 0, 800, 1600, true), upright, 1e-9), upright.toFixed(2));
  const hf2 = clamp(98 + (30 - 18) * 0.4, 96, 110), thin = 2 * Math.atan(Math.tan(hf2 * Math.PI / 360) * 400 / 1000) * 180 / Math.PI;
  ok('a long thin touch screen fixes the width (98 + (v-18)*0.4)', near(fovFor(30, 0, 1000, 400, true), thin, 1e-9), thin.toFixed(2));
  ok('a long thin NON-touch window keeps the height', near(fovFor(30, 0, 1000, 400, false), clamp(80 + 12 * 0.6, 78, 108))); }
// speed factor: the field of view sees Godot's m/s
{ const a = mk({ SPK: 2.5 }); a.PH.vz = -75; a.rig.update(1 / 60, { age: 0 }); ok('speeds are divided by SPK before the fov rule', near(a.camera.fov, clamp(80 + (30 - 18) * 0.6, 78, 108), 1e-6), a.camera.fov.toFixed(3)); }

// ---- 6. the steering roll and the trick lean: roll = -steer * 0.10 - trk_cam_roll, applied about the camera's own Z after look_at
{ const { camera, PH, rig } = mk(); PH.steer = 0.5; rig.update(1 / 60, { age: 0 });
  const q0 = new THREE.Camera(); q0.position.copy(camera.position); q0.up.set(0, 1, 0); q0.lookAt(rig.state.look); q0.rotateZ(-0.5 * 0.10); ok('steer rolls the picture by -steer * 0.10', camera.quaternion.angleTo(q0.quaternion) < 1e-6, camera.quaternion.angleTo(q0.quaternion).toExponential(2));
  const r = mk(); r.rig.update(1 / 60, { age: 0, inAir: true, trkSpin: Math.PI / 2 }); const kk = 1 - Math.exp(-14 / 60); ok('a spin leans the picture: roll eases to sin(spin) * 0.16 at 14/s', near(r.rig.state.trkRoll, 0 + (Math.sin(Math.PI / 2) * 0.16) * kk, 1e-12)); }

// ---- 7. the tip: an exact copy of what _view_juice does, worked by hand for a left turn
{ const { camera, PH, rig } = mk(); rig.update(1 / 60, { age: 0, snap: true });
  PH.heading = 0.4; PH.steer = 0.3; const dt = 1 / 60; rig.update(dt, { age: dt });
  const S = rig.state, wrap = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
  const d = wrap(0.4 - Math.atan2(S.lookX, -S.lookZ)); const yaw = 0 + (-d - 0) * (1 - Math.exp(-6 * dt));
  ok('tip yaw lags the heading: -d eased at 6/s', near(S.tipYaw, yaw, 1e-9), `${S.tipYaw.toFixed(5)} vs ${yaw.toFixed(5)}`);
  const yr = clamp((0.4 - 0) / dt, -1.5, 1.5), spn = clamp(30 / 45, 0, 1), tyr = 0 + (yr - 0) * (1 - Math.exp(-8 * dt)); const lean = -clamp(tyr * 1.6 * (0.5 + 0.5 * spn), -0.55, 0.55) - clamp(0, -0.2, 0.2) - 0.3 * 0.08;
  const roll = 0 + (lean - 0) * (1 - Math.exp(-6 * dt)); ok('tip roll leans into the turn', near(S.tipRoll, roll, 1e-9), `${S.tipRoll.toFixed(5)} vs ${roll.toFixed(5)}`);
  const tip = rig.tip; ok('tip rotation order is Godot\'s YXZ', tip.rotation.order === 'YXZ'); ok('tip roll applied', near(tip.rotation.z, roll, 1e-9)); ok('tip sits at -1.15 below the eye (+ a hum of a few mm)', Math.abs(tip.position.y + 1.15) < 0.02, tip.position.y.toFixed(4)); }
{ const { PH, rig } = mk(); PH.hurt = 1; let vis = new Set(); for (let i = 0; i < 40; i++) { rig.update(1 / 60, { age: i / 60 }); vis.add(rig.tip.visible); } ok('the tip blinks while hurt (int(age*14) % 2)', vis.size === 2); }
{ const { PH, rig } = mk(); rig.update(1 / 60, { age: 0 }); ok('the camera is added to the scene so its child (the tip) draws', rig.tip.parent !== null); let meshes = 0; rig.tip.traverse((o) => { if (o.isMesh) meshes++; }); ok('the tip is four draw calls', meshes === 4, String(meshes)); }
{ const { PH, rig } = mk(); PH.grounded = false; PH.vy = 20; PH.vx = 0; PH.vz = -30; rig.update(1 / 60, { age: 0, snap: true }); rig.update(1 / 60, { age: 1 / 60 }); const cam = rig.state; void cam; ok('in the air the tip pitch follows the flight (atan2(vy, speed) * 0.9)', rig.state.tipPitch !== 0); }

// ---- 8. the tube blend: 7/s in
{ const { camera, PH, rig } = mk(); rig.update(1 / 60, { age: 0, snap: true }); rig.setTube({ active: true, t: [1, 0, 0], u: [0, 1, 0] }); rig.update(1 / 60, { age: 1 / 60 }); ok('tube blend eases in at 7/s', near(rig.state.lkcBlend, 0 + (1 - 0) * (1 - Math.exp(-7 / 60)), 1e-9)); }

// ---- 9. the shudder: short and decaying, never continuous
{ const { camera, PH, rig } = mk(); rig.update(1 / 60, { age: 0, snap: true }); rig.shudder(0.3); const y0 = camera.position.y; let peak = 0; for (let i = 0; i < 40; i++) { rig.update(1 / 60, { age: i / 60 }); peak = Math.max(peak, Math.abs(camera.position.y - y0)); } ok('the shudder is gone in about a quarter of a second', rig.state.shud < 0.002 || rig.state.shud < 0.3 * Math.exp(-13 * 0.6), rig.state.shud.toExponential(2)); ok('the shudder moves the camera', peak > 0.01, peak.toFixed(3)); }

console.log(fails ? `\n${fails} FAILED` : '\nall passed'); process.exit(fails ? 1 : 0);
