metacrunch
==========

[![CI](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml/badge.svg)](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml)

metacrunch is a small toolkit for data processing and ETL (extract, transform, load) in Ruby. It grew out of metadata
work in a library, but nothing in it is specific to library data: a record is any Ruby object, usually a Hash.

A **job** reads records from a **source**, passes them through **steps** and writes the results to a **sink**.
Records that a step rejects, or that fail, go to sinks of their own, together with the reason:

```
source ──▶ step ──▶ step ──▶ … ──▶ sink
             │        │
             └────────┴──▶ rejects, failures
```

Everything is plain Ruby. There are three kinds of recipes, and `metacrunch run` runs each of them:

| | |
|---|---|
| **Job** | source, steps and sink |
| **Transform** | named steps with parameters of their own, which jobs insert with `use` |
| **Command** | a Ruby body that runs jobs, transforms and other commands with `invoke`, e.g. for a release |

- Steps say what they do: `map`, `filter`, `reject`, `flat_map`.
- Rejected records keep their reason; the engine counts records per step and reason.
- A failure policy per job decides whether a failing record stops the run or is skipped.
- Jobs read and write JSON Lines on stdin and stdout, so they chain with each other and with `jq`, `grep` or `sort`.
- `-w N` runs the steps in N processes, with the results in source order.
- `metacrunch trace` shows what each step does to a record; `Metacrunch::Testing` runs jobs in tests.
- `metacrunch new` creates a project, `metacrunch generate` jobs, transforms and commands in it, each with a test.
- One runtime dependency (`logger`).

> metacrunch 5 is a redesign. Jobs written for 4.x must be rewritten, see the [changelog](CHANGELOG.md).

## Installation

metacrunch 5 is not released yet; the latest version on RubyGems is 4.2.1. Until 5.0 is released, use it from Git
with Bundler:

```ruby
# Gemfile
gem "metacrunch", github: "ubpb/metacrunch", branch: "metacrunch-ng"
```

```
$ bundle install
$ bundle exec metacrunch --help
```

Requires Ruby 4.0. The commands in this Readme call `metacrunch`; with Bundler, prefix them with `bundle exec`.

JSON Lines is built in. Extension gems read and write other formats: `metacrunch-marc` (MARCXML, ISO 2709 and
MARC-in-JSON), `metacrunch-csv` (CSV) and `metacrunch-xlsx` (Excel files). They live in the same repository, share
metacrunch's version and come from the same Git source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git", branch: "metacrunch-ng" do
  gem "metacrunch"
  gem "metacrunch-csv"
end
```

`metacrunch-csv` and `metacrunch-xlsx`, together with `Metacrunch::Input` and `Metacrunch::Output`, replace the 4.x
gem `metacrunch-file`; `metacrunch-elasticsearch`, `metacrunch-db` and `metacrunch-redis` do not work with
metacrunch 5 yet. Any other source or sink is a small class of your own (see [Sources](docs/jobs.md#sources) and
[Sinks](docs/jobs.md#sinks)), built on `Metacrunch::Input` and `Metacrunch::Output`, which read gzip and tar and take
care of stdin, stdout and pipes (see [Files](docs/files.md)).

## Quickstart: a job

A job file is plain Ruby:

```ruby
# numbers.rb
Metacrunch.job "numbers" do
  params do
    param :factor, Integer, default: 2, desc: "Multiplier"
    args :numbers, min: 1, desc: "Numbers to process"
  end

  source params.numbers.map { Integer(it) }

  reject("Negative") { it.negative? }
  map { it * params.factor }
end
```

```
$ metacrunch run numbers.rb --factor 3 -- 1 2 -5
3
6
INFO  ok: read 3, written 2, rejected 1 (Negative: 1) in 0.00s (...)
```

A job without a sink writes its records to stdout as JSON Lines; logs and the summary go to stderr. A job without a
source reads JSON Lines from stdin, so jobs chain with each other and with other tools. In a checkout of this
repository:

```
$ metacrunch run examples/hello.rb | jq -c 'select(.name != "Grace")' | metacrunch run examples/normalize.rb
```

[`examples/`](examples) has more jobs with sample data, from the smallest one to a cleaning job with workers.

## Quickstart: a project

A project gives jobs, transforms and commands names, and `metacrunch` runs them by name from any of its directories:

```
$ metacrunch new catalog
$ cd catalog
$ bundle install
$ metacrunch generate job catalog:ids
$ printf '{"id":1,"title":"A"}\n{"title":"B"}\n' | metacrunch catalog:ids
{"id":1,"title":"A"}
INFO  ok: read 2, written 1, rejected 1 (No id: 1) in 0.00s (...)
$ rake test
```

`new` creates the project with a `Metacrunchfile`, a `Gemfile`, a `Rakefile` and a test that every file loads.
`generate` writes a job, transform, command, source or sink that runs right away, and a test that passes; the
generated job reads JSON Lines from stdin and rejects records without an `id`. `metacrunch --help` lists what the
project has. See [Projects, commands and gems](docs/projects.md).

## A tour

The examples use title records like those in [`examples/project`](examples/project): `{"id": "t1", "title": "Ruby
in Practice", "public": true}`.

### Sources, steps and sinks

```ruby
# jobs/catalog.rb
Metacrunch.job "catalog", desc: "Write the public titles" do
  params do
    param :input, String, default: root.join("data/titles.jsonl"), desc: "JSON Lines with title records"
    param :output, String, required: true, desc: "JSON Lines file for the public titles"
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }

  reject("Not public") { !it["public"] }
  map { |record| {"id" => record["id"], "title" => record.fetch("title")} }

  sink     Metacrunch::JsonLines::Writer.new(params.output)
  rejects  Metacrunch::JsonLines::ContextWriter.new("rejects.jsonl")
  failures Metacrunch::JsonLines::ContextWriter.new("failures.jsonl")
  on_failure :skip
end
```

| Step | The block returns | Effect |
|---|---|---|
| `map` | the new record (not `nil`) | 1:1 |
| `filter` | truthy to keep the record | 0..1 |
| `reject` | truthy to drop the record | 0..1 |
| `flat_map` | an Enumerable of records | 0..n |

- A source is any object with `#each`, a sink any object with `#write`; both may have `open` and `close`.
- `root` is the root of the project, so `root.join(...)` reaches its files from any directory.
- `filter` and `reject` with a reason, such as `"Not public"`, *reject* records: they are counted per reason and go
  to the `rejects` sink. Without a reason they are only *filtered*.
- `on_failure :skip` lets the run go on when a record fails (here: a record without a title); the record goes to
  the `failures` sink and the run ends with exit status 3. The default, `:abort`, stops at the first failure.
- A step that takes a second parameter gets the record's context, for notes (`ctx.mark`) and rejections
  (`ctx.reject!`) with a reason.

More in [Jobs](docs/jobs.md): records, the record context, batches, hooks and what runs when.

### Parameters and credentials

```ruby
params do
  param :output, String, required: true
  param :limit, Integer, default: 1000, env: "CATALOG_LIMIT"
  param :api_key, String, env: "CATALOG_API_KEY", credential: "catalog.api_key"
  args  :files, min: 1
end
```

A value comes from the command line (`--output out.jsonl`), else from the `env:` variable, else from the encrypted
credentials of the project (`metacrunch credentials edit`), else from the default. `metacrunch run JOB --help` lists
the parameters. See [Parameters](docs/jobs.md#parameters) and [Credentials](docs/credentials.md).

### Transforms

A transform is a named group of steps with parameters of its own, for steps that several jobs share:

```ruby
# transforms/normalize.rb
Metacrunch.transform "normalize", desc: "Tidy the titles, drop records without one" do
  params do
    param :max_length, Integer, default: 80
  end

  map { |record| record.merge("title" => record["title"].to_s.squeeze(" ").strip[0, params.max_length]) }
  reject("No title") { it["title"].empty? }
end
```

A job inserts its steps with `use "normalize", params: {max_length: 40}`. Alone, a transform reads JSON Lines from
stdin: `metacrunch run normalize < data/titles.jsonl`. See [Transforms](docs/transforms.md).

### Projects and commands

A project's `Metacrunchfile` loads its jobs, transforms and commands, which then run by name:

```ruby
# Metacrunchfile
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

A command is a Ruby body with parameters; `invoke` runs jobs, transforms and other commands and returns their result:

```ruby
# commands/catalog/release.rb
require "fileutils"

Metacrunch.command "catalog:release", desc: "Write a new release and switch out/current to it" do
  run do
    release = root.join("out/releases", Time.now.strftime("%Y%m%d-%H%M%S"))
    FileUtils.mkdir_p(release)
    result = invoke "catalog", params: {output: release.join("titles.jsonl")}
    next logger.warn("out/current not switched: #{result.status}") unless result.ok?

    link = root.join("out/current.new")
    FileUtils.rm_f(link)
    File.symlink(release, link)
    File.rename(link, root.join("out/current"))   # switches atomically
  end
end
```

```
$ metacrunch catalog:release
$ metacrunch --help                  # lists the jobs, transforms and commands
```

See [Projects, commands and gems](docs/projects.md): names, `metacrunch new` and `generate`, `invoke`, and jobs,
transforms and commands from gems.

### Testing

```ruby
# test/jobs/catalog_test.rb
require_relative "../test_helper"

class CatalogTest < Minitest::Test

  def test_writes_the_public_titles
    records = [{"id" => "t1", "title" => "A", "public" => true}, {"id" => "t2", "title" => "B", "public" => false}]
    result = Metacrunch::Testing.run(PROJECT, "catalog", params: {output: "unused"}, source: records)

    assert_equal [{"id" => "t1", "title" => "A"}], result.records
  end

end
```

`Testing.run` replaces the source by the records you give and the sinks by memory, so nothing is written.
`Testing.invoke` runs a command and records what it invokes instead of running it. See [Testing](docs/testing.md).

### Running, checking and tracing

```
$ metacrunch catalog --output out.jsonl                # by name, from any directory of the project
$ metacrunch run jobs/catalog.rb --output out.jsonl    # by path
$ metacrunch run -n 100 -w 4 catalog --output out.jsonl
$ metacrunch check catalog --output out.jsonl          # build the job, run nothing
$ metacrunch trace -n 2 catalog --output out.jsonl     # what each step does to the first 2 records
```

See [The command line](docs/cli.md) for all options, pipes and exit codes, and [Workers](docs/workers.md) for `-w`.

## Documentation

- [Jobs](docs/jobs.md): records, sources, steps, the record context, sinks, failures, hooks, parameters, what runs when
- [Files](docs/files.md): `Metacrunch::Input` and `Metacrunch::Output` for sources and sinks: gzip, tar, stdin, pipes
- [Transforms](docs/transforms.md): `use`, parameters, step names, testing a transform
- [Projects, commands and gems](docs/projects.md): the `Metacrunchfile`, names, `new` and `generate`, `invoke`
- [Testing](docs/testing.md): `Metacrunch::Testing.run` and `Metacrunch::Testing.invoke`
- [The command line](docs/cli.md): commands, options, pipes, `check` and `trace`, exit codes
- [Workers](docs/workers.md): parallel steps with `-w`
- [Credentials](docs/credentials.md): encrypted secrets for parameters
- [Running jobs from Ruby](docs/ruby-api.md): `Job#run` and `Project#invoke`
- [Examples](examples): runnable jobs and a project with sample data
- [Changelog](CHANGELOG.md)

## License

metacrunch is available under the [MIT license](License.txt).
