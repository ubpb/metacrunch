# frozen_string_literal: true

require "test_helper"

class RootCliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper
  include RootFixtures

  def test_a_job_runs_by_name_from_a_subdirectory
    in_tmpdir do |dir|
      write_root_project(dir)
      code, out, = Dir.chdir(File.join(dir, "jobs")) { cli("rooted") }

      assert_equal [0, "\"a@#{File.basename(dir)}\"\n"], [code, out]
    end
  end

  def test_help_shows_the_absolute_default
    in_tmpdir do |dir|
      write_root_project(dir)
      code, out, = Dir.chdir(dir) { cli("rooted", "--help") }

      assert_equal 0, code
      assert_includes out, "default: #{dir}/data/in.txt"
    end
  end

  def test_help_by_path_does_not_load_the_metacrunchfile
    in_tmpdir do |dir|
      write_root_project(dir)
      write_file(dir, "Metacrunchfile", "raise \"must not load\"\n")
      code, out, = Dir.chdir(dir) { cli("run", "jobs/rooted.rb", "--help") }

      assert_equal 0, code
      assert_includes out, "default: #{dir}/data/in.txt"
    end
  end

  def test_root_outside_a_project_is_a_usage_error
    in_tmpdir do |dir|
      path = write_file(dir, "rooted.rb", ROOTED)
      code, _out, err = Dir.chdir(dir) { cli("run", path) }

      assert_equal 2, code
      assert_includes err, "no Metacrunchfile found in #{dir} or above"
    end
  end

  def test_root_in_a_hook_outside_a_project_is_a_usage_error
    in_tmpdir do |dir|
      job = "# frozen_string_literal: true\n\nMetacrunch.job { source [1]; before { root } }\n"
      path = write_file(dir, "hooked.rb", job)
      code, _out, err = Dir.chdir(dir) { cli("run", path) }

      assert_equal 2, code
      assert_includes err, "no Metacrunchfile found in #{dir} or above"
    end
  end

  # By path from the temporary directory's parent, which has no
  # Metacrunchfile above it.
  def test_command_help_with_a_root_default
    in_tmpdir do |dir|
      write_root_project(dir)
      by_name = Dir.chdir(dir) { cli("where", "--help") }
      by_path = Dir.chdir(File.dirname(dir)) { cli("run", File.join(dir, "commands/where.rb"), "--help") }

      assert_equal [0, 2], [by_name[0], by_path[0]]
      assert_includes by_name[1], "default: #{dir}/out"
      assert_includes by_path[2], "no Metacrunchfile found"
    end
  end

  def test_a_recipe_outside_the_project_gets_the_project_root
    in_tmpdir do |dir|
      in_tmpdir do |gem_dir|
        write_file(gem_dir, "gemjob.rb", "# frozen_string_literal: true\n\n" \
                                         "Metacrunch.job(\"gemjob\") { source [root.to_s] }\n")
        write_file(dir, "Metacrunchfile", "Metacrunch.load_files #{File.join(gem_dir, "*.rb").inspect}\n")
        code, out, = Dir.chdir(dir) { cli("gemjob") }

        assert_equal [0, "#{dir.inspect}\n"], [code, out]
      end
    end
  end

end
