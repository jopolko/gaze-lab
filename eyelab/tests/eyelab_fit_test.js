// Node checks for EyeLab's pure functions:  node eyelab/tests/eyelab_fit_test.js
// Extracts the EYE FRAME and SIGNAL FIT blocks from index.html (they are plain functions) and checks them against known answers.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const block = (name) => {
  const m = src.match(new RegExp('// ==== ' + name + ' BEGIN[^\\n]*\\n([\\s\\S]*?)// ==== ' + name + ' END'));
  if (!m) throw new Error('block not found: ' + name);
  return m[1];
};
const lib = new Function(block('EYE FRAME') + block('SIGNAL FIT') + '\nreturn { eyeFrame, eyeNorm, eyeRel, solveLS, lsFit, corr, fitSignals, bestLagFit };')();
let fails = 0;
const check = (ok, msg) => { console.log((ok ? 'PASS  ' : 'FAIL  ') + msg); if (!ok) fails++; };

// ---- eye frame: a synthetic eye, rolled by a known angle. The iris sits 0.3 of the way across and 0.5 down.
const eye = (rollDeg, ix, iy) => {
  const a = rollDeg * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a), W = 40, Hh = 14;
  const rot = (x, y) => ({ x: 100 + x * ca - y * sa, y: 100 + x * sa + y * ca });
  const o = rot(-W / 2, 0), i = rot(W / 2, 0), tp = rot(0, -Hh / 2), bt = rot(0, Hh / 2);
  const q = rot(-W / 2 + ix * W, (iy - 0.5) * Hh);
  return { o, i, tp, bt, q };
};
for (const roll of [0, 10, 17.5, -25]) {
  const e = eye(roll, 0.3, 0.5);
  const on = lib.eyeNorm(lib.eyeFrame(e.o, e.i, e.tp, e.bt, true), e.q);
  check(Math.abs(on[0] - 0.3) < 1e-6 && Math.abs(on[1] - 0.5) < 1e-6, 'eye-axis iris reads 0.30 / 0.50 whatever the roll (roll ' + roll + ': ' + on[0].toFixed(3) + ' / ' + on[1].toFixed(3) + ')');
}
{
  const e = eye(17.5, 0.3, 0.5);
  const e8 = eye(17.5, 0.3, 0.8);                // iris 0.3 across but lower in the eye (looking down): the plain image axes mix that into x
  const off = lib.eyeNorm(lib.eyeFrame(e8.o, e8.i, e8.tp, e8.bt, false), e8.q);
  check(Math.abs(off[0] - 0.3) > 0.02, 'the plain image-axis reading is off at 17.5 deg of roll when the iris is also lower in the eye (reads ' + off[0].toFixed(3) + ' instead of 0.300): that is the leak');
  const e0 = eye(0, 0.3, 0.5);
  const a0 = lib.eyeNorm(lib.eyeFrame(e0.o, e0.i, e0.tp, e0.bt, true), e0.q), b0 = lib.eyeNorm(lib.eyeFrame(e0.o, e0.i, e0.tp, e0.bt, false), e0.q);
  check(Math.abs(a0[0] - b0[0]) < 1e-9 && Math.abs(a0[1] - b0[1]) < 1e-9, 'with no roll the two modes agree exactly');
  // a pure vertical eye movement (squint / look up) must not move the horizontal reading when rolled
  const lo = eye(17.5, 0.3, 0.3), hi = eye(17.5, 0.3, 0.7);
  const fr = (E) => lib.eyeNorm(lib.eyeFrame(E.o, E.i, E.tp, E.bt, true), E.q)[0];
  const fo = (E) => lib.eyeNorm(lib.eyeFrame(E.o, E.i, E.tp, E.bt, false), E.q)[0];
  check(Math.abs(fr(lo) - fr(hi)) < 1e-9 && Math.abs(fo(lo) - fo(hi)) > 0.03, 'a vertical eye movement at 17.5 deg roll: eye-axis x stays put (' + Math.abs(fr(lo) - fr(hi)).toExponential(1) + '), image-axis x moves ' + Math.abs(fo(lo) - fo(hi)).toFixed(3));
  const rel = lib.eyeRel(lib.eyeFrame(e.o, e.i, e.tp, e.bt, true), e.q);
  check(Math.abs(rel[0] - (0.3 - 0.5) * 40) < 1e-6 && Math.abs(rel[1]) < 1e-6, 'pixel offset from the eye centre is in true pixels along the eye axis (' + rel[0].toFixed(2) + ' px)');
}

// ---- least squares and the signal fit
{
  const A = [[2, 1], [1, 3]], b = [5, 10];
  const x = lib.solveLS(A, b);
  check(x && Math.abs(x[0] - 1) < 1e-9 && Math.abs(x[1] - 3) < 1e-9, 'solveLS solves a 2x2 system');
}
const rng = (() => { let s = 12345; return () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; }; })();
const gauss = () => { let u = 0; for (let i = 0; i < 6; i++) u += rng(); return (u - 3) * Math.SQRT2; };
const dot = (ms) => { const s = ms / 1000; return [0.5 + 0.42 * Math.sin(2 * Math.PI * (0.07 * s + 0.0045 * s * s)), 0.5 + 0.38 * Math.sin(2 * Math.PI * (0.05 * s + 0.003 * s * s) + 1.0)]; };
const dotAt = (ms) => (ms < 0 || ms > 32000 ? null : dot(ms));
// frames at 12 fps with jitter in time; iris is dot x delayed by 150 ms, scaled 1/6 around 0.5, noisy; head yaw carries a clean part of the same motion
const frames = [];
for (let t = 0; t < 32000; t += 1000 / 12 + (rng() - 0.5) * 20) {
  const d = dotAt(t - 150) || [0.5, 0.5];
  frames.push({ t, s: { irisX: 0.5 + (d[0] - 0.5) / 6 + gauss() * 0.012, yaw: (d[0] - 0.5) * 0.35 + gauss() * 0.02, junk: gauss() } });
}
const lags = []; for (let l = 0; l <= 500; l += 25) lags.push(l);
const fi = lib.bestLagFit(frames, dotAt, ['irisX'], 0, lags);
check(fi && Math.abs(fi.lagMs - 150) <= 25, 'the fit finds the true 150 ms delay (' + (fi && fi.lagMs) + ' ms)');
check(fi && fi.r > 0.97 && Math.abs(fi.coef[0] - 6) < 0.6, 'and the gain: dot = 6 x iris (r ' + (fi && fi.r.toFixed(3)) + ', gain ' + (fi && fi.coef[0].toFixed(2)) + ')');
const fj = lib.bestLagFit(frames, dotAt, ['junk'], 0, lags);
check(fj && Math.abs(fj.r) < 0.3, 'a signal that is just noise does not fit (r ' + (fj && fj.r.toFixed(2)) + ')');
const fy = lib.bestLagFit(frames, dotAt, ['yaw'], 0, lags);
const fb = lib.bestLagFit(frames, dotAt, ['irisX', 'yaw'], 0, lags);
check(fb && fy && fi && fb.rmsCV < fi.rmsCV && fb.rmsCV < fy.rmsCV, 'iris + head errs less than either alone, scored on held-out data (' + (fb && (fb.rmsCV * 100).toFixed(1)) + '% vs ' + (fi && (fi.rmsCV * 100).toFixed(1)) + '% / ' + (fy && (fy.rmsCV * 100).toFixed(1)) + '%)');
const fw = lib.fitSignals(frames, dotAt, ['irisX'], 0, 400);
check(fw && fi && fw.rmsCV > fi.rmsCV, 'a wrong delay fits worse (400 ms: ' + (fw && (fw.rmsCV * 100).toFixed(1)) + '% vs ' + (fi && (fi.rmsCV * 100).toFixed(1)) + '%)');
// overfitting guard: with many junk columns the cross-validated error must not look better than the fit on its own data
const fo = lib.fitSignals(frames.map((f) => ({ t: f.t, s: Object.assign({}, f.s, { j2: gauss(), j3: gauss(), j4: gauss() }) })), dotAt, ['junk', 'j2', 'j3', 'j4'], 0, 150);
check(fo && fo.rmsCV >= fo.rmsFit * 0.98, 'held-out error is not better than the fitted error (no flattering)');
console.log('RESULT: ' + (fails ? fails + ' FAILED' : 'ALL PASSED'));
process.exit(fails ? 1 : 0);
