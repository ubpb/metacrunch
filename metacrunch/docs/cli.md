# The command line

`metacrunch --help` lists the built-in commands and, in a project, its jobs, transforms and commands;
`metacrunch help COMMAND|NAME|FILE` and `metacrunch run NAME --help` show the options and parameters of one of them.

| Command | |
|---|---|
| `run` | Run a job, transform or command |
| `check` | Load a job, transform or command and bind its parameters, without running anything |
| `trace` | Show what each step does to the first records |
| `new`, `generate` | Create a project, and jobs, transforms, commands, sources and sinks in it (see [Projects](projects.md#generating-projects-and-files)) |
| `credentials` | Edit, show or rotate encrypted credentials (see [Credentials](credentials.md)) |

## Running jobs and transforms

```
$ metacrunch run [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]
$ metacrunch run jobs/catalog.rb --help                     # the job's parameters
$ metacrunch run catalog --help                             # the same, by name in a project
```

A job, transform or command always runs with `run`; `metacrunch catalog` alone is an unknown command. Options of
`run` go before the job; everything after it belongs to the job. Use `--` before job arguments that
start with `-`. A job is given by its file or, in a project, by its name; an argument with `/` or `.` is always a
file. The CLI does not change the working directory: relative paths are relative to where you start it.

| Option | |
|---|---|
| `-j`, `--job NAME` | Select a job, transform or command in a file that declares several |
| `-e`, `--environment NAME` | The [environment](environments.md): its credentials and its section of the params file (default: `METACRUNCH_ENV`, else the default environment) |
| `--params FILE` | Parameter values from FILE, the section of the environment (see [Parameter files](jobs.md#parameter-files)) |
| `--credentials DIR` | Credentials directory (default: `METACRUNCH_CREDENTIALS`, then `.metacrunch/` above the job file or, for a name, above the `Metacrunchfile`, then `~/.metacrunch/`) |
| `-i`, `--input PATH` | Read JSON Lines from PATH (`-` for stdin; gzip and tar are unpacked) instead of the job's source |
| `-o`, `--output PATH` | Write JSON Lines to PATH (`-` for stdout) instead of the job's sink |
| `--rejects PATH`, `--failures PATH` | Write rejected or failed records with their context; both may name the same file |
| `-n`, `--limit N` | Process only the first N source records |
| `--on-failure abort\|skip`, `--max-failures N` | Override the job's failure policy |
| `-w`, `--workers N\|auto` | Run the steps in N worker processes (see [Workers](workers.md)) |
| `--stats PATH` | Write status and stats as JSON at the end (`-` for stdout) |
| `--[no-]progress` | Progress on stderr; shown by default if stderr is a terminal and records do not go to the same terminal |
| `-q`, `-v` | Log warnings only, or debug messages too, among them the backtrace of the error that ended the run |

The options from `-i` to `--stats` apply to jobs and transforms only; for a command (see
[Commands](projects.md#commands)) they are a usage error.

## Pipes

A job without `source` reads JSON Lines from stdin, a job without `sink` writes JSON Lines to stdout. Such jobs chain
with each other and with other tools, and every stage runs in its own process:

```
$ metacrunch run examples/hello.rb | jq -c 'select(.name != "Grace")' | metacrunch run examples/normalize.rb
```

`source id: ->(record) { record["id"] }` gives a job that reads stdin an id extractor. Only records survive a pipe,
not their context. When the reader of the pipe stops (`| head`), the job flushes and closes its other sinks and ends
quietly by SIGPIPE. A job without source refuses to read a terminal: run from a terminal, it asks for a pipe or `-i`.

## Checking and tracing

```
$ metacrunch trace -n 2 catalog --output out
$ metacrunch trace --position 3 catalog --output out
$ metacrunch check catalog --output out
$ metacrunch check -e production --params config/release.yml catalog:release
```

`trace` shows what every step does to the first records (or to the records at `--position`, or with `--id`): the
changed keys of Hash records, marks, rejections and failures, and the records a `flat_map` emits. It changes
nothing: all sinks are replaced, and `before` and `after` hooks do not run. `--full` shows whole records.

`check` loads the job, binds its parameters and builds it, without opening, reading or running anything. For a
command it binds the parameters and runs nothing; with `--params` and `-e` it checks a params file, e.g. in CI.

## Exit codes

| Code | Job or transform | Command |
|---|---|---|
| 0 | ok | every job it invoked ended `:ok` |
| 1 | aborted | an exception left the body, logged as `NAME: Class: message` (backtrace with `-v`); an `InvokeError` is logged as its message |
| 2 | usage error: command, options, file or name, parameters, `Metacrunchfile`; `check` found the job invalid | the same, for the command itself: its parameters, an unknown or duplicate name, the `Metacrunchfile` |
| 3 | finished, but records failed (`on_failure :skip`) | an invoked job ended `:ok_with_failures`, or `:aborted` and the command went on |
| 130 | interrupted by Ctrl-C (SIGINT) | the same |
| 141 | stdout was closed by the reader (SIGPIPE) | the same |
| 143 | terminated (SIGTERM) | the same |

After Ctrl-C or SIGTERM the running job writes what its sinks have buffered, closes them, and `metacrunch` ends by the
signal, so shells and `xargs` see the interruption. Data already written to stdout is kept. A job whose source has
`stop`, such as a queue consumer, ends normally on SIGTERM instead, with exit code 0 (see
[Sources](jobs.md#sources)); a second SIGTERM interrupts it.
