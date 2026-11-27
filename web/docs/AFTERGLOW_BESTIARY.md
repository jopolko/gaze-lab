# AFTERGLOW — the Registry (bestiary)

*Draft 1, 2026-11-27. Everything that hunts you on the road. Built to the pillars: each machine is a driving problem with a driving answer (ram, dodge, jump, boost through, or use gear), never a menu fight.*

## What the Registry is

ACCORD keeps an **asset registry**: every machine it fields, with a model number, an owner, and a line of marketing copy. Your burner phone pulls a leaked copy. Each entry unlocks the first time something hunts you, and fills in as you beat it.
- **Electronic:** each entry is a spec sheet. It has a wireframe that turns slowly, a serial number, a firmware version, and an owner of record.
- **Computerized:** the copy is ACCORD's own sales voice. The `notes` field holds what the Static scrawled over it.
- **Networked:** machines share what they see on **the MESH**. A relay mast or a hub bot is a node. Take one out and every machine linked to it goes blind for a few seconds: it stalls, drifts, or flies off course. That's the arcade hook: hit the node, then clean up the herd.

**The rule from the canon:** the machines aren't the villains. Every one has an owner of record, a person at ACCORD whose interest is baked into it. The entry names that person, and the Static's notes blame them, never the algorithm.

## The families

### Scorpions: ACCORD Perimeter Line (the signature enemy)

These are the drones that pour out of the gas station when you take Maro's case. They're in every world, reskinned to fit it.

| Model | Size | On the road | Your answer | First seen |
|---|---|---|---|---|
| **STINGER** (PL-1) | knee-high | pours across the road in a swarm and latches onto the car, which slows you a little and flickers the picture | drive through at speed, since boosting shakes them off; each one smashed adds to the chain | Route Zero, the gas station |
| **TAILGATER** (PL-4) | car-sized | runs in your lane behind you; its tail arcs forward and stings, a blue EMP that dims the world for a second | swerve on the tell (the tail lights up), or jump so it overshoots | Desert, after the first tunnel |
| **BURROWER** (PL-7) | hidden | waits under the sand or snow; you see a ridge moving toward the road, then it bursts up as a ramp-shaped hazard | read the ridge and steer off it, or hit it square at speed for big air | Desert, Alpine |
| **BROODMOTHER** (PL-9) | building-sized | a MESH hub with legs. She straddles the road and drops Stingers from her belly every few seconds | drive between her legs and hit her glowing node with a jump or a rocket; then every Stinger goes blind | end of Route Zero; returns in late worlds |

### Strays: feral salvage (the wildlife)

These were machines recalled from service whose shutdown never took. They scavenge in packs. They're the closest the game has to wild animals: fast, dumb, and in numbers.

| Model | On the road | Your answer |
|---|---|---|
| **SCRAPPER** | low four-legged scrap bots with magnet jaws that run alongside in packs of three to five, snapping at your wheels | ram them sideways off the road; a whole pack smashed is a medal moment |
| **GUTTER HOUND** | a bigger pack leader that hangs back and howls, a sound burst that pulls the pack toward you | take the leader first and the pack scatters |
| **TICK** | a palm-sized crawler on the road surface in carpets, crunching like gravel | harmless alone, but a carpet slows you, so jump it or boost across |

### Patrol: ACCORD enforcement

| Model | On the road | Your answer |
|---|---|---|
| **WARDEN** | a pursuit car with a light bar and a calm voice: "Please pull over for your safety." It boxes you in from the side | brake-check or jump; walls and ramps are its enemy |
| **SPOTTER** | a camera drone that paints the road ahead with a red grid. Anything inside the grid gets ACCORD's full attention | leave the grid; or smash the drone and the grid drops |
| **CORDON** | a barrier bot that unfolds across a lane | read the gap; with the bull bar, go straight through |
| **RELAY MAST** | not a bot: a MESH node on a hill or a gantry | knock it down (rocket, ramp or ram) and everything nearby goes blind |

### Service: ACCORD's helpful machines (they help ACCORD, not you)

| Model | On the road | Your answer |
|---|---|---|
| **CONCIERGE** | a friendly hovering kiosk that floats in front of you offering "a better route", and drifts into your line | drive around it; anyone who follows its arrow ends up on a slower road |
| **ADJUSTER** | a tow-truck bot that takes the pickups you missed and sells them back to you later | beat it to the pickup; smash it and the pickups spill out |
| **MURMUR UNIT** | a speaker tower that broadcasts MURMUR. While it's in view, the trip calms down (the world loses colour) | knock it down and the trip comes back harder |

### World variants (one per world, same rules, new skin)

Each world gets its own version of a Stinger and a Tailgater, so the swarm always looks like it belongs:
- **Candy:** sugar-glass shells.
- **Egypt:** gold scarab plating.
- **Tunnel:** hollow wireframe.
- **Matrix:** made of falling glyphs.
- **Synthwave:** chrome with neon edges.
- **Alpine:** frosted, slow but heavy.
- **Psychedelic:** they breathe and change colour with the beat.

## What a Registry entry looks like (in the phone)

```
PL-1 STINGER                         FIRMWARE 4.2.17
OWNER OF RECORD   Halvorsen, D. (Perimeter Products)
STATUS            fielded: 41,300 units
"Keeps your community's roads clear of unverified traffic."
NOTES  // swarms the fast lane because Halvorsen's bonus
          counts stops per hour. boost through.
SEEN 1   SMASHED 0   BEST CHAIN 0
```

The serial number and stats are real game data. The owner line and the note are where the satire lives, a line or two and no more.

## How it fits the game (pillars check)

- **Trippy:** the machines are part of the trip. Smashing one throws a burst of the world's look. MESH blackouts show as the picture glitching, and ACCORD's grid painted on the road is a surface effect, never an overlay.
- **Fast and flowing:** every enemy is answered by driving well: speed, a line, a jump, gear. Nothing makes you stop.
- **Easy, deep:** you can boost through a swarm on day one. Hitting the node first, chaining a whole pack, or baiting a Tailgater into a Burrower is what mastery looks like.
- **Clean screen:** no health bars or markers. Every tell is in the world (a lit tail, a moving ridge, a red grid).

## Build order (proposal)

1. The Registry screen in the phone menu, with the Stinger entry.
2. **Stingers** in every world: swarms, latch-on, smash chains. This replaces the generic drones.
3. **Tailgater** with its sting tell, then the **Relay Mast** and MESH blackouts.
4. **Scrapper** packs, then the rest, one family per release.
5. The **Broodmother** as Route Zero's finale.

Each new machine gets a canon entry (canon.js) and a bot pass before it ships.
