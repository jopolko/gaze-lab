# PHYSICS_PATCH — make gv.js movement/interaction match Godot's RunRig

Source of truth: `godot/scripts/RunRig.gd` (`_physics_process` 5398-5580, `_collide` 5589, `_crash` 5682, chain/flow/pop 4189-4450, rails 1849-2013, vortex/ramps/pads 7917-8150, tricks 11265-11440), `DownhillRig.gd` `_land` 966 / `_crash` 1002.
Target: `web/downhill-three/gv.js` (anchors below are exact text/function names; line numbers as of this writing).
Not applied — gv.js is owned by the parent. Apply top-to-bottom; each block is independent unless noted.

## 1. Audit

### (a) Real omissions (Godot does it, three.js doesn't)
| # | Godot | gv.js | Fix |
|---|---|---|---|
|A1| fixed 60 Hz `_physics_process` | one step per display frame, `dt=min(.05,…)` (765) | §2 |
|A2| flow/groove chain + 4-step chain (mult→boost→ramp→air), `chain_lvl/chain_step` (4189+) | one invented `chainHit/chainTick` (483-502) | §3 — route through `PSY.events.*` |
|A3| `_crash` → glint spill, chain/groove reset (`onCrash`), speed rule, landing clamp 15 | `crash()` 503: `hits++, hurt=.45` only | §4 |
|A4| pops (brow edge, POP_VY 6.2, cooldown 1.0), tuck, ramp charge, flip/grab/slam trick scoring | none; headStep has horizontal only (367) | §7 |
|A5| rail pop-off / glint rush / groove in score | `railStep` 562-573 | §5 |
|A6| update order: rail/feat → collide → collect → pads → toys → pill → ramps → vortex → glints → chain → balls → tricks | playStep 692+ differs | §2 order list |
|A7| air rings, glints, spill (4001-4110) | missing | §6 |
|A8| rough landing ×.92 (impact≥7), ×.9 (impact>9, short flight) | `PH.mom=2.6` flat | §4 |
|A9| `PSY.events` return values (boostT/kickMps/multT/vyAdd/sling) | ignored; local constants | §3/5 |

### (b) Deliberate user deviations — KEEP
- Air steering to aim landing (`lat = 22*max(1,SPK)`, cap 26, drag .25) — user request.
- Landing = boost (`PH.mom`), nothing stops the player dead (bounce/correct away from trees) — user request.
- Quick shudder only (`SHUD`), no continuous shake — user request.
- Grippy turn `STK=3`, path width 1.1–1.28× Godot, head-tracking input (no eye tracking), gravity-well/lock-on pull (`wellSteer`) — user request.
- First-person camera as RunRig `_place_camera`.

### (c) Bugs (invented numbers)
- C1 `* SPK * .6` on slingshot (gv.js 562): Godot applies full `(3+13*sl)*SPK`. Remove `.6`.
- C2 rail pull `* dt * 2` (573): Godot is `* dt`. Remove `*2` (the 2 only compensates nothing).
- C3 `if (impact > 18 * SPK) crash('WIPEOUT!')`: Godot clamps impact to 15 before `_land` (>16 never fires), so WIPEOUT never happens. Delete the WIPEOUT branch (keeps "nothing stops dead").
- C4 `PH.air_t > 2.4` extra gravity (747) and `- .03*hypot(vx,vz)` crest glue: not in Godot; they alter airtime so jumps/rings don't line up. Remove (keep air-steer).
- C5 variable dt: linear Euler terms (`vy -= g*dt`, `x += …*dt`) integrate differently at 30 vs 60 fps → §2.

## 2. Fixed 60 Hz step (replace in `frame()`)

Anchor: `const dt = Math.min(0.05, (now - last) / 1000); last = now; clock.t += dt;`
```js
const STEP = 1 / 60; let acc = 0;               // module scope, near `let last`
// inside frame(now):
const raw = Math.min(0.1, (now - last) / 1000); last = now; clock.t += raw;
acc += raw; let n = 0;
while (acc >= STEP && n < 5) {                  // max 5 substeps (spiral-of-death guard)
  PH.px = PH.x; PH.py = PH.y; PH.pz = PH.z;     // previous state for interpolation
  playStep(STEP); acc -= STEP; n++;
}
if (n === 5) acc = 0;
const alpha = acc / STEP;                       // render pos = lerp(prev, cur, alpha)
const rx = PH.px + (PH.x - PH.px) * alpha, ry = PH.py + (PH.y - PH.py) * alpha, rz = PH.pz + (PH.z - PH.pz) * alpha;
// camera/board mesh use rx,ry,rz; per-frame visual work (camera lerps, fx, shudder decay) keeps using `raw`.
```
Rules: everything in `playStep` uses the constant `dt = STEP`. Camera/FX smoothing stays `exp(-k*raw)`. `rowsUpdate/pumpBuild` stay per frame (move out of playStep into frame()).

Order inside `playStep` (Godot): headStep → movement/integrate → rail/feat → obstacleStep(collide) → collectStep(buffs) → pads → toys → pill → ramps → vortexStep → glints → chain/flow → balls(snowball) → tricks → lap check.

## 3. Chain / flow via PSY.events (replace invented chain)

Anchor: `function chainHit() {` … `function chainTick(dt) {` … (483-502). Replace both with:
```js
function chainHit(kind) {                       // kind: 'blast'|'pad'|'rail'|'buff'|'trick'
  const ev = kind === 'pad' ? PSY.events.onPad(PH) : kind === 'rail' ? PSY.events.onRail(PH)
           : kind === 'blast' ? PSY.events.onBlast(PH) : PSY.events.onBuff(PH, kind);
  if (!ev) return;
  if (ev.boostT) PH.boost_t = Math.max(PH.boost_t, ev.boostT);
  if (ev.kickMps) { const sp = Math.hypot(PH.vx, PH.vz) || 1; PH.vz -= ev.kickMps * SPK * (-PH.vz / sp); }
  if (ev.multT) PH.mult_t = Math.max(PH.mult_t || 0, ev.multT);
  if (ev.vyAdd) PH.vy += ev.vyAdd * SPK;
  if (ev.sling) PH.vz -= ev.sling * SPK;
}
function chainTick(dt) { PSY.flow && PSY.flow.tick && PSY.flow.tick(dt, PH); }   // groove decay lives in psyfx
```
(Check psyfx.js 296-345 for exact return shapes before wiring; call sites below pass the kind.)
Existing `chainHit();` calls: in `vortexStep` lip block → `chainHit('blast')`; pad branch (`p.used = true; hideTarget(p); PH.pads++;`) → `chainHit('pad')`; rail `off()` → `chainHit('rail')`; `takeBuff` end → `chainHit(b.kind)`.

## 4. Crash / landing

Anchor `function crash(msg, kind) {`: after the shield branch, replace `PH.hits++; PH.hurt = .45;` block start with:
```js
try { PSY.events.onCrash(PH); } catch (e) {}     // resets chain/groove
spillGlints(Math.min(PH.glints || 0, 12));      // §6
PH.hits++; PH.hurt = .45;
// keep: bounce-off / no dead stop (user rule); never reduce speed below 60% of pre-crash
```
Landing (anchor `if (impact > 18 * SPK) crash('WIPEOUT!', 'tree'); else if (impact > 12 * SPK) {`):
```js
impact = Math.min(impact, 15 * SPK);             // Godot RunRig clamp before _land
if (impact >= 7 * SPK) { PH.vx *= .92; PH.vz *= .92; if (PH.air_t < 1 && impact > 9 * SPK) { PH.vx *= .9/.92; PH.vz *= .9/.92; } }
// remove the WIPEOUT branch entirely; keep the user's landing boost: PH.mom = 2.6 only when impact < 7*SPK (clean land)
```

## 5. Rails

- `railStep` slingshot (562): `PH.vz -= (3 + 13 * sl) * SPK;` (drop `* .6`).
- Pull (573): `... * dt);` (drop `* 2`).
- `off()` 'end' branch: keep `PH.vy += 3.2` but add `chainHit('rail')` and a glint rush: `spawnGlintsAt(PH.x, PH.y, PH.z, 3)`.

## 6. Glints / air rings (RunRig 4001-4110)
Port minimal: `PH.glints` counter; `collectGlint()` on pickup (+groove via `PSY.events.onBuff(PH,'glint')`); `spillGlints(n)` emits n glints in an arc that decays in 2 s and can be re-collected; air rings: on pass while `!PH.grounded` → `chainHit('blast')` + `PH.glints += 3`. Use existing `toys.js` pickup meshes; if absent, count only.

## 7. Head control: nod → pop/tuck/flip
`headStep` (367) only does horizontal. Port main.js `headVert/headLean` as `HD.nod_p` (pitch, ~0.32*clamp(up−down,−1,1)) and `HD.nod_v` (its derivative):
```js
// in headStep, after steer:
const np = HD.vt;                                  // pitch channel from main.js headVert
HD.nod_v = (np - (HD.nod_p || 0)) / dt; HD.nod_p = np;
PH.tuck = HD.nod_p < -.10;                         // tuck: less drag, faster
if (PH.grounded && PH.pop_cd <= 0 && HD.nod_v > 1.1) { PH.vy = 6.2 * SPK; PH.grounded = false; PH.pop_cd = 1.0; chainHit('trick'); }   // POP
if (!PH.grounded) {
  if (HD.nod_v > 1.1) PH.flip = (PH.flip || 0) + 1;                       // flip (up-nod in air)
  if (HD.nod_v < -1.6) { PH.vy -= 12 * SPK; PH.slam = true; }             // slam
}
PH.pop_cd = Math.max(0, (PH.pop_cd || 0) - dt);
```
On landing: `if (PH.flip) { chainHit('trick'); PH.flip = 0; }` (score/boost).
Ramp charge: while grounded and tucked within 12 m of a ramp lip, `PH.charge = Math.min(1, (PH.charge||0) + dt*.8)`; on lip, `PH.vy += C.JUMP_BLAST * (1 + .25*PH.charge)`.

## 8. Finish / lap
Godot `_finish` (5929) ends the course; gv.js `if (PH.z < WORLD_END) { PH.lap++; ... }` is fine (stream mode loops). Add `PSY.events.onLap && PSY.events.onLap(PH)`; resetting `feats.done` / `toys.used` is already in the parent's patch.

## Impact ranking
1. Fixed 60 Hz step (everything else tunes against it).
2. Chain/flow via `PSY.events` (Godot's actual reward loop).
3. Crash/landing rules (remove phantom WIPEOUT, add spill + chain reset).
4. Pops/tuck/flip/ramp-charge (head-nod channel).
5. Rail fixes (x.6, x2).
6. Remove invented glue / extra air gravity.

`physicsrig.js` not created: the step is too entangled with gv.js globals (`PH`, `C`, `SPK`, row data, FX) to be a clean pure module.
