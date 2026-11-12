# Requirements tracker

Everything asked for, with its status, so nothing gets lost. `[x]` built and tested in simulation, `[~]` partly done, `[ ]` not done.
"Tested" means the headless tests and simulations; almost nothing here has been verified on a real camera yet unless it says so.

## Standing rules
- [x] Calibration is automatic: no staring at dots.
- [x] Gaze maps to the screen; steering follows the eyes (the head may compensate).
- [x] The eyes decide, the game does the precise steering (tracker is about 10-13 fps, about 200 ms late).
- [ ] Gaze-centred fractals / point cloud / trippy visuals (parked, not started).

## Repo, site, docs
- [x] Public GitHub repo `jopolko/gaze-lab`, squashed history, all rights reserved.
- [x] Site layout `/gaze-lab/godot/`, `/gaze-lab/godot-dev/`, `/gaze-lab/eyelab/`, old URLs redirect.
- [~] The 68 site nav links still point at the old URLs (they work through redirects; not rewritten).
- [x] README with screenshots, EyeLab section, techniques link.
- [~] README "techniques at a glance" bullets and a line on EyeLab as the proving ground (offered, not done).
- [x] `docs/TECHNIQUES.md` (how the tracking reaches usable accuracy on ordinary hardware).
- [ ] A one-page item and rules map in the docs (what every pickup, hazard and move does). It exists in chat only.
- [ ] `godot/NOTES.md` brought up to date with the Downhill changes since the rename.
- [x] The game "Carve" is renamed **Downhill**; the old three-lane game is **Downhill Lanes** (`?level=lanes`).

## EyeLab (the raw, unfuzzed baseline)
- [x] Eye-axis iris measure (head-roll proof), toggleable.
- [x] Test 4, signal fit: follow a dot, no calibration, per-signal delay, gain, held-out error.
- [x] Monitor (cube and gaze arrow) fits phone and desktop shapes; mobile layout fixes.
- [ ] Real-camera numbers from test 4 (waiting on you).

## Downhill: course
- [x] Several gate layouts: scatter, pair, evenly spaced trio, isolated decoy.
- [x] Pickups in front of gates and beside the safe line, on orb trails, semi-frequent.
- [x] **Pitch variety and sections**: five zones (steep rush, flat meadow, tunnel, bend, sky-ramp air stretch), each with its own slope.
- [x] **Gates matched to the section**: wide spread gates on the meadow; close gates inside tunnel and bend corridors.
- [x] **Gates lead somewhere different**: every gate of a barrier leads to a different zone, shown by a sign above it; the next stretch is only built when you pass the gate (lazy generation, mist hides the unbuilt ground).
- [x] **Pickups in front of gates depend on what lies behind** (a burst before a rush, a trap before a bend, a shield for a tunnel), so reading the gate decides what a boost will do.
- [x] **Parameters and presets**: seed, length (endless), difficulty, zone mix; presets classic / alpine / meadow / canyon / chaos / endless; URL params and key N.
- [x] **Dead ends**: a tall post on each side of every opening, a fatter beam, corridor walls open up in front of gates, and glowing breadcrumbs lead from the board to the nearest opening when you are lost.
- [ ] More zones and biomes so the world is vaster (ice, dense forest, cliff drops), regions that last several zones, gates that lead to whole regions.
- [x] Targets shown closer (aim range 125 m), lone trees and rocks spotted earlier and avoided harder.
- [~] First-person runs still crash more than third-person in simulation: obstacles hiding gates from eye level. Needs another pass.

## Downhill: pickups and hazards
- [x] Pickups are food (burger boost, ice cream shield, candy double points, donut points), taken on contact. The wide-eyes eating rule is optional (`eat_enabled`, off) because wide-eye detection did not work on your camera.
- [~] Missed food bouncing away like rubber exists but only applies if eating by wide eyes is switched on.
- [x] Snowballs: duck your chin or squint to brace (squint did not work on your camera, chin is the reliable one), or carve away, or outrun; a hit costs about 40% speed, a shove, and your flow chain, never a crash.
- [x] Boost pads, also a burger boost; temporary speed boosts exist.
- [x] Dopamine: sparkles, flash, screen shake, a hop or spin of the rider, per-type effects and sounds, prettier items.
- [ ] Real 3D food models (planned: free CC0 pack, to be swapped in later).
- [ ] On-screen buttons for squint, eat and tricks on touch devices (today these are eyes or keys only).
- [x] Collisions: a tree throws needles, bark and shaken snow with a thwack; a rock gongs, sends out rings and shivers like a struck bell.

## Downhill: view
- [x] First person (default) and third person, toggled with V or the 1ST/3RD label; remembered.
- [x] First person shows only the tip of the board, swinging with the heading, leaning in turns, carrying the tricks.
- [~] Portrait phone layout: the camera keeps the horizontal field of view; not checked visually in a phone-sized window.

## Downhill: ramps, jumps and tricks
- [x] Big ramps in air segments with a pickup above the lip, targetable by gaze.
- [x] Boost pads at the base, middle and top; optional charge (chin down) and pop; or just take the boost.
- [x] Tricks: spin, grab, backflip, plus head shake, cross-eyes, crazy-eyes and a slam (elbow drop and friends).
- [x] Ridiculous names, commentary, chaos events (goose, snowman, slow motion, fireworks, crowd), starburst callouts.
- [~] Cross-eyes, crazy-eyes and head-shake detection is untested on a real camera; keys H, X, Z, F always work.
- [x] **Sky ramps**: air-stretch ramps are steep (about 2x a plain kicker) with a chain of four boost pads: 4 to 5 s of hang time, 30+ m up, thick air that stops the flight overshooting the run-out.
- [x] **Face challenges in the air**: a prompt demands a face (tongue, maniacal smile, shock, pain, wide eyes, cross-eyed, pirate squint, puffed cheeks, kiss, sneer, crazy eyes, head shake); pulling it for 0.3 s pays 220 to 280 points. Detected from the tracker's blendshapes. Not tuned on a real camera: G completes the current prompt.
- [x] **Cinematic cutaway**: high in a big jump the camera swings out to a hero shot of the rider with slow motion, and returns before the landing.
- [ ] More skiing and wrestling-style moves and callouts (a bigger library).
- [ ] A dedicated target marker on the ramp itself (today the pickup above the lip is the target).

## Downhill: menu and themes
- [x] **Pre-run screen** that fits phone portrait (one column, buttons pinned) and landscape (two columns): theme, preset, difficulty, length / endless, seed (roll, copy link), world mix, face challenges, cinematic jumps, phone stabiliser, haptics; remembered between visits. A slowly drifting live 3D backdrop sits behind it.
- [x] **Themes**: alpine, psychedelic (fractal sky, liquid-marble ground, neon trees, rainbow tracers on whatever moves, breathing warp, with an intensity slider), digital (green code-rain ground and sky), synthwave (neon grid, striped sun).
- [ ] More themes (aurora night, volcano, candy); themed mountains and gates; themed music.
- [ ] Tracers cost a second small render of the world: add an automatic fallback when the frame rate drops.

## Phone sensors
- [x] Gyro / accelerometer: removes the part of the iris reading that follows the phone's tilt, holds the gaze through a bump, detects lap use and pauses squint detection while the grip changes; haptics on hits and landings (Android).
- [ ] Not yet tried on a real phone. `?nopm` turns it off to compare; `?pmview=0.3` is an experimental camera lean.
- [ ] Ideas: tilt as a gentle steering bias, shake-to-brace, ambient light for a night mode.

## Open problems
- [ ] "Eye tracking is broken": the likely cause was squint detection reading you as always squinting; fixed and deployed, not confirmed on your camera.
