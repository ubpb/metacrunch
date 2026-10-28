# frozen_string_literal: true

require "test_helper"

module QueueTests

  # A batching sink that notes when each batch arrived.
  class TimedSink

    attr_reader :batches

    def initialize
      @batches = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @batches << [Process.clock_gettime(Process::CLOCK_MONOTONIC), records.dup]
    end

  end

  def test_a_producer_and_a_consumer_move_10000_records_in_order
    queue = key("books")
    records = (1..10_000).map { {"isbn" => it.to_s, "title" => "Title #{it}"} }
    connection = self.connection
    producer = Metacrunch::Job.new do
      source records
      sink Metacrunch::Redis::QueueWriter.new(connection, queue:), batch: 500
    end
    taken = []
    consumer = Metacrunch::Job.new do
      source Metacrunch::Redis::QueueReader.new(connection, queue:)
      map { taken << it }
    end

    assert_equal [:ok, :ok],
                 [producer.run(logger: Logger.new(nil)).status, consumer.run(logger: Logger.new(nil)).status]
    assert_equal records, taken
  end

  def test_a_waiting_consumer_writes_a_batch_before_the_queue_goes_quiet
    queue = key("books")
    connection = self.connection
    [nil, 2].each do |workers|
      redis.call("RPUSH", queue, *(1..5).map(&:to_s))
      sink = TimedSink.new
      job = Metacrunch::Job.new do
        source Metacrunch::Redis::QueueReader.new(connection, queue:, wait: 0.5, flush_after: 0.05)
        sink sink, batch: 1000
      end
      started = now
      job.run(logger: Logger.new(nil), workers:)

      assert_equal [1, 2, 3, 4, 5], sink.batches.flat_map(&:last)
      assert_operator sink.batches.first.first - started, :<, 0.4, "workers: #{workers.inspect}"
    end
  end

  def test_wait_seconds_ends_a_reader_after_a_quiet_time
    reader = Metacrunch::Redis::QueueReader.new(connection, queue: key("books"), wait: 0.3)
    reader.open(context)
    started = now

    assert_empty reader.each.to_a
    assert_includes 0.3..2.0, now - started
  ensure
    reader&.close
  end

  def test_a_reader_goes_on_after_its_connection_was_killed
    name = "metacrunch-test-#{SecureRandom.hex(3)}"
    queue = key("books")
    reader = Metacrunch::Redis::QueueReader.new(connection(id: name), queue:, wait: true, reconnect_delays: [0.1])
    log = StringIO.new
    reader.open(context(log))
    redis.call("RPUSH", queue, "1")
    taken = []
    reader.each do |record|
      next if record.equal?(Metacrunch::FLUSH)

      taken << record
      next reader.stop if record == 2

      kill_client(name)
      redis.call("RPUSH", queue, "2")
    end

    assert_equal [1, 2], taken
    assert_match(/lost the connection/, log.string)
  ensure
    reader&.close
  end

  def test_leftovers_go_back_to_the_queue
    queue = key("books")
    redis.call("RPUSH", queue, *(1..10).map(&:to_s))
    reader = Metacrunch::Redis::QueueReader.new(connection, queue:, fetch: 10)
    reader.open(context)
    reader.each { break if it == 3 }

    assert_equal (4..10).map(&:to_s), redis.call("LRANGE", queue, 0, -1)
  ensure
    reader&.close
  end

  def test_the_writer_pauses_at_max_length_until_a_consumer_takes_entries
    queue = key("books")
    redis.call("RPUSH", queue, *(1..10).map(&:to_s))
    consumer = Thread.new do
      sleep(0.3)
      connection.connect { it.call("LPOP", queue, 10) }
    end
    log = StringIO.new
    writer = Metacrunch::Redis::QueueWriter.new(connection, queue:, max_length: 10, pause: 0.05)
    writer.open(context(log))
    writer.write_batch(["a", "b"])
    consumer.join

    assert_equal ['"a"', '"b"'], redis.call("LRANGE", queue, 0, -1)
    assert_match(/the queue holds 10 entries \(max_length 10\); waiting for consumers/, log.string)
    assert_match(/going on after \d+ s/, log.string)
  ensure
    writer&.close
  end

  def test_a_key_of_another_type_is_refused
    redis.call("SET", key("books"), "x")
    error = assert_raises(Metacrunch::InputError) do
      Metacrunch::Redis::QueueReader.new(connection, queue: key("books")).open(context)
    end

    assert_equal "redis queue #{key("books")}: #{key("books")} holds a string, not a list", error.message
  end

  private

  def kill_client(name)
    line = redis.call("CLIENT", "LIST").lines.find { it.include?(" name=#{name} ") }
    redis.call("CLIENT", "KILL", "ID", line[/\Aid=(\d+)/, 1])
  end

end

Integration.define("Queue", QueueTests)
