// WHAT'S THERE: drives (warps) to given distances on a level and names every object visible on screen (mesh, class, material, node path), with a screenshot per stop.
//   node tools/whatsthere.mjs "<url>" -300 -700 -1100 ...
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, ...zs] = process.argv.slice(2); const STOPS = zs.length ? zs.map(Number) : [-300, -700, -1100];
const out = 'stills/probe'; mkdirSync(out, { recursive: true });
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) return 'EXC ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text); return r.result?.value; };
const port = 9300 + Math.floor(Math.random() * 120), dir = mkdtempSync(join(tmpdir(), 'dl-probe-'));
const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--use-gl=angle', '--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
const PROBE = `(async()=>{ const sc=BABYLON.EngineStore.LastCreatedScene, e=sc.getEngine(), W=e.getRenderWidth(), H=e.getRenderHeight(), G=window.__G, hits={};
  for(let gx=0.03;gx<1;gx+=0.035) for(let gy=0.15;gy<0.95;gy+=0.035){ const p=sc.pick(W*gx,H*gy,(m)=>m.isEnabled()&&m.isVisible&&m.name!=='sky'&&m.name!=='tdome'); if(!p||!p.hit||!p.pickedMesh) continue; const m=p.pickedMesh, mt=m.__meta||{};
    let node=''; try{ if(p.thinInstanceIndex>=0 && G.ANREC){ const rc=G.ANREC.find(q=>q.s===m && q.idx===p.thinInstanceIndex); if(rc) node=String(rc.n||rc.name||rc.path||'').slice(0,60); } }catch(err){}
    const key=m.name+' | '+(mt.meshClass||'')+' | '+(m.material?m.material.name.slice(0,24):'')+(node?' | '+node:''); if(!hits[key]) hits[key]={n:0, d:Math.round(p.distance), y:+(p.pickedPoint.y-G.th(p.pickedPoint.x,p.pickedPoint.z)).toFixed(1), dx:Math.round(p.pickedPoint.x-G.trailX(p.pickedPoint.z))}; hits[key].n++; }
  return JSON.stringify({z:Math.round(G.PH.z), hits:Object.entries(hits).filter(([k])=>!/^src \\| ArrayMesh/.test(k)||true).sort((a,b)=>b[1].n-a[1].n).slice(0,24)}); })()`;
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } };
  await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: url + (url.includes('?') ? '&' : '?') + 'pr=' + Date.now() });
  for (let i = 0; i < 240; i++) { await sleep(250); if (await ev('!!(window.__G && window.__G.DOP)')) break; }
  await sleep(18000);
  for (const z of STOPS) {
    await ev(`(()=>{ const G=window.__G; G.warp(${z}); G.PH.vz=-1; G.PH.vx=0; return 1; })()`); await sleep(2500);
    const shot = await send('Page.captureScreenshot', { format: 'jpeg', quality: 80 }); writeFileSync(join(out, 'z' + (-z) + '.jpg'), Buffer.from(shot.result.data, 'base64'));
    const r = await ev(PROBE); console.log('=== stop ' + z); console.log(typeof r === 'string' ? r : JSON.stringify(r));
  }
} catch (e) { console.log('ERROR ' + e); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
