# Downhill: progression and structure (draft 1, 2026-11-19)

Working from the end backwards: six molecules open the trip of a lifetime, so everything else exists to get you to the right place at the right moment to catch one.

## 1. The promise

> You are sliding down an endless, beautiful slope. Far ahead, something shines. It takes ten to twenty seconds to reach you. In between there is a playground (jumps, loops, rails, blasts) and a small puzzle: which combination puts me on the molecule's line? Catch it and the world changes. Catch all six and you get the trip of a lifetime.

Three clocks, each with its own reward:

| Clock | Length | Question the player asks | Reward |
|---|---|---|---|
| **Moment** | 2-20 s | "How do I get over there?" | speed, air time, chains, sound, score |
| **Run** | 3-5 min | "Which molecule do I go for?" | 1-3 molecules, a run grade, a ghost |
| **Collection** | hours to weeks | "What am I missing?" | depth levels, new courses, finale |

## 2. What the data says today (counted from the Godot level dumps)

| Course | Length | Molecules | Sites | Types present |
|---|---|---|---|---|
| long_s7 (current) | 7.7 km | 9 | 3 | 4 of 6 (no DOM, no 2C-E) |
| long_s7b | 11.3 km | 15 | 5 | 6 of 6 |
| long_s11 | 11.3 km | 12 | 4 | 6 of 6 |
| long_s23 | 11.3 km | 15 | 5 | 6 of 6 |
| long_s42 | 11.3 km | 15 | 5 | 6 of 6 |

- Molecules come in **trios**: three side by side, 8 m apart (a "pick one" site). That is already a good design. You can't have them all, so you choose, and you replay.
- Per km (the current course): boost 4.4, sugar 3.0, shield 2.5, donut 1.8, rails 2.7, ramps 1.6, slingshots 0.6, gates 3.6, pads 44 (the small trail ones).
- The first molecule site is at 2.35 km. That is about 50 s in. Then 4.3 km and 5.95 km.
- Today a molecule only adds to a counter ("2 OF 6") and score. **Nothing is unlocked by it.** The four buffs are not tied to the goal at all, and the donut is worth +160 points and nothing else.

So the honest answer to "how rare is everything": molecules are one per ~2.5 km, buffs about one per 90-110 m, and nothing tells the player which buffs matter. That is why you can't decide what to highlight.

## 3. The six molecules and what each one does

Each molecule is a **layer of the trip**. They stack. Names are the six already in the game.

| # | Molecule | Colour | Unlocks (layer of the trip) |
|---|---|---|---|
| 1 | mescaline | violet | colour: the world recolours (the look you love) |
| 2 | 2C-B | green | geometry: patterns crawl on terrain and sky |
| 3 | 2C-E | amber | time: speed trails, echoes, the beat pulse deepens |
| 4 | DOM | red | sound: the music opens up (stems join) |
| 5 | 2C-T-2 | cyan | space: the horizon bends, the field of view breathes |
| 6 | 2C-T-7 | white-gold | mind: faces and symbols in the mountains and clouds |

All six at once = **the Finale**: the chill-out level ("Moodless Refrain"), where every layer runs together on an unbroken, hazard-free glide. That is the trip of a lifetime, and the music's chill stage finally has a reason to exist.

Each molecule also has **depth 1-3** (see section 6). The layer gets stronger per depth, so a depth-3 collection is a much bigger finale than a depth-1 one.

## 4. The run: how a molecule encounter works

A run is one descent of a course. Pacing is **a set-piece about every 1.5-2.5 km**, so a run has 3-5 encounters (the dumps already have 3-5 sites).

Each encounter has four beats:

1. **Sighting** (900 m out, about 18 s). The molecule's column of light is visible from far off and the top-centre readout shows its name and distance. Nothing else competes with it.
2. **Read** (900-400 m). The slope shows you 3-5 **routes** (the jungle gym). Each is a short chain of toys that ends on a different sideways line. Ramps and rails are marked as route pieces, not as pickups.
3. **Commit** (400-100 m). You are on a line. Corrections are small and come from steering, air control, a slingshot or a buff.
4. **Catch or miss** (last 100 m). Catch: the layer unlocks with a flash and a sting. Miss: a clear "missed by 4.2 m" and the trio is still there next lap.

The puzzle is the **reach envelope**: how far sideways can I still move by the time I get there? Roughly, at about 50 m/s and 18 s of warning:

- plain steering on snow: ±15-20 m
- a rail: carries you to its far end, usually 20-40 m sideways
- a ramp plus air steering: ±40 m for a 2 s flight
- a slingshot or gate chain: shifts and speeds up

Trio sites are 24 m wide, so from a bad line you can reach one molecule, maybe two, with a clever route. A perfect route reaches the one you want.

## 5. Pickups: a role for each, and what gets a pillar of light

The rule: **a thing gets a pillar only if it changes where you can be at the molecule**. Everything else gets a small local glow, which stops the screen filling with columns.

| Item | New meaning (tied to reaching the molecule) | Pillar? | Rarity |
|---|---|---|---|
| **Molecule** | the goal | Yes: tallest, white-prismatic, visible 900 m | 1 per 2.5 km |
| **Ramp / launcher** | a route piece: air steering ±40 m | Yes, mid range (520 m) | 1.5 per km |
| **Rail** | a route piece: carries you sideways | Yes, mid range (520 m) | 2.7 per km |
| **Boost** | reach: speed, so you cover distance | Short (150 m) | 3-4 per km |
| **Shield** | forgiveness: lets you cut through trees or rocks on a shortcut | Short (150 m) | 2.5 per km |
| **Donut → "Drift"** (reworked) | lateral reach: double air steering for 8 s | Short (150 m) | 1.5 per km, rarer, near ramps |
| **Sugar → "Magnet"** (reworked) | catch radius: molecule grab zone ×2 for 10 s, plus the x2 score | Short (150 m) | 2 per km, one placed on each approach |
| **Pads** | momentum chain starters | No pillar, ground chevrons only | as now |
| **Slingshot / gates / bumps** | route pieces, chained in the jungle gym | No pillar, bright ring | as now |

Chains matter too: ramp → rail → pad → slingshot keeps a multiplier alive, and the multiplier scales both the score and the strength of the layer you get from the next molecule. So style is rewarded, but never required to progress.

## 6. The collection: days or an hour

**Fast path (about an hour):** play any course, take any molecule at each trio, replay until you have seen all six at least once. Finale unlocks. This is the "trip of a lifetime, first time" experience.

**Slow path (days to weeks):** each molecule has three depths. A depth is earned by *how* you caught it, not by grinding:

| Depth | Condition (examples, one per molecule so each needs a different skill) |
|---|---|
| 1 | catch it |
| 2 | catch it with a clean approach (no crash in the last 1 km), or from the air, or on a rail |
| 3 | catch it with a mastery condition: no steering correction in the final 200 m, **or** at top speed, **or** two in a row |

Plus:
- **Courses:** five exist (7.7 km and four 11.3 km). Unlock by catching the six on the previous one.
- **Daily course:** one seed per day, one trio set, a ghost to beat.
- **Trip themes:** cosmetic looks for the Finale, earned at depth milestones.
- **Journal:** a page per molecule showing where it was caught, best approach, miss distances.

Finale strength = sum of depths. 6 at depth 1 is a good trip. 18 at depth 3 is the whole mountain.

## 7. Making it feel fair (the "minor amount of challenge")

- **No death.** A crash costs speed and shield, not the run.
- **Near-miss feedback**: "missed by 2.1 m" is a lesson, not a failure.
- **Adaptive help**: miss twice at the same site and the next trio spawns a little closer to your line and the approach gets one more rail. The reverse for a streak.
- **Never a hidden requirement:** every route to a molecule is visible from 400 m.
- **Teach in the first minute:** the first run has a slow, centred, single molecule at 450 m with one ramp ahead of it.

## 8. What to build, in order

1. **Reach readout** (small): show lateral offset to the target molecule and a "reachable / stretch / out of reach" colour. This tells us whether the envelope numbers above are right.
2. **Pillar tiers** (small): implement the table in section 5. This answers "what to highlight".
3. **Encounter director** (medium): lay out the sighting / read / commit / catch beats using the existing dump sites; tag a route around each.
4. **Molecule layers** (medium): wire the six layers to the existing psyfx/music hooks, so each catch visibly and audibly changes the world.
5. **Buff rework** (small): Drift and Magnet, retire the donut's +160.
6. **Run grade, miss feedback, journal** (medium).
7. **Depth conditions + collection screen** (medium).
8. **Finale on the chill level** (medium).
9. **Courses unlock, daily seed, ghost** (large).

## 9. Ontology: buffs as a system (added 2026-11-19)

Every pickup answers one question about reaching a molecule, and each has a **visible body effect** so you always know your state at a glance. Effects stack, and the player's job is to pick the order.

| Buff | Verb | Effect | Body effect (built) | Counter-play |
|---|---|---|---|---|
| **Boost** (crystal) | arrive sooner | speed kick + faster for 2-3 s | orange fringe + trail | speed shrinks your steering time |
| **Shield** (target: saw blade) | survive a shortcut | takes one hit; planned: cuts trees on contact | cyan fringe | one use, breaks |
| **Wings** (was donut, built) | steer in the air | 2x air steering for 8 s | pink fringe | useless unless you jump |
| **Magnet** (was sugar, built) | be forgiven | molecule grab 2x wider, other pickups 1.6x, for 10 s | purple fringe + waves on the snow showing the new width | timed; flickers in the last 2 s |
| **Molecule** | win | unlocks a layer | white flash | one per site |

Decisions this creates (the point of the game):
- Boost *now* for a shorter approach, or save the line for the Magnet that's 200 m further?
- Shield or Wings for a ramp that sits right before the molecule?
- Take the rail (safe, locked sideways) or the jump with Wings (free, risky)?

Build ahead: a **loadout slot** (hold one buff, pick when to spend it), so the choice is made in the moment, not by whatever you ran over.

## 10. Answers to the pasted questions

- **An hour as the target, with pause points?** Yes. Aim at 45-60 min for a first complete trip, in six chapters of 8-10 min (one molecule each). Between chapters put a calm flat stretch with a save point (a "campfire") where pause, journal and loadout live. Players can stop there and come back.
- **Shield as a saw blade that cuts trees?** Yes, and it fits the ontology (a shield that is also a route). Needs: tree instances hide on contact, a spinning blade visual, a hit counter (3 cuts, then it's gone).
- **Donut as balloon or wings?** Wings, built as a first pass: 2x air steering for 8 s.

## 11. Questions for you

1. **Trio rule:** keep "pick one of three" (replay value, but two clean runs minimum to get six) or allow collecting all three with a hard line?
2. **Layers persist:** after a catch, does the layer stay on for the rest of the run only, or keep forever across runs?
3. **Flagship vs psych:** do the six layers apply in both, with psych as the full-strength version, or only in the flagship?
4. **Finale:** a separate level you travel to, or an automatic transition at the end of the run when you hold all six?
