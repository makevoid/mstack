# mstack

A Claude Code plugin for working with **one big agent** instead of a swarm.

Orchestrator stacks spawn a team of subagents for speed, split context and cheaper "coder" models. mstack takes the opposite position: one agent, on the best model you can afford, in one context you can watch. It is slower by default and better, because nothing is lost in agent-to-agent handoffs and you supervise the work directly instead of building guardrails around agents you cannot see.

Three things make that practical, and mstack implements each in hooks and code rather than in prompts:

1. **Single-agent mode.** Subagent and workflow spawns are denied. Want parallelism? Open another terminal, or clone the project and run a second agent there.
2. **Managed context.** A required 300k-token auto-compaction cap. As the window fills, the agent checkpoints its state to `docs/mstack/sessions/` (gitignored); after every compaction that file is loaded back. Rare, crystallized discoveries go to `docs/mstack/core_memories/` (committed) and start every future session.
3. **The top model you can afford.** Fable 5.2 at high effort by default. At 70% of the weekly limit the agent pauses and asks you to step down to Opus 5.5; at 90% of the session limit it pauses and asks. When limits have room again, it says so.

Read [docs/core-philosophy.md](docs/core-philosophy.md) for the full argument.

## Install

Requires Ruby 3.1+ on PATH (stdlib only, no gems).

```bash
claude plugin marketplace add /path/to/mstack     # or the GitHub repo
claude plugin install mstack@mstack
```

Or for a single session: `claude --plugin-dir /path/to/mstack`.

Then, in a project:

```
/mstack:setup
```

This runs `mstack init` (creates `.mstackrc`, the memory directories and the `.gitignore` entry) and walks you through the Claude Code settings mstack requires, asking before it changes any of them:

```json
{
  "model": "claude-fable-5-2",
  "effortLevel": "high",
  "autoCompactWindow": 300000,
  "statusLine": { "type": "command", "command": "~/.claude/mstack/statusline" }
}
```

The status line is how mstack sees your plan limits. It can wrap the one you already have: `~/.claude/mstack/statusline --wrap '<your command>'`.

## What happens in a session

| When | mstack does |
|---|---|
| Session starts | Briefs the agent on the rules, loads core memories if they fit their budget, reports setup problems |
| The agent tries to spawn a subagent | Denies it (lookups such as `web-fetch` are allowed) |
| Context is 50% and 70% of the way to auto-compaction | Tells the agent to checkpoint session memory |
| Context is 88% of the way (about 235k at a 300k cap) | Final checkpoint: bring the session file fully up to date, write a core memory if there was a real discovery |
| The agent ends a turn having ignored a checkpoint | Blocks the stop once and asks again |
| Compaction starts | Writes a mechanical snapshot (prompts, edited files, git state) into the session file, tells the summarizer the file exists |
| Compaction ends | Loads the session file and core memories into the new window, and has the agent merge the summary's last steps into the file |
| Weekly limit reaches 70%, or session limit 90% | Tells the agent to finish its step, stop, and ask you to run `/model` |

## Configuration

`.mstackrc` at the project root, a YAML hash. All keys optional:

```yaml
core_memories: true      # false: the agent never adds core memories on its own
subagents: false         # true: lift the single-agent guard

context:
  cap_tokens: 300000     # must equal autoCompactWindow
  checkpoints: [50, 70, 88]  # percent of the compaction point (cap minus ~33k)

model:
  default: claude-fable-5-2
  fallback: claude-opus-5-5
  effort: high

limits:
  weekly_switch_pct: 70
  session_pause_pct: 90
```

Full reference: [docs/configuration.md](docs/configuration.md).

## Skills and commands

| Skill | Use |
|---|---|
| `/mstack:setup` | Initialize a project and fix the requirements |
| `/mstack:checkpoint` | Write session memory now |
| `/mstack:remember` | Crystallize a core memory |
| `/mstack:status` | Limits, model, memory sizes |
| `/mstack:mstack` | The operating guide the agent follows |

`mstack init`, `mstack doctor`, `mstack status` and `mstack session` are available in the shell while the plugin is enabled.

## Documentation

- [Core philosophy](docs/core-philosophy.md): why one agent
- [Context management](docs/context-management.md): the cap, checkpoints, session and core memories, the hooks
- [Model policy](docs/model-policy.md): the rules and how limits are tracked
- [Working principles](docs/principles.md): how the agent works
- [Configuration](docs/configuration.md)
- [Benchmark](docs/benchmark.md): the Roda todo-app benchmark and its results

## Development

Use Ruby 3.1+ and Bundler. Install the development gems before running the tests; the plugin itself needs no extra gems.

```bash
bundle install
bundle exec rake spec          # the Ruby library, hooks and CLI
bundle exec rake validate      # the plugin manifest (requires Claude Code on PATH)
bundle exec rake benchmark:run # one headless session builds the benchmark app (spends plan usage)
bundle exec rake benchmark:verify
```

CI is manual-only: run the CI workflow from GitHub Actions when needed. It tests the latest stable Ruby; pushes and pull requests do not trigger it automatically.

Layout:

```
.claude-plugin/   plugin and marketplace manifests
hooks/hooks.json  hook registrations, all routed to bin/mstack
bin/mstack        CLI: hooks, status line, init, doctor, status
lib/mstack/       the implementation, stdlib-only Ruby
skills/           the five skills
spec/             RSpec suite
benchmark/        benchmark prompt, runner, verifier and hidden acceptance probe
docs/             philosophy and reference
```

## License

MIT
