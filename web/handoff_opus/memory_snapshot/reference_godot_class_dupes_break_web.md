---
name: reference-godot-class-dupes-break-web
description: Copies of .gd files with class_name inside the Godot project folder silently break the web export (classes missing from the pck cache, the page falls back to the wrong level)
metadata:
  type: reference
---

On 2026-11-18, snapshot copies of RunRig.gd, Themes.gd etc. under godot/tools/looks/ made Godot register each class_name twice; the exported pck then lacked those classes and the deployed page showed the old shooter level with "Could not find type RunRig" in the console. Desktop headless compile did NOT show it. Fix: a `.gdignore` in godot/tools/looks/ (added). Never put .gd copies inside the project without a .gdignore. To verify a deploy: check that build/web/index.*.pck contains `"class": &"RunRig"` and load the page in the browser pane. deploy.sh now runs `--import` first.
