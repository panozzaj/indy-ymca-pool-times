#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "time"

require_relative "scrape_to_json"

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

class CleanDescriptionTest < Minitest::Test
  def test_blank
    assert_equal "", clean_description(nil)
    assert_equal "", clean_description("  \n ")
  end

  def test_decodes_nbsp_and_collapses_whitespace
    assert_equal "9 Lanes", clean_description("9 Lanes&nbsp;")
    assert_equal "4 Lanes Safety Break from 6:30am to 7:00", clean_description("4 Lanes\nSafety Break from 6:30am to 7:00")
    assert_equal "(3) Lanes available", clean_description("(3)&nbsp; Lanes available")
  end

  def test_strips_tags_and_decodes_entities
    assert_equal "Lanes & slide", clean_description("<p>Lanes &amp; slide</p>")
  end

  def test_drops_punctuation_only_text
    assert_equal "", clean_description("&nbsp;)")
  end

  def test_removes_decorative_runs
    assert_equal "COMPETITION POOL ONLY LIMITED LANES AVAILABLE IN DEEP END",
                 clean_description("COMPETITION&nbsp; POOL ONLY&nbsp; &nbsp;-------&nbsp; &nbsp;LIMITED LANES AVAILABLE IN DEEP END")
    assert_equal "Deep end only -- 3 lanes--", clean_description("********&nbsp;Deep end only&nbsp; -- 3 lanes--")
  end
end

class ExtractPoolEventsTest < Minitest::Test
  def item(title:, studio: "Lap Pool", branch: "Fishers YMCA", schedule: "Pools Schedules", description: "")
    {
      "branch_name" => branch, "schedule_name" => schedule, "title" => title, "studio_name" => studio,
      "description" => description,
      "start_at" => "2026-01-15T14:00:00.000Z", "end_at" => "2026-01-15T15:00:00.000Z"
    }
  end

  def test_splits_lap_swim_from_other_pool_events
    data = { "apiSchedules" => { "2026-01-15" => { "items" => [
      item(title: "Lap Lane Swim", description: "4 Lanes"),
      item(title: "Shallow Water Fitness"),
      item(title: "Zumba", schedule: "Group Exercise"),
      item(title: "Lap Lane Swim", branch: "Unknown YMCA")
    ] } } }

    result = extract_pool_events(data)

    assert_equal ["fishers"], result.keys
    assert_equal 1, result["fishers"][:lap].size
    assert_equal "4 Lanes", result["fishers"][:lap].first[:description]
    assert_equal "9:00 AM", result["fishers"][:lap].first[:start_time]
    assert_equal ["Shallow Water Fitness"], result["fishers"][:other].map { |e| e[:title] }
  end
end

class BuildBranchDataTest < Minitest::Test
  DAY = "2026-01-15"

  def lap(start_time, end_time, description: "", studio: "Lap Pool")
    { day: DAY, start_time: start_time, end_time: end_time, studio: studio, title: "Lap Lane Swim", description: description }
  end

  def event(title, start_time, end_time, studio: "Lap Pool", day: DAY)
    { day: day, start_time: start_time, end_time: end_time, studio: studio, title: title, description: "" }
  end

  def window(laps, others = [])
    build_branch_data("fishers", laps, others)[:schedule][DAY]
  end

  def test_single_note_covering_window
    result = window([lap("6:00 AM", "9:00 AM", description: "4 Lanes&nbsp;")])
    assert_equal [{ start_time: "6:00 AM", end_time: "9:00 AM", text: "4 Lanes" }], result.first[:notes]
    assert_equal ["Lap Pool"], result.first[:studios]
  end

  def test_notes_kept_per_part_of_merged_window
    result = window([
      lap("6:00 AM", "8:00 AM", description: "4 Lanes"),
      lap("8:00 AM", "10:00 AM", description: "4 Lanes"),
      lap("10:00 AM", "12:00 PM", description: "1 Lane"),
      lap("12:00 PM", "1:00 PM")
    ])
    assert_equal 1, result.size
    assert_equal [
      { start_time: "6:00 AM", end_time: "10:00 AM", text: "4 Lanes" },
      { start_time: "10:00 AM", end_time: "12:00 PM", text: "1 Lane" }
    ], result.first[:notes]
  end

  def test_overlapping_classes_in_same_pool
    result = window(
      [lap("6:00 AM", "12:00 PM")],
      [
        event("Shallow Water Fitness", "9:00 AM", "10:00 AM"),
        event("Deep Water Fitness", "11:30 AM", "12:30 PM"),
        event("Aqua Zumba", "9:00 AM", "10:00 AM", studio: "Therapy Pool"), # different pool
        event("Arthritis", "12:00 PM", "1:00 PM"), # starts when lap swim ends
        event("Aqua Mobility", "9:00 AM", "10:00 AM", day: "2026-01-16") # different day
      ]
    )
    assert_equal [
      { title: "Shallow Water Fitness", start_time: "9:00 AM", end_time: "10:00 AM", studio: "Lap Pool" },
      { title: "Deep Water Fitness", start_time: "11:30 AM", end_time: "12:30 PM", studio: "Lap Pool" }
    ], result.first[:classes]
  end

  def test_class_must_overlap_a_session_in_its_own_pool
    # Lap Pool 6-9 and Program Pool 9-12 merge into one 6-12 window
    result = window(
      [lap("6:00 AM", "9:00 AM"), lap("9:00 AM", "12:00 PM", studio: "Program Pool")],
      [
        event("Arthritis", "7:00 AM", "8:00 AM", studio: "Program Pool"), # Program Pool not open for laps yet
        event("Aqua Challenge", "10:00 AM", "11:00 AM", studio: "Program Pool"),
        event("Deep Water Fitness", "10:00 AM", "11:00 AM") # Lap Pool session already over
      ]
    )
    assert_equal 1, result.size
    assert_equal ["Lap Pool", "Program Pool"], result.first[:studios]
    assert_equal ["Aqua Challenge"], result.first[:classes].map { |c| c[:title] }
  end

  def test_classes_sorted_and_deduped
    result = window(
      [lap("6:00 AM", "12:00 PM")],
      [
        event("Deep Water Fitness", "11:00 AM", "12:00 PM"),
        event("Shallow Water Fitness", "9:00 AM", "10:00 AM"),
        event("Shallow Water Fitness", "9:00 AM", "10:00 AM")
      ]
    )
    assert_equal ["Shallow Water Fitness", "Deep Water Fitness"], result.first[:classes].map { |c| c[:title] }
  end

  def test_window_without_classes_or_notes
    result = window([lap("6:00 AM", "7:00 AM")])
    assert_equal [], result.first[:classes]
    assert_equal [], result.first[:notes]
  end
end
