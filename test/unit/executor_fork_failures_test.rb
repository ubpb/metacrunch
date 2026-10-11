# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ExecutorForkFailuresTest < Minitest::Test

  include PipelineHelper
  include ForkVariant::NoWorkerLeft

  # Marshal cannot dump it: it holds an IO.
  class HoldsIO < StandardError

    def initialize(message = "holds an IO")
      super
      @io = $stderr
    end

  end

  # Logs like a Logger but is none, so workers cannot redirect it.
  class ForeignLogger

    def initialize(io)
      @io = io
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) { |message = nil, &block| @io.puts("#{level} #{message || block.call}") }
      define_method(:"#{level}?") { true }
    end

  end

  # Raises a second signal when the worker asks for its number, like SIGTERM
  # from the parent arriving while a worker ends by SIGINT.
  class DoubleSignal < SignalException

    def initialize = super("INT")

    def signo = raise(SignalException, "TERM")

  end

  # Requires a library only when it is read, after the workers started.
  class LazySource

    def initialize(path, name)
      @path = path
      @name = name
    end

    def each
      require @path
      yield Object.const_get(@name).new(1)
    end

  end

  # Opens slowly, like a connection that hangs.
  class SlowOpen

    def open(_context) = sleep(30)

    def call(record) = record

  end

  def executor = Metacrunch::Executor::Fork.new(workers: 2, batch_size: 3, stop_timeout: 0.3)

  def test_a_worker_killed_in_a_step_aborts_the_run
    result = run_pipeline do
      source [1, 2, 3]
      map { it == 2 ? Process.kill("KILL", Process.pid) : it }
    end

    assert_equal :aborted, result.status
    assert_match(/\Aworker 1 \(pid \d+\) ended unexpectedly \(killed by SIGKILL\)\z/, result.error.message)
  end

  def test_a_worker_that_ends_without_a_frame_aborts_the_run
    result = run_pipeline do
      source [1]
      map { Process.exit!(3) }
    end

    assert_match(/ended unexpectedly \(exit status 3\)\z/, result.error.message)
  end

  def test_a_crash_by_sigabrt_points_to_the_objc_variable_on_macos
    result = run_pipeline do
      source [1]
      map { Process.kill("ABRT", Process.pid) }
    end
    hint = result.error.message.include?("OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES")

    assert_equal RUBY_PLATFORM.include?("darwin"), hint
  end

  def test_a_source_record_that_cannot_be_dumped_aborts_after_the_records_before_it
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, -> {}, 4]
      sink target
    end

    assert_equal [:aborted, [1, 2]], [result.status, target.records]
    assert_match(/\Arecord at position 3 cannot be sent to a worker: no _dump_data is defined for class Proc; /,
                 result.error.message)
  end

  def test_a_step_output_that_cannot_be_dumped_aborts_the_run
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map { it == 2 ? -> {} : it }
      sink target
    end

    assert_equal [:aborted, [1]], [result.status, target.records]
    assert_match(/\Arecord at position 2 cannot be sent from a worker: /, result.error.message)
  end

  def test_a_mark_value_that_cannot_be_dumped_aborts_the_run
    result = run_pipeline do
      source [1]
      map do |record, ctx|
        ctx.mark("Stream", value: $stderr)
        record
      end
      sink CollectingSink.new
    end

    assert_match(/\Arecord at position 1 cannot be sent from a worker: can't dump IO/, result.error.message)
  end

  def test_failures_with_exceptions_that_cannot_be_dumped_reach_the_errors_sink
    failed = CollectingSink.new
    result = run_pipeline do
      source [1]
      map { raise HoldsIO }
      errors failed
      on_error :skip
    end
    error = failed.contexts.first.failure.error

    assert_equal ["ExecutorForkFailuresTest::HoldsIO", "holds an IO"], [error.original_class, error.original_message]
    assert_equal({"ExecutorForkFailuresTest::HoldsIO" => 1}, result.stats.failed)
  end

  def test_aborts_with_exceptions_that_cannot_be_dumped_keep_the_step_error
    result = run_pipeline do
      source [1]
      map(name: "lookup") { raise HoldsIO }
    end

    assert_equal "step lookup failed at position 1: ExecutorForkFailuresTest::HoldsIO: holds an IO",
                 result.error.message
    assert_instance_of Metacrunch::WorkerError, result.error.cause
  end

  def test_a_worker_that_ignores_sigterm_is_killed_after_the_stop_timeout
    started = now
    result = run_pipeline do
      source [1, 2, 3, 4]
      map do |record|
        raise "boom" if record == 1

        Signal.trap("TERM", "IGNORE")
        sleep(30)
        record
      end
    end

    assert_equal [:aborted, 1], [result.status, result.error.position]
    assert_operator now - started, :<, 5
  end

  def test_a_logger_that_is_no_logger_gets_lines_straight_from_the_workers
    Dir.mktmpdir do |dir|
      path = File.join(dir, "log")
      File.open(path, "a") do |file|
        file.sync = true
        result = run_pipeline(logger: ForeignLogger.new(file)) do
          source [1, 2]
          map { it == 2 ? raise("bad") : it }
          on_error :skip
        end

        assert_equal :ok_with_failures, result.status
      end

      assert_match(/^error \[#2\] step map#1 failed at position 2/, File.read(path))
    end
  end

  def test_a_second_signal_while_a_worker_ends_runs_no_inherited_at_exit_handler
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "at_exit")
      parent = Process.pid
      pipeline = build_pipeline do
        source [1]
        before { at_exit { File.write(marker, "ran") unless Process.pid == parent } }
        map { raise DoubleSignal }
      end
      run_ignoring_signals(pipeline)

      refute_path_exists marker
    end
  end

  def test_workers_do_not_run_signal_handlers_of_the_host
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "trap")
      previous = Signal.trap("TERM") { File.write(marker, "the host's handler ran") }
      begin
        run_pipeline do
          source [1, 2, 3, 4]
          map do |record|
            raise "boom" if record == 1

            sleep(2)
            record
          end
        end
      ensure
        Signal.trap("TERM", previous)
      end

      refute_path_exists marker
    end
  end

  def test_a_class_loaded_only_in_a_worker_gives_a_clear_error
    Dir.mktmpdir do |dir|
      name = "LoadedInAWorker#{Process.pid}"
      path = File.join(dir, "lazy.rb")
      File.write(path, "#{name} = Struct.new(:n)\n")
      result = run_pipeline do
        source [1]
        map do |record|
          require path
          Object.const_get(name).new(record)
        end
        sink CollectingSink.new
      end

      assert_match(/\Aworker 1 sent an object of a class this process does not know \(.*#{name}\); /,
                   result.error.message)
    end
  end

  def test_a_class_loaded_by_the_source_after_the_workers_started_gives_a_clear_error
    Dir.mktmpdir do |dir|
      name = "LoadedBySource#{Process.pid}"
      path = File.join(dir, "lazy.rb")
      File.write(path, "#{name} = Struct.new(:n)\n")
      result = run_pipeline { source LazySource.new(path, name) }

      assert_match(/\Arecord at position 1 cannot be read in a worker \(.*#{name}\); /, result.error.message)
    end
  end

  def test_sigint_to_the_parent_while_workers_open_their_steps
    pipeline = build_pipeline do
      source [1]
      map SlowOpen.new
    end
    signal = Thread.new do
      sleep(0.5)
      Process.kill("INT", Process.pid)
    end
    started = now

    assert_raises(Interrupt) { engine(pipeline).run }
    assert_operator now - started, :<, 5
  ensure
    signal&.join
  end

  private

  def run_ignoring_signals(pipeline)
    engine(pipeline).run
  rescue SignalException
    nil
  end

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

end
