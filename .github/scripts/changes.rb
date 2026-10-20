# frozen_string_literal: true

# Says what a CI run must check, as outputs of the `changes` job
# (.github/workflows/ci.yml):
#
#   code=true   the change has a file that is not documentation, so the
#               build and the smoke tests run; false for a pull request
#               that changes only docs/ and Markdown files
#   full=true   the full suite runs: a push to main, the nightly run, or
#               a run by hand
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

DOCS = %r{\A(docs/.*|[^/]+\.md)\z}

event = ENV.fetch("GITHUB_EVENT_NAME")
full = %w[push schedule workflow_dispatch].include?(event)
code = true
if event == "pull_request"
  number = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))).dig("pull_request", "number")
  files = []
  page = 1
  loop do
    uri = URI("#{ENV.fetch("GITHUB_API_URL")}/repos/#{ENV.fetch("GITHUB_REPOSITORY")}/pulls/#{number}/files?per_page=100&page=#{page}")
    request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{ENV.fetch("GITHUB_TOKEN")}", "Accept" => "application/vnd.github+json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    abort "changes: GitHub answered #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)
    batch = JSON.parse(response.body).map { |file| file.fetch("filename") }
    files.concat(batch)
    break if batch.size < 100

    page += 1
  end
  # CHANGELOG.md ships in the gem: a change to it is not docs only.
  code = files.empty? || !files.all? { |file| file.match?(DOCS) && file != "CHANGELOG.md" }
end

outputs = { "code" => code, "full" => full, "ruby" => File.read(File.expand_path("../../.ruby-version", __dir__)).strip }
outputs.each { |name, value| puts "#{name}=#{value}" }
File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |file| outputs.each { |name, value| file.puts "#{name}=#{value}" } }
