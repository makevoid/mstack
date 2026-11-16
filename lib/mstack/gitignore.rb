# frozen_string_literal: true

module Mstack
  # Keeps an entry present in the project's .gitignore. Session memory is
  # local working state and must never be committed.
  class Gitignore
    def initialize(root)
      @path = File.join(root, ".gitignore")
    end

    def include?(entry)
      return false unless File.file?(@path)

      wanted = normalize(entry)
      File.readlines(@path, chomp: true).any? { |line| normalize(line) == wanted }
    end

    # Returns true when the file was changed.
    def ensure!(entry)
      return false if include?(entry)

      existing = File.file?(@path) ? File.read(@path) : ""
      separator = existing.empty? || existing.end_with?("\n") ? "" : "\n"
      File.write(@path, "#{existing}#{separator}#{entry}\n")
      true
    end

    private

    def normalize(line)
      line.strip.delete_prefix("/").delete_prefix("./").delete_suffix("/")
    end
  end
end
