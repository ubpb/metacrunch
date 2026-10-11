# metacrunch-ng, sub-project 1: modern core

- Date: 2026-10-10
- Branch: `metacrunch-ng`
- Status: approved; revised after the final review (see 1.4)

## 1. Context

metacrunch is a small Ruby ETL toolkit. Jobs are Ruby files that declare a
source, a chain of transformations and a destination. At UB Paderborn it
transforms library metadata, e.g. MARCXML/MAB to JSON for Elasticsearch, or
RIS exports to FIS CSV files (`ris2fis`).

`metacrunch-ng` redesigns metacrunch. It starts as a prototype and is built so
it can become metacrunch 5. Backward compatibility with 4.x is not required.

The redesign is split into sub-projects. Each gets its own spec and plan:

| # | Sub-project | Content |
|---|---|---|
| **1** | **Modern core (this spec)** | Pipeline model, explicit step contract, per-record context, error policy, stats, Ruby DSL, job parameters, minimal CLI, tests, CI |
| 2 | CLI and Unix pipes | Subcommands (`run`, `check`, `trace`, `fix`, `new`), stdin/stdout, JSON Lines, logs on stderr, progress |
| 3 | Declarative jobs | YAML/TOML job files, plugin registry by name |
| 4 | Fix language | Mapping language for the declarative path |
| 5 | Parallel executor | Fork-based workers first, Ractors as an experimental option |

### 1.1 What changes compared to 4.x, and why

| 4.x | Problem | Sub-project 1 |
|---|---|---|
| A transformation returns `nil` to drop a record, an `Enumerator` to fan out | Implicit. An `Array` result is ambiguous (data or n records?) | Explicit step kinds: `map`, `filter`, `reject`, `flat_map` |
| `buffer:` as a transformation option | Every real use was sink batching (ES bulk, Redis) or a workaround for missing parallelism (`Parallel.map`) | Batching only at the sink (`batch: n`) |
| Exceptions abort the job | No way to skip bad records; no record context in errors | Error policy per job (`abort`/`skip`, `max_errors`), errors carry record id, position and step |
| `pre_process`/`post_process` | Lifecycle work (e.g. creating an ES index) lives outside the component that needs it | `open`/`close` on components, `before`/`after` hooks on the job |
| `options` parses `ARGV` while the job is defined, calls `exit` | Side effects at definition time; not testable | Recipe and pipeline are separate; parameters are bound from outside |
| `Dir.chdir` into the job directory | Path parameters resolve against the job, not the user's cwd | No `chdir` |
| `TransformationContext` (ris2fis) re-implemented per project, with class-variable counters | Counters break with fork workers and Ractors; every project rebuilds skip/mark logic | Per-record context in the core, aggregated by the engine |
| `data.present?` before writing | Silently drops empty hashes and arrays | Removed; only an explicit `filter`/`reject` drops records |
| ActiveSupport, colorize | Heavy dependencies for `blank?`, `strip_heredoc`, colors | No ActiveSupport, no colorize |
| CLI exits with 0 on errors (`cli.rb:48`) | Scripts cannot detect failures | Defined exit codes |

### 1.2 Non-goals of sub-project 1

- CLI subcommands, `trace`, progress display, stdin/stdout pipes, JSON Lines
  sources and sinks (sub-project 2).
- YAML/TOML job files, plugin registry (sub-project 3).
- Fix language (sub-project 4).
- Parallel execution (sub-project 5). Sub-project 1 only defines the seam.
- Migration of the extension gems (metacrunch-file, -marcxml, -elasticsearch,
  -db, -redis). They are adapted once the core is stable.
- `map_batch` (batched lookups inside a step). Can be added later without
  breaking the API if a real use case appears.

### 1.3 Success criteria

1. A job file using the full DSL (parameters, all step kinds, `reject` with
   reason, `ctx.mark`, sink with `batch:`, `rejects`/`errors` sinks,
   `on_error :skip`) runs end to end through `exe/metacrunch`. It produces the
   expected records, stats and exit code.
2. The same job runs in a Minitest test through `Metacrunch::Testing.run`
   without touching files or the network.
3. `bundle exec rake` (tests and RuboCop) passes locally. CI passes on Ruby
   4.0 on Linux and macOS.
4. Line coverage is at least 95 %, branch coverage at least 90 %.

### 1.4 Revisions after the final review

The final review of the implementation led to these changes, all reflected
in the sections below:

- Sinks are flushed after an abort and on signals (Ctrl-C, SIGTERM), so `batch:` never
  changes which records reach a sink; `written` counts records the sink
  accepted (3.2, 3.3, 3.4).
- `flat_map` streams its children instead of collecting them first (2.3, 3.1).
- Only a second *required* parameter (or a named splat) asks for the
  context; optional parameters no longer do (2.3, 2.4).
- Reasons are Strings; Symbols are converted, `nil`/empty raise (2.3, 2.5).
- `ScriptError` and `SystemStackError` follow the error policy (3.3).
- `max_errors: 0` is allowed (3.3).
- Sources that yield several values produce an Array record (2.2).
- Parameters: no abbreviated options, defaults are converted and checked,
  bound values are frozen, names that hide methods of `params` are
  reserved, environment errors name the variable, empty variables count
  as unset (5.5).
- Job files are cached per path until they change (5.2).
- `Testing.run` reports `written: 0` for jobs without a sink (5.6).
- The executable ends by the signal (`SIGINT`, `SIGTERM`) that stopped the run (6).
- `-h` is reserved as a short option for help (5.5).
- `reject!` ends the step at once by raising `Context::Rejected`; it used
  to set a flag only, so code after it ran on (2.5). Changed before
  sub-project 4.

## 2. Data model and contracts

### 2.1 Record

A record can be any Ruby object. A source may emit domain objects (e.g. a
parsed MARC record) that a `map` step converts.

Convention: records that leave a job, or are processed by the declarative
path later, are `Hash` objects with `String` keys. Only these survive a JSON
round trip (sub-project 2 pipes); symbol keys are lost by `JSON.parse`.

The engine neither copies nor freezes records. Rule (documented): a step that
emits the same object more than once (`flat_map`) must not mutate it in place
afterwards.

### 2.2 Source

Any object that responds to `#each` and yields records. Optional `#open(context)`
and `#close`. The engine calls `each` with a block, so sources that only
`yield` work. Several values yielded at once (`yield key, value`) become one
Array record, as with `Enumerable#to_a`.

Declared with an optional id extractor:

```ruby
source MySource.new(params.files), id: ->(record) { record["_id"] }
```

The id becomes `ctx.id`. Without `id:`, `ctx.id` is `nil`.

### 2.3 Steps

| Kind | Callable receives | Callable returns | Effect |
|---|---|---|---|
| `map` | record (and ctx) | the new record | 1:1 |
| `filter` | record (and ctx) | truthy to keep | 0..1 |
| `reject` | record (and ctx) | truthy to drop | 0..1 |
| `flat_map` | record (and ctx) | an `Enumerable` of records | 0..n |

- A callable is a block or any object that responds to `#call`, including a
  class with `self.call`.
- **Context parameter.** The engine passes `ctx` as second argument if the
  callable asks for it: a second *required* positional parameter, or a named
  splat (`*args`). Optional parameters do not count, so library methods such
  as `method(:Integer)` or `JSON.method(:generate)` get only the record, and
  so do Symbol procs (`&:odd?`, unnamed splat). It decides once, when the
  pipeline is built, from the parameters of the block or of `#call`
  (`Proc#parameters(lambda: true)`, `Method#parameters`). All other callables
  get `(record)`.
- **Names.** Each step has a name, used in errors, stats and later in
  `trace`. Default: `"<kind>#<n>"`, where `n` is the step's 1-based position
  in the pipeline (`map#3`). Explicit: `map Mab2Primo, name: "mab2primo"`.
- **Reasons.** `filter` and `reject` take an optional reason as first
  argument: `reject("Patent") { it["type"] == "patent" }` (a Symbol is
  converted to a String; an empty reason is an `ArgumentError`). With a reason, a
  dropped record is *rejected* (counted per reason, sent to the `rejects`
  sink). Without a reason, it is *filtered* (counted only, not sent anywhere).
- **Contract checks** raise `Metacrunch::ContractError`:
  - `map` returns `nil`.
  - `flat_map` returns something that does not respond to `#each`, or a
    `Hash`. A `Hash` is rejected explicitly because iterating it yields
    key/value pairs; the error message says to return `[hash]`.
- **Streaming.** `flat_map` passes each child on as its Enumerable yields it.
  An error raised by the step's own iteration is a failure of that step;
  children forwarded before it stay forwarded. A `reject!` during the
  iteration ends it. Errors from later steps and sinks are not counted as
  failures of the `flat_map` step, and a `rescue => e` inside the step's
  Enumerable cannot catch them.

### 2.4 Sink

Any object that responds to `#write(record)`. Optional `#write_batch(records)`,
`#open(context)` and `#close`.

- `sink MySink.new, batch: 1000` collects records and calls
  `write_batch(records)` with up to 1000 records. Without `write_batch`, the
  engine calls `write` for each record of the batch. The rest is flushed
  before `close`.
- **Context.** Like steps, a sink receives contexts if its method asks for
  them (second required parameter): `write(record, ctx)` and
  `write_batch(records, ctxs)`. Sinks use
  them to read marks (as `FisDestination` does). Calling `ctx.reject!` or
  `ctx.mark` inside a sink raises `ContractError`.
- One `sink` per job. Declaring a second one raises `ArgumentError` (4.x
  silently kept the last one). A job without a sink is valid; its records are
  counted as `out` of the last step and then discarded.
- `rejects SINK` receives rejected records with their context
  (`ctx.rejection`). `errors SINK` receives records that failed under
  `on_error :skip`, with their context (`ctx.failure`). Both are optional and
  accept `batch:`.
- One object used for several of these roles (e.g. as `sink` and `rejects`)
  is opened and closed once.

### 2.5 Per-record context

The engine creates one context per record emitted by the source.

| Member | Meaning |
|---|---|
| `id` | From the source's `id:` extractor, else `nil` |
| `position` | 1-based number of the record in the source |
| `step` | Name of the step currently processing the record |
| `reject!(reason, value: nil)` | Reason: a non-empty String or Symbol (converted to String), else `ContractError`. Stops processing this record immediately: it records a rejection (`reason`, `value`, `step`) and ends the step by raising `Context::Rejected` (an `Exception`, so `rescue => e` in a step does not catch it). The engine rescues it around every step and sends the record to the `rejects` sink. If the step rescues it anyway and returns, the record is still rejected and the return value is ignored. Called on the context of another record, it fails the step with `ContractError`. |
| `rejected?`, `rejection` | Rejection data (`Data`: `reason`, `value`, `step`) or `nil` |
| `mark(reason, value: nil)` | Records a non-fatal note; the record continues. Same reason rules as `reject!`. |
| `marks` | Array of marks (`Data`: `reason`, `value`, `step`) |
| `failure` | Set for records sent to the `errors` sink (`Data`: `error`, `step`) |
| `store` | A `Hash` for per-record scratch data, e.g. cached enrichment |
| `logger` | The job logger; messages are prefixed with the record id or position. Logger-compatible: message or lazy block, level predicates (`debug?`, ...) |

`flat_map` gives every emitted child a **copy** of the parent context: same
`id` and `position`, own `marks` (copied), own `store` (shallow copy). Rejecting
one child does not affect its siblings.

Not in the core: `source`/`target` separation and job-wide resources (lookup
tables, enrichment directories). Both stay project conventions. In the Ruby
DSL, resources are ordinary objects in the job's scope.

The context does not cross process boundaries in sub-project 2 pipes; JSON
Lines carry payload only.

### 2.6 Lifecycle and hooks

Components (source, steps, sinks) may implement `open(context)` and `close`.
`context` gives access to the logger and the bound parameters.

The job may declare `before { }` and `after { |result| }` hooks. Several of
each are allowed and run in declaration order. `after` receives the
`Metacrunch::Result` (3.4), so it sees both the stats and the status.

## 3. Execution

### 3.1 Engine

When a run starts, the engine folds the steps into a chain of procs, from the
sink backwards. Each link implements its step kind, sets `ctx.step`, counts
in/out, checks the contract and applies the error policy. Records are pushed
through the chain one at a time, with no intermediate arrays (`flat_map`
streams its children). Step counters are resolved once when the chain is
built.

`Enumerator::Lazy` stays the mental model of the DSL, but is not used
internally. Carrying the context, stopping on `reject!`, per-step counting
and the sink flush map directly onto a push chain.

### 3.2 Run sequence

1. Build the pipeline from the recipe (section 5).
2. `open` on source, steps and sinks.
3. `before` hooks.
4. For each record from the source: create the context, push it through the
   chain.
5. Flush the batches of all sinks. After an abort or a signal (Ctrl-C, SIGTERM) the
   sinks are flushed as well (best effort; flush errors are logged and the
   original error stays the run's error), so `batch:` never changes which
   records reach a sink.
6. `close` on sinks, steps and source, in reverse order. Always runs (in an
   `ensure`), also after an abort.
7. `after` hooks, with the result. They also run after an abort, but not
   after an `Interrupt`.

### 3.3 Error policy

Declared with `on_error :abort` (default) or `on_error :skip, max_errors: n`
(`n >= 0`; `0` stops at the first failure after the record reached the
`errors` sink).

"Exception" below means `StandardError`, `ScriptError` (e.g.
`NotImplementedError`) or `SystemStackError`. Other exceptions
(`NoMemoryError`, signals, `SystemExit`) end the process as usual.

| Situation | Behaviour |
|---|---|
| Exception or `ContractError` in a step, policy `:abort` | Stop. The run is `:aborted`; the error is a `StepError` (below). |
| Same, policy `:skip` | The record counts as failed (by error class), is logged and goes to the `errors` sink. The run continues. |
| `:skip` and the number of failed records exceeds `max_errors` | Stop as with `:abort`. |
| Exception in the source (including the `id:` extractor), a sink, a hook, `open` or `close` | Always stop. |
| Exception in an `after` hook | Logged; the run becomes `:aborted` if it was not already. |

`Metacrunch::StepError` carries the step name, record id, position and the
original exception as `cause`. Its message names all of them.

Error classes (all under `Metacrunch::Error < StandardError`): `ParamError`,
`ContractError`, `StepError`, `JobLoadError`.

Signals (`Interrupt` from Ctrl-C, `SignalException` from SIGTERM) are not
rescued by the policy. Sinks are flushed and closed, sources closed (steps 5
and 6), then the signal propagates.

### 3.4 Result and stats

`Job#run` returns a `Metacrunch::Result` (`Data`) and does not raise on an
abort:

- `status`: `:ok` (no failed records), `:ok_with_failures` (failed records
  under `:skip`), `:aborted`.
- `error`: the error that aborted the run, else `nil`.
- `stats`: a `Metacrunch::Stats` snapshot.
- `summary`: one line with status and the main counts, for logs.

`Stats` (`Data`, immutable):

- Job level: `read`, `written` (records the sink accepted), `filtered`, `rejected` (total and per reason),
  `marked` (number of marks per reason), `failed` (total and per error class),
  `duration`, `rate` (records read per second).
- Per step, keyed by step name: `input`, `output`, `filtered`, `rejected`,
  `failed`, and `time` only if the job sets `profile true`. Timing is opt-in
  because two clock reads per step and record add up (50 steps × 1 million
  records).
- `#to_h` for JSON output, `#summary` for a one-line text summary.
- `#merge(other)` adds two snapshots. Not used in sub-project 1, but it is the
  basis for fork workers reporting to the parent in sub-project 5.

Counting is done by a mutable collector inside the engine, which produces
the snapshot at the end.

### 3.5 Seams for later sub-projects

- **Executor.** The engine hands the source, chain and sink adapters to an
  executor. Sub-project 1 ships `Executor::Inline` only. It processes
  records in source order. Because there is no batch step, the whole step
  chain is stateless with respect to the stream. A fork executor can run all
  steps in workers and keep only the sinks in the parent.
- **Observer.** The engine accepts an optional observer that receives
  `step_in(step, record, ctx)` and `step_out(step, outputs, ctx)`. The check
  for an observer happens when the chain is built; without one, no call is
  made per record. Every `step_in` gets a matching `step_out`. For `flat_map`
  the `step_out` comes after its children went downstream (it streams).
  Used by `trace` in sub-project 2.

## 4. Logging

`Metacrunch.logger` defaults to a `Logger` on `$stderr`, level `INFO`, with a
compact formatter. Jobs use `logger` in the DSL and `ctx.logger` in steps.
Nothing in the library writes to `$stdout`; stdout is reserved for data
(sub-project 2 pipes).

## 5. Ruby DSL and job parameters

### 5.1 Recipe and pipeline

`Metacrunch.job(name = nil) { ... }` returns a `Metacrunch::Job`. It stores the
block (the recipe) and evaluates nothing. Evaluating the recipe with bound
parameters produces an immutable `Metacrunch::Pipeline`. This happens anew
for every `run`, `check` and test.

Consequences:

1. Loading a job file has no side effects, so `--help`, `check` and tests
   work without running anything.
2. In sub-project 5 every worker builds its own pipeline, so connections and
   file handles never have to be shared across a fork.
3. No global `ARGV`, no `exit`, no `Dir.chdir` in the library.

The recipe is evaluated with `instance_eval` on a `Metacrunch::Builder`.

### 5.2 Job files

A job file is plain Ruby, loaded with `Kernel#load`. Helper methods and
classes defined in it are ordinary Ruby. The recommended extension is `.rb`
(editor and ruby-lsp support); `.metacrunch` keeps working. The old reason for
avoiding `.rb` (accidental loading) no longer applies, because loading only
registers recipes.

`Metacrunch.load_job(path, name: nil)` loads the file and returns its job.
`Metacrunch.job` registers the job with the active loader, if any; outside a
loader it only returns the job. If the file defines several jobs, `name:` is
required and selects one. Errors (no job, unknown name, ambiguous) raise
`JobLoadError`.

A job file is loaded again only when it changed (modification time), because
loading it twice would redefine its constants.

Paths in parameters are relative to the user's working directory. Files
relative to the job use `require_relative` or `__dir__`.

Convention for components (documented): constructors are cheap and have no
side effects. I/O starts in `open`, `each` or `write`.

### 5.3 Example

```ruby
# jobs/mab2es.rb
require_relative "lib/mab2primo"

Metacrunch.job "mab2es" do
  params do
    param :index, String,  required: true, desc: "Elasticsearch index"
    param :url,   String,  default: "http://localhost:9200", env: "ES_URL"
    param :bulk,  Integer, default: 1000
    args  :files, min: 1, desc: "MAB files"
  end

  source Mab::Source.new(params.files), id: -> { it["id"] }

  reject("Missing ID") { it["id"].nil? }
  map Mab2Primo
  map { |record, ctx|
    ctx.mark("No title") if record["title"].nil?
    record
  }
  flat_map { |record| record["isbns"].map { |isbn| record.merge("isbn" => isbn) } }

  sink    Es::Sink.new(url: params.url, index: params.index), batch: params.bulk
  rejects RejectsCsv.new("rejects.csv")
  on_error :skip, max_errors: 100

  after { |result| logger.info(result.summary) }
end
```

### 5.4 DSL vocabulary

| Method | Purpose |
|---|---|
| `params { ... }` | Declare parameters (must come before `params` is read) |
| `params` (no block) | The bound parameters (`Data`) |
| `source OBJ, id: CALLABLE` | The source |
| `map`, `filter`, `reject`, `flat_map` | Steps (block or callable, optional `name:`, reason for `filter`/`reject`) |
| `sink OBJ, batch: n` | The sink |
| `rejects OBJ, batch: n` | Sink for rejected records |
| `errors OBJ, batch: n` | Sink for failed records under `:skip` |
| `on_error :abort` / `on_error :skip, max_errors: n` | Error policy |
| `profile true` | Per-step timing |
| `before { }`, `after { \|result\| }` | Hooks |
| `logger` | The job logger |

### 5.5 Parameters

```ruby
params do
  param :name, Type, default: ..., required: true, env: "VAR", desc: "...", short: "-n"
  args  :name, min: 0, max: nil, desc: "..."
end
```

- Types: `String` (default), `Integer`, `Float`, `:bool` (CLI flag
  `--[no-]name`), `Array` (comma-separated strings).
- CLI option names derive from the parameter name, `_` becomes `-`
  (`:bulk_size` → `--bulk-size`).
- Precedence: CLI value, then environment variable (`env:`), then `default:`.
  Environment values are converted with the parameter's type; an empty
  variable counts as unset; conversion errors name the variable.
- Abbreviated options are not accepted (`--ind` does not mean `--index`).
- `default:` together with `required: true` raises `ArgumentError`. Defaults
  are converted like CLI values when declared (`Integer, default: "1000"`
  gives 1000); an invalid default raises `ArgumentError`.
- `args` collects the positional arguments into an `Array`; `min`/`max`
  are checked. Without `args`, positional arguments are an error.
- `help` and `job` are reserved names, and so are names that would hide a
  method of the bound params object (`to_h`, `with`, `hash`, ...), checked
  when the parameter is declared. `-h` is reserved as a short option.
- Binding errors (missing required value, conversion error, unknown option,
  wrong number of arguments) raise `ParamError`. The library never calls
  `exit` or prints.
- Bound parameters are a `Data` instance: `params.index`. Their values are
  frozen (Strings and Arrays), so a default cannot leak changes between runs.
- **Help.** To describe a job (`--help`), the CLI evaluates the recipe in
  describe mode. The `params` block declares the parameters, then evaluation
  stops with `throw`, so no source, step or sink is constructed. Consequence
  (documented): `params` must be the first statement of the recipe.

### 5.6 Testing jobs

`Metacrunch::Testing` replaces the 4.x `test_utils`. It works with any test
framework and does no I/O of its own.

```ruby
result = Metacrunch::Testing.run(
  Metacrunch.load_job("jobs/mab2es.rb"),
  params: {index: "test", files: ["unused"]},
  source: [{"title" => "no id"}]
)

result.records          # what reached the sink
result.rejects          # [[record, rejection], ...]
result.errors           # [[record, failure], ...]
result.stats            # Stats
result.status           # :ok, :ok_with_failures, :aborted
```

- `params:` are bound like CLI values, without environment lookup. Values
  may already have the declared type (`bulk: 10`) or be strings, which are
  converted (`bulk: "10"`).
- `source:` replaces the job's source with any `Enumerable` (optional).
- The sink and the `rejects` and `errors` sinks are always replaced by
  in-memory sinks, so nothing is written. The replaced sinks are constructed,
  but not opened (constructor convention, 5.2). Jobs without a sink still have
  their records collected, but `stats.written` is 0, as in a real run.

## 6. Minimal CLI

Sub-project 1 ships a minimal CLI so jobs run end to end. Sub-project 2
replaces it with subcommands.

```
metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]
```

- Options before `JOB_FILE`: `-h`/`--help` (CLI usage), `-v`/`--version`.
- After `JOB_FILE`: `--job NAME` selects a job, `-h`/`--help` prints the job's
  parameters (recognized with the job's own option parser, so `-h` as the
  value of another option does not count), all other options are job
  parameters, the rest are `args`.
- Errors and logs go to stderr. Nothing is printed on stdout except help and
  version.
- At the end of a run, status and stats are logged on stderr (`INFO`). An
  error and its cause are logged once each.
- After Ctrl-C or SIGTERM, `Cli#run` returns 128 + signal number (130,
  143) and `exe/metacrunch` then ends by that signal, so callers (shells,
  `xargs`, `make`) see the interruption. Ruby flushes stdout first.
- The job is described (its recipe evaluated up to `params`) only when
  `-h`/`--help` appears in the arguments.

| Exit code | Meaning |
|---|---|
| 0 | `:ok` |
| 1 | `:aborted`, or an unexpected error |
| 2 | Usage error: no or unknown job file, `JobLoadError`, `ParamError` |
| 3 | `:ok_with_failures` |
| 130 | Interrupted by Ctrl-C (SIGINT) |
| 143 | Terminated (SIGTERM) |

## 7. Project setup

### 7.1 Gem

- Version `5.0.0.pre`, `required_ruby_version >= 4.0`.
- Runtime dependency: `logger` only (a bundled gem since Ruby 4.0, so it
  must be declared). `json` and `optparse` are default gems.
- Metadata: `source_code_uri`, `changelog_uri`, `rubygems_mfa_required`.
- `spec.files` from `Dir` globs instead of `git ls-files`.
- Development dependencies in the `Gemfile`, not the gemspec: `minitest`,
  `rake`, `simplecov`, `rubocop-ubpb` (7.3).
- `Gemfile.lock` is committed and removed from `.gitignore`, as Bundler now
  recommends for gems. It includes the `x86_64-linux` platform for CI.
- Files are loaded with explicit `require_relative`, without Zeitwerk: the
  core is small, needs no extra dependency, and has no autoload issues with
  Ractors later.
- `# frozen_string_literal: true` in every file. Ruby 4.0.7 still does not
  freeze string literals by default.

### 7.2 Layout

The 4.x implementation (`Job`, `Job::Dsl`, `Job::Buffer`, `Job::Dsl::Options`,
`Cli`, `TestUtils`) and its specs are removed.

```
lib/metacrunch.rb                 Entry: Metacrunch.job, .load_job, .logger
lib/metacrunch/
  version.rb
  errors.rb                       Error, ParamError, ContractError, StepError, JobLoadError
  job.rb                          Recipe: name + block; #pipeline, #run, #describe
  loader.rb                       Loads job files, collects registered jobs
  builder.rb                      DSL evaluated with instance_eval → Pipeline
  params.rb                       Parameter schema, binding, conversion
  pipeline.rb                     Immutable pipeline (Data)
  step.rb                         Step (Data: kind, callable, name, reason, with_ctx)
  context.rb                      Per-record context, Rejection, Mark, Failure
  engine.rb                       Push chain, run sequence, error policy
  sink_adapter.rb                 batch:, write/write_batch, context arity
  stats.rb                        Collector, Stats snapshot, merge, summary
  result.rb                       Result (Data)
  executor/inline.rb              Executor seam
  testing.rb                      Testing.run, MemorySink, Testing::Result
  cli.rb                          Minimal CLI
exe/metacrunch
```

Files under `lib/` are allowed to grow or split during implementation if a
unit gets too large; the module boundaries above stay.

### 7.3 Lint

- `Gemfile` (development): `gem "rubocop-ubpb", github: "ubpb/rubocop-ubpb",
  branch: "v2", require: false`. The `branch:` option is removed once
  rubocop-ubpb 2.0.0 is merged.
- `.rubocop.yml`:

  ```yaml
  inherit_gem:
    rubocop-ubpb: ruby.yml

  Style/FrozenStringLiteralComment:
    Enabled: true
  ```

- RuboCop runs locally (`rake`) and in CI.

### 7.4 Rake

`Rakefile`: `test` (Minitest), `rubocop`; `default` runs both.

## 8. Tests

Minitest, matching the other UB Paderborn projects and the minitest cops in
rubocop-ubpb.

- `test/unit/` – one test file per class, `Minitest::Test`.
- `test/integration/` – whole jobs through `Metacrunch::Testing`, with
  fixture jobs in `test/fixtures/jobs/`.
- `test/cli/` – runs `exe/metacrunch` with `Open3` and checks exit code,
  stdout and stderr separately.
- SimpleCov with branch coverage. Minimum 95 % lines and 90 % branches; the
  suite fails below that. CLI subprocess runs do not count towards coverage.
- Tests run with `-W:deprecated` to see deprecation warnings early.

Cases that must be covered (besides the normal behaviour of each unit):

1. Contract violations: `map` returns `nil`; `flat_map` returns a non-
   Enumerable and a `Hash`.
2. `filter`/`reject` with and without reason: rejected vs. filtered counts,
   `rejects` sink content.
3. `ctx.reject!` stops the chain; later steps are not called.
4. `flat_map` copies the context; a rejected child does not affect siblings.
5. Context arity: block with one and two parameters, callable object, class
   with `self.call`, lambda.
6. Sink `batch:`: full batches, rest flushed before `close`, fallback to
   `write`, `write_batch(records, ctxs)`.
7. `close` runs after an abort and after an `Interrupt`.
8. `on_error :abort`, `:skip`, `:skip` with `max_errors` exceeded; failures
   reach the `errors` sink; `StepError` carries step, id, position, cause.
9. Errors in source, sink, `open`, `close`, hooks always abort.
10. Stats: per-step counts, per-reason counts, `profile`, `merge`, status.
11. Parameter precedence CLI > ENV > default, type conversion, required,
    `args` min/max, unknown option, reserved names.
12. Describe mode: `--help` builds no source, step or sink.
13. Loader: one job, several jobs with and without `name:`, no job, the file
    is loaded without side effects.
14. CLI exit codes 0, 1, 2, 3 and 130; output on the right stream.
15. A second `sink` raises `ArgumentError`; a missing `source` raises.

## 9. CI

GitHub Actions replaces CircleCI.

- `.github/workflows/ci.yml`:
  - `test` job: matrix Ruby `4.0` and `head` (`head` may fail) on
    `ubuntu-latest` and `macos-latest`. macOS is included because `fork`
    behaves differently there (relevant for sub-project 5) and it is the
    development platform. Runs `bundle exec rake test`.
  - `lint` job: Ruby 4.0 on Ubuntu, `bundle exec rubocop`.
  - `ruby/setup-ruby` with `bundler-cache: true`. Actions pinned to commit
    SHAs.
- Dependabot for `bundler` and `github-actions`.
- Removed: `.circleci/`, `.rspec`, `spec/`, CodeClimate badges and reporter
  (the service is discontinued), `rspec_junit_formatter`, `simplecov 0.17.1`
  pin.

## 10. Documentation

- New `Readme.md` for 5.0: concepts (record, source, steps, sink, context),
  DSL, parameters, error policy, testing jobs, CLI. Written at the end of
  sub-project 1.
- New `CHANGELOG.md` with the breaking changes from 4.x.

## 11. Decisions recorded for later sub-projects

- **Parallelism (5).** Measured on Ruby 4.0.7 (arm64 macOS, 8 workers): Ractor
  is still experimental, Nokogiri raises `Ractor::UnsafeError` outside the
  main Ractor (Ox, Oj, JSON work). With ~28 µs of work per record, fork
  workers with Marshal and batches of 100 reached about 5× the sequential
  throughput, Ractors about 1.5×. With very cheap steps, any transfer between
  workers is slower than sequential. Plan: fork executor first, Ractors
  behind the same seam as an experimental option.
- **Pipes (2).** JSON Lines is the format between jobs; `-` means stdin/stdout;
  `Errno::EPIPE` ends a job quietly.
- **Declarative jobs (3/4).** One internal pipeline model, two front ends
  (Ruby DSL, YAML/TOML). Open: YAML (standard library) or TOML (gem); Fix
  syntax compatible with Metafacture/Catmandu Fix or not.
- **`map_batch`.** Add only for a concrete bulk-lookup use case. It would
  batch internally, return an array of equal length and keep per-record
  contexts.
