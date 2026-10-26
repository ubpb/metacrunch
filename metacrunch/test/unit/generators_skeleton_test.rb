# frozen_string_literal: true

require "test_helper"
require "prism"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsSkeletonTest < Minitest::Test

  Skeleton = Metacrunch::Generators::Skeleton
  ROOT = File.expand_path("../..", __dir__)

  def test_lists_the_files_of_a_project
    paths = Skeleton.plan("/work/catalog").entries.map { it.path.delete_prefix("/work/catalog/") }

    assert_equal ["Metacrunchfile", "Gemfile", "Rakefile", "jobs/.keep", "transforms/.keep", "commands/.keep",
                  "lib/.keep", "test/test_helper.rb", "test/project_test.rb"], paths
  end

  def test_every_file_is_ruby_without_warnings
    entries = Skeleton.plan("/work/catalog").entries.reject { it.path.end_with?(".keep") }
    problems = entries.flat_map do |entry|
      result = Prism.parse(entry.content)
      (result.errors + result.warnings).map { "#{entry.path}: #{it.message}" }
    end

    assert_empty problems
  end

  def test_a_release_asks_for_its_minor_version
    assert_equal %(gem "metacrunch", "~> 5.1"), Skeleton.gem_line("5.1.2")
  end

  def test_a_prerelease_comes_from_git
    assert_equal %(gem "metacrunch", github: "ubpb/metacrunch"), Skeleton.gem_line("5.0.0.pre")
    assert_includes Skeleton.plan("/x", version: "5.2.0").entries[1].content, %(\ngem "metacrunch", "~> 5.2"\n)
  end

  def test_the_project_loads_empty
    Dir.mktmpdir do |dir|
      Skeleton.plan(dir).write(force: false, out: StringIO.new, cwd: dir)
      project = Metacrunch.load_project(dir)

      assert_equal [[], []], [project.names, project.load_errors]
    end
  end

  def test_the_gem_ships_the_templates
    spec = Dir.chdir(ROOT) { Gem::Specification.load("metacrunch.gemspec") }
    templates = Dir.glob("lib/metacrunch/templates/**/*.erb", base: ROOT)

    assert_operator templates.size, :>=, 20
    assert_empty templates - spec.files
  end

end
