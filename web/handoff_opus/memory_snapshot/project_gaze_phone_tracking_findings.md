---
name: gaze-phone-tracking-findings
description: What was learned 2026-11-15 about why STARGAZE tracked on the phone and Downhill did not; trail game state
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-15T17:52:28.253Z
---

Findings from 2026-11-15 (phone = Android, Opera, Mali-G715; logs on the VPS under /var/lib/gaze-lab-logs/<who>/):

- STARGAZE always runs a ~10 s "follow the spark" fit before flight and flies on the fitted gaze (ridge regression over iris, lid, head yaw/pitch, face position). The user remembers it as "no calibration"; it is not. Its uncalibrated `raw` reading, ported to Downhill as scripts/KitEye.gd, moved only about +-0.1 to 0.2 on the phone and did not steer ("zero tracking").
- User said "I don't want the calibration unless necessary" and that vertical tracking was absent in STARGAZE. Phone is held about 45 degrees tilted with the head pitched about 33 degrees down.
- Downhill now has a 7 s sideways-only follow-the-dot step at the start of a phone run (RunRig `_calib_tick`, `?nocal` skips, `?calib` forces on a laptop). The result is posted as telemetry kind `calib` (r2, lag, eyes share, gain). As of this note nobody has confirmed it on the phone: check that record first.
- Trail game: riding the middle earns nothing by design; poles, ramps, rails and loot lines sit to one side and a look to that side takes them; three goals per run; modes `score` (Freestyle) and `race`. User had complained "no reason to steer, no objectives" and "too many bouncy things".

- Log analysis later on 2026-11-15 (user phone anon-2d3a37 run 566a5f; second phone anon-836734, Adreno 660, portrait, two riders on one session): the dot fit passes (r2 0.89) but only 28-43% of it is eyes; while riding the fitted reading correlates ~0.1 with the raw iris reading and 0.3-0.7 with head pose, sits past the look line 85-94% of the time, pins at the +-1.2 clamp. So it follows how the phone is held, not the eyes. On the second phone the face was lost for 64% of the ride (stretches of 55-100 s); KitEye froze its last value, the chart counted that as "eyes left", nothing told the player, and the fit was never redone for the second rider. Eye-check advice ("bring the phone up") comes after the fit and the pose change then biases it. Not yet fixed as of this note.

**Why:** several rounds were lost porting the wrong piece (raw reading instead of the fit).
**How to apply:** before changing phone tracking again, read the latest `calib` and `kit` telemetry rows; do not assume a signal works because it worked in another demo without checking which code path that demo used. See [[project_stargaze]] and [[project_gaze_lab_state]].
