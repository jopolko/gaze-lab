// BASIN CHECK: drives the ?basin=1 prototype (docs/BASINS_PLAN.md) along three lines with the arrow keys and reports speed, air, wipeouts,
// crystals taken and frame time; then times the same stretch without the basin.   node tools/basincheck.mjs [base url]
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'http://localhost:8091/babylon/index.html';
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description)); return r.result.value; };
const port = 9600 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-basin-'));
const chrome = spawn(CHROME, ['--headless=new', '--mute-audio', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', 'about:blank'], { stdio: 'ignore' });
const DRIVE = (lineX) => `(async () => { const G = __G, PH = G.PH; const set = (k, on) => window.dispatchEvent(new KeyboardEvent(on ? 'keydown' : 'keyup', { key: k, code: k }));
  PH.z = -1380; PH.x = 0; PH.y = G.th(0, -1380) + .2; PH.vx = 0; PH.vz = -40; PH.vy = 0; PH.heading = 0; PH.grounded = true; PH.hurt = 0;
  const got0 = (G.SOL && G.SOL.faces) || 0, out = { line: ${JSON.stringify(lineX)}, minV: 999, maxV: 0, air: 0, maxAir: 0, frames: 0, slow: 0, xMax: 0, wipe: 0 }; let last = performance.now(), L = null, Rk = null;
  const oc = console.log; const crashT = []; const t0 = performance.now();
  while (PH.z > -2260 && performance.now() - t0 < 40000) { await new Promise((r) => requestAnimationFrame(r)); const now = performance.now(), dt = now - last; last = now; out.frames++; if (dt > 50) out.slow++;
    const t = (-1440 - PH.z) / 720, tx = window.__BASINX(${lineX === 'left' ? -1 : lineX === 'right' ? 1 : 0}, PH.z - Math.hypot(PH.vx, PH.vz) * .4);
    const px = PH.x + PH.vx * .5, want = px < tx - 4 ? 'ArrowRight' : px > tx + 4 ? 'ArrowLeft' : null; for (const k of ['ArrowLeft', 'ArrowRight']) set(k, k === want);
    const v = Math.hypot(PH.vx, PH.vz); if (t > .05 && t < .95) { out.minV = Math.min(out.minV, v); out.maxV = Math.max(out.maxV, v); } if (!PH.grounded) { out.air += dt / 1000; } out.xMax = Math.max(out.xMax, Math.abs(PH.x)); if (PH.hurt > 0.5) out.wipe++; if (out.frames % 45 === 0) (out.tr = out.tr || []).push([Math.round(PH.z), Math.round(PH.x), +(PH.y - G.th(PH.x, PH.z)).toFixed(1), PH.grounded ? 1 : 0, Math.round(v)]); }
  for (const k of ['ArrowLeft', 'ArrowRight']) set(k, false);
  out.minV = +out.minV.toFixed(1); out.maxV = +out.maxV.toFixed(1); out.air = +out.air.toFixed(2); out.xMax = Math.round(out.xMax); out.secs = +((performance.now() - t0) / 1000).toFixed(1); out.endZ = Math.round(PH.z); out.crystals = ((G.SOL && G.SOL.faces) || 0) - got0; out.got = JSON.stringify(G.SOL && G.SOL.got); out.msPerFrame = +((performance.now() - t0) / out.frames).toFixed(1); return out; })()`;
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  for (const basin of [true, false]) {
    await send('Page.navigate', { url: base + '?biome=desert&nointake=1&notap&nomusic&noshell&nocards&noufo' + (basin ? '&basin=1' : '') + '&t=' + Date.now() });
    let ok = false; for (let i = 0; i < 90; i++) { await sleep(1000); try { if (await ev('!!(window.__G && window.__G.PH && window.__G.SOL !== undefined)')) { ok = true; break; } } catch { } } if (!ok) { console.log('did not load'); continue; }
    await sleep(3000);
    try { await ev(`(async () => { const PH = __G.PH; PH.z = -760; for (let i = 0; i < 40; i++) await new Promise((r) => requestAnimationFrame(r)); })()`); } catch (e) { }          /* past -700 so the basin's content is placed */
    console.log(basin ? '\nWITH BASIN' : '\nWITHOUT BASIN (same stretch)');
    for (const line of basin ? (process.env.LINES || 'left,centre,right').split(',') : ['centre']) { try { { const o = await ev(DRIVE(line)); if (process.env.LIST) console.log(JSON.stringify(await ev(`((L) => [L.length, L.slice(0, 40)])(__G.SOL.list.map((o) => [o.kind, Math.round(o.x), Math.round(o.z), +(o.y - __G.th(o.x, o.z)).toFixed(1), o.got ? 1 : 0, o.m && !o.m.isDisposed() ? 1 : 0]))`))); const tr = o.tr; delete o.tr; console.log(JSON.stringify(o)); if (process.env.TRACE) console.log(JSON.stringify(tr)); } } catch (e) { console.log(line, 'ERR', String(e).slice(0, 300)); } }
  }
} finally { try { chrome.kill(); } catch { } process.exit(0); }
