# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::Hooks do
  let(:session_id) { "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d" }
  let(:now) { Time.now }

  def run(name, extra = {})
    described_class.run(name, { "session_id" => session_id, "cwd" => root }.merge(extra), now: now)
  end

  def context_of(result)
    result&.dig("hookSpecificOutput", "additionalContext")
  end

  def session_file
    Dir.glob(File.join(root, "docs/mstack/sessions/*.md")).first
  end

  describe "session-start" do
    it "only hints at setup in a project that was never initialized, and writes nothing" do
      result = run("session-start", "hook_event_name" => "SessionStart", "source" => "startup")

      expect(context_of(result)).to include("not initialized", "/mstack:setup")
      expect(Dir.children(root)).to be_empty
    end

    context "in an initialized project" do
      before { project.init! }

      it "briefs the agent on the rules and the memory locations" do
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("mstack is active", "one agent", "docs/mstack/sessions/", "docs/mstack/core_memories/")
        expect(result_event(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))).to eq("SessionStart")
      end

      it "loads core memories that fit the budget" do
        write("docs/mstack/core_memories/2026-11-01-port.md", "# Port is 9797\nNever 3000.")
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("Core memories (1):", "# Port is 9797", "Never 3000.")
      end

      it "refuses to load core memories that are over budget and says so" do
        write(".mstackrc", "context:\n  core_memories_budget_tokens: 20\n")
        write("docs/mstack/core_memories/2026-11-01-big.md", "# Big one\n#{'word ' * 200}")
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("over budget", "NOT loaded", "2026-11-01-big.md: Big one")
        expect(text).not_to include("word word word")
      end

      it "says when auto-writing core memories is disabled" do
        write(".mstackrc", "core_memories: false\n")
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("auto-writing is disabled")
      end

      it "reports setup problems such as a missing context cap" do
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("setup problems", "autoCompactWindow is not set")
      end

      it "reports no context-cap problem when autoCompactWindow matches the cap" do
        user_settings("autoCompactWindow" => 300_000, "model" => "fable", "effortLevel" => "high",
                      "statusLine" => { "command" => "mstack statusline" })
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).not_to include("setup problems")
      end

      it "judges effort by what the session is really running at, not by settings files" do
        user_settings("autoCompactWindow" => 300_000, "model" => "fable", "effortLevel" => "max",
                      "statusLine" => { "command" => "mstack statusline" })
        start = ->(level) { context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup", "effort" => { "level" => level })) }

        expect(start.call("xhigh")).not_to include("setup problems")
        expect(start.call("max")).to include("effort: max (wanted high to xhigh)")
      end

      it "points at earlier session files without loading them" do
        write("docs/mstack/sessions/20261101-000000-aaaaaaaa.md", "SECRET OLD CONTENT")
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "startup"))

        expect(text).to include("docs/mstack/sessions/20261101-000000-aaaaaaaa.md")
        expect(text).not_to include("SECRET OLD CONTENT")
      end

      it "restores the gitignore entry if it was removed" do
        File.write(File.join(root, ".gitignore"), "")
        run("session-start", "hook_event_name" => "SessionStart", "source" => "startup")

        expect(File.read(File.join(root, ".gitignore"))).to include("docs/mstack/sessions/")
      end

      it "reloads this session's memory file right after a compaction" do
        memory = Mstack::SessionMemory.new(project, session_id)
        memory.ensure!
        File.write(memory.path, "## State\nNext step: add the tags join table.\n")
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "compact"))

        expect(text).to include("just compacted", "compaction #1", memory.relative_path, "Next step: add the tags join table.")
      end

      it "tells the agent to Read a session file too large to inline" do
        memory = Mstack::SessionMemory.new(project, session_id)
        memory.ensure!
        File.write(memory.path, "x" * 20_000)
        text = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "compact"))

        expect(text.length).to be <= 10_000
        expect(text).to include("Use the Read tool on #{memory.relative_path} now")
      end

      it "has the agent reconcile the file with the summary, and says so when the file went stale" do
        state = Mstack::SessionState.new(session_id)
        memory = Mstack::SessionMemory.new(project, session_id)
        memory.ensure!
        File.write(memory.path, "## State\nPhase 2 done.\n")

        run("pre-compact", "hook_event_name" => "PreCompact", "trigger" => "auto")
        fresh = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "compact"))
        expect(fresh).to include("a few steps behind the summary")
        expect(state.checkpoint_requested_at).to be_within(1).of(now)

        # Nothing written by the agent in the second window.
        File.utime(now - 60, now - 60, memory.path)
        run("pre-compact", "hook_event_name" => "PreCompact", "trigger" => "auto")
        stale = context_of(run("session-start", "hook_event_name" => "SessionStart", "source" => "compact"))
        expect(stale).to include("You did not update the file during the window that was just compacted")
      end

      it "treats a file the agent never filled in as stale" do
        Mstack::SessionMemory.new(project, session_id).ensure!
        run("pre-compact", "hook_event_name" => "PreCompact", "trigger" => "auto")

        expect(Mstack::SessionState.new(session_id).memory_stale?).to be(true)
      end

      it "counts compactions and re-arms the checkpoints" do
        state = Mstack::SessionState.new(session_id)
        state.announce_checkpoint!(2)
        2.times { run("session-start", "hook_event_name" => "SessionStart", "source" => "compact") }

        expect(state.compactions).to eq(2)
        expect(state.checkpoint_level).to be_nil
      end
    end

    def result_event(result)
      result.dig("hookSpecificOutput", "hookEventName")
    end
  end

  describe "context checkpoints (post-tool-use / user-prompt-submit)" do
    before { project.init! }

    def tool_use(tokens)
      run("post-tool-use", "hook_event_name" => "PostToolUse", "transcript_path" => transcript(assistant(tokens)))
    end

    it "stays silent while context is below the first checkpoint" do
      expect(tool_use(100_000)).to be_nil
      expect(session_file).to be_nil
    end

    it "asks for a checkpoint once when a threshold is crossed, creating the session file" do
      text = context_of(tool_use(155_000))

      expect(text).to include("mstack checkpoint", "155k", "58% of the way to auto-compaction (near 267k)", "docs/mstack/sessions/")
      expect(File.read(session_file)).to include("## State")
      expect(tool_use(160_000)).to be_nil
    end

    it "asks for the final checkpoint and a core memory near the cap" do
      text = context_of(tool_use(262_000))

      expect(text).to include("FINAL checkpoint", "imminent", "core memory")
    end

    it "counts the tool call itself, such as a large heredoc" do
      result = run("post-tool-use", "hook_event_name" => "PostToolUse", "transcript_path" => transcript(assistant(225_000)),
                                    "tool_input" => { "command" => "cat > app.rb <<'EOF'\n#{'x' * 48_000}\nEOF" }, "tool_response" => "")

      expect(context_of(result)).to include("FINAL checkpoint")
    end

    it "counts the tool result that is about to enter the context" do
      result = run("post-tool-use", "hook_event_name" => "PostToolUse", "transcript_path" => transcript(assistant(225_000)),
                                    "tool_response" => { "stdout" => "x" * 48_000 })

      expect(context_of(result)).to include("FINAL checkpoint", "237k")
    end

    it "does not ask for core memories when they are disabled" do
      write(".mstackrc", "core_memories: false\n")

      expect(context_of(tool_use(262_000))).not_to include("core memory")
    end

    it "also fires on a user prompt" do
      result = run("user-prompt-submit", "hook_event_name" => "UserPromptSubmit",
                                         "transcript_path" => transcript(assistant(215_000)))

      expect(context_of(result)).to include("mstack checkpoint")
      expect(result.dig("hookSpecificOutput", "hookEventName")).to eq("UserPromptSubmit")
    end

    it "ignores hooks fired inside a subagent" do
      result = run("post-tool-use", "agent_id" => "a1", "transcript_path" => transcript(assistant(290_000)))

      expect(result).to be_nil
    end

    it "does not checkpoint in an uninitialized project" do
      FileUtils.rm_rf(File.join(root, "docs"))
      FileUtils.rm_f(File.join(root, ".mstackrc"))

      expect(tool_use(290_000)).to be_nil
    end
  end

  describe "model policy notices" do
    def prompt(model: "claude-fable-5-2")
      run("user-prompt-submit", "hook_event_name" => "UserPromptSubmit",
                                "transcript_path" => transcript(assistant(10_000, model: model)))
    end

    it "pauses once when the weekly limit crosses 70% on the default model" do
      record_usage(session_id, weekly: 72, session: 10)

      expect(context_of(prompt)).to include("PAUSE", "Weekly limit is at 72%", "/model claude-opus-5-5")
      expect(prompt).to be_nil
    end

    it "pauses when the session limit crosses 90%" do
      record_usage(session_id, weekly: 30, session: 93)

      expect(context_of(prompt)).to include("PAUSE", "Current session limit is at 93%")
    end

    it "is quiet after the user switched to the fallback model" do
      record_usage(session_id, weekly: 72, session: 10)

      expect(prompt(model: "claude-opus-5-5")).to be_nil
    end

    it "trusts the transcript's model over a stale status line snapshot" do
      record_usage(session_id, weekly: 72, session: 10, model: "claude-opus-5-5")

      expect(context_of(prompt(model: "claude-fable-5-2"))).to include("PAUSE")
    end

    it "uses another session's limits until this one has its own" do
      record_usage("another-session", weekly: 81, session: 5)

      expect(context_of(prompt)).to include("Weekly limit is at 81%")
    end

    it "ignores a stale snapshot" do
      record_usage(session_id, weekly: 99, session: 99, at: now - (7 * 3600))

      expect(prompt).to be_nil
    end

    it "suggests stepping back up without pausing" do
      record_usage(session_id, weekly: 5, session: 5)
      text = context_of(prompt(model: "claude-opus-5-5"))

      expect(text).to include("/model claude-fable-5-2", "FYI")
      expect(text).not_to include("PAUSE")
    end

    it "is quiet when no usage was ever recorded" do
      expect(prompt).to be_nil
    end
  end

  describe "pre-compact" do
    before { project.init! }

    it "snapshots the session and hands instructions to the summarizer" do
      path = transcript(user("build the todo app"), assistant(280_000, content: [edit("#{root}/app.rb")]))
      result = run("pre-compact", "hook_event_name" => "PreCompact", "trigger" => "auto", "transcript_path" => path)

      expect(result).to be_a(String).and include(project.relative(session_file), "must be read before continuing")
      expect(File.read(session_file)).to include("Auto-snapshot before compaction", "- build the todo app", "- app.rb", "auto compaction")
    end

    it "does nothing in an uninitialized project" do
      FileUtils.rm_rf(File.join(root, "docs"))
      FileUtils.rm_f(File.join(root, ".mstackrc"))

      expect(run("pre-compact", "trigger" => "auto")).to be_nil
    end
  end

  describe "pre-tool-use (single-agent guard)" do
    def spawn(tool, type = nil)
      input = type ? { "subagent_type" => type } : {}
      run("pre-tool-use", "hook_event_name" => "PreToolUse", "tool_name" => tool, "tool_input" => input)
    end

    it "denies subagent spawns, forks and workflows" do
      [spawn("Agent", "general-purpose"), spawn("Agent", "fork"), spawn("Agent"), spawn("Task", "Explore"), spawn("Workflow")].each do |result|
        expect(result.dig("hookSpecificOutput", "permissionDecision")).to eq("deny")
        expect(result.dig("hookSpecificOutput", "permissionDecisionReason")).to include("single-agent mode")
      end
    end

    it "lets the utility lookups through" do
      expect(spawn("Agent", "web-fetch")).to be_nil
      expect(spawn("Agent", "claude-code-guide")).to be_nil
    end

    it "does not interfere with other tools" do
      expect(spawn("Bash")).to be_nil
    end

    it "allows everything when .mstackrc sets subagents: true" do
      write(".mstackrc", "subagents: true\n")

      expect(spawn("Agent", "general-purpose")).to be_nil
      expect(spawn("Workflow")).to be_nil
    end

    it "does not police a subagent's own tool calls" do
      result = run("pre-tool-use", "agent_id" => "a1", "tool_name" => "Agent", "tool_input" => {})

      expect(result).to be_nil
    end
  end

  describe "stop" do
    before { project.init! }

    let(:state) { Mstack::SessionState.new(session_id) }
    let(:memory) { Mstack::SessionMemory.new(project, session_id) }

    it "lets the turn end when no checkpoint is pending" do
      expect(run("stop", "hook_event_name" => "Stop")).to be_nil
    end

    it "blocks once when a requested checkpoint was ignored" do
      memory.ensure!
      File.utime(now - 60, now - 60, memory.path)
      state.announce_checkpoint!(1, at: now - 10)

      result = run("stop", "hook_event_name" => "Stop")
      expect(result).to include("decision" => "block")
      expect(result["reason"]).to include(memory.relative_path)
      expect(run("stop", "hook_event_name" => "Stop")).to be_nil
    end

    it "lets the turn end when the session file was updated after the request" do
      state.announce_checkpoint!(1, at: now - 10)
      memory.ensure!

      expect(run("stop", "hook_event_name" => "Stop")).to be_nil
    end

    it "enforces the reconcile that follows a compaction" do
      memory.ensure!
      File.utime(now - 60, now - 60, memory.path)
      run("session-start", "hook_event_name" => "SessionStart", "source" => "compact")

      expect(run("stop", "hook_event_name" => "Stop")).to include("decision" => "block")
    end

    it "never blocks while already continuing from a stop hook" do
      state.announce_checkpoint!(1, at: now - 10)

      expect(run("stop", "hook_event_name" => "Stop", "stop_hook_active" => true)).to be_nil
    end
  end

  it "rejects an unknown hook name" do
    expect { run("nope") }.to raise_error(ArgumentError, /unknown hook/)
  end
end

RSpec.describe Mstack::Briefing do
  let(:memory) { Mstack::SessionMemory.new(project, "abcdef12") }
  subject(:briefing) { described_class.new(project, memory) }

  before { project.init! }

  it "keeps every injected string under Claude Code's 10,000 character cap" do
    memory.ensure!
    File.write(memory.path, "s" * 7_000)
    3.times { |n| write("docs/mstack/core_memories/2026-11-0#{n}-m.md", "# Memory #{n}\n#{'c' * 1_500}") }

    [briefing.after_compaction(1), briefing.startup(source: "startup")].each do |text|
      expect(text.length).to be <= 10_000
    end
  end

  it "prefers session memory over core memories after a compaction, pointing at the files that did not fit" do
    memory.ensure!
    File.write(memory.path, "STATE #{'s' * 7_000}")
    3.times { |n| write("docs/mstack/core_memories/2026-11-0#{n}-m.md", "# Memory #{n}\n#{'c' * 1_500}") }
    text = briefing.after_compaction(1)

    expect(text).to include("STATE sss", "Core memories did not fit here. Read these files now:", "docs/mstack/core_memories/2026-11-00-m.md: Memory 0")
  end
end
