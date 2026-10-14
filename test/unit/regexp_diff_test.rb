# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/regexp_diff"

# Checks the Ruby Onigmo against ruby's own engine over a fixed sample of
# harvested and fuzzed cases (test/fixtures/regexp_diff_sample.jsonl): the
# compile error, the warnings (quiet and verbose), the position, and the
# byte offsets of each capture, all as ruby returns them.
class RegexpDiffTest < Minitest::Test
  SAMPLE = File.join(__dir__, "../fixtures/regexp_diff_sample.jsonl")

  def test_the_sample_matches_ruby
    cases = Zr::Harness::RegexpDiff.read_jsonl(SAMPLE)
    runner = Zr::Harness::RegexpDiff::Runner.new
    Regexp.timeout = 2.0
    cases.each { |kase| runner.run(kase) }

    assert_operator cases.size, :>=, 2000
    assert_empty runner.divergences.first(20).map(&:to_s), "#{runner.divergences.size} of #{cases.size} cases part from ruby"
    assert_empty runner.slow.map { |kase, _| kase.label }
  ensure
    Regexp.timeout = nil
  end
end
