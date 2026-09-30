# frozen_string_literal: true

require "test_helper"
require_relative "../support/programs"

# Tests the program tests' own parts (test/support/program_case.rb and
# programs.rb) without a build: how a test reads the files beside its
# program, how a result is judged, and how a difference is shown.
class ProgramTestsTest < Minitest::Test
  Case = Zr::Test::Case
  Programs = Zr::Test::Programs

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

  def test_the_diff_marks_each_line
    lines = Programs::Diff.lines(%W[a\n b\n c\n], %W[a\n x\n c\n])

    assert_equal [" a\n", "-b\n", "+x\n", " c\n"], lines
  end

  def test_the_diff_of_two_answers_names_each_part_that_differs
    want = Zr::Harness::Answer.new("1\n", "", 0, nil)
    got = Zr::Harness::Answer.new("2\n", "", 1, nil)
    diff = Programs::Diff.of(want, got)

    assert_includes diff, "--- expected stdout"
    assert_includes diff, "-1\n+2\n"
    refute_includes diff, "stderr"
    assert_includes diff, "status: expected exit 0, actual exit 1"
  end

  def test_a_baselined_failure_skips_and_a_baselined_pass_fails
    programs = Programs.new([], Zr::Target.default, { "area/foo.rb" => "known" }, StringIO.new)
    test = Case.new("/nowhere", "area/foo.rb")

    assert_equal :skip, programs.baselined(test, :fail, "diff").first
    assert_equal :skip, programs.baselined(test, :error, "refused").first
    kind, why = programs.baselined(test, :pass, nil)
    assert_equal :fail, kind
    assert_includes why, "this now passes"
  end

  def test_a_test_that_needs_another_platform_skips
    with_test("area/foo.rb" => "", "area/foo.rb.expected" => "", "area/foo.rb.needs" => "wasi\n") do |_, test|
      programs = Programs.new([], Zr::Target.default, {}, StringIO.new)

      assert_equal "runs only on wasi", programs.unmet(test)
    end
  end
end
