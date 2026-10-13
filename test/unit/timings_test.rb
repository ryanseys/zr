# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../support/timings"

# The times that each run keeps (tmp/zr-dev-test/times.tsv), which
# `zr-dev test --slowest` reads: a run's journal gets each time as the
# test ends, and the table gets the journal at the end of the run, or at
# the start of a later run when the run was killed.
class TimingsTest < Minitest::Test
  Timings = Zr::Test::Timings

  def test_a_run_adds_its_times_to_the_table_and_keeps_the_others
    Dir.mktmpdir("zr-timings-") do |dir|
      File.write(File.join(dir, "times.tsv"), "9.000\t2026-01-01\ttest/unit/old_test.rb\tOldTest#test_kept\n" \
                                              "1.000\t2026-01-01\ttest/unit/a_test.rb\tAT#test_a\n")
      reporter = Timings::Reporter.new(dir)
      reporter.start
      reporter.record(result("AT", "test_a", 2.5, "test/unit/a_test.rb"))
      reporter.record(result("ProgramsTest", "test_core/gc/x.rb", 4.0, "test/programs_test.rb"))
      reporter.report

      rows = Timings.read(File.join(dir, "times.tsv"))
      assert_equal %w[OldTest#test_kept ProgramsTest#test_core/gc/x.rb AT#test_a], rows.keys
      assert_in_delta 2.5, rows.fetch("AT#test_a").seconds
      assert_equal "test/programs/core/gc", rows.fetch("ProgramsTest#test_core/gc/x.rb").group
      assert_equal "2026-01-01", rows.fetch("OldTest#test_kept").date
      assert_equal ["times.tsv"], Dir.children(dir)
    end
  end

  def test_a_killed_run_keeps_its_times_for_the_next_run
    Dir.mktmpdir("zr-timings-") do |dir|
      gone = Process.spawn(RbConfig.ruby, "-e", "exit")
      Process.wait(gone)
      File.write(File.join(dir, "times-#{gone}.tsv"), "3.000\t2026-01-02\ttest/unit/b_test.rb\tBT#test_b\n")
      running = File.join(dir, "times-#{Process.ppid}.tsv")
      File.write(running, "1.000\t2026-01-02\ttest/unit/c_test.rb\tCT#test_c\n")

      Timings.merge(dir)

      assert_equal ["BT#test_b"], Timings.read(File.join(dir, "times.tsv")).keys
      assert_path_exists running, "the journal of a run that still goes stays"
    end
  end

  def test_the_report_gives_the_slowest_tests_and_groups
    io = StringIO.new
    rows = [Timings::Row.new(3.0, "2026-01-03", "test/unit/a_test.rb", "AT#test_slow"),
            Timings::Row.new(1.0, "2026-01-03", "test/unit/a_test.rb", "AT#test_fast"),
            Timings::Row.new(2.0, "2026-01-02", "test/programs/core/gc", "ProgramsTest#test_core/gc/x.rb")]

    Timings.report(rows, 2, io, dated: true)

    assert_match(/The 2 slowest of 3 tests, 5\.0 s of 6\.0 s in all:/, io.string)
    assert_match(/3\.00 s  AT#test_slow  \(2026-01-03\)\n\s+2\.00 s  ProgramsTest#test_core\/gc\/x\.rb  \(2026-01-02\)\n/, io.string)
    assert_match(/4\.0 s\s+2 tests  test\/unit\/a_test\.rb\n\s+2\.0 s\s+1 tests  test\/programs\/core\/gc\n/, io.string)
  end

  private

  def result(klass, name, time, file)
    Minitest::Result.new(name).tap do |r|
      r.klass = klass
      r.time = time
      r.source_location = [file, 1]
    end
  end
end
