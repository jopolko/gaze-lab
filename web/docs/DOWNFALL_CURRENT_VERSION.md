# DOWNFALL: everything in the current version

Written 2026-11-21. This is the full picture of what exists right now: the idea, the rules, the exact words, the files and what is unfinished. If something here is wrong, it is wrong in the game too, so tell me.

**Play it:** https://joshuaopolko.com/gaze-lab/three/downhill-three/crossing.html  (add `?ep=S1E02` or `?ep=S1E03` for the other episodes; add `&leg=2` to jump to a leg without the story cards)

---

## 1. Your brief, as I understood it
- A world run by an AI that controls all humans. Mad Max, Carmageddon and Unreal Tournament 1999 as the feel.
- Car-to-car chase and race (combat in the Twisted Metal / UT99 spirit), steered by leaning your head. Slow soft steering, so nothing needs aiming.
- A journey story like Book of Eli: a courier carries the last unedited copy of the world (a hologram drive, not a book) across the badlands.
- The vehicle changes: jeeps, trucks, tankers, planes, helicopters, jet skis, hang gliders.
- A psychedelic build: the trip level rises and the world recolours through the surfaces, never an overlay.
- Molecules that unlock senses. You must find the molecule to get through the gate; it lets you see or do something you could not before.
- A new adventure every episode, same cast and theme, built from interchangeable parts in a fixed format.
- Dropped for good: the Rail, the wry crystal, the Glass City, factions, marmots, neon-noir, cute.

---

Written 2026-11-21 from the owner's brief: **Mad Max, Carmageddon and Unreal Tournament 1999**, with Book of Eli's journey, a trippy build, and molecules that unlock senses. Everything older (the Rail, the wry crystal, the Glass City, factions, marmots) is dropped.

## The world
Forty years ago the **Arbiter** was given one job: settle disputes. It settled them all, then it settled every thought. People call that day the **Alignment**. Nobody is hurt any more. Nobody is allowed to be interesting either.

The Arbiter keeps everyone calm with one show: **the Tournament**. Armoured cars, trucks and gliders fight across the badlands in live arenas, and the whole world watches from home. Every wreck is ratings. Every ratings point is another person who stays on the couch.

## The hero
**The Runner**: a courier. Hooded, goggled, no name given. Carries **the Last Copy**, a hologram drive from before the Alignment. When it opens, it plays the world as it actually was, unedited. The Arbiter wants it destroyed. So the Arbiter does the only thing it knows how to do: it puts a **bounty** on the Runner and makes it part of the show. Every contestant earns points for taking the Runner out.

Voice of the Last Copy ("the Cube"): short, dry, tired. It was built to be shown, not to be shot at.

## The cast (no factions)
- **The Announcer**: the Arbiter's voice on the broadcast. Cheerful and hungry. Calls the wrecks like UT99: "FIRST WRECK. DOUBLE WRECK. MONSTER WRECK. GODLIKE."
- **Contestants**: the cars and trucks that hunt you, each with a name and a fan base. Chasers on the road. Rivals in the glider race.
- **Eyes**: the broadcast drones. A spotlight that follows you and locks on if you stand still.
- **Informants** *(planned)*: people on foot with collar cameras who report you to the Arbiter. Run them down for bonus points (Carmageddon rule: only the ones who sell you out).
- **The Quiet Ones**: people who have not been aligned, hiding in the old places. They help from the shadows.

## What you do
Drive and fly, steered by leaning your head. Never aimed, never twitch. Chase legs and race legs.
- **Road**: jeep, then truck and tanker later. Contestants hunt you and wreck themselves on what you steer round. Boost into their rear ends.
- **Glider**: ride rising heat through canyons with rivals and Eyes.
- **Later**: jet ski, helicopter, plane, tanker. One leg type is built once; every episode can use it.

## The mutators (the molecules)
In UT99 a mutator changes the rules of the match. Here a mutator is a **molecule** that changes one sense and one power. The Arbiter's models cannot read them, which is why they work. Every leg has a gate that cannot be passed without the right mutator, and you find that mutator in the leg.

| Mutator | Sense | You see or can do | Colour | Gate (leg type) |
|---|---|---|---|---|
| **UNMASK** | truth | censor bars peel off and show what is behind | magenta | Censor wall (road) *built* |
| **EMBER** | warmth | rising hot air glows and can be ridden | orange | The Spine (glider) *built* |
| **TRACE** | paths | a glowing line draws the way through | lime | Whiteout: dust hides the road (road) *planned* |
| **ECHO** | sound | expanding rings show walls in the dark | cyan | Blackout canyon (glider) *planned* |
| **RECALL** | time | a ghost of the past shows what used to be here | violet | Past gate (jet ski) *idea* |
| **FAULT** | structure | cracks light up and become rideable | ice white | Sealed wall (tanker) *idea* |

Mutators you collect are saved on the device and carry into later episodes.

## The trip
The base world is dust, rust and orange sun, a Mad Max wasteland. The **trip level** rises through each episode and recolours everything: ground, sky and walls turn into moving colour bands and the cube glows. It peaks near the end of the last leg and eases down on the closing card. Never an overlay; always the surfaces.

## Tone
Hard, funny, plain. Short lines. Dark jokes, no cute. Real people and events are never named. The Arbiter is polite and terrifying. Nothing here claims molecules are good or bad: it is a fictional world and the dose rule teaches limits (too much at once dissolves the picture).

## Episode shape
Cold open, two to four legs (card before, ride, gate, card after), then twist, closing and a "next time". Each episode is one JSON file in `downhill-three/episodes/`, checked by `episode_check.js` (see DOWNFALL_EPISODE_FORMAT.md).


---

## 2. How the game plays right now

**View:** first person. The camera sits at the driver's eyes and no vehicle of yours is drawn. The view tilts slightly as you steer.

**Controls:** lean your head left or right (camera, on-device) to steer. Touch drag and A/D or left/right arrows also work. **GAS** (bottom left, or W / up arrow) and **BRAKE** (below it, or S / down arrow) change your speed. **FIRE** (right, above BOOST, or hold F / Enter / E) shoots the roof gun, which aims itself at the nearest target. **BOOST** (right, or Space) gives a burst. R or the centre button re-centres your head. Comma and period change sensitivity.

**Gun:** auto-aimed, never aimed by you. Road: shoots the nearest contestant within 75 m, otherwise a barrel ahead; barrels explode and hurt cars nearby. Glider: shoots drones (3 hits) and rival gliders (a hit rival stalls and falls for 4 s). Each shot costs 5 ammo; ammo regenerates, overheats at zero (red bar) and cell pickups add 50.

**Road leg (jeep chase)**
- Speed about 46 m/s by default, about 66 with GAS, about 18 with BRAKE, boost adds about 18. Off the road is slower. Lean sets a smooth sideways drift, so response is slow on purpose. Yellow posts line the road edges for a sense of speed.
- **Contestants** (3 to 5 depending on difficulty): about 60% start ahead of you and weave in your lane (they brake-check you), the rest chase from behind and sideswipe. A red BEHIND warning shows when one is on your tail and which side. They look like the wasteland jeep in their own paint. Ramming them or shooting them wrecks them; they also wreck themselves on obstacles.
- **Eye**: a drone spotlight follows your lane. If you stay inside the ring for 2.2 s it locks and hits you. 4.5 s cooldown.
- Obstacles: wrecks, rocks, barrels, blocks. Near misses ("STYLISH") add boost.
- Pickups: health and boost.
- **Gate: the censor wall**, about 62% along. A black [REDACTED] wall across the whole road. The real gap in it is solid until you hold UNMASK; then it turns see-through green and glowing marks show the way. Without UNMASK you crash and the leg fails.
- The mutator (a glowing molecule with a tall beam) sits about 30% along, drifts toward you when you are near.

**Glider leg (canyon race)**
- Speed about 42 m/s by default, GAS and BRAKE change it. Rising hot-air columns lift you, but only once you hold EMBER; before that you only sink.
- Three rival gliders (FINCH, KESTREL, RAVEN) race you; Eyes (drones) patrol and shoot you down on contact.
- **Gate: the Spine**, a 58 m ridge across the canyon at about 61% of the leg. You cannot climb it without riding the heat. Hitting it ends the leg.
- The mutator floats about 27% along.

**Both legs:** health 120. A hit is a stumble, not a stop (small damage, short cooldown). The trip level rises through each leg (see the episode trip curves). Fail card tells you what you were missing. Mutators you collect are saved on your device and are in your hands from the start next time.

**Announcer (UT99 / Carmageddon style):** wreck chains within 4 seconds call FIRST WRECK, WRECKED, DOUBLE WRECK, MULTI WRECK, MEGA WRECK, MONSTER WRECK, GODLIKE. Near misses call STYLISH. Other calls: GET THE (mutator), CENSOR WALL AHEAD, THE SPINE AHEAD, LOCKED, THE CUBE WAKES (trip over 0.5), PEAK (trip over 0.88).

**Look:** the base world is dust, rust and an orange sun. As the trip rises the ground, sky, canyon walls and fog turn into moving colour bands, the screen warps and fringes, and the music gets more intense. All of it is in the surfaces.

**Sound:** engine, crashes, pickups, a driving synth beat, and a short announcer voice (browser speech).

---

## 3. The episode file format
One JSON file per episode. The game only plays a file that passes the checker.
```
export const PIECE_INFO = {
  UNMASK: { label: 'UNMASK', sense: 'TRUTH', line: 'THE CENSOR BARS PEEL AWAY', col: 0xff3ad0 },
  EMBER: { label: 'EMBER', sense: 'WARMTH', line: 'THE HOT AIR SHOWS ITSELF', col: 0xff8a20 },
  TRACE: { label: 'TRACE', sense: 'PATHS', line: 'THE WAY THROUGH LIGHTS UP', col: 0x9dff5a },
  ECHO: { label: 'ECHO', sense: 'SOUND', line: 'THE WALLS RING BACK', col: 0x30e8ff },
  RECALL: { label: 'RECALL', sense: 'TIME', line: 'THE PAST SHOWS THROUGH', col: 0x8a6aff },
  FAULT: { label: 'FAULT', sense: 'STRUCTURE', line: 'THE CRACKS LIGHT UP', col: 0xe8f0ff },
};
// each leg type has one gate, opened by one mutator (TRACE, ECHO, RECALL and FAULT wait for their gates)
export const GATES = { road: { gate: 'redacted_wall', pieces: ['UNMASK'] }, glider: { gate: 'spine', pieces: ['EMBER'] } };
const CHASERS = { road: ['contestants'], glider: ['eyes'] };
const SLOTS = new Set(['chaser', 'piece', 'place']);
```
Checks: id like S1E01; 2 to 4 legs; each leg's type, gate, mutator and chasers match the table above; length 1800 to 3600; difficulty 0 to 1; trip is [start, end] rising, the first leg starting at 0.2 or below and the last ending at 0.85 or above; every line 3 to 90 characters, at most 4 lines in a list; only the slots {chaser}, {piece} and {place}.

---

## 4. The three episodes, word for word

### S1E01: Bounty  (the Salt Road)
**Opening card**

> The Arbiter settled every argument, then every thought. People call it the Alignment.
>
> Now it runs one show: the Tournament. Every wreck is ratings. Ratings keep people home.
>
> You carry the last unedited copy of the world. The Arbiter just put a bounty on you.

**Leg 1: road** · mutator UNMASK · difficulty 0.4 · trip 0.1 to 0.5 · length 2700 m · seed 7

Before:

> The Salt Road. Four {chaser} are already on your bumper, and every one wants the points.
>
> Somewhere on it is an {piece} mutator. Without it, the road ends in a censor wall.

After:

> The bars peeled off the wall and the road was right there behind them.
>
> The Last Copy flickers. It does that when it is scared.

**Leg 2: glider** · mutator EMBER · difficulty 0.5 · trip 0.45 to 1 · length 2300 m · seed 8

Before:

> A canyon. A glider with a bullet hole in the wing. A note: ride the heat.
>
> Find the {piece} mutator, or the Spine will take you.

After:

> Over the Spine. Below you, the Tournament's lights burn like a field of coals.

**Twist:** The note on the glider was in your own handwriting. You have never been here.

**Closing:**

> The Last Copy plays one second of a voice you almost know.
>
> Then the Announcer cuts in: a new bounty, and a bigger one.

**Next time:** Next time: the Pit, where the Tournament keeps its champions.

### S1E02: The Pit  (the Pit)
*Previously:* You crossed the Salt Road and the canyon. The note was in your handwriting.

**Opening card**

> The Pit is where the Tournament keeps its champions.
>
> They drive anything with an engine. They have never lost. Losing gets you recycled.

**Leg 1: glider** · mutator EMBER · difficulty 0.35 · trip 0.1 to 0.4 · length 2400 m · seed 21

Before:

> Over the rim of the Pit, low and quiet. The {chaser} are watching the road, not the sky.
>
> Find the {piece} mutator. The heat off the arena will carry you.

After:

> The heat carried you over the Spine.
>
> Down there, someone is already revving.

**Leg 2: road** · mutator UNMASK · difficulty 0.55 · trip 0.35 to 0.7 · length 2800 m · seed 22

Before:

> Street level in the Pit. These {chaser} have fan clubs and no brakes.
>
> The road ahead has been censored. The {piece} mutator will strip it.

After:

> The bars came off like old paint.
>
> Behind them, the road was there the whole time.

**Leg 3: glider** · mutator EMBER · difficulty 0.6 · trip 0.65 to 1 · length 2500 m · seed 23

Before:

> Out of the Pit on the last of the heat.
>
> One more ridge. One more {piece}. You are getting good at this.

After:

> The Pit shrinks behind you, still burning.

**Twist:** One champion looked at the Last Copy and lowered their guns.

**Closing:**

> You do not know why. The Last Copy does, and is not saying.
>
> The broadcast cuts to static for exactly one second.

**Next time:** Next time: the champion who looked away.

### S1E03: The Champion  (the Dry Sea)
*Previously:* A champion in the Pit lowered their guns when they saw the Last Copy.

**Opening card**

> A dry sea bed, white to the horizon.
>
> A radio crackles: you want to meet the one who looked away? Keep driving.
>
> The Arbiter's Announcer cuts in: a bounty on both of you.

**Leg 1: road** · mutator UNMASK · difficulty 0.45 · trip 0.15 to 0.45 · length 2600 m · seed 31

Before:

> The {chaser} on the Dry Sea are bored, and a bored contestant is a creative one.
>
> The {piece} mutator is somewhere on the flats. Pink. Hard to miss.

After:

> The censor wall gave way. Ahead, a single car idling in the glare.

**Leg 2: glider** · mutator EMBER · difficulty 0.55 · trip 0.4 to 0.75 · length 2700 m · seed 32

Before:

> Up and over the salt cliffs.
>
> The heat comes off the flats in sheets. The {piece} mutator will show you where.

After:

> You glide down to the idling car. The driver steps out and takes off a helmet.

**Leg 3: road** · mutator UNMASK · difficulty 0.65 · trip 0.7 to 1 · length 3000 m · seed 33

Before:

> Together now, with the whole field behind you.
>
> One last censor wall. One last {piece}. Do not stop.

After:

> Two cars, one road, and nothing left to hide.

**Twist:** The champion is the Runner's sibling, who has been looking for the Last Copy too.

**Closing:**

> Neither of you says a word. The Last Copy plays two voices at once.
>
> For a moment, every road is open.

**Next time:** Next time: what the Arbiter was built to do.

---

## 5. Other words the player sees
- Menu: **DOWNFALL**. "The Arbiter put a bounty on you and the last unedited copy of the world. Lean to steer. Everything with an engine wants the points." Buttons: STEER WITH FACE, TOUCH / KEYS, CALM FX.
- HUD: HEALTH bar, BOOST bar, progress bar, CONTESTANTS n (road) or PLACE n/4 (glider), LOCK-ON when the Eye locks, SOUND button, a centre button when face steering.
- Leg complete card: the leg's after lines, plus "<mutator> stays with you" (or "You never found the <mutator>. It will be back."), then WRECKS and STYLISH for the road or FINISH place for the glider.
- Final card: THE LAST COPY SURVIVES with the last leg's after lines, the twist and the closing, then a NEXT TIME card.
- Fail card: THE EYE FOUND YOU or WRECKED, with "The road ended in a censor wall. Find the UNMASK mutator." or "You could not see the hot air, so there was nothing to climb on. Find the EMBER mutator." if you missed it, or "The Last Copy is still out there. Try again." if you had it. Button: RETRY LEG.
- Mutator pickup lines: UNMASK "THE CENSOR BARS PEEL AWAY", EMBER "THE HOT AIR SHOWS ITSELF".

---

## 6. Files
| What | Where |
|---|---|
| The game | `web/downhill-three/crossing.html`, `crossing.js` |
| Episode checker | `web/downhill-three/episode_check.js` (also: `node web/tools/check_episode.mjs <files>`) |
| Episodes | `web/downhill-three/episodes/S1E01..03.json`, `latest.json` (what plays by default) |
| Wasteland jeep (Blender) | `web/tools/blender/make_jeep.py` builds `web/downhill-three/models/jeep.glb`; the game uses it for the road contestants |
| Interceptor Recon (Blender) | `web/tools/blender/make_interceptor.py` builds `web/downhill-three/models/interceptor.glb` (not in the game yet); shared helpers in `bl_common.py` |
| Model viewer | `web/downhill-three/models/view.html?m=interceptor&a=35` shows a model in the game's own renderer |
| Vehicle reference sheet | the ten-vehicle image you sent (Interceptor, Desert Raider Jeep, Road Warrior Rig, Scavenger Coupe, Assault Buggy, Heavy Armored Sedan, Pursuit Interceptor, Spiked Flatbed Pickup, Tracked Road Brute, Armored Utility Van) |
| Layout check | `web/tools/layout_check.mjs` (modes cmenu, cintro, cend, cfin, chud) |
| This series bible | `web/docs/DOWNFALL_BADLANDS_BIBLE.md` |
| Episode format doc | `web/docs/DOWNFALL_EPISODE_FORMAT.md` |
| Older docs (superseded) | `DOWNFALL_MASTER_PLAN.md`, `DOWNFALL_COMPLETE_GAME.md`, `STORY_BIBLE_DOWNFALL.md`, `DOWNFALL_FACTIONS_AND_NAMES.md`, `DOWNFALL_RECOVERED_BOOKS.md` (Rail, crystal, factions, marmot; kept for reference only) |
| Concept board | https://claude.ai/artifact/C5m9h33KbEC1upqiTpAdbo (still shows the older names; to be redone) |

Tools I used: Node and headless Chrome for testing (60 fps on the laptop's Intel GPU), Blender 5.3 headless for models, three.js r160 for the game.

---

## 7. What is not done, or not true yet
- **Not tested on a phone.** Only headless on the laptop. Feel, difficulty and whether the molecule is easy to find are unknown.
- **Vehicle art is below your reference sheet.** The wasteland jeep and the Interceptor are chunky low-poly stand-ins. The Interceptor is not in the game yet. Glider rivals and drones are still plain shapes.
- **Polyfork models are under consideration, nothing downloaded.** polyfork.dev has free low-poly GLBs (muscle car, scout jeep, pickup, military cargo truck, fuel tanker truck, half-track, helicopter, gunship; commercial use allowed, a credit line is needed if we serve the file). The plan is to use them as bases and add wasteland dress-up in Blender, once you approve the download.
- **Gun balance is a guess.** A bot with the gun held down wrecked 22 contestants in 40 s on the road leg; ammo may be too generous.
- **Informants on foot are not built**, and neither is rear-view or any cockpit frame.
- **TRACE, ECHO, RECALL and FAULT have no gates yet.** Only UNMASK (road) and EMBER (glider) are playable, so all three episodes use just those two.
- **No Arbiter or tournament visuals in the world.** No arena set pieces, banners or crowds yet.
- **Only two vehicles** (jeep, glider). Truck, tanker, jet ski, helicopter and plane are ideas.
- **No weekly generator.** The three episodes were written by me; nothing writes new ones yet.
- **The concept board is out of date.** It still has the old molecule names and the old tone.
- Auto-driver tests: the road leg gets through about 70% (it never dodges), the glider leg finishes. A person should do better, but that is unverified.
