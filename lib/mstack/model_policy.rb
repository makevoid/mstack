# frozen_string_literal: true

module Mstack
  # "Always use the top model you can afford." Given the current model and
  # plan usage, decides whether the session should keep going, step down to
  # the fallback model, pause, or step back up.
  #
  # Claude Code gives hooks no way to change the model, so every decision
  # other than :ok is delivered as a pause-and-ask: the agent stops and the
  # user runs /model.
  class ModelPolicy
    Decision = Struct.new(:kind, :message, :pause) do
      def ok?
        kind == :ok
      end
    end

    OK = Decision.new(:ok, nil, false).freeze

    def initialize(config)
      @default = config.default_model
      @fallback = config.fallback_model
      @weekly_switch = Float(config.dig(:limits, :weekly_switch_pct))
      @session_pause = Float(config.dig(:limits, :session_pause_pct))
    end

    def decide(model_id:, weekly_pct:, session_pct:)
      return OK if model_id.to_s.empty?

      weekly_hot = weekly_pct && weekly_pct >= @weekly_switch
      session_hot = session_pct && session_pct >= @session_pause

      if on?(model_id, @default)
        return step_down_weekly(weekly_pct) if weekly_hot
        return pause_session(session_pct) if session_hot
      elsif !weekly_pct.nil? && !session_pct.nil? && !weekly_hot && !session_hot
        return step_up(model_id, weekly_pct, session_pct)
      end
      OK
    end

    # Model ids come with suffixes ("claude-fable-5-2[1m]") and settings use
    # aliases ("fable"), so match loosely in both directions.
    def on?(model_id, wanted)
      a = model_id.to_s.downcase
      b = wanted.to_s.downcase
      return false if a.empty? || b.empty?

      a.include?(b) || b.include?(a)
    end

    private

    def step_down_weekly(pct)
      Decision.new(
        :step_down_weekly,
        "Weekly limit is at #{pct.round}% (threshold #{@weekly_switch.round}%) and this session is on " \
        "#{@default}. Switch to #{@fallback} for the rest of the week: run `/model #{@fallback}`.",
        true
      )
    end

    def pause_session(pct)
      Decision.new(
        :pause_session,
        "Current session limit is at #{pct.round}% (threshold #{@session_pause.round}%) on #{@default}. " \
        "Either run `/model #{@fallback}` to keep going, or wait for the session window to reset.",
        true
      )
    end

    def step_up(model_id, weekly_pct, session_pct)
      Decision.new(
        :step_up,
        "This session is on #{model_id}, but limits have room (weekly #{weekly_pct.round}%, " \
        "session #{session_pct.round}%). The top model is affordable: run `/model #{@default}`.",
        false
      )
    end
  end
end
