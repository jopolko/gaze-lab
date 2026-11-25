/* The installed app's service worker. It exists so phones offer "Add to Home Screen" and open the game with no browser bars.
   It caches nothing (every update shows up at once) and leaves ranged requests (the opening track's seeking) to the browser. */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => { if (e.request.method !== 'GET' || e.request.headers.has('range')) return; e.respondWith(fetch(e.request)); });
