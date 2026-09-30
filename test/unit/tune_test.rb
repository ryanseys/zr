# frozen_string_literal: true

require "test_helper"
require "zr/tune"

# `exe/zr` waits for the first step of heavy work: a warm build of a small
# program is faster without YJIT's own compiling, and without a second
# start of ruby for the collector limits.
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

  # Without the limits, the first heavy step starts zr again with them,
  # and marks them as zr's.
  def test_heavy_work_starts_zr_again_with_the_limits
    started = nil
    with_env("RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil, Tune::ADDED => nil) do
      stub_method(Tune, :exec, ->(*args) { started = args }) do
        stub_method(Tune, :yjit, -> {}) do
          Tune.later("exe/zr", %w[run a.rb], env: { "FOO" => "1" })
          assert_nil started, "a warm build does not start again"
          Tune.heavy!
        end
      end
    end
    env, ruby, script, *argv = started
    assert_equal({ "FOO" => "1", Tune::ADDED => "1" }, env)
    assert_equal [RbConfig.ruby, "exe/zr", %w[run a.rb]], [ruby, script, argv]
  ensure
    Tune.instance_variable_set(:@pending, false)
    Tune.instance_variable_set(:@restart, nil)
  end

  # A large program's lowering and an open build directory only turn YJIT
  # on: a start again would build the HIR twice, or leave the directory.
  def test_some_heavy_work_does_not_start_again
    with_env("RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil) do
      stub_method(Tune, :exec, ->(*) { flunk "started again" }) do
        stub_method(Tune, :yjit, -> {}) do
          Tune.later("exe/zr", [])
          Tune.heavy!(restart: false)
          Zr::Paths.tmpdir("zr-tune-") { Tune.heavy! }
        end
      end
    end
  ensure
    Tune.instance_variable_set(:@pending, false)
    Tune.instance_variable_set(:@restart, nil)
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
