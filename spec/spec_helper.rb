# frozen_string_literal: true

require "tmpdir"
require "stringio"
require_relative "../lib/mstack"

# Every example gets a throwaway project directory, a throwaway mstack home
# and a throwaway Claude config directory, so nothing touches the real ones.
module Sandbox
  def self.included(base)
    base.around do |example|
      Dir.mktmpdir("mstack-spec") do |dir|
        @sandbox = File.realpath(dir)
        saved = ENV.to_h.slice("MSTACK_HOME", "CLAUDE_CONFIG_DIR", "CLAUDE_PROJECT_DIR")
        ENV["MSTACK_HOME"] = File.join(@sandbox, "home")
        ENV["CLAUDE_CONFIG_DIR"] = File.join(@sandbox, "claude")
        ENV.delete("CLAUDE_PROJECT_DIR")
        FileUtils.mkdir_p(root)
        example.run
      ensure
        %w[MSTACK_HOME CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR].each { |key| ENV.delete(key) }
        saved.each { |key, value| ENV[key] = value }
      end
    end
  end

  def root
    File.join(@sandbox, "project")
  end

  def project
    Mstack::Project.new(root)
  end

  def write(relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def user_settings(hash)
    FileUtils.mkdir_p(ENV["CLAUDE_CONFIG_DIR"])
    File.write(File.join(ENV["CLAUDE_CONFIG_DIR"], "settings.json"), JSON.generate(hash))
  end

  # Builds a transcript file from compact record descriptions.
  def transcript(*records)
    path = File.join(@sandbox, "transcript.jsonl")
    File.write(path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
    path
  end

  def assistant(tokens, model: "claude-fable-5-2", content: [])
    {
      "type" => "assistant", "isSidechain" => false,
      "message" => {
        "model" => model, "content" => content,
        "usage" => { "input_tokens" => 2, "cache_creation_input_tokens" => 0, "cache_read_input_tokens" => tokens - 2, "output_tokens" => 100 }
      }
    }
  end

  def user(text)
    { "type" => "user", "isSidechain" => false, "message" => { "role" => "user", "content" => text } }
  end

  def compact_boundary
    { "type" => "system", "subtype" => "compact_boundary", "isSidechain" => false }
  end

  def edit(path)
    { "type" => "tool_use", "name" => "Edit", "input" => { "file_path" => path } }
  end

  def record_usage(session_id, weekly:, session:, model: "claude-fable-5-2", at: Time.now)
    usage = Mstack::Usage.new(model_id: model, weekly_pct: weekly, session_pct: session, recorded_at: at)
    Mstack::Usage::Store.new.record(session_id, usage)
  end
end

RSpec.configure do |config|
  config.include Sandbox
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
