# frozen_string_literal: true

module Mstack
  # `mstack <command>`: the entry point for hooks, the status line and the
  # handful of commands the skills run.
  class CLI
    USAGE = <<~TEXT
      mstack #{VERSION}: one big agent, managed context, the best model you can afford.

      Usage:
        mstack init                  set up this project (.mstackrc, docs/mstack/, .gitignore)
        mstack doctor                check requirements (context cap, model, effort, status line)
        mstack status                show config, plan usage and memory sizes
        mstack session               print (and create) this session's memory file path
        mstack statusline [--wrap CMD]   status line command; records plan usage for the hooks
        mstack hook <event>          hook handler (reads the hook JSON on stdin)
        mstack version
    TEXT

    def initialize(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @argv = argv.dup
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def run
      command = @argv.shift
      case command
      when "init" then init
      when "doctor" then doctor
      when "status" then status
      when "session" then session
      when "statusline" then statusline
      when "hook" then hook
      when "version", "--version", "-v" then @stdout.puts(VERSION)
      when nil, "help", "--help", "-h" then @stdout.puts(USAGE)
      else
        @stderr.puts("mstack: unknown command #{command.inspect}\n\n#{USAGE}")
        return 1
      end || 0
    end

    private

    def project
      @project ||= Project.locate
    end

    def init
      changes = project.init!
      changes << "installed status line launcher" if launcher.install!
      @stdout.puts(changes.empty? ? "mstack: already initialized in #{project.root}" : "mstack: #{changes.join(', ')}")
      @stdout.puts(Doctor.new(project).report)
      0
    end

    def doctor
      doctor = Doctor.new(project)
      @stdout.puts(doctor.report)
      doctor.problems.empty? ? 0 : 1
    end

    def status
      config = project.config
      usage = Usage::Store.new.load(nil)
      memories = CoreMemories.new(project)
      latest = SessionMemory.recent(project, limit: 1).first
      @stdout.puts(<<~TEXT)
        project:        #{project.root} (#{project.initialized? ? 'initialized' : 'not initialized'})
        model policy:   #{config.default_model} @ #{config.effort}, fallback #{config.fallback_model}
        limits:         weekly #{pct(usage.weekly_pct)} (step down at #{config.dig(:limits, :weekly_switch_pct)}%), session #{pct(usage.session_pct)} (pause at #{config.dig(:limits, :session_pause_pct)}%)
        context cap:    #{config.cap_tokens} tokens, checkpoints at #{config.checkpoints.join('/')}%
        core memories:  #{memories.entries.size} files, ~#{memories.total_tokens} tokens (budget #{memories.budget_tokens}, auto-write #{config.core_memories? ? 'on' : 'off'})
        status line:    #{launcher.path}
        last session:   #{latest ? project.relative(latest) : 'none'}
        subagents:      #{config.subagents? ? 'allowed' : 'denied'}
      TEXT
      0
    end

    def launcher
      @launcher ||= Launcher.new
    end
    
    # The session id comes from the argument or from the environment Claude
    # Code gives every Bash tool call.
    def session
      id = @argv.shift || ENV["CLAUDE_CODE_SESSION_ID"]
      if id.to_s.empty?
        @stderr.puts("mstack: no session id (pass one, or run inside Claude Code)")
        return 1
      end
      unless project.initialized?
        @stderr.puts("mstack: project not initialized; run `mstack init`")
        return 1
      end
      @stdout.puts(project.relative(SessionMemory.new(project, id).ensure!))
      0
    end

    def pct(value)
      value ? "#{value.round}%" : "unknown (status line not reporting)"
    end

    def statusline
      wrap = @argv[@argv.index("--wrap") + 1] if @argv.include?("--wrap")
      payload = parse(@stdin.read)
      @stdout.puts(Statusline.new(payload, wrap: wrap).run)
      0
    end

    # A hook must never break the session it runs in: any failure is logged
    # and swallowed, and the hook exits 0 with no output.
    def hook
      name = @argv.shift
      result = Hooks.run(name, parse(@stdin.read))
      case result
      when Hash then @stdout.puts(JSON.generate(result))
      when String then @stdout.puts(result)
      end
      0
    rescue StandardError => e
      log_error(name, e)
      0
    end

    def parse(text)
      text.to_s.strip.empty? ? {} : JSON.parse(text)
    rescue JSON::ParserError
      {}
    end

    def log_error(name, error)
      FileUtils.mkdir_p(Mstack.home)
      File.open(File.join(Mstack.home, "error.log"), "a") do |file|
        file.puts("#{Time.now.iso8601} hook=#{name} #{error.class}: #{error.message}")
        file.puts(error.backtrace.first(8).map { |line| "  #{line}" })
      end
    rescue StandardError
      nil
    end
  end
end
