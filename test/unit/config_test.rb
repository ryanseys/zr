# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/config"

# `Zr::Config` collects every `ZR_*` environment variable that steers a
# build in one place. Each test sets only the variables it cares about
# and restores `ENV` after, through `Config.with`.
class ConfigTest < Minitest::Test
  def test_current_memoizes_across_calls
    assert_same Zr::Config.current, Zr::Config.current
  end

  def test_with_yields_a_config_built_from_the_given_environment
    Zr::Config.with(ZR_LINKER: "cc") do |config|
      assert_equal "cc", config.linker
    end
  end

  def test_with_restores_the_environment_after_the_block
    ENV["ZR_LINKER"] = "ruby"

    Zr::Config.with(ZR_LINKER: "cc") { |config| assert_equal "cc", config.linker }

    assert_equal "ruby", ENV["ZR_LINKER"]
  ensure
    ENV.delete("ZR_LINKER")
  end

  def test_with_restores_an_unset_variable_to_unset
    ENV.delete("ZR_LINKER")

    Zr::Config.with(ZR_LINKER: "cc") { |_| }

    refute_operator ENV, :key?, "ZR_LINKER"
  end

  def test_linker_defaults_to_auto_when_unset
    Zr::Config.with(ZR_LINKER: nil) { |config| assert_equal "auto", config.linker }
  end

  def test_linker_raises_on_an_unknown_name
    error = assert_raises(ArgumentError) { Zr::Config.with(ZR_LINKER: "gold") { |_| } }

    assert_match(/ZR_LINKER=gold/, error.message)
  end

  def test_jobs_defaults_to_at_most_six
    Zr::Config.with(ZR_JOBS: nil) { |config| assert_operator config.jobs, :<=, 6 }
  end

  def test_jobs_reads_an_explicit_value
    Zr::Config.with(ZR_JOBS: "3") { |config| assert_equal 3, config.jobs }
  end

  def test_eval_walk_is_true_only_for_walk
    Zr::Config.with(ZR_EVAL: "walk") { |config| assert config.eval_walk? }
    Zr::Config.with(ZR_EVAL: nil) { |config| refute config.eval_walk? }
  end

  def test_timing_defaults_to_off
    Zr::Config.with(ZR_TIMING: nil) { |config| refute config.timing? }
  end

  def test_timing_is_on_for_any_value_but_zero
    Zr::Config.with(ZR_TIMING: "1") { |config| assert config.timing? }
    Zr::Config.with(ZR_TIMING: "0") { |config| refute config.timing? }
  end

  def test_verify_defaults_to_off
    Zr::Config.with(ZR_VERIFY: nil) { |config| refute config.verify? }
  end

  def test_wasm_names_defaults_to_off
    Zr::Config.with(ZR_WASM_NAMES: nil) { |config| refute config.wasm_names? }
  end

  def test_wasm_width_defaults_to_256
    Zr::Config.with(ZR_WASM_WIDTH: nil) { |config| assert_equal 256, config.wasm_width }
  end

  def test_wasm_width_reads_an_explicit_value
    Zr::Config.with(ZR_WASM_WIDTH: "128") { |config| assert_equal 128, config.wasm_width }
  end

  def test_tune_defaults_to_on
    Zr::Config.with(ZR_TUNE: nil) { |config| assert config.tune? }
  end

  def test_tune_is_off_for_zero
    Zr::Config.with(ZR_TUNE: "0") { |config| refute config.tune? }
  end

  def test_cache_defaults_to_nil
    Zr::Config.with(ZR_CACHE: nil) { |config| assert_nil config.cache }
  end

  def test_cache_reads_an_explicit_path
    Zr::Config.with(ZR_CACHE: "/tmp/zr-cache") { |config| assert_equal "/tmp/zr-cache", config.cache }
  end

  def test_host_ruby_defaults_to_ruby
    Zr::Config.with(ZR_HOST_RUBY: nil) { |config| assert_equal "ruby", config.host_ruby }
  end

  def test_host_ruby_reads_an_explicit_path
    Zr::Config.with(ZR_HOST_RUBY: "/opt/ruby/bin/ruby") { |config| assert_equal "/opt/ruby/bin/ruby", config.host_ruby }
  end

  def test_config_is_frozen
    Zr::Config.with(ZR_LINKER: "cc") { |config| assert_predicate config, :frozen? }
  end
end
