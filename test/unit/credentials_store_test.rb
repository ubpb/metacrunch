# frozen_string_literal: true

require "test_helper"

class CredentialsStoreTest < Minitest::Test

  include CredentialsHelper
  include Override

  def test_looks_up_paths_through_nested_hashes
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => "sk-123"}, "port" => 9200})
      credentials = store(root)

      assert_equal ["sk-123", "9200"], [credentials.lookup("catalog.api_key"), credentials.lookup("port")]
    end
  end

  def test_missing_keys_nil_values_and_scalars_on_the_way_give_nil
    in_tmpdir do |root|
      write_credentials(root, {"catalog" => {"api_key" => nil}, "port" => 9200})
      credentials = store(root)

      assert_equal([nil, nil, nil], ["catalog.api_key", "es.password", "port.x"].map { credentials.lookup(it) })
    end
  end

  def test_decrypts_once
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1, "b" => 2})
      calls = 0
      unseal = Metacrunch::Credentials::Box.method(:unseal)
      counting = lambda do |*args, **options|
        calls += 1
        unseal.call(*args, **options)
      end
      credentials = store(root)
      override(Metacrunch::Credentials::Box, :unseal, counting) { [credentials.lookup("a"), credentials.lookup("b")] }

      assert_equal 1, calls
    end
  end

  def test_reads_nothing_before_the_first_lookup
    in_tmpdir do |root|
      write_file(root, ".metacrunch/credentials.yml.enc", "garbage")
      credentials = store(root)

      assert_raises(Metacrunch::CredentialsError) { credentials.lookup("a") }
    end
  end

  def test_a_failed_read_is_not_taken_for_empty_credentials
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1}, key_file: false)
      credentials = store(root)

      assert_raises(Metacrunch::CredentialsError) { credentials.lookup("a") }
      assert_raises(Metacrunch::CredentialsError) { credentials.lookup("a") }
    end
  end

  def test_explains_why_a_value_is_missing
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1})
      dir = File.join(root, ".metacrunch")

      assert_equal "catalog.api_key not in #{dir}/credentials.yml.enc", store(root).missing("catalog.api_key")
      assert_equal "no credentials for environment production in #{dir}",
                   store(root, environment: "production").missing("a")
    end
  end

  def test_explains_a_missing_file_without_environment
    in_tmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".metacrunch"))

      assert_equal "no credentials.yml.enc in #{File.join(root, ".metacrunch")}", store(root).missing("a")
    end
  end

  def test_without_a_directory_there_are_no_values
    credentials = Metacrunch::Credentials.store(job_file: nil, env: {})

    assert_nil credentials.lookup("catalog.api_key")
    assert_equal "no credentials directory: no ~/.metacrunch/", credentials.missing("catalog.api_key")
  end

  def test_a_given_directory_must_exist
    credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: "/nonexistent/.metacrunch")
    error = assert_raises(Metacrunch::CredentialsError) { credentials.lookup("a") }

    assert_equal "credentials directory not found: /nonexistent/.metacrunch", error.message
  end

  def test_logs_the_decrypted_file_at_debug_level
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1})
      io = StringIO.new
      store(root, logger: Logger.new(io, level: Logger::DEBUG)).lookup("a")

      assert_includes io.string, "credentials: #{root}/.metacrunch/credentials.yml.enc"
    end
  end

  def test_inspect_shows_neither_the_key_nor_the_values
    in_tmpdir do |root|
      key = write_credentials(root, {"catalog" => {"api_key" => "sk-123-geheim"}}, key_file: false)
      env = {"METACRUNCH_MASTER_KEY" => key.hex}
      credentials = Metacrunch::Credentials.store(job_file: nil, env:, directory: File.join(root, ".metacrunch"))
      credentials.lookup("catalog.api_key")

      assert_equal "#<Metacrunch::Credentials::Store #{root}/.metacrunch/credentials.yml.enc>", credentials.inspect
      refute_includes Metacrunch::Credentials::Location.for_job(job_file: nil, env:).inspect, key.hex
    end
  end

  def test_an_unreadable_credentials_file_is_a_credentials_error
    skip "root reads every file" if Process.euid.zero?
    in_tmpdir do |root|
      write_credentials(root, {"a" => 1})
      file = File.join(root, ".metacrunch", "credentials.yml.enc")
      File.chmod(0o000, file)
      error = assert_raises(Metacrunch::CredentialsError) { store(root).lookup("a") }

      assert_equal "cannot read #{file}: Permission denied", error.message
    end
  end

  def test_origin_names_the_path_and_the_file
    credentials = Metacrunch::Credentials.store(job_file: nil, env: {}, directory: "/p/.metacrunch")

    assert_equal "credential catalog.api_key in /p/.metacrunch/credentials.yml.enc",
                 credentials.origin("catalog.api_key")
  end

  private

  def store(root, environment: nil, logger: nil)
    Metacrunch::Credentials.store(job_file: nil, env: {}, environment:, logger:,
                                  directory: File.join(root, ".metacrunch"))
  end

end
