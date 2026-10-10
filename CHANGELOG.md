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
- The CLI no longer changes into the job's directory and returns defined exit codes.
- `Metacrunch::TestUtils` is replaced by `Metacrunch::Testing`.
- Requires Ruby 4.0. ActiveSupport and colorize are no longer dependencies.

### Added

- Per-record context with `reject!`, `mark`, `store` and a record logger.
- `rejects` and `errors` sinks.
- Error policy `on_error :abort | :skip` with `max_errors`.
- Run results with stats per step and reason; `profile` for step timing.
