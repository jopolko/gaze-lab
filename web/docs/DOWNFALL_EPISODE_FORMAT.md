# Downfall episode format (v1, built)

Built 2026-11-21. Checker: `downhill-three/episode_check.js` (also run by `node tools/check_episode.mjs <files>`). Samples: `downhill-three/episodes/S1E01..S1E03.json`; `latest.json` is what the game plays; `?ep=S1E02` picks one; `&leg=N` jumps to leg N without cards. Each gate accepts two Pieces (`redacted_wall`: ROOTBLOOM or EYECAP; `spine`: SUNGLASS or CHIME_SPORE); the gate mechanics are the same for both Pieces so far, only the colour and the line differ. Optional top-level `place` fills the `{place}` slot.

One episode is one JSON file. The game plays only files that pass the checker. The AI writes episodes; the checker keeps them playable.

## What is fixed (the series bible, never generated)
- Cast: the Traveller, the Crystal (the Last Copy), the Rail (the controlling AI). Plain words, wry tone, no real people or events by name.
- Leg types the game can build: `road` (jeep chase), `glider` (canyon race). More are added in code later: `boat`, `heli`, `rail` and so on.
- Pieces (molecules): ROOTBLOOM (paths), SUNGLASS (warmth), DRIFTWATER (time), CHIME_SPORE (sound), SHARD (structure), EYECAP (truth). Each leg names one Piece, and the leg has a gate that cannot be passed without it.
- The trip level always builds across an episode and eases down at the end.

## The file

```json
{
  "id": "S1E01",
  "title": "The Road Remembers",
  "previously": "one sentence, or null for episode 1",
  "cold_open": ["line", "line", "line"],
  "legs": [
    {
      "type": "road",
      "seed": 7,
      "length": 2700,
      "difficulty": 0.4,
      "chasers": "raiders",
      "piece": "ROOTBLOOM",
      "gate": "redacted_wall",
      "trip": [0.1, 0.5],
      "before": ["line", "line"],
      "after": ["line"]
    },
    {
      "type": "glider",
      "seed": 8,
      "length": 2300,
      "difficulty": 0.5,
      "chasers": "drones",
      "piece": "SUNGLASS",
      "gate": "spine",
      "trip": [0.45, 1.0],
      "before": ["line", "line"],
      "after": ["line"]
    }
  ],
  "twist": "one or two sentences",
  "closing": ["line", "line"],
  "next_time": "one sentence"
}
```

## Rules the checker enforces
- `legs`: 3 to 4 entries (2 while we test), each `type` from the known list.
- `piece` is one of the six; `gate` matches the leg type (`road`: `redacted_wall`; `glider`: `spine`).
- `trip` is `[start, end]`, both 0 to 1, with end greater than start; the first leg starts at or below 0.2; the last leg ends above 0.85.
- `difficulty` 0 to 1; `seed` an integer; `length` 1800 to 3600.
- Every line is plain text, 3 to 90 characters; at most 4 lines in any list; no real names or places.
- Slots allowed in lines: `{chaser}`, `{piece}`, `{place}`; any other `{...}` fails.

## Where it plugs in
- `crossing.js` reads the legs list instead of the two hard-coded legs. The `seed`, `difficulty`, `piece` and `trip` replace today's constants.
- The server writes one new episode a week from the series bible, a "story so far" file and the checker, and publishes it as `episodes/latest.json`.
- Pieces you have collected are kept on the device, so later episodes can use them.
