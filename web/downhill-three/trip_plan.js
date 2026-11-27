// TRIP PLANNER (preview, 2026-11-22): composes one long trip out of the rows of the existing Godot dumps ("your elements, my layout").
// Input: the row catalog (data/row_catalog.json: for every 180 m row of the four 63-row dumps its grade, pickups, toys, kickers, rings, molecule orbs).
// Output: for every biome in the current order, a list of rows picked by role so each biome is a shaped ten-minute (or any length) run with calm, build, set pieces, a big dive and a run-out.
// The total trip length is the only input that matters: each biome gets total / 7.
export const BIOMES = ['alpine', 'candy', 'desert', 'tunnel', 'matrix', 'synthwave', 'psychedelic'];
export const ROW_M = 180, SPEED = 50;                       // metres per row; typical m/s on the slope (7.7 km takes about 3.4 min in the spec)
// every biome has its own arc (its personality); the same move names, different order, length and heat
const M = (f, name, i0, i1, g, chain) => ({ f, name, i: [i0, i1], g, chain });
export const ARCS = {
  alpine: [M(.12, 'LAUNCH', .3, .4, .9), M(.28, 'FLOW', .4, .6, .45), M(.10, 'BREATHER', .1, .2, .1), M(.18, 'CLIMB', .5, .8, .5), M(.08, 'SET PIECE', .95, .95, .5, 1), M(.14, 'THE DIVE', .6, .75, 1), M(.10, 'RUN-OUT', .4, .2, .3)],
  candy: [M(.06, 'LAUNCH', .5, .5, .8), M(.10, 'SET PIECE', .95, .95, .5, 1), M(.08, 'BREATHER', .2, .2, .2), M(.10, 'SET PIECE 2', .95, .95, .6, 1), M(.08, 'BREATHER', .2, .2, .15), M(.14, 'CLIMB', .6, .85, .5), M(.10, 'SET PIECE', .95, .95, .5, 1), M(.12, 'THE DIVE', .7, .8, 1), M(.12, 'FLOW', .5, .5, .5), M(.10, 'RUN-OUT', .4, .25, .3)],
  desert: [M(.08, 'LAUNCH', .3, .35, .95), M(.30, 'THE DIVE', .45, .6, 1), M(.12, 'BREATHER', .1, .15, .1), M(.20, 'FLOW', .5, .7, .7), M(.10, 'SET PIECE', .95, .95, .6, 1), M(.12, 'THE DIVE', .6, .7, 1), M(.08, 'RUN-OUT', .35, .2, .3)],
  tunnel: [M(.10, 'LAUNCH', .4, .5, .7), M(.18, 'FLOW', .5, .6, .5), M(.12, 'SET PIECE', .95, .95, .5, 1), M(.18, 'CLIMB', .6, .85, .55), M(.10, 'BREATHER', .15, .15, .1), M(.14, 'SET PIECE 2', .95, .95, .6, 1), M(.10, 'THE DIVE', .7, .8, 1), M(.08, 'RUN-OUT', .4, .2, .3)],
  matrix: [M(.07, 'LAUNCH', .4, .4, .85), M(.07, 'CLIMB', .6, .8, .5), M(.05, 'BREATHER', .15, .15, .1), M(.08, 'CLIMB', .7, .9, .55), M(.05, 'BREATHER', .15, .15, .1), M(.12, 'SET PIECE', .95, .95, .5, 1), M(.06, 'BREATHER', .15, .15, .1), M(.14, 'CLIMB', .75, .95, .6), M(.14, 'THE DIVE', .8, .8, 1), M(.12, 'SET PIECE 2', .95, .95, .6, 1), M(.10, 'RUN-OUT', .4, .2, .3)],
  synthwave: [M(.20, 'FLOW', .35, .5, .6), M(.10, 'BREATHER', .1, .15, .1), M(.20, 'CLIMB', .5, .8, .6), M(.10, 'THE DIVE', .6, .7, 1), M(.15, 'SET PIECE', .95, .95, .6, 1), M(.15, 'THE DIVE', .8, .9, 1), M(.10, 'RUN-OUT', .5, .3, .4)],
  psychedelic: [M(.06, 'LAUNCH', .4, .5, .9), M(.14, 'FLOW', .5, .7, .6), M(.12, 'SET PIECE', .95, .95, .5, 1), M(.08, 'BREATHER', .15, .15, .1), M(.16, 'CLIMB', .7, .9, .6), M(.12, 'SET PIECE 2', .95, .95, .6, 1), M(.20, 'THE DIVE', .8, .95, 1), M(.12, 'FINALE', .95, .95, .7, 1)],
};

function rng(seed) { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function ranks(vals) { const idx = vals.map((v, i) => i).sort((a, b) => vals[a] - vals[b]), r = new Array(vals.length); idx.forEach((i, k) => (r[i] = k / (vals.length - 1))); return r; }
export function prepare(cat) {
  const raw = cat.map((c) => c.buffs + c.toys * 2 + c.kick * 3 + c.rings * .5 + (c.orbs ? 1.5 : 0) + c.pads * .12);
  const ri = ranks(raw), rg = ranks(cat.map((c) => c.slope));
  return cat.map((c, k) => Object.assign({}, c, { k, inten: ri[k], grade: rg[k], score: raw[k] }));
}
export function planTrip(rows, totalMin, seed = 1, joinOk = null) {          // joinOk(prevRow, candidateRow) -> true when the ground of the candidate meets the end of prev (edge matching)
  const per = totalMin / BIOMES.length, n = Math.max(8, Math.round(per * 60 * SPEED / ROW_M)), plan = [];
  BIOMES.forEach((b, bi) => {
    const R = rng(seed * 977 + bi * 131 + 5), used = new Set(), seq = []; let prev = null;
    let pos = 0; const ARC = ARCS[b], lens = ARC.map((m) => Math.max(1, Math.round(m.f * n * (.9 + R() * .2)))); let tot = lens.reduce((a, c) => a + c, 0); lens[lens.length - 2] += n - tot; if (lens[lens.length - 2] < 1) lens[lens.length - 2] = 1;
    ARC.forEach((m, mi) => {
      for (let q = 0; q < lens[mi]; q++, pos++) {
        const u = lens[mi] > 1 ? q / (lens[mi] - 1) : 0, ti = m.i[0] + (m.i[1] - m.i[0]) * u, tg = m.g;
        const cand = []; for (const r of rows) { if (used.has(r.k)) continue; if (pos > 0 && (r.j === 0 || r.j >= 61)) continue; if (pos === 0 ? r.j !== 0 : (joinOk && prev && !joinOk(prev, r))) continue; let sc = -Math.abs(r.inten - ti) * 2 - Math.abs(r.grade - tg) * 1.1 + R() * .5; if (m.chain && r.kick) sc += .6; if (prev && prev.d === r.d && Math.abs(prev.j - r.j) === 1) sc += .25; cand.push([sc, r]); }
        cand.sort((a, b) => b[0] - a[0]); const pick = cand[Math.floor(R() * Math.min(4, cand.length))][1];
        used.add(pick.k); prev = pick; seq.push({ k: pick.k, d: pick.d, j: pick.j, role: m.name, inten: pick.inten, slope: pick.slope, kick: pick.kick, toys: pick.toys, orbs: pick.orbs, buffs: pick.buffs });
      }
    });
    plan.push({ biome: b, rows: seq });
  });
  return { totalMin, perBiomeMin: per, rowsPerBiome: n, plan };
}
