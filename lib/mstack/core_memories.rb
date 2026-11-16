# frozen_string_literal: true

module Mstack
  # docs/mstack/core_memories/*.md: short, crystallized, committed facts
  # that every future session should start with. They are loaded on every
  # session start, so their total size is budgeted.
  class CoreMemories
    Entry = Struct.new(:path, :title, :body) do
      def tokens
        Tokens.estimate(body)
      end
    end

    # A single memory longer than this is not "crystallized" any more.
    MAX_ENTRY_TOKENS = 200

    attr_reader :project

    def initialize(project)
      @project = project
    end

    def entries
      @entries ||= Dir.glob(File.join(project.core_memories_dir, "*.md")).sort.map do |path|
        body = File.read(path).strip
        Entry.new(path, title_of(body, path), body)
      end
    end

    def empty?
      entries.empty?
    end

    def total_tokens
      entries.sum(&:tokens)
    end

    def budget_tokens
      Integer(project.config.dig(:context, :core_memories_budget_tokens))
    end

    def within_budget?
      total_tokens <= budget_tokens
    end

    def oversized
      entries.select { |entry| entry.tokens > MAX_ENTRY_TOKENS }
    end

    # Every memory in full.
    def full
      entries.map(&:body).join("\n\n")
    end

    # One line per memory, for when the full set is too big to load.
    def index
      entries.map { |entry| "- #{project.relative(entry.path)}: #{entry.title}" }.join("\n")
    end

    private

    def title_of(body, path)
      heading = body.lines.find { |line| line.start_with?("#") }
      (heading ? heading.sub(/\A#+\s*/, "") : File.basename(path, ".md")).strip
    end
  end
end
