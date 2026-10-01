# frozen_string_literal: true

require "test_helper"
require "zr/gc_tuning"

# `exe/zr` waits for the first step of heavy work: a warm build of a small
# program is faster without YJIT's own compiling, and without a second
# start of ruby for the collector limits. Each test has a tuning of its own.
class GcTuningTest < Minitest::Test
  GcTuning = Zr::GcTuning

  def test_later_waits_for_heavy_work
    tuning = GcTuning.new
    turned = 0
    stub_method(tuning, :yjit, -> { turned += 1 }) do
      with_env("RUBY_GC_MALLOC_LIMIT" => GcTuning::GC_ENV.fetch("RUBY_GC_MALLOC_LIMIT")) do
        tuning.later("exe/zr", [])
        assert_equal 0, turned, "a warm build does not turn YJIT on"
        tuning.heavy!
        assert_equal 1, turned
      end
    end
  end

  # Without the limits, the first heavy step starts zr again with them,
  # and marks them as zr's.
  def test_heavy_work_starts_zr_again_with_the_limits
    tuning = GcTuning.new
    started = nil
    with_env("RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil, GcTuning::ADDED => nil) do
      stub_method(tuning, :exec, ->(*args) { started = args }) do
        stub_method(tuning, :yjit, -> {}) do
          tuning.later("exe/zr", %w[run a.rb], env: { "FOO" => "1" })
          assert_nil started, "a warm build does not start again"
          tuning.heavy!
        end
      end
    end
    env, ruby, script, *argv = started
    assert_equal({ "FOO" => "1", GcTuning::ADDED => "1" }, env)
    assert_equal [RbConfig.ruby, "exe/zr", %w[run a.rb]], [ruby, script, argv]
  end

  # A large program's lowering and an open build directory only turn YJIT
  # on: a start again would build the HIR twice, or leave the directory.
  def test_some_heavy_work_does_not_start_again
    tuning = GcTuning.new
    with_env("RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil) do
      stub_method(tuning, :exec, ->(*) { flunk "started again" }) do
        stub_method(tuning, :yjit, -> {}) do
          tuning.later("exe/zr", [])
          tuning.heavy!(restart: false)
          Zr::Paths.tmpdir("zr-tune-") { tuning.heavy! }
        end
      end
    end
  end

  def test_heavy_work_with_nothing_pending_does_nothing
    tuning = GcTuning.new
    stub_method(tuning, :yjit, -> { flunk "turned YJIT on" }) { tuning.heavy! }
  end

  def test_zr_tune_0_leaves_nothing_pending
    tuning = GcTuning.new
    Zr::Config.with(ZR_TUNE: "0") do
      stub_method(tuning, :yjit, -> { flunk "turned YJIT on" }) do
        tuning.later("exe/zr", [])
        tuning.heavy!
      end
    end
  end

  def test_the_program_does_not_see_the_limits_that_zr_set
    tuning = GcTuning.new
    with_env(GcTuning::ADDED => "1", "RUBY_GC_MALLOC_LIMIT" => "64000000") do
      tuning.limits(nil, [], {})
      refute ENV.key?(GcTuning::ADDED), "the mark is gone"
      assert_equal({ "RUBY_GC_MALLOC_LIMIT" => nil, "RUBY_GC_OLDMALLOC_LIMIT" => nil }, tuning.program_env)
    end
  end

  def test_the_program_keeps_the_limits_that_the_user_set
    tuning = GcTuning.new
    with_env(GcTuning::ADDED => nil, "RUBY_GC_MALLOC_LIMIT" => "5") do
      tuning.limits(nil, [], {})
      assert_empty tuning.program_env, "the user's own limits stay"
    end
  end
end
