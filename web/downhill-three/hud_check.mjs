import { createHud, clockText } from './hud.js';
const calls = {}; const ctx = new Proxy({}, { get: (t, p) => p === 'measureText' ? (s) => ({ width: s.length * 8 }) : (typeof p === 'string' && /^(fill|stroke|clear|arc|beginPath|moveTo|lineTo|closePath|setTransform|save|restore|fillText|strokeText|fillRect|strokeRect|translate|rotate|scale|ellipse|rect|clip|quadraticCurveTo|bezierCurveTo|createRadialGradient|createLinearGradient)/.test(p) ? (...a) => { calls[p] = (calls[p] || 0) + 1; return { addColorStop() {} }; } : t[p]), set: (t, p, v) => { t[p] = v; return true; } });
const cv = { style: {}, getContext: () => ctx, width: 0, height: 0 };
const doc = { createElement: () => cv, body: { appendChild() {} } };
const H = createHud({ document: doc, width: 960, height: 412, dpr: 1, noResizeListener: true, touch: true, hudMin: false, project: () => ({ x: 400, y: 200, behind: false }) });
H.toast('MATCH', [1, .5, .9]); H.toast('MATCH', [1, .5, .9]); H.toast('ACH', [1, 1, 1], 'ach'); H.cheer('BLAST!', [1, .6, 1], 1.6); H.pop([0, 0, -5], [1, .5, 0], '+60');
const got = [1, 0, 1, 1, 1, 1].map(Boolean);
const seq = [{ warming: { k: .5 } }, { kmh: 80, score: 1234, progress: .3, shield: true, boostT: 2, multT: 3, glints: 4, speedG: 40, rampCharge: .7, hurtT: .5, snowball: .6, chain: { n: 2, groove: 1.5, flowT: 3, flowWindow: 5, step: 1, lvl: 2, t: 2, window: 4, target: { x: 300, y: 100 } }, mol: { got, felt: [], held: [], pop: [] }, perf: { fps: 58, tier: 2, where: 100, of: 5000, region: 'a', zone: 'b', world: 'w', alt: 10, rows: 4, chunks: 3, next: 1, queue: 0, snd: 5, music: 'x' } },
  { paused: true, perf: { fps: 30 } }, { finish: { race: true, runT: 75.3, timePen: 5, bestVal: 80, goalsDone: 3, goalsTotal: 4, endT: 2 } }, { race: true, runT: 12.34, timePen: -2, portrait: true }];
for (const s of seq) for (let i = 0; i < 20; i++) H.update(1 / 60, s);
console.log('paused hit', H.hit(480, 120), 'pause btn', H.hit(900, 20));
console.log(clockText(75.3), clockText(5.04), 'toasts left', H.state.toasts.length, calls.fillText, calls.strokeText, calls.fillRect);
