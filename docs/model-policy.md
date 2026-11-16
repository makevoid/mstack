# Model policy

**Always use the top model you can afford.** There are no per-role model tiers in mstack, because there are no roles. One agent does everything, so the only question is which model your plan limits can pay for right now.

## Defaults

| Setting | Default | `.mstackrc` key |
|---|---|---|
| Model | Fable 5.2 (`claude-fable-5-2`) | `model.default` |
| Reasoning effort | `high` (`xhigh` is accepted) | `model.effort`, `model.effort_max` |
| Fallback model | Opus 5.5 (`claude-opus-5-5`) | `model.fallback` |
| Weekly limit step-down | 70% | `limits.weekly_switch_pct` |
| Session limit pause | 90% | `limits.session_pause_pct` |

**Why `high` and not `max`.** More reasoning is not always better. Above high, each step costs noticeably more time and usage for a smaller gain, and the extra deliberation can make an agent slower to act on things that are already clear. High is the default, xhigh is worth it for a hard design problem, max is rarely the right standing setting.

## The rules

1. **Weekly limit at 70% or more, on the default model: step down to the fallback.** With 30% of the weekly allowance left and a cheaper model, you still have a lot of work available before the week resets, and the first 70% was spent on the best model. Staying on the top model would risk running dry before the reset.
2. **Current session limit at 90% or more, on the default model: pause and ask.** The session default stays Fable 5.2 until this point. The user either switches to the fallback to keep going, or waits for the session window to reset.
3. **Limits have room again and the session is on a lesser model: step back up.** After a weekly reset there is no reason to stay on the fallback. This one is a one-line suggestion, not a pause.

Rule 1 wins when both limits are hot. On the fallback model the policy stays quiet.

## How it works

Claude Code exposes plan limits only to the **status line** command (`rate_limits.five_hour` and `rate_limits.seven_day`, for Claude subscribers, after the first response of a session). Hooks do not receive them. So:

1. The mstack status line records every payload it receives under `~/.claude/mstack/usage/`.
2. On every user prompt and after every tool call, a hook reads that snapshot, takes the current model from the session transcript, and asks the policy for a decision.
3. A decision other than "ok" is injected into the agent's context once per session.

Limits are account-wide, so a new session uses the most recent snapshot from any session until its own status line has rendered. A snapshot older than six hours (`limits.stale_after_minutes`) is ignored.

**Without the mstack status line there is no limit tracking.** `mstack doctor` reports this, and `/mstack:setup` installs it. It can wrap an existing status line command, so nothing you already have is lost:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/mstack/statusline --wrap 'bash ~/.claude/statusline-command.sh'"
  }
}
```

`~/.claude/mstack/statusline` is a small launcher that mstack regenerates when the plugin moves, so the setting stays valid across plugin updates.

## Why it pauses instead of switching

Claude Code gives hooks no way to change a session's model. Only the user can, with `/model`. So "switch automatically" becomes the closest thing that is actually possible:

- The agent finishes the step it is in, so nothing is left half-edited.
- It updates the session memory.
- It stops and tells the user exactly what to run, for example `/model claude-opus-5-5`.
- The status line shows the same instruction until the switch is made.

If the user says to carry on with the current model, the agent carries on and does not raise it again in that session.

## Changing the policy

```yaml
# .mstackrc
model:
  default: claude-fable-5-2
  fallback: claude-opus-5-5
  effort: high
limits:
  weekly_switch_pct: 70
  session_pause_pct: 90
```

On a plan where Opus is the best model you have, set `default: claude-opus-5-5` and `fallback: claude-sonnet-5-5`. The rules stay the same.
