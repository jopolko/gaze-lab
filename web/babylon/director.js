/* THE DIRECTOR: every level is made from a seed, random but always shaped. Two parts.

   ROAD DIRECTOR (planRoad): picks 180 m sections out of the road bank (data/bank: courses Godot generated and baked) and stitches them into the level's road.
     Each level has a personality: a slope curve (where the dives, breathers and fast stretches fall) and a taste for ramps. A section is only allowed next to
     another if their ground meets cleanly (trip_compose.mjs joinCost: the largest height step across the road after the join), and no section is used twice.

   PLAY DIRECTOR (planPlay): writes the level's script from the same seed. Rules, not a fixed order:
     - a pacing curve: warm-up, rising pressure with breathers between, the hardest set pieces late, the finale last;
     - LOCK AND KEY: early on, a FORK puts two keys on the road, one each side (say Air Rights left, a magnet right). You can take one. Later the road holds a
       gate for each key: your choice opens one, the other becomes a loose end (it comes back as a second chance later, see chains.js);
     - a third gate late, its key placed somewhere before it (sometimes off the line, a detour you have to choose);
     - set pieces by tier (harder ones unlock in later levels), never the same one twice in a level;
     - one TUNNEL on the road's straightest, gentlest stretch near the middle (the Dimmers live there; raids keep clear of it).
   Both parts take the seed only: the same seed gives the same level every time. */

export const rng = (seed) => { let a = (seed >>> 0) || 1; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
export const seedOf = (s) => { let h = 2166136261; for (const c of String(s)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };

/* each world's road: a slope curve over the level (0..1 along it -> target slope rank 0 flat .. 1 steepest) and how much it likes ramps and toys */
const ROADP = {
  alpine: { curve: [[0, .25], [.15, .55], [.3, .85], [.42, .3], [.55, .75], [.7, .95], [.82, .35], [1, .8]], ramps: .6 },          // big dives
  candy: { curve: [[0, .3], [.2, .5], [.35, .4], [.5, .6], [.65, .45], [.8, .7], [1, .6]], ramps: 1 },                               // rolling, toy-rich
  desert: { curve: [[0, .3], [.25, .7], [.45, .4], [.7, .8], [1, .6]], ramps: .7 },
  tunnel: { curve: [[0, .25], [.3, .4], [.45, .25], [.6, .6], [.8, .45], [1, .7]], ramps: .5 },                                    // flatter, darker
  synthwave: { curve: [[0, .5], [.2, .7], [.4, .55], [.6, .85], [.8, .65], [1, .9]], ramps: .8 },                                 // fast and flowing
  matrix: { curve: [[0, .3], [.12, .8], [.22, .25], [.34, .85], [.46, .25], [.6, .9], [.72, .3], [.86, .95], [1, .5]], ramps: .7 }, // steps
  egypt: { curve: [[0, .3], [.3, .9], [.45, .5], [.75, .95], [1, .55]], ramps: .5 },                                              // long dives
  psychedelic: { curve: [[0, .4], [.15, .7], [.3, .5], [.45, .85], [.6, .4], [.75, .95], [.9, .7], [1, 1]], ramps: 1 },
};
const curveAt = (C, u) => { for (let i = 1; i < C.length; i++) if (u <= C[i][0]) { const [a, va] = C[i - 1], [b, vb] = C[i], t = (u - a) / Math.max(1e-6, b - a); return va + (vb - va) * t * t * (3 - 2 * t); } return C[C.length - 1][1]; };
const ranks = (vals) => { const idx = vals.map((v, i) => i).sort((a, b) => vals[a] - vals[b]), r = new Array(vals.length); idx.forEach((i, k) => (r[i] = k / Math.max(1, vals.length - 1))); return r; };

/* catalog: data/row_catalog.json; edge(d, j): data/trip_edges.json entry; joinCost: trip_compose.mjs. Returns [{ d: 'long_s11', j }], n long. */
export function planRoad({ catalog, edge, joinCost, seed, n, world, courses }) {
  const R = rng(seed ^ 0x51ed), P = ROADP[world] || ROADP.alpine, sr = ranks(catalog.map((c) => c.slope)), rich = ranks(catalog.map((c) => c.kick * 3 + c.vx * 2 + c.toys + c.feats * .3));
  let rows = catalog.map((c, k) => Object.assign({}, c, { k, sr: sr[k], rich: rich[k], d: 'long_' + c.d })), used = new Set(), plan = [], per = {}; let prev = null; const memo = new Map();
  /* each level builds from a handful of courses (6), all of one family (courses of one generator setup join cleanly; the first four and the 2026-11-26 bake do not join each other): a level downloads only those courses' meshes; other levels and seeds pick other courses */
  { const fam = (d) => /^long_s1\d\d$/.test(d) ? 'b2' : 'b1', all = [...new Set(rows.map((r) => r.d))], f = fam(all[Math.floor(R() * all.length)]), mine = all.filter((d) => fam(d) === f).sort(() => R() - .5).slice(0, courses || 6), keepSet = new Set(mine); for (let i = rows.length - 1; i >= 0; i--) if (!keepSet.has(rows[i].d)) rows.splice(i, 1); }
  const jc = (a, b) => { const key = a.k * 100000 + b.k; let v = memo.get(key); if (v === undefined) { v = joinCost(edge(a.d, a.j), edge(b.d, b.j)); memo.set(key, v); } return v; };
  for (let v = 0; v < n; v++) {
    const u = v / Math.max(1, n - 1), want = curveAt(P.curve, u); let pick = null;
    for (const lim of [.35, .6, 1.2, 99]) {
      const cand = [];
      for (const r of rows) { if (used.has(r.k)) continue; if (v === 0 ? r.j !== 0 : (r.j === 0 || r.j >= 61)) continue; if (prev && jc(prev, r) >= lim) continue;
        const sc = v === 0 ? R() : -Math.abs(r.sr - want) * 3 + P.ramps * r.rich * .6 + (prev && r.d === prev.d && r.j === prev.j + 1 ? .25 : 0) - .06 * (per[r.d] || 0) + R() * .5;          /* (the first section: any course's start; after that, a course used a lot gives way to fresh ones) */          // (a section's own next one joins perfectly: a small pull to keep runs of Godot's own flow)
        cand.push([sc, r]); }
      if (cand.length) { cand.sort((a, b) => b[0] - a[0]); pick = cand[Math.floor(R() * Math.min(3, cand.length))][1]; break; }
    }
    if (!pick) break; used.add(pick.k); per[pick.d] = (per[pick.d] || 0) + 1; plan.push({ d: pick.d, j: pick.j }); prev = pick;
  }
  return plan;
}

/* the straightest, gentlest 460 m near the middle of the road: [z0, z1] (z0 > z1), or null. trailX(z) and pitch slope come from the composed road. */
export function findTunnel({ trailX, slopeAt, end, len = 460 }) {
  let best = null; const L = -end;
  for (let s = L * .38; s <= L * .66; s += 30) { let curv = 0, prevD = null, sl = 0;
    for (let k = 0; k <= len; k += 20) { const z = -(s + k), d = trailX(z - 10) - trailX(z + 10); if (prevD !== null) curv += Math.abs(d - prevD); prevD = d; sl += Math.abs(slopeAt(z)); }
    const sc = curv * 3 + sl * .5; if (!best || sc < best.sc) best = { sc, z0: -s, z1: -(s + len) }; }
  return best ? [best.z0, best.z1] : null;
}

/* the gates and the set piece that tests each */
export const GATESET = { WINGS: 'wingspan', MAGNET: 'magnetline', SHIELD: 'shieldrun', LENS: 'ghostrail', SPEED: 'speedtrap', BULL: 'bullwall', ROCKETS: 'lockbox', RUSH: 'rushgate' };
const GATETIER = { SPEED: 1, WINGS: 1, MAGNET: 2, LENS: 2, BULL: 3, ROCKETS: 3, RUSH: 4, SHIELD: 4 };
const KEYABLE = ['WINGS', 'MAGNET', 'SHIELD', 'SPEED', 'LENS'];          // keys that can lie on the road (gear gates take RUSH, which you charge)

/* the level's script: an ordered list of beats the game's level script builds one after another.
   kinds: warm, speed, threat, breath, mix, pressure, lensbreath, gearpair, finale (the game's own sections), set {id}, fork {a, b}, key {need} */
export function planPlay({ seed, lvIdx, setTiers, plainSets, hardSets }) {
  const R = rng(seed ^ 0xd1ec), pick = (a) => a[Math.floor(R() * a.length)], usedSets = new Set();
  const setOf = (pool) => { const free = pool.filter((id) => !usedSets.has(id) && (setTiers[id] ?? 0) <= lvIdx); const id = free.length ? pick(free) : pick(pool); usedSets.add(id); return { k: 'set', id }; };
  const keys = KEYABLE.filter((n) => (GATETIER[n] || 0) <= Math.max(1, lvIdx)), shuffled = keys.slice().sort(() => R() - .5);
  const [ka, kb] = shuffled.length >= 2 ? shuffled : ['SPEED', 'WINGS'];
  const late = Object.keys(GATESET).filter((n) => n !== ka && n !== kb && (GATETIER[n] || 0) <= Math.max(1, lvIdx)); const kc = late.length ? pick(late) : null;
  const S = [];
  S.push({ k: 'warm' });
  S.push(setOf(plainSets));
  S.push({ k: R() < .5 ? 'speed' : 'threat' });
  S.push({ k: 'fork', a: ka, b: kb });                                   // the choice
  S.push({ k: 'set', id: GATESET[R() < .5 ? ka : kb], gate: true });    // the first of its two gates comes soon
  S.push({ k: 'breath' });
  S.push({ k: R() < .5 ? 'mix' : 'threat' });
  S.push(setOf(lvIdx >= 2 && R() < .5 ? ['remix'] : plainSets));
  S.push({ k: 'pressure' });
  const first = S.find((b) => b.gate).id, second = GATESET[first === GATESET[ka] ? kb : ka]; S.push({ k: 'set', id: second, gate: true });   // and the other gate: the key you left behind
  S.push({ k: 'lensbreath' });
  if (kc) { if (KEYABLE.includes(kc) && R() < .7) S.push({ k: 'key', need: kc, side: R() < .5 ? -1 : 1 }); S.push(setOf(hardSets)); S.push({ k: 'set', id: GATESET[kc], gate: true }); }
  else S.push(setOf(hardSets));
  S.push({ k: 'gearpair' });
  S.push(setOf(hardSets.concat(lvIdx >= 2 ? ['remix'] : [])));
  S.push({ k: 'finale' });
  return { beats: S, keys: [ka, kb], late: kc };
}
