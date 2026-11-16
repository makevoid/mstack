# frozen_string_literal: true

module Mstack
  # A small JSON file treated as a hash. Writes are atomic (temp file +
  # rename) because the status line and several hooks may touch the same
  # file within milliseconds of each other.
  class JsonStore
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def read
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def write(hash)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.tmp"
      File.write(tmp, JSON.generate(hash))
      File.rename(tmp, path)
      hash
    end

    def update
      data = read
      yield data
      write(data)
    end
  end
end
