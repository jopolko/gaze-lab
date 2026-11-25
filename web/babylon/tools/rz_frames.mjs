// ROUTE ZERO FRAMES: the player's view at each story moment (warps there, waits, captures). Used for the storyboard.
//   node tools/rz_frames.mjs
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const url = 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html?story=1&nointake=1';
const out = 'stills/rz'; mkdirSync(out, { recursive: true });
const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// [name, z, seeOn] : where the player is when the moment happens
const STOPS = [['m3_signs', -650, false], ['m4_crystal', -1150, false], ['m5_tunnelsign', -1700, true], ['m6_mouth', -2120, true], ['m7_lamp', -2380, true], ['m8_exit', -2720, false]];
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const port = 9200 + Math.floor(Math.random() * 90), dir = mkdtempSync(join(tmpdir(), 'dl-rz-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + '&rz=' + Date.now() });
  for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__G && window.__G.DOP && window.__ST && window.__ST.opening)')) break; }
  await sleep(18000);
  // clean frames: hide every overlay and button, keep only the world
  await ev(`(()=>{ const s=document.createElement('style'); s.textContent='#stBeat,#stSignB,#pzb,#pm,#camui,#cam,button,select,#status,#back,#stBtns,#stLog,#stEnd,#stPhone,#stTitle{display:none!important}'; document.head.appendChild(s); [...document.body.querySelectorAll('div')].forEach(d=>{ const r=d.getBoundingClientRect(); if(/camera/i.test(d.textContent||'') && r.height<60) d.style.display='none'; }); return 1; })()`);
  for (const [name, z, see] of STOPS) {
    await ev(`(()=>{ const G=window.__G, S=window.__ST; G.warp(${z}); G.PH.vz=-1; G.PH.vx=0; ${see ? 'S.seeT=20;' : ''} return 1; })()`); await sleep(2600);
    const s = await send('Page.captureScreenshot', { format: 'jpeg', quality: 85 }); writeFileSync(join(out, name + '.jpg'), Buffer.from(s.result.data, 'base64')); console.log('ok ' + name);
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
