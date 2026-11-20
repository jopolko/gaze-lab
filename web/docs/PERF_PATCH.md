# PERF_PATCH: exact edits for gv.js and friends

New files (done, tested in node, not wired): `downhill-three/heightfield.js` (+ `heightfield_check.mjs`), `downhill-three/tiers.js` (+ `tiers_check.mjs`), `downhill-three/rowbench.mjs`.
Line numbers are gv.js at the time of writing; anchor on the quoted text.

## 1. Heightfield replaces the raycast (biggest win)

Measured (node, same ground meshes, 4000 points): raycast 764 us/call = 7.6 ms/frame at 10 calls; heightfield 0.23 us/call. Max difference 7e-13 m. A phone is 3 to 5 times slower, so the raycast alone is 20+ ms there.

```js
// top of gv.js, with the other imports
import { createHeightfield } from './heightfield.js';
const HF = createHeightfield();
```

Replace lines 248-249:
```js
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0);
function groundY(x, z) { ray.set(new THREE.Vector3(x, 3000, z), down); const h = ray.intersectObjects(ground, false); return h.length ? h[0].point.y : null; }
```
with:
```js
const ray = new THREE.Raycaster(), down = new THREE.Vector3(0, -1, 0), _ro = new THREE.Vector3(); const SLOWGROUND = [];   // meshes that are not a regular grid (none in long_s7)
function groundY(x, z) {
  const y = HF.height(x, z); if (y !== null) return y; if (!SLOWGROUND.length) return null;
  _ro.set(x, 3000, z); ray.set(_ro, down); const h = ray.intersectObjects(SLOWGROUND, false); return h.length ? h[0].point.y : null;
}
```
Where `ground.push(m)` happens (in buildNode0, the ground mesh branch), add right after it:
```js
{ const g = m.geometry, p = g.attributes.position.array, ix = g.index ? g.index.array : null;
  m.updateMatrixWorld(true); const e = m.matrixWorld.elements;
  // only a pure translation can be baked into the grid; anything rotated stays on the raycast
  if (Math.abs(e[0] - 1) + Math.abs(e[5] - 1) + Math.abs(e[10] - 1) + Math.abs(e[1]) + Math.abs(e[2]) + Math.abs(e[4]) + Math.abs(e[6]) + Math.abs(e[8]) + Math.abs(e[9]) < 1e-6 && HF.addMesh(m.uuid, p, ix, [e[12], e[13], e[14]])) m.userData.hf = true; else SLOWGROUND.push(m); }
```
In unloadRow, where `const gi = ground.indexOf(o); ...` add: `if (o.userData && o.userData.hf) HF.remove(o.uuid); const si = SLOWGROUND.indexOf(o); if (si >= 0) SLOWGROUND.splice(si, 1);`
The `ground` array stays (other code may use it); it is simply no longer raycast. Rows build a few nodes per frame, so a row's ground may be absent for a few frames: `th()` already falls back to `PH.lastGh`.

Anything else that raycasts (`grep -n "intersectObject" *.js`) should go through `groundY`. The hill's pull should use `HF.slope(x, z, 0.6)` instead of four `groundY` calls.

## 2. Tiers replace GOV (lines 339-347 and the `govTick(now)` call at 795)

The old governor only goes one way, judges an EMA of frame time (not Godot's 2 s window), and never recovers. Godot's: down after 3 s under 50 fps (2 s if the tracker is under 10.5 fps), 6 s cool-down, up after 16 s at 55+ fps, never above the floor (tier 1 on web or phone).

```js
import { createTiers, detectWeakGpu } from './tiers.js';
const TIERQ = Q.get('tier');                       // ?tier=0..3 pins one (testing); ?nogov or ?shot = pinned at the start tier
const TIERS = createTiers({
  isTouch: matchMedia('(pointer:coarse)').matches, weakGpu: detectWeakGpu(renderer.getContext()), isWeb: true,
  pin: TIERQ !== null ? +TIERQ : (Q.has('nogov') || Q.has('shot') ? 1 : -1),
  cssSize: () => [innerWidth, innerHeight], dpr: () => Math.min(devicePixelRatio, 3),
  trackerOn: () => !!(window.__headFps !== undefined), trackerFps: () => window.__headFps || 60,   // <- point these at the head tracker's fps counter
  hooks: {
    setGlow: (on) => { GLOWQ.on = on; },
    setSamples: (n) => setSamples(n),
    setPixelRatio: (r) => setDpr(r),
    setPostLook: (on) => { /* post.u.look strength: 0 = tonemap only */ postM.uniforms.lookOn && (postM.uniforms.lookOn.value = on ? 1 : 0); },
    setTrails: (on) => { /* feedback ghosts: skip the feedback pass */ DBG.noTrails = !on; },
    setGrade: (on) => { /* colour grade (contrast/saturation) */ postM.uniforms.gradeOn && (postM.uniforms.gradeOn.value = on ? 1 : 0); },
    setGroundDetail: (on) => { /* GROUND_PSY fine noise */ },
    setSky: (on) => { /* sky dome + mountain skin visible */ sky.visible = on; },
    setVegRange: (m) => { VEG_RANGE = m; }, setBeaconRange: (m) => { BEAC_RANGE = m; },
    setFxScale: (k) => { FX_SCALE = k; },
    setStreamWindow: (a, b) => { RS.ahead = a; RS.behind = b; },
  },
});
```
Delete `GOV`, `GOV_STEPS`, `govTick`, and in the frame loop replace `govTick(now)` with `TIERS.frame(Math.min(dt, .25))` (dt in seconds). The MSAA-incomplete fallback at line 327 refers to `GOV.log`: change to `TIERS.log`. In `__gv.post`, replace `gov: GOV` with `tiers: TIERS`.
`postM`/`DBG` uniform names above are placeholders for the pass's real uniforms: wire each hook to whatever turns that stage off (the contract is just a boolean). `VEG_RANGE`, `BEAC_RANGE`, `FX_SCALE` are new module-level `let`s (section 3 and 6 use them). `resize()` must read `renderer.getPixelRatio()` (setDpr already calls it). Call `TIERS.apply()` once after the post pass exists.

Tier table (touch / desktop where they differ):

| tier | name | grade | ground detail | gate lights | trails | snow | shafts | sky | glow | post look | render scale | veg range | MSAA | fx | rows ahead/behind |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | everything | on | on | on | on | on | on | on | on | on | 1 / 1 | all | 2 / 4 | 1 | 5/2 |
| 1 | phone look (web floor) | off | off | off | off / on | off / on | on | on | on | on | 1 / 1 | 260 / 340 | 0 / 2 | 1 | 5/2 |
| 2 | glow off, smaller | off | off | off | off | off | off | on | off | on | .88 / .92 | 210 / 280 | 0 | .6 | 4/1 |
| 3 | smallest, no pass | off | off | off | off | off | off | off | off | off | .76 / .82 | 160 / 230 | 0 | .35 | 3/1 |

Pixel budget caps the scale: 0.95 Mpx phone, 1.2 Mpx Intel iGPU, 2.1 Mpx otherwise. A 390x844 phone at dpr 3 gets pixel ratio 1.70.
Finding: because of the floor, the Godot web build the user saw had NO colour grade and no ground detail. The numbers I calibrated exposure against came from desktop frames with the grade on. If "looks like Godot web" is the goal, call `TIERS.setTier(1)` flags for look; if "looks like Godot desktop", set `floorTier: 0` in createTiers and accept the cost.

## 3. Distance culling (cheap, large)

Everything is built with `frustumCulled = false` (about 735 draw calls, 450k triangles resident). Rows 2 behind + 5 ahead = 8 rows x 180 m.
Per frame, in playStep after `rowsUpdate`:
```js
function rowVis(z) {                       // hide rows beyond view; rows are 180 m slabs, row j spans z in (-180(j+1), -180j)
  const range = VEG_RANGE > 0 ? VEG_RANGE : 1e9;
  for (const k in ROWREC) { const j = +k, zc = -180 * j - 90, d = Math.abs(zc - z) - 90, vis = d < range; if (ROWREC[j].vis !== vis) { ROWREC[j].vis = vis; for (const o of (OBJS[j] || [])) if (o.userData.veg || o.isInstancedMesh) o.visible = vis; } }
}
```
`o.userData.veg` must be set where vegetation instanced meshes are made (mat.userData.veg already exists: copy it to `im.userData.veg`). Ground meshes stay visible (they are the course). This is the Godot `veg_range`.
Also turn on real culling for static meshes: in buildNode0, after creating a MeshInstance, replace `frustumCulled = false` by leaving it true and call `m.geometry.computeBoundingSphere()` once; for InstancedMesh call `im.computeBoundingSphere()` (r160 has it) after the last `setMatrixAt`. Only the sky, quad, and beacons need false.

## 4. Merge static meshes per row (about 41 per row)

After a row finishes (`onRowBuilt(j)`), group `OBJS[j]` plain Meshes by material uuid and `BufferGeometryUtils.mergeGeometries` (apply matrixWorld first), replacing the group with one mesh. 41 to roughly 8 draw calls per row, so about 330 fewer per frame. Skip anything in `ANIM`, `REGN`, or tracked by name (toys, vortex rings keep references). Do this in a time-sliced step (one row per frame).

## 5. Beacons: instance them (450 to 700 individual meshes)

`BEAC.push({ m, o, kind, z })` makes one Mesh with `frustumCulled = false` each. Use one `InstancedMesh` per kind with `count = BEAC_COUNT`, write matrices only for beacons with `|z - PH.z| < BEAC_RANGE`, set `mesh.count` to the visible number, and update `instanceMatrix.needsUpdate` only when the window moves (every few metres, not every frame). 700 draws to about 3.

## 6. Bounded per-frame loops

Index toys/targets/pickups by row: `ROWS[j].targets` already exists in physics.json rows; loop only `ROWS[j0-1..j0+1]`. Anything that loops all of `lvl.rows`, `PILLS`, `BUFFS`, `PADS`, `RAILS` each frame should start at a binary-searched index (PILLS is already sorted by z at buildWorld). Particle bursts: multiply counts by `FX_SCALE`.

## 7. Allocations in hot paths

- gv.js:219 `rowsUpdate`: `const want = new Set()` every frame. Early-out when `j0 === RS.lastJ0 && !RS.dirty` (rows only change when the board crosses a 180 m line).
- gv.js:249 `groundY`: `new THREE.Vector3` and a result array per call (fixed above).
- `animTick` (line 178): reuse module-level `Matrix4`/`Vector3`/`Quaternion` temps; check for `new` inside the per-group loop.
- `th()`/slope: use `HF.slope` (returns one 2-array; or inline the four heights).
Check with Chrome's allocation timeline over 30 s of play; the goal is no sawtooth.

## 8. Row arrival hitches

`node rowbench.mjs` (same loops as gv.js, no GPU upload):

| row | JSON KB | parse ms | build ms (geom + instance matrices) | instances | verts |
|---|---|---|---|---|---|
| 2 | 370 | 6.2 | 28.6 | 1151 | 15.7k |
| 5 | 375 | 6.6 | 27.8 | 1120 | 19.7k |
| 10 | 433 | 7.8 | 13.7 | 977 | 13.4k |
| 20 | 368 | 7.3 | 23.0 | 1124 | 17.7k |
| 33 | 980 | 21.4 | 37.4 | 1120 | 49.7k |

Desktop figures; a phone is 3 to 5 times slower, so one row is 100 to 200 ms of work. `pumpBuild(3.5)` already slices the build across frames, but `JSON.parse` of a row (`fetchRow` -> `r.json()`) and the geometry upload on first draw are single blocking steps (the first draw of a new shader program is the worst: that is why `VFX.refresh()` compiles). Fixes, in order of cost:
1. `renderer.compile(scene, camera)` (or `compileAsync`) for each row's new materials before making them visible; first-use shader compile is the typical 100 ms stall.
2. Prefetch rows 6 ahead as raw text only; parse right when they enter the window.
3. Move fetch + parse + typed-array packing to a Worker and transfer `Float32Array`s (largest effort; row 33 at 980 KB is the case that needs it).

## 9. Disposal

unloadRow disposes geometry (`GEO[id]`) and InstancedMesh. Not disposed: materials created per row, textures if any, and `instanceColor`. Verify with `renderer.info.memory` (geometries/textures) over a full lap: both must be flat after the first 8 rows. A leak shows as steady growth by lap 2.

## Order of work
1 (heightfield) and 2 (tiers) first: pure logic, tested. Then 3 (row distance visibility, 5 lines), 7, 5, 4, 8.
Test: `?dbg&tier=2` pins a tier; `window.__gv.renderer.info.render` gives calls/triangles; target under 250 calls and under 150k triangles on screen at tier 1.
