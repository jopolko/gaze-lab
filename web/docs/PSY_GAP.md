# What of Godot-dev's psychedelic experience is still missing from the three.js version

Sources: `godot/scripts/RunRig.gd` (R), `DownhillRig.gd` (D), `DhJourney.gd`, `DhPacer.gd`, `DhDirector.gd`, `DhProgress.gd`, `Themes.gd`.
Our side: `web/downhill-three/gv.js`, `spawn.js`, `toys.js`, `music.js`, `main.js`, `molecules.js`.
Effort: S under half a day, M about a day, L multi-day. Fun: priority for the player (5 = highest).

## 0. Where three.js stands today

- Done: the terrain, the dumped objects, the picture pass (psychedelic branch), physics, rails, ramps, vortex, pads, toys, the six molecules as objects, chains and a generated wide level.
- **Frozen at one look.** The picture pass runs at a fixed `trip` (default 0.8) with `mA/mB/dmt/buzz/sharp` at static values (`gv.js` ~204-220). The ground, trees and sky are at full psychedelic strength from frame 1. In Godot the look is *earned*.
- **Silent.** `gv.js` has no music (`music.js` exists but is not wired in), and its sfx are a few synthesized blips.
- **No dose model.** Collecting a molecule gives points and a chain link. It changes nothing in the picture, the sound or the play.
- Not ported at all: snowball, journey (waves), pacer, XP/unlocks, goals, flow multiplier (we have a simpler chain), astral echoes, carve trail, clarity moments, sharpen snaps, screen shake and fov punch.

## 1. The trip system: dose, felt, perks (the heart of it)

| Item | Source | Exact values | What it does | Port |
|---|---|---|---|---|
| Eating a molecule | R:9794 `_pill_eat` | first of a kind: `_mdose[mi]=6.0`, `_mol_got=true`; repeat: `+2.0` (cap 6). `_mflash[mi]=1.0`; `_sharpen(0.7)`; `_trip_add(0.25)`; `_flow_up(1)`; `_shake>=0.12`; points `120*groove*pill_n*(3 if first)`; "TRIPPING" cheer when 3 in a row (`_pill_gap`=6 s) | the pickup is also the trigger of everything below | S |
| Dose to felt | R:9896 `_pill_tick` | `_mdose` wears off at 0.008/s (DOM, index 1, 0.004/s) times `wear`; `wear = 1 + 12*max(avg - pacer.target - 0.05, 0)`. `_mbody` chases `_mdose` with time constant **25 s up, 8 s down** (`1-exp(-dt/rate)`) | what is *felt* lags what is taken by about 25 s, so the waves come later | S |
| Overall level | R:9844, 9849 | `_mol_avg = sum(_mbody)/36`. `_mol_dmt = smoothstep(0.52, 0.75, min(_mbody)/6)` (all six near the top) | drives the music, post `dmt`, "ALL SIX" cheer (+kaboom) at dmt>0.5, off below 0.3 | S |
| Trip scalar | R:1498, 1504 `_trip_add/_trip_tick` | decays `-(0.018+0.02*trip)/s`; floor = journey `trip_floor()`, and `pow(mol_avg,1.8)*0.8*stage_post`; tiers at 0.25/0.55/0.85 give cheers "things get colourful...", "WHOA", "FULL TRIP!!" (+`100*tier*groove` points). Writes post `trip` and `breathe = amount*(1+trip*6)` | the single dial the picture reads | S |
| `_cheer` adds trip | R:3959 | `+0.04*size` per cheer, `flash>=0.25*size`, `fov_punch>=6*size`, `_psy_pulse`, confetti `50*size`, ring, burst | every good moment nudges the trip | S |
| Perks (felt, 0..1 = `_mbody/6`) | R:8432-8436, 4443, 12308 | mescaline glints x(1+0.6p); **DOM points x(1+0.8p)**; 2C-B boost pads x(1+0.5p); 2C-E ramps x(1+0.35p); 2C-T-2 slingshots x(1+0.6p); 2C-T-7 speed x(1+0.12p, cap 1.9). All six: points x(1+2*dmt) | what each molecule does to play; names GLINTS, POINTS, BOOST, RAMPS, SLING, SPEED | S-M (three needs `_bm_*` hooks in `gv.js`/`toys.js`) |
| Hits cost a level | R:9875 `_mol_hurt` | a hit dims `_mbody[i]` by 2.0 (the hazard's own molecule, or a random held one); never loses the "found" mark | a setback in the trip, not the collection | S |
| Molecule gift / spawn bias | R:9215 `_mol_gift`, 9647 | `MOL_GAP_M=250` m between molecule rows; a not-yet-found one has weight 4.0 else 0.2-0.7; pacer `spawn_bias = clamp(1 + 2.6*(target - avg), 0.15, 3)` | keeps every player on about the same arc | M |
| Time drift | R:9950s | `_drift_t=110`, then `_dose += 0.7` every 100 s | a run with no pills still comes on late | S |

**Fun 5.** Port the dose/felt model first: it is about 60 lines, and it is what turns pickups into a *journey*.

## 2. What each molecule does to the picture (per-piece reveal)

R:7090-7110 (`_lv`, `_pk`), R:9917-9935 (post feed).
- `_lv[i] = max(_mbody[i]/6, fx_level)`. `_pk(i) = clamp((smoothstep(0.04, 0.45, _lv[i]) + _mflash[i]*0.7) * _clr_k, 0, 1.3)`.
- Pieces: **0 mescaline = ground** (light waves `gglow`, shapes in the snow); **1 DOM = sky** (bands, polar field); **2 2C-B = colour** (moire colour, colour on trees); **3 2C-E = mountains** (moire skin, breathing); **4 2C-T-2 = ripples** (flowing grid, bullseye, third grid); **5 2C-T-7 = pulse** (trees breathe and sway, sky tunnel).
- Post parameters: `mA = (b0,b1,b2)/6` and `mB = (b3,b4,b5)/6`, each `pow(x,1.15) * wk`, with `wk = (0.7+0.6*director.wave) * stage_post`; floor `fx_level`; plus `_mflash[i]*0.9` (a molecule's own effect surges for about 1 s, decay 0.9/s, R:7017); times `_clr_k`. `dmt` times `_clr_k`.
- `stage_post = smoothstep(0.22, 0.5, h)` with `h = max(mol_avg, x_level)`: **the full-screen look is the last piece to arrive** (R:7113 `_stage_tick`; ground `grid = smoothstep(0.08, 0.34, h)`).
- Ours: all pieces at full strength from the start, `mA/mB` fixed. Port: M. Fun 5.

Picture-pass knobs not wired in `gv.js` (`web/data/post_psy.gdshader`, driven R:9344 `_buzz_tick`): `tube` (rays while in a spring tube: `1.0` tube, `0.5` chain rail; lerp up rate 7/s, down 2/s), `smear` (boost streak: `0.6*p_smear`; up 9/s, down 3/s), `rewind` (crash tear: `hurt_t/1.1`), `k_edge/k_cel/k_fold/k_rings/k_dmtr` (off by default except `k_chroma=1`, `k_trace=1`, `k_punch=1`, `k_warp=1`, `k_pulse=1`, `k_wash=0`). Defaults from `FX_KNOBS` (R:6152): p_glow 0.35, p_bloom 0.4, **p_haze 0.55** (fog thickness), s_polar 0.45, s_tunnel 0.6, t_breathe 0.6, w_bend 0. Port: S each.

## 3. Pulses, sharpening, buzz, clarity, apex

| Item | Source | Values | Port |
|---|---|---|---|
| Buzz | R:9344 | `wave = 0.5+0.5*sin(t*0.55)*(0.6+0.4*sin(t*0.17+1))` (swells of about 10 s); `buzz = wave*(0.35+0.65*deep)`, `deep = clamp(max(mol_avg,fx_level)/3,0,1)`. Feeds post `buzz` and bloom `+(0.3*buzz+1.0*sharp)*p_bloom` | S |
| Sharpen snaps | R:9252, 9344 | `_sharp` snaps to 1 and decays **0.42/s** (about 2.4 s); auto every `rand(26,48)` s scaled by `0.7+0.8*deep`; also on molecule eat (0.7) and clarity return | S |
| Clarity moments | R:6969 | when `deep>0.45`: every `rand(50,110)` s: `clr_k` 1 to 0.10 over 0.35 s, hold to 1.7 s, up to **1.30** by 2.4 s (with a sharpen), settle to 1.0 by 5.0 s. Scales mA/mB/dmt | S |
| Pill glimmer | R:9955 | `_flick=1` then falls 2/s; `pill_k = 0.5*pow(max(sin((1-flick)*TAU*1.5),0),1.4)*(0.12+0.88*stage_post)`; sky flash when flick>0.9 | S |
| Jump apex swell | R:9958 | at the top of a flight (alt>7, no face challenge): 1.9 s swell `apex_amp = 0.28+0.3*clamp(avg*1.5,0,1)`, four rings and a burst, `fov_punch>=5`, `cue_good` | S, Fun 4 |
| `_psy_pulse` | R:10883, 10912 | two-event queue (kind, colour) with ages; kinds: 1 glint, 2 big cheer, 3 landing (0.5,1,0.9), 4 crash red, 5 small cheer. Shader params `pa, pk, c0, c1`; plus `rush`, `grind`, `air`, `speed` lerped at 3/5/3/2 per second | M (a second full-screen shader: rings from the pulses) |
| Astral echoes | R:9258-9335 | 4 additive spheres (r 0.55, scale (0.8,1.5,0.8)*(1-0.14i)) at position history every **0.12 s** at `(i+1)*3` steps back; alpha `0.30*on*(1-i/4)`; hue `age*0.15+0.13i`; on when `mol_avg>0.08` or boosting (lerp 2.5/s) | S |
| Carve trail | R:9322 | 28 dots dropped every 0.05 s when `|vel.x|>7` and on; hue `age*0.3+0.045i`, fades over **1.4 s** | S |

## 4. Camera feel

D:1394-1402, R:10330-10442. Each frame: `shake -= 1.6/s`; `h_offset, v_offset = rand(-1,1)*shake*0.3`; `fov_punch -= 24/s`; `fov = clamp(80 + (speed-18)*0.6, 78, 108) + fov_punch` (R:10442, third person; first person 62-74 base).
Triggers: cheer `6*size`; pad `7`; ramp blast `12` (+shake 1.4, flash 0.35); charged pop `4+5*charge`; rail slingshot `4+6*sling`; rail off `3`; flow combo `2.5`; apex `5`; crash `shake 0.8`; snowball closeness `shake >= 0.35*close^2`. Ours: none (a fixed fov). Port **S**, Fun 5 (the cheapest "feel" gain).

## 5. Flow, chain, groove (our chain is a different rule)

- **FLOW** R:4265-4300: `FLOW_WINDOW=5.0 s` at level 0, `FLOW_WINDOW_MIN=2.6 s` at the top (`lerp` by `chain/8`); a touch refills it; when it hits 0, drop a level and the next drop waits `FLOW_DRAIN_STEP=0.7 s`. `FLOW_MAX=8` (banked up to 24). `groove = 1 + 0.25*min(chain,8)`. "COMBO x%d!" cheer each 3 levels.
- **Chain of kinds** R:4189-4215: order `mult -> boost -> ramp -> air`, `CHAIN_WINDOW=9.0 s`, level cap 4, multiplier `1+0.25*chain_lvl` on score; the next-in-chain arch turns gold and pulses.
- **Score** R:4443: `pts * (2 if sugar) * chain_k * (1+0.8*DOM) * (1+2*dmt)`.
- Ours (`chainHit`): a single counter with window `3.2+0.25c` s and a simple kick. Not Godot's. Port: S-M, Fun 4. Gives "keep it alive" tension.

## 6. Journey director (waves, worlds, difficulty)

`DhJourney.gd` (303 lines). Order of worlds `psychedelic, candy, tunnel, synthwave, matrix, psychedelic, desert, egypt`.
ARC (`calm / on / peak / off` seconds, strength): psy 40/16/10/10 s 0.36; candy 30/18/22/10 0.48; tunnel 26/20/30/10 0.60; synthwave 22/18/38/10 0.72; matrix 18/20/34/12 0.84; psy 16/22/**55**/16 1.00; desert 22/18/30/14 0.60; egypt 45/24/40/20 0.40. Each round is x1.08 stronger.
- A wave starts when `_body >= THR[wave]` (2.6, 3.8, 5.0, 6.2, 7.6, 9.6, 4.5, 1.5) times the level (0.75/1.0/1.3); an echo wave re-runs the last one at x0.85 if nothing comes by `2*calm+25 s`.
- Stage windows of onset: sky 0-0.30, ground 0.30-0.55, veg 0.55-0.80, light 0.80-1.0 (offset reverses).
- `trip_floor = onset_k^1.5 * (0.2+0.45*clamp((strength-0.3)/0.9,0,1)) * (0.7+0.3*excitement)`.
- Biome mods (speed, hazards, pads, jumps, glints, bump, spring, pad kick, grip, music) per world in `BIOME`, e.g. tunnel spd 1.28 pads 1.6; psychedelic glint 1.7 jumps 1.2 grip 0.9.
- Not ported; our wide level has one fixed look. Port: L (the other worlds' shaders and sets), but the **calm/onset/peak/off schedule on the psychedelic world alone is M**. Fun 4.

## 7. Pacer (session shape)

`DhPacer.gd`: phases settle 0-0.07 (target 0 -> 0.12, hazard x0.35), come up 0.07-0.30 (0.12 -> 0.75, x0.75), peak 0.30-0.52 (0.75 -> 1.0, x1.2), plateau 0.52-0.70 (1.0 -> 0.65, x1.0), comedown 0.70-1.0 (0.65 -> 0, x0.45); default session 600 s; `CALM_START_S=20` (no hazards the first 20 s); each cycle x(1+0.04c). Drives `wear`, molecule spawn bias and `hazard_k`. Port: S, Fun 3 (needed for the comedown).

## 8. Music (we have `music.js` but nothing connects it in `gv.js`)

`DhDirector.gd`: pre-trip tracks by speed band; **from the first molecule the 9 Alien Warfare stems play locked** (128 BPM, bar = 1.875 s). Stem volume targets (R `lv` in `update`):
ambience 1.0; pulse `holds[0]` (mescaline); bass and drums `max(holds[5], avg*1.3)`; piano `holds[1]` (DOM); guitar `holds[4]`; synth `holds[2]`; acid `holds[3]`; fx `dmt`. (`holds[i] = _mbody[i]/6`; `main.js` has `STEM_OF = ['piano','synth','guitar','acid','fx','pulse']` for a different mapping, so reconcile.) Parts only change **on every second bar line**; per-stem dB `lerp(-24, 0, pow(v,0.7))` (silent below 0.02); smoothing `d*1.6`; crossfade `FADE_S=5 s`. `_deep` on at avg>=0.2, off below 0.11 (funk returns); comedown track when avg falls below `peak*0.4`; `exc` (excitement) picks the pre-trip band. `exc = lerp(goal)` with time constant 1.5 s, `goal = 0.45*speed + 0.25*flow/12 + 0.15*boost + 0.15*links/8` (R:8398). Intensity for the synth music: `0.3+0.42*sp+0.2*grade+0.25*trip+0.2*exc+...`. Port: M (the stem engine exists), Fun 5.

## 9. SFX (Game.sfx names fired in R/D)

`coin`(cheers, glints every 3rd) 13, `boom` 8, `whoosh` 6, `kaboom` 4 (ALL SIX), `boing` 4, `snap` 3, `hurt` 3, `honk` 3, `stretch` 2 (vortex catch), `squeak` 2, `rail_on` 2, `pad_boost` 2, `loot` 2, `cue_good` 2, `crowd` 2, `buff_mult/boost/shield`, `boing2`, `bell` (face prompt), `zap`, `thwack`, `splat`, `rumble` (snowball), `pop`, `levelup`, `launch`, `land`, `gong`, `cue_bad`, `blip`; plus per-molecule notes `mol0..mol5` and the glint ladder `lad0..lad9` (one pentatonic step per glint in a run, R:9340 `_cue(2, step)`). Ours: ~12 synthesized sounds, none of `mol0..5`, `lad*`, `rumble`, `crowd`, `levelup`, `bell`. Port: S (use the stems' key for notes). Fun 4.

## 10. Snowball

R:1375-1440. Starts when `dist >= _sb_next` (first 700 m) and grounded and stage grade > 1.1 and not within 450 m of the end; spawns **75 m behind**, radius 3.0, speed `31 + 7*prog` (prog = dist/4200); follows your x with `1.1/s` smoothing; `close = clamp(1-(gap-14)/80,0,1)` drives `shake>=0.35*close^2`; hits at `gap<3.8` and `|dx|<3.9` and alt<3.5 (a crash costing a held molecule); escaped when `gap>150`: `+500*groove`, flow up, trip +0.1, cue. Next at `dist + rand(650,1100)`. Tinted by a held molecule's colour. Cheer "SNOWBALL!  RUN!" + `rumble`. Port: M, Fun 5 (pressure gives the lateral dashes a reason).

## 11. Goals and XP

Goals R:673: pool `shave 5 poles, rail 3, jump 4, treat 6, orb 24, flow x6.0`; three per run, each pays and all three pay a lot (R:713). XP: R:1478 every 2 s `score -> xp*0.1`; `LEVEL_XP = [0,300,800,1600,2800,4500,7000,10000,14000]`; unlocks `DhProgress.gd` (themes and toys). Port: S-M, Fun 3 (needs persistence).

## 12. Image quality: why Godot-dev looks nicer

Godot environment (psychedelic, `Themes.gd:30`): sun (1,0.7,1) energy 0.7 with shadows to 80 m; fog density `0.001 * p_haze(0.55)` colour (0.35,0.05,0.45); ambient from the SKY (energy 0.9); **glow** intensity 0.127 bloom 0.05 (and `p_glow 0.35`, swelling with buzz and sharp); Filmic tonemap exposure 1.05; saturation 1.15, contrast 1.1.
Three today (`gv.js:15-16, 180-188`): `antialias:false`, pixel ratio capped 1.5, **Cineon** tonemap, a hemisphere light standing in for sky ambient, **no shadows**, **no glow pass**, fog at the full 0.001 (should be x0.55).
Concrete fixes, all small: (1) fog density x0.55; (2) swap Cineon for a Filmic curve in the post `cineon()` function; (3) a real bloom: downsample the bright part of `rtScene` to the half-res buffers already allocated and add it with intensity `0.127*0.35*(1+0.3*buzz+sharp*...)`; (4) a shadow-casting sun with a 80 m shadow box following the board; (5) sky-sampled ambient (a hemisphere light tinted from the sky colours near the horizon vs zenith); (6) MSAA via `renderer.antialias` on the scene target (WebGL2 `samples:4`) if the phone holds 60 fps; (7) screen-edge vignette already in the post. S-M each, Fun 4 (this is the "looks as good" gap).

## 13. Ranked: what to port next

1. **Dose/felt model + `mA/mB/dmt` driven by it** (section 1-2). It turns collecting into a trip. M.
2. **Per-molecule piece reveal** (`_pk`: ground, sky, colour, mountains, ripples, pulse each arrive with their own molecule, post last at `smoothstep(0.22,0.5,avg)`). M.
3. **Camera feel**: fov punch (decay 24/s, triggers listed), shake (decay 1.6/s), flash. S.
4. **Music wired to the dose**: stems by `holds[]`, parts on every second bar, 5 s crossfade, `exc` intensity. M.
5. **Image quality**: fog x0.55, Filmic curve, real bloom, sun shadows, sky ambient. S-M.
6. **Snowball** with the exact numbers above. M.
7. **Buzz, sharpen snaps (every 26-48 s), clarity moments, apex swell, pill glimmer** (section 3). S together.
8. **Flow and groove with Godot's timings** (5.0 to 2.6 s window, 0.7 s drain, groove 1+0.25*min(chain,8)) replacing our chain counter. S-M.
9. **Perks**: DOM points, 2C-B pads, 2C-E ramps (needs more ramps), 2C-T-2 sling, 2C-T-7 speed, mescaline glints. S each.
10. **Astral echoes + carve trail + SFX set (mol0..5, ladder, rumble)**. S.

## Timings that matter most (cheat sheet)

felt follows dose **25 s up / 8 s down**; dose wears **0.008/s** (DOM 0.004); trip decays **0.018+0.02*trip /s**; molecule flash **~1 s** (0.9/s); sharpen **2.4 s** decay, auto every **26-48 s**; buzz swell **~10 s**; clarity every **50-110 s**, 5 s long; flow window **5.0 -> 2.6 s**, drain **0.7 s/level**; chain window **9 s**; fov punch decay **24/s**; shake **1.6/s**; music parts change on **even bar lines (3.75 s)**, crossfade **5 s**; snowball **75 m behind, 31-38 m/s**, next in **650-1100 m**; pacer session **600 s**, first **20 s** hazard-free; calm between waves **16-45 s**, onset **16-24 s**, peak **10-55 s**.
