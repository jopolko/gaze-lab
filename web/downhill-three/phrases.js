// PHRASES: short call-outs built from interchangeable parts, never the same line twice in a row.
// NOT wired into the game yet (2026-11-22: no new text on screen). Use:  const P = createPhrases(seed);  P.say('jump', { biome: 'candy', trip: 0.4 }) -> 'SKY ROLL'
// ctx: biome (alpine candy desert tunnel matrix synthwave psychedelic), trip 0..1 (how deep into the whole trip).
// Rules: no line within the last 12 said, no shared first word with the last 3, 1 in 14 lines is a rare one, and later in the trip the wording gets stranger.
const FLAV = {
  alpine: ['SNOW', 'PEAK', 'ICE', 'PINE', 'SUMMIT', 'FROST'], candy: ['SUGAR', 'SYRUP', 'JELLY', 'GLAZE', 'FIZZ', 'MINT'], desert: ['DUNE', 'HEAT', 'MIRAGE', 'DUST', 'SAND', 'SUN'],
  tunnel: ['VOID', 'ECHO', 'BEAM', 'PULSE', 'RING', 'DEPTH'], matrix: ['CODE', 'GLITCH', 'PIXEL', 'SIGNAL', 'GRID', 'BIT'], synthwave: ['NEON', 'CHROME', 'LASER', 'VHS', 'CHROMA', 'TURBO'],
  psychedelic: ['COLOUR', 'FRACTAL', 'SPIRAL', 'BLOOM', 'PRISM', 'WAVE'],
};
const DEEP = ['IMPOSSIBLE', 'LIQUID', 'INFINITE', 'MELTING', 'TOO BRIGHT', 'UNFOLDING', 'WEIGHTLESS'];
// each pool: parts [A, B, C] (one word from each list, joined), plus fixed lines and rare lines. {F} = a word of the biome's flavour, {D} = a deep-trip word.
const POOLS = {
  jump: { parts: [['SKY', 'AIR', 'LIFT', 'HANG', 'FLOAT', 'LAUNCH', 'SOAR', 'POP'], ['ROLL', 'TIME', 'KICK', 'DROP', 'DRIFT', 'FLIP', 'GLIDE', 'RUSH'], ['', '', '{F}', 'UP', '!']], fixed: ['AND UP', 'OFF THE LIP', 'NO FLOOR', 'GONE', 'HIGHER', 'CLEAN LAUNCH'], rare: ['THE GROUND FORGOT YOU', 'NOBODY HOLDS YOU DOWN'] },
  land: { parts: [['SOFT', 'CLEAN', 'STUCK', 'SMOOTH', 'SWEET', 'TIGHT'], ['LANDING', 'TOUCH', 'DOWN', 'CATCH', 'CONTACT'], ['', '', '!']], fixed: ['BACK ON', 'GROUND AGAIN', 'GRIP', 'AND ROLLING'], rare: ['THE HILL CAUGHT YOU'] },
  bigair: { parts: [['HUGE', 'MASSIVE', 'EPIC', 'LONG', 'WILD'], ['AIR', 'HANG', 'FLIGHT', 'SKY'], ['', '{F}', '!!']], fixed: ['SEE YOU NEXT WEEK', 'THAT WAS A BIRD', 'TOO FAR TO FALL'], rare: ['YOU LEFT THE MAP'] },
  chain: { parts: [['KEEP IT', 'ONE MORE', 'STAY', 'DO NOT STOP', 'RIDE IT', 'HOLD IT', 'STACK IT'], ['GOING', 'ROLLING', 'LIT', 'HOT', 'TIGHT', 'FLOWING'], ['', '', '!']], fixed: ['LINKED', 'NO GAPS', 'THE CHAIN SINGS', 'ONE LONG LINE'], rare: ['THE LINE LOOPS BACK'] },
  mol: { parts: [['YES', 'THERE IT IS', 'GOT IT', 'CAUGHT', 'TAKEN', 'IN'], ['{F}', 'LIGHT', 'FEELING', 'SHIFT', 'OPENING', 'COLOUR'], ['', '!', 'NOW']], fixed: ['SOMETHING MOVED', 'THE WORLD TILTS', 'YOU CAN SEE IT'], rare: ['IT WAS ALWAYS THERE'] },
  setpiece: { parts: [['HERE IT COMES', 'BRACE', 'LOOK UP', 'EYES OPEN', 'ALL IN', 'NO BRAKES'], ['{F}', '', '{F} AHEAD'], ['', '!']], fixed: ['THE BIG ONE', 'FULL SEND', 'THIS IS THE PART', 'EVERYTHING AT ONCE'], rare: ['THE HILL WANTS TO SHOW YOU'] },
  breather: { parts: [['EASY', 'BREATHE', 'SOFT', 'QUIET', 'SLOW HANDS', 'LET GO'], ['{F}', 'SKY', 'AIR', 'LIGHT'], ['', '', '...']], fixed: ['NOTHING TO DO', 'JUST FALL', 'ALL OF IT IS YOURS'], rare: ['THE HILL HOLDS ITS BREATH'] },
  dive: { parts: [['DROP', 'DIVE', 'PLUNGE', 'FALL', 'DESCEND'], ['NOW', 'HARD', 'FAST', 'THROUGH', 'DEEP'], ['', '!', '{F}']], fixed: ['THE FLOOR IS GONE', 'LEAN IN', 'FASTER THAN FEAR'], rare: ['DOWN IS A DIRECTION OF LIGHT'] },
  runout: { parts: [['COAST', 'EASE', 'GLIDE', 'RELEASE', 'FADE'], ['OUT', 'HOME', 'OFF', 'DOWN'], ['', '...']], fixed: ['THE SLOPE LETS GO', 'LOOK BACK', 'WHAT A RIDE'], rare: ['YOU ARE STILL MOVING'] },
  stumble: { parts: [['OOPS', 'WHOA', 'SCUFF', 'WOBBLE', 'BUMP', 'SLIP'], ['', 'EASY', 'KEEP GOING', 'AGAIN'], ['', '!']], fixed: ['IT HAPPENS', 'SHAKE IT OFF', 'THE HILL WINS ONE'], rare: ['EVEN THE SNOW LAUGHED'] },
  near: { parts: [['CLOSE', 'TIGHT', 'THIN', 'NARROW', 'SHAVED'], ['ONE', 'SHAVE', 'CALL', 'LINE', 'GAP'], ['', '!']], fixed: ['BARELY', 'NEEDLE THREADED', 'HAIR WIDE'], rare: ['YOU DID NOT TOUCH IT'] },
  biome: { parts: [['WELCOME TO', 'ENTERING', 'NOW', 'DOWN INTO', 'THROUGH TO'], ['{F}', '{F} LAND', '{F} WORLD'], ['']], fixed: [], rare: [] },
};
function rng(seed) { let a = seed >>> 0 || 1; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const head = (s) => (s.split(' ')[0] || '').replace(/[^A-Z]/g, '');
export function poolSize(ev) { const p = POOLS[ev]; return p ? p.parts.reduce((a, l) => a * l.length, 1) + p.fixed.length + p.rare.length : 0; }
export function createPhrases(seed = 1) {
  const R = rng(seed), recent = [], lastHeads = [];
  const pick = (a) => a[Math.floor(R() * a.length)];
  const fill = (s, ctx) => s.replace(/\{F\}/g, () => pick(FLAV[ctx.biome] || FLAV.psychedelic)).replace(/\{D\}/g, () => pick(DEEP)).replace(/\s+/g, ' ').replace(/ !/g, '!').replace(/ \.\.\./g, '...').trim();
  const make = (ev, ctx) => { const p = POOLS[ev]; if (!p) return null;
    if (p.rare.length && R() < 1 / 14) return pick(p.rare);
    if (ctx.trip > .6 && R() < .22) return fill(pick(p.parts[0]) + ' {D}', ctx);
    if (p.fixed.length && R() < .3) return pick(p.fixed);
    return fill(p.parts.map((l) => pick(l)).join(' '), ctx); };
  return {
    say(ev, ctx = {}) { ctx = Object.assign({ biome: 'psychedelic', trip: 0 }, ctx);
      let line = null; for (let tries = 0; tries < 40; tries++) { const c = make(ev, ctx); if (!c) return null; if (recent.includes(c)) continue; if (lastHeads.includes(head(c)) && tries < 30) continue; line = c; break; }
      if (!line) line = make(ev, ctx); recent.push(line); if (recent.length > 12) recent.shift(); lastHeads.push(head(line)); if (lastHeads.length > 3) lastHeads.shift(); return line; },
    events: Object.keys(POOLS),
  };
}
