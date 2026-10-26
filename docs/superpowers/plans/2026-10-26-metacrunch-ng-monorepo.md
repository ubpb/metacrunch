# metacrunch monorepo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `metacrunch-ng` line of `ubpb/metacrunch` into one repository for core, metacrunch-csv,
metacrunch-xlsx and metacrunch-marc, with their history, one shared version, one CI and root tooling.

**Architecture:** Core moves into `metacrunch/` with `git mv`; the three gems are imported with `git filter-repo
--to-subdirectory-filter` and merged with `--allow-unrelated-histories`. Each gem keeps its own bundle and pins core
exactly; a small `Monorepo` module behind the root `Rakefile` runs tests, RuboCop and the version change over all
gems.

**Tech Stack:** Ruby 4.0.7, Bundler 4.0.20, Minitest, RuboCop with rubocop-ubpb, git filter-repo 2.47, GitHub
Actions.

**Spec:** `docs/superpowers/specs/2026-10-26-metacrunch-ng-monorepo-design.md` (amended with this plan)

## Global Constraints

- Branch `metacrunch-ng-monorepo` of the metacrunch repository, worktree
  `W=/Users/renspr/Code/Projects/upb/metacrunch/metacrunch/.claude/worktrees/metacrunch-ng-monorepo`. Never push.
- Sibling checkouts in `R=/Users/renspr/Code/Projects/upb/metacrunch` are read only: `metacrunch-csv` (`master`,
  6ac195d), `metacrunch-xlsx` (`master`, 05ef3ba), `metacrunch-marcxml` (`metacrunch-ng`, 12d559b).
- All gems: version `5.0.0.pre`; repository `https://github.com/ubpb/metacrunch`; release tags `v#{version}`.
- Gem directories: `metacrunch`, `metacrunch-csv`, `metacrunch-xlsx`, `metacrunch-marc`.
- Docs, comments and commit messages in English; Markdown and Ruby lines at most 120 characters.
- Ruby style of rubocop-ubpb: `["a", "b"]` instead of `%w[]`, `class Error < StandardError; end`, `it` as block
  parameter, a blank line after `class`/`module` and before their `end`, at most 3 assertions per test.
- Every commit message ends with these two lines after a blank line:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
  ```

- The worktree isolation refuses git commands that touch another repository; Task 2 leaves the worktree session.
- `bundle install` with `--prefer-local` where a lockfile is new, as in the prototype: it takes the installed
  versions, so RuboCop and its plugins are those the baseline was measured with.
- Shell state does not persist between Bash calls: set `W`, `R` and `I` again where a step uses them.

## Baseline

Measured on 2026-10-26 on fresh clones (`$CLAUDE_JOB_DIR/tmp/proto/base`); the file lists of `gem build` are in
`$CLAUDE_JOB_DIR/tmp/proto/baseline/<gem>.files` (metacrunch-marc: `metacrunch-marcxml.files`).

| Gem | Tests | Assertions | Line / branch coverage | RuboCop files | Files in the gem |
|---|---|---|---|---|---|
| metacrunch | 1127 | 2474 | 98.94 % / 96.70 % | 224 | 108 |
| metacrunch-csv | 119 | 211 | 100 % / 100 % | 23 | 10 |
| metacrunch-xlsx | 95 | 237 | 100 % / 100 % | 24 | 11 |
| metacrunch-marc | 379 | 980 | 100 % / 100 % | 60 | 30 |

## Review Focus

1. **A Gemfile that names only an extension gem in the Git block** (as the gem Readmes show) must get metacrunch
   from the same source. Task 8, step 3 (project `a`).
2. **The line `metacrunch new` writes** (`gem "metacrunch", github: …, branch: "metacrunch-ng"`) must still find
   core, now in a subdirectory. Task 8, step 3 (project `c`).
3. **CI runners on x86_64 Linux install with frozen lockfiles**: every committed lockfile must list a Linux platform.
   Task 4, step 4 and Task 5, step 1.
4. **`rake "version[X]"` when `bundle lock` fails in one gem** must stop with an error that names the gem. Task 5
   (`test_a_failing_bundle_lock_names_the_gem`).
5. **RuboCop in a gem directory** must use the gem's configuration although the root now has a `.rubocop.yml` and a
   `Gemfile`. Task 5, step 7 (counts of inspected files).

---

### Task 1: Move core into `metacrunch/`

**Files:**
- Move: `lib/ test/ exe/ bin/ bench/ examples/ metacrunch.gemspec Gemfile Gemfile.lock Rakefile .rubocop.yml
  .gitignore Readme.md CHANGELOG.md License.txt` → `metacrunch/`
- Move: `docs/*.md` → `metacrunch/docs/`
- Stay: `.github/`, `docs/superpowers/`, `.ruby-version`

**Interfaces:**
- Produces: core in `metacrunch/`, unchanged; every later task relies on this path.

- [ ] **Step 1: Move with `git mv` only**

```bash
cd "$W"
mkdir -p metacrunch/docs
git mv lib test exe bin bench examples metacrunch.gemspec Gemfile Gemfile.lock Rakefile .rubocop.yml .gitignore \
  Readme.md CHANGELOG.md License.txt metacrunch/
git mv docs/*.md metacrunch/docs/
git status --short | cut -c1-2 | sort | uniq -c
git ls-files | grep -v '^metacrunch/' | grep -v '^docs/superpowers/'
```

Expected: `273 R ` (renames only); the last command prints `.github/dependabot.yml`, `.github/workflows/ci.yml`
and `.ruby-version`.

- [ ] **Step 2: Run core's suite in its new place**

```bash
cd "$W/metacrunch" && bundle install --quiet && bundle exec rake
```

Expected: `1127 runs, 2474 assertions, 0 failures`, line coverage 98.94 %, branch coverage 96.70 %,
`224 files inspected, no offenses detected`.

- [ ] **Step 3: Commit**

```bash
cd "$W"
git commit -q -F - <<'EOF'
Move the core gem into metacrunch/

The first step to one repository for metacrunch and its extension gems: core moves with git mv only, so every file
is a rename. .github/, docs/superpowers/ and .ruby-version stay in the root.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
git show -M --stat HEAD | tail -1
```

Expected: `273 files changed, 0 insertions(+), 0 deletions(-)`.

---

### Task 2: Import the gems with their history

**Files:**
- Create (by merge): `metacrunch-csv/`, `metacrunch-xlsx/`, `metacrunch-marc/`
- Delete: `metacrunch-csv/.github/`, `metacrunch-xlsx/.github/`, `metacrunch-marc/.github/`
- Move: `metacrunch-marc/docs/superpowers/{specs,plans}/*` → `docs/superpowers/{specs,plans}/`

**Interfaces:**
- Consumes: core in `metacrunch/` (Task 1). The gems' Gemfiles still say
  `path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")`, which now finds core.
- Produces: the three gem directories with their files unchanged, and the tags `metacrunch-marcxml-v*`.

- [ ] **Step 1: Leave the worktree session**

Call `ExitWorktree` with `action: "keep"`. The commands below name the worktree with `git -C "$W"`.

- [ ] **Step 2: Check the sources and make filtered clones**

```bash
R=/Users/renspr/Code/Projects/upb/metacrunch
W=$R/metacrunch/.claude/worktrees/metacrunch-ng-monorepo
I=$CLAUDE_JOB_DIR/tmp/import
git -C $R/metacrunch-csv rev-parse --short master          # 6ac195d
git -C $R/metacrunch-xlsx rev-parse --short master         # 05ef3ba
git -C $R/metacrunch-marcxml rev-parse --short metacrunch-ng   # 12d559b
mkdir -p $I
git clone -q --no-local $R/metacrunch-csv $I/metacrunch-csv
git -C $I/metacrunch-csv filter-repo --to-subdirectory-filter metacrunch-csv
git clone -q --no-local $R/metacrunch-xlsx $I/metacrunch-xlsx
git -C $I/metacrunch-xlsx filter-repo --to-subdirectory-filter metacrunch-xlsx
git clone -q --no-local -b metacrunch-ng $R/metacrunch-marcxml $I/metacrunch-marc
git -C $I/metacrunch-marc filter-repo --to-subdirectory-filter metacrunch-marc --tag-rename '':'metacrunch-marcxml-'
git -C $I/metacrunch-marc tag | wc -l
```

Expected: the three short IDs as in the comments (stop if one differs: a source has moved on), each filter-repo run
ends with `Completely finished`, and 11 tags.

- [ ] **Step 3: Merge metacrunch-csv**

```bash
git -C "$W" fetch -q $I/metacrunch-csv master
git -C "$W" merge -q --allow-unrelated-histories --no-ff FETCH_HEAD -F - <<'EOF'
Import metacrunch-csv with its history

From the master branch of ubpb/metacrunch-csv (6ac195d); git filter-repo moved every path into metacrunch-csv/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

- [ ] **Step 4: Merge metacrunch-xlsx**

```bash
git -C "$W" fetch -q $I/metacrunch-xlsx master
git -C "$W" merge -q --allow-unrelated-histories --no-ff FETCH_HEAD -F - <<'EOF'
Import metacrunch-xlsx with its history

From the master branch of ubpb/metacrunch-xlsx (05ef3ba); git filter-repo moved every path into metacrunch-xlsx/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

- [ ] **Step 5: Merge metacrunch-marc with its tags**

The tags are fetched first, so that `FETCH_HEAD` holds only the branch.

```bash
git -C "$W" fetch -q $I/metacrunch-marc 'refs/tags/metacrunch-marcxml-*:refs/tags/metacrunch-marcxml-*'
git -C "$W" fetch -q $I/metacrunch-marc metacrunch-ng
git -C "$W" merge -q --allow-unrelated-histories --no-ff FETCH_HEAD -F - <<'EOF'
Import metacrunch-marc with its history

From the metacrunch-ng branch of ubpb/metacrunch-marcxml (12d559b), where metacrunch-marcxml became metacrunch-marc.
git filter-repo moved every path into metacrunch-marc/ and renamed the tags to metacrunch-marcxml-v*, because v3.0.0
and v3.1.0 are core's tags, too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
git -C "$W" tag -l 'metacrunch-marcxml-*' | wc -l
git -C "$W" rev-list --count HEAD
```

Expected: 11 tags, 862 commits (590 + spec + plan + move + 7 + 7 + 252 + 3 merges).

- [ ] **Step 6: Return to the worktree session**

Call `EnterWorktree` with `path: "$W"` (the absolute path from the Global Constraints).

- [ ] **Step 7: Remove the gems' workflows, move marc's specs and plans**

```bash
git rm -q -r metacrunch-csv/.github metacrunch-xlsx/.github metacrunch-marc/.github
git mv metacrunch-marc/docs/superpowers/specs/* docs/superpowers/specs/
git mv metacrunch-marc/docs/superpowers/plans/* docs/superpowers/plans/
find metacrunch-marc/docs -type d -empty -delete
git status --short
```

Expected: 3 deletions (`D  metacrunch-*/.github/workflows/ci.yml`) and 4 renames into `docs/superpowers/`
(`2026-10-12-marcxml-ng-design.md`, `2026-10-25-marc-design.md`, `2026-10-12-marcxml-ng.md`, `2026-10-26-marc.md`).

- [ ] **Step 8: Run the gems' suites**

```bash
for g in metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && bundle install --prefer-local --quiet && bundle exec rake 2>&1 | grep -E "runs,|^(Line|Branch) coverage|inspected"); done
```

Expected: the baseline per gem (119/211, 95/237, 379/980 runs/assertions; 100 % coverage; 23, 24, 60 files, no
offenses). `bundle install` writes `Gemfile.lock` files that the gems still ignore.

- [ ] **Step 9: Commit**

```bash
git commit -q -F - <<'EOF'
Remove the gems' workflows and move marc's specs and plans

GitHub reads workflows only from the root, where one workflow will test all gems. The specs and plans of
metacrunch-marc join the others in docs/superpowers/.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

---

### Task 3: One version, exact pins and gemspec links

**Files:**
- Create: `metacrunch/test/unit/gemspec_test.rb`, `metacrunch-csv/test/unit/gemspec_test.rb`,
  `metacrunch-xlsx/test/unit/gemspec_test.rb`, `metacrunch-marc/test/unit/gemspec_test.rb`
- Modify: the four gemspecs; `metacrunch-marc/lib/metacrunch/marc/version.rb`;
  `metacrunch-marc/test/unit/marc_test.rb` (remove `test_version`)

**Interfaces:**
- Produces: `Metacrunch::Marc::VERSION == "5.0.0.pre"`; every extension gemspec depends on
  `metacrunch = <its VERSION>`; metadata keys `source_code_uri`, `changelog_uri`, `bug_tracker_uri`.

- [ ] **Step 1: Write the gemspec test of core**

`metacrunch/test/unit/gemspec_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_constant
    assert_equal Metacrunch::VERSION, SPEC.version.to_s
  end

  def test_depends_on_no_other_metacrunch_gem
    assert_empty(SPEC.runtime_dependencies.select { it.name.start_with?("metacrunch") })
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
```

- [ ] **Step 2: Write the gemspec tests of the extension gems**

`metacrunch-csv/test/unit/gemspec_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch-csv.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_of_metacrunch
    assert_equal Metacrunch::Csv::VERSION, SPEC.version.to_s
    assert_equal Metacrunch::VERSION, Metacrunch::Csv::VERSION
  end

  def test_requires_metacrunch_in_exactly_its_own_version
    metacrunch = SPEC.runtime_dependencies.find { it.name == "metacrunch" }

    assert_equal Gem::Requirement.new("= #{SPEC.version}"), metacrunch.requirement
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch-csv", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch-csv/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
```

`metacrunch-xlsx/test/unit/gemspec_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch-xlsx.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_of_metacrunch
    assert_equal Metacrunch::Xlsx::VERSION, SPEC.version.to_s
    assert_equal Metacrunch::VERSION, Metacrunch::Xlsx::VERSION
  end

  def test_requires_metacrunch_in_exactly_its_own_version
    metacrunch = SPEC.runtime_dependencies.find { it.name == "metacrunch" }

    assert_equal Gem::Requirement.new("= #{SPEC.version}"), metacrunch.requirement
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch-xlsx", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch-xlsx/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
```

`metacrunch-marc/test/unit/gemspec_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test

  SPEC = Gem::Specification.load(File.expand_path("../../metacrunch-marc.gemspec", __dir__))
  REPOSITORY = "https://github.com/ubpb/metacrunch"

  def test_version_is_the_version_of_metacrunch
    assert_equal Metacrunch::Marc::VERSION, SPEC.version.to_s
    assert_equal Metacrunch::VERSION, Metacrunch::Marc::VERSION
  end

  def test_requires_metacrunch_in_exactly_its_own_version
    metacrunch = SPEC.runtime_dependencies.find { it.name == "metacrunch" }

    assert_equal Gem::Requirement.new("= #{SPEC.version}"), metacrunch.requirement
  end

  def test_homepage_and_issues_are_the_repository
    assert_equal REPOSITORY, SPEC.homepage
    assert_equal "#{REPOSITORY}/issues", SPEC.metadata["bug_tracker_uri"]
  end

  def test_links_point_to_the_release_tag_and_the_gem_directory
    assert_equal "#{REPOSITORY}/tree/v#{SPEC.version}/metacrunch-marc", SPEC.metadata["source_code_uri"]
    assert_equal "#{REPOSITORY}/blob/v#{SPEC.version}/metacrunch-marc/CHANGELOG.md", SPEC.metadata["changelog_uri"]
  end

end
```

- [ ] **Step 3: Run them to see them fail**

```bash
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && bundle exec ruby -Ilib -Itest test/unit/gemspec_test.rb 2>&1 | tail -1); done
```

Expected (without `COVERAGE` set, so no thresholds): metacrunch `4 runs, … 2 failures` (no `bug_tracker_uri`; the
links), csv and xlsx `3 failures` (pin, homepage, links), marc `4 failures` (version `"5.0.0.pre"` expected,
`"1.0.0.pre"` actual; pin; homepage; links).

- [ ] **Step 4: Change the gemspecs**

In all four gemspecs replace the homepage and the two metadata lines. Core (`metacrunch/metacrunch.gemspec`; its
homepage stays):

```ruby
  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
```

metacrunch-csv (`metacrunch-csv/metacrunch-csv.gemspec`), the changed lines:

```ruby
  spec.homepage = "https://github.com/ubpb/metacrunch"
```

```ruby
  spec.metadata = {
    "source_code_uri" => "#{spec.homepage}/tree/v#{spec.version}/metacrunch-csv",
    "changelog_uri" => "#{spec.homepage}/blob/v#{spec.version}/metacrunch-csv/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
```

```ruby
  spec.add_dependency "metacrunch", Metacrunch::Csv::VERSION
```

(replacing `spec.add_dependency "metacrunch", ">= 5.0.0.pre", "< 6"`). metacrunch-xlsx and metacrunch-marc: the same
with `metacrunch-xlsx` / `Metacrunch::Xlsx::VERSION` and `metacrunch-marc` / `Metacrunch::Marc::VERSION`; their
homepages are `https://github.com/ubpb/metacrunch-xlsx` and `https://github.com/ubpb/metacrunch-marc` today. The
order of the `add_dependency` lines stays.

- [ ] **Step 5: Give metacrunch-marc the shared version and drop its literal version test**

`metacrunch-marc/lib/metacrunch/marc/version.rb`: `VERSION = "1.0.0.pre"` → `VERSION = "5.0.0.pre"`.

`metacrunch-marc/test/unit/marc_test.rb`: remove these four lines (the method and the blank line after it):

```ruby
  def test_version
    assert_equal "1.0.0.pre", Metacrunch::Marc::VERSION
  end

```

- [ ] **Step 6: Run the suites**

```bash
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && bundle exec rake 2>&1 | grep -E "runs,|^(Line|Branch) coverage|inspected"); done
```

Expected: metacrunch 1131 runs (2481 assertions), csv 123 (218), xlsx 99 (244), marc 382 (986); coverage as in the
baseline; 225, 24, 25, 61 files, no offenses.

- [ ] **Step 7: Commit**

```bash
git add -A metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc
git status --short
git commit -q -F - <<'EOF'
Give all gems one version and pin core exactly

metacrunch-marc moves from 1.0.0.pre to 5.0.0.pre, and each extension gem requires metacrunch in exactly its own
version, so gems of different versions cannot be installed together. The gemspec links point to the release tag and
the gem's directory in this repository. A gemspec test in every gem checks the version, the pin and the links;
marc's test of the literal version goes, as it would break at every version change.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

Expected before the commit: 4 new test files, 4 gemspecs, marc's `version.rb` and `marc_test.rb`; no `Gemfile.lock`
(still ignored in the gems; core's did not change).

---

### Task 4: Load core from the repository, commit the lockfiles

**Files:**
- Modify: `metacrunch-csv/Gemfile`, `metacrunch-xlsx/Gemfile`, `metacrunch-marc/Gemfile`
- Modify: `metacrunch-csv/.gitignore`, `metacrunch-xlsx/.gitignore`, `metacrunch-marc/.gitignore`
- Create: `metacrunch-csv/Gemfile.lock`, `metacrunch-xlsx/Gemfile.lock`, `metacrunch-marc/Gemfile.lock`

**Interfaces:**
- Consumes: the exact pins (Task 3).
- Produces: committed lockfiles in every gem; the version task (Task 5) runs `bundle lock` on them.

- [ ] **Step 1: Point the Gemfiles at the repository's core**

In each of the three Gemfiles replace

```ruby
# metacrunch 5 is not released yet. METACRUNCH_PATH points to a checkout of
# its metacrunch-ng branch; by default it lies next to this repository.
gem "metacrunch", path: ENV.fetch("METACRUNCH_PATH", "../metacrunch")
```

with

```ruby
# The core gem lives next to this one in the monorepo.
gem "metacrunch", path: "../metacrunch"
```

- [ ] **Step 2: Stop ignoring the lockfiles**

Remove the line `Gemfile.lock` from `metacrunch-csv/.gitignore`, `metacrunch-xlsx/.gitignore` and
`metacrunch-marc/.gitignore`.

- [ ] **Step 3: Lock**

```bash
for g in metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && bundle install --prefer-local --quiet); done
(cd metacrunch-csv && bundle lock --add-platform x86_64-linux)
```

- [ ] **Step 4: Check the platforms and frozen installs**

```bash
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do echo "$g: $(sed -n '/^PLATFORMS/,/^$/p' $g/Gemfile.lock | grep -c 'x86_64-linux')"; done
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && BUNDLE_FROZEN=true bundle install --quiet && echo "$g frozen ok"); done
grep -n "metacrunch (" metacrunch-csv/Gemfile.lock
```

Expected: a count of at least 1 for every gem (`x86_64-linux`, or `x86_64-linux-gnu` and `-musl` in xlsx and marc,
where Bundler lists nokogiri's platforms); four `frozen ok`; `metacrunch (5.0.0.pre)` and `metacrunch (= 5.0.0.pre)`.

- [ ] **Step 5: See a version mismatch fail**

```bash
cd metacrunch-csv
sed -i '' 's/5.0.0.pre/5.0.1/' lib/metacrunch/csv/version.rb
bundle install 2>&1 | tail -2
git checkout -q lib/metacrunch/csv/version.rb
bundle install --quiet && cd ..
```

Expected: `So, because Gemfile depends on metacrunch-csv >= 0,` / `version solving has failed.`; after the restore
`bundle install` passes and `git status --short metacrunch-csv/lib` is empty.

- [ ] **Step 6: Run the suites**

```bash
for g in metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && bundle exec rake 2>&1 | grep -E "runs,|inspected"); done
```

Expected: 123, 99, 382 runs; 24, 25, 61 files, no offenses.

- [ ] **Step 7: Commit**

```bash
git add metacrunch-csv metacrunch-xlsx metacrunch-marc
git status --short
git commit -q -F - <<'EOF'
Load core from the repository and commit the gems' lockfiles

The gems take metacrunch from ../metacrunch for good; METACRUNCH_PATH and the second checkout in CI go. Their
lockfiles are committed like core's, so CI installs what was tested and Dependabot can update each gem.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

Expected before the commit: 3 Gemfiles, 3 `.gitignore`, 3 new `Gemfile.lock`.

---

### Task 5: Root tooling

**Files:**
- Create: `Gemfile`, `Gemfile.lock`, `Rakefile`, `rakelib/monorepo.rb`, `test/monorepo_test.rb`, `.rubocop.yml`,
  `.gitignore` (all in the root)

**Interfaces:**
- Consumes: the gem directories and their `version.rb` paths; the lockfiles (Task 4).
- Produces:
  - `Monorepo.gems(root = Dir.pwd) -> Array<String>`: gem directory names, `"metacrunch"` first, the others sorted.
  - `Monorepo.version_file(root, gem) -> String`: `<root>/<gem>/lib/<gem with "-" as "/">/version.rb`.
  - `Monorepo.set_version(version, root: Dir.pwd, lock: method(:bundle_lock)) -> void`; raises `ArgumentError`
    (`"not a version: #{version.inspect}"`) or `Monorepo::Error`.
  - `Monorepo.bundle_lock(dir) -> void`; raises `Monorepo::Error` (`"bundle lock failed in <gem>"`).
  - Rake tasks `bundle`, `test:tooling`, `test`, `rubocop:root`, `rubocop`, `version[X]`, `default`.

- [ ] **Step 1: The tooling bundle**

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

# The tooling of the repository (Rakefile, rakelib/). Each gem has a bundle of its own.
gem "minitest", ">= 5.25"
gem "rake", ">= 13.0"
gem "rubocop-ubpb", github: "ubpb/rubocop-ubpb", require: false
```

```bash
bundle install --prefer-local --quiet && bundle lock --add-platform x86_64-linux
sed -n '/^PLATFORMS/,/^$/p' Gemfile.lock
```

Expected: `arm64-darwin-23`, `ruby`, `x86_64-linux`.

- [ ] **Step 2: Write the failing test**

`test/monorepo_test.rb`:

```ruby
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../rakelib/monorepo"

class MonorepoTest < Minitest::Test

  VERSION_FILE = <<~RUBY
    # frozen_string_literal: true

    module Metacrunch
      module Fake

        VERSION = "5.0.0.pre"

      end
    end
  RUBY

  def setup
    @root = Dir.mktmpdir
    @locked = []
    @lock = ->(dir) { @locked << dir }
    ["metacrunch-xlsx", "metacrunch", "metacrunch-csv"].each { add_gem(it) }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_gems_are_the_directories_with_a_gemspec_of_their_name_core_first
    FileUtils.mkdir_p(File.join(@root, "docs"))
    write("other/something.gemspec", "")
    write("Rakefile", "")

    assert_equal ["metacrunch", "metacrunch-csv", "metacrunch-xlsx"], Monorepo.gems(@root)
  end

  def test_the_version_file_follows_the_gem_name
    assert_equal File.join(@root, "metacrunch/lib/metacrunch/version.rb"), Monorepo.version_file(@root, "metacrunch")
    assert_equal File.join(@root, "metacrunch-csv/lib/metacrunch/csv/version.rb"),
                 Monorepo.version_file(@root, "metacrunch-csv")
  end

  def test_set_version_writes_every_version_file
    Monorepo.set_version("5.1.0", root: @root, lock: @lock)

    assert_equal ["5.1.0"], Monorepo.gems(@root).map { version_of(it) }.uniq
  end

  def test_set_version_keeps_the_rest_of_the_file
    Monorepo.set_version("5.1.0.rc1", root: @root, lock: @lock)

    assert_equal VERSION_FILE.sub("5.0.0.pre", "5.1.0.rc1"), read("metacrunch-csv/lib/metacrunch/csv/version.rb")
  end

  def test_set_version_locks_every_gem_in_order_after_writing
    lock = ->(dir) { @locked << [File.basename(dir), version_of("metacrunch")] }
    Monorepo.set_version("5.1.0", root: @root, lock:)

    assert_equal [["metacrunch", "5.1.0"], ["metacrunch-csv", "5.1.0"], ["metacrunch-xlsx", "5.1.0"]], @locked
  end

  def test_a_version_that_is_not_canonical_is_refused_and_nothing_is_written
    [nil, "", " ", "5.1.0 ", "5.1.0-pre", "v5.1.0", "five", "5..1"].each do |version|
      error = assert_raises(ArgumentError) { Monorepo.set_version(version, root: @root, lock: @lock) }

      assert_equal "not a version: #{version.inspect}", error.message
    end
    assert_unchanged
  end

  def test_a_version_file_without_exactly_one_version_line_is_refused_and_nothing_is_written
    write("metacrunch-xlsx/lib/metacrunch/xlsx/version.rb", %(VERSION = "5.0.0.pre"\nVERSION = "5.0.0.pre"\n))

    error = assert_raises(Monorepo::Error) { Monorepo.set_version("5.1.0", root: @root, lock: @lock) }

    assert_equal "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb: expected one VERSION line, found 2", error.message
    assert_unchanged
  end

  def test_a_missing_version_file_is_refused_and_nothing_is_written
    FileUtils.rm(File.join(@root, "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb"))

    error = assert_raises(Monorepo::Error) { Monorepo.set_version("5.1.0", root: @root, lock: @lock) }

    assert_equal "metacrunch-xlsx/lib/metacrunch/xlsx/version.rb: no such file", error.message
    assert_unchanged
  end

  def test_a_failing_bundle_lock_names_the_gem
    write("metacrunch-csv/Gemfile", "raise \"broken\"\n")

    error = assert_raises(Monorepo::Error) do
      capture_subprocess_io { Monorepo.bundle_lock(File.join(@root, "metacrunch-csv")) }
    end

    assert_equal "bundle lock failed in metacrunch-csv", error.message
  end

  private

  def add_gem(name)
    write("#{name}/#{name}.gemspec", "")
    write(Monorepo.version_file(".", name), VERSION_FILE)
  end

  def version_of(gem)
    read(Monorepo.version_file(".", gem))[/VERSION = "(.*)"/, 1]
  end

  # Core comes first, so its file would be written first; the failing gem is the last one.
  def assert_unchanged
    assert_equal "5.0.0.pre", version_of("metacrunch")
    assert_empty @locked
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), text)
  end

  def read(path)
    File.read(File.join(@root, path))
  end

end
```

The broken `Gemfile` in the last test makes `bundle lock` fail in that directory, instead of searching upwards for
another `Gemfile`.

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec ruby test/monorepo_test.rb`
Expected: `cannot load such file -- …/rakelib/monorepo (LoadError)`.

- [ ] **Step 4: Write the module**

`rakelib/monorepo.rb` (a `.rb` file, so Rake does not load it by itself; the `Rakefile` requires it):

```ruby
# frozen_string_literal: true

require "bundler"

# The gems of this repository and their shared version (see the root Readme).
module Monorepo

  class Error < StandardError; end

  CORE = "metacrunch"
  VERSION_LINE = /^(\s*)VERSION = "[^"]*"$/

  module_function

  # The directories under root that hold a gemspec of their own name, core first, the others by name.
  def gems(root = Dir.pwd)
    names = Dir.children(root).select { File.file?(File.join(root, it, "#{it}.gemspec")) }
    names.sort_by { [it == CORE ? 0 : 1, it] }
  end

  # metacrunch: lib/metacrunch/version.rb; metacrunch-csv: lib/metacrunch/csv/version.rb
  def version_file(root, gem)
    File.join(root, gem, "lib", *gem.split("-"), "version.rb")
  end

  # Writes version into the version.rb of every gem, then calls lock with each gem's directory. Checks every
  # file before it writes one.
  def set_version(version, root: Dir.pwd, lock: method(:bundle_lock))
    raise ArgumentError, "not a version: #{version.inspect}" unless canonical?(version)

    texts = gems(root).to_h { [it, version_text(root, it)] }
    texts.each do |gem, text|
      File.write(version_file(root, gem), text.sub(VERSION_LINE, "\\1VERSION = \"#{version}\""))
    end
    texts.each_key { lock.call(File.join(root, it)) }
  end

  def canonical?(version)
    version.is_a?(String) && Gem::Version.correct?(version) && Gem::Version.new(version).to_s == version
  end

  def version_text(root, gem)
    path = version_file(root, gem)
    name = path.delete_prefix("#{root}/")
    raise Error, "#{name}: no such file" unless File.file?(path)

    text = File.read(path)
    count = text.scan(VERSION_LINE).size
    raise Error, "#{name}: expected one VERSION line, found #{count}" unless count == 1

    text
  end

  def bundle_lock(dir)
    locked = Bundler.with_unbundled_env { system("bundle", "lock", chdir: dir) }
    raise Error, "bundle lock failed in #{File.basename(dir)}" unless locked
  end

end
```

The replacement `"\\1VERSION = …"` keeps the indentation; `version` is canonical, so it holds no backslash.

- [ ] **Step 5: Run the test**

Run: `bundle exec ruby test/monorepo_test.rb`
Expected: `9 runs, 37 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 6: The Rakefile, RuboCop configuration and ignored files**

`Rakefile`:

```ruby
# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"
require_relative "rakelib/monorepo"

# Runs a command in the directory of every gem, with the gem's own bundle. The first failure stops.
def in_each_gem(*command)
  Monorepo.gems.each do |gem|
    puts "== #{gem}"
    Bundler.with_unbundled_env { sh(*command, chdir: gem) }
  end
end

desc "Install the bundle of every gem"
task :bundle do
  in_each_gem("bundle", "install")
end

namespace :test do
  Minitest::TestTask.create(:tooling) do |t|
    t.test_globs = ["test/**/*_test.rb"]
  end
end

desc "Run the tooling test and the tests of every gem"
task test: "test:tooling" do
  in_each_gem("bundle", "exec", "rake", "test")
end

# The gems have configurations of their own, so RuboCop in the root names the tooling files.
namespace :rubocop do
  RuboCop::RakeTask.new(:root) do |t|
    t.patterns = ["Gemfile", "Rakefile", "rakelib", "test"]
  end
end

desc "Run RuboCop on the root files and in every gem"
task rubocop: "rubocop:root" do
  in_each_gem("bundle", "exec", "rubocop")
end

desc 'Set the version of all gems, e.g. rake "version[5.1.0]"'
task :version, [:version] do |_task, args|
  Monorepo.set_version(args[:version])
end

task default: [:test, :rubocop]
```

`.rubocop.yml` (no `AllCops: Exclude`; see spec 5.3):

```yaml
inherit_gem:
  rubocop-ubpb: ruby.yml

Style/FrozenStringLiteralComment:
  Enabled: true
```

`.gitignore`:

```
.DS_Store
/.bundle/
/pkg/
/tmp/
```

- [ ] **Step 7: Lint, and check what RuboCop inspects**

```bash
bundle exec rake rubocop 2>&1 | grep -E "^== |inspected"
```

Expected: `4 files inspected, no offenses detected` (the root), then `== metacrunch` 225, `== metacrunch-csv` 24,
`== metacrunch-marc` 61, `== metacrunch-xlsx` 25 files, each without offenses. A count of 0 means a root
`AllCops: Exclude` reached the gems.

- [ ] **Step 8: Set the version for real, and back**

```bash
bundle exec rake "version[5.0.1]" > /dev/null
git status --short -- metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do (cd $g && BUNDLE_FROZEN=true bundle install --quiet && echo "$g frozen ok"); done
bundle exec rake "version[5.0.0.pre]" > /dev/null
git status --short -- metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc | wc -l
```

Expected: 8 modified files (four `version.rb`, four `Gemfile.lock`); four `frozen ok`; after the way back `0`.

- [ ] **Step 9: Run everything from the root**

Run: `bundle exec rake 2>&1 | grep -E "^== |runs,|^(Line|Branch) coverage|inspected"`
Expected: the tooling `9 runs`, then metacrunch 1131, metacrunch-csv 123, metacrunch-marc 382, metacrunch-xlsx 99
runs with the coverage of the baseline, then RuboCop as in step 7; exit status 0.

- [ ] **Step 10: Commit**

```bash
git add Gemfile Gemfile.lock Rakefile rakelib test .rubocop.yml .gitignore
git commit -q -F - <<'EOF'
Add the root tooling: test, lint and set the version of all gems

The Rakefile runs the tests and RuboCop of every gem with the gem's own bundle, and rake "version[X]" writes the
version of all gems and updates their lockfiles. The logic lives in rakelib/monorepo.rb with its test. RuboCop in the
root names its files: an AllCops Exclude of the gem directories in the root would reach the gems' own runs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

---

### Task 6: CI and Dependabot

**Files:**
- Modify: `.github/workflows/ci.yml`, `.github/dependabot.yml`

**Interfaces:**
- Consumes: `bundle exec rake test` and `bundle exec rubocop` in each gem; `rake test:tooling rubocop:root` in the
  root (Task 5).

- [ ] **Step 1: The workflow**

`.github/workflows/ci.yml` (the action pins are core's current ones):

```yaml
name: CI

on:
  push:
    branches: [master, metacrunch-ng]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    name: Test (${{ matrix.gem }}, Ruby ${{ matrix.ruby }}, ${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    continue-on-error: ${{ matrix.ruby == 'head' }}
    strategy:
      fail-fast: false
      matrix:
        gem: [metacrunch, metacrunch-csv, metacrunch-xlsx, metacrunch-marc]
        os: [ubuntu-latest, macos-latest]
        ruby: ["4.0", head]
    defaults:
      run:
        working-directory: ${{ matrix.gem }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
          working-directory: ${{ matrix.gem }}
      - run: bundle exec rake test

  lint:
    name: Lint (${{ matrix.gem }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        gem: [metacrunch, metacrunch-csv, metacrunch-xlsx, metacrunch-marc]
    defaults:
      run:
        working-directory: ${{ matrix.gem }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: "4.0"
          bundler-cache: true
          working-directory: ${{ matrix.gem }}
      - run: bundle exec rubocop

  tooling:
    name: Tooling
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ruby/setup-ruby@e81a8fa391b11a595c1b7ed84177cc0fe02faf83 # v1.328.0
        with:
          ruby-version: "4.0"
          bundler-cache: true
      - run: bundle exec rake test:tooling rubocop:root
```

- [ ] **Step 2: Dependabot**

`.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: bundler
    directories:
      - "/"
      - "/metacrunch"
      - "/metacrunch-csv"
      - "/metacrunch-xlsx"
      - "/metacrunch-marc"
    schedule:
      interval: weekly
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
```

- [ ] **Step 3: Check the YAML**

```bash
ruby -ryaml -e '
  w = YAML.load_file(".github/workflows/ci.yml"); YAML.load_file(".github/dependabot.yml")
  m = w["jobs"]["test"]["strategy"]["matrix"]
  puts "test: #{m.values.map(&:size).inject(:*)}, lint: #{w["jobs"]["lint"]["strategy"]["matrix"]["gem"].size}, tooling: 1"
  gems = Dir["*/*.gemspec"].map { File.dirname(it) }.sort
  abort "matrix #{m["gem"]} != #{gems}" unless m["gem"].sort == gems
  w["jobs"].each_value { |j| j["steps"].each { |s| abort "unpinned #{s["uses"]}" if s["uses"] && s["uses"] !~ /@\h{40}\z/ } }'
```

Expected: `test: 16, lint: 4, tooling: 1` and no abort.

- [ ] **Step 4: Commit**

```bash
git add .github
git commit -q -F - <<'EOF'
Run one CI for all gems

A matrix over gem, OS and Ruby tests every gem on every change, with the gem's own bundle; RuboCop runs per gem, and
the tooling job tests and lints the root. Dependabot updates the bundles of the root and of every gem.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

---

### Task 7: Documentation

**Files:**
- Create: `Readme.md`, `License.txt` (root)
- Modify: `metacrunch/Readme.md`, `metacrunch/docs/files.md`, `metacrunch/CHANGELOG.md`,
  `metacrunch-csv/Readme.md`, `metacrunch-csv/CHANGELOG.md`, `metacrunch-xlsx/Readme.md`,
  `metacrunch-xlsx/CHANGELOG.md`, `metacrunch-marc/Readme.md`, `metacrunch-marc/CHANGELOG.md`

- [ ] **Step 1: The root Readme**

`Readme.md`:

````markdown
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
````

- [ ] **Step 2: The root license**

```bash
cp metacrunch/License.txt License.txt
```

- [ ] **Step 3: Core's Readme and docs**

`metacrunch/Readme.md`, replace

```markdown
JSON Lines is built in. Extension gems for metacrunch 5, not released yet either, read and write other formats:
`metacrunch-marcxml` (MARCXML), `metacrunch-csv` (CSV) and `metacrunch-xlsx` (Excel files). The last two, together
with `Metacrunch::Input` and `Metacrunch::Output`, replace the 4.x gem `metacrunch-file`; `metacrunch-elasticsearch`,
`metacrunch-db` and `metacrunch-redis` do not work with metacrunch 5 yet. Any other source or sink is a small class of
```

with

````markdown
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
metacrunch 5 yet. Any other source or sink is a small class of
````

(the paragraph's last two lines, from `your own (see [Sources]…`, stay).

`metacrunch/docs/files.md`: `` `metacrunch-marcxml`, `metacrunch-csv` and `metacrunch-xlsx`. `` →
`` `metacrunch-marc`, `metacrunch-csv` and `metacrunch-xlsx`. ``

`metacrunch/CHANGELOG.md`, after `A redesign. Jobs written for 4.x must be rewritten; see the Readme and docs/.`
add a blank line and:

```markdown
The extension gems metacrunch-csv, metacrunch-xlsx and metacrunch-marc live in this repository and share
metacrunch's version.
```

- [ ] **Step 4: The gems' installation sections**

`metacrunch-csv/Readme.md`, replace

````markdown
```ruby
# Gemfile
gem "metacrunch-csv"
```

Requires Ruby 4.0 and metacrunch 5. The only other dependency is Ruby's [csv](https://github.com/ruby/csv) gem.
````

with

````markdown
metacrunch 5 and this gem are not released yet; until then they come from Git with Bundler, metacrunch from the
same source:

```ruby
# Gemfile
git "https://github.com/ubpb/metacrunch.git", branch: "metacrunch-ng" do
  gem "metacrunch-csv"
end
```

Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is Ruby's
[csv](https://github.com/ruby/csv) gem.
````

`metacrunch-xlsx/Readme.md`: the same block with `gem "metacrunch-xlsx"`; the old last sentence is
`` Requires Ruby 4.0 and metacrunch 5. The only other dependency is [zip_kit](https://github.com/julik/zip_kit), which ``
/ `writes the ZIP container.`, the new one:

```markdown
Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is
[zip_kit](https://github.com/julik/zip_kit), which writes the ZIP container.
```

`metacrunch-marc/Readme.md`: the same block with `gem "metacrunch-marc"`; the old last sentence is
`Requires Ruby 4.0 and metacrunch 5. The only other dependency is [Ox](https://github.com/ohler55/ox), for MARCXML.`,
the new one:

```markdown
Requires Ruby 4.0 and metacrunch in the same version as this gem. The only other dependency is
[Ox](https://github.com/ohler55/ox), for MARCXML.
```

- [ ] **Step 5: The links to core's docs**

`metacrunch-csv/Readme.md`, replace

```markdown
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs. gzip and tar archives are unpacked; every file in a tar archive has its own header
row. A byte order mark of the encoding (UTF-8, UTF-16LE, UTF-16BE) is removed. The progress display shows how much of
the files has been read.
```

with

```markdown
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/metacrunch/docs/files.md)): one target or an Array
of them — paths, `"-"` for stdin, or IOs. gzip and tar archives are unpacked; every file in a tar archive has its
own header row. A byte order mark of the encoding (UTF-8, UTF-16LE, UTF-16BE) is removed. The progress display shows
how much of the files has been read.
```

`metacrunch-marc/Readme.md`, replace

```markdown
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/docs/files.md)): one target or an Array of them —
paths, `"-"` for stdin, or IOs, which it does not close. gzip (all members, as `zcat` reads them) and tar archives
(every regular member, but not those whose names start with `.`) are detected by their content, whatever their names.
```

with

```markdown
[Files](https://github.com/ubpb/metacrunch/blob/metacrunch-ng/metacrunch/docs/files.md)): one target or an Array
of them — paths, `"-"` for stdin, or IOs, which it does not close. gzip (all members, as `zcat` reads them) and tar
archives (every regular member, but not those whose names start with `.`) are detected by their content, whatever
their names.
```

- [ ] **Step 6: The gems' CHANGELOGs**

Add a blank line and this paragraph after the introduction of `metacrunch-csv/CHANGELOG.md` (after `built on
smarter_csv.`), `metacrunch-xlsx/CHANGELOG.md` (after `caxlsx.`) and `metacrunch-marc/CHANGELOG.md` (after
`adapted; see the Readme.`):

```markdown
It lives in the metacrunch repository, shares metacrunch's version and requires metacrunch in exactly that version.
```

`metacrunch-marc/CHANGELOG.md`: `## 1.0.0 (unreleased)` → `## 5.0.0 (unreleased)`.

- [ ] **Step 7: Check lengths and links**

```bash
git add -A && git diff --cached -U0 | grep '^+' | grep -v '^+++' | ruby -ne 'puts "LONG: #{$_}" if $_.chomp.length > 121 && !$_.include?("badge")'
ruby -e 'Dir["**/*.md"].reject { it.start_with?("docs/superpowers") }.each { |f| File.read(f).scan(/\]\(([^)#]+)\)/).flatten.reject { it.start_with?("http") }.each { |l| puts "BROKEN #{f}: #{l}" unless File.exist?(File.join(File.dirname(f), l)) } }'
git diff --cached --stat | tail -1
```

Expected: no `LONG` line; `BROKEN` only for `metacrunch-marc/Readme.md: 35..37` and `: 6` (Ruby code such as
`&.[](6)`, not links); `11 files changed`.

- [ ] **Step 8: Commit**

```bash
git commit -q -F - <<'EOF'
Document the monorepo

A Readme in the root introduces the gems, the installation from Git, the shared version and the tasks. Core's Readme
and docs name metacrunch-marc and the shared repository; the gems' Readmes install from Git and link to core's docs in
their new place; the CHANGELOGs say where the gems live.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019w5MMFfHRsSd3PpSmNegRn
EOF
```

---

### Task 8: Final verification

No commit unless a check fails and needs a fix.

- [ ] **Step 1: Everything from the root**

Run: `bundle exec rake 2>&1 | grep -E "^== |runs,|^(Line|Branch) coverage|inspected"`
Expected: as in Task 5, step 9; exit status 0.

- [ ] **Step 2: The packages**

```bash
B=$CLAUDE_JOB_DIR/tmp/proto/baseline; O=$CLAUDE_JOB_DIR/tmp/final; mkdir -p $O
for g in metacrunch metacrunch-csv metacrunch-xlsx metacrunch-marc; do
  (cd $g && gem build --quiet $g.gemspec -o $O/$g.gem > /dev/null)
  ruby -rrubygems/package -e 'puts Gem::Package.new(ARGV[0]).spec.files.sort' $O/$g.gem > $O/$g.files
  b=$g; [ $g = metacrunch-marc ] && b=metacrunch-marcxml
  diff -q $B/$b.files $O/$g.files > /dev/null && echo "$g same ($(wc -l < $O/$g.files | tr -d ' '))" || diff $B/$b.files $O/$g.files
done
```

Expected: `same` for all four, with 108, 10, 11 and 30 files. If the baseline lists are gone, rebuild them from
fresh clones of the sources at the commits in the Global Constraints (core at 8af5d48).

- [ ] **Step 3: Bundler with the Git source**

```bash
W=$PWD; S=$CLAUDE_JOB_DIR/tmp/smoke; G=/Users/renspr/Code/Projects/upb/metacrunch/metacrunch; mkdir -p $S/a $S/b $S/c
printf 'source "https://rubygems.org"\n\ngit "file://%s", branch: "metacrunch-ng-monorepo" do\n  gem "metacrunch-csv"\nend\n' $G > $S/a/Gemfile
printf 'source "https://rubygems.org"\n\ngit "file://%s", branch: "metacrunch-ng-monorepo" do\n  gem "metacrunch"\n  gem "metacrunch-csv"\n  gem "metacrunch-xlsx"\n  gem "metacrunch-marc"\nend\n' $G > $S/b/Gemfile
printf 'source "https://rubygems.org"\n\ngem "metacrunch", git: "file://%s", branch: "metacrunch-ng-monorepo"\n' $G > $S/c/Gemfile
for v in a b c; do (cd $S/$v && BUNDLE_PATH=vendor bundle install --prefer-local --quiet && echo "$v bundled"); done
(cd $S/a && BUNDLE_PATH=vendor bundle exec ruby -e 'require "metacrunch/csv"; puts Metacrunch::VERSION')
(cd $S/c && BUNDLE_PATH=vendor bundle exec metacrunch --version)
cd $S/b
BUNDLE_PATH=vendor bundle exec ruby -e 'require "metacrunch"; require "metacrunch/csv"; require "metacrunch/xlsx"; require "metacrunch/marc"; puts [Metacrunch::VERSION, Metacrunch::Csv::VERSION, Metacrunch::Xlsx::VERSION, Metacrunch::Marc::VERSION].join(" ")'
BUNDLE_PATH=vendor bundle exec metacrunch run $W/metacrunch-csv/examples/csv2jsonl.rb $W/metacrunch-csv/examples/data/books.csv | head -1
BUNDLE_PATH=vendor bundle exec metacrunch run $W/metacrunch-marc/examples/marc2jsonl.rb $W/metacrunch-marc/examples/data/catalog.mrc | head -1
BUNDLE_PATH=vendor bundle exec metacrunch run $W/metacrunch-xlsx/examples/report.rb --target $S/report.xlsx $W/metacrunch-xlsx/examples/data/books.jsonl
file $S/report.xlsx
```

The Git source is the repository itself (`$G`), where the worktree's branch is visible; Bundler reads committed
state only. Expected: `a bundled`, `b bundled`, `c bundled`; `5.0.0.pre` twice; `5.0.0.pre 5.0.0.pre 5.0.0.pre
5.0.0.pre`; a JSON line with `"id":"1"`, one with `"id":"book-1"`; `ok: read 4, written 4`; `Microsoft Excel 2007+`.

- [ ] **Step 4: History**

```bash
git log --oneline -- metacrunch-marc/lib | tail -1
git log --oneline --follow -- metacrunch/lib/metacrunch.rb | tail -1
git tag -l 'metacrunch-marcxml-*' | wc -l
git log --oneline -- metacrunch-csv | wc -l
git log --oneline --first-parent 8af5d48..HEAD
git status --short | wc -l
```

Expected: `9920b57 Initial commit` (marcxml's first commit, rewritten), `815eb19 Initial commit for version 2.0`
(core's), 11 tags, at least 7 commits for csv, the first-parent line of this branch (spec, plan, move, three imports,
clean-up, version, lockfiles, tooling, CI, docs), and a clean tree (`0`).
