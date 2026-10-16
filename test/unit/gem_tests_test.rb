# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../tool/gem_tests"

# The parts of `zr-dev gem-tests` that need neither the network nor zr:
# the list of bundled gems, the revision to fetch, the command of a gem's
# tests, the reader of a verbose report, and the tags.
class GemTestsTest < Minitest::Test
  GemTests = Zr::Dev::GemTests

  BUNDLED = <<~TEXT
    # gem-name version repository-url [revision]
    #
    minitest            6.0.6  https://github.com/minitest/minitest
    debug               1.11.1  https://github.com/ruby/debug 6510cfbc7496c55ebbefa437a25c17ca58f7c5eb

    test-unit           3.7.8   https://github.com/test-unit/test-unit
  TEXT

  def test_a_bundled_gems_file_gives_a_row_for_each_gem
    rows = GemTests::Bundled.parse(BUNDLED)

    assert_equal %w[minitest debug test-unit], rows.map(&:name)
  end

  def test_a_row_without_a_revision_has_none
    row = GemTests::Bundled.parse(BUNDLED).first

    assert_equal({ name: "minitest", version: "6.0.6", url: "https://github.com/minitest/minitest", revision: nil }, row.to_h)
  end

  def test_a_row_with_a_revision_keeps_it
    row = GemTests::Bundled.parse(BUNDLED).find { it.name == "debug" }

    assert_equal "6510cfbc7496c55ebbefa437a25c17ca58f7c5eb", row.revision
  end

  def test_a_gem_without_a_revision_fetches_the_tag_of_its_version
    row = GemTests::Bundled.new(name: "minitest", version: "6.0.6", url: "u", revision: nil)

    assert_equal %w[v6.0.6 6.0.6], row.revisions
  end

  def test_a_gem_with_a_revision_fetches_only_that
    row = GemTests::Bundled.new(name: "debug", version: "1.11.1", url: "u", revision: "6510cfb")

    assert_equal ["6510cfb"], row.revisions
  end

  def test_most_gems_run_rake_test_with_the_verbose_option
    argv = GemTests.argv("minitest", ruby: "/r/ruby", rake: "/r/rake")

    assert_equal ["/r/ruby", "/r/rake", "test", "TESTOPTS=-v"], argv
  end

  def test_rbs_runs_its_stdlib_tests_and_skips_the_files_of_the_list
    argv = GemTests.argv("rbs", ruby: "/r/ruby", rake: "/r/rake", rbs_skips: ["/a/skip", "/a/skip_win"])

    assert_equal ["/r/ruby", "/r/rake", "stdlib_test", "validate", "RBS_SKIP_TESTS=/a/skip:/a/skip_win",
                  "SKIP_RBS_VALIDATION=true", "TESTOPTS=-v"], argv
  end

  def test_rexml_runs_its_script_without_the_performance_test
    argv = GemTests.argv("rexml", ruby: "/r/ruby", rake: "/r/rake")

    assert_equal ["/r/ruby", "test/run.rb", "--ignore-name=/linear_performance/", "-v"], argv
  end

  def test_test_unit_runs_its_own_script
    argv = GemTests.argv("test-unit", ruby: "/r/ruby", rake: "/r/rake")

    assert_equal ["/r/ruby", "test/run.rb", "-v"], argv
  end

  def test_csv_runs_its_own_script
    argv = GemTests.argv("csv", ruby: "/r/ruby", rake: "/r/rake")

    assert_equal ["/r/ruby", "run-test.rb", "-v"], argv
  end

  def test_the_runner_of_cruby_skips_debug_and_win32ole
    assert_equal %w[debug win32ole], GemTests::SKIPPED.keys
  end

  MINITEST = <<~OUT
    Run options: -v --seed 52600

    # Running:

    FooTest#test_d = 0.00 s = S
    FooTest#test_a = 0.00 s = .
    FooTest#test_c = 0.00 s = E
    FooTest#test_b = 0.00 s = F
    spec thing#test_0001_does a thing = 0.00 s = .

    Finished in 0.000828s, 8454.1063 runs/s, 4830.9179 assertions/s.

      1) Skipped:
    FooTest#test_d [mt.rb:6]:
    no

      2) Error:
    FooTest#test_c:
    RuntimeError: boom
        mt.rb:5:in 'FooTest#test_c'

      3) Failure:
    FooTest#test_b [mt.rb:4]:
    Expected: 1
      Actual: 2

    5 runs, 4 assertions, 1 failures, 1 errors, 1 skips
  OUT

  def test_a_verbose_minitest_report_gives_a_status_for_each_test
    examples = GemTests.read(MINITEST.dup)[:examples]

    assert_equal({ "FooTest#test_d" => "skip", "FooTest#test_a" => "pass", "FooTest#test_c" => "error",
                   "FooTest#test_b" => "fail", "spec thing#test_0001_does a thing" => "pass" },
                 examples.transform_values(&:first))
  end

  def test_a_minitest_failure_has_the_message_of_the_report
    examples = GemTests.read(MINITEST.dup)[:examples]

    assert_equal ["fail", "Expected: 1"], examples.fetch("FooTest#test_b")
  end

  def test_a_minitest_error_has_the_class_and_message
    examples = GemTests.read(MINITEST.dup)[:examples]

    assert_equal ["error", "RuntimeError: boom"], examples.fetch("FooTest#test_c")
  end

  def test_a_minitest_run_with_totals_has_ended
    assert GemTests.read(MINITEST.dup)[:ended]
  end

  def test_a_minitest_run_that_stops_in_a_test_names_it
    out = "Run options: -v\n\n# Running:\n\nFooTest#test_a = 0.00 s = .\nFooTest#test_slow = "

    result = GemTests.read(out)

    assert_equal [false, "FooTest#test_slow", ["FooTest#test_a"]], [result[:ended], result[:hung], result[:examples].keys]
  end

  TEST_UNIT = <<~OUT.gsub("<TABS>", "\t\t\t\t\t\t")
    Loaded suite tu
    Started
    Outer::TestIn:#{" "}
      test_x:<TABS>.: (0.000063)
    TestFoo:#{" "}
      test_a:<TABS>.: (0.000064)
      test_b:<TABS>F
    #{"=" * 79}
    Failure: test_b(TestFoo)
    tu.rb:4:in 'TestFoo#test_b'
    <1> expected but was
    <2>
    #{"=" * 79}
    : (0.003288)
      test_c:<TABS>E
    #{"=" * 79}
    Error: test_c(TestFoo): RuntimeError: boom
    tu.rb:5:in 'TestFoo#test_c'
    #{"=" * 79}
    : (0.000322)
      test_d:<TABS>O
    #{"=" * 79}
    Omission: no [test_d(TestFoo)]
    #{"=" * 79}
    : (0.000282)
    TestSub:#{" "}
      nested case:#{" "}
        test: does a thing:<TABS>.: (0.000055)

    Finished in 0.005141 seconds.
    #{"-" * 79}
    6 tests, 4 assertions, 1 failures, 1 errors, 0 pendings, 1 omissions, 0 notifications
  OUT

  def test_a_verbose_test_unit_report_gives_a_status_for_each_test
    examples = GemTests.read(TEST_UNIT.dup)[:examples]

    assert_equal({ "Outer::TestIn#test_x" => "pass", "TestFoo#test_a" => "pass", "TestFoo#test_b" => "fail",
                   "TestFoo#test_c" => "error", "TestFoo#test_d" => "skip",
                   "TestSub::nested case#test: does a thing" => "pass" },
                 examples.transform_values(&:first))
  end

  def test_a_test_unit_failure_has_the_first_line_of_its_report
    examples = GemTests.read(TEST_UNIT.dup)[:examples]

    assert_equal ["fail", "Failure: test_b(TestFoo)"], examples.fetch("TestFoo#test_b")
  end

  def test_a_test_unit_run_with_totals_has_ended
    assert GemTests.read(TEST_UNIT.dup)[:ended]
  end

  def test_a_test_unit_run_that_stops_in_a_test_names_it
    out = "Started\nTestFoo: \n  test_a:\t\t\t.: (0.000064)\n  test_slow:\t\t\t"

    result = GemTests.read(out)

    assert_equal "TestFoo#test_slow", result[:hung]
  end

  def test_a_report_with_no_test_has_no_examples
    result = GemTests.read("rake aborted!\n")

    assert_equal({ examples: {}, ended: false, hung: nil }, result)
  end

  def test_a_test_that_zr_fails_is_a_gap_and_the_gem_runs
    ruby = { examples: { "A#test_a" => ["pass"], "A#test_b" => ["pass"] } }
    zr = { examples: { "A#test_a" => ["pass"], "A#test_b" => ["fail", "no"] }, ended: true }

    result = GemTests.compare(ruby, zr)

    assert_equal ["ran", { "A#test_a" => %w[pass pass], "A#test_b" => ["pass", "fail", "no"] }], [result["state"], result["examples"]]
  end

  def test_a_test_that_zr_never_reached_is_missing
    ruby = { examples: { "A#test_a" => ["pass"], "A#test_b" => ["pass"] } }
    zr = { examples: { "A#test_a" => ["pass"] }, timed_out: true, hung: "A#test_b" }

    result = GemTests.compare(ruby, zr)

    assert_equal %w[pass missing], result["examples"]["A#test_b"]
  end

  def test_a_gem_whose_tests_never_start_in_zr_does_not_load
    ruby = { examples: { "A#test_a" => ["pass"] } }
    zr = { examples: {}, timed_out: false, error: "cannot load such file" }

    result = GemTests.compare(ruby, zr)

    assert_equal ["load", "cannot load such file"], [result["state"], result["error"]]
  end

  def test_tags_come_from_the_tests_that_ruby_passes_and_zr_does_not
    result = { "state" => "ran", "hung" => "A#test_h",
               "examples" => { "A#test_ok" => %w[pass pass], "A#test_f" => %w[pass fail], "A#test_h" => %w[pass missing],
                               "A#test_skip" => %w[skip skip], "A#test_ruby_fails" => %w[fail fail] } }

    tags = GemTests.tags_from(result, {})

    assert_equal({ "A#test_f" => "fails", "A#test_h" => "hangs" }, tags)
  end

  def test_a_gem_that_does_not_load_has_one_tag_for_the_gem
    assert_equal({ "" => "load" }, GemTests.tags_from({ "state" => "load", "examples" => {} }, {}))
  end

  def test_tags_round_trip_through_the_file
    Dir.mktmpdir do |dir|
      tags = GemTests::Tags.new(dir)
      tags.write("rake", { "A#test_f" => "fails", "A#test_h" => "hangs" })

      assert_equal({ "A#test_f" => "fail", "A#test_h" => "timeout" }, tags.reasons("rake"))
      assert_equal({ "A#test_f" => "fails", "A#test_h" => "hangs" }, tags.kinds("rake"))
    end
  end

  def test_writing_tags_again_keeps_the_reason_of_a_fail_tag
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "rake.txt"), "A#test_f\tcext\nA#test_g\tfail\n")
      tags = GemTests::Tags.new(dir)

      tags.write("rake", { "A#test_f" => "fails", "A#test_new" => "fails" })

      assert_equal({ "A#test_f" => "cext", "A#test_new" => "fail" }, tags.reasons("rake"))
    end
  end

  def test_the_tag_of_a_gem_that_does_not_load_is_a_star_line
    Dir.mktmpdir do |dir|
      tags = GemTests::Tags.new(dir)
      tags.write("csv", { "" => "load" })

      assert_equal({ "" => "load" }, tags.kinds("csv"))
      assert_equal "*\tload\n", File.read(File.join(dir, "csv.txt"))
    end
  end

  def test_writing_no_tag_removes_the_file
    Dir.mktmpdir do |dir|
      tags = GemTests::Tags.new(dir)
      tags.write("rake", { "A#test_f" => "fails" })
      tags.write("rake", {})

      refute_path_exists File.join(dir, "rake.txt")
    end
  end

  def test_tags_of_a_gem_with_no_file_are_empty
    Dir.mktmpdir { |dir| assert_empty GemTests::Tags.new(dir).kinds("rake") }
  end
end
