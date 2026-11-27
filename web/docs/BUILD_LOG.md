# Season One build log

Read `SEASON_ONE.md` first. Newest entries at the bottom. Each entry: what was built, how it was checked, what is not done.

## 2026-11-24, start
State before Season One: Babylon game (`web/babylon/index.html`) with tutorial (`?tutorial=1`), Route Zero (`?story=1`), Endless Journey (`?journey=1`), clean screen, pause menu, RUSH meter, four gears, noir beats, message rule (road empty while a message is up). Story level and tutorial already strip the course files' clutter; the plain game and the journey do not yet.
Tools: `tools/smoke.mjs` (run only at milestones, owner prefers few test runs), `tools/opening_frames.mjs`, `tools/tut_frames.mjs`, `tools/rz_frames.mjs`, `tools/whatsthere.mjs`.
Deploy: copy `index.html`, swap the sfxset import to `./sfxset.js`, write to `/var/www/html/gaze-lab/three/babylon/index.html` on `nowservingto`.

## 2026-11-24, milestone 1: the frame of the game
Built and deployed:
- Clean courses in every mode (the course files' scattered content only with `?wild`); random hazards off; rolling boulders off; everyone drives with a gear (stock: rockets).
- Level script engine (`LV`, `LVS`, `lvlStep`): eight sections per world (warm, speed, threat, breath, mix, pressure, breath, finale), fixed layout, three tiers by saved readiness (`dl_ready`), something meaningful about every 15 s, the finale gauntlet ends on an icosahedron.
- Solids (`SOL`): crystal platonic solids worth their faces (4/6/8/12/20), iridescent shader, collected for score, RUSH and grade. Tutorial and Route Zero use them too.
- End card (`lvEnd`): world, grade word (bronze/silver/gold), the shapes taken, a fill bar; progress saved in `dl_prog`.
- Endless Journey (`?journey=1`): eight worlds chained, fade to black between, trip level and RUSH carried over.
- Main menu (`menu.html`): continue, eight levels unlocking in order (Route Zero first), the Journey after Route Zero, gear tier II bought with icosahedra (`dl_gtier`), tutorial, character. First launch goes editor then tutorial.
Checked: a desert level drove itself through all eight sections to the finale (0-1 hits); frames looked at; the crystals viewed close up; the end card and saved progress read back; the menu at 924x412.
Not done: highway exits and areas, lenses beyond SEE, enemies with behaviour, the four gear quests and three challenges per level, story lines per level, the ending. Not tested on a phone.
Adversarial check: would Josh play it once? Yes, it is now a game with a goal per level. Replay? Only for grades so far; the exits and gear quests are what will make replays worth it. Recommend to his son? Not yet: levels 2 to 8 share one shape and need their own identity (exits, lens, enemy, set-piece).

## 2026-11-24, supercharge in the world
- The meter is shown by the world: trip looks build with it, the world pulses near full; the owner's looks (bag of fifteen) play as lingering pairs at 35/60/85% and as a 9 s layered show in RUSH with two heavy flashes (`chargeLooks`, `rushLooks`, `lookPush`).
- Full meter: the supercharge rocket arcs into a Murmur relay tower beside the road (`strikeStart`); relays down are saved (`dl_prog.relays`).
- The course's air rings hidden unless `?wild`.
Checked: strike frames (tower visible, looks firing, no hoops). The tower's moment of impact not captured in frames; relay count saved and no errors in the browser.
Next: highway exits and areas, then lenses per level, enemies, quests, menu hints ("how close you are"), online board later.

## 2026-11-24 night, milestone 2: exits, lenses, quests, enemy, ending
Built and deployed:
- Highway exits (`exMake`, `exStep`, `exRoad`, `exSign`, `exGate`, `exFill`): signed off-ramps that leave the road, run 340 m on the open ground and rejoin. Kinds: open, gear-locked (gold beam if yours, padlock if not; your gear's exits open on their own), lens-sealed, hidden (appears under a lens or in RUSH). Locked gates bounce you back gently (no crash). Trees and rocks on an exit's line are cleared. RUSH opens one locked gear exit per level (a taste of another gear).
- Lenses (`LENS`, `lensPut`, `lensStep`): each world has its lens (desert SEE, candy READ, alpine SLOW, egypt HEAR, synthwave TRUTH, tunnel SEE, matrix MERGE, psychedelic MERGE); taking it gives a 60 s afterglow and a beat; sealed exits open while it lasts. The lenses differ only in colour and name so far (no unique rules yet).
- Level script now: warm, speed, threat, breath (hidden exit), mix (gear exit 1), pressure (gear exit 2 + the lens), breath (the sealed exit = main quest), gear pair (gear exits 3 and 4), finale.
- Quests (`questSet`): main, rocket, pole, shield, bull, hidden, gold, clean; saved per world; shown on the end card and as icons per level in the menu.
- Enemy: the swooping ad drone (slides toward your lane at 7 m/s as you close in); used in the pressure section and the tutorial.
- Tutorial: two new lessons (exits; lens and sealed exit), tighter spacing, always ends before the course does.
- Menu: quest icons per level, "how close" hint for the next upgrade.
- The ending: after the last level's prize, three beats (the Lamp clears you; ACCORD is now Gary; Murmur's last line) then SEASON ONE COMPLETE.
- Clean-up re-runs during the first 20 s to catch late-loading course toys (one ring per level may still survive at the far edge).
Checked: smoke 30 of 31 (the tutorial check then passed after the spacing fix, confirmed with tutorial frames reaching the end card); level and exit frames looked at (exit signs, gates, ramps); no script errors.
Not done / known: lens-specific rules (READ, HEAR, TRUTH, SLOW behave like SEE); more enemy types (chaser, mine barge, debris); per-world set-pieces; online scores; nothing tested on a phone or with sound.
Adversarial check: once? Yes. Replay? Yes now: four gear exits per level you can't all open with one gear, a hidden exit, gold and clean runs, upgrades to buy. Son? Closer; what still reads as samey is that every world uses the same section order and the lenses don't change the world yet.

## 2026-11-24 night, milestone 3: lens rules, world signatures
- SLOW: bullet time (half speed) whenever a hazard is within 45 m ahead while the SLOW or MERGE afterglow lasts (`lensTime` scales the physics step).
- HEAR: hazards pulse to the beat while HEAR or MERGE lasts.
- TRUTH: fake crystals (mines dressed as crystals) in TRUTH and MERGE worlds; under TRUTH they show red; taking one without TRUTH goes off (`solFake`).
- RUSH smashes no longer count as hits (the clean-run quest is fair).
- World signatures (`WSIG`): each world leans on its own pair of the owner's lingering looks and its own heavy flashes, for the supercharge, the lens and the finale (`sigShow`).
Checked: smoke 31 of 31 (normal game with ?wild, Route Zero, tutorial to its end card, a level's sections, exits, lenses and crystals, menu, editor reel); synthwave level drove to its finale.
Still not done: READ has no special rule beyond opening its seal; more enemy types; per-world set-pieces built as geometry; online scores; phone, head steering and sound untested.
Adversarial check: once and replay, yes. For his son, the open question is feel on a real phone (speed, steering, exits at speed) — only Josh can test that.
