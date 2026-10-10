# metacrunch-ng CLI and pipes (sub-project 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the minimal CLI with subcommands (`run`, `check`, `trace`, `new`, `help`) and make jobs work as stages of Unix pipes with JSON Lines, a filter default, progress display and per-step tracing.

**Architecture:** The core gains small seams: `InvalidRecord` (a source reports an unreadable record), an optional source, `limit`/`select` in the executor, a `monitor` with `LiveStats` and a signal-safe close. `JsonLines` provides a reader and two writers that turn `EPIPE` into SIGPIPE. The CLI is a dispatcher plus one class per command on stdlib `OptionParser`; `RunOptions` rewrites a built `Pipeline` (replaced source/sinks, filter default, limit, error policy). `Progress` (monitor) and `Trace` (observer + renderer) are library units that write to injected IOs.

**Tech Stack:** Ruby 4.0, standard library and default gems (`optparse`, `json`, `zlib`, `io/console`, `fileutils`, `pathname`), `logger` gem, Minitest, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** `docs/superpowers/specs/2026-10-10-metacrunch-ng-cli-pipes-design.md` (builds on `docs/superpowers/specs/2026-10-10-metacrunch-ng-core-design.md`)

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version stays `5.0.0.pre`.
- Runtime dependency: `logger` only. No new gems; standard library and default gems only.
- Library files are loaded with `require_relative`.
- Every Ruby file starts with `# frozen_string_literal: true` (also test fixtures and generated templates).
- The library never calls `exit`. Commands never use `$stdin`, `$stdout` or `$stderr` directly; they use the streams injected into `Metacrunch::Cli`. Only `JsonLines` resolves `"-"` to `$stdin`/`$stdout`.
- Lint: `bundle exec rubocop` must be clean at the end of every task (`bundle exec rubocop -a` may fix layout).
- Style that ruby.yml enforces: double quotes (also inside interpolation), `{a: 1}` without spaces inside braces, `[:a, :b]`/`["a", "b"]` instead of `%i[]`/`%w[]`, blank lines at the start and end of class/module bodies except for pure namespaces, max line length 120, at most 3 assertions per Minitest test, a blank line before the first assertion.
- RuboCop 1.92 cops to keep in mind: `Naming/PredicateMethod` (a method that returns only `true`/`false` ends with `?`), `Style/FormatStringToken` (at most one unannotated `format` placeholder; use `%<name>s` or `ljust`), `Lint/ConstantDefinitionInBlock` (no constants inside `Data.define do ... end`).
- Tests: Minitest. Single file: `bundle exec ruby -w -Ilib -Itest <file>`. Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake`.
- Repo docs, code comments and commit messages are in English.
- Every commit message ends with these two lines:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
  ```

## Review Focus

Inputs and conditions the spec implies but does not spell out, most likely to bite a user first. Each has a test in the task named in brackets.

1. **JSON Lines with `\r\n` line endings or without a final newline** (exports from Windows tools, `printf` without `\n`): parsed like any other line. [Task 5]
2. **A UTF-8 byte order mark at the start of a JSON Lines file**: ignored instead of turning the first record into an `InvalidRecord`. [Task 5]
3. **Empty stdin for a filter job** (`< /dev/null`, an upstream job that emits nothing): exit 0, no output, no waiting. [Task 8]
4. **Sources whose size is unknown or infinite** (`(1..)`, lazy enumerators, `Float::INFINITY`): the progress display shows the spinner instead of failing. [Task 10]
5. **The same file spelled two ways** (`out/bad.jsonl` and `out/./bad.jsonl`): recognized as one file, both for sharing a writer and for conflicts. [Task 7]

---

## File Structure

```
lib/metacrunch.rb                  requires invalid_record, live_stats, json_lines
lib/metacrunch/invalid_record.rb   InvalidRecord (Data: raw, error)                     Task 1
lib/metacrunch/step.rb             SOURCE_STEP = "source"                               Task 1
lib/metacrunch/stats_collector.rb  failed/rejected totals, source_failed, live readers   Tasks 1, 4
lib/metacrunch/builder.rb          reserved step name, optional source, source id:      Tasks 1, 2
lib/metacrunch/engine.rb           InvalidRecord, observer order, source check,
                                   limit/select, monitor, signals while closing         Tasks 1, 2, 3, 4, 6
lib/metacrunch/pipeline.rb         new field limit                                      Task 3
lib/metacrunch/executor/inline.rb  limit, select                                        Task 3
lib/metacrunch/job.rb              Job#run(limit:)                                      Task 3
lib/metacrunch/testing.rb          ArgumentError without source                         Task 2
lib/metacrunch/live_stats.rb       LiveStats                                            Task 4
lib/metacrunch/json_lines.rb       JsonLines::Reader, Writer, ContextWriter             Tasks 5, 6
lib/metacrunch/errors.rb           UsageError                                           Task 7
lib/metacrunch/sink_adapter.rb     batch reader                                         Task 11
lib/metacrunch/params.rb           job no longer reserved                               Task 8
lib/metacrunch/cli.rb              dispatcher (rewritten)                               Task 8
lib/metacrunch/cli/run_options.rb  RunOptions                                           Task 7
lib/metacrunch/cli/command.rb      Command base                                         Task 8
lib/metacrunch/cli/job_command.rb  JobCommand base                                      Task 8
lib/metacrunch/cli/run.rb          RunCommand                                           Tasks 8, 9, 10
lib/metacrunch/progress.rb         Progress, Progress::Output                           Task 10
lib/metacrunch/cli/check.rb        CheckCommand                                         Task 11
lib/metacrunch/diff.rb             Diff                                                 Task 12
lib/metacrunch/trace.rb            Trace (observer, selection, tree)                    Task 13
lib/metacrunch/trace/renderer.rb   Trace::Renderer                                      Task 13
lib/metacrunch/cli/trace.rb        TraceCommand                                         Task 14
lib/metacrunch/cli/new.rb          NewCommand                                           Task 15
exe/metacrunch                     comment only                                         Task 8
test/support/cli_helper.rb         CliHelper (in-process CLI runs)                      Task 8
test/unit/..., test/cli/...        see tasks
test/fixtures/jobs/double.rb, verbose.rb (Task 8), slow.rb (Task 10), unopenable.rb (Task 11),
                   emit.rb, tag.rb, endless.rb (Task 16)
Readme.md, CHANGELOG.md, spec §13  Task 16
```

---

### Task 1: Invalid records and source failures

A source may yield `Metacrunch::InvalidRecord` for a record it could not read. The engine treats it as a failure of the pseudo-step `"source"`. Failed steps now call the observer's `step_out` after the error policy was applied, so an observer sees `ctx.failure` under `:skip`.

**Files:**
- Create: `lib/metacrunch/invalid_record.rb`, `test/unit/engine_invalid_record_test.rb`
- Modify: `lib/metacrunch.rb`, `lib/metacrunch/step.rb`, `lib/metacrunch/builder.rb`, `lib/metacrunch/stats_collector.rb`, `lib/metacrunch/engine.rb`, `test/unit/builder_test.rb`, `test/unit/stats_collector_test.rb`

**Interfaces:**
- Produces: `Metacrunch::InvalidRecord` (`Data`: `raw`, `error`); `Metacrunch::SOURCE_STEP == "source"`; `StatsCollector#source_failed(error)`, `StatsCollector#failed_total` (now a counter, same name); observer events `step_in("source", raw, ctx)` / `step_out("source", [], ctx)` for invalid records; `step_out` of a failed step after `ctx.failure` is set (under `:skip`).

- [ ] **Step 1: Write the failing tests**

`test/unit/engine_invalid_record_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineInvalidRecordTest < Minitest::Test

  include PipelineHelper

  # Records step events and, at step_out, the step of ctx.failure.
  class FailureObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def step_in(step, record, _ctx)
      @events << [:in, step, record]
    end

    def step_out(step, outputs, ctx)
      @events << [:out, step, outputs, ctx.failure&.step]
    end

  end

  def test_invalid_records_abort_the_run_by_default
    bad = invalid_record
    result = run_pipeline do
      source [1, bad, 3]
      map { it * 2 }
    end
    error = result.error

    assert_equal [:aborted, 2], [result.status, result.stats.read]
    assert_equal ["source", nil, 2], [error.step, error.record_id, error.position]
    assert_equal "step source failed at position 2: ArgumentError: unreadable", error.message
  end

  def test_invalid_records_go_to_the_errors_sink_under_skip
    bad = invalid_record
    target = CollectingSink.new
    failures = CollectingSink.new
    result = run_pipeline do
      source [1, bad, 3], id: ->(record) { record * 100 }
      map { it * 2 }
      sink target
      errors failures
      on_error :skip
    end

    assert_equal [:ok_with_failures, [2, 6]], [result.status, target.records]
    assert_equal ["{broken"], failures.records
    assert_equal([["source", nil, 2]], failures.contexts.map { [it.failure.step, it.id, it.position] })
  end

  def test_invalid_records_count_as_failed_without_a_step_entry
    bad = invalid_record
    result = run_pipeline do
      source [bad]
      map { it }
      on_error :skip
    end

    assert_equal({"ArgumentError" => 1}, result.stats.failed)
    assert_equal ["map#1"], result.stats.steps.keys
    assert_equal 0, result.stats.steps["map#1"].input
  end

  def test_max_errors_counts_invalid_records
    bad = invalid_record
    result = run_pipeline do
      source [bad, bad]
      on_error :skip, max_errors: 1
    end

    assert_equal :aborted, result.status
    assert_equal "2 failed records exceed max_errors 1", result.error.message
  end

  def test_the_observer_sees_invalid_records_as_the_source_step
    bad = invalid_record
    observer = FailureObserver.new
    pipeline = build_pipeline do
      source [bad]
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline, observer:).run

    assert_equal [[:in, "source", "{broken"], [:out, "source", [], "source"]], observer.events
  end

  def test_the_observer_sees_the_failure_of_a_step_under_skip
    observer = FailureObserver.new
    pipeline = build_pipeline do
      source [1]
      map { raise "broken" }
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline, observer:).run

    assert_equal [[:in, "map#1", 1], [:out, "map#1", [], "map#1"]], observer.events
  end

  private

  def invalid_record
    Metacrunch::InvalidRecord.new(raw: "{broken", error: ArgumentError.new("unreadable"))
  end

end
```

In `test/unit/builder_test.rb`, add to `INVALID_RECIPES` (after `"duplicate_step_name"`):

```ruby
    "reserved_step_name" => proc { source([]); map(name: "source") { it } },
```

In `test/unit/stats_collector_test.rb`, add:

```ruby
  def test_source_failures_are_counted_without_a_step
    collector = Metacrunch::StatsCollector.new(["map#1"])
    collector.source_failed(ArgumentError.new("unreadable"))
    stats = collector.snapshot

    assert_equal 1, collector.failed_total
    assert_equal [{"ArgumentError" => 1}, 0], [stats.failed, stats.steps["map#1"].failed]
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_invalid_record_test.rb`
Expected: errors with `NameError: uninitialized constant Metacrunch::InvalidRecord`.

- [ ] **Step 3: Implement**

`lib/metacrunch/invalid_record.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  # Yielded by a source for a record it could not read, e.g. a line that is
  # not valid JSON. raw is what the source read, error why it failed. The
  # engine counts it as a failure of the pseudo-step "source" under the
  # job's error policy.
  InvalidRecord = Data.define(:raw, :error)

end
```

`lib/metacrunch.rb`: add `require_relative "metacrunch/invalid_record"` directly after `require_relative "metacrunch/errors"`.

`lib/metacrunch/step.rb`: below `STEP_KINDS`, add:

```ruby
  # Failures of the source (InvalidRecord) are reported under this name; no
  # step may use it.
  SOURCE_STEP = "source"
```

`lib/metacrunch/builder.rb`, in `add_step`, after the line `name = (name || "#{kind}##{@steps.size + 1}").to_s`:

```ruby
      raise ArgumentError, "the step name #{SOURCE_STEP} is reserved" if name == SOURCE_STEP
```

`lib/metacrunch/stats_collector.rb`:
- add `attr_reader :failed_total` below `class StatsCollector` (with the usual blank line), initialize `@failed_total = 0` in `initialize`;
- replace `step_failed` and add `source_failed`:

```ruby
    def step_failed(name, error)
      @steps.fetch(name).failed += 1
      source_failed(error)
    end

    # A record the source could not read (InvalidRecord). It has no step,
    # so only the job-level counts change.
    def source_failed(error)
      @failed[error.class.name] += 1
      @failed_total += 1
    end
```

- delete the old `def failed_total ... end` method.

`lib/metacrunch/engine.rb`:

Replace `ingest`:

```ruby
    def ingest(chain, record, position)
      @stats.count_read
      return fail_invalid(record, position) if record.is_a?(InvalidRecord)

      id = @pipeline.id_extractor&.call(record)
      chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

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
```

In `single_link`, replace

```ruby
        rescue *RECOVERABLE => e
          @observer&.step_out(step.name, [], ctx)
          next fail_record(step, record, ctx, e)
        end
```

with

```ruby
        rescue *RECOVERABLE => e
          next fail_observed(step, record, ctx, e)
        end
```

Replace `fail_record` with these three methods:

```ruby
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

    def handle_failure(name, record, ctx, error)
      step_error = StepError.new(step: name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_error == :abort

      ctx.failure = Failure.new(error:, step: name)
      ctx.logger.error(step_error.message)
      @pipeline.errors&.write(record, ctx)
      check_max_errors(step_error)
    end
```

(`flat_map_link` already calls `step_out` in its `ensure`, after `fail_record`; it stays as it is.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_invalid_record_test.rb && bundle exec rake`
Expected: all tests pass, coverage thresholds met, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/invalid_record.rb lib/metacrunch/step.rb lib/metacrunch/builder.rb \
  lib/metacrunch/stats_collector.rb lib/metacrunch/engine.rb test/unit/engine_invalid_record_test.rb \
  test/unit/builder_test.rb test/unit/stats_collector_test.rb
git commit -m "Let sources report invalid records as failures of the source

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 2: Optional source

A job may leave out `source` (the CLI will read stdin) or declare only `source id: ...`. The library stays explicit: the engine and `Testing.run` refuse a pipeline without source.

**Files:**
- Modify: `lib/metacrunch/builder.rb`, `lib/metacrunch/engine.rb`, `lib/metacrunch/testing.rb`, `test/unit/builder_test.rb`, `test/unit/engine_test.rb`, `test/unit/testing_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Builder#source(enumerable = nil, id: nil)`; `Pipeline#source` may be `nil`; `Engine#run` raises `ArgumentError, "the pipeline has no source"`; `Testing.run` raises `ArgumentError, "the job has no source; pass source:"`.

- [ ] **Step 1: Write the failing tests**

In `test/unit/builder_test.rb`, in `INVALID_RECIPES`, replace the line `"missing_source" => proc { map { it } },` with:

```ruby
    "empty_source" => proc { source },
    "second_source_after_an_id" => proc { source(id: ->(record) { record }); source([]) },
```

and add:

```ruby
  def test_a_job_may_declare_only_an_id_extractor_or_no_source
    extractor = ->(record) { record["id"] }
    with_id = build_pipeline do
      source id: extractor
      map { it }
    end
    without = build_pipeline { map { it } }

    assert_nil with_id.source
    assert_same extractor, with_id.id_extractor
    assert_nil without.source
  end
```

In `test/unit/engine_test.rb`, add:

```ruby
  def test_a_pipeline_without_source_cannot_run
    pipeline = build_pipeline { map { it } }
    error = assert_raises(ArgumentError) { Metacrunch::Engine.new(pipeline).run }

    assert_equal "the pipeline has no source", error.message
  end
```

In `test/unit/testing_test.rb`, add:

```ruby
  def test_jobs_without_a_source_need_one
    job = Metacrunch.job { map { it * 2 } }
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(job) }

    assert_equal "the job has no source; pass source:", error.message
    assert_equal [2], Metacrunch::Testing.run(job, source: [1]).records
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/builder_test.rb && bundle exec ruby -w -Ilib -Itest test/unit/engine_test.rb`
Expected: failures (`ArgumentError: a job needs a source`, `source must respond to #each, got nil`).

- [ ] **Step 3: Implement**

`lib/metacrunch/builder.rb`: in `initialize`, add `@source_declared = false` after `@source = nil`. Replace `source`:

```ruby
    # With an object: the source. With only id: the job reads the default
    # input of the CLI (JSON Lines from stdin) with this id extractor.
    def source(enumerable = nil, id: nil)
      use!
      raise ArgumentError, "source already defined" if @source_declared
      raise ArgumentError, "source needs an object with #each or id:" if enumerable.nil? && id.nil?
      unless enumerable.nil? || enumerable.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{enumerable.inspect}"
      end

      @id_extractor = id && Callable.ensure_callable!(id, "id:")
      @source = enumerable
      @source_declared = true
      nil
    end
```

In `build`, delete the line `raise ArgumentError, "a job needs a source" unless @source`.

`lib/metacrunch/engine.rb`, first line of `run`:

```ruby
      raise ArgumentError, "the pipeline has no source" unless @pipeline.source
```

`lib/metacrunch/testing.rb`, in `run`, replace

```ruby
      pipeline = pipeline.with(source: source || pipeline.source, **adapters)
```

with

```ruby
      source ||= pipeline.source
      raise ArgumentError, "the job has no source; pass source:" unless source

      pipeline = pipeline.with(source:, **adapters)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/builder.rb lib/metacrunch/engine.rb lib/metacrunch/testing.rb \
  test/unit/builder_test.rb test/unit/engine_test.rb test/unit/testing_test.rb
git commit -m "Allow jobs without source and source with only an id extractor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 3: Limit and selection

`Pipeline#limit` stops a run after N records; `Engine.new(select:)` lets `trace` pick records. Both live in `Executor::Inline`.

**Files:**
- Create: `test/unit/engine_selection_test.rb`
- Modify: `lib/metacrunch/pipeline.rb`, `lib/metacrunch/builder.rb`, `lib/metacrunch/executor/inline.rb`, `lib/metacrunch/engine.rb`, `lib/metacrunch/job.rb`, `test/unit/job_test.rb`

**Interfaces:**
- Produces: `Pipeline#limit` (Integer ≥ 1 or `nil`); `Executor::Inline#run(source, limit: nil, select: nil) { |record, position| }`; `Engine.new(pipeline, executor:, observer:, select:)` where `select` is `->(record, position) { true/false }`; `Job#run(argv = [], env:, logger:, observer:, limit: nil)`. `limit` counts the records pushed into the chain (selected records); unselected records are not counted as read.

- [ ] **Step 1: Write the failing tests**

`test/unit/engine_selection_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineSelectionTest < Minitest::Test

  include PipelineHelper

  # Counts the records it yields and notes when its each has ended.
  class TrackingSource

    attr_reader :yielded, :finished

    def initialize(records)
      @records = records
      @yielded = 0
      @finished = false
    end

    def each
      @records.each do |record|
        @yielded += 1
        yield record
      end
    ensure
      @finished = true
    end

  end

  def test_limit_stops_after_n_source_records
    tracking = TrackingSource.new([1, 2, 3, 4])
    target = CollectingSink.new
    pipeline = build_pipeline do
      source tracking
      sink target
    end
    result = Metacrunch::Engine.new(pipeline.with(limit: 2)).run

    assert_equal [:ok, [1, 2]], [result.status, target.records]
    assert_equal [2, true], [tracking.yielded, tracking.finished]
  end

  def test_limit_counts_source_records_not_flat_map_outputs
    target = CollectingSink.new
    pipeline = build_pipeline do
      source [1, 2]
      flat_map { [it, it] }
      sink target
    end
    Metacrunch::Engine.new(pipeline.with(limit: 1)).run

    assert_equal [1, 1], target.records
  end

  def test_select_skips_records_without_processing_them
    target = CollectingSink.new
    seen = []
    pipeline = build_pipeline do
      source ["a", "b", "c"]
      map(&:upcase)
      sink target
    end
    select = lambda do |record, position|
      seen << [record, position]
      position != 2
    end
    result = Metacrunch::Engine.new(pipeline, select:).run

    assert_equal ["A", "C"], target.records
    assert_equal [["a", 1], ["b", 2], ["c", 3]], seen
    assert_equal 2, result.stats.read
  end

  def test_limit_counts_selected_records
    tracking = TrackingSource.new((1..10).to_a)
    target = CollectingSink.new
    pipeline = build_pipeline do
      source tracking
      sink target
    end
    Metacrunch::Engine.new(pipeline.with(limit: 2), select: ->(_record, position) { position.even? }).run

    assert_equal [[2, 4], 4], [target.records, tracking.yielded]
  end

  def test_invalid_limits_are_rejected
    pipeline = build_pipeline { source [1] }
    error = assert_raises(ArgumentError) { Metacrunch::Engine.new(pipeline.with(limit: 0)).run }

    assert_equal "limit must be a positive Integer, got 0", error.message
  end

end
```

In `test/unit/job_test.rb`, add:

```ruby
  def test_run_accepts_a_limit
    job = Metacrunch.job { source [1, 2, 3] }

    assert_equal 2, job.run([], logger: Logger.new(nil), limit: 2).stats.read
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_selection_test.rb`
Expected: errors (`ArgumentError: unknown keyword: :limit` from `Pipeline#with`, `unknown keyword: :select`).

- [ ] **Step 3: Implement**

`lib/metacrunch/pipeline.rb`:

```ruby
  # Immutable description of one run, built from a job's recipe by Builder.
  # sink, rejects and errors are SinkAdapter instances or nil. source is nil
  # for jobs that read the CLI's default input. limit stops the run after
  # that many records (nil: no limit).
  Pipeline = Data.define(
    :source, :id_extractor, :steps, :sink, :rejects, :errors,
    :on_error, :max_errors, :profile, :before_hooks, :after_hooks, :params, :logger, :limit
  )
```

`lib/metacrunch/builder.rb`, in `build`, add `limit: nil` to the `Pipeline.new` arguments (after `params: @values, logger: @logger`).

`lib/metacrunch/executor/inline.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    # Processes records one after another, in source order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work. Several values yielded
      # at once become one Array record, as with Enumerable#to_a.
      #
      # select: callable (record, position); only records it accepts are
      # yielded, positions still count every record. limit: stop after this
      # many yielded records; `break` lets the source's ensure blocks run.
      def run(source, limit: nil, select: nil)
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

    end
  end
end
```

`lib/metacrunch/engine.rb`:

```ruby
    def initialize(pipeline, executor: Executor::Inline.new, observer: nil, select: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
      @select = select
    end

    def run
      validate!
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      @on_mark = @stats.method(:mark)
      error = execute
      @stats.count_written(@pipeline.sink.delivered) if @pipeline.sink
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end

    private

    def validate!
      raise ArgumentError, "the pipeline has no source" unless @pipeline.source

      limit = @pipeline.limit
      return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

      raise ArgumentError, "limit must be a positive Integer, got #{limit.inspect}"
    end
```

(The `raise ... unless @pipeline.source` line from Task 2 moves into `validate!`.) In `process`, replace the executor call with:

```ruby
      @executor.run(@pipeline.source, limit: @pipeline.limit, select: @select) do |record, position|
        ingest(chain, record, position)
      end
```

`lib/metacrunch/job.rb`, replace `run`:

```ruby
    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments and lets errors from the recipe itself (e.g. a component
    # constructor or a DSL mistake) propagate. Errors while the pipeline
    # runs end up in the Result. limit stops after that many records.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil)
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:) }, logger:)
      Engine.new(built.with(limit:), observer:).run
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/pipeline.rb lib/metacrunch/builder.rb lib/metacrunch/executor/inline.rb \
  lib/metacrunch/engine.rb lib/metacrunch/job.rb test/unit/engine_selection_test.rb test/unit/job_test.rb
git commit -m "Add a record limit and record selection to the executor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 4: Monitor seam and live counters

The engine accepts a `monitor` that gets `start(live)` and `stop`. `LiveStats` reads the current counters without the engine doing extra work per record. Hashes are never iterated from the monitor's thread (an insert in the engine thread would raise), so the collector keeps integer totals.

**Files:**
- Create: `lib/metacrunch/live_stats.rb`, `test/unit/engine_monitor_test.rb`
- Modify: `lib/metacrunch.rb`, `lib/metacrunch/stats_collector.rb`, `lib/metacrunch/engine.rb`, `test/unit/stats_collector_test.rb`

**Interfaces:**
- Consumes: `Pipeline#limit` (Task 3).
- Produces: `Engine.new(pipeline, executor:, observer:, monitor: nil, select:)`; monitor protocol `start(live)`, `stop` (always called, also after an abort or a signal); `Metacrunch::LiveStats#read`, `#written`, `#filtered`, `#rejected`, `#failed`, `#elapsed`, `#source`, `#limit`; `StatsCollector#read`, `#rejected_total`, `#filtered_total`, `#elapsed`.

- [ ] **Step 1: Write the failing tests**

`test/unit/engine_monitor_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineMonitorTest < Minitest::Test

  include PipelineHelper

  # Notes the live counters at start and stop.
  class RecordingMonitor

    attr_reader :events, :live

    def initialize
      @events = []
    end

    def start(live)
      @live = live
      @events << [:start, live.read]
    end

    def stop
      @events << [:stop, @live.read, @live.written]
    end

  end

  def test_the_monitor_sees_the_live_counters
    monitor = RecordingMonitor.new
    pipeline = build_pipeline do
      source [1, 2, 3]
      reject("Even", &:even?)
      filter { it < 3 }
      sink CollectingSink.new
    end
    Metacrunch::Engine.new(pipeline, monitor:).run
    live = monitor.live

    assert_equal [[:start, 0], [:stop, 3, 1]], monitor.events
    assert_equal [1, 1, 0, nil], [live.filtered, live.rejected, live.failed, live.limit]
    assert_same pipeline.source, live.source
  end

  def test_the_monitor_stops_after_an_abort_and_a_signal
    aborted = RecordingMonitor.new
    interrupted = RecordingMonitor.new
    Metacrunch::Engine.new(build_pipeline { source [1]; map { raise "broken" } }, monitor: aborted).run

    assert_raises(Interrupt) do
      Metacrunch::Engine.new(build_pipeline { source [1]; map { raise Interrupt } }, monitor: interrupted).run
    end
    assert_equal [:start, :stop], aborted.events.map(&:first)
    assert_equal [:start, :stop], interrupted.events.map(&:first)
  end

  def test_failures_and_time_are_live
    monitor = RecordingMonitor.new
    pipeline = build_pipeline do
      source [1, 2]
      map { raise "broken" }
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline, monitor:).run

    assert_equal [2, 0], [monitor.live.failed, monitor.live.written]
    assert_operator monitor.live.elapsed, :>, 0
  end

end
```

In `test/unit/stats_collector_test.rb`, add:

```ruby
  def test_live_totals
    collector = Metacrunch::StatsCollector.new(["filter#1", "reject#2"])
    collector.count_read
    collector.counter("filter#1").filtered += 1
    collector.step_rejected("reject#2", "Patent")

    assert_equal [1, 1, 1], [collector.read, collector.filtered_total, collector.rejected_total]
    assert_operator collector.elapsed, :>=, 0
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_monitor_test.rb`
Expected: errors (`ArgumentError: unknown keyword: :monitor`).

- [ ] **Step 3: Implement**

`lib/metacrunch/live_stats.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # The counters of a running engine, read when asked for. Monitors such as
  # the progress display read them from another thread; the engine does no
  # extra work for them. Under the GVL reading an Integer is safe, and a
  # slightly stale value is fine.
  class LiveStats

    def initialize(collector, pipeline)
      @collector = collector
      @pipeline = pipeline
    end

    def read = @collector.read
    def filtered = @collector.filtered_total
    def rejected = @collector.rejected_total
    def failed = @collector.failed_total
    def elapsed = @collector.elapsed

    # Records the sink accepted so far; 0 for jobs without a sink.
    def written
      @pipeline.sink ? @pipeline.sink.delivered : 0
    end

    # The source, for its optional size or progress.
    def source = @pipeline.source

    def limit = @pipeline.limit

  end
end
```

`lib/metacrunch.rb`: add `require_relative "metacrunch/live_stats"` after `require_relative "metacrunch/result"`.

`lib/metacrunch/stats_collector.rb`:
- `attr_reader :read, :rejected_total, :failed_total`;
- `@rejected_total = 0` in `initialize`;
- in `step_rejected`, add `@rejected_total += 1`;
- add:

```ruby
    # Iterates only the step counters, whose Hash never changes during a
    # run, so another thread may call it.
    def filtered_total
      @steps.each_value.sum(&:filtered)
    end

    def elapsed
      now - @started_at
    end
```

- in `snapshot`, use `filtered: filtered_total` and `duration: elapsed`.

`lib/metacrunch/engine.rb`:

```ruby
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
      @on_mark = @stats.method(:mark)
      error = monitored { execute }
      @stats.count_written(@pipeline.sink.delivered) if @pipeline.sink
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end
```

and, as a private method:

```ruby
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/live_stats.rb lib/metacrunch/stats_collector.rb lib/metacrunch/engine.rb \
  test/unit/engine_monitor_test.rb test/unit/stats_collector_test.rb
git commit -m "Add a monitor seam with live counters to the engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 5: JSON Lines reader

**Files:**
- Create: `lib/metacrunch/json_lines.rb`, `test/unit/json_lines_reader_test.rb`
- Modify: `lib/metacrunch.rb`

**Interfaces:**
- Consumes: `Metacrunch::InvalidRecord` (Task 1).
- Produces: `Metacrunch::JsonLines::STDIO == "-"`, `JsonLines::GZIP == ".gz"`; `JsonLines::Reader.new(target)` where target is a path, `"-"` (stdin, resolved in `each`) or an IO; `#each { |record| }`; `#progress` → Float 0.0..1.0 or `nil`.

- [ ] **Step 1: Write the failing tests**

`test/unit/json_lines_reader_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class JsonLinesReaderTest < Minitest::Test

  Reader = Metacrunch::JsonLines::Reader

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_parses_one_json_value_per_line
    reader = Reader.new(StringIO.new("{\"a\":1}\n42\n\"x\"\n[1,2]\n"))

    assert_equal [{"a" => 1}, 42, "x", [1, 2]], read(reader)
    assert_nil reader.progress
  end

  def test_skips_blank_lines
    assert_equal [1, 2], read(Reader.new(StringIO.new("1\n\n  \n2\n")))
  end

  def test_line_endings_and_a_missing_final_newline
    assert_equal [{"a" => 1}, 2, 3], read(Reader.new(StringIO.new("{\"a\":1}\r\n2\r\n3")))
  end

  def test_ignores_a_byte_order_mark
    assert_equal [1, 2], read(Reader.new(StringIO.new("﻿1\n2\n")))
  end

  def test_invalid_lines_become_invalid_records
    records = read(Reader.new(StringIO.new("1\n{\"id\": 4711, \"ti\n3\n")))
    invalid = records[1]

    assert_equal [1, 3], [records[0], records[2]]
    assert_equal "{\"id\": 4711, \"ti", invalid.raw
    assert_instance_of JSON::ParserError, invalid.error
  end

  def test_invalid_utf8_becomes_an_invalid_record
    records = read(Reader.new(StringIO.new("\"\xFF\"\n\"ok\"\n".b)))

    assert_instance_of Metacrunch::InvalidRecord, records.first
    assert_equal "ok", records.last
  end

  def test_reads_files_and_reports_progress
    reader = Reader.new(write("in.jsonl", "1\n2\n"))

    assert_nil reader.progress
    assert_equal [1, 2], read(reader)
    assert_in_delta 1.0, reader.progress
  end

  def test_progress_grows_while_reading
    reader = Reader.new(write("big.jsonl", "\"#{"x" * 10}\"\n" * 3000))
    values = []
    reader.each { values << reader.progress }

    assert(values.any? { it.positive? && it < 1.0 })
    assert_equal values, values.sort
  end

  def test_reads_gzip_files
    path = File.join(@dir, "in.jsonl.gz")
    Zlib::GzipWriter.open(path) { it.write("{\"a\":1}\n{\"a\":2}\n") }

    assert_equal [{"a" => 1}, {"a" => 2}], read(Reader.new(path))
  end

  def test_dash_reads_stdin
    original = $stdin
    $stdin = StringIO.new("1\n")

    assert_equal [1], read(Reader.new("-"))
  ensure
    $stdin = original
  end

  def test_breaking_out_closes_the_file
    path = write("in.jsonl", "1\n2\n3\n")
    Reader.new(path).each { break }

    assert(ObjectSpace.each_object(File).none? { it.path == path && !it.closed? })
  end

  private

  def read(reader)
    records = []
    reader.each { records << it }
    records
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/json_lines_reader_test.rb`
Expected: errors with `NameError: uninitialized constant Metacrunch::JsonLines`.

- [ ] **Step 3: Implement**

`lib/metacrunch/json_lines.rb`:

```ruby
# frozen_string_literal: true

require "json"
require "zlib"

module Metacrunch
  # A source and sinks for JSON Lines: one JSON value per line. Each takes a
  # path, "-" for stdin or stdout, or an IO object; IO objects are never
  # closed. Paths ending in ".gz" are read and written with gzip.
  module JsonLines

    STDIO = "-"
    GZIP = ".gz"

    # Source: yields every line parsed with JSON.parse. A line that is not
    # valid JSON (or not valid UTF-8) is yielded as InvalidRecord, so the
    # job's error policy decides. Blank lines are skipped.
    class Reader

      # How often (in lines) the position in a file is sampled for #progress.
      PROGRESS_EVERY = 1024
      BOM = "﻿"
      BLANK = Object.new.freeze
      private_constant :BLANK

      def initialize(target)
        @target = target
        @size = nil
        @done = 0
      end

      def each
        with_input do |io, file|
          lines = 0
          io.each_line do |line|
            lines += 1
            @done = file.pos if file && (lines % PROGRESS_EVERY).zero?
            line.force_encoding(Encoding::UTF_8)
            line.delete_prefix!(BOM) if lines == 1
            record = parse(line)
            yield record unless record.equal?(BLANK)
          end
        end
      end

      # The share of the file read so far, from 0.0 to 1.0; nil for stdin,
      # IO objects and before reading. For gzip files it is the position in
      # the compressed file.
      def progress
        size = @size
        return unless size
        return 1.0 if size.zero?

        [@done.fdiv(size), 1.0].min
      end

      private

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        line.b.strip.empty? ? BLANK : InvalidRecord.new(raw: line.chomp, error: e)
      end

      # Yields the IO to read lines from and the File for progress (nil for
      # stdin and IO objects). Files are closed when each ends, also by break.
      def with_input(&)
        return yield($stdin, nil) if @target == STDIO
        return yield(@target, nil) unless @target.is_a?(String)

        File.open(@target, "rb") do |file|
          @size = file.size
          @done = 0
          @target.end_with?(GZIP) ? with_gzip(file, &) : yield(file, file)
          @done = @size
        end
      end

      def with_gzip(file)
        gzip = Zlib::GzipReader.new(file)
        begin
          yield gzip, file
        ensure
          gzip.finish
        end
      end

    end

  end
end
```

`lib/metacrunch.rb`: add `require_relative "metacrunch/json_lines"` after `require_relative "metacrunch/loader"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/json_lines_reader_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean. (If `line.delete_prefix!` raises for a first line with invalid UTF-8, compare bytes instead: `line.byteslice(3..) if line.b.start_with?(BOM.b)`; the test `test_invalid_utf8_becomes_an_invalid_record` has the invalid line first on purpose.)

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/json_lines.rb test/unit/json_lines_reader_test.rb
git commit -m "Add a JSON Lines reader that reports invalid lines as records

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 6: JSON Lines writers and a closed pipe

`Writer` writes records, `ContextWriter` writes envelopes for the `rejects` and `errors` roles. `Errno::EPIPE` becomes `SignalException("PIPE")`; afterwards nothing is written. The engine closes all components even if one raises a signal while closing, then raises the signal.

**Files:**
- Create: `test/unit/json_lines_writer_test.rb`, `test/unit/json_lines_context_writer_test.rb`
- Modify: `lib/metacrunch/json_lines.rb`, `lib/metacrunch/engine.rb`, `test/unit/engine_lifecycle_test.rb`

**Interfaces:**
- Consumes: `JsonLines::STDIO`, `JsonLines::GZIP` (Task 5).
- Produces: `JsonLines::Writer.new(target)` with `open(context)`, `write(record, ctx)`, `write_batch(records, ctxs)`, `close`; `JsonLines::ContextWriter < Writer` (same methods, writes envelopes). Non-JSON records in `Writer` raise `Metacrunch::Error` naming position and class. `Engine#close_components` re-raises the first `SignalException` after closing everything.

- [ ] **Step 1: Write the failing tests**

`test/unit/json_lines_writer_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class JsonLinesWriterTest < Minitest::Test

  Writer = Metacrunch::JsonLines::Writer

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  # A pipe that breaks when the buffered data is flushed at the end.
  class PipeClosedBeforeFlush < StringIO

    def flush = raise(Errno::EPIPE)

  end

  def setup
    @dir = Dir.mktmpdir
    @ctx = Metacrunch::Context.new(id: 7, position: 3, logger: Logger.new(nil))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_writes_one_json_value_per_line
    io = StringIO.new
    writer = open_writer(io)
    writer.write({"a" => 1}, @ctx)
    writer.write_batch([2, "x"], [@ctx, @ctx])
    writer.close

    assert_equal "{\"a\":1}\n2\n\"x\"\n", io.string
    refute_predicate io, :closed?
  end

  def test_refuses_values_that_are_not_json
    writer = open_writer(StringIO.new)
    error = assert_raises(Metacrunch::Error) { writer.write({"at" => Time.at(0)}, @ctx) }

    assert_equal "record at position 3 is not JSON (Hash): Time not allowed in JSON", error.message
  end

  def test_writes_files_and_gzip_files
    plain = File.join(@dir, "out.jsonl")
    gzip = File.join(@dir, "out.jsonl.gz")
    [plain, gzip].each do |path|
      writer = open_writer(path)
      writer.write({"a" => 1}, @ctx)
      writer.close
    end

    assert_equal "{\"a\":1}\n", File.read(plain)
    assert_equal "{\"a\":1}\n", Zlib::GzipReader.open(gzip, &:read)
  end

  def test_dash_writes_stdout
    stdout, = capture_io do
      writer = open_writer("-")
      writer.write(1, @ctx)
      writer.close
    end

    assert_equal "1\n", stdout
  end

  def test_a_closed_pipe_raises_sigpipe_once
    writer = open_writer(ClosedPipe.new)
    error = assert_raises(SignalException) { writer.write(1, @ctx) }
    writer.write(2, @ctx)
    writer.close

    assert_equal Signal.list.fetch("PIPE"), error.signo
  end

  def test_a_pipe_closed_before_the_final_flush_raises_sigpipe
    writer = open_writer(PipeClosedBeforeFlush.new)
    writer.write(1, @ctx)

    assert_raises(SignalException) { writer.close }
  end

  private

  def open_writer(target)
    writer = Writer.new(target)
    writer.open(nil)
    writer
  end

end
```

`test/unit/json_lines_context_writer_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class JsonLinesContextWriterTest < Minitest::Test

  # A record that is not a JSON type.
  class Opaque

    def inspect = "#<Opaque>"

  end

  def setup
    @ctx = Metacrunch::Context.new(id: 18, position: 2, logger: Logger.new(nil))
  end

  def test_writes_rejected_records_with_their_context
    @ctx.step = "map#3"
    @ctx.mark("No title")
    @ctx.step = "reject#4"
    @ctx.reject!("Not public", value: false)
    expected = {
      "record" => {"_id" => 18}, "id" => 18, "position" => 2,
      "marks" => [{"reason" => "No title", "step" => "map#3", "value" => nil}],
      "rejection" => {"reason" => "Not public", "step" => "reject#4", "value" => false}
    }

    assert_equal expected, JSON.parse(write({"_id" => 18}))
  end

  def test_writes_failures
    @ctx.failure = Metacrunch::Failure.new(error: JSON::ParserError.new("unexpected end of input"), step: "source")

    assert_equal({"step" => "source", "error" => "JSON::ParserError", "message" => "unexpected end of input"},
                 JSON.parse(write("{\"id\": 47"))["failure"])
  end

  def test_writes_values_that_are_not_json_as_inspect_strings
    @ctx.mark("Odd", value: Time.at(0).utc)
    data = JSON.parse(write(Opaque.new))

    assert_equal ["#<Opaque>", "JsonLinesContextWriterTest::Opaque"], [data["record"], data["record_class"]]
    assert_equal Time.at(0).utc.inspect, data["marks"].first["value"]
  end

  def test_writes_messages_with_invalid_utf8
    @ctx.failure = Metacrunch::Failure.new(error: JSON::ParserError.new("unexpected character: '\xFF'"),
                                           step: "source")

    assert_match(/unexpected character/, JSON.parse(write("x"))["failure"]["message"])
  end

  private

  def write(record)
    io = StringIO.new
    writer = Metacrunch::JsonLines::ContextWriter.new(io)
    writer.open(nil)
    writer.write(record, @ctx)
    writer.close
    io.string
  end

end
```

In `test/unit/engine_lifecycle_test.rb`, add a sink class inside the test class:

```ruby
  # Raises SIGPIPE when closed, like a writer whose reader went away.
  class PipeClosingSink

    def write(_record) = nil

    def close = raise(SignalException, "PIPE")

  end
```

and the test:

```ruby
  def test_signals_while_closing_are_raised_after_closing_everything
    log = []
    input = Component.new("source", log)
    pipeline = build_pipeline do
      source input
      sink PipeClosingSink.new
    end
    error = assert_raises(SignalException) { Metacrunch::Engine.new(pipeline).run }

    assert_equal Signal.list.fetch("PIPE"), error.signo
    assert_includes log, "close source"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/json_lines_writer_test.rb`
Expected: errors with `NameError: uninitialized constant Metacrunch::JsonLines::Writer`.

- [ ] **Step 3: Implement**

Append inside `module JsonLines` in `lib/metacrunch/json_lines.rb`, after `Reader`:

```ruby
    # Sink: writes every record as one line of JSON. Values that are not
    # JSON types (objects, Time, NaN) are refused instead of written as their
    # to_s. A closed pipe (EPIPE, e.g. `| head`) ends the run like SIGPIPE:
    # the writer raises SignalException("PIPE") and writes nothing afterwards.
    class Writer

      def initialize(target)
        @target = target
        @io = nil
        @own = false
        @broken = false
      end

      def open(_context)
        @io, @own = output
      end

      def write(record, ctx)
        emit(line(record, ctx))
      end

      def write_batch(records, ctxs)
        emit(records.zip(ctxs).map { |record, ctx| line(record, ctx) }.join)
      end

      def close
        io = @io
        @io = nil
        return unless io

        guard { @own ? io.close : io.flush }
      ensure
        discard(io) if @own && io && !io.closed?
      end

      private

      def line(record, ctx)
        "#{JSON.generate(record, strict: true)}\n"
      rescue JSON::GeneratorError => e
        raise Error, "record at position #{ctx.position} is not JSON (#{record.class}): #{e.message}"
      end

      def emit(text)
        guard { @io.write(text) }
      end

      # Turns EPIPE into SIGPIPE, once; afterwards nothing is written.
      def guard
        return if @broken

        yield
      rescue Errno::EPIPE
        @broken = true
        raise SignalException, "PIPE"
      end

      # Closes a file after a broken pipe; its buffer can no longer be written.
      def discard(io)
        io.close
      rescue Errno::EPIPE
        nil
      end

      # [io, own]: own IOs are closed, IOs from outside only flushed.
      def output
        return [$stdout, false] if @target == STDIO
        return [@target, false] unless @target.is_a?(String)
        return [Zlib::GzipWriter.open(@target), true] if @target.end_with?(GZIP)

        [File.open(@target, "w"), true]
      end

    end

    # Sink for the rejects and errors roles: writes every record with its
    # context as an envelope (record, id, position, marks, rejection,
    # failure). Values that are not JSON types are written as their inspect
    # string, so diagnostics never stop a run.
    class ContextWriter < Writer

      private

      def line(record, ctx)
        "#{JSON.generate(envelope(record, ctx), strict: true)}\n"
      end

      def envelope(record, ctx)
        plain = json?(record)
        data = {"record" => plain ? record : record.inspect}
        data["record_class"] = record.class.name unless plain
        data.merge!("id" => json(ctx.id), "position" => ctx.position, "marks" => ctx.marks.map { note(it) })
        data["rejection"] = note(ctx.rejection) if ctx.rejection
        data["failure"] = failure(ctx.failure) if ctx.failure
        data
      end

      def note(entry)
        {"reason" => json(entry.reason), "step" => entry.step, "value" => json(entry.value)}
      end

      def failure(failure)
        error = failure.error
        {"step" => failure.step, "error" => error.class.name, "message" => json(error.message)}
      end

      def json(value) = json?(value) ? value : value.inspect

      def json?(value)
        JSON.generate(value, strict: true)
        true
      rescue JSON::GeneratorError
        false
      end

    end
```

`lib/metacrunch/engine.rb`, replace `close_components`:

```ruby
    # Closes the opened components in reverse order and returns the first
    # error, after trying to close all of them. A signal raised while
    # closing (e.g. SIGPIPE from a writer whose reader went away) is raised
    # again once everything is closed.
    def close_components(opened)
      first_error = nil
      signal = nil
      opened.reverse_each do |component|
        component.close if component.respond_to?(:close)
      rescue *RECOVERABLE => e
        @pipeline.logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      rescue SignalException => e
        signal ||= e
      end
      raise signal if signal

      first_error
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/json_lines_writer_test.rb && bundle exec ruby -w -Ilib -Itest test/unit/json_lines_context_writer_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/json_lines.rb lib/metacrunch/engine.rb test/unit/json_lines_writer_test.rb \
  test/unit/json_lines_context_writer_test.rb test/unit/engine_lifecycle_test.rb
git commit -m "Add JSON Lines writers that end a run by SIGPIPE on a closed pipe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 7: RunOptions

`Cli::RunOptions` rewrites a built pipeline: replaced source and sinks, the filter default, the limit and the error policy, with all usage checks.

**Files:**
- Create: `lib/metacrunch/cli/run_options.rb`, `test/unit/run_options_test.rb`
- Modify: `lib/metacrunch/errors.rb`

**Interfaces:**
- Consumes: `JsonLines::Reader`, `Writer`, `ContextWriter`, `STDIO` (Tasks 5, 6); `Pipeline#limit` (Task 3); `SinkAdapter.new(sink)`.
- Produces: `Metacrunch::UsageError < Metacrunch::Error`; `Metacrunch::Cli::RunOptions.new(input:, output:, rejects:, errors:, stats:, limit:, on_error:, max_errors:)` (all default `nil`; `on_error` is `:abort`/`:skip`); `#apply(pipeline, stdin:, stdout:)` → Pipeline; `#apply_input(pipeline, stdin:)` → Pipeline (source only).

- [ ] **Step 1: Write the failing tests**

`test/unit/run_options_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "metacrunch/cli/run_options"

class RunOptionsTest < Minitest::Test

  include PipelineHelper

  RunOptions = Metacrunch::Cli::RunOptions

  # Stdin that claims to be a terminal.
  class TerminalInput < StringIO

    def tty? = true

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_without_options_the_pipeline_is_unchanged
    pipeline = build_pipeline do
      source [1]
      sink CollectingSink.new
    end

    assert_equal pipeline, apply(RunOptions.new, pipeline)
  end

  def test_a_job_without_source_and_sink_filters_stdin_to_stdout
    stdout = StringIO.new
    pipeline = apply(RunOptions.new, build_pipeline { map { it * 2 } }, stdin: StringIO.new("1\n2\n"), stdout:)
    Metacrunch::Engine.new(pipeline).run

    assert_equal "2\n4\n", stdout.string
  end

  def test_a_job_without_source_does_not_read_a_terminal
    error = assert_raises(Metacrunch::UsageError) do
      apply(RunOptions.new, build_pipeline { map { it } }, stdin: TerminalInput.new)
    end

    assert_equal "job has no source and stdin is a terminal; pipe JSON Lines in or use -i PATH", error.message
  end

  def test_input_and_output_replace_the_source_and_sink
    input = File.join(@dir, "in.jsonl")
    output = File.join(@dir, "out.jsonl")
    File.write(input, "1\n2\n")
    replaced = CollectingSink.new
    pipeline = build_pipeline do
      source [99]
      map { it + 1 }
      sink replaced
    end
    Metacrunch::Engine.new(apply(RunOptions.new(input:, output:), pipeline)).run

    assert_equal "2\n3\n", File.read(output)
    assert_empty replaced.events
  end

  def test_dash_means_the_cli_streams
    stdout = StringIO.new
    pipeline = build_pipeline do
      source [99]
      sink CollectingSink.new
    end
    applied = apply(RunOptions.new(input: "-", output: "-"), pipeline, stdin: StringIO.new("7\n"), stdout:)
    Metacrunch::Engine.new(applied).run

    assert_equal "7\n", stdout.string
  end

  def test_rejects_and_errors_may_share_a_file
    path = File.join(@dir, "bad.jsonl")
    pipeline = build_pipeline do
      source [1, 2, 3]
      reject("Two") { it == 2 }
      map { it == 3 ? raise("three") : it }
      sink CollectingSink.new
      on_error :skip
    end
    applied = apply(RunOptions.new(rejects: path, errors: File.join(@dir, ".", "bad.jsonl")), pipeline)
    Metacrunch::Engine.new(applied).run
    lines = File.readlines(path).map { JSON.parse(it) }

    assert_same applied.rejects.sink, applied.errors.sink
    assert_equal([["Two", nil], [nil, "RuntimeError"]],
                 lines.map { [it.dig("rejection", "reason"), it.dig("failure", "error")] })
  end

  def test_stdout_is_used_once
    pipeline = build_pipeline do
      source [1]
      sink CollectingSink.new
    end
    conflicts = [RunOptions.new(output: "-", rejects: "-"), RunOptions.new(errors: "-", stats: "-")]
    messages = conflicts.map { |options| assert_raises(Metacrunch::UsageError) { apply(options, pipeline) }.message }

    assert_equal ["stdout is used by both --output and --rejects", "stdout is used by both --errors and --stats"],
                 messages
  end

  def test_a_job_without_sink_keeps_stdout_for_its_records
    pipeline = build_pipeline { source [1] }
    error = assert_raises(Metacrunch::UsageError) { apply(RunOptions.new(rejects: "-"), pipeline) }

    assert_equal "stdout is used by both the default output (the job has no sink) and --rejects", error.message
  end

  def test_files_must_not_be_shared
    path = File.join(@dir, "x.jsonl")
    same = File.join(@dir, ".", "x.jsonl")
    pipeline = build_pipeline { source [1] }
    conflicts = [RunOptions.new(input: path, output: same), RunOptions.new(output: path, stats: same)]
    messages = conflicts.map { |options| assert_raises(Metacrunch::UsageError) { apply(options, pipeline) }.message }

    assert_equal ["--input and --output name the same file: #{same}", "--output and --stats name the same file: #{same}"],
                 messages
  end

  def test_limit_and_error_policy_override_the_job
    pipeline = build_pipeline do
      source [1]
      on_error :skip, max_errors: 5
    end
    aborting = apply(RunOptions.new(limit: 3, on_error: :abort), pipeline)
    skipping = apply(RunOptions.new(on_error: :skip), pipeline)
    stricter = apply(RunOptions.new(max_errors: 0), pipeline)

    assert_equal [3, :abort, nil], [aborting.limit, aborting.on_error, aborting.max_errors]
    assert_equal [:skip, 5], [skipping.on_error, skipping.max_errors]
    assert_equal 0, stricter.max_errors
  end

  def test_max_errors_needs_skip
    pipeline = build_pipeline { source [1] }
    error = assert_raises(Metacrunch::UsageError) { apply(RunOptions.new(max_errors: 3), pipeline) }

    assert_equal "--max-errors needs the error policy skip (add --on-error skip)", error.message
  end

  def test_apply_input_leaves_the_sinks_alone
    applied = RunOptions.new.apply_input(build_pipeline { map { it } }, stdin: StringIO.new("1\n"))

    assert_instance_of Metacrunch::JsonLines::Reader, applied.source
    assert_nil applied.sink
  end

  private

  def apply(options, pipeline, stdin: StringIO.new, stdout: StringIO.new)
    options.apply(pipeline, stdin:, stdout:)
  end

end
```

If RuboCop reports a line over 120 characters in `test_files_must_not_be_shared`, split the expected Array over two lines.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/run_options_test.rb`
Expected: `LoadError: cannot load such file -- metacrunch/cli/run_options`.

- [ ] **Step 3: Implement**

`lib/metacrunch/errors.rb`, after `JobLoadError`:

```ruby
  # Invalid use of the command line, e.g. options that conflict.
  class UsageError < Error; end
```

`lib/metacrunch/cli/run_options.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # The options of `metacrunch run` that change the pipeline: source and
    # sinks replaced by JSON Lines, the filter default, the limit and the
    # error policy. Paths may be "-" for stdin or stdout.
    RunOptions = Data.define(:input, :output, :rejects, :errors, :stats, :limit, :on_error, :max_errors) do
      def initialize(input: nil, output: nil, rejects: nil, errors: nil, stats: nil, limit: nil, on_error: nil,
                     max_errors: nil)
        super
      end

      # Returns the pipeline with all options applied. Raises UsageError
      # for options that conflict.
      def apply(pipeline, stdin:, stdout:)
        check_stdout!(pipeline)
        check_files!
        apply_input(pipeline, stdin:).with(
          sink: sink(pipeline, stdout), **side_sinks(pipeline, stdout), limit: limit || pipeline.limit,
          **error_policy(pipeline)
        )
      end

      # Only the input: -i, or JSON Lines from stdin for a job without
      # source (the filter default).
      def apply_input(pipeline, stdin:)
        return pipeline.with(source: JsonLines::Reader.new(input == JsonLines::STDIO ? stdin : input)) if input
        return pipeline if pipeline.source
        if stdin.tty?
          raise UsageError, "job has no source and stdin is a terminal; pipe JSON Lines in or use -i PATH"
        end

        pipeline.with(source: JsonLines::Reader.new(stdin))
      end

      private

      def sink(pipeline, stdout)
        return SinkAdapter.new(JsonLines::Writer.new(target(output, stdout))) if output
        return pipeline.sink if pipeline.sink

        SinkAdapter.new(JsonLines::Writer.new(stdout))
      end

      # --rejects and --errors naming the same file share one writer.
      def side_sinks(pipeline, stdout)
        writers = {}
        writer = ->(path) { writers[key(path)] ||= JsonLines::ContextWriter.new(target(path, stdout)) }
        {
          rejects: rejects ? SinkAdapter.new(writer.call(rejects)) : pipeline.rejects,
          errors: errors ? SinkAdapter.new(writer.call(errors)) : pipeline.errors
        }
      end

      def target(path, stdout) = path == JsonLines::STDIO ? stdout : path

      def key(path) = path == JsonLines::STDIO ? path : File.expand_path(path)

      def error_policy(pipeline)
        policy = on_error || pipeline.on_error
        if max_errors && policy != :skip
          raise UsageError, "--max-errors needs the error policy skip (add --on-error skip)"
        end

        {on_error: policy, max_errors: policy == :skip ? max_errors || pipeline.max_errors : nil}
      end

      # Only one option may use stdout. A job without sink uses it for its
      # records unless -o is given.
      def check_stdout!(pipeline)
        options = {"--output" => output, "--rejects" => rejects, "--errors" => errors, "--stats" => stats}
        users = options.select { |_option, path| path == JsonLines::STDIO }.keys
        users.unshift("the default output (the job has no sink)") if output.nil? && pipeline.sink.nil?
        return if users.size < 2

        raise UsageError, "stdout is used by both #{users[0]} and #{users[1]}"
      end

      # A file must not be written twice, or read and written at once, except
      # by --rejects and --errors, which share a writer.
      def check_files!
        options = {"--input" => input, "--output" => output, "--rejects" => rejects, "--errors" => errors,
                   "--stats" => stats}
        files = options.reject { |_option, path| path.nil? || path == JsonLines::STDIO }
        files.to_a.combination(2).each do |(first, first_path), (second, second_path)|
          next if [first, second] == ["--rejects", "--errors"]
          next unless key(first_path) == key(second_path)

          raise UsageError, "#{first} and #{second} name the same file: #{second_path}"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/run_options_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/errors.rb lib/metacrunch/cli/run_options.rb test/unit/run_options_test.rb
git commit -m "Add RunOptions to replace sources and sinks from the command line

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 8: CLI dispatcher, command base and `run`

Replaces the minimal CLI. `metacrunch COMMAND ...` dispatches; a job file as first argument means `run`. Commands get injected streams. `run` applies the filter default via `RunOptions`.

**Files:**
- Rewrite: `lib/metacrunch/cli.rb`, `test/cli/cli_test.rb`
- Create: `lib/metacrunch/cli/command.rb`, `lib/metacrunch/cli/job_command.rb`, `lib/metacrunch/cli/run.rb`, `test/support/cli_helper.rb`, `test/cli/run_test.rb`, `test/fixtures/jobs/double.rb`, `test/fixtures/jobs/verbose.rb`
- Modify: `lib/metacrunch/params.rb`, `exe/metacrunch`, `test/unit/params_test.rb`

**Interfaces:**
- Consumes: `RunOptions#apply` (Task 7), `UsageError`, `Engine`, `Job#describe`, `Params#help_requested?`, `Params#help`.
- Produces: `Metacrunch::Cli.new(stdin:, stdout:, stderr:, env:)`, `#run(argv)` → Integer; `Cli::EXIT_CODES`; `Cli::COMMANDS` (`{"run" => RunCommand}`; later tasks add entries); `Cli::Streams` (`Data`: `stdin`, `stdout`, `stderr`, `env`); `Cli::Command` (subclasses define `NAME`, `SUMMARY`, `USAGE`, private `define_options(parser)`, private `execute(argv)`; base provides `logger`, `log_output`, `show`, `usage_error`, `@stdin`, `@stdout`, `@stderr`, `@env`, `@log_level`); `Cli::JobCommand < Command` (private `execute_job(job, argv)` hook, `build_pipeline(job, argv)`, `@job_file`); `Cli::RunCommand` (private `report(result)`); test helper `CliHelper#cli(*args, stdin: "", env: {}, stderr: nil)` → `[code, stdout, stderr]`, `CliHelper#job(name)`, `CliHelper::TerminalInput`, `CliHelper::TerminalOutput`.

- [ ] **Step 1: Write the failing tests**

`test/fixtures/jobs/double.rb`:

```ruby
# frozen_string_literal: true

# Filter job: no source, no sink.
Metacrunch.job "double" do
  map { it * 2 }
end
```

`test/fixtures/jobs/verbose.rb`:

```ruby
# frozen_string_literal: true

# Logs a debug message before it runs.
Metacrunch.job do
  source [1]
  before { logger.debug("debug message") }
end
```

`test/support/cli_helper.rb`:

```ruby
# frozen_string_literal: true

require "metacrunch/cli"

# Runs Metacrunch::Cli in-process with injected streams. Fixture sinks that
# print to $stdout are captured as well.
module CliHelper

  JOBS = File.expand_path("../fixtures/jobs", __dir__)

  # Stdin that claims to be a terminal.
  class TerminalInput < StringIO

    def tty? = true

  end

  # stderr that claims to be a terminal.
  class TerminalOutput < StringIO

    def tty? = true

  end

  # Returns [exit code, stdout, stderr]. stderr: an IO to use instead of a
  # captured one, e.g. a TerminalOutput.
  def cli(*args, stdin: "", env: {}, stderr: nil)
    code = nil
    input = stdin.is_a?(String) ? StringIO.new(stdin) : stdin
    stdout, captured = capture_io do
      code = Metacrunch::Cli.new(stdin: input, stdout: $stdout, stderr: stderr || $stderr, env:).run(args)
    end
    [code, stdout, stderr ? stderr.string : captured]
  end

  def job(name) = File.join(JOBS, name)

end
```

`test/cli/cli_test.rb` (replaces the file):

```ruby
# frozen_string_literal: true

require "test_helper"

class CliTest < Minitest::Test

  include CliHelper

  USAGE_ERRORS = {
    [] => "no command or job file given",
    ["frobnicate"] => "unknown command or job file: frobnicate",
    ["-v"] => "unknown option -v",
    ["help", "frobnicate"] => "unknown command frobnicate"
  }.freeze

  def test_prints_the_version
    assert_equal [0, "#{Metacrunch::VERSION}\n", ""], cli("--version")
  end

  def test_prints_the_usage
    code, stdout, = cli("--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch COMMAND \[OPTIONS\] JOB_FILE/, stdout)
    assert_match(/^  run +Run a job$/, stdout)
  end

  def test_help_without_a_command_prints_the_usage
    assert_equal cli("--help"), cli("help")
  end

  def test_help_for_a_command
    code, stdout, = cli("help", "run")

    assert_equal [0, cli("run", "--help")[1]], [code, stdout]
    assert_match(/Usage: metacrunch run \[OPTIONS\] JOB_FILE/, stdout)
    assert_match(/-j, --job NAME/, stdout)
  end

  def test_usage_errors_exit_with_the_usage_code
    results = USAGE_ERRORS.keys.map { |args| cli(*args) }

    assert_equal [2] * USAGE_ERRORS.size, results.map(&:first)
    assert_equal(USAGE_ERRORS.values, results.map { |_code, _stdout, stderr| stderr[/Error: (.*)$/, 1] })
  end

  def test_a_job_file_as_first_argument_is_run
    assert_equal [0, "3\n6\n"], cli(job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2").take(2)
  end

end
```

`test/cli/run_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/jobs/lib/counting_source"

class RunTest < Minitest::Test

  include CliHelper

  # stdout whose reader went away.
  class ClosedPipe < StringIO

    def write(*) = raise(Errno::EPIPE)

    def flush = raise(Errno::EPIPE)

  end

  def test_runs_the_job
    code, stdout, stderr = cli("run", job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_usage_errors_exit_with_the_usage_code
    assert_equal 2, cli("run").first
    assert_equal 2, cli("run", job("missing.rb")).first
    assert_equal 2, cli("run", job("numbers.rb"), "--factor", "x", "1").first
  end

  def test_usage_errors_are_explained_on_stderr
    _code, stdout, stderr = cli("run", job("numbers.rb"))

    assert_empty stdout
    assert_match(/Error: expected at least 1 argument\(s\) for numbers, got 0/, stderr)
    assert_match(/Usage: metacrunch run \[OPTIONS\] JOB_FILE/, stderr)
  end

  def test_prints_job_help_without_running_the_job
    code, stdout, = cli("run", job("numbers.rb"), "--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch run \S*numbers\.rb \[JOB_PARAMS\.\.\.\] NUMBERS\.\.\./, stdout)
    assert_match(/--factor VALUE\s+Multiplier \(default: 1\)/, stdout)
  end

  def test_help_for_a_job_without_params
    code, stdout, = cli("run", "-j", "first", job("several.rb"), "--help")

    assert_equal [0, "Usage: metacrunch run #{job("several.rb")} [JOB_PARAMS...]\n\n"], [code, stdout]
  end

  def test_help_options_given_as_values_do_not_print_help
    code, stdout, stderr = cli("run", job("numbers.rb"), "--factor", "-h", "1")

    assert_equal [2, ""], [code, stdout]
    assert_match(/invalid value for --factor: "-h"/, stderr)
  end

  def test_an_aborted_run_reports_the_error_once
    _code, _stdout, stderr = cli("run", job("numbers.rb"), "0")

    assert_equal 1, stderr.scan("zero is not allowed").size
    assert_match(/INFO  aborted: read 1, written 0/, stderr)
  end

  def test_a_run_without_help_builds_the_job_once
    CountingSource.constructed = 0
    cli("run", job("counting.rb"))

    assert_equal 1, CountingSource.constructed
  end

  def test_logs_causes_of_errors_other_than_step_errors
    _code, _stdout, stderr = cli("run", job("chained_error.rb"))

    assert_match(/ERROR ArgumentError: source broke/, stderr)
    assert_match(/caused by IOError/, stderr)
  end

  def test_failed_records_exit_as_aborted_or_with_failures
    code, _stdout, stderr = cli("run", job("numbers.rb"), "0")

    assert_equal 1, code
    assert_match(/StepError: step map#2 failed at position 1: ZeroDivisionError: zero is not allowed/, stderr)
    assert_equal 3, cli("run", job("numbers.rb"), "--skip-errors", "0", "1").first
  end

  def test_selects_jobs_by_name
    assert_equal 0, cli("run", "-j", "second", job("several.rb")).first
    assert_equal 0, cli("run", "--job=first", job("several.rb")).first
    assert_match(/defines several jobs/, cli("run", job("several.rb"))[2])
  end

  def test_signals_exit_with_the_signal_code
    interrupt_code, _stdout, interrupt_log = cli("run", job("interrupted.rb"))
    term_code, _stdout, term_log = cli("run", job("terminated.rb"))

    assert_equal [130, 143], [interrupt_code, term_code]
    assert_match(/WARN  interrupted by SIGINT/, interrupt_log)
    assert_match(/WARN  interrupted by SIGTERM/, term_log)
  end

  def test_unexpected_errors_exit_as_aborted
    code, _stdout, stderr = cli("run", job("broken_recipe.rb"))

    assert_equal [1, 1], [code, cli("run", job("todo_recipe.rb")).first]
    assert_match(/NameError/, stderr)
  end

  def test_quiet_and_verbose_set_the_log_level
    _code, _stdout, quiet = cli("run", "-q", job("numbers.rb"), "1")
    _code, _stdout, verbose = cli("run", "-v", job("verbose.rb"))

    refute_match(/INFO/, quiet)
    assert_match(/DEBUG debug message/, verbose)
  end

  def test_a_job_without_source_and_sink_filters_stdin_to_stdout
    assert_equal [0, "2\n4\n"], cli("run", job("double.rb"), stdin: "1\n2\n").take(2)
  end

  def test_empty_stdin_gives_no_output
    assert_equal [0, ""], cli("run", job("double.rb"), stdin: "").take(2)
  end

  def test_a_job_without_source_does_not_wait_for_a_terminal
    code, _stdout, stderr = cli("run", job("double.rb"), stdin: TerminalInput.new)

    assert_equal 2, code
    assert_match(/job has no source and stdin is a terminal/, stderr)
  end

  def test_a_closed_stdout_ends_quietly_with_the_sigpipe_code
    stderr = StringIO.new
    command = Metacrunch::Cli.new(stdin: StringIO.new("1\n"), stdout: ClosedPipe.new, stderr:, env: {})

    assert_equal 141, command.run(["run", job("double.rb")])
    assert_empty stderr.string
  end

end
```

In `test/unit/params_test.rb`, add:

```ruby
  def test_job_is_no_longer_reserved
    schema = Metacrunch::Params.new
    schema.param :job

    assert_equal "x", schema.bind_argv(["--job", "x"], env: {}).job
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/cli_test.rb`
Expected: failures (`--version` exits 2 with the old CLI, `help` is treated as a job file).

- [ ] **Step 3: Implement**

`lib/metacrunch/params.rb`: change the constant and its comment:

```ruby
    # Used by the CLI for the job's help. Names of methods of the bound
    # params object (to_h, with, ...) are checked when a parameter is
    # declared.
    RESERVED = [:help].freeze
```

`lib/metacrunch/cli/command.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # Base class of the commands. #run parses the command's options up to
    # the first argument that is not an option, then #execute gets the rest;
    # it returns the exit code. Subclasses define NAME, SUMMARY, USAGE,
    # #define_options and #execute.
    class Command

      def initialize(streams)
        @stdin = streams.stdin
        @stdout = streams.stdout
        @stderr = streams.stderr
        @env = streams.env
        @log_level = Logger::INFO
        @help = false
      end

      def run(argv)
        argv = argv.dup
        parser = option_parser
        parser.order!(argv)
        return show(parser.help) if @help

        execute(argv)
      rescue OptionParser::ParseError, JobLoadError, ParamError, UsageError => e
        usage_error(e.message)
      rescue SignalException => e
        interrupted(e)
      rescue *Engine::RECOVERABLE => e
        logger.error(e.full_message(highlight: false))
        EXIT_CODES[:aborted]
      end

      private

      def option_parser
        OptionParser.new do |parser|
          # No built-in --help and --version (they print and exit), and no
          # abbreviated options.
          parser.base.long.clear
          parser.require_exact = true
          parser.banner = "Usage: metacrunch #{self.class::USAGE}"
          parser.separator("")
          parser.separator("#{self.class::SUMMARY}.")
          parser.separator("")
          define_options(parser)
          parser.on("-h", "--help", "Show this help") { @help = true }
        end
      end

      def define_options(_parser) = nil

      def logger
        @logger ||= Metacrunch.build_logger(log_output).tap { it.level = @log_level }
      end

      # Where logs go; run sends them through the progress display.
      def log_output = @stderr

      # Exit code 128 + signal number, as shells report it; exe/metacrunch
      # then ends by the signal. A closed stdout (SIGPIPE) is not worth a
      # warning: the reader of the pipe stopped on purpose, e.g. head.
      def interrupted(signal)
        message = "interrupted by SIG#{Signal.signame(signal.signo)}"
        if signal.signo == Signal.list.fetch("PIPE")
          logger.debug(message)
        else
          logger.warn(message)
        end
        128 + signal.signo
      end

      def show(text)
        @stdout.puts(text)
        EXIT_CODES[:ok]
      end

      def usage_error(message)
        @stderr.puts("Error: #{message}", "Usage: metacrunch #{self.class::USAGE}")
        EXIT_CODES[:usage]
      end

    end
  end
end
```

`lib/metacrunch/cli/job_command.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # A command that takes a job file (run, check, trace). Options before
    # JOB_FILE belong to the command, everything after it to the job.
    # Subclasses implement #execute_job(job, argv).
    class JobCommand < Command

      HELP_OPTIONS = ["-h", "--help"].freeze

      private

      def define_options(parser)
        parser.separator("Options go before JOB_FILE; everything after it belongs to the job.")
        parser.separator("\"metacrunch #{self.class::NAME} JOB_FILE --help\" shows the job's parameters.")
        parser.separator("")
        parser.on("-j", "--job NAME", "Select a job in a file that defines several") { @job_name = it }
        parser.on("-q", "--quiet", "Log warnings and errors only") { @log_level = Logger::WARN }
        parser.on("-v", "--verbose", "Log debug messages too") { @log_level = Logger::DEBUG }
      end

      def execute(argv)
        @job_file = argv.shift
        raise UsageError, "no job file given" unless @job_file

        job = Metacrunch.load_job(@job_file, name: @job_name)
        schema = requested_job_help(job, argv)
        return show(job_help(schema)) if schema

        execute_job(job, argv)
      end

      # Describes the job (evaluates its recipe up to params) only if -h or
      # --help appears before "--"; the job's own parser then decides, so -h
      # as the value of another option does not count.
      def requested_job_help(job, argv)
        return unless argv.take_while { it != "--" }.intersect?(HELP_OPTIONS)

        schema = job.describe
        schema if schema.help_requested?(argv)
      end

      def job_help(schema)
        args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
        "Usage: metacrunch #{self.class::NAME} #{@job_file} [JOB_PARAMS...]#{args}\n\n#{schema.help}"
      end

      # Evaluates the recipe with the job's arguments.
      def build_pipeline(job, argv)
        job.pipeline(binder: ->(schema) { schema.bind_argv(argv, env: @env) }, logger:)
      end

    end
  end
end
```

`lib/metacrunch/cli/run.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch run: runs a job. A job without source reads JSON Lines from
    # stdin, a job without sink writes them to stdout.
    class RunCommand < JobCommand

      NAME = "run"
      SUMMARY = "Run a job"
      USAGE = "run [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"

      private

      def execute_job(job, argv)
        pipeline = RunOptions.new.apply(build_pipeline(job, argv), stdin: @stdin, stdout: @stdout)
        report(Engine.new(pipeline).run)
      end

      # Logs the error and its cause once each (a StepError message already
      # names its cause), then the status and stats.
      def report(result)
        error = result.error
        if error
          logger.error("#{error.class}: #{error.message}")
          cause = error.cause
          logger.error("caused by #{cause.class}: #{cause.message}") if cause && !error.is_a?(StepError)
        end
        logger.info("#{result.status}: #{result.stats.summary}")
        EXIT_CODES.fetch(result.status)
      end

    end
  end
end
```

`lib/metacrunch/cli.rb` (replaces the file):

```ruby
# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"
require_relative "cli/run_options"
require_relative "cli/command"
require_relative "cli/job_command"
require_relative "cli/run"

module Metacrunch
  # The command line interface. Dispatches to a command by the first
  # argument; a job file there is short for `run`. #run returns the exit
  # code, exe/metacrunch exits with it.
  class Cli

    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3}.freeze
    COMMANDS = {"run" => RunCommand}.freeze

    # The streams and environment the commands use instead of globals.
    Streams = Data.define(:stdin, :stdout, :stderr, :env)

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV)
      @streams = Streams.new(stdin:, stdout:, stderr:, env:)
    end

    def run(argv)
      first, *rest = argv
      case first
      when nil then usage_error("no command or job file given")
      when "-h", "--help" then show(usage)
      when "--version" then show(VERSION)
      when "help" then help(rest.first)
      when *COMMANDS.keys then command(first).run(rest)
      else other(first, argv)
      end
    end

    private

    # An option or a job file (short for run).
    def other(first, argv)
      return usage_error("unknown option #{first}") if first.start_with?("-")
      return command("run").run(argv) if File.file?(first)

      usage_error("unknown command or job file: #{first}")
    end

    def help(name)
      return show(usage) unless name
      return usage_error("unknown command #{name}") unless COMMANDS.key?(name)

      command(name).run(["--help"])
    end

    def command(name)
      COMMANDS.fetch(name).new(@streams)
    end

    def usage
      commands = COMMANDS.map { |name, command| "  #{name.ljust(8)} #{command::SUMMARY}" }
      <<~TEXT
        Usage: metacrunch COMMAND [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
               metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]    (same as run)

        Commands:
        #{commands.join("\n")}
          help     Show the help of a command

        Options:
          -h, --help     Show this help
              --version  Show the version
      TEXT
    end

    def show(text)
      @streams.stdout.puts(text)
      EXIT_CODES[:ok]
    end

    def usage_error(message)
      @streams.stderr.puts("Error: #{message}", "Run \"metacrunch --help\" for usage.")
      EXIT_CODES[:usage]
    end

  end
end
```

`exe/metacrunch`: change the first comment line to `# After Ctrl-C, SIGTERM or a closed stdout (exit code 128 + signal number),`. The code stays.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/cli_test.rb && bundle exec ruby -w -Ilib -Itest test/cli/run_test.rb && bundle exec rake`
Expected: all tests pass, including `test/cli/exe_test.rb` and `test/integration/catalog_job_test.rb` (they use the short form `metacrunch JOB_FILE`). RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli.rb lib/metacrunch/cli/command.rb lib/metacrunch/cli/job_command.rb \
  lib/metacrunch/cli/run.rb lib/metacrunch/params.rb exe/metacrunch test/support/cli_helper.rb \
  test/cli/cli_test.rb test/cli/run_test.rb test/unit/params_test.rb test/fixtures/jobs/double.rb \
  test/fixtures/jobs/verbose.rb
git commit -m "Replace the minimal CLI with a command dispatcher and run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 9: Options of `run` and `--stats`

**Files:**
- Create: `test/cli/run_flags_test.rb`
- Modify: `lib/metacrunch/cli/run.rb`

**Interfaces:**
- Consumes: `RunOptions` (Task 7), `RunCommand` (Task 8).
- Produces: `run` options `-i/--input`, `-o/--output`, `--rejects`, `--errors`, `-n/--limit`, `--on-error`, `--max-errors`, `--stats`; `RunCommand#write_stats(path, result)` (private).

- [ ] **Step 1: Write the failing tests**

`test/cli/run_flags_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RunFlagsTest < Minitest::Test

  include CliHelper

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_input_and_output_files_replace_source_and_sink
    input = File.join(@dir, "in.jsonl")
    output = File.join(@dir, "out.jsonl")
    File.write(input, "1\n2\n")
    code, stdout, = cli("run", "-i", input, "-o", output, job("numbers.rb"), "99")

    assert_equal [0, ""], [code, stdout]
    assert_equal "1\n2\n", File.read(output)
  end

  def test_rejects_and_errors_files_get_the_context
    bad = File.join(@dir, "bad.jsonl")
    code, = cli("run", "--on-error", "skip", "--rejects", bad, "--errors", bad, job("numbers.rb"), "--", "-1", "0", "2")
    lines = File.readlines(bad).map { JSON.parse(it) }

    assert_equal 3, code
    assert_equal([["Negative", -1], ["ZeroDivisionError", 0]],
                 lines.map { [it.dig("rejection", "reason") || it.dig("failure", "error"), it["record"]] })
  end

  def test_limit_stops_after_n_records
    assert_equal [0, "2\n4\n"], cli("run", "-n", "2", job("double.rb"), stdin: "1\n2\n3\n").take(2)
  end

  def test_invalid_option_values_are_usage_errors
    assert_match(/--limit must be at least 1/, cli("run", "--limit", "0", job("double.rb"))[2])
    assert_match(/--max-errors must not be negative/, cli("run", "--max-errors", "-1", job("double.rb"))[2])
    assert_match(/--on-error must be abort or skip/, cli("run", "--on-error", "maybe", job("double.rb"))[2])
  end

  def test_the_error_policy_can_be_overridden
    assert_equal 3, cli("run", "--on-error", "skip", job("numbers.rb"), "0", "1").first
    assert_match(/--max-errors needs the error policy skip/, cli("run", "--max-errors", "3", job("numbers.rb"), "1")[2])
  end

  def test_invalid_json_lines_fail_like_records
    errors = File.join(@dir, "errors.jsonl")
    code, stdout, = cli("run", "--on-error", "skip", "--errors", errors, job("double.rb"), stdin: "1\n{oops\n3\n")
    failure = JSON.parse(File.read(errors))

    assert_equal [3, "2\n6\n"], [code, stdout]
    assert_equal ["{oops", 2, "source"], [failure["record"], failure["position"], failure.dig("failure", "step")]
  end

  def test_stats_are_written_as_json
    stats = File.join(@dir, "stats.json")
    cli("run", "--stats", stats, job("numbers.rb"), "0")
    data = JSON.parse(File.read(stats))

    assert_equal ["aborted", "Metacrunch::StepError", 1],
                 [data["status"], data.dig("error", "class"), data.dig("stats", "read")]
  end

  def test_stats_on_stdout
    code, stdout, = cli("run", "--stats", "-", "-o", File.join(@dir, "out.jsonl"), job("double.rb"), stdin: "1\n")

    assert_equal 0, code
    assert_equal({"status" => "ok", "error" => nil}, JSON.parse(stdout).slice("status", "error"))
  end

  def test_stdout_conflicts_are_usage_errors
    code, _stdout, stderr = cli("run", "--rejects", "-", job("double.rb"), stdin: "1\n")

    assert_equal 2, code
    assert_match(/stdout is used by both the default output \(the job has no sink\) and --rejects/, stderr)
  end

  def test_help_lists_the_run_options
    stdout = cli("run", "--help")[1]

    assert_match(/-i, --input PATH/, stdout)
    assert_match(/-n, --limit N/, stdout)
    assert_match(/--stats PATH/, stdout)
  end

end
```

If RuboCop reports lines over 120 characters, break the `cli(...)` argument lists after a comma.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/run_flags_test.rb`
Expected: failures with `invalid option: -i` and similar.

- [ ] **Step 3: Implement**

In `lib/metacrunch/cli/run.rb`, add below the constants:

```ruby
      def initialize(streams)
        super
        @options = {}
      end
```

and replace `execute_job`, adding `define_options` and `write_stats` (private):

```ruby
      def define_options(parser)
        super
        parser.separator("")
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source") do |path|
          @options[:input] = path
        end
        parser.on("-o", "--output PATH", "Write JSON Lines to PATH (- for stdout) instead of the job's sink") do |path|
          @options[:output] = path
        end
        parser.on("--rejects PATH", "Write rejected records with their context to PATH") { @options[:rejects] = it }
        parser.on("--errors PATH", "Write failed records with their context to PATH") { @options[:errors] = it }
        parser.on("-n", "--limit N", Integer, "Process only the first N source records") do |count|
          raise UsageError, "--limit must be at least 1" unless count.positive?

          @options[:limit] = count
        end
        parser.on("--on-error POLICY", "abort or skip, instead of the job's error policy") do |policy|
          raise UsageError, "--on-error must be abort or skip" unless ["abort", "skip"].include?(policy)

          @options[:on_error] = policy.to_sym
        end
        parser.on("--max-errors N", Integer, "Stop after more than N failed records (needs skip)") do |count|
          raise UsageError, "--max-errors must not be negative" if count.negative?

          @options[:max_errors] = count
        end
        parser.on("--stats PATH", "Write status and stats as JSON to PATH (- for stdout)") { @options[:stats] = it }
      end

      def execute_job(job, argv)
        options = RunOptions.new(**@options)
        pipeline = options.apply(build_pipeline(job, argv), stdin: @stdin, stdout: @stdout)
        result = Engine.new(pipeline).run
        write_stats(options.stats, result) if options.stats
        report(result)
      end

      def write_stats(path, result)
        error = result.error && {"class" => result.error.class.name, "message" => result.error.message}
        json = JSON.pretty_generate({"status" => result.status, "error" => error, "stats" => result.stats.to_h})
        path == JsonLines::STDIO ? @stdout.puts(json) : File.write(path, "#{json}\n")
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/run_flags_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli/run.rb test/cli/run_flags_test.rb
git commit -m "Add input, output, rejects, errors, limit, policy and stats options to run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 10: Progress display

**Files:**
- Create: `lib/metacrunch/progress.rb`, `test/unit/progress_test.rb`, `test/fixtures/jobs/slow.rb`
- Modify: `lib/metacrunch/cli.rb`, `lib/metacrunch/cli/run.rb`, `test/cli/run_flags_test.rb`

**Interfaces:**
- Consumes: monitor protocol and `LiveStats` (Task 4); `Reader#progress` (Task 5).
- Produces: `Metacrunch::Progress.new(output, mode: :line | :log, logger:, interval:, clock:, thread: true)` with `start(live)`, `stop`, `tick`, `line`; `Progress::Output.new(io)` with `write(*strings)`, `close`, `status(text)`, `clear_status`, `Output::CLEAR`; `run` option `--[no-]progress`.

- [ ] **Step 1: Write the failing tests**

`test/unit/progress_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/progress"

class ProgressTest < Minitest::Test

  Live = Struct.new(:read, :written, :filtered, :rejected, :failed, :source, :limit)
  Output = Metacrunch::Progress::Output

  # A clock the test moves.
  class Clock

    attr_accessor :now

    def initialize
      @now = 0.0
    end

    def call = now

  end

  # A source that knows how much of it was read (and has no size).
  class ProgressSource

    attr_reader :progress

    def initialize(progress)
      @progress = progress
    end

  end

  # stderr of a terminal with 10 columns.
  class NarrowTerminal < StringIO

    def winsize = [24, 10]

  end

  def setup
    @clock = Clock.new
    @live = Live.new(read: 0, written: 0, filtered: 0, rejected: 0, failed: 0, source: Object.new, limit: nil)
  end

  def test_a_line_without_a_known_total_shows_a_spinner
    progress = start(:line)
    advance(2.0, read: 20_000)

    assert_equal "⠙ 00:00:02  read 20.0k (10.0k/s)  written 0", progress.line
  end

  def test_a_known_total_shows_a_bar_and_the_eta
    @live.source = ProgressSource.new(0.5)
    progress = start(:line)
    advance(10.0, read: 500, written: 490, rejected: 3)

    assert_equal "━━━━━━━━━━────────── 50% 00:00:10 ETA 00:00:10  read 500 (50.0/s)  written 490  rejected 3",
                 progress.line
  end

  def test_the_total_comes_from_the_size_or_the_limit
    @live.source = Array.new(100)
    advance(1.0, read: 25)
    sized = start(:line).line
    @live.source = Object.new
    @live.limit = 50
    limited = start(:line).line

    assert_match(/ 25% /, sized)
    assert_match(/ 50% /, limited)
  end

  def test_unknown_or_infinite_sizes_are_ignored
    @live.source = (1..)
    progress = start(:line)
    advance(1.0, read: 5)

    assert_match(/\A⠙ 00:00:01  read 5 /, progress.line)
  end

  def test_the_rate_covers_the_last_seconds
    progress = start(:line)
    advance(10.0, read: 10_000)
    progress.line
    advance(16.0, read: 10_600)

    assert_match(%r{read 10\.6k \(100\.0/s\)}, progress.line)
  end

  def test_log_mode_logs_the_status
    io = StringIO.new
    logger = Logger.new(io, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    progress = Metacrunch::Progress.new(Output.new(StringIO.new), mode: :log, logger:, clock: @clock, thread: false)
    progress.start(@live)
    advance(10.0, read: 100)
    progress.tick

    assert_equal "progress 00:00:10  read 100 (10.0/s)  written 0\n", io.string
  end

  def test_the_status_line_is_cleared_before_log_lines
    io = StringIO.new
    output = Output.new(io)
    output.status("working")
    output.write("log line\n")
    output.status("working")
    output.clear_status

    assert_equal "\r\e[2Kworking\r\e[2Klog line\n\r\e[2Kworking\r\e[2K", io.string
  end

  def test_the_status_line_is_cut_to_the_terminal_width
    io = NarrowTerminal.new
    Output.new(io).status("0123456789abc")

    assert_equal "\r\e[2K012345678", io.string
  end

  def test_the_thread_draws_until_stopped
    io = StringIO.new
    progress = Metacrunch::Progress.new(Output.new(io), mode: :line, logger: nil, interval: 0.01)
    progress.start(@live)
    sleep(0.05)
    progress.stop

    assert_includes io.string, "read 0"
    assert(io.string.end_with?(Output::CLEAR))
  end

  private

  def start(mode)
    progress = Metacrunch::Progress.new(Output.new(StringIO.new), mode:, logger: nil, clock: @clock, thread: false)
    progress.start(@live)
    progress
  end

  def advance(now, **counts)
    @clock.now = now
    counts.each { |name, value| @live[name] = value }
  end

end
```

`test/fixtures/jobs/slow.rb`:

```ruby
# frozen_string_literal: true

# Takes long enough for the progress display to draw.
Metacrunch.job do
  source [1, 2]
  map do |record|
    sleep(0.2)
    record
  end
end
```

Append to `test/cli/run_flags_test.rb`:

```ruby
  def test_progress_is_shown_on_a_terminal
    stderr = TerminalOutput.new
    code, = cli("run", job("slow.rb"), stderr:)

    assert_equal 0, code
    assert_match(%r{read \d+ \(.*/s\)  written \d+}, stderr.string)
    assert_includes stderr.string, "\r\e[2K"
  end

  def test_no_progress_when_quiet_or_disabled
    quiet = TerminalOutput.new
    disabled = TerminalOutput.new
    cli("run", "-q", job("slow.rb"), stderr: quiet)
    cli("run", "--no-progress", job("slow.rb"), stderr: disabled)

    refute_includes quiet.string, "\e[2K"
    refute_includes disabled.string, "\e[2K"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/progress_test.rb`
Expected: `LoadError: cannot load such file -- metacrunch/progress`.

- [ ] **Step 3: Implement**

`lib/metacrunch/progress.rb`:

```ruby
# frozen_string_literal: true

require "io/console"

module Metacrunch
  # Shows the progress of a run on stderr; an Engine monitor (start, stop).
  # In :line mode (stderr is a terminal) it redraws one status line; in :log
  # mode it logs the status every 10 seconds. A background thread reads the
  # live counters, so the engine does no extra work per record.
  class Progress

    SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze
    BAR_WIDTH = 20
    # Seconds the rate is averaged over.
    RATE_WINDOW = 5.0
    INTERVALS = {line: 0.25, log: 10.0}.freeze

    # stderr shared by the logger and the status line. Each log write first
    # clears the status line; the next tick draws it again.
    class Output

      CLEAR = "\r\e[2K"

      def initialize(io)
        @io = io
        @mutex = Mutex.new
        @status = false
      end

      # For Logger, which needs write and close.
      def write(*strings)
        @mutex.synchronize do
          clear_line
          @io.write(*strings)
        end
      end

      def close = nil

      def status(text)
        @mutex.synchronize do
          @io.write(CLEAR, fit(text))
          @io.flush
          @status = true
        end
      end

      def clear_status
        @mutex.synchronize { clear_line }
      end

      private

      def clear_line
        return unless @status

        @io.write(CLEAR)
        @status = false
      end

      # Cuts the text to the terminal width, so it never wraps.
      def fit(text)
        width = terminal_width
        width && text.size >= width ? text[0, width - 1] : text
      end

      def terminal_width
        @io.winsize[1] if @io.respond_to?(:winsize)
      rescue SystemCallError
        nil
      end

    end

    # output: the Output shared with the logger. logger: for :log mode.
    # clock and thread can be replaced in tests.
    def initialize(output, mode:, logger:, interval: INTERVALS.fetch(mode), clock: nil, thread: true)
      @output = output
      @mode = mode
      @logger = logger
      @interval = interval
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @threaded = thread
      @frame = 0
    end

    def start(live)
      @live = live
      @started = @clock.call
      @samples = [[@started, 0]]
      @thread = Thread.new { loop { sleep(@interval); tick } } if @threaded
    end

    def stop
      @thread&.kill&.join
      @thread = nil
      @output.clear_status if @mode == :line
    end

    def tick
      @mode == :line ? @output.status(line) : @logger.info(line)
    end

    # The status: progress (bar or spinner), elapsed time, ETA and counts.
    def line
      now = @clock.call
      read = @live.read
      [head(now - @started, fraction(read)), counts(read, rate(now, read))].join("  ")
    end

    private

    def head(elapsed, done)
      percent = done && "#{(done * 100).floor}%"
      eta = done&.positive? && done < 1 ? "ETA #{duration(elapsed * (1 - done) / done)}" : nil
      [marker(done), percent, duration(elapsed), eta].compact.join(" ")
    end

    def marker(done)
      return "progress" if @mode == :log

      done ? bar(done) : spinner
    end

    def counts(read, rate)
      parts = ["read #{number(read)} (#{number(rate)}/s)", "written #{number(@live.written)}"]
      {"filtered" => @live.filtered, "rejected" => @live.rejected, "failed" => @live.failed}.each do |label, count|
        parts << "#{label} #{number(count)}" if count.positive?
      end
      parts.join("  ")
    end

    # Records per second over the last RATE_WINDOW seconds: the oldest kept
    # sample is the newest one that is at least that old.
    def rate(now, read)
      @samples << [now, read]
      @samples.shift while @samples.size > 2 && now - @samples[1][0] >= RATE_WINDOW
      first_time, first_read = @samples.first
      span = now - first_time
      span.positive? ? (read - first_read) / span : 0.0
    end

    # The share of the input done, from the source's progress or size or
    # the limit; nil if unknown. count is never called: it would iterate.
    def fraction(read)
      source = @live.source
      size = source.respond_to?(:size) ? source.size : nil
      limit = @live.limit
      candidates = [source.respond_to?(:progress) ? source.progress : nil]
      candidates << read.fdiv(size) if size.is_a?(Integer) && size.positive?
      candidates << read.fdiv(limit) if limit
      done = candidates.compact.max
      done && [done, 1.0].min
    end

    def number(value)
      return format("%.2fM", value / 1_000_000.0) if value >= 1_000_000
      return format("%.1fk", value / 1000.0) if value >= 1000
      return format("%.1f", value) if value.is_a?(Float)

      value.to_s
    end

    def duration(seconds)
      total = seconds.to_i
      format("%<hours>02d:%<minutes>02d:%<seconds>02d", hours: total / 3600, minutes: total % 3600 / 60,
                                                        seconds: total % 60)
    end

    def bar(done)
      filled = (done * BAR_WIDTH).floor
      ("━" * filled) + ("─" * (BAR_WIDTH - filled))
    end

    def spinner
      SPINNER[(@frame += 1) % SPINNER.size]
    end

  end
end
```

`lib/metacrunch/cli.rb`: add `require_relative "progress"` after `require_relative "../metacrunch"`.

`lib/metacrunch/cli/run.rb`:
- in `define_options`, after the `--stats` line:

```ruby
        parser.on("--[no-]progress", "Show progress on stderr (default: if stderr is a terminal)") { @progress = it }
```

- in `execute_job`, use `result = Engine.new(pipeline, monitor: progress).run`;
- add private methods:

```ruby
      # A status line if stderr is a terminal, log lines with --progress
      # otherwise; none with -q unless --progress is given.
      def progress
        enabled = @progress.nil? ? @stderr.tty? && @log_level < Logger::WARN : @progress
        return unless enabled

        Progress.new(log_output, mode: @stderr.tty? ? :line : :log, logger:)
      end

      def log_output
        @log_output ||= Progress::Output.new(@stderr)
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/progress_test.rb && bundle exec ruby -w -Ilib -Itest test/cli/run_flags_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/progress.rb lib/metacrunch/cli.rb lib/metacrunch/cli/run.rb test/unit/progress_test.rb \
  test/cli/run_flags_test.rb test/fixtures/jobs/slow.rb
git commit -m "Show the progress of a run on stderr

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 11: `check`

**Files:**
- Create: `lib/metacrunch/cli/check.rb`, `test/cli/check_test.rb`, `test/fixtures/jobs/unopenable.rb`
- Modify: `lib/metacrunch/cli.rb`, `lib/metacrunch/sink_adapter.rb`

**Interfaces:**
- Consumes: `JobCommand` (Task 8).
- Produces: `Cli::CheckCommand`; `SinkAdapter#batch`; `Cli::COMMANDS` gains `"check"` (after `"run"`).

- [ ] **Step 1: Write the failing tests**

`test/fixtures/jobs/unopenable.rb`:

```ruby
# frozen_string_literal: true

# Fails as soon as anything is opened, read or run.
class Unopenable

  def open(_context) = raise("must not be opened")

  def each = raise("must not be read")

end

Metacrunch.job do
  source Unopenable.new
  before { raise "hooks must not run" }
end
```

`test/cli/check_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CheckTest < Minitest::Test

  include CliHelper

  CATALOG = File.expand_path("../fixtures/catalog.json", __dir__)

  def test_describes_a_valid_job
    code, stdout, = cli("check", job("catalog.rb"), "--output", "/secret/dir", CATALOG)

    assert_equal 0, code
    assert_equal <<~TEXT, stdout
      #{job("catalog.rb")}: job "catalog" OK
        input     JsonArrayFile (id extractor)
        steps     reject#1 "Not public", filter#2, map#3, flat_map#4
        output    JsonLinesFile, batch 2
        rejects   JsonLinesFile
        errors    JsonLinesFile
        on_error  skip, max_errors 5
    TEXT
    refute_includes stdout, "secret"
  end

  def test_describes_a_filter_job
    assert_equal [0, <<~TEXT], cli("check", job("double.rb")).take(2)
      #{job("double.rb")}: job "double" OK
        input     stdin (JSON Lines)
        steps     map#1
        output    stdout (JSON Lines)
        on_error  abort
    TEXT
  end

  def test_opens_and_runs_nothing
    assert_equal 0, cli("check", job("unopenable.rb")).first
  end

  def test_invalid_jobs_exit_with_the_usage_code
    code, _stdout, stderr = cli("check", job("broken_recipe.rb"))

    assert_equal [2, 2], [code, cli("check", job("numbers.rb")).first]
    assert_match(/Error: \S*broken_recipe\.rb: NameError: uninitialized constant UndefinedSource/, stderr)
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/check_test.rb`
Expected: failures; `check` is treated as a job file (`unknown command or job file: check`).

- [ ] **Step 3: Implement**

`lib/metacrunch/sink_adapter.rb`: change `attr_reader :sink, :delivered` to `attr_reader :sink, :delivered, :batch` and extend the comment above it with `batch: the batch size or nil.`

`lib/metacrunch/cli/check.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch check: loads the job, binds its parameters and builds the
    # pipeline. Opens nothing, reads no record, runs no hook. Parameter
    # values are not printed; they may contain secrets.
    class CheckCommand < JobCommand

      NAME = "check"
      SUMMARY = "Validate a job without running it"
      USAGE = "check [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"

      private

      def execute_job(job, argv)
        pipeline = build_pipeline(job, argv)
        @stdout.puts(description(job, pipeline))
        EXIT_CODES[:ok]
      rescue *Engine::RECOVERABLE => e
        raise if e.is_a?(ParamError)

        @stderr.puts("Error: #{@job_file}: #{e.class}: #{e.message.lines.first&.chomp}")
        EXIT_CODES[:usage]
      end

      def description(job, pipeline)
        rows = [["input", input(pipeline)], ["steps", steps(pipeline)]]
        rows << ["output", pipeline.sink ? sink(pipeline.sink) : "stdout (JSON Lines)"]
        rows << ["rejects", sink(pipeline.rejects)] if pipeline.rejects
        rows << ["errors", sink(pipeline.errors)] if pipeline.errors
        rows << ["on_error", policy(pipeline)]
        title = job.name ? "job #{job.name.inspect}" : "job"
        ["#{@job_file}: #{title} OK", *rows.map { |label, text| "  #{label.ljust(9)} #{text}" }].join("\n")
      end

      def input(pipeline)
        name = pipeline.source ? pipeline.source.class.name : "stdin (JSON Lines)"
        pipeline.id_extractor ? "#{name} (id extractor)" : name
      end

      def steps(pipeline)
        return "none" if pipeline.steps.empty?

        pipeline.steps.map { |step| step.reason ? "#{step.name} #{step.reason.inspect}" : step.name }.join(", ")
      end

      def sink(adapter)
        adapter.batch ? "#{adapter.sink.class.name}, batch #{adapter.batch}" : adapter.sink.class.name
      end

      def policy(pipeline)
        return pipeline.on_error.to_s unless pipeline.max_errors

        "#{pipeline.on_error}, max_errors #{pipeline.max_errors}"
      end

    end
  end
end
```

`lib/metacrunch/cli.rb`: add `require_relative "cli/check"` after `require_relative "cli/run"`, and change `COMMANDS` to `{"run" => RunCommand, "check" => CheckCommand}.freeze`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/check_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli/check.rb lib/metacrunch/cli.rb lib/metacrunch/sink_adapter.rb test/cli/check_test.rb \
  test/fixtures/jobs/unopenable.rb
git commit -m "Add the check command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 12: Diff

**Files:**
- Create: `lib/metacrunch/diff.rb`, `test/unit/diff_test.rb`

**Interfaces:**
- Produces: `Metacrunch::Diff.changes(before, after)` → Array of `Diff::Change` (`Data`: `kind` (`:removed`, `:added`, `:changed`), `path` (String, dotted for nested Hashes), `before`, `after`), ordered removed, added, changed, each in key order.

- [ ] **Step 1: Write the failing tests**

`test/unit/diff_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/diff"

class DiffTest < Minitest::Test

  def test_removed_added_and_changed_keys_in_that_order
    changes = diff({"_id" => 1, "title" => "a", "x" => 1}, {"title" => "b", "x" => 1, "id" => 1})

    assert_equal [[:removed, "_id", 1, nil], [:added, "id", nil, 1], [:changed, "title", "a", "b"]], changes
  end

  def test_nested_hashes_are_compared_by_path
    changes = diff({"meta" => {"source" => "ris", "v" => 1}}, {"meta" => {"source" => "fis", "v" => 1}})

    assert_equal [[:changed, "meta.source", "ris", "fis"]], changes
  end

  def test_arrays_and_replaced_hashes_are_compared_as_a_whole
    assert_equal [[:changed, "isbns", [1], [1, 2]]], diff({"isbns" => [1]}, {"isbns" => [1, 2]})
    assert_equal [[:changed, "meta", {"a" => 1}, "x"]], diff({"meta" => {"a" => 1}}, {"meta" => "x"})
  end

  def test_equal_records_have_no_changes_and_symbol_keys_become_paths
    assert_empty diff({"a" => [1]}, {"a" => [1]})
    assert_equal [[:added, "b", nil, 2]], diff({a: 1}, {a: 1, b: 2})
  end

  private

  def diff(before, after)
    Metacrunch::Diff.changes(before, after).map { it.to_h.values }
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/diff_test.rb`
Expected: `LoadError: cannot load such file -- metacrunch/diff`.

- [ ] **Step 3: Implement**

`lib/metacrunch/diff.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Compares two Hash records for trace. Nested Hashes are compared key by
  # key with a dotted path ("meta.source"); other values, including Arrays,
  # as a whole.
  module Diff

    # kind: :removed, :added or :changed. before or after is nil when the
    # key is missing on that side.
    Change = Data.define(:kind, :path, :before, :after)

    ORDER = {removed: 0, added: 1, changed: 2}.freeze

    module_function

    # The changes from before to after: removed keys first, then added, then
    # changed ones, each in key order.
    def changes(before, after)
      collect(before, after, nil).sort_by.with_index { |change, index| [ORDER.fetch(change.kind), index] }
    end

    def collect(before, after, prefix)
      (before.keys | after.keys).flat_map do |key|
        compare(before, after, key, prefix ? "#{prefix}.#{key}" : key.to_s)
      end
    end

    def compare(before, after, key, path)
      return [Change.new(kind: :added, path:, before: nil, after: after[key])] unless before.key?(key)
      return [Change.new(kind: :removed, path:, before: before[key], after: nil)] unless after.key?(key)

      old_value = before[key]
      new_value = after[key]
      return collect(old_value, new_value, path) if old_value.is_a?(Hash) && new_value.is_a?(Hash)
      return [] if old_value == new_value

      [Change.new(kind: :changed, path:, before: old_value, after: new_value)]
    end

  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/diff_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/diff.rb test/unit/diff_test.rb
git commit -m "Add a Hash diff for trace

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 13: Trace observer and renderer

`Trace` collects the observer events of one source record into a tree (steps, `flat_map` children, their later steps) and prints it when the next record starts or the run ends. The renderer turns the tree into text with diffs.

Layout rule used by all expected outputs below: a step row is `"  " * depth + label.ljust(name_width) + "  " + text`, right-stripped; `name_width` is the longest of all step names, `"source"` and `"sink"`; continuation rows use an empty label. Depth 1 for the record's steps, depth 2 for `[k]` children of a depth-1 `flat_map`, depth 3 for their steps.

**Files:**
- Create: `lib/metacrunch/trace.rb`, `lib/metacrunch/trace/renderer.rb`, `test/unit/trace_test.rb`

**Interfaces:**
- Consumes: observer events (sub-project 1 plus Task 1 refinements), `SOURCE_STEP`, `InvalidRecord`, `Diff.changes` (Task 12).
- Produces: `Metacrunch::Trace.new(io, pipeline:, positions: nil, ids: nil, full: false, color: false, width: 160)` with `trace?(record, position)` (select callable), `step_in`, `step_out`, `finish`; `Trace::NullSink` (`write(record)` does nothing); `Trace::Opaque` (`Data`: `text`); `Trace::Renderer.new(full:, color:, width:, name_width:)` with `record(node)` → String, `summary(totals)` → String.

- [ ] **Step 1: Write the failing tests**

`test/unit/trace_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/trace"

class TraceTest < Minitest::Test

  include PipelineHelper

  # A record Marshal cannot copy.
  class Unmarshalable

    def initialize
      @callback = proc {}
    end

    def inspect = "#<Unmarshalable>"

  end

  def test_shows_the_effect_of_each_step
    output = trace_run do
      source [{"_id" => 1, "public" => true}, {"_id" => 2, "public" => false}], id: ->(record) { record["_id"] }
      reject("Not public") { !it["public"] }
      filter { it["_id"] < 10 }
      map { |record| {"id" => record["_id"]} }
    end

    assert_equal <<~TEXT, output
      #1  id=1
        reject#1  pass
        filter#2  pass
        map#3     - "_id": 1
                  - "public": true
                  + "id": 1
        sink      1 record (not written)
      #2  id=2
        reject#1  rejected: Not public
      traced 2 records: 1 to sink, 1 rejected
    TEXT
  end

  def test_shows_flat_map_children_and_their_way_through_later_steps
    output = trace_run do
      source [{"id" => 17, "isbns" => ["a", "b"]}]
      flat_map do |record|
        isbns = record.delete("isbns")
        isbns.map { |isbn| record.merge("isbn" => isbn) }
      end
      map { |record| record["isbn"] == "b" ? raise(KeyError, "no b") : record.merge("ok" => true) }
      on_error :skip
    end

    assert_equal <<~TEXT, output.sub(%r{  \(test/unit/trace_test\.rb:\d+\)}, "  (LOCATION)")
      #1
        flat_map#1  → 2 records
          [1]         - "isbns": ["a","b"]
                      + "isbn": "a"
            map#2       + "ok": true
          [2]         - "isbns": ["a","b"]
                      + "isbn": "b"
            map#2       failed: KeyError: no b  (LOCATION)
        sink        1 record (not written)
      traced 1 record: 1 to sink, 1 failed
    TEXT
  end

  def test_shows_other_records_in_full
    output = trace_run do
      source [1, 2]
      map { it * 10 }
      filter { it > 10 }
      map { it }
    end

    assert_equal <<~TEXT, output
      #1
        map#1     1 → 10
        filter#2  filtered
      #2
        map#1     2 → 20
        filter#2  pass
        map#3     unchanged
        sink      1 record (not written)
      traced 2 records: 1 to sink, 1 filtered
    TEXT
  end

  def test_shows_marks
    output = trace_run do
      source [{"id" => 1}]
      map do |record, ctx|
        ctx.mark("No title", value: 3)
        record
      end
    end

    assert_equal <<~TEXT, output
      #1
        map#1   unchanged
                mark: No title (3)
        sink    1 record (not written)
      traced 1 record: 1 to sink
    TEXT
  end

  def test_shows_invalid_records
    bad = Metacrunch::InvalidRecord.new(raw: "{oops", error: JSON::ParserError.new("unexpected token"))
    output = trace_run do
      source [bad]
      map { it }
      on_error :skip
    end

    assert_equal <<~TEXT, output
      #1
        source  failed: JSON::ParserError: unexpected token
                raw: "{oops"
      traced 1 record: 0 to sink, 1 failed
    TEXT
  end

  def test_full_shows_whole_records
    output = trace_run(full: true) do
      source [{"a" => 1}]
      map { it.merge("b" => 2) }
    end

    assert_equal <<~TEXT, output
      #1
        map#1   in:  {"a":1}
                out: {"a":1,"b":2}
        sink    1 record (not written)
      traced 1 record: 1 to sink
    TEXT
  end

  def test_traces_selected_positions_and_ids_once
    by_position = trace_run(positions: [2, 4]) do
      source ["a", "b", "c", "d"]
      map(&:upcase)
    end
    by_id = trace_run(ids: ["2"]) do
      source [{"id" => 1}, {"id" => 2}, {"id" => 2}], id: ->(record) { record["id"] }
    end

    assert_equal ["#2\n", "#4\n"], by_position.lines.grep(/\A#/)
    assert_includes by_position, "  map#1   \"b\" → \"B\"\n"
    assert_equal ["#2  id=2\n"], by_id.lines.grep(/\A#/)
  end

  def test_records_that_cannot_be_copied_are_shown_by_inspect
    record = Unmarshalable.new
    output = trace_run do
      source [record]
      map { "done" }
    end

    assert_includes output, "  map#1   #<Unmarshalable> → \"done\"\n"
  end

  def test_long_values_are_shortened_unless_full
    output = trace_run(width: 40) do
      source [{"text" => "x" * 50}]
      map { it.merge("text" => "y") }
    end

    assert_includes output, "~ \"text\": \"#{"x" * 20}… → \"y\""
  end

  def test_colors
    output = trace_run(color: true) do
      source [{"a" => 1}]
      map { it.merge("id" => 1) }
    end

    assert_includes output, "\e[1m#1\e[0m"
    assert_includes output, "\e[32m+ \"id\": 1\e[0m"
  end

  def test_a_job_without_steps
    assert_equal "#1\n  sink    1 record (not written)\ntraced 1 record: 1 to sink\n", trace_run { source [1] }
  end

  private

  def trace_run(positions: nil, ids: nil, full: false, color: false, width: 160, &)
    pipeline = build_pipeline(&)
    io = StringIO.new
    trace = Metacrunch::Trace.new(io, pipeline:, positions:, ids:, full:, color:, width:)
    Metacrunch::Engine.new(pipeline, observer: trace, select: trace.method(:trace?)).run
    trace.finish
    io.string
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/trace_test.rb`
Expected: `LoadError: cannot load such file -- metacrunch/trace`.

- [ ] **Step 3: Implement**

`lib/metacrunch/trace/renderer.rb`:

```ruby
# frozen_string_literal: true

require "json"

module Metacrunch
  class Trace
    # Turns the collected steps of one record into lines of text: a diff
    # per step for Hash records, inspect-like values otherwise.
    class Renderer

      INDENT = "  "
      COLORS = {header: 1, dim: 2, removed: 31, failed: 31, added: 32, changed: 33, note: 36}.freeze
      # Backtrace lines in here are metacrunch's own, not the job's.
      LIB = "#{File.expand_path("../..", __dir__)}/".freeze

      def initialize(full:, color:, width:, name_width:)
        @full = full
        @color = color
        @name_width = name_width
        @value_width = [width - name_width - 12, 20].max
      end

      # The lines of one traced record.
      def record(node)
        header = node.id.nil? ? "##{node.position}" : "##{node.position}  id=#{node.id}"
        lines = [paint(:header, header)]
        node.steps.each { step(it, 1, lines) }
        lines << row(1, "sink", "#{count(node.to_sink, "record")} (not written)") if node.to_sink.positive?
        lines.join("\n")
      end

      def summary(totals)
        parts = ["#{totals[:to_sink]} to sink"]
        [:filtered, :rejected, :failed].each { |key| parts << "#{totals[key]} #{key}" if totals[key].positive? }
        "traced #{count(totals[:records], "record")}: #{parts.join(", ")}"
      end

      private

      def step(node, depth, lines)
        texts = effect(node) + node.marks.map { paint(:note, "mark: #{mark(it)}") }
        lines << row(depth, node.name, texts.first)
        texts.drop(1).each { lines << row(depth, "", it) }
        node.children.each_with_index { |child, index| child_lines(child, index + 1, node.input, depth + 1, lines) }
      end

      def child_lines(child, number, parent_input, depth, lines)
        texts = @full ? [show(child.record)] : changes(parent_input, child.record)
        lines << row(depth, "[#{number}]", texts.first)
        texts.drop(1).each { lines << row(depth, "", it) }
        child.steps.each { step(it, depth + 1, lines) }
      end

      def effect(node)
        return failure(node) if node.failure
        return [paint(:failed, "rejected: #{node.rejection.reason}")] if node.rejection

        case node.kind
        when :flat_map then ["→ #{count(node.outputs.size, "record")}"]
        when :map then @full ? full(node) : changes(node.input, node.outputs.first)
        else @full ? full(node) : [node.outputs.empty? ? "filtered" : paint(:dim, "pass")]
        end
      end

      def failure(node)
        error = node.failure.error
        text = "failed: #{error.class}: #{error.message.lines.first&.chomp}"
        location = node.kind == :source ? nil : location(error)
        lines = [paint(:failed, location ? "#{text}  (#{location})" : text)]
        lines << "raw: #{show(node.input)}" if node.kind == :source
        lines
      end

      def full(node)
        outputs = node.outputs.map { "out: #{show(it)}" }
        ["in:  #{show(node.input)}", *(outputs.empty? ? ["out: (none)"] : outputs)]
      end

      def changes(before, after)
        return [paint(:dim, "unchanged")] if before == after
        return ["#{show(before)} → #{show(after)}"] unless before.is_a?(Hash) && after.is_a?(Hash)

        Diff.changes(before, after).map { change(it) }
      end

      def change(change)
        path = JSON.generate(change.path)
        case change.kind
        when :removed then paint(:removed, "- #{path}: #{show(change.before)}")
        when :added then paint(:added, "+ #{path}: #{show(change.after)}")
        else paint(:changed, "~ #{path}: #{show(change.before)} → #{show(change.after)}")
        end
      end

      def mark(mark)
        mark.value.nil? ? mark.reason : "#{mark.reason} (#{show(mark.value)})"
      end

      def show(value)
        text = value.is_a?(Opaque) ? value.text : json(value)
        @full || text.size <= @value_width ? text : "#{text[0, @value_width - 1]}…"
      end

      def json(value)
        JSON.generate(value, strict: true)
      rescue JSON::GeneratorError
        value.inspect
      end

      # The first backtrace line outside metacrunch, relative to the working
      # directory, without the method name.
      def location(error)
        line = error.backtrace&.find { !it.start_with?(LIB, "<internal:") }
        line&.delete_prefix("#{Dir.pwd}/")&.sub(/:in .*\z/, "")
      end

      def row(depth, label, text)
        "#{INDENT * depth}#{label.ljust(@name_width)}  #{text}".rstrip
      end

      def count(number, word) = "#{number} #{word}#{"s" unless number == 1}"

      def paint(style, text)
        @color ? "\e[#{COLORS.fetch(style)}m#{text}\e[0m" : text
      end

    end
  end
end
```

`lib/metacrunch/trace.rb`:

```ruby
# frozen_string_literal: true

require_relative "diff"
require_relative "trace/renderer"

module Metacrunch
  # Shows what each step does to a few records (metacrunch trace). The
  # engine gets it as observer (step_in, step_out) and #trace? as select:.
  # The events of one source record are collected into a tree and printed
  # when the next record starts or the run ends (#finish), because flat_map
  # children pass the later steps before their flat_map step ends.
  class Trace

    # Snapshot of a record that Marshal cannot copy.
    Opaque = Data.define(:text)
    RecordNode = Struct.new(:position, :id, :steps, :to_sink)
    StepNode = Struct.new(:name, :kind, :input, :outputs, :marks, :rejection, :failure, :children, :marks_before)
    ChildNode = Struct.new(:record, :steps)

    # A sink that discards everything: trace writes nothing.
    class NullSink

      def write(_record) = nil

    end

    def initialize(io, pipeline:, positions: nil, ids: nil, full: false, color: false, width: 160)
      @io = io
      @id_extractor = pipeline.id_extractor
      @kinds = pipeline.steps.to_h { [it.name, it.kind] }.merge(SOURCE_STEP => :source)
      @last_step = pipeline.steps.last&.name
      @positions = positions && Set.new(positions)
      @ids = ids && Set.new(ids.map(&:to_s))
      name_width = [*@kinds.keys, "sink"].map(&:size).max
      @renderer = Renderer.new(full:, color:, width:, name_width:)
      @totals = Hash.new(0)
      @record = nil
    end

    # The select callable: true for every record without positions or ids,
    # otherwise for each listed position or id once. Starts the record.
    def trace?(record, position)
      return false unless wanted?(record, position)

      start_record(record, position)
      true
    end

    def step_in(step, record, ctx)
      node = StepNode.new(name: step, kind: @kinds.fetch(step), input: snapshot(record), outputs: [], marks: [],
                          children: [], marks_before: ctx.marks.size)
      (@lists[ctx] ||= new_list(record)) << node
      @current[ctx] = node
      @open.push(node) if node.kind == :flat_map
    end

    def step_out(step, outputs, ctx)
      node = @current.delete(ctx)
      node.outputs = outputs.map { snapshot(it) }
      if node.kind == :flat_map
        @open.pop
        # Children that passed no later step (flat_map is the last step).
        node.children.concat(node.outputs.drop(node.children.size).map { ChildNode.new(record: it, steps: []) })
      end
      node.marks = ctx.marks.drop(node.marks_before)
      node.rejection = ctx.rejection if ctx.rejection&.step == step
      node.failure = ctx.failure if ctx.failure&.step == step
      count(node)
    end

    # Prints the last record and the summary. Call after the run.
    def finish
      flush_record
      @io.puts(@renderer.summary(@totals))
    end

    private

    def wanted?(record, position)
      return !@positions.delete?(position).nil? if @positions
      return true unless @ids

      id = record_id(record)
      !id.nil? && !@ids.delete?(id.to_s).nil?
    end

    def record_id(record)
      return if record.is_a?(InvalidRecord) || @id_extractor.nil?

      @id_extractor.call(record)
    end

    def start_record(record, position)
      flush_record
      direct = @last_step.nil? && !record.is_a?(InvalidRecord) ? 1 : 0
      @record = RecordNode.new(position:, id: record_id(record), steps: [], to_sink: direct)
      @lists = {}.compare_by_identity
      @current = {}.compare_by_identity
      @open = []
      @totals[:records] += 1
    end

    def flush_record
      return unless @record

      @totals[:to_sink] += @record.to_sink
      @io.puts(@renderer.record(@record))
      @record = nil
    end

    # The step list for a context seen for the first time: the record's own
    # list, or a new child of the innermost open flat_map.
    def new_list(record)
      parent = @open.last
      return @record.steps unless parent

      child = ChildNode.new(record: snapshot(record), steps: [])
      parent.children << child
      child.steps
    end

    def count(node)
      if node.failure
        @totals[:failed] += 1
      elsif node.rejection
        @totals[:rejected] += 1
      elsif node.outputs.empty? && [:filter, :reject].include?(node.kind)
        @totals[:filtered] += 1
      end
      @record.to_sink += node.outputs.size if node.name == @last_step
    end

    # Steps may change records in place, so inputs and outputs are copied
    # when the event happens.
    def snapshot(record)
      Marshal.load(Marshal.dump(record))
    rescue TypeError
      Opaque.new(text: record.inspect)
    end

  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/trace_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean. If an expected text differs only in column alignment, recompute it from the layout rule at the top of this task rather than changing the renderer.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/trace.rb lib/metacrunch/trace/renderer.rb test/unit/trace_test.rb
git commit -m "Add the trace observer and renderer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 14: `trace` command

**Files:**
- Create: `lib/metacrunch/cli/trace.rb`, `test/cli/trace_test.rb`
- Modify: `lib/metacrunch/cli.rb`

**Interfaces:**
- Consumes: `Trace` (Task 13), `RunOptions#apply_input` (Task 7), `JobCommand` (Task 8).
- Produces: `Cli::TraceCommand`; `Cli::COMMANDS` gains `"trace"` (after `"check"`).

- [ ] **Step 1: Write the failing tests**

`test/cli/trace_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TraceCommandTest < Minitest::Test

  include CliHelper

  CATALOG = File.expand_path("../fixtures/catalog.json", __dir__)

  def test_traces_the_first_records_without_writing
    Dir.mktmpdir do |dir|
      code, stdout, = cli("trace", "-n", "2", job("catalog.rb"), "--output", dir, CATALOG)

      assert_equal [0, []], [code, Dir.children(dir)]
      assert_match(/\A#1  id=1\n  reject#1    pass\n/, stdout)
      assert_match(/^traced 2 records: 2 to sink, 1 rejected$/, stdout)
    end
  end

  def test_traces_selected_positions
    code, stdout, = cli("trace", "--position", "5", job("catalog.rb"), "--output", "unused", CATALOG)

    assert_equal 0, code
    assert_match(/\A#5  id=5\n/, stdout)
    assert_match(/  map#3       failed: KeyError: key not found: "isbns"/, stdout)
  end

  def test_traces_json_lines_from_stdin
    code, stdout, = cli("trace", job("double.rb"), stdin: "1\n{oops\n")

    assert_equal 0, code
    assert_includes stdout, "  map#1   1 → 2\n"
    assert_includes stdout, "  source  failed: JSON::ParserError"
  end

  def test_usage_errors
    assert_match(/use either --position or --id/, cli("trace", "--position", "1", "--id", "a", job("double.rb"))[2])
    assert_match(/--position needs positive numbers, got x/, cli("trace", "--position", "x", job("double.rb"))[2])
    assert_match(/--limit must be at least 1/, cli("trace", "-n", "0", job("double.rb"))[2])
  end

  def test_an_aborted_trace_exits_with_one
    code, _stdout, stderr = cli("trace", job("chained_error.rb"))

    assert_equal 1, code
    assert_match(/ERROR ArgumentError: source broke/, stderr)
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/trace_test.rb`
Expected: failures (`unknown command or job file: trace`).

- [ ] **Step 3: Implement**

`lib/metacrunch/cli/trace.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch trace: shows what each step does to the first records. All
    # sinks are replaced by null sinks; failures are shown and skipped.
    class TraceCommand < JobCommand

      NAME = "trace"
      SUMMARY = "Show what each step does to the first records"
      USAGE = "trace [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]"
      DEFAULT_LIMIT = 10
      DEFAULT_WIDTH = 160

      def initialize(streams)
        super
        @full = false
      end

      private

      def define_options(parser)
        super
        parser.separator("")
        parser.on("-n", "--limit N", Integer, "Trace N records (default: #{DEFAULT_LIMIT})") do |count|
          raise UsageError, "--limit must be at least 1" unless count.positive?

          @limit = count
        end
        parser.on("--position LIST", Array, "Trace only these positions, e.g. 12,4711") do |list|
          @positions = list.map { position(it) }
        end
        parser.on("--id LIST", Array, "Trace only records with these ids") { @ids = it }
        parser.on("--full", "Show whole records instead of changes") { @full = true }
        parser.on("-i", "--input PATH", "Read JSON Lines from PATH (- for stdin) instead of the job's source") do |path|
          @input = path
        end
      end

      def execute_job(job, argv)
        raise UsageError, "use either --position or --id" if @positions && @ids

        pipeline = traced_pipeline(build_pipeline(job, argv))
        trace = Metacrunch::Trace.new(@stdout, pipeline:, positions: @positions, ids: @ids, full: @full,
                                               color: color?, width:)
        result = Engine.new(pipeline, observer: trace, select: trace.method(:trace?)).run
        trace.finish
        return EXIT_CODES[:ok] unless result.status == :aborted

        logger.error("#{result.error.class}: #{result.error.message}")
        EXIT_CODES[:aborted]
      end

      def traced_pipeline(pipeline)
        null = SinkAdapter.new(Metacrunch::Trace::NullSink.new)
        RunOptions.new(input: @input).apply_input(pipeline, stdin: @stdin).with(
          sink: null, rejects: null, errors: null, on_error: :skip, max_errors: nil, limit:
        )
      end

      def limit
        @limit || (@positions || @ids)&.size || DEFAULT_LIMIT
      end

      def position(text)
        value = Integer(text, 10, exception: false)
        raise UsageError, "--position needs positive numbers, got #{text}" unless value&.positive?

        value
      end

      def color?
        @stdout.tty? && @env.fetch("NO_COLOR", "").empty?
      end

      def width
        return DEFAULT_WIDTH unless @stdout.tty? && @stdout.respond_to?(:winsize)

        @stdout.winsize[1]
      rescue SystemCallError
        DEFAULT_WIDTH
      end

    end
  end
end
```

`lib/metacrunch/cli.rb`: add `require_relative "trace"` after `require_relative "progress"`, `require_relative "cli/trace"` after `require_relative "cli/check"`, and change `COMMANDS` to `{"run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand}.freeze`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/trace_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli/trace.rb lib/metacrunch/cli.rb test/cli/trace_test.rb
git commit -m "Add the trace command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 15: `new`

**Files:**
- Create: `lib/metacrunch/cli/new.rb`, `test/cli/new_test.rb`
- Modify: `lib/metacrunch/cli.rb`

**Interfaces:**
- Consumes: `Command` (Task 8).
- Produces: `Cli::NewCommand`; `Cli::COMMANDS` gains `"new"` (last).

- [ ] **Step 1: Write the failing tests**

`test/cli/new_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class NewTest < Minitest::Test

  include CliHelper

  LIB = File.expand_path("../../lib", __dir__)

  def test_creates_an_executable_filter_job_that_runs
    in_tmpdir do
      code, stdout, = cli("new", "jobs/mab2json")
      run_code, run_stdout, = cli("run", "jobs/mab2json.rb", stdin: "{\"id\":1}\n{\"x\":2}\n")

      assert_equal [0, "created jobs/mab2json.rb\n"], [code, stdout]
      assert File.executable?("jobs/mab2json.rb")
      assert_equal [0, "{\"id\":1}\n"], [run_code, run_stdout]
    end
  end

  def test_test_option_writes_a_passing_test
    in_tmpdir do |dir|
      cli("new", "--test", "jobs/pass.rb")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", LIB, "test/pass_test.rb", chdir: dir)

      assert_predicate status, :success?, stderr
    end
  end

  def test_refuses_to_overwrite_without_force
    in_tmpdir do
      cli("new", "job.rb")
      code, _stdout, stderr = cli("new", "job.rb")

      assert_equal 2, code
      assert_match(/job\.rb already exists; use --force to overwrite/, stderr)
      assert_equal 0, cli("new", "--force", "job.rb").first
    end
  end

  def test_class_names_of_tests_start_with_a_letter
    in_tmpdir do
      cli("new", "--test", "2go")

      assert_match(/^class Job2goTest < Minitest::Test$/, File.read("test/2go_test.rb"))
    end
  end

  def test_a_path_is_required
    assert_match(/Error: no path given/, cli("new")[2])
  end

  private

  def in_tmpdir(&)
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
  end

end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/new_test.rb`
Expected: failures (`unknown command or job file: new`).

- [ ] **Step 3: Implement**

`lib/metacrunch/cli/new.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

module Metacrunch
  class Cli
    # metacrunch new: creates a filter job (JSON Lines from stdin to stdout)
    # that runs right away, and with --test a Minitest test for it.
    class NewCommand < Command

      NAME = "new"
      SUMMARY = "Create a job file"
      USAGE = "new [--test] [--force] PATH"

      def initialize(streams)
        super
        @test = false
        @force = false
      end

      private

      def define_options(parser)
        parser.on("--test", "Also create test/NAME_test.rb") { @test = true }
        parser.on("--force", "Overwrite existing files") { @force = true }
      end

      def execute(argv)
        path = argv.shift
        raise UsageError, "no path given" unless path
        raise UsageError, "unexpected arguments: #{argv.join(" ")}" if argv.any?

        path = "#{path}.rb" unless path.end_with?(".rb")
        write(files(path, File.basename(path, ".rb")))
        File.chmod(0o755, path)
        EXIT_CODES[:ok]
      end

      # {path => content} of the files to create. Raises UsageError if one
      # exists and --force is not given.
      def files(path, name)
        templates = {path => job_template(name, path)}
        templates[File.join("test", "#{name}_test.rb")] = test_template(name, path) if @test
        existing = templates.keys.select { File.exist?(it) }
        if existing.any? && !@force
          raise UsageError, "#{existing.join(", ")} already exists; use --force to overwrite"
        end

        templates
      end

      def write(files)
        files.each do |file, content|
          FileUtils.mkdir_p(File.dirname(file))
          File.write(file, content)
          @stdout.puts("created #{file}")
        end
      end

      def job_template(name, path)
        <<~RUBY
          #!/usr/bin/env metacrunch
          # frozen_string_literal: true

          # Reads JSON Lines from stdin, writes JSON Lines to stdout:
          #   metacrunch run #{path} < in.jsonl > out.jsonl
          # Declare a source or sink to read or write elsewhere.
          Metacrunch.job #{name.inspect} do
            params do
              # param :index, String, required: true, desc: "Elasticsearch index"
            end

            # source MySource.new(params.files), id: ->(record) { record["id"] }

            reject("No id") { it["id"].nil? }
            map do |record, ctx|
              ctx.mark("No title") unless record.key?("title")
              record
            end

            # sink MySink.new, batch: 1000
          end
        RUBY
      end

      def test_template(name, path)
        job = Pathname(path).expand_path.relative_path_from(Pathname("test").expand_path)
        <<~RUBY
          # frozen_string_literal: true

          require "minitest/autorun"
          require "metacrunch"
          require "metacrunch/testing"

          class #{class_name(name)}Test < Minitest::Test

            JOB = File.expand_path(#{job.to_s.inspect}, __dir__)

            def test_keeps_records_with_an_id
              result = Metacrunch::Testing.run(Metacrunch.load_job(JOB), source: [{"id" => 1}, {"title" => "x"}])

              assert_equal [{"id" => 1}], result.records
            end

          end
        RUBY
      end

      def class_name(name)
        camel = name.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
        camel.match?(/\A[A-Z]/) ? camel : "Job#{camel}"
      end

    end
  end
end
```

`lib/metacrunch/cli.rb`: add `require_relative "cli/new"` after `require_relative "cli/trace"`, and change `COMMANDS` to `{"run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand}.freeze`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/new_test.rb && bundle exec rake`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli/new.rb lib/metacrunch/cli.rb test/cli/new_test.rb
git commit -m "Add the new command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```

---

### Task 16: End-to-end tests, Readme, changelog, measurements

**Files:**
- Create: `test/fixtures/jobs/emit.rb`, `test/fixtures/jobs/tag.rb`, `test/fixtures/jobs/endless.rb`
- Modify: `test/cli/exe_test.rb`, `Readme.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-10-metacrunch-ng-cli-pipes-design.md` (§13, status)

**Interfaces:**
- Consumes: everything above through `exe/metacrunch`.

- [ ] **Step 1: Write the end-to-end tests**

`test/fixtures/jobs/emit.rb`:

```ruby
# frozen_string_literal: true

# Emits five records as JSON Lines on stdout.
Metacrunch.job do
  source((1..5).map { {"n" => it} })
end
```

`test/fixtures/jobs/tag.rb`:

```ruby
# frozen_string_literal: true

# Filter job: tags every record.
Metacrunch.job do
  map { it.merge("tagged" => true) }
end
```

`test/fixtures/jobs/endless.rb`:

```ruby
# frozen_string_literal: true

# Emits records without end and rejects the even ones.
Metacrunch.job do
  source((1..).lazy.map { {"n" => it} })
  reject("Even") { it["n"].even? }
end
```

In `test/cli/exe_test.rb`, add `require "json"`, `require "pty"`, `require "shellwords"`, `require "tmpdir"` at the top, these constants below `NUMBERS`:

```ruby
  JOBS = File.join(ROOT, "test", "fixtures", "jobs")
  LIB = File.join(ROOT, "lib")
  EXE = File.join(ROOT, "exe", "metacrunch")
```

the tests:

```ruby
  def test_jobs_chain_through_pipes
    filter = Shellwords.join([RbConfig.ruby, "-rjson", "-ne", "puts $_ if JSON.parse($_)[\"n\"].odd?"])
    pipeline = [Shellwords.join(command("run", fixture("emit.rb"))), filter,
                Shellwords.join(command("run", fixture("tag.rb")))].join(" | ")
    stdout, stderr, status = Open3.capture3("sh", "-c", pipeline)
    records = stdout.lines.map { JSON.parse(it) }

    assert_predicate status, :success?, stderr
    assert_equal([1, 3, 5], records.map { it["n"] })
    assert(records.all? { it["tagged"] })
  end

  def test_a_closed_pipe_ends_the_job_by_sigpipe_and_flushes_other_sinks
    Dir.mktmpdir do |dir|
      rejects = File.join(dir, "rejects.jsonl")
      errors = File.join(dir, "stderr")
      reader, writer = IO.pipe
      pid = Process.spawn(*command("run", "--rejects", rejects, fixture("endless.rb")), out: writer, err: errors)
      writer.close
      first = reader.gets
      reader.close
      _pid, status = Process.wait2(pid)
      reasons = File.readlines(rejects).map { JSON.parse(it).dig("rejection", "reason") }

      assert_equal ["{\"n\":1}\n", Signal.list.fetch("PIPE")], [first, status.termsig]
      assert_empty File.read(errors)
      assert_equal ["Even"], reasons.uniq
    end
  end

  def test_jobs_created_by_new_run_through_their_shebang_line
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "metacrunch"), "#!/bin/sh\nexec #{Shellwords.join([RbConfig.ruby, "-I", LIB, EXE])} \"$@\"\n")
      File.chmod(0o755, File.join(bin, "metacrunch"))
      env = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}"}
      Open3.capture3(env, "metacrunch", "new", "jobs/pass.rb", chdir: dir)
      stdout, stderr, status = Open3.capture3(env, "./jobs/pass.rb", stdin_data: "{\"id\":1}\n", chdir: dir)

      assert_equal [0, "{\"id\":1}\n"], [status.exitstatus, stdout], stderr
    end
  end

  def test_shows_progress_on_a_terminal
    output = +""
    PTY.spawn(*command("run", fixture("slow.rb"))) do |reader, _writer, pid|
      begin
        reader.each_line { output << it }
      rescue Errno::EIO
        nil # Linux: the child closed the terminal
      end
      Process.wait(pid)
    end

    assert_includes output, "\e[2K"
    assert_match(/read \d+/, output)
  end
```

and private helpers:

```ruby
  def command(*)
    [RbConfig.ruby, "-I", LIB, EXE, *]
  end

  def fixture(name) = File.join(JOBS, name)
```

Split lines over 120 characters (the shebang wrapper `File.write`) into a local variable.

- [ ] **Step 2: Run the end-to-end tests**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/exe_test.rb`
Expected: PASS. Ruby 4.0.7 ends quietly by SIGPIPE (checked while designing). If `test_a_closed_pipe_...` shows a message on stderr, use superpowers:systematic-debugging; do not loosen the assertion.

- [ ] **Step 3: Measure**

Use the session scratchpad directory as `$SCRATCH`. Engine cost, at the current HEAD and at the spec commit `76f0b75` (before sub-project 2 code):

```bash
cat > "$SCRATCH/bench_engine.rb" <<'EOF'
# frozen_string_literal: true

require "metacrunch"

records = 1_000_000
steps = 10
job = Metacrunch.job do
  source(1..records)
  steps.times { map { it } }
end
logger = Logger.new(nil)
job.run([], logger:)
GC.start
allocated = GC.stat(:total_allocated_objects)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
job.run([], logger:)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
allocations = GC.stat(:total_allocated_objects) - allocated
puts format("%<ns>.1f ns per step and record, %<allocs>.1f allocations per record",
            ns: elapsed * 1e9 / (records * steps), allocs: allocations.fdiv(records))
EOF
git worktree add "$SCRATCH/baseline" 76f0b75
ruby -I "$SCRATCH/baseline/lib" "$SCRATCH/bench_engine.rb"
ruby -I lib "$SCRATCH/bench_engine.rb"
git worktree remove "$SCRATCH/baseline"
```

Expected: HEAD within about 10 % of the baseline, same allocations per record. Run each twice and keep the faster run.

JSON Lines throughput:

```bash
ruby -e 'File.open(ARGV[0], "w") { |f| 1_000_000.times { |i| f.puts(%({"id":#{i},"title":"Title #{i}","year":#{1900 + i % 120},"isbns":["978-#{i}"]})) } }' "$SCRATCH/1m.jsonl"
gzip -k "$SCRATCH/1m.jsonl"
printf '# frozen_string_literal: true\n\nMetacrunch.job {}\n' > "$SCRATCH/pass.rb"
ruby -I lib exe/metacrunch run "$SCRATCH/pass.rb" < "$SCRATCH/1m.jsonl" > /dev/null
ruby -I lib exe/metacrunch run -i "$SCRATCH/1m.jsonl.gz" "$SCRATCH/pass.rb" > /dev/null
```

Read the records/s from the summary line on stderr.

- [ ] **Step 4: Update the spec**

In `docs/superpowers/specs/2026-10-10-metacrunch-ng-cli-pipes-design.md`, replace the text of §13 below the heading with the results, e.g.:

```markdown
Measured on Ruby 4.0.7 +YJIT, arm64 macOS:

| Measurement | Sub-project 1 | Sub-project 2 |
|---|---|---|
| Engine, 10 `map` steps, no observer/monitor | X ns per step and record, Y allocations per record | X ns, Y allocations |
| Pass-through job, 1 M JSON Lines from stdin to stdout | – | N records/s |
| Same, `-i 1m.jsonl.gz` | – | N records/s |
```

with the measured numbers filled in, and set the status line to `- Status: approved; implemented`.

- [ ] **Step 5: Update the Readme**

In `Readme.md`:

Replace the section `## A first job` up to (not including) `## Records` with:

````markdown
## A first job

A job file is plain Ruby:

```ruby
# jobs/numbers.rb
Metacrunch.job "numbers" do
  params do
    param :factor, Integer, default: 2, desc: "Multiplier"
    args :numbers, min: 1, desc: "Numbers to process"
  end

  source params.numbers.map { Integer(it) }

  reject("Negative") { it.negative? }
  map { it * params.factor }
end
```

```
$ metacrunch run jobs/numbers.rb --factor 3 -- 1 2 -5
3
6
```

A job without a sink writes its records to stdout as JSON Lines. Logs and the run summary go to stderr.

````

In `## Sources`, append:

````markdown
`Metacrunch::JsonLines::Reader.new(path)` reads JSON Lines (`-` for stdin, `.gz` files are decompressed). A source
can yield `Metacrunch::InvalidRecord.new(raw:, error:)` for a record it cannot read; the reader does so for lines
that are not valid JSON. Invalid records fail like a step (the pseudo-step `source`) under the job's error policy.
````

In `## Sinks`, append:

````markdown
`Metacrunch::JsonLines::Writer.new(path)` writes JSON Lines (`-` for stdout, `.gz` files are compressed) and refuses
values that are not JSON types. `Metacrunch::JsonLines::ContextWriter` writes every record with its context (id,
position, marks, rejection, failure), which suits the `rejects` and `errors` roles.
````

Replace the section `## Running jobs` up to (not including) `## Testing jobs` with:

````markdown
## Running jobs

```
$ metacrunch run [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
$ metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]      # short for run
$ metacrunch run jobs/mab2es.rb --help                # the job's parameters
```

Options of `metacrunch` go before the job file; everything after it belongs to the job. Use `--` before job
arguments that start with `-`. The CLI does not change the working directory: relative paths are relative to where
you start it.

| Option | |
|---|---|
| `-j`, `--job NAME` | Select a job in a file that defines several |
| `-i`, `--input PATH` | Read JSON Lines from PATH (`-` for stdin) instead of the job's source |
| `-o`, `--output PATH` | Write JSON Lines to PATH (`-` for stdout) instead of the job's sink |
| `--rejects PATH`, `--errors PATH` | Write rejected or failed records with their context; both may name the same file |
| `-n`, `--limit N` | Process only the first N source records |
| `--on-error abort\|skip`, `--max-errors N` | Override the job's error policy |
| `--stats PATH` | Write status and stats as JSON at the end (`-` for stdout) |
| `--[no-]progress` | Progress on stderr; shown by default if stderr is a terminal |
| `-q`, `-v` | Log warnings only, or debug messages too |

A job file that starts with `#!/usr/bin/env metacrunch` and is executable runs as `./jobs/mab2es.rb ...`.

### Pipes

A job without `source` reads JSON Lines from stdin, a job without `sink` writes JSON Lines to stdout. Such jobs chain
with each other and with other tools, and every stage runs in its own process:

```
$ metacrunch run mab2json.rb dumps/*.xml | jq -c 'select(.year > 2000)' | metacrunch run json2es.rb --index test
```

`source id: ->(record) { record["_id"] }` gives a job that reads stdin an id extractor. Only records survive a pipe,
not their context. When the reader of the pipe stops (`| head`), the job flushes and closes its other sinks and ends
quietly by SIGPIPE.

### Debugging and checking jobs

```
$ metacrunch trace -n 5 jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch trace --position 4711 jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch check jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch new --test jobs/mab2json.rb
```

`trace` shows what every step does to the first records (or to the records at `--position`, or with `--id`): the
changed keys of Hash records, marks, rejections and failures, and the records a `flat_map` emits. It writes nothing:
all sinks are replaced. `--full` shows whole records.

`check` loads the job, binds its parameters and builds it, without opening, reading or running anything. `new`
creates a filter job that runs right away, and with `--test` a Minitest test for it.

| Exit code | Meaning |
|---|---|
| 0 | ok |
| 1 | aborted |
| 2 | usage error (command, options, job file, parameters; `check` found the job invalid) |
| 3 | finished, but records failed (`on_error :skip`) |
| 130 | interrupted by Ctrl-C (SIGINT) |
| 141 | stdout was closed by the reader (SIGPIPE) |
| 143 | terminated (SIGTERM) |

After Ctrl-C or SIGTERM the job writes what its sinks have buffered, closes them, and `metacrunch` ends by the
signal, so shells and `xargs` see the interruption. Data already written to stdout is kept.

````

- [ ] **Step 6: Update the changelog**

In `CHANGELOG.md`, under `### Breaking changes`, replace the line `- The CLI no longer changes into the job's directory and returns defined exit codes.` with:

```markdown
- The CLI has commands (`run`, `check`, `trace`, `new`); `metacrunch JOB_FILE` still runs a job. Options of
  `metacrunch` go before the job file. It no longer changes into the job's directory and returns defined exit codes.
```

and append to `### Added`:

```markdown
- Unix pipes: a job without source reads JSON Lines from stdin, a job without sink writes them to stdout.
- `Metacrunch::JsonLines` reader and writers (also gzip); `Metacrunch::InvalidRecord` for records a source cannot read.
- `run` options to replace the source and sinks (`-i`, `-o`, `--rejects`, `--errors`), `--limit`, `--on-error`,
  `--max-errors`, `--stats` and a progress display.
- `metacrunch trace` shows what each step does to a record; `metacrunch check` validates a job; `metacrunch new`
  creates one.
- A closed stdout (`| head`) ends a job quietly by SIGPIPE (exit status 141).
```

- [ ] **Step 7: Run everything**

Run: `bundle exec rake`
Expected: all tests pass, coverage at least 95 % lines and 90 % branches, RuboCop clean.

- [ ] **Step 8: Commit**

```bash
git add test/cli/exe_test.rb test/fixtures/jobs/emit.rb test/fixtures/jobs/tag.rb test/fixtures/jobs/endless.rb \
  Readme.md CHANGELOG.md docs/superpowers/specs/2026-10-10-metacrunch-ng-cli-pipes-design.md
git commit -m "Test pipes end to end, document the CLI and record measurements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF"
```
