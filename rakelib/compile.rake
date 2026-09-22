# frozen_string_literal: true

# How long does ze0 take to compile, and where does the time go?
#
#   rake compile                     every rung, three runs each
#   rake 'compile[--runs 5]'         five runs each
#   rake 'compile[hello bundler]'    the rungs whose name holds a word
#   rake 'compile[--write]'          write test/bench/compile/results.tsv
#
# `rake bench` times what a binary does; this times what it costs to
# make one. The rungs are a ladder of require graphs, from a program
# with no require at all to the whole of bundler, and each row is one
# phase of `Ze0.clock` -- so a change that moves the total says which
# phase it moved.
#
# The runtime is warm, as it is for everyone who is not building ze0
# itself for the first time: the first run of each rung is a warmup and
# is thrown away, and the row kept is the run whose total is the median.
# What this measures is therefore the program's own compile, which is
# what Phase 1 is about.

require "benchmark"
require "optparse"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ze0/paths"

module CompileBench
  ROOT = Ze0::Paths::ROOT
  DIR = File.join(ROOT, "test/bench/compile")
  RESULTS = File.join(DIR, "results.tsv")
  RUNS = 3

  # The line `Ze0.clock` writes: a label padded to 40, then the seconds.
  LINE = /\Aze0: (.+?)\s+([\d.]+)s\z/

  module_function

  def run(argv)
    runs = RUNS
    write = false
    OptionParser.new do |o|
      o.banner = "usage: rake 'compile[--runs N --write <filter>...]'"
      o.on("--runs N", Integer) { |v| runs = v }
      o.on("--write") { write = true }
    end.parse!(argv)
    abort("rake compile: --runs takes a count of one or more") if runs < 1

    rungs = Dir[File.join(DIR, "*.rb")].sort
    rungs = rungs.select { |rb| argv.any? { |f| File.basename(rb).include?(f) } } unless argv.empty?
    abort("rake compile: no rung matches #{argv.inspect}") if rungs.empty?

    rows = rungs.to_h { |rb| [File.basename(rb, ".rb"), median(rb, runs)] }
    table(rows)
    write!(rows, runs) if write
  end

  # One build, its phases as `{label => seconds}` with the whole build
  # under "" -- measured here rather than summed, since the phases do
  # not cover the process's own start.
  def build(rb, out)
    env = { "ZE0_TIMING" => "1", "ZE0_GC" => "0" }
    lines = status = nil
    took = Benchmark.realtime do
      read, write = IO.pipe
      pid = Process.spawn(env, RbConfig.ruby, File.join(ROOT, "exe/ze0"), "build", rb, "-o", out,
                          out: File::NULL, err: write, chdir: ROOT)
      write.close
      lines = read.read
      read.close
      _, status = Process.waitpid2(pid)
    end
    abort("rake compile: #{rb} did not build\n#{lines}") unless status.success?

    phases = lines.lines.filter_map { |line| LINE.match(line.strip)&.captures }.to_h { |l, s| [l, s.to_f] }
    phases.merge("the whole build" => took)
  end

  # `runs` builds after a warmup, and the one whose whole build is the
  # median of them.
  def median(rb, runs)
    Dir.mktmpdir("ze0-compile-") do |work|
      out = File.join(work, "out")
      print "#{File.basename(rb, ".rb")} ... "
      build(rb, out)
      taken = Array.new(runs) { build(rb, out) }.sort_by { |p| p.fetch("the whole build") }
      taken[runs / 2].tap { |p| puts format("%.3fs", p.fetch("the whole build")) }
    end
  end

  # One column a rung, one row a phase, in the order a build runs them.
  def table(rows)
    labels = rows.values.flat_map(&:keys).uniq - ["the whole build"]
    width = (labels.map(&:length) + [15]).max
    puts format("%-#{width}s  %s", "phase", rows.keys.map { |n| n.rjust(9) }.join(" "))
    (labels + ["the whole build"]).each do |label|
      cells = rows.values.map { |p| p[label] ? format("%9.3f", p[label]) : "        -" }
      puts format("%-#{width}s  %s", label, cells.join(" "))
    end
  end

  def write!(rows, runs)
    at = `git -C #{ROOT} rev-parse --short HEAD`.strip
    File.write(RESULTS, +"# test/bench/compile/results.tsv -- ze0 compile cost, " \
                         "the median of #{runs} run(s) at #{at}, runtime warm\n" \
                         "# rung\tphase\tmedian_secs\n" +
                        rows.flat_map { |name, phases| phases.map { |label, secs| "#{name}\t#{label}\t#{format('%.4f', secs)}\n" } }.join)
    warn "wrote #{RESULTS}"
  end
end

desc "How long does ze0 take to compile, and where? rake 'compile[--write]'"
task(:compile, [:filters]) { |_, args| CompileBench.run(args[:filters].to_s.split) }
