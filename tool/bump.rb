# frozen_string_literal: true

require "date"
require_relative "lib/zr/dev"
require_relative "changelog"
require_relative "../lib/zr/version"

module Zr
  module Dev
    module Commands
      # `zr-dev bump X.Y.Z` makes the commit of a release: the version in
      # lib/zr/version.rb and Gemfile.lock, the README's links to the tag,
      # and CHANGELOG.md's [Unreleased] section dated as X.Y.Z, with a new
      # empty one above it and the link references at the end. Then
      # commit, push, wait for a full CI run, and tag (docs/how-to/release.md).
      class Bump < Command
        summary "Set the version: version.rb, Gemfile.lock, the README's links and CHANGELOG.md"
        usage "X.Y.Z [--date YYYY-MM-DD] [--dry-run]"

        REPO = Zr::ISSUES_URL.delete_suffix("/issues")

        # A text that a step cannot change as it must.
        class Refused < StandardError; end

        def defaults
          @date = Date.today.iso8601
          @dry = false
        end

        def options(o)
          o.on("--date DATE", "the date of the release (default today)") { |date| @date = date }
          o.on("--dry-run", "write nothing; print what changes") { @dry = true }
        end

        def run(argv)
          version = argv.fetch(0) { fail!("give a version, X.Y.Z") }
          fail!("#{version} is not X.Y.Z") unless version.match?(/\A\d+\.\d+\.\d+\z/)
          old = Zr::VERSION
          changelog = File.read(Dev.path("CHANGELOG.md"))
          first = Bump.versions(changelog).empty?
          unless Gem::Version.new(version) > Gem::Version.new(old) || (version == old && first)
            fail!("#{version} is not after #{old}")
          end

          files = {
            "lib/zr/version.rb" => Bump.version_rb(File.read(Dev.path("lib/zr/version.rb")), version),
            "Gemfile.lock" => Bump.lock(File.read(Dev.path("Gemfile.lock")), old, version),
            "README.md" => Bump.readme(File.read(Dev.path("README.md")), old, version),
            "CHANGELOG.md" => Bump.changelog(changelog, version, Bump.versions(changelog).first, @date)
          }
          Changelog.notes(version, files.fetch("CHANGELOG.md"))
          files.each do |rel, text|
            next if File.read(Dev.path(rel)) == text

            @dry ? puts("would write #{rel}") : Paths.write_atomic(Dev.path(rel), text)
          end
          puts "Next: commit, push to main, wait for a full CI run (ci-ok), then git tag v#{version} && git push origin v#{version}"
        rescue Refused, Changelog::Missing => e
          fail!(e.message)
        end

        # The released versions in `changelog`, the newest first.
        def self.versions(changelog) = changelog.scan(/^## \[(\d+\.\d+\.\d+)\] - /).flatten

        def self.version_rb(text, version)
          raise Refused, "lib/zr/version.rb has no one VERSION line" unless text.scan(/^  VERSION = "[^"]+"$/).size == 1

          text.sub(/^  VERSION = "[^"]+"$/, %(  VERSION = "#{version}"))
        end

        def self.lock(text, old, version)
          raise Refused, "Gemfile.lock does not name zr (#{old})" unless text.include?("zr (#{old})")

          text.gsub("zr (#{old})", "zr (#{version})")
        end

        def self.readme(text, old, version) = text.gsub(%r{/(blob|tree)/v#{Regexp.escape(old)}/}, "/\\1/v#{version}/")

        # Dates the [Unreleased] section as `version`, puts an empty one
        # above it, and writes the link references at the end.
        def self.changelog(text, version, previous, date)
          heading = "## [Unreleased]\n"
          start = text.index(heading) or raise Refused, "CHANGELOG.md has no ## [Unreleased] section"
          body = text[(start + heading.size)..].lines.take_while { !_1.match?(Changelog::STOP) }.join.strip
          raise Refused, "the [Unreleased] section of CHANGELOG.md is empty" if body.empty?

          text = text.sub(heading, "#{heading}\n## [#{version}] - #{date}\n")
          text = text.sub(/^\[Unreleased\]: .*$/, "[Unreleased]: #{REPO}/compare/v#{version}...HEAD")
          link = previous ? "#{REPO}/compare/v#{previous}...v#{version}" : "#{REPO}/releases/tag/v#{version}"
          text.sub(/^(\[Unreleased\]: .*)$/, "\\1\n[#{version}]: #{link}")
        end
      end
    end
  end
end
