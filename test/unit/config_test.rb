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

  def test_link_args_split_as_a_shell_splits_them
    Zr::Config.with(ZR_LINK_ARGS: %(a.o -Wl,-x "-framework Foo")) do |config|
      assert_equal ["a.o", "-Wl,-x", "-framework Foo"], config.link
    end
    Zr::Config.with(ZR_LINK_ARGS: nil) { |config| assert_empty config.link }
  end

  def test_linker_defaults_to_auto_when_unset
    Zr::Config.with(ZR_LINKER: nil) { |config| assert_equal "auto", config.linker }
  end

  def test_linker_raises_on_an_unknown_name
    error = assert_raises(Zr::Config::Invalid) { Zr::Config.with(ZR_LINKER: "gold") { |_| } }

    assert_equal 'ZR_LINKER is "gold". Set it to auto, ruby or cc, for example ZR_LINKER=auto.', error.message
  end

  # A value that zr cannot use names the variable and a value that works.
  def test_a_bad_value_names_the_variable_and_a_good_value
    {
      { ZR_JOBS: "abc" } => 'ZR_JOBS is "abc". Set it to a whole number of 1 or more, for example ZR_JOBS=4.',
      { ZR_JOBS: "0" } => 'ZR_JOBS is "0". Set it to a whole number of 1 or more, for example ZR_JOBS=4.',
      { ZR_CACHE_MAX_GB: "lots" } => 'ZR_CACHE_MAX_GB is "lots". Set it to a number of 0 or more, for example ZR_CACHE_MAX_GB=10.',
      { ZR_WASM_WIDTH: "1.5" } => 'ZR_WASM_WIDTH is "1.5". Set it to a whole number of 1 or more, for example ZR_WASM_WIDTH=256.',
      { ZR_CODE_CACHE: "yes" } => 'ZR_CODE_CACHE is "yes". Set it to 1, 0 or verify, for example ZR_CODE_CACHE=1.'
    }.each do |env, message|
      error = assert_raises(Zr::Config::Invalid, env.inspect) { Zr::Config.with(**env) { |_| } }
      assert_equal message, error.message
    end
    Zr::Config.with(ZR_CACHE_MAX_GB: "0.5", ZR_JOBS: "") do |config|
      assert_in_delta 0.5, config.cache_max_gb
      refute_predicate config, :jobs_given?
    end
  end

  def test_jobs_defaults_to_at_most_six
    Zr::Config.with(ZR_JOBS: nil) { |config| assert_operator config.jobs, :<=, 6 }
  end

  def test_jobs_reads_an_explicit_value
    Zr::Config.with(ZR_JOBS: "3") { |config| assert_equal 3, config.jobs }
  end

  def test_eval_walk_is_true_only_for_walk
    Zr::Config.with(ZR_EVAL: "walk") { |config| assert_predicate config, :eval_walk? }
    Zr::Config.with(ZR_EVAL: nil) { |config| refute_predicate config, :eval_walk? }
  end

  def test_timing_defaults_to_off
    Zr::Config.with(ZR_TIMING: nil) { |config| refute_predicate config, :timing? }
  end

  def test_timing_is_on_for_any_value_but_zero
    Zr::Config.with(ZR_TIMING: "1") { |config| assert_predicate config, :timing? }
    Zr::Config.with(ZR_TIMING: "0") { |config| refute_predicate config, :timing? }
  end

  def test_verify_defaults_to_off
    Zr::Config.with(ZR_VERIFY: nil) { |config| refute_predicate config, :verify? }
  end

  def test_wasm_names_defaults_to_off
    Zr::Config.with(ZR_WASM_NAMES: nil) { |config| refute_predicate config, :wasm_names? }
  end

  def test_wasm_width_defaults_to_256
    Zr::Config.with(ZR_WASM_WIDTH: nil) { |config| assert_equal 256, config.wasm_width }
  end

  def test_wasm_width_reads_an_explicit_value
    Zr::Config.with(ZR_WASM_WIDTH: "128") { |config| assert_equal 128, config.wasm_width }
  end

  def test_tune_defaults_to_on
    Zr::Config.with(ZR_TUNE: nil) { |config| assert_predicate config, :tune? }
  end

  def test_tune_is_off_for_zero
    Zr::Config.with(ZR_TUNE: "0") { |config| refute_predicate config, :tune? }
  end

  def test_cache_defaults_to_nil
    Zr::Config.with(ZR_CACHE: nil) { |config| assert_nil config.cache }
  end

  def test_cache_reads_an_explicit_path
    Zr::Config.with(ZR_CACHE: "/tmp/zr-cache") { |config| assert_equal "/tmp/zr-cache", config.cache }
  end

  def test_config_is_frozen
    Zr::Config.with(ZR_LINKER: "cc") { |config| assert_predicate config, :frozen? }
  end

  # Only this class reads a `ZR_*` variable, so a build sees one set of
  # settings and a test can change them with `Config.with`.
  READERS = %w[lib/zr/config.rb].freeze

  def test_only_config_reads_a_zr_variable
    readers = (Dir[File.join(ROOT, "lib/**/*.rb")] - Dir[File.join(ROOT, "lib/zr/runtime/**/*.rb")]).select do |path|
      File.read(path).match?(/ENV(\[|\.fetch\(|\.key\?\()"ZR_|flag\?\("ZR_/)
    end

    assert_equal READERS, readers.map { |path| path.delete_prefix("#{ROOT}/") }.sort
  end
end
