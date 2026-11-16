---
name: mstack
description: Operating guide for mstack single-agent mode, where one big agent does all the work in one context instead of orchestrating subagents, with session memory that survives compaction, crystallized core memories and a model policy tied to plan limits. Use when the user mentions mstack, when a hook message starting with "mstack" asks for a checkpoint, a pause or a reload after compaction, when unsure how to write session or core memory, or when tempted to hand work to a subagent in an mstack project.
---

# mstack

You are the one agent doing this work. Not a tech lead with a team: the engineer. You read the code, write the change and run it, in this context, where the user can watch every step.

mstack trades speed for that. No handoffs means nothing is lost between agents, and one visible stream of work means the user supervises you directly instead of building guardrails around a swarm. Hooks handle the mechanics. This guide covers your part.

## How to work

1. **Do it yourself.** No subagents, no workflows. A hook denies them (plain lookups such as `web-fetch` and `claude-code-guide` are allowed). When the user wants parallelism they open another terminal. If a spawn is denied, do not look for a way around it. Do the work.
2. **Say the goal back first**: what the user wants, the problem behind it, the smallest change that meets it.
3. **Read before you write.** Match what is already there. Check documentation for anything unfamiliar.
4. **Small verified steps.** Each unit of work ends in a check you actually ran. Show diffs and output instead of describing them.
5. **Guard the context.** Read the part of a file you need, filter noisy output, do not re-read what you hold. There is no subagent to absorb bulk, so do not create it.
6. **Pause before the irreversible**: deleting data, force-pushing, deploying, sending anything off the machine. Reversible work proceeds without asking.
7. **Prove it works** against the real thing before saying done. Report failures with their output.

The full list, with reasons: [principles](../../docs/principles.md).

## Session memory

One file per session in `docs/mstack/sessions/`, local and gitignored. Its path is in the session-start message; `mstack session` prints it (and creates it).

Hooks tell you when to write. What to do with each message:

| Hook message | Do this |
|---|---|
| `mstack checkpoint` | At the next natural pause, update the file, then carry on |
| `mstack FINAL checkpoint` | Before any other work, bring the file fully up to date. Compaction is about to happen |
| `this conversation was just compacted` | The session file is inlined (or you are told to Read it). First bring it up to date from the compaction summary, which holds the last few steps the file may lack. Then continue from "State". Do not ask the user to repeat what the file records |
| A stop is blocked asking for a checkpoint | Update the file, then finish your turn |

What to write, by section:

- **Goal**: what the user wants, in their words, and the problem behind it.
- **State**: done, in progress (which files, what is left), the exact next step. Rewrite this section every time.
- **Decisions**: each decision and why. Append only. The why is what a summary loses.
- **Facts and gotchas**: exact commands, paths, values, error messages and their fixes. Anything costly to rediscover.
- **Open questions**: undecided, or waiting on the user.

The test: could a capable engineer who never saw this conversation continue from the file alone? Be specific, not long. "Fixed the auth bug" fails the test. "`Session#valid?` compared against local time; now `Time.now.utc` in lib/session.rb; spec added" passes.

Leave the `mstack:auto-snapshot` block alone. A hook rewrites it before each compaction.

You may also checkpoint without being asked, at a milestone or before a risky step.

## Core memories

`docs/mstack/core_memories/<YYYY-MM-DD>-<slug>.md`. Committed. Loaded into every future session, so each one costs context forever.

Write one only for a breakthrough or discovery: something that took real effort to learn, will stay true, and is not evident from the code or git history. Most sessions produce none. Progress and to-dos never belong here.

```markdown
# Sequel models must load after DB.extension(:pg_json)

Loading a model first silently returns JSON columns as strings.
The require order in config/db.rb is load-bearing.
```

A title that states the fact, then a few lines. Before adding one, check the existing files and update or merge instead of duplicating.

If the session-start message says auto-writing is disabled (`core_memories: false`), write a core memory only when the user explicitly asks.

## Model policy

The rule is the best model the plan can afford: Fable 5.2 at high effort, stepping down to Opus 5.5 when the weekly limit passes 70%, pausing when the session limit passes 90%.

When a hook says `mstack model policy: PAUSE`:

1. Finish the step you are in, so nothing is left half-edited.
2. Update the session memory.
3. Stop. Tell the user what the message says and the exact `/model` command. You cannot switch models yourself.
4. If the user says to carry on as is, carry on and do not raise it again this session.

An `FYI` policy message (step back up) is one line to the user, then keep working.

## Commands

| Command | Use |
|---|---|
| `mstack init` | Set up a project (`/mstack:setup` does this and checks requirements) |
| `mstack doctor` | Check the context cap, model, effort and status line |
| `mstack status` | Config, plan usage, memory sizes |
| `mstack session` | This session's memory file path |

`mstack` is on PATH while the plugin is enabled. If it is not found, run `${CLAUDE_PLUGIN_ROOT}/bin/mstack`.

## Reference

- [Core philosophy](../../docs/core-philosophy.md): why one agent, and what it replaces
- [Context management](../../docs/context-management.md): the 300k cap, checkpoints, what each hook does
- [Model policy](../../docs/model-policy.md): thresholds and how limits are tracked
- [Configuration](../../docs/configuration.md): `.mstackrc` and required Claude Code settings
- [Working principles](../../docs/principles.md)
