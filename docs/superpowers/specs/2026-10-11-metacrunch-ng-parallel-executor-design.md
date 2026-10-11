# metacrunch-ng, sub-project 5: parallel executor

- Date: 2026-10-11
- Branch: `metacrunch-ng`
- Status: approved; implemented
- Builds on: [sub-project 1 spec](2026-10-10-metacrunch-ng-core-design.md),
  [sub-project 2 spec](2026-10-10-metacrunch-ng-cli-pipes-design.md)

## 1. Context

Sub-project 1 built the core and left a seam for an executor (3.5): the
step chain is stateless with respect to the stream, so the steps can run in
worker processes while source and sinks stay in one place. Sub-project 2
built the CLI and deferred `--workers` to this sub-project.

The motivating case is `ris2fis` (`~/Code/Projects/upb/fis/ris2fis`). Its
per-record sanitizing is expensive, and the script parallelizes it by hand:
it slices the whole input into one chunk per worker, runs the chunks with
the `parallel` gem, collects issue rows per record, reassembles the chunks
in order and renders a dashboard per worker. The goal is to get the same
speed-up from the engine, without custom code in the job.

Measured in sub-project 1 (1, 11) on Ruby 4.0.7 (arm64 macOS, 8 workers):

- With about 28 µs of work per record, fork workers with Marshal and batches
  of 100 reached about 5× the sequential throughput, Ractors about 1.5×.
- With very cheap steps (about 0.6 µs per record), any transfer between
  workers is slower than sequential.
- Ractor is still experimental, and Nokogiri raises `Ractor::UnsafeError`
  outside the main Ractor.

### 1.1 Goals

1. `metacrunch run -w 8 job.rb` runs the steps of any job in 8 worker
   processes, without changes to the job.
2. Workers do not change the result: the sink, the `rejects` and `errors`
   sinks, logs, marks and the error policy behave as without workers, in
   source order. Section 4.4 lists the one exception (stats after an abort).
3. A ris2fis-like job (expensive steps, marks that a sink turns into an
   issue report) runs generically with workers.

### 1.2 Non-goals

- A Ractor executor. It can be added behind the same seam once Ractor is no
  longer experimental (12).
- Workers that write to sinks themselves. A sink that needs parallelism (e.g.
  concurrent Elasticsearch bulk requests) implements it internally.
- Output in arrival order (`--unordered`).
- A `workers` declaration in the job DSL. Workers are chosen per run.
- A dashboard with one line per worker, and a per-worker utilization report
  (12).
- A CLI option for the batch size.

### 1.3 Success criteria

1. The engine's behaviour tests (error policy, batching, invalid records,
   `select`/`limit`, lifecycle, monitor) pass with the inline executor and
   with `Executor::Fork.new(workers: 2, batch_size: 3)` (9.1).
2. A fixture job with expensive steps and marks produces byte-identical
   output, rejects and errors files with `-w 3` and without.
3. With about 28 µs of work per record, `-w 8` reaches at least 4× the
   inline throughput (11).
4. Inline runs keep their cost: about 64 ns per step and record and 4
   allocations per record (sub-project 2, 13).
5. With `-w 2`: `| head -n 1` ends with 141, SIGINT to the process group
   with 130, SIGTERM to the parent with 143. No worker process is left
   afterwards.
6. `bundle exec rake` passes locally (tests, coverage at least 95 % lines and
   90 % branches, RuboCop), and CI passes on Linux and macOS.

### 1.4 Decisions

| Question | Decision |
|---|---|
| Where source, steps and sinks run | Source and sinks (including `rejects`/`errors`) in the parent, the steps in the workers. Parallel writing is a matter of the sink implementation. |
| Output order | Always source order |
| How workers are enabled | `-w`, `--workers N\|auto` on `run`; `workers:` in the library API. Default: inline. No DSL declaration. |
| Mechanism | A pool of forked workers, created once per run. Two pipes per worker, length-prefixed Marshal frames, batches of 100 records, round-robin dispatch from a feeder thread. |
| Ractor | Deferred (12) |
| Progress display | One line as before, with the number of workers. Per-worker utilization deferred (12). |
| Step lifecycle | Steps are opened after the `before` hooks, by the executor: once inline, once per worker with workers |

## 2. Architecture

### 2.1 Units

| Unit | Responsibility |
|---|---|
| `Processor` (new, extracted from `Engine`) | Builds the step chain, creates contexts (`ingest`), applies the error policy, opens and closes the step callables. Hands results to an outlet. |
| `SinkOutlet` (new) | Writes delivered records to the sink, rejected ones to `rejects`, failed ones to `errors`; counts failures and enforces `max_errors`. |
| `Executor::Inline` | Runs one `Processor` with a `SinkOutlet` in the current process |
| `Executor::Fork` (new) | Forks the workers, feeds them batches, applies their results in order through the `SinkOutlet`, stops the pool |
| `Executor::Fork::Worker` (new) | The loop in the child: reads batches, runs a `Processor` with a `BatchOutlet`, writes results |
| `Executor::Fork::Frame` (new) | Reads and writes length-prefixed Marshal frames |
| `Executor.for(workers)` (new) | `nil` or `1` → `Inline`, `N > 1` → `Fork` |
| `Engine` | Validation, `open`/`close` of source and sinks, hooks, monitor, flush after an abort, `Result` |

An outlet has three methods, called in the order in which records leave the
chain: `deliver(record, ctx)`, `reject(record, ctx)` and `fail(record, ctx)`.
`SinkOutlet` writes them to the pipeline's `SinkAdapter`s. `BatchOutlet`
appends them to the current batch result (3.3).

`max_errors` moves from the engine into `SinkOutlet#fail`: it counts the
records it receives and raises the same `Error` as before once the count
exceeds `max_errors`. Inline, the processor calls it directly; with workers,
the parent calls it while it applies a batch. The same code gives the same
point of abort.

### 2.2 Executor seam

```ruby
executor.run(pipeline, stats:, outlet:, observer:, select:)
```

- `stats` is the run's `StatsCollector`; `outlet` is the run's `SinkOutlet`.
- The executor reads the source (applying `pipeline.limit` and `select`),
  opens the step callables, pushes the records through a `Processor` and
  closes the step callables.
- `Executor::Fork` raises `ArgumentError` when an observer is given. `trace`
  always runs inline.

Reading the source with `limit` and `select` stays in one place,
`Executor::Inline.each_record(source, limit:, select:)`, which the fork
executor's feeder uses as well.

### 2.3 Run sequence

The same in both modes:

1. The parent opens the source and the sinks.
2. The parent runs the `before` hooks.
3. The executor runs:
   - **Inline:** opens the step callables, processes all records, closes
     the step callables.
   - **Fork:** calls `Process.warmup` (better copy-on-write sharing) and forks
     N workers. Each worker opens its step callables and reports that it is
     ready (3.4). Once all workers are ready, the parent starts the feeder
     thread. Each worker processes its batches, closes its step callables
     and ends with `exit!`. The parent applies the results in order. If a
     worker cannot open its steps, the run aborts before any record is read,
     as inline.
4. The parent flushes the sinks, closes sinks and source in reverse order and
   runs the `after` hooks.

Consequences:

- **Changed for inline runs:** the step callables are opened after the
  `before` hooks; until now they were opened before them. Open order:
  source, sinks, then steps. Close order: steps, sinks, source.
- Data loaded at job level or in a `before` hook (lookup tables) is
  inherited by the workers through copy-on-write and loaded once. A step's
  `open` runs once per worker, which is right for connections.
- One object used both as a step and as a sink is opened twice: once as a
  step, once as a sink. Within the steps and within source and sinks it is
  opened once, as before.
- Workers inherit the file descriptors of the opened source and sinks but
  never use them. They end with `exit!`, so `at_exit` hooks run in the parent
  only and inherited write buffers are not flushed a second time. (Measured
  on Ruby 4.0.7: a child that ends with `exit` writes the parent's unflushed
  `File` buffer again.)
- The `id:` extractor and the handling of `InvalidRecord` run in the worker,
  as part of the record's processing.
- The progress thread and the feeder thread do not exist in the children
  (fork keeps only the calling thread). The feeder starts after the fork.

### 2.4 Dispatch and order

Batch `k` (0-based) goes to worker `k mod N`. Each worker processes its
batches in the order it receives them, so the parent reads the result of
batch `k` from worker `k mod N`, one batch after another. Results arrive in
source order without a reorder buffer.

- **Feeder thread (parent).** Reads the source through
  `Executor::Inline.each_record`, collects batches of `batch_size` records
  with their positions, dumps each batch and writes it to the next worker's
  input pipe. At the end of the source (or the limit) it closes all input
  pipes.
- **Main thread (parent).** Reads batch results in order and applies them
  (3.3). After the last batch, each worker sends a final frame (3.4); the
  run ends when all workers sent it.
- **Backpressure** comes from the pipe buffers: a slow sink blocks the main
  thread, the workers block on writing their results, and the feeder blocks
  on writing the next batch. Memory stays bounded by about one batch per
  pipe and worker.
- **No deadlock:** a worker reads a whole batch before it writes the result.
  The batch the main thread waits for was written completely before any
  later batch, so its worker can always finish it.

A slow source (records trickling in through a pipe) delays a record until
its batch is full or the source ends. This is documented.

## 3. What crosses the process boundary

### 3.1 Transport

Two `IO.pipe`s per worker: input (parent → worker) and output (worker →
parent). Each message is a frame: the length of the payload as 4 bytes
(`pack("N")`), then the payload, a `Marshal.dump`. `Frame.read` returns
`nil` at a clean end of file and raises `Metacrunch::Error` for a truncated
frame.

`batch_size` is 100. `Executor::Fork.new(workers:, batch_size: 100)` takes
it as a keyword (tests use small batches to force batch boundaries); there
is no CLI option.

### 3.2 Parent → worker

One frame per batch: `[positions, records]`, two Arrays of equal length.
Each element of `records` is the Marshal dump of one record, taken when
the source yielded it, so a source may reuse one object for all records.
Positions are consecutive unless `select` skipped records. The end of the
batches is the end of file of the input pipe. If a record cannot be dumped,
the feeder first sends the records before it as a batch.

### 3.3 Worker → parent: batch results

Every frame from a worker is a Hash with a `type` (`:ready`, `:batch`,
`:done`), the `events` to apply and an optional `error`. One `:batch` frame
per batch:

```ruby
{
  type:   :batch,
  events: [[:log, line], [:deliver, record, state], [:reject, record, state], [:fail, record, state], ...],
  stats:  Stats,             # what this batch counted (StatsCollector#take)
  error:  nil | Exception    # ends the batch, see 4.1
}
```

The parent first adds `stats` to its collector (`StatsCollector#absorb`), then
applies the events in order: `[:log, line]` is written with `logger << line`
(3.5); the other events rebuild the context (3.6) and go to
`SinkOutlet#deliver`, `#reject` or `#fail`. If `error` is set, the parent
raises it after the events (4.1). An exception raised while applying an
event (a sink error, `max_errors`) stops the batch at that event.

`state` is a `Context::State` (3.6). A worker sends `:deliver` events only if
the pipeline has a sink and `:reject` events only if it has a `rejects` sink;
`:fail` events always, because the parent counts them for `max_errors`.

`StatsCollector#take` returns a snapshot and sets all counters to zero,
keeping the counter objects the chain holds. Marks are counted in the worker
when they happen (`on_mark`), so they are part of the batch's stats.

### 3.4 Worker → parent: start and end

- After opening its step callables, the worker sends
  `{type: :ready, events: [logs], error: nil}`, or the error of `open` and
  ends. The parent reads the `:ready` frames of all workers, in worker
  order, before it starts the feeder. The first error aborts the run before
  any record is read.
- After the end of file of its input, the worker closes its step callables
  and sends `{type: :done, events: [logs], error: close_error}`. The parent
  logs a close error and makes it the run's error if there is no other one,
  as for components closed in the parent.
- A worker that gets SIGINT or SIGTERM closes its step callables (best
  effort) and ends by that signal, without a frame: it restores the default
  handler and sends the signal to itself again. A worker never runs the
  `at_exit` handlers it inherited (e.g. Minitest's or SimpleCov's).

### 3.5 Logs

In the worker, the pipeline's logger is redirected with `Logger#reopen` to a
buffer (an object with `write` and `close`, public `Logger` API). Each
formatted line becomes a `[:log, line]` event of the current batch; lines
logged while the worker opens or closes its steps travel in the next frame.
The parent writes the line with `logger << line` when it reaches the event.

- Logs appear in source order, in the order they would appear inline
  (e.g. the failure's log line before the record reaches the `errors` sink).
- The progress line is not garbled: all lines pass through the parent's
  shared stderr (sub-project 2, 5.3).
- Logs of work discarded after an abort do not appear.
- The worker's logger keeps the parent's level, so `debug { ... }` blocks
  are not evaluated when the level is higher.
- The timestamps are those of the worker.
- A logger that is not a `::Logger` (no `reopen`) is left as it is and writes
  directly from the worker.

### 3.6 Context

The context is converted explicitly, without Marshal hooks:

- `Context#to_state` returns a `Context::State`, a `Data` with `id`,
  `position`, `step`, `marks`, `store`, `rejection` and `failure`.
- `Context.from_state(state, logger:)` builds a context in the parent with
  the parent's logger, so `ctx.logger` works in sinks. It has no `on_mark`:
  marks were counted in the worker.

### 3.7 What must be Marshal-able

With workers, these must be Marshal-able:

- records, in both directions;
- `value:` of marks and rejections;
- `ctx.store`.

If a frame cannot be dumped (`TypeError`), the sender dumps its entries one
by one to find the culprit, then raises `Metacrunch::Error` with the
position and the reason. The run aborts. For example:

```
record at position 17 cannot be sent to a worker: no _dump_data is defined for
class Nokogiri::XML::Element; with --workers, records must be Marshal-able
(parse XML in a step, not in the source)
```

```
record at position 17 cannot be sent from a worker: can't dump IO; with
--workers, records, mark and rejection values and ctx.store must be Marshal-able
```

The first message comes from the feeder; it aborts the run like a source
error (4.1). The second comes from a worker; it becomes the `error` of the
batch result, after the events before the culprit.

Exceptions are not the job's choice (they come from libraries), so they do
not abort the run. An exception that cannot be dumped (`failure.error`, the
`error` of a batch result, or any `cause` in their chain) is replaced by a
`Metacrunch::WorkerError < Metacrunch::Error` that keeps the original class
name (`#original_class`), its message (`#original_message`; `#message` is
`"Original::Class: message"`) and the backtrace. A `StepError` whose cause
cannot be dumped stays a `StepError` with the same message; only its cause
is replaced. The stats still count the original class, because they were
counted in the worker. `JsonLines::ContextWriter` writes the original class
and message, so an `errors` file looks the same with and without workers.

The normal path costs nothing extra: the culprit is searched only after a
dump failed.

## 4. Errors, aborts and signals

### 4.1 Error policy

Rule: the parent applies everything in source order. Whatever ends a batch
or a worker is raised in the parent at the corresponding point of the order.
The error policy of sub-project 1 (3.3) applies unchanged.

| Situation | Behaviour |
|---|---|
| A step fails under `:skip` | The worker logs the failure and emits `[:fail, record, state]`. The parent writes it to the `errors` sink and checks `max_errors` (2.1), at exactly that record. |
| A step fails under `:abort` | The worker's processor raises the `StepError`. The worker stops the batch there, sends the events before it with the `StepError` as `error`, and ends. The parent applies those events, then raises the `StepError`: the run is `:aborted`. |
| The `id:` extractor raises, a step's output cannot be dumped (3.7) | Like `:abort`: the error is sent, the worker ends, the parent raises it at that point. |
| A worker's `open` fails | The run aborts before any record is read (3.4). |
| The source raises, or a source record cannot be dumped | The feeder keeps the error and closes all input pipes. The parent applies all batches before it, then raises it. The run is `:aborted`, as inline. |
| A sink raises while the parent applies a batch | The run is `:aborted`, as inline. |
| A worker raises `SystemExit` or `NoMemoryError` | The worker sends it as `error` if it can and ends. The parent raises it again; like inline, it is not covered by the error policy. |
| A worker ends without a frame (crash, OOM kill, `exit!` in a step) | The parent reads end of file, reaps the worker with `waitpid` and raises `Metacrunch::Error`: `worker 3 (pid 4711) ended unexpectedly (killed by SIGKILL)`. On macOS, `SIGABRT` adds a hint on `OBJC_DISABLE_INITIALIZE_FORK_SAFETY` (6). |

A worker that sent an `error` ends after closing its step callables. The
feeder may then get `Errno::EPIPE` when it writes the worker's next batch.
The feeder stops quietly in that case: the main thread reports the cause
when it reaches the batch.

### 4.2 Stopping the pool

`Executor::Fork#run` stops the pool in an `ensure`, after an abort and on
signals, before the engine flushes the sinks:

1. Kill the feeder thread (`Thread#kill`). The source's `ensure` blocks run.
2. Close both pipes of every worker. A worker that writes gets `EPIPE`.
3. Send `SIGTERM` to the workers that are still running. A worker closes its
   step callables (best effort) and ends by the signal (3.4).
4. Wait up to 5 seconds for the workers (`STOP_TIMEOUT`, keyword
   `stop_timeout:` of `Executor::Fork.new`), then send
   `SIGKILL` and reap it.

After a normal end the workers have already ended; the parent only reaps
them. No zombie or orphan processes are left.

### 4.3 Signals

- **Ctrl-C** sends SIGINT to the whole foreground process group, so to the
  parent and the workers. A worker ends by the signal (3.4). The parent
  treats a worker that ended by SIGINT or SIGTERM as if it had received that
  signal itself. Whichever it notices first, the result is the same: stop
  the pool, flush and close the sinks, re-raise the signal; exit status 130.
- **SIGTERM** to the parent only (`kill PID`) or to the whole group
  (systemd): the same path, exit status 143.
- **SIGPIPE**: raised by the stdout writer in the parent (sub-project 2,
  3.5); the same path, exit status 141. Workers never write to stdout.
- **The parent is killed with SIGKILL:** the workers read end of file or get
  `EPIPE` and end. No orphans are left.

### 4.4 Stats after an abort

- An abort in a worker (`:abort`, 4.1) stops the batch at the failing
  record, so the stats are exact.
- An abort in the parent in the middle of a batch (`max_errors` exceeded, a
  sink error) still adds the stats of that whole batch. They may count up to
  `batch_size - 1` records after the point of abort.
- Batches that other workers finished later are discarded and not counted.

Records in the sinks, logs, `rejects` and `errors` are always exactly as
inline. This difference in the stats is documented.

## 5. CLI and library API

### 5.1 `run`

```
  -w, --workers N|auto       run the steps in N worker processes (default: 1, no workers)
```

- `1` runs inline, without fork. `auto` is `Etc.nprocessors - 1`, at least 1:
  the parent needs a core for the source, the sinks and Marshal.
- `0`, negative numbers and other words are usage errors (exit 2):
  `--workers must be a positive number or auto`.
- On a platform without `Process.fork` (Windows, JRuby), `-w` with more than
  one worker is a usage error: `--workers needs Process.fork, which this
  platform lacks`.
- `-i`, `-o`, `--rejects`, `--errors`, `--stats` and `--limit` work
  unchanged: they concern the source and sinks in the parent.
- `trace` always runs inline and has no `-w`. `check` does not change.

### 5.2 Library

```ruby
Engine.new(pipeline, executor: Metacrunch::Executor::Fork.new(workers: 4))
job.run(argv, workers: 4)                                  # nil or 1: inline
Metacrunch::Testing.run(job, source: records, workers: 2)  # tests a job with workers
```

`Executor.for(workers)` picks the executor; `Job#run` and `Testing.run` use
it. `Executor::Fork.new` raises `ArgumentError` for `workers < 2` or a
`batch_size` that is not a positive Integer. `Testing.run(..., workers: 2)`
lets a job's tests check that its records and marks cross the process
boundary.

## 6. Platform

- **macOS:** a forked child crashes if a gem initialized parts of the
  Objective-C runtime in the parent (known with `pg` and GSSAPI, and with
  proxy lookups in `net/http`), with a message like `objc[4711]: +[...
  initialize] may have been in progress in another thread when fork() was
  called`. The fix is the environment variable
  `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`, set before the process starts;
  metacrunch cannot set it for itself. The Readme documents it (10), and the
  error for a worker killed by `SIGABRT` on Darwin names it.
- **Linux and macOS** are tested in CI (existing matrix).
- **No fork** (Windows, JRuby): see 5.1. Inline runs work everywhere.

## 7. Progress and stats

- `LiveStats` reads the parent's collector, which holds the stats of the
  applied batches, and gets a `workers` reader. With more than one worker,
  the line shows it after the time:

  ```
  ⠹ 00:02:14  8 workers  read 1.23M (52k/s)  written 1.23M  rejected 4.2k
  ```

- `read` counts applied records. A source's `progress` runs ahead by the
  batches in flight; the difference is a few hundred records and not
  corrected.
- `Stats` keeps its shape. With `profile true`, step times are summed over
  all workers and may exceed the run's duration. This is documented.
- At `DEBUG` level the parent logs `started 8 workers (pids 4711-4718)` and,
  at the end, the exit of each worker.

## 8. Layout

```
lib/metacrunch/
  components.rb                 OpenContext, Components.open/close (from Engine)
  processor.rb                  Processor: chain, contexts, error policy (from Engine)
  sink_outlet.rb                SinkOutlet: sinks, failure count, max_errors
  executor.rb                   Executor.for
  executor/inline.rb            Executor::Inline (+ each_record)
  executor/fork.rb              Executor::Fork: options, supported?
  executor/fork/run.rb          One run: pool, feeder, ordered apply, stop
  executor/fork/worker.rb       Worker loop, BatchOutlet, log buffer
  executor/fork/frame.rb        Length-prefixed Marshal frames
  executor/fork/dump.rb         Dumping with replacements and culprit search
  context.rb                    + to_state, from_state
  stats_collector.rb            + take, absorb
  live_stats.rb                 + workers
  errors.rb                     + WorkerError
  engine.rb                     lifecycle, hooks, monitor, result
  cli/run.rb                    -w, --workers
bench/executor.rb               Measurements (11)
```

## 9. Tests

Minitest, as before. Coverage stays at least 95 % lines and 90 % branches.

### 9.1 Parity suite

The engine's behaviour tests (error policy, batching, `InvalidRecord`,
`select`/`limit`, lifecycle, monitor, stats) become a shared module. It runs
twice: inline, and with `Executor::Fork.new(workers: 2, batch_size: 3)`, so
batch boundaries fall in the middle of the data. Tests that only make sense
inline (observer) stay outside the module.

### 9.2 Unit tests

- `Processor` and `SinkOutlet`, including `max_errors`.
- `Context#to_state` and `from_state`.
- `StatsCollector#take` and `absorb`.
- `Frame`: round trip, end of file, truncated frame.
- Finding the culprit of a failed dump; `WorkerError` for exceptions that
  cannot be dumped, also in a `cause`.
- `Worker#run(input, output)` driven in-process through pipes, without fork:
  the `:ready` frame, batches, logs, errors, `open`/`close` failures, the
  `:done` frame. SimpleCov
  does not see forked children (which end with `exit!`), so this is where
  the worker's lines are covered.

### 9.3 Fork tests

- Source order with deliberately uneven step costs.
- `max_errors` stops at exactly the right record; `:abort` stops the batch.
- A source error after N records; a source record, a step output, a mark
  value that cannot be dumped; an exception that cannot be dumped.
- A worker killed with `SIGKILL` inside a step; `exit` inside a step.
- `open` and `close` failures in a worker; after an `open` failure no
  record reaches a sink.
- Order of log lines; no log lines after an abort.
- Data loaded in a `before` hook reaches the workers; `open` runs once per
  worker.
- Regression: buffered output of a sink in the parent is written once.
- A worker that ignores SIGTERM is killed after `STOP_TIMEOUT` (with a
  shorter timeout in the test).
- After every fork test, no child process is left (`Process.waitall` returns
  nothing).

### 9.4 CLI

- In-process: parsing of `-w` (`N`, `auto`, invalid values), the platform
  check, `N workers` in the progress line.
- Subprocess (`exe/metacrunch`): the fixture job of 1.3 item 2 with and
  without `-w 3`, compared byte by byte; `-w 2 ... | head -n 1` ends with
  141; SIGINT to the process group ends with 130; SIGTERM to the parent ends
  with 143. Afterwards no process of the group is left.

## 10. Documentation

- Readme, new section "Workers":
  - when workers pay off (expensive steps), and when not (cheap steps,
    measured numbers);
  - what crosses the process boundary and must be Marshal-able (for
    MARCXML: the source yields Strings, a step parses them);
  - `open` of a step runs once per worker; shared read-only data belongs at
    job level or in a `before` hook;
  - records are processed in batches of 100, which delays slow sources;
  - stats after an abort (4.4) and with `profile true`;
  - macOS: `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`.
- Readme, "Running jobs": `-w`.
- CHANGELOG: `--workers`; steps are now opened after the `before` hooks.

## 11. Measurements

`bench/executor.rb` is committed. Measured on Ruby 4.0.7 +YJIT, arm64 macOS
(18 cores):

| Measurement | Target | Result |
|---|---|---|
| Inline engine, 1 M records through 10 `map` steps | About 64 ns per step and record, 4 allocations per record | 63.1 ns per step and record, 4.0 allocations per record (baseline before this sub-project: 63.8 ns) |
| Expensive step (about 28 µs per record), `-w 8` | At least 4× inline | 29 µs per record inline: 35.0k records/s; 8 workers: 178k records/s, **5.1×** |
| Cheap step (about 0.6 µs per record), `-w 8` | Measured and documented | 0.4 µs per record: inline 2.76 M records/s, 8 workers 0.52 M records/s (0.2×, slower) |
| JSON Lines pass-through, `-w 8` | Measured and documented | 1 M lines: inline 1.31–1.41 M records/s, `-w 8` 0.42 M records/s |

The inline run of the expensive step is bimodal on this machine: 29 µs per
record, or 47 µs when macOS runs the single process on an efficiency core.
The table uses the faster value; against the slower one, 8 workers reach
about 8.5×. The workers reach about 180k records/s in every run. With cheap
steps and with pass-through jobs, the parent (Marshal, source, sink) is the
bottleneck, and workers make the job slower, as expected.

The feeder dumps every record when the source yields it (one Marshal dump
per record), so a source may reuse one object for all its records (found in
the final review). That costs about 30 % of the throughput of cheap jobs
with workers (0.75 M before) and nothing measurable with expensive steps
(5.3× before).

## 12. Deferred

- **Ractor executor:** behind the same seam, once Ractor is no longer
  experimental and the libraries in use (Nokogiri) support it.
- **Utilization per worker** at the end of the run (e.g. `worker 3: 61 %
  busy`), to show whether the parent is the bottleneck.
- **Unordered output**, **a CLI option for the batch size**, **a `workers`
  DSL declaration**: only for a concrete need.
