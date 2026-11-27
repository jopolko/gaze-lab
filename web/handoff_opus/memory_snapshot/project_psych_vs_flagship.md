---
name: psych-vs-flagship-levels
description: "Plan for the three.js Downhill: psych wide level is the dev bed and strictly for tripping; flagship Downhill covers all biomes and effects; where code, backups and the branch live"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-19T18:49:33.278Z
---

Decision 2026-11-19: the **Psychedelic** wide level (web/downhill-three/gv.html, default `level_wide2_s7`; `?classic` = narrow Godot dump `level_psy_s7`) is where features are developed; it is **strictly for tripping**. The **flagship Downhill** mode is to cover all biomes, experiences, effects and levels as a full, varied taste of everything, and gets features ported over from psych in pieces as needed.

**Why:** psych is the intense trance experience; flagship is the broad product ("trying to sell this thing" eventually).

**How to apply:** keep psych-only content (dose/felt trip model, clarity, heavy post effects) separable from shared systems (physics, chains, lock/pull, spawn generator, music director) so they can move into flagship with other biomes. Don't merge psych-only effects into flagship by default.

**Flagship shape (user, 2026-11-19):** the hub and the buggy are being dropped ("liking them less as I grow older"). Downhill is ONE complete guided experience and a showcase of everything: the player is led through all options and combinations like a trip coming on: initial doses, flashes, waves of effects building to a full-blown experience, a climax, then a chill-out ride to calm them down, entice them to do it all over again. Spine = Godot's journey director (DhJourney waves + DhPacer session curve, already ported in psyfx.js with journey:true) across all biomes; psych level stays the strictly-tripping dev bed.

State at this point: branch `psych-wide-level` (commit e6a5c5a, local only, never pushed: remote is public). Restore snapshots: C:\Users\josh\projects\gaze-lab-backups\RESTORE.md (and ~/gaze-lab-backups on the VPS). Ported-but-not-yet-wired modules: toys.js (wired), snowball.js, gvmusic.js, psyfx.js, sfxset.js, carvetrail.js, echoes.js. See [[project_downhill_state_20261117]] for the older state.
