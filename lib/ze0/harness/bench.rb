# frozen_string_literal: true

require "etc"
require "rbconfig"
require "tmpdir"
require_relative "sweep"

module Ze0
  module Harness
    # `ze0 bench`: how long the binary ze0 built takes, beside the ruby
    # that recorded its answer.
    #
    # `test/bench` is a corpus suite like every other one -- `ze0 test
    # bench::` already compiles, runs and answer-checks all 61 of its
    # programs -- so what is here is the clock and the comparison
    # columns, and nothing that reads a program.
    #
    # **The answer is checked before any time is kept.** The speed of a
    # wrong answer means nothing, and a codegen step that trades an
    # answer for a time is the one thing the contract does not allow.
    #
    # Serial from end to end. A sweep runs a process per core because it
    # only asks what a program said; a time measured beside three other
    # compiles is not a time.
    class Bench
      # Three runs and the middle one: enough that one scheduling
      # accident is not the answer, few enough that the suite is minutes.
      RUNS = 3

      # `build` is the compile; the three others are the program, in
      # seconds. A row with no time carries `why` instead.
      Row = Struct.new(:rb, :bucket, :why, :build, :ze0, :ruby, :yjit) do
        def name = File.basename(rb, ".rb")
        def timed? = bucket == :timed
        def against(other) = timed? && other&.positive? ? ze0 / other : nil
      end

      def initialize(root, runs: RUNS, show: 10, target: Target.default)
        @root = root
        @runs = runs
        @show = show
        @sweep = Sweep.new(root, target: target)
      end

      # Every program under `test/bench`, or the ones a filter names.
      def matching(filters)
        rows = @sweep.matching(["bench::"])
        return rows if filters.empty?

        rows.select { |rb| filters.any? { |f| File.basename(rb).include?(f) } }
      end

      def run(cases, io = $stdout)
        io.sync = true
        Dir.mktmpdir("ze0-bench-") do |work|
          cases.map.with_index do |rb, n|
            io.print format("[%d/%d] %s ... ", n + 1, cases.size, File.basename(rb, ".rb"))
            row = one(rb, work)
            io.puts row.timed? ? format("%.3fs", row.ze0) : "#{row.bucket}: #{row.why}"
            row
          end
        end
      end

      # Build, check the answer, then time the three of them.
      def one(rb, work)
        kase = Case.read(rb)
        return Row.new(rb, :skipped, "no recording") unless kase.recorded?

        cwd = File.join(@root, "test")
        rel = rb.delete_prefix("#{cwd}/")
        bin = File.join(work, "p")
        File.delete(bin) if File.exist?(bin)

        build, out = clocked { @sweep.bounded(@sweep.build_argv(rel, bin), cwd, nil) }
        return Row.new(rb, :refused, first_line(out)) if out.code == 3
        return Row.new(rb, :backend, out.code == :timeout ? "the build ran past #{Sweep::LIMIT}s" : first_line(out)) unless out.code == 0

        stdin = kase.directives.stdin && File.binread(File.join(File.dirname(rb), kase.directives.stdin))
        env = kase.directives.env.merge(kase.directives.zeo_env)
        want = Normalize.answer(kase.expected(@sweep.runner.platform), rb, cwd)
        argv, run_env = @sweep.runner.run(bin, kase.directives.args, env)
        got, wrong = medians(argv, cwd, stdin, run_env, rb, want)
        return Row.new(rb, :diverged, wrong) if wrong

        oracle = kase.directives.ruby + [rel, *kase.directives.args]
        plain, = medians([RbConfig.ruby, *oracle], cwd, stdin, kase.directives.env, rb, nil)
        jit, = medians([RbConfig.ruby, "--yjit", *oracle], cwd, stdin, kase.directives.env, rb, nil)
        Row.new(rb, :timed, nil, build, got, plain, jit)
      end

      # The middle of `@runs` wall clocks, and what the first run of the
      # binary got wrong when `want` is given. A later run is not checked
      # again: a program whose answer depends on the run is a defect the
      # sweep is there to find, not something to spend a comparison on.
      def medians(argv, cwd, stdin, env, rb, want)
        times = []
        @runs.times do |n|
          seconds, out = clocked { @sweep.bounded(argv, cwd, stdin, env) }
          return [nil, "ran past #{Sweep::LIMIT}s"] if out.code == :timeout

          if n.zero? && want
            got = Normalize.answer(out, rb, cwd)
            return [nil, @sweep.diff(want, got)] if got != want
          elsif want.nil? && out.code != 0
            # ruby could not run it -- an old `--yjit`, a gem it wants.
            # The column stays empty and the row keeps its ze0 time.
            return [nil, nil]
          end
          times << seconds
        end
        [times.sort[@runs / 2], nil]
      end

      def clocked
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        answer = yield
        [Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, answer]
      end

      def first_line(out)
        text = out.stderr.empty? ? out.stdout : out.stderr
        (text.lines.first&.strip || "(no message)").sub(/\Aze0: /, "")
      end

      # The table, the two geometric means, and whether every program
      # answered. A slow row is a result; a wrong row is a failure.
      def report(rows, io = $stdout)
        io.puts
        io.puts format("%-26s %8s %8s %8s %8s %9s %9s", "program", "build", "ze0", "ruby", "yjit", "vs ruby", "vs yjit")
        rows.each { |r| io.puts line(r) }
        timed = rows.select(&:timed?)
        io.puts
        io.puts format("%d timed, %d not", timed.size, rows.size - timed.size)
        %i[ruby yjit].each do |what|
          ratios = timed.filter_map { |r| r.against(r[what]) }
          next if ratios.empty?

          io.puts format("ze0 is %.2fx of %s, geometric mean over %d program(s)", geomean(ratios), what, ratios.size)
        end
        io.puts "  wrote #{save(rows)}"
        rows.none? { |r| %i[diverged backend].include?(r.bucket) }
      end

      def line(row)
        return format("%-26s %8.1f %8s %8s %8s %9s %9s", row.name, row.build || 0, row.bucket, "", "", "", "") unless row.timed?

        format("%-26s %8.1f %8.3f %8s %8s %9s %9s", row.name, row.build, row.ze0,
               seconds(row.ruby), seconds(row.yjit), times(row.against(row.ruby)), times(row.against(row.yjit)))
      end

      def seconds(t) = t ? format("%.3f", t) : "-"
      def times(r) = r ? format("%.2fx", r) : "-"

      # The geometric mean, because these are ratios: the arithmetic one
      # would let a single slow program speak for the suite.
      def geomean(values) = Math.exp(values.sum { |v| Math.log(v) } / values.size)

      # `test/bench/results.tsv`, one row a group a program, so a later
      # run can be read against this one with a text diff.
      def save(rows)
        path = File.join(@root, "test/bench/results.tsv")
        rev = `git -C #{@root} rev-parse --short HEAD 2>/dev/null`.strip
        File.open(path, "w") do |f|
          f.puts "# test/bench/results.tsv -- ze0 bench, the median of #{@runs} run(s)#{rev.empty? ? "" : " at #{rev}"}"
          f.puts "# group\tbenchmark\tmedian_secs"
          rows.each do |r|
            { "build" => r.build, "ze0" => r.ze0, "ruby" => r.ruby, "yjit" => r.yjit }.each do |group, t|
              f.puts format("%s\t%s\t%.4f", group, r.name, t) if t
            end
          end
        end
        path
      end
    end
  end
end
