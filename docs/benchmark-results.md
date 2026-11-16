# Benchmark results

Recorded runs of the [Tasklane benchmark](benchmark.md). Costs are the API-equivalent figure Claude Code reports; the runs were billed against a plan login.

## run1: 2026-11-16, Fable 5.2 at high effort, 100k cap

One headless session, mstack 0.1.0, `autoCompactWindow` and `context.cap_tokens` at 100,000. The prompt never mentions mstack.

**Result: 16 of 16 checks passed.**

| | |
|---|---|
| Duration | 21.2 minutes, 38 turns, 32 tool calls |
| Cost | $10.07 (100k output tokens, 1.48M cache-read, 231k cache-write) |
| Plan usage | 5-hour window 11% to 43%, weekly 50% to 53% |
| Compactions | 4, all automatic |
| Hook errors | none |
| Subagent spawns | 0 |
| App | 8 phases, 8 commits, 134 examples, 0 failures |
| Hidden acceptance probe | 38 examples, 0 failures |
| Core memories written | 0 |

### The five context windows

| Window | Started at | Checkpoints announced | Session file written by the agent | Compacted at |
|---|---|---|---|---|
| 1 | 33k | regular at 57k | at 63k | 74k (to 20k) |
| 2 | 49k | regular at 50k | at 51k | 70k (to 23k) |
| 3 | 54k | final at 62k | at 54k; the final checkpoint arrived one step before the compaction, too late to act on | 72k (to 21k) |
| 4 | 51k | final at 63k | at 51k (reconcile, covering window 3) and 64k | 90k (to 23k) |
| 5 | 53k | final at 59k | at 55k (reconcile), 60k and 64k | session finished |

"Compacted at" is Claude Code's own `pre_tokens` figure. It is higher than the last context reading because the step that crosses the line (a long file written in one call, a test log) is counted in it.

What this shows:

- **Rules stated once survived four compactions.** The exact domain rules (priority values, slug truncation and `-2` suffix, the limit of 5 tags, ordering, soft delete) are in the first prompt only. The JSON API was built in window 4 and 5, and the hidden probe, which tests those rules through HTTP, passed in full.
- **The session file was written before every compaction** and reloaded after each one. By the end it held about 2,000 tokens: goal, state, 20 or so decisions with reasons, and gotchas such as the Sequel dataset method that could not be called `open`.
- **The agent kept to one context.** No spawn was attempted. It also wrote no core memory, which is the right call for a greenfield app with nothing worth crystallizing.
- **A 100k cap is a stress test, not a way to work.** The base prompt and tools take 33k and each summary about 20k, so a window had under 20k of working room. A 300k cap gives more than ten times that.

### What the run changed in mstack

The run was also used to tune mstack, so windows 1 and 2 ran on the first thresholds and windows 3 to 5 on the current ones. These changes came out of it:

1. **Checkpoints are measured against the compaction point, not the cap.** Claude Code compacted the 100k window at about 67k of measured context. The same reserve shows in 90 earlier compactions at a 300k cap: 70 of them fired between 266k and 270k. The first final checkpoint, at 85% of the cap, would never have fired. Checkpoints are now 50%, 70% and 88% of `cap_tokens - compact_reserve_tokens`.
2. **The reading counts the step in flight.** A hook sees the context size of the previous request. The tool call and result it is reporting are now added to it.
3. **Reconcile after compaction.** One large step can still jump past the final checkpoint (window 2 went from 51k to 70k in one, and in window 3 the final checkpoint arrived one step before the compaction). After each compaction the agent is now told to merge the summary's last steps into the session file before continuing, in stronger words if it wrote nothing in that window. Windows 4 and 5 show it working: each opens with the agent updating the file.
4. **The snapshot records git state.** The agent wrote every file through shell heredocs, so the list of files edited with Edit and Write stayed empty. The PreCompact snapshot now includes the branch, uncommitted paths and recent commits.

### Not covered by this run

- **Model policy.** Headless sessions have no status line, so plan limits never reach the hooks. A separate short run seeded a weekly reading of 72%: the agent did no work, told the user to run `/model claude-opus-5-5`, and checkpointed. The rest is covered by specs.
- **The Stop hook and the stale-memory wording.** The agent never ignored a checkpoint, so these paths ran only in specs.
- **A clean run on the final thresholds from the first window.** Worth doing after any change to the checkpoint logic.

Reproduce with `rake benchmark:run` and `rake benchmark:verify`. A run costs roughly a third of a 5-hour plan window.
