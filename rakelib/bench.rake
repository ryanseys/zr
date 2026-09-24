# frozen_string_literal: true

# Measures how long the programs that zr builds take to run.
#
#   rake bench                       # every benchmark
#   rake 'bench[fib string]'         # the ones whose name contains a word
#   rake 'bench[--runs 5 fib]'       # five runs each
#   rake 'bench[--target wasm32-wasi]'
#
# A benchmark is a whole program under `benchmark/`, with ruby's output
# in `<name>.out` next to it. A time counts only when the output matches,
# so a miscompile never shows as a speedup. A run of all benchmarks
# writes a report in the benchmark gem's layout to
# `benchmark/results/<stamp>-<revision>.txt`; commit it with the code it
# measured. A run of some benchmarks writes `tmp/bench/latest.txt`.

require "optparse"
require_relative "../lib/zr/cli"
require_relative "../test/support/harness/bench"
require_relative "../test/support/harness/runner"

module Benchmarks
  ROOT = Zr::Paths::ROOT

  module_function

  def run(argv)
    zr_tune!
    runs = Zr::Harness::Bench::RUNS
    target = Zr::Target.default
    OptionParser.new do |o|
      o.banner = "usage: rake 'bench[--runs N --target <triple> <filter>...]'"
      o.on("--runs N", Integer) { |v| runs = v }
      o.on("--target TRIPLE") do |v|
        target = Zr::Target.fetch(v) or abort("rake bench: no target #{v}; `zr targets` names them")
      end
    end.parse!(argv)
    abort("rake bench: --runs takes a count of one or more") if runs < 1

    # The benchmarks run what they build. Thus refuse a target that this
    # host cannot run here, not as one failure for each program.
    if (why = Zr::Harness::Runner.new(ROOT, target).refusal)
      abort("rake bench: #{why}")
    end

    bench = Zr::Harness::Bench.new(ROOT, runs: runs, target: target)
    cases = bench.matching(argv)
    abort("rake bench: no program matches #{argv.inspect}") if cases.empty?
    warn "rake bench: #{cases.size} program(s), #{runs} run(s) each"
    exit(bench.report(bench.run(cases)) ? 0 : 1)
  end
end

desc "How long does what zr built take? rake 'bench[--runs 5 fib]'"
task(:bench, [:filters]) { |_, args| Benchmarks.run(args[:filters].to_s.split) }

# `rake bench:check` compares the newest report under `benchmark/results/`
# with the one before it. Or it compares two given reports, before then
# after (a path, or a revision hash). Only zr's times are compared.
# A program of 100 ms or more whose wall-clock time changes by 10% or
# more fails. A shorter program is only reported, because its noise is
# about that large.
module Benchmarks
  MOVED = 0.10
  SHORT = 0.1

  module_function

  def check(argv)
    before, after = argv.empty? ? Zr::Harness::Bench.results(ROOT).last(2) : argv.map { |a| report(a) }
    abort("usage: rake 'bench:check[<before> <after>]', or none for the two newest under benchmark/results") unless after
    abort("rake bench:check: no report at #{before}") unless File.file?(before)
    abort("rake bench:check: no report at #{after}") unless File.file?(after)

    was = Zr::Harness::Bench.reals(File.read(before))
    now = Zr::Harness::Bench.reals(File.read(after))
    abort("rake bench:check: no zr rows in #{after}") if now.empty?

    failed = []
    now.each do |name, secs|
      before = was[name] or next
      moved = (secs - before) / before
      next if moved.abs < MOVED

      line = format("%-26s %8.3f -> %8.3f  %+.0f%%", name, before, secs, moved * 100)
      if [before, secs].max >= SHORT
        failed << line
      else
        puts "#{line}  (short; noted)"
      end
    end
    failed.each { |line| puts line }
    puts(failed.empty? ? "bench:check: no timed row of #{SHORT}s or more moved by #{(MOVED * 100).to_i}%" : "bench:check: #{failed.size} row(s) moved")
    exit(failed.empty? ? 0 : 1)
  end

  # Finds a report by its path, or by the revision in its file name under
  # `benchmark/results/`.
  def report(name)
    return name if File.file?(name)

    Zr::Harness::Bench.result_of(ROOT, name) || abort("rake bench:check: no report at #{name}, and none under benchmark/results names that revision")
  end
end

desc "Read the bench just run against the one before it: rake 'bench:check[<before> <after>]'"
task("bench:check", [:paths]) { |_, args| Benchmarks.check(args[:paths].to_s.split) }
