---
name: project-face-control-games
description: "Godot 4.7 face/head/eye-controlled game demos + EyeLab on joshuaopolko.com, with deploy and test commands"
metadata:
  node_type: memory
  type: project
  originSessionId: 1804e927-9051-4067-9f2d-f1c299a3cedd
  modified: 2026-11-09T21:33:38.828Z
---

The user's Godot project at C:\Users\josh\projects\godot is a web demo (https://joshuaopolko.com/godot/) with three
modes (Peek & Blast, Nod Flight, Eye arena) driven by a webcam via MediaPipe in the browser, plus a tracking lab at
https://joshuaopolko.com/eyelab/. Full architecture, URLs flags, deploy and test commands are in NOTES.md in the repo.

**Why:** the user wants a simple demo to feel head/eye tracking ideas on desktop and phone; they test on their own
Chrome (Logitech C920, dim office, ~15 fps) and a phone, and report back by feel.

**How to apply:** read NOTES.md first. Eyes now matter in Peek (lock/blink-fire/wink-swap) and Downhill (resolve openings by looking);
Nod Flight still ignores eyes. The user prefers the gravity/momentum Downhill over rocket-powered Flight. Deploy goes over `ssh nowservingto` to /var/www/html/godot and /eyelab (site is static Apache).
Write patch scripts to files (heredocs with triple quotes break in the shell).
