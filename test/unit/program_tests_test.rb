# frozen_string_literal: true

require "test_helper"
require_relative "../support/programs"

# Tests the program tests' own parts (test/support/program_case.rb and
# programs.rb) without a build: how a test reads the files beside its
# program, how a result is judged, and how a difference is shown.
class ProgramTestsTest < Minitest::Test
  Case = Zr::Test::Case
  Programs = Zr::Test::Programs
  Selection = Zr::Test::ProgramSelection

  def with_test(files)
    Dir.mktmpdir("zr-program-tests-") do |root|
      files.each do |name, bytes|
        path = File.join(root, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
      end
      yield root, Case.new(root, "area/foo.rb")
    end
  end

  def test_a_test_reads_the_files_beside_its_program
    files = { "area/foo.rb" => "p 1\n", "area/foo.rb.expected" => "1\n", "area/foo.rb.err.expected" => "e\n",
              "area/foo.rb.args" => "a b\n", "area/foo.rb.stdin" => "in", "area/foo.rb.status" => "signal 15\n",
              "area/foo.rb.env" => "X=1\n# a comment\nY=a=b\n", "area/foo.rb.needs" => "libssl\nmacos\n",
              "area/foo.rb.ruby" => "-W:no-experimental\n", "area/foo.rb.limits" => "build_mb=4096\n",
              "area/foo.rb.linux.expected" => "2\n", "area/foo.rb.files/data.txt" => "d" }
    with_test(files) do |_, test|
      assert_equal "1\n", test.stdout("macos")
      assert_equal "2\n", test.stdout("linux")
      assert_equal "e\n", test.stderr
      assert_equal %w[a b], test.args
      assert_equal "in", test.stdin
      assert_equal [nil, 15], test.status
      assert_equal({ "X" => "1", "Y" => "a=b" }, test.env)
      assert_equal %w[libssl macos], test.needs
      assert_equal %w[-W:no-experimental], test.ruby_options
      assert_equal({ build_mb: 4096 }, test.limits)
      assert test.files.end_with?("area/foo.rb.files")
    end
  end

  def test_a_test_with_only_its_output_has_the_defaults
    with_test("area/foo.rb" => "p 1\n", "area/foo.rb.expected" => "1\n") do |_, test|
      assert_equal "".b, test.stderr
      assert_equal [0, nil], test.status
      assert_empty test.args
      assert_nil test.stdin
      assert_empty test.env
      assert_nil test.files
    end
  end

  def test_only_a_program_with_an_expected_output_is_a_test
    files = { "area/foo.rb" => "", "area/foo.rb.expected" => "", "area/helper.rb" => "",
              "area/foo.rb.files/lib/x.rb" => "", "area/foo.rb.files/lib/x.rb.expected" => "" }
    with_test(files) do |root, _|
      assert_equal ["area/foo.rb"], Case.under(root, root).map(&:rel)
    end
  end

  def test_a_run_directory_holds_the_program_and_its_files
    with_test("area/foo.rb" => "p 1\n", "area/foo.rb.expected" => "", "area/foo.rb.files/data/x.txt" => "x") do |_, test|
      Zr::Test::ProgramRun.within(test) do |run, rb|
        assert_equal File.join(run, "area/foo.rb"), rb
        assert_equal "x", File.read(File.join(run, "data/x.txt"))
      end
    end
  end

  # A kept binary's key holds each file beside the program by its bytes,
  # a link by its target, and the gems that the program loads.
  def test_a_tests_parts_are_its_files_links_and_gems
    files = { "area/foo.rb" => "", "area/foo.rb.gems" => "csv 3.3.6\n", "area/foo.rb.files/lib/x.rb" => "x" }
    with_test(files) do |root, test|
      File.symlink("lib/x.rb", File.join(root, "area/foo.rb.files/link.rb"))
      assert_equal [["lib/x.rb", "x"], ["link.rb", "-> lib/x.rb"]], test.fixture_parts
      assert_equal [[".gems", "csv 3.3.6\n"]], test.sidecar_parts
    end
    with_test("area/foo.rb" => "") do |_, test|
      assert_empty test.fixture_parts
      assert_empty test.sidecar_parts
    end
  end

  # A link inside the files stays a link, and a files directory that is
  # itself a link (to a shared fixture) gives the fixture's contents.
  def test_a_link_in_the_files_stays_a_link
    with_test("area/foo.rb" => "", "area/foo.rb.expected" => "", "shared/data/x.txt" => "x") do |root, test|
      File.symlink("../shared", File.join(root, "area/foo.rb.files"))
      File.symlink("data/x.txt", File.join(root, "shared/link.txt"))
      Zr::Test::ProgramRun.within(test) do |run, _|
        assert_equal "data/x.txt", File.readlink(File.join(run, "link.txt"))
        assert_equal "x", File.read(File.join(run, "link.txt"))
        refute File.symlink?(File.join(run, "data"))
      end
    end
  end

  def test_an_answer_apart_from_another_names_its_first_different_line
    want = Zr::Harness::Answer.new("1\n2\n", "", 0, nil)

    assert_equal %(stdout: want "2", got "3"), want.apart_from(Zr::Harness::Answer.new("1\n3\n", "", 0, nil))
    assert_equal %(stdout: want 2 line(s), got 1 -- "2"\n           exit 0 vs exit 1), want.apart_from(Zr::Harness::Answer.new("1\n", "", 1, nil))
  end

  def test_the_diff_of_two_answers_names_each_part_that_differs
    want = Zr::Harness::Answer.new("1\n", "", 0, nil)
    got = Zr::Harness::Answer.new("2\n", "", 1, nil)
    diff = want.diff(got)

    assert_includes diff, "--- expected stdout"
    assert_includes diff, "-1\n+2\n"
    refute_includes diff, "stderr"
    assert_includes diff, "status: expected exit 0, actual exit 1"
  end

  def test_a_baselined_failure_skips_and_a_baselined_pass_fails
    programs = Programs.new(allowed: { "area/foo.rb" => "known" })
    test = Case.new("/nowhere", "area/foo.rb")

    assert_equal :skip, programs.baselined(test, :fail, "diff").first
    assert_equal :skip, programs.baselined(test, :error, "refused").first
    kind, why = programs.baselined(test, :pass, nil)
    assert_equal :fail, kind
    assert_includes why, "this now passes"
  end

  def test_a_test_that_needs_another_platform_skips
    with_test("area/foo.rb" => "", "area/foo.rb.expected" => "", "area/foo.rb.needs" => "wasi\n") do |_, test|
      programs = Programs.new(allowed: {})

      assert_equal "runs only on wasi", programs.unmet(test)
    end
  end

  def test_zr_programs_picks_the_tests_below_its_paths
    picked = Selection.cases("core/gc, lang/blocks").map(&:rel)

    refute_empty picked
    assert(picked.all? { |rel| rel.start_with?("core/gc/", "lang/blocks/") })
    assert_raises(ArgumentError) { Selection.cases("no/such/area") }
  end

  def test_zr_programs_takes_a_program_or_a_directory_anywhere
    with_test("area/foo.rb" => "p 1\n", "area/foo.rb.expected" => "1\n", "area/bare.rb" => "p 2\n") do |root, _|
      named = Selection.cases(File.join(root, "area/bare.rb"), mode: nil)

      assert_equal [[File.join(root, "area"), "bare.rb"]], named.map { [_1.root, _1.rel] }, "a named program is a test, in its own directory"
      assert_equal ["foo.rb"], Selection.cases(File.join(root, "area"), mode: nil).map(&:rel), "a directory gives the programs with an output"
      assert_equal %w[bare.rb foo.rb], Selection.cases(File.join(root, "area"), mode: :live).map(&:rel), "a mode gives every program"
      assert_equal ["foo.rb"], Selection.cases("area", mode: nil, base: root).map(&:rel), "below the current directory"
    end
  end

  def test_a_test_is_named_below_test_programs_or_by_its_path
    inside = Case.new(Selection::ROOT, "core/gc/x.rb")
    outside = Case.new("/elsewhere", "try.rb")

    assert_equal "core/gc/x.rb", Selection.label(inside)
    assert_equal "elsewhere/try.rb", Selection.label(outside, base: "/")
    assert_equal "/elsewhere/try.rb", Selection.label(outside, base: Selection::ROOT), "a path above the current directory is full"
  end

  def test_zr_expected_names_one_of_three_modes
    with_env("ZR_EXPECTED" => "live") { assert_equal :live, Selection.mode }
    with_env("ZR_EXPECTED" => nil) { assert_nil Selection.mode }
    with_env("ZR_EXPECTED" => "bless") { assert_raises(ArgumentError) { Selection.mode } }
  end

  def test_the_expected_answer_comes_from_the_files_or_ruby_now
    with_test("area/foo.rb" => "p 1\n", "area/foo.rb.expected" => "1\n", "area/bare.rb" => "p 2\n") do |root, test|
      programs = Programs.new(allowed: {})
      bare = Case.new(root, "area/bare.rb")
      live = Zr::Harness::Answer.new("from ruby\n", "", 0, nil)
      stub_method(Zr::Test::ProgramRun, :ruby, ->(*, **) { live }) do
        assert_equal "1\n", programs.expected(test, nil).stdout, "the files"
        assert_equal live, programs.expected(bare, nil), "no files: ruby now"
        assert_equal live, programs.expected(test, :live), "live reads no file"
        kind, why = programs.expected(bare, :verify)

        assert_equal :error, kind
        assert_includes why, "no expected output beside it"
      end
    end
  end

  def test_a_baseline_names_only_programs_below_test_programs
    programs = Programs.new(allowed: { "area/foo.rb" => "known" })

    assert_equal "known", programs.baseline(Case.new(Selection::ROOT, "area/foo.rb"))
    assert_nil programs.baseline(Case.new("/elsewhere", "area/foo.rb"))
  end

  def test_the_failure_list_drops_passes_and_keeps_what_did_not_run
    require_relative "../support/last_failures"
    Dir.mktmpdir("zr-failures-") do |dir|
      path = File.join(dir, "failed.txt")
      File.write(path, "test/unit/a_test.rb:3\ntest/unit/b_test.rb:5\n")
      reporter = Zr::Test::LastFailures::Reporter.new(path)
      reporter.record(result("AT", "test_a", ["test/unit/a_test.rb", 3]))
      reporter.record(result("ProgramsTest", "test_core/x.rb", ["test/programs_test.rb", 80], failed: true))
      reporter.record(result("CT", "test_c", ["test/unit/c_test.rb", 7], skipped: true))
      reporter.report

      assert_equal ["test/unit/b_test.rb:5", "program core/x.rb"], Zr::Test::LastFailures.read(path)
    end
  end

  private

  def result(klass, name, location, failed: false, skipped: false)
    result = Minitest::Result.new(name)
    result.klass = klass
    result.source_location = location
    result.failures << Minitest::Assertion.new("no") if failed
    result.failures << Minitest::Skip.new("later") if skipped
    result
  end
end
