# 1. Sources that wait yield FLUSH and stop on SIGTERM

- Status: accepted
- Date: 2026-10-28

## Context

The engine pulls: it reads a source with `each`, runs the steps and hands the records to the sinks, which buffer them
for `batch:` and write them when a batch is full or the run ends. With `--workers`, a feeder thread sends the records
to the workers in batches of 100. That suits sources that end, such as files and queries.

A source that waits for data does not end: a queue consumer waits for new entries without end, a source that polls an
API waits between two polls. While it waits, up to a batch of records stays in each sink and in the feeder's partial
batch, for as long as nothing new arrives. Such a job is stopped by a supervisor with SIGTERM, which aborted the run:
the record a step was working on, and those in the workers' batches, were lost.

## Decision

A source can tell the engine two things.

- It yields `Metacrunch::FLUSH` instead of a record to have the records it yielded so far written now. The feeder
  sends its partial batch at once, marked; the main process applies it in source order and then has every sink write
  what it buffers for `batch:` and, through the sink's optional `flush`, what it buffers itself (a file). `FLUSH` is
  no record: no position, no count, no limit. The source decides when, since only it knows that it waits.
- It has `stop`. On the first SIGTERM the engine calls it, and `stop` of the sinks that have one, from the signal
  handler; the source ends its `each` soon, and the run ends as if the source had ended: the records under way are
  processed and written, the status is ok, `metacrunch run` exits with 0, and `Result#stopped` says so. A sink that
  waits (a queue writer while the queue is full) gives up. A second SIGTERM goes to the default handler and stops at
  once. The engine installs its handler only in the main thread and only while SIGTERM has its default handler, so a
  program with its own handling (a job server, a web server) keeps it. `invoke` raises `SignalException` after a
  stopped job, so a command that invoked it ends by the signal.

## Alternatives

- A time-based flush in the engine (`sink ..., batch: 1000, flush_after: 5`): it needs a timer next to the pulling
  engine, a thread that writes into sinks while the main thread may be in a step or in the source, and the feeder's
  batches would still wait. The source already knows when it waits.
- A flush after every record of a slow source: a write per record, also when records come fast.
- Trapping SIGTERM in the source: a component should not own the process's signals, and with workers the source runs
  in the feeder thread.
- Trapping in the CLI only: jobs also run through `Job#run`, `invoke` and `Metacrunch::Testing`.
- Graceful SIGINT as well: Ctrl-C reaches every process of the terminal's process group, workers included, so it
  cannot drain them; it stays an immediate stop.

## Consequences

- Sources that wait (the queue reader of metacrunch-redis, future pollers) have their records written within a
  bounded time, inline and with workers, and end cleanly under systemd or Docker.
- Each FLUSH costs a partial batch: a source yields it when it waits, not after every record.
- `stop` runs in a signal handler: it may only set a flag.
- With workers, SIGTERM must reach the main process only (`kill PID`, `docker stop`, systemd `KillMode=mixed`); a
  signal to the whole process group ends the workers and the run at once. The run ends once the workers processed the
  batches they hold.
- A consumer that is killed still loses what it holds: delivery stays at most once. At-least-once needs the source to
  learn which records the sinks wrote, which is not part of this decision.
