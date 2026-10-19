# metacrunch-ng, sub-project 10: a consistent API for jobs, transforms and commands

- Date: 2026-10-19
- Branch: `metacrunch-ng-api` (from `metacrunch-ng-readme` at 65eb0c6)
- Status: approved design, not implemented
- Builds on: [sub-project 7 spec](2026-10-13-metacrunch-ng-commands-design.md)
  (names, projects, `invoke`), [sub-project 8 spec](2026-10-17-metacrunch-ng-transforms-design.md)
  (transforms, `use`), the Readme and `docs/` of `metacrunch-ng-readme`

## 1. Context

The Readme was rewritten as a short introduction with the reference in
`docs/`. Read from a user's point of view, without regard to the
implementation, the declaration of the three kinds of recipes is uniform:
`Metacrunch.job|transform|command NAME, desc:`, the same `params` block,
one namespace, `metacrunch NAME` and `--help` for all three, symmetric
loaders, and `generate` for each with a test. The seams between them are
not:

1. **Parameter values take four forms.** The command line takes
   `--max-length 40`, `use` takes keywords (`max_length: 40`), `invoke` and
   `Job#run` take strings as on the command line (`"--output", path`) next
   to keywords for their own options (`workers:`, `limit:`), and
   `Metacrunch::Testing` takes a Hash (`params: {output: "unused"}`). A user
   who knows `use` writes `invoke "catalog", output: path` and gets an
   `ArgumentError`. A value that is optional needs a conditional array
   (`input = params.input ? ["--input", params.input] : []`).
2. **Only commands reach the project's files.** A command has `root`; a job
   or transform has nothing alike, so a default such as
   `"data/titles.jsonl"` is relative to the working directory. The Readme
   says that a job runs "by name, from any directory of the project", but
   `metacrunch catalog` started in `jobs/` aborts with `ENOENT`.
3. **Two words for a failed record.** The `errors` sink, `on_error`,
   `max_errors`, `--errors`, `--on-error`, `--max-errors` and
   `Testing::Result#errors` say "error"; `ctx.failure`, `stats.failed`,
   `:ok_with_failures`, the summary, `trace` and the JSON of the
   `ContextWriter` say "failure". `Testing::Result` has `errors` (failed
   records) next to `error` (the exception that aborted the run).
4. **`invoke` returns different things.** A job or transform gives a
   `Result` with `status` and `ok?`; a command gives the value of its body.
   `invoke(name).ok?` breaks for a command, although the command line
   reports a status for commands too (its exit status).
5. **`Testing.run` and `Testing.invoke` are addressed differently.**
   `Testing.invoke(PROJECT, "name")` takes a project and a name;
   `Testing.run(PROJECT.fetch("name"), project: PROJECT)` takes an object
   and names the project twice.

The word `run` in a command (`run do ... end`) was examined as well. It
stays: it declares what the command does when it runs, as `before` and
`after` declare what a job does around its run, and `metacrunch run NAME`
runs exactly that block (section 7).

metacrunch 5 is not released, and 4.x is no design criterion: old names and
forms are removed without aliases or migration messages.

### 1.1 Goals

1. One form for parameter values in Ruby: a `params:` Hash for `use`,
   `invoke`, `Project#invoke`, `Job#run` and `Metacrunch::Testing`, bound
   by one set of rules. The argv form remains on the command line only.
2. `root` in all three kinds of recipes, with one meaning.
3. One word for a record that failed: *failure*. *Error* means an
   exception.
4. `invoke` returns a result with a common core (`status`, `ok?`, `error`)
   for every target.
5. `Testing.run` and `Testing.invoke` take the same two addressings.

### 1.2 Non-goals

- Renaming `run` in commands (section 7).
- A `:path` parameter type that resolves relative defaults against the
  project root.
- Changing the working directory (`chdir`) for calls by name.
- The other points of the review: the reason of `filter`, the `files:lines`
  notation of `generate source`, the name of `-j`/`--job` (section 12).
- `Transform#run` or a way to run a `Command` object other than `invoke`.
- A `summary` for command results.

### 1.3 Success criteria

1. `Readme.md`, `docs/`, `examples/` and the generator templates contain no
   argv form of `invoke` or `Job#run`, no keyword form of `use`, and none of
   `errors` (as a sink), `on_error`, `max_errors`, `--errors`,
   `--on-error`, `--max-errors`.
2. In a temporary project, a job whose input defaults to
   `root.join("data/titles.jsonl")` runs by name from a subdirectory of the
   project. Its `--help` shows the absolute default. Run by path outside a
   project, it ends with exit status 2 and "no Metacrunchfile found". The
   `--help` of a job by path that uses `root` in its `params` does not load
   a `Metacrunchfile` that raises.
3. A command invokes a job with `params:`, among them `nil` for an optional
   parameter and a `Pathname`. `invoke` of a command returns a
   `CommandResult` whose status is `:ok_with_failures` when a job it invoked,
   also through a nested command, ended with failures.
   `project.invoke(...).ok?` works for jobs and commands alike.
4. `failures`, `on_failure`, `max_failures`, `--failures`, `--on-failure`
   and `--max-failures` work; the old names fail.
5. `Testing.run(PROJECT, "catalog", ...)` tests a job by name; its result
   has `failures` and `ok?`.
6. The example project, a project made by `metacrunch new` with every kind
   generated, and every example in `Readme.md` and `docs/` run. `bundle
   exec rake` passes (coverage at least 95 % lines and 90 % branches,
   RuboCop).

### 1.4 Decisions

| Question | Decision |
|---|---|
| Form of parameter values in Ruby | `params:` Hash everywhere, also for `use`; no keyword form, since `limit` and `workers` are valid parameter names |
| argv in Ruby APIs | Removed from `invoke`, `Project#invoke` and `Job#run` |
| Binding of `params:` | The rules of `use` today: declared type or String, `nil` means not given, then `env:`, credentials, default; a `Pathname` counts as String |
| Testing | The same rules with an empty environment and no credentials |
| Project files | `root` in jobs, transforms and commands: the root of the project the call runs in |
| Without a project | `root` raises `ProjectError` when called, not when the recipe loads |
| Word for a failed record | *failure*: `failures`, `on_failure`, `max_failures`, `--failures`, `--on-failure`, `--max-failures`, `Testing::Result#failures` |
| Result of `invoke` | `Result` for jobs and transforms, `CommandResult` (`status`, `error`, `value`) for commands; common core `status`, `ok?`, `error` |
| Status of a command | The worst status of the jobs run during its body, also through nested commands; `:ok` or `:ok_with_failures` |
| Testing addressing | `Testing.run` and `Testing.invoke` take a project and a name, or an object |
| `run` in commands | Stays; documented as the declaration of what the command does when it runs |

## 2. Parameter values in Ruby

### 2.1 Signatures

| Call | New | Removed |
|---|---|---|
| `use` | `use(target, params: {})` | `**values` |
| `invoke` in a command | `invoke(target, params: {}, workers: nil, limit: nil)` | `*argv` |
| `Project#invoke` | `invoke(target, params: {}, logger:, env:, stdin:, stdout:, workers:, limit:)` | `*argv` |
| `Job#run` | `run(params: {}, env:, logger:, observer:, limit:, workers:, project:)` | `argv` |
| `Testing.run` | `params:` as today (section 6) | |
| `Testing.invoke` | `params:` as today | |

`target` stays as it is: a name or a path, and for `use` also a
`Transform`. The command line binds argv as before; argv exists only
there.

```ruby
use "normalize", params: {max_length: 40}

result = invoke "catalog", params: {output: release, input: params.input}, workers: 4

job.run(params: {output: "out.jsonl"}, limit: 1000)
project.invoke("catalog:release", params: {out: "tmp"})
```

### 2.2 Binding

The same rules for every call in 2.1, today the rules of `use`:

- Keys are Symbols or Strings; the `args` of a recipe are given by their
  name (`params: {files: ["a.csv"]}`).
- A value has the declared type or is a String, which is converted as on
  the command line.
- A value that responds to `to_path` (a `Pathname`) counts as the String of
  its path, also as an element of an `Array` value and as the `default:` of
  a declaration (`default: root.join("data/titles.jsonl")`).
- `nil` means not given. A parameter without a value is read from its
  `env:` variable, then from the credentials, then its default. An optional
  value therefore needs no condition: `input: params.input`.
- Values from code give no secret warning, and messages name a parameter by
  its name (`output`), not as an option (`--output`).
- `params:` must be a Hash; anything else raises `ArgumentError`.

`Metacrunch::Testing` binds by the same rules with an empty environment and
no credentials: tests never read either (section 6).

### 2.3 Errors

| Problem | `use` | `invoke`, `Project#invoke` | `Job#run` | Testing |
|---|---|---|---|---|
| Unknown key | `ArgumentError` | `InvokeError` | `ArgumentError` | `ArgumentError` |
| Invalid or missing required value | `ParamError` | `InvokeError` | `ParamError` | `ParamError` |
| `params:` not a Hash | `ArgumentError` | `ArgumentError` | `ArgumentError` | `ArgumentError` |

Messages of `use` keep their prefix (`use outer → inner: ...`); `invoke`
keeps `invoke NAME: ...`. An unknown key lists the known ones, as `use`
does today. On the command line, a `ParamError` and an `InvokeError` that
leaves a command body end with exit status 2 and 1 as today.

Calls in the old forms (`invoke "x", "--output", y`, `use "x",
max_length: 40`, `job.run(["--output", "out"])`) fail with Ruby's own
`ArgumentError`.

### 2.4 Testing stubs

A stub that is callable gets the `params` Hash of the invoke instead of
argv. `Testing::Invocation` has `name`, `params` and `options` (`argv` is
removed).

## 3. `root` in jobs and transforms

`root` returns the root of the project as a `Pathname`, as it does in
commands today. It is available wherever code of a recipe runs: in its
statements, in `params do ... end` (for defaults), in hooks and in step
blocks.

```ruby
Metacrunch.job "catalog", desc: "Write the public titles" do
  params do
    param :input, String, default: root.join("data/titles.jsonl")
    param :output, String, required: true
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  ...
end
```

The project is the one the call runs in:

| Call | `root` |
|---|---|
| Command line, by name | The project that declares the name |
| Command line, by path | The nearest `Metacrunchfile` above the working directory |
| `invoke` in a command, `Project#invoke` | The project of the chain, or that project |
| `use` | The `root` of the job that uses the transform |
| `Job#run(project:)`, `Testing.run(object, project:)` | `project:`, else the nearest `Metacrunchfile` above the working directory |
| `Testing.run(PROJECT, name)`, `Testing.invoke(PROJECT, name)` | `PROJECT` |
| A recipe from a gem | The project of the user, as for commands today; `__dir__` reaches the gem's files |

- Finding the root does not load the `Metacrunchfile`. The `--help` of a
  job run by path whose `params` use `root` still does not load it (the
  guarantee of sub-project 8 holds); calls that need names load it as
  before.
- Without a project, loading a recipe works. `root` raises `ProjectError`
  "no Metacrunchfile found in DIR or above" when it is called: on the command
  line exit status 2, in `Job#run` and `Testing.run` the error propagates
  like any error of a recipe, and in a step block the record fails like for
  any exception. The documentation recommends `root` in the recipe or a
  hook.
- `--help`, `check` and `trace` evaluate `params`, so a default built with
  `root.join(...)` shows as an absolute path in `--help`, and a job whose
  `params` use `root` shows no help outside a project.
- Values from the command line stay relative to the working directory:
  `--output out.jsonl` writes where `metacrunch` was started. Nothing
  changes the working directory.
- `root` in commands does not change.

## 4. Failures

Rule, stated once in the documentation: **a record fails, which is a
failure; an error is an exception.** A failure holds its error:
`"failure": {"step": "map#2", "error": "KeyError", "message": ...}`.

| Where | Old | New |
|---|---|---|
| Job statement | `errors SINK, batch: N` | `failures SINK, batch: N` |
| Job statement | `on_error :abort \| :skip, max_errors: N` | `on_failure :abort \| :skip, max_failures: N` |
| `run` option | `--errors PATH` | `--failures PATH` |
| `run` option | `--on-error abort\|skip` | `--on-failure abort\|skip` |
| `run` option | `--max-errors N` | `--max-failures N` |
| `Testing::Result` | `errors` | `failures` |
| Messages and documentation | "error policy", "errors sink" | "failure policy", "failures sink" |

- The statements a transform refuses become `source`, `sink`, `rejects`,
  `failures`, `on_failure` and `profile`, and the message says so.
- Unchanged, because they already say *failure* or mean an exception:
  `ctx.failure`, `stats.failed`, `:ok_with_failures`, "failed" in the
  summary, `trace` and the progress display, the JSON of `ContextWriter`
  and `--stats`, `Result#error`, the exception classes (`StepError`,
  `InvokeError`, ...).
- Errors in sources, sinks, hooks, `open` and `close` still end the run:
  they are errors, not failures of a record, and the failure policy does
  not apply to them.
- Semantics, defaults and validation of the policy do not change
  (`max_failures: 0` stops at the first failure after it reached the
  failures sink).

Afterwards both outcomes of a record read alike: `reject` gives `rejects`,
`--rejects`, `ctx.rejection` and "rejected"; a step that raises gives
`failures`, `--failures`, `on_failure`, `ctx.failure` and "failed".

## 5. Results of `invoke`

Every result has the core `status`, `ok?` (`status == :ok`) and `error`.

| Target | Result | In addition |
|---|---|---|
| Job, transform | `Metacrunch::Result` (unchanged) | `stats`, `summary` |
| Command | `Metacrunch::CommandResult` (new: `status`, `error`, `value`) | `value`: what the body returned |

```ruby
result = invoke "catalog:release", params: {out: "tmp"}
result.ok?     # false if a job in it ended with failures
result.value   # e.g. the path of the release
```

- **Status of a command:** the worst status of the jobs and transforms run
  while its body ran, also through nested commands: `:ok_with_failures`
  if one ended with failures, or aborted and the body rescued the
  `InvokeError` and went on; else `:ok`. When command A invokes command B,
  A's status includes B's. The exit status of a command on the command line
  is derived from the same status, as today.
- `error` of a `CommandResult` from `invoke` is always `nil`: an exception
  that leaves a body passes unchanged, so a command never returns
  `:aborted`. The field keeps the core uniform.
- Unchanged: an aborted job raises `InvokeError` with its `result`; the
  command line prints no `value`.
- `Project#invoke` returns the same results.

## 6. Testing

### 6.1 Addressing

`Testing.run` takes both addressings, as `Testing.invoke` does today:

```ruby
Metacrunch::Testing.run(PROJECT, "catalog", params: {output: "unused"}, source: records)
Metacrunch::Testing.run(job, params: {output: "unused"}, source: records, project: PROJECT)
Metacrunch::Testing.invoke(PROJECT, "catalog:release", params: {out:}, stubs: {"catalog" => :ok_with_failures})
Metacrunch::Testing.invoke(command, params: {out:}, stubs: {...})
```

| | Job, transform | Command |
|---|---|---|
| Method | `Testing.run` | `Testing.invoke` |
| Addressing | `(project, name)` or `(object, project: nil)` | the same |
| Instead of I/O | `source:`, sinks in memory | `stubs:` for invoked names |
| Result core | `status`, `ok?`, `error` | the same |

- With a project and a name, the name must be a job or transform; names of
  `use` and `root` resolve in that project.
- `ArgumentError` for: a command name ("catalog:release is a command; test
  it with Testing.invoke"), `project:` next to a project as first argument,
  a name next to an object, a missing name after a project. These mirror
  the messages of `Testing.invoke`.
- `params:` is bound as in 2.2 with an empty environment and no
  credentials.

### 6.2 Results

- `Testing::Result`: `records`, `rejects`, `failures` (was `errors`),
  `stats`, `status`, `error`, and `ok?`.
- `Testing::CommandRun` becomes `Testing::CommandResult`: `value`,
  `status`, `error`, `invoked`, and `ok?`. A body that raises gives
  `:aborted` with the exception in `error`, as today.
- Stubs for jobs give a status Symbol or a `Result`, as today. Stubs for
  commands give a value, which becomes the `value` of a `CommandResult`
  with status `:ok`, or a `Metacrunch::CommandResult` with status `:ok` or
  `:ok_with_failures`, which counts towards the status of the command
  under test; any other status raises `StubError`.

## 7. `run` in commands

No change to the API. `docs/projects.md` says: "`run` declares what the
command does when it runs, as `before` and `after` do for a job."

## 8. Architecture

| Unit | Change |
|---|---|
| `Params` | One binding for Ruby callers (today's `bind_values`) with `to_path` values and defaults; `bind_hash` is replaced by it with an empty environment and no credentials |
| `RecipeParams`, `Params` schema | `root` in `params do ... end` |
| `Builder` | `use(target, params:)`; `root`; `failures`, `on_failure(policy, max_failures:)`; the refused statements of a transform |
| `UseContext` | Passes `params:`; gives `root` of its resolver to the transforms it evaluates |
| `Invoker` | `invoke(target, params:, workers:, limit:)`; binding through `Params`; status per command call (nested); `CommandResult` for commands; `root` found without loading the project |
| `CommandScope` | `invoke` signature |
| `Project` | `invoke` signature; finding a root without loading the `Metacrunchfile` |
| `Job` | `run(params:, ...)` |
| `CommandResult` (new) | `Data` with `status`, `error`, `value`, `ok?` |
| `Pipeline`, `RunOptions`, `Cli::Run` | `failures` role, failure policy, `--failures`, `--on-failure`, `--max-failures` |
| `Testing` | `run(project, name)`; binding (2.2); `failures`; `CommandResult`; stubs with `params` |
| Generator templates | `invoke ... params:` in the command comment; `Testing.run(PROJECT, "name")` in the tests of jobs and transforms |

The engine, executors, stats, `trace` and the JSON formats do not change.
No new dependency.

## 9. Exit codes

No new codes. `root` without a project ends with 2 (`ProjectError`), like
other project errors.

## 10. Tests

### 10.1 Unit tests

- Binding (2.2) for each caller: declared types and Strings, `nil` as not
  given with `env:`, credentials and default behind it, `Pathname` values,
  `Pathname` in an Array, `Pathname` defaults, `args` by name, unknown keys
  with the list of known ones, invalid and missing values, `params:` that is
  not a Hash, no secret warning; Testing reads neither environment nor
  credentials.
- `root` in a statement, a `params` default, a hook and a step, for every
  row of the table in section 3; without a project; finding the root does
  not load the `Metacrunchfile`.
- `failures` and `on_failure` with their validation; the refused statements
  of a transform; `on_error` and `errors` are gone.
- `CommandResult`: status with and without failures, nested commands, a
  rescued `InvokeError`, `error` is `nil`, `value`; `Project#invoke`.
- `Testing.run` with a project and a name and its error cases; `ok?` and
  `failures`; `Testing::CommandResult`; stubs with `params` and with a
  `CommandResult`; `Invocation#params`.

### 10.2 Command tests

Through `Cli` with injected streams: `--failures`, `--on-failure`,
`--max-failures`, and the old options as invalid; a job with a `root`
default by name from a subdirectory, by path, and its `--help` with the
absolute default; `root` outside a project with exit status 2; the `--help`
of a job by path with `root` in `params` and a `Metacrunchfile` that
raises; a command whose invoked job ends with failures (exit status 3).

### 10.3 End to end

Through `exe/metacrunch`: the example project (release command with
`params:`, job with `root`); a project made by `metacrunch new` with a job,
a transform and a command generated, its `rake test` and RuboCop; every
example in `Readme.md` and `docs/` once (as for the Readme rewrite).

## 11. Documentation, examples, templates

| File | Change |
|---|---|
| `Readme.md` | The tour job with `default: root.join(...)`, the `failures` sink and `on_failure`; the release command with `params:`; the test with `Testing.run(PROJECT, "catalog", ...)` |
| `docs/jobs.md` | Section "Errors" becomes "Failures" and opens with the rule; `use ... params:`; `root` and `Pathname` values under "Parameters"; the overview job |
| `docs/transforms.md` | `use ... params:`; `root` |
| `docs/projects.md` | `invoke ... params:`; the table of results with `CommandResult`; the sentence on `run`; `root` in all three kinds |
| `docs/testing.md` | Both addressings; `failures`; stubs get `params`; `Invocation#params`; `CommandResult` |
| `docs/cli.md` | `--failures`, `--on-failure`, `--max-failures` |
| `docs/ruby-api.md` | `Job#run(params:)`, `Project#invoke(params:)`, the results |
| `docs/workers.md`, `docs/credentials.md` | Any mention of the old names or forms |
| `CHANGELOG.md` | The 5.0 entries describe the new API (5.0 is unreleased: no "changed from" entries) |
| `examples/project` | The release command with `params:` and `root`, its test with `CommandResult`; the job `catalog` with a `root` default |
| `examples/catalog.rb`, `examples/sanitize.rb`, `examples/lib/issue_report.rb`, `examples/Readme.md` | `failures`, `on_failure` |
| Generator templates | See section 8 |

## 12. Deferred

- The reason of `filter` reads as a negation of its block
  (`filter("No title") { it["title"] }`); documentation only, if at all.
- `generate source files:lines` uses the notation of names for a class
  (`Files::Lines`).
- `-j`/`--job` selects transforms and commands as well.
- A `:path` parameter type whose relative defaults resolve against the
  project root.
- A `summary` for `CommandResult`.
