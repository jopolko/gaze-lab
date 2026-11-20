# The director: what Godot already does, and how we use it (source analysis, 2026-11-19)

Decision: **we do not write our own course generator.** Godot-dev's `RunRig.gd` already is the director, and its output is already in the level dumps (`web/downhill-three/data/long_*`). Where we want something different, we change the rule at its source in Godot, regenerate the dump with the real generator, and port the result. The segment grammar in `GAME_SPEC.md` section 3 is a description of what Godot does, not a thing to build.

Everything below is read from `godot/scripts/RunRig.gd` (line numbers as of this date). "Not read yet" lists are marked.

## 1. How a course is generated

`_gen_segment(j)` (2222) builds one row of `ROW_GAP` (180 m in the dumps). Each row gets, in order:

1. **Difficulty** `_course_diff(z0)` (2424): `clamp((0.12 + progress * 0.88) * diff_scale, 0, 1)`, with progress over `min(|finish|, 4200)` m. Gate width, singles and buff offers all scale with it.
2. **Zone** (`_region_step`, `_pick_zone`, ZONES at 2411). Zones: rush, flat ("meadow"), tunnel, bend, air, forest, drop; realms (highway, interzone, hive, eyes, melt, mandala); roofed (canyon, mammoth, glowcave, crystal, lava, abyss). Each has pitch `m`, gate width `w`, singles density, wall half-width, path-buff chance. The first 3 rows are always "rush"; an air zone can't follow an air zone.
3. **Two modes.**
   - *Barrier mode* (the Godot gaze game): a barrier row of trees and boulders across the whole course with 1+ openings (`_layout_gaps`), the safe opening moving at most a third of the distance since the last barrier (8 to 44 m): **reachable by construction**. Opening width `lerp(17, 10, d) * zone w`. Singles scattered between, never on the straight line between safe openings (`path_x`, `chord_x`).
   - *Trail mode* (`trail`): no barriers; the zone is chosen by pitch (`flat` under grade 0.7, `rush` over 1.1, else `forest`); `_gen_trail` plants the forest around a winding trail. **All five dumped courses are trail mode** (0 of 43 rows have a barrier; zones are flat/forest/rush only).
4. **Content**: kicker or air zone (`_place_kicker`), boost pads (`pad_chance`), buffs (`_place_buffs`), signs, scenery, then `_gen_toys` (toys, molecules, link chains, caves, launches).

## 2. Buffs: how offers are placed (`_place_buffs`, 4131)

- **At each opening**: chance 1.0 if isolated, 0.45 if it is the safe one, 0.35 otherwise. The offer sits 9 to 22 m before the gate (first clear spot) with a three-orb trail leading in. Which buff is chosen by `_pick_for_gate(leads)`.
- **Beside the safe line**: in spans of at least 80 m, with the zone's `path_buff` chance (flat 0.85, rush 0.30, tunnel 0.12...), a buff 8 to 13 m off the safe line, mid-way (42 to 58%) between barriers, with a smoothstep orb trail pulling you to it. "You have to look there and want it."
- **The chain of kinds**: candy (x2) first, then burger (speed), then ramp, then a face or a trick in the air. Each in order within a few seconds raises the chain level (1 to 4).

## 3. Molecules, and why they come in threes

- **Pace** `_mol_gap()` (9195): `clamp(session_minutes * 60 * 33 / 8, 700, 4200)` m. "One of each a run: six finds (and two rows to spare)". A 10-minute session: 2475 m between molecule rows. Once all six are found: 1100 m (top-ups only). `_pills_ok` forbids a row within 60% of the gap of the last. The pacer's `spawn_bias` (0.6 to 1.6) closes or opens the gap.
- **Which**: `_pick_molecule` weights a not-yet-found one at 4.0, a found one at 0.7, a near-full one at 0.2. A missed one comes round again.
- **Three lanes** `_make_pills` (9660): three different molecules at `trail_x + {-8, 0, +8}`, the outer two 2 m further on. Godot's own comment: "which one to look at is the choice". It was built for eye-tracking: you pick a molecule by looking at it. It is not clutter in Godot's logic. It is the choice.
- **Where it is built**: not as a toy: either at its own pace (`_mol_next_z`) or as the **prize at the end of a link chain** (see 4).

## 4. Link chains: the jungle gym (`_make_link_chain`, 9060)

This is the "loops, jumps, rails" structure from the design discussion, and it already exists:

1. A **spring pad** in a side lane (`trail_x + side * 7`).
2. A **tube** the board rides, of shape arc (22%), loop (28%), spiral (28%) or sky (22%), 95 to 115 m long, dressed with rings (`_lk_dress`, orbs).
3. Ends on a **rail** `LK_RAIL_L` long in the lane across (`x1 = x0 - side * LK_SHIFT`).
4. The rail **throws the board about 85 m** into the opposite lane. That is where the next thing is built:
   - 50% (depth < 2): another chain, so chains of up to three, each worth more, with an alternative of molecules or a boost row;
   - 28%: a row of molecules, with a boost row as the alternative;
   - 22%: a boost row, with molecules as the alternative.
5. In the air, looking left or right decides which lane you land in (the eyes choose the lane in flight).

Also `_make_launch` (ramp) and `_make_cave` (a cave with a low mouth), chosen 22% / 28% when caves are enabled. 12 link chains are in the 7.7 km dump (arc 2, loop 2, spiral 2, sky 2, launch 4).

## 5. What is already ported to three.js

| Godot | Three.js | State |
|---|---|---|
| terrain, rows, trees, rocks, ramps | the streamed dump (`data/long_*`) | done |
| buffs, pads, rails | `gv.js` collectStep, railStep | done |
| link chains (spring, tube, rail, throw) | `toys.js` (`lkStep`) | done, the lane choice in flight is simplified (head nudge) |
| toys (gates, bumps, slings, pills) | `toys.js` | done |
| vortex ramps | `vortexfx.js` | done |
| molecule dose, perks, pacer, journey ARC | `psyfx.js` | computed, mostly not driving the picture |
| zones as visuals (tunnel walls, realms, roofed) | partial | the dumps only contain flat/forest/rush |

## 6. Where Godot's design differs from ours, and how to change it at the source

| Our goal | Godot today | Change (in Godot, then re-dump) |
|---|---|---|
| One molecule per site | three lanes | param `pills_lanes` (default 3 keeps the frozen output); set 1 for new courses |
| Molecule visible from far, readable approach | beacons exist (`_beacon`) | already ported; ranges tuned in gv.js |
| Approach = the chain that leads to the molecule | yes (`_lk_follow` pills) | none; raise the chance of "pills" as the prize in the flagship |
| Six molecules per trip, spaced | `_mol_gap` from session length | set the session/pace so six rows fit; courses already have 3 to 5 sites |
| A sixth-molecule finale | none | handled in the game layer (ARC / pacer), not the generator |
| Barrier puzzles with a saw (hedges 1 to 3 thick) | barrier rows with openings | use barrier mode for the flagship's puzzle chapters, adding a "cuttable" tag to the barrier trees |
| Reachability guaranteed | yes, by construction (barrier shift cap, chain throw 85 m) | keep; any new piece must respect the cap |

RNG warning: the generator draws random numbers in sequence. Changing the number of molecules drawn per row changes every later row for the same seed. New courses are fine; the five existing ones stay frozen.

## 7. The pipeline (so a re-dump is routine)

1. Edit `RunRig.gd` (behind a param so default output is unchanged).
2. `OUT=... SEED=n THEME=psychedelic SEGS=n Godot_v4.7.2-stable_win64_console.exe --headless --path godot res://tests/dump_long.tscn` (Godot is at `C:\Users\josh\Downloads\Godot_v4.7.2-stable_win64`).
3. `web/tools/split_level.py` splits the JSON into `meta.json` and `row_NN.json`; `web/tools/make_physics.py` builds `physics.json`.
4. Add the course to `courses.json` and deploy `data/<course>/`.

## 8. Not read yet (read before changing)

`_gen_trail`, `_toy_feat`, `_make_pad`, `_make_vortex`, `_make_launch`, `_make_cave`, `_lk_dress`, `_boost_row`, `_pick_for_gate`, `_layout_gaps`, `Realms.gd` (the realm and roofed zones), `DhJourney.gd` (waves and worlds), `DhPacer.gd`, `DhProgress.gd`.

## 9. Consequences for the spec

- Section 3 of `GAME_SPEC.md` (segment grammar) becomes a **description of Godot's zones and chain structure**, not a new system.
- The "approach" in section 5 is the link chain plus its prize. Do not invent routes.
- The director work item becomes: (a) read the remaining functions, (b) add the `pills_lanes` param and a "cuttable barrier" tag, (c) regenerate courses, (d) wire the pacer and `_mol_gap` so six sites fit a trip.
- Saw and hedges: only where Godot already places barriers (barrier mode); the trail-mode courses have none.


## 10. Barrier mode: where the variety is (measured 2026-11-19)

`dump_long.gd` now takes `BARRIER=1` (Godot's barrier-and-gates course instead of the single forest trail). A 40-row dump (seed 11, psychedelic) contains:

- **16 different zones**: rush, flat (open meadow), forest, drop, air, bend, tunnel (walled corridor), hive (walled), canyon, interzone, highway, eyes, mammoth, and four roofed caverns: glowcave (Glow Grotto), crystal (Crystal Vault), abyss (Jelly Abyss), lava.
- **Forks**: 37 of 40 rows have 2 or 3 openings, and each gate `leads` to a different next zone (the mystery gates). Layouts: trio, decoy, near, scatter, spread, pair.
- **Rendering cost**: the realms use only 14 distinct shader materials, most of them one small glow shader in colour variants, plus one 767-character ground shader and one small boost shader. The geometry is generic. So the realms are portable with a handful of shaders.

The five dumped courses and the seven biome courses are all trail mode: one winding trail, zones flat/forest/rush only, no forks, no caverns. Using barrier mode (or adding forks and caves to trail mode) is how the courses get variety. Caverns off the spring (`_make_cave`) are switched off by default in Godot (`w_caves`: "they were just tunnels in the way").

Open items before the viewer can play it: the realms' shaders, the roofed-realm exposure dimming (`Realms.cave_k`), the gates and the safe-line logic in barrier rows, and walls as obstacles.
