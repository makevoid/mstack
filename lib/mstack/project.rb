# frozen_string_literal: true

module Mstack
  # A project that mstack works in: its root, its config and the two memory
  # directories. Memory files are only ever written in a project that was
  # explicitly initialized, so opening Claude in an arbitrary repo never
  # dirties its tree.
  class Project
    MEMORY_DIR = File.join("docs", "mstack")
    SESSIONS_DIR = File.join(MEMORY_DIR, "sessions")
    CORE_MEMORIES_DIR = File.join(MEMORY_DIR, "core_memories")

    attr_reader :root

    def self.locate(cwd = nil)
      new(ENV["CLAUDE_PROJECT_DIR"] || cwd || Dir.pwd)
    end

    def initialize(root)
      @root = File.expand_path(root)
    end

    def config
      @config ||= Config.load(root)
    end

    def sessions_dir
      File.join(root, SESSIONS_DIR)
    end

    def core_memories_dir
      File.join(root, CORE_MEMORIES_DIR)
    end

    def initialized?
      config.exist? || File.directory?(File.join(root, MEMORY_DIR))
    end

    def relative(path)
      path.to_s.delete_prefix("#{root}/")
    end

    # Idempotent. Returns the list of things it actually changed.
    def init!
      changes = []
      [sessions_dir, core_memories_dir].each do |dir|
        next if File.directory?(dir)

        FileUtils.mkdir_p(dir)
        changes << "created #{relative(dir)}/"
      end
      unless config.exist?
        File.write(config.path, Config.template)
        changes << "wrote #{Config::FILENAME}"
      end
      changes << "gitignored #{SESSIONS_DIR}/" if Gitignore.new(root).ensure!("#{SESSIONS_DIR}/")
      changes
    end
  end
end
