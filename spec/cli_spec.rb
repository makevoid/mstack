# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mstack::CLI do
  def mstack(*argv, stdin: "")
    out = StringIO.new
    err = StringIO.new
    code = Dir.chdir(root) { described_class.new(argv, stdin: StringIO.new(stdin), stdout: out, stderr: err).run }
    [code, out.string, err.string]
  end

  it "initializes a project and reports what it did" do
    code, out, = mstack("init")

    expect(code).to eq(0)
    expect(out).to include("wrote .mstackrc", "gitignored docs/mstack/sessions/", "[ok]   project: initialized")
    expect(mstack("init")[1]).to include("already initialized")
  end

  it "doctor fails until the requirements are met, then passes" do
    mstack("init")
    code, out, = mstack("doctor")
    expect(code).to eq(1)
    expect(out).to include("[FIX]  context cap: autoCompactWindow is not set", %("autoCompactWindow": 300000))

    user_settings("autoCompactWindow" => 300_000, "model" => "claude-fable-5-2", "effortLevel" => "high",
                  "statusLine" => { "type" => "command", "command" => "/plugins/mstack/bin/mstack statusline" })
    code, out, = mstack("doctor")
    expect(out).not_to include("[FIX]")
    expect(code).to eq(0)
  end

  it "doctor reads the per-model autoCompactWindow and flags a mismatch with the cap" do
    mstack("init")
    user_settings("autoCompactWindow" => 300_000, "modelSettings" => { "claude-fable-5-2" => { "autoCompactWindow" => 500_000 } })

    expect(mstack("doctor")[1]).to include("autoCompactWindow is 500000, .mstackrc cap_tokens is 300000")
  end

  it "prints status for the project" do
    mstack("init")
    record_usage("s1", weekly: 42, session: 7)
    _, out, = mstack("status")

    expect(out).to include("weekly 42%", "session 7%", "context cap:    300000 tokens", "subagents:      denied")
  end

  describe "hook" do
    it "prints the handler's JSON" do
      _, out, = mstack("hook", "pre-tool-use", stdin: JSON.generate("cwd" => root, "tool_name" => "Agent", "tool_input" => {}))

      expect(JSON.parse(out).dig("hookSpecificOutput", "permissionDecision")).to eq("deny")
    end

    it "prints nothing when there is nothing to say" do
      code, out, = mstack("hook", "stop", stdin: JSON.generate("cwd" => root, "session_id" => "s1"))

      expect([code, out]).to eq([0, ""])
    end

    it "never fails the session: errors are logged and swallowed" do
      code, out, = mstack("hook", "no-such-hook", stdin: "{}")

      expect([code, out]).to eq([0, ""])
      expect(File.read(File.join(ENV["MSTACK_HOME"], "error.log"))).to include("hook=no-such-hook", "unknown hook")
    end

    it "survives garbage on stdin" do
      expect(mstack("hook", "stop", stdin: "not json")[0]).to eq(0)
    end
  end

  describe "statusline" do
    let(:payload) do
      {
        "session_id" => "s1", "cwd" => root,
        "model" => { "id" => "claude-fable-5-2", "display_name" => "Fable 5.2" },
        "effort" => { "level" => "high" },
        "context_window" => { "total_input_tokens" => 98_000 },
        "rate_limits" => { "five_hour" => { "used_percentage" => 12.4 }, "seven_day" => { "used_percentage" => 45 } }
      }
    end

    it "renders model, context against the cap, and both limits" do
      _, out, = mstack("statusline", stdin: JSON.generate(payload))

      expect(out.strip).to eq("Fable 5.2 high | [###.......] 98k/300k | CS 12% | WL 45%")
    end

    it "records usage for the hooks to read" do
      mstack("statusline", stdin: JSON.generate(payload))
      usage = Mstack::Usage::Store.new.load("s1")

      expect(usage).to have_attributes(model_id: "claude-fable-5-2", weekly_pct: 45, session_pct: 12.4, context_tokens: 98_000)
    end

    it "adds the model switch alert when the policy says to step down" do
      payload["rate_limits"]["seven_day"]["used_percentage"] = 71
      _, out, = mstack("statusline", stdin: JSON.generate(payload))

      expect(out).to include("WL 71% | mstack: /model claude-opus-5-5")
    end

    it "wraps an existing status line command, passing the payload through" do
      _, out, = mstack("statusline", "--wrap", %q(ruby -rjson -e 'print "mine:" + JSON.parse(STDIN.read)["model"]["id"]'), stdin: JSON.generate(payload))

      expect(out.strip).to eq("mine:claude-fable-5-2")
      expect(Mstack::Usage::Store.new.load("s1").weekly_pct).to eq(45)
    end

    it "does not let a payload without limits erase the account-wide snapshot" do
      mstack("statusline", stdin: JSON.generate(payload))
      mstack("statusline", stdin: JSON.generate("session_id" => "s2", "cwd" => root, "model" => { "id" => "claude-fable-5-2" }))

      expect(Mstack::Usage::Store.new.load("s2")).to have_attributes(weekly_pct: 45, model_id: "claude-fable-5-2")
    end
  end

  it "rejects unknown commands" do
    code, _, err = mstack("frobnicate")

    expect(code).to eq(1)
    expect(err).to include("unknown command")
  end
end
