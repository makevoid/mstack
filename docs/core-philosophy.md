# mstack core philosophy

mstack is a Claude Code plugin built on one idea: **one main agent does the work.** The biggest model you can afford, at a sensible reasoning level, in one context, under your eyes.

It exists as a deliberate counter-position to orchestrator stacks such as pstack's poteto-mode, where one "tech lead" agent spawns and manages a team of subagents. This document explains what those stacks are optimizing for, why mstack thinks the trade is wrong, and what mstack does instead.

## What orchestrator stacks are built around

An orchestrator stack gives three reasons for splitting work across agents.

1. **Speed.** Independent tasks run in parallel on several agents.
2. **Context.** One agent holds the architecture and acts as engineering lead. The work is split into humanized roles (frontend, backend, QA, or coder / reviewer / QA), each with its own context window, so no single window fills up.
3. **Quality per cost.** The architect runs on the biggest model at high reasoning. The "coding" is handed to cheaper, lower-intelligence models.

Each reason is real. Each also has a cost that the pitch leaves out.

## What that costs

**Every handoff is lossy.** A subagent knows only what the orchestrator wrote in its brief. The orchestrator knows only what the subagent wrote in its report. Neither can tell what the other missed. Context, tokens and intelligence are all spent on agent-to-agent communication instead of on the problem, and a subagent's mistakes come back in the same confident tone as its findings.

**You cannot watch it.** Ten agents and two thousand tool calls later, nobody, including the orchestrator, can say what actually happened. Half the calls failed inside a sandbox with too many guardrails. Or worse, one agent got out and did damage, for example reset a database, because it was a small model at low reasoning that got confused or collided with another agent's work.

**So you build guardrails.** Because you cannot supervise a swarm, you need sandboxes, permission layers, conflict detection and verification passes. That is extra machinery whose only purpose is to contain the architecture you chose.

**The cheap-coder premise is backwards.** Writing the code is not the low-intelligence part of the job. It is where the design meets the real codebase, where the subtle bugs are made or avoided. Handing it to the weakest model in the system puts the least capable agent at the point of highest consequence.

## The mstack position

### 1. One agent. Slower by default, and better.

mstack runs one agent. It is slower than a swarm on parallelizable work, and that is accepted on purpose. In exchange:

- **Nothing is lost in a handoff**, because there are no handoffs. The agent that read the code is the agent that writes the change, and the agent that hit the error is the agent that fixes it.
- **You can see everything.** One stream of reasoning, one sequence of tool calls, one set of diffs. You watch a single very good model work quickly, and you are confident because you can see it, not because a guardrail promised.
- **Supervision replaces containment.** You do not need a sandbox strong enough to hold ten unsupervised agents when you have one supervised agent whose every action is in front of you.
- **It is easy to manage.** There is no fleet, no queue, no role configuration, no inter-agent protocol.

If you really want parallelism, you run it: open a second terminal with another session of the same agent, or clone the project into a second directory and run an agent in each. Each one is still a single, big, fully visible agent with the whole context. The parallelism is yours, explicit and observable, not something a model decided to fan out on your behalf.

mstack enforces this with a hook: subagent and workflow spawns are denied. Plain lookups that stand in for a missing tool (fetching a web page, querying the Claude Code docs) are allowed. `subagents: true` in `.mstackrc` lifts the rule for a project that needs it.

### 2. Context is managed, not partitioned.

The real problem behind "give each role its own context" is that one context window fills up. mstack solves that directly instead of scattering the knowledge across agents that cannot see each other.

- **A context cap of 300k tokens.** You configure Claude Code to auto-compact at 300k (`autoCompactWindow: 300000`). This is a requirement for using mstack, not a suggestion. A capped window stays fast and affordable, and keeps the model in the range where it reasons best.
- **Session memory that survives compaction.** As the window approaches the cap, hooks tell the agent to write down what matters in `docs/mstack/sessions/`: the goal, the state, the decisions and their reasons, the exact facts that would be costly to rediscover. Right after a compaction, a hook loads that file back in. The agent picks up from its own notes, not only from a lossy summary. These files are local and gitignored.
- **Core memories.** Rare, very short, crystallized discoveries go to `docs/mstack/core_memories/` and are committed. Every future session starts with them. They are written sparingly, on a real breakthrough or when you ask. `core_memories: false` in `.mstackrc` stops the agent from adding them on its own.

Details: [context-management.md](context-management.md).

### 3. Always the top model you can afford.

There is no model tiering by role, because there are no roles. There is one question: what is the best model your limits can pay for right now?

- **Default: Fable 5.2 at high reasoning.** Max reasoning is not automatically best. High, sometimes xhigh, is the sweet spot of quality against speed and usage.
- **At 70% of the weekly limit, step down to Opus 5.5.** With 30% of the week left on a cheaper model you still have plenty of room before the reset, and you spent the first 70% on the best model available. That is the best of both.
- **At 90% of the current session limit, pause and ask.** You keep Fable 5.2 as the session default until then.
- **When limits have room again, step back up.**

mstack tracks both limits and tells the agent to stop and ask you to switch. Claude Code does not let a hook change the model, so the switch itself is always your `/model` command. Thresholds and models are configurable.

Details: [model-policy.md](model-policy.md).

## What mstack is not

- **Not an orchestrator.** There is nothing to configure about roles, panels or fleets.
- **Not autonomous-by-default.** The design assumes you are watching. Irreversible actions pause for you.
- **Not a prompt pack.** The behavior that matters (checkpoints before compaction, memory reload after it, limit tracking, the single-agent guard) is implemented in hooks and Ruby code with specs, not in instructions the model may or may not follow.

## Summary

| | Orchestrator stack | mstack |
|---|---|---|
| Agents | One lead plus many subagents | One |
| Parallelism | Model-driven fan-out | You open another terminal or clone |
| Context | Split across agents by role | One window, capped at 300k, with memory that survives compaction |
| Models | Tiered: big architect, cheap coders | The best one you can afford, for everything |
| Safety | Sandboxes and guardrails around a swarm | One agent you can watch |
| Cost of a mistake | Hidden in a subagent's report | In front of you, in the diff |
