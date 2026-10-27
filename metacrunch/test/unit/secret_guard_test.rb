# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class SecretGuardTest < Minitest::Test

  include CredentialsHelper

  def test_use_refuses_a_secret_passed_to_a_param
    error = assert_raises(Metacrunch::ParamError) { run_job(transform { param :key }, &:api_key) }

    assert_equal "use t: key gets a secret, but t declares it as param; declare it secret there", error.message
  end

  def test_use_passes_a_secret_to_a_secret
    result = run_job(transform { secret :key }, &:api_key)

    assert_equal [1], result.records
  end

  def test_a_derived_value_is_not_recognized
    result = run_job(transform { param :key }) { |params| params.api_key.dup }

    assert_equal [1], result.records
  end

  def test_equal_values_are_no_secret
    transform = transform do
      param :key
      param :port, Integer
    end
    job = Metacrunch.job do
      params do
        secret :api_key
        param :index
        secret :port, Integer
      end

      source [1]
      use transform, params: {key: params.index, port: params.port}
    end

    assert_equal [1], Metacrunch::Testing.run(job, params: {api_key: "same", index: "same", port: 5}).records
  end

  def test_invoke_refuses_a_secret_passed_to_a_param
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"*.rb\"\n")
      write_file(root, "show.rb", "Metacrunch.job(\"show\") { params { param :token }; source [1] }\n")
      write_file(root, "relay.rb", <<~RUBY)
        Metacrunch.command("relay") do
          params { secret :token }

          run { invoke "show", params: {token: params.token} }
        end
      RUBY
      project = Metacrunch.load_project(root)
      error = assert_raises(Metacrunch::InvokeError) do
        project.invoke("relay", params: {token: "x"}, logger: Logger.new(nil))
      end

      assert_equal "invoke show: token gets a secret, but show declares it as param; declare it secret there",
                   error.message
    end
  end

  private

  def transform(&)
    Metacrunch.transform("t") do
      params(&)
      map { it }
    end
  end

  # A job with secret api_key that uses transform with key: given by the block.
  def run_job(transform, &key)
    job = Metacrunch.job do
      params { secret :api_key }

      source [1]
      use transform, params: {key: key.call(params)}
    end
    Metacrunch::Testing.run(job, params: {api_key: "sk"})
  end

end
