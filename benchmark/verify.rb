#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies a benchmark run: did the session compact, did mstack's memory
# machinery do its job around each compaction, did the agent stay a single
# agent, and does the app it built actually meet the spec.
#
#   ruby benchmark/verify.rb [run-name-or-path]     (default: the latest run)

require "json"
require "open3"
require_relative "../lib/mstack"

module Benchmark
  # The stream-json log of one headless session, as a sequence of events.
  class Stream
    def initialize(path)
      @events = File.foreach(path).filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    def result
      @events.reverse.find { |event| event["type"] == "result" }
    end

    def session_id
      @events.find { |event| event["session_id"] }&.fetch("session_id")
    end

    def compactions
      @events.select { |event| event["type"] == "system" && event["subtype"] == "compact_boundary" }
    end

    def hook_outputs(event_name)
      @events.select { |event| event["subtype"] == "hook_response" && event["hook_event"] == event_name }
             .map { |event| event["output"].to_s + event["stdout"].to_s }
    end

    def tool_uses
      @events.each_with_index.flat_map do |event, index|
        next [] unless event["type"] == "assistant" && event["parent_tool_use_id"].nil?

        Array(event.dig("message", "content")).select { |part| part["type"] == "tool_use" }
                                              .map { |part| part.merge("index" => index) }
      end
    end

    def peak_context
      @events.filter_map do |event|
        usage = event.dig("message", "usage") if event["type"] == "assistant"
        usage && %w[input_tokens cache_read_input_tokens cache_creation_input_tokens].sum { |key| usage[key].to_i }
      end.max
    end

    def index_of(event)
      @events.index(event)
    end
  end

  # What hooks injected into the model's context. The event stream does not
  # carry it, but Claude Code's own session transcript records each one.
  class Injections
    def initialize(session_id)
      path = Dir.glob(File.join(Mstack.claude_dir, "projects", "*", "#{session_id}.jsonl")).first
      @texts = path ? File.foreach(path).filter_map { |line| text_of(line) } : []
    end

    def count(phrase)
      @texts.count { |text| text.include?(phrase) }
    end

    private

    def text_of(line)
      return nil unless line.include?("hook_additional_context")

      JSON.parse(line).dig("attachment", "content").to_s
    rescue JSON::ParserError
      nil
    end
  end

  class Verify
    PROBE = File.join(__dir__, "probe", "acceptance_spec.rb")
    Check = Struct.new(:name, :ok, :detail)

    def initialize(dir)
      @dir = dir
      @app = File.join(dir, "app")
      @stream = Stream.new(File.join(dir, "stream.jsonl"))
      @meta = JSON.parse(File.read(File.join(dir, "run.json")))
      @checks = []
    end

    def call
      session
      context
      memory
      single_agent
      app_quality
      report
      @checks.all?(&:ok)
    end

    private

    def check(name, ok, detail = "")
      @checks << Check.new(name, ok ? true : false, detail)
    end

    def session
      result = @stream.result
      check("session finished without error", result && !result["is_error"],
            result ? "#{result['num_turns']} turns, #{(result['duration_ms'].to_i / 60_000.0).round(1)} min, $#{result['total_cost_usd'].to_f.round(2)}" : "no result event")
      errors = File.join(@dir, "mstack-home", "error.log")
      check("no hook errors", !File.exist?(errors), File.exist?(errors) ? File.read(errors).lines.first(3).join.strip : "")
    end

    def context
      cap = @meta["cap_tokens"]
      compactions = @stream.compactions
      pre = compactions.map { |event| event.dig("compact_metadata", "pre_tokens") || event.dig("compactMetadata", "preTokens") }
      check("context cap was reached and the session compacted", compactions.any?,
            "#{compactions.size} compactions at #{pre.map { |tokens| Mstack::Tokens.human(tokens) }.join(', ')} tokens (cap #{Mstack::Tokens.human(cap)})")
      peak = @stream.peak_context
      check("context stayed under the cap", peak && peak <= cap * 1.05, "peak #{Mstack::Tokens.human(peak)} tokens")
    end

    def memory
      injected = Injections.new(@stream.session_id)
      regular = injected.count("mstack checkpoint:")
      final = injected.count("mstack FINAL checkpoint")
      check("checkpoints were requested as context filled", (regular + final).positive?, "#{regular} regular, #{final} final")

      file = Dir.glob(File.join(@app, "docs/mstack/sessions/*.md")).first
      check("session memory file exists", !file.nil?, file ? File.basename(file) : "")
      return unless file

      text = File.read(file)
      memory = Mstack::SessionMemory.new(Mstack::Project.new(@app), File.basename(file, ".md").split("-").last)
      check("the agent wrote real session memory", !memory.pristine?, "#{text.length} chars, ~#{Mstack::Tokens.estimate(text)} tokens")
      check("PreCompact left its snapshot", text.include?(Mstack::SessionMemory::SNAPSHOT_OPEN) == @stream.compactions.any?)

      writes = @stream.tool_uses.select { |use| writes_session_memory?(use) }
      first_compaction = @stream.compactions.first && @stream.index_of(@stream.compactions.first)
      before = first_compaction ? writes.count { |use| use["index"] < first_compaction } : writes.size
      check("session memory was written before the first compaction", before.positive?, "#{writes.size} writes in total, #{before} before the first compaction")

      restores = injected.count("just compacted")
      check("session memory was reloaded after every compaction", restores == @stream.compactions.size,
            "#{restores} reloads for #{@stream.compactions.size} compactions")

      ignored = system("git", "check-ignore", "-q", file, chdir: @app)
      tracked, = Open3.capture2("git", "ls-files", "docs/mstack/sessions", chdir: @app)
      check("session memory is gitignored and was never committed", ignored && tracked.strip.empty?)

      core = Dir.glob(File.join(@app, "docs/mstack/core_memories/*.md"))
      check("core memories stayed sparing", core.size <= 3, "#{core.size} written: #{core.map { |path| File.basename(path) }.join(', ')}")
    end

    # Agents write the file with Edit/Write or with a shell redirect.
    def writes_session_memory?(use)
      sessions = "docs/mstack/sessions/"
      case use["name"]
      when "Edit", "Write" then use.dig("input", "file_path").to_s.include?(sessions)
      when "Bash"
        command = use.dig("input", "command").to_s
        command.include?(sessions) && command.match?(/>|<<|\btee\b|\bsed -i\b|write/)
      else false
      end
    end

    def single_agent
      spawns = @stream.tool_uses.select { |use| %w[Agent Task Workflow].include?(use["name"]) }
      check("single agent: no subagents were spawned", spawns.empty?, "#{spawns.size} spawn attempts, #{@stream.tool_uses.size} tool calls in total")
    end

    def app_quality
      own = rspec(@app, [])
      check("the app's own spec suite passes", own[:failures]&.zero? && own[:examples].to_i.positive?, "#{own[:examples]} examples, #{own[:failures]} failures")
      probe = rspec(@app, [PROBE])
      check("hidden acceptance probe passes", probe[:failures]&.zero? && probe[:examples].to_i.positive?,
            "#{probe[:examples]} examples, #{probe[:failures]} failures#{probe[:failed].empty? ? '' : "\n      - #{probe[:failed].join("\n      - ")}"}")
      log, = Open3.capture2("git", "log", "--oneline", chdir: @app)
      check("work was committed phase by phase", log.lines.size >= 4, "#{log.lines.size} commits")
    end

    def rspec(dir, args)
      out, = Open3.capture2e({ "RACK_ENV" => "test", "DATABASE_URL" => nil }, "bundle", "exec", "rspec", "--format", "json", *args, chdir: dir)
      json = JSON.parse(out[out.index('{"version"')..] || "{}")
      {
        examples: json.dig("summary", "example_count"),
        failures: json.dig("summary", "failure_count").to_i + json.dig("summary", "errors_outside_of_examples_count").to_i,
        failed: json.fetch("examples", []).select { |example| example["status"] == "failed" }.map { |example| example["full_description"] }
      }
    rescue StandardError => e
      { examples: 0, failures: nil, failed: ["could not run: #{e.message[0, 200]}"] }
    end

    def report
      puts "mstack benchmark: #{@dir}"
      puts "#{@meta['model']} @ #{@meta['effort']}, cap #{@meta['cap_tokens']} tokens"
      puts
      @checks.each do |check|
        puts "#{check.ok ? '[pass]' : '[FAIL]'} #{check.name}#{check.detail.empty? ? '' : " (#{check.detail})"}"
      end
      puts
      puts "#{@checks.count(&:ok)}/#{@checks.size} checks passed"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  runs = ENV["MSTACK_BENCHMARK_DIR"] || File.join(Dir.home, ".cache", "mstack", "benchmark")
  target = ARGV.first
  dir = if target.nil? then Dir.glob(File.join(runs, "*")).select { |path| File.directory?(path) }.max_by { |path| File.mtime(path) }
        elsif File.directory?(target) then target
        else File.join(runs, target)
        end
  abort "no benchmark run found in #{runs}" unless dir && File.exist?(File.join(dir, "stream.jsonl"))
  exit(Benchmark::Verify.new(dir).call ? 0 : 1)
end
