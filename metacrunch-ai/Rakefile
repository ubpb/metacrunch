# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

# Coverage thresholds apply to full runs only (see test/test_helper.rb).
ENV["COVERAGE"] = "1" unless ENV.key?("COVERAGE")

Minitest::TestTask.create do |t|
  t.test_globs = ["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
