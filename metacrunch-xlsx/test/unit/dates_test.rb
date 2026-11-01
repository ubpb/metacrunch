# frozen_string_literal: true

require "test_helper"

class DatesTest < Minitest::Test

  Dates = Metacrunch::Xlsx::Dates

  IN_1900 = {
    [45_597, :date] => "2024-11-01", [45_597.6041666667, :date_time] => "2024-11-01T14:30:00",
    [0.6041666667, :time] => "14:30:00", [45_597.6041666667, :time] => "14:30:00", [0, :time] => "00:00:00",
    [1, :date] => "1900-01-01", [59, :date] => "1900-02-28", [60, :date] => nil, [61, :date] => "1900-03-01",
    [0, :date] => nil, [0.5, :date_time] => nil, [-1, :date] => nil, [-0.5, :time] => nil,
    [2_958_465, :date] => "9999-12-31", [2_958_466, :date] => nil, [0.99999999, :date_time] => nil,
    [45_597.99999999, :date_time] => "2024-11-02T00:00:00", [0.99999999, :time] => "00:00:00"
  }.freeze

  IN_1904 = {[0, :date] => "1904-01-01", [-1, :date] => nil, [45_597, :date] => "2028-11-02",
             [1.5, :date_time] => "1904-01-02T12:00:00", [60, :date] => "1904-03-01"}.freeze

  def test_dates_in_the_1900_system
    IN_1900.each { |(serial, kind), iso| assert_equal_or_nil iso, Dates.iso(serial, kind, date1904: false), serial }
  end

  def test_dates_in_the_1904_system
    IN_1904.each { |(serial, kind), iso| assert_equal_or_nil iso, Dates.iso(serial, kind, date1904: true), serial }
  end

  def test_seconds_are_rounded
    serial = 45_597 + (((14 * 3600) + (30 * 60) + 29.6) / 86_400)

    assert_equal "2024-11-01T14:30:30", Dates.iso(serial, :date_time, date1904: false)
  end

  private

  def assert_equal_or_nil(expected, actual, message)
    expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
  end

end
