# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev"
require_relative "../../tool/lib/zr/dev/suite"

# The check that the ratchets of ruby's test suites make
# (`Zr::Dev::Suite.problems`), on results made by hand.
class SuiteTest < Minitest::Test
  def problems(files, tags = {})
    Zr::Dev::Suite.problems({ "files" => files }, ->(file) { tags.fetch(file, {}) })
  end

  def ran(examples) = { "state" => "ran", "examples" => examples }

  def test_an_untagged_example_that_zr_fails_is_a_regression
    assert_equal ["a: x: zr fails it, ruby passes, and it has no tag"], problems("a" => ran("x" => %w[pass fail]))
    assert_equal ["a: x: zr never ran it, ruby passes, and it has no tag"], problems("a" => ran("x" => %w[pass missing]))
  end

  def test_a_tagged_example_is_no_regression_until_zr_passes_it
    assert_empty problems({ "a" => ran("x" => %w[pass fail], "y" => %w[pass missing]) }, "a" => { "x" => "fails", "y" => "hangs" })
    assert_equal ["a: x: stale tag, zr passes it now"], problems({ "a" => ran("x" => %w[pass pass]) }, "a" => { "x" => "fails" })
  end

  def test_an_example_that_ruby_fails_too_is_no_regression
    assert_empty problems("a" => ran("x" => %w[fail fail], "y" => %w[error missing]))
  end

  def test_a_file_that_does_not_build_needs_its_tag
    broken = { "a" => { "state" => "build", "examples" => {} } }

    assert_equal ["a: does not build, and has no fails(build) tag"], problems(broken)
    assert_empty problems(broken, "a" => { "" => "build" })
    assert_equal ["a: stale fails(build) tag: the file builds now"], problems({ "a" => ran({}) }, "a" => { "" => "build" })
  end

  def test_the_counts_of_an_area
    files = { "a" => ran("x" => %w[pass pass], "y" => %w[pass fail], "z" => %w[fail fail]),
              "b" => { "state" => "build", "examples" => {} } }

    assert_equal [2, 2, 1, 1, 0], Zr::Dev::Suite.counts("files" => files)
  end

  def test_an_area_builds_its_binaries_under_tmp
    area = Zr::Dev::Suite::Area.new(out: Zr::Dev.path("log/cruby-test"), root: "test", area: "ruby/enc", files: [],
                                    jobs: 1, keep: false, update: false, filtered: false)

    assert_equal Zr::Dev.path("tmp/cruby-test/work/ruby-enc"), area.work
  end

  # A run that stopped early hangs on the first example that it did not
  # reach. In a run that ended, a missing example is one that a guard left
  # out, so it fails.
  def test_a_missing_example_hangs_only_when_the_run_stopped_early
    area = Zr::Dev::Suite::Area.new(out: Zr::Dev.path("log/cruby-test"), root: "test", area: "ruby/enc", files: [],
                                    jobs: 1, keep: false, update: false, filtered: false)
    examples = { "x" => %w[pass missing], "y" => %w[pass missing], "z" => %w[pass fail] }

    assert_equal({ "x" => "hangs", "y" => "fails", "z" => "fails" }, area.tags_from(ran(examples), {}))
    assert_equal({ "x" => "fails", "y" => "fails", "z" => "fails" }, area.tags_from(ran(examples).merge("ended" => true), {}))
  end

  def test_capture_gives_each_whole_line_as_it_comes
    lines = []
    script = "$stdout.sync = true; print %(one\ntw); sleep 0.2; print %(o\nthree)"
    out, timed_out = Zr::Dev::Suite.capture({}, [RbConfig.ruby, "-e", script], Dir.pwd, 30, live: ->(line) { lines << line })

    assert_equal ["one\ntwo\nthree", false], [out, timed_out]
    assert_equal %w[one two], lines
  end
end
