# metacrunch-ng parallel executor (sub-project 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the steps of any job in forked worker processes (`metacrunch run -w N`), with the same results as inline, in source order.

**Architecture:** The step chain moves from `Engine` into a `Processor` that hands what leaves the chain to an *outlet*. `SinkOutlet` writes to the sinks and enforces `max_errors`. `Executor::Inline` runs one processor in-process. `Executor::Fork` forks N workers after the `before` hooks. Each worker runs a processor whose `BatchOutlet` collects events. A feeder thread in the parent sends batch k to worker k mod N. The main thread reads the results in the same order and applies them through the `SinkOutlet`. Frames are length-prefixed Marshal dumps over two pipes per worker.

**Tech Stack:** Ruby 4.0, standard library and default gems (`etc`, `logger`), Minitest 6, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** `docs/superpowers/specs/2026-10-11-metacrunch-ng-parallel-executor-design.md` (builds on the specs of sub-projects 1 and 2 in the same directory)

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version stays `5.0.0.pre`.
- Runtime dependency: `logger` only. No new gems; standard library and default gems only.
- Library files are loaded with `require_relative` from `lib/metacrunch.rb`.
- Every Ruby file starts with `# frozen_string_literal: true` (also benchmarks and test fixtures).
- The library never calls `exit`. The only exception is `Executor::Fork::Worker.main`: in the forked child it ends with `Process.exit!` or by a signal, never by `exit`, so inherited `at_exit` handlers and write buffers do not run twice.
- Commands never use `$stdin`, `$stdout` or `$stderr` directly; they use the streams injected into `Metacrunch::Cli`.
- Inline runs keep their cost. `bundle exec ruby -Ilib bench/executor.rb inline` stays within 5 % of the baseline measured in Task 1 (about 64 ns per step and record, 4.0 allocations per record).
- Fork tests leave no child process behind (`ForkVariant::NoWorkerLeft`, Task 5).
- Minitest 6 has no `stub`; tests replace singleton methods with `Override#override` (Task 5).
- Lint: `bundle exec rubocop` is clean at the end of every task (`bundle exec rubocop -a` may fix layout). Metrics cops are disabled by ruby.yml.
- Style that ruby.yml enforces:
  - double quotes, also inside interpolation;
  - `{a: 1}` without spaces inside the braces;
  - `[:a, :b]` and `["a", "b"]` instead of `%i[]` and `%w[]`;
  - blank lines at the start and end of class and module bodies, except for pure namespaces;
  - lines of at most 120 characters;
  - at most 3 assertions per Minitest test, and a blank line before the first assertion;
  - `rescue Exception` only with `# rubocop:disable Lint/RescueException` on that line.
- Tests:
  - Single file: `bundle exec ruby -w -Ilib -Itest <file>`.
  - Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake`.
- Repo docs, code comments and commit messages are in English.
- Every commit message ends with these two lines:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
  ```

## Review Focus

These are inputs and conditions the spec implies but does not spell out, ordered by how likely they are to bite a user first. Each one has a test in the task named in brackets.

1. **Records larger than a pipe buffer** (a 1 MB XML string per record), in both directions: no deadlock, and the records arrive whole. [Task 5]
2. **An empty source, and fewer batches than workers** (a test file with three records, `-w 8`): the run ends normally. [Task 5]
3. **Non-ASCII and binary Strings in records** (`"Müller"`, `"\xFF".b`): they arrive with the same bytes and encoding. [Task 5]
4. **A logger that is not a `::Logger`** (a job passes its own logger object to `Job#run`): the run works, and the workers write to it directly. [Task 6]
5. **SIGINT to the parent while the workers still open their steps** (a slow `open`, e.g. a connection that hangs): the run ends promptly with `Interrupt`, and no worker is left. [Task 6]

---

## File Structure

```
lib/metacrunch.rb                         requires                                        Tasks 1, 3, 4, 5, 7
lib/metacrunch/components.rb              OpenContext, Components.open/close              Task 1
lib/metacrunch/sink_outlet.rb             SinkOutlet                                      Task 1
lib/metacrunch/processor.rb               Processor (chain, contexts, error policy)       Task 1
lib/metacrunch/executor/inline.rb         Inline.each_record, #workers, #run              Task 1
lib/metacrunch/engine.rb                  lifecycle only; observer check; LiveStats       Tasks 1, 5, 7
lib/metacrunch/context.rb                 Context::State, to_state, from_state            Task 2
lib/metacrunch/stats_collector.rb         take, absorb                                    Task 2
lib/metacrunch/errors.rb                  WorkerError                                     Task 3
lib/metacrunch/json_lines.rb              ContextWriter writes WorkerError as original    Task 3
lib/metacrunch/executor/fork/frame.rb     Fork::Frame                                     Task 3
lib/metacrunch/executor/fork/dump.rb      Fork::Dump                                      Task 3
lib/metacrunch/executor/fork/worker.rb    Fork::Worker, BatchOutlet, LogBuffer            Task 4
lib/metacrunch/executor/fork.rb           Fork (options, supported?)                      Task 5
lib/metacrunch/executor/fork/run.rb       Fork::Run (pool, feeder, ordered apply, stop)   Tasks 5, 6
lib/metacrunch/executor.rb                Executor.for, Executor.auto_workers             Task 7
lib/metacrunch/job.rb                     Job#run(workers:)                               Task 7
lib/metacrunch/testing.rb                 Testing.run(workers:)                           Task 7
lib/metacrunch/live_stats.rb              workers                                         Task 7
lib/metacrunch/progress.rb                "N workers" in the line                         Task 7
lib/metacrunch/cli/run.rb                 -w, --workers                                   Task 7
bench/executor.rb                         measurements                                    Tasks 1, 8
test/support/pipeline_helper.rb           executor, engine                                Task 5
test/support/fork_variant.rb              ForkVariant, NoWorkerLeft                       Task 5
test/support/override.rb                  Override#override                               Task 5
test/unit/processor_test.rb, sink_outlet_test.rb                                          Task 1
test/unit/executor_fork_frame_test.rb, executor_fork_dump_test.rb                         Task 3
test/unit/executor_fork_worker_test.rb                                                    Task 4
test/unit/executor_fork_test.rb                                                           Task 5
test/unit/executor_fork_failures_test.rb                                                  Task 6
test/unit/executor_test.rb                                                                Task 7
test/unit/engine_*_test.rb                fork variants (parity suite)                    Task 5
test/fixtures/jobs/sanitize.rb, test/cli/exe_workers_test.rb                              Task 8
Readme.md, CHANGELOG.md, spec §11                                                         Task 8
```

---

### Task 1: Processor, SinkOutlet and the executor seam

Moves the step chain out of `Engine` without changing inline behaviour, except that steps are now opened after the `before` hooks.

**Files:**
- Create: `bench/executor.rb`, `lib/metacrunch/components.rb`, `lib/metacrunch/sink_outlet.rb`, `lib/metacrunch/processor.rb`
- Modify: `lib/metacrunch/engine.rb` (rewrite), `lib/metacrunch/executor/inline.rb` (rewrite), `lib/metacrunch.rb`, `test/unit/engine_lifecycle_test.rb`
- Test: `test/unit/processor_test.rb`, `test/unit/sink_outlet_test.rb`

**Interfaces:**
- Consumes: `Pipeline`, `StatsCollector`, `Context`, `SinkAdapter`, `Step` (unchanged).
- Produces:
  - `Metacrunch::OpenContext` (moved from engine.rb to components.rb, unchanged).
  - `Metacrunch::Components.open(components, context, opened)` and `Components.close(opened, logger)`. `close` returns the first error or `nil`, and re-raises a signal after closing everything.
  - `Metacrunch::Processor.new(pipeline, stats:, outlet:, observer: nil)` with `#open`, `#close` (returns error or `nil`, idempotent) and `#call(record, position)`.
  - The outlet protocol: `deliver(record, ctx)`, `reject(record, ctx)`, `fail(record, ctx)`.
  - `Metacrunch::SinkOutlet.new(pipeline)`.
  - `Executor::Inline.each_record(source, limit: nil, select: nil) { |record, position| }`, `Inline#workers` (always `1`) and `Inline#run(pipeline, stats:, outlet:, observer: nil, select: nil)`.
  - `Engine.new(pipeline, executor:, observer:, monitor:, select:)` keeps its signature.

- [ ] **Step 1: Write the benchmark and measure the baseline on the current code**

Create `bench/executor.rb`:

```ruby
# frozen_string_literal: true

# Measures the engine and its executors; not part of the test suite.
#
#   bundle exec ruby -Ilib bench/executor.rb inline
#
# inline: 1 M records through 10 map steps, without sink, observer or
# monitor: time per step and record (best of three runs) and allocations
# per record.

require "metacrunch"

module Bench

  module_function

  def build(&recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash({}) }, logger: Logger.new(nil))
    builder.instance_exec(&recipe)
    builder.build
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def inline
    records = Array.new(1_000_000) { it }
    pipeline = build do
      source records
      10.times { map { it } }
    end
    run = -> { Metacrunch::Engine.new(pipeline).run }
    run.call
    best = Array.new(3) { seconds(&run) }.min
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    run.call
    allocations = GC.stat(:total_allocated_objects) - allocated
    format("inline: %<ns>.1f ns per step and record, %<allocations>.1f allocations per record",
           ns: best * 1e9 / (records.size * 10), allocations: allocations.fdiv(records.size))
  end

end

puts Bench.public_send(ARGV.fetch(0, "inline"))
```

Run it twice and keep the better line in the ledger as the baseline: `bundle exec ruby -Ilib bench/executor.rb inline`
Expected: about `inline: 64 ns per step and record, 4.0 allocations per record`.

- [ ] **Step 2: Write the failing tests**

Create `test/unit/processor_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProcessorTest < Minitest::Test

  include PipelineHelper

  # Notes what leaves the chain.
  class RecordingOutlet

    attr_reader :events

    def initialize
      @events = []
    end

    def deliver(record, ctx) = @events << [:deliver, record, ctx.position]

    def reject(record, ctx) = @events << [:reject, record, ctx.rejection.reason]

    def fail(record, ctx) = @events << [:fail, record, ctx.failure.step]

  end

  # A step callable that notes open and close.
  class Lifecycle

    attr_reader :log

    def initialize
      @log = []
    end

    def open(_context) = @log << :open

    def close = @log << :close

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  def test_hands_what_leaves_the_chain_to_the_outlet
    outlet = RecordingOutlet.new
    processor = build_processor(outlet) do
      map { it == 2 ? raise(ArgumentError, "bad") : it }
      reject("Three") { it == 3 }
      on_error :skip
    end
    [1, 2, 3].each { processor.call(it, it) }

    assert_equal [[:deliver, 1, 1], [:fail, 2, "map#1"], [:reject, 3, "Three"]], outlet.events
  end

  def test_counts_in_the_given_stats
    stats = Metacrunch::StatsCollector.new(["filter#1"])
    processor = build_processor(RecordingOutlet.new, stats:) { filter(&:odd?) }
    processor.call(1, 1)
    processor.call(2, 2)

    assert_equal [2, 1], [stats.read, stats.filtered_total]
  end

  def test_opens_and_closes_each_step_callable_once
    step = Lifecycle.new
    processor = build_processor(RecordingOutlet.new) do
      map step
      map step
    end
    processor.open
    2.times { processor.close }

    assert_equal [:open, :close], step.log
  end

  def test_close_returns_the_first_error
    processor = build_processor(RecordingOutlet.new) { map FailingClose.new }
    processor.open

    assert_equal "close broke", processor.close.message
  end

  private

  def build_processor(outlet, stats: nil, &)
    pipeline = build_pipeline(&)
    stats ||= Metacrunch::StatsCollector.new(pipeline.steps.map(&:name))
    Metacrunch::Processor.new(pipeline, stats:, outlet:)
  end

end
```

Create `test/unit/sink_outlet_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SinkOutletTest < Minitest::Test

  include PipelineHelper

  def test_writes_each_kind_to_its_sink
    target = CollectingSink.new
    rejected = CollectingSink.new
    failed = CollectingSink.new
    outlet = Metacrunch::SinkOutlet.new(build_pipeline do
      sink target
      rejects rejected
      errors failed
    end)
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))
    outlet.fail(3, failed_context(3))

    assert_equal [[1], [2], [3]], [target.records, rejected.records, failed.records]
  end

  def test_records_without_a_sink_are_dropped
    outlet = Metacrunch::SinkOutlet.new(build_pipeline { map { it } })
    outlet.deliver(1, context(1))
    outlet.reject(2, context(2))

    assert_nil outlet.fail(3, failed_context(3))
  end

  def test_failures_over_max_errors_raise_with_the_step_error_as_cause
    outlet = Metacrunch::SinkOutlet.new(build_pipeline { on_error :skip, max_errors: 1 })
    outlet.fail(1, failed_context(1))
    error = assert_raises(Metacrunch::Error) { outlet.fail(2, failed_context(2)) }

    assert_equal "2 failed records exceed max_errors 1", error.message
    assert_equal ["map#1", 2], [error.cause.step, error.cause.position]
  end

  private

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: PipelineHelper::SILENT_LOGGER)
  end

  def failed_context(position)
    context(position).tap { it.failure = Metacrunch::Failure.new(error: ArgumentError.new("bad"), step: "map#1") }
  end

end
```

In `test/unit/engine_lifecycle_test.rb`, replace `test_opens_components_in_order_and_closes_them_in_reverse` with these two tests:

```ruby
  def test_opens_source_and_sinks_then_steps_and_closes_in_reverse
    log = []
    run_pipeline do
      source Component.new("source", log)
      map Component.new("step", log)
      sink Component.new("sink", log)
      rejects Component.new("rejects", log)
    end
    expected = ["open source", "open sink", "open rejects", "open step",
                "close step", "close rejects", "close sink", "close source"]

    assert_equal expected, log
  end

  def test_steps_open_after_the_before_hooks
    log = []
    run_pipeline do
      source Component.new("source", log)
      map Component.new("step", log)
      before { log << "before" }
    end

    assert_equal ["open source", "before", "open step", "close step", "close source"], log
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/processor_test.rb test/unit/sink_outlet_test.rb test/unit/engine_lifecycle_test.rb`
Expected: errors `uninitialized constant Metacrunch::Processor` and `Metacrunch::SinkOutlet`. The two lifecycle tests fail, because `open step` comes right after `open source`.

- [ ] **Step 4: Write `lib/metacrunch/components.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch

  # Passed to open(context) of sources, steps and sinks.
  OpenContext = Data.define(:params, :logger)

  # Opens and closes components: sources, step callables and sinks.
  module Components

    module_function

    # Opens the components in order. Each one is appended to opened once it
    # is open, so after a failed open, opened holds what has to be closed.
    def open(components, context, opened)
      components.each do |component|
        component.open(context) if component.respond_to?(:open)
        opened << component
      end
    end

    # Closes the opened components in reverse order and returns the first
    # error, after trying to close all of them. A signal raised while
    # closing (e.g. SIGPIPE from a writer whose reader went away) is raised
    # again once everything is closed.
    def close(opened, logger)
      first_error = nil
      signal = nil
      opened.reverse_each do |component|
        component.close if component.respond_to?(:close)
      rescue *Engine::RECOVERABLE => e
        logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      rescue SignalException => e
        signal ||= e
      end
      raise signal if signal

      first_error
    end

  end

end
```

- [ ] **Step 5: Write `lib/metacrunch/sink_outlet.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  # Writes the records that leave the chain of steps to the pipeline's
  # sinks: delivered ones to the sink, rejected ones to rejects and failed
  # ones to errors. Enforces max_errors, so a run stops at the same record
  # whether its steps run inline or in workers.
  class SinkOutlet

    def initialize(pipeline)
      @sink = pipeline.sink
      @rejects = pipeline.rejects
      @errors = pipeline.errors
      @max_errors = pipeline.max_errors
      @failed = 0
    end

    def deliver(record, ctx)
      @sink&.write(record, ctx)
    end

    def reject(record, ctx)
      @rejects&.write(record, ctx)
    end

    # ctx.failure is set. Raises Error once the failed records exceed
    # max_errors, with the StepError of this record as the cause.
    def fail(record, ctx)
      @errors&.write(record, ctx)
      @failed += 1
      return unless @max_errors && @failed > @max_errors

      failure = ctx.failure
      step_error = StepError.new(step: failure.step, record_id: ctx.id, position: ctx.position, error: failure.error)
      raise Error, "#{@failed} failed records exceed max_errors #{@max_errors}", cause: step_error
    end

  end
end
```

- [ ] **Step 6: Write `lib/metacrunch/processor.rb`**

The chain code comes from `engine.rb` unchanged, except for three spots: the end of the chain is the outlet's `deliver`, rejected records go to `outlet.reject`, and failed ones go to `outlet.fail`, which now enforces `max_errors`.

```ruby
# frozen_string_literal: true

module Metacrunch
  # Pushes source records through the steps of a pipeline: builds the chain
  # of steps, creates the per-record contexts and applies the error policy.
  # Records that leave the chain go to an outlet, which has three methods:
  # deliver(record, ctx), reject(record, ctx) and fail(record, ctx).
  # Executors run one Processor per process.
  class Processor

    # Returned by map/filter/reject evaluation when the record goes no further.
    DROPPED = Object.new.freeze

    # Wraps errors from later steps and sinks while a flat_map streams its
    # children, so they are not counted as failures of the flat_map step.
    # It inherits from Exception on purpose: the flat_map's Enumerable runs
    # user code around each yield, and a `rescue => e` there must not be
    # able to swallow these errors.
    class DownstreamFailure < Exception # rubocop:disable Lint/InheritException

      attr_reader :original

      def initialize(original)
        @original = original
        super(original.message)
      end

    end

    # stats: the StatsCollector to count in. observer: optional; receives
    # step_in(step, record, ctx) and step_out(step, outputs, ctx).
    def initialize(pipeline, stats:, outlet:, observer: nil)
      @pipeline = pipeline
      @stats = stats
      @outlet = outlet
      @observer = observer
      @on_mark = stats.method(:mark)
      @opened = []
      @chain = build_chain
    end

    # Opens the step callables, each object once, in step order.
    def open
      context = OpenContext.new(params: @pipeline.params, logger: @pipeline.logger)
      Components.open(@pipeline.steps.map(&:callable).uniq(&:__id__), context, @opened)
    end

    # Closes the opened step callables in reverse order and returns the
    # first error (see Components.close). A second call closes nothing.
    def close
      opened = @opened
      @opened = []
      Components.close(opened, @pipeline.logger)
    end

    # Pushes one source record through the chain. position: its 1-based
    # number in the source.
    def call(record, position)
      @stats.count_read
      return fail_invalid(record, position) if record.is_a?(InvalidRecord)

      id = @pipeline.id_extractor&.call(record)
      @chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    private

    # A record the source could not read fails as the pseudo-step "source".
    # The observer sees it like a step without output.
    def fail_invalid(invalid, position)
      ctx = Context.new(id: nil, position:, logger: @pipeline.logger, on_mark: @on_mark)
      ctx.step = SOURCE_STEP
      @observer&.step_in(SOURCE_STEP, invalid.raw, ctx)
      begin
        @stats.source_failed(invalid.error)
        handle_failure(SOURCE_STEP, invalid.raw, ctx, invalid.error)
      ensure
        @observer&.step_out(SOURCE_STEP, [], ctx)
      end
    end

    def build_chain
      @pipeline.steps.reverse.reduce(@outlet.method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain. Only the step itself is covered by the error
    # policy; errors raised further down (later steps, sinks) pass through.
    def link(step, downstream)
      counter = @stats.counter(step.name)
      step.kind == :flat_map ? flat_map_link(step, counter, downstream) : single_link(step, counter, downstream)
    end

    # map, filter and reject: at most one output, no intermediate Array.
    def single_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        begin
          output = evaluate(step, record, ctx)
        rescue *Engine::RECOVERABLE => e
          next fail_observed(step, record, ctx, e)
        end
        @observer&.step_out(step.name, output.equal?(DROPPED) ? [] : [output], ctx)
        if ctx.rejected?
          reject_record(record, ctx)
        elsif output.equal?(DROPPED)
          counter.filtered += 1
        else
          counter.output += 1
          downstream.call(output, ctx)
        end
      end
    end

    # flat_map: streams each child downstream as the step's Enumerable
    # yields it. Children forwarded before an error in the step's own
    # iteration stay forwarded; a reject! during the iteration stops it.
    # The observer's step_out comes after the children went downstream.
    def flat_map_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        children = @observer ? [] : nil
        begin
          result = timed(step) { step.call(record, ctx) }
          unless ctx.rejected?
            flat_map_contract!(step, result)
            result.each do |child|
              break if ctx.rejected?

              children&.push(child)
              counter.output += 1
              forward_child(downstream, child, ctx)
            end
          end
        rescue DownstreamFailure => e
          raise e.original, cause: e.original.cause
        rescue *Engine::RECOVERABLE => e
          next fail_record(step, record, ctx, e)
        ensure
          @observer&.step_out(step.name, children, ctx)
        end
        reject_record(record, ctx) if ctx.rejected?
      end
    end

    def forward_child(downstream, child, ctx)
      downstream.call(child, ctx.copy)
    rescue *Engine::RECOVERABLE => e
      raise DownstreamFailure, e
    end

    # Calls a map, filter or reject step. Returns the output record or
    # DROPPED. Raises ContractError if the step breaks its contract.
    def evaluate(step, record, ctx)
      result = timed(step) { step.call(record, ctx) }
      return DROPPED if ctx.rejected?

      case step.kind
      when :map then map_result(step, result)
      when :filter then kept(step, record, ctx, result)
      else kept(step, record, ctx, !result)
      end
    end

    def timed(step)
      return yield unless @pipeline.profile

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        yield
      ensure
        @stats.step_time(step.name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end

    def kept(step, record, ctx, keep)
      return record if keep

      ctx.reject!(step.reason) if step.reason
      DROPPED
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_contract!(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      return if result.respond_to?(:each)

      raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @outlet.reject(record, ctx)
    end

    # Applies the error policy first, so the observer sees ctx.failure
    # under :skip.
    def fail_observed(step, record, ctx, error)
      fail_record(step, record, ctx, error)
    ensure
      @observer&.step_out(step.name, [], ctx)
    end

    def fail_record(step, record, ctx, error)
      @stats.step_failed(step.name, error)
      handle_failure(step.name, record, ctx, error)
    end

    # :abort raises the StepError. :skip logs the failure and hands the
    # record to the outlet, which enforces max_errors.
    def handle_failure(name, record, ctx, error)
      step_error = StepError.new(step: name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_error == :abort

      ctx.failure = Failure.new(error:, step: name)
      ctx.logger.error(step_error.message)
      @outlet.fail(record, ctx)
    end

  end
end
```

- [ ] **Step 7: Rewrite `lib/metacrunch/executor/inline.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    # Runs the steps in this process, one record after another, in source
    # order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work. Several values yielded
      # at once become one Array record, as with Enumerable#to_a.
      #
      # select: callable (record, position); only records it accepts are
      # yielded, positions still count every record. limit: stop after this
      # many yielded records; `break` lets the source's ensure blocks run.
      def self.each_record(source, limit: nil, select: nil)
        position = 0
        yielded = 0
        source.each do |*values|
          record = values.size <= 1 ? values.first : values
          position += 1
          next if select && !select.call(record, position)

          yield(record, position)
          break if limit && (yielded += 1) >= limit
        end
      end

      # The number of processes that run steps.
      def workers = 1

      # Opens the step callables, pushes the source records (limit and
      # select applied) through them into the outlet and closes them.
      # Raises the error that stopped the records, else the first error of
      # closing.
      def run(pipeline, stats:, outlet:, observer: nil, select: nil)
        processor = Processor.new(pipeline, stats:, outlet:, observer:)
        begin
          processor.open
          Inline.each_record(pipeline.source, limit: pipeline.limit, select:) do |record, position|
            processor.call(record, position)
          end
        ensure
          close_error = processor.close
        end
        raise close_error if close_error
      end

    end
  end
end
```

- [ ] **Step 8: Rewrite `lib/metacrunch/engine.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  # Runs a Pipeline: opens the source and the sinks, runs the hooks and has
  # the executor push the records through the steps into the sinks. Applies
  # the error policy to the run, collects stats and returns a Result.
  class Engine

    # Errors a step can fail with. Everything else (NoMemoryError, signals,
    # SystemExit) ends the process as usual.
    RECOVERABLE = [StandardError, ScriptError, SystemStackError].freeze

    # executor: Executor::Inline or Executor::Fork. observer: see Processor.
    # monitor: start(LiveStats) and stop. select: see
    # Executor::Inline.each_record.
    def initialize(pipeline, executor: Executor::Inline.new, observer: nil, monitor: nil, select: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
      @monitor = monitor
      @select = select
    end

    def run
      validate!
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      error = monitored { execute }
      @stats.count_written(@pipeline.sink.delivered) if @pipeline.sink
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end

    private

    # Tells the monitor about the run. stop runs in any case, also after an
    # abort or a signal.
    def monitored
      return yield unless @monitor

      @monitor.start(LiveStats.new(@stats, @pipeline))
      begin
        yield
      ensure
        @monitor.stop
      end
    end

    def validate!
      raise ArgumentError, "the pipeline has no source" unless @pipeline.source

      limit = @pipeline.limit
      return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

      raise ArgumentError, "limit must be a positive Integer, got #{limit.inspect}"
    end

    def status_for(error)
      return :aborted if error
      return :ok_with_failures if @stats.failed_total.positive?

      :ok
    end

    # Returns the error that aborted the run, or nil. Buffered records are
    # flushed after an abort and on signals (Ctrl-C, SIGTERM); opened
    # components are closed in any case.
    def execute
      opened = []
      error = nil
      begin
        process(opened)
      rescue *RECOVERABLE => e
        error = e
        flush_after_abort
      rescue SignalException
        flush_after_abort
        raise
      ensure
        close_error = Components.close(opened, @pipeline.logger)
      end
      error || close_error
    end

    # The executor opens and closes the step callables itself (in every
    # worker), after the before hooks.
    def process(opened)
      Components.open(components, OpenContext.new(params: @pipeline.params, logger: @pipeline.logger), opened)
      @pipeline.before_hooks.each(&:call)
      @executor.run(@pipeline, stats: @stats, outlet: SinkOutlet.new(@pipeline), observer: @observer, select: @select)
      sinks.each(&:flush)
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.errors].compact
    end

    # Writes what the sinks have buffered, so batch: does not change which
    # records reach a sink when a run stops early. Flush errors are logged;
    # the error that aborted the run stays the run's error.
    def flush_after_abort
      sinks.each do |sink|
        sink.flush
      rescue *RECOVERABLE => e
        @pipeline.logger.error("flushing #{sink.sink.class} after abort failed: #{e.class}: #{e.message}")
      end
    end

    # Source and sinks, in open order. A SinkAdapter stands for its sink, so
    # one object used as sink and rejects opens once.
    def components
      [@pipeline.source, *sinks].uniq do |component|
        component.is_a?(SinkAdapter) ? component.sink.__id__ : component.__id__
      end
    end

    def run_after_hooks(result)
      @pipeline.after_hooks.each do |hook|
        hook.call(result)
      rescue *RECOVERABLE => e
        @pipeline.logger.error("after hook failed: #{e.class}: #{e.message}")
        result = result.with(status: :aborted, error: result.error || e)
      end
      result
    end

  end
end
```

- [ ] **Step 9: Require the new files**

In `lib/metacrunch.rb`, insert after `require_relative "metacrunch/sink_adapter"`:

```ruby
require_relative "metacrunch/components"
require_relative "metacrunch/sink_outlet"
require_relative "metacrunch/processor"
```

- [ ] **Step 10: Run the new tests, then the whole suite**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/processor_test.rb test/unit/sink_outlet_test.rb test/unit/engine_lifecycle_test.rb`
Expected: PASS.

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 11: Measure again**

Run: `bundle exec ruby -Ilib bench/executor.rb inline` (twice, keep the better line).
Expected: within 5 % of the Step 1 baseline, with the same allocations per record. If it is slower, compare the per-record path with the old `Engine#ingest`. `Processor#call` must do the same work: one `count_read`, one `is_a?`, one `Context.new` and the chain.

- [ ] **Step 12: Commit**

```bash
git add bench/executor.rb lib/metacrunch.rb lib/metacrunch/components.rb lib/metacrunch/sink_outlet.rb \
  lib/metacrunch/processor.rb lib/metacrunch/engine.rb lib/metacrunch/executor/inline.rb \
  test/unit/processor_test.rb test/unit/sink_outlet_test.rb test/unit/engine_lifecycle_test.rb
git commit -m "Move the step chain into a Processor and let executors open the steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 2: Context state and stats deltas

**Files:**
- Modify: `lib/metacrunch/context.rb`, `lib/metacrunch/stats_collector.rb`
- Test: `test/unit/context_test.rb`, `test/unit/stats_collector_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Metacrunch::Context::State`, a `Data` with `id`, `position`, `step`, `marks`, `store`, `rejection` and `failure`.
  - `Context#to_state` returns a `State`; `Context.from_state(state, logger:)` returns a `Context`.
  - `Context.new` gains the keyword `rejection: nil`.
  - `StatsCollector#take` returns `Stats` and zeroes the counters, keeping the counter objects.
  - `StatsCollector#absorb(stats)` adds a `Stats`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/context_test.rb` (before `private`):

```ruby
  def test_a_state_rebuilds_the_context_with_another_logger
    ctx = build_context
    ctx.step = "map#1"
    ctx.mark("Odd", value: 1)
    ctx.store["seen"] = true
    ctx.reject!("Bad")
    ctx.failure = Metacrunch::Failure.new(error: ArgumentError.new("x"), step: "map#1")
    io = StringIO.new
    state = Marshal.load(Marshal.dump(ctx.to_state))
    copy = Metacrunch::Context.from_state(state, logger: Metacrunch.build_logger(io))
    copy.logger.info("rebuilt")

    assert_equal [ctx.id, ctx.position, ctx.step, ctx.marks, ctx.store],
                 [copy.id, copy.position, copy.step, copy.marks, copy.store]
    assert_equal [ctx.rejection, "x"], [copy.rejection, copy.failure.error.message]
    assert_match(/INFO  \[rec1\] rebuilt/, io.string)
  end
```

Add to `test/unit/stats_collector_test.rb`:

```ruby
  def test_take_returns_the_counts_so_far_and_starts_again
    collector = Metacrunch::StatsCollector.new(["map#1"])
    counter = collector.counter("map#1")
    collector.count_read
    counter.input += 1
    collector.mark("Odd")
    first = collector.take
    collector.count_read
    second = collector.take

    assert_equal [1, 1, {"Odd" => 1}], [first.read, first.steps["map#1"].input, first.marked]
    assert_equal [1, 0, {}], [second.read, second.steps["map#1"].input, second.marked]
    assert_same counter, collector.counter("map#1")
  end

  def test_absorb_adds_the_counts_of_another_collector
    worker = Metacrunch::StatsCollector.new(["reject#1"], profile: true)
    worker.count_read
    worker.step_rejected("reject#1", "Patent")
    worker.step_failed("reject#1", KeyError.new("x"))
    worker.step_time("reject#1", 0.5)
    parent = Metacrunch::StatsCollector.new(["reject#1"], profile: true)
    2.times { parent.absorb(worker.snapshot) }
    stats = parent.snapshot

    assert_equal [2, {"Patent" => 2}, {"KeyError" => 2}], [stats.read, stats.rejected, stats.failed]
    assert_equal [2, 2], [parent.rejected_total, parent.failed_total]
    assert_in_delta 1.0, stats.steps["reject#1"].time
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/context_test.rb test/unit/stats_collector_test.rb`
Expected: `NoMethodError: undefined method 'to_state'`, `undefined method 'take'`, `undefined method 'absorb'`.

- [ ] **Step 3: Implement the context state**

In `lib/metacrunch/context.rb`:

- Add the constant and class method at the start of the `Context` class body, before the `attr_reader` line:

```ruby
    # What a sink can read of a context, as plain values. It crosses the
    # boundary between a worker and the parent (Executor::Fork).
    State = Data.define(:id, :position, :step, :marks, :store, :rejection, :failure)

    # A context from a State, with this process's logger. It counts no
    # marks: they were counted where they were made.
    def self.from_state(state, logger:)
      new(id: state.id, position: state.position, logger:, marks: state.marks, store: state.store,
          rejection: state.rejection).tap do |ctx|
        ctx.step = state.step
        ctx.failure = state.failure
      end
    end
```

- Change `initialize` to take the rejection:

```ruby
    def initialize(id:, position:, logger:, on_mark: nil, marks: [], store: {}, rejection: nil)
      @id = id
      @position = position
      @base_logger = logger
      @on_mark = on_mark
      @marks = marks
      @store = store
      @rejection = rejection
      @failure = nil
      @step = nil
      @sealed = false
    end
```

- Add before `copy`:

```ruby
    def to_state = State.new(id:, position:, step:, marks:, store:, rejection:, failure:)
```

- [ ] **Step 4: Implement take and absorb**

In `lib/metacrunch/stats_collector.rb`, add after `snapshot`:

```ruby
    # Returns the counts since the last take as Stats and sets them to
    # zero. The step counters stay the same objects, so a chain built on
    # them keeps counting. Workers report each batch this way.
    def take
      snapshot.tap { reset }
    end

    # Adds what another collector counted (a Stats from take or snapshot),
    # e.g. a batch of a worker.
    def absorb(stats)
      @read += stats.read
      @written += stats.written
      add_counts(@rejected, stats.rejected)
      add_counts(@marked, stats.marked)
      add_counts(@failed, stats.failed)
      @rejected_total += stats.rejected_total
      @failed_total += stats.failed_total
      stats.steps.each { |name, step| add_step(@steps.fetch(name), step) }
    end
```

and in the `private` section, after `now`:

```ruby
    def reset
      @read = 0
      @written = 0
      @rejected = Hash.new(0)
      @marked = Hash.new(0)
      @failed = Hash.new(0)
      @failed_total = 0
      @rejected_total = 0
      @steps.each_value do |counter|
        counter.members.each { counter[it] = 0 }
        counter.time = @profile ? 0.0 : nil
      end
    end

    def add_counts(mine, theirs)
      theirs.each { |key, count| mine[key] += count }
    end

    def add_step(counter, step)
      counter.input += step.input
      counter.output += step.output
      counter.filtered += step.filtered
      counter.rejected += step.rejected
      counter.failed += step.failed
      counter.time += step.time if counter.time && step.time
    end
```

- [ ] **Step 5: Run the tests, the suite and the benchmark**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/context_test.rb test/unit/stats_collector_test.rb`
Expected: PASS.

Run: `bundle exec rake`
Expected: PASS, RuboCop clean.

Run: `bundle exec ruby -Ilib bench/executor.rb inline`
Expected: within 5 % of the Task 1 baseline. `Context.new` has one more keyword argument.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch/context.rb lib/metacrunch/stats_collector.rb test/unit/context_test.rb \
  test/unit/stats_collector_test.rb
git commit -m "Let contexts and stats cross process boundaries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 3: WorkerError, frames and dumping

**Files:**
- Create: `lib/metacrunch/executor/fork/frame.rb`, `lib/metacrunch/executor/fork/dump.rb`
- Modify: `lib/metacrunch/errors.rb`, `lib/metacrunch/json_lines.rb`, `lib/metacrunch.rb`
- Test: `test/unit/executor_fork_frame_test.rb`, `test/unit/executor_fork_dump_test.rb`, `test/unit/errors_test.rb`, `test/unit/json_lines_context_writer_test.rb`

**Interfaces:**
- Consumes: `Context::State` (Task 2).
- Produces:
  - `Metacrunch::WorkerError.new(original_class, original_message)` with `#original_class` and `#original_message`. Its `#message` is `"Original::Class: message"`.
  - `Executor::Fork::Frame.write(io, data)`, where `data` is a String from `Marshal.dump`.
  - `Frame.read(io)` returns the loaded payload or `nil` at the end of the input; `Frame::Truncated < Metacrunch::Error`.
  - `Executor::Fork::Dump.frame(frame)` returns `[data, error]`.
  - `Dump.exception(error)`, `Dump.first_undumpable(values)` (returns `[index, TypeError]` or `nil`) and `Dump.dumpable?(value)`.
  - Worker frames are Hashes: `{type: :ready | :batch | :done, events: [...], stats: Stats | nil, error: Exception | nil}`.
  - Events: `[:log, line]`, `[:deliver | :reject | :fail, record, Context::State]`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/executor_fork_frame_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ExecutorForkFrameTest < Minitest::Test

  Frame = Metacrunch::Executor::Fork::Frame

  def test_frames_pass_a_pipe_with_their_bytes_and_encodings
    records = ["Müller", "\xFF\xFE".b]
    reader, writer = IO.pipe
    Frame.write(writer, Marshal.dump(records))
    writer.close
    loaded = Frame.read(reader)

    assert_equal records, loaded
    assert_equal [Encoding::UTF_8, Encoding::BINARY], loaded.map(&:encoding)
    assert_nil Frame.read(reader)
  ensure
    reader.close
  end

  def test_a_frame_that_ends_early_is_truncated
    data = Marshal.dump("record")

    assert_raises(Frame::Truncated) { Frame.read(StringIO.new([data.bytesize].pack("N") + data[0, 2])) }
    assert_raises(Frame::Truncated) { Frame.read(StringIO.new("\x00\x00".b)) }
  end

end
```

Create `test/unit/executor_fork_dump_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ExecutorForkDumpTest < Minitest::Test

  Dump = Metacrunch::Executor::Fork::Dump

  # Marshal cannot dump it: it holds an IO.
  class HoldsIO < StandardError

    def initialize(message = "holds an IO")
      super
      @io = $stderr
    end

  end

  def test_frames_that_can_be_dumped_stay_as_they_are
    frame = {type: :batch, events: [[:deliver, 1, state(1)]], stats: nil, error: nil}
    data, error = Dump.frame(frame)

    assert_nil error
    assert_equal frame, Marshal.load(data)
  end

  def test_exceptions_that_cannot_be_dumped_are_replaced
    failure = Metacrunch::Failure.new(error: raised(HoldsIO.new), step: "map#1")
    frame = {type: :batch, events: [[:fail, 1, state(1, failure:)]], stats: nil, error: raised(HoldsIO.new)}
    data, error = Dump.frame(frame)
    loaded = Marshal.load(data)

    assert_equal ["ExecutorForkDumpTest::HoldsIO", "holds an IO"],
                 [loaded[:events].first.last.failure.error.original_class, error.original_message]
    assert_instance_of Metacrunch::WorkerError, loaded[:error]
    assert_equal frame[:error].backtrace, loaded[:error].backtrace
  end

  def test_a_step_error_keeps_its_class_and_message_with_a_replaced_cause
    step_error = raised(
      Metacrunch::StepError.new(step: "map#1", record_id: "a", position: 3, error: HoldsIO.new),
      cause: raised(HoldsIO.new)
    )
    _data, error = Dump.frame({type: :batch, events: [], stats: nil, error: step_error})

    assert_instance_of Metacrunch::StepError, error
    assert_equal step_error.message, error.message
    assert_instance_of Metacrunch::WorkerError, error.cause
  end

  def test_an_event_that_cannot_be_dumped_ends_the_frame_before_it
    events = [[:deliver, 1, state(1)], [:deliver, -> {}, state(2)], [:deliver, 3, state(3)]]
    data, error = Dump.frame({type: :batch, events:, stats: nil, error: nil})
    loaded = Marshal.load(data)

    assert_equal [1], loaded[:events].map { it[1] }
    assert_match(/\Arecord at position 2 cannot be sent from a worker: no _dump_data is defined for class Proc; /,
                 error.message)
    assert_equal error.message, loaded[:error].message
  end

  def test_finds_the_first_value_that_cannot_be_dumped
    assert_equal 1, Dump.first_undumpable([1, $stderr, -> {}]).first
    assert_nil Dump.first_undumpable([1, 2])
  end

  private

  def state(position, failure: nil)
    Metacrunch::Context::State.new(id: nil, position:, step: "map#1", marks: [], store: {}, rejection: nil, failure:)
  end

  def raised(exception, cause: nil)
    raise exception, cause:
  rescue exception.class => e
    e
  end

end
```

Add to `test/unit/errors_test.rb`:

```ruby
  def test_worker_error_names_the_original_exception
    error = Metacrunch::WorkerError.new("Net::Broken", "socket closed")

    assert_equal "Net::Broken: socket closed", error.message
    assert_equal ["Net::Broken", "socket closed"], [error.original_class, error.original_message]
  end
```

Add to `test/unit/json_lines_context_writer_test.rb`, after `test_writes_failures`:

```ruby
  def test_writes_worker_errors_as_the_original_exception
    error = Metacrunch::WorkerError.new("Net::Broken", "socket closed")
    @ctx.failure = Metacrunch::Failure.new(error:, step: "map#1")

    assert_equal({"step" => "map#1", "error" => "Net::Broken", "message" => "socket closed"},
                 JSON.parse(write(1))["failure"])
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/executor_fork_frame_test.rb test/unit/executor_fork_dump_test.rb test/unit/errors_test.rb test/unit/json_lines_context_writer_test.rb`
Expected: `uninitialized constant Metacrunch::Executor::Fork` and `Metacrunch::WorkerError`.

- [ ] **Step 3: Add WorkerError**

Append inside `module Metacrunch` in `lib/metacrunch/errors.rb`, after `StepError`:

```ruby

  # Stands in for an exception that a worker process cannot send to the
  # parent because Marshal cannot dump it (e.g. it holds an IO). Keeps the
  # original class name, message and backtrace.
  class WorkerError < Error

    attr_reader :original_class, :original_message

    def initialize(original_class, original_message)
      @original_class = original_class
      @original_message = original_message
      super("#{original_class}: #{original_message}")
    end

  end
```

- [ ] **Step 4: Write `lib/metacrunch/executor/fork/frame.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # Messages between the parent and a worker: the size of the payload as
      # 4 bytes in network order, then the payload, a Marshal dump.
      module Frame

        HEADER = "N"
        HEADER_SIZE = 4

        # A frame that ends early: its writer ended while writing it.
        class Truncated < Error; end

        module_function

        # Writes data, a String from Marshal.dump, as one frame.
        def write(io, data)
          io.write([data.bytesize].pack(HEADER), data)
        end

        # Reads one frame and returns its payload, loaded; nil at the end of
        # the input.
        def read(io)
          header = io.read(HEADER_SIZE)
          return if header.nil?

          size = header.bytesize == HEADER_SIZE ? header.unpack1(HEADER) : nil
          data = size && io.read(size)
          raise Truncated, "the frame ended early" unless data && data.bytesize == size

          Marshal.load(data)
        end

      end
    end
  end
end
```

- [ ] **Step 5: Write `lib/metacrunch/executor/fork/dump.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # Marshal for the frames of a worker, with clear errors for what it
      # cannot dump.
      module Dump

        RESULT_RULE = "with --workers, records, mark and rejection values and ctx.store must be Marshal-able"

        module_function

        # Returns the dumped frame and its error. Exceptions Marshal cannot
        # dump are replaced (see exception). If a record, a mark or rejection
        # value or a store cannot be dumped, the frame ends before that
        # event, and an Error that names its position becomes the frame's
        # error.
        def frame(frame)
          [Marshal.dump(frame), frame[:error]]
        rescue TypeError
          repaired(frame.merge(error: exception(frame[:error]), events: frame[:events].map { dumpable_failure(it) }))
        end

        # error itself if Marshal can dump it. Else a copy it can dump: a
        # StepError keeps its class and message with a replaced cause, any
        # other exception becomes a WorkerError. Both keep the backtrace.
        def exception(error)
          return error if error.nil? || dumpable?(error)

          cause = exception(error.cause)
          if error.is_a?(StepError) && error.cause
            copy = StepError.new(step: error.step, record_id: error.record_id, position: error.position,
                                 error: error.cause)
            copy = with_cause(copy, cause, error.backtrace)
            return copy if dumpable?(copy)
          end
          with_cause(WorkerError.new(error.class.name, error.message), cause, error.backtrace)
        end

        # The index of the first value Marshal cannot dump and its TypeError,
        # or nil.
        def first_undumpable(values)
          values.each_with_index do |value, index|
            Marshal.dump(value)
          rescue TypeError => e
            return [index, e]
          end
          nil
        end

        def dumpable?(value)
          Marshal.dump(value)
          true
        rescue TypeError
          false
        end

        def repaired(frame)
          [Marshal.dump(frame), frame[:error]]
        rescue TypeError
          events = frame[:events]
          index, error = first_undumpable(events)
          position = events[index][2].position
          message = "record at position #{position} cannot be sent from a worker: #{error.message}"
          cut = Error.new("#{message}; #{RESULT_RULE}")
          [Marshal.dump(frame.merge(events: events.first(index), error: cut)), cut]
        end

        # A :fail event whose failure holds an exception Marshal cannot dump
        # gets a replacement.
        def dumpable_failure(event)
          kind, record, state = event
          failure = kind == :fail ? state.failure : nil
          return event if failure.nil? || dumpable?(failure.error)

          [kind, record, state.with(failure: failure.with(error: exception(failure.error)))]
        end

        # Gives a new exception a cause (only raise can set one) and a
        # backtrace.
        def with_cause(exception, cause, backtrace)
          raise exception, cause:
        rescue exception.class => e
          e.set_backtrace(backtrace) if backtrace
          e
        end

      end
    end
  end
end
```

- [ ] **Step 6: Write WorkerError as the original exception in ContextWriter**

In `lib/metacrunch/json_lines.rb`, replace `ContextWriter#failure` with:

```ruby
      def failure(failure)
        error = failure.error
        {"step" => failure.step, "error" => error_class(error), "message" => json(error_message(error))}
      end

      # A WorkerError stands for an exception of a worker; it is written as
      # that exception, as without workers.
      def error_class(error) = error.is_a?(WorkerError) ? error.original_class : error.class.name

      def error_message(error) = error.is_a?(WorkerError) ? error.original_message : error.message
```

- [ ] **Step 7: Require the new files**

In `lib/metacrunch.rb`, insert after `require_relative "metacrunch/executor/inline"`:

```ruby
require_relative "metacrunch/executor/fork/frame"
require_relative "metacrunch/executor/fork/dump"
```

- [ ] **Step 8: Run the tests and the suite**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/executor_fork_frame_test.rb test/unit/executor_fork_dump_test.rb test/unit/errors_test.rb test/unit/json_lines_context_writer_test.rb`
Expected: PASS.

Run: `bundle exec rake`
Expected: PASS, RuboCop clean.

- [ ] **Step 9: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/errors.rb lib/metacrunch/json_lines.rb lib/metacrunch/executor/fork \
  test/unit/executor_fork_frame_test.rb test/unit/executor_fork_dump_test.rb test/unit/errors_test.rb \
  test/unit/json_lines_context_writer_test.rb
git commit -m "Add frames and Marshal dumping with clear errors for worker processes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 4: The worker loop

**Files:**
- Create: `lib/metacrunch/executor/fork/worker.rb`
- Modify: `lib/metacrunch.rb`
- Test: `test/unit/executor_fork_worker_test.rb`

**Interfaces:**
- Consumes:
  - `Processor` (Task 1);
  - `Context#to_state` and `StatsCollector#take` (Task 2);
  - `Frame` and `Dump.frame` (Task 3).
- Produces:
  - `Executor::Fork::Worker.new(pipeline)`.
  - `Worker#run(input, output)`. It writes the frames `:ready`, then one `:batch` per batch, then `:done`. It returns after the end of the input, after an `open` error or after a batch that ended with an error. A `SignalException` closes the steps and is raised again.
  - `Worker.main(pipeline, input, output)`, called in the child; it never returns.
  - `Worker::BatchOutlet.new(events, deliver:, reject:)` and `Worker::LogBuffer.new(events)`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/executor_fork_worker_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ExecutorForkWorkerTest < Minitest::Test

  include PipelineHelper

  Frame = Metacrunch::Executor::Fork::Frame

  # A step callable that notes open and close.
  class Lifecycle

    attr_reader :log

    def initialize
      @log = []
    end

    def open(_context) = @log << :open

    def close = @log << :close

    def call(record) = record

  end

  class FailingOpen

    def open(_context) = raise("open broke")

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  def test_sends_ready_a_result_per_batch_and_done
    frames = run_worker([[[1, 2], [10, 20]], [[3], [30]]]) do
      map { it + 1 }
      sink CollectingSink.new
    end
    delivered = frames[1][:events].map { |kind, record, state| [kind, record, state.position] }

    assert_equal [:ready, :batch, :batch, :done], frames.map { it[:type] }
    assert_equal [[:deliver, 11, 1], [:deliver, 21, 2]], delivered
    assert_equal [2, 1], [frames[1][:stats].read, frames[2][:stats].read]
  end

  def test_rejected_and_failed_records_carry_their_context
    frames = run_worker([[[1, 2], [1, 2]]]) do
      reject("One") { it == 1 }
      map { raise ArgumentError, "bad" }
      rejects CollectingSink.new
      on_error :skip
    end
    events = frames[1][:events].map { |kind, _record, state| [kind, state.rejection&.reason, state.failure&.step] }

    assert_equal [[:reject, "One", nil], [:fail, nil, "map#2"]], events
  end

  def test_records_are_not_sent_to_sinks_the_pipeline_lacks
    frames = run_worker([[[1, 2], [1, 2]]]) { reject("One") { it == 1 } }

    assert_empty frames[1][:events]
  end

  def test_log_lines_become_events_in_order_with_the_records
    logger = Metacrunch.build_logger(StringIO.new)
    frames = run_worker([[[1], [1]]], logger:) do
      map do |record, ctx|
        ctx.logger.info("seen")
        record
      end
      sink CollectingSink.new
    end
    events = frames[1][:events]

    assert_equal [:log, :deliver], events.map(&:first)
    assert_match(/INFO  \[#1\] seen\n\z/, events.first.last)
  end

  def test_an_abort_ends_the_batch_and_the_worker
    frames = run_worker([[[1, 2], [1, 2]], [[3], [3]]]) do
      map { it == 2 ? raise("boom") : it }
      sink CollectingSink.new
    end

    assert_equal [:ready, :batch], frames.map { it[:type] }
    assert_equal [[:deliver, 1]], frames[1][:events].map { it.first(2) }
    assert_equal ["map#1", 2], [frames[1][:error].step, frames[1][:error].position]
  end

  def test_an_open_error_is_sent_with_ready
    frames = run_worker([[[1], [1]]]) { map FailingOpen.new }

    assert_equal [[:ready, "open broke"]], frames.map { [it[:type], it[:error]&.message] }
  end

  def test_a_close_error_is_sent_with_done
    frames = run_worker([]) { map FailingClose.new }

    assert_equal [[:ready, nil], [:done, "close broke"]], frames.map { [it[:type], it[:error]&.message] }
  end

  def test_opens_and_closes_the_step_callables
    step = Lifecycle.new
    run_worker([[[1], [1]]]) { map step }

    assert_equal [:open, :close], step.log
  end

  def test_a_signal_closes_the_steps_and_is_raised_again
    step = Lifecycle.new
    pipeline = build_pipeline do
      map step
      map { raise Interrupt }
    end

    assert_raises(Interrupt) { drive(pipeline, [[[1], [1]]]) }
    assert_equal [:open, :close], step.log
  end

  def test_an_exit_in_a_step_is_sent_as_the_error
    frames = run_worker([[[1], [1]]]) { map { exit 3 } }

    assert_equal [SystemExit, 3], [frames[1][:error].class, frames[1][:error].status]
  end

  def test_a_record_that_cannot_be_dumped_ends_the_worker
    frames = run_worker([[[1, 2], [1, 2]], [[3], [3]]]) do
      map { it == 2 ? -> {} : it }
      sink CollectingSink.new
    end

    assert_equal [:ready, :batch], frames.map { it[:type] }
    assert_match(/\Arecord at position 2 cannot be sent from a worker/, frames[1][:error].message)
  end

  private

  def run_worker(batches, logger: SILENT_LOGGER, &)
    drive(build_pipeline(logger:, &), batches)
  end

  # Runs a worker in this process: writes the batches to its input, then
  # returns the frames it wrote. The frames of these tests fit in a pipe
  # buffer, so nothing has to read while the worker runs.
  def drive(pipeline, batches)
    input, feed = IO.pipe
    results, output = IO.pipe
    batches.each { Frame.write(feed, Marshal.dump(it)) }
    feed.close
    begin
      Metacrunch::Executor::Fork::Worker.new(pipeline).run(input, output)
    ensure
      output.close
    end
    frames = []
    while (frame = Frame.read(results))
      frames << frame
    end
    frames
  ensure
    [input, results].each { it.close unless it.closed? }
  end

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_worker_test.rb`
Expected: `uninitialized constant Metacrunch::Executor::Fork::Worker`.

- [ ] **Step 3: Write `lib/metacrunch/executor/fork/worker.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # The loop of one worker process: opens the step callables, reads
      # batches from its input, pushes them through a Processor and writes
      # the results to its output (Frame, Dump). Runs in the forked child;
      # tests drive #run in-process through pipes.
      class Worker

        # Collects what leaves the chain as events of the current frame.
        class BatchOutlet

          # deliver, reject: false if the pipeline has no sink or no rejects
          # sink; those records are then not sent at all.
          def initialize(events, deliver:, reject:)
            @events = events
            @deliver = deliver
            @reject = reject
          end

          def deliver(record, ctx)
            @events << [:deliver, record, ctx.to_state] if @deliver
          end

          def reject(record, ctx)
            @events << [:reject, record, ctx.to_state] if @reject
          end

          # Always sent: the parent counts failures for max_errors.
          def fail(record, ctx)
            @events << [:fail, record, ctx.to_state]
          end

        end

        # The log device of the worker's logger: every formatted line becomes
        # an event, so the parent writes it in order with the records.
        class LogBuffer

          def initialize(events)
            @events = events
          end

          def write(line)
            @events << [:log, line]
          end

          def close = nil

        end

        # Runs a worker in the forked child and ends the process without the
        # at_exit handlers and write buffers inherited from the parent. A
        # signal ends it by that signal.
        def self.main(pipeline, input, output)
          new(pipeline).run(input, output)
          Process.exit!(0)
        rescue SignalException => e
          Signal.trap(e.signo, "SYSTEM_DEFAULT")
          Process.kill(e.signo, Process.pid)
          Process.exit!(128 + e.signo)
        rescue Exception # rubocop:disable Lint/RescueException
          Process.exit!(1)
        end

        def initialize(pipeline)
          @pipeline = pipeline
          @events = []
          @stats = StatsCollector.new(pipeline.steps.map(&:name), profile: pipeline.profile)
          outlet = BatchOutlet.new(@events, deliver: !pipeline.sink.nil?, reject: !pipeline.rejects.nil?)
          @processor = Processor.new(pipeline, stats: @stats, outlet:)
        end

        # Sends :ready (or the error of open), the result of every batch and
        # :done (with the error of close). Returns after a batch that ended
        # with an error. A signal, also an Interrupt raised by a step, closes
        # the step callables and is raised again.
        def run(input, output)
          @output = output
          redirect_logger
          return unless ready?

          error = process_batches(input)
          close_error = @processor.close
          send_frame(:done, error: close_error) unless error
        rescue SignalException
          @processor.close
          raise
        end

        private

        # Logger#reopen with an object that has write and close is public
        # Logger API. Other loggers write directly from the worker.
        def redirect_logger
          logger = @pipeline.logger
          logger.reopen(LogBuffer.new(@events)) if logger.is_a?(::Logger)
        end

        def ready?
          @processor.open
          send_frame(:ready)
          true
        rescue *Engine::RECOVERABLE => e
          @processor.close
          send_frame(:ready, error: e)
          false
        end

        # Returns the error that ended a batch, or nil at the end of the
        # input.
        def process_batches(input)
          while (batch = Frame.read(input))
            positions, records = batch
            error = send_frame(:batch, error: process(positions, records))
            return error if error
          end
          nil
        end

        # Returns the exception that stopped the batch, or nil. Signals pass.
        def process(positions, records)
          positions.each_with_index { |position, index| @processor.call(records[index], position) }
          nil
        rescue SignalException
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end

        # Writes a frame and clears the events. A :batch frame carries what
        # the batch counted. Returns the frame's error, which Dump.frame sets
        # if a record could not be dumped.
        def send_frame(type, error: nil)
          stats = type == :batch ? @stats.take : nil
          data, error = Dump.frame({type:, events: @events, stats:, error:})
          Frame.write(@output, data)
          @events.clear
          error
        end

      end
    end
  end
end
```

- [ ] **Step 4: Require the file**

In `lib/metacrunch.rb`, insert after `require_relative "metacrunch/executor/fork/dump"`:

```ruby
require_relative "metacrunch/executor/fork/worker"
```

- [ ] **Step 5: Run the test and the suite**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_worker_test.rb`
Expected: PASS.

Run: `bundle exec rake`
Expected: PASS. Coverage holds: `Worker.main` runs only in forked children, which is a handful of lines.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/executor/fork/worker.rb test/unit/executor_fork_worker_test.rb
git commit -m "Add the worker loop of the fork executor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 5: Executor::Fork and the parity suite

**Files:**
- Create: `lib/metacrunch/executor/fork.rb`, `lib/metacrunch/executor/fork/run.rb`, `test/support/fork_variant.rb`, `test/support/override.rb`, `test/unit/executor_fork_test.rb`
- Modify:
  - `lib/metacrunch/engine.rb` (observer check), `lib/metacrunch.rb`, `test/support/pipeline_helper.rb`;
  - `test/unit/engine_test.rb`, `engine_error_policy_test.rb`, `engine_lifecycle_test.rb`, `engine_batching_test.rb`, `engine_invalid_record_test.rb`, `engine_selection_test.rb`, `engine_monitor_test.rb`.

**Interfaces:**
- Consumes:
  - `Processor`, `SinkOutlet`, `Inline.each_record` (Task 1);
  - `Context.from_state`, `StatsCollector#absorb` (Task 2);
  - `Frame` (Task 3);
  - `Worker.main` (Task 4).
- Produces:
  - `Executor::Fork.new(workers:, batch_size: 100, stop_timeout: 5)` with `#workers`, `#batch_size` and `#run(pipeline, stats:, outlet:, observer: nil, select: nil)`. `ArgumentError` for `workers < 2`, a bad `batch_size` or no fork support.
  - `Executor::Fork.supported?`.
  - `Executor::Fork::Run`, internal.
  - `Engine` raises `ArgumentError, "an observer needs the inline executor"` for an observer with more than one worker.
  - Test helpers:
    - `PipelineHelper#executor` and `#engine(pipeline, **)`;
    - `ForkVariant.define(test_class, inline_only: [])`;
    - `ForkVariant::NoWorkerLeft`;
    - `Override#override(object, name, implementation) { }`.

- [ ] **Step 1: Add the test helpers**

Replace `test/support/pipeline_helper.rb` with:

```ruby
# frozen_string_literal: true

module PipelineHelper

  SILENT_LOGGER = Logger.new(nil)

  def build_pipeline(params: {}, logger: SILENT_LOGGER, &recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash(params) }, logger:)
    builder.instance_exec(&recipe)
    builder.build
  end

  # The executor of engine and run_pipeline; ForkVariant replaces it.
  def executor = Metacrunch::Executor::Inline.new

  def engine(pipeline, **)
    Metacrunch::Engine.new(pipeline, executor:, **)
  end

  def run_pipeline(params: {}, logger: SILENT_LOGGER, &)
    engine(build_pipeline(params:, logger:, &)).run
  end

end
```

Create `test/support/fork_variant.rb`:

```ruby
# frozen_string_literal: true

# Runs the tests of an engine test class a second time, with the steps in
# two worker processes and batches of three records, so batch boundaries
# fall inside the data: Executor::Fork must give the results of inline
# runs. inline_only names the tests that cannot run with workers (an
# observer, state shared with a step, a step that opens in this process,
# exact stats after an abort in the middle of a batch).
module ForkVariant

  # Fails a test that leaves a child process behind.
  module NoWorkerLeft

    def teardown
      super
      Process.waitpid(-1, Process::WNOHANG)
      flunk("a worker process is left")
    rescue Errno::ECHILD
      nil
    end

  end

  def self.define(test_class, inline_only: [])
    variant = Class.new(test_class) do
      include NoWorkerLeft

      def executor = Metacrunch::Executor::Fork.new(workers: 2, batch_size: 3)
    end
    inline_only.each { variant.undef_method(it) }
    test_class.const_set(:Fork, variant)
  end

end
```

Create `test/support/override.rb`:

```ruby
# frozen_string_literal: true

# Replaces a singleton method while a block runs (Minitest 6 has no stub).
module Override

  def override(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

end
```

- [ ] **Step 2: Turn the engine tests into the parity suite**

Apply these edits.

`test/unit/engine_test.rb`:
- Replace `test_reject_from_the_context_stops_the_record`. It must not collect records from inside a step, because that state stays in the worker:

```ruby
  def test_reject_from_the_context_stops_the_record
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2]
      map do |record, ctx|
        ctx.reject!("Odd", value: record) if record.odd?
        record
      end
      map { it * 10 }
      sink target
    end

    assert_equal [20], target.records
    assert_equal({"Odd" => 1}, result.stats.rejected)
  end
```

- In `test_a_pipeline_without_source_cannot_run`, replace `Metacrunch::Engine.new(pipeline).run` with `engine(pipeline).run`.
- Append after the class:

```ruby

ForkVariant.define(EngineTest, inline_only: [
  :test_observer_sees_a_matching_step_out_for_every_flat_map_step_in,
  :test_observer_sees_inputs_and_outputs_of_each_step
])
```

`test/unit/engine_error_policy_test.rb`: append after the class:

```ruby

ForkVariant.define(EngineErrorPolicyTest, inline_only: [
  :test_zero_max_errors_stops_at_the_first_failure_after_recording_it
])
```

`test/unit/engine_lifecycle_test.rb`:
- In `test_interrupt_in_a_step_closes_components_and_skips_after_hooks`, `test_interrupt_in_the_source_closes_the_sink` and `test_signals_while_closing_are_raised_after_closing_everything`, replace `Metacrunch::Engine.new(pipeline).run` with `engine(pipeline).run`.
- Append after the class:

```ruby

ForkVariant.define(EngineLifecycleTest, inline_only: [
  :test_opens_source_and_sinks_then_steps_and_closes_in_reverse,
  :test_steps_open_after_the_before_hooks,
  :test_hooks_run_around_the_records
])
```

`test/unit/engine_batching_test.rb`:
- In `test_interrupt_during_a_per_record_flush_keeps_the_rest`, replace `Metacrunch::Engine.new(pipeline).run` with `engine(pipeline).run`.
- Append:

```ruby

ForkVariant.define(EngineBatchingTest, inline_only: [
  :test_interrupt_writes_the_records_that_completed_the_pipeline,
  :test_sigterm_flushes_like_interrupt
])
```

`test/unit/engine_invalid_record_test.rb`: append:

```ruby

ForkVariant.define(EngineInvalidRecordTest, inline_only: [
  :test_the_observer_sees_invalid_records_as_the_source_step,
  :test_the_observer_sees_the_failure_of_a_step_under_skip
])
```

`test/unit/engine_selection_test.rb`:
- Replace every `Metacrunch::Engine.new(` with `engine(`. There are four calls: `pipeline.with(limit: 2)`, `pipeline.with(limit: 1)`, `pipeline, select:` and `pipeline.with(limit: 0)`.
- Append:

```ruby

ForkVariant.define(EngineSelectionTest)
```

`test/unit/engine_monitor_test.rb`:
- Replace every `Metacrunch::Engine.new(` with `engine(`.
- Append:

```ruby

ForkVariant.define(EngineMonitorTest)
```

Why these tests are inline-only:
- **Observers:** they need the inline executor.
- **`test_zero_max_errors_...`:** it asserts `read 1`. With workers, the stats count the whole batch (spec 4.4); `executor_fork_test` covers this case.
- **The lifecycle tests:** they see steps open in this process, or collect records from a step.
- **The two batching tests:** they raise a signal inside a step. With workers, records of the interrupted batch are discarded, as after a real Ctrl-C (spec 4.3).

- [ ] **Step 3: Write the fork tests**

Create `test/unit/executor_fork_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ExecutorForkTest < Minitest::Test

  include PipelineHelper
  include Override
  include ForkVariant::NoWorkerLeft

  # Counts the records it yields.
  class CountingSource

    attr_reader :yielded

    def initialize(records)
      @records = records
      @yielded = 0
    end

    def each
      @records.each do |record|
        @yielded += 1
        yield record
      end
    end

  end

  # A step callable that appends "open PID" and "close PID" to a file.
  class PidLog

    def initialize(path)
      @path = path
    end

    def open(_context) = File.write(@path, "open #{Process.pid}\n", mode: "a")

    def close = File.write(@path, "close #{Process.pid}\n", mode: "a")

    def call(record) = record

  end

  # A sink that writes a header in open and leaves it in its write buffer
  # while the workers start.
  class BufferedFile

    def initialize(path)
      @path = path
    end

    def open(_context)
      @file = File.open(@path, "w")
      @file.write("header\n")
    end

    def write(record) = @file.write("#{record}\n")

    def close = @file.close

  end

  class FailingOpen

    def open(_context) = raise("open broke")

    def call(record) = record

  end

  class FailingClose

    def close = raise("close broke")

    def call(record) = record

  end

  def executor = Metacrunch::Executor::Fork.new(workers: 3, batch_size: 2)

  def test_records_keep_the_source_order_when_workers_take_different_time
    target = CollectingSink.new
    run_pipeline do
      source((1..12).to_a)
      map do |record|
        sleep(0.02) if record <= 2
        record * 10
      end
      sink target
    end

    assert_equal((1..12).map { it * 10 }, target.records)
  end

  def test_contexts_reach_the_sinks_with_marks_and_store
    target = CollectingSink.new
    run_pipeline do
      source [1, 2, 3], id: ->(record) { "r#{record}" }
      map do |record, ctx|
        ctx.mark("Seen", value: record)
        ctx.store["double"] = record * 2
        record
      end
      sink target
    end
    contexts = target.contexts.map { [it.id, it.position, it.marks.map(&:value), it.store["double"]] }

    assert_equal [["r1", 1, [1], 2], ["r2", 2, [2], 4], ["r3", 3, [3], 6]], contexts
  end

  def test_runs_with_an_empty_source_and_with_fewer_batches_than_workers
    empty = run_pipeline { source [] }
    few = CollectingSink.new
    run_pipeline do
      source [1, 2, 3]
      sink few
    end

    assert_equal [:ok, 0], [empty.status, empty.stats.read]
    assert_equal [1, 2, 3], few.records
  end

  def test_records_larger_than_a_pipe_buffer_pass_both_ways
    target = CollectingSink.new
    run_pipeline do
      source(Array.new(5) { "x" * 1_000_000 })
      map { "#{it}y" }
      sink target
    end

    assert_equal [1_000_001] * 5, target.records.map(&:size)
  end

  def test_strings_keep_their_bytes_and_encoding
    target = CollectingSink.new
    records = ["Müller", "\xFF\xFE".b, "Ἀθῆναι"]
    run_pipeline do
      source records
      sink target
    end

    assert_equal records, target.records
    assert_equal records.map(&:encoding), target.records.map(&:encoding)
  end

  def test_an_abort_in_the_middle_of_a_batch_counts_the_whole_batch
    failed = CollectingSink.new
    result = run_pipeline do
      source((1..6).to_a)
      map { raise ArgumentError, "bad" }
      errors failed
      on_error :skip, max_errors: 0
    end

    assert_equal [:aborted, [1]], [result.status, failed.records]
    assert_equal 2, result.stats.read
  end

  def test_log_lines_keep_the_source_order_and_stop_at_an_abort
    io = StringIO.new
    run_pipeline(logger: Metacrunch.build_logger(io)) do
      source((1..6).to_a)
      map do |record, ctx|
        sleep(0.02) if record == 1
        ctx.logger.info("record #{record}")
        raise "boom" if record == 4

        record
      end
    end

    assert_equal ["record 1", "record 2", "record 3", "record 4"], io.string.scan(/record \d/)
  end

  def test_workers_inherit_what_before_hooks_load
    target = CollectingSink.new
    table = nil
    run_pipeline do
      source [1, 2]
      before { table = {1 => "one", 2 => "two"} }
      map { table.fetch(it) }
      sink target
    end

    assert_equal ["one", "two"], target.records
  end

  def test_each_worker_opens_and_closes_its_steps
    Dir.mktmpdir do |dir|
      log = File.join(dir, "steps.log")
      run_pipeline do
        source((1..6).to_a)
        map PidLog.new(log)
      end
      lines = File.readlines(log, chomp: true)
      pids = lines.map { it.split.last }.uniq

      assert_equal 3, pids.size
      refute_includes pids, Process.pid.to_s
      assert_equal 3, lines.count { it.start_with?("close") }
    end
  end

  def test_buffered_output_of_a_sink_is_written_once
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.txt")
      run_pipeline do
        source [1, 2]
        sink BufferedFile.new(path)
      end

      assert_equal "header\n1\n2\n", File.read(path)
    end
  end

  def test_an_open_error_in_a_worker_aborts_before_any_record_is_read
    target = CollectingSink.new
    input = CountingSource.new([1, 2])
    result = run_pipeline do
      source input
      map FailingOpen.new
      sink target
    end

    assert_equal [:aborted, "open broke"], [result.status, result.error.message]
    assert_equal [0, []], [input.yielded, target.records]
  end

  def test_a_close_error_in_a_worker_aborts_after_all_records
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map FailingClose.new
      sink target
    end

    assert_equal [:aborted, "close broke"], [result.status, result.error.message]
    assert_equal [1, 2, 3], target.records
  end

  def test_exit_in_a_step_ends_the_run_like_inline
    pipeline = build_pipeline do
      source [1]
      map { exit 3 }
    end
    error = assert_raises(SystemExit) { engine(pipeline).run }

    assert_equal 3, error.status
  end

  def test_an_early_abort_stops_feeding_the_workers
    result = run_pipeline do
      source((1..1_000).to_a)
      map { raise "boom" }
    end

    assert_equal [:aborted, 1], [result.status, result.error.position]
  end

  def test_sigterm_to_a_worker_ends_the_run_by_sigterm
    pipeline = build_pipeline do
      source [1, 2]
      map do |record|
        Process.kill("TERM", Process.pid)
        sleep(1)
        record
      end
    end
    error = assert_raises(SignalException) { engine(pipeline).run }

    assert_equal "SIGTERM", error.message
  end

  def test_an_observer_needs_the_inline_executor
    pipeline = build_pipeline { source [1] }
    error = assert_raises(ArgumentError) { engine(pipeline, observer: Object.new).run }

    assert_equal "an observer needs the inline executor", error.message
  end

  def test_arguments_are_checked
    assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 1) }
    assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 2, batch_size: 0) }
    override(Metacrunch::Executor::Fork, :supported?, -> { false }) do
      assert_raises(ArgumentError) { Metacrunch::Executor::Fork.new(workers: 2) }
    end
  end

end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_test.rb`
Expected: errors. `Executor::Fork` exists only as the namespace of `Frame` and `Dump`, so `Fork.new(workers: 3, batch_size: 2)` raises `ArgumentError` (wrong number of arguments) and `Fork.supported?` raises `NoMethodError`.

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_test.rb`
Expected: the `EngineTest::Fork` tests error with `ArgumentError` from `Fork.new`.

- [ ] **Step 5: Write `lib/metacrunch/executor/fork.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    # Runs the steps in forked worker processes; the source and the sinks
    # stay in this process. Batch k of the source goes to worker k mod N,
    # and the results are applied in the same order, so records, logs and
    # errors reach the sinks in source order, as inline. See Run, Worker,
    # Frame and Dump.
    class Fork

      BATCH_SIZE = 100

      # Seconds stopped workers get to close their steps before SIGKILL.
      STOP_TIMEOUT = 5

      # False on platforms without fork (Windows, JRuby).
      def self.supported? = Process.respond_to?(:fork)

      attr_reader :workers, :batch_size

      # workers: the number of worker processes, at least 2 (1 is Inline).
      # stop_timeout: see STOP_TIMEOUT; tests shorten it.
      def initialize(workers:, batch_size: BATCH_SIZE, stop_timeout: STOP_TIMEOUT)
        unless workers.is_a?(Integer) && workers >= 2
          raise ArgumentError, "workers must be an Integer of at least 2, got #{workers.inspect}"
        end
        unless batch_size.is_a?(Integer) && batch_size.positive?
          raise ArgumentError, "batch_size must be a positive Integer, got #{batch_size.inspect}"
        end
        raise ArgumentError, "workers need Process.fork, which this platform lacks" unless Fork.supported?

        @workers = workers
        @batch_size = batch_size
        @stop_timeout = stop_timeout
      end

      # Like Inline#run, with the steps in the workers. Engine refuses an
      # observer before.
      def run(pipeline, stats:, outlet:, observer: nil, select: nil)
        raise ArgumentError, "an observer needs the inline executor" if observer

        Run.new(pipeline, workers:, batch_size:, stop_timeout: @stop_timeout, stats:, outlet:, select:).call
      end

    end
  end
end
```

- [ ] **Step 6: Write `lib/metacrunch/executor/fork/run.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # One run of the fork executor: forks the workers, waits until they
      # opened their steps, feeds them batches from a thread and applies
      # their results in order through the outlet. Stops the workers in any
      # case.
      class Run

        # The parent's side of a worker: its number (from 1), its pid, the
        # pipe it reads batches from (input), the pipe it writes frames to
        # (output) and its exit status once reaped.
        Handle = Struct.new(:number, :pid, :input, :output, :status) do
          def close
            [input, output].each { it.close unless it.closed? }
          end
        end

        INTERRUPT = Signal.list.fetch("INT")
        TERMINATE = Signal.list.fetch("TERM")

        def initialize(pipeline, workers:, batch_size:, stop_timeout:, stats:, outlet:, select:)
          @pipeline = pipeline
          @workers = workers
          @batch_size = batch_size
          @stop_timeout = stop_timeout
          @stats = stats
          @outlet = outlet
          @select = select
          @handles = []
          @feeder = nil
          @finished = false
        end

        def call
          start_workers
          @handles.each { raise_error(receive(it)) }
          @feeder = Thread.new { feed }
          apply_results
          @finished = true
        ensure
          stop
        end

        private

        def start_workers
          Process.warmup
          @workers.times { @handles << spawn(@handles.size + 1) }
          @pipeline.logger.debug { "started #{@workers} workers (pids #{@handles.map(&:pid).join(", ")})" }
        end

        # The child closes the parent's ends of its own pipes and of the
        # pipes of the workers started before it: a worker sees the end of
        # its input only when no other process holds the writing end.
        def spawn(number)
          input, feed = IO.pipe
          results, output = IO.pipe
          [input, feed, results, output].each(&:binmode)
          pid = Process.fork do
            [feed, results, *@handles.flat_map { [it.input, it.output] }].each(&:close)
            Worker.main(@pipeline, input, output)
          end
          input.close
          output.close
          Handle.new(number, pid, feed, results)
        end

        # Runs in the feeder thread: reads the source and sends batch k to
        # worker k mod N, then closes the input of every worker. Returns the
        # exception that ended the source, or nil.
        def feed
          Thread.current.report_on_exception = false
          numbered_records.each_slice(@batch_size).with_index do |slice, batch|
            break unless send_batch(@handles[batch % @workers], slice)
          end
          nil
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        ensure
          @handles.each { it.input.close unless it.input.closed? }
        end

        # The selected source records as [position, record] pairs.
        def numbered_records
          Enumerator.new do |yielder|
            Inline.each_record(@pipeline.source, limit: @pipeline.limit, select: @select) do |record, position|
              yielder << [position, record]
            end
          end
        end

        # Returns false if the worker is gone: it ended after an error, which
        # the main thread reports when it reaches that batch.
        def send_batch(handle, slice)
          Frame.write(handle.input, Marshal.dump(slice.transpose))
          true
        rescue Errno::EPIPE
          false
        end

        # Applies batch k from worker k mod N until a worker sends :done
        # instead: then no batch is left, and the others send :done too.
        def apply_results
          batch = 0
          loop do
            handle = @handles[batch % @workers]
            frame = receive(handle)
            return finish(handle, frame) if frame[:type] == :done

            raise_error(frame)
            batch += 1
          end
        end

        # Raises the error of the source, else the first error of closing.
        def finish(last, frame)
          frames = [frame, *(@handles - [last]).map { receive(it) }]
          error = @feeder.value || frames.filter_map { it[:error] }.first
          raise error if error
        end

        # Reads the next frame of a worker, adds its stats and applies its
        # events. Returns the frame.
        def receive(handle)
          frame = read(handle)
          @stats.absorb(frame[:stats]) if frame[:stats]
          frame[:events].each { apply(it) }
          frame
        end

        def apply(event)
          return @pipeline.logger << event.last if event.first == :log

          kind, record, state = event
          ctx = Context.from_state(state, logger: @pipeline.logger)
          case kind
          when :deliver then @outlet.deliver(record, ctx)
          when :reject then @outlet.reject(record, ctx)
          else @outlet.fail(record, ctx)
          end
        end

        def raise_error(frame)
          raise frame[:error] if frame[:error]
        end

        # A worker that closed its output without a whole frame has ended.
        def read(handle)
          Frame.read(handle.output) || ended(handle)
        rescue Frame::Truncated
          ended(handle)
        end

        # Raises the signal the worker ended by (SIGINT, SIGTERM), as if this
        # process had got it, else an Error.
        def ended(handle)
          status = reap(handle)
          raise Interrupt if status.termsig == INTERRUPT
          raise SignalException, TERMINATE if status.termsig == TERMINATE

          raise Error, "worker #{handle.number} (pid #{handle.pid}) ended unexpectedly"
        end

        def reap(handle)
          handle.status ||= Process.waitpid2(handle.pid).last
        end

        # Ends the feeder and the workers. After a normal end the workers have
        # ended already and are only reaped; otherwise they get SIGTERM.
        def stop
          @feeder&.kill&.join
          @handles.each(&:close)
          @handles.each { terminate(it) } unless @finished
          @handles.each do |handle|
            reap(handle)
            @pipeline.logger.debug { "worker #{handle.number} (pid #{handle.pid}) ended: #{handle.status}" }
          end
        end

        def terminate(handle)
          Process.kill("TERM", handle.pid) unless handle.status
        rescue Errno::ESRCH
          nil
        end

      end
    end
  end
end
```

- [ ] **Step 7: Refuse observers with workers in Engine and require the files**

In `lib/metacrunch/engine.rb`, change `validate!` to:

```ruby
    def validate!
      raise ArgumentError, "the pipeline has no source" unless @pipeline.source
      raise ArgumentError, "an observer needs the inline executor" if @observer && @executor.workers > 1

      limit = @pipeline.limit
      return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

      raise ArgumentError, "limit must be a positive Integer, got #{limit.inspect}"
    end
```

In `lib/metacrunch.rb`, insert between `require_relative "metacrunch/executor/inline"` and `require_relative "metacrunch/executor/fork/frame"`:

```ruby
require_relative "metacrunch/executor/fork"
```

and after `require_relative "metacrunch/executor/fork/worker"`:

```ruby
require_relative "metacrunch/executor/fork/run"
```

- [ ] **Step 8: Run the fork tests and the parity suite**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_test.rb`
Expected: PASS.

Run: `bundle exec ruby -w -Ilib -Itest -e 'Dir["test/unit/engine*_test.rb"].each { require File.expand_path(it) }'`
Expected: PASS for `EngineTest`, `EngineTest::Fork` and the other variants.

If a fork variant fails, find out first whether the test relies on state shared with a step, or whether `Run` diverges from inline. Only the first case may go to `inline_only`, with the reason added to the list in Step 2.

Run: `bundle exec rake`
Expected: PASS, coverage above the thresholds, RuboCop clean.

- [ ] **Step 9: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/engine.rb lib/metacrunch/executor/fork.rb \
  lib/metacrunch/executor/fork/run.rb test/support test/unit/executor_fork_test.rb test/unit/engine*_test.rb
git commit -m "Add the fork executor and run the engine tests with workers too

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 6: Failure modes of workers

Adds clear messages for workers that die and for source records that cannot be sent, and SIGKILL after the stop timeout. It also pins the remaining failure behaviour with tests.

**Files:**
- Modify: `lib/metacrunch/executor/fork/run.rb`
- Test: `test/unit/executor_fork_failures_test.rb`

**Interfaces:**
- Consumes: `Run` (Task 5), `Dump.first_undumpable` (Task 3).
- Produces:
  - The error messages `worker N (pid P) ended unexpectedly (killed by SIGKILL)` and `(exit status 3)`, with an OBJC hint on Darwin for SIGABRT.
  - `record at position N cannot be sent to a worker: ...`.
  - The stop timeout with SIGKILL.

- [ ] **Step 1: Write the tests**

Create `test/unit/executor_fork_failures_test.rb`:

```ruby
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

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

end
```

- [ ] **Step 2: Run the tests to see which fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_failures_test.rb`
Expected:
- FAIL: the three messages about workers that ended (the message lacks `(killed by SIGKILL)` and the rest);
- FAIL: the source record that cannot be dumped (the error is a bare `TypeError`);
- FAIL or hang until `sleep(30)` ends: the SIGTERM timeout, because `reap` waits without a deadline.

The other tests already pass with the code of Tasks 4 and 5 and pin that behaviour.

- [ ] **Step 3: Implement the messages, the culprit search and the deadline**

In `lib/metacrunch/executor/fork/run.rb`:

Replace `send_batch` with:

```ruby
        # Returns false if the worker is gone: it ended after an error, which
        # the main thread reports when it reaches that batch.
        def send_batch(handle, slice)
          positions, records = slice.transpose
          Frame.write(handle.input, Marshal.dump([positions, records]))
          true
        rescue TypeError
          undumpable_record(handle, positions, records)
        rescue Errno::EPIPE
          false
        end

        # Sends the records before the first one Marshal cannot dump, then
        # raises like an error of the source.
        def undumpable_record(handle, positions, records)
          index, error = Dump.first_undumpable(records)
          Frame.write(handle.input, Marshal.dump([positions.first(index), records.first(index)])) if index.positive?
          raise Error, "record at position #{positions[index]} cannot be sent to a worker: #{error.message}; " \
                       "with --workers, records must be Marshal-able (e.g. parse XML in a step, not in the source)"
        end
```

Replace `ended`, `reap` and `stop` with:

```ruby
        # Raises the signal the worker ended by (SIGINT, SIGTERM), as if this
        # process had got it, else an Error.
        def ended(handle)
          status = reap(handle, deadline)
          raise Interrupt if status.termsig == INTERRUPT
          raise SignalException, TERMINATE if status.termsig == TERMINATE

          message = "worker #{handle.number} (pid #{handle.pid}) ended unexpectedly (#{describe(status)})"
          raise Error, "#{message}#{hint(status)}"
        end

        # Waits for a worker until the deadline, then kills it. Returns its
        # status.
        def reap(handle, limit)
          return handle.status if handle.status

          loop do
            result = Process.waitpid2(handle.pid, Process::WNOHANG)
            return handle.status = result.last if result
            break if now >= limit

            sleep(0.01)
          end
          Process.kill("KILL", handle.pid)
          handle.status = Process.waitpid2(handle.pid).last
        end

        def deadline = now + @stop_timeout

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def describe(status)
          status.signaled? ? "killed by SIG#{Signal.signame(status.termsig)}" : "exit status #{status.exitstatus}"
        end

        # On macOS a forked child crashes with SIGABRT if a gem initialized
        # Objective-C in the parent.
        def hint(status)
          return "" unless RUBY_PLATFORM.include?("darwin") && status.termsig == Signal.list.fetch("ABRT")

          "; on macOS, a gem that uses Objective-C needs OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (see the Readme)"
        end

        # Ends the feeder and the workers. After a normal end the workers have
        # ended already and are only reaped; otherwise they get SIGTERM and,
        # after the stop timeout, SIGKILL.
        def stop
          @feeder&.kill&.join
          @handles.each(&:close)
          @handles.each { terminate(it) } unless @finished
          limit = deadline
          @handles.each do |handle|
            reap(handle, limit)
            @pipeline.logger.debug { "worker #{handle.number} (pid #{handle.pid}) ended: #{describe(handle.status)}" }
          end
        end
```

- [ ] **Step 4: Run the tests and the suite**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/executor_fork_failures_test.rb`
Expected: PASS, in a few seconds.

Run: `bundle exec rake`
Expected: PASS, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/executor/fork/run.rb test/unit/executor_fork_failures_test.rb
git commit -m "Report dead workers and records that cannot be sent, and kill stuck workers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 7: API, CLI and progress

**Files:**
- Create: `lib/metacrunch/executor.rb`, `test/unit/executor_test.rb`
- Modify: `lib/metacrunch.rb`, `lib/metacrunch/job.rb`, `lib/metacrunch/testing.rb`, `lib/metacrunch/live_stats.rb`, `lib/metacrunch/engine.rb`, `lib/metacrunch/progress.rb`, `lib/metacrunch/cli/run.rb`
- Test: `test/unit/job_test.rb`, `test/unit/testing_test.rb`, `test/unit/engine_monitor_test.rb`, `test/unit/progress_test.rb`, `test/cli/run_test.rb`

**Interfaces:**
- Consumes: `Executor::Inline`, `Executor::Fork` and `Fork.supported?`.
- Produces:
  - `Metacrunch::Executor.for(workers)`: `nil` or `1` gives `Inline`, `N > 1` gives `Fork`, and anything else raises `ArgumentError`.
  - `Executor.auto_workers`.
  - `Job#run(argv, ..., workers: nil)` and `Testing.run(job, ..., workers: nil)`.
  - `LiveStats.new(collector, pipeline, workers: 1)` with `#workers`.
  - `run -w, --workers N|auto`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/executor_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test

  include Override

  def test_picks_inline_for_one_worker_and_fork_for_more
    assert_instance_of Metacrunch::Executor::Inline, Metacrunch::Executor.for(nil)
    assert_instance_of Metacrunch::Executor::Inline, Metacrunch::Executor.for(1)
    assert_equal 3, Metacrunch::Executor.for(3).workers
  end

  def test_refuses_other_numbers
    error = assert_raises(ArgumentError) { Metacrunch::Executor.for(0) }

    assert_equal "workers must be a positive Integer, got 0", error.message
  end

  def test_auto_leaves_a_core_for_the_parent
    counts = [1, 8].map do |cores|
      override(Etc, :nprocessors, -> { cores }) { Metacrunch::Executor.auto_workers }
    end

    assert_equal [1, 7], counts
  end

end
```

`Override#override` returns the value of its block: `yield` is the last expression before `ensure`.

Add to `test/unit/job_test.rb` (and `include ForkVariant::NoWorkerLeft` at the top of the class):

```ruby
  def test_run_with_workers_gives_the_same_records
    target = CollectingSink.new
    job = Metacrunch.job do
      source [1, 2, 3, 4]
      map { it * 2 }
      sink target
    end
    result = job.run([], logger: SILENT, workers: 2)

    assert_equal [:ok, [2, 4, 6, 8]], [result.status, target.records]
  end
```

Add to `test/unit/testing_test.rb` (and `include ForkVariant::NoWorkerLeft`):

```ruby
  def test_runs_jobs_with_workers
    result = Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1, 0, 9], workers: 2)

    assert_equal [:ok_with_failures, [1]], [result.status, result.records]
    assert_equal([[0, "zero"]], result.errors.map { |record, failure| [record, failure.error.message] })
  end
```

Add to `test/unit/engine_monitor_test.rb`, inside the class:

```ruby
  def test_the_monitor_knows_the_number_of_workers
    monitor = RecordingMonitor.new
    engine(build_pipeline { source [1] }, monitor:).run

    assert_equal executor.workers, monitor.live.workers
  end
```

In `test/unit/progress_test.rb`:
- Change the `Live` struct to

```ruby
  Live = Struct.new(:read, :written, :filtered, :rejected, :failed, :source, :limit, :workers)
```

- Add:

```ruby
  def test_shows_the_number_of_workers
    @live.workers = 8
    progress = start(:line)
    advance(2.0, read: 20_000)

    assert_equal "⠙ 00:00:02  8 workers  read 20.0k (10.0k/s)  written 0", progress.line
  end
```

Add to `test/cli/run_test.rb` (and `include Override` and `include ForkVariant::NoWorkerLeft` at the top of the class):

```ruby
  def test_workers_give_the_same_output
    code, stdout, stderr = cli("run", "-w", "2", job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_invalid_worker_counts_are_usage_errors
    zero = cli("run", "-w", "0", job("double.rb"), stdin: "1\n")
    word = cli("run", "--workers", "many", job("double.rb"), stdin: "1\n")

    assert_equal [2, 2], [zero.first, word.first]
    assert_match(/--workers must be a positive number or auto/, word.last)
  end

  def test_auto_workers_leave_a_core_for_the_parent
    seen = []
    choose = lambda do |workers|
      seen << workers
      Metacrunch::Executor::Inline.new
    end
    override(Metacrunch::Executor, :for, choose) { cli("run", "-w", "auto", job("double.rb"), stdin: "1\n") }

    assert_equal [Metacrunch::Executor.auto_workers], seen
  end

  def test_workers_need_fork
    code, _stdout, stderr = override(Metacrunch::Executor::Fork, :supported?, -> { false }) do
      cli("run", "-w", "2", job("double.rb"), stdin: "1\n")
    end

    assert_equal 2, code
    assert_match(/--workers needs Process.fork, which this platform lacks/, stderr)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/executor_test.rb test/unit/job_test.rb test/unit/testing_test.rb test/unit/engine_monitor_test.rb test/unit/progress_test.rb test/cli/run_test.rb`
Expected:
- `undefined method 'for'`;
- `unknown keyword: :workers`;
- `undefined method 'workers'` on `LiveStats`;
- the progress line without `8 workers`;
- `invalid option: -w`.

- [ ] **Step 3: Write `lib/metacrunch/executor.rb`**

```ruby
# frozen_string_literal: true

require "etc"

module Metacrunch
  # Executors push the source records through the steps; see Engine.
  module Executor

    # Inline for nil or 1, else Fork with that many workers.
    def self.for(workers)
      unless workers.nil? || (workers.is_a?(Integer) && workers.positive?)
        raise ArgumentError, "workers must be a positive Integer, got #{workers.inspect}"
      end

      workers.nil? || workers == 1 ? Inline.new : Fork.new(workers:)
    end

    # The workers for "auto": one per core but one, which the parent needs
    # for the source, the sinks and Marshal.
    def self.auto_workers = [Etc.nprocessors - 1, 1].max

  end
end
```

In `lib/metacrunch.rb`, insert before `require_relative "metacrunch/executor/inline"`:

```ruby
require_relative "metacrunch/executor"
```

- [ ] **Step 4: Pass workers through Job, Testing, LiveStats and Progress**

`lib/metacrunch/job.rb`, replace `run`:

```ruby
    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments and lets errors from the recipe itself (e.g. a component
    # constructor or a DSL mistake) propagate. Errors while the pipeline
    # runs end up in the Result. limit stops after that many records;
    # workers runs the steps in that many processes.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil)
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:) }, logger:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
    end
```

`lib/metacrunch/testing.rb`:
- Change the signature to `def run(job, params: {}, source: nil, logger: Logger.new(nil), workers: nil)`.
- Change the engine line to `result = Engine.new(pipeline, executor: Executor.for(workers)).run`.
- Extend the method comment with: `workers: run the steps in that many processes, to check that the job's records cross process boundaries.`

`lib/metacrunch/live_stats.rb`:
- Change `initialize` to:

```ruby
    # workers: the number of processes that run steps.
    def initialize(collector, pipeline, workers: 1)
      @collector = collector
      @pipeline = pipeline
      @workers = workers
    end

    attr_reader :workers
```

`lib/metacrunch/engine.rb`, in `monitored`:

```ruby
      @monitor.start(LiveStats.new(@stats, @pipeline, workers: @executor.workers))
```

`lib/metacrunch/progress.rb`:
- Replace `line` with:

```ruby
    # The status: progress (bar or spinner), elapsed time, ETA, the number
    # of workers and counts.
    def line
      now = @clock.call
      read = @live.read
      [head(now - @started, fraction(read)), workers, counts(read, rate(now, read))].compact.join("  ")
    end
```

- Add to the private methods:

```ruby
    def workers
      count = @live.workers
      "#{count} workers" if count && count > 1
    end
```

- [ ] **Step 5: Add `-w` to `run`**

In `lib/metacrunch/cli/run.rb`:

Add at the top, after the frozen string literal comment:

```ruby
require "etc"
```

In `define_options`, after the `--max-errors` option:

```ruby
        parser.on("-w", "--workers N", "Run the steps in N processes; auto: one per core but one") do |value|
          @workers = worker_count(value)
        end
```

In `execute_job`, replace the `Engine.new` line with:

```ruby
        monitor = progress(options.records_to_stdout?(built))
        result = Engine.new(pipeline, executor: Executor.for(@workers), monitor:).run
```

Add a private method:

```ruby
      # The value of --workers as a number of processes.
      def worker_count(value)
        count = value == "auto" ? Executor.auto_workers : Integer(value, 10, exception: false)
        raise UsageError, "--workers must be a positive number or auto" unless count&.positive?
        if count > 1 && !Executor::Fork.supported?
          raise UsageError, "--workers needs Process.fork, which this platform lacks"
        end

        count
      end
```

Add the `-w` line to the usage block in the comment or help text if the command lists its options there. `run --help` comes from `OptionParser`, so it lists `-w` already.

- [ ] **Step 6: Run the tests and the suite**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }; ARGV.clear' test/unit/executor_test.rb test/unit/job_test.rb test/unit/testing_test.rb test/unit/engine_monitor_test.rb test/unit/progress_test.rb test/cli/run_test.rb`
Expected: PASS.

Run: `bundle exec rake`
Expected: PASS, RuboCop clean.

- [ ] **Step 7: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/executor.rb lib/metacrunch/job.rb lib/metacrunch/testing.rb \
  lib/metacrunch/live_stats.rb lib/metacrunch/engine.rb lib/metacrunch/progress.rb lib/metacrunch/cli/run.rb \
  test/unit/executor_test.rb test/unit/job_test.rb test/unit/testing_test.rb test/unit/engine_monitor_test.rb \
  test/unit/progress_test.rb test/cli/run_test.rb
git commit -m "Add --workers to run and workers: to Job#run and Testing.run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 8: End-to-end tests, measurements and documentation

**Files:**
- Create: `test/fixtures/jobs/sanitize.rb`, `test/cli/exe_workers_test.rb`
- Modify: `bench/executor.rb`, `Readme.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-11-metacrunch-ng-parallel-executor-design.md`

**Interfaces:**
- Consumes: everything above, through `exe/metacrunch`.
- Produces: nothing new in the library.

- [ ] **Step 1: Write the fixture job and the subprocess tests**

Create `test/fixtures/jobs/sanitize.rb`:

```ruby
# frozen_string_literal: true

# Sanitizes titles like ris2fis: marks what it changes, rejects records
# without a title and fails on a broken year. Used to compare runs with and
# without workers.
Metacrunch.job do
  source id: ->(record) { record["id"] }
  map do |record, ctx|
    title = record["title"].to_s
    clean = title.unicode_normalize(:nfkc).gsub(/\s+/, " ").strip
    ctx.mark("Whitespace", value: title) if clean != title
    record.merge("title" => clean)
  end
  reject("No title") { it["title"].empty? }
  map { it.merge("year" => Integer(it["year"])) }
  on_error :skip
end
```

Create `test/cli/exe_workers_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "timeout"
require "tmpdir"

class ExeWorkersTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  JOBS = File.join(ROOT, "test", "fixtures", "jobs")

  def test_workers_write_the_same_files_as_inline
    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.jsonl")
      File.write(input, (1..300).map { record(it) }.join)
      inline = run_sanitize(dir, "inline", input)
      forked = run_sanitize(dir, "forked", input, "-w", "3")

      assert_equal inline, forked
      assert_equal [234, 42, 24], inline.map { it.lines.size }
    end
  end

  def test_a_closed_pipe_ends_the_job_by_sigpipe
    reader, writer = IO.pipe
    pid = Process.spawn(*command("run", "-w", "2", fixture("endless.rb")), out: writer, err: File::NULL,
                                                                             pgroup: true)
    writer.close
    first = reader.gets
    reader.close
    _pid, status = Timeout.timeout(30) { Process.wait2(pid) }

    assert_equal ["{\"n\":1}\n", Signal.list.fetch("PIPE")], [first, status.termsig]
    assert_group_ended(pid)
  end

  def test_sigint_to_the_process_group_ends_the_job_by_sigint
    status, pid = signal_running_job("INT", group: true)

    assert_equal Signal.list.fetch("INT"), status.termsig
    assert_group_ended(pid)
  end

  def test_sigterm_to_the_parent_ends_the_job_by_sigterm
    status, pid = signal_running_job("TERM", group: false)

    assert_equal Signal.list.fetch("TERM"), status.termsig
    assert_group_ended(pid)
  end

  private

  def command(*)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *]
  end

  def fixture(name) = File.join(JOBS, name)

  # Titles of every 7th record are blank, years of every 11th are broken:
  # 42 rejected, 24 failed (multiples of 77 are rejected first), 234 written.
  def record(number)
    title = (number % 7).zero? ? "  " : "Title  #{number} "
    year = (number % 11).zero? ? "x" : "2020"
    "#{JSON.generate({"id" => number, "title" => title, "year" => year})}\n"
  end

  # Runs sanitize.rb and returns its output, rejects and errors files.
  def run_sanitize(dir, name, input, *options)
    files = ["out", "rejects", "errors"].map { File.join(dir, "#{name}.#{it}.jsonl") }
    arguments = ["run", *options, "-i", input, "-o", files[0], "--rejects", files[1], "--errors", files[2]]
    _stdout, stderr, status = Open3.capture3(*command(*arguments, fixture("sanitize.rb")))
    raise "sanitize.rb failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    files.map { File.read(it) }
  end

  # Starts endless.rb with two workers in its own process group, waits
  # until the workers run, sends the signal and returns the exit status
  # and the pid, which is also the process group.
  def signal_running_job(signal, group:)
    errors, writer = IO.pipe
    pid = Process.spawn(*command("run", "-v", "-w", "2", "-o", File::NULL, fixture("endless.rb")),
                        err: writer, pgroup: true)
    writer.close
    started = Timeout.timeout(30) { errors.each_line.find { it.include?("started 2 workers") } }
    raise "endless.rb did not start its workers" unless started

    drain = Thread.new { errors.read }
    Process.kill(signal, group ? -pid : pid)
    _pid, status = Timeout.timeout(30) { Process.wait2(pid) }
    drain.join
    [status, pid]
  ensure
    errors&.close
  end

  # No process of the job's process group is left; the workers are in it.
  def assert_group_ended(pgid)
    Process.kill(0, -pgid)
    flunk("a process of the group #{pgid} is left")
  rescue Errno::ESRCH
    pass
  end

end
```

- [ ] **Step 2: Run the subprocess tests**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/exe_workers_test.rb`
Expected: PASS. If a test hangs, `Timeout` ends it after 30 seconds. Do not raise the timeout. Find out with `-v` which worker did not end, then fix `Run#stop` or `Worker.main`.

- [ ] **Step 3: Extend the benchmark**

Replace `bench/executor.rb` with:

```ruby
# frozen_string_literal: true

# Measures the engine and its executors; not part of the test suite.
#
#   bundle exec ruby -Ilib bench/executor.rb inline|expensive|cheap|jsonl
#
# inline:    1 M records through 10 map steps, without sink, observer or
#            monitor: time per step and record (best of three runs) and
#            allocations per record.
# expensive: 50 k records with string work like ris2fis (ROUNDS=40, about
#            28 µs per record inline), inline and with 8 workers.
# cheap:     1 M records through one cheap map, inline and with 8 workers.
# jsonl:     1 M JSON Lines through a job without steps (exe/metacrunch),
#            inline and with -w 8.

require "metacrunch"
require "open3"
require "tmpdir"

module Bench

  ROOT = File.expand_path("..", __dir__)
  WORKERS = 8

  # Counts what it gets, so records travel back from the workers.
  class Counter

    attr_reader :count

    def initialize
      @count = 0
    end

    def write(_record)
      @count += 1
    end

  end

  module_function

  def build(&recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash({}) }, logger: Logger.new(nil))
    builder.instance_exec(&recipe)
    builder.build
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def inline
    records = Array.new(1_000_000) { it }
    pipeline = build do
      source records
      10.times { map { it } }
    end
    run = -> { Metacrunch::Engine.new(pipeline).run }
    run.call
    best = Array.new(3) { seconds(&run) }.min
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    run.call
    allocations = GC.stat(:total_allocated_objects) - allocated
    format("inline: %<ns>.1f ns per step and record, %<allocations>.1f allocations per record",
           ns: best * 1e9 / (records.size * 10), allocations: allocations.fdiv(records.size))
  end

  def expensive
    rounds = Integer(ENV.fetch("ROUNDS", "40"))
    records = Array.new(50_000) { {"id" => it, "text" => "Ein  Titel mit   Leerraum #{it} " * 4} }
    compare("expensive", records) do |text|
      rounds.times { text = text.unicode_normalize(:nfkc).gsub(/\s+/, " ") }
      text
    end
  end

  def cheap
    compare("cheap", Array.new(1_000_000) { {"id" => it, "text" => "x"} }) { it }
  end

  # Runs the records through one map on "text", inline and with workers.
  def compare(name, records, &work)
    rates = [nil, WORKERS].map do |workers|
      pipeline = build do
        source records
        map { it.merge("text" => work.call(it["text"])) }
        sink Counter.new
      end
      records.size / seconds { Metacrunch::Engine.new(pipeline, executor: Metacrunch::Executor.for(workers)).run }
    end
    format("%<name>s: %<us>.1f µs per record inline; inline %<inline>.0f records/s, %<workers>d workers " \
           "%<forked>.0f records/s (%<factor>.1f×)",
           name:, us: 1e6 / rates[0], inline: rates[0], workers: WORKERS, forked: rates[1],
           factor: rates[1] / rates[0])
  end

  def jsonl
    Dir.mktmpdir do |dir|
      input = File.join(dir, "in.jsonl")
      File.write(input, Array.new(1_000_000) { "{\"id\":#{it},\"title\":\"Titel #{it}\"}\n" }.join)
      job = File.join(dir, "pass.rb")
      File.write(job, "# frozen_string_literal: true\n\nMetacrunch.job {}\n")
      rates = [[], ["-w", WORKERS.to_s]].map do |options|
        command = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), "run",
                   *options, "-i", input, "-o", File::NULL, job]
        1_000_000 / seconds { Open3.capture3(*command) }
      end
      format("jsonl: inline %<inline>.0f records/s, -w %<workers>d %<forked>.0f records/s",
             inline: rates[0], workers: WORKERS, forked: rates[1])
    end
  end

end

puts Bench.public_send(ARGV.fetch(0, "inline"))
```

Run each mode: `bundle exec ruby -Ilib bench/executor.rb inline`, then `expensive`, `cheap` and `jsonl`.

`expensive` must report about 28 µs per record inline. If it does not, set `ROUNDS` so that it does, and change the default in the script to that value. Expected for `expensive`: at least 4× with 8 workers. If it falls short, profile the parent: `Marshal.load` and the sink run in its main thread, `Marshal.dump` and the source in the feeder. Report the numbers before tuning anything.

- [ ] **Step 4: Record the measurements in the spec**

In `docs/superpowers/specs/2026-10-11-metacrunch-ng-parallel-executor-design.md`:
- Fill the "Result" column of the table in §11 with the four lines the benchmark printed. Use the best of two runs for `inline`.
- Change `- Status: draft` to `- Status: approved; implemented`.

- [ ] **Step 5: Document workers in the Readme**

In `Readme.md`, add this row to the options table under "Running jobs", after `--max-errors`:

```markdown
| `-w`, `--workers N\|auto` | Run the steps in N worker processes (see Workers) |
```

Add a section after "### Pipes". Replace `<FACTOR>` with the factor `bench/executor.rb expensive` printed, e.g. `5`:

````markdown
### Workers

`-w N` (`--workers N`) runs the steps in N worker processes; the source and the sinks stay in the main process.
`-w auto` uses one worker per core but one. Records reach the sinks, the `rejects` and `errors` sinks and the log in
source order, so a job gives the same results with and without workers.

```
$ metacrunch run -w 8 jobs/sanitize.rb data/ris.json
```

Workers pay off when the steps are expensive. With about 28 µs of work per record, 8 workers were about <FACTOR>×
as fast. With cheap steps (a few `map`s over Hashes), sending records between processes costs more than it saves,
and the job gets slower.

- Records travel between the processes with `Marshal`. Records, the `value:` of marks and rejections and `ctx.store`
  must be Marshal-able. A source that reads XML should yield Strings and leave the parsing (Nokogiri) to a step. An
  exception that cannot be sent is replaced by a `Metacrunch::WorkerError` with the original class and message.
- Each worker opens and closes the step components itself (`open`/`close`), so every worker has its own
  connections. Data that the workers only read, such as lookup tables, belongs at job level or in a `before` hook:
  the workers inherit it from the main process. Steps are opened after the `before` hooks, also without workers.
- Records are sent in batches of 100, so a slow source (records trickling in through a pipe) delays a record until
  its batch is full.
- After an abort in the middle of a batch, the stats may count up to 99 records after the point of abort; the
  records in the sinks are exact. With `profile true`, step times are summed over all workers.
- `trace` always runs without workers. In tests, `Metacrunch::Testing.run(job, source: records, workers: 2)` checks
  that a job's records cross the process boundary.

On macOS, a worker can crash right after it starts if a gem initialized Objective-C in the main process (known for
`pg` with GSSAPI and for proxy lookups in `net/http`). The error then names SIGABRT. Set this variable before you
start the job:

```
$ export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```
````

- [ ] **Step 6: Note the change in the CHANGELOG**

In `CHANGELOG.md`, under `### Added`, append:

```markdown
- `metacrunch run -w N` (`--workers N|auto`) runs the steps in N worker processes, with the results in source
  order; `Job#run`, `Testing.run` and `Engine` take workers as well. Step components are opened after the `before`
  hooks.
```

- [ ] **Step 7: Run everything**

Run: `bundle exec rake`
Expected: PASS, coverage at least 95 % lines and 90 % branches, RuboCop clean.

- [ ] **Step 8: Commit**

```bash
git add test/fixtures/jobs/sanitize.rb test/cli/exe_workers_test.rb bench/executor.rb Readme.md CHANGELOG.md \
  docs/superpowers/specs/2026-10-11-metacrunch-ng-parallel-executor-design.md
git commit -m "Test workers end to end, document them and record measurements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```
