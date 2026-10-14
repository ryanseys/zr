# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    module Commands
      # `zr-dev changelog VERSION` prints the CHANGELOG.md section of one
      # version, for the notes of its GitHub Release. The release workflow
      # writes them through `.github/scripts/release_notes.rb`. It fails
      # when the section is missing or has no date, so a tag cannot publish
      # a version that the changelog does not describe.
      class Changelog < Command
        summary "Print the CHANGELOG.md section of a version: its release notes"
        usage "VERSION"

        PATH = Dev.path("CHANGELOG.md")
        # The lines that end a section: the next version's heading, and the
        # link definitions at the end of the file.
        STOP = /\A(## \[|\[[^\]]+\]: )/

        # A version that has no notes.
        class Missing < StandardError; end

        # The body of the dated section of `version` in `text`.
        def self.notes(version, text = File.read(PATH))
          heading = /^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}$/
          start = text.index(heading) or raise Missing, "CHANGELOG.md has no \"## [#{version}] - YYYY-MM-DD\" section"
          body = text[start..].lines.drop(1).take_while { !it.match?(STOP) }.join.strip
          raise Missing, "the #{version} section of CHANGELOG.md is empty" if body.empty?

          body
        end

        def run(argv)
          version = argv.fetch(0) { fail!("give a version") }
          puts Changelog.notes(version)
        rescue Missing => e
          fail!(e.message)
        end
      end
    end
  end
end
