// CHARFX: the Loadout. One killer item per run, picked in the editor, works by itself in the game (no buttons).
// Looks (hats, masks, outfits, paint, stickers) are for fun and carry no stats.
// The gear also nudges two stats the Route Zero prizes read (speed, grip, safety), so each item opens a different prize.
(function () {
  const FXS = { 'gear.rocket': { spd: 3 }, 'gear.pole': { grp: 2 }, 'gear.shield': { safe: 1 }, 'gear.bull': { safe: 2 } };
  // plain words for each item: [what it does, the catch]
  const TXT = {
    'gear.rocket': ['Deletes drones and mines by itself: 700 and 550 pts. Owns the gold drones', 'Cannot touch boulders'],
    'gear.pole': ['Hauls drones and mines. Mines pay 1,400. Owns the cargo crates', 'Cannot touch boulders'],
    'gear.shield': ['Soaks 3 hits of anything, 550 pts each. Points x1.5 or more. Owns the rock chest', 'Slow recharge'],
    'gear.bull': ['Ploughs boulders and mines: 850 and 750 pts. Owns the rock chest', 'Drones still hit you']
  };

  const SLOTS = ['gear'];
  function stats(ch) { const v = { spd: 5, grp: 5, air: 5, safe: 5 }; for (const s of SLOTS) { const f = ch && FXS[s + '.' + ch[s]]; if (f) for (const k in f) v[k] += f[k]; } for (const k in v) v[k] = Math.max(0, Math.min(10, v[k])); return v; }
  const cl = (x, a, b) => Math.max(a, Math.min(b, x));
  function mech(ch) { const v = stats(ch), d = (k) => v[k] - 5; return { vmax: cl(1 + .025 * d('spd'), .85, 1.15), boost: cl(1 + .1 * d('spd'), .5, 1.6), grip: cl(1 + .08 * d('grp'), .6, 1.4), steer: cl(1 + .03 * d('grp'), .88, 1.15), jump: 1, airg: 1, hurt: 1, free1: false, regen: false }; }
  window.DLFX = { FXS, TXT, SLOTS, stats, mech };
})();
