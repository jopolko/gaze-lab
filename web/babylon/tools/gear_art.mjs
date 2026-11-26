// GEAR ART: renders each gear item the way the character editor shows it (its own 3D model, framed on its bounds) and saves art/gear_<id>.png for the menu's Upgrades cards.
//   node tools/gear_art.mjs [base url]   (default http://127.0.0.1:8091/babylon/)
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'http://127.0.0.1:8091/babylon/', OUT = new URL('../art/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms)), port = 9700 + Math.floor(Math.random() * 200), dir = mkdtempSync(join(tmpdir(), 'gear-'));
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--mute-audio', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--window-size=1200,900', 'about:blank'], { stdio: 'ignore' });
let ws, id = 0; const wait = new Map(); const send = (m, p = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result.result.value;
try {
  let t; for (let i = 0; i < 40; i++) { try { t = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(t.find((x) => x.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r)); ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Page.navigate', { url: base + 'dressup.html?noshell' });
  let got = null; for (let i = 0; i < 60 && !got; i++) { await sleep(1000); got = await ev("(() => { const T = window.__THUMBS; if (!T) return null; const ids = ['rocket', 'pole', 'shield', 'bull']; return ids.every((k) => T['gear.' + k]) ? ids.map((k) => [k, T['gear.' + k][0]]) : null; })()"); }
  /* the shield is a glass bubble: a 3D thumbnail of glass on a transparent canvas comes out empty, so it is drawn: a dome of light with its emitter on top */
  if (got) { const sh = await ev("(() => { const c = document.createElement('canvas'); c.width = 224; c.height = 168; const x = c.getContext('2d'); const g = x.createRadialGradient(112, 120, 10, 112, 120, 92); g.addColorStop(0, 'rgba(70,224,255,.05)'); g.addColorStop(.75, 'rgba(70,224,255,.28)'); g.addColorStop(.97, 'rgba(160,240,255,.9)'); g.addColorStop(1, 'rgba(70,224,255,0)'); x.fillStyle = g; x.beginPath(); x.ellipse(112, 132, 96, 92, 0, Math.PI, 0); x.closePath(); x.fill(); x.strokeStyle = 'rgba(190,245,255,.55)'; x.lineWidth = 1.2; for (let i = -3; i <= 3; i++) { x.beginPath(); x.ellipse(112, 132, Math.abs(i) * 14 + 4, 90, 0, Math.PI, 0); x.stroke(); } for (let j = 1; j <= 3; j++) { x.beginPath(); x.ellipse(112, 132 - j * 24, 96 * Math.cos(Math.asin(j * 24 / 92)), 10, 0, 0, Math.PI * 2); x.stroke(); } x.fillStyle = '#46e0ff'; x.shadowColor = '#46e0ff'; x.shadowBlur = 18; x.fillRect(98, 30, 28, 14); x.fillStyle = 'rgba(30,60,90,.9)'; x.shadowBlur = 0; x.fillRect(16, 132, 192, 6); return c.toDataURL('image/png'); })()"); const i = got.findIndex((q) => q[0] === 'shield'); if (i >= 0 && sh) got[i][1] = sh; }
  if (!got) console.log('no gear thumbnails'); else for (const [k, url] of got) { writeFileSync(OUT + 'gear_' + k + '.png', Buffer.from(url.split(',')[1], 'base64')); console.log('saved art/gear_' + k + '.png'); }
} finally { try { ws && ws.close(); } catch { } chrome.kill(); }
