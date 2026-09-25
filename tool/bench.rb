# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # Measures how long the programs that zr builds take to run.
    #
    #   zr-dev bench                         every benchmark
    #   zr-dev bench fib string              the ones whose name contains a word
    #   zr-dev bench --runs 5 fib            five runs each
    #   zr-dev bench --target wasm32-wasi
    #   zr-dev bench --check [before after]  compare two reports
    #
    # A benchmark is a whole program under `benchmark/`, with ruby's output
    # in `<name>.out` next to it. A time counts only when the output matches,
    # so a miscompile never shows as a speedup. A run of all benchmarks
    # writes a report in the benchmark gem's layout to
    # `benchmark/results/<stamp>-<revision>.txt`; commit it with the code it
    # measured. A run of some benchmarks writes `tmp/bench/latest.txt`.
    #
    # `--check` compares the newest report under `benchmark/results/`
    # with the one before it. Or it compares two given reports, before
    # then after (a path, or a revision hash). Only zr's times are
    # compared. A program of 100 ms or more whose wall-clock time changes
    # by 10% or more fails. A shorter program is only reported, because
    # its noise is about that large.
    class Bench < Command
      summary "How long do the programs that zr builds take to run? --check compares two reports"
      usage "[--runs N] [--target TRIPLE] [filter...] | --check [before after]"

      MOVED = 0.10
      SHORT = 0.1

      def options(o)
        o.on("--runs N", Integer, "runs of each program") { |v| @runs = v }
        o.on("--target TRIPLE", "the target to build for") { |v| @triple = v }
        o.on("--check", "compare two reports; run nothing") { @check = true }
      end

      def run(argv)
        require_relative "../lib/zr/cli"
        require_relative "../test/support/harness/bench"
        require_relative "../test/support/harness/runner"
        @check ? check(argv) : measure(argv)
      end

      def measure(filters)
        Dev.tune!
        runs = @runs || Harness::Bench::RUNS
        fail!("--runs takes a count of one or more") if runs < 1
        target = @triple ? (Target.fetch(@triple) || fail!("no target #{@triple}; `zr targets` names them")) : Target.default

        # The benchmarks run what they build. Thus refuse a target that
        # this host cannot run here, not as one failure for each program.
        why = Harness::Runner.new(ROOT, target).refusal
        fail!(why) if why

        bench = Harness::Bench.new(ROOT, runs: runs, target: target)
        cases = bench.matching(filters)
        fail!("no program matches #{filters.inspect}") if cases.empty?
        warn "zr-dev bench: #{cases.size} program(s), #{runs} run(s) each"
        bench.report(bench.run(cases))
      end

      def check(argv)
        before, after = argv.empty? ? Harness::Bench.results(ROOT).last(2) : argv.map { |a| report(a) }
        fail!("give two reports, or none for the two newest under benchmark/results") unless after
        [before, after].each { |path| fail!("no report at #{path}") unless File.file?(path) }

        was = Harness::Bench.reals(File.read(before))
        now = Harness::Bench.reals(File.read(after))
        fail!("no zr rows in #{after}") if now.empty?

        failed = []
        now.each do |name, secs|
          old = was[name] or next
          moved = (secs - old) / old
          next if moved.abs < MOVED

          line = format("%-26s %8.3f -> %8.3f  %+.0f%%", name, old, secs, moved * 100)
          if [old, secs].max >= SHORT
            failed << line
          else
            puts "#{line}  (short; noted)"
          end
        end
        failed.each { |line| puts line }
        if failed.empty?
          puts "bench --check: no timed row of #{SHORT}s or more moved by #{(MOVED * 100).to_i}%"
        else
          puts "bench --check: #{failed.size} row(s) moved"
        end
        failed.empty?
      end

      # Finds a report by its path, or by the revision in its file name
      # under `benchmark/results/`.
      def report(name)
        return name if File.file?(name)

        Harness::Bench.result_of(ROOT, name) || fail!("no report at #{name}, and none under benchmark/results names that revision")
      end
    end
  end
end
