# frozen_string_literal: true

module Mstack
  # Composes the text that hooks inject into the model's context. Claude
  # Code caps each injected string at 10,000 characters, so anything that
  # does not fit inline is replaced by an instruction to Read the file,
  # which always works.
  class Briefing
    CHAR_CAP = 9_500

    def initialize(project, memory, model_id: nil)
      @project = project
      @config = project.config
      @memory = memory
      @model_id = model_id
    end

    # Session start in a project that never ran `mstack init`.
    def uninitialized
      <<~TEXT.strip
        mstack is installed but not initialized in this project, so session memory and core memories are off here.
        #{rules}
        If the user wants mstack memory in this project, run the /mstack:setup skill (it runs `mstack init`).
      TEXT
    end

    # A fresh (or resumed, or cleared) session.
    def startup(source:, problems: [])
      parts = ["mstack is active in this project (#{source}).", rules, memory_protocol]
      parts << previous_sessions unless source == "resume"
      parts << setup_problems(problems) unless problems.empty?
      fit(parts + [core_memories_section])
    end

    # The first thing the agent sees after a compaction.
    # stale: the agent wrote nothing to the file in the window that ended.
    def after_compaction(compactions, stale: false)
      reconcile =
        if stale
          "You did not update the file during the window that was just compacted, so the summary above is the only record of that work. " \
            "First, before any other work, write it into the file: rewrite \"State\" (done, in progress, exact next step), append Decisions and Facts."
        else
          "The file is a few steps behind the summary above. First, bring its \"State\" section up to date from the summary (and append any newer Decisions and Facts)."
        end
      head = <<~TEXT.strip
        mstack: this conversation was just compacted (compaction ##{compactions} of this session). The summary above is lossy.
        Your session memory file is the authoritative record of this session: #{@memory.relative_path}
        #{reconcile} Then continue from "State". Do not re-ask the user for things the file already answers.
        #{rules}
      TEXT
      # Session memory first: after a compaction it matters more than anything else.
      fit([head, session_memory_section, core_memories_section])
    end

    def checkpoint(status)
      path = @memory.relative_path
      if status.final
        text = <<~TEXT
          mstack FINAL checkpoint: context is at #{Tokens.human(status.tokens)} tokens and auto-compaction fires near #{Tokens.human(status.compaction_point)}. Compaction is imminent.
          Now, before any other work: bring #{path} fully up to date so that you could resume from that file alone. Rewrite "State" with what is done, what is half-done (which files, what is left) and the exact next step; append new Decisions (with why) and Facts (exact commands, paths, values). Be specific, not long.
        TEXT
        text += core_memory_prompt
      else
        text = <<~TEXT
          mstack checkpoint: context is at #{Tokens.human(status.tokens)} tokens, #{status.pct}% of the way to auto-compaction (near #{Tokens.human(status.compaction_point)}).
          At the next natural pause in the current step, update #{path}: rewrite "State", append new Decisions and Facts. Keep it tight, then carry on.
        TEXT
      end
      text.strip
    end

    def policy(decision)
      return "mstack model policy (FYI, tell the user in one line and keep working): #{decision.message}" unless decision.pause

      <<~TEXT.strip
        mstack model policy: PAUSE. #{decision.message}
        Hooks cannot change the model, only the user can. Finish the step you are in the middle of so nothing is left half-edited, update the session memory, then stop and tell the user exactly this, and wait for them. Do not start new work on the current model. If the user says to keep going as is, keep going and do not ask again this session.
      TEXT
    end

    def stop_reminder
      "mstack: a context checkpoint was requested and #{@memory.relative_path} has not been updated since. " \
        "Update it now (State, Decisions, Facts), then finish your turn."
    end

    # Plain-text instructions handed to the compaction summarizer.
    def compaction_instructions
      <<~TEXT.strip
        This session uses mstack session memory. In the summary, state near the top that the file #{@memory.relative_path} holds the authoritative session state and must be read before continuing. Preserve verbatim: the user's goal and constraints in their own words, the exact next step, names of files being edited, and any exact commands, values or error messages still relevant.
      TEXT
    end

    private

    def rules
      subagents =
        if @config.subagents?
          "Subagents are allowed by .mstackrc, but the default stands: do the work yourself."
        else
          "Do not spawn subagents or workflows (a hook denies them; #{@config.allowed_subagents.join(', ')} are allowed as plain lookups)."
        end
      <<~TEXT.strip
        mstack rules: you are the one agent doing this work, in this context, under the user's eyes. #{subagents} Work in small verified steps, show diffs rather than describing them, and pause before anything irreversible. Full guide: the mstack skill.
      TEXT
    end

    def memory_protocol
      auto = @config.core_memories? ? "write one when you hit a real breakthrough" : "auto-writing is disabled in .mstackrc, write one only when the user asks"
      <<~TEXT.strip
        Session memory for this session: #{@memory.relative_path} (local, gitignored, created at the first checkpoint). Hooks tell you when to checkpoint as context approaches auto-compaction (near #{Tokens.human(@config.compaction_point)} tokens, under the #{Tokens.human(@config.cap_tokens)} cap), and reload the file after compaction.
        Core memories: #{Project::CORE_MEMORIES_DIR}/ (committed, a few lines each): #{auto}.
      TEXT
    end

    def core_memory_prompt
      return "" unless @config.core_memories?

      "If this window produced a breakthrough or discovery that every future session should know, also write ONE core memory in #{Project::CORE_MEMORIES_DIR}/ (see /mstack:remember). Most windows produce none."
    end

    def previous_sessions
      files = SessionMemory.recent(@project, except: @memory.path)
      return nil if files.empty?

      "Earlier session memories (read one only if the user is continuing that work): " +
        files.map { |file| @project.relative(file) }.join(", ")
    end

    def setup_problems(problems)
      "mstack setup problems (mention them to the user once, suggest /mstack:setup):\n" +
        problems.map { |check| "- #{check.name}: #{check.detail}" }.join("\n")
    end

    def core_memories_section
      memories = CoreMemories.new(@project)
      return nil if memories.empty?

      unless memories.within_budget?
        return "Core memories are over budget (~#{memories.total_tokens} tokens, budget #{memories.budget_tokens}), so they were NOT loaded. " \
               "Tell the user they need consolidating. Index (Read what is relevant):\n#{memories.index}"
      end

      lambda do |room|
        inline = "Core memories (#{memories.entries.size}):\n#{memories.full}"
        inline.length <= room ? inline : "Core memories did not fit here. Read these files now:\n#{memories.index}"
      end
    end

    def session_memory_section
      path = @memory.relative_path
      return "No session memory file exists yet for this session; rely on the summary and create #{path} at the next checkpoint." unless @memory.exist?

      budget = Integer(@config.dig(:context, :session_memory_budget_tokens))
      lambda do |room|
        inline = "Session memory (#{path}):\n#{@memory.render(budget)}"
        inline.length <= room ? inline : "Session memory is too large to inline here. Use the Read tool on #{path} now, before anything else."
      end
    end

    # Joins the parts under the cap. A part may be a lambda taking the room
    # that is left, so it can choose between inlining and pointing at a file.
    def fit(parts)
      out = parts.compact.each_with_object([]) do |part, done|
        room = CHAR_CAP - done.sum { |text| text.length + 2 }
        done << (part.respond_to?(:call) ? part.call(room) : part)
      end
      out.join("\n\n")[0, CHAR_CAP]
    end
  end
end
