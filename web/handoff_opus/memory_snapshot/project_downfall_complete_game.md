---
name: downfall-complete-game
description: Downfall complete game catalogue (2026-11-21): where every place, character, gadget, gear and surface is ported from in Godot, plus Season 2 new biomes incl. beach with crabs; doc web/docs/DOWNFALL_COMPLETE_GAME.md
metadata:
  type: project
---

Owner asked for "the complete game": levels, biomes, characters, equipment; stunning scenery and water everywhere; port from Godot source in every case; use new effects plus trippy mobile-friendly ones. Result: web/docs/DOWNFALL_COMPLETE_GAME.md (companion to DOWNFALL_MASTER_PLAN.md).

Key finds in Godot source: Themes.gd ORDER has 8 themes (alpine, psychedelic, tunnel, desert, candy, egypt, matrix, synthwave; egypt = the Vault); Realms.gd has 12 mystery-gate realms (highway, interzone, hive, eyes, melt, mandala, glowcave, crystal, lava, abyss, canyon, mammoth); Zone.gd has bounce/boost/slip/sticky/lava/vent (= my ice/mud/boost/trampoline surface ideas); Roster.gd has 15 comic characters (Barry the Balloon, Mime Marcel, Vacuum Vic, Poof the Magician, THE BIG CHEESE, Honk the Goose...); weapons LeafBlower/PlungerGrapple/RocketLauncher/ShockRifle; Loot.gd gear (Hat/Boots/Gloves, 5 rarities, "of Butter" suffixes); Progression.gd skill tree. Godot has NO water/beach: those are new (Season 2 "The Thaw": Tideline with crabs, Drowned City, Stormbelt, Canopy, Aurora, Stratosphere) built with one-ShaderMaterial water.

**Why:** reuse what Godot already designed (cheap) and only invent story layer, Season 2, water, Predicted You.
**How to apply:** build order in doc section 11; open decisions in section 12. Related: [[downfall-master-plan]]
