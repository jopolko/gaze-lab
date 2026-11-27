# DOWNFALL: the Badlands Tournament (series bible, replaces the neon-noir / Rail / crystal version)

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
