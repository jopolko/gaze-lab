---
name: gaze-lab-layout
description: "Project folder is projects/gaze-lab; VPS paths under /var/www/html/gaze-lab/{godot,godot-dev,eyelab}; planned public repo"
metadata:
  node_type: memory
  type: project
  originSessionId: 1804e927-9051-4067-9f2d-f1c299a3cedd
  modified: 2026-11-12T13:18:07.292Z
---

Local project moved (copied) 2026-11-12 from projects/godot to projects/gaze-lab (old projects/godot still exists as a locked duplicate; delete when possible).

VPS (ssh nowservingto), restructured 2026-11-12: /var/www/html/gaze-lab/godot (live), /gaze-lab/godot-dev (my test build, formerly godot-claude), /gaze-lab/eyelab. Old /godot/, /godot-claude/, /eyelab/ hold only an .htaccess 302 redirect (query kept). 68 site pages still link to the old /godot/?level=... and /eyelab/ (nav baked in, edit via sudo python3 on the VPS) - rewrite later.

Deploy test builds to godot-dev only, never the live godot, unless asked.

Plan: public GitHub repo "gaze-lab" (one repo: godot/ subfolder, eyelab/, web/ for three.js). Before pushing: squash to one commit (history has mjopolko@gmail.com + ssh host names), remove claude-settings.recommended.json, .gitignore build/.godot/*.import, scrub deploy host/path in notes, README + licence. Needs user to run `gh auth login`. Awaiting answers: noreply email, licence (suggested MIT), squash vs filter-repo.

**Why:** user wants eye-tracking experiences repo, public. **How to apply:** use these paths in deploy commands; don't push until the open questions are answered.

**Update 2026-11-12:** repo is live at github.com/jopolko/gaze-lab (public, all rights reserved, commits as joshua.opolko@gmail.com). The "Carve" game was renamed **Downhill** (user: "carve is a rip-off of the vr game"): class `RunRig` (scripts/RunRig.gd), `Game.run_mode`, tests/run_test, `?level=downhill`. The old three-lane game is now **Downhill Lanes** (`?level=lanes`, level 8). Never use "Carve" as a public name. Test build: /gaze-lab/godot-dev/?level=downhill. Design under discussion: snowballs (squint to break) and food pickups (wide eyes to eat).
