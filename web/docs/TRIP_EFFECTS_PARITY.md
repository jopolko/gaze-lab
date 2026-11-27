# Trip level: every effect, what it touches, its settings, and whether Babylon matches

Written from the three.js game's source (`web/downhill-three/`): `psyfx.js`, `postfx.js`, `worldfx.js`, `worldfx2.js`, `gv_trip.js`, `glowify.js`, `biomes.js`.
Status key: **SAME** = ported from the same source and driven by the same numbers. **PARTIAL** = ported but something is missing (said which). **MISSING** = not in Babylon.
**NOT AUDITED** = a source file I have identified but not yet read line by line; it is on the list at the end, so nothing is silently skipped.

Babylon file: `web/babylon/index.html`. The trip director in Babylon is the real `psyfx.js`; the picture pass is the real Godot shader text through `postfx.js`.

---

## 1. The trip director (psyfx.js, "DhPacer / DhJourney / the dose model")
It decides every number below. In Babylon it is the same module, so these are SAME.

| Part | Settings |
|---|---|
| Session clock | 10 min default (`?min=`). Phases: settle 0-.07, come up .07-.30, peak .30-.52, plateau .52-.70, comedown .70-1.0. Targets: .12->.75->1->.65->0. Calm start 20 s. |
| Molecules | six: mescaline, DOM, 2C-B, 2C-E, 2C-T-2, 2C-T-7. Eating one: dose to 6 (first time) or +2, flash 1, sharpen .7, trip +.25. Body follows dose (rise time 25 s, fall 8 s). |
| Pieces of the world | molecule i reveals piece i: 0 ground, 1 sky, 2 colour (trees), 3 mountains, 4 ripples, 5 pulse. `pk(i) = smoothstep(.04,.45, level_i) + flash*.7`, times the clarity factor. |
| Journey worlds | alpine start; arc: psychedelic, candy, tunnel, synthwave, matrix, psychedelic, desert, egypt (strengths .36 .48 .60 .72 .84 1.0 .60 .40). Stages arrive in order sky, ground, trees, light. |
| Moment of clarity | picture drops to 0.1 of its strength, snaps back to 1.3. |
| Sharpen / buzz | rare crisp snap (sharp 1, eases off); slow buzz waves. |
| Face and God | timers: face 60 s then every 70-150 s for 14 s; god 150 s then every 200-360 s for 26 s. |
| Defaults (`FX_DEFAULTS`) | x_level 0, x_pieces 1, x_wander .6, g_sq/g_shape/g_col/g_tri/g_rad/g_warp/g_glow 1, t_sway 1, t_breathe .6, t_moire 0, m_moire 1, m_breathe .5, m_polar 0, s_bands 1, s_polar .45, s_tunnel .6, p_wash 0, p_face_auto 1, p_god_auto 1, p_chroma/trace/punch 1, p_glow .35, p_bloom .4, p_haze .55, p_tube 1, p_warp 1, p_pulse 1, p_fold 0, p_rings 0, p_dmtr 0 |

Babylon: SAME for the director. DIFFERENT: Babylon's TRIP world runs it "plain" (not journey), so all pieces are available from the start; Alps and the others run it as the journey (picture pass parked until onset). The molecule's body-dose delay means a freshly eaten molecule shows nothing per-molecule for the first ~25 s (also true of the original).

## 2. The picture pass (the whole screen), `post_psy.gdshader` via `postfx.js`
Applies to the finished frame. Modes: 1 psychedelic, 2 digital (matrix), 3 synthwave. TRIP and TUNNEL use mode 1.

| Effect | Parameters (defaults in the shader) | Babylon |
|---|---|---|
| Breathing warp | `breathe`, `amount`, `k_warp` 1: `sin(TIME*.7 + r*9) * .0012` radial warp + `sin(uv.y*14+TIME)*.0008` wobble | SAME |
| Six molecule warps | mA.x mescaline slow warm waves (.002), mB.y 2C-T-2 ripples running out (.0015, `sin(r*34 - TIME*3)`), eased down at the centre (`keep`) | SAME |
| 2C-E fold (mandala) | `k_fold` 0 (off by default), segments 6 + 2*dmt | SAME (off) |
| 2C-T-7 pulse | `k_pulse` 1, `pow(max(sin(TIME*6),0),3)` push-in .006 | SAME |
| 2C-B colour split | `k_chroma` 1, (.003 + r*.012) * (1 + trip*.5 + mA.z*.5 + dmt*.6) | SAME |
| Tracer ghosts | `use_trail`, `k_trace` 1, ghost hue `fract(TIME*.12 + r*.9 + m*.5)`, needs a stack of recent frames | **MISSING** (forced off: no frame history) |
| Hue wash | `k_wash` 0 | SAME (off) |
| Saturation punch / bloom term / sharpen contrast | `k_punch` 1, `sharp`, `buzz` | SAME (in the shader) |
| DMT rings, tube rays and rings | `dmt`, `tube`, `k_rings` 0, `k_dmtr` 0 | SAME |
| Onset band | `onset`, `horizon` .42 | SAME |
| Face (a woman's face in the light and shade) | `face` | **MISSING** (forced 0) |
| Rewind tear, boost smear | `rewind`, `smear` | SAME shader branches; the game events that drive them are **MISSING** |
| Cel outlines and bands | `k_edge`, `k_cel`, `edge_hue`: 0 | SAME (off) |
| HUD tint rects under the pass | snowball .16, cue .07, hurt .22, flash .3 | **MISSING** |
| Vector / ASCII looks | `lookM` (gv_trip.js 605) | **PORTED (Babylon, flat screen)**: Matrix holds ascii .5, Synthwave vector .5, other worlds get a 2.4 s moment on a molecule (Trip .4 s). Fire/super variant and bypass mode not ported. Not in the headset (no post pass there). |
| Environment tonemap + glow pyramid + colour grade feeding the pass | Cineon, exposure 1.05; glow intensity .35, levels (0, .8, .4, .1, 0), bloom .1, hdr threshold 1, saturation 1.15, contrast 1.1 | **PARTIAL**: Babylon runs its own bloom/imageProcessing in the flat view; nothing in the headset |

## 3. The world, per element
Colour rule everywhere: mix in authored sRGB, convert once with `s2l`, Godot fog `1 - exp(-density*dist)` before tone mapping, then Cineon with exposure 1.05.

| Element | Original | Babylon |
|---|---|---|
| **Sky: alpine** | procedural sky: top (.18,.42,.9), horizon (.98,.84,.72), ground (.8,.85,.95); sun disc 38 deg, curve .1, sun colour (1,.88,.72) | SAME |
| **Sky: psychedelic (SKY_PSY)** | palette `0.5+0.5cos(2pi(t+(0,.33,.67)))`, bands `sin(az*2 + y*5 + ...)`, base (.10,.01,.16) | SAME |
| **Sky bands quad** (`SKY_SHADER`) | additive 1500x520 plane 620 m ahead, 250 m up; k = `max(sky_flash^2*.9, .30*pk(1)*breath)` | SAME |
| **Sky dome** (`SKYDOME_SHADER`): DOM polar field + 2C-T-7 tunnel | additive sphere; polar = s_polar(.45)*pk(1), tunnel = s_tunnel(.6)*pk(5) | SAME shader; was drawn as a ball (bug, fixed this round) |
| **God in the sky** | face on the dome, 26 s | **MISSING** |
| **Ground: alpine / terrain (snowMat)** | natural terrain by region (6 palettes), dirt road with ruts, edge, snow sparkle, contour lines (alpine [.55,.9,1], alpha .55), half-width 6 or 11 | SAME (all styles 0-6 ported) |
| **Ground: psychedelic (GROUND_FRAG)** | two grids, third grid, bullseye rings, warp; grid, glow, m_cell 6, m_ratio 1.037, m_depth .12, m_sat, m_hue, m_tri, m_rad, m_warp, drift; palette a(.30,.08,.55) b(.95,.50,1) line(1,.9,.3), mix .85; 6 m squares with 24 m / 96 m far fades | SAME |
| **Trees: VEG_PSY** | hue `fract(z*.012 + x*.007 + TIME*.07 + lum*.2)`, neon sat .85, `mix((.03,0,.06), neon*.75, smoothstep(.1,.9,lum))`, emission `neon*smoothstep(.35,1,lum)*.75`; far lum flattens 70-240 m | SAME |
| **Trees: sway / breathe / moire skin / face print** (`VEG_LIVE`, wob = pk(5)*(1+.5pk(5)), breathe = pk(5)*t_breathe .6, moire = pk(2)) | only used for the live alpine tree; not used by the default game | not needed |
| **Mountain ring** | vertex-coloured ring (1620 verts) moved with the board at camera y -1.7 -159.696; unlit `colour * (.84,.872,.97)` | **PARTIAL** (same ring and motion; the original's alpine ring may be lit) |
| **Mountain skin (2C-E)** (`MTNFX_SHADER`) | moire creeping with travel, rolling contour bands, polar field; mo_k = m_moire*pk(3), br_k = m_breathe*pk(3), pol_k = m_polar | SAME |
| **Mountain / sky / tree face prints** | portrait ink from the face texture | **MISSING** (needs `face_tone.png` wiring) |
| **Terrain skirt** | the sloping sides; strata hue by height in psychedelic | **PARTIAL** (drawn with the ground shader, not the skirt strata variant) |
| **Horizon bend** | `bend_k = .00012 * w_bend * (.4 + .6 speed)`, starts 140 m; w_bend defaults 0 | off in both |
| **Fog and light** | fog (.35,.05,.45) density .002; sun (1,.7,1) x .7; sky ambient (.0903,.0704,.1298) / ground (.10,.01,.16) x .9; Cineon, exposure 1.05 | SAME (taken from the dump) |
| **Environment blend alpine -> psychedelic** | fog .0012 -> .0016, sun energy 1.9 -> .7, glow .3 -> .35, saturation 1.1 -> 1.15, contrast 1.08 -> 1.1 | **MISSING** (no blend; each world is fixed) |
| **Glow on flat materials** (`glowify`) | fresnel rim `pow(1-|n.v|, 1.7)`, rim 1.6, beat .5, hue drift `fract(z*.004 + TIME*.05)` | **PARTIAL**: rocks and props use my generic shader instead |
| **Glow on lit white props** (`glowLit`) | tinted toward the world hue, rim emits light | **PARTIAL** |
| **Music beat on the picture** | exposure x(1 + .07*pulse), fov x(1 + .018*pulse), kick every beat, bigger on the bar | **PARTIAL** (Babylon pulses by game events, not by the music clock) |

## 4. Things I added to Babylon that the original does NOT have (now OFF by default, so Babylon matches the original; switch `moire+glow` in the pause menu turns them on)
- A baseline "moire + glow + breathing" layer in the ground, tree and mountain shaders in every world (from your "Psychedelic VR Effects" page: two sine grids x1.037, rim glow, bloom term, surface breathing). The original shows these only as the trip builds. Switch: pause menu `moire+glow`.
- Breathing vertex displacement on every surface (original: only trees, only with pk(5)).
- Rim glow on trees and mountains (original: not on VEG_PSY).

## 4b. Ported since the first version of this table
| Item | Source | Babylon now |
|---|---|---|
| Rocks and props: lit `StandardMaterial3D` with `glowLit` (rim 1.1, hue `fract(TIME*.04 + n.y*.12 + n.x*.09)`, +.6 beat), flat bars with `glowify` (rim 1.6, beat .5), three's squared fog applied after the tone curve | `gv_trip.js` matOf 312-325, `glowify.js` | SAME (15 materials compile) |
| Beat from the music clock: `kick = exp(-phase*7) * (bar line 1, else .55)`, pulse eased at 40/s (else decays 6/s); exposure x(1 + .07 pulse), fov x(1 + .018 pulse), ground speed + .22 pulse | `gv_trip.js` 1694-1695 | SAME |
| HUD tint rects under the picture pass: hurt red .22, flash white .3 | `postfx.js` hud() | SAME (snowball and cue tints still 0) |
| Weather: alpine snow 600 x .14 m in 76x30x76 m; candy sprinkles; egypt sand; desert dust; tunnel light streaks; matrix code; synthwave motes (storm event for egypt not ported) | `weather.js` CFG + shader | SAME (the world's own particles, same table and shaders) |
| Effect layer: sparkle bursts, sparklers, boost trail, expanding rings, shockwave bubbles, confetti, snow spray; Godot's particle rules and the web-build halving (x.5 counts, 12 bursts) | `fx.js` (whole file) | SAME; wired to: tree hit, pad, ramp blast, molecule eaten, orb, smooth landing, spray while grounded over 8 m/s, trail while boosting |
| Environment blend alpine to psychedelic (`WFX.envAt`) | `worldfx.js` | the game itself never calls it (checked: no use in `gv_trip.js`), so nothing to port |

Still **MISSING** after this round: tracer ghosts (needs a frame-history pass), the face and the god, vector/ASCII views, the glow pyramid (Godot glow) in the headset, light shafts with bonus molecules, ring-bell rock wobble, vortex swirl FX, snowball, echoes, carve trail, sky drops, hoops/rails kit, realm caves, camera fov punch / shake from `PSY.camera`.

## 4c. Biome effects ported in the third round (each from its own source file)
| Item | Source | Babylon now |
|---|---|---|
| Biome horizon skins (egypt sandstone with courses + gold tip, candy pastel hills, desert strata mesas with contour lines, synthwave neon wireframe, matrix black towers with code, tunnel neon bands) with the foot haze into the fog | `rings.js` BODY (verbatim) | SAME |
| Biome horizon silhouettes (desert mesas, matrix skyline, candy hills, synthwave retro peaks, tunnel: no ring) built from the original ring's bounding box | `ringshape.js`, `RING_KIND` | SAME |
| Biome props: alpine cairns / signposts / red-tipped poles, candy lollipops / canes / gumdrops, desert cacti / dead trees / boulders, matrix columns / slabs / cubes, synthwave palms / neon posts, tunnel ribs; the per-row dice roll (`mulberry(j*1319 + seed*17 + 5)`), distances 17-51 m from the trail | `biomeprops.js` | SAME geometry and placement rules (candy tint uses six pre-tinted batches) |
| Biome music: Trip electric_exodus .85, candy bouncer loop .8, tunnel dnb_minute loop .8 (trim 3.4), desert funk_express .45, matrix moodless_refrain .8 (file not on this machine: silent), synthwave quirky_funk .5, Alps the adaptive stems | `gv_trip.js` BTRACK, `looper.js` | SAME (paused with the menu) |
| Biome name: quiet label at top centre, tab title `Downhill · <name>`, big title in the world's own lettering for 4 s | `gv_trip.js` BTITLE | SAME |
| Picture-pass modes per world: only Trip, Tunnel (and the Alps journey) get the trip pass; matrix and synthwave have no pass in the game (I had wrongly given them modes 2 and 3) | `gv_trip.js` THEME_PK | SAME (corrected) |
| Astral echoes (4 ghosts, history 0.12 s x 16, index (i+1)*3, alpha .30*on*(1 - i/4), hue `fract(age*.15 + .13 i)`) and the chromatic carve trail (28 dots, drop 0.05 s, life 1.4 s, vx > 7 m/s, hue `fract(age*.3 + slot*.045)`) | `echoes.js`, `carvetrail.js` | SAME (echoes fanned to the sides, as in the first-person port) |
| Sky drops: a storm of smiling bombs with a growing ring on the ground, per-biome forms (jelly, snow puff, gumdrop, light bulb, pinata, data cube, disco ball); first storm at 55 s, then every ~60 s; a bonk is a stumble | `skydrops.js` | SAME |
| Trip director `x_level` .6 as in the game (it was 0 in Babylon) | `gv_trip.js` 571 | SAME |
| Unshaded emissive solids (rings, lip bars, poles, rails) get colour + emission x energy and no fog | `vortexfx.js` fixMaterials | SAME |
| Why vegBiome (tree materials per world) is not ported | `gv_trip.js` matOf order | the dump's tree shader is always VEG_PSY, which is matched before the per-biome tree shader, so the game never uses it for these courses |

**Node animation (fourth round):** pickup roots bob `a.y + sin(age*2.4 + ph)*.35`, their spin node turns about Y at 1.7 rad/s (2.8 for a boost) + ph, extra parts tumble about X/Y/Z at 1.4 / 1.9 / 2.3 rad/s + ph (gv_trip.js animTick); pad gems turn at 1.8 rad/s and bob .22 m (`p.gy + .22 sin(age*2.6 + ph)`, toys.js 161-165) and vanish when the pad is used; vortex rings wobble `Rz(spin * near * (1.2 + .5 i) * +-1) * Rx(pi/2) * scale(R, R, .7R)` with `near = 1 + 2.5 smoothstep(90, 10, dz)` (the 4-ring swirl: spin (2.2 + .7 i), baked scale), only while -40 < dz < 260 (vortexfx.js). A taken pickup now takes its halo, beacon and quad with it. SAME; checked by watching the instance buffers change (23 batches near the rider, 5 vortex ring batches).

**Fifth round:** the dump's soft glow quads and tint gradient are now drawn with the game's own `quadMat` shaders (they were opaque panels before: the "diagonal pillars" were the 13 x 64 m light shafts drawn opaque and four times too many); only every Nth shaft is drawn (Alps 8, candy 4, tunnel 6, desert 6, matrix 7, synthwave 6, Trip 4), grown 1.6 x about its foot, each holding a turning molecule worth 1000 (magnet 9 m, collect radius ~7.6 m); gaze orbs (look toward the side past 0.3, fill in 0.36 s, gold worth double, streak up to x8); the air-chain rings and the landing ring (`vortexfx.js tickAir / tickLand`); the tunnel's light-streak rush and Egypt's sandstorm (every 55 s for 14 s, fog to .016 and gold); camera shake from the trip director; dumped primitives use their true surfaces (a quad is 8 x 8 or 22 x 22, not 1 x 1); the steering feel (headCond + a rate-limited rack, self-centring at speed); a car-like lift off crests.

**Still not ported, with the reason:** the ring-bell rock wobble, the snowball, hoops / rails / bumpers (kit.js, toys.js), the tracer ghosts, the face and god, the vector / ASCII looks that the light-shaft molecules trigger, the glow pyramid. (Earlier list, now partly done:) gaze-orb dwell scaling (the original collects orbs by looking, Babylon by touching), the ramp air-chain rings and landing ring, light shafts with bonus molecules, the ring-bell rock wobble, the snowball (`snowball.js`), set pieces `kit.js` / `toys.js` (hoops, rails, bumpers need their gameplay rules), realm caves `realms.js` (only in barrier courses, not `long_s7`), the tracer ghosts, the face and the god, vector / ASCII views, the glow pyramid, camera shake from `PSY.camera`, the Egypt sandstorm event.

## 5. Gameplay effects still to audit and port (named so none is forgotten)
`fx.js` (particles: pillEat, pad, blast, orb, cheer), `toys.js`, `vortexfx.js` (ramp swirls), `snowball.js`, `echoes.js`, `carvetrail.js`, `skydrops.js`, `weather.js` (alpine snow: 600 white quads .14 m in a 76x30x76 box), `kit.js` (hoops, rails), `ringshape.js` / `rings.js` (mountain shapes and biome rings), `biomeprops.js`, `realms.js` (cave roofs, exposure), shafts of light with bonus molecules (`shaftmol`), the ring-bell struck-rock wobble (`ringBell`: 0.9 s, amp `(1-u)*.09`), camera feel (`fov_punch` decays 24/s, shake 1.6/s, flash 2/s), `lab.js`.


### Sixth round (vector/ASCII)
Babylon `index.html` now has `LOOK`, `lookPulse`, `lookStep` and a `psylook` PostProcess (edge glow and character cells, copied from gv_trip.js lookM). Molecule pickups call `PSY.events.onMolecule` (shake, flow, score), as the original does. The original never calls the FX apex burst or ring bell from gv_trip.js, so they are not gaps.

### Seventh round (gameplay pieces)
Babylon `index.html` now runs the three.js game's own `toys.js` (bumpers, colour gates, slings, spring pads with their tubes, course molecules, the MIX chain) on the same dump: three.js is loaded only for its matrix maths (import map to `stargaze/vendor/three`), and each node the toys move gets a stand-in whose matrix is copied into the thin-instance buffer (`toysStep`). Pads with a tube (`lk`) are skipped by the plain pad loop, as in gv_trip.js.
`KITL` ports kit.js `launch` / `buildTarget` / `targetsStep` / `buildRings`: leaving a ramp lip measures the flight, puts 3-5 hoops on it, a bullseye (50 / 150 / 500) and a 13-ring stream; `k.super` ramps add the +5 lift and 2.4 s boost. Callouts (toasts) are off by request.
**Still not ported:** kit.js phrase deck (pads / powerups boostrun, zigzag, fork, sweep, boostgrind), banks (shield / magnet / wings / saw inventory), rails and grinding, slalom poles (`SLN`), snowball, chaos event, the tube-end "open" flight. Untested by eye: no debug handle, so toys and hoops were checked only for load and console errors.

### Eighth round (zones, phrase deck, banks, slalom)
Ported from gv_trip.js / kit.js into Babylon `index.html` (block "ZONES, THE PHRASE DECK, BANKS AND SLALOM"): `zoneOf` (slalom / clear / content rows, from the dump), `zoneRow` (the dump's own pads hidden, springs thinned to 65 %, bumpers / colour gates / slings cleared from slalom and clear rows and thinned by biome density elsewhere), the seeded phrase deck (`planCourse`, `buildRow`: open, boostrun, zigzag, fork, sweep, boostgrind, warm) built five rows ahead with the real pickupmesh.js pad and icons.js powerup geometry (thin-instanced, near ones animated), the bank (shield, magnet, wings, saw; 2 each, spent automatically; shield absorbs a crash, wings double air steering, magnet widens the pickup reach, saw cuts obstacles for 5 s) and slalom rows (pylon fields and gate posts; a hit pylon flies out, a shield blasts the ones within 9 m).
**Differences, on purpose or for now:** the dump's own powerups stay (they are the molecules; the original hides them and gets its molecules from spawn.js, not ported); `singles` in clear rows are not built; a sawn tree stays visible but can be driven through; wings / magnet durations (8 s) and wings steer 2.0 are estimates (TUNE values not found); the original's deck has no rails, so grinding is not needed. No bank display (fps and Hz only, by request). Untested by eye.

### Ninth round (molecules, ramps, boulders)
**Ramp lip fixed:** the blast at a ramp's lip compared last frame's z with this frame's before the board had moved, so the two were always equal and no ramp ever threw the board (nothing pushed you through the vortex-ring arcs). It now runs after the move (`lipStep`).
**Molecules:** the course's own powerups are hidden as the original does (they were drawn as molecules, 90 of them); molecules are now the toys' pills, the shaft molecules and nothing else. **Rays of light:** beacons (gv_trip.js `mkBeacon`) over every molecule (7 x 160 m in its colour), deck powerup, deck pad and ramp. **Trip effect:** a molecule swells the surfaces' psychedelic layer for 2.6 s (`PSYPb`, gv_trip.js `__psychPulse`), in the headset every molecule (there is no picture pass there); the picture-pass looks (vector / ASCII) stay for flat screens.
**Boulders:** snowball.js runs unchanged (boulders are the default in the original), its three.js objects mirrored into Babylon instances each frame with the module's own rock shader; hits, dodges, escapes and the shield go through the same hooks as gv_trip.js. No red wash or text (no callouts, no overlays).
**Chaos:** in the source it is a Godot menu course preset (generator parameters) and a pattern name inside the supercharge look (`SUPFX`), not an event in the Trip game, so there was nothing to port; the supercharge (`SUPER`) look itself is still not ported. Untested by eye.

### Tenth round (the picture pass as gv.html has it, and in the headset)
Source of truth: `gv.html?course=long_s7` runs `gv.js`; its picture pass (`postM`) is identical to gv_trip.js's.
**Fixed to match gv.js:** the director runs in *journey* mode in every world (`journey: !Q.has('plain')`; Babylon had it off in Trip, which is why Trip lacked the mountains' moiré, the ground glow and the dose waves); the pass takes its numbers exactly as `applyPsy` does (mode 1, every trip uniform times PK, where PK = the psych layer: 1 in Trip and Tunnel, a 2.6 s swell of 0.85 on a molecule elsewhere, else 0) instead of a per-biome mode switch; the pass is attached only while PK > 0 (as in gv.js, other biomes have no picture pass between molecules); bloom weight follows `glowIntensityMul`.
**Headset:** the same shader and feeder (`warpShader()`) is attached to the WebXR camera at 0.6 of the eye size (a plain pass stretches it back), gated by PK; the tuner steps it 0.6 / 0.5 / 0.4 first, then the existing effect / resolution ladder, then drops it, and restores in the other order (`XRP`). `&xrfx=0` turns it off, `&postcap=0..4` forces the flat pass level (and stops the flat tuner) for testing. **Untested:** I have no headset emulator, so the XR path is written from Babylon's API and may need a fix on the first Quest run (a failure is caught and shown in the status line as "headset pass failed").
**Still missing against gv.js's chain:** trail feedback (`use_trail`, the tracer ghosts), the glow pyramid (Godot bloom; flat still uses Babylon's own bloom, none in the headset), the filmic tonemap and grade (Babylon's world shaders tone-map themselves with Cineon), sharpen, and the NaN repair. The vector / ASCII looks stay flat-only.

### Eleventh round (trails and glow)
The picture pass is now the whole `gv.js` renderPost chain as Babylon post-processes (`warpShader().build`): bright pass to 1/4 (thr 1, scale 2, bloom .1 x `glowBloomMul` + add, cap 12, expo 1.05), two 4-tap boxes to 1/8 and 1/16, the **trail feed** `max(c * .55, prev * .86)` with the .004 slow zoom (previous frame read from the main pass's second texture), then the Godot pass reading the scene, the feed (`trail`, switched by `use_trail`) and the three glow levels (.8 / .4 / .1 x .35 x `glowIntensityMul`) merged as `h + g - h * g`. It runs in every world, as postM does in gv.js (the psych layer only scales the trip numbers); Babylon's own bloom is off while it runs. Half-float stages. The headset runs the same chain at 0.6 / 0.5 of the eye size (level 2 = the picture pass alone, level 3 = off), stretched back by a plain pass whose input is the small texture; the tuner ladder is unchanged. **Untested in a headset.** Differences from gv.js: the scene is Babylon's display-referred picture (no HDR range above 1 except additive effects), so the glow threshold bites less; the filmic tonemap, grade, sharpen and the vector / ASCII looks in the headset are not done.

**Eleventh round fix:** the new Godot glow alone was too weak on Babylon's already tone-mapped picture and I had switched Babylon's own bloom off while the chain ran, so the colour bleed and bloom looked gone. Babylon's bloom is back on flat screens, and the glow's input is scaled by 1.9 so it triggers from the upper mid-tones. Trails: `use_trail` comes from the director (0 until the trip stages that use it); `&trail=1` forces it for testing. Checked: the main pass's two textures alternate every frame, so the feed reads the previous frame.

### Twelfth round (headset picture quality)
Causes found for crawling, thick lines in the headset: (1) the trail feed's history is one texture pair shared by both eyes, so each eye read the other eye's last frame (ghost lines): the headset chain now runs the glow without the trail; (2) the post chain's scene texture had no MSAA: it now has 4x in the headset (`samples`); (3) the Quest's default fixed foveation renders the edges of each eye at a fraction of the resolution: now 0 by default, `&ffr=0..1` trades it for speed; (4) the ground's grid lines were widened with distance (`0.035 + 0.0014 * dist`, up to 0.45 of a cell) and the moire was unfiltered: lines are now one pixel wide by `fwidth`, and lines and moire fade out when a cell is smaller than a few pixels. Untested in a headset.

**Beacons:** a beacon is now drawn only over something that is still there, still ahead of you and drawn (`vis` in `beaconTick`): passed ramps, passed or taken powerups, and pads / powerups whose model is not on screen no longer carry a light (in gv_trip.js the test was only the distance either side).

**Beacons, trimmed (by request):** only molecules (7 x 160 m, in their colour) and ramps (5 x 64 m) keep a light; pads and powerups no longer have one (gv_trip.js lights them all).

**Beacons, one group at a time:** only the nearest molecule group and the nearest ramp ahead keep a light (a group = the lights within 20 m of the nearest).

**The course's own pickup beacons removed:** every pickup node in the dump carries a 9 m cylinder of light (top r .1, bottom r .16) about a metre above the ground (the 'floating' columns, 100-odd of them). The ones on the powerups and pads hidden by the deck were left standing and the molecules have the lights drawn by `beaconAdd`, so all of them are hidden (found by geometry: a cylinder 9 m tall and under 0.8 m wide; the dump's `params` field holds only the names of the parameters, not their values). `&dbgshaft=1` logs the kept light shafts and the number of beams hidden.

**Steering made heavier (all modes):** the head reading is smoothed harder (cutoff .8 Hz + 3.5 x speed of the turn, was 1.1 + 6; backlash band .03, was .012; no velocity feed-forward; swerve gain +8 %, was +20 %; fine-zone slope .7, was .9), the wheel rack turns at most 2.6 -> 1.5 steer-units a second (was 5.2 -> 2.8), the spring is softer (9 .. 7 x 4.2 rad/s, was 12 .. 13 x 4.2) and the heading follows the wheels with a .16 s lag (was .05 s). Head tracking itself is untouched.

**Camera follows the action:** the camera pitches with the slope 18 m + half a second ahead on the ground (down hill looks down, up hill looks up) and with the flight path in the air, smoothed (.45 s on the ground, .3 s in the air), at 0.6 of the angle and at most 17 degrees (`CAMP`). Flat screens aim the view with it; in the headset it is added to the world's reference-space offset (half strength). `&pitch=0` turns it off, `&xrpitch=0` turns the headset share off (a negative value flips its direction). The headset direction is derived, not tested.

### Thirteenth round (pillars off, trees, rails, looks, head axis)
**Pillars of light off:** all beacons (`beaconAdd` returns at once), the light shafts' rays (the molecule in each stays), the landing-target beam. **Trees:** the saw no longer cuts through them (no saw powerups are generated; the bank still holds the other three) and a hit now pushes the board clear of the tree (it stayed inside it and re-hit it when the hurt time ran out: the sticking). **Rails:** gv_trip.js `railStep` ported for the course's 21 rails (`RAILS`, `featX`, `railY`, `railStep`): line up within .9 m (1.5 m near the start) and low to grab, ride its line with a little head freedom, steer away for .3 s to drop off, end with a lift and a slingshot; glass fast, wood slow, rust rough; score by length. Untested in play. **The big pale balls:** the molecules in the light shafts were about 7 m across (2.4 x, then grown); now 1.4 x (the same size as the course's own molecules).
**Looks:** pause menu `look:` normal / vector / ascii / line drawing / pastel / oil painting (also `&look=line|pastel|oil|vector|ascii`), one shader (`psylook`): line = Sobel ink on warm paper with a trace of colour; pastel = soft blur, colour pulled to grey, lifted toward white, chalk grain; oil = Kuwahara (four 3 x 3 patches, calmest one wins). Flat screens and the headset (the headset chain has a look stage after the picture pass; the line / pastel / oil shaders are new, not in the three.js game). **Head axis** (`head:` in the pause menu, `&axis=`): turn (yaw, as before), tilt (head roll, 18 degrees full) or turn + tilt, in the headset; lean is not offered (the headset camera's position includes the rider's, so a lean needs a separate reference). Untested in a headset.

**Selector fix (fourteenth round):** three real bugs. (1) The look pass was created with no camera and no engine, so Babylon's constructor threw and the error was swallowed: no look (vector, ASCII or the new ones) had ever run on a flat screen. (2) The look only attached with the full picture pass (level 3+), which a modest graphics chip never gets: it now runs at any level. (3) The look state was only stepped while the game ran, so choosing a look from the pause menu changed nothing until you resumed: it is stepped every frame now. Also found and fixed: the trail feed formed a WebGL feedback loop (a 'reusable' main pass could be given a texture an earlier stage still read), invalid draws and very slow frames on weaker chips; the main pass is no longer reusable and the trail history is two textures the chain owns.

### Fifteenth round (sound, finish, collisions, singles, perks)
**Sound effects:** gv_trip.js's own `sfxset.js` (synthesised set) and `audiowire.js` (event wiring and music duck / bump) run unchanged; wired to: ramp blast, landing, wipeout, tree / rock hit, shield break, pads, powerup pickups, molecules (course and shaft), rails (on / off / grind pitch), air rings, hoops, landing target, gaze orbs, pylons, finish, pause; toys and boulders get the real `SFX` object; the listener moves with the board. `&nosfx` turns it off. The audio context starts on the first touch, key press or headset entry. **Finish:** chequered arch 150 m before the end of the ground, burst + shake + white fade (1.5 s on a flat screen), +2000, then the lap repeats the same world with everything on the course available again (a world change would need a page load, which ends a headset session; `&journey=1` loads the next biome on a flat screen; `&nofinish` removes it). **Collisions** are the original's `obstacleStep`: the move is swept against trees / rocks / pylons (no tunnelling), a hit pushes out to the edge, keeps 90 % of the speed along the trunk (always still going down the hill), halves the steering; trees can be flown over above 7 m, rocks above 3 m. `crash` is a stumble (hurt .45 s, -50, spills 6 to 12 glowing orbs that hop ahead and settle for 7 s: scoop them back for +10). **Singles:** three lone pylons in the deck's 'warm' rows. **Perks:** pad kick and speed cap scale with the trip's perks (`PSY.perks().padK / speedK`).
**Checked and found not applicable:** the original's molecules come from the course rows (7.5 % of the 252 bank rows hold a pill triple, the same density as the 9 in this course), so there is no separate spawner to port; supercharge (`SUPER`) cannot trigger in the default journey mode (`superAdd` returns at once and the rocket window is disabled in the source), so it is a dev-only path and is not ported; 'chaos' is a menu preset.
**Server:** the LAN servers (8090 plain, 8447 and 443 HTTPS) now listen with a backlog of 256 (the default of 5 refused connections when a page asks for fifty modules at once: a page stuck on loading); restarted.
**Still not ported:** the springs' open-end flight, the filmic tonemap / grade / sharpen / NaN repair, head lean as an axis, hazard zones, the face and god overlays, realm caves, terrain-skirt strata, headset verification of everything.

### Audit against gv_trip.js (sixteenth round)
The director events gv_trip.js calls are exactly these seven, and all are wired in Babylon: onBlast, onBuff, onCrash (tree / rock / snowball), onMolecule, onPad, onRail, onSnowball (dodge / escape / close). The director's other events (onChain, onCheer, onFinish, onGlint, onOrb, onPop) are never called by the game, so there is nothing to wire. gv_trip.js has no hazard zones and does not use the face / god meshes (WFX.face is only passed to realm and vegetation materials the long_s7 course does not contain); realm caves are not in this course; the springs' open-end flight is a limit of toys.js itself, which the three.js game shares. What is left is Babylon-specific (its tone mapping happens in the world shaders, so the original's filmic tonemap / grade / sharpen are not added on top) and verification on a headset.

**More looks (pause menu `look:` or `&look=`):** cel cartoon (`cel`: four flat bands of light, colour pushed, thick black ink), doodle (`doodle`: crude wobbly ink and scribbled hatching on paper with a crayon smear), felt craft (`felt`: soft blurred shapes, wool fuzz, a dashed running stitch where pieces meet), and four extras: halftone comic (`halftone`), kaleidoscope (`kaleido`, six mirrored wedges, slowly turning), thermal (`thermal`) and mosaic (`mosaic`). Same shader as the other looks, so flat screens and the headset chain.

**Three more looks:** stained glass (`glass`: drifting Voronoi panes in the picture's colour, lit from within, black lead), liquid melt (`melt`: the picture flows and drips downward, colour channels sliding apart), neon edges (`neon`: the world dimmed to shadow, every edge drawn in glowing colour that cycles with brightness and time). Thirteen looks in all besides normal.

**Looks on molecules:** picking up a molecule gives about 1.15 s of two or three looks stacked (a shuffled bag of all fifteen, each at a random strength, staggered by .12 s; three look layers = three passes over each other on a flat screen, two in the headset); the surfaces' psychedelic pulse still runs beside it. Needs at least 1.2 s between bursts. `&testburst=1` fires one every 2.5 s for testing. The kaleidoscope now folds only the edges of the picture (the middle stays the game).

**Seven more looks and flashbacks:** ripple (rings of waves from the middle), twirl (wound round the middle, breathing), plasma (interfering colour fields pour over the picture), moire (two drifting line gratings), hue cycle (every colour turning round the wheel, in flat steps), zoom blur (streaks out from the middle, centre sharp), prism (colour channels split along pulsing rings): 22 looks in all besides normal, in the pause menu or `&look=ripple|twirl|plasma|moire|hue|zoom|prism`. After the main look of a molecule fades, one (50 %), two (30 %) or three (20 %) fainter, shorter echoes of some of the same looks follow, each weaker than the last (about .42, .21, .14 of the strength, .8 s, .65 s, .5 s long, 1.15 s apart): a hint of a flashback. A look burst is a list of timed events (`LOOK.evs`) assigned to the three layers, so a new pickup can overlap the echoes of the last.

**Looks trimmed:** plasma, twirl and ripple are gone (19 looks besides normal). Stacked looks are toned down: with three at once each is at 62 % of its strength (80 % with two), and the paper-like looks (line, pastel, doodle, halftone) are capped at half strength in a burst so stacking no longer washes to white; echoes are scaled from the main strength.

## Lingering looks
LOOKLINGER (oil, cel, kaleidoscope, thermal, melt, moire, hue cycle, zoom blur, prism) keep the game visible, so after a molecule they run ~2.9 s via lingerEnv: quick rise, slow decay, two minor waves dipping to half strength, then gone. Other looks keep the 1.15 s pulse. Flashback echoes come only from the short looks. Flat-screen tested with &testburst=1; headset untested.
