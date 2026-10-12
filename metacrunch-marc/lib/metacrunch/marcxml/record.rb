# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A MARC record: a leader (a String or nil), the type attribute of
    # <record> (e.g. "Bibliographic") or nil, and an ordered Array of
    # ControlFields and DataFields.
    #
    # Tag matchers select fields by tag: a String (equal), an Array of
    # matchers (any), a Range of Strings (its members) or a Regexp.
    # Indicator filters (ind1:, ind2:) are nil (any), a String or an Array of
    # Strings; with an indicator filter, control fields never match.
    class Record

      attr_accessor :leader, :type

      def initialize(leader: nil, fields: [], type: nil)
        @leader = leader
        @type = type
        @fields = fields.map { check_field(it) }
      end

      # Without arguments the record's own Array (changes affect the
      # record), otherwise a new Array of the matching fields, in record
      # order.
      def fields(*tags, ind1: nil, ind2: nil)
        return @fields if tags.empty? && ind1.nil? && ind2.nil?

        filter = Filter.new(tags, ind1, ind2)
        @fields.select { filter.matches?(it) }
      end

      # The first matching field, or nil.
      def field(*tags, ind1: nil, ind2: nil)
        filter = Filter.new(tags, ind1, ind2)
        @fields.find { filter.matches?(it) }
      end

      def [](tag) = field(tag)

      # The values of the matching fields, in record order: of data fields
      # those of these codes (all without codes), of control fields their
      # value when no codes are given.
      def values(tags, *codes, ind1: nil, ind2: nil)
        codes = codes.flatten
        fields(tags, ind1:, ind2:).flat_map do |field|
          if field.is_a?(DataField)
            field.values(*codes)
          else
            codes.empty? ? [field.value] : []
          end
        end
      end

      # The first of those values, or nil.
      def value(tags, *codes, ind1: nil, ind2: nil) = values(tags, *codes, ind1:, ind2:).first

      # Inserts the field before the first field whose tag sorts after its
      # tag (String#<=>), else at the end. Returns self.
      def add(field)
        check_field(field)
        index = @fields.index { (it.tag <=> field.tag) == 1 }
        index ? @fields.insert(index, field) : @fields.push(field)
        self
      end

      # Appends the field. Returns self.
      def append(field)
        @fields << check_field(field)
        self
      end

      # Removes the matching fields. Returns them. Without any tag or
      # indicator filter it raises, so an empty list cannot clear a record by
      # accident.
      def remove(*tags, ind1: nil, ind2: nil)
        if tags.empty? && ind1.nil? && ind2.nil?
          raise ArgumentError, "remove needs tags or indicator filters; fields.clear removes all fields"
        end

        filter = Filter.new(tags, ind1, ind2)
        removed = []
        @fields.reject! do |field|
          match = filter.matches?(field)
          removed << field if match
          match
        end
        removed
      end

      def ==(other)
        other.instance_of?(Record) && other.leader == leader && other.type == type && other.fields == fields
      end

      alias eql? ==

      def hash = [Record, leader, type, @fields].hash

      # MARC-in-JSON. "leader" only when the record has one; type is not
      # part of MARC-in-JSON.
      def to_h
        json = {}
        json["leader"] = leader if leader
        json["fields"] = @fields.map(&:to_h)
        json
      end

      # The record as MARCXML; namespace: false leaves out xmlns (a
      # <collection> declares it).
      def to_xml(namespace: true) = Serializer.record(self, namespace:)

      # One line per field in the mnemonic form of MarcEdit, the leader as
      # "=LDR".
      def to_s
        lines = leader ? ["=LDR  #{leader}"] : []
        (lines + @fields.map(&:to_s)).join("\n")
      end

      def inspect = "#<#{self.class.name}\n#{self}>"

      private

      def initialize_copy(source)
        super
        @leader = source.leader&.dup
        @type = source.type&.dup
        @fields = source.fields.map(&:dup)
      end

      def check_field(field)
        return field if field.is_a?(ControlField) || field.is_a?(DataField)

        raise ArgumentError, "a field must be a ControlField or a DataField, got #{field.inspect}"
      end

    end
  end
end
