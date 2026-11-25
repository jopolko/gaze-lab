// THUMBS: one frame from each world for the menu's level cards (art/thumb_<world>.jpg, 640x360).
//   node tools/thumbs.mjs [baseUrl] [outDir] [world ...]
// Opens the game in headless Chrome at 1280x720 with the steering held on the road, lets it run a few seconds, warps to a chosen stretch, hides every overlay and saves a JPEG.
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const A = process.argv.slice(2);
const base = A[0] || 'https://joshuaopolko.com/gaze-lab/three/babylon/';
const out = A[1] || 'art'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// world, the stretch to show (z), seconds to settle there
const ALL = [['desert', -1900], ['candy', -2300], ['alpine', -1500], ['egypt', -2100], ['synthwave', -2400], ['tunnel', -1800], ['matrix', -2000], ['psychedelic', -2600]];
const JOBS = A.length > 2 ? ALL.filter((j) => A.slice(2).includes(j[0])) : ALL;
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9650 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-thumb-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--window-size=1280,720', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  for (const [w, z] of JOBS) {
    await send('Page.navigate', { url: base + 'index.html?biome=' + w + '&notap&play&nofs&nosfx&nomusic&nointake&postcap=4&n=' + Date.now() });
    let ok = false; for (let i = 0; i < 90; i++) { await sleep(500); if (await ev('!!(window.__G && window.__G.PH && window.__G.PH.z < -60)')) { ok = true; break; } }
    if (!ok) { console.log('FAIL ' + w + ' (never started)'); continue; }
    await ev(`(() => { const G = window.__G; G.warp(${z}); window.__hold = setInterval(() => { G.PH.x += (G.trailX(G.PH.z) - G.PH.x) * .3; }, 30); return 1; })()`);
    await sleep(5000); await ev("(() => { for (const m of BABYLON.EngineStore.Instances[0].scenes[0].meshes) if (/^dose(name|beam)$|^molbeam$/.test(m.name)) { m.isVisible = false; m.visibility = 0; } return 1; })()");
    await ev(`(() => { const s = document.createElement('style'); s.textContent = 'body *:not(canvas) { visibility: hidden !important; } canvas { visibility: visible !important; }'; document.head.appendChild(s); for (const e of document.querySelectorAll('body *')) if (e.querySelector && e.querySelector('canvas')) e.style.setProperty('visibility', 'visible', 'important'); return 1; })()`);
    await sleep(400);
    const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: 84, clip: { x: 0, y: 0, width: 1280, height: 720, scale: .5 } });
    writeFileSync(join(out, 'thumb_' + w + '.jpg'), Buffer.from(shot.result.data, 'base64')); console.log('ok   ' + w);
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
