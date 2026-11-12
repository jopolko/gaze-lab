# How it works: eye tracking from a plain webcam, fast enough to play with

This is a walkthrough of the techniques in gaze-lab that make eye-controlled play work on **ordinary hardware**: a 1080p30 USB webcam,
a laptop with an *onboard* Intel GPU, Chrome, and no calibration step. Most of the work was not "a better model". It was getting a
cheap, noisy, slow signal to a place where a game can use it.

> **Honest scope.** Sub-pixel figures below come from synthetic tests. On a real laptop the tracker runs at about **10 to 13
> frames a second with about 200 ms of latency** (and that is with half the frames dropped under load). The in-game results
> were tuned on one webcam setup and judged by the person playing. The built-in TRACE test (section 7) exists so that
> claims like "almost perfect" can be turned into numbers on your own machine.

```
 webcam 1080p ─► [main thread]  grab only the eye/face pixels it needs
                      │  createImageBitmap, one frame in flight
                      ▼
              [model worker]  MediaPipe FaceLandmarker (CPU model on desktops)
                      │  landmarks ──► head pose, lean, blink, nod
                      ▼
              [build worker]  eye patches ─► iris limbus ring fit ─► per-eye fusion (EyeFuse)
                      │  packet: iris-in-eye (x, y), gaze, confidence
                      ▼
                 [game]  centre + glance scale learned from you ─► filters ─► control law
```

## 1. Keep the page responsive: do the work somewhere else

The first version ran MediaPipe in the page. The game and the tracker then fought over the one thread and the one GPU, and the
frame rate of both collapsed.

- **Tracker in Web Workers.** The page only snapshots each video frame (`createImageBitmap`) and posts it. A worker runs the
  face model; a second worker builds the eye patches and does the iris fit, connected by a `MessageChannel`. The game's render
  loop is never blocked by tracking.
- **One frame in flight.** A new frame is only sent once the last one came back, so the queue can never build up and add latency.
  A lost frame times out after 3 s. If workers or `OffscreenCanvas` are missing, it falls back to the in-page path.
- **Never copy the whole 1080p frame.** An early version drew the full frame to a canvas every frame just to read two small eye
  crops. Now only the crops are read straight from the `<video>` element (`grabCrop`).
- **Feed the model a crop, not the frame.** The face model sees a small crop around the last known face position. If a frame
  misses, the crop is *widened* from the last good one instead of dropping to the whole frame. A separate set of small
  **full-resolution eye patches** is kept for the iris fit, so the model can be cheap while the iris measurement stays sharp.

## 2. Spend the GPU on the game, not the tracker

- **CPU face model by default on desktops.** With an onboard GPU the game and the model share the same silicon. Running the model
  on the CPU in a worker left the GPU to the game and was steadier. (GPU stays available behind a switch.)
- **Frame-time profiler.** The pause screen separates "the game is slow" from "the tracker is slow" (physics, HUD, focus, model,
  patch fit, post time), so tuning is measured, not guessed.
- **Render-scale governor (opt-in, `&rs=`).** Tried, measured, and left *off* by default: on the test laptop the extra
  resolution was not what limited the frame rate, and resizing the 3D buffer cost its own hitches.

## 3. A sharper iris than the landmarks give

- **Limbus ring fit.** Landmark irises are a few pixels coarse. EyeLab's trick, now shared with the games, is to fit the dark
  ring where the iris meets the white of the eye directly in the pixels of the eye patch. On synthetic data it recovers the
  centre to about 0.04 px RMS, even from a bad landmark starting guess; the crop reader recovers a synthetic eye centre to
  about 0.07 px.
- **Measured along the eye's own axis.** The iris position is projected onto the line between the eye corners, not the camera's
  horizontal axis. Otherwise a rolled head (17° in one test run) or a squint leaks vertical eye movement into the horizontal
  signal, as large as the usable signal itself.
- **Iris inside the eye, not "where on screen".** Screen gaze mixes head turn into the answer (about half of a 10° head turn leaks
  in). The control signal for the Carve level is the iris position *inside the eye opening*, a pure eye signal that only spans a
  few percent of the eye width. A head turn with a still iris does nothing; a glance does.

## 4. No calibration: learn the person while they play

The rule was: **no staring at dots**. Everything is learned from ordinary use.

- **Per-eye fusion (`EyeFuse`).** Each eye keeps its own recent samples and is automatically weighted (0.2 to 0.8) by how
  stable and symmetric it is right now. This is what makes glasses, a squint, or one eye partly hidden by a nose or reflection
  survivable.
- **Your own centre.** The straight-ahead reference is the median of your first readings, then drifts only slowly and only
  while you are near it, so holding a look for seconds does not re-centre onto it. If the reference goes stale (head shifted,
  light changed) a recovery path notices the signal has been pinned for about 2.5 s and re-centres, rather than leaving the
  reticle stuck in a corner. The vertical axis does the same.
- **Your own glance size.** The signal is scaled by the 95th percentile of *your* recent glances (with a floor tied to your
  measured noise and a cap), so a small, lazy glance and a wide one both reach the edges of the screen.
- **Start-up without a jump.** The first valid readings pin the centre to the screen middle, and any change in regime (the
  fusion becoming ready after ~150 samples) resets the reference and fades the steering back in over 1.5 s.
- **Direction check.** The mirror direction is verified against head turns while the head is still, and corrected if it is
  backwards. There is a manual reverse button as an override.

## 5. Make a slow, noisy signal feel fluid

- **One-Euro filters** (adaptive low-pass: heavy when still, light when moving) on the iris signal.
- **Lingering.** The control value is an exponential average over about 0.12 s, so a split-second glance is noise-free and a
  real look comes through.
- **Reach and look-smoothing.** The reticle offset is multiplied by a reach (1.3) and smoothed with a ~70 ms constant, which
  turns 10 to 30 readings a second into smooth 60 fps motion.
- **Noise floors are measured, not assumed.** Fixation noise is estimated in fixed-size blocks of samples (so it does not
  depend on frame rate), and a glance is not counted as noise.

## 6. The biggest win: change what the eyes are asked to do

At 10 to 13 fps and 200 ms of latency you cannot steer a board at 50 m/s by pointing a cursor with your eyes. So the eyes do not
steer. They **decide**.

- **Eyes choose, the board carves.** Looking at an opening for about 0.22 s latches it, and the board is pulled through it.
  The raw look only *trims* the line (low gain, lower still once something is latched). You glance, linger, fly through, and
  decide again.
- **Guidance scales with speed.** The pull toward a gate starts earlier in metres as the hill speeds up, so it stays the same in
  seconds. If the chosen gate is too far sideways to reach in the distance left, the board takes the nearest reachable gate and
  keeps your choice if the tracker drops out inside the last 14 m.
- **Lone trees and rocks dodge themselves.** A swerve solver finds the smallest sideways shift that clears everything ahead,
  with a last-moment nudge. The challenge is the *decision*, not pixel-perfect avoidance.
- **A wrong choice is recoverable.** Picking the wrong gate carries you through it for small points and a toast, instead of
  a wipeout, so you can recover on the next one.
- **Fair by construction.** The safe gate never moves faster than 0.3 m sideways per metre of descent, extra gates are only
  placed where they can be reached, and singles keep clear of the safe line.
- **Safety nets.** A look that flips side to side is softened (flail guard), a lost tracker freezes steering instead of
  steering wildly, a crash grants a grace period, and the board can never be carried uphill or backwards.
- **Buffs are looked at, not just driven through.** Look at a boost, shield or double-points pickup for a moment and the board
  leans toward it; the avoidance still keeps you off the trees.

## 7. Measure it: tests that run without a camera, and one that runs with it

- **TRACE test** (pause menu, key T, or `&trace=1`). Follow a moving dot, then react to jumping dots, then carve a highlighted
  line. The game fits the tracker's latency, gain and wobble, and reports least-squares fits of the dot against the iris signal,
  the screen gaze and the head, alone and combined. That answer decides what is worth fusing, using data from the actual person.
- **Closed-loop simulations.** Headless tests drive the real game with a simulated player: noisy eyes (up to 14% of the screen),
  150 ms of delay and 15 Hz readings, full 4200 m runs, wrong picks 30% of the time, a player hunting buffs. They print crash
  counts and *what* each crash hit (barrier or single, speed, sideways speed), which is how tuning stayed honest.
- **Synthetic-signal tests.** The OLS fit, the stale-centre recovery, the direction check and the limbus fit all have tests with
  known ground truth.
- **A pause report you can paste.** Tracker fps, latency, frame drops, fixation noise, event log and crash log all come out as one
  JSON blob. Most of the improvements here started with a pasted report.

## 8. What did not work (and was reverted)

- A tighter steering cap (about 35°): it removed the authority needed to reach far gates, and crashes went from 0 to 12 in
  the clean-eye simulation.
- Letting an avoidance swerve override the gate pull: swerving is almost always active at a barrier wall, so it fought the
  gate every time.
- A GPU render-scale governor on by default: no gain on integrated graphics.
- Using the screen-gaze point for control: it includes the head, so a head turn beat the eyes.

## 9. Known limits

- The tracker is the bottleneck: roughly 10 to 13 fps and 200 ms on an onboard GPU. A faster machine or camera improves feel
  directly. Low exposure light makes many webcams cap near 15 fps.
- Results are tuned on one 1080p30 webcam setup. Glasses, head roll and dim rooms are handled, not solved.
- Real-camera numbers for the newest control changes are collected by playing and pasting the pause report; the simulation is a
  proxy, not proof.

## Where to look in the code

| Idea | File |
|---|---|
| Workers, crops, limbus fit, EyeFuse, packets | `godot/scripts/GazeCamJS.gd` (embedded JavaScript) |
| Filters, `direct`/`eih` signals, camera status | `godot/scripts/GazeProvider.gd` |
| Eyes-only offset, centre/scale learning, stale-centre recovery | `godot/scripts/DownhillRig.gd` (`_eyes_only_offs`) |
| Gate choice, pull, swerve solver, buffs, TRACE | `godot/scripts/CarveRig.gd` |
| Simulated players and signal tests | `godot/tests/carve_test.gd`, `godot/tests/trace_test.gd` |
| The plain-web version of the same pipeline | `eyelab/index.html` |
