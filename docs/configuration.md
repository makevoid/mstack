# Configuration

Two places hold configuration: Claude Code's own settings (the requirements), and `.mstackrc` in each project (mstack's options).

## Requirements: Claude Code settings

mstack reads these and never edits them on its own. `/mstack:setup` proposes the changes and applies them only when you agree. `mstack doctor` checks them.

`~/.claude/settings.json`:

```json
{
  "model": "claude-fable-5-2",
  "effortLevel": "high",
  "autoCompactWindow": 300000,
  "statusLine": {
    "type": "command",
    "command": "~/.claude/mstack/statusline"
  }
}
```

| Setting | Required value | Why |
|---|---|---|
| `autoCompactWindow` | `300000`, equal to `context.cap_tokens` | The context cap. Required. See [context-management.md](context-management.md) |
| `model` | The default or the fallback model | The best model you can afford. See [model-policy.md](model-policy.md) |
| `effortLevel` | `high` (up to `xhigh` passes) | The reasoning sweet spot |
| `statusLine` | A command that runs `mstack statusline` | The only way to see plan limits. Add `--wrap '<your command>'` to keep an existing status line |

Auto-compaction must be enabled (no `DISABLE_AUTO_COMPACT`, `autoCompactEnabled` not `false`).

## `.mstackrc`

A YAML hash at the project root. `mstack init` writes it with every option at its default. Every key is optional. An invalid file falls back to defaults, and the problem is reported at session start.

```yaml
core_memories: true
subagents: false

context:
  cap_tokens: 300000
  checkpoints: [50, 70, 88]

model:
  default: claude-fable-5-2
  fallback: claude-opus-5-5
  effort: high
  effort_max: xhigh

limits:
  weekly_switch_pct: 70
  session_pause_pct: 90
```

| Key | Default | Meaning |
|---|---|---|
| `core_memories` | `true` | `false` stops the agent from writing core memories on its own. A direct request from the user still works |
| `subagents` | `false` | `true` lifts the single-agent guard for this project |
| `allowed_subagents` | `[web-fetch, claude-code-guide, statusline-setup]` | Subagent types that stay allowed as plain lookups |
| `context.cap_tokens` | `300000` | The context cap. Must equal `autoCompactWindow` |
| `context.compact_reserve_tokens` | `33000` | How far below the cap Claude Code really compacts. `cap_tokens` minus this is the compaction point |
| `context.checkpoints` | `[50, 70, 88]` | Percent of the compaction point at which session memory is checkpointed. The last one is the final checkpoint |
| `context.core_memories_budget_tokens` | `1500` | Core memories larger than this in total are not auto-loaded |
| `context.session_memory_budget_tokens` | `12000` | A session file larger than this is trimmed in the middle when reloaded |
| `model.default` | `claude-fable-5-2` | The top model |
| `model.fallback` | `claude-opus-5-5` | The model to step down to |
| `model.effort` | `high` | Recommended reasoning effort |
| `model.effort_max` | `xhigh` | Highest effort that still passes the check. `max` is flagged by default |
| `limits.weekly_switch_pct` | `70` | Weekly limit percentage that triggers the step-down |
| `limits.session_pause_pct` | `90` | Session limit percentage that triggers the pause |
| `limits.stale_after_minutes` | `360` | Usage snapshots older than this are ignored |

## Files mstack creates

| Path | Committed | Contents |
|---|---|---|
| `.mstackrc` | Yes | Project options |
| `docs/mstack/core_memories/*.md` | Yes | Crystallized core memories |
| `docs/mstack/sessions/*.md` | No, gitignored | Per-session memory |
| `~/.claude/mstack/usage/` | Local | Plan usage snapshots from the status line |
| `~/.claude/mstack/state/` | Local | Per-session hook state |
| `~/.claude/mstack/statusline` | Local | Status line launcher |
| `~/.claude/mstack/error.log` | Local | Hook failures |

## Commands

```
mstack init        set up this project
mstack doctor      check the requirements
mstack status      config, plan usage, memory sizes
mstack session     print (and create) this session's memory file path
mstack statusline  status line command
```

Skills: `/mstack:mstack` (the operating guide), `/mstack:setup`, `/mstack:checkpoint`, `/mstack:remember`, `/mstack:status`.

## Environment

| Variable | Effect |
|---|---|
| `MSTACK_HOME` | Where mstack keeps local state. Default `~/.claude/mstack` |
| `CLAUDE_CONFIG_DIR` | Claude Code's config directory, honored when locating settings |
