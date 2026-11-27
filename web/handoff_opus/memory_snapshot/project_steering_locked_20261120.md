---
name: steering-locked-20261120
description: "Head-steering tuning the owner accepted on 2026-11-20 (committed 1af910f, live in gv.js); do not retune without a reason from them"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-20T20:18:58.534Z
---

Owner: "we've nailed down the tuning. fix it at what we just did." Live defaults in gv.js (promoted from gv_dev.js, commit 1af910f on worlds-and-realms): prediction `pred` 130 ms, `gain` 0.7, `smooth` 12, tracker model input `inw` 256, aim style, ramp pull (`vxcap` .1 far out, full 34 m/s at the mouth `vxmouth` 30 and along the sides `vxside` 10, aim follows the ramp `vxsteer` .6), steering meter hidden unless `&meter`.

**Why:** measured on the owner's C920 + T14 (about 20 readings/s, model 35-40 ms, about 110 ms head-to-screen) and a Pixel-class phone (15/s, model 50-65 ms); the owner rated this much better on desktop and phone. See [[downhill-state-20261120]].

**How to apply:** treat these as the baseline; changes need a measured reason (the lab, `&diag` log). Next focus is gameplay design (seek-and-destroy slalom, progression), not steering.
