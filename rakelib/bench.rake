# frozen_string_literal: true

# How long does what ze0 built take?
#
#   rake bench                       # every benchmark
#   rake 'bench[fib string]'         # the ones whose name holds a word
#   rake 'bench[--runs 5 fib]'       # five runs each
#   rake 'bench[--target wasm32-wasi]'
#
# A benchmark is a whole program under `test/bench/` with ruby's answer
# in `<name>.out` beside it, like any other program: the time is kept
# only when the answer matched, so a miscompile never reads as a win.

require "optparse"
require_relative "../lib/ze0/cli"
require_relative "../test/support/harness/bench"
require_relative "../test/support/harness/runner"

module Benchmarks
  ROOT = Ze0::Paths::ROOT

  module_function

  def run(argv)
    ze0_tune!
    runs = Ze0::Harness::Bench::RUNS
    target = Ze0::Target.default
    OptionParser.new do |o|
      o.banner = "usage: rake 'bench[--runs N --target <triple> <filter>...]'"
      o.on("--runs N", Integer) { |v| runs = v }
      o.on("--target TRIPLE") do |v|
        target = Ze0::Target.fetch(v) or abort("rake bench: no target #{v}; `ze0 targets` names them")
      end
    end.parse!(argv)
    abort("rake bench: --runs takes a count of one or more") if runs < 1

    # The bank runs what it builds, so a target this host cannot run is
    # refused here rather than as a failed row per program.
    if (why = Ze0::Harness::Runner.new(ROOT, target).refusal)
      abort("rake bench: #{why}")
    end

    bench = Ze0::Harness::Bench.new(ROOT, runs: runs, target: target)
    cases = bench.matching(argv)
    abort("rake bench: no program matches #{argv.inspect}") if cases.empty?
    warn "rake bench: #{cases.size} program(s), #{runs} run(s) each"
    exit(bench.report(bench.run(cases)) ? 0 : 1)
  end
end

desc "How long does what ze0 built take? rake 'bench[--runs 5 fib]'"
task(:bench, [:filters]) { |_, args| Benchmarks.run(args[:filters].to_s.split) }
