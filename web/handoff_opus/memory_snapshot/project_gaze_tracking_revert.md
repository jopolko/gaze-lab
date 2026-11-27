---
name: gaze-tracking-revert-2026-11-14
description: "Downhill tracking broke after commit 7eef287; work now on branch tracking-works (7eef287 + Kalman, median 1); all later work is in a git stash"
metadata:
  node_type: memory
  type: project
  originSessionId: 1804e927-9051-4067-9f2d-f1c299a3cedd
  modified: 2026-11-14T15:15:58.534Z
---

On 2026-11-14 the user's tracking was dead on desktop and phone in every build after 7eef287 (committed bisect: baseline 1c5a9c5 also bad). 7eef287 tracked. User asked to revert to it.

State: git branch `tracking-works` at 7eef287 (+ small edits, uncommitted): bare URL opens Downhill (?level=peek for Peek), GazeKalman.gd added, Kalman ON by default with median window 1 (user tested `?kalman` = better than One Euro + 5-median; plain Kalman with median 5 felt worse). `?nokalman` restores old chain, `?median=N` sets the window.
All later work (realms, vortex, loot targeting, doctor/tuner/AUTO card, logging, capture, chunked terrain build, Start button, fullscreen, preview hidden) is in `git stash@{0}` ("wip before revert to 7eef287") on main (at 1c5a9c5) and copied to C:\Users\josh\projects\gaze-lab-wip-backup-1114. `git switch main` + `git stash pop` brings it back.

**Why:** committed diff 7eef287..1c5a9c5 changed only: Kalman filter default, AIM_MAX_DIST 125->190 and `engage_far` early pull (game pulls to a locked gate from up to 190 m), stickiness 0.7->0.85, live doctor/tuner (changes p_pull/p_reach, camera cap/res, saved in browser storage), sweep calibration. The eye pipeline (JS tracker, geometry gaze, iris fit, EyeBias) is unchanged by default. Cause not isolated; suspects were the early pull/190 m lock and stacked Kalman+median.
**How to apply:** bring later features back onto tracking-works one at a time, user checks tracking after each; do the steering changes (early pull, 190 m lock) last or not at all. The USB camera (Logitech C920) was used in all builds; camera choice was NOT the cause (user corrected me). Face-found/tracker-rate logs do not prove gaze is accurate: the yellow-ring offset is the only real accuracy signal. Test servers: local ports 8060/8443 serve godot/build/web; Windows reboot kills them (restart with python tools/serve.py [--lan]).
