---
name: gaze-lab-perf-harness
description: "How to measure Downhill stalls without the user's Chrome (headless Chrome + prof.html), and what caused the gate/loot freezes"
metadata:
  node_type: memory
  type: reference
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-14T23:47:03.007Z
---

Measuring the web build (gaze-lab/godot), written 2026-11-14:

- `node tools/perf_run.mjs [seconds]` launches its own headless Chrome (real GPU, empty profile, no camera), loads `http://localhost:8060/prof.html?autopilot&nocam`, rides on autopilot and lists every frame over 50 ms with the WebGL calls that took the time. Needs `tools/prof.html` copied into `build/web` after each export (finish_export does not copy it).
- Claude in Chrome / the built-in pane throttle a background tab to ~1 fps, so they are useless for frame timing. Use the harness.
- `tests/gen_prof.tscn` (headless Godot) times script cost per frame; script cost at a gate is under 10 ms, so stalls are graphics-side.

Findings that explain the freezes (see [[project_gaze_lab_state]]):
- Godot frees a BaseMaterial3D shader when the last material with that flag combination is freed, and rebuilds it (5 programs, 100-400 ms on the UHD 620) next time one is made. Per-event materials caused the freeze at every gate and pickup. `Mats.keep_alive()` holds one of each kind for the session.
- Each shader has separate programs for: batch (MultiMesh) or single, lit by an omni lamp or not, and colour grading/glow on (finished in post) or both off. A quality-tier change flips the last one for every material at once.
- `RunRig._warm_shaders()` builds them at the first run start behind GET READY (6-8 s once on the laptop). Open idea: make the title backdrop use the same grading/glow mode as the run so that build happens during the load the player already waits for.
