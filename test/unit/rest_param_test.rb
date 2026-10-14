# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../../lib/zr/native/build"

# A def that only spreads its `*rest` and `**rest` binds empty ones to the
# one shared frozen Array and Hash (`zr_rest_of`, `zr_kw_rest_of`). A def
# that reads either, or whose locals something else can read, gathers new
# ones (`Hir::Escape.spread_only?`, `Params#shared_rest?`).
class RestParamTest < Minitest::Test
  PROGRAM = <<~RUBY
    def forward(*a, **k, &b) = g(*a, **k, &b)
    def bare_super(*a, **k) = super
    def literals(*a, **k) = [[*a], { **k }]
    def kept(*a, **k) = [a, k]
    def changed(*a, **k) = a << k
    def captured(*a, **k) = -> { g(*a, **k) }
    def bound(*a, **k) = binding.then { g(*a, **k) }
    def keyword_default(*a, x: a.size, **k) = g(*a, **k)
  RUBY

  BOTH = %w[zr_kw_rest_of zr_rest_of].freeze

  # The shared rests of each def. A keyword's default reads `a`, but the
  # def only spreads `k`.
  SHARED = {
    "forward" => BOTH, "bare_super" => BOTH, "literals" => BOTH,
    "kept" => [], "changed" => [], "captured" => [], "bound" => [],
    "keyword_default" => %w[zr_kw_rest_of]
  }.freeze

  def test_a_def_that_only_spreads_its_rests_shares_the_empty_ones
    assert_equal SHARED, rest_calls
  end

  private

  # The shared-rest kernel calls of each def, by the def's name.
  def rest_calls
    Zr::Program.build(PROGRAM, "rest.rb").functions.filter_map do |f|
      name = f.name[/\Azr_toplevel_def_\d+_(\w+)\z/, 1] or next
      [name, f.callees.map(&:symbol).grep(/\Azr_(kw_)?rest_of\z/).sort]
    end.to_h
  end
end
