// LAYOUT CHECK for the game's text screens (the cold open, the start card, the noodle stall, the Rail Rating) and the on-screen readouts while playing.
// It opens the game in a separate headless Chrome at several phone and tablet sizes (and, for the cold open, with reduced motion both off and on), waits until the screen is really visible and on top,
// and looks for two faults: (1) visible text that overlaps other visible text, (2) text that runs off the screen. It saves a screenshot per size and prints PASS or FAIL.
// RUN IT BEFORE ANY DEPLOY THAT TOUCHES AN OVERLAY OR A READOUT, and LOOK at the screenshots (a checker can miss things).
//   node web/tools/layout_check.mjs <mode> "<url>" [outdir]
//   mode: cold    the cold open (samples every 0.4 s while it plays; reduced motion off and on)
//         card    the start card (needs &head in the url)
//         stall   the noodle stall (&pilot; calls __nextBiome once the game is ready)
//         rating  the Rail Rating (the stall, then its button)
//         hud     the on-screen readouts while playing (fps, speed, biome tag, meters)
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [mode, url, outdir = '.'] = process.argv.slice(2);
if (!mode || !url) { console.log('usage: node layout_check.mjs <cold|card|stall|rating|hud> "<url>" [outdir]'); process.exit(2); }
mkdirSync(outdir, { recursive: true });
const SIZES = [[375, 812, 'portrait-375x812'], [412, 915, 'portrait-412x915'], [320, 568, 'small-320x568'], [924, 412, 'landscape-924x412'], [800, 600, 'tablet-800x600']];
const MARK = { cold: 'MERIDIAN', card: 'TAP TO START', stall: 'NOODLES', rating: 'SUBJECT', hud: '', dmenu: 'DERBY', dend: 'LAST CAR STANDING', dhud: 'CARS LEFT', cmenu: 'DOWNFALL', cend: 'LEG 1 COMPLETE', chud: 'CONTESTANTS', cfin: 'THE LAST COPY SURVIVES', cintro: 'CONTINUE' }[mode];
const port = 9300 + Math.floor(Math.random() * 500), dir = mkdtempSync(join(tmpdir(), 'dh3-lay-'));
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--autoplay-policy=no-user-gesture-required', '--no-first-run', '--ignore-gpu-blocklist', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map();
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
const GAMEWIN = `(function(){var f=document.getElementById('g');return (f&&f.contentWindow)||window})()`;
// inside the page: the marker's overlay (the outermost fixed-position ancestor of the marker text), whether it is visible and on top, and the visible-text boxes inside it that overlap or run off screen
const PAGE = `(function(MK){
  var f=document.getElementById('g'), W=(f&&f.contentWindow)||window, d=W.document;
  function vis(e){ var op=1,p=e; while(p&&p.nodeType===1){ var cs=W.getComputedStyle(p); if(cs.display==='none'||cs.visibility==='hidden') return 0; op*=parseFloat(cs.opacity||1); p=p.parentElement; } return op; }
  var ROOT=d.body, hit=null;
  if(MK){ var all=[].slice.call(d.querySelectorAll('body *')); hit=all.filter(function(e){return [].slice.call(e.childNodes).some(function(n){return n.nodeType===3&&n.textContent.indexOf(MK)>=0})})[0];
    if(!hit) return {state:'absent'}; var p=hit; while(p&&p!==d.body){ if(W.getComputedStyle(p).position==='fixed') ROOT=p; p=p.parentElement; }
    var hr=hit.getBoundingClientRect(), top=d.elementFromPoint(Math.min(W.innerWidth-1,Math.max(0,hr.left+hr.width/2)),Math.min(W.innerHeight-1,Math.max(0,hr.top+hr.height/2)));
    var pe=W.getComputedStyle(hit).pointerEvents; if(pe!=='none' && (!top||!ROOT.contains(top))) return {state:'covered'}; }
  var els=[].slice.call(ROOT.querySelectorAll('*')).filter(function(e){ if(['SCRIPT','STYLE','SVG','PATH','CANVAS'].indexOf(e.tagName.toUpperCase())>=0) return false; var own=[].slice.call(e.childNodes).some(function(n){return n.nodeType===3&&n.textContent.trim().length>1}); if(!own) return false; if(vis(e)<.25) return false; var r=e.getBoundingClientRect(); return r.width>3&&r.height>3; });
  var R=[]; els.forEach(function(e){ [].slice.call(e.getClientRects()).forEach(function(q){ if(q.width>3&&q.height>3) R.push({e:e,r:q,t:(e.textContent||'').trim().slice(0,28)}); }); }); var out={state:'ok',overlaps:[],offscreen:[],n:R.length,vw:W.innerWidth,vh:W.innerHeight};
  for(var i=0;i<R.length;i++){ var a=R[i].r; if(a.left<-1||a.right>W.innerWidth+1||a.top<-1||a.bottom>W.innerHeight+1) out.offscreen.push(R[i].t);
    for(var j=i+1;j<R.length;j++){ if(R[i].e===R[j].e||R[i].e.contains(R[j].e)||R[j].e.contains(R[i].e)) continue; var b=R[j].r, w=Math.min(a.right,b.right)-Math.max(a.left,b.left), h=Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top); if(w>3&&h>3){ var sm=Math.min(a.width*a.height,b.width*b.height); if(w*h>.12*sm) out.overlaps.push(R[i].t+' <> '+R[j].t); } } }
  return out; })(${JSON.stringify(MARK)})`;
const inspect = async () => ev(`JSON.stringify(${PAGE})`).then((x) => (x ? JSON.parse(x) : { state: 'error' }));
let failed = 0;
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const dd = JSON.parse(m.data); if (dd.id && wait.has(dd.id)) { wait.get(dd.id)(dd); wait.delete(dd.id); } };
  await send('Page.enable');
  for (const rm of mode === 'cold' ? [0, 1] : [0]) for (const [w, h, size] of SIZES) {
    const name = size + (rm ? '-reduced-motion' : '');
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: w < 700 });
    await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: rm ? 'reduce' : 'no-preference' }] });
    await send('Page.navigate', { url: url + (url.includes('?') ? '&' : '?') + 'coldagain&lc=' + Date.now() });
    let r = { state: 'absent' };
    if (mode === 'stall' || mode === 'rating') { for (let i = 0; i < 150; i++) { await sleep(1000); if (await ev(`!!(${GAMEWIN}).__PX`)) break; } await sleep(1500); await ev(`(${GAMEWIN}).__nextBiome()`); await sleep(1500); if (mode === 'rating') { await ev(`(function(){var b=(${GAMEWIN}).document.getElementById('nzRate'); if(b) b.click(); return 1})()`); await sleep(1500); } }
    if (mode === 'dend') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__derby)')) break; } await sleep(800); await ev('window.__derby.endCard(true)'); await sleep(600); }
    if (mode === 'dhud') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__derby && window.__derby.S.mode==="play")')) break; } await sleep(1500); }
    if (mode === 'cend') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__cross)')) break; } await sleep(800); await ev('window.__cross.complete()'); await sleep(600); }
    if (mode === 'cfin') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__cross)')) break; } await sleep(800); await ev('window.__cross.startLeg(1); window.__cross.complete()'); await sleep(2300); }
    if (mode === 'cintro') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__cross)')) break; } await sleep(800); await ev('[...document.querySelectorAll(".btn")].find(b=>b.textContent.includes("TOUCH")).click()'); await sleep(600); }
    if (mode === 'chud') { for (let i = 0; i < 100; i++) { await sleep(500); if (await ev('!!(window.__cross && window.__cross.S.mode==="play")')) break; } await sleep(1500); }
    if (mode === 'hud') { for (let i = 0; i < 150; i++) { await sleep(1000); if (await ev(`!!(${GAMEWIN}).__rdy`)) break; } await sleep(6000); }
    for (let i = 0; i < 150; i++) { r = await inspect(); if (r.state === 'ok') break; await sleep(400); }
    if (r.state !== 'ok') { console.log('FAIL ' + name + ': the screen never became visible and on top (' + r.state + ')'); failed++; continue; }
    const worst = { overlaps: new Set(), offscreen: new Set() }; let shots = 0;
    const samples = mode === 'cold' ? 26 : 1;
    for (let s = 0; s < samples; s++) {
      const q = mode === 'cold' ? await inspect() : r;
      if (q.state === 'ok') { q.overlaps.forEach((x) => worst.overlaps.add(x)); q.offscreen.forEach((x) => worst.offscreen.add(x)); }
      if (shots < 3 && (mode !== 'cold' || [5, 12, 19].includes(s))) { shots++; const sh = await send('Page.captureScreenshot', { format: 'jpeg', quality: 70 }); writeFileSync(join(outdir, mode + '-' + name + '-' + shots + '.jpg'), Buffer.from(sh.result.data, 'base64')); }
      if (mode === 'cold') await sleep(400);
    }
    const bad = worst.overlaps.size + worst.offscreen.size;
    console.log((bad ? 'FAIL ' : 'PASS ') + name + (bad ? '  overlaps: ' + [...worst.overlaps].slice(0, 6).join(' | ') + '  offscreen: ' + [...worst.offscreen].slice(0, 6).join(' | ') : ''));
    if (bad) failed++;
  }
} catch (e) { console.log('ERR ' + e); failed++; } finally { try { ws && ws.close(); } catch {} chrome.kill(); }
console.log(failed ? 'LAYOUT CHECK FAILED (' + failed + ')' : 'LAYOUT CHECK PASSED');
process.exit(failed ? 1 : 0);
