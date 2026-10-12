# frozen_string_literal: true

require_relative "marcxml/version"
require_relative "marcxml/errors"

module Metacrunch
  # MARCXML for metacrunch: an ordered record model (Record, ControlField,
  # DataField, Subfield), a parser, a serializer, and a source (Reader) and
  # a sink (Writer). Only Reader and Writer depend on metacrunch.
  module Marcxml

    # The namespace of the MARC 21 XML schema.
    NAMESPACE = "http://www.loc.gov/MARC21/slim"

  end
end
