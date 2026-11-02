# Jobs

A job is a recipe: `Metacrunch.job` declares where records come from, what happens to them and where they go. The
sections below describe each statement:

```ruby
Metacrunch.job "books:export", desc: "Write the public titles" do
  params do                                       # Parameters: first, if any
    param :output, String, required: true
  end

  source Metacrunch::JsonLines::Reader.new(root.join("data/titles.jsonl")), id: ->(record) { record["id"] } # Sources

  reject("Not public") { !it["public"] }          # Steps, in order
  use "normalize"                                 # the steps of a transform
  map { |record| record.slice("id", "title") }

  sink     Metacrunch::JsonLines::Writer.new(params.output)                # Sinks
  rejects  Metacrunch::JsonLines::ContextWriter.new("rejects.jsonl")
  failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")

  on_failure :skip, max_failures: 100             # Failures
  before { logger.info("writing #{params.output}") }                       # Hooks
end
```

Every statement is optional: without `source` a job reads JSON Lines from stdin, without `sink` it writes JSON Lines
to stdout (see [Pipes](cli.md#pipes)). `use` inserts the steps of a [transform](transforms.md). A file may declare
several jobs; the name is optional for a job that runs by path, and `desc:` shows in `--help`.

## Records

A record can be any Ruby object. Records that leave a job should be `Hash` objects with `String` keys, because
only those survive a JSON round trip. The engine neither copies nor freezes records: a step that emits the same
object several times must not change it in place afterwards.

## Sources

Any object with `#each` that yields records. Optional `#open(context)` and `#close`. A source that yields several
values at once (`yield key, value`) produces Array records (`[key, value]`). A source with `#progress` (0.0 to 1.0)
feeds the progress display. A source that reads files is best built on `Metacrunch::Input` (see [Files](files.md)).

```ruby
source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
```

`id:` gives every record an id for logs and errors.

A source that waits for data, such as a queue, can yield `Metacrunch::FLUSH` instead of a record: the records it
yielded before are written at once, also those a sink holds for `batch:` and those in a worker's batch (see
[Workers](workers.md)). `FLUSH` is no record: it has no position and counts toward no limit. Each one costs the sinks a
partial batch, so a source yields it when it waits, not after every record.

A source that waits can have `stop`. On SIGTERM the engine calls it, and the run ends as if the source had ended: the
records read are written and the status is `:ok`, so `metacrunch run` exits with 0. A second SIGTERM stops at once, as
without `stop`. The engine calls `stop` in a signal handler, so it must only set a flag that `each` checks: no I/O, no
logging, no Mutex. Sinks that have `stop` are told as well, so a sink that waits (a queue writer while its queue is
full) gives up instead of holding the run. This holds for runs in the main thread whose program has not trapped
SIGTERM itself, which includes every run of `metacrunch`; a program with its own handler (a job server, a web server)
keeps it. A command that invokes such a job ends by the signal once the job has ended (see
[Projects](projects.md)).

`Metacrunch::JsonLines::Reader.new(targets)` reads JSON Lines from a path, `-` for stdin, an IO or an Array of them;
gzip files are unpacked whatever their names; tar and zip archives when the job asks for them, e.g.
`unpack: [:gzip, :tar]`, on one level (see [Files](files.md)). A gzip, tar or zip file that `unpack:` leaves out
stops the run with an error that names the `unpack:` to pass. A source
can yield `Metacrunch::InvalidRecord.new(raw:, error:)` for a record it cannot read; the reader does so for lines
that are not valid JSON or not valid UTF-8. Invalid records fail like a step (the pseudo-step `source`) under the
job's failure policy. Note that JSON objects with duplicate keys count as invalid, and numbers beyond the Float range
(`1e400`) are read as `Infinity`, which the writer refuses.

## Steps

| Step | The block returns | Effect |
|---|---|---|
| `map` | the new record (not `nil`) | 1:1 |
| `filter` | truthy to keep the record | 0..1 |
| `reject` | truthy to drop the record | 0..1 |
| `flat_map` | an Enumerable of records (not a Hash) | 0..n |

A step is a block or any object with `#call`, for example a class with `self.call`. Steps are named
`map#1`, `filter#2`, … or explicitly: `map TitleCase, name: "titlecase"`.

`filter` and `reject` take an optional reason (a String or Symbol). Records dropped with a reason are *rejected*:
they are counted per reason and sent to the `rejects` sink. Without a reason they are *filtered*: counted, nothing
else.

`flat_map` streams: each record its Enumerable yields goes on through the pipeline right away. If the Enumerable
raises halfway, the records it yielded before are already on their way. Errors from later steps and sinks pass
through the Enumerable's `each`; a `rescue => e` there does not catch them, but a `rescue Exception` would, so do not
use one around `yield`.

```ruby
reject("Not public") { !it["public"] }
```

### Batch steps

A step that calls a service pays for each request: an embedding API, a lookup in a database or a search index.
With `batch: N` a step gets up to N records at once and answers for all of them with one request:

```ruby
map(batch: 500) do |records|
  titles = db[:titles].where(isbn: records.map { it["isbn"] }).to_h { [it[:isbn], it[:title]] }
  records.map { it.merge("title" => titles[it["isbn"]]) }
end
filter("Not relevant", judge, batch: 50)   # judge.call_batch(records) or judge.call_batch(records, ctxs)
```

A block with `batch:` gets the Array of records, and the Array of their contexts if it takes a second required
parameter. Any other object needs `call_batch`; without `batch:` it runs per record with `call`, so an object with
both works either way.

The batch function returns an Array with one result per record, in the same order: what the step returns for one
record (see the table above). The engine then treats each record as in a step without `batch:`: reasons, counts and
marks work as usual.

- An Exception in the results fails its record; the other results stand.
- If the batch function raises, or returns something else than an Array of that length, every record of the batch
  fails with that error.
- `ctx.reject!` would end the call for all records of the batch: in a batch step it breaks the contract (a
  `ContractError`). Drop records with `filter` or `reject` and a reason. `ctx.mark` works.

A batch step keeps the records that reach it until it holds N of them. It also runs on fewer at the end of every
*segment*: after the records of a segment, when the source yields `Metacrunch::FLUSH` (before the sinks flush) and
when the source ends, also by `--limit` or SIGTERM. A segment is 100 source records, or the smallest multiple of the
largest `batch:` of the job that is at least 100; with workers it is the batch a worker gets (see
[Workers](workers.md)). Records a batch step holds when the job aborts are dropped: they are neither written nor
counted as failed.

The sink gets its records in source order. The `rejects` and `failures` sinks and the log get them in the order they
leave the steps: a record that waits in a batch step arrives there after later records that an earlier step rejected.
`max_failures` counts in that order. The order is the same with and without workers. `trace` shows one record at a
time: there, batch steps get batches of one.

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

Any object with `#write(record)`. Optional `#write_batch(records)`, `#open(context)`, `#flush`, `#stop` (see
[Sources](#sources)) and `#close`. Sinks that accept a second argument get the (read-only) context: `write(record,
ctx)`, `write_batch(records, ctxs)`. A sink that writes files is best built on `Metacrunch::Output` (see
[Files](files.md)).

```ruby
sink     Metacrunch::JsonLines::Writer.new(params.output), batch: 1000
rejects  Metacrunch::JsonLines::ContextWriter.new("rejects.jsonl")    # rejected records, ctx.rejection
failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")   # failed records (on_failure :skip), ctx.failure
```

With `batch:` the sink gets `write_batch` calls with up to that many records; the rest is written at the end, also
when the job aborts or is interrupted, so `batch:` never changes which records arrive. When the source yields
`Metacrunch::FLUSH` (see [Sources](#sources)), the buffered records are written at once, and the engine then calls
the sink's `flush`, if it has one, so a sink that buffers itself writes its buffer too: the JSON Lines writers flush
their file or stream. One object used as both `sink` and `rejects` (or `failures`) is opened, flushed, stopped and
closed once.

`Metacrunch::JsonLines::Writer.new(target)` writes JSON Lines to a path (`.gz` is compressed), `-` for stdout or an
IO, and refuses values that are not JSON types. `Metacrunch::JsonLines::ContextWriter` writes every record with its
context (id, position, marks, rejection, failure), which suits the `rejects` and `failures` roles.

### Reporting failed records

A sink that writes some records of a batch but not others (a database refuses a row, a search index a document)
raises `Metacrunch::SinkFailures` after writing the rest. It takes a Hash of indices in the batch to errors; `write`
reports index 0:

```ruby
def write_batch(records)
  failed = {}
  records.each_with_index do |record, index|
    store(record)
  rescue Store::Refused => e
    failed[index] = e
  end
  raise Metacrunch::SinkFailures, failed unless failed.empty?
end
```

These records fail under the pseudo-step `sink` and follow the failure policy like records a step failed for: the job
aborts by default, and with `on_failure :skip` they go to the `failures` sink and count toward `max_failures`.
`stats.written` counts only the records the sink wrote. With `batch:` the failures arrive when the batch is written,
after later records went through the steps. Only the job's sink may report failed records; from the `rejects` or
`failures` sink `SinkFailures` stops the job.

## Failures

A record fails when a step raises for it, which is a failure; an error is an exception. A failure holds its error
(`ctx.failure.error`). The failure policy decides what a failed record does:

```ruby
on_failure :abort                      # default: stop at the first failing record
on_failure :skip, max_failures: 100    # log, send to the failures sink, continue; stop after 100 failures
on_failure :skip, max_failures: 0      # stop at the first failure, but after it reached the failures sink
```

Errors in sources, sinks, hooks, `open` and `close` are no failures of a record: they always stop the job. The
exceptions are records the source yields as `Metacrunch::InvalidRecord` (step `source`) and records the sink reports
with `Metacrunch::SinkFailures` (step `sink`, see [Reporting failed records](#reporting-failed-records)), which are
failures. Components are closed in any case. `NotImplementedError` and other script errors are handled like any other
error.

## Hooks

```ruby
before { logger.info("starting") }
after  { |result| logger.info(result.summary) }
```

`result.status` is `:ok`, `:ok_with_failures` or `:aborted`; `result.stats` has the counts per step and reason;
`result.stopped` is true when SIGTERM stopped the source (see [Sources](#sources)).
`profile true` adds the time per step.

## Parameters

```ruby
params do
  param  :output,  String, required: true, desc: "JSON Lines file for the records"
  param  :input,   String, default: root.join("data/titles.jsonl")
  param  :batch,   Integer, default: 1000
  param  :index,   String, default: "titles"
  param  :dry,     :bool, default: false
  param  :tags,    Array
  param  :es_url,  String, default: {env: "ES_URL"}
  secret :api_key, String, default: {credential: "es.api_key"}
  args   :files, min: 1
end
```

`params` must be the first statement of a job. `param` declares a parameter, `secret` one whose value is hidden (see
[Secrets](#secrets)); both take a type, `default:`, `required:`, `desc:` and `short:`. A value comes from the command
line, then the [params file](#parameter-files) of the run, then the default. Types: `String`, `Integer`, `Float`,
`:bool`, `Array` (comma-separated). Use the values with `params.output`; they are frozen. Options must be spelled out
(`--out` is not `--output`), names that would hide a method of `params` (`to_h`, `hash`, ...) are not allowed, and `-h`
is reserved for help.

A value is text, a list, or a reference that the run resolves when it needs the value:

| Value | Where | Gives |
|---|---|---|
| Text, a list | command line, params file, `default:` of the declaration, `params:` | the value, converted to the type (`"1000"` → 1000, `"no"` → false) |
| `{env: "ES_URL"}` | params file, `default:` of the declaration | the environment variable; an empty one counts as unset |
| `{credential: "es.api_key"}` | params file, `default:` of the declaration | the value in the [credentials](credentials.md) of the run's [environment](environments.md); only for a `secret` |

A reference that finds nothing is an error, also for an optional parameter: `es_url: environment variable ES_URL from
default: is not set`. A value that exists in only some environments belongs into their sections of the params file,
not into the `default:` of the declaration. Plain defaults are converted and checked when declared
(`Integer, default: "1000"` gives 1000), references for their form. `--help` shows where a default comes from, never a
value: `(default: env ES_URL)`, `(secret, default: credential es.api_key)`.

A value from code (`use`, `invoke`, `Job#run`, `Metacrunch::Testing`) is given as `params: {...}`, in the declared
type or as a String; a Pathname counts as its path, and `nil` means not given. A params file never applies to them.
`root` is the root of the project the call runs in (see [Projects](projects.md)), so
`default: root.join("data/titles.jsonl")` works from any directory of the project; `--help` shows it as an absolute
path. Without a project, `root` raises `Metacrunch::ProjectError` "no Metacrunchfile found in DIR or above" when it is
called: on the command line in the recipe or a hook, the run ends with exit status 2; in a step, the record fails. Call
`root` in the recipe or a hook, and keep what a step needs in a local variable.

### Groups of parameters

Parameters that several jobs, transforms and commands share go into a group: a proc with `param`, `secret` and
`args` statements. `use` declares them where it stands, so they show up there in `--help`:

```ruby
# lib/es_params.rb
ES_PARAMS = proc do
  param  :es_url,  String, default: {env: "ES_URL"}, desc: "URL of the Elasticsearch server"
  secret :api_key, String, default: {credential: "es.api_key"}
end
```

```ruby
# jobs/books/export.rb
require_relative "../../lib/es_params"

Metacrunch.job "books:export" do
  params do
    use ES_PARAMS
    param :output, String, required: true
  end

  # params.es_url, params.api_key, params.output
end
```

The group lives in `lib/` and is required, since job files are loaded again and define no constants (see
[Projects](projects.md)). Gems ship groups too, such as `Metacrunch::Elasticsearch::CONNECTION_PARAMS`. A parameter
declared twice is an error, also when two groups declare it. `use` in `params` takes a group; `use` in the recipe
inserts a [transform](transforms.md).

### Secrets

A `secret` is hidden in `--help`, in error messages (`(hidden)`), in `params.inspect`, `to_s` and `pp`
(`api_key=[secret]`) and in the log; `params.to_h` gives the values, since code passes them on. What a job does with a
value, such as logging it, is up to the job.

| Source | Plain value for a secret | Reference |
|---|---|---|
| Command line | allowed, with a warning (`ps` and the shell history show it) | – |
| Params file | error | `{credential: ...}`, `{env: ...}` |
| `default:` of the declaration | error, when declared | `{credential: ...}`, `{env: ...}` |
| `params: {...}` from code | allowed | – |

`{credential: ...}` for a `param` is an error: what is in the credentials is secret. A secret stays hidden where `use`
or `invoke` pass it on only if the target declares the parameter with `secret` too; passing one of its own secret
values unchanged to a `param` of the target fails: `use es-writer: api_key gets a secret, but es-writer declares it as
param; declare it secret there`. The check compares the value itself, so a derived value (`params.api_key.strip`) is
not recognized.

### Parameter files

`--params FILE` gives the values of each [environment](environments.md) in one file, one section per environment:
`default:` for the default environment (no `-e`, no `METACRUNCH_ENV`), `production:` for `-e production`.

```yaml
# config/export.yml
default: &default
  batch: 1000
  index: titles-dev
  tags: [books, nightly]

production:
  <<: *default
  index: titles-prod
  es_url: http://es-prod:9200
  api_key: {credential: es.api_key}
```

```
$ metacrunch run -e production --params config/export.yml export.rb
```

- A run uses exactly the section of its environment, and it must exist: `config/export.yml has no section production
  (sections: default)`. Nothing is inherited; a YAML merge key (`<<: *default`) takes values over where wanted, as in
  Rails' `database.yml`. So the `default:` section holds the values of the default environment, typically development,
  and no development value reaches production by accident.
- Keys are the names of the parameters (`api_key`, not `--api-key`). One file serves the whole
  [project](projects.md): a run takes the keys of its job and leaves the others to the jobs, transforms and commands
  of the project that declare them, also those from gems. A key that none of them declares fails, also in a section
  that is not used, so a typo does not pass. Without a project, every key must name a parameter of the job.
  Positional arguments come from the command line only.
- Values are read as text and converted like command-line values (`0123`, `no` and `on` need no quotes); an `Array`
  parameter also takes a list. `~`, `null` or an empty value means "not given": the default applies.
- Every section is checked on every run: keys, plain values for secrets and `{credential: ...}` for a `param` (for
  the keys of other recipes too: a secret if one of them declares it so), and the plain values of the job's keys.
  References are resolved only for the job's keys, in the section of the run.
- `run`, `check` and `trace` take the file for the job or transform named on the command line, and `run` and `check`
  also for a command; what that target invokes or uses gets its values from code. `metacrunch check -e production
  --params FILE job.rb` checks a file, e.g. in CI, and `-v` logs the file and the section it used.

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
