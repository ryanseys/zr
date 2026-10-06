# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/rubyspec"

# ruby/spec under zr (`zr-dev rubyspec`): each example that ruby passes
# and zr does not has a tag in test/rubyspec/tags, and no tag is stale.
# The test reads the results of the last run of each area in
# log/rubyspec/results; it never compiles. An area with no results for
# this ruby is not checked.
class RubySpecRatchetTest < Minitest::Test
  def test_each_area_that_ran_matches_its_tags
    results = Zr::Dev::Suite.results(Zr::Dev::RubySpec::OUT)
    skip "no ruby/spec results for ruby #{Zr::RUBY}: run zr-dev rubyspec <area>" if results.empty?

    problems = results.flat_map do |area, data|
      Zr::Dev::Suite.problems(data, Zr::Dev::RubySpec.method(:tags)).map { |line| "#{area}: #{line}" }
    end
    assert_empty problems, "run zr-dev rubyspec <area> --update-tags after a fix, and commit the tags"
  end

  # A tag that gives a reason (`fails(why):`) is a `fails` tag, and a
  # rewrite of the tags keeps its reason.
  def test_a_tag_with_a_reason_fails_and_keeps_the_reason
    rel = "library/mkmf/mkmf_spec.rb"
    name = "mkmf can be required with --enable-frozen-string-literal"

    assert_equal({ name => "fails" }, Zr::Dev::RubySpec.tags(rel))
    assert_match(/\Azr refuses mkmf/, Zr::Dev::RubySpec.reasons(rel)[name])
  end

  # mspec reads a spec file's tags from the path that `tags_path` gives.
  def test_the_tags_of_a_spec_file_are_where_mspec_looks
    assert_equal File.join(Zr::Dev::RubySpec::TAGS, "core/array/pop_tags.txt"), Zr::Dev::RubySpec.tags_path("core/array/pop_spec.rb")
  end
end
