# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/bump"

# `zr-dev bump` (tool/bump.rb): the edits of a release's commit.
class BumpTest < Minitest::Test
  Bump = Zr::Dev::Commands::Bump
  REPO = "https://github.com/ryanseys/zr"

  CHANGELOG = <<~MD
    # Changelog

    ## [Unreleased]

    ### Fixed

    - A thing.

    [Unreleased]: #{REPO}/commits/main
  MD

  def test_the_first_release_dates_unreleased_and_links_its_tag
    text = Bump.changelog(CHANGELOG, "0.1.0", nil, "2026-11-02")

    assert_includes text, "## [Unreleased]\n\n## [0.1.0] - 2026-11-02\n\n### Fixed\n"
    assert_includes text, "[Unreleased]: #{REPO}/compare/v0.1.0...HEAD\n[0.1.0]: #{REPO}/releases/tag/v0.1.0\n"
    assert_equal "### Fixed\n\n- A thing.", Zr::Dev::Commands::Changelog.notes("0.1.0", text)
  end

  def test_a_later_release_links_the_compare_with_the_last
    text = Bump.changelog(Bump.changelog(CHANGELOG, "0.1.0", nil, "2026-11-02").sub("## [Unreleased]\n", "## [Unreleased]\n\n- More.\n"),
                          "0.2.0", "0.1.0", "2026-12-01")

    assert_equal %w[0.2.0 0.1.0], Bump.versions(text)
    assert_includes text, "[0.2.0]: #{REPO}/compare/v0.1.0...v0.2.0"
  end

  def test_an_empty_unreleased_is_refused
    empty = Bump.changelog(CHANGELOG, "0.1.0", nil, "2026-11-02")
    assert_raises(Bump::Refused) { Bump.changelog(empty, "0.2.0", "0.1.0", "2026-12-01") }
  end

  def test_the_version_the_lock_and_the_readme_change
    assert_equal %(module Zr\n  VERSION = "0.2.0"\nend\n), Bump.version_rb(%(module Zr\n  VERSION = "0.1.0"\nend\n), "0.2.0")
    assert_equal "    zr (0.2.0)\n  zr (0.2.0) sha256=x\n", Bump.lock("    zr (0.1.0)\n  zr (0.1.0) sha256=x\n", "0.1.0", "0.2.0")
    assert_raises(Bump::Refused) { Bump.lock("rake (13)\n", "0.1.0", "0.2.0") }
    assert_equal "[a](#{REPO}/blob/v0.2.0/README.md) [b](#{REPO}/tree/v0.2.0/docs)",
                 Bump.readme("[a](#{REPO}/blob/v0.1.0/README.md) [b](#{REPO}/tree/v0.1.0/docs)", "0.1.0", "0.2.0")
  end
end
