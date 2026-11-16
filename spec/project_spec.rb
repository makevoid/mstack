# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::Project do
  describe "#init!" do
    it "creates the memory directories, the config and the gitignore entry" do
      changes = project.init!

      expect(File.directory?(File.join(root, "docs/mstack/sessions"))).to be(true)
      expect(File.directory?(File.join(root, "docs/mstack/core_memories"))).to be(true)
      expect(File.file?(File.join(root, ".mstackrc"))).to be(true)
      expect(File.read(File.join(root, ".gitignore"))).to include("docs/mstack/sessions/")
      expect(changes.size).to eq(4)
    end

    it "is idempotent" do
      project.init!

      expect(project.init!).to be_empty
      expect(File.read(File.join(root, ".gitignore")).scan("docs/mstack/sessions/").size).to eq(1)
    end

    it "keeps an existing .mstackrc" do
      write(".mstackrc", "core_memories: false\n")
      project.init!

      expect(File.read(File.join(root, ".mstackrc"))).to eq("core_memories: false\n")
    end
  end

  it "is initialized only after init" do
    expect(project.initialized?).to be(false)
    project.init!
    expect(project.initialized?).to be(true)
  end
end

RSpec.describe Mstack::Gitignore do
  subject(:gitignore) { described_class.new(root) }

  it "appends to an existing file without eating the last line" do
    write(".gitignore", "node_modules")
    gitignore.ensure!("docs/mstack/sessions/")

    expect(File.read(File.join(root, ".gitignore"))).to eq("node_modules\ndocs/mstack/sessions/\n")
  end

  it "recognizes equivalent spellings of the entry" do
    write(".gitignore", "/docs/mstack/sessions\n")

    expect(gitignore.ensure!("docs/mstack/sessions/")).to be(false)
  end
end
