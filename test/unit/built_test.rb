# frozen_string_literal: true

require "test_helper"
require_relative "../support/built"
require_relative "../support/program_case"
require_relative "../../lib/zr/cache/janitor"

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
      start = lambda do |target, **|
        started << target
        fork { exit! 0 }
      end
      stub_method(Built, :start, start) do
        stub_method(Built, :load, ->(target, **) { loaded << target }) { capture_io { Built.ready! } }
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
      stub_method(Built, :load, ->(target, **) { loaded << target }) { capture_io { Built.ready! } }
    end

    assert_equal [Zr::Target.default], loaded
  end

  def test_ready_with_wasm_loads_host_and_wasm_targets
    stub_method(Built, :targets, [Zr::Target.default, Zr::Target::WASM32_WASI]) do
      loaded = []
      stub_method(Built, :built?, true) do
        stub_method(Built, :load, ->(target, **) { loaded << target }) { capture_io { Built.ready!(wasm: true) } }
      end

      assert_equal [Zr::Target.default, Zr::Target::WASM32_WASI], loaded
    end
  end

  # The mark, the last entry that a build writes, is named by the
  # target's runtime digest.
  def test_the_mark_names_the_runtime_digest_of_its_target
    host = Built.mark(Zr::Target.default)

    assert_equal Zr::Runtime.for(Zr::Target.default).digest, host
    assert_equal "#{host}-plain", Built.mark(Zr::Target.default, evals: false)
    refute_equal host, Built.mark(Zr::Target::WASM32_WASI)
  end

  def test_a_run_builds_only_what_its_files_declare
    unit = File.expand_path(".", __dir__)
    asked = []
    stub_method(Built, :build, ->(_targets, evals:, **) { asked << evals }) do
      stub_method(Built, :load, ->(*) {}) do
        Built.ready!(files: ["#{unit}/runtime_test.rb"])
        Built.ready!(files: ["#{unit}/runtime_test.rb", "#{unit}/eval_key_test.rb"])
        Built.ready!
      end
    end

    assert_equal [false, true, true], asked, "runtime only, then eval support, then an unknown run"
  end

  def test_ready_builds_nothing_for_files_that_declare_nothing
    stub_method(Built, :build, ->(*) { flunk "built" }) do
      stub_method(Built, :load, ->(*) { flunk "loaded" }) { Built.ready!(files: [__FILE__]) }
    end
  end

  def test_the_guard_stops_a_test_that_uses_the_runtime_without_declaring_it
    error = assert_raises(RuntimeError) { Zr::Runtime.for(Zr::Target.default).unit }
    assert_includes error.message, "declare `# zr-test: runtime`"
  end

  def test_program_tests_need_eval_support_only_when_a_program_evals
    Dir.mktmpdir("zr-built-") do |root|
      File.write(File.join(root, "plain.rb"), "puts 1\n")
      File.write(File.join(root, "evals.rb"), "eval(\"1\")\n")
      plain, evals = %w[plain evals].map { |name| Zr::Test::Case.new(root, "#{name}.rb") }

      refute Built.programs_eval?([plain])
      assert Built.programs_eval?([plain, evals])
    end
  end

  # A runtime of digest "33…" whose object is at `dir/runtime.o`, for the
  # block, in a cache at `dir`.
  def with_runtime
    Dir.mktmpdir("zr-cache-") do |dir|
      Zr::Session.current.set(:cache, dir)
      object = File.join(dir, "runtime.o")
      File.write(object, "")
      runtime = Data.define(:digest, :object_path).new(digest: "3" * 64, object_path: object)
      stub_method(Zr::Runtime, :for, runtime) { yield runtime }
    ensure
      Zr::Session.current.forget(:cache)
    end
  end

  def test_a_build_with_eval_support_serves_a_run_without
    target = Zr::Target.default
    with_runtime do
      Built.finish(target, evals: true)
      assert Built.built?(target, evals: false)
      assert Built.built?(target, evals: true)
    end
    with_runtime do
      Built.finish(target, evals: false)
      assert Built.built?(target, evals: false)
      refute Built.built?(target, evals: true)
    end
  end

  def test_a_mark_without_its_runtime_object_is_not_built
    target = Zr::Target.default
    with_runtime do |runtime|
      Built.finish(target, evals: true)
      File.unlink(runtime.object_path)

      refute Built.built?(target)
    end
  end

  # The mark is a store entry, so a clean of the whole cache, which takes
  # the runtime object, takes the mark too, and the next run builds.
  def test_a_clean_of_the_whole_cache_takes_the_mark_with_it
    target = Zr::Target.default
    with_runtime do
      Built.finish(target, evals: true)
      assert Built.built?(target)

      Zr::Cache::Janitor.clear

      refute Built.built?(target)
    end
  end
end
