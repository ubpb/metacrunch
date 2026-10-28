# frozen_string_literal: true

require "test_helper"

class QueueWriterTest < Minitest::Test

  QueueWriter = Metacrunch::Redis::QueueWriter
  OOM = "OOM command not allowed when used memory > 'maxmemory'."

  def setup
    @redis = FakeRedis.new
    @connection = FakeConnection.new(@redis)
    @log = StringIO.new
  end

  def test_constructor_checks_the_options
    {
      {queue: ""} => "queue must be a non-empty String, got \"\"",
      {queue: nil} => "queue must be a non-empty String, got nil",
      {format: :yaml} => "format must be :json or :string, got :yaml",
      {max_length: 0} => "max_length must be a positive Integer, got 0",
      {max_length: 1.5} => "max_length must be a positive Integer, got 1.5",
      {pause: 0} => "pause must be a positive number of seconds, got 0",
      {pause: "1"} => "pause must be a positive number of seconds, got \"1\"",
      {max_bytes: -1} => "max_bytes must be a positive Integer, got -1"
    }.each do |options, message|
      error = assert_raises(ArgumentError) { QueueWriter.new(@connection, queue: "books", **options) }

      assert_equal message, error.message
    end
  end

  def test_writes_json_entries_in_order_with_one_rpush_per_batch
    writer { it.write_batch([{"isbn" => "1"}, {"isbn" => "2"}, "three"]) }

    assert_equal ['{"isbn":"1"}', '{"isbn":"2"}', '"three"'], @redis.lists["books"]
    assert_equal 1, @redis.names.count("RPUSH")
  end

  def test_rpush_goes_through_call_once
    writer { it.write_batch(["a"]) }

    assert_equal ["RPUSH", "books", '"a"', :once], @redis.commands.last
  end

  def test_format_string_writes_strings_as_they_are
    writer(format: :string) { it.write_batch(["<record/>", "<record/>"]) }

    assert_equal ["<record/>", "<record/>"], @redis.lists["books"]
  end

  def test_records_that_cannot_be_encoded_are_reported_after_the_others
    error = assert_raises(Metacrunch::SinkFailures) do
      writer { it.write_batch([1, Float::NAN, 3, Set[4], 5]) }
    end

    assert_equal({1 => Metacrunch::Redis::Error, 3 => Metacrunch::Redis::Error}, error.failed.transform_values(&:class))
    assert_equal ["1", "3", "5"], @redis.lists["books"]
  end

  def test_a_batch_of_failed_records_sends_nothing
    assert_raises(Metacrunch::SinkFailures) { writer { it.write_batch([Float::NAN]) } }

    refute_includes @redis.names, "RPUSH"
  end

  def test_pieces_stay_within_max_bytes
    small = "x" * 18 # 20 bytes as JSON
    writer(max_bytes: 50) { it.write_batch([small, small, small, "y" * 58, small]) }
    pushes = @redis.commands.select { it.first == "RPUSH" }.map { it.size - 3 }

    assert_equal [2, 1, 1, 1], pushes
    assert_equal 5, @redis.lists["books"].size
  end

  def test_write_writes_a_batch_of_one
    writer { it.write({"isbn" => "1"}) }

    assert_equal ['{"isbn":"1"}'], @redis.lists["books"]
  end

  def test_an_oom_piece_is_retried_after_the_written_pieces
    @redis.fail_next(RedisClient::OutOfMemoryError.new(OOM, "OOM"), on: "RPUSH", times: 2, after: 1)
    writer(max_bytes: 1, pause: 0.01) { it.write_batch([1, 2, 3]) }

    assert_equal ["1", "2", "3"], @redis.lists["books"]
    assert_equal 5, @redis.names.count("RPUSH")
  end

  def test_a_pause_on_oom_is_logged_when_it_begins_and_ends
    @redis.fail_next(RedisClient::OutOfMemoryError.new(OOM, "OOM"), on: "RPUSH", times: 3)
    writer(pause: 0.01) { it.write_batch([1]) }

    assert_equal(["redis queue books: Redis is full (maxmemory); waiting for consumers to take entries"],
                 log_lines("WARN").map { it.split(" -- : ").last.chomp })
    assert_match(/redis queue books: going on after \d+ s/, log_lines("INFO").last)
  end

  def test_max_length_pauses_until_the_queue_is_shorter
    @redis.push("books", "a", "b", "c")
    Thread.new do
      sleep(0.05)
      @redis.call("LPOP", "books", 2)
    end
    writer(max_length: 3, pause: 0.01) { it.write_batch(["d"]) }

    assert_equal ["c", '"d"'], @redis.lists["books"]
    assert_includes log_lines("WARN").first,
                    "redis queue books: the queue holds 3 entries (max_length 3); waiting for consumers"
    assert_equal 1, log_lines("INFO").size
  end

  def test_stop_while_redis_is_full_gives_up_the_batch
    @redis.fail_next(RedisClient::OutOfMemoryError.new(OOM, "OOM"), on: "RPUSH", times: 1000)
    error = stopped_while_waiting(max_bytes: 4) { it.write_batch([1, 2, 3, 4, 5, 6]) }

    assert_equal "redis queue books: stopped while waiting for consumers; 6 records of the batch were not written",
                 error.message
  end

  def test_stop_at_max_length_gives_up_the_rest_of_the_batch
    @redis.push("books", "a", "b")
    error = stopped_while_waiting(max_length: 3, max_bytes: 1) { it.write_batch([1, 2, 3]) }

    assert_equal "redis queue books: stopped while waiting for consumers; 2 records of the batch were not written",
                 error.message
    assert_equal ["a", "b", "1"], @redis.lists["books"]
  end

  def test_a_writer_that_was_stopped_does_not_wait
    @redis.fail_next(RedisClient::OutOfMemoryError.new(OOM, "OOM"), on: "RPUSH")
    error = assert_raises(Metacrunch::OutputError) do
      writer(pause: 5) do |w|
        w.stop
        w.write_batch(["a"])
      end
    end

    assert_equal "redis queue books: stopped while waiting for consumers; 1 record of the batch was not written",
                 error.message
  end

  def test_a_writer_that_was_stopped_still_writes_when_there_is_room
    writer do |w|
      w.stop
      w.write_batch(["a"])
    end

    assert_equal ['"a"'], @redis.lists["books"]
  end

  def test_no_pause_below_max_length
    writer(max_length: 3, pause: 0.01) { it.write_batch(["a", "b"]) }

    assert_empty log_lines("WARN")
  end

  def test_open_refuses_a_key_of_another_type
    @redis.call("SET", "books", "x")
    error = assert_raises(Metacrunch::OutputError) { writer }

    assert_equal "redis queue books: books holds a string, not a list", error.message
  end

  def test_open_warns_about_an_eviction_policy
    @redis.info_memory = "# Memory\r\nmaxmemory:1000000\r\nmaxmemory_policy:allkeys-lru\r\n"
    writer

    assert_includes log_lines("WARN").first,
                    "redis queue books: Redis evicts keys when it is full (maxmemory-policy allkeys-lru), entries " \
                    "of this queue among them; set maxmemory-policy noeviction"
  end

  def test_no_eviction_warning_without_maxmemory_with_noeviction_or_without_info
    ["maxmemory:0\r\nmaxmemory_policy:allkeys-lru\r\n",
     "maxmemory:100\r\nmaxmemory_policy:noeviction\r\n"].each do |info|
      @redis.info_memory = info
      writer
    end
    @redis.fail_next(RedisClient::CommandError.new("ERR unknown command 'INFO'"), on: "INFO")
    writer

    assert_empty log_lines("WARN")
  end

  def test_other_redis_errors_stop_the_run
    [RedisClient::WrongTypeError.new(FakeRedis::WRONGTYPE), RedisClient::ConnectionError.new("Connection reset")]
      .each do |cause|
        @redis.fail_next(cause, on: "RPUSH")
        error = assert_raises(Metacrunch::OutputError) { writer { it.write_batch(["a"]) } }

        assert_equal "redis queue books: #{cause.message}", error.message
        assert_same cause, error.cause
      end
  end

  def test_an_error_of_connect_is_an_output_error
    connection = FakeConnection.new(error: Metacrunch::Redis::Error.new("redis://fake:6379/0: Connection refused"))
    error = assert_raises(Metacrunch::OutputError) { QueueWriter.new(connection, queue: "books").open(context) }

    assert_equal "redis queue books: redis://fake:6379/0: Connection refused", error.message
  end

  def test_write_without_open_connects
    QueueWriter.new(@connection, queue: "books").write_batch(["a"])

    assert_equal ['"a"'], @redis.lists["books"]
  end

  def test_write_without_open_checks_the_key
    @redis.call("SET", "books", "x")
    error = assert_raises(Metacrunch::OutputError) { QueueWriter.new(@connection, queue: "books").write_batch(["a"]) }

    assert_equal "redis queue books: books holds a string, not a list", error.message
  end

  def test_close_closes_the_client
    writer

    assert_predicate @redis, :closed?
  end

  def test_close_without_open_does_nothing
    assert_nil QueueWriter.new(@connection, queue: "books").close
    assert_equal 0, @connection.connects
  end

  def test_inspect_names_queue_and_connection
    assert_equal "#<Metacrunch::Redis::QueueWriter queue=books connection=#<FakeConnection>>",
                 QueueWriter.new(@connection, queue: "books").inspect
  end

  private

  def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(@log))

  # A writer of options, opened, given to the block and closed, as in a job.
  def writer(**)
    writer = QueueWriter.new(@connection, queue: "books", **)
    writer.open(context)
    yield writer if block_given?
  ensure
    writer&.close
  end

  # Writes in a thread with a long pause, stops the writer after 0.1 s and returns the OutputError, which must come
  # within a second.
  def stopped_while_waiting(**, &)
    writer = QueueWriter.new(@connection, queue: "books", pause: 5, **)
    writer.open(context)
    thread = Thread.new { assert_raises(Metacrunch::OutputError) { yield writer } }
    sleep(0.1)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    writer.stop

    thread.value.tap { assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1 }
  ensure
    writer&.close
  end

  def log_lines(level) = @log.string.lines.grep(/ #{level} -- /)

end
