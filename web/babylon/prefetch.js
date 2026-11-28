/* PREFETCH (owner 2026-11-27: the first play's load was slow): while the player sits on the title screen or the menu, quietly download the level they are
   about to play, so Tune In / Continue starts almost at once. The files go through the service worker, which keeps level data on the device, and the browser's
   cache. Same road plan as the game makes (director.js planRoad with the day's seed). Low priority, one file at a time, stops if the page goes away or the
   connection says save-data. window.AGPrefetch.level(world | 'story') */
(() => {
  if (window.AGPrefetch) return;
  const BK = '../downhill-three/data/', NROWS_COMPOSE = 46, NROWS_STORY = 38, pad2 = (j) => String(j).padStart(2, '0');
  const slow = () => { const c = navigator.connection; return !!(c && (c.saveData || /2g/.test(c.effectiveType || ''))); };
  const get = (u) => fetch(BK + u, { priority: 'low' }).then((r) => (r.ok ? r : null)).catch(() => null);
  const json = async (u) => { const r = await get(u); return r ? r.json() : null; };
  let busy = null;
  async function files(world) {
    if (world === 'story') { const out = ['long_s7/meta.json', 'long_s7/physics.json']; for (let j = 0; j < NROWS_STORY; j++) out.push('long_s7/row_' + pad2(j) + '.json'); return out; }
    const M = await import('./director.js?v=20261127c'); const [catalog, EDG] = await Promise.all([json('row_catalog.json'), json('trip_edges.json')]); if (!catalog || !EDG) return [];
    const { joinCost } = await import('../downhill-three/trip_compose.mjs');
    const seed = M.seedOf(world + ':' + ('d' + new Date().toISOString().slice(0, 10))), plan = M.planRoad({ catalog, edge: (d, j) => EDG[d][j], joinCost, seed, n: NROWS_COMPOSE, world, shape: M.planShape(seed, world) });
    const out = ['bank/shared.json']; for (const d of new Set(plan.map((p) => p.d))) out.push('bank/shared_' + d + '.json');
    for (const p of plan) { const b = 'bank/' + p.d + '_' + pad2(p.j); out.push(b + '.p.json', b + '.json'); } return out; }
  async function level(world) { if (busy || slow()) return busy; busy = (async () => { try { const list = await files(world || 'story'); for (const f of list) { if (document.hidden) await new Promise((r) => document.addEventListener('visibilitychange', r, { once: true })); await get(f); } } catch (e) { window.__pfErr = String(e); } })(); return busy; }
  window.AGPrefetch = { level };
})();
