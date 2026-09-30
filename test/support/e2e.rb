# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "baseline"
require_relative "harness/answer"
require_relative "harness/child"
require_relative "harness/runner"

module Zr
  # The end-to-end tier. It builds whole programs as a user does (the
  # CLI, in its own process, with a real link) and checks the output
  # against the recording from ruby.
  #
  # The specs compile in process and test the language. These tests
  # test the product: `zr build` writes a binary, and the linked binary
  # starts, reads ARGV, opens a socket, receives a POSIX signal, resolves
  # a Gemfile and flushes its output at exit. The directories follow the
  # specs, so `test/e2e/core/process` and `test/spec/core/process` test
  # the same area at two different costs.
  #
  # A program is a plain `.rb` file that ruby can run. It has no header
  # or trailer. Its recording is next to it: `<name>.out`, and also
  # `<name>.err` and `<name>.status` when they are not empty.
  # `zr-dev record` writes them.
  module E2E
    ROOT = File.expand_path("../..", __dir__)

    # Settings for the few programs that need them. A program that is not
    # in this table runs with no arguments, no added environment and no
    # conditions. Almost all programs are not in it.
    #
    #   argv:      the arguments of the binary
    #   env:       the environment of the binary
    #   stdin:     a file next to the program, sent to its stdin
    #   needs:     what this machine must have, or the program skips
    #   only:      the platforms that run it
    #   build_mb:  a memory limit for the build, above the usual one
    #   run_mb:    a memory limit for the run, above the usual one
    #   skip:      the reason that it does not run
    #
    # `zr-dev record` also reads this table, so ruby and zr run each program
    # with the same arguments, environment and input.
    HOW = {
      "core/process/argv_and_env" => { argv: %w[alpha beta], env: { "ZR_TEST_AOT_SMOKE" => "on" } },
      "stdlib/bundler/require_bundler" => { build_mb: 3072 },
      # A WASI module that evals includes the whole front end, because
      # there is no second object to link eval support from. The module
      # is about 90 MB. It takes near 3 GB to emit and near 2.1 GB to
      # instantiate, because the engine compiles the whole module before
      # it runs. Native builds link eval support from the cache and use
      # much less memory.
      "core/io/file_io_roundtrip" => { build_mb: 4096, run_mb: 3072 },
      "lang/eval/eval_in_a_binary" => { build_mb: 3584, run_mb: 3072 },
      "lang/require/require_a_bundled_library" => { build_mb: 4096, run_mb: 3072 },
      "stdlib/ffi/ffi_libc_call" => { build_mb: 4096, run_mb: 3072 },
      "stdlib/rubygems/gem_accepts_the_programs_gems" => { build_mb: 4096, run_mb: 3072 },
      "stdlib/rubygems/require_rubygems" => { build_mb: 4096, run_mb: 3072 },
      "stdlib/openssl/openssl_digest" => { needs: ["libssl"] },
      "stdlib/testing/a_minitest_suite_runs" => { argv: %w[--seed 42] }
    }.freeze

    # Long enough for the slowest program (one resolves a Gemfile), and
    # short enough that a miscompiled infinite loop does not stop the suite.
    LIMIT = 300

    # Returns all programs, in a stable order. A program is two directories
    # below `test/e2e`, so the driver files in `test/e2e` are not programs.
    def self.programs = Dir[File.join(ROOT, "test/e2e/*/*/*.rb")].sort

    # Returns the test name of a program: its area and its file name. So
    # `-n /socket/` runs one program and `-n /core_process/` runs five.
    def self.key(rb) = rb.delete_prefix("#{File.join(ROOT, "test/e2e")}/").delete_suffix(".rb")

    # Defines one test on `suite` for each program.
    def self.define(suite, how = HOW)
      target = Harness::Runner.named(ENV["ZR_TARGET"])
      runner = Harness::Runner.new(ROOT, target)
      allowed = Test::Baseline.for(target)
      unknown = how.keys - programs.map { |rb| key(rb) }
      raise ArgumentError, "no such program: #{unknown.join(", ")}" unless unknown.empty?

      programs.each do |rb|
        mine = how.fetch(key(rb), {})
        why = allowed[rb.delete_prefix("#{ROOT}/test/")]
        suite.define_method("test_#{key(rb).tr("/", "_")}") { build_and_answer(rb, runner, mine, why) }
      end
    end

    # Builds and runs one program, and shows where its output is
    # different from the ruby recording.
    module DSL
      def build_and_answer(rb, runner, how, baselined = nil)
        return within(rb, runner, how, baselined) if baselined

        want = Harness::Answer.beside(rb)
        skip "no recording: run `zr-dev record #{rel(rb)}` first" unless want
        skip "only on #{Array(how[:only]).join(", ")}" if how[:only] && !Array(how[:only]).include?(runner.platform)
        if (need = Array(how[:needs]).find { |name| !Harness::Needs.met?(name, runner.platform) })
          skip "needs #{need}, which this machine lacks"
        end
        skip how[:skip] if how[:skip]
        skip runner.refusal if runner.refusal

        Dir.mktmpdir("zr-e2e-") do |work|
          bin = File.join(work, "p")
          build(rb, bin, how, runner)
          answer(rb, bin, how, want, runner)
        end
      end

      # Runs a program that is in the baseline of the target. A failure is
      # a skip. A pass is a failure, so the baseline file stays current.
      def within(rb, runner, how, why)
        build_and_answer(rb, runner, how)
      rescue Minitest::Skip
        # A skip because of this machine is not a baseline failure, so
        # it stays a skip.
        raise
      rescue Minitest::Assertion
        skip "the #{runner.target.triple} baseline allows this: #{why}"
      else
        flunk "this now passes: take it off test/baselines/#{runner.target.triple}.txt"
      end

      # Runs `zr build` in its own process, from `test/`, as a user does.
      def build(rb, bin, how, runner)
        megabytes = [how[:build_mb] || 0, Harness::Child::BUILD_MB].max
        argv = runner.build_argv(rel(rb), bin)
        out = bounded(argv, nil, megabytes, runner.build_env)
        return if out.code == 0

        flunk "the build #{why(out, megabytes)}\n  #{argv.join(" ")}\n#{tail(out)}"
      end

      # Runs the binary, normalizes the output as the recording was
      # normalized, and compares each part with the recording. A failure
      # gives the part that is different.
      def answer(rb, bin, how, recorded, runner)
        megabytes = [how[:run_mb] || 0, Harness::Child::RUN_MB].max
        stdin = how[:stdin] && File.binread(File.join(File.dirname(rb), how[:stdin]))
        argv, env = runner.run(bin, Array(how[:argv]), how.fetch(:env, {}))
        out = bounded(argv, stdin, megabytes, env)
        flunk "the program #{why(out, megabytes)}" unless out.code.is_a?(Integer)

        got = Harness::Normalize.answer(out, rb, cwd)
        want = Harness::Normalize.answer(recorded, rb, cwd)
        refute runner.trapped?(got) && !want.signal, "the module trapped:\n#{got.stderr}"
        # Compare stderr first. A program that wrote nothing to stdout
        # usually gives the reason on stderr.
        assert_equal want.stderr, got.stderr, "stderr"
        assert_equal want.stdout, got.stdout, "stdout"
        # A process that a POSIX signal stopped has no exit status, and a
        # process that exited has no signal, so either part can be nil.
        want.signal.nil? ? assert_nil(got.signal, "signal") : assert_equal(want.signal, got.signal, "signal")
        want.code.nil? ? assert_nil(got.code, "exit status") : assert_equal(want.code, got.code, "exit status")
      end

      # The directory where a program is built and run: `test/`. The
      # paths in a recording are relative to it.
      def cwd = File.join(E2E::ROOT, "test")
      def rel(rb) = rb.delete_prefix("#{cwd}/")

      def bounded(argv, stdin, megabytes, env)
        Harness::Child.run(argv, cwd: cwd, stdin: stdin, env: env, seconds: E2E::LIMIT, megabytes: megabytes).first
      end

      # Returns the reason, in words, that a child did not succeed.
      def why(out, megabytes)
        case out.code
        when :timeout then "ran past #{E2E::LIMIT}s"
        when :memory then "held more than #{megabytes} MB"
        else "exited #{out.code}"
        end
      end

      def tail(out) = (out.stderr.empty? ? out.stdout : out.stderr).lines.last(20).map { |l| "  #{l}" }.join
    end
  end
end
