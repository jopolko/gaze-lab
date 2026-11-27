---
name: project-anomaly
description: "ANOMALY web app (projects/anomaly): \"spirit of a place\" photo compositor with AI-generated creature pool; pivoted from the 3D face-taming slice"
metadata:
  node_type: memory
  type: project
  originSessionId: 0d59ee97-9cbc-4d75-b06f-9512492e1f4d
  modified: 2026-11-11T02:33:36.082Z
---

ANOMALY is web-only (iOS and Android must behave identically; user rejected per-platform features). As of 2026-11-10 it is a photo app: shoot an ordinary place, weather/time/light pick a pre-made Seedream creature from a pool, tap to place, name the spot, share a caption card ("SPIRIT OF THE COUCH"). Read `anomaly/NOTES.md` for run commands, code layout, art pipeline and open questions. The earlier 3D face-taming slice is archived in `src/legacy/`.

**Why:** photoreal/real-time 3D creatures weren't achievable; a curated 2D pool in a consistent "creepy-cute designer toy" style composites convincingly, avoids per-user AI cost/privacy, and the first-share trigger is a funny mundane-place photo, not the sensors. Target audience 16-28 on TikTok/Reels; avoid mythology and Pokémon-like designs.
**How to apply:** image keys live in `anomaly/.env` (OPENAI_API_KEY, OPENROUTER_API_KEY; never print). Pool generation ~$0.09/image via Seedream. The core hypothesis (people share these) is untested; suggest showing real outputs to ~5 people before adding features.

**Update 2026-11-11 (phone test):** user judged the 2D-pasted compositor "1998 Photoshop" and the app "AI slop" with no visible sensors or mechanics; the glossy 3D-render style clashes with real photos. Gemini 3.1 Flash Image edit (`tools/edit.py`, ~7c/photo) integrates lighting noticeably better (see `assets/edits/_compare.jpg`) but still reads CG. Real conflict: web-only parity + real-time embedded visuals + photoreal can't all be had; native AR (Unity AR Foundation etc.) or generative edit are the real options. Pending user decision: "photo toy" (generative edit) vs "AR game" (native). Live test build at joshuaopolko.com/anomaly/ is the weak version.

**Update 2026-11-11 (direction):** user chose Android-only and wants visual mockups of everything BEFORE spending credits on a build. Mockups in `anomaly/assets/mockups/`: `ar-mockups.html` (AR creature game screens), `ar-hook.html` (store pitch, first 60 s, return hooks), `sensor-challenges.html` (mobile-only "verified" trending sensor challenges: jump height, G-force, hold still). User's latest asks: a tool people can't easily do themselves; make trending memes easier to do; must be better on mobile than web and use sensors intelligently. AR Wi-Fi/home-X-ray utility apps already exist (NetLens, WiFi AR, NetSpot) so that is crowded. Not yet decided which direction to build.
