---
name: checkpoint
description: Write the current session's state to the mstack session memory file now, so it survives compaction or a restart. Use when the user asks to checkpoint, save progress, save the session, write session memory, or says they are about to compact, clear or step away, and before running /compact manually.
---

# Checkpoint session memory

1. Get the file: run `mstack session` (it prints the path and creates the file from the template if needed). If `mstack` is not on PATH, use `${CLAUDE_PLUGIN_ROOT}/bin/mstack`.
2. Read the file as it is now.
3. Update it:
   - **Goal**: what the user wants, in their words, and the problem behind it. Correct it if the goal moved.
   - **State**: rewrite the whole section. What is done, what is in progress (which files, what is left), the exact next step.
   - **Decisions**: append each new decision and why.
   - **Facts and gotchas**: append exact commands, paths, values, error messages and their fixes.
   - **Open questions**: what is undecided or waiting on the user. Remove the answered ones.
4. Leave the `mstack:auto-snapshot` block untouched. A hook owns it.
5. Tell the user in one line that the checkpoint is written, with the path.

Write for a capable engineer who never saw this conversation and has to continue from the file alone. Specific beats long: name the file, the function, the command, the value. Do not narrate the session; record where things stand.

If this session produced a real discovery that every future session should know, mention it and offer `/mstack:remember`. Do not write a core memory as a side effect of a checkpoint the user asked for.
