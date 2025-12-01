#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrapes all YMCA branch pool schedules and outputs JSON for the static website.
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

WEEKS_TO_FETCH = 3

BRANCHES = {
  "westfield" => { id: 40, name: "Ascension St. Vincent in Westfield" },
  "avondale" => { id: 22, name: "Avondale Meadows" },
  "baxter" => { id: 30, name: "Baxter" },
  "benjamin" => { id: 20, name: "Benjamin Harrison" },
  "fishers" => { id: 16, name: "Fishers" },
  "hendricks" => { id: 26, name: "Hendricks Regional Health" },
  "irsay" => { id: 24, name: "Irsay" },
  "jordan" => { id: 34, name: "Jordan" },
  "orthoindy" => { id: 36, name: "OrthoIndy Foundation" },
  "ransburg" => { id: 32, name: "Ransburg" },
  "witham" => { id: 18, name: "Witham" }
}.freeze

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

def parse_duration_minutes(duration_str)
  return 60 if duration_str.nil? || duration_str.empty?

  if duration_str =~ /([\d.]+)\s*hr/
    (Regexp.last_match(1).to_f * 60).to_i
  elsif duration_str =~ /(\d+)\s*min/
    Regexp.last_match(1).to_i
  else
    60
  end
end

def format_time(time_str)
  time_str.gsub(/\s+/, " ").strip
end

def normalize_time(time_str)
  Time.parse(time_str).strftime("%I:%M %p").sub(/^0/, "")
end

def calculate_end_time(start_time_str, duration_str)
  start = Time.parse(start_time_str)
  minutes = parse_duration_minutes(duration_str)
  end_time = start + (minutes * 60)
  end_time.strftime("%I:%M %p").sub(/^0/, "")
end

# Get the Sunday of the current week
def current_week_sunday
  today = Date.today
  today - today.wday
end

# Generate Sunday dates for weeks to fetch
def week_sundays
  base = current_week_sunday
  WEEKS_TO_FETCH.times.map { |i| base + (i * 7) }
end

def fetch_week_schedule(branch_id, week_date)
  params = {
    BranchID: branch_id,
    search: "pool time",
    date: week_date.strftime("%Y-%m-%d")
  }
  url = "https://indy.recliquecore.com/classes/printer_friendly/?#{URI.encode_www_form(params)}"
  html = `curl -s '#{url}'`
  return { days: [], sessions: [] } if html.empty?

  doc = Nokogiri::HTML(html)

  date_headers = doc.css("table#week_classes thead th").map(&:text).map(&:strip).reject(&:empty?)
  date_headers.reject! { |h| h.downcase.include?("time") }

  sessions = []
  doc.css("tbody#non-condensed tr").each do |row|
    cells = row.css("td")
    next if cells.empty?

    cells.each_with_index do |cell, day_index|
      next if day_index >= date_headers.length

      cell.css("div.item").each do |item|
        time_el = item.at_css("span.c-time")
        next unless time_el

        raw_time = format_time(time_el.text)
        start_time = normalize_time(raw_time)
        category = item.at_css("div.category")&.text&.strip || ""
        label = item.at_css("div.label")&.text&.strip || ""
        name = [category, label].reject(&:empty?).join(" - ")
        name = "Unknown" if name.empty?

        duration_str = item.at_css("span.duration")&.text&.strip&.gsub(/[()]/, "") || ""
        end_time = calculate_end_time(raw_time, duration_str)

        sessions << {
          day: date_headers[day_index],
          start_time: start_time,
          end_time: end_time,
          name: name
        }
      end
    end
  end

  sessions.select! { |s| s[:name].start_with?("Lap Lane Swim") && s[:day] =~ /\d+\/\d+/ }
  sessions.each { |s| s[:lanes] = s[:name].sub("Lap Lane Swim - ", "") }

  { days: date_headers, sessions: sessions }
end

def fetch_branch_schedule(branch_id, branch_key, branch_name)
  all_days = []
  all_sessions = []

  week_sundays.each do |sunday|
    result = fetch_week_schedule(branch_id, sunday)
    all_days.concat(result[:days])
    all_sessions.concat(result[:sessions])
  end

  all_days.uniq!

  # Sort sessions by day and time
  day_order = all_days.each_with_index.to_h
  all_sessions.sort_by! { |s| [day_order[s[:day]] || 99, Time.parse(s[:start_time])] }

  {
    key: branch_key,
    name: branch_name,
    id: branch_id,
    days: all_days,
    schedule: all_sessions.group_by { |s| s[:day] }.transform_values do |items|
      merge_items(items).map do |item|
        {
          start_time: item[:start_time],
          end_time: item[:end_time],
          lanes: item[:lanes]
        }
      end
    end
  }
end

def merge_items(items)
  merged = []
  items.each do |item|
    prev = merged.last
    if prev && prev[:lanes] == item[:lanes] && prev[:end_time] == item[:start_time]
      prev[:end_time] = item[:end_time]
    else
      merged << item.dup
    end
  end
  merged
end

# Fetch all branches
puts "Fetching schedules for #{BRANCHES.size} branches (#{WEEKS_TO_FETCH} weeks each)..."
branches_data = []
all_days = []

BRANCHES.each do |key, info|
  print "  #{info[:name]}..."
  data = fetch_branch_schedule(info[:id], key, info[:name])
  if data
    branches_data << data
    all_days.concat(data[:days])
    total_sessions = data[:schedule].values.flatten.size
    puts " #{total_sessions} sessions"
  else
    puts " FAILED"
  end
end

# Sort days chronologically, handling year rollover
all_days = all_days.uniq
today = Date.today
all_days.sort_by! do |d|
  month, day = d.split(" ").last.split("/").map(&:to_i)
  year = month < today.month - 6 ? today.year + 1 : today.year
  Date.new(year, month, day)
end

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
