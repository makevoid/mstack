# frozen_string_literal: true

module Mstack
  # A snapshot of plan usage. Claude Code only exposes rate limits to the
  # status line, never to hooks, so the mstack status line records each
  # payload it sees and the hooks read it back from disk.
  class Usage
    attr_reader :model_id, :session_pct, :weekly_pct, :context_tokens, :recorded_at

    def initialize(model_id: nil, session_pct: nil, weekly_pct: nil, context_tokens: nil, recorded_at: nil)
      @model_id = model_id
      @session_pct = session_pct
      @weekly_pct = weekly_pct
      @context_tokens = context_tokens
      @recorded_at = recorded_at
    end

    def self.from_statusline(payload, at: Time.now)
      limits = payload["rate_limits"] || {}
      new(
        model_id: payload.dig("model", "id"),
        session_pct: limits.dig("five_hour", "used_percentage"),
        weekly_pct: limits.dig("seven_day", "used_percentage"),
        context_tokens: payload.dig("context_window", "total_input_tokens"),
        recorded_at: at
      )
    end

    def self.from_h(hash)
      at = hash["recorded_at"]
      new(
        model_id: hash["model_id"],
        session_pct: hash["session_pct"],
        weekly_pct: hash["weekly_pct"],
        context_tokens: hash["context_tokens"],
        recorded_at: at && Time.at(at)
      )
    end

    def to_h
      {
        "model_id" => model_id,
        "session_pct" => session_pct,
        "weekly_pct" => weekly_pct,
        "context_tokens" => context_tokens,
        "recorded_at" => recorded_at&.to_f
      }
    end

    def limits_known?
      !session_pct.nil? || !weekly_pct.nil?
    end

    def stale?(max_age_minutes, now: Time.now)
      recorded_at.nil? || (now - recorded_at) > max_age_minutes * 60
    end

    # Persists snapshots under <home>/usage: one per session, plus `latest`.
    # Limits are account-wide, so a brand-new session can use the latest
    # snapshot from any session until its own status line has rendered.
    class Store
      def initialize(home: Mstack.home)
        @dir = File.join(home, "usage")
      end

      def record(session_id, usage)
        store(session_id).write(usage.to_h) if session_id
        # Before the first API response a payload carries no limits; don't
        # let it clobber a useful account-wide snapshot.
        store("latest").write(usage.to_h) if usage.limits_known?
        usage
      end

      # This session's model and context, with limits from this session if it
      # has them and from the account-wide latest snapshot otherwise.
      def load(session_id)
        own = session_id ? store(session_id).read : {}
        limits = Usage.from_h(own).limits_known? ? own : store("latest").read
        Usage.from_h(
          "model_id" => own["model_id"],
          "context_tokens" => own["context_tokens"],
          "session_pct" => limits["session_pct"],
          "weekly_pct" => limits["weekly_pct"],
          "recorded_at" => limits["recorded_at"] || own["recorded_at"]
        )
      end

      private

      def store(name)
        JsonStore.new(File.join(@dir, "#{name.to_s.gsub(/[^A-Za-z0-9_-]/, '_')}.json"))
      end
    end
  end
end
