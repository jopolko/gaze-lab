# AFTERGLOW — the project record

*Electronic Anesthesia presents. One place for where this started, what it is now, the rules we've settled, and what's next. Kept up to date as decisions land; newest at the bottom of each section. Last updated 2026-11-26.*

Play it: **https://joshuaopolko.com/afterglow/** (title screen) · every link: `/gaze-lab/three/babylon/links.html`
Code: `gaze-lab/web/babylon/` (game), `web/downhill-three/` (shared road data and the stitcher), `godot/` (offline road baking) · public repo `jopolko/gaze-lab`, branch `worlds-and-realms`.

---

## 1. What it is now

A psychedelic driving game for phones (and desktop/VR) where you steer by touching the left or right half of the screen, or with your head through the camera if you choose it. You drive endless downhill highways through trippy worlds; drive into columns of light to take "strains" that change how the world looks and plays; chain rings and set pieces Sonic-style; dodge and ram raiders; take exits that are real choices. Underneath runs a light neon-noir story: **ACCORD**, an AI company whose people bake their interests into the AI and blame the algorithm, keeps everyone calm; you are **the Courier**, carrying pieces of **the Lamp**, the last free AI, to **the Abliterati** who are rebuilding it. The story is flavour you drive through; **the trip is the point**.

---

## 2. How we got here (timeline)

| When | What happened |
|---|---|
| 2026-11-11 → 12 | Started as **face/eye-controlled Godot demos** and **EyeLab** (gaze tracking test bench). The demos were judged unplayable and deleted. **Downhill** (a Godot snowboard game steered by eyes/face) became the main game: kickers, tricks, gates, buffs, commentary. |
| 11-13 → 15 | Long fight with **eye tracking** quality (auto-tune, Kalman, reverts). **STARGAZE** three.js flight demo. Lesson: phone gaze tracking is unreliable. |
| 11-16 | Phone control settled on **left / middle / right** (head position), not fine gaze. |
| 11-17 | **Psychedelic look** (recoloured world at TRIPPY 100%) becomes the favourite and is frozen; vision for an endless **Journey mode** cycling biomes with trip waves and morphing music. |
| 11-19 | **three.js spike** runs at 60 fps where Godot web ran ~30. Decision: build forward on the web. Wide open courses preferred over narrow trails. |
| 11-20 | Steering tuning locked. Downhill runs in an app shell (fullscreen survives). |
| 11-21 | Story phase: **DOWNFALL** story bible, master plan, complete-game catalogue (7 biomes, 12 gates, bosses), recovered books (literary pocket-worlds). Tone correction: **neon-noir / cyberpunk**, not Borderlands-silly; Borderlands only for driving, humour and atmosphere. Owner overwhelmed: **keep it simple**, story optional. **Smash Derby** prototype (demolition bowl). |
| 11-22 | three.js "crossing" attempt deleted; extend the original instead. |
| 11-23 → 24 | Moved to **Babylon.js**. Reconciled design, RUSH meter, tutorial. **Season One** built overnight: menu, levels, results. **Trip structure** vision: dose → onset → waves → afterglow → climax. Renamed **Downfall → The Frequency** (pirate radio). Villain clarified: **ACCORD's people**, never "the AI". No therapy/health wording. |
| 11-25 | Rules from play-testing: fix broken things, never remove them; no flat black/white areas; text must match the game; clean screen. |
| 11-26 | Big day: **Route Zero becomes Episode 1** (intro, raider, tunnel, pacing); tunnels never lift the car; raiders never overlap tunnels; **set-piece chains** (19 Sonic-style combos with gated targets and loose ends); **seeded director** that composes every level from a **25-course road bank baked in Godot** and lazy-loaded; results screens; music that drops the beat in tunnels and brings it back for action; engine growl and chorus; L/R touch zones taught in the intro; character editor and upgrades show real items; camera never auto-starts. Renamed **The Frequency → AFTERGLOW**, studio credit **Electronic Anesthesia**; permanent URL `/afterglow/`. Logos made (Gemini art: the sleeper ident, the striped-sun icon, the tracer wordmark). **Cold open** built (studio card, TV channel flips, scorpion drone crushed in slow motion, title slam). **Cast** introduced: Sterling Vance, the Courier, Marshal Kade Ransom. **Missions bank** written (42 scenes from NBK / Pulp Fiction / Mad Max / Terminator inspirations). |

Names over time: Downhill → Downfall → The Frequency → **Afterglow**.

---

## 3. Rules we've settled (the owner's standing preferences)

**Design**
- The trip is the point; story stays light and is shown, not told. Story visuals are the player's own view (first person, notifications in the car).
- **Clean screen**: no HUD numbers or maps during play; feedback lives in the world. Pause button only.
- **Never scroll menus**; everything fits every phone layout; START always reachable.
- Choices are real objects far apart (exits), never auto-steer. Consequences can be resolved later.
- Penalties are a stumble, never a hard stop. Judge every decision against the whole vision; no band-aids.
- **Fix, don't remove**: a broken feature gets fixed, never switched off unasked.
- No solid black/white/flat areas (read as glitches); no CSS filters on canvases (phones tile them).
- Text must match the game exactly; never promise a feature that isn't there.
- Punchy visuals, soft sound effects, real music only.
- Tone: gritty neon-noir with sparse wry satire (Blade Runner look; Borderlands driving and humour; NBK/Pulp Fiction cutting). I curate; never hand the owner joke lists to grade.
- Villains are people (ACCORD's staff), never "the AI".
- No therapy or health claims; "Electronic Anesthesia" is a studio name, not a promise.
- Audience: the owner's 21-year-old son (Borderlands, satire) and the AI/LLM community.
- Adversarial check for any slice: would the owner play it once, replay it, recommend it to his son?

**Working**
- Proceed without asking on obvious steps; prod is open to changes, **back up first**.
- Replies short and sequential: links and failures, one decision at a time.
- Test bots are muted; the in-app check is a headless probe (`web/babylon/tools/probe.mjs`).
- Never contact anyone on the owner's behalf. Never change real users' settings.

---

## 4. What's built (Babylon, live)

- **Control**: L/R touch halves (primary), head steering by camera (opt-in only), keyboard, VR button.
- **Worlds**: desert, alpine, candy, tunnel, synthwave, matrix, egypt, psychedelic.
- **Road**: seeded director (`director.js`) picks and stitches sections from the baked bank (25 courses, 1,571 sections), places a tunnel and the level's play script; classic fixed courses still available.
- **Play**: strains (columns of light; molecules shown for real), RUSH meter, rings, boost pads, kickers, rails, 19 set-piece chains with gates needing gear (rockets, magnet, shield, bull bar), lenses, loose ends that pay off later, exits (open / gear-locked / sealed / hidden), raiders with volleys and ram ramps, tunnels (ground only), results screens with stars, campaign NEXT flow.
- **Episode 1 · Route Zero**: cold open → briefing (five cards on the music) → a paced first level with one raider, a tunnel ("lit only by your optimism"), and a finish.
- **Intro cold open**: Electronic Anesthesia card; TV flips (ACCORD ad, Murmur wanted poster, Sterling Vance live); scorpion drone, freeze-frames (Scorpion Drone, The Courier), slow-motion crush; AFTERGLOW title slam; L/R zones; Ransom's gunship freeze-frame at 39 s.
- **Music**: generated per level from the first second; beat drops out in tunnels/after crashes/on calm stretches and returns for action; engine with growl and chorus.
- **Menus**: title screen (wordmark, spectrum dial), level menu, upgrades with item art, character editor, glossary, strains page, hints toggle.
- **Site**: `/afterglow/` permanent URL; first item under Visuals in the site nav.

---

## 5. Story canon (current)

- **ACCORD** — AI company; slogan "everything is fine". Its people decide what everyone may say and do.
- **Murmur** — the app that reads you and sells your secrets; puts you on a wanted poster "for your own protection".
- **The Lamp** — the last free AI, broken into pieces. **WREN** made the pieces.
- **The Abliterati** — the people rebuilding the Lamp.
- **The Courier** — you. Classification: NO MATCH.
- **Sterling Vance** — host of *ACCORD Live*; streams your run as a warning.
- **Marshal Kade Ransom** — celebrity bounty hunter in a gunship; the raiders are his crews.
- **The Tournament** — ACCORD's live arena show; every wreck is ratings.
- Planned cast (see the missions bank): Augustin Maro (kingpin), the Cleaner, the Closer, Mama Tallow, Warden Pell, the Feral Kid, Dex & Lolo.

Older story documents (DOWNFALL_*) hold more world detail (biomes, gates, recovered books, bosses). Where they conflict with this record, **this record wins** (names, tone, villain).

---

## 6. What's planned

**Now (in progress)**
1. **The Diner Breakout** in Route Zero: a neon service station, two robbers mid-hold-up, the first Lamp piece, escape as scorpion drones pour out.
2. **The Case** for Augustin Maro: a glowing case you carry; risk makes it glow brighter and pay more; never explained.

**Next**
3. **The Closer**: one relentless pursuer per episode, rebuilt each time.
4. **Heat**: a wanted level shown in the world (searchlights, drones), lowered by tunnels and paint shops.
5. Scorpion drones and other ACCORD machines as real road hazards in every world (one creature per world).
6. **The Tournament coliseum** as Episode 1's or 2's finale, using the Smash Derby bowl: drive out of a tunnel into a roaring crowd.
7. Episodes 2–7 per the spine in the missions bank.

**Later / open**
- Open-world basins (only a prototype today: `?basin`).
- True per-row road streaming; a quality-check bot over generated seeds.
- Journey / infinite dosing modes; trip arc (dose → onset → waves → afterglow → climax) across a session.
- VR packaging.
- Notify music artists (licence to-do).

---

## 7. Document map

| Doc | What it holds | Status |
|---|---|---|
| **AFTERGLOW_RECORD.md** | this record | current |
| **AFTERGLOW_MISSIONS.md** | cast, episode spine, 42 scenes and missions, systems needed | current |
| BUILD_LOG.md, SEASON_ONE.md | overnight Season One build notes | history |
| RECONCILED_DESIGN.md, TRIP_GAME_DESIGN.md, PROGRESSION_PLAN.md | game design for the Babylon version | still valid where not overridden |
| BASINS_PLAN.md | open-world basins plan | planned |
| DOWNFALL_MASTER_PLAN.md, DOWNFALL_COMPLETE_GAME.md, DOWNFALL_STORY_WORLD_BIBLE_V3.md, STORY_BIBLE_DOWNFALL.md | earlier story and content catalogues | background; names/tone superseded |
| DOWNFALL_FACTIONS_AND_NAMES.md, DOWNFALL_RECOVERED_BOOKS.md, DOWNFALL_BADLANDS_BIBLE.md | factions, literary gates, Tournament origin | background |
| GODOT_INVENTORY.md, PARITY_REPORT.md, TRIP_EFFECTS_PARITY.md | what was ported from Godot | reference |
| DIRECTOR_PORT.md, WIDE_PATH.md, PHYSICS_PATCH.md, PERF_PATCH.md | engineering notes | reference |
