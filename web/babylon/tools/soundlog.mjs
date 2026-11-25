// SOUND LOG: every sound a level starts, from page load to a few seconds after the start card's tap, with what started it.
//   node tools/soundlog.mjs [base url] [query]      e.g. node tools/soundlog.mjs http://localhost:8090/babylon/index.html "biome=alpine"
// Catches sounds queued while the audio is still locked (they all play the moment the tap unlocks it).
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'http://localhost:8090/babylon/index.html', q = process.argv[3] || 'biome=alpine';
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text); return r.result.value; };
const port = 9400 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-snd-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', 'about:blank'], { stdio: 'ignore' });
const HOOK = `(() => { window.__snd = []; const t0 = performance.now(); const tag = (kind, node) => { const st = (new Error().stack || '').split('\\n').slice(1, 9).map((l) => l.trim().replace(/https?:\\/\\/[^/]+/, '')).join(' < '); let ctxState = '?'; try { ctxState = node.context.state; } catch (e) { } window.__snd.push({ at: +((performance.now() - t0) / 1000).toFixed(2), kind, ctx: ctxState, go: !!window.__go, from: st }); };
  for (const P of [AudioScheduledSourceNode.prototype, AudioBufferSourceNode.prototype, OscillatorNode.prototype]) { if (!Object.prototype.hasOwnProperty.call(P, 'start')) continue; const s0 = P.start; P.start = function (...a) { if (!(this instanceof ConstantSourceNode) && !(this instanceof OscillatorNode)) tag(this.constructor.name + (this.buffer ? ' ' + this.buffer.duration.toFixed(2) + 's' : '') + ' when=' + (a[0] === undefined ? 'now' : (a[0] - this.context.currentTime).toFixed(2) + 's ahead'), this); return s0.apply(this, a); }; }
  const M = HTMLMediaElement.prototype, p0 = M.play; M.play = function () { tag('media ' + (this.currentSrc || this.src).split('/').pop(), { context: { state: 'media' } }); return p0.apply(this, arguments); }; })();`;
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.addScriptToEvaluateOnNewDocument', { source: HOOK });
  await send('Page.navigate', { url: base + '?' + q + '&nointake=1&noshell&t=' + Date.now() });
  let ok = false; for (let i = 0; i < 90; i++) { await sleep(1000); try { if (await ev('!!document.getElementById("goCard")')) { ok = true; break; } } catch { } } if (!ok) throw new Error('no start card');
  await sleep(4000); const keep = setInterval(() => { }, 1000);
  const before = await ev('window.__snd.length'); console.log('loaded; sounds so far ' + before);
  // the tap: a real input event on the card's first button
  const r = await ev('(() => { const b = document.querySelector("#goCard button"); const q = b.getBoundingClientRect(); return [q.left + q.width / 2, q.top + q.height / 2]; })()');
  for (const type of ['mousePressed', 'mouseReleased']) await send('Input.dispatchMouseEvent', { type, x: r[0], y: r[1], button: 'left', clickCount: 1 });
  await sleep(300); console.log('tapped; started=' + await ev('!!window.__go') + ' z=' + await ev('window.__G ? __G.PH.z.toFixed(1) : null')); if (!(await ev('!!window.__go'))) { await ev('document.querySelector("#goCard button").click()'); console.log('clicked by script; started=' + await ev('!!window.__go')); } await sleep(5000); console.log('z after 5s ' + await ev('window.__G ? __G.PH.z.toFixed(1) : null'));
  const list = await ev('JSON.parse(JSON.stringify(window.__snd))'); clearInterval(keep);
  console.log('sounds before the tap: ' + before + ', total: ' + list.length);
  for (const s of list) console.log((s.go ? 'after ' : 'BEFORE') + ' tap  t=' + s.at + 's  ' + s.kind + '  ctx=' + s.ctx + '\n        ' + s.from);
} catch (e) { console.log('ERROR ' + e.message); }
finally { try { chrome.kill(); } catch { } process.exit(0); }
