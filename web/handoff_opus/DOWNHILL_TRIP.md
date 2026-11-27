# Downhill TRIP mode (local only, 2026-11-22)

One long, shaped descent through all seven worlds, composed in the browser from rows of your four long Godot dumps. Nothing here is deployed.

## Play it locally
Serve `web/` (`python -m http.server 8077` from `C:\Users\josh\projects\gaze-lab\web`), then open
`http://localhost:8077/downhill-three/shell_trip.html?play&notap&theme=alpine&trip=35&seed=1`
- `trip=` total minutes for all seven worlds (14 to 70, default 35 = 5 min each). Also a setting in the gear panel ("Trip length (minutes)"), which changes the next world you enter.
- `seed=` same seed, same course. `theme=` the world to start in (alpine, candy, desert, tunnel, matrix, synthwave, psychedelic).
- `shell_trip.html` is the shell that hands over between worlds with a crossfade. Without it: `gv.html?noshell&js=gv_trip.js&...` (a biome change then reloads the page like before).
- `play&notap` is only needed on a machine with no camera (testing). With a camera use `&head` like the normal game.

## How it works
- `trip_plan.js`: the planner. Each world has its own arc (launch, flow, set pieces, breathers, climb, the dive, run-out, finale), picks rows by role (intensity from pickups, toys, jumps, molecules; grade from the slope), and only chains rows whose ground meets (edge matching, under 0.35 m).
- `trip_compose.mjs`: moves a chosen row into its place (positions, node names, ids) so the same row can appear in different places. Verified: composing a dump's own rows in order gives the dump back unchanged (`node tools/trip_compose_test.mjs`).
- `data/bank/`: every source row as two files (`*.p.json` light physics, `*.json` heavy nodes+meshes) plus `shared.json`; made by `node tools/build_bank.mjs`. `data/trip_edges.json`, `data/row_catalog.json`: ground edges and row stats.
- `gv_trip.js`: a copy of `gv.js` that builds its level from the plan instead of one dump, plus the handover (preload at 2400 m or 12% from the end, crossfade 600 m from the end). `gv.js` is untouched.
- `phrases.js`: call-out phrase pools, not connected to anything yet.
- `trip_preview.html`: the course map.

## Not done
- The last world (psychedelic) still ends the old way (result card, reload to the first world).
- Hand-play, phone performance, and real head-steering have not been tested; the bot only steers to the trail.
- Total download per world is about 17 MB uncompressed (shared 7.6 MB plus the rows); the shared file still carries the materials of all four dumps and can be slimmed.
