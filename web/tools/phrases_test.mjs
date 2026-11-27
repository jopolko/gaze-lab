// node tools/phrases_test.mjs : says every event 300 times across all biomes and reports repeats (back-to-back and within the last 12).
import { createPhrases, poolSize } from '../downhill-three/phrases.js';
const P = createPhrases(5), biomes = ['alpine', 'candy', 'desert', 'tunnel', 'matrix', 'synthwave', 'psychedelic'];
let bad = 0;
for (const ev of P.events) {
  const out = []; for (let i = 0; i < 300; i++) out.push(P.say(ev, { biome: biomes[i % 7], trip: i / 300 }));
  let back = 0, near = 0; for (let i = 1; i < out.length; i++) if (out[i] === out[i - 1]) back++; for (let i = 12; i < out.length; i++) if (out.slice(i - 12, i).includes(out[i])) near++;
  if (back || near) bad++;
  console.log(ev.padEnd(9), 'combos', String(poolSize(ev)).padStart(4), '| unique in 300:', String(new Set(out).size).padStart(3), '| back-to-back', back, '| within 12', near, '|', out.slice(0, 4).join(' / '));
}
console.log(bad ? 'REPEATS FOUND' : 'NO REPEATS WITHIN 12');
