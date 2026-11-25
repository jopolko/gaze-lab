/* MUSIC ENGINE for the game: GENERATED from musiclab.html by tools/make_engine.py (edit the lab, then rebuild). Needs Tone.js 14.8.49 loaded first. */
(() => {

          /* bigger buffers: no dropouts on phones */
/* ---------- seeded randomness: every track is a seed, so a good one can be kept */
let SEED = 1;
const mulberry = (a) => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
let R = mulberry(SEED); const pick = (a) => a[Math.floor(R() * a.length)];
const midi = (m) => Tone.Frequency(m, 'midi').toNote();
const md = (a, n) => ((a % n) + n) % n;
/* ---------- the genres' rules (hand-picked so nothing is ever random nonsense) */
const KEYS = [['A', 57], ['F', 53], ['G', 55], ['D', 50], ['E', 52], ['C', 48], ['B', 59]];
const MINOR = [0, 2, 3, 5, 7, 8, 10], DORIAN = [0, 2, 3, 5, 7, 9, 10], PHRYG = [0, 1, 3, 5, 7, 8, 10];
const HIJAZ = [0, 1, 4, 5, 7, 8, 10], DBLH = [0, 1, 4, 5, 7, 8, 11], HIRA = [0, 2, 3, 7, 8];
/* chord qualities (semitones over the chord's root) and how they're written */
const CQ = { m7: [0, 3, 7, 10], m9: [0, 3, 7, 10, 14], m11: [0, 3, 7, 10, 14, 17], madd9: [0, 3, 7, 14], maj7: [0, 4, 7, 11], maj9: [0, 4, 7, 11, 14], add9: [0, 4, 7, 14], '6/9': [0, 4, 7, 9, 14],
  sus2: [0, 2, 7, 14], '7sus4': [0, 5, 7, 10], '9': [0, 4, 7, 10, 14], 'maj7#11': [0, 4, 7, 11, 18], M: [0, 4, 7, 12], m: [0, 3, 7, 12], '5': [0, 7, 12, 19] };
const CLAB = { m7: 'm7', m9: 'm9', m11: 'm11', madd9: 'm(add9)', maj7: 'maj7', maj9: 'maj9', add9: 'add9', '6/9': '6/9', sus2: 'sus2', '7sus4': '7sus4', '9': '9', 'maj7#11': 'maj7♯11', M: '', m: 'm', '5': '5' };
/* the progressions (roots in semitones over the key's minor tonic): the loops melodic techno, trance and liquid jungle cry on. 2 bars a chord. */
const CPROGS = [
  { id: 'cry', mode: 'minor', c: [[0, 'm9'], [8, 'maj7'], [3, 'maj9'], [10, '6/9']] },          /* i - VI - III - VII */
  { id: 'longing', mode: 'minor', c: [[0, 'm9'], [5, 'm9'], [8, 'maj7'], [7, '7sus4']] },          /* i - iv - VI - v sus */
  { id: 'float', mode: 'minor', c: [[8, 'maj9'], [10, '6/9'], [0, 'm9'], [0, 'm11']] },          /* VI - VII - i */
  { id: 'rise', mode: 'minor', c: [[0, 'm9'], [3, 'maj7'], [10, 'add9'], [5, 'm9']] },          /* i - III - VII - iv */
  { id: 'night', mode: 'phrygian', c: [[0, 'm11'], [1, 'maj7'], [0, 'm11'], [10, 'add9']] },          /* i - bII: dark */
  { id: 'dorian', mode: 'dorian', c: [[0, 'm9'], [5, '9'], [0, 'm9'], [5, '9']] },          /* i9 - IV9 */
  { id: 'sparkle', mode: 'minor', c: [[0, 'madd9'], [8, 'add9'], [3, 'add9'], [10, 'add9']] },          /* trance add9s */
  { id: 'lift', mode: 'minor', c: [[8, 'maj7#11'], [10, '6/9'], [3, 'maj9'], [7, '7sus4']] },
  { id: 'ache', mode: 'minor', c: [[0, 'm9'], [7, 'm7'], [8, 'maj9'], [5, 'm11']] },          /* i - v - VI - iv */
  { id: 'deep', mode: 'minor', c: [[0, 'm11'], [0, 'm11'], [8, 'maj9'], [10, '7sus4']] },
  { id: 'home', mode: 'minor', c: [[3, 'maj9'], [10, '6/9'], [5, 'm9'], [0, 'm11']] },          /* III - VII - iv - i */
  { id: 'drift', mode: 'minor', c: [[0, 'm9'], [10, 'sus2'], [8, 'maj7'], [5, 'm9']] }];
/* eastern: modal, so the chords stay close to the drone */
const ESCALES = [{ id: 'hijaz', name: 'Hijaz', sc: HIJAZ, progs: [[[0, 'M'], [1, 'M'], [0, 'M'], [10, 'm']], [[0, '5'], [1, 'M'], [5, 'm'], [0, 'M']]] },
  { id: 'dblh', name: 'Double harmonic', sc: DBLH, progs: [[[0, 'M'], [1, 'M'], [5, 'm'], [1, 'M']], [[0, '5'], [0, '5'], [1, 'maj7'], [0, '5']]] },
  { id: 'hira', name: 'Hirajoshi', sc: HIRA, progs: [[[0, 'madd9'], [8, 'maj7'], [0, 'madd9'], [7, '5']], [[0, 'sus2'], [8, 'maj7#11'], [7, '5'], [0, 'madd9']]] }];
const FUNKP = [[0, 3], [0, 0, 3, 3], [0, 3, 0, 4], [3, 3, 0, 0], [0, 6, 5, 3], [0, 5, 4, 3], [0, 3, 6, 4], [0, 0, 6, 6], [0, 2, 3, 4], [0, 6, 3, 3]];          /* funk vamps, played as 7th chords (scale degrees) */
const STYLES = { acid: { bpm: [128, 134] }, techno: { bpm: [122, 133] }, jungle: { bpm: [168, 175] }, eastern: { bpm: [116, 126] }, disco: { bpm: [116, 122] }, boogie: { bpm: [104, 112] }, break: { bpm: [92, 102] } };
const FUNKS = ['disco', 'boogie', 'break'];
/* each level's music: what hypes it or calms it (the game uses these): name, style, bpm range, trance 0-100, energy 0-100 */
const LVLP = { routezero: ['Route Zero', 'techno', [126, 130], 30, 92], candy: ['Sugarfall', 'boogie', [106, 110], 55, 70], alpine: ['The Safe Peaks', 'techno', [116, 120], 85, 40], egypt: ['Tomb of the Old Servers', 'eastern', [118, 124], 40, 80],
  synthwave: ['Neon Accord', 'disco', [118, 122], 70, 80], tunnel: ['The Undertow', 'jungle', [170, 174], 35, 100], matrix: ['Cold Rack', 'break', [94, 100], 25, 90], psychedelic: ['The Open Channel', 'techno', [130, 134], 90, 95] };
/* your saves teach it: progressions and scales you keep come up more */
const rdT0 = () => { try { return JSON.parse(localStorage.getItem('dl_tracks') || '[]'); } catch (e) { return []; } };
function pickW(list, keyOf, counts) { const w = list.map((x) => 1 + 3 * (counts[keyOf(x)] || 0)), tot = w.reduce((a, b) => a + b, 0); let q = R() * tot; for (let i = 0; i < list.length; i++) { q -= w[i]; if (q <= 0) return list[i]; } return list[list.length - 1]; }
const FARRS = [[['INTRO', 8], ['GROOVE', 16], ['BREAK', 8], ['DROP', 16], ['GROOVE', 16], ['BREAK', 8], ['DROP', 16], ['OUTRO', 8]], [['INTRO', 4], ['GROOVE', 16], ['DROP', 16], ['BREAK', 8], ['RISE', 4], ['DROP', 16], ['OUTRO', 8]]];
const ARRS = [
  [['INTRO', 16], ['BUILD', 16], ['GROOVE', 32], ['BREAK', 16], ['RISE', 8], ['DROP', 32], ['GROOVE', 16], ['BREAK', 8], ['DROP', 32], ['OUTRO', 16]],
  [['INTRO', 8], ['GROOVE', 16], ['BUILD', 8], ['DROP', 32], ['BREAK', 16], ['RISE', 8], ['DROP', 32], ['OUTRO', 16]],
  [['INTRO', 16], ['GROOVE', 32], ['BREAK', 16], ['RISE', 8], ['DROP', 32], ['BREAK', 16], ['RISE', 8], ['DROP', 32], ['OUTRO', 8]]];
const JARRS = [[['INTRO', 8], ['ROLL', 8], ['DROP', 32], ['BREAK', 16], ['RISE', 4], ['DROP', 32], ['SWITCH', 16], ['DROP', 16], ['OUTRO', 8]],
  [['INTRO', 8], ['DROP', 32], ['BREAK', 8], ['RISE', 4], ['SWITCH', 16], ['DROP', 32], ['OUTRO', 8]]];
/* which parts play in each section: kick, hats, open hat, clap, rumble, bass, pad, arp, lead, ride */
const SECT = {
  INTRO: { k: 1, h: .6, oh: 0, cl: 0, ru: .5, ba: 0, pad: .5, arp: 0, ld: 0, ri: 0 },
  BUILD: { k: 1, h: 1, oh: 1, cl: .6, ru: 1, ba: 1, pad: .6, arp: .5, ld: 0, ri: .5 },
  GROOVE: { k: 1, h: 1, oh: 1, cl: 1, ru: 1, ba: 1, pad: .7, arp: .6, ld: .4, ri: 1 },
  BREAK: { k: 0, h: .3, oh: 0, cl: 0, ru: 0, ba: 0, pad: 1, arp: .7, ld: 1, ri: 0 },
  RISE: { k: .5, h: 1, oh: 0, cl: 1, ru: 0, ba: .4, pad: 1, arp: 1, ld: .7, ri: 0, riser: 1 },
  DROP: { k: 1, h: 1, oh: 1, cl: 1, ru: 1, ba: 1, pad: 1, arp: 1, ld: 1, ri: 1 },
  OUTRO: { k: 1, h: .6, oh: .5, cl: 0, ru: .6, ba: .5, pad: .7, arp: 0, ld: 0, ri: 0 } };
/* jungle: the break, the sub, the reese, pads, the atmosphere loop, a lead in the breakdowns */
const JSECT = {
  INTRO: { brk: 0, sub: 0, rs: 0, pad: 1, atm: 1, ld: 0, sh: .5 },
  ROLL: { brk: .6, sub: 1, rs: 0, pad: .8, atm: .7, ld: 0, sh: 1 },
  DROP: { brk: 1, sub: 1, rs: 1, pad: .55, atm: .3, ld: 0, sh: 1 },
  BREAK: { brk: 0, sub: .6, rs: 0, pad: 1, atm: 1, ld: 1, sh: 0 },
  RISE: { brk: .6, sub: 0, rs: 0, pad: 1, atm: .6, ld: .6, sh: 1, riser: 1, roll: 1 },
  SWITCH: { brk: 1, sub: 1, rs: 1, pad: .35, atm: .2, ld: .5, sh: 1, alt: 1 },
  OUTRO: { brk: .6, sub: .5, rs: 0, pad: .8, atm: 1, ld: 0, sh: .5 } };
/* ---------- the kits: CC0 drum samples (Stargate sample pack, samples/LICENSE-CC0.txt); each track picks its own combination */
const KIT = { snare: ['x0xproc1-snare'], kick: ['x0xproc1-kick', 'x0xproc2-kick', 'distkit-kick', 'synthkit-kick', 'kick-1-A', 'kick-2-A', '266764__hard3eat__synth-kick-3'], clap: ['x0xproc1-clap', 'x0xproc2-clap', 'synthkit-clap', '509526__synthnisse__claps'],
  hat: ['x0xproc1-hatclsd', 'x0xproc2-hatclsd', 'synthkit-hatclsd', '439766__twentytwentymusic__electronic-closed-hat-9'], oh: ['x0xproc1-hatopen', 'x0xproc2-hatopen', '165028__rodrigo-the-mad__mini-909ish-open-hat'], ride: ['x0xproc1-ride', 'synthkit-ride'],
  perc: ['x0xproc2-rimshot', 'x0xproc2-cowbell', 'sdbkit-fmperc', 'x0xproc2-maracas', 'distkit-zap'], crash: ['x0xproc1-crash'] };
const ALLS = [...new Set(Object.values(KIT).flat())];
/* THE BREAK (samples/Drums_170BPM.wav, CC0): four bars at 170, cut into 64 sixteenths. Each hit's slices, found by ear-maths (tools: onset energy and spectrum per slice). */
const BRK = { bpm: 170, n: 64, K: [0, 10, 16, 22, 28, 32, 42, 48, 54, 60], S: [4, 12, 18, 24, 30, 36, 44, 50, 56, 62], H: [2, 6, 8, 14, 20, 26, 34, 38, 40, 46, 52, 58], G: [21, 27, 53, 59] };
/* jungle patterns over one bar: K kick, S snare, G ghost snare, H hat, r a snare roll (two 32nds), . nothing (the last hit rings) */
const JPAT = { two: 'K.H.S.H.HHK.S.H.', amen: 'K.K.S.GSG.KKS.GS', roll: 'K.HGS.GKG.K.S.GG', half: 'K.H.H.H.S.H.H.GH', chop: 'K.S.K.SSK.HGS.rr', step: 'K..KS.G.K.K.S.GH', tear: 'KGS.GKS.KGS.GKSr' };
const JFILL = ['S.S.SSS.SSSSrrrr', 'K.S.KSS.SSSSSSSS', 'SGSGSGSGrrrrrrrr', 'K.S.K.S.SSSSrrrr'];
/* eastern percussion (darbuka): D doum, T tek, k ka (a ghost) */
const DPAT = { maqsum: 'D.T.k.T.D.k.T.kk', baladi: 'D.D.k.T.D.k.T.k.', ayoub: 'D.kDT.k.D.kDT.k.', saidi: 'D.T.k.D.D.k.T.k.' };
/* ACID: 303 lines (eighths, semitones over the root at A1-G#2); the first is the Pattern Desk's acid line, and seed 132 always plays it exactly (A, 132 BPM) */
const ACANON = { line: [0, 0, 12, 0, 3, 0, -2, 12, -4, -4, 8, -4, 0, -4, -5, 8, -7, -7, 5, -7, -4, -7, -9, 5, -5, -5, 7, -5, 0, -1, 2, 7],          /* F minor: Fm, Db, Bbm, then C: sus4 (F) to the third (E), the fifth, home */
  prog: { id: 'canon', mode: 'minor', c: [[0, 'm9'], [8, 'maj7'], [5, 'm9'], [7, '7sus4']] } };
const ALINES = [[0, 0, 12, 0, 3, 0, -2, 12], [0, 12, 0, 0, 10, 0, 7, 12], [0, 0, 3, 0, 12, 0, 5, 7], [0, 7, 0, 12, 0, 3, 10, 0], [0, 0, 12, 10, 0, 0, 3, 5], [12, 0, 0, 12, 0, 7, 0, 10]];
/* the slow build: the line alone, then the kick, then the hats, then a snare accent (the offbeat of beat 4, every other bar, caught on the next downbeat), then the groove;
   a breakdown brings the pads in, and the drop has everything */
const AARRS = [[['ACID', 16], ['KICK', 8], ['HATS', 8], ['SNARE', 16], ['FULL', 32], ['BREAK', 8], ['DROP', 32], ['OUTRO', 8]]];
const ASECT = { ACID: { k: 0, h: 0, sn: 0, oh: 0, ru: 0, cl: 0, pad: 0 }, KICK: { k: 1, h: 0, sn: 0, oh: 0, ru: 0, cl: 0, pad: 0 }, HATS: { k: 1, h: 1, sn: 0, oh: 0, ru: 0, cl: 0, pad: 0 },
  SNARE: { k: 1, h: 1, sn: 1, oh: 0, ru: .5, cl: 0, pad: 0 }, FULL: { k: 1, h: 1, sn: 1, oh: 1, ru: 1, cl: 0, pad: 0 }, BREAK: { k: 0, h: .5, sn: 0, oh: 0, ru: 0, cl: 0, pad: 1, riser: 1 },
  DROP: { k: 1, h: 1, sn: 1, oh: 1, ru: 1, cl: 1, pad: .55 }, OUTRO: { k: 1, h: 1, sn: 0, oh: 0, ru: .5, cl: 0, pad: .3 } };
/* techno basslines: where the bass speaks in each bar (never with the kick) */
const BPATS = [[0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1], [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1], [0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1], [0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 1, 0, 1]];
/* ---------- voicing: the pad's chord, placed so it moves as little as possible from the last one (voice leading) */
function voice(prev, rootPc, q, lo, hi) {
  let iv = CQ[q]; if (iv.length >= 5) iv = iv.slice(1);          /* five-note chords drop the root (the bass has it) */
  const pcs = [...new Set(iv.map((i) => md(rootPc + i, 12)))], cands = [];
  for (let r = 0; r < pcs.length; r++) { const ord = pcs.slice(r).concat(pcs.slice(0, r)); let n = lo; while (md(n, 12) !== ord[0]) n++; const v = [n]; for (let k = 1; k < ord.length; k++) { let m = v[k - 1] + 1; while (md(m, 12) !== ord[k]) m++; v.push(m); }
    if (v[v.length - 1] <= hi) cands.push(v); if (v.length >= 4) { const o = v.slice(); o[1] += 12; o.sort((a, b) => a - b); if (o[o.length - 1] <= hi + 4) cands.push(o); } }          /* close and open (drop-2 style) voicings */
  if (!cands.length) return pcs.map((p) => lo + md(p - lo, 12)).sort((a, b) => a - b);
  const mid = (lo + hi) / 2, cost = (v) => { if (!prev) return Math.abs(v.reduce((a, b) => a + b, 0) / v.length - mid); let c = 0; for (const n of v) c += Math.min(...prev.map((p) => Math.abs(p - n))); return c + .6 * Math.abs(v[v.length - 1] - prev[prev.length - 1]); };
  return cands.reduce((b, v) => (cost(v) < cost(b) ? v : b));
}
const snapTo = (n, pcs) => { for (const d of [0, -1, 1, -2, 2, -3, 3]) if (pcs.includes(md(n + d, 12))) return n + d; return n; };
/* ---------- THE PARTS LIBRARY and THE TUNER. A track is one part per layer (chords, beat, bass, pads, melody), each from a short hand-picked list that suits
   its genre, so every combination sounds right together. Your ratings (the Music Lab's tuner: like, dislike, swap) decide how often a part comes up:
   a liked part more, a disliked one never; parts heard in the last few tracks rest; one track in five tries parts you have not rated (so it keeps finding new
   ones without getting ugly). The game reads the same ratings, so tuning here shapes every level. */
const TBEATS = [          /* straight 16ths, no swing. kdec/kpd/koct/drive shape the kick; rumble = how much reverb-rumble sits under it; ride = ride on the offbeats */
  { id: 'berlin', name: 'Berlin', hat: [0, .16, 0, .16, 0, .16, 0, .2, 0, .16, 0, .16, 0, .16, 0, .2], oh: [2, 6, 10, 14], clap: [12], perc: [], ride: true, kdec: .45, kpd: .035, koct: 3.5, drive: .45, rumble: .6 },
  { id: 'rumble', name: 'Rumble', hat: [0, 0, .3, 0, 0, 0, .3, 0, 0, 0, .3, 0, 0, 0, .3, .14], oh: [], clap: [], perc: [7], ride: false, kdec: .5, kpd: .03, koct: 3, drive: .55, rumble: 1 },
  { id: 'industrial', name: 'Industrial', hat: [.18, .3, .22, .3, .18, .3, .22, .3, .18, .3, .22, .3, .18, .3, .22, .34], oh: [6, 14], clap: [4, 12], perc: [3, 11], ride: false, kdec: .36, kpd: .03, koct: 4, drive: .8, rumble: .4 },
  { id: 'tribal', name: 'Tribal', hat: [0, 0, .26, 0, 0, 0, .26, 0, 0, 0, .26, 0, 0, 0, .26, 0], oh: [], clap: [12], perc: [3, 6, 9, 11, 14], ride: false, kdec: .4, kpd: .04, koct: 3.5, drive: .4, rumble: .5 },
  { id: 'hypnotic', name: 'Hypnotic', hat: [.12, .12, .3, .12, .12, .12, .3, .12, .12, .12, .3, .12, .12, .12, .3, .12], oh: [2, 10], clap: [], perc: [7, 15], ride: true, kdec: .45, kpd: .035, koct: 3.2, drive: .35, rumble: .7 },
  { id: 'peak', name: 'Peak-time', hat: [.16, .26, .2, .26, .16, .26, .2, .26, .16, .26, .2, .26, .16, .26, .2, .3], oh: [2, 6, 10, 14], clap: [4, 12], perc: [15], ride: true, kdec: .42, kpd: .035, koct: 4, drive: .6, rumble: .6 }];
const KDEF = { kdec: .38, kpd: .05, koct: 6, drive: .32 };          /* the kick for every other style */
const TBASS = [          /* q = resonance, base/oct = filter floor and sweep (dark), sus/dec = note shape */
  { id: 'rolling', name: 'Rolling', v: [0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1], q: 5, base: 70, oct: 2.2, sus: .15, dec: .12 },
  { id: 'offbeat', name: 'Offbeat', v: [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0], q: 2.5, base: 60, oct: 1.8, sus: .4, dec: .18, dur: '8n' },
  { id: 'subdrone', name: 'Sub drone + stab', v: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0], mode: 'drone', q: 1.5, base: 55, oct: 1.1, sus: .75, dec: .4 },
  { id: 'acid', name: 'Acid 303', v: [1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1], mode: 'acid', q: 13, base: 110, oct: 3, sus: .1, dec: .14 },
  { id: 'gallop', name: 'Gallop', v: [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1], q: 4, base: 65, oct: 2, sus: .2, dec: .11 }];
const BDEF = { q: 4, base: 90, oct: 3.2, sus: .2, dec: .16 };          /* the bass synth as the other styles use it */
const ACIDS = [{ id: 'classic', name: 'Classic', v: ALINES[0] }, { id: 'climb', name: 'Octave climb', v: ALINES[1] }, { id: 'walk', name: 'Minor walk', v: ALINES[2] }, { id: 'fifth', name: 'Fifth bounce', v: ALINES[3] }, { id: 'pulse', name: 'Low pulse', v: ALINES[4] }, { id: 'high', name: 'High octave', v: ALINES[5] }];
const JBEATS = [{ id: 'twostep', name: 'Two-step', jp: ['two', 'amen'], alt: 'half' }, { id: 'amen', name: 'Amen-style', jp: ['amen', 'chop'], alt: 'tear' }, { id: 'roll', name: 'Roller', jp: ['roll', 'two'], alt: 'step' },
  { id: 'step', name: 'Stepper', jp: ['step', 'amen'], alt: 'chop' }, { id: 'tear', name: 'Tear-out', jp: ['tear', 'roll'], alt: 'half' }, { id: 'chop', name: 'Choppy', jp: ['chop', 'two'], alt: 'tear' }];
const REESES = [{ id: 'push', name: 'Push', riff: [0, 6, 10], off: [0, 7, 12] }, { id: 'hold', name: 'Long hold', riff: [], off: [] }, { id: 'stab', name: 'Stabs', riff: [0, 3, 6, 10, 13], off: [0, 0, 12, 7, 0] }, { id: 'climb', name: 'Climb', riff: [0, 4, 8, 12], off: [0, 3, 5, 7] }];
const DBEATS = Object.keys(DPAT).map((k) => ({ id: k, name: k[0].toUpperCase() + k.slice(1), v: DPAT[k] }));
const EPROGS = ESCALES.flatMap((E) => E.progs.map((c, i) => ({ id: E.id + i, name: E.name + (i ? ' II' : ''), E, c })));
const PADS = [{ id: 'warm', name: 'Warm saws', o: { type: 'sawtooth', count: 2, spread: 24, attack: 1.1, release: 2 }, lfo: [600, 2400] }, { id: 'glass', name: 'Glass', o: { type: 'triangle', count: 2, spread: 10, attack: .6, release: 2.6 }, lfo: [1400, 4200] },
  { id: 'choir', name: 'Soft choir', o: { type: 'sine', count: 3, spread: 14, attack: 1.4, release: 2.8 }, lfo: [900, 3000] }, { id: 'dark', name: 'Dark', o: { type: 'square', count: 2, spread: 30, attack: 1.6, release: 3 }, lfo: [300, 1200] }];
const MELS = [{ id: 'lift', name: 'Lift', v: [0, 3, 6, 8, 11, 14, 16, 19] }, { id: 'skip', name: 'Skip', v: [0, 2, 4, 7, 10, 12, 16, 22] }, { id: 'push', name: 'Push', v: [0, 3, 4, 8, 11, 12, 15, 24] }, { id: 'wide', name: 'Wide', v: [0, 4, 6, 8, 12, 14, 20, 22] }, { id: 'sparse', name: 'Sparse', v: [0, 6, 8, 14, 16, 22, 24, 28] }];
const FCHORDS = FUNKP.map((p, i) => ({ id: 'v' + i, name: 'Vamp ' + (i + 1), v: p }));
const FBEATS = [{ id: 'one', name: 'On the one', k: 0, g: 0 }, { id: 'pocket', name: 'Pocket', k: 1, g: 2 }, { id: 'push', name: 'Push', k: 2, g: 1 }, { id: 'late', name: 'Late kick', k: 3, g: 3 }, { id: 'skip', name: 'Skip', k: 4, g: 0 }, { id: 'ghost', name: 'Ghosty', k: 0, g: 3 }];
const FBASS = ['Slap walk', 'Octave pop', 'Syncopated', 'Sparse', 'Busy'].map((name, i) => ({ id: 'b' + i, name, v: i }));
const rdJ = (k, d) => { try { return JSON.parse(localStorage.getItem(k) || 'null') || d; } catch (e) { return d; } }, wrJ = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { } };
let RATE = rdJ('dl_parts', {}), RECENT = rdJ('dl_recent', []), OVR = null;
/* pick a part: always two random numbers (so the other layers stay put when one is swapped), your ratings, freshness, one in five a discovery */
function choose(key, list) { const a = R(), b = R(); if (OVR && OVR[key]) { const o = list.find((x) => x.id === OVR[key]); if (o) return o; }
  let ok = list.filter((x) => (RATE[key + '.' + x.id] || 0) > -1); if (!ok.length) ok = list;
  if (b < .2) { const un = ok.filter((x) => !RATE[key + '.' + x.id]); const pool = un.length ? un : ok; return pool[Math.floor(a * pool.length)]; }
  const w = ok.map((x) => (1 + 2 * Math.max(0, RATE[key + '.' + x.id] || 0)) * (RECENT.includes(key + '.' + x.id) ? .25 : 1)), tot = w.reduce((p, q) => p + q, 0); let q = a * tot;
  for (let i = 0; i < ok.length; i++) { q -= w[i]; if (q <= 0) return ok[i]; } return ok[ok.length - 1]; }
const LAYER = { cp: 'Chords', ec: 'Chords', fc: 'Chords', tb: 'Beat', jb: 'Beat', eb: 'Beat', fb: 'Beat', tbs: 'Bass', ac: 'Bass', rs: 'Bass', fbs: 'Bass', pd: 'Pads', ml: 'Melody' };
const LISTS = () => ({ cp: CPROGS, ec: EPROGS, fc: FCHORDS, tb: TBEATS, jb: JBEATS, eb: DBEATS, fb: FBEATS, tbs: TBASS, ac: ACIDS, rs: REESES, fbs: FBASS, pd: PADS, ml: MELS });
/* swap one layer, live: the same track with only that part changed (and never a part you disliked) */
function swapPart(key) { if (!T || !T.parts) return; const cur = T.parts.find((p) => p.key === key); if (!cur) return; const list = LISTS()[key], ok = list.filter((x) => x.id !== cur.id && (RATE[key + '.' + x.id] || 0) > -1); if (!ok.length) return;
  OVR = Object.fromEntries(T.parts.map((p) => [p.key, p.id])); OVR[key] = ok[Math.floor(Math.random() * ok.length)].id; const keep = SEED; try { makeTrack(); } finally { OVR = null; SEED = keep; } }
function ratePart(key, v) { if (!T || !T.parts) return; const cur = T.parts.find((p) => p.key === key); if (!cur) return; const k = key + '.' + cur.id; RATE[k] = v < 0 ? -1 : Math.min(5, Math.max(0, RATE[k] || 0) + 1); wrJ('dl_parts', RATE); if (v < 0) swapPart(key); }
function rememberParts() { if (OVR || !T || !T.parts) return; RECENT = RECENT.filter((k) => !T.parts.some((p) => p.key + '.' + p.id === k)).concat(T.parts.map((p) => p.key + '.' + p.id)).slice(-18); wrJ('dl_recent', RECENT); }
/* ---------- the track (made from the seed) */
let T = null;
let STYLE = 'techno', LV = null;
function makeTrack() { R = mulberry(SEED); const sv = rdT0(), pc = {}, mc = {}; for (const t of sv) { if (t.prog) pc[[].concat(t.prog).join(',')] = (pc[[].concat(t.prog).join(',')] || 0) + 1; if (t.mode) mc[t.mode] = (mc[t.mode] || 0) + 1; }
  const funk = FUNKS.includes(STYLE), P0 = LV ? LVLP[LV] : null, canon = STYLE === 'acid' && +SEED === 132; let [kn, root] = pick(KEYS); if (canon) { kn = 'F'; root = 53; }
  const br = P0 ? P0[2] : STYLES[STYLE].bpm; let bpm = br[0] + Math.floor(R() * (br[1] - br[0] + 1)); if (canon) bpm = 128;
  const kit = { kick: pick(KIT.kick), clap: pick(KIT.clap), hat: pick(KIT.hat), oh: pick(KIT.oh), ride: pick(KIT.ride), perc: pick(KIT.perc), crash: KIT.crash[0] }, pmask = Array.from({ length: 16 }, (_, i) => (i % 4 === 3 || i === 6 || i === 10) && R() < .45 ? 1 : 0);
  const hacc = Array.from({ length: 16 }, (_, i) => (i % 4 === 2 ? .9 : i % 2 ? .45 : .65) * (.85 + R() * .3));
  const melP = choose('ml', MELS), rh = melP.v, parts = [];
  let d = pick([0, 2, 4]); const motif = rh.map((st, i) => { if (i) d += pick([-1, -1, 1, 1, 2, -2, 0, 3]); d = Math.max(-2, Math.min(9, d)); return { st, d, len: pick([2, 2, 3, 4]) }; });
  const secsOf = (arr) => { const secs = []; let b = 0; for (const [n, len] of arr) { secs.push({ n, b0: b, len }); b += len; } return [secs, b]; };
  if (funk) {          /* FUNK: unchanged from v2 (scale-degree 7th chords) */
    const MODES = [['dorian', DORIAN], ['dorian', DORIAN], ['minor', MINOR]], mm = pickW(MODES, (x) => x[0], mc), mode = mm[1], fcP = choose('fc', FCHORDS), prog = fcP.v, arr = pick(FARRS);
    const deg = (d2, oct) => root + 12 * (oct || 0) + mode[md(d2, 7)] + 12 * Math.floor(d2 / 7), chord = (d2) => [deg(d2), deg(d2 + 2), deg(d2 + 4), deg(d2 + 6)];
    const FK = { kick: [[0, 6, 10], [0, 7, 10], [0, 3, 10], [0, 10, 13], [0, 8, 11]], ghost: [[7, 9, 14], [3, 7, 15], [7, 11, 14], [9, 14, 15]], bass: [[0, 3, 6, 8, 10, 13, 14], [0, 2, 6, 7, 10, 12, 14], [0, 3, 4, 7, 10, 11, 14], [0, 6, 8, 9, 12, 14], [0, 3, 6, 10, 11, 13]], clav: [[2, 5, 6, 10, 13, 14], [1, 3, 6, 9, 11, 14], [2, 3, 7, 10, 12, 15], [3, 6, 7, 11, 14]], keys: [[2, 6, 10, 14], [3, 6, 11, 14], [2, 7, 10, 15]] };
    const fbP = choose('fb', FBEATS), fbsP = choose('fbs', FBASS); parts.push({ key: 'fc', id: fcP.id, name: fcP.name }, { key: 'fb', id: fbP.id, name: fbP.name }, { key: 'fbs', id: fbsP.id, name: fbsP.name }, { key: 'ml', id: melP.id, name: melP.name });
    const fk = { kick: FK.kick[fbP.k], ghost: FK.ghost[fbP.g], bass: FK.bass[fbsP.v], clav: pick(FK.clav), keys: pick(FK.keys), boctave: FK.bass[0].map(() => R() < .3) };
    const pent = [0, 3, 5, 7, 10], pdeg = (i, oct) => root + 12 * (oct || 0) + pent[md(i, 5)] + 12 * Math.floor(i / 5), [secs, bars] = secsOf(arr);
    T = { style: STYLE, kind: 'funk', funk: true, parts, fk, pdeg, modeName: mm[0], kn, root, mode, prog, bpm, deg, chord, motif, secs, bars, kit, pmask, hacc, name: kn + ' ' + mm[0] };
  } else {
    const kind = STYLE; let cprog, mode, modeName, scName = null;
    if (kind === 'eastern') { const ep = choose('ec', EPROGS), E = ep.E; scName = E.name; mode = E.sc; modeName = E.id; cprog = { id: ep.id, c: ep.c }; parts.push({ key: 'ec', id: ep.id, name: ep.name }); }
    else { cprog = choose('cp', CPROGS); parts.push({ key: 'cp', id: cprog.id, name: cprog.id[0].toUpperCase() + cprog.id.slice(1) }); if (canon) cprog = ACANON.prog; modeName = cprog.mode; mode = { minor: MINOR, dorian: DORIAN, phrygian: PHRYG }[cprog.mode]; }
    const n = mode.length, deg = (d2, oct) => root + 12 * (oct || 0) + mode[md(d2, n)] + 12 * Math.floor(d2 / n);
    /* the voicings, led through the loop twice so the first chord also follows the last */
    const lo = kind === 'jungle' ? 53 : 55, hi = kind === 'jungle' ? 77 : 76; let prev = null; const pv = []; for (let k = 0; k < cprog.c.length * 2; k++) { const [s, q] = cprog.c[k % cprog.c.length]; prev = voice(prev, md(root + s, 12), q, lo, hi); if (k >= cprog.c.length) pv.push(prev); }
    const bn = cprog.c.map(([s]) => 33 + md(root + s - 33, 12)), pcs = cprog.c.map(([s, q]) => CQ[q].map((i) => md(root + s + i, 12)));          /* bass roots between A1 and G#2; each chord's pitch classes */
    const arr = pick(kind === 'jungle' ? JARRS : kind === 'acid' ? AARRS : ARRS), [secs, bars] = secsOf(arr), acP = choose('ac', ACIDS), aline = canon ? ACANON.line : acP.v;
    const tbsP = choose('tbs', TBASS), bpat = tbsP.v, tbP = choose('tb', TBEATS), jbP = choose('jb', JBEATS), rsP = choose('rs', REESES), ebP = choose('eb', DBEATS), pdP = choose('pd', PADS), boct = Array.from({ length: 16 }, (_, i) => (i % 4 === 3 && R() < .3 ? 12 : i === 14 && R() < .3 ? 7 : 0)), arpMode = pick(['up', 'updown', 'gate', 'up']);
    const gate = Array.from({ length: 16 }, (_, i) => (i % 2 === 0 || R() < .35 ? 1 : 0));
    const jp = jbP.jp, jalt = jbP.alt;
    if (kind === 'techno') parts.push({ key: 'tb', id: tbP.id, name: tbP.name }, { key: 'tbs', id: tbsP.id, name: tbsP.name });
    if (kind === 'jungle') parts.push({ key: 'jb', id: jbP.id, name: jbP.name }, { key: 'rs', id: rsP.id, name: rsP.name });
    if (kind === 'eastern') parts.push({ key: 'eb', id: ebP.id, name: ebP.name });
    if (kind === 'acid' && !canon) parts.push({ key: 'ac', id: acP.id, name: acP.name });
    parts.push({ key: 'pd', id: pdP.id, name: pdP.name }); if (kind !== 'acid') parts.push({ key: 'ml', id: melP.id, name: melP.name });
    const chop = {}; for (const c of ['K', 'S', 'H', 'G']) { const a = BRK[c].slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(R() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } chop[c] = a.slice(0, c === 'G' ? 2 : 3); }
    const dpat = ebP.v, oud = (() => { const rr = pick([[0, 3, 6, 8, 10, 12, 14], [0, 2, 3, 6, 8, 11, 14], [0, 3, 4, 6, 8, 12, 15], [0, 2, 4, 6, 8, 10, 12, 14]]); let dd = 0; return rr.map((st, i) => { if (i) dd = Math.max(-2, Math.min(5, dd + pick([-1, 1, -1, 1, 2, -2, 0]))); return { st, d: dd }; }); })();
    T = { style: STYLE, kind, funk: false, parts, tbeat: kind === 'techno' ? tbP : null, tbs: tbsP, tbs2: TBASS[(TBASS.indexOf(tbsP) + 2) % TBASS.length], reese: rsP, padSound: pdP, cbars: canon ? 1 : 2, aline, aroot: 33 + md(root - 33, 12), kn, root, mode, modeName, scName, cprog, pv, bn, pcs, bpm, deg, motif, secs, bars, kit, pmask, hacc, bpat, boct, arpMode, gate, jp, jalt, chop, jfill: pick(JFILL), dpat, oud, name: kn + ' ' + (scName || modeName) };
  }
  if (T.kind === 'techno' && /cowbell|maracas|zap/.test(T.kit.perc)) T.kit.perc = /zap/.test(T.kit.perc) ? 'sdbkit-fmperc' : 'x0xproc2-rimshot';
  rememberParts();
  }
function info() { }
function drawSecs() { }
/* ---------- the sound: built once */
let S = null;
/* LITE VOICES: plain oscillators made for each note and gone after it. (Tone's PolySynth keeps every voice's signals running on the audio thread whether it
   sounds or not: measured, 300 of those idle signals cost 40% of a laptop's audio time.) Same calls as a PolySynth: triggerAttackRelease, releaseAll. */
const dsec = (d) => { if (typeof d === 'number') return d; const b = 60 / ((T && T.bpm) || 120), m = /^(\d+)([mn])$/.exec(d); return !m ? (+d || .25) : m[2] === 'm' ? +m[1] * 4 * b : 4 / +m[1] * b; };
function Lite(dest, o) { this.dest = dest; this.o = Object.assign({ type: 'sawtooth', count: 1, spread: 0, attack: .005, decay: .1, sustain: 0, release: .1, peak: .5, max: 14 }, o); this.on = new Set(); }
Lite.prototype.triggerAttackRelease = function (notes, dur, time, vel) {
  const ctx = this.dest.context.rawContext, o = this.o, d = dsec(dur);
  for (const n of [].concat(notes)) { if (this.on.size >= o.max) return;
    const f = Tone.Frequency(n).toFrequency(), g = ctx.createGain(), v = (vel === undefined ? 1 : vel) * o.peak / Math.sqrt(o.count), ta = time + o.attack, tr = Math.max(ta + .01, time + d), te = tr + o.release * 1.5, rec = { g, oscs: [], te };
    g.gain.setValueAtTime(0, time); g.gain.linearRampToValueAtTime(v, ta); if (o.sustain < 1) g.gain.setTargetAtTime(v * o.sustain, ta, Math.max(.005, o.decay / 3)); g.gain.setTargetAtTime(0, tr, Math.max(.005, o.release / 4));
    for (let k = 0; k < o.count; k++) { const os = ctx.createOscillator(); os.type = o.type; os.frequency.value = f; if (o.count > 1) os.detune.value = (k / (o.count - 1) - .5) * o.spread; os.connect(g); os.start(time); os.stop(te); rec.oscs.push(os); }
    Tone.connect(g, this.dest); this.on.add(rec); rec.oscs[0].onended = () => { this.on.delete(rec); try { g.disconnect(); } catch (e) { } }; } };
Lite.prototype.releaseAll = function (time) { const t = time === undefined ? this.dest.context.currentTime : time, o = this.o;
  for (const rec of this.on) if (rec.te > t + o.release) { try { const p = rec.g.gain; if (p.cancelAndHoldAtTime) p.cancelAndHoldAtTime(t); else p.cancelScheduledValues(t); p.setTargetAtTime(0, t, Math.max(.005, o.release / 4)); rec.oscs.forEach((os) => os.stop(t + o.release * 1.5)); rec.te = t + o.release * 1.5; } catch (e) { } } };
/* THE SOUND. Only what the playing style uses is built (every idle chain still costs the audio thread, and the game needs it): a core every style shares,
   then each style's instruments the first time that style plays (need). Noise sources run only while they're heard. */
function build() {
  const master = new Tone.Limiter(-2.5).toDestination(), mG = new Tone.Gain(.7).connect(master), comp = new Tone.Compressor({ threshold: -16, ratio: 3, attack: .012, release: .18 }).connect(mG);
  const rev = new Tone.Reverb({ decay: 2.4, wet: 1 }).connect(comp), revS = new Tone.Gain(.35).connect(rev);
  const dly = new Tone.FeedbackDelay({ delayTime: '8n.', feedback: .38, wet: 1 }).connect(comp), dlyS = new Tone.Gain(.3).connect(dly);
  const duck = new Tone.Gain(1).connect(comp);          /* the sidechain: everything melodic pumps under the kick */
  const drumBus = new Tone.Gain(1).connect(comp), drums = new Tone.Players({}).connect(drumBus);
  // the kick: a tuned synth kick, driven so it has a body small speakers can play, with a sample on top for texture
  const kick = new Tone.MembraneSynth({ pitchDecay: .05, octaves: 6, oscillator: { type: 'sine' }, envelope: { attack: .001, decay: .38, sustain: 0, release: .08 } });
  const kd = new Tone.Distortion(.32); kick.chain(kd, new Tone.Gain(.9), comp);
  const rumbleSrc = new Tone.MembraneSynth({ pitchDecay: .03, octaves: 4, envelope: { attack: .001, decay: .3, sustain: 0, release: .1 } }); const rumLP = new Tone.BiquadFilter(110, 'lowpass'), rumG = new Tone.Gain(0); rumbleSrc.chain(new Tone.Distortion(.4), rumLP, rumG, duck); rumG.connect(revS);
  // pads: two detuned saws per voice, a slowly breathing filter, chorus and lots of space
  const padLP = new Tone.BiquadFilter(1100, 'lowpass'), padLFO = new Tone.LFO(.05, 600, 2400).start(); padLFO.connect(padLP.frequency); const padG = new Tone.Gain(0); padLP.chain(padG, duck); padG.connect(revS);
  const pad = new Lite(padLP, { type: 'sawtooth', count: 2, spread: 24, attack: 1.1, decay: .6, sustain: .85, release: 2, peak: .42, max: 12 });
  // the riser: noise swept up before a drop (started only while it rises)
  const rn = new Tone.Noise('white'), rnBP = new Tone.BiquadFilter(400, 'bandpass'), rnG = new Tone.Gain(0); rnBP.Q.value = 2; rn.chain(rnBP, rnG, comp); rnG.connect(revS);
  S = { drums, drumBus, kick, kd, rumbleSrc, rumG, pad, padG, padLP, padLFO, rn, rnG, rnBP, duck, revS, dlyS, comp, built: {}, ready: () => Promise.all([rev.ready].filter(Boolean)) };
  const MODS = {
    bass() {          // the rolling techno bass (a resonant saw) and the trance gallop (a cleaner square)
      const bass = new Tone.MonoSynth({ oscillator: { type: 'sawtooth' }, filter: { Q: 4, type: 'lowpass', rolloff: -24 }, envelope: { attack: .003, decay: .16, sustain: .2, release: .08 }, filterEnvelope: { attack: .002, decay: .12, sustain: .15, release: .1, baseFrequency: 90, octaves: 3.2 } }); const baG = new Tone.Gain(0); bass.chain(baG, duck);
      const bass2 = new Tone.MonoSynth({ oscillator: { type: 'square' }, filter: { Q: 1, type: 'lowpass' }, envelope: { attack: .004, decay: .1, sustain: .5, release: .05 }, filterEnvelope: { attack: .002, decay: .08, sustain: .3, baseFrequency: 160, octaves: 2 } }); const b2G = new Tone.Gain(0); bass2.chain(b2G, duck);
      Object.assign(S, { bass, baG, bass2, b2G }); },
    arp() {          // short plucks running the chord, through the dotted delay
      const arpLP = new Tone.BiquadFilter(2400, 'lowpass'), arpG = new Tone.Gain(0); arpLP.chain(arpG, duck); const arp = new Lite(arpLP, { type: 'square', attack: .002, decay: .12, sustain: 0, release: .1, peak: .45, max: 8 }); arpG.connect(dlyS); arpG.connect(revS);
      Object.assign(S, { arp, arpLP, arpG }); },
    lead() {          // the hook: a soft supersaw lead, delayed and reverbed
      const ldLP = new Tone.BiquadFilter(3200, 'lowpass'), ldG = new Tone.Gain(0); ldLP.chain(ldG, comp); const lead = new Lite(ldLP, { type: 'sawtooth', count: 2, spread: 22, attack: .02, decay: .3, sustain: .5, release: 1.2, peak: .5, max: 4 }); ldG.connect(dlyS); ldG.connect(revS);
      Object.assign(S, { lead, ldLP, ldG }); },
    funk() {          // a slap-ish synth bass with a little glide, a wah clav, a Rhodes-style electric piano, and a horn section for stabs
      const fbass = new Tone.MonoSynth({ portamento: .012, oscillator: { type: 'square' }, filter: { Q: 3, type: 'lowpass', rolloff: -24 }, envelope: { attack: .002, decay: .2, sustain: .3, release: .06 }, filterEnvelope: { attack: .001, decay: .14, sustain: .25, release: .1, baseFrequency: 110, octaves: 3.6 } }); const fbG = new Tone.Gain(0); fbass.chain(fbG, duck);
      const clav = new Tone.PolySynth(Tone.Synth, { oscillator: { type: 'pulse', width: .3 }, envelope: { attack: .001, decay: .11, sustain: 0, release: .05 } }); clav.maxPolyphony = 4; const wah = new Tone.AutoWah({ baseFrequency: 300, octaves: 4, sensitivity: -28, Q: 3 }), cvG = new Tone.Gain(0); clav.chain(wah, cvG, comp);
      const ep = new Tone.PolySynth(Tone.FMSynth, { harmonicity: 3, modulationIndex: 9, oscillator: { type: 'sine' }, modulation: { type: 'sine' }, envelope: { attack: .003, decay: 1.4, sustain: .15, release: .9 }, modulationEnvelope: { attack: .002, decay: .35, sustain: .05, release: .4 } }); ep.maxPolyphony = 6; const trem = new Tone.Tremolo(4.5, .35).start(), epG = new Tone.Gain(0); ep.chain(trem, epG, duck); epG.connect(revS);
      const hnLP = new Tone.BiquadFilter(2600, 'lowpass'), hnG = new Tone.Gain(0); hnLP.chain(hnG, comp); const horn = new Lite(hnLP, { type: 'sawtooth', count: 2, spread: 18, attack: .012, decay: .22, sustain: .35, release: .12, peak: .5, max: 6 }); hnG.connect(revS);
      Object.assign(S, { fbass, fbG, clav, cvG, ep, epG, horn, hnG }); },
    jungle() {          // the break (three velocity players), a sine sub, a reese (two detuned saws, a slowly moving filter), and the atmosphere loop (85 BPM at double time)
      const brkG = new Tone.Gain(.8).connect(comp);          /* three players at fixed loudness: automating one player's volume per hit breaks when rolls schedule out of order. (Each loads the file itself: a shared buffer is copied before it has loaded.) */
      const brk = [1, .62, .36].map((g) => { const p = new Tone.Player({ url: 'samples/Drums_170BPM.wav', fadeIn: .002, fadeOut: .012 }); p.chain(new Tone.Gain(g), brkG); return p; });
      const sub = new Tone.MonoSynth({ oscillator: { type: 'sine' }, filter: { type: 'lowpass', frequency: 200 }, envelope: { attack: .01, decay: .2, sustain: .9, release: .25 }, filterEnvelope: { baseFrequency: 200, octaves: 0 } }); const subG = new Tone.Gain(0); sub.chain(subG, comp);
      const reese = new Tone.MonoSynth({ portamento: .03, oscillator: { type: 'fatsawtooth', count: 2, spread: 28 }, filter: { Q: 2.5, type: 'lowpass', rolloff: -24 }, envelope: { attack: .02, decay: .3, sustain: .8, release: .2 }, filterEnvelope: { attack: .05, decay: .4, sustain: .6, release: .3, baseFrequency: 160, octaves: 2 } });
      const rsLFO = new Tone.LFO(.18, 220, 900).start(), rsLP = new Tone.BiquadFilter(600, 'lowpass'); rsLFO.connect(rsLP.frequency); const rsG = new Tone.Gain(0); reese.chain(new Tone.Distortion(.25), rsLP, rsG, duck);
      const atm = new Tone.Player({ url: 'samples/Ambience_A_85BPM.wav', loop: true, fadeIn: .5 }), atmG = new Tone.Gain(0); atm.chain(new Tone.BiquadFilter(3500, 'lowpass'), atmG, comp); atmG.connect(revS);
      Object.assign(S, { brk, sub, subG, reese, rsG, atm, atmG }); },
    eastern() {          // a tanpura-like drone, a plucked oud, a breathy ney with vibrato and slides, and a darbuka doum
      const drLP = new Tone.BiquadFilter(700, 'lowpass'), drLFO = new Tone.LFO(.07, 350, 1400).start(); drLFO.connect(drLP.frequency); const droneG = new Tone.Gain(0); drLP.chain(droneG, duck); const drone = new Lite(drLP, { type: 'sawtooth', count: 2, spread: 12, attack: 2.5, decay: 1, sustain: .9, release: 3, peak: .5, max: 6 }); droneG.connect(revS);
      const oud = new Tone.PluckSynth({ attackNoise: 1.4, dampening: 3600, resonance: .965 }), oudG = new Tone.Gain(0); oud.chain(new Tone.BiquadFilter(4200, 'lowpass'), oudG, comp); oudG.connect(revS); oudG.connect(dlyS);
      const ney = new Tone.MonoSynth({ portamento: .07, oscillator: { type: 'triangle' }, filter: { type: 'lowpass', Q: 1 }, envelope: { attack: .09, decay: .2, sustain: .8, release: .5 }, filterEnvelope: { attack: .1, decay: .3, sustain: .7, baseFrequency: 900, octaves: 1.4 } });
      const vib = new Tone.Vibrato(5.2, .12), breath = new Tone.Noise('pink').start(), brBP = new Tone.BiquadFilter(1800, 'bandpass'), brG = new Tone.Gain(0), neyG = new Tone.Gain(0); ney.chain(vib, neyG, comp); breath.chain(brBP, brG, neyG); neyG.connect(revS); neyG.connect(dlyS);
      const doum = new Tone.MembraneSynth({ pitchDecay: .02, octaves: 2.2, envelope: { attack: .001, decay: .32, sustain: 0, release: .1 } }); doum.chain(new Tone.Gain(.55), comp);
      Object.assign(S, { drone, droneG, oud, oudG, ney, neyG, brG, doum }); },
    acid() {          // a sawtooth through a resonant low-pass (swept by the sequencer), a touch of drive, pumped by the kick
      const acid = new Tone.Synth({ oscillator: { type: 'sawtooth' }, envelope: { attack: .003, decay: .12, sustain: 0, release: .05 } }), acF = new Tone.BiquadFilter({ type: 'lowpass', frequency: 800, Q: 12 }), acG = new Tone.Gain(0); acid.chain(acF, new Tone.Distortion(.18), acG, duck); acG.connect(dlyS);
      Object.assign(S, { acid, acF, acG }); } };
  S.mods = MODS;
}
/* the instruments a style needs, built the first time it plays */
const NEEDS = { techno: ['bass', 'arp', 'lead'], funk: ['funk'], jungle: ['jungle', 'lead'], eastern: ['eastern', 'bass'], acid: ['acid'] };
function need(kind) { for (const m of NEEDS[kind] || []) if (!S.built[m]) { S.built[m] = true; S.mods[m](); }
  if (T && T.kit) for (const n of Object.values(T.kit).concat(['x0xproc1-snare', 'x0xproc2-rimshot', 'x0xproc2-maracas'])) if (!S.drums.has(n)) S.drums.add(n, 'samples/' + n + '.wav'); }          /* this track's kit (loaded before it plays) */
/* a level or a filter is only re-scheduled when it actually changes: setting fifteen of them every sixteenth piles automation onto the audio thread
   (over a long session that is the stutter, then the cut-out) */
const pT = (p, v, time, tc) => { if (!p) return; if (p._lv !== undefined && Math.abs(p._lv - v) <= Math.max(1e-3, Math.abs(v) * .004)) return; p._lv = v; p.setTargetAtTime(v, time, tc); };
/* ---------- the sequencer: one step = a sixteenth */
function hit(name, time, vel) { try { if (!S.drums.has(name)) { S.drums.add(name, 'samples/' + name + '.wav'); return; } const p = S.drums.player(name); if (!p.loaded) return; try { p.volume.setValueAtTime(Tone.gainToDb(Math.max(.001, vel)), time); } catch (e) { } p.start(time); } catch (e) { } }          /* (a volume that can't be scheduled never costs the hit itself) */
let step = 0, dose = 0, doseBar = -99, lastSec = -1;
let ME_TR = .5, ME_EN = .8; const TR = () => ME_TR, EN = () => ME_EN;
function secAt(bar) { const b = bar % T.bars; for (let i = T.secs.length - 1; i >= 0; i--) if (b >= T.secs[i].b0) return [T.secs[i], i]; return [T.secs[0], 0]; }
/* every style uses its own instruments; the rest stay silent */
const USE = { acid: ['acG', 'padG', 'rumG'], techno: ['baG', 'b2G', 'rumG', 'padG', 'arpG', 'ldG'], jungle: ['subG', 'rsG', 'atmG', 'padG', 'ldG'], eastern: ['droneG', 'oudG', 'neyG', 'padG', 'baG', 'rumG'], funk: ['fbG', 'cvG', 'epG', 'hnG'] };
const ALLG = [...new Set(Object.values(USE).flat())];
function quiet(time, kind) { const u = USE[kind]; for (const g of ALLG) if (!u.includes(g) && S[g]) pT(S[g].gain, 0, time, .08); }
function pump(time, depth, len) { const g = S.duck.gain; g.cancelScheduledValues(time); g.setValueAtTime(depth, time); g.linearRampToValueAtTime(1, time + len); }
function kickHit(time, v) { S.kick.triggerAttackRelease(midi(T.kroot || 33), '8n', time, v); hit(T.kit.kick, time, (T.kind === 'techno' ? .28 : .45) * v); }
function kickSet(p) { if (S.kcur === p) return; S.kcur = p; try { S.kick.envelope.decay = p.kdec; S.kick.pitchDecay = p.kpd; S.kick.octaves = p.koct; S.kd.distortion = p.drive; } catch (e) { } }
function bassSet(p) { const b = S.bass; if (S.bcur === p) return; S.bcur = p; try { b.filter.Q.value = p.q; b.filterEnvelope.baseFrequency = p.base; b.filterEnvelope.octaves = p.oct; b.envelope.sustain = p.sus; b.envelope.decay = p.dec; } catch (e) { } }
function bassHit(time, bar, st, bn, en, p, mut) { const b = S.bass; bassSet(p); const open = mut === 3 ? .9 : 0, sw = .5 + .5 * Math.sin(2 * Math.PI * (bar + st / 16) / 8); let note = bn, dur = p.dur || '16n';
  if (p.mode === 'acid') { note = bn + T.aline[(bar % (T.aline.length / 8)) * 8 + (st >> 1)]; b.filterEnvelope.octaves = 1.4 + 3.2 * sw * (.6 + .4 * en) + open; }
  else { b.filterEnvelope.octaves = p.oct * (.75 + .25 * en) * (.85 + .15 * sw) + open; if (p.mode === 'drone') { if (st === 0) dur = '2n'; else { note = bn + 12; dur = '32n'; } } }
  b.triggerAttackRelease(midi(note), dur, time, p.mode === 'drone' && st === 0 ? .8 : .72); }
function riserStep(time, P, sec, inSec, st, dosing, bar, big) { const riseK = P.riser ? (inSec * 16 + st) / (sec.len * 16) : dosing && bar - doseBar < 2 ? ((bar - doseBar) * 16 + st) / 32 : 0;
  if (riseK > 0 && !S.rnOn) { S.rnOn = true; S.rn.start(time); } else if (riseK <= 0 && S.rnOn) { S.rnOn = false; S.rn.stop(time + .4); }
  pT(S.rnG.gain,riseK > 0 ? .02 + (big || .16) * riseK : 0, time, riseK > 0 ? .1 : .02); pT(S.rnBP.frequency,300 + 9000 * riseK * riseK, time, .1); }
function padChord(time, P2, bar, len) { if (T.padSound && S.padSnd !== T.padSound.id) { S.padSnd = T.padSound.id; Object.assign(S.pad.o, T.padSound.o); try { S.padLFO.min = T.padSound.lfo[0]; S.padLFO.max = T.padSound.lfo[1]; } catch (e) { } } const cb = T.cbars || 2, ci = Math.floor(bar / cb) % T.pv.length; if (P2.pad && (bar % cb === 0) && T.cst === 0) { S.pad.releaseAll(time); S.pad.triggerAttackRelease(T.pv[ci].map(midi), cb === 1 ? '1m' : (len || '2m'), time, .5 * P2.pad); } return ci; }

/* FUNK: a drummer, a bass player, a clav, keys and horns, all on the same pocket. Kick patterns, ghost notes and comping rhythms come from real funk grooves. */
function funkTick(time, s, bar, st, sec, inSec, lastBar, P, dosing, en) {
  const F = T.fk, sty = T.style, chordD = T.prog[Math.floor(bar / 2) % T.prog.length], ch = T.chord(chordD), root = T.deg(chordD, -2);
  const drumsOn = P.k > 0, full = sec.n === 'DROP' || sec.n === 'GROOVE' || dosing;
  const kick = sty === 'disco' ? st % 4 === 0 : F.kick.includes(st);
  if (drumsOn && kick) { kickHit(time, .9 + .1 * en); pump(time, .3, .16); }
  if (drumsOn && (st === 4 || st === 12)) { hit('x0xproc1-snare', time, .85); if (sty === 'disco') hit(T.kit.clap, time, .55); }
  if (drumsOn && sty !== 'disco' && F.ghost.includes(st)) hit('x0xproc1-snare', time, .14 + .08 * R());          /* ghost notes */
  if (P.h && (sty === 'boogie' ? st % 2 === 0 : true) && R() < .9) hit(T.kit.hat, time, (st % 4 === 0 ? .5 : st % 2 ? .25 : .38) * (.7 + .4 * en));
  if (P.oh && sty === 'disco' && st % 4 === 2) hit(T.kit.oh, time, .5);
  if (drumsOn && lastBar && st >= 12 && sec.n !== 'OUTRO') hit('x0xproc1-snare', time, .3 + .1 * (st - 12));          /* a fill into the next section */
  if (inSec === 0 && st === 0 && sec.n === 'DROP') hit(T.kit.crash, time, .45);
  if (P.ba) { if (sty === 'disco') { if (st % 2 === 0) S.fbass.triggerAttackRelease(midi(root + (st % 4 === 2 ? 12 : 0)), '16n', time, .8); }
    else { const i = F.bass.indexOf(st); if (i >= 0) S.fbass.triggerAttackRelease(midi(root + (F.boctave[i] ? 12 : 0) + (i === F.bass.length - 1 && st > 12 ? 7 : 0)), '16n', time, .85); } }
  pT(S.fbG.gain,P.ba ? (sty === 'disco' ? .18 : .26) : 0, time, .1);          /* (measured: louder than this and the bass buries the kick) */
  if (full && sty !== 'disco' && F.clav.includes(st)) S.clav.triggerAttackRelease(ch.slice(1, 4).map((m) => midi(m + 12)), '32n', time, .6);
  pT(S.cvG.gain,sty !== 'disco' && full ? .16 : 0, time, .1);
  if (P.pad) { const v = ch.map((m) => { let x = m; while (x < 55) x += 12; while (x > 74) x -= 12; return midi(x); });
    if (sty === 'disco' ? st === 0 && bar % 2 === 0 : F.keys.includes(st)) S.ep.triggerAttackRelease(v, sty === 'disco' ? '1m' : '16n', time, sty === 'disco' ? .45 : .55); }
  pT(S.epG.gain,.22 * (P.pad ? 1 : 0), time, .2);
  if (full && bar % 4 === 3 && (st === 10 || st === 14)) S.horn.triggerAttackRelease(ch.slice(0, 3).map((m) => midi(m + 12)), '16n', time, .7);
  if ((sec.n === 'DROP' || dosing) && P.ld) { const pos = (bar % 2) * 16 + st; for (const m of T.motif) { if (m.st !== pos) continue; S.horn.triggerAttackRelease(midi(T.pdeg(m.d + 5, 0)), (m.len * .25 * 60 / T.bpm), time, .6); } }
  pT(S.hnG.gain,full ? .07 : 0, time, .15);
  if (st === 0) quiet(time, 'funk');
  riserStep(time, P, sec, inSec, st, false, bar, .12);
}
/* TECHNO / TRANCE: four to the floor, offbeat open hat, a rolling bassline from the pattern bank, voice-led pads, an arp and a hook that lands on chord tones */
function technoTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing) {
  const ci = padChord(time, P2, bar), v = T.pv[ci], pcs = T.pcs[ci], bn = T.bn[ci];
  const TB = T.tbeat || TBEATS[0], mut = (sec.n === 'GROOVE' || sec.n === 'DROP') ? Math.floor(bar / 16) % 4 : 0, BP = (mut === 1 ? T.tbs2 : T.tbs) || TBASS[0], gap = mut === 2 && bar % 4 === 3;          /* every 16 bars of the groove: 0 as written, 1 the other bass part, 2 hats out + a rim fill each 4th bar, 3 filter opens + ride */
  const kickOn = P.k > 0 && st % 4 === 0 && !(lastBar && P.k < 1 && st > 8), fill = lastBar && (sec.n === 'BUILD' || sec.n === 'RISE') && st >= 12;
  if (kickOn || (fill && st % 2 === 0)) { kickHit(time, kickOn ? .95 + .05 * en : .7); if (inSec === 0 && st === 0 && (sec.n === 'DROP' || sec.n === 'GROOVE')) hit(T.kit.crash, time, .5); if (P.ru * en * TB.rumble > .08) S.rumbleSrc.triggerAttackRelease(midi(bn - 12 > 24 ? bn - 12 : bn), '8n', time, .75); pump(time, .14, .26); }
  pT(S.rumG.gain,P.ru * (1 - tr * .7) * en * .5 * (.4 + .8 * TB.rumble), time, .1);
  { const hv = gap ? 0 : TB.hat[st]; if (P.h && hv > 0 && R() < P.h * (.85 + .15 * en)) hit(T.kit.hat, time, hv * (.55 + .3 * en)); }
  if (P.oh && !gap && TB.oh.includes(st)) hit(T.kit.oh, time, .34 + .1 * en);
  if (P.cl && TB.clap.includes(st) && R() < P.cl) hit(T.kit.clap, time, .6);
  if ((sec.n === 'GROOVE' || sec.n === 'DROP') && (TB.perc.includes(st) || (gap && st >= 13))) hit(T.kit.perc, time, .2 + .12 * en);
  if (P.ri && (TB.ride || mut === 3) && st % 4 === 2 && tr < .8) hit(T.kit.ride, time, .2 * (1 - tr));
  if (P.ba) { const techno = BP.v[st] && R() < 1 - tr * .7, trance = st % 4 !== 0 && R() < tr * 1.1;
    if (techno) bassHit(time, bar, st, bn, en, BP, mut);
    if (trance) S.bass2.triggerAttackRelease(midi(bn + (st % 4 === 2 ? 12 : 0)), '16n', time, .7); }
  pT(S.baG.gain,.42 * (1 - tr * .6), time, .2); pT(S.b2G.gain,.3 * tr, time, .2);
  pT(S.padG.gain,.14 * (.55 + .7 * tr) * P2.pad, time, .3);
  if (P2.arp) { const tones = v.concat(v.slice(0, 3).map((m) => m + 12)), L = tones.length;
    if (T.arpMode === 'gate') { if (T.gate[st]) S.arp.triggerAttackRelease(v.map((m) => midi(m + 12)), '32n', time, .35); }
    else if (R() < .94) { const i = T.arpMode === 'up' ? (st + bar * 3) % L : (() => { const k = (st + bar * 2) % (2 * L - 2); return k < L ? k : 2 * L - 2 - k; })(); S.arp.triggerAttackRelease(midi(tones[i] + 12), '32n', time, .6); } }
  pT(S.arpLP.frequency,650 + 2400 * Math.min(1, (inSec + st / 16) / Math.max(4, sec.len)) * (.4 + .6 * tr), time, .3); pT(S.arpG.gain,.07 * P2.arp * (.3 + .9 * tr), time, .3);
  if (P2.ld) { const pos = (bar % 2) * 16 + st, rep = Math.floor(bar / 2) % 4; for (const m of T.motif) { if (m.st !== pos) continue; let dd = m.d + (rep === 2 ? 2 : 0); if (rep === 3 && m === T.motif[T.motif.length - 1]) dd += pick([-3, 4, 2]); let note = T.deg(dd, 1); if (st % 4 === 0) note = snapTo(note, pcs); S.lead.triggerAttackRelease(midi(note), (m.len * .25 * 60 / T.bpm), time, .55); } }
  pT(S.ldG.gain,.075 * P2.ld * (.35 + .8 * tr), time, .4);
  if (st === 0) quiet(time, 'techno');
  riserStep(time, P, sec, inSec, st, dosing, bar);
}
/* JUNGLE: the break chopped and re-sequenced (two patterns, a switch-up, fills and rolls), the sub on the roots, the reese in the drops, pads and the atmosphere over the top */
function brkHit(time, sl, vel, len) { const rate = T.bpm / BRK.bpm, p = S.brk[vel > .8 ? 0 : vel > .45 ? 1 : 2], SL = p.buffer.duration / BRK.n; try { if (p.playbackRate !== rate) p.playbackRate = rate; p.start(time, sl * SL, (len || 2) * SL / rate); } catch (e) { if (!brkHit.err) { brkHit.err = 1; console.warn('brkHit', e); } } }
function jungleTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing) {
  const ci = padChord(time, P2, bar, '2m'), pcs = T.pcs[ci], bn = T.bn[ci], firstOfChord = bar % 2 === 0 && st === 0;
  if (P.brk && S.brk[0].loaded) { const pat = lastBar && sec.n !== 'OUTRO' && sec.n !== 'BREAK' ? T.jfill : P.alt ? JPAT[T.jalt] : JPAT[T.jp[Math.floor(bar / 4) % 2 === 1 && bar % 4 === 3 ? 1 : 0]], c = pat[st];
    if (c && c !== '.') { if (c === 'r') { const sl = T.chop.S[bar % T.chop.S.length]; brkHit(time, sl, .55, 1); brkHit(time + 30 / T.bpm / 4, sl, .7, 1); }
      else if (!(P.brk < 1 && c === 'K')) { const L = T.chop[c], sl = L[(bar + st) % L.length], fillK = lastBar ? .6 + .4 * st / 15 : 1; brkHit(time, sl, (c === 'G' ? .5 : c === 'H' ? .75 : 1) * fillK, c === 'K' || c === 'S' ? 3 : 2);
        if (c === 'K' && P.brk >= 1) { S.kick.triggerAttackRelease(midi(T.kroot || 33), '16n', time, .55); pump(time, .45, .16); } } }
    if (P.sh && st % 2 === 1 && R() < .8) hit('x0xproc2-maracas', time, .12 + .1 * en); }
  if (inSec === 0 && st === 0 && (sec.n === 'DROP' || sec.n === 'SWITCH')) hit(T.kit.crash, time, .5);
  if (firstOfChord && P.sub) S.sub.triggerAttackRelease(midi(bn), '2m', time, .9);
  pT(S.subG.gain,.26 * P.sub, time, .1);
  if (P.rs) { const RZ = T.reese || REESES[0], k = RZ.riff.indexOf(st); if (firstOfChord) S.reese.triggerAttackRelease(midi(bn + 12), RZ.riff.length ? '1m' : '2m', time, .8); else if (bar % 2 === 1 && k > 0) S.reese.triggerAttackRelease(midi(bn + 12 + RZ.off[k]), k === RZ.riff.length - 1 ? '4n' : '8n', time, .7); }
  pT(S.rsG.gain,.26 * P.rs * (.6 + .4 * en), time, .15);
  pT(S.padG.gain,.13 * P2.pad, time, .4);
  try { if (S.atm.loaded && S.atm.state !== 'started') { S.atm.playbackRate = T.bpm / 170; S.atm.start(time); } } catch (e) { }
  pT(S.atmG.gain,.22 * P.atm, time, .6);
  if (P2.ld) { const pos = (bar % 2) * 16 + st; for (const m of T.motif) { if (m.st !== pos) continue; let note = T.deg(m.d, 1); if (st % 4 === 0) note = snapTo(note, pcs); S.lead.triggerAttackRelease(midi(note), (m.len * .25 * 60 / T.bpm) * 1.5, time, .5); } }
  pT(S.ldG.gain,.06 * P2.ld, time, .4);
  if (st === 0) quiet(time, 'jungle');
  riserStep(time, P, sec, inSec, st, dosing, bar);
}
/* EASTERN: four to the floor under a darbuka rhythm (maqsum, baladi, ayoub, saidi), a drone on the tonic and fifth, an oud riff in the scale, the ney's phrases
   with grace notes and slides, and modal chords that never stray far from the drone */
function easternTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing) {
  const ci = padChord(time, Object.assign({}, P2, { pad: P2.pad * .7 }), bar, '2m'), pcs = T.pcs[ci], bn = T.bn[ci];
  if (P.k > 0 && st % 4 === 0 && !(lastBar && P.k < 1 && st > 8)) { kickHit(time, 1); pump(time, .3, .2); if (inSec === 0 && st === 0 && sec.n === 'DROP') hit(T.kit.crash, time, .4); }
  if (P.oh && st % 4 === 2) hit(T.kit.oh, time, .35);
  const c = T.dpat[st]; if (P.h && c && c !== '.') { if (c === 'D') S.doum.triggerAttackRelease(midi(T.root - 12 + 7 > 40 ? T.root - 12 : T.root), '16n', time, .8); else hit('x0xproc2-rimshot', time, c === 'T' ? .55 : .22); }
  if (P.ba && st % 4 !== 0 && (sec.n === 'DROP' || sec.n === 'GROOVE' || sec.n === 'BUILD')) { bassSet(BDEF); S.bass.triggerAttackRelease(midi(bn), '16n', time, .6); }
  pT(S.baG.gain,.24 * P.ba, time, .2); pT(S.rumG.gain,0, time, .1);
  if (bar % 4 === 0 && st === 0) { S.drone.releaseAll(time); S.drone.triggerAttackRelease([midi(T.root - 12), midi(T.root - 5)], '4m', time, .5); }
  pT(S.droneG.gain,.12 * (.6 + .4 * tr), time, .5);
  if (P2.arp) for (const o of T.oud) if (o.st === st) { let note = T.deg(o.d, 0); if (st % 4 === 0) note = snapTo(note, pcs); S.oud.triggerAttack(midi(note + 12), time); }
  pT(S.oudG.gain,.45 * P2.arp, time, .3);
  if (P2.ld) { const pos = (bar % 2) * 16 + st, rep = Math.floor(bar / 2) % 4; for (const m of T.motif) { if (m.st !== pos) continue; const note = T.deg(m.d + (rep === 2 ? 1 : 0), 1), dur = m.len * .25 * 60 / T.bpm * 1.4;
      if (m.len >= 3 && R() < .5) { S.ney.triggerAttack(midi(T.deg(m.d + 1, 1)), time, .6); S.ney.setNote(midi(note), time + 60 / T.bpm / 8); S.ney.triggerRelease(time + dur); }          /* a grace note from above, sliding in */
      else S.ney.triggerAttackRelease(midi(note), dur, time, .6);
      S.brG.gain.setValueAtTime(.02, time); S.brG.gain.linearRampToValueAtTime(0, time + .25); } }
  pT(S.neyG.gain,.2 * P2.ld, time, .4);
  pT(S.padG.gain,.08 * P2.pad, time, .4);
  if (st === 0) quiet(time, 'eastern');
  riserStep(time, P, sec, inSec, st, dosing, bar, .1);
}
/* ACID: the 303 line in eighths with its filter swept by a slow sine (200 Hz to 3 kHz over four bars); the build adds the kick, the hats, then the snare accent */
function acidTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing) {
  padChord(time, P2, bar);
  if (st % 2 === 0) { const ph = (bar + st / 16) / 4, f = 200 + 2800 * (.5 + .5 * Math.sin(2 * Math.PI * ph)); S.acF.frequency.setValueAtTime(f, time); S.acid.triggerAttackRelease(midi(T.aroot + T.aline[(bar % (T.aline.length / 8)) * 8 + st / 2]), '16n', time, .85); }
  pT(S.acG.gain,1.35, time, .1);          /* (measured: the line alone has to carry the opening) */
  if (P.k && st % 4 === 0) { kickHit(time, .95); pump(time, .45, .18); if (inSec === 0 && st === 0 && (sec.n === 'FULL' || sec.n === 'DROP')) hit(T.kit.crash, time, .45); }
  if (P.h && st % 4 === 2) hit(T.kit.hat, time, .7 * P.h);
  if (P.h && st % 2 === 1 && R() < .45) hit(T.kit.hat, time, .22 * P.h);
  if (P.oh && st % 4 === 2) hit(T.kit.oh, time, .35);
  if (P.sn) { if (bar % 2 === 1 && st === 14) hit('x0xproc1-snare', time, .85); if (bar % 2 === 1 && st === 15) hit('x0xproc1-snare', time, .32); if (bar % 2 === 0 && st === 0 && inSec > 0) hit(T.kit.clap, time, .55); }          /* the accent, and the catch */
  if (P.cl && (st === 4 || st === 12)) hit(T.kit.clap, time, .7);
  if (P.ru && st % 4 === 0) S.rumbleSrc.triggerAttackRelease(midi(T.aroot), '8n', time, .6);
  pT(S.rumG.gain,.22 * (P.ru || 0), time, .1);
  pT(S.padG.gain,.2 * (P2.pad || 0), time, .5);
  if (st === 0) quiet(time, 'acid');
  riserStep(time, P, sec, inSec, st, dosing, bar);
}
function tick(time) {
  const s = step++, bar = Math.floor(s / 16), st = s % 16, [sec, si] = secAt(bar), P = (T.kind === 'jungle' ? JSECT : T.kind === 'acid' ? ASECT : SECT)[sec.n] || SECT.GROOVE, tr = TR(), en = EN(), inSec = (bar % T.bars) - sec.b0, lastBar = inSec === sec.len - 1;
  const dosing = bar - doseBar < 8, P2 = dosing ? Object.assign({}, P, { ld: 1, arp: 1, pad: 1 }) : P;          /* a dose: the hook and the arp come in whatever the section */
  need(T.kind); T.cst = st; if (!T.kroot) T.kroot = 31 + md(T.root - 31, 12); if (S.kick) kickSet(T.kind === 'techno' && T.tbeat ? T.tbeat : KDEF);          /* the kick tuned to the key (G1 to F#2) */
  if (si !== lastSec && st === 0) { lastSec = si; Tone.Draw.schedule(() => { document.querySelectorAll('#secs span').forEach((e) => e.classList.toggle('on', +e.dataset.i === si)); }, time); }
  if (T.funk) funkTick(time, s, bar, st, sec, inSec, lastBar, P, dosing, en);
  else if (T.kind === 'jungle') jungleTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing);
  else if (T.kind === 'acid') acidTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing);
  else if (T.kind === 'eastern') easternTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing);
  else technoTick(time, bar, st, sec, inSec, lastBar, P, P2, tr, en, dosing);
  if (st === 0) Tone.Draw.schedule(() => info(sec.n + ' · bar ' + (inSec + 1) + '/' + sec.len + (dosing ? ' · DOSE' : '')), time);
}
const swingOf = () => T.funk ? (T.style === 'break' ? .18 : .12) : (T.kind === 'jungle' || T.kind === 'techno' || T.kind === 'acid') ? 0 : .06;
/* OFFLINE RENDER: plays a track into a buffer faster than real time (for measuring, and for the loop library). o: { style, seed, secs, from: section name } */
async function renderOffline(o) { const keep = [S, T, step, lastSec, STYLE, LV, SEED, doseBar];
  try { const buf = await Tone.Offline(async (ctx) => { S = null; build(); STYLE = o.style || 'techno'; LV = o.level || null; SEED = o.seed || 12345; step = 0; lastSec = -1; doseBar = -99; makeTrack(); need(T.kind); await Tone.loaded(); await S.ready();
      const g = T.secs.find((x) => x.n === (o.from || 'DROP')) || T.secs.find((x) => x.n === 'GROOVE'); if (g) step = g.b0 * 16;
      const tp = ctx.transport; tp.bpm.value = T.bpm; tp.swing = swingOf(); tp.swingSubdivision = '16n'; tp.scheduleRepeat(tick, '16n'); tp.start(0); }, o.secs || 12);
    return { buf, bpm: T.bpm, name: T.name, chords: chordNames(), style: T.style }; }
  finally { [S, T, step, lastSec, STYLE, LV, SEED, doseBar] = keep; } }
function chordNames() { const N = (['E', 'B'].includes(T.kn) || (T.mode === DORIAN && ['A', 'E', 'B'].includes(T.kn))) ? ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'] : ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];
  if (!T.funk) return T.cprog.c.map(([s, q]) => N[md(T.root + s, 12)] + CLAB[q]).join(' – ');
  return T.prog.map((d) => { const c = T.chord(d), third = (c[1] - c[0] + 12) % 12, fifth = (c[2] - c[0] + 12) % 12; const sev = (c[3] - c[0] + 12) % 12 === 10 ? '7' : (c[3] - c[0] + 12) % 12 === 11 ? 'maj7' : ''; return N[c[0] % 12] + (third === 3 ? (fifth === 6 ? 'dim' : 'm') : '') + sev; }).join(' – '); }
/* THE TUNER (lab only): one row per layer of the playing track */
let tnSig = '';
function drawTuner(force) { if (!T || !T.parts) return; const sig = T.parts.map((p) => p.key + p.id).join('|') + JSON.stringify(RATE); if (!force && sig === tnSig) return; tnSig = sig; const w = document.getElementById('tnRows'); w.textContent = '';
  for (const p of T.parts) { const row = document.createElement('div'); row.className = 'tn'; const sc = RATE[p.key + '.' + p.id] || 0;
    const l = document.createElement('span'); l.className = 'l'; l.textContent = LAYER[p.key]; const n = document.createElement('span'); n.className = 'n'; n.textContent = p.name + (sc > 0 ? '  \u2605' + sc : ''); n.title = p.name;
    const mk = (t, title, fn, on) => { const b = document.createElement('button'); b.textContent = t; b.title = title; if (on) b.className = 'on'; b.onclick = () => { fn(); drawTuner(true); info(); }; return b; };
    row.append(l, n, mk('\uD83D\uDC4D', 'More of this', () => ratePart(p.key, 1), sc > 0), mk('\uD83D\uDC4E', 'Never again (and swap it now)', () => ratePart(p.key, -1)), mk('\u27F3', 'Swap: try another', () => swapPart(p.key))); w.appendChild(row); } }
{ const tr0 = document.getElementById('tnReset'); if (tr0) tr0.onclick = () => { RATE = {}; RECENT = []; wrJ('dl_parts', RATE); wrJ('dl_recent', RECENT); drawTuner(true); }; }

/* ---------- THE GAME'S HANDLE (window.ME). The level's preset picks the style, tempo and blend; your saved tracks for that level (and the curated ones below)
   are played first, so a level opens on a track someone chose; otherwise a fresh seed. The game moves the mood: a dose (riser, hook), RUSH and fights (harder),
   the afterglow (softer, floatier). */
const CURATED = { };          /* level -> seeds picked by ear in the lab (filled in as tracks are chosen) */
let loopId = null;
window.ME = {
  on: false, base: null, key() { return T ? { root: T.root, mode: T.mode || MINOR } : null; },          /* (the track's key: the game's engine hum plays in it) */
  /* PRELOAD: called while the level loads (before any tap), so the instruments are built, the samples decoded and the reverb made before the first frame:
     the tap then only starts the clock, and the music starts with the level */
  preload(o) { if (this.pre) return this.pre; o = o || {}; this.opts = o;
    try { if (!S && Tone.getContext().latencyHint !== 'playback') Tone.setContext(new Tone.Context({ latencyHint: 'playback', lookAhead: o.lookAhead || .2 })); else if (o.lookAhead) Tone.getContext().lookAhead = o.lookAhead; } catch (e) { }          /* the game asks for more look-ahead: its frames can stall while it builds shaders, and the notes must already be planned */
    if (!S) build();
    LV = o.level && LVLP[o.level] ? o.level : null; STYLE = o.style || (LV ? LVLP[LV][1] : 'techno'); if (LV) { ME_TR = LVLP[LV][3] / 100; ME_EN = LVLP[LV][4] / 100; } if (o.tr !== undefined) ME_TR = o.tr; if (o.en !== undefined) ME_EN = o.en; if (o.trAdd) ME_TR = Math.max(0, Math.min(1, ME_TR + o.trAdd)); if (o.enMul) ME_EN = Math.max(.15, Math.min(1, ME_EN * o.enMul));          /* the Frequency's faders override the level's blend */
    const mine = rdT0().filter((t) => t.level === LV && t.style === STYLE).map((t) => t.seed), pool = (CURATED[LV] || []).concat(mine);
    SEED = o.seed || (pool.length ? pool[Math.floor(Math.random() * pool.length)] : Math.floor(Math.random() * 1e9)); step = 0; lastSec = -1; makeTrack(); need(T.kind);
    if (o.strong && T.kind !== 'acid') { const g = T.secs.find((x) => x.n === 'GROOVE' || x.n === 'DROP'); if (g) step = g.b0 * 16; }          /* a strong start: straight into the full groove */
    this.pre = (async () => { await Tone.loaded(); await S.ready(); })(); return this.pre; },
  async start(o) { if (this.on || this.starting) return; this.starting = true;
    try { await Tone.start(); } catch (e) { }          /* first, inside the tap: unlock the audio */
    await this.preload(o);
    Tone.Transport.bpm.value = T.bpm; Tone.Transport.swing = swingOf(); Tone.Transport.swingSubdivision = '16n';
    if (loopId === null) loopId = Tone.Transport.scheduleRepeat(tick, '16n'); this.on = true; this.starting = false; this.base = { tr: ME_TR, en: ME_EN };
    if (this.paused) { try { Tone.getContext().rawContext.suspend(); } catch (e) { } } else Tone.Transport.start('+0.05');          /* paused while it was loading: it waits for the resume */
    if (!this.wd) this.wd = setInterval(() => { const c = Tone.getContext(); if (ME.on && !ME.paused && c.state !== 'running') c.resume(); }, 1000); },
  /* pause: the clock stops and the whole audio context is suspended, so held pads, tails and loops stop at once (and resume where they were) */
  pause(b) { this.paused = !!b; if (!this.on) return; try { if (b) { Tone.Transport.pause(); Tone.getContext().rawContext.suspend(); } else { Tone.getContext().resume(); Tone.Transport.start(); } } catch (e) { } },
  dose() { if (this.on) doseBar = Math.floor(step / 16) + 1; },
  set(tr, en) { if (tr !== undefined) ME_TR = tr; if (en !== undefined) ME_EN = en; this.base = { tr: ME_TR, en: ME_EN }; },
  restyle(style, level) { if (!this.on) return; STYLE = style || STYLE; LV = level === undefined ? LV : level; SEED = Math.floor(Math.random() * 1e9); step = 0; lastSec = -1; makeTrack(); Tone.Transport.bpm.rampTo(T.bpm, .5); Tone.Transport.swing = swingOf(); try { if (S.atm) S.atm.stop(); } catch (e) { } need(T.kind); },
  stop() { try { Tone.Transport.stop(); S.pad.releaseAll(); if (S.drone) S.drone.releaseAll(); if (S.atm) S.atm.stop(); if (S.brk) S.brk.forEach((p) => p.stop()); if (S.rnOn) { S.rn.stop(); S.rnOn = false; } } catch (e) { } this.on = false; },
  chords() { return T ? chordNames() : ''; },
  next() { if (!this.on) return; SEED = Math.floor(Math.random() * 1e9); step = 0; lastSec = -1; makeTrack(); Tone.Transport.bpm.rampTo(T.bpm, .5); Tone.Transport.swing = swingOf(); try { if (S.atm) S.atm.stop(); } catch (e) { } need(T.kind); },
  mood(m) { const b = this.base || { tr: ME_TR, en: ME_EN }; if (m === 'glow') { ME_TR = Math.min(1, b.tr + .35); ME_EN = b.en * .45; } else if (m === 'rush' || m === 'fight') { ME_TR = b.tr * .7; ME_EN = 1; } else { ME_TR = b.tr; ME_EN = b.en; } },
  beatPos() { return this.on ? Tone.Transport.ticks / Tone.Transport.PPQ : 0; },
  volume(db) { try { Tone.getDestination().volume.value = db; } catch (e) { } },          /* (getDestination: Tone.Destination is the first context's, stale after setContext) */
  render: (o) => renderOffline(o),
  get track() { return T; }, get seed() { return SEED; },
};

})();
