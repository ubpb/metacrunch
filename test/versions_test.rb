# frozen_string_literal: true

require "minitest/autorun"
require_relative "../rakelib/monorepo"

# The root's VERSION holds the shared version, and rake version writes it into the version.rb of every gem. After a
# change of VERSION without rake version, this test fails.
class VersionsTest < Minitest::Test

  ROOT = File.expand_path("..", __dir__)

  def test_every_gem_has_the_version_of_the_root_version_file
    version = Monorepo.version(ROOT)

    Monorepo.gems(ROOT).each do |gem|
      assert_equal version, Monorepo.gem_version(ROOT, gem), "#{gem} differs from VERSION, run rake version"
    end
  end

end
