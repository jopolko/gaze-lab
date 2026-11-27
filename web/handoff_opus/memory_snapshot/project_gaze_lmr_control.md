---
name: gaze-lmr-control
description: "User's chosen phone control is a single row of left/middle/right (2026-11-16); detector built in Downhill and EyeLab, unmeasured on a real phone"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-16T21:59:35.669Z
---

On 2026-11-16 the user decided the phone game needs only a snappy, accurate left / middle / right read (one row, three columns, targets inside the screen), not continuous gaze and not rows. They will design the game around that.

Built the same day, same method in both places (iris along the eye only, dot jumps M/L/R for ~8 s to learn the three resting places, median of last 3 readings, side at 0.5 of the way to the target, back to middle at 0.3, slow drift follow, no time smoothing):
- Downhill: `KitEye.gd` (`finish_zones`, `zone`, `zn`), RunRig calibration phases reuse the eye-check flow; `eye_now()` returns the zone; logs `calib`, `eyecheck` (hits of 8, react), `lmr_trace`. Deployed to godot-dev as build dac0d98f.
- EyeLab: "Left / middle / right (full screen)" button; logs `eyelab_lmr_cal`, `eyelab_lmr`, `eyelab_lmr_live`, plus the 10 Hz `eldiag` records. EyeLab also now follows phone rotation (picture shape, screen width, camera side).

2026-11-16 later: dots removed by default (auto zones learned while playing; `?calib` / `?eyecheck` bring them back, `?cards` brings the fixed side circles back); every object is selectable (rings on objects), hazards, jump vortex+boost, switching window 130 m. Phone (Mali-G715, 924x412) ran 12-37 fps with the tracker on; the user reported right-side picks favoured. `choice` log records now carry `pz/pzn/zm/pnx` (zone reading and learned m/dl/dr at lock time) for checking that bias.

**Why:** continuous gaze on the phone was too weak (one iris pixel is ~7% of screen width); three columns is about the limit of what the camera can separate.
**How to apply:** only simulated eyes have passed (8 of 8). Before tuning thresholds, read the real `eyelab_lmr*` / `eyecheck` records: `sep` (side move in units of noise, needs >= 2, good >= 4), hits, react ms. The user wanted to try it in EyeLab first. Nothing committed as of this note. See [[gaze-phone-tracking-findings]] and [[no-auto-steer-visible-choices]].
