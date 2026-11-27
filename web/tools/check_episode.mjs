// node check_episode.mjs <episode.json> [...]  : runs the same checker the game uses. Exit 1 if any file has problems.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, '..', 'downhill-three', 'episode_check.js'), 'utf8');
const { checkEpisode } = await import('data:text/javascript;base64,' + Buffer.from(src).toString('base64'));
let fail = 0;
for (const f of process.argv.slice(2)) {
  let ep; try { ep = JSON.parse(readFileSync(f, 'utf8')); } catch (e) { console.log('FAIL ' + f + ': not valid JSON'); fail++; continue; }
  const bad = checkEpisode(ep);
  if (bad.length) { fail++; console.log('FAIL ' + f); bad.forEach((b) => console.log('   ' + b)); } else console.log('OK   ' + f + '  (' + ep.legs.length + ' legs)');
}
process.exit(fail ? 1 : 0);
