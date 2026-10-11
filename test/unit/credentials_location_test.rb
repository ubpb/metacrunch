# frozen_string_literal: true

require "test_helper"

class CredentialsLocationTest < Minitest::Test

  include CredentialsHelper

  Location = Metacrunch::Credentials::Location

  def test_takes_the_nearest_metacrunch_directory_above_the_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, ".metacrunch"), File.join(root, "app", ".metacrunch")])
      job = write_file(root, "app/jobs/x.rb", "")

      assert_equal File.join(root, "app", ".metacrunch"), Location.for_job(job_file: job, env: {}).directory
    end
  end

  def test_starts_in_the_directory_of_the_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "jobs", ".metacrunch"))
      job = write_file(root, "jobs/x.rb", "")

      assert_equal File.join(root, "jobs", ".metacrunch"), Location.for_job(job_file: job, env: {}).directory
    end
  end

  def test_resolves_a_symlinked_job_file
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "project", ".metacrunch"), File.join(root, "bin")])
      File.symlink(write_file(root, "project/jobs/x.rb", ""), File.join(root, "bin", "x"))

      assert_equal File.join(root, "project", ".metacrunch"),
                   Location.for_job(job_file: File.join(root, "bin", "x"), env: {}).directory
    end
  end

  def test_falls_back_to_the_home_directory
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "home", ".metacrunch"))
      job = write_file(root, "opt/jobs/x.rb", "")

      assert_equal File.join(root, "home", ".metacrunch"),
                   Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")}).directory
    end
  end

  def test_a_project_directory_without_the_environment_file_hides_the_home_directory
    in_tmpdir do |root|
      write_credentials(File.join(root, "home"), {"a" => 1}, environment: "production")
      FileUtils.mkdir_p(File.join(root, "opt", ".metacrunch"))
      job = write_file(root, "opt/jobs/x.rb", "")
      location = Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")}, environment: "production")

      assert_equal File.join(root, "opt", ".metacrunch", "credentials.production.yml.enc"), location.file
    end
  end

  def test_says_what_it_searched_when_there_is_no_directory
    in_tmpdir do |root|
      job = write_file(root, "jobs/x.rb", "")
      location = Location.for_job(job_file: job, env: {"HOME" => File.join(root, "home")})

      assert_nil location.directory
      assert_equal "no .metacrunch/ above #{job}, no ~/.metacrunch/", location.searched
    end
  end

  def test_works_without_home_and_without_job_file
    location = Location.for_job(job_file: nil, env: {})

    assert_nil location.directory
    assert_equal "no ~/.metacrunch/", location.searched
  end

  def test_the_option_wins_over_the_variable_and_the_search
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "jobs", ".metacrunch"))
      job = write_file(root, "jobs/x.rb", "")
      env = {"METACRUNCH_CREDENTIALS" => "/from/variable"}

      assert_equal "/from/option", Location.for_job(job_file: job, env:, directory: "/from/option").directory
      assert_equal "/from/variable", Location.for_job(job_file: job, env:).directory
      assert_predicate Location.for_job(job_file: job, env:), :explicit?
    end
  end

  def test_a_relative_directory_is_relative_to_the_working_directory
    in_tmpdir do |root|
      directory = Dir.chdir(root) { Location.for_job(job_file: nil, env: {}, directory: "secrets").directory }

      assert_equal File.join(root, "secrets"), directory
    end
  end

  def test_files_follow_the_environment
    location = Location.for_job(job_file: nil, env: {"METACRUNCH_ENV" => "production"}, directory: "/p/.metacrunch")

    assert_equal "/p/.metacrunch/credentials.production.yml.enc", location.file
    assert_equal "/p/.metacrunch/master.production.key", location.key_file
  end

  def test_the_key_comes_from_the_key_file
    in_tmpdir do |root|
      key = write_credentials(root, {})
      found = Location.for_job(job_file: nil, env: {}, directory: File.join(root, ".metacrunch")).key

      assert_equal [key.hex, File.join(root, ".metacrunch", "master.key")], [found.hex, found.source]
    end
  end

  def test_the_key_variable_wins_over_the_key_file
    in_tmpdir do |root|
      write_credentials(root, {})
      variable = Metacrunch::Credentials::Key.generate
      env = {"METACRUNCH_MASTER_KEY" => variable.hex}
      found = Location.for_job(job_file: nil, env:, directory: File.join(root, ".metacrunch")).key

      assert_equal [variable.hex, "METACRUNCH_MASTER_KEY"], [found.hex, found.source]
    end
  end

  def test_without_a_key_key_bang_says_how_to_provide_one
    location = Location.for_job(job_file: nil, env: {}, directory: "/p/.metacrunch", environment: "production")
    error = assert_raises(Metacrunch::CredentialsError) { location.key! }

    assert_nil location.key
    assert_equal "no key for /p/.metacrunch/credentials.production.yml.enc: set METACRUNCH_MASTER_KEY or " \
                 "create /p/.metacrunch/master.production.key", error.message
  end

  def test_the_command_searches_above_the_working_directory
    in_tmpdir do |root|
      FileUtils.mkdir_p([File.join(root, ".metacrunch"), File.join(root, "jobs")])
      location = Location.for_command(cwd: File.join(root, "jobs"), env: {})

      assert_equal File.join(root, ".metacrunch"), location.directory
      assert_predicate location, :exist?
    end
  end

  def test_the_command_never_picks_the_home_directory_by_itself
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      location = Location.for_command(cwd: File.join(home, "new"), env: {"HOME" => home})

      assert_equal File.join(home, "new", ".metacrunch"), location.directory
      refute_predicate location, :exist?
    end
  end

  def test_the_command_takes_the_home_directory_when_it_is_given
    in_tmpdir do |home|
      FileUtils.mkdir_p([File.join(home, ".metacrunch"), File.join(home, "new")])
      location = Location.for_command(cwd: File.join(home, "new"), env: {"HOME" => home},
                                      directory: File.join(home, ".metacrunch"))

      assert_equal File.join(home, ".metacrunch"), location.directory
    end
  end

end
