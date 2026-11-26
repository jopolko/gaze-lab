// CANON CHECK: compares canon.js with the game and lists what needs writing or fixing.
//   node tools/canon_check.mjs        (run from web/babylon; exit code 1 when something needs attention)
// It finds: worlds, strains, quests and raid craft in the game that have no lock-screen lines yet ("needs jokes"),
// names in the game that no longer match the canon ("drift"), unknown {tokens}, voices not on the canon's list,
// and canon people/factions the glossary never mentions.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const rd = (f) => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
const ctx = {}; vm.createContext(ctx); vm.runInContext(rd('canon.js'), ctx); const C = ctx.CANON;
const html = rd('index.html'), gl = (() => { try { return rd('glossary.html'); } catch { return ''; } })();
const out = { needs: [], drift: [], bad: [], warn: [] };
const title = (s) => s.toLowerCase().replace(/\b\w/g, (m) => m.toUpperCase()).replace(/\bOf\b/g, 'of').replace(/\bThe\b(?!^)/g, (m, i) => (i ? 'the' : m));

// worlds (JNAME)
const jn = html.match(/JNAME = \{([^\n]*?)\};/); const worlds = {};
if (jn) for (const m of jn[1].matchAll(/(\w+): \['([^']+)'/g)) worlds[m[1]] = m[2];
for (const [k, nm] of Object.entries(worlds)) {
  if (!C.worlds[k]) out.drift.push(`world "${k}" (${nm}) is in the game but not in canon.worlds`);
  else if (C.worlds[k].toUpperCase() !== nm.toUpperCase()) out.drift.push(`world "${k}": game says "${nm}", canon says "${C.worlds[k]}"`);
  if (!C.react['world:' + k]) out.needs.push(`world "${k}" (${nm}): add react['world:${k}'] lines`); }
for (const k of Object.keys(C.worlds)) if (!(k in worlds)) out.warn.push(`canon world "${k}" is not in the game's JNAME`);

// strains (COMP)
const comp = {}; for (const m of html.matchAll(/^\s+(\w+):\s+\{ name: '([A-Z]+)'/gm)) comp[m[1]] = m[2];
for (const [k, nm] of Object.entries(comp)) {
  if (!C.strains[k]) out.drift.push(`strain "${k}" (${nm}) is in the game but not in canon.strains`);
  else if (C.strains[k].toUpperCase() !== nm) out.drift.push(`strain "${k}": game says "${nm}", canon says "${C.strains[k]}"`);
  if (!C.react['strain:' + k]) out.needs.push(`strain "${k}": add react['strain:${k}'] lines`); }
// strain keys used anywhere in code as string literals for doses (catches typos like 'ember')
for (const f of ['index.html', 'splash.html']) { const src = rd(f); for (const m of src.matchAll(/doseTake\('(\w+)'/g)) if (!comp[m[1]]) out.bad.push(`${f}: doseTake('${m[1]}') is not a real strain`);
  const st = src.match(/const STR = \[([^\]]*)\]/); if (st) for (const m of st[1].matchAll(/'(\w+)'/g)) if (!comp[m[1]]) out.bad.push(`${f}: preview strain '${m[1]}' is not a real strain`); }

// quests (QI)
const qi = html.match(/QI = \[(.*?)\];/); const quests = qi ? [...qi[1].matchAll(/\['(\w+)', [^,]+, '([^']+)'\]/g)].map((m) => [m[1], m[2]]) : [];
for (const [k, what] of quests) { if (!C.quests[k]) out.drift.push(`quest "${k}" (${what}) is in the game but not in canon.quests`); if (!C.react['quest:' + k]) out.needs.push(`quest "${k}" (${what}): add react['quest:${k}'] lines`); }
for (const k of Object.keys(C.quests)) if (!quests.find((q) => q[0] === k)) out.warn.push(`canon quest "${k}" is no longer in the game's QI`);

// raid craft (WCRAFT)
const wc = html.match(/WCRAFT = \{([^}]*)\}/); const crafts = wc ? [...wc[1].matchAll(/(\w+): '(\w+)'/g)].map((m) => [m[1], m[2]]) : [];
for (const [w, k] of crafts) { if (!C.crafts[k]) out.drift.push(`craft "${k}" (${w}) is in the game but not in canon.crafts`); if (!C.react['craft:' + k]) out.needs.push(`craft "${k}" (${w}): add react['craft:${k}'] lines`); }

// tokens and voices
const TOK = new Set(['world', 'where', 'pct', 'odds', 'bounty', 'strain', 'hits', 'f', 'sights', 'last', 'next']);
for (const [k, e] of Object.entries(C.react)) for (const kind of ['W', 'N']) for (const q of e[kind] || []) {
  if (!Array.isArray(q) || q.length !== 3) { out.bad.push(`react['${k}'].${kind}: each line needs [voice/title, title/big, text]`); continue; }
  for (const x of q) for (const m of String(x).matchAll(/\{(\w+)\}/g)) if (!TOK.has(m[1])) out.bad.push(`react['${k}']: unknown token {${m[1]}}`);
  if (kind === 'N' && !C.voices.includes(q[0])) out.bad.push(`react['${k}']: voice "${q[0]}" is not in canon.voices`);
 }

// the glossary should know the cast
for (const g of [C.people, C.factions]) for (const v of Object.values(g)) if (gl && !gl.includes(v.name.replace(/^The /, ''))) out.warn.push(`glossary.html never mentions ${v.name}`);

const sec = (t, a) => { if (a.length) { console.log('\n' + t + ' (' + a.length + ')'); for (const x of a) console.log('  - ' + x); } };
sec('NEEDS JOKES', out.needs); sec('NAME DRIFT', out.drift); sec('BROKEN', out.bad); sec('WORTH A LOOK', out.warn);
const n = out.needs.length + out.drift.length + out.bad.length;
console.log(n ? `\n${n} thing(s) to fix.` : '\nCanon and game agree. Nothing to write.'); process.exit(n ? 1 : 0);
