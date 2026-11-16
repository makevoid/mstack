---
name: remember
description: Crystallize a breakthrough or discovery into a short, committed mstack core memory that every future session in the project starts with. Use when the user asks to remember something permanently, save a core memory, or says a finding should never be lost, and when a final checkpoint prompts for a core memory after a real discovery.
argument-hint: "[what to remember]"
---

# Write a core memory

Core memories live in `docs/mstack/core_memories/`, are committed with the project, and are loaded into every future session. Each one costs context forever, so the bar is high and the form is short.

## Is it a core memory?

Yes, when all three hold:

- It took real effort to learn (a debugging session, a failed approach, a surprising constraint).
- It will stay true for a long time.
- It is not evident from the code, the README or git history.

No, when it is progress, status, a to-do, a preference for this task, or something a reader of the code would see anyway. Those belong in session memory (`/mstack:checkpoint`).

When the user explicitly asks to remember something, write it. They decide. If it looks like session state rather than a lasting fact, say so in one line and write it anyway, short.

When the prompt came from a hook and `core_memories: false` is set in `.mstackrc`, do not write one.

## Write it

1. Read the existing files in `docs/mstack/core_memories/`. If one already covers this, update it instead of adding a second. If the new fact makes an old one wrong, fix or delete the old one.
2. Create `docs/mstack/core_memories/<YYYY-MM-DD>-<short-slug>.md`:

   ```markdown
   # Sequel models must load after DB.extension(:pg_json)

   Loading a model first silently returns JSON columns as strings.
   The require order in config/db.rb is load-bearing.
   ```

   - The title states the fact itself, not its topic. "Port 9797 is hard-coded in the CI proxy", not "Notes about ports".
   - Then one to five lines: what is true, why, and where to look. Under about 120 words.
   - No session narrative, no dates in the body, no "we found that".
3. Run `mstack doctor` and check the `core memories` line. If the set is over budget, tell the user and offer to consolidate.
4. Tell the user what you wrote, in one line, with the path. Do not commit unless asked.
