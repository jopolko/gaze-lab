// CAMRIG: Godot's FIRST-PERSON camera and view model, ported literally from godot/scripts/RunRig.gd (view_fp is true by default, RunRig.gd 10273).
//
// SOURCE MAP (RunRig.gd unless named):
//   _place_camera, first-person branch ........ 10401-10438  (look direction: half velocity, half heading, eased at 7/s; eye 1.72 m up and 0.25 m behind, +hop_cam, floored 1.2 m over the snow; look point 18 m ahead
//                                                        at snow + 1.4 + hop_cam * 0.5; the look is held between 0.1 x distance up and (0.2 + 0.05 x crest_lift) x distance down, eased at 6/s; tube blend; roll -steer*0.10 - trk_cam_roll;
//                                                        pitch trk_cam_pitch; fov = clamp(80 + (speed - 18) * 0.6, 78, 108) + fov_punch)
//   _crest_lift_tick .......................... 10361-10383 (every 3rd frame: the line from the eye to the trail 45, 70, 100 and 130 m ahead is checked against the ground; the eye is raised to see over a crest, up to CREST_LIFT_MAX = 2,
//                                                        quickly on the way up (4/s) and slowly on the way down (1.2/s))
//   _fit_fov .................................. 10326-10337 (an upright phone keeps the HORIZONTAL field of view, a very long thin phone fixes the width)
//   _fit_tip .................................. 10343-10351 (DEAD CODE in effect: _view_juice overwrites the pivot position every frame afterwards, see 4696; kept out of this port on purpose)
//   _view_juice (the tip's animation) ......... 4657-4698 (hop_cam, tip yaw / roll / pitch / x / hum, blink while hurt, the tricks' spin and flip)
//   _juice (the hop timing) ................... 4633-4650
//   _build_tip (the board tip) ................ 10450-10490 (blue board, half-round nose, white rim, orange stripe, two boots with orange laces)
//   _trk_cam_roll / _trk_cam_pitch ............ 11358-11369 (the tricks lean the picture: roll sin(spin) * 0.16 (+ a wobble in a head shake), pitch sin(flip) * 0.3, eased at 14/s)
//   _lk_step camera frame ..................... 9142-9143 + _place_camera 10423-10429 (in a tube the eye rides the tube: blend 7/s in, 3/s out; _lkc_t eased 14/s, _lkc_u 10/s)
//   _cine_apply ............................... 11053 (only for the THIRD-person view: want = cine_enabled and not view_fp ..., so it never runs here)
//   DownhillRig._place_camera ................. 1374-1405 (shake is h_offset / v_offset noise: DELIBERATELY LEFT OUT; shudder(a) gives a short decaying offset instead)
//
// WHAT THIS IS NOT: the third-person camera (cam_back 9.5, cam_h 6.2, cam_ahead 30, cam_road 0.8 on the trail) and the cinematic orbit.  Not ported: pm_view (phone-tilt view, off unless ?pmview), TrailCurve.heading (the bend is off in the dumps).
//
// USE (see the bottom of the file for the exact lines for gv.js):
//   const RIG = createCamRig({ THREE, scene, camera, th, trailX, PH, SPK, PSY, viewport, touch });
//   RIG.update(dt, { age, slideV, inAir, trkSpin, trkFlip, grabbing, tube });      // once a frame, after the physics

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const wrapPi = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };          // GDScript wrapf(a, -PI, PI)
export const CREST_LIFT_MAX = 2.0;          // RunRig.gd 10355
export const EYE_H = 1.72, EYE_BACK = 0.25, LOOK_AHEAD = 18.0, LOOK_Y = 1.4, EYE_FLOOR = 1.2;          // 10409-10415

// Godot's fov rule for the first-person view (RunRig.gd 10436) and what _fit_fov makes of it for the window's shape (10326-10337).  Returns the VERTICAL field of view in degrees (three.js has only that one).
export function fovFor(gsp, punch, vw, vh, touch) {
  const base = clamp(80 + (gsp - 18) * 0.6, 78, 108) + punch;
  const toV = (hfov) => 2 * Math.atan(Math.tan(hfov * Math.PI / 360) * vh / Math.max(vw, 1)) * 180 / Math.PI;          // KEEP_WIDTH: the number is the horizontal angle
  if (vh > vw * 1.05) return toV(clamp(62 + (gsp - 18) * 0.3, 60, 74) + punch * 0.6);
  if (touch && vw > vh * 1.9) return toV(clamp(98 + (gsp - 18) * 0.4, 96, 110) + punch * 0.6);
  return base;
}

export function createCamRig(o) {
  const { THREE, scene, camera, th, PH } = o, SPK = o.SPK || 1, trailX = o.trailX || (() => 0), PSY = o.PSY || null;
  const viewport = o.viewport || (() => ({ w: (typeof innerWidth !== 'undefined' ? innerWidth : 960), h: (typeof innerHeight !== 'undefined' ? innerHeight : 540) }));
  const touch = !!o.touch, V3 = THREE.Vector3;
  const S = {
    lookX: 0, lookZ: -1, haveLook: false, crest: 0, crestWant: 0, crestN: 0, fpDy: 0, lkcBlend: 0, lkcT: new V3(0, 0, -1), lkcU: new V3(0, 1, 0), tubeOn: false,
    hopT: 1, hopDur: 0.6, hopH: 1, hopSpin: 0, hopPitch: 0, hopReturn: false, hopVisSpin: 0, hopVisPitch: 0, hopCam: 0, trkRoll: 0, trkPitch: 0,
    tipYaw: 0, tipRoll: 0, tipX: 0, tipPitch: 0, tipYr: 0, tipPrevWh: 0, shud: 0, t: 0, eye: new V3(), look: new V3(), fov: 90,
  };
  const _up = new V3(0, 1, 0), _eye = new V3(), _ahead = new V3(), _tmp = new V3();

  // ------------------------------------------------------------------ the view model: the tip of the board (RunRig._build_tip), four draw calls
  function srgb(r, g, b) { return new THREE.Color().setRGB(r, g, b, THREE.SRGBColorSpace); }
  function mergeGeos(parts) {
    const P = [], N = [], I = []; let nv = 0;
    for (const p of parts) { const g = p.g.clone(); g.applyMatrix4(p.m); const pos = g.attributes.position, nor = g.attributes.normal, idx = g.index;
      for (let i = 0; i < pos.count; i++) { P.push(pos.getX(i), pos.getY(i), pos.getZ(i)); N.push(nor.getX(i), nor.getY(i), nor.getZ(i)); }
      if (idx) for (let i = 0; i < idx.count; i++) I.push(idx.getX(i) + nv); else for (let i = 0; i < pos.count; i++) I.push(i + nv); nv += pos.count; }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(N, 3)); g.setIndex(I); return g;
  }
  const M = (x, y, z, rx = 0, ry = 0, rz = 0) => new THREE.Matrix4().compose(new V3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz, 'YXZ')), new V3(1, 1, 1));
  const litMat = (c) => new THREE.MeshStandardMaterial({ color: c, roughness: 1, metalness: 0, side: THREE.DoubleSide });          // _flat_mat: Mats.lit() (double sided, vertex colours white, emission black), roughness 1
  const tip = new THREE.Group(); tip.rotation.order = 'YXZ'; tip.position.set(0, -1.15, 0);
  {
    const box = (w, h, d) => new THREE.BoxGeometry(w, h, d);
    const cap = new THREE.CylinderGeometry(0.4, 0.4, 0.09, 28, 1);          // CylinderMesh top_radius .4, bottom_radius .4, height .09, radial_segments 28, rings 1
    const rim = new THREE.TorusGeometry(0.39, 0.03, 6, 28); rim.rotateX(Math.PI / 2);          // TorusMesh inner .36, outer .42 (ring in the XZ plane), rings 28, ring_segments 6
    const boot = new THREE.CapsuleGeometry(0.1, 0.44 - 0.2, 4, 8);          // CapsuleMesh radius .1, height .44 (the whole thing, so the straight part is .24)
    const blueG = mergeGeos([{ g: box(0.8, 0.09, 0.5), m: M(0, 0, -0.9) }, { g: cap, m: M(0, 0, -1.15, 0.12) }]);
    const rimG = mergeGeos([{ g: rim, m: M(0, 0.05, -1.15, 0.12) }]);
    const orangeG = mergeGeos([{ g: box(0.07, 0.1, 0.55), m: M(0, 0.03, -1.0) }, { g: box(0.12, 0.03, 0.16), m: M(-0.19, 0.235, -0.82) }, { g: box(0.12, 0.03, 0.16), m: M(0.19, 0.235, -0.82) }]);
    const bootG = mergeGeos([{ g: boot, m: M(-0.19, 0.13, -0.78, Math.PI * 0.5) }, { g: boot, m: M(0.19, 0.13, -0.78, Math.PI * 0.5) }]);
    for (const [g, c] of [[blueG, srgb(0.15, 0.3, 0.75)], [rimG, srgb(0.97, 0.97, 1.0)], [orangeG, srgb(1.0, 0.55, 0.15)], [bootG, srgb(0.12, 0.13, 0.18)]]) { const m = new THREE.Mesh(g, litMat(c)); m.frustumCulled = false; m.castShadow = false; tip.add(m); }
  }
  camera.add(tip); if (!camera.parent && scene) scene.add(camera);          // the tip lives in the camera's space: the camera must be in the scene for it to draw
  tip.renderOrder = 10;

  // ------------------------------------------------------------------ the crest lift (RunRig._crest_lift_tick)
  function crestTick(dt, eyeY, eyeX, eyeZ, snap) {
    S.crestN++;
    if (snap || S.crestN % (o.crestStride || 3) === 0) {
      let need = 0; const ey0 = eyeY - S.crest;
      for (const d of [45, 70, 100, 130]) {
        const tz = PH.z - d, txx = trailX(tz), hp = th(txx, tz) + 0.4, steps = Math.trunc(d / 12);
        for (let si = 1; si < steps; si++) {
          const u = si / steps; if (u > 0.75) break;
          const gx = lerp(eyeX, txx, u), gz = lerp(eyeZ, tz, u), gh = th(gx, gz) + 0.5;
          need = Math.max(need, (gh - hp * u) / (1 - u) - ey0);
        }
      }
      S.crestWant = clamp(need - 1.5, 0, CREST_LIFT_MAX);
    }
    const k = S.crestWant > S.crest ? 4 : 1.2;
    S.crest = snap ? S.crestWant : lerp(S.crest, S.crestWant, 1 - Math.exp(-k * dt));
  }

  // ------------------------------------------------------------------ the hop (RunRig._start_hop / _juice): a pickup hop's height, spin and pitch (the picture rises a little with it)
  function startHop(h, dur, spin, pitch, ret) { S.hopT = 0; S.hopH = h; S.hopDur = dur; S.hopSpin = spin; S.hopPitch = pitch; S.hopReturn = !!ret; }
  const smooth01 = (u) => u * u * (3 - 2 * u);
  function hopTick(dt) {
    if (S.hopT < 1) {
      S.hopT = Math.min(S.hopT + dt / S.hopDur, 1); const u = S.hopT;
      S.hopVisSpin = S.hopSpin * (S.hopReturn ? Math.sin(Math.PI * u) : smooth01(u)); S.hopVisPitch = S.hopPitch * Math.sin(Math.PI * u);
    } else { S.hopVisSpin = 0; S.hopVisPitch = 0; }
  }

  // ------------------------------------------------------------------ the tube camera frame (RunRig._lk_step 9142-9143): the game hands over the tube's tangent and up each frame while it carries the board
  function setTube(tb) { if (tb && tb.active) { S.tubeOn = true; if (tb.t) S.lkcTarT = tb.t; if (tb.u) S.lkcTarU = tb.u; } else S.tubeOn = false; }

  function update(dt, st = {}) {
    S.t += dt; const snap = !!st.snap || !S.haveLook;
    const vx = PH.vx / SPK, vz = PH.vz / SPK, sp = Math.hypot(vx, vz);          // Godot's m/s
    // ---- the look direction: half the way the board travels, half the way it points (10401-10408)
    let dx = 0, dz = -1; if (sp > 1) { dx = vx / sp; dz = vz / sp; }
    const hx = Math.sin(PH.heading), hz = -Math.cos(PH.heading); let wx = dx * 0.5 + hx * 0.5, wz = dz * 0.5 + hz * 0.5; const wn = Math.hypot(wx, wz) || 1; wx /= wn; wz /= wn;
    if (snap) { S.lookX = wx; S.lookZ = wz; S.haveLook = true; } else { const k = 1 - Math.exp(-7 * dt); S.lookX += (wx - S.lookX) * k; S.lookZ += (wz - S.lookZ) * k; const ln = Math.hypot(S.lookX, S.lookZ) || 1; S.lookX /= ln; S.lookZ /= ln; }
    // ---- the eye (10409-10412)
    let ex = PH.x - S.lookX * EYE_BACK, ey = PH.y + EYE_H + S.hopCam, ez = PH.z - S.lookZ * EYE_BACK;
    ey = Math.max(ey, th(ex, ez) + EYE_FLOOR);
    crestTick(dt, ey, ex, ez, snap); ey += S.crest;
    // ---- the look point (10414-10422)
    let ax = PH.x + S.lookX * LOOK_AHEAD, az = PH.z + S.lookZ * LOOK_AHEAD, ay = th(ax, az) + LOOK_Y + S.hopCam * 0.5;
    const flat = Math.hypot(ax - ex, az - ez), lk = o.lookDown ? o.lookDown() : 0.2, wdy = clamp(ay - ey, -flat * (lk + 0.05 * S.crest), flat * 0.1);          // lk: how far the view may tip down (as a slope). Godot allowed 0.2 (11 degrees); the courses here run down 8 to 19 degrees and steeper, so the road ahead dropped out of the picture
    S.fpDy = snap ? wdy : lerp(S.fpDy, wdy, 1 - Math.exp(-9 * dt)); ay = ey + S.fpDy;
    // ---- in a tube the camera rides the tube (10423-10429)
    S.lkcBlend = lerp(S.lkcBlend, S.tubeOn ? 1 : 0, 1 - Math.exp(-(S.tubeOn ? 7 : 3) * dt));
    _up.set(0, 1, 0);
    if (S.tubeOn && S.lkcTarT) { S.lkcT.lerp(_tmp.set(S.lkcTarT[0], S.lkcTarT[1], S.lkcTarT[2]), 1 - Math.exp(-14 * dt)).normalize(); S.lkcU.lerp(_tmp.set(S.lkcTarU[0], S.lkcTarU[1], S.lkcTarU[2]), 1 - Math.exp(-10 * dt)).normalize(); }
    if (S.lkcBlend > 0.01) {
      const b = S.lkcBlend; ex = lerp(ex, PH.x + S.lkcU.x * 1.7 - S.lkcT.x * 0.25, b); ey = lerp(ey, PH.y + S.lkcU.y * 1.7 - S.lkcT.y * 0.25, b); ez = lerp(ez, PH.z + S.lkcU.z * 1.7 - S.lkcT.z * 0.25, b);
      ax = lerp(ax, PH.x + S.lkcT.x * 20, b); ay = lerp(ay, PH.y + S.lkcT.y * 20, b); az = lerp(az, PH.z + S.lkcT.z * 20, b);
      _up.lerp(S.lkcU, b).normalize();
    }
    _eye.set(ex, ey, ez); _ahead.set(ax, ay, az); S.eye.copy(_eye); S.look.copy(_ahead);
    camera.up.copy(_up); camera.position.copy(_eye); if (_ahead.distanceTo(_eye) > 0.5) camera.lookAt(_ahead);
    // ---- the tricks lean the picture (11358-11369), then the steering roll and the flip pitch (10434): basis * Rz(-steer*0.10 - trk_cam_roll) * Rx(trk_cam_pitch)
    const ts = st.inAir ? (st.trkSpin || 0) : (st.trkVisSpin || 0), tf = st.inAir ? (st.trkFlip || 0) : (st.trkVisFlip || 0), wob = st.wobble ? Math.sin(S.t * 40) * 0.07 : 0;
    S.trkRoll = lerp(S.trkRoll, Math.sin(ts) * 0.16 + wob, 1 - Math.exp(-14 * dt)); S.trkPitch = lerp(S.trkPitch, Math.sin(tf) * 0.3, 1 - Math.exp(-14 * dt));
    camera.rotateZ(-PH.steer * 0.10 - S.trkRoll); camera.rotateX(S.trkPitch);
    // ---- fov (10436) and what the window's shape makes of it (_fit_fov)
    const punch = PSY && PSY.camera ? PSY.camera.fov_punch : (st.fovPunch || 0), vp = viewport();
    const fv = fovFor(sp, punch, vp.w, vp.h, touch) * (o.fovMul ? o.fovMul() : 1); S.fov = fv;
    if (Math.abs(fv - camera.fov) > 0.05) { camera.fov = fv; camera.updateProjectionMatrix(); }
    // ---- an impact shudder, not a shake: a short decaying offset
    if (S.shud > 0.002) { camera.position.y += Math.sin(S.t * 90) * S.shud; camera.position.x += Math.sin(S.t * 71 + 1.3) * S.shud * 0.6; S.shud *= Math.exp(-dt * 13); }
    camera.updateMatrixWorld(true);
    juice(dt, st, sp, vx, vz);
  }

  // ------------------------------------------------------------------ _juice (the hop) and _view_juice (the board tip), which RunRig runs right after placing the camera
  function juice(dt, st, sp, vx, vz) {
    hopTick(dt);          // (_juice advances the hop, then _view_juice reads it)
    S.hopCam = S.hopT < 1 ? S.hopH * 4 * S.hopT * (1 - S.hopT) * 0.5 : 0;          // (_view_juice's first line: the NEXT frame's camera uses it, as in Godot)
    const ts = st.inAir ? (st.trkSpin || 0) : (st.trkVisSpin || 0), tf = st.inAir ? (st.trkFlip || 0) : (st.trkVisFlip || 0), grabbing = !!(st.inAir && st.grabbing);
    tip.visible = (PH.hurt || 0) <= 0 || Math.floor((st.age !== undefined ? st.age : S.t) * 14) % 2 === 0;
    const heading = PH.heading, age = st.age !== undefined ? st.age : S.t;
    const d = wrapPi(heading - Math.atan2(S.lookX, -S.lookZ)), rx = Math.cos(heading), rz = Math.sin(heading);
    const slip = vx * rx + vz * rz, spn = clamp(sp / 45, 0, 1);
    S.tipYaw = lerp(S.tipYaw, -d, 1 - Math.exp(-6 * dt));
    const wh = heading, yr = wrapPi(wh - S.tipPrevWh) / Math.max(dt, 0.001); S.tipPrevWh = wh;
    S.tipYr = lerp(S.tipYr, clamp(yr, -1.5, 1.5), 1 - Math.exp(-8 * dt));
    const slideV = (st.slideV !== undefined ? st.slideV : (PH.slide || 0)) / SPK;
    const lean = -clamp(S.tipYr * 1.6 * (0.5 + 0.5 * spn), -0.55, 0.55) - clamp(slideV * 0.006, -0.2, 0.2) - PH.steer * 0.08;
    S.tipRoll = lerp(S.tipRoll, lean, 1 - Math.exp(-6 * dt));
    const fx = Math.sin(heading), fz = -Math.cos(heading);
    let gp = 0; if (PH.grounded) gp = Math.atan((th(PH.x + fx * 3, PH.z + fz * 3) - th(PH.x - fx * 3, PH.z - fz * 3)) / 6); else gp = Math.atan2(PH.vy / SPK, Math.max(sp, 1)) * 0.9;
    camera.getWorldDirection(_tmp); const camPitch = Math.asin(clamp(_tmp.y, -1, 1));          // asin(-basis.z.y) in Godot is the same number: the camera looks down its own -Z
    S.tipPitch = lerp(S.tipPitch, clamp(gp - camPitch, -0.5, 0.5), 1 - Math.exp(-7 * dt));
    S.tipX = lerp(S.tipX, clamp(-slip * 0.012, -0.14, 0.14), 1 - Math.exp(-4 * dt));
    const hum = PH.grounded ? (0.008 * Math.sin(age * 17) + 0.005 * Math.sin(age * 29)) * spn : 0;
    tip.position.set(S.tipX, -1.15 + hum - (grabbing ? 0.1 : 0) - S.crest * 0.95, 0);
    tip.rotation.set(tf + S.hopVisPitch + (grabbing ? 0.2 : 0) + S.tipPitch, S.tipYaw + ts + S.hopVisSpin, S.tipRoll);
  }

  function shudder(a) { S.shud = Math.max(S.shud, a); }
  return { update, tip, shudder, setTube, startHop, state: S, fovFor };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// DIFFERENCES FOUND (gv.js camera block, CAMD.mode 'fp', versus Godot) and what this module does about each:
//  1. No crest lift in gv.js: on a fall-away the ground ahead hid the path (RunRig.gd 10354-10383).  Ported: the eye rises up to 2 m (4/s up, 1.2/s down), checked every 3rd frame against 4 sight lines.  COST: about 4 x (3..9) = 25 th() calls
//     every 3rd frame; if th() is a raycast that is about 8 per frame: raise opts.crestStride (to 6) on a slow phone.
//  2. No hop_cam in gv.js (10409, 10415, 4658): a pickup hop lifts the picture by hop_h * 4u(1-u) * 0.5.  Ported (startHop(h, dur, spin, pitch, ret) takes Godot's arguments, e.g. 1.0, 0.55, 0, 0.5, false).
//  3. gv.js has no board tip at all (RunRig._build_tip 10450-10490).  Ported as a camera child with four draw calls (blue board + nose, white rim, orange stripe + laces, two boots) and the exact animation of _view_juice (yaw lag, lean from the
//     turn rate and the slide, pitch from the ground slope or the flight, sideways slip, a hum with speed, a blink while hurt, the trick spin and flip, the grab).
//  4. gv.js's fov is the plain formula (PSY.cameraFov); Godot also runs _fit_fov (10326-10337): an upright phone keeps the horizontal field (62 + (speed-18)*0.3, 60..74, + punch*0.6) and a very long thin touch screen fixes the
//     width (98 + (speed-18)*0.4, 96..110).  Ported in fovFor(): the three.js camera takes the vertical angle, so the horizontal one is converted with the window's aspect.
//  5. gv.js has no trick roll/pitch (_trk_cam_roll / _trk_cam_pitch, 11358-11369) and no tube camera (10423-10429).  Ported; the game feeds trkSpin / trkFlip / setTube() when it has those systems (the defaults do nothing).
//  6. _fit_tip (10343-10351) is NOT ported: _view_juice (4696) writes the pivot position again every frame right after it, so its result never shows.  (The crest lift term -crest*0.95 it contained IS in _view_juice and is ported.)
//  7. Shake: Godot's h_offset / v_offset noise (DownhillRig 1403-1404) is left out by request; shudder(a) is a short decaying offset (a in metres, gone in about a quarter of a second).
//  8. Speeds: Godot's formulas take m/s; every velocity is divided by SPK first, so the field of view and the tip's lean see Godot's numbers.
//
// INTEGRATION LINES for gv.js:
//   import { createCamRig } from './camrig.js';
//   const RIG = createCamRig({ THREE, scene, camera, th: (x, z) => { const g = groundY(x, z); return g === null ? PH.y : g; }, trailX, PH, SPK, PSY, touch: TOUCHDEV, fovMul: () => (LABV.fovMul || 1) });
//   (th must NOT write PH.lastGh: use groundY directly as above, not gv.js's th())
//   in frame(), replace the whole `if (PLAY && CAMD.mode === 'fp') {...}` block with:
//     if (PLAY && CAMD.mode === 'fp') { RIG.update(dt, { age: clock.t, slideV: PH.slide, inAir: !PH.grounded, snap: !CAMD.ldone }); CAMD.ldone = true;
//       U.uBoard.value.set(PH.x, PH.z); sky.position.copy(camera.position); if (ring) { const e = ring.matrix.elements; e[12] = camera.position.x; e[13] = camera.position.y - 1.7 - 159.696; e[14] = camera.position.z; } }
//   remove the old shake lines in that block and call RIG.shudder(a) where gv.js calls shudder(a) (the SHUD object can go);
//   a pickup hop (if you add one): RIG.startHop(1.0, 0.55, 0, 0.5, false);  a tube: RIG.setTube({ active: true, t: [tx, ty, tz], u: [ux, uy, uz] }) every frame while carried, setTube(null) after.
//   note: camera.up is set every frame (the tube rolls it); the tip draws only when the camera is in the scene (the module adds it).
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
