# metacrunch-ng, sub-project 13: one repository for metacrunch and its extension gems

- Date: 2026-10-26
- Branch: `metacrunch-ng-monorepo` of metacrunch (from `metacrunch-ng` 8af5d48)
- Status: approved design, not implemented; amended while planning after a prototype (4.1, 4.4, 5.1, 5.2, 5.3, 6, 7,
  8.1, 8.2)
- Builds on: [sub-project 12 spec](2026-10-25-metacrunch-ng-csv-xlsx-design.md) (metacrunch-csv, metacrunch-xlsx) and
  the metacrunch-marc spec (`2026-10-25-marc-design.md`, which this sub-project moves into this directory)

## 1. Context

metacrunch 5 is developed in four repositories:

| Gem | Repository | Branch, head | Version | Commits |
|---|---|---|---|---|
| metacrunch | ubpb/metacrunch | `metacrunch-ng`, 8af5d48 | 5.0.0.pre | 590 |
| metacrunch-csv | ubpb/metacrunch-csv | `master`, 6ac195d | 5.0.0.pre | 7 |
| metacrunch-xlsx | ubpb/metacrunch-xlsx | `master`, 05ef3ba | 5.0.0.pre | 7 |
| metacrunch-marc | ubpb/metacrunch-marcxml | `metacrunch-ng`, 12d559b | 1.0.0.pre | 252 |

The three extension gems depend on `metacrunch >= 5.0.0.pre, < 6`. Their Gemfiles load core from a checkout next to
them (`gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")`), and their CI checks out core's
`metacrunch-ng` branch as a second repository. This has costs:

- A change to core and a gem (sub-projects 10, 11 and 12 made such changes) is two commits in two repositories,
  pushed in the right order.
- Core's CI does not run the gems' tests. A core change that breaks a gem shows up in the gem's next CI run.
- Nothing says which versions belong together; `>= 5.0.0.pre, < 6` accepts any core 5.x.
- Core's docs name the gems and link across repositories.

This sub-project turns `ubpb/metacrunch` into the one repository of core and the three extension gems, on the branch
`metacrunch-ng` (`master` stays 4.x until the 5.0 release), and gives all gems one version, as Rails does with its
gems.

### 1.1 Goals

- Core, metacrunch-csv, metacrunch-xlsx and metacrunch-marc in one repository, each in a directory with its own
  gemspec, bundle, tests and docs, each with its full history.
- One version for all gems; every extension gem requires core in exactly its own version.
- One CI that tests every gem on every change.
- Tooling in the root that tests, lints and sets the version of all gems at once.

### 1.2 Non-goals

- Releasing to RubyGems. A release task (build, push, tag) comes with the 5.0 release.
- Pushing, archiving or renaming repositories on GitHub; the user does that (see 10).
- The 4.x gems metacrunch-elasticsearch, -db, -redis and -file, and the internal gems.
- Changes to the code or API of any gem.
- Rewriting paths in existing specs and plans; they are historical documents.

### 1.3 Success criteria

- `bundle exec rake` in each gem directory passes: the test count of the baseline (see 8.2) plus the new tests, the
  coverage the gem's `test_helper.rb` demands, no RuboCop offenses.
- `bundle exec rake` in the root passes: every gem as above, the tooling test, RuboCop on the root files.
- `gem build` in each gem directory packs the same files as before the move.
- A throwaway project whose Gemfile takes all four gems from a `git "file://…"` source on the branch bundles, requires
  them and runs a job.
- `git log -- metacrunch-marc/lib` reaches the metacrunch-marcxml 1.x commits; `git log --follow
  metacrunch/lib/metacrunch.rb` reaches commits before the move; the 11 tags of metacrunch-marcxml are present as
  `metacrunch-marcxml-v*`.
- The CI workflow is valid YAML. It runs green once the user pushes the branch.

### 1.4 Decisions

All five design sections were approved by the user on 2026-10-26.

- **Layout like Rails** (the user's choice): every gem is a directory of the root, core is `metacrunch/`, the root
  holds tooling only.
- **History** is imported with git filter-repo, tags of metacrunch-marcxml with the prefix `metacrunch-marcxml-`.
- **One version** for all gems, each extension gem pins core with `= VERSION`; one tag `vX.Y.Z` per release.
- **One bundle per gem**, plus a root bundle for the tooling; all lockfiles are committed.
- **One CI workflow**, a matrix over gem, OS and Ruby, without path filters.

Rejected alternatives:

- **Keeping four repositories:** the costs listed in 1.
- **Core in the root, gems in subdirectories:** the root would be core and family at once. Core's Rakefile, RuboCop
  configuration and Gemfile would have to exclude the gem directories and carry the family's tasks.
- **Importing without history** (a copy, or `git subtree add --squash`): loses `git log` and `git blame` of the gems.
  `git subtree add` without `--squash` keeps the commits but not their paths, so `git log -- metacrunch-csv/lib` would
  stop at the import.
- **A version per gem** (as today), or **RSpec's model** (major and minor shared, patch per gem, `~> 5.1.0`): needs a
  rule for which versions go together. With one version and an exact pin, wrong combinations cannot be installed. The
  costs of one version: releases without changes for some gems (Rails has them, too), and a major release of all gems
  for a breaking change in one of them.
- **One bundle for the whole repository** (Rails' root Gemfile): a runtime dependency missing from one gemspec goes
  unnoticed while another gem brings it in.
- **A RuboCop file in the root that every gem inherits:** its `Exclude` paths are relative to the root, and a file
  between the gems and rubocop-ubpb would share two settings. rubocop-ubpb's `ruby.yml` is the shared base already.
- **The version in one file** (a root `VERSION` read by every gemspec, like Rails' `RAILS_VERSION`): the gems need the
  constant at run time anyway, so each `version.rb` keeps a literal; the version task writes them, the exact pin and
  the gemspec tests check them.
- **Path filters in CI:** a core change has to test all gems anyway, and the repository is small.

## 2. Layout

```
metacrunch/                    repository root
├── Readme.md                  overview: gems, installation, versioning, development
├── License.txt                core's license, for GitHub
├── Gemfile, Gemfile.lock      tooling bundle (rake, minitest, rubocop-ubpb)
├── Rakefile                   bundle / test / rubocop / version over all gems
├── rakelib/monorepo.rb        the logic behind the tasks
├── test/monorepo_test.rb      its test
├── .rubocop.yml               for the root files only
├── .gitignore
├── .ruby-version              4.0.7, for all gems
├── .github/                   one CI workflow, Dependabot
├── docs/superpowers/          specs and plans of all gems
├── metacrunch/                core: lib, test, docs, examples, exe, bin, bench
├── metacrunch-csv/
├── metacrunch-xlsx/
└── metacrunch-marc/
```

Each gem directory holds its gemspec, `Gemfile`, `Gemfile.lock`, `Rakefile`, `.rubocop.yml`, `.gitignore`,
`Readme.md`, `CHANGELOG.md`, `License.txt`, `lib/`, `test/`, and its examples and benchmarks.

Core moves with `git mv` and nothing else in the same commit, so Git sees every file as a rename and core's commit IDs
stay:

| From the root of core | To |
|---|---|
| `lib/`, `test/`, `exe/`, `bin/`, `bench/`, `examples/`, `docs/*.md` | `metacrunch/` |
| `metacrunch.gemspec`, `Gemfile`, `Gemfile.lock`, `Rakefile`, `.rubocop.yml`, `.gitignore`, `Readme.md`, `CHANGELOG.md`, `License.txt` | `metacrunch/` |
| `.github/`, `docs/superpowers/`, `.ruby-version` | stay in the root |

Between this commit and the CI commit (see 9) the workflow in the root does not work; the branch is only merged
complete.

## 3. Importing the gems

Each gem is imported from a fresh clone in the job's temporary directory; the original repositories are only read:

```sh
git clone --no-local ../metacrunch-csv "$TMP/csv"
git -C "$TMP/csv" filter-repo --to-subdirectory-filter metacrunch-csv
git fetch "$TMP/csv" master
git merge --allow-unrelated-histories --no-ff FETCH_HEAD -m "Import metacrunch-csv with its history"
```

| Gem | Source | Directory | Tags |
|---|---|---|---|
| metacrunch-csv | `master` (6ac195d) | `metacrunch-csv/` | none |
| metacrunch-xlsx | `master` (05ef3ba) | `metacrunch-xlsx/` | none |
| metacrunch-marc | `metacrunch-ng` (12d559b) of metacrunch-marcxml | `metacrunch-marc/` | 11, renamed |

- filter-repo rewrites the paths of every commit, so `git log -- metacrunch-csv/lib` shows the gem's whole history.
  Authors and dates stay; commit IDs of the gems change. Old IDs in specs, plans and notes stay valid in the old
  repositories.
- metacrunch-marcxml's tags `v1.0.0` … `v3.1.0` collide with core's `v3.0.0` and `v3.1.0`. filter-repo renames them
  with `--tag-rename '':'metacrunch-marcxml-'`, the name of the gem when they were made, and they are fetched with
  `refs/tags/metacrunch-marcxml-*`. The tags `v1.3.0` and `v1.3.1` sit on the side branch `v1.3`; they come along, the
  branch does not.
- After the imports, one commit removes the gems' `.github/` directories (GitHub reads workflows from the root only)
  and moves metacrunch-marc's four specs and plans to `docs/superpowers/`. No file names collide.
- If the worktree's isolation refuses to clone a neighbouring repository, the clones are made outside the worktree.

## 4. Versioning

### 4.1 One version

- All four gems have the version `5.0.0.pre`. metacrunch-marc moves from `1.0.0.pre`; its CHANGELOG heading becomes
  `## 5.0.0 (unreleased)`. Its test of the literal version (`assert_equal "1.0.0.pre", Metacrunch::Marc::VERSION` in
  `marc_test.rb`) goes: a literal would break at every version change, and the gemspec test (8.1) checks the version.
- Each gem keeps a `version.rb` with a literal `VERSION`, at the path its name gives: `metacrunch` →
  `lib/metacrunch/version.rb`, `metacrunch-csv` → `lib/metacrunch/csv/version.rb`.
- One release tag for all gems, `vX.Y.Z`, continuing core's `v2.x` … `v4.x`.
- Each gem keeps its own CHANGELOG with the same version headings. A gem without changes in a release gets the entry
  `No changes.`

### 4.2 The exact pin

csv, xlsx and marc require core in exactly their own version:

```ruby
spec.add_dependency "metacrunch", Metacrunch::Csv::VERSION
```

No extension gem depends on another. Each gem bundle loads core through `path: "../metacrunch"`, so a version that
differs from core's fails `bundle install` in development and in CI; the gemspec tests (8.1) say so directly.

### 4.3 gemspec metadata

Like Rails, the links point to the release tag and the gem's directory (here metacrunch-csv):

```ruby
spec.homepage = "https://github.com/ubpb/metacrunch"
spec.metadata = {
  "source_code_uri" => "https://github.com/ubpb/metacrunch/tree/v#{spec.version}/metacrunch-csv",
  "changelog_uri" => "https://github.com/ubpb/metacrunch/blob/v#{spec.version}/metacrunch-csv/CHANGELOG.md",
  "bug_tracker_uri" => "https://github.com/ubpb/metacrunch/issues",
  "rubygems_mfa_required" => "true"
}
```

Core gets the same with `metacrunch`. Today csv and xlsx point to their own repositories, marc to `ubpb/metacrunch-marc`,
which does not exist, and core to `master`. `spec.files` stays as it is: its `Dir` patterns are relative to the gem's
directory, where `gem build` runs and where Bundler evaluates a gemspec.

### 4.4 The version task

`rake "version[5.1.0]"` in the root sets the version of all gems:

1. It refuses anything but a version in canonical form with an `ArgumentError`. `Gem::Version.correct?` alone accepts
   `nil`, `""`, surrounding whitespace and `"5.1.0-pre"` (which becomes `5.1.0.pre.pre`), so the task also demands
   a String with `Gem::Version.new(version).to_s == version`.
2. It rewrites `VERSION = "…"` in every gem's `version.rb`; a missing file or one without exactly one such line is a
   `Monorepo::Error`, and no file is written before all are checked.
3. It runs `bundle lock` in every gem directory, because each lockfile records the version of core (a path gem) and
   of the gem itself. If `bundle lock` fails in a gem, the task stops with a `Monorepo::Error` that names the gem;
   the version files are written by then, and running the task again after the fix completes it.

The gems are not listed by hand: `Monorepo.gems` finds every directory `<name>/<name>.gemspec` in the root, core
first, the others sorted by name. The logic is a small module in `rakelib/monorepo.rb` that the `Rakefile` requires;
`bundle lock` is passed in as a callable, so the test replaces it.

## 5. Development tooling

### 5.1 Bundles

- The extension gems load core from the repository, permanently:

  ```ruby
  # The core gem lives next to this one in the monorepo.
  gem "metacrunch", path: "../metacrunch"
  ```

  `METACRUNCH_PATH` and the second checkout in CI go away.
- Every `Gemfile.lock` is committed, as core does already (Bundler recommends this for gems, too). The gems'
  `.gitignore` files lose the line `Gemfile.lock`. Each lockfile must list a Linux platform for CI: metacrunch-csv
  and the root get `x86_64-linux` with `bundle lock --add-platform`, as core has; in metacrunch-xlsx and
  metacrunch-marc, whose development bundles hold nokogiri, Bundler lists all of nokogiri's platforms by itself.
  Each lockfile must also list `ruby`: on Ruby head the precompiled nokogiri does not fit (it requires `< 4.1.dev`),
  and a frozen install can compile it only from the source gem that `ruby` brings into the lockfile. Bundler did not
  add `ruby` in metacrunch-xlsx and metacrunch-marc, so they get it with `bundle lock --add-platform ruby` (found in
  the final review). A tooling test checks the platforms of every lockfile.
- The root `Gemfile` holds the tooling: `rake`, `minitest`, `rubocop-ubpb` (from GitHub, as in the gems).

### 5.2 Root Rakefile

| Task | Does |
|---|---|
| `rake bundle` | `bundle install` in every gem |
| `rake test:tooling` | the test of `rakelib/monorepo.rb` |
| `rake test` | `test:tooling`, then `bundle exec rake test` in every gem |
| `rake rubocop:root` | RuboCop on `Gemfile`, `Rakefile`, `rakelib/` and `test/` |
| `rake rubocop` | `rubocop:root`, then `bundle exec rubocop` in every gem |
| `rake` | `test` and `rubocop` |
| `rake "version[X]"` | see 4.4 |

The per-gem steps run in `Bundler.with_unbundled_env` in the gem's directory, so every gem uses its own bundle. Core
comes first. The first failing gem stops the task.

### 5.3 RuboCop

Every gem keeps its `.rubocop.yml` as it is. The root's `.rubocop.yml` inherits rubocop-ubpb's `ruby.yml` and enables
`Style/FrozenStringLiteralComment` like the gems, without `AllCops: Exclude`.

RuboCop adds the `AllCops: Exclude` of a `.rubocop.yml` in a parent directory to every configuration below it, up to
its project root, which is the topmost directory with a `Gemfile`: here the root. In the prototype, an `Exclude` of
the gem directories in the root made RuboCop inspect 0 files in every gem. So the root task names its files instead
(`Gemfile`, `Rakefile`, `rakelib`, `test`), and RuboCop in a gem directory uses the gem's configuration; the plan
checks the counts of inspected files.

`bundle exec rubocop` in the root is no entry point: it would check the gems with the root's bundle and RuboCop
version, and with the root as base directory it misses core's `AllCops: Exclude`. The root Readme says to use the
tasks.

### 5.4 Ignored files

Each gem keeps its `.gitignore`; patterns that start with `/` are relative to the gem's directory. The root's
`.gitignore` lists `.DS_Store`, `/.bundle/`, `/pkg/` and `/tmp/`.

## 6. CI and Dependabot

One workflow, `.github/workflows/ci.yml` (the name stays, so the badge stays):

```yaml
on:
  push:
    branches: [master, metacrunch-ng]
  pull_request:

jobs:
  test:      # 16 jobs
    strategy:
      fail-fast: false
      matrix:
        gem: [metacrunch, metacrunch-csv, metacrunch-xlsx, metacrunch-marc]
        os: [ubuntu-latest, macos-latest]
        ruby: ["4.0", head]
    continue-on-error: ${{ matrix.ruby == 'head' }}
    # checkout → setup-ruby (working-directory: the gem, bundler-cache) → bundle exec rake test in the gem
  lint:      # 4 jobs: bundle exec rubocop in each gem
  tooling:   # 1 job: bundle exec rake test:tooling rubocop:root in the root
```

The root is linted in the tooling job, because RuboCop in the root needs the task (see 5.3): 21 jobs in all.

The actions stay pinned to the commit IDs core uses; `permissions: contents: read` stays.

Dependabot updates `bundler` in `/`, `/metacrunch`, `/metacrunch-csv`, `/metacrunch-xlsx` and `/metacrunch-marc`
(`directories:`), and `github-actions` in `/`, weekly as today. Dependabot reads its configuration from the default
branch, so it applies once `metacrunch-ng` is merged into `master`, as core's configuration does today.

## 7. Documentation

- **Root `Readme.md`**, new and short: title, CI badge, two sentences from core's introduction; a table of the gems
  (gem, directory, purpose) with a link to `metacrunch/Readme.md` as the main documentation; installation from Git
  until the release, one block for all gems:

  ```ruby
  git "https://github.com/ubpb/metacrunch.git", branch: "metacrunch-ng" do
    gem "metacrunch"
    gem "metacrunch-csv"
  end
  ```

  versioning (one version, the exact pin, one tag, `No changes.`); development (`rake bundle`, `rake`, one gem with
  `cd metacrunch-csv && bundle exec rake`, `rake "version[X]"`); license (MIT, each gem has its own `License.txt`).
- **Root `License.txt`:** a copy of core's, so GitHub shows the license. In each gem's directory its own
  `License.txt` applies.
- **Core** (`metacrunch/Readme.md`, `metacrunch/docs/files.md`): `metacrunch-marcxml` (MARCXML) becomes
  `metacrunch-marc` (MARCXML, ISO 2709, MARC-in-JSON); the Readme adds that the gems live in the same repository and
  come from the same Git source. Relative links keep working; the badge link does not change.
- **Gem Readmes:** the installation shows the Git block until the release (today `gem "metacrunch-csv"`, which fails
  because nothing is released). The block names only the gem: a Git source serves every gem of its repository, also
  as a dependency, so metacrunch comes from the same source (tested in the prototype). Absolute links to core's docs gain the directory:
  `…/blob/metacrunch-ng/metacrunch/docs/files.md`. They stay absolute because the Readme is packed into the gem.
- **CHANGELOGs:** csv, xlsx and marc get one line each: the gem lives in the metacrunch repository, shares its version
  and requires metacrunch in exactly that version. Core's gets one line: the extension gems live in this repository
  and share its version.

## 8. Tests and verification

### 8.1 New tests

- **A gemspec test in every gem** (`test/unit/gemspec_test.rb`) loads the gem's own gemspec and checks:
  - its version is `Metacrunch::VERSION` and the gem's own `VERSION`;
  - its dependency on metacrunch is `= VERSION` (core: no dependency on another metacrunch gem);
  - `source_code_uri` and `changelog_uri` point to `v#{version}` and the gem's directory, `bug_tracker_uri` to the
    repository's issues.
- **metacrunch-marc:** its gemspec test fails on the version until the version changes; the literal version test
  goes (see 4.1).
- **The tooling test** (`test/monorepo_test.rb`, Minitest) works on a temporary directory with fake gems:
  - `Monorepo.gems` finds the gem directories, core first, and ignores directories without a gemspec of their name;
  - the version task rewrites every `version.rb` and calls the lock step once per gem, in order;
  - it refuses versions that are not canonical, a missing `version.rb` and one without exactly one `VERSION` line,
    and then writes nothing;
  - a failing `bundle lock` raises an error that names the gem.

### 8.2 Verification

1. **Baseline before the move:** per gem the test count, the coverage, the number of files RuboCop inspects, and the
   file list of `gem build`.
2. **After:** `bundle exec rake` in every gem and in the root passes (see 1.3).
3. **Packages:** `gem build` in every gem directory; the file lists equal the baseline.
4. **Git source:** throwaway projects on `git "file://<repository>", branch: "metacrunch-ng-monorepo"`: one with all
   four gems (`bundle install`, `require` of all four, the examples of csv, xlsx and marc run), one that names only
   metacrunch-csv in the block, and one with the line `metacrunch new` writes (`gem "metacrunch", git: …, branch: …`).
   This shows that Bundler finds gemspecs in subdirectories.
5. **History:** the checks in 1.3.
6. **CI:** a YAML syntax check locally (actionlint is not installed). The real run needs a push; the user pushes
   `metacrunch-ng-monorepo` before the fast-forward to see the 21 jobs.

## 9. Order of commits

1. This spec and the plan.
2. Move core to `metacrunch/` (`git mv` only).
3. Import metacrunch-csv.
4. Import metacrunch-xlsx.
5. Import metacrunch-marc.
6. Clean up after the imports (`.github/` of the gems, marc's specs and plans).
7. Versions, exact pins, gemspec metadata and gemspec tests (TDD).
8. Gemfiles and lockfiles.
9. Root tooling: `Gemfile`, `Rakefile`, `rakelib/monorepo.rb` with its test (TDD), `.rubocop.yml`, `.gitignore`.
10. CI and Dependabot.
11. Documentation.

## 10. After the merge (the user)

- Push `metacrunch-ng-monorepo` to see CI, then fast-forward `metacrunch-ng` and push it.
- Push the imported tags: `git push origin 'refs/tags/metacrunch-marcxml-*'`.
- Push metacrunch-marcxml's local `metacrunch-ng` (27 commits ahead of its origin) to its old repository before
  archiving it, so the commit IDs in specs and notes stay resolvable there.
- Archive `ubpb/metacrunch-csv`, `ubpb/metacrunch-xlsx` and `ubpb/metacrunch-marcxml` with a pointer to this
  repository. The planned rename of metacrunch-marcxml to metacrunch-marc is no longer needed.

## 11. Deferred

- A release task (build all gems, push them, one tag) with the 5.0 release.
- Moving further gems into this repository when they are migrated to metacrunch 5 (elasticsearch, db, redis).
