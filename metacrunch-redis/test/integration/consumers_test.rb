# frozen_string_literal: true

require "test_helper"
require "json"

# Consumers as processes, started with metacrunch's executable, as on several machines.
module ConsumersTests

  CONSUMER = <<~RUBY
    require "metacrunch/redis"

    Metacrunch.job do
      params do
        use Metacrunch::Redis::CONNECTION_PARAMS
        param :queue, String, required: true
        param :wait, Float
        param :fetch, Integer, default: 100
        param :delay, Float, default: 0.0
        param :output, String, required: true
      end

      redis = Metacrunch::Redis::Connection.from_params(params)
      source Metacrunch::Redis::QueueReader.new(redis, queue: params.queue, wait: params.wait || true, flush_after: 0.1,
                                                       fetch: params.fetch)
      map do |record|
        sleep(params.delay)
        record
      end
      sink Metacrunch::JsonLines::Writer.new(params.output), batch: 1000
    end
  RUBY

  # From one queue into another that is full.
  RELAY = <<~RUBY
    require "metacrunch/redis"

    Metacrunch.job do
      params do
        use Metacrunch::Redis::CONNECTION_PARAMS
        param :from, String, required: true
        param :to, String, required: true
      end

      redis = Metacrunch::Redis::Connection.from_params(params)
      source Metacrunch::Redis::QueueReader.new(redis, queue: params.from, wait: true)
      sink Metacrunch::Redis::QueueWriter.new(redis, queue: params.to, max_length: 5), batch: 10
    end
  RUBY

  def setup
    super
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "consumer.rb"), CONSUMER)
    File.write(File.join(@dir, "relay.rb"), RELAY)
  end

  def teardown
    FileUtils.remove_entry(@dir)
    super
  end

  def test_three_consumers_take_every_entry_once
    queue = key("books")
    redis.call("RPUSH", queue, *(1..3000).map { JSON.generate({"n" => it}) })
    consumers = [[], ["-w", "2"], ["-w", "2"]].each_with_index.map do |options, index|
      spawn_metacrunch(*options, "consumer.rb", *consumer_params(queue, "out-#{index}.jsonl"), "--wait", "1",
                       dir: @dir)
    end
    statuses = consumers.map { |pid, _| exited(pid) }
    taken = (0..2).flat_map { File.readlines(File.join(@dir, "out-#{it}.jsonl")).map { JSON.parse(it)["n"] } }

    assert_equal([true] * 3, statuses.map(&:success?), consumers.map { File.read(it.last) }.join)
    assert_equal (1..3000).to_a, taken.sort
  end

  def test_sigterm_ends_a_waiting_consumer_normally_after_it_wrote_what_it_read
    queue = key("books")
    redis.call("RPUSH", queue, *(1..100).map { JSON.generate({"n" => it}) })
    pid, log = spawn_metacrunch("-w", "2", "consumer.rb", *consumer_params(queue, "out.jsonl"), dir: @dir)
    eventually(20, "the consumer did not take the queue") { redis.call("LLEN", queue).zero? }
    sleep(0.3)
    started = now
    Process.kill("TERM", pid)
    status = exited(pid)

    assert_predicate status, :success?, File.read(log)
    assert_operator now - started, :<, 3
    assert_equal((1..100).to_a, File.readlines(File.join(@dir, "out.jsonl")).map { JSON.parse(it)["n"] })
  end

  def test_sigterm_in_the_middle_of_a_group_puts_the_rest_back_in_order
    queue = key("books")
    redis.call("RPUSH", queue, *(1..100).map { JSON.generate({"n" => it}) })
    pid, log = spawn_metacrunch("consumer.rb", *consumer_params(queue, "out.jsonl"), "--fetch", "20", "--delay", "0.05",
                                dir: @dir)
    eventually(20, "the consumer did not take a group") { redis.call("LLEN", queue) <= 80 }
    sleep(0.3)
    Process.kill("TERM", pid)
    status = exited(pid)
    written = File.readlines(File.join(@dir, "out.jsonl")).map { JSON.parse(it)["n"] }
    left = redis.call("LRANGE", queue, 0, -1).map { JSON.parse(it)["n"] }

    assert_predicate status, :success?, File.read(log)
    assert_equal (1..100).to_a, written + left
    assert_includes 1..19, written.size
  end

  def test_sigterm_ends_a_job_whose_writer_waits_for_room
    from = key("in")
    to = key("out")
    redis.call("RPUSH", to, *(1..5).map(&:to_s))
    redis.call("RPUSH", from, *(1..20).map(&:to_s))
    pid, log = spawn_metacrunch("relay.rb", "--url", target.url, "--from", from, "--to", to, dir: @dir)
    eventually(20, "the relay did not start to wait") { File.read(log).include?("waiting for consumers") }
    started = now
    Process.kill("TERM", pid)
    status = exited(pid)

    assert_equal 1, status.exitstatus
    assert_operator now - started, :<, 3
    assert_includes File.read(log), "stopped while waiting for consumers; 10 records of the batch were not written"
  end

  private

  def consumer_params(queue, output) = ["--url", target.url, "--queue", queue, "--output", output]

end

Integration.define("Consumers", ConsumersTests)
