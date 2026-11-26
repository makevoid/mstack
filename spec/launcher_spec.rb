# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::Launcher do
  subject(:launcher) { described_class.new(root: "/plugins/mstack/0.1.0") }

  it "installs an executable script that runs the plugin's status line" do
    expect(launcher.install!).to be(true)
    expect(File.executable?(launcher.path)).to be(true)
    expect(File.read(launcher.path)).to include(%(exec /plugins/mstack/0.1.0/bin/mstack statusline "$@"))
  end

  it "is idempotent, and follows the plugin when it moves" do
    launcher.install!

    expect(launcher.install!).to be(false)
    expect(described_class.new(root: "/plugins/mstack/0.2.0").install!).to be(true)
    expect(File.read(launcher.path)).to include("0.2.0")
  end

  it "really runs: the installed script renders a status line" do
    described_class.new.install!
    payload = JSON.generate("session_id" => "s1", "cwd" => root, "model" => { "id" => "claude-fable-5-2", "display_name" => "Fable 5.2" })
    out, status = Open3.capture2(described_class.new.path, stdin_data: payload)

    expect(status).to be_success
    expect(out).to start_with("Fable 5.2 | [..........] 0/300k")
  end

  it "treats shell metacharacters in the plugin path literally and preserves arguments" do
    plugin_root = File.join(@sandbox, %q{plugin $HOME $(touch injected) `touch injected-backtick` "quoted" 'single'})
    FileUtils.mkdir_p(File.join(plugin_root, "bin"))
    executable = File.join(plugin_root, "bin", "mstack")
    File.write(executable, "#!/bin/sh\nprintf '<%s>\\n' \"$@\"\n")
    File.chmod(0o755, executable)
    launcher = described_class.new(root: plugin_root)
    launcher.install!

    out, err, status = Open3.capture3(launcher.path, "--wrap", "command with spaces", chdir: @sandbox)

    expect(status).to be_success, err
    expect(out).to eq("<statusline>\n<--wrap>\n<command with spaces>\n")
    expect(File.exist?(File.join(@sandbox, "injected"))).to be(false)
    expect(File.exist?(File.join(@sandbox, "injected-backtick"))).to be(false)
  end
end

RSpec.describe "mstack session" do
  def mstack(*argv)
    out = StringIO.new
    err = StringIO.new
    code = Dir.chdir(root) { Mstack::CLI.new(argv, stdin: StringIO.new, stdout: out, stderr: err).run }
    [code, out.string.strip, err.string]
  end

  it "prints and creates the session's memory file, with a stable name" do
    project.init!
    code, path, = mstack("session", "abcdef12-3456")

    expect(code).to eq(0)
    expect(path).to match(%r{\Adocs/mstack/sessions/\d{8}-\d{6}-abcdef12\.md\z})
    expect(File.file?(File.join(root, path))).to be(true)
    expect(mstack("session", "abcdef12-3456")[1]).to eq(path)
  end

  it "agrees with the path announced at session start" do
    project.init!
    briefing = Mstack::Hooks.run("session-start", { "session_id" => "abcdef12-3456", "cwd" => root, "hook_event_name" => "SessionStart", "source" => "startup" })
    announced = briefing.dig("hookSpecificOutput", "additionalContext")[%r{docs/mstack/sessions/\S+\.md}]

    expect(mstack("session", "abcdef12-3456")[1]).to eq(announced)
  end

  it "refuses outside an initialized project or without a session id" do
    expect(mstack("session", "abc")[0]).to eq(1)
    project.init!
    saved = ENV.delete("CLAUDE_CODE_SESSION_ID")
    expect(mstack("session")[0]).to eq(1)
  ensure
    ENV["CLAUDE_CODE_SESSION_ID"] = saved if saved
  end
end
