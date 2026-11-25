// SHOT: a phone-sized screenshot of any page.  node tools/shot.mjs "<url>" <width> <height> <out.jpg> [waitMs] [js-before-shot]
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, w, h, out, waitMs = '4000', js = ''] = process.argv.slice(2);
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const port = 9650 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-shot-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', 'about:blank'], { stdio: 'ignore' });
try {
  let t; for (let i = 0; i < 40; i++) { try { t = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(t.find((x) => x.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: +w, height: +h, deviceScaleFactor: 1, mobile: +w < +h });
  await send('Page.navigate', { url }); await sleep(+waitMs);
  if (js) { await send('Runtime.evaluate', { expression: js, awaitPromise: true }); await sleep(1500); }
  const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(out, Buffer.from(s.result.data, 'base64')); console.log('ok ' + out);
} catch (e) { console.log('ERROR ' + e); } finally { try { ws && ws.close(); } catch { } chrome.kill(); }
