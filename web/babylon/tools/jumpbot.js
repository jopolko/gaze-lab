// JUMP BOT (owner 2026-11-27): drives a level and reports every place the rider is moved in a way a player would read as a glitch:
// any jump the game's own detector flags (window.__jumps), INCLUDING scripted ones (warps, rewinds), when they move the rider backwards or more than 30 m in a frame.
// Use: node tools/probe.mjs "<level url>&go=1&notap" tools/jumpbot.js      (window.__BOTSEC sets the run length, default 90 s; ?botz=<z> starts there)
await new Promise((r) => setTimeout(r, 3500));
const G = window.__G, Q = new URLSearchParams(location.search), RUN = +(window.__BOTSEC || Q.get('botsec') || 90);
if (Q.get('botz')) { window.__legit = 'bot start'; G.warp(+Q.get('botz')); await new Promise((r) => setTimeout(r, 400)); }
window.__jumps.length = 0;
const key = (k, down) => dispatchEvent(new KeyboardEvent(down ? 'keydown' : 'keyup', { key: k }));
let held = null; const z0 = Math.round(G.PH.z);
for (let i = 0; i < RUN * 4; i++) {
  await new Promise((r) => setTimeout(r, 250));
  const off = G.PH.x - G.trailX(G.PH.z), want = Math.sin(i / 9) * 6 - off, k = Math.abs(want) < 1.5 ? null : want > 0 ? 'ArrowRight' : 'ArrowLeft';
  if (k !== held) { if (held) key(held, false); if (k) key(k, true); held = k; }
}
if (held) key(held, false);
const bad = window.__jumps.filter((j) => /went backwards/.test(j.why) || j.moved > 30);
return JSON.stringify({ ran: RUN, from: z0, to: Math.round(G.PH.z), glitches: bad.map((j) => ({ why: j.why, scripted: j.legit || null, from: j.from, to: j.to, moved: j.moved })) });
