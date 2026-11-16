# frozen_string_literal: true

require "open3"

module Mstack
  # A read-only look at the project's git working tree. It goes into the
  # snapshot taken before compaction: what is committed and what is still
  # in flight, however the files were written (Edit, Write or the shell).
  class GitState
    def initialize(root)
      @root = root
    end

    def repo?
      git("rev-parse", "--is-inside-work-tree") == ["true"]
    end

    def branch
      git("branch", "--show-current").first
    end

    def commits(limit = 5)
      git("log", "--oneline", "-#{limit}")
    end

    # Uncommitted paths in `git status --porcelain` form.
    def changes(limit = 30)
      git("status", "--porcelain").first(limit)
    end

    private

    def git(*args)
      out, _err, status = Open3.capture3("git", "-C", @root, *args)
      status.success? ? out.lines.map(&:chomp).reject(&:empty?) : []
    rescue SystemCallError
      []
    end
  end
end
