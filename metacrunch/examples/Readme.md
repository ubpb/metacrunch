# Examples

Runnable jobs with sample data. They need nothing but metacrunch. Run them from the root of the repository with
`bundle exec`, as below, so that they use the metacrunch of the checkout and not one installed as a gem. Every file
starts with a comment that says what it shows and how to call it.

| File | Shows |
|---|---|
| [`hello.rb`](hello.rb) | The smallest job: an Array as source, one step, JSON Lines on stdout. Executable through its `#!/usr/bin/env metacrunch` line. |
| [`catalog.rb`](catalog.rb) | The whole DSL: parameters, `reject` with a reason, `filter`, marks, `flat_map`, the `rejects` and `failures` sinks, `on_failure :skip`, an `after` hook, and a source of its own ([`lib/json_array_file.rb`](lib/json_array_file.rb)). |
| [`normalize.rb`](normalize.rb) | A filter job for Unix pipes: no source, no sink, JSON Lines from stdin to stdout. |
| [`sanitize.rb`](sanitize.rb) | Cleaning exported publication records: marks for every change, an issue report written by a sink that reads the marks ([`lib/issue_report.rb`](lib/issue_report.rb)), and workers (`-w`). |
| [`credentials/pseudonymize.rb`](credentials/pseudonymize.rb) | Encrypted credentials: a secret parameter (`credential:`) read from [`credentials/.metacrunch/`](credentials/.metacrunch), whose key is public on purpose, so the example runs. Replaces author names with keyed pseudonyms. |
| [`project/`](project) | A project: its [`Metacrunchfile`](project/Metacrunchfile) names its jobs, a transform and a command, so `metacrunch NAME` runs them from any directory of the project. The transform [`catalog:public`](project/transforms/catalog/public.rb) holds the steps that the jobs `catalog` and `catalog:ids` share with different values. The command `catalog:release` invokes the job `catalog` and switches `out/current` to the new release only after a clean run. [`project/test/`](project/test) mirrors the files, as `metacrunch generate` creates them: it tests the command with `Metacrunch::Testing.invoke`, the transform and the jobs with `Metacrunch::Testing.run`, and that every file loads. |
| [`test/catalog_test.rb`](test/catalog_test.rb) | Testing a job with `Metacrunch::Testing.run`, also with workers. |

```
$ mkdir -p tmp
$ bundle exec metacrunch run examples/hello.rb
$ bundle exec metacrunch run examples/catalog.rb --output tmp examples/data/catalog.json
$ bundle exec metacrunch trace -n 3 examples/catalog.rb --output tmp examples/data/catalog.json
$ bundle exec metacrunch run examples/hello.rb | bundle exec metacrunch run examples/normalize.rb
$ bundle exec metacrunch run -w 4 -i examples/data/publications.jsonl --rejects tmp/rejects.jsonl --failures tmp/failures.jsonl \
    examples/sanitize.rb --output tmp/publications.jsonl --issues tmp/issues.tsv
$ bundle exec metacrunch run -i examples/data/publications.jsonl examples/credentials/pseudonymize.rb | head -n 2
$ bundle exec metacrunch credentials show --credentials examples/credentials/.metacrunch
$ (cd examples/project && bundle exec metacrunch --help)
$ (cd examples/project && bundle exec metacrunch catalog:release)
$ (cd examples/project && bundle exec metacrunch catalog:ids)
$ (cd examples/project && bundle exec metacrunch catalog:public --fields id < data/titles.jsonl)
$ (cd examples/project && bundle exec rake)
$ bundle exec ruby -Ilib examples/test/catalog_test.rb
```

`catalog.rb` and `sanitize.rb` end with exit status 3 on the sample data: some records fail on purpose, and the
failure policy `on_failure :skip` sends them to the `failures` sink instead of stopping the run.

The sample data in [`data/`](data) is made up. `test/integration/examples_test.rb` runs every example, so they keep
working.
