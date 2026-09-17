# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "harness/case"
require_relative "harness/child"
require_relative "harness/runner"

module Ze0
  # The end-to-end tier: whole programs, built the way anyone builds one
  # -- the CLI, in its own process, through a real link -- and held to
  # what ruby recorded under `__END__`.
  #
  # The specs compile in process and answer for the language. These
  # answer for the product: that `ze0 build` writes a binary, and that
  # the binary a link produced starts, reads its ARGV, opens a socket,
  # takes a signal, resolves a Gemfile and flushes its output at exit.
  # They are filed by area, as the specs are, so `test/e2e/core/process`
  # and `test/spec/core/process` are about the same thing at two
  # different costs.
  module E2E
    ROOT = File.expand_path("../..", __dir__)

    # Long enough for the slowest of them -- one resolves a Gemfile --
    # and short enough that a miscompile that loops does not hold the
    # suite.
    LIMIT = 300

    # Every program, in a stable order. A program sits two directories
    # under `test/e2e`, which is what keeps the driver beside them from
    # being one.
    def self.programs = Dir[File.join(ROOT, "test/e2e/*/*/*.rb")].sort

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

    # The programs as tests on `suite`, named by area and program, so
    # `-n /socket/` runs the one and `-n /core_process/` runs the five.
    def self.define(suite)
      target = Harness::Runner.named(ENV["ZE0_TARGET"])
      runner = Harness::Runner.new(ROOT, target)
      allowed = baseline(target)
      programs.each do |rb|
        name = rb.delete_prefix("#{File.join(ROOT, "test/e2e")}/").delete_suffix(".rb").tr("/", "_")
        why = allowed[rb.delete_prefix("#{ROOT}/test/")]
        suite.define_method("test_#{name}") { build_and_answer(rb, runner, why) }
      end
    end

    # What the driver does with one program: build it, run it, and say
    # where the answer parts from ruby's.
    module DSL
      def build_and_answer(rb, runner, baselined = nil)
        return within(rb, runner, baselined) if baselined

        kase = Harness::Case.read(rb)
        skip "no recording: run `rake record[#{rel(rb)}]` first" unless kase.recorded?
        skip "only on #{kase.directives.only.join(", ")}" unless kase.runs_on?(runner.platform)
        if (need = kase.unmet_need(runner.platform))
          skip "needs #{need}, which this machine lacks"
        end
        skip kase.directives.skip if kase.directives.skip
        skip runner.refusal if runner.refusal

        Dir.mktmpdir("ze0-e2e-") do |work|
          bin = File.join(work, "p")
          build(rb, bin, kase, runner)
          answer(rb, bin, kase, runner)
        end
      end

      # A program the target's baseline names: it is allowed to fail,
      # and a pass is what the run reports, so the file cannot go stale
      # without anyone noticing.
      def within(rb, runner, why)
        build_and_answer(rb, runner)
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
      def build(rb, bin, kase, runner)
        megabytes = Harness::Child.build_mb(kase.directives)
        argv = runner.build_argv(rel(rb), bin)
        out = bounded(argv, nil, megabytes, runner.build_env)
        return if out.code == 0

        flunk "the build #{why(out, megabytes)}\n  #{argv.join(" ")}\n#{tail(out)}"
      end

      # The binary's answer, scrubbed as the recording was, held to
      # ruby's part by part so a failure names which part parted.
      def answer(rb, bin, kase, runner)
        stdin = kase.directives.stdin && File.binread(File.join(File.dirname(rb), kase.directives.stdin))
        argv, env = runner.run(bin, kase.directives.args, kase.directives.env.merge(kase.directives.zeo_env))
        out = bounded(argv, stdin, Harness::Child::RUN_MB, env)
        flunk "the program #{why(out, Harness::Child::RUN_MB)}" unless out.code.is_a?(Integer)

        got = Harness::Normalize.answer(out, rb, cwd)
        want = Harness::Normalize.answer(kase.expected(runner.platform), rb, cwd)
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
