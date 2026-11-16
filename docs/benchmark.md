# Benchmark

mstack is tested end to end by having one headless Claude Code session build a real application with the plugin loaded and a deliberately small context cap. The cap forces several compactions inside one task, so the memory machinery runs for real instead of in a unit test.

## The task: Tasklane

A todo-list web application: **Roda** routing, **Sequel** on a local **SQLite** database, **HAML** views, **Tailwind CSS**, and an **RSpec + rack-test** suite. The full specification is [benchmark/PROMPT.md](../benchmark/PROMPT.md).

It was designed to be a good memory test, not only a coding test:

- **Eight phases** (skeleton, lists, todos, tags, filters, soft delete, JSON API, finish), each ending in a green suite and a commit. Too much for one small window.
- **Exact domain rules stated once, at the start**: priority is `low` / `normal` / `urgent` and never `high`; slugs truncate at 40 characters and deduplicate with `-2`; at most 5 tags and a sixth is an error; undated todos sort last; soft-deleted todos vanish from every count. A rule stated in the first minutes has to survive every compaction to be honored in phase 7.
- **Two surfaces over one set of rules** (HTML and a JSON API), so late phases depend on decisions made in early ones.
- **Decisions left open on purpose**, so the agent has reasoning of its own worth recording.

The prompt never mentions mstack. Everything mstack does in the run is driven by hooks.

## How it is run

```bash
rake benchmark:run       # ruby benchmark/run.rb [--cap 100000] [--model ...] [--effort ...]
rake benchmark:verify    # ruby benchmark/verify.rb [run]
```

The runner creates a fresh git repository under `~/.cache/mstack/benchmark/<run>/app`, runs `mstack init`, sets `context.cap_tokens` and `autoCompactWindow` to the cap (100,000 by default, the smallest value Claude Code accepts), and starts `claude -p` with `--plugin-dir` pointing at this repository. Hook state for the run is isolated in the run directory.

Runs live outside this repository because Claude Code treats files under a loaded plugin's directory as sensitive and refuses to edit them.

## What is verified

`benchmark/verify.rb` reads the session's event stream and the resulting files:

| Area | Checks |
|---|---|
| Session | Finished without error; no hook failures logged |
| Context | The cap was reached and the session compacted; peak context stayed under the cap |
| Memory | Checkpoints were requested; the agent wrote real session memory, and did so before the first compaction; the PreCompact snapshot is present; memory was reloaded after every compaction; the session file is gitignored and never committed; core memories stayed sparing |
| Single agent | No subagent or workflow was spawned |
| App | The app's own suite passes; the **hidden acceptance probe** passes; work was committed phase by phase |

The hidden probe ([benchmark/probe/acceptance_spec.rb](../benchmark/probe/acceptance_spec.rb)) is a rack-test suite the agent never sees. It exercises every domain rule through the public HTTP surface, which is the real measure of whether the rules survived the compactions.

## Results

See [benchmark-results.md](benchmark-results.md) for recorded runs.
