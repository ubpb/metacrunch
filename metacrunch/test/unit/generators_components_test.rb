# frozen_string_literal: true

require "test_helper"
require "prism"
require "rubygems/package"
require "tmpdir"
require "zlib"
require "metacrunch/generators"

class GeneratorsComponentsTest < Minitest::Test

  Generators = Metacrunch::Generators
  ROOT = Pathname("/work/catalog")
  CWD = "/work/catalog"

  def test_a_source_by_name_is_a_class_in_its_modules_with_a_test
    entries = plan("source", "a:b:lines").entries

    assert_equal([ROOT.join("lib/a/b/lines.rb").to_s, ROOT.join("test/lib/a/b/lines_test.rb").to_s],
                 entries.map(&:path))
    assert_match(/\A# frozen_string_literal: true\n\nrequire "metacrunch"\n\nmodule A\n  module B\n    # A source:/,
                 entries.first.content)
  end

  def test_a_sink_by_path_has_no_modules
    content = plan("sink", "lib/json_file").entries.first.content

    assert_match(/\A# frozen_string_literal: true\n\nrequire "json"\nrequire "metacrunch"\n\n# A sink:/, content)
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

  # Inside module Out, File would be the class Out::File itself.
  def test_classes_named_file_still_reach_ruby_s_file
    in_project do |root|
      write(plan("sink", "out:file", root:), root)
      write(plan("source", "marc:file", root:), root)
      sink = load_class(root.join("lib/out/file.rb"), "Out::File").new(root.join("out.jsonl").to_s)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.close
      source = load_class(root.join("lib/marc/file.rb"), "Marc::File").new(root.join("out.jsonl").to_s)

      assert_equal [{"line" => %({"id":1})}], source.enum_for(:each).to_a
    end
  end

  def test_a_source_reads_gzip_tar_and_arrays
    in_project do |root|
      write(plan("source", "marc:dump", root:), root)
      File.binwrite(root.join("a.txt.gz"), Zlib.gzip("a\n"))
      io = StringIO.new(+"", "wb")
      Gem::Package::TarWriter.new(io) { |tar| tar.add_file_simple("b.txt", 0o644, 2) { it.write("b\n") } }
      File.binwrite(root.join("b.tar"), io.string)
      source = load_class(root.join("lib/marc/dump.rb"), "Marc::Dump").new([root.join("a.txt.gz"), root.join("b.tar")])

      assert_equal [{"line" => "a"}, {"line" => "b"}], source.enum_for(:each).to_a
      assert_in_delta 1.0, source.progress
    end
  end

  def test_a_sink_compresses_gz_names
    in_project do |root|
      write(plan("sink", "out:json", root:), root)
      sink = load_class(root.join("lib/out/json.rb"), "Out::Json").new(root.join("out.jsonl.gz").to_s)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.close

      assert_equal %({"id":1}\n), Zlib.gunzip(File.binread(root.join("out.jsonl.gz")))
    end
  end

  # Inside a class A::Metacrunch, Metacrunch would be that class itself.
  def test_classes_named_metacrunch_still_reach_the_layer
    in_project do |root|
      write(plan("sink", "out:metacrunch", root:), root)
      write(plan("source", "marc:metacrunch", root:), root)
      sink = load_class(root.join("lib/out/metacrunch.rb"), "Out::Metacrunch").new(root.join("out.jsonl").to_s)
      sink.open(nil)
      sink.write({"id" => 1})
      sink.close
      source = load_class(root.join("lib/marc/metacrunch.rb"), "Marc::Metacrunch").new(root.join("out.jsonl").to_s)

      assert_equal [{"line" => %({"id":1})}], source.enum_for(:each).to_a
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
