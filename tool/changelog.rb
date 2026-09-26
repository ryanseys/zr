# frozen_string_literal: true

# Prints the CHANGELOG.md section of one version, for the notes of its
# GitHub Release. The release workflow runs it; it fails when the
# section is missing or has no date, so a tag cannot publish a version
# that the changelog does not describe.
#
#   ruby tool/changelog.rb 0.1.0 > notes.md

version = ARGV.fetch(0) { abort "usage: ruby tool/changelog.rb VERSION" }
text = File.read(File.expand_path("../CHANGELOG.md", __dir__))
heading = /^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}$/
start = text.index(heading) or abort "CHANGELOG.md has no \"## [#{version}] - YYYY-MM-DD\" section"
body = text[start..].lines.drop(1)
body = body.take_while { |line| !line.start_with?("## [", "[") }
abort "the #{version} section of CHANGELOG.md is empty" if body.join.strip.empty?
puts body.join.strip
