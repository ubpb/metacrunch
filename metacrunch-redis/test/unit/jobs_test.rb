# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# The reader and the writer in jobs, inline and with workers, against the stand-in for redis-client.
class JobsTest < Minitest::Test

  # A batching sink that notes when each batch arrived. The writer runs in the main process, also with workers.
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

  def setup
    @redis = FakeRedis.new
    @connection = FakeConnection.new(@redis)
  end

  def test_a_waiting_job_writes_a_batch_before_the_queue_goes_quiet
    [nil, 2].each do |workers|
      @redis.push("books", *(1..5).map(&:to_s))
      sink = TimedSink.new
      result = consumer(sink).run(logger: Logger.new(nil), workers:)
      finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_equal :ok, result.status
      assert_equal [1, 2, 3, 4, 5], sink.batches.flat_map(&:last)
      # The run ends 0.4 s after the queue went quiet; the batch came long before.
      assert_operator finished - sink.batches.first.first, :>, 0.25, "workers: #{workers.inspect}"
    end
  end

  def test_a_job_moves_records_from_one_queue_into_another
    @redis.push("in", '{"isbn":"1"}', '{"isbn":"2"}')
    connection = @connection
    job = Metacrunch::Job.new do
      source Metacrunch::Redis::QueueReader.new(connection, queue: "in")
      map { it.merge("seen" => true) }
      sink Metacrunch::Redis::QueueWriter.new(connection, queue: "out"), batch: 10
    end
    result = job.run(logger: Logger.new(nil), workers: 2)

    assert_equal :ok, result.status
    assert_equal ['{"isbn":"1","seen":true}', '{"isbn":"2","seen":true}'], @redis.lists["out"]
  end

  def test_testing_run_replaces_the_reader_and_opens_nothing
    connection = FakeConnection.new(error: Metacrunch::Redis::Error.new("no server in tests"))
    job = Metacrunch::Job.new do
      source Metacrunch::Redis::QueueReader.new(connection, queue: "books", wait: true)
      map { it * 2 }
      sink Metacrunch::Redis::QueueWriter.new(connection, queue: "out")
    end
    result = Metacrunch::Testing.run(job, source: [1, 2])

    assert_equal [2, 4], result.records
    assert_equal 0, connection.connects
  end

  private

  # Reads books until the queue is quiet for 0.4 s, writing what it read 0.05 s after it read it.
  def consumer(sink)
    connection = @connection
    Metacrunch::Job.new do
      source Metacrunch::Redis::QueueReader.new(connection, queue: "books", wait: 0.4, flush_after: 0.05)
      sink sink, batch: 1000
    end
  end

end
