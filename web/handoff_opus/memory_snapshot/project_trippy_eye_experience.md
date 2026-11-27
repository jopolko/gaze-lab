---
name: trippy-eye-experience
description: "User's chosen direction (2026-11-11): a trippy, eye-tracked, profoundly sensory experience, starting fresh; the Godot demos were judged unplayable and deleted; ANOMALY parked"
metadata:
  node_type: memory
  type: project
  originSessionId: 0d59ee97-9cbc-4d75-b06f-9512492e1f4d
  modified: 2026-11-12T23:00:48.578Z
---

After weighing ANOMALY directions (AR creature game, Wi-Fi X-ray, sensor challenges) and finding none clearly viable for a solo builder, the user said they'd rather make **a trippy eye-tracked experience that stimulates the senses profoundly**. ANOMALY (`projects/anomaly`) is parked; its mockups remain in `anomaly/assets/mockups/`.

**Correction (2026-11-11):** the user said Ocular Trance had "nothing fun or compelling", its controls were "completely broken", and it was an unplayable demo; they **deleted it along with the other Godot face-control demos** (see [[face-control-games]], now obsolete). Do NOT assume the Godot project, shader, TrackerBridge or EyeLab exist or build on them; verify on disk first. Treat this as a fresh start.

**Status 2026-11-12:** user liked only the "Inner light" mode (felt instantly responsive, "quite profound") and asked to drop the others. Built `projects/trance-sketches/inner-light.html` (single page, WebGL feedback shader + WebAudio, MediaPipe via CDN) mapping ~20 face/eye signals to visuals+sound: per-eye lids, lid flutter, saccade rings, fixation crystallising, pupil (experimental), brows, smile, jaw, squint/wide, head steer/roll, eye misalignment/tilt -> image blur. Webcam path not yet tested by me; user tests and reports. Older `index.html` (A/B/C sketches) left in place.

**Why:** user's goal is an experiential piece, not a market bet. Webcam gaze precision is the known hard limit (user measured 29.7% error on desktop; iris moves only ~3-5 px across the screen), so design around coarse gaze zones, blinks, eyelid closure, head pose and fixation, not pointing. Past demos failed on feel and controls, so reliability of input matters more than visual ambition.
**How to apply:** user wants visuals/sketches before big builds. Prove the experience feels good with mouse/touch stand-in first, then wire in tracking. Keep photosensitivity safe (max ~3 flashes/s, intensity slider, warnings, no strobe-style flicker); make no therapeutic or brainwave claims.
