# frozen_string_literal: true

require "test_helper"

class DefinitionTest < Minitest::Test

  Definition = Metacrunch::Elasticsearch::Definition

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_reads_json_files_with_comments_and_trailing_commas
    path = file("settings.jsonc", <<~JSON)
      {
        // replicas are raised after the load
        "number_of_replicas": 0, /* for now */
        "analysis": {"analyzer": {"folding": {"filter": ["lowercase", "asciifolding",]}}},
      }
    JSON

    assert_equal({"number_of_replicas" => 0,
                  "analysis" => {"analyzer" => {"folding" => {"filter" => ["lowercase", "asciifolding"]}}}},
                 Definition.load(Pathname(path), "settings"))
  end

  def test_takes_hashes_with_string_keys_and_nil
    assert_equal({"properties" => {"title" => {"type" => "text"}}, "dynamic_templates" => [{"strings" => {}}]},
                 Definition.load({properties: {title: {type: "text"}}, dynamic_templates: [{strings: {}}]}, "mappings"))
    assert_nil Definition.load(nil, "mappings")
  end

  def test_refuses_other_values
    error = assert_raises(ArgumentError) { Definition.load(42, "mappings") }

    assert_equal "mappings must be a Hash or a path, got Integer", error.message
  end

  def test_file_errors_name_the_file
    missing = File.join(@dir, "missing.json")
    invalid = file("invalid.json", "{")
    array = file("array.json", "[]")

    assert_equal "#{missing}: No such file or directory", load_error(missing)
    assert_match(/\A#{Regexp.escape(invalid)}: \S/, load_error(invalid))
    assert_equal "#{array}: the file must hold a JSON object", load_error(array)
  end

  def test_flat_settings_give_one_form_whatever_the_input_uses
    nested = {"index" => {"number_of_replicas" => 1}, "refresh_interval" => "1s", "analysis" => {"analyzer" => {}}}
    flat = {"index.number_of_replicas" => 1, "index.refresh_interval" => "1s"}

    assert_equal flat, Definition.flat_settings(nested)
    assert_equal flat, Definition.flat_settings({"number_of_replicas" => 1, "index.refresh_interval" => "1s"})
    assert_empty Definition.flat_settings(nil)
  end

  private

  def file(name, text)
    File.join(@dir, name).tap { File.write(it, text) }
  end

  def load_error(path)
    assert_raises(Metacrunch::Elasticsearch::Error) { Definition.load(path, "settings") }.message
  end

end
