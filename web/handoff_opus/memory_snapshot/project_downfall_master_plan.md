---
name: downfall-master-plan
description: "Downfall master plan v1 (2026-11-21): full campaign, 7 episodes, Fall Line theme, Predicted You, redaction layer, viral engine; doc web/docs/DOWNFALL_MASTER_PLAN.md"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-21T17:42:39.116Z
---

2026-11-21: owner chose the FULL CAMPAIGN and asked for the perfect, viral, watchable creation: kept molecules, AI censorship, climate (as accelerant not sermon), psychedelic gameplay, face-steered ride, wry tone and their values. Master plan is web/docs/DOWNFALL_MASTER_PLAN.md (supersedes GAME_SPEC + both story bibles where they disagree).

Core: title DOWNFALL, "the only way out is down"; the Fall Line (the Rail's blind spot); surprise is the last unforgeable thing; Rail suffers model collapse (eggshell palette); WREN = the Rail's first guard, defected; Unlisted creatures (Chuck the marmot mascot); Predicted You ghost rider; redaction layer un-redacts with each Piece; 7 episodes of ~12 min; modes Episode / Binge / Daily / Chill / Pass the Face / Stream; viral: Rail Rating, Daily grid, ride-line+molecule certificate, Clip it, weekly premieres.

**Why:** owner wants to sit down and play/watch an episode; classic AAA aspiration.
**How to apply:** build Phase 1 = Episode 1 slice first (awaiting their go and answers to the six open decisions at the end of the doc). All names fictional, both political swings satirised equally, face data stays on-device, no commit unless asked. Related: [[downfall-story-bible-v2]] [[whole-vision-gentle-stakes]]

**Pilot build status (2026-11-21):** &pilot flag on gv_dev.js only (prod untouched): eggshell grade via postM bcs, wall redaction bars with [ PAUSED ] tags (terrain shader), colour won back per pickup, 17 s Meridian cold open (CSS, skippable, once per visit, &nocold hides). Still to build: Koan, Predicted You, noodle stall, Interzone gate, end card/Rail Rating. Claude Motion exists (beta, Team/Enterprise) but is not callable from Claude Code; use code-drawn motion in-game, Claude Motion for trailers.

**Pilot status update (2026-11-21, later):** built on dev only: Koan + Predicted You (PX in gv_dev.js), end of run -> NOODLE STALL overlay (Koan, notebook, radio line, next-time) -> optional NEWSPRINT BAZAAR (&bazaar: halftone paper world, sideways splices) -> RAIL RATING card (predictable %, band label, share text, play again). Session state in sessionStorage gv_pilot. Pilot link: shell.html?play&head&noshare&theme=alpine&course=long_alpine&js=gv_dev.js&nojourney&pilot . Untested: real head steering/phone, natural finish-arch trigger (stall was opened by calling __nextBiome), ghost visibility, Skew feel. Not built: drive leg between descent and stall.

**Pilot v2 (2026-11-21, promoted to PROD behind &pilot):** Predicted You now lays black [ PAUSED ] strips on the ground (ride through = Paused/colour dips, ride round = Skew); ghost waits in next strip; glyph gate (newspaper) halfway -> Newsprint Bazaar; ~9 s cold open; first molecule = staged SUNGLASS moment; snowball renamed THE BACKLOG and held to ~62% of the course, drawn 2.3x, escape = colour surge (pxBoss). Rating card = % of the Rail's pauses walked into. Perf checked on Intel UHD 620 (58-60 fps steady, pilot same as base). Docs reconciled: web/docs/DOWNFALL_README.md is the index; DOWNFALL_FACTIONS_AND_NAMES.md is the naming authority. Prod gv.js == dev gv_dev.js (backup gv_prev_main42.js.bak). Dev/prod pilot link: shell.html?play&head&noshare&theme=alpine&course=long_alpine&nojourney&pilot (add &js=gv_dev.js for dev). Test harness: scratchpad evalrun.mjs/shot3.mjs/perf3.mjs drive headless Chrome with real GPU; the game lives in the shell iframe (use contentWindow). Still unverified: real head steering/phone feel.

**PARKED 2026-11-21 (owner request):** the story pilot is switched off in prod and dev; it runs only with &story (old &pilot ignored). Normal game unchanged (still has this week's asked-for changes: contour lines, Centre button, rocket-at-end, opt-in sharing, new start-card face). Do not build more story/faction work unless the owner asks.
