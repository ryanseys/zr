# frozen_string_literal: true

# Stops a release unless a CI run of main passed for the commit that it
# publishes: a run of ci.yml for a push, the nightly schedule or a run by
# hand (not a pull request's), whose `ci-ok` job passed. Each lane of a
# push runs its target's units and programs; the nightly run adds every
# program. The release workflow runs it before it builds anything, and
# reads the run's id (`ci_run=` on GITHUB_OUTPUT) to fetch that run's gem
# and runtime bundles, which the release publishes.
#
#   GITHUB_TOKEN=... ruby .github/scripts/ci_passed.rb OWNER/REPO SHA

require "json"
require "net/http"

# The choice of the run, apart from GitHub, so that a test can give it runs.
module CIGate
  EVENTS = %w[push schedule workflow_dispatch].freeze
  JOB = "ci-ok"

  # The newest run in `runs` (the API's workflow runs) of one of EVENTS
  # that passed, or nil.
  def self.run(runs)
    runs.select { |run| EVENTS.include?(run["event"]) && run["conclusion"] == "success" }
        .max_by { |run| run["created_at"].to_s }
  end

  # Whether the `jobs` of a run (the API's jobs) hold a `ci-ok` that passed.
  def self.ok?(jobs) = jobs.any? { |job| job["name"] == JOB && job["conclusion"] == "success" }
end
return unless $PROGRAM_NAME == __FILE__

repo, sha = ARGV.fetch(0), ARGV.fetch(1)
token = ENV.fetch("GITHUB_TOKEN")

get = lambda do |path|
  uri = URI("https://api.github.com/repos/#{repo}/#{path}")
  request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json")
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  abort "ci_passed: GitHub answered #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

runs = get.call("actions/workflows/ci.yml/runs?head_sha=#{sha}&status=completed&per_page=100").fetch("workflow_runs")
runs.each { |run| puts format("%-8s %-18s run %s", run["conclusion"], run["event"], run["id"]) }
run = CIGate.run(runs) or abort "ci_passed: no CI run passed for #{sha}; run `gh workflow run ci.yml --ref <tag>`"
jobs = get.call("actions/runs/#{run["id"]}/jobs?filter=latest&per_page=100").fetch("jobs")
abort "ci_passed: run #{run["id"]} has no #{CIGate::JOB} that passed" unless CIGate.ok?(jobs)

File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |file| file.puts "ci_run=#{run["id"]}" } if ENV["GITHUB_OUTPUT"]
puts "ci_passed: run #{run["id"]} passed for #{sha}"
