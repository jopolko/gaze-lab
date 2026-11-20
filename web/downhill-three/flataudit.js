// FLAT-SURFACE AUDIT (dev tool). Teleports the camera to sample points along the course, renders each view twice: once as the player sees the scene (no post pass),
// once as an ID pass (every mesh a unique flat colour). Tiles of the first image with almost no variation are "flat"; the ID pass says which mesh they belong to.
// Run from the page console:  const A = await import('./flataudit.js?' + Date.now()); const r = await A.audit(window.__gv, { samples: 12 }); console.table(r.summary)
import * as THREE from 'three';

const W = 640, H = 360, TILE = 8;

function idMaterial() {
  return new THREE.ShaderMaterial({ uniforms: { uId: { value: new THREE.Vector3() } }, side: THREE.DoubleSide,
    vertexShader: '#include <common>\nvoid main(){ vec3 transformed = position;\n#ifdef USE_INSTANCING\n transformed = (instanceMatrix * vec4(transformed, 1.)).xyz;\n#endif\n gl_Position = projectionMatrix * modelViewMatrix * vec4(transformed, 1.); }',
    fragmentShader: 'uniform vec3 uId; void main(){ gl_FragColor = vec4(uId, 1.); }' });
}

function readTarget(renderer, rt) { const a = new Uint8Array(W * H * 4); renderer.readRenderTargetPixels(rt, 0, 0, W, H, a); return a; }

export async function audit(g, opt = {}) {
  const { scene, camera, renderer } = g, n = opt.samples || 12;
  const rows = g.lvl.rows ? Object.keys(g.lvl.rows).map(Number).sort((a, b) => a - b) : [];
  const last = rows.length ? rows[rows.length - 1] : 16;
  const meshes = []; scene.traverse((o) => { if (o.isMesh && o.visible) meshes.push(o); });
  const rt = new THREE.WebGLRenderTarget(W, H, { type: THREE.UnsignedByteType }); const idm = idMaterial();
  const saved = { z: g.PH.z, x: g.PH.x, y: g.PH.y }, cam0 = camera.aspect, results = [];
  g.setPause(true); camera.aspect = W / H; camera.updateProjectionMatrix();
  for (let s = 0; s < n; s++) {
    const row = Math.min(last, Math.round((s + .5) * (last + 1) / n)), z = -(row * 180 + 90), x = 0;
    g.PH.z = z; g.PH.x = x; g.PH.prevZ = z; g.PH.vx = 0; g.PH.vz = -5; g.st.z = z;
    g.setPause(false); let gy = null; for (let k = 0; k < 30; k++) { await new Promise((r) => setTimeout(r, 150)); gy = g.groundY(g.PH.x, g.PH.z); if (gy !== null && gy !== undefined && k > 4) break; }          // let the game stream the rows, build what it needs and place its camera
    g.setPause(true); if (gy === null || gy === undefined) { results.push({ row, skipped: 'no ground loaded here' }); continue; }
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    const prevTarget = renderer.getRenderTarget(); renderer.setRenderTarget(rt); renderer.render(scene, camera); const img = readTarget(renderer, rt);
    const mats = meshes.map((m) => m.material); meshes.forEach((m, i) => { const id = i + 1; const mm = idm.clone(); mm.uniforms.uId = { value: new THREE.Vector3(((id >> 0) & 255) / 255, ((id >> 8) & 255) / 255, ((id >> 16) & 255) / 255) }; m.material = mm; });
    renderer.render(scene, camera); const ids = readTarget(renderer, rt); meshes.forEach((m, i) => { m.material.dispose(); m.material = mats[i]; }); renderer.setRenderTarget(prevTarget);
    // per tile: luminance spread in the beauty image, and the mesh that owns most pixels of the tile
    const tw = W / TILE, th = H / TILE; let flat = 0; const byMesh = new Map();
    for (let ty = 0; ty < th; ty++) for (let tx = 0; tx < tw; tx++) {
      let mn = 1e9, mx = -1e9, sum = 0, sum2 = 0, cnt = 0, cmn = [255, 255, 255], cmx = [0, 0, 0]; const votes = new Map();
      for (let yy = 0; yy < TILE; yy++) for (let xx = 0; xx < TILE; xx++) { const p = ((ty * TILE + yy) * W + tx * TILE + xx) * 4, l = .299 * img[p] + .587 * img[p + 1] + .114 * img[p + 2]; if (l < mn) mn = l; if (l > mx) mx = l; sum += l; sum2 += l * l; cnt++; for (let c = 0; c < 3; c++) { if (img[p + c] < cmn[c]) cmn[c] = img[p + c]; if (img[p + c] > cmx[c]) cmx[c] = img[p + c]; } const id = ids[p] + (ids[p + 1] << 8) + (ids[p + 2] << 16); votes.set(id, (votes.get(id) || 0) + 1); }
      const mean = sum / cnt, sd = Math.sqrt(Math.max(0, sum2 / cnt - mean * mean)), rng = Math.max(cmx[0] - cmn[0], cmx[1] - cmn[1], cmx[2] - cmn[2]);
      let own = 0, best = 0; for (const [id, v] of votes) if (v > best) { best = v; own = id; }
      if (mean < 6) continue;          // black: not a flat fill, nothing is drawn there
      if (sd < 1.6 && rng < 10) { flat++; byMesh.set(own, (byMesh.get(own) || 0) + 1); }
    }
    const tot = tw * th, list = [...byMesh.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([id, c]) => { const m = meshes[id - 1]; if (!m) return { id, tiles: c, what: 'background' }; const geo = m.geometry, key = m.material.customProgramCacheKey ? String(m.material.customProgramCacheKey()).slice(0, 36) : ''; return { tiles: c, pct: +(100 * c / tot).toFixed(1), verts: geo.attributes.position.count, type: m.material.type, key, inst: m.isInstancedMesh ? m.count : 0, name: m.name || '', size: (geo.computeBoundingBox(), [geo.boundingBox.max.x - geo.boundingBox.min.x, geo.boundingBox.max.y - geo.boundingBox.min.y].map((v) => v.toFixed(0)).join('x')), frag: m.material.fragmentShader ? m.material.fragmentShader.slice(0, 60).replace(/\s+/g, ' ') : '' }; });
    results.push({ row, zone: g.lvl.rows && g.lvl.rows[String(row)] ? g.lvl.rows[String(row)].zone : '', flatPct: +(100 * flat / tot).toFixed(1), worst: list });
  }
  camera.aspect = cam0; camera.updateProjectionMatrix(); g.PH.z = saved.z; g.PH.x = saved.x; g.PH.y = saved.y; rt.dispose(); idm.dispose();
  const ok = results.filter((r) => !r.skipped), avg = ok.length ? ok.reduce((a, r) => a + r.flatPct, 0) / ok.length : 0;
  return { average: +avg.toFixed(1), summary: results.map((r) => r.skipped ? { row: r.row, skipped: r.skipped } : { row: r.row, zone: r.zone, flatPct: r.flatPct, top: r.worst.map((w) => (w.pct || '') + '% ' + (w.verts || '') + 'v ' + (w.key || w.type || w.what)).join(' | ') }), results };
}
