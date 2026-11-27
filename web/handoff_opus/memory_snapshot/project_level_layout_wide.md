---
name: level-layout-wide
description: "Owner's chosen level layout (2026-11-20): the wide open course (long_s7 style, about 25 m of open ground each side, trees flying past); the narrow winding forest trail is not wanted"
metadata:
  node_type: memory
  type: project
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-20T19:17:13.037Z
---

Owner: "right away wider is the version i want as far as layout and level design. just enough range for options but still good immersion with trees flying by." The wide open courses (long_s7, long_s42, bar_psy: feat_off 15, open half-width about 25 m, board limit 31.5 m by default) are the base layout. The narrow winding trail (long_w11 and the seven biome courses long_alpine/candy/egypt/tunnel/desert/matrix/synthwave, all generated with WINDING=1, feat_off 6.5, about 13 m open) is not the target.

**Why:** the steering needs lateral range for fine-tuning toward targets in the path AND wide reach for targets off to the side; the narrow trail has nowhere to test or play that.

**How to apply:** new or regenerated courses use the wide setting (godot/tests/dump_long.gd without WINDING=1, split with web/tools/split_level.py); the eight world courses should be regenerated wide when the owner agrees; place off-line targets within about 12-23 m of the line (inside the open ground). Related: [[whole-vision-gentle-stakes]]
