# Changelog

## 5.0.0 (unreleased)

A redesign. Jobs written for 4.x must be rewritten; see the Readme and docs/.

### Breaking changes

- Jobs are defined with `Metacrunch.job do ... end`. A job file is plain Ruby; `.rb` is the recommended extension.
- `transformation` is replaced by `map`, `filter`, `reject` and `flat_map`. Returning `nil` no longer drops a
  record, and returning an Enumerator no longer fans out.
- `destination` is now `sink`. A job has at most one sink.
- `buffer:` is replaced by `batch:` on the sink (`write_batch`).
- `pre_process`/`post_process` are replaced by `before`/`after` hooks and `open`/`close` on components.
- `options` is replaced by `params { param ...; args ... }`. `ARGV` is no longer used.
- The CLI has commands (`run`, `check`, `trace`, `new`, `generate`, `credentials`); `metacrunch JOB_FILE` still runs
  a job. Options of `metacrunch` go before the job file. It no longer changes into the job's directory and returns
  defined exit codes.
- `-v` now means `--verbose`; the version is shown with `metacrunch --version` only.
- `Metacrunch::TestUtils` is replaced by `Metacrunch::Testing`.
- Requires Ruby 4.0. ActiveSupport and colorize are no longer dependencies.

### Added

- Per-record context with `reject!` (ends the step), `mark`, `store` and a record logger.
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
  creates a project, and `metacrunch generate` a job, transform, command, source or sink in it with a test, or by path
  (a test with `--test`).
- A closed stdout (`| head`) ends a job quietly by SIGPIPE (exit status 141).
- `metacrunch run -w N` (`--workers N|auto`) runs the steps in N worker processes, with the results in source
  order; `Job#run`, `Testing.run` and `Engine` take workers as well. Step components are opened after the `before`
  hooks.
- Encrypted credentials: parameters read secrets with `credential:` from `.metacrunch/credentials[.ENV].yml.enc`,
  after the command line and `env:`, and hide them in help texts, errors and `inspect`. `metacrunch credentials
  edit|show|rotate` manages the files; `run`, `check` and `trace` take `-e`/`--environment` and `--credentials`.
- Projects: a `Metacrunchfile` names a project's jobs and commands (`Metacrunch.load_files`); `metacrunch NAME` runs
  them from any directory of the project, and `metacrunch --help` lists them. A file that fails to load costs only
  its own names. A name declared twice is unusable, every call that loads the project warns about it, and
  `Project#duplicates` lists such names for a test. `Metacrunch.load_project` and `Project#invoke` do the same from
  Ruby.
- Commands: `Metacrunch.command "name" do params { ... }; run { ... } end`, with the parameters, credentials, `-e`,
  `--help` and logging of jobs. `invoke` chains jobs and commands; the exit status reports the worst result.
  `Metacrunch::Testing.invoke` tests a command without running what it invokes. `Metacrunch.load_command` loads a
  command file, and `Testing.invoke` takes such a command, too.
- Names and descriptions for jobs: `Metacrunch.job "a2c", desc: "..."`. Names are parts of `a-z`, `0-9`, `_` and
  `-`, separated by `:`; `Metacrunch.job` raises for other names, and `metacrunch generate` for names and file
  names that would give one or the name of a built-in command.
- Transforms: `Metacrunch.transform "normalize" do params { ... }; map { ... } end` holds steps, hooks and parameters
  without source or sink, and a job inserts them with `use "normalize", lang: "en"`. Their steps are named with the
  transform as prefix (`normalize/map#1`); explicit step names must not contain `/`. Generated step numbers count the
  step statements of a recipe, `use` as one, so a transform that gains a step renames no step of the job. A transform
  runs, traces, checks and tests alone like a job without source and sink, and a file with one job or command besides
  transforms runs by path without `-j`. `Metacrunch.load_transform`, and `project:` for `Job#run` and `Testing.run`.
