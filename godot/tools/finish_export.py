"""After a Godot web export: make every build load fast and update cleanly.

    python tools/finish_export.py [build/web]

* The big files get a fingerprint in their name (index.wasm -> index.<hash>.wasm, the same for .pck, .js and the audio worklets). A browser can then keep them for a year without ever
  showing an old version: a new build has new names, and index.html (always fetched fresh) points at them.
* index.service.worker.js is replaced by a small one: the page itself network-first (so a reload always gets the newest build, with the last copy as the offline fallback), the
  fingerprinted files and the tracker's model/library downloads cache-first (so a returning player loads almost nothing).
* The viewport tag gets viewport-fit=cover so a phone's notch area is used.
Run it between the export and the upload (tools/deploy.sh does).
"""
import hashlib
import json
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
root = os.path.abspath(root)
names = ["wasm", "pck", "js", "audio.worklet.js", "audio.position.worklet.js"]
for f in os.listdir(root):                       # fingerprinted files from earlier builds would only be uploaded again
    if re.match(r"index\.[0-9a-f]{8}\.", f):
        os.remove(os.path.join(root, f))


def p(n):
    return os.path.join(root, n)


# already finished? (the files are renamed once)
if not os.path.exists(p("index.wasm")):
    print("index.wasm not found: nothing to do (export again first)")
    sys.exit(1)
h = hashlib.sha1()
for n in ("wasm", "pck", "js"):
    h.update(open(p("index." + n), "rb").read())
tag = h.hexdigest()[:8]                       # the build as a whole (shown in build.json, names the service worker)
# The ENGINE (wasm, its loader and the audio worklets: 40 MB) is the same file from one game build to the next, so it is named after its own contents and a
# returning player's browser keeps it across game updates. Only the game data (the .pck, under 1 MB) is renamed by every build.
he = hashlib.sha1()
for n in ("wasm", "js", "audio.worklet.js", "audio.position.worklet.js"):
    if os.path.exists(p("index." + n)):
        he.update(open(p("index." + n), "rb").read())
etag = he.hexdigest()[:8]
ptag = hashlib.sha1(open(p("index.pck"), "rb").read()).hexdigest()[:8]
sizes = {}
keep = []
for n in names:
    src = p("index." + n)
    if os.path.exists(src):
        if n == "pck":
            dst = p("index.%s.pck" % ptag)
        else:
            dst = p("index.%s.%s" % (etag, n))
        if n in ("wasm", "pck"):
            sizes[n] = os.path.getsize(src)
        os.replace(src, dst)
        keep.append(os.path.basename(dst))
html = open(p("index.html"), encoding="utf-8").read()
html = html.replace('"executable":"index"', '"executable":"index.%s"' % etag)
html = html.replace('"index.pck":', '"index.%s.pck":' % ptag).replace('"index.wasm":', '"index.%s.wasm":' % etag)
html = html.replace('"executable":"index.%s"' % etag, '"executable":"index.%s","mainPack":"index.%s.pck"' % (etag, ptag))          # the pack no longer shares the engine's name: say where it is
html = html.replace('<script src="index.js">', '<script src="index.%s.js">' % etag)
html = re.sub(r'(<meta name="viewport" content="[^"]*)"', lambda m: m.group(1) + (", viewport-fit=cover" if "viewport-fit" not in m.group(1) else "") + '"', html, count=1)
open(p("index.html"), "w", encoding="utf-8").write(html)

sw = r"""// Downhill service worker (build %(tag)s). The page: network first, so a reload always gets the newest build. The fingerprinted game files and the tracker's downloads: cache first.
const TAG = '%(tag)s';
const CORE = 'dh-files-v2';
const KEEP = %(keep)s;
const EXT = 'dh-ext-v1';
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (e) => {
  // drop the old per-build caches, and from the shared one only the fingerprinted files this build no longer uses (the engine stays across game updates)
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k.startsWith('dh-core-')).map((k) => caches.delete(k))))
    .then(() => caches.open(CORE)).then((c) => c.keys().then((rs) => Promise.all(rs.filter((r) => { const n = new URL(r.url).pathname.split('/').pop(); return /\.[0-9a-f]{8}\./.test(n) && KEEP.indexOf(n) < 0; }).map((r) => c.delete(r)))))
    .then(() => self.clients.claim()));
});
async function cacheFirst(req, name) {
  const c = await caches.open(name);
  const hit = await c.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res && (res.status === 200 || res.type === 'opaque')) c.put(req, res.clone());
  return res;
}
async function networkFirst(req) {
  const c = await caches.open(CORE);
  try {
    const res = await fetch(req);
    if (res && res.status === 200) c.put(req, res.clone());
    return res;
  } catch (err) {
    const hit = await c.match(req);
    if (hit) return hit;
    throw err;
  }
}
self.addEventListener('fetch', (e) => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (u.origin === self.location.origin) {
    if (/\.[0-9a-f]{8}\.[a-z.]+$/.test(u.pathname)) { e.respondWith(cacheFirst(r, CORE)); return; }
    if (r.mode === 'navigate' || /\/index\.html$/.test(u.pathname)) { e.respondWith(networkFirst(r)); return; }
    return;
  }
  if (/(^|\.)cdn\.jsdelivr\.net$|^storage\.googleapis\.com$/.test(u.host)) e.respondWith(cacheFirst(r, EXT));
});
""" % {"tag": tag, "keep": json.dumps(keep)}
open(p("index.service.worker.js"), "w", encoding="utf-8").write(sw)
# the page title: the game's own name only (the project name in project.godot still says "Gaze Lab: Downhill", and is left alone because the saved settings and unlocks are filed under it)
hp = p("index.html")
ht = open(hp, encoding="utf-8").read()
ht2 = ht.replace("Gaze Lab: Downhill", "Downhill")
if ht2 != ht:
    open(hp, "w", encoding="utf-8").write(ht2)
# the music files are not in the game's download: they sit beside it and are fetched when wanted (see DhDirector)
msrc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "music_web")
if os.path.isdir(msrc):
    import shutil
    shutil.copytree(msrc, p("music"), dirs_exist_ok=True)
open(p("build.json"), "w").write(json.dumps({"build": tag, "engine": etag, "wasm": sizes.get("wasm"), "pck": sizes.get("pck")}))
print("finished: build %s  (wasm %.1f MB, pck %.2f MB)" % (tag, sizes.get("wasm", 0) / 1e6, sizes.get("pck", 0) / 1e6))
