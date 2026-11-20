// SPIKE: the smallest version of the game that still has the look. A road of glowing squares (one shader, one plane), wireframe pylons, rings, loot and gates (instanced), and ONE
// full-screen pass that makes tracers (a half-size feedback buffer) and splits the colours.
//
// THE EYES ARE EXACTLY GODOT'S. The tracker is Godot's own script (gazecam_godot.js, dumped from GazeCamJS.source()): it opens the camera, runs the face model in its workers and
// publishes window.__gaze with the iris reading `hx`. The three zones are KitEye.gd, ported line for line below: no calibration, the middle learned from the first 40 readings, a look to
// a side starting at AUTO_D and growing with the looks that really reach past the line, the median of the last three readings, 0.5 to enter a side and 0.3 to leave it. The board's
// lane IS the zone (what Godot's eye_now() returned: left, middle or right, nothing in between) and the board slides there.
import * as THREE from 'three';

const Q = new URLSearchParams(location.search);
const RS = Math.min(1, Math.max(0.3, parseFloat(Q.get('rs') || '1')));
const canvas = document.getElementById('gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', alpha: false });
renderer.setPixelRatio(1);
const flags = { tracers: !Q.has('nopost'), split: !Q.has('nopost'), moire: true, objects: true };
const hud = document.getElementById('hud');
const $ = (id) => document.getElementById(id);

let W = 0, H = 0, sceneRT, trailA, trailB;
const rtOpts = { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false, stencilBuffer: false };
function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  W = Math.max(2, Math.floor(innerWidth * dpr * RS));
  H = Math.max(2, Math.floor(innerHeight * dpr * RS));
  renderer.setSize(W, H, false);
  canvas.style.width = '100%';
  canvas.style.height = '100%';
  if (sceneRT) sceneRT.dispose();
  if (trailA) trailA.dispose();
  if (trailB) trailB.dispose();
  sceneRT = new THREE.WebGLRenderTarget(W, H, { ...rtOpts, depthBuffer: true });
  const tw = Math.max(2, W >> 1), th = Math.max(2, H >> 1);          // the echoes are soft: half size
  trailA = new THREE.WebGLRenderTarget(tw, th, rtOpts);
  trailB = new THREE.WebGLRenderTarget(tw, th, rtOpts);
}
addEventListener('resize', resize);
resize();

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x000000);
const camera = new THREE.PerspectiveCamera(85, 1, 0.1, 600);
const hue = (h) => new THREE.Color().setHSL(((h % 1) + 1) % 1, 1, 0.55);

// THE GROUND: one plane that follows the rider; the pattern is computed from world position, so it is fixed to the ground as you speed by.
const groundMat = new THREE.ShaderMaterial({
  uniforms: { uT: { value: 0 }, uMoire: { value: 1 }, uCam: { value: new THREE.Vector3() } },
  vertexShader: 'varying vec3 wp; void main(){ vec4 w = modelMatrix * vec4(position,1.0); wp = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
  fragmentShader: `
    precision mediump float;
    varying vec3 wp;
    uniform float uT;
    uniform float uMoire;
    uniform vec3 uCam;
    vec3 hsv(float h){ return clamp(abs(fract(vec3(h)+vec3(0.,.6667,.3333))*6.-3.)-1.,0.,1.); }
    float gline(vec2 p, float w){ vec2 f = abs(fract(p)-.5); vec2 d = fwidth(p)*w; vec2 l = smoothstep(.5-d, vec2(.5), f); return max(l.x, l.y); }
    void main(){
      float dist = length(wp.xz - uCam.xz);
      float a = gline(wp.xz / 6.0, 1.2);
      float b = 0.0;
      if (uMoire > .5) {
        float ang = .035 + .02*sin(uT*.1);
        vec2 q = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * wp.xz;
        b = gline(q / 5.8 + vec2(uT*.05, 0.), 1.2) * .8;
      }
      float fade = 1.0 - smoothstep(120., 380., dist);
      vec3 col = hsv(fract(dist*.004 - uT*.05 + wp.z*.002)) * (a*.9 + b*.7);
      col += vec3(.0,.9,1.) * (1.0 - smoothstep(.0, .25, abs(abs(wp.x) - 10.)));
      gl_FragColor = vec4(col * fade, 1.0);
    }`,
});
const ground = new THREE.Mesh(new THREE.PlaneGeometry(900, 900, 1, 1), groundMat);
ground.rotation.x = -Math.PI / 2;
ground.frustumCulled = false;
scene.add(ground);

// OBJECTS: wireframe pylons down both sides, rings, loot and gates, all instanced.
const N_PYL = 160, N_RING = 10, SPAN = 520, LANE_W = 8, ROW_GAP = SPAN / N_RING;
const pylMesh = new THREE.InstancedMesh(new THREE.ConeGeometry(1.6, 7, 5, 1, true), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_PYL);
const ringMesh = new THREE.InstancedMesh(new THREE.TorusGeometry(4.5, 0.08, 3, 28), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING);
const orbMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(0.7, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 6);
const wallMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 1, 5, 1.2), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_RING * 2);
for (const mm of [pylMesh, ringMesh, orbMesh, wallMesh]) { mm.frustumCulled = false; scene.add(mm); }
// Ten rows ahead at any time, one every 52 m, each either a string of six glowing orbs in one lane, or a GATE: a ring marks the open lane and barriers fill the other two.
const rows = [];
function setRow(r, z) {
  r.z = z; r.type = Math.random() < 0.55 ? 0 : 1; r.lane = Math.floor(Math.random() * 3) - 1; r.done = false;
  r.orbs = [0, 1, 2, 3, 4, 5].map(() => true);
}
for (let i = 0; i < N_RING; i++) { const r = { i }; setRow(r, -50 - i * ROW_GAP); rows.push(r); }
const pyl = [];
for (let i = 0; i < N_PYL; i++) pyl.push({ z: -Math.random() * SPAN, x: (Math.random() < 0.5 ? -1 : 1) * (12 + Math.random() * 26), s: 0.7 + Math.random() * 1.3 });
const m4 = new THREE.Matrix4(), q4 = new THREE.Quaternion(), v3 = new THREE.Vector3(), s3 = new THREE.Vector3(), colr = new THREE.Color();

// THE PASS: tracers in a half-size feedback buffer, then colours split toward the edges.
const quadGeo = new THREE.BufferGeometry();
quadGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
quadGeo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
const VS = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }';
function fsq(frag, uniforms) {
  const m = new THREE.Mesh(quadGeo, new THREE.ShaderMaterial({ uniforms, vertexShader: VS, fragmentShader: frag, depthTest: false, depthWrite: false }));
  m.frustumCulled = false;
  return m;
}
const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const feedMat = fsq(`precision mediump float; varying vec2 vUv; uniform sampler2D uScene; uniform sampler2D uPrev; uniform float uK;
  void main(){ vec3 c = texture2D(uScene, vUv).rgb; vec3 p = texture2D(uPrev, vUv + (vUv-.5)*.004).rgb; gl_FragColor = vec4(max(c*.55, p*uK), 1.); }`,
  { uScene: { value: null }, uPrev: { value: null }, uK: { value: 0.86 } });
const compMat = fsq(`precision mediump float; varying vec2 vUv; uniform sampler2D uScene; uniform sampler2D uTrail; uniform float uTrace; uniform float uSplit;
  uniform vec4 uFlash;
  void main(){
    vec2 c = vUv - .5; float r = length(c);
    float ca = uSplit * (.002 + r * .01);
    vec3 col = vec3(texture2D(uScene, vUv + c*ca).r, texture2D(uScene, vUv).g, texture2D(uScene, vUv - c*ca).b);
    col += texture2D(uTrail, vUv).rgb * .8 * uTrace;
    col += uFlash.rgb * uFlash.a * (0.3 + r);
    gl_FragColor = vec4(col, 1.);
  }`, { uScene: { value: null }, uTrail: { value: null }, uTrace: { value: 1 }, uSplit: { value: 1 }, uFlash: { value: new THREE.Vector4() } });
const feedScene = new THREE.Scene();
feedScene.add(feedMat);
const compScene = new THREE.Scene();
compScene.add(compMat);

// ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// KitEye.gd, ported line for line (the zone part: add(), idle(), _zone_step(), _zn_of()). Constants are Godot's.
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
const clampf = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const median = (a) => { if (!a.length) return 0; const b = a.slice().sort((x, y) => x - y), h = b.length >> 1; return (b.length & 1) ? b[h] : (b[h - 1] + b[h]) * 0.5; };
const KIT = {
  Z_IN: 0.35, Z_OUT: 0.2, AUTO_D: 0.03,          // (Godot: Z_IN 0.5, Z_OUT 0.3. Lowered: its sides grow to match your biggest looks, so half way meant looking nearly as far as you can; 0.35 / 0.2 needs about two thirds of that)
  GROW: 0.75,          // KitEye: Z_IN, Z_OUT, AUTO_D (how far the iris moves for a look to a side: a phone 0.026 to 0.034, a laptop about three times that)
  lastHx: null, tFirst: 0, tZones: 0, zones: null, zone: 0, zn: 0, zh: [], zh_n: 3, zdrift: 0, zbuf: [], zbt: 0, zside: 0, zpk: 0, zauto: [],
  base: [-1, -1], closed: false, open_t: -10, held: false, t: -1, n: 0, lost: false, lost_s: 0, zone_t: 0,
  znOf(d) {
    const dl = this.zones.dl, dr = this.zones.dr;
    return clampf((d * dl > 0.0) ? -d / dl : d / dr, -1.6, 1.6);
  },
  idle(now, delta) {          // no reading for a moment: the zone eases back to the middle
    if (this.t < 0) return;
    if (now - this.t > 0.7) {
      this.lost = true; this.lost_s += delta;
      if (this.zone !== 0) { this.zone = 0; this.zone_t = now; }
      this.zn = 0; this.zh = [];
    } else { this.lost = false; this.lost_s = 0; }
  },
  add(hx, blinkL, blinkR, t) {
    const dt = this.t >= 0 ? clampf(t - this.t, 0.001, 1.0) : 0.033;
    this.t = t; this.lastHx = hx; if (!this.tFirst) this.tFirst = performance.now();
    if (this.base[0] < 0) this.base = [Math.min(blinkL, 0.5), Math.min(blinkR, 0.5)];
    const sc = [blinkL, blinkR];
    let lo = 1.0, hi = 0.0;
    for (let i = 0; i < 2; i++) {
      let b = this.base[i];
      const s = sc[i];
      if (s < b) b += (s - b) * 0.3;                                              // drops to a lower reading at once ...
      else if (!this.closed) b += (Math.min(s, 0.6) - b) * Math.min(1.0, dt / 8.0);          // ... and creeps up only slowly
      this.base[i] = b;
      const nb = clampf((s - b) / Math.max(1.0 - b, 0.01), 0.0, 1.0);
      lo = Math.min(lo, nb); hi = Math.max(hi, nb);
    }
    if (!this.closed && lo > 0.5) this.closed = true;
    else if (this.closed && lo < 0.28) { this.closed = false; this.open_t = t; }
    this.held = !(hi < 0.38 && !this.closed && t - this.open_t > 0.12);
    if (this.held) return;          // the lids are moving: the reading is held
    if (this.zones) this.zoneStep(hx, dt, t);
    else {          // auto_zones: the three places are learned while playing
      this.zauto.push(hx);
      if (this.zauto.length >= 40) { this.zones = { m: median(this.zauto), dl: this.AUTO_D, dr: -this.AUTO_D, noise: 0.0025, auto: true }; this.zauto = []; this.zpk = 0; this.tZones = performance.now(); }
    }
    this.n++;
  },
  zoneStep(hx, dt, t) {
    const z = this.zones;
    this.zh.push(hx); if (this.zh.length > this.zh_n) this.zh.shift();
    const d = median(this.zh) - z.m - this.zdrift;
    this.zn = this.znOf(d);
    let nz = this.zone;
    if (this.zn > this.Z_IN) nz = 1;
    else if (this.zn < -this.Z_IN) nz = -1;
    else if (Math.abs(this.zn) < this.Z_OUT) nz = 0;
    if (this.zone !== 0) this.zpk = Math.max(this.zpk, Math.abs(d));
    if (nz !== this.zone) {
      if (this.zone !== 0 && z.auto && this.zside > 0.12) {
        const k = this.zone < 0 ? 'dl' : 'dr';
        const tgt = clampf(this.zpk * this.GROW, 0.02, 0.14), cur = Math.abs(z[k]);          // (Godot used the full peak)
        if (tgt > cur * 0.7) z[k] = Math.sign(z[k]) * (cur + (tgt - cur) * 0.6);          // a look that reached further than assumed: that side is further; one that fell short of 70% is not taken as evidence
      }
      this.zpk = 0; this.zone = nz; this.zone_t = t; this.zside = 0;
    }
    if (this.zone === 0) {
      this.zdrift += d * Math.min(1.0, dt / 3.0);
      if (z.auto) {          // the two sides are about the same size: one that has grown past 1.6x the other is pulled back
        const al = Math.abs(z.dl), ar = Math.abs(z.dr);
        if (ar > al * 1.6) z.dr = Math.sign(z.dr) * al * 1.6;
        else if (al > ar * 1.6) z.dl = Math.sign(z.dl) * ar * 1.6;
      }
    } else this.zside += dt;
    // the middle follows the long-run median of the readings, so a middle that was learned badly in the first second corrects itself within seconds
    this.zbuf.push(hx); if (this.zbuf.length > 360) this.zbuf.shift();
    this.zbt += dt;
    if (this.zbt >= 0.5 && this.zbuf.length >= 60 && z.auto) {
      this.zbt = 0;
      const m0 = z.m + this.zdrift;
      z.m = z.m + (median(this.zbuf) - m0) * 0.35;
    }
  },
};

// ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// START, PAUSE, CONTROL
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
let steer = 0, steerTarget = 0, lane = 0, playing = false, started = false, paused = false;
const eyeMode = !Q.has('mouse');
function say(h, p, b, fn) {
  $('mh').textContent = h; $('mp').textContent = p; $('mb').textContent = b || ''; $('mb').style.display = b ? '' : 'none';
  $('mb').onclick = fn || null; $('msg').style.display = h ? 'flex' : 'none';
}
let tStart = 0;
function beginPlay() { say('', ''); playing = true; started = true; if (eyeMode) { $('zones').style.display = 'block'; $('gdot').style.display = 'block'; } }
if (eyeMode) {
  say('LOOK TO STEER', '', 'START', async () => {
    tStart = performance.now(); say('Opening your eyes', 'loading the tracker...');
    const poll = setInterval(() => { if (!started) $('mp').textContent = window.__gazeStatus || ''; }, 300);
    try {
      await window.__gazeStart();          // Godot's tracker: loads the model, opens the camera
      const t0 = performance.now();
      while (!/camera on/.test(window.__gazeStatus || '') && !/error/.test(window.__gazeStatus || '') && performance.now() - t0 < 30000) await new Promise((r) => setTimeout(r, 200));
      clearInterval(poll);
      if (/error/.test(window.__gazeStatus || '')) throw new Error(window.__gazeStatus);
      beginPlay();
    } catch (e) {
      clearInterval(poll);
      say('No camera', String((e && e.message) || e).slice(0, 100), 'PLAY WITH MOUSE', () => { beginPlay(); });
    }
  });
} else {
  addEventListener('pointermove', (e) => { steerTarget = Math.max(-1, Math.min(1, Math.round((e.clientX / innerWidth - 0.5) * 3))); lane = steerTarget; });
  beginPlay();
}
function setPause(on) {
  if (!started || on === paused) return;
  paused = on; playing = !on;
  if (on) say('PAUSED', '', 'RESUME', () => setPause(false)); else say('', '');
}
addEventListener('pointerdown', () => { if (paused) setPause(false); });
addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !e.repeat) setPause(!paused);
  if (e.key === '1') flags.tracers = !flags.tracers;
  if (e.key === '2') flags.split = !flags.split;
  if (e.key === '3') flags.moire = !flags.moire;
  if (e.key === '4') flags.objects = !flags.objects;
});

// the tracker publishes a packet on window.__gaze and counts them in window.__gazeSeq: each new packet with an iris reading goes to the zone detector, as GazeProvider.gd did
let lastSeq = 0;
function readTracker(now) {
  const seq = window.__gazeSeq | 0;
  if (seq !== lastSeq) {
    lastSeq = seq;
    const p = window.__gaze;
    if (p && p.hx !== null && p.hx !== undefined && isFinite(p.hx)) KIT.add(+p.hx, +(p.blink_l || 0), +(p.blink_r || 0), now / 1000);
  }
  KIT.idle(now / 1000, 1 / 60);
  KIT.zh_n = 3;          // (Godot used 2 at speed. With the lowered thresholds 2 readings flipped the lane 15 to 19 times in 10 s, so it is 3 here)
}
function updateLane() {
  if (!KIT.zones) {          // the first 40 readings are still coming in: the board stays in the middle, but the dot already follows the eyes (against the middle seen so far, at the starting size)
    lane = 0; steerTarget = 0;
    if (KIT.lastHx !== null && KIT.zauto.length) {
      const d = KIT.lastHx - median(KIT.zauto), zn = clampf(d > 0 ? -d / KIT.AUTO_D : -d / KIT.AUTO_D, -1.6, 1.6);
      const gd0 = $('gdot'); gd0.style.left = ((clampf(zn, -1.2, 1.2) * 0.5 + 0.5) * innerWidth) + 'px'; gd0.style.top = (innerHeight * 0.5) + 'px';
    }
    return;
  }
  lane = KIT.zone; steerTarget = lane;
  const cz = $('zones').children; for (let i = 0; i < 3; i++) cz[i].className = (i - 1 === lane) ? 'on' : '';
  const gd = $('gdot'); gd.style.left = ((clampf(KIT.zn, -1.2, 1.2) * 0.5 + 0.5) * innerWidth) + 'px'; gd.style.top = (innerHeight * 0.5) + 'px';
}

// SCORE, COMBO, FLASH, SOUND.
const scoreEl = document.createElement('div');
scoreEl.style.cssText = 'position:fixed;left:0;right:0;top:10px;text-align:center;color:#fff;font:700 clamp(22px,5vw,44px) ui-monospace,Consolas,monospace;text-shadow:0 0 14px #0ff;z-index:5;pointer-events:none;letter-spacing:.1em';
document.body.appendChild(scoreEl);
const G = { score: 0, combo: 0, best: 0, flash: 0, fr: 0, fg: 0, fb: 0, hit: 0, got: 0 };
function flash(r, g, b, k) { G.fr = r; G.fg = g; G.fb = b; G.flash = k; }
let actx = null;
function beep(f, d, g) {
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const o = actx.createOscillator(), v = actx.createGain();
    o.frequency.value = f; o.type = 'sine'; v.gain.value = g || 0.12; o.connect(v); v.connect(actx.destination);
    o.start(); v.gain.exponentialRampToValueAtTime(0.001, actx.currentTime + d); o.stop(actx.currentTime + d);
  } catch (e) { /* no audio */ }
}
function stepRows(dt) {
  const laneNow = Math.max(-1, Math.min(1, Math.round(camX / LANE_W)));
  for (let i = 0; i < N_RING; i++) {
    const r = rows[i];
    if (r.z > zPos + 25) setRow(r, r.z - SPAN);
    const crossing = !r.done && r.z <= zPrev && r.z > zPos - 1;          // the row's z lies between where the camera was and where it is now
    if (r.type === 0) {
      for (let k = 0; k < 6; k++) {
        const oz = r.z - k * 5, ox = r.lane * LANE_W + Math.sin(k * 0.9 + t * 3) * 0.6;
        const oc = r.orbs[k] && oz <= zPrev && oz > zPos - 1 && Math.abs(camX - r.lane * LANE_W) < 3.4;
        if (oc) { r.orbs[k] = false; G.combo++; G.best = Math.max(G.best, G.combo); G.score += 10 * (1 + Math.floor(G.combo / 8)); G.got++; flash(0, 1, 0.8, 0.28); beep(440 + Math.min(G.combo, 14) * 40, 0.12, 0.08); }
        m4.compose(v3.set(ox, 1.6, oz), q4.identity(), s3.setScalar(r.orbs[k] ? 1 : 0.0001));
        orbMesh.setMatrixAt(i * 6 + k, m4); orbMesh.setColorAt(i * 6 + k, colr.copy(hue(t * 0.3 + k * 0.06 + i * 0.1)));
      }
      m4.compose(v3.set(0, -50, r.z), q4.identity(), s3.setScalar(0.0001)); wallMesh.setMatrixAt(i * 2, m4); wallMesh.setMatrixAt(i * 2 + 1, m4);
      ringMesh.setMatrixAt(i, m4);
    } else {
      m4.compose(v3.set(r.lane * LANE_W, 4.2, r.z), q4.identity(), s3.setScalar(1)); ringMesh.setMatrixAt(i, m4);
      ringMesh.setColorAt(i, colr.copy(hue(t * 0.1 + i * 0.13)));
      let w = 0;
      for (let l = -1; l <= 1; l++) {
        if (l === r.lane) continue;
        m4.compose(v3.set(l * LANE_W, 2.5, r.z), q4.identity(), s3.setScalar(1)); wallMesh.setMatrixAt(i * 2 + w, m4);
        wallMesh.setColorAt(i * 2 + w, colr.setRGB(1, 0.2 + 0.2 * Math.sin(t * 6), 0.3)); w++;
      }
      for (let k = 0; k < 6; k++) { m4.compose(v3.set(0, -50, r.z), q4.identity(), s3.setScalar(0.0001)); orbMesh.setMatrixAt(i * 6 + k, m4); }
      if (crossing) {
        r.done = true;
        if (TEL.on) TEL.q.push({ kind: 'spike_gate', t: +(performance.now() / 1000).toFixed(1), target: r.lane, aim: laneNow, went: laneNow === r.lane ? 1 : 0, x: lane });          // the open lane, the lane the board was in, hit or not, the lane the eyes had chosen
        if (laneNow === r.lane) { G.combo += 3; G.best = Math.max(G.best, G.combo); G.score += 100 * (1 + Math.floor(G.combo / 8)); G.got++; flash(1, 0.9, 0.2, 0.55); beep(660, 0.25, 0.1); setTimeout(() => beep(990, 0.3, 0.08), 90); }
        else { G.combo = 0; G.hit++; speed *= 0.45; flash(1, 0.05, 0.1, 0.8); beep(110, 0.35, 0.18); }
      }
    }
  }
  for (const mm of [orbMesh, wallMesh, ringMesh]) { mm.instanceMatrix.needsUpdate = true; if (mm.instanceColor) mm.instanceColor.needsUpdate = true; }
  G.flash = Math.max(0, G.flash - dt * 1.6);
  scoreEl.textContent = G.score + (G.combo > 1 ? '   x' + G.combo : '');
}

// TELEMETRY, the bare minimum, into the same anonymous log the Godot game used (log.php keeps only fields it already knows, so these are existing names): one environment record, then
// one small record every 10 s. No images, no gaze positions. ?noshare turns it off.
const TEL = { on: !Q.has('noshare') && !Q.has('mouse'), url: 'https://joshuaopolko.com/gaze-lab/log.php', q: [], last: 0, flips: 0, lost: 0, lt: 0, who: '', sid: Math.random().toString(16).slice(2, 8), prevLane: 0, pk0: 0 };
try { TEL.who = localStorage.getItem('spike_id') || ''; if (!TEL.who) { TEL.who = 'spike-' + Math.random().toString(16).slice(2, 8); localStorage.setItem('spike_id', TEL.who); } } catch (e) { TEL.who = 'spike-' + TEL.sid; }
try { new PerformanceObserver((l) => { TEL.lt += l.getEntries().length; }).observe({ type: 'longtask', buffered: false }); } catch (e) { /* not supported */ }
function telSend() {
  if (!TEL.on || !TEL.q.length) return;
  const body = JSON.stringify({ kind: 'batch', who: TEL.who, sid: TEL.sid, device: matchMedia('(pointer: coarse)').matches ? 'mobile' : 'desktop', app: 'spike', items: TEL.q.splice(0, 40) });
  try { fetch(TEL.url, { method: 'POST', body, headers: { 'Content-Type': 'text/plain' }, mode: 'no-cors', keepalive: true }); } catch (e) { /* offline */ }
}
function telTick(now, dt) {
  if (!TEL.on) return;
  if (lane !== TEL.prevLane) { TEL.flips++; TEL.prevLane = lane; }
  if (started && KIT.lost) TEL.lost += dt;
  if (!TEL.last) {
    TEL.last = now;
    let gpu = '';
    try { const g = renderer.getContext(), d = g.getExtension('WEBGL_debug_renderer_info'); gpu = d ? g.getParameter(d.UNMASKED_RENDERER_WEBGL) : ''; } catch (e) { /* no info */ }
    const S = window.__gazeStats || {};
    TEL.q.push({ kind: 'spike_env', hw: { gpu: String(gpu).slice(0, 80), cores: navigator.hardwareConcurrency || 0, mem: navigator.deviceMemory || 0, scr: [screen.width, screen.height, devicePixelRatio || 1], ua: navigator.userAgent.slice(0, 100), url: location.search.slice(0, 60), cam: [S.vw || 0, S.vh || 0] } });
    return;
  }
  if (now - TEL.last < 10000) return;
  const span = (now - TEL.last) / 1000; TEL.last = now;
  const s = fts.slice().sort((a, b) => a - b), med = s[s.length >> 1] || 0, p95 = s[Math.floor(s.length * 0.95)] || 0;
  const S = window.__gazeStats || {};
  const pk = S.pk || 0, trk = (pk - TEL.pk0) / span; TEL.pk0 = pk;
  TEL.q.push({ kind: 'spike', t: +(now / 1000).toFixed(1), gameFps: +(1000 / Math.max(med, 0.1)).toFixed(1), frameP95ms: +p95.toFixed(1), trackerFps: Math.round(trk), modelMs: Math.round(S.inf || 0), latencyMs: Math.round(S.lat || 0),
    mode: 'godot-tracker ' + (S.dlg || '?') + (playing ? '' : (paused ? ' paused' : ' idle')), flips: TEL.flips, lost: +TEL.lost.toFixed(1), face: +(1 - Math.min(1, TEL.lost / span)).toFixed(2),
    lock_t: KIT.tFirst ? +((KIT.tFirst - tStart) / 1000).toFixed(1) : -1, aim_t: KIT.tZones ? +((KIT.tZones - tStart) / 1000).toFixed(1) : -1, scale: KIT.zones ? [+Math.abs(KIT.zones.dl).toFixed(3), +Math.abs(KIT.zones.dr).toFixed(3)] : [0, 0], n: TEL.lt });
  TEL.flips = 0; TEL.lost = 0; TEL.lt = 0;
  telSend();
}
addEventListener('pagehide', telSend);
document.addEventListener('visibilitychange', () => { if (document.hidden) telSend(); });

// THE LOOP
let zPrev = 0, t = 0, zPos = 0, speed = 40, last = performance.now(), lastHud = 0, camX = 0, ping = 0;
const fts = [];
function frame(now) {
  requestAnimationFrame(frame);
  const dtMs = now - last;
  last = now;
  const dt = Math.min(dtMs / 1000, 0.1);
  t += dt;
  fts.push(dtMs);
  if (fts.length > 240) fts.shift();
  if (eyeMode && started) { readTracker(now); updateLane(); }
  telTick(now, dt);
  steer += (steerTarget - steer) * (1 - Math.exp(-6 * dt));
  speed = Math.min(Math.min(110, 40 + t * 1.2), speed + 25 * dt);          // (a crash halves it; it climbs back at 25 m/s per second, up to the pace of the run)
  zPrev = zPos;
  if (playing) zPos -= speed * dt;
  camX += (steer * LANE_W - camX) * (1 - Math.exp(-5 * dt));
  camera.position.set(camX, 2.2, zPos);
  camera.rotation.set(-0.08, -steer * 0.08, -steer * 0.12, 'YXZ');
  camera.aspect = W / H;
  camera.updateProjectionMatrix();
  groundMat.uniforms.uT.value = t;
  groundMat.uniforms.uMoire.value = flags.moire ? 1 : 0;
  groundMat.uniforms.uCam.value.copy(camera.position);
  ground.position.set(camera.position.x, 0, camera.position.z - 300);
  for (const mm of [pylMesh, ringMesh, orbMesh, wallMesh]) mm.visible = flags.objects;
  if (flags.objects) {
    for (let i = 0; i < N_PYL; i++) {
      const p = pyl[i];
      if (p.z > zPos + 20) { p.z -= SPAN; p.x = (Math.random() < 0.5 ? -1 : 1) * (12 + Math.random() * 26); }
      m4.compose(v3.set(p.x, 3.5 * p.s, p.z), q4.identity(), s3.set(p.s, p.s, p.s));
      pylMesh.setMatrixAt(i, m4);
      pylMesh.setColorAt(i, colr.copy(hue(t * 0.05 + p.z * 0.003)));
    }
    pylMesh.instanceMatrix.needsUpdate = true;
    if (pylMesh.instanceColor) pylMesh.instanceColor.needsUpdate = true;
    stepRows(dt);
  }
  if (flags.tracers || flags.split) {
    renderer.setRenderTarget(sceneRT);
    renderer.render(scene, camera);
    let trailTex = trailA.texture;
    if (flags.tracers) {
      const src = ping ? trailB : trailA, dst = ping ? trailA : trailB;
      ping ^= 1;
      feedMat.material.uniforms.uScene.value = sceneRT.texture;
      feedMat.material.uniforms.uPrev.value = src.texture;
      renderer.setRenderTarget(dst);
      renderer.render(feedScene, quadCam);
      trailTex = dst.texture;
    }
    compMat.material.uniforms.uScene.value = sceneRT.texture;
    compMat.material.uniforms.uTrail.value = trailTex;
    compMat.material.uniforms.uTrace.value = flags.tracers ? 1 : 0;
    compMat.material.uniforms.uSplit.value = flags.split ? 1 : 0;
    compMat.material.uniforms.uFlash.value.set(G.fr, G.fg, G.fb, G.flash);
    renderer.setRenderTarget(null);
    renderer.render(compScene, quadCam);
  } else {
    renderer.setRenderTarget(null);
    renderer.render(scene, camera);
  }
  if (now - lastHud > 500) {
    lastHud = now;
    const s = fts.slice().sort((a, b) => a - b), med = s[s.length >> 1] || 0, p95 = s[Math.floor(s.length * 0.95)] || 0;
    const S = window.__gazeStats || {};
    window.__spike = { fps: +(1000 / Math.max(med, 0.1)).toFixed(1), ft50: +med.toFixed(1), ft95: +p95.toFixed(1) };
    hud.textContent = 'SPIKE  ' + window.__spike.fps + ' fps   ft50 ' + med.toFixed(1) + ' ms   ft95 ' + p95.toFixed(1) + ' ms   ' + W + 'x' + H + '\n'
      + (eyeMode ? 'tracker ' + (S.dlg || '?') + '  model ' + Math.round(S.inf || 0) + ' ms  latency ' + Math.round(S.lat || 0) + ' ms  camera ' + (S.vw || 0) + 'x' + (S.vh || 0) + '  ' + (window.__gazeStatus || '') + '\n'
        + 'zone ' + ['LEFT', 'MIDDLE', 'RIGHT'][KIT.zone + 1] + '  zn ' + KIT.zn.toFixed(2) + '  ' + (KIT.zones ? 'sides L ' + Math.abs(KIT.zones.dl).toFixed(3) + ' R ' + Math.abs(KIT.zones.dr).toFixed(3) : 'learning the middle...') + (KIT.lost ? '  FACE LOST' : '') + (KIT.held ? '  (blink)' : '') : 'mouse')
      + '\nscore ' + G.score + '  gates hit ' + G.got + ' missed ' + G.hit;
  }
}
requestAnimationFrame(frame);
