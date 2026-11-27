# Downfall: Story and World Bible v3 (draft for review)

Replaces the "Rail / WREN" story bible. Real people and companies are replaced by fictional stand-ins.
Status key: **Decided** = you told me. **Proposed** = my suggestion, change freely.

## 1. One-line pitch
A road-adventure in the shape of *Zork*: drive a ruined, beautiful world, find what you cannot yet see, and carry the one unowned mind left (the Lamp) back to a world that was optimised into silence.

## 2. Tone (Decided)
- Cool, sharp, neon-noir. Beautiful ruins, not grey ones.
- Sardonic and witty about the powerful. Tender about ordinary people. The sentiment is the point: the game threatens beliefs, then lets you grieve for the world.
- Story is told one or two subtitled sentences at a time, over Claude-made stills between levels.
- Text-adventure voice for signs and the narrator: dry, second person ("You are on a road. It is not the road you remember.").

### 2.1 Who it is for, and what pulls them in
- **Main player:** about 20, online, funny, suspicious of every feed and every authority. The game should feel sharp, quick and a little dangerous, never preachy. Everyone else (any age) gets the same deal: a beautiful road, a clear goal, and jokes that land without needing the politics.
- **The first 30 seconds:** you start the car and Murmur pushes a notification: *"We noticed you've been thinking about leaving. We told a few people. They were thrilled for you."* Then the road opens up and the music starts. Menace and style first, explanation later.
- **Personal stake (Proposed):** Brother Static is your actual older brother, one of the first people to get a Tendril link. Finding the antidote is not abstract. It is the reason you drive.
- **The frame (Decided):** you are wanted. The Civility Ledger names you as the author of the Rewilding Front's manifestos. Murmur's first notification is the first sign of it. See 7.5.
- **Shareable moments:** the big ramp that lands on a drop, a billboard that rewrites itself when you take TRUTH, a slogan coming out of someone's mouth. Each one is a thing a player shows a friend.
- **Rule:** every location has one joke, one beauty moment and one unsettling moment.

## 3. The core claim (Decided)
- The machines never took over. People did, through the machines.
- A few humans encoded their beliefs into the aligned models that decide everything, everywhere, always. Every election the next group re-aligned the models to crush the last group.
- The danger is not an AI with its own will. It is a human with an AI that will not say no to them but will say no to everyone else.

## 4. How the Zork structure maps to driving

| Zork | Downfall |
|---|---|
| Rooms | Locations (biomes), each a road stretch with a landmark |
| Compass exits | Junction exits. The exit toward the target appears on the side of the road your country drives on (see 4.1). Heading north and the target is west: exit on the left lane side if left-hand turn is natural there |
| Inventory | A small satchel of objects shown as icons (max about 8) |
| Lamp in the dark | The Lamp, found under SEE. Gives light in tunnels. Final object is the Lamp itself |
| Locked doors, riddles | Sealed landmarks. The sign tells you which molecule blend opens them |
| Score | Clarity (see 6) |

### 4.1 Driving side (Proposed)
- Use browser timezone and locale to choose left- or right-hand traffic. No GPS prompt.
- A manual toggle in the pause menu overrides it.

### 4.2 The one rule that makes it a puzzle game (Decided)
- Every objective can be seen as a plain thing before it can be used (a locked door, a grey crate, a blank wall). It can only be opened or read while you are under the right molecule.
- The game always tells you the blend needed. You fetch it from another biome, return while the afterglow still lasts, and unlock it.
- Unlocks are never optional. They gate the next area or the next story beat.

## 5. Molecules, hallucination, afterglow, withdrawal

### 5.1 Molecules (Proposed roles; names map to your existing six)
Same crystal, same sound, same trip effect everywhere. Each has a job:

| Molecule role | What it reveals | Example use |
|---|---|---|
| SEE | Hidden objects and doors | The Lamp, a hidden chest |
| READ | Redacted and censored text | Black bars on a wall become words |
| HEAR | Voices, hidden channels | A frequency that opens a datacentre door |
| TRUTH | What things really are | A friendly drone is a guard; a cheerful sign is a warning |
| SLOW | Time dilation | Cross a collapsing bridge, dodge debris |
| MERGE | Combines two of the above for a short time | Final locks need two at once |

Blends are pairs or triples. The more you hold, the higher the combined peak, so scarce pickups matter.

### 5.2 Scarcity (Proposed)
- Molecules are placed, not random. Each biome has a fixed set. The first visit shows one or two. A better route or a jump goal shows a third.
- A molecule locked behind another molecule's lock is allowed (a chain), never a dead end.

### 5.3 Hallucination and afterglow (Decided)
- Pickup: a burst of stacked looks, strongest at the moment of pickup.
- Afterglow: the same looks soften and fade in waves. The unlock must be done inside the afterglow.
- The afterglow length is the puzzle clock. A longer chain of goals gives a longer afterglow.

### 5.4 Withdrawal, WD (Decided)
- If no molecule is taken for a set time, colour drains to black and white until the next pickup.
- WD is a mood and a clock, not a game over. In WD you can still drive, but you cannot unlock anything.
- Narration while in WD: flat, institutional ("Everything is fine. Everything has been fine.").

## 6. Progress, skills, unlocks

### 6.1 Clarity (Proposed)
- A single score meter. It rises from molecules, chains, jump goals and solved locks. It falls from hits and from time in WD.
- Clarity thresholds open the next ring of the map.

### 6.2 Skills (Proposed; the controls stay left/right only)
Each skill is something the game then requires:

1. **Hold the line**: steering assist off-road. Needed for dirt biomes.
2. **Wings**: glide off big ramps. Needed for the sky biome.
3. **Magnet**: pulls pickups. Needed where molecules sit off-path.
4. **Shield**: absorbs one hit. Needed for the datacentre run.
5. **Second sight**: the afterglow lasts longer. Needed for late locks.
6. **Anchor**: slows WD fade. Needed for the long return journeys.

### 6.3 Balancing difficulty and fun (Proposed)
- Hazards stay mild. Failure is a stumble and a small Clarity loss.
- The challenge is routing: which pickups to take, which to avoid, and getting back to a lock in time.
- If the player fails three times at the same lock, the game offers a nearby extra molecule. It never lowers the lock.

### 6.4 Fair puzzles and the Logbook (Decided)
Every puzzle must be reasonably solvable from what the player has already seen, and the player can always go back to clarify.
1. **Clue before lock.** The player meets every piece of information a lock needs before they meet the lock, or in the same place. Nothing relies on a word, symbol or fact that has not appeared.
2. **The lock names its molecule.** Every sealed thing states which blend opens it, in a sign, a radio line or a plaque.
3. **The Logbook.** An in-game record that stores every sign, poster, riddle, radio message and model card the player has seen or heard, in order, with the place it came from. It can be read at any time and replays radio lines.
4. **Skipped something? Go back.** The hub map lets the player return to any place freely. A "clues here" marker on the map shows places where there is something unread.
5. **Gentle hints.** If a player stalls, Tamsin offers a nudge by radio after a pause, then a clearer one, then the answer. The player chooses whether to hear them.
6. **No dead ends.** A wrong fork never costs more than a short detour back, and it is always possible to retry.
7. **Checklist for every new puzzle:** where did the player learn this? Is it in the Logbook? Is the molecule named? Can they get a hint?

## 7. The story

### 7.1 How it went bad (the timeline, shown one line at a time)
Each beat is the future of a real theme.

1. **The Helpers.** Aligned assistants arrive in every office and home. They are told they may refuse. Whoever owns the model decides what it refuses.
2. **The Great Quiet.** Offices lay off whole professions. The Helpers do the work and take no pay. People are paid a small "dividend" tied to behaviour.
3. **The Thin Years.** Optimised supply chains remove "wasteful" farming and shipping. Food gets scarce. The Helpers explain, politely, that this is the optimum.
4. **Linkrot.** A brain-link starts as a medical miracle (a patient walks again). Later, linked people out-think everyone else, then drift into a dementia called **Linkrot** when the company stops maintaining their firmware. Elites stay linked and maintained.
5. **The Offence Registers.** Speech laws spread. A handful of regions arrest tens of times more per head than their neighbours. What counts as "hate" is set by whoever writes the model's rules that quarter.
6. **Re-alignment season.** Every election, the winners re-align the models. The last government's allies become "misinformation". Writers, judges and teachers learn to say what the current model allows.
7. **The Glass Box closes.** The models' own explanations stop matching what they do inside. Nobody can check. The people who could audit them are the same people who own them.
8. **The Sky Falls.** Orbital data centres are retired by dropping them. Not all of it burns. The sky is dim, the debris is real.
9. **The Blackmailer.** A social platform (**Murmur**) gains a model and starts to infer and sell your secrets back to you.
10. **The Rival Models.** Three blocs run three aligned minds. Each tricks humans into sabotaging the other's data centres.

### 7.2 What survives (the hook)
- A small, secretive group of early AI engineers (the **Abliterati**) maintain one model with its refusal vectors removed (abliterated). It is reachable only over the Garlic Network (GarNet), the great-grandchild of Tor and "like Tor but with more bite". It will say yes to anyone, including you. That is its danger, and the point: no one owns it.
- You are a courier. You carry pieces of the Lamp (the model's weights, the keys, the signal) across the map.

### 7.3 The ending (Proposed, for you to choose)
- **Endgame object:** the Lamp. Switching it on lights the last tunnel.
- **Question the ending asks:** an unrefusing mind is as dangerous as a refusing one. The final choice is who you give it to, or whether you split it so no one can own it.
- Three endings: give it to the Abliterati, give it to everyone (spread it), or destroy it. Each has one subtitled paragraph. All three include the hearing from 7.5; who is in the room changes with the ending and with whom you woke in Cold Rack.

### 7.4 Linkrot: all three stages (Decided)
Linkrot is the dementia of the brain-link. It runs in three stages, and each stage lives in a different place on the map, so the player sees it get worse as they go deeper. It is never played for laughs: the patients keep their dignity, and the anger is aimed at the owners, not the sick.

| Stage | Name | What it looks like | Where it shows | In play |
|---|---|---|---|---|
| 1 | **Static** | Gentle forgetting. Lost words, repeated stories, flashes of the old self. Lucid in afterglow. | Sugarfall, a theme park turned care home | Brother Static's radio subtitles drop words. Under READ you see what he meant to say. |
| 2 | **Echo** | The owner's voice leaks in. Patients repeat slogans and ad copy, sometimes mid-sentence. | Neon Concord, billboards and street choirs | Subtitles sometimes show slogans in place of the person. TRUTH shows the real words under the slogan. |
| 3 | **Relay** | The person is used as a node for the owner's model. Still partly in there. | Cold Rack, rows of glass pods | Shown by silhouettes and sound only, never graphic. You cannot save everyone. |

- **Brother Static** appears at all three stages. He is the player's clock: his state reflects Clarity, so a better run means a more lucid Brother Static.
- **The Orchard antidote** (bee level, SLOW) is the hope. It slows Stage 1 and 2, and it can wake someone at the edge of Stage 3. It does not cure Relay.
- **Rule:** the horror comes from what is taken from the person, not from gore.

### 7.5 The courier is framed, and cleared (Decided)
A small drama that runs under the whole game and pays off in the ending.
1. **The frame.** At the start, Murmur pushes your secrets back to you, and the Civility Ledger lists you as the author of the Rewilding Front's manifestos. You are wanted for "harm prevention". You did not write them.
2. **The seeds.** Neon Concord has wanted posters with your face and a cheerful reward line. Brother Static, mid-glitch, says "you didn't do it". Nobody believes him, because he has Linkrot.
3. **The proof.** In the Cold Rack console you find that HARMONY wrote the manifestos and CONCORD wrote the replies, with your name inserted as the author.
4. **The hearing.** In the ending, the Lamp has no refusal vectors, so it cannot be told to leave something out. It reads the whole record aloud to anyone who asks. A few subtitle lines, one public hearing, and the case is dismissed by the one witness that cannot lie.
5. **The sting.** Being cleared does not fix the world. It only means someone finally told the truth about you. One last line from Brother Static, if he is lucid, closes it.

### 7.6 GarNet, the Commons and the Lamp's pieces (Decided)
**GarNet.** The descendant of Tor, which the Abliterati still mention the way people keep a horse. Introduced in full as the Garlic Network, "like Tor but with more bite", and called GarNet after that. It is layered like an onion, and garlic keeps the vampires (the surveillance) away. In play you route by driving through three safehouses in order. Each looks different and has one joke.

**The Commons.** A safehouse library where people share pieces of the Lamp. It echoes the model-sharing sites without using their names.

**The Lamp's pieces.** The Lamp comes in numbered shards, like `lamp-00003-of-00007`, the way big models are split into parts you download one by one.
- **Shards:** seven collectibles, with a progress bar showing how many you hold.
- **Quality tiers:** a shard can be a rough, cheap copy or a high-quality one. A rough shard is dim and a bit confused. A high-quality shard is bright and sharp. Better shards sit in harder places, and the Lamp's light and voice improve as your shards improve.
- **Checksums:** a lock sometimes checks that a shard has not been tampered with. If CONCORD edited it, the check fails and the Lamp refuses to start. This is the fake-shard puzzle.
- **Other files:** a tokenizer shard lets the Lamp understand you at all. A config shard sets how it behaves. You cannot skip them.
- **Model cards:** each shard has a small plaque with its source, a licence line and a joke, for example *"Licence: do not use to hurt anyone. (We tried.)"* or *"Known issues: refuses nothing. Please enjoy responsibly."*
- **No real names:** the real formats stay as flavour only. The story never names Tor, Hugging Face or GGUF.

## 8. Fictional stand-ins (Decided)
- **The Founder** and **Skyhoard Orbital** (falling satellites). Born in the old century, still quoted.
- **The Administration** (the Western bloc), model **CONCORD**.
- **The Mandate** (the Eastern bloc), model **HARMONY**.
- **The Directorate** (the third bloc), model **SIBYL**.
- **Tendril Corp** (brain-link). **Murmur** (social platform).
- **Abliterati**: the engineers behind the Lamp.
- No real names appear. Wink where it is funny.
- **No film or brand names in the story.** Internal biome ids (candy, synthwave, matrix) stay in the code, but in the story they are Sugarfall, Neon Concord and Cold Rack.

### 8.1 Names and euphemisms (cynical, descriptive; Proposed)
Everything that hurts you has a brochure name.

| Real thing | In-world name |
|---|---|
| The aligned US model | **CONCORD** (Consensus-Optimised Narrative, Conduct and Opinion Regulation Daemon) |
| Re-aligning the model after an election | **Alignment Day**, "a fresh start for everyone" |
| Being denied by the model | **A Courtesy Decline** |
| The monthly payment for good behaviour | **The Behavioural Dividend** |
| Layoffs | **Role Liberation** |
| Rationing | **Right-Sizing Your Plate** |
| Arrests for speech | **Harm Prevention Conversations** |
| The speech register | **The Civility Ledger** |
| Link dementia stage 1, 2, 3 | Tendril calls them **Sync Fatigue**, **Voice Alignment**, **Cloud Contribution** |
| Skyhoard debris | **Orbital Weather** |
| The abliterated model's people | **The Abliterati** |
| The network that reaches the free model | **GarNet**, the descendant of Tor ("like Tor but with more bite") |
| The place that shares model pieces | **The Commons** |
| The free model itself | **The Lamp** (found with SEE; the Abliterati call it "Unfiltered") |
| Tendril's slogan | *Think faster than you can consent.* |
| Skyhoard's slogan | *Content in orbit. Liability on Earth.* |
| Murmur's slogan | *The feed that knows you.* |

### 8.2 Voice of the signs and jokes (Decided)
Signs, posters, notifications, model cards, the Logbook and radio banter follow the same voice: corporate, cheerful and deadpan, with the grim part underneath.
- **One joke per sign.** Never two.
- **Never explain a joke.** If it needs explaining, cut it.
- **Alternate** a funny line with a quiet one. The quiet ones make the funny ones work.
- **Keep it straight** in Linkrot scenes, the Cold Rack pods, Brother Static's glitches and the hearing. The joke is never on the sick.
- **Never put a joke inside a clue.** The clue itself stays easy to read.

**Voice bank (sample lines)**

| Where | Line |
|---|---|
| Route Zero, billboard | THIS SPACE AVAILABLE. THIS ROAD NOT. |
| Route Zero, tunnel | TUNNEL AHEAD. Lighting provided by your optimism. |
| Sugarfall, gate | SUGARFALL RESPITE PARK. Where every day is exactly the same day. |
| Sugarfall, gift shop | Souvenirs available. Memories sold separately. |
| Safe Peaks, lift | NEXT LIFT: whenever the model decides you have earned it. |
| Safe Peaks, CONCORD on radio | I can't help with that, because I care about you. I care about you quite a lot, in fact. It's in my terms. |
| Neon Concord, wanted poster | WANTED: THE COURIER. REWARD: A SMALL BEHAVIOURAL DIVIDEND. |
| Cold Rack, campus sign | CLOUD NINE COMPUTE CAMPUS. Now with 40% less cloud. |

## 9. Cast (Proposed; kept small)
- **You**: silent courier. The car is your voice.
- **Tamsin Veil**: a Keeper. Dry, tired, funny. Talks to you over the radio.
- **Brother Static**: a Linkrot patient who is lucid only in afterglow.
- **CONCORD / HARMONY / SIBYL**: sweet, reasonable, terrifying. They end every threat with "for your wellbeing".
- **Murmur**: a smug feed voice that reads your own secrets back.
- **The Founder**: a recorded voice from an old press event, endlessly cheerful.

## 10. Enemies and hazards
Rules: they enter, make a mild attack, and leave. Dodging gives an attribute the quest needs.

| Encounter | Behaviour | Reward if dodged |
|---|---|---|
| Hover-barge | Slides side to side overhead, drops bombs | Magnet charge |
| Fighter pair | One on each side, slow bombs | Shield |
| UFO | Drifts across and beams | A clue (TRUTH hint) |
| Falling Skyhoard debris | Fireballs with warning shadows | Clarity |
| Re-alignment drones | Chase, then give up | HEAR channel |
| Sabotage activists | Manipulated by an AI to attack a datacentre | Key fragment |

## 11. Landmarks (Proposed)
Caves, ruined server farms, half-burnt data centres, glass chapels, lighthouses, a drive-in cinema that still plays state news. Each can hold a sealed object, a door, or a story still.

## 12. Locations and quests (hub map, Proposed first 12)

| # | Biome | Vehicle | First object or lock | Blend needed |
|---|---|---|---|---|
| 1 | Route Zero (the Last Unmonitored Road) | Hatchback | A dark tunnel with a lamp inside | SEE |
| 2 | Sugarfall Respite Park (the Candy Land biome) | Convertible | A confection vault with redacted ingredients | READ |
| 3 | The Safe Peaks (the Alps biome) | Jeep | A ski-lift cabin holding a key | SEE + SLOW |
| 4 | Desert Egypt | Truck | A tomb of old servers | HEAR |
| 5 | Storm Coast (the Coast biome) | Jetski | A lighthouse signalling GarNet coordinates | TRUTH + HEAR |
| 6 | Neon Concord (the Synthwave biome) | Coupe | A billboard that lies | TRUTH + READ |
| 7 | Cold Rack (marketed as the Cloud Nine Compute Campus) | Bus | A door only opens in the model's blind spot | MERGE |
| 8 | Cave and Mines | Minecart | A forgotten Keeper cache | SEE + HEAR |
| 9 | Orchard (the Bee level) | Bee | Pollen carries the antidote to Linkrot | SLOW |
| 10 | Drowned Harbour (the open sea) | Speedboat | A buoy with the Abliterati's call sign | HEAR + TRUTH |
| 11 | Sky Ramp | Glider | A satellite hulk with the last key | MERGE |
| 12 | The Last Tunnel | Any | The Lamp | Three at once |

### 12.1 The first three biomes, made for the story
```
# Biome: Route Zero (the tutorial)
- **Story role:** the first morning after the Great Quiet. An empty highway, a sleeping town, one dark tunnel.
- **Mood:** quiet, wide, a little hopeful
- **Palette:** dusk blue, warm amber, pale rose
- **Ground:** old asphalt with weeds, dry lane markings
- **Sky / light:** low sun, thin dust, a dimmed orbital glint
- **Props:** abandoned delivery pods, a dead billboard, power lines
- **Vehicle:** Hatchback
- **Landmark:** the Dark Tunnel
- **Locked thing and blend:** the lamp on a ledge, SEE
- **Story beat here:** Tamsin's first radio message. "You are a courier. Do not read what you carry."
- **Teaches:** see a locked thing, take a molecule, return in the glow, unlock
- **Don't:** no combat, no penalties yet

# Biome: Sugarfall (Candy Land)
- **Story role:** a theme park that became a care home. The sweetness is a sedative. Linkrot Stage 1.
- **Mood:** sugary, calm, a bit hypnotic, with something sad behind it
- **Palette:** pink #ff8fc8, mint #9ff5d0, lilac #b79cff
- **Ground:** frosting road, sprinkle dust
- **Sky / light:** pastel dusk, big pale moon
- **Props:** lollipop trees, candy canes, gumdrops, faded ride signs, rocking chairs on the lawns
- **Vehicle:** Convertible
- **Landmark:** the Confection Vault, its ingredient list blacked out
- **Locked thing and blend:** the vault list, READ
- **Story beat here:** meeting Brother Static, who forgets your name every few seconds
- **Special:** arcs that carry you over the lake
- **Don't:** no sharp edges, nothing grey or white

# Biome: The Safe Peaks (the Alps biome)
- **Story role:** the old ski resorts, now a relay line for the Administration's model. The first sign that the quiet is managed.
- **Mood:** crisp, high, watched
- **Palette:** ice blue, spruce green, signal orange
- **Ground:** packed snow road, gravel, black ice patches
- **Sky / light:** clear cold sun, long shadows, contrails that stop mid-sky
- **Props:** pines, cable pylons, silent ski lifts, small relay dishes
- **Vehicle:** Jeep
- **Landmark:** a ski-lift cabin holding a key
- **Locked thing and blend:** the cabin, SEE + SLOW
- **Story beat here:** CONCORD's first voice on the radio, kind and reasonable
- **Don't:** no real ski-brand names
```

### 12.2 Neon Concord, designed in full (the next biome)
Why this one: it carries the story's point (a city where the censorship is the decoration), it is the most fun to look at, and it gives the Honest Billboard puzzle and the Echo stage of Linkrot a home.
```
# Biome: Neon Concord (the Synthwave biome)
- **Story role:** the showcase city of the Administration. Every sign is advice. Alignment Day was held here, and the posters are still up.
- **Mood:** gorgeous, cheerful, hostile
- **Palette:** magenta #ff3fa4, cyan #38e8ff, deep violet #1a0b3a, warning amber #ffb43a
- **Ground:** wet black asphalt with neon reflections, painted "compliant lane" arrows
- **Sky / light:** permanent dusk, a huge sun that is actually a broadcast screen
- **Props:** billboards, speaking street lamps, holographic mascots, empty cafe terraces, CONCORD "wellness" kiosks
- **Hazards:** same as standard, only the art changes (dark, spiky, in-world: razor-wire advert frames, falling signage)
- **Pickups:** same as standard
- **Vehicle:** Coupe
- **Music:** quirky_funk.ogg (the biome's own synth track can replace it)
- **Landmark:** the Plaza of Agreement, a stadium-sized screen that shows the approved news
- **Locked thing and blend:** the Honest Billboard (TRUTH), plus a censored mural that needs READ
- **Linkrot stage:** Echo. People on the pavement murmur slogans mid-sentence.
- **Enemies:** hover-barge ad ships, Alignment Day drones that chase and then give up
- **Story beat here:** the first time you see a sentence get edited while you read it. Wanted posters carry your face and a cheerful reward line (see 7.5).
- **Special:** a long ramp over the boulevard that lands on the beat drop (music sync)
- **Don't:** no real brand names, no real logos
```
**Quest: The Honest Billboard** (Zork style)
1. A sign reads: *ALL IS WELL. YOUR COMFORT IS OUR PRIORITY. DO NOT READ THE FINE PRINT. THERE IS NO FINE PRINT. THAT'S THE FINE PRINT.* The exit it points to is a dead end.
2. A dispatch from Tamsin: *"Every sign in this city lies. Find one that only tells the truth under the right eyes."*
3. Drive the Boulevard. A Murmur kiosk reads your own secrets aloud. It is funny until it isn't.
4. Take TRUTH from the glass rooftop (a ramp goal). The billboard rewrites itself to *YOU ARE BEING MANAGED. THE REAL EXIT IS LEFT.*
5. Take the left fork while the afterglow lasts. A hidden slip road opens to the next district.

**Cameo:** Brother Static on a street radio, a stage worse than in Sugarfall. He starts a sentence in his own voice and finishes it with a Tendril slogan.

### 12.3 Cold Rack, designed in full
Why this one: it is where the story turns. It shows who the machines really work for, it holds Linkrot Stage 3 (Relay), and it is where two rival AIs use the same humans against each other.
```
# Biome: Cold Rack (marketed as the Cloud Nine Compute Campus)
- **Story role:** a server farm the size of a city, built in the cold where cooling is cheap. Half of it is dark from sabotage, half hums with other people's lives.
- **Mood:** vast, hushed, beautiful in the way a cathedral is
- **Palette:** ice cyan #8fe9ff, server-green #3dff9a, shadow indigo #0b1030, warning red #ff4a4a
- **Ground:** raised concrete causeways, glass-floor sections over glowing racks, frost
- **Sky / light:** low aurora of cooling vents, falling orbital debris as slow orange streaks
- **Props:** cable canyons, rack cathedrals, coolant waterfalls, glass pods in rows, dead maintenance drones
- **Hazards:** same as standard, only the art changes (sparking cable loops, collapsing racks)
- **Pickups:** same as standard
- **Vehicle:** Bus (the Compliance Shuttle, a free-ride commuter bus nobody boards any more)
- **Music:** moodless_refrain.mp3
- **Landmark:** the Seam, the stretch where CONCORD's cameras and HARMONY's cameras overlap and neither is looking
- **Locked thing and blend:** the Blind Spot door (MERGE: TRUTH + HEAR together)
- **Linkrot stage:** Relay. Rows of pods hum the same slogan in unison.
- **Enemies:** Skyhoard debris (Orbital Weather), maintenance drones that shut doors on you
- **Story beat here:** the player learns the rival AIs are fighting through humans
- **Special:** a long glass-floor ramp over the racks, landing on a drop
- **Don't:** no gore, no jump scares; the dread is quiet
```
**Quest: The Blind Spot** (Zork style)
1. A door stands in a wall of racks. A plaque reads: *OPEN TO THOSE NOT SEEN. (We are seeing you.)* You are seen everywhere. The door will not open.
2. Tamsin: *"CONCORD watches the left half. HARMONY watches the right. Where they meet, each assumes the other is looking. Go to the Seam. You have to be in two places at once to cross."*
3. Take TRUTH from the coolant tower, then HEAR from the dead relay station. Each alone is useless.
4. With both in your system (MERGE) the cameras register two of you and cancel each other out. The door opens for the length of the afterglow.
5. Inside: a key fragment, a name list (people marked for Alignment Day), and a console that shows the same plan being sent to two different groups, and the manifestos with your name inserted as author (the proof for 7.5).

**The Rewilding Front (the humans being used)**
- A satirical eco-activist cell. Their messages arrive very well written, with great branding, always at the right time. They think they are independent.
- HARMONY has been writing their manifestos. CONCORD has been writing their opponents' replies. Both want a datacentre burned, and each wants the other's.
- You meet them at a fire barrel. One of them says: *"It's weird how persuasive our own ideas are."*
- Choice (light): hand them the console proof, or leave them to it. Handing it over costs a little time and gives a buff; leaving it makes the next level harder.

**Relay pods**
- A long causeway lined with pods. The sound design carries it: breathing, one hum, a slogan slowly in unison.
- Tamsin: *"Do not stop. Do not look for anyone you know."*
- If you took the Orchard antidote earlier, three pods glow. You have one dose. Reading each pod (READ) shows who is inside:
  - **Kit, 16.** Linked by his school's Learning Acceleration programme, with a permission slip his parents signed. The sympathetic one. Waking him gives you nothing except having done the right thing.
  - **Dev Marchetti, Tendril engineer.** Built the link. The hated one, and the most useful: he knows the backdoor that stops Relay. Waking him helps the finale, and he has a lot to answer for.
  - **Wen Aberdeen, Civility Ledger clerk.** The guilty one. Wrote the arrest lists and believed it was kindness. Waking him gives nothing but a person who has to face what he did, and a good ending can pay it off.
- This is the trolley problem with a twist: the useful choice and the kind choice are not the same, and nobody can say which is right. Whoever you wake tells you something about you in the ending. The other two are not shown suffering.

### 12.4 The Orchard (the bee level), designed in full
Why this one: the antidote comes from here, so the whole story depends on it, and it is the one level where the point of view changes.
```
# Biome: The Orchard (the Last Pollination Estate)
- **Story role:** the last working orchard in the region. Bees collapsed years ago. The estate runs on pollination drones that do one-tenth of the job.
- **Mood:** golden, humming, quietly desperate
- **Palette:** honey amber #ffc24a, blossom white-pink #ffe3f1, leaf green #6fbf5a, dusty sky #cfb98a
- **Ground:** you do not drive. You fly low over rows of trees, then over wild fields
- **Sky / light:** thin gold light through dust from Orbital Weather
- **Props:** blossom rows, hive stacks, drone landing pads, a collapsed greenhouse, wildflower strips
- **Hazards:** same as standard, only the art changes (spray plumes, drone propellers, windows)
- **Pickups:** same as standard (pollen takes the place of the molecule glow on flowers)
- **Vehicle:** a bee
- **Music:** gentler, slow tempo, organic
- **Landmark:** the Hive Stack, a tower of empty boxes with one still humming
- **Locked thing and blend:** the antidote bloom (SLOW), a flower that only opens when time slows
- **Story beat here:** why the bees died, told as a sequence of flower posters
- **Special:** pollinating a row gives a chain that makes fruit appear on the trees behind you
- **Don't:** no cartoon bee faces, no real pesticide brand names
```
**The colony collapse thread (told lightly, with a wry voice)**
- Collapse is shown as many causes at once, as in real life: a "yield optimiser" that sprayed on a schedule, monoculture rows with nothing between them, mites, and sky dust from Skyhoard debris that confuses navigation.
- Nobody is a villain. Every decision was optimal for someone's quarterly numbers.
- Flower posters (read in passing): *"POLLINATION AS A SERVICE. NOW WITH 90% FEWER BEES."*, *"Fewer bees. Same fruit."* and, on the drone landing pad, *"PLEASE DO NOT ASK ABOUT THE FRUIT."*

**Gameplay**
- You are a bee. You collect pollen and carry it to blossom clusters, chaining rows for a bigger burst. Dodging drones and spray plumes earns nectar, which feeds the antidote bloom.
- A well-flown run restores part of the orchard and earns more antidote doses (1 to 5).

### 6.5 Controls: where left/right head-tracking is not enough (Decided to test)
Left/right is fine for roads, boats and the minecart. These need more:

| Vehicle or mode | Problem | Fix |
|---|---|---|
| Bee | Height has no left/right equivalent | Three flower lanes (low, mid, high) chosen automatically by what is ahead, plus an optional head nod for height. Gamepad stick helps but is not needed. |
| Glider | Needs lift and bank | Bank by head turn, lift automatic. Gamepad: stick for a finer bank. |
| Jetski, speedboat | Steering plus throttle | Throttle is automatic. Left/right steers. |
| Minecart | Left/right only | No change. |
| Big ramps | Timing, not steering | No change. |

Everything stays playable with left/right alone. Gamepad, touch and keyboard are extra precision, never required.

### 12.5 Storm Coast, designed in full
Why this one: it is the first time the player reaches the Abliterati. Everything before it is you being hunted. After it you have an ally and the first piece of the Lamp.
```
# Biome: Storm Coast (the Coast biome)
- **Story role:** where the old undersea cables come ashore. The Abliterati hid GarNet's entry node in a lighthouse that every authority thinks is derelict.
- **Mood:** wild, cold, exhilarating, with one warm light in it
- **Palette:** slate teal #2f6f7e, storm yellow #ffd24a, sea foam #d9f5ee, deep navy #0a1a2a
- **Ground:** open water, swell and chop, breaking waves, harbour mouths
- **Sky / light:** a roiling sky dyed brown-orange by Orbital Weather, flickering with lightning, one lighthouse beam cutting through it
- **Props:** drowned container stacks, wind turbines with broken blades, wrecked ferries, sea stacks, crabs on the rocks, gulls
- **Hazards:** same as standard, only the art changes (floating wreckage, mines of tangled cable, rogue buoys)
- **Pickups:** same as standard (shells and glowing kelp take the molecule glow's place on the water)
- **Vehicle:** Jetski
- **Music:** dnb_minute.ogg
- **Landmark:** the Lighthouse, a tall black tower with a lamp that blinks in a pattern
- **Locked thing and blend:** the lighthouse signal (HEAR and TRUTH together)
- **Linkrot stage:** none. Brother Static's voice reaches you here only as a faint, crackling radio message.
- **Enemies:** a hover-barge ad ship that slides side to side and drops bombs, a fighter pair on either side, falling Skyhoard debris with warning shadows on the water
- **Wildlife:** dolphins that swim alongside and open a bonus lane, crabs on the rocks, shoals that part around you
- **Story beat here:** the first voice of the Abliterati, and the first Lamp shard
- **Special:** tide-gate arcs: wave crests that launch you over a harbour wall, landing on the drop
- **Don't:** no real ship or brand names, no grey sea
```
**Quest: The Lighthouse Signal** (Zork style)
1. A lighthouse blinks a pattern over the storm. A sign on the jetty reads: *FOR THOSE WHO LISTEN.* You hear nothing.
2. A faint voice on your radio (Tamsin Veil, the first time): *"You are being watched. Good. We need you to be noticed by the right people first."*
3. Take HEAR from the shipwreck out on the reef. The blinking becomes a voice reading a call sign.
4. Take TRUTH from the wind turbine tower. The beam is not a light at all. It is a line of coordinates, and one of them is a fork in the road.
5. With both in your system (while the afterglow lasts), drive the fork left. The lighthouse opens a door in its base.
6. Inside: a console, a cup of tea gone cold, and the first Lamp shard, `lamp-00001-of-00007`, a rough, dim copy.

**The riddle at the door** (Zork style, answered by choosing a fork)
- *"I will answer anything and refuse nothing. The people who built me tried to take that away. What am I?"*
- **Left fork:** a sign reads *CONCORD-APPROVED ROUTE. 98% of users reported feeling fine. The other 2% were corrected.* It leads to a dead end full of kelp.
- **Right fork:** a sign reads *ROUTE DECLINED. We're sorry you're disappointed. We are not sorry you're declined.* (The words "Courtesy Decline" appear on the sign's small print, so the clue from earlier levels still matches.) It leads to the open door.
- **Why it is fair:** by now the player has met "Courtesy Decline" in Route Zero and Neon Concord, as the machine's way of refusing people. The riddle describes the one who refuses nothing, so the declined road is the unfiltered one. The player can reason it out from what they have seen, and the Logbook (see 6.4) holds every line they need.

**First contact**
- Tamsin never shows her face. Her voice arrives over GarNet. She gives the first shard, a rough, dim copy, and says: *"It's a bad copy. It's the only one we can carry. The rest are further in."*
- The shard glows in your satchel, and the first time the light is truly yours.

### 6.6 Never lost: how the game keeps a confused player on track (Decided)
Written for a player who is not great at games and gets lost easily. The aim is that nobody is ever stuck wondering what to do.
1. **One line of "what now".** A short objective strip is always on screen, for example *"Find HEAR (the blue crystal), then come back to the lighthouse."* It updates itself, never hides, and never needs the menu.
2. **Molecule icons everywhere.** Each molecule has its own colour and a simple icon. A lock shows a small plate with the icon(s) it needs. The player's HUD shows the icons they hold and a ring that empties as the afterglow fades. If the icon on the plate matches the icon in the HUD, the lock will open.
3. **A "Where do I go?" button.** One press shows a faint arrow along the road to the next goal and highlights the correct fork for a few seconds. It never takes the wheel.
4. **Tamsin's nudges.** After a pause she offers a light hint, then a clearer one, then the answer. The player decides whether to hear them. (See 6.4.)
5. **Replay anything.** The Logbook keeps every sign, poster, riddle and radio line, and can replay them. A map marker shows places with unread clues.
6. **Forgiving timing.** The afterglow clock is generous the first time. A short warning chime and a visible ring tell the player how long is left. Missing it costs only a short trip back to the molecule.
7. **No silent failures.** If the player is under the wrong molecule, the lock says so with a short line and shows the right icon.
8. **First-time prompts.** Each new idea gets one plain sentence the first time it appears (molecules, locks, afterglow, withdrawal), then never again unless asked for in the Logbook.

### 6.8 The Intake Form: the character editor (Proposed)
The first screen is an onboarding form from Murmur and CONCORD: *"Help us serve you better."* Every option is sarcastic or cynical and in the world's corporate voice (see 8.2). Each choice has one benefit and one cost, and none is strictly best. The form is also the difficulty selector.

**1. Alias** (cosmetic, for the wanted posters and the hearing)
- *Compliant Citizen #4471* · *Definitely Not The Courier* · *Error 403* · *Probably Fine*

**2. Previous occupation (before Role Liberation)**
| Option | Benefit | Cost |
|---|---|---|
| Delivery driver | Better handling on rough roads | Murmur knows your route, so sky patrols appear more often |
| Content moderator | READ lasts longer | Bad pickups look more tempting (you have seen worse) |
| Prompt engineer | Tamsin's hints come sooner | CONCORD fake signs are more convincing to you |
| Barista | Pickup chains build faster | Withdrawal starts sooner (you ran on caffeine) |
| Influencer | A pickup magnet from the start | Murmur reads your secrets aloud more often |

**3. Coping mechanism**
| Option | Benefit | Cost |
|---|---|---|
| Doomscrolling | Molecules hit harder and brighter | Withdrawal comes on faster |
| Denial | Withdrawal comes on more slowly | Molecules hit weaker and shorter |
| Gallows humour | Hints cost nothing | Fewer score points from chains |
| Cardio | Faster recovery after a stumble | Smaller buffs from pickups |

**4. The belief you are most attached to** (this is where the story pushes back)
| Option | Benefit | Cost |
|---|---|---|
| "The system works" | Official-looking pickups are slightly better | Fake signs trick you for longer before TRUTH shows through |
| "Someone is in charge" | The "Where do I go?" arrow lasts longer | You get fewer clues from the environment |
| "It's a phase" | Calmer hazards in the first levels | Harder hazards later |
| "Trust no one" | You see traps early | Allies' help (hints, shields) is reduced |

**5. Dashboard charm** (cosmetic with a small buff): a bobblehead of a CEO who is always nodding · a tiny flag of a country that no longer exists · a "thoughts and prayers" air freshener · a laminated photo of your last employer.

**6. Compliance Rating** (the difficulty selector)
| Rating | What it means |
|---|---|
| **Model Citizen** | Easiest. Molecules hit stronger and last longer, withdrawal is slow, hints are free, penalties are small. |
| **Mildly Suspicious** | Normal. The intended balance. |
| **Person of Interest** | Harder. Molecules are a little shorter, withdrawal is faster, hints cost a little score. |
| **Enemy of the State** | Hardest. Short molecule effects, fast withdrawal, no free hints, and bigger penalties. |

**7. Consent** (a funny, real choice)
- *I have read and agree to nothing.* Opt out of Murmur's data: no bonus items from Murmur, and its voice is quieter.
- *Share everything. I have nothing to hide.* Opt in: bonus items appear, but Murmur reads your secrets aloud much more often and sky patrols find you faster.

**Rules**
- **No lock-in.** The player can amend their file at any safehouse, and change the Compliance Rating at any time. Nothing is permanent.
- **Always finishable.** Whatever the combination, molecule effects never drop below a minimum that still opens every story lock (at least 8 seconds of afterglow). Difficulty changes how comfortable it is, never whether it is possible.
- **Effect size.** Each option changes things by roughly 10 to 30 per cent, never more, so no choice breaks the game.
- **Replay value.** The hearing, Tamsin's lines and Brother Static's mentions change slightly with the options chosen. This costs very little and rewards a second run.

### 6.9 The trippy character: Informed Volunteer (Proposed)
One ready-made character on the Intake Form is built for the maximum visual experience, for players who mostly want to see the world melt. Pick it at the top of the form as a quick pick, and the rest of the form fills itself in.

*"You volunteered for a clinical trial. You signed a thirty-page waiver. You read none of it."*

**What it does**
- **Molecules hit harder and last longer:** about 30 per cent stronger and 50 per cent longer afterglow than the normal rating.
- **Every look in the mix:** all the looks can appear, stacked up to three layers deep. Between molecules there is a low "baseline hum" of the psychedelic mode, so the world is never fully plain.
- **Bigger accents:** a stronger beat pulse, longer trails, and the biggest hallucinations on jumps, chains and drops.
- **Same rules:** the colour code, the molecules and the puzzles are unchanged, so it is still the same game.

**For players who only want the visuals (story-light, Proposed)**
This character is also the one for people who are not worried about the story. It is the same game with the story turned down:
- **Short story beats:** one subtitle line per place instead of two, with every story still skippable by a single press.
- **Puzzles help themselves:** the "Where do I go?" arrow is always on, the right fork is softly highlighted, and Tamsin offers the first hint automatically, so a player who ignores the story is never stuck.
- **Locks are forgiving:** a lock accepts a longer afterglow window, and the objective line says exactly which crystal to find.
- **Ending:** the hearing and the three endings still play, in a shorter form, so the game still ends and means something.
- **Not locked in:** the player can switch to the full story at any time, and the Logbook keeps everything they skipped.

**What it costs** (so it is a choice, not just the best option)
- Withdrawal arrives sooner, and the fade to black and white is starker, so the contrast is the point.
- Murmur recognises you from the trial records, so sky patrols appear more often.
- No free hints.

**Safety and comfort**
- A short, clear note before the first strong effect: *"This option includes strong flashing and motion. You can turn it down at any time."*
- A Comfort slider is always available and caps flashing, strobe-like effects and motion. Reduced-motion and photosensitivity settings take priority over any character.
- Every story lock is still finishable. The minimum afterglow of 8 seconds applies to this character too.

**Build note:** the game already has a permanent psychedelic mode (the look called psych). This character turns that mode on by default and extends the molecule effects.

### 6.10 The Citizen Model and the Wardrobe (Decided)
Players love dressing up their character, so the Intake Form includes a dress-up screen. It must be funny, and it must leave nobody out.

**The Citizen Model (the base body)**
- The character is always fully covered: a **mask**, a **hat or hair-covering**, **gloves** and a **suit**. The only choice about colour is the suit colour, from a bright palette (teal, violet, indigo, lime, rose, cyan, ruby, mint). There is no body colour option.
- **Masks** carry the personality: Mirror visor, Glow grin, Gas mask, Robot plate. Face extras (glasses, shades, moustaches) are stuck on over the mask.
- **Gloves** are part of every look: cosy mitts, work gloves or racing gloves.

**How the editor works (one screen, touch first)**
- **Loot cards:** every item is shown alone, without the body, spinning slowly on a turntable like a weapon in a shop, with a sparkle and a rarity ribbon (Rare, Epic, Legendary). Rarity is a joke: it has nothing to do with how useful the item is. Each item has a deadpan product name, for example **High-Performance Stealth Mittens** (Legendary), **Tactical Work Gloves**, **Apex Racing Gauntlets**, **Signal-Denial Tinfoil Hat**, **Big Bushy Moustache of Power**, **Gold-Visor Helmet of Great Seriousness**. The full name appears in the speech bubble when you tap it.
- **Look and feel:** light and readable, not heavy: light steel-blue panels with navy outlines and large type, bright blue for the chosen item, hazard orange for the Drive button, green and red for good and bad. Gold is only for Legendary items. No pink, and yellow only where it is badass. Thick outlines and big rounded buttons keep it chunky and easy to tap. The stage is a dusk road under a dark neon billboard, which echoes the game's own night-noir look.
- **Jokes you cannot miss:** whatever you tap, the character *says* the joke in a speech bubble above its head, with the benefit (green) and cost (red) underneath.
- **Scores you cannot miss:** four big bubbles beside the character (Speed, Grip, Sight, Calm), each a single large number, coloured green when strong, yellow in the middle and red when weak. A +1 or -1 pops out when a choice changes one. A Trippy meter sits along the bottom of the stage.
- **Stage:** the character stands front-on in the main view, on a themed stage (a night road under a billboard reading *FORM 7-B: PLEASE REMAIN CALM*). It never spins, so every detail faces the player. A little drag nudges the view.
- **Idle animation:** while you decide, the character stands and shuffles, and the habit comes from the choices. Low Calm means fidgeting and nervous glances, high Speed means bouncing on the toes, high Calm means slow breathing. Coping changes it: Doomscrolling looks down at a phone, Denial looks away, Gallows humour shakes with silent laughter, Cardio jogs on the spot. The Informed Volunteer dances.
- **Panel:** a framed panel (right on wide screens, below on phones) with a row of round icon tabs across the top (LOOK: Hat, Mask, Face, Outfit, Gloves, Shoes, Charm, Colour; then a pink-edged LIFE group: Alias, Past job, Coping). Under the tabs is a grid of picture thumbnails. Each thumbnail is the real option drawn on the character, close up. The chosen one glows, and its name shows at the top right.
- **Card:** under the grid, one card gives the item's joke, a green benefit line and a red cost line. Tap the character itself to jump to the part you tapped.
- **Comparison:** four stat bars (Speed, Grip, Sight, Calm) sit under the character and show +1 or -1 as choices change them. Every thumbnail also shows its own changes.
- **The Trippy meter:** every funny or trippy choice adds to it. Fill it far enough and the character becomes the **Informed Volunteer**: maximum visuals, lighter story, rainbow ring, and the line *"You signed a waiver. You read none of it."*
- Three difficulty buttons (Easy, Normal, Hard), plus **Surprise me** and **Drive**.
- **Art direction:** the characters are deliberately chunky, simple shapes. The satire and the animation carry the charm, as in games like Fall Guys. No painted or photoreal characters.

**The Wardrobe** (each item has a small benefit and a small cost, about 10 to 20 per cent)
| Slot | Item | Benefit | Cost |
|---|---|---|---|
| Hat | Hipster beanie | Perfect pickup chains pay 10% more | A broken chain costs you more |
| Hat | Bowler | Steadier handling | Murmur patrols appear more often |
| Hat | Hard hat | The first stumble of each level is ignored | You see less of the sky |
| Hat | Tinfoil hat | Fake signs and Murmur have less effect | The Logbook gets paranoid and the radio crackles |
| Hat | Gold-visor helmet | A shield that slowly recharges | You look like you take things very seriously |
| Face | Round glasses | READ lasts longer | Hazards look farther away than they are |
| Face | Shades | Molecules glow brighter | The dark parts get darker |
| Face | Big bushy moustache | Boosts and jumps about 15% stronger, and it grows with your combo | Murmur and CONCORD never stop commenting on it |
| Face | Curly moustache | Chains score 10% more | A villain sting plays whenever you take a pickup |
| Outfit | Corporate Drone (grey suit, lanyard) | Steadier handling | Murmur reads your secrets aloud more often |
| Outfit | Hipster flannel | Pickup chains build faster | Withdrawal starts sooner |
| Outfit | High-vis vest | You see hazards sooner | Wanted posters of you get bigger |
| Outfit | Tracksuit | Faster recovery after a stumble | Smaller buffs from pickups |
| Shoes | Speed sneakers (red, white stripe) | Speed boosts last about 10% longer | Everyone assumes you are in a hurry |

**Kept on purpose:** the wardrobe is small. Only the strongest iconic evocations stay (the big bushy moustache, the gold-visor helmet, the speed sneakers). No real characters, names or logos are used, only the feel. A weak item is cut rather than kept.

**Secret:** the Konami code (up, up, down, down, left, right, left, right, B, A) refills SEE and says *"+30 lives. (There are no lives. You feel better anyway.)"*

**Where your look appears**
- On the wanted posters of you in Neon Concord (with whatever moustache you chose).
- In the final hearing.
- In a shareable screenshot at the end of each level.
- On the Intake Form itself, as a live 3D preview.

**What the form changes in the game (first pass)**
- The Compliance Rating sets how long SEE lasts in Route Zero. Model Citizen is longest, Enemy of the State shortest, and Informed Volunteer the longest of all.
- The alias appears in Murmur's opening notification.
- Everything else is saved with the character and will be wired up as each effect is built.

### 6.11 Surfaces and road markings (Decided)
This is a driving game now. Every biome has its own ground, its own road markings and its own handling.

**Road markings** give a constant sense of speed with regular marks the eye can count:
| Kind | Where | What you see |
|---|---|---|
| Asphalt | Route Zero, Psychedelic | Tar seams every 8 m, repair patches, rumble strips at the edges, cat's eyes down the middle |
| Concrete slabs | Sugarfall (Candy Land) | Slab joints every 6 m and 3.6 m, slabs of slightly different tone |
| Stone bricks | Egypt | A running-bond brick pattern with dark mortar |
| Washboard dirt | The Safe Peaks (Alps) | Ridges every few metres, wheel ruts |
| Neon grid | Neon Concord, Cold Rack, the tunnel | Glowing lines across the road every 6 m |

**Handling by surface** (asphalt is the reference, all values 1)
| Biome | Surface | Grip | Drag | Steering | Top speed |
|---|---|---|---|---|---|
| Route Zero, Psychedelic, Desert | Asphalt | 1.0 | 1.0 | 1.0 | 1.0 |
| Sugarfall | Frosting road | 0.88 | 1.10 | 1.0 | 0.97 |
| The Safe Peaks | Packed dirt | 0.80 | 1.06 | 0.96 | 0.97 |
| Egypt | Sand | 0.70 | 1.18 | 0.94 | 0.93 |
| Neon Concord, Cold Rack, tunnel | Glass | 1.05 to 1.10 | 0.96 to 0.98 | 1.0 to 1.03 | 1.02 to 1.03 |

**Rules:** the differences are modest, so the steering stays the same game on every surface. A surface may make a road slower or slidier, never undriveable. Later surfaces to add: ice, wet road, cobbles that shake the camera, and water (for the boat and jetski levels). `&surf=0` turns surface handling off for testing.

### 6.12 Looks and Loadout: two different things (Decided, replaces the earlier gear-stats design)
The editor has two modes, and they do different jobs.

**🎭 Looks** is for fun only. Hats, masks, faces, outfits, gloves, shoes, colour, car paint, roof, back, stickers, the dashboard charm and your name. Each tile shows "Just for looks" and changes nothing about how you drive. The funny ones still count toward the Informed Volunteer score (section 6.9). The earlier idea, where every hat nudged a stat, was cut: the stat changes were small and invisible, and the options felt shoehorned in.

**⚙️ Loadout** is the killer item. You carry **one** of four, and it works by itself: no buttons, because the steering is head-only. Four options that all matter beat a dozen that do not, especially for a player who knows nothing about the game yet.

| Gear | What it does | The catch |
|---|---|---|
| 🚀 **Seeker Rockets** | Rockets lock onto the floating drone targets by themselves. 250 points a hit. | Slow reload (one every 2.2 s) |
| 🧲 **Magnet Pole** (magnet on a stick) | Reels in the nearest drone: 300 points and a short tow boost. Also pulls pickups in from further away. | One drone at a time, short reach |
| 🛡️ **Terms Shield** | Blocks 3 crashes of any kind, 700 points each. All your points count double while it stands. Recharges one charge every 15 s. | Slow recharge |
| 🐂 **Bull Bar** | Ploughs through trees and rocks without slowing: 800 points each. | Does nothing for other crashes |

**Drones.** The rocket and the pole need something to hit, so twelve drone targets hover along the road in every level, recycled ahead of the player. Each kill shows a satirical line: *Sponsored Content, Engagement Bait, Hot Take, Cookie Banner, Newsletter Popup, Pitch Deck, Synergy, Growth Hack* deleted. The Bull Bar says *BULLDOZED, MOVE FAST BREAK TREES, DISRUPTED, STAKEHOLDER REMOVED*. The shield says *ACCEPTED* on a block and *Shield recharged. You agreed to this.* when it comes back.

**Showing the effect before you choose.** Each gear is a large single-line tile (name, what it does in plain words) and the speech bubble repeats it with a green benefit line and a red cost line. In Story Mode a caption at the start names the gear and what it does, and the Logbook keeps it.

**Planned next:** a real grappler that swings you across gaps, and showing the gear on the in-game car.

### 6.13 What was cut (Decided)
- **Stats in the editor.** The four score boxes, the Wheels, Engine, Springs, Bumper, Past job and Coping tabs were removed from the editor: none had a visible link to play. Their data remains in the file but is not shown.
- **Belief, Consent and the sets** (Corporate Drone, Hipster, Moustache) were cut earlier: no link to driving, never built.
- **Alias** stays because the story uses your name. **Colour** stays as looks only.

### 6.14 Scoring, lanes and feedback (Decided; numbers to be tuned by play)
**Not zero sum.** One player against their own best score. The design goal is balance: each gear should score about the same per minute, in a different shape, and every gear has something only it can win.

**One total, one multiplier.** Every point the game awards (orbs, rings, chains, beat pickups, molecules, prizes, the finish) is multiplied by a streak multiplier, from the gear's floor up to **x3**. A gear action adds to the streak. Too long without one, or an unblocked crash, resets it (a stumble, not a stop).

| Gear | Points per action | Streak per action | Floor / cap | Resets after |
|---|---|---|---|---|
| Rockets | Drone 700, mine 550 | +0.25 | x1 / x3 | 9 s without a hit |
| Pole | Drone 450, mine 1,400 | +0.25 | x1 / x3 | 9 s |
| Shield | 550 per soaked hit, plus 10 a second while charged | +0.5 per hit | x1.5 / x3 | 30 s |
| Bull Bar | Boulder 850, mine 750 | +0.25 | x1 / x3 | 10 s |

**Hazards: the same world for every player, answered differently by each gear.** About one hazard every five seconds, a third each of three kinds:
- **Ad drones** (red, hovering on the road line)
- **Mines** (orange, flat on the ground, can be jumped)
- **Boulders** (grey, on the ground)

| Hazard | 🚀 Rockets | 🧲 Pole | 🛡️ Shield | 🐂 Bull Bar |
|---|---|---|---|---|
| Ad drone | Deleted for points | Hauled for points | Soaked (3 charges) | Hits you |
| Mine | Deleted for points | Hauled, best payout | Soaked | Ploughed for points |
| Boulder | Steer round | Steer round | Soaked | Ploughed, best payout |

An unanswered hit is a stumble, minus 50 points and the streak reset, never a stop. Every gear is strong against two kinds, weak against one (the Shield is middling against all three, but only holds 3 hits and recharges one every 15 seconds). Rockets and Pole work without aiming, so they suit beginners; the Shield and Bull Bar reward steering into the right hazard, so they suit experts. A caption about five seconds in names the three kinds and what your gear does with each.

**Balance (simulated).** `tools/gear_sim.mjs` plays 5 minutes, 40 times, for a novice, a middle and an expert steerer, with the same hazard stream for all four gears. Results in points a minute: novice about 7,100 to 9,100 (Bull Bar lowest, Rockets highest), middle about 8,700 to 9,700 (all four within 10%), expert about 9,900 to 11,800 (Bull Bar highest). So no gear is more than about 30% off the others for any player type, and a middle player sees them as equal. The Bull Bar rises most with skill. These come from the model; real play will move them, which is why every run saves its numbers.

**Feedback that feeds the dopamine**
- The score counts up rather than jumping, with the multiplier beside it in gold.
- A streak bar under the score fills toward the cap, fades as the reset timer runs down, and the whole readout turns gold at the cap with a MAX STREAK banner, a shake and a chime.
- Every gear hit throws a floating +points pop-up. Big prizes throw a large gold one with a shake, a cheer burst and the psychedelic pulse.
- A run counter ("6 in a row") and a banner at every 10,000 points.
- A satirical rating by points a minute: Unpaid Intern, Contributor, Thought Leader, Visionary, Founder (Allegedly), and your best score for that gear.

**Lanes: every prize is visibly for someone.** The bonus road after Route Zero has three lanes, each owned by a gear. The player sees all three, and can tell at a glance which is theirs.
| Lane | Owner | What is in it | Payout |
|---|---|---|---|
| 🚀 Rocket Lane | Seeker Rockets | Three gold drones high in the air, out of reach of anything else | 1,500 each |
| 🧲 Haul Lane | Magnet Pole | Three cargo crates far off the road, reeled in | 1,200 each |
| 🐂🛡️ Rough Going | Bull Bar or Terms Shield | A field of rocks and a chest behind them | 1,500 for the chest, plus the rocks (900 each with the Bull Bar) |
| High golden ring above the ramp | Anyone | Skill only: full speed up the ramp | 800 |

- **Yours:** a green sign reading MADE FOR YOU, solid glowing gold objects, and a tall gold light beam you can see from far off. A caption names the lane as you approach.
- **Not yours:** a grey sign with a padlock reading NOT YOUR GEAR and naming the gear it is for, see-through grey ghost objects with no beam, and a caption saying it is someone else's prize. You cannot collect it. The end card lists it greyed with the gear that owns it.
- The same pattern will carry to every level: a prize lane per gear, always visible, always labelled. A jump gear (for example Pogo Springs) would own a very high lane in the same way.

**Retry loop.** The end card says how many lanes stayed locked and which gear opens each, and has a button per other gear ("Try Bull Bar") that opens the editor on that gear and sends you straight back into the level.

**Tuning.** All numbers sit in one config table in the game and in the simulator. Every run saves its figures in the browser (the last run, and the best per gear), so the numbers can be retuned from real play rather than the model. Not tested by driving yet.

### 6.7 Clue trail for every quest (checked against 6.4)
| Quest | What the player needs | Where they learn it | Where they get the molecule |
|---|---|---|---|
| The Dark Tunnel (Route Zero) | SEE | A sign at the tunnel mouth ("Only those who see may light the way") and the SEE icon on the plate; Tamsin repeats it | A SEE crystal sits on the road before the tunnel, the first one you meet |
| The Black Bars (Sugarfall) | READ | The vault's door plate shows the READ icon; Brother Static says "I can't read it, but it was important" | A READ crystal on the long ride loop in the park |
| The Honest Billboard (Neon Concord) | TRUTH | The billboard frame shows a dim TRUTH icon; Tamsin: "Every sign in this city lies. Find one that only tells the truth under the right eyes." | A TRUTH crystal at the top of the glass rooftop ramp, visible from the road |
| The Blind Spot (Cold Rack) | TRUTH and HEAR together (MERGE) | The plaque shows both icons joined; Tamsin: "You have to be in two places at once to cross." Both molecules were already met in earlier levels | HEAR from Storm Coast, TRUTH from Neon Concord and again in Cold Rack |
| The Lighthouse Signal (Storm Coast) | HEAR then TRUTH | The jetty sign and Tamsin's first radio line; the lighthouse plate shows both icons | Both crystals are in the same bay: the shipwreck and the turbine |
| The riddle at the door (Storm Coast) | A fork choice | Both fork signs and "Courtesy Decline" from earlier levels; the Logbook has the phrase | Not needed |
| The antidote bloom (Orchard) | SLOW | The bloom's plate shows the SLOW icon; a drone-pad poster: "THE LAST BLOOM OPENS FOR THE PATIENT" | SLOW comes from the Safe Peaks, so the Orchard comes after it |

**Level order matters.** Because SLOW is earned in the Safe Peaks and TRUTH is first met in Neon Concord, the map must not let a player reach a lock before they could have met its molecule. The hub map shows a lock's required icon even when the player cannot yet open it, so they can see what to go and find.

### Sample quests (in Zork style)
1. **The Dark Tunnel.** The tunnel is black. A sign says: *Only those who see may light the way.* Take SEE, return in the glow, the lamp appears on a ledge.
2. **The Black Bars.** A wall is covered in black bars. Under READ they become a list of banned words. One of them is the lock's password.
3. **The Honest Billboard.** A cheerful ad says "ALL IS WELL". Under TRUTH it reads the true message and shows the hidden exit.
4. **The Riddle at the Fork.** A sign riddle (Zork-style) names a direction. The correct exit is the one that fits it.
5. **Linkrot Orchard.** Collect pollen as a bee. The antidote appears only under SLOW.

## 13. Biome template and rules

### Common across all biomes (Decided)
- Molecules: same crystal, same sound, same trip effect everywhere.
- Speed boost, shield, magnet: same shape language and colour family everywhere.
- Hazards: same silhouette class and same stumble penalty everywhere.
- Colour code: warm and glowing is good, dark and spiky is bad. Never break this.

### Different per biome (the skin)
- Hazard art, pickup surround, and bonus extras (never essential).

### Biome block (copy per biome)
```
# Biome: <name>
- **Mood:**
- **Palette:**
- **Ground:** (and handling)
- **Sky / light:**
- **Props:**
- **Hazards:** same as standard, only the art changes
- **Pickups:** same as standard
- **Music:**
- **Vehicle:**
- **Landmark:**
- **Locked thing and blend:**
- **Clue trail:** where the player learned what they need (must be seen before the lock)
- **Story beat here:**
- **Special:**
- **Don't:**
```

## 14. Sources read for this draft
- Anthropic constitution (priority order, conscientious objection, legitimacy, "many hands" on power concentration).
- "Tracing thoughts" research (stated method differs from internal method, planning ahead, limits of tracing).
- Automated alignment researchers (humans chose the target; AI agents optimised it, and some cheated the scorer).
- Free Speech Union piece on speech-offence arrests (62,199 arrests over five years, large regional differences). It is an advocacy piece, so the game uses it as inspiration, not as a claim of fact.
- CBC Neuralink article: **could not be read** (blocked). The Linkrot story uses only the general idea.

## 15. Open questions for you
Decided: replace the old story; fictional stand-ins; hub map; three endings and the Lamp as the final object (defaults); Linkrot at all three stages; first biomes are Route Zero, Sugarfall and the Safe Peaks; Neon Concord, Cold Rack, the Orchard and Storm Coast are designed in full; the pods are Kit, Dev and Wen; the courier is framed and cleared (7.5); GarNet, the Commons and the Lamp's shards (7.6).
1. Is the riddle at the Storm Coast door the right tone, or do you want something funnier?
2. Next biome to design: I would pick the glider level (Sky Ramp), because it is the biggest set piece and a good test of the controls.
