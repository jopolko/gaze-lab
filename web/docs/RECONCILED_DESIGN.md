# DOWNFALL / Downhill (Babylon build): reconciled design and gap list

Written 2026-11-24. This is the one document that says what the Babylon game is *now*. Older docs (Badlands bible, crossing, Master Plan, GAME_SPEC) are inputs, not authority. Where they disagree with this file, this file wins until the owner says otherwise.

Build: `web/babylon/index.html` (Babylon.js 7, single module script). Live: https://joshuaopolko.com/gaze-lab/three/babylon/index.html
Test: `node web/babylon/tools/smoke.mjs` (17 checks, must print ALL PASSED before any deploy), `node web/babylon/tools/gear_sim.mjs` (gear balance).

---

## 1. What the game is (the owner's pillars)
1. Phone-first, **head steers left/right only**, no button, no up/down. Agency over assist.
2. A relaxing, easy, Sonic-like momentum run that gets **trippier** as you do well. A stumble is never a stop.
3. **Four fun gears**, not a dozen stats: each changes how you play and what you can win.
4. **Same world for everyone**: no hazard exists for one player only. Gears answer the same hazards differently; prizes show clearly whether they are *yours* or *someone else's* (gold beam vs grey padlock).
5. **Minimum text.** One message at a time, in one style, top centre. Teach by doing.
6. Satire and mirth in the copy; light, readable, big UI; no pink; no scrolling menus.
7. Real music, soft sound effects.
8. Psychedelic look (recoloured world at full trip) is loved and frozen: effects live in surfaces, never overlays.

## 2. The reconciled systems

### 2.1 Points, streak, RUSH (one economy)
- Every positive score gain is multiplied by **M = gear streak multiplier** (clamp(floor + streak, floor, cap); resets on a real hit; decays when idle) **times 3 while RUSH is on**.
- Gear events (rocket kill, haul, shield soak, bull smash) raise the streak and pay fixed points (`GCFG` in index.html, balanced by `tools/gear_sim.mjs`: novice/middle/expert land within about 30% of each other across gears).
- The score hook is installed for everyone (gear or no gear).

### 2.2 The dopamine meter (new, `DOP`)
- A thin vertical bar on the right edge. **Everything good fills it**: chain hit +.02, orb +.012, pad +.06, buff +.07, gear event +.08, molecule/SEE +.12. Doubled in the tutorial.
- A real hit drains .15. It also bleeds slowly if nothing good happens for 6 s.
- **Full = RUSH (9 s):** points x3, boosted, hits become SMASHES (+250 each instead of a stumble), trip forced to full, beat pulse, bar glows gold; then it empties and starts again.
- It is deliberately the same thing as the "supercharge" in the planned strike level (see 2.8): the meter is the one resource, RUSH is one way to spend it.
- Relation to the molecule trip: molecules and chains still raise `U.trip` (the look). The meter is the *rule* layer on top: trip is how it looks, meter is what it does.

### 2.3 Gears (4)
Rocket (auto-fires at drones/mines; owns gold drones), Magnet Pole (hauls drones/mines/crates; owns crates), Shield (soaks 3 hits; owns the chest), Bull Bar (ploughs boulders/mines; owns the chest). Numbers in `GCFG`; text in `charfx.js` `TXT`; editor in `dressup.html` (Looks vs Loadout). `?gear=X` opens the editor on that gear. Gear stat nudges (`FXS`: speed/grip/safety) are small leftovers; only speed and grip are used by `mech`.

### 2.4 Hazards (one shared world)
Pool of 7 slots, spacing 150-250 m, a third each: ad drones (air), mines (ground, jumpable), boulders (ground). Gear answers: rocket deletes drones+mines; pole hauls drones+mines; shield soaks any; bull ploughs boulders+mines. Rocks are never rocket/pole targets. In Route Zero hazards exist only on the bonus road (z -2260 to -2635) so they never compete with a message.

### 2.5 Powerups
Bank (cap 2 each, spent automatically when the need is real): shield, saw (not built), magnet, wings. Boost is automatic on pads and boost pickups. Springs (jump pads) are the natural-ground ramps. No held-slot, no gesture.

### 2.6 Character types
Intake form sets rating/cope/alias (story flavour + SEE duration: model 34 s ... enemy 14 s; doom +15%, denial -15%). **Gear is the only mechanical choice.** Looks (hats, masks, paint) are cosmetic only. Rule: any new "type" must change play visibly and be showable before choosing, or it is cut.

### 2.7 Messages (one voice)
All text goes through the director (`stQ`, `stDir`, `stBannerNow`): one card at a time, 2.5 s quiet gap after each, objective line only in gaps, user-requested hints jump the queue. Distances matter: at ~50 m/s a message needs ~450 m of road (6.5 s + 2.5 s gap), so Route Zero beats are spaced accordingly (crystal -900, sign -1330, tunnel -1750, bonus road -2280). Rule for new content: place beats by distance, not time, and never put a hazard or a second beat inside a message window.

### 2.8 Story and levels
- **Tutorial** (`?tutorial=1`, ~45 s): pure driving. Everyone gets rockets, real pads/pickups, the meter starts at .35 so a RUSH happens, six one-line tips shown once, a READY card with "Play Route Zero".
- **Route Zero** (`?story=1`): the story level (Murmur notice, SEE crystals, dark tunnel, lamp, then the bonus road: one prize lane per gear plus a skill-only high ring). A few real items sit in the quiet gaps.
- **Planned: the strike level** (not started): supercharge meter (this DOP) -> full-screen hyper-psychedelic strike mode; a huge target; auto-sweeping reticle nudged by head lean; dwell ~0.4 s auto-fires; three clean strikes win; rewards tier-II gear (rocket salvo, longer pole, 4th shield charge, bull wedge).
- Canon for the Babylon build is `DOWNFALL_STORY_WORLD_BIBLE_V3`. The Badlands/crossing line (Arbiter, Runner, mutators, three.js crossing) is a separate, parked build and is not to be mixed in.

## 3. Gap list (status as of this file)

### Fixed this session
- Tunnel unreadable (black road, mountains) -> dim-blue tunnel with exposure floor.
- Overlapping messages, three styles -> one card, one queue, one place; roadside tunnel plates removed.
- Beats physically too close for the speed -> Route Zero re-spaced.
- HUD: unlabelled score, long gear strip, strip/objective overlap -> labelled SCORE, short gear line, objective moved below.
- Items "do nothing": spring and boost code verified working; Route Zero had almost none -> real items added in quiet gaps; tutorial added.
- RUSH tripling only worked with a gear -> fixed (found by the new smoke test).
- Regressions had no net -> `tools/smoke.mjs`.

### Open: blocks release
1. **Not driven on a phone with a real head.** Feel, difficulty, speed and readability are untested; the test browser runs 1-7 fps.
2. **Sound is unverified.** Pickup/pad/rush sounds not checked on a real device; audio may stay locked until a tap.
3. **White blob** in the tunnel (shield-buff halo, unshaded cyan quad near z -501 in the OLD layout; layout moved, re-check).
4. **Molecules/senses beyond SEE** are not in the Babylon game (spec lists six); the trip arc (baseline to peak to comedown) is only partly there (trip rises with chains; RUSH peaks it; no comedown phase).
5. **Content repeats**: phrase deck exists but no variety pools; one hour would feel repetitive.

### Open: hurts the experience
6. Saw/hedge and magnet/wings trigger rules not built or tuned.
7. Gear numbers are simulator-balanced, not play-balanced; real `dl_gearlast`/`dl_gearbest` data needed.
8. Hazard density outside Route Zero not tuned against RUSH (a RUSH may be too easy/frequent: fills in about 12-15 events).
9. Lane/prize end card untested by driving; "BIG PRIZE" ring (course data at z -406) falls inside the first notice.
10. Accessibility: no reduce-effects switch or photosensitivity warning although RUSH forces full trip and a beat pulse (must stay under 3 flashes/s; verify).
11. No camera-free fallback guarantee; calibration step not reviewed.

### Open: polish
12. Optional phone-ring Murmur (GTA-style): ring then auto-show, no stopping.
13. Live rotating route map (GTA-style): data exists (trailx centreline, item lists, heading); not built.
14. Show gear on the car; jump/pogo gear as a fifth; rename `gaze-lab`/Godot paths (public naming).
15. Music licences are non-commercial (see memory note); credits and artist notification pending.

## 4. What to ask the next reviewer (Opus / Fable)
1. Walk the game as a first-time player: tutorial -> Route Zero -> end card. List every moment that is confusing, empty, too busy or off-vision. Rank by release risk.
2. Check the economy: can RUSH be farmed or ignored? Does it make gears less meaningful? Is x3 + invulnerability too strong? Suggest numbers and a way to test (extend `gear_sim.mjs` with the meter).
3. Reconcile the three scoring ideas (gear streak, RUSH, GAME_SPEC depth/TTT grades) into one clear player-facing story: "what do I do to get a better score?"
4. Decide the first-hour structure: tutorial, Route Zero, then what? Use `GAME_SPEC.md` sections 2-4 (trip arc, chapters) and `DOWNFALL_STORY_WORLD_BIBLE_V3` (gates, biomes) as inputs.
5. Design the strike level on top of the meter (2.8) and the remaining molecules as senses.
6. Extend `smoke.mjs` with whatever the audit shows can break.

## 5. How to work on this safely
- Edit `index.html` with CRLF kept; back up to `index_pre*_backup.html` first; check syntax with `node --check _chk.mjs` (extract the module script).
- Deploy: `sed` the sfxset import (`'../downhill-three/sfxset.js'` -> `'./sfxset.js'`) into `/tmp/i.html`, then copy to `/var/www/html/gaze-lab/three/babylon/index.html` on `nowservingto`.
- Always run `tools/smoke.mjs` after a deploy; add a check for anything new.
- Give the owner full URLs. Keep replies short, one decision at a time; the owner decides taste, the builder owns craft and coverage.
