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

Any object with `#each` that yields records. Optional `#open(context)` and `#close`. A source that yields several
values at once (`yield key, value`) produces Array records (`[key, value]`).

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
| `ctx.reject!(reason, value: nil)` | Stop this record; it goes to the `rejects` sink |
| `ctx.mark(reason, value: nil)`, `ctx.marks` | Non-fatal notes; the record continues |
| `ctx.store` | Hash for per-record data shared between steps |
| `ctx.logger` | Logger that prefixes messages with the record id |

`flat_map` gives every emitted record its own copy of the context.

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
`--index`), and names that would hide a method of `params` (`to_h`, `hash`, ...) are not allowed.

## Running jobs

```
$ metacrunch [-h|-v] JOB_FILE [--job NAME] [JOB_PARAMS...] [ARGS...]
$ metacrunch jobs/marc2es.rb --help
```

`--job NAME` selects a job if the file defines several. Use `--` before arguments that start with `-`.
The CLI does not change the working directory: relative paths are relative to where you start it.

| Exit code | Meaning |
|---|---|
| 0 | ok |
| 1 | aborted |
| 2 | usage error (job file, parameters) |
| 3 | finished, but records failed (`on_error :skip`) |
| 130 | interrupted (`exe/metacrunch` ends by SIGINT, so shells and `xargs` see the interruption) |

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

## License

metacrunch is available under the [MIT license](License.txt).
