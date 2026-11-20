// MOLMESH: the six molecules exactly as the Godot game builds, lights and draws them. Every number comes from godot/scripts (line numbers are RunRig.gd unless named).
//
//   geometry   _mol_mesh (9726-9786): one ball-and-stick mesh per molecule, colours in the vertices. Coordinates (MolData, already centred, long axis on x) x 0.3.
//              Atoms are Godot SphereMesh(radius 1, height 2, radial_segments 8, rings 4) scaled by MOL_EL_R x 0.3, with the sphere's own smooth normals, drawn un-indexed.
//              Sticks are CylinderMesh(top 1, bottom 1, height 1, radial_segments 6, rings 1, no caps); a single bond r = 0.17 x 0.3, a double bond is TWO sticks r = 0.10 x 0.3
//              offset +-0.15 x 0.3 along (bond direction x Z). Stick colour (0.86, 0.88, 0.95). Carbon takes the molecule's own colour (MolData 'c').
//   material   _mol_material (9711-9721): StandardMaterial3D, vertex colour as albedo, roughness 0.45, emission (0.22, 0.22, 0.26), rim 0.55, rim_tint 0.35, metallic_specular 0.7.
//              Godot's rim is a per-light term in the lighting loop (scene_forward_lights): rim_light = pow(1 - N.V, (1 - roughness) * 16) = pow(.., 8.8);
//              diffuse += rim_light * rim * mix(vec3(1), albedo, rim_tint) * light_color / PI.   It is NOT an emission term.
//   world      _make_pills (9658-9684) and _toys_tick (10238-10245): the pill is a Node3D "hold" at terrain + 2.2, scale 1.6, holding a "spin" node (rotation (0.5, 0, 0.3), YXZ order)
//              that is turned with rotate_y(2.4 * dt) (a rotation about the PARENT's Y, i.e. Ry(angle) * tilt), bobbing y = base + 0.25 * sin(age * 2.8 + x); a billboard additive "halo"
//              quad 5.0 (x1.6 = 8 m) in the molecule's colour at alpha 0.6 with the radial glow texture; and a "beacon" (_beacon 9419): a tall thin additive cylinder
//              (top r 0.1, bottom r 0.16, height 9, 6 segments, alpha 0.32) centred 4.6 above the snow. Eaten within 3 m (dx^2 + dz^2 < 9) and |dy| < 4.5.
//   HUD        _draw_mol_bar (12330-12430) and _mol_hud_get (12320-12345): six slots along the top, each a circle with the molecule turning in it (heavy atoms only), its name and its perk.
//
// API:  buildMolGeometry(THREE, id)  moleculeMaterial(THREE)  applyMolRim(THREE, material)  pillTransform(THREE, matrix, x, groundY, z, age, spin)  drawMolIcon(ctx, id, t, size, opts)  drawMolBar(ctx, W, state, opts)
import { MOLS, MOL_ORDER } from './molecules.js';

export { MOL_ORDER };
export const MOL_EL_COL = { H: [0.95, 0.95, 1.0], O: [1.0, 0.22, 0.2], N: [0.25, 0.42, 1.0], S: [1.0, 0.9, 0.2], Br: [0.70, 0.25, 0.15] };          // 9707
export const MOL_EL_R = { H: 0.36, C: 0.62, O: 0.60, N: 0.62, S: 0.82, Br: 0.92 };          // 9708
export const MOL_EL_HUD = { N: [0.45, 0.6, 1.0], O: [1.0, 0.4, 0.35], S: [1.0, 0.92, 0.3], Br: [0.85, 0.45, 0.25] };          // 12309
export const MOL_PERK = ['GLINTS', 'POINTS', 'BOOST', 'RAMPS', 'SLING', 'SPEED'];          // 12308
export const MOL_SC = 0.3;          // 9731: the mesh is the Angstrom coordinates times 0.3
export const MOL_STICK = [0.86, 0.88, 0.95];          // 9760
// the world values of a pill (9658-9684, 10238-10245)
export const PILL = { hold_scale: 1.6, y_above_snow: 2.2, tilt: [0.5, 0, 0.3], tilt_order: 'YXZ', spin_rate: 2.4, bob_amp: 0.25, bob_rate: 2.8, halo_size: 5.0, halo_alpha: 0.6, eat_r2: 9.0, eat_dy: 4.5, beacon: { top_r: 0.1, bottom_r: 0.16, height: 9.0, segments: 6, alpha: 0.32, above_snow: 4.6 } };
export const GLOW_TEX = { stops: [[0, 1.0], [0.3, 0.4], [1.0, 0.0]], size: 128 };          // _glow_texture (3604): a radial gradient, white, alpha 1 -> .4 at .3 -> 0

// ---- Godot's SphereMesh (radius 1, height 2) and CylinderMesh vertex layouts, un-indexed, with their own smooth normals
function godotSphere(rings, radial) {
  const P = [], N = [], I = []; let prev = 0, thisr = 0, point = 0;
  for (let j = 0; j <= rings + 1; j++) {
    const v = j / (rings + 1), w = Math.sin(Math.PI * v), y = Math.cos(Math.PI * v);
    for (let i = 0; i <= radial; i++) {
      const u = i / radial, x = Math.sin(u * Math.PI * 2), z = Math.cos(u * Math.PI * 2);
      P.push([x * w, y, z * w]); const n = [x * w, y, z * w], l = Math.hypot(n[0], n[1], n[2]) || 1; N.push([n[0] / l, n[1] / l, n[2] / l]); point++;
      if (i > 0 && j > 0) { I.push(prev + i - 1, prev + i, thisr + i - 1, prev + i, thisr + i, thisr + i - 1); }
    }
    prev = thisr; thisr = point;
  }
  return { P, N, I };
}
function godotCylinder(rings, radial) {          // top r = bottom r = 1, height 1, open ends
  const P = [], N = [], I = []; let prev = 0, thisr = 0, point = 0;
  for (let j = 0; j <= rings + 1; j++) {
    const v = j / (rings + 1), y = 0.5 - v;
    for (let i = 0; i <= radial; i++) {
      const u = i / radial, x = Math.sin(u * Math.PI * 2), z = Math.cos(u * Math.PI * 2);
      P.push([x, y, z]); N.push([x, 0, z]); point++;
      if (i > 0 && j > 0) { I.push(prev + i - 1, prev + i, thisr + i - 1, prev + i, thisr + i, thisr + i - 1); }
    }
    prev = thisr; thisr = point;
  }
  return { P, N, I };
}
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]], cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
// Godot's front faces wind clockwise and three's counter-clockwise: the index order of a primitive is flipped when its first triangle faces inward
function outward(prim) {
  const { P, N, I } = prim; const a = P[I[0]], b = P[I[1]], c = P[I[2]], fn = cross(sub(b, a), sub(c, a)), vn = N[I[0]]; return fn[0] * vn[0] + fn[1] * vn[1] + fn[2] * vn[2] > 0;
}

const CACHE = {};
export function buildMolGeometry(THREE, id) {
  if (CACHE[id]) return CACHE[id];
  const md = MOLS[id], sc = MOL_SC, accent = md.c, ball = godotSphere(4, 8), rod = godotCylinder(1, 6), bFlip = !outward(ball), rFlip = !outward(rod);
  const pos = [], nor = [], col = [];
  const tri = (prim, flip, k0, k1, k2, fp, fn, c) => { const order = flip ? [k0, k2, k1] : [k0, k1, k2]; for (const k of order) { const p = fp(prim.P[k]), n = fn(prim.N[k]); pos.push(p[0], p[1], p[2]); nor.push(n[0], n[1], n[2]); col.push(c[0], c[1], c[2]); } };
  const pts = [];
  for (const a of md.atoms) {          // atoms: Godot adds every index of the sphere's index array as its own vertex (un-indexed triangles)
    const el = a[0], c = [a[1] * sc, a[2] * sc, a[3] * sc], color = el === 'C' ? accent : MOL_EL_COL[el], r = MOL_EL_R[el] * sc; pts.push(c);
    for (let t = 0; t < ball.I.length; t += 3) tri(ball, bFlip, ball.I[t], ball.I[t + 1], ball.I[t + 2], (p) => [c[0] + p[0] * r, c[1] + p[1] * r, c[2] + p[2] * r], (n) => n, color);
  }
  for (const bd of md.bonds) {
    const p0 = pts[bd[0]], p1 = pts[bd[1]], d = sub(p1, p0), blen = Math.hypot(d[0], d[1], d[2]), up = [d[0] / blen, d[1] / blen, d[2] / blen];
    const ref = Math.abs(up[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0], xa = norm(cross(up, ref)), za = cross(xa, up);          // Basis(xa, up, xa x up)
    const toWorld = (v) => [xa[0] * v[0] + up[0] * v[1] + za[0] * v[2], xa[1] * v[0] + up[1] * v[1] + za[1] * v[2], xa[2] * v[0] + up[2] * v[1] + za[2] * v[2]];
    let offs = [[0, 0, 0]], br = 0.17 * sc;
    if (bd[2] === 2) { const o = norm(cross(up, [0, 0, 1])).map((x) => x * 0.15 * sc); offs = [o, [-o[0], -o[1], -o[2]]]; br = 0.10 * sc; }
    const mid = [(p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2];
    for (const off of offs) for (let t = 0; t < rod.I.length; t += 3) tri(rod, rFlip, rod.I[t], rod.I[t + 1], rod.I[t + 2],
      (p) => { const w = toWorld([p[0] * br, p[1] * blen, p[2] * br]); return [mid[0] + off[0] + w[0], mid[1] + off[1] + w[1], mid[2] + off[2] + w[2]]; }, (n) => norm(toWorld(n)), MOL_STICK);
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeBoundingSphere(); return (CACHE[id] = g);
}

// ---- the material. Rim is Godot's per-light term (see the header); the injected GLSL starts on its own line so it can never land after an #endif
export function applyMolRim(THREE, m) {
  m.onBeforeCompile = (sh) => {
    const NL = String.fromCharCode(10);
    sh.fragmentShader = sh.fragmentShader.replace('#include <lights_fragment_end>', '#include <lights_fragment_end>' + NL
      + '#if NUM_DIR_LIGHTS > 0' + NL + '{ float rimNV = clamp(dot(normal, normalize(vViewPosition)), 0., 1.); float rimL = pow(1. - rimNV, 8.8); vec3 rimT = mix(vec3(1.), diffuseColor.rgb, .35);' + NL
      + 'for (int ri = 0; ri < NUM_DIR_LIGHTS; ri++) reflectedLight.directDiffuse += rimL * .55 * rimT * directionalLights[ri].color / 3.14159265; }' + NL + '#endif' + NL);
  };
  m.customProgramCacheKey = () => 'molrim';
  return m;
}
export function moleculeMaterial(THREE) {
  const emi = new THREE.Color().setRGB(0.22, 0.22, 0.26, THREE.SRGBColorSpace);
  const m = new THREE.MeshPhysicalMaterial({ vertexColors: true, roughness: 0.45, metalness: 0, emissive: emi, specularIntensity: 0.7 / 0.5 });          // Godot specular 0.7 against its default 0.5 (three's default 1.0 = 0.5)
  return applyMolRim(THREE, m);
}

// ---- a pill's transform: position (x, snow + 2.2 + bob), rotation Ry(spin) * Euler(0.5, 0, 0.3, 'YXZ'), scale 1.6. `spin` is the accumulated angle (add 2.4 * dt each frame).
export function pillTransform(THREE, out, x, groundY, z, age, spin) {
  const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(PILL.tilt[0], PILL.tilt[1], PILL.tilt[2], PILL.tilt_order)), qy = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), spin);
  q.premultiply(qy);
  return out.compose(new THREE.Vector3(x, groundY + PILL.y_above_snow + PILL.bob_amp * Math.sin(age * PILL.bob_rate + x), z), q, new THREE.Vector3(PILL.hold_scale, PILL.hold_scale, PILL.hold_scale));
}

// ---- the HUD molecule (_mol_hud_get, _draw_mol_bar)
const HUD = {};
function hudGet(id) {
  if (HUD[id]) return HUD[id];
  const md = MOLS[id], idx = {}, pts = [], els = []; let ext = 1;
  md.atoms.forEach((a, i) => { if (a[0] === 'H') return; idx[i] = pts.length; const p = [a[1], a[2], a[3]]; pts.push(p); els.push(a[0]); ext = Math.max(ext, Math.max(Math.hypot(p[0], p[2]), Math.abs(p[1]))); });
  const bonds = md.bonds.filter((b) => idx[b[0]] !== undefined && idx[b[1]] !== undefined).map((b) => [idx[b[0]], idx[b[1]]]);
  return (HUD[id] = { pts, els, bonds, ext });
}
const css = (c, a = 1) => 'rgba(' + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255)).join(',') + ',' + a + ')';
const light = (c, k) => c.map((v) => v + (1 - v) * k);
// one molecule turning in a slot centred on (cx, cy) with radius rr (Godot: rr = 30 * k). opts: { got, i, age, k }
export function drawMolIcon(ctx, id, t, rr, opts = {}) {
  const got = opts.got !== false, k = opts.k || 1, i = opts.i || 0, cx = opts.cx !== undefined ? opts.cx : 0, cy = opts.cy !== undefined ? opts.cy : 0, md = hudGet(id), col = MOLS[id].c, sc = rr * 0.82 / md.ext;
  const ang = t * (got ? 1.0 : 0.45) + i * 1.3, ca = Math.cos(ang), sa = Math.sin(ang), sp = [], dp = [];
  for (const p of md.pts) { const px = p[0] * ca + p[2] * sa, pz = -p[0] * sa + p[2] * ca; sp.push([cx + px * sc, cy - (p[1] * 0.95 + pz * 0.28) * sc]); dp.push(pz); }
  const lc = got ? css(light(col, 0.35), 0.95) : css(col, 0.32); ctx.lineCap = 'butt'; ctx.strokeStyle = lc; ctx.lineWidth = (got ? 3.0 : 1.6) * k;
  if (got || opts.outline !== false) for (const b of md.bonds) { ctx.beginPath(); ctx.moveTo(sp[b[0]][0], sp[b[0]][1]); ctx.lineTo(sp[b[1]][0], sp[b[1]][1]); ctx.stroke(); }
  if (got) md.pts.forEach((_, pi) => { const el = md.els[pi], ac = MOL_EL_HUD[el] || light(col, 0.55), ar = (el === 'C' ? 3.8 : (el === 'S' || el === 'Br' ? 5.0 : 4.4)) * k * (1 + 0.15 * Math.max(-1, Math.min(1, dp[pi] / md.ext))); ctx.fillStyle = css(ac); ctx.beginPath(); ctx.arc(sp[pi][0], sp[pi][1], ar, 0, Math.PI * 2); ctx.fill(); });
}
// the whole bar along the top (_draw_mol_bar). state: { got[6], felt[6] (0..1), held[6] (0..1), pop[6] (0..1, decays 1.4/s), age, hurtI, hurtT }. W = canvas width, opts: { k, m (top margin) }
export function drawMolBar(ctx, W, state, opts = {}) {
  const k = opts.k || 1, m = opts.m !== undefined ? opts.m : 14 * k, gap = 94 * k, r = 30 * k, x0 = W * 0.5 - gap * 2.5, y = m + 46 * k, got = state.got, age = state.age || 0;
  const nGot = got.filter(Boolean).length; let missing = -1; if (nGot === 5) for (let q = 0; q < 6; q++) if (!got[q]) missing = q;
  ctx.font = '700 ' + Math.round(14 * k) + 'px ui-monospace,Consolas,monospace'; ctx.textAlign = 'center';
  for (let i = 0; i < 6; i++) {
    const id = MOL_ORDER[i], col = MOLS[id].c, g = !!got[i], pop = (state.pop && state.pop[i]) || 0, rr = r * (1 + 0.28 * Math.sin(pop * Math.PI)), cx = x0 + gap * i, cy = y;
    const circle = (rad, fill) => { ctx.fillStyle = fill; ctx.beginPath(); ctx.arc(cx, cy, rad, 0, Math.PI * 2); ctx.fill(); };
    if (g) circle(rr * (1.55 + 0.35 * pop), css(col, 0.10 + 0.20 * pop + 0.05 * Math.sin(age * 3 + i)));
    if (i === missing) { ctx.strokeStyle = css([1, 0.85, 0.3], 0.45 + 0.5 * (0.5 + 0.5 * Math.sin(age * 7))); ctx.lineWidth = 4 * k; ctx.beginPath(); ctx.arc(cx, cy, rr + 7 * k, 0, Math.PI * 2); ctx.stroke(); }
    circle(rr + 2 * k, 'rgba(0,0,0,0.6)'); circle(rr, g ? css([col[0] * 0.45, col[1] * 0.45, col[2] * 0.45], 0.95) : 'rgba(13,15,26,0.8)');
    const arc = (frac, c) => { ctx.strokeStyle = c; ctx.lineWidth = 4 * k; ctx.beginPath(); ctx.arc(cx, cy, rr + 4 * k, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); ctx.stroke(); };
    const held = state.held ? state.held[i] : 0, felt = state.felt ? state.felt[i] : 0; if (held > 0.001) arc(held, css(col, 0.4)); if (felt > 0.001) arc(felt, css(light(col, 0.25)));
    if (state.hurtT > 0 && state.hurtI === i) circle(rr + 6 * k, 'rgba(255,51,51,' + (0.6 * state.hurtT) + ')');
    drawMolIcon(ctx, id, age, rr, { got: g, i, k, cx, cy });
    ctx.fillStyle = css(light(col, 0.25), g ? 1 : 0.55); ctx.font = '700 ' + Math.round(14 * k) + 'px ui-monospace,Consolas,monospace'; ctx.fillText(MOLS[id].name.toUpperCase(), cx, cy + rr + 22 * k);
    ctx.fillStyle = 'rgba(255,255,255,' + (g ? 0.7 : 0.3) + ')'; ctx.font = '700 ' + Math.round(10 * k) + 'px ui-monospace,Consolas,monospace'; ctx.fillText(MOL_PERK[i], cx, cy + rr + 36 * k);
  }
  const ty = y + r + 56 * k; ctx.textAlign = 'center';
  if (state.dmtOn) { ctx.fillStyle = 'rgba(255,217,77,' + (0.7 + 0.3 * Math.sin(age * 6)) + ')'; ctx.font = '700 ' + Math.round(18 * k) + 'px ui-monospace,Consolas,monospace'; ctx.fillText('ALL SIX', W * 0.5, ty); }
  else if (nGot === 5) { ctx.fillStyle = 'rgba(255,217,77,' + (0.75 + 0.25 * Math.sin(age * 7)) + ')'; ctx.font = '700 ' + Math.round(22 * k) + 'px ui-monospace,Consolas,monospace'; ctx.fillText('ONE MORE!', W * 0.5, ty); }
  else if (nGot > 0) { ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.font = '700 ' + Math.round(14 * k) + 'px ui-monospace,Consolas,monospace'; ctx.fillText(nGot + ' OF 6', W * 0.5, ty); }
}
