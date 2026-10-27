# Running jobs from Ruby

Jobs, transforms and commands also run from Ruby code, for example from a Rake task or an application, with the same
parameters as on the command line, given as `params: {...}`. For tests, see [Testing](testing.md).

```ruby
job = Metacrunch.load_job("jobs/catalog.rb")    # name: "catalog" selects one of several jobs
result = job.run(params: {output: "out"}, workers: 4, limit: 1000)

result.status    # :ok, :ok_with_failures or :aborted
result.ok?
result.error     # the error that aborted the run, or nil
result.summary   # "ok: read 1000, written 998, rejected 2 (Not public: 2) in 0.41s ..."
```

`run` takes the job's parameters as `params:` (see [Parameters](jobs.md#parameters)), the environment variables that
references read as `env:` (default `ENV`), and the [environment](environments.md) as `environment:` (default:
`METACRUNCH_ENV` of `env:`, else the default environment). Credentials follow `env:` as well
(`METACRUNCH_CREDENTIALS`, `METACRUNCH_MASTER_KEY`, `HOME`) and are searched from the job's file. A params file is a
command-line feature only: code passes its values in `params:`. Invalid values
and unreadable credentials raise `Metacrunch::ParamError`, unknown keys `ArgumentError`; errors while the job runs
end up in the result. A job defined with `Metacrunch.job` in a Rake task or an application runs the same way. Logs
go to `Metacrunch.logger` (stderr); assign another `Logger` or pass `logger:` to `run`.

Names in `use` and `root` resolve in `project:` (`job.run(params: {...}, project: Metacrunch.load_project)`), else
in the project of the nearest `Metacrunchfile` above the working directory, loaded when the first name needs it.
That lookup loads the `Metacrunchfile` again for every run; code that runs jobs again and again loads the project
once and passes it.
`Metacrunch.load_transform(path)` loads a transform as `load_job` loads a job.

```ruby
project = Metacrunch.load_project                          # the nearest Metacrunchfile above Dir.pwd
project.names                                              # ["catalog", "catalog:ids", "catalog:public", ...]
project.invoke("catalog:release", params: {out: "tmp"})    # a CommandResult, like invoke in a command
```

`project.invoke` returns a job's `Result` or a command's `CommandResult` (`status`, `ok?`, `value`) and raises
`Metacrunch::InvokeError` as `invoke` does (see [Commands](projects.md#commands)). It takes `params:`, `logger:`,
`env:`, `environment:`, `stdin:` and `stdout:`, and for a job `workers:` and `limit:` as `Job#run` does.
