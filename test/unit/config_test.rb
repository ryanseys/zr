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

  # Each word is a bundle's path, then the objects that hold its code;
  # both become absolute.
  def test_ext_objects_map_each_bundle_to_its_objects
    Zr::Config.with(ZR_EXT_OBJECTS: "/x/a.bundle=/y/a.o,/y/b.o /x/c.bundle=/y/c.o") do |config|
      assert_equal({ "/x/a.bundle" => ["/y/a.o", "/y/b.o"], "/x/c.bundle" => ["/y/c.o"] }, config.ext_objects)
    end
    Zr::Config.with(ZR_EXT_OBJECTS: nil) { |config| assert_empty config.ext_objects }
    Zr::Config.with(ZR_EXT_OBJECTS: "/x/a.bundle") { |config| assert_equal({ "/x/a.bundle" => [] }, config.ext_objects) }
    error = assert_raises(Zr::Config::Invalid) { Zr::Config.with(ZR_EXT_OBJECTS: "/x/a.bundle=") { |_| } }
    assert_equal 'ZR_EXT_OBJECTS has "/x/a.bundle=". Give each extension as BUNDLE=OBJECT[,OBJECT...] or a BUNDLE alone, ' \
                 "for example ZR_EXT_OBJECTS=lib/hello.bundle=hello.o.", error.message
  end

  # Each word is a gem, or a gem and its version, split at commas and
  # spaces.
  def test_native_ext_names_gems_and_their_versions
    Zr::Config.with(ZR_NATIVE_EXT: "msgpack, nokogiri=1.19.4 json") do |config|
      assert_equal({ "msgpack" => nil, "nokogiri" => "1.19.4", "json" => nil }, config.native_ext)
    end
    Zr::Config.with(ZR_NATIVE_EXT: nil) { |config| assert_empty config.native_ext }
    error = assert_raises(Zr::Config::Invalid) { Zr::Config.with(ZR_NATIVE_EXT: "msgpack=") { |_| } }
    assert_equal 'ZR_NATIVE_EXT has "msgpack=". Give each gem as NAME or NAME=VERSION, for example ZR_NATIVE_EXT=msgpack.',
                 error.message
  end

  # Each word is a gem and one argument for its extconf.rb; a gem's
  # arguments keep their order, and an argument may hold `=`.
  def test_ext_config_gives_each_gem_its_extconf_arguments
    Zr::Config.with(ZR_EXT_CONFIG: "nokogiri=--use-system-libraries tiny=--with-tiny-dir=/opt/tiny nokogiri='--with-xml2-dir=/a b'") do |config|
      assert_equal({ "nokogiri" => ["--use-system-libraries", "--with-xml2-dir=/a b"], "tiny" => ["--with-tiny-dir=/opt/tiny"] },
                   config.ext_config)
    end
    Zr::Config.with(ZR_EXT_CONFIG: nil) { |config| assert_empty config.ext_config }
    %w[nokogiri nokogiri= =--x].each do |word|
      error = assert_raises(Zr::Config::Invalid) { Zr::Config.with(ZR_EXT_CONFIG: word) { |_| } }
      assert_equal "ZR_EXT_CONFIG has #{word.inspect}. Give each argument as GEM=ARG, for example ZR_EXT_CONFIG=nokogiri=--use-system-libraries.",
                   error.message
    end
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

  # Each setting's flag wins over its variable, and gives the same value.
  def test_a_flag_wins_over_the_variable_for_each_setting
    cases = {
      "ZR_LINKER" => [%w[--linker cc], :linker, "cc"],
      "ZR_JOBS" => [%w[-j3], :jobs, 3],
      "ZR_EVAL" => [%w[--eval-mode=walk], :eval_walk?, true],
      "ZR_TIMING" => [%w[--timing], :timing?, true],
      "ZR_VERIFY" => [%w[--verify], :verify?, true],
      "ZR_KERNEL_CHECKED" => [%w[--kernel-checked], :kernel_checked?, true],
      "ZR_WASM_NAMES" => [%w[--wasm-names], :wasm_names?, true],
      "ZR_WASM_WIDTH" => [%w[--wasm-width 128], :wasm_width, 128],
      "ZR_TUNE" => [%w[--no-tune], :tune?, false],
      "ZR_CACHE" => [%w[--cache-dir /tmp/c], :cache, "/tmp/c"],
      "ZR_CACHE_MAX_GB" => [%w[--cache-max-gb=0.5], :cache_max_gb, 0.5],
      "ZR_HOST_RUBY" => [%w[--host-ruby /bin/ruby], :host_ruby, "/bin/ruby"],
      "ZR_LINK_ARGS" => [["--link-args", "a.o -lz"], :link, %w[a.o -lz]],
      "ZR_EXT_OBJECTS" => [["--ext-objects", "/a.bundle=/a.o"], :ext_objects, { "/a.bundle" => ["/a.o"] }],
      "ZR_EXT" => [%w[--ext dynamic], :ext_mode, "dynamic"],
      "ZR_NATIVE_EXT" => [["--native-ext", "msgpack"], :native_ext, { "msgpack" => nil }],
      "ZR_EXT_CONFIG" => [["--ext-config", "nokogiri=--use-system-libraries"], :ext_config, { "nokogiri" => ["--use-system-libraries"] }],
      "ZR_RUN_CACHE" => [%w[--no-run-cache], :run_cache?, false],
      "ZR_TRACE" => [%w[--trace], :trace?, true],
      "ZR_CODE_CACHE" => [%w[--code-cache verify], :code_cache, "verify"],
      "ZR_SERVER" => [%w[--server 0], :server, "0"]
    }
    assert_equal Zr::Config::SETTINGS.map(&:env) - %w[ZR_DEBUG], cases.keys

    cases.each do |name, (words, reader, value)|
      # A switch's variable says the opposite, so only the flag gives `value`.
      opposite = value ? "0" : "1"
      env = { name => Zr::Config.setting(name).kind == :switch ? opposite : "" }
      given, rest = Zr::Config.flags([*words, "run"])

      assert_equal ["run"], rest, name
      assert_equal value, Zr::Config.new(given, env).public_send(reader), name
    end
  end

  # The flags stop at the first word that is not one, and at `--`.
  def test_flags_come_off_the_front_only
    assert_equal [{ "ZR_TIMING" => "1" }, %w[-e p --verify]], Zr::Config.flags(%w[--timing -e p --verify])
    assert_equal [{}, %w[-- --timing]], Zr::Config.flags(%w[-- --timing])
  end

  # A bad flag names the flag, not the variable.
  def test_a_bad_flag_names_the_flag
    {
      %w[--jobs x] => '--jobs is "x". Set it to a whole number of 1 or more, for example --jobs=4.',
      %w[--linker gold] => '--linker is "gold". Set it to auto, ruby or cc, for example --linker=auto.',
      %w[--link-args 'a] => %(--link-args has a quote with no end: "'a". Close the quote, or put a \\ before it.)
    }.each do |words, message|
      error = assert_raises(Zr::Config::Invalid, words.inspect) { Zr::Config.new(Zr::Config.flags(words).first, {}) }
      assert_equal message, error.message
    end
    error = assert_raises(Zr::Config::Invalid) { Zr::Config.flags(%w[--jobs]) }
    assert_equal "--jobs needs a value: --jobs N.", error.message
    error = assert_raises(Zr::Config::Invalid) { Zr::Config.flags(%w[--timing=1]) }
    assert_equal "--timing takes no value. Give --timing alone.", error.message
  end

  # `--backtrace` turns on the backtrace as `ZR_DEBUG=1` does.
  def test_backtrace_flag_is_debug
    Zr::Config.given!(Zr::Config.flags(%w[--backtrace]).first)
    assert_predicate Zr::Config, :debug?
  ensure
    Zr::Config.given!({})
  end

  # A build server builds only for the same fingerprint; the timing and
  # the server's socket do not change what a build writes.
  def test_the_fingerprint_holds_the_settings_that_steer_a_build
    plain = Zr::Config.new({}, {}).fingerprint

    assert_equal plain, Zr::Config.new({ "ZR_TIMING" => "1", "ZR_SERVER" => "0" }, {}).fingerprint
    refute_equal plain, Zr::Config.new({ "ZR_KERNEL_CHECKED" => "1" }, {}).fingerprint
    refute_equal plain, Zr::Config.new({}, { "ZR_LINKER" => "cc" }).fingerprint
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
  # settings and a test can change them with `Config.with`. The other one
  # runs in the child ruby of an extconf.rb, and reads what `Ext::Builder`
  # gives that child, not a setting.
  READERS = %w[lib/zr/config.rb lib/zr/ext/target_rbconfig.rb].freeze

  def test_only_config_reads_a_zr_variable
    readers = (Dir[File.join(ROOT, "lib/**/*.rb")] - Dir[File.join(ROOT, "lib/zr/runtime/**/*.rb")]).select do |path|
      File.read(path).match?(/ENV(\[|\.fetch\(|\.key\?\()"ZR_|flag\?\("ZR_/)
    end

    assert_equal READERS, readers.map { |path| path.delete_prefix("#{ROOT}/") }.sort
  end
end
