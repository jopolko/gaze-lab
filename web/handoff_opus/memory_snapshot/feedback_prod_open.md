---
name: prod-open-to-changes
description: User (2026-11-21) is fine with modifying prod/main Downhill directly; stop asking before putting changes on main
metadata:
  type: feedback
---

User said "all dev, all prod" and "i'm regretting the decision to ask to protect prod. it isn't that big a deal to mod it like crazy".

**Why:** the dev/main split slowed them down; prod is only for them and a few testers.
**How to apply:** apply Downhill changes to both gv_dev.js and gv.js and deploy both (backup main first as gv_prev_mainN.js.bak). Still scan the diff before any commit, and still don't touch the son's frozen copy unless asked. Supersedes the earlier "don't deploy untested changes to main" rule for Downhill; still test before deploying. See [[feedback-autonomy]].
