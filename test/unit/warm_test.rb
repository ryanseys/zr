# frozen_string_literal: true

require "test_helper"
require_relative "../support/warm"

# The caches a tier builds before it forks.
#
# What this pins is the decision, not the build: whether the caches are
# asked for, and whether a cold one is built at all. The build itself is
# every other check in the tree, since none of them runs without it.
class WarmTest < Minitest::Test
  Warm = Ze0::Test::Warm

  def test_it_leaves_them_alone_when_it_is_told_to
    with_env("ZE0_WARM" => "0") do
      built = builds { assert_nil Warm.call(say: nil) }

      assert_empty built
    end
  end

  def test_a_cold_cache_is_built_when_it_may_be
    standing_in(:warm?, false) do
      built = builds { refute_nil Warm.call(cold: true, say: nil) }

      assert_equal [Ze0::Target.default], built
    end
  end

  # A narrow run of checks that build no program should not wait minutes
  # for caches it will not use.
  def test_a_cold_cache_is_left_cold_when_it_may_not_be
    standing_in(:warm?, false) do
      built = builds { assert_nil Warm.call(cold: false, say: nil) }

      assert_empty built
    end
  end

  def test_a_warm_cache_is_asked_for_either_way
    standing_in(:warm?, true) do
      built = builds do
        Warm.call(cold: false, say: nil)
        Warm.call(cold: true, say: nil)
      end

      assert_equal 2, built.size
    end
  end

  # A run of unit tests alone may leave a cold cache cold only when none
  # of them builds: the ones that do once had eight workers build one
  # runtime at the same time.
  def test_only_unit_tests_that_build_nothing_may_run_cold
    unit = File.join(ROOT, "test/unit")

    assert Warm.light?([File.join(unit, "passes_test.rb"), File.join(unit, "fork_pool_test.rb")])
    %w[programs_test wasm_test exe_test rt_test zr_test aarch64_test description_test].each do |name|
      refute Warm.light?([File.join(unit, "#{name}.rb")]), "#{name} builds, and would run cold"
    end
    refute Warm.light?([File.join(unit, "passes_test.rb"), File.join(ROOT, "test/spec/core/time")])
  end

  def test_the_unit_tier_warms_wasm_beside_this_host_where_wasmtime_is
    standing_in(:wasmtime?, true) do
      assert_equal [Ze0::Target.default, Ze0::Target::WASM32_WASI], Warm.targets(wasm: true)
      assert_equal [Ze0::Target.default], Warm.targets
    end
    standing_in(:wasmtime?, false) { assert_equal [Ze0::Target.default], Warm.targets(wasm: true) }
  end

  def test_a_target_with_no_linker_is_marked_warm_by_its_last_warm_up
    assert_match(/rt-\h+\.o\z/, Warm.mark(Ze0::Target.default))
    assert_match(/warm-\h+\.ok\z/, Warm.mark(Ze0::Target::WASM32_WASI))
  end

  private

  # The targets `Warm.build` was asked for while the block ran, with no
  # build made. minitest 6 leaves `minitest/mock` out, and standing in
  # for one method is the whole of what it was wanted for.
  def builds(&block)
    asked = []
    standing_in(:build, ->(target) { asked << target }, &block)
    asked
  end

  def standing_in(name, answer)
    was = Warm.method(name)
    Warm.define_singleton_method(name) { |*args| answer.respond_to?(:call) ? answer.call(*args) : answer }
    yield
  ensure
    Warm.define_singleton_method(name, was)
  end

  def with_env(pairs)
    was = pairs.transform_values { nil }.merge(ENV.slice(*pairs.keys))
    ENV.update(pairs)
    yield
  ensure
    was.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
