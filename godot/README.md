# Goose Chaos FPS (Godot 4.7 prototype)

Open this folder in Godot 4.x and press **F5** (main scene: `scenes/MainLevel.tscn`).
Everything (arena, props, enemies, navmesh, sounds, HUD) is built from the scripts
and scenes here; no external assets.


## What's in the game now

### 15 characters (all primitive shapes; see `scripts/Roster.gd`)
| Character | Brain | Gimmick |
|---|---|---|
| Dave the Waddler | chase | Shoves you. Baseline. |
| Honk the Goose | rush | Telegraphed HONK, then a straight-line charge |
| Sir Bounce-a-Lot | hop | Pogo hops; every landing is a shockwave |
| Big Brenda | tank | Huge, ground-pounds, only a massive hit ragdolls her |
| Kaboom Kevin | bomber | Sprints in and explodes (chain-explodes if killed near friends) |
| Gerald the Banana | peel | Kites you and drops slippery peels (they trip enemies too) |
| Tomato Tony | thrower | Lobs tomatoes you can kick back |
| Dizzy Dan | rush (homing) | Human tornado, then helplessly dizzy |
| Barry the Balloon | flyer | Floats, dive-bombs, pops in one hit |
| Mime Marcel | mime | Freezes while you look at him |
| Mama Quack | summoner | Spawns ducklings in threes |
| Duckling | chase | Tiny, fast, furious |
| Vacuum Vic | vacuum | Sucks in you and your props, then burps everything out |
| Poof the Magician | blink | Teleports behind you in a puff of confetti |
| THE BIG CHEESE (boss) | boss | Stomp, roll, summon. Every 5th wave. |

### Damage, XP, skills, loot
- **Health + damage:** player HP, enemy HP bars, crits, damage numbers, i-frames, death ("EMBARRASSED", lose 25% coins).
  Damage sources: kick, slide, blower DoT, plunger flings, thrown props, ragdoll SPLAT impacts, explosions.
- **XP + levels** with a kill-combo style meter ("SLAPSTICK!" ... "GOOSE GOD!!!") that multiplies XP.
- **Skill tree (Tab / Back):** 16 skills in Brawler / Gadgeteer / Survivor, three capstones (Shockwave Boots, Yeet Cannon, Second Wind). Free respec. Saved to `user://goose_chaos_save.json`.
- **Drops:** coins, rubber-chicken health, six timed power-ups (Mega Boots, Turbo Burrito, Anti-Gravity Socks, Yeet Juice, Cheese Magnet, Dignity Shield) and procedurally generated gear (Hat/Boots/Gloves, 5 rarities, random affixes, loot beams). Better gear auto-equips, the rest sells.
- **Waves** escalate forever; clearing a boss wave moves you to the next level. PgUp/PgDn jumps levels.

### 5 levels (`scripts/LevelBuilder.gd`)
1. **Backyard BBQ Showdown**: trampolines, slip-n-slide, goo pool, sprinkler boost strip, string lights, grill embers.
2. **Supermarket Graveyard Shift**: flickering fluorescents, wet-floor ice, freezer goo, conveyor boosts, shelf-top cart ramps, mattress trampolines.
3. **Candy Kingdom Meltdown**: chocolate-river goo, rainbow slide, marshmallow bounce pads, gumdrop hills, falling sprinkles.
4. **Moonbase Low-G Brawl**: 0.4x gravity, reactor tower with launch pads, updraft vents, moon ice, stars + Earth.
5. **Disco Inferno Lava Lair**: lava everywhere, bridged islands, vents, animated disco floor, spinning disco-ball spotlights.
Props include explosive TNT crates in every level.

### Tests / tools
- `tests/smoke.tscn` headless test (levels, roster, damage, loot, skills, weapons).
- `tests/shots.tscn` windowed screenshot tour: `Godot.exe --path . res://tests/shots.tscn -- <output dir>`

## Controls
| Action | Input | InputMap name |
|---|---|---|
| Move | WASD | `move_forward/back/left/right` |
| Sprint / Jump | Shift / Space | `sprint`, `jump` |
| Slide | Ctrl or C (while moving fast; land holding it too) | `crouch` |
| Kick | F | `kick` |
| Fire / Alt fire | LMB / RMB | `fire`, `alt_fire` |
| Weapons | 1, 2, mouse wheel | `weapon_1`, `weapon_2`, `weapon_next`, `weapon_prev` |
| Release mouse | Esc (click to recapture) | `ui_cancel` |
| Skill tree | Tab / Back | `skill_tree` |
| Level prev/next | PgUp / PgDn | `level_prev`, `level_next` |

**Gamepad** (Xbox layout): L-stick move, R-stick look, L3 sprint, A jump, B slide, X kick, RT fire, LT drop, LB/RB or D-pad switch weapons. Rumble on hits; HUD hints swap automatically.

`scripts/Game.gd` (autoload) registers these at startup if they are not already in
Project Settings > Input Map, so you can override any of them there.

- **Leaf Blower** (hold LMB): wind cone pushes props and ragdolls enemies. Aim at the ground to rocket-jump/hover.
- **Plunger** (LMB): hooks props/enemies and reels them to a hold point above you; LMB again flings, RMB drops. On walls it grapples *you* (Space or click to let go).
- **Slide** down the central ramp for big speed; run or slide into enemies to bowl them over.

## Physics layers (Project Settings > Layer Names > 3D Physics)
| Layer | Name | Bit | Collides with (mask) |
|---|---|---|---|
| 1 | World | 1 | static geometry (mask 0) |
| 2 | Player | 2 | World, Enemy, Props (13) |
| 3 | Enemy | 4 | World, Player, Enemy, Props (15) |
| 4 | Props | 8 | everything (15); also used by ragdoll limbs |

The leaf blower's `WindCone` and the kick query use mask 12 (Enemy + Props).
Project settings: Jolt Physics, 60 ticks/s, gravity 9.8 (the player uses its own 24).

## Scene hierarchies
```
Player.tscn            CharacterBody3D (PlayerController.gd, layer 2, mask 13)
  CollisionShape3D     Capsule r0.4 h1.8
  Head                 Node3D (pitch)
    Camera             Camera3D (spring recoil / shake / FOV applied here)
      WeaponManager    Node3D (WeaponManager.gd)
        LeafBlower     instance
        PlungerGrapple instance
      KickFoot         MeshInstance3D

LeafBlower.tscn        Node3D (LeafBlower.gd : WeaponBase)
  Model > Body, Nozzle, Handle
  Muzzle               Marker3D
  WindCone             Area3D (mask 12) > ConeShape (convex cone built in code)

PlungerGrapple.tscn    Node3D (PlungerGrapple.gd : WeaponBase)
  Model > Handle, Cup
  Muzzle               Marker3D        (tether + cup meshes are created in code)

Enemy.tscn             CharacterBody3D (EnemyAI.gd, layer 4, mask 15)
  CollisionShape3D, Visual > Body, Head, ArmL, ArmR, NavigationAgent3D
  (ragdoll = Prop RigidBody3D torso/head/arms + PinJoint3D, spawned at runtime)

MainLevel.tscn         Node3D (MainLevel.gd)
  WorldEnvironment, Sun
  NavigationRegion3D > Geometry   (blockout boxes/ramps added by script, navmesh baked at runtime)
  Props, Enemies, PlayerSpawn, Player (instance), AudioHooks
  UI (CanvasLayer) > HitNotifierUI, Hud
```

## Scripts
`Game.gd` event bus/inputs | `PlayerController.gd` | `WeaponBase.gd`, `WeaponManager.gd`, `LeafBlower.gd`, `PlungerGrapple.gd` |
`EnemyAI.gd` | `Prop.gd` | `HitNotifierUI.gd`, `Hud.gd` | `AudioHooks.gd` (synthesised sfx) | `MainLevel.gd`

Hooks: call `Game.popup("TEXT", world_pos, color)` and `Game.sfx(&"name", world_pos)` from anywhere.
Add a weapon by subclassing `WeaponBase` and dropping its scene under `WeaponManager`.

## Tests
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/smoke.tscn
```

## Hands-free / eye-tracking mode ("Dead Eye Goose")

Press **F9** in game. The mouse becomes a simulated gaze point until a webcam tracker is connected.

| You do | Game does |
|---|---|
| Look at an enemy or prop for ~0.35 s | **Locks** it (up to 3) and drops into bullet time |
| Hard blink (or wait ~2 s) | Fires the **volley** at every locked target |
| Look at loot | Magnetises it to you |
| Look at the floor for ~0.7 s | Auto-walks there, stops when enemies get close |
| Look near the screen edge | Pans the camera (dead zone in the middle) |
| Wink left / right | Kick / next weapon |
| Open mouth / raise brows | Burp shockwave / jump |

Mime Marcel freezes only when your *gaze* is on him. Low tracking confidence widens the snap radius and slows the dwell timers.

Keys: F9 hands-free on/off, F10 mouse-sim <-> webcam backend, F8 recentre. Mouse-sim gestures: B blink (tap twice = double), Z/X wink, M mouth, V brows.

Webcam: `pip install mediapipe opencv-python`, download `face_landmarker.task` next to `tools/gaze_helper.py`, run `python tools/gaze_helper.py --preview`, then F9 + F10 in game. Packets are JSON over UDP port 5005 (format documented in `scripts/GazeProvider.gd`), so a phone app or other tracker can feed the same game. **The helper has not been tested on real hardware yet.**

Code: `GazeProvider.gd` (autoload, backends, filter, gesture detection), `OneEuro.gd`, `GazeTargeting.gd` (dwell, lock, bullet time, volley, walking, HUD overlay).

## Eye-control web demo (joshuaopolko.com/gaze-lab/godot/)
The web build (`Game.demo_mode`) is a stripped-down demo of the eye-tracking scheme: one tiny arena (`LevelBuilder._demo`), two guns (Shock Rifle, Rocket Launcher), no shadows/glow, and a start screen (`EyeDemoIntro`). START WITH CAMERA opens the front camera (MediaPipe Face Landmarker, loaded on demand from a CDN, on-device), goes fullscreen and calibrates by having you look at the centre for 3 s. EYES aim, BLINK fires, WINK swaps guns, LEAN moves. If the camera fails it falls back to touch/mouse as the eyes. A small mirrored preview with iris dots shows what the tracker sees. Build: `Godot --headless --export-release Web build/web/index.html` (needs web export templates). Deploy: `tar czf - -C build/web --exclude='*.import' . | ssh YOUR_SSH_HOST 'tar xzf - -C /var/www/html/gaze-lab/godot'`.
