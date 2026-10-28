# frozen_string_literal: true

require "monitor"

# An in-memory stand-in for RedisClient with the commands metacrunch-redis sends. Thread-safe, so a test can push
# entries while a reader waits in BLMPOP, which waits for real (up to its timeout). fail_next makes the next calls of
# a command raise; commands logs what was sent.
class FakeRedis

  WRONGTYPE = "WRONGTYPE Operation against a key holding the wrong kind of value"

  # Collects the commands of a pipelined block.
  class Pipeline

    attr_reader :commands

    def initialize
      @commands = []
    end

    def call(*command) = @commands << command

  end

  attr_reader :lists, :strings, :expiries, :blocking_timeouts
  attr_accessor :hello, :info_memory, :scan_page

  def initialize
    @lock = Monitor.new
    @pushed = @lock.new_cond
    @lists = {}
    @strings = {}
    @expiries = {}
    @log = []
    @failures = []
    @blocking_timeouts = []
    @hello = {"server" => "redis", "version" => "8.10.3", "mode" => "standalone", "role" => "master"}
    @info_memory = "# Memory\r\nmaxmemory:0\r\nmaxmemory_policy:noeviction\r\n"
    @scan_page = 10
    @closed = false
  end

  # The next times calls of command (any command without on:) raise error, after the first after calls.
  def fail_next(error, on: nil, times: 1, after: 0)
    @lock.synchronize { times.times { @failures << {on:, error:, after:} } }
  end

  # Entries pushed by the test, as another program would.
  def push(key, *values) = execute(["RPUSH", key, *values], log: false)

  def commands = @lock.synchronize { @log.dup }

  # The names of the commands sent, e.g. ["HELLO", "TYPE", "RPUSH"].
  def names = commands.map(&:first)

  def call(*command) = execute(command)

  def call_once(*command) = execute([*command, :once])

  def blocking_call(timeout, *command)
    @lock.synchronize { @blocking_timeouts << timeout }
    execute(command)
  end

  def pipelined(exception: true)
    pipeline = Pipeline.new
    yield pipeline
    results = pipeline.commands.map do |command|
      execute(command)
    rescue RedisClient::Error => e
      e
    end
    error = results.find { it.is_a?(RedisClient::Error) }
    raise error if error && exception

    results
  end

  def close = @closed = true

  def closed? = @closed

  private

  def execute(command, log: true)
    @lock.synchronize do
      once = command.last == :once
      command = command[0...-1] if once
      name = command.first.to_s.upcase
      @log << (once ? [name, *command.drop(1), :once] : [name, *command.drop(1)]) if log
      @closed = false
      fail_if_asked(name)
      dispatch(name, command.drop(1))
    end
  end

  def fail_if_asked(name)
    index = @failures.index { it[:on].nil? || it[:on] == name }
    return unless index
    return @failures[index][:after] -= 1 if @failures[index][:after].positive?

    raise @failures.delete_at(index)[:error]
  end

  def dispatch(name, args)
    case name
    when "HELLO" then @hello
    when "TYPE" then type(args.first)
    when "INFO" then @info_memory
    when "RPUSH" then list(args.first).concat(args.drop(1)).size.tap { @pushed.broadcast }
    when "LPUSH" then args.drop(1).each { list(args.first).unshift(it) }.then { list(args.first).size }
    when "LPOP" then lpop(args.first, args[1])
    when "LLEN" then @lists.fetch(args.first, []).size.tap { list?(args.first) }
    when "BLMPOP" then blmpop(args)
    when "SET" then set(args)
    when "DEL" then args.count { @strings.delete(it) || @lists.delete(it) }
    when "SCAN" then scan(args)
    when "MGET" then args.map { @strings[it] }
    else raise ArgumentError, "FakeRedis does not know #{name}"
    end
  end

  def type(key)
    return "list" if @lists.key?(key)
    return "string" if @strings.key?(key)

    "none"
  end

  def list?(key)
    raise RedisClient::WrongTypeError.new(WRONGTYPE, "WRONGTYPE") if @strings.key?(key)
  end

  def list(key)
    list?(key)
    @lists[key] ||= []
  end

  # Redis deletes a list that becomes empty.
  def lpop(key, count)
    list?(key)
    entries = @lists[key]
    return nil if entries.nil? || entries.empty?

    taken = count ? entries.shift(Integer(count)) : entries.shift
    @lists.delete(key) if entries.empty?
    taken
  end

  # BLMPOP timeout 1 key LEFT COUNT n
  def blmpop(args)
    timeout = Float(args[0])
    key = args[2]
    count = Integer(args[5])
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while @lists.fetch(key, []).empty?
      left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return nil unless left.positive?

      @pushed.wait(left)
    end
    [key, lpop(key, count)]
  end

  def set(args)
    key, value, *options = args
    @lists.delete(key)
    @strings[key] = value
    options.empty? ? @expiries.delete(key) : @expiries[key] = Integer(options.last)
    "OK"
  end

  # SCAN cursor MATCH pattern COUNT n TYPE string, @scan_page keys per call.
  def scan(args)
    cursor = Integer(args[0])
    pattern = args[args.index("MATCH") + 1]
    keys = @strings.keys.sort
    page = keys[cursor, @scan_page] || []
    following = cursor + @scan_page
    [following >= keys.size ? "0" : following.to_s, page.select { File.fnmatch?(pattern, it, File::FNM_DOTMATCH) }]
  end

end

# A connection whose connect returns one FakeRedis, or raises error.
class FakeConnection

  attr_reader :redis, :connects

  def initialize(redis = FakeRedis.new, error: nil)
    @redis = redis
    @error = error
    @connects = 0
  end

  def connect
    raise @error if @error

    @connects += 1
    @redis
  end

  def url = "redis://fake:6379/0"

  def inspect = "#<FakeConnection>"

end
