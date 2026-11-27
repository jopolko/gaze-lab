---
name: smash-derby
description: Smash Derby prototype (2026-11-21): web/downhill-three/derby.html + derby.js, deployed beside the game; demolition derby in a neon bowl, 6 cars, head/touch/keys steering, tuning notes
metadata:
  type: project
---

Owner's structure: long peaceful trippy drives between arenas (the existing downhill game) alternating with aggressive over-the-top trippy demolition derbies. Built the derby as a separate standalone page so the main game is untouched: https://joshuaopolko.com/gaze-lab/three/downhill-three/derby.html (flags: &auto computer drives your car, &calm, &nomusic, &bots=1..7).
Design: bowl arena R=92, 6 launch ramps, mounds, AI rivals with simple names (DOZER, BLAZE, TWITCH, MAMA BOLT, CHROME...), ramming damage by speed and angle (hit sides/rears, protect your front), pickups (health, boost, overdrive), callouts (FIRST WRECK ... GODLIKE), synth music + engine + crash sounds, speech announcer, post pass (chromatic aberration, speed streaks, hue shift in overdrive). Head steering copies gv's maths (steer = -(pr - neutral)*k); keys , and . change sensitivity, R recentres.
Checked: headless Chrome real GPU 60 fps, layout_check modes dmenu/dend/dhud pass 5 sizes, round flow play->dying->over verified, head sign/neutral logic verified with injected samples. NOT checked: real face steering, phone feel, audio by ear, whether AI is fun.
Next ideas if liked: more arenas/themes, car upgrades from calm drives, link drive->derby, weapons (tap auto-aim), tuning k for head.

**Speedway version (2026-11-21, after the owner said the free-turning derby didn't suit the soft/slow head control):** speedway.html + speedway.js. A huge banked round track (radii 74-112 m); every car is steered onto the track (wanted velocity = round the track at cruise speed + a sideways drift from the lean), so the player only leans across lanes (no turning); chase camera; boost button; two wrong-way drivers (BLAZE, CHROME) with a WRONG WAY AHEAD warning and a minimap ring; wrecks stay on the track as hazards for 9 s; same ramming damage idea, callouts, audio and post FX as derby.js. Verified: 60 fps headless, lean direction test (right = inward for dir +1), full round flow, layout_check dmenu/dend/dhud pass. Unverified: real head steering/phone feel, chase-camera motion comfort (the view turns ~20 deg/s round the circle), AI fun. Tunables: MAXLAT, steer smoothing .16 s, lateral/tangential response (.34/.3 s), RIN/ROUT. derby.js (the free-turning version) is kept.
