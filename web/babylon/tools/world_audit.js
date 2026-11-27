// WORLD AUDIT (owner 2026-11-27: "find anything configured in a way that should be impossible, like trees in the sky"). Run with tools/probe.mjs on any world.
// Scans every placed object on the whole course (not only what is on screen) and reports, per material, the pieces that break the world's rules:
//   FLOAT  the object's bottom is more than 6 m above the ground under it (trees, rocks, posts, buildings)   SINK  its top is under the ground
//   ROAD   a solid prop stands on the driving line (within 3 m of the trail, not a pickup/gate/ramp)          HIGH  a pickup is out of reach (more than 14 m up)
// Things that are meant to be in the air are skipped: sky, rings and air rings, beams, signs, labels, the backdrop ring, fx, birds, drones, clouds, skitters.
const G = window.__G, sc = BABYLON.Engine.LastCreatedScene; await new Promise((r) => setTimeout(r, 3500));
const th = (x, z) => { try { const g = G.th(x, z); return Number.isFinite(g) ? g : null; } catch (e) { return null; } }, trailX = G.trailX || ((z) => 0);
const END = window.__END || -7400; const AIR = /drop|accpost|accSign|sky|ring|torus|beam|sign|label|lbl|txt|dosename|fx_|ringskin|tdome|tband|tmtn|bird|drone|cloud|skit|zap|rkt|lock|grid|rain|bolt|puff|halo|lamp|mol|pill|orb|bub|craft|raid|jet|blimp|heli|barge|saucer|fighter|jelly|datacenter|ctl|fps|glass|wire|rail|arch|gate|banner|moon|sun|star|beacon/i;
const PICK = /pick|buff|gem|crystal|tetra|mol|orb|coin|shard|pkmol|pkglow/i, SOLIDOK = /pad|ramp|kick|gate|ring|lane|road|ground|grid|line|mark|dash|veg_grass|flower|grass/i;
const out = {}, add = (kind, key, ex) => { const k = kind + ' ' + key; const o = out[k] || (out[k] = { n: 0, ex: [] }); o.n++; if (o.ex.length < 4) o.ex.push(ex); };
const v = new BABYLON.Vector3(), lo = new BABYLON.Vector3(), hi = new BABYLON.Vector3();
let scanned = 0;
const ownBox = (m) => { const P = m.getVerticesData && m.getVerticesData('position'); if (!P || !P.length) return m.getBoundingInfo().boundingBox; const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9]; for (let i = 0; i < P.length; i += 3) for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], P[i + k]); mx[k] = Math.max(mx[k], P[i + k]); } return { minimum: new BABYLON.Vector3(...mn), maximum: new BABYLON.Vector3(...mx) }; };
for (const m of sc.meshes) {
  if (!m.isEnabled() || !m.isVisible || !m.material) continue; const nm = m.material.name + ' ' + m.name; if (AIR.test(nm) || m.__cat === 'ground' || m.__cat === 'back') continue;
  const bb = ownBox(m),          /* (one object's own box, from its vertices: for instanced meshes the bounding info spans the whole batch) */ n = m.thinInstanceCount || 0, W = m.getWorldMatrix(), buf = n && m._thinInstanceDataStorage && m._thinInstanceDataStorage.matrixData;
  const check = (M) => { BABYLON.Vector3.TransformCoordinatesToRef(bb.minimum, M, lo); BABYLON.Vector3.TransformCoordinatesToRef(bb.maximum, M, hi); const x = (lo.x + hi.x) / 2, z = (lo.z + hi.z) / 2;
    if (Math.abs(x - trailX(z)) > 120 || z < END || z > 40) return; const g = th(x, z); if (g == null) return; scanned++; const bot = Math.min(lo.y, hi.y), top = Math.max(lo.y, hi.y), key = (m.__cat || '') + ':' + m.material.name, ex = [Math.round(x), Math.round(z), Math.round(bot - g)];
    if (PICK.test(nm)) { if (bot - g > 14) add('HIGH', key, ex); return; }
    if (bot - g > 6) add('FLOAT', key, ex); else if (top < g - .5) add('SINK', key, ex);
    else if (Math.abs(x - trailX(z)) < 3 && top - g > 1.2 && !SOLIDOK.test(nm) && m.__cat !== 'veg') add('ROAD', key, ex); };
  if (buf) { const T = new BABYLON.Matrix(); for (let i = 0; i < n; i++) { BABYLON.Matrix.FromArrayToRef(buf, i * 16, T); T.multiplyToRef(W, T); check(T); } } else if (!m.parent || m.__cat) check(W);
}
// pads and boosts must lie on the road: every corner within .8 m of the ground (not hanging over a drop, not poking off a ramp)
for (const m of sc.meshes) { if (!/padbars|setPad/.test(m.name) || !m.isEnabled()) continue; const n = m.thinInstanceCount || 0, W = m.getWorldMatrix(), buf = n && m._thinInstanceDataStorage && m._thinInstanceDataStorage.matrixData, T = new BABYLON.Matrix();
  const pts = [[0, 0, 3.4], [0, 0, -3.4], [1.8, 0, 0], [-1.8, 0, 0]], test = (M) => { const c = BABYLON.Vector3.TransformCoordinates(BABYLON.Vector3.Zero(), M); if (c.y < -1e5 || c.z < END || c.z > 40 || (Math.abs(c.x) < 1e-6 && Math.abs(c.y) < 1e-6)) return; let worst = 0;
    for (const q of pts) { const w = BABYLON.Vector3.TransformCoordinates(new BABYLON.Vector3(q[0], q[1], q[2]), M), g = th(w.x, w.z); if (g != null) worst = Math.max(worst, Math.abs(w.y - g)); } if (worst > .8) add('MISFIT', m.name, [Math.round(c.x), Math.round(c.z), +worst.toFixed(1)]); };
  if (buf) for (let i = 0; i < n; i++) { BABYLON.Matrix.FromArrayToRef(buf, i * 16, T); if (T.m[0] === 0 && T.m[5] === 0) continue; T.multiplyToRef(W, T); test(T); } else test(W); }
const rows = Object.entries(out).sort((a, b) => b[1].n - a[1].n).slice(0, 40).map(([k, o]) => k + ' x' + o.n + ' ' + JSON.stringify(o.ex));
return JSON.stringify({ world: new URLSearchParams(location.search).get('biome'), scanned, problems: rows });
