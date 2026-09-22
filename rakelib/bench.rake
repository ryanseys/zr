# frozen_string_literal: true

# How long does what ze0 built take?
#
#   rake bench                       # every benchmark
#   rake 'bench[fib string]'         # the ones whose name holds a word
#   rake 'bench[--runs 5 fib]'       # five runs each
#   rake 'bench[--target wasm32-wasi]'
#
# A benchmark is a whole program under `benchmark/` with ruby's answer
# in `<name>.out` beside it, like any other program: the time is kept
# only when the answer matched, so a miscompile never reads as a win.
# The report goes to `tmp/bench/latest.txt`, in the benchmark gem's
# own layout, and the run before it is kept as `previous.txt`.

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

# `rake bench:check` reads the run just saved against the one before it
# -- `tmp/bench/latest.txt` against `previous.txt`, or the two reports
# named, before then after: a program of 100 ms or more whose wall clock
# moved by a tenth either way fails the check, and one below that is
# only named, since a short row is noise to that order. The rows
# compared are ze0's own.
module Benchmarks
  MOVED = 0.10
  SHORT = 0.1

  module_function

  def check(argv)
    dir = File.join(ROOT, Ze0::Harness::Bench::DIR)
    before, after = argv.empty? ? [Ze0::Harness::Bench::PREVIOUS, Ze0::Harness::Bench::LATEST].map { |f| File.join(dir, f) } : argv
    abort("usage: rake 'bench:check[<before> <after>]', or none for the last two runs") unless after
    abort("rake bench:check: no report at #{before}; run rake bench twice first") unless File.file?(before)
    abort("rake bench:check: no report at #{after}; run rake bench first") unless File.file?(after)

    was = Ze0::Harness::Bench.reals(File.read(before))
    now = Ze0::Harness::Bench.reals(File.read(after))
    abort("rake bench:check: no ze0 rows in #{after}") if now.empty?

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
end

desc "Read the bench just run against the one before it: rake 'bench:check[<before> <after>]'"
task("bench:check", [:paths]) { |_, args| Benchmarks.check(args[:paths].to_s.split) }
