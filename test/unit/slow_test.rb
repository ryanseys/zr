# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../support/slow"

# The report at the end of a run: the slowest tests by name, the groups
# that took the most time, and with `SLOW` the time that the examples
# that build a program spent, by directory. It runs after all tests, so a
# fault in it shows only there, once, at the end of a full tier.
class SlowTest < Minitest::Test
  Slow = Zr::Test::Slow

  def test_report_lists_slowest_tests_and_time_per_directory
    io = StringIO.new
    reporter = Slow::Reporter.new(io, 2)
    reporter.record(result("Fast", "quick", 0.1, "test/unit/time_test.rb"))
    reporter.record(result("Slow", "long", 2.5, "test/unit/time_test.rb", lower: 1.0, link: 0.5, run: 0.25))
    reporter.record(result("Slow", "longer", 3.0, "test/unit/eval_test.rb", lower: 2.0, link: 0.5, run: 0.5))
    reporter.report

    assert_match(/The 2 slowest of 3 tests, 5\.5 s of 5\.6 s in all:/, io.string)
    assert_match(/3\.00 s  Slow#longer\n\s+2\.50 s  Slow#long\n/, io.string)
    assert_match(/test\/unit\/eval_test\.rb\s+1\s+2\.0\s+0\.5\s+0\.5\s+3\.0/, io.string)
    assert_match(/test\/unit\/time_test\.rb\s+1\s+1\.0\s+0\.5\s+0\.2\s+2\.5/, io.string)
    assert_match(/all 2 directories\s+2\s+3\.0\s+1\.0\s+0\.8\s+5\.5/, io.string)
  end

  # Each program test is a method of ProgramsTest in test/programs_test.rb,
  # so the parts count under the program's directory, not under that file.
  def test_a_program_test_counts_under_its_program_directory
    io = StringIO.new
    reporter = Slow::Reporter.new(io, 20)
    reporter.record(result("ProgramsTest", "test_core/gc/a.rb", 2.0, "test/programs_test.rb", lower: 1.0, link: 0.5, run: 0.5))
    reporter.report

    assert_match(%r{test/programs/core/gc\s+1\s+1\.0\s+0\.5\s+0\.5\s+2\.0}, io.string)
    refute_match(/programs_test\.rb\s+1/, io.string)
  end

  def test_report_without_build_examples_lists_only_tests
    io = StringIO.new
    reporter = Slow::Reporter.new(io, 20)
    reporter.record(result("Plain", "one", 0.5, "test/unit/plain_test.rb"))
    reporter.report

    assert_match(/The 1 slowest of 1 tests/, io.string)
    refute_match(/What the examples/, io.string)
  end

  def test_with_no_slow_a_small_run_prints_nothing_and_a_large_one_its_slowest
    small = StringIO.new
    reporter = Slow::Reporter.new(small, 10, always: false)
    reporter.record(result("Plain", "one", 0.5, "test/unit/plain_test.rb"))
    reporter.report

    assert_empty small.string

    large = StringIO.new
    reporter = Slow::Reporter.new(large, 10, always: false)
    Slow::SMALL.times { |i| reporter.record(result("Many", "test_#{i}", i * 0.1, "test/unit/many_test.rb", lower: 0.1)) }
    reporter.report

    assert_match(/The 10 slowest of #{Slow::SMALL} tests/, large.string)
    assert_match(/\d+\.\d s\s+#{Slow::SMALL} tests  test\/unit\/many_test\.rb/, large.string)
    refute_match(/What the examples/, large.string, "the build parts print only when SLOW asks")
  end

  def test_clock_adds_time_to_hash_and_runs_block_without_one
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
