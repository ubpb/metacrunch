# frozen_string_literal: true

require "metacrunch/marc"

# Converts MARC records from MARCXML, ISO 2709 or MARC-in-JSON (told by the
# content of each file) to the format --to names. Records are parsed and
# serialized in steps, so with --workers the processes exchange record
# Strings, which cost little to send.
#
#   bundle exec metacrunch run examples/convert.rb --to iso2709 --target tmp/catalog.mrc examples/data/catalog.xml
Metacrunch.job do
  params do
    param :to, String, default: "xml", desc: "output format: xml, iso2709 or json"
    param :target, String, default: "-", desc: "file for the converted records (- for stdout)"
    args :files, min: 1
  end

  to = params.to.to_sym
  source Metacrunch::Marc::Reader.new(params.files, parse: false)

  map(name: "parse") { Metacrunch::Marc.parse(it) }

  map(name: "serialize") do |record|
    case to
    when :iso2709 then record.to_iso2709
    when :json then record.to_json
    else record.to_xml(namespace: false)
    end
  end

  sink Metacrunch::Marc::Writer.new(params.target, format: to)
end
