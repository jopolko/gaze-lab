# The Frequency: open basins (plan, 2026-11-25)

The question: can the game open up (branch off, explore, then hit a fast straight again) and keep its speed, its feel and its frame rate? Yes, if the open areas are **basins**, not an open world. This plan fits them to the decisions already made (RECONCILED_DESIGN.md, SEASON_ONE.md, the master plan, the owner's rules in memory).

## 1. What a basin is
A wide bowl beside or below the highway, a few hundred metres across, that **still falls downhill**. You drive in fast on a chute, roam it in any direction your head points, and leave by one of several mouths at its low end, back onto a fast straight.

- **Still the fall line.** The bowl tilts, so you never stall and never need to reverse. "The only way out is down" stays true. Exploring means choosing lines, not crawling.
- **Not a map you get lost in.** Bounded (about 300 m wide, 500 to 800 m long), lit by the same light shafts as now, edges that curve you back in gently (a lip, never a wall you hit).
- **Same control.** Left, centre, right and lean. Targets are big and far apart. No auto-steer: the slope and the world pull you, the board never turns by itself.

## 2. Why it belongs in this story
- **Basins are the Unmapped.** The highway is the Rail's road; the Rail's map ends at the edge of the tarmac. A basin is the ground it can't model (the storm-cut and heat-cut land of the master plan), which is why the good stuff is there.
- **Predicted You loses you there.** On the highway the Rail's ghost guesses your line easily. In a basin there are too many lines, so taking a new one is how you shake it (when Predicted You is built, basins are where you beat it).
- **The lenses are how you read a basin.** This is where the molecules/senses earn their place (a pillar that is currently thin):
  - **SEE**: the hidden cave mouth or second chute only shows under the lens.
  - **HEAR**: the way to the prize is a sound you steer toward (the music leans to one side).
  - **SLOW**: a jump across the bowl that is only makeable in slow time.
  - **READ / TRUTH**: the Rail's signs in the basin lie; under the lens they point the real way.
  - **MERGE** (late): two of these at once.
- **Gear quests live there.** SEASON_ONE.md already has gear-locked exits with "a short area" behind each. A basin is that area done properly: rubble the Bull Bar ploughs into a cave, a drone nest the Rockets clear, a broken bridge the Magnet pulls back, a hazard run only the Shield survives.

## 3. Where basins sit in a level
A level stays about 6 km and keeps its three acts (teach, practise, test). Basins replace the "short areas" behind exits:

- **Act 1 (teach):** no basin. Highway only, so the new thing is learned alone.
- **Act 2 (practise):** one basin off an exit. Optional. The highway carries on beside it for anyone who skips it.
- **Act 3 (test):** the finale basin, which every player enters. The level's big reward is in it (Route Zero's Lamp, Sugarfall's vault, and so on), with the lens lock at its heart.
- Every basin rejoins the highway, so a level is still one run with a start and an end.

## 4. No dead ends (and dead ends that aren't irritating)
Every line leads to a mouth. A side pocket that looks like a dead end is allowed only if it never stops you:
- **It pays.** Every pocket holds something (a molecule, a secret, a view), so going in was worth it.
- **It throws you back.** The end is a curved wall (a quarter-pipe) the slope carries you up and drops you back down, or a spring that throws you over the rim onto another line. You keep your speed; there is no stopping and no reversing.
- **It's short.** Never more than about three seconds from the mouth of the pocket to being back in the bowl.
- **It looks like what it is.** You can see from the entrance that it's a pocket, so going in is a choice, not a trap.
- **Or it drops you out.** A pocket's end can open into a slide or tunnel that comes out further down the basin, so the "dead end" becomes a shortcut.

## 4b. Basins across the whole game
Each world's basin is built around that level's lens, so the basin is where you practise the new sense. They open up as the season goes on: small and readable at first, the last level almost all basin.

| # | Level (lens) | Act 2 basin (optional) | Act 3 finale basin |
|---|---|---|---|
| 1 | Route Zero (SEE) | **The Wash**: a dry flood bowl; SEE shows a cave mouth hidden under a redaction bar | none: Route Zero keeps its finale (tunnel, Lamp) |
| 2 | Sugarfall (READ) | **The Melt**: a syrup bowl of wafer walls; the labels tell you which walls are soft | **The Vault floor**: read the right label and the vault opens onto a wall of colour |
| 3 | The Safe Peaks (SLOW) | **Avalanche bowl**: gap jumps you can only make in slow time | **The Lift**: the slow-motion ride over the peaks, launched from the bowl |
| 4 | Tomb of the Old Servers (HEAR) | **Dune sea**: a buried tomb you find by steering toward its sound | **Inside the tomb**: a chamber you ride by ear until it sings |
| 5 | Neon Accord (TRUTH) | **The Plaza**: billboards point the wrong way; TRUTH flips them | **Billboard canyon**: every sign flips at once and shows the way out |
| 6 | The Undertow (SEE + HEAR) | **The Cistern**: a dark cavern mapped by sound and light | **The Undertow**: the whole cavern lights up in sound |
| 7 | Cold Rack (MERGE) | **Server aisles**: rows of racks as pockets; one holds the record | **The cold hall**: the racks go dark, the record plays |
| 8 | The Open Channel (all) | none | **The Commons**: the level is one huge basin, every lens at once; the ending |

How basins carry the rest of the game:
- **Gear quests.** Every basin has one pocket per gear (rubble, drone nest, broken bridge, hazard run). Each holds a shard, so shards live in basins.
- **Coming back.** A new lens reveals pockets in old basins you couldn't see before (the master plan's replay hook). Route Zero's Wash has a pocket only HEAR finds, and so on.
- **Predicted You** (when built). The ghost is easy to shake in a basin and hard on the highway, so basins are where you win against it.
- **Endless Journey.** The only random place: basins from a pool of finished ones appear every few kilometres, so a long run keeps opening up.
- **Learning.** Level 1's basin is small, with one obvious secret. By level 8 the whole level is a basin. Openness is taught like any other skill.

## 5. Performance (Intel UHD 620, the target)
- A basin is about one stretch of today's course, made wider, so it costs about the same to draw: one terrain patch, instanced trees and rocks, the existing shaders.
- Only the basin you're in and the chute either side are loaded; the highway beyond is hidden while you're in it.
- Draw distance stays the same; fog hides the far rim.
- Measured with the perf tools before anything ships: no frame-rate drop against the same level without the basin.

## 6. How it's built (the technical shape)
Much of the code treats **distance down the course** as progress (rows, beacons, trail placement, the dose arc, pickup checks). Basins keep that: because a basin still falls, distance down it still means progress, and the open part is mostly **width**. So most systems keep working, and the new work is:
1. **Terrain:** a wide bowl patch joined to the course at an exit and a mouth, with a rim that curves the board back in.
2. **Sideways freedom:** the board's side limits widen inside a basin.
3. **Placement in two directions:** basin content is placed by position (x and z), not by "metres along the trail".
4. **Camera:** a little higher and wider inside a basin so you can see the lines.
5. **Exits and mouths:** the signed off-ramp in, the light shafts over the mouths, the merge back onto the highway.

## 7. The prototype (first, before anything else changes)
A test level, separate from Route Zero so nothing you've already approved is touched:
- **`?basin=1` in the desert:** 1 km of highway, an exit into one basin, three mouths back out, 1 km of highway to the end.
- **In the basin:** one SEE-hidden cave (the lens shows it), one sound to steer toward, one big jump across the bowl, molecules on three different lines, and one pocket with a quarter-pipe end that throws you back out.
- **Judged by:** Does it still feel fast? Do you find the mouths without help? Is it fun to go back for the line you missed? Does the frame rate hold? Would you replay it, and would you show it to your son?
- If it passes, basins go into the Season One levels as their Act 2 and Act 3 areas. If it fails, it is cut and the highway stays as it is.
