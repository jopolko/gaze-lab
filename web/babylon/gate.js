/* THE GATE (owner 2026-11-27): the very first visit only. A browser-style "connection not private" page glitches three times
   and turns into an ACCORD notice: this device is not registered, and it was seen trying to reach AFTERGLOW.
   Continue goes straight in (the captcha that used to follow was cut 2026-11-28).
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
#agGate.reg{background:linear-gradient(#eef1f8,#dfe5f1);color:#1b2236;align-items:flex-start;padding-top:0}
#agGate.reg::before{content:'';position:absolute;inset:0 0 auto 0;height:clamp(58px,11vh,84px);background:linear-gradient(90deg,#0d1b4c,#1d3fa6 60%,#3a6cf0);box-shadow:0 2px 0 #f5c400}
#agGate .lh{position:absolute;left:max(16px,env(safe-area-inset-left));top:0;height:clamp(58px,11vh,84px);display:flex;align-items:center;gap:10px;color:#fff;z-index:1}
#agGate .lh b{font:800 clamp(20px,3.4vmin + 10px,30px)/1 system-ui,sans-serif;letter-spacing:-.01em}#agGate .lh i{font:italic 500 12px/1.2 Georgia,serif;opacity:.85}#agGate .lh svg{width:30px;height:30px}
#agGate.reg .pg{margin-top:calc(clamp(58px,11vh,84px) + 18px);background:#fff;border:1px solid #c9d2e6;border-radius:6px;padding:18px 18px 16px;box-shadow:0 6px 24px rgba(20,30,70,.15);max-height:calc(100% - clamp(58px,11vh,84px) - 40px);overflow:auto}
#agGate.reg h1{color:#b3121f;font:800 clamp(22px,3.6vmin + 12px,34px)/1.1 system-ui,sans-serif;letter-spacing:0}
#agGate.reg p{color:#2d3550}
#agGate.reg .tag{font:700 11px system-ui,sans-serif;letter-spacing:.16em;color:#1d3fa6;text-transform:uppercase;margin-bottom:8px}
#agGate.reg .fine{margin-top:12px;font:11px/1.4 system-ui,sans-serif;color:#7a829a}
#agGate.reg button.pri{background:#1d3fa6;color:#fff}
#agGate.reg .skip{color:#4a5578}
#agGate.reg .cap{box-shadow:none;border:1px solid #d5dbe8;margin:0}#agGate.reg .verdict{color:#1d3fa6}
#agGate .cap{background:#fff;color:#202124;border-radius:4px;box-shadow:0 2px 14px #0008;width:min(340px,100%);margin:0 auto;overflow:hidden}
#agGate .cap .hd{background:#1a73e8;color:#fff;padding:14px 16px;font:500 13px/1.3 system-ui,sans-serif}
#agGate .cap .hd b{display:block;font:700 22px/1.15 system-ui,sans-serif}
#agGate .cap .gr{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;padding:4px}
#agGate .cap .t{aspect-ratio:1;background:#e9eaee;border:0;border-radius:0;padding:0;position:relative;cursor:pointer;transition:transform .12s}
#agGate .cap .t.on{transform:scale(.86);outline:3px solid #1a73e8}
#agGate .cap .t{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;color:#3c4043}#agGate .cap .t .ic{font-size:clamp(22px,7vmin,34px);line-height:1}#agGate .cap .t small{font:600 10.5px system-ui,sans-serif}
#agGate .cap .ft{display:flex;justify-content:space-between;align-items:center;padding:8px 10px;border-top:1px solid #ddd;font:12px system-ui,sans-serif;color:#5f6368}
#agGate .cap .ft button{background:#1a73e8;color:#fff;border:0;padding:8px 18px;font:700 13px system-ui,sans-serif;text-transform:uppercase;border-radius:2px}
#agGate .verdict{margin-top:14px;text-align:center;font:600 16px system-ui,sans-serif;color:#ffd23a;min-height:1.4em}

@media (orientation:landscape) and (max-height:500px){#agGate.reg .pg{margin-top:calc(clamp(58px,11vh,84px) + 6px);padding:0;background:none;border:0;box-shadow:none;overflow:visible;width:auto}#agGate .cap{width:min(420px,100%)}#agGate .cap .hd{padding:6px 10px;font-size:11px}#agGate .cap .hd b{display:inline;font-size:15px;margin:0 4px}#agGate .cap .t{aspect-ratio:auto;height:clamp(40px,12.5vh,56px);flex-direction:column;gap:1px}#agGate .cap .t .ic{font-size:18px}#agGate .cap .ft{padding:4px 8px}#agGate .cap .ft button{padding:5px 14px}#agGate .verdict{margin-top:4px;font-size:13px}#agGate.reg .fine{display:none}}
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
  const leave = () => { timers.forEach(clearTimeout); done(); window.__GATE = 0; g.classList.add('out'); setTimeout(() => g.remove(), 550); };
  { const sk = g.querySelector('.skip'); sk.textContent = 'Skip (opt out of safety)'; sk.onclick = (e) => { e.stopPropagation(); if (sk.dataset.done) return; sk.dataset.done = 1; sk.textContent = 'Opt-out recorded and shared with 412 partners.'; later(1100, leave); }; }
  for (const ev of ['pointerdown', 'pointerup', 'click', 'touchend']) g.addEventListener(ev, (e) => { if (ev !== 'click') return; e.stopPropagation(); }, false);
  const glitch = () => { g.classList.remove('g'); void g.offsetWidth; g.classList.add('g'); };
  window.__GATE = 1;          /* the title screen holds its animation while this is up, so taps stay instant */
  const notice = () => { if (stage >= 1) return; stage = 1; glitch(); later(140, () => { g.classList.add('reg');
    if (!g.querySelector('.lh')) g.insertAdjacentHTML('afterbegin', '<div class="lh"><svg viewBox="0 0 24 24"><path d="M12 2l2.6 6.6L21 9.3l-5 4.4 1.6 6.8L12 17l-5.6 3.5L8 13.7 3 9.3l6.4-.7z" fill="#f5c400"/></svg><span><b>StarLeash</b><br><i>Your connection. Our leash.</i></span></div>');
    pg.innerHTML = '<div class="tag">Customer Protection · on behalf of ACCORD Network Safety</div><h1>Device not registered</h1>'
      + '<p>Dear Valued Subscriber, this device just tried to reach <b>AFTERGLOW</b>, an unlicensed transmission, for the first time. The attempt has been logged, timestamped and lightly judged.</p>'
      + '<p>First-time visit only. After this, we will remember you.</p>'
      + '<div class="row" style="justify-content:flex-start"><button type="button" class="pri ver">Continue</button></div>'
      + '<div class="fine">StarLeash is a trading name of StarLeash Holdings, a wholly owned subsidiary of your data. Ref. 7731-B.</div>';
    pg.querySelector('.ver').onclick = (e) => { e.stopPropagation(); leave(); }; }); };          /* (owner 2026-11-28: no captcha after the browser gag: "just give me the game". Continue goes straight in; the captcha below is no longer reached) */
  /* the check: "select all squares containing your personal data". Tap anything and ACCORD selects all nine for you. */
  const captcha = () => { if (stage >= 2) return; stage = 2;
    const IC = [['\uD83D\uDCF7', 'Photos'], ['\uD83C\uDFE0', 'Home'], ['\uD83D\uDCAC', 'Messages'], ['\uD83D\uDDFA\uFE0F', 'Location'], ['\uD83C\uDFB5', 'Music'], ['\u2764\uFE0F', 'Dating'], ['\uD83D\uDED2', 'Cart'], ['\uD83D\uDD11', 'Passwords'], ['\uD83E\uDDE0', 'Thoughts']];
    pg.innerHTML = '<div class="cap"><div class="hd">Select all squares containing<b>your personal data</b>If there are none, click skip.</div><div class="gr"></div><div class="ft"><span>ACCORD\u00AE Human Check</span><button type="button">Verify</button></div></div><div class="verdict"></div>';
    const gr = pg.querySelector('.gr'), v = pg.querySelector('.verdict'); let all = false;
    const finish = () => { if (all) return; all = true; [...gr.children].forEach((t, i) => later(i * 45, () => t.classList.add('on'))); v.textContent = 'Don\u2019t worry, we selected them for you.';
      later(900, () => { v.textContent = 'Verified. Your data has been shared with 412 trusted partners.'; }); later(2300, leave); };
    IC.forEach(([ic, nm]) => { const t = document.createElement('button'); t.type = 'button'; t.className = 't'; t.setAttribute('aria-label', nm); t.innerHTML = '<span class="ic">' + ic + '</span><small>' + nm + '</small>'; t.onclick = (e) => { e.stopPropagation(); finish(); }; gr.appendChild(t); });
    pg.querySelector('.ft button').onclick = (e) => { e.stopPropagation(); finish(); }; };
  /* the error page for a beat (short: it should read as a joke before anyone worries), three glitches, then the notice */
  g.querySelector('.adv').onclick = (e) => { e.stopPropagation(); notice(); }; g.querySelector('.back').onclick = (e) => { e.stopPropagation(); notice(); };
  later(450, glitch); later(850, glitch); later(1200, notice);
})();
