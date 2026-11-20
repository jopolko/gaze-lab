// TIERS: Godot's quality tiers and the speed governor that moves between them, ported from godot/scripts/Lighting.gd (the tier block at the top, _apply_tier 212-262, step_governor 158-178, _governor 181-198,
// _weak_gpu 200-209) and RScale.gd (render scale), mapped onto the three.js renderer. No THREE import: it only calls the hooks it is given.
//
// THE TIERS (Lighting.gd 22-23): 0 everything   1 snow, gate lights and the trails pass off (on a phone)   2 glow off and the 3D picture rendered smaller   3 smaller still and no full-screen pass at all.
// THE FLOOR (Lighting.gd 65-66): a web build, or a phone, never goes above tier 1 ("the art is flat colour and soft light: the phone tier is the look, on desktop too"). So in Godot's browser build tier 0 is never reached:
//   the colour grade (contrast / saturation, `adjustment_enabled = tier < 1`) and the fine noise on the ground (`detail = 1.0 if tier < 1`) are OFF there; glow is ON until tier 2.  A web build starts at tier 1 and
//   only moves DOWN (more off) when it cannot hold 50 fps, and back up (never above the floor) after 16 s at 55+ fps.
// THE GOVERNOR (Lighting.gd 32-33, 158-198): checked every 2 s with the frame rate. PRESSURE = fps < 50 (or the head/eye tracker below 10.5 fps). Pressure for 3 s (2 s when the tracker is starving) and no cool-down: one tier worse,
//   6 s cool-down. No pressure: the pressure timer drains; after 16 s without pressure, fps >= 55 (and tracker >= 13), above the floor and no cool-down: one tier better, 6 s cool-down.
//
// WHAT EACH TIER DOES HERE (the Godot value, then how it maps; "ours" marks a knob Godot does not have):
//   snow particles ........ tier 0 on; tier 1 on only on desktop; off from 2              -> hooks.setSnow(bool) (we have none yet)
//   gate lights ........... tier < 1                                                       -> hooks.setLights(bool) (gate lights / pickup point lights, if any)
//   trails pass ........... tier < 1, or tier 1 on desktop                                -> hooks.setTrails(bool) (the post pass's feedback ghosts; turns off one render-target pass)
//   full-screen pass ...... tier < 3 (set_look(want if tier < 3 else 0))                   -> hooks.setPostLook(bool): false = plain tonemap only (no warp, ghosts, wash, vignette)
//   ground detail ......... tier < 1 (the shader's `detail` uniform)                       -> hooks.setGroundDetail(bool)
//   light shafts / sky .... shafts tier < 2, sky tier < 3                                  -> hooks.setShafts(bool), hooks.setSky(bool) (sky bands, sky dome, mountain skin)
//   glow .................. off at tier >= 2                                               -> hooks.setGlow(bool)
//   colour grade .......... on only at tier 0 (adjustment_enabled = tier < 1)              -> hooks.setGrade(bool)
//   render scale .......... touch [1, 1, .88, .76], desktop [1, 1, .92, .82], capped so the picture is about 0.95 Mpx on a phone, 1.2 Mpx on a weak laptop GPU, 2.1 Mpx otherwise (clamped .5..1)
//                                                                                          -> hooks.setPixelRatio(r): r = devicePixelRatio * scale (Godot makes the canvas smaller in the browser: same thing)
//   vegetation range ...... touch [0, 260, 210, 160], desktop [0, 340, 280, 230] (0 = as far as you can see)  -> hooks.setVegRange(m): hides rows / instanced trees beyond it
//   OURS: MSAA samples .... desktop [4, 2, 0, 0], touch [2, 0, 0, 0]                       -> hooks.setSamples(n)
//   OURS: particle scale .. [1, 1, .6, .35] (on top of the browser build's halved bursts)  -> hooks.setFxScale(k)
//   OURS: beacon range .... the vegetation range (or 340 m at 0)                           -> hooks.setBeaconRange(m)
//   OURS: stream window ... rows ahead [5, 5, 4, 3], rows behind [2, 2, 1, 1]              -> hooks.setStreamWindow(ahead, behind)

export const GAME_FPS_MIN = 50, TRACKER_FPS_MIN = 10.5, CHECK_S = 2, DOWN_NEED_S = 3, DOWN_NEED_TRACKER_S = 2, UP_NEED_S = 16, UP_FPS = 55, UP_TRACKER_FPS = 13, COOL_S = 6;
export const TIER_NAMES = ['everything', 'phone look', 'glow off, smaller', 'smallest, no pass'];
const SCALE_TOUCH = [1.0, 1.0, 0.88, 0.76], SCALE_DESK = [1.0, 1.0, 0.92, 0.82], VEG_TOUCH = [0, 260, 210, 160], VEG_DESK = [0, 340, 280, 230];
const MSAA_TOUCH = [2, 0, 0, 0], MSAA_DESK = [4, 2, 0, 0], FX_SCALE = [1, 1, 0.6, 0.35], AHEAD = [5, 5, 4, 3], BEHIND = [2, 2, 1, 1];

// the pixel budget (RScale / Lighting._apply_tier 236-238): a phone about a million pixels, a laptop up to full HD, a weak integrated GPU a little over a phone
export function pixelBudget(isTouch, weakGpu) { return isTouch ? 0.95e6 : (weakGpu ? 1.2e6 : 2.1e6); }
// _weak_gpu: an Intel UHD / HD / Iris chip has about a fifth of the pixel speed of a gaming card
export function detectWeakGpu(gl) { try { const ext = gl.getExtension('WEBGL_debug_renderer_info'); const g = String(ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : '').toLowerCase(); return g.includes('intel') && (g.includes('uhd') || g.includes('hd graphics') || g.includes('iris')); } catch (e) { return false; } }

// the flags of a tier as plain data (the table above)
export function tierFlags(tier, isTouch) {
  const t = Math.max(0, Math.min(3, tier | 0));
  return {
    tier: t, name: TIER_NAMES[t],
    snow: t === 0 || (t === 1 && !isTouch), lights: t < 1, trails: t < 1 || (t === 1 && !isTouch), postLook: t < 3, groundDetail: t < 1, shafts: t < 2, sky: t < 3, glow: t < 2, grade: t < 1,
    scale: (isTouch ? SCALE_TOUCH : SCALE_DESK)[t], vegRange: (isTouch ? VEG_TOUCH : VEG_DESK)[t], samples: (isTouch ? MSAA_TOUCH : MSAA_DESK)[t], fxScale: FX_SCALE[t], rowsAhead: AHEAD[t], rowsBehind: BEHIND[t],
  };
}

// createTiers({ isTouch, weakGpu, isWeb = true, floorTier, startTier, pin, hooks, cssSize: () => [w, h], dpr: () => devicePixelRatio, trackerOn: () => bool, trackerFps: () => number })
//   -> { tier, flags, frame(dtSeconds), update(dt, fps, trkFps, camOn), setTier(t), apply(), log, state }
export function createTiers(o = {}) {
  const isTouch = !!o.isTouch, isWeb = o.isWeb !== false, H = o.hooks || {}, weak = !!o.weakGpu;
  const floorTier = o.floorTier !== undefined ? o.floorTier : ((isTouch || isWeb) ? 1 : 0);          // Lighting.gd 65
  const S = { tier: Math.max(floorTier, o.startTier !== undefined ? o.startTier : (isWeb ? 1 : 0)), floorTier, bad: 0, good: 0, cool: 0, chk: 0, frames: 0, changes: 0, pin: o.pin === undefined || o.pin === null ? -1 : o.pin, fps: 60, applied: false };
  const log = []; let flags = tierFlags(S.tier, isTouch);
  const call = (n, ...a) => { try { if (H[n]) H[n](...a); } catch (e) { } };
  function pixelRatioFor(f) {          // RScale: the canvas is made smaller (a render scale of 1 = the page's own pixel ratio), never bigger than the pixel budget allows
    const dpr = o.dpr ? o.dpr() : 1, [w, h] = o.cssSize ? o.cssSize() : [1280, 720], px = Math.max(1, w * h * dpr * dpr);
    const cap = isWeb ? Math.max(0.5, Math.min(1, Math.sqrt(pixelBudget(isTouch, weak) / px))) : 1;          // (Godot's cap formula, relative to the full-size canvas)
    const s = Math.max(0.4, Math.min(1, Math.min(f.scale, cap))); return dpr * s;
  }
  function apply() {
    flags = tierFlags(S.tier, isTouch); S.applied = true;
    call('setSnow', flags.snow); call('setLights', flags.lights); call('setTrails', flags.trails); call('setPostLook', flags.postLook); call('setGroundDetail', flags.groundDetail); call('setShafts', flags.shafts); call('setSky', flags.sky);
    call('setGlow', flags.glow); call('setGrade', flags.grade); call('setPixelRatio', pixelRatioFor(flags)); call('setVegRange', flags.vegRange); call('setSamples', flags.samples); call('setFxScale', flags.fxScale);
    call('setBeaconRange', flags.vegRange > 0 ? flags.vegRange : 340); call('setStreamWindow', flags.rowsAhead, flags.rowsBehind); call('onTier', flags);
    return flags;
  }
  // Lighting.step_governor, line for line
  function update(dt, fps, trkFps, camOn) {
    S.cool = Math.max(S.cool - dt, 0); const pressure = fps < GAME_FPS_MIN || (camOn && trkFps < TRACKER_FPS_MIN);
    if (pressure) {
      S.good = 0; S.bad += dt; const need = (camOn && trkFps < TRACKER_FPS_MIN) ? DOWN_NEED_TRACKER_S : DOWN_NEED_S;          // a starving tracker is answered twice as fast
      if (S.bad >= need && S.tier < 3 && S.cool <= 0) { S.tier++; S.changes++; S.bad = 0; S.cool = COOL_S; log.push('tier ' + S.tier + ' (down) @' + Math.round(fps) + ' fps'); return true; }
    } else {
      S.bad = Math.max(S.bad - dt, 0); S.good += dt;
      if (S.good >= UP_NEED_S && S.tier > S.floorTier && fps >= UP_FPS && (!camOn || trkFps >= UP_TRACKER_FPS)) { S.tier--; S.changes++; S.good = 0; S.cool = COOL_S; log.push('tier ' + S.tier + ' (up) @' + Math.round(fps) + ' fps'); return true; }          // (as in step_governor: the cool-down is tested only on the way DOWN; the 16 s counter restarting after every step is what spaces the steps up)
    }
    return false;
  }
  // call once per rendered frame with the frame time in seconds: every CHECK_S (Lighting._governor, 2.0) the frame rate over that window is judged
  function frame(dt) {
    if (!S.applied) apply(); if (S.pin >= 0) { if (S.tier !== S.pin) { S.tier = S.pin; apply(); } return flags; }
    S.chk += dt; S.frames++; if (S.chk < CHECK_S) return flags; const win = S.chk, fps = S.frames / win; S.chk = 0; S.frames = 0; S.fps = fps;
    if (update(win, fps, o.trackerFps ? o.trackerFps() : 60, o.trackerOn ? !!o.trackerOn() : false)) apply(); return flags;
  }
  function setTier(t) { S.tier = Math.max(S.floorTier, Math.min(3, t | 0)); apply(); }
  return { get tier() { return S.tier; }, get flags() { return flags; }, frame, update, apply, setTier, log, state: S, floorTier };
}
