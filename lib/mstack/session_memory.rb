# frozen_string_literal: true

module Mstack
  # The per-session memory file: docs/mstack/sessions/<timestamp>-<id>.md.
  # The agent keeps it current as context fills up; after a compaction it is
  # the authoritative record of what the session was doing. Local only.
  class SessionMemory
    SNAPSHOT_OPEN = "<!-- mstack:auto-snapshot -->"
    SNAPSHOT_CLOSE = "<!-- /mstack:auto-snapshot -->"
    TRIM_MARKER = "\n\n[… middle of session memory trimmed by mstack; Read the file for the rest …]\n\n"

    attr_reader :project, :session_id

    # started_at names the file, so it must be the same for the whole session.
    def initialize(project, session_id, started_at: SessionState.new(session_id).started_at)
      @project = project
      @session_id = session_id.to_s
      @started_at = started_at
    end

    def short_id
      session_id.gsub(/[^A-Za-z0-9]/, "")[0, 8]
    end

    # The existing file for this session, or the name a new one would get.
    def path
      @path ||= existing_path || File.join(project.sessions_dir, "#{@started_at.strftime('%Y%m%d-%H%M%S')}-#{short_id}.md")
    end

    def relative_path
      project.relative(path)
    end

    def exist?
      File.file?(path)
    end

    # Creates the file from the template if needed. Returns the path.
    def ensure!
      unless exist?
        FileUtils.mkdir_p(project.sessions_dir)
        File.write(path, template)
      end
      path
    end

    def read
      exist? ? File.read(path) : ""
    end

    # True while the agent has written nothing: only template placeholders.
    def pristine?
      return true unless exist?

      text = read
      template.scan(/^_\(.*\)_$/).all? { |placeholder| text.include?(placeholder) }
    end

    def updated_since?(time)
      exist? && File.mtime(path) > time
    end

    # Content sized to a token budget. The head (goal, state) and the tail
    # (most recent notes) matter most, so an oversized file loses its middle.
    def render(budget_tokens)
      text = read
      limit = Tokens.chars(budget_tokens)
      return text if text.length <= limit

      keep = limit - TRIM_MARKER.length
      head = keep / 2
      "#{text[0, head]}#{TRIM_MARKER}#{text[-(keep - head)..]}"
    end

    # Replaces the mechanical snapshot block. Written by the PreCompact hook
    # so that even a session the agent never checkpointed leaves a trail.
    def write_snapshot!(digest, tokens:, trigger:, at: Time.now, git: GitState.new(project.root))
      ensure!
      block = snapshot_block(digest, git, tokens: tokens, trigger: trigger, at: at)
      File.write(path, "#{without_snapshot(read).rstrip}\n\n#{block}\n")
      path
    end

    # Other sessions' files, newest first.
    def self.recent(project, limit: 3, except: nil)
      Dir.glob(File.join(project.sessions_dir, "*.md"))
         .reject { |file| file == except }
         .sort_by { |file| File.mtime(file) }
         .reverse
         .first(limit)
    end

    private

    def existing_path
      return nil if short_id.empty?

      Dir.glob(File.join(project.sessions_dir, "*-#{short_id}.md")).max
    end

    def without_snapshot(text)
      text.sub(/\n*#{Regexp.escape(SNAPSHOT_OPEN)}.*?#{Regexp.escape(SNAPSHOT_CLOSE)}\n*/m, "\n")
    end

    def snapshot_block(digest, git, tokens:, trigger:, at:)
      lines = [SNAPSHOT_OPEN, "## Auto-snapshot before compaction", ""]
      lines << "_Written by the mstack PreCompact hook at #{at.strftime('%Y-%m-%d %H:%M:%S')} " \
               "(#{trigger} compaction, last context reading #{Tokens.human(tokens)} tokens, " \
               "compaction ##{digest.compactions + 1}). Mechanical; the sections above are authoritative._"
      lines << "" << "### Recent user prompts"
      lines.concat(list(digest.prompts.map { |prompt| prompt.gsub(/\s+/, " ") }))
      lines << "" << "### Files edited with Edit/Write"
      lines.concat(list(digest.files.map { |file| project.relative(file) }))
      lines.concat(git_lines(git))
      lines << SNAPSHOT_CLOSE
      lines.join("\n")
    end

    def list(items)
      items.empty? ? ["- (none recorded)"] : items.map { |item| "- #{item}" }
    end

    # The working tree catches what the transcript cannot: files written
    # through the shell, and what was already committed.
    def git_lines(git)
      return [] unless git.repo?

      ["", "### Git working tree (branch #{git.branch || 'unknown'})", "Uncommitted:"] +
        list(git.changes.map { |line| "`#{line}`" }) + ["Recent commits:"] + list(git.commits)
    end

    def template
      <<~MARKDOWN
        # Session #{@started_at.strftime('%Y-%m-%d %H:%M')} (#{short_id})

        <!-- mstack session memory. Local only (gitignored). The agent keeps it current;
             it is reloaded after every compaction. Write for a reader with zero context. -->

        ## Goal
        _(what the user wants, in their words, and the problem behind it)_

        ## State
        _(done / in progress / exact next step. Rewrite this section at every checkpoint.)_

        ## Decisions
        _(decision, then why. Append only.)_

        ## Facts and gotchas
        _(exact commands, paths, values and fixes that would be costly to rediscover)_

        ## Open questions
        _(what is undecided or waiting on the user)_
      MARKDOWN
    end
  end
end
