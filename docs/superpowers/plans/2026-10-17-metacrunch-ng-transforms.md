# metacrunch-ng transforms (sub-project 8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Named transforms (`Metacrunch.transform`) hold steps, hooks and parameters without source or sink; a job inserts them with `use "name", key: value`, and a transform runs, traces, checks and tests alone like a job without source and sink.

**Architecture:** `Transform` is a recipe like `Job`, evaluated by the job `Builder` in a transform mode that refuses source, sinks, error policy and profile. `Builder#use` asks a `UseContext` for the transform (an `Invoker` resolves names and paths), evaluates the transform's recipe with the keyword values bound by `Params#bind_values` (then `env:`, the job's credentials store, defaults), and splices its steps (renamed `label/step`) and hooks into the job. Whoever builds a job (`Invoker`, `Job#run`, `Testing.run`) hands the builder a `UseContext`. The engine does not change: a pipeline stays a flat list of steps.

**Tech Stack:** Ruby 4.0, standard library, Minitest 6, SimpleCov, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** `docs/superpowers/specs/2026-10-17-metacrunch-ng-transforms-design.md` (builds on the specs of sub-projects 1, 6 and 7 in the same directory)

## Global Constraints

- `required_ruby_version = ">= 4.0"`, gem version stays `5.0.0.pre`.
- Runtime dependency: `logger` only. No new gems.
- Library files are loaded with `require_relative` from `lib/metacrunch.rb`: `transform.rb` right after `job.rb` (the `Loader` needs the constant), `use_context.rb` right after `loader.rb`. CLI-only files from `lib/metacrunch/cli.rb`.
- Every Ruby file starts with `# frozen_string_literal: true`, also test fixtures, example files and Ruby files that tests write.
- Names: one or more parts matching `[a-z0-9][a-z0-9_-]*`, separated by `:`. Jobs, transforms and commands share one namespace; reserved: `run`, `check`, `trace`, `new`, `credentials`, `help`.
- Messages that list kinds use this order: "job, transform, command or file" (unknown targets), "job, transform or command" (project and loader nouns).
- A transform's steps are named `LABEL/STEP` (`normalize/map#1`); a second use of the same label in one recipe gets `LABEL#2`. `/` is refused in explicit step names. Generated step numbers count the step statements of a recipe, `use` included as one.
- Exit codes do not change: 0 ok, 1 aborted, 2 usage (unknown names, invalid parameters, load errors), 3 finished with failed records, 128 + n for signal n.
- The library never calls `exit`. Commands never use `$stdin`, `$stdout` or `$stderr` directly. The CLI never changes directory.
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
  - Single file: `bundle exec ruby -w -Ilib -Itest <file>`; several: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' <files>`.
  - Full suite with coverage thresholds (95 % lines, 90 % branches) and lint: `bundle exec rake` (about 16 s, 765 tests before this plan).
  - Minitest 6 has no `stub`; tests replace singleton methods with `Override#override` (`test/support/override.rb`).
  - Tests that need files use `in_tmpdir` and `write_file` from `CredentialsHelper` (`test/support/credentials_helper.rb`); `in_tmpdir` yields the real path.
  - A Hash with String keys passed to a test helper that also takes keywords is written with braces (`build_job({"scale" => SCALE})`), or Ruby 3 takes it for keywords.
  - In-process CLI tests that need a project change into it with `Dir.chdir(dir) { cli(...) }` and pass `env: {}`. Subprocess tests set `HOME` to a temporary directory and clear `METACRUNCH_ENV`, `METACRUNCH_CREDENTIALS` and `METACRUNCH_MASTER_KEY`.
- Examples, messages and docs stay generic: no internal names of a library or institution.
- Repo docs, code comments and commit messages are in English.
- Every commit message ends with this line:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

## Review Focus

These are inputs and conditions the spec implies but does not spell out, ordered by how likely they are to bite a user first. Each one has a test in the task named in brackets.

1. **The same transform twice in one job with different values** (`use "scale", factor: 2` then `use "scale", factor: 10`): each use has its own parameters, and the step names stay unique (`scale/map#1`, `scale#2/map#1`). [Task 3]
2. **A record rejected or failed inside a transform**: it reaches the job's `rejects` or `errors` sink, and its rejection or failure names the prefixed step (`checks/reject#1`), so the files say where it happened. [Task 3]
3. **A transform's `before` hook builds a lookup table that its steps use, run with `-w 2`**: the workers inherit the table, and the output equals the inline run. [Task 6]
4. **A value given at `use` and the transform's `env:` variable**: the given value wins; `nil` (an optional job parameter left unset) falls through to the variable. [Task 4]
5. **A test that runs a job from another working directory** (`rake` from the repository root, the project in a subdirectory): `Testing.run(job, project: PROJECT)` resolves names there; without `project:` and without a `Metacrunchfile` above, the error says "(no Metacrunchfile found)". [Task 4]

---

## File Structure

```
lib/metacrunch/transform.rb            Transform: name, desc, file, label, pipeline, describe    Tasks 1, 3
lib/metacrunch/builder.rb              transform mode; use; statement numbers, prefixes          Tasks 1, 3
lib/metacrunch/loader.rb               kind Transform, nouns and lists with three kinds          Task 1
lib/metacrunch.rb                      requires; transform, load_transform                       Tasks 1, 3
lib/metacrunch/params.rb               bind_values; messages by name for keywords                Task 2
lib/metacrunch/use_context.rb          UseContext: transform, evaluate, for                      Tasks 3, 4
lib/metacrunch/job.rb                  pipeline(context:), run(project:)                         Tasks 3, 4
lib/metacrunch/invoker.rb              resolve(kind:), pipeline with UseContext, transforms      Task 4
lib/metacrunch/project.rb              nearest, fetch message                                    Task 4
lib/metacrunch/testing.rb              run(project:) and transforms, invoke messages             Task 4
lib/metacrunch/cli.rb                  unknown message (Task 4), help section "Transforms"       Tasks 4, 5
lib/metacrunch/cli/job_command.rb      -j text, no-target message                                Task 5
lib/metacrunch/cli/run.rb              summary                                                   Task 5
lib/metacrunch/cli/check.rb            title "transform"                                         Task 5
test/support/fake_credentials.rb       FakeCredentials                                           Task 2
test/fixtures/jobs/shared.rb           a transform, a job and a command in one file              Task 1
examples/project/                      transform, second job, test                               Task 7
Readme.md, CHANGELOG.md, examples/Readme.md                                                      Tasks 7, 8
```

---
### Task 1: Transforms and the transform mode of the builder

**Files:**
- Create: `lib/metacrunch/transform.rb`
- Modify: `lib/metacrunch/builder.rb` (`transform:`, refusals, `recipe_kind`)
- Modify: `lib/metacrunch/loader.rb` (kind `Transform`, nouns)
- Modify: `lib/metacrunch.rb` (require, `transform`, `load_transform`)
- Create: `test/fixtures/jobs/shared.rb`
- Test: `test/unit/transform_test.rb` (new), `test/unit/loader_test.rb`

**Interfaces:**
- Consumes: `Names.check!`, `Names.check_desc!`, `RecipeParams::DESCRIBED`.
- Produces:
  - `Metacrunch::Transform.new(name = nil, desc: nil, &recipe)`; `#name`, `#desc` (String or nil), `#file` / `#file=`
  - `Transform#label -> String` (the name, else the base name of `file` without `.rb`, else `"transform"`)
  - `Transform#pipeline(binder:, logger: Metacrunch.logger) -> Pipeline` (Task 3 adds `context: nil, stack: []`)
  - `Transform#describe -> Params`
  - `Builder.new(binder:, logger:, describe: false, transform: nil)` (Task 3 adds `context: nil, stack: []`)
  - `Metacrunch.transform(name = nil, desc: nil, &) -> Transform`, registered with the loader
  - `Metacrunch.load_transform(path, name: nil) -> Transform`
  - `Loader::KINDS == {Job => "job", Transform => "transform", Command => "command"}`

- [ ] **Step 1: Write the failing tests for transforms**

`test/unit/transform_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class TransformTest < Minitest::Test

  SILENT = Logger.new(nil)

  # The statements of a job that a transform refuses.
  JOB_STATEMENTS = {
    "source" => proc { source [] },
    "sink" => proc { sink CollectingSink.new },
    "rejects" => proc { rejects CollectingSink.new },
    "errors" => proc { errors CollectingSink.new },
    "on_error" => proc { on_error :skip },
    "profile" => proc { profile true }
  }.freeze

  def test_builds_steps_and_hooks_without_source_and_sinks
    transform = Metacrunch.transform("trim") do
      before { nil }
      map(&:strip)
      reject("Empty", &:empty?)
    end
    pipeline = build(transform)

    assert_equal([["map#1", nil], ["reject#2", "Empty"]], pipeline.steps.map { [it.name, it.reason] })
    assert_equal [nil, nil, nil, nil], [pipeline.source, pipeline.sink, pipeline.rejects, pipeline.errors]
    assert_equal [1, :abort], [pipeline.before_hooks.size, pipeline.on_error]
  end

  def test_refuses_the_statements_of_jobs
    messages = JOB_STATEMENTS.transform_values do |recipe|
      build(Metacrunch.transform("trim", &recipe))
    rescue ArgumentError => e
      e.message
    end
    expected = JOB_STATEMENTS.keys.to_h do |statement|
      [statement, "transform trim: a transform has no #{statement}; the job that uses it decides"]
    end

    assert_equal expected, messages
  end

  def test_binds_its_params_like_a_job
    transform = Metacrunch.transform("scale") do
      params { param :factor, Integer, default: 2 }

      map { it * params.factor }
    end

    assert_equal 6, build(transform, params: {factor: "3"}).steps.first.call(2, nil)
  end

  def test_params_come_first_in_a_transform_too
    transform = Metacrunch.transform do
      map(&:strip)
      params { param :x }
    end
    error = assert_raises(ArgumentError) { build(transform) }

    assert_equal "params { ... } must be the first statement of a transform", error.message
  end

  def test_describe_stops_at_the_first_statement
    transform = Metacrunch.transform("scale") do
      params { param :factor, Integer, default: 2 }

      raise "must not run"
    end

    assert_equal [:factor], transform.describe.definitions.keys
  end

  def test_names_descriptions_and_labels
    named = Metacrunch.transform("text:trim", desc: "Strip strings") { map(&:strip) }
    loaded = Metacrunch.transform { map(&:strip) }.tap { it.file = "/project/transforms/clean_up.rb" }

    assert_equal ["text:trim", "Strip strings", "text:trim"], [named.name, named.desc, named.label]
    assert_equal ["clean_up", "transform"], [loaded.label, Metacrunch.transform { map(&:strip) }.label]
  end

  def test_names_follow_the_name_rules
    error = assert_raises(ArgumentError) { Metacrunch.transform("Trim") { map(&:strip) } }

    assert_match(/invalid transform name "Trim"/, error.message)
  end

  def test_a_transform_needs_a_recipe
    error = assert_raises(ArgumentError) { Metacrunch::Transform.new("trim") }

    assert_equal "a transform needs a block", error.message
  end

  private

  def build(transform, params: {})
    transform.pipeline(binder: ->(schema) { schema.bind_hash(params) }, logger: SILENT)
  end

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/transform_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'transform' for module Metacrunch` (and `NameError: uninitialized constant Metacrunch::Transform`)

- [ ] **Step 3: Write Transform**

`lib/metacrunch/transform.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # A transform is a recipe of steps, hooks and parameters without source
  # and sinks. A job inserts its steps with `use`; alone it runs like a job
  # without source and sink, from stdin to stdout.
  class Transform

    attr_reader :name, :desc

    # The file the transform was loaded from, else nil. Set by Loader.
    attr_accessor :file

    # name: see Names; nil for a transform that is used by path or as an
    # object only. desc: one line for the list in `metacrunch --help`.
    def initialize(name = nil, desc: nil, &recipe)
      raise ArgumentError, "a transform needs a block" unless recipe

      @name = name.nil? ? nil : Names.check!(name, "transform")
      @desc = Names.check_desc!(desc)
      @recipe = recipe
    end

    # The name for messages and step prefixes: the name, else the base name
    # of the file, else "transform".
    def label
      return @name if @name

      file ? File.basename(file, ".rb") : "transform"
    end

    # Evaluates the recipe in transform mode. The pipeline has steps and
    # hooks, but no source and no sinks. binder: see Job#pipeline.
    def pipeline(binder:, logger: Metacrunch.logger)
      builder = Builder.new(binder:, logger:, transform: self)
      builder.instance_exec(&@recipe)
      builder.build
    end

    # The declared parameters. Evaluates the recipe only up to its first
    # statement.
    def describe
      builder = Builder.new(binder: nil, logger: Metacrunch.logger, describe: true, transform: self)
      catch(RecipeParams::DESCRIBED) do
        builder.instance_exec(&@recipe)
        builder.build
      end
    end

  end
end
```

In `lib/metacrunch.rb`, add after `require_relative "metacrunch/job"`:

```ruby
require_relative "metacrunch/transform"
```

and add after the method `job`:

```ruby
    # Defines a transform. Like job, it is registered with the loader inside
    # a file that Loader loads.
    def transform(name = nil, desc: nil, &)
      Transform.new(name, desc:, &).tap { |transform| Loader.register(transform) }
    end
```

and after the method `load_job`:

```ruby
    def load_transform(path, name: nil)
      Loader.load(path, name:, kind: Transform)
    end
```

- [ ] **Step 4: Give the builder its transform mode**

In `lib/metacrunch/builder.rb`:

Replace the class comment and `initialize`:

```ruby
  # Evaluates a job or transform recipe with instance_exec and collects
  # what the DSL declares. #build returns the Pipeline.
  class Builder

    include RecipeParams

    ON_ERROR_POLICIES = [:abort, :skip].freeze

    attr_reader :logger

    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    # transform: the Transform whose recipe this builder evaluates; it
    # refuses source, sinks, error policy and profile. nil for a job.
    def initialize(binder:, logger:, describe: false, transform: nil)
      init_params(binder, describe)
      @logger = logger
      @transform = transform
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

Make `job_only!` the first line of `source`, `on_error`, `profile` and `add_sink`:

```ruby
    def source(enumerable = nil, id: nil)
      job_only!("source")
      use!
```

```ruby
    def on_error(policy, max_errors: nil)
      job_only!("on_error")
      use!
```

```ruby
    def profile(enabled)
      job_only!("profile")
      use!
```

```ruby
    def add_sink(role, object, batch)
      job_only!(role.to_s)
      use!
```

Replace `def recipe_kind = "job"` with:

```ruby
    def recipe_kind = @transform ? "transform" : "job"

    # Source, sinks, the error policy and profile belong to the job that
    # uses a transform.
    def job_only!(statement)
      return unless @transform

      raise ArgumentError,
            "transform #{@transform.label}: a transform has no #{statement}; the job that uses it decides"
    end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/transform_test.rb`
Expected: PASS (8 runs). The loader still knows two kinds; these tests do not load files.

- [ ] **Step 6: Write the failing loader tests**

`test/fixtures/jobs/shared.rb`:

```ruby
# frozen_string_literal: true

# A transform, a job and a command in one file; -j selects one.
Metacrunch.transform("trim", desc: "Strip strings") { map(&:strip) }
Metacrunch.job("lines", desc: "Print the lines") { source [" a "] }
Metacrunch.command("tidy", desc: "Tidy up") { run { :tidy } }
```

In `test/unit/loader_test.rb`, change the expectation in `test_unknown_names_list_jobs_and_commands`:

```ruby
    assert_match(/no job, transform or command named x in .*available: export, publish/, error.message)
```

and add before `private` (or, if the file has none, before the final `end` of the class):

```ruby
  def test_collects_transforms_and_loads_each_kind
    declarations = Metacrunch::Loader.cached(fixture("shared.rb"))

    assert_equal [Metacrunch::Transform, Metacrunch::Job, Metacrunch::Command], declarations.map(&:class)
    assert_equal ["trim", "lines"], [Metacrunch.load_transform(fixture("shared.rb")).name,
                                     Metacrunch.load_job(fixture("shared.rb")).name]
  end

  def test_a_file_without_transform_defines_none
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_transform(fixture("double.rb")) }

    assert_match(/no transform defined in .*double\.rb/, error.message)
  end

  def test_three_kinds_are_listed_with_commas
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch::Loader.load(fixture("shared.rb")) }

    assert_match(/defines several transforms, jobs and commands \(trim, lines, tidy\); select one with --job NAME/,
                 error.message)
  end
```

- [ ] **Step 7: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/loader_test.rb`
Expected: FAIL: `KeyError: key not found: Metacrunch::Transform` in the new tests, and the changed message in `test_unknown_names_list_jobs_and_commands`

- [ ] **Step 8: Teach the loader the third kind**

In `lib/metacrunch/loader.rb`, replace the module comment, `KINDS`, `load` and `plural`:

```ruby
  # Loads files that declare jobs, transforms and commands. Metacrunch.job,
  # Metacrunch.transform and Metacrunch.command register what they declare
  # with the load that is in progress on the current thread. A file is
  # loaded again only when it has changed, because loading it twice would
  # redefine its constants.
  module Loader

    KEY = :metacrunch_loading
    KINDS = {Job => "job", Transform => "transform", Command => "command"}.freeze
```

```ruby
    # The job, transform or command that path declares. name selects one of
    # several; kind (Job, Transform or Command) considers only those.
    def load(path, name: nil, kind: nil)
      raise JobLoadError, "file not found: #{path}" unless File.file?(path)

      declarations = cached(path)
      declarations = declarations.grep(kind) if kind
      select_declaration(declarations, path, name&.to_s, kind ? KINDS.fetch(kind) : "job, transform or command")
    end
```

```ruby
    # "jobs", "jobs and commands" or "transforms, jobs and commands", in the
    # order of the file.
    def plural(declarations)
      words = declarations.map { "#{KINDS.fetch(it.class)}s" }.uniq
      [words[0...-1].join(", "), words.last].reject(&:empty?).join(" and ")
    end
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/transform_test.rb test/unit/loader_test.rb`
Expected: PASS

- [ ] **Step 10: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 11: Commit**

```bash
git add lib/metacrunch/transform.rb lib/metacrunch/builder.rb lib/metacrunch/loader.rb lib/metacrunch.rb \
        test/unit/transform_test.rb test/unit/loader_test.rb test/fixtures/jobs/shared.rb
git commit -m "$(cat <<'EOF'
Add transforms: recipes of steps without source and sinks

Metacrunch.transform declares a recipe that the builder evaluates in a
transform mode: source, sinks, on_error and profile raise, since the job
that uses the transform decides them. The loader knows transforms as a
third kind, and Metacrunch.load_transform loads one from a file.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 2: Binding the keyword values of `use`

**Files:**
- Modify: `lib/metacrunch/params.rb` (`bind_values`, keyword labels)
- Create: `test/support/fake_credentials.rb`
- Test: `test/unit/params_values_test.rb` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Params#bind_values(values, env: ENV, credentials: nil) -> values Data` — values: Hash with Symbol or String keys naming a `param` or the `args`; a value of the declared type or a String; `nil` = not given. Raises `ArgumentError` for unknown keys ("unknown parameter :lnag (known: lang, files)", "(known: none)"), `ParamError` for missing or invalid values, naming parameters by name ("missing required parameter code (CODE unset; api.code: no credentials)", "invalid value for limit: \"many\" is not an Integer").
  - `FakeCredentials.new(hash)` (test support): `lookup(path)`, `origin(path)`, `missing(path)` like `Credentials::Store`.

- [ ] **Step 1: Write the test support and the failing tests**

`test/support/fake_credentials.rb`:

```ruby
# frozen_string_literal: true

# Credentials with fixed values, answering like a Credentials::Store.
class FakeCredentials

  def initialize(data)
    @data = data
  end

  def lookup(path) = @data[path]

  def origin(path) = "credential #{path} in test"

  def missing(path) = "#{path} not in test"

end
```

`test/unit/params_values_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class ParamsValuesTest < Minitest::Test

  def test_binds_typed_values_and_strings
    bound = schema.bind_values({lang: "en", limit: "5", ratio: 2, strict: true, tags: ["a"], files: ["x.xml"]})

    assert_equal ["en", 5, 2.0, true, ["a"], ["x.xml"]],
                 [bound.lang, bound.limit, bound.ratio, bound.strict, bound.tags, bound.files]
    assert_predicate bound.files, :frozen?
  end

  def test_string_keys_and_a_single_argument_work_too
    bound = schema.bind_values({"lang" => "en", "files" => "x.xml"})

    assert_equal ["en", ["x.xml"]], [bound.lang, bound.files]
  end

  def test_nil_counts_as_not_given
    bound = schema.bind_values({lang: nil, limit: nil, files: nil})

    assert_equal ["de", nil, []], [bound.lang, bound.limit, bound.files]
  end

  def test_missing_values_come_from_env_then_credentials
    credentials = FakeCredentials.new("api.code" => "credential")
    code = ->(values, env) { secret_schema.bind_values(values, env:, credentials:).code }

    assert_equal ["given", "env", "credential"],
                 [code.call({code: "given"}, {"CODE" => "env"}), code.call({}, {"CODE" => "env"}), code.call({}, {})]
  end

  def test_unknown_keys_raise_argument_errors
    messages = [schema, Metacrunch::Params.new].map do |params|
      assert_raises(ArgumentError) { params.bind_values({lnag: "en"}) }.message
    end

    assert_equal ["unknown parameter :lnag (known: lang, limit, ratio, strict, tags, files)",
                  "unknown parameter :lnag (known: none)"], messages
  end

  def test_messages_name_parameters_by_their_name
    hidden = assert_raises(Metacrunch::ParamError) { secret_schema.bind_values({pin: "abc"}, env: {}) }
    missing = assert_raises(Metacrunch::ParamError) { secret_schema.bind_values({}, env: {}) }
    invalid = assert_raises(Metacrunch::ParamError) { schema.bind_values({limit: "many"}) }

    assert_equal "invalid value for pin: (hidden) is not an Integer", hidden.message
    assert_equal "missing required parameter code (CODE unset; api.code: no credentials)", missing.message
    assert_equal "invalid value for limit: \"many\" is not an Integer", invalid.message
  end

  def test_args_keep_their_limits
    at_least_one = Metacrunch::Params.new.tap { it.args :files, min: 1 }
    error = assert_raises(Metacrunch::ParamError) { at_least_one.bind_values({}) }

    assert_equal "expected at least 1 argument(s) for files, got 0", error.message
  end

  def test_the_command_line_still_names_options
    error = assert_raises(Metacrunch::ParamError) { secret_schema.bind_argv([], env: {}) }

    assert_equal "missing required parameter --code (CODE unset; api.code: no credentials)", error.message
  end

  private

  def schema
    Metacrunch::Params.new.tap do |params|
      params.param :lang, String, default: "de"
      params.param :limit, Integer
      params.param :ratio, Float
      params.param :strict, :bool, default: false
      params.param :tags, Array
      params.args :files
    end
  end

  # pin comes first, so a test can reach its invalid value before code is
  # found missing.
  def secret_schema
    Metacrunch::Params.new.tap do |params|
      params.param :pin, Integer, credential: "api.pin"
      params.param :code, String, env: "CODE", credential: "api.code", required: true
    end
  end

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/params_values_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'bind_values'` (the last test passes already)

- [ ] **Step 3: Write bind_values**

In `lib/metacrunch/params.rb`, change the class comment's first sentence to:

```ruby
  # The parameters a job declares in `params { ... }`, and their binding
  # from CLI arguments (#bind_argv), the keyword values of `use`
  # (#bind_values) or a Hash in tests (#bind_hash). Bound values are frozen.
```

Add after `bind_hash`:

```ruby
    # Binds the keyword values of `use`. A value may have the declared type
    # or be a String, which is converted; nil means "not given". A
    # parameter without a value is read from its env: variable, then from
    # the credentials, then the default. The values come from code, so
    # messages name a parameter by its name, not as option, and a secret
    # gives no warning. Raises ArgumentError for an unknown key.
    def bind_values(values, env: ENV, credentials: nil)
      values = values.transform_keys(&:to_sym)
      args_name = @args_definition&.name
      known = [*@definitions.keys, *args_name]
      unknown = values.keys - known
      if unknown.any?
        raise ArgumentError,
              "unknown parameter #{unknown.first.inspect} (known: #{known.empty? ? "none" : known.join(", ")})"
      end

      given = values.except(args_name).compact
      bound = @definitions.to_h do |name, definition|
        [name, bind(definition, given, env, credentials, nil, keyword: true)]
      end
      build(bound, values[args_name].nil? ? [] : Array(values[args_name]))
    end
```

Replace `bind`, `resolve`, `convert` and `invalid!` with these versions, which carry `keyword:` into the messages, and add `label` after `invalid!`:

```ruby
    def bind(definition, given, env, credentials, warn, keyword: false)
      if given.key?(definition.name)
        warn&.call(secret_warning(definition)) if definition.secret?
        return resolve(definition, given[definition.name], keyword:)
      end

      raw = env_value(definition, env)
      return resolve(definition, raw, origin: "environment variable #{definition.env}", keyword:) unless raw.nil?

      raw = credentials&.lookup(definition.credential) if definition.credential
      return resolve(definition, raw, origin: credentials.origin(definition.credential), keyword:) unless raw.nil?

      resolve(definition, nil, sources: -> { sources(definition, credentials) }, keyword:)
    end
```

```ruby
    def resolve(definition, raw, origin: nil, sources: nil, keyword: false)
      value = raw.nil? ? definition.default : frozen_copy(convert(definition, raw, origin:, keyword:))
      return value unless definition.required && value.nil?

      detail = sources&.call
      raise ParamError, "missing required parameter #{label(definition, keyword)}#{" (#{detail})" if detail}"
    end

    def convert(definition, raw, origin: nil, keyword: false)
      value = raw.is_a?(String) ? CONVERTERS.fetch(definition.type).call(raw) : raw
      value = value.to_f if definition.type == Float && value.is_a?(Integer)
      VALID.fetch(definition.type).call(value) ? value : invalid!(definition, raw, origin, keyword:)
    rescue ArgumentError, TypeError
      invalid!(definition, raw, origin, keyword:)
    end

    # No cause: the converter's error (Integer(), Float(), "not a boolean")
    # would repeat a hidden value.
    def invalid!(definition, raw, origin, keyword: false)
      expected = TYPE_NAMES.fetch(definition.type)
      from = origin ? " from #{origin}" : ""
      shown = definition.secret? ? HIDDEN : raw.inspect
      raise ParamError, "invalid value for #{label(definition, keyword)}#{from}: #{shown} is not #{expected}",
            cause: nil
    end

    # How messages name a parameter: as option (--api-key) for the command
    # line, by name (api_key) for the keyword values of use.
    def label(definition, keyword) = keyword ? definition.name.to_s : definition.option
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/params_values_test.rb test/unit/params_test.rb test/unit/params_credentials_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch/params.rb test/support/fake_credentials.rb test/unit/params_values_test.rb
git commit -m "$(cat <<'EOF'
Bind parameters from keyword values

Params#bind_values takes Ruby values or strings, treats nil as not given
and falls back to env:, credentials and the default, as the command line
does. Unknown keys raise ArgumentError, and messages name parameters by
name, since the values come from code. use in jobs will bind transforms
with it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 3: `use` in recipes

**Files:**
- Create: `lib/metacrunch/use_context.rb`
- Modify: `lib/metacrunch/builder.rb` (`context:`, `stack:`, `use`, statement numbers, prefixes, `/`)
- Modify: `lib/metacrunch/transform.rb` (`pipeline(context:, stack:)`)
- Modify: `lib/metacrunch/job.rb` (`pipeline(context:)`)
- Modify: `lib/metacrunch.rb` (require)
- Test: `test/unit/use_test.rb` (new)

**Interfaces:**
- Consumes: `Transform#label`, `Transform#pipeline`, `Params#bind_values`, `Loader::KINDS`, `FakeCredentials`.
- Produces:
  - `Metacrunch::UseContext.new(resolver:, env:, credentials:, logger:)` — resolver responds to `resolve(target, kind:)` and returns `[declaration, anchor]` (as `Invoker#resolve` will in Task 4).
  - `UseContext#transform(target) -> Transform` — target: `Transform`, `Job`, `Command` or String; raises `ArgumentError` ("use takes transforms; export is a job", "use takes a transform, its name or its path, got nil").
  - `UseContext#evaluate(transform, values, stack:) -> Pipeline` — raises `ArgumentError` "use cycle: a → b → a"; errors of the values get the prefix "use LABEL: ".
  - `Builder.new(binder:, logger:, describe: false, context: nil, transform: nil, stack: [])`
  - `Builder#use(target, **values)` — raises `ArgumentError` "use needs a context: build the job with Job#pipeline(context:)" without context.
  - `Job#pipeline(binder:, logger: Metacrunch.logger, context: nil)`
  - `Transform#pipeline(binder:, logger: Metacrunch.logger, context: nil, stack: [])`

- [ ] **Step 1: Write the failing tests**

`test/unit/use_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class UseTest < Minitest::Test

  SILENT = Logger.new(nil)

  # Resolves names from a Hash, as an Invoker resolves them in a project.
  Resolver = Struct.new(:declarations) do
    def resolve(target, **)
      declaration = declarations.fetch(target) do
        raise Metacrunch::ProjectError, "unknown job, transform, command or file: #{target}"
      end
      [declaration, nil]
    end
  end

  SCALE = Metacrunch.transform("scale") do
    params { param :factor, Integer, default: 2 }

    map { it * params.factor }
  end

  TOKEN = Metacrunch.transform("token") do
    params { param :token, String, env: "TOKEN", credential: "api.token", required: true }

    map { params.token }
  end

  def test_inserts_the_steps_of_a_transform_where_it_is_used
    pipeline = build_job({"scale" => SCALE}) do
      source [1, 2]
      map { it + 1 }
      use "scale", factor: 10
      map { it - 1 }
    end

    assert_equal ["map#1", "scale/map#1", "map#3"], pipeline.steps.map(&:name)
    assert_equal [19, 29], records(pipeline)
  end

  def test_takes_transform_objects_with_their_defaults
    pipeline = build_job do
      source [1]
      use SCALE
    end

    assert_equal [2], records(pipeline)
  end

  def test_the_same_transform_twice_gets_its_own_values_and_a_numbered_prefix
    pipeline = build_job({"scale" => SCALE}) do
      source [1]
      use "scale", factor: 2
      use "scale", factor: 10
    end

    assert_equal ["scale/map#1", "scale#2/map#1"], pipeline.steps.map(&:name)
    assert_equal [20], records(pipeline)
  end

  def test_unnamed_transforms_are_prefixed_with_their_file_or_transform
    from_file = Metacrunch.transform { map(&:to_s) }.tap { it.file = "/project/transforms/stringify.rb" }
    pipeline = build_job do
      source [1]
      use from_file
      use(Metacrunch.transform { map(&:to_s) })
    end

    assert_equal ["stringify/map#1", "transform/map#1"], pipeline.steps.map(&:name)
  end

  def test_generated_numbers_count_statements_and_slashes_are_refused
    pipeline = build_job do
      source [1]
      map { it }
      use SCALE
      filter(name: "positive", &:positive?)
      reject { it > 100 }
    end
    error = assert_raises(ArgumentError) { build_job { source [1]; map(name: "a/b") { it } } }

    assert_equal ["map#1", "scale/map#1", "positive", "reject#4"], pipeline.steps.map(&:name)
    assert_equal "the step name a/b contains /, which is reserved for the prefixes of transforms", error.message
  end

  def test_hooks_run_in_the_order_of_their_statements
    events = []
    noting = Metacrunch.transform do
      before { events << :transform_before }
      after { events << :transform_after }
    end
    pipeline = build_job do
      source []
      before { events << :job_before }
      use noting
      after { events << :job_after }
    end
    Metacrunch::Engine.new(pipeline).run

    assert_equal [:job_before, :transform_before, :transform_after, :job_after], events
  end

  def test_steps_and_hooks_see_the_params_of_their_transform
    seen = []
    shout = Metacrunch.transform do
      params { param :mark, String, default: "!" }

      before { seen << params.mark }
      map { "#{it}#{params.mark}" }
    end
    pipeline = build_job(params: {mark: "?"}) do
      params { param :mark, String }

      source ["a"]
      use shout, mark: "!!"
      map { "#{it}#{params.mark}" }
    end

    assert_equal ["a!!?"], records(pipeline)
    assert_equal ["!!"], seen
  end

  def test_rejected_and_failed_records_name_the_prefixed_step
    checks = Metacrunch.transform("checks") do
      reject("Negative") { it.negative? }
      map { 10 / it }
    end
    rejected = CollectingSink.new
    failed = CollectingSink.new
    pipeline = build_job do
      source [-1, 0, 5]
      use checks
      rejects rejected
      errors failed
      on_error :skip
    end
    Metacrunch::Engine.new(pipeline).run

    assert_equal ["checks/reject#1"], rejected.contexts.map { it.rejection.step }
    assert_equal ["checks/map#2"], failed.contexts.map { it.failure.step }
  end

  def test_values_come_first_then_env_then_credentials
    credentials = FakeCredentials.new("api.token" => "credential")
    token = ->(env, **values) { records(build_job(env:, credentials:) { source [1]; use TOKEN, **values }) }

    assert_equal ["given"], token.call({"TOKEN" => "env"}, token: "given")
    assert_equal ["env"], token.call({"TOKEN" => "env"})
    assert_equal ["credential"], token.call({})
  end

  def test_errors_of_the_values_name_the_transform
    unknown = assert_raises(ArgumentError) { build_job { source []; use SCALE, factr: 3 } }
    invalid = assert_raises(Metacrunch::ParamError) { build_job { source []; use SCALE, factor: "many" } }
    missing = assert_raises(Metacrunch::ParamError) { build_job { source []; use TOKEN } }

    assert_equal "use scale: unknown parameter :factr (known: factor)", unknown.message
    assert_equal "use scale: invalid value for factor: \"many\" is not an Integer", invalid.message
    assert_equal "use token: missing required parameter token (TOKEN unset; api.token: no credentials)",
                 missing.message
  end

  def test_use_takes_transforms_only
    declarations = {"export" => Metacrunch.job("export") { source [] },
                    "publish" => Metacrunch.command("publish") { run { nil } }}
    messages = ["export", "publish", Metacrunch.job { source [] }, nil].map do |target|
      build_job(declarations) { source []; use target }
    rescue ArgumentError => e
      e.message
    end

    assert_equal ["use takes transforms; export is a job", "use takes transforms; publish is a command",
                  "use takes transforms; the target is a job",
                  "use takes a transform, its name or its path, got nil"], messages
  end

  def test_unknown_names_raise_project_errors
    error = assert_raises(Metacrunch::ProjectError) { build_job { source []; use "nope" } }

    assert_equal "unknown job, transform, command or file: nope", error.message
  end

  def test_cycles_raise_with_the_chain
    declarations = {}
    declarations["a"] = Metacrunch.transform("a") { use "b" }
    declarations["b"] = Metacrunch.transform("b") { use "a" }
    error = assert_raises(ArgumentError) { build_job(declarations) { source []; use "a" } }

    assert_equal "use cycle: a → b → a", error.message
  end

  def test_nested_transforms_give_nested_prefixes
    inner = Metacrunch.transform("inner") { map { it + 1 } }
    outer = Metacrunch.transform("outer") do
      use inner
      map { it * 2 }
    end
    pipeline = build_job do
      source [1]
      use outer
    end

    assert_equal ["outer/inner/map#1", "outer/map#2"], pipeline.steps.map(&:name)
    assert_equal [4], records(pipeline)
  end

  def test_a_transform_alone_cannot_use_itself
    looping = Metacrunch.transform("loop") { use "loop" }
    binder = ->(schema) { schema.bind_hash({}) }
    context = context_for({"loop" => looping})
    error = assert_raises(ArgumentError) { looping.pipeline(binder:, logger: SILENT, context:) }

    assert_equal "use cycle: loop → loop", error.message
  end

  def test_use_needs_a_context
    job = Metacrunch.job { source []; use SCALE }
    error = assert_raises(ArgumentError) { job.pipeline(binder: ->(schema) { schema.bind_hash({}) }, logger: SILENT) }

    assert_equal "use needs a context: build the job with Job#pipeline(context:)", error.message
  end

  def test_help_never_evaluates_use
    job = Metacrunch.job do
      params { param :index, String }

      use "nope"
    end

    assert_equal [:index], job.describe.definitions.keys
  end

  private

  def context_for(declarations, env: {}, credentials: nil)
    Metacrunch::UseContext.new(resolver: Resolver.new(declarations), env:, credentials:, logger: SILENT)
  end

  # Evaluates a job recipe with params bound from a Hash and names resolved
  # in declarations.
  def build_job(declarations = {}, params: {}, env: {}, credentials: nil, &recipe)
    context = context_for(declarations, env:, credentials:)
    Metacrunch.job(&recipe).pipeline(binder: ->(schema) { schema.bind_hash(params) }, logger: SILENT, context:)
  end

  # The records that reach the sink when pipeline runs.
  def records(pipeline)
    sink = CollectingSink.new
    Metacrunch::Engine.new(pipeline.with(sink: Metacrunch::SinkAdapter.new(sink))).run
    sink.records
  end

end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -w -Ilib -Itest test/unit/use_test.rb`
Expected: FAIL with `NameError: uninitialized constant Metacrunch::UseContext` and `ArgumentError: unknown keyword: :context`

- [ ] **Step 3: Write UseContext**

`lib/metacrunch/use_context.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  # What `use` needs from the call that builds a job: a resolver for names
  # and paths (an Invoker), the environment and the credentials store the
  # job is bound with, and the logger. Nested transforms share it, so one
  # run reads one credentials file.
  class UseContext

    # resolver: responds to resolve(target, kind:) and returns
    # [declaration, anchor], as Invoker#resolve does. credentials: a
    # Credentials::Store, or nil for none (tests).
    def initialize(resolver:, env:, credentials:, logger:)
      @resolver = resolver
      @env = env
      @credentials = credentials
      @logger = logger
    end

    # The Transform that target stands for: a Transform, or its name or
    # path. Raises ArgumentError for a job, a command or any other object,
    # ProjectError for an unknown name and JobLoadError for a path without
    # a transform.
    def transform(target)
      declaration = declaration_for(target)
      return declaration if declaration.is_a?(Transform)

      name = declaration.name || (target if target.is_a?(String)) || "the target"
      raise ArgumentError, "use takes transforms; #{name} is a #{Loader::KINDS.fetch(declaration.class)}"
    end

    # Evaluates the recipe of transform with values bound (see
    # Params#bind_values) and returns its pipeline: steps and hooks, no
    # source and no sinks. stack: the transforms whose recipes are being
    # evaluated around this use. Errors of the values name the transform.
    def evaluate(transform, values, stack:)
      if stack.include?(transform)
        raise ArgumentError, "use cycle: #{[*stack, transform].map(&:label).join(" → ")}"
      end

      transform.pipeline(binder: binder(transform, values), logger: @logger, context: self, stack:)
    end

    private

    def declaration_for(target)
      return target if [Transform, Job, Command].any? { target.is_a?(it) }
      return @resolver.resolve(target, kind: Transform).first if target.is_a?(String)

      raise ArgumentError, "use takes a transform, its name or its path, got #{target.inspect}"
    end

    # No cause: the original message is part of the new one.
    def binder(transform, values)
      lambda do |schema|
        schema.bind_values(values, env: @env, credentials: @credentials)
      rescue ParamError, ArgumentError => e
        raise e.class, "use #{transform.label}: #{e.message}", cause: nil
      end
    end

  end
end
```

In `lib/metacrunch.rb`, add after `require_relative "metacrunch/loader"`:

```ruby
require_relative "metacrunch/use_context"
```

- [ ] **Step 4: Give recipes `use`**

In `lib/metacrunch/builder.rb`, replace `initialize` (from Task 1) with:

```ruby
    # binder: callable that takes the Params schema and returns the bound
    # values. describe: stop as soon as the schema is known (for --help).
    # context: the UseContext that `use` resolves and binds transforms in.
    # transform: the Transform whose recipe this builder evaluates; it
    # refuses source, sinks, error policy and profile. nil for a job.
    # stack: the transforms being evaluated, this one last (for cycles).
    def initialize(binder:, logger:, describe: false, context: nil, transform: nil, stack: [])
      init_params(binder, describe)
      @logger = logger
      @context = context
      @transform = transform
      @stack = stack
      @source = nil
      @source_declared = false
      @id_extractor = nil
      @steps = []
      @statements = 0
      @prefixes = Hash.new(0)
      @sinks = {}
      @on_error = :abort
      @max_errors = nil
      @profile = false
      @before_hooks = []
      @after_hooks = []
    end
```

Add after `reject`:

```ruby
    # Inserts the steps and hooks of a transform here. target: a Transform,
    # or its name or path; values bind its parameters (see UseContext).
    # Its steps are named with its label as prefix: normalize/map#1.
    def use(target, **values)
      use!
      raise ArgumentError, "use needs a context: build the job with Job#pipeline(context:)" unless @context

      transform = @context.transform(target)
      built = @context.evaluate(transform, values, stack: @stack)
      prefix = prefix_for(transform)
      @steps.concat(built.steps.map { it.with(name: "#{prefix}/#{it.name}") })
      @before_hooks.concat(built.before_hooks)
      @after_hooks.concat(built.after_hooks)
      @statements += 1
      nil
    end
```

Replace `add_step` with:

```ruby
    # Generated names count the step statements of the recipe, use
    # included, so a transform that gains a step renames no step of the
    # job. / is reserved for the prefixes of transforms.
    def add_step(kind, reason, callable, block, name)
      use!
      raise ArgumentError, "#{kind}: pass a callable or a block, not both" if callable && block

      implementation = callable || block
      raise ArgumentError, "#{kind}: a callable or a block is required" unless implementation

      @statements += 1
      name = (name || "#{kind}##{@statements}").to_s
      raise ArgumentError, "the step name #{SOURCE_STEP} is reserved" if name == SOURCE_STEP
      if name.include?("/")
        raise ArgumentError, "the step name #{name} contains /, which is reserved for the prefixes of transforms"
      end
      raise ArgumentError, "duplicate step name #{name}" if @steps.any? { |step| step.name == name }

      @steps << Step.build(kind, implementation, name:, reason:)
      nil
    end

    # The label of transform, numbered from its second use in this recipe:
    # normalize, normalize#2, ...
    def prefix_for(transform)
      label = transform.label
      @prefixes[label] += 1
      @prefixes[label] == 1 ? label : "#{label}##{@prefixes[label]}"
    end
```

(`prefix_for` goes below `private`, next to `add_step`.)

In `lib/metacrunch/transform.rb`, replace `pipeline`:

```ruby
    # Evaluates the recipe in transform mode. The pipeline has steps and
    # hooks, but no source and no sinks. binder: see Job#pipeline.
    # context: the UseContext for `use` in this recipe. stack: the
    # transforms whose recipes are being evaluated around this one.
    def pipeline(binder:, logger: Metacrunch.logger, context: nil, stack: [])
      builder = Builder.new(binder:, logger:, context:, transform: self, stack: [*stack, self])
      builder.instance_exec(&@recipe)
      builder.build
    end
```

In `lib/metacrunch/job.rb`, replace `pipeline`:

```ruby
    # Evaluates the recipe. binder takes the Params schema and returns the
    # bound values. context: the UseContext that `use` resolves transforms
    # in; a recipe with `use` needs one.
    def pipeline(binder:, logger: Metacrunch.logger, context: nil)
      builder = Builder.new(binder:, logger:, context:)
      builder.instance_exec(&@recipe)
      builder.build
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/use_test.rb test/unit/builder_test.rb test/unit/transform_test.rb`
Expected: PASS (the builder tests keep their step names: without `use`, statements and steps count alike)

- [ ] **Step 6: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 7: Commit**

```bash
git add lib/metacrunch/use_context.rb lib/metacrunch/builder.rb lib/metacrunch/transform.rb lib/metacrunch/job.rb \
        lib/metacrunch.rb test/unit/use_test.rb
git commit -m "$(cat <<'EOF'
Insert transforms into recipes with use

use resolves a transform through a UseContext, evaluates its recipe with
the keyword values bound and inserts its steps and hooks where it stands.
The steps get the transform as prefix (normalize/map#1, normalize#2/...),
generated numbers count statements with use as one, explicit step names
must not contain /, and a cycle of transforms raises.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 4: Contexts for every caller

**Files:**
- Modify: `lib/metacrunch/invoker.rb` (`resolve(kind:)`, `pipeline` with `UseContext`, transforms in `invoke`, message)
- Modify: `lib/metacrunch/use_context.rb` (`UseContext.for`)
- Modify: `lib/metacrunch/project.rb` (`Project.nearest`, `fetch` message)
- Modify: `lib/metacrunch/job.rb` (`run(project:)`)
- Modify: `lib/metacrunch/testing.rb` (`run(project:)`, transforms, messages of `invoke`)
- Modify: `lib/metacrunch/cli.rb` (`unknown`: the same message as the `Invoker`)
- Test: `test/unit/invoker_test.rb`, `test/unit/job_test.rb`, `test/unit/project_test.rb`, `test/unit/testing_test.rb`, `test/unit/testing_invoke_test.rb`, `test/cli/cli_test.rb`, `test/cli/project_cli_test.rb` (messages)

**Interfaces:**
- Consumes: `UseContext.new`, `Job#pipeline(context:)`, `Transform#pipeline(context:)`, `Loader.load(kind:)`.
- Produces:
  - `Invoker#resolve(target, select: nil, kind: nil) -> [declaration, anchor]` — `kind:` restricts what a path loads; unknown names raise `ProjectError` "unknown job, transform, command or file: x (hint)".
  - `Invoker#pipeline(job, argv, anchor:)` — job may be a `Transform`; one credentials store for the job and its transforms.
  - `Invoker#invoke` runs transforms like jobs.
  - `UseContext.for(project:, env:, credentials:, logger:) -> UseContext` — names resolve in project, else in `Project.nearest` (looked up when the first name needs it).
  - `Project.nearest(dir = Dir.pwd) -> Project | nil`
  - `Job#run(argv = [], env:, logger:, observer:, limit:, workers:, project: nil)`
  - `Testing.run(job_or_transform, params:, source:, logger:, workers:, project: nil)`

- [ ] **Step 1: Write the failing tests**

In `test/unit/invoker_test.rb`:

Replace the `"Metacrunchfile"` entry of `FILES`:

```ruby
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\", \"commands/*.rb\"\n",
```

Add to `FILES`, after the entry `"jobs/term.rb"`:

```ruby
    "transforms/scale.rb" => <<~RUBY,
      Metacrunch.transform "scale" do
        params { param :factor, Integer, env: "SCALE_FACTOR", default: 2 }

        map { it * params.factor }
      end
    RUBY
    "jobs/scaled.rb" => <<~RUBY,
      Metacrunch.job "scaled" do
        params do
          param :factor, Integer
          args :numbers
        end

        source params.numbers.map { Integer(it, 10) }
        use "scale", factor: params.factor
      end
    RUBY
```

Add after `NAMED_SECRET_JOB`:

```ruby
  REVEAL = <<~RUBY
    Metacrunch.transform "reveal" do
      params { param :api_key, String, credential: "catalog.api_key", required: true }

      map { params.api_key.reverse }
    end
  RUBY
```

Change the expected messages:

```ruby
      assert_equal ["invoke nope: unknown job, transform, command or file: nope", "nope"], [error.message, error.name]
```

```ruby
    assert_equal "invoke numbers: unknown job, transform, command or file: numbers (no Metacrunchfile found)",
                 error.message
```

Add before `private`:

```ruby
  def test_jobs_use_transforms_by_name
    with_project do |invoker, out|
      invoker.invoke("scaled", "1", "2")

      assert_equal "2\n4\n", out.string
    end
  end

  # A value given at use wins over the transform's env: variable; nil (the
  # job's factor left unset) falls through to it.
  def test_values_at_use_win_over_the_environment_and_nil_falls_through
    with_project(env: {"SCALE_FACTOR" => "3"}) do |invoker, out|
      invoker.invoke("scaled", "1")
      invoker.invoke("scaled", "--factor", "5", "1")

      assert_equal "3\n5\n", out.string
    end
  end

  def test_transforms_run_alone_like_jobs
    with_project(stdin: "1\n2\n") do |invoker, out|
      result = invoker.invoke("scale", "--factor", "3")

      assert_equal [:ok, "3\n6\n"], [result.status, out.string]
    end
  end

  def test_the_credentials_of_the_job_reach_its_transforms
    in_tmpdir do |root|
      write_ruby(root, "Metacrunchfile", "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\"\n")
      write_ruby(root, "transforms/reveal.rb", REVEAL)
      write_ruby(root, "jobs/revealed.rb", "Metacrunch.job(\"revealed\") do\n  source [1]\n  use \"reveal\"\nend\n")
      write_credentials(root, {"catalog" => {"api_key" => SECRET}}, environment: "production")
      out = StringIO.new
      invoker_for(Metacrunch.load_project(root), stdout: out, environment: "production").invoke("revealed")

      assert_equal "\"#{SECRET.reverse}\"\n", out.string
    end
  end

  def test_a_path_for_use_loads_only_transforms
    with_project do |invoker|
      path = job("double.rb")
      error = assert_raises(Metacrunch::JobLoadError) { invoker.resolve(path, kind: Metacrunch::Transform) }

      assert_match(/no transform defined in .*double\.rb/, error.message)
    end
  end
```

Replace the helpers `with_project` and `invoker_for`:

```ruby
  # Yields an Invoker for a project with FILES, its stdout and the root.
  def with_project(logger: Logger.new(nil), env: {}, stdin: "")
    in_tmpdir do |root|
      FILES.each { |path, code| write_ruby(root, path, code) }
      out = StringIO.new
      invoker = invoker_for(Metacrunch.load_project(root), stdin: StringIO.new(stdin), stdout: out, logger:, env:)
      yield invoker, out, root
    end
  end

  def invoker_for(project, stdin: StringIO.new, stdout: StringIO.new, logger: Logger.new(nil), environment: nil,
                  env: {})
    Metacrunch::Invoker.new(project:, logger:, env:, stdin:, stdout:, environment:)
  end
```

In `test/unit/job_test.rb`, add `include CredentialsHelper` after `include ForkVariant::NoWorkerLeft`, this constant after `SILENT`:

```ruby
  SCALE = "Metacrunch.transform(\"scale\") { map { it * 2 } }\n"
```

and these tests and helper before the final `end` of the class:

```ruby
  def test_run_resolves_names_in_the_given_project
    in_tmpdir do |root|
      write_project(root)
      target = CollectingSink.new
      job = Metacrunch.job do
        source [1]
        use "scale"
        sink target
      end
      job.run([], logger: SILENT, project: Metacrunch.load_project(root))

      assert_equal [2], target.records
    end
  end

  def test_run_finds_the_project_of_the_working_directory_when_a_name_needs_it
    in_tmpdir do |root|
      write_project(root)
      FileUtils.mkdir_p(File.join(root, "sub"))
      job = Metacrunch.job { source [1]; use "scale" }
      result = Dir.chdir(File.join(root, "sub")) { job.run([], logger: SILENT) }

      assert_equal [:ok, ["scale/map#1"]], [result.status, result.stats.steps.keys]
    end
  end

  def test_run_without_a_project_names_the_missing_metacrunchfile
    in_tmpdir do |dir|
      job = Metacrunch.job { source [1]; use "scale" }
      error = Dir.chdir(dir) { assert_raises(Metacrunch::ProjectError) { job.run([], logger: SILENT) } }

      assert_equal "unknown job, transform, command or file: scale (no Metacrunchfile found)", error.message
    end
  end

  def test_run_uses_transforms_by_path_without_a_project
    in_tmpdir do |dir|
      path = write_file(dir, "scale.rb", "# frozen_string_literal: true\n\n#{SCALE}")
      target = CollectingSink.new
      job = Metacrunch.job do
        source [1]
        use path
        sink target
      end
      job.run([], logger: SILENT)

      assert_equal [2], target.records
    end
  end

  private

  def write_project(root)
    write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nMetacrunch.load_files \"transforms/*.rb\"\n")
    write_file(root, "transforms/scale.rb", "# frozen_string_literal: true\n\n#{SCALE}")
  end
```

In `test/unit/project_test.rb`, change the expectation in `test_unknown_names_hint_at_files_that_did_not_load`:

```ruby
      assert_equal "unknown job, transform or command: nope (1 file of the project did not load)", error.message
```

and add after `test_loading_without_metacrunchfile_raises`:

```ruby
  def test_nearest_loads_the_project_above_a_directory_or_gives_nil
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "")
      FileUtils.mkdir_p(File.join(root, "sub"))

      assert_equal File.join(root, "Metacrunchfile"), Metacrunch::Project.nearest(File.join(root, "sub")).file
    end
    in_tmpdir { |dir| assert_nil Metacrunch::Project.nearest(dir) }
  end

  def test_a_transform_and_a_job_of_one_name_are_a_duplicate
    in_tmpdir do |root|
      project = load_project(root, "Metacrunchfile" => LOAD_ALL, "jobs/a.rb" => job("dup"),
                                   "jobs/b.rb" => "Metacrunch.transform(\"dup\") { map { it } }\n")
      error = assert_raises(Metacrunch::ProjectError) { project.fetch("dup") }

      assert_match(%r{\Adup is declared more than once \(jobs/a\.rb, jobs/b\.rb\); rename one\z}, error.message)
    end
  end
```

The CLI gives the same message for unknown names. In `test/cli/cli_test.rb`, change the two entries of `USAGE_ERRORS` with "unknown command, job or file":

```ruby
    ["frobnicate"] => "unknown job, transform, command or file: frobnicate (no Metacrunchfile found)",
```

```ruby
    ["help", "frobnicate"] => "unknown job, transform, command or file: frobnicate (no Metacrunchfile found)"
```

In `test/cli/project_cli_test.rb`, change the messages in `test_unknown_names_hint_at_files_that_did_not_load` and `test_unknown_names_outside_a_project`:

```ruby
      assert_match(/Error: unknown job, transform, command or file: nope \(1 file of the project did not load\)/,
                   stderr)
```

```ruby
      assert_match(/Error: unknown job, transform, command or file: nope \(no Metacrunchfile found\)/, stderr)
```

In `test/unit/testing_test.rb`, add `include CredentialsHelper` after `include ForkVariant::NoWorkerLeft`, this constant after the class `Untouchable`:

```ruby
  SCALE = "# frozen_string_literal: true\n\nMetacrunch.transform(\"scale\") { map { it * 2 } }\n"
```

and these tests before `private`:

```ruby
  def test_runs_a_transform_with_a_source
    transform = Metacrunch.transform do
      params { param :factor, Integer, default: 2 }

      map { it * params.factor }
    end
    error = assert_raises(ArgumentError) { Metacrunch::Testing.run(transform) }

    assert_equal [3], Metacrunch::Testing.run(transform, params: {factor: 3}, source: [1]).records
    assert_equal "a transform has no source; pass source:", error.message
  end

  def test_resolves_names_in_the_given_project
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nMetacrunch.load_files \"transforms/*.rb\"\n")
      write_file(root, "transforms/scale.rb", SCALE)
      job = Metacrunch.job { source [1]; use "scale" }
      result = Metacrunch::Testing.run(job, project: Metacrunch.load_project(root))

      assert_equal [[2], ["scale/map#1"]], [result.records, result.stats.steps.keys]
    end
  end

  def test_transforms_get_no_environment
    transform = Metacrunch.transform("env") do
      params { param :factor, Integer, env: "METACRUNCH_TEST_FACTOR", default: 2 }

      map { it * params.factor }
    end
    job = Metacrunch.job { source [1]; use transform }
    ENV["METACRUNCH_TEST_FACTOR"] = "7"

    assert_equal [2], Metacrunch::Testing.run(job).records
  ensure
    ENV.delete("METACRUNCH_TEST_FACTOR")
  end
```

In `test/unit/testing_invoke_test.rb`, change the two expected messages:

```ruby
    assert_equal "invoke a2x: unknown job, transform, command or file: a2x", run.error.message
```

```ruby
    assert_equal "stub for unknown job, transform or command: a2x", error.message
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/invoker_test.rb test/unit/job_test.rb test/unit/project_test.rb test/unit/testing_test.rb test/unit/testing_invoke_test.rb test/cli/cli_test.rb test/cli/project_cli_test.rb`
Expected: FAIL: "use needs a context" in the tests that use names, `unknown keyword: :project`, `unknown keyword: :kind`, `undefined method 'nearest'`, and the changed messages (`test_a_transform_and_a_job_of_one_name_are_a_duplicate` passes already: duplicates work for any kind)

- [ ] **Step 3: Give UseContext its constructor for Ruby callers and Project.nearest**

In `lib/metacrunch/use_context.rb`, add after `initialize`:

```ruby
    # A context whose names resolve in project, or, without one, in the
    # project of the nearest Metacrunchfile above the working directory,
    # loaded when the first name needs it (Job#run, Testing.run).
    def self.for(project:, env:, credentials:, logger:)
      resolver = Invoker.new(project: project || -> { Project.nearest }, logger:, env:)
      new(resolver:, env:, credentials:, logger:)
    end
```

In `lib/metacrunch/project.rb`, add after `self.load`:

```ruby
    # The project of the nearest Metacrunchfile at or above dir, or nil if
    # there is none. Raises ProjectError if it fails to load.
    def self.nearest(dir = Dir.pwd)
      file = find(dir)
      file && load_file(file)
    end
```

and change the message in `fetch`:

```ruby
      raise ProjectError, "unknown job, transform or command: #{name}#{load_hint}" if declarations.empty?
```

- [ ] **Step 4: Build jobs with a UseContext in the Invoker**

In `lib/metacrunch/invoker.rb`:

Replace the class comment's first sentence:

```ruby
  # Runs jobs, transforms and commands with the context of one call: the
  # environment, the credentials options (-e, --credentials), the logger,
  # stdin and stdout, and the progress display. The CLI runs its target
  # through it, and a command's body invokes through it, so a whole chain
  # shares that context. It also resolves the names of `use` (see
  # UseContext). Tracks the worst status of the jobs it ran.
```

Replace `invoke`:

```ruby
    # Runs target, a name or a path, with argv as on the command line, each
    # converted with to_s. Returns the Result of a job or transform, or a
    # command's value. Raises InvokeError if the target is unknown, argv is
    # invalid for it or the job aborted; exceptions from a command's body
    # pass unchanged.
    def invoke(target, *argv, workers: nil, limit: nil)
      target = target.to_s
      argv = arguments(target, argv)
      declaration, anchor = wrap(target) { resolve(target) }
      return invoke_job(declaration, argv, target:, anchor:, workers:, limit:) unless declaration.is_a?(Command)
      raise ArgumentError, "#{target} is a command; workers: and limit: apply to jobs" if workers || limit

      invoke_command(declaration, argv, target:, anchor:)
    end
```

Replace `resolve`:

```ruby
    # [declaration, anchor] for target. A target with / or . is a path; any
    # other is a name of the project, else an existing file of that name.
    # anchor is the file credentials are searched from: the Metacrunchfile
    # for a name, the file itself for a path. select: -j, for paths only.
    # kind: what a path may give (Transform for use), as for Loader.load.
    def resolve(target, select: nil, kind: nil)
      return by_path(target, select, kind) if Names.path?(target)

      current = project
      return by_name(current, target, select) if current&.include?(target)
      return by_path(target, select, kind) if File.file?(target)

      hint = current ? current.load_hint : " (no #{Project::FILE} found)"
      raise ProjectError, "unknown job, transform, command or file: #{target}#{hint}"
    end
```

Replace `pipeline` and `prepare`:

```ruby
    # The pipeline of a job or transform with argv bound: the command line,
    # env:, the credentials searched from anchor, then the default. The
    # transforms it uses resolve here and read the same credentials.
    def pipeline(job, argv, anchor:)
      credentials = credentials_for(anchor)
      context = UseContext.new(resolver: self, env: @env, credentials:, logger: @logger)
      job.pipeline(binder: binder(argv, credentials), logger: @logger, context:)
    end

    # Evaluates the command's recipe with argv bound as pipeline does.
    def prepare(command, argv, anchor:)
      command.prepare(binder: binder(argv, credentials_for(anchor)))
    end
```

Replace `by_path` and `binder` (both private):

```ruby
    def by_path(path, select, kind)
      declaration = Loader.load(path, name: select, kind:)
      [declaration, declaration.file]
    end
```

```ruby
    # Read only if a parameter needs a value from them.
    def credentials_for(anchor)
      Credentials.store(job_file: anchor, env: @env, logger: @logger, environment: @environment,
                        directory: @credentials)
    end

    def binder(argv, credentials)
      warn = ->(message) { @logger.warn(message) }
      ->(schema) { schema.bind_argv(argv, env: @env, credentials:, warn:) }
    end
```

In `lib/metacrunch/cli.rb`, replace `unknown`, so the CLI names unknown targets as the `Invoker` does:

```ruby
    def unknown(target)
      return "unknown job, transform, command or file: #{target}" if Names.path?(target)

      hint = project ? project.load_hint : " (no #{Project::FILE} found)"
      "unknown job, transform, command or file: #{target}#{hint}"
    end
```

- [ ] **Step 5: Give Job#run and Testing.run a project**

In `lib/metacrunch/job.rb`, replace `run` and its comment:

```ruby
    # Runs the job with CLI-style arguments. Raises ParamError for invalid
    # arguments (CredentialsError, a ParamError, for unreadable credentials)
    # and lets errors from the recipe itself (e.g. a component constructor
    # or a DSL mistake) propagate. Errors while the pipeline runs end up in
    # the Result. limit stops after that many records; workers runs the
    # steps in that many processes. Credentials follow env:
    # METACRUNCH_ENV, METACRUNCH_CREDENTIALS, METACRUNCH_MASTER_KEY, HOME.
    # project: where the names of `use` resolve; without it, the project of
    # the nearest Metacrunchfile above Dir.pwd, loaded when a name needs it.
    def run(argv = [], env: ENV, logger: Metacrunch.logger, observer: nil, limit: nil, workers: nil, project: nil)
      credentials = Credentials.store(job_file: file, env:, logger:)
      warn = ->(message) { logger.warn(message) }
      context = UseContext.for(project:, env:, credentials:, logger:)
      built = pipeline(binder: ->(schema) { schema.bind_argv(argv, env:, credentials:, warn:) }, logger:, context:)
      Engine.new(built.with(limit:), observer:, executor: Executor.for(workers)).run
    end
```

In `lib/metacrunch/testing.rb`, replace `run` and its comment:

```ruby
    # params are bound like CLI values (strings are converted), without
    # environment lookup. The job's sinks are built but never opened.
    # Records are collected even if the job has no sink; stats.written is
    # 0 then, as in a real run. workers: run the steps in that many
    # processes, to check that the job's records cross process boundaries.
    # job may be a Transform, which needs source:. project: where the
    # names of `use` resolve (see UseContext.for); the transforms of the
    # job get neither environment nor credentials either.
    def run(job, params: {}, source: nil, logger: Logger.new(nil), workers: nil, project: nil)
      unless source.nil? || source.respond_to?(:each)
        raise ArgumentError, "source must respond to #each, got #{source.inspect}"
      end

      context = UseContext.for(project:, env: {}, credentials: nil, logger:)
      pipeline = job.pipeline(binder: ->(schema) { schema.bind_hash(params) }, logger:, context:)
      memory = {sink: MemorySink.new, rejects: MemorySink.new, errors: MemorySink.new}
      adapters = memory.transform_values { |sink| SinkAdapter.new(sink) }
      adapters[:sink] = UncountedSinkAdapter.new(memory[:sink]) unless pipeline.sink
      source ||= pipeline.source
      unless source
        raise ArgumentError, "#{job.is_a?(Transform) ? "a transform" : "the job"} has no source; pass source:"
      end

      pipeline = pipeline.with(source:, **adapters)
      result = Engine.new(pipeline, executor: Executor.for(workers)).run
      Result.new(
        records: memory[:sink].records,
        rejects: memory[:rejects].records.zip(memory[:rejects].contexts.map(&:rejection)),
        errors: memory[:errors].records.zip(memory[:errors].contexts.map(&:failure)),
        stats: result.stats,
        status: result.status,
        error: result.error
      )
    end
```

In `invoke` of the same file, replace the two `raise` lines:

```ruby
      unless command.is_a?(Command)
        raise ArgumentError, "#{name} is a #{Loader::KINDS.fetch(command.class)}; test it with Testing.run"
      end

      unknown = stubs.keys.map(&:to_s).reject { project.include?(it) || File.file?(it) }
      raise ArgumentError, "stub for unknown job, transform or command: #{unknown.first}" if unknown.any?
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/unit/invoker_test.rb test/unit/job_test.rb test/unit/project_test.rb test/unit/testing_test.rb test/unit/testing_invoke_test.rb test/unit/use_test.rb test/cli/cli_test.rb test/cli/project_cli_test.rb`
Expected: PASS

- [ ] **Step 7: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 8: Commit**

```bash
git add lib/metacrunch/invoker.rb lib/metacrunch/use_context.rb lib/metacrunch/project.rb lib/metacrunch/job.rb \
        lib/metacrunch/testing.rb lib/metacrunch/cli.rb test/unit/invoker_test.rb test/unit/job_test.rb \
        test/unit/project_test.rb test/unit/testing_test.rb test/unit/testing_invoke_test.rb test/cli/cli_test.rb \
        test/cli/project_cli_test.rb
git commit -m "$(cat <<'EOF'
Resolve transforms wherever jobs are built

The Invoker builds jobs with a UseContext that resolves names in its
project and binds transforms with the job's credentials store, so -e
reaches them; it also runs and invokes transforms like jobs. Job#run and
Testing.run take project: and otherwise use the nearest Metacrunchfile,
looked up only when a name needs it. Messages that list kinds name
transforms.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 5: Transforms on the command line

**Files:**
- Modify: `lib/metacrunch/cli.rb` (help section "Transforms", comments)
- Modify: `lib/metacrunch/cli/job_command.rb` (`-j` text, no-target message)
- Modify: `lib/metacrunch/cli/run.rb` (summary)
- Modify: `lib/metacrunch/cli/check.rb` (title)
- Test: `test/cli/project_cli_test.rb`, `test/cli/cli_test.rb`

**Interfaces:**
- Consumes: `Invoker#resolve`, `Invoker#pipeline`, `Metacrunch::Transform`.
- Produces: `metacrunch --help` lists "Transforms (ROOT):" between "Jobs" and "Project commands"; `check` titles `transform "NAME" OK`; `run` summary "Run a job, transform or command".

- [ ] **Step 1: Write the failing tests**

In `test/cli/cli_test.rb`, change the expected summary of `run` (the `USAGE_ERRORS` entries changed in Task 4):

```ruby
    assert_match(/^  run +Run a job, transform or command$/, stdout)
```

In `test/cli/project_cli_test.rb`:

Replace the `"Metacrunchfile"` entry of `FILES`:

```ruby
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\", \"commands/*.rb\"\n",
```

Add to `FILES`, after the entry `"jobs/interrupted.rb"`:

```ruby
    "transforms/scale.rb" => <<~RUBY,
      Metacrunch.transform "scale", desc: "Multiply by a factor" do
        params { param :factor, Integer, default: 2 }

        map { it * params.factor }
      end
    RUBY
    "jobs/scaled.rb" => <<~RUBY,
      Metacrunch.job "scaled" do
        params { args :numbers }

        source params.numbers.map { Integer(it, 10) }
        use "scale", factor: 10
      end
    RUBY
```

Add after the constant `BROKEN`:

```ruby
  # A job file outside jobs/ that uses a transform by name.
  TOOL_JOB = <<~RUBY
    Metacrunch.job do
      params { param :factor, Integer, default: 2 }

      source [1]
      use "scale"
    end
  RUBY
  # Jobs whose use fails: an unknown name, a missing value, a job as target.
  USE_ERRORS = <<~RUBY
    Metacrunch.transform("needy") do
      params { param :level, Integer, required: true }

      map { it * params.level }
    end
    Metacrunch.job("unknown-use") { source [1]; use "nope" }
    Metacrunch.job("missing-value") { source [1]; use "needy" }
    Metacrunch.job("job-use") { source [1]; use "numbers" }
  RUBY
```

Add before `private`:

```ruby
  def test_runs_checks_and_traces_a_transform
    in_project do |root|
      results = [cli_in(root, "scale", "--factor", "3", stdin: "1\n2\n"), cli_in(root, "check", "scale"),
                 cli_in(root, "trace", "scale", stdin: "1\n")]

      assert_equal [0, 0, 0], results.map(&:first)
      assert_equal "3\n6\n", results[0][1]
      assert_equal "scale: transform \"scale\" OK", results[1][1].lines.first.chomp
    end
  end

  def test_check_shows_the_prefixed_steps_of_a_job
    in_project do |root|
      code, stdout, = cli_in(root, "check", "scaled", "1")

      assert_equal 0, code
      assert_match(%r{^  steps     scale/map#1$}, stdout)
    end
  end

  def test_the_usage_lists_transforms_between_jobs_and_commands
    in_project do |root|
      _code, stdout, = cli_in(root, "--help")

      assert_match(/^Transforms \(#{Regexp.escape(root)}\):\n  scale +Multiply by a factor\n\nProject commands/, stdout)
      assert_operator stdout.index("Jobs ("), :<, stdout.index("Transforms (")
    end
  end

  def test_a_job_file_loads_the_metacrunchfile_only_when_it_runs_a_name
    in_tmpdir do |root|
      write_file(root, "Metacrunchfile", "# frozen_string_literal: true\n\nraise \"loaded\"\n")
      path = write_file(root, "tool.rb", "# frozen_string_literal: true\n\n#{TOOL_JOB}")
      help = cli_in(root, "run", path, "--help")
      run = cli_in(root, "run", path)

      assert_equal [0, 2], [help.first, run.first]
      refute_includes help.last, "loaded"
      assert_match(/Error: could not load .*Metacrunchfile: RuntimeError: loaded/, run.last)
    end
  end

  def test_use_errors_exit_with_their_status
    in_project("jobs/use_errors.rb" => USE_ERRORS) do |root|
      results = [["unknown-use"], ["missing-value"], ["job-use"], ["check", "job-use"]].map { cli_in(root, *it) }

      assert_equal [2, 2, 1, 2], results.map(&:first)
      assert_match(/Error: unknown job, transform, command or file: nope/, results[0].last)
      assert_match(/Error: use needy: missing required parameter level/, results[1].last)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/cli/project_cli_test.rb test/cli/cli_test.rb`
Expected: FAIL: the `run` summary, `job "scale" OK` instead of `transform "scale" OK`, the help without "Transforms" (the transform appears under "Jobs" or "Project commands")

- [ ] **Step 3: Implement the CLI changes**

In `lib/metacrunch/cli.rb`, change the class comment's second sentence and the comment of `other`:

```ruby
  # The command line interface. Dispatches to a command by the first
  # argument; a job, transform or command there, by name or file, is short
  # for `run`. #run returns the exit code, exe/metacrunch exits with it.
```

```ruby
    # An option, or a job, transform or command by name or file: short for
    # run.
```

Replace `project_sections` and its comment:

```ruby
    # The jobs, transforms and commands of the project and the files that
    # did not load, or the error of the Metacrunchfile. No warnings: the
    # list shows the files.
    LISTS = {"Jobs" => Metacrunch::Job, "Transforms" => Metacrunch::Transform,
             "Project commands" => Metacrunch::Command}.freeze
```

(Put `LISTS` next to `COMMANDS` at the top of the class, and keep the old comment above `project_help`.)

```ruby
    def project_sections(project)
      names = project.names
      width = names.map(&:size).max
      kinds = names.group_by { project.declared(it).first.class }
      lists = LISTS.filter_map do |title, kind|
        entries = kinds.fetch(kind, []).map { entry(project, it, width) }
        section("#{title} (#{project.root})", entries) if entries.any?
      end
      errors = project.load_errors.map { |file, error| "  #{project.load_error_summary(file, error)}" }
      [*lists, (section("Not loaded", errors) if errors.any?)].compact
    end
```

In `lib/metacrunch/cli/job_command.rb`, replace the class comment, the `-j` option and the no-target message:

```ruby
    # A command that takes a job, transform or command by name or file
    # (run, check, trace). Options before it belong to the command,
    # everything after it to the target. Subclasses implement
    # #execute_job(job, argv), which also gets transforms; run also
    # #execute_command(command, argv).
```

```ruby
        parser.on("-j", "--job NAME", "Select a job, transform or command in a file that declares several") do |name|
          @job_name = name
        end
```

```ruby
        raise UsageError, "no job, transform, command or file given" unless @target
```

In `lib/metacrunch/cli/run.rb`:

```ruby
      SUMMARY = "Run a job, transform or command"
```

In `lib/metacrunch/cli/check.rb`, replace in `description`:

```ruby
        kind = job.is_a?(Transform) ? "transform" : "job"
        title = job.name ? "#{kind} #{job.name.inspect}" : kind
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest -e 'ARGV.each { require File.expand_path(it) }' test/cli/project_cli_test.rb test/cli/cli_test.rb test/cli/check_test.rb test/cli/run_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 6: Commit**

```bash
git add lib/metacrunch/cli.rb lib/metacrunch/cli/job_command.rb lib/metacrunch/cli/run.rb lib/metacrunch/cli/check.rb \
        test/cli/project_cli_test.rb test/cli/cli_test.rb
git commit -m "$(cat <<'EOF'
List and run transforms on the command line

metacrunch --help lists a project's transforms between its jobs and
commands; run, check and trace take transforms like jobs without source
and sink, and check names them. A job file that uses a transform by name
loads the Metacrunchfile only when it runs, never for --help.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 6: Transforms end to end through exe/metacrunch

**Files:**
- Test: `test/cli/exe_transforms_test.rb` (new)

**Interfaces:**
- Consumes: everything above, through `exe/metacrunch` in a subprocess.
- Produces: nothing new.

- [ ] **Step 1: Write the test**

`test/cli/exe_transforms_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class ExeTransformsTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\"\n",
    "transforms/checks.rb" => <<~RUBY,
      Metacrunch.transform "checks" do
        reject("No code") { it["code"].nil? }
        map { it.merge("n" => 100 / it.fetch("n")) }
      end
    RUBY
    # A before hook builds the lookup table in the main process; the
    # workers inherit it.
    "transforms/labels.rb" => <<~RUBY,
      Metacrunch.transform "labels" do
        labels = nil
        before { labels = {"a" => "Alpha", "b" => "Beta"} }
        map { it.merge("label" => labels.fetch(it["code"])) }
      end
    RUBY
    "jobs/enrich.rb" => <<~RUBY
      Metacrunch.job "enrich" do
        use "checks"
        use "labels"
        on_error :skip
      end
    RUBY
  }.freeze

  # One record rejected (no code), one failed (division by zero).
  INPUT = <<~JSONL
    {"code":"a","n":1}
    {"code":"b","n":2}
    {"n":3}
    {"code":"a","n":0}
    {"code":"b","n":4}
  JSONL

  def test_a_job_with_transforms_gives_the_same_results_with_workers
    in_project do |root|
      inline = enrich(root)
      forked = enrich(root, "-w", "2")

      assert_equal inline, forked
      assert_equal [3, ["Alpha", "Beta", "Beta"]], [inline[:status], inline[:records].map { it["label"] }]
      assert_equal ["checks/reject#1", "checks/map#2", "labels/map#1"], inline[:stats]["steps"].keys
    end
  end

  def test_a_transform_runs_alone_through_stdin
    in_project do |root|
      stdout, stderr, status = metacrunch("labels", stdin_data: "{\"code\":\"b\"}\n", chdir: root)

      assert_equal [0, "{\"code\":\"b\",\"label\":\"Beta\"}\n"], [status.exitstatus, stdout], stderr
    end
  end

  private

  # Runs enrich with options and returns what two runs can be compared by:
  # the exit status, the records, the rejects and errors files and the
  # stats without times.
  def enrich(root, *options)
    files = ["rejects", "errors", "stats"].to_h { [it, File.join(root, "#{it}#{options.join}.json")] }
    stdout, stderr, status = metacrunch("run", *options, "--rejects", files["rejects"], "--errors", files["errors"],
                                        "--stats", files["stats"], "enrich", stdin_data: INPUT, chdir: root)
    raise "enrich failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    {status: status.exitstatus, records: stdout.lines.map { JSON.parse(it) },
     rejects: File.read(files["rejects"]), errors: File.read(files["errors"]),
     stats: JSON.parse(File.read(files["stats"]))["stats"].except("duration", "rate")}
  end

  # Yields the root of a temporary project with FILES.
  def in_project
    in_tmpdir do |root|
      FILES.each { |path, code| write_file(root, path, "# frozen_string_literal: true\n\n#{code}") }
      yield root
    end
  end

  # HOME points into the project, so ~/.metacrunch is never read.
  def metacrunch(*args, stdin_data:, chdir:)
    command = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *args]
    Open3.capture3(CLEAN_ENV.merge("HOME" => chdir), *command, stdin_data:, chdir:)
  end

end
```

- [ ] **Step 2: Run the test**

Run: `bundle exec ruby -w -Ilib -Itest test/cli/exe_transforms_test.rb`
Expected: PASS (2 runs). This task adds no code; if a test fails, the cause is in Tasks 1 to 5: fix it there, with a unit test that shows it, before going on.

- [ ] **Step 3: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 4: Commit**

```bash
git add test/cli/exe_transforms_test.rb
git commit -m "$(cat <<'EOF'
Test transforms end to end, with and without workers

A job of two transforms gives the same records, rejects, errors and stats
with -w 2 as inline, including a lookup table that a transform builds in a
before hook; a transform also runs alone through stdin.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 7: The example project gets a transform

**Files:**
- Create: `examples/project/transforms/public.rb`
- Create: `examples/project/jobs/ids.rb`
- Create: `examples/project/test/public_test.rb`
- Modify: `examples/project/Metacrunchfile`, `examples/project/jobs/catalog.rb`, `examples/Readme.md`
- Test: `test/integration/examples_test.rb`

**Interfaces:**
- Consumes: `Metacrunch.transform`, `use`, `Testing.run(project:)`.
- Produces: the transform `catalog:public` (`--fields`, default `id,title`), the job `catalog:ids`.

- [ ] **Step 1: Write the failing integration tests**

In `test/integration/examples_test.rb`, replace `test_the_project_example_tests_pass`:

```ruby
  def test_the_project_example_tests_pass
    tests = Dir[example("project/test/*_test.rb")]
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", "ARGV.each { require it }", *tests]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_equal 2, tests.size
    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end
```

and add after `test_project_help_lists_the_job_and_the_command`:

```ruby
  def test_project_help_lists_the_transform
    stdout, stderr, status = metacrunch("--help", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_match(/^Transforms \(.*\):\n  catalog:public +Keep the public titles, reduced to some fields$/, stdout)
  end

  def test_project_jobs_share_the_transform_with_other_values
    stdout, stderr, status = metacrunch("catalog:ids", chdir: example("project"))

    assert_predicate status, :success?, stderr
    assert_equal([{"id" => "t1"}, {"id" => "t2"}, {"id" => "t4"}, {"id" => "t5"}], stdout.lines.map { JSON.parse(it) })
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -w -Ilib -Itest test/integration/examples_test.rb`
Expected: FAIL: 1 project test file instead of 2, no "Transforms" section, `unknown job, transform, command or file: catalog:ids`

- [ ] **Step 3: Write the transform, the second job and the test**

`examples/project/transforms/public.rb`:

```ruby
# frozen_string_literal: true

# Keeps the public title records and reduces them to some fields; a record
# without one of them fails. A transform has steps and parameters but no
# source and no sink: the jobs that use it decide where records come from
# and go to. Alone it reads JSON Lines from stdin and writes them to stdout.
#
#   cd examples/project
#   bundle exec metacrunch catalog:public --help
#   bundle exec metacrunch catalog:public --fields id < data/titles.jsonl
Metacrunch.transform "catalog:public", desc: "Keep the public titles, reduced to some fields" do
  params do
    param :fields, Array, default: ["id", "title"], desc: "Fields to keep"
  end

  reject("Not public") { !it["public"] }
  map { |record| params.fields.to_h { [it, record.fetch(it)] } }
end
```

`examples/project/jobs/ids.rb`:

```ruby
# frozen_string_literal: true

# Prints the ids of the public titles as JSON Lines: the transform of the
# job catalog, with another value for its parameter fields.
#
#   cd examples/project
#   bundle exec metacrunch catalog:ids
Metacrunch.job "catalog:ids", desc: "Print the ids of the public titles" do
  params do
    param :input, String, default: File.expand_path("../data/titles.jsonl", __dir__),
                          desc: "JSON Lines with title records"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  use "catalog:public", fields: ["id"]
end
```

In `examples/project/jobs/catalog.rb`, replace the comment and the two steps:

```ruby
# Writes the public titles of a JSON Lines file to DIR/titles.jsonl, with
# the steps of the transform catalog:public. A record without a title
# fails; on_error :skip lets the run go on, and it ends with failed records
# (exit status 3).
#
#   cd examples/project
#   bundle exec metacrunch catalog --help
#   mkdir -p ../../tmp && bundle exec metacrunch catalog --output ../../tmp
```

```ruby
  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  use "catalog:public"
  sink Metacrunch::JsonLines::Writer.new(File.join(params.output, "titles.jsonl"))
  on_error :skip
```

`examples/project/Metacrunchfile`:

```ruby
# frozen_string_literal: true

# The project file: it names the jobs, transforms and commands of this
# directory, so that `metacrunch NAME` runs them from any directory below
# it.
#
#   cd examples/project
#   bundle exec metacrunch --help
#   bundle exec metacrunch catalog:release
#   bundle exec metacrunch catalog:ids
#   bundle exec ruby -I../../lib -e 'ARGV.each { require File.expand_path(it) }' test/*_test.rb
Metacrunch.load_files "jobs/*.rb", "transforms/*.rb", "commands/*.rb"
```

`examples/project/test/public_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the transform catalog:public alone and in the job catalog with
# Metacrunch::Testing.run. project: lets the job's names resolve from any
# working directory.
#
#   bundle exec ruby -Ilib examples/project/test/public_test.rb

require "minitest/autorun"
require "tmpdir"
require "metacrunch"
require "metacrunch/testing"

class PublicTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))
  RECORDS = [{"id" => "a", "title" => "A", "public" => true}, {"id" => "b", "title" => "B", "public" => false}].freeze

  def test_keeps_the_public_records_with_the_given_fields
    result = Metacrunch::Testing.run(PROJECT.fetch("catalog:public"), params: {fields: ["id"]}, source: RECORDS)

    assert_equal [{"id" => "a"}], result.records
    assert_equal(["Not public"], result.rejects.map { |_record, rejection| rejection.reason })
  end

  def test_the_job_catalog_names_the_steps_of_the_transform
    Dir.mktmpdir do |out|
      result = Metacrunch::Testing.run(PROJECT.fetch("catalog"), params: {output: out}, project: PROJECT)

      assert_equal ["catalog:public/reject#1", "catalog:public/map#2"], result.stats.steps.keys
      assert_equal 4, result.records.size
    end
  end

end
```

In `examples/Readme.md`, replace the row of `project/`:

```markdown
| [`project/`](project) | A project: its [`Metacrunchfile`](project/Metacrunchfile) names its jobs, a transform and a command, so `metacrunch NAME` runs them from any directory of the project. The transform [`catalog:public`](project/transforms/public.rb) holds the steps that the jobs `catalog` and `catalog:ids` share with different values. The command `catalog:release` invokes the job `catalog` and switches `out/current` to the new release only after a clean run. [`project/test/`](project/test) tests the command with `Metacrunch::Testing.invoke` and the transform with `Metacrunch::Testing.run`. |
```

and replace the line `$ bundle exec ruby -Ilib examples/project/test/release_test.rb` in the command list with:

```
$ (cd examples/project && bundle exec metacrunch catalog:ids)
$ (cd examples/project && bundle exec metacrunch catalog:public --fields id < data/titles.jsonl)
$ bundle exec ruby -Ilib examples/project/test/release_test.rb
$ bundle exec ruby -Ilib examples/project/test/public_test.rb
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -w -Ilib -Itest test/integration/examples_test.rb && bundle exec ruby -Ilib examples/project/test/public_test.rb`
Expected: PASS; `test_project_release_switches_current_only_after_a_clean_run` still passes (4 titles, exit status 3 for `data/broken.jsonl`, whose failure is now in `catalog:public/map#2`)

- [ ] **Step 5: Run the full suite and lint**

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

- [ ] **Step 6: Commit**

```bash
git add examples/project examples/Readme.md test/integration/examples_test.rb
git commit -m "$(cat <<'EOF'
Share the steps of the example project in a transform

The transform catalog:public holds the steps of the job catalog; the new
job catalog:ids uses it with other fields. A test runs the transform alone
and the job with project:.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---
### Task 8: Readme, changelog and the engine's cost

**Files:**
- Modify: `Readme.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: the behavior of Tasks 1 to 7.
- Produces: documentation only.

- [ ] **Step 1: Update the Readme**

In `Readme.md`:

a) In the list at the top, add after "- Steps say what they do: `map`, `filter`, `reject`, `flat_map`.":

```markdown
- Transforms are named groups of steps with parameters of their own; jobs share them with `use`.
```

and change the bullet of the `Metacrunchfile` to:

```markdown
- A project's `Metacrunchfile` names its jobs, transforms and commands; `metacrunch NAME` runs them from any
  directory of the project, and commands chain jobs and other commands.
```

b) Add this section after "## Parameters" (before "## Credentials"):

````markdown
## Transforms

A transform is a named group of steps with parameters of its own and without source or sink. Jobs insert it with
`use`; the job decides where the records come from, where they go and how errors are handled.

```ruby
# transforms/normalize.rb
Metacrunch.transform "normalize", desc: "Clean titles, drop records without one" do
  params do
    param :lang, String, default: "de", desc: "Language of the stopword list"
  end

  stopwords = nil
  before { stopwords = Stopwords.load(params.lang) }
  map { |record| record.merge("title" => Titles.clean(record["title"], stopwords)) }
  reject("No title") { it["title"].nil? }
end
```

```ruby
# jobs/marc2es.rb
Metacrunch.job "marc2es" do
  params do
    param :index, String, required: true
    param :lang, String
    args :files, min: 1
  end

  source MarcReader.new(params.files), id: ->(record) { record["001"] }
  use "marc:to-json", holdings: true
  use "normalize", lang: params.lang
  sink EsSink.new(index: params.index), batch: 1000
end
```

- A transform holds `params`, `map`, `filter`, `reject`, `flat_map`, `before`, `after` and `use`. `source`, `sink`,
  `rejects`, `errors`, `on_error` and `profile` raise an `ArgumentError`: they belong to the job.
- `use` takes a name (in a project, see [Projects and commands](#projects-and-commands)), a path or a transform
  object, and inserts the transform's steps and hooks where it stands. The hooks of a job and its transforms run in
  the order of their statements. A path loads the transform of its file.
- The keywords of `use` set the transform's parameters, as Ruby values or as strings like on the command line;
  `nil` counts as not given. A parameter without a value comes from its `env:` variable, then from the credentials
  of the job, then its default. The steps and hooks of a transform see its own `params`, never the job's.
- The steps get the transform's name as prefix, `normalize/map#1`, in stats, `trace`, `check`, errors and
  `ctx.step`; a second `use` of the same transform gives `normalize#2/...`. Generated step numbers count the
  statements of a recipe, `use` as one, so a transform that gains a step renames no step of the job. Explicit step
  names must not contain `/`.
- A transform may `use` other transforms; a cycle raises an `ArgumentError`.
- Alone, a transform runs like a job without source and sink: `metacrunch run normalize --lang en < titles.jsonl`,
  `trace` and `check` take it, and `Metacrunch::Testing.run(transform, source: [...])` tests it (see
  [Testing jobs](#testing-jobs)).

Compared with a [pipe](#pipes) between two jobs, the transforms of one job share the context of each record (id,
marks, rejections), one `rejects` and `errors` sink, one error policy, one summary and one exit status, and the
records between them need not be JSON. Compared with step classes in plain Ruby, a transform has parameters and a
name in the project, and runs and tests on its own.
````

c) In the table of "Running jobs", change the row of `-j`:

```markdown
| `-j`, `--job NAME` | Select a job, transform or command in a file that declares several |
```

d) In "Running jobs from Ruby", add after the paragraph that ends with "pass `logger:` to `run`.":

```markdown
Names in `use` resolve in `project:` (`job.run(argv, project: Metacrunch.load_project)`), else in the project of the
nearest `Metacrunchfile` above the working directory, loaded when the first name needs it.
`Metacrunch.load_transform(path)` loads a transform as `load_job` loads a job.
```

e) In "Projects and commands", replace the `Metacrunchfile` example, the tree and the help comment:

```ruby
# Metacrunchfile
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

```
project/
├── Metacrunchfile
├── .metacrunch/              credentials
├── jobs/marc2es.rb           Metacrunch.job "marc2es", desc: "..."
├── transforms/normalize.rb   Metacrunch.transform "normalize", desc: "..."
├── commands/catalog.rb       Metacrunch.command "catalog:reindex", desc: "..."
└── lib/
```

```
$ metacrunch --help                                  # lists the jobs, transforms and commands
```

and replace the paragraph that starts with "`metacrunch` finds the nearest `Metacrunchfile`" with:

```markdown
`metacrunch` finds the nearest `Metacrunchfile` above the working directory and loads it only when a name is needed:
for `metacrunch NAME`, for `run`, `check` and `trace` with a name, for `help NAME` and for `--help`, and when a job
run by path uses a transform by name. The other built-in commands never load it, so job files `require` what they use
themselves. The `Metacrunchfile` is plain Ruby. `Metacrunch.load_files` takes globs relative to the project root, or
absolute ones, and loads each matching file once, in sorted order.
```

f) In "Jobs and commands from gems", change the first sentence to "A gem ships job, transform and command files like
a project's, and a constant with their glob for each kind:", add `├── transforms/to_bulk.rb    # Metacrunch.transform "es:to-bulk" do ... end` to the tree before the `jobs/` line, add
`TRANSFORMS = File.expand_path("elasticsearch/transforms/*.rb", __dir__)` to the module, and replace the
`Metacrunchfile` example:

```ruby
# Metacrunchfile
require "metacrunch/elasticsearch"

Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS, Metacrunch::Elasticsearch::JOBS,
                      Metacrunch::Elasticsearch::TRANSFORMS, "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

In the same section, change "lists the gem's jobs and commands with the project's" to "lists the gem's jobs,
transforms and commands with the project's", and "The job and command files define no constants" to "The job,
transform and command files define no constants".

g) In "What runs when", add after the table:

```markdown
`use` evaluates the recipe of a transform while the recipe of the job is evaluated, once per `use`; `--help` of the
job stops before any `use`.
```

h) In "Testing jobs", add after the paragraph that ends with "do I/O in `open`, `each` and `write`.":

````markdown
A transform is tested the same way, with `source:`, since it has none. Names in `use` resolve in `project:`, else in
the project of the nearest `Metacrunchfile` above the working directory:

```ruby
PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

result = Metacrunch::Testing.run(PROJECT.fetch("normalize"), params: {lang: "en"}, source: [{"title" => " A "}])
result = Metacrunch::Testing.run(PROJECT.fetch("marc2es"), params: {index: "test", files: ["unused"]},
                                 source: [File.read("test/fixtures/record.xml")], project: PROJECT)
result.stats.steps.keys   # ["marc:to-json/map#1", ..., "normalize/map#1", ...]
```

The parameters of transforms get the values of `use` and their defaults; `Testing.run` reads neither the
environment nor credentials.
````

- [ ] **Step 2: Update the changelog**

In `CHANGELOG.md`, add at the end of "### Added":

```markdown
- Transforms: `Metacrunch.transform "normalize" do params { ... }; map { ... } end` holds steps, hooks and parameters
  without source or sink, and a job inserts them with `use "normalize", lang: "en"`. Their steps are named with the
  transform as prefix (`normalize/map#1`); explicit step names must not contain `/`. A transform runs, traces, checks
  and tests alone like a job without source and sink. `Metacrunch.load_transform`, and `project:` for `Job#run` and
  `Testing.run`.
```

- [ ] **Step 3: Check the engine's cost and the whole branch**

Run: `bundle exec ruby -Ilib bench/executor.rb inline`
Expected: about 64 ns per step and record (within 5 %), the same allocations per record as before. The engine did not change; a larger difference means something else runs per record: find it before the commit.

Run: `bundle exec rake`
Expected: all tests pass, coverage above the thresholds, RuboCop clean.

Check the Readme examples by reading them against the code: the names in the transform section match `Builder` (`use`), the messages match (`a transform has no source`), and every link target exists (`#pipes`, `#testing-jobs`, `#projects-and-commands`).

- [ ] **Step 4: Commit**

```bash
git add Readme.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
Describe transforms in the Readme and the changelog

A section on transforms (declaration, use, values, step names, running
and testing alone, compared with pipes and Ruby step classes), and
transforms in projects, gems, What runs when, Running jobs from Ruby and
Testing jobs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```
