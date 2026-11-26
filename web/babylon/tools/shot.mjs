// SHOT: open any page headless (muted) at a given size and pixel ratio, with localStorage preset, wait, save a PNG.
//   node tools/shot.mjs "<url>" out.png      env: VW, VH, DPR (default 1), WAIT ms (default 9000), LS='{"dl_freq":"820"}'
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, out] = process.argv.slice(2);
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const port = 9800 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-shot-'));
const chrome = spawn(CHROME, ['--headless=new', '--mute-audio', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--enable-unsafe-swiftshader', 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: +(process.env.VW || 1280), height: +(process.env.VH || 720), deviceScaleFactor: +(process.env.DPR || 1), mobile: false });
  const ls = process.env.LS ? JSON.parse(process.env.LS) : {};
  await send('Page.addScriptToEvaluateOnNewDocument', { source: `try { const o = ${JSON.stringify(ls)}; for (const k in o) localStorage.setItem(k, o[k]); } catch (e) { }` });
  await send('Page.navigate', { url }); await sleep(+(process.env.WAIT || 9000));
  const png = (await send('Page.captureScreenshot', { format: 'png' })).result.data; writeFileSync(out, Buffer.from(png, 'base64')); console.log('saved', out);
} catch (e) { console.log('SHOT FAILED', String(e).slice(0, 300)); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
