#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

# Extract the method to test
def standardize_lanes(lanes_str)
  return lanes_str if lanes_str.nil? || lanes_str.empty?

  # Extract number or range (e.g., "4-6", "7", "2-3")
  if lanes_str =~ /(\d+(?:-\d+)?)/
    count = Regexp.last_match(1)
    # Use singular for "1", plural otherwise
    suffix = count == "1" ? "lane" : "lanes"
    "#{count} #{suffix}"
  else
    # No number found, return original (e.g., "Lap Lane Swim")
    lanes_str
  end
end

class StandardizeLanesTest < Minitest::Test
  # Single lane - should be singular
  def test_1_lane_lowercase
    assert_equal "1 lane", standardize_lanes("1 lane")
  end

  def test_1_lane_uppercase
    assert_equal "1 lane", standardize_lanes("1 Lane")
  end

  def test_1_lanes_incorrect_plural
    assert_equal "1 lane", standardize_lanes("1 Lanes")
  end

  def test_1_open_lane
    assert_equal "1 lane", standardize_lanes("1 open lane")
  end

  def test_only_1_lane_open
    assert_equal "1 lane", standardize_lanes("Only 1 Lane open")
  end

  # Multiple lanes - should be plural
  def test_10_lanes_uppercase
    assert_equal "10 lanes", standardize_lanes("10 Lanes")
  end

  def test_10_lane_lowercase_singular
    assert_equal "10 lanes", standardize_lanes("10 lane")
  end

  def test_2_lanes
    assert_equal "2 lanes", standardize_lanes("2 Lanes")
  end

  def test_7_open_lanes
    assert_equal "7 lanes", standardize_lanes("7 open lanes")
  end

  def test_only_3_lanes_open
    assert_equal "3 lanes", standardize_lanes("Only 3 Lanes open")
  end

  def test_3_lanes_only
    assert_equal "3 lanes", standardize_lanes("3 Lanes only")
  end

  # Ranges - should be plural
  def test_4_6_open_lanes
    assert_equal "4-6 lanes", standardize_lanes("4-6 open lanes")
  end

  def test_2_3_open_lanes
    assert_equal "2-3 lanes", standardize_lanes("2-3 open lanes")
  end

  def test_6_7_lanes_open
    assert_equal "6-7 lanes", standardize_lanes("6-7 lanes open")
  end

  # Complex cases - extracts first number
  def test_swim_lanes_water_walking
    assert_equal "3 lanes", standardize_lanes("3 Swim Lanes- 1 Water Walking Lane")
  end

  def test_swim_team_practice
    assert_equal "3 lanes", standardize_lanes("Swim Team Practice - Lanes 3 and 4")
  end

  # No number - return original
  def test_lap_lane_swim
    assert_equal "Lap Lane Swim", standardize_lanes("Lap Lane Swim")
  end

  # Edge cases
  def test_nil
    assert_nil standardize_lanes(nil)
  end

  def test_empty_string
    assert_equal "", standardize_lanes("")
  end
end
