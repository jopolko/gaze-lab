# Downhill: the full game spec (v1, 2026-11-19)

One document, top to bottom, so nothing gets bolted on later. Where a decision wasn't made yet I've written a default and marked it **[default]**. Change a default here before building.

Companion: DESIGN_PROGRESSION.md (the data counts and the first ideas).

---

## 0. One sentence

You ride a slope toward six shining molecules. Each catch adds a layer to your trip, and the game is the fastest, most stylish way of getting all six and arriving at the peak.

Controls: your own head steers (left / middle / right). Phone-first. No death.

---

## 1. Vocabulary (the ontology)

| Thing | What it is |
|---|---|
| **Trip** | one play session from sober start to comedown. About 60 min for a full one, but can end at any campfire. |
| **Chapter** | a part of the trip, about 8-10 min, ending at a campfire. Six chapters, one per molecule. |
| **Descent** | one run down a course (3-4 min). A chapter is 2-3 descents. |
| **Course** | a stretch of mountain (7.7 km or 11.3 km). Five exist. |
| **Segment** | a 300-900 m piece of a course with a job (see 4). |
| **Site** | where one molecule sits, with its approach. |
| **Molecule** | one of six. Catching one adds its **layer**. |
| **Layer** | a stackable change to the world (colour, pattern, time, sound, space, mind). |
| **Depth** | 1-3: how well you caught it. Scales the layer. |
| **Route piece** | ramp, rail, pad, slingshot, gate, hedge (tree barrier). The jungle gym. |
| **Buff** | boost, saw, wings, magnet. Timed or counted effects on the player. |
| **Loadout** | the one buff you're holding, to spend when you choose. |
| **Campfire** | a calm stop between chapters: pause, journal, loadout, save. |

Rules of the world:
1. A molecule is **never** blocked, only far. The puzzle is reaching it, never finding it.
2. Every obstacle has a **visible cost** and a **cheaper way past**.
3. Nothing kills you. A crash costs speed and your held buff.
4. Anything that matters to the molecule is lit; scenery is not.

---

## 2. The dose-to-trip arc (the whole shape)

The trip follows the shape of an experience: baseline, onset, come-up, peak, plateau, comedown, afterglow. Each phase has a job in the game.

| Phase | Time | What the player does | World | Music (GM stage) |
|---|---|---|---|---|
| **Baseline** | 0-4 | learns steer / jump / rail on a gentle course; sees the first molecule from 450 m | sober: plain snow and trees | pre |
| **Onset** | 4-14 | chapter 1 (colour). First real approach. Tutorials end. | edges of colour creeping in | pre → funk |
| **Come-up** | 14-38 | chapters 2-4 (pattern, time, sound). Each chapter adds a layer and a tougher puzzle. | recolour, crawling patterns, trails, music opening | funk |
| **Build** | 38-52 | chapters 5-6 (space, mind). The hardest approaches. Barriers 3 thick. | horizon bends, faces appear | funk, rising |
| **Peak** | 52-58 | the Finale on a special descent: all six layers at once, momentum chains with no barriers. Pure flow. | everything | drop |
| **Comedown** | 58-64 | the chill-out course ("Moodless Refrain"), slow, wide, no hazards, layers fade out one by one | softening | chill |
| **Afterglow** | 64+ | summary: molecules, depths, time to trip, best chains; unlocks | quiet | chill tail |

Key point: **the player-controlled variable is time to the peak** (see 7). A fast player skips lots of the come-up. The structure still works because every layer lands the moment you catch it.

---

> **2026-11-19 correction: do not build a new generator.** Godot's `RunRig.gd` already is the director and its output is in the dumps. This section describes what Godot does (zones, rows, link chains); it is not a new system. See `web/docs/DIRECTOR_PORT.md` for the source analysis, what is already ported, and how to change rules at the source (edit Godot, regenerate the dump).

## 3. Pacing: peaks and valleys, in numbers

Intensity = number of decisions per km. One decision = a route piece or buff you choose to use or not.

Per descent (about 10 km, 3-4 min), target curve:

```
decisions/km
 10 |            ##        ##          ###
  8 |          ######    ######      #######
  6 |       #########  ##########  ##########
  4 |     ###########################
  2 |  ####                                  ###
  0 +----------------------------------------------> km
     warm  build   SITE1   valley  build SITE2 ...
```

Segment grammar (every course is a sequence of these, authored by a script, not by hand):

| Segment | Length | Decisions/km | Job |
|---|---|---|---|
| **Valley** | 500-900 m | 1-2 | breath: scenery, a pad chain, one easy buff |
| **Build** | 600-1000 m | 4-6 | introduce this chapter's new piece |
| **Approach** | 900 m | 8-10 | the jungle gym before the molecule (see 5) |
| **Catch** | 100 m | 0 | the molecule, nothing else on screen |
| **Payoff** | 300-500 m | 3-4 | a rewarding chain after the catch: pads, a big ramp, layers settling in |
| **Campfire** | 400 m | 0 | flat, slow, safe. Chapter ends here. |

Course template for a 11 km descent: Valley, Build, Approach+Catch+Payoff, Valley, Build, Approach+Catch+Payoff, Valley, Build, Approach+Catch+Payoff, final Valley. Three to five sites, matching what the dumps already have.

Rules for peaks and valleys:
- Never two Approaches in a row.
- A Valley always follows a Payoff.
- Every Build adds **one** new thing. Don't teach two at once.
- The longest valley sits right before the hardest approach.

---

## 4. The six chapters

| # | Molecule | Layer | New piece introduced | Barrier thickness | Approach shape |
|---|---|---|---|---|---|
| 1 | mescaline | colour | ramps and air steering | none | one ramp straight to the line |
| 2 | 2C-B | pattern | rails (they move you sideways) | 1 | rail or ramp, two options |
| 3 | 2C-E | time | boost + pad chains | 1-2 | speed matters: faster is shorter |
| 4 | DOM | sound | magnet | 2 | magnet saves a bad line |
| 5 | 2C-T-2 | space | saw (cut hedges) | 2-3 | cut through or jump over |
| 6 | 2C-T-7 | mind | wings + everything | 3 | two buffs needed in the right order |

**[default]** Order is fixed on the first trip, to teach well. On later trips the courses are re-seeded and the molecule at each site is shuffled, so the sequence differs.

Per chapter: 2-3 descents. The molecule's site appears once per descent from chapter 2 onward, so a missed one returns in the next descent within a few minutes. Chapter ends when the molecule is caught (or after three descents, then it's offered at campfire to retry).

---

> **Correction:** the approach is Godot's link chain (spring, tube of rings, rail, throw into the opposite lane, then the next chain, molecules or a boost row) plus its prize. Do not invent routes. See `DIRECTOR_PORT.md` section 4.

## 5. Anatomy of an Approach (the puzzle)

The one repeating unit of the game. About 900 m, 18 s at 50 m/s.

1. **Sighting** (900 m): a tall white-prismatic pillar. The HUD shows its name and distance.
2. **Fork** (800-600 m): 3-5 routes visible, each lit and colour-coded by what it asks for:
   - ramp (jump), rail (ride), hedge-with-saw (cut), gate/pad chain (speed), open snow (steer)
3. **Cost board**: any barrier shows thickness by colour ring (green 1, amber 2, red 3); your held saw shows as pips on screen.
4. **Commit** (400-100 m): routes merge toward the molecule's line.
5. **Catch**: grab zone ±4.2 m sideways (±8.4 m with magnet).

Every route ends at a different lateral offset. At most **two** routes reach the molecule's exact line, on purpose: the player is choosing between them. One is cheap but demanding (aim and timing), the other costs a buff but is forgiving.

Sonic test: from the Fork you should know in about 2 s what you'd do. If it takes longer, simplify the Approach.

---

## 6. Buffs and held item

| Buff | Verb | Effect | Built |
|---|---|---|---|
| Boost | arrive sooner | speed kick, faster for 2-3 s | yes |
| Saw | cut a shortcut | cuts up to 3 tree blocks; rocks break it | no |
| Wings | steer in the air | 2x air steering for 8 s | yes (first pass) |
| Magnet | be forgiven | molecule zone 2x wide, others 1.6x, 10 s | yes |

- Each has a screen-edge fringe (cyan saw, purple magnet, orange boost, pink wings) and a world sign (waves for magnet, blade for saw).
- **Loadout slot [default]:** pick up one buff, it's held (shown at the bottom of the screen). Tap to use it. A second pickup swaps or is ignored. This is the main source of "managing options". Boost stays automatic (it's a pad-like thing, not a decision).
- Spawn rules: a buff is placed 100-250 m before the piece it is meant for, so the right tool is always at hand but never spoon-fed.
- Rarity per km: boost 3-4, magnet 1 per approach, saw 1 per hedge section, wings 1-2 (near ramps).

---

## 7. The metric and the loops

**Time to trip (TTT):** seconds from start to catching the sixth. The single number to optimise.
- First trip: about 60 min total, about 35-40 min to the sixth.
- Expert: under 15 min on a daily seed.

**Three loops, each rewarding something different:**

| Loop | Length | Reward |
|---|---|---|
| Moment | seconds | chains, multiplier, sounds, near-miss feedback |
| Descent | 3-4 min | a molecule, descent grade (A-S: cuts, chain, no crash), the next ramp of difficulty |
| Collection | days | depths, courses, trip themes, journal, daily seed, ghost |

**Depth rules (1-3) [default]:**
- 1: caught.
- 2: caught with a clean last 1 km (no crash), or from the air, or on a rail.
- 3: a mastery condition (hands-off final 200 m, or max speed, or two in a row, or a no-saw route through a hedge).

Finale strength = sum of depths of all six (6 to 18). Layer intensity scales with it.

---

## 8. Persistence and modes

**[default]**
- **Trip layers reset each trip** (every trip starts sober). Depth, courses, themes and journal persist forever.
- **Psych mode** = the Finale only, at the strength you've earned, with the sober-to-peak build removed. This is the day-tripper experience and the dev bed. It stays separate until merged.
- **Flagship** = the full trip above.
- **Chill-out mode:** the comedown course, playable on its own at any time once the Finale has been done once.

---

## 9. Data model (so the game can be authored by script)

```
Profile {
  caught: { molecule: { best_depth, count, best_miss } },
  courses_unlocked: [id], themes_unlocked: [id],
  stats: { ttt_best, longest_chain, ... }
}
Trip { chapter, layers: [ids by depth], loadout, clock, seed }
Course { id, length_km, seed, segments: [ {type, z0, z1} ] }
Segment { type: valley|build|approach|catch|payoff|campfire,
          pieces: [ {kind, z, x, params} ],      // from the generator
          site: { molecule, z, x } }              // only on approach/catch
```

The content generator takes a Course (terrain from the Godot dump) plus the segment list and places everything: the dump's own scattered content is **replaced** on approach stretches. That is the one big build: a director that turns the grammar in 3 into placed objects. Everything else hangs off it.

---

> **Revised build order for the director item:** (a) read the remaining generator functions (`DIRECTOR_PORT.md` section 8), (b) add a `pills_lanes` param and a cuttable-barrier tag in Godot behind params so default output stays frozen, (c) regenerate courses with the real generator, (d) wire `_mol_gap` and the pacer so six sites fit a trip. The hand-built generator idea is dropped.

## 10. Build order (dependency-first)

| # | Build | Why now |
|---|---|---|
| 1 | Segment grammar + director (place sites, valleys, approaches) | everything depends on it |
| 2 | Hedge + saw + pips + cost rings | the main puzzle verb |
| 3 | Loadout slot | the "managing options" decision |
| 4 | One molecule per site, six types per trip | removes the trio |
| 5 | Layers wired to molecule catches (visual + audio) | the reward |
| 6 | Campfire, chapters, trip clock, TTT | the structure |
| 7 | Depth rules + journal + profile save | the collection |
| 8 | Finale and comedown courses | the ending |
| 9 | Courses unlock, daily seed, ghost | the long tail |

Test gates (so we don't build 9 before 1 works): after 1-2, a tester should be able to see a hedge from 200 m and know its cost; after 4-5, a catch should be audible and visible from across a room.

---

## 11. Decisions still open

1. ~~Layers per-trip or permanent?~~ **DECIDED 2026-11-19: reset each trip.** Depth, courses, themes and journal persist.
2. Fixed order of molecules on trip 1, or free? Default: fixed.
3. Should the Finale have any hazards? Default: none.
4. Do you want to hold one buff, or allow two? Default: one.
5. Is 60 min the right length for a first trip, or shorter (e.g. 30)? Default: 60 with save points.

---

## 12. Content catalogue: keeping it fresh (added 2026-11-19)

Today the real verbs are steer, jump, grind and speed. Variety comes from changing the ground and the movement, not from more pickups. One new piece per chapter, then mix.

| Piece | What it does for reach | Introduced | Status |
|---|---|---|---|
| Ramp / launcher | air, steer in the air | ch 1 | built |
| Rail | carries you sideways | ch 2 | built |
| Pad chain / boost | speed | ch 3 | built |
| Magnet | wider grab | ch 4 | built |
| Saw + hedge | cut a shortcut | ch 5 | design |
| Wings | 2x air steering | ch 6 | built |
| **Banked wall / half-pipe** | free sideways swing | ch 2-3 | new |
| **Portal pair** | instant 30-40 m sideways move | ch 4 | new |
| **Wind stream** | lift or cross-push, visible ribbons | ch 3-5 | new |
| **Ice / powder patch** | grip changes how you aim | ch 2-5 | new |
| **Beat gate / beat rail** | opens or lights on the music's beat | ch 3+ | new |
| Spring / cannon | big launch, aimed by head | later | idea |
| Collapsing bridge | timed shortcut | later | idea |
| Tunnel / ice cave | fast enclosed route, hidden molecule line | later | idea |

Variations on existing pieces: curved or forking rails, ramps at several angles or with a loop, hedges with gaps or that sway open and shut.

Daily twists (mutators): wings always on, double wind, mirrored slope, fog, reversed gates.

Rule: a new piece is introduced alone in a Build segment, used in an Approach next, then mixed with older pieces from then on. Never introduce two at once.

---

## 13. Do it now or regret it later

| Item | Why it can't wait |
|---|---|
| **Fixed-timestep physics (60 Hz)** | ghosts, daily seeds and fair leaderboards need identical results on every device. Retrofitting breaks every tuned value. |
| **Versioned save format** | profile data (depths, journal, unlocks) must survive updates. Add a version number on day one. |
| **Naming and rating decision** | the molecules use real controlled-substance names. Stores, ad networks and age ratings treat that differently from fictional names. Decide now whether the public build uses real names, code names or invented ones. |
| **Music licences** | the current tracks are non-commercial (some no-derivatives). Selling, ads or in-app purchases need a licence or original music. |
| **Comfort and photosensitivity** | strobing, shake and wide fov can cause harm. Add a reduce-effects switch and a first-run warning before more effects get stacked on. |
| **Head-tracking fallback and calibration** | keyboard / touch / tilt control for anyone without a camera, and a short calibration step on first launch. |
| **Tuning in one config file** | reach envelope, grab radii, spawn rates, buff durations as data, so balancing doesn't mean editing code. |
| **Telemetry for balance** | log approach choices, miss distances, time to trip, where players quit. It exists in part (steer log); extend it. |
| **Party and shared seeds** | the party-play goal means seeds and ghosts need to be shareable. Keep the course seed the single source. |


---

## 14. Status log (2026-11-19, autonomous pass)

Decisions made with the defaults above, no questions asked:

| Item | Done | Notes |
|---|---|---|
| Layers reset each trip | decided | depth, courses, journal persist (profile.js) |
| Effects ripple through the surfaces | built | beat ripple and magnet wave in the ground shader; `?norip` turns off |
| Cheap-looking effects | fixed | stacked glowing popups, soft pickup rings and bubbles, soft spray, tree foliage flattens at distance, gates/rails/rocks/snowball glow (`?noglow` turns off) |
| Black-screen bug | fixed | negative-power NaN in psyfx; guard in gv.js |
| Baseline colour split | reduced | sober split is about a third of before; it grows back to the old strength with the trip |
| **Physics step** | **changed from the plan** | not a literal fixed 60 Hz: equal sub-steps capped at 1/58 s, head read once per frame. Reason: a fixed step without picture interpolation judders on high-refresh screens and would double-process the head sample on slow frames (more steering lag). Determinism for ghosts is deferred: record inputs and add a true fixed step with interpolation when ghosts are built. |
| Tuning in one file | built | `tuning.js` (grab zones, magnet, wings, bpm) |
| Versioned save | built | `profile.js` (v1, migrate hook, guarded localStorage); records catches |
| Naming | built | `names.js`: public build shows Sunglass / Rootbloom / Driftwater / Chime Spore / Shard / Eyecap; `?realnames` shows the originals. NOTE: the cards are named by order, but each molecule's actual effect in psyfx is the Godot one, so card art and effect still need aligning. |
| Comfort / photosensitivity switch | not built | next |
| Camera-free controls + calibration | not built | next |
| Telemetry for balance | partly exists | steer log only; add approach and catch logs |
| Shareable seeds | not built | needs the director |

Next in build order: saw + hedges + pips, loadout slot, then the director (section 10).


---

## 15. Psychedelic effects catalogue and the card each one belongs to (2026-11-19)

Sources: (A) the owner's page `joshuaopolko.com/psychedelic-vr-visual-effects-meta-quest/` (four techniques; its title says six, only four are on the page), (B) Godot's psychedelic code, `web/docs/PSY_GAP.md`, (C) general technique (the visual-hallucination "form constants": tunnels, spirals, lattices, cobwebs). Cost is for a phone: low, mid or high. Status is from reading the code, not from watching each one run.

**Rule:** the psychedelic look is frozen (see memory). New effects ship behind a URL flag and are off by default until the owner turns them on. Every card is a preview of a real effect, so the card art is made from a screenshot of the effect once it exists.

### The six pieces (what each molecule really drives in Godot)

| Piece (molecule) | Effects | Element | Source | Cost | Status |
|---|---|---|---|---|---|
| Ground (mescaline) | moire interference grid | snow | A | low | live (the current ground) |
| | light waves, shapes in the snow | snow | B | low | missing |
| | breathing displacement | snow | A | mid | missing |
| Sky (DOM) | colour bands | sky | B | low | live |
| | polar sine field (rotating lattice) | sky | A | low | missing |
| Colour (2C-B) | moire colour on foliage, hue cycling | trees | A, B | low | colour only |
| Mountains (2C-E) | moire skin creeping with travel, contour bands, breathing | mountains | B | low | skin attached, not driven |
| Ripples (2C-T-2) | flowing grid, bullseye, third grid | snow | B | low | missing |
| Pulse (2C-T-7) | infinite tunnel | sky | A | mid | missing |
| | trees breathe and sway to the beat | trees, rocks | B | mid | missing |

Computed but not drawn: the six "piece" strengths come out of psyfx (`PSY.pieces()`), but nothing in gv.js reads them, so the world runs at one fixed look. Wiring them to the shaders above is the main job.

### Screen-wide effects (Godot post pass)

| Effect | Source | Cost | Status |
|---|---|---|---|
| warp, colour split, pulse, tracer ghosts, punch | B | mid | live |
| buzz swells, sharpen snaps | B | low | computed, partly driving |
| clarity moments (picture drops, then snaps back stronger) | B | low | computed, not drawn |
| rays in tubes | B | mid | barely wired |
| boost smear | B | low | not wired |
| crash tear (rewind) | B | low | not wired |
| jump apex swell (rings and burst) | B | low | not wired |
| mirror fold, cel edges, rings (off by default in Godot) | B | mid | off |

### Faces

| Effect | Element | Source | Cost | Status |
|---|---|---|---|---|
| portrait in the mountains | mountains | B | low | code in worldfx2, not wired |
| portrait on the trees | trees | B | low | same |
| the god in the sky | sky | B | low | same |

### Candidate additions (not in the Godot list)

| Effect | Looks like | Element | Cost | Fits card |
|---|---|---|---|---|
| kaleidoscope / mirror symmetry | view folds into repeating wedges | sky or screen | low | Sky |
| domain warping | flowing noise bends every pattern | snow, sky | mid | Ground, Ripples |
| feedback / video echo | each frame redrawn slightly zoomed and rotated, endless spiral trails | screen | high | Pulse |
| reaction-diffusion | spots and stripes growing and merging | rocks, snow | high | Mountains |
| Voronoi cells | cracked-glass cells that pulse | snow, mountains | low | Mountains |
| cosine palette cycling | colours rotate through a gradient | everything | low | Colour |
| fractal zoom | falling into a Mandelbrot or Julia pattern | sky | high | Sky |
| sacred-geometry lattice | hexagon / flower-of-life grids | sky, mountains | low | Sky |
| visual snow and halation | fine grain, halos on bright things | screen | low | any |
| afterimages | complementary-colour ghost after flashes | screen | low | Colour |
| pareidolia | faces in textures | trees, mountains | mid | Mind (the Watcher) |

Phone budget: prefer low and mid. Feedback, reaction-diffusion and fractal zoom stay desktop-only or are used in short bursts.

### Cards follow the real pieces

Replace the placeholder card set (Sun, Wheel, Hourglass, Bell, Tower, Watcher) with six cards that name the six pieces above (Ground, Sky, Colour, Mountains, Ripples, Pulse), each drawn from a screenshot of its own effect. `names.js` currently maps the old names by molecule order; update it when the art exists.

### Build order for the effects

1. Wire `PSY.pieces()` into the existing shaders (ground, sky, trees, mountains), behind `?pieces`, so each molecule visibly changes its own element. No new shader math needed for the first pass.
2. Missing ground effects: light waves, shapes, bullseye, third grid (switch to the Godot ground port in worldfx2 under the flag).
3. Sky: polar sine field, then the tunnel for Pulse.
4. Trees and rocks: breathing and sway to the beat.
5. Screen: clarity moments, apex swell, smear, rewind.
6. Faces.
7. Candidate additions, one per card, cheapest first.


---

## 16. Steering: assisted lane selection (2026-11-19)

Owner feedback: steering was jittery, and the earlier 3-lane model (the head only selects a target, steering is automatic) felt much better.

Measured (384 steering records from 2026-11-19): the head signal changes only 0.01 to 0.09 per sample, but the steering input after the assists changed 0.12 to 0.26 per sample, 3 to 10 times more. The jitter was added after the head, by the assist terms (lock-on pull, lane hold, edge push) switching on and off. The tracker itself runs at 10 to 13 fps.

Built (default on, `?assist=free` restores direct steering):
- **Lane assist:** the head or keys only select a lane (left / middle / right, 8 m apart, `?lanew=`). Hysteresis: select at 0.30, return to the middle after 0.30 s below 0.14. The board carves to the lane on Godot's pull rule (`(lane - (x + 0.45 vx)) / 12`) with the lane centre eased over 0.18 s, so tracker noise cannot shake it. Three dots at the bottom show the selected lane.
- **Assist smoothing (both modes):** lock-on, lane hold, edge push and the rest are low-passed (0.16 s) separately from the head's own response, so they cannot flip the input between frames.

Not verified on a real head: the numbers above are from keyboard-driven tests in the browser. The right-hand lane reached only +1 m in one 3.5 s test (the lane-hold and lock-on assists may have been fighting it), so check it on a phone.

Related memory: an earlier note says "no auto-steer, visible choices". Reconciled: the board still never turns by itself; it only carves toward a lane the player selected.

### 15b. Additions from an outside suggestion list (2026-11-19)

Source: a pasted answer from another AI (its citations were social-media posts; treat it as ideas, not verified facts).

| Idea | Verdict | Element / card | Cost |
|---|---|---|---|
| Motion aftereffect (rush, then stop: the still world drifts the other way) | build, best of the list | comedown and afterglow (Moodless Refrain) | low |
| FFT frequency bands from the music (bass pulses fov, hi-hats fire particles) | build, with the beat clock as the muted fallback | whole screen | low |
| Beat-snapped gates and pads (extend the quantised sound effects) | build | gates, pads, rails | low |
| Non-Euclidean space (a room bigger than its doorway) | design with the portal pair | Space card | mid |
| Raymarched fractal tunnel | sky only, low resolution, or desktop only | Sky or Pulse | high |
| Stroboscopic flicker | opt-in only, behind a first-run warning, capped at 3 flashes per second | any | low |
| Recursive feedback, vertex displacement, chromatic split, hue cycling | already in the catalogue or live | see section 15 | |

Comfort rule: nothing flashes faster than 3 Hz by default; strobe is off until the player turns it on.


## 17. Buff scarcity and gentle stakes (2026-11-20; reconciles sections 0, 2, 6 with Godot's actual rules and the three.js port)

Principle (owner): consider the whole vision for every decision; mistakes cost something gentle: no hard stop, no huge loss, but enough that a player retries a thing a couple of times. Buffs exist to serve the hunt for the six pieces and to protect the trip, never as a separate pickup game.

### What Godot already does (kept as it is, do not invent over it)
- **A crash** (`RunRig._crash`): speed x 0.3, put back on the line, chain and groove reset, 1.1 s of grace (nothing hurts during it), nothing kills you.
- **A shield** absorbs one crash completely (0.8 s grace, "SHIELD BROKE").
- **A found molecule is never lost** (`_mol_hurt`): the one hit dims (felt level -2 for a while) and comes back ("a setback in the trip, not in the collection"). This is the gentle penalty the owner asked for; no extra layer-loss rule is added.
- **A missed or unfound molecule turns up again** (`_pick_molecule` weights unfound ones 4.0): the retry.
- Spec section 6: one **held slot** (pick up, tap to use, a second pickup swaps or is ignored), buffs placed **100-250 m before the piece they are meant for**, rarity per km: boost 3-4, magnet 1 per approach, saw 1 per hedge section, wings 1-2 near ramps.

### Where the three.js port differs (the work)
1. **Too many buffs.** The dumped courses have about 12 buffs per km (36 in 3 km), because Godot's generator offers one at nearly every opening. The spec rarity is about 3-4 boosts per km, and the other kinds only where they answer something. Fix without regenerating: a rule in the loader keeps a buff only if it answers a nearby need (a molecule site, a hedge, a ramp/gap) and drops the rest, to the spec rarity.
2. **No held slot.** Pickups apply at once. Add the slot: held item shown at the bottom, tap (or a head nod) to use, swap or ignore on a second pickup.
3. **Saw is not built.**
4. **Pickups themselves score nothing.** Points come from effective use (the shield absorbing a hit, the magnet pulling a molecule, wings over a gap).
5. **Gaze orbs** (Godot's "look at it" prizes, three per station at 2.6 and 5.6 m up) were built for left / middle / right control. With analog steering they cannot be collected sensibly. Decision open: make them touchable at 1.3 m in their three lanes (a small streak currency) or remove them. A gaze-dwell port is currently deployed, untested, and should be replaced by whichever is chosen.

### Open decisions
- One held slot or two? (spec says one)
- Use by tap / head nod, or automatic when needed? (spec says tap; boost stays automatic)
- Gaze orbs: touchable currency or remove?

### Not done / not verified
Nothing here is built yet. The loader thinning rule needs the buff-to-need mapping defined from the dump data before coding.

### Decision update (2026-11-20, later): a BANK, not a held slot; nothing to touch, no gesture needed
Owner: use must be hands-free. Instead of one held item with a gesture, the player carries a small **bank** of each buff (cap 2 per type, shown as icons with counts at the bottom). Each is **spent automatically when the situation it is for happens**:
- shield: a crash spends one (that crash is absorbed; Godot's rule: 0.8 s grace, "SHIELD BROKE");
- saw: hitting a hedge spends one and cuts through it instead of crashing (needs a "cuttable" tag on barrier trees in the course data; only the barrier-mode courses have hedges);
- magnet: spent when a piece the player still lacks is close ahead and the board is off its line (needs a tuned rule);
- wings: spent on leaving a ramp toward something in the air (needs a tuned rule);
- boost: stays automatic on pads.
An empty bank means the normal gentle crash (speed x 0.3, about 1 s grace, one found layer dims and comes back, the missed piece turns up again). Hitting something costs a buff, never progress. Scarcity comes from the cap and the spec's rarity; "I am out of shields" tells the player what to hunt for. Rule: a buff is only spent when the need is real (no wasted use). An optional deliberate "use now" (nod, tilt-and-nod for a second choice) can be added later; it is not needed for the first version. Open: the exact trigger rules for magnet and wings; the cap per type; whether gaze orbs become touchable lane orbs or go.

### Level layout decision (owner, 2026-11-20)
The wide open course is the layout: about 25 m of open ground either side of the line (feat_off 15; board limit 31.5 m, 58 m with ?wide=2.4), trees streaming past beyond it. Enough lateral range for fine-tuning toward targets in the path and for wide reach to off-line targets, with the immersion of trees flying by. The narrow winding trail (feat_off 6.5, about 13 m open; long_w11 and the seven biome courses) is not the target: regenerate the biome courses wide (dump_long.gd without WINDING=1) when agreed. Off-line targets belong within about 12-23 m of the line.



## 18. Seek and destroy: the slalom core, progression and set-pieces (2026-11-20, owner direction; nothing here is built yet)

### The core loop (owner)
The game shines when the player threads a **slalom of obstacles, buffs and hazards** and has to look back and forth and decide at once: like flying through a maze, read which way it goes, follow the opening, be ready for a hazard, spot a buff over to the right and make a big swing to nab it. Today the courses are the open slope with the same ramp, rail, spiral, arc and pickups repeated, with no barriers, forks or hazards to choose between (long_s7 has about 20,000 side trees, 53 rocks, 12 ramps, 21 rails, 230 toys, 78 buffs, 341 pads and no barriers). The fix is a **placement language** on top of the pieces we have, not new physics.

**The skill the game trains:** look ahead (read the next opening before you reach this one), commit with fine steering, and use the wide reach for a bait swing. This is exactly what the head steering now supports: the fine centre for threading, the wide reach for the swing (steering tuning is locked, see memory note steering-locked-20261120).

### The moves a section is built from (all reuse existing pieces)
| Move | What the player does | Built from |
|---|---|---|
| **Gate slalom** | Openings alternate left and right, spacing shrinks along the section | barrier trees/rocks with an opening (the `bar_*` courses, Godot gate layouts) |
| **Maze corridor** | Walls with one visible way through; the way bends | wall segments from the same barrier objects, a layout generator |
| **Bait swing** | A buff or piece sits 12-23 m off the line; reaching it means leaving the safe opening for a moment | buffs / pieces placed off line (already tested with `?reachtest`) |
| **Hazard in the opening** | The opening you aim at has a hazard to dodge or a buff to spend (shield, saw) | rocks, hedges, snowball, sling |
| **Fork** | Ramp, rail or open ground, each ending on a different line | existing ramp / rail / pad pieces (section 5) |
| **Chain** | Pads, ramp, rail strung so speed carries through | existing pieces |
| **Squeeze** | The opening is narrower than the board's wobble: fine steering only | barrier with a tight opening |

### Progression across the whole game (one continuous run)
One new thing at a time, never two (section 12), and every earlier thing returns in a harder form. It maps onto the six chapters (section 4):
1. **Chapter 1 (the start):** nearly open snow, one wide gate every ~250 m, ramps only. Learn: steer, look ahead.
2. **Chapter 2:** gate slalom with wide openings, first rails; first bait buff.
3. **Chapter 3:** openings alternate faster; boost chains; first hazard in an opening.
4. **Chapter 4:** maze corridors; magnet appears; baits sit further off line.
5. **Chapter 5:** hedges and the saw; squeeze gates; forks whose routes cost a buff.
6. **Chapter 6 (the climax):** all moves mixed at speed, set-pieces back to back, two buffs needed in the right order, then the Finale glide (every layer on, no hazards).

Points reward **risk**: threading a squeeze, a near miss, a long bait swing and then back on line, a chain kept alive. A flat run of gates pays little. Difficulty adapts gently (section 8): a player who keeps failing a section gets wider openings next time, never a hard stop (section 17).

### Continuity once the levels are bolted into one run
- **Sections are joined at gates:** a themed section ends in a gate that opens into the next; the board's speed, the bank (cap 2 per buff type), the score, the combo and the layers collected carry across.
- **No resets between themes:** a theme is a stretch of the same run with its own props, music colour and obstacle style, not a new level screen.
- **Motifs return harder:** the carnival ring in chapter 2 returns as a faster, denser ring in chapter 5. The player recognises it and feels progress.
- **A set-piece never pauses the run:** it is entered at speed and left at speed.

### Set-piece catalogue (owner's themes first, then ideas)
Each has the read (what you see far off), the decision, the payoff. Props are boxes, cylinders and cheap textured shapes; flat single-colour surfaces are not acceptable (every surface gets a texture or a psychedelic treatment, section 15). Each theme also has a **dressing** (sky, ground texture, music colour) so it reads at a glance from far away.

| Set-piece | The play | Obstacles / baits | Needs |
|---|---|---|---|
| **Roadside carnival** | Slalom through a ring of spinning rides and tent poles, bumper-car lanes, light strings overhead | spinning arms to time, stalls as walls, a prize buff on the far rim | spinning obstacle (rotating bar), tents (boxes), lights (emissive) |
| **Merry-go-round** | A big slow turntable you ride across; horses move up and down and sweep through your line | rotating horses, a buff on the far edge, a ramp off the rim | rotating platform (moving ground the board inherits), horse props |
| **Shopping mall interior** | Long hall with pillars, kiosk slalom, glass shopfronts, an escalator ramp, a fountain to swing around | pillars, kiosks, rolling carts, bait buffs in shopfront doors | interior set (lit hall), pillar and kiosk props, escalator = ramp piece |
| **Mall parking lot** | A grid of parked cars to thread, with cars pulling out and carts rolling | rows of parked cars as gates, moving cars, a cart train, lamp posts | car props (textured boxes), moving obstacle along a path |
| **Farmer's field (cows)** | Open pasture; cows stand and wander across your line, hay bales, fences with gaps, a barn jump | cows (slow moving obstacles), hay bales, fence lines with openings, a tractor | cow and bale props, simple wander motion |
| **Corn field** | A true maze: rows of corn with bends; you cannot see far, so you read the next turn only just in time; clearings with a buff | dense walls (instanced stalks), dead ends with baits, a scarecrow | maze generator on the barrier objects, instanced corn |
| **Superhighway** | Fast, flat, wide: weave through traffic at top speed, trucks as moving walls, overpasses as jumps, lane changes as the swing | moving cars and trucks in lanes, lane gaps, a boost on the shoulder | moving obstacles, lane layout, speed at the top |
| **Tornado (owner, 2026-11-20)** | The board is sucked up into a tornado and drives along the inside of its wall, like a multi-lane highway wrapped around a funnel: lanes are bands on the wall, the "road" climbs in a spiral, and the debris orbiting with you is the slalom | a cow, a house, a car, a barn door, a pickup truck, a swing set, hay bales, a fridge, trees, a shed roof, fence panels, road signs: random debris drifting past, some across your lane, some falling toward you; buffs caught in the swirl; a calm eye at the top as the payoff | a funnel wall mesh (a tilted cylinder or cone textured with swirling cloud and dust), a camera that leans into the curve, debris props on circular paths (an orbit, not a straight line), lanes as angle bands, a way in (a ramp or a vortex pull that sucks the board up) and a way out (the eye) |
| **Haunted forest** (idea) | Slalom between swaying trunks and low branches | swaying obstacles, fog | sway animation |
| **Canyon pendulums** (idea) | Timed gaps between swinging blades | swinging obstacle on a timer | pendulum prop |
| **Drive-in / rooftops** (idea) | Weave between cars; jump between roofs | moving cars, gap jumps | existing ramps |

### Rhythm: slalom is a burst, not the whole game (owner, 2026-11-20)
Not slalom all the time. The run breathes: **a slalom burst** (hunt a buff, seek an opening, evade a hazard; about 250-400 m), then a **blast-off straightaway** (about 500-900 m of wide road at full speed with the usual wide-road objects: ramps, rails, pad chains, big jumps, wide pickups, scenery flying past) before the next burst. Rough cycle: blast, burst, blast, set-piece, blast, harder burst. The set-piece themes (carnival, mall, corn field, highway) are the longer, stranger bursts. Chapter 1 is mostly blast with one tiny burst; chapter 6 is nearly all burst with short blasts to breathe.

### Variety: custom objects, nothing repeated for miles (owner, 2026-11-20)
Rails and ramps get boring when they are the same piece over and over. Rules:
- **A variant pool per piece, per region.** Each region (the post-collapse setting: abandoned everything) has its own 6-8 kinds of ramp, rail and obstacle, and a piece may not repeat within about 600 m. Variants differ in silhouette and in how they play (angle, length, width, where they throw you), not only in colour.
- **Everything is a recycled-world custom object** (post-apocalyptic, abandoned): a wrecked bus tipped on its side as a ramp, a collapsed overpass slab, a car-carrier trailer, a ski-lift gondola on its cable, a fallen pylon, an escalator, a drained pool bowl, a crashed plane fuselage as a tunnel.
- **Rails:** a snapped guardrail, a fallen power line, a pipeline, a shopping-cart track, a broken monorail beam, a fire-escape stair rail, a conveyor.
- **Spirals and arcs:** a parking-garage helix, a ruined bridge span, a ferris wheel rim, a roller-coaster remnant, a broken highway cloverleaf.
- **Pads and markers:** painted road arrows, hazard stripes, faded lane lines, runway lights.
- **Hazards and obstacles:** wrecked cars, barricades, tumbleweed, sinkholes, rogue drones, rusted containers, fallen trees; each region adds a few of its own.
- **One signature object per region** that appears nowhere else (a giant mannequin hand, a derailed train on a bridge, a drained fountain), as the thing the player remembers.
- **Buffs live in the wreckage** (a boost on a car roof, a shield in a vending machine, a magnet in a radio tower), so hunting a buff is also exploring.
Build order for objects: define a small shared kit first (chunks of metal, concrete, glass, signs, vehicles in a few textured shapes) and assemble many variants from it; hand-made hero objects only for the signature pieces. Every surface textured or psychedelic (no flat single colour).

### Materials and shapes change how things ride (owner, 2026-11-20)
Same kind of object, different material or shape, different behaviour, readable at a glance by colour and silhouette:
- **Rails (built in the test copy, colours and ride only):** steel (cyan, normal), glass (pale, fast, shorter), wood (amber, slow and long), neon (magenta, double points), rust (orange, a little rough, longer). A toast names it on contact.
- **Ramps (built in the test copy, throw height only):** each ramp throws 0.7x to 1.6x (SMALL HOP / AIR / BIG AIR). Real shape variety (a short steep kicker, a long low roller, a wrecked-bus ramp, a collapsed slab) needs new geometry: the object kit in the variety rules above.
- **Arcs and tubes:** same idea (a material and a shape per tube: glass tube fast and thin, wooden tube slow and wide).
- **Rules:** four or five materials at most, each with one clear effect; the effect is shown by colour and sound before you touch it; no hidden penalties (gentle stakes, section 17); regions bias which materials appear (a glass-and-neon city, a wood-and-rust farm).

### Authoring approach (so many can be made cheaply)
A section is a short script: a theme, a length, a difficulty level (0-1) and a list of moves. The generator lays the moves on the course by the placement language above, using only the moves that chapter allows. The seeded generator and the buff-thinning rule (section 17) stay; a section replaces the repeated toy / ramp / rail placement in its stretch. Props are instanced meshes (cheap); obstacles that move are a short list updated per frame.

### Open decisions
- Moving obstacles (cows, cars, rides): how many at once; the collision rule (a simple circle test in the board's frame is enough to start).
- Interior sets (mall) in the same run: enclosed lighting and a ceiling, or an open-air mall with a roofline?
- How a mall or carnival connects to the forest slope at both ends (a gate or ramp transition each way).
- Build one section first as a playable test (recommended: a gate slalom with a bait buff on long_s7) to confirm the look-back-and-forth decision is there before the themed sets.

### Not done / not verified
Nothing in this section is built. Barriers exist only in the `bar_*` courses (Godot layouts); moving obstacles, rotating platforms and the maze generator do not exist yet. The three.js build would start from the barrier objects in the dump and the buff bank already in `gv.js`.


## 19. Course grammar: everything has a reason (owner, 2026-11-20)

**Owner's rules.** One material per kind of object: the natural earth-and-grass ramps stay exactly as Godot made them, every rail is shiny chrome. Nothing is strewn at random: a rail, hoop or pad is there because of something near it. Everything is optional (a player can speed past without tripping on it), and a one-hour session must not repeat the same arrangement (the owner's examples of what bores: ramps on either side with a rail in the middle; ramp, same rail, same loop).

### Phrases, not objects
The unit of content is a **phrase**: a short chain of two to four pieces (150-450 m) where each piece leads to the next and ends in a reward. The generator places phrases, never loose objects.
| Phrase | The chain | Why it makes sense |
|---|---|---|
| **Launch and land** | natural ramp -> hoops along the real flight -> a chrome rail where the flight comes down | the hoops show the flight, the rail is the landing |
| **Boost and grind** (built) | boost pad -> a chrome rail starting just past it -> hoops at its end | the boost carries you onto the rail |
| **Boost run** | two or three pads in a line -> a powerup 25-120 m after the last one (built) | steer after speed |
| **Gate field** | slalom with wide openings, a single pylon field before it as a warm-up | tests steering, never blocks |
| **Over-the-top** (planned) | a long rail running above a gate field or a cluster of pylons | the rail is the bypass: fast and safe, but only if you line up |
| **Molecule approach** | the existing Godot approach (spec section 5) | the goal of the run |
| **Open blast** | nothing but road | rest, speed |
No curved rails unless a curve avoids something (a rail may bend around a pylon cluster, never an S for its own sake).

### Against repetition (one hour)
1. A **phrase deck**: shuffled like cards, a phrase may not follow itself or repeat within five, and its lane (left, middle, right, diagonal) must differ from the last two.
2. **Variants inside a phrase**: rail length (28-72 m), design (pipe, bar, twin), hoop arrangement (parabola, spiral, ladder, sweep, low), where on the ramp's line the rail starts.
3. **Chapters change the deck** (spec section 4): chapter 1 has Launch and land and Open blast only; each chapter adds one phrase; the last mixes all, back to back.
4. **Rhythm**: tension and rest on a wave (a busy phrase, then an open blast), longer rests early, shorter later.
5. **Callbacks and surprises**: a signature object per region (spec section 18) and a rare set-piece (tornado, carnival, mall) roughly every 10-15 minutes.
6. **Variable rewards**: hoops, powerups and points differ per phrase; some phrases pay for risk (a tight line) and some for skill (a rail held to its end).

### Built so far (test copy)
Chrome rails only (pipe, bar, twin), straight, from a boost pad (Boost and grind) and after each natural ramp (Launch and land: hoops plus a rail); kit ramps and multi-material looks are off; natural ramps are unmodified; the old spring-and-ring-tube chain is removed.
### Next
Phrase deck and lanes (items 1 and 2), Over-the-top, and a seed so a run can be replayed and shared.
