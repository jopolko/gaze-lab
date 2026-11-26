/* The installed app's service worker. It makes the game installable ("Add to Home Screen", no browser bars), and it keeps the LEVEL DATA on the device.
   Pages, scripts and art are never cached here: every update shows up at once. Ranged requests (the opening track's seeking) are left to the browser.
   LEVEL DATA (owner 2026-11-26: "don't download each level all over again unless it changes; overwrite new versions, never leave old copies or duplicates"):
   - the road bank and course files under downhill-three/data/ live in ONE cache, named after data/stamp.txt; a level loads straight from it;
   - each file is stored once: fetched with no-store, so the browser's own cache keeps no second copy; a newer version replaces it in place;
   - after a file is served from the device, it is checked against the server in the background (a zero-byte 'not modified' when unchanged) and replaced if it changed;
   - when stamp.txt changes (new level data deployed), every older cache is deleted. Deploying new level data = rewrite stamp.txt (newest data file's mtime). */
const DATA = /\/downhill-three\/data\/.+\.json(\?|$)/, STAMP_URL = new URL('../downhill-three/data/stamp.txt', self.location).href, PREFIX = 'ag-levels-';
let stamp = null, checked = 0, pending = null; const fresh = new Map();          /* (url -> when last checked against the server) */
async function currentStamp() {
  if (stamp && Date.now() - checked < 60000) return stamp;
  if (pending) return pending;
  pending = (async () => { try { const r = await fetch(STAMP_URL + '?t=' + Date.now(), { cache: 'no-store' }); if (r.ok) { const t = (await r.text()).trim(); if (t) stamp = t; } } catch (e) { } checked = Date.now(); pending = null;
    if (stamp) { try { for (const k of await caches.keys()) if (k.startsWith(PREFIX) && k !== PREFIX + stamp) await caches.delete(k); } catch (e) { } } return stamp; })();
  return pending;
}
const net = (url, h) => fetch(url, { cache: 'no-store', headers: h || {} });
async function recheck(c, url, hit) {          /* in the background: has the server got a newer copy? replace ours if so (one copy, overwritten) */
  if (Date.now() - (fresh.get(url) || 0) < 10 * 60000) return; fresh.set(url, Date.now());
  try { const tag = hit.headers.get('etag'), lm = hit.headers.get('last-modified'), h = {}; if (tag) h['If-None-Match'] = tag; else if (lm) h['If-Modified-Since'] = lm; else return;
    const r = await net(url, h); if (r.status === 200) await c.put(url, r); } catch (e) { } }
async function levelData(e) {
  const url = e.request.url, s = await currentStamp(); if (!s) return fetch(e.request);          /* (no stamp reachable: behave as before) */
  const c = await caches.open(PREFIX + s), hit = await c.match(url);
  if (hit) { e.waitUntil(recheck(c, url, hit)); return hit; }
  const r = await net(url); if (r.status === 200) { try { await c.put(url, r.clone()); fresh.set(url, Date.now()); } catch (er) { } } return r;
}
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => { if (e.request.method !== 'GET' || e.request.headers.has('range')) return;
  if (DATA.test(e.request.url)) { e.respondWith(levelData(e).catch(() => fetch(e.request))); return; }
  e.respondWith(fetch(e.request)); });
