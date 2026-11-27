---
name: no-auto-steer-visible-choices
description: Downhill must never steer by itself; choices must be real objects far apart on screen so the player can see their eyes are in control
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-15T21:38:06.490Z
---

In Downhill (gaze-lab) the board must not turn on its own, and the things to choose between must be real world objects placed far apart across the screen. The user asked for this several times on 2026-11-15 ("objectives farther apart so the player has a choice", "no way to know if I'm being auto-steered or if tracking is working") and was angry that I answered with HUD markers and diagnostics instead.

**Why:** the winding trail's follower turned the board 10-15 degrees on the first bend with hands off; the user read that as broken tracking for several rounds. Objects 6.5 m either side of the middle were near screen centre, too close for the phone camera to separate.

**How to apply:** hands-off must ride dead straight and earn nothing (tests/lean_probe checks heading stays 0). Default is the open straight slope (`?winding` restores the old trail), objects 15 m either side, board position follows the look. When the user asks for a gameplay change, make that change in the world first; overlays and logs are extras, not a substitute. See [[gaze-phone-tracking-findings]].
