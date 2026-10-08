# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/ext_compare"

# `zr-dev ext compare` (tool/lib/zr/dev/ext_compare.rb): a gem's programs
# built with zr's port and with the real C extension, summed into one row
# of a table.
class ExtCompareTest < Minitest::Test
  Compare = Zr::Dev::ExtCompare
  Run = Compare::Run

  def test_a_row_counts_the_passes_and_sums_each_ways_time_and_size
    runs = [Run.new("a.rb", :port, true, 0.5, 4_000_000), Run.new("a.rb", :native, true, 0.25, 6_000_000),
            Run.new("b.rb", :port, false, 1.0, 2_000_000), Run.new("b.rb", :native, true, 0.75, 4_000_000)]

    assert_equal "| json | 2 | 1 | 2 | 1.50 s | 1.00 s | 3.0 MB | 5.0 MB |", Compare.row("json", runs)
  end

  def test_a_build_that_failed_counts_as_a_program_but_not_in_the_time
    runs = [Run.new("a.rb", :port, true, 0.5, 4_000_000), Run.new("a.rb", :native, false, nil, nil)]

    assert_equal "| strscan | 1 | 1 | 0 | 0.50 s | 0.00 s | 4.0 MB | 0.0 MB |", Compare.row("strscan", runs)
  end

  def test_the_native_build_names_the_gem_only_when_it_is_installed
    assert_equal ["--native-ext", "no-such-gem-here"], Compare.native_flags("no-such-gem-here")
  end
end
