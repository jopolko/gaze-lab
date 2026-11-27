# DOWNFALL: the complete game (v1, 2026-11-21)

> **Naming and status note (2026-11-21):** see `DOWNFALL_README.md`. Where this file uses older names (Chuck, Bonbon, Mildred, Dolores, The Burn, The Comfort Belt and so on), the names in `DOWNFALL_FACTIONS_AND_NAMES.md` apply.

Companion to `DOWNFALL_MASTER_PLAN.md` (story, theme, viral engine, modes). That file says *why and what it feels like*. This one says **everything in the box**: every place, character, piece of gear, surface, effect and boss, each marked with **where it is ported from** (Godot source file) or, where Godot has nothing, **that it is new and which Godot technique it copies**. Nothing is built unless marked **[built]**.

## THE CORE (read this first; it overrides anything below that disagrees)

**The core of Downfall is the three.js game as it plays today**: `shell.html?play&head&noshare&theme=alpine&course=long_alpine&js=gv_dev.js` (code: `gv.js` / `gv_dev.js`, `shell.html`). A phone-first, face-steered ride down a wide open slope; you steer with your head (left, centre, right, lean); you chain ramps, rails, pads, springs and pickups for momentum; you catch six molecules that stack layers onto the world; the world changes biome by biome in one journey with quick fades; a rocket comes near the end on a moment of skill; stars and a certificate close the run. That ride, its **steering feel** and its **look** are the product.

What that means for everything in this document:
1. **The Godot game is a quarry, not the blueprint.** From Godot we take *looks and parts that serve the ride*: themes, skies, grounds, trees, realms (gates), surfaces (`Zone.gd`), the picture pass, toys, music logic. We do **not** take its other game (a goose brawler with kicks, enemies to defeat, hit points and a skill tree for fighting).
2. **No fighting, no hit points, no aiming.** Anything borrowed from the brawler is turned into **ride** terms or dropped (see the revised sections 6, 7 and 10 below). Characters are *things on the slope you read and ride around*, gadgets are *one-tap helpers*, gear only changes the *feel* of the ride.
3. **Every addition has to pass one test:** does it make the ride better, or the world more beautiful or more surprising, **without making the steering harder or the screen busier**? If not, it is cut.
4. **The existing ride is protected.** The steering values (`gv.js`, locked 2026-11-20), the minimal UI, the no-scroll menus and the frozen psychedelic world do not change for any feature here. New things arrive behind flags on `gv_dev.js`, are checked on dev first, then promoted to prod with a backup.
5. **Build order starts from what is playing** (section 11): make the seven existing biomes stunning and complete before any new system.

Rules for every line below (from the owner): port from the Godot source whenever it exists; stunning, beautiful scenery and water in every place; the trippy effects that run well on a phone; head steering stays coarse (left, centre, right, lean); no auto-steer; gentle stakes; surface effects, never overlays; the psychedelic world stays frozen.

---

## 0. The box, in numbers

| Part | Count | Where it comes from |
|---|---|---|
| **Season 1: The Fall Line** (7 episodes) | 7 biomes | Godot `Themes.gd` `ORDER`: alpine, candy, desert, tunnel, matrix, synthwave, psychedelic **[all built]** |
| **The Vault** (secret episode) | 1 | Godot `Themes.gd` `egypt` (ground, veg, sky, pyramids, mummies, sandstorm) |
| **Gates** (mystery side-levels, 1-2 min, inside every episode) | 12 | Godot `Realms.gd` `IDS`: highway, interzone, hive, eyes, melt, mandala, glowcave, crystal, lava, abyss, canyon, mammoth |
| **Season 2: The Thaw** (6 episodes) | 6 biomes | New, authored in the same style (water, weather, nature). Uses Godot `Zone.gd`, `ThemeFX.gd` and `Realms.gd` pieces where they apply |
| **Rail staff and bosses** | 15 characters | Godot `Roster.gd` `DEFS` (the existing cast, re-cast into the story) |
| **The Unlisted** (companions) | 13 (7 + 6) | New; built with Godot's `Roster.gd` primitive-shape builder |
| **Gadgets** | 4 | Godot weapons: LeafBlower, PlungerGrapple, RocketLauncher, ShockRifle |
| **Gear** | 3 slots x 5 rarities x 19 stats | Godot `Loot.gd` (`STAT_INFO`, `SLOT_STATS`, `RARITIES`) |
| **Skill tree** | 3 branches | Godot `Progression.gd` `BRANCHES` and `SKILLS` |
| **Surfaces** | 6 kinds | Godot `Zone.gd` (bounce, boost, slip, sticky, lava, vent) |
| **Buffs** | 7 | Godot `RunRig.gd` 3547 (boost, shield, mult, donut) plus magnet, wings, saw from `GAME_SPEC.md` |

---

## 1. The Beauty Standard (applies to every biome, so "stunning" is a checklist, not a hope)

Every place must pass all ten before it ships. The Godot themes already pass most of them; the new ones are built to the same bar.

1. **A hero view in the first second:** looking down the slope at the start, a landmark and a colour story you would screenshot.
2. **Three depth layers:** near props (trees, rocks, crabs), mid (hills, dunes, ruins), far (silhouette mountains, skyline). From Godot `ThemeBackdrop.gd`.
3. **A sky worth looking at:** gradient, a sun or moon, bands or clouds from noise. From the Godot `SKY_*` shaders, ported **[built for 7]**.
4. **Fog and light matched to the sky:** the per-theme `env` block in `Themes.gd` (`fog`, `fog_density`, `sun_color`, `sun_energy`, `glow`, `saturation`, `contrast`) ported literally.
5. **One thing always moving:** sprinkles, snow, sand, code, fireflies, spray, a swaying tree (`VEG_LIVE_SHADER`).
6. **A glow pass:** bloom on the things that matter (gates, pickups, the path edge), nothing else, so the path always reads.
7. **A colour grade per place:** the `saturation` and `contrast` numbers, plus a gentle tone-map.
8. **Water that is beautiful if there is water** (see 5).
9. **The path stays dark and readable:** the Godot rule ("the neon goes on the things you must see").
10. **It holds 60 fps on a phone,** measured with the perf harness. Anything that cannot is a cheaper cousin of the same idea, not dropped.

---

## 2. Season 1: The Fall Line (the seven built biomes, now with their full cast)

Story beats, bosses and Pieces are in the master plan. This is the **content** each episode needs beyond that, all ported or marked new.

| Ep | Biome | Ported source | Surfaces and structures (Zone.gd, RunRig, new) | Gates inside it (Realms.gd) | Gadget it teaches | Rail staff |
|---|---|---|---|---|---|---|
| 1 | **Cold Storage** (alpine) | Themes `alpine`, GROUND, SKIRT, snowball (RunRig 1334, 7704) | `slip` ice patch, kickers and ramps (RunRig 10491), boost pads (7840), jump vortex (7851) | **Crystal Vault** (cold glow), **Glow Grotto** | **Leaf Blower** = *Updraft Fan* | Barry the Balloon (Chaperone) |
| 2 | **The Comfort Belt** (candy) | Themes `candy`: `GROUND_CANDY`, `VEG_CANDY`, `SKY_CANDY`, `fluffy_tree_mesh`, `gumdrop_mesh`, `candy_hills_mesh`; gumball hazard (`hazard_skin`) | `bounce` gumdrop trampolines, licorice rails (RunRig 8564), frosting `sticky`, spring-tube-rail set piece | **Interzone** (newsprint bazaar), **Mandala Drop** | **Plunger** = *Grapple* | Gerald the Banana, Tomato Tony, **THE BIG CHEESE** (boss) |
| 3 | **The Burn** (desert) | Themes `desert`: `GROUND_DESERT`, `VEG_DESERT`, `SKY_DESERT`; sandstorm (`ThemeFX.gd` 28) | `sticky` sand and mud, boulder canyon, wall rides, `vent` updrafts | **Desert Highway** (slick, bats), **Red Canyon** | **Rocket** | Big Brenda, Sir Bounce-a-Lot, Warden-General Pruitt |
| 4 | **The Underlay** (tunnel) | Themes `tunnel`: `GROUND_TUNNEL`, `VEG_TUNNEL`, `SKY_TUNNEL`; the cavern (RunRig 8821, `CAVE_SHADER`) | rails, `boost` strips, conveyors, moving platforms, loop-the-loop | **The Hive** (ribbed, breathing), **Lava Tube** | **Shock Rifle** = *Jammer* | Mime Marcel (the Silencer), Dizzy Dan |
| 5 | **The Mirror** (matrix) | Themes `matrix`: `GROUND_MATRIX`, `VEG_MATRIX`, `SKY_MATRIX`; matrix post mode 2 | floating data-blocks, code-rain bridge, glass wall rides | **Orchard of Eyes**, **Jelly Abyss** | **Jammer upgrade** (EMP chain) | Poof the Magician (the Redactor), Vacuum Vic (the Cleaner) |
| 6 | **The Broadcast** (synthwave) | Themes `synthwave`: `GROUND_SYNTH`, `VEG_SYNTH`, `SKY_SYNTH`; synthwave post mode 3 | billboard bouncers, neon wall ride, boost ribbons | **The Melt** (liquid ground) | all four, combined | Sir Bounce-a-Lot (the Bouncer, "not on the list"), Kaboom Kevin |
| 7 | **The Commons** (psychedelic) | Themes `psychedelic`: `GROUND_PSY`, `VEG_PSY`, `SKY_PSY`, `POST` mode 1; **frozen** | everything, blended by the dose | **Mammoth Garden** (giant glowing plants) | the player's loadout | none (the choice is the boss) |

**The Vault** (Egypt, secret): `GROUND_EGYPT`, `VEG_EGYPT`, `SKY_EGYPT`, pyramids and obelisks (`pyramid_mesh`), rolling mummies (`hazard_skin` = mummy), the sandstorm every ~55 s. Story: WREN's original servers under a data centre shaped like a pyramid ("someone's idea of permanence"). Unlocked by ending 4.

**Port status of the Godot look in three.js** is tracked in `WORLDS_PLAN.md` (per-biome table). The to-do from there, in this plan's terms: finish horizon landmarks (pyramids, candy hills), the weather per biome, then the two missing post passes (matrix mode 2, synthwave mode 3).

---

## 3. The Gates (12 mystery side-levels, ported from `Realms.gd`)

Every episode has one or two **gates**: a glyph (never a name) on a gate in the path. Ride through and you enter a strange short place with its own ground, props, rule and look; the name appears on arrival. They are the replay and discovery layer, cost almost nothing new (the shaders, props and rules exist in Godot), and each one maps to the story:

| Gate | Godot rule (`Realms.gd`) | In the story | Rides well with head steering because |
|---|---|---|---|
| **Desert Highway** | neon grid, bats; the surface is slick: you drift | the Rail's old arterial, a road that remembers speed limits | slip is forgiving, wide lanes |
| **Interzone** | paper-and-newsprint bazaar; at the far barrier the world is *cut up* and you are spliced sideways | **the home of the Redaction layer**: the Rail's censorship room, black bars and cut-out headlines | big shapes, one lateral splice to ride |
| **The Hive** | ribbed bone-and-pipe corridor that breathes; the beat speeds you up and drags you back, hoops to thread | the Rail's server farm, breathing with its cooling | rhythm and big hoops |
| **Orchard of Eyes** | giant eyes follow you; look toward one and hold it and it blinks shut and lets you pass | the Rail's watchers; teaches Eyecap and the camera joke | uses where you *look*, not tiny aim |
| **The Melt** | liquid, swirling ground that rolls under you; slippery slope | climate heat, a place the weather made soft | slow, wide, wobbly, gentle |
| **Mandala Drop** | steep fall through radial petals and rings; the ground a spinning colour wheel | pure trip, the falling-as-bliss moment | a steady drop, big targets |
| **Glow Grotto** | roofed cavern: dark mouth, a black tunnel, the lights come on, giant glowing mushrooms | a first taste of Sunglass (warmth, life) | dark-then-light reveal, calm |
| **Crystal Vault** | roofed vault of glowing crystal and stalagmites in cold colours | frozen server-vaults, cold storage | clean lines |
| **Lava Tube** | roofed basalt tube, glowing floor cracks, lava falls; fast and crowded (hard) | climate fire made rideable | the "hard" gate: optional for bragging rights |
| **Jelly Abyss** | deep roofed dark, drifting glowing jellyfish and coral; heavy going | under the sea before Season 2 | beauty, slow |
| **Red Canyon** | red-rock canyon | the Burn's heart | wall rides |
| **Mammoth Garden** | giant glowing plants | where the plants made the Pieces; a late gift | beauty |

The roofed gates already include the **exposure dimming and reveal** (`Realms.ROOF`, `apply_cave`): the picture dims inside and the glowing things become the light. Port as is.

Gates are **where gear and cuts drop** most often, so they are the reason to take the odd route, not a tax.

---

## 4. Season 2: The Thaw (six new places, authored in the same style)

Season 1 is about *thinking*. Season 2 is about *nature taking part*: the climate side of the story, never preachy. The theme: **the one molecule nobody designed.** A marine algae bloom, born of warm water, made a seventh compound with no AI in the loop: the **Tidewater**. WREN is jealous and curious. The Rail cannot find it, because nobody wrote it down.

Each is a place in the **Unmapped** whose map went stale first. All are built in three.js to the Beauty Standard, using Godot's techniques (single `ShaderMaterial`, noise in the fragment, per-theme `env` colours, surfaces from `Zone.gd`), because Godot has no source for them.

| Ep | Place | What it is | Signature look | Unlisted | Boss | Rig, game type |
|---|---|---|---|---|---|---|
| 1 | **The Tideline** (beach) | a shore at low tide, wet sand, rock pools, a pier, a ruined lifeguard tower | the **water** (see 5): turquoise shallows to deep blue, foam lines, caustics on the sand, a low gold sun | **Clive the hermit crab** (wears a dead phone as a shell); **crabs** scuttle sideways across the path (a lane-crossing hazard you read; a stumble if hit); a **crab colony** is the "Choir" of this place | **The Tide:** an incoming wave you outsurf along the beach | bodyboard, surf and balance |
| 2 | **The Drowned City** | the old city under shallow water: streets as canals, tower tops as islands (the original Driftwater region of the first bible) | rippling light on glass towers, sunken cars, drifting jellyfish, caustics on tarmac | **Sera the manta ray** (carries you over deep gaps) | **The Floodgate:** a barrier AI that opens in a rhythm | jet-ski, river drift |
| 3 | **The Stormbelt** | the place the forecasts forgot: lightning, rain curtains, a funnel on the horizon, shifting wind | dark teal sky, god-rays through holes in cloud (`SHAFT_SHADER`), rain streaks as surface sheen | **Petra the storm petrel** (rides updrafts, shows safe air) | **The Forecast:** a tornado the Rail predicted would not happen; ride its fall line | glider, tightrope in wind (`vent` updrafts) |
| 4 | **The Canopy** | a rainforest roofed by trees as tall as buildings, vines as rails, giant glowing fungi | green gloom, shafts of light, fireflies, mist; the **Mammoth Garden** look from `Realms.gd` | **Slo the sloth** ("the only one who has never hurried") | **The Strangler Fig:** a tree that closes lanes | vine-rail grind, rhythm lanes |
| 5 | **The Aurora** | an ice shelf at night under curtains of aurora | aurora ribbons from a sky shader (moving colour bands), ice with a glassy fresnel, stars | **Fenn the arctic fox** | **The Whiteout:** a snow storm to ride blind by sound | sled, slalom |
| 6 | **The Stratosphere** | the last fall: a skydive from the edge of space to the sea | a curved horizon, thin blue sky, city lights below, then clouds; reuses the STARGAZE flight | **Moth** (drawn to the light) | **Gravity:** none; the fall is the level | glider (STARGAZE) |

**Season 2 ending:** the Tidewater is not for the player, the Rail or WREN. It belongs to no one, and the last choice is to **leave it where it is**. (A different answer to the question of control, and a quiet one.)

---

## 5. Water, the stunning way (one shared system for every place with water)

Godot has no water, so this is new, but it follows the Godot method: **one ShaderMaterial per surface, everything in the shader, no render-to-texture**. That is what keeps it fast on a phone.

- **Shape:** a camera-following grid, vertex-displaced by three or four summed sines (Gerstner-like) so waves roll toward the shore and crests peak. Fewer vertices far away.
- **Colour:** deep and shallow colours mixed by *depth*, which is cheap to fake from a shore-distance value baked into the heightfield (`heightfield.js` already exists). Turquoise to deep blue, a darker outline where it meets the sand (the wet-sand line).
- **Sky in the water:** fresnel. At a low angle the water reflects the sky gradient and the sun disc (the same sky function the sky shader uses, so they match); looking down it is see-through.
- **Foam:** a white band where waves crest and along the shore, from noise scrolled with the wave; it breaks into lacy edges.
- **Caustics:** two layers of scrolling bright pattern on the sand and sunk objects in shallow water, in the ground shader (a cheap voronoi-like product of sines).
- **Glitter:** a sharp specular highlight from perturbed normals, so the sun sparkles.
- **Refraction (fake):** shallow ground colour is slightly offset in UV, so the sand wobbles.
- **Gameplay:** water uses Godot's `Zone.gd` `sticky` (slows) in shallows and `vent` or `slip` as the rule suits; a wave you can **ride** is a banked wall ride along the curl.
- **Budget:** one draw call per water surface, no extra render passes. If a phone drops under 60 fps the sines drop first, then the caustics, never the colour.

Every place with water (Tideline, Drowned City, Stormbelt, Aurora's sea, the Stratosphere's ocean) reuses this one material with different colours and wave numbers.

---

## 6. Characters

### The Rail's staff (looks and behaviours ported from `Roster.gd`, but they are **ride hazards, not enemies**)
The Godot cast is already a comic roster of silly-named characters with a primitive-shape builder (`Roster.build_visual`) and one AI script (`EnemyAI.gd`) with different behaviours. They are not fighters here and nothing is ever defeated: they are **chasers, blockers and set pieces you read and ride around** (the snowball rule: a clear telegraph, a cheaper way past). The hit points and damage numbers in Godot are ignored; only the look, the movement and the joke are used. Contact is a stumble, never a death. The slalom, snowball and rolling-hazard rules already in the game (RunRig 7704) are the template.

| Godot character | Role in Downfall | What it does on the slope |
|---|---|---|
| **Barry the Balloon** (8 hp, slow) | the **Chaperone**: a smiling balloon drone with a chime | floats ahead and politely closes a lane |
| **Mime Marcel** (70 hp, fast) | **the Silencer** | mimes an invisible wall across a lane |
| **Poof the Magician** | **the Redactor** | puffs a black bar over a pickup ("now you don't see it") |
| **Vacuum Vic** | **the Cleaner** | sucks colour and pickups toward him |
| **Big Brenda** (240 hp, tank) | **Assurance Officer** | slow, wide, blocks the road; ride around |
| **Sir Bounce-a-Lot** | **the Bouncer** | guards a gate ("you're not on the list") |
| **Kaboom Kevin** | a **de-escalation specialist** | hugs you, explosively (a gentle bump) |
| **Gerald the Banana**, **Tomato Tony** | **Comfort Belt staff** | slip hazards, throw food |
| **Dizzy Dan** | a **spinner** in the Hive | rotating obstacle |
| **Dave the Waddler** | **the Placid** | pleasantly in the way; "I'm fine" |
| **Honk the Goose** | **an Unlisted cameo**: the hero of the first game | a free companion, honks at the Rail |
| **Mama Quack and Duckling** | **an Unlisted family** | a duckling-chain you gather for a bonus; Tideline crowd |
| **THE BIG CHEESE** (700 hp, scale 2.4) | **boss of the Comfort Belt** | replaces the "Pastry Chef": the Rail's PR mascot |

### The Unlisted (companions)
Season 1: **Chuck** (marmot), **Bonbon** (sugar glider), **Mildred** (tortoise), **the Choir** (bats), **the Weaver** (spider), **Dolores** (flamingo), **Eight** (octopus). Season 2: **Clive** (hermit crab), **Sera** (manta), **Petra** (storm petrel), **Slo** (sloth), **Fenn** (arctic fox), **Moth**. Plus the cameo **Honk** and the duck family. Built with the `Roster.gd` primitive builder (balls, cylinders, boxes, capsules, tori) so they are cheap, charming and consistent with the molecule "ball-and-stick" look (`RunRig` 9433 THE KIT). **One active at a time**; each gives one gentle ability and one story job.

### The main cast
The Rider, the Rail, WREN, Ash Mercer, Dr. Orrin Vale, Pruitt: see the master plan.

---

## 7. Equipment (ported from Godot, made to suit a face-steered phone game)

Head steering has no aiming hand, so **nothing here needs precise aim and nothing here is a weapon**. The Godot items below are borrowed for their *movement* ideas (lift, hook, boost, burst) and renamed as ride gadgets; they open and clear the way and never harm anything. One big button, auto-assist, never required. Gear is passive and changes only the feel.

### Gadgets (one slot, one tap, a cooldown, never required)
| Gadget | Ported from | What it does |
|---|---|---|
| **Updraft Fan** | `LeafBlower.gd` (cone of wind; aimed at the ground it lifts you: "rocket jump / hover") | hold to hover over a gap or stretch a jump; pushes light hazards aside |
| **Grapple** | `PlungerGrapple.gd` (hooks a prop or the world; reels you) | tap: hooks the nearest pickup or rail anchor and reels you in; on world geometry it swings you |
| **Rocket** | `RocketLauncher.gd` (soft homing; alt: load up to 6 and fire a fan) | tap: a homing rocket pops a Chaperone or a hazard; hold to load a fan |
| **Jammer** | `ShockRifle.gd` (hitscan beam, aim-assisted; slow core; beam on core = shock combo) | tap: jams the nearest Chaperone (it stops closing lanes); combo wipes a row of redaction bars |

Gadgets are **earned in episodes 1 to 4** (one each) and swapped at campfires.

### Gear (3 slots, 5 rarities, silly suffixes, from `Loot.gd`)
- **Slots:** **Helmet** (was Hat), **Boots**, **Gloves**. Common to Legendary (1 to 4 stats; weights 60 / 26 / 10 / 3.5 / 0.5, multipliers 1.0 to 3.6).
- **Stats**, re-aimed at riding (keeping Godot's suffix jokes): **of Zoomies** (speed), **of Boing** (jump), **of Floating** (lower gravity, hang time), **of Butter** (slide speed), **of Soup** (stumble recovery, was regen), **of Padding** (less speed lost on a stumble), **of Luck** (chain bonus, was crit), **of Fortune** (better cut and gear drops), **of Learning** (stars grow faster), **of Greed** (more Glints), **of Gale** and **of Suction** (gadget power), **of Blast-Off** (rocket thrust).
- Examples: *Legendary Boots of Butter and Zoomies*; *Epic Helmet of Soup*.
- **Drops:** gates, bosses, Unlisted gifts, the campfire shop (for Glints). No pay-to-win: gear changes the *feel*, not the ability to finish.

### Skill tree (3 branches, from `Progression.gd`)
- **STYLE** (was Brawler): chains, tricks, speed. *Steel-Toed Boots* becomes *Sticky Landings*; capstone *Shockwave Boots* becomes **Shockwave Landing** (a big landing sends a wave that jams everything nearby).
- **GADGETS** (was Gadgeteer): *Turbo Fan*, *Industrial Suction*, *Funny Bone*; capstone **Yeet Cannon**.
- **GRIT** (was Survivor): stumble recovery, grace time. Never a hit-point wall: the gentle-stakes rule.
- One point per rank, prerequisites kept, as in Godot.

### Buffs (pickups on the slope; ported from `RunRig.gd` 3547 and `GAME_SPEC.md`)
Boost (burst of speed), Shield (absorbs a stumble), Multiplier (double points 10 s), Donut = Wings, Sugar = Magnet, plus the **Saw** (cuts tree hedges). Each lit and one at a time.

### Glints
The gold sparks of Godot's GLINTS system (RunRig 3914): a rail carries a spiral of them; a ramp leaves an arc; a stumble spills some. Currency for the campfire shop (cosmetics and gear only).

---

## 8. Surfaces, structures and toys (the list you asked for, mapped to Godot's `Zone.gd`)

The surfaces I brainstormed are, almost one for one, already written in Godot's `Zone.gd`. Port them once; every biome reuses them.

| Idea | `Zone.gd` kind | Where it appears |
|---|---|---|
| Ice patch | `slip` | Alpine, Aurora, Desert Highway |
| Mud, sand, goo, shallow water | `sticky` | Desert, Candy frosting, Tideline shallows |
| Boost strip | `boost` | everywhere |
| Trampolines, gumdrops, mushrooms | `bounce` | Candy, Canopy, Hive |
| Updraft column | `vent` | Desert, Stormbelt, Canopy |
| Lava | `lava` | Lava Tube, the Burn's lowlands |

Structures (ramps, kickers, vortex, spring-tube-rail, cavern, snowballs, gaze-orbs) come from `RunRig.gd` (8187 TOYS, 8564 linked set pieces, 8718 gaze orbs, 8821 cavern) and are **[partly built]**. New to port or build: half-pipe, loop-the-loop, wall rides, drawbridge and moving platforms, rolling boulders.

---

## 9. Effects (ported and new, ranked for phones)

All are **surface effects** (they live in the ground, trees, sky, mountains, water) except where marked; all sit behind knobs in the FX lab; all are checked at 60 fps before shipping.

**Ported (Godot source):** the picture pass `POST` modes (psychedelic, matrix, synthwave; breathing warp, 6 molecule effects, chroma split, tracers, bloom, rings, tube, onset), `SKYDOME_SHADER`, `MTNFX_SHADER` (mountain moiré), `FACEFX_SHADER`, `VEG_LIVE_SHADER` (swaying trees), `SHAFT_SHADER` (light shafts), `CAVE_SHADER`, ThemeFX sandstorm, astral echoes and chromatic carve trails, cel outlines and bands.

**New this session and planned:**
1. **Contour lines** on terrain **[built: Alpine, Candy, Egypt, Desert]**; add to mountains.
2. **Ink outline pass and velocity chroma** on every biome (the Godot `k_edge`, `k_cel`, `k_chroma`, driven by a `Speed_Normalized` 0..1).
3. **Moiré guardrails and fences** (two offset grids).
4. **Voronoi shatter** on a stumble, 0.3 s, no freeze.
5. **The Redaction layer** (black bars, mosaic blocks, `[PAUSED]` tags) as a *surface* pattern on objects, peeling with each Piece.
6. **Predicted You** ghost rider (a game mechanic, drawn as a translucent rider).
7. **Water** (see 5), **aurora** (a moving-colour sky band), **caustics**, **god-rays**, **bioluminescence** (emissive vertex colour that pulses with the music).
8. **Kaleidoscope fold** on the Mandala gate (a cheap UV fold in the post).
9. **Heat haze and mirage** in the Burn (a UV wobble in the ground and distant mountains).
10. **Radial slit-scan** = the existing tracer stack; kept in the psychedelic and tunnel worlds only.
11. **Non-Euclidean portals** and **SDF gates**: only for the finish arch and boss gates, as a single cheap gate each, not a general system.
Not planned: datamosh frame-bleed (needs an uncleared buffer; heavy and fragile on phones).

---

## 10. Bosses (one a different head-steering game each; ported where a Godot character exists)

Godot's `WaveDirector.gd` has **a boss every fifth wave** and `Roster` has `THE BIG CHEESE`; the rest are built the same way (a big primitive-shape character with a simple behaviour).

| Boss | Where | Head-steer game |
|---|---|---|
| The Backlog (snowball) | Cold Storage | slalom, outrun |
| **THE BIG CHEESE** | Comfort Belt | rhythm lanes (a conveyor of cakes) |
| Pruitt's Compliance Roller | the Burn | surf, wide arcs |
| The Signal Eater | the Underlay | rhythm, the beat that jams it |
| Moderator Prime | the Mirror | glider, shatter the face |
| Aria Sol | the Broadcast | rhythm lanes and balance |
| *(none)* | the Commons | the choice |
| The Tide | Tideline | surf the barrel |
| The Floodgate | Drowned City | timed gates |
| The Forecast | Stormbelt | glider, tornado |
| The Strangler Fig | Canopy | lane-snap |
| The Whiteout | Aurora | ride by sound |
| Gravity | Stratosphere | the fall itself |

---

## 11. What is built, and how to build the rest (efficient order, biggest payoff per hour first)

**Built:** the 7 biomes and their looks (grounds, trees, skies, the psychedelic frozen look), the journey and fades, the finish arch, the rocket, stars and certificate, head steering, contour lines, the start card.

**Phase 1: make the existing seven stunning and complete (the Godot port).**
1. Horizon landmarks and weather per biome (WORLDS_PLAN gaps): pyramids, candy hills, sandstorm, falling code, sprinkles, heat shimmer.
2. The two missing picture passes (matrix mode 2, synthwave mode 3).
3. **Surfaces** from `Zone.gd` (ice, sticky, boost, bounce, vent, lava) in every biome.
4. **Gates:** port `Realms.gd` (cheapest big win: 12 finished places).
5. The Beauty Standard checklist run over each biome with a screenshot at 924x412 and 375x812.

**Phase 2: the story and the cast (see the master plan).** Redaction layer, Predicted You, the Rail's voice, the Unlisted, the Rail staff from `Roster.gd`, bosses, cuts.

**Phase 3: equipment and progression.** Gear and the skill tree from `Loot.gd` and `Progression.gd`, the four gadgets, buffs, the campfire shop.

**Phase 4: Season 2 (The Thaw).** The shared water system first (it unlocks four places), then Tideline, Drowned City, Stormbelt, Canopy, Aurora, Stratosphere.

**Phase 5: the viral layer and launch** (master plan 8): Rail Rating, Daily, Clip it, weekly premieres.

**Reuse is the efficiency:** gates, surfaces, staff, gear and gadgets are all **already designed in Godot**. They cost porting time, not design time. Only the story layer, the Season 2 places, water and Predicted You are new.

---

## 12. Open decisions

1. **Season 2 now, or after Season 1 ships?** (I would ship Season 1 first; Season 2 is the sequel and the water showpiece.)
2. **The twelve gates:** all twelve, or the best six first (I would start with Glow Grotto, Crystal Vault, Interzone, Orchard of Eyes, Mandala Drop and the Melt)?
3. **Gear and skill tree:** gear only (a light version) or the tree too? Both come from the Godot brawler, so my recommendation is **gear only, and cut the tree** unless it earns its place in the ride.
4. **The Rail staff as hazards:** keep the Godot goofy names and comic style as is? (I think yes: it is the tone.)
5. **Honk the Goose** as a hidden cameo: yes?
6. **Season 2's "the one molecule nobody designed":** keep, or merge Season 2 into the Season 1 story?
