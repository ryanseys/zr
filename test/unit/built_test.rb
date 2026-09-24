# frozen_string_literal: true

require "test_helper"
require_relative "../support/built"

# The runtime that a tier runs on: which targets it needs, what counts
# as built, and that a tier builds only what is missing.
class BuiltTest < Minitest::Test
  Built = Zr::Test::Built

  # `ZR_TEST_BUILT=0` would make `ready!` skip everything that these tests check.
  def setup
    @built = ENV.delete("ZR_TEST_BUILT")
  end

  def teardown
    ENV["ZR_TEST_BUILT"] = @built if @built
  end

  def test_ready_builds_a_target_that_is_not_built_then_loads_it
    started = []
    loaded = []
    stub_method(Built, :built?, ->(target) { started.include?(target) }) do
      stub_method(Built, :start, ->(target, **) { started << target; fork { exit! 0 } }) do
        stub_method(Built, :load, ->(target) { loaded << target }) { capture_io { Built.ready! } }
      end
    end

    assert_equal [Zr::Target.default], started
    assert_equal [Zr::Target.default], loaded
  end

  def test_build_says_a_built_target_is_up_to_date_and_builds_nothing
    stub_method(Built, :built?, true) do
      stub_method(Built, :start, ->(*) { flunk "started a build" }) do
        _, err = capture_io { Built.build([Zr::Target.default], say: $stderr) }
        assert_match(/zr runtime for #{Zr::Target.default.triple} is up to date \(cache: /, err)
      end
    end
  end

  def test_a_tier_loads_what_is_built_and_builds_nothing
    loaded = []
    stub_method(Built, :built?, true) do
      stub_method(Built, :load, ->(target) { loaded << target }) { capture_io { Built.ready! } }
    end

    assert_equal [Zr::Target.default], loaded
  end

  def test_the_unit_tier_asks_for_wasm_beside_this_host_where_wasmtime_is
    stub_method(Built, :targets, [Zr::Target.default, Zr::Target::WASM32_WASI]) do
      loaded = []
      stub_method(Built, :built?, true) do
        stub_method(Built, :load, ->(target) { loaded << target }) { capture_io { Built.ready!(wasm: true) } }
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
end
