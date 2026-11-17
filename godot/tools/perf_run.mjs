// Rides the course on autopilot in a separate Chrome (no camera, own empty profile) and reports the slow frames and what the graphics calls were doing in them.
//   node tools/perf_run.mjs [seconds of play, default 40] [extra query, e.g. "rs=1"]
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const secs = Number(process.argv[2] || 40);
const extra = process.argv[3] ? '&' + process.argv[3] : '';
const port = 9333 + Math.floor(Math.random() * 200);
const dir = mkdtempSync(join(tmpdir(), 'dh-perf-'));
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--window-size=1280,720',
  '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--autoplay-policy=no-user-gesture-required', '--no-first-run', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result?.result?.value;
const click = async (x, y) => { await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }); await sleep(120); for (const type of ['mousePressed', 'mouseReleased']) { await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', buttons: type === 'mousePressed' ? 1 : 0, clickCount: 1 }); await sleep(80); } };
const key = async (k, code, vk) => { for (const type of ['keyDown', 'keyUp']) { await send('Input.dispatchKeyEvent', { type, key: k, code, windowsVirtualKeyCode: vk }); await sleep(60); } };
const shot = async (name) => { const r = await send('Page.captureScreenshot', { format: 'jpeg', quality: 55 }); (await import('node:fs')).writeFileSync(join(dir, name), Buffer.from(r.result.data, 'base64')); console.log('screenshot:', join(dir, name).split(String.fromCharCode(92)).join('/')); };
try {
  let targets;
  for (let i = 0; i < 40; i++) { try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable');
  await send('Page.navigate', { url: 'http://localhost:8060/prof.html?autopilot&nocam' + extra });
  let lastP = -1, same = 0;
  for (let i = 0; i < 160; i++) { await sleep(500); const pn = await ev('window.__sp ? __sp.programs : 0'); same = (pn === lastP && pn > 60) ? same + 1 : 0; lastP = pn; if (same >= 5) break; }
  console.log('gpu:', await ev("(function(){var c=document.createElement('canvas').getContext('webgl');var d=c.getExtension('WEBGL_debug_renderer_info');return d?c.getParameter(d.UNMASKED_RENDERER_WEBGL):'?'})()"));
  console.log('at title:', await ev('__sp.summary(0)'));
  const vh = await ev('innerHeight'), vw = await ev('innerWidth');
  await ev("document.querySelector('canvas').focus(); 0");
  await key('Enter', 'Enter', 13); await sleep(1800);   // title: any key
  await shot('menu.jpg');
  for (let i = 0; i < 4; i++) { const before = await ev('__sp.programs'); await click(vw * 0.5, vh * 0.905); await sleep(5000); if ((await ev('__sp.programs')) > before) break; }   // START (again if the menu was not ready)
  await ev('__sp.slow.length = 0; __sp.frames = 0; 0');
  if (process.env.SHOTS) { for (let i = 0; i < secs; i++) { await sleep(1000); await shot('t' + i + '.jpg'); } } else await sleep(secs * 1000);
  const out = JSON.parse(await ev('__sp.summary(40)'));
  console.log(`play ${secs} s: ${out.frames} frames (${(out.frames / secs).toFixed(1)} fps), ${out.slowFrames} frames over 50 ms, programs ${out.programs}`);
  for (const s of out.slow) console.log(`  at ${s.at}s  ${s.ms} ms (graphics calls ${s.glMs} ms)  ${s.top.map((t) => `${t[0]} x${t[1]} ${t[2]}ms`).join(', ')}`);
  const seen = new Map(); for (const s of out.slow) for (const x of s.src || []) seen.set(x, (seen.get(x) || 0) + 1);
  for (const [x, n] of seen) console.log(`     built in play x${n}: ${x}`);
  const all = JSON.parse(await ev("JSON.stringify((__sp.all||[]).filter(function(e){return /m_glow|m_boost/.test(e[2]);}))"));
  for (const e of all) console.log(`     ${e[0]}s len ${e[1]} ${e[2]}: ${e[3]}`);
  await shot('play.jpg');
} finally { chrome.kill(); }
