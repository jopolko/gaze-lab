// node tools/check_pantry.mjs: closest non-bonded atoms and longest bond per strain (atoms closer than ~1.1 overlap on screen)
import { PANTRY } from '../molpantry.js';
for (const [k, m] of Object.entries(PANTRY)) {
  let worst = 9, pr = null; const bd = new Set(m.bonds.flatMap((b) => [b[0] + ',' + b[1], b[1] + ',' + b[0]]));
  for (let i = 0; i < m.atoms.length; i++) for (let j = i + 1; j < m.atoms.length; j++) { const a = m.atoms[i], b = m.atoms[j], d = Math.hypot(a[1] - b[1], a[2] - b[2], a[3] - b[3]); if (!bd.has(i + ',' + j) && d < worst) { worst = d; pr = [i, j]; } }
  let lb = 0; for (const [i, j] of m.bonds) { const a = m.atoms[i], b = m.atoms[j]; lb = Math.max(lb, Math.hypot(a[1] - b[1], a[2] - b[2], a[3] - b[3])); }
  console.log(k.padEnd(9), 'closest', worst.toFixed(2), JSON.stringify(pr), 'longest bond', lb.toFixed(2), worst < 1.1 ? '  <-- OVERLAP' : '');
}
