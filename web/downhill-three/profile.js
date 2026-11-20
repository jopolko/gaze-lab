// PROFILE: what persists between trips (the collection, never the trip's layers). Versioned so an update can migrate old saves. Stored in localStorage, every access guarded: private windows and blocked storage must never break the game.
export const PROFILE_VERSION = 1;
const KEY = 'downhill.profile';
const fresh = () => ({ v: PROFILE_VERSION, caught: {}, stats: { runs: 0, catches: 0, longestChain: 0, bestTrip: null }, courses: ['long_s7'], themes: [] });
function migrate(p) {          // add a step here for every version bump: if (p.v < 2) { ...; p.v = 2; }
  if (!p || typeof p !== 'object') return fresh(); const f = fresh(); const out = Object.assign(f, p); out.stats = Object.assign(f.stats, p.stats || {}); out.v = Math.max(+p.v || 1, 1); return out;
}
export function loadProfile() { try { const raw = localStorage.getItem(KEY); return raw ? migrate(JSON.parse(raw)) : fresh(); } catch (e) { return fresh(); } }
export function saveProfile(p) { try { localStorage.setItem(KEY, JSON.stringify(p)); } catch (e) { } }
export function recordCatch(p, id, depth = 1) { const c = p.caught[id] || (p.caught[id] = { count: 0, best_depth: 0 }); c.count++; c.best_depth = Math.max(c.best_depth, depth); p.stats.catches++; }
