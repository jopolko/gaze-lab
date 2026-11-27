---
name: overlay-layout-check
description: Every full-screen text overlay must pass web/tools/layout_check.mjs (phone sizes, reduced motion on/off) before deploy; the cold open once jumbled all its lines together under prefers-reduced-motion
metadata:
  type: feedback
---

2026-11-21: the owner saw the opening (cold open) screen with all text jumbled together and unreadable, and asked to fix it and make sure it never happens again. Cause: with prefers-reduced-motion the code showed every absolutely-positioned line at once, stacked on each other. Also the start-card face (skin-coloured round face with a nose) read as a pig, and at narrow widths the fps readout sat on the biome tag.

**Why:** overlays were only eyeballed at one size with animations on, in the browser pane.
**How to apply:** build text screens as ONE slide at a time in one centred, wrapping box (no stacked absolute lines). Before deploying any overlay or HUD change run `node web/tools/layout_check.mjs <cold|card|stall|rating|hud> "<url>" <outdir>` (5 sizes, reduced motion on and off, checks visibility/topmost, overlap, off-screen) AND open the saved screenshots. Test the checker against a known-bad build when changing it. Related: [[feedback-never-scroll-menus]]
