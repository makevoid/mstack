# frozen_string_literal: true

module Mstack
  # Checks that the machine and the project meet mstack's requirements.
  # Used by `mstack doctor`, the setup skill and the SessionStart briefing.
  class Doctor
    Check = Struct.new(:name, :ok, :detail, :fix)

    def initialize(project, settings: ClaudeSettings.new(project.root), model_id: nil, effort: nil)
      @project = project
      @config = project.config
      @settings = settings
      @model_id = model_id
      @effort = effort
    end

    def checks
      [initialized, gitignore, compact_window, model, effort, statusline, core_memories, config_file].compact
    end

    def problems
      checks.reject(&:ok)
    end

    def report
      checks.map do |check|
        line = "#{check.ok ? '[ok]  ' : '[FIX] '} #{check.name}: #{check.detail}"
        check.ok || check.fix.nil? ? line : "#{line}\n       -> #{check.fix}"
      end.join("\n")
    end

    private

    def initialized
      Check.new("project", @project.initialized?,
                @project.initialized? ? "initialized" : "not initialized",
                "run `mstack init` in the project root")
    end

    def gitignore
      return nil unless @project.initialized?

      entry = "#{Project::SESSIONS_DIR}/"
      ok = Gitignore.new(@project.root).include?(entry)
      Check.new("gitignore", ok, ok ? "#{entry} is ignored" : "#{entry} is NOT ignored", "run `mstack init`")
    end

    def compact_window
      cap = @config.cap_tokens
      window = @settings.auto_compact_window(@model_id || @config.default_model)
      unless @settings.auto_compact_enabled?
        return Check.new("context cap", false, "auto-compaction is disabled",
                         "remove DISABLE_AUTO_COMPACT / set autoCompactEnabled to true")
      end

      ok = window == cap
      detail = window ? "autoCompactWindow is #{window}, .mstackrc cap_tokens is #{cap}" : "autoCompactWindow is not set"
      Check.new("context cap", ok, ok ? "auto-compaction at #{cap} tokens" : detail,
                %(set "autoCompactWindow": #{cap} in ~/.claude/settings.json (or run /autocompact)))
    end

    def model
      wanted = @config.default_model
      current = @model_id || @settings.model
      ok = policy.on?(current, wanted) || policy.on?(current, @config.fallback_model)
      Check.new("model", ok, "#{current || 'unset'} (default #{wanted}, fallback #{@config.fallback_model})",
                "run `/model #{wanted}`")
    end

    # A live session reports its real effort; otherwise fall back to settings.
    def effort
      wanted = @config.effort
      current = @effort || @settings.effort(@model_id || @config.default_model)
      range = wanted == @config.effort_max ? wanted : "#{wanted} to #{@config.effort_max}"
      Check.new("effort", @config.effort_ok?(current), "#{current || 'unset'} (wanted #{range})",
                %(set "effortLevel": "#{wanted}" in ~/.claude/settings.json (or run `/effort #{wanted}`)))
    end

    def statusline
      ok = @settings.statusline_command.to_s.include?("mstack")
      Check.new("usage tracking", ok,
                ok ? "mstack status line installed" : "mstack status line not installed, so plan limits are invisible",
                "run /mstack:setup to install the status line (it can wrap your existing one)")
    end

    def core_memories
      return nil unless @project.initialized?

      memories = CoreMemories.new(@project)
      detail = "#{memories.entries.size} files, ~#{memories.total_tokens} tokens (budget #{memories.budget_tokens})"
      long = memories.oversized.map { |entry| File.basename(entry.path) }
      detail += "; too long: #{long.join(', ')}" unless long.empty?
      Check.new("core memories", memories.within_budget? && long.empty?, detail,
                "merge or trim files in #{Project::CORE_MEMORIES_DIR}/")
    end

    def config_file
      return nil if @config.warnings.empty?

      Check.new("config", false, @config.warnings.join("; "), "fix #{Config::FILENAME}")
    end

    def policy
      @policy ||= ModelPolicy.new(@config)
    end
  end
end
