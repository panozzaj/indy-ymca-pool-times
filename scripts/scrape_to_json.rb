#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrapes all YMCA branch pool schedules from Y360 data and outputs JSON for the static website.
# Run with: ruby scripts/scrape_to_json.rb
# Output: data/schedule.json

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "nokogiri"
end

require "net/http"
require "uri"
require "optparse"
require "time"
require "json"
require "date"

# Branch definitions: key => { source_name (from indymca.org), display_name (for our site) }
BRANCHES = {
  "westfield" => {
    source_name: "Ascension St. Vincent YMCA in Westfield",
    display_name: "Ascension St. Vincent in Westfield"
  },
  "avondale" => {
    source_name: "Avondale Meadows YMCA",
    display_name: "Avondale Meadows"
  },
  "baxter" => {
    source_name: "Baxter YMCA",
    display_name: "Baxter"
  },
  "benjamin" => {
    source_name: "Benjamin Harrison YMCA",
    display_name: "Benjamin Harrison"
  },
  "fishers" => {
    source_name: "Fishers YMCA",
    display_name: "Fishers"
  },
  "hendricks" => {
    source_name: "Hendricks Regional Health YMCA",
    display_name: "Hendricks Regional Health"
  },
  "irsay" => {
    source_name: "Irsay Family YMCA at CityWay",
    display_name: "Irsay"
  },
  "jordan" => {
    source_name: "Jordan YMCA",
    display_name: "Jordan"
  },
  "orthoindy" => {
    source_name: "OrthoIndy Foundation YMCA",
    display_name: "OrthoIndy Foundation"
  },
  "ransburg" => {
    source_name: "Ransburg YMCA",
    display_name: "Ransburg"
  },
  "witham" => {
    source_name: "Witham Family YMCA",
    display_name: "Witham"
  }
}.freeze

# Reverse lookup: source name => our key
SOURCE_NAME_TO_KEY = BRANCHES.transform_values { |v| v[:source_name] }.invert.freeze

# Pool schedule types that count as lap swim
LAP_SWIM_TYPES = ["Lap Lane Swim", "Open Swim"].freeze

options = { dry_run: false, output: "data/schedule.json" }

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("--dry-run", "Preview without writing (default is to write)") do
    options[:dry_run] = true
  end

  opts.on("-o", "--output FILE", "Output file path (default: data/schedule.json)") do |v|
    options[:output] = v
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

# Convert UTC ISO timestamp to Eastern time, handling DST correctly
def utc_to_eastern(iso_str)
  # Parse as UTC, convert to Eastern using TZ
  utc_time = Time.parse(iso_str)
  ENV["TZ"] = "America/Indiana/Indianapolis"
  eastern_time = utc_time.localtime
  ENV["TZ"] = nil
  eastern_time
end

# Convert UTC ISO timestamp to Eastern time formatted string
def utc_to_eastern_time(iso_str)
  utc_to_eastern(iso_str).strftime("%I:%M %p").sub(/^0/, "")
end

# Convert UTC ISO timestamp to Eastern date (ISO format)
def utc_to_eastern_date(iso_str)
  utc_to_eastern(iso_str).strftime("%Y-%m-%d")
end

# Fetch Y360 data from indymca.org
def fetch_y360_data
  url = "https://indymca.org/fishers/"
  html = `curl -sL '#{url}'`

  # Extract y360-data JSON from HTML
  match = html.match(/<script type="application\/json" class="y360-data">(.+?)<\/script>/m)
  return nil unless match

  JSON.parse(match[1])
end

# Extract lap swim sessions from Y360 data
def extract_lap_swim_sessions(y360_data)
  sessions_by_branch = Hash.new { |h, k| h[k] = [] }

  y360_data["apiSchedules"].each do |_date, day_data|
    day_data["items"].each do |item|
      branch_name = item["branch_name"]
      schedule_name = item["schedule_name"]
      title = item["title"]

      next unless branch_name
      next unless schedule_name == "Pools Schedules"
      next unless LAP_SWIM_TYPES.include?(title)

      branch_key = SOURCE_NAME_TO_KEY[branch_name]
      next unless branch_key

      # Convert UTC to Eastern
      start_date = utc_to_eastern_date(item["start_at"])
      start_time = utc_to_eastern_time(item["start_at"])
      end_time = utc_to_eastern_time(item["end_at"])

      sessions_by_branch[branch_key] << {
        day: start_date,
        start_time: start_time,
        end_time: end_time,
        studio: item["studio_name"] || ""
      }
    end
  end

  sessions_by_branch
end

# Merge overlapping or adjacent sessions
def merge_sessions(sessions)
  return [] if sessions.empty?

  # Sort by start time
  sorted = sessions.sort_by { |s| Time.parse(s[:start_time]) }

  merged = [sorted.first.dup]
  sorted[1..].each do |session|
    prev = merged.last
    prev_end = Time.parse(prev[:end_time])
    curr_start = Time.parse(session[:start_time])
    curr_end = Time.parse(session[:end_time])

    # If current session starts before or at previous end, merge them
    if curr_start <= prev_end
      # Extend end time if current ends later
      prev[:end_time] = session[:end_time] if curr_end > prev_end
    else
      merged << session.dup
    end
  end
  merged
end

# Build branch schedule data
def build_branch_data(branch_key, sessions)
  # Sort by day and start time
  sessions.sort_by! { |s| [s[:day], Time.parse(s[:start_time])] }

  days = sessions.map { |s| s[:day] }.uniq.sort

  schedule = sessions.group_by { |s| s[:day] }.transform_values do |day_sessions|
    merge_sessions(day_sessions).map do |s|
      {
        start_time: s[:start_time],
        end_time: s[:end_time],
        lanes: "" # Y360 doesn't provide lane counts
      }
    end
  end

  {
    key: branch_key,
    name: BRANCHES[branch_key][:display_name],
    days: days,
    schedule: schedule
  }
end

# Main execution
puts "Fetching Y360 schedule data from indymca.org..."
y360_data = fetch_y360_data

if y360_data.nil?
  puts "ERROR: Failed to fetch Y360 data"
  exit 1
end

dates_available = y360_data["apiSchedules"].keys.sort
puts "  Found data for #{dates_available.length} days: #{dates_available.first} to #{dates_available.last}"

sessions_by_branch = extract_lap_swim_sessions(y360_data)
puts "  Found lap swim sessions for #{sessions_by_branch.keys.length} branches"

branches_data = []
all_days = []

BRANCHES.keys.each do |key|
  sessions = sessions_by_branch[key] || []
  print "  #{BRANCHES[key][:display_name]}..."

  if sessions.empty?
    puts " 0 sessions (no pool data)"
    next
  end

  data = build_branch_data(key, sessions)
  branches_data << data
  all_days.concat(data[:days])

  total_sessions = data[:schedule].values.flatten.size
  puts " #{total_sessions} sessions"
end

# Sort days chronologically
all_days = all_days.uniq.sort

output = {
  generated_at: Time.now.utc.iso8601,
  days: all_days,
  branches: branches_data
}

json = JSON.pretty_generate(output)

if options[:dry_run]
  puts "\n[DRY RUN] Would write #{json.bytesize} bytes to #{options[:output]}"
  puts "\nPreview (first 2000 chars):"
  puts json[0, 2000]
else
  File.write(options[:output], json)
  puts "\nWrote #{json.bytesize} bytes to #{options[:output]}"
end
