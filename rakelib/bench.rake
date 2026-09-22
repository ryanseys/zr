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

# `rake bench:check` reads the run just saved against the one committed:
# a program of 100 ms or more that moved by a tenth either way fails the
# check, and one below that is only named, since a short row is noise
# to that order. The rows compared are ze0's own times.
module Benchmarks
  MOVED = 0.10
  SHORT = 0.1

  module_function

  def check
    path = File.join(ROOT, "test/bench/results.tsv")
    was = times(`git -C #{ROOT} show HEAD:test/bench/results.tsv 2>/dev/null`)
    now = times(File.read(path))
    abort("rake bench:check: no ze0 rows in #{path}; run rake bench first") if now.empty?

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

  # `{ "bm_fib" => 0.123, ... }`: the ze0 rows of a results file.
  def times(tsv)
    tsv.lines.filter_map do |line|
      group, name, secs = line.chomp.split("\t")
      [name, Float(secs)] if group == "ze0"
    end.to_h
  end
end

desc "Read the bench just run against the committed results"
task("bench:check") { Benchmarks.check }
