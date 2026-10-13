# metacrunch-ng projects and commands (sub-project 7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A project declares its jobs and commands in a `Metacrunchfile`; `metacrunch NAME` runs them from anywhere in the project, and commands chain jobs and other commands with `invoke`.

**Architecture:** `Names` holds the name rules. `Command` is a recipe like `Job`: `CommandBuilder` evaluates `params { }` and `run { }` (sharing `RecipeParams` with the job `Builder`), `CommandScope` runs the body. `Loader` collects jobs and commands per file. `Project` finds and loads the `Metacrunchfile`, whose `Metacrunch.load_files` loads job and command files with per-file errors. `Invoker` holds the context of one call (environment, credentials options, logger, streams, progress), resolves names and paths, runs jobs like `metacrunch run` and command bodies, wraps errors as `InvokeError` and tracks the worst status. The CLI dispatches names through a shared `Cli::ProjectLookup` and runs everything through the `Invoker`; `Testing.invoke` swaps in a recording invoker. The engine does not change.

**Tech Stack:** Ruby 4.0, standard library (`pathname`, `fileutils`, `tmpdir`, `open3`), Minitest 6, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** `docs/superpowers/specs/2026-10-13-metacrunch-ng-commands-design.md` (builds on the specs of sub-projects 1, 2 and 6 in the same directory)

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version stays `5.0.0.pre`.
- Runtime dependency: `logger` only. No new gems.
- Library files are loaded with `require_relative` from `lib/metacrunch.rb`; CLI-only files from `lib/metacrunch/cli.rb`. `Invoker`, `Project` and `RunOptions` are library files, because `Project#invoke` and `Testing.invoke` work without the CLI.
- Every Ruby file starts with `# frozen_string_literal: true`, also test fixtures, the `Metacrunchfile` of the example and Ruby files that tests write.
- Names: one or more parts matching `[a-z0-9][a-z0-9_-]*`, separated by `:`. Reserved in projects: `run`, `check`, `trace`, `new`, `credentials`, `help`. The project file is `Metacrunchfile`.
- Exit codes: 0 ok, 1 aborted or an exception left a command's body, 2 usage (also unknown or duplicate names and project errors), 3 finished with failed records (for a command: an invoked job ended `:ok_with_failures`, or `:aborted` and the body went on), 128 + n for signal n.
- The library never calls `exit`. Commands never use `$stdin`, `$stdout` or `$stderr` directly; they use the streams and the `env` injected into `Metacrunch::Cli`. The CLI finds the project from `Dir.pwd` and never changes directory.
- Inline runs keep their cost: `bundle exec ruby -Ilib bench/executor.rb inline` stays within 5 % of about 64 ns per step and record.
- Lint: `bundle exec rubocop` is clean at the end of every task (`bundle exec rubocop -a` may fix layout). Metrics cops are disabled by ruby.yml.
- Style that ruby.yml enforces:
  - double quotes, also inside interpolation;
  - `{a: 1}` without spaces inside the braces;
  - `[:a, :b]` and `["a", "b"]` instead of `%i[]` and `%w[]`;
  - blank lines at the start and end of class and module bodies, except for pure namespaces;
  - lines of at most 120 characters;
  - at most 3 assertions per Minitest test, and a blank line before the first assertion;
  - `it` instead of `_1` in one-parameter blocks.
- Tests:
  - Single file: `bundle exec ruby -w -Ilib -Itest <file>`.
  - Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake` (about 15 s, 648 tests before this plan).
  - Minitest 6 has no `stub`; tests replace singleton methods with `Override#override` (`test/support/override.rb`).
  - Tests that need files use `in_tmpdir` and `write_file` from `CredentialsHelper` (`test/support/credentials_helper.rb`); `in_tmpdir` yields the real path (macOS links `/var` to `/private/var`).
  - In-process CLI tests that need a project change into it with `Dir.chdir(dir) { cli(...) }`, as the credentials tests do, and pass `env: {}` (the default of `cli`), so the developer's `~/.metacrunch/` is never read. Subprocess tests set `HOME` to a temporary directory and clear `METACRUNCH_ENV`, `METACRUNCH_CREDENTIALS` and `METACRUNCH_MASTER_KEY`.
  - Project files that tests write define no constants at the top level, except where a test checks exactly that.
- Examples, messages and docs stay generic: no internal names of a library or institution.
- Repo docs, code comments and commit messages are in English.
- Every commit message ends with this line:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

## Review Focus

These are inputs and conditions the spec implies but does not spell out, ordered by how likely they are to bite a user first. Each one has a test in the task named in brackets.

1. **`nil` in the arguments of `invoke`** (`invoke "a2c", "--index", params.index` with an optional parameter left unset): `to_s` would pass an empty string and bind it silently. `invoke` raises `ArgumentError` naming the argument. [Task 4]
2. **An invoked job without source while stdin is a terminal** (a command started by hand invokes a filter job): it must not wait for input. `invoke` raises `InvokeError` with the run's message ("job has no source and stdin is a terminal"). [Task 4]
3. **Ctrl-C during an invoked job** (SIGINT, not only SIGTERM): the chain ends with exit status 130, and nothing after the job runs. [Task 5]
4. **A file in the working directory with the same name as a project name** (`./note` next to the command `note`): the name wins, a file is used only for names the project lacks. [Tasks 4, 5]
5. **A project root with spaces or glob characters in its path** (`My Data [2026]/`): relative globs of `load_files` still match, because they are expanded below the root, not inside a pattern that contains it. [Task 3]

---

## File Structure

```
lib/metacrunch/names.rb                Names: syntax, reserved names, path rule, desc        Task 1
lib/metacrunch/job.rb                  desc:, name check                                    Task 1
lib/metacrunch/cli/new.rb              refuses file names that are no job names             Task 1
lib/metacrunch/recipe_params.rb        RecipeParams: params handling of recipes             Task 2
lib/metacrunch/builder.rb              includes RecipeParams                                Task 2
lib/metacrunch/command.rb              Command, Command::Prepared                           Task 2
lib/metacrunch/command_builder.rb      CommandBuilder: params, run                          Task 2
lib/metacrunch/command_scope.rb        CommandScope: params, logger, invoke, root           Task 2
lib/metacrunch/loader.rb               jobs and commands, kind:, messages                   Task 2
lib/metacrunch/errors.rb               ProjectError (Task 3), InvokeError (Task 4)          Tasks 3, 4
lib/metacrunch/project.rb              Project: find, load, load_files, fetch, invoke       Tasks 3, 4
lib/metacrunch/run_options.rb          RunOptions, moved from cli/                          Task 4
lib/metacrunch/invoker.rb              Invoker                                              Task 4
lib/metacrunch.rb                      requires; job(desc:), command, load_files,           Tasks 1-4
                                       load_project
lib/metacrunch/cli/project_lookup.rb   Cli::ProjectLookup                                   Task 5
lib/metacrunch/cli.rb                  dispatch of names, help, project lists               Task 5
lib/metacrunch/cli/command.rb          lookup, ProjectError                                 Task 5
lib/metacrunch/cli/job_command.rb      NAME|FILE through the Invoker, help with desc        Task 5
lib/metacrunch/cli/run.rb              commands, job options, run through the Invoker       Task 5
lib/metacrunch/cli/check.rb, trace.rb  @target, constructor                                 Task 5
lib/metacrunch/testing.rb              Testing.invoke, RecordingInvoker                     Task 6
test/fixtures/jobs/mixed.rb, greet.rb  a job and a command; a command                       Task 2
examples/project/                      Metacrunchfile, job, command, data, test             Task 8
Readme.md, CHANGELOG.md, examples/Readme.md                                                 Tasks 8, 9
```

---
### Task 1: Names and descriptions of jobs

**Files:**
- Create: `lib/metacrunch/names.rb`
- Modify: `lib/metacrunch.rb` (require, `job(name = nil, desc: nil, &)`)
- Modify: `lib/metacrunch/job.rb` (name check, `desc`)
- Modify: `lib/metacrunch/cli/new.rb` (refuse invalid names)
- Test: `test/unit/names_test.rb`, `test/unit/job_test.rb`, `test/cli/new_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Metacrunch::Names::PATTERN` (Regexp), `Names::RESERVED` (Array of Strings)
  - `Names.valid?(name) -> Boolean` (only Strings are valid)
  - `Names.check!(name, kind) -> String` (name: String or Symbol; kind: "job" or "command"; raises `ArgumentError`)
  - `Names.check_desc!(desc) -> String | nil` (raises `ArgumentError` for anything but nil or one line)
  - `Names.reserved?(name) -> Boolean`
  - `Names.path?(argument) -> Boolean` (contains `/` or `.`)
  - `Job.new(name = nil, desc: nil, &recipe)`, `Job#desc`
  - `Metacrunch.job(name = nil, desc: nil, &recipe) -> Job`

- [ ] **Step 1: Write the failing tests for Names**

`test/unit/names_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class NamesTest < Minitest::Test

  Names = Metacrunch::Names

  VALID = ["a2c", "catalog:reindex", "es:create-index", "marc_to_json", "2go", "a:b:c"].freeze
  INVALID = ["", "A2c", "-a", "_a", "a:", ":a", "a::b", "a b", "a.b", "a/b", "ä", "a:-b"].freeze

  def test_accepts_valid_names
    assert_equal(VALID, VALID.map { Names.check!(it, "job") })
  end

  def test_rejects_invalid_names
    rejected = INVALID.select do |name|
      Names.check!(name, "job")
      false
    rescue ArgumentError
      true
    end

    assert_equal INVALID, rejected
  end

  def test_symbols_are_names_too
    assert_equal "a2c", Names.check!(:a2c, "job")
  end

  def test_the_message_names_the_kind_and_the_rule
    error = assert_raises(ArgumentError) { Names.check!("Catalog", "command") }

    assert_equal "invalid command name \"Catalog\": use a-z, 0-9, _ and -, in parts separated by :", error.message
  end

  def test_other_objects_are_no_names
    assert_raises(ArgumentError) { Names.check!(42, "job") }
  end

  def test_valid_takes_strings_only
    assert_equal([true, false, false], ["es:create-index", "Es", :a2c].map { Names.valid?(it) })
  end

  def test_reserved_names_are_the_builtin_commands
    assert_equal [*Metacrunch::Cli::COMMANDS.keys, "help"].sort, Names::RESERVED.sort
    assert Names.reserved?("run")
    refute Names.reserved?("catalog")
  end

  def test_paths_contain_a_slash_or_a_dot
    assert_equal([true, true, true, false], ["jobs/a2c", "a2c.rb", "./a2c", "a2c"].map { Names.path?(it) })
  end

  def test_descriptions_are_one_line_or_nil
    assert_equal "Load the catalog", Names.check_desc!("Load the catalog")
    assert_nil Names.check_desc!(nil)
    assert_raises(ArgumentError) { Names.check_desc!("two\nlines") }
  end

  def test_descriptions_are_strings
    error = assert_raises(ArgumentError) { Names.check_desc!(:catalog) }

    assert_equal "desc must be one line of text, got :catalog", error.message
  end

end
```

`Metacrunch::Cli` is loaded in every test: `test/support/cli_helper.rb` requires `metacrunch/cli`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/names_test.rb`
Expected: FAIL with `NameError: uninitialized constant Metacrunch::Names`

- [ ] **Step 3: Write Names**

`lib/metacrunch/names.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Names of jobs and commands, and their descriptions. A name is one or
  # more parts of a-z, 0-9, _ and -, separated by ":" ("a2c",
  # "es:create-index"). In a project, jobs, commands and the built-in
  # commands share one namespace.
  module Names

    PATTERN = /\A[a-z0-9][a-z0-9_-]*(?::[a-z0-9][a-z0-9_-]*)*\z/
    # The built-in commands of the CLI.
    RESERVED = ["run", "check", "trace", "new", "credentials", "help"].freeze

    module_function

    def valid?(name) = name.is_a?(String) && PATTERN.match?(name)

    # The name as a String; kind ("job", "command") is for the message.
    # Raises ArgumentError for anything but a valid String or Symbol.
    def check!(name, kind)
      text = name.to_s if name.is_a?(String) || name.is_a?(Symbol)
      return text if valid?(text)

      raise ArgumentError, "invalid #{kind} name #{name.inspect}: use a-z, 0-9, _ and -, in parts separated by :"
    end

    # A description for the list in `metacrunch --help`: nil or one line.
    def check_desc!(desc)
      return desc if desc.nil? || (desc.is_a?(String) && !desc.match?(/[\r\n]/))

      raise ArgumentError, "desc must be one line of text, got #{desc.inspect}"
    end

    def reserved?(name) = RESERVED.include?(name)

    # True if argument is a path: it contains / or ., which no name does.
    def path?(argument) = argument.include?("/") || argument.include?(".")

  end
end
```

In `lib/metacrunch.rb`, add the require before `require_relative "metacrunch/params"`:

```ruby
require_relative "metacrunch/names"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/names_test.rb`
Expected: PASS (10 runs)

- [ ] **Step 5: Write the failing tests for jobs**

Add to `test/unit/job_test.rb`, before `private` or, as the file has none, before the final `end` of the class:

```ruby
  def test_names_follow_the_name_rules
    error = assert_raises(ArgumentError) { Metacrunch.job("Catalog") { source [] } }

    assert_match(/invalid job name "Catalog"/, error.message)
  end

  def test_jobs_have_a_description
    job = Metacrunch.job("catalog", desc: "Export the catalog") { source [] }

    assert_equal ["catalog", "Export the catalog"], [job.name, job.desc]
  end

  def test_jobs_may_stay_unnamed
    job = Metacrunch.job { source [] }

    assert_nil job.name
    assert_nil job.desc
  end
```

Add to `test/cli/new_test.rb`, after `test_a_directory_is_not_a_job_path`:

```ruby
  def test_refuses_file_names_that_are_no_job_names
    in_tmpdir do
      code, _stdout, stderr = cli("new", "jobs/MyJob.rb")

      assert_equal 2, code
      assert_match(/MyJob\.rb: "MyJob" is not a valid job name; use a-z, 0-9, _ and -/, stderr)
      refute_path_exists "jobs/MyJob.rb"
    end
  end
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/job_test.rb test/cli/new_test.rb`
Expected: FAIL: `test_names_follow_the_name_rules` (no error raised), `test_jobs_have_a_description` (`ArgumentError: unknown keyword: :desc`), `test_jobs_may_stay_unnamed` (`NoMethodError: undefined method 'desc'`), `test_refuses_file_names_that_are_no_job_names` (exit code 0)

- [ ] **Step 7: Implement desc and the name check**

In `lib/metacrunch/job.rb`, replace `attr_reader :name` and `initialize`:

```ruby
    attr_reader :name, :desc

    # The file the job was loaded from (Metacrunch.load_job), else nil.
    # Credentials are searched from there.
    attr_accessor :file

    # name: see Names; nil for a job that runs by path only. desc: one line
    # for the list in `metacrunch --help`.
    def initialize(name = nil, desc: nil, &recipe)
      raise ArgumentError, "a job needs a block" unless recipe

      @name = name.nil? ? nil : Names.check!(name, "job")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end
```

(The `attr_accessor :file` block with its comment stays as it is; it is shown for its position.)

In `lib/metacrunch.rb`, replace `job`:

```ruby
    # Defines a job. Inside a file that Loader loads, the job is also
    # registered with the loader.
    def job(name = nil, desc: nil, &)
      Job.new(name, desc:, &).tap { |job| Loader.register(job) }
    end
```

In `lib/metacrunch/cli/new.rb`, replace the lines from `path = "#{path}.rb" unless path.end_with?(".rb")` to `write(files(path, File.basename(path, ".rb")))` in `execute`:

```ruby
        path = "#{path}.rb" unless path.end_with?(".rb")
        name = File.basename(path, ".rb")
        unless Names.valid?(name)
          raise UsageError, "#{File.basename(path)}: #{name.inspect} is not a valid job name; use a-z, 0-9, _ and -"
        end

        write(files(path, name))
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/names_test.rb test/unit/job_test.rb test/cli/new_test.rb`
Expected: PASS

- [ ] **Step 9: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass (every job name in the repository is valid), coverage above the thresholds, RuboCop clean.

- [ ] **Step 10: Commit**

```bash
git add lib/metacrunch/names.rb lib/metacrunch.rb lib/metacrunch/job.rb lib/metacrunch/cli/new.rb \
        test/unit/names_test.rb test/unit/job_test.rb test/cli/new_test.rb
git commit -m "$(cat <<'EOF'
Check the names of jobs and give jobs a description

Names are parts of a-z, 0-9, _ and -, separated by ":"; Metacrunch.job
raises for any other name. desc: is one line for the project's help list.
metacrunch new refuses file names that would give an invalid job name.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 2: Commands and their recipes

**Files:**
- Create: `lib/metacrunch/recipe_params.rb`
- Modify: `lib/metacrunch/builder.rb` (include `RecipeParams`)
- Create: `lib/metacrunch/command.rb`, `lib/metacrunch/command_builder.rb`, `lib/metacrunch/command_scope.rb`
- Modify: `lib/metacrunch/loader.rb` (jobs and commands, `kind:`, messages)
- Modify: `lib/metacrunch.rb` (requires, `command`, `load_job` with `kind: Job`)
- Create: `test/fixtures/jobs/mixed.rb`, `test/fixtures/jobs/greet.rb`
- Test: `test/unit/command_test.rb`, `test/unit/loader_test.rb`

**Interfaces:**
- Consumes: `Names.check!`, `Names.check_desc!` (Task 1).
- Produces:
  - `Metacrunch::RecipeParams::DESCRIBED` (the throw tag; `Builder::DESCRIBED` resolves to it too)
  - `Metacrunch::Command.new(name, desc: nil, &recipe)`; `#name`, `#desc`, `#file` (accessor, set by `Loader`), `#prepare(binder:) -> Command::Prepared`, `#describe -> Params`
  - `Command::Prepared = Data.define(:params, :body)` (`params`: bound values, `body`: the `run` block)
  - `Metacrunch::CommandBuilder.new(binder:, describe: false)`; `#params`, `#run`, `#build -> Command::Prepared`
  - `Metacrunch::CommandScope.new(params:, logger:, invoker:)`; `#params`, `#logger`, `#invoke(target, *argv, workers: nil, limit: nil)`, `#root` (both delegate to `invoker.invoke` and `invoker.root`)
  - `Metacrunch.command(name, desc: nil, &recipe) -> Command`
  - `Loader.load(path, name: nil, kind: nil) -> Job | Command` (`kind`: `Job` or `Command`); `Loader.cached(path) -> Array` (what the file declares, by mtime); `Loader.collect(path) -> Array` (loads now, sets `file`); `Loader.register(declaration)`
  - `Metacrunch.load_job(path, name: nil)` considers jobs only.
  - Fixtures: `mixed.rb` declares job `export` and command `publish`; `greet.rb` declares command `greet` with `--name` (default "world") that logs `hello, NAME`.

- [ ] **Step 1: Write the failing tests for commands**

`test/unit/command_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "pathname"

class CommandTest < Minitest::Test

  # Stands in for the Invoker: records invokes and has a root.
  class FakeInvoker

    attr_reader :calls

    def initialize
      @calls = []
    end

    def invoke(target, *argv, workers: nil, limit: nil)
      @calls << [target, argv, {workers:, limit:}.compact]
      :invoked
    end

    def root = Pathname("/srv/data")

  end

  def test_prepare_binds_the_params_and_the_body_uses_them
    command = Metacrunch.command("greet") do
      params { param :name, String, default: "Ada" }
      run { "Hello, #{params.name}!" }
    end

    assert_equal "Hello, Grace!", call(command, ["--name", "Grace"])
  end

  def test_next_ends_the_body_with_a_value
    command = Metacrunch.command("probe") do
      params { param :skip, :bool, default: false }
      run do
        next :skipped if params.skip

        :done
      end
    end

    assert_equal [:skipped, :done], [call(command, ["--skip"]), call(command, [])]
  end

  def test_the_body_invokes_through_the_invoker_and_knows_the_root
    invoker = FakeInvoker.new
    command = Metacrunch.command("chain") do
      run do
        invoke "a2c", "--index", "test", workers: 2
        root.join("etc")
      end
    end
    value = call(command, [], invoker:)

    assert_equal [["a2c", ["--index", "test"], {workers: 2}]], invoker.calls
    assert_equal Pathname("/srv/data/etc"), value
  end

  def test_the_body_gets_the_logger
    logger = Logger.new(nil)
    command = Metacrunch.command("log") { run { logger } }

    assert_same logger, call(command, [], logger:)
  end

  def test_describe_never_runs_the_body
    ran = []
    command = Metacrunch.command("noparams") { run { ran << :body } }
    schema = command.describe

    assert_empty schema.definitions
    assert_empty ran
  end

  def test_describe_returns_the_declared_params
    command = Metacrunch.command("es:create-index") do
      params do
        param :url, String
        args :index, min: 1, max: 1
      end
      run { raise "must not run" }
    end

    assert_equal [:url], command.describe.definitions.keys
  end

  def test_a_command_needs_a_run_block
    command = Metacrunch.command("empty") { params { param :x, String } }
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "a command needs run { ... }", error.message
  end

  def test_a_command_has_one_run_block
    command = Metacrunch.command("twice") do
      run { 1 }
      run { 2 }
    end
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "run is declared twice; a command has one body", error.message
  end

  def test_run_needs_a_block
    command = Metacrunch.command("blockless") { run }

    assert_raises(ArgumentError) { prepare(command, []) }
  end

  def test_params_must_come_first
    command = Metacrunch.command("late") do
      run { nil }
      params { param :x, String }
    end
    error = assert_raises(ArgumentError) { prepare(command, []) }

    assert_equal "params { ... } must be the first statement of a command", error.message
  end

  def test_invalid_arguments_raise_param_errors
    command = Metacrunch.command("strict") do
      params { param :index, String, required: true }
      run { nil }
    end

    assert_raises(Metacrunch::ParamError) { prepare(command, []) }
  end

  def test_a_command_needs_a_valid_name_and_a_block
    assert_raises(ArgumentError) { Metacrunch.command(nil) { run { nil } } }
    assert_raises(ArgumentError) { Metacrunch::Command.new("nameless") }
  end

  def test_commands_have_a_description
    command = Metacrunch.command("es:create-index", desc: "Create an index") { run { nil } }

    assert_equal ["es:create-index", "Create an index", nil], [command.name, command.desc, command.file]
  end

  private

  def prepare(command, argv)
    command.prepare(binder: ->(schema) { schema.bind_argv(argv, env: {}) })
  end

  def call(command, argv, invoker: FakeInvoker.new, logger: Logger.new(nil))
    prepared = prepare(command, argv)
    scope = Metacrunch::CommandScope.new(params: prepared.params, logger:, invoker:)
    scope.instance_exec(&prepared.body)
  end

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/command_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'command' for module Metacrunch`

- [ ] **Step 3: Extract RecipeParams from Builder**

`lib/metacrunch/recipe_params.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # The parameters of a recipe, for Builder (jobs) and CommandBuilder
  # (commands). `params { ... }` declares them as the first statement and
  # binds them, `params` returns the bound values. Includers call
  # init_params in initialize, use! in every other statement and
  # ensure_params_bound before they build, and define recipe_kind.
  module RecipeParams

    # Thrown in describe mode with the Params schema as soon as it is known.
    DESCRIBED = :metacrunch_described

    # With a block: declares the parameters (must be the first statement).
    # Without a block: returns the bound values.
    def params(&declaration)
      return bound_params unless declaration
      raise ArgumentError, "params { ... } must be the first statement of a #{recipe_kind}" if @used || @schema

      @schema = Params.new
      @schema.instance_exec(&declaration)
      bind_schema
    end

    private

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    def init_params(binder, describe)
      @binder = binder
      @describe = describe
      @schema = nil
      @values = nil
      @used = false
    end

    def bound_params
      use!
      @values
    end

    # Every statement calls this. In describe mode the first statement ends
    # the evaluation; otherwise recipes without params get an empty schema.
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

  end
end
```

In `lib/metacrunch/builder.rb`:

1. Replace the class head up to the end of `initialize`:

```ruby
  # Evaluates a job recipe with instance_exec and collects what the DSL
  # declares. #build returns the Pipeline.
  class Builder

    include RecipeParams

    ON_ERROR_POLICIES = [:abort, :skip].freeze

    attr_reader :logger

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    def initialize(binder:, logger:, describe: false)
      init_params(binder, describe)
      @logger = logger
      @source = nil
      @source_declared = false
      @id_extractor = nil
      @steps = []
      @sinks = {}
      @on_error = :abort
      @max_errors = nil
      @profile = false
      @before_hooks = []
      @after_hooks = []
    end
```

2. Delete the public method `params` (with its two comment lines) and the private methods `bound_params`, `use!` (with its comment), `ensure_params_bound` and `bind_schema`; they now come from `RecipeParams`.

3. Add as the first private method, right after `private`:

```ruby
    def recipe_kind = "job"
```

`Builder::DESCRIBED` keeps working (`Job#describe` uses it): a constant lookup through a class also searches the modules it includes.

In `lib/metacrunch.rb`, add before `require_relative "metacrunch/builder"`:

```ruby
require_relative "metacrunch/recipe_params"
```

Run: `bundle exec ruby -w -Ilib -Itest test/unit/builder_test.rb`
Expected: PASS (the refactoring changes no behavior)

- [ ] **Step 4: Write Command, CommandBuilder and CommandScope**

`lib/metacrunch/command.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # A command: a named recipe that declares parameters and a body,
  # `run { ... }`. Evaluating the recipe binds the parameters; the body
  # runs afterwards on a CommandScope (see Invoker#call).
  class Command

    # The bound parameters and the body of an evaluated recipe.
    Prepared = Data.define(:params, :body)

    attr_reader :name, :desc

    # The file the command was loaded from, else nil. Set by Loader.
    attr_accessor :file

    # name: see Names. desc: one line for the list in `metacrunch --help`.
    def initialize(name, desc: nil, &recipe)
      raise ArgumentError, "a command needs a block" unless recipe

      @name = Names.check!(name, "command")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end

    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values. Raises ParamError for invalid arguments and
    # ArgumentError for a recipe without or with two run blocks.
    def prepare(binder:)
      builder = CommandBuilder.new(binder:)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # The declared parameters. Evaluates the recipe only up to its first
    # statement, so the body never runs.
    def describe
      builder = CommandBuilder.new(binder: nil, describe: true)
      catch(RecipeParams::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
```

`lib/metacrunch/command_builder.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Evaluates a command recipe with instance_exec: params { ... } declares
  # the parameters (first statement), run { ... } the body (exactly one).
  # #build returns a Command::Prepared.
  class CommandBuilder

    include RecipeParams

    def initialize(binder:, describe: false)
      init_params(binder, describe)
      @body = nil
    end

    def run(&body)
      use!
      raise ArgumentError, "run needs a block" unless body
      raise ArgumentError, "run is declared twice; a command has one body" if @body

      @body = body
      nil
    end

    def build
      ensure_params_bound
      raise ArgumentError, "a command needs run { ... }" unless @body

      Command::Prepared.new(params: @values, body: @body)
    end

    private

    def recipe_kind = "command"

  end
end
```

`lib/metacrunch/command_scope.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # The receiver of a command's body (run { ... }): the bound params, the
  # logger, invoke and root. invoker is the Invoker of the call.
  class CommandScope

    attr_reader :params, :logger

    def initialize(params:, logger:, invoker:)
      @params = params
      @logger = logger
      @invoker = invoker
    end

    # Runs a job or command by name or path, with arguments as on the
    # command line; see Invoker#invoke.
    def invoke(target, *argv, workers: nil, limit: nil) = @invoker.invoke(target, *argv, workers:, limit:)

    # The root of the current project, a Pathname. Raises ProjectError
    # without project.
    def root = @invoker.root

  end
end
```

In `lib/metacrunch.rb`, add after `require_relative "metacrunch/job"`:

```ruby
require_relative "metacrunch/command"
require_relative "metacrunch/command_builder"
require_relative "metacrunch/command_scope"
```

and add after `job`:

```ruby
    # Defines a command. Like job, it is registered with the loader inside
    # a file that Loader loads.
    def command(name, desc: nil, &)
      Command.new(name, desc:, &).tap { |command| Loader.register(command) }
    end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/command_test.rb`
Expected: PASS (13 runs)

- [ ] **Step 6: Write the failing loader tests and fixtures**

`test/fixtures/jobs/mixed.rb`:

```ruby
# frozen_string_literal: true

# A job and a command in one file; -j selects one.
Metacrunch.job("export", desc: "Export the numbers") { source [1] }
Metacrunch.command("publish", desc: "Publish the export") { run { :published } }
```

`test/fixtures/jobs/greet.rb`:

```ruby
# frozen_string_literal: true

# A command, run by path.
Metacrunch.command "greet", desc: "Log a greeting" do
  params do
    param :name, String, default: "world", desc: "Who to greet"
  end

  run { logger.info("hello, #{params.name}") }
end
```

In `test/unit/loader_test.rb`, change the `"missing_file"` entry of `ERRORS`:

```ruby
    "missing_file" => ["missing.rb", nil, /file not found: .*missing\.rb/],
```

and add these tests after `test_loads_a_file_once_until_it_changes`:

```ruby
  def test_collects_jobs_and_commands_with_their_file
    declarations = Metacrunch::Loader.cached(fixture("mixed.rb"))

    assert_equal [Metacrunch::Job, Metacrunch::Command], declarations.map(&:class)
    assert_equal [fixture("mixed.rb")] * 2, declarations.map(&:file)
  end

  def test_selects_a_command_by_name
    assert_equal "publish", Metacrunch::Loader.load(fixture("mixed.rb"), name: "publish").name
  end

  def test_load_job_considers_jobs_only
    assert_equal "export", Metacrunch.load_job(fixture("mixed.rb")).name
  end

  def test_a_file_with_only_commands_defines_no_job
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_job(fixture("greet.rb")) }

    assert_match(/no job defined in .*greet\.rb/, error.message)
  end

  def test_several_jobs_and_commands_need_a_selection
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch::Loader.load(fixture("mixed.rb")) }

    assert_match(/defines several jobs and commands \(export, publish\); select one with --job NAME/, error.message)
  end

  def test_unknown_names_list_jobs_and_commands
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch::Loader.load(fixture("mixed.rb"), name: "x") }

    assert_match(/no job or command named x in .*available: export, publish/, error.message)
  end

  def test_kind_restricts_the_selection
    error = assert_raises(Metacrunch::JobLoadError) do
      Metacrunch::Loader.load(fixture("mixed.rb"), name: "export", kind: Metacrunch::Command)
    end

    assert_match(/no command named export in .*available: publish/, error.message)
  end
```

- [ ] **Step 7: Run the loader tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/loader_test.rb`
Expected: FAIL: `NoMethodError: undefined method 'cached'`, `JobLoadError: mixed.rb defines several jobs (export, publish)` where a command was selected, and the messages of the new tests.

- [ ] **Step 8: Teach Loader about commands**

Replace `lib/metacrunch/loader.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Loads files that declare jobs and commands. Metacrunch.job and
  # Metacrunch.command register what they declare with the load that is in
  # progress on the current thread. A file is loaded again only when it has
  # changed, because loading it twice would redefine its constants.
  module Loader

    KEY = :metacrunch_loading
    KINDS = {Job => "job", Command => "command"}.freeze

    @cache = {}

    module_function

    # The job or command that path declares. name selects one of several;
    # kind (Job or Command) considers only those.
    def load(path, name: nil, kind: nil)
      raise JobLoadError, "file not found: #{path}" unless File.file?(path)

      declarations = cached(path)
      declarations = declarations.grep(kind) if kind
      select_declaration(declarations, path, name&.to_s, kind ? KINDS.fetch(kind) : "job or command")
    end

    # What path declares, loaded again only when the file has changed.
    def cached(path)
      key = File.expand_path(path)
      mtime = File.mtime(key)
      cached_mtime, declarations = @cache[key]
      return declarations if cached_mtime == mtime

      declarations = collect(path)
      @cache[key] = [mtime, declarations]
      declarations
    end

    def register(declaration)
      Thread.current[KEY]&.push(declaration)
    end

    # Loads path now and returns what it declares, each with its file.
    def collect(path)
      previous = Thread.current[KEY]
      declarations = Thread.current[KEY] = []
      Kernel.load(File.expand_path(path))
      declarations.each { it.file = File.expand_path(path) }
    rescue ScriptError, StandardError => e
      raise JobLoadError, "could not load #{path}: #{e.class}: #{e.message}"
    ensure
      Thread.current[KEY] = previous
    end

    def select_declaration(declarations, path, name, noun)
      raise JobLoadError, "no #{noun} defined in #{path}" if declarations.empty?
      return pick_named(declarations, path, name, noun) if name
      return declarations.first if declarations.one?

      raise JobLoadError,
            "#{path} defines several #{plural(declarations)} (#{names(declarations)}); select one with --job NAME"
    end

    def pick_named(declarations, path, name, noun)
      declarations.find { it.name == name } ||
        raise(JobLoadError, "no #{noun} named #{name} in #{path} (available: #{names(declarations)})")
    end

    # "jobs", "commands" or "jobs and commands".
    def plural(declarations)
      declarations.map { "#{KINDS.fetch(it.class)}s" }.uniq.join(" and ")
    end

    def names(declarations)
      declarations.map { it.name || "(unnamed)" }.join(", ")
    end

  end
end
```

`KINDS` needs `Job` and `Command` at load time: in `lib/metacrunch.rb`, `require_relative "metacrunch/loader"` must come after the three command requires of Step 4 (it already comes after `job`; move it below them if needed).

In `lib/metacrunch.rb`, replace `load_job`:

```ruby
    def load_job(path, name: nil)
      Loader.load(path, name:, kind: Job)
    end
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/loader_test.rb test/unit/command_test.rb test/cli/run_test.rb`
Expected: PASS. `run_test.rb` still finds "defines several jobs" for `several.rb`: a file with only jobs says "jobs".

- [ ] **Step 10: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 11: Commit**

```bash
git add lib/metacrunch/recipe_params.rb lib/metacrunch/builder.rb lib/metacrunch/command.rb \
        lib/metacrunch/command_builder.rb lib/metacrunch/command_scope.rb lib/metacrunch/loader.rb \
        lib/metacrunch.rb test/fixtures/jobs/mixed.rb test/fixtures/jobs/greet.rb \
        test/unit/command_test.rb test/unit/loader_test.rb
git commit -m "$(cat <<'EOF'
Add commands: recipes with params and a run block

Metacrunch.command declares a named recipe: params { } first, then
exactly one run { } with the body. CommandBuilder evaluates the recipe
and binds the parameters; describe stops at the first statement, so
--help never runs the body. The body runs on a CommandScope with params,
logger, invoke and root. Job and command recipes share RecipeParams.
Loader collects jobs and commands per file; -j selects among both, and
load_job still returns jobs only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 3: Projects and the Metacrunchfile

**Files:**
- Modify: `lib/metacrunch/errors.rb` (`ProjectError`)
- Create: `lib/metacrunch/project.rb`
- Modify: `lib/metacrunch.rb` (require, `load_files`, `load_project`)
- Test: `test/unit/project_test.rb`

**Interfaces:**
- Consumes: `Names.reserved?` (Task 1); `Loader.collect(path)`, `Loader.cached(path)`, `#file` of jobs and commands (Task 2).
- Produces:
  - `Metacrunch::ProjectError < Error`
  - `Project::FILE = "Metacrunchfile"`
  - `Project.find(dir) -> String | nil` (path of the nearest Metacrunchfile at or above dir)
  - `Project.load(dir = Dir.pwd) -> Project` (raises `ProjectError`), `Project.load_file(file) -> Project` (raises `ProjectError`), `Project.loading -> Project | nil`; `Project.new` is private
  - `#file` (absolute path of the Metacrunchfile), `#root` (Pathname), `#load_errors` (`[[path, exception], ...]`)
  - `#names -> Array<String>` (sorted), `#include?(name) -> Boolean` (also for duplicates), `#declared(name) -> Array` (one, several or none), `#fetch(name) -> Job | Command` (raises `ProjectError`)
  - `#load_files(globs)`, `#relative(path) -> String`, `#load_error_summary(file, error) -> String`, `#load_hint -> String` ("" or " (N file(s) of the project did not load)")
  - `Metacrunch.load_files(*globs)`, `Metacrunch.load_project(dir = Dir.pwd) -> Project`

- [ ] **Step 1: Write the failing tests**

`test/unit/project_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProjectTest < Minitest::Test

  include CredentialsHelper

  LOAD_ALL = "Metacrunch.load_files \"jobs/**/*.rb\", \"commands/**/*.rb\"\n"

  def test_finds_the_nearest_metacrunchfile_upward
    in_tmpdir do |root|
      outer = write_file(root, "Metacrunchfile", "")
      inner = write_file(root, "sub/Metacrunchfile", "")
      FileUtils.mkdir_p(File.join(root, "sub", "deep", "er"))

      assert_equal inner, Metacrunch::Project.find(File.join(root, "sub", "deep", "er"))
      assert_equal outer, Metacrunch::Project.find(root)
    end
  end

  def test_finds_nothing_without_metacrunchfile
    in_tmpdir { |root| assert_nil Metacrunch::Project.find(root) }
  end

  def test_loading_without_metacrunchfile_raises
    in_tmpdir do |root|
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_equal "no Metacrunchfile found in #{root} or above", error.message
    end
  end

  def test_loads_jobs_and_commands_from_relative_globs
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/a2c.rb" => job("a2c"),
                                   "jobs/sub/b.rb" => job("b"), "commands/release.rb" => command("catalog:release"))

      assert_equal ["a2c", "b", "catalog:release"], project.names
      assert_instance_of Metacrunch::Command, project.fetch("catalog:release")
      assert_equal [Pathname(root), File.join(root, "Metacrunchfile")], [project.root, project.file]
    end
  end

  def test_declarations_in_the_metacrunchfile_belong_to_the_project
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => command("inline"))

      assert_equal File.join(root, "Metacrunchfile"), project.fetch("inline").file
    end
  end

  def test_absolute_globs_load_files_outside_the_project
    in_tmpdir do |root|
      gem = write_file(root, "gem/commands/es.rb", ruby(command("es:create-index")))
      glob = File.join(root, "gem", "commands", "*.rb")
      project = load_project(File.join(root, "project"), "Metacrunchfile" => "Metacrunch.load_files #{glob.inspect}\n")

      assert_equal ["es:create-index"], project.names
      assert_equal gem, project.relative(project.fetch("es:create-index").file)
    end
  end

  def test_overlapping_globs_load_a_file_once
    in_tmpdir do |root|
      globs = "Metacrunch.load_files \"jobs/*.rb\", \"jobs/a*.rb\"\nMetacrunch.load_files \"jobs/a.rb\"\n"
      project = load_project(root, "Metacrunchfile" => globs, "jobs/a.rb" => job("a"))

      assert_equal "a", project.fetch("a").name
    end
  end

  def test_a_name_declared_twice_is_unusable_and_the_others_work
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/dup.rb" => job("dup"),
                                   "commands/dup.rb" => command("dup"), "jobs/ok.rb" => job("ok"))
      error = assert_raises(Metacrunch::ProjectError) { project.fetch("dup") }

      assert_equal "dup is declared more than once (commands/dup.rb, jobs/dup.rb); rename one", error.message
      assert_equal "ok", project.fetch("ok").name
    end
  end

  def test_a_file_that_fails_costs_only_its_names
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "Metacrunch.job \"x\" do\n",
                                   "jobs/ok.rb" => job("ok"))
      file, error = project.load_errors.first

      assert_equal [File.join(root, "jobs", "broken.rb"), SyntaxError], [file, error.class]
      assert_equal ["ok"], project.names
    end
  end

  def test_reserved_and_invalid_names_are_load_errors_of_their_file
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/run.rb" => job("run"),
                                   "jobs/upper.rb" => job("Upper"))
      messages = project.load_errors.map { |_file, error| error.message }

      assert_equal ["the name run is reserved for a built-in command",
                    "invalid job name \"Upper\": use a-z, 0-9, _ and -, in parts separated by :"], messages
      assert_empty project.names
    end
  end

  def test_an_error_in_the_metacrunchfile_is_a_project_error
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", ruby("raise \"broken\"\n"))
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_match(/could not load .*Metacrunchfile: RuntimeError: broken/, error.message)
    end
  end

  def test_a_reserved_name_in_the_metacrunchfile_is_a_project_error
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", ruby(command("help")))
      error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_project(root) }

      assert_equal "the name help is reserved for a built-in command", error.message
    end
  end

  def test_load_files_works_only_in_a_metacrunchfile
    error = assert_raises(Metacrunch::ProjectError) { Metacrunch.load_files("jobs/*.rb") }

    assert_equal "load_files works only in a Metacrunchfile", error.message
  end

  def test_files_that_the_metacrunchfile_loads_cannot_load_files
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL,
                                   "jobs/nested.rb" => "Metacrunch.load_files \"other/*.rb\"\n")

      assert_equal "load_files works only in a Metacrunchfile", project.load_errors.first.last.message
    end
  end

  def test_loading_a_project_twice_redefines_no_constants
    in_tmpdir do |root|
      write_project(root, "Metacrunchfile" => LOAD_ALL,
                          "jobs/a.rb" => "ProjectTest::LOADED_ONCE = true\n#{job("a")}")
      _stdout, stderr = capture_io { 2.times { Metacrunch.load_project(root) } }

      assert_empty stderr
    end
  end

  def test_relative_globs_work_below_a_root_with_glob_characters
    in_tmpdir do |dir|
      root = File.join(dir, "My Data [2026] {a,b}")
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/a.rb" => job("a"))

      assert_equal ["a"], project.names
    end
  end

  def test_unnamed_jobs_have_no_name_in_the_project
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/anon.rb" => "Metacrunch.job { source [] }\n")

      assert_empty project.names
      assert_empty project.load_errors
    end
  end

  def test_unknown_names_hint_at_files_that_did_not_load
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "x = (\n")
      error = assert_raises(Metacrunch::ProjectError) { project.fetch("nope") }

      assert_equal "unknown job or command: nope (1 file of the project did not load)", error.message
    end
  end

  def test_load_error_summaries_are_one_line_with_relative_paths
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/broken.rb" => "x = (\n")
      summary = project.load_error_summary(*project.load_errors.first)

      assert_match(%r{\Ajobs/broken\.rb: SyntaxError: jobs/broken\.rb:\d+: [^\n]+\z}, summary)
    end
  end

  private

  # Writes files below root, Ruby files with the magic comment, and loads
  # the project.
  def load_project(root, files)
    write_project(root, files)
    Metacrunch.load_project(root)
  end

  def write_project(root, files)
    files.each do |path, content|
      ruby_file = path.end_with?(".rb") || path == "Metacrunchfile"
      write_file(root, path, ruby_file ? ruby(content) : content)
    end
  end

  def ruby(code) = "# frozen_string_literal: true\n\n#{code}"

  def job(name) = "Metacrunch.job(#{name.inspect}) { source [] }\n"

  def command(name) = "Metacrunch.command(#{name.inspect}) { run { nil } }\n"

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/project_test.rb`
Expected: FAIL with `NameError: uninitialized constant Metacrunch::Project` (and `Metacrunch::ProjectError`)

- [ ] **Step 3: Add ProjectError**

In `lib/metacrunch/errors.rb`, after `UsageError`:

```ruby
  # A project could not be found or loaded, or a name is unknown or
  # declared more than once. The CLI exits with 2.
  class ProjectError < Error; end
```

- [ ] **Step 4: Write Project**

`lib/metacrunch/project.rb`:

```ruby
# frozen_string_literal: true

require "pathname"

module Metacrunch
  # A project: the directory of a Metacrunchfile, and the jobs and commands
  # its files declare (see the Readme, "Projects and commands"). A name
  # declared more than once stays in the project, but fetch refuses it; a
  # file that fails to load is kept in load_errors.
  class Project

    FILE = "Metacrunchfile"
    KEY = :metacrunch_loading_project

    attr_reader :file, :root, :load_errors

    # The nearest Metacrunchfile at or above dir, or nil.
    def self.find(dir)
      current = File.expand_path(dir)
      loop do
        candidate = File.join(current, FILE)
        return candidate if File.file?(candidate)

        parent = File.dirname(current)
        return if parent == current

        current = parent
      end
    end

    # The project of the nearest Metacrunchfile at or above dir. Raises
    # ProjectError if there is none or it fails to load.
    def self.load(dir = Dir.pwd)
      file = find(dir) || raise(ProjectError, "no #{FILE} found in #{File.expand_path(dir)} or above")
      load_file(file)
    end

    # Loads file, a Metacrunchfile, with the files it loads. Raises
    # ProjectError if the Metacrunchfile itself fails.
    def self.load_file(file) = new(file)

    # The project whose Metacrunchfile is being loaded on this thread.
    def self.loading = Thread.current[KEY]

    private_class_method :new

    def initialize(file)
      @file = File.expand_path(file)
      @root = Pathname(File.dirname(@file))
      @declarations = {}
      @files = [@file]
      @load_errors = []
      load_metacrunchfile
    end

    # The declared names, sorted; duplicates included.
    def names = @declarations.keys.sort

    def include?(name) = @declarations.key?(name.to_s)

    # The jobs and commands declared as name: one, several for a duplicate,
    # or none.
    def declared(name) = @declarations.fetch(name.to_s, [])

    # The Job or Command named name. Raises ProjectError if the name is
    # unknown or declared more than once.
    def fetch(name)
      declarations = declared(name)
      raise ProjectError, "unknown job or command: #{name}#{load_hint}" if declarations.empty?
      return declarations.first if declarations.one?

      files = declarations.map { relative(it.file) }.join(", ")
      raise ProjectError, "#{name} is declared more than once (#{files}); rename one"
    end

    # Loads the files that match globs (relative to the root, or absolute),
    # in sorted order and each once. A file that fails or declares a
    # reserved name contributes nothing and ends up in load_errors.
    def load_files(globs)
      paths = globs.flatten.flat_map { matches(it.to_s) }
      paths.select { File.file?(it) }.map { File.expand_path(it) }.uniq.sort.each { add_file(it) }
      nil
    end

    # path relative to the root if it is below it, else path.
    def relative(path)
      prefix = "#{@root}/"
      path.start_with?(prefix) ? path.delete_prefix(prefix) : path
    end

    # One line about a file that did not load, with paths relative to the
    # root: "jobs/x.rb: SyntaxError: jobs/x.rb:3: syntax error found".
    def load_error_summary(file, error)
      line = error.message.lines.first.to_s.chomp.gsub(file, relative(file))
      "#{relative(file)}: #{error.class}: #{line}"
    end

    # " (2 files of the project did not load)", or "" if all loaded.
    def load_hint
      count = @load_errors.size
      return "" if count.zero?

      " (#{count} #{count == 1 ? "file" : "files"} of the project did not load)"
    end

    def inspect = "#<#{self.class.name} #{@file}>"

    private

    def load_metacrunchfile
      add_all(loading(self) { Loader.collect(@file) })
    rescue JobLoadError => e
      raise ProjectError, e.message
    end

    # Metacrunch.load_files works while the Metacrunchfile loads, not in
    # the files it loads.
    def loading(project)
      previous = Thread.current[KEY]
      Thread.current[KEY] = project
      yield
    ensure
      Thread.current[KEY] = previous
    end

    def add_file(path)
      return if @files.include?(path)

      @files << path
      add_all(loading(nil) { Loader.cached(path) })
    rescue JobLoadError => e
      @load_errors << [path, e.cause || e]
    rescue ProjectError => e
      @load_errors << [path, e]
    end

    # Adds what one file declares, or nothing if it uses a reserved name.
    def add_all(declarations)
      reserved = declarations.find { Names.reserved?(it.name) }
      raise ProjectError, "the name #{reserved.name} is reserved for a built-in command" if reserved

      declarations.each { add(it) }
    end

    # Unnamed jobs have no name in the project; they run by path only.
    def add(declaration)
      return unless declaration.name

      (@declarations[declaration.name] ||= []) << declaration
    end

    # Relative globs are expanded below the root, so that characters such
    # as [ in the root's path do not count as a pattern.
    def matches(glob)
      return Dir.glob(glob) if File.absolute_path?(glob)

      Dir.glob(glob, base: @root.to_s).map { File.join(@root.to_s, it) }
    end

  end
end
```

In `lib/metacrunch.rb`, add after `require_relative "metacrunch/loader"`:

```ruby
require_relative "metacrunch/project"
```

and after `load_job`:

```ruby
    # Loads the job and command files that match globs into the project
    # whose Metacrunchfile is being loaded (see Project#load_files).
    def load_files(*globs)
      project = Project.loading || raise(ProjectError, "load_files works only in a Metacrunchfile")
      project.load_files(globs)
    end

    # The project of the nearest Metacrunchfile at or above dir.
    def load_project(dir = Dir.pwd) = Project.load(dir)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/project_test.rb`
Expected: PASS (19 runs)

- [ ] **Step 6: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 7: Commit**

```bash
git add lib/metacrunch/errors.rb lib/metacrunch/project.rb lib/metacrunch.rb test/unit/project_test.rb
git commit -m "$(cat <<'EOF'
Add projects: a Metacrunchfile names jobs and commands

Metacrunch.load_project finds the nearest Metacrunchfile upward and loads
it; Metacrunch.load_files loads job and command files relative to the
project root, or absolute ones from gems, sorted and each once. A file
that fails or uses a reserved name costs only its own names; a name
declared twice is refused by fetch with both files; an error in the
Metacrunchfile itself is a ProjectError.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 4: The Invoker

**Files:**
- Move: `lib/metacrunch/cli/run_options.rb` to `lib/metacrunch/run_options.rb` (`Metacrunch::RunOptions`)
- Modify: `lib/metacrunch/cli.rb` (drop the require of `cli/run_options`), `test/unit/run_options_test.rb` (constant)
- Modify: `lib/metacrunch/errors.rb` (`InvokeError`)
- Create: `lib/metacrunch/invoker.rb`
- Modify: `lib/metacrunch/project.rb` (`invoke`)
- Modify: `lib/metacrunch.rb` (requires)
- Test: `test/unit/invoker_test.rb`

**Interfaces:**
- Consumes: `Names.path?` (Task 1); `Command#prepare`, `Command::Prepared`, `CommandScope`, `Loader.load` (Task 2); `Project#include?`, `#fetch`, `#file`, `#root`, `Project::FILE`, `ProjectError` (Task 3); `Credentials.store(job_file:, env:, logger:, environment:, directory:)`, `Engine`, `Executor.for`, `StepError`.
- Produces:
  - `Metacrunch::RunOptions` (unchanged API: `new(input:, output:, rejects:, errors:, stats:, limit:, on_error:, max_errors:)`, `#apply(pipeline, stdin:, stdout:)`, `#records_to_stdout?(pipeline)`, `#apply_input(pipeline, stdin:)`, `#stats`)
  - `Metacrunch::InvokeError < Error`: `new(message, name:, result: nil)`, `#name`, `#result`; the original error is `cause`
  - `Metacrunch::Invoker.new(project: nil, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout, environment: nil, credentials: nil, progress: nil)`; `project:` is a Project, nil, or a Proc called once when a name is first needed; `progress:` is called with `records_to_stdout` and returns an Engine monitor or nil
  - `#invoke(target, *argv, workers: nil, limit: nil) -> Result | Object` (raises `InvokeError`, `ArgumentError`)
  - `#resolve(target, select: nil) -> [declaration, anchor]` (raises `ProjectError`, `JobLoadError`, `UsageError`)
  - `#pipeline(job, argv, anchor:) -> Pipeline`, `#prepare(command, argv, anchor:) -> Command::Prepared`, `#call(prepared) -> Object`
  - `#run_job(job, argv, anchor:, options: RunOptions.new, workers: nil, label: nil) -> Result` (logs error and summary, tracks the status)
  - `#project -> Project | nil`, `#root -> Pathname` (raises `ProjectError`), `#logger`, `#status` (worst of `:ok`, `:ok_with_failures`, `:aborted`), `#finished_status` (`:ok` or `:ok_with_failures`)
  - Private hooks for Task 6: `invoke_job(job, argv, target:, anchor:, workers:, limit:)`, `invoke_command(command, argv, target:, anchor:)`, `track(status)`, `aborted!(result, target)`, `wrap(target) { }`; constant `Invoker::STATUSES`
  - `Project#invoke(target, *argv, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout, workers: nil, limit: nil)`

- [ ] **Step 1: Move RunOptions into the library**

```bash
git mv lib/metacrunch/cli/run_options.rb lib/metacrunch/run_options.rb
```

In `lib/metacrunch/run_options.rb`, remove the `class Cli` wrapper (the line `class Cli`, the empty line after it, the matching `end` before the module's `end`) and outdent the `RunOptions = Data.define(...) do ... end` block by two spaces, so that it reads:

```ruby
# frozen_string_literal: true

module Metacrunch

  # The options of `metacrunch run` that change the pipeline: source and
  # sinks replaced by JSON Lines, the filter default, the limit and the
  # error policy. Paths may be "-" for stdin or stdout. The Invoker applies
  # them to every job it runs; invoked jobs get the defaults.
  RunOptions = Data.define(:input, :output, :rejects, :errors, :stats, :limit, :on_error, :max_errors) do
    def initialize(input: nil, output: nil, rejects: nil, errors: nil, stats: nil, limit: nil, on_error: nil,
                   max_errors: nil)
      super
    end

    # ... the rest of the block unchanged, outdented by two spaces ...
  end

end
```

In `lib/metacrunch/cli.rb`, delete `require_relative "cli/run_options"`. In `lib/metacrunch.rb`, add after `require_relative "metacrunch/json_lines"` (RunOptions uses `JsonLines` only at run time, the order is for readability):

```ruby
require_relative "metacrunch/run_options"
```

In `test/unit/run_options_test.rb`, change the constant:

```ruby
  RunOptions = Metacrunch::RunOptions
```

`Cli::RunCommand` and `Cli::TraceCommand` name `RunOptions` inside `class Cli`; the constant lookup now finds `Metacrunch::RunOptions` and they need no change.

Run: `bundle exec rake test`
Expected: PASS

- [ ] **Step 2: Write the failing Invoker tests**

`test/unit/invoker_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class InvokerTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_error(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/term.rb" => <<~RUBY,
      Metacrunch.job "term" do
        params { param :output, String, required: true }

        source [1, 2]
        map { it == 2 ? raise(SignalException, "TERM") : it }
        sink Metacrunch::JsonLines::Writer.new(params.output), batch: 10
      end
    RUBY
    "commands/note.rb" => <<~RUBY,
      Metacrunch.command "note" do
        params { args :text, min: 1, max: 1 }

        run { params.text.first }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain" do
        params do
          param :tolerant, :bool, default: false
          args :numbers
        end

        run do
          invoke "numbers", *params.numbers
        rescue Metacrunch::InvokeError
          raise unless params.tolerant

          :rescued
        end
      end
    RUBY
    "commands/outer.rb" => <<~RUBY,
      Metacrunch.command "outer" do
        params { args :numbers }

        run { [invoke("chain", "--tolerant", *params.numbers), invoke("note", "done")] }
      end
    RUBY
    "commands/boom.rb" => "Metacrunch.command(\"boom\") { run { raise IOError, \"disk full\" } }\n"
  }.freeze

  # A command from a gem: its file lives outside the project.
  GEM_COMMAND = <<~RUBY
    Metacrunch.command "secret:show" do
      params { param :api_key, String, credential: "catalog.api_key", required: true }

      run do
        invoke "secret"
        params.api_key.reverse
      end
    end
  RUBY

  NAMED_SECRET_JOB = <<~RUBY
    Metacrunch.job "secret" do
      params { param :api_key, String, credential: "catalog.api_key", required: true }

      source [params.api_key.reverse]
    end
  RUBY

  def test_invoking_a_job_returns_its_result_and_writes_stdout
    with_project do |invoker, out|
      result = invoker.invoke("numbers", 4, Pathname("5"))

      assert_equal [:ok, "25\n20\n"], [result.status, out.string]
    end
  end

  def test_an_aborted_job_raises_an_invoke_error_with_its_result
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", "0") }

      assert_equal ["numbers", :aborted, Metacrunch::StepError], [error.name, error.result.status, error.cause.class]
      assert_match(/\Anumbers aborted: Metacrunch::StepError: step map#1 failed at position 1/, error.message)
    end
  end

  def test_failed_records_return_the_result_and_worsen_the_status
    with_project do |invoker|
      result = invoker.invoke("numbers", "--skip", "0", "4")

      assert_equal [:ok_with_failures, :ok_with_failures], [result.status, invoker.status]
    end
  end

  def test_a_command_returns_the_value_of_its_body
    with_project { |invoker| assert_equal "done", invoker.invoke("note", "done") }
  end

  def test_exceptions_from_a_body_propagate_unchanged
    with_project do |invoker|
      error = assert_raises(IOError) { invoker.invoke("boom") }

      assert_equal "disk full", error.message
    end
  end

  def test_invalid_arguments_for_the_target_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("note") }

      assert_equal "invoke note: expected at least 1 argument(s) for text, got 0", error.message
      assert_instance_of Metacrunch::ParamError, error.cause
    end
  end

  def test_unknown_names_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("nope") }

      assert_equal ["invoke nope: unknown command, job or file: nope", "nope"], [error.message, error.name]
    end
  end

  def test_names_without_a_project_are_unknown
    error = assert_raises(Metacrunch::InvokeError) { invoker_for(nil).invoke("numbers") }

    assert_equal "invoke numbers: unknown command, job or file: numbers (no Metacrunchfile found)", error.message
  end

  def test_paths_run_without_a_project
    out = StringIO.new
    result = invoker_for(nil, stdin: StringIO.new("1\n2\n"), stdout: out).invoke(job("double.rb"))

    assert_equal [:ok, "2\n4\n"], [result.status, out.string]
  end

  def test_the_project_is_looked_up_once_when_a_name_is_first_needed
    with_project do |invoker|
      project = invoker.project
      calls = 0
      lookup = lambda do
        calls += 1
        project
      end
      lazy = invoker_for(lookup)
      2.times { lazy.invoke("note", "x") }

      assert_equal 1, calls
    end
  end

  def test_a_name_wins_over_a_file_of_that_name_and_files_fill_in
    with_project do |invoker, out, root|
      write_file(root, "note", "# frozen_string_literal: true\n\nMetacrunch.job { source [\"file\"] }\n")
      write_file(root, "solo", "# frozen_string_literal: true\n\nMetacrunch.job { source [\"solo\"] }\n")
      value = Dir.chdir(root) { [invoker.invoke("note", "name"), invoker.invoke("solo").status] }

      assert_equal ["name", :ok], value
      assert_equal "\"solo\"\n", out.string
    end
  end

  def test_nil_arguments_are_refused
    with_project do |invoker|
      error = assert_raises(ArgumentError) { invoker.invoke("note", "--x", nil) }

      assert_equal "invoke note: argument 2 is nil", error.message
    end
  end

  def test_workers_and_limit_apply_to_jobs_only
    with_project do |invoker|
      error = assert_raises(ArgumentError) { invoker.invoke("note", "x", workers: 2) }

      assert_equal "note is a command; workers: and limit: apply to jobs", error.message
      assert_equal 2, invoker.invoke("numbers", "1", "2", "4", limit: 2).stats.read
    end
  end

  def test_a_job_without_source_on_a_terminal_raises_an_invoke_error
    invoker = invoker_for(nil, stdin: TerminalInput.new)
    error = assert_raises(Metacrunch::InvokeError) { invoker.invoke(job("double.rb")) }

    assert_match(/job has no source and stdin is a terminal/, error.message)
  end

  def test_the_worst_status_comes_through_a_nested_command
    with_project do |invoker|
      value = invoker.invoke("outer", "0")

      assert_equal [:rescued, "done"], value
      assert_equal [:aborted, :ok_with_failures], [invoker.status, invoker.finished_status]
    end
  end

  def test_logs_the_error_and_the_summary_with_the_name
    log = StringIO.new
    with_project(logger: Logger.new(log)) do |invoker|
      assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", "0") }

      assert_match(/numbers: Metacrunch::StepError: step map#1 failed/, log.string)
      assert_match(/numbers: aborted: read 1, written 0/, log.string)
    end
  end

  def test_a_signal_from_an_invoked_job_propagates_after_the_sink_was_flushed
    with_project do |invoker, _out, root|
      output = File.join(root, "term.jsonl")

      assert_raises(SignalException) { invoker.invoke("term", "--output", output) }
      assert_equal "1\n", File.read(output)
    end
  end

  def test_the_environment_and_credentials_from_the_project_root_reach_a_gem_command
    in_tmpdir do |dir|
      root = File.join(dir, "project")
      glob = File.join(dir, "gem", "commands", "*.rb")
      write_ruby(dir, "gem/commands/secret.rb", GEM_COMMAND)
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files #{glob.inspect}, \"jobs/*.rb\"\n")
      write_ruby(root, "jobs/secret.rb", NAMED_SECRET_JOB)
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      out = StringIO.new
      invoker = invoker_for(Metacrunch.load_project(root), stdout: out, environment: "production")

      assert_equal SECRET.reverse, invoker.invoke("secret:show")
      assert_equal "\"#{SECRET.reverse}\"\n", out.string
    end
  end

  def test_root_needs_a_project
    error = assert_raises(Metacrunch::ProjectError) { invoker_for(nil).root }

    assert_match(/\Ano Metacrunchfile found in .* or above\z/, error.message)
  end

  def test_project_invoke_runs_like_invoke_in_a_command
    with_project do |invoker|
      assert_equal "done", invoker.project.invoke("note", "done", logger: Logger.new(nil), env: {})
    end
  end

  private

  # Yields an Invoker for a project with FILES, its stdout and the root.
  def with_project(logger: Logger.new(nil))
    in_tmpdir do |root|
      FILES.each { |path, code| write_ruby(root, path, code) }
      out = StringIO.new
      yield invoker_for(Metacrunch.load_project(root), stdout: out, logger:), out, root
    end
  end

  def invoker_for(project, stdin: StringIO.new, stdout: StringIO.new, logger: Logger.new(nil), environment: nil)
    Metacrunch::Invoker.new(project:, logger:, env: {}, stdin:, stdout:, environment:)
  end

  def write_ruby(root, path, code) = write_file(root, path, "# frozen_string_literal: true\n\n#{code}")

end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/invoker_test.rb`
Expected: FAIL with `NameError: uninitialized constant Metacrunch::Invoker` (and `Metacrunch::InvokeError`)

- [ ] **Step 4: Add InvokeError**

In `lib/metacrunch/errors.rb`, after `ProjectError`:

```ruby
  # invoke failed: the target is unknown, the arguments are invalid for
  # it, or the job aborted. name: the target as given; result: the Result
  # of an aborted job, else nil. The original error is the cause.
  class InvokeError < Error

    attr_reader :name, :result

    def initialize(message, name:, result: nil)
      @name = name
      @result = result
      super(message)
    end

  end
```

- [ ] **Step 5: Write the Invoker**

`lib/metacrunch/invoker.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # Runs jobs and commands with the context of one call: the environment,
  # the credentials options (-e, --credentials), the logger, stdin and
  # stdout, and the progress display. The CLI runs its target through it,
  # and a command's body invokes through it, so a whole chain shares that
  # context. Tracks the worst status of the jobs it ran.
  class Invoker

    STATUSES = [:ok, :ok_with_failures, :aborted].freeze
    # Errors that mean the invoking command passed a wrong target or wrong
    # arguments; invoke raises them as InvokeError.
    WRAPPED = [ParamError, UsageError, JobLoadError, ProjectError].freeze

    attr_reader :logger, :status

    # project: the Project that names resolve in, nil, or a Proc that
    # returns one of these when a name is first needed. environment and
    # credentials: -e and --credentials. progress: called with whether a
    # job's records go to stdout; returns a monitor for Engine or nil.
    def initialize(project: nil, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout,
                   environment: nil, credentials: nil, progress: nil)
      @project = project
      @logger = logger
      @env = env
      @stdin = stdin
      @stdout = stdout
      @environment = environment
      @credentials = credentials
      @progress = progress
      @status = :ok
    end

    # The project that names resolve in, or nil.
    def project
      @project = @project.call if @project.is_a?(Proc)
      @project
    end

    # The root of the project, a Pathname. Raises ProjectError without one.
    def root
      project&.root || raise(ProjectError, "no #{Project::FILE} found in #{Dir.pwd} or above")
    end

    # Runs target, a name or a path, with argv as on the command line, each
    # converted with to_s. Returns a job's Result or a command's value.
    # Raises InvokeError if the target is unknown, argv is invalid for it or
    # the job aborted; exceptions from a command's body pass unchanged.
    def invoke(target, *argv, workers: nil, limit: nil)
      target = target.to_s
      argv = arguments(target, argv)
      declaration, anchor = wrap(target) { resolve(target) }
      return invoke_job(declaration, argv, target:, anchor:, workers:, limit:) if declaration.is_a?(Job)
      raise ArgumentError, "#{target} is a command; workers: and limit: apply to jobs" if workers || limit

      invoke_command(declaration, argv, target:, anchor:)
    end

    # [declaration, anchor] for target. A target with / or . is a path; any
    # other is a name of the project, else an existing file of that name.
    # anchor is the file credentials are searched from: the Metacrunchfile
    # for a name, the file itself for a path. select: -j, for paths only.
    def resolve(target, select: nil)
      return by_path(target, select) if Names.path?(target)

      current = project
      return by_name(current, target, select) if current&.include?(target)
      return by_path(target, select) if File.file?(target)

      hint = current ? current.load_hint : " (no #{Project::FILE} found)"
      raise ProjectError, "unknown command, job or file: #{target}#{hint}"
    end

    # The job's pipeline with argv bound: the command line, env:, the
    # credentials searched from anchor, then the default.
    def pipeline(job, argv, anchor:)
      job.pipeline(binder: binder(argv, anchor), logger: @logger)
    end

    # Evaluates the command's recipe with argv bound as pipeline does.
    def prepare(command, argv, anchor:)
      command.prepare(binder: binder(argv, anchor))
    end

    # Runs the body of a prepared command and returns its value.
    def call(prepared)
      CommandScope.new(params: prepared.params, logger: @logger, invoker: self).instance_exec(&prepared.body)
    end

    # Runs a job like `metacrunch run`: options are the run options (-i,
    # -o, ...); their defaults read stdin for a job without source and
    # write stdout for one without sink. Logs the job's error and its
    # summary, prefixed with label, and returns the Result.
    def run_job(job, argv, anchor:, options: RunOptions.new, workers: nil, label: nil)
      built = pipeline(job, argv, anchor:)
      pipeline = options.apply(built, stdin: @stdin, stdout: @stdout)
      monitor = @progress&.call(options.records_to_stdout?(built))
      result = Engine.new(pipeline, executor: Executor.for(workers), monitor:).run
      report(result, label)
      track(result.status)
      result
    end

    # The status of a command whose body finished: :ok, or
    # :ok_with_failures if a job it invoked ended with failed records, or
    # aborted and the body went on.
    def finished_status = @status == :ok ? :ok : :ok_with_failures

    private

    def arguments(target, argv)
      index = argv.index(nil)
      raise ArgumentError, "invoke #{target}: argument #{index + 1} is nil" if index

      argv.map(&:to_s)
    end

    # Project#fetch raises for a name declared more than once.
    def by_name(project, name, select)
      raise UsageError, "--job selects in a file; #{name} is a name" if select

      [project.fetch(name), project.file]
    end

    def by_path(path, select)
      declaration = Loader.load(path, name: select)
      [declaration, declaration.file]
    end

    def invoke_job(job, argv, target:, anchor:, workers:, limit:)
      result = wrap(target) { run_job(job, argv, anchor:, options: RunOptions.new(limit:), workers:, label: target) }
      aborted!(result, target)
      result
    end

    def invoke_command(command, argv, target:, anchor:)
      call(wrap(target) { prepare(command, argv, anchor:) })
    end

    # The job has logged its error already.
    def aborted!(result, target)
      return unless result.status == :aborted

      error = result.error
      raise InvokeError.new("#{target} aborted: #{error.class}: #{error.message}", name: target, result:),
            cause: error
    end

    def wrap(target)
      yield
    rescue *WRAPPED => e
      raise InvokeError.new("invoke #{target}: #{e.message}", name: target)
    end

    def binder(argv, anchor)
      credentials = Credentials.store(job_file: anchor, env: @env, logger: @logger, environment: @environment,
                                      directory: @credentials)
      warn = ->(message) { @logger.warn(message) }
      ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }
    end

    # Logs the error and its cause once each (a StepError message already
    # names its cause), then the status and stats.
    def report(result, label)
      prefix = label ? "#{label}: " : ""
      error = result.error
      if error
        @logger.error("#{prefix}#{error.class}: #{error.message}")
        cause = error.cause
        @logger.error("#{prefix}caused by #{cause.class}: #{cause.message}") if cause && !error.is_a?(StepError)
      end
      @logger.info("#{prefix}#{result.status}: #{result.stats.summary}")
    end

    def track(status)
      @status = [@status, status].max_by { STATUSES.index(it) }
    end

  end
end
```

Notes for the implementer:
- `resolve` says "unknown command, job or file", as the CLI does (Task 5), with the project's `load_hint` or the hint that there is no project.
- `wrap` around `run_job` also catches the `UsageError` of `RunOptions#apply` (a job without source on a terminal). The engine itself never raises the wrapped errors: step and hook errors end up in the Result, and signals and `ArgumentError` pass through.
- `raise InvokeError.new(...)` inside `rescue` gets the rescued error as `cause` without `cause:`.

Add `Project#invoke` to `lib/metacrunch/project.rb`, after `fetch`:

```ruby
    # Runs a job or command of the project like invoke in a command body
    # (see Invoker#invoke), with its own streams, environment and logger.
    def invoke(target, *argv, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout, workers: nil,
               limit: nil)
      Invoker.new(project: self, logger:, env:, stdin:, stdout:).invoke(target, *argv, workers:, limit:)
    end
```

In `lib/metacrunch.rb`, add after `require_relative "metacrunch/run_options"`:

```ruby
require_relative "metacrunch/invoker"
```

`Invoker::WRAPPED` names the error classes at load time; they come from `errors.rb`, which is required first.

- [ ] **Step 6: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/invoker_test.rb`
Expected: PASS (20 runs)

- [ ] **Step 7: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 8: Commit**

```bash
git add lib/metacrunch/run_options.rb lib/metacrunch/cli.rb lib/metacrunch/errors.rb lib/metacrunch/invoker.rb \
        lib/metacrunch/project.rb lib/metacrunch.rb test/unit/run_options_test.rb test/unit/invoker_test.rb
git commit -m "$(cat <<'EOF'
Add the Invoker: run jobs and commands of a chain

The Invoker holds what a chain shares (environment, credentials options,
logger, streams, progress), resolves names in the project and paths as
files, runs jobs like metacrunch run and command bodies, and tracks the
worst status. invoke raises InvokeError for an aborted job, an unknown
target or invalid arguments, and ArgumentError for nil arguments.
Credentials for names are searched from the project root. RunOptions
moves into the library, since the Invoker also serves Project#invoke.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 5: Names and commands on the command line

**Files:**
- Create: `lib/metacrunch/cli/project_lookup.rb`
- Modify: `lib/metacrunch/cli.rb` (lookup, dispatch of names, help, project lists)
- Modify: `lib/metacrunch/cli/command.rb` (`initialize(streams, lookup)`, rescue `ProjectError`)
- Modify: `lib/metacrunch/cli/job_command.rb` (targets through the Invoker, help with desc, `check_target!`)
- Modify: `lib/metacrunch/cli/run.rb` (commands, job options, runs through the Invoker)
- Modify: `lib/metacrunch/cli/check.rb` (`@target`), `lib/metacrunch/cli/trace.rb`, `lib/metacrunch/cli/new.rb` (constructor)
- Test: `test/cli/project_cli_test.rb`; update `test/cli/cli_test.rb`, `test/cli/run_test.rb`

**Interfaces:**
- Consumes: `Names.path?`, `Names` messages (Task 1); `Command`, fixture `greet.rb` (Task 2); `Project.find`, `Project.load_file`, `#include?`, `#names`, `#declared`, `#root`, `#load_errors`, `#load_error_summary`, `#load_hint`, `Project::FILE`, `ProjectError` (Task 3); `Invoker` with `#resolve`, `#pipeline`, `#prepare`, `#call`, `#run_job`, `#finished_status`, `InvokeError`, `RunOptions` (Task 4).
- Produces:
  - `Metacrunch::Cli::ProjectLookup.new`; `#project(logger) -> Project | nil` (loads once; raises `ProjectError`; logs one warning per load error to logger unless it is nil)
  - `Cli::Command.new(streams, lookup)` for every command
  - CLI behavior of spec section 6: `metacrunch NAME`, `run|check|trace NAME`, `NAME --help`, `help NAME`, the project lists in `--help`, the usage errors and exit codes.

- [ ] **Step 1: Write the failing CLI tests**

`test/cli/project_cli_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ProjectCliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers", desc: "Divide 100 by each number" do
        params do
          param :skip, :bool, default: false, desc: "Skip failed records"
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_error(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/interrupted.rb" => <<~RUBY,
      Metacrunch.job "interrupted" do
        source [1]
        map { raise Interrupt }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain", desc: "numbers, then a note" do
        params do
          param :skip, :bool, default: false
          param :tolerant, :bool, default: false
          args :numbers
        end

        run do
          begin
            invoke "numbers", *(params.skip ? ["--skip"] : []), *params.numbers
          rescue Metacrunch::InvokeError
            raise unless params.tolerant
          end
          invoke "note", "done"
        end
      end
    RUBY
    "commands/note.rb" => <<~'RUBY',
      Metacrunch.command "note", desc: "Log a note" do
        params { args :text, min: 1, max: 1 }

        run { logger.info("note: #{params.text.first}") }
      end
    RUBY
    "commands/stop.rb" => <<~RUBY,
      Metacrunch.command "stop" do
        run do
          invoke "interrupted"
          invoke "note", "after"
        end
      end
    RUBY
    "commands/fail.rb" => "Metacrunch.command(\"fail\") { run { raise IOError, \"disk full\" } }\n"
  }.freeze

  # A command outside jobs/ and commands/, run by path.
  TOOL = "Metacrunch.command(\"tools:release\") { run { invoke \"note\", \"from tools\" } }\n"
  # Writes a file if its body ever runs.
  DANGER = "Metacrunch.command(\"danger\") { run { File.write(\"ran\", \"\") } }\n"
  DUPLICATE = "Metacrunch.job(\"note\") { source [] }\n"
  BROKEN = "x = (\n"

  def test_runs_a_job_by_name_from_a_subdirectory
    in_project do |root|
      code, stdout, stderr = cli_in(File.join(root, "jobs"), "numbers", "4", "5")

      assert_equal [0, "25\n20\n"], [code, stdout]
      assert_match(/INFO  ok: read 2, written 2/, stderr)
    end
  end

  def test_runs_a_command_by_name_also_with_run
    in_project do |root|
      short = cli_in(root, "note", "hello")
      long = cli_in(root, "run", "note", "hi")

      assert_equal [0, 0], [short.first, long.first]
      assert_match(/INFO  note: hello/, short.last)
    end
  end

  def test_a_chain_exits_with_the_worst_status
    in_project do |root|
      results = [["4"], ["0"], ["--skip", "0", "4"], ["--tolerant", "0"]].map { cli_in(root, "chain", *it) }
      aborted = results[1].last

      assert_equal [0, 1, 3, 3], results.map(&:first)
      assert_match(/ERROR numbers aborted: Metacrunch::StepError/, aborted)
      refute_match(/note: done/, aborted)
    end
  end

  def test_an_exception_in_the_body_exits_with_1_and_its_backtrace
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "fail")

      assert_equal 1, code
      assert_match(/disk full \(IOError\)/, stderr)
    end
  end

  def test_invalid_params_of_a_command_exit_with_2
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "note")

      assert_equal 2, code
      assert_match(/Error: expected at least 1 argument\(s\) for text, got 0/, stderr)
    end
  end

  def test_ctrl_c_in_an_invoked_job_ends_the_chain_with_130
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "stop")

      assert_equal 130, code
      refute_match(/note: after/, stderr)
    end
  end

  def test_invoked_jobs_show_progress_as_run_does
    slowly = "Metacrunch.command(\"slowly\") { run { invoke #{job("slow.rb").inspect} } }\n"
    in_project("commands/slowly.rb" => slowly) do |root|
      shown = TerminalOutput.new
      hidden = TerminalOutput.new
      cli_in(root, "slowly", stderr: shown)
      cli_in(root, "run", "--no-progress", "slowly", stderr: hidden)

      assert_includes shown.string, "\r\e[2K"
      refute_includes hidden.string, "\e[2K"
    end
  end

  def test_help_for_names_shows_the_description
    in_project do |root|
      code, stdout, = cli_in(root, "numbers", "--help")

      assert_equal 0, code
      assert_match(/\AUsage: metacrunch run numbers \[JOB_PARAMS\.\.\.\] NUMBERS\.\.\.\n\nDivide 100 by each number\n\n/,
                   stdout)
      assert_equal cli_in(root, "note", "--help"), cli_in(root, "help", "note")
    end
  end

  def test_help_never_runs_a_body
    in_project("commands/danger.rb" => DANGER) do |root|
      code, stdout, = cli_in(root, "danger", "--help")

      assert_equal [0, "Usage: metacrunch run danger [PARAMS...]\n\n"], [code, stdout]
      refute_path_exists File.join(root, "ran")
    end
  end

  def test_the_usage_lists_jobs_and_commands_with_their_descriptions
    in_project do |root|
      code, stdout, = cli_in(root, "--help")

      assert_equal 0, code
      assert_match(/^Jobs \(#{Regexp.escape(root)}\):\n  interrupted\n  numbers +Divide 100 by each number\n/, stdout)
      assert_match(/^Project commands \(.*\):\n  chain +numbers, then a note\n  fail\n  note +Log a note\n  stop\n/,
                   stdout)
    end
  end

  def test_the_usage_lists_duplicates_and_files_that_did_not_load_without_warnings
    in_project("jobs/dup.rb" => DUPLICATE, "jobs/broken.rb" => BROKEN) do |root|
      _code, stdout, stderr = cli_in(root, "--help")

      assert_match(/^  note +\(declared more than once, unusable\)$/, stdout)
      assert_match(%r{^Not loaded:\n  jobs/broken\.rb: SyntaxError: jobs/broken\.rb:\d+: }, stdout)
      assert_empty stderr
    end
  end

  def test_a_failing_metacrunchfile_shows_in_the_usage_and_stops_names
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nraise \"broken\"\n")
      help = cli_in(root, "--help")
      named = cli_in(root, "numbers")

      assert_equal [0, 2], [help.first, named.first]
      assert_match(/^Project:\n  could not load .*Metacrunchfile: RuntimeError: broken$/, help[1])
      assert_match(/Error: could not load .*Metacrunchfile: RuntimeError: broken/, named.last)
    end
  end

  def test_files_that_did_not_load_give_one_warning_each
    in_project("jobs/broken.rb" => BROKEN) do |root|
      quiet = cli_in(root, "note", "x")
      verbose = cli_in(root, "run", "-v", "note", "x")

      assert_equal [0, 1], [quiet.first, quiet.last.scan("WARN  jobs/broken.rb: SyntaxError").size]
      assert_match(%r{WARN  jobs/broken\.rb: SyntaxError: .* \(-v for details\)}, quiet.last)
      assert_match(/DEBUG .*broken\.rb:\d+: syntax error/m, verbose.last)
    end
  end

  def test_unknown_names_hint_at_files_that_did_not_load
    in_project("jobs/broken.rb" => BROKEN) do |root|
      code, _stdout, stderr = cli_in(root, "nope")

      assert_equal 2, code
      assert_match(/Error: unknown command, job or file: nope \(1 file of the project did not load\)/, stderr)
    end
  end

  def test_unknown_names_outside_a_project
    in_tmpdir do |dir|
      code, _stdout, stderr = cli_in(dir, "nope")

      assert_equal 2, code
      assert_match(/Error: unknown command, job or file: nope \(no Metacrunchfile found\)/, stderr)
    end
  end

  def test_a_duplicate_name_is_a_usage_error_naming_both_files
    in_project("jobs/dup.rb" => DUPLICATE) do |root|
      code, _stdout, stderr = cli_in(root, "note", "x")

      assert_equal 2, code
      assert_match(%r{Error: note is declared more than once \(commands/note\.rb, jobs/dup\.rb\); rename one}, stderr)
    end
  end

  def test_job_options_are_a_usage_error_for_commands
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "-w", "2", "note", "x")

      assert_equal 2, code
      assert_match(/Error: note is a command; -w applies to jobs/, stderr)
    end
  end

  def test_check_and_trace_take_jobs_only
    in_project do |root|
      results = ["check", "trace"].map { cli_in(root, it, "note", "x") }

      assert_equal [2, 2], results.map(&:first)
      assert_match(/Error: note is a command; check takes jobs/, results.first.last)
    end
  end

  def test_check_takes_job_names
    in_project do |root|
      code, stdout, = cli_in(root, "check", "numbers", "4")

      assert_equal [0, "numbers: job \"numbers\" OK"], [code, stdout.lines.first.chomp]
    end
  end

  def test_job_selection_applies_to_files_only
    in_project do |root|
      code, _stdout, stderr = cli_in(root, "run", "-j", "x", "numbers")

      assert_equal 2, code
      assert_match(/Error: --job selects in a file; numbers is a name/, stderr)
    end
  end

  def test_builtins_and_paths_never_load_the_metacrunchfile
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nraise \"must not be loaded\"\n")
      results = [
        cli_in(root, "run", job("double.rb"), stdin: "1\n"), cli_in(root, job("double.rb"), stdin: "1\n"),
        cli_in(root, "check", job("double.rb")), cli_in(root, "--version"), cli_in(root, "help", "run")
      ]

      assert_equal [0] * 5, results.map(&:first)
      assert(results.none? { it.last.include?("must not be loaded") })
    end
  end

  def test_commands_run_by_path
    in_project("tools/release.rb" => TOOL) do |root|
      code, _stdout, stderr = cli_in(File.join(root, "jobs"), "run", File.join(root, "tools", "release.rb"))
      greeting = cli_in(root, job("greet.rb"), "--name", "Ada")

      assert_equal [0, 0], [code, greeting.first]
      assert_match(/INFO  note: from tools/, stderr)
      assert_match(/INFO  hello, Ada/, greeting.last)
    end
  end

  def test_a_name_wins_over_a_file_of_that_name
    in_project("note" => "Metacrunch.job { source [1] }\n") do |root|
      code, stdout, stderr = cli_in(root, "note", "x")

      assert_equal [0, ""], [code, stdout]
      assert_match(/INFO  note: x/, stderr)
    end
  end

  private

  # Yields the root of a temporary project with FILES and extra; every file
  # gets the magic comment.
  def in_project(extra = {})
    in_tmpdir do |root|
      FILES.merge(extra).each { |path, code| write_file(root, path, "# frozen_string_literal: true\n\n#{code}") }
      yield root
    end
  end

  # Runs the CLI in dir. cli passes env: {}, so ~/.metacrunch is never read.
  def cli_in(dir, *args, **options) = Dir.chdir(dir) { cli(*args, **options) }

end
```

Update the existing tests:

In `test/cli/cli_test.rb`, replace `USAGE_ERRORS` (these run in the repository, which has no `Metacrunchfile` above it):

```ruby
  USAGE_ERRORS = {
    [] => "no command, job or file given",
    ["frobnicate"] => "unknown command, job or file: frobnicate (no Metacrunchfile found)",
    ["-v"] => "unknown option -v",
    ["help", "frobnicate"] => "unknown command, job or file: frobnicate (no Metacrunchfile found)"
  }.freeze
```

and in `test_prints_the_usage` and `test_help_for_a_command`:

```ruby
    assert_match(/Usage: metacrunch COMMAND \[OPTIONS\] NAME\|FILE/, stdout)
    assert_match(/^  run +Run a job or command$/, stdout)
```

```ruby
    assert_match(/Usage: metacrunch run \[OPTIONS\] NAME\|FILE/, stdout)
```

In `test/cli/run_test.rb`, `test_usage_errors_are_explained_on_stderr`:

```ruby
    assert_match(/Usage: metacrunch run \[OPTIONS\] NAME\|FILE/, stderr)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/cli/project_cli_test.rb test/cli/cli_test.rb test/cli/run_test.rb`
Expected: FAIL: names are "unknown command or job file", the usage texts are the old ones.

- [ ] **Step 3: Write ProjectLookup**

`lib/metacrunch/cli/project_lookup.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # Finds the project of the working directory and loads it, at most once
    # per call and only when a name needs it. The commands of one call
    # share it, so its warnings appear once.
    class ProjectLookup

      def initialize
        @loaded = false
        @project = nil
      end

      # The project, or nil without Metacrunchfile. Raises ProjectError if
      # the Metacrunchfile fails. logger, unless nil, gets a warning for
      # each file that did not load, and with -v the whole error.
      def project(logger)
        return @project if @loaded

        file = Project.find(Dir.pwd)
        @project = file && Project.load_file(file)
        @loaded = true
        log_load_errors(logger) if logger && @project
        @project
      end

      private

      def log_load_errors(logger)
        @project.load_errors.each do |file, error|
          logger.warn("#{@project.load_error_summary(file, error)} (-v for details)")
          logger.debug(error.full_message(highlight: false))
        end
      end

    end
  end
end
```

- [ ] **Step 4: Dispatch names and list the project in the help**

Replace `lib/metacrunch/cli.rb`:

```ruby
# frozen_string_literal: true

require "optparse"
require_relative "../metacrunch"
require_relative "progress"
require_relative "trace"
require_relative "credentials/editor"
require_relative "cli/project_lookup"
require_relative "cli/command"
require_relative "cli/job_command"
require_relative "cli/run"
require_relative "cli/check"
require_relative "cli/trace"
require_relative "cli/new"
require_relative "cli/credentials"

module Metacrunch
  # The command line interface. Dispatches to a command by the first
  # argument; a job or command there, by name or file, is short for `run`.
  # #run returns the exit code, exe/metacrunch exits with it.
  class Cli

    EXIT_CODES = {ok: 0, aborted: 1, usage: 2, ok_with_failures: 3}.freeze
    COMMANDS = {
      "run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand,
      "credentials" => CredentialsCommand
    }.freeze

    # The streams and environment the commands use instead of globals.
    Streams = Data.define(:stdin, :stdout, :stderr, :env)

    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV)
      @streams = Streams.new(stdin:, stdout:, stderr:, env:)
      @lookup = ProjectLookup.new
    end

    def run(argv)
      first, *rest = argv
      case first
      when nil then usage_error("no command, job or file given")
      when "-h", "--help" then show(usage)
      when "--version" then show(VERSION)
      when "help" then help(rest.first)
      when *COMMANDS.keys then command(first).run(rest)
      else other(first, argv)
      end
    end

    private

    # An option, or a job or command by name or file: short for run.
    def other(first, argv)
      return usage_error("unknown option #{first}") if first.start_with?("-")
      return command("run").run(argv) if runnable?(first)

      usage_error(unknown(first))
    rescue ProjectError => e
      usage_error(e.message)
    end

    def help(name)
      return show(usage) if name.nil? || name == "help"
      return command(name).run(["--help"]) if COMMANDS.key?(name)
      return command("run").run([name, "--help"]) if runnable?(name)

      usage_error(unknown(name))
    rescue ProjectError => e
      usage_error(e.message)
    end

    # A file given by path; else a name of the project, which wins over a
    # file of that name. Paths never load the project.
    def runnable?(target)
      return File.file?(target) if Names.path?(target)

      project&.include?(target) || File.file?(target)
    end

    def unknown(target)
      return "unknown command, job or file: #{target}" if Names.path?(target)

      hint = project ? project.load_hint : " (no #{Project::FILE} found)"
      "unknown command, job or file: #{target}#{hint}"
    end

    # The project of the working directory. Its files that did not load
    # give warnings on stderr, once per call.
    def project = @lookup.project(Metacrunch.build_logger(@streams.stderr))

    def command(name)
      COMMANDS.fetch(name).new(@streams, @lookup)
    end

    def usage
      width = [*COMMANDS.keys, "help"].map(&:size).max
      commands = COMMANDS.map { |name, command| "  #{name.ljust(width)} #{command::SUMMARY}" }
      commands << "  #{"help".ljust(width)} Show the help of a command, job or file"
      text = <<~TEXT
        Usage: metacrunch COMMAND [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]
               metacrunch NAME|FILE [PARAMS...] [ARGS...]    (same as run)

        Commands:
        #{commands.join("\n")}

        Options:
          -h, --help     Show this help
              --version  Show the version
      TEXT
      [text, *project_help].join("\n")
    end

    # The jobs and commands of the project and the files that did not load,
    # or the error of the Metacrunchfile. No warnings: the list shows the
    # files.
    def project_help
      project = @lookup.project(nil)
      project ? project_sections(project) : []
    rescue ProjectError => e
      ["Project:\n  #{e.message.lines.first.chomp}\n"]
    end

    def project_sections(project)
      names = project.names
      width = names.map(&:size).max
      jobs, commands = names.partition { project.declared(it).first.is_a?(Job) }
      errors = project.load_errors.map { |file, error| "  #{project.load_error_summary(file, error)}" }
      [
        (section("Jobs (#{project.root})", jobs.map { entry(project, it, width) }) if jobs.any?),
        (section("Project commands (#{project.root})", commands.map { entry(project, it, width) }) if commands.any?),
        (section("Not loaded", errors) if errors.any?)
      ].compact
    end

    def section(title, lines) = "#{title}:\n#{lines.join("\n")}\n"

    def entry(project, name, width)
      declarations = project.declared(name)
      desc = declarations.one? ? declarations.first.desc : "(declared more than once, unusable)"
      "  #{name.ljust(width)}  #{desc}".rstrip
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

`rescue ProjectError` in `other` and `help` catches only a failing `Metacrunchfile` in `runnable?`: `Command#run` handles the errors of the command itself (Step 5).

- [ ] **Step 5: Give the commands the lookup**

In `lib/metacrunch/cli/command.rb`:

```ruby
      def initialize(streams, lookup)
        @stdin = streams.stdin
        @stdout = streams.stdout
        @stderr = streams.stderr
        @env = streams.env
        @lookup = lookup
        @log_level = Logger::INFO
        @help = false
      end
```

and add `ProjectError` to the first `rescue` of `run`:

```ruby
      rescue OptionParser::ParseError, JobLoadError, ParamError, UsageError, ProjectError => e
        usage_error(e.message)
```

Update the class comment: "Subclasses define NAME, SUMMARY, USAGE, #define_options and #execute; lookup is the Cli's ProjectLookup."

In `lib/metacrunch/cli/trace.rb` and `lib/metacrunch/cli/new.rb`, change `def initialize(streams)` to:

```ruby
      def initialize(streams, lookup)
```

(the bodies keep their bare `super`, which passes both arguments on).

- [ ] **Step 6: Resolve targets through the Invoker**

Replace `lib/metacrunch/cli/job_command.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # A command that takes a job or command by name or file (run, check,
    # trace). Options before it belong to the command, everything after it
    # to the job or command. Subclasses implement #execute_job(job, argv);
    # run also #execute_command(command, argv).
    class JobCommand < Command

      HELP_OPTIONS = ["-h", "--help"].freeze

      private

      def define_options(parser)
        parser.separator("Options go before NAME|FILE; everything after it is passed on.")
        parser.separator("\"metacrunch #{self.class::NAME} NAME|FILE --help\" shows its parameters.")
        parser.separator("")
        parser.on("-j", "--job NAME", "Select a job or command in a file that declares several") { @job_name = it }
        parser.on("-q", "--quiet", "Log warnings and errors only") { @log_level = Logger::WARN }
        parser.on("-v", "--verbose", "Log debug messages too") { @log_level = Logger::DEBUG }
        credentials_options(parser, "Credentials directory (default: METACRUNCH_CREDENTIALS,",
                            "then .metacrunch/ above the Metacrunchfile for a name or above the file,",
                            "then ~/.metacrunch/)")
      end

      def execute(argv)
        @target = argv.shift
        raise UsageError, "no job, command or file given" unless @target

        declaration, @anchor = invoker.resolve(@target, select: @job_name)
        check_target!(declaration)
        schema = requested_help(declaration, argv)
        return show(help_text(declaration, schema)) if schema
        return execute_command(declaration, argv) if declaration.is_a?(Command)

        execute_job(declaration, argv)
      end

      # check and trace take jobs only; run overrides this.
      def check_target!(declaration)
        return unless declaration.is_a?(Command)

        raise UsageError, "#{@target} is a command; #{self.class::NAME} takes jobs"
      end

      # Describes the job or command (evaluates its recipe up to the first
      # statement) only if -h or --help appears before "--"; its own parser
      # then decides, so -h as the value of another option does not count.
      def requested_help(declaration, argv)
        return unless argv.take_while { it != "--" }.intersect?(HELP_OPTIONS)

        schema = declaration.describe
        schema if schema.help_requested?(argv)
      end

      def help_text(declaration, schema)
        params = declaration.is_a?(Command) ? "[PARAMS...]" : "[JOB_PARAMS...]"
        args = schema.args_definition ? " #{schema.args_definition.name.to_s.upcase}..." : ""
        desc = declaration.desc ? "#{declaration.desc}\n\n" : ""
        "Usage: metacrunch #{self.class::NAME} #{@target} #{params}#{args}\n\n#{desc}#{schema.help}"
      end

      # Runs jobs and commands with this call's environment, credentials
      # options, logger and streams. Names resolve in the project of the
      # working directory, which is loaded when a name first needs it.
      def invoker
        @invoker ||= Invoker.new(
          project: -> { @lookup.project(logger) }, logger:, env: @env, stdin: @stdin, stdout: @stdout,
          environment: @environment, credentials: @credentials, progress: progress_factory
        )
      end

      # A callable that gets whether records go to stdout and returns a
      # progress display or nil; only run shows progress.
      def progress_factory = nil

      # Evaluates the recipe with the job's arguments. Credentials are read
      # only if a parameter needs them.
      def build_pipeline(job, argv) = invoker.pipeline(job, argv, anchor: @anchor)

    end
  end
end
```

In `lib/metacrunch/cli/check.rb`, replace both `@job_file` with `@target`.

- [ ] **Step 7: Run commands with run**

Replace `lib/metacrunch/cli/run.rb`:

```ruby
# frozen_string_literal: true

require "etc"

module Metacrunch
  class Cli
    # metacrunch run: runs a job or a command. A job without source reads
    # JSON Lines from stdin, a job without sink writes them to stdout.
    class RunCommand < JobCommand

      NAME = "run"
      SUMMARY = "Run a job or command"
      USAGE = "run [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]"
      # The options that apply to jobs only, as the usage error names them;
      # -w is kept apart in @workers.
      JOB_OPTIONS = {input: "-i", output: "-o", rejects: "--rejects", errors: "--errors", limit: "-n",
                     on_error: "--on-error", max_errors: "--max-errors", stats: "--stats"}.freeze

      def initialize(streams, lookup)
        super
        @options = {}
      end

      private

      def define_options(parser)
        super
        parser.on("--[no-]progress", "Show progress on stderr (default: if stderr is a terminal)") { @progress = it }
        parser.separator("")
        parser.separator("For jobs only:")
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
        parser.on("-w", "--workers N", "Run the steps in N processes; auto: one per core but one") do |value|
          @workers = worker_count(value)
        end
        parser.on("--stats PATH", "Write status and stats as JSON to PATH (- for stdout)") { @options[:stats] = it }
      end

      def check_target!(declaration)
        return unless declaration.is_a?(Command)

        given = @options.keys.map { JOB_OPTIONS.fetch(it) }
        given << "-w" if @workers
        raise UsageError, "#{@target} is a command; #{given.first} applies to jobs" if given.any?
      end

      def execute_job(job, argv)
        options = RunOptions.new(**@options)
        result = invoker.run_job(job, argv, anchor: @anchor, options:, workers: @workers)
        write_stats(options.stats, result) if options.stats
        EXIT_CODES.fetch(result.status)
      end

      # Invalid parameters of the command itself raise ParamError here, which
      # Command#run turns into exit status 2. Then the body runs.
      def execute_command(command, argv)
        finish(invoker.prepare(command, argv, anchor: @anchor))
      end

      # 0, or 3 if an invoked job ended with failed records, or aborted and
      # the body went on; 1 if an exception left the body. An InvokeError is
      # logged as its message, since the job logged its error already.
      # Signals pass on to Command#run.
      def finish(prepared)
        invoker.call(prepared)
        EXIT_CODES.fetch(invoker.finished_status)
      rescue InvokeError => e
        logger.error(e.message)
        EXIT_CODES[:aborted]
      rescue *Engine::RECOVERABLE => e
        logger.error(e.full_message(highlight: false))
        EXIT_CODES[:aborted]
      end

      def progress_factory = method(:progress)

      # The value of --workers as a number of processes.
      def worker_count(value)
        count = value == "auto" ? Executor.auto_workers : Integer(value, 10, exception: false)
        raise UsageError, "--workers must be a positive number or auto" unless count&.positive?
        if count > 1 && !Executor::Fork.supported?
          raise UsageError, "--workers needs Process.fork, which this platform lacks"
        end

        count
      end

      # A status line if stderr is a terminal, log lines with --progress
      # otherwise. Off by default with -q, and when records go to stdout on
      # the same terminal, where the line would mix with them.
      def progress(records_to_stdout)
        enabled = @progress
        enabled = default_progress?(records_to_stdout) if enabled.nil?
        return unless enabled

        Progress.new(log_output, mode: @stderr.tty? ? :line : :log)
      end

      def default_progress?(records_to_stdout)
        @stderr.tty? && @log_level < Logger::WARN && !(records_to_stdout && @stdout.tty?)
      end

      def log_output
        @log_output ||= Progress::Output.new(@stderr)
      end

      def write_stats(path, result)
        error = result.error && {"class" => result.error.class.name, "message" => result.error.message}
        json = JSON.pretty_generate({"status" => result.status, "error" => error, "stats" => result.stats.to_h})
        path == JsonLines::STDIO ? @stdout.puts(json) : File.write(path, "#{json}\n")
      end

    end
  end
end
```

`report` moved to `Invoker#report` in Task 4; the run of a job named or given by path logs exactly as before (no label for the target itself).

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/cli/*_test.rb`
Expected: PASS (`project_cli_test.rb`: 23 runs)

- [ ] **Step 9: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 10: Commit**

```bash
git add lib/metacrunch/cli.rb lib/metacrunch/cli/project_lookup.rb lib/metacrunch/cli/command.rb \
        lib/metacrunch/cli/job_command.rb lib/metacrunch/cli/run.rb lib/metacrunch/cli/check.rb \
        lib/metacrunch/cli/trace.rb lib/metacrunch/cli/new.rb \
        test/cli/project_cli_test.rb test/cli/cli_test.rb test/cli/run_test.rb
git commit -m "$(cat <<'EOF'
Run jobs and commands by name on the command line

metacrunch NAME is short for run NAME; run, check and trace take a name
or a file, and run also runs commands through the Invoker. The project is
loaded only when a name needs it, once per call, with one warning per
file that did not load. --help lists the project's jobs and commands,
names declared twice and files that did not load. Job options with a
command, and commands for check and trace, are usage errors. A command
exits with 0, 1, 2, 3 or by the signal that stopped it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 6: Testing commands with Testing.invoke

**Files:**
- Modify: `lib/metacrunch/testing.rb`
- Test: `test/unit/testing_invoke_test.rb`

**Interfaces:**
- Consumes: `Command#prepare`, `Command::Prepared` (Task 2); `Project#fetch`, `#include?` (Task 3); `Invoker` and its private hooks `invoke_job`, `invoke_command`, `track`, `aborted!`, constant `STATUSES`, `#call`, `#status`, `#finished_status` (Task 4); `Metacrunch::Result`, `Metacrunch::Stats`.
- Produces:
  - `Metacrunch::Testing.invoke(project, name, params: {}, stubs: {}, logger: Logger.new(nil)) -> Testing::CommandRun`
  - `Testing::Invocation = Data.define(:name, :argv, :options)` (`options`: `{workers:, limit:}` as given, without nils)
  - `Testing::CommandRun = Data.define(:value, :status, :error, :invoked)`
  - `Testing::EMPTY_STATS` (a `Stats` with all counts 0)
  - `Testing::RecordingInvoker < Invoker` (`#invoked`)

- [ ] **Step 1: Write the failing tests**

`test/unit/testing_invoke_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "metacrunch/testing"

class TestingInvokeTest < Minitest::Test

  Invocation = Metacrunch::Testing::Invocation

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "jobs/a2c.rb" => <<~RUBY,
      Metacrunch.job "a2c" do
        params { param :api_key, String, credential: "catalog.api_key", required: true }

        source raise("a2c must not run")
      end
    RUBY
    "commands/es.rb" => "Metacrunch.command(\"es:switch-alias\") { run { raise \"must not run\" } }\n",
    "commands/reindex.rb" => <<~RUBY,
      Metacrunch.command "catalog:reindex" do
        params do
          param :alias, String, default: "catalog"
          param :api_key, String, credential: "catalog.api_key"
          args :files, min: 1
        end

        run do
          result = invoke "a2c", "--index", "new", *params.files, workers: 4
          next :kept unless result.ok?

          invoke "es:switch-alias", "--to", "new", params.alias
          :switched
        end
      end
    RUBY
    "commands/tolerant.rb" => <<~RUBY,
      Metacrunch.command "tolerant" do
        run do
          invoke "a2c"
        rescue Metacrunch::InvokeError
          :rescued
        end
      end
    RUBY
    "commands/typo.rb" => "Metacrunch.command(\"typo\") { run { invoke \"a2x\" } }\n"
  }.freeze

  def setup
    @root = File.realpath(Dir.mktmpdir("metacrunch-test"))
    FILES.each { |path, code| write(path, "# frozen_string_literal: true\n\n#{code}") }
    # Unreadable credentials: any attempt to read them would raise.
    write(".metacrunch/credentials.yml.enc", "garbage")
    @project = Metacrunch.load_project(@root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_records_invokes_without_running_them
    run = invoke("catalog:reindex", params: {files: ["a.xml"]})

    assert_equal [:switched, :ok, nil], [run.value, run.status, run.error]
    assert_equal [Invocation.new(name: "a2c", argv: ["--index", "new", "a.xml"], options: {workers: 4}),
                  Invocation.new(name: "es:switch-alias", argv: ["--to", "new", "catalog"], options: {})],
                 run.invoked
  end

  def test_a_status_stub_changes_what_the_command_does
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => :ok_with_failures})

    assert_equal [:kept, :ok_with_failures, ["a2c"]], [run.value, run.status, run.invoked.map(&:name)]
  end

  def test_result_stubs
    result = Metacrunch::Result.new(status: :ok_with_failures, error: nil, stats: Metacrunch::Testing::EMPTY_STATS)
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => result})

    assert_equal :kept, run.value
  end

  def test_callable_stubs_get_the_arguments
    seen = []
    record = lambda do |argv|
      seen << argv
      :ok
    end
    run = invoke("catalog:reindex", params: {files: ["a.xml"]},
                                    stubs: {"a2c" => record, "es:switch-alias" => ->(_argv) { :ignored }})

    assert_equal [:switched, [["--index", "new", "a.xml"]]], [run.value, seen]
  end

  def test_a_stubbed_abort_raises_like_a_real_one
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => :aborted})

    assert_equal [:aborted, Metacrunch::InvokeError], [run.status, run.error.class]
    assert_equal "a2c aborted: RuntimeError: stubbed abort", run.error.message
  end

  def test_a_rescued_abort_finishes_with_failures
    run = invoke("tolerant", stubs: {"a2c" => :aborted})

    assert_equal [:rescued, :ok_with_failures], [run.value, run.status]
  end

  def test_unknown_names_in_the_body_fail_the_run
    run = invoke("typo")

    assert_equal :aborted, run.status
    assert_equal "invoke a2x: unknown command, job or file: a2x", run.error.message
  end

  def test_stubs_for_unknown_names_raise
    error = assert_raises(ArgumentError) { invoke("typo", stubs: {"a2x" => :ok}) }

    assert_equal "stub for unknown job or command: a2x", error.message
  end

  def test_stubs_for_jobs_must_give_a_status_or_a_result
    run = invoke("catalog:reindex", params: {files: ["a.xml"]}, stubs: {"a2c" => "ok"})

    assert_equal "the stub for a2c must give a status Symbol or a Result, got \"ok\"", run.error.message
  end

  def test_params_are_bound_from_a_hash
    assert_raises(Metacrunch::ParamError) { invoke("catalog:reindex") }
  end

  def test_jobs_are_tested_with_testing_run
    error = assert_raises(ArgumentError) { invoke("a2c") }

    assert_equal "a2c is a job; test it with Testing.run", error.message
  end

  private

  def invoke(name, **) = Metacrunch::Testing.invoke(@project, name, **)

  def write(path, content)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end

end
```

The garbage credentials file and the `credential:` parameters of `a2c` and `catalog:reindex` show that credentials are never read: `bind_hash` does not ask them, and invoked jobs are not run.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/testing_invoke_test.rb`
Expected: FAIL with `NameError: uninitialized constant Metacrunch::Testing::Invocation`

- [ ] **Step 3: Write Testing.invoke**

In `lib/metacrunch/testing.rb`, add after `Result = Data.define(...)`:

```ruby
    # One invoke recorded by Testing.invoke. options: workers: and limit:
    # as given.
    Invocation = Data.define(:name, :argv, :options)

    # value: what the body returned. status: :ok, :ok_with_failures (an
    # invoked job ended with failed records, or aborted and the body went
    # on) or :aborted (an exception left the body; error holds it).
    CommandRun = Data.define(:value, :status, :error, :invoked)

    EMPTY_STATS = Stats.new(read: 0, written: 0, filtered: 0, rejected: {}, marked: {}, failed: {}, steps: {},
                            duration: 0.0)

    # Records invokes instead of running them and answers from stubs: a
    # status Symbol or a Result for a job, any value for a command, or a
    # callable that gets argv and returns one of these. Without a stub a
    # job ends :ok and a command returns nil. Names resolve as in a real
    # run, so unknown names raise InvokeError.
    class RecordingInvoker < Invoker

      attr_reader :invoked

      def initialize(project:, stubs:, logger:)
        super(project:, logger:, env: {}, stdin: nil, stdout: nil)
        @stubs = stubs.transform_keys(&:to_s)
        @invoked = []
      end

      private

      # ** takes the anchor:, which a recording needs no more than the
      # declaration itself.
      def invoke_job(_job, argv, target:, workers:, limit:, **)
        @invoked << Invocation.new(name: target, argv:, options: {workers:, limit:}.compact)
        result = job_result(target, answer(target, argv, :ok))
        track(result.status)
        aborted!(result, target)
        result
      end

      def invoke_command(_command, argv, target:, **)
        @invoked << Invocation.new(name: target, argv:, options: {})
        answer(target, argv, nil)
      end

      def answer(target, argv, default)
        stub = @stubs.fetch(target, default)
        stub.respond_to?(:call) ? stub.call(argv) : stub
      end

      def job_result(target, stub)
        case stub
        when Metacrunch::Result then stub
        when *STATUSES
          error = stub == :aborted ? RuntimeError.new("stubbed abort") : nil
          Metacrunch::Result.new(status: stub, error:, stats: EMPTY_STATS)
        else
          raise ArgumentError, "the stub for #{target} must give a status Symbol or a Result, got #{stub.inspect}"
        end
      end

    end
```

`Metacrunch::Result` is spelled out: inside `Testing`, `Result` is `Testing::Result`.

After `def run(...) ... end`, add:

```ruby
    # Runs the body of the command name of project with params bound as a
    # Hash, like run does (no environment, no credentials). Every invoke in
    # the body is recorded and answered from stubs (name => status Symbol,
    # Result, value, or callable that gets argv) instead of run; see
    # RecordingInvoker. A stub for a name the project does not know raises
    # ArgumentError, as does a job name for name.
    def invoke(project, name, params: {}, stubs: {}, logger: Logger.new(nil))
      command = project.fetch(name)
      raise ArgumentError, "#{name} is a job; test it with Testing.run" unless command.is_a?(Command)

      unknown = stubs.keys.map(&:to_s).reject { project.include?(it) || File.file?(it) }
      raise ArgumentError, "stub for unknown job or command: #{unknown.first}" if unknown.any?

      invoker = RecordingInvoker.new(project:, stubs:, logger:)
      command_run(invoker, command.prepare(binder: ->(schema) { schema.bind_hash(params) }))
    end

    def command_run(invoker, prepared)
      value = invoker.call(prepared)
      CommandRun.new(value:, status: invoker.finished_status, error: nil, invoked: invoker.invoked)
    rescue *Engine::RECOVERABLE => e
      CommandRun.new(value: nil, status: :aborted, error: e, invoked: invoker.invoked)
    end
    private_class_method :command_run
```

`module_function` makes `command_run` a public module method; `private_class_method` hides it again.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/testing_invoke_test.rb`
Expected: PASS (11 runs)

- [ ] **Step 5: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch/testing.rb test/unit/testing_invoke_test.rb
git commit -m "$(cat <<'EOF'
Test commands with Testing.invoke

Testing.invoke runs a command's body with params bound from a Hash and
records every invoke instead of running it. Stubs answer per name with a
status, a Result, a value or a callable; a stubbed abort raises like a
real one. Unknown names fail as in a real run, stubs for unknown names
raise at once, and credentials are never read.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 7: Chains end to end through exe/metacrunch

**Files:**
- Test: `test/cli/exe_project_test.rb`

**Interfaces:**
- Consumes: everything of Tasks 1–5; `CredentialsHelper` (`in_tmpdir`, `write_file`, `write_credentials`, `SECRET`, `SECRET_JOB`).
- Produces: no code; spec section 10.3 and success criteria 1, 2 and 5 checked in real processes.

These tests should pass at once: they pin down behavior that Tasks 4 and 5 built, in separate processes with real signals. If one fails, fix the code of the task it points to, not the test.

- [ ] **Step 1: Write the tests**

`test/cli/exe_project_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"

class ExeProjectTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"commands/*.rb\"\n",
    "lib/marker_sink.rb" => <<~RUBY,
      # Writes each record on a line of its own at once, and "closed" when
      # it is closed.
      class MarkerSink

        def initialize(path)
          @path = path
        end

        def open(_context)
          @file = File.open(@path, "w")
          @file.sync = true
        end

        def write(record)
          @file.puts(record)
        end

        def close
          @file.puts("closed")
          @file.close
        end

      end
    RUBY
    "jobs/numbers.rb" => <<~RUBY,
      Metacrunch.job "numbers" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        map { 100 / it }
        on_error(params.skip ? :skip : :abort)
      end
    RUBY
    "jobs/forever.rb" => <<~RUBY,
      require_relative "../lib/marker_sink"

      Metacrunch.job "forever" do
        params { param :output, String, required: true }

        source((1..).lazy)
        sink MarkerSink.new(params.output)
      end
    RUBY
    "commands/note.rb" => <<~RUBY,
      Metacrunch.command "note" do
        params { args :text, min: 1, max: 1 }

        run { File.write(root.join("note.txt"), params.text.first) }
      end
    RUBY
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain" do
        params do
          param :skip, :bool, default: false
          args :numbers
        end

        run do
          invoke "numbers", *(params.skip ? ["--skip"] : []), *params.numbers
          invoke "note", "done"
        end
      end
    RUBY
    "commands/watch.rb" => <<~RUBY
      Metacrunch.command "watch" do
        params { args :output, min: 1, max: 1 }

        run do
          invoke "forever", "--output", params.output.first
          invoke "note", "after"
        end
      end
    RUBY
  }.freeze

  # A command shipped by a gem, outside the project; it reads a credential
  # and invokes a job of the project that reads the same credential.
  GEM_COMMAND = <<~'RUBY'
    Metacrunch.command "secret:check" do
      params { param :api_key, String, credential: "catalog.api_key", required: true }

      run do
        logger.info("command: #{params.api_key.reverse}")
        invoke "secret"
      end
    end
  RUBY

  def test_a_chain_from_a_subdirectory_exits_with_0_1_and_3
    in_project do |root|
      jobs = File.join(root, "jobs")
      ok = metacrunch("chain", "4", chdir: jobs, home: root)
      noted = File.read(File.join(root, "note.txt"))
      File.delete(File.join(root, "note.txt"))
      aborted = metacrunch("chain", "0", chdir: jobs, home: root)
      partial = metacrunch("chain", "--skip", "0", "4", chdir: jobs, home: root)

      assert_equal [0, 1, 3], [ok, aborted, partial].map { it.last.exitstatus }
      assert_equal ["25\n", "done", "25\n"], [ok.first, noted, partial.first]
      assert_match(/ERROR numbers aborted: Metacrunch::StepError/, aborted[1])
    end
  end

  def test_sigterm_during_an_invoked_job_closes_its_sink_and_ends_the_chain
    in_project do |root|
      output = File.join(root, "forever.txt")
      pid = Process.spawn(env(root), *command("watch", output), chdir: root, out: File::NULL, err: File::NULL)
      status = nil
      begin
        wait_for { File.size?(output) }
        Process.kill("TERM", pid)
        _pid, status = Process.wait2(pid)
      ensure
        stop(pid) unless status
      end

      assert_equal Signal.list.fetch("TERM"), status.termsig
      assert_equal "closed", File.readlines(output, chomp: true).last
      refute_path_exists File.join(root, "note.txt")
    end
  end

  def test_production_credentials_reach_a_gem_command_and_the_job_it_invokes
    in_tmpdir do |dir|
      root = File.join(dir, "project")
      glob = File.join(dir, "gem", "commands", "*.rb")
      write_ruby(dir, "gem/commands/secret.rb", GEM_COMMAND)
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files #{glob.inspect}, \"jobs/*.rb\"\n")
      write_file(root, "jobs/secret.rb", SECRET_JOB.sub("Metacrunch.job do", "Metacrunch.job \"secret\" do"))
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      jobs = File.join(root, "jobs")
      stdout, stderr, status = metacrunch("run", "-e", "production", "secret:check", chdir: jobs, home: dir)

      assert_equal [0, "\"#{SECRET.reverse}\"\n" * 2], [status.exitstatus, stdout], stderr
      assert_match(/INFO  command: #{SECRET.reverse}/, stderr)
    end
  end

  private

  # Yields the root of a temporary project with FILES.
  def in_project
    in_tmpdir do |root|
      FILES.each { |path, code| write_ruby(root, path, code) }
      yield root
    end
  end

  def write_ruby(root, path, code) = write_file(root, path, "# frozen_string_literal: true\n\n#{code}")

  def metacrunch(*args, chdir:, home:)
    Open3.capture3(env(home), *command(*args), chdir:)
  end

  def command(*args)
    [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *args]
  end

  # HOME points into the test's directory, so ~/.metacrunch is never read.
  def env(home) = CLEAN_ENV.merge("HOME" => home)

  def wait_for(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  # Kills and reaps pid, which the test has not reaped yet, so a failing
  # test leaves no endless process behind.
  def stop(pid)
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

end
```

`SECRET_JOB` writes the reversed secret twice to stdout (`source [1, 2]`); it is unnamed, so the test names it `secret`. The gem command logs the reversed secret, so neither output contains the secret itself.

- [ ] **Step 2: Run the tests**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/exe_project_test.rb`
Expected: PASS (3 runs)

- [ ] **Step 3: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 4: Commit**

```bash
git add test/cli/exe_project_test.rb
git commit -m "$(cat <<'EOF'
Test chains of commands and jobs through exe/metacrunch

A chain started from a subdirectory exits with 0, 1 and 3; SIGTERM
during an invoked job closes its sink and ends the chain by the signal;
-e production reaches a gem command and the job it invokes, both reading
the credentials of the project root.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 8: The example project

**Files:**
- Create: `examples/project/Metacrunchfile`, `examples/project/jobs/catalog.rb`, `examples/project/commands/release.rb`, `examples/project/data/titles.jsonl`, `examples/project/data/broken.jsonl`, `examples/project/test/release_test.rb`, `examples/project/.gitignore`
- Modify: `examples/Readme.md`
- Modify: `test/integration/examples_test.rb`

**Interfaces:**
- Consumes: everything of Tasks 1–6.
- Produces: the project of spec section 11: job `catalog`, command `catalog:release` with `--input` and `--out`.

- [ ] **Step 1: Write the failing integration tests**

In `test/integration/examples_test.rb`, add `require "fileutils"` to the requires, give `metacrunch` a working directory:

```ruby
  def metacrunch(*, stdin_data: "", env: {}, chdir: Dir.pwd)
    Open3.capture3(CLEAN_ENV.merge(env), *command(*), stdin_data:, chdir:)
  end
```

and add these tests after `test_the_example_tests_pass`:

```ruby
  def test_project_release_switches_current_only_after_a_clean_run
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project")
      FileUtils.cp_r(example("project"), project)
      _stdout, stderr, status = metacrunch("catalog:release", chdir: File.join(project, "jobs"))
      current = File.join(project, "out", "current", "titles.jsonl")
      released = File.readlines(current).size
      failed = metacrunch("catalog:release", "--input", File.join(project, "data", "broken.jsonl"), chdir: project)

      assert_equal [0, 4], [status.exitstatus, released], stderr
      assert_equal 3, failed.last.exitstatus
      assert_equal 4, File.readlines(current).size
    end
  end

  def test_project_help_lists_the_job_and_the_command
    stdout, stderr, status = metacrunch("--help", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_match(/^  catalog +Write the public titles into a directory$/, stdout)
    assert_match(%r{^  catalog:release +Write a new release and switch out/current to it$}, stdout)
  end

  def test_the_project_example_tests_pass
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), example("project/test/release_test.rb")]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end
```

Run: `bundle exec ruby -w -Ilib -Itest test/integration/examples_test.rb`
Expected: FAIL: `examples/project` does not exist.

- [ ] **Step 2: Write the example project**

`examples/project/Metacrunchfile`:

```ruby
# frozen_string_literal: true

# The project file: it names the jobs and commands of this directory, so
# that `metacrunch NAME` runs them from any directory below it.
#
#   cd examples/project
#   bundle exec metacrunch --help
#   bundle exec metacrunch catalog:release
#   bundle exec ruby -I../../lib test/release_test.rb
Metacrunch.load_files "jobs/*.rb", "commands/*.rb"
```

`examples/project/jobs/catalog.rb`:

```ruby
# frozen_string_literal: true

# Writes the public titles of a JSON Lines file to DIR/titles.jsonl. A
# record without a title fails; on_error :skip lets the run go on, and it
# ends with failed records (exit status 3).
#
#   cd examples/project
#   bundle exec metacrunch catalog --help
#   mkdir -p ../../tmp && bundle exec metacrunch catalog --output ../../tmp
Metacrunch.job "catalog", desc: "Write the public titles into a directory" do
  params do
    param :output, String, required: true, desc: "Directory for titles.jsonl; must exist"
    param :input, String, default: File.expand_path("../data/titles.jsonl", __dir__),
                          desc: "JSON Lines with title records"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  reject("Not public") { !it["public"] }
  map { |record| {"id" => record["id"], "title" => record.fetch("title")} }
  sink Metacrunch::JsonLines::Writer.new(File.join(params.output, "titles.jsonl"))
  on_error :skip
end
```

`examples/project/commands/release.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"

# Writes a new release of the catalog into out/releases/TIME/ and points
# out/current at it, but only if the job ended :ok. It is the pattern of
# loading a new search index and switching an alias, with directories and
# a symbolic link instead, so that it runs anywhere.
#
#   cd examples/project
#   bundle exec metacrunch catalog:release
#   bundle exec metacrunch catalog:release --input data/broken.jsonl    # exit status 3, out/current stays
Metacrunch.command "catalog:release", desc: "Write a new release and switch out/current to it" do
  params do
    param :input, String, desc: "JSON Lines with title records (default: the job's)"
    param :out, String, desc: "Directory for releases/ and current (default: out/ in the project)"
  end

  run do
    out = params.out ? Pathname(params.out) : root.join("out")
    release = out.join("releases", Time.now.strftime("%Y%m%d-%H%M%S-%L"))
    FileUtils.mkdir_p(release)
    input = params.input ? ["--input", params.input] : []
    result = invoke "catalog", "--output", release, *input
    next logger.warn("catalog:release: #{result.status}; out/current not switched") unless result.ok?

    # A new link renamed over the old one: the switch is atomic.
    link = out.join("current.new")
    FileUtils.rm_f(link)
    File.symlink(release.relative_path_from(out), link)
    File.rename(link, out.join("current"))
    logger.info("catalog:release: out/current is #{release.relative_path_from(out)}")
    release
  end
end
```

`examples/project/data/titles.jsonl`:

```
{"id":"t1","title":"Ruby in Practice","public":true}
{"id":"t2","title":"Metadata for Libraries","public":true}
{"id":"t3","title":"Internal Notes","public":false}
{"id":"t4","title":"Data Pipelines","public":true}
{"id":"t5","title":"Searching Catalogs","public":true}
```

`examples/project/data/broken.jsonl`:

```
{"id":"b1","title":"Complete Record","public":true}
{"id":"b2","public":true}
```

`examples/project/.gitignore`:

```
/out/
```

`examples/project/test/release_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the orchestration of catalog:release without running the job:
# Metacrunch::Testing.invoke records what the command invokes and answers
# with stubbed results.
#
#   bundle exec ruby -Ilib examples/project/test/release_test.rb

require "minitest/autorun"
require "tmpdir"
require "metacrunch"
require "metacrunch/testing"

class ReleaseTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load
    assert_empty PROJECT.load_errors
  end

  def test_switches_current_after_a_clean_run
    Dir.mktmpdir do |out|
      run = release(out)

      assert_equal [:ok, ["catalog"]], [run.status, run.invoked.map(&:name)]
      assert_equal ["--output", run.value.to_s], run.invoked.first.argv
      assert_equal File.realpath(run.value), File.realpath(File.join(out, "current"))
    end
  end

  def test_keeps_current_when_records_failed
    Dir.mktmpdir do |out|
      run = release(out, stubs: {"catalog" => :ok_with_failures})

      assert_equal :ok_with_failures, run.status
      refute_path_exists File.join(out, "current")
    end
  end

  private

  def release(out, stubs: {})
    Metacrunch::Testing.invoke(PROJECT, "catalog:release", params: {out:}, stubs:)
  end

end
```

- [ ] **Step 3: List the example**

In `examples/Readme.md`, add a row to the table after the `credentials/pseudonymize.rb` row:

```markdown
| [`project/`](project) | A project: its [`Metacrunchfile`](project/Metacrunchfile) names a job and a command, so `metacrunch NAME` runs them from any directory of the project. The command `catalog:release` invokes the job and switches `out/current` to the new release only after a clean run; [`project/test/release_test.rb`](project/test/release_test.rb) tests that with `Metacrunch::Testing.invoke`. |
```

and add to the command block, after the `credentials show` line:

```
$ (cd examples/project && bundle exec metacrunch --help)
$ (cd examples/project && bundle exec metacrunch catalog:release)
$ bundle exec ruby -Ilib examples/project/test/release_test.rb
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/integration/examples_test.rb`
Expected: PASS

Run: `bundle exec ruby -Ilib examples/project/test/release_test.rb`
Expected: `3 runs, ..., 0 failures, 0 errors`

Run the example by hand once and look at the result:

```bash
(cd examples/project && bundle exec metacrunch catalog:release && ls -l out && cat out/current/titles.jsonl)
rm -rf examples/project/out
```

Expected: exit status 0, a log line `catalog: ok: read 5, written 4, rejected 1 (Not public: 1) ...`, `out/current` pointing to `releases/...`, four titles.

- [ ] **Step 5: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean (it also checks the `.rb` files of the example).

- [ ] **Step 6: Commit**

```bash
git add examples/project examples/Readme.md test/integration/examples_test.rb
git commit -m "$(cat <<'EOF'
Add an example project with a job and a release command

examples/project has a Metacrunchfile, a catalog job and the command
catalog:release, which writes a new release and switches out/current to
it only after a clean run: the pattern of index and alias, with
directories and a link. Its test uses Testing.invoke; the integration
test runs the command from a subdirectory of a copy.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 9: Readme, CHANGELOG and final checks

**Files:**
- Modify: `Readme.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-10-13-metacrunch-ng-commands-design.md` (status)

**Interfaces:**
- Consumes: the behavior of Tasks 1–8.
- Produces: documentation only.

- [ ] **Step 1: Update the introduction and "A first job"**

In `Readme.md`, add to the list at the top, after the bullet that starts with "`metacrunch trace` shows":

```markdown
- A project's `Metacrunchfile` names its jobs and commands; `metacrunch NAME` runs them from any directory of the
  project, and commands chain jobs and other commands.
```

Replace the paragraph "A file can define several jobs, each with its own name (...); `-j NAME` selects one." with:

```markdown
A job can have a name and a one-line description: `Metacrunch.job "marc2es", desc: "MARCXML into the search index"
do ... end`. A name consists of parts of `a-z`, `0-9`, `_` and `-`, separated by `:` (`catalog:reindex`). A file can
define several jobs; `-j NAME` selects one. In a project, jobs run by name (see
[Projects and commands](#projects-and-commands)).
```

- [ ] **Step 2: Update "Credentials" and "Running jobs"**

In the "Credentials" section, bullet **Where:**, replace "else the nearest `.metacrunch/` above the job file," with:

```markdown
else the nearest `.metacrunch/` above the job file (for a job or command run by name: above the project's
`Metacrunchfile`),
```

In "Running jobs", replace the code block and the paragraph after it:

````markdown
```
$ metacrunch run [OPTIONS] NAME|JOB_FILE [JOB_PARAMS...] [ARGS...]
$ metacrunch NAME|JOB_FILE [JOB_PARAMS...] [ARGS...]      # short for run
$ metacrunch run jobs/marc2es.rb --help                     # the job's parameters
$ metacrunch marc2es --help                                 # the same, by name in a project
```

Options of `metacrunch` go before the job; everything after it belongs to the job. Use `--` before job arguments that
start with `-`. A job is given by its file or, in a project, by its name; an argument with `/` or `.` is always a
file. The CLI does not change the working directory: relative paths are relative to where you start it.
````

In the options table, replace the rows of `-j` and `--credentials`:

```markdown
| `-j`, `--job NAME` | Select a job or command in a file that declares several |
| `--credentials DIR` | Credentials directory (default: `METACRUNCH_CREDENTIALS`, then `.metacrunch/` above the job file or, for a name, above the `Metacrunchfile`, then `~/.metacrunch/`) |
```

and add after the table, before "A job file that starts with":

```markdown
The options from `-i` to `--stats` apply to jobs only; for a command (see
[Projects and commands](#projects-and-commands)) they are a usage error.
```

In the exit code table, replace the row of 2:

```markdown
| 2 | usage error (command, options, job file or name, parameters, `Metacrunchfile`; `check` found the job invalid) |
```

- [ ] **Step 3: Fix the advice on lookup tables for workers**

In "Workers", replace:

```markdown
  connections. Data that the workers only read, such as lookup tables, belongs at job level or in a `before` hook:
  the workers inherit it from the main process. Steps are opened after the `before` hooks, also without workers.
```

with:

```markdown
  connections. Data that the workers only read, such as lookup tables, belongs in a `before` hook: the workers
  inherit it from the main process, and `--help` does not build it (see [What runs when](#what-runs-when)). Steps
  are opened after the `before` hooks, also without workers.
```

- [ ] **Step 4: Add the Ruby API of projects**

In "Running jobs from Ruby", add to the end of the section:

````markdown
```ruby
project = Metacrunch.load_project                          # the nearest Metacrunchfile above Dir.pwd
project.names                                              # ["catalog:reindex", "marc2es", ...]
project.invoke("catalog:reindex", "dumps/a.xml")           # like invoke in a command
```

`project.invoke` returns a job's `Result` or a command's value and raises `Metacrunch::InvokeError` as `invoke` does
(see [Projects and commands](#projects-and-commands)). It takes `logger:`, `env:`, `stdin:` and `stdout:`.
````

- [ ] **Step 5: Add "Projects and commands" and "What runs when"**

Insert before `## Testing jobs`:

````markdown
## Projects and commands

A project names its jobs and commands in a `Metacrunchfile` at its root:

```ruby
# Metacrunchfile
Metacrunch.load_files "jobs/**/*.rb", "commands/**/*.rb"
```

```
project/
├── Metacrunchfile
├── .metacrunch/          credentials
├── jobs/marc2es.rb       Metacrunch.job "marc2es", desc: "..."
├── commands/catalog.rb   Metacrunch.command "catalog:reindex", desc: "..."
└── lib/
```

```
$ metacrunch marc2es --index test dumps/a.xml       # from any directory of the project
$ metacrunch catalog:reindex dumps/*.xml
$ metacrunch catalog:reindex --help
$ metacrunch --help                                  # lists the jobs and commands
```

`metacrunch` finds the nearest `Metacrunchfile` above the working directory and loads it only when a name is needed;
runs by path and the built-in commands never load it, so job files `require` what they use themselves. The
`Metacrunchfile` is plain Ruby. `Metacrunch.load_files` takes globs relative to the project root, or absolute ones,
and loads each matching file once, in sorted order.

- A file that fails to load costs only its own names: `metacrunch` warns about it (`-v` shows the whole error), and
  `--help` lists it under "Not loaded".
- A name declared twice cannot be used until one is renamed; the error names both files.
- The names of the built-in commands (`run`, `check`, `trace`, `new`, `credentials`, `help`) are reserved.
- Jobs without a name are not part of the project; they run by path.
- The `Metacrunchfile` and the files it loads are loaded again by every `Metacrunch.load_project`, so like job files
  they define no constants: helpers go into `lib/` and are required.

### Commands

A command is a named recipe like a job, with parameters and a body instead of a pipeline:

```ruby
# commands/catalog.rb
Metacrunch.command "catalog:reindex", desc: "Load an export into a new index and switch the alias" do
  params do
    param :url, String, default: "http://localhost:9200", env: "ES_URL"
    param :alias, String, default: "catalog"
    args :files, min: 1
  end

  run do
    index = "#{params.alias}-#{Time.now.strftime("%Y%m%d%H%M")}"
    es = ["--url", params.url]

    invoke "es:create-index", *es, "--mappings", root.join("etc/catalog_mappings.json"), index
    result = invoke "marc2es", *es, "--index", index, *params.files, workers: 8
    next logger.warn("alias not switched: #{result.status}") unless result.ok?

    invoke "es:switch-alias", *es, "--to", index, params.alias
  end
end
```

Parameters, `env:`, credentials, `-e`, `--help` and logging work as for jobs. `params` comes first; `run { ... }`
holds the body, which `--help` never runs. In the body, `params`, `logger`, `invoke` and `root` (the project root, a
`Pathname`) are available, and `next` ends it early (`return` does not work in a block). Helpers shared by several
commands are plain Ruby: a module that the body `extend`s, or a proc for common parameters
(`params { instance_exec(&ES_PARAMS) }`) in a required file.

`invoke NAME, *ARGS, workers:, limit:` runs a job or command with arguments as on the command line; each is converted
with `to_s`, and `nil` raises `ArgumentError`. An invoked job runs like `metacrunch run NAME`: it logs its summary as
`marc2es: ok: read ...`, reads stdin if it has no source and writes stdout if it has no sink. All jobs and commands of
a chain share `-e`, `--credentials`, the environment, the log level and the progress setting.

| Case | `invoke` |
|---|---|
| Job ends `:ok` or `:ok_with_failures` | returns its `Result`; the command decides |
| Job ends `:aborted` | raises `Metacrunch::InvokeError` (with `result`); the chain ends unless the command rescues it |
| Unknown name, invalid arguments | raises `Metacrunch::InvokeError`: the command has a bug |
| Command | returns the value of its body; its exceptions pass unchanged |
| Ctrl-C, SIGTERM | the running job flushes and closes its sinks, then the chain ends by the signal |

| Exit status of a command | When |
|---|---|
| 0 | every invoked job ended `:ok` |
| 1 | an exception left the body; an `InvokeError` is logged as its message |
| 2 | invalid parameters of the command itself |
| 3 | an invoked job ended `:ok_with_failures`, or `:aborted` and the command went on |
| 130, 143 | Ctrl-C, SIGTERM |

`run` takes commands too; the job options (`-i`, `-o`, `-w`, ...) are a usage error for them, and `check` and
`trace` take jobs only. A command file can also run by path, or as an executable with `#!/usr/bin/env metacrunch`;
when it invokes a name, it finds the project from the working directory.

Names search credentials from the project root (`.metacrunch/` next to the `Metacrunchfile`), also for commands from
gems; a path searches from its file. A job below `jobs/x/` with a `.metacrunch/` of its own therefore uses the
project's credentials by name and its own by path. Nothing changes the working directory: relative paths stay
relative to where `metacrunch` was started, and `root.join(...)` reaches the project's files from anywhere.

### Commands from gems

A gem ships command files and a constant with their glob; a project opts in:

```ruby
# in the gem
module Metacrunch
  module Elasticsearch
    COMMANDS = File.expand_path("elasticsearch/commands/*.rb", __dir__)
  end
end

# Metacrunchfile
require "metacrunch/elasticsearch"
Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS, "jobs/**/*.rb", "commands/**/*.rb"
```

There is no global registry and no `~/.metacrunch` for commands: under Bundler a global file could not load gems that
the project's Gemfile lacks. Personal tools are executable command files on the `PATH`. For task automation without
records, Rake, Thor or just fit better.

### Testing commands

```ruby
require "metacrunch/testing"

class CatalogTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load
    assert_empty PROJECT.load_errors
  end

  def test_keeps_the_alias_when_records_failed
    run = Metacrunch::Testing.invoke(PROJECT, "catalog:reindex", params: {files: ["dumps/a.xml"]},
                                     stubs: {"marc2es" => :ok_with_failures})

    assert_equal ["es:create-index", "marc2es"], run.invoked.map(&:name)
    assert_equal :ok_with_failures, run.status
  end

end
```

`Testing.invoke` runs the body with `params` bound from a Hash and records every `invoke` (`name`, `argv`,
`options`) instead of running it. A stub answers with a status, a `Result`, a value for a command, or a callable that
gets the arguments; without a stub a job ends `:ok` and a command returns `nil`. A stubbed `:aborted` raises like a
real abort, an unknown name fails as in a real run, a stub for an unknown name raises at once, and credentials are
never read. `run.status` is `:ok`, `:ok_with_failures`, or `:aborted` with the exception in `run.error`.

[`examples/project`](examples/project) is a runnable project with a test.

## What runs when

| When | What runs |
|---|---|
| A file is loaded: every call that uses it; in a project, every call that needs a name, `--help` included | the file's top-level code: `require`, constants |
| The recipe is evaluated: `run`, `check`, `trace`, `Testing.run`, `Testing.invoke`; for `--help` only up to its first statement | the recipe's code and the arguments of its statements, such as `MySource.new(...)` |
| The job or command runs | `before`, `open`, `each` and `write` of the components, the steps, `after`; a command's `run` block |

A recipe only declares. Code before `params` and the arguments of the first statement run for every `--help`: a
lookup table built there makes `--help` slow, and a relative path read there breaks `--help` when it is started from
another directory. Preparation such as lookup tables and connections belongs into a `before` hook or a component's
`open`, effects into components or a command's `run` block. Code that must stay in the recipe goes after `params`,
where `--help` does not reach it.

````

- [ ] **Step 6: Update the CHANGELOG**

In `CHANGELOG.md`, add to the end of "### Added" in "5.0.0 (unreleased)":

```markdown
- Projects: a `Metacrunchfile` names a project's jobs and commands (`Metacrunch.load_files`); `metacrunch NAME` runs
  them from any directory of the project, and `metacrunch --help` lists them. A file that fails to load costs only
  its own names. `Metacrunch.load_project` and `Project#invoke` do the same from Ruby.
- Commands: `Metacrunch.command "name" do params { ... }; run { ... } end`, with the parameters, credentials, `-e`,
  `--help` and logging of jobs. `invoke` chains jobs and commands; the exit status reports the worst result.
  `Metacrunch::Testing.invoke` tests a command without running what it invokes.
- Names and descriptions for jobs: `Metacrunch.job "a2c", desc: "..."`. Names are parts of `a-z`, `0-9`, `_` and
  `-`, separated by `:`; `Metacrunch.job` raises for other names, and `metacrunch new` for file names that would
  give one.
```

- [ ] **Step 7: Mark the spec as implemented**

In `docs/superpowers/specs/2026-10-13-metacrunch-ng-commands-design.md`, change the status line:

```markdown
- Status: implemented
```

- [ ] **Step 8: Check the links and the examples of the Readme**

Run: `grep -o '](#[a-z-]*)' Readme.md | sort -u`
Expected: every anchor is the slug of a heading in `Readme.md` (`#projects-and-commands`, `#what-runs-when`, `#credentials`, ...).

Run the Readme's project commands against the example once:

```bash
(cd examples/project && bundle exec metacrunch --help | tail -n 8)
(cd examples/project && bundle exec metacrunch catalog:release --help)
```

Expected: the lists "Jobs (...)" with `catalog` and "Project commands (...)" with `catalog:release`; the help of the command with its description and `--input`, `--out`.

- [ ] **Step 9: Final verification**

Run: `bundle exec rake`
Expected: all tests pass (about 760: 648 before, 113 new), coverage at least 95 % lines and 90 % branches, RuboCop clean.

Run: `bundle exec ruby -Ilib bench/executor.rb inline`
Expected: within 5 % of about 64 ns per step and record (the engine did not change).

Run: `git status --short`
Expected: clean except for the files of this task.

- [ ] **Step 10: Commit**

```bash
git add Readme.md CHANGELOG.md docs/superpowers/specs/2026-10-13-metacrunch-ng-commands-design.md
git commit -m "$(cat <<'EOF'
Document projects, commands and what runs when

The Readme gets the section "Projects and commands" (Metacrunchfile,
names, commands, invoke and exit statuses, gem commands, credentials from
the project root, Testing.invoke) and "What runs when", names next to
paths in "Running jobs", and the advice to build lookup tables in a
before hook. The CHANGELOG lists projects, commands and job names.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```
