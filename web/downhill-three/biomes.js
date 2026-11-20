// BIOMES: the skies and the trees of Godot's other worlds (Themes.gd), each ported from its own shader. The ground is in gv.js (snowMat, one style per biome). Each world is meant to be a place, not a recolour:
//   candy      pastel sky and a pale sun; every tree and rock is its own sweet, picked by where it stands
//   egypt      a blue sky to a gold horizon, a pale sun; turquoise and gold trees
//   tunnel     rays and bands converging on the vanishing point, striped glowing columns
//   desert     a huge red sun in rippling stripes, cactus-green trees with pale ribs
//   matrix     code falling down the sky, scan-lit trees
//   synthwave  a striped sun that never sets, hot pink to cyan trees
// Godot's sky COLOR is an authored sRGB colour, so every sky here ends in s2l() like the psychedelic one (worldfx2: the colour rule).
import * as THREE from 'three';
import { S2L_GLSL, HSV_GLSL, GODOT_FOG_LIT } from './worldfx2.js';

const NL = String.fromCharCode(10);
const TAIL = NL + '#include <tonemapping_fragment>' + NL + '#include <colorspace_fragment>' + NL;
const H21 = 'float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }';
const CANDYC = 'vec3 candyc(float h){ h = fract(h) * 6.; if (h < 1.) return vec3(1., .45, .72); if (h < 2.) return vec3(.5, .95, .8); if (h < 3.) return vec3(.72, .55, 1.); if (h < 4.) return vec3(1., .72, .45); if (h < 5.) return vec3(.5, .78, 1.); return vec3(1., .9, .5); }';

const SKY = {
  candy: `vec3 top = vec3(.62, .50, .96), hor = vec3(1., .78, .78); float k = pow(clamp(1. - abs(d.y), 0., 1.), 2.2); vec3 col = mix(top, hor, k); col *= col;
    vec3 sd = normalize(vec3(.25, .30, -1.)); float r = acos(clamp(dot(d, sd), -1., 1.)); col = mix(col, vec3(1., .97, .9), 1. - smoothstep(.13, .14, r)); col += vec3(1., .6, .8) * (1. - smoothstep(.13, .6, r)) * .2;`,
  egypt: `vec3 top = vec3(.10, .30, .78), hor = vec3(.98, .62, .32); float k = pow(clamp(1. - abs(d.y), 0., 1.), 2.5); vec3 col = mix(top, hor, k); col *= col;
    vec3 sd = normalize(vec3(-.3, .32, -1.)); float r = acos(clamp(dot(d, sd), -1., 1.)); float disc = 1. - smoothstep(.15, .16, r); col = mix(col, vec3(1., .97, .8), disc); col += vec3(1., .7, .3) * (1. - smoothstep(.15, .5, r)) * .16;`,
  tunnel: `float rad = acos(clamp(-d.z, -1., 1.)), ang = atan(d.y, d.x), sector = floor((ang + 3.14159) / 6.28318 * 11.), st = fract(rad * 7. - uTime * .35);
    vec3 col = (.5 + .5 * cos(6.28318 * (sector * .09 + rad * .2 + uTime * .02 + vec3(0., .33, .67)))) * (.15 + .85 * smoothstep(0., .2, st) * (1. - smoothstep(.55, .7, st)));
    col *= .35 + .65 * (1. - smoothstep(.3, 2.4, rad)); float horizon = smoothstep(-.12, .25, d.y); col = mix(vec3(.06, 0., .12), col, horizon);`,
  desert: `vec3 sd = normalize(vec3(.12, .28, -1.)); float a = acos(clamp(dot(d, sd), -1., 1.)); vec3 rx = normalize(cross(sd, vec3(0., 1., 0.))), ry = cross(rx, sd); float th = atan(dot(d, ry), dot(d, rx));
    float warp = .08 * sin(th * 4. + uTime * .25) + .05 * sin(th * 9. - uTime * .4) + .04 * sin(a * 6. - uTime * .2), rip = sin((a + warp) * 46. - uTime * .6);
    vec3 c1 = vec3(.93, .28, .32), c2 = vec3(1., .72, .42), c3 = vec3(.55, .78, .62); float far = smoothstep(.3, 2.4, a);
    vec3 col = mix(c1, c2, smoothstep(-.2, .5, rip)); col = mix(col, c3, smoothstep(.55, .95, rip) * far * (.5 + .5 * sin(th * 3. + uTime * .1)));
    vec3 sun = mix(vec3(.96, .3, .2), vec3(1., .5, .3), a / .3); col = mix(col, vec3(1., .85, .55), 1. - smoothstep(.29, .34, a)); col = mix(col, sun, 1. - smoothstep(.27, .29, a)); col = mix(vec3(.75, .28, .28), col, smoothstep(-.12, .05, d.y));`,
  matrix: `float az = atan(d.x, -d.z), cl = floor(az * 26.), spd = .2 + h21(vec2(cl, 1.)) * .5, y = d.y * 14., t = fract(h21(vec2(cl, 5.)) - uTime * spd * .25 + floor(y) * .11);
    float streak = pow(1. - t, 4.) * step(0., d.y), cellf = smoothstep(0., .2, fract(az * 26.)) * (1. - smoothstep(.8, 1., fract(az * 26.)));
    vec3 col = mix(vec3(0., .05, .02), vec3(0.), clamp(d.y * 2., 0., 1.)) + vec3(.1, 1., .3) * streak * cellf * .5;`,
  synthwave: `vec3 top = vec3(.04, 0., .16), hor = vec3(1., .25, .55); float k = pow(clamp(1. - abs(d.y), 0., 1.), 3.); vec3 col = mix(top, hor, k);
    vec3 sd = normalize(vec3(0., .14, -1.)); float r = acos(clamp(dot(d, sd), -1., 1.)), disc = 1. - smoothstep(.325, .34, r), band = step(.5, fract((d.y - .14) * 22. + .5)); float cut = d.y < .14 ? mix(1., band, clamp((.14 - d.y) * 9., 0., 1.)) : 1.;
    vec3 sun = mix(vec3(1., .85, .2), vec3(1., .1, .55), clamp((.34 - r) * -3. + (.14 - d.y) * 4. + .2, 0., 1.)); col = mix(col, sun, disc * cut); col += vec3(1., .3, .6) * (1. - smoothstep(.325, .7, r)) * .18;`,
};

export function skyBiome(id, U) {
  const body = SKY[id]; if (!body) return null;
  return new THREE.ShaderMaterial({ uniforms: { uTime: U.uTime }, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: 'varying vec3 vD; void main(){ vD = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.); gl_Position = p.xyww; }',
    fragmentShader: 'uniform float uTime; varying vec3 vD;' + NL + S2L_GLSL + NL + H21 + NL + 'void main(){ vec3 d = normalize(vD); ' + body + ' gl_FragColor = vec4(s2l(col), 1.);' + TAIL + '}' });
}

// the trees: what each one is made of, from the vertex colour's brightness (the pale cap, the dark underside) and where it stands
const VEG = {
  candy: { emi: `float lum = dot(vcr_, vec3(.34)); vec3 base = candyc(h21(floor(vOrg.xz * .37)) * 1.7), top = mix(base, vec3(1., .97, .98), .72); float k = floor(smoothstep(.22, .85, lum) * 3.) / 2.; vec3 c = mix(base * .82, top, clamp(k, 0., 1.)); diffuseColor.rgb = vec3(0.); gEmiV = s2l(c * c);` },
  egypt: { emi: `float lum = dot(vcr_, vec3(.34)); float k = floor(smoothstep(.30, .80, lum) * 3.) / 2.; vec3 c = mix(vec3(.08, .62, .58), vec3(1., .8, .3), clamp(k, 0., 1.)); diffuseColor.rgb = vec3(0.); gEmiV = s2l(c * c);` },
  tunnel: { emi: `float lum = dot(vcr_, vec3(.34)); float b = floor(vWp.y * .9 + abs(vWp.x) * .08); vec3 neon = hsv(fract(b * .23 + .55), .9, 1.); diffuseColor.rgb = s2l(mix(vec3(.02, 0., .05), neon * .7, smoothstep(.1, .9, lum))); gEmiV = neon * smoothstep(.35, 1., lum) * .5;`, rough: .5 },
  desert: { emi: `float lum = dot(vcr_, vec3(.34)); float rib = .5 + .5 * sin((vWp.x + vWp.z) * 6. + vWp.y * .5); vec3 g = mix(vec3(.1, .27, .17), vec3(.32, .55, .3), rib); diffuseColor.rgb = s2l(mix(vec3(.05, .1, .07), g, smoothstep(.1, .9, lum)));`, rough: .8 },
  matrix: { emi: `float lum = dot(vcr_, vec3(.34)); float scan = .65 + .35 * sin(vWp.y * 6. - uTime * 3.); diffuseColor.rgb = vec3(0.); gEmiV = s2l(mix(vec3(0., .03, .01), vec3(.15, 1., .4) * scan, smoothstep(.1, .95, lum)));` },
  synthwave: { emi: `float lum = dot(vcr_, vec3(.34)); vec3 hot = mix(vec3(1., .15, .6), vec3(.2, .85, 1.), clamp(vWp.y * .12, 0., 1.)); diffuseColor.rgb = vec3(0.); gEmiV = s2l(mix(vec3(.06, 0., .12), hot, smoothstep(.1, .95, lum))) * .85;` },
};

export function vegBiome(id, U, F2) {
  const V = VEG[id]; if (!V) return null;
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: V.rough === undefined ? 1 : V.rough, metalness: 0, side: THREE.DoubleSide, fog: false }); m.userData.veg = true;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, { uTime: U.uTime }, F2.VC, F2.fogU());
    sh.vertexShader = 'varying vec3 vWp; varying vec3 vOrg;' + NL + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      vec4 wpp_ = vec4(transformed, 1.0), o_ = vec4(0., 0., 0., 1.);
      #ifdef USE_INSTANCING
      wpp_ = instanceMatrix * wpp_; o_ = instanceMatrix * o_;
      #endif
      vWp = (modelMatrix * wpp_).xyz; vOrg = (modelMatrix * o_).xyz;`);
    sh.fragmentShader = 'varying vec3 vWp; varying vec3 vOrg; uniform float uTime, vc_lin, gFogDensity; uniform vec3 gFogColor;' + NL + HSV_GLSL + NL + S2L_GLSL + NL + H21 + NL + CANDYC + NL + sh.fragmentShader
      .replace('#include <color_fragment>', `
        vec3 vcr_ = ${F2.vcOf('vColor.rgb')}; vec3 gEmiV = vec3(0.);
        ${V.emi}`)
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>' + NL + 'totalEmissiveRadiance += gEmiV;')
      .replace('#include <fog_fragment>', GODOT_FOG_LIT);
  };
  m.customProgramCacheKey = () => 'biomes-veg-' + id;
  return m;
}
