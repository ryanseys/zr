# frozen_string_literal: true

# Checks that a release tag names the version in lib/zr/version.rb,
# writes that version's CHANGELOG.md section to notes.md (`zr-dev
# changelog`), and gives the version to the later steps of the job
# (VERSION in GITHUB_ENV). The release workflow runs it first.
#
#   ruby .github/scripts/release_notes.rb v0.1.0

require_relative "../../lib/zr/version"
require_relative "../../tool/changelog"

tag = ARGV.fetch(0) { abort "usage: ruby .github/scripts/release_notes.rb TAG" }
version = Zr::VERSION
abort "release_notes: the tag is #{tag}, but Zr::VERSION is #{version}" unless tag == "v#{version}"

begin
  File.write("notes.md", "#{Zr::Dev::Commands::Changelog.notes(version)}\n")
rescue Zr::Dev::Commands::Changelog::Missing => e
  abort "release_notes: #{e.message}"
end
File.write(ENV.fetch("GITHUB_ENV"), "VERSION=#{version}\n", mode: "a")
