# metacrunch-ng generators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `metacrunch new` into `new DIR` (a project skeleton) and `generate KIND NAME|PATH` (a job, transform, command, source or sink with a test), and make command files testable by path.

**Architecture:** Pure generator units in `lib/metacrunch/generators/` compute what to write: `Target` maps a kind and a name or path to files and class names, `Files` and `Skeleton` render ERB templates from `lib/metacrunch/templates/`, `Plan` writes all or nothing. Thin CLI commands (`Cli::NewCommand`, `Cli::GenerateCommand`) parse, check the project before and after writing, and print. `Metacrunch.load_command` and `Testing.invoke(command)` close the testing gap for command files.

**Tech Stack:** Ruby 4.0, ERB and Prism (both shipped with Ruby), OptionParser, Minitest 6, RuboCop with rubocop-ubpb `ruby.yml`.

**Spec:** [docs/superpowers/specs/2026-10-18-metacrunch-ng-generators-design.md](../specs/2026-10-18-metacrunch-ng-generators-design.md) (amended from planning, see its section 1.4)

## Global Constraints

- Ruby `>= 4.0`; no new runtime dependency (ERB and Prism ship with Ruby; `erb` is a default gem).
- Repo docs, code comments, messages and commit messages in English; examples and templates use generic names only (no internal tool or institution names).
- `bundle exec rake` (tests + RuboCop) must stay green after every task; RuboCop config is rubocop-ubpb `ruby.yml` (double quotes, `[...]` arrays, `Layout/EmptyLinesAroundClassBody: empty_lines_except_namespace`, line length 120).
- Minitest; at most 3 assertions per test method (`Minitest/MultipleAssertions`); table tests use `define_method` per row.
- Coverage thresholds of full runs: 95 % lines, 90 % branches (baseline 851 runs, 98.88 % / 96.11 %).
- Messages are exactly those of spec sections 4.1, 4.2, 5.2 and 7.
- Generated files must pass rubocop-ubpb `ruby.yml` themselves (Task 9 checks it).
- One commit per task, imperative subject, body explaining why, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run single test files with `bundle exec ruby -Ilib -Itest test/path/to/file_test.rb` (add `-n /pattern/` for one test).
- Some test lines in this plan are longer than 120 characters; wrap them as RuboCop asks without changing what they assert.

## Review Focus

1. A source or sink named after a core class (`generate sink file`, `generate source dir`) must be refused, not reopen `File` and break every test that loads it — Task 1 (`ERRORS` rows) and Task 8 (CLI row).
2. `generate` run from a subdirectory of the project (`cd jobs && metacrunch generate job x`) must place the file below the root and print paths relative to the working directory — Task 8 (`test_a_name_goes_below_the_project_root`).
3. `--desc` with quotes, `#{`, or non-ASCII text must still give valid Ruby with that exact description — Task 4 (`test_desc_becomes_a_ruby_string`).
4. `generate ... --force` for a name declared in the very file being regenerated must overwrite it, not report "already declared" — Task 8 (`test_force_regenerates_the_file_that_declares_the_name`).
5. All generated tests of a project in one Ruby process (`rake test`) must not collide (test class names, `PROJECT`, constants) — Task 9 (`test_the_generated_tests_of_a_project_pass_in_one_run`).

---

### Task 1: Generators::Target

**Files:**
- Create: `lib/metacrunch/generators.rb`
- Create: `lib/metacrunch/generators/target.rb`
- Test: `test/unit/generators_target_test.rb`

**Interfaces:**
- Consumes: `Metacrunch::Names.valid?`, `Names.reserved?`, `Names.path?`, `Metacrunch::UsageError`, `Metacrunch::Project::FILE`.
- Produces:
  - `Metacrunch::Generators::KINDS` (`["job", "transform", "command", "source", "sink"]`), `KIND_LIST` (`"job, transform, command, source or sink"`), `DECLARED` (`["job", "transform", "command"]`), `DIRECTORIES` (kind → `"jobs"`, `"transforms"`, `"commands"`, `"lib"`).
  - `Generators.relative(path, dir) -> String` (path relative to dir).
  - `Generators::Target.for(kind, argument, cwd:, root:) -> Target`; `kind` must be one of `KINDS` (the CLI checks it); `root` is a `Pathname` or `nil`.
  - `Target` fields: `kind`, `form` (`:name`/`:path`), `argument`, `name`, `file` (String, absolute), `test` (String, absolute), `root` (Pathname or nil), `modules` (Array of String), `class_name` (String or nil), `test_class` (String); methods `declared?`, `constant` (`"Marc::Dump"`).

- [ ] **Step 1: Write the failing test**

`test/unit/generators_target_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "metacrunch/generators"

class GeneratorsTargetTest < Minitest::Test

  Target = Metacrunch::Generators::Target
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog/jobs"

  # kind, name => file, test, test class (below ROOT)
  NAMES = {
    ["job", "catalog:ids"] => ["jobs/catalog/ids.rb", "test/jobs/catalog/ids_test.rb", "CatalogIdsJobTest"],
    ["transform", "clean"] => ["transforms/clean.rb", "test/transforms/clean_test.rb", "CleanTransformTest"],
    ["command", "es:create-index"] => ["commands/es/create_index.rb", "test/commands/es/create_index_test.rb",
                                       "EsCreateIndexCommandTest"],
    ["job", "2go"] => ["jobs/2go.rb", "test/jobs/2go_test.rb", "Job2goTest"],
    ["source", "marc:dump"] => ["lib/marc/dump.rb", "test/lib/marc/dump_test.rb", "MarcDumpTest"],
    ["sink", "a:b:json_array"] => ["lib/a/b/json_array.rb", "test/lib/a/b/json_array_test.rb", "ABJsonArrayTest"]
  }.freeze

  # kind, path => file, test (relative to CWD), name, test class
  PATHS = {
    ["job", "tools/fix"] => ["tools/fix.rb", "test/fix_test.rb", "fix", "FixJobTest"],
    ["command", "../release.rb"] => ["../release.rb", "test/release_test.rb", "release", "ReleaseCommandTest"],
    ["sink", "lib/json_array.rb"] => ["lib/json_array.rb", "test/json_array_test.rb", "json_array", "JsonArrayTest"]
  }.freeze

  # kind, argument, root => message
  ERRORS = {
    ["job", "Catalog", ROOT] =>
      '"Catalog" is not a valid job name; use a-z, 0-9, _ and -, in parts separated by :',
    ["command", "run", ROOT] => '"run" is the name of a built-in command; choose another name',
    ["job", "jobs/MyJob.rb", nil] => 'MyJob.rb: "MyJob" is not a valid job name; use a-z, 0-9, _ and -',
    ["transform", "x/check.rb", nil] =>
      'check.rb: "check" is the name of a built-in command; choose another file name',
    ["source", "marc-dump", ROOT] =>
      '"marc-dump" is not a valid source name; use a-z, 0-9 and _, starting with a letter, in parts separated by :',
    ["sink", "a:2b", ROOT] =>
      '"a:2b" is not a valid sink name; use a-z, 0-9 and _, starting with a letter, in parts separated by :',
    ["sink", "lib/2b.rb", nil] => '2b.rb: "2b" is not a valid sink name; use a-z, 0-9 and _, starting with a letter',
    ["sink", "file", ROOT] => '"file" would reopen File; choose another name',
    ["source", "file:reader", ROOT] => '"file:reader" would reopen File; choose another name',
    ["source", "lib/dir.rb", nil] => '"dir" would reopen Dir; choose another name',
    ["job", "jobs/", nil] => "jobs/ is a directory; give a file name",
    ["job", "catalog:ids", nil] => "no Metacrunchfile found in /work/catalog/jobs or above; give a path " \
                                   "(./ids.rb) or create a project with metacrunch new"
  }.freeze

  NAMES.each do |(kind, name), (file, test, test_class)|
    define_method("test_#{kind}_#{name.tr(":-", "__")}_goes_below_the_root") do
      target = Target.for(kind, name, cwd: CWD, root: ROOT)

      assert_equal [ROOT.join(file).to_s, ROOT.join(test).to_s, test_class],
                   [target.file, target.test, target.test_class]
      assert_equal [:name, name, name, ROOT], [target.form, target.argument, target.name, target.root]
    end
  end

  PATHS.each do |(kind, path), (file, test, name, test_class)|
    define_method("test_#{kind}_path_#{name}_stays_where_it_is_given") do
      target = Target.for(kind, path, cwd: CWD, root: ROOT)

      assert_equal [File.expand_path(file, CWD), File.expand_path(test, CWD), name, test_class],
                   [target.file, target.test, target.name, target.test_class]
      assert_equal [:path, nil], [target.form, target.root]
    end
  end

  ERRORS.each_with_index do |((kind, argument, root), message), index|
    define_method("test_error_#{index}_#{kind}") do
      error = assert_raises(Metacrunch::UsageError) { Target.for(kind, argument, cwd: CWD, root:) }

      assert_equal message, error.message
    end
  end

  def test_a_path_keeps_its_argument_with_rb
    assert_equal "tools/fix.rb", Target.for("job", "tools/fix", cwd: CWD, root: nil).argument
  end

  def test_sources_and_sinks_are_constants_in_modules
    target = Target.for("source", "a:b:json_array", cwd: CWD, root: ROOT)

    assert_equal [["A", "B"], "JsonArray", "A::B::JsonArray"], [target.modules, target.class_name, target.constant]
    refute_predicate target, :declared?
  end

  def test_a_path_gives_a_class_without_modules
    target = Target.for("source", "lib/json_array.rb", cwd: CWD, root: nil)

    assert_equal [[], "JsonArray"], [target.modules, target.class_name]
  end

  def test_jobs_transforms_and_commands_have_no_constant
    target = Target.for("command", "catalog:release", cwd: CWD, root: ROOT)

    assert_equal [[], nil], [target.modules, target.class_name]
    assert_predicate target, :declared?
  end

  def test_a_source_may_go_into_an_existing_module
    assert_equal "Metacrunch::Lines", Target.for("source", "metacrunch:lines", cwd: CWD, root: ROOT).constant
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_target_test.rb`
Expected: FAIL with `cannot load such file -- metacrunch/generators` (LoadError).

- [ ] **Step 3: Write minimal implementation**

`lib/metacrunch/generators.rb`:

```ruby
# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"
require_relative "../metacrunch"

module Metacrunch
  # What `metacrunch new` and `metacrunch generate` create (see the Readme,
  # "Generating projects and files"): Target says where a file goes, Files
  # and Skeleton compute the files, Plan writes them.
  module Generators

    KINDS = ["job", "transform", "command", "source", "sink"].freeze
    KIND_LIST = "job, transform, command, source or sink"
    # The kinds that declare a name in the project; sources and sinks are
    # classes.
    DECLARED = ["job", "transform", "command"].freeze
    DIRECTORIES = {"job" => "jobs", "transform" => "transforms", "command" => "commands", "source" => "lib",
                   "sink" => "lib"}.freeze

    module_function

    # path relative to dir, for messages: "jobs/x.rb", "../jobs/x.rb".
    def relative(path, dir) = Pathname(path).relative_path_from(Pathname(dir)).to_s

  end
end

require_relative "generators/target"
```

`lib/metacrunch/generators/target.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Generators

    # The name of a source or sink, and one part of it: a Ruby constant in
    # snake case.
    COMPONENT_NAME = /\A[a-z][a-z0-9_]*(?::[a-z][a-z0-9_]*)*\z/
    COMPONENT_PART = /\A[a-z][a-z0-9_]*\z/

    # Where `metacrunch generate` puts a file and its test, and the names in
    # them; Target.for computes it.
    #
    # - form: :name (below the project root) or :path (as given)
    # - argument: the name, or the path with .rb, as given
    # - name: the declared name of a job, transform or command; the name or
    #   base name of a source or sink
    # - file, test: absolute paths
    # - root: the project root (a Pathname) for :name, else nil
    # - modules, class_name: the constant of a source or sink, else [] and
    #   nil
    # - test_class: the class of the test
    Target = Data.define(:kind, :form, :argument, :name, :file, :test, :root, :modules, :class_name,
                         :test_class) do
      class << self

        # The target of kind (one of KINDS) for argument: a path if it
        # contains / or ., else a name. cwd: the working directory. root:
        # the project root, nil without project; a path ignores it. Raises
        # UsageError for an invalid name and for a name without project.
        def for(kind, argument, cwd:, root:)
          Names.path?(argument) ? by_path(kind, argument, cwd) : by_name(kind, argument, cwd, root)
        end

        private

        # ":" separates directories; "-" becomes "_" in file names.
        def by_name(kind, name, cwd, root)
          check_name(kind, name)
          unless root
            raise UsageError, "no #{Project::FILE} found in #{cwd} or above; give a path " \
                              "(./#{name.split(":").last}.rb) or create a project with metacrunch new"
          end

          parts = name.split(":")
          base = File.join(DIRECTORIES.fetch(kind), *parts.map { it.tr("-", "_") })
          build(kind, :name, name, name, parts, file: root.join("#{base}.rb"),
                                                test: root.join("test", "#{base}_test.rb"), root:)
        end

        def by_path(kind, path, cwd)
          raise UsageError, "#{path} is a directory; give a file name" if path.end_with?("/")

          path = "#{path}.rb" unless path.end_with?(".rb")
          base = File.basename(path, ".rb")
          check_file_name(kind, File.basename(path), base)
          build(kind, :path, path, base, [base], file: File.expand_path(path, cwd),
                                                 test: File.expand_path(File.join("test", "#{base}_test.rb"), cwd),
                                                 root: nil)
        end

        def build(kind, form, argument, name, parts, file:, test:, root:)
          constants = DECLARED.include?(kind) ? [] : parts.map { camel(it) }
          check_constant(name, constants) if constants.any?
          new(kind:, form:, argument:, name:, file: file.to_s, test: test.to_s, root:, modules: constants[0...-1],
              class_name: constants.last, test_class: test_class(kind, name, constants))
        end

        def check_name(kind, name)
          if DECLARED.include?(kind)
            unless Names.valid?(name)
              raise UsageError, "#{name.inspect} is not a valid #{kind} name; use a-z, 0-9, _ and -, " \
                                "in parts separated by :"
            end
            if Names.reserved?(name)
              raise UsageError, "#{name.inspect} is the name of a built-in command; choose another name"
            end
          elsif !COMPONENT_NAME.match?(name)
            raise UsageError, "#{name.inspect} is not a valid #{kind} name; use a-z, 0-9 and _, " \
                              "starting with a letter, in parts separated by :"
          end
        end

        def check_file_name(kind, file, base)
          if DECLARED.include?(kind)
            unless Names.valid?(base)
              raise UsageError, "#{file}: #{base.inspect} is not a valid #{kind} name; use a-z, 0-9, _ and -"
            end
            if Names.reserved?(base)
              raise UsageError, "#{file}: #{base.inspect} is the name of a built-in command; " \
                                "choose another file name"
            end
          elsif !COMPONENT_PART.match?(base)
            raise UsageError, "#{file}: #{base.inspect} is not a valid #{kind} name; use a-z, 0-9 and _, " \
                              "starting with a letter"
          end
        end

        # A source or sink must not reopen a class of Ruby or metacrunch;
        # a module may hold it ("metacrunch:lines").
        def check_constant(name, constants)
          top = constants.first
          return unless Object.const_defined?(top, false)
          return if constants.size > 1 && !Object.const_get(top, false).is_a?(Class)

          raise UsageError, "#{name.inspect} would reopen #{top}; choose another name"
        end

        def camel(part) = part.split("_").map(&:capitalize).join

        # "CatalogIdsJobTest"; "Job2goTest", since a constant starts with a
        # letter; "MarcDumpTest" for a source or sink.
        def test_class(kind, name, constants)
          return "#{constants.join}Test" if constants.any?

          words = name.split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
          words.match?(/\A[A-Z]/) ? "#{words}#{kind.capitalize}Test" : "#{kind.capitalize}#{words}Test"
        end

      end

      # A job, transform or command, not a source or sink.
      def declared? = DECLARED.include?(kind)

      # The constant of a source or sink: "Marc::Dump".
      def constant = [*modules, class_name].join("::")
    end

  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_target_test.rb`
Expected: PASS (all runs, 0 failures). Then `bundle exec rubocop lib/metacrunch/generators.rb lib/metacrunch/generators test/unit/generators_target_test.rb` — no offenses (fix layout if RuboCop asks, without changing behavior).

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/generators.rb lib/metacrunch/generators/target.rb test/unit/generators_target_test.rb
git commit -m "Map generate's kinds and names to files and classes

Generators::Target says where metacrunch generate puts a file and its
test: a name below the project root with : as directories and - as _
in file names, a path as given. It checks names, refuses names without
a project, and keeps sources and sinks from reopening classes such as
File.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Template and Plan

**Files:**
- Create: `lib/metacrunch/generators/template.rb`
- Create: `lib/metacrunch/generators/plan.rb`
- Modify: `lib/metacrunch/generators.rb` (two `require_relative` lines at the end)
- Test: `test/unit/generators_template_test.rb`, `test/unit/generators_plan_test.rb`

**Interfaces:**
- Consumes: `Generators.relative`, `Metacrunch::UsageError`.
- Produces:
  - `Generators::Template::DIR` (absolute path of `lib/metacrunch/templates`).
  - `Template.render(path, **locals) -> String` (path relative to `DIR` or absolute; ERB `trim_mode: "-"`).
  - `Template.nest(code, modules) -> String` (wraps all lines after the preamble — magic comment, `require` lines, blank lines — in `module X` per element of modules, outermost first).
  - `Generators::Plan.new`, `#add(path, content, executable: false) -> self`, `#entries -> Array<Plan::Entry>` (`Entry` has `path`, `content`, `executable`), `#write(force:, out:, cwd:) -> nil` (raises `UsageError` "A, B already exist; use --force to overwrite" before writing anything).

- [ ] **Step 1: Write the failing tests**

`test/unit/generators_template_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsTemplateTest < Minitest::Test

  Template = Metacrunch::Generators::Template

  CLASS = <<~RUBY
    # frozen_string_literal: true

    require "json"

    # A sink.
    class Dump

      def write(record) = record

    end
  RUBY

  def test_renders_locals_and_trims_lines
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.rb.erb")
      File.write(path, "<%- if loud -%>\nputs <%= name.inspect %>\n<%- end -%>\n")

      assert_equal %(puts "catalog:ids"\n), Template.render(path, name: "catalog:ids", loud: true)
    end
  end

  def test_templates_live_below_lib
    assert_equal File.expand_path("../../lib/metacrunch/templates", __dir__), Template::DIR
  end

  def test_nests_all_but_the_preamble_in_modules
    assert_equal <<~RUBY, Template.nest(CLASS, ["Marc", "Records"])
      # frozen_string_literal: true

      require "json"

      module Marc
        module Records
          # A sink.
          class Dump

            def write(record) = record

          end
        end
      end
    RUBY
  end

  def test_no_modules_leave_the_code_alone
    assert_equal CLASS, Template.nest(CLASS, [])
  end

end
```

`test/unit/generators_plan_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsPlanTest < Minitest::Test

  Plan = Metacrunch::Generators::Plan

  def test_writes_files_with_directories_and_reports_them
    in_tmpdir do |dir|
      out = StringIO.new
      plan(dir).write(force: false, out:, cwd: File.join(dir, "jobs").tap { FileUtils.mkdir_p(it) })

      assert_equal "created a/x.rb\ncreated ../test/x_test.rb\n", out.string
      assert_equal ["x = 1\n", "test\n"], [File.read(File.join(dir, "jobs/a/x.rb")), File.read(File.join(dir, "test/x_test.rb"))]
    end
  end

  def test_executable_files_get_mode_0755
    in_tmpdir do |dir|
      plan(dir).write(force: false, out: StringIO.new, cwd: dir)

      assert_equal [0o755, false], [File.stat(File.join(dir, "jobs/a/x.rb")).mode & 0o777,
                                    File.executable?(File.join(dir, "test/x_test.rb"))]
    end
  end

  def test_refuses_existing_files_and_writes_none
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      File.write(File.join(dir, "test/x_test.rb"), "mine")
      error = assert_raises(Metacrunch::UsageError) { plan(dir).write(force: false, out: StringIO.new, cwd: dir) }

      assert_equal "test/x_test.rb already exists; use --force to overwrite", error.message
      refute_path_exists File.join(dir, "jobs/a/x.rb")
    end
  end

  def test_names_every_existing_file
    in_tmpdir do |dir|
      plan(dir).write(force: false, out: StringIO.new, cwd: dir)
      error = assert_raises(Metacrunch::UsageError) { plan(dir).write(force: false, out: StringIO.new, cwd: dir) }

      assert_equal "jobs/a/x.rb, test/x_test.rb already exist; use --force to overwrite", error.message
    end
  end

  def test_force_overwrites
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test"))
      File.write(File.join(dir, "test/x_test.rb"), "mine")
      plan(dir).write(force: true, out: StringIO.new, cwd: dir)

      assert_equal "test\n", File.read(File.join(dir, "test/x_test.rb"))
    end
  end

  private

  def plan(dir)
    Plan.new.add(File.join(dir, "jobs/a/x.rb"), "x = 1\n", executable: true).add(File.join(dir, "test/x_test.rb"), "test\n")
  end

  def in_tmpdir
    Dir.mktmpdir { |dir| yield File.realpath(dir) }
  end

end
```

(Wrap any line RuboCop finds longer than 120 characters; keep the assertions.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_template_test.rb && bundle exec ruby -Ilib -Itest test/unit/generators_plan_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Generators::Template` (NameError).

- [ ] **Step 3: Write minimal implementation**

`lib/metacrunch/generators/template.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Generators
    # The ERB templates in lib/metacrunch/templates.
    module Template

      DIR = File.expand_path("../templates", __dir__)
      # A line at the top of a file that stays outside the modules nest
      # wraps around the rest: the magic comment, a require, a blank line.
      PREAMBLE = /\A(?:# frozen_string_literal: true|require .*)?\n\z/

      module_function

      # The template at path, relative to DIR or absolute, with locals as
      # local variables. Lines in <%- ... -%> leave no line behind.
      def render(path, **locals)
        ERB.new(File.read(File.expand_path(path, DIR)), trim_mode: "-").result_with_hash(locals)
      end

      # code with all but its preamble wrapped in modules, outermost first,
      # two spaces deeper per module.
      def nest(code, modules)
        lines = code.lines
        preamble = lines.take_while { PREAMBLE.match?(it) }
        body = lines.drop(preamble.size)
        modules.reverse_each { |name| body = ["module #{name}\n", *body.map { indent(it) }, "end\n"] }
        [*preamble, *body].join
      end

      def indent(line) = line == "\n" ? line : "  #{line}"

    end
  end
end
```

`lib/metacrunch/generators/plan.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Generators
    # The files of one `new` or `generate`: all are written, or none if one
    # exists already and force is not given.
    class Plan

      Entry = Data.define(:path, :content, :executable)

      attr_reader :entries

      def initialize
        @entries = []
      end

      # path: absolute. executable: mode 0755 instead of the default.
      def add(path, content, executable: false)
        @entries << Entry.new(path: path.to_s, content:, executable:)
        self
      end

      # Writes the files, creating their directories, and puts
      # "created PATH" on out for each, PATH relative to cwd. Raises
      # UsageError before writing anything if a file exists and force is
      # false.
      def write(force:, out:, cwd:)
        existing = @entries.map(&:path).select { File.exist?(it) }.map { Generators.relative(it, cwd) }
        if existing.any? && !force
          raise UsageError, "#{existing.join(", ")} already #{existing.one? ? "exists" : "exist"}; " \
                            "use --force to overwrite"
        end

        @entries.each { write_entry(it, out, cwd) }
        nil
      end

      private

      def write_entry(entry, out, cwd)
        FileUtils.mkdir_p(File.dirname(entry.path))
        File.write(entry.path, entry.content)
        File.chmod(0o755, entry.path) if entry.executable
        out.puts("created #{Generators.relative(entry.path, cwd)}")
      end

    end
  end
end
```

Append to `lib/metacrunch/generators.rb` after `require_relative "generators/target"`:

```ruby
require_relative "generators/template"
require_relative "generators/plan"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_template_test.rb && bundle exec ruby -Ilib -Itest test/unit/generators_plan_test.rb`
Expected: PASS. Then `bundle exec rubocop lib/metacrunch/generators test/unit/generators_*_test.rb` — no offenses.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/generators.rb lib/metacrunch/generators/template.rb lib/metacrunch/generators/plan.rb \
        test/unit/generators_template_test.rb test/unit/generators_plan_test.rb
git commit -m "Render generator templates and write files all or none

Template renders the ERB files below lib/metacrunch/templates and nests
a class in its modules, leaving the magic comment and requires at the
top. Plan writes the files of one call, refusing all of them if one
exists without --force, so a failed generate leaves nothing half done.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Metacrunch.load_command and Testing.invoke with a command

**Files:**
- Modify: `lib/metacrunch.rb:87-93` (add `load_command` after `load_transform`)
- Modify: `lib/metacrunch/testing.rb:141-161` (`invoke`, new private helpers)
- Test: `test/unit/loader_test.rb` (two tests), `test/unit/testing_invoke_test.rb` (four tests, `write` returns the path)

**Interfaces:**
- Consumes: `Loader.load(path, name:, kind:, hint:)`, `Project.nearest`, `Testing::RecordingInvoker.new(project:, stubs:, logger:)` (project may be a Proc), `RecordingInvoker#project`.
- Produces:
  - `Metacrunch.load_command(path, name: nil) -> Command`
  - `Metacrunch::Testing.invoke(project, name, params: {}, stubs: {}, logger: Logger.new(nil))` as before, and `Testing.invoke(command, params: {}, stubs: {}, logger: Logger.new(nil), project: nil)`; returns `Testing::CommandRun`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/loader_test.rb` after `test_a_file_without_transform_defines_none`:

```ruby
  def test_load_command_considers_commands_only
    assert_equal "tidy", Metacrunch.load_command(fixture("shared.rb")).name
  end

  def test_load_command_selects_by_name
    error = assert_raises(Metacrunch::JobLoadError) { Metacrunch.load_command(fixture("mixed.rb"), name: "export") }

    assert_match(/no command named export in .*available: publish/, error.message)
  end
```

In `test/unit/testing_invoke_test.rb`, add a constant after `FILES`:

```ruby
  # A command outside the project's globs that invokes a name.
  CHAIN = "# frozen_string_literal: true\n\nMetacrunch.command(\"chain\") { run { invoke(\"a2c\").status } }\n"
```

change the private `write` helper to return the file:

```ruby
  def write(path, content)
    file = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
    file
  end
```

and add these tests before `private`:

```ruby
  def test_invokes_a_command_object_in_the_given_project
    run = Metacrunch::Testing.invoke(@project.fetch("tolerant"), project: @project, stubs: {"a2c" => :aborted})

    assert_equal [:rescued, :ok_with_failures], [run.value, run.status]
  end

  def test_a_command_object_resolves_names_from_the_working_directory
    command = Metacrunch.load_command(write("tools/chain.rb", CHAIN))
    run = Dir.chdir(@root) { Metacrunch::Testing.invoke(command, stubs: {"a2c" => :ok_with_failures}) }

    assert_equal [:ok_with_failures, ["a2c"]], [run.value, run.invoked.map(&:name)]
  end

  def test_a_command_object_without_project_invokes_no_names
    command = Metacrunch.load_command(write("tools/chain.rb", CHAIN))
    Dir.mktmpdir do |dir|
      run = Dir.chdir(dir) { Metacrunch::Testing.invoke(command) }
      error = assert_raises(ArgumentError) do
        Dir.chdir(dir) { Metacrunch::Testing.invoke(command, stubs: {"a2c" => :ok}) }
      end

      assert_equal [:aborted, Metacrunch::InvokeError], [run.status, run.error.class]
      assert_equal "stub for unknown job, transform or command: a2c", error.message
    end
  end

  def test_wrong_arguments_raise
    command = @project.fetch("tolerant")
    calls = [-> { Metacrunch::Testing.invoke(command, "tolerant") },
             -> { Metacrunch::Testing.invoke(@project, "tolerant", project: @project) },
             -> { Metacrunch::Testing.invoke(@project) },
             -> { Metacrunch::Testing.invoke(command, project: "x") },
             -> { Metacrunch::Testing.invoke("tolerant") }]

    assert_equal ['a command needs no name, got "tolerant"',
                  "project: is for a command; the first argument is a project already",
                  "the name of a command is missing",
                  'project: must be a Metacrunch::Project, got "x"',
                  'Testing.invoke takes a project and the name of a command, or a command; got "tolerant"'],
                 calls.map { assert_raises(ArgumentError, &it).message }
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Ilib -Itest test/unit/loader_test.rb -n /load_command/ && bundle exec ruby -Ilib -Itest test/unit/testing_invoke_test.rb`
Expected: FAIL with `undefined method 'load_command' for module Metacrunch` (NoMethodError).

- [ ] **Step 3: Write minimal implementation**

In `lib/metacrunch.rb`, after `load_transform`:

```ruby
    def load_command(path, name: nil)
      Loader.load(path, name:, kind: Command, hint: "select one with name:")
    end
```

In `lib/metacrunch/testing.rb`, replace `invoke` and add helpers (keep `command_run` as is):

```ruby
    # Runs the body of a command with params bound as a Hash, like run
    # does (no environment, no credentials): the command name of project,
    # or a Command (from Metacrunch.load_command, say), whose names resolve
    # in project:, else in the project of the working directory, loaded
    # when a name is first needed. Every invoke in the body is recorded and
    # answered from stubs (name => status Symbol, Result, value, or
    # callable that gets argv) instead of run; see RecordingInvoker. A stub
    # for a name that does not resolve raises ArgumentError, as does a job
    # name for name; a job's stub without a status raises StubError (an
    # ArgumentError).
    def invoke(target, name = nil, params: {}, stubs: {}, logger: Logger.new(nil), project: nil)
      command, project = invoke_target(target, name, project)
      invoker = RecordingInvoker.new(project:, stubs:, logger:)
      unknown = stubs.keys.map(&:to_s).reject { File.file?(it) || invoker.project&.include?(it) }
      raise ArgumentError, "stub for unknown job, transform or command: #{unknown.first}" if unknown.any?

      command_run(invoker, command.prepare(binder: ->(schema) { schema.bind_hash(params) }))
    end

    # [command, project] for invoke; project may be a Proc.
    def invoke_target(target, name, project)
      case target
      when Project then [project_command(target, name, project), target]
      when Command
        raise ArgumentError, "a command needs no name, got #{name.inspect}" if name
        unless project.nil? || project.is_a?(Project)
          raise ArgumentError, "project: must be a Metacrunch::Project, got #{project.inspect}"
        end

        [target, project || -> { Project.nearest }]
      else
        raise ArgumentError, "Testing.invoke takes a project and the name of a command, or a command; " \
                             "got #{target.inspect}"
      end
    end
    private_class_method :invoke_target

    def project_command(project, name, other)
      raise ArgumentError, "project: is for a command; the first argument is a project already" if other
      raise ArgumentError, "the name of a command is missing" unless name

      command = project.fetch(name)
      unless command.is_a?(Command)
        raise ArgumentError, "#{name} is a #{Loader::KINDS.fetch(command.class)}; test it with Testing.run"
      end

      command
    end
    private_class_method :project_command
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/unit/loader_test.rb && bundle exec ruby -Ilib -Itest test/unit/testing_invoke_test.rb`
Expected: PASS, including the existing `test_stubs_for_unknown_names_raise` and `test_jobs_are_tested_with_testing_run`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch.rb lib/metacrunch/testing.rb test/unit/loader_test.rb test/unit/testing_invoke_test.rb
git commit -m "Test command files by path with load_command

Testing.invoke needed a project and a name, so a command file run by
path or as an executable could not be tested. Metacrunch.load_command
loads one like load_job, and Testing.invoke takes the command itself;
its names resolve in project:, else in the project of the working
directory, as for Testing.run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Files with the templates of jobs, transforms and commands

**Files:**
- Create: `lib/metacrunch/generators/files.rb`
- Create: `lib/metacrunch/templates/job/file.rb.erb`, `job/test.rb.erb`, `job/path_test.rb.erb`
- Create: `lib/metacrunch/templates/transform/file.rb.erb`, `transform/test.rb.erb`, `transform/path_test.rb.erb`
- Create: `lib/metacrunch/templates/command/file.rb.erb`, `command/test.rb.erb`, `command/path_test.rb.erb`
- Modify: `lib/metacrunch/generators.rb` (one `require_relative` at the end)
- Test: `test/unit/generators_files_test.rb`

**Interfaces:**
- Consumes: `Target.for`, `Target#declared?`, `#modules`, `#form`; `Template.render`, `Template.nest`; `Plan`; `Metacrunch.load_command` (Task 3) in the generated command test by path.
- Produces: `Generators::Files.plan(target, desc: nil, test: true) -> Plan` (the file first, executable for jobs, transforms and commands; the test second). Template locals: `target`, `desc`, `run`, `helper`, `file`, `library` (see `template_locals`).

- [ ] **Step 1: Write the failing test**

`test/unit/generators_files_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "prism"
require "tmpdir"
require "metacrunch/generators"
require "metacrunch/testing"

class GeneratorsFilesTest < Minitest::Test

  Generators = Metacrunch::Generators
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog"
  SOURCE = [{"id" => 1}, {"title" => "x"}].freeze

  def test_a_name_gets_an_executable_file_and_a_test
    entries = plan("job", "catalog:ids").entries

    assert_equal [[ROOT.join("jobs/catalog/ids.rb").to_s, true], [ROOT.join("test/jobs/catalog/ids_test.rb").to_s, false]],
                 entries.map { [it.path, it.executable] }
  end

  def test_without_test_only_the_file
    assert_equal 1, plan("command", "tools/x", test: false).entries.size
  end

  def test_files_and_tests_are_ruby_without_warnings
    problems = ["job", "transform", "command"].product(["catalog:ids", "tools/fix"]).flat_map do |kind, argument|
      plan(kind, argument).entries.flat_map { |entry| ruby_problems(entry.content).map { "#{entry.path}: #{it}" } }
    end

    assert_empty problems
  end

  def test_the_comment_shows_how_to_run_it
    by_name = plan("job", "catalog:ids").entries.first.content
    by_path = plan("job", "tools/fix").entries.first.content

    assert_includes by_name, "#   metacrunch catalog:ids < in.jsonl > out.jsonl\n"
    assert_includes by_path, "#   metacrunch run tools/fix.rb < in.jsonl > out.jsonl\n"
  end

  def test_a_transform_shows_how_jobs_use_it
    assert_includes plan("transform", "tools/tidy").entries.first.content, %(#   use "tools/tidy.rb"\n)
  end

  def test_tests_by_name_use_the_helper_and_tests_by_path_the_file
    by_name = plan("job", "catalog:ids").entries.last.content
    by_path = plan("job", "tools/fix").entries.last.content

    assert_includes by_name, %(require_relative "../../test_helper"\n)
    assert_includes by_path, %(FILE = File.expand_path("../tools/fix.rb", __dir__)\n)
  end

  def test_no_desc_without_the_option
    assert_includes plan("job", "catalog:ids").entries.first.content, %(Metacrunch.job "catalog:ids" do\n)
  end

  def test_a_job_keeps_records_with_an_id_and_marks_missing_titles
    in_project do |root|
      write(plan("job", "catalog:ids", root:), root)
      result = Metacrunch::Testing.run(Metacrunch.load_job(root.join("jobs/catalog/ids.rb").to_s), source: SOURCE)

      assert_equal [[{"id" => 1}], {"No id" => 1}, {"No title" => 1}],
                   [result.records, result.stats.rejected, result.stats.marked]
    end
  end

  def test_a_transform_runs_alone_with_a_source
    in_project do |root|
      write(plan("transform", "catalog:clean", root:), root)
      transform = Metacrunch.load_transform(root.join("transforms/catalog/clean.rb").to_s)
      result = Metacrunch::Testing.run(transform, source: [{"id" => 1}, {"title" => "x"}, {"id" => 2, "title" => "y"}])

      assert_equal [[{"id" => 1}, {"id" => 2, "title" => "y"}], {"No title" => 1}],
                   [result.records, result.stats.marked]
    end
  end

  def test_a_command_runs_without_invoking
    in_project do |root|
      write(plan("command", "catalog:release", root:), root)
      run = Metacrunch::Testing.invoke(Metacrunch.load_command(root.join("commands/catalog/release.rb").to_s))

      assert_equal [:ok, []], [run.status, run.invoked]
    end
  end

  def test_desc_becomes_a_ruby_string
    desc = %(Say "hi" \#{x} – ü)
    in_project do |root|
      write(plan("transform", "clean", root:, desc:), root)

      assert_equal desc, Metacrunch.load_transform(root.join("transforms/clean.rb").to_s).desc
    end
  end

  private

  def plan(kind, argument, root: ROOT, desc: nil, test: true)
    root = nil if Metacrunch::Names.path?(argument)
    Generators::Files.plan(Generators::Target.for(kind, argument, cwd: CWD, root:), desc:, test:)
  end

  def write(plan, root)
    plan.write(force: false, out: StringIO.new, cwd: root.to_s)
  end

  # Parse errors and warnings, verbose ones included.
  def ruby_problems(code)
    result = Prism.parse(code)
    (result.errors + result.warnings).map { "#{it.location.start_line}: #{it.message}" }
  end

  def in_project
    Dir.mktmpdir { |dir| yield Pathname(File.realpath(dir)) }
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_files_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Generators::Files` (NameError).

- [ ] **Step 3: Write minimal implementation**

`lib/metacrunch/generators/files.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Generators
    # The file and the test of a job, transform, command, source or sink,
    # from the templates of its kind: KIND/file.rb.erb, and
    # KIND/test.rb.erb for a name or KIND/path_test.rb.erb for a path.
    module Files

      module_function

      # The Plan for target. desc: the desc: of a job, transform or
      # command, or nil. test: whether the test is part of it.
      def plan(target, desc: nil, test: true)
        locals = template_locals(target, desc)
        code = Template.render(File.join(target.kind, "file.rb.erb"), **locals)
        plan = Plan.new.add(target.file, Template.nest(code, target.modules), executable: target.declared?)
        return plan unless test

        template = target.form == :name ? "test.rb.erb" : "path_test.rb.erb"
        plan.add(target.test, Template.render(File.join(target.kind, template), **locals))
      end

      # target and desc, and for the templates:
      # - run: what follows `metacrunch` to run it ("catalog:ids", "run tools/fix.rb")
      # - helper: test/test_helper relative to the test (name form)
      # - file: the file relative to the test
      # - library: the file to require from a test, below lib/ (name form)
      def template_locals(target, desc)
        test_dir = File.dirname(target.test)
        by_name = target.form == :name
        {
          target:, desc:,
          run: by_name ? target.name : "run #{target.argument}",
          helper: (Generators.relative(target.root.join("test", "test_helper").to_s, test_dir) if by_name),
          file: Generators.relative(target.file, test_dir),
          library: (Generators.relative(target.file, target.root.join("lib").to_s).delete_suffix(".rb") if by_name)
        }
      end

    end
  end
end
```

Append to `lib/metacrunch/generators.rb`:

```ruby
require_relative "generators/files"
```

`lib/metacrunch/templates/job/file.rb.erb`:

```erb
#!/usr/bin/env metacrunch
# frozen_string_literal: true

# Reads JSON Lines from stdin and writes them to stdout:
#   metacrunch <%= run %> < in.jsonl > out.jsonl
# Declare a source or a sink to read or write elsewhere.
Metacrunch.job <%= target.name.inspect %><%= ", desc: #{desc.inspect}" if desc %> do
  params do
    # param :input, String, required: true, desc: "JSON Lines file"
  end

  # source MySource.new(params.input), id: ->(record) { record["id"] }

  reject("No id") { it["id"].nil? }
  # use "catalog:clean", lang: "en"
  map do |record, ctx|
    ctx.mark("No title") unless record.key?("title")
    record
  end

  # sink MySink.new, batch: 1000
end
```

`lib/metacrunch/templates/job/test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative <%= helper.inspect %>

class <%= target.test_class %> < Minitest::Test

  def test_keeps_records_with_an_id
    job = PROJECT.fetch(<%= target.name.inspect %>)
    result = Metacrunch::Testing.run(job, source: [{"id" => 1}, {"title" => "x"}])

    assert_equal [{"id" => 1}], result.records
  end

end
```

`lib/metacrunch/templates/job/path_test.rb.erb`:

```erb
# frozen_string_literal: true

require "minitest/autorun"
require "metacrunch"
require "metacrunch/testing"

class <%= target.test_class %> < Minitest::Test

  FILE = File.expand_path(<%= file.inspect %>, __dir__)

  def test_keeps_records_with_an_id
    result = Metacrunch::Testing.run(Metacrunch.load_job(FILE), source: [{"id" => 1}, {"title" => "x"}])

    assert_equal [{"id" => 1}], result.records
  end

end
```

`lib/metacrunch/templates/transform/file.rb.erb`:

```erb
#!/usr/bin/env metacrunch
# frozen_string_literal: true

# Steps for the jobs that use them:
#   use <%= (target.form == :name ? target.name : target.argument).inspect %>
# Alone it reads JSON Lines from stdin and writes them to stdout:
#   metacrunch <%= run %> < in.jsonl > out.jsonl
Metacrunch.transform <%= target.name.inspect %><%= ", desc: #{desc.inspect}" if desc %> do
  params do
    # param :lang, String, default: "en", desc: "Language of the titles"
  end

  reject("No id") { it["id"].nil? }
  map do |record, ctx|
    ctx.mark("No title") unless record.key?("title")
    record
  end
end
```

`lib/metacrunch/templates/transform/test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative <%= helper.inspect %>

class <%= target.test_class %> < Minitest::Test

  def test_keeps_records_with_an_id
    transform = PROJECT.fetch(<%= target.name.inspect %>)
    result = Metacrunch::Testing.run(transform, source: [{"id" => 1}, {"title" => "x"}])

    assert_equal [{"id" => 1}], result.records
  end

end
```

`lib/metacrunch/templates/transform/path_test.rb.erb`:

```erb
# frozen_string_literal: true

require "minitest/autorun"
require "metacrunch"
require "metacrunch/testing"

class <%= target.test_class %> < Minitest::Test

  FILE = File.expand_path(<%= file.inspect %>, __dir__)

  def test_keeps_records_with_an_id
    result = Metacrunch::Testing.run(Metacrunch.load_transform(FILE), source: [{"id" => 1}, {"title" => "x"}])

    assert_equal [{"id" => 1}], result.records
  end

end
```

`lib/metacrunch/templates/command/file.rb.erb`:

```erb
#!/usr/bin/env metacrunch
# frozen_string_literal: true

# Runs its body; invoke runs jobs, transforms and other commands:
#   metacrunch <%= run %>
Metacrunch.command <%= target.name.inspect %><%= ", desc: #{desc.inspect}" if desc %> do
  params do
    # param :input, String, required: true, desc: "JSON Lines file"
  end

  run do
    logger.info(<%= "#{target.name}: nothing to do yet".inspect %>)
    # result = invoke "catalog:ids", "--input", params.input
    # next logger.warn("<%= target.name %>: #{result.status}") unless result.ok?
  end
end
```

`lib/metacrunch/templates/command/test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative <%= helper.inspect %>

class <%= target.test_class %> < Minitest::Test

  def test_runs_without_invoking
    run = Metacrunch::Testing.invoke(PROJECT, <%= target.name.inspect %>)

    assert_equal [:ok, []], [run.status, run.invoked.map(&:name)]
  end

end
```

`lib/metacrunch/templates/command/path_test.rb.erb`:

```erb
# frozen_string_literal: true

require "minitest/autorun"
require "metacrunch"
require "metacrunch/testing"

class <%= target.test_class %> < Minitest::Test

  FILE = File.expand_path(<%= file.inspect %>, __dir__)

  def test_runs_without_invoking
    run = Metacrunch::Testing.invoke(Metacrunch.load_command(FILE))

    assert_equal [:ok, []], [run.status, run.invoked.map(&:name)]
  end

end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_files_test.rb`
Expected: PASS. If `test_a_job_keeps_records_with_an_id_and_marks_missing_titles` shows other key types for `rejected`/`marked`, check `Stats` and adjust the expected value, not the template. Then `bundle exec rubocop lib/metacrunch/generators test/unit/generators_files_test.rb`.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/generators.rb lib/metacrunch/generators/files.rb lib/metacrunch/templates \
        test/unit/generators_files_test.rb
git commit -m "Generate jobs, transforms and commands with tests

Each kind has a template for its file and for its test by name (using
the project's test helper) or by path (self-contained). The files run
right away: a job and a transform filter JSON Lines, a command logs a
line; their tests pass as generated.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Templates of sources and sinks

**Files:**
- Create: `lib/metacrunch/templates/source/file.rb.erb`, `source/test.rb.erb`, `source/path_test.rb.erb`
- Create: `lib/metacrunch/templates/sink/file.rb.erb`, `sink/test.rb.erb`, `sink/path_test.rb.erb`
- Test: `test/unit/generators_components_test.rb`

**Interfaces:**
- Consumes: `Generators::Files.plan` (Task 4; it nests the class in `target.modules` and marks it not executable), locals `target`, `helper`, `library`, `file`.
- Produces: the six templates; nothing new in Ruby.

- [ ] **Step 1: Write the failing test**

`test/unit/generators_components_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "prism"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsComponentsTest < Minitest::Test

  Generators = Metacrunch::Generators
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog"

  def test_a_source_by_name_is_a_class_in_its_modules_with_a_test
    entries = plan("source", "a:b:lines").entries

    assert_equal [[ROOT.join("lib/a/b/lines.rb").to_s, false], [ROOT.join("test/lib/a/b/lines_test.rb").to_s, false]],
                 entries.map { [it.path, it.executable] }
    assert entries.first.content.start_with?("# frozen_string_literal: true\n\nmodule A\n  module B\n    # A source:")
  end

  def test_a_sink_by_path_has_no_modules
    content = plan("sink", "lib/json_file").entries.first.content

    assert content.start_with?(%(# frozen_string_literal: true\n\nrequire "json"\n\n# A sink:)), content
  end

  def test_files_and_tests_are_ruby_without_warnings
    problems = ["source", "sink"].product(["marc:dump", "lib/json_file"]).flat_map do |kind, argument|
      plan(kind, argument).entries.flat_map { |entry| ruby_problems(entry.content).map { "#{entry.path}: #{it}" } }
    end

    assert_empty problems
  end

  def test_tests_require_the_class
    by_name = plan("source", "marc:dump").entries.last.content
    by_path = plan("sink", "lib/json_file").entries.last.content

    assert_includes by_name, %(require_relative "../../test_helper"\nrequire "marc/dump"\n)
    assert_includes by_path, %(require_relative "../lib/json_file"\n)
  end

  def test_a_source_yields_a_record_for_each_line
    in_project do |root|
      write(plan("source", "marc:dump", root:), root)
      File.write(root.join("lines.txt"), "a\nb\n")
      source = load_class(root.join("lib/marc/dump.rb"), "Marc::Dump").new(root.join("lines.txt").to_s)

      assert_equal [{"line" => "a"}, {"line" => "b"}], source.enum_for(:each).to_a
    end
  end

  def test_a_sink_writes_a_line_of_json_for_each_record
    in_project do |root|
      write(plan("sink", "out:json", root:), root)
      sink = load_class(root.join("lib/out/json.rb"), "Out::Json").new(root.join("out.jsonl").to_s)
      sink.open(nil)
      [{"id" => 1}, {"id" => 2}].each { sink.write(it) }
      sink.close

      assert_equal %({"id":1}\n{"id":2}\n), File.read(root.join("out.jsonl"))
    end
  end

  private

  def plan(kind, argument, root: ROOT)
    root = nil if Metacrunch::Names.path?(argument)
    Generators::Files.plan(Generators::Target.for(kind, argument, cwd: CWD, root:))
  end

  def write(plan, root)
    plan.write(force: false, out: StringIO.new, cwd: root.to_s)
  end

  # Loads path into a module of its own, so its constants stay out of
  # Object, and returns the constant there.
  def load_class(path, constant)
    namespace = Module.new
    load(path.to_s, namespace)
    namespace.const_get(constant)
  end

  def ruby_problems(code)
    result = Prism.parse(code)
    (result.errors + result.warnings).map { "#{it.location.start_line}: #{it.message}" }
  end

  def in_project
    Dir.mktmpdir { |dir| yield Pathname(File.realpath(dir)) }
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_components_test.rb`
Expected: FAIL with `No such file or directory @ rb_sysopen - .../templates/source/file.rb.erb` (Errno::ENOENT).

- [ ] **Step 3: Write the templates**

`lib/metacrunch/templates/source/file.rb.erb`:

```erb
# frozen_string_literal: true

# A source: yields a record for each line of a file. The file is read in
# each, not in new, so that --help, check and tests with another source
# read nothing. In a job:
#   source <%= target.constant %>.new(params.input)
class <%= target.class_name %>

  def initialize(path)
    @path = path
  end

  # Optional: called once before the first record, with context.params
  # and context.logger.
  # def open(context) = nil

  def each
    File.foreach(@path, chomp: true) { |line| yield({"line" => line}) }
  end

  # Optional: called at the end, also after an error.
  # def close = nil

end
```

`lib/metacrunch/templates/source/test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative <%= helper.inspect %>
require <%= library.inspect %>
require "tmpdir"

class <%= target.test_class %> < Minitest::Test

  def test_yields_a_record_for_each_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lines.txt")
      File.write(path, "a\nb\n")
      records = <%= target.constant %>.new(path).enum_for(:each).to_a

      assert_equal [{"line" => "a"}, {"line" => "b"}], records
    end
  end

end
```

`lib/metacrunch/templates/source/path_test.rb.erb`:

```erb
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative <%= file.delete_suffix(".rb").inspect %>

class <%= target.test_class %> < Minitest::Test

  def test_yields_a_record_for_each_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lines.txt")
      File.write(path, "a\nb\n")
      records = <%= target.constant %>.new(path).enum_for(:each).to_a

      assert_equal [{"line" => "a"}, {"line" => "b"}], records
    end
  end

end
```

`lib/metacrunch/templates/sink/file.rb.erb`:

```erb
# frozen_string_literal: true

require "json"

# A sink: writes each record as a line of JSON into a file. In a job:
#   sink <%= target.constant %>.new(params.output)
class <%= target.class_name %>

  def initialize(path)
    @path = path
  end

  # Called once before the first record.
  def open(_context)
    @file = File.open(@path, "w")
  end

  def write(record)
    @file.puts(JSON.generate(record))
  end

  # Optional: with `sink <%= target.constant %>.new(...), batch: 1000` the
  # job calls write_batch with up to 1000 records instead of write.
  # def write_batch(records) = records.each { write(it) }

  # Called at the end, also after an error.
  def close
    @file&.close
  end

end
```

`lib/metacrunch/templates/sink/test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative <%= helper.inspect %>
require <%= library.inspect %>
require "tmpdir"

class <%= target.test_class %> < Minitest::Test

  def test_writes_a_line_of_json_for_each_record
    Dir.mktmpdir do |dir|
      path = File.join(dir, "records.jsonl")
      sink = <%= target.constant %>.new(path)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.write({"id" => 2})
      sink.close

      assert_equal %({"id":1}\n{"id":2}\n), File.read(path)
    end
  end

end
```

`lib/metacrunch/templates/sink/path_test.rb.erb`:

```erb
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative <%= file.delete_suffix(".rb").inspect %>

class <%= target.test_class %> < Minitest::Test

  def test_writes_a_line_of_json_for_each_record
    Dir.mktmpdir do |dir|
      path = File.join(dir, "records.jsonl")
      sink = <%= target.constant %>.new(path)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.write({"id" => 2})
      sink.close

      assert_equal %({"id":1}\n{"id":2}\n), File.read(path)
    end
  end

end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_components_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/templates/source lib/metacrunch/templates/sink test/unit/generators_components_test.rb
git commit -m "Generate sources and sinks with tests

A source reads the lines of a file in each, a sink writes JSON Lines
between open and close; comments name the optional methods of the
contract. By name the class goes into the modules of its name's parts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Generators::Skeleton and the gemspec

**Files:**
- Create: `lib/metacrunch/generators/skeleton.rb`
- Create: `lib/metacrunch/templates/project/Metacrunchfile.erb`, `Gemfile.erb`, `Rakefile.erb`, `test_helper.rb.erb`, `project_test.rb.erb`
- Modify: `lib/metacrunch/generators.rb` (one `require_relative` at the end)
- Modify: `metacrunch.gemspec:21` (ship `lib/**/*.erb`)
- Test: `test/unit/generators_skeleton_test.rb`

**Interfaces:**
- Consumes: `Template.render`, `Plan`, `Metacrunch::VERSION`.
- Produces: `Generators::Skeleton::FILES` (ordered Hash path → template or nil), `Skeleton.plan(root, version: VERSION) -> Plan`, `Skeleton.gem_line(version) -> String`.

- [ ] **Step 1: Write the failing test**

`test/unit/generators_skeleton_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "prism"
require "tmpdir"
require "metacrunch/generators"

class GeneratorsSkeletonTest < Minitest::Test

  Skeleton = Metacrunch::Generators::Skeleton
  ROOT = File.expand_path("../..", __dir__)

  def test_lists_the_files_of_a_project
    paths = Skeleton.plan("/work/catalog").entries.map { it.path.delete_prefix("/work/catalog/") }

    assert_equal ["Metacrunchfile", "Gemfile", "Rakefile", "jobs/.keep", "transforms/.keep", "commands/.keep",
                  "lib/.keep", "test/test_helper.rb", "test/project_test.rb"], paths
  end

  def test_every_file_is_ruby_without_warnings
    entries = Skeleton.plan("/work/catalog").entries.reject { it.path.end_with?(".keep") }
    problems = entries.flat_map do |entry|
      result = Prism.parse(entry.content)
      (result.errors + result.warnings).map { "#{entry.path}: #{it.message}" }
    end

    assert_empty problems
  end

  def test_a_release_asks_for_its_minor_version
    assert_equal %(gem "metacrunch", "~> 5.1"), Skeleton.gem_line("5.1.2")
  end

  def test_a_prerelease_comes_from_git
    assert_equal %(gem "metacrunch", github: "ubpb/metacrunch", branch: "metacrunch-ng"), Skeleton.gem_line("5.0.0.pre")
    assert_includes Skeleton.plan("/x", version: "5.2.0").entries[1].content, %(\ngem "metacrunch", "~> 5.2"\n)
  end

  def test_the_project_loads_empty
    Dir.mktmpdir do |dir|
      Skeleton.plan(dir).write(force: false, out: StringIO.new, cwd: dir)
      project = Metacrunch.load_project(dir)

      assert_equal [[], []], [project.names, project.load_errors]
    end
  end

  def test_the_gem_ships_the_templates
    spec = Dir.chdir(ROOT) { Gem::Specification.load("metacrunch.gemspec") }
    templates = Dir.glob("lib/metacrunch/templates/**/*.erb", base: ROOT)

    assert_operator templates.size, :>=, 20
    assert_empty templates - spec.files
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_skeleton_test.rb`
Expected: FAIL with `uninitialized constant Metacrunch::Generators::Skeleton` (NameError).

- [ ] **Step 3: Write minimal implementation**

`lib/metacrunch/generators/skeleton.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  module Generators
    # The files of a new project (`metacrunch new`): a Metacrunchfile that
    # loads jobs, transforms and commands, a Gemfile and a Rakefile, the
    # directories for them and for lib/, and a test of the project.
    module Skeleton

      # Path in the project => template in templates/project, or nil for an
      # empty file that keeps the directory in Git.
      FILES = {
        "Metacrunchfile" => "Metacrunchfile.erb", "Gemfile" => "Gemfile.erb", "Rakefile" => "Rakefile.erb",
        "jobs/.keep" => nil, "transforms/.keep" => nil, "commands/.keep" => nil, "lib/.keep" => nil,
        "test/test_helper.rb" => "test_helper.rb.erb", "test/project_test.rb" => "project_test.rb.erb"
      }.freeze

      module_function

      # The Plan of a project in root, an absolute path. version: the
      # metacrunch version the Gemfile asks for.
      def plan(root, version: VERSION)
        metacrunch = gem_line(version)
        FILES.each_with_object(Plan.new) do |(path, template), plan|
          content = template ? Template.render(File.join("project", template), metacrunch:) : ""
          plan.add(File.join(root, path), content)
        end
      end

      # The Gemfile line of metacrunch: "~> MAJOR.MINOR" for a release; Git
      # for a prerelease, which RubyGems does not have.
      def gem_line(version)
        version = Gem::Version.new(version)
        return %(gem "metacrunch", github: "ubpb/metacrunch", branch: "metacrunch-ng") if version.prerelease?

        %(gem "metacrunch", "~> #{version.segments.first(2).join(".")}")
      end

    end
  end
end
```

Append to `lib/metacrunch/generators.rb`:

```ruby
require_relative "generators/skeleton"
```

`lib/metacrunch/templates/project/Metacrunchfile.erb`:

```erb
# frozen_string_literal: true

# The project file: it names the jobs, transforms and commands of this
# directory, so that `metacrunch NAME` runs them from any directory below
# it and `metacrunch --help` lists them. `metacrunch generate` adds files.
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

`lib/metacrunch/templates/project/Gemfile.erb`:

```erb
# frozen_string_literal: true

source "https://rubygems.org"

<%= metacrunch %>

group :test do
  gem "minitest"
  gem "rake"
end
```

`lib/metacrunch/templates/project/Rakefile.erb`:

```erb
# frozen_string_literal: true

require "minitest/test_task"

# rake test, the default, runs test/**/*_test.rb with lib and test on the
# load path.
Minitest::TestTask.create

task default: :test
```

`lib/metacrunch/templates/project/test_helper.rb.erb`:

```erb
# frozen_string_literal: true

# Required by every test: loads metacrunch and the project once.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "metacrunch"
require "metacrunch/testing"

PROJECT = Metacrunch.load_project(File.expand_path("..", __dir__))
```

`lib/metacrunch/templates/project/project_test.rb.erb`:

```erb
# frozen_string_literal: true

require_relative "test_helper"

# Fails for a file of the project that does not load and for a name that
# is declared twice.
class ProjectTest < Minitest::Test

  def test_all_files_load_and_every_name_is_unique
    assert_empty PROJECT.load_errors
    assert_empty PROJECT.duplicates
  end

end
```

`metacrunch.gemspec` line 21 becomes:

```ruby
  spec.files = Dir["lib/**/*.rb", "lib/**/*.erb", "exe/*", "CHANGELOG.md", "License.txt", "Readme.md"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/unit/generators_skeleton_test.rb`
Expected: PASS (20 templates: 9 from Task 4, 6 from Task 5, 5 here; the `>=` only guards against an empty glob).

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/generators.rb lib/metacrunch/generators/skeleton.rb lib/metacrunch/templates/project \
        metacrunch.gemspec test/unit/generators_skeleton_test.rb
git commit -m "Describe the skeleton of a new project

A project gets a Metacrunchfile with recursive globs, a Gemfile, a
Rakefile running Minitest, directories for jobs, transforms, commands
and lib, and a test that fails when a file does not load or a name is
declared twice. The gem ships the templates.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `metacrunch new DIR`

**Files:**
- Modify: `lib/metacrunch/cli/new.rb` (rewrite)
- Modify: `lib/metacrunch/cli.rb:1-15` (require the generators)
- Test: `test/cli/new_test.rb` (rewrite)

**Interfaces:**
- Consumes: `Generators::Skeleton.plan(root)`, `Plan#write(force:, out:, cwd:)`, `Project.find(dir)`, `Cli::Command` (`define_options`, `parse`, `execute`, `UsageError` → exit 2).
- Produces: `Cli::NewCommand` with `NAME = "new"`, `SUMMARY = "Create a project"`, `USAGE = "new [--force] DIR"`.

- [ ] **Step 1: Write the failing test**

Replace `test/cli/new_test.rb` with:

```ruby
# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class NewTest < Minitest::Test

  include CliHelper

  SKELETON = ["Metacrunchfile", "Gemfile", "Rakefile", "jobs/.keep", "transforms/.keep", "commands/.keep",
              "lib/.keep", "test/test_helper.rb", "test/project_test.rb"].freeze
  USAGE_ERRORS = {
    [] => "no directory given",
    ["a", "b"] => "unexpected arguments: b",
    ["jobs/x.rb"] => "new creates a project; for a job file use metacrunch generate job jobs/x.rb"
  }.freeze

  def test_creates_a_project_that_loads
    in_tmpdir do |dir|
      code, stdout, stderr = cli("new", "catalog")
      project = Metacrunch.load_project(File.join(dir, "catalog"))

      assert_equal [0, ""], [code, stderr]
      assert_equal SKELETON.map { "created catalog/#{it}" }, stdout.lines(chomp: true).first(SKELETON.size)
      assert_equal [[], []], [project.names, project.load_errors]
    end
  end

  def test_prints_the_next_steps
    in_tmpdir do
      _code, stdout, = cli("new", "my catalog")

      assert stdout.end_with?("Next steps:\n  cd my\\ catalog\n  bundle install\n" \
                              "  bundle exec metacrunch generate job NAME\n  bundle exec rake\n"), stdout
    end
  end

  def test_the_working_directory_needs_no_cd
    in_tmpdir do
      _code, stdout, = cli("new", ".")

      assert_path_exists "Metacrunchfile"
      refute_match(/^  cd /, stdout)
    end
  end

  def test_keeps_other_files_of_the_directory
    in_tmpdir do
      FileUtils.mkdir_p("catalog/jobs")
      File.write("catalog/jobs/old.rb", "x")
      code, = cli("new", "catalog")

      assert_equal [0, "x"], [code, File.read("catalog/jobs/old.rb")]
    end
  end

  def test_refuses_existing_files_of_the_skeleton_without_force
    in_tmpdir do
      FileUtils.mkdir_p("catalog")
      ["Gemfile", "Rakefile"].each { File.write("catalog/#{it}", "mine") }
      code, _stdout, stderr = cli("new", "catalog")

      assert_equal [2, "Error: catalog/Gemfile, catalog/Rakefile already exist; use --force to overwrite"],
                   [code, stderr.lines.first.chomp]
      refute_path_exists "catalog/Metacrunchfile"
    end
  end

  def test_force_overwrites_the_skeleton_only
    in_tmpdir do
      FileUtils.mkdir_p("catalog")
      ["Gemfile", "notes.txt"].each { File.write("catalog/#{it}", "mine") }
      code, = cli("new", "catalog", "--force")

      assert_equal 0, code
      assert_equal ["mine", true], [File.read("catalog/notes.txt"), File.read("catalog/Gemfile").include?("metacrunch")]
    end
  end

  def test_notes_a_project_inside_another
    in_tmpdir do |dir|
      File.write("Metacrunchfile", "")
      code, _stdout, stderr = cli("new", "sub")

      assert_equal [0, "note: inside the project #{dir}; below sub/ names resolve in the new project\n"],
                   [code, stderr]
    end
  end

  def test_a_file_is_no_directory
    in_tmpdir do
      File.write("catalog", "")

      assert_equal "Error: catalog is a file", cli("new", "catalog")[2].lines.first.chomp
    end
  end

  USAGE_ERRORS.each_with_index do |(args, message), index|
    define_method("test_usage_error_#{index}") do
      in_tmpdir do
        code, _stdout, stderr = cli("new", *args)

        assert_equal [2, "Error: #{message}"], [code, stderr.lines.first.chomp]
        assert_empty Dir.children(".")
      end
    end
  end

  def test_help_shows_the_usage
    assert_match(/\AUsage: metacrunch new \[--force\] DIR\n\nCreate a project\./, cli("help", "new")[1])
  end

  private

  def in_tmpdir
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield File.realpath(dir) } }
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/cli/new_test.rb`
Expected: FAIL — `test_creates_a_project_that_loads` gets `created catalog.rb` (the old job generator), `test_help_shows_the_usage` sees `new [--test] [--force] PATH`.

- [ ] **Step 3: Write minimal implementation**

In `lib/metacrunch/cli.rb`, after `require_relative "credentials/editor"` add:

```ruby
require_relative "generators"
```

Replace `lib/metacrunch/cli/new.rb` with:

```ruby
# frozen_string_literal: true

require "shellwords"

module Metacrunch
  class Cli
    # metacrunch new: creates a project (see Generators::Skeleton) in a
    # directory that is new, empty, or lacks the files of the skeleton.
    # Other files of the directory stay as they are.
    class NewCommand < Command

      NAME = "new"
      SUMMARY = "Create a project"
      USAGE = "new [--force] DIR"

      def initialize(streams, lookup)
        super
        @force = false
      end

      private

      def define_options(parser)
        parser.on("--force", "Overwrite existing files of the skeleton") { @force = true }
      end

      # Options may stand before or after DIR.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        dir = argv.shift
        check_dir(dir, argv)
        root = File.expand_path(dir)
        outer = Project.find(File.dirname(root))
        Generators::Skeleton.plan(root).write(force: @force, out: @stdout, cwd: Dir.pwd)
        if outer
          @stderr.puts("note: inside the project #{File.dirname(outer)}; below #{dir.chomp("/")}/ names resolve " \
                       "in the new project")
        end
        @stdout.puts(next_steps(dir, root))
        EXIT_CODES[:ok]
      end

      def check_dir(dir, rest)
        raise UsageError, "no directory given" unless dir
        raise UsageError, "unexpected arguments: #{rest.join(" ")}" if rest.any?
        if dir.end_with?(".rb")
          raise UsageError, "new creates a project; for a job file use metacrunch generate job #{dir}"
        end
        raise UsageError, "#{dir} is a file" if File.file?(dir)
      end

      def next_steps(dir, root)
        cd = root == Dir.pwd ? [] : ["cd #{Shellwords.escape(dir)}"]
        steps = [*cd, "bundle install", "bundle exec metacrunch generate job NAME", "bundle exec rake"]
        ["Next steps:", *steps.map { "  #{it}" }]
      end

    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Ilib -Itest test/cli/new_test.rb && bundle exec ruby -Ilib -Itest test/cli/cli_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli.rb lib/metacrunch/cli/new.rb test/cli/new_test.rb
git commit -m "Create projects with metacrunch new

new DIR now writes the skeleton of a project instead of a job file, so
a new user starts from a project that loads and whose tests pass. It
keeps other files of the directory, refuses existing skeleton files
without --force, notes a project inside another and prints the next
steps. A .rb argument points to generate job.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `metacrunch generate KIND NAME|PATH`

**Files:**
- Create: `lib/metacrunch/cli/generate.rb`
- Modify: `lib/metacrunch/cli.rb` (require, `COMMANDS`)
- Modify: `lib/metacrunch/names.rb:12` (`RESERVED` gains `"generate"`)
- Test: `test/cli/generate_test.rb`

**Interfaces:**
- Consumes: `Generators::KINDS`, `KIND_LIST`, `Generators.relative`, `Target.for`, `Files.plan`, `Plan#write`; `ProjectLookup#project(logger)`; `Project.find`, `Project.load_file`, `#declared`, `#relative`, `#load_errors`, `#load_error_summary`, `#duplicates`, `#duplicate_message`.
- Produces: `Cli::GenerateCommand` (`NAME = "generate"`, `SUMMARY = "Create a job, transform, command, source or sink"`, `USAGE = "generate KIND [OPTIONS] NAME|PATH"`); `Cli::COMMANDS["generate"]`; `Names::RESERVED` includes `"generate"`.

- [ ] **Step 1: Write the failing test**

`test/cli/generate_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class GenerateTest < Minitest::Test

  include CliHelper
  include Override

  METACRUNCHFILE = %(Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"\n)
  USAGE_ERRORS = {
    [] => "no kind given (job, transform, command, source or sink)",
    ["model", "x"] => "unknown kind model (job, transform, command, source or sink)",
    ["job"] => "no name or path given",
    ["job", "a", "b"] => "unexpected arguments: b",
    ["job", "Catalog"] => '"Catalog" is not a valid job name; use a-z, 0-9, _ and -, in parts separated by :',
    ["job", "help"] => '"help" is the name of a built-in command; choose another name',
    ["source", "lines", "--desc", "x"] => "--desc is for jobs, transforms and commands",
    ["job", "x", "--desc", "a\nb"] => "desc must be one line of text",
    ["sink", "file"] => '"file" would reopen File; choose another name'
  }.freeze

  def test_a_name_goes_below_the_project_root
    in_project do |root|
      FileUtils.mkdir_p(File.join(root, "jobs"))
      code, stdout, stderr = Dir.chdir(File.join(root, "jobs")) { cli("generate", "job", "catalog:ids") }

      assert_equal [0, "created ../jobs/catalog/ids.rb\ncreated ../test/jobs/catalog/ids_test.rb\n", ""],
                   [code, stdout, stderr]
      assert File.executable?(File.join(root, "jobs/catalog/ids.rb"))
    end
  end

  def test_every_kind_by_name_has_its_place
    in_project do |root|
      ["transform catalog:clean", "command es:create-index", "source marc:dump", "sink files:json"].each do
        cli("generate", *it.split)
      end

      assert_equal ["commands/es/create_index.rb", "lib/files/json.rb", "lib/marc/dump.rb",
                    "test/commands/es/create_index_test.rb", "test/lib/files/json_test.rb", "test/lib/marc/dump_test.rb",
                    "test/transforms/catalog/clean_test.rb", "transforms/catalog/clean.rb"],
                   Dir.glob("**/*.rb", base: root).sort
    end
  end

  def test_a_path_works_without_project_and_without_test
    in_tmpdir do
      code, stdout, = cli("generate", "command", "tools/release")

      assert_equal [0, "created tools/release.rb\n"], [code, stdout]
      refute_path_exists "test"
    end
  end

  def test_test_option_adds_a_test_for_a_path
    in_tmpdir do
      assert_equal "created tools/fix.rb\ncreated test/fix_test.rb\n", cli("generate", "job", "--test", "tools/fix.rb")[1]
    end
  end

  def test_no_test_option_leaves_out_the_test_of_a_name
    in_project do |root|
      cli("generate", "transform", "clean", "--no-test")

      refute_path_exists File.join(root, "test/transforms/clean_test.rb")
    end
  end

  def test_desc_goes_into_the_declaration
    in_project do |root|
      cli("generate", "job", "--desc", "Extract the ids", "catalog:ids")

      assert_includes File.read(File.join(root, "jobs/catalog/ids.rb")),
                      %(Metacrunch.job "catalog:ids", desc: "Extract the ids" do\n)
    end
  end

  def test_sources_and_sinks_tell_how_to_use_them
    in_project do
      assert_equal "In a job: require_relative the file, then sink Files::Json.new(...)",
                   cli("generate", "sink", "files:json")[1].lines.last.chomp
    end
  end

  def test_a_name_needs_a_project
    in_tmpdir do |dir|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: no Metacrunchfile found in #{dir} or above; give a path (./ids.rb) or create a " \
                       "project with metacrunch new"], [code, stderr.lines.first.chomp]
    end
  end

  def test_a_name_needs_a_metacrunchfile_that_loads
    in_project("Metacrunchfile" => "raise \"broken\"\n") do |root|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: could not load #{root}/Metacrunchfile: RuntimeError: broken"],
                   [code, stderr.lines.first.chomp]
    end
  end

  def test_refuses_a_name_declared_in_another_file
    in_project("commands/x.rb" => %(Metacrunch.command("catalog:ids") { run { nil } }\n)) do |root|
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: catalog:ids is already declared in commands/x.rb"], [code, stderr.lines.first.chomp]
      refute_path_exists File.join(root, "jobs/catalog/ids.rb")
    end
  end

  def test_force_regenerates_the_file_that_declares_the_name
    in_project do
      cli("generate", "job", "catalog:ids")
      code, stdout, stderr = cli("generate", "job", "catalog:ids", "--force")

      assert_equal [0, ""], [code, stderr]
      assert_includes stdout, "created jobs/catalog/ids.rb\n"
    end
  end

  def test_refuses_to_overwrite_without_force
    in_project do |root|
      FileUtils.mkdir_p(File.join(root, "test/jobs/catalog"))
      File.write(File.join(root, "test/jobs/catalog/ids_test.rb"), "mine")
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [2, "Error: test/jobs/catalog/ids_test.rb already exists; use --force to overwrite"],
                   [code, stderr.lines.first.chomp]
      refute_path_exists File.join(root, "jobs/catalog/ids.rb")
    end
  end

  def test_notes_a_name_the_metacrunchfile_does_not_load
    in_project("Metacrunchfile" => %(Metacrunch.load_files "jobs/*.rb"\n)) do
      code, _stdout, stderr = cli("generate", "job", "catalog:ids")

      assert_equal [0, "note: jobs/catalog/ids.rb is not loaded by the Metacrunchfile; it runs by path only\n"],
                   [code, stderr]
    end
  end

  def test_notes_a_path_the_metacrunchfile_does_not_load
    in_project do
      assert_equal "note: tools/fix.rb is not loaded by the Metacrunchfile; it runs by path only\n",
                   cli("generate", "job", "tools/fix.rb")[2]
    end
  end

  def test_warns_about_a_path_that_declares_a_name_twice
    in_project("jobs/fix.rb" => %(Metacrunch.job("fix") { source [] }\n)) do
      assert_equal "warning: fix is declared more than once (jobs/fix.rb, jobs/more/fix.rb); rename one\n",
                   cli("generate", "job", "jobs/more/fix.rb")[2]
    end
  end

  def test_warns_about_a_new_file_that_does_not_load
    in_project do
      broken = ->(target, **) { Metacrunch::Generators::Plan.new.add(target.file, "raise \"broken\"\n") }
      _code, _stdout, stderr = override(Metacrunch::Generators::Files, :plan, broken) do
        cli("generate", "job", "catalog:ids")
      end

      assert_equal "warning: jobs/catalog/ids.rb: RuntimeError: broken\n", stderr
    end
  end

  def test_warns_when_the_metacrunchfile_above_a_path_fails
    in_project("Metacrunchfile" => "raise \"broken\"\n") do |root|
      code, _stdout, stderr = cli("generate", "job", "tools/fix.rb")

      assert_equal [0, "warning: could not load #{root}/Metacrunchfile: RuntimeError: broken; " \
                       "tools/fix.rb is not checked\n"], [code, stderr]
    end
  end

  def test_help_lists_the_kinds
    _code, stdout, = cli("help", "generate")

    assert_match(%r{^Kinds:\n  job +jobs/NAME\.rb: reads JSON Lines from stdin}, stdout)
    assert_match(/--\[no-\]test +Create a test \(default: for a NAME\)/, stdout)
  end

  def test_generate_is_a_reserved_name
    assert Metacrunch::Names.reserved?("generate")
  end

  USAGE_ERRORS.each_with_index do |(args, message), index|
    define_method("test_usage_error_#{index}") do
      in_project do |root|
        code, _stdout, stderr = cli("generate", *args)

        assert_equal [2, "Error: #{message}"], [code, stderr.lines.first.chomp]
        assert_empty Dir.glob("**/*.rb", base: root)
      end
    end
  end

  private

  def in_tmpdir
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield File.realpath(dir) } }
  end

  # A project in a temporary directory, the working directory while the
  # block runs; files: path => code (a frozen string comment is added).
  def in_project(files = {})
    in_tmpdir do |root|
      {"Metacrunchfile" => METACRUNCHFILE}.merge(files).each do |path, code|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# frozen_string_literal: true\n\n#{code}")
      end
      yield root
    end
  end

end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/cli/generate_test.rb`
Expected: FAIL — `generate` is no command yet: `Error: unknown job, transform, command or file: generate (...)`.

- [ ] **Step 3: Write minimal implementation**

`lib/metacrunch/cli/generate.rb`:

```ruby
# frozen_string_literal: true

module Metacrunch
  class Cli
    # metacrunch generate: creates a job, transform, command, source or
    # sink with a test, by name in the project or by path anywhere (see
    # Generators::Target). After writing a job, transform or command it
    # loads the project again and tells when the new name is not in it.
    class GenerateCommand < Command

      NAME = "generate"
      SUMMARY = "Create a job, transform, command, source or sink"
      USAGE = "generate KIND [OPTIONS] NAME|PATH"
      HELP = <<~TEXT
        Kinds:
          job        jobs/NAME.rb: reads JSON Lines from stdin and writes them to stdout
          transform  transforms/NAME.rb: steps that jobs use
          command    commands/NAME.rb: a body that invokes jobs and commands
          source     lib/NAME.rb: a class that yields records
          sink       lib/NAME.rb: a class that writes records

        A NAME (catalog:ids) places the file in the project of the working directory,
        with a test in test/. A PATH (tools/fix.rb) places it there, without a test
        unless --test is given.

        Options:
      TEXT

      def initialize(streams, lookup)
        super
        @test = nil
        @desc = nil
        @force = false
      end

      private

      def define_options(parser)
        HELP.each_line(chomp: true) { parser.separator(it) }
        parser.on("--[no-]test", "Create a test (default: for a NAME)") { @test = it }
        parser.on("--desc TEXT", "Description for metacrunch --help (job, transform, command)") { @desc = it }
        parser.on("--force", "Overwrite existing files") { @force = true }
      end

      # Options may stand anywhere.
      def parse(parser, argv) = parser.permute!(argv)

      def execute(argv)
        kind, argument, *rest = argv
        check_arguments(kind, argument, rest)
        target = Generators::Target.for(kind, argument, cwd: Dir.pwd, root: (project&.root unless Names.path?(argument)))
        check_desc(target)
        check_declared(target)
        test = @test.nil? ? target.form == :name : @test
        Generators::Files.plan(target, desc: @desc, test:).write(force: @force, out: @stdout, cwd: Dir.pwd)
        target.declared? ? check_loaded(target) : @stdout.puts(usage_hint(target))
        EXIT_CODES[:ok]
      end

      def check_arguments(kind, argument, rest)
        raise UsageError, "no kind given (#{Generators::KIND_LIST})" unless kind
        raise UsageError, "unknown kind #{kind} (#{Generators::KIND_LIST})" unless Generators::KINDS.include?(kind)
        raise UsageError, "no name or path given" unless argument
        raise UsageError, "unexpected arguments: #{rest.join(" ")}" if rest.any?
      end

      # The project of the working directory, loaded once; its files that
      # did not load give the usual warnings.
      def project = @lookup.project(logger)

      def check_desc(target)
        return unless @desc
        raise UsageError, "--desc is for jobs, transforms and commands" unless target.declared?
        raise UsageError, "desc must be one line of text" if @desc.match?(/[\r\n]/)
      end

      # A name of the project declared in another file than the target's;
      # --force overwrites files, never names declared elsewhere.
      def check_declared(target)
        return unless target.form == :name && target.declared?

        other = project.declared(target.name).map(&:file).find { it != target.file }
        raise UsageError, "#{target.name} is already declared in #{project.relative(other)}" if other
      end

      # Loads the project at or above the new file again, without
      # warnings, and tells whether it has the new name. The files are
      # written either way.
      def check_loaded(target)
        file = Project.find(File.dirname(target.file))
        return unless file

        message = loaded_message(Project.load_file(file), target)
        @stderr.puts(message) if message
      rescue ProjectError => e
        @stderr.puts("warning: #{e.message.lines.first.chomp}; #{Generators.relative(target.file, Dir.pwd)} " \
                     "is not checked")
      end

      def loaded_message(project, target)
        error = project.load_errors.find { |path, _error| path == target.file }
        return "warning: #{project.load_error_summary(*error)}" if error
        return "warning: #{project.duplicate_message(target.name)}" if project.duplicates.key?(target.name)
        return if project.declared(target.name).any? { it.file == target.file }

        "note: #{Generators.relative(target.file, Dir.pwd)} is not loaded by the #{Project::FILE}; " \
          "it runs by path only"
      end

      def usage_hint(target) = "In a job: require_relative the file, then #{target.kind} #{target.constant}.new(...)"

    end
  end
end
```

In `lib/metacrunch/cli.rb`, after `require_relative "cli/new"` add `require_relative "cli/generate"`, and make `COMMANDS`:

```ruby
    COMMANDS = {
      "run" => RunCommand, "check" => CheckCommand, "trace" => TraceCommand, "new" => NewCommand,
      "generate" => GenerateCommand, "credentials" => CredentialsCommand
    }.freeze
```

In `lib/metacrunch/names.rb`:

```ruby
    RESERVED = ["run", "check", "trace", "new", "generate", "credentials", "help"].freeze
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby -Ilib -Itest test/cli/generate_test.rb && bundle exec ruby -Ilib -Itest test/unit/names_test.rb && bundle exec ruby -Ilib -Itest test/cli/cli_test.rb`
Expected: PASS. If the `duplicate_message` order in `test_warns_about_a_path_that_declares_a_name_twice` differs, check `Project#load_files` (sorted paths) before changing the expectation.

- [ ] **Step 5: Commit**

```bash
git add lib/metacrunch/cli.rb lib/metacrunch/cli/generate.rb lib/metacrunch/names.rb test/cli/generate_test.rb
git commit -m "Generate jobs, transforms, commands, sources and sinks

metacrunch generate KIND NAME|PATH writes a file and its test: a name
below the project root from any of its directories, a path anywhere.
It refuses names declared elsewhere and existing files without --force,
and loads the project again afterwards to note a new name that the
Metacrunchfile does not load. generate becomes a reserved name.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: End to end

**Files:**
- Test: `test/cli/exe_generators_test.rb`

**Interfaces:**
- Consumes: `CliHelper#cli` (in-process generation), `exe/metacrunch`, the generated tests, RuboCop (`Gem.bin_path("rubocop", "rubocop")`, repository `.rubocop.yml`).
- Produces: nothing new in Ruby.

- [ ] **Step 1: Write the test**

`test/cli/exe_generators_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Generates a project and files as a user would, then runs what was
# generated: the jobs through exe/metacrunch, the generated tests in one
# process, RuboCop over all of it.
class ExeGeneratorsTest < Minitest::Test

  include CliHelper

  ROOT = File.expand_path("../..", __dir__)
  LIB = File.join(ROOT, "lib")
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze
  RECORDS = %({"id":1,"title":"A"}\n{"title":"B"}\n)
  KEPT = [{"id" => 1, "title" => "A"}].freeze
  BY_NAME = [["job", "catalog:ids"], ["transform", "catalog:clean"], ["command", "catalog:re-index"],
             ["source", "files:lines"], ["sink", "files:json"]].freeze
  BY_PATH = [["job", "tools/fix"], ["transform", "tools/tidy"], ["command", "tools/publish"],
             ["source", "tools/lines"], ["sink", "tools/json_file"]].freeze

  def test_a_new_project_lists_and_runs_what_was_generated
    in_tmpdir do |dir|
      root = generate_project(dir)
      help, = metacrunch("--help", chdir: root)
      outputs = ["catalog:ids", "catalog:clean"].map { metacrunch(it, stdin: RECORDS, chdir: root).first }
      _stdout, log, status = metacrunch("catalog:re-index", chdir: root)

      assert_match(/^Jobs .*\n  catalog:ids.*^Transforms .*\n  catalog:clean.*^Project commands .*\n  catalog:re-index/m,
                   help)
      assert_equal [KEPT, KEPT], outputs.map { |out| out.lines.map { JSON.parse(it) } }
      assert_equal [true, true], [status.success?, log.include?("catalog:re-index: nothing to do yet")]
    end
  end

  def test_the_generated_tests_of_a_project_pass_in_one_run
    in_tmpdir do |dir|
      stdout, stderr, status = run_tests(generate_project(dir))

      assert_predicate status, :success?, stdout + stderr
      assert_match(/^6 runs, \d+ assertions, 0 failures, 0 errors/, stdout)
    end
  end

  def test_files_by_path_run_and_pass_their_tests_without_project
    in_tmpdir do |dir|
      generate_paths(dir)
      fixed, = metacrunch("run", "tools/fix.rb", stdin: RECORDS, chdir: dir)
      stdout, stderr, status = run_tests(dir)

      assert_equal KEPT, fixed.lines.map { JSON.parse(it) }
      assert_predicate status, :success?, stdout + stderr
      assert_match(/^5 runs, \d+ assertions, 0 failures, 0 errors/, stdout)
    end
  end

  def test_generated_files_pass_rubocop
    in_tmpdir do |dir|
      generate_project(dir)
      generate_paths(File.join(dir, "loose").tap { FileUtils.mkdir_p(it) })
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, Gem.bin_path("rubocop", "rubocop"), "--config",
                                              File.join(ROOT, ".rubocop.yml"), "--cache", "false", "--format",
                                              "simple", chdir: dir)

      assert_predicate status, :success?, stdout + stderr
      assert_match(/\b\d+ files inspected, no offenses detected/, stdout)
    end
  end

  private

  # catalog/ in dir with the five kinds by name, generated from
  # catalog/jobs/, a directory below the root. Returns the root.
  def generate_project(dir)
    Dir.chdir(dir) { generate("new", "catalog") }
    root = File.join(dir, "catalog")
    Dir.chdir(File.join(root, "jobs")) { BY_NAME.each { |kind, name| generate("generate", kind, name) } }
    root
  end

  # The five kinds by path with tests, in dir.
  def generate_paths(dir)
    Dir.chdir(dir) { BY_PATH.each { |kind, path| generate("generate", kind, "--test", path) } }
  end

  def generate(*args)
    code, _stdout, stderr = cli(*args)
    raise "metacrunch #{args.join(" ")} failed (#{code}): #{stderr}" unless code.zero?
  end

  def run_tests(dir)
    tests = Dir.glob("test/**/*_test.rb", base: dir)
    Open3.capture3(CLEAN_ENV, RbConfig.ruby, "-I", LIB, "-e", "ARGV.each { require File.expand_path(it) }", *tests,
                   chdir: dir)
  end

  def metacrunch(*, chdir:, stdin: "")
    Open3.capture3(CLEAN_ENV, RbConfig.ruby, "-I", LIB, File.join(ROOT, "exe", "metacrunch"), *, stdin_data: stdin,
                                                                                               chdir:)
  end

  def in_tmpdir
    Dir.mktmpdir { |dir| yield File.realpath(dir) }
  end

end
```

- [ ] **Step 2: Run the test**

Run: `bundle exec ruby -Ilib -Itest test/cli/exe_generators_test.rb`
Expected: PASS. This task adds no production code; if a test fails, the failure points at a template or command of Tasks 4–8: fix it there (a RuboCop offense in a template is fixed in the template, then re-run Tasks 4–5 unit tests), never by loosening this test. Note any such fix in the commit body.

- [ ] **Step 3: Run the whole suite**

Run: `bundle exec rake`
Expected: all tests pass, RuboCop clean, coverage above 95 % / 90 %.

- [ ] **Step 4: Commit**

```bash
git add test/cli/exe_generators_test.rb
git commit -m "Run what new and generate create, end to end

A project with all five kinds by name, generated from a subdirectory,
lists them in --help, runs its job, transform and command through
exe/metacrunch and passes its generated tests in one process; the same
kinds by path pass outside any project; RuboCop finds no offense.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: examples/project in the layout of generate

**Files:**
- Modify: `examples/project/Metacrunchfile`
- Create: `examples/project/Rakefile`
- Move: `examples/project/jobs/ids.rb` → `examples/project/jobs/catalog/ids.rb` (and change its data path)
- Move: `examples/project/transforms/public.rb` → `examples/project/transforms/catalog/public.rb`
- Move: `examples/project/commands/release.rb` → `examples/project/commands/catalog/release.rb`
- Create: `examples/project/test/test_helper.rb`, `test/project_test.rb`, `test/jobs/catalog_test.rb`, `test/jobs/catalog/ids_test.rb`, `test/transforms/catalog/public_test.rb`, `test/commands/catalog/release_test.rb`
- Delete: `examples/project/test/public_test.rb`, `examples/project/test/release_test.rb`
- Modify: `examples/Readme.md:14,31-32`
- Test: `test/integration/examples_test.rb:149-157`

**Interfaces:**
- Consumes: the skeleton's `test_helper.rb` and `project_test.rb` contents (Task 6), the naming rules of Task 1.
- Produces: nothing new in Ruby.

- [ ] **Step 1: Update the integration test**

In `test/integration/examples_test.rb`, `test_the_project_example_tests_pass` becomes:

```ruby
  def test_the_project_example_tests_pass
    tests = Dir[example("project/test/**/*_test.rb")]
    arguments = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", "ARGV.each { require it }", *tests]
    stdout, stderr, status = Open3.capture3(*arguments)

    assert_equal 5, tests.size
    assert_predicate status, :success?, stdout + stderr
    assert_match(/ 0 failures, 0 errors/, stdout)
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec ruby -Ilib -Itest test/integration/examples_test.rb -n test_the_project_example_tests_pass`
Expected: FAIL with `Expected: 5 Actual: 2`.

- [ ] **Step 3: Move and write the files**

```bash
cd examples/project
mkdir -p jobs/catalog transforms/catalog commands/catalog test/jobs/catalog test/transforms/catalog test/commands/catalog
git mv jobs/ids.rb jobs/catalog/ids.rb
git mv transforms/public.rb transforms/catalog/public.rb
git mv commands/release.rb commands/catalog/release.rb
git rm -q test/public_test.rb test/release_test.rb
cd ../..
```

In `examples/project/jobs/catalog/ids.rb` the default input moves one level up:

```ruby
    param :input, String, default: File.expand_path("../../data/titles.jsonl", __dir__),
```

`examples/project/Metacrunchfile`:

```ruby
# frozen_string_literal: true

# The project file: it names the jobs, transforms and commands of this
# directory, so that `metacrunch NAME` runs them from any directory below
# it. The files are where `metacrunch generate` puts them: catalog:ids in
# jobs/catalog/ids.rb, its test in test/jobs/catalog/ids_test.rb. The
# project has no Gemfile, so that it runs with metacrunch from this
# repository.
#
#   cd examples/project
#   bundle exec metacrunch --help
#   bundle exec metacrunch catalog:release
#   bundle exec metacrunch catalog:ids
#   bundle exec rake
Metacrunch.load_files "jobs/**/*.rb", "transforms/**/*.rb", "commands/**/*.rb"
```

`examples/project/Rakefile`, `examples/project/test/test_helper.rb` and `examples/project/test/project_test.rb`: the exact contents of `lib/metacrunch/templates/project/Rakefile.erb`, `test_helper.rb.erb` and `project_test.rb.erb` (they contain no ERB tags).

`examples/project/test/transforms/catalog/public_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the transform catalog:public alone with Metacrunch::Testing.run.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"

class CatalogPublicTransformTest < Minitest::Test

  RECORDS = [{"id" => "a", "title" => "A", "public" => true}, {"id" => "b", "title" => "B", "public" => false}].freeze

  def test_keeps_the_public_records_with_the_given_fields
    result = Metacrunch::Testing.run(PROJECT.fetch("catalog:public"), params: {fields: ["id"]}, source: RECORDS)

    assert_equal [{"id" => "a"}], result.records
    assert_equal(["Not public"], result.rejects.map { |_record, rejection| rejection.reason })
  end

end
```

`examples/project/test/jobs/catalog_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the job catalog with the steps of catalog:public. project: lets
# the names of use resolve from any working directory.
#
#   cd examples/project && bundle exec rake

require_relative "../test_helper"
require "tmpdir"

class CatalogJobTest < Minitest::Test

  def test_names_the_steps_of_the_transform
    Dir.mktmpdir do |out|
      result = Metacrunch::Testing.run(PROJECT.fetch("catalog"), params: {output: out}, project: PROJECT)

      assert_equal ["catalog:public/reject#1", "catalog:public/map#2"], result.stats.steps.keys
      assert_equal 4, result.records.size
    end
  end

end
```

`examples/project/test/jobs/catalog/ids_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the job catalog:ids, which uses catalog:public with other fields.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"

class CatalogIdsJobTest < Minitest::Test

  def test_keeps_the_ids_of_the_public_titles
    result = Metacrunch::Testing.run(PROJECT.fetch("catalog:ids"), project: PROJECT)

    assert_equal [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t4"}, {"id" => "t5"}], result.records
  end

end
```

`examples/project/test/commands/catalog/release_test.rb`:

```ruby
# frozen_string_literal: true

# Tests the orchestration of catalog:release without running the job:
# Metacrunch::Testing.invoke records what the command invokes and answers
# with stubbed results.
#
#   cd examples/project && bundle exec rake

require_relative "../../test_helper"
require "tmpdir"

class CatalogReleaseCommandTest < Minitest::Test

  def test_switches_current_after_a_clean_run
    Dir.mktmpdir do |out|
      run = release(out)

      assert_equal [:ok, ["catalog"]], [run.status, run.invoked.map(&:name)]
      assert_equal ["--output", run.value.to_s], run.invoked.first.argv
      assert_equal File.realpath(run.value), File.realpath(File.join(out, "current"))
    end
  end

  def test_keeps_current_when_records_failed
    Dir.mktmpdir do |out|
      run = release(out, stubs: {"catalog" => :ok_with_failures})

      assert_equal :ok_with_failures, run.status
      refute_path_exists File.join(out, "current")
    end
  end

  private

  def release(out, stubs: {})
    Metacrunch::Testing.invoke(PROJECT, "catalog:release", params: {out:}, stubs:)
  end

end
```

In `examples/Readme.md`, the project row (line 14) links `project/transforms/catalog/public.rb` instead of `project/transforms/public.rb` and its last sentence reads: "[`project/test/`](project/test) mirrors the files, as `metacrunch generate` creates them: it tests the command with `Metacrunch::Testing.invoke`, the transform and the jobs with `Metacrunch::Testing.run`, and that every file loads." Lines 31-32 become one line:

```
$ (cd examples/project && bundle exec rake)
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec ruby -Ilib -Itest test/integration/examples_test.rb && (cd examples/project && bundle exec rake)`
Expected: PASS; the example's own `rake` reports `5 runs, ... 0 failures, 0 errors`.

- [ ] **Step 5: Commit**

```bash
git add -A examples test/integration/examples_test.rb
git commit -m "Lay out the example project as generate does

The jobs, transform and command move to the files their names give
(catalog:ids in jobs/catalog/ids.rb), the Metacrunchfile globs are
recursive, and the tests mirror the files with a test helper, a test
of the project and a Rakefile, so the example shows what new and
generate create.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Readme and CHANGELOG

**Files:**
- Modify: `Readme.md` (Installation, A first job, Debugging and checking jobs, Projects and commands, new section, Testing commands)
- Modify: `CHANGELOG.md:16,36-37,49-51,52-54`

**Interfaces:** none.

- [ ] **Step 1: Readme edits**

1. Installation: the Gemfile line becomes `gem "metacrunch", github: "ubpb/metacrunch", branch: "metacrunch-ng"`.
2. "A first job": after the paragraph "More jobs with sample data, …" add:

   > `metacrunch new` creates a project, and `metacrunch generate` jobs, transforms, commands, sources and sinks in it
   > (see [Generating projects and files](#generating-projects-and-files)).

3. "Debugging and checking jobs": delete the line `$ metacrunch new --test jobs/marc2json.rb` and the sentence "`new` creates a filter job that runs right away, and with `--test` a Minitest test for it." (the paragraph then ends after "without opening, reading or running anything.").
4. "Projects and commands": the tree line `├── commands/catalog.rb       Metacrunch.command "catalog:reindex", desc: "..."` becomes `├── commands/catalog/reindex.rb  Metacrunch.command "catalog:reindex", desc: "..."` (re-align the column), and the tree gains `└── test/` after `├── lib/` (with `lib/` becoming `├── lib/`). In the paragraph on loading, "and when a job run by path uses a transform by name. The other built-in commands never load it" becomes "when a job run by path uses a transform by name, and for `generate` with a name and after it writes a job, transform or command. The other built-in commands never load it". In the list of reserved names add `generate`: (`run`, `check`, `trace`, `new`, `generate`, `credentials`, `help`).
5. "### Commands": the code comment `# commands/catalog.rb` becomes `# commands/catalog/reindex.rb`.
6. Insert this section before "### Commands":

````markdown
### Generating projects and files

```
$ metacrunch new catalog
$ cd catalog
$ metacrunch generate job catalog:ids
$ metacrunch generate transform normalize --desc "Tidy the titles"
$ metacrunch generate source marc:dump
$ metacrunch generate command --test ~/bin/release.rb      # a single file, no project needed
```

`new DIR` creates a project: a `Metacrunchfile` that loads `jobs/`, `transforms/` and `commands/`, a `Gemfile`, a
`Rakefile` whose `rake test` runs `test/**/*_test.rb`, a `lib/` for helpers, and `test/project_test.rb`, which fails
when a file of the project does not load or a name is declared twice. It writes into a new or empty directory, or next
to other files, which it leaves alone; existing files of the skeleton need `--force`.

`generate KIND NAME|PATH` creates a file that runs right away and a test that passes:

| Command | Creates | What it is |
|---|---|---|
| `generate job catalog:ids` | `jobs/catalog/ids.rb`, `test/jobs/catalog/ids_test.rb` | a job that filters JSON Lines from stdin to stdout |
| `generate transform normalize` | `transforms/normalize.rb`, `test/transforms/normalize_test.rb` | steps for `use`; alone a filter like the job |
| `generate command es:create-index` | `commands/es/create_index.rb`, `test/commands/es/create_index_test.rb` | a body that logs a line, with `invoke` as a comment |
| `generate source marc:dump` | `lib/marc/dump.rb` (`Marc::Dump`), `test/lib/marc/dump_test.rb` | a class that yields a record for each line of a file |
| `generate sink json_array` | `lib/json_array.rb` (`JsonArray`), `test/lib/json_array_test.rb` | a class that writes each record as a line of JSON |

- A name places the file below the project root, from any directory of the project: `:` separates directories, and
  `-` becomes `_` in file names. The test goes to the same place below `test/`. A name needs a `Metacrunchfile`.
- A path (it contains `/` or `.`) places the file there, also without a project, and the file name gives the name. It
  gets a test only with `--test`, in `test/` below the working directory, which loads the file by its path.
- `--no-test` leaves the test out, `--desc TEXT` sets the description of a job, transform or command, and `--force`
  overwrites existing files. A name declared in another file of the project is refused.
- Sources and sinks are classes, not names of the project: the parts of their names are `a-z`, `0-9` and `_`,
  starting with a letter, and they must not reopen a class such as `File`.
- After writing a job, transform or command, `generate` loads the project again and notes when the
  `Metacrunchfile` does not load the new file, for example because its globs are not recursive (`jobs/*.rb`).
````

7. "Testing commands": after the paragraph that ends "`run.status` is `:ok`, `:ok_with_failures`, or `:aborted` with the exception in `run.error`." add:

```markdown
A command file outside a project is tested the same way: `Metacrunch.load_command("tools/release.rb")` loads it, and
`Metacrunch::Testing.invoke(command, params: {...}, stubs: {...})` runs it. Its names resolve in `project:`, else in
the project of the nearest `Metacrunchfile` above the working directory.
```

- [ ] **Step 2: CHANGELOG edits**

1. Line 16: "The CLI has commands (`run`, `check`, `trace`, `new`)" → "The CLI has commands (`run`, `check`, `trace`, `new`, `generate`, `credentials`)".
2. Lines 36-37: "`metacrunch new` creates one." → "`metacrunch new` creates a project, and `metacrunch generate` a job, transform, command, source or sink in it or by path, each with a test."
3. Commands entry (ends "`Metacrunch::Testing.invoke` tests a command without running what it invokes."): append " `Metacrunch.load_command` loads a command file, and `Testing.invoke` takes such a command, too."
4. Names entry: "and `metacrunch new` for file names that would give one or the name of a built-in command" → "and `metacrunch generate` for names and file names that would give one or the name of a built-in command".

- [ ] **Step 3: Check the docs against the code**

Run `bundle exec rake`, then from the worktree root:

```bash
repo=$(pwd); tmp=$(mktemp -d)
(cd "$tmp" && bundle exec --gemfile "$repo/Gemfile" ruby -I"$repo/lib" "$repo/exe/metacrunch" new demo &&
 cd demo && bundle exec --gemfile "$repo/Gemfile" ruby -I"$repo/lib" "$repo/exe/metacrunch" generate job catalog:ids)
grep -n "new --test\|commands/catalog.rb" Readme.md
```

The output matches the Readme section (created lines, Next steps); `grep` finds nothing.
Expected: green suite, no stale references.

- [ ] **Step 4: Commit**

```bash
git add Readme.md CHANGELOG.md
git commit -m "Describe new and generate in the Readme and the changelog

A section on generating projects and files, the Gemfile line with the
metacrunch-ng branch (master holds 4.x until 5.0), the project layout
as generate creates it, generate among the reserved names, and testing
command files with load_command.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
