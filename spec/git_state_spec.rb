# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::GitState do
  subject(:git) { described_class.new(root) }

  def sh(*args)
    system(*args, chdir: root, out: File::NULL, err: File::NULL)
  end

  it "is quiet outside a repository" do
    expect(git.repo?).to be(false)
    expect(git.branch).to be_nil
    expect(git.commits).to eq([])
    expect(git.changes).to eq([])
  end

  it "reports the branch, recent commits and uncommitted paths" do
    sh("git", "init", "-q", "-b", "main")
    write("app.rb", "one")
    sh("git", "add", "-A")
    sh("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "Phase 1: skeleton")
    write("app.rb", "two")
    write("models/todo.rb", "class Todo; end")

    expect(git.repo?).to be(true)
    expect(git.branch).to eq("main")
    expect(git.commits.first).to end_with("Phase 1: skeleton")
    expect(git.changes).to contain_exactly(" M app.rb", "?? models/")
  end

  it "survives a repository without commits" do
    sh("git", "init", "-q")
    write("app.rb", "one")

    expect(git.commits).to eq([])
    expect(git.changes).to eq(["?? app.rb"])
  end
end
