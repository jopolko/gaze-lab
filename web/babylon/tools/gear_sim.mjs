// Balance simulator for the four gears (docs: DOWNFALL_STORY_WORLD_BIBLE_V3.md, 6.14).
// Same world for everybody: hazards arrive at a fixed rate and mix. Each gear answers each hazard its own way.
// Skill (0..1) is how well the player steers: it sets dodging (for gears that cannot answer a hazard) and aiming at hazards the gear WANTS to hit.
// Run: node tools/gear_sim.mjs   -> score a minute per gear per skill, and the spread.
const BASE = 40;                // base points a second from the rest of the game (orbs, rings, beat pickups), multiplied by the streak
const HAZ_PER_MIN = 12, MIX = { drone: 1, mine: 1, rock: 1 };
const STUMBLE = 50 + 1.2 * BASE; // a hit: -50, and about 1.2 s of base income lost
const CFG = {
  rocket: { cd: 2.2, pts: { drone: 225, mine: 150 }, step: .25, cap: 3, floor: 1, decay: 9, kill: .9, win: [.8, 3.2] },
  pole: { cd: 3.2, pts: { drone: 300, mine: 400 }, step: .25, cap: 3, floor: 1, decay: 9, kill: .9, win: [1.4, 1.9] },
  shield: { pts: 800, step: .5, cap: 3, floor: 2, decay: 30, div: 40, rech: 15, charges: 3 },
  bull: { pts: { rock: 900, mine: 500 }, step: .75, cap: 3, floor: 1, decay: 14 },
};
function rnd(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }
function run(gear, skill, minutes, seed, cfg) {
  const R = rnd(seed), c = cfg[gear], dt = .1, T = minutes * 60; let t = 0, score = 0, streak = 0, since = 0, cd = 0, sh = c.charges || 0, rech = 0, hits = 0, events = 0;
  const M = () => Math.min(c.cap, c.floor + streak), gain = (p) => { score += p * M(); }, ev = () => { streak += c.step; since = 0; events++; };
  const types = Object.keys(MIX); const H = []; let nextH = 3;
  while (t < T) {
    while (nextH < t + 4) { H.push({ t: nextH, type: types[Math.floor(R() * types.length)], claimed: false }); nextH += -Math.log(1 - R()) * 60 / HAZ_PER_MIN; }
    score += BASE * M() * dt; since += dt; if (since > c.decay) streak = 0;
    if (gear === 'shield') { score += c.div * dt * (sh > 0 ? M() : 0); if (sh < c.charges) { rech += dt; if (rech > c.rech) { rech = 0; sh++; } } }
    cd -= dt;
    if ((gear === 'rocket' || gear === 'pole') && cd <= 0) { const h = H.find((q) => !q.claimed && q.type !== 'rock' && q.t - t > c.win[0] && q.t - t < c.win[1]); if (h) { h.claimed = true; cd = c.cd; h.killAt = t + .8; h.willKill = R() < c.kill; } }
    for (let i = H.length - 1; i >= 0; i--) {
      const h = H[i];
      if (h.claimed && h.willKill && t >= h.killAt && !h.done) { h.done = true; ev(); gain(c.pts[h.type]); }
      if (t >= h.t) {
        H.splice(i, 1); if (h.done) continue; const dodge = R() < skill, aim = R() < .4 + .5 * skill;
        if (gear === 'bull' && h.type !== 'drone') { if (aim) { ev(); gain(c.pts[h.type]); } continue; }
        if (gear === 'shield' && sh > 0) { if (aim) { sh--; rech = 0; ev(); gain(c.pts); } continue; }
        if (dodge) continue;
        score = Math.max(0, score - STUMBLE); streak = 0; hits++;
      }
    }
    t += dt;
  }
  return { perMin: score / minutes, hits: hits / minutes, ev: events / minutes };
}
export function table(cfg = CFG) {
  const out = {}; for (const g of Object.keys(cfg)) { out[g] = {}; for (const s of [.2, .5, .8]) { let a = 0, h = 0, e = 0; const N = 40; for (let k = 0; k < N; k++) { const r = run(g, s, 5, 1000 + k, cfg); a += r.perMin; h += r.hits; e += r.ev; } out[g][s] = { pts: Math.round(a / N), hits: +(h / N).toFixed(1), ev: +(e / N).toFixed(1) }; } }
  return out;
}
if (process.argv[1] && process.argv[1].endsWith('gear_sim.mjs')) {
  const t = table(); console.log('score a minute (hits a minute, gear events a minute)');
  for (const s of [.2, .5, .8]) { const row = Object.keys(t).map((g) => g + ' ' + t[g][s].pts + ' (' + t[g][s].hits + ',' + t[g][s].ev + ')'); const v = Object.keys(t).map((g) => t[g][s].pts); console.log('skill ' + s + ': ' + row.join(' | ') + '   spread ' + Math.round((Math.max(...v) / Math.min(...v) - 1) * 100) + '%'); }
}
