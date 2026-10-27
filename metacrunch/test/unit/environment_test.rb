# frozen_string_literal: true

require "test_helper"

class EnvironmentTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  RESERVED_IN_RUBY = %(environment: "default" is reserved: leave environment: out for the default environment)

  JOB = <<~RUBY
    Metacrunch.job do
      params { secret :api_key, default: {credential: "catalog.api_key"} }

      source [1]
      map { params.api_key.reverse }
    end
  RUBY

  def test_the_default_environment_is_reserved
    messages = [
      assert_raises(Metacrunch::CredentialsError) { Metacrunch::Credentials.environment("default", {}) },
      assert_raises(Metacrunch::CredentialsError) do
        Metacrunch::Credentials.environment(nil, {"METACRUNCH_ENV" => "default"})
      end
    ].map(&:message)

    assert_equal ["default is the environment without -e; leave -e out",
                  "METACRUNCH_ENV=default: default is the environment without -e; unset METACRUNCH_ENV"], messages
  end

  def test_an_invalid_name_from_the_variable_says_so
    error = assert_raises(Metacrunch::CredentialsError) do
      Metacrunch::Credentials.environment(nil, {"METACRUNCH_ENV" => "Prod"})
    end

    assert_equal %(invalid environment "Prod" (from METACRUNCH_ENV): use a-z, 0-9, _ and -), error.message
  end

  def test_the_source_of_the_environment
    assert_equal [["production", "-e"], ["staging", "METACRUNCH_ENV"], nil],
                 [Metacrunch::Credentials.environment_source("production", {"METACRUNCH_ENV" => "staging"}),
                  Metacrunch::Credentials.environment_source(nil, {"METACRUNCH_ENV" => "staging"}),
                  Metacrunch::Credentials.environment_source(nil, {})]
  end

  def test_the_cli_refuses_the_reserved_name
    in_tmpdir do |root|
      job_file = project(root)
      codes = [cli("run", "-e", "default", job_file), cli("run", job_file, env: {"METACRUNCH_ENV" => "default"})]

      assert_equal [2, 2], codes.map(&:first)
      assert_includes codes.first.last, "default is the environment without -e; leave -e out"
    end
  end

  def test_the_environment_source_is_logged
    in_tmpdir do |root|
      job_file = project(root)
      logs = [
        cli("run", "-e", "production", job_file)[2],
        cli("run", job_file, env: {"METACRUNCH_ENV" => "production"})[2],
        cli("check", job_file)[2]
      ]

      assert_includes logs[0], "environment production (from -e)"
      assert_includes logs[1], "environment production (from METACRUNCH_ENV)"
      refute_includes logs[2], "environment"
    end
  end

  def test_job_run_takes_an_environment
    in_tmpdir do |root|
      project(root)
      check = "params.api_key == #{SECRET.inspect} ? it : raise(\"wrong key\")"
      job_file = write_file(root, "jobs/production.rb", JOB.sub("params.api_key.reverse", check))
      result = Metacrunch.load_job(job_file).run(environment: "production", env: {}, logger: Logger.new(nil))

      assert_equal :ok, result.status, result.error
    end
  end

  def test_ruby_refuses_the_reserved_name_without_mentioning_e
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"jobs/*.rb\"\n")
      write_file(root, "jobs/named.rb", JOB.sub("Metacrunch.job do", "Metacrunch.job(\"secret\") do"))
      job = Metacrunch.load_job(project(root))
      project = Metacrunch.load_project(root)
      errors = [
        assert_raises(Metacrunch::CredentialsError) do
          job.run(environment: "default", env: {}, logger: Logger.new(nil))
        end,
        assert_raises(Metacrunch::CredentialsError) do
          project.invoke("secret", environment: "default", env: {}, logger: Logger.new(nil))
        end
      ]

      assert_equal [RESERVED_IN_RUBY] * 2, errors.map(&:message)
    end
  end

  def test_project_invoke_takes_an_environment
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"*.rb\"\n")
      write_file(root, "secret.rb", JOB.sub("Metacrunch.job do", "Metacrunch.job(\"secret\") do"))
      result = Metacrunch.load_project(root).invoke("secret", environment: "production", env: {},
                                                              logger: Logger.new(nil), stdout: StringIO.new)

      assert_equal :ok, result.status, result.error
    end
  end

  private

  # A job that needs a credential, whose production value is SECRET;
  # returns its file.
  def project(root)
    write_credentials(root, {"catalog" => {"api_key" => "not the production key"}})
    write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
    write_file(root, "jobs/secret.rb", JOB)
  end

end
