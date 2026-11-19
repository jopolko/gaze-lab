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
const ringMesh = new THREE.InstancedMesh(new THREE.TorusGeometry(9, 0.18, 3, 28), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 2);
const orbMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(1.5, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 12);
const wallMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 2, 7, 2), new THREE.MeshBasicMaterial({ wireframe: true, color: 0xffffff }), N_RING * 2);
const beamMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1.6, 90, 1.6), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 2);          // a tall beam over each row's lane: visible from far away, so the choice can be seen (and looked at) long before the ring itself
const padMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 4, 0.5, 18), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 2);          // a glowing pad on the ground at the open lane: the base of the gate, low on the screen, where the eyes rest
const pickMesh = new THREE.InstancedMesh(new THREE.OctahedronGeometry(2.6, 0), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 2);
const pickWire = new THREE.InstancedMesh(new THREE.OctahedronGeometry(3.6, 0), new THREE.MeshBasicMaterial({ color: 0xffffff, wireframe: true }), N_RING * 2);
const rampMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(LANE_W - 6, 0.7, 18), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 2);
const rockMesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(3.4, 0), new THREE.MeshBasicMaterial({ color: 0xffffff }), N_RING * 4);
const allMeshes = [pylMesh, ringMesh, orbMesh, wallMesh, beamMesh, padMesh, pickMesh, pickWire, rampMesh, rockMesh];
wallMesh.count = 0;          // (walls are gone: there is nothing to be walled off from, the middle is open)
for (const mm of allMeshes) { mm.frustumCulled = false; scene.add(mm); }
const PICKS = [          // kind: what it does (Godot: CRYSTAL a longer boost, CAGE a shield, RINGS double points, CLUSTER a lump of points)
  { name: 'BOOST', col: [1.0, 0.55, 0.1] }, { name: 'SHIELD', col: [0.3, 0.85, 1.0] }, { name: 'x2', col: [0.95, 0.4, 1.0] }, { name: 'POINTS', col: [1.0, 0.85, 0.35] },
];
const rows = [];
// EVERY ROW IS A CHOICE OF TWO (RunRig._gen_feats): something on the left and something DIFFERENT on the right, side by side, nothing in the middle. You can not have both, the board takes
// neither by itself, and the one you get is the one you looked at. Resting your eyes in the middle (the board rides between them) costs nothing and picks nothing.
// kinds: 0 orbs (points), 1 ring (a bonus ring), 2 pickup (boost / shield / x2 / points), 3 ramp (a jump), 4 rocks (a crash: rare, and the other side is never rocks too)
function mkThing(avoid, calm) {
  const hz = calm ? 0 : Math.min(0.12, 0.03 + tPlay * 0.0003);
  for (let tries = 0; tries < 20; tries++) {
    const k = Math.random();
    const type = k < 0.28 ? 0 : k < 0.50 ? 1 : k < 0.78 ? 2 : k < 1 - hz ? 3 : 4;
    const pick = Math.floor(Math.random() * 4);
    if (avoid && avoid.type === type && (type !== 2 || avoid.pick === pick)) continue;
    if (avoid && avoid.type === 4 && type === 4) continue;
    return { type, pick, orbs: [0, 1, 2, 3, 4, 5].map(() => true), done: false };
  }
  return { type: 0, pick: 0, orbs: [true, true, true, true, true, true], done: false };
}
function setRow(r, z) {
  r.z = z; r.passed = false;
  const calm = tPlay < 20;          // the first 20 seconds: no hazards
  const a = mkThing(null, calm), b = mkThing(a, calm);
  r.s = Math.random() < 0.5 ? [a, b] : [b, a];          // [left, right]
}
let tPlay = 0;
for (let i = 0; i < N_RING; i++) { const r = { i }; setRow(r, -50 - i * ROW_GAP); rows.push(r); }
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
  // RunRig._trail_pick on the open slope: two things, left and right. A look to a side chooses that side's thing; a look at the middle chooses nothing and changes nothing (what was chosen stays
  // chosen, and with nothing chosen the board rides between them). Fill / drain / commitment times are Godot's: a first look settles after 0.11 s, a change of mind needs 0.35 s, then 0.14 s once
  // the half-second commitment is over, and none in the last quarter second before the board reaches the thing.
  const qk = 0.7;          // at speed everything about choosing is quicker (Godot: qk 0.6 flat out)
  for (const l of [-1, 1]) {
    if (zone === l) LOCK.want[l] = Math.min(LOCK.want[l] + dt, 0.5);
    else LOCK.want[l] = Math.max(LOCK.want[l] - dt * (zone !== 0 ? 3.0 : 0.6), 0);
  }
  LOCK.age += dt;
  let need = LOCK.lane === 0 ? 0.11 * qk : (LOCK.age >= 0.5 * qk ? 0.14 : 0.35) * qk;
  const nd = nextRowDist();
  if (LOCK.lane !== 0 && nd / Math.max(speed, 14) < 0.25) need = 9;
  for (const l of [-1, 1]) if (l !== LOCK.lane && LOCK.want[l] > need) { LOCK.lane = l; LOCK.age = 0; break; }
  return LOCK.lane;
}
function nextRowDist() {          // how far ahead the nearest row is (m)
  let bz = -1e9;
  for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) bz = r.z;
  return bz > -1e8 ? zPos - bz : 999;
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
    if (!r.passed && r.z <= zPrev && r.z > zPos - 1) { r.passed = true; LOCK.lane = 0; LOCK.age = 9; }          // past the choice: what was chosen is released, the board rides back between
    for (let sd = 0; sd < 2; sd++) {
      const o = r.s[sd], lane = sd === 0 ? -1 : 1, lx = lane * LANE_W, si = i * 2 + sd;
      const crossing = (z) => !o.done && z <= zPrev && z > zPos - 1;          // the line z lies between where the camera was and where it is now
      const mine = laneNow === lane;
      for (let k = 0; k < 6; k++) hz(orbMesh, i * 12 + sd * 6 + k);
      hz(ringMesh, si); hz(beamMesh, si); hz(padMesh, si); hz(pickMesh, si); hz(pickWire, si); hz(rampMesh, si); hz(rockMesh, i * 4 + sd * 2); hz(rockMesh, i * 4 + sd * 2 + 1);
      if (o.type === 0) {
        for (let k = 0; k < 6; k++) {
          const oz = r.z - k * 5, ox = lx + Math.sin(k * 0.9 + t * 3) * 0.6;
          const oc = o.orbs[k] && oz <= zPrev && oz > zPos - 1 && Math.abs(camX - lx) < 8.0;
          if (oc) { o.orbs[k] = false; G.combo++; G.best = Math.max(G.best, G.combo); award(10 * (1 + Math.floor(G.combo / 8))); G.got++; flash(0, 1, 0.8, 0.28); beep(440 + Math.min(G.combo, 14) * 40, 0.12, 0.08); }
          if (o.orbs[k]) { m4.compose(v3.set(ox, 2.6, oz), q4.identity(), s3.setScalar(1)); orbMesh.setMatrixAt(i * 12 + sd * 6 + k, m4); orbMesh.setColorAt(i * 12 + sd * 6 + k, themeCol(t * 0.3 + k * 0.06 + i * 0.1, colr)); }
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
        for (let n = 0; n < 2; n++) { m4.compose(v3.set(lx + (n ? 4.5 : -4.5), 2.4, r.z), q4.identity(), s3.set(2.6, 1.8, 2.6)); rockMesh.setMatrixAt(i * 4 + sd * 2 + n, m4); rockMesh.setColorAt(i * 4 + sd * 2 + n, colr.setRGB(1, 0.25 + 0.15 * Math.sin(t * 5), 0.15)); }
        m4.compose(v3.set(lx, 45, r.z), q4.identity(), s3.setScalar(1)); beamMesh.setMatrixAt(si, m4); beamMesh.setColorAt(si, colr.setRGB(1, 0.2, 0.1));
        if (crossing(r.z)) { o.done = true; if (mine && ST.y < 3) crash('ROCK'); }
      }
    }
  }
  for (const mm of allMeshes) { mm.instanceMatrix.needsUpdate = true; if (mm.instanceColor) mm.instanceColor.needsUpdate = true; }
  G.flash = Math.max(0, G.flash - dt * 1.6);
  scoreEl.textContent = G.score + (G.combo > 1 ? '   x' + G.combo : '');
  const chips = [];
  if (ST.boost > 0) chips.push('BOOST ' + ST.boost.toFixed(1)); if (ST.shield > 0) chips.push('SHIELD'); if (ST.mult > 0) chips.push('x2 ' + ST.mult.toFixed(0)); if (ST.chain > 1 && ST.chainT > 0) chips.push('CHAIN ' + ST.chain);
  chipEl.textContent = chips.join('   ');
  speedEl.textContent = Math.round(speed * 3.6) + ' km/h\n' + THEMES[worldIdx].name;
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
  for (const r of rows) if (!r.passed && r.z < zPos && r.z > bz) { bz = r.z; open = r.s[0].type * 10 + r.s[1].type; dist = zPos - r.z; }          // the nearest row's two kinds (left * 10 + right): there is no right answer now, the log shows what was offered and what the eyes picked
  LOG.buf.push([+(now / 1000).toFixed(2), +KIT.lastHx.toFixed(4), +KIT.zn.toFixed(2), KIT.zone, LOCK.lane, +camX.toFixed(1), open, +dist.toFixed(0), +speed.toFixed(0), KIT.held ? 1 : 0, +LOCK.want[-1].toFixed(2), +LOCK.want[0].toFixed(2), +LOCK.want[1].toFixed(2)]);
  if (LOG.buf.length >= 50) flushLog();
}
function flushLog() {
  if (!LOG.buf.length) return;
  const body = JSON.stringify({ sid: LOG.sid, app: 'downhill-three', cols: 't,hx,zn,zone,lock,camX,open,dist,speed,held,wL,wM,wR', m: KIT.zones ? KIT.zones.m : 0, dl: KIT.zones ? KIT.zones.dl : 0, dr: KIT.zones ? KIT.zones.dr : 0, s: LOG.buf });
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
  if (playing) { tPlay += dt; worldT += dt; if (!worldQ && worldT > WORLD_SECS) { worldT = 0; setWorld(worldIdx + 1); } stepAir(dt); }
  worldBlend(dt);
  speed = Math.min(Math.min(64, 28 + tPlay * 0.4) + (ST.boost > 0 ? 22 : 0), speed + (ST.boost > 0 ? 40 : 15) * dt);          // slower than before (it was up to 110): time to look, choose, and let the board slide          // (a crash halves it; it climbs back at 25 m/s per second, up to the pace of the run)
  zPrev = zPos;
  if (playing) zPos -= speed * dt;
  camX += (steer * LANE_W - camX) * (1 - Math.exp(-5 * dt));
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
window.__dh = { renderer, scene, camera, groundMat, skyMat, TH, frame, ST, G };
