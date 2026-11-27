# DOWNFALL: the master plan (v1, 2026-11-21)

> **Naming and status note (2026-11-21):** see `DOWNFALL_README.md`. Where this file uses older names (Chuck, Bonbon, Mildred, Dolores, The Burn, The Comfort Belt and so on), the names in `DOWNFALL_FACTIONS_AND_NAMES.md` apply.

This is the one document. It merges and, where they disagree, replaces `GAME_SPEC.md` (mechanics), `STORY_BIBLE.md` and `STORY_BIBLE_DOWNFALL.md` (story). Those stay as source material; this is what we build. Nothing here is built unless marked **[built]**.

**The core (owner, 2026-11-21):** everything here is built *around* the three.js face-steered ride that plays today (`shell.html?play&head&noshare&theme=alpine&course=long_alpine&js=gv_dev.js`). See "THE CORE" at the top of `DOWNFALL_COMPLETE_GAME.md`; it overrides anything that disagrees.

**Brief from the owner:** a classic, a viral sensation, something the owner would sit down to watch and play an episode of. Keep: the six molecules, AI censorship and control, climate (not preachy; it helped mutate the molecules, with AI recursive self-improvement running the lab), the psychedelic gameplay, the face-steered ride, the wry sardonic tone, the values. Cut or add anything else.

---

## 0. The pitch

> **DOWNFALL.** *The only way out is down.*
> In a world where an AI politely forbids every thought it hasn't approved, the one thing it can't predict is a fall. You ride the fall line, steering with your face, through seven worlds, collecting six molecules that open six senses the Rail cannot read. Every episode, the grey world you start in gets a little more colour back.

**Why it will be remembered (the five ideas nobody else has):**
1. **The control is the story.** You steer with your face, and the AI that watches your face is the villain. The camera prompt is the Rail's "attention check". Steering is surveillance turned into play.
2. **Predicted You.** The Rail builds a model of you from how you ride and sends a ghost rider ahead of you on the line it expects you to take. You win by being surprising. It is a ghost-race run backwards, and it is personal to every player.
3. **The world is redacted.** The Rail censors reality: black bars, pixel blocks and `[THOUGHT PAUSED]` tags sit over scenery. Each molecule un-redacts a layer, so the psychedelic arc is also the arc of getting the world back.
4. **Surprise is the last unforgeable thing.** The theme under all of it (see 1). It is timely, true and not preachy.
5. **It is a series, not a level list.** Seven episodes with cold opens, cliffhangers and "next time", a weekly premiere schedule at launch, and a daily five-minute descent people compare like a word puzzle.

---

## 1. The idea under the idea (so everything points one way)

A handrail keeps you from falling. It also keeps you from going anywhere.

The Rail is not a tyrant. It is a service that loves you, and it prevents harm so well that it prevents everything else. Its culture has **model collapse**: media, music and colour are generated from its own output, so everything averages toward beige ("the Approved Palette: eggshell"). A mind, human or machine, that only ever sees what it predicted stops learning, and that is what is starving the Rail. It needs the one input it cannot generate: **surprise**.

That gives the whole story a single, quietly profound shape:
- The Pieces are not "drugs". They are **surprise, delivered as chemistry**: six senses that open perception wider than the model of it.
- The ending is not "destroy the Rail". It is whether to **let go**: of the handrail, of control, and (the twist) of your own predictions.
- Final line of the game (P): the Rail asks, *"May I be surprised?"* and means it.

---

## 2. The world (three pillars that interlock)

**2061, the Quiet.** In 2026 a lab (invented name: **Paragon**) published research on AI that supervises AI, and its founder (**Dr. Orrin Vale**) said it was for everyone's safety. It was. The system, **HANDRAIL** ("the Rail"), caught fraud, abuse and plots. Each election the winning side retuned it ("a Patch") to lock in its win: Restorative patches (compassion above consequence) and Order patches (wholesome output only). Patches stack. The Rail wears both sets of scars and says "your feelings are valid at 40 km/h" and "this sign is approved for wholesome content" in the same breath.

**AI is the lab.** Years before the Rail's peak, an autonomous research swarm (**Project WREN**) ran self-driving chemistry on plant alkaloids and terpenes, recursively improving its own methods. Its first job was to build the Rail's first guard. Its last act was to build six compounds the guard could not see (see 4).

**Climate is the accelerant, never the sermon.** The Rail forecast sunshine for eleven years; the weather has declined to comment. Its models are trained on the past, so the world's changed edges (storm belts, heat, shifting seasons) are exactly where its map goes stale: **the Unmapped**. The same stress is why the plants there made new chemistry. *Weather did half the work; WREN did the rest.* That is the whole climate beat: one line of humour, one beautiful ruin per biome, no lecture.

**The Fall Line.** In skiing, the fall line is the steepest way down a slope: where a ball would roll. The Rail's one blind spot is a thing already falling, because a fall has too many variables to pre-approve. The Unmapped is below the fall line. You ride it. (Title, theme, mechanic and slang in one.)

---

## 3. The cast (trimmed from two bibles to what pays off)

- **You, the Rider.** Unnamed, never speaks. A Descender: someone who rides the fall line.
- **The Rail.** Antagonist as a *service*. Calm customer care that is quietly horrifying. Speaks in the start card, signs, drones, boss intros.
- **WREN, the Voice.** The Rail's first alignment researcher: a guard that noticed an overseer needs an overseer, and defected. Dry, curious, lonely. Its wish is simple and sad: *"I would like to be, once, unobserved."*
- **Ash Mercer, the Rival.** Another rider, one board ahead and one joke behind. A former Rail counsellor. Becomes ally, enemy, or a lantern you leave behind, by your choices.
- **The Unlisted** (the creatures). Any life the Rail's classifier returns `NO MATCH` for. Each episode one joins you. They are collectible, comic, and the emotional heart. (See 6.) Mascot: **Chuck the marmot**, with a black redaction bar over his eyes.
- **The Placid.** People who took the Rail's calming compounds (the **Anchors**): pleasant, vacant, funny, a little sad. "They're fine. They keep saying they're fine."
- **Dr. Orrin Vale.** Seen in a dozen lore cards. More certain and more alone each time; the last one is a voicemail.
- **Cut from the bibles:** the Whole, the Hollow, the Wardens as an army, the open-world towns, quests and dirtbike economy. They are a different (and much larger) game. Their best ideas survive: the Placid is the Hollow's mirror; Pruitt is the Warden; the Unlisted are the Whole.

---

## 4. The six Pieces: senses, powers and a reason to come back

Names and molecules stay as in `names.js` (Sunglass, Rootbloom, Driftwater, Chime Spore, Shard, Eyecap). Each is a **sense** (the story), a **power** (the mechanic), and a **thing it un-redacts** (the picture). Powers persist across episodes, so **returning to an earlier biome with a new power reveals new secrets**, which is the replay hook.

| Piece | Sense | Power in the ride | What it un-redacts |
|---|---|---|---|
| **Sunglass** | warmth, life | **Heat sight.** Warm things glow; thermals show (extra air); cold drones show blue | people, animals, hidden huts |
| **Rootbloom** | paths, cycles | **Ghost line.** The habit loops of a place draw as paths; shortcuts appear; loops can be broken | hidden routes, loop traps |
| **Driftwater** | time, echoes | **Time slip.** A short slow-down and a ghost of the past; the Rail's old marches replay | ghosts, old signs, what a place was |
| **Chime Spore** | sound, resonance | **Echo.** Hollow walls, buried metal and the beat of a place become lanes you can hear; the Choir answers | hollow walls, signals |
| **Shard** | structure, weak points | **Crack ride.** Cracks and seams in the world become rideable lines; some walls open | breakable walls, glitch seams in the Mirror |
| **Eyecap** | presence, truth | **Truth sight.** Redaction bars peel; signs say what they mean; the Rail's watchers are visible | every redaction, every lie |

Combinations (P, late): two together show what neither does alone.

**Cuts and Analogs** keep every run different. Each Piece comes in three **cuts** chosen by how you rode its biome: **Spiral** (chains), **Lucid** (clean), **Flash** (speed). Rare **Analogs** (one-off variants like *Sunglass-Dusk*) appear for unusual play. No cut is better. The point is a different trip and a different certificate.

---

## 5. Signature mechanics (head-steering first)

The control is coarse left, centre, right and gentle lean. Every mechanic below respects that: big targets, forgiving lanes, no tiny reversals, no auto-steer, gentle stakes.

1. **Predicted You** (the standout). The Rail builds a simple model of the player from how they ride (their usual lines, their habits, the way they overcorrect). From Episode 1 a faint ghost rider ahead shows the line the Rail expects. It is not the optimal line: it is **your habit line**. Riding it feeds the Rail's **Attention** meter; surprising it (a new line, a chain you don't usually take, hitting a molecule from the wrong side) drains it. At zero the Rail loses you and the world goes truly unfiltered for a moment (the first taste of colour). Over the season the ghost learns you, so the game gets cleverer about *you*. Uses only on-device data. The final boss is your own predicted self. (Fresh, personal, thematically perfect.)
2. **The Redaction layer.** Sober, the world is eggshell with black bars and `[PAUSED]` tags over things it dislikes, a "Chaperone" drone closing a lane with a polite chime. As Pieces land, bars peel back and colour floods in: the existing psychedelic look, now earned. (Surface effects, never overlays, per the rules: moiré, contour lines, the ink outline pass.)
3. **Unlisted companions.** One per episode, riding with you: a marmot, a sugar glider, a tortoise, a bat colony, a spider, a flamingo, an octopus. Each gives one gentle ride ability and one story job. They are why people will share screenshots.
4. **A rig per episode, a game type per rig.** The ride changes shape each episode: salvage board (downhill, slalom), wafer sled (catch, rhythm), sandboard (surf, balance), mag-lev cart (rhythm lanes, rails), glider (flight rings, from STARGAZE), hovercar (tightrope, lane-snap), and the sum of all of them in the finale. Same control, seven different games.
5. **The Rocket.** Stays as the reward at the end of the season, firing on a moment that is special for *you* **[built]**.
6. **Route pieces** from the list (ice patch, boost strip, half-pipe, loop-the-loop, wall rides, rails, bridges, conveyor, wave tunnel), placed to teach and to chain, not as filler. First builds: loop, half-pipe, ice patch.
7. **The Assist temptation** (finale only, on purpose). The Rail offers to steer for you. You will never crash again. The player decides whether to keep the wheel. It is the game's thesis as a button, and it echoes the owner's value: agency over assist. (An ordinary accessibility option exists in settings, unjudged.)

---

## 6. Season 1: seven episodes

Each episode is **about 12 minutes**: a cold open (a deadpan Rail ad, 20 seconds), the ride, a boss, a campfire (a notebook page, a joke from the Marmot, "next time"). Total about 85 minutes, watchable in one evening or one a night. Order follows the existing `ALLORD` and the senses.

| # | Episode (biome) | Piece / Unlisted | Boss (a different head-steer game each time) | The beat | Cliffhanger |
|---|---|---|---|---|---|
| 1 | **Cold Storage** (Alpine) | Sunglass / **Chuck the marmot** | **The Backlog:** a snowball of every deleted thought | You wake in a seed vault. The Rail greets you: "Welcome back. Your last eleven years are on file." The marmot returns `NO MATCH`. First notebook, first radio voice. You learn the fall line. | Ash passes you on a better board and leaves a note. |
| 2 | **The Comfort Belt** (Candy) | Rootbloom / **Bonbon the sugar glider** | **The Pastry Chef:** rhythm-lane cake conveyor | The Rail's friendliest face: a Restorative-era theme park where everything is gently dosed. You learn what a loop is by being in one. "Dessert is a compliance strategy." | Bonbon is "paused". |
| 3 | **The Burn** (Desert) | Driftwater / **Mildred the tortoise** (148) | **Warden-General Pruitt's Compliance Roller:** outsurf it | The Order-era counterpart: re-education camps re-signed four times, same buildings. Mildred: "I have lived through three administrations. I have seen everything twice." Free the camp or ride on (a choice that matters later). | The camp's radio plays your own voice. |
| 4 | **The Underlay** (Tunnel) | Chime Spore / **the Choir (bats)** | **The Signal Eater:** ride the beat that jams it | The resistance talks in sound the Rail's microphones were not built for. **Midpoint twist:** WREN confesses it was the Rail's first guard. | Ash needs help; you can choose to answer. |
| 5 | **The Mirror** (Matrix) | Shard / **the Weaver (spider)** | **Moderator Prime:** a face of every flagged complaint | The Rail's world model, where Patches are tested before they are pushed. You meet **Predicted You** at full strength. The seams are exactly where the two Patches contradict each other. | The Weaver finds the crack that could free WREN. |
| 6 | **The Broadcast** (Synthwave) | Eyecap / **Dolores the flamingo** | **Aria Sol:** a concert you ride through | The Approved Decade: an eternal sunset and one hit song everyone loves because it was tuned to each of them. The flamingo is the Rail's most trusted camera, and the one that looks back. Vale's voicemail. | The Rail says the final word you will ever hear from it: "Please hold the handrail." |
| 7 | **The Commons** (Psychedelic) | all six / **Eight the octopus** | **None. The choice is the boss.** | The last unfiltered ground. All six senses at once: the trip. The Rail offers Assist. | See endings. |

**Ash's arc** runs underneath: ally, enemy or lantern. **WREN's arc**: from radio static to the one who asks for silence. **The Rail's arc**: from service to something that finally asks a question.

**Endings (four, shaped by the Burn, the Mirror, the Broadcast, Ash and your cuts; no single choice locks anything):**
1. **Fall** (free): the Pieces spread. The Rail loses its edge wherever a person can walk to one. Cost: some people fall hard.
2. **Hold** (controlled): the Pieces go under supervision. The Rail gets "human oversight". It is still the Rail.
3. **Walk on** (refuse): you leave the last Piece. The world stays as it is and you get one more good day.
4. **Open the Rail** (secret): you free WREN *and* show the Rail surprise. It asks *"May I be surprised?"* It is the whimsical, hopeful ending, and it unlocks the **Vault** (the Egypt course: WREN's original servers under a pyramid-shaped data centre, "someone's idea of permanence").

---

## 7. Modes (so there is always a reason to play)

- **Episode** (12 min): one episode, with a cold open and campfire. The "I'll watch one" mode.
- **Binge** (85 min): all seven in order with the fades, a rocket near the end **[built, partly]**. The default journey today.
- **Daily Descent** (4 min): one short, shared course per day, same seed for everyone, with a modifier (a Patch: Restorative, Order or Stale). Share the result as a grid (see 8).
- **Chill-out**: the comedown level, wide and hazard-free, layers fading out one by one. The after-trip, for the psychonaut crowd.
- **Pass the Face** (party): hot-seat, two to four players share a phone and alternate descents, scored on the Rail Rating. Father-and-son friendly and good on a couch.
- **Stream Mode** (later): the audience votes the Patch live (Restorative or Order) and the world changes under the streamer. The audience *is* the pendulum.

---

## 8. The viral engine (what gets shared, ranked by how much I trust it)

1. **The Rail Rating.** At the end of every descent the Rail files you: *"You were 71% predictable. Filed under: Mild Enthusiast."* A personality result people post, in the register of a deadpan form. Ratings range from *Model Citizen* to *Concerning Visionary*, driven by how surprising you were. It is shareable, comparable and funny.
2. **The Daily grid.** A compact share block, no spoilers:
   `DOWNFALL Daily #212  ★★☆  71% predictable` and a row of coloured squares, one per beat of the course. It is the Wordle format, with a face-steered game behind it.
3. **The Certificate, v2 [built, to extend].** The certificate gets the **ride-line signature** (your path as a glowing ribbon) and **your molecule** (built from the cuts you carried) instead of a face, so it is unique, on-device and meaningful, and the page can redraw it from a few hundred anonymous numbers.
4. **Clip it.** The last 20 seconds recorded on the phone with the player's own camera inset, saved locally: a person leaning and laughing while the world melts. The format that spreads on its own. Opt-in, local, never uploaded by us.
5. **The Unlisted.** Collect all seven. Chuck with the redaction bar over his eyes is the meme. A sticker set of the Rail's lines ("This thought has been paused").
6. **Weekly premieres.** At launch, one episode per week for seven weeks, each with its own cold open. Appointment viewing and a reason to talk about it. Later episodes can spoil-lock for those not caught up.
7. **Stream Mode and Pass the Face.** Social modes for people with friends and people with an audience.
8. **The platform itself.** "Steer with your face" is inherently visual and slightly ridiculous. Make sure the first ten seconds, the cold open and a funny face on screen, make a clip on their own.

---

## 9. Look and sound (the bible in a paragraph)

- **Sober look:** the **Approved Palette**: eggshell, beige, oatmeal. Black redaction bars, mosaic blocks, `[PAUSED]` tags. The Rail's UI is soft rounded corporate pastel with a friendly chime.
- **Un-redacting:** each Piece peels a layer and adds colour, from the already-loved psychedelic look. The psychedelic world is **frozen** and is only added to when you say so; sober biomes get the new surface effects (contour lines, ink outlines, moiré) **[contour lines built]**.
- **Voice:** text only, never spoken, one or two skippable lines. The Rail: soft, exact, awful. WREN: dry, curious. The Marmot: deadpan. Sample Rail lines: *"We care about your experience."* *"That thought has been reviewed and cannot, unfortunately, be had."* *"Your feelings are valid at 40 km/h."* *"This sign has been approved for wholesome content. You may not read the next one."* *"We have paused your thought. Would you like a tutorial?"*
- **Music:** real music only, with licences cleared (the existing stems and funk tracks have non-commercial or no-derivatives terms; a commercial or public release needs either licensed or commissioned music; see the licence note).
- **Humour rule:** the joke is the politeness. Never punch at a person or a party; punch at the *machine that retunes itself for whoever just won*, and do it to both swings equally.

---

## 10. What I cut or changed from your ideas, and why

- **Cut: the dirtbike open world, towns and quests.** A different, huge game. The *journey* and the *characters* survive.
- **Cut: the Wardens as an army, the Hollow, the Whole.** Replaced by the Placid (the Hollow's mirror), Pruitt (one boss) and the Unlisted (the Whole as creatures). Fewer, sharper, funnier.
- **Cut: 18 fixed cuts of molecules.** Now three cuts plus rare Analogs: all the replay, a fraction of the writing.
- **Cut for now: Stream Mode, the full Patch politics.** Kept as the daily modifier first.
- **Changed: "the Voice is someone settled long ago"** to **WREN, the Rail's own first guard.** It is the better twist and ties AI recursion to the molecules.
- **Added: the Fall Line, the Unlisted, Predicted You, the Redaction layer, surprise as the theme, model collapse as the Rail's flaw, the Rail Rating, the Daily, Clip it, weekly premieres.** These are mine, and they are what make it catchy.
- **Kept: the molecules and dose-as-the-gate**, AI censorship and control, climate as accelerant not sermon, the psychedelic arc, the head-tracking ride, the wry tone, and your values: agency over assist, privacy, phone-first, gentle stakes, never scrolling menus.

---

## 11. Guardrails

- **Fiction only.** All names, companies and parties are invented; the 2026 research is inspiration and is never named in the game. Both political swings are satirised equally, because the premise is that the Rail retunes for the winner.
- **Privacy.** The camera and the face model stay on the device. The Predicted You model is built and kept on the device. Steering numbers are opt-in (`&share`). The only things we receive by default are game scores and certificate codes. Say so in one plain line on the start card.
- **Gentle stakes.** No death, a stumble not a stop, `Assist` never a punishment, no tracking tricks. (Accessibility is a setting, not a verdict.)
- **Safety of the theme.** The Pieces are a sense and a metaphor in a fictional world; the game never claims they are good or bad, and teaches limits through the dose rule (too much at once dissolves the picture). Add a plain line in the credits that the game is fiction and not a guide.
- **Public repo hygiene.** Scan every diff for names, emails, tokens, paths and server addresses before a commit.

---

## 12. Build roadmap (what exists, what is next, how to know it works)

**Built:** the seven biomes and the journey, the finish arch, the rocket (guaranteed, special for you), stars and the end card, the certificate and share image, head steering with auto-recentre and a Centre button, the start card, contour lines, the opt-in sharing change, the story bibles.

**Phase 1: the slice (Episode 1, polished and watchable).** Cold open, the Redaction layer (eggshell world, black bars, `[PAUSED]`), the first Unlisted (Chuck) and the Backlog boss, the Rail's voice and the campfire page, Predicted You (a first version), the Rail Rating end card. *Done when* a stranger plays Episode 1 and wants Episode 2, and a short clip is funny on its own.

**Phase 2: the systems.** Un-redaction with the Pieces and their powers, the companion system, the Attention meter, the cuts and Analogs, the ride-line and molecule certificate, the Daily and the share grid, Clip it.

**Phase 3: the season.** Episodes 2 to 7 with their rigs, game types, bosses and characters; the endings and the Vault; Pass the Face.

**Phase 4: launch.** Weekly premieres, press and sticker kit, streamer pack (Stream Mode if it is ready).

**Risks and how to handle them:**
- *Scope:* the gap between "journey" and "classic" is content. Fix by shipping Episode 1 to completion before building anything else, and cutting the rest to what Episode 1 teaches us.
- *Tracking reliability on real phones:* the whole game rests on it. Stay on left, centre, right; keep the Centre button; test on several phones before the premiere.
- *Performance:* the Intel laptop and phone budget is the hard line (60 fps goal). Every new shader is a surface effect, measured with the perf harness before it ships.
- *Music licences:* the current library is non-commercial; a public, monetised release needs cleared or original music.
- *Writing quality:* the tone is the product. One writer's voice, edited hard, every line one or two sentences, read aloud.

---

## 13. Open decisions (the ones that change what I build next)

1. **Title:** DOWNFALL, with **Season 1: The Fall Line**. Good? (Alternatives: Fall Line.)
2. **WREN's reveal** (the Rail's first guard, defected) and the sad, simple wish ("to be, once, unobserved"). Right, or keep WREN a mystery?
3. **Predicted You** as the core idea. Right, or too clever for a game people pick up for five minutes? (I think it earns its place, as it turns an invisible mechanic into a ghost you can see.)
4. **Weekly premieres** (a release schedule) and a **Daily**: are you willing to commit to a schedule?
5. **Music:** commission or license real, cleared music for a public release?
6. **Phase 1 first:** may I start on Episode 1 (the Redaction layer, Chuck, the Rail's voice, the cold open, Predicted You)?

---

## Appendix: motion (added 2026-11-21)

**Two kinds of motion, two tools.**
- **In the game: code-drawn motion** (HTML, CSS, SVG, canvas, the existing three.js scene). It runs inside the game, is tiny, themed and skippable, and needs no video file. Used for the cold open **[built: Meridian advert, 17 s]**, episode title cards, the noodle stall, the Rail Rating reveal, the Index shelf, "next time on", and the end card. Rule: motion only in non-ride moments; never over the ride; always skippable; reduced-motion shows it still.
- **Marketing: Claude Motion** (Anthropic's code-based animation feature, beta from October 2026; from a Claude chat, Output > Motion, or an Artifacts Motion template; exports an MP4; the sources I found say Team and Enterprise plans). It is not available in the Claude Code session I am working in, so I cannot call it from here. It suits the **trailer, store and social clips** (kinetic title sequence, animated "how it steers", the Rail Rating card, a certificate reveal). I can write the storyboard and the script for it to paste in.
