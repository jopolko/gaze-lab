class_name GazeCamJS
extends RefCounted
## Browser-side face tracking, injected only when the player asks for camera
## control. Loads MediaPipe Face Landmarker from a CDN on demand (so it costs
## nothing on first load), opens the front camera, and publishes
## window.__gaze every video frame. Video never leaves the device.
##
## Published fields: x,y (gaze guess), conf, blink_l, blink_r, mouth, brows,
## nx (nose x, mirrored so + = your right), fw (face width = distance proxy).
## NOTE: written without access to a real camera; tune GAIN / flip signs with F8.

const SHARED := """
  const GAIN = 2.4;
  const IRIS_GAIN_X = 3.4;
  const IRIS_GAIN_Y = 3.0;
  // Environment (screen, window, profile): read from the page on the main thread, sent to the worker otherwise. The shared code below never touches window / screen / document.
  let ENV = null, qs = null, PROF = null, coarse = false, HFOV = 66, FLIPX = false, FLIPY = false;
  function applyEnv(e) {
    ENV = e; qs = new URLSearchParams(e.search || ''); PROF = e.PROF || null; coarse = !!e.coarse;
    HFOV = parseFloat(qs.get('hfov')) || (PROF && PROF.hfov > 40 && PROF.hfov < 120 ? PROF.hfov : 66);
    FLIPX = qs.has('flipx'); FLIPY = qs.has('flipy');
  }
  let yawRef = null, pitchRef = null, frameN = 0;
  // physical screen size (cm) in the CURRENT orientation. Phones: ~63 CSS px per cm. Desktop: 34 cm wide unless ?sw=
  const screenCm = () => {
    const sw = qs.get('sw') ? parseFloat(qs.get('sw')) : (PROF && PROF.scrW >= 4 && PROF.scrW <= 150 ? PROF.scrW : (coarse ? ENV.sw / 63 : 34));
    const ar = (ENV.sw > 0 && ENV.sh > 0) ? ENV.sh / ENV.sw : 9 / 16;
    return [sw, (coarse && !(PROF && PROF.scrW)) ? (ENV.sh > 0 ? ENV.sh / 63 : sw * ar) : sw * ar];
  };
  // where the camera sits relative to the screen, as fractions of the screen (portrait: top centre; landscape phone: left or right edge)
  const camPos = () => {
    if (!coarse) return [0.5, -0.03];
    const t = ENV.orient || 'portrait-primary';
    if (t.indexOf('landscape') === 0) return t === 'landscape-primary' ? [-0.02, 0.5] : [1.02, 0.5];
    return [0.5, -0.02];
  };
  // Calibration-free gaze: depth from iris size (11.7 mm), eyeball centre = eye-corner midpoint pushed back
  // along the head's facing direction, gaze = eyeball centre -> iris centre, intersected with the screen plane.
  function geo(L, mm, W, H, ov) {
    const fpx = (W / 2) / Math.tan(HFOV * Math.PI / 360), cx = W / 2, cy = H / 2;
    const P = (i) => [L[i].x * W, L[i].y * H];
    const ringR = (c, idx) => { const a = P(c); let t = 0; for (const i of idx) { const b = P(i); t += Math.hypot(b[0] - a[0], b[1] - a[1]); } return t / idx.length; };
    const rad = ringR(468, [469, 470, 471, 472]) + ringR(473, [474, 475, 476, 477]);   // = 2 x mean iris radius, px
    if (!(rad > 4)) return { ok: false };
    const Zi = fpx * 1.17 / rad;
    let back = [0, 0, 1];
    if (mm) { const n = Math.hypot(mm[8], mm[9], mm[10]) || 1; back = [-mm[8] / n, mm[9] / n, mm[10] / n]; }
    const eye = (iris, o, i) => {
      const c = (ov && ov[iris === 468 ? 0 : 1]) || P(iris), a = P(o), b = P(i);   // ov: sub-pixel limbus centres
      const I = [(c[0] - cx) * Zi / fpx, (c[1] - cy) * Zi / fpx, Zi];
      const M = [((a[0] + b[0]) / 2 - cx) * Zi / fpx, ((a[1] + b[1]) / 2 - cy) * Zi / fpx, Zi + 0.25];
      const E = [M[0] + back[0] * 1.05, M[1] + back[1] * 1.05, M[2] + back[2] * 1.05];
      const g = [I[0] - E[0], I[1] - E[1], I[2] - E[2]], gl = Math.hypot(g[0], g[1], g[2]) || 1;
      return { E, g: [g[0] / gl, g[1] / gl, g[2] / gl] };
    };
    const r1 = eye(468, 33, 133), r2 = eye(473, 362, 263);
    const O = [0, 1, 2].map((k) => (r1.E[k] + r2.E[k]) / 2);
    const Gs = [0, 1, 2].map((k) => r1.g[k] + r2.g[k]), gl = Math.hypot(Gs[0], Gs[1], Gs[2]) || 1;
    const G = Gs.map((v) => v / gl);
    if (G[2] > -0.05) return { ok: false };
    const t = O[2] / -G[2], Px = O[0] + G[0] * t, Py = O[1] + G[1] * t;
    const sc = screenCm(), cp = camPos();
    let u = cp[0] + (-Px) / sc[0], v = cp[1] + Py / sc[1];
    const eu = [], ev = [];
    for (const re of [r1, r2]) {
      if (re.g[2] > -0.05) { eu.push(NaN); ev.push(NaN); continue; }
      const tt = re.E[2] / -re.g[2];
      let ue = cp[0] + (-(re.E[0] + re.g[0] * tt)) / sc[0], ve = cp[1] + (re.E[1] + re.g[1] * tt) / sc[1];
      if (FLIPX) ue = 1 - ue;
      if (FLIPY) ve = 1 - ve;
      eu.push(ue); ev.push(ve);
    }
    if (FLIPX) u = 1 - u;
    if (FLIPY) v = 1 - v;
    return { ok: true, eu: eu, ev: ev, u, v, gyaw: Math.atan2(G[0], -G[2]), gpitch: Math.atan2(G[1], -G[2]) };
  }

// EyeFuse: automatic per-eye calibration and weighting, learned from normal use (no targets, no keys).
// Glasses (and anatomy) distort each eye's reading differently. For each eye we keep a window of its recent horizontal / vertical gaze values and learn:
//   * its centre (the median of the window)
//   * its per-side gains: the left and right (top and bottom) excursions are equalised to their mean, so an eye that responds weakly to one side is boosted there
//   * a weight: how strong (range / fixation noise) and how symmetric the eye's response is. The more normal-looking eye dominates the blend.
// Safe by design: gains stay within 0.6..2.5, change slowly, and only update while the window shows real excursions (range well above the noise).
class EyeFuse {
  constructor() {
    this.u = { R: [], L: [] }; this.v = { R: [], L: [] };
    this.last = 0; this.ready = false; this.info = '';
    this.c = { R: { u: 0, v: 0 }, L: { u: 0, v: 0 } };
    this.g = { R: { gl: 1, gr: 1, gt: 1, gb: 1 }, L: { gl: 1, gr: 1, gt: 1, gb: 1 } };
    this.w = { u: [0.5, 0.5], v: [0.5, 0.5] };
  }
  static stats(a) {
    const b = a.slice().sort((x, y) => x - y), n = b.length, q = (p) => b[Math.min(n - 1, Math.max(0, Math.floor((n - 1) * p)))];
    const stds = [];
    for (let i = Math.max(0, n - 180) + 0; i + 12 <= a.length; i += 12) {
      let m = 0; for (let j = 0; j < 12; j++) m += a[i + j]; m /= 12;
      let v = 0; for (let j = 0; j < 12; j++) v += (a[i + j] - m) * (a[i + j] - m);
      stds.push(Math.sqrt(v / 12));
    }
    stds.sort((x, y) => x - y);
    return { med: q(0.5), p5: q(0.05), p95: q(0.95), noise: stds.length ? Math.max(stds[Math.floor(stds.length / 2)], 0.002) : 0.01 };
  }
  push(uR, uL, vR, vL, t) {
    if (![uR, uL, vR, vL].every(isFinite)) return;
    const put = (arr, x) => { arr.push(x); if (arr.length > 900) arr.shift(); };
    put(this.u.R, uR); put(this.u.L, uL); put(this.v.R, vR); put(this.v.L, vL);
    if (t - this.last >= 1000 && this.u.R.length >= 150) { this.last = t; this.update(); }
  }
  update() {
    const ks = ['R', 'L'], sc = { u: [0, 0], v: [0, 0] }, det = {};
    const lerp = (a, b, r) => a + (b - a) * r;
    const clampG = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
    for (let i = 0; i < 2; i++) {
      const k = ks[i];
      for (const ax of ['u', 'v']) {
        const st = EyeFuse.stats(this[ax][k]);
        this.c[k][ax] = lerp(this.c[k][ax], st.med, this.ready ? 0.3 : 1);
        const dl = st.p5 - st.med, dr = st.p95 - st.med, range = dr - dl;
        const real = range > Math.max(0.04, 6 * st.noise) && dl < -0.01 && dr > 0.01;      // a real look to both sides, well above the noise
        if (real) {
          const H = (-dl + dr) / 2, gLo = clampG(H / -dl, 0.6, ax === 'u' ? 2.2 : 2.5), gHi = clampG(H / dr, 0.6, ax === 'u' ? 2.2 : 2.5);
          const kl = ax === 'u' ? 'gl' : 'gt', kh = ax === 'u' ? 'gr' : 'gb';
          this.g[k][kl] = lerp(this.g[k][kl], gLo, 0.2); this.g[k][kh] = lerp(this.g[k][kh], gHi, 0.2);
          const sym = Math.min(-dl, dr) / Math.max(-dl, dr);
          sc[ax][i] = (range / st.noise) * Math.sqrt(sym);
          det[k + ax] = { sym, snr: range / st.noise };
        }
      }
    }
    for (const ax of ['u', 'v']) {
      const q = sc[ax].map((x) => x * x), t = q[0] + q[1];
      // The weights come from short, noisy windows and swung wildly between runs: never trust one eye more than 80/20, and move slowly.
      if (t > 1e-9) { const target = q.map((x) => Math.max(0.2, Math.min(0.8, x / t))); this.w[ax] = [lerp(this.w[ax][0], target[0], 0.1), lerp(this.w[ax][1], target[1], 0.1)]; }
    }
    if (!this.ready && this.u.R.length >= 150) this.ready = true;
    const d = det.Ru && det.Lu;
    this.info = d ? ('eyes: right ' + Math.round(this.w.u[0] * 100) + '% (symmetry ' + det.Ru.sym.toFixed(2) + ', S/N ' + det.Ru.snr.toFixed(0) + ')  left ' + Math.round(this.w.u[1] * 100) + '% (symmetry ' + det.Lu.sym.toFixed(2) + ', S/N ' + det.Lu.snr.toFixed(0) + ')') : 'eyes: learning (look around the screen)';
  }
  map(uR, uL, vR, vL) {
    if (!this.ready || ![uR, uL, vR, vL].every(isFinite)) return null;
    let au = 0, wu = 0, av = 0, wv = 0;
    const raw = { R: [uR, vR], L: [uL, vL] };
    for (let i = 0; i < 2; i++) {
      const k = i === 0 ? 'R' : 'L', g = this.g[k];
      const xu = raw[k][0] - this.c[k].u, xv = raw[k][1] - this.c[k].v;
      au += this.w.u[i] * (0.5 + (xu < 0 ? g.gl : g.gr) * xu); wu += this.w.u[i];
      av += this.w.v[i] * (0.5 + (xv < 0 ? g.gt : g.gb) * xv); wv += this.w.v[i];
    }
    return { u: au / wu, v: av / wv };
  }
}

  const fuse = new EyeFuse();

  // ---- limbus ring fit (ported from EyeLab): finds the iris edge in the actual video pixels, sub-pixel.
  // MediaPipe's iris landmarks are only a starting guess and wobble by a pixel or more; this is what made EyeLab precise.
  function toGray(d, S) {
    const g = new Float32Array(S * S);
    for (let p = 0, q = 0; p < g.length; p++, q += 4) g[p] = 0.299 * d[q] + 0.587 * d[q + 1] + 0.114 * d[q + 2];
    return g;
  }
  function bil(a, S, x, y) {
    if (x < 0) x = 0; if (y < 0) y = 0; if (x > S - 1.001) x = S - 1.001; if (y > S - 1.001) y = S - 1.001;
    const x0 = x | 0, y0 = y | 0, fx = x - x0, fy = y - y0, i = y0 * S + x0;
    return a[i] * (1 - fx) * (1 - fy) + a[i + 1] * fx * (1 - fy) + a[i + S] * (1 - fx) * fy + a[i + S + 1] * fx * fy;
  }
  function limbusFit(gray, S, cx, cy, r0) {
    const sm = new Float32Array(S * S);
    for (let y = 1; y < S - 1; y++) for (let x = 1; x < S - 1; x++) {
      let t = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) t += gray[(y + dy) * S + x + dx];
      sm[y * S + x] = t / 9;
    }
    const gx = new Float32Array(S * S), gy = new Float32Array(S * S);
    for (let y = 1; y < S - 1; y++) for (let x = 1; x < S - 1; x++) {
      gx[y * S + x] = (sm[y * S + x + 1] - sm[y * S + x - 1]) * 0.5;
      gy[y * S + x] = (sm[(y + 1) * S + x] - sm[(y - 1) * S + x]) * 0.5;
    }
    const angs = [];
    for (let a = -55; a <= 55; a += 10) { angs.push(a * Math.PI / 180); angs.push((a + 180) * Math.PI / 180); }
    const STEP = 0.5, RNG = 3.0, n = Math.round(RNG * 2 / STEP) + 1;
    let best = -1e9, bi = 0, bj = 0, bestScores = null, bestR = r0;
    for (const dr of [-1.5, 0, 1.5]) {
      const rr = Math.max(2.5, r0 + dr);
      const scores = new Float32Array(n * n);
      for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
        const ccx = cx - RNG + i * STEP, ccy = cy - RNG + j * STEP;
        let sc = 0;
        for (const th of angs) {
          const px = ccx + rr * Math.cos(th), py = ccy + rr * Math.sin(th);
          sc += bil(gx, S, px, py) * Math.cos(th) + bil(gy, S, px, py) * Math.sin(th);
        }
        scores[j * n + i] = sc;
        if (sc > best) { best = sc; bi = i; bj = j; bestScores = scores; bestR = rr; }
      }
    }
    const at = (i, j) => bestScores[Math.max(0, Math.min(n - 1, j)) * n + Math.max(0, Math.min(n - 1, i))];
    const par = (m, c, p) => { const d = m - 2 * c + p; return Math.abs(d) < 1e-6 ? 0 : 0.5 * (m - p) / d * STEP; };
    const sx = par(at(bi - 1, bj), at(bi, bj), at(bi + 1, bj));
    const sy = par(at(bi, bj - 1), at(bi, bj), at(bi, bj + 1));
    return { x: cx - RNG + bi * STEP + sx, y: cy - RNG + bj * STEP + sy, r: bestR, score: best };
  }
  const cropMemo = {};
  // Face region: the worker only receives a crop around the face (about 4x fewer pixels to move, upload and read back), as an ImageBitmap whose
  // top-left is CROP.x, CROP.y in full-frame pixels. Full frame: CROP = {0, 0, huge, huge}. All landmarks are mapped back to full-frame coordinates before use.
  let CROP = { x: 0, y: 0, w: 1e9, h: 1e9 };
  let lastSide = 0, lastCx = 0, lastCy = 0;
  function nextRoi(L, W, H, cur) {
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (const q of L) { if (q.x < x0) x0 = q.x; if (q.x > x1) x1 = q.x; if (q.y < y0) y0 = q.y; if (q.y > y1) y1 = q.y; }
    x0 *= W; x1 *= W; y0 *= H; y1 *= H;
    const side = Math.max(x1 - x0, y1 - y0), cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    // (A "sanity reset to the whole frame" was tried here: it fired 68 times in a run and made things worse. Every switch between crop and full frame breaks the model's tracking.)
    const want = Math.round(Math.min(Math.min(W, H), Math.max(480, side * 1.9)) / 2) * 2;
    if (cur) {       // keep the same crop while the face stays well inside it: a moving crop makes the model search again
      const mg = 0.12 * cur.w;
      if (x0 > cur.x + mg && x1 < cur.x + cur.w - mg && y0 > cur.y + mg && y1 < cur.y + cur.h - mg && Math.abs(want - cur.w) < 0.3 * cur.w) return cur;
    }
    const rx = Math.max(0, Math.min(W - want, Math.round(cx - want / 2) & ~1)), ry = Math.max(0, Math.min(H - want, Math.round(cy - want / 2) & ~1));
    return { x: rx, y: ry, w: want, h: want };
  }
  // Read only the small crop around each eye straight from the video: copying the whole 1080p frame every time cost most of the frame budget.
  const cropCan = (typeof document !== 'undefined') ? document.createElement('canvas') : new OffscreenCanvas(1, 1);
  const cropCtx = cropCan.getContext('2d', { willReadFrequently: true });
  function grabCrop(vid, x0, y0, S) {
    if (cropCan.width !== S) { cropCan.width = S; cropCan.height = S; }
    cropCtx.drawImage(vid, x0 - CROP.x, y0 - CROP.y, S, S, 0, 0, S, S);
    return cropCtx.getImageData(0, 0, S, S).data;
  }
  // A window (x0, y0, S) out of an eye patch {pdata: RGBA bytes, x, y, w}: plain copying, no GPU readback.
  function grabFromPatch(p, x0, y0, S) {
    const out = new Uint8ClampedArray(S * S * 4);
    for (let j = 0; j < S; j++) {
      const so = ((y0 - p.y + j) * p.w + (x0 - p.x)) * 4;
      out.set(p.pdata.subarray(so, so + S * 4), j * S * 4);
    }
    return out;
  }
  // Where to cut the two eye patches for the NEXT frame: a square 2.3x the eye width around each iris (the fit window is 1.5x, the rest is room for the head to move).
  function eyePatches(L, W, H) {
    const out = [];
    for (const e of [[33, 133, 468], [362, 263, 473]]) {
      const cx = L[e[2]].x * W, cy = L[e[2]].y * H;
      const ew = Math.hypot((L[e[1]].x - L[e[0]].x) * W, (L[e[1]].y - L[e[0]].y) * H);
      const s = Math.min(Math.max(48, Math.round(ew * 2.3)), W, H);
      out.push({ x: Math.max(0, Math.min(W - s, Math.round(cx - s / 2))), y: Math.max(0, Math.min(H - s, Math.round(cy - s / 2))), s: s });
    }
    return out;
  }
  // Iris centre inside one eye, normalised to the eye box (0..1 across from the 'outer' landmark, 0..1 down from the top lid).
  function limbEye(L, gctx, W, H, outer, inner, top, bot, iris, ringIdx) {
    const P = (i) => ({ x: L[i].x * W, y: L[i].y * H });
    const o = P(outer), i = P(inner), tp = P(top), bt = P(bot), c = P(iris);
    let rad = 0;
    for (const idx of ringIdx) { const q = P(idx); rad += Math.hypot(q.x - c.x, q.y - c.y); }
    rad /= ringIdx.length;
    const wx = i.x - o.x, wy = bt.y - tp.y;
    if (!(rad > 2.5) || Math.abs(wx) < 6 || Math.abs(wy) < 2) return null;
    const eyeW = Math.hypot(wx, i.y - o.y);
    const S = Math.max(24, Math.round(eyeW * 1.5));
    if (S > W || S > H) return null;
    // Worker mode with eye patches: gctx.eyes = [patch of the first eye, patch of the second], each a small FULL-RESOLUTION square cut from the camera
    // just before the model finished, around where the eye was a moment ago. The fit window must lie inside it, else this frame uses the landmark gaze only.
    const pp = gctx && gctx.eyes ? gctx.eyes[outer === 33 ? 0 : 1] : null;
    if (gctx && gctx.eyes && !pp) return null;
    let x0, y0;
    if (pp) {
      x0 = Math.round(c.x - S / 2);
      y0 = Math.round(c.y - S / 2);
    } else {
      x0 = Math.max(CROP.x, Math.min(Math.min(W, CROP.x + CROP.w) - S, Math.round(c.x - S / 2)));
      y0 = Math.max(CROP.y, Math.min(Math.min(H, CROP.y + CROP.h) - S, Math.round(c.y - S / 2)));
    }
    const pc = cropMemo[outer];
    if (pc && pc.S === S && Math.abs(c.x - (pc.x0 + S / 2)) < 3 && Math.abs(c.y - (pc.y0 + S / 2)) < 3) { x0 = pc.x0; y0 = pc.y0; }   // hysteresis: a steady crop
    if (pp && (x0 < pp.x || y0 < pp.y || x0 + S > pp.x + pp.w || y0 + S > pp.y + pp.w)) return null;      // the eye moved out of its patch since it was cut
    cropMemo[outer] = { S: S, x0: x0, y0: y0 };
    const gray = toGray(pp ? grabFromPatch(pp, x0, y0, S) : grabCrop(gctx, x0, y0, S), S);      // gctx is the <video> / a bitmap on the old path
    const limb = limbusFit(gray, S, c.x - x0, c.y - y0, rad);
    // along the line between the eye corners (not along the image x axis): a rolled head must not turn an up/down glance or a squint into a sideways one
    const ux = wx / eyeW, uy = (i.y - o.y) / eyeW;
    const along = ((x0 + limb.x - o.x) * ux + (y0 + limb.y - o.y) * uy) / eyeW;
    return [along, (y0 + limb.y - tp.y) / wy, rad, x0 + limb.x, y0 + limb.y];
  }

  // One camera frame in, one packet out: landmarks -> blendshapes, head pose, limbus fit, geometry gaze, per-eye fusion, window mapping.
  // `src` is anything drawImage accepts (the <video> on the main thread, an ImageBitmap in the worker).
  function buildPacket(r, src, W, H) {
    if (!(r.faceBlendshapes && r.faceBlendshapes.length)) return { pkt: { conf: 0 }, pts: null };
    let pkt = null;
    const bs = {};
    for (const c of r.faceBlendshapes[0].categories) bs[c.categoryName] = c.score;
    const g = (k) => bs[k] || 0;
    const L = r.faceLandmarks[0];
    // Iris position inside each eye (relative to the eye corners / lids), so
    // head movement (used for walking) does not leak into the aim.
    let gx = 0.5, gy = 0.5;
    if (L.length > 473) {
      // across each eye measured along the line between its corners (pixel space), so head roll does not leak vertical iris movement into it
      const along = (c, o, i) => {
        const ax = (i.x - o.x) * W, ay = (i.y - o.y) * H, n2 = ax * ax + ay * ay || 1;
        return ((c.x - o.x) * W * ax + (c.y - o.y) * H * ay) / n2;
      };
      const rx = along(L[468], L[33], L[133]);
      const lx = along(L[473], L[362], L[263]);
      const ry = (L[468].y - L[159].y) / (L[145].y - L[159].y || 1);
      const ly = (L[473].y - L[386].y) / (L[374].y - L[386].y || 1);
      gx = 0.5 + (0.5 - (rx + lx) * 0.5) * IRIS_GAIN_X;
      gy = 0.5 + (((ry + ly) * 0.5) - 0.5) * IRIS_GAIN_Y;
    }
    const bh = ((g('eyeLookInLeft') + g('eyeLookOutRight')) - (g('eyeLookOutLeft') + g('eyeLookInRight'))) * 0.5;
    const bu = ((g('eyeLookUpLeft') + g('eyeLookUpRight')) - (g('eyeLookDownLeft') + g('eyeLookDownRight'))) * 0.5;
    const bx = 0.5 + bh * GAIN, by = 0.5 - bu * GAIN;
    let yaw = 0, pitch = 0, roll = 0;
    let gg = { ok: false };
    const mm = r.facialTransformationMatrixes && r.facialTransformationMatrixes[0] && r.facialTransformationMatrixes[0].data;
    if (mm) { yaw = Math.atan2(mm[8], mm[10]); pitch = Math.asin(Math.max(-1, Math.min(1, -mm[9]))); roll = Math.atan2(mm[1], mm[5]); }
    const rr = (a, b, c) => (L[a].x - L[b].x) / (L[c].x - L[b].x || 1);
    const vv = (a, t, bt) => (L[a].y - L[t].y) / (L[bt].y - L[t].y || 1);
    const feats = [
      rr(468, 33, 133), rr(473, 362, 263), vv(468, 159, 145), vv(473, 386, 374),
      g('eyeLookInLeft'), g('eyeLookOutLeft'), g('eyeLookUpLeft'), g('eyeLookDownLeft'),
      g('eyeLookInRight'), g('eyeLookOutRight'), g('eyeLookUpRight'), g('eyeLookDownRight'),
      yaw * 2.0, pitch * 2.0,
      g('eyeBlinkLeft'), g('eyeBlinkRight'),
      (L[145].y - L[159].y) / (Math.abs(L[133].x - L[33].x) || 1), (L[374].y - L[386].y) / (Math.abs(L[263].x - L[362].x) || 1),
      (L[468].y - L[159].y) / (Math.abs(L[133].x - L[33].x) || 1), (L[145].y - L[468].y) / (Math.abs(L[133].x - L[33].x) || 1),
      (L[473].y - L[386].y) / (Math.abs(L[263].x - L[362].x) || 1), (L[374].y - L[473].y) / (Math.abs(L[263].x - L[362].x) || 1)
    ];
    let lx, ly, lrad, ov = null;
    try {
      const e1 = limbEye(L, src, W, H, 33, 133, 159, 145, 468, [469, 470, 471, 472]);
      const e2 = limbEye(L, src, W, H, 362, 263, 386, 374, 473, [474, 475, 476, 477]);
      if (e1 && e2) { lx = (e1[0] + e2[0]) / 2; ly = (e1[1] + e2[1]) / 2; lrad = (e1[2] + e2[2]) / 2; ov = [[e1[3], e1[4]], [e2[3], e2[4]]]; }
    } catch (e) { /* the landmark gaze still works */ }
    gg = geo(L, mm, W, H, ov);
    let hu = 0, hv = 0, fused = false;
    if (gg.ok && PROF && (PROF.kyaw || PROF.kpitch)) {
      yawRef = yawRef === null ? yaw : yawRef + (yaw - yawRef) * 0.01; pitchRef = pitchRef === null ? pitch : pitchRef + (pitch - pitchRef) * 0.01;
      hu = (PROF.kyaw || 0) * (yaw - yawRef); hv = (PROF.kpitch || 0) * (pitch - pitchRef);
      gg.u += hu; gg.v += hv;
    }
    if (gg.ok && gg.eu) {
      fuse.push(gg.eu[0] + hu, gg.eu[1] + hu, gg.ev[0] + hv, gg.ev[1] + hv, performance.now());
      const fm = fuse.map(gg.eu[0] + hu, gg.eu[1] + hu, gg.ev[0] + hv, gg.ev[1] + hv);
      if (fm) { gg.u = fm.u; gg.v = fm.v; fused = true; }     // already centred on your own median look, per-eye gains and weights learned automatically
    }
    if (gg.ok && !coarse) {
      // gaze is measured against the MONITOR; the game draws in the browser WINDOW. Convert, so a window on one side of the monitor still maps onto your gaze.
      const sw = ENV.sw, sh = ENV.sh, iw = ENV.iw, ih = ENV.ih;
      if (sw > 0 && sh > 0 && iw > 0 && ih > 0) {
        if (fused) { gg.u = 0.5 + (gg.u - 0.5) * sw / iw; gg.v = 0.5 + (gg.v - 0.5) * sh / ih; }      // centred on your median look: only the scale changes
        else {
          const ox = ENV.wx || 0, oy = (ENV.wy || 0) + Math.max(0, (ENV.oh || 0) - ih);
          gg.u = (gg.u * sw - ox) / iw; gg.v = (gg.v * sh - oy) / ih;
        }
      }
    }
    const glimb = ov ? 1 : 0;

            pkt = {
      n: ++frameN, ew: fuse.ready ? [fuse.w.u[0], fuse.w.u[1]] : null, pp: (PROF && PROF.pose && isFinite(PROF.pose.pit)) ? [PROF.pose.pit, PROF.pose.yaw, PROF.pose.rol] : null, lx: lx, ly: ly, lrad: lrad, glimb: glimb,
      x: gx, y: gy, bx: bx, by: by, f: feats, gu: gg.ok ? gg.u : undefined, gv: gg.ok ? gg.v : undefined, hyaw: yaw, hpitch: pitch, hroll: roll, gyaw: gg.ok ? gg.gyaw : undefined, gpitch: gg.ok ? gg.gpitch : undefined, conf: 1.0,
      blink_l: g('eyeBlinkLeft'), blink_r: g('eyeBlinkRight'),
      mouth: g('jawOpen'), brows: g('browInnerUp'),
      smile: (g('mouthSmileLeft') + g('mouthSmileRight')) * 0.5, tongue: (bs.tongueOut !== undefined ? bs.tongueOut : -1), puff: g('cheekPuff'),
      frown: (g('mouthFrownLeft') + g('mouthFrownRight')) * 0.5, bdown: (g('browDownLeft') + g('browDownRight')) * 0.5,
      ewide: (g('eyeWideLeft') + g('eyeWideRight')) * 0.5, esq: (g('eyeSquintLeft') + g('eyeSquintRight')) * 0.5, pucker: g('mouthPucker'), sneer: (g('noseSneerLeft') + g('noseSneerRight')) * 0.5,
      nx: 1.0 - L[1].x, ny: L[1].y, fw: Math.abs(L[454].x - L[234].x)
    };
    const pts = [];
    for (const i of [468, 473, 1]) { if (L[i]) pts.push([L[i].x, L[i].y]); }
    return { pkt: pkt, pts: pts };
  }
"""
const GLUE := """
  // ---- worker side: owns the face model, receives camera frames as ImageBitmaps, posts packets back
  // The work is split over TWO workers so the face network (GPU) and our own gaze maths (CPU + reading eye pixels back) overlap instead of queueing:
  //   'model' runs the network, maps the landmarks to the full frame, tells the page where to crop next, and hands the landmarks + frame on;
  //   'build' turns landmarks into a gaze packet (limbus fit, per-eye fusion, head pose) and posts it to the page.
  // With ?oneworker they run in the same worker, one after the other.
  let lmw = null;
  let peer = null;
  let role = 'model';
  // Losing the face for a frame must NOT drop to the whole 1920x1080 frame: the model's face finder works on a tiny copy of the image, and at that size a normal face
  // is too small to find again (that is how a run ended up 76% lost). Instead the last crop is widened a little each missed frame, around where the face was.
  let lastRoi = null, lostN = 0;
  function recoverRoi(W, H) {
    lostN++;
    const cap = Math.min(W, H);
    const base = lastRoi || { x: Math.round((W - cap) / 2), y: 0, w: cap, h: cap };      // never seen yet: the biggest centred square
    if (lostN > 24 && lostN % 8 === 0) return null;                                       // now and then: the whole frame, in case you moved far
    const size = Math.min(cap, Math.round(base.w * (1 + 0.15 * lostN) / 2) * 2);
    const cx = base.x + base.w / 2, cy = base.y + base.h / 2;
    return { x: Math.max(0, Math.min(W - size, Math.round(cx - size / 2) & ~1)), y: Math.max(0, Math.min(H - size, Math.round(cy - size / 2) & ~1)), w: size, h: size };
  }
  const patchCan = new OffscreenCanvas(1, 1);
  const patchCtx = patchCan.getContext('2d', { willReadFrequently: true });
  function onBuild(d) {
    try {
      const tb0 = performance.now();
      applyEnv(d.env);
      CROP = d.roi ? { x: d.roi.x, y: d.roi.y, w: d.roi.w, h: d.roi.h } : { x: 0, y: 0, w: 1e9, h: 1e9 };
      const r = { faceLandmarks: d.lm ? [d.lm] : [], faceBlendshapes: d.bs ? [{ categories: d.bs }] : [], facialTransformationMatrixes: d.mx ? [{ data: d.mx }] : [] };
      let src = d.bmp;
      if (d.pa) {       // the two eye patches (small, full resolution): read their pixels once, here. Tiny readbacks instead of one big one.
        src = { eyes: d.pa.map((p) => {
          if (!p) return null;
          if (patchCan.width !== p.s || patchCan.height !== p.s) { patchCan.width = p.s; patchCan.height = p.s; }
          patchCtx.drawImage(p.bmp, 0, 0);
          return { pdata: patchCtx.getImageData(0, 0, p.s, p.s).data, x: p.x, y: p.y, w: p.s };
        }) };
      }
      const out = buildPacket(r, src, d.FW, d.FH);
      self.postMessage({ type: 'pkt', pkt: out.pkt, pts: out.pts, t: d.t, inf: d.det + (performance.now() - tb0), det: d.det });
    } catch (e) { self.postMessage({ type: 'frameerr', msg: String((e && e.message) || e) }); }
    finally {
      try { if (d.bmp) d.bmp.close(); } catch (e2) {}
      try { if (d.pa) for (const p of d.pa) { if (p && p.bmp) p.bmp.close(); } } catch (e3) {}
    }
  }
  self.onmessage = async (ev) => {
    const m = ev.data;
    if (m.type === 'peer') {
      if (role === 'build') { m.port.onmessage = (e) => onBuild(e.data); } else { peer = m.port; }
    } else if (m.type === 'init') {
      role = m.role || 'model';
      if (role === 'build') { applyEnv(m.env); self.postMessage({ type: 'ready' }); return; }
      try {
        applyEnv(m.env);
        const mod = await import(m.base + '/vision_bundle.mjs');
        const files = await mod.FilesetResolver.forVisionTasks(m.base + '/wasm');
        const opts = (d) => ({ baseOptions: { modelAssetPath: m.model, delegate: d }, runningMode: 'VIDEO', numFaces: 1, outputFaceBlendshapes: true, outputFacialTransformationMatrixes: true });
        let dlg = 'GPU';
        try { if (m.cpu) throw new Error('cpu requested'); lmw = await mod.FaceLandmarker.createFromOptions(files, opts('GPU')); }
        catch (e) { dlg = 'CPU'; lmw = await mod.FaceLandmarker.createFromOptions(files, opts('CPU')); }
        self.postMessage({ type: 'ready', dlg: dlg });
      } catch (e) { self.postMessage({ type: 'error', msg: String((e && e.message) || e) }); }
    } else if (m.type === 'frame') {
      try {
        const tw0 = performance.now();
        const r = lmw.detectForVideo(m.bmp, m.t);
        const det = performance.now() - tw0;
        const roi = m.roi || null;
        const FW = roi ? m.W : m.bmp.width, FH = roi ? m.H : m.bmp.height;
        let lm = null, bs = null, mx = null, nroi = null;
        if (r.faceLandmarks && r.faceLandmarks.length && r.faceBlendshapes && r.faceBlendshapes.length) {
          // landmarks come back relative to the crop: map them to the full frame (plain copies, so they can be posted to the other worker)
          const sx = roi ? roi.w / FW : 1;
          lm = r.faceLandmarks[0].map((q) => roi ? { x: (roi.x + q.x * roi.w) / FW, y: (roi.y + q.y * roi.h) / FH, z: q.z * sx } : { x: q.x, y: q.y, z: q.z });
          bs = r.faceBlendshapes[0].categories.map((c) => ({ categoryName: c.categoryName, score: c.score }));
          const t0 = r.facialTransformationMatrixes && r.facialTransformationMatrixes[0];
          mx = t0 && t0.data ? Array.from(t0.data) : null;
          if (!m.noroi) { nroi = nextRoi(lm, FW, FH, roi); if (nroi) { lastRoi = nroi; lostN = 0; } }
        } else if (!m.noroi) {
          nroi = recoverRoi(FW, FH);
        }
        // right away: the next frame can already use the new crop, and cut its eye patches where the eyes are now
        self.postMessage({ type: 'roi', roi: nroi, eyes: (lm && !m.noroi) ? eyePatches(lm, FW, FH) : null });
        const d = { lm: lm, bs: bs, mx: mx, bmp: m.pa ? null : m.bmp, pa: m.pa || null, t: m.t, env: m.env, roi: roi, FW: FW, FH: FH, det: det };
        if (m.pa) { try { m.bmp.close(); } catch (e0) {} }          // the (small) face copy has done its job; the build side only needs the eye patches
        if (peer) peer.postMessage(d, m.pa ? [m.pa[0].bmp, m.pa[1].bmp] : [m.bmp]); else onBuild(d);
      } catch (e) {
        self.postMessage({ type: 'frameerr', msg: String((e && e.message) || e) });
        try { m.bmp.close(); } catch (e2) {}
        try { if (m.pa) for (const p of m.pa) { if (p && p.bmp) p.bmp.close(); } } catch (e3) {}
      }
    }
  };
"""
const MAIN := """
  if (window.__gazeStart) return;
  window.__gaze = null;
  window.__gazeStatus = 'idle';
  window.__gazeStats = { pk: 0, cf: 0, drop: 0 };
  const BASE = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
  const MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';
  const coarseNow = matchMedia('(pointer: coarse)').matches;
  let PROFnow = null;
  try { const o = JSON.parse(localStorage.getItem('eyelab.profile') || 'null'); if (o && o.v === 1 && o.dev === ((screen.width || 0) + 'x' + (screen.height || 0) + '@' + (window.devicePixelRatio || 1))) PROFnow = o; } catch (e) {}
  window.__gazeProfile = PROFnow ? 1 : 0;
  const envNow = () => ({ search: location.search, PROF: PROFnow, coarse: coarseNow, sw: screen.width || 0, sh: screen.height || 0, iw: window.innerWidth, ih: window.innerHeight,
    wx: window.screenX || 0, wy: window.screenY || 0, oh: window.outerHeight, orient: (screen.orientation && screen.orientation.type) || 'portrait-primary' });
  applyEnv(envNow());
  window.__eyeFit = { limbusFit: limbusFit, toGray: toGray, geo: geo };


  // Release the camera (and the worker) when the page goes away (refresh, close, navigate) so everything is free for the next load.
  let worker = null;       // the model worker (also does everything when ?oneworker)
  let worker2 = null;      // the packet-building worker
  function stopAll() {
    try { const st = window.__gazeStream; if (st) st.getTracks().forEach((t) => t.stop()); } catch (e) {}
    window.__gazeStream = null;
    try { if (worker) { worker.terminate(); worker = null; } } catch (e) {}
    try { if (worker2) { worker2.terminate(); worker2 = null; } } catch (e) {}
    try { if (window.__gazePreview && window.__gazePreview.parentNode) window.__gazePreview.parentNode.removeChild(window.__gazePreview); } catch (e) {}
    window.__gazeRunning = false;
  }
  window.__gazeStop = stopAll;
  window.addEventListener('pagehide', stopAll);
  window.addEventListener('beforeunload', stopAll);
  // Start the tracker worker. Resolves true when the model is loaded in it, false when workers / the model cannot be used (then the old in-page path runs).
  function startWorker() {
    return new Promise((resolve) => {
      let done = false;
      const fin = (ok) => { if (!done) { done = true; resolve(ok); } };
      try {
        if (qs.has('noworker') || typeof Worker === 'undefined' || typeof createImageBitmap === 'undefined' || typeof OffscreenCanvas === 'undefined') { fin(false); return; }
        const url = URL.createObjectURL(new Blob([__WSRC], { type: 'text/javascript' }));
        worker = new Worker(url);
        worker2 = qs.has('oneworker') ? null : new Worker(url);
        let ready = 0;
        const need = worker2 ? 2 : 1;
        const onm = (ev) => { const m = ev.data; if (m.type === 'ready') { if (m.dlg) window.__gazeStats.dlg = m.dlg; if (++ready >= need) fin(true); } else if (m.type === 'error') { window.__gazeWorkerError = m.msg; fin(false); } };
        const one = (e) => { window.__gazeWorkerError = String(e && e.message || e); fin(false); };
        worker.onerror = one; worker.onmessage = onm;
        worker.postMessage({ type: 'init', role: 'model', env: envNow(), base: BASE, model: MODEL, cpu: qs.has('cpu') || (!qs.has('gpu') && !coarseNow) });   // laptops / desktops: the game owns the GPU, the face model runs on the CPU (?gpu to force the GPU; phones keep the GPU)
        if (worker2) {
          worker2.onerror = one; worker2.onmessage = onm;
          worker2.postMessage({ type: 'init', role: 'build', env: envNow() });
          const ch = new MessageChannel();
          worker.postMessage({ type: 'peer', port: ch.port1 }, [ch.port1]);
          worker2.postMessage({ type: 'peer', port: ch.port2 }, [ch.port2]);
        }
        setTimeout(() => fin(false), 30000);
      } catch (e) { window.__gazeWorkerError = String(e && e.message || e); fin(false); }
    });
  }
  window.__gazeCams = [];
  window.__gazeCamLabel = '';
  window.__gazeListCams = async function () {
    try {
      const ds = await navigator.mediaDevices.enumerateDevices();
      window.__gazeCams = ds.filter((d) => d.kind === 'videoinput').map((d, i) => ({ id: d.deviceId, label: d.label || ('camera ' + (i + 1)) }));
    } catch (e) { window.__gazeCams = []; }
    return window.__gazeCams;
  };
  try { navigator.mediaDevices.addEventListener('devicechange', () => { window.__gazeListCams(); }); } catch (e) {}
  // Switch camera: remember the choice, release everything and start again on that camera.
  window.__gazeUseCam = function (id) {
    try { localStorage.setItem('gazelab_cam', id); } catch (e) {}
    window.__gazeStatus = 'switching camera...';
    stopAll();
    window.__gazeRunning = false;
    setTimeout(() => { window.__gazeStart(); }, 150);
  };
  window.__gazeStart = async function () {
    if (window.__gazeRunning) return;
    window.__gazeRunning = true;
    try {
      window.__gazeStatus = 'loading tracker...';
      const workerOk = await startWorker();
      window.__gazeMode = workerOk ? 'worker' : 'page';
      let lm = null;
      if (!workerOk) {
        if (worker) { try { worker.terminate(); } catch (e) {} worker = null; }
        if (worker2) { try { worker2.terminate(); } catch (e) {} worker2 = null; }
        const mod = await import(BASE + '/vision_bundle.mjs');
        const files = await mod.FilesetResolver.forVisionTasks(BASE + '/wasm');
        const opts = (d) => ({ baseOptions: { modelAssetPath: MODEL, delegate: d }, runningMode: 'VIDEO', numFaces: 1, outputFaceBlendshapes: true, outputFacialTransformationMatrixes: true });
        try { lm = await mod.FaceLandmarker.createFromOptions(files, opts('GPU')); }
        catch (e) { lm = await mod.FaceLandmarker.createFromOptions(files, opts('CPU')); }
      }
      window.__gazeStatus = 'allow the camera...';
      const w = worker;               // stopAll() would terminate them: set them aside while old sessions are released
      const w2 = worker2;
      worker = null;
      worker2 = null;
      stopAll();
      worker = w;
      worker2 = w2;
      window.__gazeRunning = true;
      let camId = '';
      try { camId = localStorage.getItem('gazelab_cam') || ''; } catch (e) {}
      const vq = { frameRate: { ideal: 30, max: 30 }, width: { ideal: Math.round((parseInt(qs.get('res')) || (coarseNow ? 720 : 1080)) * 16 / 9) }, height: { ideal: parseInt(qs.get('res')) || (coarseNow ? 720 : 1080) } };
      let stream0 = null;
      try { stream0 = await navigator.mediaDevices.getUserMedia({ video: camId ? Object.assign({ deviceId: { exact: camId } }, vq) : Object.assign({ facingMode: 'user' }, vq), audio: false }); }
      catch (e) { stream0 = await navigator.mediaDevices.getUserMedia({ video: Object.assign({ facingMode: 'user' }, vq), audio: false }); }      // the saved camera is gone: whatever the browser picks
      const stream = window.__gazeStream = stream0;
      window.__gazeCamLabel = (stream.getVideoTracks()[0] || {}).label || '';
      // which cameras exist (the names only appear once a camera is allowed). With no saved choice an external / USB camera is preferred over the built-in one.
      await window.__gazeListCams();
      if (!camId) {
        const ext = (window.__gazeCams || []).find((c) => /usb|logi|brio|c9[0-9][0-9]|kiyo|elgato|obsbot|external/i.test(c.label));
        if (ext && ext.label !== window.__gazeCamLabel) { window.__gazeUseCam(ext.id); return; }
      }
      try { const ts = stream.getVideoTracks()[0].getSettings(); window.__gazeStats.vw = ts.width; window.__gazeStats.vh = ts.height; window.__gazeStats.cfps = ts.frameRate; } catch (e) {}
      if (qs.has('fast')) {
        // Dim rooms make auto-exposure pick ~60 ms shutters, which caps the camera near 15 fps. A short
        // fixed exposure gives the full 30 fps (the image is darker: add light). Not every camera allows it.
        try { await stream.getVideoTracks()[0].applyConstraints({ advanced: [{ exposureMode: 'manual', exposureTime: 150 }] }); } catch (e) {}
      }
      const v = document.createElement('video');
      v.playsInline = true; v.muted = true; v.srcObject = stream;
      window.__gazeStatus = 'camera on';
      // Small mirrored preview with the tracked iris points, bottom-centre, so you can see what the tracker sees (lighting, framing). Hidden from touch.
      const wrap = document.createElement('div');
      wrap.style.cssText = 'position:fixed;left:8px;bottom:8px;width:132px;height:99px;border-radius:10px;overflow:hidden;border:2px solid rgba(255,255,255,.7);opacity:.9;pointer-events:none;z-index:9999;background:#000';
      v.style.cssText = 'width:100%;height:100%;object-fit:cover;transform:scaleX(-1)';
      const cv = document.createElement('canvas');
      cv.width = 176; cv.height = 132;
      cv.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;transform:scaleX(-1)';
      wrap.appendChild(v); wrap.appendChild(cv);
      document.body.appendChild(wrap);
      await v.play();                       // attached to the page first: required by iOS Safari
      const cx = cv.getContext('2d');
      window.__gazePreview = wrap;
      const drawPts = (pts) => {
        cx.clearRect(0, 0, 176, 132);
        if (!pts) return;
        cx.fillStyle = '#3f6';
        for (const q of pts) { cx.beginPath(); cx.arc(q[0] * 176, q[1] * 132, 3, 0, 6.3); cx.fill(); }
      };
      // ---- frame rotation. Some phones hand over the front camera sideways or upside down (the sensor is mounted that way, or the screen is locked to landscape while the phone
      // is held upright), and a leaning phone does the same by a few degrees. A face model reads an upright face best, so: if no face is found for ~2 s, try the other
      // three orientations in turn and keep the one that works; if the face is found but turned more than ~45 degrees, turn the frame a quarter and check that it helped.
      // A rotated frame is drawn onto a canvas and the tracker reads that canvas instead of the video; the preview shows the same canvas, so what you see is what it sees.
      let rot = 0, lastFace = performance.now(), lastRot = 0, rollSince = 0, rollSign = 1, pend = null;
      const rc = document.createElement('canvas');
      const rx = rc.getContext('2d');
      rc.style.cssText = 'position:absolute;left:0;top:0;width:100%;height:100%;object-fit:cover;transform:scaleX(-1);display:none';
      wrap.insertBefore(rc, cv);
      const setRot = (r) => {
        rot = ((r % 360) + 360) % 360; window.__gazeRot = rot; window.__gazeRoi = null; window.__gazeEyes = null;
        rc.style.display = rot ? 'block' : 'none'; v.style.display = rot ? 'none' : 'block';
        lastRot = performance.now();
      };
      const srcFrame = () => {
        if (!rot) return v;
        const W = v.videoWidth, H = v.videoHeight, sw = (rot === 90 || rot === 270);
        if (rc.width !== (sw ? H : W) || rc.height !== (sw ? W : H)) { rc.width = sw ? H : W; rc.height = sw ? W : H; }
        rx.save(); rx.translate(rc.width / 2, rc.height / 2); rx.rotate(rot * Math.PI / 180); rx.drawImage(v, -W / 2, -H / 2, W, H); rx.restore();
        return rc;
      };
      const ORDER = [0, 90, 270, 180];
      // A snapshot for the frame-capture test (opt-in, the player turns it on): a square crop around the face (the eyes in detail), a small copy of the whole frame, and the tracker's
      // numbers for that frame. Raw camera orientation (not mirrored). Only ever sent to the local test server, never anywhere else.
      window.__gazeBright = () => {                                       // mean brightness of the camera picture, 0 (black) .. 255 (white)
        try {
          const c = document.createElement('canvas'); c.width = 16; c.height = 12;
          const x = c.getContext('2d'); x.drawImage(v, 0, 0, 16, 12);
          const d = x.getImageData(0, 0, 16, 12).data; let s = 0;
          for (let i = 0; i < d.length; i += 4) s += 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
          return s / (d.length / 4);
        } catch (e) { return -1; }
      };
      window.__gazeSetRes = async (h) => {                                // a different camera resolution without restarting the camera
        try { await stream.getVideoTracks()[0].applyConstraints({ width: { ideal: Math.round(h * 16 / 9) }, height: { ideal: h } }); } catch (e) {}
      };
      window.__gazeExposure = async (fast) => {                           // a short fixed exposure keeps 30 fps in a dim room; false puts it back to automatic
        try { await stream.getVideoTracks()[0].applyConstraints(fast ? { advanced: [{ exposureMode: 'manual', exposureTime: 150 }] } : { advanced: [{ exposureMode: 'continuous' }] }); } catch (e) {}
      };
      window.__gazeSnap = () => {
        try {
          const src = srcFrame();
          const W = src.videoWidth || src.width, H = src.videoHeight || src.height;
          if (!W || !H) return null;
          const g = window.__gaze || {};
          const fx = g.nx !== undefined ? (1 - g.nx) * W : W / 2, fy = g.ny !== undefined ? g.ny * H : H / 2;
          const side = Math.max(160, Math.min(H, (g.fw || 0.3) * W * 1.7));
          const x0 = Math.min(Math.max(fx - side / 2, 0), W - side), y0 = Math.min(Math.max(fy - side / 2, 0), H - side);
          const c1 = document.createElement('canvas'); c1.width = 480; c1.height = 480;
          c1.getContext('2d').drawImage(src, x0, y0, side, side, 0, 0, 480, 480);
          const c2 = document.createElement('canvas'); c2.width = 320; c2.height = Math.round(320 * H / W);
          c2.getContext('2d').drawImage(src, 0, 0, W, H, 0, 0, c2.width, c2.height);
          return { face: c1.toDataURL('image/jpeg', 0.82), full: c2.toDataURL('image/jpeg', 0.7), pkt: g, rot: rot, w: W, h: H, crop: [Math.round(x0), Math.round(y0), Math.round(side)] };
        } catch (e) { return null; }
      };
      setInterval(() => {
        if (!window.__gazeRunning) return;
        const g = window.__gaze, t = performance.now(), has = !!(g && g.conf > 0 && g.nx !== undefined);
        if (has) lastFace = t;
        else if (t - lastFace > 2000 && t - lastRot > 1700) { setRot(ORDER[(ORDER.indexOf(rot) + 1) % 4]); lastFace = t - 300; }
        if (has && typeof g.hroll === 'number') {
          const ar = Math.abs(g.hroll);
          if (pend && t - pend.t > 1500) {                       // did the last quarter turn help?
            if (ar > pend.ar - 0.25) { rollSign = -rollSign; setRot(rot + pend.dir * -1 * 1); }
            pend = null; rollSince = 0;
          } else if (!pend) {
            if (ar > 0.78) {
              if (!rollSince) rollSince = t;
              else if (t - rollSince > 2000 && t - lastRot > 3000) { const dir = (g.hroll > 0 ? -90 : 90) * rollSign; pend = { t: t, ar: ar, dir: dir }; setRot(rot + dir); rollSince = 0; }
            } else rollSince = 0;
          }
        }
      }, 400);
      let last = -1, errShown = false, inflight = 0, busyAt = 0;
      const DEPTH = 2;        // frames in the pipeline at once: one in the model worker, one being turned into a packet
      if (workerOk) {
        // The face model runs in the workers: this thread only snapshots a frame (cheap) and lets the game keep its frame rate.
        const onw = (ev) => {
          const m = ev.data;
          if (m.type === 'roi') {
            const S0 = window.__gazeStats, o = window.__gazeRoi, n = m.roi || null;     // count crop moves and losses: a crop that keeps jumping is a sign of trouble
            if (n && o && (n.x !== o.x || n.y !== o.y || n.w !== o.w)) S0.rmv = (S0.rmv || 0) + 1;
            if (!n && o) S0.rlost = (S0.rlost || 0) + 1;
            window.__gazeRoi = n; S0.roi = n ? n.w : 0;
            window.__gazeEyes = m.eyes || null; S0.pa = m.eyes ? 1 : 0;
          }
          else if (m.type === 'pkt') {
            inflight = Math.max(0, inflight - 1); window.__gaze = m.pkt; const S = window.__gazeStats; S.pk++; drawPts(m.pts);
            // capture-to-page latency (frame grabbed -> packet back) and model time per frame, smoothed
            if (typeof m.t === 'number') { const l = performance.now() - m.t; S.lat = S.lat === undefined ? l : S.lat * 0.9 + l * 0.1; }
            if (typeof m.inf === 'number') { S.inf = S.inf === undefined ? m.inf : S.inf * 0.9 + m.inf * 0.1; }
            if (typeof m.det === 'number') { S.det = S.det === undefined ? m.det : S.det * 0.9 + m.det * 0.1; }
          }
          else if (m.type === 'frameerr') { inflight = Math.max(0, inflight - 1); if (!errShown) { errShown = true; window.__gazeStatus = 'error: tracking frame failed: ' + m.msg; } }
        };
        const onerr = (e) => { if (!errShown) { errShown = true; window.__gazeStatus = 'error: tracker worker: ' + ((e && e.message) || e); } };
        worker.onmessage = onw; worker.onerror = onerr;
        if (worker2) { worker2.onmessage = onw; worker2.onerror = onerr; }
        const tickW = () => {
          if (v.requestVideoFrameCallback) v.requestVideoFrameCallback(tickW); else requestAnimationFrame(tickW);
          if (!window.__gazeRunning || !worker) return;
          const now = performance.now();
          if (inflight > 0 && now - busyAt > 3000) inflight = 0;         // a lost frame must not stall the tracker
          if (v.readyState >= 2 && v.currentTime !== last) { window.__gazeStats.cf++; if (inflight >= DEPTH) window.__gazeStats.drop++; }   // camera frames seen / dropped because the pipeline was full
          if (inflight >= DEPTH || v.readyState < 2 || v.currentTime === last) return;
          const cap = window.__gazeCap || 0;                              // the tuner can hold the tracker to N readings a second so the game keeps its frame rate
          if (cap > 0 && now - (window.__gazeLastSend || 0) < 1000 / cap - 3) return;
          window.__gazeLastSend = now;
          last = v.currentTime; inflight++; busyAt = now;
          const SRC = srcFrame();
          const roi = qs.has('noroi') ? null : window.__gazeRoi;       // a crop around the face, from the previous packet (null: whole frame)
          // Full detail only where it matters: the face model gets a SMALL copy of the face crop (it shrinks the face to ~256 px anyway), and the iris fit gets two
          // small full-resolution patches around the eyes. ?bigcrop goes back to one big full-resolution crop; ?mi=N sets the model copy's size (default 448).
          const eyes = (roi && !qs.has('bigcrop')) ? window.__gazeEyes : null;
          const MI = parseInt(qs.get('mi')) || 448;
          const mk = roi ? ((eyes && roi.w > MI) ? createImageBitmap(SRC, roi.x, roi.y, roi.w, roi.h, { resizeWidth: MI, resizeHeight: MI, resizeQuality: 'medium' }) : createImageBitmap(SRC, roi.x, roi.y, roi.w, roi.h)) : createImageBitmap(SRC);
          const pk = eyes ? Promise.all(eyes.map((e) => createImageBitmap(SRC, e.x, e.y, e.s, e.s))) : Promise.resolve(null);
          Promise.all([mk, pk]).then((res) => {
            const bmp = res[0], pb = res[1];
            if (worker) worker.postMessage({ type: 'frame', bmp: bmp, pa: pb ? [{ bmp: pb[0], x: eyes[0].x, y: eyes[0].y, s: eyes[0].s }, { bmp: pb[1], x: eyes[1].x, y: eyes[1].y, s: eyes[1].s }] : null, t: performance.now(), env: envNow(), roi: roi || null, W: SRC === v ? v.videoWidth : SRC.width, H: SRC === v ? v.videoHeight : SRC.height, noroi: qs.has('noroi') }, pb ? [bmp, pb[0], pb[1]] : [bmp]);
            else { bmp.close(); if (pb) pb.forEach((b) => b.close()); }
          }).catch(() => { inflight = Math.max(0, inflight - 1); window.__gazeRoi = null; window.__gazeEyes = null; });
        };
        tickW();
        return;
      }
      const tick = () => {
        if (v.requestVideoFrameCallback) v.requestVideoFrameCallback(tick); else requestAnimationFrame(tick);
        try {
          if (v.readyState >= 2 && v.currentTime !== last) {
            last = v.currentTime;
            applyEnv(envNow());
            const tm0 = performance.now();
            const r = lm.detectForVideo(v, tm0);
            const out = buildPacket(r, v, v.videoWidth, v.videoHeight);
            const S = window.__gazeStats; const il = performance.now() - tm0;
            window.__gaze = out.pkt; S.pk++; S.cf++; S.lat = S.inf = (S.inf === undefined ? il : S.inf * 0.9 + il * 0.1); drawPts(out.pts);
          }
        } catch (e) {
          if (!errShown) { errShown = true; window.__gazeStatus = 'error: tracking frame failed: ' + ((e && e.message) || e); }
        }
      };
      tick();
    } catch (e) {
      window.__gazeStatus = 'error: ' + ((e && e.message) || e);
      window.__gazeRunning = false;
    }
  };
"""


## The script injected into the page. The face model + gaze maths (SHARED) run in a Web Worker when the browser allows it, so the game's own frame rate
## no longer starves the tracker (and vice versa); otherwise they run in the page exactly as before.
static func source() -> String:
	return "(function () {\n  const __WSRC = " + JSON.stringify(SHARED + GLUE) + ";\n" + SHARED + MAIN + "\n})();"
