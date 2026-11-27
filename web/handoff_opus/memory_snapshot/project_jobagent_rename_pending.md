---
name: jobagent-rename-pending
description: "Finish the lookout -> jobagent rename (package, env var names, secrets file, data dir) only when the user has free usage credits"
metadata:
  node_type: memory
  type: project
  originSessionId: 0d59ee97-9cbc-4d75-b06f-9512492e1f4d
  modified: 2026-11-11T00:36:07.798Z
---

jobagent's rename is half done on purpose (see `jobagent/docs/HANDOFF-rename.md`): package `lookout`, `LOOKOUT_*` vars, `/var/secrets/lookout.env`, `/var/lib/lookout` still use the old name. The user dislikes the two-name inconsistency and wants it finished, but **only when they have free usage credits** (said 2026-11-10); don't start it unprompted.

**Why:** they want it done but it costs real session usage, and production changes need an explicit "deploy".
**How to apply:** when they say credits are free, do it staged: rename locally with `JOBAGENT_*` accepting old `LOOKOUT_*` as fallback, run tests, then server rename with symlinks at old paths at deploy time, remove fallbacks after ~2 stable weeks. Server-side secrets are never printed.
