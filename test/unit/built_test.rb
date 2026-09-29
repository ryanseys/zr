# frozen_string_literal: true

require "test_helper"
require_relative "../support/built"

# Tests the runtime build that a tier uses: which targets a tier needs,
# when a target is built, and that a tier builds only missing targets.
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
    stub_method(Built, :built?, ->(target, **) { started.include?(target) }) do
      stub_method(Built, :start, ->(target, **) { started << target; fork { exit! 0 } }) do
        stub_method(Built, :load, ->(target) { loaded << target }) { capture_io { Built.ready! } }
      end
    end

    assert_equal [Zr::Target.default], started
    assert_equal [Zr::Target.default], loaded
  end

  def test_build_reports_up_to_date_target_and_builds_nothing
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

  def test_ready_with_wasm_loads_host_and_wasm_targets
    stub_method(Built, :targets, [Zr::Target.default, Zr::Target::WASM32_WASI]) do
      loaded = []
      stub_method(Built, :built?, true) do
        stub_method(Built, :load, ->(target) { loaded << target }) { capture_io { Built.ready!(wasm: true) } }
      end

      assert_equal [Zr::Target.default, Zr::Target::WASM32_WASI], loaded
    end
  end

  # The mark is the last file that a build writes.
  def test_build_mark_path_contains_target_digest
    assert_match(/built-\h+\.ok\z/, Built.mark(Zr::Target.default))
    assert_match(/built-\h+\.ok\z/, Built.mark(Zr::Target::WASM32_WASI))
    refute_equal Built.mark(Zr::Target.default), Built.mark(Zr::Target::WASM32_WASI)
  end

  def test_a_run_needs_eval_support_only_when_a_program_evals
    spec = File.expand_path("../spec", __dir__)
    assert Built.evals?(nil), "an unknown run"
    assert Built.evals?([__FILE__]), "a unit test"
    refute Built.evals?(["#{spec}/core/comparable/comparison_test.rb"]), "a spec with no eval"
    assert Built.evals?(["#{spec}/core/comparable/comparison_test.rb", "#{spec}/lang/eval/eval_test.rb"]), "a spec that evals"
  end

  def test_a_build_with_eval_support_serves_a_run_without
    target = Zr::Target.default
    full = Built.mark(target, evals: true)
    plain = Built.mark(target, evals: false)
    stub_method(File, :exist?, ->(path) { path == full }) do
      assert Built.built?(target, evals: false)
      assert Built.built?(target, evals: true)
    end
    stub_method(File, :exist?, ->(path) { path == plain }) do
      assert Built.built?(target, evals: false)
      refute Built.built?(target, evals: true)
    end
  end
end
