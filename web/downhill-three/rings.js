// RINGS: the distant horizon of each world, drawn on the mountain ring that follows the camera. Godot gives only two of its own (pyramids for Egypt, candy hills for candy: they come from the dump with their own vertex colours); the others used the plain white mountains, which is what made every world feel the same. These put each world's own landmarks on the horizon:
//   desert     mesas in strata of sand, rust and teal, ringed by thin dark contour lines (the ground's poster look at the scale of mountains)
//   synthwave  dark purple mountains drawn as a neon wireframe, glowing, with a hot haze at their feet
//   matrix     black towers of data with green scan lines and code falling down them
//   tunnel     dark walls banded in neon, one colour per band, glowing
//   egypt      the pyramids' own warm colours, lit, with the courses of blocks showing and a gold tip
//   candy      the hills' own pastel colours, softly lit
// All of them fade into the fog colour toward their base so they meet the horizon.
import * as THREE from 'three';
import { S2L_GLSL, HSV_GLSL } from './worldfx2.js';

const NL = String.fromCharCode(10);
const TAIL = NL + '#include <tonemapping_fragment>' + NL + '#include <colorspace_fragment>' + NL;
const H21 = 'float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }';

const BODY = {
  egypt: `float lam = clamp(dot(normalize(vN), normalize(vec3(-.35, .8, -.45))), 0., 1.); float course = 1. - smoothstep(0., .04, abs(fract(vP.y * .07) - .5) * 2. - .93);
    vec3 col = vC * (.36 + .5 * lam) * (1. - .22 * course);          // sandstone pyramids: the mesh's own warm colours, lit by the sun, with the blocks' courses showing
    col = mix(col, vec3(1., .85, .35), smoothstep(430., 480., vP.y) * .7);`,
  candy: `float lam = clamp(dot(normalize(vN), normalize(vec3(-.35, .8, -.45))), 0., 1.); vec3 col = vC * (.78 + .36 * lam);          // candy hills: the mesh's pastel colours, soft light`,
  desert: `float lam = clamp(dot(normalize(vN), normalize(vec3(-.35, .8, -.45))), 0., 1.); float k = fract(vP.y * .02 + .5 * sin(atan(vP.z, vP.x) * 5.) * .1);
    vec3 c = k < .45 ? vec3(.92, .52, .40) : (k < .8 ? vec3(.66, .22, .24) : vec3(.22, .42, .42));
    float edge = 1. - smoothstep(0., .02, min(abs(k - .45), min(abs(k - .8), min(k, 1. - k)))); c = mix(c, vec3(.15, .04, .08), edge * .7);
    vec3 col = c * (.5 + .55 * lam) * (.7 + .5 * dot(vC, vec3(.34)));`,
  synthwave: `float ang = atan(vP.z, vP.x); float l1 = 1. - smoothstep(0., .05, abs(fract(vP.y * .05) - .5) * 2. - .9 + .0), l2 = 1. - smoothstep(0., .05, abs(fract(ang * 18.) - .5) * 2. - .9);
    float wire = max(smoothstep(.86, .98, abs(fract(vP.y * .05) - .5) * 2.), smoothstep(.86, .98, abs(fract(ang * 18.) - .5) * 2.));
    vec3 neon = mix(vec3(1., .1, .65), vec3(.15, .85, 1.), clamp(vP.y / 260., 0., 1.));
    vec3 col = vec3(.05, 0., .1) * (.6 + dot(vC, vec3(.34))) + neon * wire * 1.1;`,
  matrix: `float ang = atan(vP.z, vP.x), cl = floor(ang * 60.), spd = .2 + h21(vec2(cl, 1.)) * .5, t = fract(h21(vec2(cl, 5.)) - uTime * spd * .25 + floor(vP.y * .09) * .11);
    float streak = pow(1. - t, 4.) * (1. - smoothstep(0., .25, abs(fract(ang * 60.) - .5) - .15)); float scan = 1. - smoothstep(0., .08, abs(fract(vP.y * .04) - .5) * 2. - .85);
    vec3 col = vec3(0., .02, .01) + vec3(.1, 1., .3) * (streak * .6 + scan * .25);`,
  tunnel: `float b = floor(vP.y * .03), f = fract(vP.y * .03); vec3 neon = hsv(fract(b * .23 + .55), .9, 1.); float line = smoothstep(0., .05, f) * (1. - smoothstep(.08, .16, f));
    vec3 col = vec3(.02, 0., .06) * (.6 + dot(vC, vec3(.34))) + neon * line * .9;`,
};

export function ringBiome(id, U) {
  const body = BODY[id]; if (!body) return null;
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime, fogColor: U.fogColor }, side: THREE.DoubleSide, fog: false,
    vertexShader: 'attribute vec3 color; varying vec3 vP; varying vec3 vN; varying vec3 vC; void main(){ vP = position; vN = normalize(mat3(modelMatrix) * normal); vC = color; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: 'uniform float uTime; uniform vec3 fogColor; varying vec3 vP; varying vec3 vN; varying vec3 vC;' + NL + S2L_GLSL + NL + HSV_GLSL + NL + H21 + NL +
      'void main(){ ' + body + ' float haze = 1. - smoothstep(-60., 200., vP.y); vec3 lin = mix(s2l(col), fogColor, haze * .55); gl_FragColor = vec4(lin, 1.);' + TAIL + '}' });
}
