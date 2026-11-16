# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::ModelPolicy do
  subject(:policy) { described_class.new(project.config) }

  def decide(model, weekly, session)
    policy.decide(model_id: model, weekly_pct: weekly, session_pct: session)
  end

  it "keeps the default model while limits have room" do
    expect(decide("claude-fable-5-2", 69.9, 89.9)).to be_ok
  end

  it "steps down to the fallback when the weekly limit reaches 70%" do
    decision = decide("claude-fable-5-2", 70, 10)

    expect(decision).to have_attributes(kind: :step_down_weekly, pause: true)
    expect(decision.message).to include("/model claude-opus-5-5", "70%")
  end

  it "pauses when the current session limit reaches 90% on the default model" do
    decision = decide("claude-fable-5-2", 40, 90)

    expect(decision).to have_attributes(kind: :pause_session, pause: true)
    expect(decision.message).to include("/model claude-opus-5-5")
  end

  it "prefers the weekly step-down when both limits are hot" do
    expect(decide("claude-fable-5-2", 80, 95).kind).to eq(:step_down_weekly)
  end

  it "leaves the fallback model alone once the weekly limit is hot" do
    expect(decide("claude-opus-5-5", 85, 30)).to be_ok
    expect(decide("claude-opus-5-5", 85, 95)).to be_ok
  end

  it "suggests stepping back up when a lesser model is running with room to spare" do
    decision = decide("claude-opus-5-5", 12, 20)

    expect(decision).to have_attributes(kind: :step_up, pause: false)
    expect(decision.message).to include("/model claude-fable-5-2")
  end

  it "matches model ids with suffixes" do
    expect(decide("claude-fable-5-2[1m]", 75, 10).kind).to eq(:step_down_weekly)
  end

  it "stays quiet when the model or the limits are unknown" do
    expect(decide(nil, 99, 99)).to be_ok
    expect(decide("claude-fable-5-2", nil, nil)).to be_ok
    expect(decide("claude-opus-5-5", nil, nil)).to be_ok
  end

  it "uses the thresholds and models from .mstackrc" do
    write(".mstackrc", "model:\n  default: claude-opus-5-5\n  fallback: claude-sonnet-5-5\nlimits:\n  weekly_switch_pct: 50\n")

    decision = decide("claude-opus-5-5", 55, 10)
    expect(decision.kind).to eq(:step_down_weekly)
    expect(decision.message).to include("/model claude-sonnet-5-5")
  end
end
