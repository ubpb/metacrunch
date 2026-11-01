# frozen_string_literal: true

require "date"

module Metacrunch
  module Xlsx
    # Excel's serial dates as ISO 8601 Strings without zone. Excel counts
    # days from an epoch, the time of day as a fraction. Internal.
    module Dates

      SECONDS_PER_DAY = 86_400
      # Excel's 1900 system counts a 29 February 1900 that never was:
      # serials 1 to 59 are days since 1899-12-31, from 61 on since
      # 1899-12-30, and 60 names no date.
      EPOCH_1900 = Date.new(1899, 12, 30)
      LEAP_DAY = 60
      EPOCH_1904 = Date.new(1904, 1, 1)
      LAST_YEAR = 9999

      module_function

      # "2024-11-01", "2024-11-01T14:30:00" or "14:30:00" by kind (:date,
      # :date_time, :time); nil for a serial that names no real date (or
      # for a negative time), whose number the caller keeps. Seconds are
      # rounded.
      def iso(serial, kind, date1904:)
        return if serial.negative?

        days, seconds = (serial * SECONDS_PER_DAY).round.divmod(SECONDS_PER_DAY)
        return clock(seconds) if kind == :time

        date = date(serial, days, date1904)
        return unless date

        kind == :date ? date.iso8601 : "#{date.iso8601}T#{clock(seconds)}"
      end

      def date(serial, days, date1904)
        return in_range(EPOCH_1904 + days) if date1904
        return if serial < 1 || days == LEAP_DAY

        in_range(EPOCH_1900 + days + (days < LEAP_DAY ? 1 : 0))
      end

      def in_range(date) = date.year > LAST_YEAR ? nil : date

      def clock(seconds)
        format("%<hours>02d:%<minutes>02d:%<seconds>02d", hours: seconds / 3600, minutes: seconds / 60 % 60,
                                                          seconds: seconds % 60)
      end

    end
  end
end
