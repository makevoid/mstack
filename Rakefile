# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Validate the plugin manifest and hooks"
task :validate do
  sh "claude plugin validate ."
end

namespace :benchmark do
  desc "Run the Roda todo-app benchmark against a small context cap (spends plan usage)"
  task :run do
    ruby "benchmark/run.rb"
  end

  desc "Verify the most recent benchmark run"
  task :verify do
    ruby "benchmark/verify.rb"
  end
end

task default: :spec
