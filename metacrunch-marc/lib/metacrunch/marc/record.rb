# frozen_string_literal: true

module Metacrunch
  module Marc
    # A MARC record: a leader (a String or nil), the type attribute of a
    # MARCXML <record> (e.g. "Bibliographic") or nil, and an ordered, frozen
    # Array of ControlFields and DataFields.
    #
    # The fields change only through add, append, remove and clear, which
    # put a new Array in place, and the tags of fields are fixed. So queries
    # by tag use an index, built on the first query after a change.
    #
    # Tag matchers select fields by tag: a String (equal), an Array of
    # matchers (any), a Range of Strings (its members) or a Regexp.
    # Indicator filters (ind1:, ind2:) are nil (any), a String or an Array of
    # Strings; with an indicator filter, control fields never match.
    class Record

      attr_accessor :leader, :type

      # A Record from MARC-in-JSON as to_h returns it, e.g. a line of JSON
      # the caller parsed. Raises ParseError, with the path to the problem,
      # for other shapes and for values that break the rule of all formats
      # (see Values). normalize: nil or :nfc.
      def self.from_h(hash, normalize: nil)
        Marc.check_normalize(normalize)
        Json::Parser.new(normalize).record(hash)
      end

      def initialize(leader: nil, fields: [], type: nil)
        @leader = leader
        @type = type
        @fields = fields.map { check_field(it) }.freeze
        @index = nil
      end

      # Without arguments the record's frozen Array of fields, otherwise a
      # new Array of the matching fields, in record order.
      def fields(*tags, ind1: nil, ind2: nil)
        return @fields if tags.empty? && ind1.nil? && ind2.nil?

        found = []
        each_match(tags, ind1, ind2) { found << it }
        found
      end

      # The first matching field, or nil.
      def field(*tags, ind1: nil, ind2: nil)
        each_match(tags, ind1, ind2) { return it } # rubocop:disable Lint/UnreachableLoop -- ends at the first match
        nil
      end

      # field(tag) for one tag.
      def [](tag)
        return field(tag) unless tag.is_a?(String)

        entry = index[tag]
        entry.is_a?(Array) ? entry.first : entry
      end

      # The values of the matching fields, in record order: of data fields
      # those of these codes (all without codes), of control fields their
      # value when no codes are given.
      def values(tags, *codes, ind1: nil, ind2: nil)
        codes = Codes.check(codes)
        found = []
        each_tag(tags, ind1, ind2) do |field|
          if field.is_a?(DataField)
            field.each_subfield { |subfield| found << subfield.value if codes.empty? || codes.include?(subfield.code) }
          elsif codes.empty?
            found << field.value
          end
        end
        found
      end

      # The first of those values, or nil.
      def value(tags, *codes, ind1: nil, ind2: nil)
        codes = Codes.check(codes)
        each_tag(tags, ind1, ind2) do |field|
          if field.is_a?(DataField)
            field.each_subfield { |subfield| return subfield.value if codes.empty? || codes.include?(subfield.code) }
          elsif codes.empty?
            return field.value
          end
        end
        nil
      end

      # Inserts the field before the first field whose tag sorts after its
      # tag (String#<=>), else at the end. Returns self.
      def add(field)
        check_field(field)
        index = @fields.index { (it.tag <=> field.tag) == 1 }
        update(index ? @fields.dup.insert(index, field) : [*@fields, field])
        self
      end

      # Appends the field. Returns self.
      def append(field)
        update([*@fields, check_field(field)])
        self
      end

      # Removes the fields that match the tags and indicator filters and,
      # with a block, for which the block is true. Returns them. Without any
      # tag, indicator filter or block it raises, so an empty list cannot
      # clear a record by accident.
      def remove(*tags, ind1: nil, ind2: nil)
        filtered = !(tags.empty? && ind1.nil? && ind2.nil?)
        unless filtered || block_given?
          raise ArgumentError, "remove needs tags, indicator filters or a block; clear removes all fields"
        end

        filter = filtered ? Filter.new(tags, ind1, ind2) : nil
        removed, kept = @fields.partition { (filter.nil? || filter.matches?(it)) && (!block_given? || yield(it)) }
        update(kept) unless removed.empty?
        removed
      end

      # Removes all fields. Returns them.
      def clear
        removed = @fields
        update([])
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
      def to_xml(namespace: true) = Xml::Serializer.record(self, namespace:)

      # The record as ISO 2709, a String in UTF-8. Raises SerializeError for
      # what ISO 2709 cannot hold: tags other than 3 ASCII characters,
      # indicators and codes other than 1, data fields without subfields,
      # a leader other than 24 ASCII characters, and fields over 9,999 or
      # records over 99,999 bytes; oversize: :allow writes those numbers as
      # all nines instead, which tolerant readers read.
      def to_iso2709(oversize: :error) = Iso2709::Serializer.record(self, oversize:)

      # One line per field in the mnemonic form of MarcEdit, the leader as
      # "=LDR".
      def to_s
        lines = leader ? ["=LDR  #{leader}"] : []
        (lines + @fields.map(&:to_s)).join("\n")
      end

      def inspect = "#<#{self.class.name}\n#{self}>"

      # Marshal leaves the index out; it is built again when needed.
      def marshal_dump = [@leader, @type, @fields]

      def marshal_load(data)
        @leader, @type, @fields = data
        @index = nil
      end

      private

      def initialize_copy(source)
        super
        @leader = source.leader&.dup
        @type = source.type&.dup
        @fields = source.fields.map(&:dup).freeze
        @index = nil
      end

      def update(fields)
        @fields = fields.freeze
        @index = nil
      end

      # Tag => the field with that tag, or an Array of the fields in record
      # order if the tag repeats. Most tags do not repeat, so most entries
      # need no Array of their own.
      def index = @index ||= build_index

      def build_index
        index = {}
        @fields.each do |field|
          entry = index[field.tag]
          if entry.nil?
            index[field.tag] = field
          elsif entry.is_a?(Array)
            entry << field
          else
            index[field.tag] = [entry, field]
          end
        end
        index
      end

      # Yields the fields that match tags, an Array of tag matchers, in
      # record order.
      def each_match(tags, ind1, ind2, &)
        return each_tag(tags.first, ind1, ind2, &) if tags.size == 1

        filter = Filter.new(tags, ind1, ind2)
        @fields.each { yield it if filter.matches?(it) }
      end

      # Yields the fields that match one tag matcher, in record order. A
      # String tag, the most common query, goes through the index and checks
      # indicators only for its fields, without allocating; other matchers
      # scan the fields.
      def each_tag(tag, ind1, ind2, &)
        unless tag.is_a?(String)
          filter = Filter.new([tag], ind1, ind2)
          return @fields.each { yield it if filter.matches?(it) }
        end

        Filter.indicator(ind1, "ind1")
        Filter.indicator(ind2, "ind2")
        entry = index[tag]
        if !entry.is_a?(Array)
          yield entry if entry && Filter.indicators?(entry, ind1, ind2)
        elsif ind1.nil? && ind2.nil?
          entry.each(&)
        else
          entry.each { yield it if Filter.indicators?(it, ind1, ind2) }
        end
      end

      def check_field(field)
        return field if field.is_a?(ControlField) || field.is_a?(DataField)

        raise ArgumentError, "a field must be a ControlField or a DataField, got #{field.inspect}"
      end

    end
  end
end
