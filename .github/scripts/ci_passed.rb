# frozen_string_literal: true

# Stops a release unless every CI job passed for the commit it
# publishes. The release workflow runs it before it publishes anything.
#
#   GITHUB_TOKEN=... ruby .github/scripts/ci_passed.rb OWNER/REPO SHA

require "json"
require "net/http"
require "yaml"

repo, sha = ARGV.fetch(0), ARGV.fetch(1)
token = ENV.fetch("GITHUB_TOKEN")

# The names of the jobs in ci.yml: each one must have passed.
ci = YAML.load_file(File.expand_path("../workflows/ci.yml", __dir__))
required = ci.fetch("jobs").map { |id, job| job.fetch("name", id) }

runs = []
page = 1
loop do
  uri = URI("https://api.github.com/repos/#{repo}/commits/#{sha}/check-runs?per_page=100&page=#{page}")
  request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json")
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  abort "ci_passed: GitHub answered #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)
  batch = JSON.parse(response.body).fetch("check_runs")
  runs.concat(batch)
  break if batch.size < 100

  page += 1
end

# The newest run of each job counts: a job that was run again replaces
# its earlier result.
latest = runs.group_by { |run| run["name"] }.transform_values { |group| group.max_by { |run| run["started_at"].to_s } }
missing = required.reject { |name| latest.key?(name) }
failed = required.select { |name| latest.key?(name) && latest[name]["conclusion"] != "success" }

required.each { |name| puts format("%-8s %s", latest.dig(name, "conclusion") || "missing", name) }
abort "ci_passed: CI has not passed for #{sha}: #{(missing + failed).join(", ")}" unless missing.empty? && failed.empty?
puts "ci_passed: every CI job passed for #{sha}"
