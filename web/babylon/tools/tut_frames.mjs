// TUTORIAL FRAMES: lets the car drive the tutorial by itself and captures each lesson twice: while its message is up, and 3 s after (meeting the object).
//   node tools/tut_frames.mjs [url] [outDir]
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const url = process.argv[2] || 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html?tutorial=1&nointake=1';
const out = process.argv[3] || 'stills/tutorial'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9550 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-tut-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
const shot = async (name) => { const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(join(out, name + '.jpg'), Buffer.from(s.result.data, 'base64')); console.log('ok ' + name); };
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + '&tf=' + Date.now() });
  for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__G && window.__G.TUT && window.__G.TUT.built)')) break; }
  let seen = 0, last = '';
  for (let k = 0; k < 500 && seen < 14; k++) {
    await sleep(300); await ev('(()=>{ const G=window.__G; G.PH.vx*=0.5; return 1; })()');
    const txt = await ev("(()=>{ const b=document.getElementById('stBeat'); return b&&b.classList.contains('on')?b.innerText.replace(/\\s+/g,' ').slice(0,40):''; })()");
    if (txt && txt !== last) { last = txt; seen++; await sleep(1200); await shot('t' + seen + 'a_message'); await sleep(4200); await shot('t' + seen + 'b_meet'); }
    if (await ev("!!document.getElementById('tutEnd')")) { await shot('t_end'); break; }
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
