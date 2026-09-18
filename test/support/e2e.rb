# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "harness/answer"
require_relative "harness/child"
require_relative "harness/runner"

module Ze0
  # The end-to-end tier: whole programs, built the way anyone builds one
  # -- the CLI, in its own process, through a real link -- and held to
  # what ruby answered.
  #
  # The specs compile in process and answer for the language. These
  # answer for the product: that `ze0 build` writes a binary, and that
  # the binary a link produced starts, reads its ARGV, opens a socket,
  # takes a signal, resolves a Gemfile and flushes its output at exit.
  # They are filed by area, as the specs are, so `test/e2e/core/process`
  # and `test/spec/core/process` are about the same thing at two
  # different costs.
  #
  # A program is a `.rb` file anyone can run under ruby, and nothing
  # else: no header, no trailer, nothing to parse. What ruby answered
  # sits beside it, in files that hold those bytes and no others --
  # `<name>.out`, and `<name>.err` and `<name>.status` when there is
  # something to say. `rake record` writes them.
  module E2E
    ROOT = File.expand_path("../..", __dir__)

    # The few programs that need something. A program not named here is
    # built and run with no arguments, no environment of its own and no
    # conditions, which is nearly all of them.
    #
    #   argv:      what the binary is started with
    #   env:       what it is started under
    #   stdin:     a file beside the program, fed to it
    #   needs:     what this machine must have, or the program skips
    #   only:      the platforms that run it
    #   build_mb:  a memory bound for the build, above the usual one
    #   skip:      why it does not run at all, in words
    #
    # It lives here rather than in the test file because `rake record`
    # reads it too: a program is asked of ruby the way it is asked of
    # ze0, or the answer is not an answer to the same question.
    HOW = {
      "core/process/argv_and_env" => { argv: %w[alpha beta], env: { "ZEO_AOT_SMOKE" => "on" } },
"stdlib/bundler/require_bundler" => { build_mb: 3072 },
# A wasm module that evals holds the whole front end, since there is
# no second object to link it in as: the emitter peaks near 4.5 GB
# writing one. A native binary reads the road off the cache and
# stays far under these.
"core/io/file_io_roundtrip" => { build_mb: 5120 },
"lang/eval/eval_in_a_binary" => { build_mb: 3584 },
"lang/require/require_a_bundled_library" => { build_mb: 5120 },
"stdlib/ffi/ffi_libc_call" => { build_mb: 5120 },
"stdlib/rubygems/require_rubygems" => { build_mb: 5120 },
      "stdlib/openssl/openssl_digest" => { needs: ["libssl"] },
      "stdlib/testing/a_minitest_suite_runs" => { argv: %w[--seed 42] },
      "stdlib/testing/a_test_unit_suite_runs" => {
        skip: "power_assert's re-parse hits `Prism::CallNode#location=`, which the port does not define"
      }
    }.freeze

    # Long enough for the slowest of them -- one resolves a Gemfile --
    # and short enough that a miscompile that loops does not hold the
    # suite.
    LIMIT = 300

    # Every program, in a stable order. A program sits two directories
    # under `test/e2e`, which is what keeps the driver beside them from
    # being one.
    def self.programs = Dir[File.join(ROOT, "test/e2e/*/*/*.rb")].sort

    # The name a program answers to: its area and its own, so
    # `-n /socket/` runs the one and `-n /core_process/` runs the five.
    def self.key(rb) = rb.delete_prefix("#{File.join(ROOT, "test/e2e")}/").delete_suffix(".rb")

    # The programs a target is allowed to fail, and why, read from
    # `test/baselines/<triple>.txt`. A target on its way in is held to
    # what it did rather than to the whole tier -- and a row that now
    # passes fails the run, so the file never grows stale.
    def self.baseline(target)
      path = File.join(ROOT, "test/baselines", "#{target.triple}.txt")
      return {} unless File.file?(path)

      File.readlines(path, chomp: true).each_with_index.filter_map do |line, n|
        next if line.empty? || line.start_with?("#")

        rb, why = line.split("\t", 2)
        raise ArgumentError, "#{path}: line #{n + 1}: a row is a path and a reason, separated by a tab" unless why

        [rb, why]
      end.to_h
    end

    # The programs as tests on `suite`.
    def self.define(suite, how = HOW)
      target = Harness::Runner.named(ENV["ZE0_TARGET"])
      runner = Harness::Runner.new(ROOT, target)
      allowed = baseline(target)
      unknown = how.keys - programs.map { |rb| key(rb) }
      raise ArgumentError, "no such program: #{unknown.join(", ")}" unless unknown.empty?

      programs.each do |rb|
        mine = how.fetch(key(rb), {})
        why = allowed[rb.delete_prefix("#{ROOT}/test/")]
        suite.define_method("test_#{key(rb).tr("/", "_")}") { build_and_answer(rb, runner, mine, why) }
      end
    end

    # What the driver does with one program: build it, run it, and say
    # where the answer parts from ruby's.
    module DSL
      def build_and_answer(rb, runner, how, baselined = nil)
        return within(rb, runner, how, baselined) if baselined

        want = Harness::Answer.beside(rb)
        skip "no recording: run `rake record[#{rel(rb)}]` first" unless want
        skip "only on #{Array(how[:only]).join(", ")}" if how[:only] && !Array(how[:only]).include?(runner.platform)
        if (need = Array(how[:needs]).find { |name| !Harness::Needs.met?(name, runner.platform) })
          skip "needs #{need}, which this machine lacks"
        end
        skip how[:skip] if how[:skip]
        skip runner.refusal if runner.refusal

        Dir.mktmpdir("ze0-e2e-") do |work|
          bin = File.join(work, "p")
          build(rb, bin, how, runner)
          answer(rb, bin, how, want, runner)
        end
      end

      # A program the target's baseline names: it is allowed to fail,
      # and a pass is what the run reports, so the file cannot go stale
      # without anyone noticing.
      def within(rb, runner, how, why)
        build_and_answer(rb, runner, how)
      rescue Minitest::Skip
        # A program this machine cannot run says so for itself; the
        # baseline is about what the target answers, not about that.
        raise
      rescue Minitest::Assertion
        skip "the #{runner.target.triple} baseline allows this: #{why}"
      else
        flunk "this now passes: take it off test/baselines/#{runner.target.triple}.txt"
      end

      # `ze0 zr build`, in its own process, from `test/`, as any of
      # these programs would be built by hand.
      def build(rb, bin, how, runner)
        megabytes = [how[:build_mb] || 0, Harness::Child::BUILD_MB].max
        argv = runner.build_argv(rel(rb), bin)
        out = bounded(argv, nil, megabytes, runner.build_env)
        return if out.code == 0

        flunk "the build #{why(out, megabytes)}\n  #{argv.join(" ")}\n#{tail(out)}"
      end

      # The binary's answer, scrubbed as the recording was, held to
      # ruby's part by part so a failure names which part parted.
      def answer(rb, bin, how, recorded, runner)
        stdin = how[:stdin] && File.binread(File.join(File.dirname(rb), how[:stdin]))
        argv, env = runner.run(bin, Array(how[:argv]), how.fetch(:env, {}))
        out = bounded(argv, stdin, Harness::Child::RUN_MB, env)
        flunk "the program #{why(out, Harness::Child::RUN_MB)}" unless out.code.is_a?(Integer)

        got = Harness::Normalize.answer(out, rb, cwd)
        want = Harness::Normalize.answer(recorded, rb, cwd)
        refute runner.trapped?(got) && !want.signal, "the module trapped:\n#{got.stderr}"
        # stderr first: a program that wrote nothing to stdout has
        # almost always said why on stderr, and an empty-vs-empty
        # comparison costs nothing when it has not.
        assert_equal want.stderr, got.stderr, "stderr"
        assert_equal want.stdout, got.stdout, "stdout"
        # A signalled process has no exit status, and a process that
        # exited took no signal, so either part may be absent.
        want.signal.nil? ? assert_nil(got.signal, "signal") : assert_equal(want.signal, got.signal, "signal")
        want.code.nil? ? assert_nil(got.code, "exit status") : assert_equal(want.code, got.code, "exit status")
      end

      # Where a program is built and run: `test/`, which is what the
      # paths in its recording are relative to.
      def cwd = File.join(E2E::ROOT, "test")
      def rel(rb) = rb.delete_prefix("#{cwd}/")

      def bounded(argv, stdin, megabytes, env)
        Harness::Child.run(argv, cwd: cwd, stdin: stdin, env: env, seconds: E2E::LIMIT, megabytes: megabytes).first
      end

      # Why a child produced no answer, in words.
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
