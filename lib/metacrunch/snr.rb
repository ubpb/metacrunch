module Metacrunch
  #
  # A SNR object (Simple Normalized Record) is a simple data structure
  # that you can use as a target resource when performing data normalization routines.
  # A DNSR record consists of unique sections. A section is unique identified by it's
  # name. Each section can hold many fields that store the actual values.
  #
  # A SNR object can be transformed into XML or JSON to allow easy integration into
  # existing tools and workflows.
  #
  # For example: If you normalize MAB XML data for use in a search engine you can
  # use a SNR object to store your normalized values.
  #
  class SNR
    require_relative "./snr/section"
    require_relative "./snr/field"

    # ------------------------------------------------------------------------------
    # Common API
    # ------------------------------------------------------------------------------

    #
    # Adds a field with a value to a section. If the section with the given name
    # doesn't exists it will be created.
    #
    # @param [String] section_name
    # @param [String] field_name
    # @param [#to_s] value
    #
    def add(section_name, field_name, value)
      section = self.section(section_name) || Section.new(section_name)
      section.add(field_name, value)
      add_section(section)
    end

    # ------------------------------------------------------------------------------
    # Sections
    # ------------------------------------------------------------------------------

    #
    # @return [Hash{String => Metacrunch::SNR::Section}]
    # @private
    #
    def sections_struct
      @sections_struct ||= {}
    end
    private :sections_struct

    #
    # Return all sections.
    #
    # @return [Array<Metacrunch::SNR::Section>]
    #
    def sections
      sections_struct.values
    end

    #
    # Get section by name.
    #
    # @param  [String] name Name of the section
    # @return [Metacrunch::SNR::Section, nil] section by name or nil if a section
    #   with the given name doesn't exists.
    #
    def section(name)
      sections_struct[name]
    end

    #
    # Adds / replaces a section. The name of the section is used as a unique identifier.
    # Therefore if you add a section with a name that already exists, the new section
    # will override the existing one.
    #
    # @param [Metacrunch::SNR::Section] section
    # @return [Metacrunch::SNR::Section]
    #
    def add_section(section)
      sections_struct[section.name] = section
    end

    # ------------------------------------------------------------------------------
    # Serialization
    # ------------------------------------------------------------------------------

    #
    # Transforms the SNR into XML.
    #
    # @return [String] The SNR as XML string.
    #
    def to_xml
      doc  = Ox::Document.new(version: "1.0")
      root = Ox::Element.new("snr")

      sections.each do |section|
        section_node = Ox::Element.new(section.name)

        section.fields.each do |field|
          field_node = Ox::Element.new(field.name)
          field_node << field.value
          section_node << field_node
        end

        root << section_node
      end

      doc << root

      Ox.dump(doc)
    end

  end
end
