# frozen_string_literal: true

module Mstack
  # Cheap token arithmetic. Exact counts need the API; for budgeting memory
  # files a 4-chars-per-token estimate is close enough and costs nothing.
  module Tokens
    CHARS_PER_TOKEN = 4

    module_function

    def estimate(text)
      (text.to_s.length / CHARS_PER_TOKEN.to_f).ceil
    end

    def chars(tokens)
      tokens * CHARS_PER_TOKEN
    end

    def human(tokens)
      return "?" if tokens.nil?

      tokens >= 1000 ? "#{(tokens / 1000.0).round}k" : tokens.to_s
    end
  end
end
