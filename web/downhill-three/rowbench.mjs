// node rowbench.mjs : what a row costs when it arrives (parse + build), with the same loops gv.js uses
import * as THREE from '../stargaze/vendor/three/three.module.min.js';
import fs from 'fs';
const dir = new URL('./data/long_s7/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const meta = JSON.parse(fs.readFileSync(dir + 'meta.json', 'utf8'));
const mat4 = (a) => new THREE.Matrix4().set(a[0], a[3], a[6], a[9], a[1], a[4], a[7], a[10], a[2], a[5], a[8], a[11], 0, 0, 0, 1);
const out = [];
for (const j of [2, 5, 10, 20, 33]) {
  const f = dir + 'row_' + String(j).padStart(2, '0') + '.json', txt = fs.readFileSync(f, 'utf8');
  let t0 = process.hrtime.bigint(); const r = JSON.parse(txt); const tParse = Number(process.hrtime.bigint() - t0) / 1e6;
  const meshes = Object.assign({}, meta.meshes, r.meshes); t0 = process.hrtime.bigint(); let geoms = 0, inst = 0, verts = 0;
  const GEO = {};
  for (const n of r.nodes) {
    if (n.class === 'MeshInstance3D' && n.mesh) {
      if (!GEO[n.mesh]) { const md = meshes[n.mesh]; for (const s of md.surfaces) { const v = s.v; if (!v || !v.length) continue; const g = new THREE.BufferGeometry(), pos = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { pos[i * 3] = v[i][0]; pos[i * 3 + 1] = v[i][1]; pos[i * 3 + 2] = v[i][2]; } g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); if (s.n) { const nn = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { nn[i * 3] = s.n[i][0]; nn[i * 3 + 1] = s.n[i][1]; nn[i * 3 + 2] = s.n[i][2]; } g.setAttribute('normal', new THREE.BufferAttribute(nn, 3)); } if (s.c) { const c = new Float32Array(v.length * 3); for (let i = 0; i < v.length; i++) { c[i * 3] = s.c[i][0]; c[i * 3 + 1] = s.c[i][1]; c[i * 3 + 2] = s.c[i][2]; } g.setAttribute('color', new THREE.BufferAttribute(c, 3)); } if (s.i && s.i.length) g.setIndex(s.i); GEO[n.mesh] = 1; geoms++; verts += v.length; } }
    } else if (n.class === 'MultiMeshInstance3D' && n.mesh && n.count) {
      const NM = mat4(n.xf), im = new THREE.InstancedMesh(new THREE.BufferGeometry(), new THREE.MeshBasicMaterial(), n.count), t = new THREE.Matrix4();
      for (let i = 0; i < n.count; i++) { t.copy(NM).multiply(mat4(n.xfs[i])); im.setMatrixAt(i, t); if (n.cols) im.setColorAt(i, new THREE.Color().setRGB(n.cols[i][0], n.cols[i][1], n.cols[i][2], THREE.LinearSRGBColorSpace)); } inst += n.count;
    }
  }
  const tBuild = Number(process.hrtime.bigint() - t0) / 1e6;
  out.push({ row: j, KB: Math.round(txt.length / 1024), parseMs: +tParse.toFixed(1), buildMs: +tBuild.toFixed(1), geometries: geoms, verts, instances: inst, nodes: r.nodes.length });
}
console.table(out);
