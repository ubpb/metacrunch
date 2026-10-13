# metacrunch-ng, sub-project 7: projects and commands

- Date: 2026-10-13
- Branch: `metacrunch-ng-commands` (from `metacrunch-ng` at e8fea68)
- Status: design approved; plan written
- Builds on: [sub-project 1 spec](2026-10-10-metacrunch-ng-core-design.md)
  (jobs, parameters), [sub-project 2 spec](2026-10-10-metacrunch-ng-cli-pipes-design.md)
  (CLI commands), [sub-project 6 spec](2026-10-11-metacrunch-ng-credentials-design.md)
  (credentials)

## 1. Context

metacrunch runs jobs: records flow from a source through steps into a sink.
A job is addressed by its file (`metacrunch run jobs/a2c.rb`); a file that
defines several jobs selects one with `-j NAME`.

Projects that publish data also need operations without records: create a
search index, switch an alias, set the number of replicas. A private toolbox
that metacrunch is meant to replace one day has ten commands. Four move
records (and become jobs); six are such operations, all of them generic
(Elasticsearch index administration). What is project-specific is the
orchestration: create an index, run the job into it, switch the alias only
if the run went well.

This sub-project adds **commands** next to jobs: named Ruby blocks with the
same parameters, credentials, logging and exit codes as jobs, which can
invoke jobs and other commands. Commands need names, so a project gets a
**`Metacrunchfile`** that declares its jobs and commands, and names become
the standard way to address jobs in a project. Paths keep working.

Global commands or jobs in `~/.metacrunch/` were considered and rejected:
under Bundler a global file cannot load gems that the project's Gemfile
lacks, CI and containers do not have the home directory, and Rake's
`~/.rake` (`rake -g`) and `thor install` (`~/.thor`) have existed for years
with little use. Generic commands come from gems; personal tools are
executable files on the `PATH`, which metacrunch already supports with
`#!/usr/bin/env metacrunch`.

### 1.1 Goals

1. A project declares its jobs and commands once, in a `Metacrunchfile`.
   `metacrunch NAME ...` runs either from any directory of the project, and
   `metacrunch --help` lists them with a description.
2. A command can chain commands and jobs (`invoke`). A job that aborts stops
   the chain; a job that finished with failed records lets the command
   decide; the exit status tells cron what happened.
3. Commands get typed parameters, `env:`, credentials, `-e ENV`, `--help`
   and logging from the same code as jobs.
4. Gems can ship commands (e.g. `es:create-index` in a future
   `metacrunch-elasticsearch`) that a project opts into.
5. A broken job or command file costs only its own names.
6. The orchestration of a command can be tested without running its jobs or
   touching external services.

### 1.2 Non-goals

- Global commands or jobs in `~/.metacrunch/`, or any registry outside the
  project.
- Long-running processes and endless sources (queue consumers): kept as
  item 7 of the backlog. They need a time-based sink flush, which is an
  engine topic.
- The Elasticsearch commands themselves: they belong to the port of
  `metacrunch-elasticsearch`.
- Running invoked jobs or commands in parallel.
- A Hash form of `invoke` (`invoke "a2c", index: ...`).
- `run { }` in jobs (3.2).
- Shell completion, `metacrunch list`, `metacrunch new --command`,
  `check` for commands, `root` in jobs.
- Loading only the file that defines a name (lazy lookup by file name);
  possible later as an optimization without changing job files.
- Changing the working directory (`-C DIR`, or a `chdir` to the project
  root as Rake does).

### 1.3 Success criteria

1. In a temporary project, started from a subdirectory, `metacrunch NAME`
   runs a job and a command declared through the `Metacrunchfile`, and
   `metacrunch --help` lists both with their descriptions.
2. A command that invokes a command, a job and another command:
   - stops after a job that aborts, with exit status 1;
   - goes on after a job that ends with failed records, and exits with 3;
   - ends by the signal after SIGTERM during the job, which flushes and
     closes its sinks first.
3. A file that fails to load costs only its names (one warning line); a
   name declared twice is unusable while all other names work; an error in
   the `Metacrunchfile` itself ends with exit status 2.
4. Built-in commands and runs by path never load the `Metacrunchfile`
   (checked with a `Metacrunchfile` that raises).
5. `-e production` reaches every job and command of a chain. Names in a
   project find `.metacrunch/` from the project root, also for a command
   loaded from outside the project (a gem).
6. `Metacrunch::Testing.invoke` records the invocations of a command
   without running them, and a stubbed status changes what the command does.
7. The engine keeps its cost (about 64 ns per step and record). `bundle
   exec rake` passes (coverage at least 95 % lines and 90 % branches,
   RuboCop).

### 1.4 Decisions

| Question | Decision |
|---|---|
| Scope | Single operation commands plus orchestration (chains of commands and jobs). No long-running processes. |
| Names for jobs too | Yes. One namespace for jobs and commands in a project; paths stay a second address. |
| Where names come from | From the code (`Metacrunch.job "a2c"`, `Metacrunch.command "es:create-index"`). Every call that needs names loads all files of the project. |
| Project file | `Metacrunchfile` (Ruby) in the project root, found upward from the working directory |
| Command form | A recipe like a job's: `params` first, then `run { ... }` with the body. `--help` never runs the body. Jobs get no `run`. |
| Calling | `invoke NAME, *argv, workers:, limit:` with arguments as on the command line |
| Gem commands | Command files in the gem plus a path constant; the project loads them with `load_files` |
| Credentials | Names in a project search `.metacrunch/` from the project root; paths from the file, as today |
| Global registry | None |

## 2. Names

### 2.1 Syntax

A name is one or more parts separated by `:`; each part matches
`[a-z0-9][a-z0-9_-]*`:

```
a2c   catalog:reindex   es:create-index   marc_to_json
```

`Metacrunch.job(name)` and `Metacrunch.command(name)` raise `ArgumentError`
for any other name. This applies to every job, also outside a project
(backward compatibility is not required; all names in the repository
match). Jobs may still be unnamed; commands may not. `metacrunch new` derives
the job's name from the file name and refuses a file name that is not a
valid name (`jobs/MyJob.rb`).

### 2.2 Name or path

An argument that contains `/` or `.` is a path. Any other argument is a
name; if the project has no such name (or there is no project) and a file
of that name exists, it is a path after all (an executable job without
`.rb` in the working directory).

### 2.3 Reserved names

The names of the built-in commands: `run`, `check`, `trace`, `new`,
`credentials`, `help`. In a project, declaring one is a load error of that
file (4.4); outside a project the name only matters for `-j`.

### 2.4 Descriptions

`desc:` is a one-line description for the list in `metacrunch --help`:

```ruby
Metacrunch.job "a2c", desc: "MARCXML to the catalog index" do ... end
Metacrunch.command "catalog:reindex", desc: "Load an export into a new index" do ... end
```

It is optional; the list shows nothing for a missing one.

## 3. Commands

### 3.1 Declaration

```ruby
Metacrunch.command "es:create-index", desc: "Create an Elasticsearch index" do
  params do
    param :url, String, default: "http://localhost:9200", env: "ES_URL"
    param :mappings, String, desc: "JSON file with the mappings"
    args :index, min: 1, max: 1
  end

  run do
    client = Elasticsearch::Client.new(url: params.url)
    index = params.index.first
    next logger.warn("#{index} exists, skipped") if client.indices.exists?(index:)

    client.indices.create(index:, body: {mappings: JSON.load_file(params.mappings)})
  end
end
```

`Metacrunch.command(name, desc: nil, &recipe)` returns a `Metacrunch::Command`
and registers it with the file that is being loaded (4.3), as
`Metacrunch.job` does today.

### 3.2 Recipe and body

The block is a **recipe**, like a job's: it only declares. It runs with
`instance_exec` on a `Metacrunch::CommandBuilder`:

| Statement | |
|---|---|
| `params { ... }` / `params` | Declares the parameters (first statement, as in jobs) / the bound values |
| `run { ... }` | The body; exactly one |

Evaluating the recipe binds the parameters; a `ParamError` there always
means invalid arguments. A recipe without `run`, or with two, raises
`ArgumentError` when it is evaluated, as a DSL mistake in a job recipe
does; loading the file does not evaluate the recipe.

The `run` block, the **body**, runs afterwards with `instance_exec` on a
`Metacrunch::CommandScope`:

| Method | |
|---|---|
| `params` | The bound values |
| `logger` | The logger of the run |
| `invoke(target, *argv, **options)` | Runs a job or command (section 5) |
| `root` | The root of the current project as a `Pathname`; `ProjectError` without project |

The value of the body (or of `next value`) is the command's value. `return`
cannot leave the block, as in job recipes; `next` does. Helpers shared by
several commands are plain Ruby: a module (`extend EsHelpers` in the body)
or a proc for common parameters (`params { instance_exec(&ES_PARAMS); args ... }`).

Code in the recipe outside `run` runs whenever the recipe is evaluated, as
component constructors in job recipes do; effects belong into `run`.

Jobs get no `run`: a job's pipeline is what runs, and `before` and `after`
are its hooks. A `run` in a job would either replace the pipeline (then it
is a command, and `-w`, `-o`, `check` and `trace` would not apply) or be a
third hook.

### 3.3 Help

`--help` evaluates the recipe only up to its first statement (`params` or
`run`), as `Job#describe` does with the `throw` of `Builder::DESCRIBED`. The
body never runs for help, also for a command without parameters. The help
has the form of a job's, with the description after the usage line:

```
Usage: metacrunch run es:create-index [PARAMS...] INDEX...

Create an Elasticsearch index

        --url VALUE                  (default: http://localhost:9200, env: ES_URL)
        --mappings VALUE             JSON file with the mappings
    INDEX  (1 to 1 arguments)
```

### 3.4 Commands by path

A file that declares a command can be run by path, like a job:
`metacrunch run tools/reindex.rb ...`, or as an executable file with
`#!/usr/bin/env metacrunch`. `-j NAME` selects among several declarations of
a file, jobs and commands alike. Outside a project, such a command can only
invoke paths, and `root` raises.

## 4. Projects

### 4.1 The `Metacrunchfile`

```ruby
# Metacrunchfile
require "metacrunch/elasticsearch"

Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS,  # absolute glob into the gem
                      "jobs/**/*.rb", "commands/**/*.rb"     # relative to the project root

Metacrunch.command "catalog:reindex", desc: "..." do       # inline declarations are fine
  run { ... }
end
```

```
project/
├── Metacrunchfile
├── .metacrunch/          credentials (unchanged)
├── jobs/a2c.rb
├── commands/catalog.rb
├── lib/  etc/
└── Gemfile
```

It is plain Ruby, loaded with `Kernel.load` (no `instance_eval`, so
constants behave as in any Ruby file). The project root is its directory.
Every `load_project` loads it again, so like job files it defines no
constants; helpers live in `lib/` and are required.

### 4.2 Finding the project

From the working directory upward; the nearest `Metacrunchfile` wins, and
nothing is merged. A `~/Metacrunchfile` is therefore found from any
directory below the home directory that has no project of its own, as a
`~/Rakefile` is for `rake`; it is not blocked.

The `Metacrunchfile` is loaded only when a name is needed: a name as the
first argument, `run|check|trace NAME`, `--help`, `help`, and the first
`invoke` of a name by a command run by path. Built-in commands
with paths (`metacrunch run jobs/a2c.rb`) and `metacrunch FILE` with a path
(2.2) never load it. Job files therefore require what they use themselves.

### 4.3 `Metacrunch.load_files`

`Metacrunch.load_files(*globs)` loads files into the project whose
`Metacrunchfile` is being loaded; called anywhere else it raises
`ProjectError` ("only in a Metacrunchfile").

- Relative globs are relative to the project root, absolute ones are used as
  they are. Matches are sorted; a file matched twice is loaded once.
- Each file goes through `Loader` (mtime cache, `Metacrunch.job` and
  `Metacrunch.command` register with the file being loaded), which collects
  its declarations with their file.
- Declarations made directly in the `Metacrunchfile` belong to the project,
  with the `Metacrunchfile` as their file.

Gem command files must not define constants (helpers live in library files
that the gem requires), because loading a file again in the same process
would redefine them. The mtime cache of `Loader` avoids that for unchanged
files. Job files already follow this rule.

### 4.4 Errors while loading

| Error | Effect |
|---|---|
| A file of `load_files` raises (`ScriptError`, `StandardError`), including a reserved or invalid name | That file contributes no names. Its error is kept in `load_errors`. |
| A name is declared twice (job/job, job/command, gem/project) | That name is unusable; calling it reports both locations. Other names work. |
| The `Metacrunchfile` itself raises | `ProjectError`; the CLI ends with exit status 2. |

When a call loads the project, every file in `load_errors` gives one warning
line on stderr (`jobs/broken.rb: SyntaxError: ... (-v for details)`, with
the first line of the message); `-v` logs the whole message. The help lists
these files instead (6.3).

### 4.5 Gems

A gem ships command files in the same form as a project and a constant with
their glob:

```ruby
# metacrunch-elasticsearch/lib/metacrunch/elasticsearch.rb
module Metacrunch
  module Elasticsearch
    COMMANDS = File.expand_path("elasticsearch/commands/*.rb", __dir__)
  end
end
```

The project opts in with `Metacrunch.load_files Metacrunch::Elasticsearch::COMMANDS`.
There is no global registry: a gem whose `require` registered its commands
would register them once per process, so a second project loaded in the same
process (a test, an application) would lack them.

### 4.6 Ruby API

```ruby
project = Metacrunch.load_project                # upward from Dir.pwd
project = Metacrunch.load_project("/srv/data")   # upward from that directory

project.root           # Pathname
project.names          # declared names, sorted
project.fetch("a2c")   # the Job or Command; ProjectError if unknown, duplicate or none
project.load_errors    # [[file, error], ...]
project.invoke("catalog:reindex", "dumps/a.tar.gz", logger:, env: ENV)
```

`load_project` raises `ProjectError` if no `Metacrunchfile` is found.
`project.invoke` behaves like `invoke` in a command (section 5), with
`$stdin`, `$stdout`, `Metacrunch.logger` and `ENV` as defaults and no
progress display; it returns the value and raises `InvokeError` as `invoke`
does. `Job#run` keeps its behavior.

## 5. Invoking jobs and commands

### 5.1 Calling

```ruby
Metacrunch.command "catalog:reindex", desc: "Load an export into a new index and switch the alias" do
  params do
    param :url, String, default: "http://localhost:9200", env: "ES_URL"
    param :alias, String, default: "catalog"
    param :workers, Integer, default: 8
    args :files, min: 1
  end

  run do
    index = "#{params.alias}-#{Time.now.strftime("%Y%m%d%H%M")}"
    es = ["--url", params.url]

    invoke "es:create-index", *es, "--mappings", root.join("etc/catalog_mappings.json"), index
    result = invoke "a2c", *es, "--index", index, *params.files, workers: params.workers
    next logger.warn("alias not switched") unless result.status == :ok
    invoke "es:switch-alias", *es, "--to", index, params.alias
  end
end
```

`invoke(target, *argv, workers: nil, limit: nil)`:

- `target` is a name or a path (2.2). Names resolve in the current project:
  the one found from the working directory on the command line, the given
  one in the Ruby API.
- `argv` are the arguments as on the command line; each is converted with
  `to_s` (Pathname, Integer). The parameters of the target are bound from
  them like on the command line: argv, `env:`, credentials, default. A
  `nil` raises `ArgumentError`: an optional parameter left unset would
  otherwise pass an empty string.
- `workers:` and `limit:` apply to jobs, as in `Job#run`; for a command they
  raise `ArgumentError`.

### 5.2 How a job runs

An invoked job runs like `metacrunch run NAME ARGV` with no other run
options: a job without source reads JSON Lines from stdin (an error if
stdin is a terminal), a job without sink writes JSON Lines to stdout. Its
error is logged and its summary is logged as `NAME: ok: read ...`. Progress
follows the rule of `run`: a status line if stderr is a terminal, off with
`-q`, and `--[no-]progress` of the outer call overrides it.

### 5.3 Results and failures

| Case | Effect |
|---|---|
| Job ends `:ok` or `:ok_with_failures` | `invoke` returns its `Result` |
| Job ends `:aborted` | `invoke` raises `InvokeError` ("a2c aborted: StepError: ..."), with the `Result` |
| Invoked command | `invoke` returns the command's value |
| Invoked command raises | The exception propagates unchanged |
| Invalid argv for the target (`ParamError`, also `CredentialsError`, raised while its recipe is evaluated), unknown name | `InvokeError`; the command has a bug, the user's input is fine |
| Ctrl-C, SIGTERM | The running job flushes and closes its sinks; the `SignalException` propagates and ends the chain |

`InvokeError` has `name`, `result` (for an aborted job, else nil) and the
original error as `cause`.

### 5.4 Exit status of a command

| Status | When |
|---|---|
| 0 | The body finished and every invoked job ended `:ok` |
| 1 | An exception left the body: logged with its backtrace; an `InvokeError` as its message only, since the job already logged its error |
| 2 | Invalid parameters of the command itself; on the command line an unknown or duplicate name, a project error |
| 3 | The body finished, and an invoked job (also one invoked by an invoked command) ended `:ok_with_failures`, or `:aborted` with the `InvokeError` rescued by the command |
| 128 + n | Ended by signal n |

### 5.5 Shared context

All jobs and commands of a chain share the outer call's `-e` (or
`METACRUNCH_ENV`), `--credentials` (or `METACRUNCH_CREDENTIALS`), `env`,
logger, log level (`-q`, `-v`) and progress setting, and stdin and stdout.

Credentials: a name in a project searches `.metacrunch/` from the project
root, which is what `Credentials::Location.for_job` does when it is given
the `Metacrunchfile` as the job file. This also holds for a command whose
file lives in a gem. A path searches from its file, as today. A job below
`jobs/x/` with a `.metacrunch/` of its own therefore uses the project's
directory by name and its own by path; the Readme says so.

Relative paths stay relative to the working directory; nothing changes
directory. `root.join(...)` reaches project files from anywhere.

## 6. Command line

### 6.1 Calls

```
metacrunch NAME [PARAMS...] [ARGS...]            short for run NAME
metacrunch run [OPTIONS] NAME|FILE [PARAMS...] [ARGS...]
metacrunch check|trace [OPTIONS] NAME|FILE ...   jobs only
metacrunch NAME --help                           the parameters; same as help NAME
metacrunch help NAME
metacrunch FILE [PARAMS...] [ARGS...]            unchanged
```

`Cli#run` dispatches the first argument: `-h`/`--help`/`--version`/`help`,
then built-in commands, then a name (2.2), then an existing file. Anything
else is a usage error: `unknown command, job or file: x`, and with a project
whose `load_errors` are not empty, the hint that some files did not load.

### 6.2 `run` and commands

`run` runs jobs and commands. For a command:

- `-e`, `--credentials`, `-q`, `-v` and `--[no-]progress` apply (5.5).
- The job options (`-i`, `-o`, `--rejects`, `--errors`, `-n`, `--on-error`,
  `--max-errors`, `-w`, `--stats`) are a usage error:
  `catalog:reindex is a command; -w applies to jobs`.

`check` and `trace` with a command: usage error
`catalog:reindex is a command; check takes jobs`. `-j` selects within a
file; with a name it is a usage error.

### 6.3 Help

Outside a project, `metacrunch --help` is as today. In a project it adds
the project's names:

```
Usage: metacrunch NAME [PARAMS...] [ARGS...]
       metacrunch COMMAND [OPTIONS] NAME|JOB_FILE [PARAMS...] [ARGS...]

Commands:
  run           Run a job or project command
  check         Validate a job without running it
  ...

Jobs (/srv/data):
  a2c           MARCXML to the catalog index

Project commands (/srv/data):
  catalog:reindex   Load an export into a new index and switch the alias
  es:create-index   Create an Elasticsearch index

Not loaded:
  jobs/broken.rb: SyntaxError: jobs/broken.rb:3: syntax error found
```

A duplicate name is listed once, with `(declared more than once, unusable)`.
A file that did not load is listed with the first line of its error. If the
`Metacrunchfile` itself fails, the help shows the built-in commands and the
first line of the error in place of the lists, with exit status 0.

## 7. Testing commands

```ruby
require "metacrunch/testing"

class ProjectTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load
    assert_empty PROJECT.load_errors
  end

  def test_keeps_the_alias_when_records_failed
    run = Metacrunch::Testing.invoke(PROJECT, "catalog:reindex",
                                     params: {files: ["dumps/a.tar.gz"]},
                                     stubs: {"a2c" => :ok_with_failures})

    assert_equal ["es:create-index", "a2c"], run.invoked.map(&:name)
    assert_equal :ok_with_failures, run.status
  end

end
```

`Metacrunch::Testing.invoke(project, name, params: {}, stubs: {}, logger: Logger.new(nil))`:

- Binds `params` as a Hash (`bind_hash`); credentials are never read, as in
  `Testing.run`.
- Every `invoke` in the body is recorded as `Invocation(name, argv,
  options)` and not run. It returns the stub for its name:
  - none given: a `Result` with status `:ok` and empty stats for a job,
    `nil` for a command;
  - a status Symbol: a `Result` with that status;
  - a `Result`, or a callable that gets argv and returns the value.
  A stubbed `:aborted` raises `InvokeError` as a real abort does.
- An invoked name the project does not know raises as in a real run; a stub
  for an unknown name raises `ArgumentError`. Both catch typos.
- Returns `Testing::CommandRun(value, status, error, invoked)`; `status` is
  `:ok`, `:ok_with_failures` or `:aborted` (an exception left the body;
  `error` holds it).

Jobs are still tested with `Testing.run`.

## 8. Architecture

| Unit | Responsibility |
|---|---|
| `Metacrunch::Names` (new) | Name syntax, reserved names, name-or-path rule (2.1–2.3) |
| `Metacrunch::Command` (new) | The recipe: `name`, `desc`, `file`, `describe`, `prepare` (evaluate the recipe with a binder, return values and body) |
| `Metacrunch::CommandBuilder` (new) | The recipe's receiver: `params` (declare and bind, first statement), `run` |
| `Metacrunch::CommandScope` (new) | The body's receiver: `params`, `logger`, `invoke`, `root` |
| `Metacrunch::Invoker` (new) | The shared context of a chain (5.5); resolves targets, runs jobs (5.2) and commands, wraps errors (5.3), tracks the worst status (5.4) |
| `Metacrunch::Project` (new) | Finds and loads the `Metacrunchfile`; `root`, declarations, `load_errors`, duplicates, `fetch`, `names`, `invoke` |
| `Loader` | Registers jobs and commands; `load_files` for the project being loaded; selection by `-j` across both |
| `Job` | `desc:`, name validation |
| `Metacrunch` | `command`, `load_files`, `load_project` |
| `Cli` | Dispatch of names (6.1), help with the project's lists (6.3) |
| `Cli::JobCommand`, `Cli::RunCommand` | `NAME|FILE`; `run` runs commands through the `Invoker` and rejects job options for them; `check`/`trace` reject commands |
| `Testing` | `invoke` with a recording invoker (7) |
| `errors.rb` | `ProjectError < Error` (exit 2), `InvokeError < Error` (exit 1) |

`Cli::RunCommand` and `Invoker` share the code that applies the run
options, runs the engine and reports the result; the plan decides where it
lives (`RunOptions` is in `cli/` today and the `Invoker` also serves the
Ruby API). The engine, the executors, the step chain and the credentials
format do not change. No new dependency.

## 9. Exit codes

| Situation | Exit status |
|---|---|
| Unknown name, duplicate name, `Metacrunchfile` error, job option for a command, command for `check`/`trace` | 2 |
| Command: see 5.4 | 0, 1, 2, 3, 128 + n |
| Jobs by name | as jobs by path today |

## 10. Tests

### 10.1 Unit tests

- `Names`: valid and invalid names, reserved names, the name-or-path rule
  with and without an existing file.
- `Command`/`CommandBuilder`/`CommandScope`: `params` first, `describe`
  stops at the first statement and never runs the body (also without
  `params`), no `run` or two, the body's value, `next`, `root` with and
  without project.
- `Loader`: jobs and commands from one file; `-j` across both; registration
  with the file being loaded.
- `Project`: upward search, nearest wins; `load_files` with relative,
  absolute and overlapping globs, sorted; `load_files` outside a
  `Metacrunchfile`; a failing file, a duplicate name, a reserved name; an
  error in the `Metacrunchfile`; loading the same project twice in one
  process without constant warnings; `fetch` messages.
- `Invoker`: argv conversion; resolution of names and paths; each row of
  5.3; the worst status of 5.4 through a nested command; a signal from an
  invoked job propagates after the job closed its sinks; shared `-e` and
  credentials from the project root for a command file outside the project.
- `Testing.invoke`: recording, each stub form, the default stubs, stubbed
  `:aborted`, unknown names in `invoke` and in `stubs`, credentials never
  read.

### 10.2 Command tests

Through `Cli` with injected streams: dispatch order (built-in, name, file,
unknown), `metacrunch NAME --help` and `help NAME` for jobs and commands,
job options with a command, `check`/`trace` with a command, the help lists
with descriptions, duplicates, `Not loaded` and a failing `Metacrunchfile`,
warnings for load errors, and that built-ins and paths do not load a
`Metacrunchfile` that raises.

### 10.3 End to end

Through `exe/metacrunch` in a temporary project, started from a
subdirectory: a chain command → job → command with exit statuses 0, 1 and
3; SIGTERM during the invoked job (an endless source fixture) ends the
chain with 143 after the sink was closed; `-e production` with credentials
used by an invoked job.

## 11. Documentation and example

- `examples/project/`: a small project without external services, with a
  `Metacrunchfile`, `jobs/catalog.rb` and `commands/release.rb`. The command
  `catalog:release` writes the catalog into `out/releases/<time>/` and
  switches the symlink `out/current` only if the job ended `:ok`: the
  pattern of index and alias, runnable anywhere. A test uses
  `Testing.invoke`. `examples/Readme.md` lists it.
- Readme, new section "Projects and commands": the `Metacrunchfile`, names,
  commands, `invoke` and exit statuses, gem commands, credentials from the
  project root, testing with `Testing.invoke`, and that task automation
  without records fits Rake, Thor or just.
- Readme, "Running jobs": names next to paths, `run` for commands.
- Readme, new paragraph "What runs when", for jobs and commands alike:
  - top-level code of a file runs whenever the file is loaded (in a project
    also for the `--help` list);
  - the recipe runs for `run`, `check`, `trace` and `Testing.run`, and for
    `--help` up to its first statement, including the arguments of that
    statement;
  - `before`, the components' `open`, the steps, `after` and a command's
    `run` block run only in a run.

  The rule: a recipe only declares. Preparation (lookup tables,
  connections) belongs into `before`, effects into components or a
  command's `run`; code that must stay in the recipe goes after `params`,
  where `--help` does not reach it.
- Readme, workers: the advice to build a lookup table "at job level or in a
  `before` hook" becomes "in a `before` hook", since code at job level runs
  for every `--help` too.
- CHANGELOG: projects, commands, names for jobs, `desc:`, the stricter name
  syntax.

## 12. Deferred

- Long-running processes and endless sources (backlog item 7).
- Elasticsearch commands, with the port of `metacrunch-elasticsearch`.
- Lazy lookup of a name by file name.
- Shell completion, `metacrunch list`, `metacrunch new --command`, `check`
  for commands, `root` in jobs.
- Parallel `invoke`.
