# frozen_string_literal: true

require "test_helper"

# A producer against a Redis that is full: TEST_REDIS_MEMORY_URL names a server of its own (see test/compose.yml),
# whose maxmemory the test sets, since that holds for the whole server. Runs from parallel worktrees take turns
# through a lock key.
class MemoryTest < Minitest::Test

  ENTRIES = 3000
  ENTRY = "x" * 10_000
  LOCK = "metacrunch-test:memory-lock"

  def setup
    url = ENV.fetch("TEST_REDIS_MEMORY_URL", "")
    skip "needs a server of its own: set TEST_REDIS_MEMORY_URL (see test/compose.yml)" if url.empty?

    @connection = Metacrunch::Redis::Connection.new(url:)
    @queue = "metacrunch-test:#{SecureRandom.hex(4)}:books"
    @redis = @connection.connect
    lock
    @redis.call("CONFIG", "SET", "maxmemory", "16mb", "maxmemory-policy", "noeviction")
  end

  def teardown
    return unless @redis

    @redis.call("DEL", @queue)
    @redis.call("CONFIG", "SET", "maxmemory", "0")
    @redis.call("DEL", LOCK) if @redis.call("GET", LOCK) == @token
    @redis.close
  end

  def test_the_writer_waits_while_redis_is_full_and_every_entry_arrives_once
    taken = []
    consumer = Thread.new do
      sleep(1)
      @connection.connect do |redis|
        while taken.size < ENTRIES
          entries = redis.call("LPOP", @queue, 100)
          entries ? taken.concat(entries) : sleep(0.01)
        end
      end
    end
    log = StringIO.new
    writer = Metacrunch::Redis::QueueWriter.new(@connection, queue: @queue, format: :string, pause: 0.05)
    writer.open(Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log)))
    ENTRIES.times.each_slice(100) { |slice| writer.write_batch(slice.map { "#{it}:#{ENTRY}" }) }
    consumer.join(30)

    assert_equal((0...ENTRIES).to_a, taken.map(&:to_i))
    assert_match(/Redis is full \(maxmemory\); waiting for consumers to take entries/, log.string)
    assert_match(/going on after \d+ s/, log.string)
  ensure
    writer&.close
  end

  private

  # Waits up to two minutes for the lock; it expires by itself after two minutes, should a run die.
  def lock
    @token = SecureRandom.hex(8)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
    until @redis.call("SET", LOCK, @token, "NX", "EX", 120)
      flunk("another run held #{LOCK} for two minutes") if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep(0.5)
    end
  end

end
