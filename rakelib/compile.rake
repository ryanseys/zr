# frozen_string_literal: true

# Measures how long zr takes to compile, and the time of each phase.
#
#   rake compile                     every program, three runs each
#   rake 'compile[--runs 5]'         five runs each
#   rake 'compile[hello bundler]'    the programs whose name contains a word
#   rake 'compile[--write]'          write the table to tmp/bench/compile.txt
#   rake 'compile[--zr]'             also time the compiled compiler
#
# `rake bench` times what a binary does; this task times how long it
# takes to make one. The programs in `benchmark/compile` have require
# graphs of increasing size, from no require to all of bundler. Each
# row is one phase of `Zr.clock`, so you can see which phase a change
# affects.
#
# The runtime is already built. The first run of each program is a
# warmup and is discarded. The task keeps the run with the median total.
# Thus it measures only the compile of the program itself.
#
# `--zr` first uses ruby to build the compiler from the current tree.
# Then it times each program with both compilers. The compiled
# compiler's column has a `*`, and a last row gives its time divided by
# ruby's. The compiled compiler gets its own cache, with links to the
# runtime that ruby built. This is correct because a runtime's key is
# the digest of its sources, and a compiler built from the same sources
# makes the same bytes (`rake stage1`). A compiled compiler from a
# different tree would write its output under this tree's digest. Thus
# the task always builds its own compiled compiler.

require "benchmark"
require "fileutils"
require "optparse"
require "rbconfig"
require "tmpdir"
require_relative "../lib/zr/paths"

module CompileBench
  ROOT = Zr::Paths::ROOT
  DIR = File.join(ROOT, "benchmark/compile")
  # Where `--write` puts the table: under `tmp`, next to the report of
  # `rake bench`. It is not committed.
  RESULTS = File.join(ROOT, "tmp/bench/compile.txt")
  RUNS = 3
  # The compiled compiler and its cache, under `tmp`.
  COMPILED = File.join(ROOT, "tmp/compile/zr")
  COMPILED_CACHE = File.join(ROOT, "tmp/compile/cache")

  # The line `Zr.clock` writes: a label padded to 40, then the seconds.
  LINE = /\Azr: (.+?)\s+([\d.]+)s(?:\s|\z)/

  module_function

  def run(argv)
    runs = RUNS
    write = false
    compiled = false
    OptionParser.new do |o|
      o.banner = "usage: rake 'compile[--runs N --write <filter>...]'"
      o.on("--runs N", Integer) { |v| runs = v }
      o.on("--write") { write = true }
      o.on("--zr") { compiled = true }
    end.parse!(argv)
    abort("rake compile: --runs takes a count of one or more") if runs < 1

    rungs = Dir[File.join(DIR, "*.rb")].sort
    rungs = rungs.select { |rb| argv.any? { |f| File.basename(rb).include?(f) } } unless argv.empty?
    abort("rake compile: no rung matches #{argv.inspect}") if rungs.empty?

    compiled!(rungs.first) if compiled
    rows = rungs.each_with_object({}) do |rb, h|
      name = File.basename(rb, ".rb")
      h[name] = median(rb, runs)
      h["#{name}*"] = median(rb, runs, compiled: true) if compiled
    end
    table(rows)
    write!(rows, runs) if write
  end

  # Runs one build and returns its phases as `{label => seconds}`. The
  # entry "the whole build" is measured here, not added from the phases,
  # because the phases do not include the process start.
  def build(rb, out, compiled: false)
    # With the GC limits set here, `zr` does not restart itself.
    env = { "ZR_TIMING" => "1", **Zr::CLI::GC_ENV }
    command = [RbConfig.ruby, File.join(ROOT, "exe/zr")]
    if compiled
      env["ZR_CACHE"] = COMPILED_CACHE
      command = [COMPILED]
    end
    lines = status = nil
    took = Benchmark.realtime do
      read, write = IO.pipe
      pid = Process.spawn(env, *command, "build", rb, "-o", out, out: File::NULL, err: write, chdir: ROOT)
      write.close
      lines = read.read
      read.close
      _, status = Process.waitpid2(pid)
    end
    abort("rake compile: #{rb} did not build\n#{lines}") unless status.success?

    phases = lines.lines.filter_map { |line| LINE.match(line.strip)&.captures }.to_h { |l, s| [l, s.to_f] }
    phases.merge("the whole build" => took)
  end

  # Runs one warmup build and then `runs` builds. Returns the build with
  # the median total time.
  def median(rb, runs, compiled: false)
    Dir.mktmpdir("zr-compile-") do |work|
      out = File.join(work, "out")
      print "#{File.basename(rb, ".rb")}#{"*" if compiled} ... "
      build(rb, out, compiled: compiled)
      taken = Array.new(runs) { build(rb, out, compiled: compiled) }.sort_by { |p| p.fetch("the whole build") }
      taken[runs / 2].tap { |p| puts format("%.3fs", p.fetch("the whole build")) }
    end
  end

  # Uses ruby to compile the compiler from this tree. Its cache gets a
  # link to each entry of ruby's cache, except the unit entries. `rung`
  # builds first with ruby, so that this tree's runtime is available.
  def compiled!(rung)
    Dir.mktmpdir("zr-compile-") { |work| build(rung, File.join(work, "out")) }
    print "the compiled compiler ... "
    took = Benchmark.realtime do
      system(Zr::CLI::GC_ENV, RbConfig.ruby, File.join(ROOT, "exe/zr"), "build", File.join(ROOT, "exe/zr"),
             "-o", COMPILED, out: File::NULL, chdir: ROOT) or abort("rake compile: the compiler did not build")
    end
    puts format("%.1fs", took)
    FileUtils.mkdir_p(COMPILED_CACHE)
    Dir.children(Zr::Paths.cache).each do |name|
      from = File.join(Zr::Paths.cache, name)
      to = File.join(COMPILED_CACHE, name)
      next if name.start_with?("unit-") || !File.file?(from) || File.exist?(to)

      File.link(from, to)
    end
  end

  # Prints one column for each program and one row for each phase, in
  # build order. With `--zr`, a last row gives the compiled compiler's
  # total time divided by ruby's.
  def table(rows, io = $stdout)
    labels = rows.values.flat_map(&:keys).uniq - ["the whole build"]
    width = (labels.map(&:length) + [15]).max
    io.puts format("%-#{width}s  %s", "phase", rows.keys.map { |n| n.rjust(9) }.join(" "))
    (labels + ["the whole build"]).each do |label|
      cells = rows.values.map { |p| p[label] ? format("%9.3f", p[label]) : "        -" }
      io.puts format("%-#{width}s  %s", label, cells.join(" "))
    end
    return unless rows.keys.any? { |n| n.end_with?("*") }

    cells = rows.map do |name, p|
      ruby = rows[name.delete_suffix("*")]
      name.end_with?("*") ? format("%8.2fx", p.fetch("the whole build") / ruby.fetch("the whole build")) : "        -"
    end
    io.puts format("%-#{width}s  %s", "compiled / ruby", cells.join(" "))
  end

  # Writes the same table, under a line that gives the time and revision.
  def write!(rows, runs)
    at = `git -C #{ROOT} rev-parse --short HEAD`.strip
    FileUtils.mkdir_p(File.dirname(RESULTS))
    File.open(RESULTS, "w") do |f|
      f.puts "# zr compile cost, the median of #{runs} run(s) at #{at}, runtime warm, #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}"
      table(rows, f)
    end
    warn "wrote #{RESULTS}"
  end
end

desc "How long does zr take to compile, and where? rake 'compile[--write]'"
task(:compile, [:filters]) { |_, args| CompileBench.run(args[:filters].to_s.split) }
