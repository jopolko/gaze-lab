// THE LAB: a trip-effect explorer. It cycles through combinations of effect knobs by itself, eases from one to the next, and near the end of each one asks for a verdict (a big thumbs up / thumbs down).
// After the verdict it asks WHAT it was: a row of tags (trees breathing, mountains swaying, the face in the clouds, ground moire, colour split...). Each tag points at the knobs that make that thing, so the lab learns which knob mattered:
//   - a liked combination is kept as a parent; the knobs behind its tags are HELD at their values while the other knobs are mutated around them ("keep what worked, explore around it");
//   - a flat combination's tagged knobs are pulled back toward neutral;
//   - tags that no knob exists for yet (effects Godot has that are not in this viewer) are still logged, as a list of what to build next.
// Every verdict and tag set is handed to log(record) with the full combination, so it can be read and analysed later.
//
//   const LAB = createLab({ knobs, tags, apply(values), log(record), holdS, easeS, judgeS });  LAB.tick(dt); LAB.verdict(true|false); LAB.toggleTag(id); LAB.commit(); LAB.state
// knobs: [{ k, lo, hi, def, note }]   tags: [{ id, label, knobs: ['k_warp', ...] }]

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const gauss = () => { let u = 0, v = 0; while (!u) u = Math.random(); while (!v) v = Math.random(); return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };

export function createLab(o) {
  const K = o.knobs, N = K.length, T = o.tags || [], kIdx = {}; K.forEach((k, i) => { kIdx[k.k] = i; });
  const norm = (i, v) => (v - K[i].lo) / (K[i].hi - K[i].lo), real = (i, g) => K[i].lo + g * (K[i].hi - K[i].lo), DEF = K.map((k, i) => norm(i, k.def));
  const tagKnobs = (ids) => { const set = new Set(); for (const id of ids) { const t = T.find((x) => x.id === id); if (t) for (const k of t.knobs) if (kIdx[k] !== undefined) set.add(kIdx[k]); } return set; };
  const S = { on: true, n: 0, likes: [], nopes: [], cur: DEF.slice(), from: DEF.slice(), to: DEF.slice(), t: 0, hold: 0, phase: 'ease', label: '', changed: [], flash: 0, last: null, judge: false, ask: null, askT: 0, picked: [], pend: null, wishlist: {} };
  try { const sv = JSON.parse(localStorage.getItem('labElites2') || 'null'); if (sv && sv.length) S.likes = sv.filter((e) => e.g && e.g.length === N).slice(-40); const wl = JSON.parse(localStorage.getItem('labWish') || 'null'); if (wl) S.wishlist = wl; } catch (e) { }
  const dist = (a, b) => Math.sqrt(a.reduce((s, x, i) => s + (x - b[i]) * (x - b[i]), 0) / N);
  const clampG = (g) => g.map((x) => clamp(x, 0, 1));
  function propose() {
    const parent = S.likes.length && Math.random() < .75 ? S.likes[Math.floor(Math.random() * S.likes.length)] : null;
    let g = parent ? parent.g.slice() : (Math.random() < .5 ? DEF.slice() : S.cur.slice()); const keep = parent ? tagKnobs(parent.tags || []) : new Set();
    if (S.likes.length >= 2 && Math.random() < .22) { const b2 = S.likes[Math.floor(Math.random() * S.likes.length)]; g = g.map((x, i) => (keep.has(i) || Math.random() < .5 ? x : b2.g[i])); }          // crossover (what worked is kept)
    const nChange = 2 + Math.floor(Math.random() * 4), sigma = S.likes.length ? .13 : .3;
    for (let c = 0; c < nChange; c++) { let i = Math.floor(Math.random() * N), guard = 0; while (keep.has(i) && Math.random() < .85 && guard++ < 8) i = Math.floor(Math.random() * N); g[i] = Math.random() < .12 ? Math.random() : g[i] + gauss() * sigma; }
    if (S.likes.length < 3 && Math.random() < .3) { const i = Math.floor(Math.random() * N); g[i] = Math.random(); }
    g = clampG(g);
    for (let tries = 0; tries < 6 && S.nopes.some((n) => dist(n.g, g) < .07); tries++) { const i = Math.floor(Math.random() * N); g[i] = Math.random(); g = clampG(g); }
    return g;
  }
  function describe(g) { return g.map((x, i) => ({ i, d: x - DEF[i] })).filter((e) => Math.abs(e.d) > .12).sort((a, b) => Math.abs(b.d) - Math.abs(a.d)).slice(0, 5).map((e) => K[e.i].k + (e.d > 0 ? ' +' : ' -') + Math.round(Math.abs(e.d) * 100)); }
  function next() { S.from = S.cur.slice(); S.to = propose(); S.t = 0; S.phase = 'ease'; S.n++; S.judge = false; S.ask = null; S.changed = describe(S.to); S.label = '#' + S.n + '  ' + (S.changed.join('   ') || 'baseline'); }
  function values(g) { const v = {}; K.forEach((k, i) => { v[k.k] = +real(i, g[i]).toFixed(4); }); return v; }
  const send = (rec) => { try { o.log && o.log(rec); } catch (e) { } };
  // the verdict: thumbs up / down. Then the tag row (what worked / what was off) for askS seconds; committing (or the timeout) applies the learning and moves on.
  function verdict(up) {
    if (!S.on || S.ask) return; S.ask = up ? 'up' : 'down'; S.askT = o.askS || 6; S.picked = []; S.flash = 1; S.last = up ? '\u{1F44D}' : '\u{1F44E}'; S.pend = { g: S.cur.slice(), values: values(S.cur), n: S.n };
    send({ kind: 'lab', pick: up ? 'like' : 'nope', n: S.n, likes: S.likes.length, nopes: S.nopes.length, genome: S.pend.values, tags: [] });
  }
  function toggleTag(id) { if (!S.ask) return; const i = S.picked.indexOf(id); if (i >= 0) S.picked.splice(i, 1); else S.picked.push(id); S.askT = Math.max(S.askT, 3); }
  function commit() {
    if (!S.ask || !S.pend) return; const up = S.ask === 'up', tags = S.picked.slice(), ks = tagKnobs(tags), rec = { g: S.pend.g, tags };
    for (const id of tags) { const t = T.find((x) => x.id === id); if (t && !t.knobs.length) S.wishlist[id] = (S.wishlist[id] || 0) + (up ? 1 : -1); }          // tags with no knob yet: a list of what to build
    if (up) { S.likes.push(rec); if (S.likes.length > 60) S.likes.shift(); S.phase = 'hold'; S.t = 0; S.hold = (o.holdS || 7) * 1.4; }
    else { S.nopes.push(rec); if (S.nopes.length > 40) S.nopes.shift(); for (const i of ks) { S.cur[i] += (DEF[i] - S.cur[i]) * .6; } }
    try { localStorage.setItem('labElites2', JSON.stringify(S.likes)); localStorage.setItem('labWish', JSON.stringify(S.wishlist)); } catch (e) { }
    send({ kind: 'lab', pick: up ? 'like-tags' : 'nope-tags', n: S.pend.n, tags, genome: S.pend.values });
    S.ask = null; S.pend = null; if (!up) next();
  }
  function tick(dt) {
    if (!S.on) { o.apply(values(DEF)); return; }
    S.flash = Math.max(S.flash - dt * 1.4, 0);
    if (S.ask) { S.askT -= dt; if (S.askT <= 0) commit(); }
    else if (S.phase === 'ease') { S.t += dt; const k = clamp(S.t / (o.easeS || 2.5), 0, 1), e = k * k * (3 - 2 * k); S.cur = S.from.map((a, i) => a + (S.to[i] - a) * e); if (k >= 1) { S.phase = 'hold'; S.t = 0; S.hold = o.holdS || 7; } }
    else { S.t += dt; S.judge = S.t >= S.hold - (o.judgeS || 3); if (S.t >= S.hold) next(); }
    o.apply(values(S.cur));
  }
  function toggle() { S.on = !S.on; if (S.on) next(); }
  next();
  function stats() { if (!S.likes.length) return null; const m = DEF.map(() => 0); for (const e of S.likes) e.g.forEach((x, i) => { m[i] += x / S.likes.length; }); return K.map((k, i) => ({ k: k.k, mean: +real(i, m[i]).toFixed(3) })); }
  return { state: S, tick, verdict, like: () => verdict(true), nope: () => verdict(false), toggleTag, commit, toggle, next, stats, values: () => values(S.cur), knobs: K, tags: T };
}
