# Prompt: build with this eye-tracking kit

Paste everything below the line to Claude, with this folder available to it (unzipped in the project, or attached).

---

I have a working in-browser eye-tracking module that I want you to use as the control input for a new project. Use it as it is; do not rewrite the tracking or swap in another library unless I ask.

## What I want built

[DESCRIBE THE NEW DEMO HERE: what it is, who it is for, what the eyes should control.]

## What is in the kit

- `tracker.js` — the whole tracker, one ES module, about 270 lines, no dependencies except the MediaPipe files below. Read it first.
- `vendor/mediapipe/` — MediaPipe tasks-vision 0.10.14 (`vision_bundle.mjs`, `wasm/`, `face_landmarker.task`). `tracker.js` loads these by path relative to itself, so keep this folder next to it. About 23 MB; nothing is fetched from a CDN.
- `example.html` — the smallest complete use: open camera, calibrate, then a dot follows the gaze. Start from its calibration loop.

## How it works

Camera frame → MediaPipe face landmarks → seven features (iris position inside each eye opening measured along the eye's own axis, upper-lid height, head yaw and pitch, face position in the frame) → ridge regression to screen position. The regression is fitted per session on a roughly 10 second "follow the dot" pursuit. The fit also searches for the eye-plus-camera lag (0 to 0.42 s), drops outliers once, and rescales each axis so a weak axis still reaches the screen edges. Output goes through a One-Euro filter whose strength follows the fit quality. Gaze is held steady through blinks. Blinks are measured against each person's own resting lid level, because the raw blink score for "open" varies a lot by person and by phone angle.

Everything runs on the device. No frame or landmark leaves the page; keep it that way.

## API

```js
import { Tracker } from './tracker.js';
const tracker = new Tracker(videoElement);      // <video playsinline muted autoplay>
await tracker.start(onStage);                   // call from a tap; onStage('camera' | 'model' | 'ready'); throws if the camera is refused

// calibration
tracker.beginCalibration();                     // start recording features
// each frame while the dot moves: targets.push({ t: performance.now() / 1000, x, y })
const r = tracker.finishCalibration(targets);   // { ok, quality, r2x, r2y, lag, n, rms }

// read every frame
tracker.gaze        // { x, y } calibrated and filtered, -1..1, x right, y up (not pixels, not y-down)
tracker.raw         // { x, y } uncalibrated eye direction, usable before calibration for "it sees you" effects
tracker.face        // a face is in view
tracker.closed      // both eyes shut now
tracker.closedFor   // seconds they have been shut
tracker.onBlink = (duration) => {};             // a blink of 0.04 to 0.55 s finished
tracker.fps, tracker.delegate                   // tracker rate and 'GPU' or 'CPU'

tracker.nudge(ex, ey);    // drift correction: pass (known target - tracker.gaze) when you know where the user was looking
tracker.sim = true; tracker.setSim(x, y);       // touch or mouse stands in for gaze (no camera needed)
tracker.stop();
```

## Rules for using it well

1. **Calibrate with a smoothly moving dot, never a jumping one.** The fit assumes continuous pursuit. Log the dot's true position with `performance.now() / 1000` timestamps on every frame it is drawn.
2. **Respect the quality gate.** If `r.ok` is false, say so and offer a retry and a way to continue or switch to touch. Do not silently proceed.
3. **Treat gaze as coarse.** Accuracy on a real phone has not been measured. Design for errors of a quarter of the screen: large targets, continuous steering with a dead zone, dwell-to-select with visible progress. Never require the user to hit something small.
4. **Never let the user be stranded.** Provide a touch or mouse fallback through `sim`, a recalibrate button, and a visible "looking for your eyes" state when `tracker.face` is false.
5. **Give the user real control.** Do not add aim assist that takes over; the user notices immediately. Slow drift correction through `nudge` is fine.
6. **Show the user where the tracker thinks they are looking**, at least subtly, so they can compensate.
7. **Do not use fast flashing or strobing** as feedback.
8. **Camera needs HTTPS or localhost.** A phone on the LAN needs an HTTPS server, and a self-signed certificate is fine. Start the camera from a user tap.
9. **Keep the render loop light.** The face model shares the main thread and the GPU with the page. Expect about 20 to 30 tracker updates per second, so interpolate or filter anything driven by gaze, and lower the render resolution if the frame rate drops.

## Known limits, be honest about them

- Verified only with a synthetic fit test, a still-image camera test and a touch stand-in. Live accuracy on a phone, iOS Safari behaviour and phone frame rate are untested.
- One face only. Glasses, low light, backlight and a phone held low all make it worse.
- Calibration is per session and assumes the head stays roughly where it was; large head moves need a recalibration.
- `tracker.js` contains a one-line shim (`globalThis.dbg`) that this MediaPipe build needs; do not remove it.

## How to check your work

Serve the folder and open `example.html` first to confirm the kit works on this machine. Add `?fakecam=<image url>` to run the whole pipeline on a still photo of a face when no camera is available (it should load, find the face, and report a weak lock). Tell me plainly what you tested and what you could not.
