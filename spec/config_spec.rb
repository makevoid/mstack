# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::Config do
  subject(:config) { described_class.load(root) }

  it "uses the recommended defaults when there is no .mstackrc" do
    expect(config.cap_tokens).to eq(300_000)
    expect(config.default_model).to eq("claude-fable-5-2")
    expect(config.fallback_model).to eq("claude-opus-5-5")
    expect(config.effort).to eq("high")
    expect(config.dig(:limits, :weekly_switch_pct)).to eq(70)
    expect(config.dig(:limits, :session_pause_pct)).to eq(90)
    expect(config.core_memories?).to be(true)
    expect(config.subagents?).to be(false)
  end

  it "overlays .mstackrc on the defaults, keeping untouched nested keys" do
    write(".mstackrc", "core_memories: false\ncontext:\n  cap_tokens: 100000\nlimits:\n  weekly_switch_pct: 60\n")

    expect(config.core_memories?).to be(false)
    expect(config.cap_tokens).to eq(100_000)
    expect(config.checkpoints).to eq([50, 70, 88])
    expect(config.dig(:limits, :weekly_switch_pct)).to eq(60)
    expect(config.dig(:limits, :session_pause_pct)).to eq(90)
  end

  it "falls back to defaults and warns on invalid YAML" do
    write(".mstackrc", "context: [unclosed\n")

    expect(config.cap_tokens).to eq(300_000)
    expect(config.warnings.join).to include("not valid YAML")
  end

  it "falls back to defaults and warns when the file is not a hash" do
    write(".mstackrc", "- just\n- a list\n")

    expect(config.cap_tokens).to eq(300_000)
    expect(config.warnings.join).to include("must be a YAML hash")
  end

  it "puts the compaction point a reserve below the cap" do
    expect(config.compaction_point).to eq(267_000)

    write(".mstackrc", "context:\n  cap_tokens: 100000\n  compact_reserve_tokens: 20000\n")
    expect(described_class.load(root).compaction_point).to eq(80_000)
  end

  it "accepts reasoning effort inside the sweet spot only" do
    expect(%w[low medium high xhigh max].map { |level| config.effort_ok?(level) }).to eq([false, false, true, true, false])
    expect(config.effort_ok?(nil)).to be(false)
  end

  it "ships a template that parses back to the defaults" do
    write(".mstackrc", described_class.template)

    expect(config.warnings).to be_empty
    expect(config.to_h).to eq(described_class.new(File.join(root, "missing")).to_h)
  end
end
