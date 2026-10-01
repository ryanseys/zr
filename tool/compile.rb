# frozen_string_literal: true

require "benchmark"
require "fileutils"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Measures how long zr takes to compile, and the time of each phase.
    #
    #   zr-dev compile                   every program, three runs each
    #   zr-dev compile --runs 5          five runs each
    #   zr-dev compile hello bundler     the programs whose name contains a word
    #   zr-dev compile --write           write the table to tmp/bench/compile.txt
    #   zr-dev compile --zr              also time the compiled compiler
    #   zr-dev compile --zr --commit     write a baseline to benchmark/results/compile/
    #   zr-dev compile --zr --check      fail if slower than the newest baseline
    #   zr-dev compile --profile eval    each function's passes and assembly
    #
    # `zr-dev bench` times what a binary does; this tool times how long it
    # takes to make one. The programs in `benchmark/compile` have require
    # graphs of increasing size, from no require to all of bundler. Each
    # row is one phase of `Zr::Timing.phase`, so you can see which phase a change
    # affects.
    #
    # The runtime is already built. The first run of each program is a
    # warmup and is discarded. The tool keeps the run with the median total.
    # Thus it measures only the compile of the program itself.
    #
    # `--zr` first uses ruby to build the compiler from the current tree.
    # Then it times each program with both compilers. The compiled
    # compiler's column has a `*`, and a last row gives its time divided by
    # ruby's. The compiled compiler gets its own cache, with links to the
    # runtime that ruby built. This is correct because a runtime's key is
    # the digest of its sources, and a compiler built from the same sources
    # makes the same bytes (`zr-dev stage 1`). A compiled compiler from a
    # different tree would write its output under this tree's digest. Thus
    # the tool always builds its own compiled compiler.
    class Compile < Command
      summary "How long does zr take to compile, and where? --check guards a baseline"
      usage "[--runs N] [--write] [--zr [--commit | --check]] [filter...]"

      DIR = Dev.path("benchmark/compile")
      # Where `--write` puts the table: under `tmp`, next to the report of
      # `zr-dev bench`. It is not committed.
      RESULTS = Dev.path("tmp/bench/compile.txt")
      # Where `--commit` puts a baseline. A subdirectory, because the glob of
      # `zr-dev bench --check` (Zr::Harness::Bench.results) reads the files
      # directly under `benchmark/results/`.
      BASELINES = Dev.path("benchmark/results/compile")
      WHOLE = "the whole build"
      RATIO = "compiled / ruby"
      # `--check` fails when the whole build is this much slower and at least
      # this many seconds slower, or when the ratio rises by this much. A
      # phase is only reported.
      MOVED = 0.08
      SLOWER = 0.5
      RATIO_MOVED = 0.05
      PHASE_MOVED = 0.15
      PHASE_SLOWER = 0.25
      RUNS = 3
      # The compiled compiler and its cache, under `tmp`.
      COMPILED = Dev.path("tmp/compile/zr")
      COMPILED_CACHE = Dev.path("tmp/compile/cache")

      # The line `Zr::Timing.phase` writes: a label padded to 40, then the seconds.
      LINE = /\Azr: (.+?)\s+([\d.]+)s(?:\s|\z)/

      def options(o)
        o.on("--runs N", Integer, "builds of each program, after one warmup (default: #{RUNS})") { |v| @runs = v }
        o.on("--write", "write the table to tmp/bench/compile.txt") { @write = true }
        o.on("--zr", "also time the compiled compiler") { @compiled = true }
        o.on("--commit", "write a baseline to benchmark/results/compile/ (needs --zr)") { @commit = true }
        o.on("--check", "fail if slower than the newest baseline (needs --zr)") { @check = true }
        o.on("--profile OBJECT", %w[runtime eval], "time each function of the runtime or eval support object") { |v| @profile = v }
      end

      def run(argv)
        return profile(@profile) if @profile

        require "benchmark"
        require_relative "../lib/zr/cli"
        runs = @runs || RUNS
        fail!("--runs takes a count of one or more") if runs < 1
        fail!("--commit and --check need --zr") if (@commit || @check) && !@compiled

        rungs = Dir[File.join(DIR, "*.rb")].sort
        rungs = rungs.select { |rb| argv.any? { |f| File.basename(rb).include?(f) } } unless argv.empty?
        fail!("no rung matches #{argv.inspect}") if rungs.empty?

        compiled!(rungs.first) if @compiled
        rows = rungs.each_with_object({}) do |rb, h|
          name = File.basename(rb, ".rb")
          h[name] = median(rb, runs)
          h["#{name}*"] = median(rb, runs, compiled: true) if @compiled
        end
        table(rows)
        write!(rows, runs, RESULTS) if @write
        write!(rows, runs, baseline_path) if @commit
        @check ? no_regression?(read(File.read(newest_baseline)), rows) : true
      end

      # Lowers the runtime or eval support object, then runs the passes and
      # the assembly of each function in this process, one at a time, and
      # prints the phases, the sums and the slowest functions. A build runs
      # the same work in workers, so this shows the work, not the wall time.
      # Writes every function to tmp/bench/profile-<object>.tsv.
      def profile(object)
        require_relative "../lib/zr/runtime"
        require_relative "../lib/zr/native/build"
        target = Target.default
        functions, data, raw =
          if object == "runtime"
            rt = Runtime.for(target)
            timed("runtime lowered") { [rt.functions, rt.data, rt.raw] }
          else
            support = EvalSupport.for(target)
            timed("eval support lowered") { [support.functions, support.data, []] }
          end
        puts "#{functions.size} functions, #{data.size} data"
        timed("inlined, for the whole unit") { IR::Passes.inline(functions) }
        emitter = Native::Build.backend(target)
        defined = (functions.map(&:name) + data.map(&:name) + raw).to_set
        rows = timed("prepared and assembled, one at a time") do
          functions.map do |f|
            insts = f.blocks.sum { |b| b.insts.size }
            blocks = f.blocks.size
            prepared = Benchmark.realtime { IR::Passes.prepare(f) }
            assembled = Benchmark.realtime { emitter.assemble(f, defined) }
            [f.name, blocks, insts, prepared, assembled]
          end
        end
        FileUtils.mkdir_p(File.dirname(RESULTS))
        path = Dev.path("tmp/bench/profile-#{object}.tsv")
        File.write(path, (["name\tblocks\tinsts\tprepare_s\tassemble_s"] + rows.map { |r| r.join("\t") }).join("\n") << "\n")
        prepared = rows.sum { |r| r[3] }
        assembled = rows.sum { |r| r[4] }
        puts format("passes %.1fs, assembly %.1fs, over %d functions", prepared, assembled, rows.size)
        slowest = rows.max_by(20) { |r| r[3] + r[4] }
        puts "the 20 slowest (blocks, instructions, passes s, assembly s):"
        slowest.each { |r| puts format("  %-60s %6d %7d %7.2f %7.2f", r[0][0, 60], *r[1..]) }
        puts format("the 20 slowest take %.0f%% of the time; all rows in %s",
                    100 * slowest.sum { |r| r[3] + r[4] } / (prepared + assembled), Dev.rel(path))
      end

      def timed(label)
        result = nil
        took = Benchmark.realtime { result = yield }
        puts format("%-40s %8.2fs", label, took)
        result
      end

      # Runs one build and returns its phases as `{label => seconds}`. The
      # entry "the whole build" is measured here, not added from the phases,
      # because the phases do not include the process start.
      def build(rb, out, compiled: false)
        # With the GC limits set here, `zr` does not restart itself.
        env = { "ZR_TIMING" => "1", **GcTuning::GC_ENV }
        command = [Dev.ruby, Dev.path("exe/zr")]
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
        fail!("#{rb} did not build\n#{lines}") unless status.success?

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
        FileUtils.mkdir_p(File.dirname(COMPILED))
        took = Benchmark.realtime do
          system(GcTuning::GC_ENV, Dev.ruby, Dev.path("exe/zr"), "build", Dev.path("exe/zr"),
                 "-o", COMPILED, out: File::NULL, chdir: ROOT) or fail!("the compiler did not build")
        end
        puts format("%.1fs", took)
        FileUtils.mkdir_p(COMPILED_CACHE)
        Dir.children(Paths.cache).each do |name|
          from = File.join(Paths.cache, name)
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

      # Writes the same table to `path`, under a line that gives the time,
      # the revision and the host. `check` compares only the ratio row when
      # the host differs.
      def write!(rows, runs, path)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "w") do |f|
          f.puts "# zr compile cost, the median of #{runs} run(s) at #{revision}, runtime warm, #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}"
          f.puts "# host: #{host}"
          table(rows, f)
        end
        warn "wrote #{Dev.rel(path)}"
      end

      def revision = IO.popen(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], &:read).strip

      def host
        require "etc"
        "#{RbConfig::CONFIG["host_cpu"]}-#{RbConfig::CONFIG["host_os"]} cpus=#{Etc.nprocessors} jobs=#{ENV.fetch("ZR_JOBS", "-")}"
      end

      def baseline_path = File.join(BASELINES, "#{Time.now.utc.strftime("%Y%m%d-%H%M")}-#{revision}.txt")

      def newest_baseline
        Dir[File.join(BASELINES, "*.txt")].max || fail!("no baseline under #{Dev.rel(BASELINES)}; run zr-dev compile --zr --commit")
      end

      # Reads a table that `write!` wrote: `{rung => {phase => seconds}}`,
      # plus the ratio row under RATIO and the host under :host.
      def read(text)
        lines = text.lines.map(&:chomp)
        host = lines.find { |l| l.start_with?("# host: ") }&.delete_prefix("# host: ")
        body = lines.reject { |l| l.start_with?("#") || l.empty? }
        names = body.shift.split.drop(1)
        rows = names.to_h { |n| [n, {}] }
        body.each do |line|
          cells = line.split
          label = line[/\A.+?(?=\s{2,}[-\d])/].to_s.strip
          cells.last(names.size).each_with_index do |cell, i|
            next if cell == "-"

            rows[names[i]][label] = cell.delete_suffix("x").to_f
          end
        end
        rows.merge(host: host)
      end

      # Compares a run with a baseline. Only a slower build fails. On another
      # host only the ratio row is compared, because it does not depend on the
      # speed of the machine.
      def no_regression?(was, now)
        same_host = was[:host] == host
        failed = []
        now.each do |name, phases|
          before = was[name] or next
          phases.each do |label, secs|
            old = before[label] or next
            next unless same_host

            moved = (secs - old) / old
            line = format("%-9s %-40s %8.3f -> %8.3f  %+.0f%%", name, label, old, secs, moved * 100)
            if label == WHOLE
              failed << line if moved >= MOVED && secs - old >= SLOWER
              puts "#{line}  (faster; re-baseline)" if moved <= -MOVED
            elsif moved >= PHASE_MOVED && secs - old >= PHASE_SLOWER
              puts "#{line}  (phase; noted)"
            end
          end
        end
        ratios(now).each do |name, ratio|
          old = was.dig(name, RATIO) or next
          line = format("%-9s %-40s %8.2fx -> %7.2fx", name, RATIO, old, ratio)
          failed << line if ratio - old >= RATIO_MOVED
        end
        puts "compile --check: #{same_host ? "same host" : "another host, only #{RATIO} compared"}"
        failed.each { |line| puts line }
        puts(failed.empty? ? "compile --check: no regression" : "compile --check: #{failed.size} regression(s)")
        failed.empty?
      end

      def ratios(rows)
        rows.filter_map do |name, p|
          next unless name.end_with?("*") && (ruby = rows[name.delete_suffix("*")])

          [name, p.fetch(WHOLE) / ruby.fetch(WHOLE)]
        end
      end
    end
  end
end
