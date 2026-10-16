# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/gem_tests"

# The bundled gems' own tests under zr (`zr-dev gem-tests`): each test
# that ruby passes and zr does not has a tag in test/gem_tests/tags, and
# no tag is stale. The test reads the results of the last run of each gem
# in log/gem-tests/results; it never runs a gem. A gem with no results
# for this ruby is not checked.
class GemTestsRatchetTest < Minitest::Test
  def test_each_gem_that_ran_matches_its_tags
    results = Zr::Dev::Suite.results(Zr::Dev::Commands::GemTests::OUT)
    skip "no gem test results for ruby #{Zr::RUBY}: run zr-dev gem-tests <gem>" if results.empty?

    problems = results.flat_map do |gem, data|
      Zr::Dev::Suite.problems(data, Zr::Dev::Commands::GemTests.method(:tags)).map { |line| "#{gem}: #{line}" }
    end
    assert_empty problems, "run zr-dev gem-tests <gem> --update-tags after a fix, and commit the tags"
  end
end
