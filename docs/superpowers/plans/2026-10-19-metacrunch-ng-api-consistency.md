# A consistent API for jobs, transforms and commands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One form for parameter values in Ruby (`params:`), `root` in every recipe, one word for failed records (*failure*), one result core for `invoke`, and one addressing for `Testing`.

**Architecture:** `Params#bind_values` becomes the only binding for values from code (`use`, `invoke`, `Project#invoke`, `Job#run`, `Testing`); argv stays on the command line. A root callable flows from `Invoker#root` (which finds a `Metacrunchfile` without loading it) through `UseContext`, the builders and the `Params` schema, so `root` works in statements, `params` blocks, hooks and steps. `Invoker` gives each command call a status of its own and returns `CommandResult`. The failure vocabulary is renamed through DSL, `Pipeline`, `RunOptions` and the CLI.

**Tech Stack:** Ruby 4.0, Minitest, RuboCop (rubocop-ubpb), SimpleCov.

**Spec:** `docs/superpowers/specs/2026-10-19-metacrunch-ng-api-consistency-design.md`

## Global Constraints

- Ruby 4.0; no new runtime dependency (only `logger`).
- metacrunch 5 is unreleased: old names and forms are removed without aliases or migration messages.
- Repository docs, comments, commit messages in English; examples generic (no MARC, Elasticsearch, library or internal names) in `Readme.md`, `docs/` and `examples/`.
- `bundle exec rake` passes: tests, coverage at least 95 % lines and 90 % branches, RuboCop with no offenses.
- Every commit ends with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Unchanged: the engine, executors, stats, `trace`, the JSON of `ContextWriter` and `--stats`, `ctx.failure`, `stats.failed`, `:ok_with_failures`, `Result#error`, the exit codes, `run do ... end` in commands.

## Review Focus

1. `root` called in a step that runs in a forked worker (`-w 2`): records get the same root as inline. Test in Task 6 (`test_root_works_in_workers`).
2. A command that ran a job with failures and then raised, rescued by the command that invoked it: the outer command still reports `:ok_with_failures`. Test in Task 4 (`test_a_command_that_raises_keeps_the_status_of_its_jobs`).
3. `--help` of a command whose `params` default uses `root`: shows the absolute default by name; by path outside a project it ends with exit status 2, not a crash. Test in Task 6 (`test_command_help_with_a_root_default`).
4. A job file outside the project (a gem's file, loaded by an absolute glob) run by name: `root` is the project's, not the file's directory. Test in Task 6 (`test_a_recipe_outside_the_project_gets_the_project_root`).
5. `Testing.run(PROJECT, "name")` of a transform without `source:` keeps the message "a transform has no source; pass source:". Test in Task 5 (`test_runs_jobs_and_transforms_of_a_project_by_name`).

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `lib/metacrunch/params.rb` | One binding for values from code; `to_path` values; `root` for defaults | 1, 6 |
| `lib/metacrunch/builder.rb` | `use(target, params:)`; root; `failures`, `on_failure` | 2, 6, 7 |
| `lib/metacrunch/use_context.rb` | Passes `params`; `root` of its resolver | 2, 6 |
| `lib/metacrunch/invoker.rb` | `invoke(target, params:)`; `argv:`/`params:` binding; `CommandResult`; status per command; `root` without loading | 3, 4, 6 |
| `lib/metacrunch/command_scope.rb` | `invoke` signature | 3 |
| `lib/metacrunch/project.rb` | `invoke` signature | 3 |
| `lib/metacrunch/job.rb` | `run(params:)`; `describe(root:)` | 3, 6 |
| `lib/metacrunch/result.rb` | `CommandResult` | 4 |
| `lib/metacrunch/testing.rb` | Binding; `Invocation#params`; `CommandResult`; `run(project, name)`; `failures`; `ok?` | 1, 3, 4, 5, 7 |
| `lib/metacrunch/recipe_params.rb`, `command_builder.rb`, `command.rb`, `transform.rb` | Root callable; `prepare(root:)`, `describe(root:)` | 6 |
| `lib/metacrunch/cli/job_command.rb`, `cli/run.rb` | `argv:` keyword; help with root; `--failures` options | 3, 6, 7 |
| `lib/metacrunch/pipeline.rb`, `run_options.rb`, `sink_outlet.rb`, `processor.rb`, `engine.rb`, `cli/check.rb`, `cli/trace.rb`, `json_lines.rb` | Failure vocabulary | 7 |
| `lib/metacrunch/templates/{job,transform,command}/*.erb` | `params:`; `Testing.run(PROJECT, name)` | 2, 3, 5 |
| `examples/` | New API | 2, 3, 7, 8 |
| `Readme.md`, `docs/*.md`, `CHANGELOG.md` | New API | 8 |

Task order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Each task leaves `bundle exec rake` green.

---

### Task 1: One binding for values from code

**Files:**
- Modify: `lib/metacrunch/params.rb` (header comment; `bind_values`; `convert`; `args_values`; delete `bind_hash`)
- Modify: `lib/metacrunch/testing.rb:122`, `:159`
- Modify: `test/support/pipeline_helper.rb:8`, `test/unit/use_test.rb:255,264,289`, `test/unit/transform_test.rb:98`, `test/unit/params_credentials_test.rb:173,181,237-238`, `test/unit/params_test.rb:82-98`
- Test: `test/unit/params_values_test.rb`, `test/unit/params_test.rb`, `test/unit/testing_test.rb`

**Interfaces:**
- Produces: `Params#bind_values(values, env: ENV, credentials: nil)` is the only Hash binding. Raises `ArgumentError` "params: must be a Hash, got X" for a non-Hash and "unknown parameter :x (known: a, b)" for an unknown key; `ParamError` for invalid or missing values. A value (or Array element, or `args` value, or `default:`) that responds to `to_path` counts as its path String. `Params#bind_hash` no longer exists.
- Produces: Testing binds with `schema.bind_values(params, env: {}, credentials: nil)`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/params_values_test.rb` (the `schema` helper declares `lang` with default "de", `limit`, `ratio`, `strict`, `tags` and `args :files`):

```ruby
  def test_pathnames_count_as_strings
    bound = schema.bind_values({lang: Pathname("en"), tags: [Pathname("a"), "b"], files: [Pathname("x.xml")]})

    assert_equal ["en", ["a", "b"], ["x.xml"]], [bound.lang, bound.tags, bound.files]
  end

  def test_a_single_pathname_argument_works_too
    assert_equal ["x.xml"], schema.bind_values({files: Pathname("x.xml")}).files
  end

  def test_values_must_be_a_hash
    error = assert_raises(ArgumentError) { schema.bind_values([[:lang, "en"]]) }

    assert_equal "params: must be a Hash, got [[:lang, \"en\"]]", error.message
  end
```

Add to `test/unit/params_test.rb`:

```ruby
  def test_pathname_defaults_count_as_strings
    params = Metacrunch::Params.new
    params.param :input, String, default: Pathname("/data/titles.jsonl")

    assert_equal "/data/titles.jsonl", params.bind_values({}, env: {}).input
    assert_includes params.help, "(default: /data/titles.jsonl)"
  end
```

Add to `test/unit/testing_test.rb`:

```ruby
  def test_params_are_bound_like_use_but_without_the_environment
    job = Metacrunch.job do
      params do
        param :lang, String, env: "METACRUNCH_TEST_LANG", default: "de"
        param :path, String
      end
      source [1]
      map { [params.lang, params.path] }
    end
    ENV["METACRUNCH_TEST_LANG"] = "en"
    result = Metacrunch::Testing.run(job, params: {path: Pathname("a/b")})

    assert_equal [["de", "a/b"]], result.records
  ensure
    ENV.delete("METACRUNCH_TEST_LANG")
  end

  def test_unknown_params_raise_argument_errors
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(build_job, params: {limt: 5}, source: []) }

    assert_match(/\Aunknown parameter :limt \(known: /, error.message)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/params_values_test.rb test/unit/params_test.rb test/unit/testing_test.rb`
Expected: failures for the Pathname tests ("is not a String"), `test_values_must_be_a_hash` (`NoMethodError` on `transform_keys`), the Pathname default (`invalid default`), and the two Testing tests (ParamError instead of ArgumentError; "path" not a String).

- [ ] **Step 3: Implement**

In `lib/metacrunch/params.rb`, replace the class comment's first sentence:

```ruby
  # The parameters a recipe declares in `params { ... }`, and their binding
  # from the command line (#bind_argv) or from values in code (#bind_values:
  # use, invoke, Job#run, Testing). Bound values are frozen.
```

Delete `bind_hash` (lines 131-141). Replace the comment and first lines of `bind_values`:

```ruby
    # Binds values from code: use, invoke, Project#invoke, Job#run and, with
    # an empty environment and no credentials, Testing. A value may have the
    # declared type or be a String, which is converted; a Pathname counts as
    # its path; nil means "not given". A parameter without a value is read
    # from its env: variable, then from the credentials, then the default.
    # The values come from code, so messages name a parameter by its name,
    # not as option, and a secret gives no warning. Raises ArgumentError for
    # a non-Hash and an unknown key.
    def bind_values(values, env: ENV, credentials: nil)
      raise ArgumentError, "params: must be a Hash, got #{values.inspect}" unless values.is_a?(Hash)

      values = values.transform_keys(&:to_sym)
```

Change `convert` and `args_values`, and add `path_string` next to them:

```ruby
    def convert(definition, raw, origin: nil, keyword: false)
      raw = path_string(raw)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, keyword:)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, keyword:)
    end

    # A Pathname (anything with to_path) counts as the String of its path,
    # also inside an Array.
    def path_string(value)
      return value.to_path if value.respond_to?(:to_path)
      return value.map { path_string(it) } if value.is_a?(Array)

      value
    end
```

```ruby
    def args_values(value)
      value = path_string(value)
      return [] if value.nil?
```

In `lib/metacrunch/testing.rb`, both binders (`run` and `invoke`) become:

```ruby
->(schema) { schema.bind_values(params, env: {}, credentials: nil) }
```

and the comment above `run` says "params are bound like the values of `use` (see Params#bind_values), with an empty environment and no credentials".

- [ ] **Step 4: Move the remaining callers of `bind_hash`**

| File:line | New |
|---|---|
| `test/support/pipeline_helper.rb:8` | `binder: ->(schema) { schema.bind_values(params, env: {}) }` |
| `test/unit/use_test.rb:255` | `binder = ->(schema) { schema.bind_values({}, env: {}) }` |
| `test/unit/use_test.rb:264` | `job.pipeline(binder: ->(schema) { schema.bind_values({}, env: {}) }, logger: SILENT)` |
| `test/unit/use_test.rb:289` | `binder: ->(schema) { schema.bind_values(params, env: {}) }` |
| `test/unit/transform_test.rb:98` | `binder: ->(schema) { schema.bind_values(params, env: {}) }` |
| `test/unit/params_credentials_test.rb:173` | `params.bind_values({index: "test", api_key: SECRET}, env: {})` |
| `test/unit/params_credentials_test.rb:181` | `api_key_schema.bind_values({api_key: SECRET}, env: {})` |
| `test/unit/params_credentials_test.rb:237-238` | rename to `test_bind_values_without_credentials_finds_none`; `assert_nil api_key_schema.bind_values({}, env: {}).api_key` |
| `test/unit/params_test.rb:82-98` | delete both `test_bind_hash_*` tests (`params_values_test.rb` covers `bind_values`) |

Run `grep -rn bind_hash lib test`; Expected: no output.

- [ ] **Step 5: Run the suite**

Run: `bundle exec rake`
Expected: all tests pass, no RuboCop offenses. Tests that asserted a `ParamError` for an unknown key in `Testing.run`/`Testing.invoke` now see `ArgumentError`, and messages name `limit` instead of `--limit`; update those assertions to the new class and text.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch/params.rb lib/metacrunch/testing.rb test
git commit -m "Bind values from code and tests by one set of rules

Params#bind_values is the only binding for values from code. Testing
uses it with an empty environment and no credentials, so an unknown key
raises ArgumentError there too; bind_hash is gone. A Pathname counts as
its path, as a value, an element of an Array, an argument and a default,
and a non-Hash raises ArgumentError.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `use` takes `params:`

**Files:**
- Modify: `lib/metacrunch/builder.rb:77-92`, `lib/metacrunch/use_context.rb` (`evaluate`, `binder`)
- Modify: `lib/metacrunch/templates/job/file.rb.erb:15`, `examples/project/jobs/catalog/ids.rb:15`
- Modify tests: `test/unit/use_test.rb:35,55,56,117`, `test/unit/invoker_test.rb:48`, `test/cli/project_cli_test.rb:42`, and any generator test that expects the template line
- Test: `test/unit/use_test.rb`

**Interfaces:**
- Consumes: `Params#bind_values` (Task 1).
- Produces: `Builder#use(target, params: {})`; `UseContext#evaluate(transform, params, stack:)`.

- [ ] **Step 1: Write the failing tests**

In `test/unit/use_test.rb`, change the existing calls to the new form (line 35 `use "scale", params: {factor: 10}`; 55 `params: {factor: 2}`; 56 `params: {factor: 10}`; 117 `use shout, params: {mark: "!!"}`) and add:

```ruby
  def test_values_as_keywords_are_refused
    error = assert_raises(ArgumentError) { build_job({"scale" => SCALE}) { source []; use "scale", factor: 2 } }

    assert_equal "unknown keyword: :factor", error.message
  end

  def test_params_must_be_a_hash
    error = assert_raises(ArgumentError) { build_job({"scale" => SCALE}) { source []; use "scale", params: [2] } }

    assert_equal "use scale: params: must be a Hash, got [2]", error.message
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/use_test.rb`
Expected: FAIL — "unknown keyword: :params" in the changed tests; the keyword test passes for the wrong reason or fails on the message.

- [ ] **Step 3: Implement**

`lib/metacrunch/builder.rb`:

```ruby
    # Inserts the steps and hooks of a transform here. target: a Transform,
    # or its name or path; params: the values of its parameters (see
    # Params#bind_values). Its steps are named with its label as prefix:
    # normalize/map#1.
    def use(target, params: {})
      use!
      raise ArgumentError, "use needs a context: build the job with Job#pipeline(context:)" unless @context

      transform = @context.transform(target)
      built = @context.evaluate(transform, params, stack: @stack)
```

`lib/metacrunch/use_context.rb`: rename the parameter `values` to `params` in `evaluate(transform, params, stack:)` and `binder(chain, params)`, and in the comment ("Evaluates the recipe of transform with params bound").

- [ ] **Step 4: Move the other callers**

| File:line | New |
|---|---|
| `test/unit/invoker_test.rb:48` | `use "scale", params: {factor: params.factor}` |
| `test/cli/project_cli_test.rb:42` | `use "scale", params: {factor: 10}` |
| `examples/project/jobs/catalog/ids.rb:15` | `use "catalog:public", params: {fields: ["id"]}` |
| `lib/metacrunch/templates/job/file.rb.erb:15` | `  # use "catalog:clean", params: {lang: "en"}` |

Run `grep -rn 'catalog:clean' test` and update an expected template line, if any, to the new comment.
Run `grep -rnE 'use [^,]+, [a-z_]+:' lib test examples` (ignore hits with `params:`); Expected: none.

- [ ] **Step 5: Run the suite**

Run: `bundle exec rake`
Expected: all pass, no offenses.

- [ ] **Step 6: Commit**

```bash
git add lib examples test
git commit -m "Give the values of use as params:

use takes the values of a transform's parameters as params: {...}, the
form every Ruby caller will use. Keywords are refused by Ruby.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `invoke`, `Project#invoke` and `Job#run` take `params:`

**Files:**
- Modify: `lib/metacrunch/invoker.rb` (`invoke`, `pipeline`, `prepare`, `run_job`, private `invoke_job`, `invoke_command`, `binder`; delete `arguments`, `argument_problem`)
- Modify: `lib/metacrunch/command_scope.rb:16-18`, `lib/metacrunch/project.rb:94-99`, `lib/metacrunch/job.rb:33-48`
- Modify: `lib/metacrunch/cli/job_command.rb:87`, `lib/metacrunch/cli/run.rb` (`execute_job`, `execute_command`)
- Modify: `lib/metacrunch/testing.rb` (`Invocation`, `RecordingInvoker#invoke_job`, `#invoke_command`, `#answer`)
- Modify: `examples/project/commands/catalog/release.rb:23-24`, `lib/metacrunch/templates/command/file.rb.erb:13`
- Modify tests: `test/unit/invoker_test.rb`, `test/unit/command_test.rb:51`, `test/unit/testing_invoke_test.rb`, `test/unit/job_test.rb`, `test/unit/job_credentials_test.rb`, `test/cli/project_cli_test.rb:55-74`, `test/cli/exe_project_test.rb:78-103`
- Test: `test/unit/invoker_test.rb`, `test/unit/job_test.rb`

**Interfaces:**
- Consumes: `Params#bind_values` (Task 1).
- Produces:
  - `Invoker#invoke(target, params: {}, workers: nil, limit: nil)`
  - `Invoker#pipeline(job, anchor:, argv: nil, params: nil)`, `Invoker#prepare(command, anchor:, argv: nil, params: nil)`, `Invoker#run_job(job, anchor:, argv: nil, params: nil, options: RunOptions.new, workers: nil, label: nil)` — exactly one of `argv:` (CLI) and `params:` (code).
  - `CommandScope#invoke(target, params: {}, workers: nil, limit: nil)`
  - `Project#invoke(target, params: {}, logger:, env:, stdin:, stdout:, workers:, limit:)`
  - `Job#run(params: {}, env: ENV, logger:, observer: nil, limit: nil, workers: nil, project: nil)`
  - `Testing::Invocation = Data.define(:name, :params, :options)`; callable stubs get the `params` Hash.

- [ ] **Step 1: Write the failing tests**

In `test/unit/invoker_test.rb`, change the fixtures:

```ruby
    "commands/chain.rb" => <<~RUBY,
      Metacrunch.command "chain" do
        params do
          param :tolerant, :bool, default: false
          args :numbers
        end

        run do
          invoke "numbers", params: {numbers: params.numbers}
        rescue Metacrunch::InvokeError
          raise unless params.tolerant

          :rescued
        end
      end
    RUBY
    "commands/outer.rb" => <<~RUBY,
      Metacrunch.command "outer" do
        params { args :numbers }

        run { [invoke("chain", params: {tolerant: true, numbers: params.numbers}), invoke("note", params: {text: "done"})] }
      end
    RUBY
```

Replace `test_nil_arguments_are_refused` and `test_arrays_and_hashes_are_refused` with:

```ruby
  def test_params_from_code_are_bound_by_name
    with_project do |invoker|
      result = invoker.invoke("numbers", params: {skip: true, numbers: ["0", Pathname("4")]})

      assert_equal [:ok_with_failures, 2], [result.status, result.stats.read]
    end
  end

  def test_nil_params_count_as_not_given
    with_project do |invoker, out|
      invoker.invoke("scaled", params: {factor: nil, numbers: ["1"]})

      assert_equal "2\n", out.string
    end
  end

  def test_unknown_params_raise_invoke_errors
    with_project do |invoker|
      error = assert_raises(Metacrunch::InvokeError) { invoker.invoke("numbers", params: {skp: true}) }

      assert_equal "invoke numbers: unknown parameter :skp (known: skip, numbers)", error.message
    end
  end

  def test_params_must_be_a_hash
    with_project do |invoker|
      error = assert_raises(ArgumentError) { invoker.invoke("note", params: ["x"]) }

      assert_equal "invoke note: params: must be a Hash, got [\"x\"]", error.message
    end
  end

  def test_arguments_as_on_the_command_line_are_gone
    with_project do |invoker|
      assert_raises(ArgumentError) { invoker.invoke("note", "done") }
    end
  end
```

In `test/unit/job_test.rb`, change `test_run_binds_cli_arguments_and_returns_the_result` to `test_run_binds_params_and_returns_the_result` with `job.run(params: {factor: 3, numbers: ["1", "2"]}, logger: SILENT)`, and add:

```ruby
  def test_run_reads_the_environment_for_params_not_given
    target = CollectingSink.new
    job = Metacrunch.job do
      params { param :factor, Integer, env: "FACTOR", default: 1 }
      source [2]
      map { it * params.factor }
      sink target
    end
    job.run(params: {factor: nil}, env: {"FACTOR" => "4"}, logger: SILENT)

    assert_equal [8], target.records
  end

  def test_run_refuses_unknown_params
    job = Metacrunch.job { params { param :factor, Integer }; source [] }
    error = assert_raises(ArgumentError) { job.run(params: {facter: 3}, logger: SILENT) }

    assert_equal "unknown parameter :facter (known: factor)", error.message
  end
```

In `test/unit/job_credentials_test.rb`, replace `test_run_logs_a_warning_for_a_secret_on_the_command_line` with:

```ruby
  def test_run_gives_no_warning_for_a_secret_from_code
    in_tmpdir do |root|
      job = Metacrunch.load_job(write_file(root, "jobs/x.rb", SECRET_JOB))
      io = StringIO.new
      job.run(params: {api_key: SECRET, output: File.join(root, "out.jsonl")}, env: {}, logger: Logger.new(io))

      refute_includes io.string, "is a secret"
      refute_includes io.string, SECRET
    end
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/invoker_test.rb test/unit/job_test.rb test/unit/job_credentials_test.rb`
Expected: FAIL with "unknown keyword: :params" (invoke, Job#run).

- [ ] **Step 3: Implement `Invoker`**

```ruby
    # Runs target, a name or a path, with params bound by name (see
    # Params#bind_values). Returns the Result of a job or transform, or a
    # command's value. Raises InvokeError if the target is unknown, params
    # are invalid for it or the job aborted, and ArgumentError if params is
    # no Hash; exceptions from a command's body pass unchanged.
    def invoke(target, params: {}, workers: nil, limit: nil)
      target = target.to_s
      raise ArgumentError, "invoke #{target}: params: must be a Hash, got #{params.inspect}" unless params.is_a?(Hash)

      declaration, anchor = wrap(target) { resolve(target) }
      return invoke_job(declaration, params, target:, anchor:, workers:, limit:) unless declaration.is_a?(Command)
      if workers || limit
        raise ArgumentError, "#{target} is a command; workers: and limit: apply to jobs and transforms"
      end

      invoke_command(declaration, params, target:, anchor:)
    end
```

```ruby
    # The pipeline of a job or transform with its parameters bound from
    # argv (the command line) or params (code): then env:, the credentials
    # searched from anchor, then the default. The transforms it uses
    # resolve here and read the same credentials.
    def pipeline(job, anchor:, argv: nil, params: nil)
      credentials = credentials_for(anchor)
      context = UseContext.new(resolver: self, env: @env, credentials:, logger: @logger)
      job.pipeline(binder: binder(credentials, argv:, params:), logger: @logger, context:)
    end

    # Evaluates the command's recipe with argv or params bound as pipeline
    # does.
    def prepare(command, anchor:, argv: nil, params: nil)
      command.prepare(binder: binder(credentials_for(anchor), argv:, params:))
    end
```

`run_job(job, anchor:, argv: nil, params: nil, options: RunOptions.new, workers: nil, label: nil)` calls `pipeline(job, anchor:, argv:, params:)`; the rest is unchanged.

Private:

```ruby
    def invoke_job(job, params, target:, anchor:, workers:, limit:)
      result = wrap(target) do
        run_job(job, anchor:, params:, options: RunOptions.new(limit:), workers:, label: target)
      rescue NoInputError
        # invoke has no -i: the job reads the stdin of the chain.
        raise NoInputError.new(target, hint: "pipe them into the command that invokes it")
      end
      aborted!(result, target)
      result
    end

    def invoke_command(command, params, target:, anchor:)
      call(wrap(target) { prepare(command, anchor:, params:) })
    end

    # argv: the command line, with a warning for a secret given there.
    # params: values from code (see Params#bind_values).
    def binder(credentials, argv:, params:)
      return ->(schema) { bind_params(schema, params, credentials) } if params

      warn = ->(message) { @logger.warn(message) }
      ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }
    end

    # An unknown key is a wrong argument of invoke, as an invalid value is:
    # both become a ParamError, which invoke raises as InvokeError.
    def bind_params(schema, params, credentials)
      schema.bind_values(params, env: @env, credentials:)
    rescue ArgumentError => e
      raise ParamError, e.message, cause: nil
    end
```

Delete `arguments` and `argument_problem`.

- [ ] **Step 4: Implement the other callers**

`lib/metacrunch/command_scope.rb`:

```ruby
    # Runs a job, transform or command by name or path, with params bound
    # by name; see Invoker#invoke.
    def invoke(target, params: {}, workers: nil, limit: nil) = @invoker.invoke(target, params:, workers:, limit:)
```

`lib/metacrunch/project.rb`:

```ruby
    def invoke(target, params: {}, logger: Metacrunch.logger, env: ENV, stdin: $stdin, stdout: $stdout, workers: nil,
               limit: nil)
      Invoker.new(project: self, logger:, env:, stdin:, stdout:).invoke(target, params:, workers:, limit:)
    end
```

`lib/metacrunch/job.rb`:

```ruby
    # Runs the job with params bound by name (see Params#bind_values):
    # given values, then env:, then the credentials, then the default.
    # Raises ArgumentError for an unknown key and ParamError for invalid
    # values (CredentialsError, a ParamError, for unreadable credentials);
    # errors from the recipe itself (a component constructor, a DSL
    # mistake) propagate. Errors while the pipeline runs end up in the
    # Result. limit stops after that many records; workers runs the steps in
    # that many processes. Credentials follow env: METACRUNCH_ENV,
    # METACRUNCH_CREDENTIALS, METACRUNCH_MASTER_KEY, HOME. project: where the
    # names of `use` resolve; without it, the project of the nearest
    # Metacrunchfile above Dir.pwd, loaded when a name needs it.
    def run(params: {}, env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil, project: nil)
      credentials = Credentials.store(job_file: file, env:, logger:)
      context = UseContext.for(project:, env:, credentials:, logger:)
      built = pipeline(binder: ->(schema) { schema.bind_values(params, env:, credentials:) }, logger:, context:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
    end
```

CLI: `lib/metacrunch/cli/job_command.rb:87` `def build_pipeline(job, argv) = invoker.pipeline(job, anchor: @anchor, argv:)`; in `lib/metacrunch/cli/run.rb`, `invoker.run_job(job, anchor: @anchor, argv:, options:, workers: @workers)` and `finish(invoker.prepare(command, anchor: @anchor, argv:))`.

`lib/metacrunch/testing.rb`:

```ruby
    # One invoke recorded by Testing.invoke. params: as given. options:
    # workers: and limit: as given.
    Invocation = Data.define(:name, :params, :options)
```

In `RecordingInvoker`, rename `argv` to `params` in `invoke_job`, `invoke_command` and `answer`, record `Invocation.new(name: target, params:, options: ...)`, and say in the class comment that a callable stub "gets the params Hash".

- [ ] **Step 5: Move the remaining callers**

Every argv call becomes a `params:` Hash keyed by the parameter names of the invoked fixture:

| File:line | New |
|---|---|
| `test/unit/invoker_test.rb:114` | `invoker.invoke("numbers", params: {numbers: ["4", Pathname("5")]})` |
| `:122`, `:257` | `invoker.invoke("numbers", params: {numbers: ["0"]})` |
| `:131` | `invoker.invoke("numbers", params: {skip: true, numbers: ["0", "4"]})` |
| `:138` | `invoker.invoke("note", params: {text: "done"})` |
| `:189` | `lazy.invoke("note", params: {text: "x"})` |
| `:199` | `invoker.invoke("note", params: {text: "name"})` |
| `:229` | `invoker.invoke("note", params: {text: "x"}, workers: 2)` |
| `:232` | `invoker.invoke("numbers", params: {numbers: ["1", "2", "4"]}, limit: 2).stats.read` |
| `:247` | `invoker.invoke("outer", params: {numbers: ["0"]})` (the value stays `[:rescued, "done"]`) |
| `:268` | `invoker.invoke("term", params: {output:})` |
| `:297` | `invoker.project.invoke("note", params: {text: "done"}, logger: Logger.new(nil), env: {})` |
| `:303` | `invoker.invoke("scaled", params: {numbers: ["1", "2"]})` |
| `:313-314` | `invoker.invoke("scaled", params: {numbers: ["1"]})`, `invoker.invoke("scaled", params: {factor: 5, numbers: ["1"]})` |
| `:322` | `invoker.invoke("scale", params: {factor: 3})` |
| `test/unit/command_test.rb:51` | `invoke "a2c", params: {index: "test"}, workers: 2` |
| `test/unit/testing_invoke_test.rb:31` | `result = invoke "a2c", params: {index: "new", files: params.files}, workers: 4` |
| `:34` | `invoke "es:switch-alias", params: {to: "new", alias: params.alias}` |
| `:69-70` | `Invocation.new(name: "a2c", params: {index: "new", files: ["a.xml"]}, options: {workers: 4})`, `Invocation.new(name: "es:switch-alias", params: {to: "new", alias: "catalog"}, options: {})` |
| `:86-96` | rename to `test_callable_stubs_get_the_params`; lambdas take `params`; expect `[:switched, [{index: "new", files: ["a.xml"]}]]` |
| `:125-129` | `->(_params) { "ok" }` |
| `test/unit/job_test.rb` | `job.run([], ...)` → `job.run(...)` without the array (lines 38, 49, 60, 75, 110, 121, 130, 145, 153, 162) |
| `test/unit/job_credentials_test.rb:23`, `:35` | `job.run(params: {output:}, env: ..., logger: Logger.new(nil))` |
| `test/unit/job_credentials_test.rb:56` | `job.run(env: {"METACRUNCH_ENV" => "Prod"}, logger: Logger.new(nil))` |
| `test/cli/project_cli_test.rb:55` | `invoke "numbers", params: {skip: params.skip, numbers: params.numbers}` |
| `test/cli/project_cli_test.rb:59,73-74`, `test/cli/exe_project_test.rb:78-79,88-89,103` | the same rule, with the parameter names the invoked fixture declares in that file (`note` takes its text as `args`, `forever` takes `output:`) |
| `examples/project/commands/catalog/release.rb:23-24` | delete the `input = ...` line; `result = invoke "catalog", params: {output: release, input: params.input}` |
| `lib/metacrunch/templates/command/file.rb.erb:13` | `    # result = invoke "catalog:ids", params: {input: params.input}` |

Run: `grep -rnE 'invoke[ (]"[^"]+", "|invoke\("[^"]+", [^p]|\.run\(\[' lib test examples`
Expected: hits only for `Cli#run([...])`-style calls (`command.run(["run", ...])`, `cli.run([...])`), which take a command line.

- [ ] **Step 6: Run the suite**

Run: `bundle exec rake`
Expected: all pass, no offenses.

- [ ] **Step 7: Commit**

```bash
git add lib examples test
git commit -m "Give the values of invoke, Project#invoke and Job#run as params:

All Ruby callers pass parameter values as params: {...}, bound like the
values of use: nil means not given, then env:, credentials and the
default. Arguments as on the command line remain for the command line.
An optional value needs no condition any more (input: params.input).
Testing records the params of each invoke and passes them to callable
stubs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `invoke` of a command returns a `CommandResult`

**Files:**
- Modify: `lib/metacrunch/result.rb`, `lib/metacrunch/invoker.rb` (`invoke_command`, new `command_result`, comment of `invoke`)
- Modify: `lib/metacrunch/testing.rb` (`Result#ok?`, `CommandRun` → `CommandResult`, `RecordingInvoker#invoke_command`, `command_run`)
- Modify tests: `test/unit/invoker_test.rb` (values of command invokes), `test/unit/testing_invoke_test.rb`, `test/cli/*` where a command uses the value of another command
- Test: `test/unit/invoker_test.rb`, `test/unit/testing_invoke_test.rb`, `test/unit/result_test.rb`

**Interfaces:**
- Consumes: `Invoker#invoke(target, params:)` (Task 3).
- Produces:
  - `Metacrunch::CommandResult = Data.define(:status, :error, :value)` with `ok?`.
  - `Invoker#invoke` of a command returns `CommandResult(status:, error: nil, value:)`; status is the worst status of the jobs run during its body, nested commands included.
  - `Testing::Result#ok?`; `Testing::CommandResult = Data.define(:value, :status, :error, :invoked)` with `ok?` (was `CommandRun`).
  - Command stubs: a value → `CommandResult(:ok, nil, value)`; a `Metacrunch::CommandResult` with `:ok`/`:ok_with_failures` is used as is and counts toward the status; any other status raises `StubError`.

- [ ] **Step 1: Write the failing tests**

`test/unit/result_test.rb`:

```ruby
  def test_command_results_share_the_core_of_results
    ok = Metacrunch::CommandResult.new(status: :ok, error: nil, value: 1)
    failed = ok.with(status: :ok_with_failures)

    assert_equal [true, false, 1], [ok.ok?, failed.ok?, failed.value]
  end
```

`test/unit/invoker_test.rb` — add fixtures:

```ruby
    "commands/risky.rb" => <<~RUBY,
      Metacrunch.command "risky" do
        params { args :numbers }

        run do
          invoke "numbers", params: {skip: true, numbers: params.numbers}
          raise IOError, "disk full"
        end
      end
    RUBY
    "commands/careful.rb" => <<~RUBY,
      Metacrunch.command "careful" do
        params { args :numbers }

        run do
          invoke "risky", params: {numbers: params.numbers}
        rescue IOError
          :rescued
        end
      end
    RUBY
```

and tests:

```ruby
  def test_invoking_a_command_returns_a_command_result
    with_project do |invoker|
      result = invoker.invoke("note", params: {text: "done"})

      assert_equal [Metacrunch::CommandResult, :ok, true, nil, "done"],
                   [result.class, result.status, result.ok?, result.error, result.value]
    end
  end

  def test_each_command_result_has_the_status_of_its_own_jobs
    with_project do |invoker|
      result = invoker.invoke("outer", params: {numbers: ["0"]})
      chain, note = result.value

      assert_equal [:ok_with_failures, :ok_with_failures, :ok], [result.status, chain.status, note.status]
      assert_equal [:rescued, "done"], [chain.value, note.value]
      assert_equal [:aborted, :ok_with_failures], [invoker.status, invoker.finished_status]
    end
  end

  def test_a_command_that_raises_keeps_the_status_of_its_jobs
    with_project do |invoker|
      result = invoker.invoke("careful", params: {numbers: ["0"]})

      assert_equal [:ok_with_failures, :rescued], [result.status, result.value]
    end
  end
```

Replace `test_the_worst_status_comes_through_a_nested_command` (now covered by `test_each_command_result_has_the_status_of_its_own_jobs`). In the tests that compared a command's value (`:138`, `:199`, `:297`, and `GEM_COMMAND` at `:284`), compare `.value`.

`test/unit/testing_invoke_test.rb` — add the fixture `"commands/outer.rb" => "Metacrunch.command(\"outer\") { run { invoke(\"es:switch-alias\") } }\n"` and:

```ruby
  def test_results_answer_ok
    assert_predicate invoke("catalog:reindex", params: {files: ["a.xml"]}), :ok?
  end

  def test_command_stubs_give_a_value_or_a_command_result
    partly = Metacrunch::CommandResult.new(status: :ok_with_failures, error: nil, value: :partly)
    plain = invoke("outer", stubs: {"es:switch-alias" => :switched})
    stubbed = invoke("outer", stubs: {"es:switch-alias" => partly})

    assert_equal [:ok, :ok, :switched], [plain.status, plain.value.status, plain.value.value]
    assert_equal [:ok_with_failures, partly], [stubbed.status, stubbed.value]
  end

  def test_command_stubs_must_not_abort
    aborted = Metacrunch::CommandResult.new(status: :aborted, error: nil, value: nil)
    error = assert_raises(ArgumentError) { invoke("outer", stubs: {"es:switch-alias" => aborted}) }

    assert_equal "the stub for es:switch-alias must give a CommandResult with status :ok or :ok_with_failures, " \
                 "got :aborted", error.message
  end
```

`test/unit/testing_test.rb`:

```ruby
  def test_results_answer_ok
    results = [Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [1]),
               Metacrunch::Testing.run(build_job, params: {limit: 5}, source: [0])]

    assert_equal [true, false], results.map(&:ok?)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/result_test.rb test/unit/invoker_test.rb test/unit/testing_invoke_test.rb test/unit/testing_test.rb`
Expected: FAIL with "uninitialized constant Metacrunch::CommandResult" and `NoMethodError` for `ok?`.

- [ ] **Step 3: Implement**

`lib/metacrunch/result.rb`, after `Result`:

```ruby
  # Outcome of invoking a command. status is :ok, or :ok_with_failures if a
  # job run during its body (also through nested commands) ended with
  # failures, or aborted and the body went on; value is what the body
  # returned. error is nil: an exception that leaves the body passes
  # unchanged. Shares status, ok? and error with Result.
  CommandResult = Data.define(:status, :error, :value) do
    def ok? = status == :ok
  end
```

`lib/metacrunch/invoker.rb` — `invoke`'s comment says "Returns the Result of a job or transform, or the CommandResult of a command"; then:

```ruby
    def invoke_command(command, params, target:, anchor:)
      prepared = wrap(target) { prepare(command, anchor:, params:) }
      command_result { call(prepared) }
    end

    # Runs the block, the body of an invoked command, with a status of its
    # own: the worst status of the jobs run meanwhile, nested commands
    # included. The status of the chain keeps them too, also when the block
    # raises.
    def command_result
      outer = @status
      @status = :ok
      value = yield
      CommandResult.new(status: finished_status, error: nil, value:)
    ensure
      track(outer)
    end
```

`command_result` must be protected or private so `RecordingInvoker` can use `track`/`finished_status` (it inherits; private is enough).

`lib/metacrunch/testing.rb`:

```ruby
    # records: what reached the sink. rejects: [record, Rejection] pairs.
    # errors: [record, Failure] pairs.
    Result = Data.define(:records, :rejects, :errors, :stats, :status, :error) do
      def ok? = status == :ok
    end
```

(`errors` becomes `failures` in Task 7.) Rename `CommandRun` to `CommandResult` (definition, comment, the private helper `command_run` → `run_command`, its two `new` calls) and add `def ok? = status == :ok` to it. In `RecordingInvoker`:

```ruby
      def invoke_command(_command, params, target:, **)
        @invoked << Invocation.new(name: target, params:, options: {})
        command_stub_result(target, answer(target, params, nil))
      end

      # A value is what the stubbed body returned; a CommandResult also
      # gives the status, which counts toward the command under test.
      def command_stub_result(target, stub)
        return Metacrunch::CommandResult.new(status: :ok, error: nil, value: stub) unless stub.is_a?(Metacrunch::CommandResult)
        unless [:ok, :ok_with_failures].include?(stub.status)
          raise StubError, "the stub for #{target} must give a CommandResult with status :ok or :ok_with_failures, " \
                           "got #{stub.status.inspect}"
        end

        track(stub.status)
        stub
      end
```

Update the `RecordingInvoker` class comment ("a value or a Metacrunch::CommandResult for a command").

- [ ] **Step 4: Run the suite**

Run: `bundle exec rake`
Expected: all pass. CLI tests whose command bodies use another command's value (`grep -rn 'invoke("note"\|invoke "note"' test`) compare `.value` where they use it.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "Return a CommandResult from invoke of a command

invoke gives every target a result with status, ok? and error: a
Result for jobs and transforms, a CommandResult with the body's value
for commands. A command's status is the worst status of the jobs run
during its body, nested commands included, as its exit status on the
command line. Testing's results answer ok?, CommandRun is renamed
CommandResult, and a command stub may give a CommandResult.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `Testing.run` takes a project and a name

**Files:**
- Modify: `lib/metacrunch/testing.rb` (`run`, new private `run_target`)
- Modify: `lib/metacrunch/templates/job/test.rb.erb`, `lib/metacrunch/templates/transform/test.rb.erb`, `examples/project/test/` (tests that use `PROJECT.fetch(...)` with `Testing.run`)
- Modify tests that expect the old template text: `test/unit/generators_files_test.rb`, `test/cli/generate_test.rb` (find with `grep -rn 'PROJECT.fetch' test`)
- Test: `test/unit/testing_test.rb`

**Interfaces:**
- Consumes: Task 1 binding.
- Produces: `Testing.run(target, name = nil, params: {}, source: nil, logger: Logger.new(nil), workers: nil, project: nil)`; `target` is a `Project` (with `name`) or a `Job`/`Transform` (with optional `project:`).

- [ ] **Step 1: Write the failing tests**

`test/unit/testing_test.rb`:

```ruby
  def test_runs_jobs_and_transforms_of_a_project_by_name
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"*.rb\"\n")
      write_file(root, "scale.rb", SCALE)
      write_file(root, "doubled.rb", "# frozen_string_literal: true\n\nMetacrunch.job(\"doubled\") { use \"scale\" }\n")
      project = Metacrunch.load_project(root)
      results = [Metacrunch::Testing.run(project, "doubled", source: [1]), Metacrunch::Testing.run(project, "scale", source: [2])]
      error = assert_raises(ArgumentError) { Metacrunch::Testing.run(project, "scale") }

      assert_equal [[2], [4]], results.map(&:records)
      assert_equal "a transform has no source; pass source:", error.message
    end
  end

  def test_project_addressing_refuses_wrong_arguments
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "Metacrunch.load_files \"*.rb\"\n")
      write_file(root, "cmd.rb", "# frozen_string_literal: true\n\nMetacrunch.command(\"cmd\") { run { nil } }\n")
      project = Metacrunch.load_project(root)
      calls = [-> { Metacrunch::Testing.run(project, "cmd") }, -> { Metacrunch::Testing.run(project) },
               -> { Metacrunch::Testing.run(project, "cmd", project:) }, -> { Metacrunch::Testing.run(build_job, "x") },
               -> { Metacrunch::Testing.run("jobs/x.rb") }]

      assert_equal ["cmd is a command; test it with Testing.invoke",
                    "the name of a job or transform is missing",
                    "project: is for a job or transform; the first argument is a project already",
                    "a job or transform needs no name, got \"x\"",
                    "Testing.run takes a project and the name of a job or transform, or a job or transform; " \
                    "got \"jobs/x.rb\""],
                   calls.map { assert_raises(ArgumentError, &it).message }
    end
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib test/unit/testing_test.rb`
Expected: FAIL with `NoMethodError` (`pipeline` for a Project) or "wrong number of arguments".

- [ ] **Step 3: Implement**

```ruby
    # Runs a job or transform without I/O: target is a Project with the
    # name of one of its jobs or transforms, or a Job or Transform, whose
    # names resolve in project:, else in the project of the working
    # directory. params are bound like the values of `use` (see
    # Params#bind_values), with an empty environment and no credentials.
    # The job's sinks are built but never opened. Records are collected
    # even if the job has no sink; stats.written is 0 then, as in a real
    # run. workers: run the steps in that many processes, to check that the
    # job's records cross process boundaries. A transform needs source:.
    def run(target, name = nil, params: {}, source: nil, logger: Logger.new(nil), workers: nil, project: nil)
      job, project = run_target(target, name, project)
      unless source.nil? || source.respond_to?(:each)
```

and use `job` and `project` below as before. Add:

```ruby
    # [job or transform, project] for run.
    def run_target(target, name, project)
      case target
      when Project
        raise ArgumentError, "project: is for a job or transform; the first argument is a project already" if project
        raise ArgumentError, "the name of a job or transform is missing" unless name

        declaration = target.fetch(name)
        raise ArgumentError, "#{name} is a command; test it with Testing.invoke" if declaration.is_a?(Command)

        [declaration, target]
      when Job, Transform
        raise ArgumentError, "a job or transform needs no name, got #{name.inspect}" if name

        [target, project]
      else
        raise ArgumentError, "Testing.run takes a project and the name of a job or transform, or a job or " \
                             "transform; got #{target.inspect}"
      end
    end
    private_class_method :run_target
```

Templates — `job/test.rb.erb` and `transform/test.rb.erb`:

```erb
  def test_keeps_records_with_an_id
    result = Metacrunch::Testing.run(PROJECT, <%= target.name.inspect %>, source: [{"id" => 1}, {"title" => "x"}])

    assert_equal [{"id" => 1}], result.records
  end
```

Change `examples/project/test/**/*_test.rb` that call `Testing.run(PROJECT.fetch("x"), ...)` to `Testing.run(PROJECT, "x", ...)` and drop `project: PROJECT` there.

- [ ] **Step 4: Run the suite**

Run: `bundle exec rake`
Expected: all pass; `exe_generators_test` runs the generated tests and RuboCop on them. Update expected template text in generator tests if they compare it.

- [ ] **Step 5: Commit**

```bash
git add lib examples test
git commit -m "Address jobs and transforms in Testing.run by project and name

Testing.run takes a project and a name, as Testing.invoke does, or a
job or transform with project:, so a test names its project once. The
generated tests use the new form.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `root` in jobs and transforms

**Files:**
- Modify: `lib/metacrunch/invoker.rb` (`root`), `lib/metacrunch/use_context.rb` (`root`), `lib/metacrunch/recipe_params.rb` (`init_params`, `params`, `ensure_params_bound`, new `root`), `lib/metacrunch/params.rb` (`initialize(root:)`, `root`), `lib/metacrunch/builder.rb` (`initialize`), `lib/metacrunch/command_builder.rb` (`initialize`), `lib/metacrunch/command.rb` (`prepare`, `describe`), `lib/metacrunch/job.rb` (`describe`), `lib/metacrunch/transform.rb` (`describe`), `lib/metacrunch/cli/job_command.rb` (`requested_help`), `lib/metacrunch/testing.rb` (`invoke`)
- Create: `test/support/root_fixtures.rb`, `test/unit/root_test.rb`, `test/cli/root_cli_test.rb`

**Interfaces:**
- Consumes: `Testing.run(project, name)` (Task 5), `Invoker#prepare(command, anchor:, params:)` (Task 3).
- Produces:
  - `Invoker#root` → `Pathname`; finds a `Metacrunchfile` above `Dir.pwd` without loading it while the project is still a Proc; raises `ProjectError` "no Metacrunchfile found in DIR or above".
  - `UseContext#root` → `@resolver.root`.
  - A root callable (`#call` → `Pathname`) passed as `root:` to `Params.new`, `CommandBuilder.new`, `Command#prepare`, and `describe(root:)` of `Job`, `Transform`, `Command`; `Builder.new(..., root: nil)` derives it from `context:` when not given.
  - `root` in recipes, `params` blocks, hooks and steps (`RecipeParams#root`, `Params#root`).

- [ ] **Step 1: Write the failing unit tests**

`test/support/root_fixtures.rb` (loaded by `test_helper.rb` like every support file; the recipes use single-quoted heredocs — `<<~'RUBY'` — so `#{root}` is not interpolated by the test):

```ruby
# frozen_string_literal: true

# Recipes that use root, and a project with them, for RootTest and
# RootCliTest. Never name a test's block variable root: it would shadow
# root inside the recipe blocks of the test.
module RootFixtures

  METACRUNCHFILE = "Metacrunch.load_files \"jobs/**/*.rb\", \"transforms/**/*.rb\", \"commands/**/*.rb\"\n"

  ROOTED = <<~'RUBY'
    # frozen_string_literal: true

    Metacrunch.job "rooted" do
      params { param :input, String, default: root.join("data/in.txt") }

      source File.readlines(params.input, chomp: true)
      before { logger.info("root #{root}") }
      map { |line| "#{line}@#{root.basename}" }
    end
  RUBY

  LABELED = <<~'RUBY'
    # frozen_string_literal: true

    Metacrunch.transform("label") { map { |line| "#{line}:#{root.basename}" } }
    Metacrunch.job("labeled") { source ["x"]; use "label" }
  RUBY

  WHERE = <<~'RUBY'
    # frozen_string_literal: true

    Metacrunch.command "where" do
      params { param :out, String, default: root.join("out") }

      run { [params.out, root.to_s] }
    end
  RUBY

  # Writes the project with every recipe above and its data below dir.
  def write_root_project(dir)
    write_file(dir, "Metacrunchfile", METACRUNCHFILE)
    write_file(dir, "jobs/rooted.rb", ROOTED)
    write_file(dir, "jobs/labeled.rb", LABELED)
    write_file(dir, "commands/where.rb", WHERE)
    write_file(dir, "data/in.txt", "a\n")
  end

end
```

`test/unit/root_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class RootTest < Minitest::Test

  include CredentialsHelper
  include RootFixtures
  include ForkVariant::NoWorkerLeft

  SILENT = Logger.new(nil)

  def test_root_reaches_params_statements_hooks_and_steps
    in_tmpdir do |dir|
      log = StringIO.new
      result = Metacrunch::Testing.run(write_project(dir), "rooted", logger: Logger.new(log))

      assert_equal ["a@#{File.basename(dir)}"], result.records
      assert_includes log.string, "root #{dir}"
    end
  end

  def test_root_works_in_workers
    in_tmpdir do |dir|
      result = Metacrunch::Testing.run(write_project(dir), "rooted", workers: 2)

      assert_equal ["a@#{File.basename(dir)}"], result.records
    end
  end

  def test_a_transform_gets_the_root_of_the_job_that_uses_it
    in_tmpdir do |dir|
      assert_equal ["x:#{File.basename(dir)}"], Metacrunch::Testing.run(write_project(dir), "labeled").records
    end
  end

  def test_job_run_takes_the_root_from_project_or_working_directory
    in_tmpdir do |dir|
      project = write_project(dir)
      job = project.fetch("rooted")
      FileUtils.mkdir_p(File.join(dir, "sub"))
      results = [job.run(logger: SILENT, project:), Dir.chdir(File.join(dir, "sub")) { job.run(logger: SILENT) }]

      assert_equal [[:ok, 1], [:ok, 1]], results.map { [it.status, it.stats.read] }
    end
  end

  def test_root_without_a_project_raises
    in_tmpdir do |dir|
      job = Metacrunch.job { params { param :input, String, default: root.join("x") } }
      error = Dir.chdir(dir) { assert_raises(Metacrunch::ProjectError) { job.run(logger: SILENT) } }

      assert_equal "no Metacrunchfile found in #{dir} or above", error.message
    end
  end

  def test_finding_the_root_does_not_load_the_project
    in_tmpdir do |dir|
      write_file(dir, "Metacrunchfile", "raise \"must not load\"\n")
      invoker = Metacrunch::Invoker.new(project: -> { raise "must not load" }, logger: SILENT, env: {})

      assert_equal Pathname(dir), Dir.chdir(dir) { invoker.root }
    end
  end

  def test_commands_get_root_in_params_too
    in_tmpdir do |dir|
      run = Metacrunch::Testing.invoke(write_project(dir), "where")

      assert_equal [File.join(dir, "out"), dir], run.value
    end
  end

  private

  def write_project(dir)
    write_root_project(dir)
    Metacrunch.load_project(dir)
  end

end
```

- [ ] **Step 2: Write the failing CLI tests**

`test/cli/root_cli_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RootCliTest < Minitest::Test

  include CliHelper
  include CredentialsHelper
  include RootFixtures

  def test_a_job_runs_by_name_from_a_subdirectory
    in_tmpdir do |dir|
      write_root_project(dir)
      code, out, = Dir.chdir(File.join(dir, "jobs")) { cli("rooted") }

      assert_equal [0, "\"a@#{File.basename(dir)}\"\n"], [code, out]
    end
  end

  def test_help_shows_the_absolute_default
    in_tmpdir do |dir|
      write_root_project(dir)
      code, out, = Dir.chdir(dir) { cli("rooted", "--help") }

      assert_equal 0, code
      assert_includes out, "default: #{dir}/data/in.txt"
    end
  end

  def test_help_by_path_does_not_load_the_metacrunchfile
    in_tmpdir do |dir|
      write_root_project(dir)
      write_file(dir, "Metacrunchfile", "raise \"must not load\"\n")
      code, out, = Dir.chdir(dir) { cli("run", "jobs/rooted.rb", "--help") }

      assert_equal 0, code
      assert_includes out, "default: #{dir}/data/in.txt"
    end
  end

  def test_root_outside_a_project_ends_with_status_2
    in_tmpdir do |dir|
      path = write_file(dir, "rooted.rb", ROOTED)
      code, _out, err = Dir.chdir(dir) { cli("run", path) }

      assert_equal 2, code
      assert_includes err, "no Metacrunchfile found in #{dir} or above"
    end
  end

  # By path from the temporary directory's parent, which has no
  # Metacrunchfile above it.
  def test_command_help_with_a_root_default
    in_tmpdir do |dir|
      write_root_project(dir)
      by_name = Dir.chdir(dir) { cli("where", "--help") }
      by_path = Dir.chdir(File.dirname(dir)) { cli("run", File.join(dir, "commands/where.rb"), "--help") }

      assert_equal 0, by_name[0]
      assert_includes by_name[1], "default: #{dir}/out"
      assert_equal 2, by_path[0]
      assert_includes by_path[2], "no Metacrunchfile found"
    end
  end

  def test_a_recipe_outside_the_project_gets_the_project_root
    in_tmpdir do |dir|
      in_tmpdir do |gem_dir|
        write_file(gem_dir, "gemjob.rb", "# frozen_string_literal: true\n\n" \
                                         "Metacrunch.job(\"gemjob\") { source [root.to_s] }\n")
        write_file(dir, "Metacrunchfile", "Metacrunch.load_files #{File.join(gem_dir, "*.rb").inspect}\n")
        code, out, = Dir.chdir(dir) { cli("gemjob") }

        assert_equal [0, "#{dir.inspect}\n"], [code, out]
      end
    end
  end

end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/root_test.rb test/cli/root_cli_test.rb`
Expected: FAIL with `NameError: undefined local variable or method 'root'`.

- [ ] **Step 4: Implement the root source**

`lib/metacrunch/invoker.rb`:

```ruby
    # The root of the project, a Pathname. While the project is a Proc
    # (loaded when a name first needs it), the nearest Metacrunchfile above
    # the working directory is found without loading it. Raises
    # ProjectError without one.
    def root
      return @project.root if @project.is_a?(Project)

      file = Project.find(Dir.pwd) if @project.is_a?(Proc)
      raise ProjectError, "no #{Project::FILE} found in #{Dir.pwd} or above" unless file

      Pathname(File.dirname(file))
    end
```

`lib/metacrunch/use_context.rb`:

```ruby
    # The root of the project the job is built in (see Invoker#root).
    def root = @resolver.root
```

- [ ] **Step 5: Implement the root callable in recipes**

`lib/metacrunch/recipe_params.rb`:

```ruby
    # The root of the project the recipe runs in, a Pathname: in
    # statements, hooks and steps. Raises ProjectError if the call has no
    # project.
    def root
      raise ProjectError, Params::NO_ROOT unless @root

      @root.call
    end

    private

    # binder: ... describe: ... root: a callable that returns the project
    # root (see Invoker#root), or nil.
    def init_params(binder, describe, root = nil)
      @binder = binder
      @describe = describe
      @root = root
      ...
```

`params` and `ensure_params_bound` create `Params.new(root: @root)`. Make `root` public in `RecipeParams` (above `private`).

`lib/metacrunch/params.rb`:

```ruby
    NO_ROOT = "root needs a project, and none was given"

    # root: a callable that returns the project root, for defaults such as
    # root.join("data/titles.jsonl"); nil where there is none.
    def initialize(root: nil)
      @definitions = {}
      @args_definition = nil
      @root = root
    end

    # The root of the project, a Pathname; see Invoker#root.
    def root
      raise ProjectError, NO_ROOT unless @root

      @root.call
    end
```

`lib/metacrunch/builder.rb`:

```ruby
    def initialize(binder:, logger:, describe: false, context: nil, root: nil, transform: nil, stack: [])
      init_params(binder, describe, root || (context && -> { context.root }))
```

`lib/metacrunch/command_builder.rb`: `def initialize(binder:, describe: false, root: nil)` → `init_params(binder, describe, root)`.

`lib/metacrunch/command.rb`: `def prepare(binder:, root: nil)` → `CommandBuilder.new(binder:, root:)`; `def describe(root: nil)` → `CommandBuilder.new(binder: nil, describe: true, root:)`.

`lib/metacrunch/job.rb`, `lib/metacrunch/transform.rb`: `def describe(root: nil)` → `Builder.new(binder: nil, logger: Metacrunch.logger, describe: true, root:, ...)`.

`lib/metacrunch/invoker.rb`: `prepare` passes `root: method(:root)` to `command.prepare`.

`lib/metacrunch/cli/job_command.rb`: `schema = declaration.describe(root: invoker.method(:root))`.

`lib/metacrunch/testing.rb` (`invoke`): `command.prepare(binder: ..., root: invoker.method(:root))`.

Comments: the comment of `CommandScope#root` says "see Invoker#root"; the class comments of `Builder` and `CommandBuilder` mention root.

- [ ] **Step 6: Run the new tests, then the suite**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/root_test.rb test/cli/root_cli_test.rb`
Expected: PASS.
Run: `bundle exec rake`
Expected: all pass, coverage thresholds hold, no offenses.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "Give jobs and transforms root, as commands have it

root is the root of the project a call runs in, in all three kinds of
recipes: in statements, params blocks, hooks and steps. A default like
root.join(\"data/titles.jsonl\") works from any directory of the
project. Finding the root does not load the Metacrunchfile, so --help of
a job by path still does not. Without a project, root raises
ProjectError when it is called.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: *Failure* for failed records

**Files:**
- Modify: `lib/metacrunch/builder.rb` (`ON_FAILURE_POLICIES`, `failures`, `on_failure`, `build`, `job_only!` comment), `lib/metacrunch/pipeline.rb`, `lib/metacrunch/sink_outlet.rb`, `lib/metacrunch/processor.rb:233-236`, `lib/metacrunch/engine.rb:94`, `lib/metacrunch/run_options.rb`, `lib/metacrunch/cli/run.rb` (options, `JOB_OPTIONS`), `lib/metacrunch/cli/check.rb:31-32,53-57`, `lib/metacrunch/cli/trace.rb:62`, `lib/metacrunch/testing.rb` (`Result`, memory sinks), `lib/metacrunch/json_lines.rb:191`, `lib/metacrunch/executor/fork/worker.rb:31` (comment)
- Modify: `examples/catalog.rb`, `examples/sanitize.rb`, `examples/project/jobs/catalog.rb`, `examples/lib/issue_report.rb`, `examples/Readme.md`
- Modify tests and fixtures: every hit of the greps in Step 5
- Test: `test/unit/builder_test.rb`, `test/unit/transform_test.rb`, `test/cli/run_flags_test.rb`, `test/cli/check_test.rb`, `test/unit/sink_outlet_test.rb`

**Interfaces:**
- Produces: DSL `failures(object, batch: nil)`, `on_failure(policy, max_failures: nil)`; `Pipeline` fields `failures`, `on_failure`, `max_failures`; `RunOptions` fields `failures`, `on_failure`, `max_failures`; CLI `--failures PATH`, `--on-failure abort|skip`, `--max-failures N`; `Testing::Result#failures`.

- [ ] **Step 1: Write the failing tests**

`test/unit/builder_test.rb` (use the file's helper that builds a pipeline from a recipe, `build_pipeline`):

```ruby
  def test_failures_and_the_failure_policy
    sink = CollectingSink.new
    pipeline = build_pipeline do
      source []
      failures sink, batch: 5
      on_failure :skip, max_failures: 3
    end

    assert_equal [sink, 5, :skip, 3],
                 [pipeline.failures.sink, pipeline.failures.batch, pipeline.on_failure, pipeline.max_failures]
  end

  def test_the_failure_policy_is_checked
    messages = [-> { on_failure :retry }, -> { on_failure :abort, max_failures: 1 }].map do |statement|
      assert_raises(ArgumentError) { build_pipeline { source []; instance_exec(&statement) } }.message
    end

    assert_equal ["on_failure must be one of [:abort, :skip], got :retry",
                  "max_failures must be a non-negative Integer and needs on_failure :skip"], messages
  end

  def test_the_old_names_are_gone
    [-> { errors CollectingSink.new }, -> { on_error :skip }].each do |statement|
      assert_raises(NoMethodError) { build_pipeline { source []; instance_exec(&statement) } }
    end
  end
```

`test/unit/transform_test.rb`:

```ruby
  def test_a_transform_has_no_failure_sink_or_policy
    messages = [-> { failures CollectingSink.new }, -> { on_failure :skip }].map do |statement|
      transform = Metacrunch.transform("t") { instance_exec(&statement) }
      assert_raises(ArgumentError) { Metacrunch::Testing.run(transform, source: []) }.message
    end

    assert_equal ["transform t: a transform has no failures; the job that uses it decides",
                  "transform t: a transform has no on_failure; the job that uses it decides"], messages
  end
```

`test/cli/run_flags_test.rb` (uses `cli` and the fixture jobs; `sanitize.rb` reads stdin and fails a record whose year is no number):

```ruby
  def test_failures_options
    path = File.join(@dir, "failures.jsonl")
    code, = cli("run", "--failures", path, "--on-failure", "skip", "--max-failures", "10",
                "-o", File.join(@dir, "out.jsonl"), job("sanitize.rb"),
                stdin: "{\"id\":\"a\",\"title\":\"T\",\"year\":\"n.d.\"}\n")

    assert_equal 3, code
    assert_includes File.read(path), "\"id\":\"a\""
  end

  def test_the_old_options_are_gone
    ["--errors", "--on-error", "--max-errors"].each do |option|
      code, _out, err = cli("run", option, "x", job("double.rb"))

      assert_equal 2, code
      assert_includes err, "invalid option: #{option}"
    end
  end
```

`test/cli/check_test.rb`: the label column gets one character wider (`ljust(10)`), so every expected row gains a space after its label; lines 21-22 become `  failures   JsonLinesFile` and `  on_failure skip, max_failures 5`, line 33 `  on_failure abort`.

`test/unit/sink_outlet_test.rb:16,34,38`: the pipeline gets `failures failed` and `on_failure :skip, max_failures: 1`; rename the test to `test_failures_over_max_failures_raise_with_the_step_error_as_cause`; expect "2 failed records exceed max_failures 1".

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec ruby -Itest -Ilib -e 'ARGV.each { require File.expand_path(it) }' test/unit/builder_test.rb test/unit/transform_test.rb test/cli/run_flags_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'failures'` / `'on_failure'` and exit status 2 for `--failures`.

- [ ] **Step 3: Implement**

`lib/metacrunch/pipeline.rb`:

```ruby
  # Immutable description of one run, built from a job's recipe by Builder.
  # sink, rejects and failures are SinkAdapter instances or nil. source is
  # nil for jobs that read the CLI's default input. on_failure and
  # max_failures: the failure policy. limit stops the run after that many
  # records (nil: no limit).
  Pipeline = Data.define(
    :source, :id_extractor, :steps, :sink, :rejects, :failures,
    :on_failure, :max_failures, :profile, :before_hooks, :after_hooks, :params, :logger, :limit
  )
```

`lib/metacrunch/builder.rb`:

```ruby
    ON_FAILURE_POLICIES = [:abort, :skip].freeze
```

`initialize`: `@on_failure = :abort`, `@max_failures = nil`. Replace `errors` and `on_error`:

```ruby
    # The sink for records that failed (a step raised; on_failure :skip).
    def failures(object, batch: nil)
      add_sink(:failures, object, batch)
    end

    # What a failed record does: :abort ends the run, :skip sends it to the
    # failures sink and goes on, up to max_failures.
    def on_failure(policy, max_failures: nil)
      job_only!("on_failure")
      use!
      unless ON_FAILURE_POLICIES.include?(policy)
        raise ArgumentError, "on_failure must be one of #{ON_FAILURE_POLICIES.inspect}, got #{policy.inspect}"
      end
      unless max_failures.nil? || (policy == :skip && max_failures.is_a?(Integer) && !max_failures.negative?)
        raise ArgumentError, "max_failures must be a non-negative Integer and needs on_failure :skip"
      end

      @on_failure = policy
      @max_failures = max_failures
      nil
    end
```

`build`: `failures: @sinks[:failures], on_failure: @on_failure, max_failures: @max_failures`. Comment of `job_only!`: "Source, sinks, the failure policy and profile belong to the job".

`lib/metacrunch/sink_outlet.rb`: `@failures = pipeline.failures`, `@max_failures = pipeline.max_failures`, comments "failed ones to failures. Enforces max_failures", and

```ruby
      raise Error, "#{@failed} failed records exceed max_failures #{@max_failures}", cause: step_error
```

`lib/metacrunch/processor.rb:233-236`: comment "which enforces max_failures"; `raise step_error, cause: error if @pipeline.on_failure == :abort`.

`lib/metacrunch/engine.rb:94`: `[@pipeline.sink, @pipeline.rejects, @pipeline.failures].compact`.

`lib/metacrunch/run_options.rb`: fields and keywords `failures`, `on_failure`, `max_failures`; `side_sinks` key `failures:` with `pipeline.failures`; `records_to_stdout?` uses `failures`; option labels `"--failures"`, `"--rejects/--failures"`; `check_files!` skips `["--rejects", "--failures"]`; comments say failures; and

```ruby
    def failure_policy(pipeline)
      policy = on_failure || pipeline.on_failure
      if max_failures && policy != :skip
        raise UsageError, "--max-failures needs the failure policy skip (add --on-failure skip)"
      end

      {on_failure: policy, max_failures: policy == :skip ? max_failures || pipeline.max_failures : nil}
    end
```

(`apply` calls `**failure_policy(pipeline)`; the class comment says "the failure policy".)

`lib/metacrunch/cli/run.rb`:

```ruby
      JOB_OPTIONS = {input: "-i", output: "-o", rejects: "--rejects", failures: "--failures", limit: "-n",
                     on_failure: "--on-failure", max_failures: "--max-failures", stats: "--stats"}.freeze
```

```ruby
        parser.on("--failures PATH", "Write failed records with their context to PATH") { @options[:failures] = it }
```

```ruby
        parser.on("--on-failure POLICY", "abort or skip, instead of the job's failure policy") do |policy|
          raise UsageError, "--on-failure must be abort or skip" unless ["abort", "skip"].include?(policy)

          @options[:on_failure] = policy.to_sym
        end
        parser.on("--max-failures N", Integer, "Stop after more than N failed records (needs skip)") do |count|
          raise UsageError, "--max-failures must not be negative" if count.negative?

          @options[:max_failures] = count
        end
```

`lib/metacrunch/cli/check.rb`:

```ruby
        rows << ["failures", sink(pipeline.failures)] if pipeline.failures
        rows << ["on_failure", policy(pipeline)]
```

```ruby
      def policy(pipeline)
        return pipeline.on_failure.to_s unless pipeline.max_failures

        "#{pipeline.on_failure}, max_failures #{pipeline.max_failures}"
      end
```

and widen the label column from `ljust(9)` to `ljust(10)` so `on_failure` keeps a space before its value.

`lib/metacrunch/cli/trace.rb:62`: `sink: null, rejects: null, failures: null, on_failure: :skip, max_failures: nil, limit:,`.

`lib/metacrunch/testing.rb`:

```ruby
    # records: what reached the sink. rejects: [record, Rejection] pairs.
    # failures: [record, Failure] pairs.
    Result = Data.define(:records, :rejects, :failures, :stats, :status, :error) do
      def ok? = status == :ok
    end
```

memory sinks `{sink: ..., rejects: ..., failures: MemorySink.new}`; `failures: memory[:failures].records.zip(memory[:failures].contexts.map(&:failure))`.

`lib/metacrunch/json_lines.rb:191`: "Sink for the rejects and failures roles". `lib/metacrunch/executor/fork/worker.rb:31`: "counts failures for max_failures".

- [ ] **Step 4: Rename in examples, fixtures and tests**

Run, then review each hit and rename:

```bash
grep -rnE "on_error|max_errors|--on-error|--max-errors|--errors|^\s*errors\s|errors:|\.errors\b|error policy|errors sink" \
  test examples lib | grep -v "load_errors"
```

- `on_error` → `on_failure`, `max_errors` → `max_failures`, `--on-error` → `--on-failure`, `--max-errors` → `--max-failures`, `--errors` → `--failures`.
- The DSL statement `errors X` → `failures X`; `errors:` as a `Pipeline`/`RunOptions` key → `failures:`; `pipeline.errors`/`result.errors` (of `Testing`) → `.failures`.
- "error policy" → "failure policy", "errors sink" → "failures sink" in messages, comments and `examples/Readme.md`.
- Keep: `load_errors`, `Result#error`, exception classes, file names of fixtures (`errors.jsonl`) unless a test reads them under the new name, `StepError`.

Expected after the renames: the grep shows only `load_errors` hits filtered out, fixture data file names, and prose about Ruby errors (exceptions).

- [ ] **Step 5: Run the suite**

Run: `bundle exec rake`
Expected: all pass, no offenses.

- [ ] **Step 6: Commit**

```bash
git add lib examples test
git commit -m "Call failed records failures throughout

A record fails, which is a failure; an error is an exception. The
failures sink, on_failure with max_failures, --failures, --on-failure,
--max-failures and Testing's result.failures replace the names with
error, so they match ctx.failure, stats.failed, :ok_with_failures and
the summary. check shows failures and on_failure.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Example project, docs, Readme, changelog

**Files:**
- Modify: `examples/project/jobs/catalog.rb` (input default with `root`), `examples/project/commands/catalog/release.rb` (check), `examples/project/test/**` (release test: `CommandResult` where values are compared)
- Modify: `Readme.md`, `docs/jobs.md`, `docs/transforms.md`, `docs/projects.md`, `docs/testing.md`, `docs/cli.md`, `docs/ruby-api.md`, `docs/workers.md`, `docs/credentials.md`, `CHANGELOG.md`
- Test: `test/integration/examples_test.rb` (runs the example project), a scratch script outside the repository for the doc examples

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Example project**

`examples/project/jobs/catalog.rb`: the input parameter gets `default: root.join("data/titles.jsonl")` (instead of a relative default). Run:

```bash
cd examples/project && bundle exec metacrunch catalog --output /tmp/titles.jsonl; echo "exit $?"
cd examples/project/jobs && bundle exec metacrunch catalog --output /tmp/titles.jsonl; echo "exit $?"
cd examples/project && bundle exec rake test
```

Expected: exit 0 both times (the second from a subdirectory), the project's tests pass. Then `bundle exec rake` in the repository (runs `examples_test.rb`).

- [ ] **Step 2: Readme**

- Diagram (line 15): `rejects, failures`.
- Tour job: `param :input, String, default: root.join("data/titles.jsonl"), desc: ...`; `failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")`; `on_failure :skip`.
- The bullets: "`on_failure :skip` lets the run go on when a record fails (...); the record goes to the `failures` sink ..."; add after the source bullet: "`root` is the root of the project, so `root.join(...)` reaches its files from any directory."
- Transforms: "A job inserts its steps with `use "normalize", params: {max_length: 40}`."
- Release command: `result = invoke "catalog", params: {output: release.join("titles.jsonl")}`.
- Test: `result = Metacrunch::Testing.run(PROJECT, "catalog", params: {output: "unused"}, source: records)`.
- Documentation list: "sinks, failures, hooks".

- [ ] **Step 3: docs/**

- `docs/jobs.md`: the overview job uses `root.join(...)` for the input default, `failures ...`, `on_failure :skip, max_failures: 100  # Failures`. Section "Errors" becomes "Failures" and opens with: "A record fails when a step raises for it, which is a failure; an error is an exception. A failure holds its error (`ctx.failure.error`)." The examples become `on_failure :abort` / `on_failure :skip, max_failures: 100` / `max_failures: 0`, "the failures sink". Sinks: `failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")   # failed records (on_failure :skip), ctx.failure`, "`sink` and `rejects` (or `failures`)", "the `rejects` and `failures` roles". Parameters: after the types, "A value from code (`use`, `invoke`, `Job#run`, `Testing`) is given as `params: {...}`: in the declared type or as a String; a Pathname counts as its path, and `nil` means not given. `root` is the root of the project the call runs in (see [Projects](projects.md)), so `default: root.join("data/titles.jsonl")` works from any directory; `--help` shows it as an absolute path."
- `docs/transforms.md`: `use "catalog:public", params: {fields: ["id", "title"]}`, `use "normalize", params: {max_length: params.max_length}`; the refused statements `source`, `sink`, `rejects`, `failures`, `on_failure` and `profile`; "one `rejects` and `failures` sink, one failure policy"; "`root` is the root of the job's project".
- `docs/projects.md`: release command `result = invoke "catalog", params: {output: release, input: params.input}` (delete the `input = ...` line); the paragraph on `invoke`: "`invoke NAME, params: {...}, workers:, limit:` runs a job, transform or command; params are bound as in a job's `Job#run`: in the declared type or as a String, a Pathname as its path, `nil` as not given." The table of `invoke` results: rows for a job (`Result`), an aborted job (`InvokeError`), a command (`CommandResult` with `status`, `ok?`, `error` (`nil`), `value`), plus: "A command's status is the worst status of the jobs run during its body, nested commands included." After the paragraph that introduces `run { ... }`: "`run` declares what the command does when it runs, as `before` and `after` do for a job." `root`: "`root` (the project root, a `Pathname`) is available in jobs and transforms too."
- `docs/testing.md`: `Testing.run(Metacrunch.load_job("jobs/export.rb"), params: ...)` stays; the project examples become `Metacrunch::Testing.run(PROJECT, "catalog:public", params: {fields: ["id"]}, source: [...])` and `Metacrunch::Testing.run(PROJECT, "catalog", params: {output: "unused"})`; `result.failures   # [[record, failure], ...]`; `result.ok?`; "records every `invoke` (`name`, `params`, `options`)"; stubs: "A stub answers with a status, a `Result`, a value or a `CommandResult` for a command, or a callable that gets the params"; the table of addressings from the spec (6.1).
- `docs/cli.md`: `--rejects PATH`, `--failures PATH`; `--on-failure abort\|skip`, `--max-failures N` "Override the job's failure policy"; exit code 3 "(`on_failure :skip`)".
- `docs/ruby-api.md`: `result = job.run(params: {output: "out"}, workers: 4, limit: 1000)`; "`run` takes the job's parameters as `params:` (see [Parameters](jobs.md#parameters)) and the environment for parameters with `env:` as `env:`"; "Invalid values raise `Metacrunch::ParamError`, unknown keys `ArgumentError`"; `job.run(params: {...}, project: Metacrunch.load_project)`; `project.invoke("catalog:release", params: {out: "tmp"})  # a CommandResult`; "`project.invoke` returns a job's `Result` or a command's `CommandResult`".
- `docs/workers.md`: "the `rejects` and `failures` sinks"; `Metacrunch::Testing.run(job, source: records, workers: 2)` stays.
- `docs/credentials.md`: check the sentence on `Testing.run` (no change needed unless it mentions argv).

- [ ] **Step 4: CHANGELOG**

In "Added":
- line 26: "- `rejects` and `failures` sinks."
- line 27: "- Failure policy `on_failure :abort | :skip` with `max_failures`."
- lines 35-36: "(`-i`, `-o`, `--rejects`, `--failures`), `--limit`, `--on-failure`, `--max-failures`, `--stats` ..."
- line 53: "`invoke NAME, params: {...}` chains jobs, transforms and commands and returns a `Result` or `CommandResult`; the exit status reports the worst result."
- line 60: "a job inserts them with `use "normalize", params: {lang: "en"}`".
- New bullet at the end: "- One form for values from code: `use`, `invoke`, `Project#invoke`, `Job#run` and `Metacrunch::Testing` take `params: {...}`, bound by the same rules (a Pathname counts as its path, `nil` as not given). `root` reaches the project's files in jobs, transforms and commands. `Testing.run` takes a project and a name, like `Testing.invoke`; results answer `ok?`."

- [ ] **Step 5: Check the success criteria and run the doc examples**

Run:

```bash
grep -rnE 'invoke[ (]"[^"]+", "|\.run\(\[|use "[^"]+", [a-z_]+:|on_error|max_errors|--errors|--on-error|--max-errors|^\s*errors\s' \
  Readme.md docs/*.md examples lib/metacrunch/templates
```

Expected: no output (only `params:` forms remain).

Then run every example of `Readme.md` and `docs/` once, as for the Readme rewrite: in a scratch directory outside the repository, `metacrunch new catalog`, copy `examples/project/data`, write the code blocks that start with `# PATH` into the project, and run the commands shown (quickstart job and pipe, the tour job by name from `jobs/`, the release command twice, `check`, `trace`, `-w 4`, the testing snippets with `rake test`, the overview job of `docs/jobs.md`, the `invoke` and `Job#run` snippets of `docs/projects.md` and `docs/ruby-api.md`). Expected: each runs as documented; fix the docs where not.

Run: `bundle exec rake`
Expected: all pass, no offenses.

- [ ] **Step 6: Commit**

```bash
git add examples Readme.md docs/*.md CHANGELOG.md
git commit -m "Describe the consistent API in the Readme, docs and changelog

params: for every value from code, root in all recipes, failures for
failed records, CommandResult, and both addressings of Testing.run. The
example project's job reads its input from root, so it runs by name
from any directory of the project.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
