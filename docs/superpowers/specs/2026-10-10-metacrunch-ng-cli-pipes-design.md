# metacrunch-ng, sub-project 2: CLI and Unix pipes

- Date: 2026-10-10
- Branch: `metacrunch-ng`
- Status: approved; implemented
- Builds on: [sub-project 1 spec](2026-10-10-metacrunch-ng-core-design.md)

## 1. Context

Sub-project 1 built the core (pipeline model, step contract, per-record
context, error policy, stats, Ruby DSL, parameters) and a minimal CLI:
`metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]`. Sub-project 2 replaces that
CLI with subcommands and makes jobs work as stages of Unix pipes.

### 1.1 Goals

Pipes have to support four scenarios:

1. **Chaining jobs.** `mab2json | json2es`: extraction and loading as
   separate jobs; the intermediate stream can be saved as a `.jsonl` file.
2. **Mixing Unix tools.** `jq`, `grep`, `head`, `gzip`, `sort` before,
   between or after jobs.
3. **Parallel stages.** Each stage of a pipe is its own process, so a pipe
   gives CPU parallelism between stages without sub-project 5.
4. **Ad hoc runs and debugging.** Run a job against real data with its
   source or sinks replaced, without editing the job file.

### 1.2 Non-goals

- `fix` subcommand (sub-project 4) and `--workers` (sub-project 5).
- Formats other than JSON Lines (CSV, MARC). They come with the extension
  gems.
- Colors in the progress line, a dashboard per worker (sub-project 5 uses
  the monitor seam of 5.4).
- A configuration file for CLI defaults, shell completion.

### 1.3 Success criteria

1. `metacrunch run a.rb FILE | ruby -ne ... | metacrunch run b.rb` runs end to
   end with fixture jobs (Ruby instead of `jq` as the filter, because CI has
   no `jq`).
2. In `metacrunch run ... | head -n 1`, the metacrunch process ends by
   SIGPIPE (exit status 141) and prints nothing on stderr except its logs.
3. `metacrunch trace --position N` shows the diffs, `flat_map` children,
   marks and failures of that one record.
4. `metacrunch check` exits with 0 for a valid job and 2 for an invalid one.
   `metacrunch new jobs/x.rb` creates a job that runs right away as
   `./jobs/x.rb < in.jsonl`.
5. Without an observer and a monitor, the engine keeps its per-record cost
   from sub-project 1 (about 70 ns per step and record, 4 allocations per
   record). The throughput of a pass-through JSON Lines job is measured and
   recorded in this spec (not a fixed target).
6. `bundle exec rake` passes locally (tests, coverage at least 95 % lines and
   90 % branches, RuboCop), and CI passes.

### 1.4 Decisions

| Question | Decision |
|---|---|
| How jobs reach stdin/stdout | Filter default: a job without `source` reads JSON Lines from stdin, a job without `sink` writes JSON Lines to stdout (as in Catmandu and Benthos). Flags replace the source and sinks for ad hoc runs. |
| Subcommands | `run`, `check`, `trace`, `new`, `help` |
| Where metacrunch options go | Before `JOB_FILE`; everything after it belongs to the job. `metacrunch JOB_FILE` is short for `run`. |
| Options of `run` | `-i`, `-o`, `--rejects`, `--errors`, `--limit`, `--on-error`, `--max-errors`, `--stats`, `--[no-]progress` |
| `trace` output | A diff per step; `--full` for whole records |
| Invalid JSON input line | Fails like a record (`InvalidRecord`), follows the error policy |
| CLI implementation | stdlib `OptionParser` and one small class per command; no new runtime dependency |

## 2. Command line

### 2.1 Grammar

```
metacrunch [--help] [--version]
metacrunch run   [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
metacrunch check [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
metacrunch trace [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]
metacrunch new   [OPTIONS] PATH
metacrunch help  [COMMAND]
metacrunch JOB_FILE [JOB_PARAMS...] [ARGS...]      # short for run
```

The first argument decides:

- A command name selects that command.
- An argument that starts with `-` is a top-level option (`--help`,
  `--version`).
- Anything else is a job file, and the command is `run`. This makes job
  files with a `#!/usr/bin/env metacrunch` line executable. A job file that
  is literally named like a command is started as `./run`.
- If the argument is neither a command nor an existing file, the error is
  `unknown command or job file: NAME` (exit 2).
- No arguments at all: usage on stderr, exit 2.

`help` prints the top-level help; `help COMMAND` is the same as
`COMMAND --help`. Help and `--version` go to stdout.

### 2.2 Options

Each command has its own `OptionParser`. It parses with `order!`, which stops
at the first argument that is not an option: `JOB_FILE`. Everything after
`JOB_FILE` is passed to the job (job parameters, then `args`), so job
parameters may use any name, including `input` or `limit`.

Options of `run`, `check` and `trace`:

| Option | Meaning |
|---|---|
| `-j`, `--job NAME` | Select a job in a file that defines several |
| `-q`, `--quiet` | Log level `WARN`; no progress display |
| `-v`, `--verbose` | Log level `DEBUG` |
| `-h`, `--help` (before `JOB_FILE`) | Help for the command |
| `-h`, `--help` (after `JOB_FILE`) | Parameters of the job, as in sub-project 1 (recognized by the job's own parser) |

Changes compared to sub-project 1:

- The version is `--version` only, at the top level. `-v` means verbose, as
  in git and rsync.
- `--job NAME` moves before `JOB_FILE` (`-j NAME`). Because job parameters
  no longer share the option namespace with `--job`, `job` is no longer a
  reserved parameter name. `help` and `-h` stay reserved.

### 2.3 Exit codes

| Code | Meaning |
|---|---|
| 0 | `:ok`; `check` found the job valid; `trace` finished; `help`, `--version`, `new` |
| 1 | `:aborted`, or an unexpected error |
| 2 | Usage error: unknown command or job file, invalid option, `JobLoadError`, `ParamError`, conflicting stdout use (4.2), stdin is a terminal (4.1); `check` found the job invalid; `new` would overwrite a file |
| 3 | `:ok_with_failures` |
| 130 | Interrupted by Ctrl-C (SIGINT) |
| 141 | stdout closed by the reader (SIGPIPE), see 3.5 |
| 143 | Terminated (SIGTERM) |

For 130, 141 and 143, `Cli#run` returns the code and `exe/metacrunch` ends by
the signal, as in sub-project 1. Measured on Ruby 4.0.7: `raise
SignalException, "PIPE"` ends the process with status 141 and prints nothing.

### 2.4 Structure

- `lib/metacrunch/cli.rb`: `Metacrunch::Cli`, dispatch and exit codes.
  `Cli.new(stdin:, stdout:, stderr:, env:)`; `#run(argv)` returns the exit
  code. The streams are injected, so commands are tested in-process with
  `StringIO`.
- `lib/metacrunch/cli/command.rb`: base class. Logger setup (`-q`/`-v`),
  loading the job (`-j`), job help, the final report, usage errors.
- `lib/metacrunch/cli/job_command.rb`: base class of the commands that take
  a job file (`run`, `check`, `trace`): `-j`, `-q`, `-v`, job help.
- `lib/metacrunch/cli/run.rb`, `check.rb`, `trace.rb`, `new.rb`: one class
  per command (`RunCommand`, `CheckCommand`, `TraceCommand`, `NewCommand`).
- `lib/metacrunch/cli/run_options.rb`: `RunOptions` (4.2).
- `exe/metacrunch` stays as it is.

The commands do not use `Job#run`. They build the pipeline with
`job.pipeline(binder:, logger:)`, apply their options with `Pipeline#with` and
run it with `Engine`, as `Metacrunch::Testing.run` already does.

## 3. JSON Lines

`lib/metacrunch/json_lines.rb` provides a source and two sinks. They are
ordinary components, usable in any job:

```ruby
source  Metacrunch::JsonLines::Reader.new("dump.jsonl.gz")     # "-" = stdin
sink    Metacrunch::JsonLines::Writer.new("out.jsonl")         # "-" = stdout
rejects Metacrunch::JsonLines::ContextWriter.new("bad.jsonl")
```

Each accepts a path, `"-"` (stdin or stdout, resolved when the stream is
opened) or an IO object. An IO given from outside is never closed (the
writer flushes it). The CLI passes its injected streams as IO objects.

### 3.1 Reader

- `each` opens the file, reads it line by line and closes it in an
  `ensure`, so a `break` (e.g. from `--limit`) closes it as well. It needs no
  `open` or `close`.
- Lines are read as UTF-8. Blank lines are skipped and not counted. A
  byte order mark at the start is ignored; `\r\n` line endings and a
  missing final newline are fine.
- A path ending in `.gz` is decompressed with `Zlib::GzipReader` (`zlib` is
  a default gem).
- Each line is parsed with `JSON.parse`, so a record can be any JSON value.
  Objects become Hashes with String keys.
- A line that does not parse is yielded as
  `Metacrunch::InvalidRecord.new(raw: line, error: e)` (3.4). So is a line
  that is not valid UTF-8 (error: `JSON::ParserError`, "invalid UTF-8"):
  json 3.0.2 accepts invalid UTF-8 inside strings, and the writer would
  refuse such a record later.
- `progress` returns the fraction of bytes read (0.0 to 1.0) for files,
  including `.gz` files (position in the compressed file), and `nil` for
  stdin and other IO objects (5.2).

### 3.2 Writer

- `open` opens the file for writing (truncating it) or takes the IO.
  `close` flushes and closes the file; an IO from outside is only flushed.
- A path ending in `.gz` is compressed with `Zlib::GzipWriter`.
- `write(record, ctx)` and `write_batch(records, ctxs)` write
  `JSON.generate(record, strict: true)` and a newline per record. The
  contexts are used for error messages only. The IO buffers; there is no
  flush per record.
- `strict: true` refuses values that are not JSON types (`Object not allowed
  in JSON`, also `Time`, `NaN`, `Infinity`) instead of writing their `to_s`.
  Symbols are written as strings. A refused record is a sink error, so the
  run aborts (sub-project 1, 3.3); the error names the record's position and
  class.

### 3.3 ContextWriter

For the `rejects` and `errors` roles. `write(record, ctx)` (a required second
parameter, so the sink adapter passes the context) writes one envelope per
record:

```json
{"record":{"_id":18,"public":false},"id":18,"position":2,"marks":[],
 "rejection":{"reason":"Not public","step":"reject#1","value":null}}
{"record":"{\"id\": 4711, \"ti","id":null,"position":4711,"marks":[],
 "failure":{"step":"source","error":"JSON::ParserError","message":"unexpected end of input ..."}}
```

- Keys: `record`, `id`, `position`, `marks` (array of `reason`, `step`,
  `value`), then `rejection` (`reason`, `step`, `value`) if the record was
  rejected and `failure` (`step`, `error` = class name, `message`) if it
  failed.
- Robust rather than strict: a record (or a mark or rejection `value`) that
  is not a JSON type is written as its `inspect` string, with
  `"record_class"` added for the record. Otherwise `--rejects` would abort a
  run exactly when diagnostics are needed, e.g. for a MARC object rejected
  before the step that converts it.
- `open`, `close` and `.gz` as for `Writer`.

### 3.4 InvalidRecord

`Metacrunch::InvalidRecord = Data.define(:raw, :error)`. Any source may yield
one instead of raising, to report a record it could not read (later also CSV
or MARC readers). The engine:

- counts it as read;
- creates its context (no `id:` extractor call; `id` is `nil`);
- treats it as a failure of the pseudo-step `"source"`, under the job's
  error policy:
  - `:abort`: a `StepError` with step `"source"`, the position and the
    parse error as `cause`; the run aborts.
  - `:skip`: the failure is logged, `raw` goes to the `errors` sink with
    `ctx.failure.step == "source"`, `max_errors` applies.
- counts it in `Stats#failed` (total and per error class). `Stats#steps`
  gets no `"source"` entry;
- reports it to the observer as the step `"source"`: `step_in` with the raw
  value, `step_out` without outputs.

`"source"` becomes a reserved step name: `map ..., name: "source"` raises
`ArgumentError`.

### 3.5 Closed stdout (EPIPE)

When the reader of a pipe goes away (`| head`), the next write raises
`Errno::EPIPE`. `JsonLines::Writer` and `ContextWriter` turn it into
`SignalException.new("PIPE")`, for any target (a FIFO behaves like stdout),
and remember that the stream is broken: later `write`, `flush` and `close`
calls do not write.

From there the signal path of sub-project 1 applies: the engine flushes the
other sinks (e.g. `--rejects` to a file), closes all components and
re-raises; the CLI logs `interrupted by SIGPIPE` at `DEBUG` only and returns
141; `exe/metacrunch` ends by SIGPIPE.

Sinks written by users keep `Errno::EPIPE` as an ordinary sink error. A
generic rule would also swallow broken socket connections, e.g. to
Elasticsearch, where `EPIPE` is a real failure.

## 4. Running jobs: `run`

```
metacrunch run [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]

  -i, --input PATH|-         replace the source (JsonLines::Reader)
  -o, --output PATH|-        replace the sink (JsonLines::Writer)
      --rejects PATH|-       replace the rejects sink (ContextWriter)
      --errors PATH|-        replace the errors sink (ContextWriter)
  -n, --limit N              process only the first N source records
      --on-error abort|skip  override the error policy
      --max-errors N         override max_errors
      --stats PATH|-         write status and stats as JSON at the end
      --[no-]progress        force the progress display on or off
  -j, -q, -v, -h             see 2.2
```

### 4.1 Filter default

Applied by `run` and `trace` (not by `check`, which only reports it):

- A job without `source` reads JSON Lines from stdin
  (`JsonLines::Reader` on the injected stdin).
- A job without `sink` writes JSON Lines to stdout (`JsonLines::Writer` on the
  injected stdout).
- If the job has no source, no `-i` is given and stdin is a terminal, the
  command fails with exit 2: `job has no source and stdin is a terminal; pipe
  JSON Lines in or use -i PATH`. Without the check it would wait for input.

The library stays explicit: `Builder` now accepts a job without `source`, but
`Engine`, `Job#run` and `Testing.run` (without `source:`) raise
`ArgumentError` for a pipeline without source. A job without sink discards its
records in the library, as in sub-project 1.

DSL addition for filter jobs: `source id: ->(record) { record["_id"] }`
(without an object) declares the id extractor for the default input, so logs
and rejects show ids instead of positions. Declaring `source` twice, with or
without an object, raises `ArgumentError`.

### 4.2 Options and the pipeline

- **Precedence:** an option beats the job's declaration, which beats the
  filter default.
- Replaced components are constructed by the recipe but never opened
  (constructor convention, sub-project 1, 5.2). The job's `id:` extractor is
  kept with `-i`. Replaced sinks have no `batch:`; the writers buffer
  themselves.
- **stdout once.** `-o -`, `--rejects -`, `--errors -`, `--stats -` and the
  filter default (job without sink, no `-o`) must not share stdout; a
  conflict is a usage error (exit 2) such as `stdout is used by both --output
  and --rejects`.
- **Same path, same object.** Options naming the same path share one writer:
  `--rejects bad.jsonl --errors bad.jsonl` writes both roles into one file,
  opened and closed once (sub-project 1, 2.4). The `rejection` or `failure`
  key tells them apart. Paths are compared after `File.expand_path`. Any
  other two of `-i`, `-o`, `--rejects`, `--errors` and `--stats` naming the
  same file are a usage error (`-i x -o x` would truncate the input before
  it is read).
- **`--limit N`** (N ≥ 1): a new `Pipeline` field `limit` (default `nil`).
  `Executor::Inline` leaves the source's `each` with `break` after N
  records, so the source's `ensure` blocks run. The limit counts source
  records, including invalid ones, not `flat_map` outputs. The status stays
  `:ok`: the run did what was asked.
- **`--on-error` and `--max-errors`** override the job's values one by one.
  `--on-error abort` drops a `max_errors` of the job. `--max-errors N` (N ≥
  0) without an effective `:skip` (from the job or from `--on-error skip`) is
  a usage error, like the DSL rule.
- **`--stats PATH|-`** writes, after the run (also after an abort):

  ```json
  {"status": "aborted", "error": {"class": "Metacrunch::StepError", "message": "..."},
   "stats": {"read": 10, "written": 9, "...": "Stats#to_h"}}
  ```

  `error` is `null` without error. After a signal (130, 141, 143) nothing is
  written, because the engine re-raises the signal and produces no `Result`.
  The log on stderr stays as in sub-project 1.

### 4.3 RunOptions

`Cli::RunOptions` (`Data`) holds the parsed options. `#apply(pipeline,
stdin:, stdout:)` returns a new pipeline (`Pipeline#with`) with replaced
source and sinks (wrapped in `SinkAdapter`), the filter default, `limit` and
the error policy, and raises a usage error for the conflicts above. `trace`
uses the input part only (6.1).

Example: what ris2fis does today with `.marked.csv` and `.skipped.csv` files
written by job code:

```
$ metacrunch run --on-error skip --rejects out/bad.jsonl --errors out/bad.jsonl \
    --stats out/stats.json publications.rb data/ris.json > out/fis.jsonl
$ jq -r '.rejection.reason // .failure.error' out/bad.jsonl | sort | uniq -c
```

## 5. Progress display

### 5.1 When

- On by default if stderr is a terminal and `-q` is not given.
- `--no-progress` turns it off.
- `--progress` without a terminal (cron, systemd, a log file) logs one
  `INFO` line every 10 seconds instead of the live line, so a long run shows
  that it is alive.

### 5.2 What

One line on stderr, redrawn four times per second, cut to the terminal width
(`IO#winsize` from `io/console`):

```
⠹ 00:02:14  read 1.23M (9.2k/s)  written 1.23M  rejected 4.2k  failed 3
━━━━━━━━━━╺━━━━━━━━━ 52%  00:02:14 ETA 00:02:03  read 1.23M (9.2k/s)  written 1.23M  rejected 4.2k  failed 3
```

- The first form is used when the total is unknown, the second when it is
  known.
- The rate covers the last few seconds, not the whole run.
- Counts with no records (e.g. `failed 0`) are left out.
- At the end the line is cleared; the summary is logged as before.

The total is known if the source implements one of two optional methods:

- `size` returning an Integer (number of records), e.g. an Array. `count` is
  never called, because it would iterate the source.
- `progress` returning a Float from 0.0 to 1.0, or `nil` if unknown. The
  `JsonLines::Reader` implements it (3.1).

`--limit` caps the total.

### 5.3 Logs and the progress line

The logger and the progress display write through one shared stderr object
with a mutex. Before a log line is written, the progress line is cleared
(`\r\e[2K`); the next tick redraws it. Warnings such as `#4711: source failed`
do not garble the display.

### 5.4 Monitor seam

`Engine.new(pipeline, observer:, monitor:)`. The monitor receives
`start(live)` when the run starts and `stop` in an `ensure` (also after an
abort or a signal). `live` reads the current counters without copying them
(`read`, `written` from the sink adapter's `delivered`, `filtered`,
`rejected`, `failed`, elapsed time), and the source for `size`/`progress`.

`Metacrunch::Progress` implements the monitor with a background thread that
polls `live`. The engine does no extra work per record. Under the GVL,
reading Integer instance variables from another thread is safe; a slightly
stale value is fine. In sub-project 5 a fork executor can provide merged
worker counters through the same seam.

## 6. `trace`

```
metacrunch trace [OPTIONS] JOB_FILE [JOB_PARAMS...] [ARGS...]

  -n, --limit N          number of records to trace (default 10)
      --position LIST    only these positions, e.g. 4711 or 12,4711
      --id LIST          only records with these ids (compared as strings)
      --full             whole records instead of diffs, no shortening
  -i, --input PATH|-     as for run; the filter default applies
  -j, -q, -v, -h         see 2.2
```

### 6.1 Run

- The sink, `rejects` and `errors` sinks are replaced by null sinks. They are
  constructed but never opened; nothing is written.
- The error policy is always `:skip` without limit: failures are shown and
  do not end the trace.
- With `--position` or `--id`, records are read until all selected records
  were seen; only the selected ones are pushed through the chain. Positions
  stay real source positions. `-n` then limits the number of traced
  records, default: all selected.
- No progress display.
- Typical use: the log says `#4711: map#3 failed`, so
  `metacrunch trace --position 4711 job.rb ...` shows what happened.

### 6.2 Output

On stdout, colored if stdout is a terminal and `NO_COLOR` is not set. Logs go
to stderr.

```
#1  id=17
  reject#1    pass
  filter#2    pass
  map#3       - "_id": 17
              + "id": 17
              ~ "meta.source": "ris" → "fis"
              mark: No title
  flat_map#4  [1] - "isbns": ["978-3", "978-4"]
                  + "isbn": "978-3"
                  map#5  + "isbn13": "978-3-…"
              [2] - "isbns": ["978-3", "978-4"]
                  + "isbn": "978-4"
                  map#5  failed: KeyError: key not found: "x"  (jobs/catalog.rb:31)
              → 2 records
  sink        1 record (not written)
#2  id=18
  reject#1    rejected: Not public
traced 2 records: 1 to sink, 1 rejected, 1 failed
```

- **Diff of Hash records:** removed (`-`), added (`+`) and changed
  (`~ old → new`) keys. Nested Hashes are compared recursively, with a
  dotted path (`meta.source`); Arrays are compared as whole values. Values
  are shown as JSON, shortened to the terminal width (160 characters without
  a terminal).
- **Other records** (domain objects, strings, numbers) are shown in full
  with `inspect`, input and output.
- **Snapshots:** before each step, the input is deep-copied with `Marshal`,
  because steps may change records in place (the catalog fixture deletes
  `isbns`). If a record cannot be marshaled (a Proc, an IO), its `inspect`
  string serves as the snapshot.
- **Steps without effect** take one line: `pass`, `unchanged`, `filtered`,
  `rejected: REASON`.
- **Marks** added by a step are listed below it. **Failures** show class,
  message and the first backtrace line from the job's code.
- **`flat_map` children** are indented with `[k]`: each with its diff
  against the input and its way through the following steps. This follows
  the streaming order of the observer events (sub-project 1, 3.5): children
  pass the later steps before the `flat_map`'s `step_out`.
- **Invalid input** (`InvalidRecord`) is shown as `source failed:
  JSON::ParserError ...` with the raw line.
- `--full` shows the whole input and output of every step as pretty JSON (or
  `inspect`), not shortened.

### 6.3 Exit codes

0 after the trace, also if records failed (showing them is the purpose); 1 if
the run aborted (error in the source, `open`, `close`); 2 for usage errors.

### 6.4 Structure and engine addition

- `lib/metacrunch/trace.rb`: the observer and renderer, writing to an
  injected IO.
- `lib/metacrunch/diff.rb`: the Hash diff.
- `lib/metacrunch/cli/trace.rb`: options and wiring.
- The engine accepts `select: ->(record, position) { ... }` and hands it to
  the executor. Records that are not selected are read, but neither counted
  nor pushed into the chain. `limit` counts the records pushed into the
  chain; without `select` these are all source records. `Trace#trace?` is
  the select callable.
- The observer interface of sub-project 1 (`step_in`, `step_out`) does not
  change. Two refinements: for a failed step, `step_out` comes after the
  error policy was applied, so under `:skip` the observer sees
  `ctx.failure`; invalid records appear as the step `"source"` (3.4).

## 7. `check`

```
metacrunch check [-j NAME] [-q|-v] JOB_FILE [JOB_PARAMS...] [ARGS...]
```

Static validation: the file loads, the parameters bind, the recipe builds a
pipeline (constructors run, the DSL rules apply). Nothing is opened, no record
is read, no hook runs. There is no `--open` for a connectivity test, because
`open` has side effects (a writer truncates its file, an Elasticsearch sink may
create an index).

Output on stdout:

```
$ metacrunch check jobs/catalog.rb --output out data.json
jobs/catalog.rb: job "catalog" OK
  input     JsonArrayFile (id extractor)
  steps     reject#1 "Not public", filter#2, map#3, flat_map#4
  output    JsonLinesFile, batch 2
  rejects   JsonLinesFile
  errors    JsonLinesFile
  on_error  skip, max_errors 5
$ metacrunch check jobs/json2es.rb --index x
jobs/json2es.rb: job "json2es" OK
  input     stdin (JSON Lines)
  ...
```

- Parameter values are not printed: they may contain secrets from
  environment variables that would end up in CI logs.
- Exit 0 if valid. Exit 2 for any load, parameter or build error; the error
  goes to stderr. (`run` keeps exit 1 for build errors, as in sub-project 1.)

## 8. `new`

```
metacrunch new [--test] [--force] PATH
```

Creates a filter job, the idiomatic form for pipes. It runs right away and
passes records through:

```ruby
#!/usr/bin/env metacrunch
# frozen_string_literal: true

# Reads JSON Lines from stdin, writes JSON Lines to stdout:
#   metacrunch run jobs/mab2json.rb < in.jsonl > out.jsonl
# Declare a source or sink to read or write elsewhere.
Metacrunch.job "mab2json" do
  params do
    # param :index, String, required: true, desc: "Elasticsearch index"
  end

  # source MySource.new(params.files), id: ->(record) { record["id"] }

  reject("No id") { it["id"].nil? }
  map do |record, ctx|
    record
  end

  # sink MySink.new, batch: 1000
end
```

- The job name comes from the file name; `.rb` is appended if missing.
  Missing directories are created.
- The file is made executable, so `./jobs/mab2json.rb < in.jsonl` works.
- `--test` also writes `test/<name>_test.rb` (relative to the working
  directory): a Minitest test that runs the job with
  `Metacrunch::Testing.run` and one sample record.
- If a file exists, `new` exits with 2 unless `--force` is given.
- The created paths are printed on stdout.

## 9. Core changes

| Unit | Change |
|---|---|
| `Builder` | `source` is optional; `source id: ...` without an object; `"source"` is a reserved step name |
| `Pipeline` | new field `limit` |
| `Engine` | `ArgumentError` without source; handles `InvalidRecord` (3.4); options `monitor:` (5.4) and `select:` (6.4); live counters |
| `Executor::Inline` | `limit` and `select` |
| `StatsCollector` | counts failures of the `"source"` pseudo-step without a step entry |
| `InvalidRecord` | new (`Data`: `raw`, `error`) |
| `Job#run` | `limit:` keyword |
| `Testing.run` | `ArgumentError` if the job has no source and no `source:` is given |
| `Params` | `job` is no longer reserved (2.2) |
| `Engine` (closing) | A signal raised while closing a component (SIGPIPE from a writer) is raised again after all components were closed |
| `LiveStats` | new: live counters for monitors (5.4) |
| `SinkAdapter` | `batch` reader (for `check`) |
| new | `json_lines.rb`, `progress.rb`, `trace.rb`, `diff.rb`, `cli/` |

The step contract, context, error policy and stats of sub-project 1 do not
change otherwise.

## 10. Layout

```
lib/metacrunch.rb
lib/metacrunch/
  invalid_record.rb               InvalidRecord (Data)
  live_stats.rb                   LiveStats for monitors
  json_lines.rb                   JsonLines::Reader, Writer, ContextWriter
  progress.rb                     Progress monitor, shared stderr
  trace.rb                        Trace observer (events → tree)
  trace/renderer.rb               Trace::Renderer (tree → text)
  diff.rb                         Hash diff for trace
  cli.rb                          Dispatch, exit codes
  cli/
    command.rb                    Base: options, logger, exit codes
    job_command.rb                Base for run/check/trace: job loading, job help
    run_options.rb                RunOptions#apply
    run.rb
    check.rb
    trace.rb
    new.rb                        Templates for the job and test as heredocs
exe/metacrunch
```

`json_lines.rb` is required by `lib/metacrunch.rb` (jobs use it without an
extra `require`). `progress.rb`, `trace.rb`, `diff.rb` and `cli/` are required
by `metacrunch/cli`.

## 11. Tests

Minitest, as in sub-project 1. Coverage stays at least 95 % lines and 90 %
branches.

- **Unit tests:**
  - `JsonLines::Reader`: blank lines, `InvalidRecord` for invalid JSON and
    invalid UTF-8, `.gz`, `progress`, injected IO, closing after `break`.
  - `JsonLines::Writer`: `strict` errors, EPIPE → `SignalException("PIPE")`,
    no writes after a broken stream, `.gz`, IO from outside is not closed.
  - `JsonLines::ContextWriter`: envelope for rejection, failure and marks;
    `inspect` fallback.
  - `Diff`: added, removed, changed, nested, Arrays.
  - `Trace` renderer with `StringIO`: in-place mutation, `flat_map` children,
    non-Hash records, failures, `InvalidRecord`, `--full`, shortening.
  - `Progress` with a fake clock: terminal line, heartbeat without terminal,
    clearing before log lines, `size` and `progress` totals, `stop` after an
    abort.
  - `Engine`: `InvalidRecord` under `:abort` and `:skip`, `limit`, `select`,
    monitor `start`/`stop` after an abort and a signal, missing source.
  - `Builder`: optional source, `source id:` only, reserved `"source"`.
  - `RunOptions`: precedence, stdout conflicts, same path same object, error
    policy overrides.
- **CLI in-process** (`Cli` with `StringIO` streams): every command and
  option, help texts, all exit codes.
- **CLI as a subprocess** (`exe/metacrunch` with `Open3`, not counted for
  coverage):
  - a real pipe `run a | ruby -ne ... | run b`;
  - `run ... | head -n 1`: status 141 by SIGPIPE, empty stderr apart from
    logs;
  - a job created by `new`, started through its shebang line;
  - the progress line through `PTY.spawn`.

## 12. Documentation

- Readme: the CLI chapter is rewritten (commands, pipes and JSON Lines, filter
  jobs, `run` options, `trace`, `check`, `new`, exit codes). The JSON Lines
  components and `InvalidRecord` are documented with the sources and sinks.
- CHANGELOG: the new commands and options; breaking changes compared to the
  sub-project 1 CLI (`-v` means verbose, `--job` moves before the job file).

## 13. Measurements

Measured on Ruby 4.0.7 +YJIT, arm64 macOS (best of two runs):

| Measurement | Sub-project 1 (76f0b75) | Sub-project 2 |
|---|---|---|
| Engine, 1 M records through 10 `map` steps, no observer or monitor | 65.4 ns per step and record, 4.0 allocations per record | 63.6 ns per step and record, 4.0 allocations per record |
| Pass-through job (`Metacrunch.job {}`), 1 M JSON Lines (72 MB) from stdin to stdout | – | 1.30 M records/s |
| Same, `-i 1m.jsonl.gz` (8.6 MB) | – | 1.15 M records/s |

The seams of sub-project 2 (invalid records, limit, select, monitor) cost
nothing measurable per record. JSON parsing and generation (json 3.0.2)
are fast enough that a pipe stage is rarely the bottleneck of a job.
