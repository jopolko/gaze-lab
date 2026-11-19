// OPTION 1 (spike-light): Godot's zone logic (KitEye, with its constants lowered a little) on the LIGHT tracker (STARGAZE's, in a worker, on the graphics chip, 1280x720 whole frames,
// about 50 ms a frame instead of Godot's ~110), plus each side learning from the player's own glances in both directions.
// SPIKE: the smallest version of the game that still has the look. A road of glowing squares (one shader, one plane), wireframe pylons, rings, loot and gates (instanced), and ONE
// full-screen pass that makes tracers (a half-size feedback buffer) and splits the colours.
//
// THE EYES: STARGAZE's tracker (../stargaze/tracker.js) in a worker on the graphics chip, whole 1280x720 frames. Its steady iris readings (hx) go to KitEye.gd's zone logic, ported line
// for line below (middle learned from the first 40 readings, a look to a side starting at AUTO_D, the median of the last readings, an enter line and a leave line), with three changes:
// the enter / leave lines are 0.35 / 0.2 (Godot 0.5 / 0.3), and each side also learns from the player's own glances in both directions. The lane IS the zone and the board slides there.
import * as THREE from 'three';
import { Tracker } from '../stargaze/tracker.js';

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
      col += vec3(.0,.9,1.) * (1.0 - smoothstep(.0, .25, abs(abs(wp.x) - 38.)));
      gl_FragColor = vec4(col * fade, 1.0);
    }`,
});
const ground = new THREE.Mesh(new THREE.PlaneGeometry(900, 900, 1, 1), groundMat);
ground.rotation.x = -Math.PI / 2;
ground.frustumCulled = false;
scene.add(ground);

// OBJECTS: wireframe pylons down both sides, rings, loot and gates, all instanced.
const N_PYL = 160, N_RING = 10, SPAN = 520, LANE_W = 22, ROW_GAP = SPAN / N_RING;          // wide lanes: the choices must be far apart ON THE SCREEN (at 70 m ahead, lanes 8 m apart sit within about 4 degrees of each other, too close for the eyes to tell apart)
const pylMesh = new THREE.InstancedMesh(new THREE.ConeGeometry(1.6, 7, 5, 1, true), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_PYL);
const ringMesh = new THREE.InstancedMesh(new THREE.TorusGeometry(9, 0.18, 3, 28), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING);
const orbMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(1.5, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 6);
const wallMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 2, 7, 2), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_RING * 2);
const beamMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1.6, 90, 1.6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING);          // a tall beam over each row's lane: visible from far away, so the choice can be seen (and looked at) long before the ring itself
const padMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 4, 0.5, 18), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING);          // a glowing pad on the ground at the open lane: the base of the gate, low on the screen, where the eyes rest (looking up at a high ring tilted the eyes and made the reading worse)
for (const mm of [pylMesh, ringMesh, orbMesh, wallMesh, beamMesh, padMesh]) { mm.frustumCulled = false; scene.add(mm); }
// Ten rows ahead at any time, one every 52 m, each either a string of six glowing orbs in one lane, or a GATE: a ring marks the open lane and barriers fill the other two.
const rows = [];
function setRow(r, z) {
  r.z = z; r.type = Math.random() < 0.55 ? 0 : 1; r.lane = Math.floor(Math.random() * 3) - 1; r.done = false;
  r.orbs = [0, 1, 2, 3, 4, 5].map(() => true);
}
for (let i = 0; i < N_RING; i++) { const r = { i }; setRow(r, -50 - i * ROW_GAP); rows.push(r); }
const pyl = [];
for (let i = 0; i < N_PYL; i++) pyl.push({ z: -Math.random() * SPAN, x: (Math.random() < 0.5 ? -1 : 1) * (LANE_W * 1.5 + 8 + Math.random() * 34), s: 1.2 + Math.random() * 2 });
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
  lastHx: null, tFirst: 0, tZones: 0, zones: null, zone: 0, zn: 0, zh: [], zh_n: 3, zdrift: 0, zbuf: [], zall: [], zbt: 0, zside: 0, zpk: 0, zauto: [],
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
        const tgt = clampf(this.zpk * this.GROW, 0.022, 0.03), cur = Math.abs(z[k]);          // (Godot used the full peak)
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
    this.zall.push(hx); if (this.zall.length > 360) this.zall.shift();
    if (this.zone === 0 || Math.abs(this.zn) > 2.2 || this.zside > 8) { this.zbuf.push(hx); if (this.zbuf.length > 360) this.zbuf.shift(); }          // only readings taken while the eyes were in the MIDDLE shape the middle (plus a way out if it is badly off: a reading more than 2.2 sides away, or 8 s on one side, also counts, or a wrong middle could never be corrected): a long run of looks to one side must not drag it over there (the lane then dropped back to the middle while still looking right)
    this.zbt += dt;
    if (this.zbt >= 0.5 && this.zbuf.length >= 60 && z.auto) {
      this.zbt = 0;
      const m0 = z.m + this.zdrift;
      const sb = this.zbuf.slice().sort((a, b) => a - b), qq = (p) => sb[Math.min(sb.length - 1, Math.floor(p * sb.length))];
      const spanMid = median(this.zbuf);          // the middle sits half way between the median and the centre of the span of looks: the left gap and the right gap were 0.014 and 0.022
      z.m = z.m + (spanMid - m0) * 0.35;
      // EACH SIDE ALSO LEARNS FROM THE PLAYER'S OWN GLANCES, in both directions (Godot's only ever grows a side, from looks that cross the line, so a side whose glances are smaller than the
      // starting size never gets fixed): over the last ~12 s, readings clearly away from the middle (past 0.012) set that side to their 90th percentile / 0.75, within 0.02 to 0.06.
      const mid = z.m + this.zdrift;
      for (const side of [1, -1]) {
        const k = side > 0 ? 'dl' : 'dr', v = this.zall.map((h) => (h - mid) * side).filter((x) => x > 0.012).sort((a, b) => a - b);
        if (v.length >= 12) { const p90 = v[Math.floor(v.length * 0.9)], tg = clampf(p90 / 0.75, 0.022, 0.03); z[k] = Math.sign(z[k]) * (Math.abs(z[k]) + (tg - Math.abs(z[k])) * 0.25); }
      }
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
const video = document.createElement('video');
video.playsInline = true; video.muted = true; video.autoplay = true; video.style.cssText = 'position:fixed;right:0;bottom:0;width:2px;height:2px;opacity:.01;pointer-events:none';
document.body.appendChild(video);
let tracker = null, pkCount = 0;
window.__gazeStatus = 'idle';
if (eyeMode) {
  say('LOOK TO STEER', '', 'START', async () => {
    tStart = performance.now(); say('Opening your eyes', 'loading the tracker...');
    try {
      tracker = new Tracker(video);
      tracker.camW = 1280; tracker.camH = 720; tracker.fullRes = true; tracker.useWorker = true;
      tracker.onSteady = (hx, t) => { pkCount++; KIT.add(hx, 0, 0, t); };          // (the tracker already holds readings through blinks, so the blink inputs are zero here)
      await tracker.start((st) => { $('mp').textContent = st; window.__gazeStatus = st === 'ready' ? 'camera on' : st; }, Q.get('fakecam'));
      window.__gazeStatus = 'camera on';
      beginPlay();
    } catch (e) {
      window.__gazeStatus = 'error';
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
  window.__gazeStats = { pk: pkCount, inf: tracker ? tracker.modelMs : 0, lat: 0, dlg: tracker ? (tracker.delegate || '') : '', vw: video.videoWidth, vh: video.videoHeight };
  KIT.idle(now / 1000, 1 / 60);
  KIT.zh_n = 3;          // (Godot used 2 at speed. With the lowered thresholds 2 readings flipped the lane 15 to 19 times in 10 s, so it is 3 here)
}
// LOCK-ON, the way RunRig.gd chose things (this is what made Godot forgiving, and why it needed no calibration): the zone is NOT the lane. Each lane keeps a leaky "want": it fills while
// the eyes are in that lane's zone (the middle only at 0.35 of the pace, because resting eyes go there), and drains when they are elsewhere (3x as fast when the eyes are on a side).
// A lane takes the lock after a ninth of a second at first; once locked it holds however the eyes wander, committed for half a second, and a change of mind then needs a steadier look
// (0.35 s), then 0.14 s once the commitment is over. The board slides to the locked lane, so one glance starts a move that finishes by itself.
const LOCK = { want: { '-1': 0, '0': 0, '1': 0 }, lane: 0, age: 9 };
function lockStep(zone, dt) {
  const qk = 0.7;          // at speed everything about choosing is quicker (Godot: qk 0.6 flat out)
  for (const l of [-1, 0, 1]) {
    if (zone === l) LOCK.want[l] = Math.min(LOCK.want[l] + dt * (l === 0 ? 0.35 : 1.0), 0.5);
    else LOCK.want[l] = Math.max(LOCK.want[l] - dt * (zone !== 0 ? 3.0 : 0.6), 0);
  }
  LOCK.age += dt;
  const need = (LOCK.age >= 0.8 * qk ? 0.16 : 0.45) * qk;          // (Godot: committed 0.5 s, then 0.14 / 0.35. Stickier here: the lane still changed 10 to 18 times in 10 s, about twice what the gates ask for)
  // a side lane is held until the eyes clearly go somewhere else: returning to the MIDDLE needs a steady look there (about 0.8 s), because following a target that moves inward as it nears reads as 'middle' for a moment
  for (const l of [-1, 0, 1]) if (l !== LOCK.lane && LOCK.want[l] > (l === 0 && LOCK.lane !== 0 ? 0.28 : need)) { LOCK.lane = l; LOCK.age = 0; break; }
  return LOCK.lane;
}
function nextGate() {          // the open lane of the nearest gate still ahead (within 220 m), or null
  let best = null, bz = -1e9;
  for (const r of rows) if (r.type === 1 && !r.done && r.z < zPos && r.z > bz && zPos - r.z < 220) { bz = r.z; best = { lane: r.lane, dist: zPos - r.z }; }
  return best;
}
function updateLane(dt) {
  if (!KIT.zones) {          // the first 40 readings are still coming in: the board stays in the middle, but the dot already follows the eyes (against the middle seen so far, at the starting size)
    lane = 0; steerTarget = 0;
    if (KIT.lastHx !== null && KIT.zauto.length) {
      const d = KIT.lastHx - median(KIT.zauto), zn = clampf(d > 0 ? -d / KIT.AUTO_D : -d / KIT.AUTO_D, -1.6, 1.6);
      const gd0 = $('gdot'); gd0.style.left = ((Math.tanh(zn * 0.8) * 0.45 + 0.5) * innerWidth) + 'px'; gd0.style.top = (innerHeight * 0.5) + 'px';
    }
    return;
  }
  lane = lockStep(KIT.zone, dt); steerTarget = lane;
  const ng = nextGate(), cz = $('zones').children;
  for (let i = 0; i < 3; i++) { const l = i - 1, c = []; if (l === lane) c.push('on'); if (ng && ng.lane === l) c.push('tg'); if (l === KIT.zone) c.push('zn'); cz[i].className = c.join(' '); }
  const gd = $('gdot'); gd.style.left = ((Math.tanh(KIT.zn * 0.8) * 0.45 + 0.5) * innerWidth) + 'px';          // (squashed so it always stays on the screen: the sides are at about 0.5 either way) gd.style.top = (innerHeight * 0.5) + 'px';
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
        const oc = r.orbs[k] && oz <= zPrev && oz > zPos - 1 && Math.abs(camX - r.lane * LANE_W) < 8.0;
        if (oc) { r.orbs[k] = false; G.combo++; G.best = Math.max(G.best, G.combo); G.score += 10 * (1 + Math.floor(G.combo / 8)); G.got++; flash(0, 1, 0.8, 0.28); beep(440 + Math.min(G.combo, 14) * 40, 0.12, 0.08); }
        m4.compose(v3.set(ox, 2.6, oz), q4.identity(), s3.setScalar(r.orbs[k] ? 1 : 0.0001));
        orbMesh.setMatrixAt(i * 6 + k, m4); orbMesh.setColorAt(i * 6 + k, colr.copy(hue(t * 0.3 + k * 0.06 + i * 0.1)));
      }
      m4.compose(v3.set(0, -50, r.z), q4.identity(), s3.setScalar(0.0001)); wallMesh.setMatrixAt(i * 2, m4); wallMesh.setMatrixAt(i * 2 + 1, m4);
      ringMesh.setMatrixAt(i, m4);
      m4.compose(v3.set(r.lane * LANE_W, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(i, m4); beamMesh.setColorAt(i, colr.setRGB(0.2, 1, 0.5));
      m4.compose(v3.set(r.lane * LANE_W, 0.25, r.z), q4.identity(), s3.setScalar(1)); padMesh.setMatrixAt(i, m4); padMesh.setColorAt(i, colr.setRGB(0.1, 0.6, 0.3));
    } else {
      m4.compose(v3.set(r.lane * LANE_W, 4.5, r.z), q4.identity(), s3.setScalar(0.8)); ringMesh.setMatrixAt(i, m4);
      m4.compose(v3.set(r.lane * LANE_W, 0.25, r.z), q4.identity(), s3.setScalar(1)); padMesh.setMatrixAt(i, m4); padMesh.setColorAt(i, colr.setRGB(1, 0.9 * (0.6 + 0.4 * Math.sin(t * 6)), 0.1));
      m4.compose(v3.set(r.lane * LANE_W, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(i, m4); beamMesh.setColorAt(i, colr.setRGB(1, 0.9, 0.2));
      ringMesh.setColorAt(i, colr.copy(hue(t * 0.1 + i * 0.13)));
      let w = 0;
      for (let l = -1; l <= 1; l++) {
        if (l === r.lane) continue;
        m4.compose(v3.set(l * LANE_W, 3.5, r.z), q4.identity(), s3.setScalar(1)); wallMesh.setMatrixAt(i * 2 + w, m4);
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
  for (const mm of [orbMesh, wallMesh, ringMesh, beamMesh, padMesh]) { mm.instanceMatrix.needsUpdate = true; if (mm.instanceColor) mm.instanceColor.needsUpdate = true; }
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
    mode: 'light-tracker ' + (S.dlg || '?') + (playing ? '' : (paused ? ' paused' : ' idle')), flips: TEL.flips, lost: +TEL.lost.toFixed(1), face: +(1 - Math.min(1, TEL.lost / span)).toFixed(2),
    lock_t: KIT.tFirst ? +((KIT.tFirst - tStart) / 1000).toFixed(1) : -1, aim_t: KIT.tZones ? +((KIT.tZones - tStart) / 1000).toFixed(1) : -1, scale: KIT.zones ? [+Math.abs(KIT.zones.dl).toFixed(3), +Math.abs(KIT.zones.dr).toFixed(3)] : [0, 0], n: TEL.lt });
  TEL.flips = 0; TEL.lost = 0; TEL.lt = 0;
  telSend();
}
addEventListener('pagehide', telSend);
document.addEventListener('visibilitychange', () => { if (document.hidden) telSend(); });

// EYES VERSUS BOARD: ten samples a second go to the spike server (web/spike/logs/*.jsonl) so a run can be compared afterwards: the iris reading, the zone, the locked lane, where the board
// is, and the nearest gate ahead (which lane is open, how far). cols: t, hx, zn, zone, lockLane, camX, nextOpenLane, dist, speed, held, lockWants(L,M,R)
const LOG = { buf: [], last: 0, sid: Math.random().toString(16).slice(2, 8) };
function logSample(now) {
  if (!started || !playing || !eyeMode || now - LOG.last < 100 || KIT.lastHx === null) return;          // (not while paused: a paused run logged the same gate hundreds of times)
  LOG.last = now;
  let open = 9, dist = -1, bz = -1e9;
  for (const r of rows) if (r.type === 1 && !r.done && r.z < zPos && r.z > bz) { bz = r.z; open = r.lane; dist = zPos - r.z; }
  LOG.buf.push([+(now / 1000).toFixed(2), +KIT.lastHx.toFixed(4), +KIT.zn.toFixed(2), KIT.zone, LOCK.lane, +camX.toFixed(1), open, +dist.toFixed(0), +speed.toFixed(0), KIT.held ? 1 : 0, +LOCK.want[-1].toFixed(2), +LOCK.want[0].toFixed(2), +LOCK.want[1].toFixed(2)]);
  if (LOG.buf.length >= 50) flushLog();
}
function flushLog() {
  if (!LOG.buf.length) return;
  const body = JSON.stringify({ sid: LOG.sid, app: 'spike-light', cols: 't,hx,zn,zone,lock,camX,open,dist,speed,held,wL,wM,wR', m: KIT.zones ? KIT.zones.m : 0, dl: KIT.zones ? KIT.zones.dl : 0, dr: KIT.zones ? KIT.zones.dr : 0, s: LOG.buf });
  LOG.buf = [];
  try { fetch('/spike/log', { method: 'POST', body, keepalive: true }); } catch (e) { /* no server */ }
}
addEventListener('pagehide', flushLog);

// THE LOOP
let zPrev = 0, t = 0, zPos = 0, speed = 28, last = performance.now(), lastHud = 0, camX = 0, ping = 0;
const fts = [];
function frame(now) {
  requestAnimationFrame(frame);
  const dtMs = now - last;
  last = now;
  const dt = Math.min(dtMs / 1000, 0.1);
  t += dt;
  fts.push(dtMs);
  if (fts.length > 240) fts.shift();
  if (eyeMode && started) { readTracker(now); updateLane(dt); }
  telTick(now, dt);
  logSample(now);
  steer += (steerTarget - steer) * (1 - Math.exp(-6 * dt));
  speed = Math.min(Math.min(60, 28 + t * 0.4), speed + 15 * dt);          // slower than before (it was up to 110): time to look, choose, and let the board slide          // (a crash halves it; it climbs back at 25 m/s per second, up to the pace of the run)
  zPrev = zPos;
  if (playing) zPos -= speed * dt;
  camX += (steer * LANE_W - camX) * (1 - Math.exp(-5 * dt));
  camera.position.set(camX, 3.2, zPos);
  camera.rotation.set(-0.08, -steer * 0.08, -steer * 0.12, 'YXZ');
  camera.aspect = W / H;
  camera.updateProjectionMatrix();
  groundMat.uniforms.uT.value = t;
  groundMat.uniforms.uMoire.value = flags.moire ? 1 : 0;
  groundMat.uniforms.uCam.value.copy(camera.position);
  ground.position.set(camera.position.x, 0, camera.position.z - 300);
  for (const mm of [pylMesh, ringMesh, orbMesh, wallMesh, beamMesh, padMesh]) mm.visible = flags.objects;
  if (flags.objects) {
    for (let i = 0; i < N_PYL; i++) {
      const p = pyl[i];
      if (p.z > zPos + 20) { p.z -= SPAN; p.x = (Math.random() < 0.5 ? -1 : 1) * (LANE_W * 1.5 + 8 + Math.random() * 34); }
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
