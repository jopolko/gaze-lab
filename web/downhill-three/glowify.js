// GLOWIFY: turns a flat unshaded MeshBasicMaterial into a glowing one. A bright fresnel rim, a slow shimmer toward the world's hue, and a lift on every beat; the values go above 1 on purpose, so the bloom pass draws a halo around them.
// usage: glowify(mat, { uTime, uBeat }, { rim: 1.6, beat: .5 })  (idempotent)
export function glowify(mat, U, o = {}) {
  if (!mat || !mat.isMeshBasicMaterial || mat.userData.glowified) return mat; mat.userData.glowified = true;
  const rim = o.rim === undefined ? 1.6 : o.rim, beat = o.beat === undefined ? .5 : o.beat;
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = U.uTime; sh.uniforms.uBeat = U.uBeat;
    sh.vertexShader = 'varying vec3 vGn; varying vec3 vGv; varying vec3 vGw;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
      vec3 nn_ = normal; vec4 pp_ = vec4(transformed, 1.0);
      #ifdef USE_INSTANCING
      nn_ = mat3(instanceMatrix) * nn_; pp_ = instanceMatrix * pp_;
      #endif
      vGn = normalize(normalMatrix * nn_); vGv = -(modelViewMatrix * pp_).xyz; vGw = (modelMatrix * pp_).xyz;`);
    sh.fragmentShader = 'varying vec3 vGn; varying vec3 vGv; varying vec3 vGw; uniform float uTime, uBeat;\nvec3 gH_(float h){ return clamp(abs(mod(h * 6. + vec3(0., 4., 2.), 6.) - 3.) - 1., 0., 1.); }\n' + sh.fragmentShader.replace('#include <color_fragment>', `#include <color_fragment>
      { float f_ = pow(1.0 - abs(dot(normalize(vGn), normalize(vGv))), 1.7); vec3 hue_ = gH_(fract(vGw.z * 0.004 + uTime * 0.05));
        diffuseColor.rgb = diffuseColor.rgb * (0.85 + ${rim.toFixed(2)} * f_ + ${beat.toFixed(2)} * uBeat) + mix(diffuseColor.rgb, hue_, 0.55) * f_ * 0.9; }`);
  };
  mat.customProgramCacheKey = () => 'glowify' + rim + '_' + beat; mat.needsUpdate = true; return mat;
}

// GLOWLIT: the same idea for lit white materials (rocks, bumps, posts): near-white surfaces are tinted toward the world's hue instead of reading as flat cream, and the rim emits light that the bloom picks up.
export function glowLit(mat, U, o = {}) {
  if (!mat || !mat.isMeshStandardMaterial || mat.userData.glowified) return mat; mat.userData.glowified = true; const k = o.rim === undefined ? 1.1 : o.rim;
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uTime = U.uTime; sh.uniforms.uBeat = U.uBeat;
    sh.fragmentShader = 'uniform float uTime, uBeat;\nvec3 gH_(float h){ return clamp(abs(mod(h * 6. + vec3(0., 4., 2.), 6.) - 3.) - 1., 0., 1.); }\n' + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        float gl_ = dot(diffuseColor.rgb, vec3(.333)); vec3 gh_ = gH_(fract(uTime * .04 + normal.y * .12 + normal.x * .09));
        diffuseColor.rgb = mix(diffuseColor.rgb, gh_ * .85 + .12, smoothstep(.6, .95, gl_) * .55);`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        { float rim_ = pow(1. - clamp(dot(normalize(normal), normalize(vViewPosition)), 0., 1.), 2.2); totalEmissiveRadiance += (gh_ * ${k.toFixed(2)} * rim_) * (1. + .6 * uBeat) + gh_ * .08; }`);
  };
  mat.customProgramCacheKey = () => 'glowlit' + k; mat.needsUpdate = true; return mat;
}
