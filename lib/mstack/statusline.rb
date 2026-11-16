# frozen_string_literal: true

require "open3"

module Mstack
  # The status line is the only place Claude Code exposes plan limits, so
  # this is both a renderer and mstack's usage sensor: every payload is
  # recorded for the hooks to read. With `wrap`, rendering is delegated to
  # the user's existing status line command and mstack only adds its alert.
  class Statusline
    BAR_WIDTH = 10

    def initialize(payload, home: Mstack.home, wrap: nil)
      @payload = payload
      @home = home
      @wrap = wrap
      @project = Project.new(payload.dig("workspace", "project_dir") || payload["cwd"] || Dir.pwd)
      @config = @project.config
    end

    def run
      usage = Usage::Store.new(home: @home).record(@payload["session_id"], Usage.from_statusline(@payload))
      alert = alert_for(usage)
      line = @wrap ? wrapped : render(usage)
      alert ? "#{line} | #{alert}" : line
    end

    private

    def render(usage)
      model = @payload.dig("model", "display_name") || usage.model_id || "?"
      effort = @payload.dig("effort", "level")
      tokens = usage.context_tokens.to_i
      cap = @config.cap_tokens
      pct = [(tokens * 100.0 / cap).round, 100].min
      filled = pct * BAR_WIDTH / 100
      bar = "[#{'#' * filled}#{'.' * (BAR_WIDTH - filled)}]"
      [
        [model, effort].compact.join(" "),
        "#{bar} #{Tokens.human(tokens)}/#{Tokens.human(cap)}",
        "CS #{limit(usage.session_pct)}",
        "WL #{limit(usage.weekly_pct)}"
      ].join(" | ")
    end

    def limit(pct)
      pct ? "#{pct.round}%" : "--"
    end

    def alert_for(usage)
      decision = ModelPolicy.new(@config).decide(
        model_id: usage.model_id, weekly_pct: usage.weekly_pct, session_pct: usage.session_pct
      )
      case decision.kind
      when :step_down_weekly, :pause_session then "mstack: /model #{@config.fallback_model}"
      when :step_up then "mstack: /model #{@config.default_model}"
      end
    end

    def wrapped
      out, = Open3.capture2(@wrap, stdin_data: JSON.generate(@payload))
      out.chomp
    rescue SystemCallError => e
      "mstack: wrapped status line failed (#{e.message})"
    end
  end
end
