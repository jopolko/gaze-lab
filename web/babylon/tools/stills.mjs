// STILLS: renders dramatic frames of the real character models (for the storyboard and the graphic novel).
//   node tools/stills.mjs [baseUrl] [outDir]
// Each job opens dressup.html in still mode (?still=1) at 1280x720, freezes the story reel on one moment, and saves a JPEG.
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const ARGS = process.argv.slice(2).filter((a) => !a.startsWith('--')), SHOTS_ONLY = process.argv.includes('--shots');
const base = (ARGS[0] || 'https://joshuaopolko.com/gaze-lab/three/babylon/') .replace(/[^/]*$/, (m) => (m.includes('.') ? '' : m));
const out = ARGS[1] || 'stills'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// scene: 0 murmur, 1 blue, 2 see, 3 sign, 4 tunnel, 5 lamp. cam = alpha,beta,radius,targetY (alpha PI/2 = straight on)
export const JOBS = [
  ['01_murmur_arrives', 'scene=0&t=3.0&set=black&props=card&mask=mirror&cam=1.82,1.5,7.6,2.35'],
  ['02_murmur_smug', 'scene=0&t=6.8&set=black&props=card&mask=mirror&cam=1.95,1.45,7.4,2.3'],
  ['03_something_blue', 'scene=1&t=3.9&set=dusk&props=crystal&mask=mirror&cam=1.25,1.52,7.4,2.0'],
  ['04_see', 'scene=2&t=3.6&set=dusk&props=burst&mask=mirror&cam=1.5,1.38,6.4,2.2'],
  ['05_the_sign', 'scene=3&t=5.8&set=dusk&props=sign&mask=mirror&cam=1.9,1.5,7.0,2.0'],
  ['06_tunnel_dread', 'scene=4&t=4.8&set=tunnel&mask=mirror&cam=1.5,1.68,5.6,1.9'],
  ['07_tunnel_resolve', 'scene=4&t=8.6&set=tunnel&mask=mirror&cam=1.3,1.38,6.0,2.0'],
  ['08_the_lamp', 'scene=5&t=6.8&set=lamp&props=lamp&mask=mirror&cam=1.75,1.5,6.8,2.1'],
  ['09_robot_resolve', 'scene=4&t=8.6&set=tunnel&mask=robot&cam=1.35,1.4,5.8,2.2'],
  ['10_robot_joy', 'scene=2&t=3.6&set=dusk&props=burst&mask=robot&cam=1.5,1.38,6.2,2.2'],
  ['11_grin_resolve', 'scene=4&t=8.6&set=tunnel&mask=grin&cam=1.35,1.4,5.8,2.2'],
  ['12_grin_joy', 'scene=2&t=3.6&set=dusk&props=burst&mask=grin&cam=1.5,1.38,6.2,2.2'],
  ['13_gas_resolve', 'scene=4&t=8.6&set=tunnel&mask=gas&cam=1.35,1.4,5.8,2.2'],
  ['14_gas_joy', 'scene=2&t=3.6&set=dusk&props=burst&mask=gas&cam=1.5,1.38,6.2,2.2'],
];
export const SHOTJOBS = ['thrilled', 'monolith', 'optimism', 'lanes', 'tiptoe', 'peek', 'aloft', 'magnet'].map((n, i) => ['s' + String(i + 1).padStart(2, '0') + '_' + n, 'shot=' + n]);
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9650 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-still-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--window-size=1280,720', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  for (const [name, q] of (SHOTS_ONLY ? SHOTJOBS : JOBS)) {
    await send('Page.navigate', { url: base + 'dressup.html?still=1&' + q + '&n=' + Date.now() });
    let ok = false; for (let i = 0; i < 60; i++) { await sleep(500); if (await ev('!!window.__STILL_READY')) { ok = true; break; } }
    await sleep(600);
    if (!ok) { console.log('FAIL ' + name + ' (never became ready)'); continue; }
    const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: 90 });
    writeFileSync(join(out, name + '.jpg'), Buffer.from(shot.result.data, 'base64')); console.log('ok   ' + name);
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
