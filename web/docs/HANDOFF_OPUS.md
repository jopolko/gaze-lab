# HANDOFF TO OPUS: Downfall / Downhill (Babylon build)

Written 2026-11-24 by the Sonnet 5.5 session. Read this top to bottom first. Everything else is linked from here, and a copy of every key file is in `C:\Users\josh\projects\gaze-lab\web\handoff_opus\`.

## 0. Your job, in one paragraph
The owner (Joshua) is building a head-steered (left/right only, no button) driving game and wants it **AAA-quality and release-ready**, built with AI in weeks, not years. He decides *taste*; you own *craft and coverage*. He is tired of finding broken things by playing. Do three things, in order: (1) **fix the two live bugs in section 5**, (2) **audit the whole game as a first-time player** and produce one ranked gap list (questions in section 8), (3) **resolve what you can** and report plainly. Do not ask him questions you can answer from this file. He has said repeatedly: proceed without asking, follow best practices, and give *full URLs*.

## 1. The owner and how to work with him
- Short replies, one step at a time. He loses the thread in long messages. One open-items list.
- **Give full URLs** he can paste into notes, every time.
- Honest reporting: say what you verified and what you did not. He has been burned by "it loads" being reported as "it works".
- Never contact anyone on his behalf; never change real users' settings or caps. Prod is open to changes (backup first).
- He reads the game on a phone, head-tracking, in landscape. The in-app test browser here runs 1-7 fps, so feel/speed cannot be judged from it.
- **Hard rules from him:** no scrolling menus; light readable UI, big fonts; no pink; yellow/gold only if badass; touch-first; options must directly affect play and be visible *before* choosing; four fun options beat a dozen that don't matter; satire and mirth in copy; the world must be the same for every player (no single-out hazards); penalties are a stumble, never a stop; psychedelic effects live in surfaces, never overlays; the psychedelic look is **frozen**.
- Tone: neon-noir keep for the *look of attention beats*; keep Borderlands only for driving, humour, atmosphere. Plain words. Story is optional to follow.

## 2. His words, verbatim (this stretch; the decisions come from these)
- "I want a killer loadout meaning weapons or shields, maybe tools... I'd rather 4 fun options that make the game worth playing again than a dozen that don't really matter... stupid shit like weapons tools and we can make mirth with satirical descriptions and points systems."
- "Whatever you need to do to resolve the scoring system so it's fun and addictive dopamine and there are clear indicators to players that they need or can or cannot use certain elements. The player who's suited should somehow see that an element is theirs and the others should see it's not meant for them."
- "can we balance that in all directions for all players? i feel like rocks to slam into or trees to cut or whatever could advantage the users with those buffs"
- "There has to be another way to display this to the player... I'd rather display the minimum of data possible as reading."
- "I'd like how you handle the story elements too... I want this done with the eye and taste of a AAA game director and acclaimed movie and movie critic. That means scenes, story telling, shit placement, everything."
- "I would suggest start black, then the murmur message appears and lingers, fades, lights come on, you're driving, a few seconds to take in the scene, the next message onscreen, fades, etc."
- "I want masks so no face so no skin color... could it be funny to have the characters all faceless, masked in these dramatic story poses and actions?" (Decided: yes. Faceless, masked.)
- "I really want these messages to get their due attention. Like almost fade to black to let them sink in."
- "i like the murmur messages and a map in the style of gta v... always rotating live with your movement and the phone would ring and display messages."
- "can you resolve all gaps, reconcile scoring, bonuses, hazards, character types, storyline, elements, powerups, supercharge, dopamine potential (hey maybe there should be a dopamine mode or boost, we're already half-way there with molecules)."
- Latest: "The road is still full of objects. A boulder just fucking hit me and messages are still popping up on top of the score or whatever it is."

## 3. The game and where everything is
- **Build:** `C:\Users\josh\projects\gaze-lab\web\babylon\` (Babylon.js 7). `index.html` is one module script (CRLF line endings; some of my inserted lines are LF, harmless). Character editor: `dressup.html` (LF). Gear text/stat nudges: `charfx.js`. Balance sim: `tools/gear_sim.mjs`. **Smoke test: `tools/smoke.mjs`** (22 checks). Stills renderer: `tools/stills.mjs`.
- **Live (VPS `nowservingto`, web root `/var/www/html/gaze-lab/three/babylon/`):**
  - Game: https://joshuaopolko.com/gaze-lab/three/babylon/index.html
  - Route Zero (story level): https://joshuaopolko.com/gaze-lab/three/babylon/index.html?story=1&nointake=1
  - Tutorial: https://joshuaopolko.com/gaze-lab/three/babylon/index.html?tutorial=1&nointake=1
  - Character editor (+ story reel): https://joshuaopolko.com/gaze-lab/three/babylon/dressup.html
  - Editor with a gear open: `dressup.html?gear=rocket|pole|shield|bull`
- **Private artifacts:** Storyboard https://claude.ai/artifact/8qwFTSrJMaebP5SR4DcqAQ ; Stills https://claude.ai/artifact/LbF29gZUVMT5dqnV4VmooC
- **Other builds (do not mix in):** Godot web builds `/gaze-lab/godot/`, `/godot-dev/` (the owner's pick-tool dumps come from Godot); original three.js `downhill-three/`; STARGAZE `stargaze/`; parked "crossing" game (deleted). The Babylon build is the target.
- **Deploy:** copy `index.html` to the VPS `/tmp`, then `sed "s#'../downhill-three/sfxset.js'#'./sfxset.js'#"` into `/var/www/html/gaze-lab/three/babylon/index.html` (the deployed file must import `./sfxset.js`). `dressup.html` is copied as is. Check syntax first: extract the module script to `_chk.mjs` and run `node --check`. Back up to `index_pre*_backup.html` before big edits.
- **Safe patching:** write patch scripts with the Write tool (not bash heredocs: quotes get mangled), assert exact match counts, keep CRLF in `index.html`.

## 4. Decisions made (the design as it stands)
Full detail is in `RECONCILED_DESIGN.md`. Short form:
1. **Four gears** replace stats: Rocket (auto-fires at drones/mines, owns gold drones), Magnet Pole (hauls drones/mines/crates), Shield (soaks 3 hits), Bull Bar (ploughs boulders/mines). All numbers in `GCFG`; each lands within ~30% of the others across novice/middle/expert (simulator).
2. **Scoring:** every gain x gear streak multiplier x **3 during RUSH**. Hit = streak resets.
3. **RUSH (dopamine meter, new):** right-edge bar; chains/pickups/pads/molecules/gear hits fill it; a hit drains .15; full = 9 s of x3 points, boost, hits become +250 smashes, full trip look. Same meter is the planned "supercharge" for the strike level.
4. **Shared hazard world:** drones (air), mines (ground), boulders; one every 150-250 m; gears answer differently. Lanes of prizes: gold beam = yours, grey padlock = someone else's.
5. **Messages:** one voice at a time (`stQ`/`stDir`), 2.5 s gap, objective line only in gaps. **Attention beats** (new, noir): world drops to near-black/grey, one line held like a title card, colour returns. **Route Zero has four beats:** Murmur, sign 1, sign 2, bonus-road lanes. Everything else is wordless/logged. Budget for the whole game: ~3 beats and ~10 s of text per level.
6. **Distances:** at ~50 m/s a message needs ~450 m of road. Route Zero is re-spaced: crystal 1 at -900, sign 1 at -1330, crystal 2 at -1700, tunnel -1750..-2200, bonus road -2280..-2635.
7. **Characters are faceless and masked.** Body acts; masks have tricks (eye shape, tilt, glow, smile curve). Looks (hats, masks, paint) are cosmetic only; gear is the only mechanical choice.
8. **Tutorial** exists (`?tutorial=1`, ~45 s, rockets for all, real pads/pickups, meter starts at .35, six one-line tips, READY card).
9. **Planned, not built:** live rotating route map (GTA-style); phone-ring Murmur (auto-answer, no button); strike level (supercharge -> hyper-psychedelic auto-aimed rocket strikes, three clean strikes win; gear tier II as reward); saw/hedge; remaining molecule senses; graphic novel (storyboard -> panels; art from Claude/Gemini).
10. **Canon:** `DOWNFALL_STORY_WORLD_BIBLE_V3` for the Babylon build. The Badlands/crossing line (Arbiter, Runner, mutators) is separate and parked.

## 5. LIVE BUGS TO FIX FIRST (reported by the owner, not yet fixed)
1. **"The road is still full of objects. A boulder just hit me."** I verified (via `__G.OG` and the zones map) that in `?story=1` the stretch z 0 to -2340 has no obstacles within 9 m of the road centre and no spring arcs, and hazards only exist on the bonus road. **So either (a) he was not on `?story=1`** (the editor's Drive button may link to plain `index.html`, where hazards spawn everywhere from the start, see `gearWin` and `GEAR` hazard pool), **or (b) a hazard/boulder source I did not clear is still active.** Check: the editor's `next`/Drive link; `gearPlace`/`gearWin`; the gear hazard pool (`q.kind==='rock'` boulders at `PH.hurt` collision, ~line 1840); the obstacle grid (`OG`); the natural rocks added by `zoneRow`. Reproduce with a headless run that drives the real course and logs every crash (`crash()` calls) with z and kind.
2. **"Messages are still popping up on top of the score."** The score strip is `#gearHud` (top centre, z-index 30). On top of it can appear: `gpop` popups (gear points, `RUSH`, `SMASHED`), the objective pill `#stObj` (moved to top 96 px), the banner `#stSignB` (top 10 px, z-index 40, used by the tutorial and hint button), and the beat overlay. Decide one rule: **nothing may overlap the score**. Move the score to a fixed, reserved strip and put all transient text elsewhere, or hide the score during any message. Use `web/tools/layout_check.mjs` (hud mode) plus screenshots; add a smoke check for overlap.
Also confirm which URL he actually plays; he said he tests "first level". Give him links with `?story=1&nointake=1`.

## 6. Known gaps (ranked; from RECONCILED_DESIGN section 3)
Blocks release: not driven on a phone with real head steering; sound unverified (audio may stay locked until a tap); remaining molecule senses/trip arc incomplete (no comedown); content repeats (no variety pools); white "blob" in the tunnel (shield-buff halo, re-check after the re-layout).
Hurts: saw/magnet/wings trigger rules not built; gear numbers are simulator-balanced not play-balanced; RUSH economy untested (may be too easy); lane/prize end card untested by driving; accessibility (RUSH forces full trip + beat pulse; must stay under 3 flashes/s; no reduce-effects switch); camera-free fallback.
Polish: phone-ring Murmur; live map; gear shown on the car; fifth (jump) gear; public naming (`gaze-lab`/Godot paths); music licences are non-commercial (see memory note).
**Pacing risk I found:** the storyboard cut spends ~50% of Route Zero's time on text; the beat budget (above) fixes it but only four beats are implemented.

## 7. How to verify (do this every time)
- `node web/babylon/tools/smoke.mjs` (headless Chrome, 22 checks: items work, RUSH x3, never two messages at once, no script errors, tutorial, story reel, no slalom/obstacle rows or spring arcs in Route Zero's reading stretch). It must print ALL PASSED. **Add a check for every bug you fix.** The test caught a real bug (RUSH only tripled points with a gear) the first time it ran.
- `node web/babylon/tools/gear_sim.mjs` for balance. `node web/babylon/tools/stills.mjs` regenerates the story stills. `web/tools/layout_check.mjs` for overlays.
- The in-app browser pane is tiny and slow; use headless Chrome (CDP, as in `smoke.mjs`) for anything about layout or timing.

## 8. Questions for the audit
1. Walk tutorial -> Route Zero -> end card as a first-time player. List every confusing, empty, busy or off-vision moment, ranked by release risk.
2. Economy: can RUSH be farmed or ignored? Does it make gears meaningless? Extend `gear_sim.mjs` with the meter and recommend numbers.
3. Reconcile gear streak, RUSH and GAME_SPEC depth/TTT into one player-facing story: "what do I do to score better?"
4. Decide the first-hour structure (tutorial, Route Zero, then what), using GAME_SPEC sections 2-4 and the Bible's gates/biomes.
5. Design the strike level on the meter and the remaining molecules as senses.
6. Implement the live map and the phone-ring Murmur if time allows; storyboard's frames are the cue sheet for the opening (black, Murmur, lights, title, breathe).
7. Extend `smoke.mjs` to cover everything you touch.

## 9. Files and where to read them (all copied into `web/handoff_opus/`)
| File | Why |
|---|---|
| `HANDOFF_OPUS.md` | this file |
| `RECONCILED_DESIGN.md` | current systems, decisions, gap list, review questions |
| `DOWNFALL_STORY_WORLD_BIBLE_V3.md` / `.docx` | story and world canon for the Babylon build (sections 6.12-6.14 cover gear, scoring, lanes) |
| `DOWNFALL_CURRENT_VERSION.md` | the *Badlands/crossing* line, parked; read to avoid mixing it in |
| `GAME_SPEC.md` | the original full game spec: trip arc, six chapters, buffs, slalom core, phrase grammar (sections 2-4, 17-19 matter most) |
| `DOWNFALL_MASTER_PLAN.md`, `DOWNFALL_README.md` | the pitch, the fall line, modes; README says which doc wins |
| `DOWNHILL_TRIP.md` | the seven-world trip composer notes |
| `storyboard.html`, `stills.html`, `stills/*.jpg` | the 17-frame Route Zero storyboard (open in a browser) and 14 rendered stills |
| `memory_snapshot/` | the owner's persistent preferences and project notes (index `MEMORY.md`) |
**His "original doc":** I could not tell which single file you mean by the owner's *original* brief. The earliest statements of the vision are `DOWNFALL_MASTER_PLAN.md`, `GAME_SPEC.md` (section 0-2) and the psychedelic VR effects page referenced in GAME_SPEC section 15. If he has another file, he will point you to it.

## 10. State of the working tree
Uncommitted work (the folder is not a git repo). Backups: `index_pre*_backup.html`, `dressup_pre*_backup.html` in `web/babylon/`. Latest deployed: `index.html` (beats, RUSH, tutorial, clear stretch, queue), `dressup.html` (reel, still mode). Nothing is half-edited.
