# frozen_string_literal: true

# Says what a CI run must check, as outputs of the `changes` job
# (.github/workflows/ci.yml):
#
#   code=true   the change has a file that is not documentation, so the
#               build and the smoke tests run; false for a pull request
#               that changes only docs/ and Markdown files, and for a push
#               or nightly run that a full run of its commit replaces
#               (Changes.superseding)
#   full=true   the full suite runs: the nightly run, or a run by hand.
#               A push to main runs the unit tier, not the full suite:
#               macOS minutes cost the most
#   ruby=X      the pinned ruby (.ruby-version), for the container jobs
#
# A docs-only pull request still runs the `docs` job, which checks the
# generated pages and the links. A path filter on the workflow would
# skip ci-ok too, and a required check that never reports blocks the
# merge.
#
#   ruby .github/scripts/changes.rb   (reads GITHUB_* as Actions sets them)

require "json"
require "net/http"

# The choices of the run, apart from GitHub, so that a test can give them
# runs.
module Changes
  DOCS = %r{\A(docs/.*|[^/]+\.md)\z}
  # The events of a run of every program.
  FULL = %w[schedule workflow_dispatch].freeze

  # The full run that a run of `event` on `branch` gives its work to: a
  # run by hand or a nightly run of the same commit and branch that has
  # not ended, or, for a nightly run, one that passed. A full run checks
  # all that a push checks, and two runs at once build each runtime
  # twice. `runs` are the API's workflow runs of this commit. Nil when no
  # run replaces this one.
  def self.superseding(runs, event:, branch:, run_id:)
    return nil unless %w[push schedule].include?(event)

    runs.find do |run|
      run["id"] != run_id && run["head_branch"] == branch && FULL.include?(run["event"]) &&
        (run["status"] != "completed" || (event == "schedule" && run["conclusion"] == "success"))
    end
  end
end
return unless $PROGRAM_NAME == __FILE__

get = lambda do |path|
  uri = URI("#{ENV.fetch("GITHUB_API_URL")}/repos/#{ENV.fetch("GITHUB_REPOSITORY")}/#{path}")
  request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{ENV.fetch("GITHUB_TOKEN")}", "Accept" => "application/vnd.github+json")
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  raise "changes: GitHub answered #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

event = ENV.fetch("GITHUB_EVENT_NAME")
full = Changes::FULL.include?(event)
code = true
if event == "pull_request"
  number = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))).dig("pull_request", "number")
  files = []
  page = 1
  loop do
    batch = get.call("pulls/#{number}/files?per_page=100&page=#{page}").map { |file| file.fetch("filename") }
    files.concat(batch)
    break if batch.size < 100

    page += 1
  end
  # CHANGELOG.md ships in the gem: a change to it is not docs only.
  code = files.empty? || !files.all? { |file| file.match?(Changes::DOCS) && file != "CHANGELOG.md" }
elsif %w[push schedule].include?(event)
  begin
    runs = get.call("actions/workflows/ci.yml/runs?head_sha=#{ENV.fetch("GITHUB_SHA")}&per_page=100").fetch("workflow_runs")
    other = Changes.superseding(runs, event: event, branch: ENV.fetch("GITHUB_REF_NAME"), run_id: Integer(ENV.fetch("GITHUB_RUN_ID")))
    if other
      code = false
      puts "::notice::run #{other.fetch("html_url")} checks #{ENV.fetch("GITHUB_SHA")} with every program; this run builds and tests nothing"
    end
  rescue StandardError => e
    puts "::warning::changes: could not read the other runs of this commit (#{e.message}); this run checks it"
  end
end

outputs = { "code" => code, "full" => full, "ruby" => File.read(File.expand_path("../../.ruby-version", __dir__)).strip }
outputs.each { |name, value| puts "#{name}=#{value}" }
File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |file| outputs.each { |name, value| file.puts "#{name}=#{value}" } }
