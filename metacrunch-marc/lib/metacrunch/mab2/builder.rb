require_relative "./document"

module Metacrunch
  module Mab2
    class Builder

      attr_reader :document

      def self.build(&block)
        builder = new
        document = builder.instance_eval(&block) if block_given?
        document || Document.new
      end

      def initialize
        @document = Document.new
      end

      def controlfield(tag, values)
        controlfield = Document::Controlfield.new(tag, values)
        @document.add_controlfield(controlfield)
        @document
      end

      def datafield(tag, ind1:nil, ind2:nil, &block)
        datafield = Document::Datafield.new(tag, ind1: ind1, ind2: ind2)
        @document.add_datafield(datafield)

        if block_given?
          subfield_builder = SubfieldBuilder.new(datafield)
          subfield_builder.instance_eval(&block)
        end

        @document
      end


      class SubfieldBuilder
        def initialize(datafield)
          @datafield = datafield
        end

        def subfield(code, value)
          subfield = Document::Subfield.new(code, value)
          @datafield.add_subfield(subfield)
          subfield
        end
      end

    end
  end
end
