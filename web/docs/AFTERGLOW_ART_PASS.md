# AFTERGLOW — art pass: style kit, audit, plan

*2026-11-26. The bar: the intro gunship and the rebuilt raiders. Simple primitives, no imported 3D models, fast on a phone, and nothing left looking basic beside them.*

## 1. The style kit (every object follows this)

1. **Silhouette first.** Read the object from 60 m in one glance: a clear shape with one recognisable feature (a visor, a fin, a lamp).
2. **Dark base, one accent, one light.** Body in near-black gunmetal or the world's dark tone; ONE accent colour that says what it is; ONE emissive light that blinks, glows or sweeps.
3. **One moving part.** Rotors, a spinning ring, a sweeping beam, a bob. Movement reads as alive and costs nothing.
4. **Colour means something.** Gold = yours / a prize. Cyan = SEE and pickups. Red = danger and ACCORD. Violet = lenses. Amber = ACCORD's corporate brand. Green = open / go. No other meanings.
5. **No flat white or black areas, no pink** (standing rules). Emissive values 1.5–2.8 for lights so the bloom picks them up; bodies stay under 0.4.
6. **Cheap by construction.** Primitives with 8–20 segments; one shared material per colour (`rMat` / `solidMat` cache); instancing or thin instances for anything placed more than ~6 times; no per-object textures except signs.
7. **Signs are world objects, not text walls.** One or two words, ACCORD's corporate type, a lit frame. Anything longer belongs in the logbook.

## 2. Audit (critical: upgrade, keep, cut)

Verdicts: **UP** = upgrade to the kit · **KEEP** = already at the bar or not worth the cost · **CUT** = remove or replace.

| Object | Where | Now | Verdict and why |
|---|---|---|---|
| Raider craft (8) | raids | jet rebuilt; others dressed | **UP** the remaining seven to the jet's level (silhouette + visor + accent). Biggest visual payoff; seen every level. |
| Intro gunship / car / scorpion | intro | the bar | **KEEP** (reference). |
| Scorpion drones (diner) | Route Zero | simpler than the intro's | **UP** to the intro scorpion; they're about to appear in every world. |
| Strain columns (molbeam, dose beam) + molecules | all levels | strong | **KEEP**; check the floating name plates (`dosename`) are short. |
| SEE crystal / lens gems | story, levels | plain polyhedra in a beam | **UP** lightly: inner glow core + slow spin + ground halo. Key objects deserve it. |
| Beat pickups (`beatp`), orbs, spill | all levels | plain icospheres | **KEEP** shape (they're instanced, many on screen); add one shared rim-glow pass only if cheap. |
| Rings (`kring`, `landring`, prize) | all | plain tori | **UP**: a second thin inner ring rotating the other way, light at the top. Cheap, reads much better. |
| Kickers / ramps / ram ramp | all | boxes + posts + beam | **UP**: chevrons on the deck, lit lip, posts in the accent colour. Gameplay-critical: must read at speed. |
| Set-piece parts (chains.js: pad, kick, spring, rail, helix, gate posts) | all | chrome posts, plain rails | **UP**: lit rail edge, spring coils, gate frames with the NEED colour; one consistent "track furniture" look. |
| Exit gantries + signs (`exsign`, `exgate`) | all | canvas text plates, posts | **UP**: highway-gantry frame with lit border; text cut to one or two words (already shortened). |
| ACCORD billboards (`accSign`) | story/levels | plate on a post | **UP**: a lit frame + a blinking "LIVE · SWARMCAST" corner; they're satire carriers, fewer now, so each should look good. |
| Tunnel hazards (dimmers) | tunnels | spheres/torus | **UP** to ACCORD hardware (dark body, red eye, a scanning beam). |
| Ammo (pods, jars, cubes...) | raids | simple shapes | **KEEP** mostly; add a blinking light to each (one line each). |
| Bombs' landing rings (`raidmark`) | raids | discs | **KEEP**: clear and functional. |
| Diner, Dex's car, Maro's case | Route Zero | new, decent | **UP** small: case gets a handle and a latch glow; diner gets a lit sign frame. |
| Story lanes: gold drones, crates, chest, rocks | Route Zero end | plain boxes / icospheres | **UP**: drones get rotors + light; crates get bands; chest a lid + glow. Rocks KEEP. |
| Relay mast / super rocket / UFO toys | toys | mixed | **UP** the relay (Murmur's relay is a story object); UFO **KEEP**. |
| Finish arch (`finp`, `finbn`) | level ends | posts + banner | **UP**: a proper finish gantry in the world's accent. |
| Terrain, trees, rocks, scenery | baked bank | Godot-baked, recoloured by the trip | **KEEP**. Not worth touching: the trip look carries them, and they're 1,571 baked sections. Only fix anything that reads flat (rule 5). |
| Sky / sun / stained glass | all | strong | **KEEP**. |
| HUD bits (chips, banners, results) | screen | consistent | **KEEP**; any new UI uses the same type and colours. |

## 3. Plan (phases, each shippable on its own)

1. **Track furniture**: kickers, ramps, rings, set-piece parts, gate frames. (Biggest gameplay readability win.)
2. **Enemies**: the other seven raider craft to the jet's level; scorpion drones to the intro's; tunnel dimmers as ACCORD hardware.
3. **Key objects**: SEE crystals, lenses, Maro's case, the story lanes' drones/crates/chest.
4. **Signs & world props**: exit gantries, ACCORD billboards (with the SWARMCAST "LIVE" corner), finish gantry, relay mast.

Each phase: build → screenshot every changed object at play distance in two worlds → fps check on the probe (no worse than before) → deploy → note here.

## 4. Practicality notes

- One shared helper (`kit`) builds the common parts (lit frame, blinking light, accent stripe, beam) so every object is built the same way and stays consistent.
- No new textures beyond sign plates; no new per-frame work except the existing tag animations (`blink`, `rotor`, `beam`, `spin`).
- Performance budget per phase: draw calls up by no more than ~5% on the probe's fps reading; anything placed many times uses instances.
