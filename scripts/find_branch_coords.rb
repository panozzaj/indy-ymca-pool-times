#!/usr/bin/env ruby
# frozen_string_literal: true

# Finds lat/lng coordinates for YMCA branches using Nominatim (OpenStreetMap).
# Run with: ruby scripts/find_branch_coords.rb
# Output: data/branches.json

require "net/http"
require "uri"
require "json"
require "optparse"

BRANCHES = {
  "westfield" => { name: "Ascension St. Vincent YMCA in Westfield", address: "17660 Shamrock Blvd, Westfield, IN 46074" },
  "avondale" => { name: "Avondale Meadows YMCA", address: "3908 Meadows Dr, Indianapolis, IN 46205" },
  "baxter" => { name: "Baxter YMCA", address: "7900 Shelby St, Indianapolis, IN 46227" },
  "benjamin" => { name: "Benjamin Harrison YMCA", address: "5736 Lee Rd, Indianapolis, IN 46216" },
  "fishers" => { name: "Fishers YMCA", address: "9012 E 126th St, Fishers, IN 46038" },
  "hendricks" => { name: "Hendricks Regional Health YMCA", address: "301 Satori Pkwy, Avon, IN 46123" },
  "irsay" => { name: "Irsay Family YMCA", address: "7900 W 21st St, Indianapolis, IN 46214" },
  "jordan" => { name: "Jordan YMCA", address: "8400 Westfield Blvd, Indianapolis, IN 46240" },
  "orthoindy" => { name: "OrthoIndy Foundation YMCA", address: "5315 Lafayette Rd, Indianapolis, IN 46254" },
  "ransburg" => { name: "Ransburg YMCA", address: "501 N Shortridge Rd, Indianapolis, IN 46219" },
  "witham" => { name: "Witham Family YMCA", address: "1000 S Lebanon St, Lebanon, IN 46052" }
}.freeze

options = { dry_run: false, output: "data/branches.json" }

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("--dry-run", "Preview without writing") do
    options[:dry_run] = true
  end

  opts.on("-o", "--output FILE", "Output file (default: data/branches.json)") do |v|
    options[:output] = v
  end

  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end.parse!

def geocode(address)
  params = {
    q: address,
    format: "json",
    limit: 1
  }
  url = "https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(params)}"

  response = `curl -s -A "YMCA-Pool-Times-Geocoder/1.0" '#{url}'`
  data = JSON.parse(response)

  if data.any?
    { lat: data[0]["lat"].to_f.round(6), lng: data[0]["lon"].to_f.round(6) }
  else
    nil
  end
rescue StandardError => e
  puts "  Error: #{e.message}"
  nil
end

puts "Finding coordinates for #{BRANCHES.size} YMCA branches using Nominatim...\n\n"

results = []

BRANCHES.each do |key, info|
  print "  #{info[:name]}..."
  coords = geocode(info[:address])
  if coords
    results << {
      key: key,
      name: info[:name],
      address: info[:address],
      lat: coords[:lat],
      lng: coords[:lng]
    }
    puts " #{coords[:lat]}, #{coords[:lng]}"
  else
    puts " FAILED (no results)"
  end
  sleep 1.1 # Nominatim rate limit: 1 request/second
end

json = JSON.pretty_generate(results)

if options[:dry_run]
  puts "\n[DRY RUN] Would write to #{options[:output]}:\n\n"
  puts json
else
  File.write(options[:output], json)
  puts "\nWrote #{results.size} branches to #{options[:output]}"
end
