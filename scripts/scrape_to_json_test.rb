#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "time"

# Load constants and methods from the main script (without executing main logic)
# We duplicate the relevant code here for isolated testing

BRANCHES = {
  "westfield" => {
    source_name: "Ascension St. Vincent YMCA in Westfield",
    display_name: "Ascension St. Vincent in Westfield"
  },
  "fishers" => {
    source_name: "Fishers YMCA",
    display_name: "Fishers"
  },
  "irsay" => {
    source_name: "Irsay Family YMCA at CityWay",
    display_name: "Irsay"
  }
}.freeze

SOURCE_NAME_TO_KEY = BRANCHES.transform_values { |v| v[:source_name] }.invert.freeze

LAP_SWIM_TYPES = ["Lap Lane Swim", "Open Swim"].freeze

def utc_to_eastern(iso_str)
  utc_time = Time.parse(iso_str)
  ENV["TZ"] = "America/Indiana/Indianapolis"
  eastern_time = utc_time.localtime
  ENV["TZ"] = nil
  eastern_time
end

def utc_to_eastern_time(iso_str)
  utc_to_eastern(iso_str).strftime("%I:%M %p").sub(/^0/, "")
end

def utc_to_eastern_date(iso_str)
  utc_to_eastern(iso_str).strftime("%Y-%m-%d")
end

def merge_sessions(sessions)
  return [] if sessions.empty?

  sorted = sessions.sort_by { |s| Time.parse(s[:start_time]) }

  merged = [sorted.first.dup]
  sorted[1..].each do |session|
    prev = merged.last
    prev_end = Time.parse(prev[:end_time])
    curr_start = Time.parse(session[:start_time])
    curr_end = Time.parse(session[:end_time])

    if curr_start <= prev_end
      prev[:end_time] = session[:end_time] if curr_end > prev_end
    else
      merged << session.dup
    end
  end
  merged
end

class BranchMappingTest < Minitest::Test
  def test_source_name_to_key_maps_exact_names
    assert_equal "westfield", SOURCE_NAME_TO_KEY["Ascension St. Vincent YMCA in Westfield"]
    assert_equal "fishers", SOURCE_NAME_TO_KEY["Fishers YMCA"]
    assert_equal "irsay", SOURCE_NAME_TO_KEY["Irsay Family YMCA at CityWay"]
  end

  def test_source_name_to_key_returns_nil_for_unknown
    assert_nil SOURCE_NAME_TO_KEY["Unknown YMCA"]
    assert_nil SOURCE_NAME_TO_KEY["Fishers"] # partial match shouldn't work
  end

  def test_display_name_lookup
    assert_equal "Ascension St. Vincent in Westfield", BRANCHES["westfield"][:display_name]
    assert_equal "Fishers", BRANCHES["fishers"][:display_name]
    assert_equal "Irsay", BRANCHES["irsay"][:display_name]
  end
end

class LapSwimTypesTest < Minitest::Test
  def test_lap_lane_swim_included
    assert_includes LAP_SWIM_TYPES, "Lap Lane Swim"
  end

  def test_open_swim_included
    assert_includes LAP_SWIM_TYPES, "Open Swim"
  end

  def test_other_types_not_included
    refute_includes LAP_SWIM_TYPES, "Family Swim"
    refute_includes LAP_SWIM_TYPES, "Water Aerobics"
  end
end

class TimeConversionTest < Minitest::Test
  # EST (standard time) - UTC-5
  def test_utc_to_eastern_time_est
    # 3:00 PM UTC = 10:00 AM EST
    assert_equal "10:00 AM", utc_to_eastern_time("2026-01-15T15:00:00.000Z")
  end

  def test_utc_to_eastern_date_est
    # 3:00 AM UTC on Jan 15 = 10:00 PM EST on Jan 14
    assert_equal "2026-01-14", utc_to_eastern_date("2026-01-15T03:00:00.000Z")
  end

  def test_utc_to_eastern_time_formats_without_leading_zero
    # 2:30 PM UTC = 9:30 AM EST
    assert_equal "9:30 AM", utc_to_eastern_time("2026-01-15T14:30:00.000Z")
  end

  # EDT (daylight saving) - UTC-4
  def test_utc_to_eastern_time_edt
    # 3:00 PM UTC = 11:00 AM EDT (during DST)
    assert_equal "11:00 AM", utc_to_eastern_time("2026-06-15T15:00:00.000Z")
  end

  def test_utc_to_eastern_date_edt
    # 3:00 AM UTC on June 15 = 11:00 PM EDT on June 14
    assert_equal "2026-06-14", utc_to_eastern_date("2026-06-15T03:00:00.000Z")
  end

  # Edge case: midnight boundary
  def test_utc_to_eastern_crosses_midnight
    # 4:00 AM UTC = 11:00 PM EST previous day
    assert_equal "2026-01-14", utc_to_eastern_date("2026-01-15T04:00:00.000Z")
    assert_equal "11:00 PM", utc_to_eastern_time("2026-01-15T04:00:00.000Z")
  end
end

class MergeSessionsTest < Minitest::Test
  def test_empty_sessions
    assert_equal [], merge_sessions([])
  end

  def test_single_session
    sessions = [{ start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" }]
    result = merge_sessions(sessions)
    assert_equal 1, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "10:00 AM", result[0][:end_time]
  end

  def test_non_overlapping_sessions
    sessions = [
      { start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" },
      { start_time: "11:00 AM", end_time: "12:00 PM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 2, result.length
  end

  def test_adjacent_sessions_not_merged
    # Adjacent but not overlapping - should stay separate
    sessions = [
      { start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" },
      { start_time: "10:01 AM", end_time: "11:00 AM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 2, result.length
  end

  def test_touching_sessions_merged
    # End time equals start time - should merge
    sessions = [
      { start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" },
      { start_time: "10:00 AM", end_time: "11:00 AM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 1, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "11:00 AM", result[0][:end_time]
  end

  def test_overlapping_sessions_merged
    sessions = [
      { start_time: "9:00 AM", end_time: "11:00 AM", studio: "Pool" },
      { start_time: "10:00 AM", end_time: "12:00 PM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 1, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "12:00 PM", result[0][:end_time]
  end

  def test_contained_session_merged
    # Second session entirely within first
    sessions = [
      { start_time: "9:00 AM", end_time: "1:00 PM", studio: "Pool" },
      { start_time: "10:00 AM", end_time: "11:00 AM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 1, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "1:00 PM", result[0][:end_time]
  end

  def test_unsorted_sessions_handled
    # Sessions not in order - should still merge correctly
    sessions = [
      { start_time: "11:00 AM", end_time: "12:00 PM", studio: "Pool" },
      { start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" },
      { start_time: "10:00 AM", end_time: "11:00 AM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 1, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "12:00 PM", result[0][:end_time]
  end

  def test_multiple_groups_merged_separately
    sessions = [
      { start_time: "9:00 AM", end_time: "10:00 AM", studio: "Pool" },
      { start_time: "10:00 AM", end_time: "11:00 AM", studio: "Pool" },
      { start_time: "2:00 PM", end_time: "3:00 PM", studio: "Pool" },
      { start_time: "3:00 PM", end_time: "4:00 PM", studio: "Pool" }
    ]
    result = merge_sessions(sessions)
    assert_equal 2, result.length
    assert_equal "9:00 AM", result[0][:start_time]
    assert_equal "11:00 AM", result[0][:end_time]
    assert_equal "2:00 PM", result[1][:start_time]
    assert_equal "4:00 PM", result[1][:end_time]
  end
end
