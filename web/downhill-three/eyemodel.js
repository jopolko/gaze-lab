// EYE MODEL: a three-state filter (LEFT / MIDDLE / RIGHT) over BOTH eyes' iris readings together, learned while playing.
//
// WHAT THE SIGNAL IS (measured on the real logs): each eye i reads  h_i = o_i + g_i(side) * look + drift(t) + noise.
//   o_i    its own resting level (eye A sat near -0.07 and eye B near +0.05: they can not be averaged blindly or compared to one fixed centre)
//   g_i    its own gain, DIFFERENT for a look left and a look right (through glasses one eye barely moved for a left look: +0.014 vs -0.052, while the other gave +0.037 / -0.042)
//   noise  about 0.005 per reading, partly shared by the two eyes
//   drift  the whole signal wanders by 0.01 or more over 30 s (head turn, glare); a look at a target in play is only about 0.01, two or three times the noise
//
// THE MODEL: x = (hA, hB). State k in {L, M, R} has mean  m + d_k  where m is the MIDDLE (a 2-vector) and d_L, d_R are the left and right OFFSETS from it (d_M = 0). One shared covariance S.
//   1. FILTER   the posterior over the three states is updated every reading by the forward algorithm with a sticky transition matrix (a look lasts about a second, M<->L and M<->R are the likely moves,
//               L<->R directly is very unlikely), so one noisy reading can not flip the state, and the evidence of both eyes is combined by their own offsets and the shared covariance (the weak eye
//               counts less on its weak side automatically: no "which eye" switch)
//   2. FLOAT    the middle follows the readings the filter believes are MIDDLE (time constant about 3 s), and the sides are offsets from it, so drift moves all three places together: the gyroscope
//   3. LEARN    each side's offset follows the readings believed to be that side (about 7 s); the shared covariance follows the residuals; a side is never allowed closer than 2.2 noise widths to the
//               middle (the states must stay separable), nor further than 0.08
//   4. REMEMBER the learned offsets and covariance are saved (localStorage) so the next session starts from them: no calibration step, ever
//   5. DECIDE   the state is the most probable one once it passes 0.65 (otherwise the old one stays): that is the hysteresis
export class EyeModel {
  constructor(prior) {
    this.m = [0, 0];
    this.dL = prior && prior.dL ? prior.dL.slice() : [0.02, 0.02];          // left = middle + dL (hx rises for a look left)
    this.dR = prior && prior.dR ? prior.dR.slice() : [0.02, 0.02];          // right = middle - dR
    this.S = prior && prior.S ? prior.S.slice() : [3.0e-5, 3.0e-5, 1.0e-5];          // [varA, varB, covAB]
    this.post = [0, 1, 0]; this.state = 1; this.ready = false; this.init = [];
    this.n = 0; this.zn = 0;
    this.STAY = 0.94; this.TEMP = 1.0; this.ETA_M = 0.02; this.ETA_S = 0.01; this.ETA_C = 0.01; this.MIN_SEP = 2.5; this.DECIDE = 0.8; this.NEED = 30;          // (tuned by simulation on eyes like the logged ones)
  }
  inv() { const [a, b, c] = this.S, det = Math.max(a * b - c * c, 1e-12); return [b / det, a / det, -c / det]; }          // inverse of [[a,c],[c,b]] as [ia, ib, ic]
  q(x, k) {          // squared Mahalanobis distance of x from state k's mean
    const d = k === 0 ? this.dL : k === 2 ? [-this.dR[0], -this.dR[1]] : [0, 0];
    const r0 = x[0] - this.m[0] - d[0], r1 = x[1] - this.m[1] - d[1], [ia, ib, ic] = this.inv();
    return ia * r0 * r0 + ib * r1 * r1 + 2 * ic * r0 * r1;
  }
  sepOf(d) { const [ia, ib, ic] = this.inv(); return Math.sqrt(Math.max(ia * d[0] * d[0] + ib * d[1] * d[1] + 2 * ic * d[0] * d[1], 0)); }
  fixSep(d) {          // keep a side at least MIN_SEP noise widths from the middle, and no further than 0.08 per eye
    const s = this.sepOf(d); if (s > 1e-9 && s < this.MIN_SEP) { const f = this.MIN_SEP / s; d[0] *= f; d[1] *= f; }
    d[0] = Math.max(-0.08, Math.min(0.08, d[0])); d[1] = Math.max(-0.08, Math.min(0.08, d[1]));
  }
  step(x) {
    this.n++;
    if (!this.ready) {          // the first readings (the stare at the centre) set the middle and the noise
      this.init.push(x);
      if (this.init.length >= this.NEED) {
        const n = this.init.length, mA = this.init.reduce((s, v) => s + v[0], 0) / n, mB = this.init.reduce((s, v) => s + v[1], 0) / n;
        let a = 0, b = 0, c = 0; for (const v of this.init) { a += (v[0] - mA) ** 2; b += (v[1] - mB) ** 2; c += (v[0] - mA) * (v[1] - mB); }
        this.m = [mA, mB]; this.S = [Math.max(a / n, 1.2e-5), Math.max(b / n, 1.2e-5), Math.max(Math.min(c / n, 0.8 * Math.sqrt((a / n) * (b / n))), 0)];
        this.fixSep(this.dL); this.fixSep(this.dR); this.ready = true;
      }
      return this.state;
    }
    // FILTER: predict with the sticky transitions, then weight by how well x fits each state
    const s = this.STAY, p = this.post;
    const eM = (1 - s) * 0.92, eX = (1 - s) * 0.08, eS = 0.03;          // side to middle, side to other side, middle to a side
    const pr = [p[0] * s + p[1] * eS + p[2] * eX, p[1] * s + (p[0] + p[2]) * eM, p[2] * s + p[1] * eS + p[0] * eX];
    const T = this.TEMP;          // tempering: the noise is not exactly Gaussian (blinks, glints), so one reading should not decide (1 = none; tuned)
    const l = [0, 1, 2].map((k) => Math.exp(-0.5 * this.q(x, k) / T));
    let z = 0; const np = pr.map((v, k) => { const w = v * l[k] + 1e-6; z += w; return w; }); for (let k = 0; k < 3; k++) np[k] /= z;
    this.post = np;
    // ADAPT. FLOAT: the middle follows the whole signal, each reading weighted by the state the filter believes it is in and measured from THAT state's own mean (so a long look to the left, which
    // sits at m + dL, does not drag the middle left; but a drift of everything moves all three places together). LEARN: each side's offset follows the readings believed to be that side, slowly.
    const rA = [x[0] - this.m[0], x[1] - this.m[1]], dl = this.dL, dr = this.dR;
    const resA = np[0] * (rA[0] - dl[0]) + np[1] * rA[0] + np[2] * (rA[0] + dr[0]), resB = np[0] * (rA[1] - dl[1]) + np[1] * rA[1] + np[2] * (rA[1] + dr[1]);
    this.m[0] += this.ETA_M * resA; this.m[1] += this.ETA_M * resB;
    const r2 = [x[0] - this.m[0], x[1] - this.m[1]];
    if (np[0] > 0.7) { const e = this.ETA_S * np[0]; this.dL[0] += e * (r2[0] - this.dL[0]); this.dL[1] += e * (r2[1] - this.dL[1]); this.fixSep(this.dL); }
    if (np[2] > 0.7) { const e = this.ETA_S * np[2]; this.dR[0] += e * (-r2[0] - this.dR[0]); this.dR[1] += e * (-r2[1] - this.dR[1]); this.fixSep(this.dR); }
    const k = np[0] > 0.6 ? 0 : np[2] > 0.6 ? 2 : np[1] > 0.6 ? 1 : -1;
    if (k >= 0) {
      const d = k === 0 ? this.dL : k === 2 ? [-this.dR[0], -this.dR[1]] : [0, 0], r0 = x[0] - this.m[0] - d[0], r1 = x[1] - this.m[1] - d[1], e = this.ETA_C;
      this.S[0] = Math.max((1 - e) * this.S[0] + e * r0 * r0, 1.2e-5); this.S[1] = Math.max((1 - e) * this.S[1] + e * r1 * r1, 1.2e-5);
      this.S[2] = Math.max(Math.min((1 - e) * this.S[2] + e * r0 * r1, 0.8 * Math.sqrt(this.S[0] * this.S[1])), 0);
    }
    // DECIDE with hysteresis
    let best = 0; for (let j = 1; j < 3; j++) if (np[j] > np[best]) best = j;
    if (np[best] > this.DECIDE) this.state = best;
    this.zn = np[2] - np[0];          // -1 = surely left, +1 = surely right (the game's convention: zone -1 is left)
    return this.state;
  }
  get zone() { return this.state - 1; }          // -1 left, 0 middle, +1 right
  save() { return { dL: this.dL, dR: this.dR, S: this.S }; }
}
