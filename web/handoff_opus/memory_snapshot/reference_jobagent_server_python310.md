---
name: reference_jobagent_server_python310
description: jobagent VPS runs Python 3.10 while the local venv is newer; f-string quoting that works locally can crash the live service
metadata:
  node_type: memory
  type: reference
  originSessionId: d211752e-574d-4c02-84f3-838c3de62eb7
  modified: 2026-11-12T23:13:34.980Z
---

The jobagent VPS (`/opt/jobagent/.venv`) runs Python 3.10.12. The local Windows venv accepts newer syntax, such as the same quote type nested inside an f-string expression: `f"{fn("x")}"`.

**Why:** On 2026-11-12 deploying notify.py with `f"{_header(site, "Welcome", "...")}"` crashed the service in a restart loop (503 for about a minute) with `SyntaxError: f-string: unmatched '('`. Local tests passed.

**How to apply:** Before restarting after a deploy, copy the changed .py files to /tmp on the server and run `/opt/jobagent/.venv/bin/python -m py_compile <file>`, or avoid nested same-type quotes and backslashes inside f-string expressions. See [[project_jobagent_rename_pending]] for the project context.
