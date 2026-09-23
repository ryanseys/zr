# frozen_string_literal: true

# How long does ze0 take to compile, and where does the time go?
#
#   rake compile                     every rung, three runs each
#   rake 'compile[--runs 5]'         five runs each
#   rake 'compile[hello bundler]'    the rungs whose name holds a word
#   rake 'compile[--write]'          write the table to tmp/bench/compile.txt
#   rake 'compile[--ze0]'            the compiler ze0 compiled, beside ruby
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
#
# `--ze0` first builds the compiler with ruby, from the tree as it is,
# and times each rung under both, the compiled one's column named with
# a `*`, and a last row of what it took against ruby. It keeps a cache
# of its own, seeded with links to the runtime ruby built: a runtime is
# keyed on the digest of the sources that made it, and a compiler built
# from those same sources makes the same bytes (`rake stage1`), so the
# compiled compiler starts warm too. A compiled compiler from another
# tree would claim this tree's digest for its own work, which is why the
# task builds its own and never takes one it is given.

require "benchmark"
require "fileutils"
require "optparse"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ze0/paths"

module CompileBench
  ROOT = Ze0::Paths::ROOT
  DIR = File.join(ROOT, "benchmark/compile")
  # Where `--write` keeps the table: under `tmp`, beside `rake bench`'s
  # own report, and not committed.
  RESULTS = File.join(ROOT, "tmp/bench/compile.txt")
  RUNS = 3
  # The compiled compiler and its cache, under `tmp`.
  COMPILED = File.join(ROOT, "tmp/compile/ze0")
  COMPILED_CACHE = File.join(ROOT, "tmp/compile/cache")

  # The line `Ze0.clock` writes: a label padded to 40, then the seconds.
  LINE = /\Aze0: (.+?)\s+([\d.]+)s(?:\s|\z)/

  module_function

  def run(argv)
    runs = RUNS
    write = false
    compiled = false
    OptionParser.new do |o|
      o.banner = "usage: rake 'compile[--runs N --write <filter>...]'"
      o.on("--runs N", Integer) { |v| runs = v }
      o.on("--write") { write = true }
      o.on("--ze0") { compiled = true }
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

  # One build, its phases as `{label => seconds}` with the whole build
  # under "" -- measured here rather than summed, since the phases do
  # not cover the process's own start.
  def build(rb, out, compiled: false)
    env = { "ZE0_TIMING" => "1", "ZE0_GC" => "0" }
    command = [RbConfig.ruby, File.join(ROOT, "exe/ze0")]
    if compiled
      env["ZE0_CACHE"] = COMPILED_CACHE
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

  # `runs` builds after a warmup, and the one whose whole build is the
  # median of them.
  def median(rb, runs, compiled: false)
    Dir.mktmpdir("ze0-compile-") do |work|
      out = File.join(work, "out")
      print "#{File.basename(rb, ".rb")}#{"*" if compiled} ... "
      build(rb, out, compiled: compiled)
      taken = Array.new(runs) { build(rb, out, compiled: compiled) }.sort_by { |p| p.fetch("the whole build") }
      taken[runs / 2].tap { |p| puts format("%.3fs", p.fetch("the whole build")) }
    end
  end

  # The compiler, compiled by ruby from this tree, with a cache that
  # links every runtime-wide entry of ruby's own: `rung` builds first
  # with ruby, so the runtime of this tree is there to link.
  def compiled!(rung)
    Dir.mktmpdir("ze0-compile-") { |work| build(rung, File.join(work, "out")) }
    print "the compiled compiler ... "
    took = Benchmark.realtime do
      system({ "ZE0_GC" => "0" }, RbConfig.ruby, File.join(ROOT, "exe/ze0"), "build", File.join(ROOT, "exe/ze0"),
             "-o", COMPILED, out: File::NULL, chdir: ROOT) or abort("rake compile: the compiler did not build")
    end
    puts format("%.1fs", took)
    FileUtils.mkdir_p(COMPILED_CACHE)
    Dir.children(Ze0::Paths.cache).each do |name|
      from = File.join(Ze0::Paths.cache, name)
      to = File.join(COMPILED_CACHE, name)
      next if name.start_with?("unit-") || !File.file?(from) || File.exist?(to)

      File.link(from, to)
    end
  end

  # One column a rung, one row a phase, in the order a build runs them.
  # A rung built both ways ends with the compiled build's whole against
  # ruby's.
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

  # The same table, under a line that says when and at what revision.
  def write!(rows, runs)
    at = `git -C #{ROOT} rev-parse --short HEAD`.strip
    FileUtils.mkdir_p(File.dirname(RESULTS))
    File.open(RESULTS, "w") do |f|
      f.puts "# ze0 compile cost, the median of #{runs} run(s) at #{at}, runtime warm, #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}"
      table(rows, f)
    end
    warn "wrote #{RESULTS}"
  end
end

desc "How long does ze0 take to compile, and where? rake 'compile[--write]'"
task(:compile, [:filters]) { |_, args| CompileBench.run(args[:filters].to_s.split) }
