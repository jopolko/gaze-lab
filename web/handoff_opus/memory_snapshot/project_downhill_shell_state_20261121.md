---
name: downhill-shell-and-main-promotion-20261121
description: Downhill main link now runs inside shell.html (iframe) for fullscreen/sound persistence; gv.js == gv_dev.js after promotion; rollback .bak files; what is untested
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-21T04:38:20.177Z
---

On 2026-11-21 main (`web/downhill-three/gv.html` -> `shell.html` iframe -> `gv.html?inshell=1`) was switched to the shell so biome switches keep fullscreen and the browser's sound permission. `gv.js` was overwritten with `gv_dev.js` (identical); old copies saved as `gv_prev_main{,2,3,4}.js.bak` and `gv_prev.html.bak` on the VPS and locally. `&noshell` opens the game bare (use for perf harness/tools). The owner confirmed "Works" for camera, fullscreen and music through the shell.

**Why:** browsers only allow fullscreen and sound after a tap, and a page reload (the biome picker) drops both; the iframe reload keeps the outer page's activation.

**How to apply:** promoting dev to main needs the owner's explicit go-ahead (the harness blocks the copy otherwise); test with `&nomusic`; physics "feel" numbers (accel/grip/roll/airg/blast/launch/stick) are untested by ear/hand and tunable via link params; the in-pane sim runs in slow motion so it cannot time rides. Related: [[feedback-downhill-preferences]].
