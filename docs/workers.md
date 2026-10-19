# Workers

`-w N` (`--workers N`) runs the steps in N worker processes; the source and the sinks stay in the main process.
`-w auto` uses one worker per core but one. Records reach the sinks, the `rejects` and `errors` sinks and the log in
source order, so a job gives the same results with and without workers.

```
$ metacrunch run -w 8 -i examples/data/publications.jsonl examples/sanitize.rb --issues tmp/issues.tsv
```

Workers pay off when the steps are expensive. With about 28 µs of work per record, 8 workers were about 5× as fast.
With cheap steps (a few `map`s over Hashes, about 0.4 µs per record), sending records between processes costs more
than it saves: 8 workers handled 0.5 M records/s, inline 2.8 M records/s.

- Records travel between the processes with `Marshal`. Records, the `value:` of marks and rejections and `ctx.store`
  must be Marshal-able. A source that reads large documents (XML, JSON) should yield them as Strings and leave the
  parsing to a step. An
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
  inherit it from the main process, and `--help` does not build it (see [What runs when](jobs.md#what-runs-when)). Steps
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
