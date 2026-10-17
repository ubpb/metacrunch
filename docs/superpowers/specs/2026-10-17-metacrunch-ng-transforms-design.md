# metacrunch-ng, sub-project 8: transforms

- Date: 2026-10-17
- Branch: `metacrunch-ng-transforms` (from `metacrunch-ng` at 1ebc426)
- Status: approved design, not implemented
- Builds on: [sub-project 1 spec](2026-10-10-metacrunch-ng-core-design.md)
  (jobs, steps, parameters), [sub-project 6 spec](2026-10-11-metacrunch-ng-credentials-design.md)
  (credentials), [sub-project 7 spec](2026-10-13-metacrunch-ng-commands-design.md)
  (names, projects, `invoke`)

## 1. Context

A job reads records from a source, passes them through steps and writes them
to a sink. Today two kinds of reuse are possible:

- **Unix pipes** chain whole jobs (`metacrunch run a | metacrunch run b`).
  Every stage is a process of its own, so only records cross the boundary:
  ids, marks and rejections are lost, each stage has its own stats, rejects
  sink, exit status and workers, and every record is encoded to JSON and
  decoded again. Records between the stages must be JSON.
- **Ruby** shares step classes and procs between jobs. They have no name in
  the project, no parameters of their own, and cannot run or be tested alone
  as a unit of several steps.

Two needs are not covered. A data flow with several stages (clean the
export, then map it to the target format) is run as separate jobs with an
intermediate file. And the same group of steps (normalize titles, drop
records without an id) is repeated in several jobs that write to different
sinks.

This sub-project adds **transforms**: named recipes that hold only steps,
with parameters of their own. A job inserts a transform's steps at any point
with `use`. A transform has no source and no sink; the job that uses it
decides where records come from, where they go and how errors are handled.

Rejected alternatives:

- **`use` takes any job and ignores its source, sinks and error policy.**
  Existing stages would compose without changes, but a job such as
  `marc2json` must still get the parameters of its source (`args :files,
  min: 1`), which is then ignored, and the rules of what is ignored are
  hidden behavior.
- **`use` takes any job without source and sink (no new kind).** Less to
  learn, but the intent is invisible: a source added later breaks a distant
  job instead of the transform itself, and a job that sets its own
  `on_error` could not be used.
- **A separate `Metacrunch.pipeline` kind** that lists jobs: it needs a
  source, sinks, parameters, an error policy, `trace`, `check` and tests, so
  it is a job; the class name `Metacrunch::Pipeline` is also taken by the
  internal description of a run.
- **Names:** `steps` (plural) describes the content exactly, but a
  declaration is one thing: the class, `--help`, error messages, a gem
  constant and counting ("3 steps") all need a second word ("step group"),
  and "step" already names the single `map` or `filter` throughout stats,
  `trace`, `ctx.step` and workers. `module` clashes with Ruby's `Module`.
  `transform` is a countable singular like `job` and `command`, and names the
  purpose. Vector calls the same thing a transform.

Comparable tools separate transformation from I/O in the same way: Catmandu
Fix files hold only transformations and `include` other Fix files, while
importers and exporters are separate; Metafacture keeps Fix/Morph apart from
the Flux that wires I/O. Traject mixes reader settings and indexing steps in
its configuration files.

### 1.1 Goals

1. Transformation logic can be written once, as a named transform with
   parameters, and used by several jobs with different values.
2. A job can be assembled from several transforms and steps of its own, in
   one process: one context per record, one rejects and errors sink, one
   error policy, one stats summary, one exit status, one pool of workers,
   and no JSON between the transforms.
3. A transform runs, traces, checks and tests alone, like a job without
   source and sink.
4. Nothing is declared that is not used: a transform has only steps, hooks
   and parameters.
5. Gems can ship transforms that a project opts into, like jobs and
   commands.

### 1.2 Non-goals

- Using jobs or commands as parts of a job.
- Transforms with their own sinks, error policy or source.
- Renaming a transform's prefix at `use` (`as:`); 3.5 numbers duplicates.
- `metacrunch new --transform`.
- A Hash form of `invoke`.
- Totals per transform in the stats summary.
- Loading only the file that defines a name (lazy lookup).

### 1.3 Success criteria

1. In a temporary project, a transform with a parameter is used by two jobs
   with different values. Both run by name; their stats name the
   transform's steps with its prefix; `metacrunch --help` lists the
   transform under "Transforms".
2. The transform runs alone (`metacrunch run NAME < in.jsonl`), and `trace`
   and `check` take it.
3. A job that uses two transforms gives the same records, rejects and stats
   with `-w 2` as without workers.
4. A transform that declares a source, `use` of a job, an unknown value key,
   a missing required value and a cycle each fail with a message that names
   the transform; missing values and unknown names end with exit status 2.
5. `--help` of a job run by path does not evaluate `use` and does not load
   the `Metacrunchfile` (checked with a `Metacrunchfile` that raises).
6. A transform parameter with `credential:` reads the job's credentials,
   and `-e production` reaches it.
7. The engine keeps its cost (about 64 ns per step and record). `bundle
   exec rake` passes (coverage at least 95 % lines and 90 % branches,
   RuboCop).

### 1.4 Decisions

| Question | Decision |
|---|---|
| Unit of reuse | A new kind, `Metacrunch.transform`, with steps, hooks and parameters only |
| Name | `transform` (singular); the job statement is `use` |
| What a job takes from a transform | Steps and `before`/`after` hooks, at the position of `use` |
| Parameters at `use` | Keywords with Ruby values; `nil` means not given; then `env:`, credentials, default |
| Credentials | The store of the job being built; no anchor of its own |
| Targets | Name (project), path, or a `Transform` object; jobs and commands are refused |
| Step names | Prefix with the transform's name (`normalize/map#1`); numbers count statements, `use` as one |
| Alone | Runs like a job without source and sink: `run`, `check`, `trace`, `invoke`, `Testing.run` |
| Engine | Unchanged; a pipeline stays a flat list of steps |

## 2. Transforms

### 2.1 Declaration

```ruby
# transforms/normalize.rb
Metacrunch.transform "normalize", desc: "Trim strings, drop records without a title" do
  params do
    param :lang, String, default: "de", desc: "Language of the stopword list"
  end

  before { @stopwords = Stopwords.load(params.lang) }
  map { Normalize.call(it, stopwords: @stopwords) }
  reject("No title") { it["title"].nil? }
end
```

`Metacrunch.transform(name = nil, desc: nil, &recipe)` returns a
`Metacrunch::Transform` and registers it with the loader, like
`Metacrunch.job`. The name follows the rules for names (sub-project 7, 2.1)
and is optional: a transform without a name is used by path or as an
object. `desc:` is one line for the lists of `--help`.

`Metacrunch.load_transform(path, name: nil)` loads a transform from a file,
like `Metacrunch.load_job`.

### 2.2 Contents

A transform's recipe may contain:

- `params { ... }`, as the first statement, as in jobs;
- `map`, `filter`, `reject`, `flat_map`, with the same arguments as in jobs;
- `before` and `after`;
- `use`, for other transforms (3.6).

`source`, `sink`, `rejects`, `errors`, `on_error` and `profile` raise
`ArgumentError` when the recipe is evaluated: "transform normalize: a
transform has no source; the job that uses it decides". The message names
the statement.

### 2.3 Running alone

A transform runs like a job without source and sink: it reads JSON Lines
from stdin and writes JSON Lines to stdout, and all job options apply (`-i`,
`-o`, `--rejects`, `--errors`, `-n`, `--on-error`, `--max-errors`, `-w`,
`--stats`, `--progress`). Its parameters are bound from the command line,
`env:`, credentials and defaults, as for a job.

```
$ metacrunch run normalize --lang en < data/titles.jsonl
$ metacrunch trace -n 3 -i data/titles.jsonl normalize
$ metacrunch check normalize
$ metacrunch normalize --help
```

`invoke "normalize", "--lang", "en"` in a command runs it like a job. A
transform has no `run` method in Ruby, since it has no source; it runs in
Ruby through a job or `Testing.run` (7).

### 2.4 Projects and gems

Transforms share the namespace of jobs and commands: reserved names,
duplicate names and load errors work as for them. A project loads transform
files with `load_files` (the kind comes from the declaration); the
convention is a directory `transforms/`:

```ruby
# Metacrunchfile
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

A gem ships transform files and a constant with their glob, next to `JOBS`
and `COMMANDS`:

```ruby
module Metacrunch
  module Marcxml
    TRANSFORMS = File.expand_path("marcxml/transforms/*.rb", __dir__)
  end
end
```

## 3. `use`

```ruby
# jobs/marc2es.rb
Metacrunch.job "marc2es", desc: "MARCXML into the search index" do
  params do
    param :index, String, required: true
    param :lang, String
    args :files, min: 1
  end

  source MarcReader.new(params.files), id: ->(record) { record["001"] }
  use "marc:to-json", holdings: true
  use "normalize", lang: params.lang
  map { it.merge("indexed_at" => Time.now.utc.iso8601) }
  sink EsSink.new(index: params.index), batch: 1000
end
```

### 3.1 Targets

`use TARGET, **values` takes:

- a **name**, resolved in the project as `invoke` resolves it (sub-project
  7, 5.1): the project of the call, found upward from the working directory
  when the job runs by path, and loaded when the first name needs it;
- a **path** (an argument with `/` or `.`), relative to the working
  directory as for `invoke`; the Readme recommends
  `File.join(__dir__, "normalize.rb")`;
- a **`Metacrunch::Transform`** object, for Ruby code and single files:

  ```ruby
  normalize = Metacrunch.transform("normalize") { map { Normalize.call(it) } }

  Metacrunch.job "titles" do
    source TitleSource.new
    use normalize
  end
  ```

A job or command, given as object or as a name or path that resolves to
one, raises `ArgumentError`: "use takes transforms; marc2es is a job". An
unknown name raises `ProjectError` with the message and hints of `invoke`
("unknown job, transform, command or file: x (no Metacrunchfile found)").
A target that is neither a String nor a `Transform` (`nil`, a Symbol)
raises `ArgumentError`.

### 3.2 Values

- Keys are Symbols that name a `param` or the `args` of the transform. An
  unknown key raises `ArgumentError`: "use normalize: unknown parameter
  :lnag (known: lang)".
- A value may have the declared type (`Integer`, `Float`, `true`/`false`,
  `Array`) or be a String, which is converted as on the command line. The
  `args` take an Array.
- `nil` means "not given", so a job can pass an optional value of its own:
  `use "normalize", lang: params.lang`.
- A parameter without a value is read from its `env:` variable, then from
  the credentials (3.3), then its default. A required parameter without a
  value, `args` outside `min`/`max` and an invalid value raise `ParamError`
  with the prefix of the transform. Since the values come from keywords,
  these messages name a parameter as keyword, not as option: "use
  normalize: missing required parameter api_key: (LOOKUP_API_KEY unset;
  lookup.api_key not in .metacrunch/credentials.yml.enc)".
- Bound values are frozen, and secret values are hidden in messages and
  `inspect`, as for jobs. A value given at `use` comes from code, not from
  the command line, so it gives no warning.

### 3.3 Environment and credentials

The environment is the one the job is bound with (`ENV`, `env:` of
`Job#run`, none in `Testing.run`, see 5). The credentials are the store of
the job being built: searched from the project root for a job run by name,
from the job's file for a job run by path, with `-e` and `--credentials`
applied, decrypted at most once and only if a value is needed. A transform
never searches credentials from its own file, so one run never mixes two
credentials files, and transforms from gems use the project's credentials.

### 3.4 What `use` takes over

`use` evaluates the transform's recipe with a builder of its own in
transform mode, then inserts into the job, at the position of `use`:

- the transform's steps, in their order;
- its `before` and `after` hooks. All hooks of a job run in the order of
  their statements, `use` included; `after` hooks get the job's `Result`.

The transform's steps and hooks see the transform's own `params`, never the
job's, and the job's `logger`. Each `use` evaluates the recipe again, so two
uses with different values are independent.

### 3.5 Step names

- A transform's steps get its name as prefix: `normalize/map#1`,
  `normalize/reject#2` (the part after `/` is the step's name inside the
  transform, generated or given with `name:`). A transform without a name uses the base name of its file
  without `.rb`; an object without name and file uses `transform`.
- The number in a generated step name (`map#3`) is the position of the step
  statement in its recipe, where `use` counts as one statement. A job with
  `map`, `use "normalize"`, `map` has the steps `map#1`, `normalize/map#1`,
  `normalize/reject#2`, `map#3`. Without `use` the names are the same as
  today; with `use`, a transform that gains a step does not rename the
  job's steps.
- A prefix that the recipe already used gets a number: the second
  `use "normalize"` gives `normalize#2/map#1`.
- Nested transforms give nested prefixes: `outer/inner/map#1`.
- An explicit step name (`name:`) must not contain `/`; it raises
  `ArgumentError`.

Stats, `profile`, `ctx.step`, `StepError` messages, `ContextWriter` output,
`trace` and the `steps` line of `check` show the names with prefix.

### 3.6 Nesting and cycles

A transform may `use` other transforms, resolved in the same context (3.1,
3.3). The builder keeps the stack of transforms being evaluated; a transform
that is already on it raises `ArgumentError`: "use cycle: normalize →
titles → normalize".

### 3.7 Errors

| Situation | Error | `run` | `check` |
|---|---|---|---|
| Forbidden statement in a transform (2.2) | `ArgumentError` | 1 | 2 |
| `use` of a job or command, a wrong target, an unknown key, a cycle | `ArgumentError` | 1 | 2 |
| Unknown name, no project for a name | `ProjectError` | 2 | 2 |
| Missing or invalid value | `ParamError` ("use normalize: …") | 2 | 2 |
| Any other exception in a transform's recipe | unchanged | 1 | 2 |

An exception from a transform's recipe passes unchanged otherwise; its
backtrace shows the transform's file. In a command, `invoke` wraps the
`ProjectError` and `ParamError` of an invoked job as it does today.

## 4. When recipes are evaluated

| Call | The job's recipe | `use` |
|---|---|---|
| `--help`, `help NAME` | up to its first statement | not evaluated; no project lookup for it |
| `check` | whole | evaluated; nothing opened, no hook runs |
| `run`, `invoke`, `Job#run`, `Testing.run` | whole | evaluated |
| `trace` | whole | evaluated; hooks of job and transforms are dropped, sinks replaced |

A transform's recipe follows the rule of "What runs when": it only
declares. Its constructors run once per `use` and evaluation; lookup tables
belong into its `before` hooks, which run in the main process before the
workers start, so the workers inherit them.

## 5. Context per caller

| Caller | Project for names | Environment | Credentials |
|---|---|---|---|
| `metacrunch run`/`check`/`trace` (name or path) | from the working directory, loaded when the first name needs it | `ENV` | the job's store |
| `invoke` in a command, `Project#invoke` | the project of the call | as the call | the job's store |
| `Job#run` | `project:` (new), else from `Dir.pwd` when needed | `env:` | the job's store |
| `Testing.run` | `project:` (new), else from `Dir.pwd` when needed | none | none; values come from `use` and defaults |

A job run by path that uses a name now loads the `Metacrunchfile`, as a
command run by path that invokes a name does today; its load warnings appear
then. A job that uses only paths and objects never loads it.

## 6. Command line

- `run`, `check`, `trace` and `invoke` take transforms by name or path; `-j`
  selects a job, transform or command in a file that declares several.
- `check` titles a transform `transform "normalize" OK` and shows `input
  stdin (JSON Lines)`, `output stdout (JSON Lines)`.
- `metacrunch --help` lists the project's transforms in a section of their
  own, between jobs and commands:

  ```
  Jobs (/srv/catalog):
    marc2es          MARCXML into the search index
  Transforms (/srv/catalog):
    marc:to-json     MARCXML string into a JSON record
    normalize        Trim strings, drop records without a title
  Project commands (/srv/catalog):
    catalog:reindex  Load an export into a new index and switch the alias
  ```

- Messages that list kinds name transforms too, for `use`, `invoke` and the
  CLI alike ("unknown job, transform, command or file: x", "no job,
  transform, command or file given").
- No new exit status.

## 7. Ruby API and testing

```ruby
job = Metacrunch.load_job("jobs/marc2es.rb")
job.run(["--index", "test", "dumps/a.xml"], project: Metacrunch.load_project)

normalize = Metacrunch.load_transform("transforms/normalize.rb")
```

```ruby
PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

result = Metacrunch::Testing.run(PROJECT.fetch("normalize"), params: {lang: "en"},
                                 source: [{"title" => " A "}, {"title" => nil}])
result.records                            # [{"title" => "A"}]
result.stats.steps.keys                   # ["map#1", "reject#2"]

result = Metacrunch::Testing.run(PROJECT.fetch("marc2es"), params: {index: "test", files: ["unused"]},
                                 source: [File.read("test/fixtures/record.xml")], project: PROJECT)
result.stats.steps.keys                   # ["normalize/map#1", ...]
```

- `Job#run(argv, ..., project: nil)`: names in `use` resolve in `project`,
  else in the project of the nearest `Metacrunchfile` above `Dir.pwd`,
  loaded when the first name needs it.
- `Testing.run(job_or_transform, ..., project: nil)`: names resolve as for
  `Job#run`. A transform needs `source:` ("a transform has no source; pass
  source:"). Values of transforms come from `use` and their defaults; the
  environment and credentials are never read, as for the job's own
  parameters.
- The steps of a transform run alone are named without prefix (`map#1`);
  inside a job they carry it.

## 8. Architecture

| Unit | Responsibility |
|---|---|
| `Metacrunch::Transform` (new) | The recipe: `name`, `desc`, `file`, `describe`, evaluation in transform mode (alone: a pipeline without source and sink; through `use`: steps and hooks) |
| `Builder` | Transform mode (2.2); `use` (3.4); step numbering by statement, prefixes, `/` refused in explicit names (3.5); the stack for cycles (3.6) |
| `Metacrunch::UseContext` (new) | What `use` needs from the caller (5): the project (lazy), the environment, the job's credentials store, the logger; resolves targets (3.1) and binds values (3.2) |
| `Params` | Binding from a Hash with `nil` as not given and `env:`/credentials/default for the rest; `bind_hash` for tests stays |
| `Loader` | Kind `Transform`; `-j` across jobs, transforms and commands |
| `Project` | Transforms as declarations |
| `Invoker` | Resolves, runs and invokes transforms like jobs; builds the use context from its environment and credentials options |
| `Job` | `run(project:)`; passes the use context to the builder |
| `Metacrunch` | `transform`, `load_transform` |
| `Cli` | Help section (6); `run`/`check`/`trace` with transforms; the `check` title |
| `Testing` | `run` with `project:` and transforms (7) |

`Transform` is not a subclass of `Job`: `is_a?(Job)` decides in the
`Invoker`, the CLI, the help lists and `load_job`, and a transform must not
pass for a job there. The few places learn `Transform` explicitly. The
engine, processor, executors, stats collector and `trace` do not change:
step names are opaque keys to them. No new dependency.

## 9. Exit codes

No new codes. Unknown names and missing or invalid values of a transform end
with 2, like the job's own; other errors in recipes as today (3.7).

## 10. Tests

### 10.1 Unit tests

- `Transform`/`Builder`: the forbidden statements with their messages;
  `params` first; `describe` stops at the first statement.
- `use`: names, paths and objects; a job or command as target; unknown
  names with and without project; other targets.
- Values: declared types and Strings, `args`, unknown keys, `nil` as not
  given, `env:`, credentials from the job's store with `-e`, defaults,
  required and `min`, frozen values, hidden secrets.
- Step names: prefixes, numbering by statement, duplicates (`#2`), nested
  prefixes, unnamed transforms, `/` in explicit names.
- Hooks in statement order; a transform's steps see its own `params`.
- Nesting, cycles.
- `Job#run` and `Testing.run` with `project:` and from `Dir.pwd`;
  `Testing.run` of a transform with and without `source:`.
- `Loader`, `Project`: the kind, `-j`, duplicates across the three kinds.

### 10.2 Command tests

Through `Cli` with injected streams: `run`, `check` and `trace` of a
transform; `check` of a job with transforms (prefixed steps); the help list
with "Transforms"; a job by path whose `--help` does not load a
`Metacrunchfile` that raises, while running it loads the project; the
messages and exit statuses of 3.7.

### 10.3 End to end

Through `exe/metacrunch` in a temporary project: a job with two transforms,
inline and with `-w 2`, gives the same output, rejects file and `--stats`;
a transform run alone through stdin.

## 11. Documentation and example

- Readme, new section "Transforms" after "Steps": declaration, contents,
  `use` with values, step names, running and testing a transform alone, and
  when to prefer a transform over a Unix pipe (context, one rejects sink, no
  JSON in between) and over plain Ruby step classes (parameters, names,
  standalone runs).
- Readme, "Projects and commands": transforms in the `Metacrunchfile`, the
  help list, a job by path that uses names loads the `Metacrunchfile`
  (corrects "Runs by path … never load it").
- Readme, "Jobs and commands from gems": `TRANSFORMS` and
  `transforms/`.
- Readme, "What runs when" and "Testing jobs": `use`, `project:`.
- CHANGELOG: transforms, `use`, `load_transform`, `project:` for `Job#run`
  and `Testing.run`, step numbers by statement, `/` reserved in step names.
- `examples/project/`: a transform `catalog:public` with a parameter takes
  over the steps of the job `catalog`; a second job uses it with another
  value; the test runs the transform alone and the job with `project:`.
  `examples/Readme.md` lists it.

## 12. Deferred

- `metacrunch new --transform`.
- Renaming a prefix at `use` (`as:`).
- Totals per transform in the stats summary.
- Lazy lookup of a name by file name.
