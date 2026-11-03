# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch-ai.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_of_metacrunch
    assert_equal Metacrunch::Ai::VERSION, SPEC.version.to_s
    assert_equal Metacrunch::VERSION, Metacrunch::Ai::VERSION
  end

  def test_requires_metacrunch_in_exactly_its_own_version
    metacrunch = SPEC.runtime_dependencies.find { it.name == "metacrunch" }

    assert_equal Gem::Requirement.new("= #{SPEC.version}"), metacrunch.requirement
  end

  def test_depends_on_nokogiri_besides
    nokogiri = SPEC.runtime_dependencies.find { it.name == "nokogiri" }

    assert_equal ["metacrunch", "nokogiri"], SPEC.runtime_dependencies.map(&:name).sort
    assert_equal Gem::Requirement.new("~> 1.19"), nokogiri.requirement
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch-ai", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch-ai/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
