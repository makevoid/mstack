---
name: setup
description: Set up mstack in the current project and check its requirements, namely the 300k auto-compaction cap, the default model and effort, and the status line that tracks plan limits. Use when the user asks to set up, install, initialize or configure mstack, when a session-start message says mstack is not initialized or lists setup problems, or when `mstack doctor` reports a failure.
---

# Set up mstack

Two parts: initialize the project (safe, do it), then fix the Claude Code settings (the user's own files, ask first).

If `mstack` is not on PATH, use `${CLAUDE_PLUGIN_ROOT}/bin/mstack` in every command below.

## 1. Initialize the project

```bash
mstack init
```

This creates `.mstackrc`, `docs/mstack/sessions/` and `docs/mstack/core_memories/`, and adds `docs/mstack/sessions/` to `.gitignore`. It is idempotent. It then prints the doctor report.

## 2. Read the doctor report

Each `[FIX]` line names a requirement that is not met and how to meet it. All of the fixes below edit Claude Code settings, normally `~/.claude/settings.json`.

Those files belong to the user. Read the current file, tell the user exactly which keys you would change and to what, and make the edit only after they agree. Change only the keys listed here and leave everything else untouched.

| Doctor line | Fix |
|---|---|
| `context cap` | Set `"autoCompactWindow"` to the `context.cap_tokens` value from `.mstackrc` (300000 by default). If the report mentions a per-model value, fix `modelSettings.<model-id>.autoCompactWindow` instead, since it takes precedence. This one is required for mstack to work as designed |
| `model` | Set `"model"` to the default model (`claude-fable-5-2`), or tell the user to run `/model claude-fable-5-2` |
| `effort` | Set `"effortLevel"` to `"high"` |
| `usage tracking` | Install the status line, below |
| `core memories` | Over budget or too long: offer to merge and trim the files in `docs/mstack/core_memories/` |
| `config` | `.mstackrc` is invalid YAML: show the error and fix it with the user |

### The status line

Plan limits reach mstack only through the status line, so without it the model policy is blind. `mstack init` installed a stable launcher at `~/.claude/mstack/statusline`.

- No existing `statusLine` in the settings:

  ```json
  "statusLine": { "type": "command", "command": "~/.claude/mstack/statusline" }
  ```

- An existing `statusLine` command: keep it, wrapped. mstack records the usage and prints the user's own line unchanged, adding only a short alert when a model switch is due.

  ```json
  "statusLine": { "type": "command", "command": "~/.claude/mstack/statusline --wrap 'bash ~/.claude/statusline-command.sh'" }
  ```

  Put the user's existing command, exactly as it was, inside the single quotes.

## 3. Confirm

Run `mstack doctor` again and report the result plainly: what passes, and what the user chose to leave. Settings changes to the model and the context cap apply to new sessions, so say that a restart is needed for them to take effect in full.

Do not commit anything unless the user asks. If they do, `.mstackrc` and `docs/mstack/core_memories/` are meant to be committed, and `docs/mstack/sessions/` is not.
