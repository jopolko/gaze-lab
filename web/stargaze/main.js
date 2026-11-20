// STARGAZE: a flight you steer with your eyes. three.js world + flow; the eye tracking lives in tracker.js.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { Tracker } from './tracker.js';

const $ = (s) => document.querySelector(s);
const Q = new URLSearchParams(location.search);
const DEBUG = Q.has('debug');
if (DEBUG) document.body.classList.add('debug');
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const ease = (t) => t * t * (3 - 2 * t);
const damp = (dt, tau) => 1 - Math.exp(-dt / tau);
const now = () => performance.now() / 1000;

// ---------------------------------------------------------------------------------------------------------------------
// Worlds
const REALMS = [
  { name: 'Violet Deep', a: [0.42, 0.18, 1.0], b: [0.08, 0.55, 1.0], c: [1.0, 0.45, 0.85], root: 55.0, seed: 1.7 },
  { name: 'Ember Sea', a: [1.0, 0.32, 0.08], b: [0.9, 0.08, 0.35], c: [1.0, 0.82, 0.35], root: 49.0, seed: 5.3 },
  { name: 'Glacier', a: [0.15, 0.75, 1.0], b: [0.25, 0.35, 1.0], c: [0.8, 1.0, 1.0], root: 65.4, seed: 9.1 },
  { name: 'Verdant', a: [0.08, 1.0, 0.5], b: [0.0, 0.55, 0.75], c: [0.9, 1.0, 0.35], root: 58.3, seed: 13.9 },
  { name: 'Solar', a: [1.0, 0.7, 0.18], b: [1.0, 0.25, 0.5], c: [1.0, 1.0, 0.85], root: 61.7, seed: 21.4 },
];
const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];

// ---------------------------------------------------------------------------------------------------------------------
// Renderer
const canvas = $('#gl');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', alpha: false, stencil: false });
renderer.setClearColor(0x000000, 1);
let pixelRatio = Math.min(window.devicePixelRatio || 1, 1.75);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(70, 1, 0.1, 5000);
camera.rotation.order = 'YXZ';

const U = { // shared uniforms
  uTime: { value: 0 }, uCamZ: { value: 0 }, uCam: { value: new THREE.Vector3() }, uGaze: { value: new THREE.Vector2() }, uAspect: { value: 1 },
  uColA: { value: new THREE.Color() }, uColB: { value: new THREE.Color() }, uColC: { value: new THREE.Color() },
  uStreak: { value: 1 }, uGlow: { value: 1 }, uPR: { value: pixelRatio },
};
const NOISE = /* glsl */`
  float hash(vec3 p){ p = fract(p*0.3183099 + .1); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
  float noise(vec3 x){ vec3 i = floor(x), f = fract(x); f = f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)), f.x), mix(hash(i+vec3(0,1,0)), hash(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i+vec3(0,0,1)), hash(i+vec3(1,0,1)), f.x), mix(hash(i+vec3(0,1,1)), hash(i+vec3(1,1,1)), f.x), f.y), f.z); }
  float fbm(vec3 p){ float a = .5, s = 0.; for(int i=0;i<5;i++){ s += a*noise(p); p = p*2.03 + 11.7; a *= .5; } return s; }
`;
// how close a vertex is to where the player is looking, on screen (the world brightens under the gaze)
const GAZE_V = /* glsl */`
  uniform vec2 uGaze; uniform float uAspect;
  float gazeGlow(vec4 clip){ vec2 d = (clip.xy/max(clip.w, 1e-4) - uGaze) * vec2(uAspect, 1.0); return exp(-dot(d,d)*5.0) * step(0.0, clip.w); }
`;

// --- sky: a nebula baked once per world into a texture (cheap to draw every frame) -------------------------------------
const skyRT = new THREE.WebGLRenderTarget(1024, 512, { depthBuffer: false });
skyRT.texture.wrapS = THREE.RepeatWrapping;
const bakeScene = new THREE.Scene(), bakeCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const bakeMat = new THREE.ShaderMaterial({
  uniforms: { uColA: U.uColA, uColB: U.uColB, uColC: U.uColC, uSeed: { value: 0 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }`,
  fragmentShader: `precision highp float; varying vec2 vUv; uniform vec3 uColA, uColB, uColC; uniform float uSeed; ${NOISE}
    void main(){
      float phi = vUv.x*6.2831853, th = (1.0-vUv.y)*3.14159265;
      vec3 d = vec3(-cos(phi)*sin(th), cos(th), sin(phi)*sin(th));
      vec3 p = d*1.6 + uSeed;
      float n1 = fbm(p), n2 = fbm(p*2.1 + n1*1.8 + 3.0), n3 = fbm(p*4.5 - n2*1.2);
      float cloud = smoothstep(0.38, 0.85, n1*0.75 + n2*0.45);
      vec3 col = mix(uColA, uColB, smoothstep(0.3, 0.7, n2)) * cloud * 0.42;
      col += uColC * pow(n3, 3.0) * cloud * 0.55;
      float dust = smoothstep(0.42, 0.68, fbm(p*2.6 + 7.0));
      col *= 1.0 - dust*0.75;
      col += uColB*0.012 + uColA*0.01*n1;
      gl_FragColor = vec4(col, 1.0);
    }`,
});
bakeScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), bakeMat));
const sky = new THREE.Mesh(new THREE.SphereGeometry(3000, 40, 20), new THREE.ShaderMaterial({
  uniforms: { tSky: { value: skyRT.texture }, uGain: { value: 1 } }, side: THREE.BackSide, depthWrite: false, depthTest: false,
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }`,
  fragmentShader: `varying vec2 vUv; uniform sampler2D tSky; uniform float uGain; void main(){ gl_FragColor = vec4(texture2D(tSky, vUv).rgb * uGain, 1.); }`,
}));
sky.renderOrder = -10; sky.frustumCulled = false; scene.add(sky);

// --- stars -------------------------------------------------------------------------------------------------------------
{
  const N = 4200, pos = new Float32Array(N * 3), inf = new Float32Array(N * 2);
  for (let i = 0; i < N; i++) {
    const u = Math.random() * 2 - 1, a = Math.random() * 6.2832, r = Math.sqrt(1 - u * u);
    pos.set([r * Math.cos(a) * 2400, u * 2400, r * Math.sin(a) * 2400], i * 3);
    inf[i * 2] = Math.pow(Math.random(), 4) * 2.6 + 0.9; inf[i * 2 + 1] = Math.random() * 100;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('aInf', new THREE.BufferAttribute(inf, 2));
  var stars = new THREE.Points(g, new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime, uGaze: U.uGaze, uAspect: U.uAspect, uColC: U.uColC, uPR: U.uPR }, transparent: true, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending,
    vertexShader: `attribute vec2 aInf; uniform float uTime, uPR; varying float vA; ${GAZE_V}
      void main(){ vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = clip;
        float g = gazeGlow(clip); float tw = 0.7 + 0.3*sin(uTime*(1.0+fract(aInf.y)*3.0) + aInf.y);
        gl_PointSize = aInf.x * uPR * (1.0 + g*1.6); vA = tw * (0.55 + g*1.8) * min(aInf.x*0.5, 1.2); }`,
    fragmentShader: `varying float vA; uniform vec3 uColC; void main(){ vec2 p = gl_PointCoord - .5; float d = dot(p,p)*4.0; gl_FragColor = vec4(mix(vec3(1.), uColC, .35) * vA * exp(-d*5.0), 1.); }`,
  }));
  stars.frustumCulled = false; stars.renderOrder = -9; scene.add(stars);
}

// --- speed streaks: dust that wraps around the camera and stretches with speed ---------------------------------------------
const STREAK_L = 260;
{
  const N = 700, pos = new Float32Array(N * 6), end = new Float32Array(N * 2);
  for (let i = 0; i < N; i++) {
    const x = (Math.random() - .5) * 90, y = (Math.random() - .5) * 90, z = Math.random() * STREAK_L;
    pos.set([x, y, z, x, y, z], i * 6); end[i * 2] = 0; end[i * 2 + 1] = 1;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('aEnd', new THREE.BufferAttribute(end, 1));
  const m = new THREE.ShaderMaterial({
    uniforms: { uCam: U.uCam, uStreak: U.uStreak, uColC: U.uColC, uGaze: U.uGaze, uAspect: U.uAspect }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `attribute float aEnd; uniform vec3 uCam; uniform float uStreak; varying float vA; ${GAZE_V}
      void main(){ vec3 p = position;
        p.x = uCam.x + mod(p.x - uCam.x + 45.0, 90.0) - 45.0; p.y = uCam.y + mod(p.y - uCam.y + 45.0, 90.0) - 45.0;
        float dz = mod(uCam.z + 8.0 - p.z, ${STREAK_L.toFixed(1)});
        p.z = uCam.z + 8.0 - dz - aEnd*uStreak;
        vec4 clip = projectionMatrix * viewMatrix * vec4(p, 1.); gl_Position = clip;
        float near = length(p.xy - uCam.xy);
        vA = (1.0 - aEnd*0.85) * smoothstep(${STREAK_L.toFixed(1)}, 120.0, dz) * smoothstep(1.5, 7.0, near) * (0.35 + gazeGlow(clip)*0.9); }`,
    fragmentShader: `varying float vA; uniform vec3 uColC; void main(){ gl_FragColor = vec4(mix(vec3(1.), uColC, .5) * vA, 1.); }`,
  });
  const streaks = new THREE.LineSegments(g, m); streaks.frustumCulled = false; scene.add(streaks);
}

// --- crystals: the canyon you fly through; they light up under your gaze -------------------------------------------------
const CRY_L = 620;
{
  const N = 240, base = new THREE.OctahedronGeometry(1, 0);
  const g = new THREE.InstancedBufferGeometry(); g.setAttribute('position', base.getAttribute('position')); g.instanceCount = N;
  const aBase = new Float32Array(N * 3), aScale = new Float32Array(N * 3), aRot = new Float32Array(N * 4);
  for (let i = 0; i < N; i++) {
    const s = 0.8 + Math.pow(Math.random(), 2.4) * 5.5, long = s * (1.3 + Math.random() * 1.6);
    const a = Math.random() * 6.2832, r = 19 + long + Math.pow(Math.random(), 1.5) * 70; // never reaches into the flight lane
    aBase.set([Math.cos(a) * r, Math.sin(a) * r * 0.9, Math.random() * CRY_L], i * 3);
    aScale.set([s * (0.5 + Math.random() * 0.5), long, s * (0.5 + Math.random() * 0.5)], i * 3);
    const ax = new THREE.Vector3(Math.random() - .5, Math.random() - .5, Math.random() - .5).normalize();
    aRot.set([ax.x, ax.y, ax.z, Math.random() * 100], i * 4);
  }
  g.setAttribute('aBase', new THREE.InstancedBufferAttribute(aBase, 3)); g.setAttribute('aScale', new THREE.InstancedBufferAttribute(aScale, 3)); g.setAttribute('aRot', new THREE.InstancedBufferAttribute(aRot, 4));
  const m = new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime, uCam: U.uCam, uGaze: U.uGaze, uAspect: U.uAspect, uColA: U.uColA, uColB: U.uColB, uColC: U.uColC, uGlow: U.uGlow },
    vertexShader: `attribute vec3 aBase, aScale; attribute vec4 aRot; uniform float uTime; uniform vec3 uCam; varying vec3 vView; varying float vG, vSeed, vFade; ${GAZE_V}
      vec3 rot(vec3 v, vec3 k, float a){ float c = cos(a), s = sin(a); return v*c + cross(k, v)*s + k*dot(k, v)*(1.0-c); }
      void main(){
        float dz = mod(uCam.z + 60.0 - aBase.z, ${CRY_L.toFixed(1)});
        vFade = smoothstep(${CRY_L.toFixed(1)}, ${(CRY_L - 160).toFixed(1)}, dz);
        vec3 c = vec3(aBase.xy, uCam.z + 60.0 - dz);
        vec3 p = rot(position * aScale * vFade, aRot.xyz, aRot.w + uTime*0.12*(fract(aRot.w)-.3)) + c;
        vec4 mv = viewMatrix * vec4(p, 1.); vView = mv.xyz; gl_Position = projectionMatrix * mv;
        vG = gazeGlow(projectionMatrix * viewMatrix * vec4(c, 1.)); vSeed = fract(aRot.w*7.31); }`,
    fragmentShader: `varying vec3 vView; varying float vG, vSeed, vFade; uniform vec3 uColA, uColB, uColC; uniform float uGlow;
      void main(){ vec3 n = normalize(cross(dFdx(vView), dFdy(vView))); vec3 v = normalize(-vView);
        float fres = pow(1.0 - abs(dot(n, v)), 2.2); float facet = max(dot(n, normalize(vec3(.35,.8,.5))), 0.);
        vec3 tint = mix(uColA, uColB, vSeed);
        vec3 col = tint * (0.025 + facet*0.16 + fres*0.9) + uColC * vG * (0.35 + fres*2.2 + facet*0.6) * uGlow;
        float fog = exp(-length(vView)*0.0026); gl_FragColor = vec4(col * fog * vFade, 1.); }`,
  });
  const crystals = new THREE.Mesh(g, m); crystals.frustumCulled = false; scene.add(crystals);
}

// --- the Eye: mirrors the player's eye; the far end of every world -----------------------------------------------------------
const eyeU = { uTime: U.uTime, uColA: U.uColA, uColB: U.uColB, uColC: U.uColC, uLook: { value: new THREE.Vector2() }, uLid: { value: 1 }, uDil: { value: 0 }, uPower: { value: 0 }, uFade: { value: 0 } };
const eyeMesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.ShaderMaterial({
  uniforms: eyeU, transparent: true, depthWrite: false, depthTest: false,
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }`,
  fragmentShader: `precision highp float; varying vec2 vUv; uniform float uTime, uLid, uDil, uPower, uFade; uniform vec2 uLook; uniform vec3 uColA, uColB, uColC; ${NOISE}
    void main(){
      vec2 p = (vUv - .5) * 2.0;
      float open = 1.0 - uLid;
      float almond = open * 0.6 * pow(max(1.0 - p.x*p.x*1.05, 0.0), 0.62);
      float edge = almond - abs(p.y);
      float inside = smoothstep(0.0, 0.025, edge);
      vec2 q = p - uLook * 0.2; float r = length(q) / 0.47; float a = atan(q.y, q.x);
      vec2 ca = vec2(cos(a), sin(a));
      float pupilR = 0.33 + uDil*0.13 + 0.012*sin(uTime*1.7);
      float fib = noise(vec3(ca*13.0, r*1.6 - uTime*0.05)); float fib2 = noise(vec3(ca*34.0, r*2.5 + 4.0)); float cl = fbm(vec3(ca*2.2, r*2.4 - uTime*0.08));
      float t = clamp((r - pupilR) / (1.0 - pupilR), 0., 1.);
      vec3 iris = mix(uColC, uColA, smoothstep(0.0, 0.45, t)); iris = mix(iris, uColB, smoothstep(0.4, 1.0, t));
      iris *= 0.35 + fib*0.9 + pow(fib2, 3.0)*1.8 + cl*0.5;
      iris += uColC * exp(-t*9.0) * (0.9 + uPower*2.5);
      iris *= smoothstep(1.0, 0.9, r) * (0.75 + 0.25*smoothstep(1.0, 0.78, r));
      float pupil = smoothstep(pupilR - 0.02, pupilR + 0.02, r);
      vec3 col = iris * pupil * (1.0 + uPower*0.8);
      col += uColC * uPower * exp(-r*r*14.0) * 1.4 * (1.0 - pupil);
      col += mix(uColB, uColA, .5) * 0.035 * smoothstep(0.9, 1.6, r) * (0.6 + cl);
      col *= inside;
      float rim = exp(-abs(edge)*26.0) * (0.35 + 0.65*open);
      col += mix(uColC, vec3(1.), .3) * rim * (0.8 + uPower);
      float aura = exp(-max(-edge, 0.0)*5.0) * 0.14 * (1.0 + uPower*2.0);
      col += uColA * aura * (1.0 - inside);
      float alpha = clamp(inside + rim + aura, 0., 1.) * smoothstep(1.0, 0.8, length(p));
      gl_FragColor = vec4(col * uFade, alpha * uFade);
    }`,
}));
eyeMesh.frustumCulled = false; eyeMesh.renderOrder = -8; scene.add(eyeMesh);
const EYE_SIZE = 360;

// --- embers: the lights you gather by looking --------------------------------------------------------------------------------
const MAXE = 96;
const emberGeo = new THREE.InstancedBufferGeometry();
{
  const pg = new THREE.PlaneGeometry(1, 1);
  emberGeo.setAttribute('position', pg.getAttribute('position')); emberGeo.setAttribute('uv', pg.getAttribute('uv')); emberGeo.setIndex(pg.getIndex());
}
const ePos = new THREE.InstancedBufferAttribute(new Float32Array(MAXE * 3), 3), eInf = new THREE.InstancedBufferAttribute(new Float32Array(MAXE * 4), 4);
ePos.setUsage(THREE.DynamicDrawUsage); eInf.setUsage(THREE.DynamicDrawUsage);
emberGeo.setAttribute('aPos', ePos); emberGeo.setAttribute('aInf', eInf); emberGeo.instanceCount = 0;
const emberMesh = new THREE.Mesh(emberGeo, new THREE.ShaderMaterial({
  uniforms: { uTime: U.uTime, uColC: U.uColC, uColA: U.uColA }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  vertexShader: `attribute vec3 aPos; attribute vec4 aInf; varying vec2 vUv; varying vec4 vInf;
    void main(){ vUv = uv; vInf = aInf; vec4 mv = viewMatrix * vec4(aPos, 1.); mv.xy += position.xy * aInf.x; gl_Position = projectionMatrix * mv; }`,
  fragmentShader: `varying vec2 vUv; varying vec4 vInf; uniform float uTime; uniform vec3 uColC, uColA;
    void main(){ vec2 p = (vUv - .5)*2.0; float r = length(p); float a = atan(p.y, p.x);
      vec3 tint = mix(uColC, vec3(1.0, 0.85, 0.35), vInf.z);
      float core = exp(-r*r*60.0)*2.6; float halo = exp(-r*4.6)*0.36;
      float rays = pow(abs(cos(a*2.0 + uTime*1.3 + vInf.w)), 24.0) * exp(-r*3.2) * 0.9;
      float ch = vInf.y; float rr = mix(0.92, 0.2, ch);
      float ring = exp(-pow((r - rr)*16.0, 2.0)) * smoothstep(0.02, 0.15, ch) * 1.6;
      vec3 col = tint*(halo + rays) + mix(tint, vec3(1.), .7)*core + mix(uColA, vec3(1.), .5 + ch*.5)*ring;
      gl_FragColor = vec4(col * smoothstep(1.0, 0.8, r), 1.); }`,
}));
emberMesh.frustumCulled = false; emberMesh.renderOrder = 5; scene.add(emberMesh);

// --- rings -------------------------------------------------------------------------------------------------------------------
const RING_R = 3.6, ringGeo = new THREE.TorusGeometry(RING_R, 0.07, 6, 72), ringPool = [];
for (let i = 0; i < 5; i++) {
  const m = new THREE.Mesh(ringGeo, new THREE.ShaderMaterial({
    uniforms: { uTime: U.uTime, uColC: U.uColC, uColA: U.uColA, uFade: { value: 0 }, uGaze: U.uGaze, uAspect: U.uAspect }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `varying vec2 vUv; varying float vG; ${GAZE_V} void main(){ vUv = uv; vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = clip; vG = gazeGlow(projectionMatrix * modelViewMatrix * vec4(0., 0., 0., 1.)); }`,
    fragmentShader: `varying vec2 vUv; varying float vG; uniform float uTime, uFade; uniform vec3 uColC, uColA;
      void main(){ float flow = 0.55 + 0.45*sin(vUv.x*75.4 - uTime*5.0); gl_FragColor = vec4(mix(uColA, uColC, flow) * (1.2 + flow*1.6 + vG*2.5) * uFade, 1.); }`,
  }));
  m.visible = false; m.frustumCulled = false; scene.add(m); ringPool.push({ mesh: m, on: false, z: 0, x: 0, y: 0, hit: 0 });
}

// --- post: bloom, then one pass for everything else (gaze wisp, blink ripple, warp, vignette, tone map) -----------------------
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.72, 0.55, 0.5);
composer.addPass(bloom);
const fin = new ShaderPass({
  uniforms: { tDiffuse: { value: null }, uGaze: { value: new THREE.Vector2() }, uAspect: { value: 1 }, uTime: { value: 0 }, uFlash: { value: 0 }, uWarp: { value: 0 }, uPulseAge: { value: 9 }, uPulseO: { value: new THREE.Vector2(.5, .5) }, uWisp: { value: 0 }, uWispCol: { value: new THREE.Color(1, 1, 1) }, uDim: { value: 0 }, uCharge: { value: 0 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }`,
  fragmentShader: `varying vec2 vUv; uniform sampler2D tDiffuse; uniform vec2 uGaze, uPulseO; uniform float uAspect, uTime, uFlash, uWarp, uPulseAge, uWisp, uDim, uCharge; uniform vec3 uWispCol;
    vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), 0., 1.); }
    void main(){
      vec2 uv = vUv, asp = vec2(uAspect, 1.0);
      vec2 pd = (uv - uPulseO) * asp; float pl = length(pd) + 1e-5; float pr = uPulseAge * 1.5;
      float wave = exp(-pow((pl - pr)*8.0, 2.0)) * max(0.0, 1.0 - uPulseAge*0.9);
      uv += (pd/pl)/asp * wave * 0.04;
      vec2 c = uv - .5; float ca = 0.0012 + uWarp*0.014; vec2 dir = c * ca * (1.0 + dot(c,c)*5.0);
      uv -= c * uWarp * 0.06 * dot(c,c);
      vec3 col = vec3(texture2D(tDiffuse, uv + dir).r, texture2D(tDiffuse, uv).g, texture2D(tDiffuse, uv - dir).b);
      vec2 g = uGaze*.5 + .5; vec2 gd = (vUv - g) * asp; float gl = length(gd);
      float ang = atan(gd.y, gd.x);
      float arc = smoothstep(0.0, 0.02, uCharge) * step(mod(ang/6.2831853 + 0.25, 1.0), uCharge);
      col += uWispCol * uWisp * (exp(-gl*gl*2600.0)*0.9 + exp(-pow((gl - 0.052)*90.0, 2.0))*(0.16 + arc*0.9) + exp(-gl*gl*26.0)*0.045);
      col += mix(uWispCol, vec3(1.), .5) * wave * 0.5;
      vec2 vc = (vUv - .5 - uGaze*0.07) * vec2(min(uAspect*1.25, 1.0), min(1.25/uAspect, 1.0)*0.8 + 0.2);
      col *= mix(0.32, 1.0, smoothstep(0.85, 0.22, length(vc)));
      col *= 1.0 - uDim*0.75;
      col = aces(col * 1.15); col = pow(col, vec3(1.0/2.2));
      col = mix(col, vec3(1.0, 0.98, 0.95), uFlash);
      col += (fract(sin(dot(vUv*vec2(1920., 1080.) + uTime, vec2(12.9898, 78.233))) * 43758.5453) - .5) * 0.018;
      gl_FragColor = vec4(col, 1.);
    }`,
});
composer.addPass(fin);

let W = 1, H = 1, aspect = 1, portrait = true;
function resize() {
  W = window.innerWidth; H = window.innerHeight; aspect = W / H; portrait = aspect < 1;
  renderer.setPixelRatio(pixelRatio); renderer.setSize(W, H, false);
  composer.setPixelRatio(pixelRatio); composer.setSize(W, H);
  camera.aspect = aspect; camera.fov = portrait ? 74 : 58; camera.updateProjectionMatrix();
  U.uAspect.value = aspect; fin.uniforms.uAspect.value = aspect; U.uPR.value = pixelRatio;
}
window.addEventListener('resize', resize); window.addEventListener('orientationchange', () => setTimeout(resize, 250));
resize();

// ---------------------------------------------------------------------------------------------------------------------
// Sound: a drone that shifts with each world, chimes that climb with your streak
const audio = {
  ctx: null, muted: false,
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return;
    const c = this.ctx = new AC();
    this.master = c.createGain(); this.master.gain.value = 0.9;
    const comp = c.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 5;
    this.master.connect(comp).connect(c.destination);
    // small feedback-delay reverb
    this.rev = c.createGain(); this.rev.gain.value = 1;
    const out = c.createGain(); out.gain.value = 0.5; out.connect(this.master);
    [[0.137, 0.52], [0.223, 0.48], [0.349, 0.44]].forEach(([t, fb]) => {
      const d = c.createDelay(1); d.delayTime.value = t; const g = c.createGain(); g.gain.value = fb; const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3200;
      this.rev.connect(d); d.connect(lp).connect(g).connect(d); lp.connect(out);
    });
    // drone
    this.droneGain = c.createGain(); this.droneGain.gain.value = 0;
    this.droneLP = c.createBiquadFilter(); this.droneLP.type = 'lowpass'; this.droneLP.frequency.value = 320; this.droneLP.Q.value = 2;
    this.droneLP.connect(this.droneGain); this.droneGain.connect(this.master); this.droneGain.connect(this.rev);
    this.osc = [[1, 'sawtooth', -7], [1, 'sawtooth', 8], [2, 'triangle', 3], [1.5, 'sine', 0], [0.5, 'sine', 0]].map(([mul, type, det]) => {
      const o = c.createOscillator(); o.type = type; o.detune.value = det; o.frequency.value = 55 * mul; const g = c.createGain(); g.gain.value = type === 'sawtooth' ? 0.12 : 0.2;
      o.connect(g).connect(this.droneLP); o.start(); return { o, mul };
    });
    const lfo = c.createOscillator(); lfo.frequency.value = 0.07; const lg = c.createGain(); lg.gain.value = 140; lfo.connect(lg).connect(this.droneLP.frequency); lfo.start();
    // riser (noise) for closing your eyes
    const buf = c.createBuffer(1, c.sampleRate * 2, c.sampleRate), ch = buf.getChannelData(0); for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
    this.noiseBuf = buf;
    const ns = c.createBufferSource(); ns.buffer = buf; ns.loop = true; this.riseBP = c.createBiquadFilter(); this.riseBP.type = 'bandpass'; this.riseBP.Q.value = 3; this.riseBP.frequency.value = 300;
    this.riseGain = c.createGain(); this.riseGain.gain.value = 0; ns.connect(this.riseBP).connect(this.riseGain); this.riseGain.connect(this.master); this.riseGain.connect(this.rev); ns.start();
    this.root = 55;
  },
  resume() { this.ctx?.resume(); },
  setMuted(m) { this.muted = m; if (this.ctx) this.master.gain.setTargetAtTime(m ? 0 : 0.9, this.ctx.currentTime, 0.05); },
  drone(level) { if (this.ctx) this.droneGain.gain.setTargetAtTime(level, this.ctx.currentTime, 1.2); },
  setRoot(hz) { this.root = hz; if (!this.ctx) return; const t = this.ctx.currentTime; this.osc.forEach(({ o, mul }) => o.frequency.setTargetAtTime(hz * mul, t, 0.6)); },
  tone(freq, dur, vol, type = 'sine', when = 0) {
    if (!this.ctx) return; const c = this.ctx, t = c.currentTime + when;
    const o = c.createOscillator(); o.type = type; o.frequency.value = freq; const g = c.createGain();
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    o.connect(g); g.connect(this.master); g.connect(this.rev); o.start(t); o.stop(t + dur + 0.05);
  },
  chime(step, gold) { // pentatonic ladder above the drone's root
    const scale = [0, 2, 4, 7, 9]; const n = scale[step % 5] + 12 * Math.floor(step / 5);
    const f = this.root * 4 * Math.pow(2, n / 12);
    this.tone(f, 0.9, 0.16, 'sine'); this.tone(f * 2.001, 0.5, 0.05, 'triangle'); if (gold) { this.tone(f * 1.5, 1.2, 0.1, 'sine', 0.06); this.tone(f * 2, 1.4, 0.08, 'sine', 0.12); }
  },
  chord() { [0, 7, 12, 16, 19].forEach((n, i) => this.tone(this.root * 4 * Math.pow(2, n / 12), 1.8, 0.1, 'triangle', i * 0.045)); },
  pulse() {
    if (!this.ctx) return; const c = this.ctx, t = c.currentTime;
    const o = c.createOscillator(), g = c.createGain(); o.frequency.setValueAtTime(190, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.3);
    g.gain.setValueAtTime(0.5, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.4); o.connect(g); g.connect(this.master); g.connect(this.rev); o.start(t); o.stop(t + 0.45);
  },
  rise(x) { if (!this.ctx) return; const t = this.ctx.currentTime; this.riseGain.gain.setTargetAtTime(x * 0.35, t, 0.06); this.riseBP.frequency.setTargetAtTime(250 + x * x * 3800, t, 0.06); },
  boom() {
    if (!this.ctx) return; const c = this.ctx, t = c.currentTime;
    const o = c.createOscillator(), g = c.createGain(); o.frequency.setValueAtTime(110, t); o.frequency.exponentialRampToValueAtTime(28, t + 1.4);
    g.gain.setValueAtTime(0.8, t); g.gain.exponentialRampToValueAtTime(0.001, t + 1.8); o.connect(g); g.connect(this.master); g.connect(this.rev); o.start(t); o.stop(t + 1.9);
    [0, 7, 12, 19, 24].forEach((n, i) => this.tone(this.root * 2 * Math.pow(2, n / 12), 3.2, 0.09, 'sine', 0.1 + i * 0.07));
  },
};

// ---------------------------------------------------------------------------------------------------------------------
// State
const tracker = new Tracker($('#cam'));
const S = {
  mode: 'title', t: 0, modeT: 0,
  realm: 0, jumps: 0,
  pos: new THREE.Vector2(), vel: new THREE.Vector2(), z: 0, speed: 4, surge: 0,
  g: new THREE.Vector2(), steer: new THREE.Vector2(), look: new THREE.Vector2(),
  score: 0, combo: 0, best: 0, caught: 0, charge: 0, need: 10,
  embers: [], spawnZ: -140, beat: 0, strayAt: 14,
  pulseAge: 9, pulseCd: 0, flash: 0, flashHold: false, warp: 0,
  eyeDist: 600, eyeLid: 1, eyeFade: 0, blinkAnim: 0,
  closedSim: false, simClosedAt: 0, lostFor: 0,
  blinksSeen: 0, hintT: 0, tutorial: 0,
  focusCharge: 0,
};
function setRealm(i) {
  S.realm = i; const R = REALMS[i % REALMS.length];
  U.uColA.value.setRGB(...R.a); U.uColB.value.setRGB(...R.b); U.uColC.value.setRGB(...R.c);
  fin.uniforms.uWispCol.value.setRGB(...R.c).lerp(new THREE.Color(1, 1, 1), 0.45);
  bakeMat.uniforms.uSeed.value = R.seed + Math.floor(i / REALMS.length) * 3.3;
  renderer.setRenderTarget(skyRT); renderer.render(bakeScene, bakeCam); renderer.setRenderTarget(null);
  audio.setRoot(R.root);
  const css = (c) => `rgb(${c.map(v => Math.round(Math.min(1, v * 0.6 + 0.4) * 255)).join(',')})`;
  document.documentElement.style.setProperty('--c', css(R.a));
}
setRealm(0);

// the line of light you follow: a smooth wander down the canyon
function pathAt(z) { const s = -z; return [6.0 * Math.sin(s * 0.0105) + 2.6 * Math.sin(s * 0.027 + 1.3), 4.6 * Math.sin(s * 0.0135 + 2.1) + 2.0 * Math.cos(s * 0.031)]; }

function spawnAhead() {
  while (S.spawnZ > S.z - 300) {
    const z = S.spawnZ; S.spawnZ -= 8.5; S.beat++;
    const phase = S.beat % 10;                       // 7 lights, a ring, 2 beats of rest
    const [px, py] = pathAt(z);
    if (phase < 7) addEmber(px, py, z, 0);
    else if (phase === 7 && S.tutorial >= 2) {
      const r = ringPool.find(r => !r.on);
      if (r) { r.on = true; r.hit = 0; r.x = px; r.y = py; r.z = z; r.mesh.position.set(px, py, z); r.mesh.scale.setScalar(1); r.mesh.visible = true; }
    }
    if (S.tutorial >= 2 && -z > S.strayAt * 30) {     // a golden stray off the line: worth a deliberate glance
      S.strayAt = -z / 30 + 9 + Math.random() * 6;
      const a = Math.random() * 6.2832, d = 6.5 + Math.random() * 2.5;
      addEmber(clamp(px + Math.cos(a) * d, -12, 12), clamp(py + Math.sin(a) * d, -11, 11), z, 1);
    }
  }
}
function addEmber(x, y, z, kind) { if (S.embers.length < MAXE) S.embers.push({ x, y, z, kind, charge: 0, state: 0, t: 0, seed: Math.random() * 6.28, sx: 0, sy: 0 }); }

// ---------------------------------------------------------------------------------------------------------------------
// DOM helpers
const rowEl = $('#msg .row'), msg = $('#msg'), big = $('#msg .big'), sub = $('#msg .sub'), hintEl = $('#hint');
function say(a, b = '', where = '') { big.textContent = a; sub.textContent = b; msg.className = 'layer ' + where; }
function hush() { msg.classList.add('off'); }
let hintTimer = 0;
function hint(text, secs = 4.5) { hintEl.textContent = text; hintEl.style.opacity = 1; clearTimeout(hintTimer); if (secs) hintTimer = setTimeout(() => { hintEl.style.opacity = 0; }, secs * 1000); }
function showRealm() {
  $('#realm small').textContent = ROMAN[S.jumps % ROMAN.length]; $('#realm span').textContent = REALMS[S.realm % REALMS.length].name;
  $('#realm').classList.add('on'); setTimeout(() => $('#realm').classList.remove('on'), 3200);
}
const scoreN = $('#score .n'), scoreM = $('#score .m'), jumpEl = $('#jump'), jumpBar = $('#jump .bar i'), jumpLbl = $('#jump .lbl');
let shownScore = -1, shownMult = '';
function hud() {
  const s = Math.round(S.score); if (s !== shownScore) { shownScore = s; scoreN.textContent = s.toLocaleString(); }
  const mult = 1 + Math.min(7, Math.floor(S.combo / 8)), m = S.combo > 2 ? `streak ${S.combo} · x${mult}` : ' ';
  if (m !== shownMult) { shownMult = m; scoreM.innerHTML = S.combo > 2 ? `streak <b>${S.combo}</b> · x${mult}` : '&nbsp;'; }
  const c = clamp(S.charge / S.need, 0, 1); jumpBar.style.width = (c * 100).toFixed(0) + '%';
  const ready = c >= 1; if (ready !== jumpEl.classList.contains('ready')) { jumpEl.classList.toggle('ready', ready); jumpLbl.textContent = ready ? (tracker.sim ? 'jump ready' : 'close your eyes to jump') : 'gathering light'; }
}

// ---------------------------------------------------------------------------------------------------------------------
// Flow
function setMode(m) { S.mode = m; S.modeT = 0; }

async function begin(sim) {
  audio.init(); audio.resume(); audio.drone(0.55);
  document.documentElement.requestFullscreen?.({ navigationUI: 'hide' }).catch(() => {});
  navigator.wakeLock?.request('screen').catch(() => {});
  $('#title').classList.add('hidden');
  tracker.sim = !!sim; document.body.classList.toggle('sim', !!sim);
  if (sim) { tracker.setSim(0, 0); setMode('mirror'); say('It sees you', 'tap twice to wake it', 'low'); return; }
  setMode('loading'); say('Opening your eyes', 'allow the camera');
  try {
    await tracker.start((stage) => { if (stage === 'model') say('Opening your eyes', 'loading'); }, Q.get('fakecam'));
    setMode('mirror'); say('It sees you', 'blink twice to wake it', 'low');
  } catch (e) {
    console.warn(e);
    say('No camera', String(e?.message || e).slice(0, 90)); $('#msg .row').classList.remove('hidden');
    $('#retry').textContent = 'Try again'; $('#anyway').textContent = 'Play by touch';
    $('#retry').onclick = () => { $('#msg .row').classList.add('hidden'); begin(false); };
    $('#anyway').onclick = () => { $('#msg .row').classList.add('hidden'); begin(true); };
  }
}
$('#begin').onclick = () => begin(false);
$('#touchmode').onclick = () => begin(true);
$('#mute').onclick = () => { audio.setMuted(!audio.muted); $('#mute').style.opacity = audio.muted ? 0.3 : 0.75; };
$('#recal').onclick = () => { if (!tracker.sim && S.mode === 'fly') startCalibration(true); };
$('#jumpbtn').onclick = () => tryJump();

// calibration: follow a spark for ~10 s
const CAL_PTS = [[0, 0], [-.8, .8], [.8, .8], [-.8, 0], [.8, 0], [-.8, -.8], [.8, -.8], [0, 0]];
const CAL_LEG = 1.15, CAL_HOLD = 0.4, CAL_LEAD = 1.3;
const cal = { targets: [], resume: false, done: false };
function startCalibration(resume) {
  cal.targets = []; cal.resume = !!resume; cal.done = false; setMode('calib');
  say('Follow the spark', 'with your eyes', 'top');
  $('#spark').classList.remove('hidden'); $('#calbar').classList.remove('hidden'); $('#hud').classList.add('hidden');
  placeSpark(0, 0);
}
function placeSpark(x, y) { $('#spark').style.transform = `translate(${((x * .5 + .5) * W).toFixed(1)}px, ${((1 - (y * .5 + .5)) * H).toFixed(1)}px)`; }
function calibStep() {
  const t = S.modeT - CAL_LEAD, seg = CAL_LEG + CAL_HOLD, total = (CAL_PTS.length - 1) * seg;
  if (cal.done) return;
  if (t < 0) { placeSpark(0, 0); if (t > -0.5 && !tracker._rec) tracker.beginCalibration(); return; }
  if (S.modeT > 2.2) hush();
  const i = Math.min(CAL_PTS.length - 2, Math.floor(t / seg)), u = ease(clamp((t - i * seg) / CAL_LEG, 0, 1));
  const a = CAL_PTS[i], b = CAL_PTS[i + 1], x = lerp(a[0], b[0], u), y = lerp(a[1], b[1], u);
  placeSpark(x, y); cal.targets.push({ t: now(), x, y });
  $('#calbar i').style.width = (clamp(t / total, 0, 1) * 100).toFixed(1) + '%';
  if (t >= total) {
    cal.done = true; $('#spark').classList.add('hidden'); $('#calbar').classList.add('hidden');
    const r = tracker.finishCalibration(cal.targets); cal.result = r; console.log('calibration', r);
    if (r.ok) { say('Eyes locked', `${Math.round(r.quality * 100)}% lock`); audio.chord(); setTimeout(launch, 1500); }
    else {
      say('Weak lock', 'face a light · hold the phone at eye level');
      $('#msg .row').classList.remove('hidden'); $('#retry').textContent = 'Retry'; $('#anyway').textContent = r.n >= 40 ? 'Continue' : 'Play by touch';
      $('#retry').onclick = () => { $('#msg .row').classList.add('hidden'); startCalibration(cal.resume); };
      $('#anyway').onclick = () => { $('#msg .row').classList.add('hidden'); if (r.n < 40 || !tracker.model) { tracker.sim = true; document.body.classList.add('sim'); } launch(); };
    }
  }
}
function launch() {
  hush(); $('#hud').classList.remove('hidden'); setMode('fly');
  if (!cal.resume) { S.tutorial = 0; S.hintT = 0; hint(tracker.sim ? 'Drag to steer' : 'Look where you want to fly', 6); showRealm(); audio.boom(); S.surge = 60; S.warp = 0.6; }
  else hint('Recalibrated', 2.5);
}

// blink and long eye-close
tracker.onBlink = () => blink();
function blink() {
  S.blinkAnim = 1;
  if (S.mode === 'mirror') {
    S.blinksSeen++; audio.pulse(); S.pulseAge = 0; fin.uniforms.uPulseO.value.set(.5, .5);
    if (S.blinksSeen === 1) sub.textContent = 'once more';
    if (S.blinksSeen >= 2) setTimeout(() => (tracker.sim ? launch() : startCalibration(false)), 500);
    return;
  }
  if (S.mode !== 'fly' || S.pulseCd > 0) return;
  S.pulseCd = 1.1; S.pulseAge = 0; fin.uniforms.uPulseO.value.set(S.g.x * .5 + .5, S.g.y * .5 + .5); audio.pulse();
  if (S.tutorial === 2) { S.tutorial = 3; }
  for (const e of S.embers) if (e.state === 0 && e.near2 < 4.0 && e.dz > 3 && e.dz < 95) catchEmber(e, true); // the pulse sweeps in everything near your gaze
}
function tryJump() {
  if (S.mode !== 'fly' || S.charge < S.need || S.flashHold) return false;
  S.charge = 0; S.need = Math.min(26, S.need + 6); S.jumps++; S.flashHold = true; S.jumpT = 0; S.swapped = false;
  audio.boom(); S.score += 500; return true;
}

function catchEmber(e, byPulse) {
  e.state = 1; e.t = 0;
  S.combo++; S.best = Math.max(S.best, S.combo); S.caught++; S.charge++;
  const mult = 1 + Math.min(7, Math.floor(S.combo / 8));
  S.score += (e.kind ? 50 : 10) * mult;
  audio.chime(Math.min(S.combo - 1, 14) % 15, e.kind === 1);
  if (!byPulse && !tracker.sim && e.dz < 70) tracker.nudge(e.sx - tracker.gaze.x, e.sy - tracker.gaze.y); // slow self-correction of drift
  if (S.tutorial === 0 && S.caught >= 4) { S.tutorial = 1; hint(tracker.sim ? 'Hold on a light to gather it' : 'Rest your gaze on a light to gather it', 5); }
}

// ---------------------------------------------------------------------------------------------------------------------
// Pointer / keys: the touch stand-in, and a way to test without a camera
let ptr = { x: 0, y: 0, down: false, lastTap: 0 };
function ptrMove(e) { ptr.x = (e.clientX / W) * 2 - 1; ptr.y = 1 - (e.clientY / H) * 2; }
window.addEventListener('pointermove', (e) => { if (tracker.sim) ptrMove(e); });
window.addEventListener('pointerdown', (e) => {
  audio.resume();
  if (!tracker.sim || e.target?.closest?.('button')) return;
  ptrMove(e); const t = now();
  if (S.mode === 'mirror' || t - ptr.lastTap < 0.32) blink();
  ptr.lastTap = t;
});
window.addEventListener('keydown', (e) => {
  if (!tracker.sim || e.repeat) return;
  if (e.code === 'Space') { S.closedSim = true; S.simClosedAt = now(); }
});
window.addEventListener('keyup', (e) => { if (e.code === 'Space' && S.closedSim) { S.closedSim = false; if (now() - S.simClosedAt < 0.5) blink(); } });
document.addEventListener('visibilitychange', () => { if (document.hidden) audio.ctx?.suspend(); else { audio.resume(); last = now(); } });

// ---------------------------------------------------------------------------------------------------------------------
// Frame
const v3 = new THREE.Vector3();
let last = now(), fpsAvg = 60, perfT = 0, slow = 0;
function frame() {
  requestAnimationFrame(frame);
  const tNow = now(); let dt = tNow - last; last = tNow;
  fpsAvg += (1 / Math.max(dt, 1e-3) - fpsAvg) * 0.05;
  dt = Math.min(dt, 0.05);
  S.t += dt; S.modeT += dt; U.uTime.value = S.t; fin.uniforms.uTime.value = S.t;

  // input
  if (tracker.sim) tracker.setSim(ptr.x, ptr.y);
  const closed = tracker.sim ? S.closedSim : tracker.closed, closedFor = tracker.sim ? (S.closedSim ? tNow - S.simClosedAt : 0) : tracker.closedFor;
  const seen = tracker.face;
  S.lostFor = seen ? 0 : S.lostFor + dt;
  const src = (S.mode === 'fly' || S.mode === 'calib') && (tracker.model || tracker.sim) ? tracker.gaze : tracker.raw;
  const k = damp(dt, 0.07); S.g.x += (clamp(src.x, -1, 1) - S.g.x) * k; S.g.y += (clamp(src.y, -1, 1) - S.g.y) * k;

  if (S.mode === 'calib') calibStep();
  if (S.mode === 'mirror' && S.modeT > 14 && S.blinksSeen < 2) { S.blinksSeen = 2; sub.textContent = ''; tracker.sim ? launch() : startCalibration(false); } // never strand the player

  const flying = S.mode === 'fly';
  // --- flight ---
  let targetSpeed = 3;
  if (flying) {
    const lost = S.lostFor > 0.6;
    const m = S.g.length(), dead = 0.1, kk = m > dead ? (m - dead) / (m * (1 - dead)) : 0;
    const sx = lost ? 0 : S.g.x * kk, sy = lost ? 0 : S.g.y * kk;
    S.steer.x += (sx - S.steer.x) * damp(dt, 0.12); S.steer.y += (sy - S.steer.y) * damp(dt, 0.12);
    const reach = portrait ? 9.5 : 13;
    S.vel.x += (S.steer.x * reach - S.vel.x) * damp(dt, 0.2); S.vel.y += (S.steer.y * 11 - S.vel.y) * damp(dt, 0.2);
    S.pos.addScaledVector(S.vel, dt);
    const r = S.pos.length(); if (r > 13) S.pos.multiplyScalar(13 / r);
    targetSpeed = (lost ? 14 : 30 + Math.min(S.combo, 60) * 0.28) + S.surge;
  } else { S.steer.multiplyScalar(1 - damp(dt, 0.3)); S.vel.multiplyScalar(1 - damp(dt, 0.3)); }
  S.surge *= 1 - damp(dt, 1.3); S.warp *= 1 - damp(dt, 0.9);
  S.speed += (targetSpeed - S.speed) * damp(dt, 0.8);
  S.z -= S.speed * dt;

  S.look.x += (S.steer.x - S.look.x) * damp(dt, 0.28); S.look.y += (S.steer.y - S.look.y) * damp(dt, 0.28);
  camera.position.set(S.pos.x, S.pos.y, S.z);
  camera.rotation.set(S.look.y * 0.15, -S.look.x * (portrait ? 0.1 : 0.17), -S.vel.x * 0.014);
  camera.updateMatrixWorld();
  U.uCam.value.copy(camera.position); U.uCamZ.value = S.z;
  U.uStreak.value = 0.6 + S.speed * 0.11 + S.warp * 30;
  U.uGaze.value.copy(S.g); fin.uniforms.uGaze.value.copy(S.g);
  sky.position.copy(camera.position); stars.position.copy(camera.position);

  // --- embers ---
  let focus = 0;
  if (flying) {
    spawnAhead();
    S.pulseCd = Math.max(0, S.pulseCd - dt);
    const rx = portrait ? 0.46 : 0.26, ry = portrait ? 0.27 : 0.42; // how close (in screen terms) a look has to be: sized to what a phone camera can tell apart
    let n = 0;
    for (let i = S.embers.length - 1; i >= 0; i--) {
      const e = S.embers[i]; e.dz = S.z - e.z; e.t += dt;
      if (e.state === 1) { // caught: streak into you
        const u = e.t / 0.32; if (u >= 1) { S.embers.splice(i, 1); continue; }
        const tx = S.pos.x, ty = S.pos.y - 1.0, tz = S.z - 2.5, q = damp(dt, 0.07);
        e.x += (tx - e.x) * q; e.y += (ty - e.y) * q; e.z += (tz - e.z) * q;
      } else {
        if (e.dz < -1.5) { S.embers.splice(i, 1); if (S.combo > 0) S.combo = Math.floor(S.combo / 2); continue; }
        v3.set(e.x, e.y, e.z).project(camera); e.sx = v3.x; e.sy = v3.y;
        const dx = (v3.x - S.g.x) / rx, dy = (v3.y - S.g.y) / ry; e.near2 = dx * dx + dy * dy;
        const lat = Math.hypot(e.x - S.pos.x, e.y - S.pos.y);
        if (e.dz < 3.5 && lat < 2.4) { catchEmber(e, true); }
        else if (e.dz > 3 && e.dz < 85 && e.near2 < 1 && S.lostFor < 0.3 && !closed) { e.charge += dt / (e.kind ? 0.5 : 0.3); if (e.charge >= 1) catchEmber(e, false); }
        else e.charge = Math.max(0, e.charge - dt * 2.5);
        if (e.state === 0) focus = Math.max(focus, e.charge);
      }
    }
    for (const e of S.embers) {
      if (n >= MAXE) break;
      const sc = e.state === 1 ? (1 - e.t / 0.32) * 2.2 : (e.kind ? 3.6 : 2.6) * (1 + e.charge * 0.5) * clamp(e.t * 2, 0, 1) * clamp((300 - e.dz) / 60, 0, 1) * (0.55 + 0.45 * clamp(e.dz / 30, 0, 1));
      ePos.array.set([e.x, e.y + (e.state ? 0 : Math.sin(S.t * 2 + e.seed) * 0.15), e.z], n * 3); eInf.array.set([sc, e.state ? 1 : e.charge, e.kind, e.seed], n * 4); n++;
    }
    emberGeo.instanceCount = n; ePos.needsUpdate = true; eInf.needsUpdate = true;

    // rings
    for (const r of ringPool) {
      if (!r.on) continue; const dz = S.z - r.z, u = r.mesh.material.uniforms.uFade;
      if (r.hit) { r.hit += dt; r.mesh.scale.setScalar(1 + r.hit * 9); r.mesh.position.z = S.z - 6 - r.hit * 30; u.value = Math.max(0, 1 - r.hit * 1.6); if (r.hit > 0.65) { r.on = false; r.mesh.visible = false; } continue; }
      u.value = clamp((300 - dz) / 80, 0, 1); r.mesh.rotation.z += dt * 0.4;
      if (dz < 0.5) {
        if (Math.hypot(r.x - S.pos.x, r.y - S.pos.y) < RING_R) {
          r.hit = 0.001; S.surge += 26; S.warp = Math.max(S.warp, 0.5); audio.chord(); S.score += 100 * (1 + Math.min(7, Math.floor(S.combo / 8)));
          if (S.tutorial === 3) S.tutorial = 4;
        } else { r.on = false; r.mesh.visible = false; }
      }
    }

    // tutorial beats
    S.hintT += dt;
    if (S.tutorial === 1 && S.caught >= 12) { S.tutorial = 2; hint(tracker.sim ? 'Double-tap to send a pulse' : 'Blink to send a pulse', 6); }
    if (S.tutorial >= 2 && S.charge >= S.need && !S.toldJump) { S.toldJump = true; hint(tracker.sim ? 'Tap jump, or hold space' : 'Close your eyes for a second', 7); }
    if (S.lostFor > 0.6 !== !$('#lost').classList.contains('hidden')) $('#lost').classList.toggle('hidden', !(S.lostFor > 0.6));

    // close your eyes to jump
    const ready = S.charge >= S.need;
    audio.rise(ready && closed && !S.flashHold ? clamp(closedFor / 0.9, 0, 1) : 0);
    if (ready && closed && closedFor > 0.9) tryJump();
    hud();
  }
  S.focusCharge += (focus - S.focusCharge) * damp(dt, 0.05);

  // jump sequence: white while your eyes are shut, a new world when they open
  if (S.flashHold) {
    S.jumpT += dt; S.flash = Math.min(1, S.flash + dt / 0.35);
    if (S.flash >= 1 && !S.swapped) { S.swapped = true; setRealm(S.realm + 1); S.toldJump = false; S.surge = 150; S.warp = 1; S.embers.length = 0; emberGeo.instanceCount = 0; ringPool.forEach(r => { r.on = false; r.mesh.visible = false; }); S.spawnZ = S.z - 120; }
    if (S.swapped && ((!closed && S.jumpT > 0.7) || S.jumpT > 3.5)) { S.flashHold = false; showRealm(); }
  } else S.flash = Math.max(0, S.flash - dt / 0.9);

  // --- the Eye ---
  const fitDist = (EYE_SIZE * 0.5) / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2) * Math.min(aspect, 1) * (portrait ? 1 : 1)) * (portrait ? 1.05 / Math.max(aspect, 0.4) * 0.5 : 1.25);
  const wantDist = flying ? 1900 : fitDist;
  S.eyeDist += (wantDist - S.eyeDist) * damp(dt, flying ? 1.6 : 0.6);
  S.eyeFade += ((S.mode === 'title' ? 0.55 : S.mode === 'calib' ? 0.22 : flying ? 0.62 : 1) - S.eyeFade) * damp(dt, 0.7);
  S.blinkAnim = Math.max(0, S.blinkAnim - dt / 0.28);
  const lidWant = S.mode === 'title' ? 0.5 + 0.08 * Math.sin(S.t * 0.6) : S.mode === 'loading' ? 0.75 : Math.max(closed ? 1 : 0, Math.sin(S.blinkAnim * Math.PI));
  S.eyeLid += (lidWant - S.eyeLid) * damp(dt, 0.06);
  const ec = pathAt(S.z - 600);
  eyeMesh.position.set(flying ? ec[0] * 3 : 0, flying ? ec[1] * 3 : (portrait ? EYE_SIZE * 0.06 : 0), S.z - S.eyeDist); eyeMesh.scale.setScalar(EYE_SIZE);
  eyeMesh.quaternion.copy(camera.quaternion);
  eyeU.uLid.value = S.eyeLid; eyeU.uFade.value = S.eyeFade; eyeU.uLook.value.set(S.g.x, S.g.y);
  eyeU.uDil.value += ((flying ? clamp(S.combo / 40, 0, 1) : 0.2) - eyeU.uDil.value) * damp(dt, 0.5);
  eyeU.uPower.value += ((flying && S.charge >= S.need ? 0.7 + 0.3 * Math.sin(S.t * 3) : 0) - eyeU.uPower.value) * damp(dt, 0.4);

  // --- post ---
  S.pulseAge += dt; fin.uniforms.uPulseAge.value = S.pulseAge;
  fin.uniforms.uFlash.value = ease(S.flash); fin.uniforms.uWarp.value = clamp(S.warp + S.surge * 0.004, 0, 1.2);
  fin.uniforms.uWisp.value += (((flying || S.mode === 'mirror') && S.lostFor < 0.6 ? 1 : 0) - fin.uniforms.uWisp.value) * damp(dt, 0.3);
  fin.uniforms.uCharge.value = S.focusCharge;
  fin.uniforms.uDim.value += ((S.mode === 'title' ? 0.35 : rowEl.classList.contains('hidden') ? 0 : 0.8) - fin.uniforms.uDim.value) * damp(dt, 0.6);
  U.uGlow.value = 1 + S.surge * 0.01;
  composer.render();

  // keep the frame rate: step the resolution down if the phone is struggling
  perfT += dt;
  if (perfT > 2.5) {
    perfT = 0;
    if (fpsAvg < 44 && pixelRatio > 0.85) { slow++; if (slow >= 2) { slow = 0; pixelRatio = Math.max(0.85, pixelRatio - 0.25); resize(); } } else slow = 0;
  }
  if (DEBUG) {
    const c = cal.result;
    $('#dbg').textContent = `fps ${fpsAvg.toFixed(0)}  pr ${pixelRatio.toFixed(2)}  trk ${tracker.fps.toFixed(0)}/s ${tracker.delegate}  face ${seen ? 1 : 0}\n` +
      `gaze ${S.g.x.toFixed(2)} ${S.g.y.toFixed(2)}  raw ${tracker.raw.x.toFixed(2)} ${tracker.raw.y.toFixed(2)}  blink ${tracker.blinkL.toFixed(2)} ${tracker.blinkR.toFixed(2)}${closed ? ' CLOSED' : ''}\n` +
      (c ? `cal ${c.ok ? 'ok' : 'weak'} r2 ${c.r2x?.toFixed(2)} ${c.r2y?.toFixed(2)} lag ${(c.lag * 1000 || 0).toFixed(0)}ms n ${c.n} bias ${tracker.bias.x.toFixed(2)} ${tracker.bias.y.toFixed(2)}\n` : '') +
      `mode ${S.mode} embers ${S.embers.length} speed ${S.speed.toFixed(0)}${tracker.err ? '\n' + tracker.err : ''}`;
  }
}
window.__S = S; window.__tracker = tracker; // for the console
frame();
