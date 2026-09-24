# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../support/slow"

# The report `ZR_SLOW` asks for: the slowest tests by name, and what
# the examples that build a program spent, by directory. It runs after
# every test has, so a fault in it would show only there -- once, at
# the end of a whole tier.
class SlowTest < Minitest::Test
  Slow = Zr::Test::Slow

  def test_it_names_the_slowest_tests_and_sums_what_each_directory_spent
    io = StringIO.new
    reporter = Slow::Reporter.new(io, 2)
    reporter.record(result("Fast", "quick", 0.1, "test/spec/core/time/time_test.rb"))
    reporter.record(result("Slow", "long", 2.5, "test/spec/core/time/time_test.rb", lower: 1.0, link: 0.5, run: 0.25))
    reporter.record(result("Slow", "longer", 3.0, "test/spec/lang/eval/eval_test.rb", lower: 2.0, link: 0.5, run: 0.5))
    reporter.report

    assert_match(/The 2 slowest of 3 tests, 5\.5 s of 5\.6 s in all:/, io.string)
    assert_match(/3\.00 s  Slow#longer\n\s+2\.50 s  Slow#long\n/, io.string)
    assert_match(/test\/spec\/lang\/eval\s+1\s+2\.0\s+0\.5\s+0\.5\s+3\.0/, io.string)
    assert_match(/test\/spec\/core\/time\s+1\s+1\.0\s+0\.5\s+0\.2\s+2\.5/, io.string)
    assert_match(/all 2 directories\s+2\s+3\.0\s+1\.0\s+0\.8\s+5\.5/, io.string)
  end

  def test_a_run_with_no_examples_that_build_reports_the_tests_alone
    io = StringIO.new
    reporter = Slow::Reporter.new(io, 20)
    reporter.record(result("Plain", "one", 0.5, "test/unit/plain_test.rb"))
    reporter.report

    assert_match(/The 1 slowest of 1 tests/, io.string)
    refute_match(/What the examples/, io.string)
  end

  def test_the_clock_adds_to_the_row_it_is_given_and_runs_the_block_without_one
    row = {}
    assert_equal 3, Slow.clock(row, :lower) { 3 }
    Slow.clock(row, :lower) { nil }
    assert_operator row[:lower], :>=, 0
    assert_equal 4, Slow.clock(nil, :lower) { 4 }
  end

  private

  def result(klass, name, time, file, **phases)
    Minitest::Result.new(name).tap do |r|
      r.klass = klass
      r.time = time
      r.source_location = [file, 1]
      r.metadata[Slow::KEY] = phases unless phases.empty?
    end
  end
end
