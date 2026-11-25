// CATCH CHECK: does every rail catch you and every spring arc (spiral / tube) pick you up?
//   node tools/catchcheck.mjs [base url] [worlds...]
//   e.g. node tools/catchcheck.mjs http://localhost:8090/babylon/index.html alpine candy tunnel
// For each rail and each spring-arc pad ahead, it puts the car 60 m before it, lined up and at ground speed, lets the real game run for up to 4 s
// (real frames in headless Chrome), and records whether the game caught it (PH.rail for rails, toys' S.lk for arcs).
// Also prints why a miss happened (how far off line and how high above or below the rail the car was when it passed).
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'http://localhost:8090/babylon/index.html';
const worlds = process.argv.slice(3).length ? process.argv.slice(3) : ['alpine', 'candy', 'tunnel'];
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description)); return r.result.value; };
const port = 9600 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-catch-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', 'about:blank'], { stdio: 'ignore' });
let total = 0, caught = 0;
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  for (const w of worlds) {
    await send('Page.navigate', { url: base + '?biome=' + w + '&nointake=1&notap&nomusic&noshell&nocards&noufo&t=' + Date.now() });
    let ok = false; for (let i = 0; i < 90; i++) { await sleep(1000); try { if (await ev('!!(window.__G && window.__G.RAILS && window.__G.PADS)')) { ok = true; break; } } catch { } } if (!ok) { console.log(w + ': did not load'); continue; }
    await sleep(3000);
    const list = await ev(`(() => { const G = __G; return { rails: G.RAILS.map((f, i) => ({ i, za: f.za, zb: f.zb, sd: f.sd })), arcs: G.PADS.map((p, i) => ({ i, z: p.z, x: p.x, lk: !!p.lk, used: p.used })).filter((p) => p.lk) }; })()`);
    console.log('\n' + w + ': ' + list.rails.length + ' rails, ' + list.arcs.length + ' spring arcs');
    const test = async (kind, it) => {
      const r = await ev(`(async () => { const G = __G, PH = G.PH, T = G.toys(); const isR = ${kind === 'rail'};
        const f = isR ? G.RAILS[${it.i}] : null, p = isR ? null : G.PADS[${it.i}]; if (f) f.done = false; if (p) p.used = false;
        const z0 = (isR ? f.za : p.z) + 60, x0 = isR ? G.featX(f, z0) : p.x; PH.rail = null; PH.hurt = 0; PH.z = z0; PH.x = x0; PH.y = G.th(x0, z0) + .3; PH.vx = 0; PH.vz = -30; PH.vy = 0; PH.heading = 0; PH.grounded = true; if (T && T.state) T.state.lk = null;
        let closest = null; const t0 = performance.now();
        while (performance.now() - t0 < 4000) { await new Promise((r) => requestAnimationFrame(r));
          if (isR && PH.rail === f) return { ok: true, after: +(performance.now() - t0).toFixed(0) };
          if (!isR && T.state.lk) return { ok: true, after: +(performance.now() - t0).toFixed(0) };
          const zt = isR ? f.za : p.z; if (closest === null && PH.z <= zt) closest = isR ? { dx: +(PH.x - G.featX(f, PH.z)).toFixed(1), dy: +(PH.y - G.railY(f, PH.z)).toFixed(1), rail: PH.rail ? 'other' : null, hurt: +PH.hurt.toFixed(2) } : { dx: +(PH.x - p.x).toFixed(1), above: +(PH.y - G.th(PH.x, PH.z)).toFixed(1), rail: !!PH.rail, used: p.used };
          if (PH.z < (isR ? f.zb : p.z - 40)) break; }
        return { ok: false, at: closest }; })()`);
      total++; if (r.ok) caught++; console.log('  ' + (r.ok ? 'CAUGHT ' : 'MISSED ') + kind + ' ' + it.i + ' at z ' + Math.round(isFinite(it.za) ? it.za : it.z) + (r.ok ? '  (after ' + r.after + ' ms)' : '  ' + JSON.stringify(r.at)));
    };
    for (const it of list.rails.slice(0, 8)) await test('rail', it);
    for (const it of list.arcs.slice(0, 8)) await test('arc', it);
  }
  console.log('\n' + caught + ' of ' + total + ' caught');
} catch (e) { console.log('ERROR ' + e.message); }
finally { try { chrome.kill(); } catch { } process.exit(0); }
