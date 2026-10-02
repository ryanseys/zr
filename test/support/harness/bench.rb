# frozen_string_literal: true

require "benchmark"
require "etc"
require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "answer"
require_relative "child"
require_relative "runner"
require_relative "../../../tool/lib/zr/dev/host"

module Zr
  module Harness
    # `zr-dev bench`: the run time of the binary that zr builds, compared
    # with the run time of ruby, which made the recording.
    #
    # `benchmark/` contains whole programs, as `test/programs` does: a `.rb`
    # file with ruby's output in `<name>.out` next to it. This class only
    # measures time and makes the comparison columns.
    #
    # **The output is checked before a time is kept.** The speed of a
    # wrong output has no meaning. A codegen step must never make the
    # output wrong to make a program faster.
    #
    # All runs are serial. The test tiers run one worker for each core,
    # because they check only the output. A time measured while other
    # compiles run is not correct.
    class Bench
      # Long enough for the slowest program, and short enough that a
      # program in an infinite loop does not stop the suite.
      LIMIT = 300

      # Five runs, and the median is kept. This is sufficient to ignore
      # one scheduling delay, and the suite takes only minutes.
      # `bm_startup` prints one line: its time is the process start-up,
      # which is part of every other time. Read the other times with this
      # in mind.
      RUNS = 5

      # Where a report goes. A run of all benchmarks goes to
      # `benchmark/results/<stamp>-<revision>.txt`: the UTC time of the
      # run (so the files sort in order) and the measured commit. It is
      # committed with the code, so a later run can compare with it by
      # hash. A run of some benchmarks goes under `tmp`, because a
      # partial report does not tell about the others.
      RESULTS = "benchmark/results"
      SCRATCH = "tmp/bench"
      LATEST = "latest.txt"

      # `build` is the compile time, in seconds. `zr`, `ruby` and `yjit`
      # are each a `Benchmark::Tms` of the median run: the wall clock in
      # `real`, and the child's user and system time in `utime` and
      # `stime`. A result with no time has a reason in `why`.
      class Row
        attr_reader :rb, :bucket, :why, :build, :zr, :ruby, :yjit

        def initialize(rb, bucket, why = nil, build: nil, zr: nil, ruby: nil, yjit: nil)
          @rb = rb
          @bucket = bucket
          @why = why
          @build = build
          @zr = zr
          @ruby = ruby
          @yjit = yjit
        end

        def name = File.basename(rb, ".rb")
        def timed? = bucket == :timed

        # The CPU time of the binary. Unlike the wall clock, it does not
        # include other work on the machine.
        def cpu = zr.total

        # zr's wall clock divided by the wall clock of `other` (a Tms or nil).
        def against(other) = timed? && other && other.real.positive? ? zr.real / other.real : nil
      end

      def initialize(root, runs: RUNS, show: 10, target: Target.default)
        @root = root
        @runs = runs
        @show = show
        @runner = Runner.new(root, target, compiler: "cranelift")
      end

      # All programs under `benchmark/`, or the programs that match a filter.
      def matching(filters)
        rows = Dir[File.join(@root, "benchmark/*.rb")].sort
        @whole = filters.empty?
        return rows if @whole

        rows.select { |rb| filters.any? { |f| File.basename(rb).include?(f) } }
      end

      # Runs one child with a time limit, and a memory limit when
      # `megabytes` is given. A timed run has no memory limit: the memory
      # sampler starts `ps` five times a second, and its time would count
      # as the program's time.
      def bounded(argv, cwd, stdin, megabytes, env)
        Child.run(argv, cwd: cwd, stdin: stdin, env: env, seconds: LIMIT, megabytes: megabytes).first
      end

      def run(cases, io = $stdout)
        io.sync = true
        Dir.mktmpdir("zr-bench-") do |work|
          cases.map.with_index do |rb, n|
            io.print format("[%d/%d] %s ... ", n + 1, cases.size, File.basename(rb, ".rb"))
            row = one(rb, work)
            io.puts row.timed? ? format("%.3fs", row.zr.real) : "#{row.bucket}: #{row.why}"
            row
          end
        end
      end

      # Builds the program, checks its output, then times zr, ruby and yjit.
      def one(rb, work)
        recorded = Answer.beside(rb)
        return Row.new(rb, :skipped, "no recording") unless recorded

        cwd = @root
        rel = rb.delete_prefix("#{cwd}/")
        bin = File.join(work, "p")
        File.delete(bin) if File.exist?(bin)

        build, out = clocked("build") { bounded(@runner.build_argv(rel, bin), cwd, nil, Child::BUILD_MB, @runner.build_env) }
        return Row.new(rb, :refused, first_line(out)) if out.code == 3
        return Row.new(rb, :backend, out.code == :timeout ? "the build ran past #{LIMIT}s" : first_line(out)) unless out.code == 0

        want = Normalize.answer(recorded, rb, cwd)
        argv, run_env = @runner.run(bin, [], {})
        got, wrong = medians("zr", argv, cwd, nil, run_env, rb, want)
        return Row.new(rb, :diverged, wrong) if wrong

        plain, = medians("ruby", [RbConfig.ruby, rel], cwd, nil, {}, rb, nil)
        # A threshold of one call: YJIT then compiles a toplevel loop too,
        # which runs once (fannkuch, sieve, matmul).
        jit, = medians("yjit", [RbConfig.ruby, "--yjit", "--yjit-call-threshold=1", rel], cwd, nil, {}, rb, nil)
        Row.new(rb, :timed, build: build.real, zr: got, ruby: plain, yjit: jit)
      end

      # Returns the median run of `@runs` by wall clock, as a Tms. When
      # `want` is given, also returns the difference in the first run's
      # output. Later runs are not checked. The program tests find a program
      # whose output changes from run to run.
      def medians(label, argv, cwd, stdin, env, rb, want)
        times = []
        @runs.times do |n|
          took, out = clocked(label) { bounded(argv, cwd, stdin, nil, env) }
          return [nil, "ran past #{LIMIT}s"] if out.code == :timeout

          if n.zero? && want
            got = Normalize.answer(out, rb, cwd)
            return [nil, want.apart_from(got)] if got != want
          elsif want.nil? && out.code != 0
            # ruby could not run it (for example, no `--yjit`, or a
            # missing gem). The column stays empty; the zr time stays.
            return [nil, nil]
          end
          times << took
        end
        [times.sort_by(&:real)[@runs / 2], nil]
      end

      # Returns the time of the block, as a `Benchmark::Tms`, and the
      # block's result. `Benchmark.measure` reads the wall clock and the
      # user and system time of the children that the block waited for.
      # There is only one child, because nothing else forks at that time.
      # The returned Tms has these times as `utime`, `stime` and `real`,
      # so it prints and adds as a usual Tms.
      def clocked(label)
        answer = nil
        took = Benchmark.measure { answer = yield }
        [Benchmark::Tms.new(took.cutime, took.cstime, 0.0, 0.0, took.real, label), answer]
      end

      def first_line(out)
        text = out.stderr.empty? ? out.stdout : out.stderr
        (text.lines.first&.strip || "(no message)").delete_prefix("zr: ")
      end

      # Prints the table and the two geometric means. Returns true when
      # no program failed. A slow program is a result; a wrong output
      # is a failure.
      def report(rows, io = $stdout)
        io.puts
        io.puts format("%-26s %8s %8s %8s %8s %8s %9s %9s", "program", "build", "zr", "cpu", "ruby", "yjit", "vs ruby", "vs yjit")
        rows.each { |r| io.puts line(r) }
        timed = rows.select(&:timed?)
        io.puts
        io.puts format("%d timed, %d not", timed.size, rows.size - timed.size)
        %i[ruby yjit].each do |what|
          ratios = timed.filter_map { |r| r.against(r.public_send(what)) }
          next if ratios.empty?

          io.puts format("zr is %.2fx of %s, geometric mean over %d program(s)", geomean(ratios), what, ratios.size)
        end
        io.puts "  wrote #{save(rows)}"
        rows.none? { |r| %i[diverged backend].include?(r.bucket) }
      end

      def line(row)
        return format("%-26s %8.1f %8s %8s %8s %8s %9s %9s", row.name, row.build || 0, row.bucket, "", "", "", "", "") unless row.timed?

        format("%-26s %8.1f %8.3f %8.3f %8s %8s %9s %9s", row.name, row.build, row.zr.real, row.cpu,
               seconds(row.ruby), seconds(row.yjit), times(row.against(row.ruby)), times(row.against(row.yjit)))
      end

      # A Tms's wall clock, or a dash for the column ruby left empty.
      def seconds(t) = t ? format("%.3f", t.real) : "-"
      def times(r) = r ? format("%.2fx", r) : "-"

      # The geometric mean, because these are ratios. With the arithmetic
      # mean, one slow program would control the result of the suite.
      def geomean(values) = Math.exp(values.sum { |v| Math.log(v) } / values.size)

      # Writes the report in the benchmark gem's format: for each program,
      # its name, `Benchmark::CAPTION`, and one `Tms#format` line for each
      # runner. A run of all benchmarks goes to
      # `benchmark/results/<stamp>-<revision>.txt` (with `-dirty` when the
      # tree has uncommitted changes). A partial run goes to
      # `tmp/bench/latest.txt`.
      def save(rows)
        taken = Time.now.utc
        path = @whole ? File.join(@root, RESULTS, "#{taken.strftime("%Y%m%d-%H%M")}-#{revision}.txt") : File.join(@root, SCRATCH, LATEST)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text(rows, taken))
        path
      end

      # The short hash of HEAD, with `-dirty` when the tree has changes
      # under `lib`, `runtime` or `benchmark`. `unknown` outside git.
      def revision
        rev = Dev.revision(dir: @root) or return "unknown"

        changed = Dev.git("status", "--porcelain", "--", "lib", "runtime", "benchmark", dir: @root).to_s.lines.reject { |l| l.include?(RESULTS) }
        changed.empty? ? rev : "#{rev}-dirty"
      end

      # The reports under `benchmark/results/`, newest last. Each file
      # name starts with its time, so they sort by time.
      def self.results(root) = Dir[File.join(root, RESULTS, "*.txt")].sort

      # The report for the revision hash `rev`, or nil.
      def self.result_of(root, rev) = Dir[File.join(root, RESULTS, "*-#{rev}.txt")].max

      LABEL = "%-8n"

      def text(rows, taken = Time.now.utc)
        lines = ["# zr bench, the median of #{@runs} run(s) at #{revision}, #{taken.strftime("%Y-%m-%d %H:%M UTC")}"]
        rows.each do |r|
          lines << ""
          unless r.timed?
            lines << "#{r.name}  #{r.bucket}: #{r.why}"
            next
          end

          lines << format("%s  built in %.1f s", r.name, r.build)
          lines << (" " * 8) + Benchmark::CAPTION.chomp
          %i[zr ruby yjit].each do |what|
            t = r.public_send(what) or next
            lines << t.format(LABEL + Benchmark::FORMAT).chomp
          end
        end
        "#{lines.join("\n")}\n"
      end

      # `{ "bm_fib" => 0.1438, ... }`: the wall clock on the `label` line
      # for each program, in a report that `save` wrote.
      def self.reals(text, label = "zr")
        program = nil
        text.each_line.with_object({}) do |line, reals|
          if (m = line.match(/\A(\S+)\s+[\d.]+\s.*\(\s*([\d.]+)\)\s*\z/))
            reals[program] = Float(m[2]) if program && m[1] == label
          elsif line.match?(/\A[^\s#]/)
            program = line.split.first
          end
        end
      end
    end
  end
end
