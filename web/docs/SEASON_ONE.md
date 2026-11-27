# Downfall: Season One (the build spec)

Written 2026-11-24. This is the spec being built autonomously in `web/babylon/`. Progress is in `BUILD_LOG.md`. Owner rules that override everything here: clean screen, gritty tone with sparse satire, frugal content, skill over brute force (see memory notes).

## The rules of content (owner, 2026-11-24)
1. **Nothing exists unless it matters.** No pickup, ramp, arc, pad, orb or obstacle is placed unless it is part of a lesson, a quest, a route or a reward. The course files' own scattered content is removed in every mode.
2. **Readiness before density.** The game measures how the player is doing and only adds more when they're ready.
3. **Economical, regular rewards, priming the big one.** Small rewards often (a pad into a ring, an orb trail to a lens), each level building to one big payoff at its end.
4. **Attainable and repeatable.** Every level is the same each time (fixed placement), so skill grows run by run. No randomness in levels; the daily variety lives only in the Endless Journey.
5. **Splurge on the psychedelic effects.** They are the reward language.

## The game
Eight levels, one per world, all by car. Each is a highway with exits. A level is about 6 km (two to three minutes).

| # | World | Level | Lens it teaches | Big reward |
|---|---|---|---|---|
| 1 | desert | Route Zero | SEE | the Lamp lights the tunnel |
| 2 | candy | Sugarfall | READ | the vault opens: a wall of colour |
| 3 | alpine | The Safe Peaks | SLOW | the lift: a slow-motion ride over the peaks |
| 4 | egypt | The Tomb of the Old Servers | HEAR | the tomb sings: the sky lights to the music |
| 5 | synthwave | Neon Accord | TRUTH | every billboard flips to the truth at once |
| 6 | tunnel | The Undertow | SEE + HEAR | the dark tunnel maps itself in sound and light |
| 7 | matrix | Cold Rack | MERGE | the racks go dark; the record plays |
| 8 | psychedelic | The Open Channel | all | the ending: the Lamp, full trip |

## A level's shape (by distance)
- **Act 1, teach (0 to 2 km):** the level's new thing introduced alone, with one beat, then a safe first meeting.
- **Act 2, practise (2 to 4 km):** the new thing mixed with what the player already knows; the first exits.
- **Act 3, test (4 to 6 km):** the lens lock (main quest) and the finale; the big reward.
- Between acts: a breather (clear road, the world and the music).

## Quests (eight per level, 64 in Season One)
- **Main quest (1):** the lens lock. Needed to finish the level properly; without it the level still ends, without the big reward.
- **Gear quests (4):** one gear-locked exit per gear (rubble for the Bull Bar, a drone barrier for Rockets, a broken bridge the Magnet pulls back, a hazard run only the Shield survives). Each area holds a shard.
- **Challenges (3):** gold grade, a clean run (no hits), the hidden exit (visible only under a lens or in RUSH).

## Exits
An exit is a signed off-ramp that leaves the road onto the open ground beside it (the courses have about 25 m of open ground each side), runs through a short area, and rejoins the highway. Locked exits show what they need (a lens icon, or a gear icon with a gold beam if it's yours and a padlock if not). Missed exits are listed on the end card.

## Readiness (how density is paced)
A readiness value R from 0 to 1, saved per player, rises with hazards handled (avoided or answered by gear) and pickups taken, and falls with hits and missed lessons. Each level has three placement tiers fixed in the level script; R picks the tier, so a given player always meets the same layout until they improve. New players get tier 1 (sparse), experts tier 3.

## Economy
- **Points** stay internal. They grade a level (bronze, silver, gold); thresholds are per level.
- **Shards** are the currency: main quest 1, each gear quest 1 (five per level, forty total).
- **Unlocks:** finishing a level's main quest opens the next level; the Endless Journey opens after Route Zero; four shards buy a gear's tier II (salvo rockets, longer pole, a fourth shield charge, a wedge bull bar); challenges unlock looks in the editor.
- **RUSH** fills from good driving; while it lasts you can smash through one locked exit you lack the gear for (a taste of another gear).

## Enemies (one behaviour each, introduced like the tutorial)
Ad drones that swoop into your lane; re-alignment drones that chase and give up; mine barges that drop a line of mines across the road; falling debris with warning shadows. Each gear answers them differently.

## Menu and flow
First launch: character editor, then the tutorial. Main menu: Continue, Levels (the map of eight), Journey (after level 1), Tutorial, Character. Pause menu as built. No numbers during play; the end card and the menu show grades, shards and missing quests.

## Out of scope for Season One
New vehicles (jetski, glider, bee, minecart), the other four levels, the hub map beyond a simple level list, the three endings (one ending in Season One).

## The adversarial test (owner rule)
Before anything ships: would Josh play it even once? Would he replay it? Would he recommend it to his son without wasting his attention? If not, cut or fix it. Every milestone in BUILD_LOG.md records the honest answer.
