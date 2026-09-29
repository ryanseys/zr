# frozen_string_literal: true

require "test_helper"
require "zr/tune"

# `exe/zr` sets the collector limits at once, and turns YJIT on only at
# the first step of heavy work: a warm build of a small program is faster
# without YJIT's own compiling.
class TuneTest < Minitest::Test
  Tune = Zr::Tune

  def test_later_waits_for_heavy_work
    turned = 0
    stub_method(Tune, :yjit, -> { turned += 1 }) do
      with_env("RUBY_GC_MALLOC_LIMIT" => Tune::GC_ENV.fetch("RUBY_GC_MALLOC_LIMIT")) do
        Tune.later("exe/zr", [])
        assert_equal 0, turned, "a warm build does not turn YJIT on"
        Tune.heavy!
        assert_equal 1, turned
      end
    end
  ensure
    Tune.instance_variable_set(:@pending, false)
  end

  def test_heavy_work_with_nothing_pending_does_nothing
    Tune.instance_variable_set(:@pending, false)
    stub_method(Tune, :yjit, -> { flunk "turned YJIT on" }) { Tune.heavy! }
  end

  def test_zr_tune_0_leaves_nothing_pending
    Zr::Config.with(ZR_TUNE: "0") do
      stub_method(Tune, :yjit, -> { flunk "turned YJIT on" }) do
        Tune.later("exe/zr", [])
        Tune.heavy!
      end
    end
  ensure
    Tune.instance_variable_set(:@pending, false)
  end

  def test_the_program_does_not_see_the_limits_that_zr_set
    Tune.instance_variable_set(:@added, nil)
    with_env(Tune::ADDED => "1", "RUBY_GC_MALLOC_LIMIT" => "64000000") do
      Tune.limits(nil, [], {})
      refute ENV.key?(Tune::ADDED), "the mark is gone"
      assert_equal({ "RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil }, Tune.program_env)
    end
    Tune.instance_variable_set(:@added, nil)
    with_env(Tune::ADDED => nil, "RUBY_GC_MALLOC_LIMIT" => "5") do
      Tune.limits(nil, [], {})
      assert_empty Tune.program_env, "the user's own limits stay"
    end
  ensure
    Tune.instance_variable_set(:@added, nil)
  end
end
