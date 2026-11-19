# Wide path: from "pick one of three" to "choose your line across the whole slope"

## What exists today

**Godot (RunRig.gd).**
- The slope is 116 m wide (`W_HALF` 58).
- Almost everything happens in a 3-lane band around the trail: `FEAT_OFF` = 15 m, pads at `trail_x ± 7`, ramps 14–19 m off-centre.
- Choices come in pairs or threes between poles. The eyes are read as left / middle / right (`_zoned()`, `_sector()`, `SECTOR_M` = 2 m).
- A choice latches after `AIM_LINGER` = 0.14 s (halved for the pickup kind the chain expects). `_update_buff_aim` then sets `_buff_w` (building at 4/s) and `_buff_want = clamp((tx − (x + 0.45·vx)) / 12, ±0.9)`.
- `_guard_path` adds `_buff_w · _buff_want · (1 − 0.6·|s_in|)` to steering.
- Pickups are only offered from about 130 m out.
- `ZONES` set per-stretch character: `path_buff` (how much loot), `singles` (lone obstacles), `walls`, and a multiplier `m`.

**gv.js (now).**
- Candidates: every pickup, pad, rail and ramp within 260 m ahead and ±48 m across.
- A head nudge toward one, or lining one up dead ahead, locks it with a green reticle.
- The Godot pull applies, scaled by distance, and there is a forward tug over the last 28 m plus a sling on pickup.
- The level data is still Godot's lane layout, so most candidates sit within ±20 m of the middle. The wide corridor is empty space.

## 1. Corridor and layout

**Width.** Keep the playable slope at about 116 m (±58) but treat it as three bands:
- core (|x| < 14), where the trail is
- shoulders (14–34)
- flanks (34–54, banks start rising at 58)

Obstacles thin out toward the flanks and loot gets richer, so going wide is a decision with a payoff.

**Targets come in four shapes** (replacing pair/triple choices):
1. **Clusters:** 3–6 pickups of one kind in a 10 m patch. Take the cluster for a chain, miss it and you lose little.
2. **Leading chains:** orbs that curve sideways (as the loot line already does) for 120–200 m and end in a treat on a shoulder or flank. Following the first orbs is the commitment.
3. **Risk/reward lines:** a rail or ramp on a flank with a tree band between it and the core. The reward is 2–3× a core pickup, and the cost is a swerve through a gap.
4. **Decoys:** one expensive-looking item sitting in a rock patch.

Place these on a **sparse grid of cells** (about 60 m long × 3 bands wide), not between poles. A cell holds at most one shape, and cells within 180 m of each other get different bands so there is always something to the left and something to the right.

## 2. Showing and tracking far targets

Three reticle tiers, all green and drawn the same way as the existing reticle:
- **Far (130–260 m):** a small dim diamond projected on the horizon, size inversely proportional to distance, with kind-coloured fill (boost orange, shield cyan, mult magenta, ramp white).
- **Mid (50–130 m):** a bracket that grows. Candidates in your steering direction brighten slightly; that is the preview of the lock.
- **Near (< 50 m):** the existing locked ring. It pulses faster as you close in.

**Off-screen bearing markers.** Targets beyond the screen edge get a chevron on that edge at their height, with distance in tens of metres. This is what lets you see "a rail to the far right in 200 m" before it is on screen.

**Radar strip.** A thin top-of-screen strip, 260 m of lookahead, shows every candidate as a dot on a horizontal axis from −58 to +58. The player's x is a tick, the locked target a bright dot, and the best chain target a ring. It costs almost nothing and makes planning possible.

Show at most about 8 markers: nearest first, then highest value.

## 3. Committing

- **Nudge to lock:** a head nudge (|s| > 0.08, after the 1.5 power curve) toward a candidate selects the one on that side with the lowest `|dx| + 0.06·dz`. Dead ahead within 3 m also locks. Lock takes `AIM_LINGER` = 0.14 s of steady nudge.
- **Hold to keep:** the lock stays while the target is ahead and you are not nudging hard the other way (|s| > 0.5 opposite releases it).
- **Re-lock chaining:** after a pickup, the next candidate in the same chain locks at once (half linger), which keeps the flow.

**Pull by distance.** (`kd` = 1.25 − dz/260, clamped to 0.35–1.0.)

| Distance | Pull | Feel |
|---|---|---|
| 260–130 m | `kd` 0.35–0.7, `w` builds at 4/s | a gentle lean, you can ignore it |
| 130–50 m | 0.7–1.0 | clearly carried toward it |
| 50–28 m | full | aim lines up |
| < 28 m | full + forward tug `10·SPK·dt·w·(1 − d/28)` | the slingshot |
| take | boost or kick: boost +6 m/s·SPK, others +3 m/s·SPK, rails the sling | satisfying snap |

Far locks never override an obstacle: the tree swerve rule stays above the pull (obstacles first, then pull). The pull only works while grounded.

## 4. Progression through a run

- **Distance 0–600 m:** cluster-only, all in the core and near shoulders. Teaches nudge-to-lock.
- **600–1500 m:** leading chains appear, flanks open up, the radar strip fades in.
- **1500 m on:** risk/reward lines and decoys, plus branching.
- **Branching lines:** two chains start at the same cell and diverge (left chain through rails, right through ramps). Take one and the other disappears behind you. The pickups are worth more the longer you stay on a branch (chain multiplier).
- **Chain multiplier:** each consecutive pickup within 4 seconds raises the multiplier, up to ×8. A missed pickup resets it. The existing `_chain_expect_kind` halves the lock time for the next expected kind.
- **Speed and width scale together:** as the speed ceiling builds, cells get longer (60 → 90 m) so the reaction window stays about 1.5 s, and the flank bands get richer.

## 5. Changes to the Godot dump and generator

The dump already gives `rows[].buffs/pads/feats/obs`, `vx` ramps, `trailx`, and `anims`. To build a bigger level:
1. Add `cells[]` per row: `{band, z0, z1, shape, ids[]}` so the viewer knows what each target belongs to.
2. Add `chain` ids on buffs and orbs: `{chain, idx, next}` for leading chains and branches.
3. Add `value` and `risk` to every target (for markers and the radar colouring).
4. Add `corridor` to the dump: per-row `{band_obstacle_density[3], bank_start}`.
5. In the generator (`_gen_segment`, `_place_kicker`, `_spawn_buff`, `_boost_row`): replace `choices_built` lanes with the cell grid, offset pickups by band instead of `sd · FEAT_OFF`, lift `FEAT_OFF` to a per-target `off` (0–50 m), and thin `obs` by band.
6. Dump at least 3 seeds × 20 segments, plus the cell metadata, so we can validate a JS generator against it.

## 6. Parameters to expose (`?` flags and a tuning panel)

`lockRange` (260), `lockLatMax` (48), `linger` (0.14 s), `nudgeCurve` (1.5), `pullFar` / `pullNear` (0.35 / 1.0), `pullRate` (4/s), `tugDist` (28 m), `tugGain` (10·SPK), `releaseNudge` (0.5), `cellLen` (60 → 90), `bandWeights` (core / shoulder / flank loot and obstacle density), `chainWindow` (4 s), `chainMax` (8), `markerCap` (8), `radar` (on / off).
