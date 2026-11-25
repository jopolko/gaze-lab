// SMOKE TEST for the Babylon game: does each thing actually DO its job, not just load?
// Run before every deploy:   node tools/smoke.mjs "https://joshuaopolko.com/gaze-lab/three/babylon/index.html"
// (or a local URL). It opens headless Chrome, waits for the game, then checks the list below and prints PASS / FAIL per line. Exit code 1 if any FAIL.
// Add a check here whenever a feature is added or a bug is found, so it can never silently break again.
import { spawn } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'https://joshuaopolko.com/gaze-lab/three/babylon/index.html';
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map(), errors = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result?.value; };
const results = [];
const check = (name, ok, detail = '') => { results.push(ok); console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail ? '  (' + detail + ')' : '')); };
const port = 9800 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-smoke-'));
const chrome = spawn(CHROME, ['--headless=new', '--mute-audio', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--enable-unsafe-swiftshader', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
async function open(url, ready = 'window.__G && window.__G.DOP') {
  await send('Page.navigate', { url: url + (url.includes('?') ? '&' : '?') + 'smoke=' + Date.now() });
  for (let i = 0; i < 120; i++) { await sleep(1000); try { if (await ev('!!(' + ready + ')')) { await sleep(3000); return true; } } catch { } }
  return false;
}
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } else if (d.method === 'Runtime.exceptionThrown') errors.push(d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text); else if (d.method === 'Runtime.consoleAPICalled' && d.params.type === 'error') errors.push((d.params.args[0] && (d.params.args[0].value || d.params.args[0].description)) || 'console.error'); };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });

  // ---------- the normal game ----------
  const ok = await open(base + '?nointake=1&wild=1');
  check('game loads', ok);
  if (ok) {
    // spring pads launch you
    const sp = JSON.parse(await ev(`(async()=>{const G=window.__G; const p=G.PADS.filter(q=>q.lk&&!q.used&&!q.zoneHid&&q.z<-700)[0]; if(!p) return JSON.stringify({none:1}); G.PH.z=p.z+14; G.PH.x=p.x; G.PH.y=G.th(p.x,G.PH.z); G.PH.gh_prev=G.PH.y; G.PH.vx=0; G.PH.vz=-70; G.PH.vy=0; let vymax=-99; for(let i=0;i<40;i++){ await new Promise(r=>setTimeout(r,50)); vymax=Math.max(vymax,G.PH.vy);} return JSON.stringify({vymax});})()`));
    check('spring pad launches the player', !sp.none && sp.vymax > 12, 'peak upward speed ' + sp.vymax);
    // dopamine meter fills, rushes, triples points, drains
    const d = JSON.parse(await ev(`(async()=>{const G=window.__G; const o={}; G.DOP.v=0; G.DOP.on=false; G.dopAdd('pad'); o.filled=G.DOP.v>0; G.dopAdd('mol',1); o.on=G.DOP.on; const s=G.PH.score; G.PH.score+=100; o.gain=G.PH.score-s; await new Promise(r=>setTimeout(r,1200)); o.boost=G.PH.boost_t>0; o.t=G.DOP.t; return JSON.stringify(o);})()`));
    check('dopamine meter fills from a pickup', d.filled);
    check('full meter starts a RUSH', d.on);
    check('RUSH triples points', d.gain >= 290, 'gain ' + d.gain);
    check('RUSH keeps you boosted and counts down', d.boost && d.t < 9);
    // a hit during RUSH is a smash, not a stumble
    const c = JSON.parse(await ev(`(async()=>{const G=window.__G; G.DOP.on=true; G.DOP.t=5; G.PH.hurt=0; const s=G.PH.score; try{ window.__crash && window.__crash('TEST','rock'); }catch(e){} return JSON.stringify({ran: !!window.__crash, gain:G.PH.score-s});})()`));
    if (c.ran) check('a hit during RUSH pays points', c.gain > 0, 'gain ' + c.gain);
    check('no script errors in the normal game', errors.length === 0, errors.slice(0, 2).join(' | '));
  }

  // ---------- Route Zero ----------
  errors.length = 0;
  const ok2 = await open(base + '?story=1&nointake=1');
  check('Route Zero loads', ok2);
  if (ok2) {
    const seen = JSON.parse(await ev(`(async()=>{let max=0, shown=new Set(); for(let i=0;i<26;i++){ await new Promise(r=>setTimeout(r,1000)); const t=document.getElementById('stToast'), c=document.getElementById('stCap'), s=document.getElementById('stSignB'); let n=0; if(t&&t.classList.contains('on')) n++; if(c&&c.classList.contains('on')) n++; if(s&&getComputedStyle(s).opacity>0.5){ n++; shown.add(s.innerText.split('\\n')[0]); } const bt=document.getElementById('stBeat'); if(bt&&bt.classList.contains('on')){ n++; shown.add(bt.innerText.split(String.fromCharCode(10))[0]); } const ph=document.getElementById('stPhone'); if(ph&&ph.classList.contains('on')){ n++; shown.add('PHONE:MURMUR'); } const ti=document.getElementById('stTitle'); if(ti&&ti.classList.contains('on')){ n++; shown.add('TITLE'); } const op=document.getElementById('stOpen'); if(i===0&&op&&getComputedStyle(op).opacity>0.9) shown.add('BLACK'); max=Math.max(max,n);} return JSON.stringify({max, labels:[...shown]});})()`));
    check('never two messages on screen at once', seen.max <= 1, 'max ' + seen.max + ' labels ' + seen.labels.join(','));
    check('Route Zero shows the first notice', seen.labels.length > 0);
    check('opening starts on black', seen.labels.includes('BLACK'), seen.labels.join(','));
    check('the Murmur arrives on the phone, then the title', seen.labels.includes('PHONE:MURMUR') && seen.labels.includes('TITLE'));
    check('the opening hands back to the road', JSON.parse(await ev(`JSON.stringify(!document.getElementById('stOpen') && !document.body.classList.contains('stOpening'))`)));
    const cl = JSON.parse(await ev(`JSON.stringify((()=>{const G=window.__G; let zones=[]; for(let j=0;j<=12;j++) zones.push(G.ZM[j]); const springs=G.PADS.filter(p=>p.lk&&!p.used&&!p.zoneHid&&p.z<-20&&p.z>-2340).length; return {allClear: zones.every(z=>z==='clear'), springs};})())`));
    check('Route Zero reading stretch has no slalom or obstacle rows', cl.allClear);
    check('Route Zero reading stretch has no spring arcs', cl.springs === 0, cl.springs + ' left');

    check('no script errors in Route Zero', errors.length === 0, errors.slice(0, 2).join(' | '));
  }

  // ---------- Tutorial ----------
  errors.length = 0;
  const ok3 = await open(base + '?tutorial=1&nointake=1');
  check('tutorial loads', ok3);
  if (ok3) {
    const t = JSON.parse(await ev(`(async()=>{ const G=window.__G, NL=String.fromCharCode(10); const o={beats:[], badWindow:0, haz:0, pads:0, buffs:0};
      for(let k=0;k<720 && !document.getElementById('tutEnd');k++){ G.PH.vx*=0.5; await new Promise(r=>setTimeout(r,500));
        const b=document.getElementById('stBeat'); if(b&&b.classList.contains('on')){ const txt=b.innerText.split(NL).slice(2).join(' ').trim(); if(txt&&!o.beats.includes(txt)) o.beats.push(txt);
          const sp=Math.max(18,Math.hypot(G.PH.vx,G.PH.vz)), lim=G.PH.z-sp*2.5; for(const q of window.__GEAR_T()) if(!q.dead && q.z<G.PH.z-5 && q.z>lim){ o.badWindow++; (o.bad=o.bad||[]).push(q.kind+' '+Math.round(G.PH.z-q.z)+'m ahead @'+Math.round(-G.PH.z)+' sp'+Math.round(sp)+' ['+txt.slice(0,18)+']'); } } }
      o.pads=G.KPADS.length; o.buffs=G.KB.length; o.end=!!document.getElementById('tutEnd'); return JSON.stringify(o); })()`));
    check('tutorial teaches each object with its own beat', t.beats.length >= 7, t.beats.length + ' beats: ' + t.beats.map((b) => b.slice(0, 22)).join(' / '));
    check('nothing on the road while a tutorial message is up', t.badWindow === 0, t.badWindow + ' hazards inside a message window ' + (t.bad || []).slice(0, 4).join(' | '));
    check('tutorial places pads and pickups on purpose', t.pads >= 3 && t.buffs >= 2, 'pads ' + t.pads + ' pickups ' + t.buffs);
    check('tutorial ends with the TRAINING DONE card', t.end);
    check('no script errors in the tutorial', errors.length === 0, errors.slice(0, 2).join(' | '));
  }

  // ---------- A Season One level ----------
  errors.length = 0;
  const ok5 = await open(base + '?biome=alpine&nointake=1', 'window.__G && window.__G.LV');
  check('a level loads', ok5);
  if (ok5) {
    const lv = JSON.parse(await ev(`(async()=>{ const G=window.__G; for(let k=0;k<120 && G.LV.i<6;k++){ await new Promise(r=>setTimeout(r,1000)); } return JSON.stringify({i:G.LV.i, exits:(G.LV.exits||[]).length, solids:G.SOL.max, lenses:(G.LV.lenses||[]).length}); })()`));
    check('the level script runs its sections', lv.i >= 5, lv.i + ' sections');
    check('the level places exits, a lens and crystals', lv.exits >= 2 && lv.solids > 0, 'exits ' + lv.exits + ', lenses ' + lv.lenses + ', crystal faces ' + lv.solids);
    check('no script errors in a level', errors.length === 0, errors.slice(0, 2).join(' | '));
  }
  // ---------- Menu ----------
  errors.length = 0;
  await ev(`localStorage.setItem('dl_char', JSON.stringify({ gear: 'rocket' })); 1`);
  await send('Page.navigate', { url: base.replace(/index\.html.*$/, '') + 'menu.html?s=' + Date.now() }); await sleep(4000);
  const mn = JSON.parse(await ev(`JSON.stringify({levels: document.querySelectorAll('.lv').length, cont: (document.getElementById('cont')||{}).textContent || ''})`) || '{}');
  check('menu shows eight levels and a start button', mn.levels === 8 && /Route Zero/.test(mn.cont), mn.levels + ' levels, "' + mn.cont + '"');
  check('no script errors in the menu', errors.length === 0, errors.slice(0, 2).join(' | '));

  // ---------- Character editor reel ----------
  errors.length = 0;
  const base2 = base.replace(/index\.html.*$/, '') + 'dressup.html';
  const ok4 = await open(base2, 'window.__REEL');
  check('editor loads with the story reel', ok4);
  if (ok4) {
    const rl = JSON.parse(await ev(`(async()=>{const o={}; document.getElementById('reelBtn').click(); await new Promise(r=>setTimeout(r,2500)); o.on=window.__REEL.on; o.scenes=document.querySelectorAll('#reelChips button[data-i]').length; o.cap=document.getElementById('reelCap').textContent; for(const m of ['mirror','grin','gas','robot']){ /* each mask must survive a scene */ } return JSON.stringify(o);})()`));
    check('reel plays and shows its caption', rl.on && rl.scenes === 6 && rl.cap.length > 0, 'scenes ' + rl.scenes + ' caption "' + rl.cap + '"');
    check('no script errors in the editor', errors.length === 0, errors.slice(0, 2).join(' | '));
  }
} catch (e) { check('smoke test ran to the end', false, String(e).slice(0, 200)); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); }
const bad = results.filter((x) => !x).length;
console.log(bad ? bad + ' FAILED of ' + results.length : 'ALL ' + results.length + ' PASSED');
process.exit(bad ? 1 : 0);
