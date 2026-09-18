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
