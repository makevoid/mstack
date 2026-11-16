# frozen_string_literal: true

module Mstack
  # Turns a context-token reading into checkpoint decisions. Checkpoints
  # are percentages of the compaction point, the size at which Claude Code
  # really compacts (a reserve below the configured cap), so the final one
  # always leaves headroom whatever the cap is.
  class ContextMonitor
    Status = Struct.new(:tokens, :compaction_point, :level, :final) do
      def pct
        (tokens * 100.0 / compaction_point).round
      end

      def headroom
        [compaction_point - tokens, 0].max
      end
    end

    def initialize(config)
      @point = config.compaction_point
      @checkpoints = config.checkpoints
    end

    def status(tokens)
      level = @checkpoints.rindex { |pct| tokens * 100 >= pct * @point } || -1
      Status.new(tokens, @point, level, level == @checkpoints.size - 1 && level >= 0)
    end

    # Returns a Status when the context just crossed into a higher
    # checkpoint than any announced so far in this window, nil otherwise.
    # Each checkpoint is announced once; a shrunken context (compaction,
    # /clear) quietly re-arms the ones above it.
    def check!(tokens, state)
      return nil if tokens.nil?

      current = status(tokens)
      announced = state.checkpoint_level
      if announced.nil? || current.level < announced
        state.baseline_checkpoint!(current.level)
        return nil
      end
      return nil unless current.level > announced

      state.announce_checkpoint!(current.level)
      current
    end
  end
end
