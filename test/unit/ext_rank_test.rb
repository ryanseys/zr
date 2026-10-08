# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../tool/lib/zr/dev/ext_rank"
require_relative "../../tool/lib/zr/dev/gems/fetched_gems"

# `zr-dev ext rank` (tool/lib/zr/dev/ext_rank.rb): the C extensions that
# block the most downloaded gems, worst first, and what a build of each
# lacks of zr's C API.
class ExtRankTest < Minitest::Test
  Rank = Zr::Dev::ExtRank
  Row = Zr::Dev::Gems::Table::Row

  def row(gem, kind) = Row.new(gem: gem, version: "1.0", source: "rubygems", tier: "refused", kind: kind, detail: "",
                               zr_commit: "", date: "", downloads: "")

  def test_extensions_rank_by_the_top_gems_they_block_then_by_downloads
    table = [row("rails", "cext:nokogiri"), row("loofah", "cext:nokogiri"), row("bcrypt", "cext:bcrypt"),
             row("devise", "cext:bcrypt"), row("oj", "cext:oj"), row("fast", "cext:fast_blank"), row("rack", ""),
             row("far_down", "cext:zstd-ruby")]
    top = { "rails" => 900, "loofah" => 800, "devise" => 700, "bcrypt" => 600, "nokogiri" => 650, "oj" => 50, "fast" => 40,
            "fast_blank" => 400, "rack" => 10, "far_down" => 1 }

    ranked = Rank.ranked(table, top, 9)

    assert_equal [["nokogiri", %w[loofah rails]], ["bcrypt", %w[bcrypt devise]], ["fast_blank", %w[fast]], ["oj", %w[oj]]],
                 ranked.map { |entry| [entry.name, entry.blocked] }
    assert_equal [650, 600, 400, 50], ranked.map(&:downloads)
  end

  def test_the_worklist_weighs_each_missing_function_by_the_gems_waiting
    big = Rank::Entry.new("big", %w[a b c], 0)
    small = Rank::Entry.new("small", %w[d], 0)
    reports = [Rank::Report.new(big, "1", :lacks, %w[rb_x rb_y], ""), Rank::Report.new(small, "1", :lacks, %w[rb_y rb_z], ""),
               Rank::Report.new(small, "1", :ready, [], "")]

    assert_equal [["rb_y", 4], ["rb_x", 3], ["rb_z", 1]], Rank.worklist(reports)
  end

  def test_a_gem_that_was_not_fetched_reports_how_to_fetch_it
    Dir.mktmpdir do |dir|
      report = Rank.build(Rank::Entry.new("absent", ["x"], 0), Zr::Dev::Gems::FetchedGems.new(dir))

      assert_equal [:failed, "not fetched; run `zr-dev gems try absent`"], [report.status, report.detail]
    end
  end

  def test_a_child_that_runs_too_long_is_stopped
    error = assert_raises(Rank::ChildFailed) { Rank.in_child(1) { sleep 30 } }

    assert_equal "the build ran past 1 s", error.message
    assert_equal [:done], Rank.in_child(5) { [:done] }
    assert_equal "boom", assert_raises(Rank::ChildFailed) { Rank.in_child(5) { raise "boom" } }.message
  end
end
