# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../rakelib/monorepo"

class MonorepoTest < Minitest::Test

  VERSION_FILE = <<~RUBY
    # frozen_string_literal: true

    module Metacrunch
      module Fake

        VERSION = "5.0.0.pre"

      end
    end
  RUBY

  def setup
    @root = Dir.mktmpdir
    @locked = []
    @lock = ->(dir) { @locked << dir }
    ["metacrunch-xlsx", "metacrunch", "metacrunch-csv"].each { add_gem(it) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_gems_are_the_directories_with_a_gemspec_of_their_name_core_first
    FileUtils.mkdir_p(File.join(@root, "docs"))
    write("other/something.gemspec", "")
    write("Rakefile", "")

    assert_equal ["metacrunch", "metacrunch-csv", "metacrunch-xlsx"], Monorepo.gems(@root)
  end

  def test_the_version_file_follows_the_gem_name
    assert_equal File.join(@root, "metacrunch/lib/metacrunch/version.rb"), Monorepo.version_file(@root, "metacrunch")
    assert_equal File.join(@root, "metacrunch-csv/lib/metacrunch/csv/version.rb"),
                 Monorepo.version_file(@root, "metacrunch-csv")
  end

  def test_set_version_writes_every_version_file
    Monorepo.set_version("5.1.0", root: @root, lock: @lock)

    assert_equal ["5.1.0"], Monorepo.gems(@root).map { version_of(it) }.uniq
  end

  def test_set_version_keeps_the_rest_of_the_file
    Monorepo.set_version("5.1.0.rc1", root: @root, lock: @lock)

    assert_equal VERSION_FILE.sub("5.0.0.pre", "5.1.0.rc1"), read("metacrunch-csv/lib/metacrunch/csv/version.rb")
  end

  def test_set_version_locks_every_gem_in_order_after_writing
    # The first and the last gem: every file is written before the first lock.
    lock = ->(dir) { @locked << [File.basename(dir), version_of("metacrunch"), version_of("metacrunch-xlsx")] }
    Monorepo.set_version("5.1.0", root: @root, lock:)

    assert_equal [["metacrunch", "5.1.0", "5.1.0"], ["metacrunch-csv", "5.1.0", "5.1.0"],
                  ["metacrunch-xlsx", "5.1.0", "5.1.0"]], @locked
  end

  def test_set_version_also_locks_the_further_gemfiles_of_a_gem
    write("metacrunch-csv/gemfiles/csv-3.gemfile", "")
    write("metacrunch-csv/gemfiles/csv-3.gemfile.lock", "")
    Monorepo.set_version("5.1.0", root: @root, lock: @lock)
    locked = @locked.map { it.delete_prefix("#{@root}/") }

    assert_equal ["metacrunch", "metacrunch-csv", "metacrunch-csv/gemfiles/csv-3.gemfile", "metacrunch-xlsx"], locked
  end

  def test_a_version_that_is_not_canonical_is_refused_and_nothing_is_written
    [nil, "", " ", "5.1.0 ", "5.1.0-pre", "v5.1.0", "five", "5..1"].each do |version|
      error = assert_raises(ArgumentError) { Monorepo.set_version(version, root: @root, lock: @lock) }

      assert_equal "not a version: #{version.inspect}", error.message
    end
    assert_unchanged
  end

  def test_a_version_file_without_exactly_one_version_line_is_refused_and_nothing_is_written
    write("metacrunch-xlsx/lib/metacrunch/xlsx/version.rb", %(VERSION = "5.0.0.pre"\nVERSION = "5.0.0.pre"\n))

    error = assert_raises(Monorepo::Error) { Monorepo.set_version("5.1.0", root: @root, lock: @lock) }

    assert_equal "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb: expected one VERSION line, found 2", error.message
    assert_unchanged
  end

  def test_a_missing_version_file_is_refused_and_nothing_is_written
    FileUtils.rm(File.join(@root, "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb"))

    error = assert_raises(Monorepo::Error) { Monorepo.set_version("5.1.0", root: @root, lock: @lock) }

    assert_equal "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb: no such file", error.message
    assert_unchanged
  end

  def test_a_failing_bundle_lock_names_the_gem
    write("metacrunch-csv/Gemfile", "raise \"broken\"\n")

    error = assert_raises(Monorepo::Error) do
      capture_subprocess_io { Monorepo.bundle_lock(File.join(@root, "metacrunch-csv")) }
    end

    assert_equal "bundle lock failed in metacrunch-csv", error.message
  end

  def test_a_failing_bundle_lock_of_a_further_gemfile_names_it
    write("metacrunch-csv/gemfiles/csv-3.gemfile", "raise \"broken\"\n")

    error = assert_raises(Monorepo::Error) do
      capture_subprocess_io { Monorepo.bundle_lock(File.join(@root, "metacrunch-csv/gemfiles/csv-3.gemfile")) }
    end

    assert_equal "bundle lock failed for csv-3.gemfile", error.message
  end

  private

  def add_gem(name)
    write("#{name}/#{name}.gemspec", "")
    write(Monorepo.version_file(".", name), VERSION_FILE)
  end

  def version_of(gem)
    read(Monorepo.version_file(".", gem))[/VERSION = "(.*)"/, 1]
  end

  # Core comes first, so its file would be written first; the failing gem is the last one.
  def assert_unchanged
    assert_equal "5.0.0.pre", version_of("metacrunch")
    assert_empty @locked
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), text)
  end

  def read(path)
    File.read(File.join(@root, path))
  end

end
