# Downfall: the trip game (design v1, 2026-11-24)

**The goal:** the most powerful, fun and rewarding psychedelic experience a game can give, steered by your head.
- It's for anyone who wants to get high on it, stoners and psychonauts alike:
  - If you're already high, it enhances the high.
  - If you're sober, it simulates one, as a clean virtual trip.
- It has to be fun either way. Every effect is tuned so a high player enjoys it and a sober player feels it.
- The game is built on what you crave: hunt and seek, speed, sizing up what's incoming, split-second choices.

## 1. The one loop: dose, rush, waves, afterglow

Every molecule is a dose. Each one plays out in four phases:

| Phase | How long | What you feel | What the game does |
|---|---|---|---|
| **Sober** | Between doses | Calm and clear. You're hunting. | Clean world. Columns of light far down the road show where the next dose is. |
| **Rush** | 2–4 s | A hit: energy, speed, a flood of light. | Tracers, blur and a colour bloom. The music swells, with a speed boost and a short slow-motion. |
| **Waves** | About 30–60 s | It keeps coming back, a bit stronger each time. | Effects swell and ebb, with calm gaps between them. Each dose in a level lifts the ceiling a little. |
| **Afterglow** | About 60–90 s | All is well with the world: warm, easy, loving. | Soft warm colours and a world that breathes. Hidden things appear: paths, ramps, gates, creatures. |

**Objectives live in the afterglow.**
- What the trip reveals can only be taken while it lasts.
- The fading world is the timer, so no clock appears on screen.
- When it's gone, you're sober and hunting for the next dose.

## 2. The readability rule (never broken)
- The road, the hazards and the pickups are always drawn clean.
- Effects live in the sky, the terrain surfaces, the edges and the colours, never over what's coming at you.
- By default the screen is calm, with a small spike when you take a dose.
- A flash of chaos is allowed now and then: one second at most, and never during a skirmish.
- Heavy distortion appears only in the finale. Even then the road stays lit and readable while everything else melts.

## 3. Compounds: each dose is a different trip
The story already has WREN making the Pieces, so each compound is one of them. Every one has its own look from your bag of looks, its own music shift, and its own power:

| Compound | Feels like | Look | What it does in play |
|---|---|---|---|
| **Lucid** (LSD-like) | Patterns, breathing geometry, insight | Tracers, moiré, fractals | Reveals hidden roads and ramps |
| **Embrace** (MDMA-like) | Warmth, love, energy | Golden glow, soft bloom | Pulls pickups to you, and enemies stop hunting you |
| **Velocity** (stimulant-like) | Rush, confidence, razor focus | Speed lines, smeared light, hard contrast | Top speed up and time slowed for split-second gaps. A short, brittle afterglow that wants another dose. |
| **Haze** (cannabis-like) | Mellow, sinking in, music gets huge | Rich saturated colour, soft edges, light and sound ripples | Bass and colour go deep. The world slows into a long, easy afterglow, good for the Chill mode. |
| **Drift** (opioid-like) | Sedation, warm bliss | Cotton-soft light, slow motion, muffled sound | Hits don't hurt and everything slows. ACCORD hands it out to keep people docile, so its bliss has a cost in the story. |
| **Hollow** (dissociative, ketamine-like) | Detached, floating outside yourself | The camera drifts out of the car, the world goes distant and geometric | You steer from outside your body and see the whole course, including hidden lines. |
| **Fold** (salvia-like) | Reality peels into pages and layers | The world splits into flat sliding layers, like turning pages | Short and strange. It opens the recovered-book pocket-worlds. |
| **Deep** (DMT-like, rare) | Breakthrough, alone in the universe | Tunnel, void, stars | The breakthrough. Saved for the big moments and the finale. |

**Obfuscated names:** in-game names only, with no real drug names anywhere.

Each world introduces one compound. Later worlds mix them.

**Rules that make compounds a game:**
- **Combos:** two compounds stacked make a special state of their own. For example, Lucid with Embrace is the candyflip: love plus patterns.
- **Tolerance:** the same compound twice in a row hits softer, so variety pays.
- **Set and setting:** the world and the music colour every dose.
- **Comedowns are gentle:** a stumble, never a punishment.

## 4. One level (8–12 min)
1. **Arrival:** an ethereal, atmospheric track. You scan the road and spot the first column of light far off.
2. **Dose 1, then a small objective in the afterglow**, such as taking the hidden ramp.
3. **Skirmish:** the music announces it before anything appears. Drones or a Murmur relay come at you, and the choices are split-second: dodge, smash, or use your gear.
4. **Dose 2, stronger, then a bigger objective** through a gate only the trip shows you.
5. **Set piece:** a big jump or a long rail into the exit and the level prize. Calm returns.

## 5. The whole game builds to one peak
- Each world allows a little more intensity than the last.
- **The finale is the full trip:**
  - Come-up: doses stack.
  - Waves: they keep growing.
  - Dissolution: the world falls away until only you, the road and the music remain. You're alone in the universe, and the story's ordinary things (Murmur, the road, the Courier) come back as profound and beautiful.
  - The ride home: a long afterglow that runs over the credits.
- Loss of control is felt, but you can still drive.

## 6. Music (Borderlands-style)
- A thumping track for the cold open.
- Ethereal atmospheric tracks for each world.
- A driving rhythm layer that starts **before** enemies arrive or an important scene begins, so the music warns you.
- Each dose shifts the music: stems layer in on the rush and thin out in the afterglow.
- The finale track builds through the whole climax.

## 7. Story: optional and well placed
- It's a light frame by default: the cold open, plus Murmur messages inside the car.
- A deeper season arc is there for players who want it.
- Story beats only land in calm or afterglow stretches. They never come during a skirmish or a rush.
- The Story switch stays in the pause menu.

## 8. Why players come back
- **Compound catalogue:** discover each Piece and its effect, and find the combinations.
- **Unlocks:** new worlds, plus cars, gear and looks.
- **Per level:** a grade, the quests, and beating your best.
- **Modes:**
  - **Quick Trip:** one level, about 5 minutes, good on the phone.
  - **Season:** the story and the finale.
  - **Journey:** endless dosing through every world.
  - **Chill:** no enemies, a long afterglow, for the couch or for tripping.

## 9. What carries over
- From the current game:
  - head steering, the worlds and courses
  - the car builder and gear
  - the relay strike, the light beams, rails and jumps
  - the lens system (already shaped like an afterglow that opens gates)
  - the jump watch and the right-click inspector
- **Ported in:** your psychedelic look, and the blur and tracer effects from the three.js and godot-dev builds.

## 10. First build: one slice to judge it by
One level, start to finish:
- One world in your psychedelic look, with the tracers ported.
- One compound (Lucid) and the full dose loop.
- One afterglow objective.
- One skirmish with its music cue.
- The readability rule enforced.

You play it on the phone. If it feels right, the rest gets built the same way.

## Open
- Hard no's (anything that would ruin it for you or your son).
- Music rights for a public release. The current tracks are licensed non-commercial, and two of them are no-derivatives, which stops us from remixing them into stems.
