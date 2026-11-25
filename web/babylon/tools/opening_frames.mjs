// OPENING FRAMES: captures Route Zero's opening at fixed moments (black, phone, lights up, title, road) so the cut can be judged without driving.
//   node tools/opening_frames.mjs [url] [outDir]
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const url = process.argv[2] || 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html?story=1&nointake=1';
const out = process.argv[3] || 'stills/opening'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const AT = [[1.5, 'o1_black'], [5, 'o2_phone'], [11, 'o3_lights'], [14, 'o4_title'], [19, 'o5_road']];
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9450 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-open-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + '&of=' + Date.now() });
  let t0 = 0; for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__ST && window.__ST.opening)')) { t0 = Date.now(); break; } }
  if (!t0) throw new Error('opening never started');
  for (const [sec, name] of AT) { const w = t0 + sec * 1000 - Date.now(); if (w > 0) await sleep(w); const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: 85 }); writeFileSync(join(out, name + '.jpg'), Buffer.from(shot.result.data, 'base64')); console.log('ok ' + name + ' at ' + sec + ' s'); }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
