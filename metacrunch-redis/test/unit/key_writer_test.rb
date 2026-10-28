# frozen_string_literal: true

require "test_helper"

class KeyWriterTest < Minitest::Test

  KeyWriter = Metacrunch::Redis::KeyWriter
  OOM = "OOM command not allowed when used memory > 'maxmemory'."

  def setup
    @redis = FakeRedis.new
    @connection = FakeConnection.new(@redis)
  end

  def test_constructor_checks_the_options
    {
      {key: 1} => "key must be a template such as book:%{isbn} or a callable, got 1",
      {key: ""} => "key must be a template such as book:%{isbn} or a callable, got \"\"",
      {action: :index} => "action must be :set, :delete or a callable, got :index",
      {format: :xml} => "format must be :json or :string, got :xml",
      {expire: 0} => "expire must be a positive Integer of seconds, got 0",
      {expire: 1.5} => "expire must be a positive Integer of seconds, got 1.5",
      {max_bytes: 0} => "max_bytes must be a positive Integer, got 0"
    }.each do |options, message|
      error = assert_raises(ArgumentError) { KeyWriter.new(@connection, key: "book:%{isbn}", **options) }

      assert_equal message, error.message
    end
  end

  def test_sets_json_values_under_template_keys
    write([{"isbn" => "1", "title" => "A"}, {"isbn" => "2"}])

    assert_equal({"book:1" => '{"isbn":"1","title":"A"}', "book:2" => '{"isbn":"2"}'}, @redis.strings)
  end

  def test_expire_sets_ex
    write([{"isbn" => "1"}], expire: 60)

    assert_equal ["SET", "book:1", '{"isbn":"1"}', "EX", "60"], @redis.commands.last
    assert_equal({"book:1" => 60}, @redis.expiries)
  end

  def test_callable_key_and_a_callable_action_that_deletes
    @redis.call("SET", "b-1", "old")
    write([{"id" => 1, "deleted" => true}, {"id" => 2}],
          key: ->(record) { "b-#{record["id"]}" }, action: ->(record) { record["deleted"] ? :delete : :set })

    assert_equal({"b-2" => '{"id":2}'}, @redis.strings)
  end

  def test_action_delete_needs_no_value_the_format_takes
    @redis.call("SET", "book:1", "old")
    write([{"isbn" => "1"}], action: :delete, format: :string)

    assert_empty @redis.strings
  end

  def test_the_last_command_for_a_key_wins
    write([{"isbn" => "1", "n" => 1}, {"isbn" => "1", "n" => 2}])

    assert_equal({"book:1" => '{"isbn":"1","n":2}'}, @redis.strings)
  end

  def test_format_string_writes_strings_under_a_callable_key
    write(["<record/>"], key: ->(_record) { "latest" }, format: :string)

    assert_equal({"latest" => "<record/>"}, @redis.strings)
  end

  def test_failed_records_are_reported_after_the_others
    action = ->(record) { record["action"] || :set }
    error = assert_raises(Metacrunch::SinkFailures) do
      write([{"isbn" => "1"}, {"title" => "no isbn"}, {"isbn" => "3", "action" => :index}, {"isbn" => "4", "x" => Float::NAN},
             {"isbn" => "5"}], action:)
    end
    messages = error.failed.transform_values(&:message)

    assert_equal({1 => "no value for isbn in the key book:%{isbn}", 2 => "action must be :set or :delete, got :index"},
                 messages.slice(1, 2))
    assert_equal ["book:1", "book:5"], @redis.strings.keys
  end

  def test_a_callable_key_must_give_a_non_empty_string
    error = assert_raises(Metacrunch::SinkFailures) { write([{}], key: ->(_record) {}) }

    assert_equal "key returned nil, not a non-empty String", error.failed[0].message
  end

  def test_pieces_stay_within_max_bytes
    write([{"isbn" => "1"}, {"isbn" => "2"}, {"isbn" => "3"}], max_bytes: 30) # 21 bytes per SET

    assert_equal [3, 3], [@redis.strings.size, @redis.pipelines]
  end

  def test_a_batch_goes_out_in_one_pipeline
    write([{"isbn" => "1"}, {"isbn" => "2"}, {"isbn" => "3"}])

    assert_equal 1, @redis.pipelines
  end

  def test_a_redis_error_stops_the_run
    @redis.fail_next(RedisClient::OutOfMemoryError.new(OOM, "OOM"), on: "SET")
    error = assert_raises(Metacrunch::OutputError) { write([{"isbn" => "1"}]) }

    assert_equal "redis keys book:%{isbn}: #{OOM}", error.message
    assert_kind_of RedisClient::OutOfMemoryError, error.cause
  end

  def test_an_error_of_connect_is_an_output_error
    connection = FakeConnection.new(error: Metacrunch::Redis::Error.new("redis://fake:6379/0: Connection refused"))
    error = assert_raises(Metacrunch::OutputError) { KeyWriter.new(connection, key: "book:%{isbn}").open(context) }

    assert_equal "redis keys book:%{isbn}: redis://fake:6379/0: Connection refused", error.message
  end

  def test_write_without_open_connects_and_writes_one_record
    KeyWriter.new(@connection, key: "book:%{isbn}").write({"isbn" => "1"})

    assert_equal ["book:1"], @redis.strings.keys
  end

  def test_close_closes_the_client_and_does_nothing_without_open
    writer = KeyWriter.new(@connection, key: "book:%{isbn}")

    assert_nil writer.close
    writer.open(context)
    writer.close

    assert_predicate @redis, :closed?
  end

  def test_inspect_names_key_action_and_connection
    assert_equal "#<Metacrunch::Redis::KeyWriter key=book:%{isbn} action=set connection=#<FakeConnection>>",
                 KeyWriter.new(@connection, key: "book:%{isbn}").inspect
    assert_equal "#<Metacrunch::Redis::KeyWriter key=(callable) action=(callable) connection=#<FakeConnection>>",
                 KeyWriter.new(@connection, key: ->(_) { "k" }, action: ->(_) { :set }).inspect
  end

  private

  def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(nil))

  # Writes the records as one batch with a writer of options, opened and closed as in a job.
  def write(records, key: "book:%{isbn}", **)
    writer = KeyWriter.new(@connection, key:, **)
    writer.open(context)
    writer.write_batch(records)
  ensure
    writer&.close
  end

end
