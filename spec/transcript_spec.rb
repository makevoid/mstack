# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::Transcript do
  it "reads context size and model from the last main-thread assistant record" do
    path = transcript(user("hi"), assistant(50_000), user("more"), assistant(120_000, model: "claude-opus-5-5"))
    reading = described_class.new(path).reading

    expect(reading.tokens).to eq(120_000)
    expect(reading.model_id).to eq("claude-opus-5-5")
  end

  it "ignores subagent (sidechain) records" do
    side = assistant(999_000).merge("isSidechain" => true)
    path = transcript(assistant(80_000), side)

    expect(described_class.new(path).context_tokens).to eq(80_000)
  end

  it "reports unknown right after a compaction" do
    path = transcript(assistant(290_000), compact_boundary, user("This session is being continued"))

    expect(described_class.new(path).context_tokens).to be_nil
  end

  it "reads the new window once the model has responded after a compaction" do
    path = transcript(assistant(290_000), compact_boundary, assistant(40_000))

    expect(described_class.new(path).context_tokens).to eq(40_000)
  end

  it "finds the reading behind a tool result larger than the first tail window" do
    huge = { "type" => "user", "isSidechain" => false,
             "message" => { "content" => [{ "type" => "tool_result", "content" => "x" * 400_000 }] } }
    path = transcript(assistant(70_000), huge)

    expect(described_class.new(path).context_tokens).to eq(70_000)
  end

  it "is empty for a missing or absent transcript" do
    expect(described_class.new(nil).context_tokens).to be_nil
    expect(described_class.new("/nonexistent.jsonl").context_tokens).to be_nil
  end

  describe "#digest" do
    it "collects the user's prompts, edited files and the compaction count" do
      path = transcript(
        user("build the todo app"),
        assistant(10_000, content: [edit("/p/app.rb"), edit("/p/app.rb"), edit("/p/views/index.haml")]),
        compact_boundary,
        user("This session is being continued from a previous conversation"),
        user("<system-reminder>noise</system-reminder>"),
        { "type" => "user", "isSidechain" => false,
          "message" => { "content" => [{ "type" => "tool_result", "content" => "ok" }] } },
        user("now add tags")
      )
      digest = described_class.new(path).digest

      expect(digest.prompts).to eq(["build the todo app", "now add tags"])
      expect(digest.files).to eq(["/p/app.rb", "/p/views/index.haml"])
      expect(digest.compactions).to eq(1)
    end
  end
end
