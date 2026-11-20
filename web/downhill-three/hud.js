// HUD: Godot's heads-up display and on-screen feedback, redrawn on ONE overlay 2D canvas (cheap on a phone: one clear and a handful of rects and strings per frame).
// Ported from godot/scripts/RunRig.gd _draw_hud_inner (12478-12775) and the helpers it calls; DownhillRig.gd _toast (1308), _hud_scale (1465), _text / _ctext (1485-1498), _pause_rect (2910), _draw_pause_simple (3051);
// RunRig.gd _cheer (3959), _draw_chain (4409), _chain_color (4372), _draw_pops (12097) / _buff_pop (4551), _draw_tricks (11720, the ramp-charge bar), the finish screen (12729), clock_text (2041), progress (2212).
//
// WHAT IS PORTED (source line refs are RunRig.gd unless noted):
//   layout scale k ................ _hud_scale (Downhill 1465): 2.0 portrait, 1.25 touch, else 1.0.  m = 24k (12512)
//   text .......................... _text / _ctext (Downhill 1485/1491): black outline (7 px at size>=30 else 3 px, alpha .9) then the fill; size * k
//   toasts ........................ _toast (Downhill 1308): kinds info (2.4 s, one at a time, never the same twice in a row, middle of the screen y = .40 H, size 20, +26k per line, alpha*.85,
//                                   fades over the last .5 s), ach (3.0 s, small 15, bottom-left stack at y = H - m - 54k, -20k each, alpha*.8), face (2.0 s, size 44 at .32 H); max 5 in the queue (12716-12727)
//   cheer ......................... _cheer (3959): a toast + white flash .25*size (the fov punch, rings, confetti and sound are the game's)
//   screen washes ................. journey flash (12482: flash_col, alpha*.30), snowball red wash + "SNOWBALL BEHIND YOU" (12506), cue tint .07 (12510), hurt red .22 (12513), flash white .3 (12515; decays 2/s, Downhill 1437)
//   buff pops ..................... _draw_pops (12097): seven nested frame rects (pop colour, alpha .2 - .026 i, 12*k wide) and per pop a ring + 10 rays + a word, over .8 s
//   ramp charge bar ............... _draw_tricks (11720): 180k wide bar at .80 H, "pop at the lip" / "FULL CHARGE"
//   speed lines ................... 12521: 30 lines from the edge of the screen when the board is faster than 26 m/s, more of them the faster
//   progress bar .................. 12636: top centre, min(.34 W, 420k) wide, 4k high, gold fill
//   score ......................... 12645: top left, size 26, "%d" (race mode: the clock, clock_text 2041, plus the time penalty)
//   chain / glints / boost / x2 ... 12647-12661: HUD_MIN is true in the game, so the chain dots, glint count and BOOST / x2 POINTS texts are NOT shown (opts.hudMin = false shows them); SHIELD is always shown
//   perf strip .................... 12671-12685: "%d km/h   GAME %d fps  Q%d  WHERE %d of %d m ... rows .. SND .." along the bottom edge, green >= 50 fps, amber >= 35, red below
//   molecule bar .................. 12686: molmesh.js drawMolBar (the slots, arcs, names, perks, "N OF 6", "ONE MORE!", "ALL SIX")
//   FLOW .......................... 12689: "FLOW xN.N" with its clock bar (hidden while hudMin)
//   finish screen ................. 12729: FINISH, RACE / FREESTYLE line, best, goals / poles / rails / jumps / flow / crashes, "press R, SPACE or tap to ride again" after 1.2 s
//   pause ......................... 12756 / Downhill 3051: dim .9, "PAUSED", the fps line, the buttons; on a phone a pause button top right (RunRig _pause_rect 10941)
//   warm-up screen ................ 12492: solid blue, "GET READY", a bar
// NOT PORTED ON PURPOSE (eye tracking, which the user keeps out): the calibration dot (_draw_calib), look cards, the next-pole arrows, feature rings that fill while a look settles, the gaze reticle,
// the set-up guide icons, the eye status text, beacons, the eyebrow hint, the face challenge, the TRACE test and the tracking-monitor pause screen.
//
// FONT: Godot draws with ThemeDB.fallback_font (Open Sans SemiBold, bundled with the engine). The closest web-safe stack, used here:  600 <size>px "Open Sans","Segoe UI",system-ui,-apple-system,Roboto,"Helvetica Neue",Arial,sans-serif
//
// USE:  const HUD = createHud({ document, project: (x, y, z) => ({ x, y, behind }), onPauseButton: (id) => {...}, touch: false });
//       HUD.toast('MATCH', [1, .5, .9]);  HUD.cheer('BLAST!', [1, .6, 1], 1.6);  HUD.pop([x, y, z], [1, .5, 0], '+60');
//       every frame:  HUD.update(dt, state)   (state: see the field list in update())
import { drawMolBar } from './molmesh.js';

const FONT = '"Open Sans","Segoe UI",system-ui,-apple-system,Roboto,"Helvetica Neue",Arial,sans-serif';
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const rgba = (c, a = 1) => 'rgba(' + Math.round(clamp(c[0], 0, 1) * 255) + ',' + Math.round(clamp(c[1], 0, 1) * 255) + ',' + Math.round(clamp(c[2], 0, 1) * 255) + ',' + clamp(a, 0, 1).toFixed(3) + ')';
export const clockText = (t) => Math.floor(t / 60) + ':' + (((t % 60) + 60) % 60).toFixed(1).padStart(4, '0');          // "%d:%04.1f"
const CHAIN_COL = [[.95, .4, 1], [1, .55, .1], [.9, .95, 1], [1, .88, .3]];          // _chain_color (4372)

export function createHud(o = {}) {
  const doc = o.document || (typeof document !== 'undefined' ? document : null);
  const cv = doc.createElement('canvas'); cv.style.cssText = 'position:fixed;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:7'; doc.body.appendChild(cv);
  const ctx = cv.getContext('2d'); const S = { w: 960, h: 540, dpr: 1 };
  const H = { hudMin: o.hudMin !== false, touch: !!o.touch, perf: o.perf !== false, buttons: o.buttons || [['resume', 'RESUME'], ['restart', 'RESTART RUN']], onButton: o.onButton || null };
  const st = { age: 0, flash: 0, popA: 0, popCol: [1, 1, 1], toasts: [], pops: [], btnRects: [], pauseRect: null };
  function resize(w, h, dpr) { S.dpr = dpr || (typeof devicePixelRatio !== 'undefined' ? Math.min(devicePixelRatio, 2) : 1); S.w = w || (typeof innerWidth !== 'undefined' ? innerWidth : 960); S.h = h || (typeof innerHeight !== 'undefined' ? innerHeight : 540); cv.width = Math.round(S.w * S.dpr); cv.height = Math.round(S.h * S.dpr); }
  resize(o.width, o.height, o.dpr);
  if (typeof addEventListener !== 'undefined' && !o.noResizeListener) addEventListener('resize', () => resize());

  // ---- text (Downhill _text / _ctext): a black outline, then the fill; widths remembered like Godot's _tw cache
  const tw = new Map();
  const font = (fs) => '600 ' + fs + 'px ' + FONT;
  function width(text, fs) { const key = fs + '|' + text; let w = tw.get(key); if (w === undefined) { if (tw.size > 600) tw.clear(); ctx.font = font(fs); w = ctx.measureText(text).width; tw.set(key, w); } return w; }
  let K = 1;
  function text(x, y, t, size, col, a = 1) { const fs = Math.max(1, Math.floor(size * K)); ctx.font = font(fs); ctx.textAlign = 'left'; ctx.lineJoin = 'round'; ctx.lineWidth = fs >= 30 ? 7 : 3; ctx.strokeStyle = 'rgba(0,0,0,0.9)'; ctx.strokeText(t, x, y); ctx.fillStyle = rgba(col, a); ctx.fillText(t, x, y); }
  function ctext(y, t, size, col, a = 1) { const fs = Math.max(1, Math.floor(size * K)), w = width(t, fs); text(S.w * 0.5 - w * 0.5, y, t, size, col, a); }
  const rect = (x, y, w, h, c, a) => { ctx.fillStyle = rgba(c, a); ctx.fillRect(x, y, w, h); };
  const frame = (x, y, w, h, c, a, lw) => { ctx.strokeStyle = rgba(c, a); ctx.lineWidth = lw; ctx.strokeRect(x, y, w, h); };
  const circle = (x, y, r, c, a) => { ctx.fillStyle = rgba(c, a); ctx.beginPath(); ctx.arc(x, y, Math.max(0, r), 0, Math.PI * 2); ctx.fill(); };
  const arc = (x, y, r, a0, a1, c, a, lw) => { ctx.strokeStyle = rgba(c, a); ctx.lineWidth = lw; ctx.beginPath(); ctx.arc(x, y, Math.max(0, r), a0, a1); ctx.stroke(); };
  const line = (x0, y0, x1, y1, c, a, lw) => { ctx.strokeStyle = rgba(c, a); ctx.lineWidth = lw; ctx.lineCap = 'butt'; ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke(); };
  const poly = (pts, c, a) => { ctx.fillStyle = rgba(c, a); ctx.beginPath(); pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]))); ctx.closePath(); ctx.fill(); };

  // ---- events from the game
  // _toast (Downhill 1308): "info" is one message at a time and never the same twice in a row; "ach" is small in the corner; "face" is the loud one
  function toast(t, col = [1, 1, 1], kind = 'info') {
    if (kind === 'info') { for (const q of st.toasts) if (q.kind === 'info') { if (q.text === t && q.t > 0) return; q.t = 0; } }
    st.toasts.push({ text: t, color: col, t: kind === 'info' ? 2.4 : (kind === 'ach' ? 3.0 : 2.0), kind }); if (st.toasts.length > 5) st.toasts.shift();
  }
  function cheer(t, col = [1, 1, 1], size = 1) { toast(t, col); st.flash = Math.max(st.flash, 0.25 * size); return { size, fovPunch: 6 * size, trip: 0.04 * size, ringRadius: 7 + 5 * size, confetti: Math.floor(50 * size), burst: Math.floor(30 * size) }; }          // _cheer (3959): the rest is the game's
  function flash(a) { st.flash = Math.max(st.flash, a); }
  function pop(p, col, text) { st.popA = 1; st.popCol = col; st.pops.push({ p, col, t: 0, text }); }          // _buff_pop (4561)

  // ---- one frame
  // state fields (all optional): kmh, score, progress 0..1, distance m, finishZ (m, positive), shield bool, boostT, multT, hurtT 0..1, flashJourney {a, col}, cueTint {a, col}, snowball 0..1,
  //   speedG (Godot m/s, for the speed lines), rampCharge 0..1, chain {n, groove, flowT, flowWindow, flowBump, step, lvl, t, window}, glints, race bool, runT, timePen, paused bool, warming {k} | null,
  //   mol { got[6], felt[6], held[6], pop[6], hurtI, hurtT, dmtOn }, perf { fps, tier, where, of, region, zone, world, alt, rows, chunks, next, queue, snd, music, cam }, finish { ... }, portrait bool
  function update(dt, s = {}) {
    st.age += dt; st.flash = Math.max(st.flash - 2 * dt, 0); st.popA = Math.max(st.popA - 2.4 * dt, 0);
    for (const q of st.toasts) q.t -= dt; while (st.toasts.length && st.toasts[0].t <= 0) st.toasts.shift();
    for (const p of st.pops) p.t += dt; while (st.pops.length && st.pops[0].t > 0.85) st.pops.shift();
    const dpr = S.dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, S.w, S.h);
    const W = S.w, Hh = S.h, portrait = s.portrait !== undefined ? s.portrait : Hh > W * 1.05; K = portrait ? 2.0 : (H.touch ? 1.25 : 1.0); const k = K, m = 24 * k, age = st.age;
    if (s.warming) { rect(0, 0, W, Hh, [.06, .09, .2], 1); const bw0 = Math.min(W * 0.4, 460 * k), bx = W * 0.5 - bw0 * 0.5, by = Hh * 0.62; ctext(by - 26 * k, 'GET READY', 34, [1, 1, 1], .95); rect(bx, by, bw0, 12 * k, [.05, .12, .25], .6); rect(bx, by, bw0 * clamp(s.warming.k || 0, 0, 1), 12 * k, [1, .85, .35], .95); return; }
    if (s.nohud) return;
    if (s.flashJourney && s.flashJourney.a > 0) rect(0, 0, W, Hh, s.flashJourney.col || [1, 1, 1], s.flashJourney.a * 0.30);
    if (s.snowball > 0.02) { rect(0, 0, W, Hh, [.9, .15, .1], 0.16 * s.snowball * (0.7 + 0.3 * Math.sin(age * 14))); text(W * 0.5 - 150 * k, Hh - 40 * k, 'SNOWBALL BEHIND YOU', 22, [1, .85, .8], 0.9 * s.snowball); }
    if (s.cueTint && s.cueTint.a > 0) rect(0, 0, W, Hh, s.cueTint.col || [1, 1, 1], 0.07 * s.cueTint.a);
    if (s.hurtT > 0) rect(0, 0, W, Hh, [1, .1, .1], 0.22 * clamp(s.hurtT, 0, 1));
    if (st.flash > 0) rect(0, 0, W, Hh, [1, 1, 1], 0.3 * st.flash);
    // pops (12097)
    if (st.popA > 0) for (let i = 0; i < 7; i++) { const g = i * 10 * k; frame(g, g, W - 2 * g, Hh - 2 * g, st.popCol, st.popA * (0.2 - 0.026 * i), 12 * k); }
    for (const pp of st.pops) {
      const pr = o.project ? o.project(pp.p[0], pp.p[1], pp.p[2]) : null; if (!pr || pr.behind) continue; const u = clamp(pp.t / 0.8, 0, 1), e = 1 - Math.pow(1 - u, 3), c2 = pp.col, sx = pr.x, sy = pr.y;
      arc(sx, sy, (14 + 120 * e) * k, 0, Math.PI * 2, c2, 1 - u, 5 * k * (1 - u) + 1);
      for (let ri = 0; ri < 10; ri++) { const ang = ri * Math.PI * 2 / 10 + 0.3, dx = Math.cos(ang), dy = Math.sin(ang); line(sx + dx * (20 + 90 * e) * k, sy + dy * (20 + 90 * e) * k, sx + dx * (30 + 150 * e) * k, sy + dy * (30 + 150 * e) * k, [1, 1, .9], 1 - u, 3 * k * (1 - u) + 1); }
      text(sx - 18 * k, sy + (-24 - 40 * e) * k, String(pp.text), 18, [c2[0] * .4 + .6, c2[1] * .4 + .6, c2[2] * .4 + .6], 1 - u * u);
    }
    // the ramp charge (11720)
    if (s.rampCharge > 0.02) { const bw = 180 * k, bx = W * 0.5 - bw * 0.5, by = Hh * 0.8; rect(bx, by, bw, 14 * k, [.05, .1, .2], .6); rect(bx, by, bw * s.rampCharge, 14 * k, [1, .7 + .25 * s.rampCharge, .2], .95); ctext(by - 8 * k, s.rampCharge < 0.95 ? 'pop at the lip' : 'FULL CHARGE', 16, [1, 1, 1], .8); }
    // speed lines (12521)
    const spf = clamp(((s.speedG !== undefined ? s.speedG : (s.kmh || 0) / 3.6) - 26) / 40, 0, 1);
    if (spf > 0.02) { const cx0 = W * 0.5, cy0 = Hh * 0.5 + Hh * 0.04, rmax = Math.hypot(W, Hh) * 0.5; for (let i = 0; i < 30; i++) { const a = i * 2.399963 + Math.floor(age * 3 + i * 0.37) * 1.3, f = (((age * (1.3 + 0.07 * (i % 5)) + i * 0.173) % 1) + 1) % 1, r0 = (0.42 + (0.95 - 0.42) * f) * rmax, r1 = r0 + (0.03 + 0.12 * f) * rmax * (0.5 + spf), dx = Math.cos(a), dy = Math.sin(a); line(cx0 + dx * r0, cy0 + dy * r0, cx0 + dx * r1, cy0 + dy * r1, [1, 1, 1], 0.22 * spf * f, 2 * k); } }
    // progress bar, score (12636-12645)
    const bw = Math.min(W * 0.34, 420 * k), bx = W * 0.5 - bw * 0.5; rect(bx, 6 * k, bw, 4 * k, [.05, .12, .25], .35); rect(bx, 6 * k, bw * clamp(s.progress || 0, 0, 1), 4 * k, [1, .85, .3], .8);
    if (s.race) { text(m, m + 22 * k, clockText(s.runT || 0), 26, [1, 1, 1], .95); if (s.timePen) text(m + 96 * k, m + 22 * k, (s.timePen > 0 ? '+' : '') + Math.trunc(s.timePen) + ' s', 18, s.timePen > 0 ? [1, .5, .4] : [.5, 1, .6], .95); }
    else text(m, m + 22 * k, String(Math.floor(s.score || 0)), 26, [1, 1, 1], .95);
    if (!H.hudMin && s.chain) drawChain(s.chain, W, k, m);
    if (!H.hudMin && s.glints > 0) { const gx = m + 9 * k, gy = m + 47 * k; poly([[gx, gy - 9 * k], [gx + 8 * k, gy], [gx, gy + 9 * k], [gx - 8 * k, gy]], [1, .82, .25], .95); text(m + 24 * k, m + 54 * k, String(s.glints), 22, [1, .9, .5], .95); }
    let by2 = m + 84 * k;
    if (!H.hudMin && s.boostT > 0) { text(m, by2, 'BOOST ' + s.boostT.toFixed(1), 15, [1, .55, .1]); by2 += 20 * k; }
    if (!H.hudMin && s.multT > 0) { text(m, by2, 'x2 POINTS ' + s.multT.toFixed(1), 15, [.95, .4, 1]); by2 += 20 * k; }
    if (s.shield) text(m, by2, 'SHIELD', 15, [.3, .85, 1]);
    // the perf strip along the bottom edge (12671)
    if (H.perf && s.perf) {
      const p = s.perf, gf = Math.round(p.fps || 0); let pt = Math.trunc(s.kmh || 0) + ' km/h     GAME ' + gf + ' fps'; if (p.cam) pt += '   CAM ' + p.cam; pt += '   Q' + (p.tier || 0);
      pt += '   WHERE ' + Math.trunc(p.where || 0) + ' of ' + Math.trunc(p.of || 0) + ' m  ' + (p.region || '-') + '/' + (p.zone || '-') + '  ' + (p.world || '-') + '  alt ' + (p.alt || 0).toFixed(0);
      pt += '   rows ' + (p.rows || 0) + ' chunks ' + (p.chunks || 0) + ' next ' + (p.next || 0) + ' queue ' + (p.queue || 0); pt += '   SND ' + (p.snd || 0) + ' ' + (p.music || '-');
      const col = gf >= 50 ? [.6, 1, .6] : (gf >= 35 ? [1, .85, .3] : [1, .4, .35]); const fs = Math.floor(18 * k); text(W * 0.5 - width(pt, fs) * 0.5, Hh - m * 0.6, pt, 18, col);
    }
    // the molecule bar (12686)
    if (s.mol) { const state = Object.assign({ age }, s.mol); drawMolBar(ctx, W, state, { k, m }); }
    // FLOW (12689)
    if (!H.hudMin && s.chain && s.chain.n > 0) { const c = s.chain, fsz = 26 + Math.floor(8 * (c.flowBump || 0)), t = c.flowBump || 0, fcol = [1 + (1 - 1) * t, .85 + .15 * t, .3 + .7 * t], fy = Hh - m - 84 * k, fw = 150 * k, left = clamp((c.flowT || 0) / Math.max(c.flowWindow || 5, 0.1), 0, 1), low = left < 0.3; text(m, fy, 'FLOW x' + (c.groove || 1).toFixed(1), fsz, fcol, .95); rect(m, fy + 8 * k, fw, 9 * k, [.05, .1, .2], .6); rect(m, fy + 8 * k, fw * left, 9 * k, low && Math.floor(age * 8) % 2 === 0 ? [1, .35, .25] : [1, .85, .3], .95); }
    // toasts (12712-12728)
    let ty = Hh * 0.40, ay = Hh - m - 54 * k, anyFace = false; for (const q of st.toasts) if (q.kind === 'face') anyFace = true;
    for (const q of st.toasts) { const a2 = clamp(q.t / 0.5, 0, 1); if (q.kind === 'face') ctext(Hh * 0.32, q.text, 44, q.color, a2); else if (q.kind === 'ach') { text(m, ay, q.text, 15, q.color, a2 * 0.8); ay -= 20 * k; } else if (a2 > 0 && !anyFace) { ctext(ty, q.text, 20, q.color, a2 * 0.85); ty += 26 * k; } }
    // finish (12729)
    if (s.finish) drawFinish(s.finish, W, Hh, k);
    // pause button on a phone, the pause screen (12756)
    st.pauseRect = null; st.btnRects = [];
    if (!s.paused) { if (H.touch) { const pw = Math.max(150 * k, W * 0.16), ph = Math.max(110 * k, Hh * 0.22), px = W - pw; st.pauseRect = { x: px, y: 0, w: pw, h: ph }; rect(px, 0, pw, ph, [.05, .12, .25], .5); rect(px + pw * 0.32, ph * 0.25, pw * 0.12, ph * 0.5, [1, 1, 1], .9); rect(px + pw * 0.56, ph * 0.25, pw * 0.12, ph * 0.5, [1, 1, 1], .9); } }
    else drawPause(s, W, Hh, k);
    if (s.coach && s.coach.t > 0) { const ca = clamp(s.coach.t / 0.6, 0, 1); ctext(Hh - m - 8 * k, s.coach.text, 15, s.coach.good ? [.5, 1, .6] : [1, .85, .4], ca * 0.75); }
  }
  function drawChain(c, W, k, m) {          // _draw_chain (4409): four dots, the next one big and pulsing, a pip per level, a thin bar for the time left
    const cx0 = W * 0.5 - 60 * k, cy0 = m + 34 * k, age = st.age;
    for (let i = 0; i < 4; i++) { const col = CHAIN_COL[i], px = cx0 + i * 40 * k; if (i === c.step) { const rr = (11 + 2.5 * Math.sin(age * 8) + 5 * (c.flash || 0)) * k; circle(px, cy0, rr + 3 * k, [0, 0, 0], .6); circle(px, cy0, rr, col, 1); } else if (c.lvl > 0 && i < c.step) circle(px, cy0, 7 * k, col, .9); else circle(px, cy0, 7 * k, col, .3); }
    for (let li = 0; li < 4; li++) rect(cx0 + (li * 14 - 8) * k, cy0 + 20 * k, 11 * k, 5 * k, li < c.lvl ? [1, .85, .3] : [1, 1, 1], li < c.lvl ? .95 : .2);
    if (c.lvl > 0) { const fw = 120 * k; rect(cx0 - 10 * k, cy0 + 29 * k, fw, 3 * k, [1, 1, 1], .15); rect(cx0 - 10 * k, cy0 + 29 * k, fw * clamp((c.t || 0) / (c.window || 4), 0, 1), 3 * k, [1, .85, .3], .9); }
    if (c.target) { const pr = (24 + 4 * Math.sin(age * 8)) * k, col = CHAIN_COL[c.step] || CHAIN_COL[3], tx = c.target.x, ty = c.target.y; arc(tx, ty, pr, 0, Math.PI * 2, [0, 0, 0], .6, 7 * k); arc(tx, ty, pr, 0, Math.PI * 2, col, .95, 4 * k); poly([[tx, ty - pr - 18 * k], [tx - 9 * k, ty - pr - 30 * k], [tx + 9 * k, ty - pr - 30 * k]], col, .95); }
  }
  function drawFinish(f, W, Hh, k) {          // the finish screen (12729)
    rect(0, 0, W, Hh, [.03, .07, .15], .55); ctext(Hh * 0.34, 'FINISH', 64, [1, .9, .4]); const y0 = Hh * 0.34;
    if (f.trail !== false) {
      const mine = f.race ? clockText((f.runT || 0) + (f.timePen || 0)) : String(Math.floor(f.score || 0)); ctext(y0 + 56 * k, (f.race ? 'RACE   ' + mine : 'FREESTYLE   ' + mine + ' points'), 34, [1, 1, 1]);
      let sub = ''; if (f.newBest) sub = 'NEW BEST!'; else if (f.bestVal > 0) sub = 'best ' + (f.race ? clockText(f.bestVal) : String(Math.trunc(f.bestVal))); if (f.race && f.timePen) sub += '   (' + (f.timePen > 0 ? '+' : '') + Math.trunc(f.timePen) + ' s from poles and goals)';
      if (sub) ctext(y0 + 96 * k, sub, 24, f.newBest ? [.5, 1, .6] : [1, 1, 1], f.newBest ? 1 : .8);
      ctext(y0 + 126 * k, 'goals ' + (f.goalsDone || 0) + '/' + (f.goalsTotal || 0) + '   poles ' + (f.polesClean || 0) + ' (shaved ' + (f.polesShaved || 0) + ')   rails ' + (f.railsDone || 0) + '   jumps ' + (f.jumpsDone || 0) + '   best flow x' + (f.bestFlow || 1).toFixed(1) + '   crashes ' + (f.crashes || 0), 18, [1, 1, 1], .75);
      if (!f.race) ctext(y0 + 150 * k, 'time ' + clockText(f.runT || 0), 16, [1, 1, 1], .55); if (f.choiceSummary) ctext(y0 + 214 * k, f.choiceSummary, 16, [.6, .95, 1], .9);
    } else { ctext(y0 + 56 * k, 'time ' + (f.runT || 0).toFixed(1) + ' s   crashes ' + (f.crashes || 0) + '   score ' + Math.floor(f.score || 0), 30, [1, 1, 1]); if (!f.crashes) ctext(y0 + 98 * k, 'CLEAN RUN +1000', 28, [.5, 1, .6]); }
    if ((f.endT || 0) > 1.2) ctext(y0 + 184 * k, 'press R, SPACE or tap to ride again', 22, [1, 1, 1], .85);
  }
  function drawPause(s, W, Hh, k) {          // Downhill _draw_pause_simple (3051)
    rect(0, 0, W, Hh, [.03, .07, .15], .9); ctext(Hh * 0.14, 'PAUSED', 46, [1, 1, 1]); ctext(Hh * 0.14 + 40 * k, 'GAME ' + Math.round((s.perf && s.perf.fps) || 0) + ' fps', 18, [1, 1, 1], .7);
    const bw = Math.min(W * 0.8, 560 * k), bh = 38 * k; let y = Hh * 0.26;
    for (const b of H.buttons) { const r = { id: b[0], x: (W - bw) * 0.5, y, w: bw, h: bh }; rect(r.x, r.y, r.w, r.h, b[0] === 'resume' ? [.2, .5, .9] : [1, 1, 1], b[0] === 'resume' ? .95 : .14); const fs = Math.floor(24 * k), w = width(b[1], fs); text(r.x + (bw - w) * 0.5, r.y + bh * 0.66, b[1], 24, [1, 1, 1]); st.btnRects.push(r); y += bh + 9 * k; }
  }
  // a tap: returns the id of the pause-screen button or 'pause' for the phone's pause button (the game decides what to do)
  function hit(x, y) { for (const r of st.btnRects) if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) return r.id; const p = st.pauseRect; if (p && x >= p.x && x <= p.x + p.w && y >= p.y && y <= p.y + p.h) return 'pause'; return null; }
  return { canvas: cv, ctx, update, toast, cheer, flash, pop, hit, resize, state: st, opts: H, FONT, clockText };
}
