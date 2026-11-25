// LEVEL AUDIT: every level, headless (muted). For each: what objects exist (pickups, orbs, pads, rails, ramps, rings, toys, crystals), whether rails
// carry you to their end and where they let you off, whether the trail is continuous, what stands in the road that is not a game object (stray posts),
// whether anything collectible is out of reach, and how much of the screen is black along the course.
//   node tools/audit.mjs [baseUrl] [biome,biome,...]
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const base = process.argv[2] || 'http://127.0.0.1:8091/babylon/index.html';
const LEVELS = (process.argv[3] || 'story,psychedelic,alpine,candy,egypt,tunnel,desert,matrix,synthwave').split(',');
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0; const wait = new Map(), errors = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; wait.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (e) => { const r = (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result?.value; };
const port = 9800 + Math.floor(Math.random() * 150), dir = mkdtempSync(join(tmpdir(), 'dl-audit-'));
const chrome = spawn(CHROME, ['--headless=new', '--mute-audio', '--remote-debugging-port=' + port, '--user-data-dir=' + dir, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--use-gl=angle', '--enable-unsafe-swiftshader', '--window-size=924,412', 'about:blank'], { stdio: 'ignore' });
const OUT = {};
try {
  let targets; for (let i = 0; i < 40; i++) { try { targets = await (await fetch('http://127.0.0.1:' + port + '/json')).json(); break; } catch { await sleep(250); } }
  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && wait.has(d.id)) { wait.get(d.id)(d); wait.delete(d.id); } else if (d.method === 'Runtime.exceptionThrown') errors.push(d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text); };
  await send('Runtime.enable'); await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 924, height: 412, deviceScaleFactor: 1, mobile: false });
  for (const L of LEVELS) {
    errors.length = 0;
    const q = L === 'story' ? 'story=1' : 'biome=' + L;
    await send('Page.navigate', { url: base + '?' + q + '&nointake=1&noshell&nomusic&notap&a=' + Date.now() });
    let ok = false; for (let i = 0; i < 90; i++) { await sleep(1000); try { if (await ev('!!(window.__G && window.__G.PH && window.__G.LV)')) { ok = true; break; } } catch { } }
    if (!ok) { OUT[L] = { error: 'did not load' }; console.log(L, 'DID NOT LOAD'); continue; }
    await sleep(2500);
    // 1. build every row by passing through the course (warp in steps), then count what exists
    const r = JSON.parse(await ev(`(async()=>{ const G=window.__G, PH=G.PH, o={};
      const END=Math.min(...Object.keys(G.phys.rows).map(Number))*0; let zMin=0; for(const k in G.phys.rows) zMin=Math.min(zMin,-180*(+k+1));
      o.courseLen=-zMin;
      // trail continuity and ground steps along the road
      o.trailJumps=[]; o.groundSteps=[]; let px=G.trailX(-2), py=G.th(px,-2);
      for(let z=-4; z>zMin+20; z-=2){ const x=G.trailX(z), y=G.th(x,z); if(Math.abs(x-px)>1.2) o.trailJumps.push([Math.round(-z),+(x-px).toFixed(1)]); if(Math.abs(y-py)>1.6) o.groundSteps.push([Math.round(-z),+(y-py).toFixed(1)]); px=x; py=y; }
      o.trailJumps=o.trailJumps.slice(0,12); o.groundSteps=o.groundSteps.slice(0,12);
      // raw data in the level dump, per kind
      const raw={}; for(const k in G.phys.rows){ const rr=G.phys.rows[k]; for(const key of ['obs','pads','buffs','orbs','toys','feats','airrings','trees']){ const a=rr[key]; if(!a) continue; for(const it of a){ const kk=key+(it.kind?':'+it.kind:''); raw[kk]=(raw[kk]||0)+1; } } } o.raw=raw;
      // pass through so every row builds
      for(let z=-20; z>zMin+60; z-=120){ G.warp(z); await new Promise(r=>setTimeout(r,160)); }
      G.warp(-20); await new Promise(r=>setTimeout(r,400));
      o.live={ pads:G.PADS.length, padsHidden:G.PADS.filter(p=>p.zoneHid).length, kpads:G.KPADS.length, buffs:G.BUFFS.length, buffsHidden:G.BUFFS.filter(b=>b.zoneHid||b.on===false).length, orbs:G.ORBS.length, kb:G.KB.length, rails:G.RAILS.length, toys:(G.toys()||[]).length, solids:G.SOL.max||0, exits:(G.LV.exits||[]).length, lenses:(G.LV.lenses||[]).length, zones:Object.values(G.ZM||{}).reduce((a,z)=>(a[z]=(a[z]||0)+1,a),{}) };
      // unreachable collectibles: far off the road or high above the ground
      o.unreach=[]; const chk=(kind,x,y,z)=>{ const gx=G.th(x,z), off=Math.abs(x-G.trailX(z)); if(off>45||y-gx>14) o.unreach.push(kind+' z'+Math.round(-z)+' off'+Math.round(off)+' up'+Math.round(y-gx)); };
      for(const b of G.BUFFS) if(!b.zoneHid&&b.on!==false&&Number.isFinite(b.x)) chk('pickup',b.x,b.y??G.th(b.x,b.z),b.z);
      for(const b of G.ORBS) if(Number.isFinite(b.x)) chk('orb',b.x,b.y??G.th(b.x,b.z),b.z);
      o.unreachN=o.unreach.length; o.unreach=o.unreach.slice(0,10);
      return JSON.stringify(o); })()`));
    // 2. rails: ride each one hands-off and see how it lets you off
    const rails = process.env.FAST ? [] : JSON.parse(await ev(`(async()=>{ const G=window.__G, PH=G.PH, out=[];
      for(const f of G.RAILS.slice(0,40)){ f.done=false; G.warp(f.za+3); PH.x=G.featX(f,PH.z); PH.y=G.railY(f,PH.z)+.5; PH.gh_prev=G.th(PH.x,PH.z); PH.vz=-55; PH.vx=0; PH.vy=0; PH.hurt=0; PH.rail=null;
        let got=false, how='never mounted', maxOff=0, endZ=null, endX=null, startZ=null;
        for(let i=0;i<220;i++){ await new Promise(r=>setTimeout(r,33)); if(PH.rail===f){ if(!got){got=true; startZ=PH.z;} maxOff=Math.max(maxOff,Math.abs(PH.x-G.featX(f,PH.z))); } else if(got){ endZ=PH.z; endX=PH.x; how = PH.z<=f.zb+1 ? 'end' : 'dropped early'; break; } }
        if(got&&endZ===null) how='still riding';
        out.push({za:Math.round(-f.za), zb:Math.round(-f.zb), len:Math.round(f.za-f.zb), side:f.sd, mat:f.mat, how, rode: got&&endZ!==null ? Math.round(startZ-endZ) : 0, offAt: endZ!==null ? Math.round(-endZ) : null, dxAtEnd: endZ!==null ? +(endX-G.featX(f,endZ)).toFixed(1) : null, maxOff:+maxOff.toFixed(1)}); }
      return JSON.stringify(out); })()`));
    // 3. stray posts: dump pieces (not ground, not trees, not backdrop) standing on the road surface
    const posts = JSON.parse(await ev(`(()=>{ const G=window.__G, B=BABYLON, sc=B.Engine.LastCreatedScene||BABYLON.EngineStore.LastCreatedScene, out={}, list=[];
      const half=(G.TUNE&&0)||11; for(const m of sc.meshes){ if(m.name!=='src'||!m.__m||m.__cat==='ground'||m.__cat==='veg'||m.__cat==='back') continue; m.refreshBoundingInfo&&m.refreshBoundingInfo(); const bb=m.getBoundingInfo().boundingBox, ex=bb.extendSize; const tall=ex.y*2, wide=Math.max(ex.x,ex.z)*2;
        for(let i=0;i<m.__m.length/16;i++){ const x=m.__m[i*16+12], y=m.__m[i*16+13], z=m.__m[i*16+14], sy=Math.hypot(m.__m[i*16+4],m.__m[i*16+5],m.__m[i*16+6]); const off=Math.abs(x-G.trailX(z)); if(off>half+1) continue;
          const gy=G.th(x,z); if(y+ (bb.maximum.y)*sy < gy+.3) continue; const key=(m.__meta&&m.__meta.meshClass)+' '+(m.__meta&&m.__meta.matId)+' '+((m.__nm&&m.__nm[i])||'').replace(/@?[0-9]+/g,'#').slice(-40)+' h'+(tall*sy).toFixed(1)+' w'+wide.toFixed(1)+(m.isEnabled()?'':' (hidden)');
          out[key]=(out[key]||0)+1; if(list.length<30) list.push(key+' @z'+Math.round(-z)+' off'+off.toFixed(1)); } }
      return JSON.stringify({kinds:out, sample:list}); })()`));
    // 4. black screen: frames along the course, share of near-black pixels
    const shots = [];
    const zMax = r.courseLen || 6000;
    for (const z of [300, 1200, 2400, 3600, 4800, 6000].filter((v) => v < zMax - 100)) {
      await ev(`(()=>{const G=window.__G; G.warp(-${z}); G.PH.vz=-40; return 1;})()`); await sleep(1500);
      const png = (await send('Page.captureScreenshot', { format: 'png' })).result.data;
      const black = await ev(`(async()=>{ const im=new Image(); im.src='data:image/png;base64,${png}'; await im.decode(); const c=document.createElement('canvas'); c.width=231; c.height=103; const x=c.getContext('2d'); x.drawImage(im,0,0,231,103); const d=x.getImageData(0,0,231,103).data; let n=0, bot=0; for(let i=0;i<d.length;i+=4){ const k=d[i]+d[i+1]+d[i+2]; if(k<24){ n++; if(i/4/231>51) bot++; } } return JSON.stringify({all:+(n/(231*103)).toFixed(2), lower:+(bot/(231*52)).toFixed(2)}); })()`);
      shots.push({ z, ...JSON.parse(black) });
      writeFileSync(join(process.env.OUTDIR || '.', `audit_${L}_${z}.png`), Buffer.from(png, 'base64'));
    }
    OUT[L] = { ...r, rails, posts, black: shots, errors: errors.slice(0, 4) };
    const bad = rails.filter((x) => x.how !== 'end');
    console.log(`\n== ${L}: course ${r.courseLen} m · pickups ${r.live.buffs} (hidden ${r.live.buffsHidden}) · orbs ${r.live.orbs} · pads ${r.live.pads} (hidden ${r.live.padsHidden}) · rails ${r.live.rails} · toys ${r.live.toys} · crystal faces ${r.live.solids} · exits ${r.live.exits}`);
    console.log('   raw:', JSON.stringify(r.raw));
    console.log('   zones:', JSON.stringify(r.live.zones));
    console.log('   rails not to the end:', bad.length, JSON.stringify(bad.slice(0, 6)));
    console.log('   trail jumps:', JSON.stringify(r.trailJumps), ' ground steps:', JSON.stringify(r.groundSteps));
    console.log('   unreachable:', r.unreachN, JSON.stringify(r.unreach.slice(0, 4)));
    console.log('   in the road:', JSON.stringify(posts.kinds));
    console.log('   black:', JSON.stringify(shots));
    console.log('   errors:', JSON.stringify(errors.slice(0, 3)));
  }
} catch (e) { console.log('AUDIT FAILED', String(e).slice(0, 400)); }
finally { try { ws && ws.close(); } catch { } chrome.kill(); writeFileSync(join(process.env.OUTDIR || '.', 'audit.json'), JSON.stringify(OUT, null, 1)); }
