// REALMS: the strange places of Godot's barrier courses (Realms.gd), their two shaders ported:
//   the realm GROUND   vertex-coloured, lit a little, glowing: ALBEDO = c*c*0.4, EMISSION = c*c*0.7 * boost * (1 + flash*0.8)   (the ground carries the realm's colours in its vertices)
//   the GLOW shader    mushrooms, crystals, eyes, jellyfish, cave roofs: rim-lit, emissive, with a wobble where the vertex alpha is below 1, a beat pulse and a sway
// The caverns (glowcave, crystal, lava, abyss) are roofed: the picture is dimmed while you are inside (cave_k, ROOF below) and the glowing things are boosted to be the light.
import * as THREE from 'three';
import { S2L_GLSL, GODOT_FOG_LIT } from './worldfx2.js';

const NL = String.fromCharCode(10);

// what Godot does to the picture inside each roofed realm (Realms.ROOF): fog colour, exposure, and what it says when the lights come on
export const ROOF = {
  glowcave: { col: [.12, .08, .22], expo: .4, reveal: 'THE GROTTO WAKES' },
  crystal: { col: [.08, .12, .24], expo: .5, reveal: 'THE VAULT LIGHTS' },
  lava: { col: [.16, .06, .05], expo: .55, reveal: 'THE TUBE GLOWS' },
  abyss: { col: [.03, .08, .20], expo: .35, reveal: 'SOMETHING IS WATCHING' },
};

export function isRealmShader(code) { return code.includes('ALBEDO = c * 0.4') || code.includes('uniform float glow'); }

export function realmMaterial(code, params, U, F2) {
  const p = params || {};
  if (code.includes('ALBEDO = c * 0.4')) return ground(p, U, F2);
  if (code.includes('uniform float glow')) return glow(p, U, F2);
  return null;
}

function common(m, U, F2, vertexHook, fragHook, emisHook = '') {
  m.userData.veg = false;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, { uTime: U.uTime, uBeat: U.uBeatG }, F2.VC, F2.fogU(), m.userData.u);
    sh.vertexShader = 'attribute float aW; varying vec3 vWP; uniform float uTime, uBeat, uWob;' + NL + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>' + NL + vertexHook + NL + 'vWP = (modelMatrix * vec4(transformed, 1.)).xyz;');
    sh.fragmentShader = 'varying vec3 vWP; uniform float uBoost, uFlash, uGlow, uTime, vc_lin, gFogDensity; uniform vec3 gFogColor;' + NL + S2L_GLSL + NL + sh.fragmentShader
      .replace('#include <color_fragment>', '#include <color_fragment>' + NL + 'vec3 vcr_ = ' + F2.vcOf('vColor.rgb') + '; vec3 gEmiV = vec3(0.);' + NL + fragHook)
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>' + NL + emisHook + NL + 'totalEmissiveRadiance += gEmiV;')
      .replace('#include <fog_fragment>', GODOT_FOG_LIT);
  };
}

function ground(p, U, F2) {
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .95, metalness: 0, side: THREE.DoubleSide, fog: false });
  m.userData.u = { uBoost: { value: p.boost === undefined ? 1 : p.boost }, uFlash: { value: p.flash || 0 }, uGlow: { value: 0 }, uWob: { value: 0 } };
  common(m, U, F2, '', `float q_ = vWP.x * .22 + sin(vWP.z * .09 + uTime * .3) * 1.6, r_ = vWP.z * .22 + cos(vWP.x * .07 - uTime * .25) * 1.6;
     float fd_ = 1. - smoothstep(50., 200., length(vViewPosition));
     float ln_ = (pow(abs(sin(q_ * 3.14159)), 22.) + pow(abs(sin(r_ * 3.14159)), 22.)) * fd_;
     float bl_ = .5 + .5 * sin(vWP.x * .045 + uTime * .4) * sin(vWP.z * .05 - uTime * .3), mo_ = .5 + .5 * sin(vWP.x * 1.7 + vWP.z * 1.3 + sin(vWP.z * .4) * 3.) * fd_;
     vec3 cc_ = vcr_ * vcr_ * (.7 + .45 * bl_ + .15 * mo_);
     diffuseColor.rgb = s2l(cc_ * .4); gEmiV = cc_ * .7 * uBoost * (1. + uFlash * .8) + mix(vcr_, vec3(1.), .45) * vcr_ * ln_ * .8;`);
  m.customProgramCacheKey = () => 'realm-ground'; return m;
}

function glow(p, U, F2) {
  const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: .7, metalness: 0, side: THREE.DoubleSide, fog: false });
  m.userData.u = { uBoost: { value: p.boost === undefined ? 1 : p.boost }, uFlash: { value: p.flash || 0 }, uGlow: { value: p.glow === undefined ? .3 : p.glow }, uWob: { value: p.wob || 0 } };
  common(m, U, F2,
    `float w_ = aW; float id_ = float(gl_InstanceID);
     transformed.y += sin(uTime * 9. + transformed.x * 2. + id_) * .4 * w_; transformed.x += cos(uTime * 7. + id_ * 1.7) * .3 * w_;
     transformed *= 1. + uBeat * .07 * sin(uTime * 5.5);
     transformed.xz += uWob * .22 * sin(uTime * 1.8 + transformed.y * 1.4 + id_) * max(transformed.y, 0.) * .3;`,
    `diffuseColor.rgb = s2l(vcr_);`,
    `float rim_ = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.2); gEmiV = (vcr_ * uGlow + vcr_ * rim_ * .5) * uBoost * (1. + uFlash * 1.5);`);
  m.customProgramCacheKey = () => 'realm-glow'; return m;
}
