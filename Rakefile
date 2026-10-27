# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"
require_relative "rakelib/monorepo"

# Runs a command in the directory of every gem, with the gem's own bundle; with gemfiles: true also with each of its
# further Gemfiles (gemfiles/*.gemfile). The first failure stops.
def in_each_gem(*command, gemfiles: false)
  Monorepo.gems.each do |gem|
    puts "== #{gem}"
    Bundler.with_unbundled_env { sh(*command, chdir: gem) }
    next unless gemfiles

    Monorepo.gemfiles(Dir.pwd, gem).each do |gemfile|
      puts "== #{gem} with #{File.basename(gemfile)}"
      Bundler.with_unbundled_env { sh({"BUNDLE_GEMFILE" => gemfile}, *command, chdir: gem) }
    end
  end
end

desc "Install the bundle of every gem"
task :bundle do
  in_each_gem("bundle", "install", gemfiles: true)
end

namespace :test do
  Minitest::TestTask.create(:tooling) do |t|
    t.test_globs = ["test/**/*_test.rb"]
  end
end

desc "Run the tooling test and the tests of every gem"
task test: "test:tooling" do
  in_each_gem("bundle", "exec", "rake", "test", gemfiles: true)
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

desc "Write the version of VERSION into every gem and update their lockfiles"
task :version do
  Monorepo.set_version
end

task default: [:test, :rubocop]
