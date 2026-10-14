# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/changelog"

# `zr-dev changelog VERSION` (tool/changelog.rb) gives the notes of a
# release: the body of the version's dated section of CHANGELOG.md.
class ChangelogTest < Minitest::Test
  Changelog = Zr::Dev::Commands::Changelog

  TEXT = <<~MARKDOWN
    # Changelog

    [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) is the format.

    ## [Unreleased]

    ### Added

    - A thing for later.

    ## [0.2.0] - 2027-01-04

    ### Added

    - Static linking.
    [Linking](docs/explanation/linking.md) tells how.

    ### Fixed

    - A crash.

    ## [0.1.0] - 2026-11-02

    The first public release.

    [Unreleased]: https://github.com/ryanseys/zr/compare/v0.2.0...main
    [0.2.0]: https://github.com/ryanseys/zr/compare/v0.1.0...v0.2.0
  MARKDOWN

  # A line that starts with a link is part of the notes; the next
  # version's heading ends them.
  def test_the_notes_are_the_body_of_the_dated_section
    want = "### Added\n\n- Static linking.\n[Linking](docs/explanation/linking.md) tells how.\n\n### Fixed\n\n- A crash."

    assert_equal want, Changelog.notes("0.2.0", TEXT)
  end

  # The link definitions at the end of the file are no part of the last
  # section.
  def test_the_links_at_the_end_end_the_last_section
    assert_equal "The first public release.", Changelog.notes("0.1.0", TEXT)
  end

  def test_a_version_with_no_dated_section_has_no_notes
    error = assert_raises(Changelog::Missing) { Changelog.notes("0.3.0", TEXT) }

    assert_includes error.message, "## [0.3.0] - YYYY-MM-DD"
    assert_raises(Changelog::Missing) { Changelog.notes("Unreleased", TEXT) }
  end

  def test_an_empty_section_has_no_notes
    text = "## [0.4.0] - 2027-02-01\n\n## [0.3.0] - 2027-01-20\n\n- Fixes.\n"

    assert_raises(Changelog::Missing) { Changelog.notes("0.4.0", text) }
  end
end
