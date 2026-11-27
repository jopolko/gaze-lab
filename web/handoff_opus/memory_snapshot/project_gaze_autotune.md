---
name: gaze-autotune-system
description: Silent eye-tracking doctor + health logging across all Godot apps; dev URLs/flags, local servers, what is opt-in (state 2026-11-13)
metadata:
  type: project
---

Goal (user, 2026-11-13): one bare URL for everyone, no params; the system diagnoses and fixes eye-tracking problems itself in EVERY Godot app, with the same logging; the user validates fixes afterwards. Users must never need to know the toggles.

Built: GazeProvider health sampling (all apps, tagged app/who/sid/device/hw), GazeDoctor (Downhill barrier metrics -> one fix at a time, verify after 6 barriers, revert if worse; params p_linger/p_pull/p_carve/p_reach), health rules (median/hold/narrow-range sweep), auto calibration sweep once per visit in every app, Peek fixation-error rule, Kalman + EyeBias + EyeSweep, GazeTune lit-gate trials (dev only), consent prompt for sharing numbers off dev hosts, tools/collector.py (VPS endpoint, NOT deployed).
Bare URL opens Downhill (menu -> OTHER GAMES reaches the rest). Dev extras: ?dev shows the EYE OPTIONS panel (O), ?who=name overrides the anonymous id, ?noauto turns the doctor off.
Local testing: `python tools/serve.py` (http://localhost:8060) and `--lan` (https://<laptop ip>:8443, self-signed, gzip); logs to tools/logs/<id>/, frames (opt-in) to tools/frames; watch live with tools/watch_tune.py. Prod posts nothing unless the user consents (then /gaze-lab/log, needs the collector + nginx).
Doctor coverage is deep only for Downhill barriers; Peek has a fixation-error rule; flight/trance/gazetest/arena get health rules + auto sweep + logging only.

**Why:** user is the human test subject and wants zero-knowledge users. **How to apply:** extend the doctor with per-app outcome adapters rather than adding toggles; post test links in replies (see [[feedback-post-links]]); deploy only to godot-dev unless asked (see [[gaze-lab-layout]]).

**VPS collection (live 2026-11-13):** /var/www/html/gaze-lab/log.php (source tools/vps/log.php) appends whitelisted numbers to /var/lib/gaze-lab-logs/<id>/<date>.jsonl (outside web root, www-data:john 2770). Players off dev hosts are asked once to share, or a link with `?share=1` pre-agrees (son: `...godot-dev/?who=son&share=1`). Read with `sh tools/pull_logs.sh` (copies down + summarize.py). Images never go to the VPS (frames only on the laptop's servers). Build is on godot-dev only; the live /gaze-lab/godot/ is the old game until the user says.
