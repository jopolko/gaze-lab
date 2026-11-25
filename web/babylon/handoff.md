# Handoff: Babylon.js Downhill port (written 2026-11-22, before a context compaction)

## What this is
`web/babylon/index.html` (one file, one `<script type="module">`, ~200 KB) is the Babylon.js 7 version of the Downhill / Trip game. Goal from the user: **identical to the three.js original** (`web/downhill-three/`, source of truth = the code, not screenshots), running on Quest 2 (WebXR, head steering), phone and desktop. They test on a Quest via the LAN server and can only refresh `menu.html`.
Companion docs: `web/docs/TRIP_EFFECTS_PARITY.md` (every effect, element, parameters, status; keep it updated).

## Run / test
- Server: `python tools\serve_lan.py 8090 http` from `web/` (**keep it running**, user asked). Also HTTPS on 8447 / 443 for the Quest. Sends `Cache-Control: no-store`.
- Pages: `http://localhost:8090/babylon/index.html?nomusic&biome=<alpine|psychedelic|candy|egypt|tunnel|desert|matrix|synthwave>&r=<n>`. `&biome=` beats the saved choice (localStorage `bab_opts2`). `psychedelic` is called **Trip**.
- Menu: `web/menu.html` appends `?v=<time>` to every card link on load.
- Embedded browser tab used for tests: `tab-12`. **`computer wait` max is 10 s.** The Edit-tool hook opens a `file://` preview tab after each Edit: close it (`tabs_close`) or it clutters.
- **No debug handle any more** (user asked to remove `window.__bab`, `window.__psy`, `?iwer`, `?fakecam`, all `/vrlog` logging). Verify by: `node --check` of the extracted module script, loading the page, `read_console_messages` with pattern `Uncaught|ReferenceError|TypeError|ERROR: 0|redefinition|undeclared|Unable to compile`, and reading `#status` text. Babylon prints shader compile errors to the console (look for `BJS - ... Offending line`).
- Syntax check recipe (python, then node): extract `re.search(r'<script type="module">(.*?)</script>', s, re.S)` to `_chk.mjs`, `node --check`, delete it.

## Editing rules learned the hard way
- The file has **CRLF** line endings. Python: open with `newline=''`; use `NL` handling when matching multi-line strings.
- **bash heredocs / tool params mangle `\\n` and backslashes** (a real newline appears inside JS strings, or comments swallow code). Write patch scripts with the **Write tool**, then run them; for single replacements use the Edit tool. After every patch run the syntax check.
- A trailing `// comment` on a line swallowed following code twice (updateMats, ring body). Use `/* */`, and put a newline before appended GLSL when a body ends in a `//` comment.
- GLSL: a variable named `gl_` is reserved (broke the world once). Redefinitions (`gEmi`, `instanceColor`) kill the shader silently: the mesh just doesn't draw. Check the console.
- Babylon: `infiniteDistance = true` **plus** a hand-set position doubles the offset (that was the "globe"). Both are now false; sky and trip dome are moved to the camera each frame.
- Babylon `instancesDeclaration` already declares `instanceColor` when a thin-instance colour buffer exists: do not declare it again.
- Thin-instance picking needs `thinInstanceEnablePicking`; instance buffers are kept (`s.__buf`) and updated with `thinInstanceBufferUpdated('matrix')`.

## Architecture (main sections of index.html, roughly top to bottom)
1. Imports: `heightfield.js`, `gvmusic.js`, `looper.js`, `molecules.js`, `molmesh.js` (constants), `psyfx.js` (the REAL trip director), `postfx.js` (the REAL Godot picture-pass shader text via `toGLSLPost` + a stub THREE). `PSY = createPsyFx({ fx:{x_level:.6}, seed:7, sessionMin:10, journey: world !== psychedelic, ... })`. `WORLD0` = chosen world. BTRACK music table, `gmStart` (biome track or the adaptive stems).
2. Course load: `data/long_s7/{meta,physics,row_NN}.json` (22 rows). `geometry(def)` now uses each dumped mesh's real `surfaces` (v,n,i,uv,c) for ALL classes (quads are 8x8 etc.). `addInstance` splits batches **per 180 m row** (frustum culling does the culling; `alwaysSelectAsActiveMesh=false`). Records `ANREC/BYNAME/BYIID` per node instance. The level's own nodes (mountain ring `1620 verts`, terrain skirt `4656`) are loaded first from `meta.nodes`; ring is a separate mesh moved with the board (`cam y - 1.7 - 159.696`).
3. Materials: `material(id,...)` classifies by dump shader code: ground (`snowMat` port, all 7 styles, + `gpsy` = WFX.ground for Trip), veg (`VEG_PSY`), back (HORIZON BEND ring), quads (`quadMatFor`: additive shaft shader / tint gradient), `stdMat` (StandardMaterial3D: lit + `glowLit`, unshaded + `glowify`, emissive solids brightened, three-style squared fog after tone curve), else the old generic `psy` shader (halos, molecule parts). Common GLSL in `GW_H`: `s2l/l2s/hsv/vn/fbm3/lit/finish` (Cineon + exposure 1.05, Godot fog), `uLite` (cheaper ground for the headset when the tuner sheds), `psyfx()` extra moire/glow layer (**off by default**, not in the original; pause-menu switch `moire+glow`).
4. Skies: `SKYB` bodies (alpine = real procedural sky, psychedelic = SKY_PSY, others from biomes.js) + `skyFor`. Trip-only layers `TRIPFX` (sky dome polar/tunnel, sky bands, mountain skin) driven by `PSY.world()`.
5. Biome pieces: ring skins (`RBODY` from rings.js), silhouettes (`ringShapeVD` from ringshape.js), biome props (biomeprops.js, per-row seeded), weather (weather.js table + shaders, egypt storm, tunnel rush), name tag/title/banner.
6. Physics/board (`step`, `vortexStep`, constants): "type 1" handling. Steering feel = `headCond` (Trip head conditioning: sticky centre, backlash .012, adaptive low-pass, swerve, speed ratio, variable-ratio curve) then a rate-limited rack + self-centring at speed + the original adaptive spring (12 rad/s) + heading tau .05. Head reading itself stays raw. **Car-like lift**: ground-glue threshold lowered (`.15 + .012*speed`), `stickT .35` after landing.
7. Pickups: molecules from `molecules.js` as instanced meshes (`molGeo`), beams, bob/spin; collecting calls `PSY.pillEat`, `GM.onMolecule`, `FXB.E.pillEat`.
8. Effects: `FXB` (fx.js port: bursts, sparklers, rings, bubbles, confetti, spray, boost trail), `ECHO`, `CARVE`, `DROPS` (sky drops), `BEATFX` (music-clock beat: exposure x(1+.07p), fov x(1+.018p)), HUD tint rects in the picture pass (hurt .22, flash .3).
9. Animation: `animStep` (pickup roots bob/spin/extras tumble, pad gems turn+bob, vortex ring wobble) writing into instance buffers; `hideRecs`; `shaftStep` (light-shaft molecules, every Nth shaft drawn, grown 1.6x), `gazeOrbStep`, `airStep` (air-chain rings + landing ring).
10. Camera/XR/UI: Babylon WebXR with reference-space offset to move the rider; headset HUD plane (head-locked, bottom, **only `NN fps  cur / target Hz`**); flat-screen status line same; picture-pass `PostProcess` (flat only); tuner: effects shed ladder -> render scale (WebXR `requestViewportScale`, 100%->60%) -> refresh rate; restore order resolution first. Pause menu (P/Esc, strip top-left) with layer switches, world select, `copy diag`; **right-click copies a piece's metadata to the clipboard** (user pastes it to Claude).
11. No on-screen callouts: `big()` is a no-op (user: "no more boost or landed").

## User preferences (don't relitigate)
- Source code is the source of truth, not screenshots (they said so twice). Do not take screenshots for porting; numeric/console checks are fine. They get angry at repeated questions: **act, don't ask**.
- Stats popup: fps and Hz only. Stats box at the bottom. Pause menu small, never blocks the view.
- Head tracking stays precise; steering feel should be car-like (see item 6). Tyres held straight by movement/weight.
- Quest performance matters a lot: last real log (before shader work) was GPU-bound 19-25 fps, 2.9 M tris, tuner at max shed. Lighter ground + row culling + render-scale step were added; **no Quest log available now** (logging removed). Any new effect costs GPU: keep a budget.

## Still NOT ported (full list given to the user)
Picture/look: tracer ghosts (needs frame-history pass), face + god (face texture `face_tone.png`, worldfx2 FACE shaders), (vector/ASCII DONE 2026-11-22: `LOOK`/`lookPulse`/`psylook` pass, flat only; "psy" pulse falls back to vector), glow pyramid (Godot bloom; none in the headset), snowball/cue tints, realm caves (`realms.js`, not used by long_s7), terrain-skirt strata variant, Alps ring is flat/unlit (unconfirmed), pickups are my own molecule meshes, candy props use 6 fixed tints, matrix music file `moodless_refrain.mp3` missing.
Gameplay DONE 2026-11-22 (untested by eye): toys.js run for real (`createToys`, `toysStep`, import map to three for matrix maths), `KITL` hoops/targets/streams, super-ramp flag. Also DONE (untested by eye): zones + phrase deck pads/powerups, banks, slalom pylons (see parity doc 'Eighth round' for the deviations). STILL NOT: snowball, chaos event, hazard zones, `singles`, spawn.js molecules (the original's molecule source), tree hiding for the saw. (ring bell is not called by gv_trip.)
Director wiring: PSY events onRail/onPop/onGlint/onCheer/onSnowball/onFinish, FX apex burst, perks (speedK etc.) not applied, molHurt on crash.
Other: course streaming/`trip_plan`/`trip_compose` (Babylon loads a fixed 22 rows), biome profiles (density etc.), camera rig (`camrig.js`), HUD molecule bar/score, per-event sound wiring (`audiowire.js`, `sfxset.js`).
Unread files that may hold more: `pickupmesh.js`, `lab.js`, `tiers.js`, `hud.js`, `profile.js`, `spawn.js`, `names.js`, `phrases.js`, `icons.js`.

## Other projects touched this session (state)
- three.js VR build: `web/downhill-three/gv_trip.js` + `vr.html` (copy of gv.js with XR). Godot web build with `XRMode.gd` in `godot/` (`/godot/` on the server). Unity starter in `unity/DownhillQuest` (APK build blocked on OpenJDK module in Unity Hub; HUD still small).
- Music files copied to `web/music/` (stems, funk, plus bouncer/dnb_minute/electric_exodus from `music_new/`).

## Suggested next steps
1. Ask the user for a fresh Quest result (they must paste any numbers now) and judge perf before adding effects.
2. Wire the director events + FX apex/ring-bell (cheap), then HUD molecule bar, then snowball/kit/toys if wanted.
3. Tracers / glow pyramid only with a performance plan for the headset.
4. Keep `TRIP_EFFECTS_PARITY.md` current after each port.

## 2026-11-22 later
Lip blast bug fixed (`lipStep` after the move). Dump powerups hidden; beacons (rays) added; molecule psy pulse on surfaces (`PSYPb`); snowball.js boulders via `sbScene` mirror. 'Chaos' is not a Trip event (menu preset / SUPFX pattern). Still not ported: SUPER (supercharge) mode and its look, `singles`, spawn.js, hazard zones, saw tree hiding, per-event SFX, camera rig.

Picture pass: gv.js is the reference (journey mode everywhere, PK-scaled uniforms, pass only while PK>0). Headset pass `XRP` (untested on a Quest). Test flags: `&postcap=4` forces the flat pass, `&xrfx=0` disables the headset pass. The pane resolves `localhost` over IPv6 sometimes and gets refused: use `http://127.0.0.1:8090/...`.

Trails + glow chain: `warpShader().build(camera, ratio, full)` makes [bright, down, down, feed, main]; the main pass is reusable (ping-pong) and the feed reads its other texture (`_textures`, `_currentRenderTextureInd`, Babylon internals). If a Babylon version change breaks the trail, look there first. Headset: `XRP` levels 0 / 1 full chain, 2 main only, 3 off.

## Fifteenth round
Sound (sfxset + audiowire), finish + lap reset, original obstacleStep/crash/spill orbs, singles, perks, looks and trails/glow chain (own history textures), rails, deck, banks, slalom, boulders, headset pass (XRP). LAN servers restarted with backlog 256. Not applicable: spawner, supercharge, chaos. Still open: spring open-end flight, tonemap/grade/sharpen, lean axis, hazard zones, face/god, realm caves, strata. Everything headset-side is untested.
