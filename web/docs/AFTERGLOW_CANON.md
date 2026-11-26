# Afterglow canon: how the world stays in sync

One file holds the world's names and what every app, network and voice says when something happens:
`web/babylon/canon.js`. One command checks it against the game:

```
cd web/babylon
node tools/canon_check.mjs
```

## What the checker tells you

- **NEEDS JOKES**: something exists in the game with no lock-screen lines yet: a world (`JNAME`), a strain (`COMP`), a quest (`QI`) or a raid craft (`WCRAFT`). Add a `react['world:key']`, `react['strain:key']`, `react['quest:key']` or `react['craft:key']` entry.
- **NAME DRIFT**: the game and the canon disagree on a name. Fix whichever is wrong.
- **BROKEN**: a dose of a strain that doesn't exist (this caught the old preview's `'ember'`), an unknown `{token}`, or a voice that isn't on `canon.voices`.
- **WORTH A LOOK**: canon entries the game no longer uses, and cast the glossary never mentions.

It exits with code 1 when anything needs fixing, so it can run before every deploy.

## When you add something

| You add | Then |
|---|---|
| a world | `worlds` name + `react['world:key']` (one widget, one notification) |
| a strain | `strains` name + `react['strain:key']` |
| a quest | `quests` entry + `react['quest:key']` |
| a raid craft | `crafts` entry + `react['craft:key']` |
| a person or faction | `people` / `factions` + a glossary entry |
| a new app or service voice | add it to `voices` |

Then run the checker until it says nothing to write.

## How reactions fire

The game passes what is happening (`window.__lkCtx()` in index.html): world, progress, strain, hits, dial, cameras exposed, quests done, the world's raid craft. The title screen passes the trail (last seen, expected next). `lock.js` turns each true signal into lines from `canon.react`, fills the tokens, and about half the time shows one as a widget and one as a notification.

Tokens: `{world} {where} {pct} {odds} {bounty} {strain} {hits} {f} {sights} {last} {next}`.

## Writing rules

Voices are ACCORD, MURMUR, a person, or a made-up service. They are never the game's makers, and never real brands. Use glance copy: short, with the punchline last. The bar is the GPU smoke widget: "Datacenter exhaust advisory. Mild lung inflammation, now with ray tracing."
