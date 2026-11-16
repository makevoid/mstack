# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::SessionMemory do
  let(:now) { Time.new(2026, 11, 16, 4, 15, 0) }
  subject(:memory) { described_class.new(project, "a1b2c3d4-e5f6-4a7b", started_at: now) }

  it "names the file by timestamp and short session id" do
    expect(memory.relative_path).to eq("docs/mstack/sessions/20261116-041500-a1b2c3d4.md")
  end

  it "creates the file from a template and reports it pristine" do
    memory.ensure!

    expect(memory.read).to include("## Goal", "## State", "## Decisions", "## Facts and gotchas")
    expect(memory.pristine?).to be(true)
  end

  it "gets the same name every time it is asked for, before the file exists" do
    first = described_class.new(project, "abcdef12-0000").relative_path
    sleep 1.1
    expect(described_class.new(project, "abcdef12-0000").relative_path).to eq(first)
  end

  it "finds the same file again later in the session" do
    memory.ensure!
    later = described_class.new(project, "a1b2c3d4-e5f6-4a7b", started_at: now + 3600)

    expect(later.path).to eq(memory.path)
    expect(later.pristine?).to be(true)
  end

  it "is no longer pristine once the agent fills it in" do
    memory.ensure!
    File.write(memory.path, memory.read.sub(/^_\(what the user wants.*$/, "Build a todo app."))

    expect(memory.pristine?).to be(false)
  end

  it "trims the middle of an oversized file to the budget" do
    memory.ensure!
    File.write(memory.path, "HEAD #{'m' * 10_000} TAIL")
    rendered = memory.render(500)

    expect(rendered.length).to be <= 2_000
    expect(rendered).to start_with("HEAD").and end_with("TAIL")
    expect(rendered).to include("trimmed by mstack")
  end

  describe "#write_snapshot!" do
    let(:digest) { Mstack::Transcript::Digest.new(["build it"], ["#{root}/app.rb"], 0) }

    it "appends a mechanical snapshot without touching the agent's notes" do
      memory.ensure!
      File.write(memory.path, "# Session\n\n## Goal\nBuild a todo app.\n")
      memory.write_snapshot!(digest, tokens: 280_000, trigger: "auto")

      expect(memory.read).to start_with("# Session\n\n## Goal\nBuild a todo app.\n")
      expect(memory.read).to include("Auto-snapshot before compaction", "- build it", "- app.rb", "280k")
    end

    it "records the git working tree, which also catches files written through the shell" do
      system("git", "init", "-q", "-b", "main", chdir: root)
      write("app.rb", "one")
      memory.write_snapshot!(Mstack::Transcript::Digest.new([], [], 0), tokens: 60_000, trigger: "auto")

      expect(memory.read).to include("### Git working tree (branch main)", "- `?? app.rb`", "Recent commits:\n- (none recorded)")
    end

    it "leaves git out when the project is not a repository" do
      memory.write_snapshot!(digest, tokens: 280_000, trigger: "auto")

      expect(memory.read).not_to include("Git working tree")
    end

    it "replaces the previous snapshot instead of accumulating them" do
      memory.write_snapshot!(digest, tokens: 280_000, trigger: "auto")
      memory.write_snapshot!(Mstack::Transcript::Digest.new(["second"], [], 1), tokens: 290_000, trigger: "auto")

      expect(memory.read.scan("Auto-snapshot before compaction").size).to eq(1)
      expect(memory.read).to include("- second", "compaction #2")
      expect(memory.read).not_to include("- build it")
    end
  end

  it "lists other sessions' files newest first" do
    old = write("docs/mstack/sessions/20261101-000000-aaaaaaaa.md", "old")
    recent = write("docs/mstack/sessions/20261110-000000-bbbbbbbb.md", "recent")
    File.utime(now - 900, now - 900, old)
    File.utime(now - 100, now - 100, recent)
    memory.ensure!

    expect(described_class.recent(project, except: memory.path)).to eq([recent, old])
  end
end

RSpec.describe Mstack::CoreMemories do
  subject(:memories) { described_class.new(project) }

  it "is empty in a project with none" do
    expect(memories).to be_empty
    expect(memories.within_budget?).to be(true)
  end

  it "loads memories in filename order with their titles" do
    write("docs/mstack/core_memories/2026-11-02-b.md", "# Sequel needs the pk plugin\nUse it.")
    write("docs/mstack/core_memories/2026-11-01-a.md", "# Port is 9797\nNever 3000.")

    expect(memories.entries.map(&:title)).to eq(["Port is 9797", "Sequel needs the pk plugin"])
    expect(memories.full).to start_with("# Port is 9797")
    expect(memories.within_budget?).to be(true)
  end

  it "goes over budget when the memories outgrow it, and offers an index instead" do
    write(".mstackrc", "context:\n  core_memories_budget_tokens: 50\n")
    write("docs/mstack/core_memories/2026-11-01-a.md", "# Big one\n#{'word ' * 400}")

    expect(memories.within_budget?).to be(false)
    expect(memories.index).to eq("- docs/mstack/core_memories/2026-11-01-a.md: Big one")
    expect(memories.oversized.size).to eq(1)
  end
end
