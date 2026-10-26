# Transforms

A transform is a named group of steps with parameters of its own and without source or sink. Jobs insert it with
`use`; the job decides where the records come from, where they go and what failed records do.

```ruby
# transforms/normalize.rb
Metacrunch.transform "normalize", desc: "Tidy the titles, drop records without one" do
  params do
    param :max_length, Integer, default: 80, desc: "Cut titles after this many characters"
  end

  map { |record| record.merge("title" => record["title"].to_s.squeeze(" ").strip[0, params.max_length]) }
  reject("No title") { it["title"].empty? }
end
```

```ruby
# jobs/export.rb
Metacrunch.job "export", desc: "Write the public titles, tidied, as JSON Lines" do
  params do
    param :input, String, required: true
    param :output, String, required: true
    param :max_length, Integer
  end

  source Metacrunch::JsonLines::Reader.new(params.input), id: ->(record) { record["id"] }
  use "catalog:public", params: {fields: ["id", "title"]}
  use "normalize", params: {max_length: params.max_length}
  sink Metacrunch::JsonLines::Writer.new(params.output), batch: 1000
end
```

- A transform holds `params`, `map`, `filter`, `reject`, `flat_map`, `before`, `after` and `use`. `source`, `sink`,
  `rejects`, `failures`, `on_failure` and `profile` raise an `ArgumentError`: they belong to the job.
- `use` takes a name (in a project, see [Projects](projects.md)), a path or a transform
  object, and inserts the transform's steps and hooks where it stands. The hooks of a job and its transforms run in
  the order of their statements.
- A path loads the transform of its file. Like every relative path, it is relative to the working directory, so a job
  file that uses a transform next to it writes `use File.join(__dir__, "normalize.rb")`.
- A job file can keep a transform of its own as an object: `trim = Metacrunch.transform { map { ... } }` before the
  job, `use trim` inside it. The file still runs by path without `-j`, since transforms beside a single job or command
  count as its building blocks; leave such a transform unnamed and it takes no name in the project either.
- `params:` of `use` sets the transform's parameters, as Ruby values or as strings like on the command line;
  `nil` counts as not given. A parameter without a value comes from its `env:` variable, then from the credentials
  of the job, then its default. The steps and hooks of a transform see its own `params`, never the job's, and
  `root` is the root of the job's project.
- The steps get the transform's name as prefix, `normalize/map#1`, in stats, `trace`, `check`, errors and
  `ctx.step`; a second `use` of the same transform gives `normalize#2/...`. Generated step numbers count the
  statements of a recipe, `use` as one, so a transform that gains a step renames no step of the job. Explicit step
  names must not contain `/`.
- A transform may `use` other transforms; a cycle raises an `ArgumentError`.
- Transforms share their names with jobs and commands, so a transform and a job that runs it with a source of its own
  need two names. Name the transform after what it does and the job after what it produces, for example the transform
  `catalog:public` and the job `catalog`, as in [`examples/project`](../examples/project).
- Alone, a transform runs like a job without source and sink, from stdin to stdout:
  `metacrunch run normalize --max-length 20 < data/titles.jsonl`. `trace` and `check` take it, and
  `Metacrunch::Testing.run(transform, source: [...])` tests it (see [Testing](testing.md#testing-jobs-and-transforms)).

Compared with a [pipe](cli.md#pipes) between two jobs, the transforms of one job share the context of each record (id,
marks, rejections), one `rejects` and `failures` sink, one failure policy, one summary and one exit status, and the
records between them need not be JSON. Compared with step classes in plain Ruby, a transform has parameters and a
name in the project, and runs and tests on its own.
