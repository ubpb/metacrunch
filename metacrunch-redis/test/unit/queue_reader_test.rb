# frozen_string_literal: true

require "test_helper"

class QueueReaderTest < Minitest::Test

  QueueReader = Metacrunch::Redis::QueueReader
  FLUSH = Metacrunch::FLUSH

  def setup
    @redis = FakeRedis.new
    @connection = FakeConnection.new(@redis)
    @log = StringIO.new
  end

  def test_constructor_checks_the_options
    {
      {queue: nil} => "queue must be a non-empty String, got nil",
      {wait: 0} => "wait must be true, false or a number of seconds above 0, got 0",
      {wait: -1} => "wait must be true, false or a number of seconds above 0, got -1",
      {wait: "x"} => "wait must be true, false or a number of seconds above 0, got \"x\"",
      {format: :xml} => "format must be :json or :string, got :xml",
      {fetch: 0} => "fetch must be a positive Integer, got 0",
      {flush_after: 0} => "flush_after must be a positive number of seconds, got 0",
      {reconnect_delays: []} => "reconnect_delays must be a non-empty Array of seconds, got []",
      {reconnect_delays: [1, 0]} => "reconnect_delays must be a non-empty Array of seconds, got [1, 0]"
    }.each do |options, message|
      error = assert_raises(ArgumentError) { QueueReader.new(@connection, queue: "books", **options) }

      assert_equal message, error.message
    end
  end

  def test_takes_true_false_and_seconds_for_wait
    [true, false, 0.5, 300].each { QueueReader.new(@connection, queue: "books", wait: it) }
  end

  def test_reads_until_the_queue_is_empty
    @redis.push("books", *(1..250).map(&:to_s))

    assert_equal (1..250).to_a, read(fetch: 100)
    assert_equal 4, @redis.names.count("LPOP")
  end

  def test_progress_is_the_share_taken
    @redis.push("books", *(1..250).map(&:to_s))
    reader = opened(fetch: 100)
    shares = {}
    before = reader.progress
    reader.each { |number| shares[number] = reader.progress if [1, 100].include?(number) }

    assert_nil before
    assert_equal({1 => 1.fdiv(250), 100 => 0.4}, shares)
    assert_in_delta 1.0, reader.progress
  end

  def test_progress_of_an_empty_queue_is_done
    reader = opened

    reader.each { flunk("no record expected") }

    assert_in_delta 1.0, reader.progress
  end

  def test_progress_is_nil_with_wait
    @redis.push("books", "1")
    reader = opened(wait: 0.05)
    reader.each { nil }

    assert_nil reader.progress
  end

  def test_yields_invalid_json_as_an_invalid_record
    @redis.push("books", "{not json")
    record = read.first

    assert_kind_of Metacrunch::InvalidRecord, record
    assert_equal "{not json", record.raw
  end

  def test_format_string_yields_strings
    @redis.push("books", "<record/>")

    assert_equal ["<record/>"], read(format: :string)
  end

  def test_open_refuses_a_key_of_another_type
    @redis.call("SET", "books", "x")
    error = assert_raises(Metacrunch::InputError) { opened }

    assert_equal "redis queue books: books holds a string, not a list", error.message
  end

  def test_an_error_of_connect_is_an_input_error
    connection = FakeConnection.new(error: Metacrunch::Redis::Error.new("redis://fake:6379/0: Connection refused"))
    error = assert_raises(Metacrunch::InputError) { QueueReader.new(connection, queue: "books", wait: true).open(context) }

    assert_equal "redis queue books: redis://fake:6379/0: Connection refused", error.message
  end

  def test_each_without_open_connects_and_checks_the_key
    @redis.push("books", "1")
    reader = QueueReader.new(@connection, queue: "books")

    assert_equal [1], reader.each.to_a
    assert_equal ["TYPE", "books"], @redis.commands.first
  end

  def test_each_returns_the_reader
    reader = opened

    assert_same(reader, reader.each { nil })
  end

  def test_leftovers_go_back_to_the_head_in_order_after_break
    @redis.push("books", "1", "2", "3", "4", "5", "6")
    opened(fetch: 5).each { break if it == 2 }

    assert_equal ["3", "4", "5", "6"], @redis.lists["books"]
  end

  def test_leftovers_go_back_after_an_error_in_a_step
    @redis.push("books", "1", "2", "3", "4", "5")
    assert_raises(RuntimeError) { opened(fetch: 5).each { raise "step failed" if it == 2 } }

    assert_equal ["3", "4", "5"], @redis.lists["books"]
  end

  def test_a_failed_put_back_is_logged_and_the_error_passes
    @redis.push("books", "1", "2", "3", "4")
    @redis.fail_next(RedisClient::ConnectionError.new("Connection lost"), on: "LPUSH")
    error = assert_raises(RuntimeError) { opened(fetch: 4).each { raise "step failed" } }

    assert_equal "step failed", error.message
    assert_includes log_lines("ERROR").first, "redis queue books: 3 entries taken from the queue could not be put " \
                                              "back and are lost: Connection lost"
  end

  def test_wait_true_waits_for_entries_pushed_later
    pusher = Thread.new do
      sleep(0.1)
      @redis.push("books", "1", "2")
    end
    reader = opened(wait: true, flush_after: 0.05)
    records = []
    reader.each do |record|
      records << record
      reader.stop if record == 2
    end
    pusher.join

    assert_equal [1, 2], records
  end

  def test_wait_seconds_ends_after_a_quiet_time
    @redis.push("books", "1")
    started = now
    records = read(wait: 0.2)
    elapsed = now - started

    assert_equal [1], records
    assert_operator elapsed, :>=, 0.2
    assert_operator elapsed, :<, 1.5
  end

  def test_yields_flush_after_flush_after_seconds_once
    @redis.push("books", "1", "2")

    assert_equal [1, 2, FLUSH], read(wait: 0.5, flush_after: 0.1)
  end

  def test_under_load_flush_comes_at_most_once_per_flush_after
    pusher = Thread.new do
      60.times do |number|
        @redis.push("books", number.to_s)
        sleep(0.01)
      end
    end
    started = now
    records = read(wait: 0.3, flush_after: 0.1)
    elapsed = now - started
    pusher.join

    assert_equal (0...60).to_a, records - [FLUSH]
    assert_operator records.count(FLUSH), :<=, (elapsed / 0.1).ceil
    assert_operator records.count(FLUSH), :>=, 3
  end

  def test_the_round_trip_timeout_never_is_zero_and_at_most_a_second
    @redis.push("books", "1")
    read(wait: 0.15, flush_after: 0.05)

    assert_empty(@redis.blocking_timeouts.grep_v(0.01..1.0))
  end

  def test_blmpop_takes_fetch_entries_from_the_head
    @redis.push("books", "1")
    read(wait: 0.05, fetch: 7)
    command = @redis.commands.find { it.first == "BLMPOP" }

    assert_equal [1, "books", "LEFT", "COUNT", 7], command.drop(2)
  end

  def test_no_flush_without_wait
    @redis.push("books", "1", "2")

    assert_equal [1, 2], read(flush_after: 0.01)
  end

  def test_stop_returns_within_a_round_trip
    reader = opened(wait: true)
    Thread.new do
      sleep(0.1)
      reader.stop
    end
    started = now

    reader.each { flunk("no record expected") }

    assert_operator now - started, :<, 1.5
  end

  def test_stop_after_a_record_puts_the_rest_back
    @redis.push("books", "1", "2", "3", "4", "5")
    reader = opened(wait: true, fetch: 5)
    reader.each { reader.stop if it == 2 }

    assert_equal ["3", "4", "5"], @redis.lists["books"]
  end

  def test_stop_before_each_reads_nothing
    @redis.push("books", "1")
    reader = opened(wait: true)
    reader.stop

    reader.each { flunk("no record expected") }

    refute_includes @redis.names, "BLMPOP"
  end

  def test_wait_retries_a_lost_connection_with_growing_delays
    @redis.push("books", "1")
    @redis.fail_next(RedisClient::CannotConnectError.new("Connection refused"), on: "BLMPOP", times: 3)
    reader = opened(wait: true, reconnect_delays: [0.01, 0.02])
    reader.each { reader.stop }
    warnings = log_lines("WARN").map { it.split(" -- : ").last.chomp }

    expected = ["0.01", "0.02", "0.02"].map do |delay|
      "redis queue books: lost the connection (Connection refused); trying again in #{delay} s"
    end

    assert_equal expected, warnings
    assert_match(/redis queue books: connected again after \d+ s/, log_lines("INFO").last)
  end

  def test_wait_seconds_gives_up_after_the_quiet_time
    @redis.fail_next(RedisClient::CannotConnectError.new("Connection refused"), on: "BLMPOP", times: 1000)
    error = assert_raises(Metacrunch::InputError) do
      opened(wait: 0.1, reconnect_delays: [0.02]).each { flunk("no record expected") }
    end

    assert_match(/\Aredis queue books: no connection for \d+ s: Connection refused\z/, error.message)
  end

  def test_a_stop_ends_the_reconnect_delays
    @redis.fail_next(RedisClient::CannotConnectError.new("Connection refused"), on: "BLMPOP", times: 1000)
    reader = opened(wait: true, reconnect_delays: [5])
    Thread.new do
      sleep(0.1)
      reader.stop
    end
    started = now

    reader.each { flunk("no record expected") }

    assert_operator now - started, :<, 1.5
  end

  def test_without_wait_a_lost_connection_is_an_input_error
    @redis.fail_next(RedisClient::ConnectionError.new("Connection lost"), on: "LPOP")
    error = assert_raises(Metacrunch::InputError) { read }

    assert_equal "redis queue books: Connection lost", error.message
    assert_kind_of RedisClient::ConnectionError, error.cause
  end

  def test_command_errors_are_input_errors_also_with_wait
    @redis.fail_next(RedisClient::WrongTypeError.new(FakeRedis::WRONGTYPE), on: "BLMPOP")
    error = assert_raises(Metacrunch::InputError) { read(wait: true) }

    assert_equal "redis queue books: #{FakeRedis::WRONGTYPE}", error.message
  end

  def test_close_closes_the_client
    opened.close

    assert_predicate @redis, :closed?
  end

  def test_close_without_open_does_nothing
    assert_nil QueueReader.new(@connection, queue: "books").close
    assert_equal 0, @connection.connects
  end

  def test_inspect_names_queue_wait_and_connection
    assert_equal "#<Metacrunch::Redis::QueueReader queue=books wait=300 connection=#<FakeConnection>>",
                 QueueReader.new(@connection, queue: "books", wait: 300).inspect
  end

  private

  def context = Metacrunch::OpenContext.new(params: nil, logger: Logger.new(@log))

  def opened(**)
    QueueReader.new(@connection, queue: "books", **).tap { it.open(context) }
  end

  # What an opened reader of options yields.
  def read(**)
    reader = opened(**)
    reader.each.to_a
  ensure
    reader&.close
  end

  def log_lines(level) = @log.string.lines.grep(/ #{level} -- /)

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

end
