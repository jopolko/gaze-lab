// node molmesh_check.mjs : geometry counts, winding, NaNs, the shader hook, pill transform, and an icon draw with a recording stub
import * as THREE from '../stargaze/vendor/three/three.module.min.js';
import { buildMolGeometry, moleculeMaterial, pillTransform, drawMolIcon, drawMolBar, MOL_ORDER, PILL } from './molmesh.js';
import { MOLS } from './molecules.js';
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL', m); } else console.log('ok  ', m); };
for (const id of MOL_ORDER) {
  const g = buildMolGeometry(THREE, id), pos = g.attributes.position.array, nor = g.attributes.normal.array, col = g.attributes.color.array, n = pos.length / 3, md = MOLS[id];
  const dbl = md.bonds.filter((b) => b[2] === 2).length, rods = md.bonds.length + dbl;
  const expect = (md.atoms.length * 80 + rods * 24) * 3;
  ok(n === expect, id + ': ' + n + ' vertices (' + md.atoms.length + ' atoms x 80 tris + ' + rods + ' sticks x 24 tris)');
  ok(![...pos, ...nor, ...col].some((v) => !isFinite(v)), id + ': no NaN');
  let inward = 0, tris = n / 3; for (let t = 0; t < tris; t++) { const a = new THREE.Vector3().fromArray(pos, t * 9), b = new THREE.Vector3().fromArray(pos, t * 9 + 3), c = new THREE.Vector3().fromArray(pos, t * 9 + 6), fn = b.clone().sub(a).cross(c.clone().sub(a)), vn = new THREE.Vector3().fromArray(nor, t * 9); if (fn.lengthSq() > 1e-14 && fn.dot(vn) < 0) inward++; }
  ok(inward === 0, id + ': every face winds outward (' + inward + ' inward of ' + tris + ')');
  g.computeBoundingBox(); const s = new THREE.Vector3(); g.boundingBox.getSize(s); console.log('     size', s.toArray().map((x) => +x.toFixed(2)).join(' x '), ' (x1.6 in the world =', (s.x * 1.6).toFixed(1), 'm long)');
}
const f = THREE.ShaderLib.physical.fragmentShader; ok(f.includes('#include <lights_fragment_end>'), 'physical shader has the lights_fragment_end include');
const m = moleculeMaterial(THREE); const sh = { fragmentShader: f }; m.onBeforeCompile(sh);
const lines = sh.fragmentShader.split('\n'); const li = lines.findIndex((l) => l.startsWith('#if NUM_DIR_LIGHTS > 0') ); ok(li > 0 && lines[li - 1].trim() === '#include <lights_fragment_end>' && lines.some((l) => l.startsWith('for (int ri = 0')), 'rim GLSL starts on its own lines after the include');
ok(m.roughness === 0.45 && m.specularIntensity === 1.4 && Math.abs(m.emissive.r - THREE.Color.prototype.setRGB.call(new THREE.Color(), 0.22, 0.22, 0.26, THREE.SRGBColorSpace).r) < 1e-6, 'material: roughness .45, specular .7 (x2), emission .22/.22/.26');
const M = new THREE.Matrix4(); pillTransform(THREE, M, 10, 100, -50, 0, 0); const p = new THREE.Vector3(), q = new THREE.Quaternion(), s2 = new THREE.Vector3(); M.decompose(p, q, s2);
ok(Math.abs(p.y - (100 + PILL.y_above_snow + PILL.bob_amp * Math.sin(0 * PILL.bob_rate + 10))) < 1e-9 && Math.abs(s2.x - 1.6) < 1e-9, 'pill transform: height 2.2 + bob, scale 1.6');
const calls = []; const ctx = new Proxy({}, { get: (_, k) => (typeof k === 'string' && ['beginPath', 'moveTo', 'lineTo', 'stroke', 'arc', 'fill', 'fillText'].includes(k)) ? (...a) => calls.push(k) : undefined, set: () => true });
drawMolIcon(ctx, 'mescaline', 1.0, 30, { got: true, cx: 50, cy: 50 }); const heavy = MOLS.mescaline.atoms.filter((a) => a[0] !== 'H').length;
ok(calls.filter((c) => c === 'fill').length === heavy, 'HUD icon draws only the ' + heavy + ' heavy atoms');
drawMolBar(ctx, 800, { got: [true, true, false, false, false, true], felt: [.5, .2, 0, 0, 0, .1], held: [1, .5, 0, 0, 0, 1], pop: [0, 0, 0, 0, 0, 0], age: 3 }); ok(calls.includes('fillText'), 'the bar draws names, perks and the count');
console.log(bad ? 'FAILURES: ' + bad : 'all passed'); process.exit(bad ? 1 : 0);
