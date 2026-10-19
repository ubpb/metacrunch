# Projects, commands and gems

A project gives jobs, transforms and commands names, so that `metacrunch NAME` runs them from any directory of the
project. Commands chain jobs and other commands; gems can ship all three.

## Projects

A project names its jobs, transforms and commands in a `Metacrunchfile` at its root:

```ruby
# Metacrunchfile
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

```
project/
├── Metacrunchfile
├── .metacrunch/                   credentials
├── jobs/catalog.rb                Metacrunch.job "catalog", desc: "..."
├── transforms/catalog/public.rb   Metacrunch.transform "catalog:public", desc: "..."
├── commands/catalog/release.rb    Metacrunch.command "catalog:release", desc: "..."
├── lib/
└── test/
```

```
$ metacrunch catalog --output out                    # from any directory of the project
$ metacrunch catalog:release
$ metacrunch catalog:release --help
$ metacrunch --help                                  # lists the jobs, transforms and commands
```

`metacrunch` finds the nearest `Metacrunchfile` above the working directory and loads it only when a name is needed:
for `metacrunch NAME`, for `run`, `check` and `trace` with a name, for `help NAME` and for `--help`, when a job run
by path uses a transform by name, and for `generate` with a name and after it writes a job, transform or command.
The other built-in commands never load it, so job files `require` what they use themselves. The `Metacrunchfile` is
plain Ruby. `Metacrunch.load_files` takes globs relative to the project root, or absolute ones, and loads each
matching file once, in sorted order.

- A file that fails to load costs only its own names: `metacrunch` warns about it (`-v` after `run`, `check` or
  `trace` shows the whole error), and `--help` lists it under "Not loaded".
- Jobs, transforms and commands share one namespace. A name declared twice cannot be used until one is renamed; the
  error names both files, every call that loads the project warns about it, and `Project#duplicates` lists such
  names, so a test of the project can check that there is none (see [Testing commands](testing.md#testing-commands)).
- The names of the built-in commands (`run`, `check`, `trace`, `new`, `generate`, `credentials`, `help`) are reserved.
- Jobs without a name are not part of the project; they run by path.
- The `Metacrunchfile` and the files it loads are loaded again by every `Metacrunch.load_project`, so like job files
  they define no constants: helpers go into `lib/` and are required.

## Generating projects and files

```
$ metacrunch generate command --test tools/release.rb      # a single file, no project needed
$ metacrunch new catalog
$ cd catalog
$ metacrunch generate job catalog:ids
$ metacrunch generate transform normalize --desc "Tidy the titles"
$ metacrunch generate source files:lines
```

`new DIR` creates a project: a `Metacrunchfile` that loads `jobs/`, `transforms/` and `commands/`, a `Gemfile`, a
`Rakefile` whose `rake test` runs `test/**/*_test.rb`, a `lib/` for helpers, `test/test_helper.rb`, and
`test/project_test.rb`, which fails when a file of the project does not load or a name is declared twice. It writes
into a new or empty directory, or next to other files, which it leaves alone; existing files of the skeleton need
`--force`.

`generate KIND NAME|PATH` creates a file that runs right away and a test that passes:

| Command | Creates | What it is |
|---|---|---|
| `generate job catalog:ids` | `jobs/catalog/ids.rb`, `test/jobs/catalog/ids_test.rb` | a job that filters JSON Lines from stdin to stdout |
| `generate transform normalize` | `transforms/normalize.rb`, `test/transforms/normalize_test.rb` | steps for `use`; alone a filter like the job |
| `generate command catalog:publish` | `commands/catalog/publish.rb`, `test/commands/catalog/publish_test.rb` | a body that logs a line, with `invoke` as a comment |
| `generate source files:lines` | `lib/files/lines.rb` (`Files::Lines`), `test/lib/files/lines_test.rb` | a class that yields a record for each line of a file |
| `generate sink json_array` | `lib/json_array.rb` (`JsonArray`), `test/lib/json_array_test.rb` | a class that writes each record as a line of JSON |

- A name places the file below the project root, from any directory of the project: `:` separates directories, and
  `-` becomes `_` in file names. The test goes to the same place below `test/`. A name needs a `Metacrunchfile`.
- A path (it contains `/` or `.`) places the file there, also without a project, and the file name gives the name. It
  gets a test only with `--test`, in `test/` below the working directory, which loads the file by its path. Run it
  outside the project, or the test joins the project's `rake test`.
- `--no-test` leaves the test out, `--desc TEXT` sets the description of a job, transform or command, and `--force`
  overwrites existing files. A name declared in another file of the project is refused, and so is a test class
  that another test defines already.
- Sources and sinks are classes, not names of the project: the parts of their names are `a-z`, `0-9` and `_`,
  starting with a letter. A name that would reopen a class or module (`file`, or `files` next to `files:lines`) or put a
  library such as `json` or `yaml` into `lib/` is refused, since `lib/` comes first on the load path of the tests.
- After writing a job, transform or command, `generate` loads the project again and notes when the
  `Metacrunchfile` does not load the new file, for example because its globs are not recursive (`jobs/*.rb`).

## Commands

A command is a named recipe like a job, with parameters and a body instead of a pipeline:

```ruby
# commands/catalog/release.rb
require "fileutils"

Metacrunch.command "catalog:release", desc: "Write a new release and switch out/current to it" do
  params do
    param :input, String, desc: "JSON Lines with title records (default: the job's)"
    param :out, String, desc: "Directory for releases/ and current (default: out/ in the project)"
  end

  run do
    out = params.out ? Pathname(params.out) : root.join("out")
    release = out.join("releases", Time.now.strftime("%Y%m%d-%H%M%S-%L"))
    FileUtils.mkdir_p(release)
    input = params.input ? ["--input", params.input] : []
    result = invoke "catalog", "--output", release, *input
    next logger.warn("catalog:release: #{result.status}; out/current not switched") unless result.ok?

    # A new link renamed over the old one: the switch is atomic.
    link = out.join("current.new")
    FileUtils.rm_f(link)
    File.symlink(release.relative_path_from(out), link)
    File.rename(link, out.join("current"))
    release
  end
end
```

The command writes a release of the job `catalog` and switches `out/current` to it only after a clean run, so
readers of `out/current` never see a half-written or failed release.

Parameters, `env:`, credentials, `-e`, `--help` and logging work as for jobs. `params` comes first; `run { ... }`
holds the body, which `--help` never runs. In the body, `params`, `logger`, `invoke` and `root` (the project root, a
`Pathname`) are available, and `next` ends it early (`return` does not work in a block). Helpers shared by several
commands are plain Ruby: a module that the body `extend`s, or a proc for common parameters
(`params { instance_exec(&COMMON_PARAMS) }`) in a required file.

`invoke NAME, *ARGS, workers:, limit:` runs a job, transform or command with arguments as on the command line; each is
converted with `to_s`, and `nil`, an Array (a forgotten `*`) or a Hash raise `ArgumentError`. An invoked job runs like
`metacrunch run NAME`: it logs its summary as `catalog: ok: read ...`, reads stdin if it has no source and writes
stdout if it has no sink. All jobs and commands of a chain share `-e`, `--credentials`, the environment, the log
level and the progress setting.

| Case | `invoke` |
|---|---|
| Job ends `:ok` or `:ok_with_failures` | returns its `Result`; the command decides |
| Job ends `:aborted` | raises `Metacrunch::InvokeError` (with `result`); the chain ends unless the command rescues it |
| Unknown name, invalid arguments | raises `Metacrunch::InvokeError`: the command has a bug |
| Command | returns the value of its body; its exceptions pass unchanged |
| Ctrl-C, SIGTERM | the running job flushes and closes its sinks, then the chain ends by the signal |

The exit status of a command reports the worst result of the jobs it invoked (see
[Exit codes](cli.md#exit-codes)): 3 if one ended with failed records, 1 if an exception left the body.

`run` takes commands too; the job options (`-i`, `-o`, `-w`, ...) are a usage error for them, and `check` and
`trace` take jobs and transforms only. A command file can also run by path, or as an executable with
`#!/usr/bin/env metacrunch`; when it invokes a name, it finds the project from the working directory.

Names search credentials from the project root (`.metacrunch/` next to the `Metacrunchfile`), also for commands from
gems; a path searches from its file. A job below `jobs/x/` with a `.metacrunch/` of its own therefore uses the
project's credentials by name and its own by path. Nothing changes the working directory: relative paths stay
relative to where `metacrunch` was started, and `root.join(...)` reaches the project's files from anywhere.

## Jobs, transforms and commands from gems

A gem ships job, transform and command files like a project's, and a constant with their glob for each kind:

```
metacrunch-csv/
└── lib/metacrunch/
    ├── csv.rb                            # the constants; requires the helpers
    └── csv/
        ├── reader.rb                     # helpers: classes and constants go here
        ├── commands/check.rb             # Metacrunch.command "csv:check" do ... end
        ├── transforms/to_records.rb      # Metacrunch.transform "csv:to-records" do ... end
        └── jobs/import.rb                # Metacrunch.job "csv:import" do ... end
```

```ruby
# lib/metacrunch/csv.rb
require_relative "csv/reader"

module Metacrunch
  module Csv
    COMMANDS = File.expand_path("csv/commands/*.rb", __dir__)
    TRANSFORMS = File.expand_path("csv/transforms/*.rb", __dir__)
    JOBS = File.expand_path("csv/jobs/*.rb", __dir__)
  end
end
```

A project adds the gem to its `Gemfile` and opts in, next to its own files:

```ruby
# Metacrunchfile
require "metacrunch/csv"

Metacrunch.load_files Metacrunch::Csv::COMMANDS, Metacrunch::Csv::TRANSFORMS, Metacrunch::Csv::JOBS,
                      "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

`bundle exec metacrunch csv:check data/titles.csv` then runs a command of the gem, and `bundle exec metacrunch --help`
lists the gem's jobs, transforms and commands with the project's.

- The job, transform and command files define no constants, since every `Metacrunch.load_project` loads them
  again; classes and helpers belong in files that the gem's main file requires.
- The gem does not `require` its job, transform and command files: only `load_files` registers them with the project,
  while a `require` would load them once per process, and a second project in the same process would lack them.
- Names with a prefix (`csv:check`) keep clear of the project's: a name that the gem and the project both
  declare cannot be used. A reserved name makes the gem's file a load error.
- Credentials are searched from the project root, also for jobs and commands of a gem, so `-e production` works as
  for the project's files. In a command, `root.join(...)` reaches the project's files and `__dir__` the gem's.
- A file of the gem that fails to load costs only its own names, as a file of the project does.

For a gem without such a constant, the glob can start at the gem's directory:

```ruby
gem_dir = Gem::Specification.find_by_name("metacrunch-csv").gem_dir
Metacrunch.load_files File.join(gem_dir, "lib/metacrunch/csv/commands/*.rb")
```

The constant is still the better way: the gem can then move its files without breaking projects.

There is no global registry and no `~/.metacrunch` for jobs or commands: under Bundler a global file could not load
gems that the project's Gemfile lacks. Personal tools are executable command files on the `PATH`. For task automation
without records, Rake, Thor or just fit better.
