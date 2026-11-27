# AFTERGLOW — from runs to a full game (open-world plan)

*2026-11-26. Owner's direction: the course layout, the lane count and "racing, not open world" were all shaped around eye and head tracking as the main control. That is no longer the main control. Build it out into a full game: open-world zones, the missions and places from the bible, full controls (VR head tracking, touch with buttons, gamepad, mouse and keyboard). The touchstone is a "Grand Theft Mars": a living world with places, people and jobs, in Afterglow's neon-noir dystopia.*

## 1. What we keep (everything)

- **The runs.** The downhill roads, set pieces, raids, strains, molecules, lenses, exits and the trip become the game's **highways and missions**: the long Dead Air drives between places, and the jobs you take. They are already good at that and stay as they are.
- **The look and the trip.** Worlds, skies, Max Intensity, play clear, the art pass, the musical engine, beat sync, the music.
- **The story.** ACCORD, Murmur, the Lamp and WREN's pieces, the Courier, Vance, Ransom, Maro, Dex & Lolo, the Static and the Abliterati, Dead Air (see AFTERGLOW_RECORD.md §5).
- **The tech.** The heightfield, the baked terrain bank, the director, the bots, the level cache, the service worker, the phone-safe UI.
- **Head and eye tracking** stays as an optional extra (accessibility, novelty), never again the design constraint.

## 2. The shape of the game

- **Zones.** A free-roam area around each Static outpost: open ground you can drive anywhere in (off-road, side roads, forecourts, ruins). One per world. The first is **Mile Zero** (the diner on Route Zero, already built as a set).
- **Highways.** Zones are joined by **Dead Air**: the existing runs, entered through road gates at a zone's edge. A highway is a run with a destination: finishing it brings you to the next zone.
- **Missions.** Jobs come in on the **burner phone** (calls and texts from the Static's people). Accept one and a marker appears; drive to it; the mission plays. Two kinds:
  - **Run missions**: a run with a goal (courier job, getaway, raid, chase down the highway). Mostly what we have, given a purpose and a payout.
  - **Zone missions**: set inside a zone (a delivery across it, a chase, find ACCORD's hidden camera with a lens, break into the drone nest, the Diner Breakout).
- **The burner phone is the interface** (pause = take out the phone): Calls and Messages (missions), Map (zones, highways, outposts), Murmur (your heat), Radio (music), Garage (car and character), Stash (strains, gear, Lamp pieces), Camera (inspect and share: the diagnostic tool in-world), Settings.
- **The spine.** The episode spine in AFTERGLOW_MISSIONS.md becomes the main story missions; the scenes bank becomes side jobs.

## 3. Controls (all inputs, one mapping)

| Action | Touch | Gamepad | Keyboard & mouse | VR |
|---|---|---|---|---|
| Steer | joystick left/right | left stick | A/D or arrows | controller stick or tilt |
| Throttle / brake (reverse) | joystick up/down | triggers RT / LT | W/S or arrows | triggers |
| Jump / launch | button (right thumb) | A | Space | button |
| Boost / RUSH | button | B or RB | Shift | button |
| Gear (rockets, pole, shield, bull bar) | button | X | E / left click | button |
| Look around | drag the right half | right stick | mouse | head (true 6-DoF) |
| Phone (pause) | the padlock | Start | Esc / Tab | menu button |

- In **runs**, throttle and brake matter less (gravity drives you downhill); they trim speed. In **zones** they are the engine: accelerate, brake, reverse, turn on the spot.
- Touch keeps the floating joystick (now 2-D) and adds two or three thumb buttons on the right, sized and placed off the rounded corners, only shown when they mean something.
- VR: true head look, with the clean-screen rule (no HUD; the phone is held in the hand).

## 4. What has to be built

1. **Driving physics for open ground.** Today's handling is a downhill sled: gravity drives you, steering bends the line. Zones need an engine: throttle, brakes, reverse, low-speed turning, grip and drift. The run physics stays for runs; zones get a car model that shares the feel (the same steering curve, the same landing and jump behaviour).
2. **Open terrain streaming.** Runs stream terrain as rows down one axis. Zones need a grid of tiles in every direction, built from the baked bank plus the basin generator (the `?basin` prototype already builds a 300 m bowl). A zone is about 1–2 km across; tiles load around you, with the level cache.
3. **Camera modes.** First person (as now) and a chase camera, switchable. Zones probably default to chase so you can see the car on open ground.
4. **The burner phone** (above). Phase 1: pause = phone, apps replace the menus, Camera = inspect and share. Phase 2: calls and texts that deliver missions, a notification banner during play.
5. **Mission system.** A mission is data: who gives it, where it starts, the goal (reach, collect, chase, survive, escape), the run or zone it uses, the payout, the dialogue. Markers in the world, a simple objective line on the phone and as a toast in play (clean screen: nothing permanent).
6. **Heat.** ACCORD's attention, shown in the world (searchlights, drones, raider frequency) and on Murmur. Raised by public chaos; cooled by Dead Air, tunnels and paint shops (already planned).
7. **Money, the garage and saves.** Shards and credits from missions; upgrades and repaints in the garage (the character editor, reached from the phone); progress saved per outpost.
8. **Life in the zones.** Traffic, Static locals, ACCORD patrols and raiders roaming (the raider craft and scorpions exist), the diner's local hours (built), ambient radio.

## 5. Milestones (each one playable)

1. **Controls + Mile Zero.** Full input mapping (touch 2-D joystick and buttons, gamepad, keyboard and mouse); a small open zone around the diner (free roam, the car model, chase camera); one mission picked up by phone that launches an existing run (the Route Zero courier job). *Done when* you can roam Mile Zero, take the call, drive to the marker and play the run, on phone, PC and gamepad.
2. **The phone as the hub.** Pause = phone; Calls, Map, Garage, Stash, Camera (inspect + share), Settings, Radio; heat on Murmur; money and saves. *Done when* every current menu is reachable from the phone and the old pause menu is gone.
3. **The second zone and the highway between.** A run that ends in the next zone (Dead Air between Mile Zero and Low Band); zone missions (delivery, chase, hidden camera); roaming raiders and patrols. *Done when* the game can be played zone to zone for 20 minutes without the menu.
4. **The rest of the worlds.** One zone per world (Low Band, Sideband, the Squelch and the world outposts), the episode spine as story missions, side jobs from the scenes bank.
5. **VR.** True head look, controller mapping, the phone in the hand.

## 6. Risks and how we keep them small

- **Phones.** Open ground costs more than a corridor. Zones stay small (1–2 km), stream tiles, reuse the baked bank and the performance governor (smooth first, then distance).
- **Scope.** Each milestone ships on its own; runs keep working throughout.
- **Feel.** The car model must feel like the run handling. Bots and the steering probe measure response the way we did for touch.
- **Story load.** The owner was overwhelmed once (keep it simple): missions are short, plain-worded, one decision at a time.

## 7. Decisions for the owner (one at a time, when we reach them)

1. Zones in first person or chase camera by default?
2. Can you leave the car in a zone (on foot), or are you always driving? (Recommendation: always driving, for now.)
3. Money: one currency (credits) or two (credits + shards)?
4. Are the existing levels kept as a separate "Arcade" mode too, for quick runs?
