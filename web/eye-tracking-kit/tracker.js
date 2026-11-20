// Eye tracking for STARGAZE. Everything runs on the device: camera -> MediaPipe face landmarks -> eye features -> calibrated gaze.
//
// What it gives the game:
//   gaze {x,y}   where on the screen the player is looking, -1..1 (x right, y up), filtered
//   raw {x,y}    an uncalibrated "which way are the eyes turned" signal, used for the mirror eye before calibration
//   closed       both eyes shut right now; closedFor = seconds they have been shut
//   onBlink()    a deliberate-length blink finished
//   face         a face is in view
//
// Gaze is a ridge regression from seven features (iris position inside each eye opening, upper-lid height, head yaw/pitch,
// face position in the frame) to screen position, fitted on a ~10 s "follow the spark" pursuit. The fit also finds the
// eye+camera lag, drops outliers, and rescales the output so a weak axis still reaches the screen edges.
import { FaceLandmarker, FilesetResolver } from './vendor/mediapipe/vision_bundle.mjs';

// this MediaPipe build calls a debug-print hook that it never defines; without it model start-up throws
if (typeof globalThis.dbg !== 'function') globalThis.dbg = () => {};

const NF = 7;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

class OneEuro {
  constructor(minCut, beta, dCut = 1) { this.minCut = minCut; this.beta = beta; this.dCut = dCut; this.x = null; this.dx = 0; this.t = 0; }
  reset() { this.x = null; this.dx = 0; }
  filter(v, t) {
    if (this.x === null) { this.x = v; this.t = t; return v; }
    const dt = Math.max(1e-3, t - this.t); this.t = t;
    const a = (c) => { const r = 2 * Math.PI * c * dt; return r / (r + 1); };
    const dv = (v - this.x) / dt;
    this.dx += a(this.dCut) * (dv - this.dx);
    this.x += a(this.minCut + this.beta * Math.abs(this.dx)) * (v - this.x);
    return this.x;
  }
}

function solve(A, b) { // Gaussian elimination with partial pivoting; A is n x n (modified in place)
  const n = b.length;
  for (let i = 0; i < n; i++) {
    let p = i;
    for (let r = i + 1; r < n; r++) if (Math.abs(A[r][i]) > Math.abs(A[p][i])) p = r;
    [A[i], A[p]] = [A[p], A[i]]; [b[i], b[p]] = [b[p], b[i]];
    const d = A[i][i] || 1e-12;
    for (let r = i + 1; r < n; r++) {
      const f = A[r][i] / d; if (!f) continue;
      for (let c = i; c < n; c++) A[r][c] -= f * A[i][c];
      b[r] -= f * b[i];
    }
  }
  const x = new Array(n).fill(0);
  for (let i = n - 1; i >= 0; i--) {
    let s = b[i];
    for (let c = i + 1; c < n; c++) s -= A[i][c] * x[c];
    x[i] = s / (A[i][i] || 1e-12);
  }
  return x;
}

// pairs: [{f:[NF], x, y}] -> model, or null
function ridgeFit(pairs) {
  const n = pairs.length; if (n < 30) return null;
  const mean = new Array(NF).fill(0), std = new Array(NF).fill(0);
  for (const p of pairs) for (let j = 0; j < NF; j++) mean[j] += p.f[j] / n;
  for (const p of pairs) for (let j = 0; j < NF; j++) std[j] += (p.f[j] - mean[j]) ** 2 / n;
  for (let j = 0; j < NF; j++) std[j] = Math.sqrt(std[j]) || 1e-6;
  const D = NF + 1, lam = 0.03 * n;
  const XtX = Array.from({ length: D }, () => new Array(D).fill(0)), Xx = new Array(D).fill(0), Xy = new Array(D).fill(0);
  const row = new Array(D);
  for (const p of pairs) {
    for (let j = 0; j < NF; j++) row[j] = (p.f[j] - mean[j]) / std[j];
    row[NF] = 1;
    for (let a = 0; a < D; a++) { Xx[a] += row[a] * p.x; Xy[a] += row[a] * p.y; for (let b = 0; b < D; b++) XtX[a][b] += row[a] * row[b]; }
  }
  for (let j = 0; j < NF; j++) XtX[j][j] += lam;
  const wx = solve(XtX.map(r => r.slice()), Xx.slice()), wy = solve(XtX.map(r => r.slice()), Xy.slice());
  const m = { mean, std, wx, wy, gx: 1, gy: 1 };
  // goodness of fit, and a gain so a shrunken axis still spans the screen
  let sx = 0, sy = 0, tx = 0, ty = 0, mx = 0, my = 0, px = 0, py = 0, pmx = 0, pmy = 0;
  const preds = pairs.map(p => predict(m, p.f));
  for (let i = 0; i < n; i++) { mx += pairs[i].x / n; my += pairs[i].y / n; pmx += preds[i][0] / n; pmy += preds[i][1] / n; }
  for (let i = 0; i < n; i++) {
    sx += (pairs[i].x - preds[i][0]) ** 2; sy += (pairs[i].y - preds[i][1]) ** 2;
    tx += (pairs[i].x - mx) ** 2; ty += (pairs[i].y - my) ** 2;
    px += (preds[i][0] - pmx) ** 2; py += (preds[i][1] - pmy) ** 2;
  }
  m.r2x = 1 - sx / (tx || 1); m.r2y = 1 - sy / (ty || 1);
  m.gx = clamp(Math.sqrt(tx / (px || 1e-9)), 1, 2.2); m.gy = clamp(Math.sqrt(ty / (py || 1e-9)), 1, 2.2);
  m.cx = pmx; m.cy = pmy;
  m.rms = Math.sqrt((sx + sy) / (2 * n)); m.n = n; m.res = preds.map((q, i) => Math.hypot(pairs[i].x - q[0], pairs[i].y - q[1]));
  return m;
}
function predict(m, f) {
  let x = m.wx[NF], y = m.wy[NF];
  for (let j = 0; j < NF; j++) { const z = (f[j] - m.mean[j]) / m.std[j]; x += m.wx[j] * z; y += m.wy[j] * z; }
  return [x, y];
}

export class Tracker {
  constructor(video) {
    this.video = video;
    this.sim = false;                 // touch / mouse stand-in
    this.face = false; this.lastSeen = 0; this.fps = 0; this.delegate = '';
    this.raw = { x: 0, y: 0 };
    this.gaze = { x: 0, y: 0 };
    this.head = { yaw: 0, pitch: 0, roll: 0 };
    this.blinkL = 0; this.blinkR = 0;
    this.closed = false; this.closedFor = 0; this._closedAt = 0; this._lastOpenT = 0;
    this.onBlink = null;
    this.model = null; this.bias = { x: 0, y: 0 };
    this._rec = null;
    this._fx = new OneEuro(0.9, 0.45); this._fy = new OneEuro(0.9, 0.45);
    this._rx = new OneEuro(1.6, 0.5); this._ry = new OneEuro(1.6, 0.5);
    this._c = null;                   // slow centre of the raw iris signal
    this._lastT = 0; this._lastVT = -1; this._ts = 0;
    this.feat = new Array(NF).fill(0);
  }

  async start(onStage, fakeUrl) {
    onStage?.('camera');
    if (fakeUrl) await this._fakeCamera(fakeUrl);
    else {
      if (!navigator.mediaDevices?.getUserMedia) throw new Error('This browser cannot open the camera (needs HTTPS).');
      const stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 30, max: 30 } } });
      this.stream = stream; this.video.srcObject = stream;
    }
    await this.video.play().catch(() => {});
    onStage?.('model');
    const fileset = await FilesetResolver.forVisionTasks(new URL('./vendor/mediapipe/wasm', import.meta.url).href);
    const opts = (delegate) => ({
      baseOptions: { modelAssetPath: new URL('./vendor/mediapipe/face_landmarker.task', import.meta.url).href, delegate },
      runningMode: 'VIDEO', numFaces: 1, outputFaceBlendshapes: true, outputFacialTransformationMatrixes: true,
      minFaceDetectionConfidence: 0.5, minFacePresenceConfidence: 0.5, minTrackingConfidence: 0.5,
    });
    try { this.lm = await FaceLandmarker.createFromOptions(fileset, opts('GPU')); this.delegate = 'GPU'; }
    catch (e) { this.lm = await FaceLandmarker.createFromOptions(fileset, opts('CPU')); this.delegate = 'CPU'; }
    this.running = true; this._loop();
    onStage?.('ready');
  }

  async _fakeCamera(url) { // dev only: a still image stands in for the camera so the whole pipeline can be exercised
    const img = new Image(); img.src = url; await img.decode();
    const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
    const g = c.getContext('2d'); let k = 0;
    const draw = () => { g.drawImage(img, (k++ % 2), 0); };
    draw(); this._fakeTimer = setInterval(draw, 50);
    this.video.srcObject = c.captureStream(20);
  }

  stop() { this.running = false; this.stream?.getTracks().forEach(t => t.stop()); clearInterval(this._fakeTimer); }

  _loop() {
    const v = this.video;
    const step = () => {
      if (!this.running) return;
      if (v.readyState >= 2 && v.videoWidth && v.currentTime !== this._lastVT) {
        this._lastVT = v.currentTime;
        const now = performance.now(); this._ts = Math.max(this._ts + 1, now);
        let res = null;
        try { res = this.lm.detectForVideo(v, this._ts); } catch (e) { this.err = String(e); }
        this._process(res, now / 1000);
      }
      next();
    };
    const next = v.requestVideoFrameCallback ? () => v.requestVideoFrameCallback(step) : () => requestAnimationFrame(step);
    next();
    // a hidden tab pauses video callbacks; this keeps "face lost" honest and restarts the chain if it stalls
    this._watch = setInterval(() => { const t = performance.now() / 1000; if (t - this.lastSeen > 0.5) { this.face = false; this._openEyes(t, false); } }, 200);
  }

  _openEyes(t, emit) {
    if (!this.closed) return;
    const dur = t - this._closedAt; this.closed = false; this.closedFor = 0; this._lastOpenT = t;
    if (emit && dur > 0.04 && dur < 0.55) this.onBlink?.(dur);
  }

  _process(res, t) {
    const L = res?.faceLandmarks?.[0];
    if (!L) return;
    const dt = t - this._lastT; this._lastT = t;
    if (dt > 0 && dt < 1) this.fps += (1 / dt - this.fps) * 0.1;
    this.face = true; this.lastSeen = t;
    const W = this.video.videoWidth, H = this.video.videoHeight;
    const P = (i) => [L[i].x * W, L[i].y * H];
    // one eye: iris centre measured inside the eye opening, along the eye's own axis (so head roll does not leak in)
    const eye = (c1, c2, ir, up) => {
      const a = P(c1), b = P(c2), i = P(ir), u = P(up);
      const ax = b[0] - a[0], ay = b[1] - a[1], w = Math.hypot(ax, ay) || 1;
      const ux = ax / w, uy = ay / w, nx = -uy, ny = ux; // n points down the image
      const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
      return { hx: ((i[0] - mx) * ux + (i[1] - my) * uy) / w, hy: ((i[0] - mx) * nx + (i[1] - my) * ny) / w, lid: ((u[0] - mx) * nx + (u[1] - my) * ny) / w };
    };
    const eA = eye(33, 133, 468, 159), eB = eye(362, 263, 473, 386);
    const hx = (eA.hx + eB.hx) / 2, hy = (eA.hy + eB.hy) / 2, lid = (eA.lid + eB.lid) / 2;

    const M = res.facialTransformationMatrixes?.[0]?.data;
    if (M) { this.head.yaw = Math.atan2(M[8], M[10]); this.head.pitch = Math.asin(clamp(-M[9], -1, 1)); this.head.roll = Math.atan2(M[1], M[5]); }
    const f = this.feat;
    f[0] = hx; f[1] = hy; f[2] = lid; f[3] = this.head.yaw; f[4] = this.head.pitch; f[5] = L[168].x - 0.5; f[6] = L[168].y - 0.5;

    // blink
    const cats = res.faceBlendshapes?.[0]?.categories;
    if (cats) {
      if (!this._bi) { this._bi = {}; cats.forEach((c, i) => { this._bi[c.categoryName] = i; }); }
      this.blinkL = cats[this._bi.eyeBlinkLeft]?.score ?? 0; this.blinkR = cats[this._bi.eyeBlinkRight]?.score ?? 0;
    }
    // "Open" reads differently per person and per pose (looking down at a phone lifts the score a lot), so measure blinks
    // against this player's own resting level: it drops to a lower reading at once and creeps up only slowly.
    if (!this._base) this._base = [Math.min(this.blinkL, 0.5), Math.min(this.blinkR, 0.5)];
    const B = this._base, sc = [this.blinkL, this.blinkR], nb = [0, 0];
    for (let i = 0; i < 2; i++) {
      if (sc[i] < B[i]) B[i] += (sc[i] - B[i]) * 0.3; else if (!this.closed) B[i] += (Math.min(sc[i], 0.6) - B[i]) * Math.min(1, dt / 8);
      nb[i] = clamp((sc[i] - B[i]) / (1 - B[i]), 0, 1);
    }
    const lo = Math.min(nb[0], nb[1]), hi = Math.max(nb[0], nb[1]);
    if (!this.closed && lo > 0.5) { this.closed = true; this._closedAt = t; }
    else if (this.closed && lo < 0.28) this._openEyes(t, true);
    this.closedFor = this.closed ? t - this._closedAt : 0;
    // the iris is unreliable while the lids are moving: hold the last gaze through a blink and just after it
    const steady = hi < 0.38 && !this.closed && t - this._lastOpenT > 0.12;
    if (!steady) return;

    // uncalibrated mirror signal: iris offset from its own slow centre
    if (!this._c) this._c = { x: hx, y: hy };
    const k = Math.min(1, dt / 4); this._c.x += (hx - this._c.x) * k; this._c.y += (hy - this._c.y) * k;
    this.raw.x = this._rx.filter(clamp(-(hx - this._c.x) * 14, -1, 1), t);   // image is unmirrored: iris toward image-right = looking screen-left
    this.raw.y = this._ry.filter(clamp(-(hy - this._c.y) * 16, -1, 1), t);

    if (this._rec) this._rec.push({ t, f: f.slice() });
    if (this.model && !this.sim) {
      const m = this.model, p = predict(m, f);
      const x = clamp((p[0] - m.cx) * m.gx + m.cx + this.bias.x, -1.2, 1.2), y = clamp((p[1] - m.cy) * m.gy + m.cy + this.bias.y, -1.2, 1.2);
      this.gaze.x = this._fx.filter(x, t); this.gaze.y = this._fy.filter(y, t);
    }
  }

  // --- calibration -------------------------------------------------------------------------------------------------
  beginCalibration() { this._rec = []; }
  // targets: [{t, x, y}] in the same clock as the tracker (performance.now()/1000), sorted by t
  finishCalibration(targets) {
    const rec = this._rec || []; this._rec = null;
    if (rec.length < 40 || targets.length < 2) return { ok: false, n: rec.length, why: 'few' };
    const at = (t) => {
      if (t <= targets[0].t) return null;
      let lo = 0, hi = targets.length - 1; if (t >= targets[hi].t) return null;
      while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (targets[mid].t <= t) lo = mid; else hi = mid; }
      const a = targets[lo], b = targets[hi], u = (t - a.t) / ((b.t - a.t) || 1);
      return [a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u];
    };
    let best = null;
    for (let lag = 0; lag <= 0.42; lag += 0.035) { // the eyes trail the spark and the camera trails the eyes: find by how much
      const pairs = [];
      for (const s of rec) { const q = at(s.t - lag); if (q) pairs.push({ f: s.f, x: q[0], y: q[1] }); }
      const m = ridgeFit(pairs); if (!m) continue;
      if (!best || m.rms < best.m.rms) best = { m, lag, pairs };
    }
    if (!best) return { ok: false, n: rec.length, why: 'fit' };
    // one outlier pass (glances away, half-blinks)
    const cut = 2.2 * best.m.rms, kept = best.pairs.filter((p, i) => best.m.res[i] < cut);
    const m = ridgeFit(kept) || best.m;
    delete m.res;
    this.model = m; this.bias.x = 0; this.bias.y = 0; this._fx.reset(); this._fy.reset();
    const q = clamp((Math.max(0, m.r2x) + Math.max(0, m.r2y)) / 2, 0, 1);
    // a noisier fit gets a heavier filter: steadier, a little slower
    this._fx.minCut = 0.45 + 0.7 * clamp(m.r2x, 0, 1); this._fy.minCut = 0.45 + 0.7 * clamp(m.r2y, 0, 1);
    return { ok: m.r2x > 0.3 && m.r2y > 0.3 && q > 0.45, quality: q, r2x: m.r2x, r2y: m.r2y, lag: best.lag, n: kept.length, rms: m.rms };
  }
  // The game knows where the player was probably looking when a catch lands; lean the mapping toward it a little.
  nudge(ex, ey) { this.bias.x = clamp(this.bias.x + ex * 0.06, -0.4, 0.4); this.bias.y = clamp(this.bias.y + ey * 0.06, -0.4, 0.4); }

  // --- touch / mouse stand-in ---------------------------------------------------------------------------------------
  setSim(x, y) { this.gaze.x = x; this.gaze.y = y; this.raw.x = x; this.raw.y = y; this.face = true; this.lastSeen = performance.now() / 1000; }
}
