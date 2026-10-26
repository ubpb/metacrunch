# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_constant
    assert_equal Metacrunch::VERSION, SPEC.version.to_s
  end

  def test_depends_on_no_other_metacrunch_gem
    assert_empty(SPEC.runtime_dependencies.select { it.name.start_with?("metacrunch") })
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
