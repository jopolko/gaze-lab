// GEAR THUMBS: the car wearing each piece of gear, for the menu's Upgrades cards (art/gear_<id>.jpg, 640x360).
//   node tools/gearthumbs.mjs [baseUrl] [outDir]
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const A = process.argv.slice(2);
const base = A[0] || 'https://joshuaopolko.com/gaze-lab/three/babylon/';
const out = A[1] || 'art'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9650 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-gear-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--window-size=1280,720', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: base + 'dressup.html?nofs&next=menu.html' }); await sleep(6000);
  for (const g of ['rocket', 'pole', 'shield', 'bull']) {
    await ev(`(() => { const b = document.querySelector('#mode button[data-m=loadout]'); if (b) b.click(); return 1; })()`); await sleep(1500);
    const ok = await ev(`(() => { const o = [...document.querySelectorAll('#grid .gearopt')]; const want = { rocket: 0, pole: 1, shield: 2, bull: 3 }['${g}']; if (!o[want]) return false; o[want].click(); return true; })()`);
    await sleep(2500);
    if (!ok) { console.log('FAIL ' + g); continue; }
    const r = await ev(`(() => { const s = document.getElementById('hidestyle') || document.createElement('style'); s.id = 'hidestyle'; s.textContent = '#bubble,#rnd,#reelBtn,#stats,#nm,#trip,#reel,#reelCap{visibility:hidden!important}'; document.head.appendChild(s); const b = document.getElementById('cv').getBoundingClientRect(); return [b.x, b.y, b.width, b.height]; })()`);
    await sleep(300);
    const w = r[2], h = Math.min(r[3], w * 9 / 16), y = r[1] + (r[3] - h) / 2;
    const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: 84, clip: { x: r[0], y, width: w, height: h, scale: 640 / w } });
    writeFileSync(join(out, 'gear_' + g + '.jpg'), Buffer.from(shot.result.data, 'base64')); console.log('ok   ' + g);
    await ev(`(() => { const s = document.getElementById('hidestyle'); if (s) s.textContent = ''; return 1; })()`);
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
