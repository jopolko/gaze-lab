# Story bible (draft 1, 2026-11-20)

Purpose: one consistent story and world that every region, quest, building and effect is written from. Nothing gets built that isn't answerable to this document. Proposals are marked (P) and are the owner's to change. Read with `GAME_SPEC.md` (mechanics) and `DESIGN_PROGRESSION.md` (the dose arc).

## 1. The premise in five lines
1. Something ended the old world (the Collapse). We never say exactly what. People call it "the Fall".
2. Radiation and what came after altered ordinary molecules in plants, water and soil. Those altered molecules turned out to fit receptors in the human body that have sat unused for as long as there have been people.
3. Bodies that take them in begin to change: new senses open, one at a time. Survivors call the molecules **the Pieces**. There are six.
4. The change is slow and spreads through generations. The people who have it fully are the **Whole**. Almost nobody is yet.
5. You ride a dirtbike across the ruins toward the one place where all six are said to meet, and you become the first to open all six senses at once.

## 2. The Change (why it works, kept short and in-world)
- Not magic, and not a drug story. It is evolution catching up with something: the body was built with locks nobody had the keys to.
- The Pieces are not made by people. They form in the wasteland: in glowing growths, in storm-washed soil, in old reactor pools. That is why the strange flora and the realms are everywhere.
- **Dose is the gate.** A little opens a sense briefly. Taking it in again and again makes the sense stay. When a sense is permanent for a person it is "settled". Most people are settled in none; a few in one.
- A sense can overload. Too much at once and the world dissolves (the full trip look). Riders learn their limit. This is where the psychedelic picture lives: it is what perception looks like when it opens past what the brain can sort.
- Rule: the story never claims the Pieces are good or bad. They are a change, and people argue about it.

## 3. The six Pieces (P: each is a sense)
The on-screen names stay the names in `names.js` (Sunglass, Rootbloom, Driftwater, Chime Spore, Shard, Eyecap: named for the sense and the source, not tarot); the underlying molecules stay private to `molecules.js`.

| Piece | Sense it opens | What it reveals in the world | Region it is found in (first) |
|---|---|---|---|
| Sunglass | Warmth and life | Anything alive or recently warm: hidden people, animals, buried fuel, heat leaks that mark a hidden door | the green zone near the start |
| Rootbloom | Paths and cycles | Old routes, rail lines, the way things used to move; shortcuts; where a road once ran under the rubble | the road towns |
| Driftwater | Time and echoes | The past in a place: ghost traces of people, what a building was, where a thing was dropped | the drowned city |
| Chime Spore | Sound and resonance | Machines, hollow walls, buried metal, a signal; things that hum; safe versus dangerous ground | the industrial belt |
| Shard | Structure and weak points | Cracks, load paths, doors that can be opened or walls that can be broken; ledges you can ride | the high ruins |
| Eyecap | Presence and truth | Who is lying, who is watching, hidden watchers and traps; the Whole and the Hollow at a distance | the last region |

Combinations (P): two together show what neither does alone. Examples: Sun + Hourglass shows where people lived and still live; Wheel + Tower shows a route that can be built; Bell + Watcher finds a hidden transmitter and who is using it.

## 4. The world and journey
- A single long journey across **six regions**, one per Piece, each a place that makes sense of its Piece. The player can ride faster than they can explore; the world is bigger than the road.
- The bike: a salvaged dirtbike. Fuel, tires and a small carrying rack matter. Fuel is the clock; it forces stops, and stops are where the world meets you.
- Regions are connected by passes and a long road. The road is the spine; side routes are the exploration.
- Look: the first region is plain and grey (the ordinary ruined world). Each Piece you settle makes the world richer: colour first, then surface effects, then sky, then the full trip. The final region is the psychedelic world. This is the arc in `DESIGN_PROGRESSION.md`, now with a reason.

## 5. People (no voice acting; all text)
- **Settlers**: ordinary survivors in the towns. Practical, wary, funny. They want fuel, parts, news.
- **The Whole**: people with several Pieces settled. Calm, a bit strange, they speak in short odd lines. Not villains.
- **The Hollow**: people who took too much, too fast, and didn't settle. Dangerous, lost, not evil. They are what overdose looks like and the reason the game teaches limits.
- **The Wardens**: a group that wants the Pieces controlled or destroyed. They are the main opposition: not monsters, people who watched the Hollow. They run checkpoints and burn growths.
- **The Rival**: another rider after the same goal, met in every region. They want it first. Becomes ally or enemy by your choices.
- **The Voice**: a recurring guide that speaks through old radios and signs only. Text only. Appears in the quest log. Identity revealed in region six (P: it is someone who was settled in all six long ago).

## 6. The spine of the story
1. **Region 1 (Sun):** you wake in a quiet place, find the first Piece, and learn the bike and the sense. First hidden doorway, first fuel stop. Meet the Voice and the Rival.
2. **Regions 2 to 5:** one Piece each, each region with its own problem and a settlement that is hurting. Each region's main quest ends with a settlement choice: help the Wardens or help the Whole. The Rival and the Voice appear in each.
3. **Region 6 (Watcher):** the settled place. The Voice's secret, the final choice, the final trip.
- Main path is always rideable. Senses unlock secrets, shortcuts and side quests, never the way forward.
- Endings (P): three, by what you chose across regions: the Pieces spread freely, the Pieces controlled, or you refuse the last one and ride on.

## 7. Quest structure (how the story becomes quests)
Each region has:
- **One main quest** (4 to 6 beats) that moves the journey and ends in a settlement choice.
- **Three to five side quests**, each tied to a sense: they show an obstacle you can only solve after settling that Piece (or finding it again later).
- **One recurring thread** (the Rival, the Voice, the Wardens) that advances in every region.
- **Two or three discoveries**: places with no quest marker, only a hint (a hum, a shimmer, a warm wall). Reward: a story piece, a part, a lore card, a shortcut.

Verbs (same set everywhere): go, fetch or deliver, find, survive, ride, choose. Details and the data format go in `QUEST_DESIGN.md` once this document is agreed.

## 8. Towns and buildings
Every town is written as a **quest map first**: what is here, who wants what, what is hidden, what it gives. Only then are buildings chosen. Quality of buildings comes from consistent kits and our shaders, not from one-off models (see the open question on the asset kit).
- Each region has: one town (the hub), two or three small stops (fuel, a shop, a shelter), and a landmark you can see from far away.
- Businesses that matter to the bike: fuel, mechanic, trade, a safehouse to save.
- Residences and shops carry **small stories** (a note, an object), written to point at the same big story, never a one-off joke.

## 9. Tone and rules for consistency
- Dry, human, a little funny. Never grimdark; it is a world recovering, not ending.
- All story is text: one or two short lines on screen, skippable. No voice acting.
- Nothing contradicts section 2. If a quest needs the rules to bend, change the rules here first.
- The Pieces are never named by anything but the names in `names.js` in the public build.
- Every region must answer: what sense does it teach, what is in it that you can only see with that sense, what does it add to the story, and what does the player want here.

## 10. Open decisions (owner)
1. Is the guide's reveal (section 5) right, or should the Voice stay a mystery?
2. Is the Whole versus Wardens conflict the right main tension, or should the opposition be something else (the land itself, a machine)?
3. Region names and exact order of the six places (P above).
4. Asset kit for buildings and props (Kenney, Quaternius, Poly Haven, or other); needed before any town is designed.
5. Do the endings need to be three, or is one with a choice enough?
