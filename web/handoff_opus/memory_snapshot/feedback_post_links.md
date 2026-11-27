---
name: feedback-post-links
description: Post the test URLs in the reply whenever the user needs them (they close the tab to free the camera and lose the address)
metadata:
  type: feedback
---

Whenever a build is ready to test, or the user may need to reopen the game, put the clickable URLs in the reply (local `http://localhost:8060/`, LAN `https://<laptop ip>:8443/`, with `?level=downhill` for Downhill).

**Why:** the user closes the tab to release the webcam and then has to hunt for the address again.

**How to apply:** end test-ready replies with the links; re-post them when asked, with current ports from `tools/serve.py` (see [[project-gaze-lab-state]]).
