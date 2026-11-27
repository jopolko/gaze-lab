---
name: project-babylon-reconciled-20261124
description: "Babylon build state 2026-11-24 - reconciled design doc, RUSH meter, tutorial, smoke test; ready for Opus/Fable audit"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-24T00:59:37.812Z
---

Babylon build (web/babylon/index.html) now has: one-voice message queue (top card), RUSH dopamine meter (`DOP`, right-edge bar, full = 9 s x3 points + smash), tutorial (`?tutorial=1`), Route Zero re-spaced by distance, `tools/smoke.mjs` (17 checks, run before every deploy). Single source of truth: `web/docs/RECONCILED_DESIGN.md` (systems, gap list, questions for the next reviewer).

**Why:** user wants a release-ready game with the builder owning craft/coverage; they only decide taste. They asked to be told when it is "ready for opus" (and curious about Fable 5.2, costly) - audit is the big cross-cutting job, building stays on Sonnet.

**How to apply:** read RECONCILED_DESIGN.md first; keep replies short; give full URLs; run smoke.mjs after any deploy and add a check for every new feature or bug. Not yet verified: real phone/head feel, sound, strike level not started.

See [[feedback-autonomy]], [[feedback-short-sequential-replies]].
