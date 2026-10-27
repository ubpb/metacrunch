# Testing

`metacrunch/testing` runs jobs and transforms without I/O and commands without running what they invoke. A project
made by `metacrunch new` has the setup already: `test/test_helper.rb` loads the project as `PROJECT`,
`test/project_test.rb` checks that every file loads and every name is unique, `metacrunch generate` adds a test for
each file, and `rake test` runs them all.

| | Job, transform | Command |
|---|---|---|
| Method | `Testing.run` | `Testing.invoke` |
| Addressing | `(PROJECT, "name")`, or the object with `project:` | the same |
| Instead of I/O | `source:`, sinks in memory | `stubs:` for the names it invokes |
| Result | `records`, `rejects`, `failures`, `stats`, `status`, `ok?`, `error` | `value`, `invoked`, `status`, `ok?`, `error` |

Both bind `params:` like the values of `use` (see [Parameters](jobs.md#parameters)) and read neither environment
variables nor credentials. A default that refers to them fails, so a test passes the value:
`api_key: Testing reads no credentials; pass api_key in params:`.

## Testing jobs and transforms

```ruby
require "metacrunch/testing"

result = Metacrunch::Testing.run(
  Metacrunch.load_job("jobs/export.rb"),
  params: {input: "unused", output: "unused"},
  source: [{"id" => "t1", "title" => " A ", "public" => true}, {"id" => "t2", "title" => "B", "public" => false}]
)

result.records   # what reached the sink
result.rejects   # [[record, rejection], ...]
result.failures  # [[record, failure], ...]
result.stats
result.status    # :ok, :ok_with_failures or :aborted
result.ok?
```

All sinks are replaced by in-memory sinks; nothing is written. Component constructors should therefore be
cheap and free of side effects; do I/O in `open`, `each` and `write`. Required parameters still need a value,
even those that only the replaced source or sinks use; any value does, as `"unused"` above.

A transform is tested the same way, with `source:`, since it has none. A job or transform of a project is given by
the project and its name; names in `use` and `root` then resolve in that project. An object resolves them in
`project:`, else in the project of the nearest `Metacrunchfile` above the working directory, which is then loaded
for every run; a test class loads its project once:

```ruby
PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

result = Metacrunch::Testing.run(PROJECT, "catalog:public", params: {fields: ["id"]},
                                 source: [{"id" => "t1", "title" => "A", "public" => true}])
result.records            # [{"id" => "t1"}]

result = Metacrunch::Testing.run(PROJECT, "catalog", params: {output: "unused"})
result.stats.steps.keys   # ["catalog:public/reject#1", "catalog:public/map#2"]
```

The parameters of transforms get the values of `use` and their defaults; `Testing.run` reads neither the
environment nor credentials.

## Testing commands

```ruby
require "metacrunch/testing"

class ReleaseTest < Minitest::Test

  PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))

  def test_all_files_load_and_every_name_is_unique
    assert_empty PROJECT.load_errors
    assert_empty PROJECT.duplicates
  end

  def test_keeps_current_when_records_failed
    Dir.mktmpdir do |out|
      run = Metacrunch::Testing.invoke(PROJECT, "catalog:release", params: {out:},
                                       stubs: {"catalog" => :ok_with_failures})

      assert_equal [:ok_with_failures, ["catalog"]], [run.status, run.invoked.map(&:name)]
      refute_path_exists File.join(out, "current")
    end
  end

end
```

`Testing.invoke` runs the body with `params` bound from a Hash and records every `invoke` (`name`, `params`,
`options`) instead of running it. A stub answers with a status or a `Result` for a job, a value or a
`Metacrunch::CommandResult` (with `:ok` or `:ok_with_failures`) for a command, or a callable that gets the params;
without a stub a job ends `:ok` and a command returns a `CommandResult` with the value `nil`. A stubbed `:aborted`
raises like a real abort, an unknown name fails as in a real run, and credentials are never read. A stub for an
unknown name, or a job's stub that gives no status or `Result`, raises `ArgumentError`, so a mistake in the stubs
never passes for a failing command. `run.status` is `:ok`, `:ok_with_failures`, or `:aborted` with the exception in
`run.error`; `run.value` is what the body returned.

A command file outside a project is tested the same way: `Metacrunch.load_command("tools/release.rb")` loads it, and
`Metacrunch::Testing.invoke(command, params: {...}, stubs: {...})` runs it. Its names resolve in `project:`, else in
the project of the nearest `Metacrunchfile` above the working directory.

[`examples/project`](../examples/project) is a runnable project with a test.
