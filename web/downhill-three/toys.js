// TOYS and LINKED SET PIECES, ported from Godot's RunRig (_toys_tick, _sling_tick, _pill_eat, _gate_result, _mix_add, _surprise, _lk_start / _lk_step / _lk_end / _lk_payoff, and the pad-gem spin in _toys_tick),
// against the same level dump (lvl.rows[*].toys / pads[*].lk). Velocities are Godot's metres per second multiplied by SPK (the viewer's speed factor); distances, radii and timers are Godot's own.
//
//   bump    three cupcake bumpers: ride into one and it kicks you sideways (15 m/s * SPK), slows you a little, pays, springs back from 1.6x size
//   gates   rows of colour lollipops (sway on their sticks): the colour of the one you pass between is scored, same colour in a row = COLOUR CHAIN (match, boost, jackpot surprise)
//   sling   a stretch of ring that draws the board in (sideways pull and a forward pull building to the middle), then lets go with a boost
//   pill    a molecule (spins, bobs): eat it for points, a first-of-each-run bonus, and a hook for the trip effects
//   springs pads that carry a "lk" tube (pads[*].lk, from _make_link_chain): the pad catches the board, the board rides the dumped tube path, and is handed to the rail at its end
//   pad gems turn and bob (1.8 rad/s, 0.22 m)
//   mix     _mix_add: a chain of anything within 7 s; MEGA CHAIN at 6 / 10 / 15 links; four different kinds in 14 s fire a random SURPRISE
//
// Not fully ported: the "open" tube end is simplified (the held nudge picks one of the three catches and the prize is given at once; no flight to it). Not ported: the cavern ("cave"/"land")
// scenery, the XP / progress unlocks (DhProgress), molecule gifts (_mol_gift), the post pass's molecule doses (a hook is provided instead).
import * as THREE from 'three';

const ORDER = ['mescaline', 'dom', '2cb', '2ce', '2ct2', '2ct7'];
const GATE_NAMES = ['CYAN', 'PINK', 'GOLD'], GATE_COLS = ['#33f2ff', '#ff4de6', '#ffd933'];
const nameOf = (s) => String(s).replace(/^<node |>$/g, '');
const mat4 = (e) => new THREE.Matrix4().set(e[0], e[3], e[6], e[9], e[1], e[4], e[7], e[10], e[2], e[5], e[8], e[11], 0, 0, 0, 1);
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

export function createToys({ lvl, PH, th, SPK, hideNode, toast, SFX, REGN, hooks }) {
  hooks = hooks || {};
  const snd = (n, alt) => { const f = SFX[n] || SFX[alt || 'pick']; if (f) { try { f(); } catch (e) { } } };
  const ROWS = Object.values(lvl.rows);
  const TOYS = ROWS.flatMap((r) => r.toys || []), PADS = ROWS.flatMap((r) => r.pads || []);
  const NBN = {}; for (const n of lvl.nodes) NBN[n.name] = n;
  const S = { age: 0, links: 0, linkT: 0, mix: {}, mixT: 0, gateStreak: 0, gateCol: -1, pillN: 0, pillGap: 0, lk: null, lkDepth: 0, lkRecent: 0, lkDone: 0, flow: 0, mol: { got: [false, false, false, false, false, false], dose: [0, 0, 0, 0, 0, 0], flash: [0, 0, 0, 0, 0, 0] }, tube: { active: false, u: 0, t: [0, 0, -1], up: [0, 1, 0] } };

  // ---- moving things in the dump: a node's meshes, each with its original global matrix, so a node can be re-posed (spin, bob, sway, scale) about its own origin
  const REC = {};
  function rec(name) {
    name = nameOf(name); if (REC[name]) return REC[name]; const nd = NBN[name]; if (!nd) return (REC[name] = null);
    const base = mat4(nd.xf), meshes = [];
    for (const n of lvl.nodes) { if (n.class !== 'MeshInstance3D') continue; if (n.path === nd.path || n.path.startsWith(nd.path + '/')) for (const m of (REGN[n.name] || [])) meshes.push({ m, orig: m.matrix.clone(), path: n.path }); }
    return (REC[name] = { nd, base, inv: base.clone().invert(), meshes });
  }
  const _t = new THREE.Matrix4(), _u = new THREE.Matrix4();
  // pose(name, M): the node is moved from its dump pose to global matrix M; every mesh below it follows (M * base^-1 * orig)
  function pose(name, M) { const r = rec(name); if (!r) return; _t.copy(M).multiply(r.inv); for (const q of r.meshes) q.m.matrix.copy(_t).multiply(q.orig); }
  // poseUnder(name, parentName, Mparent_pose_delta, ...) is not needed: a child that spins inside a bobbing parent is posed with the parent's translation folded into M.
  const rotY = (a) => new THREE.Matrix4().makeRotationY(a), rotZ = (a) => new THREE.Matrix4().makeRotationZ(a);
  const trans = (x, y, z) => new THREE.Matrix4().makeTranslation(x, y, z), scl = (s) => new THREE.Matrix4().makeScale(s, s, s);
  const withY = (M, y) => { const o = M.clone(); o.elements[13] = y; return o; };

  // ---- scoring, flow and the chain of "linked" things
  const gain = (v) => { PH.score += v; };
  const flowUp = (n) => { S.flow += (n || 1); PH.flow = S.flow; };
  const cheer = (t, col) => toast(t, col);
  function surprise() {
    const r = Math.floor(Math.random() * 4);
    if (r === 0) { gain(1500); cheer('JACKPOT!', '#fd4'); }
    else if (r === 1) { PH.boost_t = Math.max(PH.boost_t, 4); const sp0 = Math.hypot(PH.vx, PH.vz), fx = Math.sin(PH.heading), fz = -Math.cos(PH.heading); PH.vx += fx * 7 * SPK; PH.vz += fz * 7 * SPK; const v = Math.hypot(PH.vx, PH.vz), lim = Math.max(57 * SPK, sp0); if (v > lim) { PH.vx *= lim / v; PH.vz *= lim / v; } cheer('TURBO SURPRISE!', '#f82'); }
    else if (r === 2) { PH.trip = Math.min(1, (PH.trip || 0) + .4); cheer('TRIP SURGE!', '#f4d'); if (hooks.onTrip) hooks.onTrip(.4); }
    else { gain(24 * 10); cheer('GLINT SHOWER!', '#fd4'); }
    snd('kaboom', 'blast'); flowUp(2);
  }
  function mixAdd(kind) {
    S.links++; S.linkT = 7;
    const L = S.links;
    if (L === 6 || L === 10 || L === 15 || (L > 15 && L % 8 === 0)) { gain(400 * L); cheer('MEGA CHAIN x' + L, '#fd4'); if (L >= 10) surprise(); }
    S.mix[kind] = true; S.mixT = 14;
    if (Object.keys(S.mix).length >= 4) { S.mix = {}; surprise(); }
  }
  PH.mixAdd = mixAdd;

  // ---- gates (colour lollipops)
  function gateResult(hit, first) {
    if (first) { S.gateStreak = 0; S.gateCol = -1; }
    if (hit < 0) { S.gateStreak = 0; S.gateCol = -1; return; }
    if (hit === S.gateCol) S.gateStreak++; else { S.gateCol = hit; S.gateStreak = 1; }
    const col = GATE_COLS[hit]; gain(60 * S.gateStreak); mixAdd('gate'); (hooks && hooks.quant ? hooks.quant : (f) => f())(() => snd('blip', 'orb'));          // the blip lands on the beat
    if (S.gateStreak === 2) toast('MATCH', col);
    else if (S.gateStreak === 3) { flowUp(1); PH.boost_t = Math.max(PH.boost_t, 1.5); cheer('COLOUR CHAIN x3', col); }
    else if (S.gateStreak >= 4) { gain(600); cheer('COLOUR CHAIN x' + S.gateStreak + ' !!', col); surprise(); }
  }

  // ---- pills
  function pillEat(t) {
    t.t = 1e15; hideNode(t.n);
    S.pillN = S.pillGap > 0 ? S.pillN + 1 : 1; S.pillGap = 6;
    const mi = Math.max(0, ORDER.indexOf(String(t.id))), first = !S.mol.got[mi], old = S.mol.dose[mi];
    if (first) { S.mol.got[mi] = true; S.mol.dose[mi] = 6; } else S.mol.dose[mi] = Math.min(S.mol.dose[mi] + 2, 6);
    S.mol.flash[mi] = 1; PH.trip = Math.min(1, (PH.trip || 0) + .25);
    gain(120 * S.pillN * (first ? 3 : 1)); flowUp(1); mixAdd('pill'); snd('pick');
    const nf = S.mol.got.filter(Boolean).length, col = 'rgb(' + (t.col || [.7, .5, 1]).slice(0, 3).map((c) => Math.round(c * 255)).join(',') + ')';
    if (first) { cheer(({ mescaline: '3,4,5-TMPEA', dom: '4-Me-2,5-DMA' }[t.id] || String(t.name)).toUpperCase() + ' FOUND  ' + nf + ' OF 6', col); if (nf === 5) toast('ONE MORE!', '#fd4'); } else toast(({ mescaline: '3,4,5-TMPEA', dom: '4-Me-2,5-DMA' }[t.id] || String(t.name)).toUpperCase() + '  topped up', col);
    if (S.pillN === 3) cheer('TRIPPING', '#f4d');
    if (hooks.onPill) hooks.onPill(t, first, mi, old);
  }

  // ---- sling: a ring that draws the board in then lets go
  function slingTick(t, dt) {
    const dz = PH.z - t.z;
    if (Math.abs(dz) < 100) for (const rr of (t.rings || [])) { rr.a = (rr.a || 0) + (Array.isArray(rr) ? rr[1] : 1) * dt; const nm = Array.isArray(rr) ? rr[0] : rr; const r = rec(nm); if (r) pose(nm, r.base.clone().multiply(rotY(rr.a))); }
    if (t.used) return;
    const dx = t.x - PH.x, low = PH.y - th(PH.x, PH.z) < 6, inside = dz < 24 && dz > -4 && Math.abs(dx) < 17 && low;
    if (inside) {
      if (!t.in) { t.in = true; snd('stretch'); }
      const near = 1 - clamp(Math.abs(dz) / 24, 0, 1);
      PH.vx += clamp(dx * 2.4, -15, 15) * SPK * dt * (.4 + near);
      PH.vz -= (9 + 38 * near) * SPK * dt;
      PH.vxa = Math.max(PH.vxa, .5);
    } else if (t.in && dz <= -4) {
      t.used = true; PH.vz -= 7 * SPK; PH.vxa = 1.2; PH.boost_t = Math.max(PH.boost_t, 1.6);
      gain(150); flowUp(1); mixAdd('sling'); snd('snap'); snd('whoosh', 'blast');
    }
  }

  // ---- springs: the pad's tube
  const ptAt = (d, u) => {
    const pts = d.pts, cum = d.cum, tl = cum[cum.length - 1], sd = clamp(u, 0, 1) * tl; let i = 1; while (i < cum.length - 1 && cum[i] < sd) i++;
    const seg = Math.max(cum[i] - cum[i - 1], .0001), f = clamp((sd - cum[i - 1]) / seg, 0, 1), a = pts[i - 1], b = pts[i];
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
  };
  const tanAt = (d, u) => { const tl = d.cum[d.cum.length - 1], e = 2 / Math.max(tl, 1), a = ptAt(d, Math.min(u + e, 1)), b = ptAt(d, Math.max(u - e, 0)); const v = [a[0] - b[0], a[1] - b[1], a[2] - b[2]], l = Math.hypot(...v) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
  const frameAt = (d, u) => {
    const cum = d.cum, sd = clamp(u, 0, 1) * cum[cum.length - 1]; let i = 1; while (i < cum.length - 1 && cum[i] < sd) i++;
    const seg = Math.max(cum[i] - cum[i - 1], .0001), f = clamp((sd - cum[i - 1]) / seg, 0, 1), ts = d.ts, us = d.us, nz = (v) => { const l = Math.hypot(...v) || 1; return [v[0] / l, v[1] / l, v[2] / l]; };
    const lp = (A, B) => [A[0] + (B[0] - A[0]) * f, A[1] + (B[1] - A[1]) * f, A[2] + (B[2] - A[2]) * f];
    return [nz(lp(ts[i - 1], ts[i])), nz(lp(us[i - 1], us[i]))];
  };
  function lkStart(d, pad) {
    const sp = (Math.max(-PH.vz, 24 * SPK) + 8 * SPK) * (hooks.lkSpeedK || 1);          // (a page may speed the arcs up: the Babylon game does)
    S.lk = { d, t: 0, dur: d.len / sp, sp, ri: 0 }; S.lkDepth = S.lkRecent > 0 ? S.lkDepth + 1 : 1;
    PH.slide = 0; PH.grounded = false; PH.air_t = 0; PH.vxa = Math.max(PH.vxa, 2.6); PH.latch = null; PH.rail = null;
    snd('pad'); cheer('SPRING!', '#f6e'); flowUp(1); gain(150); mixAdd('spring'); S.tube.active = true;
  }
  function lkStep(dt) {
    const L = S.lk, d = L.d; L.t += dt; const u = clamp(L.t / Math.max(L.dur, .1), 0, 1), pt = ptAt(d, u), tn = tanAt(d, u), sp = L.sp;
    const nr = d.nring | 0; if (nr > 0) { const ri = Math.floor(u * nr); if (ri > L.ri) { L.ri = ri; snd('orb'); if (hooks.onRing) hooks.onRing(ri); } }
    const fr = frameAt(d, u); S.tube.u = u; S.tube.t = fr[0]; S.tube.up = fr[1];
    const gh = th(pt[0], pt[2]); const free = hooks.lkFree ? hooks.lkFree() : 0; L.off = (L.off || 0) + ((clamp(S.lastS || 0, -1, 1) * free) - (L.off || 0)) * (1 - Math.exp(-dt / .2)); const hz = Math.hypot(tn[0], tn[2]) || 1; PH.x = pt[0] + (-tn[2] / hz) * L.off; PH.y = d.cave ? pt[1] : Math.max(pt[1], gh + .8); PH.z = pt[2];          // free: a small sideways drift inside the tube
    PH.vx = tn[0] * sp; PH.vz = tn[2] * sp; PH.vy = tn[1] * sp; PH.heading = Math.atan2(tn[0], -tn[2]) + clamp(S.lastS || 0, -1, 1) * (free ? .1 : 0); PH.grounded = false; PH.air_t = 0; PH.hurt = 0; PH.slide = 0; PH.gh_prev = gh;
    if (u >= 1) lkEnd(d);
  }
  function lkEnd(d) {
    S.tube.active = false;
    if (d.open && d.catch && d.catch.length) {          // the open end (_lk_open + _lkp_step + _lk_catch), simplified: the nudge you hold at the end picks left / middle / right, and you are given that prize at once
      const c = d.catch[S.lastS > .3 ? 2 : S.lastS < -.3 ? 0 : Math.min(1, d.catch.length - 1)] || d.catch[0], kind = c.kind; S.lk = null; PH.grounded = false; PH.vy = Math.min(PH.vy, -2);
      if (kind === 'gold') { gain(4000); cheer('JACKPOT!', '#fd4'); } else if (kind === 'boost') { PH.boost_t = Math.max(PH.boost_t, 7); PH.mult = Math.max(PH.mult || 0, 12); gain(900); cheer('TURBO!', '#f82'); } else { gain(900); cheer('MOLECULE!', '#b8f'); if (hooks.onPill) hooks.onPill({ name: 'catch', id: ORDER[S.lkDone % 6], col: c.col }, true, S.lkDone % 6, 0); }
      S.lkDone++; S.lkRecent = 10; PH.vxa = Math.max(PH.vxa, 3); return;
    }
    if (d.land) { S.lk = null; PH.grounded = false; gain(1800); PH.boost_t = Math.max(PH.boost_t, 3); cheer('CAVERN!', '#b6f'); S.lkDone++; S.lkRecent = 10; return; }
    const f = d.rail; S.lk = null; f.chain = true; f.sd = 0;          // the parent's featX must return f.kx when it is defined (the chain rail stands at kx, not on the trail's side line)
    PH.rail = f; PH.rail_dx = 0; PH.rail_z0 = PH.z; PH.rail_ok = false; PH.rail_out = 0; PH.rail_sp = 0; PH.grounded = true; PH.vy = 0; snd('grindOn', 'pick');
    flowUp(1); toast('TUBE TO RAIL', '#4ef');
  }
  // called by the parent when a rail that has .chain ends at its end (RunRig._rail_off -> _lk_payoff)
  function payoff() {
    S.lkDone++; const dp = Math.max(S.lkDepth, 1); S.lkRecent = 10;
    gain(500 * dp); PH.mult = Math.max(PH.mult || 0, 8 + 3 * dp); PH.boost_t = Math.max(PH.boost_t, 3 + .5 * dp); PH.vxa = Math.max(PH.vxa, 2.4);
    PH.trip = Math.min(1, (PH.trip || 0) + .08 + .03 * dp); cheer(dp === 1 ? 'CHAIN!' : 'CHAIN x' + dp + '!', '#f6e'); snd('kaboom', 'blast');
  }

  // ---- the per-frame tick (RunRig._toys_tick + _update_pads' spring catch + _lk_step), called after the board has moved
  function tick(dt, sIn) {
    S.lastS = sIn || 0;
    S.age += dt; S.linkT -= dt; if (S.linkT <= 0) S.links = 0; S.mixT -= dt; if (S.mixT <= 0 && Object.keys(S.mix).length) S.mix = {};
    S.pillGap = Math.max(S.pillGap - dt, 0); S.lkRecent = Math.max(S.lkRecent - dt, 0); for (let i = 0; i < 6; i++) S.mol.flash[i] = Math.max(S.mol.flash[i] - dt, 0);
    // pad gems turn and bob; a spring pad (one with a tube) catches the board
    const above = PH.y - th(PH.x, PH.z), low = PH.grounded || above <= 2.5;
    for (const p of PADS) {
      if (!p.gem || Math.abs(p.z - PH.z) > 150) continue; const r = rec(p.gem);
      if (r && !p.used) { p.a = (p.a || 0) + 1.8 * dt; pose(p.gem, withY(r.base, p.gy + .22 * Math.sin(S.age * 2.6 + p.ph)).multiply(rotY(p.a))); }
    }
    if (!S.lk && !PH.rail && (low || above <= 16)) for (const p of PADS) {
      if (!p.lk || p.used || Math.abs(p.z - PH.z) > 230) continue;
      if (Math.abs(p.z - 2.2 - PH.z) < 4.5 && Math.abs(p.x - PH.x) < 7.5) { p.used = true; if (p.gem) hideNode(p.gem); lkStart(p.lk, p); break; }
    }
    if (S.lk) { lkStep(dt); return; }
    const now = performance.now();
    for (const t of TOYS) {
      const tz = t.z, kind = t.kind;
      if (kind === 'gates') {
        if (Math.abs(tz - PH.z) < 90) for (const ln of t.lanes) if (!ln.hid) { const r = rec(ln.n); if (r) { const bs = 1 + .2 * ((hooks && hooks.beatK && hooks.beatK()) || 0); pose(ln.n, r.base.clone().multiply(rotZ(.16 * Math.sin(PH.vx_spin * 2.4 + ln.x))).multiply(new THREE.Matrix4().makeScale(bs, bs, bs))); }          /* the gates swell on every beat */ }
        if (t.done || PH.z > tz) continue;
        t.done = true; if (tz - PH.z > 8) continue;
        let hit = -1; for (const ln of t.lanes) if (Math.abs(ln.x - PH.x) < 3.2) { hit = ln.c; ln.hid = true; hideNode(ln.n); }
        gateResult(hit, t.r === 0); if (hit >= 0 && hooks && hooks.beatOff && hooks.beatOff() < .09) { gain(120); toast('ON BEAT', GATE_COLS[hit]); }          // through a gate on the beat
        continue;
      }
      if (kind === 'sling') { slingTick(t, dt); continue; }
      if (Math.abs(tz - PH.z) > 40) continue;
      const r = rec(t.n);
      if (kind === 'pill') {
        if (!t.hid && !t.eaten) {
          const gy0 = th(t.x + (t.px || 0), tz + (t.pz || 0)); if (t.y < gy0 + 1.5) { if (!t.rz) { t.rz = 1; try { (window.__dm || (() => {}))('PILL RAISED ' + t.id + ' y ' + t.y.toFixed(1) + ' ground ' + gy0.toFixed(1)); } catch (e) { } } t.y = gy0 + 3; } const by = t.y + .25 * Math.sin(S.age * 2.8 + t.x), sr = t.spin ? rec(t.spin) : null; t.a = (t.a || 0) + 2.4 * dt;
          /* A MOLECULE IS PULLED TOWARD YOU when you are close (a wider reach with a magnet), and it can be caught from further away: forgiving, not fiddly */
          { const pr = hooks && hooks.pillPull ? hooks.pillPull() : 0; if (pr > 0) { const ddx = PH.x - (t.x + (t.px || 0)), ddz = PH.z - (tz + (t.pz || 0)), dd = Math.hypot(ddx, ddz); if (dd < pr && dd > .01) { const k = Math.min(1, dt * (1.6 + 3 * (1 - dd / pr))); t.px = (t.px || 0) + ddx * k; t.pz = (t.pz || 0) + ddz * k; } } }
          if (r) { const dy = by - r.base.elements[13]; for (const q of r.meshes) { _t.copy(trans(t.px || 0, dy, t.pz || 0)); if (sr && q.path.startsWith(sr.nd.path)) _t.multiply(sr.base).multiply(rotY(t.a)).multiply(sr.inv); q.m.matrix.copy(_t).multiply(q.orig); } }
          const pdx = PH.x - (t.x + (t.px || 0)), pdz = PH.z - (tz + (t.pz || 0)), pk = hooks && hooks.pillK ? hooks.pillK() : 1;
          if (pdx * pdx + pdz * pdz < 9 * pk * pk && Math.abs(PH.y - by) < 4.5 + 2 * pk) { t.eaten = true; pillEat(t); }
        }
        continue;
      }
      if (kind === 'bump') {
        t.s = t.s === undefined ? 1 : 1 + (t.s - 1) * Math.exp(-8 * dt); if (r && t.s > 1.001) pose(t.n, r.base.clone().multiply(scl(t.s))); else if (r && t.sOn) { pose(t.n, r.base); t.sOn = false; }
        if (Math.abs(tz - PH.z) > 3.5 || now < (t.t || 0)) continue;
        const dx = PH.x - t.x, dz = PH.z - tz;
        if (dx * dx + dz * dz > 10 || above > 3.2) continue;
        t.t = now + 400; const l = Math.hypot(dx, dz), dxn = l > .1 ? dx / l : 1;
        PH.vx += dxn * 15 * SPK; PH.vz -= 2.5 * SPK; t.s = 1.6; t.sOn = true; gain(80); flowUp(1); mixAdd('bump'); snd('boing'); try { hooks && hooks.onBump && hooks.onBump(t.x, t.y, tz, dxn); } catch (e) { }
      }
    }
  }
  return { tick, payoff, active: () => !!S.lk, state: S, mixAdd, rail: () => (S.lk ? null : PH.rail) };
}
