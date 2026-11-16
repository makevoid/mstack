# frozen_string_literal: true

module Mstack
  # Read-only view of the Claude Code settings that mstack depends on,
  # resolved across the local, project and user settings files (highest
  # precedence first). mstack never edits these files itself.
  class ClaudeSettings
    def initialize(project_root, user_dir: Mstack.claude_dir, env: ENV)
      @files = [
        File.join(project_root, ".claude", "settings.local.json"),
        File.join(project_root, ".claude", "settings.json"),
        File.join(user_dir, "settings.json")
      ]
      @env = env
    end

    def value(key)
      layers.each { |layer| return layer[key] if layer.key?(key) }
      nil
    end

    def model
      @env["ANTHROPIC_MODEL"] || value("model")
    end

    def effort(model_id = nil)
      @env["CLAUDE_CODE_EFFORT_LEVEL"] || model_setting(model_id, "effortLevel") || value("effortLevel")
    end

    # Tokens, or nil when unset. The per-model form wins over the top-level key.
    def auto_compact_window(model_id = nil)
      raw = @env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] || model_setting(model_id, "autoCompactWindow") ||
            value("autoCompactWindow")
      parse_tokens(raw)
    end

    def auto_compact_enabled?
      return false if @env["DISABLE_AUTO_COMPACT"] == "1"

      value("autoCompactEnabled") != false
    end

    def statusline_command
      value("statusLine")&.fetch("command", nil)
    end

    private

    def layers
      @layers ||= @files.filter_map do |file|
        JSON.parse(File.read(file))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end
    end

    def model_setting(model_id, key)
      return nil if model_id.to_s.empty?

      layers.each do |layer|
        (layer["modelSettings"] || {}).each do |id, settings|
          next unless model_id.include?(id) || id.include?(model_id)
          return settings[key] if settings.is_a?(Hash) && settings.key?(key)
        end
      end
      nil
    end

    def parse_tokens(raw)
      case raw
      when Integer then raw
      when /\A(\d+)k\z/i then Regexp.last_match(1).to_i * 1000
      when /\A\d+\z/ then raw.to_i
      end
    end
  end
end
