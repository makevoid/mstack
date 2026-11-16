---
name: status
description: Report mstack's current state for this project, including plan usage against the weekly and session limits, the model policy, the context cap, and the size of session and core memories. Use when the user asks for mstack status, how much of their limit is used, which model they should be on, or whether mstack is set up correctly.
---

# mstack status

Run both (use `${CLAUDE_PLUGIN_ROOT}/bin/mstack` if `mstack` is not on PATH):

```bash
mstack status
mstack doctor
```

Then answer what the user asked, briefly:

- **Limits and model.** Weekly and session usage against their thresholds, and whether the current model is the right one under the policy (the default below the thresholds, the fallback once the weekly limit passes its threshold). If a switch is due, give the exact `/model` command.
- **"unknown (status line not reporting)"** means the mstack status line is not installed or has not rendered yet, so limits cannot be tracked. Point to `/mstack:setup`.
- **Setup.** Any `[FIX]` line from the doctor, with its fix. Do not edit settings from here; that is `/mstack:setup`.
- **Memory.** How many core memories and their size against the budget, and the latest session file.

Report the numbers as printed. Do not estimate a limit you cannot see.
