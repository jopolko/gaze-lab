---
name: no-blame-user-hardware
description: "For software we build, failures on the user's machine are our bug (never blame hardware/drivers/browser); for IT support work the normal user-side checks are fine; always say which machine data came from"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6528d112-c53d-475f-bdc3-f9d2e181e537
  modified: 2026-11-20T16:50:22.372Z
---

SCOPE: this applies to DEVELOPMENT of software we maintain (the three.js game etc.). It does NOT apply to IT support / troubleshooting someone's own device, account or network: there, user error and environment faults are common, so check them early (kindly, without blame), with short numbered steps. If a request does not say which kind it is, ask. The user may prefix requests with "Dev:" or "Support:".

For development work: when the game freezes or fails on the user's laptop, treat it as a bug in our three.js build, not their hardware, driver, browser settings or tabs.

**Why:** 2026-11-20 the user said their laptops ran the Godot build fine, and that I kept blaming their browser, drivers and "weak GPU" ("what can I put in your system message so you don't blame the user... like a typical developer"). I had also mixed up machines: this Claude session (and its browser pane) runs on the T480 (Intel UHD 620), while the user was testing on a new ThinkPad T14 Gen 5 in Edge, so I explained T14 problems with T480 data. A Chromium browser disables WebGL after repeated GPU-process crashes, so a "cannot create WebGL context" error is likely a consequence of our shader stalls, not a user problem. Later the user clarified they also do office tech support, where user error is often the cause.

**How to apply (development):**
- Compare with the last build that worked on that machine (Godot build, or an earlier three.js snapshot) and bisect our changes; use the `?diag` logging (diag.js posts to log.php, read /var/lib/gaze-lab-logs/three/<date>.jsonl on the VPS) and the saved gv.js snapshots in the temp backups.
- Do not suggest reboots, driver updates, browser settings or closing tabs as an explanation unless our code is shown not to be involved.
- State which machine any measurement came from; if unclear, ask. The session host is the T480, not the machine the user tests on.
- Weak integrated graphics is the target to support: compile shaders gradually behind the loader, degrade quality, never freeze the browser.
- Related: [[downhill-user-preferences]] [[short-sequential-replies]]
