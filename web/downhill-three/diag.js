// DIAG (dev tool, only with ?diag in the address). Finds out what freezes the page. A separate background thread (a worker) keeps running when the page freezes, so it can say how long the page has been unresponsive and what the last marker was.
// Every second it sends one small record (numbers and short labels, no images) to ./log.php, which appends it to /var/lib/gaze-lab-logs/three/<date>.jsonl on the server: { app: 'gv', kind: 'diag', sid, ev: 'start' | 'beat' }.
//   beat.mainAgoMs  how long since the page last answered the worker (a few hundred ms is normal; thousands means the page is frozen)
//   beat.frames     frames drawn so far (stops growing when the page or the graphics process is stalled)
//   beat.last       the last marker the game set (window.__dm('...'))      beat.marks  every marker since the last beat, with its time in ms since the page started
// The game calls window.__dm(label) at its main stages (see gv.js), and this file adds the errors, the long tasks (over 50 ms) and a lost graphics context.
(function () {
  const Q = new URLSearchParams(location.search); if (!Q.has('diag')) return;
  const sid = Math.random().toString(36).slice(2, 8), T0 = performance.now(); let last = 'html', frames = 0;
  const info = { ua: navigator.userAgent, cores: navigator.hardwareConcurrency, devMem: navigator.deviceMemory, dpr: devicePixelRatio, w: innerWidth, h: innerHeight, url: location.search };
  try { const c = document.createElement('canvas'), gl = c.getContext('webgl2'), e = gl && gl.getExtension('WEBGL_debug_renderer_info'); info.gpu = e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'n/a'; } catch (e) { info.gpu = 'error'; }
  const src = `
    let sid, logUrl, lastAlive = 0, state = {}, marks = [];
    const post = (rec) => fetch(logUrl, { method: 'POST', body: JSON.stringify(Object.assign({ app: 'gv', kind: 'diag', sid }, rec)), keepalive: true }).catch(() => {});
    function beat() { const now = performance.now(); post({ ev: 'beat', t: Math.round(state.t || 0), mainAgoMs: lastAlive ? Math.round(now - lastAlive) : -1, frames: state.frames, last: state.last, heapMB: state.heap, vis: state.vis, marks: marks.splice(0, 150) }); }
    onmessage = (e) => { const d = e.data; if (d.type === 'init') { sid = d.sid; logUrl = d.logUrl; post({ ev: 'start', info: d.info }); const t0w = performance.now(), loop = () => { beat(); setTimeout(loop, performance.now() - t0w < 60000 ? 2000 : 5000); }; setTimeout(loop, 2000); } else if (d.type === 'mark') marks.push([Math.round(d.t), d.label]); else if (d.type === 'alive') { lastAlive = performance.now(); state = d; } };`;
  const w = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
  w.postMessage({ type: 'init', sid, info, logUrl: new URL('log.php', location.href).href });
  const mark = (label) => { last = label; w.postMessage({ type: 'mark', label, t: performance.now() - T0 }); };
  window.__dm = mark; mark('html: diag started');
  setInterval(() => { w.postMessage({ type: 'alive', t: performance.now() - T0, frames, last, heap: performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : 0, vis: document.visibilityState }); }, 250);
  const tick = () => { frames++; requestAnimationFrame(tick); }; requestAnimationFrame(tick);
  addEventListener('error', (e) => mark('ERROR ' + e.message + ' @' + String(e.filename || '').split('/').pop() + ':' + e.lineno));
  addEventListener('unhandledrejection', (e) => mark('REJECTED ' + String((e.reason && e.reason.message) || e.reason).slice(0, 120)));
  document.addEventListener('webglcontextlost', () => mark('WEBGL CONTEXT LOST'), true);
  document.addEventListener('visibilitychange', () => mark('visibility ' + document.visibilityState));
  try { new PerformanceObserver((l) => { for (const en of l.getEntries()) w.postMessage({ type: 'mark', label: 'longtask ' + Math.round(en.duration) + 'ms', t: en.startTime }); }).observe({ entryTypes: ['longtask'] }); } catch (e) { }
})();
