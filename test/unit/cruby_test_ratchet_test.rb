# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/cruby_test"

# CRuby's test-all under zr (`zr-dev cruby-test`): each test that ruby
# passes and zr does not has a tag in test/cruby/tags, and no tag is
# stale. The test reads the results of the last run of each directory in
# log/cruby-test/results; it never compiles. A directory with no results
# for this ruby is not checked.
class CRubyTestRatchetTest < Minitest::Test
  def test_each_directory_that_ran_matches_its_tags
    results = Zr::Dev::Suite.results(Zr::Dev::CRubyTest::OUT)
    skip "no test-all results for ruby #{Zr::RUBY}: run zr-dev cruby-test <dir>" if results.empty?

    problems = results.flat_map do |dir, data|
      Zr::Dev::Suite.problems(data, Zr::Dev::CRubyTest.method(:tags)).map { |line| "#{dir}: #{line}" }
    end
    assert_empty problems, "run zr-dev cruby-test <dir> --update-tags after a fix, and commit the tags"
  end

  # The runner's report of a run: the tests that ended, and the ones that
  # failed, with the first line of the message.
  def test_a_run_reads_as_its_tests
    out = <<~OUT
      [1/3] TestX#test_b = 0.00 s
      [2/3] TestX#test_a = 0.00 s
      [3/3] TestX#test_c

        1) Failure:
      TestX#test_a [/x/t_x.rb:3]:
      <1> expected but was

        2) Error:
      TestX#test_b:
      RuntimeError: boom
    OUT
    expected = { "TestX#test_b" => ["error", "RuntimeError: boom"], "TestX#test_a" => ["fail", "<1> expected but was"] }

    assert_equal({ examples: expected, load: nil, ended: false }, Zr::Dev::CRubyTest.read(out.dup))
  end
end
