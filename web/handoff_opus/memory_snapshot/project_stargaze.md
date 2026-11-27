---
name: stargaze-threejs-demo
description: "STARGAZE = three.js eye-tracked phone flight demo in gaze-lab/web/stargaze (built 2026-11-15 to impress the user's 21-year-old son); how to serve and test it"
metadata:
  node_type: memory
  type: project
  originSessionId: 0c1ca384-64ee-4990-8c6d-50954a9d1843
  modified: 2026-11-15T12:45:32.900Z
---

Built 2026-11-15 in `projects/gaze-lab/web/stargaze` (index.html, main.js, tracker.js, serve.py, vendor/ = three 0.160 + MediaPipe tasks-vision 0.10.14 + face model, self-contained, uncommitted on branch winding-trail).

Serve: `python serve.py` -> http://localhost:8070/ ; `python serve.py --lan` -> https://<laptop ip>:8470/ (reuses godot/tools dev cert). Ports 8060 and 8443-8447 belong to the Godot build servers (see [[gaze-autotune-system]]); never kill all python.exe to restart one.
Flags: `?debug` (camera preview + tracker numbers), `?fakecam=<image url>` (still image stands in for the camera, for pipeline tests), "Play by touch" = no-camera mode (Space = blink / hold = eyes closed).

Tracking: ridge regression from 7 eye/lid/head features to screen, fitted on a 10 s follow-the-spark pursuit (lag search, outlier pass, gain rescale, weak-lock fallback); blink measured against the player's own resting lid level.

State when written: verified by me only with touch stand-in, a synthetic fit test, and a still-image camera test. Real-phone gaze accuracy NOT measured; the user and their son are the test. Post links per [[feedback-post-links]].
