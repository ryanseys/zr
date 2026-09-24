# frozen_string_literal: true

require "test_helper"
require_relative "../support/built"

# The runtime that a tier runs on: which targets it needs, what counts
# as built, and that a tier builds only what is missing.
class BuiltTest < Minitest::Test
  Built = Zr::Test::Built

  # `ZR_BUILT=0` would make `ready!` skip everything that these tests check.
  def setup
    @built = ENV.delete("ZR_BUILT")
  end

  def teardown
    ENV["ZR_BUILT"] = @built if @built
  end

  def test_ready_builds_a_target_that_is_not_built_then_loads_it
    started = []
    loaded = []
    standing_in(:built?, ->(target) { started.include?(target) }) do
      standing_in(:start, ->(target, **) { started << target; fork { exit! 0 } }) do
        standing_in(:load, ->(target) { loaded << target }) { capture_io { Built.ready! } }
      end
    end

    assert_equal [Zr::Target.default], started
    assert_equal [Zr::Target.default], loaded
  end

  def test_build_says_a_built_target_is_up_to_date_and_builds_nothing
    standing_in(:built?, true) do
      standing_in(:start, ->(*) { flunk "started a build" }) do
        _, err = capture_io { Built.build([Zr::Target.default], say: $stderr) }
        assert_match(/zr runtime for #{Zr::Target.default.triple} is up to date \(cache: /, err)
      end
    end
  end

  def test_a_tier_loads_what_is_built_and_builds_nothing
    loaded = []
    standing_in(:built?, true) do
      standing_in(:load, ->(target) { loaded << target }) { capture_io { Built.ready! } }
    end

    assert_equal [Zr::Target.default], loaded
  end

  def test_the_unit_tier_asks_for_wasm_beside_this_host_where_wasmtime_is
    standing_in(:targets, [Zr::Target.default, Zr::Target::WASM32_WASI]) do
      loaded = []
      standing_in(:built?, true) do
        standing_in(:load, ->(target) { loaded << target }) { capture_io { Built.ready!(wasm: true) } }
      end

      assert_equal [Zr::Target.default, Zr::Target::WASM32_WASI], loaded
    end
  end

  # The mark is the last file that a build writes.
  def test_every_target_is_marked_built_by_its_build_under_its_digest
    assert_match(/built-\h+\.ok\z/, Built.mark(Zr::Target.default))
    assert_match(/built-\h+\.ok\z/, Built.mark(Zr::Target::WASM32_WASI))
    refute_equal Built.mark(Zr::Target.default), Built.mark(Zr::Target::WASM32_WASI)
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
