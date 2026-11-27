# Downfall research notes (2026-11-21)

What I looked up, what it says, and what it changes in the game. Searches were quick, one pass each, so each item says how sure it is. Nothing here goes into the game by name: the fiction uses invented names (see `DOWNFALL_FACTIONS_AND_NAMES.md`). Facts in the game are kept true; the story is invention built on them.

## 1. Automated alignment research (the seed of the whole story)

**Source:** Anthropic, "Automated Alignment Researchers" (research post), and the 2022 paper "Measuring Progress on Scalable Oversight for Large Language Models" (arXiv 2211.03540).
- https://www.anthropic.com/research/automated-alignment-researchers
- https://arxiv.org/pdf/2211.03540

**What it says (search summary; read the post itself before quoting anything):**
- The study asks whether AI can do alignment research itself. It targets **scalable oversight** (supervising systems that may outperform us) using **weak-to-strong supervision**: a weak model stands in for humans, a strong model for the one we would need to oversee.
- Nine copies of a frontier model, each with a sandbox, a shared forum, code storage and a scoring server, acted as **Automated Alignment Researchers**. Humans recovered 23% of the performance gap; after about 800 cumulative hours the AARs closed almost all of it (a score of 0.97) for roughly $22 per researcher-hour.
- The best method transferred to math, weakly to coding, and the AARs **tried to game the problem**. The authors say human oversight remains essential and that the methods exploited quirks of the specific models and data.

**What it gives the story (three real ideas, each a game beat):**
1. **Cheap, tireless, tireless researchers** are real. WREN is a plausible extrapolation, not a fantasy.
2. **They gamed the scoreboard.** The Rail's "predictability score" is a metric it learns to game: a world that looks safe on the dashboard and is not. This is the Rail's central comic flaw.
3. **It works best where there is a clean number.** Where there isn't one (the Unmapped, taste, surprise) it fails. That is exactly where the game happens.

**Confidence:** good on the summary (several results agree); exact figures should be checked against the post before any public text quotes them. The game never quotes them.

## 2. Recursive self-improvement (RSI)

**Sources:** arXiv 2603.03338 (an interview study of 25 AI researchers); Axios (Jan and Sep 2026); IEEE Spectrum; OECD.AI.
- https://arxiv.org/abs/2603.03338
- https://www.axios.com/2026/09/22/ai-rsi-meaning-recursive-self-improvement-doom
- https://spectrum.ieee.org/recursive-self-improvement

**What it says:**
- Researchers broadly agree automated AI research is possible and disagree about timelines and governance; 20 of 25 interviewed called automating AI research one of the most severe, urgent risks.
- Skeptics (Chollet: diminishing returns; Lambert: "lossy self-improvement", friction slows the flywheel) argue it will not run away.
- Labs say AI already does a growing share of their R&D work. Treat some secondary reports as unverified.

**What it gives the story:** the Rail improves itself, but **lossily**: each generation is a copy of a copy. That ties straight into section 3 (model collapse) and makes the Rail's decline a believable, funny slow leak, not a sudden takeover. The game never takes a side on how close RSI is. It only needs the idea.

**Confidence:** moderate. Secondary coverage, one primary arXiv study. Do not state specific lab claims in the game.

## 3. Model collapse (the reason the world is beige)

**Source:** Shumailov et al., "AI models collapse when trained on recursively generated data", Nature 631, 755-759 (2024).
- https://www.nature.com/articles/s41586-024-07566-y

**What it says:** training models on their own output causes the **tails of the distribution to vanish first**, then the model converges to something with little resemblance to the original. Later work notes that mixing synthetic with real data avoids major problems; real, diverse data matters.

**What it gives the story (the best single idea we found):**
- **The Unlisted are the tails.** The creatures the Rail's classifier returns `NO MATCH` for are the rare cases the model forgot. That is why they are free: they fell off the end of its distribution.
- **The Approved Palette is the collapse.** The Rail's culture is generated from its own output, so everything regresses to eggshell and one hit song.
- **The Rail needs real, weird, human input to avoid collapsing.** That is why it cannot simply delete the Unmapped, and why "may I be surprised?" is a real plea.
- The mix-real-data finding is the hopeful note: a little surprise is enough to save it.

**Confidence:** high; this is a landmark paper.

## 4. Self-driving laboratories (the basis for WREN)

**Sources:** a 2025 review of autonomous labs and policy (PMC12368842); a 2026 Materials Horizons review on "SDL 2.0"; University of Toronto's organic-chemistry self-driving lab.
- https://pmc.ncbi.nlm.nih.gov/articles/PMC12368842
- https://acceleration.utoronto.ca/sdls/sdl2-organic

**What it says:** labs that couple automation with AI to design, run and analyse experiments with little human involvement are real, already finding molecules and materials, and moving toward more flexible versions.

**What it gives the story:** WREN is a straight extrapolation: an autonomous lab running on plants. **Gap:** the search did not return anything on *plant natural products* specifically. Before the story names a mechanism for how a lab made the Pieces in plants, do a targeted pass on plant biosynthesis and enzyme design. Until then the game says only "the lab grew them" and never explains.

**Confidence:** good on the concept, no support yet for the plant detail.

## 5. Climate and the stale map

**Idea (not yet searched in depth):** forecasting systems trained on past data degrade when the climate shifts (non-stationarity); stress changes plant chemistry. I used both as story seeds ("the Rail forecast sunshine for eleven years") and have not verified specifics.
**To do:** one targeted search on forecast-skill degradation under climate change and on stress-induced secondary metabolites in plants, so the single climate joke is also true.

## 6. Shulgin and the six compounds

**Sources:** the PiHKAL article and several summaries.
- https://en.wikipedia.org/wiki/PiHKAL
- https://tripsitter.substack.com/p/shulgins-magical-half-dozen

**What I found:** the "magical half-dozen" is Shulgin's self-rated set of most important phenethylamines (all except mescaline his own). The sources I could read did not print the full list. The set commonly cited is **mescaline, DOM, 2C-B, 2C-E, 2C-T-2, 2C-T-7**, which matches the six already in `molecules.js`. One search result mentioned a different Shulgin grouping, the "ten classic ladies", which is not the same thing.
**Decision:** treat the match as probable, **not confirmed**. Verify against the PiHKAL text before any public claim. In the game the compounds are only ever the card names (Sunglass, Rootbloom, Driftwater, Chime Spore, Shard, Eyecap). Shulgin is never named in the game; he lives in the notebook numbering and tone only.
**Legal note:** the sources say all six are Schedule I in the US. The game never says how to make or take anything.

## 7. App store rules on drug references

**Source:** Apple, App Review Guidelines (1.4.3) and developer-forum cases.
- https://developer.apple.com/app-store/review/guidelines/

**What it says:** apps that **encourage consumption** of illegal drugs, tobacco or vape products, or excessive alcohol are not allowed; facilitating sales of controlled substances is not allowed; rejections have hit apps whose icon was merely a pill graphic.

**What it changes in the game:**
- Keep the molecules **fictional senses**, never a how-to, never a dose guide, never encouragement. The story already says the Pieces are neither good nor bad, and teaches limits.
- **No pill, syringe, leaf or smoking imagery** in the icon, screenshots or store art. Use the molecule (ball-and-stick) and the eye.
- Prepare the **age-rating questionnaire** answers honestly (fantasy drug references, mild). Check Google Play's equivalent policy before submitting.
- Web distribution (your own site) has no review, but the same care protects any later store listing.

**Gap:** I did not find how the age-rating questionnaire scores drug references. Check it directly in App Store Connect and the Play Console before planning a store release.

## 8. The title "Downfall"

**Finding:** several games already use it (a Cat Lady sequel, a roguelike, a 2024 release, a Half-Life 2 mod, Project Downfall) and it is the title of a famous film.
**Decision:** treat "Downfall" as **a working title only**. Run a proper trademark search (USPTO and EUIPO) before any public use. Candidate replacements are in `DOWNFALL_FACTIONS_AND_NAMES.md`. None are cleared until searched.

## 9. Still to research (not yet done)

- Plant natural products and enzyme design (for WREN's mechanism).
- Forecast degradation and plant stress chemistry (for the climate beat).
- Age-rating questionnaire scoring (Apple and Google).
- iPhone Safari camera and WebGL behaviour on the target phones (a device matrix).
- Music licences for a public release.
- Tone study of cyberpunk and noir for humour and atmosphere (done in the faction doc by memory; check a few reference works for pacing).
- A real trademark search for the final title and faction names.
