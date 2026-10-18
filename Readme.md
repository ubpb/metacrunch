metacrunch
==========

[![CI](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml/badge.svg)](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml)

metacrunch is a small data processing and ETL (extract, transform, load) toolkit for Ruby. A job reads records
from a **source**, passes them through **steps** and writes the results to a **sink**. It is used for library metadata,
for example to turn MARCXML records into JSON for a search index, but nothing in it is specific to library data.

- Jobs are plain Ruby files. Steps, sources and sinks are blocks or small Ruby classes; there is no second language.
- Steps say what they do: `map`, `filter`, `reject`, `flat_map`.
- Transforms are named groups of steps with parameters of their own; jobs share them with `use`.
- Rejected records keep their reason. The engine counts records per step and reason, and sends rejected and failed
  records with their context to sinks of their own.
- An error policy per job decides whether a failing record stops the run or is skipped.
- Jobs read and write JSON Lines on stdin and stdout, so they chain with each other and with `jq`, `grep` or `sort`.
- `-w N` runs the steps in N processes, with the results in source order.
- `metacrunch trace` shows what each step does to a record; `Metacrunch::Testing` runs a job in a test.
- A project's `Metacrunchfile` names its jobs, transforms and commands; `metacrunch NAME` runs them from any
  directory of the project, and commands chain jobs and other commands.
- One runtime dependency (`logger`).

> metacrunch 5 is a redesign. Jobs written for 4.x must be rewritten, see the [changelog](CHANGELOG.md).

## Installation

metacrunch 5 is not released yet; the latest version on RubyGems is 4.2.1. Until 5.0 is released, use it from Git
with Bundler:

```ruby
# Gemfile
gem "metacrunch", github: "ubpb/metacrunch"
```

```
$ bundle install
$ bundle exec metacrunch --help
```

Requires Ruby 4.0. The commands in this Readme call `metacrunch`; with Bundler, prefix them with `bundle exec`.

The extension gems of 4.x (`metacrunch-file`, `metacrunch-marcxml`, `metacrunch-elasticsearch`, `metacrunch-db`,
`metacrunch-redis`) do not work with metacrunch 5 yet. Until they are ported, JSON Lines is built in (see
[Sources](#sources) and [Sinks](#sinks)), and any other source or sink is a small class of your own, such as
[`examples/lib/json_array_file.rb`](examples/lib/json_array_file.rb).

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

A job can have a name and a one-line description: `Metacrunch.job "marc2es", desc: "MARCXML into the search index"
do ... end`. A name consists of parts of `a-z`, `0-9`, `_` and `-`, separated by `:` (`catalog:reindex`). A file can
define several jobs; `-j NAME` selects one, and a name declared twice in the file cannot be selected until one is
renamed. In a project, jobs run by name (see [Projects and commands](#projects-and-commands)).

More jobs with sample data, from the smallest one to a cleaning job with workers, are in [`examples/`](examples).

## Records

A record can be any Ruby object. Records that leave a job should be `Hash` objects with `String` keys, because
only those survive a JSON round trip. The engine neither copies nor freezes records: a step that emits the same
object several times must not change it in place afterwards.

## Sources

Any object with `#each` that yields records. Optional `#open(context)` and `#close`. A source that yields several
values at once (`yield key, value`) produces Array records (`[key, value]`).

```ruby
source MySource.new(params.files), id: ->(record) { record["_id"] }
```

`id:` gives every record an id for logs and errors.

`Metacrunch::JsonLines::Reader.new(path)` reads JSON Lines (`-` for stdin, `.gz` files are decompressed). A source
can yield `Metacrunch::InvalidRecord.new(raw:, error:)` for a record it cannot read; the reader does so for lines
that are not valid JSON or not valid UTF-8. Invalid records fail like a step (the pseudo-step `source`) under the
job's error policy. Note that JSON objects with duplicate keys count as invalid, and numbers beyond the Float range
(`1e400`) are read as `Infinity`, which the writer refuses.

## Steps

| Step | The block returns | Effect |
|---|---|---|
| `map` | the new record (not `nil`) | 1:1 |
| `filter` | truthy to keep the record | 0..1 |
| `reject` | truthy to drop the record | 0..1 |
| `flat_map` | an Enumerable of records (not a Hash) | 0..n |

A step is a block or any object with `#call`, for example a class with `self.call`. Steps are named
`map#1`, `filter#2`, … or explicitly: `map MarcToJson, name: "marc2json"`.

`filter` and `reject` take an optional reason (a String or Symbol). Records dropped with a reason are *rejected*:
they are counted per reason and sent to the `rejects` sink. Without a reason they are *filtered*: counted, nothing
else.

`flat_map` streams: each record its Enumerable yields goes on through the pipeline right away. If the Enumerable
raises halfway, the records it yielded before are already on their way. Errors from later steps and sinks pass
through the Enumerable's `each`; a `rescue => e` there does not catch them, but a `rescue Exception` would, so do not
use one around `yield`.

```ruby
reject("Patent") { it["type"] == "patent" }
```

## The record context

A step that takes a second **required** parameter gets the record's context:

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
| `ctx.reject!(reason, value: nil)` | Stop this record: ends the step at once; the record goes to the `rejects` sink |
| `ctx.mark(reason, value: nil)`, `ctx.marks` | Non-fatal notes; the record continues |
| `ctx.store` | Hash for per-record data shared between steps |
| `ctx.logger` | Logger that prefixes messages with the record id |

`flat_map` gives every emitted record its own copy of the context.

`reject!` ends the step by raising `Metacrunch::Context::Rejected`, so no `return` or `next` is needed after it. The
engine rescues it around every step. It is an `Exception`, not a `StandardError`: a `rescue => e` in the step does not
catch it, but a `rescue Exception` would, so do not use one around `reject!`. Call `reject!` only on the context the
step got; on the context of another record it fails the step with a `ContractError`.

Optional parameters do not count, so methods such as `method(:Integer)` or `JSON.method(:generate)` can be used as
steps directly: `map(&method(:Integer))`. A step written as `->(record, ctx = nil)` gets `nil` for `ctx`.

## Sinks

Any object with `#write(record)`. Optional `#write_batch(records)`, `#open(context)` and `#close`. Sinks that
accept a second argument get the (read-only) context: `write(record, ctx)`, `write_batch(records, ctxs)`.

```ruby
sink    ElasticsearchSink.new(index: params.index), batch: 1000
rejects JsonLinesFile.new("rejects.jsonl")   # rejected records, ctx.rejection
errors  JsonLinesFile.new("errors.jsonl")    # failed records (on_error :skip), ctx.failure
```

With `batch:` the sink gets `write_batch` calls with up to that many records; the rest is written at the end, also
when the job aborts or is interrupted, so `batch:` never changes which records arrive. One object used as both
`sink` and `rejects` (or `errors`) is opened and closed once.

`Metacrunch::JsonLines::Writer.new(path)` writes JSON Lines (`-` for stdout, `.gz` files are compressed) and refuses
values that are not JSON types. `Metacrunch::JsonLines::ContextWriter` writes every record with its context (id,
position, marks, rejection, failure), which suits the `rejects` and `errors` roles.

## Errors

```ruby
on_error :abort                    # default: stop at the first failing record
on_error :skip, max_errors: 100    # log, send to the errors sink, continue; stop after 100 failures
on_error :skip, max_errors: 0      # stop at the first failure, but after it reached the errors sink
```

Errors in sources, sinks, hooks, `open` and `close` always stop the job. Components are closed in any case.
`NotImplementedError` and other script errors are handled like any other error.

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
  param :api_key, String, env: "CATALOG_API_KEY", credential: "catalog.api_key"
  args  :files, min: 1
end
```

`params` must be the first statement of a job. Values come from the command line, then the environment
variable (`env:`, an empty variable counts as unset), then the credentials (`credential:`, see
[Credentials](#credentials)), then the default. Types: `String`, `Integer`, `Float`, `:bool`, `Array`
(comma-separated). Defaults are converted and checked when declared (`Integer, default: "1000"`
gives 1000). Use the values with `params.index`; they are frozen. Options must be spelled out (`--ind` is not
`--index`), names that would hide a method of `params` (`to_h`, `hash`, ...) are not allowed, and `-h` is reserved
for help.

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
  the order of their statements.
- A path loads the transform of its file. Like every relative path, it is relative to the working directory, so a job
  file that uses a transform next to it writes `use File.join(__dir__, "normalize.rb")`.
- A job file can keep a transform of its own as an object: `trim = Metacrunch.transform { map { ... } }` before the
  job, `use trim` inside it. The file still runs by path without `-j`, since transforms beside a single job or command
  count as its building blocks; leave such a transform unnamed and it takes no name in the project either.
- The keywords of `use` set the transform's parameters, as Ruby values or as strings like on the command line;
  `nil` counts as not given. A parameter without a value comes from its `env:` variable, then from the credentials
  of the job, then its default. The steps and hooks of a transform see its own `params`, never the job's.
- The steps get the transform's name as prefix, `normalize/map#1`, in stats, `trace`, `check`, errors and
  `ctx.step`; a second `use` of the same transform gives `normalize#2/...`. Generated step numbers count the
  statements of a recipe, `use` as one, so a transform that gains a step renames no step of the job. Explicit step
  names must not contain `/`.
- A transform may `use` other transforms; a cycle raises an `ArgumentError`.
- Transforms share their names with jobs and commands, so a transform and a job that runs it with a source of its own
  need two names. Name the transform after what it does and the job after what it produces, for example the transform
  `catalog:public` and the job `catalog`, as in [`examples/project`](examples/project).
- Alone, a transform runs like a job without source and sink: `metacrunch run normalize --lang en < titles.jsonl`,
  `trace` and `check` take it, and `Metacrunch::Testing.run(transform, source: [...])` tests it (see
  [Testing jobs](#testing-jobs)).

Compared with a [pipe](#pipes) between two jobs, the transforms of one job share the context of each record (id,
marks, rejections), one `rejects` and `errors` sink, one error policy, one summary and one exit status, and the
records between them need not be JSON. Compared with step classes in plain Ruby, a transform has parameters and a
name in the project, and runs and tests on its own.

## Credentials

Parameters can read secrets, such as API keys and passwords, from encrypted files in the project:

```ruby
params do
  param :api_key, String, env: "CATALOG_API_KEY", credential: "catalog.api_key", required: true
end
```

```
$ metacrunch credentials edit                    # opens $VISUAL or $EDITOR
$ metacrunch credentials edit -e production
$ metacrunch credentials show -e production
$ metacrunch credentials rotate -e production
```

`edit` creates `.metacrunch/credentials.yml.enc`, which you commit, and the key `.metacrunch/master.key`, which you
never commit (`.metacrunch/.gitignore` excludes it). The file holds YAML: `credential: "catalog.api_key"` reads
`api_key` below `catalog`. Every value is read as its text and converted like a command-line value, so `0123`, `no` or `on` need no
quotes; an empty value, `~` and `null` mean "not set". `edit` refuses to save invalid YAML and, on a terminal, offers
to edit again.

| Environment | File | Key |
|---|---|---|
| none | `.metacrunch/credentials.yml.enc` | `.metacrunch/master.key` |
| `-e production` or `METACRUNCH_ENV=production` | `.metacrunch/credentials.production.yml.enc` | `.metacrunch/master.production.key` |

[`examples/credentials`](examples/credentials) has a runnable example. Each environment has its own file and key, so
laptops and CI need not hold the production key. A run with an
environment never falls back to the file without one.

- **Where:** `--credentials DIR` or `METACRUNCH_CREDENTIALS`, else the nearest `.metacrunch/` above the job file
  (for a job or command run by name: above the project's `Metacrunchfile`), else `~/.metacrunch/` for personal
  credentials. The directory found decides alone; `-v` logs the file that was decrypted. `metacrunch credentials`
  looks above the working directory and uses `~/.metacrunch/` only with `--credentials ~/.metacrunch`.
- **Key:** `METACRUNCH_MASTER_KEY`, else the key file. In containers and CI, set `METACRUNCH_MASTER_KEY`; with Kamal,
  list it under `env: secret:` and provide it in `.kamal/secrets`.
- **Order:** a parameter's value comes from the command line, its `env:` variable, the credentials, then the default,
  so an environment variable overrides a credential. Credentials are decrypted only if a value is needed: a container
  that sets every variable needs neither key nor file. Leave out `env:` to make sure that no inherited variable
  overrides a secret.
- **Secrets:** a parameter with `credential:` is secret. `--help`, error messages and `params.inspect` hide its value,
  and a value on the command line, where `ps` and the shell history show it, gives a warning. What a job does with the
  value, such as logging it or putting it into an exception, is not hidden. `Metacrunch::Testing.run` never reads
  credentials; pass values with `params:`.
- **Rotation:** `rotate` encrypts a file with a new key and replaces the key file, or prints the new key if the old
  one came from `METACRUNCH_MASTER_KEY`. If a `master[.ENV].key.new` is left behind (rotate died between its two
  renames), check first: if `metacrunch credentials show` fails with "wrong key", the `.new` file holds the key of the
  new file, so rename it to `master[.ENV].key`; otherwise delete it. `rotate` refuses to run while it exists.

Keep in mind:

- While the editor runs, `edit` keeps the plaintext in a temporary file (mode 0600 in a directory with mode 0700) and
  removes it afterwards; only SIGKILL leaves it behind. Ctrl-C meanwhile reaches only the editor.
- Editors may keep copies of the plaintext: vim's swap and backup files, VS Code's Local History. Turn them off for
  these files if that matters to you (in vim, for example, `EDITOR="vim -n -c 'set nobackup nowritebackup'"`).
- `.metacrunch/.gitignore` keeps the keys in `.metacrunch/` out of git. A key in a directory given with
  `--credentials` needs an ignore rule of its own.
- The plaintext stays in the memory of every process that uses it, workers included.
- Other processes of the same user can read `METACRUNCH_MASTER_KEY` from a process's environment
  (`/proc/PID/environ` on Linux).
- A lost key cannot be recovered: delete the file and create it again with `edit`.

## Running jobs

```
$ metacrunch run [OPTIONS] NAME|JOB_FILE [JOB_PARAMS...] [ARGS...]
$ metacrunch NAME|JOB_FILE [JOB_PARAMS...] [ARGS...]        # short for run
$ metacrunch run jobs/marc2es.rb --help                     # the job's parameters
$ metacrunch marc2es --help                                 # the same, by name in a project
```

Options of `metacrunch` go before the job; everything after it belongs to the job. Use `--` before job arguments that
start with `-`. A job is given by its file or, in a project, by its name; an argument with `/` or `.` is always a
file. The CLI does not change the working directory: relative paths are relative to where you start it.

| Option | |
|---|---|
| `-j`, `--job NAME` | Select a job, transform or command in a file that declares several |
| `-e`, `--environment NAME` | Credentials environment (default: `METACRUNCH_ENV`) |
| `--credentials DIR` | Credentials directory (default: `METACRUNCH_CREDENTIALS`, then `.metacrunch/` above the job file or, for a name, above the `Metacrunchfile`, then `~/.metacrunch/`) |
| `-i`, `--input PATH` | Read JSON Lines from PATH (`-` for stdin) instead of the job's source |
| `-o`, `--output PATH` | Write JSON Lines to PATH (`-` for stdout) instead of the job's sink |
| `--rejects PATH`, `--errors PATH` | Write rejected or failed records with their context; both may name the same file |
| `-n`, `--limit N` | Process only the first N source records |
| `--on-error abort\|skip`, `--max-errors N` | Override the job's error policy |
| `-w`, `--workers N\|auto` | Run the steps in N worker processes (see Workers) |
| `--stats PATH` | Write status and stats as JSON at the end (`-` for stdout) |
| `--[no-]progress` | Progress on stderr; shown by default if stderr is a terminal and records do not go to the same terminal |
| `-q`, `-v` | Log warnings only, or debug messages too |

The options from `-i` to `--stats` apply to jobs and transforms only; for a command (see
[Projects and commands](#projects-and-commands)) they are a usage error.

A job file that starts with `#!/usr/bin/env metacrunch` and is executable runs as `./jobs/marc2es.rb ...`.

### Pipes

A job without `source` reads JSON Lines from stdin, a job without `sink` writes JSON Lines to stdout. Such jobs chain
with each other and with other tools, and every stage runs in its own process:

```
$ metacrunch run marc2json.rb dumps/*.xml | jq -c 'select(.year > 2000)' | metacrunch run json2es.rb --index test
```

`source id: ->(record) { record["_id"] }` gives a job that reads stdin an id extractor. Only records survive a pipe,
not their context. When the reader of the pipe stops (`| head`), the job flushes and closes its other sinks and ends
quietly by SIGPIPE.

### Workers

`-w N` (`--workers N`) runs the steps in N worker processes; the source and the sinks stay in the main process.
`-w auto` uses one worker per core but one. Records reach the sinks, the `rejects` and `errors` sinks and the log in
source order, so a job gives the same results with and without workers.

```
$ metacrunch run -w 8 jobs/sanitize.rb data/publications.jsonl
```

Workers pay off when the steps are expensive. With about 28 µs of work per record, 8 workers were about 5× as fast.
With cheap steps (a few `map`s over Hashes, about 0.4 µs per record), sending records between processes costs more
than it saves: 8 workers handled 0.5 M records/s, inline 2.8 M records/s.

- Records travel between the processes with `Marshal`. Records, the `value:` of marks and rejections and `ctx.store`
  must be Marshal-able. A source that reads XML should yield Strings and leave the parsing (Nokogiri) to a step. An
  exception that cannot be sent is replaced by a `Metacrunch::WorkerError` with the original class and message.
  Marshal does not keep the frozen state: a frozen source record arrives unfrozen in the steps.
- Workers speed up only the steps. The main process reads the source, sends and receives the records and writes the
  sinks; with cheap steps or many workers it sets the pace. Like XML, JSON Lines are best parsed in a step, in the
  workers: `-i` and `JsonLines::Reader` parse in the main process. With records of about 360 bytes and 4 workers, a
  source that yields the lines, `File.foreach(params.input, chomp: true)`, with `map { JSON.parse(it) }` as the first
  step handled 0.31 M instead of 0.19 M records/s. Such a job takes its file as a parameter, not with `-i`. Its `id:`
  gets the line, not the parsed record (`line["id"]` is just `"id"`), and it does without the reader's handling of
  `.gz` files, blank lines and invalid UTF-8.
- Libraries must be loaded before the workers start: `require` them at job level, not in a step's `open` or `call`
  and not while the source reads. A record of a class that only one of the processes knows stops the run with an
  error that says so.
- Each worker opens and closes the step components itself (`open`/`close`), so every worker has its own
  connections. Data that the workers only read, such as lookup tables, belongs in a `before` hook: the workers
  inherit it from the main process, and `--help` does not build it (see [What runs when](#what-runs-when)). Steps
  are opened after the `before` hooks, also without workers.
- Records are sent in batches of 100, so a slow source (records trickling in through a pipe) delays a record until
  its batch is full. Each process holds a few batches: with records of 1 MB, the main process needs several hundred
  MB more than without workers.
- The source is read in a thread of its own. A source that relies on thread-local state (`Thread.current[...]`,
  e.g. a database connection per thread) or that continues an external enumerator (`Enumerator#next`) begun in
  `open` behaves differently than without workers.
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

### Debugging and checking jobs

```
$ metacrunch trace -n 5 jobs/marc2es.rb --index test dumps/a.xml
$ metacrunch trace --position 4711 jobs/marc2es.rb --index test dumps/a.xml
$ metacrunch check jobs/marc2es.rb --index test dumps/a.xml
$ metacrunch new --test jobs/marc2json.rb
```

`trace` shows what every step does to the first records (or to the records at `--position`, or with `--id`): the
changed keys of Hash records, marks, rejections and failures, and the records a `flat_map` emits. It changes
nothing: all sinks are replaced, and `before` and `after` hooks do not run. `--full` shows whole records.

`check` loads the job, binds its parameters and builds it, without opening, reading or running anything. `new`
creates a filter job that runs right away, and with `--test` a Minitest test for it.

| Exit code | Meaning |
|---|---|
| 0 | ok |
| 1 | aborted |
| 2 | usage error (command, options, job file or name, parameters, `Metacrunchfile`; `check` found the job invalid) |
| 3 | finished, but records failed (`on_error :skip`) |
| 130 | interrupted by Ctrl-C (SIGINT) |
| 141 | stdout was closed by the reader (SIGPIPE) |
| 143 | terminated (SIGTERM) |

After Ctrl-C or SIGTERM the job writes what its sinks have buffered, closes them, and `metacrunch` ends by the
signal, so shells and `xargs` see the interruption. Data already written to stdout is kept.

### Running jobs from Ruby

```ruby
job = Metacrunch.load_job("jobs/marc2es.rb")    # name: "marc2es" selects one of several jobs
result = job.run(["--index", "test", "dumps/a.xml"], workers: 4, limit: 1000)

result.status    # :ok, :ok_with_failures or :aborted
result.error     # the error that aborted the run, or nil
result.summary   # "ok: read 1000, written 998, rejected 2 (Patent: 2) in 0.41s ..."
```

`run` takes the job's parameters as command-line arguments, and the environment for parameters with `env:` as
`env:` (default `ENV`). Credentials follow the same `env:` (`METACRUNCH_ENV`, `METACRUNCH_CREDENTIALS`,
`METACRUNCH_MASTER_KEY`, `HOME`) and are searched from the job's file. Invalid parameters and unreadable credentials
raise `Metacrunch::ParamError`; errors while the job runs end up in the result. A job
defined with `Metacrunch.job` in a Rake task or an application runs the same way. Logs go to `Metacrunch.logger`
(stderr); assign another `Logger` or pass `logger:` to `run`.

Names in `use` resolve in `project:` (`job.run(argv, project: Metacrunch.load_project)`), else in the project of the
nearest `Metacrunchfile` above the working directory, loaded when the first name needs it. That lookup loads the
`Metacrunchfile` again for every run; code that runs jobs again and again loads the project once and passes it.
`Metacrunch.load_transform(path)` loads a transform as `load_job` loads a job.

```ruby
project = Metacrunch.load_project                          # the nearest Metacrunchfile above Dir.pwd
project.names                                              # ["catalog:reindex", "marc2es", ...]
project.invoke("catalog:reindex", "dumps/a.xml")           # like invoke in a command
```

`project.invoke` returns a job's `Result` or a command's value and raises `Metacrunch::InvokeError` as `invoke` does
(see [Projects and commands](#projects-and-commands)). It takes `logger:`, `env:`, `stdin:` and `stdout:`, and for a
job `workers:` and `limit:` as `Job#run` does.

## Projects and commands

A project names its jobs, transforms and commands in a `Metacrunchfile` at its root:

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
$ metacrunch marc2es --index test dumps/a.xml        # from any directory of the project
$ metacrunch catalog:reindex dumps/*.xml
$ metacrunch catalog:reindex --help
$ metacrunch --help                                  # lists the jobs, transforms and commands
```

`metacrunch` finds the nearest `Metacrunchfile` above the working directory and loads it only when a name is needed:
for `metacrunch NAME`, for `run`, `check` and `trace` with a name, for `help NAME` and for `--help`, and when a job
run by path uses a transform by name. The other built-in commands never load it, so job files `require` what they use
themselves. The `Metacrunchfile` is plain Ruby. `Metacrunch.load_files` takes globs relative to the project root, or
absolute ones, and loads each matching file once, in sorted order.

- A file that fails to load costs only its own names: `metacrunch` warns about it (`-v` after `run`, `check` or
  `trace` shows the whole error), and `--help` lists it under "Not loaded".
- Jobs, transforms and commands share one namespace. A name declared twice cannot be used until one is renamed; the
  error names both files, every call that loads the project warns about it, and `Project#duplicates` lists such
  names, so a test of the project can check that there is none (see [Testing commands](#testing-commands)).
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

`invoke NAME, *ARGS, workers:, limit:` runs a job, transform or command with arguments as on the command line; each is
converted with `to_s`, and `nil`, an Array (a forgotten `*`) or a Hash raise `ArgumentError`. An invoked job runs like
`metacrunch run NAME`: it logs its summary as `marc2es: ok: read ...`, reads stdin if it has no source and writes
stdout if it has no sink. All jobs and commands of a chain share `-e`, `--credentials`, the environment, the log
level and the progress setting.

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
| 2 | invalid parameters of the command itself; on the command line also an unknown or duplicate name, or an error in the `Metacrunchfile` |
| 3 | an invoked job ended `:ok_with_failures`, or `:aborted` and the command went on |
| 130, 143 | Ctrl-C, SIGTERM |

`run` takes commands too; the job options (`-i`, `-o`, `-w`, ...) are a usage error for them, and `check` and
`trace` take jobs and transforms only. A command file can also run by path, or as an executable with `#!/usr/bin/env metacrunch`;
when it invokes a name, it finds the project from the working directory.

Names search credentials from the project root (`.metacrunch/` next to the `Metacrunchfile`), also for commands from
gems; a path searches from its file. A job below `jobs/x/` with a `.metacrunch/` of its own therefore uses the
project's credentials by name and its own by path. Nothing changes the working directory: relative paths stay
relative to where `metacrunch` was started, and `root.join(...)` reaches the project's files from anywhere.

### Jobs and commands from gems

A gem ships job, transform and command files like a project's, and a constant with their glob for each kind:

```
metacrunch-elasticsearch/
└── lib/metacrunch/
    ├── elasticsearch.rb                  # the constants; requires the helpers
    └── elasticsearch/
        ├── client.rb                     # helpers: classes and constants go here
        ├── commands/create_index.rb      # Metacrunch.command "es:create-index" do ... end
        ├── transforms/to_bulk.rb         # Metacrunch.transform "es:to-bulk" do ... end
        └── jobs/reindex.rb               # Metacrunch.job "es:reindex" do ... end
```

```ruby
# lib/metacrunch/elasticsearch.rb
require_relative "elasticsearch/client"

module Metacrunch
  module Elasticsearch
    COMMANDS = File.expand_path("elasticsearch/commands/*.rb", __dir__)
    TRANSFORMS = File.expand_path("elasticsearch/transforms/*.rb", __dir__)
    JOBS = File.expand_path("elasticsearch/jobs/*.rb", __dir__)
  end
end
```

A project adds the gem to its `Gemfile` and opts in, next to its own files:

```ruby
# Metacrunchfile
require "metacrunch/elasticsearch"

Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS, Metacrunch::Elasticsearch::JOBS,
                      Metacrunch::Elasticsearch::TRANSFORMS, "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

`bundle exec metacrunch es:create-index ...` then runs a command of the gem, and `bundle exec metacrunch --help` lists
the gem's jobs, transforms and commands with the project's.

- The job, transform and command files define no constants, since every `Metacrunch.load_project` loads them
  again; classes and helpers belong in files that the gem's main file requires.
- The gem does not `require` its job, transform and command files: only `load_files` registers them with the project,
  while a `require` would load them once per process, and a second project in the same process would lack them.
- Names with a prefix (`es:create-index`) keep clear of the project's: a name that the gem and the project both
  declare cannot be used. A reserved name makes the gem's file a load error.
- Credentials are searched from the project root, also for jobs and commands of a gem, so `-e production` works as
  for the project's files. In a command, `root.join(...)` reaches the project's files and `__dir__` the gem's.
- A file of the gem that fails to load costs only its own names, as a file of the project does.

For a gem without such a constant, the glob can start at the gem's directory:

```ruby
gem_dir = Gem::Specification.find_by_name("metacrunch-elasticsearch").gem_dir
Metacrunch.load_files File.join(gem_dir, "lib/metacrunch/elasticsearch/commands/*.rb")
```

The constant is still the better way: the gem can then move its files without breaking projects.

There is no global registry and no `~/.metacrunch` for jobs or commands: under Bundler a global file could not load
gems that the project's Gemfile lacks. Personal tools are executable command files on the `PATH`. For task automation
without records, Rake, Thor or just fit better.

### Testing commands

```ruby
require "metacrunch/testing"

class CatalogTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load_and_every_name_is_unique
    assert_empty PROJECT.load_errors
    assert_empty PROJECT.duplicates
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
real abort, an unknown name fails as in a real run, and credentials are never read. A stub for an unknown name, or a
job's stub that gives no status or `Result`, raises `ArgumentError`, so a mistake in the stubs never passes for a
failing command. `run.status` is `:ok`, `:ok_with_failures`, or `:aborted` with the exception in `run.error`.

[`examples/project`](examples/project) is a runnable project with a test.

## What runs when

| When | What runs |
|---|---|
| A file is loaded: every call that uses it; in a project, every call that needs a name, `--help` included | the file's top-level code: `require`, constants |
| The recipe is evaluated: `run`, `check`, `trace`, `Testing.run`, `Testing.invoke`; for `--help` only up to its first statement | the recipe's code and the arguments of its statements, such as `MySource.new(...)` |
| The job or command runs | `before`, `open`, `each` and `write` of the components, the steps, `after`; a command's `run` block |

`use` evaluates the recipe of a transform while the recipe of the job is evaluated, once per `use`; `--help` of the
job stops before any `use`.

A recipe only declares. Code before `params` and the arguments of the first statement run for every `--help`: a
lookup table built there makes `--help` slow, and a relative path read there breaks `--help` when it is started from
another directory. Preparation such as lookup tables and connections belongs into a `before` hook or a component's
`open`, effects into components or a command's `run` block. Code that must stay in the recipe goes after `params`,
where `--help` does not reach it.

## Testing jobs

```ruby
require "metacrunch/testing"

result = Metacrunch::Testing.run(
  Metacrunch.load_job("jobs/marc2es.rb"),
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

A transform is tested the same way, with `source:`, since it has none. Names in `use` resolve in `project:`, else in
the project of the nearest `Metacrunchfile` above the working directory, which is then loaded for every run; a test
class loads its project once:

```ruby
PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

result = Metacrunch::Testing.run(PROJECT.fetch("normalize"), params: {lang: "en"}, source: [{"title" => " A "}])
result = Metacrunch::Testing.run(PROJECT.fetch("marc2es"), params: {index: "test", files: ["unused"]},
                                 source: [File.read("test/fixtures/record.xml")], project: PROJECT)
result.stats.steps.keys   # ["marc:to-json/map#1", ..., "normalize/map#1", ...]
```

The parameters of transforms get the values of `use` and their defaults; `Testing.run` reads neither the
environment nor credentials.

## License

metacrunch is available under the [MIT license](License.txt).
