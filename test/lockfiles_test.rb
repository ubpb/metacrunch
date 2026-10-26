# frozen_string_literal: true

require "minitest/autorun"
require_relative "../rakelib/monorepo"

# CI installs every bundle frozen: on x86_64 Linux, and on Ruby head, where precompiled native gems may not fit and
# Bundler needs the ruby platform to compile them.
class LockfilesTest < Minitest::Test

  ROOT = File.expand_path("..", __dir__)

  def test_every_lockfile_lists_the_ruby_platform_and_an_x86_64_linux_one
    ["."].concat(Monorepo.gems(ROOT)).each do |dir|
      platforms = platforms_of(File.join(ROOT, dir, "Gemfile.lock"))

      assert_includes platforms, "ruby", "#{dir}/Gemfile.lock"
      assert(platforms.any? { it.start_with?("x86_64-linux") }, "#{dir}/Gemfile.lock lists no x86_64 Linux platform")
    end
  end

  private

  def platforms_of(lockfile)
    File.read(lockfile)[/^PLATFORMS\n(.*?)\n\n/m, 1].split
  end

end
