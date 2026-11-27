---
name: verify-scripted-patches
description: "When applying scripted file patches, run them in the foreground and confirm they landed; never claim a feature is deployed without checking"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 1804e927-9051-4067-9f2d-f1c299a3cedd
  modified: 2026-11-13T01:46:26.627Z
---

Scripted patches (python string-replace on GDScript) silently failed when run in the background or chained with `&&` / `;`, and I reported auto-help and earned help as deployed when they were not in the build. The user relies on these reports.

**Why:** tab indentation in pasted snippets was often off by one and shell heredocs mangled escape sequences; failures were hidden.
**How to apply:** write patch scripts with the Write tool (real tabs), run via a runner that tolerates one tab of indent and exits loudly on NOT FOUND, run in the foreground, then grep that a marker landed before running tests, exporting or telling the user. If a claim turns out false, say so plainly.
