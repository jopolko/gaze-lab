---
name: feedback-never-scroll-menus
description: NEVER add scrolling to any menu/page in Downhill; fit it by scaling/trimming instead; START must always be reachable
metadata:
  type: feedback
---

Never make a menu, tab or card scrollable. The user said "NO FUCKING SCROLL SHIT, burn this into your memory" after I set the menu ScrollContainer to AUTO to fix START being pushed off screen (2026-11-18). It was already a rule ([[feedback-downhill-preferences]]: no-scroll menus) and I broke it.

**Why:** scrolling on a phone is awkward mid-setup, and the user has asked many times for START to be pressable on the psych level.

**How to apply:** when a page is too tall, scale it (`_fit` in DownhillMenu), merge rows, hide help text, cut options. Keep `_scroll.vertical_scroll_mode = DISABLED`. START (footer) must always be on screen on a phone in landscape and portrait; check by screenshotting at 924x412 before deploying menu changes. Before any menu edit, ask whether it adds a row (new rows are what pushed START off).
