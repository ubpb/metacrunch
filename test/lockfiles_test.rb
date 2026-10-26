# frozen_string_literal: true

require "minitest/autorun"
require_relative "../rakelib/monorepo"

# CI installs every bundle frozen: on x86_64 Linux, and on Ruby head, where precompiled native gems may not fit and
# Bundler needs the ruby platform to compile them.
class LockfilesTest < Minitest::Test

  ROOT = File.expand_path("..", __dir__)

  def test_every_lockfile_lists_the_ruby_platform_and_an_x86_64_linux_one
    lockfiles.each do |lockfile|
      platforms = platforms_of(File.join(ROOT, lockfile))

      assert_includes platforms, "ruby", lockfile
      assert(platforms.any? { it.start_with?("x86_64-linux") }, "#{lockfile} lists no x86_64 Linux platform")
    end
  end

  private

  # The lockfiles of the root, of every gem and of the gems' further Gemfiles.
  def lockfiles
    gems = Monorepo.gems(ROOT)
    further = gems.flat_map { Monorepo.gemfiles(ROOT, it) }.map { "#{it.delete_prefix("#{ROOT}/")}.lock" }
    ["."].concat(gems).map { File.join(it, "Gemfile.lock") }.concat(further)
  end

  def platforms_of(lockfile)
    File.read(lockfile)[/^PLATFORMS\n(.*?)\n\n/m, 1].split
  end

end
