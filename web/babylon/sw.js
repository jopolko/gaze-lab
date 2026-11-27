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
/* SONGS (owner 2026-11-26): the recorded tracks under three/music/ are kept on the device the same way: one copy each, replaced in place when the server's copy
   changes (a background check, zero bytes when unchanged), and only for players who come back (from the second visit). The audio player asks for byte ranges; they are cut from the stored copy. The beat analysis
   reads the same stored copy, so a song is downloaded once. */
const MUSIC = /\/three\/music\/[^/?]+\.(ogg|mp3|wav|m4a)(\?|$)/i, MCACHE = 'ag-music'; const inflight = new Map();
async function musicFull(e, url) { const c = await caches.open(MCACHE), hit = await c.match(url); if (hit) { e.waitUntil(recheck(c, url, hit)); return hit; }
  /* (owner 2026-11-26: keep a song only for players who come back: the first visit streams it and leaves a 1-byte note; a later visit (30 min on) stores it) */
  const seen = await caches.open(MCACHE + '-seen'), note = await seen.match(url), back = note && Date.now() - (+(await note.clone().text()) || 0) > 30 * 60000; if (!note) { try { await seen.put(url, new Response(String(Date.now()))); } catch (er) { } }
  if (!inflight.has(url)) inflight.set(url, (async () => { const r = await net(url); if (r.status === 200 && back) { try { await c.put(url, r.clone()); fresh.set(url, Date.now()); } catch (er) { } } return r; })().finally(() => setTimeout(() => inflight.delete(url), 1000)));
  const r = await inflight.get(url); return r.clone(); }
async function music(e) { const url = e.request.url.split('#')[0], full = await musicFull(e, url), rg = e.request.headers.get('range'); if (!rg || full.status !== 200) return full;
  const buf = await full.arrayBuffer(), L = buf.byteLength, m = /bytes=(\d*)-(\d*)/.exec(rg); let a = 0, b = L - 1; if (m) { if (m[1] === '' && m[2] !== '') { a = Math.max(0, L - +m[2]); } else { a = +m[1] || 0; if (m[2] !== '') b = Math.min(L - 1, +m[2]); } }
  return new Response(buf.slice(a, b + 1), { status: 206, headers: { 'Content-Type': full.headers.get('content-type') || 'audio/ogg', 'Content-Range': 'bytes ' + a + '-' + b + '/' + L, 'Content-Length': String(b - a + 1), 'Accept-Ranges': 'bytes' } }); }
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => { if (e.request.method !== 'GET') return; if (MUSIC.test(e.request.url)) { e.respondWith(music(e).catch(() => fetch(e.request))); return; } if (e.request.headers.has('range')) return;
  if (DATA.test(e.request.url)) { e.respondWith(levelData(e).catch(() => fetch(e.request))); return; }
  e.respondWith(fetch(e.request)); });
