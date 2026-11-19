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
import { EyeModel } from './eyemodel.js?v=1795094018';

const Q = new URLSearchParams(location.search);
const EYE_PICK = Q.get('eye') || '';
// THE EYE MODEL (eyemodel.js): a three-state filter over both eyes together that floats with drift and remembers what it learned on this device. ?nomodel goes back to the threshold detector.
// LIVE TUNING: tune.json beside the log (web/spike/tune.json) is read every 2 s and applied to the running game, so settings can be changed while it is being played. {"v":N,"EM":{"DECIDE":0.8,...},"LOCK":{"qk":0.7,"midhold":0.28},"KIT":{...},"recentre":true}
const TUNE = { qk: 0.7, midhold: 0.28, steerK: 14, camK: 10, v: -1 };          // steerK / camK: how fast the steering and the board follow the chosen lane (they were 6 and 5: the board took 0.31 s to get half way across, and 20% of rows were passed before it arrived)
let EM = null;
// PROFILES (per device, in this browser only): up to three sets of learned left / right offsets (glasses on, glasses off, another person). The most recent one is the starting point; when there are two or more, the
// first few labelled looks of the session choose the one that fits them best (profChoose), and what is learned is written back to it (profStore). A first run on a device shows the LOOK HERE rings once.
if (Q.has('resetprofiles')) { try { localStorage.removeItem('spike_profiles'); localStorage.removeItem('spike_cal_done'); localStorage.removeItem('spike_eye'); } catch (e) { /* */ } }          // ?resetprofiles forgets everything learned about eyes on this device
const PROF = { list: [], cur: -1, chosen: false };
let CAL_DONE = false; try { CAL_DONE = localStorage.getItem('spike_cal_done') === '1'; } catch (e) { /* */ }
function profSave() { try { localStorage.setItem('spike_profiles', JSON.stringify(PROF.list)); } catch (e) { /* */ } }
if (!Q.has('nomodel')) {
  try { PROF.list = JSON.parse(localStorage.getItem('spike_profiles') || '[]'); } catch (e) { PROF.list = []; }
  let pr = null;
  if (PROF.list.length) { PROF.cur = PROF.list.reduce((b, p, i) => (p.t > PROF.list[b].t ? i : b), 0); pr = { dL: PROF.list[PROF.cur].dL, dR: PROF.list[PROF.cur].dR, B: PROF.list[PROF.cur].B }; }
  EM = new EyeModel(pr); EM.hold = PROF.list.length > 1;          // with several profiles the first labelled looks choose one before any learning
}
function profChoose() {
  const dflt = EM.fit([0.02, 0.02], [0.02, 0.02], EM.labeled); let best = -1, bs = 1e9;
  PROF.list.forEach((p, i) => { const sc = EM.fit(p.dL, p.dR, EM.labeled); if (sc < bs) { bs = sc; best = i; } });
  EM.hold = false; PROF.chosen = true;
  if (best >= 0 && bs < dflt * 1.2) { EM.dL = PROF.list[best].dL.slice(); EM.dR = PROF.list[best].dR.slice(); if (PROF.list[best].B) EM.B = PROF.list[best].B.map((r) => r.slice()); PROF.cur = best; }
  else {          // none fits: a new person (or new glasses). A new profile is made when saving, the sizes start from the defaults, and the LOOK HERE rings are shown once for them
    PROF.cur = -1; EM.dL = [0.02, 0.02]; EM.dR = [0.02, 0.02]; EM.B = [[0, 0, 0], [0, 0, 0]];
    if (GUIDE.on && GUIDE.pending === 0) { GUIDE.pending = 3; GUIDE.bSize = 3; GUIDE.bTried = 0; GUIDE.bHits = 0; bannerShow('NEW PLAYER: LOOK AT THE RINGS', true); }
  }
}
function profStore() {
  const p = { dL: EM.dL.slice(), dR: EM.dR.slice(), B: EM.B.map((r) => r.slice()), t: Date.now() };
  const rel = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]) / Math.max(Math.hypot(b[0], b[1]), 0.02);
  if (PROF.cur >= 0 && (rel(p.dL, PROF.list[PROF.cur].dL) > 0.7 || rel(p.dR, PROF.list[PROF.cur].dR) > 0.7)) PROF.cur = -1;          // it has drifted far from this profile: it is probably someone else, so it does not overwrite it
  if (PROF.cur >= 0) PROF.list[PROF.cur] = p; else { PROF.list.push(p); if (PROF.list.length > 3) PROF.list.shift(); PROF.cur = PROF.list.length - 1; }
  profSave();
}
// WHICH EYE (glasses and lenses can distort one eye). The two eyes' readings are kept apart for the last ~25 s and each is judged at the moments BOTH eyes agree you looked left or right: the 15% of readings
// where the two-eye average is furthest left, the 15% furthest right, against the middle 40%. An eye's score is its WEAKER side (how far it moves for a look that way) over its jitter, so an eye that barely
// responds on one side, or is noisy, scores low. In play the looks are small and the eyes can not be told apart, so it only switches on strong evidence (a clear 1.5x win and a real spread of looks), and the
// choice is remembered on this device (localStorage spike_eye). Until it is sure both eyes are averaged. ?eye=a / ?eye=b force one (and remember it); ?eye=auto forgets.
let eyeSaved = ''; try { eyeSaved = localStorage.getItem('spike_eye') || ''; } catch (e) { /* no storage */ }
if (EYE_PICK === 'auto') { try { localStorage.removeItem('spike_eye'); } catch (e) { /* */ } eyeSaved = ''; }
if (EYE_PICK === 'a' || EYE_PICK === 'b') { try { localStorage.setItem('spike_eye', EYE_PICK.toUpperCase()); } catch (e) { /* */ } }
const EYE = { sel: EYE_PICK === 'a' ? 'A' : EYE_PICK === 'b' ? 'B' : (eyeSaved === 'A' || eyeSaved === 'B') ? eyeSaved : 'avg', bufA: [], bufB: [], t: 0, sA: 0, sB: 0, spread: 0, auto: EYE_PICK !== 'a' && EYE_PICK !== 'b' && !EM, switches: 0 };
function eyeScores(A, B) {
  const n = Math.min(A.length, B.length); if (n < 100) return null;
  const a = A.slice(-n), b = B.slice(-n), avg = a.map((x, i) => (x + b[i]) / 2), idx = avg.map((v, i) => i).sort((i, j) => avg[i] - avg[j]);
  const k = Math.floor(n * 0.15), lo = idx.slice(0, k), hi = idx.slice(n - k), mid = idx.slice(Math.floor(n * 0.3), Math.floor(n * 0.7));
  const mean = (v, ix) => ix.reduce((t, i) => t + v[i], 0) / ix.length;
  const jit = (v) => { let j = 0; for (let i = 1; i < v.length; i++) j += Math.abs(v[i] - v[i - 1]); return j / (v.length - 1); };
  const one = (v) => { const c = mean(v, mid), up = mean(v, hi) - c, dn = c - mean(v, lo); return { med: c, score: Math.max(0, Math.min(up, dn)) / (jit(v) + 0.002) }; };
  return { A: one(a), B: one(b), spread: Math.abs(mean(avg, hi) - mean(avg, lo)) };
}
function eyeAuto(t) {
  if (!EYE.auto || t - EYE.t < 2) return; EYE.t = t;
  const r = eyeScores(EYE.bufA, EYE.bufB); if (!r) return;
  EYE.sA = r.A.score; EYE.sB = r.B.score; EYE.spread = r.spread;
  if (r.spread < 0.05) return;          // no real looking around yet: can not tell
  const want = r.A.score > r.B.score * 1.5 ? 'A' : r.B.score > r.A.score * 1.5 ? 'B' : EYE.sel;
  if (want === EYE.sel) return;
  const nb = want === 'A' ? EYE.bufA : EYE.bufB;
  if (KIT.zones) { const old = median(KIT.zall.slice(-300)); KIT.zones.m += (want === 'A' ? r.A.med : r.B.med) - old; KIT.zall = nb.slice(-300); KIT.zbuf = []; KIT.zh = []; }          // the new eye reads at a different level: move the middle with it
  EYE.sel = want; EYE.switches++;
  try { localStorage.setItem('spike_eye', want); } catch (e) { /* no storage */ }
}
const RS = Math.min(1, Math.max(0.3, parseFloat(Q.get('rs') || '1')));
// MUSIC: the funk tracks of the Godot game, played in turn (the server maps /music/ to godot/music_web). M mutes. ?nomusic turns it off.
const TRACKS = ['funk_it', 'quirky_funk', 'funk_express'];
let song = null, songI = 0, musicOn = !Q.has('nomusic');
function startMusic() {
  if (!musicOn || song) return;
  song = new Audio('../music/' + TRACKS[songI] + '.ogg'); song.volume = 0.55;
  song.onended = () => { songI = (songI + 1) % TRACKS.length; song.src = '../music/' + TRACKS[songI] + '.ogg'; song.play().catch(() => {}); };
  song.play().catch(() => {});
}
function toggleMusic() { musicOn = !musicOn; if (song) { if (musicOn) song.play().catch(() => {}); else song.pause(); } else startMusic(); }
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
const camera = new THREE.PerspectiveCamera(85, 1, 0.1, 700);
const hue = (h) => new THREE.Color().setHSL(((h % 1) + 1) % 1, 1, 0.55);

// THE WORLDS (Themes.gd): a sky, a ground pattern (mode), two colours the objects wear, and how strongly the tracers and the colour split work. The journey cycles through them.
// rainbow 1 = objects cycle through every hue (psychedelic); wire = objects drawn as wireframes (the neon worlds) or solid (the daylight ones); sun = a sun disc on the horizon.
const THEMES = [
  { id: 'alpine',      name: 'ALPINE',      mode: 0, top: [0.12, 0.35, 0.85], hor: [0.62, 0.75, 0.95], c1: [0.06, 0.30, 0.16], c2: [0.30, 0.55, 0.70], wire: false, rainbow: 0, sun: 0.0, trace: 0.10, split: 0.15, fog: 1.0 },
  { id: 'psychedelic', name: 'PSYCHEDELIC', mode: 1, top: [0.08, 0.00, 0.20], hor: [0.55, 0.08, 0.65], c1: [1.00, 0.25, 0.85], c2: [0.20, 0.90, 1.00], wire: true,  rainbow: 1, sun: 0.0, trace: 1.00, split: 1.00, fog: 1.0 },
  { id: 'candy',       name: 'CANDYLAND',   mode: 4, top: [0.70, 0.62, 1.00], hor: [1.00, 0.84, 0.88], c1: [1.00, 0.45, 0.72], c2: [0.50, 0.95, 0.80], wire: false, rainbow: 0, sun: 0.0, trace: 0.25, split: 0.30, fog: 1.0 },
  { id: 'tunnel',      name: 'TUNNEL ROAD', mode: 2, top: [0.02, 0.00, 0.08], hor: [0.40, 0.08, 0.45], c1: [0.15, 0.85, 1.00], c2: [1.00, 0.25, 0.80], wire: true,  rainbow: 0, sun: 0.0, trace: 0.70, split: 0.70, fog: 1.0 },
  { id: 'synthwave',   name: 'SYNTHWAVE',   mode: 7, top: [0.05, 0.00, 0.18], hor: [1.00, 0.30, 0.60], c1: [1.00, 0.20, 0.70], c2: [0.20, 0.80, 1.00], wire: true,  rainbow: 0, sun: 1.0, trace: 0.70, split: 0.60, fog: 1.0 },
  { id: 'matrix',      name: 'DIGITAL',     mode: 6, top: [0.00, 0.02, 0.00], hor: [0.00, 0.14, 0.05], c1: [0.10, 1.00, 0.35], c2: [0.60, 1.00, 0.75], wire: true,  rainbow: 0, sun: 0.0, trace: 0.80, split: 0.40, fog: 1.0 },
  { id: 'desert',      name: 'DESERT SUN',  mode: 3, top: [0.90, 0.30, 0.35], hor: [1.00, 0.55, 0.40], c1: [0.55, 0.85, 0.65], c2: [1.00, 0.80, 0.45], wire: false, rainbow: 0, sun: 1.0, trace: 0.20, split: 0.40, fog: 1.0 },
  { id: 'egypt',       name: 'EGYPT',       mode: 5, top: [0.20, 0.45, 0.85], hor: [1.00, 0.82, 0.50], c1: [1.00, 0.78, 0.25], c2: [0.15, 0.80, 0.75], wire: false, rainbow: 0, sun: 0.6, trace: 0.20, split: 0.30, fog: 1.0 },
];
const TH = { mode: 0, wire: false, rainbow: 0, sun: 0, trace: 1, split: 1, top: new THREE.Color(), hor: new THREE.Color(), c1: new THREE.Color(), c2: new THREE.Color(), idx: -1 };
const themeCol = (phase, out) => (TH.rainbow > 0.5 ? out.copy(hue(phase)) : out.copy(TH.c1).lerp(TH.c2, 0.5 + 0.5 * Math.sin(phase * 6.2832)));

// THE GROUND: one plane that follows the rider; the pattern is computed from world position, so it is fixed to the ground as you speed by. One shader, eight looks (uMode).
const groundMat = new THREE.ShaderMaterial({
  uniforms: { uT: { value: 0 }, uMode: { value: 1 }, uCam: { value: new THREE.Vector3() }, uC1: { value: TH.c1 }, uC2: { value: TH.c2 }, uHor: { value: TH.hor } },
  vertexShader: 'varying vec3 wp; void main(){ vec4 w = modelMatrix * vec4(position,1.0); wp = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }',
  fragmentShader: `
    precision mediump float;
    varying vec3 wp;
    uniform float uT;
    uniform float uMode;
    uniform vec3 uCam, uC1, uC2, uHor;
    vec3 hsv(float h){ return clamp(abs(fract(vec3(h)+vec3(0.,.6667,.3333))*6.-3.)-1.,0.,1.); }
    float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float gline(vec2 p, float w){ vec2 f = abs(fract(p)-.5); vec2 d = fwidth(p)*w; vec2 l = smoothstep(.5-d, vec2(.5), f); return max(l.x, l.y); }
    void main(){
      float dist = length(wp.xz - uCam.xz);
      vec3 col;
      float m = uMode;
      if (m < 0.5) {                                                    // ALPINE: snow, a faint blue checker, long blue shadows of the lane lines
        float chk = step(0., sin(wp.x*.5236)*sin(wp.z*.5236));
        col = mix(vec3(.58,.68,.86), vec3(.72,.80,.94), chk);
        col -= vec3(.10,.06,.0) * gline(wp.xz/12., 1.0);
      } else if (m < 1.5) {                                             // PSYCHEDELIC: two grids of squares that fall in and out of step (moire), coloured by how far in step they are
        float a = gline(wp.xz / 6.0, 1.2);
        float ang = .035 + .02*sin(uT*.1);
        vec2 q = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * wp.xz;
        float b = gline(q / 5.8 + vec2(uT*.05, 0.), 1.2) * .8;
        col = hsv(fract(dist*.004 - uT*.05 + wp.z*.002)) * (a*.9 + b*.7);
      } else if (m < 2.5) {                                             // TUNNEL ROAD: chevrons racing at you
        float v = abs(fract(wp.z/7. + abs(wp.x)*.045) - .5);
        float ch = smoothstep(.34, .44, v);
        col = vec3(.02,.0,.05) + mix(uC1, uC2, step(0., sin(wp.x*.08+uT*.4))) * ch * .9;
      } else if (m < 3.5) {                                             // DESERT: rippled rust sand and a faint grid
        float s = .5 + .5*sin(wp.x*.13 + sin(wp.z*.035)*3. + sin(wp.x*.04)*2.);
        col = mix(vec3(.70,.28,.20), vec3(.97,.58,.32), s) * (.88 + .12*step(0., sin(wp.x*.5236)*sin(wp.z*.5236)));
      } else if (m < 4.5) {                                             // CANDYLAND: frosting bands and sprinkles
        float rip = .5 + .5*sin(wp.x*.13 + sin(wp.z*.035)*3. + sin(wp.x*.04)*2.);
        float band = floor(rip*3.);
        col = band < 1. ? vec3(1.,.62,.80) : (band < 2. ? vec3(.98,.88,.84) : vec3(.66,.92,.84));
        vec2 cell = floor(wp.xz*.8); float hh = h21(cell); vec2 l = fract(wp.xz*.8) - .5;
        float ang = hh*6.2831; l = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * l;
        float spr = step(.80, hh) * step(abs(l.x), .34) * step(abs(l.y), .10);
        col = mix(col, hsv(hh*7.3)*.9+.1, spr);
      } else if (m < 5.5) {                                             // EGYPT: gold sand ripples, teal lines every 12 m
        float s = .5 + .5*sin(wp.x*.21 + sin(wp.z*.05)*2.4);
        col = mix(vec3(.80,.60,.28), vec3(.98,.82,.50), s);
        col = mix(col, uC2, .55*gline(wp.xz/12., 1.4));
      } else if (m < 6.5) {                                             // DIGITAL: a column of falling code per cell
        vec2 g = wp.xz/3.2; vec2 id = floor(g); vec2 f = fract(g);
        float sp = .35 + h21(vec2(id.x,3.))*.8;
        float tt = fract(h21(vec2(id.x,9.)) + id.y*.071 + uT*sp*.35);
        float trail = pow(1.-tt, 3.), head = smoothstep(.06, 0., tt);
        vec2 px = floor(f*vec2(3.,5.));
        float glyph = step(.45, h21(px + id*3.1 + floor(uT*1.5 + h21(id)*7.)));
        float inside = step(.12,f.x)*step(f.x,.88)*step(.1,f.y)*step(f.y,.9);
        col = vec3(0.,.02,.01) + vec3(0.,.07,.03)*max(smoothstep(.03,0.,f.x), smoothstep(.03,0.,f.y)) + uC1*glyph*inside*trail*.6 + uC2*glyph*inside*head*.9;
      } else {                                                          // SYNTHWAVE: a neon lattice, the same width at every distance
        vec2 g = wp.xz/3.; vec2 f = abs(fract(g)-.5);
        float w = .05 + .0016*length(wp.xz-uCam.xz);
        float line = max(smoothstep(.5-w,.5,f.x), smoothstep(.5-w,.5,f.y));
        float chk = step(0., sin(g.x*3.14159)*sin(g.y*3.14159));
        float pulse = .75 + .25*sin(wp.z*.05 - uT*2.);
        col = vec3(.03,0.,.07) + vec3(.07,.02,.14)*chk + mix(uC1, uC2, .5+.5*sin(wp.x*.02+uT*.3)) * line * pulse * .9;
      }
      col += uC2 * (1.0 - smoothstep(.0, .25, abs(abs(wp.x) - 38.))) * .9;          // the edge of the slope
      float fade = smoothstep(110., 400., dist);
      gl_FragColor = vec4(mix(col, uHor, fade), 1.0);
    }`,
});
const ground = new THREE.Mesh(new THREE.PlaneGeometry(1000, 1000, 1, 1), groundMat);
ground.rotation.x = -Math.PI / 2;
ground.frustumCulled = false;
scene.add(ground);

// THE SKY: a gradient dome that follows the camera (and a sun disc in the worlds that have one: stripes cut into it in SYNTHWAVE).
const skyMat = new THREE.ShaderMaterial({
  uniforms: { uTop: { value: TH.top }, uHor: { value: TH.hor }, uC1: { value: TH.c1 }, uSun: { value: 0 }, uStripe: { value: 0 }, uT: { value: 0 } },
  vertexShader: 'varying vec3 dir; void main(){ dir = normalize(position); gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position,1.0); }',
  fragmentShader: `precision mediump float; varying vec3 dir; uniform vec3 uTop, uHor, uC1; uniform float uSun, uStripe, uT;
    void main(){
      float y = dir.y;
      vec3 col = mix(uHor, uTop, smoothstep(.0, .55, y));
      col = mix(col, uHor*.6, smoothstep(.0, -.4, y));
      vec3 sd = normalize(vec3(0., .16, -1.));
      float d = distance(dir, sd);
      float disc = smoothstep(.20, .185, d) * uSun;
      float cut = mix(1., step(.5, fract(y*40. + uT*.1)) , uStripe * step(dir.y, .16));
      col = mix(col, uC1 + .35, disc * cut);
      col += uC1 * .25 * uSun * smoothstep(.5, .0, d);
      gl_FragColor = vec4(col, 1.);
    }`,
  side: THREE.BackSide, depthWrite: false, depthTest: false,
});
const sky = new THREE.Mesh(new THREE.SphereGeometry(600, 24, 12), skyMat);
sky.frustumCulled = false; sky.renderOrder = -10;
scene.add(sky);

// OBJECTS (all instanced, one draw each): pylons down both sides (trees / crystals), and ten rows ahead, one every 52 m. A row is one of: ORBS (a string of points in one lane), a GATE (a ring marks the open lane,
// barriers fill the other two), a PICKUP (boost / shield / x2 / points), a RAMP (a jump), or ROCKS (two lanes blocked: crash).
const N_PYL = 160, N_RING = 10, SPAN = 520, LANE_W = 22, ROW_GAP = SPAN / N_RING;          // wide lanes: the choices must be far apart ON THE SCREEN (at 70 m ahead, lanes 8 m apart sit within about 4 degrees of each other, too close for the eyes to tell apart)
const pylMat = new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff });
const pylMesh = new THREE.InstancedMesh(new THREE.ConeGeometry(1.6, 7, 5, 1, false), pylMat, N_PYL);
const ringMesh = new THREE.InstancedMesh(new THREE.TorusGeometry(9, 0.18, 3, 28), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 3);
const orbMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(1.5, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 18);
const wallMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 2, 7, 2), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_RING * 2);
const beamMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1.6, 90, 1.6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 3);          // a tall beam over each row's lane: visible from far away, so the choice can be seen (and looked at) long before the ring itself
const padMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 4, 0.5, 18), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 3);          // a glowing pad on the ground at the open lane: the base of the gate, low on the screen, where the eyes rest
const pickMesh = new THREE.InstancedMesh(new THREE.OctahedronGeometry(2.6, 0), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 3);
const pickWire = new THREE.InstancedMesh(new THREE.OctahedronGeometry(3.6, 0), new THREE.MeshBasicMaterial({ color: 0xffffff, wireframe: true }), N_RING * 3);
const rampMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 6, 0.7, 18), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 3);
const rockMesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(3.4, 0), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 6);
const allMeshes = [pylMesh, ringMesh, orbMesh, wallMesh, beamMesh, padMesh, pickMesh, pickWire, rampMesh, rockMesh];
wallMesh.count = 0;          // (walls are gone: there is nothing to be walled off from, the middle is open)
for (const mm of allMeshes) { mm.frustumCulled = false; scene.add(mm); }
const PICKS = [          // kind: what it does (Godot: CRYSTAL a longer boost, CAGE a shield, RINGS double points, CLUSTER a lump of points)
  { name: 'BOOST', col: [1.0, 0.55, 0.1] }, { name: 'SHIELD', col: [0.3, 0.85, 1.0] }, { name: 'x2', col: [0.95, 0.4, 1.0] }, { name: 'POINTS', col: [1.0, 0.85, 0.35] },
];
const rows = [];
// EVERY ROW IS A CHOICE (RunRig._gen_feats), laid out four ways over three lanes: PAIR (a thing each side, the middle open or with a rock slalom), CENTRE (one good thing in the middle, rocks on both
// sides: stay on it or run the rocks), TRIPLE (three different things, left, middle and right), FLANK (a pair with rocks between). The middle is a real choice in about 58% of rows.
// kinds: 0 orbs (points), 1 ring (a bonus ring), 2 pickup (boost / shield / x2 / points), 3 ramp (a jump), 4 rocks (a crash)
function mkThing(avoid, noRamp) {
  for (let tries = 0; tries < 30; tries++) {
    const k = Math.random();
    const type = k < 0.30 ? 0 : k < 0.52 ? 1 : k < 0.84 || noRamp ? 2 : 3;
    const pick = Math.floor(Math.random() * 4);
    if (avoid.some((a) => a && a.type === type && (type !== 2 || a.pick === pick))) continue;
    return { type, pick, orbs: [0, 1, 2, 3, 4, 5].map(() => true), done: false };
  }
  return { type: 0, pick: 0, orbs: [true, true, true, true, true, true], done: false };
}
const mkRocks = () => ({ type: 4, pick: 0, orbs: [], done: false });
// GUIDED ROWS (the calibration that is part of the game): for the first 3 rows exactly ONE lane holds a prize and the matching card says LOOK HERE, in a shuffled left / middle / right order. The true lane
// of the look is then known, so the model learns from it directly (EyeModel.supervise) and the log holds true-target / model-guess pairs. ?noguide skips it.
const GUIDE = { on: !Q.has('noguide') && !Q.has('mouse') && !Q.has('head'), visible: Q.has('guide') || !CAL_DONE, max: Math.max(3, parseInt(Q.get('guide') || '3', 10) || 3), n: 0, seq: [], bSize: 0, bTried: 0, bHits: 0, pending: 0, warm: 0, rn: 0, every: Q.has('targets') ? parseInt(Q.get('targets'), 10) || 0 : 3, tuneups: 0, lastTune: -999, first: false };
GUIDE.first = GUIDE.on && GUIDE.visible; GUIDE.bSize = GUIDE.first ? GUIDE.max : 0;          // 3 rows by default (one look at each lane, shuffled): the rings are SHOWN only on the first run on a device (or ?guide), and for a tune-up; every other session starts with 3 normal-looking rows, each with one obviously better prize (hidden warm-up)
for (let k = 0; k < Math.ceil(GUIDE.max / 3); k++) GUIDE.seq.push(...[-1, 0, 1].sort(() => Math.random() - 0.5));
const VAL = { 0: 1, 1: 2, 2: 3, 3: 2.5, 4: -5 };          // what a thing is worth to someone choosing: used to see which lane of a row is clearly the best one (an inferred label for the eyes)
function setRow(r, z) {
  r.z = z; r.passed = false; r.guide = 9; r.lab = 9; r.lw = 0; r.votes = [0, 0, 0];
  const orbs = () => ({ type: 0, pick: 0, orbs: [true, true, true, true, true, true], done: false });
  if (GUIDE.on && GUIDE.every && GUIDE.n >= GUIDE.max && GUIDE.pending === 0 && tPlay > 6 && ++GUIDE.rn % GUIDE.every === 0) GUIDE.pending = 1;          // ?targets=N (default 3 while testing, 0 = off): after the first rows, every Nth row is a visible LOOK HERE ring, all run long
  if (GUIDE.pending > 0 || GUIDE.warm > 0 || (GUIDE.on && GUIDE.n < GUIDE.max)) {          // a guided row: ONE lane holds the prize
    const g = (GUIDE.pending > 0 || GUIDE.warm > 0) ? [-1, 0, 1][Math.floor(Math.random() * 3)] : GUIDE.seq[GUIDE.n++];
    const vis = GUIDE.pending > 0 || (GUIDE.warm <= 0 && GUIDE.visible); if (GUIDE.pending > 0) GUIDE.pending--; else if (GUIDE.warm > 0) GUIDE.warm--;
    r.lab = g; r.s = [null, null, null];
    if (vis) { r.guide = g; r.lw = 1; r.s[g + 1] = orbs(); }          // shown: the ring says LOOK HERE
    else { r.lw = 0.6; r.s = [orbs(), orbs(), orbs()]; r.s[g + 1] = { type: 2, pick: Math.floor(Math.random() * 4), orbs: [], done: false }; }          // hidden: three normal lanes, one clearly better (a pickup against orbs)
    return;
  }
  const calm = tPlay < 20;          // the first 20 seconds: no hazards
  const hzK = calm ? 0 : Math.min(0.7, 0.25 + tPlay * 0.002);          // how often something nasty is put in
  const roll = Math.random(), flip = Math.random() < 0.5 ? 1 : -1;
  let L = null, M = null, R = null;
  if (roll < 0.22 && !calm) {          // centre: one good thing straight ahead, rocks either side
    M = mkThing([], true); L = mkRocks(); R = mkRocks();
  } else if (roll < 0.58) {          // triple: three different things
    const a = mkThing([], false), b = mkThing([a], false), c = mkThing([a, b], false);
    [L, M, R] = Math.random() < 0.5 ? [a, b, c] : [c, b, a];
    if (M.type === 3 && Math.random() < 0.9) { const t = L; L = M; M = t; }          // a ramp is rarely in the middle
  } else {          // pair (and flank: no separate rocks between here, the middle gets a rock slalom instead)
    const a = mkThing([], false), b = mkThing([a], false);
    if (flip > 0) { L = a; R = b; } else { L = b; R = a; }
    if (L.type !== 3 && R.type !== 3 && Math.random() < hzK * 0.5) M = mkRocks();
    else if (Math.random() < 0.3) M = mkThing([L, R], true);          // the middle lane is rarely empty
  }
  r.s = [L, M, R];
  const vals = r.s.map((o) => (o ? VAL[o.type] : 0)), top = Math.max(...vals), bi = vals.indexOf(top), second = Math.max(...vals.filter((v, i) => i !== bi));
  if (top >= 2.5 && top - second >= 1.5) { r.lab = bi - 1; r.lw = (bi === 1 && L && L.type === 4 && R && R.type === 4) ? 0.8 : 0.4; }          // one lane clearly worth taking: the eyes are probably there (weak label; the centre layout, rocks on both sides, is the strongest)
}
let tPlay = 0;
for (let i = 0; i < N_RING; i++) { const r = { i }; setRow(r, -(GUIDE.on ? 110 : 50) - i * ROW_GAP); rows.push(r); }
const pyl = [];
for (let i = 0; i < N_PYL; i++) pyl.push({ z: -Math.random() * SPAN, x: (Math.random() < 0.5 ? -1 : 1) * (LANE_W * 1.5 + 8 + Math.random() * 34), s: 1.2 + Math.random() * 2 });
const m4 = new THREE.Matrix4(), q4 = new THREE.Quaternion(), v3 = new THREE.Vector3(), s3 = new THREE.Vector3(), colr = new THREE.Color(), qRamp = new THREE.Quaternion().setFromEuler(new THREE.Euler(0.22, 0, 0));
const HIDE = new THREE.Matrix4().compose(new THREE.Vector3(0, -50, 0), new THREE.Quaternion(), new THREE.Vector3(0.0001, 0.0001, 0.0001));

// WORLD CHANGES: the colours blend over two seconds; the ground pattern and the object style switch at once, hidden under a flash of the new world's colour.
let worldIdx = -1, worldT = 0;
const WORLD_SECS = Q.has('fast') ? 12 : 50;
const worldQ = Q.get('world');
function setWorld(i, instant) {
  const th = THEMES[i % THEMES.length];
  worldIdx = i % THEMES.length;
  TH.idx = worldIdx; TH.mode = th.mode; TH.wire = th.wire; TH.rainbow = th.rainbow; TH.sun = th.sun;
  groundMat.uniforms.uMode.value = th.mode;
  pylMat.wireframe = th.wire; wallMesh.material.wireframe = th.wire;
  TH.tgt = th;
  if (instant) { TH.top.setRGB(...th.top); TH.hor.setRGB(...th.hor); TH.c1.setRGB(...th.c1); TH.c2.setRGB(...th.c2); TH.trace = th.trace; TH.split = th.split; }
  else { G.flash = 1.0; G.fr = th.c1[0]; G.fg = th.c1[1]; G.fb = th.c1[2]; bannerShow(th.name); }
  skyMat.uniforms.uSun.value = th.sun; skyMat.uniforms.uStripe.value = th.id === 'synthwave' ? 1 : 0;
}
const tmpC = new THREE.Color();
function worldBlend(dt) {
  const th = TH.tgt; if (!th) return;
  const k = 1 - Math.exp(-2.2 * dt);
  TH.top.lerp(tmpC.setRGB(...th.top), k); TH.hor.lerp(tmpC.setRGB(...th.hor), k); TH.c1.lerp(tmpC.setRGB(...th.c1), k); TH.c2.lerp(tmpC.setRGB(...th.c2), k);
  TH.trace += (th.trace - TH.trace) * k; TH.split += (th.split - TH.split) * k;
}

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
    col += texture2D(uTrail, vUv).rgb * .8 * uTrace * (1. - clamp(dot(col, vec3(.35,.5,.15)) * 1.2, 0., .9));
    col += uFlash.rgb * uFlash.a * (0.08 + r * 0.45);
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
    // THE FLOATING CENTRE (a gyroscope for the eyes): the middle is held at the midpoint of the envelope of your last ~20 s of readings, (10th percentile + 90th percentile) / 2. Unlike a median it does not care
    // how long you dwell in each lane, only that you have visited both ends, so a head that turns or leans as you play, or glare on the glasses, slides the middle along with the whole signal and the three
    // places stay balanced around you. With no real movement in the window (less than 0.012 between the two percentiles) it uses the median instead. It moves about a third of the way every 1.5 s, and not at
    // all while within 0.002 of where it is.
    this.zft = (this.zft || 0) + dt;
    if (this.zft >= 0.5 && this.zall.length >= 120 && z.auto) {
      this.zft = 0;
      const w = this.zall.slice(-300).sort((a, b) => a - b), q = (p) => w[Math.min(w.length - 1, Math.floor(p * w.length))];
      const env = (q(0.9) - q(0.1) >= 0.012) ? (q(0.1) + q(0.9)) * 0.5 : median(w), gap = env - (z.m + this.zdrift);
      if (Math.abs(gap) > 0.002) z.m += gap * 0.15;
    }
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
function beginPlay() { say('', ''); playing = true; started = true; startMusic(); if (eyeMode) { $('zones').style.display = 'block'; $('gdot').style.display = 'block'; } }
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
      tracker.onSteady = (hx, t, ha, hb) => {          // hx = both eyes averaged; ha / hb = each eye alone (a lens can distort one of them). ?eye=a or ?eye=b drives the game from one eye; ?eye=best picks the cleaner one as it goes
        pkCount++; headFeed(); KIT.ha = ha; KIT.hb = hb; KIT.roll = tracker.head ? tracker.head.roll * 57.2958 : 0; KIT.fx = tracker.feat ? tracker.feat[5] : 0; KIT.fy = tracker.feat ? tracker.feat[6] : 0; KIT.fsz = tracker.fsz || 0; KIT.lids = tracker.lids || [0, 0]; KIT.yaw = tracker.head ? tracker.head.yaw * 57.2958 : 0; KIT.pitch = tracker.head ? tracker.head.pitch * 57.2958 : 0;
        if (Number.isFinite(ha) && Number.isFinite(hb)) { EYE.bufA.push(ha); EYE.bufB.push(hb); if (EYE.bufA.length > 400) { EYE.bufA.shift(); EYE.bufB.shift(); } eyeAuto(t); }
        const pick = EYE.sel === 'A' && Number.isFinite(ha) ? ha : EYE.sel === 'B' && Number.isFinite(hb) ? hb : hx;
        KIT.add(pick, 0, 0, t);
        if (EM && Number.isFinite(ha) && Number.isFinite(hb)) {          // the model decides the zone once the middle is learned (KIT still runs, for the setup bar, blinks and the logs)
          EM.step([ha, hb], [KIT.roll || 0, KIT.pitch || 0, KIT.yaw || 0]);          // the head's roll, pitch and yaw (degrees) are used to correct the reading for a tilted or leaning head
          KIT.gl = 9; KIT.gp = 9; KIT.gw = 0;
          const gr = EM.ready && wasReady ? labRow() : null;
          if (gr) {
            const tt = (zPos - gr.z) / Math.max(speed, 14);
            if (tt < 1.0 && tt > 0.2) {          // (the eyes need about half a second to find a ring: only the last second counts)
              KIT.gl = gr.lab; KIT.gp = EM.zone; KIT.gw = gr.lw; if (gr.guide !== 9) gr.votes[EM.zone + 1]++;
              if (EM.hold && EM.labeled.length >= 25) profChoose();
              if (gr.lw >= 0.99 || EM.post[gr.lab + 1] >= 0.12 || EM.labeled.length < 30) EM.supervise(EM.xc || [ha, hb], gr.lab, gr.lw);          // an inferred label only counts when the model does not flatly disagree with it (a player who ignored the prize must not retrain it)
            }
          }
          if (EM.ready && wasReady) { CONF.push(Math.max(EM.post[0], EM.post[1], EM.post[2])); if (CONF.length > 300) CONF.shift(); tuneCheck(); }
          if (EM.ready && KIT.zones) { if (KIT.zone !== EM.zone) KIT.zone_t = t; KIT.zone = EM.zone; KIT.zn = EM.zn; }
          if (EM.n % 150 === 0 && EM.ready && !EM.hold && EM.labeled.length >= 15) profStore();
        }
      };          // (the tracker already holds readings through blinks, so the blink inputs are zero here)
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
  if (song && musicOn) { if (on) song.pause(); else song.play().catch(() => {}); }
  if (on) say('PAUSED', '', 'RESUME', () => setPause(false)); else say('', '');
}
addEventListener('pointerdown', () => { if (paused) setPause(false); });
addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !e.repeat) setPause(!paused);
  if (e.key === '1') flags.tracers = !flags.tracers;
  if (e.key === '2') flags.split = !flags.split;
  if (e.key === '3' || e.key === 'n' || e.key === 'N') { worldT = 0; setWorld(worldIdx + 1); }          // next world
  if (e.key === 'm' || e.key === 'M') toggleMusic();
  if (e.key === '4') flags.objects = !flags.objects;
});

// the tracker publishes a packet on window.__gaze and counts them in window.__gazeSeq: each new packet with an iris reading goes to the zone detector, as GazeProvider.gd did
let lastSeq = 0;
let lostSince = 0, wasAway = false;
function handover() {          // the face was gone for more than 1.5 s and came back: possibly another player. Forget the labelled looks, choose a profile again from the next few looks, and warm up with hidden rows.
  if (!EM || !EM.ready) return;
  EM.labeled = []; EM.hold = true; PROF.chosen = false; CONF.length = 0; GUIDE.warm = 3;
}
function readTracker(now) {
  window.__gazeStats = { pk: pkCount, inf: tracker ? tracker.modelMs : 0, lat: 0, dlg: tracker ? (tracker.delegate || '') : '', vw: video.videoWidth, vh: video.videoHeight };
  KIT.idle(now / 1000, 1 / 60);
  if (KIT.lost) { if (!lostSince) lostSince = now; if (now - lostSince > 1500) wasAway = true; } else { lostSince = 0; if (wasAway) { wasAway = false; handover(); } }          // real time, whatever the frame rate
  KIT.zh_n = 3;          // (Godot used 2 at speed. With the lowered thresholds 2 readings flipped the lane 15 to 19 times in 10 s, so it is 3 here)
}
// LOCK-ON, the way RunRig.gd chose things (this is what made Godot forgiving, and why it needed no calibration): the zone is NOT the lane. Each lane keeps a leaky "want": it fills while
// the eyes are in that lane's zone (the middle only at 0.35 of the pace, because resting eyes go there), and drains when they are elsewhere (3x as fast when the eyes are on a side).
// A lane takes the lock after a ninth of a second at first; once locked it holds however the eyes wander, committed for half a second, and a change of mind then needs a steadier look
// (0.35 s), then 0.14 s once the commitment is over. The board slides to the locked lane, so one glance starts a move that finishes by itself.
const LOCK = { want: { '-1': 0, '0': 0, '1': 0 }, lane: 0, age: 9, block: 0, free: true };
function lockStep(zone, dt) {
  // The lane FOLLOWS THE EYES (left / middle / right), with Godot's lock-on only as a hold: a lane chosen is kept while the thing is still ahead, so a flicker (or a glance at the middle while you follow a
  // target in) can not snap it back, and it is FREE again the moment the board passes the thing (RunRig clears its lock there), when any lane the eyes are asking for takes over at once.
  // Fill / drain are Godot's (the middle fills at 0.35 of the pace: resting eyes go there). A lane is taken after a first look of 0.11 s, a change of mind needs 0.35 s, then 0.14 s once the half-second
  // commitment is over, and none in the last quarter second before the board reaches the thing; between passes the MIDDLE needs a steady look of about 0.8 s to take a side lane away.
  const qk = TUNE.qk;          // at speed everything about choosing is quicker (Godot: qk 0.6 flat out); live-tunable
  for (const l of [-1, 0, 1]) {
    if (zone === l) LOCK.want[l] = Math.min(LOCK.want[l] + dt * (l === 0 ? 0.35 / qk : 1.0), 0.5);
    else LOCK.want[l] = Math.max(LOCK.want[l] - dt * (zone !== 0 ? 3.0 : 0.6), 0);
  }
  LOCK.age += dt;
  let need = LOCK.free ? 0.11 * qk : (LOCK.age >= 0.5 * qk ? 0.14 : 0.35) * qk;
  const nd = nextRowDist();
  if (!LOCK.free && nd / Math.max(speed, 14) < 0.25) need = 9;
  for (const l of [-1, 0, 1]) {
    if (l === LOCK.lane) continue;
    const nl = !LOCK.free && l === 0 && LOCK.lane !== 0 ? Math.max(need, TUNE.midhold) : need;
    if (LOCK.want[l] > nl) { LOCK.lane = l; LOCK.age = 0; LOCK.free = false; break; }
  }
  return LOCK.lane;
}
function nextRowDist() {          // how far ahead the nearest row is (m)
  let bz = -1e9;
  for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) bz = r.z;
  return bz > -1e8 ? zPos - bz : 999;
}
// THE SETUP INDICATOR: while the first 40 readings come in (about 3 s) the player is told to stare at the centre of the screen, with a progress bar; when the middle is learned it says CONTROL ON and the board starts to obey.
const calEl = document.createElement('div');
calEl.style.cssText = 'position:fixed;left:0;right:0;top:38%;text-align:center;color:#fff;font:300 clamp(18px,4.5vw,40px) ui-monospace,Consolas,monospace;letter-spacing:.25em;text-shadow:0 0 14px #000,0 0 3px #000;z-index:6;pointer-events:none;display:none';
calEl.innerHTML = '<div id="calT"></div><div style="width:min(320px,60vw);height:8px;margin:14px auto 0;border:1px solid #fff9;border-radius:6px;overflow:hidden"><div id="calB" style="height:100%;width:0;background:#0ff"></div></div>';
document.body.appendChild(calEl);
let calState = 0, calT = 0;          // 0 waiting for the camera, 1 learning, 2 done (showing CONTROL ON), 3 hidden
function calUpdate(dt) {
  if (calState === 3) return;
  const T = document.getElementById('calT'), B = document.getElementById('calB');
  if (!KIT.zones) {
    calState = 1; calEl.style.display = 'block';
    T.textContent = KIT.lastHx === null ? 'FINDING YOUR EYES' : 'STARE AT THE CENTRE';
    B.style.width = Math.round(100 * Math.min(1, KIT.zauto.length / 40)) + '%'; B.style.background = '#0ff';
  } else if (calState <= 1) {
    calState = 2; calT = 0; T.textContent = 'CONTROL ON'; B.style.width = '100%'; B.style.background = '#6f6';
    beep(660, 0.15, 0.08); setTimeout(() => beep(990, 0.2, 0.08), 110);
  } else if (calState === 2) {
    calT += dt; if (calT > 1.6) { calState = 3; calEl.style.display = 'none'; }
  }
}
// THE GAUGE (G toggles it): a strip chart of the last 8 s of the eye reading, so what the zone detector sees can be watched. Up = a look LEFT, down = RIGHT. The reading is in units of one side's size
// (the same number that decides the zone), so the lines are the same on both sides: the middle at 0, the enter lines at +-Z_IN (a look past them counts), the leave lines at +-Z_OUT, and +-1 a full look.
// Dots are coloured by the zone read at that moment, and the right-hand column shows the LOCKED lane. The text under it: the raw reading, where the centre is, and the size of each side.
const gCan = document.createElement('canvas'); gCan.width = 360; gCan.height = 120;
gCan.style.cssText = 'position:fixed;left:auto;right:8px;top:58px;width:min(300px,46vw);height:auto;background:#000a;border:1px solid #fff4;border-radius:4px;z-index:5;pointer-events:none';
const gTxt = document.createElement('div');
gTxt.style.cssText = 'position:fixed;right:8px;top:calc(58px + min(300px,46vw) * 0.334 + 4px);width:min(300px,46vw);color:#cff;font:11px ui-monospace,Consolas,monospace;text-align:right;text-shadow:0 0 3px #000;z-index:5;pointer-events:none;white-space:pre';
let gaugeOn = !Q.has('nogauge'); const gH = [];
function gaugeUpdate() {
  gCan.style.display = gTxt.style.display = gaugeOn && eyeMode && started ? 'block' : 'none';
  if (!gaugeOn || !eyeMode || !started) return;
  if (!gCan.parentNode) { document.body.appendChild(gCan); document.body.appendChild(gTxt); }
  const now = performance.now() / 1000;
  gH.push([now, KIT.zones ? KIT.zn : 0, KIT.zone, LOCK.lane]); while (gH.length && now - gH[0][0] > 8) gH.shift();
  const c = gCan.getContext('2d'), w = gCan.width, h = gCan.height, mid = h / 2, k = (h / 2) / 1.5, plotW = w - 26;
  c.clearRect(0, 0, w, h);
  const ln = (v, col, dash) => { c.strokeStyle = col; c.setLineDash(dash || []); c.beginPath(); c.moveTo(0, mid + v * k); c.lineTo(plotW, mid + v * k); c.stroke(); };
  ln(0, '#fff5'); ln(KIT.Z_IN, '#0f98', [4, 3]); ln(-KIT.Z_IN, '#0f98', [4, 3]); ln(KIT.Z_OUT, '#ff08', [2, 3]); ln(-KIT.Z_OUT, '#ff08', [2, 3]); ln(1, '#fff3'); ln(-1, '#fff3');
  c.setLineDash([]); c.fillStyle = '#fffa'; c.font = '10px monospace'; c.fillText('LEFT', 3, 11); c.fillText('RIGHT', 3, h - 4);
  const col = { '-1': '#4af', '0': '#fff', '1': '#fa4' };
  c.lineWidth = 1.5;
  for (let i = 1; i < gH.length; i++) {
    const x0 = plotW * (1 - (now - gH[i - 1][0]) / 8), x1 = plotW * (1 - (now - gH[i][0]) / 8);
    c.strokeStyle = col[gH[i][2]]; c.beginPath(); c.moveTo(x0, mid + clampf(gH[i - 1][1], -1.5, 1.5) * k); c.lineTo(x1, mid + clampf(gH[i][1], -1.5, 1.5) * k); c.stroke();
  }
  c.lineWidth = 1;
  const ly = mid + LOCK.lane * -0.9 * k;          // the locked lane, drawn at the same height as a full look that way
  c.fillStyle = '#0f8'; c.fillRect(plotW + 6, ly - 5, 14, 10);
  const z = KIT.zones;
  gTxt.textContent = z ? 'hx ' + (KIT.lastHx || 0).toFixed(4) + '  A ' + (Number.isFinite(KIT.ha) ? KIT.ha.toFixed(4) : '-') + ' B ' + (Number.isFinite(KIT.hb) ? KIT.hb.toFixed(4) : '-') + '  yaw ' + (KIT.yaw || 0).toFixed(0) + '°  EYE ' + EYE.sel + ' (' + EYE.sA.toFixed(1) + ' / ' + EYE.sB.toFixed(1) + ' spread ' + EYE.spread.toFixed(2) + ')' + '  centre ' + (z.m + KIT.zdrift).toFixed(4) + '  zn ' + KIT.zn.toFixed(2) + '\n' + (EM ? 'MODEL  L ' + EM.post[0].toFixed(2) + '  M ' + EM.post[1].toFixed(2) + '  R ' + EM.post[2].toFixed(2) + '   ' : '') + 'sides L ' + Math.abs(z.dl).toFixed(3) + ' R ' + Math.abs(z.dr).toFixed(3) + '  lock ' + ['LEFT', 'MID', 'RIGHT'][LOCK.lane + 1] : 'learning the middle...';
}
addEventListener('keydown', (e) => { if (e.key === 'g' || e.key === 'G') gaugeOn = !gaugeOn; });
// LOOK TARGETS (RunRig._draw_cards, which Godot showed out at the sides because things far away sit close to the middle of the screen, where looking at them barely moves the eyes). Three big round
// cards: the thing LEFT of the lane the board is going for, the thing RIGHT of it, and (small, top middle) the thing it is going for. Each is coloured as the thing in the nearest row and its ring fills while the
// eyes ask for it. Looking at the left card is a look left, so it steps the board one lane left; the lane in the middle of the row is the card in the middle.
const CARD_KIND = (o) => !o ? { n: 'EMPTY', c: '#667' } : o.type === 0 ? { n: 'POINTS', c: '#3f8' } : o.type === 1 ? { n: 'RING', c: '#fd3' } : o.type === 2 ? { n: PICKS[o.pick].name, c: 'rgb(' + PICKS[o.pick].col.map((v) => Math.round(v * 255)).join(',') + ')' } : o.type === 3 ? { n: 'RAMP', c: '#f5f' } : { n: 'ROCKS', c: '#f44' };
const cards = [-1, 0, 1].map((p) => {
  const e = document.createElement('div'), big = p !== 0, sz = big ? 'clamp(60px,11vmin,96px)' : 'clamp(44px,8vmin,66px)';
  e.style.cssText = 'position:fixed;z-index:4;pointer-events:none;border-radius:50%;display:none;text-align:center;font:700 clamp(9px,1.6vmin,13px) ui-monospace,Consolas,monospace;letter-spacing:.08em;color:#fff;text-shadow:0 0 4px #000;width:' + sz + ';height:' + sz + ';line-height:' + sz + ';top:' + (big ? '46%' : '24%') + ';left:' + (p < 0 ? '4%' : p > 0 ? 'auto' : 'calc(50% - 33px)') + ';right:' + (p > 0 ? '4%' : 'auto');
  document.body.appendChild(e); return e;
});
// THE GUIDE MARKER: a big pulsing ring with LOOK HERE at the exact place to look (left 12% / middle 50% / right 88% of the screen width, 46% down): the true position of the look, which is also logged.
const GX = { '-1': 0.12, '0': 0.5, '1': 0.88 };
const guideEl = document.createElement('div');
guideEl.style.cssText = 'position:fixed;z-index:6;pointer-events:none;display:none;border-radius:50%;width:clamp(120px,19vmin,200px);height:clamp(120px,19vmin,200px);margin:calc(clamp(120px,19vmin,200px) / -2) 0 0 calc(clamp(120px,19vmin,200px) / -2);top:46%;border:6px solid #fff;background:radial-gradient(circle,#fff3,#fff0 70%);color:#fff;font:700 clamp(15px,2.6vmin,26px) ui-monospace,Consolas,monospace;letter-spacing:.12em;text-align:center;display:none;text-shadow:0 0 8px #000;align-items:center;justify-content:center';
guideEl.textContent = 'LOOK HERE';
document.body.appendChild(guideEl);
function cardsUpdate() {
  let row = null, bz = -1e9;
  for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) { bz = r.z; row = r; }
  const grow = row && row.guide !== 9 && wasReady ? row : null;
  if (grow) { const k = 1 + 0.08 * Math.sin(performance.now() / 140); guideEl.style.display = 'flex'; guideEl.style.left = (GX[grow.guide] * 100) + '%'; guideEl.style.transform = 'scale(' + k.toFixed(3) + ')'; guideEl.style.boxShadow = '0 0 ' + (30 + 20 * Math.sin(performance.now() / 140)) + 'px #fff'; } else guideEl.style.display = 'none';
  for (let i = 0; i < 3; i++) {
    const e = cards[i], p = i - 1, lane = p;
    if (!row || lane < -1 || lane > 1 || !KIT.zones) { e.style.display = 'none'; continue; }
    const k = CARD_KIND(row.s[lane + 1]), fill = lane === LOCK.lane ? 1 : Math.min(1, LOCK.want[lane] / 0.5), on = lane === LOCK.lane;
    e.style.display = 'block';
    e.style.background = 'radial-gradient(circle,#000b 58%,transparent 60%), conic-gradient(' + (on ? '#6f6' : k.c) + ' ' + Math.round(fill * 360) + 'deg, #fff3 0)';
    e.style.boxShadow = '0 0 ' + (on ? 14 : 8) + 'px ' + k.c; e.textContent = k.n;
    if (row.guide !== 9) {          // a guided row: the card to look at pulses and says so, the others fade
      const g = lane === row.guide; e.style.opacity = g ? '0.5' : '0.15'; e.style.outline = 'none';
    } else { e.style.opacity = '1'; e.style.outline = 'none'; }
  }
}
let waitT = 0, wasReady = false;
function ctrlReady() {          // the world holds still until the middle is learned (or 15 s have passed without a camera: then it plays on)
  const ok = !eyeMode || (HEAD.on ? HEAD.phase === 'run' || (!HEAD.cal && HEAD.fb.length >= 12) : (KIT.zones && (!EM || EM.ready))) || waitT > (HEAD.on ? 40 : 15);
  if (ok && !wasReady) { wasReady = true; if (GUIDE.on && GUIDE.visible) { bannerShow('LOOK AT THE RING', false); setTimeout(() => bannerShow('LOOK AT THE RING', true), 1700); } }
  return ok;
}
const CONF = [];
function tuneCheck() {          // a visible TUNE-UP (three rings, a bonus round) only when the model has been unsure for 20 s; at most twice a session, a minute apart
  if (!GUIDE.on || GUIDE.pending > 0 || GUIDE.tuneups >= 2 || tPlay < 25 || tPlay - GUIDE.lastTune < 60 || CONF.length < 300) return;
  const med = CONF.slice().sort((a, b) => a - b)[150];
  if (med < 0.7) { GUIDE.pending = 3; GUIDE.tuneups++; GUIDE.lastTune = tPlay; GUIDE.bSize = 3; GUIDE.bTried = 0; GUIDE.bHits = 0; CONF.length = 0; bannerShow('TUNE-UP: LOOK AT THE RINGS', true); }
}
function labRow() { let row = null, bz = -1e9; for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) { bz = r.z; row = r; } return row && row.lab !== 9 ? row : null; }
function guideRow() { let row = null, bz = -1e9; for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) { bz = r.z; row = r; } return row && row.guide !== 9 ? row : null; }
// HEAD STEERING TEST (?head): no eyes, no zones, no lanes chosen for you. The board goes where the HEAD points: a short two-step set-up (turn the head left, then right, 3 s each) learns which of yaw, roll and
// the face's sideways position moves most, and by how much, for THIS person on THIS device; the board then follows a smooth number between -1 (head fully left) and +1 (fully right), exactly as far as the head has turned.
// Live tuning (tune.json "HEAD": gain, dead, flip, tau, rc to re-centre on the current pose, redo to repeat the set-up).
const HEAD = { on: Q.has('head'), phase: 'wait', t0: 0, buf: [], L: null, R: null, mid: null, w: null, s: 0, gain: 1.1, dead: 0.05, flip: 1, tau: 0.06, rc: 0, redo: 0, cur: null, msg: '', cal: Q.has('cal'), fb: [], ax: [0.577, -0.577, 0.577], ax0: [0.577, -0.577, 0.577], neu: 0, k: 0.9, lastFit: 0, vs: 0, sOut: 0, vel: 0, lead: 0.05, fc: 1.2, beta: 0.7 };
if (HEAD.on) { TUNE.steerK = 40; TUNE.camK = 22; }          // the board follows the head almost at once (the eye game slides slowly on purpose)
const headF = () => [KIT.yaw || 0, KIT.roll || 0, (KIT.fx || 0) * 100];
const HN = [5, 2.5, 1.5];          // typical head movement in play: yaw degrees, roll degrees, face sideways position
function headFeed() {
  if (!HEAD.on) return;
  if (HEAD.phase === 'left' || HEAD.phase === 'right') HEAD.buf.push({ t: performance.now(), f: headF() });
  if (!HEAD.cal && !KIT.lost) { const f = headF(); HEAD.fb.push([f[0] / HN[0], f[1] / HN[1], f[2] / HN[2]]); if (HEAD.fb.length > 600) HEAD.fb.shift(); }
}
// SELF-CALIBRATION the player never sees: the head's three signals (yaw, roll, sideways position) move together when you turn to steer. The dominant direction of everything the head has done in the last
// ~40 s is the steering axis (signed by a prior: left = more yaw, less roll, more x), the median along it is straight ahead, and the 90th percentile of how far it strays is a 0.9 turn. Re-fitted twice a second, so a
// phone that is held differently, a lean on the bus or a new player re-tunes itself within seconds, and nothing is ever asked of the player. A one-euro filter keeps it still when the head is still and quick when it moves.
function headFit() {
  const fb = HEAD.fb, n = fb.length; if (n < 20) return;
  const mean = [0, 0, 0]; for (const v of fb) for (let i = 0; i < 3; i++) mean[i] += v[i] / n;
  let ax = HEAD.ax0.slice();
  if (n >= 150) {
    const C = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]; for (const v of fb) for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) C[i][j] += (v[i] - mean[i]) * (v[j] - mean[j]) / n;
    let a = [1, 1, 1]; for (let it = 0; it < 14; it++) { const b = [0, 1, 2].map((i) => C[i][0] * a[0] + C[i][1] * a[1] + C[i][2] * a[2]); const m = Math.hypot(b[0], b[1], b[2]) || 1; a = b.map((x) => x / m); }
    let d = a[0] * HEAD.ax0[0] + a[1] * HEAD.ax0[1] + a[2] * HEAD.ax0[2]; if (d < 0) { a = a.map((x) => -x); d = -d; }
    if (d > 0.5) ax = a;
  }
  HEAD.ax = HEAD.ax.map((x, i) => x * 0.7 + ax[i] * 0.3); const m = Math.hypot(...HEAD.ax); HEAD.ax = HEAD.ax.map((x) => x / m);
  const pr = fb.map((v) => v[0] * HEAD.ax[0] + v[1] * HEAD.ax[1] + v[2] * HEAD.ax[2]).sort((x, y) => x - y);
  const med = pr[Math.floor(pr.length / 2)], dev = pr.map((x) => Math.abs(x - med)).sort((x, y) => x - y), q90 = dev[Math.floor(dev.length * 0.9)];
  HEAD.neu = n < 40 ? med : HEAD.neu + (med - HEAD.neu) * 0.25;
  HEAD.k = HEAD.k + (0.9 / Math.max(0.25, Math.min(2.5, q90)) - HEAD.k) * (n < 40 ? 1 : 0.25);
}
function headAuto(dt, now, f) {
  if (!HEAD.cur) return; if (HEAD.fb.length < 12) { HEAD.phase = 'wait'; return; } HEAD.phase = 'run';
  if (now - HEAD.lastFit > 500) { HEAD.lastFit = now; headFit(); }
  const nv = [HEAD.cur[0] / HN[0], HEAD.cur[1] / HN[1], HEAD.cur[2] / HN[2]], pcur = nv[0] * HEAD.ax[0] + nv[1] * HEAD.ax[1] + nv[2] * HEAD.ax[2];
  let sv = KIT.lost ? 0 : -HEAD.flip * (pcur - HEAD.neu) * HEAD.k;
  sv = Math.max(-1.3, Math.min(1.3, sv)); if (Math.abs(sv) < HEAD.dead) sv = 0;
  const dv = (sv - HEAD.vs) / Math.max(dt, 0.001); HEAD.vel += (dv - HEAD.vel) * 0.3; HEAD.vs = sv;          // one-euro: the faster the head moves the less it is smoothed
  const fc = HEAD.fc + HEAD.beta * Math.abs(HEAD.vel), a = 1 / (1 + 1 / (2 * Math.PI * fc * Math.max(dt, 0.001)));
  HEAD.s += (sv - HEAD.s) * a;
  steerTarget = Math.max(-1, Math.min(1, (HEAD.s + HEAD.vel * HEAD.lead) * HEAD.gain)); lane = Math.round(steerTarget);
  KIT.zn = steerTarget; KIT.zone = lane; LOCK.lane = lane;
  const gd = $('gdot'); gd.style.left = ((steerTarget * 0.45 + 0.5) * innerWidth) + 'px'; gd.style.top = (innerHeight * 0.5) + 'px';
}
function headStats(t0) { const a = HEAD.buf.filter((b) => b.t > t0 + 1200); const n = Math.max(a.length, 1), m = [0, 0, 0], v = [0, 0, 0]; for (const b of a) for (let i = 0; i < 3; i++) m[i] += b.f[i] / n; for (const b of a) for (let i = 0; i < 3; i++) v[i] += (b.f[i] - m[i]) ** 2 / n; return { m, v, n: a.length }; }
function headUpdate(dt, now) {
  const f = headF(); HEAD.cur = HEAD.cur ? HEAD.cur.map((c, i) => c + (f[i] - c) * 0.35) : f;
  if (!HEAD.cal) { if (HEAD.rc && HEAD.rc !== HEAD.rcDone) { HEAD.rcDone = HEAD.rc; HEAD.fb = HEAD.fb.slice(-30); HEAD.lastFit = 0; } headAuto(dt, now, f); return; }
  if (HEAD.phase === 'wait') { if (pkCount > 15 && !KIT.lost) { HEAD.phase = 'left'; HEAD.t0 = now; HEAD.buf = []; bannerShow('TURN YOUR HEAD LEFT AND HOLD', false); } return; }
  if ((HEAD.phase === 'left' || HEAD.phase === 'right') && now - (HEAD.shown || 0) > 1500) { HEAD.shown = now; bannerShow(HEAD.phase === 'left' ? 'TURN YOUR HEAD LEFT AND HOLD' : 'NOW TURN YOUR HEAD RIGHT AND HOLD', false); }
  if (HEAD.phase === 'left' && now - HEAD.t0 > 3000) { HEAD.L = headStats(HEAD.t0); HEAD.phase = 'right'; HEAD.t0 = now; HEAD.buf = []; bannerShow('NOW TURN YOUR HEAD RIGHT AND HOLD', false); return; }
  if (HEAD.phase === 'right' && now - HEAD.t0 > 3000) {
    HEAD.R = headStats(HEAD.t0); const L = HEAD.L, R = HEAD.R, d = [0, 1, 2].map((i) => R.m[i] - L.m[i]), sg = [0, 1, 2].map((i) => (L.v[i] + R.v[i]) / 2 + 1e-4);
    const snr = Math.sqrt(d.reduce((a, x, i) => a + x * x / sg[i], 0));
    if (L.n < 8 || R.n < 8 || snr < 3) { HEAD.phase = 'left'; HEAD.t0 = now; HEAD.buf = []; bannerShow('TURN MORE: HEAD LEFT AND HOLD', false); return; }
    const w = d.map((x, i) => x / sg[i]), k = 2 / w.reduce((a, x, i) => a + x * d[i], 0);
    HEAD.w = w.map((x) => x * k); HEAD.mid = [0, 1, 2].map((i) => (L.m[i] + R.m[i]) / 2); HEAD.phase = 'run'; HEAD.msg = 'snr ' + snr.toFixed(1) + ' w ' + HEAD.w.map((x) => x.toFixed(3)).join(',');
    bannerShow('HEAD STEERING ON: TURN TO STEER', true); return;
  }
  if (HEAD.phase !== 'run') return;
  if (HEAD.rc && HEAD.rc !== HEAD.rcDone) { HEAD.rcDone = HEAD.rc; HEAD.mid = HEAD.cur.slice(); }
  if (HEAD.redo && HEAD.redo !== HEAD.redoDone) { HEAD.redoDone = HEAD.redo; HEAD.phase = 'wait'; pkCount = 0; return; }
  let sv = KIT.lost ? 0 : HEAD.flip * HEAD.w.reduce((a, x, i) => a + x * (f[i] - HEAD.mid[i]), 0);
  sv = Math.max(-1.3, Math.min(1.3, sv)); if (Math.abs(sv) < HEAD.dead) sv = 0;
  HEAD.s += (sv - HEAD.s) * (1 - Math.exp(-dt / Math.max(HEAD.tau, 0.005)));
  steerTarget = Math.max(-1, Math.min(1, HEAD.s * HEAD.gain)); lane = Math.round(steerTarget);
  KIT.zn = steerTarget; KIT.zone = lane; LOCK.lane = lane;          // (the log columns zn / zone / lock carry the head-steering value and its nearest lane)
  const gd = $('gdot'); gd.style.left = ((steerTarget * 0.45 + 0.5) * innerWidth) + 'px'; gd.style.top = (innerHeight * 0.5) + 'px';
}
function updateLane(dt) {
  if (HEAD.on) { if (playing && HEAD.phase !== 'run') waitT += dt; headUpdate(dt, performance.now()); return; }
  if (playing && !wasReady) waitT += dt;
  calUpdate(dt); gaugeUpdate(); cardsUpdate();
  if (!KIT.zones) {          // the first 40 readings are still coming in: the board stays in the middle, but the dot already follows the eyes (against the middle seen so far, at the starting size)
    lane = 0; steerTarget = 0;
    if (KIT.lastHx !== null && KIT.zauto.length) {
      const d = KIT.lastHx - median(KIT.zauto), zn = clampf(d > 0 ? -d / KIT.AUTO_D : -d / KIT.AUTO_D, -1.6, 1.6);
      const gd0 = $('gdot'); gd0.style.left = ((Math.tanh(zn * 0.8) * 0.45 + 0.5) * innerWidth) + 'px'; gd0.style.top = (innerHeight * 0.5) + 'px';
    }
    return;
  }
  lane = lockStep(KIT.zone, dt); steerTarget = lane;
  const cz = $('zones').children;
  for (let i = 0; i < 3; i++) { const l = i - 1, c = []; if (l === lane) c.push('on'); if (l === KIT.zone) c.push('zn'); cz[i].className = c.join(' '); }
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
// WHAT YOU CARRY: a boost (speed), a shield (takes one hit), double points; and being in the air (a ramp throws you up; you land for a bonus that grows with the hang time).
const ST = { boost: 0, shield: 0, mult: 0, y: 0, vy: 0, air: 0, chainT: 0, chain: 0, lastKind: -1 };
const AIR_G = 18, eul = new THREE.Euler();
const chipEl = document.createElement('div');
chipEl.style.cssText = 'position:fixed;left:0;right:0;top:calc(10px + clamp(22px,5vw,44px) * 1.5);text-align:center;color:#fff;font:700 clamp(12px,2.6vw,18px) ui-monospace,Consolas,monospace;letter-spacing:.14em;text-shadow:0 0 8px #000;z-index:5;pointer-events:none';
document.body.appendChild(chipEl);
const speedEl = document.createElement('div');
speedEl.style.cssText = 'position:fixed;right:12px;top:10px;color:#fff9;font:700 clamp(12px,2.6vw,18px) ui-monospace,Consolas,monospace;letter-spacing:.1em;text-shadow:0 0 8px #000;z-index:5;pointer-events:none;text-align:right';
document.body.appendChild(speedEl);
const bannerEl = document.createElement('div');
bannerEl.style.cssText = 'position:fixed;left:0;right:0;top:30%;text-align:center;color:#fff;font:300 clamp(26px,8vw,80px) ui-monospace,Consolas,monospace;letter-spacing:.3em;text-shadow:0 0 24px #fff8;z-index:6;pointer-events:none;opacity:0;transition:opacity .5s';
document.body.appendChild(bannerEl);
let bannerTimer = 0;
function bannerShow(txt, small) {
  bannerEl.textContent = txt; bannerEl.style.fontSize = small ? 'clamp(18px,5vw,44px)' : ''; bannerEl.style.opacity = '1';
  clearTimeout(bannerTimer); bannerTimer = setTimeout(() => { bannerEl.style.opacity = '0'; }, 1800);
}
const award = (n) => { G.score += Math.round(n * (ST.mult > 0 ? 2 : 1)); };
function link(kind) {          // Godot: every DIFFERENT thing inside 7 s links a chain
  if (ST.chainT > 0 && kind !== ST.lastKind) { ST.chain++; if (ST.chain >= 2) { award(40 * ST.chain); bannerShow('CHAIN x' + ST.chain, true); beep(520 + ST.chain * 90, 0.2, 0.08); } } else if (ST.chainT <= 0) ST.chain = 1;
  ST.lastKind = kind; ST.chainT = 7;
}
function crash(why) {
  if (ST.shield > 0) { ST.shield = 0; flash(0.3, 0.85, 1, 0.6); beep(300, 0.2, 0.12); bannerShow('SHIELD GONE', true); return; }
  G.combo = 0; G.hit++; speed *= 0.45; ST.chain = 0; flash(1, 0.05, 0.1, 0.8); beep(110, 0.35, 0.18); bannerShow(why, true);
}
function stepAir(dt) {
  if (ST.y > 0 || ST.vy > 0) {
    ST.vy -= AIR_G * dt; ST.y += ST.vy * dt; ST.air += dt;
    if (ST.y <= 0) { ST.y = 0; ST.vy = 0; const bonus = Math.round(ST.air * 80); if (ST.air > 0.6) { award(bonus); bannerShow('AIR +' + bonus, true); flash(0.6, 1, 0.8, 0.35); beep(330, 0.25, 0.1); } ST.air = 0; }
  }
}
function stepRows(dt) {
  const laneNow = Math.max(-1, Math.min(1, Math.round(camX / LANE_W)));
  ST.boost = Math.max(0, ST.boost - dt); ST.mult = Math.max(0, ST.mult - dt); ST.chainT = Math.max(0, ST.chainT - dt);
  const hz = (m, k) => m.setMatrixAt(k, HIDE);
  for (let i = 0; i < N_RING; i++) {
    const r = rows[i];
    if (r.z > zPos + 25) setRow(r, r.z - SPAN);
    if (!r.passed && r.z <= zPrev && r.z > zPos - 1) {
      r.passed = true; LOCK.free = true;
      if (r.guide !== 9 && r.votes) {
        GUIDE.bTried++; const v = r.votes, best = v.indexOf(Math.max(...v)) - 1; if (v[0] + v[1] + v[2] > 0 && best === r.guide) GUIDE.bHits++;
        if (GUIDE.bTried >= GUIDE.bSize && GUIDE.bSize > 0) {
          bannerShow('EYES TUNED: ' + GUIDE.bHits + ' OF ' + GUIDE.bSize + ' LOOKS READ', true);
          if (GUIDE.first && GUIDE.bHits >= 2) { try { localStorage.setItem('spike_cal_done', '1'); } catch (e) { /* */ } }          // the intro is not shown again on this device once it has read two of the three looks
          GUIDE.first = false; GUIDE.bSize = 0; GUIDE.bTried = 0; GUIDE.bHits = 0;
        }
      }
    }          // past the thing: the lock is let go
    for (let sd = 0; sd < 3; sd++) {
      const o = r.s[sd], lane = sd - 1, lx = lane * LANE_W, si = i * 3 + sd;
      const crossing = (z) => !o.done && z <= zPrev && z > zPos - 1;          // the line z lies between where the camera was and where it is now
      const mine = HEAD.on ? Math.abs(camX - lx) < 7.5 : laneNow === lane;          // (head steering: the board is anywhere, so a thing is taken when it is within reach and a rock only when the board is on one)
      for (let k = 0; k < 6; k++) hz(orbMesh, i * 18 + sd * 6 + k);
      hz(ringMesh, si); hz(beamMesh, si); hz(padMesh, si); hz(pickMesh, si); hz(pickWire, si); hz(rampMesh, si); hz(rockMesh, i * 6 + sd * 2); hz(rockMesh, i * 6 + sd * 2 + 1);
      if (!o) continue;
      if (o.type === 0) {
        for (let k = 0; k < 6; k++) {
          const oz = r.z - k * 5, ox = lx + Math.sin(k * 0.9 + t * 3) * 0.6;
          const oc = o.orbs[k] && oz <= zPrev && oz > zPos - 1 && Math.abs(camX - lx) < 8.0;
          if (oc) { o.orbs[k] = false; G.combo++; G.best = Math.max(G.best, G.combo); award(10 * (1 + Math.floor(G.combo / 8))); G.got++; flash(0, 1, 0.8, 0.28); beep(440 + Math.min(G.combo, 14) * 40, 0.12, 0.08); }
          if (o.orbs[k]) { m4.compose(v3.set(ox, 2.6, oz), q4.identity(), s3.setScalar(1)); orbMesh.setMatrixAt(i * 18 + sd * 6 + k, m4); orbMesh.setColorAt(i * 18 + sd * 6 + k, themeCol(t * 0.3 + k * 0.06 + i * 0.1, colr)); }
        }
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(0.2, 1, 0.5));
        m4.compose(v3.set(lx, 0.25, r.z), q4.identity(), s3.setScalar(1)); padMesh.setMatrixAt(si, m4); padMesh.setColorAt(si, colr.setRGB(0.1, 0.6, 0.3));
      } else if (o.type === 1) {
        m4.compose(v3.set(lx, 4.5, r.z), q4.identity(), s3.setScalar(0.8)); ringMesh.setMatrixAt(si, m4); ringMesh.setColorAt(si, themeCol(t * 0.1 + i * 0.13, colr));
        m4.compose(v3.set(lx, 0.25, r.z), q4.identity(), s3.setScalar(1)); padMesh.setMatrixAt(si, m4); padMesh.setColorAt(si, colr.setRGB(1, 0.9 * (0.6 + 0.4 * Math.sin(t * 6)), 0.1));
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(1, 0.9, 0.2));
        if (crossing(r.z)) { o.done = true; if (mine) { G.combo += 3; G.best = Math.max(G.best, G.combo); award(100 * (1 + Math.floor(G.combo / 8))); G.got++; link(1); flash(1, 0.9, 0.2, 0.55); beep(660, 0.25, 0.1); setTimeout(() => beep(990, 0.3, 0.08), 90); } }
      } else if (o.type === 2) {
        const pk = PICKS[o.pick], c = pk.col, a = t * 1.7 + i;
        q4.setFromEuler(eul.set(a * 0.6, a, 0));
        m4.compose(v3.set(lx, 3 + Math.sin(t * 3 + i) * 0.5, r.z), q4, s3.setScalar(1)); pickMesh.setMatrixAt(si, m4); pickMesh.setColorAt(si, colr.setRGB(c[0], c[1], c[2]));
        m4.compose(v3.set(lx, 3 + Math.sin(t * 3 + i) * 0.5, r.z), q4, s3.setScalar(1)); pickWire.setMatrixAt(si, m4); pickWire.setColorAt(si, colr.setRGB(c[0], c[1], c[2]).multiplyScalar(0.8));
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(c[0], c[1], c[2]));
        m4.compose(v3.set(lx, 0.25, r.z), q4.identity(), s3.setScalar(1)); padMesh.setMatrixAt(si, m4); padMesh.setColorAt(si, colr.setRGB(c[0] * 0.5, c[1] * 0.5, c[2] * 0.5));
        if (crossing(r.z)) {
          o.done = true;
          if (mine) {
            G.got++; link(2 + o.pick); G.combo += 2; G.best = Math.max(G.best, G.combo);
            if (o.pick === 0) { ST.boost = 3; speed += 12; flash(1, 0.55, 0.1, 0.5); beep(520, 0.3, 0.1); bannerShow('BOOST', true); }
            else if (o.pick === 1) { ST.shield = 1; flash(0.3, 0.85, 1, 0.5); beep(700, 0.3, 0.1); bannerShow('SHIELD', true); }
            else if (o.pick === 2) { ST.mult = 12; flash(0.95, 0.4, 1, 0.5); beep(880, 0.3, 0.1); bannerShow('DOUBLE POINTS', true); }
            else { award(150); flash(1, 0.85, 0.35, 0.5); beep(990, 0.3, 0.1); }
          }
        }
      } else if (o.type === 3) {
        m4.compose(v3.set(lx, 1.7, r.z), qRamp, s3.setScalar(1)); rampMesh.setMatrixAt(si, m4); rampMesh.setColorAt(si, colr.setRGB(0.95, 0.35, 1));
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(0.95, 0.35, 1));
        if (crossing(r.z - 8)) { o.done = true; if (mine) { ST.vy = 10 + speed * 0.18; ST.y = 0.01; ST.air = 0; G.got++; link(6); flash(0.95, 0.35, 1, 0.4); beep(260, 0.25, 0.1); } }
      } else {
        for (let n = 0; n < 2; n++) { m4.compose(v3.set(lx + (n ? 4.5 : -4.5), 2.4, r.z), q4.identity(), s3.set(2.6, 1.8, 2.6)); rockMesh.setMatrixAt(i * 6 + sd * 2 + n, m4); rockMesh.setColorAt(i * 6 + sd * 2 + n, colr.setRGB(1, 0.25 + 0.15 * Math.sin(t * 5), 0.15)); }
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(1, 0.2, 0.1));
        if (crossing(r.z)) { o.done = true; if ((HEAD.on ? (Math.abs(camX - lx - 4.5) < 3.6 || Math.abs(camX - lx + 4.5) < 3.6) : mine) && ST.y < 3) crash('ROCK'); }
      }
    }
  }
  for (const mm of allMeshes) { mm.instanceMatrix.needsUpdate = true; if (mm.instanceColor) mm.instanceColor.needsUpdate = true; }
  G.flash = Math.max(0, G.flash - dt * 1.6);
  scoreEl.textContent = G.score + (G.combo > 1 ? '   x' + G.combo : '');
  const chips = [];
  if (ST.boost > 0) chips.push('BOOST ' + ST.boost.toFixed(1)); if (ST.shield > 0) chips.push('SHIELD'); if (ST.mult > 0) chips.push('x2 ' + ST.mult.toFixed(0)); if (ST.chain > 1 && ST.chainT > 0) chips.push('CHAIN ' + ST.chain);
  chipEl.textContent = chips.join('   ');
  const tm = Math.floor(tPlay / 60), ts = Math.floor(tPlay % 60);
  speedEl.textContent = Math.round(speed * 3.6) + ' km/h\n' + THEMES[worldIdx].name + '\n' + tm + ':' + (ts < 10 ? '0' : '') + ts + (tPlay >= 60 ? '  ✓' : '');
  if (!stepRows.said && tPlay >= 60) { stepRows.said = true; bannerShow('60 SECONDS: ENOUGH DATA', true); beep(880, 0.2, 0.08); setTimeout(() => beep(1320, 0.3, 0.08), 150); }
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
const LOCAL = /^(localhost|127\.|10\.|192\.168\.|\[?::1)/.test(location.hostname);          // local dev server (logs to web/spike) or the VPS (logs through log.php, tunes from tune.json beside the game folders)
const LOG = { buf: [], last: 0, sid: Math.random().toString(16).slice(2, 8) };
function logSample(now) {
  if (!started || !playing || !eyeMode || now - LOG.last < 100 || KIT.lastHx === null) return;          // (not while paused: a paused run logged the same gate hundreds of times)
  LOG.last = now;
  let open = 9, dist = -1, bz = -1e9;
  for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) { bz = r.z; open = r.s.reduce((a, o) => a * 10 + (o ? o.type + 1 : 0), 0); dist = zPos - r.z; }          // the nearest row's three kinds as one number (left, middle, right; 0 = nothing there, else type + 1): there is no right answer, the log shows what was offered and what the eyes picked
  LOG.buf.push([+(now / 1000).toFixed(2), +KIT.lastHx.toFixed(4), +KIT.zn.toFixed(2), KIT.zone, LOCK.lane, +camX.toFixed(1), open, +dist.toFixed(0), +speed.toFixed(0), KIT.held ? 1 : 0, +LOCK.want[-1].toFixed(2), +LOCK.want[0].toFixed(2), +LOCK.want[1].toFixed(2), +(Number.isFinite(KIT.ha) ? KIT.ha : 0).toFixed(4), +(Number.isFinite(KIT.hb) ? KIT.hb : 0).toFixed(4), +(KIT.yaw || 0).toFixed(1), +(KIT.pitch || 0).toFixed(1), +(KIT.roll || 0).toFixed(1), +(KIT.fx || 0).toFixed(4), +(KIT.fy || 0).toFixed(4), +(KIT.fsz || 0).toFixed(4), +((KIT.lids || [0, 0])[0]).toFixed(4), +((KIT.lids || [0, 0])[1]).toFixed(4), +(EM ? EM.m[0] : 0).toFixed(4), +(EM ? EM.m[1] : 0).toFixed(4), +(EM ? EM.post[0] : 0).toFixed(2), +(EM ? EM.post[1] : 0).toFixed(2), +(EM ? EM.post[2] : 0).toFixed(2), +(EM ? Math.sqrt(EM.S[0]) : 0).toFixed(4), +(EM ? Math.sqrt(EM.S[1]) : 0).toFixed(4), KIT.gl === undefined ? 9 : KIT.gl, KIT.gp === undefined ? 9 : KIT.gp, (KIT.gl === undefined || KIT.gl === 9) ? 0 : GX[KIT.gl], KIT.gw === undefined ? 0 : KIT.gw, +(EM ? EM.corr[0] : 0).toFixed(4), +(EM ? EM.corr[1] : 0).toFixed(4), +HEAD.s.toFixed(3), +HEAD.neu.toFixed(3), +HEAD.k.toFixed(3)]);
  if (LOG.buf.length >= 50) flushLog();
}
function flushLog() {
  if (!LOG.buf.length) return;
  const body = JSON.stringify({ sid: LOG.sid, app: 'downhill-three', cols: 't,hx,zn,zone,lock,camX,open,dist,speed,held,wL,wM,wR,ha,hb,yaw,pitch,roll,fx,fy,fsz,lA,lB,mA,mB,pL,pM,pR,sA2,sB2,gl,gp,gx,gw,cA,cB,hs,hn,hk', tv: TUNE.v, eye: EYE.sel, sA: +EYE.sA.toFixed(2), sB: +EYE.sB.toFixed(2), gfps: (window.__spike || {}).fps || 0, mms: Math.round((window.__gazeStats || {}).inf || 0), zd: +KIT.zdrift.toFixed(4), m: KIT.zones ? KIT.zones.m : 0, dl: KIT.zones ? KIT.zones.dl : 0, dr: KIT.zones ? KIT.zones.dr : 0, s: LOG.buf });
  LOG.buf = [];
  try { fetch(LOCAL ? '/spike/log' : '../log.php', { method: 'POST', body, keepalive: true }); } catch (e) { /* no server */ }
}
addEventListener('pagehide', flushLog);
async function tunePoll() {
  try {
    const r = await fetch((LOCAL ? '../spike/tune.json' : '../tune.json') + '?_=' + Date.now(), { cache: 'no-store' }); if (!r.ok) return;
    const j = await r.json(); if (j.v === TUNE.v) return; TUNE.v = j.v;
    if (j.EM && EM) for (const k in j.EM) if (typeof EM[k] === 'number' && typeof j.EM[k] === 'number') EM[k] = j.EM[k];
    if (j.LOCK) for (const k in j.LOCK) if (typeof j.LOCK[k] === 'number') TUNE[k] = j.LOCK[k];
    if (j.HEAD) for (const k in j.HEAD) if (typeof HEAD[k] === 'number' && typeof j.HEAD[k] === 'number') HEAD[k] = j.HEAD[k];
    if (j.KIT) for (const k in j.KIT) if (typeof KIT[k] === 'number' && typeof j.KIT[k] === 'number') KIT[k] = j.KIT[k];
    if (j.recentre && EM) EM.recentre();
    bannerShow('TUNED v' + j.v, true);
  } catch (e) { /* no tune file */ }
}
setInterval(tunePoll, 2000);

// THE LOOP
let zPrev = 0, t = 0, zPos = 0, speed = 28, last = performance.now(), lastHud = 0, camX = 0, ping = 0;
const fts = [];
function frame(now) {
  requestAnimationFrame(frame);
  const dtMs = now - last;
  last = now;
  const dt = Math.max(0, Math.min(dtMs / 1000, 0.1));
  t += dt;
  fts.push(dtMs);
  if (fts.length > 240) fts.shift();
  if (eyeMode && started) { readTracker(now); updateLane(dt); }
  telTick(now, dt);
  logSample(now);
  steer += (steerTarget - steer) * (1 - Math.exp(-TUNE.steerK * dt));
  if (playing && ctrlReady()) { tPlay += dt; worldT += dt; if (!worldQ && worldT > WORLD_SECS) { worldT = 0; setWorld(worldIdx + 1); } stepAir(dt); }
  worldBlend(dt);
  speed = Math.min(Math.min(64, 28 + tPlay * 0.4) + (ST.boost > 0 ? 22 : 0), speed + (ST.boost > 0 ? 40 : 15) * dt);          // slower than before (it was up to 110): time to look, choose, and let the board slide          // (a crash halves it; it climbs back at 25 m/s per second, up to the pace of the run)
  zPrev = zPos;
  if (playing && ctrlReady()) zPos -= speed * dt;
  camX += (steer * LANE_W - camX) * (1 - Math.exp(-TUNE.camK * dt));
  camera.position.set(camX, 3.2 + ST.y, zPos);
  camera.fov = 85 + (speed - 28) * 0.2 + (ST.boost > 0 ? 8 : 0);
  camera.rotation.set(-0.08, -steer * 0.08, -steer * 0.12, 'YXZ');
  camera.aspect = W / H;
  camera.updateProjectionMatrix();
  groundMat.uniforms.uT.value = t;
  skyMat.uniforms.uT.value = t; sky.position.copy(camera.position);
  groundMat.uniforms.uCam.value.copy(camera.position);
  ground.position.set(camera.position.x, 0, camera.position.z - 300);
  for (const mm of allMeshes) mm.visible = flags.objects;
  if (flags.objects) {
    for (let i = 0; i < N_PYL; i++) {
      const p = pyl[i];
      if (p.z > zPos + 20) { p.z -= SPAN; p.x = (Math.random() < 0.5 ? -1 : 1) * (LANE_W * 1.5 + 8 + Math.random() * 34); }
      m4.compose(v3.set(p.x, 3.5 * p.s, p.z), q4.identity(), s3.set(p.s, p.s, p.s));
      pylMesh.setMatrixAt(i, m4);
      pylMesh.setColorAt(i, themeCol(t * 0.05 + p.z * 0.003, colr));
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
    compMat.material.uniforms.uTrace.value = flags.tracers ? TH.trace : 0;
    compMat.material.uniforms.uSplit.value = flags.split ? TH.split : 0;
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
setWorld(worldQ ? Math.max(0, THEMES.findIndex((x) => x.id === worldQ)) : 0, true);
requestAnimationFrame(frame);
window.__dh = { HEAD, KIT, renderer, scene, camera, groundMat, skyMat, TH, frame, ST, G, dbg: () => ({ steer, steerTarget, camX, lane, TUNE, speed, zPos }) };
