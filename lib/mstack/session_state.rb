# frozen_string_literal: true

module Mstack
  # What the hooks remember about one Claude Code session between
  # invocations: which context checkpoint was last announced, which model
  # policy notices were already delivered, how many compactions happened.
  class SessionState
    def initialize(session_id, home: Mstack.home)
      @store = JsonStore.new(File.join(home, "state", "#{safe(session_id)}.json"))
    end

    def to_h
      @store.read
    end

    # When mstack first saw this session. Fixed from then on, so that the
    # session memory file gets the same name whenever it is asked for.
    def started_at(now = Time.now)
      at = to_h["started_at"]
      return Time.at(at) if at

      @store.update { |s| s["started_at"] = now.to_f }
      now
    end

    # Index into Config#checkpoints of the last announced checkpoint: -1 when
    # none was announced yet, nil when unknown (right after a compaction, so
    # the next reading becomes the new baseline instead of a fresh nudge).
    def checkpoint_level
      to_h.fetch("checkpoint_level", -1)
    end

    # Adopt a level without asking the agent for anything.
    def baseline_checkpoint!(level)
      @store.update { |s| s["checkpoint_level"] = level }
    end

    def announce_checkpoint!(level, at: Time.now)
      @store.update do |s|
        s["checkpoint_level"] = level
        s["checkpoint_requested_at"] = at.to_f
        s["checkpoint_enforced"] = false
      end
    end

    def checkpoint_requested_at
      at = to_h["checkpoint_requested_at"]
      at && Time.at(at)
    end

    def checkpoint_enforced?
      to_h["checkpoint_enforced"] == true
    end

    def checkpoint_enforced!
      @store.update { |s| s["checkpoint_enforced"] = true }
    end

    def compactions
      to_h.fetch("compactions", 0)
    end

    # A compaction opens a new context window. The agent is asked to
    # reconcile its session memory with the summary straight away, which
    # the Stop hook enforces like any other checkpoint.
    def compacted!(at: Time.now)
      @store.update do |s|
        s["compactions"] = s.fetch("compactions", 0) + 1
        s["checkpoint_level"] = nil
        s["window_started_at"] = at.to_f
        s["checkpoint_requested_at"] = at.to_f
        s["checkpoint_enforced"] = false
      end
    end

    # When the current context window began: the last compaction, or the
    # start of the session.
    def window_started_at
      at = to_h["window_started_at"]
      at ? Time.at(at) : started_at
    end

    # Recorded just before a compaction: did the agent leave the window
    # without writing anything to its session memory?
    def memory_stale!(stale)
      @store.update { |s| s["memory_stale"] = stale ? true : false }
    end

    def memory_stale?
      to_h["memory_stale"] == true
    end

    def noticed?(kind)
      to_h.fetch("notices", {}).key?(kind.to_s)
    end

    def noticed!(kind, at: Time.now)
      @store.update { |s| (s["notices"] ||= {})[kind.to_s] = at.to_f }
    end

    private

    def safe(session_id)
      session_id.to_s.gsub(/[^A-Za-z0-9_-]/, "_")
    end
  end
end
