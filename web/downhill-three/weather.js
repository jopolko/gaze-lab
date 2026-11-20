// WEATHER: what is in the air of each world. Quiet by design (a light field of particles around the camera, recycled as you move), never in the way of the road or the targets.
//   alpine     light falling snow (Lighting.gd: 600 white quads of 0.14 m in a 76 x 30 x 76 m box around the camera, drifting down)
//   candy      sprinkles in the candy colours drifting down
//   egypt      the sandstorm (ThemeFX.gd: every 55 s, 14 s long, the fog goes thick and gold, `SANDSTORM! follow the beams`) with wind-blown sand
//   desert     warm dust blowing across, a few motes rising off the hot ground
//   tunnel     light streaks rushing toward you along the road
//   matrix     code falling in green streaks
//   synthwave  neon motes drifting up
//   psychedelic  none (the frozen look)
import * as THREE from 'three';

const CANDY = [[1, .45, .72], [.5, .95, .8], [.72, .55, 1], [1, .72, .45], [.5, .78, 1], [1, .9, .5]];
const CFG = {
  alpine: { kind: 'points', n: 600, size: .14, rgb: [1, 1, 1], a: .85, vel: [.35, -1.6, .2], box: [76, 30, 76], off: [0, 4, -14], add: false },
  candy: { kind: 'points', n: 420, size: .26, pal: CANDY, a: .95, vel: [.5, -.8, .15], box: [70, 26, 70], off: [0, 4, -14], add: false },
  egypt: { kind: 'points', n: 900, size: .17, rgb: [.95, .78, .5], a: .05, vel: [-3, -.2, .6], box: [90, 26, 90], off: [0, 3, -18], add: false, storm: true },
  desert: { kind: 'points', n: 360, size: .16, rgb: [1, .72, .5], a: .35, vel: [-2.2, .5, .6], box: [80, 22, 80], off: [0, 3, -16], add: false },
  tunnel: { kind: 'streaks', n: 320, len: 6, pal: [[.2, .9, 1], [1, .25, .8]], a: .8, vel: [0, 0, 40], box: [40, 20, 160], off: [0, 4, -70], add: true, rush: true },
  matrix: { kind: 'streaks', n: 520, len: 3.4, rgb: [.1, 1, .3], a: .65, vel: [0, -12, 0], box: [60, 34, 70], off: [0, 8, -24], add: true },
  synthwave: { kind: 'points', n: 260, size: .2, pal: [[1, .1, .65], [.15, .85, 1]], a: .9, vel: [0, .6, 0], box: [80, 26, 90], off: [0, 4, -18], add: true },
};
const STORM_EVERY = 55, STORM_LEN = 14;

const VERT = `uniform vec3 uCam, uBox, uVel, uOff; uniform float uTime, uSize, uH, uA, uLen; attribute vec4 aS; attribute vec3 aC; attribute float aEnd; varying vec3 vCol; varying float vA;
  void main(){
    vec3 p = aS.xyz * uBox + uVel * uTime * (.7 + .6 * aS.w), c = uCam + uOff; p = c + (mod(p - c + uBox * .5, uBox) - uBox * .5);
    float fade = 1. - smoothstep(.35, .5, length((p - c) / uBox));
    #ifdef STREAK
    p -= normalize(uVel) * uLen * (.5 + aS.w) * aEnd; vA = uA * fade * (1. - aEnd);
    vec4 mv = viewMatrix * vec4(p, 1.); gl_Position = projectionMatrix * mv;
    #else
    vec4 mv = viewMatrix * vec4(p, 1.); gl_Position = projectionMatrix * mv; gl_PointSize = clamp(uSize * (.6 + .9 * aS.w) * projectionMatrix[1][1] * uH * .5 / max(-mv.z, .1), 1., 40.); vA = uA * fade;
    #endif
    vCol = aC * aC;
  }`;
const FRAG = `varying vec3 vCol; varying float vA;
  void main(){
    #ifdef STREAK
    float a = 1.;
    #else
    float a = smoothstep(.5, .2, length(gl_PointCoord - .5));
    #endif
    #ifdef ADD
    gl_FragColor = vec4(vCol * a * vA, 1.);
    #else
    gl_FragColor = vec4(vCol, a * vA);
    #endif
  }`;

export function createWeather({ scene, theme, U, toast, fogSceneRef }) {
  const cfg = CFG[theme]; if (!cfg) return { tick() { }, active: false };
  const streak = cfg.kind === 'streaks', n = cfg.n, vc = streak ? n * 2 : n;
  const S = new Float32Array(vc * 4), C = new Float32Array(vc * 3), E = new Float32Array(vc);
  for (let i = 0; i < n; i++) {
    const s = [Math.random(), Math.random(), Math.random(), Math.random()], col = cfg.pal ? cfg.pal[Math.floor(Math.random() * cfg.pal.length)] : cfg.rgb;
    for (let k = 0; k < (streak ? 2 : 1); k++) { const v = streak ? i * 2 + k : i; S.set(s, v * 4); C.set(col, v * 3); E[v] = k; }
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('aS', new THREE.BufferAttribute(S, 4)); g.setAttribute('aC', new THREE.BufferAttribute(C, 3)); g.setAttribute('aEnd', new THREE.BufferAttribute(E, 1)); g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(vc * 3), 3));
  const defs = {}; if (streak) defs.STREAK = ''; if (cfg.add) defs.ADD = '';
  const mat = new THREE.ShaderMaterial({ defines: defs, transparent: true, depthWrite: false, blending: cfg.add ? THREE.AdditiveBlending : THREE.NormalBlending, fog: false,
    uniforms: { uCam: { value: new THREE.Vector3() }, uBox: { value: new THREE.Vector3(...cfg.box) }, uVel: { value: new THREE.Vector3(...cfg.vel) }, uOff: { value: new THREE.Vector3(...cfg.off) }, uTime: { value: 0 }, uSize: { value: cfg.size || 0 }, uH: { value: 720 }, uA: { value: cfg.a }, uLen: { value: cfg.len || 0 } }, vertexShader: VERT, fragmentShader: FRAG });
  const obj = streak ? new THREE.LineSegments(g, mat) : new THREE.Points(g, mat); obj.frustumCulled = false; obj.renderOrder = 8; scene.add(obj);
  let t = 0, clock = 0, said = false, base = null; const stormCol = new THREE.Color(.9, .66, .38);
  function tick(dt, camPos, spdNorm, heightPx) {
    t += dt; clock += dt; const u = mat.uniforms; u.uTime.value = t; u.uCam.value.copy(camPos); if (heightPx) u.uH.value = heightPx;
    if (cfg.rush) u.uVel.value.z = 30 + 1.6 * spdNorm;
    if (cfg.storm) {          // the sandstorm: Godot's own envelope and fog values
      const cyc = clock % STORM_EVERY; let k = 0; if (cyc > STORM_EVERY - STORM_LEN) k = Math.sin((cyc - (STORM_EVERY - STORM_LEN)) / STORM_LEN * Math.PI);
      u.uA.value = cfg.a + .7 * k; u.uVel.value.set(-3 - 24 * k, -.2, .6 + 6 * k);
      if (!base) base = { c: U.fogColor.value.clone() };
      U.fogDensity.value = U.fogDensity.value + (0.016 - U.fogDensity.value) * k; U.fogColor.value.copy(base.c).lerp(stormCol, k);
      if (fogSceneRef && fogSceneRef.fog) { fogSceneRef.fog.density = U.fogDensity.value; fogSceneRef.fog.color.copy(U.fogColor.value); }
      if (k > .15 && !said) { said = true; if (toast) toast('SANDSTORM!  follow the beams', '#ffcc66'); } else if (k < .02) said = false;
    }
  }
  return { tick, active: true, mesh: obj };
}
