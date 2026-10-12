# frozen_string_literal: true

module Metacrunch
  module Marcxml
    # A MARC record: a leader (a String or nil), the type attribute of
    # <record> (e.g. "Bibliographic") or nil, and an ordered, frozen Array of
    # ControlFields and DataFields.
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

      ANY_TAG = [].freeze

      attr_accessor :leader, :type

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

      def [](tag) = field(tag)

      # The values of the matching fields, in record order: of data fields
      # those of these codes (all without codes), of control fields their
      # value when no codes are given.
      def values(tags, *codes, ind1: nil, ind2: nil)
        codes = Codes.check(codes)
        found = []
        each_match([tags], ind1, ind2) do |field|
          if field.is_a?(DataField)
            field.subfields.each { |subfield| found << subfield.value if codes.empty? || codes.include?(subfield.code) }
          elsif codes.empty?
            found << field.value
          end
        end
        found
      end

      # The first of those values, or nil.
      def value(tags, *codes, ind1: nil, ind2: nil)
        codes = Codes.check(codes)
        each_match([tags], ind1, ind2) do |field|
          if field.is_a?(DataField)
            field.subfields.each { |subfield| return subfield.value if codes.empty? || codes.include?(subfield.code) }
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
      def to_xml(namespace: true) = Serializer.record(self, namespace:)

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

      # Tag => fields with that tag, in record order.
      def index = @index ||= @fields.group_by(&:tag)

      # Yields the matching fields in record order. One String tag, the most
      # common query, goes through the index, and indicators are checked only
      # for its fields; other tag matchers scan the fields.
      def each_match(tags, ind1, ind2, &)
        tag = tags.first
        if tags.size != 1 || !tag.is_a?(String)
          filter = Filter.new(tags, ind1, ind2)
          @fields.each { yield it if filter.matches?(it) }
        elsif ind1.nil? && ind2.nil?
          index[tag]&.each(&)
        else
          filter = Filter.new(ANY_TAG, ind1, ind2)
          index[tag]&.each { yield it if filter.matches?(it) }
        end
      end

      def check_field(field)
        return field if field.is_a?(ControlField) || field.is_a?(DataField)

        raise ArgumentError, "a field must be a ControlField or a DataField, got #{field.inspect}"
      end

    end
  end
end
