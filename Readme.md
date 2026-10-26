metacrunch
==========

[![CI](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml/badge.svg)](https://github.com/ubpb/metacrunch/actions/workflows/ci.yml)

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

## Installation

metacrunch 5 is not released yet; until then the gems come from Git with Bundler. Name the gems you need:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git", branch: "metacrunch-ng" do
  gem "metacrunch"
  gem "metacrunch-csv"
end
```

All gems require Ruby 4.0.

## Versioning

All gems share one version, and each extension gem requires metacrunch in exactly its own version: metacrunch-csv
5.1.0 requires metacrunch 5.1.0. A release tags the repository once (`v5.1.0`) and publishes every gem, also one
without changes; its CHANGELOG then says `No changes.` Each gem keeps its CHANGELOG in its directory.

## Development

Each gem has a bundle of its own; the root's bundle holds the tooling. In the root:

```
$ bundle install
$ bundle exec rake bundle             # bundle install in every gem
$ bundle exec rake                    # all tests and RuboCop: the tooling, then every gem
$ bundle exec rake "version[5.1.0]"   # set the version of all gems and update their lockfiles
```

One gem alone:

```
$ cd metacrunch-csv
$ bundle exec rake                    # its tests and RuboCop
```

Run RuboCop through these tasks: `bundle exec rubocop` in the root would check the gems with the root's bundle instead
of their own.

## License

MIT. Each gem has its own `License.txt`; the root's [License.txt](License.txt) is metacrunch's.
