# frozen_string_literal: true

require "test_helper"
require_relative "../support/built"

# The runtime a tier runs on: built by `rake build`, and only asked for
# by the tiers. What this pins is the asking -- which targets, what
# counts as built, and that a tier stops rather than builds.
class BuiltTest < Minitest::Test
  Built = Ze0::Test::Built

  def test_a_tier_stops_at_once_where_a_target_is_not_built
    standing_in(:built?, false) do
      error = assert_raises(SystemExit) { capture_io { Built.ready! } }
      refute_predicate error, :success?
    end
  end

  def test_a_tier_loads_what_is_built_and_builds_nothing
    loaded = []
    standing_in(:built?, true) do
      standing_in(:load, ->(target) { loaded << target }) { Built.ready! }
    end

    assert_equal [Ze0::Target.default], loaded
  end

  def test_the_unit_tier_asks_for_wasm_beside_this_host_where_wasmtime_is
    standing_in(:targets, [Ze0::Target.default, Ze0::Target::WASM32_WASI]) do
      loaded = []
      standing_in(:built?, true) do
        standing_in(:load, ->(target) { loaded << target }) { Built.ready!(wasm: true) }
      end

      assert_equal [Ze0::Target.default, Ze0::Target::WASM32_WASI], loaded
    end
  end

  def test_a_target_with_no_linker_is_marked_built_by_its_build
    assert_match(/rt-\h+\.o\z/, Built.mark(Ze0::Target.default))
    assert_match(/built-\h+\.ok\z/, Built.mark(Ze0::Target::WASM32_WASI))
  end

  private

  # `name` answering `answer` (called, where it is callable) while the
  # block runs. minitest 6 leaves `minitest/mock` out, and standing in
  # for one method is the whole of what it was wanted for.
  def standing_in(name, answer)
    was = Built.method(name)
    Built.define_singleton_method(name) { |*args, **kw| answer.respond_to?(:call) ? answer.call(*args, **kw) : answer }
    yield
  ensure
    Built.define_singleton_method(name, was)
  end
end
