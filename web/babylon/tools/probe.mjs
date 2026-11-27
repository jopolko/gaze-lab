// PROBE: open a game URL headless (muted), wait for window.__G, run a JS file's async body in the page, print what it returns.
//   node tools/probe.mjs "<url>" probe.js
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, file] = process.argv.slice(2);
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map(), errors = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result?.value; };
const port = 9600 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-probe-'));
const chrome = spawn(CHROME, ['--headless=new', '--mute-audio', '--autoplay-policy=no-user-gesture-required', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--enable-unsafe-swiftshader', '--window-size=' + (process.env.WS || '924,412'), 'about:blank'], { stdio: 'ignore' });
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } else if (d.method === 'Runtime.exceptionThrown') errors.push(d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text); else if (d.method === 'Runtime.consoleAPICalled' && (d.params.type === 'error' || d.params.type === 'warning')) errors.push(d.params.type + ': ' + d.params.args.map((a) => a.value || a.description).join(' ')); };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: +(process.env.VW || 924), height: +(process.env.VH || 412), deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url });
  let ok = false; for (let i = 0; i < 90; i++) { await sleep(1000); try { if (await ev(process.env.READY || '!!(window.__G && window.__G.PH && window.__G.LV)')) { ok = true; break; } } catch { } }
  if (!ok) console.log('did not load'); else { await sleep(2500);
    // the probe may return {shots:[...]} steps: each a JS snippet run before a screenshot saved to $SHOTDIR/probe_<i>.png
    const out = await ev('(async()=>{' + readFileSync(file, 'utf8') + '})()'); console.log(out);
    try { const o = JSON.parse(out); if (o && o.shots) for (let i = 0; i < o.shots.length; i++) { await ev('(async()=>{' + o.shots[i] + '})()'); await sleep(+(process.env.SHOTWAIT || 700)); const png = (await send('Page.captureScreenshot', { format: 'png' })).result.data; (await import('node:fs')).writeFileSync(join(process.env.SHOTDIR || '.', 'probe_' + i + '.png'), Buffer.from(png, 'base64')); } } catch { } }
  console.log('errors:', JSON.stringify((process.env.ERRALL ? errors.filter((e) => /ERROR|rror:/.test(e)).map((e) => e.slice(-600)) : errors.slice(0, 8))));
} catch (e) { console.log('PROBE FAILED', String(e).slice(0, 400)); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
