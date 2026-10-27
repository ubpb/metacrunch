# Changelog

## 5.1.0 (unreleased)

A redesign. Jobs written for 4.x must be rewritten; see the Readme and docs/.

The extension gems metacrunch-csv, metacrunch-xlsx, metacrunch-marc and metacrunch-elasticsearch live in this
repository and share metacrunch's version.

### Breaking changes

- Jobs are defined with `Metacrunch.job do ... end`. A job file is plain Ruby; `.rb` is the recommended extension.
- `transformation` is replaced by `map`, `filter`, `reject` and `flat_map`. Returning `nil` no longer drops a
  record, and returning an Enumerator no longer fans out.
- `destination` is now `sink`. A job has at most one sink.
- `buffer:` is replaced by `batch:` on the sink (`write_batch`).
- `pre_process`/`post_process` are replaced by `before`/`after` hooks and `open`/`close` on components.
- `options` is replaced by `params { param ...; args ... }`. `ARGV` is no longer used.
- The CLI has commands (`run`, `check`, `trace`, `new`, `generate`, `credentials`); a job runs with `metacrunch run
  JOB_FILE` (`metacrunch JOB_FILE` and executable job files no longer work). Options of `run` go before the job file.
  It no longer changes into the job's directory and returns defined exit codes.
- `-v` now means `--verbose`; the version is shown with `metacrunch --version` only.
- `Metacrunch::TestUtils` is replaced by `Metacrunch::Testing`.
- Requires Ruby 4.0. ActiveSupport and colorize are no longer dependencies.

### Added

- Per-record context with `reject!` (ends the step), `mark`, `store` and a record logger.
- `rejects` and `failures` sinks.
- Failure policy `on_failure :abort | :skip` with `max_failures`.
- Sinks report records they could not write with `Metacrunch::SinkFailures`; those records fail under the pseudo-step
  `sink` and follow the failure policy. `sink` and `source` are reserved step names.
- Run results with stats per step and reason; `profile` for step timing.
- `flat_map` streams its children; batched sinks are flushed after an abort, on Ctrl-C and on SIGTERM.
- The CLI ends by the signal that stopped a job (exit status 130 for SIGINT, 143 for SIGTERM).
- Steps and sinks get the context only for a second required parameter, so `map(&method(:Integer))` works.
- Job files are loaded again only when they change.
- Unix pipes: a job without source reads JSON Lines from stdin, a job without sink writes them to stdout.
- `Metacrunch::JsonLines` reader and writers; `Metacrunch::InvalidRecord` for records a source cannot read. The reader
  takes Arrays of files and reads gzip and tar archives whatever their names, also on stdin (`-i dump.tar.gz`).
- `Metacrunch::Input` and `Metacrunch::Output` for sources and sinks: paths, `-`, IOs (and Arrays for input); gzip and
  tar detected by content and unpacked; bzip2, xz, zstd and zip named in the error; all paths checked before reading;
  progress; a closed pipe ends the run as SIGPIPE. Problems raise `Metacrunch::InputError` and
  `Metacrunch::OutputError` with the file name. `metacrunch generate source|sink` builds on them.
- `run` options to replace the source and sinks (`-i`, `-o`, `--rejects`, `--failures`), `--limit`, `--on-failure`,
  `--max-failures`, `--stats` and a progress display.
- `metacrunch trace` shows what each step does to a record; `metacrunch check` validates a job; `metacrunch new`
  creates a project, and `metacrunch generate` a job, transform, command, source or sink in it with a test, or by path
  (a test with `--test`).
- A closed stdout (`| head`) ends a job quietly by SIGPIPE (exit status 141).
- `metacrunch run -w N` (`--workers N|auto`) runs the steps in N worker processes, with the results in source
  order; `Job#run`, `Testing.run` and `Engine` take workers as well. Step components are opened after the `before`
  hooks.
- Parameter values come from the command line, then a params file, then the default; a value is text, a list or a
  reference, `{env: NAME}` for an environment variable or `{credential: PATH}` for the encrypted credentials, also
  as the default (`default: {env: "ES_URL"}`). A reference that finds nothing is an error.
- `secret` declares a secret parameter, hidden in help texts, errors, `inspect` and logs; only a secret may refer to
  the credentials, and it takes no plain value from a params file or a default. Passing a secret unchanged to a
  `param` of a target of `use` or `invoke` is an error.
- Environments: `-e NAME` (or `METACRUNCH_ENV`) selects the credentials file and key and the section of a params file;
  without it, the environment `default` applies, a reserved name. A run logs where a selected environment comes from.
  `Job#run` and `Project#invoke` take `environment:`.
- Encrypted credentials in `.metacrunch/credentials[.ENV].yml.enc`; `metacrunch credentials edit|show|rotate` manages
  the files; `run`, `check` and `trace` take `-e`/`--environment` and `--credentials`.
- Parameter files: `run`, `check` and `trace` take `--params FILE`, a YAML file with one section per environment
  (`default:` for the default environment) whose keys are the parameters; sections share values only through YAML
  merge keys. One file serves the whole project: each target takes its own keys, and a key no job, transform or
  command of the project declares fails. Every section is checked on every run. `check` also checks commands.
- Projects: a `Metacrunchfile` names a project's jobs and commands (`Metacrunch.load_files`); `metacrunch run NAME`
  runs them from any directory of the project, and `metacrunch --help` lists them. A file that fails to load costs only
  its own names. A name declared twice is unusable, every call that loads the project warns about it, and
  `Project#duplicates` lists such names for a test. `Metacrunch.load_project` and `Project#invoke` do the same from
  Ruby.
- Commands: `Metacrunch.command "name" do params { ... }; run { ... } end`, with the parameters, credentials, `-e`,
  `--help` and logging of jobs. `invoke NAME, params: {...}` chains jobs, transforms and commands and returns a
  `Result` or a `CommandResult`; the exit status reports the worst result. An exception that ends a command is logged
  as a job's error is, in one line with the command's name and one for its cause; `-v` adds the backtrace, for jobs
  too. `Metacrunch::Testing.invoke` tests a command without running what it invokes. `Metacrunch.load_command` loads a
  command file, and `Testing.invoke` takes such a command, too.
- Names and descriptions for jobs: `Metacrunch.job "a2c", desc: "..."`. Names are parts of `a-z`, `0-9`, `_` and
  `-`, separated by `:`; `Metacrunch.job` raises for other names, and `metacrunch generate` for names and file
  names that would give one or the name of a built-in command.
- Transforms: `Metacrunch.transform "normalize" do params { ... }; map { ... } end` holds steps, hooks and parameters
  without source or sink, and a job inserts them with `use "normalize", params: {lang: "en"}`. Their steps are named
  with the transform as prefix (`normalize/map#1`); explicit step names must not contain `/`. Generated step numbers
  count the step statements of a recipe, `use` as one, so a transform that gains a step renames no step of the job. A
  transform runs, traces, checks and tests alone like a job without source and sink, and a file with one job or
  command besides transforms runs by path without `-j`. `Metacrunch.load_transform`, and `project:` for `Job#run` and
  `Testing.run`.
- One form for values from code: `use`, `invoke`, `Project#invoke`, `Job#run` and `Metacrunch::Testing` take
  `params: {...}`, bound by the same rules (a Pathname counts as its path, `nil` as not given). `root` reaches the
  project's files in jobs, transforms and commands. `Testing.run` takes a project and a name, like `Testing.invoke`;
  results answer `ok?`.
