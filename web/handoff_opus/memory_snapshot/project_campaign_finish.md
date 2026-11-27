---
name: campaign-and-finish
description: Downhill levels should chain into one epic campaign building to a climax; finish arch built on dev 2026-11-21, campaign NOT started
metadata:
  type: project
---

Original plan (restated by user 2026-11-21): all Downhill levels lead into each other as an epic campaign; trip onset, waves etc. build to one major climax. User said not to build it yet.
Courses had no finish (lap wrapped with a hard white cut at WORLD_END). Built FINISH on dev only (gv_dev.js): chequered arch 150 m before WORLD_END, burst + 1.5 s white fade, lap resets under the white; &nofinish disables; window.__FINISH.

**Why:** the instant restart read as a glitch/death to the user.
**How to apply:** campaign = next phase after finish is accepted; hook level hand-off at FINISH.done() instead of the lap wrap. See [[journey-mode-vision]].
