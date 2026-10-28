# AGENTS.md

How work is done in this repository, for coding agents and for people. The [Readme](Readme.md) describes the gems
and the development commands; this file describes the process and the rules on top of them.

## The project

- A monorepo of Ruby gems: `metacrunch` (the core) and its extension gems, each in a directory of its own. All gems
  share one version (the file `VERSION`) and require Ruby 4.0.
- `master` holds metacrunch 5, a redesign that is not released yet. It need not stay compatible with 4.x, and 4.x
  names and concepts are no design criterion: weigh them on their own merits and against current tools. The released
  4.x code is maintained in the branch `4.x`.

## Sizing the work

| Size | For example | How |
|---|---|---|
| Quick | a typo, wording, a comment | Change it and run the checks. |
| Bug | wrong behaviour, a crash | Reproduce it with a failing test first, then fix it. |
| Small change | a new option, a message, a small refactoring | Agree on it in the conversation, then test first. No spec, no plan. |
| Project | a feature, an API change, a new gem, a change across components | The full process below. |

When unsure, take the larger size. Work that grows while it is done moves up a size. Every size works in a worktree
(see [Git](#git)); the final review belongs to projects, and your human partner may ask for one on smaller work.

## The full process

The person who directs the work (superpowers calls them "your human partner") approves the design section by section,
then the spec, then the plan. From the approved plan on, the work runs to the end without stopping: implementation,
review, fixes, report. The [superpowers](https://github.com/obra/superpowers) skills named in each phase carry out
the phases; where a skill and this file differ, this file wins.

1. **Design** (`brainstorming`). Find out what is wanted and why before proposing anything. Ask one question per
   message. Propose two or three approaches with a recommendation, with code previews where they help, and compare
   with similar tools (Catmandu, Metafacture, Traject, Kiba, Vector, Redpanda Connect, jq) where that helps. Present
   the design in sections; your human partner approves each section.
2. **Spec**: `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. It opens with the date, the branch and its base
   commit, the status and the ADRs it builds on, if any. Section 1 holds the context, goals, non-goals, success
   criteria and the decisions taken, and says whether one of them calls for an [ADR](#decisions); the last sections
   cover tests, documentation and what is deferred. Your human partner approves the spec before planning starts.
3. **Plan** (`writing-plans`): `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`. It names global constraints, a review
   focus (the spots most likely to go wrong), amendments to the spec found while planning, and tasks that are each
   one commit, test first. Your human partner approves the plan.
4. **Implementation** (`using-git-worktrees`, `test-driven-development`, `executing-plans`). Work in a worktree. Per
   task: a failing test, the code, the passing test, RuboCop, a commit. Keep a progress ledger in `.superpowers/`. A
   deviation from the plan or the spec goes back into the document. When your human partner picks
   `subagent-driven-development` instead, its review after each task comes on top of the final review.
5. **Review** (`requesting-code-review`, `receiving-code-review`). At the end, a fresh reviewer on the most capable
   model available reviews the whole branch against the spec and the plan. Check each finding before acting on it,
   and push back with reasons on a wrong one. Fix every Critical and Important finding, each test first. List the
   Minor findings in the report as deferred; fixing them is recommended, and your human partner decides. Record in the
   spec what the review changed.
6. **Finish** (`verification-before-completion`, `finishing-a-development-branch`). `bundle exec rake` in the root
   is green, and the [integration tests](#integration-tests) ran where they are due. Report the result, the fixed
   findings and the deferred minors to your human partner. Merging and pushing follow the rules under [Git](#git).

Spec and plan are working documents: git ignores `docs/superpowers/`, and they go with the worktree. Do not commit
them, not even with `git add -f`, although the `brainstorming` skill says to commit the spec. Code, comments, docs
and commit messages do not refer to them, since no one else can read them. What lasts is in the code and its tests,
the docs, the CHANGELOG, the commit messages and, for a central decision, an [ADR](#decisions). An open question in
design or planning can be settled with a throwaway prototype; what it teaches goes into the spec, the prototype is
not kept.

Gates: no code before the plan is approved, and no claim that something works or is done without a green run whose
output you have seen. Your human partner may waive single approvals for one piece of work ("confirm the plan
yourself"); that holds for this work only.

## Decisions

A central decision gets an Architecture Decision Record (ADR): `docs/decisions/NNNN-<title>.md`, numbered from 0001.
Central means that it shapes the project for a long time and that someone would otherwise ask again why: the
architecture, a concept of the public API, a dependency that is hard to replace, an approach that was dropped but keeps
coming up. Most decisions are not central; their why goes into the commit message.

- The spec says whether the work takes a central decision, and your human partner decides. The ADR is written in the
  branch that carries out the decision and is reviewed with it.
- An ADR is short, about a page. Its title states the decision; it gives the status and the date, the context, the
  decision, the alternatives considered and why they lost, and the consequences.
- An accepted ADR is not rewritten. A change of mind gets a new ADR, and the old one's status becomes "Superseded by
  NNNN".
- ADRs are public like the rest of the repository: generic, without internal names.

## Engineering rules

- Test everything: new and changed code is covered by tests, lines and branches. The tests use Minitest; a full run
  of a gem enforces 95 % line and 90 % branch coverage.
- RuboCop with `rubocop-ubpb` (`ruby.yml`), run through the Rake tasks (see the Readme).
- Prefer current best practice and modern Ruby over the style of older code.

## Integration tests

Gems that talk to a server (Elasticsearch, databases) test against real servers, started with Docker:

- The tests in the gem's `test/integration` run when an environment variable names the server
  (`ELASTICSEARCH_URL`) and skip otherwise, with a message that points to `test/compose.yml`.
- `test/compose.yml` starts the servers in the versions CI uses, with a project `name:` and host ports off the
  defaults (9208, 9209). The gem's Readme shows the commands under "Running the tests of this gem"; CI starts the
  same versions as service containers.
- Each test works on data of its own (unique index or table names, removed afterwards), so runs from parallel
  worktrees can share the servers. `up -d --wait` can be repeated; stop the servers with `down` only when no other
  work uses them.
- Run them locally when the branch changes a gem with integration tests (its code, tests, gemspec or lockfiles) or
  the metacrunch code such a gem builds on (sources, sinks, failure handling, params): once before the final review,
  and again on the rebased head before the merge if the rebase brought in new commits. Not after every TDD step, and
  not for changes elsewhere. When unsure, run them. CI runs them too, but only on pull requests and on `master`: for
  a branch merged locally, the local run is the only check before the merge.
- Where they are due, only a run against the servers verifies the change; skipped integration tests do not count.
  When they cannot run (no Docker, a port taken), say so instead of reporting the branch as verified. Your human
  partner may waive the run for one piece of work.

## Conventions

- Everything in the repository is in English: code, comments, docs, ADRs, CHANGELOGs, commit messages. So are specs
  and plans.
- Examples, docs, ADRs, templates, messages and comments are generic. Do not name internal tools, projects or
  institutions; library metadata (catalog records, MARC, ISBNs) is welcome. Specs and plans, which are not committed,
  are the exception: they may name the real projects a design was checked against.
- Docs change with the code, in the same branch: the gem's Readme and `docs/`, its examples and its `CHANGELOG.md`.
- A changed dependency in a gemspec changes lockfiles: run `bundle exec rake bundle` and commit every changed
  `Gemfile.lock`.
- One commit per topic. The subject is a sentence in the imperative that says what changes, without a type prefix or
  a final period ("Refuse a closed index when the writer opens"). The body says why, when the subject does not.

## Git

- Features are developed in parallel, each in its own worktree and branch.
- Work in a worktree under `.claude/worktrees/<name>` (ignored), created from `master`; Claude Code names its branch
  `worktree-<name>`. Set it up with `bundle install` and `bundle exec rake bundle`, and check the baseline with
  `bundle exec rake`.
- Never push and never merge unless your human partner asks for it; until then, worktree branches stay local.
- Keep the history of `master` linear. To merge a branch, rebase it onto the current `master` (never merge `master`
  into a branch), run `bundle exec rake` on the rebased head, then fast-forward `master` with `git merge --ff-only`.
  The branch's commits are kept, one per topic: no merge commits, no squashing.
- The maintainer merges into `master`. Contributors without push rights push their branch to a fork and open a pull
  request; CI runs on pull requests.
- Pull requests are merged the same way. The maintainer may squash a pull request whose commits are not one per topic.

## Commands

The Readme's Development section lists them. One test file of a gem, without the coverage check:

```
$ cd metacrunch
$ env -u COVERAGE bundle exec ruby -Ilib -Itest test/unit/engine_test.rb
```

## Claude Code

- `CLAUDE.md` imports this file, so Claude Code reads it whatever its version. Rules go into this file, not into
  `CLAUDE.md`. Personal instructions go into `CLAUDE.local.md` (ignored) or `~/.claude/CLAUDE.md`.
- `.claude/settings.json` turns on the superpowers plugin from the official marketplace but does not install it.
  Install it once with `/plugin install superpowers@claude-plugins-official`.
- Auto memory is personal. A rule for everyone belongs in this file.
