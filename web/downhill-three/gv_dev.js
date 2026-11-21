// GODOT LEVEL VIEWER. Renders a level DUMPED from the real Godot game (godot/tests/dump_level.gd: the real generator, run headless with a fixed seed) so that every mesh, every instance and every transform
// is the game's own, not an approximation. Godot and three.js are both right-handed, Y up, -Z forward, so transforms carry over as they are. What this file does: build geometry from the dumped vertex arrays,
// map Godot's materials (StandardMaterial3D -> MeshStandardMaterial, each shader -> a GLSL port), set the sun, the sky-lit ambient, the exponential fog and the filmic tonemap from the dumped Environment, and fly a camera down the course.
import * as THREE from 'three';
const Q = new URLSearchParams(location.search); window.__RUNSEED = Q.has('seed') ? Math.floor(parseFloat(Q.get('seed')) || 7) : Math.floor(Math.random() * 90000) + 1;          // each visit rolls a new run seed (the extra objects, phrase order and lanes all follow it); &seed=N repeats a run. It is shown when paused.
// BIOME PROFILES: each biome starts with its own defaults for the density and look settings (anything set by hand, in the link or in the panel still wins). Trip is the original and has none.
const BIOME_PROFILES = { psychedelic: {}, alpine: { density: .4, shaftmolk: 8 }, candy: { density: .7, shaftmolk: 4, hoops: 1 }, tunnel: { density: .3, hoops: .8, shaftmolk: 6, slalomrun: 3 }, desert: { density: .4, shaftmolk: 6 }, matrix: { density: .35, shaftmolk: 7, ascii: .5 }, synthwave: { density: .5, shaftmolk: 6, vector: .5 } };
const BDEF = BIOME_PROFILES[Q.get('theme') || 'psychedelic'] || {};
// FULLSCREEN: browsers only allow it from a tap or key press, so the first tap or key (the tap-to-start) takes the page fullscreen, with the browser's own bars hidden. It tries again on later taps if it was left (Esc), and &nofs turns it off.
{ const goFS = () => { if (Q.has('nofs') || document.fullscreenElement || document.webkitFullscreenElement) return; const el = document.documentElement, f = el.requestFullscreen || el.webkitRequestFullscreen; if (f) { try { const r = f.call(el, { navigationUI: 'hide' }); if (r && r.catch) r.catch(() => { }); } catch (e) { } } }; for (const ev of ['pointerup', 'touchend', 'click', 'keydown']) addEventListener(ev, goFS, true); } const LABS = (() => { try { return Q.has('nolab') ? null : JSON.parse(localStorage.getItem('steerlab') || 'null'); } catch (e) { return null; } })(), LIVE = (() => { try { return Q.has('nolab') || Q.has('resettune') ? {} : JSON.parse(localStorage.getItem('gvtune') || '{}'); } catch (e) { return {}; } })(), sp = (n, d) => (LIVE[n] !== undefined ? LIVE[n] : Q.has(n) ? parseFloat(Q.get(n)) : (LABS && LABS[n] !== undefined && isFinite(+LABS[n]) ? +LABS[n] : (BDEF[n] !== undefined ? BDEF[n] : d)));          /* steering settings: ?name=value, else what steerlab.html saved (Save for the game), else the default; &nolab ignores the saved ones */ const VEGIM = [];          // every big instanced mesh (trees, rocks): the saw removes the instances at a cut tree window.__dm && window.__dm('gv.js: imports loaded, module running');
// THE CAMERA STARTS AT ONCE: with ?head the tracker (camera, face model) is started the moment the page opens, in parallel with loading the level, so it is ready by the time the course is.
let openGate = null; const GATE = new Promise((r) => { openGate = r; }); let openTap = null; const TAPGATE = new Promise((r) => { openTap = r; }); const TAPCAM = Q.has('tapcam') || !Q.has('notap');          /* phones: a tap starts the camera AND the music (browsers allow sound only after a tap), so the music is already playing when the race begins; &notap skips it */          // ?tapcam: the old way, nothing about the camera starts until you tap
const EARLY = Q.has('head') ? (async () => {
  const video = document.createElement('video'); video.playsInline = true; video.muted = true; video.autoplay = true; video.style.cssText = 'position:fixed;right:0;bottom:0;width:2px;height:2px;opacity:.01;pointer-events:none'; document.body.appendChild(video);
  window.__dm && window.__dm('tracker: importing now (the tap only starts the music and the race)'); const { Tracker } = await import('../stargaze/tracker.js?' + Date.now()); window.__dm && window.__dm('tracker module imported'); const tr = new Tracker(video); if (Q.has('hires')) { tr.camW = 1280; tr.camH = 720; tr.fullRes = true; } else { tr.camW = 640; tr.camH = 480; tr.fullRes = false; } tr.useWorker = true; tr.inW = +Q.get('inw') || 256; window.__trk = tr;          /* head steering does not need 720p (?hires brings it back) */
  // the module and the tracker object are made now (cheap); the camera and the face model start the moment the course is built (openGate), never while the game is still compiling
  window.__gazeStatus = 'waiting for the course';
  const p = GATE.then(() => { window.__dm && window.__dm('gate open: starting the camera and model'); return tr.start((m) => { window.__gazeStatus = m; window.__dm && window.__dm('tracker stage: ' + m); }, Q.get('fakecam')); }).then((r) => { window.__dm && window.__dm('tracker started'); return r; }); p.catch(() => { }); return { tr, p };
})() : null; if (EARLY) EARLY.catch(() => { });
const LVL = Q.get('lvl') || 'long_s7';          // the streamed Godot level (data/long_s7: meta.json, physics.json and one row_NN.json per 180 m); ?lvl=level_psy_s7 (or level_wide2_s7) loads a whole static dump instead
const START_ROW = Math.max(0, parseInt(Q.get('row') || '0', 10) || 0);          // ?row=5 starts the run in the fifth 180 m row (to jump straight to a realm)
const STREAM = !Q.get('lvl'); const LVLDIR = './data/' + (Q.get('course') || 'long_s7') + '/';          // ?course=long_w11 plays the winding course (Godot's own winding trail: a turn about every 94 m, a narrow trail, slalom poles)
const hud = document.getElementById('hud');
THREE.ColorManagement.enabled = true;
// Godot's exponential fog (1 - exp(-density * distance)); three's own is squared
THREE.ShaderChunk.fog_fragment = `#ifdef USE_FOG
  float fogFactor = 1.0 - exp( - fogDensity * vFogDepth );
  gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );
#endif`;
const canvas = document.getElementById('gl');
let renderer; try { renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' }); } catch (e) {          // the browser could not make a graphics context: say so, with what to try, instead of sitting on a loader
  window.__dm && window.__dm('NO WEBGL: ' + (e && e.message)); document.body.style.background = '#10041a';
  document.body.innerHTML = '<div style="color:#fff;font:16px/1.5 system-ui,Segoe UI,sans-serif;max-width:640px;margin:12vh auto;padding:0 20px"><h2 style="color:#fc8;margin:0 0 12px">Graphics are switched off in this browser for now</h2><p>A browser turns graphics (WebGL) off for the rest of its session once it has had to reset them several times. Earlier versions of this game caused such resets, and we are fixing that. This is our bug, not something you did.</p><p><b>To get it back:</b> close every browser window (check Task Manager for leftover browser processes), then open this page again.</p><p>If it happens again after a fresh start, that is a new bug in the game: please tell us, and add <b>&amp;diag</b> to the address so the game can report what it did.</p><p style="opacity:.6">Detail: ' + String((e && e.message) || e).replace(/[<>&]/g, '') + '</p></div>'; throw e; }
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5)); renderer.toneMapping = THREE.CineonToneMapping; renderer.toneMappingExposure = 1.05;
const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(78, 1, 0.2, 1600);
const clock = { t: 0 };
import { MOLS, MOL_ORDER } from './molecules.js';
import { createSpawn } from './spawn.js';
import { ringShape, RING_KIND } from './ringshape.js';
import { createBiomeProps } from './biomeprops.js';
import { buildMolGeometry, moleculeMaterial } from './molmesh.js';
import { createToys } from './toys.js';
import { createPsyFx } from './psyfx.js';
import { createPostFx } from './postfx.js';
import { createHeightfield } from './heightfield.js';
import { createTiers, detectWeakGpu, pixelBudget } from './tiers.js';
import { createCamRig } from './camrig.js';
import { createAudioWire } from './audiowire.js';
import { createSfx } from './sfxset.js';
import { createCarveTrail } from './carvetrail.js';
import { createEchoes } from './echoes.js';
import { createSnowball } from './snowball.js';
import { glowify, glowLit } from './glowify.js';
import { TUNE } from './tuning.js';
import { skyBiome, vegBiome } from './biomes.js';
import { ringBiome } from './rings.js';
import { realmMaterial, ROOF } from './realms.js';
import { createWeather } from './weather.js';
import { loadProfile, saveProfile, recordCatch } from './profile.js';
import { CARD_NAMES } from './names.js';
const PROFILE = loadProfile();          // the collection that persists between trips
if (!Q_has_realnames()) for (const id of Object.keys(MOLS)) { MOLS[id].realName = MOLS[id].name; MOLS[id].name = CARD_NAMES[id] || MOLS[id].name; }
globalThis.__relicName = (id) => (MOLS[id] && MOLS[id].name) || id;
function Q_has_realnames() { try { return new URLSearchParams(location.search).has('realnames'); } catch (e) { return false; } }
import { createGvMusic, CREDITS } from './gvmusic.js';
import { createVortexFx } from './vortexfx.js';
import { createWorldFx, GROUND_PAL, S2L_GLSL, ALPINE } from './worldfx.js';
import { createFx } from './fx.js';
import { createLab } from './lab.js';
import { createKit } from './kit.js';
const U = { uRegion: { value: (() => { const t = new THREE.DataTexture(new Float32Array(2), 2, 1, THREE.RedFormat, THREE.FloatType); t.needsUpdate = true; return t; })() }, uRegN: { value: 2 }, uTrail: { value: (() => { const t = new THREE.DataTexture(new Float32Array(2), 2, 1, THREE.RedFormat, THREE.FloatType); t.needsUpdate = true; return t; })() }, uTrailN: { value: 2 }, uBeatG: { value: 0 }, uRip: { value: [0, 1, 2, 3].map(() => new THREE.Vector4(0, 0, -99, 0)) }, uLabA: { value: new THREE.Vector4(1, 1.037, 1, 1) }, uLabB: { value: new THREE.Vector4(1, 1, 1, 1) }, uTime: { value: 0 }, uBoard: { value: new THREE.Vector2() }, fogColor: { value: new THREE.Color(0.35, 0.05, 0.45) }, fogDensity: { value: 0.001 } };          // (Godot's exponential fog, shared with the custom shaders: 1 - exp(-density * distance) toward the fog colour, in linear light, before the tonemap)
const WFX = createWorldFx({ THREE, scene, camera, U });
const GROUNDSRC = Q.get('ground') || 'snow';          // DEFAULT back to the natural terrain (the freezes started when Godot's own ground, ?ground=psy, became the default; its graphics cost on integrated chips is not measured yet) (grey road, grass, earth) used by the other worlds          // matrix (the default: near-black squares with sharp bright-green lines), pink (the psychedelic world's purple, pink and gold), psy (the old colourful interference field)
const PALS = { matrix: { a: [0, .07, .03], b: [0, .015, .005], line: [.1, 1, .3], mix: .95 }, pink: { a: [.30, .08, .55], b: [.95, .50, 1], line: [1, .9, .3], mix: .85 } };   // Themes.ground_pal
function setGroundPal() { const P = PALS[GROUNDSRC]; if (!P) return; const G = WFX.uniforms.ground; G.w_a.value.set(...P.a); G.w_b.value.set(...P.b); G.w_line.value.set(...P.line); G.w_mix.value = P.mix; }
setGroundPal();
const FOGF = 'float fd = distance(wp, cameraPosition); col = mix(col, fogColor, 1. - exp(-fogDensity * fd));';
const rgb = (a, srgb = true) => new THREE.Color().setRGB(a[0], a[1], a[2], srgb ? THREE.SRGBColorSpace : THREE.LinearSRGBColorSpace);
const mat4 = (x) => new THREE.Matrix4().set(x[0], x[3], x[6], x[9], x[1], x[4], x[7], x[10], x[2], x[5], x[8], x[11], 0, 0, 0, 1);          // dump: basis columns x,y,z then origin

// ---------------------------------------------------------------- the Godot shaders, ported (shader hash -> material)
const GLSL_HSV = `vec3 hsv(float h, float s, float v){ vec3 k = vec3(1., 2./3., 1./3.); vec3 p = abs(fract(vec3(h) + k) * 6. - 3.); return v * mix(vec3(1.), clamp(p - 1., 0., 1.), s); }
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }`;
const TAIL = `
#include <tonemapping_fragment>
#include <colorspace_fragment>
`;
let EDGE_UPD = null, MINUP = null;          // (set below: the path-edge ribbons and the minimal readout)
const CHILL = Q.has('chill');          // the chill-out level: the comedown on its own (Moodless Refrain), slow and soft; ?chill
const BEATFX = { k: Q.has('nobeat') ? 0 : (CHILL ? .5 : 1), pulse: 0, bar: 0, fov: 1, exp: parseFloat(Q.get('exp') || '1.05') };          // the music's beat drives the picture (kick pulse on every beat, a bigger one on the bar line); ?nobeat turns it off
const GMATS = []; let GSPEED = 0; const TOUCHDEV = matchMedia('(pointer: coarse)').matches; const TOUCHLOOK = TOUCHDEV || !Q.has('truedesk');          /* ONE PROFILE: the mobile one (narrower field of view, mobile camera feel, tap to start, gentle window effect) is used on every device, so a demo on a PC shows exactly what the phone shows. &truedesk gives a desktop its own wide view */ const CAMD = { dx: 0, dz: -1, x: 0, y: 0, z: 0, init: false, fp: Q.get('cam') === 'old', mode: Q.get('cam') || 'fp', lx: 0, lz: -1, dy: 0, ldone: false }; const _look = new THREE.Vector3();
function groundMat(params) {          // GROUND_PSY (Themes.gd): two grids of squares, the second 3.7% finer and turning about the board, coloured by how far in step they are
  const gm = new THREE.ShaderMaterial({
    uniforms: { uRip: U.uRip, uLabA: U.uLabA, uTime: U.uTime, gcen: U.uBoard, fogColor: U.fogColor, fogDensity: U.fogDensity, speed: { value: params.speed || 0 } }, side: THREE.DoubleSide,
    vertexShader: 'varying vec3 wp; varying vec3 vC; attribute vec3 color; void main(){ wp = (modelMatrix * vec4(position,1.)).xyz; vC = color; gl_Position = projectionMatrix * viewMatrix * vec4(wp,1.); }',
    fragmentShader: `uniform float uTime, speed, fogDensity; uniform vec4 uLabA; uniform vec3 fogColor; uniform vec2 gcen; uniform vec4 uRip[4]; varying vec3 wp; ${S2L_GLSL}
${GLSL_HSV}
      void main(){ float dist = distance(wp, cameraPosition); float sc = uLabA.x / 6.;
        vec2 wq = wp.xz; float rb = 0., rm = 0.;          // RIPPLES: a wave rolls out through the snow from the board on every beat (and, purple and tighter, while the magnet is on); it bends the squares, shifts their hue and lifts their light
        for (int i = 0; i < 4; i++) { vec4 R = uRip[i]; float age = uTime - R.z; if (age < 0. || age > 3.4 || R.w == 0.) continue; vec2 dv = wp.xz - R.xy; float d = length(dv); bool mg = R.w < 0.; float r = age * (mg ? 34. : 52.); float wd = mg ? 5. : 11.; float w = exp(-pow((d - r) / wd, 2.)) * (1. - age / 3.4) * abs(R.w) * smoothstep(10., 34., r) * (1. - smoothstep(120., 260., d)); wq += dv / max(d, .001) * w * (mg ? 1.4 : 2.4); if (mg) rm += w; else rb += w; }
        vec2 g1 = wq * sc; float grid1 = sin(g1.x * 6.283) * sin(g1.y * 6.283);
        float t = uTime * .15 * .3 * uLabA.z, ca = cos(t), sa = sin(t); vec2 rp = wq - gcen; vec2 g2 = vec2(rp.x * ca - rp.y * sa, rp.x * sa + rp.y * ca) * sc * uLabA.y; float grid2 = sin(g2.x * 6.283) * sin(g2.y * 6.283);
        float far = 1. - smoothstep(130., 340., dist); float amp = mix(.5, grid1 * grid2 * .5 + .5, far); float sq = mix(.5, smoothstep(-.06, .06, grid1), far);
        vec3 col = hsv(fract(amp * .5 + uTime * .03), clamp(.9 * uLabA.w, 0., 1.), .25 + .75 * pow(amp, .65)) * (.62 + .38 * sq); col = hsv(fract(amp * .5 + uTime * .03 + rb * .12), clamp(.9 * uLabA.w, 0., 1.), .25 + .75 * pow(amp, .65)) * (.62 + .38 * sq); col *= (.75 + .25 * speed) * (1. + rb * .45); col = mix(col, vec3(.75, .35, 1.) * (.5 + .9 * amp), clamp(rm * .9, 0., .85)); col += vec3(.35, .12, .6) * rm;
        col = ${Q.has('nos2l') ? 'col * col' : 's2l(col * col)'}; ${FOGF} gl_FragColor = vec4(col, 1.); ${TAIL} }`,
  });
  GMATS.push(gm); return gm;
}

// ---- TERRAIN: the floor as natural ground. A dark grey road with white lines (centre dashes, solid edges) and a gravel shoulder; beside it snow, grass and bare earth, chosen by the slope (steep = earth, so ramps and rollers show earth and grass like a real hillside), by big soft patches, and by the REGION of the course (pines, fever, dusk, blossom, under, ember), blended across each row boundary, so colour and pattern change as you go. Quiet by design: only the targets shout. The mountains keep their moire. ?ground=psy brings the old two-grid floor back; ?roadc= (hex) overrides the road colour; ?roadw= the road's half width.
const GROUND_SIGS = ['ALBEDO = c * 0.4', 'frosting', 'dunes in flat bands', 'chevrons racing', 'flat poster colours', 'a drop runs down each column', 'A REGULAR LATTICE', 'uniform float grid'];          // each biome's ground shader (the same list the level splitter uses)
const REGION_NAMES = ['pines', 'fever', 'dusk', 'blossom', 'under', 'ember'];
const hexRGB = (h) => { const n = parseInt(String(h), 16) || 0; return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]; };
// the biomes' road and ground styles (Themes.gd's own patterns, kept dark and quiet): style 0 = natural terrain by region (alpine, psychedelic), 1 candy frosting, 2 egypt dunes, 3 tunnel chevrons, 4 desert poster bands, 5 matrix code rain, 6 synthwave lattice. Road: its colour, the colour of its lines, and how much the lines glow.
const BIOME_GROUND = { alpine: { style: 0, road: [.26, .28, .32], line: [.93, .93, .90], glow: 0 }, psychedelic: { style: 0, road: null, line: [.93, .93, .90], glow: 0 }, candy: { style: 1, road: [.36, .20, .26], line: [1., .95, .90], glow: 0 }, egypt: { style: 2, road: [.42, .31, .22], line: [.96, .90, .70], glow: 0 }, tunnel: { style: 3, road: [.05, .04, .10], line: [.20, .90, 1.], glow: .8 }, desert: { style: 4, road: [.26, .25, .27], line: [.97, .95, .90], glow: 0 }, matrix: { style: 5, road: [0., .03, .01], line: [.10, 1., .30], glow: .8 }, synthwave: { style: 6, road: [.06, .02, .12], line: [1., .20, .70], glow: .8 } };
function snowMat(params) {
  const open = (lvl.feat_off || 15) < 10 ? 13 : 25, rc = Q.get('roadc'), BG = BIOME_GROUND[Q.get('theme') || lvl.theme || 'psychedelic'] || BIOME_GROUND.psychedelic;
  const sm = new THREE.ShaderMaterial({
    uniforms: { uSkirt: { value: params.skirt ? 1 : 0 }, uRip: U.uRip, uTime: U.uTime, uTrail: U.uTrail, uTrailN: U.uTrailN, uRegion: U.uRegion, uRegN: U.uRegN, fogColor: U.fogColor, fogDensity: U.fogDensity, speed: { value: params.speed || 0 }, uOpen: { value: open }, uRoadHalf: { value: parseFloat(Q.get('roadw') || (open < 20 ? '6' : '11')) }, uRoadOver: { value: rc ? new THREE.Vector4(...hexRGB(rc), 1) : (BG.road ? new THREE.Vector4(BG.road[0], BG.road[1], BG.road[2], 1) : new THREE.Vector4(0, 0, 0, 0)) }, uStyle: { value: BG.style }, uDirt: { value: sp('dirt', ({ alpine: 1 })[Q.get('theme') || 'psychedelic'] || 0) }, uLineC: { value: new THREE.Vector3(...BG.line) }, uGlow: { value: BG.glow }, uBeat: U.uBeatG }, side: THREE.DoubleSide,
    vertexShader: 'varying vec3 wp; void main(){ wp = (modelMatrix * vec4(position,1.)).xyz; gl_Position = projectionMatrix * viewMatrix * vec4(wp,1.); }',
    fragmentShader: `uniform float uTime, speed, fogDensity, uRoadHalf, uTrailN, uRegN, uOpen, uStyle, uGlow, uBeat, uSkirt, uDirt; uniform vec3 fogColor, uLineC; uniform vec4 uRip[4], uRoadOver; uniform highp sampler2D uTrail, uRegion; varying vec3 wp; ${S2L_GLSL}
      ${GLSL_HSV}
      const vec3 SN[6] = vec3[6](vec3(.88,.92,.98), vec3(.90,.85,.78), vec3(.72,.78,.95), vec3(.95,.88,.92), vec3(.55,.60,.70), vec3(.55,.50,.50));
      const vec3 GR[6] = vec3[6](vec3(.30,.46,.27), vec3(.55,.50,.24), vec3(.24,.33,.36), vec3(.36,.58,.30), vec3(.19,.30,.27), vec3(.25,.22,.20));
      const vec3 EA[6] = vec3[6](vec3(.40,.32,.25), vec3(.62,.38,.20), vec3(.36,.29,.34), vec3(.45,.33,.27), vec3(.22,.19,.22), vec3(.33,.18,.14));
      const vec3 RD[6] = vec3[6](vec3(.26,.28,.32), vec3(.36,.31,.27), vec3(.24,.25,.33), vec3(.30,.30,.32), vec3(.17,.17,.21), vec3(.21,.18,.18));
      const float SK[6] = float[6](.9, .15, .55, .25, .1, 0.);
      float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f); return mix(mix(h21(i), h21(i + vec2(1., 0.)), f.x), mix(h21(i + vec2(0., 1.)), h21(i + vec2(1., 1.)), f.x), f.y); }
      float fbm3(vec2 p){ return .5 * vn(p) + .3 * vn(p * 2.03 + 7.1) + .2 * vn(p * 4.1 + 3.3); }
      vec3 candyc(float h){ h = fract(h) * 6.; if (h < 1.) return vec3(1., .45, .72); if (h < 2.) return vec3(.5, .95, .8); if (h < 3.) return vec3(.72, .55, 1.); if (h < 4.) return vec3(1., .72, .45); if (h < 5.) return vec3(.5, .78, 1.); return vec3(1., .9, .5); }
      float trailAt(float z){ float i = clamp(-z / 6., 0., uTrailN - 2.); int a = int(i); float x0 = texelFetch(uTrail, ivec2(a, 0), 0).r, x1 = texelFetch(uTrail, ivec2(a + 1, 0), 0).r; return mix(x0, x1, fract(i)); }
      void main(){ float dist = distance(wp, cameraPosition);
        vec3 n0 = normalize(cross(dFdx(wp), dFdy(wp))); if (n0.y < 0.) n0 = -n0; vec3 n = normalize(mix(n0, vec3(0., 1., 0.), .5)); float slope = 1. - n0.y + (vn(wp.xz * .35) - .5) * .07, lam = clamp(dot(n, normalize(vec3(-.35, .8, -.45))), 0., 1.), lit = .52 + .62 * lam;
        float off = wp.x - trailAt(wp.z), ao = abs(off), far = smoothstep(50., 200., dist);
        vec3 ground, ea = vec3(.4, .32, .25), rd = vec3(.26, .28, .32); float snowK = 0., forest = 0.;
        if (uStyle < .5) {
          float jf = max(-wp.z, 0.) / 180.; int j0 = int(min(jf, uRegN - 1.)), j1 = int(min(float(j0) + 1., uRegN - 1.)); float tr = smoothstep(.75, 1., fract(jf));
          int r0 = clamp(int(texelFetch(uRegion, ivec2(j0, 0), 0).r + .5), 0, 5), r1 = clamp(int(texelFetch(uRegion, ivec2(j1, 0), 0).r + .5), 0, 5);
          vec3 sn = mix(SN[r0], SN[r1], tr), gr = mix(GR[r0], GR[r1], tr); ea = mix(EA[r0], EA[r1], tr); rd = mix(RD[r0], RD[r1], tr); float sk = mix(SK[r0], SK[r1], tr);
          float big = fbm3(wp.xz * .035), mid = vn(wp.xz * .22), fine = mix(vn(vec2(wp.x * 1.7, wp.z * .55)), .5, far);
          float earthK = clamp(smoothstep(.10, .26, slope) + smoothstep(.62, .8, mid + (big - .5)) * .45, 0., 1.); snowK = sk * smoothstep(.42, .62, big + (mid - .5) * .25) * (1. - smoothstep(.06, .2, slope));
          ground = mix(gr * (.82 + .36 * fine), ea * (.85 + .3 * mid), earthK); vec3 snt = sn * (.82 + .28 * mid) * mix(vec3(.88, .93, 1.12), vec3(1.07, .97, .93), big); snt *= .92 + .08 * (.5 + .5 * sin(wp.x * .9 + vn(wp.xz * .35) * 7.)); snt *= .93 + .12 * fine; snt = min(snt, vec3(.9, .9, .94)); ground = mix(ground, snt, snowK); ground *= lit;
          forest = smoothstep(uOpen - 3., uOpen + 5., ao); ground = mix(ground, ea * .45, forest * .5) * mix(1., .6, forest);
        } else if (uStyle < 1.5) {          // candy: swirled frosting bands and sprinkles
          float rip = .5 + .5 * sin(wp.x * .13 + sin(wp.z * .035) * 3. + sin(wp.x * .04) * 2.), band = floor(rip * 3.); vec3 fr = band < 1. ? vec3(1., .62, .80) : (band < 2. ? vec3(.98, .88, .84) : vec3(.66, .92, .84));
          vec2 cc = floor(wp.xz * .8); float hh = h21(cc), ang = hh * 6.2831, ca_ = cos(ang), sa_ = sin(ang); vec2 l = fract(wp.xz * .8) - .5; l = vec2(ca_ * l.x + sa_ * l.y, -sa_ * l.x + ca_ * l.y);
          float spr = step(.8, hh) * step(abs(l.x), .34) * step(abs(l.y), .10) * (1. - far); ground = mix(fr, candyc(hh * 7.3), spr) * (.8 + .28 * lam); ea = vec3(.98, .88, .84); ground *= ground;
        } else if (uStyle < 2.5) {          // egypt: dunes in flat bands, a few dark dashes, a little grain
          float rip = .5 + .5 * sin(wp.x * .22 + sin(wp.z * .045) * 3.2 + sin(wp.x * .05) * 2.), band = floor(rip * 3.) / 3.; vec3 sand = mix(vec3(.72, .46, .22), vec3(.92, .70, .38), band);
          float dash = step(.93, h21(floor(vec2(wp.x * .5, wp.z * .12)))) * step(.5, fract(wp.z * .12 + .2)) * .5 * (1. - far); sand = mix(sand, vec3(.42, .22, .10), dash); sand *= .96 + .06 * h21(floor(wp.xz * 3.)) * (1. - far);
          ground = sand * (.72 + .45 * lam); ea = vec3(.62, .42, .22); ground *= ground;
        } else if (uStyle < 3.5) {          // tunnel: a dark floor with thin neon chevrons racing toward you
          float ch = ao * .16 + wp.z * .045, id = floor(ch), f = fract(ch), line = smoothstep(0., .05, f) * (1. - smoothstep(.1, .18, f)); vec3 neon = hsv(fract(id * .17 + .55), .9, 1.);
          ground = vec3(.03, .02, .08) + .05 * hsv(fract(id * .17 + .55), 1., 1.) + neon * line * .4 * (1. - far * .6); ea = vec3(.04, .03, .10); ground *= ground;
        } else if (uStyle < 4.5) {          // desert: flat poster bands of sand, rust and teal, each ringed by a thin dark contour
          float nn = sin(wp.x * .05 + sin(wp.z * .02) * 2.) + sin(wp.z * .03 + wp.x * .02) + .5 * sin(wp.z * .11 - wp.x * .04), k = fract(nn * .35 + .5); vec3 c = k < .45 ? vec3(.92, .52, .40) : (k < .8 ? vec3(.66, .22, .24) : vec3(.22, .42, .42));
          float edge = 1. - smoothstep(0., .025, min(abs(k - .45), min(abs(k - .8), min(k, 1. - k)))); c = mix(c, vec3(.15, .04, .08), edge * .8 * (1. - far)); ground = c * (.55 + .5 * lam); ea = vec3(.6, .3, .25); ground *= ground;
        } else if (uStyle < 5.5) {          // matrix: a dark grid with code falling down each column
          vec2 g = wp.xz / 3.2, id = floor(g), f = fract(g); float spd = .35 + h21(vec2(id.x, 3.)) * .8, t = fract(h21(vec2(id.x, 9.)) + id.y * .071 + uTime * spd * .35), trail = pow(1. - t, 3.), head = 1. - smoothstep(0., .06, t);
          vec2 px = floor(f * vec2(3., 5.)); float glyph = step(.45, h21(px + id * 3.1 + floor(uTime * 1.5 + h21(id) * 7.))), inside = step(.12, f.x) * step(f.x, .88) * step(.1, f.y) * step(f.y, .9), lines = max(1. - smoothstep(0., .03, f.x), 1. - smoothstep(0., .03, f.y));
          ground = vec3(0., .015, .005) + vec3(0., .07, .03) * lines + vec3(.1, 1., .3) * glyph * inside * trail * .4 * (1. - far) + vec3(.7, 1., .8) * glyph * inside * head * .6 * (1. - far); ea = vec3(0., .04, .015); ground *= ground;
        } else {          // synthwave: a regular neon lattice, alternate squares light and dark
          vec2 g = wp.xz / 3., f = abs(fract(g) - .5); float w = .05 + .0016 * dist, line = max(smoothstep(.5 - w, .5, f.x), smoothstep(.5 - w, .5, f.y)), chk = step(0., sin(g.x * 3.14159) * sin(g.y * 3.14159)), pulse = .75 + .25 * sin(wp.z * .05 - uTime * 2.);
          vec3 neon = mix(vec3(1., .1, .65), vec3(.15, .85, 1.), .5 + .5 * sin(wp.x * .02 + uTime * .3)); ground = vec3(.03, 0., .07) + vec3(.07, .02, .14) * chk + neon * line * pulse * .55; ea = vec3(.05, 0., .10); ground *= ground;
        }
        ground *= (.84 + .32 * vn(wp.xz * .017)) * (.92 + .16 * vn(wp.xz * .09 + 7.));          // broad light and dark drifts, so large slopes are never one tone
        if (uSkirt > .5) {          // the terrain skirt, the steep walls around the course: strata by height, a moire hatch, colour that drifts, so a wall is never one tone
          float st_ = wp.y * .06 + vn(wp.xz * .01) * 3., bd_ = .5 + .5 * sin(st_ * 6.2831 + sin(wp.x * .02 + wp.z * .015) * 3.), ht_ = .5 + .5 * sin((wp.x + wp.z) * .35 + wp.y * .5) * sin((wp.x - wp.z) * .3 - wp.y * .45);
          vec3 hu_ = hsv(fract(.78 + bd_ * .18 + wp.y * .0012 + uTime * .01), .8, .8); ground = mix(ground, hu_ * (.5 + .5 * bd_) * (.7 + .4 * ht_), .85) * lit; }
        if (uRoadOver.w > 0.) rd = uRoadOver.rgb;
        float rj_ = uDirt * (vn(wp.xz * vec2(.45, .3)) - .5) * 2.6; float road = 1. - smoothstep(uRoadHalf - .4 + rj_, uRoadHalf + .4 + rj_, ao), shoulder = (1. - smoothstep(uRoadHalf, uRoadHalf + 2.2, ao)) * (1. - road);
        vec3 roadc = rd * (.9 + .2 * vn(wp.xz * vec2(2.2, 1.))) * (.7 + .5 * lam);
        if (uDirt > .5) { // DIRT ROAD (Alps): packed earth, two worn wheel ruts, a lighter crown down the middle, scattered stones, dust and damp patches. A few hashes, faded with distance.
          float nr_ = 1. - smoothstep(22., 130., dist), gr_ = .5 * vn(wp.xz * vec2(17., 15.)) + .5 * vn(wp.xz * vec2(43., 37.)), rut_ = exp(-pow((ao - uRoadHalf * .34) / (uRoadHalf * .12), 2.)), crown_ = exp(-pow(ao / (uRoadHalf * .1), 2.)), st_ = step(.955, h21(floor(wp.xz * vec2(21., 19.)) + 5.)), dust_ = vn(wp.xz * vec2(.11, .07)), damp_ = smoothstep(.62, .85, vn(wp.xz * vec2(.05, .09) + 3.));
          vec3 dc_ = mix(vec3(.36, .22, .12), vec3(.56, .38, .22), gr_); dc_ *= (1. - .30 * rut_ - .22 * damp_) * (1. + .16 * crown_) * (.88 + .24 * dust_); dc_ += vec3(.16, .14, .12) * st_ * nr_; roadc = dc_ * (.75 + .5 * lam); } else { // ASPHALT: fine grain and pale aggregate near the camera, worn tyre tracks, slow patches of lighter and darker repair, and the odd hairline crack. Cheap (a few hashes), faded with distance so nothing shimmers
          float nr_ = 1. - smoothstep(22., 130., dist), gr_ = .5 * vn(wp.xz * vec2(21., 19.)) + .5 * vn(wp.xz * vec2(47., 41.)), sp_ = step(.94, h21(floor(wp.xz * vec2(26., 23.)) + 17.)), wr_ = exp(-pow((ao - uRoadHalf * .36) / (uRoadHalf * .13), 2.)) + .6 * exp(-pow(ao / (uRoadHalf * .12), 2.));
          float pt_ = .86 + .28 * vn(wp.xz * vec2(.13, .06)) + .08 * vn(wp.xz * vec2(.9, .5)), cr_ = abs(fract(wp.x * .31 + sin(wp.z * .17) * .7) - .5), ck_ = (1. - smoothstep(0., .008 + .012 * (1. - nr_), cr_)) * step(.93, h21(floor(vec2(wp.x * .31, wp.z * .045)))) * (1. - smoothstep(.0, 1., abs(vn(wp.xz * .5) - .5) * 3.));
          roadc *= pt_ * (1. - .20 * wr_) * (.84 + .26 * gr_ * nr_ + .1 * (1. - nr_)); roadc += vec3(.07) * sp_ * nr_; roadc = mix(roadc, roadc * .55, ck_ * (.4 + .6 * nr_)); }
        vec3 col = mix(ground, ea * .75 * lit, shoulder * .65); col = mix(col, roadc, road);
        float fw = fwidth(off) + 1e-4, edgeL = (1. - smoothstep(.10, .10 + fw, abs(ao - (uRoadHalf - .7)))) * step(ao, uRoadHalf), dash = step(fract(wp.z / 9.), .5), cl = (1. - smoothstep(.09, .09 + fw, ao)) * dash;
        float lineK = max(edgeL, cl) * road * (1. - smoothstep(.3, .9, fw)) * (1. - uDirt); col = mix(col, uLineC * (1. + uGlow * (.9 + .6 * uBeat)), lineK * .92);
        vec2 sc = wp.xz * 1.8, fc = fract(sc) - .5; float hh2 = h21(floor(sc)); float spk = step(.985, hh2) * (.55 + .45 * sin(uTime * 2.5 + hh2 * 80.)) * (1. - smoothstep(.05, .3, length(fc))) * (1. - smoothstep(18., 80., dist)) * snowK; col += vec3(.9, .95, 1.) * spk * .7;
        float rb = 0., rm = 0.; for (int i = 0; i < 4; i++) { vec4 R = uRip[i]; float age = uTime - R.z; if (age < 0. || age > 3.4 || R.w == 0.) continue; vec2 dv = wp.xz - R.xy; float d = length(dv); bool mg = R.w < 0.; float r = age * (mg ? 34. : 52.); float wd = mg ? 5. : 11.; float w = exp(-pow((d - r) / wd, 2.)) * (1. - age / 3.4) * abs(R.w) * smoothstep(10., 34., r) * (1. - smoothstep(120., 260., d)); if (mg) rm += w; else rb += w; }
        col += vec3(.2, .18, .3) * rb; col = mix(col, vec3(.75, .45, 1.), clamp(rm * .8, 0., .7));
        col *= .95 + .05 * speed; col = s2l(col); ${FOGF} gl_FragColor = vec4(col, 1.); ${TAIL} }`,
  });
  GMATS.push(sm); return sm;
}
function trailTexInit() {
  if (U.uTrailDone || typeof TX === 'undefined' || !TX || !TX.length) return;
  const d = Float32Array.from(TX), t = new THREE.DataTexture(d, d.length, 1, THREE.RedFormat, THREE.FloatType); t.minFilter = t.magFilter = THREE.NearestFilter; t.needsUpdate = true; U.uTrail.value = t; U.uTrailN.value = d.length;
  const nr = Math.max(1, lvl.nrows || 1), ra = new Float32Array(nr); for (let k = 0; k < nr; k++) { const rr = lvl.rows && (lvl.rows[String(k)] || lvl.rows[k]); ra[k] = Math.max(0, REGION_NAMES.indexOf(rr && rr.region)); }
  const rt = new THREE.DataTexture(ra, nr, 1, THREE.RedFormat, THREE.FloatType); rt.minFilter = rt.magFilter = THREE.NearestFilter; rt.needsUpdate = true; U.uRegion.value = rt; U.uRegN.value = nr; U.uTrailDone = true;
}
function vegMat() { return Q.has('oldveg') ? vegMatOld() : WFX.vegPsy({ labB: U.uLabB }); }          // VEG_PSY from worldfx2 (authored-space mix, one s2l, Godot fog)
function vegMatOld() {          // VEG_PSY: dark purple, neon where bright, the neon hue drifting with where it stands and with time; lit (roughness .5), so it is a standard material with the albedo and emission replaced
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5, metalness: 0, side: THREE.DoubleSide }); m.userData.veg = true;
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = U.uTime; sh.uniforms.uLabB = U.uLabB;
    sh.vertexShader = 'varying vec3 vWp;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n vec4 wpp = vec4(transformed, 1.);\n#ifdef USE_INSTANCING\n wpp = instanceMatrix * wpp;\n#endif\n vWp = (modelMatrix * wpp).xyz;');
    sh.fragmentShader = 'varying vec3 vWp; uniform float uTime; uniform vec4 uLabB;\n' + GLSL_HSV + '\n' + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        float lum = dot(vColor.rgb, vec3(.34)); float hue = fract(vWp.z * .012 + vWp.x * .007 + uTime * .07 * uLabB.x + lum * .2); vec3 neon = hsv(hue, .85, 1.);
        diffuseColor.rgb = mix(vec3(.03, 0., .06), neon * .75, smoothstep(.1, .9, lum));`)
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance += neon * smoothstep(.35, 1., lum) * .75 * uLabB.y;');
  };
  return m;
}
function skyMat() { return Q.has('oldsky') ? skyMatOld() : WFX.skyPsy(); }
function skyMatOld() {          // SKY_PSY
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime }, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: 'varying vec3 vD; void main(){ vD = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p.xyww; }',
    fragmentShader: `uniform float uTime; varying vec3 vD; vec3 pal(float t){ return .5 + .5 * cos(6.28318 * (t + vec3(0., .33, .67))); }
      void main(){ vec3 d = normalize(vD); float az = atan(d.x, -d.z); float band = .5 + .5 * sin(az * 2. + d.y * 5. + sin(d.y * 3. + uTime * .15) * 1.2 + uTime * .05);
        vec3 col = pal(d.y * .5 + az * .08 + uTime * .02) * (.05 + .20 * band * smoothstep(0., .6, d.y)); col += vec3(.02, 0., .06); float horizon = smoothstep(-.1, .3, d.y);
        gl_FragColor = vec4(mix(vec3(.10, .01, .16), col, horizon), 1.); ${TAIL} }` });
}
function backdropMat(params) {          // the distant backdrop with the HORIZON BEND (past 140 m the world curls up with the square of the distance)
  return new THREE.ShaderMaterial({ uniforms: { fogColor: U.fogColor, fogDensity: U.fogDensity, albedo: { value: rgb(params.albedo_color || [1, 1, 1], true) }, bend_k: { value: params.bend_k || 0 } }, side: THREE.DoubleSide,
    vertexShader: 'attribute vec3 color; varying vec3 vC; varying vec3 wp; uniform float bend_k; void main(){ vC = color; vec4 w = modelMatrix * vec4(position, 1.); wp = w.xyz; float bd = max(length(w.xz - cameraPosition.xz) - 140., 0.); w.y += bend_k * bd * bd; gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: `uniform vec3 albedo, fogColor; uniform float fogDensity; varying vec3 wp; varying vec3 vC; void main(){ vec3 col = vC * albedo; { float lm = dot(col, vec3(.299, .587, .114)), mx = max(col.r, max(col.g, col.b)), mn = min(col.r, min(col.g, col.b)), sat = (mx - mn) / max(mx, .001); col = mix(col, vec3(.10, .03, .20) + col * .3, smoothstep(.4, .7, lm) * (1. - smoothstep(.3, .65, sat))); }          /* no white: a pale, colourless backdrop is pulled down to the dark purple of the world */ ${FOGF} gl_FragColor = vec4(col, 1.); ${TAIL} }` });
}
function quadMat(code, params) {          // the soft additive glow quads and the tint gradient
  const add = code.includes('blend_add');
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime, dose: { value: params.dose || 0 }, tint: { value: (() => { const t = params.tint || [.93, .96, 1, .97], l = (c) => (c <= .04045 ? c / 12.92 : Math.pow((c + .055) / 1.055, 2.4)); return new THREE.Vector4(l(t[0]), l(t[1]), l(t[2]), t[3]); })() } }, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: add ? THREE.AdditiveBlending : THREE.NormalBlending,
    vertexShader: ['varying vec2 vUv;', 'void main(){ vUv = uv;', '#ifdef USE_INSTANCING', ' vec4 p = instanceMatrix * vec4(position, 1.);', '#else', ' vec4 p = vec4(position, 1.);', '#endif', ' gl_Position = projectionMatrix * viewMatrix * modelMatrix * p; }'].join(String.fromCharCode(10)),
    fragmentShader: add
      ? 'uniform float uTime, dose; varying vec2 vUv; void main(){ float e = smoothstep(0., .4, vUv.x) * (1. - smoothstep(.6, 1., vUv.x)); float v = (1. - smoothstep(.7, 1., vUv.y)) * smoothstep(0., .55, vUv.y); float sh = .75 + .25 * sin(vUv.x * 23. + uTime * .7) * sin(vUv.x * 7. - uTime * .4); vec3 rb = .5 + .5 * cos(6.2831 * (vUv.y * 1.5 + uTime * .15 + vec3(0., .33, .67))); gl_FragColor = vec4(mix(vec3(.6, .5, 1.), rb, clamp(dose * 1.4, 0., .85)), e * v * sh * (1. + dose * 1.6) * .6); }'
      : 'uniform vec4 tint; varying vec2 vUv; void main(){ gl_FragColor = vec4(tint.rgb, tint.a * smoothstep(.22, .62, vUv.y)); }' });
}

function glowMat(d) {
  const a = d.albedo, tex = !!d.tex, bb = d.billboard === 1;
  return new THREE.ShaderMaterial({ uniforms: { col: { value: new THREE.Vector4(a[0], a[1], a[2], a[3] * (tex ? 1 : .28)) } }, transparent: true, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; ${bb ? 'vec3 o = modelMatrix[3].xyz; vec2 sc = vec2(length(modelMatrix[0].xyz), length(modelMatrix[1].xyz)); vec4 mv = viewMatrix * vec4(o, 1.) + vec4(position.xy * sc, 0., 0.); gl_Position = projectionMatrix * mv;' : 'gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.);'} }`,
    fragmentShader: `uniform vec4 col; varying vec2 vUv; void main(){ float k = 1.; ${tex ? 'float r = clamp(length(vUv - .5) * 2., 0., 1.); k = r < .3 ? mix(1., .4, r / .3) : mix(.4, 0., (r - .3) / .7);' : 'k = 1. - smoothstep(.35, .5, length(vUv - .5) * 1.0);'} gl_FragColor = vec4(col.rgb, col.a * k); }` });
}
// ---------------------------------------------------------------- load
const LD = document.createElement('div'); LD.style.cssText = 'position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:#10041a;z-index:30;color:#fff;font:700 20px ui-monospace,Consolas,monospace'; LD.innerHTML = '<div id="ldt">loading the level...</div><div style="width:min(70vw,360px);height:10px;margin-top:14px;border:1px solid #fff8;border-radius:6px;overflow:hidden"><div id="ldb" style="height:100%;width:0;background:linear-gradient(90deg,#f0f,#0ff)"></div></div>'; document.body.appendChild(LD);
const showErr = (m) => { const l = document.getElementById('ldt'); if (l) { l.style.color = '#f88'; l.style.fontSize = '14px'; l.style.maxWidth = '90vw'; l.style.wordBreak = 'break-word'; l.textContent = 'could not start: ' + m; } };
addEventListener('error', (e) => showErr((e.message || 'error') + ' ' + (e.filename ? e.filename.split('/').pop() + ':' + e.lineno : ''))); addEventListener('unhandledrejection', (e) => showErr(String((e.reason && (e.reason.stack || e.reason.message)) || e.reason).slice(0, 300)));
const setLoad = (f, t) => { const b = document.getElementById('ldb'), l = document.getElementById('ldt'); if (b) b.style.width = Math.round(Math.max(0, Math.min(1, f)) * 100) + '%'; if (l && t) l.textContent = t; };
async function fetchJson(url, f0, f1, label) {          // streamed so the bar can move
  const r = await fetch(url, { cache: 'no-cache' }); const tot = +r.headers.get('content-length') || 5e6; const rd = r.body.getReader(); const parts = []; let got = 0;
  for (;;) { const { done, value } = await rd.read(); if (done) break; parts.push(value); got += value.length; setLoad(f0 + Math.min(1, got / tot) * (f1 - f0), label + '  ' + (got / 1e6).toFixed(1) + ' MB'); }
  const all = new Uint8Array(got); let o = 0; for (const c of parts) { all.set(c, o); o += c.length; } await new Promise((r2) => setTimeout(r2, 30)); return JSON.parse(new TextDecoder().decode(all));
}
const lvl = await (async () => {
  if (!STREAM) return fetchJson('./data/' + LVL + '.json', 0, .45, 'downloading the level');
  window.__dm && window.__dm('level: fetching meta'); const meta = await fetchJson(LVLDIR + 'meta.json', 0, .25, 'the level\u2019s shape'), phys = await fetchJson(LVLDIR + 'physics.json', .25, .4, 'where everything is');
  const L = Object.assign({}, meta); L.stream = true; L.metaNodes = meta.nodes; L.rows = phys.rows; L.vx = phys.vx; L.kickers = phys.kickers; L.anims = phys.anims; L.nodes = meta.nodes.concat(phys.nodes); return L;          // (the slim nodes are only for looking things up by name: their meshes come with their row)
})();
const WORLD_THEME = Q.get('theme') || lvl.theme || 'psychedelic';
const THEME_PK = ({ psychedelic: 1, tunnel: 1 })[Q.get('theme') || lvl.theme || 'psychedelic'] || 0;          // Godot's Themes.post_mode: only the trippy worlds get the trip picture pass (matrix and synthwave have their own passes, not ported yet)
hud.textContent = 'building ' + lvl.nodes.length + ' nodes, ' + Object.keys(lvl.meshes).length + ' meshes...';
await new Promise((r) => setTimeout(r, 30));
const MAT = {}, GEO = {};
const matOf = (id) => {
  if (!id) return null; if (MAT[id]) return MAT[id]; const d = lvl.materials[id]; let m;
  if (d.class === 'ShaderMaterial') {
    const code = d.shader_code || '', p = d.params || {};
    const THEME_ID = Q.get('theme') || lvl.theme || 'psychedelic';
    const rm = realmMaterial(code, p, U, WFX.face);
    if (rm) m = rm;
    else if (code.includes('GROUND') || code.includes('MOIRE INTERFERENCE') || GROUND_SIGS.some((sg) => code.includes(sg))) m = (GROUNDSRC === 'snow' || THEME_ID !== 'psychedelic') ? snowMat(p) : ((GROUNDSRC === 'psy') ? groundMat(p) : WFX.ground());
    else if (code.includes('HORIZON BEND')) m = backdropMat(p);
    else if (code.includes('shader_type sky')) m = (THEME_ID !== 'psychedelic' && skyBiome(THEME_ID, U)) || skyMat();
    else if (code.includes('float hue = fract(wp.z * 0.012')) m = vegMat();
    else if (THEME_ID !== 'psychedelic' && /dot\(COLOR\.rgb/.test(code) && vegBiome(THEME_ID, U, WFX.face)) m = vegBiome(THEME_ID, U, WFX.face);
    else if (code.includes('blend_add') || code.includes('smoothstep(0.22, 0.62, UV.y)')) m = quadMat(code, p);
    else m = new THREE.MeshBasicMaterial({ color: 0xff00ff });
  } else if (d.class === 'StandardMaterial3D') {
    if (d.unshaded && d.transparency > 0 && d.blend === 1) m = glowMat(d);          // Godot's "halo" / "ground" / "add" materials: additive, and the halo and pool carry a radial fade texture (a soft ball of light, not a square); the halo always faces the camera
    else if (d.unshaded) { m = new THREE.MeshBasicMaterial({ color: rgb(d.albedo), vertexColors: !!d.vertex_color_albedo }); if (!Q.has('noglow') && !d.vertex_color_albedo) glowify(m, { uTime: U.uTime, uBeat: U.uBeatG }); }          // the flat cream gates and bars: now they glow
    else {
      m = new THREE.MeshStandardMaterial({ color: rgb(d.albedo), roughness: d.roughness, metalness: d.metallic, vertexColors: !!d.vertex_color_albedo });
      if (d.emission_on) { m.emissive = rgb(d.emission); m.emissiveIntensity = d.emission_energy; }
      if (!d.vertex_color_albedo && !d.emission_on && !Q.has('noglow')) glowLit(m, { uTime: U.uTime, uBeat: U.uBeatG });          // lit white rocks and bumps: tinted to the world and glowing at the rim
      if (d.vertex_color_albedo && d.emission_on && Math.abs(d.roughness - .45) < .01) {          // the molecule material: rim_enabled .55, rim_tint .35 and a glossy specular, so the atoms read round
        m.metalness = .15; m.roughness = .32; m.onBeforeCompile = (sh) => { sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_begin>', String.fromCharCode(10) + '{ float rim = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.5); totalEmissiveRadiance += mix(vec3(1.), diffuseColor.rgb, .35) * rim * .75; }' + String.fromCharCode(10) + '#include <lights_fragment_begin>'); };
      }
    }
    if (!m.isShaderMaterial && (d.transparency > 0 || d.albedo[3] < 0.99)) { m.transparent = true; m.opacity = d.albedo[3]; }
    if (d.cull_mode === 2) m.side = THREE.DoubleSide; else if (d.cull_mode === 1) m.side = THREE.BackSide;
  } else m = new THREE.MeshBasicMaterial({ color: 0xff00ff });
  return (MAT[id] = m);
};
function geoOf(id) {
  if (GEO[id]) return GEO[id]; const md = lvl.meshes[id]; const out = [];
  for (const s of md.surfaces) {
    const v = s.v; if (!v || !v.length || s.prim !== 3) continue;
    const g = new THREE.BufferGeometry(), pos = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { pos[i * 3] = v[i][0]; pos[i * 3 + 1] = v[i][1]; pos[i * 3 + 2] = v[i][2]; }
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    if (s.n) { const n = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { n[i * 3] = s.n[i][0]; n[i * 3 + 1] = s.n[i][1]; n[i * 3 + 2] = s.n[i][2]; } g.setAttribute('normal', new THREE.BufferAttribute(n, 3)); } else g.computeVertexNormals();
    { const c = new Float32Array(v.length * 3); if (s.c) for (let i = 0; i < v.length; i++) { c[i * 3] = s.c[i][0]; c[i * 3 + 1] = s.c[i][1]; c[i * 3 + 2] = s.c[i][2]; } else c.fill(1); g.setAttribute('color', new THREE.BufferAttribute(c, 3)); }
    if (s.c && s.c[0] && s.c[0].length > 3) { let mn = 1, mx = 0; for (const q of s.c) { if (q[3] < mn) mn = q[3]; if (q[3] > mx) mx = q[3]; } if (mx - mn > .01) { const w = new Float32Array(v.length); for (let i = 0; i < v.length; i++) w[i] = 1 - s.c[i][3]; g.setAttribute('aW', new THREE.BufferAttribute(w, 1)); } }
    if (s.uv) { const u = new Float32Array(v.length * 2); for (let i = 0; i < v.length; i++) { u[i * 2] = s.uv[i][0]; u[i * 2 + 1] = s.uv[i][1]; } g.setAttribute('uv', new THREE.BufferAttribute(u, 2)); }
    if (s.i && s.i.length) g.setIndex(s.i);
    out.push([g, s.mat]);
  }
  return (GEO[id] = out);
}
// ancestors must be visible; only the level's own world (the rig's meshes), not the UI or the player body
let VEGSRC = null; const REGN = {}; const TREES = new Map(); const vis = {}; const ground = []; let nMesh = 0, nInst = 0;
const NODE = new THREE.Group(); scene.add(NODE);
const AN = {}; const GRP = {}; const ANIM = []; const pathOf = {}; for (const n of lvl.nodes) pathOf[n.iid] = n.path;
for (const a of (lvl.anims || [])) {          // the pickups: the root bobs, "spin" turns about its own up axis, "extra" parts tumble (RunRig._animate_buffs)
  if (a.moving) continue; for (const k of ['n', 'spin']) if (a[k] && pathOf[a[k]]) AN[pathOf[a[k]]] = { a, k };
  (a.extra || []).forEach((e, i) => { if (pathOf[e]) AN[pathOf[e]] = { a, k: 'x' + i }; });
}
const nodeByPath = {}; for (const n of lvl.nodes) nodeByPath[n.path] = n;
function groupFor(path) {          // the nearest animated ancestor (or the node itself) as a THREE.Group, created on demand with its parent chain
  if (GRP[path]) return GRP[path]; const an = AN[path]; if (!an) return null;
  const g = new THREE.Group(); g.matrixAutoUpdate = false; g.userData = { an, base: mat4(nodeByPath[path].xf) }; g.matrix.copy(g.userData.base); GRP[path] = g;
  let par = null, pp = path; while (!par && pp.lastIndexOf('/') > 0) { pp = pp.slice(0, pp.lastIndexOf('/')); par = GRP[pp] || (AN[pp] ? groupFor(pp) : null); }
  if (par) { g.matrix.copy(par.userData.base.clone().invert().multiply(g.userData.base)); g.userData.pbase = par.userData.base; par.add(g); } else NODE.add(g); ANIM.push(g); return g;
}
function animParent(path) { let pp = path; while (pp.lastIndexOf('/') > 0) { pp = pp.slice(0, pp.lastIndexOf('/')); if (AN[pp]) return groupFor(pp); } return null; }
function animTick(age) {
  for (const g of ANIM) { const { an, base } = g.userData, a = an.a, ph = a.ph, par = g.parent && g.parent.userData && g.parent.userData.base ? g.parent.userData.base : null;
    const L = par ? par.clone().invert().multiply(base) : base.clone(); const p = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3(); L.decompose(p, q, sc);
    if (an.k === 'n') p.y += par ? 0 : 0, p.y = (par ? p.y : a.y) + Math.sin(age * 2.4 + ph) * .35 - (par ? 0 : 0);
    else if (an.k === 'spin') q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), age * (a.t === 'boost' ? 2.8 : 1.7) + ph);
    else if (an.k === 'x0') q.setFromAxisAngle(new THREE.Vector3(1, 0, 0), age * 1.4 + ph); else if (an.k === 'x1') q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), age * 1.9 + ph); else if (an.k === 'x2') q.setFromAxisAngle(new THREE.Vector3(0, 0, 1), age * 2.3 + ph);
    g.matrix.compose(p, q, sc); g.matrixWorldNeedsUpdate = true; }
} let ring = null;          // the mountain ring (the 1620-vertex vertex-coloured mesh): Godot moves it with the board so it never moves against the road
const HF = createHeightfield(), GRIDLESS = [];          // ground height by lookup (a regular grid), the raycast only for meshes that are not one
let TRK = []; const OBJS = {}, GRPS = {}, ROWREC = {};
// LIGHT SHAFTS: the level's tall soft glow quads (13 m x 64 m, additive, with a shimmer) are found as the rows build. Each is made a little bigger (&shaftsize, default 1.35 wide, about 1.2 tall, grown about its foot),
// and hangs a special MOLECULE in its beam: a slowly turning molecule you fly into for a big bonus (not one of the six story molecules). &shaftmol=0 turns the molecules off.
const SHAFTS = [], SHAFTSEEN = new Map(); let SHAFTKEEP = 0;
function shaftPrep(g, mat, M) { try {
  if (!(mat.uniforms && mat.uniforms.dose && mat.blending === THREE.AdditiveBlending)) return; if (!g.boundingBox) g.computeBoundingBox(); const b = g.boundingBox, sz = b.getSize(new THREE.Vector3()); if (sz.y < 40) return;
  const k = Math.max(.5, Math.min(2.5, sp('shaftsize', 1.35))); if (!M.__grown && k !== 1) { M.__grown = true; const cx = (b.min.x + b.max.x) / 2, cz = (b.min.z + b.max.z) / 2, T1 = new THREE.Matrix4().makeTranslation(cx, b.min.y, cz), S = new THREE.Matrix4().makeScale(k, 1 + (k - 1) * .6, k), T2 = new THREE.Matrix4().makeTranslation(-cx, -b.min.y, -cz); M.multiply(T1).multiply(S).multiply(T2); }
  const c = new THREE.Vector3((b.min.x + b.max.x) / 2, b.min.y, (b.min.z + b.max.z) / 2).applyMatrix4(M), key = Math.round(c.x / 3) + ',' + Math.round(c.z / 3); let sh = SHAFTSEEN.get(key);
  if (!sh) { sh = { x: c.x, y: c.y, z: c.z, h: sz.y, i: SHAFTS.length, taken: false, mesh: null, age: 0 }; sh.keep = sp('shaftmol', 1) <= 0 || sh.i % Math.max(1, Math.round(sp('shaftmolk', 4))) === 0; if (sh.keep) sh.m = SHAFTKEEP++; SHAFTSEEN.set(key, sh); SHAFTS.push(sh); }
  if (!sh.keep) M.makeScale(0, 0, 0);          /* a ray of light means a molecule: shafts without one are not drawn */ } catch (e) { } }
function shaftStep(dt) { dt = dt || .016;
  if (sp('shaftmol', 1) <= 0 || !SHAFTS.length) return; const t = performance.now() / 1000;
  for (const s of SHAFTS) {
    if (!s.keep) continue; if (s.taken || Math.abs(s.z - PH.z) > 520) { if (s.mesh && s.mesh.visible && (s.taken || Math.abs(s.z - PH.z) > 560)) s.mesh.visible = false; continue; }
    if (!s.mesh) { const id = MOL_ORDER[((s.m || 0) * 5 + 1) % MOL_ORDER.length]; s.mesh = new THREE.Mesh(buildMolGeometry(THREE, id), moleculeMaterial(THREE)); s.mesh.scale.setScalar(2.4); s.mesh.frustumCulled = false; s.mesh.renderOrder = 7; scene.add(s.mesh); s.id = id; }
    s.mesh.visible = true; { const pr = PH.mult > 0 ? sp('pillmagr', 30) : sp('pillpull', 9), ddx = PH.x - (s.x + (s.px || 0)), ddz = PH.z - (s.z + (s.pz || 0)), dd = Math.hypot(ddx, ddz); if (dd < pr && dd > .01) { const k = Math.min(1, (dt || .016) * (1.6 + 3 * (1 - dd / pr))); s.px = (s.px || 0) + ddx * k; s.pz = (s.pz || 0) + ddz * k; } }
    const gy = groundY(s.x, s.z), base = gy === null ? s.y : gy, y = base + 5 + .5 * Math.sin(t * 2.2 + s.i); s.my = y; s.mesh.position.set(s.x + (s.px || 0), y, s.z + (s.pz || 0)); s.mesh.rotation.set(.5, t * 1.6 + s.i, .3);
    const dx = PH.x - (s.x + (s.px || 0)), dz = PH.z - (s.z + (s.pz || 0)), kk = PH.mult > 0 ? sp('pillmagk', 2.6) : sp('pillk', 1.7); if (dx * dx + dz * dz < 20 * kk * kk && Math.abs(PH.y - y) < 6 + 2 * kk) {
      s.taken = true; s.mesh.visible = false; PH.score += 1000; PH.boost_t = Math.max(PH.boost_t, 2.4); PH.picks++; chainHit(); chainHit(); toast('LIGHT MOLECULE  +1000', '#8ff'); try { window.__lookPulse(['psy', 'vec', 'asc'][(s.m || 0) % 3]); } catch (e) { } try { FX.E.pillEat([s.x, y, s.z], MOLS[s.id].c); } catch (e) { } try { SFX.pick(); SFX.snap(); } catch (e) { } try { FX.E.orb([s.x, y, s.z]); } catch (e) { } }
  }
}

function buildNode(n, tag) { const a0 = ANIM.length; TRK = OBJS[tag] = OBJS[tag] || []; buildNode0(n); if (ANIM.length > a0) (GRPS[tag] = GRPS[tag] || []).push(...ANIM.slice(a0)); }
function buildNode0(n) {
  vis[n.path] = n.vis !== false; const parts = n.path.split('/'); let ok = true; for (let k = 2; k < parts.length; k++) if (vis['/' + parts.slice(1, k + 1).join('/')] === false) { ok = false; break; }
  if (!ok || !n.path.startsWith('/MainLevel/RunRig') || n.path.includes('@Camera3D') || n.path.includes('SubViewport')) return;
  if (n.class === 'MeshInstance3D' && n.mesh) {
    const gs = geoOf(n.mesh); const M4 = mat4(n.xf);
    for (const [g, sm] of gs) { const mat = matOf(n.mat_override || sm); if (!mat) continue; shaftPrep(g, mat, M4); const m = new THREE.Mesh(g, mat); m.matrixAutoUpdate = false; m.matrix.copy(M4); m.frustumCulled = false; const ap = animParent(n.path); if (ap) { m.matrix.copy(ap.userData.base.clone().invert().multiply(M4)); ap.add(m); } else NODE.add(m); TRK.push(m); (REGN[n.name] || (REGN[n.name] = [])).push(m); nMesh++; if (((c) => c.includes('MOIRE') || GROUND_SIGS.some((sg) => c.includes(sg)))(lvl.materials[n.mat_override || sm]?.shader_code || '')) {          /* every world's ground, not only the psychedelic one: the board follows its terrain */ ground.push(m); const e = M4.elements; const plain = Math.abs(e[0] - 1) + Math.abs(e[5] - 1) + Math.abs(e[10] - 1) + Math.abs(e[1]) + Math.abs(e[2]) + Math.abs(e[4]) + Math.abs(e[6]) + Math.abs(e[8]) + Math.abs(e[9]) < 1e-6; if (plain && !Q.has('noheightfield') && HF.addMesh(m.uuid, g.attributes.position.array, g.index ? g.index.array : null, [e[12], e[13], e[14]])) m.userData.hf = true; else GRIDLESS.push(m); } if (!ring && (g.attributes.position.count === 1620 || (n.xf && Math.abs(n.xf[9]) < 1 && Math.abs(n.xf[10] + 160) < 2 && Math.abs(n.xf[11]) < 1))) { ring = m; if (!Q.has('plainring')) { const rb = (WORLD_THEME !== 'psychedelic' || Q.has('newring')) && ringBiome(WORLD_THEME, U); if (rb) m.material = rb; { const rk = Q.get('ring') || RING_KIND[WORLD_THEME]; if (rk && !Q.has('pointy')) { if (rk === 'none') m.visible = false; else { const ng = ringShape(THREE, rk, g); if (ng) m.geometry = ng; } } } } } else if (((WORLD_THEME !== 'psychedelic' && WORLD_THEME !== 'alpine') || Q.has('newskirt')) && g.attributes.position.count === 4656 && n.xf && Math.abs(n.xf[10]) < 1) m.material = snowMat({ skirt: WORLD_THEME === 'psychedelic' }); }          // the terrain skirt (the sloping sides around the course) wears each world's own ground, not plain white
  } else if (n.class === 'MultiMeshInstance3D' && n.mesh && n.count) {
    const gs = geoOf(n.mesh); const NM = mat4(n.xf);
    for (const [g, sm] of gs) {
      const mat = matOf(n.mat_override || sm); if (!mat) continue; const im = new THREE.InstancedMesh(g, mat, n.count); const t = new THREE.Matrix4();
      for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); t.__grown = false; shaftPrep(g, mat, t); im.setMatrixAt(i, t); if (n.cols) im.setColorAt(i, new THREE.Color().setRGB(n.cols[i][0], n.cols[i][1], n.cols[i][2], THREE.LinearSRGBColorSpace)); }
      im.frustumCulled = false; NODE.add(im); TRK.push(im); { g.computeBoundingSphere(); if (g.boundingSphere.radius > 1.2) { VEGIM.push(im); if (window.__clearTrees) window.__clearTrees(im); } } nMesh++; nInst += n.count; if (mat.userData && mat.userData.veg) { g.computeBoundingSphere(); const br = g.boundingSphere.radius; if (br > 2 && br < 9 && (!VEGSRC || n.count > VEGSRC.n)) VEGSRC = { g, mat, n: n.count }; } if (!lvl.stream && mat.userData && mat.userData.veg) for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); const k = Math.round(t.elements[12]) + ',' + Math.round(t.elements[14]); if (!TREES.has(k)) TREES.set(k, [t.elements[12], t.elements[14]]); }
    }
  }
}
if (lvl.stream) for (const n of lvl.nodes) if (!REGN[n.name]) REGN[n.name] = [];          // every node name has its (still empty) list of meshes, which the toys and the vortex module keep hold of and which fills when the row arrives
// ---- THE ROW STREAM: the rows around the board are fetched and built a few nodes at a time; the ones behind are taken down again
const BQ = []; const RS = { loading: {}, ahead: 6, behind: 2, j0: 0 };
async function fetchRow(j) { const r = await fetch(LVLDIR + 'row_' + String(j).padStart(2, '0') + '.json'); return r.json(); }
function enqueueRow(j, r) { Object.assign(lvl.meshes, r.meshes || {}); ROWREC[j] = { total: r.nodes.length, built: 0, meshIds: Object.keys(r.meshes || {}), names: [] }; for (const n of r.nodes) { BQ.push({ n, j }); ROWREC[j].names.push(n.name); } if (!r.nodes.length) onRowBuilt(j); }
// ZONES (&zones=0 turns them off): the course repeats a 6-row pattern (1080 m): clear, slalom, slalom, content, clear, content. Clear and slalom rows lose their pickups (pads and buffs);
// content rows keep a share of them (&density=0.5). Molecules, ramps and rails are never touched.
window.__zmap = null;
window.__zoneOf = (j) => {
  if (sp('zones', 1) <= 0) return 'off';
  if (!window.__zmap) {          // decided once, from the course itself: a slalom only goes where there is no ramp, rail or molecule in the row (or within 140 m upstream of one: a ramp pulls the board in from that far)
    const rows = lvl.rows || {}, n = lvl.nrows || Object.keys(rows).length, busy = (j) => { const rr = rows[String(j)], z0 = -180 * j, lo = z0 - 190, hi = z0 + 10; const hit = (zs, pre) => { const a = Math.min(...zs), b = Math.max(...zs) + pre; return b > lo && a < hi; };
      for (const k of [j - 1, j, j + 1]) for (const p of ((rows[String(k)] || {}).pads || [])) if (p.lk && Number.isFinite(p.z) && hit([p.z, p.z - (Number.isFinite(p.lk.len) ? p.lk.len : 90)], 5)) return true;          /* a spring (pad + tube) is a set piece: no pylons along its length, and its pad is never hidden */
      for (const q of [rows[String(j)], rows[String(j + 1)], rows[String(j - 1)]]) { if (!q) continue; for (const f of (q.feats || [])) { if (f.kind !== 'jump' && f.kind !== 'rail') continue; const zs = [f.za, f.zb, f.zl, f.z].filter(Number.isFinite); if (zs.length && hit(zs, f.kind === 'jump' ? 140 : 10)) return true; } for (const t of (q.toys || [])) if (t.kind === 'pill' && Number.isFinite(t.z) && hit([t.z], 20)) return true; }
      return false; };
    const m = {}; let run = 0, prev = 'clear'; for (let j = 0; j < n; j++) { let z; if (j === 0) z = 'clear'; else if (!busy(j) && run < Math.round(sp('slalomrun', 2))) { z = 'slalom'; run++; } else { run = 0; z = prev === 'slalom' ? 'clear' : (j % 2 ? 'content' : 'clear'); } m[j] = z; prev = z; }
    window.__zmap = m; try { window.__dm && window.__dm('zones: ' + Object.values(m).join(',')); } catch (e) { }
  }
  return window.__zmap[j] || 'content';
};
window.__spawnGap = () => Math.max(0, sp('spawngap', 1.3));
window.__ZD = new Set();
// hide a whole thing, not just one mesh: a pad, a pickup or a toy is a small tree of nodes (bars, glow pool, gem, halo...), and hiding only the gem left the bars lying there doing nothing.
// The top-level node under RunRig that holds the referenced node is hidden together with everything inside it (only when it is a small tree, so nothing unrelated can disappear).
window.__CH = null;
window.__hideWhole = (o) => {
  try {
    const refs = [o.gem, o.n, o.halo, o.spin, o.sp].filter(Boolean); if (!refs.length) return false;
    if (!window.__CH) { window.__CH = {}; for (const n of lvl.nodes) { const seg = String(n.path).split('/'); if (seg.length >= 4) { const top = seg.slice(0, 4).join('/'); (window.__CH[top] = window.__CH[top] || []).push(n.name); } } }
    let ok = false; const seen = new Set();
    for (const r of refs) { const nd = NBN[nameOf(r)]; if (!nd) continue; const seg = String(nd.path).split('/'); if (seg.length < 4) continue; const top = seg.slice(0, 4).join('/'); if (seen.has(top)) continue; seen.add(top); const list = window.__CH[top] || []; if (list.length > 40) { hideNode(r); continue; } for (const nm of list) hideNode(nm); ok = true; }
    return ok;
  } catch (e) { return false; }
};
window.__ZD = new Set();
window.__zoneRow = (rr, j) => {
  if (window.__ZD.has(j)) return; const z = window.__zoneOf(j); if (z === 'off') { window.__ZD.add(j); return; }
  const dens = z === 'content' ? Math.max(0, Math.min(1, sp('density', .5))) : 0, keep = (i, salt) => (((i * 2654435761 + j * 40503 + salt * 977) >>> 0) % 1000) / 1000 < dens;
  try {
    const prevR = lvl.rows[String(j - 1)] || {}, ap = (rr.pads || []).concat(prevR.pads || []), follows = (b) => ap.some((q) => !q.zoneHid && q.z - b.z > 25 && q.z - b.z < 120 && Math.abs(q.x - b.x) < 45);
    (rr.pads || []).forEach((q) => { if (!q.used && !q.lk) { if (!window.__hideWhole(q)) hideTarget(q); q.used = true; q.zoneHid = true; } });          // the course's own pads: all hidden (the phrase deck places boosts on purpose)
    (rr.buffs || []).forEach((b) => { if (!b.taken) { if (!window.__hideWhole(b)) hideTarget(b); for (const o of (b.orbs || [])) hideNode(o.n); b.thin = true; b.taken = true; } });          // the course's own powerups: all hidden (the deck places them after the boosts)
    for (const t of (rr.toys || [])) if (t.kind !== 'pill' && !t.gone && (z === 'slalom' || z === 'clear' || t.kind === 'sling' || !keep((t.x * 7 + t.z) | 0, 3))) { if (!window.__hideWhole(t)) hideNode(t.n); t.done = true; t.t = 1e15; t.gone = true; }          // bumps, colour gates and slingshots: gone from clear and slalom stretches, thinned in the content ones (molecules stay)
    window.__ZD.add(j);
  } catch (e) { /* the world is not ready yet: the per-frame tick tries again */ }
};
function hideDropped(j) { const rr = lvl.rows && lvl.rows[String(j)]; if (!rr) return; for (const o of (rr.orbs || [])) { o.got = true; hideNode(o.n); } for (const b of (rr.buffs || [])) if (b.thin) { hideTarget(b); for (const o of (b.orbs || [])) hideNode(o.n); } if (window.__zoneRow) window.__zoneRow(rr, j); }          // the gaze orbs and the thinned buffs are hidden when their row is built
function onRowBuilt(j) { try { VFX.refresh(); } catch (e) { } try { hideDropped(j); } catch (e) { } }
function pumpBuild(budgetMs) { const t0 = performance.now(); while (BQ.length && performance.now() - t0 < budgetMs) { const it = BQ.shift(), R = ROWREC[it.j]; if (!R) continue; buildNode(it.n, it.j); R.built++; if (R.built === R.total) onRowBuilt(it.j); } }
function unloadRow(j) {
  const R = ROWREC[j]; if (!R) return; for (let i = BQ.length - 1; i >= 0; i--) if (BQ[i].j === j) BQ.splice(i, 1);
  for (const o of (OBJS[j] || [])) { if (o.parent) o.parent.remove(o); if (o.isInstancedMesh) o.dispose(); const gi = ground.indexOf(o); if (gi >= 0) ground.splice(gi, 1); if (o.userData && o.userData.hf) HF.remove(o.uuid); const gl = GRIDLESS.indexOf(o); if (gl >= 0) GRIDLESS.splice(gl, 1); }
  for (const g of (GRPS[j] || [])) { if (g.parent) g.parent.remove(g); const ai = ANIM.indexOf(g); if (ai >= 0) ANIM.splice(ai, 1); delete GRP[Object.keys(GRP).find((k) => GRP[k] === g)]; }
  for (const nm of R.names) if (REGN[nm]) REGN[nm].length = 0;
  for (const id of R.meshIds) { if (GEO[id]) { for (const [g] of GEO[id]) g.dispose(); delete GEO[id]; } delete lvl.meshes[id]; }
  delete OBJS[j]; delete GRPS[j]; delete ROWREC[j];
}
function rowsUpdate(z) {
  if (!lvl.stream) return; const j0 = Math.max(0, Math.min(lvl.nrows - 1, Math.floor(-z / 180))); RS.j0 = j0; const want = new Set();
  for (let j = Math.max(0, j0 - RS.behind); j <= Math.min(lvl.nrows - 1, j0 + RS.ahead); j++) want.add(j);
  if (j0 >= lvl.nrows - 7) for (let j = 0; j <= 3; j++) want.add(j);          // the end of the course loops to the start: its first rows are brought in before the board gets there
  for (const j of want) if (!ROWREC[j] && !RS.loading[j]) { RS.loading[j] = true; fetchRow(j).then((r) => { RS.loading[j] = false; enqueueRow(j, r); }).catch(() => { RS.loading[j] = false; }); }
  for (const k of Object.keys(ROWREC)) if (!want.has(+k)) unloadRow(+k);
}
let bi = 0; const BUILD0 = lvl.stream ? lvl.metaNodes : lvl.nodes;
for (const n of BUILD0) {
  if ((++bi & 31) === 0) { if (window.__dm && (bi & 255) === 0) window.__dm('build world ' + bi + ' / ' + BUILD0.length); setLoad(.5 + .3 * bi / BUILD0.length, 'building the world  ' + Math.round(100 * bi / BUILD0.length) + '%'); await new Promise((r2) => setTimeout(r2, 0)); }
  buildNode(n, 'meta');
}
if (lvl.stream) {          // the first rows, before the game starts
  window.__dm && window.__dm('level: meta and physics loaded'); { const TXc = lvl.trailx || [], zmat = new THREE.Matrix4().makeScale(0, 0, 0), mm = new THREE.Matrix4(), txf = (z) => { const i = Math.max(0, -z) / 6, a = Math.min(TXc.length - 1, Math.floor(i)), b = Math.min(TXc.length - 1, a + 1); return TXc.length ? TXc[a] + (TXc[b] - TXc[a]) * (i - a) : 0; }; window.__clearTrees = (im) => { const W = parseFloat(Q.get('clear') || '0'); if (!(W > 0)) return; for (let i = 0; i < im.count; i++) { im.getMatrixAt(i, mm); const e = mm.elements; if (e[15] !== 0 && Math.abs(e[12] - txf(e[14])) < W) im.setMatrixAt(i, zmat); } im.instanceMatrix.needsUpdate = true; }; }          /* &clear=48: no trees or rocks within 48 m of the trail centre, so the wide steering can be tested on open ground (use with &wide=2) */ const first = []; const j00 = Math.max(0, Math.min(lvl.nrows - 5, START_ROW - 1)); for (let j = j00; j <= j00 + 4; j++) first.push(fetchRow(j)); const got = await Promise.all(first); got.forEach((r, k) => enqueueRow(j00 + k, r));
  const tot = BQ.length; window.__dm && window.__dm('build first rows: ' + tot + ' items'); let bq0 = 0; while (BQ.length) { if (window.__dm && (++bq0 & 15) === 0) window.__dm('build first rows: ' + BQ.length + ' left'); pumpBuild(12); setLoad(.8 + .2 * (1 - BQ.length / tot), 'building the first rows  ' + Math.round(100 * (1 - BQ.length / tot)) + '%'); await new Promise((r2) => setTimeout(r2, 0)); }
}
// lights and environment from the dump
let ENV = null; let sunNode = lvl.nodes.find((n) => n.light && n.name === 'Sun'), envNode = lvl.nodes.find((n) => n.env);
if (sunNode) {
  const L = sunNode.light, sun = new THREE.DirectionalLight(rgb(L.color), L.energy * Math.PI), b = sunNode.xf, dir = new THREE.Vector3(-b[6], -b[7], -b[8]);          // Godot lights shine along the node's -Z
  sun.position.copy(dir.clone().multiplyScalar(-200)); sun.target.position.set(0, 0, 0); scene.add(sun, sun.target);
}
if (envNode) {
  const e = envNode.env; scene.fog = new THREE.FogExp2(rgb(e.fog_light_color), e.fog_density); U.fogColor.value.copy(rgb(e.fog_light_color)); U.fogDensity.value = e.fog_density;
  scene.add(new THREE.HemisphereLight(new THREE.Color(0.0903, 0.0704, 0.1298), new THREE.Color(0.10, 0.01, 0.16), e.ambient_light_energy * Math.PI));          // Godot's sky ambient (Themes.gd sky(): cosine-weighted average of the sky over the upper and the lower hemisphere)
  renderer.toneMappingExposure = parseFloat(Q.get('exp') || '1.05'); ENV = e;
}
const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), WORLD_THEME === 'psychedelic' ? skyMat() : (skyBiome(WORLD_THEME, U) || (WORLD_THEME === 'alpine' ? WFX.skyAlpine() : skyMat()))); sky.frustumCulled = false; sky.renderOrder = -10; scene.add(sky); if (WORLD_THEME === 'alpine') WFX.setSkyEnv(ALPINE);
if (WORLD_THEME !== 'psychedelic' && WFX.meshes) for (const k of ['skyFx', 'skyDome']) if (WFX.meshes[k]) WFX.meshes[k].visible = false;          // the psychedelic sky's nebula and dome belong to that world only
const CAVE = { k: 0, mul: 1, last: null, said: {}, base: null, col: new THREE.Color() };
function caveTick(dt) {          // Realms.cave_k: 0 outside, 1 deep inside a roofed realm (glowcave, crystal, lava, abyss); exposure and fog follow it
  if (!PLAY || !lvl.stream || !lvl.rows) return; const j = Math.max(0, Math.floor(-PH.z / 180)), rr = lvl.rows[String(j)], roof = rr && ROOF[rr.zone];
  if (roof) { CAVE.last = roof; if (!CAVE.said[j]) { CAVE.said[j] = 1; toast(roof.reveal, '#c9f'); } }
  CAVE.k += ((roof ? 1 : 0) - CAVE.k) * (1 - Math.exp(-dt / .7)); CAVE.mul = 1 - (1 - (CAVE.last ? CAVE.last.expo : 1)) * CAVE.k;
  if (CAVE.last) { if (!CAVE.base) CAVE.base = U.fogColor.value.clone(); CAVE.col.setRGB(CAVE.last.col[0], CAVE.last.col[1], CAVE.last.col[2], THREE.SRGBColorSpace); U.fogColor.value.copy(CAVE.base).lerp(CAVE.col, .85 * CAVE.k); if (scene.fog) scene.fog.color.copy(U.fogColor.value); }
}
const WEATHER = Q.has('noweather') ? { tick() { } } : createWeather({ scene, theme: WORLD_THEME, U, toast: (t, c) => toast(t, c), fogSceneRef: scene });          // alpine: Godot's procedural sky (blue top, a peach horizon, a low sun)
if (ring && WORLD_THEME === 'psychedelic') WFX.attachMountainSkin(ring);          // the 2C-E skin on the distant mountains (MTNFX: moire creeping with travel, rolling contour bands, a polar field)
// ---------------------------------------------------------------- fly
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0);
function groundY(x, z) { const y = HF.height(x, z); if (y !== null) return y; if (!GRIDLESS.length) return null; ray.set(new THREE.Vector3(x, 3000, z), down); const h = ray.intersectObjects(GRIDLESS, false); return h.length ? h[0].point.y : null; }
const st = { z: START_ROW > 0 ? -(Math.min(START_ROW, lvl.nrows - 2) * 180) - 30 : (lvl.start ? lvl.start[2] - 2 : -2), x: 0, speed: parseFloat(Q.get('speed') || '40'), paused: false, y: 0 };
addEventListener('keydown', (e) => { if (e.key === ' ' && !PLAY) st.paused = !st.paused; if (e.key === 'ArrowUp') st.speed += 10; if (e.key === 'ArrowDown') st.speed = Math.max(0, st.speed - 10); if (e.key === 'ArrowLeft') st.x -= 4; if (e.key === 'ArrowRight') st.x += 4; });

// ---------------------------------------------------------------- THE PICTURE PASS (the real shader from the game: the psychedelic branch of ThemeFX's pass, with the values the game had when the level was dumped)
// The scene is drawn into a float target, tonemapped like the game's filmic tonemap into display colours, and the game's own post math runs on those (warp, chromatic split, tracer ghosts, wash, punch, vignette).
const POST_ON = !Q.has('nopost');
const GLOWQ = { on: !Q.has('noglow'), samples: 0 }; const _gl = renderer.getContext(); const MSAA_OK = renderer.capabilities.isWebGL2 && !!(_gl.getExtension('EXT_color_buffer_float') || _gl.getExtension('EXT_color_buffer_half_float')) && !Q.has('nomsaa');
GLOWQ.samples = MSAA_OK ? parseInt(Q.get('msaa') || '4', 10) : 0;
const rtScene = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: true, samples: GLOWQ.samples }), rtG4 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtG8 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtG16 = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtA = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false }), rtB = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false });
const qGeo = new THREE.BufferGeometry(); qGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3)); qGeo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
const QV = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }';
const feedM = new THREE.ShaderMaterial({ uniforms: { uScene: { value: null }, uPrev: { value: null } }, vertexShader: QV, depthTest: false, depthWrite: false, fragmentShader: `varying vec2 vUv; uniform sampler2D uScene, uPrev; void main(){ vec3 c = texture2D(uScene, vUv).rgb, p = texture2D(uPrev, vUv + (vUv - .5) * .004).rgb; if (any(equal(floatBitsToUint(c) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) c = vec3(0.); if (any(equal(floatBitsToUint(p) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) p = vec3(0.); gl_FragColor = vec4(max(c * .55, p * .86), 1.); }` });
const brightM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, thr: { value: 1 }, scl: { value: 2 }, bloom: { value: .1 }, expo: { value: 1.05 }, cap: { value: 12 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel; uniform float thr, scl, bloom, expo, cap; vec3 tap(vec2 o){ vec3 c0 = texture2D(uSrc, vUv + o * uTexel).rgb; if (any(equal(floatBitsToUint(c0) & uvec3(0x7F800000u), uvec3(0x7F800000u)))) c0 = vec3(0.); vec3 c = min(max(c0, vec3(0.)) * expo, vec3(cap)); float m = max(c.r, max(c.g, c.b)); return c * max(smoothstep(thr, thr + scl, m), bloom); }
  void main(){ gl_FragColor = vec4((tap(vec2(-1., -1.)) + tap(vec2(1., -1.)) + tap(vec2(-1., 1.)) + tap(vec2(1., 1.))) * .25, 1.); }` });
const downM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel; void main(){ vec3 c = texture2D(uSrc, vUv + uTexel * vec2(-1., -1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(1., -1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(-1., 1.)).rgb + texture2D(uSrc, vUv + uTexel * vec2(1., 1.)).rgb; gl_FragColor = vec4(c * .25, 1.); }` });
const P = { amount: 0.8, breathe: 0.8, trip: 0, mA: new THREE.Vector3(), mB: new THREE.Vector3(), dmt: 0, buzz: 0, sharp: 0, k_warp: 1, k_pulse: 1, k_chroma: 1, k_trace: 1, k_punch: 1, k_wash: 0 };
const postOld = new THREE.ShaderMaterial({ uniforms: { mae: { value: 0 }, gA: { value: null }, gB: { value: null }, gC: { value: null }, glowI: { value: 0 }, lv4: { value: .8 }, lv8: { value: .4 }, lv16: { value: .1 }, tmWhite: { value: 1 }, bcs: { value: new THREE.Vector3(1, 1.1, 1.15) }, screen_tex: { value: null }, trail: { value: null }, TIME: U.uTime, exposure: { value: 1.05 }, amount: { value: P.amount }, breathe: { value: P.breathe }, trip: { value: 0 }, mA: { value: P.mA }, mB: { value: P.mB }, dmt: { value: 0 }, buzz: { value: 0 }, sharp: { value: 0 }, k_warp: { value: 1 }, k_pulse: { value: 1 }, k_chroma: { value: 1 }, k_trace: { value: 1 }, k_punch: { value: 1 }, k_wash: { value: 0 }, use_trail: { value: 1 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D screen_tex, trail; uniform float mae, TIME, exposure, amount, breathe, trip, dmt, buzz, sharp, k_warp, k_pulse, k_chroma, k_trace, k_punch, k_wash, use_trail; uniform vec3 mA, mB; uniform sampler2D gA, gB, gC; uniform float glowI, lv4, lv8, lv16, tmWhite; uniform vec3 bcs; uniform float vmode, uCell; uniform vec2 uRes; uniform sampler2D glyphs; ${GLSL_HSV}
  float hable(float x){ const float A = .88, B = .6, C = .1, D = .2, E = .01, F = .3; return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F; }          // Godot 4 tonemap_filmic: Hable with exposure bias 2, divided by the curve at white
  vec3 filmic(vec3 c){ c = max(c, vec3(0.)); float w = hable(tmWhite); return vec3(hable(c.r), hable(c.g), hable(c.b)) / w; }
  vec3 srgb(vec3 c){ c = clamp(c, 0., 1.); return mix(c * 12.92, 1.055 * pow(c, vec3(1. / 2.4)) - .055, step(.0031308, c)); }
  vec3 bcsAdj(vec3 c){ c = mix(vec3(0.), c, bcs.x); c = mix(vec3(.5), c, bcs.y); return mix(vec3(dot(vec3(1.), c) * (1. / 3.)), c, bcs.z); }          // Godot's adjustment: brightness, contrast, saturation (saturation about the channel average)
  vec3 toDisp(vec3 hdr){ return bcsAdj(srgb(filmic(hdr))); }
  bool badf(float x){ return (floatBitsToUint(x) & 0x7F800000u) == 0x7F800000u; }          // NaN or Inf, tested on the bits (isnan() can be optimised away by a driver)
  bool bad(vec3 c){ return badf(c.x) || badf(c.y) || badf(c.z); }
  vec3 hdrAt(sampler2D t, vec2 u){ vec3 c = texture2D(t, u).rgb; if (bad(c)) { ivec2 sz = textureSize(t, 0); ivec2 ip = ivec2(u * vec2(sz)); vec3 a = vec3(0.); float n = 0.; for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) { vec3 sm = texelFetch(t, clamp(ip + ivec2(i, j), ivec2(0), sz - 1), 0).rgb; if (!bad(sm)) { a += sm; n += 1.; } } c = n > 0. ? a / n : vec3(0.); } return min(max(c, vec3(0.)), vec3(60.)); }          // (bilinear filtering smears a NaN texel over its neighbours, so the repair reads whole texels)
  vec3 disp(vec2 u){ vec3 h = hdrAt(screen_tex, u) * exposure; if (glowI > 0.) { vec3 g = (texture2D(gA, u).rgb * lv4 + texture2D(gB, u).rgb * lv8 + texture2D(gC, u).rgb * lv16) * glowI; h = max(h + g - h * g, vec3(0.)); } return toDisp(h); }
  void main(){ vec2 uv = vUv, c = uv - .5; float r = length(c), w = sin(TIME * .7 + r * 9.) * .0012 * k_warp * amount * breathe, tw = trip * trip;
    vec2 wuv = vec2(.5) + c + c * w * 2. + vec2(sin(uv.y * 14. + TIME) * .0008, 0.) * amount * breathe;
    float keep = mix(.35, 1., smoothstep(.05, .38, length(c * vec2(1., 1.25)))), pl = pow(max(sin(TIME * 6.), 0.), 3.);
    wuv += c * (mA.x * .002 * k_warp * keep * sin(TIME * .5 + r * 6.)); wuv += c * (mB.y * .0015 * k_warp * keep * sin(r * 34. - TIME * 3.));
    wuv = vec2(.5) + (wuv - vec2(.5)) * (1. - .006 * k_pulse * mB.z * pl * keep + .006 * k_pulse * dmt * sin(TIME * .8) * keep);
    float ca = (.003 + r * .012) * amount * k_chroma * (1. + trip * .5 + mA.z * .5 + dmt * .6);          /* the frozen psychedelic look: Godot's own colour split (I had reduced it; reverted) */
    vec3 col;
    if (mae > .002) {          // MOTION AFTEREFFECT: after a long rush the still world seems to drift the other way (it contracts). Two zoom phases, half a cycle apart, cross-faded so the loop has no seam.
      float p0 = fract(TIME * .2), p1 = fract(p0 + .5), wA = 1. - abs(2. * p0 - 1.); float am = mae * .11;
      vec2 uA = vec2(.5) + (wuv - .5) * (1. + am * p0), uB = vec2(.5) + (wuv - .5) * (1. + am * p1);
      vec3 cA = vec3(disp(uA + c * ca).r, disp(uA).g, disp(uA - c * ca).b), cB = vec3(disp(uB + c * ca).r, disp(uB).g, disp(uB - c * ca).b); col = mix(cB, cA, wA);
    } else col = vec3(disp(wuv + c * ca).r, disp(wuv).g, disp(wuv - c * ca).b);
    vec3 old = toDisp(hdrAt(trail, uv) * exposure), cur = disp(uv), diff = max(old - cur * .92 - .02, vec3(0.));
    float m = clamp(dot(diff, vec3(.34)) * 3.2 * (1. + trip) * (.4 + .6 * smoothstep(.1, .45, r)), 0., 1.); vec3 ghost = hsv(fract(TIME * .12 + r * .9 + m * .5), .95, 1.) * m;
    col += ghost * .45 * amount * use_trail * k_trace;
    col = mix(col, col * hsv(fract(TIME * .05), .25, 1.1), .12 * amount); col = mix(col, col * hsv(fract(TIME * .14 + r * 1.2), .7, 1.3), tw * .55 * k_wash);
    col *= 1. + trip * .08; col *= 1. - .45 * smoothstep(.45, .95, r); col = mix(col, col * vec3(1.15, .95, .78), mA.x * .5); col *= 1. + mA.y * .12 * sin(TIME * .35); col *= 1. + mB.z * .30 * pl * keep;
    float lm = dot(col, vec3(.299, .587, .114)); col = mix(vec3(lm), col, 1. + (.45 + .6 * trip + .8 * mA.z + .5 * dmt) * k_punch);
    col += max(col - .55, vec3(0.)) * (.30 + .25 * buzz + 1. * sharp) * amount; col = max((col - .5) * (1. + .3 * sharp) + .5, vec3(0.)); col = mix(vec3(dot(col, vec3(.299, .587, .114))), col, 1. + .4 * sharp);
    col = max((col - .5) * (1.14 + .2 * trip + .2 * mA.y) + .5 - .05, vec3(0.));
    float mxc = max(max(col.r, col.g), col.b); if (mxc > .75) col *= (.75 + .25 * (1. - exp(-(mxc - .75) * 2.5))) / mxc; col *= .92;
    if (vmode > 2.5) { col = disp(uv); }          // BYPASS (for measuring): the scene after the environment (tonemap, glow, colour grade) and before the picture pass
    else if (vmode > .5 && vmode < 1.5) {
      vec2 tx = 1.6 / uRes; float l0 = dot(disp(uv + vec2(tx.x, 0.)), vec3(.299, .587, .114)), l1 = dot(disp(uv - vec2(tx.x, 0.)), vec3(.299, .587, .114)), l2 = dot(disp(uv + vec2(0., tx.y)), vec3(.299, .587, .114)), l3 = dot(disp(uv - vec2(0., tx.y)), vec3(.299, .587, .114));
      float e = length(vec2(l0 - l1, l2 - l3)) * 3.2; float ln = smoothstep(.05, .22, e); vec3 hue = col / max(max(col.r, max(col.g, col.b)), .05);
      vec3 lines = (hue * (.35 + .65 * ln) * ln * 1.7) + texture2D(gA, uv).rgb * glowI * .9; col = lines + col * .035; }
    else if (vmode > 1.5 && vmode < 2.5) {
      vec2 cells = uRes / uCell; vec2 cuv = (floor(uv * cells) + .5) / cells; vec3 cc = disp(cuv); float lum = dot(cc, vec3(.299, .587, .114)); float idx = floor(clamp(lum * 1.35, 0., .999) * 10.); vec2 lc = fract(uv * cells);
      float gl = texture2D(glyphs, vec2((idx + lc.x) / 10., 1. - lc.y)).r; vec3 hc = cc / max(max(cc.r, max(cc.g, cc.b)), .08); col = hc * gl * (.5 + 1.4 * lum) + cc * .05; }
    gl_FragColor = vec4(col, 1.); }` });
// THE PICTURE PASS: with ?newpost Godot's own full pass (postfx.js, generated from the real shader source: tube, onset, fold, rings, wash, face, rewind, smear, outlines...), fed by the same inputs as the older hand-copied pass, which is the default.
const PFX = Q.has('newpost') ? createPostFx({ THREE, time: U.uTime }) : null;          // (opt-in: the parity harness gives identical numbers for both, and the big generated shader costs about a second more to compile here, more on integrated graphics)
const postM = PFX ? PFX.material : postOld; if (PFX) { for (const k of Object.keys(postOld.uniforms)) postM.uniforms[k] = postOld.uniforms[k]; postM.uniforms.mode = { value: 1 }; }
const qScene = new THREE.Scene(), qCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1), qMesh = new THREE.Mesh(qGeo, feedM); qMesh.frustumCulled = false; qScene.add(qMesh);
const PSY = createPsyFx({ fx: { x_level: parseFloat(Q.get('level') || (CHILL ? '0.3' : '0.6')) }, seed: lvl.seed || 7, sessionMin: parseFloat(Q.get('min') || '10'), cfgTrip: parseFloat(Q.get('trip') || (CHILL ? '.35' : '1')), journey: !Q.has('plain'), onCheer: (t) => toast(String(t).replace(/!?$/, ''), '#fd8'), onToast: (t) => toast(t, '#fff') }); window.__psy = PSY;
const GL0 = { i: null, b: null }, FOG0 = { d: null };
const GL = { intensity: 0, bloom: .1, thr: 1, scale: 2, cap: 12 };
if (ENV) { GL.intensity = ENV.glow_enabled === false ? 0 : (ENV.glow_intensity !== undefined ? ENV.glow_intensity : .35); GL.bloom = ENV.glow_bloom !== undefined ? ENV.glow_bloom : .1; GL.thr = ENV.glow_hdr_threshold !== undefined ? ENV.glow_hdr_threshold : 1; GL.scale = ENV.glow_hdr_scale !== undefined ? ENV.glow_hdr_scale : 2; GL.cap = ENV.glow_hdr_luminance_cap || 12;
  const pu = postM.uniforms; pu.lv4.value = ENV['glow_levels/2'] !== undefined ? ENV['glow_levels/2'] : .8; pu.lv8.value = ENV['glow_levels/3'] !== undefined ? ENV['glow_levels/3'] : .4; pu.lv16.value = ENV['glow_levels/4'] !== undefined ? ENV['glow_levels/4'] : .1;
  pu.bcs.value.set(ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_brightness || 1), ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_contrast || 1), ENV.adjustment_enabled === false ? 1 : (ENV.adjustment_saturation || 1)); if (!Q.has('grade')) pu.bcs.value.set(1, 1, 1); if (Q.has('neon')) pu.bcs.value.set(.94, 1.45, 1.35);          /* ?neon: a harder, more saturated picture (contrast 1.45, saturation 1.35) to try for the psych level */          /* the web-build look, on desktop too: no colour grade (Lighting._apply_tier); ?grade turns it back on */ pu.tmWhite.value = ENV.tonemap_white || 1; brightM.uniforms.cap.value = GL.cap; }
let ping = 0; let MSAA_CHECK = 3;
// THE PSYCH LAYER: the trip picture pass (warp, trails, colour, rings...) scaled by one number, PSYK. In the Trip and Tunnel biomes it is 1 (the original), elsewhere 0, and &psych=0..1.5 (or the Psych button in the panel) sets it for any biome.
// In the other biomes a molecule gives it a brief, smooth moment (about 2.6 s, in and out, never above 0.85) and then it is gone again.
const PSYL = { pulse: 0, t: performance.now() }; window.__PSYL = PSYL;
window.__psychPulse = () => { if (sp('flash', 1) <= 0 || THEME_PK > 0) return false; if (PSYL.pulse > 0) return false; PSYL.pulse = 1; return true; };
function psykNow() { const now = performance.now(), dt = Math.min(.1, (now - PSYL.t) / 1000); PSYL.t = now; PSYL.pulse = Math.max(0, PSYL.pulse - dt / 2.6); const base = Math.max(0, Math.min(1.5, sp('psych', THEME_PK))); const env = Math.sin(Math.PI * (1 - PSYL.pulse)) * (PSYL.pulse > 0 ? .85 : 0) * sp('flash', 1); return Math.max(base, env); }
function applyPsy() {          // the Godot trip model's numbers into the picture pass, the bloom and the haze (RunRig._pill_tick / _buzz_tick)
  const Uq = PSY.uniforms(), pu = postM.uniforms, PK = psykNow(); if (PFX) { PFX.setUniformsFrom(Uq, {}); pu.mode.value = 1; for (const k of ['tube', 'smear', 'rewind', 'k_edge', 'k_cel', 'k_fold', 'k_rings', 'k_dmtr', 'face', 'edge_hue']) if (pu[k] && typeof pu[k].value === 'number') pu[k].value *= PK; } if (GL0.i === null) { GL0.i = GL.intensity; GL0.b = GL.bloom; } if (FOG0.d === null) FOG0.d = U.fogDensity.value;
  pu.trip.value = Uq.trip * PK; pu.mA.value.set((Uq.mA[0] || 0) * PK, (Uq.mA[1] || 0) * PK, (Uq.mA[2] || 0) * PK); pu.mB.value.set((Uq.mB[0] || 0) * PK, (Uq.mB[1] || 0) * PK, (Uq.mB[2] || 0) * PK); pu.dmt.value = Uq.dmt * PK; pu.buzz.value = Uq.buzz * PK; pu.sharp.value = Uq.sharp * PK; pu.amount.value = Uq.amount * PK; pu.breathe.value = Uq.breathe * PK;
  pu.k_warp.value = Uq.k_warp * PK; pu.k_pulse.value = Uq.k_pulse * PK; pu.k_chroma.value = Uq.k_chroma * PK; pu.k_trace.value = Uq.k_trace * PK; pu.k_punch.value = Uq.k_punch * PK; pu.k_wash.value = Uq.k_wash * PK;
  GL.intensity = Q.has('noglow') ? 0 : GL0.i * Uq.glowIntensityMul; GL.bloom = GL0.b * Uq.glowBloomMul + Uq.glowBloomAdd; U.fogDensity.value = FOG0.d * Uq.fogDensityMul;
}
const VM = { mode: 0, names: ['NORMAL', 'VECTOR', 'ASCII'] };
postM.uniforms.vmode = { value: 0 }; postM.uniforms.uCell = { value: 9 }; postM.uniforms.uRes = { value: new THREE.Vector2(960, 540) };
{ const cv = document.createElement('canvas'); cv.width = 160; cv.height = 24; const cx = cv.getContext('2d'); cx.fillStyle = '#000'; cx.fillRect(0, 0, 160, 24); cx.fillStyle = '#fff'; cx.font = '700 20px ui-monospace,Consolas,monospace'; cx.textAlign = 'center'; cx.textBaseline = 'middle'; ' .:-=+*#%@'.split('').forEach((ch, i) => { cx.fillText(ch, i * 16 + 8, 13); }); const gt = new THREE.CanvasTexture(cv); gt.minFilter = THREE.LinearFilter; gt.magFilter = THREE.LinearFilter; gt.generateMipmaps = false; postM.uniforms.glyphs = { value: gt }; }
function setVMode(m) { VM.mode = ((m % 3) + 3) % 3; postM.uniforms.vmode.value = VM.mode; if (window.__vbtn) window.__vbtn.textContent = VM.names[VM.mode]; }
function sizePost(w, h) { postM.uniforms.uRes.value.set(w, h); postM.uniforms.uCell.value = Math.max(6, Math.round(w / 110)); rtScene.setSize(w, h); rtSharp.setSize(w, h); rtA.setSize(w >> 1, h >> 1); rtB.setSize(w >> 1, h >> 1); rtG4.setSize(Math.max(2, w >> 2), Math.max(2, h >> 2)); rtG8.setSize(Math.max(2, w >> 3), Math.max(2, h >> 3)); rtG16.setSize(Math.max(2, w >> 4), Math.max(2, h >> 4)); PW = w; PHt = h; }
let PW = 4, PHt = 4;
// SHARPENING (&sharpen=1, 0 turns it off): a smaller picture is stretched to the screen, which softens it; this adds the edge contrast back with an unsharp mask limited to the neighbouring values (so no halos),
// stronger the fewer pixels the dynamic resolution is drawing. Five texture reads a pixel: cheap beside the scene.
const rtSharp = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false });
const sharpM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, uAmt: { value: 0 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel; uniform float uAmt;
  void main() { vec3 c = texture2D(uSrc, vUv).rgb, n = texture2D(uSrc, vUv + vec2(0., uTexel.y)).rgb, s = texture2D(uSrc, vUv - vec2(0., uTexel.y)).rgb, e = texture2D(uSrc, vUv + vec2(uTexel.x, 0.)).rgb, w = texture2D(uSrc, vUv - vec2(uTexel.x, 0.)).rgb;
    vec3 lo = min(min(n, s), min(e, w)), hi = max(max(n, s), max(e, w)), blur = (n + s + e + w) * .25, sh = c + (c - blur) * uAmt; sh = clamp(sh, min(lo, c) * .9, max(hi, c) * 1.1); gl_FragColor = vec4(sh, 1.0); ${TAIL} }` });

// LOOKS (vector + ASCII): full-screen passes over the finished picture, switched live and faded in and out (LOOK.vec / LOOK.asc follow the targets 'vector' and 'ascii', 0..1, over about half a second).
//   vector: edges found in the picture glow in the colour of what they outline, on a near-black ground (a wireframe look). ascii: the picture is cut into character cells (about 110 across); each cell draws a
//   dot, colon, plus, cross or block by how bright it is, in the colour underneath.
const LOOK = window.__LOOK = { vec: 0, asc: 0, pv: 0, pa: 0, ev: 0, ea: 0, last: 0, t: performance.now() };
// FLASHES: a molecule can flash the vector or the ASCII look for a moment (Trip biome only; &flash=0 off). One flash at most every 1.5 s, 0.4 s long, never above 70%, faded in and out (no strobing), so it never hides the road for long.
window.__lookPulse = (kind) => { if (sp('flash', 1) <= 0) return; const trip = WORLD_THEME === 'psychedelic', now = performance.now(); if (kind === 'psy') { if (!trip && WORLD_THEME !== 'matrix' && WORLD_THEME !== 'synthwave' && now - LOOK.last > 4000 && window.__psychPulse()) { LOOK.last = now; return; } kind = 'vec'; } if (now - LOOK.last < (trip ? 1500 : 4000)) return; LOOK.last = now; LOOK.dur = trip ? .4 : 2.4; if (WORLD_THEME === 'matrix') kind = 'asc'; else if (WORLD_THEME === 'synthwave') kind = 'vec'; if (kind === 'asc') LOOK.pa = 1; else LOOK.pv = 1; };          /* other biomes: a molecule gives a brief 2.4 s moment of the look, smoothly in and out, then the biome is back as it was */
const lookM = new THREE.ShaderMaterial({ uniforms: { uSrc: { value: null }, uTexel: { value: new THREE.Vector2() }, uRes: { value: new THREE.Vector2(1, 1) }, uCell: { value: 8 }, uVec: { value: 0 }, uAsc: { value: 0 } }, vertexShader: QV, depthTest: false, depthWrite: false,
  fragmentShader: `varying vec2 vUv; uniform sampler2D uSrc; uniform vec2 uTexel, uRes; uniform float uCell, uVec, uAsc;
  float lum(vec3 c) { return dot(c, vec3(.299, .587, .114)); }
  void main() {
    vec3 c = texture2D(uSrc, vUv).rgb, col = c;
    if (uVec > .001) {
      vec2 t = uTexel;
      float a = lum(texture2D(uSrc, vUv + vec2(-t.x, -t.y)).rgb), b = lum(texture2D(uSrc, vUv + vec2(0., -t.y)).rgb), d = lum(texture2D(uSrc, vUv + vec2(t.x, -t.y)).rgb), e = lum(texture2D(uSrc, vUv + vec2(-t.x, 0.)).rgb), f = lum(texture2D(uSrc, vUv + vec2(t.x, 0.)).rgb), g = lum(texture2D(uSrc, vUv + vec2(-t.x, t.y)).rgb), h = lum(texture2D(uSrc, vUv + vec2(0., t.y)).rgb), i = lum(texture2D(uSrc, vUv + vec2(t.x, t.y)).rgb);
      float gx = (d + 2. * f + i) - (a + 2. * e + g), gy = (g + 2. * h + i) - (a + 2. * b + d), ed = clamp(length(vec2(gx, gy)) * 3., 0., 1.);
      vec3 hue = c / max(max(c.r, max(c.g, c.b)), .05);
      col = mix(c, hue * ed * 2.2 + c * .04, uVec);
    }
    if (uAsc > .001) {
      vec2 px = vUv * uRes, cid = floor(px / uCell), fr = fract(px / uCell), cuv = (cid + .5) * uCell / uRes, o = vec2(.25) * uCell / uRes;
      vec3 sc = (texture2D(uSrc, cuv - o).rgb + texture2D(uSrc, cuv + o).rgb + texture2D(uSrc, cuv + vec2(o.x, -o.y)).rgb + texture2D(uSrc, cuv + vec2(-o.x, o.y)).rgb) * .25;
      float L = clamp(lum(sc) * 1.5, 0., 1.), n = floor(L * 5.); vec2 q = fr - .5; float gl = 0., ax = abs(q.x), ay = abs(q.y), m = max(ax, ay);
      if (n == 1.) gl = step(length(q), .13);
      else if (n == 2.) gl = max(step(length(q - vec2(0., .2)), .1), step(length(q + vec2(0., .2)), .1));
      else if (n == 3.) gl = step(min(ax, ay), .08) * step(m, .36);
      else if (n == 4.) gl = step(abs(ax - ay), .1) * step(m, .4);
      else if (n >= 5.) gl = step(m, .42);
      col = mix(col, sc * 1.9 * gl + sc * .03, uAsc);
    }
    gl_FragColor = vec4(col, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }` });
try { const pm = qMesh.material; qMesh.material = lookM; renderer.compile(qScene, qCam); qMesh.material = pm; } catch (e) { }          // (compile the look shader now, so the first molecule moment does not stall)
function lookStep() { const now = performance.now(), dt = Math.min(.1, (now - LOOK.t) / 1000); LOOK.t = now; LOOK.pv = Math.max(0, LOOK.pv - dt / (LOOK.dur || .4)); LOOK.pa = Math.max(0, LOOK.pa - dt / (LOOK.dur || .4)); const k = 1 - Math.exp(-dt / .45); LOOK.vec += (Math.max(0, Math.min(1, sp('vector', 0))) - LOOK.vec) * k; LOOK.asc += (Math.max(0, Math.min(1, sp('ascii', 0))) - LOOK.asc) * k; LOOK.ev = Math.max(LOOK.vec, Math.sin(Math.PI * Math.min(1, LOOK.pv)) * .7 * sp('flash', 1)); LOOK.ea = Math.max(LOOK.asc, Math.sin(Math.PI * Math.min(1, LOOK.pa)) * .7 * sp('flash', 1)); if (LOOK.vec < .004) LOOK.vec = Math.max(0, sp('vector', 0)) > 0 ? LOOK.vec : 0; if (LOOK.asc < .004) LOOK.asc = Math.max(0, sp('ascii', 0)) > 0 ? LOOK.asc : 0; }
const sharpAmt = () => { const d = Math.min(1, (PW * PHt) / 1.2e6);          /* the fewer pixels the picture has, the more it is sharpened */ return Math.max(0, sp('sharpen', 0)) * Math.min(1.6, .3 + 1.4 * (1 - Math.min(1, d))); };
// HEAD-COUPLED VIEW (&hcp): the screen is a window. Where your head is (sideways and up/down in the camera picture) moves the camera a little the same way and skews the view so a plane
// at hcpz metres stays put: things nearer than that shift against you, things farther shift with you (parallax), the way a real window does. &hcpk = how many metres of camera per full camera-picture
// width of head movement (default 8), &hcpz = the distance that stays still (default 10), &hcpy = up/down strength (default 0.6), &hcpflip=1 reverses left/right if it feels wrong.
const HCPK0 = 3;          /* phones and tablets: a gentler window effect by default */
const HCP = { on: false, k: parseFloat(Q.get('hcpk') || '8'), z: parseFloat(Q.get('hcpz') || '10'), y: parseFloat(Q.get('hcpy') || '.6'), sx: Q.has('hcpflip') ? -1 : 1, rx: null, ry: null, x: 0, yv: 0, t: 0, ox: 0, oy: 0, saved: null };
function hcpApply() {
  HCP.k = sp('hcpk', HCPK0); HCP.z = sp('hcpz', 10); HCP.y = sp('hcpy', .6); HCP.sx = sp('hcpflip', 0) ? -1 : 1;
  const trk = window.__trk, now = performance.now(), dt = Math.min(.1, (now - (HCP.t || now)) / 1000); HCP.t = now;
  if (trk && trk.face && HD.cur && !HD.lost) { const vx = HD.cur[2] / 100, vy = trk.feat ? trk.feat[6] : 0; if (HCP.rx === null) { HCP.rx = vx; HCP.ry = vy; } const a = 1 - Math.exp(-dt / 8); HCP.rx += (vx - HCP.rx) * a; HCP.ry += (vy - HCP.ry) * a; const tx = -(vx - HCP.rx) * HCP.k * HCP.sx, ty = -(vy - HCP.ry) * HCP.k * HCP.y;
    if (HCP.lt !== HD.t) { const dtr = Math.max(.01, (HD.t - (HCP.lt || HD.t - 60)) / 1000); HCP.evx = (HCP.evx || 0) + (((tx - (HCP.ltx === undefined ? tx : HCP.ltx)) / dtr) - (HCP.evx || 0)) * .5; HCP.evy = (HCP.evy || 0) + (((ty - (HCP.lty === undefined ? ty : HCP.lty)) / dtr) - (HCP.evy || 0)) * .5; HCP.ltx = tx; HCP.lty = ty; HCP.lt = HD.t; }
    const calm = Math.max(0, Math.min(1, sp('m_calm', .4))), fc0 = sp('hcpfc', 1.2 - .95 * calm), bt = sp('hcpbeta', 18), ax = 1 / (1 + 1 / (2 * Math.PI * (fc0 + bt * Math.abs(HCP.evx || 0)) * Math.max(dt, .001))), ay = 1 / (1 + 1 / (2 * Math.PI * (fc0 + bt * Math.abs(HCP.evy || 0)) * Math.max(dt, .001)));
    HCP.x += (tx - HCP.x) * ax; HCP.yv += (ty - HCP.yv) * ay; }
  else { const b = 1 - Math.exp(-dt / .3); HCP.x += (0 - HCP.x) * b; HCP.yv += (0 - HCP.yv) * b; }
  const e = camera.projectionMatrix.elements; HCP.saved = { px: camera.position.x, py: camera.position.y, pz: camera.position.z, e8: e[8], e9: e[9] };
  camera.updateMatrixWorld(); camera.translateX(HCP.x); camera.translateY(HCP.yv);
  e[8] = -HCP.x * e[0] / HCP.z; e[9] = -HCP.yv * e[5] / HCP.z; camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
}
function hcpRestore() { const sv = HCP.saved; if (!sv) return; camera.position.set(sv.px, sv.py, sv.pz); const e = camera.projectionMatrix.elements; e[8] = sv.e8; e[9] = sv.e9; camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert(); camera.updateMatrixWorld(); }
function renderScene() { HCP.on = Q.has('head') && sp('hcp', Q.has('hcp') ? 1 : 0) > 0; if (!HCP.on) { renderer.render(scene, camera); return; } hcpApply(); renderer.render(scene, camera); hcpRestore(); }
function renderPost() {
  if (!POST_ON) { renderScene(); return; }
  renderer.setRenderTarget(rtScene); renderScene();
  if (MSAA_CHECK > 0) { MSAA_CHECK--; if (rtScene.samples > 0 && _gl.checkFramebufferStatus(_gl.FRAMEBUFFER) !== _gl.FRAMEBUFFER_COMPLETE) { setSamples(0); GOV.log.push('msaa target incomplete: off'); } }          // (a phone whose GPU cannot multisample a half-float target falls back to none instead of a black screen)
  const src = ping ? rtB : rtA, dst = ping ? rtA : rtB; ping ^= 1; qMesh.material = feedM; feedM.uniforms.uScene.value = rtScene.texture; feedM.uniforms.uPrev.value = src.texture; renderer.setRenderTarget(dst); renderer.render(qScene, qCam);
  const useGlow = GLOWQ.on && ENV && ENV.glow_enabled !== false && GL.intensity > 0;
  if (useGlow) {          // Godot's glow: bright pass into 1/4 resolution (4x4 box), then 1/8 and 1/16 (each a 4x4 box of the one before)
    qMesh.material = brightM; brightM.uniforms.uSrc.value = rtScene.texture; brightM.uniforms.uTexel.value.set(1 / PW, 1 / PHt); brightM.uniforms.thr.value = GL.thr; brightM.uniforms.scl.value = GL.scale; brightM.uniforms.bloom.value = GL.bloom; brightM.uniforms.expo.value = renderer.toneMappingExposure; renderer.setRenderTarget(rtG4); renderer.render(qScene, qCam);
    qMesh.material = downM; downM.uniforms.uSrc.value = rtG4.texture; downM.uniforms.uTexel.value.set(1 / Math.max(2, PW >> 2), 1 / Math.max(2, PHt >> 2)); renderer.setRenderTarget(rtG8); renderer.render(qScene, qCam);
    downM.uniforms.uSrc.value = rtG8.texture; downM.uniforms.uTexel.value.set(1 / Math.max(2, PW >> 3), 1 / Math.max(2, PHt >> 3)); renderer.setRenderTarget(rtG16); renderer.render(qScene, qCam);
    postM.uniforms.gA.value = rtG4.texture; postM.uniforms.gB.value = rtG8.texture; postM.uniforms.gC.value = rtG16.texture;
  }
  postM.uniforms.glowI.value = useGlow ? GL.intensity : 0; postM.uniforms.exposure.value = renderer.toneMappingExposure;
  qMesh.material = postM; postM.uniforms.screen_tex.value = rtScene.texture; postM.uniforms.trail.value = dst.texture; const shAmt = sharpAmt(); lookStep(); const lookOn = LOOK.ev > .004 || LOOK.ea > .004;
 if (lookOn) { renderer.setRenderTarget(rtSharp); renderer.render(qScene, qCam); qMesh.material = lookM; const lu = lookM.uniforms; lu.uSrc.value = rtSharp.texture; lu.uTexel.value.set(1 / PW, 1 / PHt); lu.uRes.value.set(PW, PHt); lu.uCell.value = Math.max(6, Math.round(PW / 110)); lu.uVec.value = LOOK.ev; lu.uAsc.value = LOOK.ea; renderer.setRenderTarget(null); renderer.render(qScene, qCam); }
 else if (shAmt > .03) { renderer.setRenderTarget(rtSharp); renderer.render(qScene, qCam); qMesh.material = sharpM; sharpM.uniforms.uSrc.value = rtSharp.texture; sharpM.uniforms.uTexel.value.set(1 / PW, 1 / PHt); sharpM.uniforms.uAmt.value = Q.has('sharpdbg') ? 0 : shAmt; renderer.setRenderTarget(null); renderer.render(qScene, qCam); }
 else { renderer.setRenderTarget(null); renderer.render(qScene, qCam); }
}
// QUALITY GOVERNOR: the picture steps down by itself, one notch at a time, whenever the frame time stays over ~21 ms (below 48 fps): glow off, then fewer MSAA samples, then a lower render resolution. (Godot's own tiers do the same, Lighting.gd: glow off at tier 2, the colour adjustment at tier 1.) ?nogov turns it off.
const GOV = { on: !Q.has('nogov') && !Q.has('shot'), ema: 16.7, lastNow: 0, since: performance.now() + 2500, step: 0, log: [] };
function setSamples(n) { if (!MSAA_OK) return; rtScene.samples = n; GLOWQ.samples = n; rtScene.dispose(); }
function setDpr(r) { renderer.setPixelRatio(Math.min(r, window.devicePixelRatio || 1)); resize(); }          // never above the screen's own resolution: rendering at 1.5x (2.25x the pixels) stalled integrated graphics and lost the graphics context
const GOV_STEPS = [['glow off', () => { GLOWQ.on = false; }], ['msaa 2', () => setSamples(2)], ['dpr 1.25', () => setDpr(1.25)], ['msaa off', () => setSamples(0)], ['dpr 1.0', () => setDpr(1.0)], ['dpr 0.85', () => setDpr(.85)]];
if (Q.has('px')) window.__PXB = parseFloat(Q.get('px')) * 1e6;          /* &px=0.6: the picture is drawn with at most 0.6 million pixels (the game's quality control stays under it) */
const TIERS = (!Q.has('oldgov') && !Q.has('nogov') && !Q.has('shot')) ? createTiers({ allowDown: () => !window.__DRS || !window.__DRS.on || window.__DRS.atFloor(), isTouch: matchMedia('(pointer:coarse)').matches, weakGpu: detectWeakGpu(_gl), isWeb: true, pin: Q.has('tier') ? +Q.get('tier') : null, dpr: () => window.devicePixelRatio || 1, cssSize: () => [innerWidth, innerHeight],
  hooks: { setGlow: (on) => { window.__dm && window.__dm('TIER hook: glow ' + on); GLOWQ.on = on; }, setSamples: (n) => { window.__dm && window.__dm('TIER hook: msaa samples ' + n); setSamples(n); }, setPixelRatio: (r) => { window.__dm && window.__dm('TIER hook: pixel ratio ' + r); setDpr(r); }, setStreamWindow: (a, b) => { RS.ahead = Math.max(6, a); RS.behind = b; }          /* never fewer than six rows ahead: a quality level used to cut it to three, and the road ahead was blank */ } }) : null;
if (TIERS) GOV.on = false; window.__tiers = TIERS;          // Lighting.gd's tiers and speed governor (tiers.js): checked every 2 s, down after 3 s under 50 fps, up after 16 s over 55; ?tier=N pins, ?oldgov the earlier stepper
let tLast = 0;
function govTick(now) {
  if (TIERS) { if (!document.hidden && tLast && now - tLast < 200) { TIERS.frame((now - tLast) / 1000); drsFrame((now - tLast) / 1000); } tLast = now; return; }
  if (!GOV.on || document.hidden) { GOV.lastNow = now; return; } const d = GOV.lastNow ? now - GOV.lastNow : 16.7; GOV.lastNow = now; if (d > 200) return;
  GOV.ema += (Math.min(d, 60) - GOV.ema) * .04; if (now < GOV.since || GOV.step >= GOV_STEPS.length) return;
  if (GOV.ema > 21) { const st2 = GOV_STEPS[GOV.step++]; st2[1](); GOV.log.push(st2[0] + ' @' + Math.round(GOV.ema) + 'ms'); GOV.since = now + 3000; GOV.ema = 16.7; }
}
function resize() { const w = innerWidth, h = innerHeight; renderer.setSize(w, h, false); sizePost(Math.floor(w * renderer.getPixelRatio()), Math.floor(h * renderer.getPixelRatio())); camera.aspect = w / h; camera.updateProjectionMatrix(); }
// DYNAMIC RESOLUTION (&nodrs turns it off; &px=N fixes it): the game keeps itself at 60 fps by changing how many pixels it draws, on any device. Every second it looks at the frame rate:
// under 55 fps it draws fewer pixels at once (by how far it is under), at a steady 60 for six seconds it tries a few percent more (never more than it just failed at, for 20 s), and only when it is
// already at the smallest picture does the old quality control start switching effects off. It starts a little under the device's ceiling (a phone about 1 million pixels, a weak laptop 1.2 million, a
// good one 2.1 million) and finds its own level, so a ten-year-old phone ends up with a smaller, softer picture and a smooth game instead of a sharp slideshow.
const DRS = window.__DRS = { on: !!TIERS && !Q.has('nodrs') && !Q.has('px'), px: 0, max: 0, floor: .22e6, lim: 1e12, t: 0, f: 0, good: 0, hold: 0, changes: 0, atFloor: () => DRS.px <= DRS.floor * 1.08 };
if (DRS.on) { const o0 = window.__PXB; window.__PXB = 0; DRS.max = pixelBudget(matchMedia('(pointer:coarse)').matches, detectWeakGpu(_gl)); window.__PXB = o0; DRS.px = DRS.max * .75; window.__PXB = DRS.px; }
function drsFrame(dt) {
  if (!DRS.on || document.hidden || st.paused) return; if (dt > .004) DRS.minDt = Math.min(DRS.minDt || 1, dt); DRS.age = (DRS.age || 0) + dt; DRS.t += dt; DRS.f++; if (DRS.t < 1) return; const fps = DRS.f / DRS.t; DRS.t = 0; DRS.f = 0; const TG = Math.max(24, Math.min(75, sp('fpstarget', 60), DRS.age > 4 && DRS.minDt ? (1 / DRS.minDt) * .98 : 75));          /* never aim above what the screen can show: a display that only refreshes 30 or 45 times a second is not a reason to blur the picture */
  if (DRS.age < 10) { DRS.t = 0; DRS.f = 0; return; } DRS.cool = Math.max(0, (DRS.cool || 0) - 1); const apply = (why) => { DRS.cool = 3; window.__PXB = DRS.px; DRS.changes++; try { TIERS.apply(); } catch (e) { } try { window.__dm && window.__dm('drs ' + why + ' ' + (DRS.px / 1e6).toFixed(2) + 'M px at ' + Math.round(fps) + ' fps'); } catch (e) { } };
  if (fps < TG - 5) { DRS.good = 0; const nx = Math.max(DRS.floor, DRS.px * Math.max(.72, Math.min(.93, fps / TG))); if ((DRS.cool || 0) <= 0 && nx < DRS.px * .94) { DRS.lim = DRS.px; DRS.px = nx; DRS.hold = 20; apply('down'); } }
  else if (fps >= TG - 1.5) { DRS.good++; DRS.hold = Math.max(0, DRS.hold - 1); DRS.lim *= 1.02; if (DRS.good >= 6 && DRS.hold <= 0 && DRS.px < DRS.max * .995) { const nx = Math.min(DRS.max, DRS.px * 1.07); DRS.good = 0; if (nx < DRS.lim * .97) { DRS.px = nx; apply('up'); } } }
  else DRS.good = 0;
}
addEventListener('resize', resize); resize(); if (TIERS) { TIERS.apply(); if (Q.has('tier')) TIERS.setTier(+Q.get('tier')); if (Q.has('msaa')) setSamples(+Q.get('msaa')); }          // (a pinned tier or ?msaa=N is applied before the first draw too)          // the quality tier is applied once, here, before anything is drawn (it used to be applied during the first frames, while the shaders were still compiling)
let last = performance.now(), fps = 0, acc = 0, frames = 0;
const SHOT = Q.has('shot') ? lvl.shots[parseInt(Q.get('shot'), 10) || 0] : null;
if (SHOT) { st.paused = true; const img = document.createElement('img'); img.src = './shots/godot_' + String(SHOT.i).padStart(2, '0') + '.png'; img.id = 'ref'; img.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;object-fit:fill;opacity:' + (Q.get('ref') || '0') + ';pointer-events:none;z-index:4'; document.body.appendChild(img); addEventListener('keydown', (e) => { if (e.key === 'g') img.style.opacity = img.style.opacity === '1' ? '0' : (img.style.opacity === '0.5' ? '1' : '0.5'); }); camera.fov = SHOT.fov; }

// ---------------------------------------------------------------- HEAD STEERING (?head): the tracker's yaw / roll / sideways face position, self-calibrated exactly as in main.js (online PCA axis, median = straight ahead, 90th percentile = a full turn, one-euro filter)
const MIXS = Q.get('mix') === 'split';          /* &mix=split: the head TURN does the gentle part of the reach and the sideways LEAN adds the far reaches (from the steering lab) */
const HD = { on: Q.has('head'), cur: null, fb: [], ax: [.577, -.577, .577], ax0: [.577, -.577, .577], neu: 0, k: .9, cal: false, ramp: 0, lastFit: 0, vs: 0, vel: 0, s: 0, fc: sp('fc', 1.1), beta: sp('beta', 6), lead: sp('lead', .03), flip: 1, dead: .03, gain: sp('gain', .7), lost: true, t: 0 };
// TURNING THE PHONE: when the screen goes between portrait and landscape the way you hold the phone changes, so the neutral and the head axes are learned again (about a second of looking straight ahead, steering is still until then). &norot turns it off.
{ let wasL = innerWidth > innerHeight, tm = 0; const re = () => { const isL = innerWidth > innerHeight; if (isL === wasL) return; wasL = isL; if (Q.has('norot') || !HD.on) return; HD.fb = []; HD.cal = false; HD.frozen = false; HD.nT = undefined; HD.nL = undefined; HD.s = 0; HD.vs = 0; HD.ramp = 0; try { toast('SCREEN TURNED: LOOK STRAIGHT AHEAD FOR A MOMENT', '#6df'); } catch (e) { } }; const q = () => { clearTimeout(tm); tm = setTimeout(re, 400); }; addEventListener('resize', q); try { screen.orientation && screen.orientation.addEventListener('change', q); } catch (e) { } }
const HN3 = [8, 5, 3.5], hproj = (v) => (v[0] * HD.ax[0] + v[1] * HD.ax[1] + v[2] * HD.ax[2]) / (Math.abs(HD.ax[0]) + Math.abs(HD.ax[1]) + Math.abs(HD.ax[2]));
function hfit() {
  const fb = HD.fb, n = fb.length; if (n < 20) return;
  if (sp('splitmix', MIXS ? 1 : 0) > 0) { const med = (i) => { const a = fb.map((v) => v[i] * HN3[i]).sort((x, y) => x - y); return a[Math.floor(a.length / 2)]; }, mT = med(0), mL = med(2); if (HD.nT === undefined) { HD.nT = mT; HD.nL = mL; } if (HD.frozen) { if (Math.abs(HD.s) < .1) { HD.nT += (mT - HD.nT) * .03; HD.nL += (mL - HD.nL) * .03; } } else { HD.nT = n < 40 ? mT : HD.nT + (mT - HD.nT) * .25; HD.nL = n < 40 ? mL : HD.nL + (mL - HD.nL) * .25; } HD.cal = true; return; }          /* split: the neutral of the turn and of the lean are measured separately */
  const mean = [0, 0, 0]; for (const v of fb) for (let i = 0; i < 3; i++) mean[i] += v[i] / n; let ax = HD.ax0.slice();
  if (n >= 150) { const Cv = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]; for (const v of fb) for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) Cv[i][j] += (v[i] - mean[i]) * (v[j] - mean[j]) / n;
    let a = [1, 1, 1]; for (let it = 0; it < 14; it++) { const b = [0, 1, 2].map((i) => Cv[i][0] * a[0] + Cv[i][1] * a[1] + Cv[i][2] * a[2]); const m = Math.hypot(...b) || 1; a = b.map((x) => x / m); }
    let d = a[0] * HD.ax0[0] + a[1] * HD.ax0[1] + a[2] * HD.ax0[2]; if (d < 0) { a = a.map((x) => -x); d = -d; } if (d > .5) ax = a; }
  if (!HD.frozen || sp('axisfree', 0) > 0) { HD.ax = HD.ax.map((x, i) => x * .7 + ax[i] * .3); const m = Math.hypot(...HD.ax); HD.ax = HD.ax.map((x) => x / m); }
  const pr = fb.map(hproj).sort((x, y) => x - y), med = pr[Math.floor(pr.length / 2)], dev = pr.map((x) => Math.abs(x - med)).sort((x, y) => x - y), q90 = dev[Math.floor(dev.length * .9)];
  if (HD.frozen) { if (Math.abs(HD.s) < .1) HD.neu += (med - HD.neu) * .03; } else { HD.neu = n < 40 ? med : HD.neu + (med - HD.neu) * .25; HD.k = HD.k + (.9 / Math.max(.3, Math.min(2.5, q90)) - HD.k) * (n < 40 ? 1 : .25); } HD.cal = true;          /* the neutral and the gain are now measured from you */
}
// ---- THE START: READY (looking for you) -> SET (tracking confirmed, you are centred) -> GO! The board waits at the line, nothing steers or moves until GO, and GO is the same moment steering becomes live.
const START = { state: 'idle', hold: false, t: 0, ok: 0 };
const STARTUI = (() => { const d = document.createElement('div'); d.style.cssText = 'position:fixed;left:0;right:0;top:30%;text-align:center;pointer-events:none;z-index:9;color:#fff;opacity:0;transition:opacity .2s,transform .2s;transform:scale(.85)'; const w = document.createElement('div'), sub = document.createElement('div'); w.style.cssText = 'font:800 64px/1 system-ui,Segoe UI,sans-serif;letter-spacing:.2em;padding-left:.2em;text-shadow:0 0 18px #c6f,0 0 40px #c6f,0 3px 0 rgba(0,0,0,.4)'; sub.style.cssText = 'font:700 15px system-ui,Segoe UI,sans-serif;letter-spacing:.18em;margin-top:16px;text-transform:uppercase;text-shadow:0 0 8px #000'; d.append(w, sub); document.body.appendChild(d); let cur = '';
  return { show(word, line) { if (word !== cur) { cur = word; w.textContent = word; d.style.transform = 'scale(1.15)'; requestAnimationFrame(() => { d.style.transform = 'scale(1)'; }); } sub.textContent = line || ''; d.style.opacity = 1; }, hide() { d.style.opacity = 0; cur = ''; } }; })();
function startHold(dt) {
  if (!PH.ready) { PH.x = 0; PH.z = st.z; PH.y = th(0, PH.z); PH.gh_prev = PH.y; PH.prevZ = PH.z; PH.ready = true; }          // the board waits at the line with the world around it, not at the origin in the dark
  rowsUpdate(PH.z); headStep(dt, performance.now()); HD.ramp = 0; if (performance.now() - HD.t > 600) HD.lost = true; pumpBuild(BQ.length > 300 ? 10 : 4);
  const tracking = HD.on && HD.cal && HD.fb.length >= 12 && !HD.lost, centred = Math.abs(HD.s) < .28; START.t += dt;
  if (START.state === 'ready') { STARTUI.show('READY', tracking ? 'keep your head straight: calibrating' : 'looking for your face...'); if (tracking && START.t > sp('rdy1', .4)) START.ok += dt; else START.ok = 0; if (START.ok > sp('rdy2', .3)) { START.state = 'set'; START.t = 0; } }
  else if (START.state === 'set') { STARTUI.show('SET', 'hold it right there'); if (!tracking) { START.state = 'ready'; START.t = 0; START.ok = 0; } else if (START.t > sp('set1', .4) && centred) { START.state = 'go'; START.t = 0; START.hold = false; PH.vz = Math.min(PH.vz, -sp('launch', 36) * SPK); PH.boost_t = Math.max(PH.boost_t, 3); PH.vxa = Math.max(PH.vxa, 1.2); toast('GO!', '#fc8'); HD.ramp = 0; try { window.__recentreNow && window.__recentreNow(); } catch (e) { } HD.frozen = true; HD.k = Math.max(.5, Math.min(sp('kmax', .85), HD.k)) * parseFloat(Q.get('hk') || '1');          /* the log showed k at its old maximum (1.3) and full lock at only 5-9 degrees of head turn: the total sensitivity (k x gain) is now about half */ LANE.x = null; STARTUI.show('GO!', ''); } }
}
let CALMSG = null; function calMsg(on) { if (on && !CALMSG) { CALMSG = document.createElement('div'); CALMSG.style.cssText = 'position:fixed;left:0;right:0;bottom:16%;text-align:center;color:#fff;font:800 18px system-ui,Segoe UI,sans-serif;letter-spacing:.16em;text-transform:uppercase;text-shadow:0 0 10px #000,0 0 3px #000;pointer-events:none;z-index:8'; CALMSG.textContent = 'look straight ahead'; document.body.appendChild(CALMSG); } else if (!on && CALMSG) { CALMSG.remove(); CALMSG = null; } }

const SL = { t0: 0, frames: 0, sum2: 0, jumps: 0, maxStep: 0, last: 0, lock: 0, centre: 0, trkN: 0, ref: null, rawStep: 0, lastYaw: 0, minU: 9, maxU: -9, hs: 0, hd: 0, hd2: 0, le: 0, nc: 0 };
function SLOG(u, o) {          // STEER LOG: every 2 s: the tracker's own rate and biggest step, how often the output jumped more than 0.2 in one frame, how often it sat at full lock, and how often your head was near the middle
  if (!window.__dm) return; const now = performance.now(); if (!SL.t0) SL.t0 = now; SL.frames++; SL.sum2 += o * o; const st = Math.abs(o - SL.last); if (st > .2) SL.jumps++; if (st > SL.maxStep) SL.maxStep = st; SL.last = o; if (Math.abs(o) > .95) SL.lock++; if (Math.abs(HD.s) < .1) { SL.centre++; SL.nc++; SL.hs += HD.s; const hd = Math.atan2(PH.vx, -PH.vz) * 57.2958; SL.hd += hd; SL.hd2 += Math.abs(hd); if (typeof LANE !== 'undefined' && LANE.x !== null) SL.le += LANE.x - PH.x; }          /* head near the middle: the average sign and size of the head signal, the board's heading (degrees, + = toward +x) and how far the board is from where it is aiming */ if (u < SL.minU) SL.minU = u; if (u > SL.maxU) SL.maxU = u;
  if (HD.cur && SL.ref !== HD.cur) { SL.ref = HD.cur; SL.trkN++; const d = Math.abs(HD.cur[0] - SL.lastYaw); if (d > SL.rawStep) SL.rawStep = d; SL.lastYaw = HD.cur[0]; }
  if (now - SL.t0 > 2000) { window.__dm('steer 2s: frames ' + SL.frames + ' trackerUpdates ' + SL.trkN + ' rawYaw ' + (HD.cur ? HD.cur[0].toFixed(1) : '-') + ' maxYawStep ' + SL.rawStep.toFixed(2) + ' deg | out rms ' + Math.sqrt(SL.sum2 / SL.frames).toFixed(2) + ' maxStep ' + SL.maxStep.toFixed(2) + ' jumps>0.2 ' + SL.jumps + ' atLock ' + SL.lock + ' headNearMiddle ' + SL.centre + ' u range ' + SL.minU.toFixed(2) + '..' + SL.maxU.toFixed(2) + ' k ' + HD.k.toFixed(2) + ' gain ' + HD.gain.toFixed(2) + ' | head near middle (' + SL.nc + ' frames): mean head signal ' + (SL.nc ? (SL.hs / SL.nc).toFixed(3) : '-') + ' mean heading ' + (SL.nc ? (SL.hd / SL.nc).toFixed(2) : '-') + ' deg, mean |heading| ' + (SL.nc ? (SL.hd2 / SL.nc).toFixed(2) : '-') + ' deg, mean aim-minus-board ' + (SL.nc ? (SL.le / SL.nc).toFixed(2) : '-') + ' m'); SL.hs = 0; SL.hd = 0; SL.hd2 = 0; SL.le = 0; SL.nc = 0; SL.t0 = now; SL.frames = 0; SL.sum2 = 0; SL.jumps = 0; SL.maxStep = 0; SL.lock = 0; SL.centre = 0; SL.trkN = 0; SL.rawStep = 0; SL.minU = 9; SL.maxU = -9; }
}
function headStep(dt, now) {
  if (HD.on && HD.fb.length >= 12 && now - HD.lastFit > 500) { HD.lastFit = now; hfit(); }          // (the first fit finds your neutral: steering waits for it, then eases in)
  if (!HD.on || !HD.cur || HD.fb.length < 12 || !HD.cal) { window.__steer = 0; HD.ramp = 0; return; }
  if (HD.wasLost && !HD.lost) { HD.vel = 0; HD.s = 0; HD.vs = 0; HD.ramp = 0; } HD.wasLost = HD.lost;
  HD.ramp = Math.min(1, HD.ramp + dt / (HD.lost ? .5 : .8));
  const nv = [HD.cur[0] / HN3[0], HD.cur[1] / HN3[1], HD.cur[2] / HN3[2]]; let pr = hproj(nv); if (HD.gT !== HD.t) { const dtg = (HD.t - (HD.gT0 || HD.t - 60)) / 1000; if (HD.gPr !== undefined && dtg > .004 && Math.abs(pr - HD.gPr) / dtg > 14) HD.glitchT = now; HD.gPr = pr; HD.gT0 = HD.t; HD.gT = HD.t; } if (HD.lost || now - HD.t > 250) HD.glitchT = now;          /* GLITCH FLAG: a reading that jumps farther than a head can move, or a stale/lost one, marks the last 350 ms as "tracking trouble" (used to forgive a graze) */
  if (HD.pT !== HD.t) { const t0 = HD.t, dt0 = (t0 - (HD.pT0 || 0)) / 1000; if (HD.pT0 && dt0 > .004) HD.pvel = (HD.pvel || 0) + (Math.max(-6, Math.min(6, (pr - HD.pPr) / dt0)) - (HD.pvel || 0)) * .5; if (HD.pT0 && dt0 > .004 && HD.cur) { HD.vT = (HD.vT || 0) + (Math.max(-200, Math.min(200, (HD.cur[0] - HD.pY) / dt0)) - (HD.vT || 0)) * .5; HD.vL = (HD.vL || 0) + (Math.max(-100, Math.min(100, (HD.cur[2] - HD.pL) / dt0)) - (HD.vL || 0)) * .5; } if (HD.cur) { HD.pY = HD.cur[0]; HD.pL = HD.cur[2]; } HD.pT = t0; HD.pT0 = t0; HD.pPr = pr; } { const PMS = sp('pred', 130); if (PMS > 0 && !HD.lost) pr += Math.max(-3, Math.min(3, HD.pvel || 0)) * Math.min(.25, (performance.now() - HD.t + PMS) / 1000); }          /* prediction: the reading is about 100 ms old; move to where the head probably is now (speed from the readings' own timestamps) */
  {          /* RE-CENTRING: the middle is not fixed, it follows where your head rests. When the head has been still for a moment and is near the middle, the middle slides to where it is: slowly in normal riding (a few seconds), quickly while the board is held by a ramp, rail or arc or in the air, and for a second and a half after one of those ends (landing, rail end, lip). A head deliberately held well off to one side is never absorbed. &recentre=0 turns it off. */
    const nowT = performance.now(), locked = !!(PH.rail || PH.vlock !== null || !PH.grounded || (typeof toys !== 'undefined' && toys && toys.active && toys.active())), still = Math.abs(HD.pvel || 0) < .3 && !HD.lost && (window.__rot || 0) < 25;
    if (HD._free === false && !locked) HD.recentreUntil = nowT + 1500; HD._free = !locked; HD.stillT = still ? (HD.stillT || 0) + dt : 0;
    const coast = !locked && PH.grounded && Math.abs(PH.x - trailX(PH.z)) < 8 && Math.abs(PH.vx) < 3;          /* the ROAD tells the middle: the board is on the paved line, going straight, nothing holding it. A head that is still and nearly centred then IS straight, so the middle is pulled to it quickly (and the meter goes back to zero). */
    if (sp('recentre', 1) > 0 && HD.frozen && HD.cal && HD.stillT > (coast ? .8 : .6)) {
      const fast = locked || nowT < (HD.recentreUntil || 0), tc = fast ? .5 : (coast ? 1.5 : 3), lim = fast ? .6 : (coast ? .6 : .3), a = 1 - Math.exp(-dt / tc);
      if (sp('splitmix', MIXS ? 1 : 0) > 0 && HD.nT !== undefined) { const sT = -(HD.cur[0] - HD.nT) / sp('turnfull', 10) * .5, sL = -(HD.cur[2] - HD.nL) / Math.max(.5, sp('leanfull', 8)) * .8; if (Math.abs(sT + sL) < lim) { HD.nT += (HD.cur[0] - HD.nT) * a; HD.nL += (HD.cur[2] - HD.nL) * a; } }
      else { const raw = hproj(nv); if (Math.abs((raw - HD.neu) * HD.k) < lim) HD.neu += (raw - HD.neu) * a; }
    }
  }
  let sv = HD.lost ? 0 : -HD.flip * (pr - HD.neu) * HD.k; sv = Math.max(-1.3, Math.min(1.3, sv));
  if (sp('splitmix', MIXS ? 1 : 0) > 0 && HD.nT !== undefined) { const PMS2 = sp('pred', 130), pm = PMS2 > 0 && !HD.lost ? Math.min(.25, (performance.now() - HD.t + PMS2) / 1000) : 0, yaw = HD.cur[0] + (HD.vT || 0) * pm, lean = HD.cur[2] + (HD.vL || 0) * pm, tp = Math.max(-.55, Math.min(.55, -HD.flip * (yaw - HD.nT) / sp('turnfull', 10) * .5)), lr = -HD.flip * (lean - HD.nL), la = Math.max(0, Math.abs(lr) - sp('leandz', 1.2)), lp = Math.sign(lr) * la / Math.max(.5, sp('leanfull', 8)) * .8; sv = HD.lost ? 0 : Math.max(-1.3, Math.min(1.3, (tp + lp) / HD.gain)); }          /* split: the turn gives the first half of the reach (gentle, precise), the lean adds the far reaches */ { const a0 = Math.abs(sv), dz = sp('dz', .015); sv = a0 < dz ? 0 : Math.sign(sv) * (a0 - dz) / (1 - dz) * (1 + dz * .5); }          /* soft dead zone: no jump, so a resting head never drifts the board */
  { const a1 = Math.abs(sv); if (a1 < .1) { const st0 = sp('sticky', .2); sv *= (1 - st0) + st0 * a1 / .1; } }          /* a sticky centre: near straight ahead the signal is damped, so a resting head does not wobble the board */
  { const bw = sp('hyst', .012); if (HD.hold === undefined || HD.lost) HD.hold = sv; const df = sv - HD.hold; if (Math.abs(df) > bw) HD.hold = sv - Math.sign(df) * bw; sv = HD.hold; }          /* a backlash band: head tremor smaller than the band is levelled out (the board holds), a real move passes through at full speed, like resting a hand on a mouse */
  const dv = (sv - HD.vs) / Math.max(dt, .001); HD.vel += (Math.max(-2, Math.min(2, dv)) - HD.vel) * .3; HD.vs = sv; const fc = HD.fc + HD.beta * Math.abs(HD.vel), a = 1 / (1 + 1 / (2 * Math.PI * fc * Math.max(dt, .001))); HD.s += (sv - HD.s) * a;
  { const sw0 = Math.min(1, Math.max(0, (Math.abs(HD.s) - .12) / .25)), swerve = 1 + sp('swerve', .2) * sw0 * Math.min(1, Math.abs(HD.vel) / 2.5), spdK = 1 + sp('spdadapt', 1) * (.12 - .27 * Math.min(1, Math.max(0, (Math.hypot(PH.vx, PH.vz) / SPK - 14) / 40))), u = Math.max(-1, Math.min(1, (HD.s * swerve + HD.vel * HD.lead) * HD.gain * spdK));          /* speed-dependent ratio: a little more sensitive when slow, a little less when fast (about +12% to -15%) */          /* adaptive: slow movements get the fine, low-slope part of the curve; a fast swerve of the head gets up to 45% more gain, so a broad move to a gate is still broad */ const au = Math.abs(u), sF = sp('fine', .9), bd = sp('band', .3), aa = Math.max(.05, Math.min(1.5, sF * (1 - bd) / (1 - sF * bd))), tt = Math.max(0, (au - bd) / (1 - bd)), o = au <= bd ? sF * au : sF * bd + (1 - sF * bd) * (aa * tt + (1 - aa) * tt * tt);          /* VARIABLE RATIO (as steer-by-wire does it): the middle band (+-30% of your range, ?band=) is for fine-tuning toward things already roughly in the path (slope ?fine=0.9, no threshold), beyond it the response steepens smoothly (the slope stays continuous) so a wide turn still reaches full lock */ window.__steer = Math.sign(u) * o * HD.ramp; SLOG(u, o); }          /* a SOFT CENTRE: the middle 30% of your head range is only 35% as strong (a slight correction is a slight correction), then it climbs steeply to full, so the broad moves are still broad */
    { }
}
if (HD.on) {
  const ov = document.createElement('div'); ov.style.cssText = 'position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:transparent;z-index:20;color:#fff;font:700 28px ui-monospace,Consolas,monospace;cursor:pointer;text-align:center'; ov.innerHTML = '<div style="background:#000c;padding:16px 26px;border-radius:18px;border:2px solid #0ff8;box-shadow:0 0 24px #0ff6">TURN YOUR HEAD TO STEER<br><span style="font-size:16px">starting the camera...</span></div>'; st.paused = true; document.body.appendChild(ov);
  const bar = document.createElement('div'); bar.style.cssText = 'position:fixed;left:50%;bottom:30px;width:200px;height:8px;margin-left:-100px;border:1px solid #fff8;z-index:6'; const mk = document.createElement('div'); mk.style.cssText = 'position:absolute;top:-3px;width:6px;height:14px;background:#0ff;left:97px'; bar.appendChild(mk); document.body.appendChild(bar); window.__mk = mk;
  const bringUp = async () => { ov.textContent = 'starting the camera...'; const poll = setInterval(() => { if (ov.isConnected) ov.textContent = 'camera: ' + (window.__gazeStatus || 'starting') + '...'; }, 200); try {
 window.__dm && window.__dm('head overlay: waiting for the tracker'); const { tr, p } = await EARLY;          /* the camera and the tracker were started the moment the page opened, in step with the level loading */

    tr.onSteady = () => { const f = [tr.head ? tr.head.yaw * 57.2958 : 0, tr.head ? tr.head.roll * 57.2958 : 0, (tr.feat ? tr.feat[5] : 0) * 100]; HD.lost = false; { const n0 = performance.now(), g0 = n0 - HD.t; if (HD.t && g0 > 150 && window.__dm) window.__dm('tracker gap ' + Math.round(g0) + ' ms (model ' + Math.round(tr.modelMs) + ', vis ' + document.visibilityState + ')'); HD.t = n0; } HD.cur = HD.cur ? HD.cur.map((c, i) => c + (f[i] - c) * .7) : f; HD.fb.push([f[0] / HN3[0], f[1] / HN3[1], f[2] / HN3[2]]); if (HD.fb.length > 900) HD.fb.shift(); };
    await p; clearInterval(poll); ov.remove(); window.__dm && window.__dm('head overlay removed: READY'); addEventListener('keydown', (e) => { if (e.key === '-' || e.key === '=') { SMOOTHW = Math.max(6, Math.min(40, SMOOTHW * (e.key === '=' ? 1.18 : 1 / 1.18))); toast('SMOOTHNESS ' + SMOOTHW.toFixed(0) + (e.key === '-' ? '  (smoother)' : '  (crisper)'), '#6df'); } if (e.key === '[' || e.key === ']') { AK = Math.max(0, Math.min(2, AK + (e.key === ']' ? .5 : -.5))); toast('GATE ASSIST ' + (AK <= 0 ? 'OFF' : AK < 1 ? 'LOW' : AK < 1.5 ? 'MEDIUM' : 'HIGH'), '#6df'); } if (e.key === ',' || e.key === '.') { HD.gain = Math.max(.6, Math.min(4, HD.gain * (e.key === '.' ? 1.15 : 1 / 1.15))); toast('HEAD SENSITIVITY ' + Math.round(HD.gain / 1.18 * 100) + '%', '#6df'); } if (e.key === 'c' || e.key === 'C') tr.switchCamera().then((l) => toast('CAMERA: ' + l, '#6df')).catch(() => { }); }); setTimeout(() => toast('CAMERA: ' + (tr.camLabel || '?') + '  |  found: ' + ((tr.cams || []).map((c) => c.label).join(' / ') || 'none') + '  (C switches)', '#6df'), 600); START.hold = true; START.state = 'ready'; START.t = 0; START.ok = 0; st.paused = false; } catch (e) { const nm = (e && e.name) || '', busy = /NotReadable|AbortError|Could not start/i.test(nm + ' ' + String((e && e.message) || e)); ov.innerHTML = '<div style="background:#000d;padding:16px 26px;border-radius:12px;font-size:20px;line-height:1.5">' + (busy ? 'The camera is busy.<br>Another app still has it (Teams, Zoom, another tab).<br>Quit that app completely, then tap here to retry.' : 'No camera: ' + String((e && e.message) || e).slice(0, 80) + '<br>Tap here to retry.') + '<br><small>(or wait: keys A/D steer)</small></div>'; clearInterval(poll); ov.onclick = () => location.reload(); st.paused = false; } };
  if (TAPCAM) { ov.innerHTML = '<div style="background:#000c;padding:16px 26px;border-radius:18px;border:2px solid #0ff8;box-shadow:0 0 24px #0ff6">TURN YOUR HEAD TO STEER<br><span style="font-size:16px">tap to start (the camera is already warming up)</span><br><span style="font-size:13px;font-weight:500;opacity:.75">best sideways, with headphones; works fine without</span><br><span style="font-size:13px;font-weight:500;opacity:.75">at GO, hold your head straight for a second: it sets your middle</span></div>'; ov.onclick = () => { ov.onclick = null; openTap(); bringUp(); }; } else bringUp();
}
// ---------------------------------------------------------------- PLAY: the board's physics from RunRig._physics_process, literally (hill pull, drag, grip with a carve cost, the steering and heading springs, the caps), plus what the level does to the board:
// trees and rocks (_collide, _crash), pickups (_collect_buffs, _take_buff), boost pads (_update_pads), rails (_feat_tick), and the ramps with their vortex (_update_ramps, _vortex_drive). Speeds are scaled up (?spd=) and the grip tightened (?turn=), everything else is Godot's.
let AK = parseFloat(Q.get('aa') || '.5');          // the strength of the gate assist: 0 off, .5 low, 1 medium (the default), 1.5 high. [ and ] change it while riding
let SMOOTHW = sp('smooth', 12);
const PLAY = Q.has('play'); const K = { l: 0, r: 0 };
const SPK = parseFloat(Q.get('spd') || '1.12'), STK = sp('turn', 4.2);
// ---- ASSISTED STEERING. (Barrier courses, the ones with gates, default to direct steering plus the gate lock-on: there is no single trail to aim around.) 'lane' (the default): the head only SELECTS a lane (left / middle / right, with hysteresis and a dwell before returning to the middle); the board then carves to it on Godot's own pull rule, so tracker jitter cannot shake it. 'free': the head steers directly (?assist=free). Either way the assists (lock-on pull, lane hold, edge push) are low-passed, so they cannot flip the input from one frame to the next.
const ASSIST = Q.get('assist') || (LABS && (LABS.assist === 'aim' || LABS.assist === 'free') ? LABS.assist : null) || (Object.values(lvl.rows || {}).some((r) => r && r.has_row) ? 'free' : 'aim'), LANE = { i: 0, n: 0, x: null }, LANE_W = parseFloat(Q.get('lanew') || '8'), REACH = sp('reach', (lvl.feat_off || 15) < 10 ? 16 : 36); let ASM = 0;          // 'aim' (default): the head aims at a POSITION across the width of the course (full lean = REACH metres off the trail) and the board carves there; 'lane': three fixed lanes; 'free': direct steering
const LANEPIPS = (() => { const d = document.createElement('div'); d.style.cssText = 'position:fixed;left:0;right:0;bottom:9%;display:flex;justify-content:center;gap:14px;pointer-events:none;z-index:5'; d.innerHTML = '<i></i><i></i><i></i>'; for (const e of d.children) e.style.cssText = 'width:10px;height:10px;border-radius:50%;background:#fff3;transition:background .15s,transform .15s'; if (ASSIST === 'lane') document.body.appendChild(d); let last = 9; return (i) => { if (i === last) return; last = i; [...d.children].forEach((e, k) => { const on = k === i + 1; e.style.background = on ? '#fff' : '#fff3'; e.style.transform = on ? 'scale(1.5)' : 'scale(1)'; }); }; })();
const C = { G: 9.8 * SPK, GV: 9.8 * SPK, DRAG: .0024 / SPK, GRIP: 2.6 * STK, THETA_MAX: sp('theta', .62), MIN_SPEED: 14 * SPK, TRAIL_VMAX: 30 * SPK, TRAIL_SPEED: 23.5 * SPK, SPEED_CAP: 57 * SPK * (CHILL ? .6 : 1), SLED_R: 1, W_HALF: Math.min(25 * parseFloat(Q.get('wide') || '1.4') + 4, Math.min((lvl.W_HALF || 58), 138)), PULL_RAMP: 3500, AIR_G_K: 2.1, JUMP_LAUNCH: 11 * SPK, VX_REACH: 130, VX_TRAIL: 37 * SPK, VX_ACCEL: 34 * SPK, JUMP_BLAST: 2, RAIL_H: .9, BOOST_S: 3 };
const PH = { vx: 0, vz: -20, heading: 0, steer: 0, sv: 0, hurt: 0, hits: 0, grounded: true, vy: 0, y: 0, ready: false, x: 0, z: 0, air_t: 0, gh_prev: 0, boost_t: 0, vxa: 0, shield: 0, score: 0, rail: null, rail_dx: 0, rail_z0: 0, rail_py: 0, rail_ok: false, rail_out: 0, rail_sp: 0, prevZ: 0, vx_spin: 0, picks: 0, rails: 0, jumps: 0, pads: 0, vlock: null, slide: 0, chain: 0, chainT: 0, chainBest: 0, landT: 0, mom: 0, grade: 0, lastGh: null, trip: 0, flow: 0, mixAdd: 0, cands: [], latch: null, latchDist: 1e9, mult: 0, vsnd: false };
addEventListener('keydown', (e) => { if (e.key === 'a' || e.key === 'ArrowLeft') K.l = 1; if (e.key === 'd' || e.key === 'ArrowRight') K.r = 1; });
addEventListener('keyup', (e) => { if (e.key === 'a' || e.key === 'ArrowLeft') K.l = 0; if (e.key === 'd' || e.key === 'ArrowRight') K.r = 0; });
function th(x, z) { const g = groundY(x, z); if (g === null) return PH.lastGh === null ? PH.y : PH.lastGh; PH.lastGh = g; return g; }          // (where there is no ground reading, the last one is used: a board must never land on thin air)
const sstep = (a, b, x) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
// ---- the level's data (from the Godot dump)
const nameOf = (s) => String(s).replace(/^<node |>$/g, '');
const NBN = {}; for (const n of lvl.nodes) NBN[n.name] = n; for (const jj of Object.keys(ROWREC)) { if (ROWREC[jj].built >= ROWREC[jj].total) { try { hideDropped(jj); } catch (e) { } } }          // rows built before this point
function hideTarget(o) { if (o.hideSelf) o.hideSelf(); else hideNode(o.n || o.gem); }
function hideNode(name) { const nd = NBN[nameOf(name)]; if (!nd) return; const g = GRP[nd.path]; if (g) g.visible = false; for (const m of (REGN[nd.name] || [])) m.visible = false; }
const ROWS = Object.values(lvl.rows), OGRID = new Map();
for (const r of ROWS) { const o = r.obs || []; for (let i = 0; i + 3 < o.length; i += 4) { const ob = { x: o[i], z: o[i + 1], r: o[i + 2], k: o[i + 3] }; const key = Math.floor(ob.x / 8) + ',' + Math.floor(ob.z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); } }
for (const r of ROWS) for (const t of (r.trees || [])) { const ob = { x: t[0], z: t[1], r: 1.5, k: 0 }; const key = Math.floor(ob.x / 8) + ',' + Math.floor(ob.z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); }
for (const t of TREES.values()) { const ob = { x: t[0], z: t[1], r: 1.5, k: 0 }; const key = Math.floor(ob.x / 8) + ',' + Math.floor(ob.z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); }
OGRID.forEach((a) => { for (let i = a.length - 1; i >= 0; i--) if (a[i].x === 0 && a[i].z === 0) a.splice(i, 1); });          // the dump has a placeholder tree at the exact origin, right where the board starts: it is not a real obstacle (it would have crashed, or spent a saw, at the start of every run)
const BUFFS = ROWS.flatMap((r) => r.buffs || []), PADS = ROWS.flatMap((r) => r.pads || []), FEATS = ROWS.flatMap((r) => r.feats || []), RAILS = FEATS.filter((f) => f.kind === 'rail'), VXS = lvl.vx || [];

// SCARCITY (GAME_SPEC 6 and 17): Godot's generator offers a buff at nearly every opening (about 12 per km); the spec wants boosts 3-4 per km and the other kinds only now and then. Boost buffs stay; the others are kept only if at least 280 m
// beyond the last one kept, in course order. The dropped ones, and the orb trails leading to them, are marked taken (never collected) and hidden when their row is built. ?allbuffs keeps everything.
if (!Q.has('allbuffs')) { let lastZ = 1e9; const sorted = BUFFS.slice().sort((a, b) => b.z - a.z); for (const b of sorted) { if (b.t === 'boost') continue; if (lastZ - b.z >= 280) { lastZ = b.z; continue; } b.thin = true; b.taken = true; for (const o of (b.orbs || [])) o.taken = true; } }

const TX = lvl.trailx || [], FEAT_OFF = lvl.feat_off || 15;
const trailX = (z) => { const i = Math.max(0, -z) / 6, a = Math.min(TX.length - 1, Math.floor(i)), b = Math.min(TX.length - 1, a + 1); return TX.length ? TX[a] + (TX[b] - TX[a]) * (i - a) : 0; };
const featX = (f, z) => f.kx !== undefined ? f.kx + (f.cv ? f.cv(z) : 0) : trailX(z) + f.sd * FEAT_OFF;
const railY = (f, z) => th(featX(f, z), z) + (.15 + (C.RAIL_H - .15) * sstep(0, 4, f.za - z));
// ---- the vortex rings (RunRig._vortex_drive): spin about the ring's own axis, faster the nearer the ramp
const RINGS = []; { const byIid = {}; for (const n of lvl.nodes) byIid[n.iid] = n; for (const v of VXS) for (const r of v.rings) { const nd = byIid[r.iid]; if (!nd) continue; const ms = REGN[nd.name] || []; const e = nd.xf; for (const m of ms) RINGS.push({ m, v, r, p: [e[9], e[10], e[11]] }); } }
let toys = null;
const _mA = new THREE.Matrix4(), _mB = new THREE.Matrix4(), _mS = new THREE.Matrix4();
function ringsTickOld() {
  for (const q of RINGS) {
    const dz = PH.z - q.v.z; if (dz > 260 || dz < -40) continue; const gi = q.r.gi, near = 1 + 2.5 * sstep(90, 10, dz), sg = gi % 2 === 0 ? 1 : -1;
    let ang, sc; if (q.r.R !== undefined) { ang = PH.vx_spin * near * (1.2 + .5 * gi) * sg; sc = [q.r.R, q.r.R, q.r.R * .7]; } else { ang = PH.vx_spin * (2.2 + .7 * gi) * sg; sc = q.r.S || [1, 1, 1]; }
    _mA.makeRotationZ(ang); _mB.makeRotationX(Math.PI * .5); _mS.makeScale(sc[0], sc[1], sc[2]); q.m.matrix.copy(_mA).multiply(_mB).multiply(_mS); q.m.matrix.elements[12] = q.p[0]; q.m.matrix.elements[13] = q.p[1]; q.m.matrix.elements[14] = q.p[2];
  }
}
// ---- the HUD text and sound
const toastEl = document.createElement('div'); toastEl.style.cssText = 'position:fixed;left:0;right:0;top:22%;text-align:center;color:#fff;font:700 34px ui-monospace,Consolas,monospace;text-shadow:0 0 12px #f0f,0 0 4px #000;pointer-events:none;z-index:7;opacity:0;transition:opacity .25s'; document.body.appendChild(toastEl);
let toastT = 0;
const toastBox = document.createElement('div'); toastBox.style.cssText = 'position:fixed;left:0;right:0;top:17%;display:flex;flex-direction:column;align-items:center;gap:6px;pointer-events:none;z-index:7'; document.body.appendChild(toastBox);
{ const st = document.createElement('style'); st.textContent = '@keyframes tpop{0%{opacity:0;transform:translateY(16px) scale(.7)}10%{opacity:1;transform:translateY(0) scale(1.14)}20%{transform:translateY(0) scale(1)}75%{opacity:1;transform:translateY(-5px) scale(1)}100%{opacity:0;transform:translateY(-24px) scale(.96)}}'; document.head.appendChild(st); }
function toast(t, col) {          // popups stack (at most three), an identical one restarts instead of piling up, each one pops in, drifts up and fades
  col = col || '#fff'; const last = toastBox.lastElementChild;
  if (last && last.dataset.t === t && performance.now() - (+last.dataset.at) < 900) { last.style.animation = 'none'; void last.offsetWidth; last.style.animation = 'tpop 1.5s ease-out forwards'; last.dataset.at = performance.now(); return; }
  const el = document.createElement('div'); el.dataset.t = t; el.dataset.at = performance.now(); el.textContent = t;
  el.style.cssText = 'font:800 26px/1 system-ui,Segoe UI,Inter,sans-serif;letter-spacing:.16em;text-transform:uppercase;color:#fff;white-space:nowrap;text-shadow:0 0 6px ' + col + ',0 0 18px ' + col + ',0 0 36px ' + col + ',0 2px 0 rgba(0,0,0,.4);animation:tpop 1.5s ease-out forwards';
  el.addEventListener('animationend', () => el.remove()); toastBox.appendChild(el); while (toastBox.children.length > 3) toastBox.firstElementChild.remove();
}
let AC = null, SFXG = null, grindN = null;
function ac() { if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); SFXG = AC.createGain(); SFXG.gain.value = .5; const lp = AC.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3200; SFXG.connect(lp); lp.connect(AC.destination); } catch (e) { } } if (AC && AC.state === 'suspended') AC.resume(); return AC; }
let SFXM = null; function sfxInit() { if (SFXM || !ac()) return; SFXM = createSfx(() => ac(), SFXG); Object.assign(SFX, SFXM); setTimeout(() => { try { SFXM.preload && SFXM.preload(); } catch (e) { } }, 1500); }
addEventListener('pointerdown', () => { ac(); sfxInit(); gmStart(); }); addEventListener('keydown', () => { ac(); sfxInit(); gmStart(); });
function tone(f0, f1, dur, vol, type) { const a = ac(); if (!a) return; const o = a.createOscillator(), g = a.createGain(); o.type = type || 'sine'; o.frequency.setValueAtTime(f0, a.currentTime); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), a.currentTime + dur); g.gain.setValueAtTime(0, a.currentTime); g.gain.linearRampToValueAtTime(vol, a.currentTime + .015); g.gain.exponentialRampToValueAtTime(.0001, a.currentTime + dur); o.connect(g); g.connect(SFXG); o.start(); o.stop(a.currentTime + dur + .05); }
function noise(dur, vol, f, q) { const a = ac(); if (!a) return null; const n = Math.floor(a.sampleRate * dur), b = a.createBuffer(1, n, a.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; const s = a.createBufferSource(); s.buffer = b; const fl = a.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.value = f; fl.Q.value = q || 1; const g = a.createGain(); g.gain.setValueAtTime(vol, a.currentTime); g.gain.exponentialRampToValueAtTime(.0001, a.currentTime + dur); s.connect(fl); fl.connect(g); g.connect(SFXG); s.start(); return s; }
const SFX = {
  thwack: () => { noise(.25, .9, 500, .8); tone(140, 60, .2, .5); }, gong: () => { tone(220, 215, 1.4, .45); tone(331, 328, 1.1, .2); tone(553, 550, .8, .1); },
  pick: () => { tone(660, 990, .18, .3); setTimeout(() => tone(990, 1320, .2, .25), 70); }, orb: () => tone(880, 1180, .1, .15), pad: () => { tone(200, 900, .35, .35, 'triangle'); noise(.3, .3, 1800, 1.5); },
  land: () => { tone(110, 45, .25, .55); noise(.12, .25, 300, 1); }, blast: () => { tone(120, 700, .5, .45, 'sawtooth'); noise(.5, .5, 1200, .7); tone(60, 40, .6, .5); }, stretch: () => tone(150, 420, 1.1, .22, 'triangle'),
  snap: () => { tone(900, 300, .15, .35, 'square'); noise(.1, .3, 3000, 2); }, hurt: () => { tone(180, 60, .35, .5, 'sawtooth'); }, shield: () => { tone(500, 200, .4, .35); noise(.25, .3, 2500, 2); }, boing: () => tone(250, 520, .25, .3),
  grindOn: () => { const a = ac(); if (!a || grindN) return; const n = a.sampleRate * 1, b = a.createBuffer(1, n, a.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; const s = a.createBufferSource(); s.buffer = b; s.loop = true; const fl = a.createBiquadFilter(); fl.type = 'bandpass'; fl.frequency.value = 2200; fl.Q.value = 3; const g = a.createGain(); g.gain.value = .22; s.connect(fl); fl.connect(g); g.connect(SFXG); s.start(); grindN = { s, g, fl }; },
  grindOff: () => { if (grindN) { try { grindN.g.gain.setTargetAtTime(0, AC.currentTime, .05); grindN.s.stop(AC.currentTime + .3); } catch (e) { } grindN = null; } },
};
toys = createToys({ lvl, PH, th, SPK, hideNode, toast, SFX, REGN, hooks: { pillK: () => (PH.mult > 0 ? sp('pillmagk', 2.6) : sp('pillk', 1.7)), pillPull: () => (PH.mult > 0 ? sp('pillmagr', 30) : sp('pillpull', 9)), onBump: (x, y, z) => { try { FX.E.orb([x, y + 1.5, z]); FX.E.cheer([x, y + 2, z], 0xffcc44, 1); } catch (e) { } try { SFX.pick(); } catch (e) { } toast('BOING!  +80', '#fc6'); PH.boost_t = Math.max(PH.boost_t, .6); shudder(.3); }, lkFree: () => sp('lkfree', 1.4), beatK: () => BEATFX.pulse * BEATFX.k, beatOff: () => { try { if (CHILL || (GM.arc && GM.arc.stage === 'chill')) return 9; const bp = (gmOn && GM.beatPos() > 0) ? GM.beatPos() : U.uTime.value * 128 / 60; return Math.abs(bp - Math.round(bp)) * 60 / 128; } catch (e) { return 9; } }, quant: (f) => { let d = 0; try { if (gmOn && !(CHILL || (GM.arc && GM.arc.stage === 'chill'))) { const bp = GM.beatPos(); if (bp > 0) d = (Math.ceil(bp * 2) / 2 - bp) * 60 / 128; } } catch (e) { } if (d > .02 && d < .26) setTimeout(f, d * 1000); else f(); }, onPill: (t, first, mi) => { try { PSY.events.onMolecule(['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'][mi], t.name); } catch (e) { } } } });
const VFX = createVortexFx({ THREE, scene, lvl, th, PH, SPK, REGN, MAT, rgb, toast, SFX, gain: (n) => { PH.score += n; }, groove: () => (PSY.flow ? PSY.flow.groove : 1), onAirRing: () => { chainHit(); }, onAirChainEnd: (c) => { if (c >= 3) chainHit(); } }); VFX.fixMaterials();
const FX = createFx({ THREE, scene, camera }); const TRB = FX.trailBoost(), TRM = FX.trailMult(), SPRAY = FX.spray(); let railSparkT = 0;

// ---- BUFF AURAS: what is on you is visible. Screen-edge fringe per buff (cyan shield, purple magnet, orange boost, pink wings; they stack) and, for the magnet, waves spreading out over the snow to the edge of the widened grab zone
const AUR = document.createElement('div'); AUR.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:4;transition:box-shadow .25s'; document.body.appendChild(AUR);
let auraKey = '', auraT = 0, magT = 0, lastBeat = -1, ripI = 0; const ripple = (x, z, a) => { U.uRip.value[ripI++ & 3].set(x, z, U.uTime.value, a); };
function auraUpd(dt) {
  auraT += dt; const mg = PH.mult > 0, sh = PH.shield > 0, bo = PH.boost_t > .3, wi = PH.wings > 0, key = (mg ? 'm' : '') + (sh ? 's' : '') + (bo ? 'b' : '') + (wi ? 'w' : '');
  if (key !== auraKey) { auraKey = key; const L = []; if (sh) L.push('inset 0 0 70px 14px rgba(80,220,255,.55)'); if (mg) L.push('inset 0 0 90px 22px rgba(190,90,255,.6)'); if (bo) L.push('inset 0 0 60px 10px rgba(255,150,40,.5)'); if (wi) L.push('inset 0 0 80px 18px rgba(255,120,200,.55)'); AUR.style.boxShadow = L.join(',') || 'none'; }
  AUR.style.opacity = (mg && PH.mult < 2) ? String(.45 + .55 * Math.abs(Math.sin(auraT * 12))) : '1';          // the last two seconds of a buff flicker
  if (Q.has('norip')) return;
  if (mg) { magT -= dt; if (magT <= 0) { magT = .5; ripple(PH.x, PH.z, -1.2); } } else magT = 0;
  const bp0 = (gmOn && GM.beatPos() > 0) ? GM.beatPos() : U.uTime.value * 128 / 60; const bi = Math.floor(bp0); if (bi !== lastBeat && BEATFX.k > 0) { lastBeat = bi; ripple(PH.x, PH.z, (bi % 4 === 0) ? 1.1 : .65); }
}
const CARVE = createCarveTrail({ THREE, scene, th, vxMin: 7 * SPK, size: 2 }), ECHO = createEchoes({ THREE, scene, th, fan: true });
const GM = createGvMusic({ base: '../music/', introSkip: sp('musicskip', 16), stemsOnly: !Q.has('funk') });          /* &musicskip=N: start the intro N bars in (0 = the old quiet build) */ let gmOn = false;
// MUSIC PER BIOME: Alps keeps the adaptive Alien Warfare stems; every other biome plays its own track (a loop, started at a random point so the intro is never the same, faded in). &track=file.ogg forces one, &track=stems the stems.
const BTRACK = { psychedelic: ['electric_exodus.ogg', .85], candy: ['bouncer.ogg', .8], tunnel: ['dnb_minute.ogg', .8], desert: ['funk_express.ogg', .45], matrix: ['moodless_refrain.mp3', .8], synthwave: ['quirky_funk.ogg', .5], alpine: null };
// THE BIOME'S NAME: a big title that fades after about 4 s when the ride starts, a small quiet label at the top centre that stays, the browser tab title, and a line in the pause readout, so the biome you liked can be remembered and found again.
const BIOME_NAME = { psychedelic: 'Trip', alpine: 'Alps', candy: 'Candy Land', tunnel: 'Tunnel', desert: 'Desert', matrix: 'Matrix', synthwave: 'Synthwave' }, BNAME = BIOME_NAME[WORLD_THEME] || WORLD_THEME;
try { document.title = 'Downhill · ' + BNAME; } catch (e) { }
const BTAG = document.createElement('div'); BTAG.textContent = BNAME.toUpperCase(); BTAG.style.cssText = 'position:fixed;left:50%;top:6px;transform:translateX(-50%);z-index:8;padding:3px 12px;border-radius:10px;background:#0005;color:#fff;font:700 11px system-ui,sans-serif;letter-spacing:.3em;opacity:.6;pointer-events:none'; document.body.appendChild(BTAG);
let bannerShown = false; function biomeBanner() { if (bannerShown) return; bannerShown = true; const d = document.createElement('div'); d.textContent = BNAME.toUpperCase(); d.style.cssText = 'position:fixed;left:0;right:0;top:20%;z-index:12;text-align:center;color:#fff;font:800 clamp(30px,7vw,64px) system-ui,sans-serif;letter-spacing:.3em;text-shadow:0 0 18px #fff9,0 0 40px #8cf8;opacity:0;transition:opacity .8s;pointer-events:none'; document.body.appendChild(d); requestAnimationFrame(() => { d.style.opacity = '1'; }); setTimeout(() => { d.style.opacity = '0'; }, 3800); setTimeout(() => d.remove(), 5000); }
function biomeTrack() { const f = Q.get('track'); if (f === 'stems') return null; if (f) return [f, .8]; return BTRACK[WORLD_THEME] || null; }
function startBiomeTrack(tr) { const a = new Audio('../music/' + tr[0]); a.loop = true; a.preload = 'auto'; a.volume = 0; window.__bt = a; let t = 0; const go = () => { try { a.currentTime = Math.random() * Math.max(0, (a.duration || 60) - 25) * .7; } catch (e) { } a.play().then(() => { const iv = setInterval(() => { t += .05; a.volume = Math.min(tr[1], tr[1] * t / 3); if (t >= 3) clearInterval(iv); }, 150); }).catch(() => { }); }; if (a.readyState >= 1) go(); else a.addEventListener('loadedmetadata', go, { once: true }); }
function gmStart() { biomeBanner(); if (gmOn || Q.has('nomusic')) return; const tr = biomeTrack(); if (tr) { if (!window.__bt) { try { startBiomeTrack(tr); } catch (e) { } } return; } gmOn = true; try { GM.start(); } catch (e) { gmOn = false; } }
const AW = createAudioWire({ SFX, GM, PSY });          // every game event -> Godot's sound sequence (audiowire.js); ?oldsfx keeps the earlier one-sound calls
const AWON = !Q.has('oldsfx');
if (!Q.has('noquant')) for (const nm of ['onPickup', 'onMoleculeFound', 'onChain', 'onPadHit', 'onChargedPop', 'onGate', 'onOrb', 'onGlint', 'onCheer', 'onCue']) { const f0 = AW[nm]; if (!f0) continue; AW[nm] = (...a) => { let d = 0; try { if (gmOn && !(CHILL || (GM.arc && GM.arc.stage === 'chill'))) { const bp = GM.beatPos(); if (bp > 0) d = (Math.ceil(bp * 2) / 2 - bp) * 60 / 128; } } catch (e) { } if (d > .02 && d < .26) setTimeout(() => f0(...a), d * 1000); else f0(...a); }; }          // (landing on the half beat: at most a quarter of a second; hits and landings stay instant)
const SBH = document.createElement('div'); SBH.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:6;background:#f00;opacity:0;mix-blend-mode:screen'; SBH.innerHTML = '<div style="position:absolute;left:0;right:0;top:34%;text-align:center;color:#fff;font:700 26px ui-monospace,Consolas,monospace;text-shadow:0 0 10px #000">BOULDER BEHIND YOU</div>'; document.body.appendChild(SBH);
// ---- what hurts, and what helps

// ---------------------------------------------------------------- THE LAB (?lab): cycles effect combinations on the picture, the ground and the trees; the player taps TRIPPY (tap the green button, T or space) or NOPE (red button, X); it learns from the taps (lab.js) and logs every pick
const LABON = Q.has('lab'); let LABV = { fovMul: 1 }; let LAB = null;
if (LABON) {
  const KN = [
    ['amount', .2, 1.6, 1, 'picture-pass strength'], ['breathe', 0, 1.5, 1, 'breathing'], ['k_warp', 0, 3, 1, 'warp'], ['k_pulse', 0, 3, 1, 'pulse'], ['k_chroma', 0, 3, 1, 'colour split'], ['k_trace', 0, 3, 1, 'tracer ghosts'], ['k_punch', 0, 2.5, 1, 'saturation punch'], ['k_wash', 0, 2, 1, 'hue wash'],
    ['mAx', 0, 1, 0, 'warm waves'], ['mAy', 0, 1, 0, 'swell of light'], ['mAz', 0, 1, 0, 'colour split B'], ['mBx', 0, 1, 0, 'ripples'], ['mBy', 0, 1, 0, 'radial warp'], ['mBz', 0, 1, 0, 'pulse B'], ['dmt', 0, 1, 0, 'dmt'], ['buzz', 0, 1, 0, 'buzz'], ['sharp', 0, 1, 0, 'sharp'], ['trip', 0, 1, 0, 'trip'],
    ['glowMul', .5, 3, 1, 'bloom'], ['bloomAdd', 0, .4, 0, 'bloom spread'], ['fogMul', .3, 2.5, 1, 'haze'],
    ['gScale', .5, 3, 1, 'ground grid scale'], ['gRatio', 1.01, 1.14, 1.037, 'moire ratio'], ['gRot', 0, 6, 1, 'moire turning'], ['gSat', .3, 1.2, 1, 'ground saturation'],
    ['vHue', 0, 5, 1, 'tree hue drift'], ['vGlow', .3, 3, 1, 'tree glow'], ['fovMul', .9, 1.25, 1, 'field of view'],
  ].map((a) => ({ k: a[0], lo: a[1], hi: a[2], def: a[3], note: a[4] }));
  const logRec = (rec) => { if (Q.has('noshare')) return; try { fetch('./log.php', { method: 'POST', body: JSON.stringify(Object.assign({ app: 'gv', kind: 'lab', sid: (window.__sid = window.__sid || Math.random().toString(16).slice(2, 8)), t: Math.round(performance.now() / 1000) }, rec)), keepalive: true }).catch(() => { }); } catch (e) { } };
  const TAGS = [
    ['trees_breathe', 'trees breathing', []], ['trees_color', 'tree colours', ['vHue', 'vGlow']], ['mtn_sway', 'mountains swaying', []], ['mtn_moire', 'mountain patterns', []], ['sky', 'sky patterns', []], ['goddess', 'face in the clouds', []],
    ['ground', 'ground moire', ['gScale', 'gRatio', 'gRot', 'gSat']], ['split', 'colour split', ['k_chroma', 'mAz']], ['tracers', 'tracer ghosts', ['k_trace']], ['warp', 'warping', ['k_warp', 'mBy']], ['pulse', 'pulsing zoom', ['k_pulse', 'mBz']],
    ['bloom', 'glow / bloom', ['glowMul', 'bloomAdd']], ['haze', 'haze', ['fogMul']], ['wash', 'hue wash', ['k_wash', 'mAx']], ['punch', 'saturation', ['k_punch']], ['breathe', 'breathing', ['breathe', 'mAy']], ['ripples', 'ripples', ['mBx']], ['fov', 'zoom / fov', ['fovMul']], ['sharp', 'crisp / sharp', ['sharp', 'buzz', 'dmt']],
  ].map((a) => ({ id: a[0], label: a[1], knobs: a[2] }));
  LAB = createLab({ knobs: KN, tags: TAGS, askS: 7, judgeS: 3, apply: (v) => { LABV = v; }, log: logRec, holdS: parseFloat(Q.get('hold') || '7'), easeS: 2.5 });
  const mk = (big, small, col, right, fn) => { const b = document.createElement('div'); b.innerHTML = '<div style="font-size:40px;line-height:1">' + big + '</div><div style="font-size:11px;margin-top:6px;opacity:.9">' + small + '</div>'; b.style.cssText = 'position:fixed;top:50%;transform:translateY(-50%);' + (right ? 'right:max(0px,env(safe-area-inset-right));border-radius:44px 0 0 44px;border-right:0' : 'left:max(0px,env(safe-area-inset-left));border-radius:0 44px 44px 0;border-left:0') + ';width:92px;height:190px;border:3px solid ' + col + ';color:#fff;background:' + col + '44;font:700 14px ui-monospace,Consolas,monospace;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;z-index:12;user-select:none;-webkit-user-select:none;touch-action:manipulation;cursor:pointer'; b.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); b.style.background = col + 'aa'; setTimeout(() => { b.style.background = col + '44'; }, 160); fn(); }); document.body.appendChild(b); return b; };
  mk('👍', 'J · JESUS THAT’S<br>NICE!', '#3f6', true, () => LAB.like()); mk('👎', 'F · FAIL', '#f55', false, () => LAB.nope());
  const lt = document.createElement('div'); lt.style.cssText = 'position:fixed;left:0;right:0;top:56px;text-align:center;color:#ffd;font:700 13px ui-monospace,Consolas,monospace;text-shadow:0 0 5px #000;z-index:11;pointer-events:none;padding:0 70px'; document.body.appendChild(lt);
  addEventListener('keydown', (e) => { if (e.key === 'j' || e.key === 'J') { e.preventDefault(); LAB.like(); } else if (e.key === 'f' || e.key === 'F') LAB.nope(); else if (e.key === 'Enter' || e.key === ' ') { if (LAB.state.ask) { e.preventDefault(); LAB.commit(); } } else if (e.key >= '1' && e.key <= '9' && LAB.state.ask) LAB.toggleTag(TAGS[+e.key - 1].id); else if (e.key === 'l' || e.key === 'L') LAB.toggle(); });
  const jd = document.createElement('div'); jd.style.cssText = 'position:fixed;left:50%;top:16%;transform:translateX(-50%);z-index:13;pointer-events:none;font:700 64px ui-monospace,Consolas,monospace;text-shadow:0 0 18px #000;opacity:0;white-space:nowrap'; jd.textContent = '\U0001F44D   \U0001F44E'; document.body.appendChild(jd);
  const tr = document.createElement('div'); tr.style.cssText = 'position:fixed;left:104px;right:104px;bottom:14px;z-index:13;display:none;flex-wrap:wrap;justify-content:center;gap:6px;font:700 12px ui-monospace,Consolas,monospace;color:#fff;text-align:center'; document.body.appendChild(tr);
  const trT = document.createElement('div'); trT.style.cssText = 'width:100%;font-size:13px;text-shadow:0 0 6px #000;margin-bottom:2px'; tr.appendChild(trT); const chips = {};
  TAGS.forEach((t, k) => { const c = document.createElement('div'); c.textContent = (k < 9 ? (k + 1) + ' ' : '') + t.label; c.style.cssText = 'padding:9px 12px;border:2px solid #fff8;border-radius:18px;background:#0007;cursor:pointer;user-select:none;touch-action:manipulation'; c.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); LAB.toggleTag(t.id); }); tr.appendChild(c); chips[t.id] = c; });
  const dn = document.createElement('div'); dn.textContent = 'DONE'; dn.style.cssText = 'padding:9px 16px;border:2px solid #3f6;border-radius:18px;background:#3f64;cursor:pointer;user-select:none'; dn.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); LAB.commit(); }); tr.appendChild(dn);
  window.__labUI = { jd, tr, trT, chips };
  window.__lab = LAB; window.__labText = lt;
}
function labStep(dt) {
  if (!LAB) return; LAB.tick(dt); const v = LABV, pu = postM.uniforms;
  pu.amount.value *= v.amount; pu.breathe.value *= v.breathe; pu.k_warp.value *= v.k_warp; pu.k_pulse.value *= v.k_pulse; pu.k_chroma.value *= v.k_chroma; pu.k_trace.value *= v.k_trace; pu.k_punch.value *= v.k_punch; pu.k_wash.value *= v.k_wash;
  pu.mA.value.x = Math.min(1.4, pu.mA.value.x + v.mAx); pu.mA.value.y = Math.min(1.4, pu.mA.value.y + v.mAy); pu.mA.value.z = Math.min(1.4, pu.mA.value.z + v.mAz); pu.mB.value.x = Math.min(1.4, pu.mB.value.x + v.mBx); pu.mB.value.y = Math.min(1.4, pu.mB.value.y + v.mBy); pu.mB.value.z = Math.min(1.4, pu.mB.value.z + v.mBz);
  pu.dmt.value = Math.min(1, pu.dmt.value + v.dmt); pu.buzz.value = Math.min(1, pu.buzz.value + v.buzz); pu.sharp.value = Math.min(1, pu.sharp.value + v.sharp); pu.trip.value = Math.min(1, pu.trip.value + v.trip);
  GL.intensity *= v.glowMul; GL.bloom += v.bloomAdd; U.fogDensity.value *= v.fogMul; U.uLabA.value.set(v.gScale, v.gRatio, v.gRot, v.gSat); U.uLabB.value.set(v.vHue, v.vGlow, 1, 1);
  const S = LAB.state, UI = window.__labUI; if (UI) { UI.jd.style.opacity = (S.judge && !S.ask) ? (.55 + .45 * Math.abs(Math.sin(performance.now() * .006))).toFixed(2) : '0'; UI.tr.style.display = S.ask ? 'flex' : 'none';
    if (S.ask) { UI.trT.textContent = (S.ask === 'up' ? '\u{1F44D} what worked?' : '\u{1F44E} what was off?') + '   (tap, or 1-9)  ' + Math.ceil(S.askT) + 's'; for (const id in UI.chips) UI.chips[id].style.background = S.picked.includes(id) ? (S.ask === 'up' ? '#3f6a' : '#f55a') : '#0007'; } }
  if (window.__labText) window.__labText.innerHTML = 'LAB  ' + S.label + '<br><span style="opacity:.8">liked ' + S.likes.length + ' · nope ' + S.nopes.length + (S.flash > 0 ? '  ' + S.last : '') + '</span>';
}
const CH = document.createElement('div'); CH.style.cssText = 'position:fixed;left:50%;bottom:19%;transform:translateX(-50%);text-align:center;color:#fff;font:800 20px/1.2 system-ui,Segoe UI,Inter,sans-serif;letter-spacing:.14em;text-shadow:0 0 8px #f0f,0 0 20px #f0f;pointer-events:none;z-index:7;opacity:0'; CH.innerHTML = '<div id="chn"></div><div style="width:120px;height:6px;margin:4px auto 0;border:1px solid #fff8;border-radius:3px;overflow:hidden"><div id="chb" style="height:100%;width:100%;background:linear-gradient(90deg,#f0f,#0ff)"></div></div>'; document.body.appendChild(CH);
function chainHit() {
  PH.chain++; const c = PH.chain; PH.chainT = 3.2 + .25 * Math.min(c, 12); PH.chainMax = Math.max(PH.chainMax || 0, c); PH.score += 25 * c;
  PH.boost_t = Math.max(PH.boost_t, Math.min(2.6, .5 + .14 * c)); PH.mom = Math.max(PH.mom, 1.5);
  const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), kick = Math.min(5, .8 + .35 * c) * SPK; PH.vx += fx * kick; PH.vz += fz * kick;
  tone(520 * Math.pow(1.0595, Math.min(c, 14) * 2), 520 * Math.pow(1.0595, Math.min(c, 14) * 2) * 1.5, .16, .22);
  if (c === 3 || c === 6 || c === 10 || c === 15 || c === 21 || c === 28) { toast('CHAIN x' + c + '!', '#f9f'); try { FX.E.cheer([PH.x, PH.y + 1, PH.z], [1, .5, 1], 1); } catch (e) { } SFX.snap(); PH.vxa = Math.max(PH.vxa, .8); PH.score += 100 * c; }
}
function chainTick(dt) {
  if (PH.chain > 0) { PH.chainT -= dt; if (PH.chainT <= 0) { if (PH.chain >= 3) toast('CHAIN ENDED  x' + PH.chain, '#c9f'); PH.chain = 0; } }
  const on = PH.chain > 1 ? 1 : 0; CH.style.opacity = on; if (on) { document.getElementById('chn').textContent = 'CHAIN x' + PH.chain; document.getElementById('chb').style.width = Math.max(0, Math.min(100, PH.chainT / (3.2 + .25 * Math.min(PH.chain, 12)) * 100)) + '%'; }
}
// the gravity well: while a chain is alive the nearest target ahead pulls the board toward it (steering and a little forward drag), harder with a longer chain, and not at all against a hard nudge the other way
function wellSteer(sIn, dt) {
  if (PH.chain < 1 || PH.rail || !PH.grounded) return 0; let best = null, bd = 1e9;
  for (const c of PH.cands) { if (c.kind === 'ramp') continue; if (c.dz < 14 || c.dz > 150 || Math.abs(c.dx) > 42) continue; const sc = Math.abs(c.dx) + .12 * c.dz; if (sc < bd) { bd = sc; best = c; } }
  if (!best) return 0; const w = Math.min(.9, .16 * PH.chain), want = Math.max(-.9, Math.min(.9, (best.x - (PH.x + PH.vx * .45)) / 14)); if (Math.abs(sIn) > .5 && Math.sign(sIn) !== Math.sign(want)) return 0;
  if (best.dz < 70) { const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), tug = 9 * SPK * dt * w * (1 - best.dz / 70); PH.vx += fx * tug; PH.vz += fz * tug; }
  return w * want * (1 - .6 * Math.abs(sIn));
}
const SHUD = { a: 0 }; const shudder = (a) => { a *= Math.max(0, Math.min(1.5, sp('shake', 1))); if (a <= 0) return; SHUD.a = Math.max(SHUD.a, a); try { RIG.shudder(a); } catch (e) { } };          // a quick shudder to match an impact, nothing continuous

// ---------------------------------------------------------------- THE BANK (GAME_SPEC 17): up to 2 of each of shield, saw, magnet, wings are carried and spent AUTOMATICALLY when the situation they are for happens; nothing to touch.
// shield: a crash is absorbed (impact shown, one shield lost).  saw: a tree that is a real obstacle ON the path is cut down (the trees at the sides are not an obstacle and cost nothing).
// magnet: a piece you still lack is close ahead and off your line.  wings: you are in the air with a target ahead and off your line.  boost stays automatic on pads. ?bank=shield2,saw2,magnet1 preloads the bank for testing.
const BANK = { shield: 0, saw: 0, magnet: 0, wings: 0 }, BCAP = 2, BKIND = { shield: 'shield', mult: 'magnet', donut: 'wings', saw: 'saw' };
const BANKHUD = (() => { const d = document.createElement('div'); d.style.cssText = 'position:fixed;left:12px;bottom:14px;z-index:7;display:flex;gap:8px;pointer-events:none;font:700 12px/1 system-ui,Segoe UI,sans-serif;color:#fff;letter-spacing:.08em';
  const COL = { shield: '#5df', saw: '#7f7', magnet: '#c8f', wings: '#f9c' }, els = {}; for (const k of Object.keys(COL)) { const e = document.createElement('div'); e.style.cssText = 'min-width:74px;padding:5px 7px;border-radius:12px;background:#000b;border:2px solid ' + COL[k] + ';text-align:center;transition:opacity .25s,transform .2s'; d.appendChild(e); els[k] = e; }
  document.body.appendChild(d); return { draw() { const act = { magnet: PH.mult > 0 ? Math.min(1, PH.mult / (TUNE.magnet.seconds || 8)) : 0, wings: PH.wings > 0 ? Math.min(1, PH.wings / (TUNE.wings.seconds || 6)) : 0 }, sig = Object.keys(COL).map((k) => BANK[k] + ':' + Math.round((act[k] || 0) * 24)).join('|'); if (sig === this.last) return; this.last = sig;
    const WHAT = { shield: 'blocks a crash', saw: 'cuts a tree', magnet: 'pulls pickups in', wings: 'air steering' };
    for (const k of Object.keys(COL)) { const n = BANK[k], a = act[k] || 0; els[k].style.opacity = n > 0 || a > 0 ? '1' : '.4'; els[k].style.boxShadow = a > 0 ? '0 0 14px ' + COL[k] : (n >= BCAP ? '0 0 8px ' + COL[k] + '88' : 'none');
      const status = a > 0 ? '<div style="height:5px;margin-top:4px;border-radius:3px;background:#fff2;overflow:hidden"><div style="height:100%;width:' + Math.round(a * 100) + '%;background:' + COL[k] + '"></div></div>' : '<div style="margin-top:4px;font-size:9px;letter-spacing:.06em;color:' + (n >= BCAP ? COL[k] : '#fff9') + '">' + (n >= BCAP ? 'FULL' : n > 0 ? 'READY' : 'EMPTY') + '</div>';
      els[k].innerHTML = k.toUpperCase() + '<div style="font-size:14px;margin-top:3px;color:' + COL[k] + '">' + (n > 0 ? '●'.repeat(n) + '○'.repeat(BCAP - n) : '○'.repeat(BCAP)) + '</div>' + status + '<div style="margin-top:3px;font:500 9px/1.1 system-ui;letter-spacing:0;color:#fffa">' + WHAT[k] + '</div>'; } }, pop(k) { els[k].style.transform = 'scale(1.18)'; setTimeout(() => { els[k].style.transform = ''; }, 220); } }; })();
function bankSync() { PH.shield = BANK.shield > 0 ? 1 : 0; BANKHUD.draw(); }
function bankAdd(k) { if (BANK[k] >= BCAP) return false; BANK[k]++; bankSync(); BANKHUD.pop(k); return true; }
function bankSpend(k) { if (BANK[k] <= 0) return false; BANK[k]--; bankSync(); BANKHUD.pop(k); return true; }
{ const bq = Q.get('bank'); if (bq) for (const part of bq.split(',')) { const m = /^(shield|saw|magnet|wings)(\d)$/.exec(part); if (m) BANK[m[1]] = Math.min(BCAP, +m[2]); } }
bankSync();
const _cm = new THREE.Matrix4(), _zm = new THREE.Matrix4().makeScale(0, 0, 0);
function onPath(o) { const j = Math.floor(-o.z / 180), rr = lvl.rows && lvl.rows[String(j)]; if (rr && rr.has_row) return Math.abs(o.z - rr.z) < 7; return Math.abs(o.x - trailX(o.z)) < 9; }          // a barrier line's trees, or trees on the trail itself: an obstacle; trees off to the sides are scenery
function cutTree(o) { let n = 0; for (const im of VEGIM) { for (let i = 0; i < im.count; i++) { im.getMatrixAt(i, _cm); const e = _cm.elements; if (e[15] !== 0 && Math.abs(e[12] - o.x) < 1.5 && Math.abs(e[14] - o.z) < 1.5 && Math.abs(e[0]) + Math.abs(e[5]) > 0) { im.setMatrixAt(i, _zm); n++; } } im.instanceMatrix.needsUpdate = true; } o.dead = true; return n; }

// REACH TARGETS (?reachtest, dev only): a test of the wide steering. Every 150 m a bank buff (shield, magnet, wings in turn) floats 12-23 m to the side on the wide courses (8-12 m on the narrow trail, which is all the open ground it has) of the line, with a column of light and a curved trail of orbs leading to it from the line.
// You have to steer wide to take it. A missed one is simply gone (the next comes along). They are our own objects (not Godot's), collected by touch; collecting one adds it to the bank.
const REACHT = Q.has('reachtest'), RTG = { items: [], next: -140, n: 0 }, RKINDS = ['shield', 'magnet', 'wings'], RCOL = { shield: 0x55ddff, magnet: 0xcc88ff, wings: 0xff99cc };
const _rsph = new THREE.SphereGeometry(1, 14, 10), _rcyl = new THREE.CylinderGeometry(.35, .35, 46, 8, 1, true);
const rmat = (c, o) => new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: o, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
function reachSpawn(z) {
  const side = RTG.n % 2 ? 1 : -1, off = ((lvl.feat_off < 10 ? 8 : 12) + ((RTG.n * 37) % (lvl.feat_off < 10 ? 5 : 12))) * parseFloat(Q.get('reachx') || '1'), lim = C.W_HALF - 4, x = Math.max(-lim, Math.min(lim, trailX(z) + side * off)), gy = groundY(x, z); if (gy === null || gy === undefined) return false;
  const kind = RKINDS[RTG.n % 3], col = RCOL[kind], grp = new THREE.Group(); const core = new THREE.Mesh(_rsph, rmat(col, .95)); core.scale.setScalar(1.15); grp.add(core); const halo = new THREE.Mesh(_rsph, rmat(col, .22)); halo.scale.setScalar(2.4); grp.add(halo);
  const beam = new THREE.Mesh(_rcyl, rmat(col, .3)); beam.position.y = 22; grp.add(beam); grp.position.set(x, gy + 1.7, z); scene.add(grp);
  const trail = []; const z0 = z + 58, x0 = trailX(z0); for (let i = 1; i <= 6; i++) { const t = i / 7, ss = t * t * (3 - 2 * t), zz = z0 + (z - z0) * t, xx = x0 + (x - x0) * ss, g2 = groundY(xx, zz); if (g2 === null || g2 === undefined) continue; const o = new THREE.Mesh(_rsph, rmat(col, .75)); o.scale.setScalar(.42); o.position.set(xx, g2 + 1.3, zz); scene.add(o); trail.push(o); }
  RTG.items.push({ x, z, y: gy + 1.7, kind, grp, core, halo, beam, trail, taken: false }); RTG.n++; return true;
}
function reachRemove(it) { scene.remove(it.grp); for (const o of it.trail) scene.remove(o); it.gone = true; }
function reachStep(dt) {
  if (!REACHT) return;
  while (RTG.next > PH.z - 320) { if (!reachSpawn(RTG.next)) break; RTG.next -= 150; }
  const above = PH.y - th(PH.x, PH.z), t = clock.t;
  for (const it of RTG.items) { if (it.gone) continue; if (it.z > PH.z + 50) { reachRemove(it); continue; }
    it.core.scale.setScalar(1.15 + .12 * Math.sin(t * 5 + it.z)); it.halo.material.opacity = .2 + .08 * Math.sin(t * 3 + it.z); it.grp.position.y = it.y + .35 * Math.sin(t * 2.4 + it.z * .1);
    if (!it.taken && Math.abs(it.z - PH.z) < 3.6 && Math.abs(it.x - PH.x) < 4 && above < 6) { it.taken = true; if (bankAdd(it.kind)) { toast(it.kind.toUpperCase() + ' +1  (reached)', '#' + RCOL[it.kind].toString(16).padStart(6, '0')); PH.score += 60; SFX.pick(); } else toast(it.kind.toUpperCase() + ' FULL', '#9ab'); reachRemove(it); } }
  RTG.items = RTG.items.filter((it) => !it.gone);
}
function bankAuto(dt) {
  if (BANK.magnet > 0 && PH.mult <= 0) { const cand = []; for (const m of PILLS) { if (m.mine ? m.taken : (m.eaten || m.hid)) continue; cand.push(m); } for (const q of SHAFTS) if (q.keep && !q.taken) cand.push(q); for (const b of BUFFS) if (!b.taken) cand.push(b); for (const m of cand) { const dz = PH.z - m.z; if (dz > 10 && dz < 45 && Math.abs(m.x - PH.x) > 3.5 && Math.abs(m.x - PH.x) < 30) { bankSpend('magnet'); PH.mult = TUNE.magnet.seconds; toast('MAGNET ON: pickups are pulled in', '#c8f'); break; } } }
  if (BANK.wings > 0 && PH.wings <= 0 && !PH.grounded && PH.air_t > .45) { let tg = null; for (const m of PILLS) if ((m.mine ? !m.taken : !(m.eaten || m.hid)) && PH.z - m.z > 8 && PH.z - m.z < 70 && Math.abs(m.x - PH.x) > 4) tg = m; if (!tg) for (const q of SHAFTS) if (q.keep && !q.taken && PH.z - q.z > 8 && PH.z - q.z < 70 && Math.abs(q.x - PH.x) > 4) { tg = q; break; } if (!tg) for (const b of BUFFS) if (!b.taken && PH.z - b.z > 8 && PH.z - b.z < 70 && Math.abs(b.x - PH.x) > 4) { tg = b; break; } if (tg) { bankSpend('wings'); PH.wings = TUNE.wings.seconds; toast('WINGS ON: steer harder in the air', '#f9c'); } }
}
function crash(msg, kind) {
  if (PH.hurt > 0 || toys.active()) return;
  if (PH.shield > 0) { bankSpend('shield'); PH.hurt = .8; toast('SHIELD BROKE  ' + BANK.shield + ' left', '#5df'); if (AWON) AW.onShieldBreak(); else SFX.shield(); shudder(.45); try { FX.E.shieldBreak([PH.x, PH.y, PH.z]); } catch (e) { } return; }
  try { PSY.events.onCrash(kind, { shield: false }); } catch (e) { }
  PH.hits++; PH.hurt = .45; if (AWON) { if (kind === 'rock') AW.onRockHit(); else AW.onTreeHit(); } else SFX[kind === 'rock' ? 'gong' : 'thwack'](); toast(msg, '#f66'); PH.score = Math.max(0, PH.score - 50); PH.rail = null; SFX.grindOff();          // (the bounce itself is done where the hit happens: obstacleStep keeps your speed and turns it back to open ground)
}
function takeBuff(b) {
  const bk = BKIND[b.t]; if (bk && BANK[bk] >= BCAP) { if (!(b.fullT > performance.now() - 1500)) { b.fullT = performance.now(); toast(bk.toUpperCase() + ' FULL', '#9ab'); } return; }
  try { FX.E.pickup(b.t, [b.x, b.y, b.z], PH.heading); } catch (e) { }
  try { PSY.events.onBuff(b.t); } catch (e) { } if (bk) bankAdd(bk);
  b.taken = true; hideTarget(b); PH.picks++; PH.score += 60; chainHit(); const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), sp0 = Math.hypot(PH.vx, PH.vz);
  if (b.t === 'boost') { PH.boost_t = C.BOOST_S; PH.vx += fx * 6 * SPK; PH.vz += fz * 6 * SPK; const v = Math.hypot(PH.vx, PH.vz), lim = Math.max(C.SPEED_CAP, sp0); if (v > lim) { PH.vx *= lim / v; PH.vz *= lim / v; } toast('CRYSTAL BOOST!', '#fa3'); }
  else if (b.t === 'shield') { toast('SHIELD +1  (blocks one crash)', '#5df'); } else if (b.t === 'mult') { toast('MAGNET +1  (pulls pickups in)', '#c8f'); } else if (b.t === 'saw') { toast('SAW +1  (cuts through a tree)', '#fb6'); } else { toast('WINGS +1  (steer in the air)', '#f9c'); }
  if (b.t !== 'boost') { PH.vx += fx * 3 * SPK; PH.vz += fz * 3 * SPK; PH.boost_t = Math.max(PH.boost_t, .8); } SFX.pick(); SFX.snap(); PH.latch = null;
}
for (const k of Object.keys(TUNE.grab)) TUNE.grab[k] *= parseFloat(Q.get('grab') || '1.3');          // pickups count from 30% farther out, so a near miss with a head is still a catch (?grab=1 for the original)
function collectStep() {
  if (window.__slalomTick) window.__slalomTick(); BANKHUD.draw(); shaftStep(); if (window.__hazeStep) window.__hazeStep(); if (window.__bpStep) window.__bpStep();
  if (PH.rail) shudder(.04 + .05 * Math.min(1, Math.hypot(PH.vx, PH.vz) / (40 * SPK)));          /* grinding a rail: a faint hum in the picture, gone the moment you leave it */
  { const held = toys.active() || PH.vlock !== null; if (held && !window.__heldPrev) shudder(.4); window.__heldPrev = held; }          /* a spring or a vortex takes hold of the board: one whoomph */
  const above = PH.y - th(PH.x, PH.z); const TG = TUNE.grab, MG = PH.mult > 0 ? TUNE.magnet.molX : 1, MB = PH.mult > 0 ? TUNE.magnet.other : 1;          // MAGNET: molecules count from twice as far sideways, other pickups from 1.6x
  for (const b of BUFFS) {
    if (Math.abs(b.z - PH.z) > 150) continue;
    for (const o of (b.orbs || [])) if (!o.taken && Math.abs(o.z - PH.z) < TG.orbZ * MB && Math.abs(o.x - PH.x) < TG.orbX * MB && above < 5) { o.taken = true; hideNode(o.n); PH.score += 10; SFX.orb(); }
    if (b.taken) continue;
    if (b.kind === 'air') { if (Math.abs(b.z - PH.z) < TG.airZ * MB && Math.abs(b.x - PH.x) < TG.airX * MB && above > .8 && Math.abs(b.y - PH.y) < 3.6) takeBuff(b); }
    else if (Math.abs(b.z - PH.z) < TG.buffZ * MB && Math.abs(b.x - PH.x) < TG.buffX * MB && above < 6) takeBuff(b);
  }
  { const no = SPW.collectOrbs(PH, above); if (no) { PH.score += 10 * no; SFX.orb(); try { FX.E.orb([PH.x, PH.y + 1, PH.z]); } catch (e) { } } }
  for (const m of PILLS) if (m.mine && !m.taken && Math.abs(m.z - PH.z) < TG.molZ * (MG > 1 ? TUNE.magnet.molZ : 1) && Math.abs(m.x - PH.x) < TG.molX * MG && above < 8) { m.taken = true; m.hideSelf(); PH.mols = (PH.mols || 0) + 1; PH.molSet = PH.molSet || {}; const first = !PH.molSet[m.id]; PH.molSet[m.id] = 1; setTimeout(() => { try { recordCatch(PROFILE, m.id, 1); saveProfile(PROFILE); } catch (e) { } }, 400); try { FX.E.pillEat([m.x, m.y || PH.y + 3, m.z], MOLS[m.id].c); } catch (e) { } try { PSY.events.onMolecule(m.id, m.name); GM.onMolecule(m.id); } catch (e) { } try { window.__lookPulse(['vec', 'asc', 'psy'][MOL_ORDER.indexOf(m.id) % 3]); } catch (e) { } PH.score += first ? 1500 : 500; PH.boost_t = Math.max(PH.boost_t, 2); chainHit(); chainHit(); toast((m.name || m.id).toUpperCase() + (first ? '  NEW  ' + Object.keys(PH.molSet).length + ' OF 6' : '  FOUND'), '#8ff'); if (AWON) AW.onMoleculeFound(Math.max(0, MOL_ORDER.indexOf(m.id)), Object.keys(PH.molSet).length >= 6); else { SFX.pick(); setTimeout(() => SFX.pick(), 130); setTimeout(() => SFX.pick(), 260); } }
  const low = PH.grounded || above <= 2.5;
  if (low || above <= 16) for (const p of PADS) {
    if (p.used || p.lk || !low || Math.abs(p.z - PH.z) > 230) continue;
    if (Math.abs(p.z - 2.2 - PH.z) < 3.6 && Math.abs(p.x - PH.x) < 4.6) {
      p.used = true; hideTarget(p); PH.pads++; PH.boost_t = Math.max(PH.boost_t, 2.6); const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), sp0 = Math.hypot(PH.vx, PH.vz);
      PH.vx += fx * 10 * SPK * PSY.perks().padK; PH.vz += fz * 10 * SPK * PSY.perks().padK; PH.vxa = Math.max(PH.vxa, 1.4); const v = Math.hypot(PH.vx, PH.vz), lim = Math.max(C.SPEED_CAP, sp0) + 10 * SPK; if (v > lim) { PH.vx *= lim / v; PH.vz *= lim / v; }          /* a pad is a real kick: it is allowed past the speed cap a little, so it is felt at any speed */
      try { FX.E.orb([PH.x, PH.y + .5, PH.z]); } catch (e) { } shudder(.15);
      if (AWON) AW.onPadHit(); else SFX.pad(); try { FX.E.pad([PH.x, PH.y, PH.z]); } catch (e) { } toast(p.epic ? 'LAUNCH PAD' : 'BOOST PAD', '#fb4'); PH.score += 40; chainHit(); try { PSY.events.onPad(p.epic); } catch (e) { }
    }
  }
}
function obstacleStep(px, pz) {
  if (PH.hurt > 0) return; const above = PH.y - th(PH.x, PH.z), cx = Math.floor(PH.x / 8), cz = Math.floor(PH.z / 8), sx = PH.x - px, sz = PH.z - pz, sl = sx * sx + sz * sz;
  for (let i = -2; i <= 2; i++) for (let j = -2; j <= 2; j++) {
    const a = OGRID.get((cx + i) + ',' + (cz + j)); if (!a) continue;
    for (const o of a) {
      if (o.dead) continue; let t = sl > 1e-6 ? ((o.x - px) * sx + (o.z - pz) * sz) / sl : 1; t = Math.max(0, Math.min(1, t)); const qx = px + sx * t, qz = pz + sz * t, R = o.r + C.SLED_R, ex = qx - o.x, ez = qz - o.z;
      if (ex * ex + ez * ez < R * R && above < (o.k < .5 ? 7 : 3)) {
        if (o.k < .5 && BANK.saw > 0 && onPath(o)) { bankSpend('saw'); cutTree(o); toast('SAWED THROUGH  ' + BANK.saw + ' left', '#7f7'); try { FX.E.treeHit(o.x, th(o.x, o.z), o.z, 12); } catch (e) { } SFX.snap(); continue; }
        if (HD.on && sp('forgive', 1) > 0 && performance.now() - (HD.glitchT || -1e9) < 350 && Math.hypot(ex, ez) > R - .5 && !PH.rail) {          /* SAVED: tracking glitched and this is only a graze of the edge: slide off, keep the speed, no crash */
          const d0 = Math.hypot(ex, ez) || 1; PH.x = o.x + ex / d0 * (R + .1); if (PH.grounded) { PH.y = th(PH.x, PH.z); PH.gh_prev = PH.y; } toast('SAVED', '#8f8'); try { SFX.snap(); } catch (e) { } window.__saved = (window.__saved || 0) + 1; continue;
        }
        const dx = ex || .01, dz = ez || .01;
        const d = Math.hypot(dx, dz) || 1, nx = dx / d, nz = dz / d; PH.x = o.x + nx * (R + .1); PH.z = o.z + nz * (R + .1); if (PH.grounded) { PH.y = th(PH.x, PH.z); PH.gh_prev = PH.y; }
        const sp0 = Math.hypot(PH.vx, PH.vz), dp = PH.vx * nx + PH.vz * nz; let bx = PH.vx - (1 + .35) * Math.min(dp, 0) * nx, bz = PH.vz - (1 + .35) * Math.min(dp, 0) * nz;          // reflect: slide along the trunk and be pushed away from it
        bx += Math.sign(trailX(PH.z) - PH.x) * .18 * sp0; bz = Math.min(bz, -.55 * sp0);          // and a nudge back toward the path, and always still going down the hill
        const nn = Math.hypot(bx, bz) || 1, keep = .9 * sp0; PH.vx = bx / nn * keep; PH.vz = bz / nn * keep; PH.heading *= .5; PH.steer *= .5; PH.sv = 0; PH.mom = Math.max(PH.mom, 1.5);
        shudder(.28); try { if (o.k < .5) FX.E.treeHit(o.x, th(o.x, o.z), o.z, Math.hypot(PH.vx, PH.vz) / SPK); else FX.E.rockHit(o.x, th(o.x, o.z), o.z, o.r); } catch (e) { }
        if (o.im && window.__pylonHit) o.label = window.__pylonHit(o); crash(o.label || (o.k < .5 ? 'TREE!' : 'ROCK!'), o.k < .5 ? 'tree' : 'rock'); return;
      }
    }
  }
}
function railStep(dt, sIn) {
  if (PH.rail) {
    const f = PH.rail; if (PH.hurt > 0) { PH.rail = null; f.done = true; SFX.grindOff(); return; }
    const off = (how) => {
      const m = PH.rail_z0 - PH.z; PH.rail = null; f.done = true; SFX.grindOff(); if (how !== 'drop') { PH.grounded = false; PH.air_t = 0; if (how === 'end') PH.vy += 3.2; }
      try { FX.E.railEnd([PH.x, PH.y, PH.z]); } catch (e) { } if (m < 6) return; PH.rails++; PH.score += Math.floor(m * 7) * (f.mat === 'neon' ? 2 : 1); chainHit(); try { PSY.events.onRail(m, how, 0, !!f.chain, 1); } catch (e) { } const sl = Math.max(0, Math.min(1, m / 36)); toast('RAIL  ' + Math.floor(m) + ' m', '#7ef'); SFX.pick();
      if (sl > .2 && how !== 'drop') { PH.vz -= (3 + 13 * sl) * SPK * .6; PH.boost_t = Math.max(PH.boost_t, .7 + 1.8 * sl); PH.vxa = .7; SFX.snap(); if (sl > .5) toast('SLINGSHOT!', '#7ef'); }
    };
    if (PH.z <= f.zb) { if (f.chain) toys.payoff(); off('end'); return; }
    PH.rail_out = (sIn * f.sd < -.8) ? PH.rail_out + dt : 0; if (PH.rail_out > .3) { off('drop'); return; }
    if (f.mat === 'glass') PH.vz -= 11 * SPK * dt; else if (f.mat === 'wood') PH.vz *= Math.exp(-.35 * dt); else if (f.mat === 'rust') PH.vz *= Math.exp(-.2 * dt);          /* the material decides how it rides: glass is fast, wood slow, rust a little rough */
    const slope = (featX(f, PH.z - 1) - featX(f, PH.z + 1)) * .5; PH.rail_dx += PH.slide * dt; PH.slide *= Math.exp(-dt / .1); { const tgtR = Math.max(-1, Math.min(1, sIn)) * sp('railfree', 1.6); PH.rail_dx += (tgtR - PH.rail_dx) * (1 - Math.exp(-dt / .18)); }          /* free to move a little with the head: the rail pulls you back toward its line only as far as your steering lets it */
    PH.x = featX(f, PH.z) + PH.rail_dx; const ry = railY(f, PH.z); PH.vy = PH.rail_ok ? Math.max(-40, Math.min(10, (ry - PH.rail_py) / Math.max(dt, 1e-4))) : PH.vy; PH.rail_py = ry; PH.rail_ok = true; PH.y = ry;
    PH.vx = slope * -PH.vz; PH.heading = Math.atan(slope) + Math.max(-1, Math.min(1, sIn)) * .1; PH.steer = Math.max(-1, Math.min(1, PH.heading / C.THETA_MAX)); PH.sv = 0; PH.grounded = true;
    if (grindN) grindN.fl.frequency.value = 1800 + Math.hypot(PH.vx, PH.vz) * 14; railSparkT -= dt; if (railSparkT <= 0) { railSparkT = .14; try { FX.E.railSpark([PH.x, PH.y, PH.z]); } catch (e) { } } return;
  }
  for (const f of RAILS) {
    if (f.done) continue; if (PH.z < f.zb + 5) { f.done = true; continue; }
    if (PH.grounded && PH.z < f.za + 6) { const wdx = featX(f, Math.max(f.zb, Math.min(f.za, PH.z))) - PH.x; if (sp('railpull', 0) > 0 && Math.abs(wdx) < 7 && Math.abs(wdx) > .3) PH.x += Math.sign(wdx) * Math.min(Math.abs(wdx), (2.5 + 9 * (1 - Math.abs(wdx) / 7)) * dt * 2); }          /* no pull toward a rail: you have to line up on it yourself (&railpull=1 for the old pull) */
    if (PH.hurt > 0 || PH.z > f.za + .5) continue; const nt = PH.z > f.za - 10;
    if (sp('railgrab', 1) > 0 && Math.abs(PH.x - featX(f, PH.z)) < (nt ? 1.5 : .9) * sp('railgrab', 1) && PH.y - railY(f, PH.z) < 2) { PH.rail = f; PH.rail_z0 = PH.z; PH.rail_dx = PH.x - featX(f, PH.z); PH.slide = PH.vx; PH.rail_ok = false; PH.rail_out = 0; SFX.grindOn(); toast({ glass: 'GLASS RAIL: FAST', wood: 'WOODEN RAIL: SLOW AND LONG', neon: 'NEON RAIL: DOUBLE POINTS', rust: 'RUSTY RAIL: ROUGH' }[f.mat] || 'GRIND', f.col ? '#' + f.col.map((c) => Math.round(Math.min(1, c) * 15).toString(16)).join('') : '#7ef'); break; }
  }
}
/* NO INVISIBLE WALL AT A RAMP: the banked walls (they turn you back from the road edge) and the aim limit stop the board about 16 m inside the edge. A ramp can stand out there, so while one is close ahead
   (within ~170 m, and its mouth within 14 m of the board's side) the edge push is off and the aim may reach the ramp's own x. */
function nearRamp() { for (const k of VXS) { if (!k.trail) continue; if (PH.z < k.z + 60 + (C.VX_REACH || 40) && PH.z > k.z - k.len && Math.abs(k.x - PH.x) < k.w * .5 + 16) return k; } return null; }
function vortexStep(dt, steerIn) {
  PH.vx_spin += dt; let active = false, lockX = null;
  for (const k of VXS) {
    if (!k.trail) continue; const kz = k.z, kx = k.x, lipz = kz - k.len, half = k.w * .5, dxk = kx - PH.x, onIt = PH.z < kz + 4 && Math.abs(dxk) < half + 1.5;
    const wantSide = Math.sign(steerIn) === Math.sign(dxk) && Math.abs(steerIn) > .15;
    if (PH.grounded && !PH.rail && PH.z < kz + C.VX_REACH + 14 && PH.z > lipz + 1 && (onIt || Math.abs(dxk) < half + sp('vxcatch', 3) || (wantSide && Math.abs(dxk) < half + sp('vxwant', 12)))) {
      lockX = kx; active = true; if (!PH.vsnd) { PH.vsnd = true; SFX.stretch(); }
      const t = Math.max(0, Math.min(1, (kz + C.VX_REACH - PH.z) / (C.VX_REACH + k.len))); { const side = Math.max(0, Math.abs(dxk) - half), gentle = 1 + sp('vxcap', .1) * Math.abs(PH.vz), ahead = Math.max(0, PH.z - kz), wMouth = (1 - sstep(0, sp('vxmouth', 30), ahead)) * Math.max(0, 1 - side / Math.max(4, sp('vxcatch', 3) + 8)), wSide = PH.z < kz + 6 ? Math.max(0, 1 - side / sp('vxside', 5)) : 0, cap = gentle + (34 - gentle) * Math.max(wMouth, wSide); PH.x += Math.max(-cap, Math.min(cap, dxk * 7)) * dt * sstep(0, .12, t); }          /* the ramp's pull: full strength (34 m/s) at the mouth (the last 30 m before it, &vxmouth) and all along its sides (up to 10 m out, fading, &vxside) so a board going up the side is caught; further out only a gentle pull (about 8 degrees of slant at 30 m/s, &vxcap) so approaching a ramp never looks like a slide */ VFX.setPull(t);
      const fsp = -PH.vz; if (fsp < C.VX_TRAIL) PH.vz -= Math.min(C.VX_ACCEL * (PH.z < kz ? .9 : .6) * dt, C.VX_TRAIL - fsp);
    }
    if (PH.prevZ > lipz && PH.z <= lipz && Math.abs(PH.x - kx) < half) {          // the lip: the swirl lets go (RunRig._update_ramps, crossed): a hard blast off it
      PH.vy += C.JUMP_BLAST; PH.boost_t = Math.max(PH.boost_t, 1.2);          /* the natural ramps: exactly Godot's launch */ try { if (window.__kitLaunch) window.__kitLaunch(); } catch (e) { }          /* each ramp throws a different height (0.7x to 1.6x), keyed to where it stands */ PH.jumps++; PH.score += 150; chainHit(); try { PSY.events.onBlast({ crossedMid: true, superRamp: !!k.super, charge: 0 }); } catch (e) { } toast(k.super ? 'SUPER AIR!' : 'BLAST!', '#f8f'); VFX.blast(); FX.E.blast([PH.x, PH.y, PH.z]); if (AWON) AW.onRampBlast(); else SFX.blast(); if (k.super) { PH.vy += 5; PH.boost_t = 2.4; } PH.vxa = Math.max(PH.vxa, .45);
    }
  }
  PH.vlock = lockX; if (active) PH.vxa = Math.max(PH.vxa, .45); else { if (PH.grounded) PH.vxa = Math.max(PH.vxa - dt, 0); PH.vsnd = false; }
}
const ramp = () => sp('rampbase', 1.15) + (1 - sp('rampbase', 1.15)) * sstep(0, 1000, -PH.z) + .12 * Math.min(PH.lap || 0, 4);
const MS = { buf: [], t0: performance.now(), q: [], last: 0, flips: 0, lastSign: 0, lagMs: 0, sw: 0, ll: 0 };
const scope = document.createElement('canvas'); scope.width = 360; scope.height = 120; scope.style.cssText = 'position:fixed;left:8px;bottom:36px;width:300px;height:100px;background:#0008;border:1px solid #fff4;z-index:8;pointer-events:none'; if (Q.has('meter')) document.body.appendChild(scope);          /* the steering meter is a tuning tool: hidden unless &meter */
const sgx = scope.getContext('2d'); const txt = document.createElement('div'); txt.style.cssText = 'position:fixed;left:8px;bottom:140px;color:#cfe;font:11px/1.35 ui-monospace,Consolas,monospace;z-index:8;pointer-events:none;white-space:pre;text-shadow:0 0 3px #000'; if (Q.has('meter')) document.body.appendChild(txt);
function measure(dt, sIn, steer) {
  const now = performance.now(); const lv = PH.vx * Math.cos(PH.heading) + PH.vz * Math.sin(PH.heading);          // sideways speed across the board's heading
  MS.buf.push([now, window.__steer || 0, sIn, steer, PH.heading, PH.x, PH.vx, Math.hypot(PH.vx, PH.vz), PH.z, PH.hurt > 0 ? 1 : 0]); if (MS.buf.length > 600) MS.buf.shift();
  const sg = Math.abs(window.__steer || 0) > .15 ? Math.sign(window.__steer) : 0; if (sg && sg !== MS.lastSign) { if (MS.lastSign) MS.flips++; MS.lastSign = sg; }
  if (now - MS.last > 250) {
    MS.last = now; const b = MS.buf, n = b.length; let best = 0, bl = 0;
    if (n > 120) { for (let lag = 0; lag <= 24; lag += 2) { let c = 0, m = 0; for (let i = lag; i < n; i++) { c += b[i - lag][2] * b[i][6]; m++; } c /= m; if (c > best) { best = c; bl = lag; } } MS.lagMs = bl * (n > 1 ? (b[n - 1][0] - b[0][0]) / (n - 1) : 16); }
    const secs = (now - MS.t0) / 1000; MS.sw = MS.flips / Math.max(secs, 1);
    txt.textContent = 'head ' + (window.__steer || 0).toFixed(2) + '  steer ' + steer.toFixed(2) + '  heading ' + (PH.heading * 57.3).toFixed(0) + 'deg\nside-to-side flips ' + MS.flips + '  (' + MS.sw.toFixed(2) + '/s)  tracker ' + (window.__trk ? Math.round(window.__trk.fps) : '-') + ' fps  game ' + Math.round(fps || 0) + ' fps  response lag ~' + MS.lagMs.toFixed(0) + ' ms\nspeed ' + (Math.hypot(PH.vx, PH.vz) * 3.6).toFixed(0) + ' km/h  lateral ' + lv.toFixed(1) + ' m/s';
    sgx.clearRect(0, 0, 360, 120); sgx.strokeStyle = '#fff3'; sgx.beginPath(); sgx.moveTo(0, 60); sgx.lineTo(360, 60); sgx.stroke();
    const draw = (col, k, sc) => { sgx.strokeStyle = col; sgx.beginPath(); const t1 = b[n - 1] ? b[n - 1][0] : now; for (let i = 0; i < n; i++) { const x = 360 - (t1 - b[i][0]) / 8000 * 360, y = 60 - b[i][k] * sc; if (i === 0) sgx.moveTo(x, y); else sgx.lineTo(x, y); } sgx.stroke(); };
    draw('#0ff', 1, 50); draw('#ff0', 3, 50); draw('#f6f', 4, 50);
  }
  if (now - (MS.sent || 0) > 5000 && !Q.has('noshare') && MS.buf.length > 20) {          // numbers only, to the same anonymous log as the other games (every 5 s)
    MS.sent = now; const rows = MS.buf.filter((_, i) => i % 3 === 0).map((r) => r.map((v, i) => +(i === 0 ? (v - MS.t0) / 1000 : v).toFixed(3)));
    try { fetch('./log.php', { method: 'POST', body: JSON.stringify({ app: 'gv', kind: 'steer', cols: 't head sIn steer heading x vx speed z hurt', flips: MS.flips, lag: Math.round(MS.lagMs), trkFps: window.__trk ? Math.round(window.__trk.fps) : null, gameFps: Math.round(fps || 0), rows: rows.slice(-90) }), keepalive: true }).catch(() => { }); } catch (e) { }
  }
}
// ---------------------------------------------------------------- THE GOAL MOLECULE: the next molecule on the course is shown at the top of the screen as a spinning ball-and-stick icon, with a downward triangle that tracks, live, where it is coming from (at the screen edge with an arrow when it is off to the side)
const PILLS = ROWS.flatMap((r) => (r.toys || []).filter((t) => t.kind === 'pill')).sort((a, b) => b.z - a.z);
if (!Q.has('realnames')) for (const p of PILLS) if (CARD_NAMES[p.id]) p.name = CARD_NAMES[p.id];
const GOAL = document.createElement('div'); GOAL.style.cssText = 'position:fixed;top:6px;left:50%;width:92px;transform:translateX(-50%);text-align:center;pointer-events:none;z-index:8;display:none;font:700 12px ui-monospace,Consolas,monospace;color:#fff;text-shadow:0 0 6px #000';
const GC = document.createElement('canvas'); GC.width = 160; GC.height = 160; GC.style.cssText = 'width:96px;height:96px;display:block;margin:0 auto;filter:drop-shadow(0 0 8px #fff8)'; const GT = document.createElement('div'); GT.style.cssText = 'margin-top:-6px'; const GA = document.createElement('div'); GA.style.cssText = 'width:0;height:0;margin:2px auto 0;border-left:12px solid transparent;border-right:12px solid transparent;border-top:18px solid #fff;filter:drop-shadow(0 0 6px #fff)';
GOAL.appendChild(GC); GOAL.appendChild(GT); GOAL.appendChild(GA); document.body.appendChild(GOAL); const GX = GC.getContext('2d');
const ELC = { H: [1, 1, 1, .5], C: null, N: [.4, .6, 1, .8], O: [1, .3, .3, .8], S: [1, .9, .3, 1.05], Br: [.8, .4, .2, 1.15] };
function drawMol(mol, t) {
  GX.clearRect(0, 0, 160, 160); const A = mol.atoms, ca = Math.cos(t * .9), sa = Math.sin(t * .9), tl = .35, ct = Math.cos(tl), st = Math.sin(tl); let cx = 0, cy = 0, cz = 0; for (const a of A) { cx += a[1]; cy += a[2]; cz += a[3]; } cx /= A.length; cy /= A.length; cz /= A.length;
  const P = A.map((a) => { const x = a[1] - cx, y = a[2] - cy, z = a[3] - cz; const x1 = x * ca + z * sa, z1 = -x * sa + z * ca; const y1 = y * ct - z1 * st, z2 = y * st + z1 * ct; return [x1, y1, z2]; });
  const sc = 17, pc = (q) => [80 + q[0] * sc, 80 - q[1] * sc]; GX.lineCap = 'round';
  const items = []; for (const b of mol.bonds) items.push({ z: (P[b[0]][2] + P[b[1]][2]) / 2, b }); A.forEach((a, i) => items.push({ z: P[i][2], i })); items.sort((u, v) => u.z - v.z);
  for (const it of items) {
    if (it.b) { const a = pc(P[it.b[0]]), c = pc(P[it.b[1]]); GX.strokeStyle = '#ffffffdd'; GX.lineWidth = it.b[2] === 2 ? 7 : 4.5; GX.beginPath(); GX.moveTo(a[0], a[1]); GX.lineTo(c[0], c[1]); GX.stroke(); }
    else { const a = A[it.i], e = ELC[a[0]] || [1, 1, 1, .8], col = e[0] === undefined || e === null ? mol.c : e, c = pc(P[it.i]), r = (a[0] === 'H' ? .5 : a[0] === 'C' ? .75 : e[3]) * 10 * (1 + P[it.i][2] * .03);
      const rgb = a[0] === 'C' ? mol.c : [e[0], e[1], e[2]]; const g = GX.createRadialGradient(c[0] - r * .3, c[1] - r * .3, r * .1, c[0], c[1], r); g.addColorStop(0, 'rgba(255,255,255,.95)'); g.addColorStop(.35, 'rgb(' + rgb.map((v) => Math.round(v * 255)).join(',') + ')'); g.addColorStop(1, 'rgb(' + rgb.map((v) => Math.round(v * 150)).join(',') + ')'); GX.fillStyle = g; GX.beginPath(); GX.arc(c[0], c[1], r, 0, 6.2832); GX.fill(); }
  }
}
let goalIdx = -1;
function goalTick(time) {
  let tgt = null; for (const p of PILLS) if (!(p.taken || p.t > 1e14) && p.z < PH.z - 4) { tgt = p; break; }          // the nearest one still ahead
  if (!PLAY || st.paused || !tgt || PH.z - tgt.z > 900) { GOAL.style.display = 'none'; return; }
  const mol = MOLS[tgt.id]; if (!mol) { GOAL.style.display = 'none'; return; }
  _rv.set(tgt.x, th(tgt.x, tgt.z) + 3, tgt.z).project(camera); const W = innerWidth; let px = (_rv.x * .5 + .5) * W, off = 0; if (_rv.z > 1) { px = _rv.x > 0 ? 0 : W; off = _rv.x > 0 ? -1 : 1; } if (px < 50) { px = 50; off = off || -1; } if (px > W - 50) { px = W - 50; off = off || 1; }
  GOAL.style.display = 'block'; GOAL.style.left = px + 'px'; const col = 'rgb(' + mol.c.map((v) => Math.round(v * 255)).join(',') + ')'; GA.style.borderTopColor = col; GA.style.filter = 'drop-shadow(0 0 6px ' + col + ')';
  const dz = PH.z - tgt.z; GT.textContent = (off < 0 ? '< ' : '') + mol.name + '  ' + Math.round(dz) + ' m' + (off > 0 ? ' >' : ''); drawMol(mol, time * .001);
}

// ---------------------------------------------------------------- BEACONS: every target is a tall coloured column of light, drawn through the fog, so it can be picked out from far up the slope against the scenery and the road. Colour says what it is (orange boost, cyan shield and rails, magenta sugar and ramps, pink donut, gold pads); the molecule is the tallest, widest, and pulses.
const BCOL = { saw: [1, .7, .25], boost: [1, .55, .1], shield: [.3, .9, 1], mult: [.72, .35, 1], donut: [1, .45, .75], pad: [1, .8, .2], rail: [.3, 1, .95], ramp: [1, .3, 1], mol: [1, 1, 1] };
const bGeo = new THREE.PlaneGeometry(1, 1); bGeo.translate(0, .5, 0);
const BEAC = []; const BMAT = {};
function mkBeacon(o, x, z, y, kind, w, h, col) {
  const c = col || BCOL[kind] || [1, 1, 1];
  const bkey = kind + c.join(',') + w + h; const m = new THREE.Mesh(bGeo, BMAT[bkey] || (BMAT[bkey] = new THREE.ShaderMaterial({ uniforms: { col: { value: new THREE.Vector3(c[0], c[1], c[2]) }, uW: { value: w }, uH: { value: h }, uMA: { value: kind === 'mol' ? .055 : (kind === 'ramp' || kind === 'rail' ? .03 : .018) }, uP: { value: 0 }, uTime: U.uTime }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    vertexShader: `varying vec2 vUv; uniform float uW, uH, uMA; void main(){ vUv = uv; vec3 o = modelMatrix[3].xyz; vec3 toC = cameraPosition - o; float dd = length(toC); toC.y = 0.; vec3 r = normalize(cross(vec3(0., 1., 0.), toC + vec3(1e-4))); float W = max(uW, dd * uMA); vec3 wp = o + r * position.x * W + vec3(0., position.y * max(uH, dd * uMA * 7.), 0.);          /* never thinner than a fixed angle on screen: a distant beam is still a clear bar */ gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.); }`,
    fragmentShader: `varying vec2 vUv; uniform vec3 col; uniform float uP, uTime; void main(){ float ex = 1. - abs(vUv.x - .5) * 2.; float core = pow(ex, 2.2); float fall = pow(1. - vUv.y, 1.3) * smoothstep(0., .04, vUv.y); float pulse = .8 + .2 * sin(uTime * 4. + vUv.y * 9. - uP * 6.); gl_FragColor = vec4(col * (.55 + .9 * core), (core * .85 + ex * .15) * fall * pulse); }` })));
  m.position.set(x, y, z); m.frustumCulled = false; m.renderOrder = 5; scene.add(m); BEAC.push({ m, o, kind, z });
}
const PT_ = lvl.pitch || []; const hApprox = (z) => { let e = PT_[0]; for (const q of PT_) if (q.z >= z) e = q; return e ? e.h - e.s * (e.z - z) : 0; };          // the slope table: a good-enough ground height where the row (and its ground) has not been streamed in yet
const _bAt = (x, z) => { const g = groundY(x, z); return g === null ? hApprox(z) : g; };
for (const b of BUFFS) mkBeacon(b, b.x, b.z, (b.y !== undefined ? b.y - 1.9 : _bAt(b.x, b.z)), b.t === 'boost' ? 'boost' : b.t === 'shield' ? 'shield' : b.t === 'mult' ? 'mult' : b.t === 'saw' ? 'saw' : 'donut', 3.2, 48);
for (const pd of PADS) mkBeacon(pd, pd.x, pd.z, _bAt(pd.x, pd.z), 'pad', 3, 38);
for (const f of RAILS) mkBeacon(f, featX(f, f.za), f.za, _bAt(featX(f, f.za), f.za), 'rail', 3, 44);
for (const k of VXS) if (k.trail) mkBeacon(k, k.x, k.z, _bAt(k.x, k.z), 'ramp', 5, 64);
for (const mm of PILLS) { const mo = MOLS[mm.id]; mkBeacon(mm, mm.x, mm.z, _bAt(mm.x, mm.z), 'mol', 7, 160, mo ? mo.c : null); }
let molPing = 0;
function beaconTick(time) {
  for (const B of BEAC) { const o = B.o; const gone = o.taken || o.used || o.done || o.hidden || o.gone || o.zoneHid || o.thin || o.dead || o.t > 1e14;          /* a light never outlives its object */ B.m.visible = !gone && PLAY && Math.abs(B.z - PH.z) < (B.kind === 'mol' ? 900 : (B.kind === 'ramp' ? 520 : 340));  }
  // the molecule ahead pings, faster the closer it gets (a quiet two-note tick), so it is heard before it is seen
  const tg = PILLS.find((p) => !(p.taken || p.t > 1e14) && p.z < PH.z - 4);
  if (PLAY && !st.paused && tg) { const d = PH.z - tg.z; if (d < 900) { const period = Math.max(.35, d / 700); if (time / 1000 - molPing > period) { molPing = time / 1000; tone(740 + 500 * (1 - d / 900), 740 + 500 * (1 - d / 900), .09, .12); } } }
}
const addObsG = (x, z, r) => { const ob = { x, z, r, k: 0 }; const key = Math.floor(x / 8) + ',' + Math.floor(z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); };
const SPW = createSpawn({ scene, MOLS, MOL_ORDER, th, railY, BUFFS, PADS, RAILS, PILLS, addObs: addObsG, vegSrc: VEGSRC, trailX,
  onTarget: (o, kind) => { if (kind === 'pad') mkBeacon(o, o.x, o.z, th(o.x, o.z), 'pad', 3, 38); else if (kind === 'rail') mkBeacon(o, o.kx, o.za, th(o.kx, o.za), 'rail', 3, 44); else if (kind === 'mol') { const mo = MOLS[o.id]; mkBeacon(o, o.x, o.z, th(o.x, o.z), 'mol', 7, 160, mo ? mo.c : null); } else mkBeacon(o, o.x, o.z, o.y - 2.4, kind, 3.2, 48); } });
PH.lap = 0; let GROUND_END = 0; for (const gm of ground) { gm.geometry.computeBoundingBox(); const bb = gm.geometry.boundingBox.clone().applyMatrix4(gm.matrix); GROUND_END = Math.min(GROUND_END, bb.min.z); }
const WORLD_END = lvl.stream ? -(180 * lvl.nrows) + 220 : GROUND_END + 280;          // the ground ends at GROUND_END: reset 280 m before it, so the edge is never reached or seen up close
const SB = createSnowball({ boulders: !Q.has('snowballs'), glow: (m) => (Q.has('noglow') ? m : glowify(m, { uTime: U.uTime, uBeat: U.uBeatG }, { rim: 1.1, beat: .35 })), THREE, scene, th, PH, toast, SFX, SPK, halfW: C.W_HALF, worldEnd: WORLD_END, molColors: MOL_ORDER.map((id) => MOLS[id].c), onHit: () => { PH.chain = 0; shudder(.8); try { PSY.events.onCrash('snowball', { shield: PH.shield > 0 }); FX.E.ballHit([PH.x, PH.y, PH.z]); } catch (e) { } }, onDodge: () => { chainHit(); try { PSY.events.onSnowball('dodge', 0); } catch (e) { } }, onEscape: () => { chainHit(); chainHit(); try { FX.E.snowballEnd([PH.x, PH.y, PH.z]); } catch (e) { } try { PSY.events.onSnowball('escape', 0); } catch (e) { } }, onWarn: (lv) => { PH.sbWarn = lv; try { PSY.events.onSnowball('close', lv); } catch (e) { } }, onShake: () => { } });
function buildWorld() { SB.reset(); VFX.reset(); if (lvl.stream) { PILLS.sort((a, b) => b.z - a.z); return {}; } const r = SPW.build(lvl.seed || 7, WORLD_END, Math.min(C.W_HALF - 4, 120), PH.lap); PILLS.sort((a, b) => b.z - a.z); window.__world = r; return r; }
if (PLAY) buildWorld();
if (PLAY && lvl.stream) { /* nothing generated: the rows are Godot's */ }
const RET = document.createElement('div'); RET.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:6;overflow:hidden'; document.body.appendChild(RET);
const retEls = []; const _rv = new THREE.Vector3();
function retEl(i) { if (!retEls[i]) { const e = document.createElement('div'); e.style.cssText = 'position:absolute;border-radius:50%;transform:translate(-50%,-50%);box-sizing:border-box'; RET.appendChild(e); retEls[i] = e; } return retEls[i]; }
function reticleTick(time) {
  let n = 0; const W = innerWidth, H = innerHeight;
  const place = (c, locked) => {
    const y = (c.y !== null && c.y !== undefined ? c.y : th(c.x, c.z)) + 1.6; _rv.set(c.x, y, c.z).project(camera); if (_rv.z > 1 || _rv.z < -1) return; const px = (_rv.x * .5 + .5) * W, py = (-_rv.y * .5 + .5) * H; if (px < -40 || px > W + 40 || py < -40 || py > H + 40) return;
    const e = retEl(n++); e.style.display = 'block'; e.style.left = px + 'px'; e.style.top = py + 'px';
    if (locked) { const pr = 1 + .12 * Math.sin(time * .008), sz = Math.max(46, Math.min(110, 5200 / Math.max(c.dz, 30))) * pr; e.style.width = sz + 'px'; e.style.height = sz + 'px'; e.style.border = '3px solid #3f6'; e.style.boxShadow = '0 0 14px #3f6, inset 0 0 12px #3f68'; e.style.background = 'transparent'; e.style.opacity = '1'; e.style.borderRadius = '50%'; }
    else { const sz = Math.max(10, Math.min(30, 2200 / Math.max(c.dz, 30))); e.style.width = sz + 'px'; e.style.height = sz + 'px'; e.style.border = '2px solid #3f6a'; e.style.boxShadow = 'none'; e.style.background = 'transparent'; e.style.opacity = '.7'; e.style.borderRadius = '30%'; }
  };
  if (PLAY && !st.paused) { for (const c of PH.cands) if (!PH.latch || c.o !== PH.latch.o) place(c, false); if (PH.latch) place({ x: PH.latch.x, y: PH.latch.y, z: PH.latch.z, dz: PH.latchDist }, true); }
  for (let i = n; i < retEls.length; i++) retEls[i].style.display = 'none';
}
const DBGON = Q.has('dbg'), DBG = { noGround: 0, maxQ: 0, frames: 0 };

// GAZE ORBS (RunRig._orb_add / _orb_station / _orb_tick): prizes that only need to be LOOKED at. Stations of three (left, middle, right) float 2.6 m (sides) and 5.6 m (middle) above the ground on purpose; each one fills while you look
// toward its side (head turned or steering that way, past 0.3) and is collected when full (0.36 s). The nearest orb on the side you look at fills, the others drain; one of the three is gold and worth double; collecting in a row builds a streak.
const GAZE = { streak: 0, t: 0 }, _gv3 = new THREE.Vector3();
function setOrbScale(o, k) { const nd = NBN[nameOf(o.n)]; if (!nd) return; for (const m of (REGN[nd.name] || [])) { if (!m.userData.bm) m.userData.bm = m.matrix.clone(); m.matrix.copy(m.userData.bm).scale(_gv3.set(k, k, k)); m.matrixWorldNeedsUpdate = true; } }
function gazeOrbStep(dt, sIn) {
  GAZE.t = Math.max(GAZE.t - dt, 0); if (GAZE.t <= 0) GAZE.streak = 0;
  const look = Math.abs(sIn) < .3 ? 0 : (sIn > 0 ? 1 : -1), j0 = Math.max(0, Math.floor(-PH.z / 180)); let best = null, bdz = 1e9;
  for (let j = j0 - 1; j <= j0 + 1; j++) { const r = lvl.rows && lvl.rows[String(j)]; if (!r || !r.orbs) continue;
    for (const o of r.orbs) { if (o.got) continue; const dz = PH.z - o.p[2];
      if (dz < 2 || dz > 70) { if (o.dwell > 0) { o.dwell = 0; setOrbScale(o, 1); } continue; }
      if (o.side === look && dz < bdz) { best = o; bdz = dz; } else if (o.dwell > 0) { o.dwell = Math.max(o.dwell - dt * 1.5, 0); setOrbScale(o, 1 + .9 * o.dwell / .36); } } }
  if (!best) return; best.dwell += dt; setOrbScale(best, 1 + .9 * best.dwell / .36);
  if (best.dwell >= .36) { best.got = true; hideNode(best.n); GAZE.streak++; GAZE.t = 2.6; PH.score += (best.big ? 130 : 60) * Math.min(GAZE.streak, 8); SFX.orb(); if (GAZE.streak >= 3) toast('LOOK x' + GAZE.streak, '#fd6'); }
}
function playStep(dt, first = true, frameDt = dt) {          // dt is one physics sub-step (never more than 1/58 s); the first sub-step of a frame also does the once-per-frame work (row streaming, reading the head)
  if (first) { rowsUpdate(PH.ready ? PH.z : st.z); pumpBuild(BQ.length > 700 ? 10 : (BQ.length > 120 ? 7 : 4)); } if (DBGON && first) { DBG.frames++; DBG.maxQ = Math.max(DBG.maxQ, BQ.length); if (groundY(PH.x, PH.z) === null) DBG.noGround++; }
  if (first) headStep(frameDt, performance.now()); if (HD.on && performance.now() - HD.t > 600) HD.lost = true; if (window.__mk) window.__mk.style.left = (97 + (window.__steer || 0) * 97) + 'px';
  if (!PH.ready && START_ROW > 0 && groundY(0, st.z) === null) return;          // a jump-in start waits until the ground under it has loaded (else the board spawns at y=0 and falls)
  if (!PH.ready) { PH.x = 0; PH.z = st.z; PH.y = th(0, PH.z); PH.gh_prev = PH.y; PH.prevZ = PH.z; PH.ready = true; }
  const prog = Math.min(Math.max(-PH.z, 0) / C.PULL_RAMP, 1); PH.hurt = Math.max(PH.hurt - dt, 0); PH.boost_t = Math.max(PH.boost_t - dt, 0); PH.slide *= Math.exp(-dt / .3);
  let hs = window.__steer || 0; hs = Math.sign(hs) * Math.pow(Math.abs(hs), .8);          // a small turn of the head is a small nudge; only a decided one is a big move
  let sIn;
  if (ASSIST === 'lane' || ASSIST === 'aim') {          // the head selects; the board carves
    const ls = K.r - K.l + hs, la = Math.abs(ls);
    if (ASSIST === 'lane') { if (ls < -.30) { LANE.i = -1; LANE.n = 0; } else if (ls > .30) { LANE.i = 1; LANE.n = 0; } else if (la < .14) { LANE.n += dt; if (LANE.n > .3) LANE.i = 0; } else LANE.n = 0; }
    const rk0 = nearRamp(), lim = Math.min(C.W_HALF - 3, Math.max(C.W_HALF - 14, rk0 ? Math.abs(rk0.x) + 6 : 0)), aimd = Math.sign(ls) * Math.max(0, la - .015) / .985, lx = Math.max(-lim, Math.min(lim, trailX(PH.z - 20) + (ASSIST === 'lane' ? LANE.i * LANE_W : Math.max(-1.1, Math.min(1.1, aimd)) * REACH))); if (LANE.x === null) { LANE.x = PH.x; LANE.born = performance.now(); } const lxA = (rk0 && Math.sign(ls) === Math.sign(rk0.x - PH.x) && la > .2) ? lx + (rk0.x - lx) * sstep(.2, .6, la) : lx;          /* steering toward a ramp that is out at the side: the aim point slides to its mouth, so a full head turn reaches it */
    const vw = (PH.vlock !== null && PH.grounded && ASSIST === 'aim') ? Math.max(0, Math.min(1, sp('vxhold', .5))) * (1 - sstep(.05, .3, la)) : 0, tgtL = lxA + ((PH.vlock === null ? lxA : PH.vlock) - lxA) * vw, SPp = ASSIST === 'aim' ? Math.max(0, Math.min(1, sp('smoothpath', 1))) : 0;
    if (SPp > 0) { const big = Math.max(0, Math.min(1, Math.abs(tgtL - LANE.x) / 8)), w = (1 / Math.max(.05, sp('aimtau', .1) + SPp * .3 + vw * sp('vxslow', .12))) * (1 + 2.2 * big); LANE.v = LANE.v || 0; const ns = 4, h = dt / ns; for (let q = 0; q < ns; q++) { LANE.v += (w * w * (tgtL - LANE.x) - 2 * w * LANE.v) * h; LANE.x += LANE.v * h; } } else LANE.v = 0;          /* SMOOTH PATH (&smoothpath=0..1): the aim point glides to where the head points on a critically damped spring (no overshoot, gentle start and end), stiffer when the head makes a big, decisive move so it never fights you; 0 = the plain easing below */
    if (!(SPp > 0)) LANE.x += (tgtL - LANE.x) * (1 - Math.exp(-dt / ((ASSIST === 'lane' ? .18 : sp('aimtau', .1)) + Math.max(0, 1 - (performance.now() - LANE.born) / 1500) * .9)));
    const slowK = (1 - sstep(14 * SPK, 40 * SPK, Math.hypot(PH.vx, PH.vz))) * Math.max(0, sp('slowboost', 1)); if (!C.TH0) C.TH0 = C.THETA_MAX; C.THETA_MAX = C.TH0 * (1 + .5 * slowK);
    sIn = Math.max(-1, Math.min(1, (LANE.x - (PH.x + PH.vx * (.45 + .55 * sp('stab', 1) * (1 - sstep(.05, .3, la))) * (1 + .5 * slowK * (1 - sstep(.05, .3, la))))) / (10 / (1 + .8 * slowK * sstep(.03, .25, la))))); if (ASSIST === 'lane') LANEPIPS(LANE.i);
  } else sIn = Math.max(-1, Math.min(1, K.r - K.l + hs));
  bankAuto(dt); reachStep(dt); const sHead = sIn; if (!PH.rail && PH.ready) gazeOrbStep(dt, sHead); PH.sVel = (PH.sVel || 0) + (Math.max(-12, Math.min(12, (sIn - (PH.sPrev || 0)) / Math.max(dt, 1e-3))) - (PH.sVel || 0)) * .2; PH.sPrev = sIn; const sPred = Math.max(-1, Math.min(1, sIn + .22 * PH.sVel));          // (where the lean is heading, so the assist can pick the gate you mean a moment earlier)
  // LOCK-ON (RunRig._update_buff_aim + _guard_path): every pickup, pad, rail and ramp up to 260 m ahead is a candidate; nudge toward one (or line one up dead ahead) and the green reticle locks on. While locked the board is pulled toward it by Godot's rule
  // (want = (target x - (x + 0.45 vx)) / 12, weight building at 4 per second, strength fading a little with distance), and the last stretch tugs you forward so you are slung into it. Nudge hard the other way to let go.
  { const lt = PH.latch; if (lt && (PH.z - lt.z < 2 || lt.o.taken || lt.o.used || lt.o.done || lt.o.t > 1e14 || (Math.abs(sIn) > .5 && Math.sign(sIn) !== Math.sign(lt.x - PH.x)) || Math.abs(lt.x - PH.x) > 60 || PH.z - lt.z > 270)) PH.latch = null;
    PH.cands.length = 0; const addC = (o, z, x, y, kind) => { const dzz = PH.z - z; if (dzz > 8 && dzz < 260 && Math.abs(x - PH.x) < 48) PH.cands.push({ o, z, x, y, kind, dz: dzz, dx: x - PH.x }); };
    if (!PH.rail) { for (const b of BUFFS) if (!b.taken && Math.abs(b.z - PH.z) < 270) addC(b, b.z, b.x, b.y, 'buff'); for (const pd of PADS) if (!pd.used && Math.abs(pd.z - PH.z) < 270) addC(pd, pd.z, pd.x, null, 'pad'); for (const f of RAILS) if (!f.done && Math.abs(f.za - PH.z) < 270) addC(f, f.za, featX(f, f.za), null, 'rail'); for (const k of VXS) if (!k.done && Math.abs(k.z - PH.z) < 270) addC(k, k.z, k.x, null, 'ramp'); for (const m of PILLS) if (!(m.taken || m.t > 1e14) && Math.abs(m.z - PH.z) < 270) addC(m, m.z, m.x, null, 'mol'); { const j0 = Math.max(0, Math.floor(-PH.z / 180)); for (let rj = j0; rj <= j0 + 2; rj++) { const rr = lvl.rows && lvl.rows[String(rj)]; if (rr && rr.has_row && rr.gaps) for (const gp of rr.gaps) addC(gp, rr.z, gp.x, null, 'gate'); } } }          /* the barrier's gates are lock-on targets too: lean toward one and the board carves through it (Godot: the eyes choose, the board carves) */
    if (!PH.latch && !PH.rail) { let bd = 1e9, best = null; for (const c of PH.cands) { const side = Math.sign(c.dx) === Math.sign(sPred) && Math.abs(sPred) > .1 && Math.abs(sIn) > .04, ahead = Math.abs(c.dx) < 3 && c.dz < 70; if (!side && !ahead) continue; const sc = Math.abs(c.dx) + .06 * c.dz; if (sc < bd) { bd = sc; best = c; } } if (best) PH.latch = { z: best.z, x: best.x, y: best.y, o: best.o, kind: best.kind, w: 0 }; }
    if (PH.latch) { const L = PH.latch; L.w = Math.min(1, L.w + 4 * dt); const dzl = PH.z - L.z, kd = Math.max(.35, Math.min(1, 1.25 - dzl / 260)); const want = Math.max(-.9, Math.min(.9, (L.x - (PH.x + PH.vx * .45)) / 9)); sIn = Math.max(-1, Math.min(1, sIn + AK * L.w * kd * Math.min(1, dzl / 6) * want * (1 - .5 * Math.abs(sIn)))); PH.latchDist = dzl; }
    else PH.latchDist = 1e9; }
  sIn = Math.max(-1, Math.min(1, sIn + wellSteer(sIn, dt)));
  if (!PH.rail && PH.grounded) {          // LANE HOLD (RunRig._free_shift): the smallest shift that clears every tree and rock coming up in the next second, applied early, and any nudge toward a tree is cancelled: you are held in the lane beside it
    const spd = Math.max(Math.hypot(PH.vx, PH.vz), 20), look = Math.min(90, spd * 1.15), cx2 = Math.floor(PH.x / 8), cz2 = Math.floor(PH.z / 8), reach = Math.ceil(look / 8) + 1; let push = 0, block = 0;
    for (let ci = -2; ci <= 2; ci++) for (let cj = -reach; cj <= 1; cj++) { const a = OGRID.get((cx2 + ci) + ',' + (cz2 + cj)); if (!a) continue;
      for (const o of a) { const dzz = PH.z - o.z; if (dzz < -1 || dzz > look) continue; const tt = Math.max(dzz, 0) / spd, xp = PH.x + PH.vx * tt * .8, clr = o.r + C.SLED_R + 2.2, d = xp - o.x; if (Math.abs(d) >= clr) continue;
        const side = Math.sign(d) || Math.sign(PH.x - o.x) || (o.x > 0 ? -1 : 1), urg = Math.max(.25, 1 - dzz / look), need = Math.min(1, (clr - Math.abs(d)) / 3); push += side * need * urg * 1.4; if (Math.sign(sIn) === -side && Math.abs(sIn) > .05) block = Math.max(block, urg); } }
    if (push) sIn = Math.max(-1, Math.min(1, sIn * (1 - .85 * block) + Math.max(-1.1, Math.min(1.1, push)))); }
  if (!PH.rail && !nearRamp()) { const ex = Math.abs(PH.x), edge = sstep(C.W_HALF - 16, C.W_HALF - 4, ex); sIn = Math.max(-1, Math.min(1, sIn - Math.sign(PH.x) * edge * .9)); }          // the banked walls turn you back: no sliding up the side
  if (PH.vlock !== null && PH.grounded) sIn = Math.max(-1, Math.min(1, sIn + Math.max(-1, Math.min(1, (PH.vlock - PH.x) / 12)) * sp('vxsteer', .35) * (1 - sstep(.08, .35, Math.abs(window.__steer || 0)))));          // the swirl has the board's own steering aim at the ramp too
  ASM += ((sIn - sHead) - ASM) * (1 - Math.exp(-dt / .16)); sIn = Math.max(-1, Math.min(1, sHead + ASM));          // the assists, low-passed
  let steer = sIn; if (Math.abs(sIn) < .3) steer = Math.max(-1, Math.min(1, steer - .1 * Math.max(-1, Math.min(1, PH.vx / (10 * SPK)))));
  const wFast = 13 * STK, dSt = Math.abs(steer - PH.steer), kSt = Math.min(1, Math.max(0, (dSt - .05) / .3)), w = SMOOTHW + (wFast - SMOOTHW) * kSt;          /* an ADAPTIVE spring: a small change in the command (head jitter) meets a soft spring (about SMOOTHW rad/s), a big deliberate turn meets the stiff one, so the board is smooth without losing accuracy. ?smooth=N sets the soft value (lower = smoother), - and = change it live */
  { const ns = Math.max(1, Math.ceil(w * dt / .25)), h = dt / ns; for (let q = 0; q < ns; q++) { const acc = w * w * (steer - PH.steer) - 2 * w * PH.sv; PH.sv += acc * h; PH.steer = Math.max(-1, Math.min(1, PH.steer + PH.sv * h)); } } steer = PH.steer;          /* sub-stepped: a stiff spring integrated once per frame rings and flips +-1 every frame (that was the soft, diagonal, wobbly feel) */
  PH.heading += (steer * C.THETA_MAX * (PH.grounded ? 1 : .4) - PH.heading) * (1 - Math.exp(-dt / (PH.grounded ? .05 : .4)));
  const fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading), rx = Math.cos(PH.heading), rz = Math.sin(PH.heading), prevY = PH.y, ox0 = PH.x, oz0 = PH.z;
  if (PH.grounded) {
    const e = .6, gx = (th(PH.x + e, PH.z) - th(PH.x - e, PH.z)) / (2 * e), gz = (th(PH.x, PH.z + e) - th(PH.x, PH.z - e)) / (2 * e), g2 = gx * gx + gz * gz;
    const spd = Math.hypot(PH.vx, PH.vz); if (spd < C.MIN_SPEED) { PH.vx += fx * (C.MIN_SPEED - spd) * 1.2 * dt; PH.vz += fz * (C.MIN_SPEED - spd) * 1.2 * dt; }
    PH.vx += -C.G * gx / (1 + g2) * dt; PH.vz += -C.G * gz / (1 + g2) * dt;
    let sp = Math.hypot(PH.vx, PH.vz); const drag = C.DRAG * (1 - .5 * prog) * (PH.boost_t > 0 ? .3 : 1);
    if (PH.boost_t > 0 && spd < C.SPEED_CAP) { PH.vx += fx * 7 * SPK * dt; PH.vz += fz * 7 * SPK * dt; }
    if (sp > .01) { const dec = Math.min((.22 + drag * sp * sp) * dt, sp); PH.vx -= PH.vx / sp * dec; PH.vz -= PH.vz / sp * dec; }
    PH.grade = Math.max(0, Math.min(1.5, -(gx * fx + gz * fz)));          // how steeply the way you are heading runs downhill
    sp = Math.hypot(PH.vx, PH.vz); const vcap = (C.TRAIL_VMAX * ramp() + (PH.boost_t > 0 ? 8 * SPK : 0) + (PH.vxa > 0 ? 9 * SPK : 0)) * (1 + .28 * PH.grade); if (sp > vcap) { const k = (sp - vcap) * (PH.mom > 0 ? .12 : .7) * dt; PH.vx -= PH.vx / sp * k; PH.vz -= PH.vz / sp * k; }
    const old = Math.hypot(PH.vx, PH.vz); let along = PH.vx * fx + PH.vz * fz; const lat = PH.vx * rx + PH.vz * rz, latN = lat * Math.exp(-C.GRIP * (Math.abs(PH.steer) < .15 ? 2.2 : 1) * dt);          // (with the head straight the board straightens along its lane: the sideways slide is killed twice as hard)
    along += Math.abs(lat - latN) * .6 * Math.sign(Math.abs(along) > .01 ? along : 1); PH.vx = fx * along + rx * latN; PH.vz = fz * along + rz * latN; const v = Math.hypot(PH.vx, PH.vz); if (v > old) { PH.vx *= old / v; PH.vz *= old / v; }
  } else {
    const sp2 = Math.hypot(PH.vx, PH.vz); if (sp2 > .01) { const dd = Math.min(C.DRAG * .4 * sp2 * sp2 * dt, sp2); PH.vx -= PH.vx / sp2 * dd; PH.vz -= PH.vz / sp2 * dd; }
    { const wg = PH.wings > 0 ? TUNE.wings.steer : 1; const lat = 22 * wg * Math.max(1, SPK); PH.vx += sIn * lat * dt; const cap = 26 * (wg > 1 ? TUNE.wings.cap : 1) * Math.max(1, SPK); PH.vx = Math.max(-cap, Math.min(cap, PH.vx)); PH.vx *= Math.exp(-.25 * dt); }          // (steer in the air to aim the landing)
    const aHigh = PH.y - th(PH.x, PH.z) - 34 * SPK; if (aHigh > 0 && PH.vy > -12) PH.vy -= Math.min(aHigh * 6, 30) * dt;
    PH.air_t += dt;
  }
  { const cap = PSY.perks().speedK * (C.TRAIL_SPEED * ramp() + 6 * SPK * prog + (PH.boost_t > 0 ? 4 * SPK : 0) + (PH.vxa > 0 ? 9 * SPK : 0)) * (1 + .28 * PH.grade), spn = Math.hypot(PH.vx, PH.vz); if (spn > cap) { const k = 1 - Math.exp(-(PH.mom > 0 ? .1 : .5) * dt); PH.vx -= PH.vx * k * (1 - cap / spn); PH.vz -= PH.vz * k * (1 - cap / spn); } { const hard = Math.min(cap * (PH.mom > 0 ? 1.5 : 1.25), C.SPEED_CAP), sp3 = Math.hypot(PH.vx, PH.vz); if (sp3 > hard) { const k3 = 1 - Math.exp(-3 * dt); PH.vx -= PH.vx * k3 * (1 - hard / sp3); PH.vz -= PH.vz * k3 * (1 - hard / sp3); } }          // (momentum may carry you well past the cap, but never without limit)
  PH.mom = Math.max(PH.mom - dt, 0); }
  if (PH.latch && PH.grounded && PH.latchDist < 28 && PH.latchDist > 0) { const tug = 10 * SPK * dt * PH.latch.w * (1 - PH.latchDist / 28); PH.vx += fx * tug; PH.vz += fz * tug; PH.vxa = Math.max(PH.vxa, .25); }
  if (PH.ready && !st.paused && -PH.z < sp('launchzone', 450) && PH.hurt <= 0) PH.boost_t = Math.max(PH.boost_t, .4);          /* the launch zone */
  if (PH.vxa > 0 || PH.boost_t > 0) PH.mom = Math.max(PH.mom, 1.2);
  PH.vz = Math.min(PH.vz, -3); PH.x += PH.vx * dt; PH.z = Math.min(PH.z + PH.vz * dt, 0);
  if (Math.abs(PH.x) >= C.W_HALF - 2.5) { PH.x = Math.max(-(C.W_HALF - 2.5), Math.min(C.W_HALF - 2.5, PH.x)); PH.vx *= -.2; }
  const gh = th(PH.x, PH.z), gvy = Math.max(-60, Math.min(60, (gh - PH.gh_prev) / Math.max(dt, 1e-4)));
  if (PH.grounded) { const vg = (gh - prevY) / Math.max(dt, 1e-4); if (vg < PH.vy - C.GV * dt - .4 - .03 * Math.hypot(PH.vx, PH.vz)) {          // (the board stays glued over small crests: the faster it goes, the bigger the drop has to be to leave the snow)
 PH.grounded = false; PH.air_t = 0; PH.vy = PH.vy - C.GV * dt; PH.y = prevY + PH.vy * dt; } else { PH.y = gh; PH.vy = Math.min(vg, C.JUMP_LAUNCH); } }
  else {
    PH.vy -= C.GV * dt * C.AIR_G_K; if (PH.air_t > 2.4) PH.vy -= 26 * SPK * (PH.air_t - 2.4) * dt; PH.vy = Math.max(PH.vy, -90 * SPK); PH.y += PH.vy * dt;          // (a flight longer than about two seconds is pulled down harder and harder)
    if (PH.y <= gh + .05 || PH.y < gh) { const impact = Math.max(gvy - PH.vy, 0); PH.landT = PH.air_t; PH.grounded = true; PH.y = gh; PH.vy = gvy; PH.air_t = 0; if (impact > 4 * SPK) { shudder(Math.min(.32, .1 + impact / (60 * SPK))); if (AWON) AW.onLand(impact / SPK, 0); else SFX.land(); VFX.onLand(); FX.E.landSmooth([PH.x, PH.y, PH.z]); } PH.mom = 2.6; if (impact > 18 * SPK) crash('WIPEOUT!', 'tree'); else if (impact > 12 * SPK) { PH.vx *= .97; PH.vz *= .97; } else if (PH.landT > .5) { const fx2 = Math.sin(PH.heading), fz2 = -Math.cos(PH.heading), kick = (4 + 3 * Math.min(PH.landT, 3)) * SPK; PH.vx += fx2 * kick; PH.vz += fz2 * kick; PH.boost_t = Math.max(PH.boost_t, 1.1); PH.vxa = Math.max(PH.vxa, .8); toast(impact < 5 * SPK ? 'SMOOTH LANDING!' : 'LANDED', '#7fa'); SFX.snap(); chainHit(); } }          // (a landing after a real flight is a boost, and a link in the chain)
  }
  PH.gh_prev = gh;
  if (PH.z < WORLD_END) { PH.lap++; toast('LAP ' + PH.lap + ' DONE  score ' + Math.floor(PH.score), '#ff6'); buildWorld(); for (const r of ROWS) { for (const b of (r.buffs || [])) b.taken = false; for (const pd of (r.pads || [])) pd.used = false; for (const f of (r.feats || [])) f.done = false; for (const t of (r.toys || [])) { t.used = false; if (t.t > 1e14) t.t = 0; } } PH.z = -2; PH.x = 0; PH.vx = 0; PH.vz = -20; PH.y = th(0, -2); PH.gh_prev = PH.y; PH.vy = 0; PH.grounded = true; PH.prevZ = -2; PH.rail = null; SFX.grindOff(); }
  railStep(dt, sIn); vortexStep(dt, sIn); if (window.__kitStep) window.__kitStep(dt); toys.tick(dt, sIn); collectStep(); if (!toys.active()) obstacleStep(ox0, oz0); PH.prevZ = PH.z; VFX.tick(dt, clock.t);
  if (PH.mult > 0) PH.mult -= dt; if (PH.wings > 0) PH.wings -= dt; PH.score += dt * Math.hypot(PH.vx, PH.vz) * .02 * (PH.mult > 0 ? 2 : 1);
  GSPEED += (Math.min(1, Math.max(0, Math.hypot(PH.vx, PH.vz) / SPK / 45)) - GSPEED) * Math.min(1, dt * 2); { const bp = gmOn ? GM.beatPos() : 0; if (gmOn && bp > 0 && BEATFX.k > 0) { const ph = bp - Math.floor(bp), bar = (Math.floor(bp) % 4 === 0) ? 1 : .55; const chillNow = CHILL || (GM.arc && GM.arc.stage === 'chill'); const kick = chillNow ? .5 + .5 * Math.sin(bp * Math.PI / 4) : Math.exp(-ph * 7) * bar;          /* (Moodless Refrain is not on the 128 BPM grid: in the chill-out the picture breathes slowly instead of kicking) */ BEATFX.pulse += (kick - BEATFX.pulse) * Math.min(1, dt * 40); } else BEATFX.pulse *= Math.exp(-dt * 6);
  const bk = BEATFX.pulse * BEATFX.k; U.uBeatG.value = bk; BEATFX.fov = 1 + .018 * bk; renderer.toneMappingExposure = BEATFX.exp * (1 + .07 * bk) * CAVE.mul; for (const gm of GMATS) gm.uniforms.speed.value = Math.min(1.3, GSPEED + .22 * bk); }
  { const fxv = Math.sin(PH.heading), fzv = -Math.cos(PH.heading); TRB.update(PH.x, PH.y, PH.z, fxv, fzv, PH.boost_t > 0); TRM.update(PH.x, PH.y, PH.z, fxv, fzv, PH.mult > 0); SPRAY.update(PH.x, PH.y, PH.z, fxv, fzv, PH.grounded && Math.hypot(PH.vx, PH.vz) / SPK > 8); FX.tick(dt); auraUpd(dt); }
  chainTick(dt); SPW.tick(clock.t, PH.z); SB.tick(dt); CARVE.tick(dt, PH, clock.t, { dose: PSY.state ? PSY.state.trip || 0 : 0 }); ECHO.tick(dt, PH, clock.t, { dose: PSY.state ? PSY.state.trip || 0 : 0 });
  { const spd = Math.hypot(PH.vx, PH.vz); PSY.tick(dt, { speed: spd / SPK, speedY: -PH.vz / SPK, chain: PH.chain, boosting: PH.boost_t > 0, links: 0, wave: .5, inAir: !PH.grounded, vy: PH.vy / SPK, alt: PH.y - th(PH.x, PH.z), hurtT: PH.hurt, rail: !!PH.rail, tube: toys.active() }); applyPsy(); WFX.tick(dt, clock.t, PSY.world(), { board: { x: PH.x, z: PH.z }, camera, speed01: Math.min(1, spd / SPK / 50), travZ: -PH.z }); if (GROUNDSRC !== 'psy') { const G = WFX.uniforms.ground; G.grid.value = Math.max(G.grid.value, 1); setGroundPal(); } labStep(dt);
    const fl = PSY.state && PSY.state.mbody ? PSY.state.mbody.map((v) => Math.min(1, v / 6)) : [0, 0, 0, 0, 0, 0]; if (gmOn) GM.tick(dt, { chill: CHILL, phase: CHILL ? 'comedown' : (PSY.pacer ? PSY.pacer.phaseName() : undefined), u: PSY.pacer ? Math.min(1, PSY.pacer.t / PSY.pacer.session_s) : 0, tripOn: !Q.has('stems') || !!(PSY.state && PSY.state.trip_on) || fl.reduce((x, y) => x + y, 0) / 6 >= .03, clarityK: PSY.state ? PSY.state.clr_k : 1, sharp: PSY.state ? PSY.state.sharp : 0, felt: fl, excitement: Math.min(1, .3 + spd / (C.SPEED_CAP) * .42 + (PH.chain > 1 ? .2 : 0) + (PH.boost_t > 0 ? .15 : 0)), chain: PH.chain, airborne: !PH.grounded, speed01: Math.min(1, spd / C.SPEED_CAP) });
    const wl = PH.sbWarn || 0; SBH.style.opacity = (.16 * wl * (.7 + .3 * Math.sin(performance.now() * .014))).toFixed(3); SBH.firstChild.style.opacity = (.9 * wl).toFixed(2); PH.sbWarn = Math.max(0, wl - dt * 2); PH.shake = Math.max(0, (PH.shake || 0) - 1.6 * dt); }
  measure(dt, sIn, PH.steer);
  if (toastT > 0) { toastT -= dt; if (toastT <= 0) toastEl.style.opacity = 0; }
  st.x = PH.x; st.z = PH.z;
}
const RIG = createCamRig({ useBike: () => !Q.has('board'), THREE, scene, camera, th: (x, z) => { const g = groundY(x, z); return g === null ? PH.y : g; }, trailX, PH, SPK, PSY, touch: TOUCHLOOK, lookDown: () => sp('camdown', .62), fovMul: () => (LABV.fovMul || 1) * BEATFX.fov * (() => { const base = Math.max(78, Math.min(108, 80 + (Math.hypot(PH.vx, PH.vz) / SPK - 18) * .6)), cap = parseFloat(Q.get('fovcap') || '88'); return base > cap ? cap / base : 1; })() });          /* (Godot widens the view to 108 degrees at speed, which shrinks everything in the distance: capped at 88, ?fovcap=108 for the original) */
const MAE = { adapt: 0, v: 0 };
function maeTick(dt) {          // adaptation fills while you ride fast (about 6 s) and drains slowly (about 12 s); the drift shows when the flow stops: a crash, the pause, the comedown
  if (Q.has('nomae')) { postM.uniforms.mae.value = 0; return; }
  const fl = sstep(.15, .85, GSPEED), chill = CHILL || (GM.arc && GM.arc.stage === 'chill'), rushing = fl > .6 && !st.paused;
  MAE.adapt = Math.max(0, Math.min(1, MAE.adapt + (rushing ? dt / 6 : -dt / 12)));
  const still = st.paused ? 1 : (chill ? Math.max(1 - fl, .6) : 1 - fl); MAE.v += (MAE.adapt * still - MAE.v) * (1 - Math.exp(-dt / .5)); postM.uniforms.mae.value = MAE.v;
}
canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); window.__dm && window.__dm('canvas: context lost (game)'); }, false);
canvas.addEventListener('webglcontextrestored', () => { window.__dm && window.__dm('canvas: context restored: reloading'); let n = 0; try { n = +sessionStorage.getItem('gvReloads') || 0; sessionStorage.setItem('gvReloads', String(n + 1)); } catch (e) { } if (n < 2) location.reload(); else { const d = document.createElement('div'); d.style.cssText = 'position:fixed;inset:0;z-index:99;background:#10041a;color:#fff;font:16px system-ui;display:flex;align-items:center;justify-content:center;text-align:center;padding:20px'; d.textContent = 'The graphics were reset twice in a row. Please reload this page.'; document.body.appendChild(d); } }, false);
setTimeout(() => { try { sessionStorage.setItem('gvReloads', '0'); } catch (e) { } }, 20000);          // a start that lasts 20 s counts as good
let FRAMES_DONE = 0, GATE_T0 = 0, STAT_T = 0;          // the camera model starts only after the game has drawn steadily for a moment (its shaders are compiled by then): both fight over the same graphics chip otherwise
function frame(now) {
  FRAMES_DONE++; if (FRAMES_DONE === 1 || FRAMES_DONE === 30 || FRAMES_DONE === 150 || FRAMES_DONE === 600) window.__dm && window.__dm('frame ' + FRAMES_DONE); if (openGate && FRAMES_DONE >= 6 && !GATE_T0) GATE_T0 = performance.now(); if (openGate && GATE_T0 && FRAMES_DONE >= sp('gateframes', 30) && performance.now() - GATE_T0 > sp('gatems', 500)) { const og = openGate; openGate = null; og(); }
  if (window.__dm && now - STAT_T > 1000) { STAT_T = now; try { const i = renderer.info, t0 = performance.now(); _gl.finish(); const gw = Math.round(performance.now() - t0); window.__dm('stats frames ' + FRAMES_DONE + ' calls ' + i.render.calls + ' tris ' + i.render.triangles + ' programs ' + (i.programs ? i.programs.length : 0) + ' geos ' + i.memory.geometries + ' tex ' + i.memory.textures + ' gpuWait ' + gw + 'ms fps ' + fps.toFixed(0) + ' tier ' + (TIERS ? TIERS.tier : '-') + ' dpr ' + renderer.getPixelRatio().toFixed(2) + ' paused ' + st.paused); } catch (e) { window.__dm('stats failed ' + e.message); } }
  const T0 = performance.now(); requestAnimationFrame(frame); const dt = Math.min(0.05, (now - last) / 1000); last = now; clock.t += dt; U.uTime.value = clock.t;
  animTick(clock.t); maeTick(dt); trailTexInit(); const T1 = performance.now();
  if (START.state === 'go') { START.t += dt; if (START.t > .9) { START.state = 'live'; STARTUI.hide(); } }
  if (PLAY && !PH.ready && HD.on && !SHOT) { PH.x = 0; PH.z = st.z; PH.y = th(0, PH.z); PH.gh_prev = PH.y; PH.prevZ = PH.z; PH.ready = true; window.__dm && window.__dm('board placed at the start line'); }          // in camera mode the game waits paused at the start: the board (and so the camera) must already be at the line, not at the origin inside the terrain, which made the first frames far too heavy and reset the graphics
  if (PLAY && !st.paused && !SHOT) { if (START.hold) startHold(dt); else { const nSub = Math.max(1, Math.ceil(dt / (1 / 58))); for (let si = 0; si < nSub; si++) playStep(dt / nSub, si === 0, dt); } } else if (!PLAY && !st.paused) st.z -= st.speed * dt;
  const T2 = performance.now();
  if (EDGE_UPD) EDGE_UPD(clock.t);
  if (SHOT) { const M4 = mat4(SHOT.xf), p = new THREE.Vector3(), q = new THREE.Quaternion(), sc = new THREE.Vector3(); M4.decompose(p, q, sc); camera.position.copy(p); camera.quaternion.copy(q); if (ring) { const e = ring.matrix.elements; e[12] = p.x; e[13] = p.y - 1.7 - 159.696; e[14] = p.z; } U.uBoard.value.set(p.x, p.z); sky.position.copy(camera.position); renderPost(); return; }
  const gy = PLAY ? PH.y : groundY(st.x, st.z); if (gy !== null) { const tgY = gy + 3.2; if (Math.abs(tgY - st.y) > 6) st.y = tgY; else st.y += (tgY - st.y) * Math.min(1, dt * (PLAY ? 14 : 8)); }
  const ahead = groundY(st.x, st.z - 30); const pitch = (gy !== null && ahead !== null) ? Math.atan2(ahead - gy, 30) : 0;
  if (ring) { const e = ring.matrix.elements; e[12] = st.x; e[13] = st.y - 1.7 - 159.696; e[14] = st.z; }
  { const fv = PLAY ? (CAMD.fp ? PSY.cameraFov(Math.hypot(PH.vx, PH.vz) / SPK, true) * (LABV.fovMul || 1) : camera.fov) : 78; if (Math.abs(fv - camera.fov) > .05) { camera.fov = fv; camera.updateProjectionMatrix(); } }
  if (PLAY && CAMD.mode === 'fp') {          // RunRig.gd 10401-10438, literally
    if (Q.has('oldcam')) { /* the earlier literal camera was replaced by camrig.js (crest lift, hop, board tip, trick lean, Godot's fov fit) */ }
    RIG.update(dt, { age: clock.t, slideV: PH.slide, inAir: !PH.grounded, snap: !CAMD.ldone }); CAMD.ldone = true;
    U.uBoard.value.set(PH.x, PH.z); sky.position.copy(camera.position); if (ring) { const e = ring.matrix.elements; e[12] = camera.position.x; e[13] = camera.position.y - 1.7 - 159.696; e[14] = camera.position.z; }
  } else if (PLAY && CAMD.mode === '3p') {
    const sp = Math.hypot(PH.vx, PH.vz); let vx = 0, vz = -1; if (sp > 1) { vx = PH.vx / sp; vz = PH.vz / sp; } const kd = 1 - Math.exp(-3 * dt); CAMD.dx += (vx - CAMD.dx) * kd; CAMD.dz += (vz - CAMD.dz) * kd; const nn = Math.hypot(CAMD.dx, CAMD.dz) || 1; CAMD.dx /= nn; CAMD.dz /= nn;
    const tx = PH.x - CAMD.dx * 9.5, tz = PH.z - CAMD.dz * 9.5; let ty = PH.y + 6.2 + (PH.grounded ? 0 : .5); const gc = groundY(tx, tz); ty = Math.max(ty, (gc === null ? PH.y : gc) + 2.2);
    if (!CAMD.init || Math.abs(ty - CAMD.y) > 25) { CAMD.x = tx; CAMD.y = ty; CAMD.z = tz; CAMD.init = true; } else { const kp = 1 - Math.exp(-8 * dt); CAMD.x += (tx - CAMD.x) * kp; CAMD.y += (ty - CAMD.y) * kp; CAMD.z += (tz - CAMD.z) * kp; }
    const ax = PH.x + CAMD.dx * 30, az = PH.z + CAMD.dz * 30, ga = groundY(ax, az); _look.set(ax, (ga === null ? PH.y : ga) + 1, az);
    camera.position.set(CAMD.x, CAMD.y, CAMD.z); camera.lookAt(_look); camera.rotateZ(-PH.steer * .12);
    if (SHUD.a > .002) { const tt = performance.now(); camera.position.y += Math.sin(tt * .09) * SHUD.a; camera.position.x += Math.sin(tt * .071 + 1.3) * SHUD.a * .6; } SHUD.a *= Math.exp(-dt * 13);
    { const gsp = sp / SPK, pun = PSY.camera ? PSY.camera.fov_punch : 0, fv = (TOUCHLOOK ? Math.min(72, Math.max(54, 56 + (gsp - 18) * .4)) + pun * .6 : Math.min(100, Math.max(66, 68 + (gsp - 18) * .7)) + pun) * (LABV.fovMul || 1); if (Math.abs(fv - camera.fov) > .05) { camera.fov = fv; camera.updateProjectionMatrix(); } }
    U.uBoard.value.set(PH.x, PH.z); sky.position.copy(camera.position); if (ring) { const e = ring.matrix.elements; e[12] = camera.position.x; e[13] = camera.position.y - 1.7 - 159.696 - 3; e[14] = camera.position.z; }
  } else if (PLAY && CAMD.mode !== 'old') { /* handled above */ } else { camera.position.set(st.x, st.y, st.z); }
  if (PLAY && CAMD.mode === 'old') { if (SHUD.a > .002) { const tt = performance.now(); camera.position.y += Math.sin(tt * .09) * SHUD.a; camera.position.x += Math.sin(tt * .071 + 1.3) * SHUD.a * .6; } SHUD.a *= Math.exp(-dt * 13); }
  if (!PLAY || CAMD.mode === 'old') { camera.rotation.set(-0.06 + pitch * 0.8, 0, 0, 'YXZ'); U.uBoard.value.set(st.x, st.z); sky.position.copy(camera.position); }
  const T3 = performance.now(); WEATHER.tick(dt, camera.position, Math.hypot(PH.vx, PH.vz) / SPK, renderer.domElement.height); caveTick(dt);
  const T4 = performance.now(); renderPost(); if (window.__snapWant) window.__snapDo(); const T5 = performance.now(); goalTick(now); beaconTick(now); govTick(now); { const T6 = performance.now(); { const A = window.__FT || (window.__FT = { n: 0, a: 0, p: 0, c: 0, w: 0, r: 0, g: 0, tot: 0 }); A.n++; A.a += T1 - T0; A.p += T2 - T1; A.c += T3 - T2; A.w += T4 - T3; A.r += T5 - T4; A.g += T6 - T5; A.tot += T6 - T0; } if (window.__dm && T6 - T0 > 250) window.__dm('SLOW FRAME ' + Math.round(T6 - T0) + 'ms: anim/mae/trail ' + Math.round(T1 - T0) + ' | physics ' + Math.round(T2 - T1) + ' | camera ' + Math.round(T3 - T2) + ' | weather/cave ' + Math.round(T4 - T3) + ' | renderPost ' + Math.round(T5 - T4) + ' | goal/beacon/gov ' + Math.round(T6 - T5) + ' | paused ' + st.paused); }
  frames++; acc += dt; if (acc > 0.5) { fps = frames / acc; frames = 0; acc = 0; hud.textContent = LVL + '  seed ' + lvl.seed + '  ' + lvl.theme + '\n' + nMesh + ' meshes, ' + nInst + ' instances, ' + Object.keys(lvl.meshes).length + ' unique meshes\nz ' + st.z.toFixed(0) + '  speed ' + (PLAY ? (Math.hypot(PH.vx, PH.vz) * 3.6).toFixed(0) + 'km/h  hits ' + PH.hits + '  score ' + Math.floor(PH.score) + (PH.shield ? '  SHIELD' : '') + (PH.boost_t > 0 ? '  BOOST' : '') : st.speed.toFixed(0)) + '  ' + fps.toFixed(0) + ' fps'; if (MINUP) MINUP(fps); }
}
const VB = document.createElement('div'); VB.textContent = 'NORMAL'; VB.style.cssText = 'position:fixed;right:10px;top:60px;min-width:44px;padding:0 10px;height:30px;line-height:30px;text-align:center;border:2px solid #fff9;border-radius:15px;color:#fff;font:700 11px ui-monospace,Consolas,monospace;background:#0006;z-index:9;cursor:pointer;user-select:none'; document.body.appendChild(VB); window.__vbtn = VB; VB.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); setVMode(VM.mode + 1); });
addEventListener('keydown', (e) => { if (e.key === 'v' || e.key === 'V') setVMode(VM.mode + 1); }); { const vq = Q.get('view'); if (vq === 'vector') setVMode(1); else if (vq === 'ascii') setVMode(2); }
// ---------------------------------------------------------------- CLEAN SCREEN: only fps and speed are shown while playing; the DEV button (top left) brings up every readout (stats, head scope, view modes). Tap the speed to switch km/h and mph.
{ const css = document.createElement('style'); css.textContent = 'body:not(.dev) #hud, body:not(.dev) #bar, body:not(.dev) .devonly { display: none !important; }'; document.head.appendChild(css);
  for (const e of [scope, txt, VB]) if (e) e.classList.add('devonly');
  let mph = false; try { mph = localStorage.getItem('gv_mph') === '1'; } catch (e) { }
  const MN = document.createElement('div'); MN.style.cssText = 'position:fixed;left:8px;top:8px;z-index:30;color:#fff;font:700 20px ui-monospace,Consolas,monospace;text-shadow:0 0 4px #000,0 0 2px #000;padding:4px 8px;pointer-events:auto;cursor:pointer;user-select:none;background:#0006;border-radius:8px'; document.body.appendChild(MN); window.__MN = MN;
  MN.onclick = () => { mph = !mph; try { localStorage.setItem('gv_mph', mph ? '1' : '0'); } catch (e) { } };
  const DB = document.createElement('div'); DB.textContent = 'DEV'; DB.style.cssText = 'position:fixed;left:8px;top:52px;z-index:30;color:#fff;font:700 12px ui-monospace,Consolas,monospace;padding:3px 8px;border:1px solid #fff6;border-radius:8px;background:#0006;cursor:pointer;user-select:none;opacity:.6'; document.body.appendChild(DB);
  DB.onclick = () => { const on = document.body.classList.toggle('dev'); DB.style.opacity = on ? '1' : '.6'; DB.style.background = on ? '#0a68' : '#0006'; try { localStorage.setItem('gv_dev', on ? '1' : '0'); } catch (e) { } };
  try { if (localStorage.getItem('gv_dev') === '1' || Q.has('dev')) DB.onclick(); } catch (e) { }
  MINUP = (f) => { const v = Math.hypot(PH.vx, PH.vz) / SPK * 3.6; MN.textContent = Math.round(f) + ' fps   ' + (PLAY ? (mph ? Math.round(v * .6214) + ' mph' : Math.round(v) + ' km/h') : ''); };
}
// ---------------------------------------------------------------- PATH EDGES: a neon ribbon along each side of the track, so the way and the landscape are told apart at a glance (?noedge turns it off)
if (PLAY && !Q.has('noedge')) {
  const N = 150, STEP = 2.2, RW = .9, EW = C.W_HALF - 4;
  const geo = new THREE.BufferGeometry(), nv = 2 * 2 * (N + 1), pos = new Float32Array(nv * 3), wz = new Float32Array(nv), side = new Float32Array(nv), idx = [];
  for (let r = 0; r < 2; r++) for (let i = 0; i < N; i++) { const b = r * 2 * (N + 1) + 2 * i; idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2); for (let k = 0; k < 4; k++) side[b + k] = r; }
  for (let r = 0; r < 2; r++) side[r * 2 * (N + 1) + 2 * N] = side[r * 2 * (N + 1) + 2 * N + 1] = r;
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('wz', new THREE.BufferAttribute(wz, 1)); geo.setAttribute('side', new THREE.BufferAttribute(side, 1)); geo.setIndex(idx);
  const mat = new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime, uBeat: { value: 0 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false,
    vertexShader: 'attribute float wz; attribute float side; varying float vZ; varying float vS; varying float vD; void main(){ vZ = wz; vS = side; vec4 w = modelMatrix * vec4(position, 1.); vD = distance(w.xyz, cameraPosition); gl_Position = projectionMatrix * viewMatrix * w; }',
    fragmentShader: 'uniform float uTime, uBeat; varying float vZ; varying float vS; varying float vD;\n' + GLSL_HSV + '\nvoid main(){ float dash = .55 + .45 * smoothstep(.35, .5, abs(fract(vZ * .09 - uTime * .6) - .5) * 2.); vec3 c = hsv(fract(.83 - vS * .33 + vZ * .002 + uTime * .03), .75, 1.) * (2.4 + 1.4 * uBeat) * dash; float a = 1. - smoothstep(190., 330., vD); gl_FragColor = vec4(c * a, 1.);\n' + TAIL + ' }' });
  const mesh = new THREE.Mesh(geo, mat); mesh.frustumCulled = false; mesh.renderOrder = 5; scene.add(mesh); const lastY = [0, 0];
  EDGE_UPD = () => {
    if (!PLAY) return; const z0 = Math.floor(PH.z / STEP) * STEP + 24; mat.uniforms.uBeat.value = BEATFX.pulse * BEATFX.k;
    for (let r = 0; r < 2; r++) { const ex = (r ? 1 : -1) * EW; for (let i = 0; i <= N; i++) { const z = z0 - i * STEP, o = (r * (N + 1) + i) * 2; let g = groundY(ex, z); if (g === null) g = lastY[r]; else lastY[r] = g; const y = g + .2;
      for (let k = 0; k < 2; k++) { const v = (o + k) * 3; pos[v] = ex + (k ? RW : -RW) * .5; pos[v + 1] = y; pos[v + 2] = z; wz[o + k] = z; } } }
    geo.attributes.position.needsUpdate = true; geo.attributes.wz.needsUpdate = true;
  };
}
const PB = document.createElement('div'); const PAUSE_SVG = '<svg viewBox="0 0 24 24" width="30" height="30" style="display:block"><rect x="5.5" y="3.5" width="4.6" height="17" rx="1.3" fill="#fff"/><rect x="13.9" y="3.5" width="4.6" height="17" rx="1.3" fill="#fff"/></svg>', PLAY_SVG = '<svg viewBox="0 0 24 24" width="30" height="30" style="display:block"><path d="M7.5 3.8 L20 12 L7.5 20.2 Z" fill="#fff" stroke="#fff" stroke-linejoin="round" stroke-width="1.6"/></svg>'; PB.innerHTML = PAUSE_SVG; PB.style.cssText = 'position:fixed;right:10px;top:8px;width:56px;height:56px;display:flex;align-items:center;justify-content:center;border:2px solid #fff9;border-radius:28px;color:#fff;background:#0006;z-index:9;cursor:pointer;user-select:none'; document.body.appendChild(PB);
const PV = document.createElement('div'); PV.style.cssText = 'position:fixed;inset:0;display:none;align-items:center;justify-content:center;flex-direction:column;background:transparent;z-index:25;color:#fff;font:700 40px ui-monospace,Consolas,monospace;cursor:pointer;text-align:center'; PV.innerHTML = '<div style="background:#000a;padding:6px 14px;border-radius:10px;font-size:20px">PAUSED <span style="font-size:13px;opacity:.8">P / Esc resume &nbsp; <b>right-click</b>: select what is under the pointer and copy its details &nbsp; (I inspect, Y copy)</span></div>'; const PI = document.createElement('pre'); PI.style.cssText = 'position:fixed;left:6px;bottom:6px;margin:0;max-width:96vw;background:#000c;color:#9fe;font:11px/1.35 ui-monospace,Consolas,monospace;padding:6px 8px;border-radius:6px;text-align:left;white-space:pre-wrap;pointer-events:auto;user-select:text;cursor:text'; PI.addEventListener('click', (e) => e.stopPropagation()); PV.appendChild(PI); document.body.appendChild(PV);          // paused: the picture stays undimmed, and a small caption records where you are, so a screenshot is a bug report
function pauseInfo() { try { const j = Math.max(0, Math.floor(-PH.z / 180)), R = (k) => { const r = lvl.rows && lvl.rows[String(k)]; return r ? (r.zone || '-') : '-'; }; return 'course ' + (Q.get('course') || 'long_s7') + '  biome ' + (typeof BNAME === 'string' ? BNAME : '') + '  run seed ' + window.__RUNSEED + '  row ' + j + '  zone ' + R(j) + ' > ' + R(j + 1) + ' > ' + R(j + 2) + '\n' + 'x ' + PH.x.toFixed(1) + '  z ' + PH.z.toFixed(0) + '  y ' + PH.y.toFixed(1) + '  speed ' + Math.hypot(PH.vx, PH.vz).toFixed(1) + '  grounded ' + PH.grounded + '\n' + 'cave ' + (CAVE.k || 0).toFixed(2) + '  exposure ' + renderer.toneMappingExposure.toFixed(2) + '  assist ' + ASSIST + ' aa ' + AK + '\n' + 'view ' + innerWidth + 'x' + innerHeight + '  pixel ratio ' + renderer.getPixelRatio().toFixed(2) + '  url ' + location.search; } catch (e) { return 'info unavailable: ' + e.message; } }
function setPause(v) { try { GM.setPaused(v); } catch (e) { } try { if (window.__bt) { if (v) window.__bt.pause(); else window.__bt.play().catch(() => { }); } } catch (e) { }  st.paused = v; PV.style.display = v ? 'flex' : 'none'; if (v) PI.textContent = pauseInfo(); PB.innerHTML = v ? PLAY_SVG : PAUSE_SVG; if (window.__HL) window.__HL.style.display = v ? '' : 'none'; if (v) SFX.grindOff(); else last = performance.now(); }
// INSPECT: while paused, press I with the pointer over anything that looks wrong; the caption names the mesh and shader there (so a screenshot says exactly what to fix)
let PTR = { x: 0, y: 0 }; addEventListener('pointermove', (e) => { PTR = { x: e.clientX, y: e.clientY }; });
const RAYC = new THREE.Raycaster(); function inspectAt(k = 0) {
  try { RAYC.setFromCamera(new THREE.Vector2(PTR.x / innerWidth * 2 - 1, -(PTR.y / innerHeight) * 2 + 1), camera); const hits = RAYC.intersectObjects(scene.children, true).filter((h) => h.object.isMesh && h.object.visible); if (!hits[k]) return k ? '' : 'inspect: nothing under the pointer (sky or background)';
    const h = hits[k], o = h.object, m = o.material, geo = o.geometry; geo.computeBoundingBox(); const b = geo.boundingBox, key = m.customProgramCacheKey ? String(m.customProgramCacheKey()).slice(0, 40) : '', frag = m.fragmentShader ? m.fragmentShader.slice(0, 90).replace(/\s+/g, ' ') : '';
    return 'inspect: ' + geo.attributes.position.count + ' verts' + (o.isInstancedMesh ? ' x' + o.count + ' instances' : '') + ', ' + m.type + (m.vertexColors ? ', vertex colours' : '') + ', size ' + [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z].map((v) => v.toFixed(0)).join('x') + ', distance ' + h.distance.toFixed(0) + ' m, at ' + h.point.x.toFixed(0) + ' ' + h.point.y.toFixed(0) + ' ' + h.point.z.toFixed(0) + (h.face ? ', slope ' + (1 - Math.abs(h.face.normal.y)).toFixed(2) : '') + (o.name ? ', name ' + o.name : '') + (key ? ', key ' + key : '') + (frag ? ', shader: ' + frag : ''); } catch (e) { return 'inspect failed: ' + e.message; } }
addEventListener('keydown', (e) => { if ((e.key === 'i' || e.key === 'I') && st.paused) PI.textContent = pauseInfo() + '\n' + inspectAt(); if ((e.key === 'y' || e.key === 'Y') && st.paused) { const t = PI.textContent; (navigator.clipboard ? navigator.clipboard.writeText(t) : Promise.reject()).then(() => { PI.style.outline = '2px solid #6f6'; setTimeout(() => { PI.style.outline = ''; }, 600); }).catch(() => { const r = document.createRange(); r.selectNodeContents(PI); const sl = getSelection(); sl.removeAllRanges(); sl.addRange(r); }); } });

function copyText(t) { const fb = () => { try { const ta = document.createElement('textarea'); ta.value = t; ta.style.cssText = 'position:fixed;left:-999px;top:0'; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); return true; } catch (e) { return false; } }; return (navigator.clipboard && window.isSecureContext ? navigator.clipboard.writeText(t).then(() => true, fb) : Promise.resolve(fb())); }
PV.addEventListener('contextmenu', (e) => {          // PAUSED: right-click selects what is under the pointer (and what is behind it) and copies everything to the clipboard, ready to paste
  e.preventDefault(); e.stopPropagation(); PTR = { x: e.clientX, y: e.clientY }; const parts = [pauseInfo(), inspectAt(0)]; const b1 = inspectAt(1), b2 = inspectAt(2); if (b1) parts.push('   behind it: ' + b1.replace('inspect: ', '')); if (b2) parts.push('   and behind that: ' + b2.replace('inspect: ', '')); parts.push('pointer at ' + Math.round(PTR.x) + ',' + Math.round(PTR.y) + ' of ' + innerWidth + 'x' + innerHeight);
  const t = parts.join(String.fromCharCode(10)); PI.textContent = t; copyText(t).then((ok) => { PI.style.outline = ok ? '3px solid #6f6' : '3px solid #f66'; PI.insertAdjacentText('afterbegin', ok ? 'COPIED TO THE CLIPBOARD - paste it into the chat' + String.fromCharCode(10) : 'COPY FAILED - select this text by hand' + String.fromCharCode(10)); setTimeout(() => { PI.style.outline = ''; }, 1500); });
});
PB.addEventListener('click', (e) => { e.stopPropagation(); setPause(!st.paused); }); PV.addEventListener('click', () => setPause(false));
addEventListener('keydown', (e) => { if (e.key === 'p' || e.key === 'P' || e.key === 'Escape') setPause(!st.paused); });
document.addEventListener('visibilitychange', () => { if (document.hidden && PLAY) setPause(true); });
try { window.__dm && window.__dm('shaders: compiling in the background'); const tc0 = performance.now(); const rt0 = renderer.getRenderTarget(); renderer.setRenderTarget(rtScene); await renderer.compileAsync(scene, camera);          /* the scene is drawn into the HDR target, which needs its own program variants: they were compiling on the first frames */
    for (const [m, tg] of [[feedM, rtA], [brightM, rtG4], [downM, rtG8], [postM, null]]) { qMesh.material = m; renderer.setRenderTarget(tg); await renderer.compileAsync(qScene, qCam); } renderer.setRenderTarget(rt0);
    { const touch = async (name, tg, fn) => { const t0 = performance.now(); renderer.setRenderTarget(tg); renderer.setScissorTest(true); renderer.setScissor(0, 0, 2, 2); try { fn(); _gl.finish(); } catch (e) { } renderer.setScissorTest(false); renderer.setRenderTarget(rt0); window.__dm && window.__dm('warm draw ' + name + ': ' + Math.round(performance.now() - t0) + ' ms'); await new Promise((r) => setTimeout(r, 30)); };          /* a 2x2 pixel draw per pass makes the driver build each pipeline now, one at a time, and the log says which ones are slow */
      await touch('scene', rtScene, () => renderer.render(scene, camera));

      for (const [nm, m, tg] of [['feed', feedM, rtA], ['bright', brightM, rtG4], ['down', downM, rtG8], ['post', postM, null]]) await touch(nm, tg, () => { qMesh.material = m; renderer.render(qScene, qCam); }); } window.__dm && window.__dm('shaders: compiled in ' + Math.round(performance.now() - tc0) + ' ms'); } catch (e) { window.__dm && window.__dm('shader warm-up failed: ' + e.message); }          // compiled behind the loader (in parallel where the browser allows), not all at once on the first frame
if (window.__dm) { try { const rs = performance.getEntriesByType('resource'); const slow = rs.slice().sort((x, y) => y.duration - x.duration).slice(0, 8).map((e) => e.name.split('/').slice(-2).join('/').slice(0, 40) + ' ' + Math.round(e.duration) + 'ms ' + Math.round((e.transferSize || 0) / 1024) + 'KB').join(' | '); const tot = rs.reduce((a2, e) => a2 + (e.transferSize || 0), 0); window.__dm('network: ' + rs.length + ' requests, ' + Math.round(tot / 1048576) + ' MB; slowest: ' + slow); window.__dm('memory: ' + (performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) + ' MB heap' : 'n/a') + '; meshes ' + nMesh + ', instances ' + nInst + ', queued ' + BQ.length + ', rows ' + Object.keys(ROWREC).length); } catch (e) { window.__dm('summary failed: ' + e.message); } }
LD.remove(); window.__dm && window.__dm('loader removed: game starting');
requestAnimationFrame(frame);
window.__gv = { RTG, BANK, bankAdd, bankSpend, cutTree, onPath, OGRID, groundY, CAVE, START, HD, MAE, LANE, trailX, PROFILE, TUNE, FX, toast, BEAC, PILLS, clock, U, DBG, rows: () => Object.keys(ROWREC).join(','), bq: () => BQ.length, LAB, PSY, GM, SB, frame, scene, camera, st, lvl, renderer, PH, setPause, BUFFS, PADS, RAILS, featX, K, post: { rt: rtScene, u: postM.uniforms, glow: GL, gov: GOV, glowQ: GLOWQ, bright: brightM.uniforms, setSamples, setDpr }, fog: U };


// TUNING PANEL (&tune): two compact tables, steering on the left and the head-coupled view on the right, so both fit a phone held sideways. Changes apply live and are saved on this device
// (localStorage 'gvtune'); each slider has its own reset arrow; Copy gives the address-bar settings; Reset all clears every change.
if (Q.get('tune') === 'all') {
  const L = 'Steering', R = '3D depth + density';
  const rows = [
    [L, 'splitmix', 'Head signal: 0 auto, 1 split', 0, 1, 1, 0, 'Auto = the mix of turn, tilt and sideways position the game learns from you. Split = turn for gentle corrections, lean for the far reaches (best on a PC).'],
    [L, 'smoothpath', 'Softness (glide)', 0, 1, .05, 1, 'Higher = a softer, gentler glide to where you point. Lower = snappier.'],
    [L, 'aimtau', 'Follow time (s)', .02, .4, .01, .1, 'How fast the aim follows your head. Lower = snappier.'],
    [L, 'pred', 'Prediction (ms)', 0, 250, 5, 130, 'Reacts ahead of the camera delay. Higher = quicker, can overshoot.'],
    [L, 'gain', 'Sensitivity', .3, 2.5, .05, .7, 'How far the board goes for a head move.'],
    [L, 'turnfull', 'Split: turn, half reach (deg)', 4, 30, .5, 10, 'Only with &mix=split. Lower = less head turn needed.'],
    [L, 'leanfull', 'Split: lean, far side (%)', 3, 20, .5, 8, 'Only with &mix=split. Lower = a smaller lean goes far.'],
    [R, 'hcp', 'View on (0 off, 1 on)', 0, 1, 1, Q.has('hcp') ? 1 : 0, 'The screen as a window: your head moves the view.'],
    [R, 'hcpk', 'Strength', 0, 24, .5, HCPK0, 'How much the view shifts as your head moves. 2-4 is subtle.'],
    [R, 'hcpz', 'Still distance (m)', 3, 40, 1, 10, 'The distance that stays still. Nearer things shift against you.'],
    [R, 'hcpy', 'Up/down strength', 0, 1.5, .05, .6, 'Vertical share of the effect.'],
    [R, 'hcpflip', 'Reverse left/right (0/1)', 0, 1, 1, 0, 'If the picture shifts the wrong way.'],
    [R, 'density', 'Density: bumpers, gates, slings', 0, 1, .05, .5, 'How many of the course toys stay in the content stretches. 0 = none, 1 = all.'],
    [R, 'hoops', 'Density: jump hoops + targets', 0, 1, .05, 1, 'The chance a jump gets its hoops, landing target and ring stream. 0 = none.'],
    [R, 'shaftmolk', 'Density: shaft molecules (1 in N)', 1, 20, 1, 4, 'Every Nth light shaft holds a molecule. Higher = rarer.'],
    [R, 'shaftsize', 'Light shaft size (reload)', .6, 2.5, .05, 1.35, 'How much bigger the light shafts are drawn. Takes effect when the page loads.'],
    [R, 'slalomrun', 'Density: pylon rows in a row (reload)', 0, 4, 1, 2, 'The longest run of pylon rows. 0 = no pylon rows. Takes effect when the page loads.'],
    [L, 'stab', 'Anti-waggle', 0, 2.5, .1, 1, 'Calms the wobble after a turn. Higher settles sooner.'],
    [L, 'shake', 'Shake', 0, 1.5, .1, 1, 'How much the camera shakes on hits, landings, grinds and boosts.'],
    [L, 'forgive', 'Glitch forgiveness (0/1)', 0, 1, 1, 1, 'A graze right after a tracking glitch slides off instead of crashing.'],
  ];
  const wrap = document.createElement('div'); wrap.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:30;pointer-events:none;font:11px/1.2 system-ui,sans-serif;color:#fff';
  const btn = document.createElement('button'); btn.textContent = 'TUNE'; btn.style.cssText = 'position:absolute;right:76px;top:14px;pointer-events:auto;padding:5px 12px;border-radius:14px;border:1px solid #fff6;background:#000a;color:#fff;font:600 12px system-ui;touch-action:manipulation';
  const mkPanel = (side, title) => { const d = document.createElement('div'); d.style.cssText = 'display:none;position:absolute;top:38px;' + side + ':6px;width:min(46vw,290px);padding:5px 8px 6px;background:#000c;border:1px solid #fff4;border-radius:10px;pointer-events:auto;max-height:calc(100vh - 46px);overflow:auto'; const h = document.createElement('div'); h.textContent = title; h.style.cssText = 'font:700 11px system-ui;letter-spacing:.06em;text-transform:uppercase;opacity:.8;margin-bottom:2px'; d.appendChild(h); wrap.appendChild(d); return d; };
  const pl = mkPanel('left', L), pr = mkPanel('right', R); wrap.appendChild(btn); document.body.appendChild(wrap);
  const save = () => { try { localStorage.setItem('gvtune', JSON.stringify(LIVE)); } catch (e) { } };
  const els = {};
  for (const [g, n, t, lo, hi, st, d, h] of rows) {
    const r = document.createElement('div'); r.style.cssText = 'margin:2px 0'; r.title = h;
    const top = document.createElement('div'); top.style.cssText = 'display:flex;align-items:center;gap:4px';
    const tt = document.createElement('span'); tt.textContent = t; tt.style.cssText = 'flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
    const v = document.createElement('span'); v.style.cssText = 'min-width:2.4em;text-align:right;opacity:.9';
    const rb = document.createElement('button'); rb.textContent = '\u21BA'; rb.title = 'Reset this one to the optimized default (' + d + ')'; rb.style.cssText = 'padding:0 6px;border-radius:6px;border:1px solid #fff5;background:#fff2;color:#fff;font:600 12px system-ui;touch-action:manipulation';
    const inp = document.createElement('input'); inp.type = 'range'; inp.min = lo; inp.max = hi; inp.step = st; inp.style.cssText = 'width:100%;height:16px;margin:0;touch-action:pan-y';
    const refresh = () => { const val = sp(n, d), ch = Math.abs(val - d) > 1e-9; inp.value = val; v.textContent = val; v.style.color = ch ? '#fc6' : ''; rb.style.opacity = ch ? 1 : .35; if (n === 'gain') HD.gain = val; };
    inp.addEventListener('input', () => { LIVE[n] = +inp.value; save(); refresh(); });
    rb.onclick = () => { delete LIVE[n]; if (Math.abs(sp(n, d) - d) > 1e-9) LIVE[n] = d; save(); refresh(); };          /* back to the default, even when the address bar or the lab set something else */
    top.appendChild(tt); top.appendChild(v); top.appendChild(rb); r.appendChild(top); r.appendChild(inp); (g === L ? pl : pr).appendChild(r); els[n] = { inp, v, d, refresh }; refresh();
  }
  const bar = document.createElement('div'); bar.style.cssText = 'display:flex;gap:6px;margin-top:5px';
  const mk = (txt, fn) => { const b = document.createElement('button'); b.textContent = txt; b.style.cssText = 'flex:1;padding:5px;border-radius:8px;border:1px solid #fff5;background:#fff2;color:#fff;font:600 11px system-ui;touch-action:manipulation'; b.onclick = fn; bar.appendChild(b); return b; };
  mk('Reset all', () => { for (const k of Object.keys(LIVE)) delete LIVE[k]; for (const n in els) { if (Math.abs(sp(n, els[n].d) - els[n].d) > 1e-9) LIVE[n] = els[n].d; } save(); for (const n in els) els[n].refresh(); });
  const cp = mk('Copy', () => { const txt = Object.entries(LIVE).map(([k, v]) => k + '=' + v).join('&'); try { navigator.clipboard.writeText('&' + txt); } catch (e) { } cp.textContent = 'Copied'; setTimeout(() => { cp.textContent = 'Copy'; }, 1200); });
  pr.appendChild(bar);
  btn.onclick = () => { const on = pl.style.display === 'none'; pl.style.display = pr.style.display = on ? 'block' : 'none'; };
}

// SIMPLE TUNING PANEL (&tune), built for a phone held in either direction: one round button at the edge of the screen (reachable with a thumb) opens a sheet of five settings. Every control is at least
// 44 px: the slider is tall, drags in any direction without scrolling the page, and has a big minus and plus beside it for exact steps, and a big reset arrow. Touching the sheet never reaches the game
// (no steering, no pause). In landscape the five settings sit in two columns so nothing needs scrolling. (&tune=all is the long developer list of every setting.)
// Underlying settings: Sensitivity = gain. Smoothness = smoothpath + aimtau. Anticipation = pred. Calm centre = dz + sticky + hyst (+ the window's still-smoothing). Window = hcp + hcpk.
if (Q.has('tune') && Q.get('tune') !== 'all') {
  const lerp2 = (a, b, t) => a + (b - a) * t;
  const SET = {          // key, label, min, max, step, default, help, what it sets
    gain: ['gain', 'Sensitivity', .3, 2.5, .05, .7, 'How far the board goes for a head move. Too high = it jumps to the edges.', (v) => ({ gain: v })],
    smooth: ['m_smooth', 'Smoothness', 0, 1, .05, 1, 'Higher = a softer glide (also slower). Lower = crisp, quick.', (v) => ({ smoothpath: v, aimtau: lerp2(.05, .14, v) })],
    ahead: ['pred', 'Prediction (ms)', 0, 250, 10, 130, 'Reacts ahead of the camera delay. Higher = quicker, can overshoot.', (v) => ({ pred: v })],
    calm: ['m_calm', 'Stabilize centre', 0, 1, .05, .4, 'Ignores tiny head movements near the middle (and steadies the window view).', (v) => ({ dz: .04 * v, sticky: .5 * v, hyst: .03 * v })],
    shake: ['shake', 'Shake', 0, 1.5, .1, 1, 'How much the camera shakes on hits, landings, grinds and boosts. 0 = none.', (v) => ({ shake: v })],
    stab: ['stab', 'Anti-waggle', 0, 2.5, .1, 1, 'Calms the wobble after a turn or a slalom. Higher = the board settles straight sooner (too high feels heavy). Lower = looser.', (v) => ({ stab: v })],
    win: ['m_win', '3D depth', 0, 1, .05, 0, 'The screen as a window: 0 off; higher = the picture shifts more as your head moves.', (v) => ({ hcp: v > 0 ? 1 : 0, hcpk: v * 6 })],
  };
  const css = (el, t) => { el.style.cssText = t; return el; };
  const wrap = css(document.createElement('div'), 'position:fixed;left:0;top:0;right:0;bottom:0;z-index:30;pointer-events:none;font:14px/1.2 system-ui,sans-serif;color:#fff;-webkit-tap-highlight-color:transparent');
  const stop = (el) => { for (const ev of ['pointerdown', 'pointerup', 'touchstart', 'touchmove', 'click', 'mousedown']) el.addEventListener(ev, (e) => e.stopPropagation()); return el; };
  // the health line sits under the fps readout, top left (read only, never in the way)
  const hl = css(document.createElement('div'), 'position:absolute;left:150px;top:8px;box-sizing:border-box;height:34px;padding:4px 8px;background:#0006;border-radius:8px;color:#cfe;font:11px/26px ui-monospace,Consolas,monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;pointer-events:none'); hl.textContent = '...'; window.__HL = hl; hl.style.display = st.paused ? '' : 'none';          /* the stats line shows only while paused */
  // the round button: 52 px, at the right edge, a little above the middle (a thumb in landscape reaches it)
  const btn = stop(css(document.createElement('button'), 'position:absolute;right:max(8px,env(safe-area-inset-right));top:40%;width:52px;height:52px;border-radius:26px;border:2px solid #fff8;background:#000c;color:#fff;font:700 22px system-ui;pointer-events:auto;touch-action:manipulation;padding:0')); btn.textContent = '\u2699'; btn.setAttribute('aria-label', 'Tune');
  const sheet = stop(css(document.createElement('div'), 'display:none;position:absolute;right:max(68px,calc(env(safe-area-inset-right) + 68px));top:max(6px,env(safe-area-inset-top));bottom:max(6px,env(safe-area-inset-bottom));width:min(70vw,420px);padding:8px;box-sizing:border-box;background:#000d;border:1px solid #fff5;border-radius:16px;pointer-events:auto;touch-action:none;overflow:hidden;flex-direction:column'));
  const grid = css(document.createElement('div'), 'flex:1;display:grid;grid-template-columns:1fr;gap:6px;align-content:start;min-height:0'); sheet.appendChild(grid);
  wrap.appendChild(hl); wrap.appendChild(sheet); wrap.appendChild(btn); document.body.appendChild(wrap);
  const NOTES = []; const layout = () => { const land = innerWidth > innerHeight * 1.15; for (const n of NOTES) n.style.display = land ? 'none' : 'block'; grid.style.gridTemplateColumns = land ? '1fr 1fr' : '1fr'; sheet.style.width = land ? 'min(76vw,640px)' : 'min(92vw,420px)'; if (!land) { sheet.style.right = '8px'; sheet.style.left = 'auto'; sheet.style.top = 'auto'; sheet.style.bottom = '8px'; sheet.style.height = 'auto'; } else { sheet.style.right = '68px'; sheet.style.top = '6px'; sheet.style.bottom = '6px'; sheet.style.height = 'auto'; } };
  addEventListener('resize', layout); layout();
  const save = () => { try { localStorage.setItem('gvtune', JSON.stringify(LIVE)); } catch (e) { } };
  const apply = (name, v) => { const k = SET[name][0]; LIVE[k] = v; Object.assign(LIVE, SET[name][7](v)); if (name === 'gain') HD.gain = v; save(); };
  const els = {};
  const bigBtn = (txt, label) => { const b = css(document.createElement('button'), 'width:48px;height:48px;flex:none;border-radius:12px;border:1px solid #fff6;background:#ffffff22;color:#fff;font:700 24px system-ui;padding:0;touch-action:manipulation'); b.textContent = txt; b.setAttribute('aria-label', label); return b; };
  for (const name of Object.keys(SET)) {
    const [k, t, lo, hi, st, d, h] = SET[name];
    const row = css(document.createElement('div'), 'padding:4px 6px 6px;border-radius:12px;background:#ffffff0d');
    const top = css(document.createElement('div'), 'display:flex;justify-content:space-between;align-items:baseline;margin-bottom:2px'); const tt = css(document.createElement('b'), 'font-size:15px'); tt.textContent = t; const v = css(document.createElement('span'), 'font:700 16px ui-monospace,Consolas,monospace');
    const ctl = css(document.createElement('div'), 'display:flex;align-items:center;gap:6px');
    const minus = bigBtn('\u2212', 'less'), plus = bigBtn('+', 'more'), rb = bigBtn('\u21BA', 'reset to default');
    const inp = css(document.createElement('input'), 'flex:1;min-width:0;height:48px;margin:0;touch-action:none;accent-color:#6df'); inp.type = 'range'; inp.min = lo; inp.max = hi; inp.step = st;
    const note = css(document.createElement('div'), 'opacity:.6;font-size:11px;margin-top:1px'); note.textContent = h; NOTES.push(note);
    const cur = () => (LIVE[k] !== undefined ? LIVE[k] : sp(k, d));
    const refresh = () => { const val = cur(), ch = Math.abs(val - d) > 1e-9; inp.value = val; v.textContent = String(Math.round(val * 100) / 100); v.style.color = ch ? '#fc6' : ''; rb.style.opacity = ch ? 1 : .35; };
    inp.addEventListener('input', () => { apply(name, +inp.value); refresh(); });
    const nudge = (dir) => { const val = Math.max(lo, Math.min(hi, Math.round((cur() + dir * st) / st) * st)); apply(name, val); refresh(); };
    minus.onclick = () => nudge(-1); plus.onclick = () => nudge(1); rb.onclick = () => { apply(name, d); refresh(); };
    top.appendChild(tt); top.appendChild(v); ctl.appendChild(minus); ctl.appendChild(inp); ctl.appendChild(plus); ctl.appendChild(rb); row.appendChild(top); row.appendChild(ctl); row.appendChild(note); grid.appendChild(row); els[name] = { refresh, d }; refresh();
  }
  const bar = css(document.createElement('div'), 'display:flex;gap:8px;margin-top:6px;flex:none');
  const mk = (txt, fn) => { const b = css(document.createElement('button'), 'flex:1;height:48px;border-radius:12px;border:1px solid #fff6;background:#ffffff22;color:#fff;font:700 15px system-ui;touch-action:manipulation'); b.textContent = txt; b.onclick = fn; bar.appendChild(b); return b; };
  const rsAll = () => { for (const k of Object.keys(LIVE)) delete LIVE[k]; for (const name of Object.keys(SET)) apply(name, SET[name][5]); for (const name in els) els[name].refresh(); };
  const sv = mk('Save', () => { save(); try { localStorage.setItem('gvtune_saved', JSON.stringify({ t: Date.now(), v: LIVE })); } catch (e) { } toast('SETTINGS SAVED ON THIS DEVICE', '#6df'); sv.textContent = 'Saved ✓'; setTimeout(() => { sv.textContent = 'Save'; }, 1500); });          /* every setting stays on this device and is applied each time the game opens */
  const sh = mk('Share', () => { const u = new URL(location.href); for (const k of ['resettune']) u.searchParams.delete(k); for (const [k, v] of Object.entries(LIVE)) u.searchParams.set(k, String(Math.round(v * 1000) / 1000)); const url = u.toString(); const done = () => { sh.textContent = 'Copied'; setTimeout(() => { sh.textContent = 'Share'; }, 1500); }; if (navigator.share) navigator.share({ title: 'Downhill settings', url }).catch(() => { }); else { try { navigator.clipboard.writeText(url).then(done, done); } catch (e) { done(); } } });          /* a link that opens the game with every setting applied: for another phone */
  { /* WORLD: switch the whole environment (sky, ground, trees, weather). It reloads the page with &theme=, keeping everything else in the link */ const sel = css(document.createElement('select'), 'width:100%;height:48px;margin-top:6px;border-radius:12px;border:1px solid #fff6;background:#ffffff22;color:#fff;font:700 15px system-ui;flex:none;padding:0 10px'); const BN = { psychedelic: 'Trip', alpine: 'Alps', candy: 'Candy Land', tunnel: 'Tunnel', desert: 'Desert', matrix: 'Matrix', synthwave: 'Synthwave' }; for (const w of Object.keys(BN)) { const o = document.createElement('option'); o.value = w; o.textContent = 'Biome: ' + BN[w]; o.style.color = '#000'; if (w === WORLD_THEME) o.selected = true; sel.appendChild(o); } sel.onchange = () => { const u = new URL(location.href); u.searchParams.set('theme', sel.value); location.href = u.toString(); }; sel.style.cssText = 'flex:2;min-width:0;height:44px;border-radius:12px;border:1px solid #fff6;background:#ffffff22;color:#fff;font:700 14px system-ui;padding:0 8px'; const lrow = css(document.createElement('div'), 'display:flex;gap:6px'); lrow.appendChild(sel); const LV = [0, .5, 1], LN = ['off', 'half', 'full']; for (const [key, nm] of [['psych', 'Psych'], ['vector', 'Vector'], ['ascii', 'ASCII']]) { const b = css(document.createElement('button'), 'flex:1;min-width:0;height:44px;border-radius:12px;border:1px solid #fff6;background:#ffffff22;color:#fff;font:700 13px system-ui;touch-action:manipulation;padding:0'); const show = () => { const v = sp(key, key === 'psych' ? THEME_PK : 0); b.textContent = nm + ': ' + LN[Math.max(0, LV.findIndex((x) => Math.abs(x - v) < .01))]; b.style.background = v > 0 ? '#3cf6' : '#ffffff22'; }; b.onclick = () => { const v = sp(key, key === 'psych' ? THEME_PK : 0); const i = Math.max(0, LV.findIndex((x) => Math.abs(x - v) < .01)); LIVE[key] = LV[(i + 1) % 3]; save(); show(); }; show(); lrow.appendChild(b); } grid.insertBefore(lrow, grid.firstChild); }
  mk('All params', () => { const u = new URL(location.href); u.searchParams.set('tune', 'all'); location.href = u.toString(); }); mk('Centre', () => { if (window.__recentreNow) window.__recentreNow(); }); mk('Reset', rsAll); mk('Close', () => { sheet.style.display = 'none'; btn.style.display = 'block'; });
  sheet.appendChild(bar);
  btn.onclick = () => { layout(); sheet.style.display = 'flex'; btn.style.display = 'none'; };          /* the round button hides while the sheet is open (Close brings it back), so nothing overlaps */
  // the health line: what is going on, in plain words, updated twice a second
  let lock = 0, mid = 0, jit = 0, last = 0;
  setInterval(() => { const s2 = window.__steer || 0, a = Math.abs(s2); lock += ((a > .95 ? 1 : 0) - lock) * .04; mid += ((a < .1 ? 1 : 0) - mid) * .04; jit += (Math.min(1, Math.abs(s2 - last) * 6) - jit) * .04; last = s2; }, 50);
  setInterval(() => {
    const trk = window.__trk, hz = trk && trk.fps ? trk.fps : 0, lat = trk && trk.lat && Number.isFinite(trk.lat.total) ? trk.lat.total : null, g = HD.gain;
    const tips = []; if (lock > .25) tips.push('at the edge ' + Math.round(lock * 100) + '% of the time: lower Sensitivity'); if (jit > .35 && mid > .3) tips.push('jittery near the middle: raise Smoothness or Calm centre'); if (hz && hz < 10) tips.push('the tracker is slow (' + hz.toFixed(0) + '/s): not a setting problem'); if (!HD.cal) tips.push('not calibrated: look straight ahead');
    /* ONE LINE, right of the fps / km/h readout, same dark background */ hl.textContent = (window.__DRS && window.__DRS.on ? 'draws ' + (window.__DRS.px / 1e6).toFixed(2) + 'M  ' : '') + 'tracker ' + (hz ? hz.toFixed(0) : '-') + '/s' + (lat !== null ? '  delay ~' + Math.round(lat + 40) + 'ms' : '') + '  sens ' + (+g).toFixed(2) + '  edge ' + Math.round(lock * 100) + '%  centre ' + Math.round(mid * 100) + '%  jitter ' + Math.round(jit * 100) + '%' + (tips.length ? '  ! ' + tips[0] : '');
    try { const mr = window.__MN; const L = mr ? mr.getBoundingClientRect().right + 8 : 150; hl.style.left = L + 'px'; hl.style.maxWidth = Math.max(60, innerWidth - L - 76) + 'px'; } catch (e) { }
  }, 500);
}

// SLALOM STRETCHES: walls of striped pylons across the open ground, each with an opening that swings from side to side, so the board swerves back and forth. The openings are marked
// with tall glowing beacons. Hitting a pylon is the gentle crash (speed x 0.3 and about a second of grace). Gates get a little tighter and swing a little wider with distance.
// &gate=N metres between gates (default 34).
{
  const SLN = { done: new Set() };
  const tex = (() => { const c = document.createElement('canvas'); c.width = 32; c.height = 128; const g = c.getContext('2d'); for (let i = 0; i < 8; i++) { g.fillStyle = i % 2 ? '#ffd23a' : '#26202e'; g.fillRect(0, i * 16, 32, 16); } const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; return t; })();
  const geoP = new THREE.CylinderGeometry(.75, .9, 4.4, 18, 3); geoP.translate(0, 2.2, 0); { const nn = geoP.attributes.normal, pp = geoP.attributes.position, cc = new Float32Array(nn.count * 3), sun = new THREE.Vector3(.4, .8, .3).normalize(); for (let i = 0; i < nn.count; i++) { const k = .62 + .62 * Math.max(0, nn.getX(i) * sun.x + nn.getY(i) * sun.y + nn.getZ(i) * sun.z) + .14 * (pp.getY(i) / 4.4); cc[i * 3] = cc[i * 3 + 1] = cc[i * 3 + 2] = k; } geoP.setAttribute('color', new THREE.BufferAttribute(cc, 3)); }
  const matP = new THREE.MeshBasicMaterial({ map: tex, vertexColors: true, color: new THREE.Color(1.35, 1.3, 1.25), fog: false });
  const geoB = new THREE.CylinderGeometry(.16, .24, 9, 8); geoB.translate(0, 4.5, 0); const capGeo = new THREE.OctahedronGeometry(.85), capMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(2.6, 1.5, .3), toneMapped: false, fog: false });
  const matB = matP;
  const addOb = (x, z, r, imx, idx, yy, sx, sy) => { const ob = { x, z, r, k: .7, label: 'PYLON!', im: imx, idx, y: yy, sx, sy }; const key = Math.floor(x / 8) + ',' + Math.floor(z / 8); (OGRID.get(key) || OGRID.set(key, []).get(key)).push(ob); return ob; };
  // PYLON BLAST: a pylon you hit flies out of the wall, forward and to the sides, tumbling, and drops. Without a shield only that pylon goes (you still take the gentle crash); with a shield the shield is
  // spent in a BLAST that throws every pylon within 9 m out of the way, and you lose nothing.
  const DEB = window.__DEB = [], ZM = new THREE.Matrix4().makeScale(0, 0, 0); DEB.t = 0;
  const flyPylon = (o, power) => { if (o.dead) return; o.dead = true; if (o.im) { o.im.setMatrixAt(o.idx, ZM); o.im.instanceMatrix.needsUpdate = true; } const mesh = new THREE.Mesh(geoP, matP); mesh.position.set(o.x, o.y || th(o.x, o.z), o.z); mesh.scale.set(o.sx || 1, o.sy || 1, o.sx || 1); mesh.frustumCulled = false; scene.add(mesh); const sp0 = Math.hypot(PH.vx, PH.vz), side = Math.sign(o.x - PH.x) || (Math.random() < .5 ? -1 : 1); DEB.push({ mesh, vx: side * (4 + Math.random() * 9 * power) + (Math.random() - .5) * 3, vy: 6 + Math.random() * 9 * power, vz: -(sp0 * .8 + 8 + Math.random() * 14 * power), rx: (Math.random() - .5) * 9, ry: (Math.random() - .5) * 5, rz: (Math.random() - .5) * 9, age: 0 }); };
  window.__pylonHit = (o) => { const shield = PH.shield > 0; if (shield) shudder(.7); flyPylon(o, shield ? 1.5 : 1); if (shield) { const cx = Math.floor(o.x / 8), cz = Math.floor(o.z / 8); for (let i = -2; i <= 2; i++) for (let j = -2; j <= 2; j++) { const a = OGRID.get((cx + i) + ',' + (cz + j)); if (!a) continue; for (const p2 of a) if (p2.im && !p2.dead && Math.hypot(p2.x - o.x, p2.z - o.z) < 9) flyPylon(p2, 1.5); } } try { FX.E.rockHit(o.x, th(o.x, o.z), o.z, shield ? 4 : 2); } catch (e) { } try { SFX.snap(); if (shield) SFX.blast && SFX.blast(); } catch (e) { } return shield ? 'PYLONS BLASTED!' : 'PYLON SMASHED!'; };
  const debStep = () => { const now = performance.now(), dt = Math.min(.05, (now - (DEB.t || now)) / 1000); DEB.t = now; for (let k = DEB.length - 1; k >= 0; k--) { const d = DEB[k]; d.age += dt; d.vy -= 22 * dt; const m = d.mesh; m.position.x += d.vx * dt; m.position.y += d.vy * dt; m.position.z += d.vz * dt; m.rotation.x += d.rx * dt; m.rotation.y += d.ry * dt; m.rotation.z += d.rz * dt; const gg = groundY(m.position.x, m.position.z); if (gg !== null && m.position.y < gg + .5) { m.position.y = gg + .5; d.vy = Math.abs(d.vy) * .3; d.vx *= .6; d.vz *= .6; } if (d.age > 2.4) { const s2 = Math.max(0, 1 - (d.age - 2.4) / .6); m.scale.multiplyScalar(.9); if (d.age > 3) { scene.remove(m); DEB.splice(k, 1); } } } };
  const build = (j, rr, z0) => {
    const gap = sp('gate', 52), gates = Math.max(1, Math.floor(150 / gap)), spans = []; for (const f of (rr.feats || [])) { if (f.kind !== 'jump' && f.kind !== 'rail') continue; const zs = [f.za, f.zb, f.zl, f.z].filter(Number.isFinite); if (zs.length) spans.push([Math.min(...zs), Math.max(...zs)]); } for (const t of (rr.toys || [])) if (t.kind === 'pill' && Number.isFinite(t.z)) spans.push([t.z - 6, t.z + 6]);
    const P = [], B = [];
    for (let k = 0; k < gates; k++) {
      const z = z0 - 30 - k * gap, g = j * 6 + k; if (spans.some((q) => z > q[0] - 14 && z < q[1] + 14)) continue;
      const pr = Math.min(1, -z / 5000), amp = sp('gateamp', 6) * (.85 + .35 * pr), hw = sp('gatew', 9.5) - 2.5 * pr, side = g % 2 ? 1 : -1, tx = trailX(z), oc = tx + side * amp, L = Math.min(25, C.W_HALF - 6);
      for (let x = tx - L; x <= tx + L; x += 2.6) { if (Math.abs(x - oc) < hw) continue; P.push([x, z]); }
      B.push([oc - hw, z], [oc + hw, z]);
    }
    window.__dm && window.__dm('slalom row ' + j + ': ' + P.length + ' pylons, ' + B.length / 2 + ' gates (of ' + gates + ')');
    if (!P.length) return;
    const im = new THREE.InstancedMesh(geoP, matP, P.length), m = new THREE.Matrix4(); P.forEach(([x, z], i) => { const y = groundY(x, z), yy = y === null ? th(x, z) : y, sy = .9 + ((i * 37) % 7) / 35; m.makeScale(1, sy, 1).setPosition(x, yy, z); im.setMatrixAt(i, m); addOb(x, z, .95, im, i, yy, 1, sy); });
    im.frustumCulled = false; scene.add(im);
    const ib = new THREE.InstancedMesh(geoB, matB, B.length), ic = new THREE.InstancedMesh(capGeo, capMat, B.length); B.forEach(([x, z], i) => { const y = groundY(x, z), yy = y === null ? th(x, z) : y; m.makeScale(1, 1, 1).setPosition(x, yy, z); ib.setMatrixAt(i, m); m.makeScale(1, 1.5, 1).setPosition(x, yy + 9.6, z); ic.setMatrixAt(i, m); addOb(x, z, .5); });
    ib.frustumCulled = false; scene.add(ib); ic.frustumCulled = false; scene.add(ic);
  };
  const KIT = createKit({ scene, th, groundY, trailX, PH, C, SPK, RAILS, toast, hooks: {}, PADS, BUFFS, nrows: lvl.nrows || 43, hooks: { hoopP: () => sp('hoops', 1), shake: (a) => shudder(a), onRing: (g) => { try { FX.E.orb([g.x, g.y, g.z]); } catch (e) { } try { SFX.orb(); SFX.pick(); } catch (e) { } }, cheer: (p, c, s) => { try { FX.E.cheer(p, c, s); } catch (e) { } shudder(.22 * (s || 1)); }, sfx: () => { try { SFX.pick(); SFX.snap(); } catch (e) { } }, chain: () => { try { chainHit(); } catch (e) { } } }, zoneOf: (j) => window.__zoneOf(j), seed: window.__RUNSEED, onTarget: (o, kind) => { if (kind === 'pad') mkBeacon(o, o.x, o.z, th(o.x, o.z), 'pad', 3, 38); else mkBeacon(o, o.x, o.z, o.y - 2.4, kind, 3.2, 48); } }); KIT.setVxRows((lvl.vx || []).map((k) => Math.floor(-k.z / 180))); window.__inv = () => { const cnt = (arr, f) => { const o = {}; for (const x of arr) { const k = f(x); o[k] = (o[k] || 0) + 1; } return o; }; const ob = []; for (const v of OGRID.values()) ob.push(...v); return { rows: ROWS.length, buffs: cnt(BUFFS, (x) => x.t + '/' + (x.kind || '')), pads: cnt(PADS, (x) => x.t || x.kind || '?'), feats: cnt(FEATS, (x) => x.kind), toys: cnt(ROWS.flatMap((r) => r.toys || []), (x) => x.kind), obstacles: cnt(ob, (x) => (x.label || (x.k < .5 ? 'tree' : 'rock')) + (x.im ? '(inst)' : '')), sLoot: JSON.stringify(FEATS.filter((x) => x.kind === 'loot').slice(0, 2)).slice(0, 500), sToy: JSON.stringify(FEATS.filter((x) => x.kind === 'toy').slice(0, 2)).slice(0, 500), sPad: JSON.stringify(PADS.slice(0, 2)).slice(0, 400), lkPads: JSON.stringify(PADS.filter((x) => x.lk).map((x) => [x.x | 0, x.z | 0, !!x.used, !!x.zoneHid, Object.keys(x.lk).join('+')])).slice(0, 900), kitRings: KIT.rings.length, kitRamps: KIT.ramps.length }; };
  window.__shafts = () => SHAFTS; // NO BLACK VOID: past the edge of the terrain and under the horizon the sky dome is dark, which shows as a black area around the mountains when you are high up (a jump). A huge flat disc of haze colour follows the
// camera, drawn before everything else, so anything not covered by the world is haze, not black. &nohaze turns it off, &hazek=0..1 sets how bright it is.
{ const fc = U.fogColor.value, hc = fc.clone().lerp(new THREE.Color(.5, .32, .75), Math.max(0, Math.min(1, sp('hazek', WORLD_THEME === 'psychedelic' ? .5 : .15)))); const HZ = new THREE.Mesh(new THREE.CircleGeometry(9000, 20), new THREE.MeshBasicMaterial({ color: hc, depthWrite: false, fog: false })); HZ.rotation.x = -Math.PI / 2; HZ.renderOrder = -9; HZ.frustumCulled = false; if (!Q.has('nohaze')) scene.add(HZ); window.__hazeStep = () => HZ.position.set(camera.position.x, camera.position.y - 260, camera.position.z); }
const BP = Q.get('props') === '0' ? null : createBiomeProps({ THREE, scene, groundY, trailX, PH, theme: WORLD_THEME, seed: window.__RUNSEED }); window.__bp = BP; window.__bpStep = () => { if (BP) BP.step(); }; window.__kitStep = (dt) => KIT.step(dt); window.__kitLaunch = () => KIT.launch();          /* custom ramps, rails and hoops in five cheap materials (kit.js) */
  const spansOf = (j, rr) => { const sp0 = []; for (const q of [lvl.rows[String(j - 1)], rr, lvl.rows[String(j + 1)]]) { if (!q) continue; for (const f of (q.feats || [])) { if (f.kind !== 'jump' && f.kind !== 'rail') continue; const zs = [f.za, f.zb, f.zl, f.z].filter(Number.isFinite); if (zs.length) sp0.push([Math.min(...zs) - 6, Math.max(...zs) + (f.kind === 'jump' ? 140 : 8)]); } for (const t of (q.toys || [])) if (t.kind === 'pill' && Number.isFinite(t.z)) sp0.push([t.z - 25, t.z + 25]); } return sp0; };
  const singles = (j, rr, z0) => {
    const spans = []; for (const q of [lvl.rows[String(j - 1)], rr, lvl.rows[String(j + 1)]]) { if (!q) continue; for (const f of (q.feats || [])) { if (f.kind !== 'jump' && f.kind !== 'rail') continue; const zs = [f.za, f.zb, f.zl, f.z].filter(Number.isFinite); if (zs.length) spans.push([Math.min(...zs) - 6, Math.max(...zs) + (f.kind === 'jump' ? 140 : 8)]); } for (const t of (q.toys || [])) if (t.kind === 'pill' && Number.isFinite(t.z)) spans.push([t.z - 25, t.z + 25]); }
    const P = [], lanes = [-9, 8, 0, 10, -8]; for (let k = 0; k < 3; k++) { const z = z0 - 35 - k * 55, x = trailX(z) + lanes[(j * 3 + k) % lanes.length]; if (spans.some((q) => z > q[0] && z < q[1])) continue; P.push([x, z]); }
    if (!P.length) return; const m = new THREE.Matrix4(), im = new THREE.InstancedMesh(geoP, matP, P.length), ib = new THREE.InstancedMesh(geoB, matB, P.length);
    P.forEach(([x, z], i) => { const y = groundY(x, z), yy = y === null ? th(x, z) : y; m.makeScale(1.3, 1.2, 1.3).setPosition(x, yy, z); im.setMatrixAt(i, m); m.makeScale(1, .55, 1).setPosition(x, yy, z); ib.setMatrixAt(i, m); addOb(x, z, 1.2, im, i, yy, 1.3, 1.2); });
    im.frustumCulled = false; ib.frustumCulled = false; scene.add(im); scene.add(ib);
  };
  window.__slalomTick = () => {
    debStep();
    { const j1 = Math.max(1, Math.floor(-PH.z / 180) - 1); for (let j = j1; j <= j1 + 5; j++) { const zn = window.__zoneOf(j), rr = lvl.rows[String(j)]; if (!rr || zn === 'slalom' || zn === 'off') continue; const z0 = -180 * j; if (groundY(trailX(z0 - 90), z0 - 90) === null) continue; try { const n0 = KIT.ramps.length, r0 = RAILS.length; KIT.buildRow(j, rr, z0, spansOf(j, rr)); for (const k of (lvl.vx || [])) { if (k.kb || !(k.z <= z0 && k.z > z0 - 180)) continue; k.kb = true; KIT.buildAfterRamp(k, spansOf(j, rr)); } if (KIT.ramps.length + RAILS.length !== n0 + r0) window.__dm && window.__dm('kit row ' + j + ': +' + (KIT.ramps.length - n0) + ' ramps, +' + (RAILS.length - r0) + ' rails, rings ' + KIT.rings.length); } catch (e) { window.__dm && window.__dm('kit build failed: ' + (e && e.message)); } } }
    if (!window.__railMats) { window.__railMats = true; const MT = [['steel', [.35, .95, 1]], ['steel', [.35, .95, 1]], ['glass', [.85, .95, 1]], ['wood', [1, .62, .25]], ['neon', [1, .3, .9]], ['rust', [1, .5, .2]]]; for (const f of RAILS) if (!f.mat) { f.mat = 'steel'; }          /* one material: chrome, one way of riding */ }
    if (!PLAY || sp('zones', 1) <= 0) return; const j0 = Math.max(0, Math.floor(-PH.z / 180) - 1);
    for (let j = j0; j <= j0 + 6; j++) { const rr = lvl.rows[String(j)]; if (rr && !window.__ZD.has(j)) window.__zoneRow(rr, j); }
    for (let j = j0; j <= j0 + 5; j++) {
      const zn = window.__zoneOf(j) === 'slalom' ? 'slalom' : (KIT.phraseOf(j) === 'warm' ? 'clear' : 'none'); if (SLN.done.has(j) || (zn !== 'slalom' && zn !== 'clear') || j < 1) continue; const rr = lvl.rows[String(j)]; if (!rr) continue;
      const z0 = -180 * j; if (groundY(trailX(z0 - 90), z0 - 90) === null) continue;          // the ground of that row is not there yet: try again next frame
      SLN.done.add(j); try { if (zn === 'slalom') build(j, rr, z0); else singles(j, rr, z0); } catch (e) { window.__dm && window.__dm('slalom build failed: ' + (e && e.message)); }
    }
  };
}

// GENTLER PICKUP PUNCH: a pickup or a pad used to kick the field of view by up to 9 degrees, shake and flash the picture for an instant, which felt like the view locking as you passed
// through it. Now scaled by &punch (default 0.3; 1 = the old kick, 0 = none).
{
  const K = () => Math.max(0, Math.min(1, sp('punch', .3)));
  for (const ev of ['onBuff', 'onPad']) { const f = PSY.events[ev]; if (typeof f === 'function') PSY.events[ev] = function () { const r = f.apply(PSY.events, arguments); try { const c = PSY.camera; if (c) { c.fov_punch *= K(); c.shake *= K(); c.flash *= K(); } } catch (e) { } return r; }; }
}


// SNAPSHOT (&tune): a round camera button under the gear. It saves the picture of the game (no buttons or text over it) as a PNG: on a phone it opens the share sheet (save to photos, send), elsewhere it downloads.
if (Q.has('tune') && Q.get('tune') !== 'all') {
  const cam = document.createElement('button'); cam.textContent = '📷'; cam.setAttribute('aria-label', 'Snapshot'); cam.style.cssText = 'position:fixed;right:max(8px,env(safe-area-inset-right));top:calc(40% + 64px);width:52px;height:52px;border-radius:26px;border:2px solid #fff8;background:#000c;color:#fff;font:22px system-ui;z-index:30;touch-action:manipulation;padding:0';
  for (const ev of ['pointerdown', 'pointerup', 'touchstart', 'click', 'mousedown']) cam.addEventListener(ev, (e) => e.stopPropagation());
  document.body.appendChild(cam);
  window.__snapDo = () => { window.__snapWant = false; try { canvas.toBlob((b) => { if (!b) return; const name = 'downhill-' + new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19) + '.png', file = new File([b], name, { type: 'image/png' }); if (navigator.canShare && navigator.canShare({ files: [file] })) navigator.share({ files: [file], title: 'Downhill' }).catch(() => { }); else { const a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 2000); } toast('SNAPSHOT SAVED', '#6df'); }, 'image/png'); } catch (e) { toast('SNAPSHOT FAILED', '#f88'); } };
  cam.onclick = () => { window.__snapWant = true; };
}

// SPEED LOG (&diag): every 2 s, the speed, what limits it and the boost state, so a slow start can be explained with numbers
setInterval(() => { try { if (!window.__dm || !PLAY) return; const sp0 = Math.hypot(PH.vx, PH.vz); window.__dm('speed ' + sp0.toFixed(1) + ' m/s z ' + PH.z.toFixed(0) + ' boost ' + PH.boost_t.toFixed(2) + ' vxa ' + PH.vxa.toFixed(2) + ' ramp ' + ramp().toFixed(2) + ' grade ' + PH.grade.toFixed(2) + ' hurt ' + PH.hurt.toFixed(1) + ' ready ' + PH.ready + ' perk ' + PSY.perks().speedK.toFixed(2) + ' VMAX ' + (C.TRAIL_VMAX * ramp()).toFixed(1) + ' SPD ' + (C.TRAIL_SPEED * ramp()).toFixed(1) + ' rot ' + (window.__rotRms || 0).toFixed(1) + (() => { const A = window.__FT; if (!A || !A.n) return ''; const f = (v) => (v / A.n).toFixed(1), o = ' | cpu ms per frame: anim ' + f(A.a) + ' physics ' + f(A.p) + ' camera ' + f(A.c) + ' weather ' + f(A.w) + ' renderPost ' + f(A.r) + ' other ' + f(A.g) + ' total ' + f(A.tot) + ' (' + A.n + ' frames, period ' + (2000 / A.n).toFixed(1) + ' ms)'; window.__FT = null; return o; })()); } catch (e) { } }, 2000);


// CENTRE NOW: re-measure the middle from where the head is this instant (the R key, or the Centre button in the settings sheet)
window.__recentreNow = () => { try { if (!HD.cur) return; const nv = [HD.cur[0] / HN3[0], HD.cur[1] / HN3[1], HD.cur[2] / HN3[2]]; HD.neu = hproj(nv); HD.nT = HD.cur[0]; HD.nL = HD.cur[2]; toast('CENTRED', '#6df'); } catch (e) { } };
addEventListener('keydown', (e) => { if ((e.key === 'r' || e.key === 'R') && !e.ctrlKey && !e.metaKey) window.__recentreNow(); });


// THE PHONE'S OWN MOVEMENT (gyro): how fast the phone itself is turning, in degrees a second. A phone that moves in the hand makes the face move in the camera picture although the head did not, so the
// re-centring waits while the phone is moving, and the 2-second RMS goes into the speed log (&diag) so the real size of the effect can be read before anything is compensated.
window.__rot = 0; window.__rotRms = 0; { let acc = 0, n = 0;
  addEventListener('devicemotion', (e) => { const r = e.rotationRate; if (!r) return; const m = Math.hypot(r.alpha || 0, r.beta || 0, r.gamma || 0); window.__rot += (m - window.__rot) * .2; acc += m * m; n++; });
  addEventListener('pointerdown', () => { try { if (typeof DeviceMotionEvent !== 'undefined' && DeviceMotionEvent.requestPermission) DeviceMotionEvent.requestPermission().catch(() => { }); } catch (e) { } }, { once: true });
  setInterval(() => { window.__rotRms = n ? Math.sqrt(acc / n) : 0; acc = 0; n = 0; }, 2000); }

// a round CENTRE button (under the camera button) so the middle can be reset with one tap on a phone
if (Q.has('tune') && Q.get('tune') !== 'all') {
  const ctr = document.createElement('button'); ctr.textContent = '⌖'; ctr.setAttribute('aria-label', 'Centre'); ctr.style.cssText = 'position:fixed;right:max(8px,env(safe-area-inset-right));top:calc(40% + 128px);width:52px;height:52px;border-radius:26px;border:2px solid #fff8;background:#000c;color:#fff;font:26px system-ui;z-index:30;touch-action:manipulation;padding:0';
  for (const ev of ['pointerdown', 'pointerup', 'touchstart', 'click', 'mousedown']) ctr.addEventListener(ev, (e) => e.stopPropagation());
  document.body.appendChild(ctr); ctr.onclick = () => window.__recentreNow && window.__recentreNow();
}

// HIDE (debug, &hide=skirt,quad,ground): switch off a kind of big mesh to find out which one is which on screen. skirt = the steep terrain walls, quad = the 4-vertex backdrop planes, ground = the heightfield.
if (Q.has('hide')) { const what = String(Q.get('hide')).split(','); setInterval(() => { scene.traverse((m) => { if (!m.isMesh || !m.material) return; const mt = m.material, u = mt.uniforms || {}; const nv = m.geometry && m.geometry.attributes && m.geometry.attributes.position ? m.geometry.attributes.position.count : 0;
  if (what.includes('skirt') && u.uSkirt && u.uSkirt.value > .5) m.visible = false; if (what.includes('quad') && nv === 4 && u.k) m.visible = false; if (what.includes('ground') && u.uSkirt && u.uSkirt.value < .5 && nv > 1000) m.visible = false; }); }, 1500); }
