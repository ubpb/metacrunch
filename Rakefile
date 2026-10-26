# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"
require_relative "rakelib/monorepo"

# Runs a command in the directory of every gem, with the gem's own bundle. The first failure stops.
def in_each_gem(*command)
  Monorepo.gems.each do |gem|
    puts "== #{gem}"
    Bundler.with_unbundled_env { sh(*command, chdir: gem) }
  end
end

desc "Install the bundle of every gem"
task :bundle do
  in_each_gem("bundle", "install")
end

namespace :test do
  Minitest::TestTask.create(:tooling) do |t|
    t.test_globs = ["test/**/*_test.rb"]
  end
end

desc "Run the tooling test and the tests of every gem"
task test: "test:tooling" do
  in_each_gem("bundle", "exec", "rake", "test")
end

# The gems have configurations of their own, so RuboCop in the root names the tooling files.
namespace :rubocop do
  RuboCop::RakeTask.new(:root) do |t|
    t.patterns = ["Gemfile", "Rakefile", "rakelib", "test"]
  end
end

desc "Run RuboCop on the root files and in every gem"
task rubocop: "rubocop:root" do
  in_each_gem("bundle", "exec", "rubocop")
end

desc 'Set the version of all gems, e.g. rake "version[5.1.0]"'
task :version, [:version] do |_task, args|
  Monorepo.set_version(args[:version])
end

task default: [:test, :rubocop]
