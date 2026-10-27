metacrunch
==========

[![CI](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml/badge.svg)](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml)

> **metacrunch 5 is not released yet.** `master` holds the 5.x line under development. The released version on
> RubyGems is metacrunch 4.2.1; its code is in the branch [`4.x`](https://github.com/ubpb/metacrunch/tree/4.x).

metacrunch is a small toolkit for data processing and ETL (extract, transform, load) in Ruby. A **job** reads records
from a **source**, passes them through **steps** and writes the results to a **sink**.

This repository holds metacrunch and its extension gems. Start with [metacrunch's Readme](metacrunch/Readme.md).

## Gems

| Gem | Directory | What it does |
|---|---|---|
| `metacrunch` | [`metacrunch/`](metacrunch) | jobs, sources, steps, sinks, projects and the command line; JSON Lines |
| `metacrunch-csv` | [`metacrunch-csv/`](metacrunch-csv) | a source and a sink for CSV |
| `metacrunch-xlsx` | [`metacrunch-xlsx/`](metacrunch-xlsx) | a sink that streams Excel files |
| `metacrunch-marc` | [`metacrunch-marc/`](metacrunch-marc) | MARCXML, ISO 2709 and MARC-in-JSON on one record model |
| `metacrunch-elasticsearch` | [`metacrunch-elasticsearch/`](metacrunch-elasticsearch) | a source, a bulk sink and index commands for Elasticsearch 8 and 9 |
| `metacrunch-db` | [`metacrunch-db/`](metacrunch-db) | a source and a sink for SQLite, PostgreSQL, MySQL and MariaDB |

## Installation

Until metacrunch 5 is released, the gems come from Git with Bundler. Name the gems you need:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git" do
  gem "metacrunch"
  gem "metacrunch-csv"
end
```

All gems require Ruby 4.0.

## Versioning

All gems share one version, and each extension gem requires metacrunch in exactly its own version: metacrunch-csv
5.1.0 requires metacrunch 5.1.0. The version is in the file [`VERSION`](VERSION) in the root.

To change it, edit `VERSION` and run `bundle exec rake version`. The task writes the version into the `version.rb` of
every gem, since an installed gem holds only its own directory, and updates the lockfiles. The tooling test fails
while a gem has a version other than the one in `VERSION`.

A release tags the repository once (`v5.1.0`) and publishes every gem, also one without changes; its CHANGELOG then
says `No changes.` Each gem keeps its CHANGELOG in its directory.

## Development

[AGENTS.md](AGENTS.md) describes how changes are designed, made and reviewed, for people and coding agents alike.

Each gem has a bundle of its own; the root's bundle holds the tooling. In the root:

```
$ bundle install
$ bundle exec rake bundle             # bundle install in every gem
$ bundle exec rake                    # all tests and RuboCop: the tooling, then every gem
$ bundle exec rake version            # write VERSION into every gem and update their lockfiles
```

One gem alone:

```
$ cd metacrunch-csv
$ bundle exec rake                    # its tests and RuboCop
```

Run RuboCop through these tasks: `bundle exec rubocop` in the root would check the gems with the root's bundle instead
of their own.

The lockfiles are committed, and CI installs them frozen. Every gem's lockfile records metacrunch as a path gem, so a
changed dependency in a gemspec, above all in metacrunch's, changes the lockfiles of the gems that load it: run
`bundle exec rake bundle` and commit every changed `Gemfile.lock`.

A gem may have further Gemfiles in `gemfiles/`: metacrunch-elasticsearch tests the client for Elasticsearch 8 with
`gemfiles/elasticsearch_8.gemfile`. `rake bundle`, `rake test` and `rake version` take them along; Dependabot updates
only `Gemfile.lock`, so after its updates `bundle exec rake bundle` brings the further lockfiles up to date.

Gems that talk to a server, such as metacrunch-elasticsearch, have integration tests that need the server: the gem's
`test/compose.yml` starts it with Docker, and the gem's Readme shows how to run them. Without the server they are
skipped. [AGENTS.md](AGENTS.md#integration-tests) says when they have to run before a merge.

## License

MIT. Each gem has its own `License.txt`; the root's [License.txt](License.txt) is metacrunch's.
