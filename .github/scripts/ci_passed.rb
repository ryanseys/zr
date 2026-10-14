# frozen_string_literal: true

# Stops a release unless every CI job passed for the commit it
# publishes. The release workflow runs it before it publishes anything.
#
#   GITHUB_TOKEN=... ruby .github/scripts/ci_passed.rb OWNER/REPO SHA

require "json"
require "net/http"
require "yaml"

# The jobs of ci.yml, by the names that GitHub gives their check runs.
module CIJobs
  CI = File.expand_path("../workflows/ci.yml", __dir__)
  MATRIX_VALUE = /\$\{\{\s*matrix\.(\w+)\s*\}\}/

  # The name of each job, and of each row of a job's matrix: a row's
  # name is the job's name with the row's values put in.
  def self.required(ci = YAML.load_file(CI))
    ci.fetch("jobs").flat_map do |id, job|
      name = job.fetch("name", id)
      rows = job.dig("strategy", "matrix", "include") || [{}]
      rows.map { |row| name.gsub(MATRIX_VALUE) { row.fetch(Regexp.last_match(1)) } }
    end
  end
end
return unless $PROGRAM_NAME == __FILE__

repo, sha = ARGV.fetch(0), ARGV.fetch(1)
token = ENV.fetch("GITHUB_TOKEN")
# Each one must have passed.
required = CIJobs.required

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
