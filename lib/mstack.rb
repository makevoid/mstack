# frozen_string_literal: true

# mstack: one big agent, managed context, the best model you can afford.
# Stdlib only, so hooks run on any system Ruby without Bundler.
require "json"
require "yaml"
require "time"
require "fileutils"

module Mstack
  ROOT = File.expand_path("..", __dir__)

  # Claude Code's own config directory.
  def self.claude_dir
    ENV["CLAUDE_CONFIG_DIR"] || File.join(Dir.home, ".claude")
  end

  # Where mstack keeps machine-local state (usage snapshots, per-session
  # hook state). The status line and the hooks run in different processes
  # with different environments, so this must not depend on plugin env vars.
  def self.home
    ENV["MSTACK_HOME"] || File.join(claude_dir, "mstack")
  end
end

require_relative "mstack/version"
require_relative "mstack/tokens"
require_relative "mstack/config"
require_relative "mstack/project"
require_relative "mstack/gitignore"
require_relative "mstack/json_store"
require_relative "mstack/session_state"
require_relative "mstack/usage"
require_relative "mstack/transcript"
require_relative "mstack/git_state"
require_relative "mstack/session_memory"
require_relative "mstack/core_memories"
require_relative "mstack/context_monitor"
require_relative "mstack/model_policy"
require_relative "mstack/claude_settings"
require_relative "mstack/doctor"
require_relative "mstack/briefing"
require_relative "mstack/statusline"
require_relative "mstack/launcher"
require_relative "mstack/hooks"
require_relative "mstack/cli"
