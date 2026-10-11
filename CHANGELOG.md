# Changelog

## 5.0.0 (unreleased)

A redesign. Jobs written for 4.x must be rewritten; see the Readme.

### Breaking changes

- Jobs are defined with `Metacrunch.job do ... end`. A job file is plain Ruby; `.rb` is the recommended extension.
- `transformation` is replaced by `map`, `filter`, `reject` and `flat_map`. Returning `nil` no longer drops a
  record, and returning an Enumerator no longer fans out.
- `destination` is now `sink`. A job has at most one sink.
- `buffer:` is replaced by `batch:` on the sink (`write_batch`).
- `pre_process`/`post_process` are replaced by `before`/`after` hooks and `open`/`close` on components.
- `options` is replaced by `params { param ...; args ... }`. `ARGV` is no longer used.
- The CLI has commands (`run`, `check`, `trace`, `new`); `metacrunch JOB_FILE` still runs a job. Options of
  `metacrunch` go before the job file. It no longer changes into the job's directory and returns defined exit codes.
- `-v` now means `--verbose`; the version is shown with `metacrunch --version` only.
- `Metacrunch::TestUtils` is replaced by `Metacrunch::Testing`.
- Requires Ruby 4.0. ActiveSupport and colorize are no longer dependencies.

### Added

- Per-record context with `reject!`, `mark`, `store` and a record logger.
- `rejects` and `errors` sinks.
- Error policy `on_error :abort | :skip` with `max_errors`.
- Run results with stats per step and reason; `profile` for step timing.
- `flat_map` streams its children; batched sinks are flushed after an abort, on Ctrl-C and on SIGTERM.
- The CLI ends by the signal that stopped a job (exit status 130 for SIGINT, 143 for SIGTERM).
- Steps and sinks get the context only for a second required parameter, so `map(&method(:Integer))` works.
- Job files are loaded again only when they change.
- Unix pipes: a job without source reads JSON Lines from stdin, a job without sink writes them to stdout.
- `Metacrunch::JsonLines` reader and writers (also gzip); `Metacrunch::InvalidRecord` for records a source cannot read.
- `run` options to replace the source and sinks (`-i`, `-o`, `--rejects`, `--errors`), `--limit`, `--on-error`,
  `--max-errors`, `--stats` and a progress display.
- `metacrunch trace` shows what each step does to a record; `metacrunch check` validates a job; `metacrunch new`
  creates one.
- A closed stdout (`| head`) ends a job quietly by SIGPIPE (exit status 141).
