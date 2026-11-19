# Godot Downhill: inventory of every system, for the three.js port

Generated from `godot/scripts/*.gd` (64 files, 35365 lines, 1290 functions, 38 shaders, 121 section banners). Statuses are what exists in `web/downhill-three` today.


## 1. Systems (the section banners of the big files), with status

| File:line | System | Status in three.js | Note |
|---|---|---|---|
| RunRig.gd:80 | Terrain: the base slope, getting steeper with distance | **PARTIAL** | stage slopes, steep drops, banked walls, trail rollers ported; zones/kickers/melt/mogul not |
| RunRig.gd:82 | One stretch of forest trail: the tree lines down both sides (solid: leave the trail and you hit them), forest behind them, and the slalom poles. Nothing is drawn further  | **PARTIAL** | trail weave, rollers, rising sides done; the tree lines, slalom poles, forest behind not |
| RunRig.gd:197 | FOLLOW THE DOT: on a phone the run starts with a dot that sweeps left and right for about seven seconds. Following it with your eyes is what teaches the game how YOUR loo | **n/a** | phone calibration (replaced by the self-calibrating head control) |
| RunRig.gd:215 | EYE CHECK: is the camera reading your eyes? It runs straight after the dot sweep (and again from Pause > EYE CHECK, or with ?eyecheck on a laptop): 1  the sweep: the fit  | **n/a** | eye tracking diagnostics (different tracker in three.js) |
| RunRig.gd:457 | EYES vs GAME: the four links between your eyes and what the board does, compared at every choice and drawn live. EYES   what the tracker reads (the fitted look on a phone | **n/a** | eye diagnostics |
| RunRig.gd:670 | GOALS: three things to do this run, picked at the start and shown on screen. Nothing on the trail is collected by riding down the middle any more: every pole, ramp, rail  | **MISSING** | three goals per run |
| RunRig.gd:757 | WHAT IS ON THE TRAIL. Between every two poles the trail runs nearly straight for a moment, and that is where things stand: a JUMP   across the middle: ride on and you fly | **NOT STARTED** |  |
| RunRig.gd:767 | THE OPEN SLOPE (the default; ?winding brings the forest trail back). The trail used to wind, and the board followed its bends by itself: hands off, it turned 10 to 15 deg | **PARTIAL** | trail weave, rollers, rising sides done; the tree lines, slalom poles, forest behind not |
| RunRig.gd:1219 | THE TRIP: a meter that sugar and combos fill and time drains. In the Psychedelic look it drives how far gone the picture is: a tease at first (a little breathing and trac | **PARTIAL** | a time and molecule ramp drives the psychedelic pass; the meter (sugar, combos) not |
| RunRig.gd:1226 | SOUND: the music (procedural techno, trance or industrial) follows how hard the run is going: speed, the steepness of the stretch, the trip, a snowball behind you. | **PARTIAL** | a time and molecule ramp drives the psychedelic pass; the meter (sugar, combos) not |
| RunRig.gd:1334 | THE SNOWBALL: now and then, as a steep stretch begins, a giant snowball starts rolling down the slope behind you. It follows where you go but turns slowly, so a quick mov | **PARTIAL** | behind-you ball, dodge rule, molecule hit; side-rolling balls, squint brace, aim not |
| RunRig.gd:1433 | SUBLIMINAL CUES: very quiet tones and a faint tint at the edge of the picture that go with doing things well (an early choice, a clean landing, a long rail, a run of glin | **MISSING** | gold sparks, rails of glints, crash spills |
| RunRig.gd:2118 | FOREST TRAIL: a slalom run. No walls of trees across the hill and no doors in them: one trail, about 26 m wide, winding through forest that stands along both sides, over  | **PARTIAL** | trail weave, rollers, rising sides done; the tree lines, slalom poles, forest behind not |
| RunRig.gd:2219 | Course: every segment has a barrier (a line of trees / boulders with openings) at a random depth, and scattered singles in between. The safe opening drifts by at most abo | **MISSING** | barriers of trees and boulders with openings |
| RunRig.gd:2403 | ZONES: what lies beyond a gate. Every gate in a barrier leads somewhere different, and the next stretch of the course is only built once you have gone through one (a bank | **MISSING** | what lies beyond each gate |
| RunRig.gd:2936 | Realms (Realms.gd): what is built there and what the rule is. Props go into buckets while a stretch is generated, then one multimesh per kind. | **MISSING** | what is built in each zone |
| RunRig.gd:3383 | Parameters and presets. Every course is generated from these, so any setting makes a different run, and length 0 never ends. ?preset=alpine/meadow/canyon/chaos/endless    | **MISSING** | seeded courses and presets |
| RunRig.gd:3454 | Gate layouts: a barrier is one of several shapes, so reading the slope pays off. scatter  the safe gate plus 0-2 gates at random places (the original) | **MISSING** | barrier shapes |
| RunRig.gd:3547 | Buffs: the things worth looking at. boost   a burst of speed and less drag for a few seconds (faster is harder to steer) | **MISSING** | boost, candy, burger and the other buffs and their rules |
| RunRig.gd:3914 | GLINTS: small gold sparks. A rail carries a spiral of them (ride it and you scoop the lot), a ramp leaves an arc of them in the air, and a crash spills some of yours onto | **MISSING** | gold sparks, rails of glints, crash spills |
| RunRig.gd:4184 | The chain. The game is about picking the right thing to go for, in the right order: CANDY (x2) first, because it multiplies what follows, then a BURGER (speed), then a RA | **PARTIAL** | a simple chain count only |
| RunRig.gd:4250 | FLOW: the multiplier you keep alive. Clean gates, landed tricks, pickups, dodges and faces push it up a level; everything you do, even a small pop off the snow, refills i | **PARTIAL** | combo only; the flow multiplier not |
| RunRig.gd:4296 | POP: raise your eyebrows to hop off the snow (W or the up arrow without a camera). On a ramp, holding them up charges the launch instead, and the pop happens at the lip.  | **PARTIAL** | the buggy hop only |
| RunRig.gd:4917 | Physics: the hill pulls, carving costs speed, the board turns on a short spring, momentum follows through grip | **PARTIAL** | hill pull and carving cost in the buggy and open board; the board spring and grip not |
| RunRig.gd:4919 | The safe line toward a barrier: straight from the safe opening of the barrier before it to the safe opening of this one. The straight line from the last opening to the sa | **NOT STARTED** |  |
| RunRig.gd:4965 | The board looks after itself: it swerves just enough around a lone tree or rock, and it always commits to a gate in a barrier. The skill is choosing the right gate, in ti | **NOT STARTED** |  |
| RunRig.gd:5731 | CALLED GATE test (?called): the game marks one opening of every barrier, you look at it, and it records what your eyes said and which opening it understood. Nothing about | **n/a** | eye test |
| RunRig.gd:5997 | ONE THING AT A TIME. Coming up is not everything at once: each part of the world goes strange by itself, in this order, as more is held (h = the six together, 0..1): the  | **MISSING** | each part of the world going strange in its own order |
| RunRig.gd:6138 | THE EFFECTS LAB (F2, or the FX button when the page is opened with ?fxlab): every effect is a knob, grouped by what it lands on. 1 = as designed, 0 = off, more = stronger | **MISSING** | every effect as a knob |
| RunRig.gd:6798 | THE DISTANT BACKDROP. The mountains are a ring that follows the board, so they never move against the road and give no depth. These replace them (the lab switch w_backdro | **PARTIAL** | a ring of close peaks; the real backdrop meshes not |
| RunRig.gd:7554 | Eyes as buttons. LOOK steers and chooses. OPEN WIDE (or hold SPACE) eats a food as you reach it. SQUINT (or hold SHIFT) braces against a snowball. A food you drive past w | **NOT STARTED** |  |
| RunRig.gd:7704 | Snowballs: one rolls in from the side now and then, aimed at where you will be in about 2.6 s. Three ways through: carve away   steer out of its line (or behind it)       | **MISSING** | the sideways snowball with three ways through |
| RunRig.gd:7840 | Boost pads (chevrons on the snow, usually just before a kicker) and epic kickers: a taller ramp with a pad and two pickups in the air. | **MISSING** | chevron pads and epic kickers |
| RunRig.gd:7851 | The jump vortex: a swirl hanging over the base of every ramp. Come near it and an invisible suction lines you up with the ramp and speeds you up to launch speed by itself | **MISSING** | the swirl and suction at the base of every ramp |
| RunRig.gd:8187 | TOYS: things to bounce off and ride through, set between the choice points. Every one feeds the combo, and four DIFFERENT kinds inside a few seconds (these, boost pads, a | **MISSING** | chevron pads and epic kickers |
| RunRig.gd:8384 | ALL DRESSED (see DhJourney): the world changes in waves, and each world changes the ride. | **PARTIAL** | six molecules, dose and felt model, perks, picture-pass looks; the journey director, waves not |
| RunRig.gd:8564 | LINKED SET PIECES (the first one): a SPRING pad in one of the side lanes fires the board up through a TUBE of rings and lands it on the start of a RAIL, which grinds out  | **MISSING** | spring, ring tube and rail |
| RunRig.gd:8718 | GAZE ORBS: prizes that only need to be LOOKED at. In threes (left, middle, right) beside a tube, a rail or the ground, each one fills while the eyes rest on its side and  | **MISSING** | prizes that fill while the eyes rest on them |
| RunRig.gd:8821 | THE CAVERN. A spring that fires the board into the mouth of a long winding tunnel: walls all round, close, and no distance at all, so the picture is made by the walls. Th | **MISSING** | the winding tunnel |
| RunRig.gd:9258 | ASTRAL ECHOES and CHROMATIC CARVE TRAILS (All dressed only). Four faint coloured copies of where the board was a moment ago hang behind it, each a little smaller and a li | **PARTIAL** | six molecules, dose and felt model, perks, picture-pass looks; the journey director, waves not |
| RunRig.gd:9433 | THE KIT: everything you can pick up or bounce off is built the way the molecules are (balls joined by sticks, colours in the vertices, the same material and the same ligh | **MISSING** | pickups, bumpers and rails built as ball-and-stick shapes |
| RunRig.gd:10270 | View: first person (default, like a snowboarding game: only the tip of the board shows, which is also the best view for eye tracking, because the gates are where you look | **PARTIAL** | buggy hood and wheels done; the board tip in the track runs is not |
| RunRig.gd:10491 | Jumps and tricks. A kicker (a ramp of snow) sits beside the safe line now and then, usually with a pickup floating above its lip: look at it, ride it, and in the air: | **MISSING** | kickers with spin, grab and flip tricks |
| RunRig.gd:10665 | Up in the sky: face challenges and the cinematic cutaway | **MISSING** | face challenges and the cutaway |
| RunRig.gd:10667 | Every face the game can ask for: the prompt, what the move is called, and what it pays. | **NOT STARTED** |  |
| RunRig.gd:10801 | PSYCHEDELIC MODE: one full-screen shader over the world, nothing else. Rings and spokes fall away from where you are looking, in colours that cycle; the faster you go (an | **PARTIAL** | tracer ghosts, chroma, vignette, breathing; rings and spokes from the gaze not |
| RunRig.gd:11767 | Aim: the opening you look at, and keep looking at for a moment, pulls the board through it | **MISSING** | the looked-at opening pulls the board |
| RunRig.gd:11973 | Input, pause, report | **NOT STARTED** |  |
| RunRig.gd:12089 | HUD: speed, distance, flow, the gaze ring. Nothing else on the snow. | **PARTIAL** | combo only; the flow multiplier not |
| RunRig.gd:12119 | The set-up guide: pictures, no sentences. For the first seconds of a run on a phone, five round icons show what the tracker needs: your face at a good size, good light, t | **n/a** | eye set-up pictures |
| RunRig.gd:12778 | TRACE test: follow a highlighted dot with your eyes while the game measures how well the tracking keeps up. Start it from Pause -> TRACE TEST, with the T key, or by openi | **n/a** | eye test |
| DownhillRig.gd:290 | Terrain: one function the physics, the meshes and the trees all agree on | **PARTIAL** | stage slopes, steep drops, banked walls, trail rollers ported; zones/kickers/melt/mogul not |
| DownhillRig.gd:402 | Course generation: a forest wall every ROW_GAP metres with several openings, only some of them real | **NOT STARTED** |  |
| DownhillRig.gd:567 | The winding trail (see TrailCurve): the game works on a straight strip; these put what it draws onto the curving line. | **NOT STARTED** |  |
| DownhillRig.gd:569 | A strip point as a world point. | **NOT STARTED** |  |
| DownhillRig.gd:819 | Physics: slope, momentum, grip, drag, jumps | **NOT STARTED** |  |
| DownhillRig.gd:1072 | Openings: reveal by looking (or by closeness), score when you pass | **NOT STARTED** |  |
| DownhillRig.gd:1239 | Eye setup: look at three dots, map the raw eye signal to screen x | **NOT STARTED** |  |
| DownhillRig.gd:1366 | Camera + visuals + HUD | **PARTIAL** | speed and score; the flow and gaze ring not |
| DownhillRig.gd:1668 | Gates: some open and close on a timer (your speed decides when you arrive), some stay shut until the last moment, some look open and slam shut. Snow screens hide part of  | **NOT STARTED** |  |
| DownhillRig.gd:1832 | Art: all built from code (no downloads), kept low-poly so a phone can draw it | **NOT STARTED** |  |
| DownhillRig.gd:1834 | The far valley sheet, as a shader (it was an unshaded standard material) so that it can bend up with the ground. | **NOT STARTED** |  |
| DownhillRig.gd:2197 | Eye tuning: how long you must look, how hard the line pulls, how forgiving the aim is. Open with T or by tapping the EYES label (top right). Saved on this device. | **MISSING** | the looked-at opening pulls the board |
| DownhillRig.gd:2303 | THREE-LANE mode | **NOT STARTED** |  |
| DownhillRig.gd:2305 | Which lane do the eyes pick among the three gates of a wall? The gate nearest to the gaze wins only if it is clearly nearer than the committed one. | **NOT STARTED** |  |
| DownhillRig.gd:2876 | Pause + live tracking monitor (P / Esc, or the button under EYES). Same idea as EyeLab, kept simple. | **NOT STARTED** |  |
| DownhillMenu.gd:309 | THE GUIDE: everything on the course on one page, a colour and a few words each. No scrolling: the columns and the type are sized to the screen. Tap anywhere to close. | **NOT STARTED** |  |
| EnemyAI.gd:168 | Damage API | **NOT STARTED** |  |
| EnemyAI.gd:248 | Death + loot | **NOT STARTED** |  |
| EnemyAI.gd:310 | Ragdoll swap | **NOT STARTED** |  |
| EnemyAI.gd:500 | Brains | **NOT STARTED** |  |
| FlightRig.gd:109 | Course | **NOT STARTED** |  |
| FlightRig.gd:173 | Flight | **NOT STARTED** |  |
| FlightRig.gd:390 | Camera + HUD | **PARTIAL** | speed and score; the flow and gaze ring not |
| Game.gd:101 | InputMap (only registers actions that don't already exist in Project Settings) | **NOT STARTED** |  |
| GazeProvider.gd:245 | Public API | **NOT STARTED** |  |
| GazeProvider.gd:247 | True during the short 'look at the centre of the screen' auto-calibration. | **NOT STARTED** |  |
| GazeProvider.gd:520 | Internals | **NOT STARTED** |  |
| GazeProvider.gd:522 | The usual opening is YOUR median over the last ~8 s of play, not a high percentile: someone who always squints a little (glasses, a low camera) must not be read as squint | **NOT STARTED** |  |
| GazeProvider.gd:903 | Calibration | **NOT STARTED** |  |
| GazeProvider.gd:1273 | Peek (lean out of cover) | **NOT STARTED** |  |
| GazeProvider.gd:1381 | Nod (flight) | **NOT STARTED** |  |
| GazeTargeting.gd:166 | Camera pan from gaze position (and head pose when a tracker supplies it) | **NOT STARTED** |  |
| GazeTargeting.gd:178 | Picking | **NOT STARTED** |  |
| GazeTargeting.gd:237 | Floor-gaze auto-walk | **NOT STARTED** |  |
| GazeTargeting.gd:293 | Bullet time + volley | **NOT STARTED** |  |
| GazeTargeting.gd:388 | Face gestures | **NOT STARTED** |  |
| GazeTargeting.gd:459 | HUD overlay (called from Hud._draw) | **PARTIAL** | speed and score; the flow and gaze ring not |
| GazeTargeting.gd:714 | Peek level: eyes | **NOT STARTED** |  |
| KitEye.gd:209 | The fit (sideways only). While a dot sweeps left and right for a few seconds the seven readings are recorded; a ridge regression then maps them to where the dot was. It a | **NOT STARTED** |  |
| KitEye.gd:411 | LEFT / MIDDLE / RIGHT. The phone camera cannot place a look on the screen to the centimetre, but it can tell three places apart: a look from the middle of the screen to a | **NOT STARTED** |  |
| LevelBuilder.gd:203 | 0  BACKYARD BBQ SHOWDOWN | **NOT STARTED** |  |
| LevelBuilder.gd:309 | 1  SUPERMARKET GRAVEYARD SHIFT | **NOT STARTED** |  |
| LevelBuilder.gd:388 | 2  CANDY KINGDOM MELTDOWN | **NOT STARTED** |  |
| LevelBuilder.gd:484 | 3  MOONBASE LOW-G BRAWL | **NOT STARTED** |  |
| LevelBuilder.gd:577 | 4  DISCO INFERNO LAVA LAIR | **NOT STARTED** |  |
| MainLevel.gd:144 | Level lifecycle | **NOT STARTED** |  |
| MainLevel.gd:267 | Population | **PARTIAL** | the buggy hop only |
| MainLevel.gd:317 | Primitive helpers used by LevelBuilder | **NOT STARTED** |  |
| MainLevel.gd:506 | Peek level: rail stations | **NOT STARTED** |  |
| MainLevel.gd:538 | Nod Flight (level 7): the player body sleeps, the FlightRig owns the camera | **NOT STARTED** |  |
| PlayerController.gd:132 | Input | **NOT STARTED** |  |
| PlayerController.gd:148 | Public API (used by weapons / enemies) | **NOT STARTED** |  |
| PlayerController.gd:150 | Add instantaneous velocity (shoves, blower thrust, grapple pull). | **NOT STARTED** |  |
| PlayerController.gd:174 | Physics | **NOT STARTED** |  |
| PlayerController.gd:359 | Kick | **NOT STARTED** |  |
| PlayerController.gd:422 | Camera: FOV, spring recoil, trauma shake, lean | **NOT STARTED** |  |
| PlayerController.gd:479 | Health | **NOT STARTED** |  |
| Progression.gd:130 | Stat queries | **NOT STARTED** |  |
| Progression.gd:178 | XP / combo / coins | **NOT STARTED** |  |
| Progression.gd:225 | Skills | **NOT STARTED** |  |
| Progression.gd:270 | Gear and power-ups | **NOT STARTED** |  |
| Progression.gd:272 | Equip if better than what's in that slot, else sell. Returns true if equipped. | **NOT STARTED** |  |
| Progression.gd:294 | Save / load | **NOT STARTED** |  |
| Realms.gd:245 | Meshes: a handful of primitives with vertex colours, merged into one mesh each. | **NOT STARTED** |  |
| Realms.gd:452 | What you have discovered, kept between runs. | **NOT STARTED** |  |
| Roster.gd:94 | Primitive helpers | **NOT STARTED** |  |
| Roster.gd:162 | Humanoid dressing (heads/torsos of the 5 humanoids) | **NOT STARTED** |  |
| Themes.gd:478 | The overlay sees the finished picture (screen_texture). In the psychedelic theme `trail` is a slowly fading stack of recent frames; where the picture has moved since then | **PARTIAL** | speed and score; the flow and gaze ring not |
| TouchControls.gd:112 | Input | **NOT STARTED** |  |
| TouchControls.gd:348 | Drawing | **NOT STARTED** |  |

Counts: PARTIAL 23, MISSING 23, REPLACED 0, NOT STARTED 69, n/a 6


## 2. Every shader (visual effect) in the project

| File:line | Name |
|---|---|
| DownhillRig.gd:1835 | SKIRT_SHADER |
| DownhillRig.gd:1852 | GROUND_SHADER |
| GazeCamJS.gd:12 | SHARED |
| GazeCamJS.gd:379 | GLUE |
| GazeCamJS.gd:474 | MAIN |
| RunRig.gd:6005 | SKY_SHADER |
| RunRig.gd:6018 | VEG_LIVE_SHADER |
| RunRig.gd:6385 | SKYDOME_SHADER |
| RunRig.gd:6456 | MTNFX_SHADER |
| RunRig.gd:6548 | FACEFX_SHADER |
| RunRig.gd:6803 | BD_SHADER |
| RunRig.gd:8227 | SHAFT_SHADER |
| RunRig.gd:8827 | CAVE_SHADER |
| RunRig.gd:10805 | PSY_SHADER |
| Themes.gd:58 | HSV |
| Themes.gd:68 | GROUND_PSY |
| Themes.gd:98 | GROUND_MATRIX |
| Themes.gd:125 | GROUND_SYNTH |
| Themes.gd:145 | GROUND_CANDY |
| Themes.gd:176 | VEG_CANDY |
| Themes.gd:202 | SKY_CANDY |
| Themes.gd:219 | GROUND_EGYPT |
| Themes.gd:237 | VEG_EGYPT |
| Themes.gd:251 | SKY_EGYPT |
| Themes.gd:270 | VEG_PSY |
| Themes.gd:286 | VEG_MATRIX |
| Themes.gd:298 | VEG_SYNTH |
| Themes.gd:312 | GROUND_TUNNEL |
| Themes.gd:330 | VEG_TUNNEL |
| Themes.gd:347 | SKY_TUNNEL |
| Themes.gd:364 | GROUND_DESERT |
| Themes.gd:383 | VEG_DESERT |
| Themes.gd:398 | SKY_DESERT |
| Themes.gd:424 | SKY_PSY |
| Themes.gd:439 | SKY_MATRIX |
| Themes.gd:456 | SKY_SYNTH |
| Themes.gd:480 | POST |
| Themes.gd:676 | TRAIL_QUAD |

## 3. File by file: purpose and documented functions


### RunRig.gd  (13393 lines, 394 functions)  class `RunRig`

DOWNHILL: free carving down an open slope. No lanes, no gates, no markers: the course is natural (tree lines, boulder bands, scattered trees and rocks) with openings you read and aim for. Reach the finish line without wiping out.  steering   continuous, from where you look (the iris inside the eye, see DownhillRig._eyes_only_offs): a look aside carves that way, a look back to the middle straightens. Keys A / D, a lean (no camera) and the mouse stand in. aim assist look at an opening and keep looking for a moment (AIM_LINGER): it latches, and the board is gently pulled through it. Look somewhere else and it lets go. After you pass it, the next opening is yours to choose. speed      the hill pulls harder the further you go (steeper slope, less drag), so the run keeps getting faster. Carving costs speed, a tuck (chin down) saves it.  It reuses the DownhillRig terrain, trees, rocks, camera, 

- `RunRig.gd:88` `_forest_tick()`: A few metres of the back forest per frame, for the stretch that was built last; when a stretch's forest is whole it goes in as two batches (crowns and trunks).
- `RunRig.gd:252` `eye_check_start()`: Run the whole check again (from the pause menu).
- `RunRig.gd:272` `_dot_sim_feed()`: Made-up eyes for ?eyecheck=sim and the tests: they follow the dot 0.15 s late, mostly with the head, a little with the iris, with some noise.
- `RunRig.gd:284` `_calib_tick(delta: float)`: True while the dot or the result is on screen: the board waits where it is.
- `RunRig.gd:482` `eye_now()`: What the tracker says right now, before the game does anything with it.
- `RunRig.gd:502` `_dec(g: int, ev: Array)`: The decision trace: every step between the eye reading and the board, as short records per choice: [time, what, ...].
- `RunRig.gd:519` `_choice_feat_done(f: Dictionary, got: bool)`: One thing of a choice is behind the board (or was ridden).
- `RunRig.gd:770` `_winding()`: THE OPEN SLOPE (the default; ?winding brings the forest trail back).
- `RunRig.gd:821` `_seg_box(row: Dictionary, a: Vector3, b: Vector3, thick: Vector2, mat)`: A box laid from a to b (strip points).
- `RunRig.gd:944` `_kick_dh(kk: Dictionary, x: float, z: float)`: How much a ramp raises the ground at a point (the ground with it, minus the ground without it).
- `RunRig.gd:955` `_kick_lift(kk: Dictionary, cur: Dictionary)`: A new ramp raises the ground under things that were put down before it existed (a buff, a pad, a pill, a cupcake in its path): they were set on the old ground and would sit buried.
- `RunRig.gd:1110` `_gen_feats(row: Dictionary, z0: float)`: The things that stand between the poles of this stretch of trail.
- `RunRig.gd:1463` `_cue(kind: int, step: int = 0)`: kind 1: a good moment (two rising notes and a warm tint); kind -1: a bad one (one low note and a cool tint); kind 2: a rung of the glint ladder, `step` higher each time.
- `RunRig.gd:1478` `_xp_tick(delta: float, force: bool = false)`: Points become XP every couple of seconds (and the last bit when the run ends); a new level opens things in the menu and says so.
- `RunRig.gd:1525` `_make_hazard(row: Dictionary, feats: Array, kind: String, zi: float, cx_o)`: A hazard in the middle lane.
- `RunRig.gd:1586` `_eye_zn()`: The same reading unrounded: 0 = the middle of the screen, -1 / +1 = the look targets at the sides (0.75 of the way to the edge).
- `RunRig.gd:1594` `_eye_fine()`: The smallest look to a side the reading can be trusted for, in the same units.
- `RunRig.gd:1605` `_feat_nx(f: Dictionary)`: Where a rail, a jump or a loot line is across the screen right now: -1 = the left edge, +1 = the right edge, 99 = not in view.
- `RunRig.gd:1624` `_zoned()`: True when the eyes are being read as left / middle / right (the learning step passed and the face is in view).
- `RunRig.gd:1635` `_qk()`: How far ahead a thing can be chosen.
- `RunRig.gd:1640` `slide_max()`: How fast the board may slide across to what was chosen: 30 m/s at an easy pace, up to 40 at speed (more of the screen is reachable in the time there is).
- `RunRig.gd:1894` `_feat_tick(delta: float)`: Per physics frame, after the board has moved: getting on a rail, riding it, coming off it.
- `RunRig.gd:2030` `_best_store()`: The run is over: is it the record for this mode on a course of this length?
- `RunRig.gd:2069` `_slalom_tick()`: Which side did the board pass each pole on, and how close?
- `RunRig.gd:2105` `_next_pole()`: The next pole ahead, or {}.
- `RunRig.gd:2144` `trail_x(z: float)`: Where the middle of the trail is (strip x) at strip z.
- `RunRig.gd:2150` `_trail_turn(z: float)`: How hard the trail is turning there, -1 ..
- `RunRig.gd:2158` `_trail_h(x: float, z: float)`: What the trail adds to the height of the ground: rollers and whoops along it, a bank on the outside of every turn, and the sides rising where the forest stands.
- `RunRig.gd:2380` `_make_finish(row: Dictionary)`: The finish: two tall posts and a chequered bar across the whole run.
- `RunRig.gd:2537` `_region_step(j: int)`: Called once per segment: a region lasts four to seven of them, then another (never the same twice in a row) takes over.
- `RunRig.gd:2592` `_assign_leads(row: Dictionary, gaps: Array, rz: float)`: Each gate of a barrier leads to a different kind of stretch (as far as there are kinds to go round).
- `RunRig.gd:2664` `_gate_mat(kind: String)`: The three materials a gate is built from.
- `RunRig.gd:2911` `_build_corridor(row: Dictionary, zone: String, halfw: float, prev_rz: float,)`: A line of trees down both sides of the stretch (a corridor that follows the safe line), and in a tunnel two hoops to thread.
- `RunRig.gd:3014` `_roof_y(x: float, z: float, z0: float, lip: bool)`: Height of the roof above the ground at a point in a roofed realm: a low mouth at the start, then a tall cavern that closes in at the sides of the valley.
- `RunRig.gd:3054` `_make_watcher(x: float, z: float, sc: float, obs: PackedFloat32Array)`: A giant eye on a stalk: a real node, because its iris follows you.
- `RunRig.gd:3080` `_build_roof(row: Dictionary, zone: String, z0: float)`: The roof of a cave: one cheap lumpy sheet over the whole stretch, closing down to the valley walls at the sides.
- `RunRig.gd:3150` `_realm_tick(delta: float)`: Per physics tick: the rule of the realm you are in, the name when you arrive, and the eyes watching you.
- `RunRig.gd:3240` `_update_ribbons()`: Glowing ribbons on the snow from the board to every opening of the next barrier, in the colour of its sign.
- `RunRig.gd:3356` `_layout_spread(gaps: Array, gx: float, d: float, want: int)`: Spread layout for a meadow: several wide gates across the whole slope.
- `RunRig.gd:3373` `_layout_near(gaps: Array, gx: float, d: float, lo: float, hi: float)`: A tunnel or a bend: the second gate sits close by, so the choice is quick.
- `RunRig.gd:3620` `_fx_mat(kind: String, col: Color, energy: float = 1.8)`: Shared materials: "solid" glowing colour, "add" additive translucent, "halo" soft billboard glow, "spark" particle colour from vertex colours.
- `RunRig.gd:3684` `_sparkler(parent: Node3D, col: Color, radius: float, n: int)`: A small cloud of sparkles that stays around an item (turned on only when it is close, so far ones cost nothing).
- `RunRig.gd:3719` `_food_mat(col: Color, glow: float = 0.35)`: One pickup, built from simple shapes but lit like a treat: a spinning gem, a soft halo, a pool of light on the snow and a few sparkles.
- `RunRig.gd:3756` `_food_variant(body: Node3D, t: String, vr: int)`: One pickup, built from simple shapes and lit like a treat.
- `RunRig.gd:3959` `_cheer(text: String, col: Color, size: float = 1.0)`: A big moment: words, a colour flash, confetti and a ring, so it is felt and not read.
- `RunRig.gd:4001` `_air_rings_tick()`: Flying through a ring: a lift, a push and a cheer that grows with every ring in a row.
- `RunRig.gd:4081` `_glint_spill()`: A crash knocks some glints out of the board's pocket: they scatter forward and down the slope, a handful to chase.
- `RunRig.gd:4108` `_spawn_buff(row: Dictionary, t: String, x: float, z: float, trail: Array)`: A buff with a lead-in trail of small orbs (x, z pairs, ordered from far to near).
- `RunRig.gd:4265` `_flow_touch()`: Something small happened: the clock is refilled, the level stays.
- `RunRig.gd:4271` `_flow_up(levels: int = 1)`: Something worth a level happened.
- `RunRig.gd:4314` `_brows_up(delta: float)`: Are the eyebrows up, judged against where this face's eyebrows normally sit?
- `RunRig.gd:4384` `_chain_target_pos(kind: String)`: Where the next step of the chain is in the world (INF when it is not something you can see: the air step).
- `RunRig.gd:4409` `_draw_chain(s: Vector2, k: float, m: float)`: The chain on screen: four dots in order (the next one big and pulsing), a pip for each level, and a thin bar for the time left.
- `RunRig.gd:4556` `_buff_pop(b: Dictionary, shown: String)`: What a pickup feels like, one flavour each.
- `RunRig.gd:4859` `_update_buff_aim(delta: float)`: Looking at a buff for a moment leans the board toward it: the same dwell as an opening, with a wide look tolerance.
- `RunRig.gd:4921` `chord_x(row: Dictionary, z: float)`: The safe line toward a barrier: straight from the safe opening of the barrier before it to the safe opening of this one.
- `RunRig.gd:5019` `_intent_pref()`: Which way the player means to go, from the most certain evidence down: the gate their eyes hold, a look just made, a look held to one side.
- `RunRig.gd:5034` `agency_summary()`: How much of the run was you: the share of gates chosen with your eyes, the share of the steering that came from you (not from help), how engaged the help thought you were.
- `RunRig.gd:5064` `_free_shift(max_t: float, sp: float, above: float, skip_wall: bool = fal)`: Smallest sideways shift (m) that clears every lone tree/rock closer than max_t seconds ahead, and the time to the nearest of them.
- `RunRig.gd:5123` `_guard_path(delta: float, s_in: float)`: Returns the steering added by the avoidance and gate commitment, and nudges the board sideways at the last moment if a swerve is still owed.
- ... and 67 more documented functions
- undocumented: `setup`, `_vis_range`, `_dot_x`, `_dot_ready`, `_check_finish`, `_check_dismiss`, `_draw_calib`, `_cho_get`, `_feat_got`, `_diag_tick`, `choice_summary`, `_draw_cards`, `_draw_diag`, `_goals_new`, `_goal_have`, `_goals_tick`, `_draw_goals`, `_feat_x`, `_rail_y`, `_build_rail`, `_lift_node`, `_in_rects`, `_make_feat`, `_gen_guide`, `_audio_setup`, `_music_tick`, `music_morph`, `_sb_clear`, `_sb_end`, `_sb_tick`, `_cue_init`, `_trip_add`, `_trip_tick`, `_eye_zone`, `_sector`, `offer_m`, `_trail_pick`, `_rail_off`, `_best_key`, `_best_load` ...

### DownhillRig.gd  (3182 lines, 101 functions)  class `DownhillRig`

DOWNHILL: a procedural snow run where gravity, momentum and posture do the work.  body            real slope physics: the hill pulls you, carving sheds speed, a tuck cuts drag, sitting up brakes LEAN head       steer. The board turns, your momentum follows the grip, so a hard turn costs speed chin DOWN hold  TUCK: less drag (faster) and it charges a spring chin snaps UP   POP: a hop off the snow (bigger when charged). Hold chin UP in the air to GLIDE chin UP hold    on snow: sit up = air brake chin snaps DOWN in the air: SLAM, a stomp landing that kicks you forward EYES            the course is a row of openings in a forest wall. Far away every opening looks alike. Look at one for a moment and it resolves (open / hop / dead end). Peripheral vision handles what is near.  Input: GazeProvider.peek_offset (lean), nod_state (chin), gaze (screen position). Arrow keys, A / D, W / S stand in.

- `DownhillRig.gd:570` `W(p: Vector3)`: A strip point as a world point.
- `DownhillRig.gd:575` `_place(n: Node3D, p: Vector3)`: Put a node (made at the strip's orientation) where strip point p is in the world, turned with the trail there.
- `DownhillRig.gd:580` `_wset(n: Node3D, p: Vector3)`: Move a node to strip point p in the world without touching how it is turned.
- `DownhillRig.gd:585` `_unp(p: Vector3)`: Where a strip point is on the screen, and whether it is behind the camera.
- `DownhillRig.gd:615` `_make_marker(g: Dictionary, rz: float)`: Posts + a bar over the opening.
- `DownhillRig.gd:678` `_chunk_step(job: Dictionary, budget_us: int)`: Advance one chunk job for at most budget_us microseconds (it always does at least one row).
- `DownhillRig.gd:771` `_chunk_pump()`: Called every physics frame: one queued ground chunk gets a few milliseconds of work.
- `DownhillRig.gd:1250` `fit_gaze(cs: Array, ls: Array, rs: Array)`: Pure: fit screen x (0.5 / 0.1 / 0.9) against the raw signal medians for the centre, left and right dots.
- `DownhillRig.gd:1308` `_toast(text: String, color: Color, kind: String = "info")`: kind "info" is a short message in the middle; kind "ach" is an achievement (points and a name), small, in the corner.
- `DownhillRig.gd:1738` `_forecast(g: Dictionary, row: Dictionary)`: Will this gate let you through if you keep your speed?
- `DownhillRig.gd:1988` `_make_tree_mesh()`: Three stacked tiers, green skirts under snow-laden tops.
- `DownhillRig.gd:2016` `_make_rock_mesh()`: A lumpy boulder: rocky sides, a snow cap on every upward-facing vertex.
- `DownhillRig.gd:2040` `_make_flag_mesh()`: A pole with a tall feather flag (tinted per instance).
- `DownhillRig.gd:2182` `_push_shadow(x: float, z: float, length: float, width: float)`: A soft blue shadow shape on the snow, cast away from the low sun (works the same on every renderer, so a phone gets it too).
- `DownhillRig.gd:2207` `_pad()`: Extra width (screen fraction) around a gate that still counts as looking at it: grows with how noisy your tracking is.
- `DownhillRig.gd:2306` `lane_pick(gx: float, sx: Array, cur: int, margin: float)`: Which lane do the eyes pick among the three gates of a wall?
- `DownhillRig.gd:2317` `_seek_term()`: SEEK: the carve toward the lane of the gate your gaze picked (same lead / gain the lane tests were tuned with), faded in after a reset.
- `DownhillRig.gd:2325` `_eyes_only_offs(delta: float, geo_offs: float)`: EYES ONLY: the iris position inside the eye opening is a pure eye signal (a head turn moves the whole eye, not the iris inside it).
- `DownhillRig.gd:2475` `_lane_gate(delta: float, vs: Vector2)`: GATE control: look at the gate you want to go through.
- `DownhillRig.gd:2524` `_update_lane_stats()`: Learns the dead zone from your own signal: wide enough to ignore your noise, narrow enough that your real range crosses it.
- `DownhillRig.gd:2557` `lane_dir(off: float, zone: float, prev: int)`: Joystick-style lane control: look clearly left or right of the middle and the lane steps that way.
- `DownhillRig.gd:2781` `_lane_gaps(row: Dictionary, gaps: Array, j: int)`: Three gaps per wall at fixed lanes.
- `DownhillRig.gd:2824` `_make_coins(row: Dictionary, gaps: Array, rz: float)`: Coins sit in every lane, so the lane you choose is what you collect: nothing points at the safe lane.
- `DownhillRig.gd:3051` `_draw_pause_simple(font: Font, s: Vector2, k: float)`: The pause screen a player sees: big buttons, nothing to tune.
- undocumented: `_note`, `setup`, `terrain_h`, `_grad`, `_make_assets`, `_kind_color`, `_kind_label`, `_gen_segment`, `_flat_mat`, `_add_rock`, `_behind`, `_add_mm`, `_chunk_tint`, `_path_lat_a`, `_ground_color`, `_chunk_post`, `_chunk_job_new`, `_build_chunk`, `_build_sled`, `_eye_mode`, `_physics_process`, `_pop`, `_land`, `_crash`, `_collide`, `_gap_screen`, `_resolve`, `_update_rows`, `_pass_row`, `_update_focus`, `_maybe_start_cal`, `_on_recentre`, `_eye_x`, `_input`, `_cleanup`, `cleanup`, `_place_camera`, `_process`, `_hud_scale`, `_tw` ...

### GazeProvider.gd  (1443 lines, 58 functions)

Autoload "GazeProvider": the one place gameplay reads eye / face input from.  Backends (swap at runtime, gameplay never knows which one is live): MOUSE    mouse position is the gaze point; keys simulate face gestures. For development and for playing without a camera. UDP      JSON packets from an external tracker (tools/gaze_helper.py uses MediaPipe Face Landmarker on a webcam; a phone app / ARKit bridge can send the same packets). Low confidence falls back to the mouse. SCRIPTED tests / replays set the gaze directly.  Packet (any subset of keys, UDP port 5005): {"x":0..1, "y":0..1, "conf":0..1, "blink_l":0..1, "blink_r":0..1, "mouth":0..1, "brows":0..1, "yaw":-1..1, "pitch":-1..1}  Keys: F9 hands-free on/off, F10 mouse <-> UDP backend, F8 recentre (UDP). Mouse-sim gestures: B blink (tap twice = double), Z/X wink L/R, M mouth, V brows.

- `GazeProvider.gd:326` `set_scripted(pos: Vector2, conf: float = 1.0)`: Tests / replays: pin the gaze point directly.
- `GazeProvider.gd:334` `ingest(d: Dictionary)`: Apply one tracker packet (also callable directly by other transports).
- `GazeProvider.gd:460` `eye_x()`: The sideways eye reading the steering uses (iris-in-eye units: 0.5 = centre, falls when you look right).
- `GazeProvider.gd:465` `kit_used()`: True when the steering should take the STARGAZE reading as it is, with none of the centring, sizing and filtering this game adds to its own readings.
- `GazeProvider.gd:474` `tracking_ok()`: True when a tracker is feeding us (or we're simulating with the mouse).
- `GazeProvider.gd:483` `eye_anchor(screen_pos: Vector2, weight: float = 0.5)`: A known fact for the automatic offset: right now the player is looking at `screen_pos`.
- `GazeProvider.gd:585` `face_is(kind: String)`: Is the player pulling this face right now?
- `GazeProvider.gd:793` `_update_head_move()`: Lean sideways = strafe, lean toward the screen = walk forward, lean back = back up.
- `GazeProvider.gd:803` `start_camera()`: Browser camera tracking (MediaPipe Face Landmarker, runs on-device, nothing is uploaded).
- `GazeProvider.gd:1017` `_fit_ridge()`: Ridge regression: standardised signals (iris ratios, eye-look blendshapes, head pose) -> screen x,y.
- `GazeProvider.gd:1171` `_geo_z(g: Vector2, openness: float, hd: Vector2, has_head: bool)`: One new tracker sample (15 Hz).
- `GazeProvider.gd:1281` `geo_median()`: Median of the last few raw geometry-gaze samples (screen-plane units from the tracker), or Vector2.INF.
- `GazeProvider.gd:1295` `limb_ready()`: True while the limbus-fit eye signal (the precise one, same as EyeLab) is arriving.
- `GazeProvider.gd:1301` `limb_sample()`: [lx, ly, head yaw, head pitch]: where the iris sits inside the eye box (median of the last few frames) and the head angles in radians.
- `GazeProvider.gd:1353` `peek_offset(delta: float)`: Where the player should lean to (x right, y up, z forward; metres), smoothed.
- `GazeProvider.gd:1369` `peek_look(delta: float)`: Extra camera yaw / pitch (radians) from turning / nodding the head, magnified.
- `GazeProvider.gd:1400` `nod_state(delta: float)`: (chin pitch, chin velocity) for the flight game, camera and keyboard combined.
- `GazeProvider.gd:1418` `debug_line()`: One-line live diagnostic for the on-screen HUD (so a phone that "does nothing" can tell us why).
- `GazeProvider.gd:1430` `camera_message()`: What the HUD should say about the camera: {"text": String, "color": Color}; text "" = nothing to say.
- undocumented: `_ready`, `set_active`, `set_backend`, `mix_used`, `backend_name`, `recentre`, `lid_baseline`, `_track_lids`, `_track_conv`, `cross_eyed`, `squint_held`, `wide_held`, `_now`, `_input`, `_process`, `_process_body`, `_poll_udp`, `_gestures`, `_emit_blink`, `_poll_camera`, `_poll_camera_inner`, `_feat_vec`, `start_calibration`, `_calibrate_tick`, `_series`, `_mean`, `_std`, `_finish_calibration_axes`, `_finish_calibration`, `_ridge_solve`, `_predict`, `_pct`, `reset_gestures`, `_geo_push`, `_dz`, `_camera_fresh`, `_update_peek`, `peek_offset_current`, `_update_nod`

### DownhillMenu.gd  (1345 lines, 46 functions)  class `DownhillMenu`

The pre-run screen for Downhill: a live 3D backdrop that drifts slowly behind glass cards, one column on a phone held upright, two on a wide screen, with the start buttons always on screen at the bottom. The game is paused behind it. Everything chosen here is remembered, and the course can be shared as a link. Sizes are in the game's canvas units (1280 wide in landscape, 1280 across the SHORT side in portrait), so `_u` scales them up for a phone held upright.

- `DownhillMenu.gd:205` `_switch_tex(on: bool)`: An iOS-style switch row: the name on the left, the switch on the right, a hairline under it.
- `DownhillMenu.gd:264` `_pair_grid(parent: Node)`: Two columns of switches (or dials), so a page of them is half as tall.
- `DownhillMenu.gd:760` `_mh_slider(c: Node, key: String, lo: float, hi: float, name: String, wo)`: One dial can drive more than one setting (`also`: key, scale), so the page has four dials instead of six.
- `DownhillMenu.gd:1002` `_locked(key: String)`: A setting that is not open yet at this level: greyed out, with the level that opens it.
- `DownhillMenu.gd:1235` `_css_per_unit()`: How many CSS pixels one canvas unit is on this screen right now (1.0 is a laptop window at its natural size, about 0.3 to 0.5 on a phone).
- `DownhillMenu.gd:1339` `_input(event: InputEvent)`: The camera and the tracker take a few seconds to wake up: the first touch of the menu starts them, so that by the time START is pressed they are nearly ready (the camera stays off for anyone who only landed here).
- undocumented: `_ready`, `_label`, `_style`, `_card`, `_switch_row`, `_build_tabs`, `_show_cards`, `_guide_toggle`, `_button`, `_flow`, `_grabber_tex`, `_slider`, `_build_header`, `_build_theme_card`, `_build_course_card`, `_build_sound_card`, `_build_experience_card`, `_build_mayhem_card`, `_build_reports_card`, `_refresh_reports`, `_build_footer`, `Game_presets`, `_preset_defs`, `_pick_preset`, `_custom`, `_pick_theme`, `_sync_widgets`, `_apply_locks`, `_sync_labels`, `_diff_word`, `_mix_word`, `_load`, `_save`, `_url_overrides`, `link`, `_copy_link`, `_process`, `_apply_unit`, `_other_games`, `_start`

### EnemyAI.gd  (973 lines, 43 functions)  class `EnemyAI`

One script, many characters: Roster.DEFS picks stats/looks, `behavior` picks the brain. Hits deal damage; big hits ragdoll (a jointed RigidBody swap that inherits the impact vector); at 0 HP the character pops into confetti and drops loot.

- `EnemyAI.gd:184` `apply_hit(launch_velocity: Vector3, point: Vector3, source: StringName)`: `launch_velocity` is the velocity change a ragdoll should receive.
- `EnemyAI.gd:222` `apply_wind(accel: Vector3, delta: float, dps: float = 0.0)`: Continuous wind from the leaf blower: damage-over-time + ragdoll after exposure.
- `EnemyAI.gd:830` `rustle()`: A hidden baddy gives itself away: a squeak and a puff of dust.
- `EnemyAI.gd:836` `_exposed_to_player()`: True when the player's camera has a clear line to this character's head or chest.
- undocumented: `_ready`, `_exit_tree`, `_setup_collider`, `_build_bar`, `_bar_mat`, `_update_bar`, `_default_damage`, `take_damage`, `get_ragdoll_body`, `_die`, `_pop`, `_drop_loot`, `ragdoll`, `_new_root`, `_build_blob_ragdoll`, `_build_humanoid_ragdoll`, `_make_part`, `_pin`, `_announce`, `_restore_visual`, `_recover`, `_physics_process`, `_path_dir`, `_keep_distance`, `_begin`, `_chase`, `_run_behavior`, `_run_action`, `_suck`, `_fly`, `_seen_by_player`, `_cover`, `_throw`, `_summon`, `_hit_player`, `_flash`, `_apply_move`, `_animate`, `_ragdoll_tick`

### Themes.gd  (910 lines, 15 functions)  class `Themes`

Looks for the Downhill world. A theme is a sky, a ground, a tree finish, the light, and (for the trippy ones) a full-screen pass. Each shader is written to keep the PLAY readable: the ground stays dark enough that gates, trees and rocks always stand out, and the neon goes on the things you must see.

- `Themes.gd:693` `ground_pal(id: String)`: Each world's ground is the same lattice in its own colours: [light square, dark square, line, how much of it replaces the snow].
- `Themes.gd:789` `_puff(st: SurfaceTool, c: Vector3, r: float, squash: float, dark: )`: A lumpy sphere for the fluffy shapes: smooth, a little uneven, dark underneath and pale on top (the vertex colours tell the shaders which is which).
- `Themes.gd:817` `fluffy_tree_mesh(id: String)`: A fluffy tree: four soft puffs stacked and narrowing, a stubby trunk.
- `Themes.gd:834` `gumdrop_mesh()`: A gumdrop for a rock: a squat, smooth dome.
- `Themes.gd:844` `candy_hills_mesh()`: Cotton-candy hills around the horizon, in place of mountains.
- `Themes.gd:867` `hazard_skin(id: String)`: What rolls down at you (the snowball's stand-in): the rules are the same, the monster is not.
- `Themes.gd:872` `pyramid_mesh()`: Pyramids (and a few obelisks) in a ring far away, in the colours of sandstone, each face a different shade.
- undocumented: `theme_data`, `make_shader`, `ground_material`, `veg_material`, `sky_material`, `mist_color`, `_puff_big`, `post_mode`

### GazeTargeting.gd  (852 lines, 39 functions)  class `GazeTargeting`

Hands-free gameplay layer ("Dead Eye Goose").  * Gaze picks things: enemies, props and loot within a snap radius of the gaze point (cone-snap), with a short grace period so webcam jitter never resets a lock. * STARE at an enemy/prop to LOCK it (up to 3). The first lock drops the world into bullet time; a hard blink (or the timer running out) fires the volley. * STARE at loot to magnetise it. STARE at the floor to walk there (auto-stops when enemies get close: that's your "stage"). * Looking near the screen edge pans the camera (dead zone in the middle). * Face gestures: wink-left kick, wink-right next weapon, mouth-open burp shockwave, eyebrows jump. Low tracking confidence widens the snap radius and slows dwell timers.

- `GazeTargeting.gd:84` `_snap()`: Screen radius that counts as "looking at" something.
- `GazeTargeting.gd:407` `_fire_at_gaze()`: Blink with nothing locked: shoot wherever you are looking (snapped to an enemy if close).
- `GazeTargeting.gd:429` `_on_wink(_left: bool)`: Either eye's wink swaps guns.
- `GazeTargeting.gd:538` `_draw_guide(ci: Control, font: Font)`: The "how to play hands-free" card: four steps that tick off as you do them.
- `GazeTargeting.gd:593` `_draw_eye_meters(ci: Control, font: Font)`: Two small bars show how closed each eye reads (above its own open baseline), with the trigger line, so you can SEE what blinks / winks the detector is getting.
- `GazeTargeting.gd:626` `_draw_head_monitor(ci: Control, font: Font)`: A live 3D monitor of what the tracker sees: a cube that turns like your head (shown as in a mirror: turn right and it turns right) with a floor grid for reference, an amber nose line, and a green arrow for the 3D gaze di
- `GazeTargeting.gd:684` `_draw_peek_hud(ci: Control)`: Peek level HUD: the head monitor (camera mode) and a lean gauge so you can see what your lean does.
- undocumented: `_ready`, `_exit_tree`, `_real`, `_process`, `_pan`, `_pick`, `_consider`, `_complete`, `_floor_step`, `_walk`, `_enemy_near`, `_clear_waypoint`, `_begin_bullet`, `_end_bullet`, `reset`, `fire_volley`, `_fire_one`, `_impact`, `_live`, `_on_blink`, `_on_mouth`, `_on_brows`, `draw_overlay`, `_guide_done`, `_draw_calibration`, `_peek_eyes_live`, `_peek_clear`, `_peek_gaze`, `_peek_sniff`, `_peek_fire`, `_peek_swap`, `_draw_peek_eyes`

### GazeCamJS.gd  (755 lines, 1 functions)  class `GazeCamJS`

Browser-side face tracking, injected only when the player asks for camera control. Loads MediaPipe Face Landmarker from a CDN on demand (so it costs nothing on first load), opens the front camera, and publishes window.__gaze every video frame. Video never leaves the device.  Published fields: x,y (gaze guess), conf, blink_l, blink_r, mouth, brows, nx (nose x, mirrored so + = your right), fw (face width = distance proxy). NOTE: written without access to a real camera; tune GAIN / flip signs with F8.

- `GazeCamJS.gd:753` `source()`: The script injected into the page.

### LevelBuilder.gd  (650 lines, 17 functions)  class `LevelBuilder`

Builds the five themed levels out of primitives, plus each level's lighting. Every level has its own environment AND its own mechanic mix: 0 Backyard BBQ     trampolines, slip-n-slide, goo pool, sprinkler boost strip 1 Supermarket      wet-floor ice, freezer goo, conveyor boosts, shelf-top climbs 2 Candy Kingdom    chocolate river goo, marshmallow bounce, rainbow slide, gumdrop hills 3 Moonbase         LOW GRAVITY, launch pads up the reactor, updraft vents, moon ice 4 Disco Inferno    LAVA everywhere, bridges between islands, vents, disco floor + disco ball

- `LevelBuilder.gd:33` `_demo(L: MainLevel)`: 5  EYE DEMO RANGE: a small, cheap arena for the web demo (few objects so a phone loads it quickly; no lights, no particles, no decor).
- `LevelBuilder.gd:68` `peek_baddies(station: int, round_n: int)`: Spawn list [kind, position] of hidden baddies for a station (more on later rounds).
- `LevelBuilder.gd:84` `_hide_spot(cam: Vector2, cover: Vector2, r: float, behind: float, side:)`: Where to stand behind a round cover so you are hidden from `cam` but a sideways lean of `want_lean` reveals you.
- `LevelBuilder.gd:101` `_lean_to_reveal(cam: Vector2, cover: Vector2, r: float, spot: Vector2)`: Smallest sideways camera shift (either way) that gives a clear sight line past a round cover.
- `LevelBuilder.gd:111` `_flight(_L: MainLevel)`: 7  NOD FLIGHT: just an environment.
- `LevelBuilder.gd:123` `_downhill(_L: MainLevel)`: 8  DOWNHILL: just an environment.
- `LevelBuilder.gd:137` `_trance(_L: MainLevel)`: 9  OCULAR TRANCE: just an environment (a dusk void).
- `LevelBuilder.gd:150` `_gaze_test(_L: MainLevel)`: 10  GAZE TEST: a dark void; the rig draws everything in 2D.
- undocumented: `build`, `_peek`, `_hue`, `_ring_points`, `_backyard`, `_market`, `_candy`, `_moon`, `_lava`

### MainLevel.gd  (595 lines, 32 functions)  class `MainLevel`

Level framework: owns the director, builds one of five themed levels (LevelBuilder), applies its lighting/environment, bakes navigation, scatters props, and exposes the primitive helpers the builders use.

- `MainLevel.gd:406` `ramp(x: float, z_low: float, dir: float, height: float, deg: floa)`: Ramp rising from ground at z_low toward dir (+/-1 along Z).
- undocumented: `_ready`, `_unhandled_input`, `_process`, `_physics_process`, `load_level`, `advance_level`, `_on_player_died`, `_apply_environment`, `_bake_navigation`, `_blocked`, `random_spawn_point`, `_spawn_props`, `_make_checker_material`, `_material`, `_place`, `cone`, `ball`, `prism`, `torus`, `light`, `spot`, `spinner`, `zone`, `keepout`, `particles`, `_peek_begin_station`, `_peek_advance`, `_start_flight`, `_start_trance`, `_start_gaze_test`, `_stop_flight`

### KitEye.gd  (580 lines, 16 functions)  class `KitEye`

The sideways eye reading from the STARGAZE tracker, ported as it is (no calibration, no Kalman filter, no blending of several readings): on the player's phone it followed a sideways look well, where the blend of three readings used here before did not.  hx    where the iris sits along the line between the corners of the eye, averaged over both eyes (0 = the middle, in eye widths) x     hx minus its own slow centre (it follows over about 4 s), times 14, limited to -1 .. +1, through a One-Euro filter. + = looking to the right of the screen.  The reading is held while the lids are moving (a blink drags the iris landmark with it). "Open" is judged against this face's own resting lid level, because the raw blink score for open eyes is much higher when you look down at a phone.

- `KitEye.gd:98` `idle(now: float, delta: float)`: Every frame: when the readings stop (no face in the picture) the look eases back to straight ahead instead of staying where it was.
- `KitEye.gd:126` `set_feat(hx: float, hy: float, lid: float, yaw: float, pitch: float, )`: The other six things the fit uses, from the same camera frame: iris height in the eye, upper lid, head turn and nod, where the face is in the picture.
- `KitEye.gd:263` `_ridge(pairs: Array)`: pairs: [[PackedFloat32Array, x], ...] -> model, or {}
- `KitEye.gd:330` `finish_fit(targets: Array)`: targets: [Vector2(time, x)] in the same clock as the readings, in order.
- `KitEye.gd:498` `finish_zones(stops: Array)`: stops: [[time the dot jumped there, time it left, x of the dot (-, 0, +)], ...] in the clock of the readings.
- undocumented: `reset`, `_alpha`, `add`, `begin_fit`, `_solve`, `_predict`, `fitted`, `_median`, `_zn_of`, `_zone_step`, `begin_zones`

### PlayerController.gd  (549 lines, 23 functions)  class `PlayerController`

First-person slapstick controller.  Features: mouse-look + speed-reactive FOV, WASD/sprint/jump (with coyote time and jump buffering), a momentum slide that turns slopes into speed ramps, a box-query kick that launches props and ragdolls enemies, and a spring-based camera (recoil + trauma shake).

- `PlayerController.gd:151` `apply_push(dv: Vector3, max_speed: float = 0.0)`: Add instantaneous velocity (shoves, blower thrust, grapple pull).
- `PlayerController.gd:158` `add_trauma(amount: float, cap: float = 1.0)`: Screen-shake. `cap` stops continuous sources from stacking beyond a level.
- `PlayerController.gd:164` `add_recoil(peak_deg: float, kick_back: float = 0.0)`: Spring kick on camera pitch.
- `PlayerController.gd:256` `_peek_velocity(delta: float)`: Velocity that takes the body to the rail anchor plus the (magnified) head lean.
- `PlayerController.gd:346` `_shove_bodies(speed: float, dir: Vector3)`: Fast bodies plow through physics props and bowl over enemies.
- `PlayerController.gd:524` `slip()`: Banana-peel stumble: brief loss of control, a little damage.
- undocumented: `_ready`, `_unhandled_input`, `is_sliding`, `_physics_process`, `_walk_step`, `_start_slide`, `_end_slide`, `_slide_step`, `_can_stand`, `_do_kick`, `_play_foot_anim`, `_process`, `max_hp`, `heal`, `take_damage`, `revive`, `reset_wave_state`

### DhMusic.gd  (506 lines, 25 functions)  class `DhMusic`

Procedural music for Downhill: techno, trance or industrial, composed from a seed and rendered at the start of a run as a handful of looping layers (kick, bass, hats, percussion, pad, lead) that all have the same length. The layers fade in and out with how hard the run is going, so the music builds with you: the kick and a soft pad on the gentle stretches, the bass, hats, percussion and lead as the speed, the steepness and the trip go up. Rendering is spread over many frames (a few milliseconds each) so nothing stalls; the music starts when it is ready.

- `DhMusic.gd:58` `ensure_buses()`: No extra buses: everything plays on Master and the two volumes are applied to the players themselves.
- `DhMusic.gd:74` `compose(style_id: String, seed_v: int)`: Composes and starts rendering.
- `DhMusic.gd:93` `_plan_special()`: JUNGLE: the amen break (a four-bar drum pattern of kicks, snares and ghost snares over steady hats) with a deep sub bass and dark pads.
- `DhMusic.gd:441` `_finish()`: All the events are drawn: duck the sustained layers under the kick, soft-limit, and turn each layer into a looping stream.
- `DhMusic.gd:487` `bump(a: float = 0.35)`: A moment that deserves a hit: the whole mix swells for a second.
- undocumented: `_fade`, `set_bus_volume`, `vol_db`, `_plan`, `_process`, `_run`, `_hz`, `_add`, `_kick`, `_clap`, `_clang`, `_hat`, `_snare`, `_bell`, `_bass`, `_pad`, `_arp`, `set_intensity`, `_mix_levels`, `stop`

### Realms.gd  (476 lines, 13 functions)  class `Realms`

REALMS: the strange places behind the mystery gates. Each one has its own ground, its own props, its own rule, and none of them is announced: a gate shows a glyph, never a name, and the name appears when you arrive. Everything is generated from primitives and a small shader.  highway   DESERT HIGHWAY  a neon desert grid, cacti, road-sign poles, swarms of bats. The surface is slick: you drift.      (hard) interzone INTERZONE       a paper-and-newsprint bazaar of arches and pillars. At the far barrier the world is CUT UP: you are spliced sideways. hive      THE HIVE        a ribbed bone-and-pipe corridor that breathes. The beat speeds you up and drags you back, hoops to thread.  (hard) eyes      ORCHARD OF EYES giant eyes on stalks follow you. Look toward one and hold it: it blinks shut and lets you pass. melt      THE MELT        liquid, swirling ground that rolls under you, blobs and mus

- `Realms.gd:38` `apply_cave()`: All the glowing materials get brighter as the world dims, and surge when the lights come on.
- `Realms.gd:88` `tint(zone: String, rng: RandomNumberGenerator)`: A tint that varies the look from one prop to the next.
- `Realms.gd:116` `ground(zone: String, x: float, z: float, zc: float, base: Color)`: The colour of the ground at a point.
- `Realms.gd:185` `melt_h(x: float, z: float, edge: float)`: How much the ground rolls in a melt stretch.
- `Realms.gd:190` `ground_material()`: The ground colour comes through almost as designed (the snow lighting is tuned for white and would wash it out): mostly emission, a little light for the slopes.
- `Realms.gd:466` `discover(id: String)`: Returns how many realms you have found so far if this one is new to you, else 0.
- undocumented: `has_roof`, `is_realm`, `pick`, `radius`, `material`, `mesh`, `_load`

### FlightRig.gd  (461 lines, 23 functions)  class `FlightRig`

Nod-energy flight prototype ("lift and rise, float, arise, slam down").  chin DOWN (held)        gather energy, shed speed        (the dip before the surge) chin snaps UP           BLAST: stored energy becomes speed + a few seconds of smashing through walls chin UP (held)          float: climb, trade a little speed for height chin snaps DOWN, high   SLAM: dive and crush everything on the ground around the impact lean / head turn        steer bob at a steady beat    GROOVE multiplier (blasts chained within ~3 s)  Input comes from GazeProvider.nod_state() (head pitch + how fast it is changing) and peek_offset() (steer); W/S or the arrow keys stand in for the chin when there is no camera.

- undocumented: `setup`, `_build_ground`, `_node_at`, `add_ring`, `add_wall`, `add_pillar`, `add_target`, `_spawn_chunk`, `_spawn_decor`, `_physics_process`, `_blast`, `_start_slam`, `_slam_impact`, `_crush`, `_crash`, `_fwd`, `_process_items`, `_free_node`, `_cleanup_behind`, `cleanup`, `_process`, `_draw_hud`, `_text`

### TouchControls.gd  (439 lines, 22 functions)  class `TouchControls`

On-screen controls for phones/tablets (also testable on desktop with F7). left side  : floating thumb-stick (move; pushing to the edge sprints) right side : drag to look (or, in hands-free mode, your finger IS your gaze) buttons    : FIRE, JUMP, KICK, SLIDE, weapon swap, EYES (hands-free), skills Everything is drawn in code. Shows itself only on touch devices (or after F7).

- undocumented: `_ready`, `_exit_tree`, `_player`, `_input`, `_layout`, `_button_pos`, `_press`, `_move`, `_release`, `_release_all`, `_apply_stick`, `_set_move`, `_axis`, `_tap`, `_button_hidden`, `_btn_down`, `_btn_up`, `toggle_camera`, `toggle_hands_free`, `_process`, `_draw`, `_text`

### DhDirector.gd  (416 lines, 19 functions)  class `DhDirector`

THE MUSIC DIRECTOR. It chooses what plays from what is happening, and moves between pieces with crossfades. The music files (ogg, made by tools/music_build.py) are not part of the game's download: each is fetched when it is first wanted (the page's own cache keeps it after that).  before the first molecule   one of the pre-trip tracks, by how fast the run is going: sunny and chill when it is easy, a lifting dream when it speeds up, hard when it is frantic from the first molecule     the Alien Warfare stems (Kamihamiha), playing together, locked, looping: the ambience is always there and each molecule brings in its own part, so the music is built from what you are holding. A level lost takes its part away. All six at the top bring in the FX layer: the full piece. after the peak, as it wears off   the comedown track, until the next molecule  When the files cannot be fetched (offline, a des

- `DhDirector.gd:58` `_vol(p: AudioStreamPlayer, db: float)`: Sends a volume only when it has moved enough to matter (changing a player's volume every frame was what dropped the game to 8 fps on the web).
- `DhDirector.gd:102` `secs_to_beat(div: float = 1.0)`: The seconds until the next beat of the stems (div 1 = a beat, 4 = a bar, 0.5 = an eighth note; the stems are in 4/4), or -1 when they are not playing: a sound that waits for it lands on the beat.
- `DhDirector.gd:116` `bar_pos()`: Where the stems are in their 16-bar loop, in bars (0 to 16), or -1 when they are not playing.
- `DhDirector.gd:125` `wave_at(ahead: float)`: The wave, 0 to 1, `ahead` seconds from now: it swells over six bars and falls away over two, over and over (so each wave comes on slowly and lets go quickly).
- `DhDirector.gd:272` `update(delta: float, st: Dictionary)`: state: avg (0..1 of all six molecules felt), holds (six values 0..1), dmt (0..1), exc (0..1, how hard the run is going), paused.
- undocumented: `credits_text`, `start`, `stop`, `_fetch`, `_mk_player`, `_on_sfx`, `_db`, `_play_track`, `_wind_make`, `_wind_mix`, `_band_for`, `_next_in`, `_loaded_stems`, `_start_stems`

### Telemetry.gd  (377 lines, 16 functions)  class `Telemetry`

Passive diagnostics, so that when a tester says "it sucked" we can see why. It never changes how anything works: once a second it writes down how the game, the phone / computer and the tracker were doing, names what looks wrong (too dark, backlit, bad angle, squinting, too far, phone shaking or lying flat, frame rate, GPU or CPU maxed, tracker slow or late, main thread stalls, camera problems), notes every gate, and sends it to the server in small batches. No pictures, no video, no names. The camera never leaves the device. Off with ?noshare, or the DIAGNOSTICS button on the pause screen.  Records (kind): env (once), tick (every second), incident (a problem that lasted 2 s or more, when it started and again when it ended), gate (every barrier), sum (running totals), sensor (camera track ended / muted), feltbad (the player pressed THAT FELT BAD: the last 40 seconds ride along).

- `Telemetry.gd:97` `flush_now()`: Hand what has been kept to the page's own sender (one call, not one per record).
- `Telemetry.gd:147` `_adapt_tracker(fps: float)`: ADAPTIVE TRACKER: when the game itself is slow the tracker is asked for fewer frames (the camera and model share the phone with the picture), and it is let go again when the game has room.
- `Telemetry.gd:260` `light_issue(lt: Dictionary)`: What is wrong with the light on the face, from one camera sample: "" (fine), "flat", "dark", "bright", "back" (the light is behind you), "side_l" / "side_r" (one half of the face is much brighter; l / r are the halves of
- `Telemetry.gd:282` `_classify(r: Dictionary, fps: float, f95: float, fmax: float, cpu_ms: )`: What looks wrong right now, in a few words each.
- `Telemetry.gd:352` `barrier(d: Dictionary)`: One barrier: which gate you went through, how far from its middle, whether your eyes had chosen one, how fast, and what was wrong at the time.
- `Telemetry.gd:364` `event(kind: String, d: Dictionary)`: A one-off record (the result of the follow-the-dot fit, ...).
- `Telemetry.gd:372` `felt_bad(why: String)`: THAT FELT BAD: keep the last 40 seconds with the note.
- undocumented: `_ready`, `set_rig`, `sharing`, `set_sharing`, `_post`, `_notification`, `_process`, `_pct`, `_tick`

### ThemeFX.gd  (368 lines, 8 functions)  class `ThemeFX`

Puts a Themes look onto a running level (sky, light, ground, trees, the full-screen pass), or onto the menu backdrop. ThemePost is the full-screen pass; with the psychedelic theme it also keeps a fading stack of recent frames (a SubViewport that is never cleared, onto which each finished frame is drawn at a low alpha) so that whatever moved leaves a rainbow echo.

- `ThemeFX.gd:29` `_process(delta: float)`: The desert: a sandstorm rolls in now and then and the world goes thick and gold.
- `ThemeFX.gd:49` `apply_to_level(level: MainLevel, rig: DownhillRig, id: String, intensity: f)`: Apply a theme to the Downhill level.
- `ThemeFX.gd:113` `apply_part(level: MainLevel, rig: DownhillRig, id: String, part: String)`: One piece of a look at a time, so a world can come on a layer at a time (and flicker in and out) instead of all at once: "sky" the sky, light, fog, the mountains and the mist; "ground" the snow; "veg" the trees, rocks an
- `ThemeFX.gd:179` `blend_env(level: MainLevel, id: String, k: float)`: The colours of a world mixed into the plain ones, k from 0 to 1: sky, fog, sun and light slide over instead of jumping.
- undocumented: `reset_storm`, `_snapshot`, `show_theme`, `current`

### Progression.gd  (347 lines, 24 functions)

Autoload "Prog": XP / levels, the skill tree, equipped gear, timed power-ups, kill-combo "style", coins, and saving. Everything that scales gameplay asks this node: Prog.mult("kick_damage"), Prog.flag("shockboots"), ...

- `Progression.gd:235` `can_buy(id: String)`: "" when purchasable, otherwise a human-readable reason.
- `Progression.gd:273` `try_loot(item: Dictionary)`: Equip if better than what's in that slot, else sell.
- undocumented: `_ready`, `_process`, `bonus`, `mult`, `flag`, `has_powerup`, `crit_chance`, `_recompute`, `_add`, `xp_needed`, `combo_mult`, `style_name`, `register_kill`, `add_xp`, `add_coins`, `skill_def`, `buy`, `respec`, `grant_powerup`, `reset`, `save_game`, `load_game`

### Roster.gd  (337 lines, 13 functions)  class `Roster`

The cast. Every character is data (DEFS) plus a primitive-shape builder. collider = [type, a, b]: capsule [r, h], sphere [r, 0], box [width, height].

- `Roster.gd:210` `build_visual(kind: StringName, def: Dictionary, visual: Node3D, body_mat:)`: Builds the standing visual.
- undocumented: `get_def`, `pick`, `mat`, `mi`, `sphere`, `cyl`, `box`, `capsule`, `torus`, `add_face`, `accessorize_head`, `dress_torso`

### ThemeBackdrop.gd  (330 lines, 12 functions)  class `ThemeBackdrop`

A small live 3D world behind the menu: a snowy (or neon, or digital) slope with trees, rocks and a few gates, seen from a camera that slowly drifts around it. It lives in its own SubViewport with its own World3D, so it never touches the game, and it is thrown away when the run starts.

- undocumented: `hill`, `_ready`, `_want_size`, `choose_theme`, `set_intensity`, `_process`, `_build_world`, `_recolor_gates`, `_terrain_mesh`, `_make_tree`, `_make_rock`, `_scatter`

### Lighting.gd  (316 lines, 12 functions)  class `DhLighting`

Everything that makes the light move in Downhill: - a day that passes as you ride (dawn pink, bright blue morning, golden hour, blue dusk with moonlight), driven by distance, alpine look only; - falling snow around the camera (alpine); - a light on the rider that warms to orange on a boost, cools to cyan under a shield and flares on a hit or a landing; - a few lights pooled on the next barrier's openings, coloured by what lies behind each one, so the gates glow on the snow before you reach them. Cheap by design (a handful of omni lights, no real-time shadows, a few hundred particles): it has to run on a phone.

- `Lighting.gd:103` `_apply_cave_exposure()`: Inside a roofed realm the whole picture is dimmed (the glowing things are boosted to make up for it, see Realms.apply_cave).
- `Lighting.gd:119` `sample_day(ph: float)`: The sky, fog and sun for a point in the day (0..1, wrapping).
- `Lighting.gd:159` `step_governor(dt: float, game_fps: float, trk_fps: float, cam_on: bool)`: Decide the tier from the two frame rates (the tracker's matters more: a slow game is a worse picture, a slow tracker is lost control).
- `Lighting.gd:203` `_weak_gpu()`: A laptop with an integrated graphics chip (Intel UHD / HD / Iris) has about a fifth of the pixel speed of a gaming card: it gets the same pixel budget as a phone, a little more.
- undocumented: `setup`, `_ease`, `_process`, `_governor`, `_apply_tier`, `_apply_day`, `_update_rider`, `_update_gate_lights`

### RunLog.gd  (306 lines, 17 functions)  class `RunLog`

A black box for every run: how the tracking, the steering, the phone and the frame rate behaved, on whatever device and in whatever conditions (desk, bus, streetcar). It is stored ON THE DEVICE ONLY (browser localStorage, or a file outside the web build) and nothing is ever sent anywhere: you read it back from the menu (copy it, or download it) and send it yourself if you want help. Location is never recorded: with the optional GPS toggle on, only the browser's reported SPEED and its accuracy are read, to notice a moving vehicle; the coordinates are never touched.

- `RunLog.gd:69` `start_gps()`: Optional: read the browser's reported speed (never the position) so the game can tell it is on a moving vehicle.
- `RunLog.gd:91` `on_vehicle(forced: bool)`: True while the device is on a moving vehicle (the player says so, or the speed reading says so).
- `RunLog.gd:200` `end_run(rig: RunRig, why: String)`: Called when a run ends (finish, restart, or a new course): writes the final entry.
- undocumented: `device`, `poll_gps`, `tick`, `summary`, `_tier_now`, `_tier_changes`, `reset`, `load_all`, `store`, `save_run`, `clear_all`, `line`, `copy_text`, `download`

### AudioHooks.gd  (305 lines, 13 functions)  class `AudioHooks`

Listens to Game.sfx_requested and plays procedurally synthesised sounds (no audio files needed). To use real audio, replace entries in `_streams` with `load("res://audio/squawk.ogg")` etc. -- the signal names stay the same.

- `AudioHooks.gd:112` `_free_later(pl: Node, stream: AudioStream, pitch: float)`: A voice is freed by a timer of its own length, not by its "finished" signal, and counted by hand: if a signal ever fails to come, the sounds do not run out.
- `AudioHooks.gd:190` `_tone(f0: float, f1: float, dur: float, vol: float, att: float = 0)`: A soft tone: a sine gliding f0 to f1 (exponentially) with a second and third harmonic mixed in (h2, h3) and any extra partials (a list of Vector2(multiple of the pitch, strength)), an attack of `att` seconds (never abrup
- `AudioHooks.gd:216` `_air(dur: float, lp0: float, lp1: float, vol: float, att: float =)`: Soft air: noise smoothed by two low-pass stages (the coefficient moves lp0 to lp1: small is dark, larger is brighter), a slow attack and a decay.
- `AudioHooks.gd:236` `_voice(dur: float, f0: float, f1: float, curve: float, wave: Vector)`: A general voice: the pitch glides f0 to f1 along a curve, sine/saw/square mixed (`wave`), noise with a low-pass that sweeps lp0 to lp1 (0..1 coefficients), an FM wobble (fm_hz, fm_depth in radians), tanh drive, an expone
- `AudioHooks.gd:261` `_mixp(parts: Array)`: Mixes several sounds that start together (the longest sets the length).
- undocumented: `_ready`, `_on_sfx`, `_synth`, `_build_new_voices`, `_sum_x`, `_cat`, `_noise_loop`, `_wav`

### DhJourney.gd  (304 lines, 18 functions)  class `DhJourney`

ALL DRESSED: one endless run that leads the player through every world. It looks and plays like the plain alpine run, and now and then a different world comes on, the way a trip does: first a shimmer behind and around the mountains (the sky flickers into the new colours and out again), then the ground, then the trees, with the full-screen effect spreading from the horizon over the whole picture, the ride changing with it and the music morphing. It holds for a while, then recedes the same way, back to plain. The first waves are brief and faint, later ones come on slower, last longer and go all the way to the full trip. Between waves there are long calm stretches, so it stays a surprise. Everything comes from the seed and the clock, so a 30 second run and a six hour one are both complete.

- `DhJourney.gd:112` `_plan_wave(w: int = -1)`: How long each part of the coming wave lasts, from how many have gone before.
- `DhJourney.gd:125` `_len_k()`: A short session has shorter waves and rests, a long one longer: half at ten minutes, one and a half from half an hour up.
- `DhJourney.gd:136` `_calm(w: int)`: The rest before wave `w`, from the script.
- `DhJourney.gd:142` `peek_world(k: int)`: The world `k` waves ahead of the one coming now (the first one or two are built while the run loads).
- `DhJourney.gd:147` `difficulty()`: 1.0 at the start, a little more each wave, and it never stops growing slowly: faster, more rocks, more going on.
- `DhJourney.gd:152` `hint()`: The first signs, in the last ten seconds of the calm: faint, round the horizon, and they stay there (and never grow) until the run builds up enough to carry the wave in.
- `DhJourney.gd:159` `nudge()`: A long run of pills: the calm is over, the next wave starts (it still waits out the first fifteen seconds of a run).
- `DhJourney.gd:165` `onset_k()`: How far the world has come on: a hint in the calm, rising through the onset, 1 at the peak, falling away through the offset.
- `DhJourney.gd:180` `wants_trip()`: The full effect (swirl, tracers, colours thrown apart) is for the strong waves and for the worlds that are made of it.
- `DhJourney.gd:185` `trip_floor()`: How far gone the picture should be: nothing between waves, building during the onset, and from the third wave on, right up to a full trip.
- undocumented: `start`, `_shuffle`, `_thr`, `_frac`, `tick`, `_set_phase`, `_stages`, `_pulse`

### GazeTestRig.gd  (279 lines, 16 functions)  class `GazeTestRig`

GAZE TEST: shows how precisely your eyes map to the screen. A dot lights up, you look at it for a moment, and the test records where the tracker thought you were looking. Lines run from each dot to the measured point, so the error is visible. It only MEASURES: nothing here is a calibration (the correction is learned silently while you play anything).  R restart   C centre (pins the automatic offset to the middle of the screen) Works with the camera (web), the UDP tracker, or the mouse (which should score near zero: a useful sanity check).

- `GazeTestRig.gd:121` `_tail()`: Mean distance of the measured point from the dot, as a fraction of the screen WIDTH (aspect-corrected).
- `GazeTestRig.gd:147` `reach()`: How far each direction actually reached: the measured gaze for targets in the left / right columns and top / bottom rows, next to where those targets are.
- undocumented: `setup`, `restart`, `target`, `_process`, `_median_point`, `mean_error`, `mean_offset`, `jitter`, `_input`, `_hud_scale`, `_text`, `_draw_hud`, `_fmt`, `cleanup`

### PlungerGrapple.gd  (233 lines, 13 functions)  class `PlungerGrapple`

LMB: fire a suction cup (hit-scan with a visible flight). On a prop/enemy it hooks on and reels the target to a hold point above and in front of you; LMB again FLINGS it, RMB just drops it. On world geometry it grapples YOU toward the hook point (jump or click to let go).

- undocumented: `_ready`, `_on_unequip`, `primary_pressed`, `alt_pressed`, `_fire`, `_physics_process`, `_on_impact`, `_hook_body`, `_step_body`, `_step_world`, `_release`, `_hide_tether`, `_draw_tether`

### EyeBias.gd  (213 lines, 9 functions)  class `EyeBias`

Automatic, invisible correction of the gaze point. No dots, no stare-at-this.  The geometry model (head pose + depth from iris size + the screen's real size) already maps the eyes to the screen with the right scale. What it cannot know is each person's constant offset (the eye's optical axis is about 5 degrees off the line of sight, the camera may sit off-centre, the head may be habitually tilted). That offset is steady, so it is learned while you play, from the one thing every game here has in common: the action is where you look.  * every ~1.5 s the median of your recent gaze is nudged toward `target` (screen centre, a little above the middle) * vertical offset also learns a slow link to HEAD PITCH and eyelid APERTURE (a head tilted back squints the eyes and shifts the vertical reading), by a small ridge regression over recent windows * a confirmed event (a blink on a target, the CENTE

- `EyeBias.gd:180` `apply(u: float, v: float, pitch: float, aperture: float)`: The corrected gaze point, always inside the screen.
- `EyeBias.gd:191` `anchor(raw: Vector2, pitch: float, aperture: float, screen_pos: Vec)`: A known fact: right now the player is looking at `screen_pos` (a blink on a target, the CENTER button).
- undocumented: `_median`, `add`, `_window_done`, `_pct`, `_update_scale`, `_fit_vertical`, `reset`

### Hud.gd  (213 lines, 10 functions)  class `Hud`

Crosshair, health/XP bars, wave + boss info, power-up timers, combo style, coins, big banners and a red damage flash. Everything drawn/built in code.

- undocumented: `_ready`, `_bind`, `set_level_name`, `_set_hint`, `_show_banner`, `_on_hurt`, `_make_label`, `_process`, `_notification`, `_draw`

### Prop.gd  (213 lines, 8 functions)  class `Prop`

Physics prop: crate, barrel, beach ball or rubber duck. Builds its own collider + mesh from `kind`. Use kind = &"custom" and add your own children (the enemy ragdoll parts do this). Hard impacts spawn "BONK!" pop-ups, and fast props knock enemies into ragdoll.

- undocumented: `make`, `_ready`, `_build`, `_add_beak`, `_integrate_forces`, `_on_body_entered`, `_meta`, `_tomato_hit`

### EyeDemoIntro.gd  (210 lines, 10 functions)  class `EyeDemoIntro`

Start screen for the face-control demos. Kept short on purpose: pick a mode, read three lines, press the big button. The button is a user gesture, so it can open the camera, go fullscreen and ask for landscape in one tap. Sizes scale with orientation / touch so it stays readable on a phone and nothing falls off the bottom (the whole panel scrolls if a very short window cannot fit it). The game is paused behind it.

- `EyeDemoIntro.gd:125` `_apply_unit()`: Fonts and spacing scale with how the screen is held: big in portrait (the viewport is very wide there, so everything shrinks on a phone), a bit bigger on a touch device in landscape.
- undocumented: `_ready`, `_reg`, `_label`, `_button`, `_current_mode`, `_refresh`, `_pick`, `_process`, `_start`

### PhoneMotion.gd  (190 lines, 7 functions)  class `PhoneMotion`

The phone's motion sensors, used to help the eye tracker. A hand-held phone tilts and shakes; the camera sees the face move and the iris-in-eye reading picks up part of that as a fake glance. 1. correct(): learns, while you play, how much of the iris reading follows the phone's tilt (a two-variable regression on the short-term tilt, per axis) and subtracts it. A steady phone has ~0 short-term tilt, so real glances pass through untouched. 2. shake: how hard the phone is moving right now (0..1). A grab or bump freezes the gaze for a moment instead of throwing the board at a gate. 3. tilt_x / tilt_y: the phone's tilt in screen terms (degrees), for an optional world-lock camera. 4. buzz(): haptics where the browser allows it (Android). Everything is a no-op where there is no sensor (desktop), so callers never need to check.

- `PhoneMotion.gd:69` `poll(delta: float)`: Call every frame; it samples at ~30 Hz.
- `PhoneMotion.gd:90` `feed(beta: float, gamma: float, ang: int, gyro: Vector3, dt: floa)`: One sensor sample: beta / gamma in degrees, the screen orientation angle, and the gyro rates in deg/s.
- `PhoneMotion.gd:126` `settling()`: True while the way the phone is held is changing (shifting in a seat, lifting it, settling into the lap): the eyelid baseline lags behind that, so squint / wide-eye detection waits instead of firing on it.
- `PhoneMotion.gd:134` `holding()`: True while the phone is being moved hard enough that the gaze reading should be held, not trusted.
- `PhoneMotion.gd:139` `correct(e: Vector2)`: The iris-in-eye reading with the part that follows the phone's tilt taken out.
- `PhoneMotion.gd:186` `buzz(pattern: Array)`: A buzz in the hand. pattern: milliseconds on / off / on ...
- undocumented: `start`

### SkillTreeUI.gd  (180 lines, 7 functions)  class `SkillTreeUI`

Pause-menu skill tree + equipped gear. Tab (or Back on a pad) toggles it. Mouse click or gamepad focus + A buys a rank. Built entirely in code.

- undocumented: `_ready`, `_unhandled_input`, `open_menu`, `close_menu`, `_on_buy`, `_describe`, `_refresh`

### Pickup.gd  (179 lines, 8 functions)  class `Pickup`

Loot on the floor: coins, rubber-chicken health, power-ups and gear (with a rarity-coloured loot beam). Pops out of the dead enemy, then magnetises to you.

- `Pickup.gd:19` `attract()`: Hands-free: staring at loot pulls it to the player regardless of distance.
- undocumented: `spawn`, `_ready`, `_build_powerup`, `_build_gear`, `_process`, `_physics_process`, `_collect`

### SplashView.gd  (168 lines, 9 functions)  class `SplashView`

The welcome screen: the emblem (a ring, two peaks, and the sun as an iris), the title, the promise, and eight one-word pictograms that say what the eyes do. Drawn in code so it matches any screen shape and stays sharp. It sits over the live 3D backdrop; any tap, click or key moves on to the settings.

- `SplashView.gd:121` `_disc(c: Vector2, r: float, fill: Color, ink: Color, ow: float)`: One cartoon badge picture in a box of about +-34 units, scaled by u: fat shapes, bright fills, dark outlines, a face or a burst in each so it reads at a glance.
- undocumented: `_ready`, `_process`, `_gui_input`, `_input`, `_finish`, `_draw`, `_star`, `_icon`

### SweepTest.gd  (167 lines, 8 functions)  class `SweepTest`

SWEEP TEST (?level=gaze&sweep): a dot moves across the screen on a known path while every raw tracker reading is logged at full rate. With the truth known, each stage of the gaze (iris inside the eye, the geometry reading, the final cursor, the head angles) can be scored for how well it follows the eyes and how noisy it is. It measures only: nothing here calibrates or changes the tracker.  Phases: side-to-side glide, side-to-side jumps, up-and-down glide, then "turn your head, keep looking at the middle" (how much a head turn leaks into the gaze).

- `SweepTest.gd:72` `make_row(id: String, tt: float, target: Vector2, d: Dictionary, P: Ob)`: One log row from a tracker packet: every number the tracker sent, plus where the dot was and what each later stage made of it.
- undocumented: `_ready`, `phase_id`, `target_at`, `_num`, `_flush`, `_process`, `_draw`

### Game.gd  (158 lines, 13 functions)

Autoload "Game": global event bus, collision-mask constants, and runtime InputMap registration (so the project works with zero editor setup).  Audio / UI hook-ups: anything can call Game.popup() or Game.sfx(); the HitNotifierUI and AudioHooks nodes subscribe to the signals below.

- `Game.gd:68` `rumble(weak: float, strong: float, duration: float = 0.15)`: Controller rumble (no-op without a gamepad).
- `Game.gd:74` `popup(text: String, world_pos: Vector3, color: Color = Color.WHITE)`: Spawn a comedic pop-up word at a world position.
- `Game.gd:79` `banner(text: String, color: Color = Color.WHITE, seconds: float = 2)`: Big centered announcement ("WAVE 3", "LEVEL UP!").
- undocumented: `_ready`, `_input`, `_set_pad`, `sfx`, `add_chaos`, `_register_inputs`, `_k`, `_m`, `_a`, `_b`

### HeadCoach.gd  (150 lines, 9 functions)  class `HeadCoach`

Works out, from the camera image alone (no dots), where your head should sit so the eyes stay readable, and how far off that you are right now.  Why it matters: tilting the head back (for example to look through the lower part of progressive lenses) narrows the eye opening and shrinks the visible iris, so gaze is least precise exactly when you look down. The ideal pose is learned while you play: it is the head pose you hold when your eyes are open widest. Pure logic, unit tested.

- `HeadCoach.gd:43` `seed(pitch: float, yaw: float, roll: float)`: Start from a pose measured earlier (EyeLab saves one); it is refined as you play.
- `HeadCoach.gd:99` `issues()`: Problems right now, most important first: [{"id", "text"}].
- `HeadCoach.gd:120` `message(t: float)`: A hint to show now ("" most of the time): only after you have been off for a while, and not more than once per NAG_GAP.
- undocumented: `reset`, `add`, `deviation`, `take_good_event`, `_med_recent`, `_median`

### Zone.gd  (149 lines, 4 functions)  class `Zone`

Interactive floor/volume mechanics used by the levels. bounce  trampoline: launches anything that touches it (`launch` vector) boost   speed strip: shoves the player along `launch` direction slip    ice / wet floor: player loses traction, enemies trip sticky  goo / water: slows player and enemies lava    burns player + enemies, bounces them out, floats props vent    updraft column: lifts player and props

- undocumented: `_ready`, `_on_enter`, `_physics_process`, `_lava`

### ShockRifle.gd  (141 lines, 11 functions)  class `ShockRifle`

UT99-style Shock Rifle. primary : instant shock beam (hitscan), aim-assisted alt     : slow shock CORE. Shoot the core with the beam for a SHOCK COMBO. Built entirely from primitives; no art assets.

- undocumented: `_ready`, `_physics_process`, `is_ready`, `primary_pressed`, `primary_held`, `alt_pressed`, `fire_at`, `_dir_to`, `_beam`, `_core`, `_draw_beam`

### Projectile.gd  (139 lines, 5 functions)  class `Projectile`

Rockets and shock cores. Swept-ray movement (no tunnelling), optional soft homing, explosion via Fx.shockwave. A shock core hit by a shock-rifle beam detonates as a huge SHOCK COMBO.

- `Projectile.gd:101` `combo()`: Shock combo: a beam through a core makes everything near it bad news.
- undocumented: `fire`, `_ready`, `_physics_process`, `_explode`

### LeafBlower.gd  (131 lines, 9 functions)  class `LeafBlower`

Hold fire: a cone-shaped Area3D pushes everything in front of you with a constant per-frame impulse. Aim at the ground to rocket-jump / hover.

- undocumented: `_ready`, `_on_stats`, `_build_cone`, `_build_particles`, `_on_unequip`, `primary_pressed`, `primary_released`, `_set_firing`, `_physics_process`

### Draw2D.gd  (127 lines, 7 functions)  class `Draw2D`

Circles, arcs, polylines and filled polygons for HUD drawing that cost the graphics chip nothing extra.  Why this exists: in the browser renderer, CanvasItem.draw_circle / draw_arc / draw_polyline / draw_colored_polygon each make a brand-new vertex buffer (and a vertex array) on the graphics chip every time they are drawn, and throw it away at the next redraw. A HUD that redraws every frame with a hundred of them makes and destroys a hundred buffers a frame, which on a laptop's built-in graphics takes longer than drawing the whole 3D scene. These helpers draw the same shapes from quads and one shared disc texture, which the renderer batches without allocating anything.

- `Draw2D.gd:34` `circle(ci: CanvasItem, pos: Vector2, r: float, col: Color)`: A filled circle.
- `Draw2D.gd:51` `arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, )`: A ring section, same arguments as CanvasItem.draw_arc.
- `Draw2D.gd:100` `pline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: floa)`: Connected line segments, same arguments as CanvasItem.draw_polyline.
- `Draw2D.gd:113` `poly(ci: CanvasItem, pts: PackedVector2Array, col: Color)`: A filled polygon, same arguments as CanvasItem.draw_colored_polygon.
- undocumented: `_disc_for`, `_quad`, `_feather`

### Loot.gd  (127 lines, 6 functions)  class `Loot`

Procedural gear: 3 slots x 5 rarities x random stat affixes, with silly names.

- undocumented: `rarity_color`, `rarity_name`, `generate`, `rating`, `sell_value`, `describe`

### RocketLauncher.gd  (123 lines, 13 functions)  class `RocketLauncher`

UT99-style Rocket Launcher. primary : one rocket. Soft homing on the assisted target for touch / gaze. alt     : HOLD to load up to 6 rockets, release to fire them in a fan. Built entirely from primitives; no art assets.

- undocumented: `_ready`, `_on_unequip`, `_physics_process`, `is_ready`, `primary_pressed`, `primary_held`, `alt_pressed`, `alt_held`, `alt_released`, `fire_at`, `_assisted_dir`, `_assist_target`, `_launch`

### TrailCurve.gd  (115 lines, 8 functions)  class `TrailCurve`

The trail winds. Everything the game DECIDES still happens on a straight strip (x across, z down the hill): the course, the steering, the collisions and every test are unchanged. This class is only about what you SEE: it lays that strip along a curving line across the mountain, so the ground, the trees, the gates, the board and the camera all swing left and right through long bends, and the peaks and the sun wheel around you as the trail turns.  strip point (x, y, z)  ->  world point = centre(s) + x * right(s),  height unchanged,  with s = -z the distance down the trail  The line turns by at most about one degree every 5.5 m (a radius over 300 m), which keeps the inside of a bend from folding over itself: the ground is drawn 150 m either side of the middle. The first 120 m are straight, so a run starts the way it always did.

- `TrailCurve.gd:23` `setup(seed_n: int, strength: float = 1.0)`: Lay out a new line. `strength` 1 is the normal amount of winding, 0 is dead straight.
- `TrailCurve.gd:65` `heading(z: float)`: Heading of the trail at strip z (radians).
- `TrailCurve.gd:70` `w(p: Vector3)`: A strip point as a world point.
- `TrailCurve.gd:78` `strip_near(p: Vector3, z_lo: float, z_hi: float)`: The other way: a world point back to a strip point, looked for only between strip z_lo and z_hi (the nearest stored point of the line along the trail, then across and along from it).
- `TrailCurve.gd:97` `basis_at(z: float)`: How things standing at strip z are turned: the strip's "down the hill" (-z) becomes the trail's direction there.
- `TrailCurve.gd:104` `xf(t: Transform3D)`: A strip transform (where something stands and how it is turned) as a world transform.
- `TrailCurve.gd:111` `dir(v: Vector3, z: float)`: A strip direction at strip z as a world direction.
- undocumented: `_at`

### Saccades.gd  (114 lines, 5 functions)  class `Saccades`

Real looks versus noise, in a slow, noisy, lopsided signal (a webcam iris reading at 10 to 15 frames a second). Noise spread evenly around the true gaze averages out. A look is different: a jump one way that SETTLES somewhere new. So a jump is accepted only if it carries on the same way for two frames in a row and clears a threshold that grows with how jittery YOUR signal is. A one-frame spike that comes back (a blink, a glance down, a glitch) is counted and thrown away. Each accepted jump is an event with a direction and a size, usable as intent: "he looked right, now".

- `Saccades.gd:37` `push(t: float, x: float)`: Feed one fresh reading.
- `Saccades.gd:88` `pending()`: True from the moment a look is accepted until it has stayed long enough to be certain (or has been taken back).
- undocumented: `threshold`, `recent`, `reset`

### WeaponManager.gd  (111 lines, 6 functions)  class `WeaponManager`

Owns every WeaponBase child, handles switching and routes fire input. Sits under the player's Camera3D so weapons inherit camera shake/recoil.

- undocumented: `_ready`, `current_weapon`, `block_input`, `select`, `_unhandled_input`, `_process`

### WaveDirector.gd  (110 lines, 8 functions)  class `WaveDirector`

Endless escalating waves. Every 5th wave is a boss wave. Clearing a boss wave advances to the next themed level (see MainLevel.advance_level).

- undocumented: `_ready`, `abort_wave`, `alive`, `remaining`, `_process`, `start_wave`, `_clear_wave`, `spawn_enemy`

### EyeMix.gd  (107 lines, 3 functions)  class `EyeMix`

One steady "eyes left / right" number for phones, made from the three sideways eye readings the tracker gives every frame: bx   the face model's own "eye look" outputs x    the model's iris point between the eye corners lx   our iris-edge fit inside the eye opening (the precise one on a laptop; on a phone the eye is only a few pixels wide and it jitters)  Each reading is centred on its own median and divided by the size of this player's own glances, so the three are in the same units, then they are averaged with weights = (glance size / jitter while the eyes rest) squared. Whichever reading is steadiest FOR THIS PLAYER counts most: without glasses that is usually bx, with glasses the three end up closer. Nothing is fitted to a target, so it needs no calibration step.  Measured on two phone recordings of the sweep test (jumping dot): jitter while looking steadily 2.2% / 3.4% of the screen

- `EyeMix.gd:42` `add(bx: float, x: float, lx: float)`: One tracker frame. Pass NAN for a reading that is missing this frame (the iris-edge fit drops out when the eye is nearly shut).
- undocumented: `reset`, `_learn`

### Fx.gd  (102 lines, 3 functions)  class `Fx`

Static helpers for juicy effects: confetti bursts and radial shockwaves.

- undocumented: `_world`, `confetti`, `_ring`

### GazeKalman.gd  (100 lines, 2 functions)  class `GazeKalman`

One axis of the gaze point as a Kalman filter: position and velocity, in screen fractions.  Why not the One Euro filter alone: the camera delivers 12-15 readings a second but the game draws 60. One Euro holds the last value between readings (a staircase) and has to pick between "calm when still" and "quick when moving" with two knobs. This one keeps a velocity, so between readings it keeps gliding the way your gaze was going (the velocity fades quickly, so it never runs away), and each new reading is blended in by how much we trust it against how sure we already were.  Eyes do not drift, they jump (saccades): a jump of the gaze looks like a wildly wrong reading to a plain Kalman filter, which then lags behind it for half a second. So a reading far outside what the filter expected is held at arm's length once (it could be a glitch), and if the NEXT reading agrees (same side, also far), th

- `GazeKalman.gd:38` `step(z: float, dt: float, fresh: bool)`: Advance by dt seconds; `z` is the newest reading when `fresh`, otherwise only the prediction moves.
- undocumented: `reset`

### DhProgress.gd  (99 lines, 10 functions)  class `DhProgress`

The player's progress in Downhill: points earned in runs turn into XP, XP into a level, and levels open up the looks and the sandbox toys one at a time, so the game starts simple and grows. Kept on this device only.

- `DhProgress.gd:63` `progress()`: XP into this level and XP the level needs: for the bar in the menu.
- `DhProgress.gd:80` `add(a: float)`: Adds XP; returns the list of names opened by it (empty if the level did not change).
- undocumented: `_load`, `_save`, `get_xp`, `level_of`, `level`, `need`, `unlocked`, `unlock_all`

### AimAssist.gd  (80 lines, 3 functions)  class `AimAssist`

Aim assist that scales with how imprecise the input device is.  Why it exists: a webcam gaze is only good to ~3-5 degrees, a thumb on a phone covers the target it is aiming at, and a 1080p screen at arm's length is about 24 pixels per degree. A mouse needs almost nothing; gaze needs a lot. The assist only ever bends a shot toward an enemy you are already roughly aiming at (inside the cone) and that you can actually see (line of sight).

- `AimAssist.gd:36` `find(tree: SceneTree, cam: Camera3D, origin: Vector3, dir: Vector)`: Best visible enemy within `cone` degrees of the ray.
- `AimAssist.gd:75` `assist(tree: SceneTree, cam: Camera3D, origin: Vector3, dir: Vector)`: Aim direction after assist (unchanged when nothing is in the cone).
- undocumented: `cone_deg`

### WeaponBase.gd  (80 lines, 16 functions)  class `WeaponBase`

Extensible weapon base class. Subclass it, override the virtual hooks, drop the scene under the Camera's WeaponManager and it shows up as a new slot.

- `WeaponBase.gd:18` `setup(p_player: PlayerController, p_camera: Camera3D)`: Called once by WeaponManager.
- `WeaponBase.gd:59` `fire_at(_point: Vector3, _node: Node3D, _force: bool = false)`: Hands-free / lock-on firing: shoot at a world point (and optional target node).
- `WeaponBase.gd:75` `raycast(max_dist: float, mask: int)`: Ray from the crosshair.
- undocumented: `equip`, `unequip`, `_on_equip`, `_on_unequip`, `primary_pressed`, `primary_held`, `primary_released`, `alt_pressed`, `alt_held`, `alt_released`, `is_ready`, `aim_origin`, `aim_direction`

### Mats.gd  (72 lines, 6 functions)  class `Mats`

The few kinds of plain material the game is allowed to make.  Why: every different combination of material switches (lit or not, see-through or not, two-sided or not, glow or not, vertex colours or not) is a separate shader program, and the browser builds each one, in several versions, while the page is frozen at start-up. Two materials that differ only in a colour or a number share a program; two that differ in a switch do not. So every plain material starts from one of these, with the switches already set the same way, and only changes colours and numbers afterwards. A switch that is on but not needed costs nothing visible: glow set to black adds nothing, vertex colours on a mesh that has none read as white.

- `Mats.gd:11` `lit()`: Lit, solid. Vertex colours on, two-sided, glow on (black until you set it).
- `Mats.gd:21` `flat()`: Unlit, solid: the colour you give it is the colour you see.
- `Mats.gd:29` `glass(two_sided: bool = false)`: Unlit, see-through. `two_sided` for flat sheets and walls you can be on either side of; leave it off for closed shapes (a see-through ball would show its back too).
- `Mats.gd:38` `glow()`: Unlit, see-through, adds its colour to what is behind it (glows, rings, beams).
- `Mats.gd:50` `keep_alive(extra: Array = [])`: Holds one material of every kind for the whole session.
- `Mats.gd:65` `shader(code: String)`: One Shader object per piece of shader code, however many materials use it (two Shader objects with the same code are built twice).

### DhPacer.gd  (68 lines, 6 functions)  class `DhPacer`

THE PACER. A session has a shape, stretched to whatever length the player chooses (10 minutes to 8 hours, then it goes round again, a little higher each time):  settle      the first few minutes: calm, nothing hostile, the first molecules offered come up     a slow, wave-like climb: each wave a bit higher than the last peak        everything near the top at once: the window plateau     held, then easing comedown    a long, soft way down to calm  The pacer holds a TARGET level (0..1: how much of the six the session should be carrying right now). It does not hand anything out: it nudges how often molecules turn up (more when the player is behind the curve, fewer when ahead of it), so a careful player and a clumsy one both ride roughly the same arc, and losing levels to hazards is something to win back, not the end. It also sets how hostile the course is in each phase. It models no real sub

- `DhPacer.gd:48` `target()`: How much of the six the session should be carrying now, 0..1.
- `DhPacer.gd:57` `spawn_bias(avg: float)`: How often molecules turn up, as a multiple of normal: more when the player is behind the curve, fewer when ahead of it.
- `DhPacer.gd:62` `hazard_k()`: How hostile the course is now, as a multiple of normal: none at all for the first twenty seconds.
- undocumented: `tick`, `_phase`, `phase_name`

### HitNotifierUI.gd  (57 lines, 2 functions)  class `HitNotifierUI`

Full-screen overlay that spawns animated comic-book words ("YEET!", "BONK!", "SLIP!") at the screen position of a world-space hit. Subscribes to Game.popup_requested, so any gameplay code can fire one with Game.popup().

- undocumented: `_ready`, `spawn_popup`

### Hazard.gd  (54 lines, 4 functions)  class `Hazard`

Banana peel. Whoever steps on it (except its owner) slips: the player stumbles and takes a little damage, enemies ragdoll.

- undocumented: `make_peel`, `_ready`, `_process`, `_on_body_entered`

### RScale.gd  (33 lines, 2 functions)  class `RScale`

Render scale: how many pixels the game draws, as a fraction of the screen's.  In the browser this must NOT be Viewport.scaling_3d_scale. With that below 1 the browser renderer copies the depth buffer from the small picture to the full-size one every frame, and a scaled depth copy has no fast path on Windows graphics drivers (measured on an Intel UHD 620: 25 to 40 ms a frame, 57 fps with the copy skipped against 21 with it). So in the browser the whole canvas is made smaller instead and the browser stretches it to the window, which costs nothing: the page's devicePixelRatio is what the engine sizes its canvas from, and it re-reads it every frame.

- `RScale.gd:30` `full_px()`: The canvas's pixel count at full scale.
- undocumented: `set_scale`

### OneEuro.gd  (28 lines, 3 functions)  class `OneEuro`

One Euro filter: smooth when still, responsive when moving. Ideal for jittery webcam gaze. Units are screen-fractions per second.

- undocumented: `_alpha`, `filter`, `reset`

### FaceTone.gd  (16 lines, 1 functions)  class `FaceTone`

The tone map behind the emergent face: 120 x 180, light = bright. Made from tools/face/tone_woman1.png (any grayscale portrait works: see tools/face/make_tone.py).

- undocumented: `texture`

### MolData.gd  (14 lines, 0 functions)  class `MolData`

Ball-and-stick coordinates (angstroms, centred, long axis along x) for six phenethylamines from Alexander Shulgin's PiHKAL. Made by tools/mol_gen.py: do not edit by hand.


## 4. Tunable constants with comments (the numbers that define the feel)


**RunRig.gd**

- `RunRig.gd:17` `PULL_RAMP = 3500.0            # metres until the hill is at fu`: metres until the hill is at full pull
- `RunRig.gd:18` `AIM_LINGER = 0.14             # seconds your eyes must stay on `: seconds your eyes must stay on an opening before it latches
- `RunRig.gd:20` `AIM_MAX_DIST = 125.0          # kept at the distance the tracking`: kept at the distance the tracking was tested with (the realms commit had raised it to 190)
- `RunRig.gd:21` `START_CALM = 2                # the first segments are open sno`: the first segments are open snow
- `RunRig.gd:201` `CAL_XS = [0.0, -0.75, 0.75, 0.0, 0.75, -0.75, 0.0]         `: learning: the dot JUMPS between the middle, the left and the right (it does not glide)
- `RunRig.gd:2123` `TRAIL_TURN_LEN = 30.0         # metres: the trail swings one way an`: metres: the trail swings one way and back every 2 * PI * this (a turn about every 95 m)
- `RunRig.gd:2127` `TRAIL_SPEED = 23.5           # m/s`: m/s
- `RunRig.gd:2170` `SWELL_K = 0.35          # how much the rolling swells count:`: how much the rolling swells count: they are what hides the path ahead (a crest on a swell, every 100 m or so), so they are small
- `RunRig.gd:2499` `PITCH_EASE_M = 110.0          # metres over which one stretch's s`: metres over which one stretch's slope eases into the next
- `RunRig.gd:2505` `STAGE_CYCLE = [0.0, 0.0, 0.0, 0.5, 1.0, 1.0]          # in rows `: in rows (about 180 m each): 0 mild, 0.5 build, 1 steep
- `RunRig.gd:3557` `SLIDE_MAX = 30.0                 # m/s sideways at the most wh`: m/s sideways at the most when the board crosses over to what the eyes chose
- `RunRig.gd:3558` `TRAIL_VMAX = 30.0                 # m/s on the forest trail (10`: m/s on the forest trail (108 km/h) before boosts
- `RunRig.gd:3559` `SPEED_CAP = 57.0              # a boost never pushes you past `: a boost never pushes you past this (the hill alone reaches about 51 m/s)
- `RunRig.gd:4254` `FLOW_WINDOW = 5.0             # seconds of grace at the bottom l`: seconds of grace at the bottom level
- `RunRig.gd:4255` `FLOW_WINDOW_MIN = 2.6         # and at the top`: and at the top
- `RunRig.gd:4256` `FLOW_DRAIN_STEP = 0.7         # seconds per level once the clock has`: seconds per level once the clock has run out
- `RunRig.gd:4299` `POP_RISE = 0.3                # how far above your own restin`: how far above your own resting level the eyebrows must go
- `RunRig.gd:4300` `POP_VY = 6.2                  # m/s off the snow: about 1.2`: m/s off the snow: about 1.2 s in the air and 1.9 m up
- `RunRig.gd:4968` `WALL_FAR = 80.0               # the barrier ahead starts pull`: the barrier ahead starts pulling you into a gate this far away ...
- `RunRig.gd:4969` `WALL_NEAR = 34.0              # ... and pulls with full streng`: ... and pulls with full strength from here
- `RunRig.gd:7558` `FOOD_NAME = {"boost": "CRYSTAL", "shield": "CAGE", "mult": "RI`: the pickups are kit shapes now, not food
- `RunRig.gd:7854` `VX_LAUNCH = 46.0                   # m/s the vortex brings you`: m/s the vortex brings you to by the lip
- `RunRig.gd:7856` `VX_TRAIL = 37.0                   # m/s the trail swirl build`: m/s the trail swirl builds up to by the lip
- `RunRig.gd:7857` `VX_REACH = 130.0                   # m before the foot of the`: m before the foot of the ramp where the swirl starts to take hold
- `RunRig.gd:8569` `LK_GAP_M = 360.0                 # metres between one set pie`: metres between one set piece and the next (about every ten seconds at a good pace)
- `RunRig.gd:8570` `LK_TUBE_L = 70.0                 # how far down the hill the t`: how far down the hill the tube carries you
- `RunRig.gd:8571` `LK_RAIL_L = 30.0                 # the rail it lands you on`: the rail it lands you on
- `RunRig.gd:8572` `LK_SHIFT = 14.0                  # the tube carries you this `: the tube carries you this far across the trail, toward the other side
- `RunRig.gd:8573` `LK_FOLLOW_M = 85.0               # how far past the rail's end t`: how far past the rail's end the next piece stands
- `RunRig.gd:8722` `ORB_DWELL = 0.36          # seconds of looking to fill one`: seconds of looking to fill one
- `RunRig.gd:8723` `ORB_RANGE = 70.0          # m ahead where an orb can be collec`: m ahead where an orb can be collected
- `RunRig.gd:9647` `MOL_GAP_M = 250.0          # metres between molecule rows at a`: metres between molecule rows at an even pace (about seven seconds of riding)
- `RunRig.gd:10500` `HUD_MIN = true                    # on screen in play: point`: on screen in play: points, speed, frame rates.
- `RunRig.gd:10515` `AIR_G_K = 2.1                    # how much harder gravity p`: how much harder gravity pulls in the air on the trail: flights of two to two and a half seconds
- `RunRig.gd:11784` `BEACON_MAX_DIST = 190.0       # markers appear as soon as the barrie`: markers appear as soon as the barrier does
- `RunRig.gd:11785` `BEACON_LEFT = 0.17            # where the outermost markers sit `: where the outermost markers sit across the screen
- `RunRig.gd:11787` `GLANCE_WINDOW = 0.35          # seconds`: seconds
- `RunRig.gd:11788` `GLANCE_MOVE = 0.07            # the look must cross this share o`: the look must cross this share of the screen within the window to count as a glance
- `RunRig.gd:11789` `GLANCE_HOLD = 0.7             # seconds a glance stays "fresh" f`: seconds a glance stays "fresh" for changing the choice
- `RunRig.gd:12259` `POS_FACE_IDEAL = 0.30         # face width as a share of the camera`: face width as a share of the camera picture when the distance is right
- `RunRig.gd:12262` `POS_ANGLE_DEG = 20.0          # a head turned or tipped this far p`: a head turned or tipped this far puts the dot on the ring
- `RunRig.gd:12263` `GUIDE_RAISE_S = 8.0           # seconds a set-up problem must last`: seconds a set-up problem must last during play before the ring comes back
- `RunRig.gd:12308` `MOL_PERK = ["GLINTS", "POINTS", "BOOST", "RAMPS", "SLING", "S`: what each one does (the same order as MolData.ORDER): more glints, more points, stronger boost pads, more ramps, stronger slingshots, faster

**DownhillRig.gd**

- `DownhillRig.gd:18` `ROW_GAP = 180.0          # metres of hill per barrier on ave`: metres of hill per barrier on average (was 125): more room to choose, to carve and to meander
- `DownhillRig.gd:22` `AHEAD = 400.0          # how far down the hill is built ah`: how far down the hill is built ahead of the rider (was 520: the haze hides everything past about 340 m, so the rest was built early for nothing)
- `DownhillRig.gd:33` `ASSIST = 0.75        # how hard the line your eyes set pull`: how hard the line your eyes set pulls the board (your lean still wins)
- `DownhillRig.gd:34` `LATE_DIST = 34.0     # a late gate opens at least this close .`: a late gate opens at least this close ...
- `DownhillRig.gd:35` `SHUT_DIST = 26.0     # a false opening slams shut at least thi`: a false opening slams shut at least this close
- `DownhillRig.gd:36` `LATE_WARN = 1.5      # ... and never later than this many seco`: ... and never later than this many seconds before you arrive (eyes need about 0.7 s to read and commit)
- `DownhillRig.gd:41` `CALM_ROWS = 5               # the first rows are all open: set`: the first rows are all open: settle in
- `DownhillRig.gd:42` `LANE_ZONE = 0.13            # dead zone: look further than thi`: dead zone: look further than this (screen fraction) left or right of the middle to step a lane
- `DownhillRig.gd:43` `LANE_MARGIN = 0.04          # gate mode: your eyes must be this `: gate mode: your eyes must be this much (screen fraction) nearer another gate before it can win
- `DownhillRig.gd:44` `LANE_DWELL = 0.25           # seconds of looking aside before t`: seconds of looking aside before the first step
- `DownhillRig.gd:45` `LANE_REPEAT = 0.60          # seconds between further steps whil`: seconds between further steps while you keep looking aside
- `DownhillRig.gd:46` `PHONE_CENTRE_S = 3.5       # seconds: how quickly the centre of the`: seconds: how quickly the centre of the look follows the reading on a hand-held phone
- `DownhillRig.gd:47` `LANE_HEAD_GAIN = 0.012      # screen fraction per degree of head tu`: screen fraction per degree of head turn: turning toward where you want to go helps the eyes
- `DownhillRig.gd:48` `STEER_SCALE_MIN = 0.10       # STEER control: a look this far (scree`: STEER control: a look this far (screen fraction) from your own centre is full steering at most; never more sensitive than this
- `DownhillRig.gd:53` `LANE_COMMIT_T = 2.2         # seconds before a wall that its lane `: seconds before a wall that its lane is locked
- `DownhillRig.gd:54` `LANE_GRACE = 1.5            # seconds the line is held after tr`: seconds the line is held after tracking is lost
- `DownhillRig.gd:145` `GATE_ROW_MIN = 22.0             # choose among the gates of the f`: choose among the gates of the first wall at least this far ahead (near gates are wide apart on screen)

**GazeProvider.gd**

- `GazeProvider.gd:105` `HEAD_MIN_SIGMA = Vector2(0.03, 0.02)       # radians: ~1.7 deg turn`: radians: ~1.7 deg turn / ~1.1 deg nod = one 'unit' of movement
- `GazeProvider.gd:122` `PEEK_M_PER_RAD = 8.6                           # head turn: 10 degr`: head turn: 10 degrees ~ 1.5 m of lean
- `GazeProvider.gd:123` `PEEK_YAW_MIX_PHONE = 0.6                       # held phones jiggle the`: held phones jiggle the face in the frame, so lean on head TURN more
- `GazeProvider.gd:155` `GEO_TARGET = Vector2(0.2, 0.2)    # one standard deviation of y`: one standard deviation of your gaze maps to this fraction of the screen
- `GazeProvider.gd:194` `LID_HOLD = 0.18                # seconds a squint / wide look`: seconds a squint / wide look must last (a blink is shorter)

**LevelBuilder.gd**

- `LevelBuilder.gd:62` `PEEK_RADIUS = [1.0, 1.2, 0.7]        # cover radius per station `: cover radius per station type (rock, fat rock, pillar)
- `LevelBuilder.gd:63` `PEEK_LEAN = [1.0, 1.4, 0.8]          # how far you must lean t`: how far you must lean to reveal a baddy, per station type

**KitEye.gd**

- `KitEye.gd:26` `RECENTRE_S = 20.0          # the resting place of the iris drif`: the resting place of the iris drifts as the phone is re-gripped: the fitted look follows it this slowly
- `KitEye.gd:50` `Z_IN = 0.5                 # more than half way to a side`: more than half way to a side target: that side
- `KitEye.gd:51` `Z_OUT = 0.3                # back inside this: the middle `: back inside this: the middle again
- `KitEye.gd:67` `AUTO_M = 0.018              # where the iris rests, typical`: where the iris rests, typical (measured on a phone and on a laptop: 0.014 to 0.021)
- `KitEye.gd:68` `AUTO_D = 0.03               # how far it moves for a look t`: how far it moves for a look to a side, small (a phone: 0.026 to 0.034; a laptop moves about 3x that)

**Realms.gd**

- `Realms.gd:44` `SIGN_COL = Color(0.95, 0.55, 1.0)          # every realm gate`: every realm gate glows the same shimmering violet: you learn the glyphs, not the colours
- `Realms.gd:63` `HANGING = ["vine", "stalactite"]          # these hang from `: these hang from the roof
- `Realms.gd:64` `FLOATING = ["jelly"]                      # these drift in th`: these drift in the air
- `Realms.gd:65` `FACING = ["arch", "rib", "awning", "ring", "petal", "pole"]`: these do not turn at random: they face the rider

**DhDirector.gd**

- `DhDirector.gd:23` `BPM = 128.0          # the stems`: the stems
- `DhDirector.gd:25` `BAR_S = 4.0 * 60.0 / BPM          # one bar of the stems, `: one bar of the stems, in seconds
- `DhDirector.gd:49` `OPENING = []          # keys of TRACKS for the opening of a `: keys of TRACKS for the opening of a run (fresh, awake): none chosen yet, so the run opens on the wind alone

**Telemetry.gd**

- `Telemetry.gd:11` `TICK = 10.0          # one summary every ten seconds (it `: one summary every ten seconds (it was every second: the report itself cost a frame or two each time on a phone)
- `Telemetry.gd:12` `LIGHT_EVERY = 45.0          # reading the camera picture back co`: reading the camera picture back costs a frame or two: rarely, once play is under way

**Lighting.gd**

- `Lighting.gd:32` `GAME_FPS_MIN = 50.0          # below this for a few seconds and t`: below this for a few seconds and the picture steps down a level

**AudioHooks.gd**

- `AudioHooks.gd:106` `SFX_GAIN_DB = 3.0          # the soft sounds are quieter than th`: the soft sounds are quieter than the old harsh ones: this brings them back up so they are still heard over the music

**DhJourney.gd**

- `DhJourney.gd:29` `THR = [2.6, 3.8, 5.0, 6.2, 7.6, 9.6, 4.5, 1.5]          `: the first wave of another world waits until the pieces (sky, trees, ground) have had their turn          # (0.42 a level: the peak wave wants about 23 of the 36 levels held)

**GazeTestRig.gd**

- `GazeTestRig.gd:15` `SCORED_TAIL = 12            # the score uses the last 12: the fi`: the score uses the last 12: the first ones are the tracker learning your range

**PhoneMotion.gd**

- `PhoneMotion.gd:39` `GAIN_CAP = 0.02             # iris-reading units per degree, `: iris-reading units per degree, at most
- `PhoneMotion.gd:40` `WARM_UP = 90                # samples before the fit is used`: samples before the fit is used
- `PhoneMotion.gd:41` `FORGET = 0.004              # per sample (the poll runs at `: per sample (the poll runs at ~30 Hz: ~8 s memory)

**Game.gd**

- `Game.gd:19` `MASK_WORLD = 1    # layer 1`: layer 1
- `Game.gd:20` `MASK_PLAYER = 2   # layer 2`: layer 2
- `Game.gd:21` `MASK_ENEMY = 4    # layer 3`: layer 3
- `Game.gd:22` `MASK_PROPS = 8    # layer 4`: layer 4

**HeadCoach.gd**

- `HeadCoach.gd:10` `KEEP = 600                       # samples kept (about 40`: samples kept (about 40 s at 15 frames/s)
- `HeadCoach.gd:11` `MIN_REF = 45                     # samples before a referenc`: samples before a reference pose exists
- `HeadCoach.gd:12` `TOL_PITCH = 8.0                  # degrees`: degrees
- `HeadCoach.gd:15` `TOL_OPEN = 0.80                  # eye opening below this sha`: eye opening below this share of your usual = squinting
- `HeadCoach.gd:16` `NAG_AFTER = 1.5                  # seconds out of range before`: seconds out of range before a hint appears
- `HeadCoach.gd:17` `NAG_GAP = 14.0                   # seconds between hints`: seconds between hints

**TrailCurve.gd**

- `TrailCurve.gd:11` `STEP = 4.0                    # metres between stored poi`: metres between stored points of the line
- `TrailCurve.gd:12` `LENGTH = 12000.0              # metres of trail laid out (a`: metres of trail laid out (a run is about 4 km; ENDLESS wraps the heading smoothly well before this)
- `TrailCurve.gd:14` `EASE_IN = 260.0               # metres over which the bends `: metres over which the bends grow to full size after the straight start

**EyeMix.gd**

- `EyeMix.gd:16` `SIGN = [1.0, 1.0, -1.0]               # which way each re`: which way each reading grows when you look to the right of the screen
- `EyeMix.gd:17` `KEEP = 900                            # readings kept per`: readings kept per signal (about 45 s)
- `EyeMix.gd:19` `OUT_UNIT = 0.03                       # one normal glance, wr`: one normal glance, written in the units of the iris-in-eye reading the rest of the game expects

**DhProgress.gd**

- `DhProgress.gd:7` `LEVEL_XP = [0, 300, 800, 1600, 2800, 4500, 7000, 10000, 14000`: XP at which levels 1..9 begin

**AimAssist.gd**

- `AimAssist.gd:14` `CONE_GAZE_SIM = 5.0     # mouse/finger driving hands-free`: mouse/finger driving hands-free
- `AimAssist.gd:15` `CONE_GAZE_CAM = 7.5     # real camera gaze`: real camera gaze

**DhPacer.gd**

- `DhPacer.gd:22` `CALM_START_S = 20.0          # nothing hostile at all for the fir`: nothing hostile at all for the first twenty seconds
