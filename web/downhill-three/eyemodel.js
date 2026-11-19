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
    this.S = [3.0e-5, 3.0e-5, 1.0e-5];          // (measured from the stare each time: a saved one once carried an inflated value from a bad run into the next)          // [varA, varB, covAB]
    this.post = [0, 1, 0]; this.state = 1; this.ready = false; this.init = [];
    this.n = 0; this.zn = 0; this.xs = []; this.ss = []; this.labeled = []; this.hold = false; this.lastFix = 0; this.fixes = 0;
    this.STAY = 0.94; this.TEMP = 1.0; this.ETA_M = 0.04; this.ETA_S = 0.01; this.ETA_C = 0.01; this.MIN_SEP = 2.5; this.DECIDE = 0.8; this.NEED = 45; this.CLIP = 0.012; this.SUP = 0.03; this.SIDEW = 0.5; this.SMAX = 7.0e-5;          // (tuned by simulation on eyes like the logged ones)
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
        this.init = this.init.slice(15);          // the first second is thrown away: the eyes are still settling on the centre and the camera is still adjusting (in one run the first readings sat 0.03 away from where they stayed)
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
    const sw = this.SIDEW;          // a side counts for less when moving the middle: a long look to one side must not drag the middle over to it
    const resA = sw * np[0] * (rA[0] - dl[0]) + np[1] * rA[0] + sw * np[2] * (rA[0] + dr[0]), resB = sw * np[0] * (rA[1] - dl[1]) + np[1] * rA[1] + sw * np[2] * (rA[1] + dr[1]);
    const cl = (v) => Math.max(-this.CLIP, Math.min(this.CLIP, v));          // one reading can only pull the middle so far (a long look to a side must not drag it over)
    this.m[0] += this.ETA_M * cl(resA); this.m[1] += this.ETA_M * cl(resB);
    const r2 = [x[0] - this.m[0], x[1] - this.m[1]];
    if (np[0] > 0.7) { const e = this.ETA_S * np[0]; this.dL[0] += e * (r2[0] - this.dL[0]); this.dL[1] += e * (r2[1] - this.dL[1]); this.fixSep(this.dL); }
    if (np[2] > 0.7) { const e = this.ETA_S * np[2]; this.dR[0] += e * (-r2[0] - this.dR[0]); this.dR[1] += e * (-r2[1] - this.dR[1]); this.fixSep(this.dR); }
    const k = np[0] > 0.6 ? 0 : np[2] > 0.6 ? 2 : np[1] > 0.6 ? 1 : -1;
    if (k >= 0) {
      const d = k === 0 ? this.dL : k === 2 ? [-this.dR[0], -this.dR[1]] : [0, 0], r0 = x[0] - this.m[0] - d[0], r1 = x[1] - this.m[1] - d[1], e = this.ETA_C;
      this.S[0] = Math.max((1 - e) * this.S[0] + e * r0 * r0, 1.2e-5); this.S[1] = Math.max((1 - e) * this.S[1] + e * r1 * r1, 1.2e-5);
      this.S[0] = Math.min(this.S[0], this.SMAX); this.S[1] = Math.min(this.S[1], this.SMAX);
      this.S[2] = Math.max(Math.min((1 - e) * this.S[2] + e * r0 * r1, 0.8 * Math.sqrt(this.S[0] * this.S[1])), 0);
    }
    // SANITY (the middle is the most common state: people mostly look ahead). The three places can slide together by one place (everything read as RIGHT while the middle drifts to sit above the
    // readings: the centre follows what it believes, so a wrong belief holds itself up). If the filter has spent less than 30% of the last 10 s in the MIDDLE, the middle is put back on the median
    // of the recent readings and the filter starts again from MIDDLE.
    this.xs.push(x); this.ss.push(this.state); if (this.xs.length > 150) { this.xs.shift(); this.ss.shift(); }
    if (this.xs.length >= 150 && this.n - this.lastFix > 15) {
      const occ = this.ss.reduce((c, v) => c + (v === 1 ? 1 : 0), 0) / this.ss.length;
      if (occ < 0.3) {
        const med = (k) => { const v = this.xs.map((q) => q[k]).sort((p, q2) => p - q2); return v[v.length >> 1]; };
        this.m = [med(0), med(1)]; this.post = [0.05, 0.9, 0.05]; this.state = 1; this.lastFix = this.n; this.fixes++; this.ss = this.ss.map(() => 1);
      }
    }
    // DECIDE with hysteresis
    let best = 0; for (let j = 1; j < 3; j++) if (np[j] > np[best]) best = j;
    if (np[best] > this.DECIDE) this.state = best;
    this.zn = np[2] - np[0];          // -1 = surely left, +1 = surely right (the game's convention: zone -1 is left)
    return this.state;
  }
  get zone() { return this.state - 1; }          // -1 left, 0 middle, +1 right
  supervise(x, k, w = 1) {          // a look whose lane is known (k = -1 / 0 / +1), with a trust w in 0..1 (1 = told to look there; less = inferred from what was worth taking): learn from it, gently
    if (!this.ready) return;
    this.labeled.push([[x[0], x[1]], k]); if (this.labeled.length > 200) this.labeled.shift();
    if (this.hold) return;          // the profile for this person / glasses is chosen first, from the first few labelled looks (the app releases the hold)
    const e = this.SUP * w;          // gentle: a few looks are only a start, and one odd look (the move itself, a blink, a wandering eye) must not set a side (it once taught a right look of A -0.044 / B -0.010 when play showed -0.020 / -0.020)
    if (k !== 0 && Math.abs((x[0] - this.m[0]) - (x[1] - this.m[1])) > 0.04) return;          // the two eyes disagree strongly: not a clean look
    const side = ((x[0] - this.m[0]) + (x[1] - this.m[1])) / 2;
    if ((k < 0 && side < 0.004) || (k > 0 && side > -0.004)) return;          // the reading is not on the side the look was meant for (the eyes were still on the way, or still on the last ring): a look to the right can not read left, so it teaches nothing
    if (k === 0) { this.m[0] += e * (x[0] - this.m[0]); this.m[1] += e * (x[1] - this.m[1]); }
    else {
      const r0 = x[0] - this.m[0], r1 = x[1] - this.m[1];
      if (k < 0) { this.dL[0] += e * (r0 - this.dL[0]); this.dL[1] += e * (r1 - this.dL[1]); this.fixSep(this.dL); }
      else { this.dR[0] += e * (-r0 - this.dR[0]); this.dR[1] += e * (-r1 - this.dR[1]); this.fixSep(this.dR); }
    }
    if (w >= 0.99) { this.post = k < 0 ? [0.9, 0.08, 0.02] : k > 0 ? [0.02, 0.08, 0.9] : [0.05, 0.9, 0.05]; this.state = k + 1; }
  }
  fit(dL, dR, data) {          // how well a set of left / right offsets explains labelled looks: the mean squared Mahalanobis distance (lower is better)
    let sum = 0, n = 0; const [ia, ib, ic] = this.inv();
    for (const [x, k] of data) { const d = k < 0 ? dL : k > 0 ? [-dR[0], -dR[1]] : [0, 0], r0 = x[0] - this.m[0] - d[0], r1 = x[1] - this.m[1] - d[1]; sum += ia * r0 * r0 + ib * r1 * r1 + 2 * ic * r0 * r1; n++; }
    return n ? sum / n : 99;
  }
  recentre() {          // put the middle on the median of the last ~4 s of readings and start again from MIDDLE (used by the live tuning)
    if (this.xs.length < 30) return false;
    const w = this.xs.slice(-60), med = (k) => { const v = w.map((q) => q[k]).sort((p, q) => p - q); return v[v.length >> 1]; };
    this.m = [med(0), med(1)]; this.post = [0.05, 0.9, 0.05]; this.state = 1; this.ss = this.ss.map(() => 1); return true;
  }
  save() { return { dL: this.dL, dR: this.dR, S: this.S }; }
}
