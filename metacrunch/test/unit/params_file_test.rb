# frozen_string_literal: true

require "test_helper"

class ParamsFileTest < Minitest::Test

  ParamsFile = Metacrunch::ParamsFile

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.chmod_R(0o700, @dir)
    FileUtils.remove_entry(@dir)
  end

  def test_merges_the_environment_over_default
    selection = load(<<~YAML).select("production")
      default: {batch: "1000", index: titles}
      production: {index: titles-prod}
    YAML

    assert_equal ["titles-prod", "production"], selection.fetch("index")
    assert_equal ["1000", "default"], selection.fetch("batch")
    assert_equal ["default", "production"], selection.sections
  end

  def test_without_environment_only_default_counts
    selection = load(<<~YAML).select(nil)
      default: {index: titles}
      production: {es_url: http://es-prod:9200}
    YAML

    assert_equal ["titles", "default"], selection.fetch("index")
    assert_nil selection.fetch("es_url")
    assert_equal ["default"], selection.sections
  end

  def test_reads_scalars_as_text
    selection = load("default: {id: 0123, dry: no, batch: 1000}\n").select(nil)

    assert_equal(["0123", "no", "1000"], ["id", "dry", "batch"].map { selection.fetch(it).first })
  end

  def test_null_means_not_given_and_overrides_default
    selection = load("default: {index: titles}\nproduction: {index: ~}\n").select("production")

    assert_equal [nil, "production"], selection.fetch("index")
  end

  def test_lists_and_references
    selection = load("default: {tags: [a, b], api_key: {credential: catalog.api_key}}\n").select(nil)

    assert_equal ["a", "b"], selection.fetch("tags").first
    assert_equal ParamsFile::Reference.new(path: "catalog.api_key"), selection.fetch("api_key").first
  end

  def test_anchors_and_merge_keys
    selection = load(<<~YAML).select("production")
      default: &d {batch: 5}
      production: {<<: *d, index: x}
    YAML

    assert_equal ["5", "production"], selection.fetch("batch")
    assert_equal ["x", "production"], selection.fetch("index")
  end

  def test_a_file_with_only_default_serves_every_environment
    selection = load("default: {index: titles}\n").select("staging")

    assert_equal ["titles", "default"], selection.fetch("index")
    assert_equal ["default"], selection.sections
  end

  def test_an_environment_without_section_fails
    file = load("default: {index: titles}\nstaging: {index: s}\n")
    error = assert_raises(Metacrunch::ParamError) { file.select("production") }

    assert_equal "#{file.path} has no section for environment production (sections: default, staging)", error.message
  end

  def test_errors_of_the_file
    {
      "- a\n" => "FILE must contain a mapping of sections (default: and environments) at the top level",
      "Prod: {index: x}\n" =>
        %(FILE: invalid section "Prod": use default or an environment name (a-z, 0-9, _ and -)),
      "batch: 1000\n" => "FILE: section batch must be a mapping of parameters",
      "production: {api_key: {a: 1}}\n" =>
        "FILE: production.api_key: a value must be text, a list or {credential: PATH}",
      "default: {tags: [[1]]}\n" => "FILE: default.tags: a value must be text, a list or {credential: PATH}",
      "default: {api_key: {credential: x.y, other: 1}}\n" =>
        "FILE: default.api_key: a value must be text, a list or {credential: PATH}",
      "default: {api_key: {credential: a..b}}\n" =>
        %(FILE: default.api_key: credential must be a path like "catalog.api_key", got "a..b"),
      "default: [\n" => "invalid YAML in FILE at line 2, column 1"
    }.each do |content, message|
      path = write(content)
      error = assert_raises(Metacrunch::ParamError, content) { ParamsFile.load(path) }

      assert_equal message.gsub("FILE", path), error.message
    end
  end

  def test_a_missing_file
    error = assert_raises(Metacrunch::ParamError) { ParamsFile.load("missing.yml") }

    assert_equal "params file not found: missing.yml", error.message
  end

  def test_an_unreadable_file
    skip "root reads every file" if Process.uid.zero?

    path = write("default: {}\n")
    File.chmod(0, path)
    error = assert_raises(Metacrunch::ParamError) { ParamsFile.load(path) }

    assert_equal "cannot read params file #{path}: Permission denied", error.message
  end

  def test_each_key_yields_every_section
    file = load("default: {batch: 1, index: x}\nstaging: {index: s}\n")

    assert_equal [["default", "batch"], ["default", "index"], ["staging", "index"]], file.to_enum(:each_key).to_a
  end

  def test_an_empty_file_has_no_values
    assert_nil load("").select(nil).fetch("index")
    assert_nil load("production:\n").select("production").fetch("index")
  end

  private

  def write(content)
    path = File.join(@dir, "params-#{content.hash.abs}.yml")
    File.write(path, content)
    path
  end

  def load(content) = ParamsFile.load(write(content))

end
