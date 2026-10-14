# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# The counts that a call's arguments are checked against, which the
# lowering, the host machine and the eval walker read from one place
# (Hir::Params). `|a,|` has an implicit rest, which takes no argument.
class HirParamsTest < Minitest::Test
  # The Params of `required`, `optional` names, `rest`, `post` and
  # `keywords` (name => default).
  def params(required: [], optional: [], rest: nil, post: [], keywords: {})
    Zr::Hir::Params.new(required, optional.map { [it, nil] }, rest, post, keywords.to_a, nil, nil)
  end

  def test_a_trailing_comma_takes_one_argument
    trailing = params(required: %i[a], rest: :implicit)

    assert_equal [1, 1, false], [trailing.min_args, trailing.max_args, trailing.rest?]
  end

  def test_the_counts_of_each_shape
    assert_equal [1, 2, false], counts(params(required: %i[a], optional: %i[b]))
    assert_equal [2, nil, true], counts(params(required: %i[a], rest: :r, post: %i[z]))
    assert_equal [0, nil, true], counts(params(rest: :*))
    assert_equal [0, 0, false], counts(params)
  end

  def test_required_keywords_are_those_with_no_default
    one = Zr::Hir::Literal.new(1, 1)

    assert_equal %i[g k], params(keywords: { g: nil, h: one, k: nil }).required_keywords
  end

  private

  def counts(found) = [found.min_args, found.max_args, found.rest?]
end
