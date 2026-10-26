# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsPlanTest < Minitest::Test

  Plan = Metacrunch::Generators::Plan

  def test_writes_files_with_directories_and_reports_them
    in_tmpdir do |dir|
      out = StringIO.new
      plan(dir).write(force: false, out:, cwd: File.join(dir, "jobs").tap { FileUtils.mkdir_p(it) })

      assert_equal "created a/x.rb\ncreated ../test/x_test.rb\n", out.string
      assert_equal ["x = 1\n", "test\n"], [read(dir, "jobs/a/x.rb"), read(dir, "test/x_test.rb")]
    end
  end

  def test_executable_files_get_mode_rwxr_xr_x
    in_tmpdir do |dir|
      plan(dir).write(force: false, out: StringIO.new, cwd: dir)

      assert_equal [0o755, false], [File.stat(File.join(dir, "jobs/a/x.rb")).mode & 0o777,
                                    File.executable?(File.join(dir, "test/x_test.rb"))]
    end
  end

  def test_refuses_existing_files_and_writes_none
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      File.write(File.join(dir, "test/x_test.rb"), "mine")
      error = assert_raises(Metacrunch::UsageError) { plan(dir).write(force: false, out: StringIO.new, cwd: dir) }

      assert_equal "test/x_test.rb already exists; use --force to overwrite", error.message
      refute_path_exists File.join(dir, "jobs/a/x.rb")
    end
  end

  def test_names_every_existing_file
    in_tmpdir do |dir|
      plan(dir).write(force: false, out: StringIO.new, cwd: dir)
      error = assert_raises(Metacrunch::UsageError) { plan(dir).write(force: false, out: StringIO.new, cwd: dir) }

      assert_equal "jobs/a/x.rb, test/x_test.rb already exist; use --force to overwrite", error.message
    end
  end

  def test_force_overwrites
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      File.write(File.join(dir, "test/x_test.rb"), "mine")
      plan(dir).write(force: true, out: StringIO.new, cwd: dir)

      assert_equal "test\n", read(dir, "test/x_test.rb")
    end
  end

  private

  def plan(dir)
    Plan.new.add(File.join(dir, "jobs/a/x.rb"), "x = 1\n", executable: true)
        .add(File.join(dir, "test/x_test.rb"), "test\n")
  end

  def read(dir, path) = File.read(File.join(dir, path))

  def in_tmpdir
    Dir.mktmpdir { |dir| yield File.realpath(dir) }
  end

end
