# Context management

mstack keeps one agent productive across a long session by doing three things: capping the context window, getting the important state onto disk before the cap is reached, and loading it back right after compaction.

## The cap: auto-compaction at 300k tokens

Claude Code compacts a conversation (replaces it with a summary) when it reaches the auto-compaction window. mstack requires that window to be **300,000 tokens**.

Set it once in `~/.claude/settings.json`:

```json
{ "autoCompactWindow": 300000 }
```

or run `/autocompact` in Claude Code, or set `CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000`. A per-model value under `modelSettings.<model-id>.autoCompactWindow` takes precedence over the top-level key. The allowed range is 100,000 to 1,000,000.

Why a cap at all, on a model with a far bigger window:

- **Cost and speed.** Every request resends the window. A 300k window is several times cheaper and faster per turn than a full one, which matters when the plan has a weekly limit.
- **Quality.** A model reasons best when the relevant facts are a large share of what it is reading. An uncapped window fills with stale tool output.
- **Predictability.** A known cap makes compaction a routine, planned event instead of a surprise at the worst moment.

`.mstackrc` holds the same number as `context.cap_tokens`. The two must match; `mstack doctor` checks it.

## Compaction is lossy, so write things down first

A compaction summary is written by a model in one pass, under pressure, about everything at once. It keeps the gist and drops the specifics: the exact command that worked, the reason a decision went one way, the half-finished edit. mstack does not rely on it.

### Session memory

`docs/mstack/sessions/<YYYYMMDD-HHMMSS>-<session-id>.md`, one file per Claude Code session. **Local only**: `mstack init` adds `docs/mstack/sessions/` to `.gitignore`, and the SessionStart hook puts the entry back if it disappears.

The file has five sections:

| Section | Contents | How it is maintained |
|---|---|---|
| Goal | What the user wants, in their words, and the problem behind it | Written once, corrected if the goal moves |
| State | Done, in progress, the exact next step | Rewritten at every checkpoint |
| Decisions | Each decision and why | Append only |
| Facts and gotchas | Exact commands, paths, values, fixes | Append only |
| Open questions | Undecided, or waiting on the user | Kept current |

The test for a good session file: could a capable engineer with no access to the conversation continue the work from this file alone?

### Checkpoints

Hooks have no token counts on stdin, so mstack reads the session transcript: the API usage on the last assistant record is exactly how full the window was, and the tool result or prompt the hook is reporting is added on top.

Claude Code does not wait for the window to be full. It keeps room for the reply and for the summary, and compacts about **33k tokens below the cap**: near 267k with a 300k cap (measured across some ninety compactions), near 67k with a 100k cap. mstack calls this the **compaction point** (`cap_tokens - compact_reserve_tokens`) and places its checkpoints at **50%, 70% and 88%** of it. At a 300k cap that is about 134k, 187k and 235k, which leaves the final checkpoint roughly 32k of headroom.

| Event | What happens |
|---|---|
| Context crosses 50% or 70% of the compaction point | The agent is told to update the session file at the next natural pause |
| Context crosses 88% (the last checkpoint) | **Final checkpoint.** The agent stops other work and brings the file fully up to date. If the window produced a real discovery, it writes one core memory |
| The agent ends its turn without having updated the file after a checkpoint | The Stop hook blocks once and asks again |
| Compaction starts (auto or manual) | The PreCompact hook writes a mechanical snapshot into the file (recent user prompts, files edited, the git working tree and recent commits) and tells the summarizer the file exists |
| Compaction finished | The SessionStart hook loads the session file and core memories into the new window, and has the agent reconcile the file with the summary before it continues |

Each checkpoint is announced once per window. After a compaction the first reading becomes the new baseline, and the checkpoints above it are armed again.

The mechanical snapshot is a safety net. It guarantees a trail even if the agent never checkpointed, but it only knows what happened, not why. The agent's own notes are the real memory. The git section matters because agents often write files through the shell, which no edit log sees.

### After compaction

The first thing in the new window is a message from the SessionStart hook: the conversation was compacted, the session file is the authoritative record, here it is. A file too large to inject (Claude Code caps an injected string at 10,000 characters) is replaced by an instruction to Read it, which always works.

**Reconcile first.** A checkpoint is always a little behind: work continues between the last checkpoint and the compaction, and one large step (a long file written in a single call, a big test log) can jump straight past the final checkpoint. So the hook's message also tells the agent to bring the file up to date from the summary before any other work, while the summary is the freshest thing in the window. If the agent wrote nothing to the file in the window that ended, the message says so in stronger words. The Stop hook enforces this like any other checkpoint.

The agent then continues from the "State" section and does not ask the user for things the file already answers.

## Core memories

`docs/mstack/core_memories/<YYYY-MM-DD>-<slug>.md`. Short, crystallized, **committed** facts that every future session in the project should start with.

```markdown
# Sequel models must be loaded after DB.extension(:pg_json)

Loading a model before the extension silently returns JSON columns as strings.
Require order in `config/db.rb` is load-bearing.
```

Rules:

- **A few lines each.** A title that states the fact, then at most a short paragraph. `mstack doctor` flags a memory over about 200 tokens.
- **Sparingly.** A core memory is for a breakthrough or a discovery: something that cost real effort to learn and will stay true. Most sessions produce none. Progress, status and to-dos belong in session memory.
- **Not what the repo already says.** Nothing that is evident from the code, the README or git history.
- **When they are written.** When the user asks (`/mstack:remember`), or when the agent recognizes a breakthrough, typically at the final checkpoint before a compaction.
- **Opt out.** `core_memories: false` at the top level of `.mstackrc` stops the agent from adding them on its own. An explicit request from the user still works.

### Loading and the size check

At every session start the hook measures the core memories:

- Within the budget (`context.core_memories_budget_tokens`, default 1,500): loaded into context in full.
- Over the budget: **not** loaded. The agent gets a one-line index, is told they need consolidating, and reads the relevant ones on demand.

A memory set that keeps growing stops being core. Merge and delete.

## Starting and resuming sessions

- **New session.** Core memories are loaded. Earlier session files are listed by path but not loaded; the agent reads one only when the user is continuing that work.
- **After `/clear` or a resume.** Same as a new session; the file for a resumed session is found by its session id.
- **A project that never ran `mstack init`.** No memory files are created. The single-agent rule and the model policy still apply, and the agent is told how to initialize.

## The hooks

| Hook | Does |
|---|---|
| SessionStart | Startup: rules, memory locations, core memories, setup problems. After compaction: reloads session memory |
| UserPromptSubmit, PostToolUse | Context checkpoints and model policy notices |
| PreCompact | Mechanical snapshot into the session file, instructions for the summarizer |
| Stop | Enforces an ignored checkpoint, once |
| PreToolUse (Agent, Task, Workflow) | Single-agent guard |

A hook never breaks a session: any failure is logged to `~/.claude/mstack/error.log` and the hook exits silently.
