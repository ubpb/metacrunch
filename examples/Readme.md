# Examples

Runnable jobs with sample data. They need nothing but metacrunch. Run them from the root of the repository; in a
checkout, use `bundle exec exe/metacrunch` instead of `metacrunch`. Every file starts with a comment that says what it
shows and how to call it.

| File | Shows |
|---|---|
| [`hello.rb`](hello.rb) | The smallest job: an Array as source, one step, JSON Lines on stdout. Executable through its `#!/usr/bin/env metacrunch` line. |
| [`catalog.rb`](catalog.rb) | The whole DSL: parameters, `reject` with a reason, `filter`, marks, `flat_map`, the `rejects` and `errors` sinks, `on_error :skip`, an `after` hook, and a source of its own ([`lib/json_array_file.rb`](lib/json_array_file.rb)). |
| [`normalize.rb`](normalize.rb) | A filter job for Unix pipes: no source, no sink, JSON Lines from stdin to stdout. |
| [`sanitize.rb`](sanitize.rb) | Cleaning an RIS export like ris2fis: marks for every change, an issue report written by a sink that reads the marks ([`lib/issue_report.rb`](lib/issue_report.rb)), and workers (`-w`). |
| [`test/catalog_test.rb`](test/catalog_test.rb) | Testing a job with `Metacrunch::Testing.run`, also with workers. |

```
$ mkdir -p tmp
$ metacrunch run examples/hello.rb
$ metacrunch run examples/catalog.rb --output tmp examples/data/catalog.json
$ metacrunch trace -n 3 examples/catalog.rb --output tmp examples/data/catalog.json
$ metacrunch run examples/hello.rb | metacrunch run examples/normalize.rb
$ metacrunch run -w 4 -i examples/data/ris.jsonl --rejects tmp/rejects.jsonl --errors tmp/errors.jsonl \
    examples/sanitize.rb --output tmp/ris.jsonl --issues tmp/issues.tsv
$ bundle exec ruby -Ilib examples/test/catalog_test.rb
```

`catalog.rb` and `sanitize.rb` end with exit status 3 on the sample data: some records fail on purpose, and the
error policy `on_error :skip` sends them to the `errors` sink instead of stopping the run.

The sample data in [`data/`](data) is made up. `test/integration/examples_test.rb` runs every example, so they keep
working.
