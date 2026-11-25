// LEVEL FRAMES: lets a level drive itself and captures the view each time a new section of the level script starts, plus at the finale. Reports sections, hits and readiness.
//   node tools/level_frames.mjs [biome]
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const biome = process.argv[2] || 'desert';
const url = 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html?biome=' + biome + '&nointake=1';
const out = 'stills/level_' + biome; mkdirSync(out, { recursive: true });
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9100 + Math.floor(Math.random() * 90), dir = mkdtempSync(join(tmpdir(), 'dl-lvl-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + '&lf=' + Date.now() });
  for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__G && window.__G.LV)')) break; }
  let last = -1, shots = 0;
  for (let k = 0; k < 600; k++) {
    await sleep(300); const st = JSON.parse(await ev('JSON.stringify({i:window.__G.LV.i, done:window.__G.LV.done, z:Math.round(window.__G.PH.z), hits:(window.__crashes||[]).length, R:window.__G.LV.R, tier:window.__G.LV.tier})'));
    if (st.i !== last) { last = st.i; await sleep(2600); const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(join(out, 's' + st.i + '.jpg'), Buffer.from(s.result.data, 'base64')); console.log('section ' + st.i + ' at ' + st.z + ' m, hits ' + st.hits + ', readiness ' + st.R.toFixed(2) + ', tier ' + st.tier); shots++; }
    if (st.done) { await sleep(1200); const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(join(out, 'finale.jpg'), Buffer.from(s.result.data, 'base64')); console.log('finale at ' + st.z + ' m, hits ' + st.hits); break; }
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
