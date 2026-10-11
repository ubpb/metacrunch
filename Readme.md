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
`map#1`, `filter#2`, … or explicitly: `map Mab2Primo, name: "mab2primo"`.

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
  args  :files, min: 1
end
```

`params` must be the first statement of a job. Values come from the command line, then the environment
variable (`env:`, an empty variable counts as unset), then the default. Types: `String`, `Integer`, `Float`,
`:bool`, `Array` (comma-separated). Defaults are converted and checked when declared (`Integer, default: "1000"`
gives 1000). Use the values with `params.index`; they are frozen. Options must be spelled out (`--ind` is not
`--index`), names that would hide a method of `params` (`to_h`, `hash`, ...) are not allowed, and `-h` is reserved
for help.

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
| `-w`, `--workers N\|auto` | Run the steps in N worker processes (see Workers) |
| `--stats PATH` | Write status and stats as JSON at the end (`-` for stdout) |
| `--[no-]progress` | Progress on stderr; shown by default if stderr is a terminal and records do not go to the same terminal |
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

### Workers

`-w N` (`--workers N`) runs the steps in N worker processes; the source and the sinks stay in the main process.
`-w auto` uses one worker per core but one. Records reach the sinks, the `rejects` and `errors` sinks and the log in
source order, so a job gives the same results with and without workers.

```
$ metacrunch run -w 8 jobs/sanitize.rb data/ris.json
```

Workers pay off when the steps are expensive. With about 28 µs of work per record, 8 workers were about 5× as fast.
With cheap steps (a few `map`s over Hashes, about 0.4 µs per record), sending records between processes costs more
than it saves: 8 workers handled 0.5 M records/s, inline 2.8 M records/s.

- Records travel between the processes with `Marshal`. Records, the `value:` of marks and rejections and `ctx.store`
  must be Marshal-able. A source that reads XML should yield Strings and leave the parsing (Nokogiri) to a step. An
  exception that cannot be sent is replaced by a `Metacrunch::WorkerError` with the original class and message.
  Marshal does not keep the frozen state: a frozen source record arrives unfrozen in the steps.
- Libraries must be loaded before the workers start: `require` them at job level, not in a step's `open` or `call`
  and not while the source reads. A record of a class that only one of the processes knows stops the run with an
  error that says so.
- Each worker opens and closes the step components itself (`open`/`close`), so every worker has its own
  connections. Data that the workers only read, such as lookup tables, belongs at job level or in a `before` hook:
  the workers inherit it from the main process. Steps are opened after the `before` hooks, also without workers.
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
$ metacrunch trace -n 5 jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch trace --position 4711 jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch check jobs/mab2es.rb --index test dumps/a.xml
$ metacrunch new --test jobs/mab2json.rb
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
| 2 | usage error (command, options, job file, parameters; `check` found the job invalid) |
| 3 | finished, but records failed (`on_error :skip`) |
| 130 | interrupted by Ctrl-C (SIGINT) |
| 141 | stdout was closed by the reader (SIGPIPE) |
| 143 | terminated (SIGTERM) |

After Ctrl-C or SIGTERM the job writes what its sinks have buffered, closes them, and `metacrunch` ends by the
signal, so shells and `xargs` see the interruption. Data already written to stdout is kept.

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
