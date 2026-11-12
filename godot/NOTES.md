# Handoff notes (Goose Chaos FPS + face-control demos)

Godot 4.7.2 project in `gaze-lab/godot`. Web demo live at https://joshuaopolko.com/gaze-lab/godot/ ;
EyeLab (webcam tracking lab) at https://joshuaopolko.com/gaze-lab/eyelab/ (in the site's XR nav menu on 69 pages).

## Modes (web demo opens on Peek; picker on the start screen; ?level=flight / ?level=eyes)
- **Peek & Blast (level 6):** rail between 3 stations, hidden baddies behind round cover. Head lean moves the BODY
  (`PlayerController._peek_velocity`, rail_anchor + GazeProvider.peek_offset). Mouse/keyboard shoot. Baddies are
  `EnemyAI.cover` (rustle while hidden, throw tomatoes once exposed). Hiding spots solved numerically in
  `LevelBuilder._hide_spot`; tests ray-check every baddy is hidden from the rail centre and revealable by a lean.
- **Nod Flight (level 7):** `FlightRig.gd`. Chin down = gather energy, snap chin up = blast, chin up = float, fast chin
  drop from height = slam, lean = steer, groove multiplier. Inputs: `GazeProvider.nod_state()` + `peek_offset()`.
- **Eye arena (level 5):** original hands-free demo (gaze dwell-lock, blink fires, wink swaps guns).

## Tracking pipeline
`GazeCamJS.gd` (MediaPipe FaceLandmarker in the browser, CDN, on-device) -> `window.__gaze` -> `GazeProvider.gd`
(autoload): head pose (yaw/pitch/roll), lean in real cm (face width based), 3D-geometry gaze + running mean/spread
auto-fit (no calibration; optional 5/9-dot ridge via C key in hands-free), blink/wink with per-eye baselines,
nod velocity. Touch fallbacks: touch_lean / touch_steer / touch_nod_goal. Diagnostic line: `debug_line()`.
Camera facts: user's office cam is a Logitech C920 (auto-exposure caps it ~15 fps in dim light; `?fast` / EyeLab
"fast exposure" forces 30 fps). `?res=1080`, `?flipyaw`, `?flippitch`, `?headw=`, `?hfov=`, `?sw=` exist.

## Known gap (next thing to do)
Eye GAZE only drives the old Eye arena. In Peek and Flight only HEAD (and face gestures) control anything, so the
eyes are tracked but change nothing. Ideas agreed: eyes = fine control on top of head gross control
(gaze lock-on + blink fire in Peek; gaze-assisted steering / target lock in Flight; squint/wide as held modes).

## Dev commands
- Godot: the Godot 4.7.2 console executable
- Tests: `--headless --path . res://tests/smoke.tscn` (RESULT: ALL PASSED; two old ragdoll/AI timing checks flake
  occasionally). After adding class_name scripts run `--headless --path . --import` once.
- Web export (templates installed in %APPDATA%\Godot\export_templates\4.7.2.stable):
  `--headless --path . --export-release Web build/web/index.html`
- Deploy: `tar czf - -C build/web --exclude='*.import' . | ssh YOUR_SSH_HOST 'tar xzf - -C /var/www/html/gaze-lab/godot'`;
  EyeLab: `scp eyelab/index.html YOUR_SSH_HOST:/var/www/html/gaze-lab/eyelab/index.html`.
  Local EyeLab: `eyelab/run.bat` (http://localhost:8070).
- Editing tip: write Python patch scripts to a file and run them (shell heredocs with triple quotes break).
- Site nav backup before the EyeLab link edit: `(a backup on the server)`.

## Downhill (level 8, `?level=downhill`) and later changes (2026-11-09)
- `scripts/DownhillRig.gd`: snow run. Real slope physics (gravity along the surface gradient, drag, grip, carving
  redirects momentum and costs speed, never creates it). Heightfield `terrain_h()` is shared by physics, chunk meshes
  and trees. Kickers are bumps in that function; launch happens when the ground falls away faster than gravity.
- Posture: lean = steer, chin down = tuck (less drag, charges spring), snap up = pop, chin up = brake (ground) / glide
  (air), snap down in air = stomp. Uses `Game.flight_mode` + `Game.downhill_mode` so it shares chin/lean input and the
  flight touch layout.
- Eyes are the point: each ~85 m a forest wall has openings (open / tight / hop bank / dead-end pocket in snow
  colours). Far away all look alike; gaze dwell 0.35 s on one resolves it (marker + label). Without eyes they resolve at
  110 m, with eyes only at 46 m, so looking buys early information. Scoring: look-ahead, scouting several openings,
  clean line, air time. Director: `diff` rises on clean passes, drops on crashes; kicker count follows how long the
  player stares at ramps. Desktop without camera: mouse pointer = eyes.
- `GazeProvider`: `Game.downhill_mode` gets the same eye-weighted gaze as peek mode.
- Start screen rewritten (short, scales for portrait/touch, scrolls if too tall). Nav labels match the game titles.
- Tests: `tests/downhill_test.tscn` (headless; includes a momentum-aware autopilot that must clear the course),
  `tests/shots_downhill.tscn`, `tests/shots_intro.tscn`. Full `tests/smoke.tscn` still passes.
- Server: `/godot/.htaccess` and `/eyelab/.htaccess` send `Cache-Control: no-cache` (a phone kept an old build).
  Nav is baked into ~69 pages; edit scripts run as `sudo python3` on the VPS (files are owned by www-data).
- EyeLab: head-sweep drift compensation + centre-eyes buttons (untested on a real camera).
- Unverified on real hardware: Downhill feel with a webcam (steer latency, nod thresholds), gaze dwell tolerance.

## Downhill update 2 (2026-11-09, later)
- Gameplay: gates now open and close. Kinds: open, tight, hop (snow bank, pop over), trap (dead-end pocket), cycle (timed
  door; your speed decides if it is open when you arrive), late (shut until ~34 m, then opens), shut (looks open, slams shut
  at ~26 m). The way through is always open / tight / late. Snow screens hide part of a wall until ~50 m.
- Eyes: 3-dot setup (centre / left / right) maps the raw `GazeProvider.geo_median()` to screen x (`DownhillRig.fit_gaze`).
  Only horizontal gaze is used; nearest wall first. Looking ~0.35 s at a gate reads it and LOCKS it as your line: dashed
  path + steering pull (ASSIST 0.75, your lean still wins). Forecast label says if a gate will be open at your arrival.
  Press C / CENTER to redo the setup. Why it was bad before: the game's gaze auto-stretches your gaze spread to a fixed
  fraction of the screen, which amplifies noise when you mostly look at one place.
- Visuals (all code-built, no assets): tiered snowy trees, snow-capped rocks and cliffs, mountain ring, valley sides,
  banner flags at gates, snow ground shader (needs `render_mode cull_disabled`, `SPECULAR = 0`), baked blue shadow shapes
  under trees/rocks (engine sun shadows did not show on the ground in my tests, cause not found), warm low sun.
  Config keys in `LevelBuilder._downhill`; `MainLevel._apply_environment` reads shadows / glow_on / ambient_color / fog_sky.
- Tests: `tests/downhill_test.tscn` sets `Game.touch_mode = true` for the physics checks (a headless mouse counts as eyes).
- Reference look: Carve (Quest). Gap still: real modelled assets, volumetric haze, rider/board model, particles.
- Eye tuning panel (T, or tap the EYES label): LOOK TIME (dwell), LINE PULL (assist), AIM FORGIVING (tolerance multiplier).
  Saved in localStorage `dh_tune`; `?dwell=0.3&assist=0.5&pad=1.2` override. Aim zone also adapts to measured noise
  (setup noise `_cal_sigma`, live `_jit`); selection is sticky; line pull scales with camera confidence.

## Ocular Trance (level 9, `?level=trance`) - from the Gemini spec in Downloads (2026-11-09)
- Files in `trance/`: `TrackerBridge.gd` (autoload; UDP 4242 JSON -> in-browser camera -> mouse/touch fallback; `gaze`, `ear`,
  `is_blinking`, `just_blinked`, `head_pitch_yaw`, `force_mouse_mode`), `AlteredStateCamera.gd` (FastNoiseLite drift, bi-phasic bob with
  pow(x,3) drop, sawtooth nystagmus, `intensity`), `DopamineLoop.gd` (0.5 s dwell -> charge; audio bus "Trance" low-pass + pitch shift;
  shader aberration; blink release = physics shockwave + multiplier), `NystagmusPostProcess.gdshader`, `TranceRig.gd` (arena, drone,
  HUD, comfort slider). `tools/trance/webcam_server.py` + README (opencv + mediapipe -> UDP). Python side is syntax-checked only.
- Deviation from the spec: shader parameters are normal uniforms set from script, not global shader parameters (safer on the web renderer).
- Comfort: INTENSITY slider always visible; `-` `=` change it, `C`/Esc calm. Intro says the effects are strong.
- Tests: `tests/trance_test.tscn` (headless, incl. a UDP packet and blink-on-reopen), `tests/shots_trance.tscn`.

## Automatic eye mapping (2026-11-09, supersedes the 3-dot setup and the z-score auto-fit)
- Why it was loose: the game fed MediaPipe's iris LANDMARKS (wobble ~1 px) into the geometry model, and one pixel of iris is ~7% of the
  screen width (~13% of the height) at ~55 cm. EyeLab looked precise because it fits the iris edge in the video pixels (limbus ring fit).
- Now: `GazeCamJS` runs the EyeLab limbus fit on both eyes (RMS 0.04 px on synthetic data, even from a bad landmark guess) and feeds those
  sub-pixel centres into the existing geometry gaze (head pose, depth from iris size, real screen size, camera position). Published as
  gu/gv with `glimb=1` (plus lx/ly, the iris position in the eye box).
- `GazeProvider`: when `glimb` is live the gaze is the physical mapping directly (no stretching to your recent spread) + `EyeBias`.
- `EyeBias` (scripts/EyeBias.gd): invisible, constant-offset correction learned while playing (window medians toward screen centre / horizon),
  a slow ridge fit of the vertical offset against head PITCH and eyelid APERTURE (head tilted back / squint), anchors from confirmed events
  (blink on an orb in Trance, CENTER / C), only trusted when the face is roughly frontal. Output is clamped to the screen.
- No dot calibration anywhere. `tests/eyebias_test.tscn` (synthetic data), JS checked in a browser page (limbus + geometry signs/scale).
- Unverified on a real camera/phone.

## Visuals menu, trippy effects, Gaze Test (2026-11-09, later)
- Site nav: new "Visuals" dropdown (toys / fun): the Godot modes, Gaze Test, EyeLab, Smushlings, and the psychedelic demos (Psychedelic VR
  Effects article, Visual Tests, Psychedelic A-Frame, 3D WebXR Trip, Cosmic Grid). XR keeps only the 8 article pages. Other live demos not
  in the menu: /hex_skybox.html, /babylon_skybox_clouds.html, /disoriented-vr-fixed.html, /test3d.html, /three_js_pattern.html, /vr-debug.html.
  The psychedelic article was cut from 11 to 6 techniques; the full 11 (with GLSL) is in
- Ocular Trance effects: `trance/NystagmusPostProcess.gdshader` now holds screen-space ports of flow-based UV distortion, kaleidoscope fold,
  infinite tunnel, god rays (from the charging orb), phosphene rings/spokes, and the time-breathing chromatic fracture. `DopamineLoop.FX_NAMES`
  / `FX_WEIGHTS`; keys 1-7 or tap the EFFECT label. All scaled by the INTENSITY slider (phosphene rings kept < 3 per second).
  Headless Godot cannot compile shaders: render a window (`tests/shots_trance.tscn`) and grep for "SHADER ERROR" (PI is built in).
- Gaze Test (`?level=gaze`, level 10, `scripts/GazeTestRig.gd`): lit dots, measured-vs-dot lines, average error as % of screen width, live
  jitter, learned offset. Measures only. `tests/gaze_test_test.tscn`.
- Real-camera result (user, desktop, 2026-11-09): physical-only mapping scored 29.7% error: offsets pinned at the +/-0.3 clamp, gaze barely moved
  (iris moves only ~3-5 px across the whole screen). Fix: EyeBias now also learns SCALE (`exp_span` per mode: percentile span of the signal ->
  expected span of the screen, scale clamped 0.6..3). Gaze Test now has 24 dots (score = last 12), a raw-signal panel (iris px, readings/s,
  raw gaze, eye-in-box, head, scale, range) and a hint when the iris is < 9 px. Phones: iris ~10 px at arm's length; precise points are not
  realistic there, use head pose + coarse zones.

## EyeLab: Screen reach card (2026-11-09, latest)
- eyelab/index.html now has a "Screen reach" card (top of the right column, `RC` object, `reachFrame(f)`): a to-scale map of the REAL screen
  (aspect + cm from screen width) with a coverage heat map, the area the gaze covered (dashed), red bands + cm for the parts never reached, this
  window's rectangle, and where the + in the middle of the map physically is. Table per direction (left/right/up/down): reach %, cm short,
  iris pixels moved, gaze/head angles, gain still needed. Sliders: head-follow cancel (yaw/pitch), eye gain, shift, centre-on-median. Buttons:
  Fit range to screen, Stop head-follow (6 s fixation + head sweep, fits and cancels the leak), Clear, Reset.
- It uses `geoGaze(f, mm, true)`: the geometry gaze with the limbus ring-fit iris centres (same idea as the game's glimb path). Tested with
  synthetic frames in a browser (coverage 33%x11% -> 88%x87% after Fit; head-follow coefficients recovered exactly). Not yet seen a real face.
- Why the gaze follows the head: the geometry output is head angle + eye angle. The eye part is only ~3 px of iris movement per 10 deg, so
  when it is under-resolved the head term dominates; stretching the signal amplifies the head term too. The cancel sliders / Stop head-follow
  measure and remove it. Game builds do not yet take these tuned numbers.
- EyeLab Screen reach: "Guide me: look here (20 s)" button (`guidedRun`): full-screen dot via enterStage/holdOn. Steps: centre (head still), centre with
  slow head turn/nod (runs the head-follow fit), then left / right / top / bottom edges and centre again. Per dot it reports where the gaze read
  vs where the dot really was (physical screen fractions, cm error, left/right/high/low), and the error predicted after "Fit range". Included in
  Copy results JSON (`reach.guided`). Header "Copy results JSON" is always enabled now.
- EyeLab layout (user request): top row = Screen reach card (left) + Head and gaze monitor with a SMALL camera thumbnail under it (right).
  Phones: cube, reach, small camera, then the rest. Added: monitor diagonal input (a 1920x1080 monitor is 53-60 cm wide, not the 34 cm laptop
  default), camera distance readout from iris size, "Fit to the dots" (least-squares gain+shift from the guided dots), head-turn step with live
  degrees counter (needs 18 deg yaw + 8 deg pitch), and a warning when the dot follows the head (coverage verdict is then mostly head).
- REAL DATA (user, 1920x1080, camera 1280x720, ~88 cm from the camera, iris 11.7-13 px): physical model needed gains ~x1.5 (across) and ~x2.2
  (up/down) plus offsets; mean error 5.2 cm raw, ~2.3 cm after a per-axis fit to the six dots. Head leak measured -52% of width per 10 deg of head
  turn (eyes' counter-rotation not detected), so a "100% coverage" verdict was mostly head. Vertical iris movement only ~0.3-0.8 px per extreme.
- EyeLab mobile fix: the desktop `.topRow` grid CSS came AFTER the `@media (max-width:980px)` block, so it overrode `display: contents` and the page was 822 px
  wide on a phone. A final `@media` block (last in the stylesheet) now flattens .topRow/.topMain/.topSide, wraps tables, single-column sliders, hides horizontal
  overflow. Checked 320, 375, 768 px: scrollWidth == viewport, 0 overflowing elements. Touch devices default the screen width to screen.width/63 cm.
  Lesson: put responsive overrides at the END of the stylesheet and always measure `document.documentElement.scrollWidth` at 375 px.
- REAL PHONE DATA (user, 412x924 CSS px, camera 720x1280 portrait, ~27 cm away, iris 23.7 px = 2x the desktop resolution): horizontal iris travel
  +1.8 / -3.3 px (output overshoots 100%: physical gain ~0.7 too high); vertical output covers only 45% (needs ~x2); head pitched -28 deg
  (camera looking up at the face; squints the eyes). Phones HAVE usable signal; the game's auto-range (per-side scale, exp_span) should learn this.
  EyeLab now warns when |median head pitch| > 15 deg ("hold the camera at eye level").
- EyeLab reload robustness: `getStream` retries when the phone still holds the camera after a reload (NotReadableError), falls back to simpler constraints,
  startCam waits for the tracker (`modelPromise`), tracker load retries 4x, errors/unhandled rejections are printed into #status (no console on a phone),
  bfcache-restored pages reload. Fine control: "Resolution" readout (cm per iris pixel from a numerical derivative of the geometry + measured frame-to-frame
  noise -> smallest distinguishable movement), "centre boost" curve and One-Euro "smoothing" sliders on the live dot. geoGaze guards W=0 / screen=0.
- WHY THE GAME WAS WOBBLIER THAN ETERNAL EYELAB: (1) BUG: GazeProvider._poll_camera ran every 30 ms and ingested window.__gaze whether or not a new camera frame
  had arrived (camera = 12-15 fps), so every frame entered the median/bias/limb buffers 2-3 times (and the "readings/s" readout was ~33). Now the JS packet has a
  frame counter `n` and only fresh frames feed `_geo_push` / `_limb_buf`; median window 7 -> 5 (distinct frames). Head/peek/nod/gesture paths still see every
  ingest (nod velocity was tuned against the old behaviour, deliberately untouched). (2) Structure: EyeLab shows the pupil inside the eye box (px); the game turns
  1 px into ~7% of the screen width and then multiplies by the learned scale (0.6-3x), so noise is amplified 5-20x. (3) The game's gaze still includes the head's
  contribution (measured -52% width per 10 deg of head turn on the user's desktop); EyeLab's pupil views exclude it. (4) The mapping adapts every ~1.5 s (median
  centring + per-side scale), which can make the dot slowly swim.
- EyeLab "Guide me" is now a 10-dot PERFORMANCE MEASUREMENT (head step, then centre, 4 edges, 4 corners, centre again; 2.3 s per dot). Output block "Expected
  performance: design around this": accuracy on positions NOT fitted to (leave-one-out, per-axis vs affine, the better one reported), steadiness while holding one
  dot, response time (63% / 90% of a jump, from the post-jump time series), camera fps, smallest target hit 9/10 (diameter = 2 x 1.52 x RMS, floor 1 cm), zone grid
  (capped 16x9), hold time (t90 + 4 frames), cm per iris pixel, fps hint. Also in Copy results JSON as `reach.performance`. Verified on synthetic eyes with a known lag.
- Does EyeLab have the game's frame optimizations? It had the equivalent from the start (requestVideoFrameCallback, one pass per NEW frame). The game now matches
  (frame counter `n`; `_pkt_times` counts distinct frames). Neither raises the camera's own rate (15 fps in dim light = auto-exposure cap): use "fast exposure"/?fast.
- EyeLab Screen reach: "Full screen map" button. Real element fullscreen on #reachWrap (falls back to a CSS full-viewport mode on iPhone/Safari; Esc exits). The canvas draws in
  a fixed logical 720-wide space and is scaled to any pixel size, so it is sharp full screen. In full screen the map IS the physical screen, so the dot is where you look; a
  live readout (gaze %, cm from left/top, iris px, head angles, red "outside the screen") and Fit range / Clear / Exit buttons float over it.
- Camera release: EyeLab `stopCam()` (stop all tracks, vid.srcObject = null, loop off) runs on pagehide/beforeunload and at the start of every `startCam()` (+250 ms
  before re-requesting if one was open). The game's GazeCamJS has `window.__gazeStop` (tracks stopped, preview removed) on pagehide/beforeunload and calls it before
  asking for a new stream. Note: EyeLab's script is a module: test via `window.__eyelabCam` / `window.__eyelabTest`, not bare names.
- Hardware profile: EyeLab now defaults to 1080p (auto-drops to 720p if <18 fps after 5 s), has "fit field of view" (iris 11.7 mm at the typed distance) and
  "measure screen with a card" (85.6 mm), and saves scrW/dist/hfov/campos/res/head cancel/gains to localStorage `eyelab.profile` (key = screen px @ dpr).
  The game's GazeCamJS reads it (same origin): screen width, hfov, head-follow cancel (yaw/pitch vs slow running median), 1080p on desktop (phones stay 720 unless ?res=1080).
- Head coach (EyeLab, under the Head monitor): live chin/turn/tilt/eyes-open chips + one gentle sentence (tilted back, chin dropped, turned, leaning, eyes narrowing).
  "Remember this head position" stores the pose (profile `pose`) so the coach guides back to it with tighter tolerances; Guide me runs `alignStep()` first (up to 12 s) and
  shows the same coaching full screen. Origin: user tilts head back to use the lower part of progressive lenses, which squints the eye and loses precision looking down.
  Pitch sign: negative = head tilted back (verified from earlier reports). Not yet fed into the game.
- Auto head pose (no dots): `scripts/HeadCoach.gd` (owned by GazeProvider as `coach`, fed from every fresh camera frame with head pitch/yaw/roll + eyelid opening).
  The good pose = median head pose while the eyes are open widest (above the 60th percentile of opening), learned during play; optionally seeded from the EyeLab
  profile `pose` (sent in the packet as `pp`). `quality` 0..1 widens Downhill's aim zone (up to +60%); a hint line shows rarely (after 1.5 s off, once per 14 s, never in
  the first 6 s) and a green "Good position" on return. Comfort: late gates open >=1.5 s before arrival (was a fixed 34 m), false openings slam shut >=1.1 s before.
  Tests: tests/coach_test.tscn, plus two checks in downhill_test. NOT verified on a real camera/glasses.
- THREE-LANE Downhill (branch claude-lanes, deployed to /godot-claude/, NOT the live /godot/): DownhillRig `lane_mode` (default on): 3 gaps per wall at LANE_X -24/0/24 (width 14),
  safe lane moves at most 1 per wall, first 8 walls all open, difficulty capped 0.55 and eased by HeadCoach quality, coins trace the carve to the safe lane. `lane_pick()` =
  nearest lane on screen with hysteresis (LANE_MARGIN) + dwell; a wall freezes its lane max(55 m, 2.2 s) ahead (LANE_COMMIT_*) so a lane change = one long carve (~85 m), steering is a
  smoothed (4.5/s) PD toward the lane gap (clamp 0.7, lead 0.45 s); speed kept in 12..36 m/s; crashes softer (0.5 s, vel x0.6); lane held 1.5 s when tracking is lost;
  arrows/A/D or screen thirds switch lanes without eyes. Old "look at a gate to lock it" is bypassed in lane mode. Tests: lane checks in downhill_test, tests/shots_lanes.tscn.
- Lane control v2 (user: "game decides, eye tracking inconsistent"): far lanes are only ~90 px apart on screen, below the tracker's ~9% error, and scouting a wall the choice did
  not apply to felt random. Now JOYSTICK control: gaze left/right of a dead zone (LANE_ZONE 0.13, hysteresis 0.6x) steps the lane (first after 0.30 s, then every 0.60 s);
  needs only left/right discrimination. Walls lock their lane max(55 m, 2.2 s) ahead; gates are revealed from 170 m (course readable early); coins in EVERY lane (nothing points
  at the safe one); traps/shut/cycle lanes more common (calm 5 walls, difficulty cap 0.7). HUD: 3-pill lane indicator top centre (filled = committed, ring = locked for the wall
  ahead, white arc fills while you look aside), orange marker under the committed gate of the wall your choice applies to. Test: noisy gaze (sigma 6%) around the middle = 0 lane steps.
- Lane control v3 + pause monitor: dead zone is learned from your own gaze spread (3.0 x robust std of the last 10 s, clamp 0.06..0.13); gaze is centred on its own 10 s median;
  a head turn adds LANE_HEAD_GAIN 0.012 per degree (head help, toggle in pause) because head yaw is far more accurate than pupils; vertical gaze is never used (looking down is the
  least accurate): chin pitch handles speed. Pause: P / Esc / button under EYES; world stops, lanes do not step; monitor shows fps, iris px, confidence, head angles, eyes-open %,
  head position quality, gaze offset vs dead zone, a 10 s left/right trace, a mini screen map with the three lanes, a verdict line; buttons RESUME / COPY REPORT (JSON to
  clipboard) / RESET LEARNING / HEAD HELP. Tests in downhill_test (noise, pause, report). Unverified on a real camera.
- Lane control v4 (immediate response): lane mode has NO tree wall between lanes (obstacles live only inside lanes: dead-end pockets, doors), and the committed lane is the steering
  target at once (the old freeze 2.2 s before each wall made the board answer 2-6 s after you looked: it felt like the game chose). Bigger gaze cursor with a trail; soft whoosh per step.
  Esc: browsers swallow Esc in fullscreen, so the game also pauses on window focus loss and on leaving fullscreen.
- ROOT CAUSE of "looks at the centre gate, game picks far lanes": EyeBias spread-based stretching (exp_span 0.6, scale up to 3x) assumes the player looks all over the screen. Holding the
  gaze on the middle makes the observed spread tiny, so the noise was multiplied up to 3x and crossed the lane dead zone. In pause the user looks left/right on purpose -> scale ~1 -> looked
  precise. Lane mode now sets exp_span = ZERO (physical mapping + learned offset only). Pause monitor also shows game fps, tracker fps now / while playing, and the gaze stretch, to
  rule out single-thread frame contention. Test: eyebias_test "steady stare keeps scale 1.0".
- Lane control v5: (1) GAZE IS MONITOR-RELATIVE, the game draws in the WINDOW: GazeCamJS now converts u,v from monitor fractions to window fractions (window.screenX/Y,
  innerWidth/Height; desktop only, identity when fullscreen), fixing "windowed browser on the right of the monitor = no control on the left". (2) GATE control is the default again
  (`lane_ctl` 0): the gate nearest to your gaze among the gates of the first wall >= 22 m ahead (about 250-390 px apart on screen; far walls are ~90 px apart) with hysteresis
  (LANE_MARGIN 0.04 of the width) + dwell 0.25 s, steering immediate. The SIDE joystick remains (lane_ctl 1, pause button CONTROL). From an outer lane the far gate is off screen, so
  looking toward the edge walks one lane per ~1.2 s. Tests cover noise on the middle gate, right gate, walking left. Deploys went only to /godot-claude/.
- Lane control v6 (user: "far looks work, looks within the monitor range do not"): BUG: the dead zone was 3 x the TOTAL spread of the gaze history, so the more the player looked
  aside the wider the zone became (capped 0.13), until real glances could not cross it. Now zone = max(0.30 x observed half range, 3 x FIXATION noise) with fixation noise = median of
  15-sample block stds (a glance does not count as noise), clamp 0.02..0.20. The reference is the 30 s median (a look held for seconds no longer re-centres itself). SIDE (look
  more left / straight / right) is the default again (lane_ctl 1); GATE stays as a pause-menu option. Tests: an 8% look steps with low noise; 6% noise on the middle never steps.
- EyeLab "Ball demo (full screen)": tennis-ball sized (6.7 cm, from the screen width setting) circle that follows RC.cur (the same tuned pipeline as the reach map: limbus fit, geometry,
  head cancel, gains, One-Euro). Keys: SPACE re-centre on the current look, arrows shift, [ ] gain, , . smoothing, H toggle head cancel, Esc exit. HUD shows jitter in cm, iris px, fps.
- EyeLab per-side gains (user: ball cannot reach the left edge, overshoots off the right): outUp/outVp now apply separate multipliers RC.gl/gr/gt/gb on each side of the centre (saved in the
  device profile). Ball demo key X = fit the edges (look at centre, left, right, top, bottom rings 2.6 s each, head still); Q/W left gain, E/R right gain. Tested with simulated samples
  (expected gains recovered). NOT yet used by the game (lane mode disables spread-based scaling; a per-side fit from the profile could be fed in).
- Per-eye calibration for glasses (user: asymmetry comes from the glasses): geoGaze now also returns each eye's own screen intersection (eu/ev, [right, left]); samples carry uR,uL,vR,vL.
  Ball demo key X fits EACH eye separately (own centre + gl/gr/gt/gb) and weights the eyes by (signal range / fixation noise) x left-right symmetry, squared and normalised (the cleaner,
  more symmetric eye dominates; 99/1 in a synthetic test). RC.dual is saved in the profile; key D toggles weighted-eyes vs single blend; SPACE re-centres each eye. Not yet in the game.
  Unverified: whether 'R' (landmarks 33/133/468) is the user's right eye as labelled; test by covering one eye.
- AUTOMATIC per-eye calibration (user: "no manual calibration"): class EyeFuse (JS, in EyeLab and embedded in GazeCamJS). For each eye it keeps 900 samples of its own horizontal/vertical gaze,
  learns centre (median), per-side gains (left/right and top/bottom excursions equalised to their mean, clamp 0.6..2.5, rate 0.2/s, only while the window shows real excursions
  > 6 x fixation noise), and a weight ~ (range/noise)^2 x symmetry, normalised. The more normal-looking eye dominates (glasses). Output is already centred on the median look. Game:
  fused u,v replace the averaged ones and the monitor->window step becomes a pure scale. Packet field `ew` = [right, left] weights (NOT `fw`: that is face width) -> GazeProvider.eye_w ->
  pause monitor line. Staring at one spot does not amplify noise (tested in node: gains stay 1.0). Manual X-fit in the ball demo was removed (fitDual remains as dead code).
- STEER control (lane_ctl 2, default; user: "normal looks have no effect, I want immediate, continuous, real-time steering"): steer = proportional gaze offset from your own 30 s median centre,
  divided by a scale learned from your own gaze (1.15 x the 90th percentile of |offset| over 10 s, clamp 0.10..0.30; MORE SENSITIVE in the pause menu shrinks it), tiny dead zone = min(fixation
  noise, 0.03); no thresholds, no dwell, no lane stepping; head turn adds 0.012/deg; steering smoothing 9/s. The lock/assist pull is off in STEER. SIDE and GATE remain (pause menu CONTROL cycles
  GATE / SIDE / STEER). Tests: steady = straight, 8% look = +0.67, 4% look = +0.37, left = -1.0. Test lesson: headless frame waits are timing-flaky (dwell is wall-clock): wait on elapsed ms.
  NEXT (asked for, not built): gaze-centred expanding fractals / disintegration in the Trance mode (feed gaze uv into the post-process shader).
- STEER tuning (closed-loop sim, tests/steer_sweep.tscn; a scripted driver looks at the gate of the lane it wants): FINDING: the first STEER version ignored every curve/rate setting
  (rise to 80% of a lane change 6.4 s whatever the values) because it normalised itself: the scale was 1.15 x the 90th percentile of |offset| over 10 s and the centre was the 30 s
  median, so a look held to one side grew the scale and became the new centre, cancelling the steering. Fixed: scale is a CONSTANT (steer_scale_const 0.12, raised only by 4 x fixation
  noise), the centre `_ref_x` follows slow drift only while you look near it (and moves for real only after 25 s away). Rise to a lane 24 m away: 2.8 s. Defaults: curve 0.8 (small looks
  steer more), rate 12/s. Pause menu: MORE/LESS SENSITIVE, FINER CENTRE/FLATTER (curve), FASTER/SMOOTHER (rate); all saved on the device (localStorage dh_tune: zs, curve, rate);
  ?curve= ?rate= ?steer= override. Note: stale Godot processes holding UDP 4242 make the trance UDP tests fail and slow the sweep; killing them was denied, left alone.
- CORRECTION to the STEER tuning note: the "2.8 s rise" was one noisy sample. Re-measured with the deployed defaults (scale 0.12 / curve 0.8 / rate 12): 5.6 s right, 6.1 s left; with
  scale 0.08 / curve 1.0 / rate 9 (now the default): 4.5 s right, 6.1 s left (noise 0.015), about 5.3-5.9 s at noise 0.03. Run-to-run variance is large (sequential RNG, different worlds), so the
  sweep does NOT show a robust gain from any setting; the driver looks at far gates whose screen offsets are small. Treat the sim as a weak proxy: judge by feel + the pause report.
- User report (steer, camera on): game 11 fps, tracker 12 fps (EyeLab does 25-30), fixationNoise 0.149, gaze pinned at the left edge (offNow -0.6, steer -1.0) from the moment the camera
  came on, "the orange circle jumps left and never tracks". Causes found: (1) the tracker copied the WHOLE 1080p frame to a canvas every frame to read two small eye crops: now only the two
  crops are drawn/read straight from the <video> (grabCrop; unit-tested in node on a synthetic eye: centre error 0.07 px); (2) start-up regime changes: the first raw gaze (no offset yet),
  then the per-eye fusion becoming ready after ~150 samples (12 s at 12 fps) shifted the signal by a different offset while STEER's reference was already set, saturating at -1 for 25 s.
  Now: after 10 fresh geometry samples the centre is pinned to the screen middle (eye_anchor, weight 1: you look at the middle when it starts), when the fusion becomes ready the bias is
  reset and the reference/history re-initialised, steering fades in over 1.5 s after any such reset (`_steer_arm`), fixation-noise blocks are 6 samples (fps independent) and clamped to 0.06.
  Report now includes steerArm and anchored. UNVERIFIED on the real camera: the fps gain and the start-up behaviour.
- SEEK control (lane_ctl 3, default; user: "general gaze auto-mapped to the nearest gate so it feels fluid, like the player is seeking each gate"; also "what is the auto-aim based on
  now?" -> in STEER there is NO auto-aim, the green line/marker was just the gate of the lane the board happened to be in): gaze (centred on your own reference, offs + 0.5) picks the
  gate nearest on screen among the three gates of the first wall >= 22 m ahead (lane_pick, hysteresis LANE_MARGIN 0.04, no dwell, no thresholds); the board carves toward that gate's
  lane (lead 0.45, /20, clamp 0.7, steering fades in via _steer_arm); `_lock` (green line) and the orange marker are on the gaze-picked gate; the reticle is drawn where the game reads the gaze
  (`_cursor_px`, i.e. relative to your own centre, so a constant offset no longer misleads). Looking straight ahead = the gate in front of the board. Frozen while paused. Pause menu CONTROL cycles
  GATE / SIDE / STEER / SEEK. Tests: middle keeps own lane, right gate becomes target at once, green marker on it, board carves toward it, 3% noise = no switching.
- Reticle fix (user: "no perceptible tracking in game, cannot move the circle to the top right; EyeLab is effortless"): the game drew the reticle at a FIXED height (`_gaze_px.y = GAZE_Y * h`),
  so it could never go up, and fed horizontal control through the processed gaze (5-frame median + offset learner + heavy One-Euro 0.6 + 12 fps). Now GazeProvider.direct = the tracker's
  geometry gaze with only a light One-Euro (min_cutoff 2, beta 3), the same signal EyeLab shows; the rig reads it in BOTH axes (own gated centre per axis: _ref_x, _ref_y) for the reticle
  (`_cursor_px`) and for STEER/SEEK. Test: camera-style packets move the reticle to (0.75, 0.25) of the screen and back. Pause report: directGaze, refY.
- Reach + smoothing: reticle/control offsets are multiplied by `reach` (default 1.3) and smoothed with a time constant `look_smooth` (70 ms) so 12-30 readings/s become fluid 60 fps motion; the pause map now
  draws the same reticle the game uses (it drew the old processed gaze, which could not reach the edges). Pause buttons REACH +/-, STEADIER/SNAPPIER; saved with the other tuning.
- TRACKER IN A WEB WORKER (user approved "#1"): GazeCamJS.gd is now SHARED (gaze maths: geo, EyeFuse, limbus fit, `buildPacket`, `applyEnv`; no window/screen/document), GLUE (worker message
  handler) and MAIN (page: camera, preview, worker control, in-page fallback), joined by `GazeCamJS.source()` (GazeProvider calls it). ENV (search, PROF, coarse, screen/window geometry) is read
  from the page and sent with every frame. The page only snapshots each video frame with createImageBitmap and posts it (one frame in flight, a lost frame times out after 3 s); the
  worker runs MediaPipe (GPU, falling back to CPU), the iris fit, geometry, fusion and posts the packet + preview points. Falls back to the old in-page path if Worker / createImageBitmap /
  OffscreenCanvas are missing, the worker fails or 30 s pass, or with ?noworker. `window.__gazeMode` = 'worker' | 'page'. Verified in the browser pane: worker loads MediaPipe via dynamic
  import in a classic Blob worker (init 0.18 s), returns conf 0 for a face-less frame, start-up picks 'worker' and `?noworker` picks 'page' (stopped only at the blocked camera). Node test of
  buildPacket on a synthetic face: 260/260 valid gaze packets. UNVERIFIED on a real camera: the actual fps gain. EyeLab itself still tracks in-page.
- BUG FIXED (worker release, user: "no tracking at all, goes perfectly straight"): the start-up call stopAll() (which releases old camera sessions) also terminated the worker that had just been
  created, so no frame was ever processed. Now the worker handle is set aside around stopAll(). Verified in the pane with a fake canvas camera: the first packet ({conf:0}) now round-trips through
  the worker (before: window.__gaze stayed null); the fake stream then stalls identically in the old in-page path (hidden pane), so continuous flow is NOT verified without a real camera.
  Pause monitor shows `tracker <mode> packets <n>`; report has trackerMode.
- EYES-ONLY control (user: "I have to strain extremely to switch paths, turning my head works but I need gaze-directed control; later much faster: split-second glance, linger a moment,
  fly through, decide again"): the control signal was the screen-gaze point, which includes the head (head-turn leak ~48%/10 deg), so a head turn beat the eyes. Now `GazeProvider.eih` = the iris
  position INSIDE the eye opening (packet lx, ly from the limbus fit, One-Euro 3/6), a pure eye signal whose range is only a few % of the eye width. DownhillRig `_eyes_only_offs()`: raw = -eih.x
  * sign; own centre (median of the first 45 samples, slow drift only while near it); lingered (EMA tau = 1.7 x look_smooth = 0.12 s) so a split-second glance is noise-free; scaled by YOUR glance
  size (_ex_full = 95th percentile of |lingered offset| over ~20 s, floor max(0.008, 6 x fixation noise), cap 0.08) so a small glance maps to the outer gate (x0.25 screen fraction, then reach/smoothing
  as before) and feeds SEEK/STEER/reticle. Direction (mirror) is checked only while the head is still (|yaw - ema| < 0.015) with corr > 0.5 after 300 samples, flips + re-inits; REVERSE EYES button as
  the manual override; EYES ONLY on/off button. Tests: a 2% iris glance moves the target gate, a head turn with a still iris does not, noise never flips the sign, a reversed signal is corrected.
  Earlier bug found by the test: an unseeded covariance EMA flipped the sign spuriously and left the old reference (pinned full right). UNVERIFIED on a real camera (sign convention, glance size).

## DOWNHILL (level 11, `?level=downhill`; was called CARVE until 2026-11-12, now `RunRig` / `run_test`): free run. The older three-lane game is now "Downhill Lanes" (level 8, `?level=lanes`)

Request: "Carve Snowboarding" feel. Free carving down an open slope; natural obstacles (trees, rocks) with openings to aim for; no gates until the
finish; momentum, a pull that builds, tight smooth controls; finish without crashing.

- `scripts/CarveRig.gd` `extends DownhillRig` (reuses terrain, trees, rocks, camera, pause monitor, gaze pipeline). Overrides: `terrain_h` (slope steepens
  with distance), `_gen_segment` (a barrier per 85 m segment = two staggered lines of trees / boulders / a mix with 1-3 openings; scattered singles
  between barriers that keep 9 m clear of the safe line), `_physics_process` (hill pull ramps with distance: drag halves over 3500 m; carving costs
  speed; tuck saves it), `_collide` (all rows with obstacles near), `_crash` (wipeout: x0.3 speed, 1.1 s invulnerable, run continues), `_update_rows`
  (scores each barrier: opening, margin to its middle, TIGHT bonus, flow chain), `_draw_hud` (no markers; speed lines; latched-opening posts).
- Steering: `lane_ctl` stays 2 (STEER) so `_lane_tick` produces `_steer_gaze` and the reticle (the eyes-only signal from the previous entry). With the eyes
  on, a head lean does NOT steer (it leaks into screen gaze). Without eyes: lean / A, D / mouse.
- Aim assist: look at an opening and hold it for AIM_LINGER (0.16 s) and it latches (posts drawn at its edges); a pull (carve_assist 0.55 x pull weight)
  adds to the steering; looking away (>1.6 x the opening's tolerance) lets go; each new barrier needs a new decision.
- Fairness: the safe opening moves at most 0.3 m sideways per metre downhill between barriers (`shift`), singles keep clear of the straight line between
  safe openings (`path_x`). The test autopilot follows that line and finishes 4200 m with 0 crashes (speed 34 m/s at 500 m, 51 m/s at 3500 m).
- Finish at z = -4200 (posts + chequered bar), clean run +1000, R / SPACE / tap restarts (`_restart`).
- Wiring: `Game.carve_mode`, MainLevel level 11 (LEVEL_COUNT 12; sets flight_mode + downhill_mode too), LevelBuilder 11 -> _downhill config named Carve,
  EyeDemoIntro tab CARVE. Test: `tests/carve_test.tscn` (25 checks: course fairness, autopilot full run, crash, gaze steering, aim latch, restart).
- Test lessons: manual `_update_focus(0.016)` inside an elapsed-time loop double counts time (frames are much shorter than 16 ms headless): use real
  `_process` and elapsed-ms loops. The first autopilot crashed on singles because generation excluded the wrong corridor; fixed by building singles
  between barrier j-1 and j along `path_x`.
- Unverified on a real camera / phone: the feel of gaze carving at speed, the aim assist strength, tuning of the speed ramp.
