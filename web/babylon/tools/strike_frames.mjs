// STRIKE FRAMES: fills the supercharge and captures the relay strike every 0.4 s.
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const url = 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html?biome=' + (process.argv[2] || 'alpine') + '&nointake=1';
const out = 'stills/strike'; mkdirSync(out, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9000 + Math.floor(Math.random() * 90), dir = mkdtempSync(join(tmpdir(), 'dl-st-'));
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + '&sf=' + Date.now() });
  for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__G && window.__G.dopAdd)')) break; }
  await sleep(3000); await ev('(()=>{ const G=window.__G; G.dopAdd("mol",1); return 1; })()');
  for (let k = 0; k < 10; k++) { await sleep(400); const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(join(out, 'f' + k + '.jpg'), Buffer.from(s.result.data, 'base64')); }
  console.log('ok');
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
