# frozen_string_literal: true

# Builds ISO 2709 records byte by byte, so a test shows the defect it reads:
# lengths and starts are right, and numbers too large for their positions
# are nines, as the serializer writes them.
module Iso

  LEADER = "00000nam a2200000 c 4500"

  # A binary record from [tag, body] pairs; a body is the field without its
  # terminator, e.g. "10\x1FaTitle".
  def raw(*fields, leader: LEADER)
    directory = String.new(encoding: Encoding::BINARY)
    data = String.new(encoding: Encoding::BINARY)
    fields.each do |tag, body|
      body = "#{body}\x1E".b
      directory << tag.b << number(body.bytesize, 4) << number(data.bytesize, 5)
      data << body
    end
    record = leader.b << directory << "\x1E" << data << "\x1D"
    record[12, 5] = number(24 + directory.bytesize + 1, 5)
    record[0, 5] = number(record.bytesize, 5)
    record
  end

  # A record with a control field 001 and a 245.
  def book(id = "1") = raw(["001", id], ["245", "10\x1FaTitle\x1FbSub"])

  def number(value, digits) = value.to_s.size > digits ? "9" * digits : value.to_s.rjust(digits, "0")

end
