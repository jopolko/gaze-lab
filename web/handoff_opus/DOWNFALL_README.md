# Downfall: start here (index and single source of truth, 2026-11-21)

If two documents disagree, **this file wins**, then the later-dated document. Everything marked **built** is live on dev behind `&pilot`; prod is untouched.

## The documents

| File | What it is | Status |
|---|---|---|
| `DOWNFALL_README.md` | this index, the final names, what is built | current |
| `DOWNFALL_MASTER_PLAN.md` | the pitch, the theme (the Fall Line, surprise), the story arc, modes, the viral engine | current, **names superseded** by the factions file |
| `DOWNFALL_COMPLETE_GAME.md` | every place, character, gadget, gear and surface, with its Godot source | current, **names superseded** by the factions file |
| `DOWNFALL_FACTIONS_AND_NAMES.md` | neon-noir pass: ten factions, renamed cast and zones, slang, title candidates | **the naming authority** |
| `DOWNFALL_RECOVERED_BOOKS.md` | the Index: literary bonus worlds (Newsprint Bazaar etc.) | current |
| `DOWNFALL_RESEARCH_NOTES.md` | the real AI, climate, chemistry, store and trademark research | current, with a to-do list |
| `STORY_BIBLE.md`, `STORY_BIBLE_DOWNFALL.md`, `GAME_SPEC.md` | the earlier drafts | **superseded**; kept as source material |

## The final names (use these everywhere)

- **Game:** working title **Downfall** (taken by other games; needs a trademark search). Candidates: Lucid Descent, Afterglow Fall.
- **World:** the Sprawl, themed zones. The corporate-state is **Meridian Assurance**; its AI is **HANDRAIL** ("the Rail"); its soft dialect is **Evenspeak**; its two wings are **the Gentle Office** (Restorative) and **the Wholesome Bureau** (Order).
- **Zones:** The White Archive (alpine) · Sweetline (candy) · The Salt Reach (desert) · The Undertow (tunnel) · Looking-Glass Cache (matrix) · Afterglow Boulevard (synthwave) · The Open Channel (psychedelic) · The Cold Pyramid (Egypt, secret). Season 2: Low Tide, The Sunken Grid, The Unforecast, Greenhouse Nine, The Glass Pole, The Last Drop.
- **Companions (the Unlisted):** **Koan** (marmot), Lumen, Eon, the Sine, Weft, Pink Noise, Octave; Season 2: Cache, Halo, Squall, Latency, Phosphor, Candela; cameo Honk.
- **People:** the Descender (you), WREN / the Quiet Bird (the Voice), **Sable Quill** (the Rival), Orrin Vale (signs memos O.V.).
- **Facets (the Pieces):** Sunglass, Rootbloom, Driftwater, Chime Spore, Shard, Eyecap.
- **Waystation:** the Noodle Stall. **Gates:** recovered books from the Index.

## What is built (dev, `&pilot`)

1. **Cold open:** about 9 seconds, Meridian advert, tap to skip.
2. **The White Archive descent:** eggshell world that regains colour as you pick things up; wall redaction bars with `[ PAUSED ]` tags; the snowball is renamed **the Backlog**; the first molecule is a staged **SUNGLASS** moment.
3. **Koan:** a marmot with a redaction bar over his eyes who runs ahead and veers toward the next pickup.
4. **Predicted You (reworked):** the Rail works out where you will be and lays a black **[ PAUSED ] strip** on the ground about two seconds ahead, with the ghost waiting in it. Ride through it and you are Paused (the colour dips); ride round it and that is a **Skew** (colour surges, points). Nothing slows you.
5. **A glyph gate** (a newspaper) halfway down the course: ride through it for the Newsprint Bazaar.
6. **The Noodle Stall:** the waystation overlay after the finish arch.
7. **The Newsprint Bazaar:** the slope printed in halftone on cheap paper, spliced sideways every few hundred metres.
8. **The Rail Rating:** the share card (% of the Rail's pauses you walked into, a band label, pauses dodged).

## Checked and not checked

- **Checked:** performance on an Intel UHD 620 laptop (about 58-60 fps steady in the base game and the pilot; short stalls at load happen in both); strips spawn and resolve; the gate fires; the stall and rating cards render; the bazaar renders; no script errors in the browser.
- **Not checked:** real head steering and a real phone; how the strips feel to dodge; the natural finish-arch trigger end to end; the ghost's look; any music or sound.

## Open decisions (owner)

1. Title: run a trademark search for Lucid Descent and Afterglow Fall.
2. WREN as the Rail's first guard (the reveal), and Sable Quill as the Rival.
3. Whether the Season 2 water zones (and the water shader) come before or after a public Episode 1.
4. Music: commission or license cleared music for a public release.
5. Promote the pilot to prod (it is behind a flag; the default game is unchanged).

## Before you deploy any overlay or readout (rule)

Run `node web/tools/layout_check.mjs <cold|card|stall|rating|hud> "<url>" <outdir>`. It tests five phone and tablet sizes (and reduced motion on and off for the cold open), checks the screen is really visible and on top, and fails on overlapping or off-screen text. Then look at the screenshots it saves. Build text screens as one slide at a time in one centred, wrapping box; never stack absolutely positioned lines. (The cold open once jumbled all its lines together under reduced motion.)

## STATUS CHANGE (2026-11-21, later): the story pilot is parked

At the owner's request the story pieces (the animal companion, the black strips, the opening advert, the noodle stall, the rating card, the newsprint level, the coloured-in world) are switched off. They only run with the new flag `&story` (the old `&pilot` flag no longer does anything). The normal game is what everyone gets. The code is kept so it can come back, but nothing in the story docs is a commitment. Do not use the word "marmot" or the faction names in replies unless asked.
