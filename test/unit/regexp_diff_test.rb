# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/regexp_diff"

# The Ruby Onigmo held to ruby's own engine over a fixed sample of
# harvested and fuzzed cases (test/unit/regexp_diff_sample.jsonl): the
# compile error, the
# warnings quiet and verbose, the position and every capture's byte
# offsets, all as ruby answers them.
class RegexpDiffTest < Minitest::Test
  SAMPLE = File.join(__dir__, "regexp_diff_sample.jsonl")

  def test_the_sample_matches_ruby
    cases = Ze0::Harness::RegexpDiff.read_jsonl(SAMPLE)
    runner = Ze0::Harness::RegexpDiff::Runner.new
    Regexp.timeout = 2.0
    cases.each { |kase| runner.run(kase) }

    assert_operator cases.size, :>=, 2000
    assert_empty runner.divergences.first(20).map(&:to_s), "#{runner.divergences.size} of #{cases.size} cases part from ruby"
    assert_empty runner.slow.map { |kase, _| kase.label }
  ensure
    Regexp.timeout = nil
  end
end
