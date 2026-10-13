# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require_relative "../../tool/test"

# Tests what `zr-dev test` runs (tool/test.rb): the bin/minitest command
# that its paths and options give, which --list prints and runs nothing.
class DevTestCommandTest < Minitest::Test
  PROGRAM = "test/programs/core/signal/sigvtalrm_does_nothing.rb"

  def test_a_test_file_and_its_line_go_to_minitest
    status, out = listed("test/unit/cli_test.rb:40")

    assert_equal 0, status
    assert_includes command_line(out), "bin/minitest test/unit/cli_test.rb:40"
    refute_includes command_line(out), "ZR_PROGRAMS"
  end

  def test_a_program_runs_through_the_program_tests
    _, out = listed(PROGRAM)
    line = command_line(out)

    assert_includes line, "ZR_PROGRAMS=#{File.join(ROOT, PROGRAM)} "
    assert line.rstrip.end_with?("bin/minitest test/programs_test.rb"), line
    assert_includes out, "test/programs_test.rb: 1 program(s)\n    core/signal/sigvtalrm_does_nothing.rb\n"
  end

  def test_a_program_anywhere_is_a_test_named_by_its_path
    Dir.mktmpdir do |dir|
      path = File.join(dir, "try.rb")
      File.write(path, "p 1\n")
      File.write(File.join(dir, "helper.rb"), "")
      _, out = listed(path)

      assert_includes out, "test/programs_test.rb: 1 program(s)\n    #{path}\n"
      _, out = listed(dir)

      assert_includes out, "test/programs_test.rb: 0 program(s)", "a directory gives the programs with an expected output"
      _, out = listed("--live", dir)

      assert_includes out, "test/programs_test.rb: 2 program(s)", "a mode gives every program"
    end
  end

  def test_options_set_the_variables_that_the_run_reads
    _, out = listed("--jobs", "3", "--timeout", "30", "--no-build", "--no-cache", "--gc-stress", "--fail-fast",
                    "--target", "aarch64-linux-musl", "--verify", PROGRAM)
    line = command_line(out)

    %w[MT_CPU=3 ZR_TEST_TIMEOUT=30 ZR_TEST_SECONDS=30 ZR_TEST_HOST=1 ZR_TEST_FRESH=1 ZR_GC_STRESS=1
       ZR_TEST_FAIL_FAST=1 ZR_TARGET=aarch64-linux-musl ZR_EXPECTED=verify].each { |pair| assert_includes line, pair }
  end

  def test_minitest_options_pass_on_in_order
    _, out = listed("--seed", "42", "-n", "/help/", "-e", "slow", "test/unit/cli_test.rb")

    assert_includes command_line(out), "bin/minitest test/unit/cli_test.rb --seed 42 --include /help/ --exclude slow"
  end

  def test_suites_name_whole_directories
    _, out = listed("--suite", "unit,programs")
    line = command_line(out)

    assert_includes line, "bin/minitest test/unit test/programs_test.rb"
    refute_includes line, "ZR_PROGRAMS", "all of test/programs needs no list"
  end

  def test_no_path_runs_every_test
    _, out = listed

    assert command_line(out).rstrip.end_with?("bin/minitest"), command_line(out)
    assert_includes out, "every test file: test/**/*_test.rb"
  end

  def test_a_wrong_selection_is_refused
    assert_includes refused("--suite", "nope"), "no suite nope; the suites are unit, programs, ext"
    assert_includes refused("--record", "--live", PROGRAM), "give one of --record, --verify, --live"
    assert_includes refused("no/such/path"), "no file or directory no/such/path"
    assert_includes refused("#{PROGRAM}:3"), "a program is one test; give it with no line"
  end

  def test_failed_runs_the_failures_that_still_exist_and_never_every_test
    lines = ["test/unit/cli_test.rb:40", "program core/signal/sigvtalrm_does_nothing.rb", "program gone/away.rb"]
    stub_method(Zr::Test::LastFailures, :read, lines) do
      _, out = listed("--failed")
      line = command_line(out)

      assert_includes line, "ZR_PROGRAMS=#{File.join(ROOT, PROGRAM)} "
      assert_includes line, "test/unit/cli_test.rb:40 test/programs_test.rb"
    end
    stub_method(Zr::Test::LastFailures, :read, ["program gone/away.rb"]) do
      _, out = listed("--failed")

      assert_equal "none of the 1 failed test(s) is there any more\n", out
    end
  end

  private

  # `[status, stdout]` of `zr-dev test --list *argv`.
  def listed(*argv)
    status = nil
    out, = capture_io { status = Zr::Dev::Commands::Test.new("test").start(["--list", *argv]) }
    [status, out]
  end

  def command_line(out) = out.lines.find { |line| line.include?("bin/minitest") }.to_s

  # What `zr-dev test --list *argv` says as it stops with status 1.
  def refused(*argv)
    err = StringIO.new
    was = $stderr
    $stderr = err
    error = assert_raises(SystemExit) { Zr::Dev::Commands::Test.new("test").start(["--list", *argv]) }
    assert_equal 1, error.status
    err.string
  ensure
    $stderr = was
  end
end
