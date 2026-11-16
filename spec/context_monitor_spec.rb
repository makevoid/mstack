# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::ContextMonitor do
  subject(:monitor) { described_class.new(project.config) }

  let(:state) { Mstack::SessionState.new("s1") }

  it "places checkpoints at 50/70/88% of the compaction point (267k under a 300k cap)" do
    expect(monitor.status(133_000).level).to eq(-1)
    expect(monitor.status(134_000).level).to eq(0)
    expect(monitor.status(187_000).level).to eq(1)
    expect(monitor.status(234_000).level).to eq(1)
    expect(monitor.status(235_000)).to have_attributes(level: 2, final: true, pct: 88, headroom: 32_000)
  end

  it "announces each checkpoint once as context grows" do
    expect(monitor.check!(100_000, state)).to be_nil
    expect(monitor.check!(151_000, state)).to have_attributes(level: 0, final: false)
    expect(monitor.check!(160_000, state)).to be_nil
    expect(monitor.check!(215_000, state)).to have_attributes(level: 1)
    expect(monitor.check!(260_000, state)).to have_attributes(level: 2, final: true)
    expect(monitor.check!(280_000, state)).to be_nil
  end

  it "jumps straight to the highest crossed checkpoint" do
    expect(monitor.check!(270_000, state)).to have_attributes(level: 2, final: true)
  end

  it "does nothing when the context size is unknown" do
    expect(monitor.check!(nil, state)).to be_nil
    expect(state.checkpoint_level).to eq(-1)
  end

  it "re-arms after a compaction, taking the first reading as the baseline" do
    monitor.check!(260_000, state)
    state.compacted!

    expect(monitor.check!(160_000, state)).to be_nil # new baseline, already past 50%
    expect(monitor.check!(170_000, state)).to be_nil
    expect(monitor.check!(215_000, state)).to have_attributes(level: 1)
  end

  it "re-arms when the context shrinks without a compaction event (/clear)" do
    monitor.check!(215_000, state)

    expect(monitor.check!(20_000, state)).to be_nil
    expect(monitor.check!(152_000, state)).to have_attributes(level: 0)
  end

  it "respects a custom cap and checkpoints" do
    write(".mstackrc", "context:\n  cap_tokens: 100000\n  checkpoints: [60, 90]\n")

    # compaction point 67k: checkpoints at 40.2k and 60.3k
    expect(monitor.status(40_000).level).to eq(-1)
    expect(monitor.status(40_200).level).to eq(0)
    expect(monitor.status(61_000)).to have_attributes(level: 1, final: true, headroom: 6_000)
  end
end
