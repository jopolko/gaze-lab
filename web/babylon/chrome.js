/* Shared page chrome for every Afterglow page (owner 2026-11-27):
   1. Full screen on the first touch, click or key, on every page (not in a headset, not with ?nofs).
      Inside a frame it asks the top page (shell) instead.
   2. The padlock always sits in the same top-right corner, thumb-reachable, on every screen:
      any element with class "aglk" (or id lkBtn / pzb) is pinned there. */
(() => {
  if (window.__AGCHROME) return; window.__AGCHROME = 1;
  const css = document.createElement('style');
  css.textContent = '.aglk,#lkBtn,#pzb{position:fixed!important;top:max(10px,var(--sa-top, env(safe-area-inset-top,0px)))!important;right:max(10px,var(--sa-right, env(safe-area-inset-right,0px)))!important;left:auto!important;bottom:auto!important;margin:0!important;width:44px!important;height:44px!important;z-index:130!important;display:grid!important;place-items:center!important;padding:0!important;cursor:pointer}';
  (document.head || document.documentElement).appendChild(css);
  /* 4. BACK (owner 2026-11-27): every Back/Close returns you to where you came from: the ?back= page, else the page before this one, else the fallback */
  window.__goBack = (fallback) => { const b = new URLSearchParams(location.search).get('back'); if (b && /^[\w.\-\/?=&%]+$/.test(b)) { location.href = b; return; }
    try { if (document.referrer && new URL(document.referrer).origin === location.origin && new URL(document.referrer).pathname !== location.pathname && history.length > 1) { history.back(); return; } } catch (e) { } location.href = fallback || 'splash.html'; };
  /* 3. the AFTERGLOW title on any page is a one-tap way back to the title screen */
  const tt = () => { if (/splash\.html$/.test(location.pathname)) return; for (const h of document.querySelectorAll('h1')) { if (!/AFTERGLOW/i.test(h.textContent || '') || h.closest('a') || h.querySelector('a')) continue; h.style.cursor = 'pointer'; h.title = 'Back to the title'; h.addEventListener('click', () => { location.href = 'splash.html'; }); } };
  if (document.readyState === 'loading') addEventListener('DOMContentLoaded', tt); else tt();
  const Q = location.search, vr = /OculusBrowser|Quest|Pico|Wolvic/i.test(navigator.userAgent);
  if (/[?&]nofs\b/.test(Q) || vr) return;
  const isFs = (d) => !!(d.fullscreenElement || d.webkitFullscreenElement);
  const go = () => {
    if (window.top !== window) { try { const td = window.top.document; if (isFs(td)) return; const te = td.documentElement, tr = te.requestFullscreen || te.webkitRequestFullscreen; if (tr) { const p = tr.call(te, { navigationUI: 'hide' }); if (p && p.catch) p.catch(() => { }); return; } } catch (e) { } try { window.top.postMessage('gv-fs', location.origin); } catch (e) { } return; }          /* (same-origin shell: full screen the shell itself; the tap counts for it too) */
    if (isFs(document)) return; const el = document.documentElement, r = el.requestFullscreen || el.webkitRequestFullscreen; if (!r) return;
    try { const p = r.call(el, { navigationUI: 'hide' }); if (p && p.catch) p.catch(() => { }); } catch (e) { }
  };
  for (const ev of ['pointerup', 'touchend', 'click', 'keydown']) addEventListener(ev, go, true);
  /* a top page (splash, guide, menu) also answers a framed page's request */
  addEventListener('message', (e) => { if (e.origin === location.origin && e.data === 'gv-fs' && window.top === window) go(); });
})();
