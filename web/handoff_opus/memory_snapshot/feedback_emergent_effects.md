---
name: feedback-emergent-effects
description: "User wants effects emergent from the landscape's own patterns, never a distinct overlay image; path must stay fixed and readable"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-18T18:51:18.465Z
---

Effects must emerge from the landscape's own patterns (moire dots/squares across mountains, foliage, sky), never a distinct image floating or filled with its own colour, and never a full-screen blur/tie-dye wash. The ground squares must stay fixed to the world as you speed past (never rescaled), and the road/path must stay clean and clearly separated from scenery.

**Why:** 2026-11-18, user rejected repeated "floating face" attempts, the rainbow wash, and ground squares that shifted. Wants vague, barely-noticeable faces on terrain (some players notice, some don't), a bold whole-sky "god looking down" face as a separate rarer set piece, and mosaic cells filled with moire driven by the same variable knobs.

**How to apply:** Before adding a visual effect, ask whether it lives IN a surface (ground/trees/mountains/sky pattern) rather than ON the screen. Always run the Godot headless compile check and only deploy if it is clean (a broken build went to godot-dev twice because deploy.sh swallows errors). Keep every effect behind a knob in the FX lab (F2 / ?fxlab).
