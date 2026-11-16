# frozen_string_literal: true

module Mstack
  # Claude Code hook handlers. Each handler takes the hook's stdin payload
  # and returns what to print on stdout: a Hash (printed as JSON), a String
  # (printed as is) or nil (print nothing).
  module Hooks
    # Shared plumbing: the project, session and state a handler works with.
    class Base
      def initialize(input, home: Mstack.home, now: Time.now)
        @input = input
        @home = home
        @now = now
      end

      def call
        raise NotImplementedError
      end

      private

      attr_reader :input

      def project
        @project ||= Project.locate(input["cwd"])
      end

      def config
        project.config
      end

      def session_id
        input["session_id"].to_s
      end

      # Hooks also fire inside subagents; mstack only manages the main agent.
      def subagent?
        !input["agent_id"].to_s.empty?
      end

      def state
        @state ||= SessionState.new(session_id, home: @home)
      end

      def memory
        @memory ||= SessionMemory.new(project, session_id, started_at: state.started_at(@now))
      end

      def transcript
        @transcript ||= Transcript.new(input["transcript_path"])
      end

      def briefing(model_id: nil)
        Briefing.new(project, memory, model_id: model_id)
      end

      def additional_context(text)
        return nil if text.to_s.strip.empty?

        { "hookSpecificOutput" => { "hookEventName" => input["hook_event_name"], "additionalContext" => text } }
      end

      # The two things mstack watches while the agent works: how full the
      # context is, and whether the current model is still affordable.
      # Returns the messages that are due now (each is delivered once).
      def watch
        reading = transcript.reading
        [checkpoint_message(reading), policy_message(reading)].compact
      end

      # The transcript's last usage predates whatever this hook is reporting
      # (a tool call and its result, a new prompt). That text is about to
      # enter the context, so count it, or one large step can jump past a
      # checkpoint.
      def pending_tokens
        pending = input.values_at("tool_input", "tool_response", "prompt").compact
        Tokens.estimate(pending.map { |part| part.is_a?(String) ? part : JSON.generate(part) }.join)
      end

      def checkpoint_message(reading)
        return nil unless project.initialized?

        tokens = reading.tokens && reading.tokens + pending_tokens
        status = ContextMonitor.new(config).check!(tokens, state)
        return nil unless status

        memory.ensure!
        briefing.checkpoint(status)
      end

      def policy_message(reading)
        usage = Usage::Store.new(home: @home).load(session_id)
        return nil if usage.stale?(Integer(config.dig(:limits, :stale_after_minutes)), now: @now)

        decision = ModelPolicy.new(config).decide(
          model_id: reading.model_id || usage.model_id,
          weekly_pct: usage.weekly_pct,
          session_pct: usage.session_pct
        )
        return nil if decision.ok? || state.noticed?(decision.kind)

        state.noticed!(decision.kind, at: @now)
        briefing.policy(decision)
      end
    end

    # Loads memory into a new context window: core memories at session
    # start, and the session memory file right after a compaction.
    class SessionStart < Base
      def call
        return nil if subagent?

        Launcher.new(home: @home).install!
        return additional_context(briefing.uninitialized) unless project.initialized?

        project.init! # idempotent: keeps the directories and the gitignore entry in place
        if input["source"] == "compact"
          state.compacted!(at: @now)
          additional_context(briefing.after_compaction(state.compactions, stale: state.memory_stale?))
        else
          problems = Doctor.new(project, model_id: input["model"], effort: input.dig("effort", "level")).problems
          additional_context(briefing(model_id: input["model"]).startup(source: input["source"] || "startup", problems: problems))
        end
      end
    end

    # Safety net before the window is summarized: a mechanical snapshot goes
    # into the session file, and the summarizer is told the file exists.
    class PreCompact < Base
      def call
        return nil if subagent? || !project.initialized?

        # Before the snapshot touches the file: did the agent write to it in this window?
        state.memory_stale!(memory.pristine? || !memory.updated_since?(state.window_started_at))
        memory.write_snapshot!(transcript.digest, tokens: transcript.context_tokens, trigger: input["trigger"] || "auto", at: @now)
        briefing.compaction_instructions
      end
    end

    class UserPromptSubmit < Base
      def call
        return nil if subagent?

        additional_context(watch.join("\n\n"))
      end
    end

    class PostToolUse < Base
      def call
        return nil if subagent?

        additional_context(watch.join("\n\n"))
      end
    end

    # Single-agent mode: deny subagent and workflow spawns.
    class PreToolUse < Base
      SPAWNING_TOOLS = %w[Agent Task Workflow].freeze

      def call
        return nil if subagent? || config.subagents?
        return nil unless SPAWNING_TOOLS.include?(input["tool_name"])

        type = input.dig("tool_input", "subagent_type").to_s
        return nil if input["tool_name"] != "Workflow" && config.allowed_subagents.include?(type)

        {
          "hookSpecificOutput" => {
            "hookEventName" => "PreToolUse",
            "permissionDecision" => "deny",
            "permissionDecisionReason" =>
              "mstack single-agent mode: do this work yourself in the main context, where the user can watch it " \
              "and nothing is lost in a handoff. Allowed lookups: #{config.allowed_subagents.join(', ')}. " \
              "The user can set `subagents: true` in .mstackrc to lift this."
          }
        }
      end
    end

    # A checkpoint that was asked for and ignored is enforced once, at the
    # end of the turn.
    class Stop < Base
      def call
        return nil if subagent? || input["stop_hook_active"] || !project.initialized?

        requested_at = state.checkpoint_requested_at
        return nil if requested_at.nil? || state.checkpoint_enforced? || memory.updated_since?(requested_at)

        state.checkpoint_enforced!
        { "decision" => "block", "reason" => briefing.stop_reminder }
      end
    end

    HANDLERS = {
      "session-start" => SessionStart,
      "pre-compact" => PreCompact,
      "user-prompt-submit" => UserPromptSubmit,
      "post-tool-use" => PostToolUse,
      "pre-tool-use" => PreToolUse,
      "stop" => Stop
    }.freeze

    def self.run(name, input, **options)
      handler = HANDLERS.fetch(name) { raise ArgumentError, "unknown hook: #{name}" }
      handler.new(input, **options).call
    end
  end
end
