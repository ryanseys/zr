# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../support/history"

# What the runs keep for later runs (tmp/zr-dev-test): the times that
# `zr-dev test --slowest` reads, which a run's journal gets as each test
# ends and the table gets at the end of the run, or at the start of a
# later run when the run was killed; and the failures that
# `zr-dev test --failed` runs again.
class HistoryTest < Minitest::Test
  History = Zr::Test::History

  def setup
    @root = Dir.mktmpdir("zr-history-root-")
    %w[test/unit/old_test.rb test/unit/a_test.rb test/unit/b_test.rb test/unit/c_test.rb].each do |file|
      FileUtils.mkdir_p(File.dirname(File.join(@root, file)))
      File.write(File.join(@root, file), "")
    end
    FileUtils.mkdir_p(File.join(@root, "test/programs/core/gc"))
    @today = Date.today.iso8601
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_a_run_adds_its_times_to_the_table_and_keeps_the_others
    Dir.mktmpdir("zr-history-") do |dir|
      File.write(File.join(dir, "times.tsv"), "9.000\t#{@today}\ttest/unit/old_test.rb\tOldTest#test_kept\n" \
                                              "1.000\t#{@today}\ttest/unit/a_test.rb\tAT#test_a\n")
      reporter = History::Reporter.new(dir, root: @root)
      reporter.start
      reporter.record(result("AT", "test_a", 2.5, "test/unit/a_test.rb"))
      reporter.record(result("ProgramsTest", "test_core/gc/x.rb", 4.0, "test/programs_test.rb"))
      reporter.report

      rows = History.read(File.join(dir, "times.tsv"))
      assert_equal %w[OldTest#test_kept ProgramsTest#test_core/gc/x.rb AT#test_a], rows.keys
      assert_in_delta 2.5, rows.fetch("AT#test_a").seconds
      assert_equal "test/programs/core/gc", rows.fetch("ProgramsTest#test_core/gc/x.rb").group
      assert_equal %w[failed.txt times.tsv], Dir.children(dir).sort
    end
  end

  def test_a_killed_run_keeps_its_times_for_the_next_run
    Dir.mktmpdir("zr-history-") do |dir|
      gone = Process.spawn(RbConfig.ruby, "-e", "exit")
      Process.wait(gone)
      File.write(File.join(dir, "times-#{gone}.tsv"), "3.000\t#{@today}\ttest/unit/b_test.rb\tBT#test_b\n")
      running = File.join(dir, "times-#{Process.ppid}.tsv")
      File.write(running, "1.000\t#{@today}\ttest/unit/c_test.rb\tCT#test_c\n")

      History.merge(dir, root: @root)

      assert_equal ["BT#test_b"], History.read(File.join(dir, "times.tsv")).keys
      assert_path_exists running, "the journal of a run that still goes stays"
    end
  end

  # A row lasts while its group is there and it ran in the last
  # KEEP_DAYS days, so the table does not grow with each rename.
  def test_the_table_drops_a_test_whose_file_is_gone_or_that_has_not_run_for_long
    Dir.mktmpdir("zr-history-") do |dir|
      long_ago = (Date.today - History::KEEP_DAYS - 1).iso8601
      File.write(File.join(dir, "times.tsv"), "1.000\t#{@today}\ttest/unit/a_test.rb\tAT#test_kept\n" \
                                              "1.000\t#{@today}\ttest/unit/gone_test.rb\tGT#test_gone\n" \
                                              "1.000\t#{long_ago}\ttest/unit/b_test.rb\tBT#test_old\n")
      reporter = History::Reporter.new(dir, root: @root)
      reporter.start
      reporter.record(result("CT", "test_c", 0.5, "test/unit/c_test.rb"))
      reporter.report

      assert_equal %w[AT#test_kept CT#test_c], History.read(File.join(dir, "times.tsv")).keys.sort
    end
  end

  def test_the_failure_list_drops_passes_and_keeps_what_did_not_run
    Dir.mktmpdir("zr-history-") do |dir|
      path = File.join(dir, "failed.txt")
      File.write(path, "test/unit/a_test.rb:3\ntest/unit/b_test.rb:5\n")
      reporter = History::Reporter.new(dir, root: @root)
      reporter.record(result("AT", "test_a", 0.1, File.join(History::ROOT, "test/unit/a_test.rb"), line: 3))
      reporter.record(result("ProgramsTest", "test_core/x.rb", 0.1, "test/programs_test.rb", failed: true))
      reporter.record(result("CT", "test_c", 0.1, File.join(History::ROOT, "test/unit/c_test.rb"), line: 7, skipped: true))
      reporter.report

      assert_equal ["test/unit/b_test.rb:5", "program core/x.rb"], History.failed(path)
    end
  end

  def test_the_report_gives_the_slowest_tests_and_groups
    io = StringIO.new
    rows = [History::Row.new(3.0, "2026-01-03", "test/unit/a_test.rb", "AT#test_slow"),
            History::Row.new(1.0, "2026-01-03", "test/unit/a_test.rb", "AT#test_fast"),
            History::Row.new(2.0, "2026-01-02", "test/programs/core/gc", "ProgramsTest#test_core/gc/x.rb")]

    History.report(rows, 2, io, dated: true)

    assert_match(/The 2 slowest of 3 tests, 5\.0 s of 6\.0 s in all:/, io.string)
    assert_match(/3\.00 s  AT#test_slow  \(2026-01-03\)\n\s+2\.00 s  ProgramsTest#test_core\/gc\/x\.rb  \(2026-01-02\)\n/, io.string)
    assert_match(/4\.0 s\s+2 tests  test\/unit\/a_test\.rb\n\s+2\.0 s\s+1 tests  test\/programs\/core\/gc\n/, io.string)
  end

  private

  def result(klass, name, time, file, line: 1, failed: false, skipped: false)
    Minitest::Result.new(name).tap do |r|
      r.klass = klass
      r.time = time
      r.source_location = [file, line]
      r.failures << Minitest::Assertion.new("no") if failed
      r.failures << Minitest::Skip.new("later") if skipped
    end
  end
end
