# Why we misunderstand each other and miss things (written 2026-11-20, from this session)

Written by Claude for the owner to read later. These are patterns I can see in this session, with the actual moments. Not all of it is fixable by either of us; the last section lists things that would help.

## 1. I build the thing named, not the thing meant
- You asked for a panel with the head-coupled view parameters "esp for mobile". I built a panel for those. You meant the control panel for everything we had tuned, and the head-signal mix ("the head axis stuff") was the one you went looking for and did not find. It existed only in the steering lab and as `&mix=split`. I had the whole list of controls in front of me and did not check the panel against it.
- Earlier: "put the lab on the playable level" became a separate lab page first. "Make it softer" became one smoothing number. "Fix the tuning at what we just did" was a sentence I could have done and recorded in one step, but I let it become part of a longer answer.
- Pattern: a request names one item, and the real wish is "make all of this controllable / consistent / complete". I answer the item. The fix is to ask myself, every time, "what is the full set this belongs to?" and check my work against that set before saying done.

## 2. Words that mean several things, and I pick one silently
| Word | What I took it to mean | Other things it could mean |
|---|---|---|
| "head axis" | the signal mix selector | the head-coupled (window) axes, the PCA axis, which way is left/right |
| "lean" vs "tilt" vs "turn" | three different head signals (turn = yaw, tilt = roll, lean = sideways position) | you use "lean" for tilt too ("if i tilt my head left or right it already turns more aggressively") |
| "mobile link" | the test copy (`js=gv_dev.js`) | the main link |
| "soft" / "loose" / "mushy" | too much smoothing, or too much lag, or too sensitive | I treated them as three separate causes and measured; you might have meant one feeling |
| "tracking" | the camera and model | the steering feel after the camera |
| "meter" | the steering scope/readout | the head bar |
| "buffs", "pickups", "molecules" | different things in the story and the code | used loosely in speech |
- Pattern: I decide silently and build. The cost shows up later, as "that's not what I meant".
- Fix: a short shared glossary (turn, tilt, lean, window, aim, direct, steer, split, test copy, main link) kept in one file and used in every reply.

## 3. "Done" in my words is not "done" for you
- I said "loads with no errors" many times. That was true, and it was also all I had tested, because my browser pane has no camera and no phone. You then found what loading doesn't show: the white page, VEGIM, the REACH clash, the ramp slip-out, the music silence. Several of those I could have anticipated by tracing the code path from your side (for example: head mode starts without a tap, so the browser blocks audio).
- I also reported results with hedges in some replies and without in others, so you could not tell "verified" from "should work".
- Fix: I will label each result one of three ways: **tested with a real head/phone by you**, **tested by me with the page only**, **not tested**. And I will trace the user's path (tap, permission, camera, start) before calling something ready.

## 4. Your standing rules vs how I actually behave
You told me (and I saved): short sequential replies; proceed without asking; no band-aids, consider the whole vision; never blame the hardware; don't push untested things to the main link; give test URLs.
What I still do:
- Long replies with several topics, tables and headings, when you wanted one step.
- Ending with a question on things where you had already said "just do it" (and, the reverse, going ahead on things that deserved one line first).
- Silent stretches of tool work. You had to ask what I was doing more than once, and you interrupt when I test instead of delivering.
- Quick fixes where the cause was bigger (the ramp slip-out took three passes: gentle pull, then side catch, then the aim override).
- Fix: after any request, one line of "what I understood and will do", then do it; replies in the order of your question; no more than one question, and only when I truly cannot proceed.

## 5. Things get lost between messages and between context windows
- Your requests accumulate: in-game tuning overlay with auto-optimize, regenerate wide courses, saw placement, magnet and wings, gaze orbs, music intro, panel for everything, the sandbox panel. I carry them in a summary that drops detail. The panel request after the head-coupled view is an example: it was clear in the moment, and the "everything tunable" part did not survive my narrower reading.
- Fix: one running file of **your asks with their status** (asked / built / tested by you / done). I update it as we go, and you can read it any time. It also gives you something to point at: "item 7 is wrong".

## 6. Too many versions of the thing
- Main link, test copy, lab, mobile vs PC links with different settings, address-bar settings, saved settings in the browser that override the address bar. You were right to ask "what's the best latest URL" more than once.
- Fix: one link per device, always the latest, with the settings in the panel and not in the URL; the main link only changes when you say so. Saved-in-browser overrides shown in the panel (the orange values) so nothing is hidden.

## 7. I explain how, you want to know what it feels like and what to do
- I gave mechanisms (critically damped spring, off-axis frustum). You wanted: does it feel better, what do I press. Some of my answers were right but sat inside a lot of explanation.
- Fix: lead with what to try and what to look for; mechanism only if asked.

## 8. Where I was right to push back, and where I wasn't
- Right: head-coupled view cannot keep your eyes straight ahead with a fixed screen. Wrong to bury it: say it in one sentence first.
- Wrong: I assumed phones and PCs wanted the same steering. You told me they don't (large screen for lean, phone maybe not at all).

## What would help most, in order
1. A single **asks list** file that I keep current (section 5).
2. A one-page **glossary** (section 2).
3. **Honest status labels** on every claim (section 3).
4. One consolidated **panel** with every control (section below), so "where is X" always has the same answer.

## The panel as a sandbox for players (your idea)
Your reaction to the panel is a strong signal: sliders that change the game live and a reset arrow per control are what you reached for every time. Making it a player feature fits the game: trippy effects the player tailors.
- **What it would hold:** the six molecules' layers (colour, pattern, time, sound, space, mind) as 0–100% knobs; ring/glow/chroma/trail amounts; the window (head-coupled) view; steering feel; music mix; world look (ground, sky, realm).
- **Rules that make it good:** every knob has a plain-language line, a per-control reset, "Reset all", a few named presets ("Chill", "Full trip", "Sharp"), and Copy/Share as a link. Settings saved per device.
- **Guard rails:** a "safe" range by default (the nauseating extremes behind an Advanced toggle); the story progression unaffected (sandbox runs are marked so they don't unlock the six pieces unless the player chooses to); a one-tap "back to the designed look".
- **Why it is cheap:** the effect knobs already exist in the Godot post pass and the three.js port (the spec's effects catalogue, section 15, lists them). The panel code is built and works with any numeric setting.
- **Open decisions for you:** does sandbox unlock anything? Do we show it on phones (a smaller version)? Is it available from the start or only after the first molecule?
