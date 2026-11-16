#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the mstack benchmark: one headless Claude Code session builds the
# Tasklane app (benchmark/PROMPT.md) with the mstack plugin loaded and a
# deliberately small context cap, so the session has to compact several
# times and the memory machinery is exercised for real.
#
#   ruby benchmark/run.rb [--cap 100000] [--model claude-fable-5-2] [--effort high]
#
# Spends plan usage. Verify afterwards with `ruby benchmark/verify.rb`.

require "json"
require "fileutils"
require "optparse"
require_relative "../lib/mstack"

module Benchmark
  class Run
    ROOT = File.expand_path("..", __dir__)
    # Runs live outside this repository: Claude Code treats files under a
    # loaded plugin's directory as sensitive and refuses to edit them.
    RUNS = ENV["MSTACK_BENCHMARK_DIR"] || File.join(Dir.home, ".cache", "mstack", "benchmark")
    # Variables a nested session must not inherit from the session that launched it.
    INHERITED = %w[
      CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
      CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID
      CLAUDE_EFFORT CLAUDE_PROJECT_DIR CLAUDE_CODE_EXECPATH AI_AGENT
    ].freeze
    # An API key in the environment would take precedence over the Claude login and
    # bill a different account. The benchmark runs on the plan, like a normal session.
    API_KEYS = %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN].freeze
    # Agent is allowed on purpose: the mstack hook must be what denies a spawn.
    TOOLS = "Bash,Read,Write,Edit,Glob,Grep,Skill,TodoWrite,Agent"

    def initialize(cap:, model:, effort:, prompt:, name:, usage: nil)
      @usage = usage
      @cap = cap
      @model = model
      @effort = effort
      @prompt = prompt
      @dir = File.join(RUNS, name)
      @app = File.join(@dir, "app")
    end

    def call
      prepare
      File.write(File.join(@dir, "run.json"), JSON.pretty_generate(meta))
      puts "benchmark: #{@dir}"
      puts "benchmark: cap #{@cap} tokens, #{@model} @ #{@effort}; streaming to stream.jsonl"
      started = Time.now
      ok = system(env, *command, chdir: @app, in: @prompt, out: File.join(@dir, "stream.jsonl"),
                                 err: File.join(@dir, "stderr.log"), unsetenv_others: false)
      File.write(File.join(@dir, "run.json"), JSON.pretty_generate(meta.merge("exit_ok" => ok, "seconds" => (Time.now - started).round)))
      puts "benchmark: finished in #{(Time.now - started).round}s (exit #{ok ? 'ok' : 'FAILED'})"
      ok
    end

    private

    def prepare
      FileUtils.mkdir_p(File.join(@app, ".claude"))
      system("git", "init", "-q", chdir: @app) or abort "git init failed"
      File.write(File.join(@app, ".mstackrc"), "context:\n  cap_tokens: #{@cap}\n")
      File.write(File.join(@app, ".claude", "settings.json"), JSON.pretty_generate(settings))
      system({ "MSTACK_HOME" => home }, File.join(ROOT, "bin", "mstack"), "init", chdir: @app, out: File.join(@dir, "init.log")) or abort "mstack init failed"
      seed_usage if @usage
    end

    # Headless sessions have no status line, so plan usage never reaches the
    # hooks. Seeding a snapshot lets a run exercise the model policy.
    def seed_usage
      weekly, session = @usage
      snapshot = Mstack::Usage.new(weekly_pct: weekly, session_pct: session, recorded_at: Time.now)
      Mstack::Usage::Store.new(home: home).record(nil, snapshot)
    end

    def settings
      { "autoCompactWindow" => @cap, "model" => @model, "effortLevel" => @effort }
    end

    def home
      File.join(@dir, "mstack-home")
    end

    def env
      (INHERITED + API_KEYS).to_h { |key| [key, nil] }.merge("MSTACK_HOME" => home)
    end

    def command
      [
        "claude", "-p",
        "--plugin-dir", ROOT,
        "--model", @model,
        "--effort", @effort,
        "--settings", JSON.generate(settings),
        "--permission-mode", "acceptEdits",
        "--allowedTools", TOOLS,
        "--output-format", "stream-json",
        "--verbose"
      ]
    end

    def meta
      { "cap_tokens" => @cap, "model" => @model, "effort" => @effort, "prompt" => @prompt,
        "app" => @app, "started_at" => Time.now.to_s, "command" => command }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { cap: 100_000, model: "claude-fable-5-2", effort: "high",
              prompt: File.join(__dir__, "PROMPT.md"), name: Time.now.strftime("%Y%m%d-%H%M%S") }
  OptionParser.new do |parser|
    parser.on("--cap TOKENS", Integer) { |value| options[:cap] = value }
    parser.on("--model MODEL") { |value| options[:model] = value }
    parser.on("--effort LEVEL") { |value| options[:effort] = value }
    parser.on("--prompt FILE") { |value| options[:prompt] = File.expand_path(value) }
    parser.on("--name NAME") { |value| options[:name] = value }
    parser.on("--usage WEEKLY,SESSION", Array, "seed plan usage percentages") { |value| options[:usage] = value.map(&:to_f) }
  end.parse!
  exit(Benchmark::Run.new(**options).call ? 0 : 1)
end
