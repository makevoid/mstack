# frozen_string_literal: true

module Mstack
  # Reads a Claude Code session transcript (JSONL). Hooks get no token
  # counts on stdin, but every assistant record in the transcript carries
  # the API usage of the request that produced it, which is exactly how
  # full the context window was at that point.
  class Transcript
    TAIL_WINDOWS = [256 * 1024, 4 * 1024 * 1024].freeze
    EDIT_TOOLS = %w[Edit Write NotebookEdit MultiEdit].freeze

    Reading = Struct.new(:tokens, :model_id)
    Digest = Struct.new(:prompts, :files, :compactions)

    def initialize(path)
      @path = path
    end

    def exist?
      !@path.nil? && File.file?(@path)
    end

    # Context size and model as of the last main-thread API response.
    # tokens is nil right after a compaction, when the last recorded usage
    # describes a window that no longer exists.
    def reading
      return Reading.new(nil, nil) unless exist?

      (TAIL_WINDOWS + [File.size(@path)]).each do |window|
        found = reading_from(tail_lines(window))
        return found if found
        break if window >= File.size(@path)
      end
      Reading.new(nil, nil)
    end

    def context_tokens
      reading.tokens
    end

    # A mechanical summary of the session, used as the safety net snapshot
    # written before compaction.
    def digest(max_prompts: 8, max_files: 40)
      prompts = []
      files = []
      compactions = 0
      each_record do |record|
        next if record["isSidechain"]

        case record["type"]
        when "system"
          compactions += 1 if record["subtype"] == "compact_boundary"
        when "user"
          text = user_prompt(record)
          prompts << text if text
        when "assistant"
          files.concat(edited_files(record))
        end
      end
      Digest.new(prompts.last(max_prompts), files.uniq.last(max_files), compactions)
    end

    private

    def reading_from(lines)
      lines.reverse_each do |line|
        record = parse(line)
        next unless record && !record["isSidechain"]
        return Reading.new(nil, nil) if record["type"] == "system" && record["subtype"] == "compact_boundary"
        next unless record["type"] == "assistant"

        usage = record.dig("message", "usage")
        next unless usage

        return Reading.new(input_tokens(usage), record.dig("message", "model"))
      end
      nil
    end

    def input_tokens(usage)
      %w[input_tokens cache_creation_input_tokens cache_read_input_tokens].sum { |key| usage[key].to_i }
    end

    def tail_lines(window)
      File.open(@path, "rb") do |file|
        size = file.size
        start = [size - window, 0].max
        file.seek(start)
        lines = file.read.force_encoding("UTF-8").scrub.lines
        lines.shift if start.positive? # first line is probably cut in half
        lines
      end
    end

    def each_record
      return unless exist?

      File.foreach(@path) do |line|
        record = parse(line)
        yield record if record
      end
    end

    def parse(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    def user_prompt(record)
      return nil if record["isMeta"] || record["isCompactSummary"]

      content = record.dig("message", "content")
      text =
        case content
        when String then content
        when Array
          return nil if content.any? { |part| part["type"] == "tool_result" }

          content.filter_map { |part| part["text"] if part["type"] == "text" }.join("\n")
        end
      text = text.to_s.strip
      # Harness-injected turns (command output, reminders) are not the user's words.
      return nil if text.empty? || text.start_with?("<", "This session is being continued")

      text.length > 400 ? "#{text[0, 400]}…" : text
    end

    def edited_files(record)
      Array(record.dig("message", "content")).filter_map do |part|
        next unless part.is_a?(Hash) && part["type"] == "tool_use" && EDIT_TOOLS.include?(part["name"])

        part.dig("input", "file_path") || part.dig("input", "notebook_path")
      end
    end
  end
end
