# frozen_string_literal: true

require "test_helper"

class JobCredentialsTest < Minitest::Test

  include CredentialsHelper

  def test_load_job_remembers_the_file
    in_tmpdir do |root|
      path = write_file(root, "jobs/x.rb", SECRET_JOB)

      assert_equal path, Metacrunch.load_job(path).file
      assert_nil Metacrunch::Job.new { source [] }.file
    end
  end

  def test_run_reads_credentials_above_the_job_file
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      output = File.join(root, "out.jsonl")
      result = job.run(["--output", output], env: {"METACRUNCH_ENV" => "production"}, logger: Logger.new(nil))

      assert_equal :ok, result.status
      assert_equal "\"#{SECRET.reverse}\"\n" * 2, File.read(output)
    end
  end

  def test_run_takes_the_key_from_the_environment
    in_tmpdir do |root|
      key = write_credentials(root, {"catalog" => {"api_key" => SECRET}}, key_file: false)
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      output = File.join(root, "out.jsonl")
      job.run(["--output", output], env: {"METACRUNCH_MASTER_KEY" => key.hex}, logger: Logger.new(nil))

      assert_equal "\"#{SECRET.reverse}\"\n" * 2, File.read(output)
    end
  end

  def test_run_logs_a_warning_for_a_secret_on_the_command_line
    in_tmpdir do |root|
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      io = StringIO.new
      job.run(["--api-key", SECRET, "--output", File.join(root, "out.jsonl")], env: {}, logger: Logger.new(io))

      assert_includes io.string, "--api-key is a secret; pass it by CATALOG_API_KEY or credentials instead"
      refute_includes io.string, SECRET
    end
  end

  def test_run_rejects_an_invalid_environment_name
    job = Metacrunch::Job.new { source [] }

    assert_raises(Metacrunch::CredentialsError) do
      job.run([], env: {"METACRUNCH_ENV" => "Prod"}, logger: Logger.new(nil))
    end
  end

end
