/* THE GATE (owner 2026-11-27): the very first visit only. A browser-style "connection not private" page glitches three times
   and turns into an ACCORD notice: this device is not registered, and it was seen trying to reach AFTERGLOW.
   The way past is the world's simplest captcha: nine tiles, one has a dot. Any answer gets you in.
   Under ten seconds, a Skip link from the first frame. ?gate shows it again; ?nogate never shows it. */
(() => {
  const Q = location.search; let seen = false; try { seen = localStorage.getItem('dl_gate') === '1'; } catch (e) { }
  if (/[?&]nogate\b/.test(Q)) return; if (!/[?&]gate\b/.test(Q) && (seen || navigator.webdriver)) return;
  const done = () => { try { localStorage.setItem('dl_gate', '1'); } catch (e) { } };
  const css = document.createElement('style');
  css.textContent = `
#agGate{position:fixed;inset:0;z-index:400;background:#202124;color:#e8eaed;font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;display:flex;align-items:center;justify-content:center;overflow:hidden;padding:max(16px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(16px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left));box-sizing:border-box;transition:opacity .5s}
#agGate.out{opacity:0;pointer-events:none}
#agGate .pg{width:min(560px,100%);position:relative}
#agGate .ic{width:46px;height:46px;margin-bottom:14px}
#agGate h1{font:500 clamp(22px,4.4vmin + 8px,30px)/1.2 system-ui,sans-serif;margin:0 0 12px;color:#e8eaed;letter-spacing:0}
#agGate p{margin:0 0 10px;color:#bdc1c6}
#agGate code{display:block;margin:8px 0 18px;font:12px ui-monospace,Consolas,monospace;color:#9aa0a6;letter-spacing:.02em}
#agGate .row{display:flex;gap:10px;justify-content:space-between;flex-wrap:wrap}
#agGate button{font:600 14px system-ui,sans-serif;border-radius:6px;padding:9px 18px;cursor:pointer;border:1px solid #5f6368;background:transparent;color:#8ab4f8}
#agGate button.pri{background:#8ab4f8;color:#202124;border:0}
#agGate .skip{position:absolute;right:max(14px,env(safe-area-inset-right));bottom:max(12px,env(safe-area-inset-bottom));font:600 12px system-ui,sans-serif;color:#9aa0a6;background:none;border:0;letter-spacing:.08em;text-transform:uppercase;padding:6px}
#agGate.g .pg{animation:agG .42s steps(2) 1}
@keyframes agG{0%{transform:translate(0);filter:none;clip-path:inset(0 0 0 0)}15%{transform:translate(-7px,2px);text-shadow:3px 0 #ff2a6d,-3px 0 #05d9e8;clip-path:inset(12% 0 58% 0)}30%{transform:translate(9px,-3px);clip-path:inset(54% 0 8% 0)}45%{transform:translate(-3px,0) skewX(-8deg);filter:invert(1)}60%{transform:translate(5px,4px);clip-path:inset(30% 0 30% 0);text-shadow:-4px 0 #ff2a6d,4px 0 #05d9e8}80%{transform:translate(-2px,-2px) skewX(6deg);filter:hue-rotate(90deg)}100%{transform:none;filter:none;clip-path:inset(0)}}
#agGate.reg{background:#0b0d14}
#agGate.reg h1{color:#ffd23a;font-family:"Bebas Neue","Barlow Condensed",Impact,sans-serif;letter-spacing:.06em;font-size:clamp(30px,7vmin + 10px,54px);line-height:1}
#agGate.reg p{color:#d7dbe6}
#agGate.reg .tag{font:700 11px "Barlow Condensed",system-ui,sans-serif;letter-spacing:.22em;color:#38e8ff;text-transform:uppercase;margin-bottom:8px}
#agGate.reg button.pri{background:#ffd23a;color:#0b0d14}
#agGate .cap{background:#fff;color:#202124;border-radius:4px;box-shadow:0 2px 14px #0008;width:min(340px,100%);margin:0 auto;overflow:hidden}
#agGate .cap .hd{background:#1a73e8;color:#fff;padding:14px 16px;font:500 13px/1.3 system-ui,sans-serif}
#agGate .cap .hd b{display:block;font:700 22px/1.15 system-ui,sans-serif}
#agGate .cap .gr{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;padding:4px}
#agGate .cap .t{aspect-ratio:1;background:#e9eaee;border:0;border-radius:0;padding:0;position:relative;cursor:pointer;transition:transform .12s}
#agGate .cap .t.on{transform:scale(.86);outline:3px solid #1a73e8}
#agGate .cap .t .d{position:absolute;width:15%;height:15%;border-radius:50%;background:#111}
#agGate .cap .ft{display:flex;justify-content:space-between;align-items:center;padding:8px 10px;border-top:1px solid #ddd;font:12px system-ui,sans-serif;color:#5f6368}
#agGate .cap .ft button{background:#1a73e8;color:#fff;border:0;padding:8px 18px;font:700 13px system-ui,sans-serif;text-transform:uppercase;border-radius:2px}
#agGate .verdict{margin-top:14px;text-align:center;font:600 16px system-ui,sans-serif;color:#ffd23a;min-height:1.4em}
@media (orientation:landscape) and (max-height:500px){#agGate .cap{display:grid;grid-template-columns:minmax(0,220px) auto;width:max-content;max-width:100%}#agGate .cap .hd{grid-row:1/3}#agGate .cap .gr{width:min(52vh,230px)}#agGate .cap .ft{grid-column:2}#agGate .cap .gr{grid-column:2;grid-row:1}}
`;
  document.head.appendChild(css);
  const g = document.createElement('div'); g.id = 'agGate'; g.setAttribute('role', 'dialog');
  const host = location.hostname || 'this site';
  g.innerHTML = '<div class="pg"><svg class="ic" viewBox="0 0 24 24"><path d="M12 2 1 21h22L12 2z" fill="#f28b82"/><rect x="11" y="9" width="2" height="6" fill="#202124"/><rect x="11" y="16.5" width="2" height="2" fill="#202124"/></svg>'
    + '<h1>Your connection is not private</h1><p>Attackers might be trying to steal your information from <b></b> (for example, passwords, messages or credit cards).</p><code>NET::ERR_CERT_AUTHORITY_INVALID</code>'
    + '<div class="row"><button type="button" class="adv">Advanced</button><button type="button" class="pri back">Back to safety</button></div></div><button type="button" class="skip">Skip</button>';
  g.querySelector('p b').textContent = host;
  (document.body || document.documentElement).appendChild(g);
  const pg = g.querySelector('.pg'); let stage = 0, timers = [];
  const later = (ms, f) => timers.push(setTimeout(f, ms));
  const leave = () => { timers.forEach(clearTimeout); done(); g.classList.add('out'); setTimeout(() => g.remove(), 550); };
  g.querySelector('.skip').onclick = (e) => { e.stopPropagation(); leave(); };
  for (const ev of ['pointerdown', 'pointerup', 'click', 'touchend']) g.addEventListener(ev, (e) => { if (ev !== 'click') return; e.stopPropagation(); }, false);
  const glitch = () => { g.classList.remove('g'); void g.offsetWidth; g.classList.add('g'); };
  const notice = () => { if (stage >= 1) return; stage = 1; glitch(); later(200, () => { g.classList.add('reg');
    pg.innerHTML = '<div class="tag">ACCORD Network Safety · notice 7731-B</div><h1>Device not registered</h1>'
      + '<p>This device just tried to reach <b>AFTERGLOW</b>, an unlicensed broadcast. The attempt has been logged, timestamped and lightly judged.</p>'
      + '<p>Registered humans may continue after a short check. Unregistered humans may also continue. Nobody reads these.</p>'
      + '<div class="row" style="justify-content:flex-start"><button type="button" class="pri ver">Prove you are human</button></div>';
    pg.querySelector('.ver').onclick = (e) => { e.stopPropagation(); captcha(); }; }); };
  const captcha = () => { if (stage >= 2) return; stage = 2; glitch();
    const dotAt = Math.floor(Math.random() * 9), corners = [['8%', '9%'], ['77%', '8%'], ['9%', '76%'], ['76%', '78%']], c = corners[Math.floor(Math.random() * 4)];
    pg.innerHTML = '<div class="cap"><div class="hd">Select all images with<b>a dot</b>Click verify once there are none left.</div><div class="gr"></div><div class="ft"><span>ACCORD® Human Check</span><button type="button">Verify</button></div></div><div class="verdict"></div>';
    const gr = pg.querySelector('.gr');
    for (let i = 0; i < 9; i++) { const t = document.createElement('button'); t.type = 'button'; t.className = 't'; t.setAttribute('aria-label', 'Image ' + (i + 1)); if (i === dotAt) { const d = document.createElement('i'); d.className = 'd'; d.style.left = c[0]; d.style.top = c[1]; t.appendChild(d); }
      t.onclick = (e) => { e.stopPropagation(); t.classList.toggle('on'); }; gr.appendChild(t); }
    pg.querySelector('.ft button').onclick = (e) => { e.stopPropagation(); const on = [...gr.children].map((t, i) => t.classList.contains('on') ? i : -1).filter((i) => i >= 0);
      const v = pg.querySelector('.verdict');
      v.textContent = on.length === 1 && on[0] === dotAt ? 'Verified. Barely.' : on.length === 0 ? 'No dots? Bold. Verified anyway.' : on.includes(dotAt) ? 'Verified. You found the dot and also some feelings.' : 'Wrong. Verified anyway. Standards are at an all-time low.';
      later(1400, leave); }; };
  /* the error page holds for a beat, glitches three times, then the notice */
  g.querySelector('.adv').onclick = (e) => { e.stopPropagation(); notice(); }; g.querySelector('.back').onclick = (e) => { e.stopPropagation(); notice(); };
  later(900, glitch); later(1700, glitch); later(2300, notice);
})();
