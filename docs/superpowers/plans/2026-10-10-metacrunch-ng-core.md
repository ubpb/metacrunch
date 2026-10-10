# metacrunch-ng core (sub-project 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the metacrunch 4.x implementation with the redesigned core: explicit step kinds, per-record context, sink-side batching, error policy, stats, recipe/pipeline separation, job parameters, a testing helper and a minimal CLI.

**Architecture:** A job is a recipe (a DSL block). `Builder` evaluates it with bound `Params` into an immutable `Pipeline`. `Engine` folds the steps into a push chain, feeds every source record (with a `Context`) through it into `SinkAdapter`s, applies the error policy and returns a `Result` with `Stats`. `Job`/`Loader` load job files, `Testing` runs jobs in memory, `Cli` runs them from the shell.

**Tech Stack:** Ruby 4.0, standard library (`optparse`, `json`), `logger` gem, Minitest, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-10-metacrunch-ng-core-design.md`

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version `5.0.0.pre`.
- Runtime dependency: `logger` only. No ActiveSupport, no colorize, no Zeitwerk.
- Files are loaded with `require_relative`.
- Every Ruby file starts with `# frozen_string_literal: true` (also `Gemfile`, gemspec, `Rakefile`, `exe/*`, test fixtures).
- The library never writes to `$stdout` and never calls `exit`. Logs go to the logger (default: `$stderr`). Only `Cli` prints help and version on stdout.
- Lint: `.rubocop.yml` inherits `rubocop-ubpb: ruby.yml` (gem from `github: "ubpb/rubocop-ubpb", branch: "v2"`) and enables `Style/FrozenStringLiteralComment`. `bundle exec rubocop` must be clean at the end of every task. `bundle exec rubocop -a` may be used for layout fixes.
- Style that ruby.yml enforces: double quotes (also inside interpolation), `{a: 1}` without spaces inside braces, `[:a, :b]`/`["a", "b"]` instead of `%i[]`/`%w[]`, blank lines at the start and end of class/module bodies except for pure namespaces, max line length 120, at most 3 assertions per Minitest test, a blank line before the first assertion.
- Naming note: the spec's per-step counters "in"/"out" are named `input`/`output` (`in` is a Ruby keyword).
- Tests: Minitest. Single file: `bundle exec ruby -w -Ilib -Itest <file>`. Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake`.
- Every commit message ends with these two lines:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
  ```

## Review Focus

Inputs and conditions the spec implies but does not spell out, most likely to bite a user first. Each has a test in the task named in brackets.

1. **Symbol procs as steps** (`filter(&:odd?)`, `map(&:to_s)`): they have an unnamed splat parameter and must get only the record, not the context. [Task 4, Task 8]
2. **Sources whose `each` only yields** (a plain `def each; yield ...; end` without returning an Enumerator): the engine must call `each` with a block. [Task 8]
3. **`flat_map` returning an `Enumerator`** (lazy or `Enumerator.new`): must be accepted and expanded. [Task 8]
4. **Ctrl-C while the source is reading** (Interrupt outside any step): sinks must still be closed, `after` hooks skipped. [Task 9]
5. **Relative paths and the working directory**: a job started from another directory with relative parameter paths must resolve them against the user's cwd (no `chdir`). [Task 13]

---

## File Structure

```
metacrunch.gemspec                rewritten
Gemfile, Gemfile.lock             rewritten / committed
Rakefile, .rubocop.yml            rewritten / new
.ruby-version, .gitignore         new / rewritten
.github/workflows/ci.yml          new
.github/dependabot.yml            new
bin/console                       rewritten
exe/metacrunch                    rewritten (Task 12)
lib/metacrunch.rb                 entry: requires, Metacrunch.logger/.job/.load_job
lib/metacrunch/version.rb
lib/metacrunch/errors.rb          Error, ParamError, ContractError, JobLoadError, StepError
lib/metacrunch/record_logger.rb   logger wrapper with record prefix
lib/metacrunch/context.rb         Context, Rejection, Mark, Failure
lib/metacrunch/stats.rb           Stats, StepStats (immutable)
lib/metacrunch/stats_collector.rb mutable counters → Stats
lib/metacrunch/result.rb          Result
lib/metacrunch/callable.rb        callable checks, context arity detection
lib/metacrunch/step.rb            Step, STEP_KINDS
lib/metacrunch/sink_adapter.rb    batching, context passing, open/close
lib/metacrunch/params.rb          parameter schema and binding
lib/metacrunch/pipeline.rb        Pipeline (immutable)
lib/metacrunch/builder.rb         DSL → Pipeline
lib/metacrunch/executor/inline.rb executor seam
lib/metacrunch/engine.rb          OpenContext, Engine
lib/metacrunch/job.rb             Job (recipe)
lib/metacrunch/loader.rb          job file loading
lib/metacrunch/testing.rb         Testing.run, MemorySink, Testing::Result
lib/metacrunch/cli.rb             minimal CLI
test/test_helper.rb
test/support/pipeline_helper.rb   build_pipeline / run_pipeline
test/support/collecting_sink.rb   CollectingSink
test/unit/*_test.rb, test/cli/*_test.rb, test/integration/*_test.rb
test/fixtures/jobs/*.rb, test/fixtures/catalog.json
Readme.md, CHANGELOG.md           rewritten / new (Task 13)
```

Removed in Task 1: `lib/metacrunch/cli.rb` (old), `lib/metacrunch/job.rb` (old), `lib/metacrunch/job/`, `lib/metacrunch/test_utils.rb`, `lib/metacrunch/test_utils/`, `spec/`, `.rspec`, `.circleci/`, `exe/metacrunch` (old).

---

### Task 1: Project scaffold

Replace the 4.x code, test and CI setup with the new gem skeleton. Deliverable: `bundle exec rake` runs one passing test and a clean RuboCop.

**Files:**
- Delete: `lib/metacrunch/cli.rb`, `lib/metacrunch/job.rb`, `lib/metacrunch/job/`, `lib/metacrunch/test_utils.rb`, `lib/metacrunch/test_utils/`, `spec/`, `.rspec`, `.circleci/`, `exe/metacrunch`
- Rewrite: `metacrunch.gemspec`, `Gemfile`, `Rakefile`, `.gitignore`, `bin/console`, `lib/metacrunch.rb`, `lib/metacrunch/version.rb`
- Create: `lib/metacrunch/errors.rb`, `.rubocop.yml`, `.ruby-version`, `.github/workflows/ci.yml`, `.github/dependabot.yml`, `test/test_helper.rb`, `test/unit/metacrunch_test.rb`, `Gemfile.lock`

**Interfaces:**
- Produces: `Metacrunch::VERSION` (`"5.0.0.pre"`); `Metacrunch.logger` (default `Logger` on `$stderr`), `Metacrunch.logger=`, `Metacrunch.build_logger(io) → Logger`; error classes `Metacrunch::Error < StandardError`, `ParamError`, `ContractError`, `JobLoadError`, `StepError` (`#step`, `#record_id`, `#position`; `new(step:, record_id:, position:, error:)`).

- [ ] **Step 0: Check the rubocop-ubpb branch is on GitHub**

Run: `git ls-remote https://github.com/ubpb/rubocop-ubpb refs/heads/v2`
Expected: one line with a SHA. If the output is empty, stop and ask the user to push branch `v2` of rubocop-ubpb.

- [ ] **Step 1: Remove the 4.x implementation and setup**

```bash
git rm -r -q lib/metacrunch/cli.rb lib/metacrunch/job.rb lib/metacrunch/job lib/metacrunch/test_utils.rb lib/metacrunch/test_utils spec .rspec .circleci exe/metacrunch
```

- [ ] **Step 2: Write the gem setup files**

`metacrunch.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/metacrunch/version"

Gem::Specification.new do |spec|
  spec.name     = "metacrunch"
  spec.version  = Metacrunch::VERSION
  spec.authors  = ["René Sprotte", "Michael Sievers", "Marcel Otto"]
  spec.summary  = "Data processing and ETL toolkit for Ruby"
  spec.homepage = "https://github.com/ubpb/metacrunch"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "exe/*", "CHANGELOG.md", "License.txt", "Readme.md"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |path| File.basename(path) }

  spec.add_dependency "logger", ">= 1.6"
end
```

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "minitest", ">= 5.25"
  gem "rake", ">= 13.0"
  gem "rubocop-ubpb", github: "ubpb/rubocop-ubpb", branch: "v2", require: false
  gem "simplecov", ">= 0.22", require: false
end
```

`Rakefile`:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

# Coverage thresholds apply to full runs only (see test/test_helper.rb).
ENV["COVERAGE"] = "1" unless ENV.key?("COVERAGE")

Minitest::TestTask.create do |t|
  t.test_globs = ["test/**/*_test.rb"]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
```

`.rubocop.yml`:

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

inherit_mode:
  merge:
    - Exclude

Style/FrozenStringLiteralComment:
  Enabled: true
```

`.ruby-version`:

```
4.0.7
```

`.gitignore`:

```
*.gem
.DS_Store
/.bundle/
/coverage/
/pkg/
/tmp/
```

`bin/console`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "metacrunch"
require "irb"

IRB.start(__FILE__)
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [master, metacrunch-ng]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    name: Test (Ruby ${{ matrix.ruby }}, ${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    continue-on-error: ${{ matrix.ruby == 'head' }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
        ruby: ["4.0", head]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake test

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: "4.0"
          bundler-cache: true
      - run: bundle exec rubocop
```

`.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: bundler
    directory: "/"
    schedule:
      interval: weekly
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
```

- [ ] **Step 3: Install and lock**

Run:

```bash
bundle install
bundle lock --add-platform x86_64-linux
```

Expected: `Bundle complete!`; `Gemfile.lock` lists `arm64-darwin` and `x86_64-linux` under `PLATFORMS`.

- [ ] **Step 4: Write the test helper and the failing test**

`test/test_helper.rb`:

```ruby
# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    add_filter "/test/"
  end
end

require "minitest/autorun"
require "stringio"
require "metacrunch"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
```

`test/unit/metacrunch_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class MetacrunchTest < Minitest::Test

  def setup
    Metacrunch.logger = nil
  end

  def teardown
    Metacrunch.logger = nil
  end

  def test_default_logger_writes_to_stderr_not_stdout
    stdout, stderr = capture_io { Metacrunch.logger.info("hello") }

    assert_empty stdout
    assert_match(/INFO  hello$/, stderr)
  end

end
```

- [ ] **Step 5: Run the test to see it fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/metacrunch_test.rb`
Expected: error `NoMethodError: undefined method 'logger=' for module Metacrunch` (the old entry file requires removed files, so it may fail earlier with `LoadError`; both mean the feature is missing).

- [ ] **Step 6: Write the entry file, version and errors**

`lib/metacrunch/version.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  VERSION = "5.0.0.pre"
end
```

`lib/metacrunch/errors.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  class Error < StandardError; end

  # Invalid or missing job parameters.
  class ParamError < Error; end

  # A step or sink broke its contract, e.g. a map step returned nil.
  class ContractError < Error; end

  # A job file could not be loaded or does not define the requested job.
  class JobLoadError < Error; end

  # A step raised an error for a record. The original error is the cause.
  class StepError < Error

    attr_reader :step, :record_id, :position

    def initialize(step:, record_id:, position:, error:)
      @step = step
      @record_id = record_id
      @position = position
      record = record_id.nil? ? "position #{position}" : "position #{position} (id #{record_id})"
      super("step #{step} failed at #{record}: #{error.class}: #{error.message}")
    end

  end

end
```

`lib/metacrunch.rb`:

```ruby
# frozen_string_literal: true

require "logger"

require_relative "metacrunch/version"
require_relative "metacrunch/errors"

module Metacrunch

  LOG_FORMATTER = proc do |severity, time, _progname, message|
    "#{time.strftime("%H:%M:%S")} #{severity.ljust(5)} #{message}\n"
  end

  class << self

    attr_writer :logger

    # The default logger writes to stderr. Stdout is reserved for data.
    def logger
      @logger ||= build_logger($stderr)
    end

    def build_logger(io)
      Logger.new(io, level: Logger::INFO, formatter: LOG_FORMATTER)
    end

  end

end
```

- [ ] **Step 7: Run the test to see it pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/metacrunch_test.rb`
Expected: `1 runs, 2 assertions, 0 failures, 0 errors`

- [ ] **Step 8: Run the full suite and lint**

Run: `bundle exec rake`
Expected: tests pass, coverage above thresholds, `no offenses detected`. Fix any RuboCop offense (use `bundle exec rubocop -a` for layout).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Replace 4.x setup with the metacrunch-ng gem skeleton

Remove the 4.x implementation, RSpec suite and CircleCI. Add the new
gemspec (Ruby 4.0, logger only), Minitest with SimpleCov, RuboCop via
rubocop-ubpb ruby.yml, GitHub Actions, Dependabot, the error classes
and Metacrunch.logger (stderr).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 2: Per-record context

**Files:**
- Create: `lib/metacrunch/record_logger.rb`, `lib/metacrunch/context.rb`, `test/unit/context_test.rb`
- Modify: `lib/metacrunch.rb` (add requires after `require_relative "metacrunch/errors"`)

**Interfaces:**
- Consumes: `Metacrunch::ContractError`, `Metacrunch.build_logger(io)`.
- Produces:
  - `Metacrunch::Rejection = Data.define(:reason, :value, :step)`, `Metacrunch::Mark = Data.define(:reason, :value, :step)`, `Metacrunch::Failure = Data.define(:error, :step)`.
  - `Metacrunch::Context.new(id:, position:, logger:, on_mark: nil, marks: [], store: {})` with `#id`, `#position`, `#step`/`#step=`, `#failure`/`#failure=`, `#marks`, `#store`, `#rejection`, `#reject!(reason, value: nil) → nil`, `#rejected? → Boolean`, `#mark(reason, value: nil) → nil` (calls `on_mark.call(reason)`), `#logger → RecordLogger`, `#copy → Context`, `#seal! → self`.
  - `Metacrunch::RecordLogger.new(logger, label)` with `debug/info/warn/error/fatal(message)`.

- [ ] **Step 1: Write the failing tests**

`test/unit/context_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test

  def test_reject_records_reason_value_and_step
    ctx = build_context
    ctx.step = "reject#2"
    ctx.reject!("Patent", value: "patent")

    assert_predicate ctx, :rejected?
    assert_equal Metacrunch::Rejection.new(reason: "Patent", value: "patent", step: "reject#2"), ctx.rejection
  end

  def test_mark_keeps_the_record_and_reports_the_reason
    reported = []
    ctx = build_context(on_mark: ->(reason) { reported << reason })
    ctx.step = "map#1"
    ctx.mark("No title")

    refute_predicate ctx, :rejected?
    assert_equal [Metacrunch::Mark.new(reason: "No title", value: nil, step: "map#1")], ctx.marks
    assert_equal ["No title"], reported
  end

  def test_copy_keeps_identity_but_not_marks_or_store
    parent = build_context
    parent.step = "flat_map#3"
    parent.mark("parent")
    parent.store[:cache] = 1
    child = parent.copy
    child.mark("child")
    child.store[:cache] = 2

    assert_equal ["rec1", 7, "flat_map#3"], [child.id, child.position, child.step]
    assert_equal [["parent"], 1], [parent.marks.map(&:reason), parent.store[:cache]]
    assert_equal ["parent", "child"], child.marks.map(&:reason)
  end

  def test_sealed_context_rejects_changes
    ctx = build_context.seal!

    assert_raises(Metacrunch::ContractError) { ctx.reject!("x") }
    assert_raises(Metacrunch::ContractError) { ctx.mark("x") }
  end

  def test_logger_prefixes_messages_with_id_or_position
    io = StringIO.new
    logger = Metacrunch.build_logger(io)
    build_context(id: "rec1", logger:).logger.warn("missing title")
    build_context(id: nil, logger:).logger.warn("no id")

    assert_match(/WARN  \[rec1\] missing title/, io.string)
    assert_match(/WARN  \[#7\] no id/, io.string)
  end

  private

  def build_context(id: "rec1", logger: Logger.new(nil), on_mark: nil)
    Metacrunch::Context.new(id:, position: 7, logger:, on_mark:)
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/context_test.rb`
Expected: errors `NameError: uninitialized constant Metacrunch::Context`.

- [ ] **Step 3: Implement**

`lib/metacrunch/record_logger.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Logger for one record: prefixes every message with the record's id or
  # position, so log lines can be traced back to the input.
  class RecordLogger

    LEVELS = [:debug, :info, :warn, :error, :fatal].freeze

    def initialize(logger, label)
      @logger = logger
      @label = label
    end

    LEVELS.each do |level|
      define_method(level) do |message|
        @logger.public_send(level) { "[#{@label}] #{message}" }
      end
    end

  end
end
```

`lib/metacrunch/context.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  Rejection = Data.define(:reason, :value, :step)
  Mark = Data.define(:reason, :value, :step)
  Failure = Data.define(:error, :step)

  # Per-record context. The engine creates one for every record the source
  # emits and passes it to steps and sinks that accept a second argument.
  class Context

    attr_reader :id, :position, :marks, :store, :rejection
    attr_accessor :step, :failure

    # on_mark is called with the reason of every mark, so marks are counted
    # when they happen (once, even if a flat_map copies the context later).
    def initialize(id:, position:, logger:, on_mark: nil, marks: [], store: {})
      @id = id
      @position = position
      @base_logger = logger
      @on_mark = on_mark
      @marks = marks
      @store = store
      @rejection = nil
      @failure = nil
      @step = nil
      @sealed = false
    end

    # Stops processing of this record. The engine sends it to the rejects
    # sink and ignores the return value of the current step.
    def reject!(reason, value: nil)
      ensure_writable!
      @rejection = Rejection.new(reason:, value:, step:)
      nil
    end

    def rejected?
      !@rejection.nil?
    end

    # Records a non-fatal note. The record continues through the pipeline.
    def mark(reason, value: nil)
      ensure_writable!
      @marks << Mark.new(reason:, value:, step:)
      @on_mark&.call(reason)
      nil
    end

    def logger
      @logger ||= RecordLogger.new(@base_logger, id.nil? ? "##{position}" : id)
    end

    # A copy for one child of a flat_map step: same id and position, own
    # marks and store.
    def copy
      child = self.class.new(
        id:, position:, logger: @base_logger, on_mark: @on_mark, marks: marks.dup, store: store.dup
      )
      child.step = step
      child
    end

    # Sinks get sealed contexts: they may read them, but not reject or mark.
    def seal!
      @sealed = true
      self
    end

    private

    def ensure_writable!
      return unless @sealed

      raise ContractError, "the context is read-only in sinks; reject or mark records in a step"
    end

  end

end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/errors"`:

```ruby
require_relative "metacrunch/record_logger"
require_relative "metacrunch/context"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/context_test.rb`
Expected: `5 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add the per-record context

Context carries id, position and current step, supports reject!, mark,
a per-record store and a prefixed logger. flat_map children get copies;
sinks get sealed contexts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 3: Stats and result

**Files:**
- Create: `lib/metacrunch/stats.rb`, `lib/metacrunch/stats_collector.rb`, `lib/metacrunch/result.rb`, `test/unit/stats_test.rb`, `test/unit/stats_collector_test.rb`, `test/unit/result_test.rb`
- Modify: `lib/metacrunch.rb` (add requires after `require_relative "metacrunch/context"`)

**Interfaces:**
- Produces:
  - `Metacrunch::StepStats = Data.define(:input, :output, :filtered, :rejected, :failed, :time)` with `#merge(other)`; `time` is `nil` unless profiled.
  - `Metacrunch::Stats = Data.define(:read, :written, :filtered, :rejected, :marked, :failed, :steps, :duration)`; `rejected`/`marked`/`failed` are `Hash{String => Integer}` (failed keyed by error class name), `steps` is `Hash{String => StepStats}`; methods `#rejected_total`, `#marked_total`, `#failed_total`, `#rate`, `#merge(other)`, `#to_h`, `#summary`.
  - `Metacrunch::StatsCollector.new(step_names, profile: false)` with `#count_read`, `#count_written`, `#step_in(name)`, `#step_out(name, count = 1)`, `#step_filtered(name)`, `#step_rejected(name, reason)`, `#step_failed(name, error)`, `#step_time(name, seconds)`, `#mark(reason)`, `#failed_total`, `#profile?`, `#snapshot → Stats`.
  - `Metacrunch::Result = Data.define(:status, :error, :stats)` with `#ok?`, `#summary`.

- [ ] **Step 1: Write the failing tests**

`test/unit/stats_collector_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StatsCollectorTest < Minitest::Test

  def test_snapshot_reports_job_and_step_counts
    collector = Metacrunch::StatsCollector.new(["map#1", "reject#2"])
    3.times do
      collector.count_read
      collector.step_in("map#1")
      collector.step_out("map#1")
      collector.step_in("reject#2")
    end
    collector.step_rejected("reject#2", "Patent")
    collector.step_filtered("reject#2")
    collector.step_out("reject#2")
    collector.count_written
    collector.mark("No title")
    stats = collector.snapshot

    assert_equal [3, 1, 1], [stats.read, stats.written, stats.filtered]
    assert_equal [{"Patent" => 1}, {"No title" => 1}], [stats.rejected, stats.marked]
    assert_equal Metacrunch::StepStats.new(input: 3, output: 1, filtered: 1, rejected: 1, failed: 0, time: nil),
                 stats.steps["reject#2"]
  end

  def test_failures_are_counted_by_error_class
    collector = Metacrunch::StatsCollector.new(["map#1"])
    collector.step_failed("map#1", KeyError.new("x"))
    collector.step_failed("map#1", KeyError.new("y"))

    assert_equal 2, collector.failed_total
    assert_equal({"KeyError" => 2}, collector.snapshot.failed)
  end

  def test_step_time_is_tracked_only_when_profiling
    plain = Metacrunch::StatsCollector.new(["map#1"])
    profiled = Metacrunch::StatsCollector.new(["map#1"], profile: true)
    profiled.step_time("map#1", 0.25)

    assert_nil plain.snapshot.steps["map#1"].time
    assert_in_delta 0.25, profiled.snapshot.steps["map#1"].time
  end

end
```

`test/unit/stats_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StatsTest < Minitest::Test

  def test_merge_adds_counts_and_keeps_the_longer_duration
    a = stats(read: 2, rejected: {"Patent" => 1}, steps: {"map#1" => step(input: 2, output: 2)}, duration: 1.0)
    b = stats(read: 3, rejected: {"Patent" => 2, "Private" => 1}, steps: {"map#1" => step(input: 3, output: 1)},
              duration: 2.5)
    merged = a.merge(b)

    assert_equal [5, {"Patent" => 3, "Private" => 1}, 2.5], [merged.read, merged.rejected, merged.duration]
    assert_equal step(input: 5, output: 3), merged.steps["map#1"]
  end

  def test_summary_lists_reasons_and_omits_zero_counts
    text = stats(read: 10, written: 8, rejected: {"Patent" => 2}, duration: 2.0).summary

    assert_equal "read 10, written 8, rejected 2 (Patent: 2) in 2.00s (5 records/s)", text
  end

  def test_to_h_includes_rate_and_step_hashes
    hash = stats(read: 4, steps: {"map#1" => step(input: 4, output: 4)}, duration: 2.0).to_h

    assert_in_delta 2.0, hash[:rate]
    assert_equal 4, hash[:steps]["map#1"][:output]
  end

  private

  def stats(read: 0, written: 0, rejected: {}, steps: {}, duration: 1.0)
    Metacrunch::Stats.new(read:, written:, filtered: 0, rejected:, marked: {}, failed: {}, steps:, duration:)
  end

  def step(input: 0, output: 0)
    Metacrunch::StepStats.new(input:, output:, filtered: 0, rejected: 0, failed: 0, time: nil)
  end

end
```

`test/unit/result_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ResultTest < Minitest::Test

  def test_summary_names_status_and_error
    stats = Metacrunch::Stats.new(
      read: 1, written: 0, filtered: 0, rejected: {}, marked: {}, failed: {}, steps: {}, duration: 1.0
    )
    result = Metacrunch::Result.new(status: :aborted, error: RuntimeError.new("boom"), stats:)

    assert_equal "aborted: read 1, written 0 in 1.00s (1 records/s); RuntimeError: boom", result.summary
    refute_predicate result, :ok?
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `for f in test/unit/stats_test.rb test/unit/stats_collector_test.rb test/unit/result_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: `NameError: uninitialized constant Metacrunch::Stats` (and `StatsCollector`, `Result`).

- [ ] **Step 3: Implement**

`lib/metacrunch/stats.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  # Counters of one step. time is nil unless the job uses `profile true`.
  StepStats = Data.define(:input, :output, :filtered, :rejected, :failed, :time) do
    def merge(other)
      with(
        input: input + other.input,
        output: output + other.output,
        filtered: filtered + other.filtered,
        rejected: rejected + other.rejected,
        failed: failed + other.failed,
        time: time || other.time ? time.to_f + other.time.to_f : nil
      )
    end
  end

  # Immutable counters of a run. rejected and marked map a reason to a
  # count, failed maps an error class name to a count, steps maps a step
  # name to its StepStats.
  Stats = Data.define(:read, :written, :filtered, :rejected, :marked, :failed, :steps, :duration) do
    def rejected_total = rejected.values.sum
    def marked_total = marked.values.sum
    def failed_total = failed.values.sum

    # Records read per second.
    def rate
      duration.positive? ? read / duration : 0.0
    end

    # Adds another snapshot, e.g. from a worker process. The duration is
    # the longer one, because workers run at the same time.
    def merge(other)
      add = ->(mine, theirs) { mine.merge(theirs) { |_key, a, b| a + b } }
      with(
        read: read + other.read,
        written: written + other.written,
        filtered: filtered + other.filtered,
        rejected: add.call(rejected, other.rejected),
        marked: add.call(marked, other.marked),
        failed: add.call(failed, other.failed),
        steps: steps.merge(other.steps) { |_name, mine, theirs| mine.merge(theirs) },
        duration: [duration, other.duration].max
      )
    end

    def to_h
      super.merge(rate:, steps: steps.transform_values(&:to_h))
    end

    def summary
      counts = ->(hash) { hash.map { |key, count| "#{key}: #{count}" }.join(", ") }
      parts = ["read #{read}", "written #{written}"]
      parts << "filtered #{filtered}" if filtered.positive?
      parts << "rejected #{rejected_total} (#{counts.call(rejected)})" if rejected_total.positive?
      parts << "marked #{marked_total} (#{counts.call(marked)})" if marked_total.positive?
      parts << "failed #{failed_total} (#{counts.call(failed)})" if failed_total.positive?
      "#{parts.join(", ")} in #{format("%.2f", duration)}s (#{rate.round} records/s)"
    end
  end

end
```

`lib/metacrunch/stats_collector.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Mutable counters used by the engine during a run. #snapshot returns
  # an immutable Stats.
  class StatsCollector

    StepCounter = Struct.new(:input, :output, :filtered, :rejected, :failed, :time)

    def initialize(step_names, profile: false)
      @profile = profile
      @read = 0
      @written = 0
      @rejected = Hash.new(0)
      @marked = Hash.new(0)
      @failed = Hash.new(0)
      @steps = step_names.to_h { |name| [name, StepCounter.new(0, 0, 0, 0, 0, profile ? 0.0 : nil)] }
      @started_at = now
    end

    def profile?
      @profile
    end

    def count_read
      @read += 1
    end

    def count_written
      @written += 1
    end

    def step_in(name)
      @steps.fetch(name).input += 1
    end

    def step_out(name, count = 1)
      @steps.fetch(name).output += count
    end

    def step_filtered(name)
      @steps.fetch(name).filtered += 1
    end

    def step_rejected(name, reason)
      @steps.fetch(name).rejected += 1
      @rejected[reason] += 1
    end

    def step_failed(name, error)
      @steps.fetch(name).failed += 1
      @failed[error.class.name] += 1
    end

    def step_time(name, seconds)
      @steps.fetch(name).time += seconds
    end

    def mark(reason)
      @marked[reason] += 1
    end

    def failed_total
      @failed.values.sum
    end

    def snapshot
      Stats.new(
        read: @read,
        written: @written,
        filtered: @steps.each_value.sum(&:filtered),
        rejected: @rejected.dup,
        marked: @marked.dup,
        failed: @failed.dup,
        steps: @steps.transform_values { |counter| StepStats.new(**counter.to_h) },
        duration: now - @started_at
      )
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

  end
end
```

`lib/metacrunch/result.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  # Outcome of a run. status is :ok, :ok_with_failures or :aborted; error
  # is the error that aborted the run.
  Result = Data.define(:status, :error, :stats) do
    def ok? = status == :ok

    def summary
      text = "#{status}: #{stats.summary}"
      error ? "#{text}; #{error.class}: #{error.message}" : text
    end
  end

end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/context"`:

```ruby
require_relative "metacrunch/stats"
require_relative "metacrunch/stats_collector"
require_relative "metacrunch/result"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `for f in test/unit/stats_test.rb test/unit/stats_collector_test.rb test/unit/result_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: all `0 failures, 0 errors`.

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add stats, stats collector and result

Stats is an immutable snapshot with per-reason and per-step counts,
merge (for later worker processes), to_h and a one-line summary.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 4: Callables and steps

**Files:**
- Create: `lib/metacrunch/callable.rb`, `lib/metacrunch/step.rb`, `test/unit/step_test.rb`
- Modify: `lib/metacrunch.rb` (add requires after `require_relative "metacrunch/result"`)

**Interfaces:**
- Produces:
  - `Metacrunch::Callable.accepts_second_argument?(callable) → Boolean` (a second required/optional positional parameter, or a **named** splat; works for Proc, Method and objects with `#call`), `Metacrunch::Callable.ensure_callable!(object, role) → object` (raises `ArgumentError`).
  - `Metacrunch::STEP_KINDS = [:map, :filter, :reject, :flat_map]`.
  - `Metacrunch::Step = Data.define(:kind, :callable, :name, :reason, :pass_context)`; `Step.build(kind, callable, name:, reason: nil)`; `#call(record, ctx)`.

- [ ] **Step 1: Write the failing tests**

`test/unit/step_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class StepTest < Minitest::Test

  class OneArgument

    def self.call(record) = [record]

  end

  class TwoArguments

    def call(record, ctx) = [record, ctx]

  end

  # callable => what it returns for step.call("r", "ctx")
  CASES = {
    "block_with_one_parameter" => [proc { |record| [record] }, ["r"]],
    "block_using_it" => [proc { [it] }, ["r"]],
    "block_with_two_parameters" => [proc { |record, ctx| [record, ctx] }, ["r", "ctx"]],
    "lambda_with_one_parameter" => [->(record) { [record] }, ["r"]],
    "lambda_with_optional_second_parameter" => [->(record, ctx = nil) { [record, ctx] }, ["r", "ctx"]],
    "block_with_named_splat" => [proc { |*args| args }, ["r", "ctx"]],
    "class_with_self_call" => [OneArgument, ["r"]],
    "object_with_two_parameter_call" => [TwoArguments.new, ["r", "ctx"]]
  }.freeze

  CASES.each do |description, (callable, expected)|
    define_method("test_context_passing_for_#{description}") do
      step = Metacrunch::Step.build(:map, callable, name: "map#1")

      assert_equal expected, step.call("r", "ctx")
    end
  end

  def test_symbol_procs_get_only_the_record
    step = Metacrunch::Step.build(:map, :upcase.to_proc, name: "map#1")

    assert_equal "R", step.call("r", "ctx")
  end

  def test_rejects_unknown_kinds_and_non_callables
    assert_raises(ArgumentError) { Metacrunch::Step.build(:each, proc { it }, name: "x") }
    assert_raises(ArgumentError) { Metacrunch::Step.build(:map, "not callable", name: "x") }
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/step_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Step`.

- [ ] **Step 3: Implement**

`lib/metacrunch/callable.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Helpers for callables: blocks, lambdas, Method objects and any object
  # that responds to #call.
  module Callable

    POSITIONAL = [:req, :opt].freeze

    module_function

    # True if the callable takes a second positional argument (the context):
    # a second required or optional parameter, or a named splat. Symbol
    # procs (&:odd?) have an unnamed splat and get only the record.
    def accepts_second_argument?(callable)
      parameters = parameters_of(callable)
      return true if parameters.any? { |type, name| type == :rest && name }

      parameters.count { |type, _name| POSITIONAL.include?(type) } >= 2
    end

    def parameters_of(callable)
      case callable
      when Proc then callable.parameters(lambda: true)
      when Method then callable.parameters
      else callable.method(:call).parameters
      end
    end

    def ensure_callable!(object, role)
      return object if object.respond_to?(:call)

      raise ArgumentError, "#{role} must respond to #call, got #{object.inspect}"
    end

  end
end
```

`lib/metacrunch/step.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  STEP_KINDS = [:map, :filter, :reject, :flat_map].freeze

  # One step of a pipeline. reason is set for filter/reject steps that
  # reject (instead of silently filter) the records they drop.
  Step = Data.define(:kind, :callable, :name, :reason, :pass_context) do
    def self.build(kind, callable, name:, reason: nil)
      raise ArgumentError, "unknown step kind #{kind.inspect}" unless STEP_KINDS.include?(kind)

      Callable.ensure_callable!(callable, "#{kind} step #{name}")
      new(kind:, callable:, name:, reason:, pass_context: Callable.accepts_second_argument?(callable))
    end

    def call(record, ctx)
      pass_context ? callable.call(record, ctx) : callable.call(record)
    end
  end

end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/result"`:

```ruby
require_relative "metacrunch/callable"
require_relative "metacrunch/step"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/step_test.rb`
Expected: `10 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add steps and context arity detection

A step passes the context only to callables that accept a second
positional argument. Symbol procs (&:odd?) get only the record.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 5: Sink adapter

**Files:**
- Create: `lib/metacrunch/sink_adapter.rb`, `test/unit/sink_adapter_test.rb`
- Modify: `lib/metacrunch.rb` (add require after `require_relative "metacrunch/step"`)

**Interfaces:**
- Consumes: `Callable.accepts_second_argument?`, `Context#seal!`.
- Produces: `Metacrunch::SinkAdapter.new(sink, batch: nil)` with `#sink`, `#open(context)`, `#write(record, ctx)` (seals ctx, writes or buffers), `#flush` (writes buffered records via `write_batch(records[, contexts])` or `write`), `#close`. Raises `ArgumentError` for objects without `#write` and for a `batch` that is not a positive Integer.

- [ ] **Step 1: Write the failing tests**

`test/unit/sink_adapter_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class SinkAdapterTest < Minitest::Test

  class PlainSink

    attr_reader :written

    def initialize
      @written = []
    end

    def write(record)
      @written << record
    end

  end

  class ContextSink

    attr_reader :written

    def initialize
      @written = []
    end

    def write(record, ctx)
      @written << [record, ctx.position]
    end

  end

  class BatchSink

    attr_reader :batches

    def initialize
      @batches = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @batches << records
    end

  end

  class BatchContextSink

    attr_reader :positions

    def initialize
      @positions = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(_records, contexts)
      @positions << contexts.map(&:position)
    end

  end

  def test_writes_records_one_by_one_without_batch
    sink = PlainSink.new
    adapter = Metacrunch::SinkAdapter.new(sink)
    adapter.write("a", context(1))
    adapter.write("b", context(2))

    assert_equal ["a", "b"], sink.written
  end

  def test_passes_the_context_to_sinks_that_accept_it
    sink = ContextSink.new
    Metacrunch::SinkAdapter.new(sink).write("a", context(5))

    assert_equal [["a", 5]], sink.written
  end

  def test_batches_and_flushes_the_rest
    sink = BatchSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 2)
    ["a", "b", "c"].each_with_index { |record, index| adapter.write(record, context(index + 1)) }
    before_flush = sink.batches.dup
    adapter.flush

    assert_equal [["a", "b"]], before_flush
    assert_equal [["a", "b"], ["c"]], sink.batches
  end

  def test_falls_back_to_write_without_write_batch
    sink = PlainSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 10)
    adapter.write("a", context(1))
    adapter.write("b", context(2))
    before_flush = sink.written.dup
    adapter.flush

    assert_empty before_flush
    assert_equal ["a", "b"], sink.written
  end

  def test_passes_contexts_to_write_batch_that_accepts_them
    sink = BatchContextSink.new
    adapter = Metacrunch::SinkAdapter.new(sink, batch: 2)
    adapter.write("a", context(1))
    adapter.write("b", context(2))

    assert_equal [[1, 2]], sink.positions
  end

  def test_seals_contexts_given_to_sinks
    ctx = context(1)
    Metacrunch::SinkAdapter.new(PlainSink.new).write("a", ctx)

    assert_raises(Metacrunch::ContractError) { ctx.mark("late") }
  end

  def test_forwards_open_and_close_when_defined
    events = []
    sink = Object.new
    sink.define_singleton_method(:write) { |_record| nil }
    sink.define_singleton_method(:open) { |context| events << [:open, context] }
    sink.define_singleton_method(:close) { events << :close }
    adapter = Metacrunch::SinkAdapter.new(sink)
    adapter.open(:context)
    adapter.close

    assert_equal [[:open, :context], :close], events
  end

  def test_open_and_close_are_optional
    adapter = Metacrunch::SinkAdapter.new(PlainSink.new)

    assert_nil adapter.open(:context)
    assert_nil adapter.close
  end

  def test_rejects_invalid_sinks_and_batch_sizes
    assert_raises(ArgumentError) { Metacrunch::SinkAdapter.new(Object.new) }
    assert_raises(ArgumentError) { Metacrunch::SinkAdapter.new(PlainSink.new, batch: 0) }
  end

  private

  def context(position)
    Metacrunch::Context.new(id: nil, position:, logger: Logger.new(nil))
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/sink_adapter_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::SinkAdapter`.

- [ ] **Step 3: Implement**

`lib/metacrunch/sink_adapter.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Wraps a sink: batching (batch: n), context passing and the optional
  # open, close and write_batch methods.
  class SinkAdapter

    attr_reader :sink

    def initialize(sink, batch: nil)
      raise ArgumentError, "sink must respond to #write, got #{sink.inspect}" unless sink.respond_to?(:write)
      unless batch.nil? || (batch.is_a?(Integer) && batch.positive?)
        raise ArgumentError, "batch must be a positive Integer, got #{batch.inspect}"
      end

      @sink = sink
      @batch = batch
      @write_with_context = Callable.accepts_second_argument?(sink.method(:write))
      @write_batch = sink.respond_to?(:write_batch) ? sink.method(:write_batch) : nil
      @write_batch_with_context = @write_batch && Callable.accepts_second_argument?(@write_batch)
      @records = []
      @contexts = []
    end

    def open(context)
      @sink.open(context) if @sink.respond_to?(:open)
    end

    def write(record, ctx)
      ctx.seal!
      return write_one(record, ctx) unless @batch

      @records << record
      @contexts << ctx
      flush if @records.size >= @batch
    end

    # Writes the buffered records. The engine calls it once more before close.
    def flush
      return if @records.empty?

      records = @records
      contexts = @contexts
      @records = []
      @contexts = []
      if @write_batch
        @write_batch_with_context ? @write_batch.call(records, contexts) : @write_batch.call(records)
      else
        records.zip(contexts) { |record, ctx| write_one(record, ctx) }
      end
    end

    def close
      @sink.close if @sink.respond_to?(:close)
    end

    private

    def write_one(record, ctx)
      @write_with_context ? @sink.write(record, ctx) : @sink.write(record)
    end

  end
end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/step"`:

```ruby
require_relative "metacrunch/sink_adapter"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/sink_adapter_test.rb`
Expected: `9 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add the sink adapter

Batching happens at the sink (batch: n, write_batch with fallback to
write). Sinks get sealed contexts if their write methods accept them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 6: Job parameters

**Files:**
- Create: `lib/metacrunch/params.rb`, `test/unit/params_test.rb`
- Modify: `lib/metacrunch.rb` (add require after `require_relative "metacrunch/sink_adapter"`)

**Interfaces:**
- Consumes: `Metacrunch::ParamError`.
- Produces: `Metacrunch::Params.new` with declaration methods `#param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil)`, `#args(name, min: 0, max: nil, desc: nil)`; binding `#bind_argv(argv, env: ENV) → Data`, `#bind_hash(hash) → Data`; `#help → String`; readers `#definitions` (`Hash{Symbol => Params::Definition}`), `#args_definition` (`Params::ArgsDefinition` or nil). `Params::Definition#option` returns the CLI option (`:bulk_size` → `"--bulk-size"`). Types: `String`, `Integer`, `Float`, `:bool`, `Array`. Reserved names: `:help`, `:job`.

- [ ] **Step 1: Write the failing tests**

`test/unit/params_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ParamsTest < Minitest::Test

  ARGV_ERRORS = {
    "missing_required_value" => [[], /missing required parameter --index/],
    "invalid_integer" => [["--index", "i", "--bulk", "ten", "f"], /invalid value for --bulk: "ten" is not an Integer/],
    "unknown_option" => [["--index", "i", "--color", "red", "f"], /invalid option: --color/],
    "missing_option_value" => [["--index"], /missing argument: --index/],
    "too_few_arguments" => [["--index", "i"], /expected at least 1 argument\(s\) for files, got 0/],
    "too_many_arguments" => [["--index", "i", "a", "b", "c"], /expected at most 2 argument\(s\) for files, got 3/],
    "help_does_not_exit" => [["--index", "i", "--help", "f"], /invalid option: --help/],
    "version_does_not_exit" => [["--index", "i", "--version", "f"], /invalid option: --version/]
  }.freeze

  DECLARATION_ERRORS = {
    "reserved_name" => proc { param :help },
    "duplicate_name" => proc { param :x; param :x },
    "unsupported_type" => proc { param :x, Symbol },
    "default_and_required" => proc { param :x, String, default: "a", required: true },
    "args_twice" => proc { args :a; args :b },
    "min_above_max" => proc { args :a, min: 3, max: 1 }
  }.freeze

  def test_cli_value_wins_over_environment_and_default
    params = schema { param :url, String, default: "http://default", env: "ES_URL" }
    env = {"ES_URL" => "http://env"}

    assert_equal "http://cli", params.bind_argv(["--url", "http://cli"], env:).url
    assert_equal "http://env", params.bind_argv([], env:).url
    assert_equal "http://default", params.bind_argv([], env: {}).url
  end

  def test_converts_cli_values_to_the_declared_types
    params = schema do
      param :bulk_size, Integer
      param :ratio, Float
      param :verbose, :bool
      param :fields, Array
    end
    values = params.bind_argv(["--bulk-size", "10", "--ratio", "0.5", "--no-verbose", "--fields", "a, b"], env: {})

    assert_equal({bulk_size: 10, ratio: 0.5, verbose: false, fields: ["a", "b"]}, values.to_h)
  end

  def test_converts_environment_values
    params = schema do
      param :verbose, :bool, env: "VERBOSE"
      param :bulk, Integer, env: "BULK"
    end

    assert_equal({verbose: true, bulk: 5}, params.bind_argv([], env: {"VERBOSE" => "yes", "BULK" => "5"}).to_h)
  end

  def test_collects_positional_arguments
    values = job_schema.bind_argv(["--index", "books", "a.xml", "b.xml"], env: {})

    assert_equal({index: "books", bulk: 100, files: ["a.xml", "b.xml"]}, values.to_h)
  end

  ARGV_ERRORS.each do |description, (argv, message)|
    define_method("test_bind_argv_error_#{description}") do
      error = assert_raises(Metacrunch::ParamError) { job_schema.bind_argv(argv, env: {}) }

      assert_match message, error.message
    end
  end

  def test_rejects_arguments_without_args_declaration
    error = assert_raises(Metacrunch::ParamError) { schema { param :x }.bind_argv(["a"], env: {}) }

    assert_match(/unexpected arguments: a/, error.message)
  end

  def test_bind_hash_keeps_typed_values_and_converts_strings
    params = schema do
      param :bulk, Integer
      param :verbose, :bool
      args :files
    end
    values = params.bind_hash(bulk: "10", verbose: true, files: ["a"])

    assert_equal({bulk: 10, verbose: true, files: ["a"]}, values.to_h)
  end

  def test_bind_hash_rejects_unknown_keys_and_wrong_types
    params = schema { param :bulk, Integer }

    assert_raises(Metacrunch::ParamError) { params.bind_hash(color: "red") }
    assert_raises(Metacrunch::ParamError) { params.bind_hash(bulk: 1.5) }
  end

  DECLARATION_ERRORS.each do |description, declaration|
    define_method("test_declaration_error_#{description}") do
      assert_raises(ArgumentError) { schema(&declaration) }
    end
  end

  def test_help_lists_options_and_arguments
    help = schema do
      param :index, String, required: true, short: "-i", desc: "Index name"
      param :url, String, default: "http://localhost:9200", env: "ES_URL"
      args :files, min: 1, desc: "Input files"
    end.help

    assert_match(/-i, --index VALUE\s+Index name \(required\)/, help)
    assert_match(%r{--url VALUE\s+\(default: http://localhost:9200, env: ES_URL\)}, help)
    assert_match(/FILES  Input files  \(1 or more arguments\)/, help)
  end

  private

  def schema(&declaration)
    Metacrunch::Params.new.tap { |params| params.instance_exec(&declaration) }
  end

  def job_schema
    schema do
      param :index, String, required: true
      param :bulk, Integer, default: 100
      args :files, min: 1, max: 2
    end
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/params_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Params`.

- [ ] **Step 3: Implement**

`lib/metacrunch/params.rb`:

```ruby
# frozen_string_literal: true

require "optparse"

module Metacrunch
  # The parameters a job declares in `params { ... }`, and their binding
  # from CLI arguments (#bind_argv) or a Hash (#bind_hash).
  class Params

    TYPES = [String, Integer, Float, :bool, Array].freeze
    RESERVED = [:help, :job].freeze
    TRUE_VALUES = ["true", "yes", "on", "1"].freeze
    FALSE_VALUES = ["false", "no", "off", "0"].freeze

    CONVERTERS = {
      String => ->(raw) { raw },
      Integer => ->(raw) { Integer(raw, 10) },
      Float => ->(raw) { Float(raw) },
      Array => ->(raw) { raw.split(",").map(&:strip) },
      :bool => lambda do |raw|
        return true if TRUE_VALUES.include?(raw.downcase)
        return false if FALSE_VALUES.include?(raw.downcase)

        raise ArgumentError, "not a boolean: #{raw}"
      end
    }.freeze

    VALID = {
      String => ->(value) { value.is_a?(String) },
      Integer => ->(value) { value.is_a?(Integer) },
      Float => ->(value) { value.is_a?(Float) },
      Array => ->(value) { value.is_a?(Array) },
      :bool => ->(value) { [true, false].include?(value) }
    }.freeze

    TYPE_NAMES = {
      String => "a String",
      Integer => "an Integer",
      Float => "a Float",
      Array => "a comma-separated list",
      :bool => "a boolean (true/false, yes/no, on/off, 1/0)"
    }.freeze

    Definition = Data.define(:name, :type, :default, :required, :env, :desc, :short) do
      def option = "--#{name.to_s.tr("_", "-")}"
    end

    ArgsDefinition = Data.define(:name, :min, :max, :desc)

    attr_reader :definitions, :args_definition

    def initialize
      @definitions = {}
      @args_definition = nil
    end

    def param(name, type = String, default: nil, required: false, env: nil, desc: nil, short: nil)
      name = check_name!(name)
      raise ArgumentError, "unsupported type #{type.inspect} for parameter #{name}" unless TYPES.include?(type)
      raise ArgumentError, "parameter #{name}: use either default: or required: true" if required && !default.nil?

      @definitions[name] = Definition.new(name:, type:, default:, required:, env:, desc:, short:)
      nil
    end

    def args(name, min: 0, max: nil, desc: nil)
      raise ArgumentError, "args can only be declared once" if @args_definition

      name = check_name!(name)
      raise ArgumentError, "args #{name}: min must not be greater than max" if max && min > max

      @args_definition = ArgsDefinition.new(name:, min:, max:, desc:)
      nil
    end

    # Binds CLI arguments. Parameters with env: that are not given on the
    # command line are read from env.
    def bind_argv(argv, env: ENV)
      given = {}
      positional = option_parser(given).parse(argv)
      values = @definitions.to_h do |name, definition|
        [name, resolve(definition, given.fetch(name) { env_value(definition, env) })]
      end
      build(values, positional)
    rescue OptionParser::ParseError => e
      raise ParamError, e.message
    end

    # Binds a Hash, e.g. in tests. Values may already have the declared
    # type or be strings, which are converted. No environment lookup.
    def bind_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      args_name = @args_definition&.name
      unknown = hash.keys - @definitions.keys - [args_name]
      raise ParamError, "unknown parameter #{unknown.first}" if unknown.any?

      values = @definitions.to_h { |name, definition| [name, resolve(definition, hash[name])] }
      build(values, args_name ? Array(hash[args_name]) : [])
    end

    def help
      lines = option_parser({}).summarize
      lines << "    #{args_usage}\n" if @args_definition
      lines.join
    end

    private

    def check_name!(name)
      name = name.to_sym
      raise ArgumentError, "parameter name #{name} is reserved" if RESERVED.include?(name)
      if @definitions.key?(name) || @args_definition&.name == name
        raise ArgumentError, "parameter #{name} is declared twice"
      end

      name
    end

    def option_parser(given)
      OptionParser.new do |parser|
        # Remove the built-in --help and --version: they would print and exit.
        parser.base.long.clear
        @definitions.each_value do |definition|
          parser.on(*switches(definition)) { |value| given[definition.name] = value }
        end
      end
    end

    def switches(definition)
      long = if definition.type == :bool
               "--[no-]#{definition.option.delete_prefix("--")}"
             else
               "#{definition.option} VALUE"
             end
      [definition.short, long, description(definition)].compact
    end

    def description(definition)
      notes = []
      notes << "required" if definition.required
      notes << "default: #{definition.default}" unless definition.default.nil?
      notes << "env: #{definition.env}" if definition.env
      text = [definition.desc, ("(#{notes.join(", ")})" if notes.any?)].compact.join(" ")
      text unless text.empty?
    end

    def env_value(definition, env)
      env[definition.env] if definition.env
    end

    def resolve(definition, raw)
      value = raw.nil? ? definition.default : convert(definition, raw)
      raise ParamError, "missing required parameter #{definition.option}" if definition.required && value.nil?

      value
    end

    def convert(definition, raw)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw)
    rescue ArgumentError, TypeError
      invalid!(definition, raw)
    end

    def invalid!(definition, raw)
      expected = TYPE_NAMES.fetch(definition.type)
      raise ParamError, "invalid value for #{definition.option}: #{raw.inspect} is not #{expected}"
    end

    def build(values, positional)
      if @args_definition
        check_args!(positional)
        values[@args_definition.name] = positional
      elsif positional.any?
        raise ParamError, "unexpected arguments: #{positional.join(" ")}"
      end
      values_class.new(**values)
    end

    def check_args!(positional)
      definition = @args_definition
      if positional.size < definition.min
        raise ParamError,
              "expected at least #{definition.min} argument(s) for #{definition.name}, got #{positional.size}"
      end
      return unless definition.max && positional.size > definition.max

      raise ParamError, "expected at most #{definition.max} argument(s) for #{definition.name}, got #{positional.size}"
    end

    def args_usage
      definition = @args_definition
      count = if definition.max
                "#{definition.min} to #{definition.max} arguments"
              else
                "#{definition.min} or more arguments"
              end
      [definition.name.to_s.upcase, definition.desc, "(#{count})"].compact.join("  ")
    end

    def values_class
      @values_class ||= Data.define(*@definitions.keys, *[@args_definition&.name].compact)
    end

  end
end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/sink_adapter"`:

```ruby
require_relative "metacrunch/params"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/params_test.rb`
Expected: `0 failures, 0 errors`.

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add job parameters

Parameters are declared with param/args, bound from CLI arguments
(CLI > ENV > default) or a Hash, converted to their types and validated.
Errors raise ParamError; OptionParser's --help/--version are disabled.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 7: Pipeline and DSL builder

**Files:**
- Create: `lib/metacrunch/pipeline.rb`, `lib/metacrunch/builder.rb`, `test/support/pipeline_helper.rb`, `test/support/collecting_sink.rb`, `test/unit/builder_test.rb`
- Modify: `lib/metacrunch.rb` (add requires after `require_relative "metacrunch/params"`)

**Interfaces:**
- Consumes: `Step.build`, `SinkAdapter.new`, `Params`, `Callable.ensure_callable!`.
- Produces:
  - `Metacrunch::Pipeline = Data.define(:source, :id_extractor, :steps, :sink, :rejects, :errors, :on_error, :max_errors, :profile, :before_hooks, :after_hooks, :params, :logger)`; `sink`/`rejects`/`errors` are `SinkAdapter` or nil.
  - `Metacrunch::Builder.new(binder:, logger:, describe: false)`; `binder.call(params_schema) → values`. DSL: `params(&)`, `params`, `source(enumerable, id: nil)`, `map(callable = nil, name: nil, &)`, `flat_map(callable = nil, name: nil, &)`, `filter(reason_or_callable = nil, callable = nil, name: nil, &)`, `reject(...)` (same as filter), `sink(object, batch: nil)`, `rejects(object, batch: nil)`, `errors(object, batch: nil)`, `on_error(policy, max_errors: nil)`, `profile(enabled)`, `before(&)`, `after(&)`, `logger`. `#build → Pipeline`. `Builder::DESCRIBED` is thrown with the `Params` schema in describe mode.
  - Test helpers: `PipelineHelper#build_pipeline(params: {}, logger: SILENT_LOGGER, &recipe) → Pipeline`, `#run_pipeline(params: {}, logger: SILENT_LOGGER, &recipe) → Result` (uses `Metacrunch::Engine`, Task 8), `PipelineHelper::SILENT_LOGGER`; `CollectingSink` with `#records`, `#contexts`, `#events`, `open`, `write(record, ctx)`, `close`.

- [ ] **Step 1: Write the test helpers**

`test/support/pipeline_helper.rb`:

```ruby
# frozen_string_literal: true

module PipelineHelper

  SILENT_LOGGER = Logger.new(nil)

  def build_pipeline(params: {}, logger: SILENT_LOGGER, &recipe)
    builder = Metacrunch::Builder.new(binder: ->(schema) { schema.bind_hash(params) }, logger:)
    builder.instance_exec(&recipe)
    builder.build
  end

  def run_pipeline(params: {}, logger: SILENT_LOGGER, &)
    Metacrunch::Engine.new(build_pipeline(params:, logger:, &)).run
  end

end
```

`test/support/collecting_sink.rb`:

```ruby
# frozen_string_literal: true

# Sink for tests: keeps records, contexts and lifecycle events.
class CollectingSink

  attr_reader :records, :contexts, :events

  def initialize
    @records = []
    @contexts = []
    @events = []
  end

  def open(_context)
    @events << :open
  end

  def write(record, ctx)
    @records << record
    @contexts << ctx
  end

  def close
    @events << :close
  end

end
```

- [ ] **Step 2: Write the failing tests**

`test/unit/builder_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class BuilderTest < Minitest::Test

  include PipelineHelper

  INVALID_RECIPES = {
    "missing_source" => proc { map { it } },
    "second_source" => proc { source([]); source([]) },
    "source_without_each" => proc { source(42) },
    "second_sink" => proc { source([]); sink(CollectingSink.new); sink(CollectingSink.new) },
    "callable_and_block" => proc { source([]); map(->(record) { record }) { it } },
    "neither_callable_nor_block" => proc { source([]); map },
    "duplicate_step_name" => proc { source([]); map(name: "x") { it }; map(name: "x") { it } },
    "unknown_error_policy" => proc { source([]); on_error :ignore },
    "max_errors_without_skip" => proc { source([]); on_error :abort, max_errors: 3 },
    "params_after_other_statements" => proc { source([]); params { param :x } }
  }.freeze

  def test_builds_a_pipeline_from_the_recipe
    target = CollectingSink.new
    pipeline = build_pipeline do
      source [1, 2], id: ->(record) { record }
      map { it * 2 }
      filter("Too small") { it > 2 }
      reject { it > 100 }
      flat_map(name: "explode") { [it, it] }
      sink target, batch: 10
      on_error :skip, max_errors: 5
    end
    steps = pipeline.steps.map { [it.kind, it.name, it.reason] }

    assert_equal [[:map, "map#1", nil], [:filter, "filter#2", "Too small"], [:reject, "reject#3", nil],
                  [:flat_map, "explode", nil]], steps
    assert_equal [:skip, 5], [pipeline.on_error, pipeline.max_errors]
    assert_same target, pipeline.sink.sink
  end

  def test_accepts_a_reason_or_a_callable_as_first_argument
    callable = ->(record) { record }
    pipeline = build_pipeline do
      source []
      filter callable
      reject "Patent", callable
    end

    assert_equal [[nil, callable], ["Patent", callable]], pipeline.steps.map { [it.reason, it.callable] }
  end

  def test_binds_declared_params
    pipeline = build_pipeline(params: {index: "books"}) do
      params { param :index, String, required: true }
      source [params.index]
    end

    assert_equal ["books"], pipeline.source
  end

  def test_jobs_without_params_reject_given_params
    assert_raises(Metacrunch::ParamError) { build_pipeline(params: {index: "x"}) { source [] } }
  end

  INVALID_RECIPES.each do |description, recipe|
    define_method("test_invalid_recipe_#{description}") do
      assert_raises(ArgumentError) { build_pipeline(&recipe) }
    end
  end

  def test_describe_mode_stops_after_params
    schema = describe do
      params { param :index, String, required: true }
      source raise("the source must not be built in describe mode")
    end

    assert_equal [:index], schema.definitions.keys
  end

  def test_describe_mode_without_params_stops_at_the_first_statement
    schema = describe do
      source []
      raise "the recipe must not continue in describe mode"
    end

    assert_empty schema.definitions
  end

  private

  def describe(&recipe)
    builder = Metacrunch::Builder.new(binder: nil, logger: SILENT_LOGGER, describe: true)
    catch(Metacrunch::Builder::DESCRIBED) do
      builder.instance_exec(&recipe)
      builder.build
    end
  end

end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/builder_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Builder`.

- [ ] **Step 4: Implement**

`lib/metacrunch/pipeline.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch

  # Immutable description of one run, built from a job's recipe by Builder.
  # sink, rejects and errors are SinkAdapter instances or nil.
  Pipeline = Data.define(
    :source, :id_extractor, :steps, :sink, :rejects, :errors,
    :on_error, :max_errors, :profile, :before_hooks, :after_hooks, :params, :logger
  )

end
```

`lib/metacrunch/builder.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Evaluates a job recipe with instance_exec and collects what the DSL
  # declares. #build returns the Pipeline.
  class Builder

    # Thrown in describe mode with the Params schema as soon as it is known.
    DESCRIBED = :metacrunch_described
    ON_ERROR_POLICIES = [:abort, :skip].freeze

    attr_reader :logger

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    def initialize(binder:, logger:, describe: false)
      @binder = binder
      @logger = logger
      @describe = describe
      @schema = nil
      @values = nil
      @used = false
      @source = nil
      @id_extractor = nil
      @steps = []
      @sinks = {}
      @on_error = :abort
      @max_errors = nil
      @profile = false
      @before_hooks = []
      @after_hooks = []
    end

    # With a block: declares the parameters (must be the first statement).
    # Without a block: returns the bound values.
    def params(&declaration)
      return bound_params unless declaration
      raise ArgumentError, "params { ... } must be the first statement of a job" if @used || @schema

      @schema = Params.new
      @schema.instance_exec(&declaration)
      bind_schema
    end

    def source(enumerable, id: nil)
      use!
      raise ArgumentError, "source already defined" if @source
      unless enumerable.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{enumerable.inspect}"
      end

      @id_extractor = id && Callable.ensure_callable!(id, "id:")
      @source = enumerable
      nil
    end

    def map(callable = nil, name: nil, &block)
      add_step(:map, nil, callable, block, name)
    end

    def flat_map(callable = nil, name: nil, &block)
      add_step(:flat_map, nil, callable, block, name)
    end

    # filter { ... }, filter(callable), filter("reason") { ... }, filter("reason", callable)
    def filter(reason_or_callable = nil, callable = nil, name: nil, &block)
      reason, callable = split_reason(reason_or_callable, callable)
      add_step(:filter, reason, callable, block, name)
    end

    # Same arguments as filter.
    def reject(reason_or_callable = nil, callable = nil, name: nil, &block)
      reason, callable = split_reason(reason_or_callable, callable)
      add_step(:reject, reason, callable, block, name)
    end

    def sink(object, batch: nil)
      add_sink(:sink, object, batch)
    end

    def rejects(object, batch: nil)
      add_sink(:rejects, object, batch)
    end

    def errors(object, batch: nil)
      add_sink(:errors, object, batch)
    end

    def on_error(policy, max_errors: nil)
      use!
      unless ON_ERROR_POLICIES.include?(policy)
        raise ArgumentError, "on_error must be one of #{ON_ERROR_POLICIES.inspect}, got #{policy.inspect}"
      end
      unless max_errors.nil? || (policy == :skip && max_errors.is_a?(Integer) && max_errors.positive?)
        raise ArgumentError, "max_errors must be a positive Integer and needs on_error :skip"
      end

      @on_error = policy
      @max_errors = max_errors
      nil
    end

    def profile(enabled)
      use!
      @profile = enabled == true
      nil
    end

    def before(&hook)
      add_hook(@before_hooks, "before", hook)
    end

    def after(&hook)
      add_hook(@after_hooks, "after", hook)
    end

    def build
      ensure_params_bound
      raise ArgumentError, "a job needs a source" unless @source

      Pipeline.new(
        source: @source, id_extractor: @id_extractor, steps: @steps.dup.freeze,
        sink: @sinks[:sink], rejects: @sinks[:rejects], errors: @sinks[:errors],
        on_error: @on_error, max_errors: @max_errors, profile: @profile,
        before_hooks: @before_hooks.dup.freeze, after_hooks: @after_hooks.dup.freeze,
        params: @values, logger: @logger
      )
    end

    private

    def bound_params
      use!
      @values
    end

    # Every DSL statement calls this. In describe mode the first statement
    # ends the evaluation; otherwise jobs without params get an empty schema.
    def use!
      ensure_params_bound
      @used = true
      nil
    end

    def ensure_params_bound
      return if @schema

      @schema = Params.new
      bind_schema
    end

    def bind_schema
      throw DESCRIBED, @schema if @describe

      @values = @binder.call(@schema)
    end

    def split_reason(first, second)
      return [first, second] if first.is_a?(String)
      raise ArgumentError, "the reason must be a String, got #{first.inspect}" unless second.nil?

      [nil, first]
    end

    def add_step(kind, reason, callable, block, name)
      use!
      raise ArgumentError, "#{kind}: pass a callable or a block, not both" if callable && block

      implementation = callable || block
      raise ArgumentError, "#{kind}: a callable or a block is required" unless implementation

      name = (name || "#{kind}##{@steps.size + 1}").to_s
      raise ArgumentError, "duplicate step name #{name}" if @steps.any? { |step| step.name == name }

      @steps << Step.build(kind, implementation, name:, reason:)
      nil
    end

    def add_sink(role, object, batch)
      use!
      raise ArgumentError, "#{role} already defined" if @sinks.key?(role)

      @sinks[role] = SinkAdapter.new(object, batch:)
      nil
    end

    def add_hook(hooks, kind, hook)
      use!
      raise ArgumentError, "#{kind} needs a block" unless hook

      hooks << hook
      nil
    end

  end
end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/params"`:

```ruby
require_relative "metacrunch/pipeline"
require_relative "metacrunch/builder"
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/builder_test.rb`
Expected: `0 failures, 0 errors`. (`run_pipeline` is not used yet; `Metacrunch::Engine` follows in Task 8.)

- [ ] **Step 6: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add the pipeline and the DSL builder

The builder evaluates a recipe into an immutable Pipeline. params must
come first; in describe mode evaluation stops once the parameters are
known, so --help builds no components.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 8: Engine – chain and step semantics

The engine pushes records through the steps. In this task every step error aborts the run; the skip policy, lifecycle and hooks follow in Task 9.

**Files:**
- Create: `lib/metacrunch/executor/inline.rb`, `lib/metacrunch/engine.rb`, `test/unit/engine_test.rb`
- Modify: `lib/metacrunch.rb` (add requires after `require_relative "metacrunch/builder"`)

**Interfaces:**
- Consumes: `Pipeline`, `Step#call`, `SinkAdapter#write/#flush`, `Context`, `StatsCollector`, `Result`, `StepError`, `ContractError`.
- Produces: `Metacrunch::Executor::Inline#run(source) { |record, position| ... }`; `Metacrunch::Engine.new(pipeline, executor: Executor::Inline.new, observer: nil)`, `#run → Result`. Observer protocol: `step_in(step_name, record, ctx)`, `step_out(step_name, outputs_array, ctx)`.

- [ ] **Step 1: Write the failing tests**

`test/unit/engine_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test

  include PipelineHelper

  class YieldingSource

    def each
      yield 1
      yield 2
    end

  end

  class RecordingObserver

    attr_reader :events

    def initialize
      @events = []
    end

    def step_in(step, record, _ctx)
      @events << [:in, step, record]
    end

    def step_out(step, outputs, _ctx)
      @events << [:out, step, outputs]
    end

  end

  class BatchSink

    attr_reader :batches

    def initialize
      @batches = []
    end

    def write(_record) = raise("write_batch expected")

    def write_batch(records)
      @batches << records
    end

  end

  CONTRACT_VIOLATIONS = {
    "map_returns_nil" => proc { map { nil } },
    "flat_map_returns_a_hash" => proc { flat_map { {"a" => 1} } },
    "flat_map_returns_a_non_enumerable" => proc { flat_map { 42 } }
  }.freeze

  def test_runs_records_through_all_step_kinds
    target = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { it * 10 }
      filter { it > 10 }
      reject { it == 40 }
      flat_map { [it, it + 1] }
      sink target
    end

    assert_equal [20, 21, 30, 31], target.records
    assert_equal :ok, result.status
  end

  def test_counts_records_per_step
    stats = run_pipeline do
      source [1, 2, 3]
      filter(&:odd?)
      flat_map { [it, it] }
      sink CollectingSink.new
    end.stats
    filter_step = stats.steps["filter#1"]

    assert_equal [3, 4, 1], [stats.read, stats.written, stats.filtered]
    assert_equal [3, 2, 1], [filter_step.input, filter_step.output, filter_step.filtered]
    assert_equal [2, 4], [stats.steps["flat_map#2"].input, stats.steps["flat_map#2"].output]
  end

  def test_reasoned_filter_and_reject_send_records_to_the_rejects_sink
    rejected = CollectingSink.new
    result = run_pipeline do
      source [{"type" => "patent"}, {"type" => "book", "public" => false}, {"type" => "book", "public" => true}]
      reject("Patent") { it["type"] == "patent" }
      filter("Not public") { it["public"] }
      rejects rejected
    end

    assert_equal({"Patent" => 1, "Not public" => 1}, result.stats.rejected)
    assert_equal [["Patent", "reject#1"], ["Not public", "filter#2"]],
                 rejected.contexts.map { [it.rejection.reason, it.rejection.step] }
  end

  def test_reject_from_the_context_stops_the_record
    later = []
    result = run_pipeline do
      source [1, 2]
      map do |record, ctx|
        ctx.reject!("Odd", value: record) if record.odd?
        record
      end
      map do |record|
        later << record
        record
      end
    end

    assert_equal [2], later
    assert_equal({"Odd" => 1}, result.stats.rejected)
  end

  def test_flat_map_children_get_their_own_context
    target = CollectingSink.new
    result = run_pipeline do
      source [{"isbns" => ["a", "b"]}], id: ->(_record) { "rec1" }
      map do |record, ctx|
        ctx.mark("Parent")
        record
      end
      flat_map { it["isbns"] }
      reject("Isbn a") { it == "a" }
      map do |record, ctx|
        ctx.mark("Child #{record}")
        record
      end
      sink target
    end

    assert_equal ["b"], target.records
    assert_equal [["rec1", 1, ["Parent", "Child b"]]],
                 target.contexts.map { [it.id, it.position, it.marks.map(&:reason)] }
    assert_equal({"Parent" => 1, "Child b" => 1}, result.stats.marked)
  end

  def test_reads_sources_that_only_yield
    target = CollectingSink.new
    run_pipeline do
      source YieldingSource.new
      sink target
    end

    assert_equal [1, 2], target.records
  end

  def test_flat_map_accepts_enumerators
    target = CollectingSink.new
    run_pipeline do
      source [2]
      flat_map { |count| Enumerator.new { |yielder| count.times { yielder << it } } }
      sink target
    end

    assert_equal [0, 1], target.records
  end

  CONTRACT_VIOLATIONS.each do |description, step|
    define_method("test_contract_violation_#{description}_aborts") do
      result = run_pipeline do
        source [1]
        instance_exec(&step)
      end

      assert_equal :aborted, result.status
      assert_instance_of Metacrunch::ContractError, result.error.cause
    end
  end

  def test_step_errors_abort_with_record_details
    result = run_pipeline do
      source [{"id" => "a"}, {"id" => "b"}, {"id" => "c"}], id: ->(record) { record["id"] }
      map(name: "lookup") { it["id"] == "b" ? raise(KeyError, "boom") : it }
    end
    error = result.error

    assert_equal [:aborted, 2], [result.status, result.stats.read]
    assert_equal ["lookup", "b", 2, KeyError], [error.step, error.record_id, error.position, error.cause.class]
    assert_equal "step lookup failed at position 2 (id b): KeyError: boom", error.message
  end

  def test_flushes_sink_batches_at_the_end
    target = BatchSink.new
    run_pipeline do
      source [1, 2, 3]
      sink target, batch: 2
    end

    assert_equal [[1, 2], [3]], target.batches
  end

  def test_observer_sees_inputs_and_outputs_of_each_step
    observer = RecordingObserver.new
    pipeline = build_pipeline do
      source [1, 2]
      filter(&:odd?)
      map { it * 10 }
    end
    Metacrunch::Engine.new(pipeline, observer:).run
    expected = [[:in, "filter#1", 1], [:out, "filter#1", [1]], [:in, "map#2", 1], [:out, "map#2", [10]],
                [:in, "filter#1", 2], [:out, "filter#1", []]]

    assert_equal expected, observer.events
  end

  def test_runs_without_a_sink
    stats = run_pipeline do
      source [1, 2]
      map { it }
    end.stats

    assert_equal [2, 0, 2], [stats.read, stats.written, stats.steps["map#1"].output]
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_test.rb`
Expected: `NameError: uninitialized constant Metacrunch::Engine`.

- [ ] **Step 3: Implement**

`lib/metacrunch/executor/inline.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Executor
    # Processes records one after another, in source order.
    class Inline

      # Yields each source record with its 1-based position. Calls each with
      # a block, so sources that only `yield` work.
      def run(source)
        position = 0
        source.each { |record| yield(record, position += 1) }
      end

    end
  end
end
```

`lib/metacrunch/engine.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Runs a Pipeline: pushes every source record through the chain of steps
  # into the sink and collects stats.
  class Engine

    def initialize(pipeline, executor: Executor::Inline.new, observer: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
    end

    def run
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      @on_mark = @stats.method(:mark)
      error = execute
      Result.new(status: error ? :aborted : :ok, error:, stats: @stats.snapshot)
    end

    private

    # Returns the error that aborted the run, or nil.
    def execute
      chain = build_chain
      @executor.run(@pipeline.source) { |record, position| ingest(chain, record, position) }
      sinks.each(&:flush)
      nil
    rescue StandardError => e
      e
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.errors].compact
    end

    def ingest(chain, record, position)
      @stats.count_read
      id = @pipeline.id_extractor&.call(record)
      chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    def build_chain
      @pipeline.steps.reverse.reduce(method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain: runs the step and passes its outputs on. Only
    # the step itself is covered by the error handling; errors raised
    # further down (later steps, sinks) pass through.
    def link(step, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        @stats.step_in(step.name)
        @observer&.step_in(step.name, record, ctx)
        begin
          outputs = evaluate(step, record, ctx)
        rescue StandardError => e
          @observer&.step_out(step.name, [], ctx)
          next fail_record(step, record, ctx, e)
        end
        @observer&.step_out(step.name, outputs, ctx)
        forward(step, record, ctx, outputs, downstream)
      end
    end

    # Calls the step and returns its outputs as an Array. Raises
    # ContractError if the step breaks its contract.
    def evaluate(step, record, ctx)
      result = step.call(record, ctx)
      return [] if ctx.rejected?

      case step.kind
      when :map then [map_result(step, result)]
      when :filter then kept(step, record, ctx, result)
      when :reject then kept(step, record, ctx, !result)
      else flat_map_result(step, result)
      end
    end

    def kept(step, record, ctx, keep)
      return [record] if keep

      ctx.reject!(step.reason) if step.reason
      []
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_result(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      unless result.respond_to?(:each)
        raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
      end

      outputs = []
      result.each { |output| outputs << output }
      outputs
    end

    def forward(step, record, ctx, outputs, downstream)
      if ctx.rejected?
        reject_record(record, ctx)
      elsif step.kind == :flat_map
        @stats.step_out(step.name, outputs.size)
        outputs.each { |child| downstream.call(child, ctx.copy) }
      elsif outputs.empty?
        @stats.step_filtered(step.name)
      else
        @stats.step_out(step.name)
        downstream.call(outputs.first, ctx)
      end
    end

    def deliver(record, ctx)
      return unless @pipeline.sink

      @pipeline.sink.write(record, ctx)
      @stats.count_written
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @pipeline.rejects&.write(record, ctx)
    end

    def fail_record(step, _record, ctx, error)
      @stats.step_failed(step.name, error)
      step_error = StepError.new(step: step.name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error
    end

  end
end
```

`lib/metacrunch.rb`: add after `require_relative "metacrunch/builder"`:

```ruby
require_relative "metacrunch/executor/inline"
require_relative "metacrunch/engine"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/engine_test.rb`
Expected: `0 failures, 0 errors`.

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add the engine with step semantics

The engine folds the steps into a push chain: map, filter, reject and
flat_map with contract checks, reasoned rejections to the rejects sink,
context copies for flat_map children, sink batching, stats and an
observer seam. Step errors abort the run with a StepError.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 9: Engine – error policy, lifecycle and hooks

**Files:**
- Modify: `lib/metacrunch/engine.rb` (replace the whole file with the version below)
- Create: `test/unit/engine_error_policy_test.rb`, `test/unit/engine_lifecycle_test.rb`

**Interfaces:**
- Consumes: everything from Task 8; `Pipeline#on_error`, `#max_errors`, `#profile`, `#before_hooks`, `#after_hooks`, `#params`; `StatsCollector#step_time`, `#failed_total`; `Failure`.
- Produces: `Metacrunch::OpenContext = Data.define(:params, :logger)` (argument of every `open`); `Engine#run` now applies `on_error :skip`/`max_errors`, writes failed records to the `errors` sink, opens/closes components, runs hooks, records step time when profiling and returns `:ok_with_failures` when records failed under `:skip`. An abort over `max_errors` raises `Metacrunch::Error` ("N failed records exceed max_errors M") with the last `StepError` as cause.

- [ ] **Step 1: Write the failing tests**

`test/unit/engine_error_policy_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineErrorPolicyTest < Minitest::Test

  include PipelineHelper

  class RaisingSink

    def write(_record) = raise("sink broke")

  end

  class MarkingSink

    def write(_record, ctx)
      ctx.mark("too late")
    end

  end

  # recipe => expected error message, also with on_error :skip
  ALWAYS_ABORT = {
    "source" => [proc { source(Enumerator.new { raise "source broke" }) }, /source broke/],
    "id_extractor" => [proc { source([1], id: ->(_record) { raise "id broke" }) }, /id broke/],
    "sink" => [proc { source([1]); sink(RaisingSink.new) }, /sink broke/],
    "sink_changing_the_context" => [proc { source([1]); sink(MarkingSink.new) }, /read-only in sinks/],
    "before_hook" => [proc { source([1]); before { raise "hook broke" } }, /hook broke/]
  }.freeze

  def test_skip_continues_and_sends_failures_to_the_errors_sink
    target = CollectingSink.new
    failed = CollectingSink.new
    result = run_pipeline do
      source [1, 2, 3]
      map(name: "check") { it == 2 ? raise(ArgumentError, "bad") : it }
      sink target
      errors failed
      on_error :skip
    end
    failures = failed.records.zip(failed.contexts).map do |record, ctx|
      [record, ctx.failure.step, ctx.failure.error.message]
    end

    assert_equal [:ok_with_failures, [1, 3]], [result.status, target.records]
    assert_equal({"ArgumentError" => 1}, result.stats.failed)
    assert_equal [[2, "check", "bad"]], failures
  end

  def test_skip_logs_failed_records
    io = StringIO.new
    run_pipeline(logger: Metacrunch.build_logger(io)) do
      source [{"id" => "x"}], id: ->(record) { record["id"] }
      map { raise ArgumentError, "bad" }
      on_error :skip
    end

    assert_match(/ERROR \[x\] step map#1 failed at position 1 \(id x\): ArgumentError: bad/, io.string)
  end

  def test_skip_aborts_when_max_errors_is_exceeded
    result = run_pipeline do
      source [1, 2, 3, 4]
      map { raise ArgumentError, "bad" }
      on_error :skip, max_errors: 2
    end

    assert_equal [:aborted, 3], [result.status, result.stats.read]
    assert_match(/3 failed records exceed max_errors 2/, result.error.message)
    assert_instance_of Metacrunch::StepError, result.error.cause
  end

  ALWAYS_ABORT.each do |description, (recipe, message)|
    define_method("test_errors_in_#{description}_abort_even_with_skip") do
      result = run_pipeline do
        instance_exec(&recipe)
        on_error :skip
      end

      assert_equal :aborted, result.status
      assert_match message, result.error.message
    end
  end

end
```

`test/unit/engine_lifecycle_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class EngineLifecycleTest < Minitest::Test

  include PipelineHelper

  # Can act as source, step and sink. Logs open and close.
  class Component

    attr_reader :context

    def initialize(name, log, records: [1])
      @name = name
      @log = log
      @records = records
    end

    def open(context)
      @context = context
      @log << "open #{@name}"
    end

    def close
      @log << "close #{@name}"
    end

    def each(&)
      @records.each(&)
    end

    def call(record) = record

    def write(_record) = nil

  end

  class FailingClose

    def write(_record) = nil

    def close = raise("close broke")

  end

  class FailingOpen

    def write(_record) = nil

    def open(_context) = raise("open broke")

  end

  def test_opens_components_in_order_and_closes_them_in_reverse
    log = []
    run_pipeline do
      source Component.new("source", log)
      map Component.new("step", log)
      sink Component.new("sink", log)
      rejects Component.new("rejects", log)
    end
    expected = ["open source", "open step", "open sink", "open rejects",
                "close rejects", "close sink", "close step", "close source"]

    assert_equal expected, log
  end

  def test_open_receives_params_and_logger
    component = Component.new("source", [])
    run_pipeline(params: {index: "books"}) do
      params { param :index }
      source component
    end

    assert_equal "books", component.context.params.index
    assert_same PipelineHelper::SILENT_LOGGER, component.context.logger
  end

  def test_hooks_run_around_the_records
    log = []
    run_pipeline do
      source Component.new("source", log)
      map do |record|
        log << "record #{record}"
        record
      end
      before { log << "before" }
      after { |result| log << "after #{result.status} #{result.stats.read}" }
    end

    assert_equal ["open source", "before", "record 1", "close source", "after ok 1"], log
  end

  def test_closes_components_after_an_abort
    log = []
    result = run_pipeline do
      source Component.new("source", log, records: [1, 2])
      map { it == 2 ? raise("boom") : it }
      sink Component.new("sink", log), batch: 10
    end

    assert_equal :aborted, result.status
    assert_equal ["open source", "open sink", "close sink", "close source"], log
  end

  def test_interrupt_in_a_step_closes_components_and_skips_after_hooks
    log = []
    pipeline = build_pipeline do
      source Component.new("source", log)
      map { raise Interrupt }
      after { log << "after" }
    end

    assert_raises(Interrupt) { Metacrunch::Engine.new(pipeline).run }
    assert_equal ["open source", "close source"], log
  end

  def test_interrupt_in_the_source_closes_the_sink
    log = []
    pipeline = build_pipeline do
      source(Enumerator.new { raise Interrupt })
      sink Component.new("sink", log)
    end

    assert_raises(Interrupt) { Metacrunch::Engine.new(pipeline).run }
    assert_equal ["open sink", "close sink"], log
  end

  def test_open_errors_abort_and_close_what_was_opened
    log = []
    result = run_pipeline do
      source Component.new("source", log)
      sink FailingOpen.new
    end

    assert_equal [:aborted, "open broke"], [result.status, result.error.message]
    assert_equal ["open source", "close source"], log
  end

  def test_close_errors_abort_the_run_after_closing_everything
    log = []
    result = run_pipeline do
      source Component.new("source", log)
      sink FailingClose.new
    end

    assert_equal [:aborted, "close broke"], [result.status, result.error.message]
    assert_equal ["open source", "close source"], log
  end

  def test_failing_after_hook_aborts_the_run
    seen = []
    result = run_pipeline do
      source [1]
      after { raise "report broke" }
      after { |res| seen << res.status }
    end

    assert_equal [:aborted, "report broke"], [result.status, result.error.message]
    assert_equal [:aborted], seen
  end

  def test_profile_records_time_per_step
    result = run_pipeline do
      source [1]
      map { it }
      profile true
    end

    assert_kind_of Float, result.stats.steps["map#1"].time
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `for f in test/unit/engine_error_policy_test.rb test/unit/engine_lifecycle_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: failures, e.g. `test_skip_continues_and_sends_failures_to_the_errors_sink` gets `:aborted` instead of `:ok_with_failures`, lifecycle tests see an empty log.

- [ ] **Step 3: Implement — replace `lib/metacrunch/engine.rb`**

```ruby
# frozen_string_literal: true

module Metacrunch

  # Passed to open(context) of sources, steps and sinks.
  OpenContext = Data.define(:params, :logger)

  # Runs a Pipeline: pushes every source record through the chain of steps
  # into the sink, applies the error policy and collects stats.
  class Engine

    def initialize(pipeline, executor: Executor::Inline.new, observer: nil)
      @pipeline = pipeline
      @executor = executor
      @observer = observer
    end

    def run
      @stats = StatsCollector.new(@pipeline.steps.map(&:name), profile: @pipeline.profile)
      @on_mark = @stats.method(:mark)
      error = execute
      run_after_hooks(Result.new(status: status_for(error), error:, stats: @stats.snapshot))
    end

    private

    def status_for(error)
      return :aborted if error
      return :ok_with_failures if @stats.failed_total.positive?

      :ok
    end

    # Returns the error that aborted the run, or nil. Opened components are
    # closed in any case, also while an Interrupt propagates.
    def execute
      opened = []
      error = nil
      begin
        process(opened)
      rescue StandardError => e
        error = e
      ensure
        close_error = close_components(opened)
      end
      error || close_error
    end

    def process(opened)
      open_components(opened)
      @pipeline.before_hooks.each(&:call)
      chain = build_chain
      @executor.run(@pipeline.source) { |record, position| ingest(chain, record, position) }
      sinks.each(&:flush)
    end

    def sinks
      [@pipeline.sink, @pipeline.rejects, @pipeline.errors].compact
    end

    # Source, step callables and sinks, in open order.
    def components
      [@pipeline.source, *@pipeline.steps.map(&:callable), *sinks].uniq(&:__id__)
    end

    def open_components(opened)
      context = OpenContext.new(params: @pipeline.params, logger: @pipeline.logger)
      components.each do |component|
        component.open(context) if component.respond_to?(:open)
        opened << component
      end
    end

    # Closes the opened components in reverse order and returns the first
    # error, after trying to close all of them.
    def close_components(opened)
      first_error = nil
      opened.reverse_each do |component|
        component.close if component.respond_to?(:close)
      rescue StandardError => e
        @pipeline.logger.error("closing #{component.class} failed: #{e.class}: #{e.message}")
        first_error ||= e
      end
      first_error
    end

    def run_after_hooks(result)
      @pipeline.after_hooks.each do |hook|
        hook.call(result)
      rescue StandardError => e
        @pipeline.logger.error("after hook failed: #{e.class}: #{e.message}")
        result = result.with(status: :aborted, error: result.error || e)
      end
      result
    end

    def ingest(chain, record, position)
      @stats.count_read
      id = @pipeline.id_extractor&.call(record)
      chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    def build_chain
      @pipeline.steps.reverse.reduce(method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain: runs the step and passes its outputs on. Only
    # the step itself is covered by the error policy; errors raised further
    # down (later steps, sinks) pass through.
    def link(step, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        @stats.step_in(step.name)
        @observer&.step_in(step.name, record, ctx)
        begin
          outputs = evaluate(step, record, ctx)
        rescue StandardError => e
          @observer&.step_out(step.name, [], ctx)
          next fail_record(step, record, ctx, e)
        end
        @observer&.step_out(step.name, outputs, ctx)
        forward(step, record, ctx, outputs, downstream)
      end
    end

    # Calls the step and returns its outputs as an Array. Raises
    # ContractError if the step breaks its contract.
    def evaluate(step, record, ctx)
      result = timed(step) { step.call(record, ctx) }
      return [] if ctx.rejected?

      case step.kind
      when :map then [map_result(step, result)]
      when :filter then kept(step, record, ctx, result)
      when :reject then kept(step, record, ctx, !result)
      else flat_map_result(step, result)
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
      return [record] if keep

      ctx.reject!(step.reason) if step.reason
      []
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_result(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      unless result.respond_to?(:each)
        raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
      end

      outputs = []
      result.each { |output| outputs << output }
      outputs
    end

    def forward(step, record, ctx, outputs, downstream)
      if ctx.rejected?
        reject_record(record, ctx)
      elsif step.kind == :flat_map
        @stats.step_out(step.name, outputs.size)
        outputs.each { |child| downstream.call(child, ctx.copy) }
      elsif outputs.empty?
        @stats.step_filtered(step.name)
      else
        @stats.step_out(step.name)
        downstream.call(outputs.first, ctx)
      end
    end

    def deliver(record, ctx)
      return unless @pipeline.sink

      @pipeline.sink.write(record, ctx)
      @stats.count_written
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @pipeline.rejects&.write(record, ctx)
    end

    def fail_record(step, record, ctx, error)
      @stats.step_failed(step.name, error)
      step_error = StepError.new(step: step.name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_error == :abort

      ctx.failure = Failure.new(error:, step: step.name)
      ctx.logger.error(step_error.message)
      @pipeline.errors&.write(record, ctx)
      check_max_errors(step_error)
    end

    def check_max_errors(step_error)
      max = @pipeline.max_errors
      return unless max && @stats.failed_total > max

      error = Error.new("#{@stats.failed_total} failed records exceed max_errors #{max}")
      raise error, cause: step_error
    end

  end

end
```

- [ ] **Step 4: Run all engine tests**

Run: `for f in test/unit/engine_test.rb test/unit/engine_error_policy_test.rb test/unit/engine_lifecycle_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: all `0 failures, 0 errors`.

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add error policy, lifecycle and hooks to the engine

on_error :skip sends failed records to the errors sink and continues;
max_errors stops it. Errors in sources, sinks, hooks, open and close
always abort. Components are opened in order and always closed in
reverse, also on Interrupt. after hooks receive the result.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 10: Jobs and job files

**Files:**
- Create: `lib/metacrunch/job.rb`, `lib/metacrunch/loader.rb`, `test/unit/job_test.rb`, `test/unit/loader_test.rb`, `test/fixtures/jobs/lazy.rb`, `test/fixtures/jobs/several.rb`, `test/fixtures/jobs/none.rb`, `test/fixtures/jobs/broken.rb`
- Modify: `lib/metacrunch.rb` (requires and `Metacrunch.job`/`Metacrunch.load_job`), `.rubocop.yml` (exclude `broken.rb`)

**Interfaces:**
- Consumes: `Builder`, `Engine`, `Params#bind_argv`.
- Produces:
  - `Metacrunch::Job.new(name = nil, &recipe)`; `#name` (String or nil); `#pipeline(binder:, logger: Metacrunch.logger) → Pipeline`; `#run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil) → Result` (raises `ParamError` for bad arguments); `#describe → Params`.
  - `Metacrunch::Loader.load(path, name: nil) → Job` (raises `JobLoadError`), `Metacrunch::Loader.register(job)`.
  - `Metacrunch.job(name = nil, &recipe) → Job`, `Metacrunch.load_job(path, name: nil) → Job`.

- [ ] **Step 1: Write the fixtures**

`test/fixtures/jobs/lazy.rb`:

```ruby
# frozen_string_literal: true

Metacrunch.job "lazy" do
  raise "the recipe must not run while the file is loaded"
end
```

`test/fixtures/jobs/several.rb`:

```ruby
# frozen_string_literal: true

Metacrunch.job("first") { source [] }
Metacrunch.job("second") { source [1] }
```

`test/fixtures/jobs/none.rb`:

```ruby
# frozen_string_literal: true

# This file defines no job.
```

`test/fixtures/jobs/broken.rb` (syntax error on purpose):

```ruby
# frozen_string_literal: true

Metacrunch.job do
```

`.rubocop.yml`: add the exclude, so the file reads:

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

inherit_mode:
  merge:
    - Exclude

AllCops:
  Exclude:
    # Contains a syntax error on purpose (loader tests).
    - "test/fixtures/jobs/broken.rb"

Style/FrozenStringLiteralComment:
  Enabled: true
```

- [ ] **Step 2: Write the failing tests**

`test/unit/job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class JobTest < Minitest::Test

  SILENT = Logger.new(nil)

  def test_run_binds_cli_arguments_and_returns_the_result
    target = CollectingSink.new
    job = Metacrunch.job do
      params do
        param :factor, Integer, default: 1
        args :numbers
      end
      source params.numbers.map(&:to_i)
      map { it * params.factor }
      sink target
    end
    result = job.run(["--factor", "3", "1", "2"], logger: SILENT)

    assert_equal :ok, result.status
    assert_equal [3, 6], target.records
  end

  def test_each_run_builds_a_fresh_pipeline
    built = 0
    job = Metacrunch.job do
      built += 1
      source []
    end
    2.times { job.run([], logger: SILENT) }

    assert_equal 2, built
  end

  def test_run_raises_param_errors
    job = Metacrunch.job do
      params { param :index, String, required: true }
      source []
    end

    assert_raises(Metacrunch::ParamError) { job.run([], env: {}, logger: SILENT) }
  end

  def test_describe_returns_the_params_without_building_components
    job = Metacrunch.job do
      params { param :index, String, required: true }
      source raise("must not be built")
    end

    assert_equal [:index], job.describe.definitions.keys
  end

  def test_a_job_needs_a_recipe
    assert_raises(ArgumentError) { Metacrunch::Job.new("empty") }
  end

end
```

`test/unit/loader_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class LoaderTest < Minitest::Test

  FIXTURES = File.expand_path("../fixtures/jobs", __dir__)

  # file, name => expected message
  ERRORS = {
    "missing_file" => ["missing.rb", nil, /job file not found/],
    "no_job" => ["none.rb", nil, /no job defined/],
    "several_jobs_without_name" => ["several.rb", nil, /defines several jobs \(first, second\)/],
    "unknown_name" => ["several.rb", "third", /no job named third .*available: first, second/],
    "syntax_error" => ["broken.rb", nil, /could not load .*broken\.rb: SyntaxError/]
  }.freeze

  def test_loads_the_only_job_without_evaluating_it
    assert_equal "lazy", Metacrunch.load_job(fixture("lazy.rb")).name
  end

  def test_selects_a_job_by_name
    assert_equal "second", Metacrunch.load_job(fixture("several.rb"), name: "second").name
  end

  def test_jobs_defined_outside_a_file_are_not_collected
    Metacrunch.job("inline") { source [] }

    assert_equal "lazy", Metacrunch.load_job(fixture("lazy.rb")).name
  end

  ERRORS.each do |description, (file, name, message)|
    define_method("test_load_error_#{description}") do
      error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_job(fixture(file), name:) }

      assert_match message, error.message
    end
  end

  private

  def fixture(file)
    File.join(FIXTURES, file)
  end

end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `for f in test/unit/job_test.rb test/unit/loader_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: `NoMethodError: undefined method 'job' for module Metacrunch`.

- [ ] **Step 4: Implement**

`lib/metacrunch/job.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # A job is a recipe: a block in the DSL. It builds a fresh Pipeline for
  # every run, so loading a job has no side effects.
  class Job

    attr_reader :name

    def initialize(name = nil, &recipe)
      raise ArgumentError, "a job needs a block" unless recipe

      @name = name&.to_s
      @recipe = recipe
    end

    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values.
    def pipeline(binder:, logger: Metacrunch.logger)
      builder = Builder.new(binder:, logger:)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments; everything else ends up in the Result.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil)
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:) }, logger:)
      Engine.new(built, observer:).run
    end

    # The declared parameters. Builds no source, step or sink.
    def describe
      builder = Builder.new(binder: nil, logger: Metacrunch.logger, describe: true)
      catch(Builder::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
```

`lib/metacrunch/loader.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Loads job files. Metacrunch.job registers each job with the load that
  # is in progress on the current thread.
  module Loader

    KEY = :metacrunch_loading_jobs

    module_function

    def load(path, name: nil)
      raise JobLoadError, "job file not found: #{path}" unless File.file?(path)

      select_job(collect(path), path, name&.to_s)
    end

    def register(job)
      Thread.current[KEY]&.push(job)
    end

    def collect(path)
      previous = Thread.current[KEY]
      jobs = Thread.current[KEY] = []
      Kernel.load(File.expand_path(path))
      jobs
    rescue ScriptError, StandardError => e
      raise JobLoadError, "could not load #{path}: #{e.class}: #{e.message}"
    ensure
      Thread.current[KEY] = previous
    end

    def select_job(jobs, path, name)
      raise JobLoadError, "no job defined in #{path}" if jobs.empty?
      return pick_named(jobs, path, name) if name
      return jobs.first if jobs.one?

      raise JobLoadError, "#{path} defines several jobs (#{names(jobs)}); select one with --job NAME"
    end

    def pick_named(jobs, path, name)
      jobs.find { |job| job.name == name } ||
        raise(JobLoadError, "no job named #{name} in #{path} (available: #{names(jobs)})")
    end

    def names(jobs)
      jobs.map { |job| job.name || "(unnamed)" }.join(", ")
    end

  end
end
```

`lib/metacrunch.rb` — the complete file after this task:

```ruby
# frozen_string_literal: true

require "logger"

require_relative "metacrunch/version"
require_relative "metacrunch/errors"
require_relative "metacrunch/record_logger"
require_relative "metacrunch/context"
require_relative "metacrunch/stats"
require_relative "metacrunch/stats_collector"
require_relative "metacrunch/result"
require_relative "metacrunch/callable"
require_relative "metacrunch/step"
require_relative "metacrunch/sink_adapter"
require_relative "metacrunch/params"
require_relative "metacrunch/pipeline"
require_relative "metacrunch/builder"
require_relative "metacrunch/executor/inline"
require_relative "metacrunch/engine"
require_relative "metacrunch/job"
require_relative "metacrunch/loader"

module Metacrunch

  LOG_FORMATTER = proc do |severity, time, _progname, message|
    "#{time.strftime("%H:%M:%S")} #{severity.ljust(5)} #{message}\n"
  end

  class << self

    attr_writer :logger

    # The default logger writes to stderr. Stdout is reserved for data.
    def logger
      @logger ||= build_logger($stderr)
    end

    def build_logger(io)
      Logger.new(io, level: Logger::INFO, formatter: LOG_FORMATTER)
    end

    # Defines a job. Inside a job file loaded with load_job, the job is
    # also registered with the loader.
    def job(name = nil, &recipe)
      Job.new(name, &recipe).tap { |job| Loader.register(job) }
    end

    def load_job(path, name: nil)
      Loader.load(path, name:)
    end

  end

end
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `for f in test/unit/job_test.rb test/unit/loader_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: all `0 failures, 0 errors`.

- [ ] **Step 6: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses (`broken.rb` is excluded).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add jobs and job file loading

Metacrunch.job defines a recipe; Job#run binds CLI arguments and builds
a fresh pipeline per run; Job#describe returns the parameters without
building components. Metacrunch.load_job loads a file and selects a job.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 11: Testing helper

**Files:**
- Create: `lib/metacrunch/testing.rb`, `test/unit/testing_test.rb`

**Interfaces:**
- Consumes: `Job#pipeline`, `Params#bind_hash`, `SinkAdapter`, `Engine`, `Pipeline#with`.
- Produces: `require "metacrunch/testing"`; `Metacrunch::Testing.run(job, params: {}, source: nil, logger: Logger.new(nil)) → Testing::Result`; `Metacrunch::Testing::Result = Data.define(:records, :rejects, :errors, :stats, :status, :error)` where `rejects` is `[[record, Rejection], ...]` and `errors` is `[[record, Failure], ...]`; `Metacrunch::Testing::MemorySink` (`#records`, `#contexts`, `#write(record, ctx)`).

- [ ] **Step 1: Write the failing tests**

`test/unit/testing_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class TestingTest < Minitest::Test

  # Fails if the job's own source or sinks are used.
  class Untouchable

    def each = raise("the job's source must not be read")

    def open(_context) = raise("the job's components must not be opened")

    def write(_record) = raise("the job's sinks must not be written")

  end

  def test_replaces_the_source_and_all_sinks
    result = Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1, 0, 9])

    assert_equal [:ok_with_failures, [1]], [result.status, result.records]
    assert_equal [[9, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] }
    assert_equal [[0, "zero"]], result.errors.map { |record, failure| [record, failure.error.message] }
  end

  def test_converts_string_params
    result = Metacrunch::Testing.run(build_job, params: {limit: "0"}, source: [1])

    assert_equal [[1, "Too large"]], result.rejects.map { |record, rejection| [record, rejection.reason] }
  end

  def test_uses_the_jobs_source_when_none_is_given
    job = Metacrunch.job { source [1, 2] }

    assert_equal [1, 2], Metacrunch::Testing.run(job).records
  end

  def test_rejects_a_source_without_each
    assert_raises(ArgumentError) { Metacrunch::Testing.run(build_job, source: 42) }
  end

  private

  def build_job
    Metacrunch.job do
      params { param :limit, Integer, default: 100 }
      source Untouchable.new
      reject("Too large") { it > params.limit }
      map { it.zero? ? raise(ArgumentError, "zero") : it }
      sink Untouchable.new
      rejects Untouchable.new
      errors Untouchable.new
      on_error :skip
    end
  end

end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/testing_test.rb`
Expected: `LoadError: cannot load such file -- metacrunch/testing`.

- [ ] **Step 3: Implement**

`lib/metacrunch/testing.rb`:

```ruby
# frozen_string_literal: true

require_relative "../metacrunch"

module Metacrunch
  # Runs jobs in tests without I/O: all sinks are replaced by in-memory
  # sinks, and the source can be replaced by any Enumerable.
  module Testing

    # Keeps records and their contexts.
    class MemorySink

      attr_reader :records, :contexts

      def initialize
        @records = []
        @contexts = []
      end

      def write(record, ctx)
        @records << record
        @contexts << ctx
      end

    end

    # records: what reached the sink. rejects: [record, Rejection] pairs.
    # errors: [record, Failure] pairs.
    Result = Data.define(:records, :rejects, :errors, :stats, :status, :error)

    module_function

    # params are bound like CLI values (strings are converted), without
    # environment lookup. The job's sinks are built but never opened.
    def run(job, params: {}, source: nil, logger: Logger.new(nil))
      unless source.nil? || source.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{source.inspect}"
      end

      pipeline = job.pipeline(binder: ->(schema) { schema.bind_hash(params) }, logger:)
      memory = {sink: MemorySink.new, rejects: MemorySink.new, errors: MemorySink.new}
      pipeline = pipeline.with(source: source || pipeline.source,
                               **memory.transform_values { |sink| SinkAdapter.new(sink) })
      result = Engine.new(pipeline).run
      Result.new(
        records: memory[:sink].records,
        rejects: memory[:rejects].records.zip(memory[:rejects].contexts.map(&:rejection)),
        errors: memory[:errors].records.zip(memory[:errors].contexts.map(&:failure)),
        stats: result.stats,
        status: result.status,
        error: result.error
      )
    end

  end
end
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/testing_test.rb`
Expected: `4 runs, ... 0 failures, 0 errors`.

- [ ] **Step 5: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add Metacrunch::Testing

Testing.run runs a job with in-memory sinks and an optional replacement
source, and returns records, rejects, errors, stats and status.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 12: Minimal CLI

**Files:**
- Create: `lib/metacrunch/cli.rb`, `exe/metacrunch`, `test/cli/cli_test.rb`, `test/cli/exe_test.rb`, `test/fixtures/jobs/numbers.rb`, `test/fixtures/jobs/lib/printing_sink.rb`, `test/fixtures/jobs/interrupted.rb`, `test/fixtures/jobs/broken_recipe.rb`

**Interfaces:**
- Consumes: `Metacrunch.load_job`, `Job#run`, `Job#describe`, `Params#help`, `Params#args_definition`, `Result#summary`, `Metacrunch.build_logger`.
- Produces: `require "metacrunch/cli"`; `Metacrunch::Cli.new(stdout: $stdout, stderr: $stderr, env: ENV)`, `#run(argv) → Integer` exit code; `Cli::EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3, interrupted: 130}`; executable `exe/metacrunch`.

- [ ] **Step 1: Write the fixtures**

`test/fixtures/jobs/lib/printing_sink.rb`:

```ruby
# frozen_string_literal: true

# Prints each record on stdout.
class PrintingSink

  def write(record)
    $stdout.puts(record)
  end

end
```

`test/fixtures/jobs/numbers.rb`:

```ruby
# frozen_string_literal: true

require_relative "lib/printing_sink"

# Multiplies numbers, rejects negative ones and fails on zero.
Metacrunch.job "numbers" do
  params do
    param :factor, Integer, default: 1, desc: "Multiplier"
    param :skip_errors, :bool, default: false, desc: "Skip records that fail"
    args :numbers, min: 1, desc: "Numbers to process"
  end

  source params.numbers.map { Integer(it) }

  reject("Negative", &:negative?)
  map { |number| number.zero? ? raise(ZeroDivisionError, "zero is not allowed") : number * params.factor }

  sink PrintingSink.new
  on_error :skip if params.skip_errors
end
```

`test/fixtures/jobs/interrupted.rb`:

```ruby
# frozen_string_literal: true

Metacrunch.job do
  source [1]
  map { raise Interrupt }
end
```

`test/fixtures/jobs/broken_recipe.rb`:

```ruby
# frozen_string_literal: true

Metacrunch.job do
  source UndefinedSource.new
end
```

- [ ] **Step 2: Write the failing tests**

`test/cli/cli_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/cli"

class CliTest < Minitest::Test

  JOBS = File.expand_path("../fixtures/jobs", __dir__)

  def test_prints_the_version
    assert_equal [0, "#{Metacrunch::VERSION}\n", ""], cli("-v")
  end

  def test_prints_the_usage
    code, stdout, = cli("--help")

    assert_equal 0, code
    assert_match(/Usage: metacrunch \[-h\|-v\] JOB_FILE/, stdout)
  end

  def test_usage_errors_exit_with_2
    assert_equal 2, cli.first
    assert_equal 2, cli(job("missing.rb")).first
    assert_equal 2, cli(job("numbers.rb"), "--factor", "x", "1").first
  end

  def test_usage_errors_are_explained_on_stderr
    _code, stdout, stderr = cli(job("numbers.rb"))

    assert_empty stdout
    assert_match(/Error: expected at least 1 argument\(s\) for numbers, got 0/, stderr)
  end

  def test_prints_job_help_without_running_the_job
    code, stdout, = cli(job("numbers.rb"), "--help")

    assert_equal 0, code
    assert_match(/--factor VALUE\s+Multiplier \(default: 1\)/, stdout)
    assert_match(/NUMBERS  Numbers to process  \(1 or more arguments\)/, stdout)
  end

  def test_help_for_a_job_without_params
    code, stdout, = cli(job("several.rb"), "--job", "first", "--help")

    assert_equal [0, "Usage: metacrunch #{job("several.rb")} [JOB_PARAMS...]\n\n"], [code, stdout]
  end

  def test_runs_the_job
    code, stdout, stderr = cli(job("numbers.rb"), "--factor", "3", "--", "1", "-2", "2")

    assert_equal [0, "3\n6\n"], [code, stdout]
    assert_match(/INFO  ok: read 3, written 2, rejected 1 \(Negative: 1\)/, stderr)
  end

  def test_failed_records_exit_with_1_or_3
    code, _stdout, stderr = cli(job("numbers.rb"), "0")

    assert_equal 1, code
    assert_match(/StepError: step map#2 failed at position 1: ZeroDivisionError: zero is not allowed/, stderr)
    assert_equal 3, cli(job("numbers.rb"), "--skip-errors", "0", "1").first
  end

  def test_selects_jobs_by_name
    assert_equal 0, cli(job("several.rb"), "--job", "second").first
    assert_equal 0, cli(job("several.rb"), "--job=first").first
    assert_match(/defines several jobs/, cli(job("several.rb"))[2])
  end

  def test_interrupt_exits_with_130
    code, _stdout, stderr = cli(job("interrupted.rb"))

    assert_equal 130, code
    assert_match(/WARN  interrupted/, stderr)
  end

  def test_unexpected_errors_exit_with_1
    code, _stdout, stderr = cli(job("broken_recipe.rb"))

    assert_equal 1, code
    assert_match(/NameError/, stderr)
  end

  private

  def job(name)
    File.join(JOBS, name)
  end

  def cli(*args)
    code = nil
    stdout, stderr = capture_io { code = Metacrunch::Cli.new(env: {}).run(args) }
    [code, stdout, stderr]
  end

end
```

`test/cli/exe_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  NUMBERS = File.join(ROOT, "test", "fixtures", "jobs", "numbers.rb")

  def test_prints_data_on_stdout_and_logs_on_stderr
    stdout, stderr, status = metacrunch(NUMBERS, "--factor", "2", "1", "2")

    assert_equal [0, "2\n4\n"], [status.exitstatus, stdout]
    assert_match(/INFO  ok: read 2, written 2/, stderr)
  end

  def test_exit_codes
    assert_equal 1, metacrunch(NUMBERS, "0").last.exitstatus
    assert_equal 3, metacrunch(NUMBERS, "--skip-errors", "0", "1").last.exitstatus
    assert_equal 2, metacrunch.last.exitstatus
  end

  private

  def metacrunch(*args)
    Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *args)
  end

end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `for f in test/cli/cli_test.rb test/cli/exe_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: `LoadError: cannot load such file -- metacrunch/cli`; the exe test fails with exit status 1 and "No such file" for `exe/metacrunch`.

- [ ] **Step 4: Implement**

`lib/metacrunch/cli.rb`:

```ruby
# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"

module Metacrunch
  # Minimal command line interface. Sub-project 2 replaces it with
  # subcommands.
  class Cli

    USAGE = "Usage: metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]"
    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3, interrupted: 130}.freeze
    HELP_OPTIONS = ["-h", "--help"].freeze

    def initialize(stdout: $stdout, stderr: $stderr, env: ENV)
      @stdout = stdout
      @stderr = stderr
      @env = env
      @logger = Metacrunch.build_logger(stderr)
    end

    # Runs the CLI and returns the exit code.
    def run(argv)
      argv = argv.dup
      action, parser = global_action(argv)
      return show(parser.help) if action == :help
      return show(VERSION) if action == :version

      run_job(argv)
    rescue OptionParser::ParseError, JobLoadError, ParamError => e
      usage_error(e.message)
    rescue Interrupt
      @logger.warn("interrupted")
      EXIT_CODES[:interrupted]
    rescue StandardError => e
      @logger.error(e.full_message(highlight: false))
      EXIT_CODES[:aborted]
    end

    private

    def run_job(argv)
      job_file = argv.shift
      return usage_error("no job file given") unless job_file

      job = Metacrunch.load_job(job_file, name: extract_job_name(argv))
      return show(job_help(job_file, job)) if help_requested?(argv)

      report(job.run(argv, env: @env, logger: @logger))
    end

    # Parses the options before JOB_FILE. Returns [action, parser].
    def global_action(argv)
      action = nil
      parser = OptionParser.new(USAGE) do |opts|
        opts.on("-h", "--help", "Show this help") { action = :help }
        opts.on("-v", "--version", "Show the version") { action = :version }
      end
      parser.order!(argv)
      [action, parser]
    end

    # Removes --job NAME or --job=NAME from argv and returns NAME.
    def extract_job_name(argv)
      index = options_part(argv).index { |arg| arg == "--job" || arg.start_with?("--job=") }
      return unless index

      option = argv.delete_at(index)
      return option.delete_prefix("--job=") if option.start_with?("--job=")

      argv.delete_at(index) || raise(ParamError, "--job needs a job name")
    end

    def help_requested?(argv)
      options_part(argv).intersect?(HELP_OPTIONS)
    end

    # The arguments before a "--" separator.
    def options_part(argv)
      argv.take_while { |arg| arg != "--" }
    end

    def job_help(job_file, job)
      schema = job.describe
      args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
      "Usage: metacrunch #{job_file} [JOB_PARAMS...]#{args}\n\n#{schema.help}"
    end

    def report(result)
      if result.error
        @logger.error("#{result.error.class}: #{result.error.message}")
        cause = result.error.cause
        @logger.error("caused by #{cause.class}: #{cause.message}") if cause
      end
      @logger.info(result.summary)
      EXIT_CODES.fetch(result.status)
    end

    def show(text)
      @stdout.puts(text)
      EXIT_CODES[:ok]
    end

    def usage_error(message)
      @stderr.puts("Error: #{message}", USAGE)
      EXIT_CODES[:usage]
    end

  end
end
```

`exe/metacrunch`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "metacrunch/cli"

exit Metacrunch::Cli.new.run(ARGV)
```

Run: `chmod +x exe/metacrunch`

- [ ] **Step 5: Run the tests to see them pass**

Run: `for f in test/cli/cli_test.rb test/cli/exe_test.rb; do bundle exec ruby -w -Ilib -Itest $f; done`
Expected: all `0 failures, 0 errors`.

- [ ] **Step 6: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, no offenses.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add the minimal CLI

metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]
runs a job, prints job help, logs to stderr and returns defined exit
codes (0 ok, 1 aborted, 2 usage, 3 ok with failures, 130 interrupted).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```

---

### Task 13: End-to-end job, Readme and changelog

Covers success criteria 1 and 2 of the spec with a job that uses the whole DSL, and documents 5.0.

**Files:**
- Create: `test/fixtures/jobs/catalog.rb`, `test/fixtures/jobs/lib/json_files.rb`, `test/fixtures/catalog.json`, `test/integration/catalog_job_test.rb`, `CHANGELOG.md`
- Rewrite: `Readme.md`

**Interfaces:**
- Consumes: `Metacrunch.load_job`, `Metacrunch::Testing.run`, `Metacrunch::Cli`, `exe/metacrunch`.
- Produces: no new library API.

- [ ] **Step 1: Write the fixtures**

`test/fixtures/jobs/lib/json_files.rb`:

```ruby
# frozen_string_literal: true

require "json"

# Source: reads a JSON file that contains an array of records.
class JsonArrayFile

  def initialize(path)
    @path = path
  end

  def each(&)
    JSON.parse(File.read(@path)).each(&)
  end

end

# Sink: writes one JSON document per line.
class JsonLinesFile

  def initialize(path)
    @path = path
  end

  def open(_context)
    @file = File.open(@path, "w")
  end

  def write_batch(records)
    records.each { |record| @file.puts(JSON.generate(record)) }
  end

  def write(record)
    write_batch([record])
  end

  def close
    @file&.close
  end

end
```

`test/fixtures/jobs/catalog.rb`:

```ruby
# frozen_string_literal: true

require_relative "lib/json_files"

# Example job that uses the whole DSL.
Metacrunch.job "catalog" do
  params do
    param :output, String, required: true, desc: "Directory for the output files"
    param :min_year, Integer, default: 1900, env: "CATALOG_MIN_YEAR", desc: "Oldest year to keep"
    args :input, min: 1, max: 1, desc: "JSON file with an array of records"
  end

  source JsonArrayFile.new(params.input.first), id: ->(record) { record["_id"] }

  reject("Not public") { !it["public"] }
  filter { it["year"].nil? || it["year"] >= params.min_year }
  map do |record, ctx|
    ctx.mark("No title") if record["title"].nil?
    {"id" => record["_id"], "title" => record["title"], "year" => record["year"], "isbns" => record.fetch("isbns")}
  end
  flat_map do |record|
    isbns = record.delete("isbns")
    isbns.empty? ? [record] : isbns.map { |isbn| record.merge("isbn" => isbn) }
  end

  sink JsonLinesFile.new(File.join(params.output, "records.jsonl")), batch: 2
  rejects JsonLinesFile.new(File.join(params.output, "rejects.jsonl"))
  errors JsonLinesFile.new(File.join(params.output, "errors.jsonl"))
  on_error :skip, max_errors: 5

  after { |result| logger.info("catalog finished: #{result.status}") }
end
```

`test/fixtures/catalog.json`:

```json
[
  {"_id": "1", "public": true, "title": "Ruby", "year": 2020, "isbns": ["978-1", "978-2"]},
  {"_id": "2", "public": false, "title": "Secret", "year": 2021, "isbns": []},
  {"_id": "3", "public": true, "title": "Old", "year": 1850, "isbns": []},
  {"_id": "4", "public": true, "title": null, "year": 2001, "isbns": []},
  {"_id": "5", "public": true, "title": "No ISBN field", "year": 2005}
]
```

Expected behaviour, derived by hand: record 1 fans out into two records (one per ISBN); record 2 is rejected ("Not public"); record 3 is filtered (1850 < 1900); record 4 is kept and marked ("No title"); record 5 fails with `KeyError` (no `isbns`). Written: 3. Status `:ok_with_failures`, exit code 3.

- [ ] **Step 2: Write the failing tests**

`test/integration/catalog_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"
require "metacrunch/cli"
require "metacrunch/testing"

class CatalogJobTest < Minitest::Test

  ROOT = File.expand_path("../..", __dir__)
  JOB = File.join(ROOT, "test", "fixtures", "jobs", "catalog.rb")
  INPUT = File.join(ROOT, "test", "fixtures", "catalog.json")

  EXPECTED_FILES = {
    "records.jsonl" => [
      {"id" => "1", "title" => "Ruby", "year" => 2020, "isbn" => "978-1"},
      {"id" => "1", "title" => "Ruby", "year" => 2020, "isbn" => "978-2"},
      {"id" => "4", "title" => nil, "year" => 2001}
    ],
    "rejects.jsonl" => [{"_id" => "2", "public" => false, "title" => "Secret", "year" => 2021, "isbns" => []}],
    "errors.jsonl" => [{"_id" => "5", "public" => true, "title" => "No ISBN field", "year" => 2005}]
  }.freeze

  SUMMARY = Regexp.new(Regexp.escape(
    "ok_with_failures: read 5, written 3, filtered 1, rejected 1 (Not public: 1), " \
    "marked 1 (No title: 1), failed 1 (KeyError: 1)"
  ))

  # Runs from a temporary working directory with a relative --output, so
  # the files must land in that directory (the CLI must not chdir).
  def test_runs_through_the_executable_relative_to_the_working_directory
    Dir.mktmpdir do |dir|
      exe = File.join(ROOT, "exe", "metacrunch")
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", File.join(ROOT, "lib"), exe, JOB, "--output", ".", INPUT, chdir: dir
      )

      assert_equal 3, status.exitstatus, stderr
      assert_equal EXPECTED_FILES, read_outputs(dir)
      assert_match SUMMARY, stderr
    end
  end

  def test_runs_in_tests_without_files
    records = JSON.parse(File.read(INPUT))
    result = Metacrunch::Testing.run(
      Metacrunch.load_job(JOB), params: {output: "unused", input: ["unused.json"]}, source: records
    )

    assert_equal [:ok_with_failures, EXPECTED_FILES["records.jsonl"]], [result.status, result.records]
    assert_equal [["2", "Not public"]], result.rejects.map { |record, rejection| [record["_id"], rejection.reason] }
    assert_equal [["5", "KeyError"]], result.errors.map { |record, failure| [record["_id"], failure.error.class.name] }
  end

  def test_min_year_can_come_from_the_environment
    Dir.mktmpdir do |dir|
      code = nil
      capture_io do
        cli = Metacrunch::Cli.new(env: {"CATALOG_MIN_YEAR" => "1800"})
        code = cli.run([JOB, "--output", dir, INPUT])
      end

      assert_equal 3, code
      assert_equal 4, File.readlines(File.join(dir, "records.jsonl")).size
    end
  end

  private

  def read_outputs(dir)
    ["records.jsonl", "rejects.jsonl", "errors.jsonl"].to_h do |name|
      [name, File.readlines(File.join(dir, name)).map { |line| JSON.parse(line) }]
    end
  end

end
```

- [ ] **Step 3: Run the tests**

Run: `bundle exec ruby -w -Ilib -Itest test/integration/catalog_job_test.rb`
Expected: all three pass. The library is complete at this point, so these tests confirm the end-to-end behaviour rather than drive new code. If one fails, the failure points to a gap in Tasks 2–12: fix it there with a unit test first, then re-run.

- [ ] **Step 4: Rewrite `Readme.md`**

````markdown
metacrunch
==========

[![CI](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml/badge.svg)](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml)

metacrunch is a small data processing and ETL (extract, transform, load) toolkit for Ruby. A job reads records
from a **source**, passes them through **steps** and writes the results to a **sink**.

> metacrunch 5 is a redesign. Jobs written for 4.x must be rewritten, see the [changelog](CHANGELOG.md).

Requires Ruby 4.0.

## Installation

```
$ gem install metacrunch --pre
```

## A first job

A job file is plain Ruby:

```ruby
# jobs/numbers.rb
class StdoutSink
  def write(record) = $stdout.puts(record)
end

Metacrunch.job "numbers" do
  params do
    param :factor, Integer, default: 2, desc: "Multiplier"
    args :numbers, min: 1, desc: "Numbers to process"
  end

  source params.numbers.map { Integer(it) }

  reject("Negative") { it.negative? }
  map { it * params.factor }

  sink StdoutSink.new
end
```

```
$ metacrunch jobs/numbers.rb --factor 3 -- 1 2 -5
3
6
```

Data goes to stdout, logs and the run summary go to stderr.

## Records

A record can be any Ruby object. Records that leave a job should be `Hash` objects with `String` keys, because
only those survive a JSON round trip. The engine neither copies nor freezes records: a step that emits the same
object several times must not change it in place afterwards.

## Sources

Any object with `#each` that yields records. Optional `#open(context)` and `#close`.

```ruby
source MySource.new(params.files), id: ->(record) { record["_id"] }
```

`id:` gives every record an id for logs and errors.

## Steps

| Step | The block returns | Effect |
|---|---|---|
| `map` | the new record (not `nil`) | 1:1 |
| `filter` | truthy to keep the record | 0..1 |
| `reject` | truthy to drop the record | 0..1 |
| `flat_map` | an Enumerable of records (not a Hash) | 0..n |

A step is a block or any object with `#call`, for example a class with `self.call`. Steps are named
`map#1`, `filter#2`, … or explicitly: `map Mab2Primo, name: "mab2primo"`.

`filter` and `reject` take an optional reason. Records dropped with a reason are *rejected*: they are counted
per reason and sent to the `rejects` sink. Without a reason they are *filtered*: counted, nothing else.

```ruby
reject("Patent") { it["type"] == "patent" }
```

## The record context

A step that takes a second parameter gets the record's context:

```ruby
map do |record, ctx|
  ctx.mark("No title") if record["title"].nil?
  ctx.reject!("Duplicate") if seen?(record)
  record
end
```

| Method | |
|---|---|
| `ctx.id`, `ctx.position`, `ctx.step` | Record id, position in the source, current step |
| `ctx.reject!(reason, value: nil)` | Stop this record; it goes to the `rejects` sink |
| `ctx.mark(reason, value: nil)`, `ctx.marks` | Non-fatal notes; the record continues |
| `ctx.store` | Hash for per-record data shared between steps |
| `ctx.logger` | Logger that prefixes messages with the record id |

`flat_map` gives every emitted record its own copy of the context.

## Sinks

Any object with `#write(record)`. Optional `#write_batch(records)`, `#open(context)` and `#close`. Sinks that
accept a second argument get the (read-only) context: `write(record, ctx)`, `write_batch(records, ctxs)`.

```ruby
sink    ElasticsearchSink.new(index: params.index), batch: 1000
rejects JsonLinesFile.new("rejects.jsonl")   # rejected records, ctx.rejection
errors  JsonLinesFile.new("errors.jsonl")    # failed records (on_error :skip), ctx.failure
```

With `batch:` the sink gets `write_batch` calls with up to that many records; the rest is written at the end.

## Errors

```ruby
on_error :abort                    # default: stop at the first failing record
on_error :skip, max_errors: 100    # log, send to the errors sink, continue; stop after 100 failures
```

Errors in sources, sinks, hooks, `open` and `close` always stop the job. Components are closed in any case.

## Hooks

```ruby
before { logger.info("starting") }
after  { |result| logger.info(result.summary) }
```

`result.status` is `:ok`, `:ok_with_failures` or `:aborted`; `result.stats` has the counts per step and reason.
`profile true` adds the time per step.

## Parameters

```ruby
params do
  param :index, String, required: true, desc: "Elasticsearch index"
  param :url,   String, default: "http://localhost:9200", env: "ES_URL"
  param :bulk,  Integer, default: 1000
  param :dry,   :bool, default: false
  param :tags,  Array
  args  :files, min: 1
end
```

`params` must be the first statement of a job. Values come from the command line, then the environment
variable (`env:`), then the default. Types: `String`, `Integer`, `Float`, `:bool`, `Array` (comma-separated).
Use the values with `params.index`.

## Running jobs

```
$ metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]
$ metacrunch jobs/mab2es.rb --help
```

`--job NAME` selects a job if the file defines several. Use `--` before arguments that start with `-`.
The CLI does not change the working directory: relative paths are relative to where you start it.

| Exit code | Meaning |
|---|---|
| 0 | ok |
| 1 | aborted |
| 2 | usage error (job file, parameters) |
| 3 | finished, but records failed (`on_error :skip`) |
| 130 | interrupted |

## Testing jobs

```ruby
require "metacrunch/testing"

result = Metacrunch::Testing.run(
  Metacrunch.load_job("jobs/mab2es.rb"),
  params: {index: "test", files: ["unused"]},
  source: [{"title" => "no id"}]
)

result.records   # what reached the sink
result.rejects   # [[record, rejection], ...]
result.errors    # [[record, failure], ...]
result.stats
result.status
```

All sinks are replaced by in-memory sinks; nothing is written. Component constructors should therefore be
cheap and free of side effects; do I/O in `open`, `each` and `write`.

## License

metacrunch is available under the [MIT license](License.txt).
````

- [ ] **Step 5: Write `CHANGELOG.md`**

```markdown
# Changelog

## 5.0.0 (unreleased)

A redesign. Jobs written for 4.x must be rewritten; see the Readme.

### Breaking changes

- Jobs are defined with `Metacrunch.job do ... end`. A job file is plain Ruby; `.rb` is the recommended extension.
- `transformation` is replaced by `map`, `filter`, `reject` and `flat_map`. Returning `nil` no longer drops a
  record, and returning an Enumerator no longer fans out.
- `destination` is now `sink`. A job has at most one sink.
- `buffer:` is replaced by `batch:` on the sink (`write_batch`).
- `pre_process`/`post_process` are replaced by `before`/`after` hooks and `open`/`close` on components.
- `options` is replaced by `params { param ...; args ... }`. `ARGV` is no longer used.
- The CLI no longer changes into the job's directory and returns defined exit codes.
- `Metacrunch::TestUtils` is replaced by `Metacrunch::Testing`.
- Requires Ruby 4.0. ActiveSupport and colorize are no longer dependencies.

### Added

- Per-record context with `reject!`, `mark`, `store` and a record logger.
- `rejects` and `errors` sinks.
- Error policy `on_error :abort | :skip` with `max_errors`.
- Run results with stats per step and reason; `profile` for step timing.
```

- [ ] **Step 6: Full suite and lint**

Run: `bundle exec rake`
Expected: all green, coverage ≥ 95 % lines and ≥ 90 % branches, no offenses. If SimpleCov reports a coverage below a threshold, open `coverage/index.html`, find the uncovered lines or branches in `lib/`, and add unit tests for them to the matching `test/unit/*_test.rb` (red first, then green) until the thresholds pass.

- [ ] **Step 7: Check the gem builds**

Run: `gem build metacrunch.gemspec && rm metacrunch-5.0.0.pre.gem`
Expected: `Successfully built RubyGem` without warnings.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -F - <<'EOF'
Add end-to-end job tests, Readme and changelog for 5.0

A fixture job uses the whole DSL and runs through the executable and
Metacrunch::Testing. The Readme and changelog describe metacrunch 5.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TDdBM8GN1hfMuFySdGbKeF
EOF
```
