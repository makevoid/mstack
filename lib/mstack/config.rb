# frozen_string_literal: true

module Mstack
  # Project configuration: defaults overlaid with the `.mstackrc` YAML hash at
  # the project root. A broken file never breaks a session; it falls back to
  # defaults and reports the problem through #warnings.
  class Config
    FILENAME = ".mstackrc"

    DEFAULTS = {
      # Let the agent write core memories on its own. false = only when the
      # user explicitly asks.
      "core_memories" => true,
      # Single-agent mode: deny subagent spawns except the utility types below.
      "subagents" => false,
      "allowed_subagents" => %w[web-fetch claude-code-guide statusline-setup],
      "context" => {
        # Must match Claude Code's autoCompactWindow.
        "cap_tokens" => 300_000,
        # Claude Code compacts before the window is full: it keeps room for
        # the reply and for the summary. Measured at about 33k below the cap.
        "compact_reserve_tokens" => 33_000,
        # Thresholds, in percent of the compaction point (cap minus reserve),
        # that trigger a session-memory checkpoint.
        # The last one is the final checkpoint before compaction.
        "checkpoints" => [50, 70, 88],
        "core_memories_budget_tokens" => 1_500,
        "session_memory_budget_tokens" => 12_000
      },
      "model" => {
        "default" => "claude-fable-5-2",
        "fallback" => "claude-opus-5-5",
        # The reasoning sweet spot is effort..effort_max; below wastes the
        # model, above wastes time and usage.
        "effort" => "high",
        "effort_max" => "xhigh"
      },
      "limits" => {
        # Weekly usage at which to step down from default to fallback.
        "weekly_switch_pct" => 70,
        # Current-session (5h) usage at which to pause and ask.
        "session_pause_pct" => 90,
        # Ignore usage snapshots older than this.
        "stale_after_minutes" => 360
      }
    }.freeze

    attr_reader :warnings, :path

    def self.load(root)
      new(File.join(root, FILENAME))
    end

    def initialize(path)
      @path = path
      @warnings = []
      @data = deep_merge(DEFAULTS, read_overrides)
    end

    def exist?
      File.file?(path)
    end

    def [](key)
      @data[key.to_s]
    end

    def dig(*keys)
      @data.dig(*keys.map(&:to_s))
    end

    def to_h
      @data
    end

    def core_memories?
      self["core_memories"] != false
    end

    def subagents?
      self["subagents"] == true
    end

    def allowed_subagents
      Array(self["allowed_subagents"]).map(&:to_s)
    end

    def cap_tokens
      Integer(dig(:context, :cap_tokens))
    end

    # Where auto-compaction actually fires.
    def compaction_point
      [cap_tokens - Integer(dig(:context, :compact_reserve_tokens)), 1].max
    end

    def checkpoints
      Array(dig(:context, :checkpoints)).map { |n| Integer(n) }.sort
    end

    def default_model
      dig(:model, :default).to_s
    end

    def fallback_model
      dig(:model, :fallback).to_s
    end

    EFFORT_LEVELS = %w[low medium high xhigh max].freeze

    def effort
      dig(:model, :effort).to_s
    end

    def effort_max
      dig(:model, :effort_max).to_s
    end

    # Is this reasoning level inside the configured sweet spot?
    def effort_ok?(level)
      at, low, high = [level.to_s, effort, effort_max].map { |name| EFFORT_LEVELS.index(name) }
      !at.nil? && !low.nil? && at >= low && at <= (high || low)
    end

    # The template written by `mstack init`: every option, at its default.
    def self.template
      <<~YAML
        # mstack configuration. Every key is optional; these are the defaults.

        # Let the agent write core memories on its own when it hits a real
        # breakthrough. false = only when you explicitly ask.
        core_memories: true

        # Single-agent mode. true = allow the agent to spawn subagents.
        subagents: false

        context:
          # Must match Claude Code's autoCompactWindow (settings.json).
          cap_tokens: 300000
          # Percent of the compaction point (cap minus ~33k) at which the agent
          # checkpoints session memory. The last one is the final checkpoint.
          checkpoints: [50, 70, 88]

        model:
          default: claude-fable-5-2
          fallback: claude-opus-5-5
          effort: high        # recommended level
          effort_max: xhigh   # highest level that is still fine

        limits:
          # Weekly limit % at which to step down from default to fallback.
          weekly_switch_pct: 70
          # Current session (5h) limit % at which to pause and ask.
          session_pause_pct: 90
      YAML
    end

    private

    def read_overrides
      return {} unless exist?

      parsed = YAML.safe_load(File.read(path)) || {}
      unless parsed.is_a?(Hash)
        @warnings << "#{FILENAME} must be a YAML hash of options; using defaults"
        return {}
      end
      parsed
    rescue Psych::Exception => e
      @warnings << "#{FILENAME} is not valid YAML (#{e.message.lines.first.to_s.strip}); using defaults"
      {}
    end

    def deep_merge(base, over)
      base.each_with_object({}) do |(key, value), out|
        other = over.key?(key) ? over[key] : over[key.to_sym]
        out[key] =
          if value.is_a?(Hash)
            deep_merge(value, other.is_a?(Hash) ? other : {})
          else
            other.nil? ? value : other
          end
      end.merge(over.reject { |k, _| base.key?(k.to_s) }.transform_keys(&:to_s))
    end
  end
end
